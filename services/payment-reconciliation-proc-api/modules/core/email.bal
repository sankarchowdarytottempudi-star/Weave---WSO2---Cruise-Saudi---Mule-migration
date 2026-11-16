// The summary e-mail of a run (Mule: "Build reconciliation email"). The HTML is the old template,
// text for text.

const CELL = "<td style='padding:8px;border:1px solid #ddd;'>";
const NARROW_CELL = "<td style='padding:8px;border:1px solid #ddd;white-space:nowrap;'>";
const HEAD = "<th style='padding:8px;border:1px solid #ddd;'>";
const NO_ROWS = "<tr><td colspan='5' style='padding:8px;border:1px solid #ddd;'>None</td></tr>";
const TABLE = "<table style='border-collapse:collapse;width:100%;'><tr>" + HEAD + "Booking</th>" + HEAD + "Order Ref</th>"
    + HEAD + "Status/Reason</th>" + HEAD + "Response</th>" + HEAD + "Payment Correlation ID</th>" + HEAD
    + "Session ID</th></tr>";

# JSON text with line breaks and two blanks per level, as DataWeave writes it.
#
# + value - The value
# + indent - Indentation of the enclosing level
# + return - The text
public isolated function prettyJson(json value, string indent = "") returns string {
    string inner = indent + "  ";
    if value is map<json> {
        if value.length() == 0 {
            return "{\n" + inner + "\n" + indent + "}";
        }
        string[] parts = [];
        foreach [string, json] [key, item] in value.entries() {
            parts.push(inner + key.toJsonString() + ": " + prettyJson(item, inner));
        }
        return "{\n" + string:'join(",\n", ...parts) + "\n" + indent + "}";
    }
    if value is json[] {
        if value.length() == 0 {
            return "[\n" + inner + "\n" + indent + "]";
        }
        string[] parts = [];
        foreach json item in value {
            parts.push(inner + prettyJson(item, inner));
        }
        return "[\n" + string:'join(",\n", ...parts) + "\n" + indent + "]";
    }
    return value.toJsonString();
}

isolated function statusTextOf(map<json> line) returns string {
    foreach string name in ["statusCode", "reason", "errorType"] {
        json value = line[name];
        if !isEmptyValue(value) {
            return textOf(value);
        }
    }
    return "";
}

isolated function detailOf(map<json> line) returns string {
    json response = line["response"];
    if !isEmptyValue(response) {
        return textOf(response);
    }
    json description = line["description"];
    if !isEmptyValue(description) {
        return textOf(description);
    }
    return prettyJson({});
}

# The table rows of one group of the summary.
#
# + lines - The summary lines of the group
# + return - HTML rows; one "None" row when the group is empty
public isolated function rowsHtml(map<json>[] lines) returns string {
    if lines.length() == 0 {
        return NO_ROWS;
    }
    string out = "";
    foreach map<json> line in lines {
        out += "<tr>" + CELL + textOf(line["bookingNumber"]) + "</td>" + CELL + textOf(line["orderRef"]) + "</td>" + CELL
            + statusTextOf(line) + "</td>" + CELL + "<pre style='white-space:pre-wrap;margin:0;'>" + detailOf(line)
            + "</pre></td>" + NARROW_CELL + textOf(line["correlationId"]) + "</td>" + NARROW_CELL
            + textOf(line["sessionId"]) + "</td></tr>";
    }
    return out;
}

# The subject of the summary e-mail.
#
# + prefix - Configured start of the subject
# + success - Number of accepted payments
# + failed - Number of failed payments
# + skipped - Number of rows left alone
# + return - The subject
public isolated function emailSubject(string prefix, int success, int failed, int skipped) returns string =>
    prefix + " - success " + success.toString() + ", failed " + failed.toString() + ", skipped " + skipped.toString();

# The HTML of the summary e-mail.
#
# + correlationId - Correlation id of the run
# + query - The numbers the run used
# + success - Lines of accepted payments
# + failed - Lines of failed payments
# + skipped - Lines of rows left alone
# + return - The HTML
public isolated function emailBody(string correlationId, QuerySettings query, map<json>[] success, map<json>[] failed,
        map<json>[] skipped) returns string =>
    "<!DOCTYPE html><html><body style='font-family:Arial,sans-serif;color:#222;'><h2>Payment Reconciliation Summary</h2>"
    + "<p><b>Scheduler Correlation ID:</b> " + correlationId + "</p><p><b>Lookback:</b> " + query.lookbackMinutes.toString()
    + " minutes<br/><b>Grace:</b> " + query.graceMinutes.toString() + " minutes<br/><b>Batch size:</b> "
    + query.batchSize.toString() + "</p><p><b>Success:</b> " + success.length().toString() + " | <b>Failed:</b> "
    + failed.length().toString() + " | <b>Skipped:</b> " + skipped.length().toString() + "</p><h3>Successful Records</h3>"
    + TABLE + rowsHtml(success) + "</table><h3>Failed Records</h3>" + TABLE + rowsHtml(failed)
    + "</table><h3>Skipped Records</h3>" + TABLE + rowsHtml(skipped) + "</table></body></html>";

# The body sent to the e-mail system API.
#
# + to - Recipients, separated by commas
# + subjectPrefix - Configured start of the subject
# + correlationId - Correlation id of the run
# + query - The numbers the run used
# + success - Lines of accepted payments
# + failed - Lines of failed payments
# + skipped - Lines of rows left alone
# + return - `{to, subject, body}`
public isolated function emailMessage(string to, string subjectPrefix, string correlationId, QuerySettings query,
        map<json>[] success, map<json>[] failed, map<json>[] skipped) returns map<json> => {
    to: splitText(to, ","),
    subject: emailSubject(subjectPrefix, success.length(), failed.length(), skipped.length()),
    body: emailBody(correlationId, query, success, failed, skipped)
};
