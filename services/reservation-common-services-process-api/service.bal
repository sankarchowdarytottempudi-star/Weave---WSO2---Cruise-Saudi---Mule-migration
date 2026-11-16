// reservation-common-services-process-api on WSO2 (Ballerina): the common reservation Process API.
// source-entry: post:\integration-tasks - the single operation of the old application, written below.
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
final http:Client cacheClient = check new (cacheUrl, timeout = cacheTimeoutSeconds);

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(procService, basePath);
    log:printInfo("reservation-common-services-process-api starting", env = env, basePath = basePath,
            cache = cacheUrl, upstream = sysApiUrl);
}

final commons:AuditSink errorRecordSink = errorRecordSinkOf();

function errorRecordSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    return sink is commons:AuditSink ? sink : new commons:NoopAuditSink();
}

isolated service class ErrorRecordedApi {
    *http:InterceptableService;

    // Mule global error handler, sub-flow `kafka`: every failed call goes to kafka.errorTopic as
    // [saved payload, {"errorMessage": error body}], skipped when either is empty (off unless switched on)
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
        // Old seaware-live-call-flow: with no sign-in of the caller, the API signs in to Seaware itself
        // and keeps the token (object store Object_store_accessToken, 11 hours; now Redis).
        boolean own = auth is () && swAuth is ();
        if own {
            string|error token = seawareToken(correlationId, false);
            if token is string {
                headers["Authorization"] = token;
            } else {
                log:printWarn("Seaware sign-in failed; the call goes on without a token", correlationId = correlationId,
                        'error = token);
            }
        }
        http:Response|http:ClientError reply = sysClient->post(sysApiPath, body, headers);
        if own && reply is http:Response && reply.statusCode == 401 {
            // old unauthorized-error-retrySub_Flow: a refused token is dropped and the call made once more
            string|error fresh = seawareToken(correlationId, true);
            if fresh is string {
                headers["Authorization"] = fresh;
                reply = sysClient->post(sysApiPath, body, headers);
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

// ---------------------------------------------------------------------------------------------
// Seaware sign-in (old accessTokenValidattionSub_Flow / accessTokenSub_Flow)
// ---------------------------------------------------------------------------------------------

// object-store: VoyageCacheOS -> written but never read by the old application; cached voyage answers come from seaware-cache-proc-api (Redis)

const string SEAWARE_TOKEN_KEY = "access_Token";
const int SEAWARE_TOKEN_TTL_SECONDS = 39600;          // Object_store_accessToken: 11 hours
const string SEAWARE_LOGIN = "mutation Login { login(role: Internal, totalTimeout: \"PT12H\", inactivityTimeout: \"PT12H\") "
    + "{ sessionGUID role username sourceCode versionInfo expiration { timeout inactivityTimeout expires autoExtend } "
    + "objects { isLocked lockInfo { timeout inactivityTimeout expires autoExtend lockedBy lockedByMe } } token }} ";

# The Seaware token to send: the kept one, or a new sign-in (kept for 11 hours).
#
# + correlationId - Correlation id of the call
# + renew - True when Seaware has just refused the kept token
# + return - The token, or why there is none
isolated function seawareToken(string correlationId, boolean renew) returns string|error {
    if renew {
        check state.remove(SEAWARE_TOKEN_KEY);
    } else {
        string? kept = check state.get(SEAWARE_TOKEN_KEY);
        if kept is string && kept != "" {
            return kept;
        }
    }
    map<string> headers = {"Accept": "application/json", "Content-Type": "application/json"};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response reply = check sysClient->post(sysApiPath, {query: SEAWARE_LOGIN}, headers);
    json answer = check reply.getJsonPayload();
    string token = check tokenOfLogin(answer);
    check state.put(SEAWARE_TOKEN_KEY, token, SEAWARE_TOKEN_TTL_SECONDS);
    log:printInfo("Seaware access token issued", correlationId = correlationId, keptIn = state.location());
    return token;
}

# + answer - Seaware's answer to the login mutation
# + return - data.login.token, or an error when the answer has none
isolated function tokenOfLogin(json answer) returns string|error {
    json token = check answer.data.login.token;
    if token is string && token != "" {
        return token;
    }
    return error("Seaware gave no token in its login answer");
}
