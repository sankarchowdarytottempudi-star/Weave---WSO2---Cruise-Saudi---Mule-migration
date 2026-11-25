import ballerina/crypto;
import ballerina/http;
import ballerina/log;
import ballerinax/kafka;

// The Mule global error handler of these applications published every failed call to the error
// topic: `[vars.OGPayload] ++ [{"errorMessage": payload}]`, in an async scope, only when
// `kafka.ErrorPayloadToKafka` is true, and skipped when either part is empty. These two
// interceptors do the same for a service without touching its operations: the first keeps the
// request body, the second publishes the error answer. `savepayload` (audit) was never called in
// these applications, so nothing is published for successful calls.

const string OG_PAYLOAD = "weave.ogPayload";
const string OG_CORRELATION = "weave.correlationId";

# Statuses that never reached the Mule global error handler: routing answers of the API itself.
public final readonly & int[] NOT_RECORDED = [404, 405];

# Keeps the caller's request body for the error record.
public isolated service class ErrorRecordRequestInterceptor {
    *http:RequestInterceptor;

    private final boolean keep;

    # + sink - Where error records go; with records off the request body is never touched
    public isolated function init(AuditSink sink = new NoopAuditSink()) {
        self.keep = recordsErrors(sink);
    }

    isolated resource function 'default [string... path](http:RequestContext ctx, http:Request req)
            returns http:NextService|error? {
        // Only when error records are on: the body is read as bytes and PUT BACK, so the operation
        // (and anything it forwards) still gets exactly what the caller sent
        if self.keep && req.getContentType().toLowerAscii().includes("json") {
            byte[]|http:ClientError raw = req.getBinaryPayload();
            if raw is byte[] {
                req.setBinaryPayload(raw, req.getContentType());
                string|error text = string:fromBytes(raw);
                if text is string {
                    ctx.set(OG_PAYLOAD, text);
                }
            }
        }
        string|http:HeaderNotFoundError cid = req.getHeader(CORRELATION_HEADER);
        if cid is string {
            ctx.set(OG_CORRELATION, cid);
        }
        return ctx.next();
    }
}

# Publishes the error record of an answer with status 400 or more.
public isolated service class ErrorRecordResponseInterceptor {
    *http:ResponseInterceptor;

    private final AuditSink sink;

    # + sink - Where error records go (a no-op sink when Kafka is off)
    public isolated function init(AuditSink sink) {
        self.sink = sink;
    }

    isolated remote function interceptResponse(http:RequestContext ctx, http:Response res)
            returns http:NextService|error? {
        int status = res.statusCode;
        if recordsErrors(self.sink) && status >= 400 && NOT_RECORDED.indexOf(status) == () {
            json request = ctx.hasKey(OG_PAYLOAD) ? jsonOfBytes((<string>ctx.get(OG_PAYLOAD)).toBytes()) : ();
            byte[]|http:ClientError out = res.getBinaryPayload();
            if out is byte[] {
                // the caller still gets the error answer exactly as it was
                res.setBinaryPayload(out, res.getContentType());
            }
            json errorBody = out is byte[] ? jsonOfBytes(out) : ();
            string correlationId = ctx.hasKey(OG_CORRELATION) ? <string>ctx.get(OG_CORRELATION) : "";
            if correlationId == "" {
                string|http:HeaderNotFoundError cid = res.getHeader(CORRELATION_HEADER);
                correlationId = cid is string ? cid : "";
            }
            AuditSink sink = self.sink;
            json & readonly req = request.cloneReadOnly();
            json & readonly body = errorBody.cloneReadOnly();
            future<()> _ = start sink.failure(correlationId, req, body);
        }
        return ctx.next();
    }
}

# The two interceptors, for a service's `createInterceptors`.
#
# + sink - Where error records go
# + return - Request interceptor, then response interceptor
public isolated function errorRecordInterceptors(AuditSink sink) returns http:Interceptor[] =>
    [new ErrorRecordRequestInterceptor(sink), new ErrorRecordResponseInterceptor(sink)];

# True only when error records really go to Kafka; then (and only then) bodies are read.
isolated function recordsErrors(AuditSink sink) returns boolean =>
    sink is KafkaAuditSink && sink.errorsOn();

isolated function jsonOfBytes(byte[] raw) returns json {
    if raw.length() == 0 {
        return ();
    }
    string|error text = string:fromBytes(raw);
    if text is error {
        return ();
    }
    json|error parsed = text.fromJsonString();
    return parsed is json ? parsed : text;
}

# Fingerprint of a bearer token, for records that used to carry the token in clear.
#
# + authorization - Header value as sent ("Bearer …" or the token)
# + return - `sha256:<16 hex>`, or "UNKNOWN" when there is no token
public isolated function tokenFingerprint(string authorization) returns string {
    string token = authorization.startsWith("Bearer ") ? authorization.substring(7) : authorization;
    if token.trim() == "" {
        return "UNKNOWN";
    }
    return "sha256:" + crypto:hashSha256(token.toBytes()).toBase16().substring(0, 16);
}

# Publishes records an application builds itself (applications whose Mule flows wrote a full
# record, such as reservation-mgr-exp-api). Off when its switches are off: nothing is made.
public isolated class RecordPublisher {
    private final kafka:Producer? producer;
    private final AuditSettings & readonly settings;

    # + settings - Kafka settings (the same section as the error records)
    public isolated function init(AuditSettings settings) {
        self.settings = settings.cloneReadOnly();
        kafka:Producer? made = ();
        if (settings.auditEnabled || settings.errorEnabled) && settings.bootstrapServers.length() > 0 {
            kafka:Producer|error p = new (settings.bootstrapServers, {maxBlock: settings.maxBlockSeconds, acks: kafka:ACKS_SINGLE});
            if p is error {
                log:printError("Kafka records are switched on but the producer could not be made", 'error = p);
            } else {
                made = p;
            }
        }
        self.producer = made;
    }

    # True when audit records are published.
    #
    # + return - Whether the audit switch is on and a producer exists
    public isolated function auditOn() returns boolean => self.settings.auditEnabled && self.producer !is ();

    # True when error records are published.
    #
    # + return - Whether the error switch is on and a producer exists
    public isolated function errorOn() returns boolean => self.settings.errorEnabled && self.producer !is ();

    # Publishes an audit record as it is, keyed by the correlation id. Failures are logged only.
    #
    # + key - Correlation id
    # + rec - The record
    public isolated function audit(string key, json rec) {
        if self.auditOn() {
            self.send(self.settings.auditTopic, key, rec);
        }
    }

    # Publishes an error record as it is, keyed by the correlation id. Failures are logged only.
    #
    # + key - Correlation id
    # + rec - The record
    public isolated function failure(string key, json rec) {
        if self.errorOn() {
            self.send(self.settings.errorTopic, key, rec);
        }
    }

    private isolated function send(string topic, string key, json rec) {
        kafka:Producer? p = self.producer;
        if p is () || topic == "" {
            return;
        }
        kafka:Error? sent = p->send({topic, key: key.toBytes(), value: rec.toJsonString().toBytes()});
        if sent is kafka:Error {
            log:printError("Kafka publish failed", topic = topic, correlationId = key, 'error = sent);
        }
    }
}
