// Routing rules of reservation-mgr-exp-api, ported from the "apiPath" DataWeave of
// reservation-mgr-exp-api-implementation-flow-Process-Sub_Flow(-v2).

# Where a request goes.
#
# + rootField - The GraphQL root field the decision was made on
# + targetApi - Target API name from the operation mapping (`/reservation-common-api`)
# + path - Path on reservation-common-proc-api
public type Route record {|
    string rootField;
    string targetApi;
    string path;
|};

# Why a request could not be routed.
#
# + errorType - `GRAPHQL_QUERY` (no root field) or `NOT_IMPLEMENTED` (unmapped or unsupported target)
# + message - Message for the caller
public type RoutingError record {|
    string errorType;
    string message;
|};

# Decides the route for a request.
#
# Mule rules: the mapping lookup is case-insensitive and `operationMapping` wins over
# `static.operationMapping`; an unmapped field is "INVALID_OPERATION: Fields not found in
# mappings: <field>", and any target other than `/reservation-common-api` raises
# `CUSTOM:NOT_IMPLEMENTED` "The query or mutation is invalid.".
#
# + rootField - The request's GraphQL root field
# + operationMapping - Mule `operationMapping`
# + staticMapping - Mule `static.operationMapping`
# + routeTargets - Target API name -> path
# + return - The route, or why there is none
public isolated function resolveRoute(string? rootField, map<string> operationMapping, map<string> staticMapping,
        map<string> routeTargets) returns Route|RoutingError {
    if rootField is () {
        return {errorType: "GRAPHQL_QUERY", message: "invalid graphql query"};
    }
    string key = rootField.toLowerAscii();
    string? targetApi = lookupIgnoringCase(operationMapping, key) ?: lookupIgnoringCase(staticMapping, key);
    if targetApi is () {
        return {errorType: "NOT_IMPLEMENTED", message: string `INVALID_OPERATION: Fields not found in mappings: ${rootField}`};
    }
    string? path = routeTargets[targetApi];
    if path is () {
        return {errorType: "NOT_IMPLEMENTED", message: "The query or mutation is invalid."};
    }
    return {rootField, targetApi, path};
}

# Keys as written in the mapping. Config.toml keys that need quotes (`"/reservation-common-api"`)
# arrive with the quotes kept, so they are removed here, once, at startup.
#
# + mapping - A mapping from configuration
# + return - The same mapping with surrounding quotes and spaces removed from every key
public isolated function normalizeKeys(map<string> mapping) returns map<string> & readonly {
    map<string> out = {};
    foreach [string, string] [k, v] in mapping.entries() {
        string key = k.trim();
        if key.length() >= 2 && key.startsWith("\"") && key.endsWith("\"") {
            key = key.substring(1, key.length() - 1).trim();
        }
        out[key] = v;
    }
    return out.cloneReadOnly();
}

isolated function lookupIgnoringCase(map<string> mapping, string lowerKey) returns string? {
    foreach [string, string] [k, v] in mapping.entries() {
        if k.trim().toLowerAscii() == lowerKey {
            return v;
        }
    }
    return ();
}

# Whether the caller asked for asynchronous processing (Mule: header `client_asyncFlag` is "true").
#
# + flag - Header value
# + return - `true` for async
public isolated function isAsyncRequest(string? flag) returns boolean => flag is string && flag.toLowerAscii() == "true";
