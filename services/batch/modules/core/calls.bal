import aroya/integration_commons as commons;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/url;

# What a called system answered.
#
# + status - HTTP status
# + body - The JSON it sent, () when there was none
# + unreadable - true when it sent something that is not JSON, or nothing usable at all
# + failure - Short description when the call was refused
public type Answer record {|
    int status;
    json body = ();
    boolean unreadable = false;
    string failure = "";
|};

# One system the job calls, with the old application's retry rule: failures of the listed kinds
# are tried again after a pause; when the tries are used up the run stops with an error. Any other
# refusal is handed back so the caller can record it and carry on.
public isolated class Backend {
    private final http:Client httpClient;
    private final string name;
    private final int retryCount;
    private final decimal retryWaitSeconds;
    private final readonly & string[] retryErrorTypes;

    # + name - Name used in log lines and errors
    # + settings - Address and timeout
    # + sync - Retry settings
    # + return - An error when the client cannot be created
    public isolated function init(string name, commons:DownstreamSettings settings, SyncSettings sync) returns error? {
        self.name = name;
        self.httpClient = check commons:newDownstreamClient(settings);
        self.retryCount = sync.retryCount;
        self.retryWaitSeconds = sync.retryWaitSeconds;
        self.retryErrorTypes = sync.retryErrorTypes.cloneReadOnly();
    }

    # Sends one request.
    #
    # + method - HTTP method
    # + headers - Request headers
    # + body - JSON body, () for none
    # + query - Query values
    # + return - The answer, or an error once the retries are used up
    public isolated function send(string method, map<string> headers, json body = (), map<string> query = {})
            returns Answer|error {
        string path = "";
        foreach [string, string] [key, value] in query.entries() {
            path += (path == "" ? "?" : "&") + key + "=" + check url:encode(value, "UTF-8");
        }
        int left = self.retryCount;
        while true {
            Answer answer;
            string errorType;
            http:Response|http:ClientError res = self.httpClient->execute(method, path, body is () ? () : body, headers);
            if res is http:Response {
                answer = readAnswer(res);
                if res.statusCode < 400 {
                    return answer;
                }
                errorType = commons:errorTypeOfStatus(res.statusCode);
            } else {
                errorType = commons:errorTypeOfClientError(res);
                answer = {status: 500, unreadable: true, failure: errorType};
            }
            if self.retryErrorTypes.indexOf(errorType) is () {
                return answer;
            }
            if left <= 0 {
                return error(string `${self.name}: ${errorType} (still failing after ${self.retryCount} more tries)`);
            }
            left -= 1;
            runtime:sleep(self.retryWaitSeconds);
        }
    }
}

isolated function readAnswer(http:Response res) returns Answer {
    int status = res.statusCode;
    string failure = status >= 400 ? string `HTTP ${status}` : "";
    json|http:ClientError body = res.getJsonPayload();
    if body is json {
        return {status, body, failure};
    }
    string|http:ClientError raw = res.getTextPayload();
    boolean empty = raw is http:ClientError || raw.trim() == "";
    return {status, unreadable: !empty || status >= 400, failure};
}

# The entries the old flows put under `data` when the CRM refused a write.
#
# + answer - The refusal
# + label - Text put in front of the message ("reservation : ", "Addons : " …)
# + recordCount - How many records were in the request
# + byApiName - true: message is "<label><apiName>-<message>" when a apiName is named; false: "<label><message>"
# + return - One entry per CRM complaint (or per record when the answer could not be read)
public isolated function refusedData(Answer answer, string label, int recordCount, boolean byApiName) returns json[] {
    json[] out = [];
    if answer.unreadable {
        foreach int i in 0 ..< (recordCount < 1 ? 1 : recordCount) {
            out.push({"status": "error", "errorCode": 500, "message": answer.failure});
        }
        return out;
    }
    json target = f(answer.body, "targetError");
    json[] complaints = blank(f(target, "data")) ? items(target) : items(f(target, "data"));
    if complaints.length() == 0 {
        complaints = [answer.body];
    }
    foreach json c in complaints {
        string? message = text(f(c, "message"));
        string? apiName = text(f(c, "details", "api_name"));
        string shown = answer.failure;
        if byApiName && apiName is string && apiName != "" {
            shown = label + apiName + "-" + (message ?: "");
        } else if !byApiName && message is string && message != "" {
            shown = label + message;
        }
        out.push({"status": "error", "errorCode": answer.status, "message": shown});
    }
    return out;
}

# Writes records to the CRM through the CRM system service.
#
# + zoho - The CRM system service
# + method - POST or PUT
# + zohoPath - CRM path, sent in the `zohoPath` header
# + body - Request body
# + correlationId - Run id
# + label - Label for refusals
# + byApiName - See `refusedData`
# + recordCount - Records in the request
# + return - The CRM answer; a refusal comes back as `{data: [error entries]}`
public isolated function crmWrite(Backend zoho, string method, string zohoPath, json body, string correlationId,
        string label, boolean byApiName, int recordCount) returns json|error {
    Answer answer = check zoho.send(method, {"zohoPath": zohoPath, "correlationId": correlationId}, body);
    if answer.status >= 400 || answer.unreadable {
        return {"data": refusedData(answer, label, recordCount, byApiName)};
    }
    return answer.body;
}

# Searches the CRM. "Nothing found" and refusals both give an empty list.
#
# + zoho - The CRM system service
# + zohoPath - CRM search path
# + criteria - Search text
# + correlationId - Run id
# + return - Records found
public isolated function crmSearch(Backend zoho, string zohoPath, string criteria, string correlationId)
        returns json[]|error {
    Answer answer = check zoho.send("GET", {"zohoPath": zohoPath, "correlationId": correlationId}, (), {"criteria": criteria});
    if answer.status == 204 || answer.status >= 400 || answer.unreadable {
        return [];
    }
    return items(f(answer.body, "data"));
}

# The search text the old flows built: `((apiName:op:a) or (apiName:op:b))`.
#
# + fieldOp - Field and operator, e.g. `Name:in`
# + values - Values to look for
# + return - Search text
public isolated function anyOf(string fieldOp, json[] values) returns string {
    string[] parts = from json v in values select "(" + fieldOp + ":" + textOr(v, "") + ")";
    return "(" + string:'join(" or ", ...parts) + ")";
}

# Builds the insert for the error table the way the old flows did.
#
# + tableName - Table
# + rows - Rows; the columns are those of the first row
# + return - The request for the database system service, () when there are no rows
public isolated function errorInsert(string tableName, map<json>[] rows) returns json {
    if rows.length() == 0 {
        return ();
    }
    string[] keys = rows[0].keys();
    string[] tuples = [];
    foreach map<json> row in rows {
        string[] values = from string k in keys select sqlValue(row[k]);
        tuples.push("(" + string:'join(", ", ...values) + ")");
    }
    return {
        "connectionKey": "PG_Guest",
        "operation": "insert",
        "query": "INSERT INTO " + tableName + " (" + string:'join(", ", ...keys) + ") VALUES " + string:'join(", ", ...tuples)
    };
}

isolated function sqlValue(json v) returns string {
    if v is () {
        return "NULL";
    }
    if v is int|float|decimal {
        return v.toString();
    }
    string s = v is string ? v : v.toJsonString();
    return "'" + re `'`.replaceAll(s, "''") + "'";
}

# Sends error rows to the database system service. Problems here never stop the run.
#
# + db - The database system service, () when its address is not set
# + tableName - Error table
# + rows - Rows to write
# + correlationId - Run id
# + return - "" when written, otherwise why not
public isolated function writeErrorRows(Backend? db, string tableName, map<json>[] rows, string correlationId) returns string {
    json request = errorInsert(tableName, rows);
    if request is () {
        return "";
    }
    if db is () || tableName == "" {
        return "error table address or name not set";
    }
    Answer|error answer = db.send("POST", {"correlationId": correlationId}, request);
    if answer is error {
        return answer.message();
    }
    return answer.status >= 400 ? answer.failure : "";
}
