// What each operation of check-in-proc-api sends to the Otalio System API
// (Mule: v1/check-in-proc-api-implementation.xml, one sub-flow per operation).

# How the caller's body goes on to the backend.
public enum BodyKind {
    # Nothing is sent (GET)
    NO_BODY,
    # The caller's body, sent as `application/json` (Mule set that header itself)
    JSON_BODY,
    # The caller's body under the caller's own content type
    CALLER_BODY,
    # The caller's multipart upload
    UPLOAD
}

# One call to the Otalio System API.
#
# + method - HTTP method
# + pathKey - Name of the path setting (Mule `httpRequest.path.<name>`)
# + query - Query parameters added to the path, in order
# + headers - Headers to send besides the correlation id
# + body - How the caller's body is passed on
# + backendStatus - True when the caller gets the backend's own success status (Mule set
# `httpStatus` from the answer), false when a success is always answered 200
public type Call record {|
    string method;
    string pathKey;
    [string, string][] query = [];
    map<string> headers = {};
    BodyKind body = NO_BODY;
    boolean backendStatus = false;
|};

const JSON = "application/json";

# The paths of the Otalio System API, below its base path. Mule kept one setting per path
# (`httpRequest.path.*`); the same names can be overridden in the settings.
public final readonly & map<string> DEFAULT_PATHS = {
    "uploadFile": "/files?operationName=uploadFile",
    "personPicture": "/files?operationName=personPicture",
    "getDocumentsId": "/integration-tasks?operationName=getDocumentsId",
    "getAllDocuments": "/integration-tasks?operationName=getAllDocuments",
    "uploadDocuments": "/integration-tasks",
    "showPersonPicture": "/integration-tasks?operationName=showPersonPicture",
    "paymentToken": "/integration-tasks?operationName=paymentAuthorization",
    "getLinkedPerson": "/integration-tasks?operationName=getLinkedPerson",
    "updateEmergencyContact": "/integration-tasks?operationName=updateEmergencyContact",
    "customAttributesCheckIn": "/integration-tasks?operationName=customAttributesCheckIn",
    "deleteCustomValue": "/integration-tasks?operationName=deleteCustomValue"
};

# The full path of a call.
#
# + basePath - Base path of the Otalio System API
# + overrides - Paths from the settings, by name
# + pathKey - Name of the path
# + return - Base path and path, `()` when the name has no path
public isolated function pathOf(string basePath, map<string> overrides, string pathKey) returns string? {
    string? path = overrides.hasKey(pathKey) ? overrides[pathKey] : DEFAULT_PATHS[pathKey];
    if path is () || path.trim() == "" {
        return ();
    }
    string base = basePath.trim();
    if base.endsWith("/") {
        base = base.substring(0, base.length() - 1);
    }
    string rest = path.trim();
    return base + (rest.startsWith("/") ? rest : "/" + rest);
}

# GET /getLinkedPerson (Mule `getLinkedPersonSub_Flow`).
#
# + id - The caller's query parameter `id`
# + return - The call
public isolated function linkedPersonCall(string? id) returns Call {
    [string, string][] query = [["operationName", "getLinkedPerson"]];
    if id is string {
        query.push(["shipId", id]);
    }
    return {method: "GET", pathKey: "getLinkedPerson", query, headers: {"Content-Type": JSON}};
}

# PUT /updateEmergencyContact (Mule `updateEmergencyContactSub_Flow`): a POST that names the
# real method in `httpMethod`.
#
# + id - The caller's query parameter `id`
# + return - The call
public isolated function emergencyContactCall(string? id) returns Call {
    [string, string][] query = [["operationName", "updateEmergencyContact"], ["httpMethod", "PUT"]];
    if id is string {
        query.push(["shipId", id]);
    }
    return {method: "POST", pathKey: "updateEmergencyContact", query, body: CALLER_BODY};
}

# POST /travel-documents/{id}/file (Mule `uploadFile_implementation_Sub_Flow`): a document
# upload when the caller says `operationName=uploadFile`, a person picture otherwise.
#
# + id - The id in the path
# + operationName - The caller's query parameter `operationName`
# + return - The call
public isolated function fileUploadCall(string id, string? operationName) returns Call => {
    method: "POST",
    pathKey: operationName == "uploadFile" ? "uploadFile" : "personPicture",
    query: [["shipId", id]],
    body: UPLOAD,
    backendStatus: true
};

# GET /travel-documents/{id} (Mule `getDocuments(Id)_implementation_Sub_Flow`).
#
# + id - The id in the path
# + operationName - The caller's query parameter `operationName`
# + return - The call
public isolated function documentCall(string id, string? operationName) returns Call {
    string pathKey = "getDocumentsId";
    if operationName == "showPersonPicture" || operationName == "deleteCustomValue" {
        pathKey = <string>operationName;
    }
    return {method: "GET", pathKey, query: [["shipId", id]], headers: {"Content-Type": JSON}};
}

# GET /travelDocuments (Mule `getAllDocuments_implementation_Sub_Flow`).
#
# + return - The call
public isolated function allDocumentsCall() returns Call =>
    {method: "GET", pathKey: "getAllDocuments", headers: {"Content-Type": JSON}};

# POST /uploadDocuments (Mule `uploadDocuments_implementation_Sub_Flow`).
#
# + operationName - The caller's query parameter `operationName`
# + httpMethod - The caller's query parameter `httpMethod`
# + id - The caller's query parameter `id`
# + return - The call
public isolated function uploadDocumentsCall(string? operationName, string? httpMethod, string? id) returns Call {
    if operationName == "customAttributesCheckIn" {
        return {
            method: "POST",
            pathKey: "customAttributesCheckIn",
            query: [["operationName", "customAttributesCheckIn"]],
            body: JSON_BODY,
            backendStatus: true
        };
    }
    if operationName is string {
        return {
            method: "POST",
            pathKey: "uploadDocuments",
            query: [["httpMethod", httpMethod ?: ""], ["shipId", id ?: ""], ["operationName", operationName]],
            body: JSON_BODY,
            backendStatus: true
        };
    }
    return {
        method: "POST",
        pathKey: "uploadDocuments",
        query: [["operationName", "uploadDocuments"]],
        body: JSON_BODY,
        backendStatus: true
    };
}

# POST /paymentToken (Mule `paymentToken_Sub_Flow`): the caller's Authorization header goes on.
#
# + authorization - The caller's Authorization header
# + return - The call
public isolated function paymentTokenCall(string? authorization) returns Call {
    map<string> headers = {};
    if authorization is string {
        headers["Authorization"] = authorization;
    }
    return {method: "POST", pathKey: "paymentToken", headers, body: JSON_BODY, backendStatus: true};
}
