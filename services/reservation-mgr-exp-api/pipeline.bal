import reservation_mgr_exp_api.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import ballerinax/redis;

import aroya/integration_commons as commons;

// The request pipeline: route -> circuit breaker -> call with retry -> audit / error path.
// Mule equivalents: reservation-mgr-experience-api-main, the v1/v2 implementation
// sub-flows, circuit-breaker.xml and Global_Error_Handler.

final http:Client commonProcClient = check commons:newDownstreamClient(commonProc);
// Writes: their own, longer time limit, and never repeated (see `writeTimeoutSeconds`).
final http:Client commonProcWriteClient = check commons:newDownstreamClient({
    url: commonProc.url,
    timeoutSeconds: writeTimeoutSeconds,
    http2: commonProc.http2,
    tlsValidation: commonProc.tlsValidation,
    caCertPath: commonProc.caCertPath
});
final http:Client dbSysClient = check commons:newDownstreamClient(dbSysApi);
final redis:Client? breakerStore = check commons:newRedisClient(breakerRedis, "reservation-mgr-exp-api");
final commons:CircuitBreaker breaker = new (circuitBreaker, breakerStore, string `intg:exp-api:${env}`);
// Kafka audit and error records as the Mule sub-flows wrote them (off unless switched on).
// The Mule application sent no error e-mail, so none is sent here.
final string kafkaProducer = core:producerTargetOf(env, deploymentTarget);
final commons:RecordPublisher records = new (core:recordSettingsOf(audit, kafkaProducers, kafkaProducer));
final map<string> & readonly operations = core:normalizeKeys(operationMapping);
final map<string> & readonly staticOperations = core:normalizeKeys(staticOperationMapping);
final map<string> & readonly targets = core:normalizeKeys(routeTargets);
final http:Client seawareSysClient = check commons:newDownstreamClient(flightPromotion.sysApi);

# Everything a request needs once its body is read. Read-only, so the async path can hand it
# to a new strand.
#
# + correlationId - Correlation id
# + version - `v1` or `v2`
# + endpoint - Inbound path, for error mapping and e-mails
# + body - Raw request body
# + payload - Body as JSON (audit records)
# + operationType - query, mutation or subscription
# + operationName - Name after the operation type
# + rootField - GraphQL root field
# + headers - Headers for the downstream call
# + authorization - The caller's Authorization header (only its fingerprint goes into records)
# + forwardedFor - Header x-forwarded-for
# + targetHeader - Header x-target-system
type RequestContext record {|
    string correlationId;
    string version;
    string endpoint;
    byte[] body;
    json payload;
    string operationType;
    string operationName;
    string? rootField;
    map<string> headers;
    string authorization;
    string forwardedFor;
    string targetHeader;
|};

# The outcome of a downstream call.
#
# + ok - `true` for a 2xx answer
# + status - HTTP status to return
# + body - Body to return
# + errorType - Error type when not ok
# + extraHeaders - Headers to add (Retry-After)
# + raw - The downstream answer exactly as it arrived, set when nothing here needs it as JSON
type Outcome record {|
    boolean ok;
    int status;
    json body;
    string errorType = "";
    map<string> extraHeaders = {};
    byte[]? raw = ();
|};

isolated function handleIntegrationTask(http:Caller caller, http:Request request, string version) returns http:Response {
    RequestContext & readonly ctx = contextOf(caller, request, version);
    if core:isIntrospection(queryOf(ctx.payload)) {
        return refuseIntrospection(request, ctx);
    }
    log:printInfo("EXP request started", correlationId = ctx.correlationId, operationName = ctx.operationName,
            rootField = ctx.rootField ?: "UNKNOWN", version = version,
            clientChannel = commons:headerOf(request, "client_channel") ?: "", clientPlatform = commons:headerOf(request,
                    "client_platform") ?: "");

    if core:isAsyncRequest(commons:headerOf(request, "client_asyncFlag")) {
        return acceptAsync(ctx);
    }
    // The answer is only read here to audit it; with auditing off it goes back as it arrived.
    Outcome outcome = processRequest(ctx, !audit.auditEnabled);
    return respond(ctx, outcome);
}

isolated function contextOf(http:Caller caller, http:Request request, string version) returns RequestContext & readonly {
    string correlationId = commons:correlationIdOf(request);
    byte[]|http:ClientError raw = request.getBinaryPayload();
    byte[] body = raw is byte[] ? raw : [];
    json payload = jsonOf(body);
    string query = queryOf(payload);
    string operationType = commons:operationTypeOf(query);
    string operationName = commons:operationNameOf(query);
    string? rootField = commons:rootFieldOf(query);
    map<string> headers = commons:forwardHeaders(request, correlationId, {
                                                                             "client_version": version,
                                                                             "x-operation-type": operationType,
                                                                             "x-operation-name": operationName,
                                                                             "x-client-ip": commons:clientIpOf(caller),
                                                                             "X-Seaware-Authorization": commons:headerOf(request, "X-Seaware-Authorization")
                                                                         });
    RequestContext ctx = {
        correlationId,
        version,
        endpoint: pathOnly(request.rawPath),
        body,
        payload,
        operationType,
        operationName,
        rootField,
        headers,
        authorization: commons:headerOf(request, "Authorization") ?: commons:headerOf(request, "authorization") ?: "",
        forwardedFor: commons:headerOf(request, "x-forwarded-for") ?: "",
        targetHeader: commons:headerOf(request, "x-target-system") ?: ""
    };
    return ctx.cloneReadOnly();
}

# Routes and calls the downstream; never panics, every failure is an Outcome.
isolated function processRequest(RequestContext & readonly ctx, boolean asReceived = false) returns Outcome {
    if flightPromotion.enabled && ctx.rootField == flightPromotion.rootField {
        return flightPromotions(ctx);
    }
    core:Route|core:RoutingError route = core:resolveRoute(ctx.rootField, operations, staticOperations, targets);
    if route is core:RoutingError {
        return failure(ctx, route.errorType, route.message);
    }
    log:printInfo("Requesting process API", correlationId = ctx.correlationId, targetApi = route.targetApi);
    return callCommonProc(ctx, route.path, route.rootField, asReceived);
}

# Calls reservation-common-proc-api behind the circuit breaker, with retry for operations
# that may be retried.
isolated function callCommonProc(RequestContext & readonly ctx, string path, string? operation,
        boolean asReceived = false) returns Outcome {
    if breaker.isOpen(ctx.correlationId) {
        commons:ErrorEnvelope envelope = breaker.openEnvelope(ctx.correlationId);
        return {
            ok: false,
            status: 503,
            body: envelope.toJson(),
            errorType: commons:CIRCUIT_OPEN,
            extraHeaders: {"Retry-After": breaker.retryAfterSeconds().toString()}
        };
    }
    boolean write = core:isWrite(queryOf(ctx.payload));
    http:Client target = write ? commonProcWriteClient : commonProcClient;
    int maxAttempts = retryPolicy.count + 1;
    Outcome last = failure(ctx, commons:CONNECTIVITY, "Downstream was not called");
    foreach int attempt in 1 ... maxAttempts {
        http:Response|http:ClientError reply = target->post(path, ctx.body, ctx.headers);
        if reply is http:Response && reply.statusCode < 400 {
            breaker.recordSuccess(ctx.correlationId);
            byte[]? raw = asReceived ? bytesOfJson(reply) : ();
            if raw is byte[] {
                return {ok: true, status: reply.statusCode, body: (), raw};
            }
            return {ok: true, status: reply.statusCode, body: responseJson(reply)};
        }
        string errorType;
        if reply is http:Response {
            errorType = commons:errorTypeOfStatus(reply.statusCode);
            json downstream = responseJson(reply);
            commons:ErrorEnvelope envelope = commons:envelopeOf(errorType, messageOf(downstream, errorType),
                    ctx.correlationId, reply.statusCode, downstream);
            // Mule `error.target_error` (default true): the downstream body is returned as-is.
            last = {ok: false, status: reply.statusCode, body: downstream == () ? envelope.toJson() : downstream, errorType};
        } else {
            errorType = commons:errorTypeOfClientError(reply);
            last = failure(ctx, errorType, reply.message());
        }
        breaker.recordFailure(errorType, ctx.correlationId);
        if write || !commons:isRetryable(retryPolicy, operation, errorType, attempt) {
            break;
        }
        log:printWarn("Retrying process API call", correlationId = ctx.correlationId, attempt = attempt,
                errorType = errorType);
        commons:waitBeforeRetry(retryPolicy, attempt);
    }
    return last;
}

isolated function failure(RequestContext & readonly ctx, string errorType, string message) returns Outcome {
    commons:ErrorEnvelope envelope = commons:envelopeOf(errorType, message, ctx.correlationId);
    return {ok: false, status: envelope.statusCode, body: envelope.toJson(), errorType};
}

# Turns an outcome into the response; on failure applies error mapping and notifies once.
isolated function respond(RequestContext & readonly ctx, Outcome outcome) returns http:Response {
    http:Response response = new;
    response.setHeader(commons:CORRELATION_HEADER, ctx.correlationId);
    foreach [string, string] [name, value] in outcome.extraHeaders.entries() {
        response.setHeader(name, value);
    }
    if outcome.ok {
        response.statusCode = outcome.status;
        byte[]? raw = outcome.raw;
        if raw is byte[] {
            // Reading a large list (the voyages answer is about 1.5 MB) into JSON and writing it
            // out again was most of this service's time, so the bytes go back untouched.
            response.setBinaryPayload(raw, "application/json");
        } else {
            response.setJsonPayload(outcome.body);
        }
        log:printInfo("EXP request completed", correlationId = ctx.correlationId, operationName = ctx.operationName,
                status = outcome.status);
        if raw is () {
            publishAudit(ctx, outcome.body);
        }
        return response;
    }
    json body = mappedErrorBody(ctx, outcome);
    response.statusCode = outcome.status;
    response.setJsonPayload(body);
    log:printError("EXP request failed", correlationId = ctx.correlationId, operationName = ctx.operationName,
            status = outcome.status, errorType = outcome.errorType);
    // One error record per request (Mule kafkaAttempted guard). Mule sent no error e-mail.
    publishError(ctx, body, outcome.status);
    return response;
}

# The facts of a request for its Kafka record; target and target URL from its route (Mule
# vars.targetApiName / vars.targetUrl).
isolated function factsOf(RequestContext & readonly ctx) returns core:RecordFacts {
    core:Route|core:RoutingError route = core:resolveRoute(ctx.rootField, operations, staticOperations, targets);
    return {
        correlationId: ctx.correlationId,
        operationName: ctx.operationName,
        operationType: ctx.operationType,
        clientIp: ctx.forwardedFor,
        authorization: ctx.authorization,
        targetSystem: route is core:Route ? route.targetApi : ctx.targetHeader,
        endpointUrl: route is core:Route ? commonProc.url + route.path : ctx.endpoint,
        requestPayload: ctx.payload
    };
}

isolated function publishAudit(RequestContext & readonly ctx, json response) {
    if !records.auditOn() {
        return;
    }
    core:RecordFacts facts = factsOf(ctx);
    if core:recordSkipped(facts, response) {
        log:printInfo("Kafka audit skipped (query operation or empty payload)", correlationId = ctx.correlationId);
        return;
    }
    map<json> & readonly rec = core:auditRecordOf(facts, response, time:utcToString(time:utcNow())).cloneReadOnly();
    future<()> _ = start records.audit(ctx.correlationId, rec);
}

isolated function publishError(RequestContext & readonly ctx, json body, int status) {
    if !records.errorOn() {
        return;
    }
    core:RecordFacts facts = factsOf(ctx);
    if core:recordSkipped(facts, body) {
        log:printInfo("Kafka error record skipped (query operation or empty payload)", correlationId = ctx.correlationId);
        return;
    }
    map<json> & readonly rec = core:errorRecordOf(facts, body, status, time:utcToString(time:utcNow())).cloneReadOnly();
    future<()> _ = start records.failure(ctx.correlationId, rec);
}

# Mule: a schema query is refused before anything else (INVALID:GRAPHQL_QUERY, 400). Its error
# record only knows what the caller's headers say, as in Mule where the variables were not set yet.
isolated function refuseIntrospection(http:Request request, RequestContext & readonly ctx) returns http:Response {
    json body = core:introspectionRefusalOf(time:utcToString(time:utcNow()));
    log:printWarn("Introspection query refused", correlationId = ctx.correlationId);
    if records.errorOn() {
        core:RecordFacts facts = {
            correlationId: commons:headerOf(request, commons:CORRELATION_HEADER) ?: "",
            operationName: commons:headerOf(request, "x-operation-name") ?: "",
            operationType: commons:headerOf(request, "x-operation-type") ?: "",
            clientIp: ctx.forwardedFor,
            authorization: ctx.authorization,
            targetSystem: ctx.targetHeader,
            endpointUrl: "",
            requestPayload: ctx.payload
        };
        if !core:recordSkipped(facts, body) {
            map<json> & readonly rec = core:errorRecordOf(facts, body, 400, time:utcToString(time:utcNow())).cloneReadOnly();
            future<()> _ = start records.failure(ctx.correlationId, rec);
        }
    }
    http:Response response = new;
    response.statusCode = 400;
    response.setJsonPayload(body);
    return response;
}

# Mule dbErrorMappingEnabled: a row in cs_error_mapping can replace the error body. Any
# problem with the lookup keeps the original body.
isolated function mappedErrorBody(RequestContext & readonly ctx, Outcome outcome) returns json {
    if !errorMapping.enabled {
        return outcome.body;
    }
    log:printInfo("Looking up error mapping", correlationId = ctx.correlationId, endpoint = ctx.endpoint,
            code = outcome.status, errorType = outcome.errorType);
    json lookup = core:errorMappingBody(errorMapping.connectionKey, errorMapping.query, ctx.endpoint, outcome.status,
            outcome.errorType);
    json|http:ClientError answer = dbSysClient->post(dbSysApiPath, lookup, {correlationId: ctx.correlationId});
    if answer is http:ClientError {
        log:printWarn("Error mapping lookup failed; keeping the original error", correlationId = ctx.correlationId,
                'error = answer);
        return outcome.body;
    }
    json mapped = core:mappedErrorBodyOf(answer, outcome.errorType, outcome.status, ctx.correlationId);
    return mapped == () ? outcome.body : mapped;
}

// ---------- flightpromotion (through seaware-sys-api) ----------

isolated function flightPromotions(RequestContext & readonly ctx) returns Outcome {
    core:FlightPromotionRequest req = core:parseFlightPromotionRequest(queryOf(ctx.payload));
    map<string> headers = {"Content-Type": "application/json", correlationId: ctx.correlationId};
    string? auth = ctx.headers["Authorization"];
    if auth is string {
        headers["Authorization"] = auth;
    }
    json|Outcome promotions = sysCall(ctx, core:availablePromotionsQuery(req), headers);
    if promotions is Outcome {
        return promotions;
    }
    [string, json][] priced = [];
    foreach string promoKey in core:promotionKeysOf(promotions) {
        json|Outcome answer = sysCall(ctx, core:priceWithPromotionQuery(req, promoKey), headers);
        if answer is Outcome {
            return answer;
        }
        priced.push([promoKey, answer]);
    }
    log:printInfo("flightpromotion priced", correlationId = ctx.correlationId, promotions = priced.length());
    return {ok: true, status: 200, body: core:transferPromotionsOf(priced, req)};
}

isolated function sysCall(RequestContext & readonly ctx, json body, map<string> headers) returns json|Outcome {
    http:Response|http:ClientError reply = seawareSysClient->post(flightPromotion.path, body, headers);
    if reply is http:ClientError {
        return failure(ctx, commons:errorTypeOfClientError(reply), reply.message());
    }
    if reply.statusCode >= 400 {
        json downstream = responseJson(reply);
        string errorType = commons:errorTypeOfStatus(reply.statusCode);
        Outcome failed = {
            ok: false,
            status: reply.statusCode,
            body: downstream == () ? commons:envelopeOf(errorType,
                        "seaware-sys-api answered an error", ctx.correlationId, reply.statusCode).toJson() : downstream,
            errorType
        };
        return failed;
    }
    return responseJson(reply);
}

// ---------- async path ----------

isolated function acceptAsync(RequestContext & readonly ctx) returns http:Response {
    json insert = core:asyncInsertBody(asyncRequests.connectionKey, asyncRequests.'table, ctx.correlationId,
            asyncRequests.description, ctx.payload);
    json|http:ClientError recorded = dbSysClient->post(dbSysApiPath, insert, {correlationId: ctx.correlationId});
    if recorded is http:ClientError {
        // Mule: the insert failure went to the global error handler, so no 202 was returned.
        return respond(ctx, failure(ctx, commons:errorTypeOfClientError(recorded),
                        "The asynchronous request could not be recorded"));
    }
    _ = start processAsync(ctx);
    http:Response response = new;
    response.statusCode = 202;
    response.setJsonPayload({UUID: ctx.correlationId});
    response.setHeader(commons:CORRELATION_HEADER, ctx.correlationId);
    return response;
}

isolated function processAsync(RequestContext & readonly ctx) {
    Outcome outcome = processRequest(ctx);
    json result = outcome.ok ? outcome.body : mappedErrorBody(ctx, outcome);
    core:AsyncStatus status = outcome.ok ? core:PROCESSED : core:FAILED;
    if !outcome.ok {
        publishError(ctx, result, outcome.status);
    } else {
        publishAudit(ctx, result);
    }
    json update = core:asyncUpdateBody(asyncRequests.connectionKey, asyncRequests.'table, ctx.correlationId, status,
            asyncRequests.description, result);
    foreach int attempt in 1 ... asyncRequests.statusUpdateAttempts {
        json|http:ClientError saved = dbSysClient->post(dbSysApiPath, update, {correlationId: ctx.correlationId});
        if saved !is http:ClientError {
            log:printInfo("Async request processed", correlationId = ctx.correlationId, status = status);
            return;
        }
        log:printError("Unable to persist async status", correlationId = ctx.correlationId, status = status,
                attempt = attempt, 'error = saved);
        if attempt < asyncRequests.statusUpdateAttempts {
            runtime:sleep(asyncRequests.statusUpdateIntervalSeconds);
        }
    }
}

isolated function handleAsyncStatus(http:Request request, string? uuid) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if uuid is () || uuid.trim() == "" {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "Query parameter uuid is required",
                        correlationId));
    }
    json selectBody = core:asyncSelectBody(asyncRequests.connectionKey, asyncRequests.'table, uuid);
    json|http:ClientError answer = dbSysClient->post(dbSysApiPath, selectBody, {correlationId});
    if answer is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:errorTypeOfClientError(answer), answer.message(),
                        correlationId));
    }
    http:Response response = new;
    response.setJsonPayload(answer);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    return response;
}

// ---------- payment ----------

# POST v1/process-payment: passed to reservation-common-proc-api unchanged. Never retried.
isolated function handlePayment(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    json|http:ClientError body = request.getJsonPayload();
    if body is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body is not JSON",
                        correlationId));
    }
    if breaker.isOpen(correlationId) {
        return commons:errorResponse(breaker.openEnvelope(correlationId),
                {"Retry-After": breaker.retryAfterSeconds().toString()});
    }
    http:Response|http:ClientError reply = commonProcWriteClient->post(commonProcPaymentPath, body,
            commons:forwardHeaders(request, correlationId));
    if reply is http:ClientError {
        string errorType = commons:errorTypeOfClientError(reply);
        breaker.recordFailure(errorType, correlationId);
        return commons:errorResponse(commons:envelopeOf(errorType, reply.message(), correlationId));
    }
    if reply.statusCode >= 500 {
        breaker.recordFailure(commons:errorTypeOfStatus(reply.statusCode), correlationId);
    } else {
        breaker.recordSuccess(correlationId);
    }
    log:printInfo("Payment request completed", correlationId = correlationId, status = reply.statusCode);
    reply.setHeader(commons:CORRELATION_HEADER, correlationId);
    return reply;
}

// ---------- helpers ----------

# The request path as Mule logged and matched it: no query string.
isolated function pathOnly(string rawPath) returns string {
    int? q = rawPath.indexOf("?");
    return q is int ? rawPath.substring(0, q) : rawPath;
}

isolated function jsonOf(byte[] body) returns json {
    string|error text = string:fromBytes(body);
    if text is error {
        return ();
    }
    json|error parsed = text.fromJsonString();
    return parsed is error ? () : parsed;
}

# The GraphQL text; Mule also accepted the query as an array of lines (`joinBy " "`).
isolated function queryOf(json payload) returns string {
    if payload !is map<json> {
        return "";
    }
    json query = payload["query"];
    if query is string {
        return query;
    }
    if query is json[] {
        return string:'join(" ", ...from json line in query
                    select line.toString());
    }
    return "";
}

# The body of a JSON answer exactly as it arrived.
#
# + reply - The downstream answer
# + return - The bytes; `()` when the answer is empty or not JSON, which is then read as before
isolated function bytesOfJson(http:Response reply) returns byte[]? {
    if !reply.getContentType().toLowerAscii().startsWith("application/json") {
        return ();
    }
    byte[]|http:ClientError raw = reply.getBinaryPayload();
    return raw is byte[] && raw.length() > 0 ? raw : ();
}

isolated function responseJson(http:Response reply) returns json {
    json|http:ClientError body = reply.getJsonPayload();
    if body is json {
        return body;
    }
    string|http:ClientError text = reply.getTextPayload();
    return text is string && text != "" ? text : ();
}

isolated function messageOf(json body, string errorType) returns string {
    if body is map<json> {
        json message = body["message"];
        if message is string {
            return message;
        }
    }
    return errorType;
}
