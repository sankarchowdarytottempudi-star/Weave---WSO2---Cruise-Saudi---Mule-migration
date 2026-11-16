// Reading the request (Mule: "Extract Request Variables" and "Validate Request").

# The request as the old flow read it: missing members become "" and {}.
# Mule: connectionKey, query and params with a default, operation in lower case.
#
# + body - The JSON body, `()` when there was none
# + return - The request, or a refusal when `params` is not an object
public isolated function requestOf(json body) returns DbRequest|Refusal {
    map<json> data = body is map<json> ? body : {};
    json params = data["params"];
    if params !is () && params !is map<json> {
        return refusal("BAD_REQUEST", 400, "params must be an object of names and values");
    }
    return {
        connectionKey: textOf(data["connectionKey"]),
        operation: textOf(data["operation"]).toLowerAscii(),
        query: textOf(data["query"]),
        params: params is map<json> ? params : {}
    };
}

# Checks the connection key and the operation, in the order the old flow did.
# An unknown key is UNAUTHORIZED (401), an unknown operation INVALID_REQUEST (400); both carry
# the old message, which names the operation in either case.
#
# + request - The request
# + return - A refusal, or `()` when both are known
public isolated function checked(DbRequest request) returns Refusal? {
    string message = "Invalid operation or not implemented: " + request.operation;
    if request.connectionKey != KEY_SHIP_TRACKING && request.connectionKey != KEY_GUEST {
        return refusal("UNAUTHORIZED", 401, message);
    }
    if request.operation != "select" && request.operation != "insert" && request.operation != "update" {
        return refusal("INVALID_REQUEST", 400, message);
    }
    return ();
}

# Settings without a value that the account of a connection key needs.
#
# + connectionKey - `PG_ShipTracking` or `PG_Guest`
# + database - The shared database settings
# + account - The account of that key
# + return - Names as they stand in Config.toml; empty when everything is set
public isolated function settingsNotSet(string connectionKey, DatabaseSettings database, AccountSettings account)
        returns string[] {
    string group = connectionKey == KEY_SHIP_TRACKING ? "shipTracking" : "guest";
    string[] names = [];
    if database.host.trim() == "" {
        names.push("database.host");
    }
    if database.name.trim() == "" {
        names.push("database.name");
    }
    if account.username.trim() == "" {
        names.push(group + ".username");
    }
    if account.password == "" {
        names.push(group + ".password");
    }
    return names;
}

# Builds a refusal.
#
# + errorType - Error type identifier
# + status - HTTP status
# + message - Text for the caller
# + return - The refusal
public isolated function refusal(string errorType, int status, string message) returns Refusal =>
    error Refusal(message, errorType = errorType, status = status);

isolated function textOf(json value) returns string {
    if value is () {
        return "";
    }
    return value is string ? value : value.toJsonString();
}
