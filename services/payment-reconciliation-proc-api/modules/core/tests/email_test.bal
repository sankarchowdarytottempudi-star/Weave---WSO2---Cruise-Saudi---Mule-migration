import ballerina/io;
import ballerina/test;

const CELL_HTML = "<td style='padding:8px;border:1px solid #ddd;'>";
const NARROW_HTML = "<td style='padding:8px;border:1px solid #ddd;white-space:nowrap;'>";

@test:Config {}
function prettyJsonWritesTwoBlanksPerLevel() {
    test:assertEquals(prettyJson({a: 1, b: ["x", {c: ()}]}),
            "{\n  \"a\": 1,\n  \"b\": [\n    \"x\",\n    {\n      \"c\": null\n    }\n  ]\n}");
    test:assertEquals(prettyJson({}), "{\n  \n}");
    test:assertEquals(prettyJson([]), "[\n  \n]");
    test:assertEquals(prettyJson("a\"b"), "\"a\\\"b\"");
}

@test:Config {}
function anEmptyGroupShowsNone() {
    test:assertEquals(rowsHtml([]), "<tr><td colspan='5' style='padding:8px;border:1px solid #ddd;'>None</td></tr>");
}

@test:Config {}
function aSuccessRowShowsStatusAndAnswer() {
    map<json> line = successRecord({orderRef: "REF-1", bookingNumber: "B100", sessionId: "sess-1"}, "c-1", 200, {ok: true});
    test:assertEquals(rowsHtml([line]), "<tr>" + CELL_HTML + "B100</td>" + CELL_HTML + "REF-1</td>" + CELL_HTML + "200</td>"
            + CELL_HTML + "<pre style='white-space:pre-wrap;margin:0;'>{\n  \"ok\": true\n}</pre></td>" + NARROW_HTML
            + "c-1</td>" + NARROW_HTML + "sess-1</td></tr>");
}

@test:Config {}
function aSkippedRowShowsReasonAndRemarks() {
    map<json> line = {sessionId: "s", correlationId: "c", orderRef: "R", bookingNumber: "B", reason: "why", response: "remarks"};
    string html = rowsHtml([line]);
    test:assertTrue(html.includes(CELL_HTML + "why</td>"));
    test:assertTrue(html.includes("<pre style='white-space:pre-wrap;margin:0;'>remarks</pre>"));
}

@test:Config {}
function aMissingRowShowsAnEmptyObject() {
    string html = rowsHtml([missingRecord({orderRef: (), bookingNumber: (), sessionId: ()}, "c")]);
    test:assertTrue(html.includes(CELL_HTML + "Missing orderRef or bookingNumber</td>"));
    test:assertTrue(html.includes("<pre style='white-space:pre-wrap;margin:0;'>{\n  \n}</pre>"));
}

@test:Config {}
function aFailedRowShowsStatusThenAnswerThenDescription() {
    map<json> withStatus = failedRecord((), "c", "HTTP:INTERNAL_SERVER_ERROR", 500, "it failed", {message: "x"});
    test:assertTrue(rowsHtml([withStatus]).includes(CELL_HTML + "500</td>"));
    test:assertTrue(rowsHtml([withStatus]).includes("\"message\": \"x\""));
    map<json> unreachable = failedRecord((), "c", "HTTP:CONNECTIVITY", "", "it failed", ());
    test:assertTrue(rowsHtml([unreachable]).includes(CELL_HTML + "HTTP:CONNECTIVITY</td>"));
    test:assertTrue(rowsHtml([unreachable]).includes("<pre style='white-space:pre-wrap;margin:0;'>it failed</pre>"));
}

@test:Config {}
function rowsFollowEachOtherWithoutSeparator() {
    map<json> line = {bookingNumber: "B"};
    string one = rowsHtml([line]);
    test:assertEquals(rowsHtml([line, line]), one + one);
}

@test:Config {}
function subjectCountsTheThreeGroups() {
    test:assertEquals(emailSubject("[TEST] Payment reconciliation", 3, 1, 12),
            "[TEST] Payment reconciliation - success 3, failed 1, skipped 12");
}

@test:Config {}
function messageSplitsRecipientsAtCommas() {
    map<json> message = emailMessage("a@x.test,b@x.test", "P", "cid", {}, [], [], []);
    test:assertEquals(message.get("to"), ["a@x.test", "b@x.test"]);
    test:assertEquals(message.get("subject"), "P - success 0, failed 0, skipped 0");
    test:assertEquals(message.keys(), ["to", "subject", "body"]);
}

@test:Config {}
function bodyShowsNumbersCountsAndThreeTables() {
    map<json> line = {bookingNumber: "B", orderRef: "R", statusCode: 200, response: {}, correlationId: "c", sessionId: "s"};
    string body = emailBody("run-1", {lookbackMinutes: 15, graceMinutes: 0, batchSize: 150}, [line, line], [], [line]);
    test:assertTrue(body.startsWith("<!DOCTYPE html><html><body style='font-family:Arial,sans-serif;color:#222;'>"
            + "<h2>Payment Reconciliation Summary</h2><p><b>Scheduler Correlation ID:</b> run-1</p>"));
    test:assertTrue(body.includes("<p><b>Lookback:</b> 15 minutes<br/><b>Grace:</b> 0 minutes<br/><b>Batch size:</b> 150</p>"));
    test:assertTrue(body.includes("<p><b>Success:</b> 2 | <b>Failed:</b> 0 | <b>Skipped:</b> 1</p>"));
    test:assertTrue(body.endsWith("</table></body></html>"));
}

// The old template, taken from the uploaded application by a script (empty run, correlation id
// "CID", numbers 15 / 0 / 150): the new HTML must be the same text.
@test:Config {}
function bodyOfAnEmptyRunIsTheOldTemplateTextForText() returns error? {
    string expected = check io:fileReadString("modules/core/tests/resources/old_template_empty_run.html");
    test:assertEquals(emailBody("CID", {lookbackMinutes: 15, graceMinutes: 0, batchSize: 150}, [], [], []), expected);
}
