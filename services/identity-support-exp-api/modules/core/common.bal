// Small pure helpers shared by the operations of identity-support-exp-api.

import ballerina/url;

# True while a backend address is still the generator's placeholder.
#
# + address - Configured address
# + return - True when it is empty or points at localhost
public isolated function isPlaceholderAddress(string address) returns boolean {
    string u = address.trim().toLowerAscii();
    return u == "" || u.includes("//localhost") || u.includes("//127.0.0.1");
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

# One path segment, URL-encoded.
#
# + segment - Raw segment, for example a guest id
# + return - The encoded segment
public isolated function pathSegment(string segment) returns string {
    string|url:Error encoded = url:encode(segment, "UTF-8");
    return encoded is string ? encoded : segment;
}
