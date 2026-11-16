// Small pure helpers of check-in-proc-api.

import ballerina/url;

# True while a backend address is still the generator's placeholder.
#
# + address - Configured address
# + return - True when it is empty or points at localhost
public isolated function isPlaceholderAddress(string address) returns boolean {
    string u = address.trim().toLowerAscii();
    return u == "" || u.includes("//localhost") || u.includes("//127.0.0.1");
}

# A path with query parameters added, in the given order (values are URL-encoded). A path that
# already carries a query string keeps it, as the Mule requester did.
#
# + path - Path, which may already carry a query string
# + params - Parameters to add: name and value
# + return - The path with the parameters
public isolated function withQuery(string path, [string, string][] params) returns string {
    string out = path;
    foreach [string, string] [name, value] in params {
        string|url:Error encodedName = url:encode(name, "UTF-8");
        string|url:Error encodedValue = url:encode(value, "UTF-8");
        out += (out.includes("?") ? "&" : "?") + (encodedName is string ? encodedName : name) + "="
            + (encodedValue is string ? encodedValue : value);
    }
    return out;
}

# The media type of a Content-Type value without its parameters.
#
# + contentType - Header value, for example `multipart/form-data; boundary=x`
# + return - Lower-case media type, "" when there is none
public isolated function baseMediaTypeOf(string contentType) returns string {
    int? cut = contentType.indexOf(";");
    string base = cut is int ? contentType.substring(0, cut) : contentType;
    return base.trim().toLowerAscii();
}

# Mule `isEmpty`: nothing, an empty text, an empty object or an empty list.
#
# + value - Value to look at
# + return - True when it is empty
public isolated function isEmptyValue(json value) returns boolean {
    if value is () {
        return true;
    }
    if value is string {
        return value.trim() == "";
    }
    if value is map<json> {
        return value.length() == 0;
    }
    if value is json[] {
        return value.length() == 0;
    }
    return false;
}
