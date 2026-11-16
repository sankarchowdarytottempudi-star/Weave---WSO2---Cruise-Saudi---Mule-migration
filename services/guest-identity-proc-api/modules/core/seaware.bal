// Seaware session handling (Mule: seaware-login / seaware-logout sub-flows and Seaware_Error_check).

# The Login mutation for the reservation agent.
#
# + agent - The agent account
# + return - Request body
public isolated function loginRequestOf(SeawareAgent agent) returns map<json> => {
    "query": "mutation Login { login(role: ResAgent, login: \"" + gqlText(agent.userName) + "\", password: \""
        + gqlText(agent.password) + "\", totalTimeout: \"PT2H\", inactivityTimeout: \"PT2H\") { sessionGUID role username"
        + " sourceCode token versionInfo expiration { timeout inactivityTimeout expires autoExtend } } }"
};

public isolated function logoutRequestOf() returns map<json> => {"query": "mutation Logout { logout }"};

# The session token of a Login answer.
#
# + answer - Seaware's answer
# + return - The token, `()` when there is none
public isolated function loginTokenOf(json answer) returns string? {
    json token = fieldOf(answer, "data", "login", "token");
    return token is string && token != "" ? token : ();
}

# The `Authorization` value for a session token (Mule: the token as it is when it already says Bearer).
#
# + token - Session token
# + return - Header value
public isolated function bearerOf(string token) returns string => token.includes("Bearer") ? token : "Bearer " + token;

# The first error message of a Seaware answer.
#
# + answer - Seaware's answer
# + return - The message, `()` when the answer has no errors
public isolated function firstSeawareError(json answer) returns string? {
    json errors = fieldOf(answer, "errors");
    if errors is json[] && errors.length() > 0 {
        json message = fieldOf(errors[0], "message");
        return message is string ? message : "Seaware returned an error";
    }
    return ();
}

# True when the error means the request must be repeated with a new session (Mule Seaware_Error_check).
#
# + message - Seaware error message
# + return - True for a session error
public isolated function isSessionError(string message) returns boolean =>
    message.includes("Session context not found or expired") || message.includes("ManageClients")
        || message.includes("is being edited by XML SERVER operator");
