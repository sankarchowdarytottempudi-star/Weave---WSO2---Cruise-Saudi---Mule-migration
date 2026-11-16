import ballerina/lang.runtime;
import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

# Where the job reads its rows from. The real one is the Otalio database; tests hand in rows.
public type RowSource isolated object {
    # Runs one query.
    #
    # + query - SQL text (a SELECT)
    # + return - The rows as JSON objects, or an error
    public isolated function rows(string query) returns json[]|error;
};

# The Otalio database (MySQL). Only SELECT statements are run.
public isolated class MySqlRows {
    *RowSource;
    private final mysql:Client db;
    private final int retryCount;
    private final decimal retryWaitSeconds;

    # + settings - Address and account
    # + sync - Retry settings
    # + return - An error when the database cannot be reached
    public isolated function init(DbSettings settings, SyncSettings sync) returns error? {
        self.retryCount = sync.retryCount;
        self.retryWaitSeconds = sync.retryWaitSeconds;
        mysql:Client|sql:Error db = new (settings.host, settings.username, settings.password,
            settings.database == "" ? () : settings.database, settings.port,
            {connectTimeout: settings.connectTimeoutSeconds},
            {maxOpenConnections: 2, minIdleConnections: 0}
        );
        if db is sql:Error {
            // The driver's text can contain the server address, so it is not passed on.
            return error("the database could not be reached with the configured address and account");
        }
        self.db = db;
    }

    # Checks that the database answers.
    #
    # + return - An error when it does not
    public isolated function ping() returns error? {
        json[]|error answer = self.once("SELECT 1 AS ok");
        if answer is error {
            return error("the database could not be reached with the configured address and account");
        }
    }

    # Runs one query; a lost connection is tried again like the old job did.
    #
    # + query - SQL text
    # + return - Rows or an error once the tries are used up
    public isolated function rows(string query) returns json[]|error {
        int left = self.retryCount;
        while true {
            json[]|error answer = self.once(query);
            if answer is json[] {
                return answer;
            }
            boolean connectionProblem = answer is sql:DatabaseError
                ? (answer.detail().sqlState ?: "").startsWith("08")
                : answer is sql:ApplicationError && !(answer is sql:DataError);
            if !connectionProblem {
                return error("Otalio database: the query was refused (" + errorKind(answer) + ")");
            }
            if left <= 0 {
                return error(string `Otalio database: no connection (still failing after ${self.retryCount} more tries)`);
            }
            left -= 1;
            runtime:sleep(self.retryWaitSeconds);
        }
    }

    isolated function once(string query) returns json[]|error {
        sql:ParameterizedQuery q = ``;
        q.strings = [query].cloneReadOnly();
        stream<record {}, sql:Error?> result = self.db->query(q);
        json[] out = [];
        check from record {} row in result
            do {
                out.push(rowJson(row));
            };
        return out;
    }

    # Closes the connections.
    #
    # + return - An error when closing fails
    public isolated function close() returns error? {
        return self.db.close();
    }
}

isolated function errorKind(error e) returns string {
    if e is sql:DatabaseError {
        // Vendor code and SQL state only: the message can contain names from the customer's schema.
        sql:DatabaseErrorDetail detail = e.detail();
        return string `database error ${detail.errorCode}, state ${detail.sqlState ?: "-"}`;
    }
    return e is sql:DataError ? "a value could not be read" : "not a connection problem";
}

# One database row as JSON. Dates and times become text the way the old job saw them:
# `yyyy-MM-ddTHH:mm:ss`, `yyyy-MM-dd`, `HH:mm:ss`.
#
# + row - The row
# + return - JSON object with the same column names
public isolated function rowJson(record {} row) returns map<json> {
    map<json> out = {};
    foreach [string, anydata] [name, value] in row.entries() {
        out[name] = cellJson(value);
    }
    return out;
}

isolated function cellJson(anydata value) returns json {
    if value is ()|string|int|float|decimal|boolean {
        return value;
    }
    if value is byte[] {
        string|error asText = string:fromBytes(value);
        return asText is string ? asText : ();
    }
    if value is [int, decimal] {
        // A point in time: shown as UTC date and time.
        string utcText = stamp([value[0], value[1]]);
        return utcText.substring(0, 19);
    }
    if value is map<anydata> {
        boolean hasDate = value["year"] is int && value["month"] is int && value["day"] is int;
        boolean hasTime = value["hour"] is int && value["minute"] is int;
        if hasDate || hasTime {
            string date = hasDate ? pad(value["year"], 4) + "-" + pad(value["month"], 2) + "-" + pad(value["day"], 2) : "";
            string time = hasTime ? pad(value["hour"], 2) + ":" + pad(value["minute"], 2) + ":" + seconds(value["second"]) : "";
            return hasDate && hasTime ? date + "T" + time : date + time;
        }
    }
    json|error asJson = value.toJson();
    return asJson is error ? value.toString() : asJson;
}

isolated function pad(anydata value, int width) returns string {
    return value is int ? value.toString().padZero(width) : "".padZero(width);
}

isolated function seconds(anydata value) returns string {
    if value is int {
        return value.toString().padZero(2);
    }
    if value is decimal {
        return (<int>value.floor()).toString().padZero(2);
    }
    if value is float {
        return (<int>value.floor()).toString().padZero(2);
    }
    return "00";
}
