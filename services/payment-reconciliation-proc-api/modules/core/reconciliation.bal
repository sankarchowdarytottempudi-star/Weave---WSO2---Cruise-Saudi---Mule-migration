// Pure logic of the payment reconciliation job (Mule: payment-reconciliation-scheduler-flow).
// Nothing in this module calls a backend; job.bal does that and uses these functions for every
// decision and every body it sends.

# Settings of the audit query (Mule: paymentReconciliation.query.*).
#
# + sql - The statement that selects the payment audit rows to look at. The texts `:lookbackMinutes`,
# `:graceMinutes` and `:batchSize` in it are replaced by the three numbers below
# + lookbackMinutes - How far back the statement looks
# + graceMinutes - Minutes a new audit row is left alone before it is picked up
# + batchSize - Most rows of one run
public type QuerySettings record {|
    string sql = "";
    int lookbackMinutes = 15;
    int graceMinutes = 0;
    int batchSize = 150;
|};

# What the job needs before the timer may start.
#
# + frequencyMinutes - Minutes between two runs
# + sql - The audit statement
# + connectionKey - Connection name of the database system API
# + dbUrl - Address of the database system API
# + paymentsUrl - Address of financial-transactions-proc-api
# + emailEnabled - True when the summary e-mail is sent
# + emailUrl - Address of the e-mail system API
# + emailTo - Recipients of the summary e-mail
public type StartCheck record {|
    int frequencyMinutes;
    string sql;
    string connectionKey;
    string dbUrl;
    string paymentsUrl;
    boolean emailEnabled;
    string emailUrl;
    string emailTo;
|};

# The payment a stored audit row describes.
#
# + orderRef - Telr order reference (from the stored response)
# + bookingNumber - Booking number (from the stored request)
# + sessionId - Session of the audit row
public type PaymentRequest record {|
    json orderRef;
    json bookingNumber;
    json sessionId;
|};

# Whether the payment of an audit row is tried again, and why.
#
# + shouldProcess - True when process-payment is called
# + httpStatus - HTTP status of the latest attempt; empty when there was none
# + errorCode - Error code of the latest attempt, upper case
# + status - Status text of the latest attempt
# + remarks - Remarks of the latest attempt
# + reason - The decision in words
public type RetryDecision record {|
    boolean shouldProcess;
    string httpStatus;
    string errorCode;
    string status;
    string remarks;
    string reason;
|};

final readonly & string[] REQUEST_KEYS = ["request_payload", "REQUEST_PAYLOAD", "requestPayload", "REQUESTPAYLOAD",
    "requestpayload"];
final readonly & string[] RESPONSE_KEYS = ["response_payload", "RESPONSE_PAYLOAD", "responsePayload", "RESPONSEPAYLOAD",
    "responsepayload"];
final readonly & string[] RECORD_KEYS = ["data", "records", "result", "rows"];
final readonly & string[] ITEM_NAME_KEYS = ["key", "name", "column", "columnName"];
final readonly & string[] ITEM_VALUE_KEYS = ["value", "VALUE", "data", "DATA"];

# True for an address that was never set (empty, or the generated placeholder).
#
# + address - The configured address
# + return - True when it is not a real address
public isolated function isPlaceholderAddress(string address) returns boolean {
    string u = address.trim().toLowerAscii();
    return u == "" || u.includes("//localhost") || u.includes("//127.0.0.1");
}

# The settings that keep the timer from starting; empty when it can start.
#
# + required - The values the job needs
# + return - Names of the settings that have no usable value
public isolated function settingsNotSet(StartCheck required) returns string[] {
    string[] names = [];
    if required.frequencyMinutes < 1 {
        names.push("scheduler.frequencyMinutes");
    }
    if required.sql.trim() == "" {
        names.push("query.sql");
    }
    if required.connectionKey.trim() == "" {
        names.push("dbSysApi.connectionKey");
    }
    if isPlaceholderAddress(required.dbUrl) {
        names.push("dBSysAPIHTTPRequestConfig.url");
    }
    if isPlaceholderAddress(required.paymentsUrl) {
        names.push("financialTransactionsHTTPRequestConfig.url");
    }
    if required.emailEnabled && isPlaceholderAddress(required.emailUrl) {
        names.push("emailSysAPIHTTPRequestConfig.url");
    }
    if required.emailEnabled && required.emailTo.trim() == "" {
        names.push("email.to");
    }
    return names;
}

# Replaces every occurrence of a text (DataWeave: `replace "a" with "b"`).
#
# + text - The text to change
# + find - The text to look for
# + replacement - What is put in its place
# + return - The changed text
public isolated function replaceText(string text, string find, string replacement) returns string {
    if find == "" {
        return text;
    }
    string out = "";
    int position = 0;
    while true {
        int? at = text.indexOf(find, position);
        if at is () {
            break;
        }
        out += text.substring(position, at) + replacement;
        position = at + find.length();
    }
    return out + text.substring(position);
}

# Splits a text at a separator (DataWeave: `splitBy`).
#
# + text - The text
# + separator - The separator
# + return - The parts, not trimmed
public isolated function splitText(string text, string separator) returns string[] {
    string[] parts = [];
    int position = 0;
    while true {
        int? at = text.indexOf(separator, position);
        if at is () {
            break;
        }
        parts.push(text.substring(position, at));
        position = at + separator.length();
    }
    parts.push(text.substring(position));
    return parts;
}

# The body sent to the database system API (Mule: "Build DB select request").
#
# + query - The audit statement and its three numbers
# + connectionKey - Connection name of the database system API
# + sessionId - Session id sent as parameter
# + return - The request body
public isolated function dbSelectRequest(QuerySettings query, string connectionKey, string sessionId) returns map<json> {
    string statement = replaceText(query.sql, ":lookbackMinutes", query.lookbackMinutes.toString());
    statement = replaceText(statement, ":graceMinutes", query.graceMinutes.toString());
    statement = replaceText(statement, ":batchSize", query.batchSize.toString());
    return {connectionKey, operation: "Select", query: statement, params: {sessionId}};
}

isolated function selected(json value, string name) returns json {
    if value is map<json> {
        return value[name];
    }
    if value is json[] {
        // DataWeave: a field selector on a list gives that field of every item, or null when no item has it
        json[] found = [];
        foreach json item in value {
            if item is map<json> && item.hasKey(name) {
                found.push(item[name]);
            }
        }
        return found.length() == 0 ? () : found;
    }
    return ();
}

# The audit rows inside the reply of the database system API (Mule: "Normalize DB response records":
# `payload.data default payload.records default payload.result default payload.rows default payload`).
#
# + reply - The reply body
# + return - The part that holds the rows
public isolated function recordsOf(json reply) returns json {
    foreach string name in RECORD_KEYS {
        json found = selected(reply, name);
        if found !is () {
            return found;
        }
    }
    return reply;
}

# The rows to work through. Anything that is not a list has no rows.
#
# + records - Result of `recordsOf`
# + return - The rows
public isolated function rowsOf(json records) returns json[] => records is json[] ? records : [];

# A value as text (DataWeave: `(value default '') as String`).
#
# + value - The value
# + return - Its text; empty for null
public isolated function textOf(json value) returns string {
    if value is () {
        return "";
    }
    if value is string {
        return value;
    }
    if value is map<json>|json[] {
        return prettyJson(value);
    }
    return value.toString();
}

# A column name without case, blanks and underscores (Mule: normalizedKey).
#
# + key - The name
# + return - The comparable form
public isolated function normalizedKey(json key) returns string => replaceText(textOf(key).trim(), "_", "").toLowerAscii();

# The first field of a row object whose name matches, whatever its spelling (snake, camel, upper).
#
# + row - The audit row
# + fieldName - Name of the column
# + return - Its value; `()` when the row is not an object or has no such field
public isolated function namedFieldOf(json row, string fieldName) returns json {
    if row !is map<json> {
        return ();
    }
    string wanted = normalizedKey(fieldName);
    foreach [string, json] [key, value] in row.entries() {
        if normalizedKey(key) == wanted {
            return value;
        }
    }
    return ();
}

# A column of an audit row, for a row that is an object or a list (Mule: getField of "Build
# process-payment request"). In a list, a named item wins; otherwise the stored request is item 10
# and the stored response is item 13.
#
# + row - The audit row
# + fieldName - Name of the column
# + return - Its value, or `()`
public isolated function fieldOf(json row, string fieldName) returns json {
    string wanted = normalizedKey(fieldName);
    if row is map<json> {
        string[] direct = wanted == "requestpayload" ? REQUEST_KEYS : (wanted == "responsepayload" ? RESPONSE_KEYS : []);
        foreach string key in direct {
            json value = row[key];
            if value !is () {
                return value;
            }
        }
        return namedFieldOf(row, fieldName);
    }
    if row is json[] {
        foreach json item in row {
            if item is map<json> && isNamed(item, wanted) {
                foreach string key in ITEM_VALUE_KEYS {
                    json value = item[key];
                    if value !is () {
                        return value;
                    }
                }
                return ();
            }
        }
        int? index = wanted == "requestpayload" ? 10 : (wanted == "responsepayload" ? 13 : ());
        return index is int && index < row.length() ? row[index] : ();
    }
    return ();
}

isolated function isNamed(map<json> item, string wanted) returns boolean {
    foreach string key in ITEM_NAME_KEYS {
        if normalizedKey(item[key]) == wanted {
            return true;
        }
    }
    return false;
}

# The inner value of a `{value: ...}` wrapper; anything else unchanged.
#
# + value - The value
# + return - The unwrapped value
public isolated function unwrapValue(json value) returns json => value is map<json> && value.hasKey("value") ? value["value"] : value;

# A stored payload as JSON: text is parsed, anything else is kept (Mule: parseJson).
#
# + value - The stored value
# + return - The parsed value, or an error when the text is not JSON
public isolated function parsedJson(json value) returns json|error {
    json inner = unwrapValue(value);
    if inner is string && inner.trim() != "" {
        return inner.fromJsonString();
    }
    return inner;
}

isolated function at(json value, string... path) returns json {
    json current = value;
    foreach string name in path {
        if current !is map<json> {
            return ();
        }
        current = current[name];
    }
    return current;
}

# The payment an audit row describes (Mule: "Build process-payment request").
#
# + row - The audit row
# + return - Order reference, booking number and session; an error when a stored payload is not JSON
public isolated function paymentRequestOf(json row) returns PaymentRequest|error {
    json sessionId = unwrapValue(fieldOf(row, "session_id"));
    json responsePayload = check parsedJson(fieldOf(row, "response_payload"));
    json requestPayload = check parsedJson(fieldOf(row, "request_payload"));
    json cartId = at(requestPayload, "order", "cartId");
    return {
        orderRef: at(responsePayload, "order", "ref"),
        bookingNumber: cartId is () ? at(requestPayload, "order", "cartid") : cartId,
        sessionId
    };
}

# DataWeave `isEmpty`: null, empty text, empty list, empty object.
#
# + value - The value
# + return - True when it is empty
public isolated function isEmptyValue(json value) returns boolean {
    if value is () {
        return true;
    }
    if value is string {
        return value == "";
    }
    if value is json[] {
        return value.length() == 0;
    }
    if value is map<json> {
        return value.length() == 0;
    }
    return false;
}

# True when the row gives both an order reference and a booking number.
#
# + request - The payment of the row
# + return - True when process-payment can be called for it
public isolated function isComplete(PaymentRequest request) returns boolean =>
    !isEmptyValue(request.orderRef) && !isEmptyValue(request.bookingNumber);

# The body sent to process-payment.
#
# + request - The payment of the row
# + return - `{orderRef, bookingNumber}`
public isolated function requestBodyOf(PaymentRequest request) returns map<json> =>
    {orderRef: request.orderRef, bookingNumber: request.bookingNumber};

# Decides from the latest attempt of an audit row whether the payment is tried again (Mule: "Set
# retry decision"): no attempt yet, HTTP 500, or HTTP 400 with TELR_PENDING or CUSTOM-ERROR.
#
# + auditRecord - The audit row
# + return - The decision
public isolated function retryDecisionOf(json auditRecord) returns RetryDecision {
    string httpStatus = textOf(unwrapValue(namedFieldOf(auditRecord, "attempt_http_status")));
    string errorCode = textOf(unwrapValue(namedFieldOf(auditRecord, "attempt_error_code"))).toUpperAscii();
    boolean pending = httpStatus == "400" && errorCode == "TELR_PENDING";
    boolean custom = httpStatus == "400" && errorCode == "CUSTOM-ERROR";
    string reason = "Latest payment attempt is terminal or not retryable";
    if httpStatus == "" {
        reason = "No previous payment attempt found";
    } else if httpStatus == "500" {
        reason = "Latest payment attempt was HTTP 500";
    } else if pending {
        reason = "Latest payment attempt was TELR_PENDING";
    } else if custom {
        reason = "Latest payment attempt was CUSTOM-ERROR";
    }
    return {
        shouldProcess: httpStatus == "" || httpStatus == "500" || pending || custom,
        httpStatus,
        errorCode,
        status: textOf(unwrapValue(namedFieldOf(auditRecord, "attempt_status"))),
        remarks: textOf(unwrapValue(namedFieldOf(auditRecord, "attempt_remarks"))),
        reason
    };
}

isolated function orEmpty(json value) returns json => value is () ? "" : value;

# The line of the summary for a payment that process-payment accepted.
#
# + request - The payment
# + correlationId - Correlation id of this payment
# + statusCode - HTTP status of process-payment
# + response - Its answer
# + return - The summary line
public isolated function successRecord(PaymentRequest request, string correlationId, int statusCode, json response)
        returns map<json> => {
    sessionId: orEmpty(request.sessionId),
    correlationId,
    orderRef: orEmpty(request.orderRef),
    bookingNumber: orEmpty(request.bookingNumber),
    statusCode,
    response: response is () ? {} : response
};

# The line of the summary for a payment whose latest attempt must not be repeated.
#
# + request - The payment
# + correlationId - Correlation id of this payment
# + decision - The retry decision
# + return - The summary line
public isolated function notRetryableRecord(PaymentRequest request, string correlationId, RetryDecision decision)
        returns map<json> => {
    sessionId: orEmpty(request.sessionId),
    correlationId,
    orderRef: orEmpty(request.orderRef),
    bookingNumber: orEmpty(request.bookingNumber),
    reason: decision.reason + ": httpStatus=" + decision.httpStatus + ", errorCode=" + decision.errorCode + ", status="
        + decision.status,
    response: decision.remarks
};

# The line of the summary for a row without order reference or booking number.
#
# + request - What the row gave
# + correlationId - Correlation id of this payment
# + return - The summary line
public isolated function missingRecord(PaymentRequest request, string correlationId) returns map<json> => {
    sessionId: orEmpty(request.sessionId),
    correlationId,
    orderRef: orEmpty(request.orderRef),
    bookingNumber: orEmpty(request.bookingNumber),
    reason: "Missing orderRef or bookingNumber"
};

# The line of the summary for a payment that failed.
#
# + request - The payment; `()` when the row could not be read
# + correlationId - Correlation id of this payment
# + errorType - Kind of failure
# + statusCode - HTTP status of process-payment; empty text when there was no answer
# + description - The failure in words
# + response - Answer body of process-payment; `()` for none
# + return - The summary line
public isolated function failedRecord(PaymentRequest? request, string correlationId, string errorType, json statusCode,
        string description, json response) returns map<json> => {
    sessionId: request is () ? "" : orEmpty(request.sessionId),
    correlationId,
    orderRef: request is () ? "" : orEmpty(request.orderRef),
    bookingNumber: request is () ? "" : orEmpty(request.bookingNumber),
    errorType,
    statusCode: orEmpty(statusCode),
    description,
    response: response is () ? {} : response
};

# The names of a row's columns, for the log (never their values).
#
# + row - The audit row
# + return - The column names
public isolated function rowKeysOf(json row) returns string[] => row is map<json> ? row.keys() : [];

# The Mule name of the failure a backend status stands for (shown in the log and the summary).
#
# + status - HTTP status outside 200-299
# + return - The failure name
public isolated function errorTypeOfStatus(int status) returns string {
    match status {
        400 => {
            return "HTTP:BAD_REQUEST";
        }
        401 => {
            return "HTTP:UNAUTHORIZED";
        }
        403 => {
            return "HTTP:FORBIDDEN";
        }
        404 => {
            return "HTTP:NOT_FOUND";
        }
        405 => {
            return "HTTP:METHOD_NOT_ALLOWED";
        }
        406 => {
            return "HTTP:NOT_ACCEPTABLE";
        }
        408|504 => {
            return "HTTP:TIMEOUT";
        }
        415 => {
            return "HTTP:UNSUPPORTED_MEDIA_TYPE";
        }
        429 => {
            return "HTTP:TOO_MANY_REQUESTS";
        }
        500 => {
            return "HTTP:INTERNAL_SERVER_ERROR";
        }
        502 => {
            return "HTTP:BAD_GATEWAY";
        }
        503 => {
            return "HTTP:SERVICE_UNAVAILABLE";
        }
    }
    return "HTTP:RESPONSE_VALIDATION";
}

# A failed call in words, without the backend's address.
#
# + path - Path that was called
# + status - HTTP status; `()` when there was no answer
# + timedOut - True when the answer did not come in time
# + return - The description
public isolated function failureDescription(string path, int? status, boolean timedOut = false) returns string {
    string opening = "HTTP POST on resource '" + path + "' failed: ";
    if status is () {
        return opening + (timedOut ? "the answer did not come in time." : "the backend could not be reached.");
    }
    return opening + "status code " + status.toString() + ".";
}
