// Small pure helpers shared by the operations of guest-identity-proc-api.

import ballerina/url;

# The Seaware reservation agent this API signs in as (Mule: data.seawareUserName / data.seawarePassword).
public type SeawareAgent record {|
    string userName = "";
    string password = "";
|};

# True while a backend address is still the generator's placeholder.
#
# + address - Configured address
# + return - True when it is empty or points at localhost
public isolated function isPlaceholderAddress(string address) returns boolean {
    string u = address.trim().toLowerAscii();
    return u == "" || u.includes("//localhost") || u.includes("//127.0.0.1");
}

# The field at `path` inside `value`; `()` when any step is missing (DataWeave null-safe selector).
#
# + value - JSON to read
# + path - Field names, outermost first
# + return - The field's value or `()`
public isolated function fieldOf(json value, string... path) returns json {
    json current = value;
    foreach string name in path {
        if current is map<json> {
            current = current[name];
        } else {
            return ();
        }
    }
    return current;
}

# A JSON value as text: text as it is, nothing as "", anything else in its JSON form.
#
# + value - JSON value
# + return - Text
public isolated function textOf(json value) returns string {
    if value is string {
        return value;
    }
    if value is () {
        return "";
    }
    return value.toString();
}

# A JSON value as trimmed text.
#
# + value - JSON value
# + return - Text without surrounding blanks
public isolated function trimmed(json value) returns string => textOf(value).trim();

# The fields of a request body. A caller that keeps them inside a "variables" object (the shape a
# GraphQL client holds them in) is read the same as a caller that sends them at the top level.
# Mule read the top level only; a body with its own top-level `identifier` is never unwrapped.
#
# + body - Request body
# + return - The object holding the fields, or nothing when the body is not an object
public isolated function requestFieldsOf(json body) returns map<json>? {
    if body !is map<json> {
        return ();
    }
    json inner = body["variables"];
    if inner is map<json> && !body.hasKey("identifier") {
        return inner;
    }
    return body;
}

# DataWeave `!isEmpty(value)`: false for nothing, "", [] and {}.
#
# + value - JSON value
# + return - True when there is something in it
public isolated function has(json value) returns boolean {
    if value is () {
        return false;
    }
    if value is string {
        return value != "";
    }
    if value is json[] {
        return value.length() > 0;
    }
    if value is map<json> {
        return value.length() > 0;
    }
    return true;
}

# A JSON number, or numeric text, as a decimal.
#
# + value - JSON value
# + return - The number, `()` when it is not one
public isolated function decimalOf(json value) returns decimal? {
    if value is decimal {
        return value;
    }
    if value is int|float|string {
        decimal|error parsed = decimal:fromString(value.toString().trim());
        return parsed is decimal ? parsed : ();
    }
    return ();
}

# A JSON number, or numeric text, as a whole number.
#
# + value - JSON value
# + fallback - Used when the value is not a number
# + return - The number
public isolated function intOf(json value, int fallback) returns int {
    decimal? number = decimalOf(value);
    return number is decimal ? <int>number.floor() : fallback;
}

# A JSON list as a list: a single object counts as a list of one, anything else as empty.
#
# + value - JSON value
# + return - The list
public isolated function listOf(json value) returns json[] {
    if value is json[] {
        return value;
    }
    if value is map<json> {
        return [value];
    }
    return [];
}

# Text parsed as JSON; `()` when it is not JSON.
#
# + text - Text
# + return - Parsed JSON or `()`
public isolated function jsonOfText(string text) returns json {
    json|error parsed = text.fromJsonString();
    return parsed is error ? () : parsed;
}

# Text made safe to stand between double quotes in a GraphQL document.
#
# + value - Raw text
# + return - Escaped text
public isolated function gqlText(string value) returns string {
    string out = "";
    foreach string:Char ch in value {
        if ch == "\\" {
            out += "\\\\";
        } else if ch == "\"" {
            out += "\\\"";
        } else if ch == "\n" {
            out += "\\n";
        } else if ch == "\r" {
            out += "\\r";
        } else if ch == "\t" {
            out += "\\t";
        } else {
            out += ch;
        }
    }
    return out;
}

# Text that stands without quotes in a GraphQL document (an enum value or a number): only
# letters, digits and underscores are kept.
#
# + value - Raw text
# + return - Safe text
public isolated function bareWord(string value) returns string => re `[^A-Za-z0-9_]`.replaceAll(value, "");

# Text as an SQL string literal.
#
# + value - Raw text
# + return - Quoted text with quotes doubled
public isolated function sqlText(string value) returns string => "'" + re `'`.replaceAll(value, "''") + "'";

# Text made safe to stand inside HTML.
#
# + value - Raw text
# + return - Escaped text
public isolated function htmlText(string value) returns string {
    string out = re `&`.replaceAll(value, "&amp;");
    out = re `<`.replaceAll(out, "&lt;");
    return re `>`.replaceAll(out, "&gt;");
}

# A path with query parameters added (values are URL-encoded).
#
# + path - Path, which may already carry a query string
# + params - Parameters to add
# + return - The path with the parameters
public isolated function withQuery(string path, map<string[]> params) returns string {
    string out = path;
    foreach [string, string[]] [name, values] in params.entries() {
        foreach string value in values {
            string|url:Error encodedName = url:encode(name, "UTF-8");
            string|url:Error encodedValue = url:encode(value, "UTF-8");
            out += (out.includes("?") ? "&" : "?") + (encodedName is string ? encodedName : name) + "="
                + (encodedValue is string ? encodedValue : value);
        }
    }
    return out;
}

# DataWeave `capitalize`: every word starts with a capital, the rest is lower case; underscores,
# hyphens and camelCase steps separate words.
#
# + text - Raw text
# + return - Capitalized text
public isolated function capitalize(string text) returns string {
    string[] words = [];
    string current = "";
    boolean previousLower = false;
    foreach string:Char ch in text {
        if ch == " " || ch == "_" || ch == "-" || ch == "\t" || ch == "\n" {
            if current != "" {
                words.push(current);
                current = "";
            }
            previousLower = false;
            continue;
        }
        boolean upper = ch.toUpperAscii() == ch && ch.toLowerAscii() != ch;
        if upper && previousLower && current != "" {
            words.push(current);
            current = "";
        }
        current += ch;
        previousLower = ch.toLowerAscii() == ch && ch.toUpperAscii() != ch;
    }
    if current != "" {
        words.push(current);
    }
    string[] out = from string word in words
        select word.substring(0, 1).toUpperAscii() + word.substring(1).toLowerAscii();
    return string:'join(" ", ...out);
}

# Mule: `email matches /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/`.
#
# + value - The e-mail address, or nothing
# + return - True for a usable address
public isolated function emailValid(json value) returns boolean {
    if value !is string {
        return false;
    }
    return re `[A-Za-z0-9._%+'\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`.isFullMatch(value);
}

# The rows of a database system API answer.
#
# + answer - The answer
# + return - Its rows; empty when it is not a list
public isolated function rowsOf(json answer) returns json[] => answer is json[] ? answer : [];

# The first row of a database system API answer.
#
# + answer - The answer
# + return - The row, `()` when there is none
public isolated function firstRowOf(json answer) returns map<json>? {
    json[] rows = rowsOf(answer);
    if rows.length() > 0 {
        json row = rows[0];
        if row is map<json> {
            return row;
        }
    }
    return ();
}

# A request for the database system API.
#
# + operation - select, insert or update
# + query - SQL text
# + params - Named parameters, `()` for none
# + return - Request body
public isolated function dbRequestOf(string operation, string query, map<json>? params = ()) returns map<json> {
    map<json> request = {"connectionKey": "PG_Guest", "operation": operation, "query": query};
    if params is map<json> {
        request["params"] = params;
    }
    return request;
}

# The error body of the Mule global handler for a failure that has no backend answer.
#
# + errorType - Error type
# + message - What happened
# + return - Error body
public isolated function plainErrorOf(string errorType, string message) returns map<json> => {
    "messageType": errorType,
    "message": message,
    "responseCode": "FEIGN_CLIENT",
    "responsePayload": (),
    "errorDoesNotExist": false
};

# Only an answer in the 200 range means the other side took a message. A redirect (3xx) does
# not: nothing was sent.
#
# + status - HTTP status of the answer
# + return - True for 200 to 299
public isolated function handedOver(int status) returns boolean => status >= 200 && status < 300;
