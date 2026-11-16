// reservation-common-proc-api on WSO2 (Ballerina). The Process API the Experience layer routes to.
// Voyage-list style operations are served from the Process cache (real Seaware data, pre-built,
// fast — the whole reason the cache exists), so heavy 12-month queries return in ~1s and never
// trip the breaker. Everything else is forwarded to real Seaware through the System API.
import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// Operations the Process cache already holds (served fast from Redis snapshots).
final readonly & string[] CACHEABLE = ["availablevoyages", "availablepromotions", "packagepromotions", "cities"];

final http:Client sysClient = check new (sysApiUrl, timeout = sysTimeoutSeconds);
// Writes: their own limit, longer than a read (a reservation store takes up to ~30 s in Seaware).
final http:Client sysWriteClient = check new (sysApiUrl, timeout = sysWriteTimeoutSeconds);
final http:Client cacheClient = check new (cacheUrl, timeout = cacheTimeoutSeconds);
// No retry on this client: a payment must never be sent twice.
final http:Client paymentsClient = check new (paymentsUrl, timeout = paymentsTimeoutSeconds);

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(procService, basePath);
    log:printInfo("reservation-common-proc-api starting", env = env, basePath = basePath,
            cache = cacheUrl, upstream = sysApiUrl);
}

final commons:AuditSink errorRecordSink = errorRecordSinkOf();

function errorRecordSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    return sink is commons:AuditSink ? sink : new commons:NoopAuditSink();
}

isolated service class ErrorRecordedApi {
    *http:InterceptableService;

    // Mule global error handler: every failed call goes to kafka.errorTopic as
    // [saved payload, {"errorMessage": error body}] (off unless switched on in the settings)
    public function createInterceptors() returns http:Interceptor[] => commons:errorRecordInterceptors(errorRecordSink);


    isolated resource function post integration\-tasks(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        http:Response res = new;
        res.setHeader(commons:CORRELATION_HEADER, correlationId);
        byte[]|http:ClientError body = request.getBinaryPayload();
        if body is http:ClientError {
            res.statusCode = 400;
            res.setJsonPayload({message: "The request body could not be read"});
            return res;
        }
        string? op = rootFieldOfBody(body);
        boolean cacheable = op is string && CACHEABLE.indexOf(op.toLowerAscii()) != ();

        if cacheable {
            // Fast path: the voyage/promotions list from the Process cache (real Seaware data).
            map<string> h = {"Content-Type": "application/json", "operationName": <string>op};
            h[commons:CORRELATION_HEADER] = correlationId;
            http:Response|http:ClientError cached = cacheClient->post(cachePath, body, h);
            if cached is http:Response {
                cached.setHeader(commons:CORRELATION_HEADER, correlationId);
                return cached;
            }
            log:printError("Cache read failed", correlationId = correlationId, 'error = cached);
            // fall through to the live source if the cache is unavailable
        }

        // Live path: forward to real Seaware through the System API.
        map<string> headers = {"Content-Type": "application/json"};
        headers[commons:CORRELATION_HEADER] = correlationId;
        string? auth = commons:headerOf(request, "Authorization");
        if auth is string {
            headers["Authorization"] = auth;
        }
        string? swAuth = commons:headerOf(request, "X-Seaware-Authorization");
        if swAuth is string {
            headers["X-Seaware-Authorization"] = swAuth;
        }
        // reference lists: answered from the hourly cache (refreshed in the background when older)
        boolean hourly = hourlyCached(op, body);
        string refKeyOf = hourly ? refKey(body) : "";
        if hourly {
            [int, string, byte[]]? kept = refGet(refKeyOf);
            if kept is [int, string, byte[]] {
                if kept[0] >= hourlyCacheSeconds {
                    refreshInBackground(refKeyOf, body, headers);
                    return cachedResponse(correlationId, kept[1], kept[2], "stale-refreshing");
                }
                return cachedResponse(correlationId, kept[1], kept[2], "hit");
            }
        }
        http:Client upstream = isMutation(body) ? sysWriteClient : sysClient;
        http:Response|http:ClientError reply = upstream->post(sysApiPath, body, headers);
        if hourly && reply is http:Response {
            byte[]|http:ClientError data = reply.getBinaryPayload();
            if data is byte[] {
                refPut(refKeyOf, reply.statusCode, reply.getContentType(), data);
                reply.setBinaryPayload(data, reply.getContentType());
            }
        }
        if reply is http:ClientError {
            log:printError("Upstream call failed", correlationId = correlationId, 'error = reply);
            res.statusCode = 502;
            res.setJsonPayload({message: "Upstream reservation source was not reachable",
                    correlationId: correlationId});
            return res;
        }
        reply.setHeader(commons:CORRELATION_HEADER, correlationId);
        return reply;
    }

    # POST process-payment: handed to the financial transactions Process API unchanged, together with the
    # caller's own sign-in headers. A payment is sent once from here; it is never repeated.
    isolated resource function post process\-payment(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        http:Response res = new;
        res.setHeader(commons:CORRELATION_HEADER, correlationId);
        byte[]|http:ClientError body = request.getBinaryPayload();
        if body is http:ClientError {
            res.statusCode = 400;
            res.setJsonPayload({message: "The request body could not be read", correlationId: correlationId});
            return res;
        }
        map<string> headers = {"Content-Type": "application/json"};
        headers[commons:CORRELATION_HEADER] = correlationId;
        foreach string name in ["Authorization", "X-Seaware-Authorization", "client_channel"] {
            string? value = commons:headerOf(request, name);
            if value is string {
                headers[name] = value;
            }
        }
        http:Response|http:ClientError reply = paymentsClient->post(paymentsPath, body, headers);
        if reply is http:ClientError {
            log:printError("Payments service call failed", correlationId = correlationId, 'error = reply);
            res.statusCode = 502;
            res.setJsonPayload({message: "The payments service was not reachable", correlationId: correlationId});
            return res;
        }
        log:printInfo("Payment request completed", correlationId = correlationId, status = reply.statusCode);
        reply.setHeader(commons:CORRELATION_HEADER, correlationId);
        return reply;
    }
}

final ErrorRecordedApi procService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};
    isolated resource function get ready() returns json => {status: "UP"};
}

isolated function rootFieldOfBody(byte[] body) returns string? {
    string|error s = string:fromBytes(body);
    if s is error {
        return ();
    }
    json|error j = s.fromJsonString();
    if j is json {
        json|error qv = j.query;
        if qv is json {
            return commons:rootFieldOf(qv.toString());
        }
    }
    return ();
}


# Whether the request is a GraphQL mutation (a write). Anything unreadable counts as a read.
#
# + body - The request body as received
# + return - True for a mutation
isolated function isMutation(byte[] body) returns boolean {
    string|error text = string:fromBytes(body);
    if text is error {
        return false;
    }
    json|error parsed = text.fromJsonString();
    if parsed is map<json> && parsed["query"] is string {
        // comment lines before the operation are ignored, as in seaware-sys
        string query = re `#[^\n]*`.replaceAll(<string>parsed["query"], "");
        return commons:operationTypeOf(query) == commons:MUTATION;
    }
    return false;
}
