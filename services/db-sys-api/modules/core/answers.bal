import ballerina/sql;
import ballerina/time;

import aroya/integration_commons as commons;

// What goes back to the caller: rows, the count of changed rows, or the error body.

# One row as JSON.
#
# Numbers, true/false and null stay what they are. Text stays text, and so does everything the
# database hands over as text (uuid, date, time, json and jsonb). A timestamp is written the
# ISO way (`2026-03-04T10:15:30.5`), bytes as base64, a list as a list.
#
# + row - The row as the database client returns it
# + return - The JSON object, one member per column
public isolated function rowOf(record {} row) returns map<json> {
    map<json> out = {};
    foreach [string, anydata] [name, value] in row.entries() {
        out[name] = columnOf(value);
    }
    return out;
}

isolated function columnOf(anydata value) returns json {
    if value is string {
        return isoStampOf(value);
    }
    if value is ()|int|boolean|decimal {
        return value;
    }
    if value is float {
        return value.isNaN() || value.isInfinite() ? value.toString() : value;
    }
    if value is byte[] {
        return value.toBase64();
    }
    if value is anydata[] {
        return from anydata item in value
            select columnOf(item);
    }
    if value is map<anydata> {
        map<json> out = {};
        foreach [string, anydata] [name, item] in value.entries() {
            out[name] = columnOf(item);
        }
        return out;
    }
    return value.toString();
}

# A timestamp as the database driver prints it (`2026-03-04 10:15:30.0`, always with a
# fraction) written the ISO way; any other text is returned as it is.
#
# + text - A column value
# + return - `2026-03-04T10:15:30`, or the text unchanged
public isolated function isoStampOf(string text) returns string {
    if text.length() < 21 || !(re `\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+`.isFullMatch(text)) {
        return text;
    }
    string fraction = text.substring(20);
    while fraction.endsWith("0") {
        fraction = fraction.substring(0, fraction.length() - 1);
    }
    return text.substring(0, 10) + "T" + text.substring(11, 19) + (fraction == "" ? "" : "." + fraction);
}

# The answer to an insert or an update (Mule: the statement result written as JSON).
#
# + affectedRows - Rows changed
# + return - `{"affectedRows": n, "generatedKeys": {}}`
public isolated function changedOf(int? affectedRows) returns map<json> =>
    {"affectedRows": affectedRows ?: 0, "generatedKeys": {}};

# The error body (Mule: Global_Error_Handler of this application).
#
# + failure - The refusal
# + correlationId - The request's correlation id
# + return - `{timestamp, statusCode, message, correlationId, error, targetError}`
public isolated function envelopeOf(Refusal failure, string correlationId) returns commons:ErrorEnvelope => {
    timestamp: time:utcToString(time:utcNow()),
    statusCode: failure.detail().status,
    message: failure.message(),
    correlationId,
    'error: failure.detail().errorType,
    targetError: failure.message()
};

# A database failure as the refusal the caller gets. Status 500 in every case, as before.
#
# A statement the database refused keeps the database's own message (the caller wrote the
# statement). A failure to connect or to log in gets a fixed text, because the driver's text
# can carry the server address.
#
# + failure - The error of the database client
# + return - QUERY_EXECUTION or CONNECTIVITY
public isolated function databaseRefusal(sql:Error failure) returns Refusal {
    if failure is sql:DatabaseError {
        string state = failure.detail().sqlState ?: "";
        if state != "" && !state.startsWith("08") && !state.startsWith("28") && !state.startsWith("3D")
                && !state.startsWith("53") && !state.startsWith("57") {
            return refusal("QUERY_EXECUTION", 500, serverMessageOf(failure.message()) + " (SQLSTATE " + state + ")");
        }
    }
    return notReachable(connectFailureOf(failure));
}

# Why the database could not be used, as one word. Read from the driver's text and the SQLSTATE;
# the text itself (it can carry the address, the user and the database name) goes nowhere.
#
# + failure - The error of the database client
# + return - refused, no-answer, unknown-host, login, database-name, encryption, busy or unknown
public isolated function connectFailureOf(sql:Error failure) returns string {
    string state = failure is sql:DatabaseError ? (failure.detail().sqlState ?: "") : "";
    string text = failure.message().toLowerAscii();
    error? cause = failure.cause();
    if cause is error {
        text += " " + cause.message().toLowerAscii();
    }
    if state.startsWith("28") || text.includes("password authentication failed") || text.includes("pg_hba.conf")
            || text.includes("authentication") {
        return "login";
    }
    if state.startsWith("3d") || state.startsWith("3D") || (text.includes("database") && text.includes("does not exist")) {
        return "database-name";
    }
    if state.startsWith("53") || text.includes("too many connections") || text.includes("connection slots") {
        return "busy";
    }
    if text.includes("unknownhost") || text.includes("unknown host") {
        return "unknown-host";
    }
    if text.includes("refused") {
        return "refused";
    }
    if text.includes("timed out") || text.includes("timeout") {
        return "no-answer";
    }
    if text.includes("ssl") || text.includes("encryption") {
        return "encryption";
    }
    return "unknown";
}

isolated function reasonTextOf(string reason) returns string {
    match reason {
        "refused" => {
            return ": the database host refused the connection from this server (its firewall or allow-list does"
                + " not admit this server, or nothing listens on that port)";
        }
        "no-answer" => {
            return ": the database host did not answer in time (a firewall drops the connection, or the address"
                + " is only reachable from another network)";
        }
        "unknown-host" => {
            return ": the database host name is not known from this server";
        }
        "login" => {
            return ": the database did not accept the account (user name or password, or this server is not"
                + " allowed for that account)";
        }
        "database-name" => {
            return ": the database name does not exist on that host";
        }
        "encryption" => {
            return ": the database asks for an encrypted connection";
        }
        "busy" => {
            return ": the database has no free connection";
        }
    }
    return "";
}

# The refusal for a database that cannot be reached or does not accept the account.
#
# + reason - What `connectFailureOf` found, if known
# + return - CONNECTIVITY, 500
public isolated function notReachable(string reason = "unknown") returns Refusal =>
    refusal("CONNECTIVITY", 500, "The database could not be reached with the configured address and account"
            + reasonTextOf(reason));

# The refusal for settings without a value.
#
# + names - The settings, as they stand in Config.toml
# + return - SERVICE_UNAVAILABLE, 503
public isolated function notConfigured(string[] names) returns Refusal =>
    refusal("SERVICE_UNAVAILABLE", 503, "The database settings are not set: " + ", ".'join(...names));

// The client's text is "Error while executing SQL query: <statement>. <server message>."; only
// the server's part is passed on.
isolated function serverMessageOf(string message) returns string {
    int? at = message.lastIndexOf("ERROR: ");
    string text = at is int ? message.substring(at) : "The statement failed";
    text = re `\s+`.replaceAll(text, " ").trim();
    return text.endsWith(".") ? text.substring(0, text.length() - 1) : text;
}
