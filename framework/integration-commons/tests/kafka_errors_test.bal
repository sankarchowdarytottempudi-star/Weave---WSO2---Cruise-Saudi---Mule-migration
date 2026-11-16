import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

isolated class RecordingSink {
    *AuditSink;
    private json[] seen = [];

    public isolated function audit(string correlationId, json request, json response) {
    }

    public isolated function failure(string correlationId, json request, json errorBody) {
        lock {
            self.seen.push({correlationId, request: request.clone(), errorBody: errorBody.clone()});
        }
    }

    isolated function records() returns json[] {
        lock {
            return self.seen.clone();
        }
    }
}

final RecordingSink recording = new;

listener http:Listener errorRecordListener = new (19477);

isolated service class ErrorRecordTestService {
    *http:InterceptableService;

    public function createInterceptors() returns http:Interceptor[] => errorRecordInterceptors(recording);

    isolated resource function post fails(@http:Payload json body) returns http:Response {
        http:Response res = new;
        res.statusCode = 502;
        // the operation still gets the body after the interceptor read it
        res.setJsonPayload({message: "backend refused", echoed: body});
        return res;
    }

    isolated resource function get fine() returns json => {ok: true};
}

final ErrorRecordTestService errorRecordService = new;

// attached before the listener starts, as the services do in their init()
function init() returns error? {
    check errorRecordListener.attach(errorRecordService, "/t");
}

@test:Config
function errorRecordOfAFailedCall() returns error? {
    http:Client c = check new ("http://127.0.0.1:19477/t");
    http:Response r = check c->post("/fails", {"guest": "x"}, {[CORRELATION_HEADER]: "c-77"});
    test:assertEquals(r.statusCode, 502);
    json answer = check r.getJsonPayload();
    test:assertEquals(answer, {message: "backend refused", echoed: {"guest": "x"}});
    http:Response ok = check c->get("/fine");
    test:assertEquals(ok.statusCode, 200);
    http:Response missing = check c->get("/nowhere");
    test:assertEquals(missing.statusCode, 404);
    runtime:sleep(0.5);
    json[] seen = recording.records();
    test:assertEquals(seen.length(), 1, "only the failed call is recorded; 200 and 404 are not: " + seen.toJsonString());
    test:assertEquals(seen[0].toJsonString(), ({correlationId: "c-77", request: {"guest": "x"},
                                errorBody: {message: "backend refused", echoed: {"guest": "x"}}}).toJsonString());
}

@test:Config
function emptyMeansEmpty() {
    test:assertTrue(isEmptyJson(()));
    test:assertTrue(isEmptyJson(""));
    test:assertTrue(isEmptyJson([]));
    test:assertTrue(isEmptyJson({}));
    test:assertFalse(isEmptyJson(0));
    test:assertFalse(isEmptyJson({a: 1}));
}

@test:Config
function tokenIsNeverKeptInClear() {
    string f = tokenFingerprint("Bearer abc.def");
    test:assertTrue(f.startsWith("sha256:"));
    test:assertEquals(f.length(), 23);
    test:assertFalse(f.includes("abc"));
    test:assertEquals(tokenFingerprint(""), "UNKNOWN");
}

@test:Config
function deadBrokerNeverStopsTheService() returns error? {
    AuditSink sink = check newAuditSink({bootstrapServers: ["127.0.0.1:9"], errorTopic: "t", errorEnabled: true,
                                         maxBlockSeconds: 1});
    // empty parts are skipped before Kafka is touched; a real send to a dead broker only logs
    sink.failure("c-1", (), {m: 1});
    sink.failure("c-2", {a: 1}, {m: 1});
}

@test:Config
function recordPublisherIsOffUnlessSwitchedOn() {
    RecordPublisher off = new ({bootstrapServers: ["127.0.0.1:9"], auditEnabled: false, errorEnabled: false});
    test:assertFalse(off.auditOn());
    test:assertFalse(off.errorOn());
    off.audit("c", {a: 1});
    RecordPublisher dead = new ({bootstrapServers: ["127.0.0.1:9"], errorEnabled: true, errorTopic: "t", maxBlockSeconds: 1});
    test:assertTrue(dead.errorOn());
    // a dead broker is logged, never raised
    dead.failure("c", {a: 1});
}
