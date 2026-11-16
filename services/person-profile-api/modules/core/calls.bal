// What each operation of person-profile-api sends to the Otalio System API
// (Mule: v1/*-implementation.xml, one sub-flow per operation, all through
// v1/generic-httpRequest.xml: httpRequest_Get_Otalio-sys-api / httpRequest_Post_Otalio-sys-api).

# How the caller's body goes on to the backend.
public enum BodyKind {
    # Nothing is sent (GET)
    NO_BODY,
    # The caller's body as it arrived (Mule: the payload of the POST operations)
    CALLER_BODY
}

# One call to the Otalio System API: always `otalioPath` with the query parameters below.
#
# + method - HTTP method
# + operation - Mule `operationName`, also used in the log
# + query - Query parameters, in the order Mule built them
# + headers - Headers to send besides the correlation id
# + body - How the caller's body is passed on
public type Call record {|
    string method;
    string operation;
    [string, string][] query = [];
    map<string> headers = {};
    BodyKind body = NO_BODY;
|};

const JSON = "application/json";

// Mule httpRequest_Get_Otalio-sys-api headers: Content-Type and `correletionID: vars.correletionID`.
// That variable is never set in the old application (only `correlationId` is), so the header
// carried no value; the correlation id is sent under its usual name instead.
final readonly & map<string> GET_HEADERS = {"Content-Type": JSON};

isolated function add([string, string][] query, string name, string? value) {
    if value is string {
        query.push([name, value]);
    }
}

isolated function addAll([string, string][] query, [string, string][] callerParams) {
    foreach [string, string] param in callerParams {
        query.push(param);
    }
}

isolated function get(string operation, [string, string][] query) returns Call =>
    {method: "GET", operation, query, headers: GET_HEADERS};

// source-flow: geteventbyfolio-implementationSub_Flow
# GET /getEventsFolio: `{operationName: "getEventsFolio", page, search, size, sort}` from the
# caller's query parameters (a parameter the caller did not send is left out).
#
# + page - Caller's `page`
# + search - Caller's `search`
# + size - Caller's `size`
# + sort - Caller's `sort`
# + return - The call
public isolated function eventsFolioCall(string? page, string? search, string? size, string? sort) returns Call {
    [string, string][] query = [["operationName", "getEventsFolio"]];
    add(query, "page", page);
    add(query, "search", search);
    add(query, "size", size);
    add(query, "sort", sort);
    return get("getEventsFolio", query);
}

// source-flow: getamenity-implementationSub_Flow
# GET /getamenity: `{operationName: "getamenity", search}`.
#
# + search - Caller's `search`
# + return - The call
public isolated function amenityCall(string? search) returns Call {
    [string, string][] query = [["operationName", "getamenity"]];
    add(query, "search", search);
    return get("getamenity", query);
}

// source-flow: getamenity-code-implementationSub_Flow
# GET /getamenity-codes: `{operationName: "getamenity-codes", search}`.
#
# + search - Caller's `search`
# + return - The call
public isolated function amenityCodesCall(string? search) returns Call {
    [string, string][] query = [["operationName", "getamenity-codes"]];
    add(query, "search", search);
    return get("getamenity-codes", query);
}

// source-flow: person-profile-proc-api-getPackage-implementationSub_Flow
# GET /pos/v1/packages: `{operationName: "getPackages", search}`. Only `search` goes on: the
# old flow did not pass page, hierarchyId, size or sort, although the API describes them.
#
# + search - Caller's `search`
# + return - The call
public isolated function packagesCall(string? search) returns Call {
    [string, string][] query = [["operationName", "getPackages"]];
    add(query, "search", search);
    return get("getPackages", query);
}

// source-flow: person-search-implementationSub_Flow
# GET /reservation/v1/person-search: operationName "getPersonSearch" followed by every query parameter
# of the caller, in the caller's order (Mule: the object ++ attributes.queryParams).
#
# + callerParams - The caller's query parameters (each value of each name)
# + return - The call
public isolated function personSearchCall([string, string][] callerParams) returns Call {
    [string, string][] query = [["operationName", "getPersonSearch"]];
    addAll(query, callerParams);
    return get("getPersonSearch", query);
}

// source-flow: person-search-byreservationid-implementationSub_Flow
# GET /reservation/v1/person-search/{reservationId}: operationName "getPersonByReservationID",
# shipId = reservationId, then every query parameter of the caller.
#
# + reservationId - Path parameter
# + callerParams - The caller's query parameters
# + return - The call
public isolated function personByReservationCall(string reservationId, [string, string][] callerParams) returns Call {
    [string, string][] query = [["operationName", "getPersonByReservationID"], ["shipId", reservationId]];
    addAll(query, callerParams);
    return get("getPersonByReservationID", query);
}

// source-flow: reservation-search-byreservationid-implementationSub_Flow
# GET /reservation/v1/reservation-search/{reservationId}: operationName "getReservationByID",
# shipId = reservationId, then every query parameter of the caller.
#
# + reservationId - Path parameter
# + callerParams - The caller's query parameters
# + return - The call
public isolated function reservationByIdCall(string reservationId, [string, string][] callerParams) returns Call {
    [string, string][] query = [["operationName", "getReservationByID"], ["shipId", reservationId]];
    addAll(query, callerParams);
    return get("getReservationByID", query);
}

// Mule httpRequest_Post_Otalio-sys-api headers: Content-Type, correlationId (sent by the relay)
// and `client_name` (the caller's `client_name` header, "MuleSoft" when it sent none).
isolated function post(string operation, [string, string][] query, string? clientName) returns Call =>
    {method: "POST", operation, query, body: CALLER_BODY,
        headers: {"Content-Type": JSON, "client_name": clientName ?: "MuleSoft"}};

// source-flow: messagestatus_implementationSub_Flow
# POST /integration/v1/messages/statuses: the caller's body, `{operationName: "statusmessage"}`.
#
# + clientName - Caller's `client_name` header
# + return - The call
public isolated function messageStatusesCall(string? clientName) returns Call =>
    post("statusmessage", [["operationName", "statusmessage"]], clientName);

// source-flow: message-implementationSub_Flow
# POST /integration/v1/messages: the caller's body, `{operationName: "sendmessage"}`.
#
# + clientName - Caller's `client_name` header
# + return - The call
public isolated function messagesCall(string? clientName) returns Call =>
    post("sendmessage", [["operationName", "sendmessage"]], clientName);

// source-flow: bulkUpdateReservations-implementationSub_Flow
# POST /reservation/v1/person-reservations/actions/bulk-update: the caller's body,
# `{operationName: "bulkUpdateReservations", httpMethod: "PATCH"}` (still sent as POST).
#
# + clientName - Caller's `client_name` header
# + return - The call
public isolated function bulkUpdateCall(string? clientName) returns Call =>
    post("bulkUpdateReservations", [["operationName", "bulkUpdateReservations"], ["httpMethod", "PATCH"]], clientName);

# The caller's query parameters as name/value pairs: every value of every name, in order.
#
# + params - The query parameters of the request, by name
# + return - The pairs
public isolated function pairsOf(map<string[]> params) returns [string, string][] {
    [string, string][] out = [];
    foreach [string, string[]] [name, values] in params.entries() {
        foreach string value in values {
            out.push([name, value]);
        }
    }
    return out;
}
