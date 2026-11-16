// Small pure helpers shared by the operations of financial-transactions-proc-api.

import ballerina/url;

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

# The part of a payment-session body that holds `order`, `customer` and `extra`: the body itself,
# or its `session` member when the caller wrapped it.
#
# + payload - Caller's body
# + return - The session document
public isolated function sessionDocumentOf(json payload) returns json {
    if payload is map<json> && !payload.hasKey("order") {
        json wrapped = payload["session"];
        if wrapped is map<json> {
            return wrapped;
        }
    }
    return payload;
}
