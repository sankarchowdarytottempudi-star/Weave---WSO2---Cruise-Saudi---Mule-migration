import ballerina/http;
import ballerina/test;

import aroya/email_sys_api.core;

// One-time codes through ZeptoMail's HTTPS send API: same message as the mail server would get,
// "Email sent." only when the provider takes it, the old error answer otherwise.

isolated json lastBody = ();
isolated string lastAuth = "";
isolated string mode = "ok";

service /v1\.1 on new http:Listener(18964, {host: "127.0.0.2"}) {
    isolated resource function post email(http:Request req) returns http:Response|error {
        json body = check req.getJsonPayload();
        string auth = check req.getHeader("Authorization");
        lock { lastBody = body.cloneReadOnly(); }
        lock { lastAuth = auth; }
        string m;
        lock { m = mode; }
        http:Response res = new;
        if m == "refuse" {
            res.statusCode = 422;
            res.setJsonPayload({"error": {"code": "TM_3201", "details": [{"code": "GE_102", "message": "Mandatory field missing"}]}});
        } else {
            res.statusCode = 201;
            res.setJsonPayload({"data": [{"code": "EM_104", "message": "Email request received"}], "request_id": "stand-in-req-1"});
        }
        return res;
    }
}

final http:Client emailSys = check new ("http://127.0.0.1:18963");

isolated function setMode(string m) { lock { mode = m; } }

@test:Config {}
function bodyCarriesTheSameMessage() {
    core:Mail mail = {to: ["a@example.invalid", "b@example.invalid"], cc: ["c@example.invalid"], subject: "S",
        body: "<!DOCTYPE html><html><body>X</body></html>",
        attachment: {name: "f.txt", contentType: "text/plain", contentBase64: "eA=="}};
    json b = core:zeptoApiBody("noreply@example.invalid", mail);
    test:assertEquals(b, {"from": {"address": "noreply@example.invalid"},
        "to": [{"email_address": {"address": "a@example.invalid"}}, {"email_address": {"address": "b@example.invalid"}}],
        "subject": "S", "htmlbody": "<!DOCTYPE html><html><body>X</body></html>",
        "cc": [{"email_address": {"address": "c@example.invalid"}}],
        "attachments": [{"content": "eA==", "mime_type": "text/plain", "name": "f.txt"}]});
}

@test:Config {}
function errorCodeIsReadWithoutAddresses() {
    test:assertEquals(core:zeptoErrorCode({"error": {"code": "TM_3201", "details": [{"code": "GE_102"}]}}), "TM_3201/GE_102");
    test:assertEquals(core:zeptoErrorCode({"error": {"code": "TM_4001"}}), "TM_4001");
    test:assertEquals(core:zeptoErrorCode(()), "");
}

@test:Config {}
function codeMailTakenByTheApiAnswersEmailSent() returns error? {
    setMode("ok");
    http:Response res = check emailSys->post("/email-sys-api/v1/send-email-notification",
        {"to": "guest@example.invalid", "subject": "Your code", "body": "<p>123456</p>"}, {"provider": "exchange"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getJsonPayload(), {message: "Email sent."});
    json body;
    lock { body = lastBody.clone(); }
    test:assertEquals(body, {"from": {"address": "noreply@example.invalid"},
        "to": [{"email_address": {"address": "guest@example.invalid"}}], "subject": "Your code",
        "htmlbody": "<!DOCTYPE html><html><body><p>123456</p></body></html>"});
    string auth;
    lock { auth = lastAuth; }
    test:assertEquals(auth, "Zoho-enczapikey stand-in-api-token");
}

@test:Config {}
function refusedByTheApiAnswersTheOldError() returns error? {
    setMode("refuse");
    http:Response res = check emailSys->post("/email-sys-api/v1/send-email-notification",
        {"to": "guest@example.invalid", "subject": "Your code", "body": "x"}, {"provider": "exchange"});
    setMode("ok");
    test:assertEquals(res.statusCode, 502);
    string text = (check res.getJsonPayload()).toJsonString();
    test:assertTrue(text.includes("The mail server did not accept the message"), text);
    test:assertTrue(text.includes("TM_3201"), text);
    test:assertFalse(text.includes("guest@example.invalid"), text);
    test:assertFalse(text.includes("stand-in-api-token"), text);
    test:assertFalse(text.includes("stand-in-send-mail-token"), text);
}

@test:Config {}
function badRequestStillRefusedBeforeTheProvider() returns error? {
    http:Response res = check emailSys->post("/email-sys-api/v1/send-email-notification",
        {"to": "guest@example.invalid", "body": "x"}, {"provider": "exchange"});
    test:assertEquals(res.statusCode, 400);
}


@test:Config {}
function apiTokenWinsAndSmtpPasswordIsTheFallback() {
    test:assertEquals(core:zeptoAuthorization("api-tok", "smtp-pw"), "Zoho-enczapikey api-tok");
    test:assertEquals(core:zeptoAuthorization("  ", "smtp-pw"), "Zoho-enczapikey smtp-pw");
    test:assertEquals(core:zeptoAuthorization("", "smtp-pw"), "Zoho-enczapikey smtp-pw");
}
