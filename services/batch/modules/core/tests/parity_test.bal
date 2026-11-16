import ballerina/test;
import ballerina/time;

// Tests for the parts ported to reach parity with the old Mule flows (made-up data only).

@test:Config {}
function errorMailIsTheOldBody() {
    MailSettings s = {enabled: true, url: "http://mail.test", toAddress: "to@example.test", ccAddress: "cc@example.test",
        env: "uat", app: "seaware-batch-proc-api"};
    json body = errorMailBody(s, "CONNECTIVITY", "Seaware sign-in was refused", "HTTP 401", "page");
    test:assertEquals(f(body, "message", "subject"), "uat - seaware-batch-proc-api");
    test:assertEquals(f(body, "message", "importance"), "High");
    test:assertEquals(f(body, "message", "body", "contentType"), "HTML");
    string content = textOr(f(body, "message", "body", "content"), "");
    test:assertTrue(content.startsWith("<b>Error type :</b> CONNECTIVITY<br/><b>Description :</b> Seaware sign-in was refused"));
    test:assertTrue(content.includes("<b>Details :</b> HTTP 401"));
    test:assertEquals(f(at(f(body, "message", "toRecipients"), 0), "emailAddress", "address"), "to@example.test");
    test:assertEquals(f(at(f(body, "message", "ccRecipients"), 0), "emailAddress", "address"), "cc@example.test");
    json att = at(f(body, "message", "attachments"), 0);
    test:assertEquals(f(att, "@odata.type"), "#microsoft.graph.fileAttachment");
    test:assertEquals(f(att, "name"), "batch_errors.txt");
    test:assertEquals(f(att, "contentBytes"), "cGFnZQ==");
}

@test:Config {}
function importanceAsTheOldFlow() {
    foreach string t in ["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"] {
        test:assertEquals(mailImportance(t), "High");
    }
    foreach string t in ["RETRY_EXHAUSTED", "TIMEOUT", "UNAUTHORIZED", "N/A"] {
        test:assertEquals(mailImportance(t), "Low");
    }
}

@test:Config {}
function mailPartsFromErrors() {
    [string, string, string] a = mailParts(error("Seaware sign-in was refused", errorType = "UNAUTHORIZED", details = "HTTP 401"));
    test:assertEquals(a, ["UNAUTHORIZED", "Seaware sign-in was refused", "HTTP 401"]);
    [string, string, string] b = mailParts(error("CRM system service: CONNECTIVITY (still failing after 3 more tries)"));
    test:assertEquals(b[0], "CONNECTIVITY");
    test:assertEquals(b[2], "N/A");
    test:assertEquals(mailParts(error("something else"))[0], "N/A");
}

@test:Config {}
function mailSwitchedOffSendsNothing() returns error? {
    ErrorMail m = check new ({});
    test:assertFalse(m.active());
    test:assertEquals(m.send("X", "d", "x", "", "c1"), "error e-mail switched off");
}

@test:Config {}
function ossSignatureDateAndName() returns error? {
    time:Utc at = [1794805629, 0];
    test:assertEquals(httpDate(at), "Mon, 16 Nov 2026 05:07:09 GMT");
    test:assertEquals(ossObjectName("landing-area/x-", at), "landing-area/x-20261116050709.json");
    test:assertEquals(check ossSignature("test-secret-not-real", "application/json", "Mon, 16 Nov 2026 05:07:09 GMT",
            "demo-bucket", "landing-area/x-20261116050709.json"), "wLoFbyRU6CCX2sd76HTcSX53QGE=");
    OssUploader off = check new ({});
    test:assertFalse(off.active());
    test:assertEquals(check off.upload([{"node": {}}], "c1"), "");
}

function shorexChunk() returns Chunk {
    json guestWith = {"client": {"key": "CL1"}, "voyages": {"pkg": {"key": ["PKG1"]}},
        "shorex": [{"price": 75, "code": "SX1", "pkg": {"key": "PK", "description": "Tour"}}]};
    json guestWithout = {"client": {"key": "CL2"}, "voyages": {"pkg": {"key": ["PKG1"]}}};
    return {
        edges: [{"node": {"key": "R1", "version": 3, "guests": [guestWith, guestWithout]}}],
        correlationId: "c1",
        jobName: "delta",
        reservationAnswer: {"data": [{"details": {"id": "Z-R1"}}]},
        contactAnswers: [[{"zohoId": "G-1"}, {"zohoId": "G-2"}]]
    };
}

@test:Config {}
function shorexRecordsAsTheOldScript() {
    json[] recs = shorexRecords(shorexChunk());
    test:assertEquals(recs.length(), 2);
    test:assertEquals(recs[0], {
        "Shorex_Code": "SX1",
        "Name": "R1|CL1|SX1",
        "Shorex_Price": "75",
        "Shorex_Package_Key": "PK",
        "Shorex_Package_Description": "Tour",
        "Reservation_Shorex": "Z-R1",
        "Client_ID": "CL1",
        "Guest_Shorex": "G-1",
        "Shorex_Version": "3"
    });
    test:assertEquals(f(recs[1], "Name"), "R1|CL2|");
    test:assertEquals(f(recs[1], "message"), "No shorex assigned");
    test:assertEquals(f(recs[1], "errorCode"), 400);
}

@test:Config {}
function shorexErrorRowsHaveTheOldColumns() {
    Chunk c = shorexChunk();
    json[] recs = shorexRecords(c);
    Group g = {key: "R1", records: recs};
    map<json>[] rows = shorexErrors(c, g, answersFor(g, {"data": [{"status": "error", "errorCode": 400, "message": "Shorex : Name-bad"}]}));
    test:assertEquals(rows.length(), 2);
    test:assertEquals(rows[0]["module_name"], "Shorex");
    test:assertEquals(rows[0]["client_id"], "CL1");
    test:assertEquals(rows[0]["failure_reason"], "Shorex : Name-bad");
    test:assertFalse(rows[0].hasKey("cabin_number"));
    test:assertEquals(rows[1]["failure_reason"], "No shorex assigned");
    test:assertEquals(rows[1]["package_name"], "PKG1");
}

@test:Config {}
function shorexPathsAndSwitch() {
    CrmPaths p = {};
    test:assertEquals(p.shorex, "/crm/v6/Shorex/upsert");
    test:assertEquals(p.shorexSearch, "/crm/v6/Shorex/search");
    SyncSettings s = {};
    test:assertFalse(s.writeShorex);
}
