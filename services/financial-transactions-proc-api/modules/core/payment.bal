// POST /process-payment: the rules of the Mule flow "process-payment-impl" as pure functions.
// The service module makes the calls (Telr system API, Seaware system API, DB system API); every
// decision and every text sent or returned is built here so it can be unit-tested.

# Seaware service account used when the caller sends no agent session (Mule `data.seawareUserName`
# / `data.seawarePassword`). Both empty = no service account.
#
# + userName - Login name
# + password - Password
public type SeawareAgent record {|
    string userName = "";
    string password = "";
|};

# The body of POST /process-payment.
#
# + orderRef - Telr order reference
# + bookingNumber - Booking number the payment is for
public type PaymentInput record {|
    string orderRef;
    string bookingNumber;
|};

public const string VALIDATION_SUCCESS = "Success";
public const string PAYMENT_DONE = "Payment processed successfully";

# Reads and checks the request body. Both values end up inside queries, so only plain reference
# characters are accepted.
#
# + payload - Request body
# + return - The input, or an error that names the bad field
public isolated function paymentInputOf(json payload) returns PaymentInput|error {
    json orderRef = fieldOf(payload, "orderRef");
    json bookingNumber = fieldOf(payload, "bookingNumber");
    if !(orderRef is string) || orderRef.trim() == "" {
        return error("orderRef is required");
    }
    if !(bookingNumber is string) || bookingNumber.trim() == "" {
        return error("bookingNumber is required");
    }
    if !re `[A-Za-z0-9_.\-]{1,64}`.isFullMatch(orderRef.trim()) {
        return error("orderRef has characters that are not allowed");
    }
    if !re `[A-Za-z0-9_\-]{1,40}`.isFullMatch(bookingNumber.trim()) {
        return error("bookingNumber has characters that are not allowed");
    }
    return {orderRef: orderRef.trim(), bookingNumber: bookingNumber.trim()};
}

# The reservation number inside a booking number or a Telr cart id.
# Mule: `(value splitBy "-")[0] replace /^RES/ with ""`.
#
# + value - Booking number or cart id
# + return - The reservation number
public isolated function bookingKeyOf(string value) returns string {
    int? dash = value.indexOf("-");
    string first = dash is int ? value.substring(0, dash) : value;
    return first.startsWith("RES") ? first.substring(3) : first;
}

# The `order` part of the Telr status answer.
#
# + telrResponse - Answer of the Telr system API `status` operation
# + return - The order, `()` when Telr did not return one
public isolated function telrOrderOf(json telrResponse) returns json => fieldOf(telrResponse, "order");

# True when the Telr order belongs to the booking number the caller sent.
#
# + telrResponse - Telr status answer
# + bookingNumber - Booking number from the request
# + return - True when both carry the same reservation number
public isolated function bookingMatches(json telrResponse, string bookingNumber) returns boolean {
    json cartId = fieldOf(telrResponse, "order", "cartid");
    return cartId is string && cartId != "" && bookingKeyOf(cartId) == bookingKeyOf(bookingNumber);
}

# The Telr status text of the order ("Paid", "Pending", ...).
#
# + telrResponse - Telr status answer
# + return - The text, "" when missing
public isolated function telrStatusTextOf(json telrResponse) returns string =>
    textOf(fieldOf(telrResponse, "order", "status", "text"));

# The reservations inside a ReservationsSearch answer
# (Mule: `data.reservationsSearch.edges.node.reservation`).
#
# + searchAnswer - Seaware answer
# + return - The reservations
public isolated function reservationsOf(json searchAnswer) returns json[] {
    json edges = fieldOf(searchAnswer, "data", "reservationsSearch", "edges");
    json[] reservations = [];
    if edges is json[] {
        foreach json edge in edges {
            json reservation = fieldOf(edge, "node", "reservation");
            if reservation is map<json> {
                reservations.push(reservation);
            }
        }
    }
    return reservations;
}

isolated function scheduleSum(json reservation, string[] dueTypes) returns decimal? {
    json schedule = fieldOf(reservation, "paymentSchedule");
    decimal? total = ();
    if schedule is json[] {
        foreach json entry in schedule {
            json dueType = fieldOf(entry, "dueType");
            decimal? amount = decimalOf(fieldOf(entry, "amount"));
            if dueType is string && dueTypes.indexOf(dueType) is int && amount is decimal {
                total = total is decimal ? total + amount : amount;
            }
        }
    }
    return total;
}

# The amounts a payment may have for this booking: first deposit (with add-ons and shore
# excursions), final payment, invoice total and gross due. All taken from the first reservation,
# as in Mule.
#
# + reservations - Reservations of the search answer
# + return - The amounts that exist
public isolated function expectedAmountsOf(json[] reservations) returns decimal[] {
    decimal[] amounts = [];
    if reservations.length() == 0 {
        return amounts;
    }
    json first = reservations[0];
    decimal?[] candidates = [
        scheduleSum(first, ["ADDON", "FIRST DEPOSIT", "SHOREX"]),
        scheduleSum(first, ["FINAL PAYMENT"]),
        decimalOf(fieldOf(first, "invoiceTotals", "invoiceTotal")),
        decimalOf(fieldOf(first, "invoiceTotals", "grossDue"))
    ];
    foreach decimal? candidate in candidates {
        if candidate is decimal {
            amounts.push(candidate);
        }
    }
    return amounts;
}

# True when a transaction with this external reference is already on one of the reservations.
#
# + reservations - Reservations (or the result of a store)
# + orderRef - Telr order reference
# + return - True when found
public isolated function hasTransaction(json[] reservations, string orderRef) returns boolean {
    foreach json reservation in reservations {
        json transactions = fieldOf(reservation, "transactions");
        if transactions is json[] {
            foreach json txn in transactions {
                if fieldOf(txn, "externalIdent") == orderRef {
                    return true;
                }
            }
        }
    }
    return false;
}

# The decision before anything is written: "Success", or the reason the payment is refused.
# Same checks, same order and same texts as the Mule variable `validation`.
#
# + telrResponse - Telr status answer
# + bookingNumber - Booking number from the request
# + searchAnswer - Seaware ReservationsSearch answer (`()` when Seaware was not asked)
# + return - "Success" or the refusal text
public isolated function validationOf(json telrResponse, string bookingNumber, json searchAnswer) returns string {
    json[] reservations = reservationsOf(searchAnswer);
    boolean bookingOk = bookingMatches(telrResponse, bookingNumber);
    string statusText = telrStatusTextOf(telrResponse);
    boolean paid = statusText == "Paid";
    decimal telrAmount = decimalOf(fieldOf(telrResponse, "order", "amount")) ?: 0d;
    boolean amountOk = expectedAmountsOf(reservations).indexOf(telrAmount) is int;
    string telrRef = textOf(fieldOf(telrResponse, "order", "ref"));
    boolean alreadyProcessed = hasTransaction(reservations, telrRef);
    if bookingOk && paid && amountOk && !alreadyProcessed {
        return VALIDATION_SUCCESS;
    }
    if !bookingOk {
        return "Booking number validation failed. The booking number " + bookingNumber
            + " does not match the Telr payment details.";
    }
    if !paid {
        return "Payment is not successful. Current status is " + statusText + ".";
    }
    if !amountOk {
        return "Payment amount " + telrAmount.toString() + " does not match any expected booking amount in the system.";
    }
    return "Order reference " + telrRef + " has already been processed and cannot be processed again.";
}

// ---------------------------------------------------------------------------------------------
// Seaware requests
// ---------------------------------------------------------------------------------------------

# Login of the service account (Mule sub-flow `accessToken_ResAgent_Sub_Flow`).
#
# + agent - Service account
# + return - Request body for the Seaware system API
public isolated function loginRequestOf(SeawareAgent agent) returns map<json> => {
    "query": "mutation Login { login(role: ResAgent, login: \"" + gqlText(agent.userName) + "\", password: \""
        + gqlText(agent.password) + "\", totalTimeout: \"PT15M\", inactivityTimeout: \"PT15M\") { sessionGUID role username"
        + " sourceCode token versionInfo expiration { timeout inactivityTimeout expires autoExtend } } }"
};

public isolated function logoutRequestOf() returns map<json> => {"query": "mutation Logout { logout }"};

# ReservationsSearch for the booking.
#
# + bookingNumber - Checked booking number
# + return - Request body for the Seaware system API
public isolated function searchRequestOf(string bookingNumber) returns map<json> => {
    "query": "query ReservationsSearch { reservationsSearch(params: { keys: \"" + gqlText(bookingKeyOf(bookingNumber))
        + "\" }) { edges { cursor node { reservation { key id status { name } invoiceTotals { invoiceTotal payments"
        + " refunds invoicePaid chargeTotal grandTotal grossDue netDue pendingPayments pendingRefunds currentDue { date"
        + " amount type actionCode } } originalInitialDate confirmationDate currency { key name } transactions { key"
        + " externalIdent status { key } comment creditCardServerType creditCardMerchant type merchantReference amount"
        + " creditCardServerResponse } sourceCode paymentSchedule { dueType dueDate expirationDate amount"
        + " designatedPaymentCode paid } } } } } }",
    "variables": {}
};

# ReservationLock for the booking (15 minutes, as in Mule).
#
# + bookingNumber - Checked booking number
# + return - Request body for the Seaware system API
public isolated function lockRequestOf(string bookingNumber) returns map<json> => {
    "query": "mutation ReservationLock { reservationLock(input: { key: \"" + gqlText(bookingKeyOf(bookingNumber))
        + "\",duration: \"PT15M\" }) { operationResult clientMutationId result { isLocked keys key id lockInfo { timeout"
        + " inactivityTimeout expires autoExtend lockedBy lockedByMe } } errors { severity advice message code canSave"
        + " onSaveOnly } } }"
};

# ReservationStore with unlock for the booking.
#
# + bookingNumber - Checked booking number
# + return - Request body for the Seaware system API
public isolated function storeRequestOf(string bookingNumber) returns map<json> => {
    "query": "mutation ReservationStore { reservationStore(input: { id: \"Reservation|"
        + gqlText(bookingKeyOf(bookingNumber)) + "\", unlock: true }) { operationResult clientMutationId result { key"
        + " lockInfo { timeout inactivityTimeout expires autoExtend lockedBy lockedByMe } status { key name }"
        + " invoiceTotals { invoiceTotal payments grossDue } transactions { status { key } externalIdent type amount } }"
        + " errors { severity advice message code canSave onSaveOnly } } }"
};

# JSON text without any spaces between members: what the Mule flow stored in Seaware as the card
# server response.
#
# + value - JSON value
# + return - Compact JSON text
public isolated function compactJson(json value) returns string {
    if value is map<json> {
        string[] members = [];
        foreach [string, json] [name, member] in value.entries() {
            members.push(name.toJsonString() + ":" + compactJson(member));
        }
        return "{" + string:'join(",", ...members) + "}";
    }
    if value is json[] {
        string[] items = from json item in value
            select compactJson(item);
        return "[" + string:'join(",", ...items) + "]";
    }
    return value.toJsonString();
}

# The component split saved with the payment session (`extra.extra2` of the session request).
# Accepts the row the DB system API returns: `payload` as JSON text, as `{ value: "<JSON text>" }`
# or as an object. `extra2` itself may be a list or JSON text of a list.
#
# + contextRows - Rows returned for the payment-context select
# + return - The split entries; empty when there is none
public isolated function extra2Of(json contextRows) returns json[] {
    json[] rows = rowsOf(contextRows);
    if rows.length() == 0 {
        return [];
    }
    json stored = fieldOf(rows[0], "payload");
    if stored is map<json> && stored.hasKey("value") {
        stored = stored["value"];
    }
    if stored is string {
        stored = stored.trim() == "" ? () : jsonOfText(stored);
    }
    json extra2 = fieldOf(sessionDocumentOf(stored), "extra", "extra2");
    if extra2 is string {
        extra2 = extra2.trim() == "" ? () : jsonOfText(extra2);
    }
    return extra2 is json[] ? extra2 : [];
}

# TransactionCreate for the paid Telr order. Text identical to the Mule flow; every value that is
# placed inside it is checked or escaped first.
#
# + telrResponse - Telr status answer (stored whole as the card server response)
# + extra2 - Component split, may be empty
# + cardMerchant - Merchant name for this environment
# + return - Request body for the Seaware system API, or an error when a value cannot be used
public isolated function transactionCreateRequestOf(json telrResponse, json[] extra2, string cardMerchant)
        returns map<json>|error {
    json telrOrder = telrOrderOf(telrResponse);
    decimal? amount = decimalOf(fieldOf(telrOrder, "amount"));
    if amount is () {
        return error("The Telr order has no usable amount");
    }
    string currency = textOf(fieldOf(telrOrder, "currency")).trim();
    if !re `[A-Za-z]{3}`.isFullMatch(currency) {
        return error("The Telr order has no usable currency");
    }
    string customerRef = textOf(fieldOf(telrOrder, "customer", "ref"));
    string[] refParts = re `\|`.split(customerRef);
    string clientKey = refParts[refParts.length() - 1].trim();
    if clientKey == "" {
        return error("The Telr order has no customer reference");
    }
    string reservationKey = bookingKeyOf(textOf(fieldOf(telrOrder, "cartid")));
    string telrRef = textOf(fieldOf(telrOrder, "ref"));
    if reservationKey == "" || telrRef == "" {
        return error("The Telr order has no cart id or reference");
    }
    string componentDistr = "";
    if extra2.length() > 0 {
        string[] parts = [];
        foreach json item in extra2 {
            decimal? itemAmount = decimalOf(fieldOf(item, "amount"));
            string paymentCode = textOf(fieldOf(item, "paymentCode"));
            if itemAmount is () || paymentCode == "" {
                return error("The component split saved with this payment is not usable");
            }
            parts.push("{paymentCode: \"" + gqlText(paymentCode) + "\", amount: " + itemAmount.toString() + "}");
        }
        componentDistr = ", componentDistr: [" + string:'join(", ", ...parts) + "]";
    }
    string payment = "{ amount: " + amount.toString() + ", currency: {key: \"" + currency + "\"},"
        + " formOfTransaction: {key: \"Credit Card\"}, comments: \"This transaction was made from TELR website\","
        + " creditCardMerchant: \"" + gqlText(cardMerchant) + "\", creditCardServerResponse: \""
        + gqlText(compactJson(telrResponse)) + "\", creditCardServerType: \"TELR\", externalIdent: \""
        + gqlText(telrRef) + "\", transactionStatus: {key: \"OK\"}, sourceEntity: {key: \"" + gqlText(clientKey)
        + "\",type: Client}, destinationEntity: {key: \"" + gqlText(reservationKey) + "\",type: Reservation} "
        + componentDistr + "}";
    return {
        "query": "mutation TransactionCreate { transactionCreate( input: { payments: { payments: [" + payment
            + "] } } ) { operationResult } }"
    };
}

// ---------------------------------------------------------------------------------------------
// Seaware answers
// ---------------------------------------------------------------------------------------------

# The first error message of a Seaware answer (Mule `payload.errors.message[0]`).
#
# + answer - Seaware answer
# + return - The message, `()` when the answer has no errors
public isolated function firstSeawareError(json answer) returns string? {
    json errors = fieldOf(answer, "errors");
    if errors is json[] && errors.length() > 0 {
        json message = fieldOf(errors[0], "message");
        return message is string ? message : "Seaware returned an error";
    }
    return ();
}

# True when the error means the Seaware session is gone or not allowed (Mule `Seaware_Error_check`).
#
# + message - Seaware error message
# + return - True for a session error
public isolated function isSessionError(string message) returns boolean =>
    message.includes("Session context not found or expired") || message.includes("ManageClients")
        || message.includes("GUID is required") || message.includes("Permission Error: Query is not permitted");

# The session token of a Login answer.
#
# + answer - Seaware answer
# + return - The token, `()` when the login did not return one
public isolated function loginTokenOf(json answer) returns string? {
    json token = fieldOf(answer, "data", "login", "token");
    return token is string && token != "" ? token : ();
}

# True when the stored reservation carries the Telr order reference (Mule "Order Ref Validation").
#
# + storeAnswer - ReservationStore answer
# + orderRef - Telr order reference
# + return - True when the payment is on the reservation
public isolated function storedTransactionFound(json storeAnswer, string orderRef) returns boolean {
    json result = fieldOf(storeAnswer, "data", "reservationStore", "result");
    return hasTransaction(result is json[] ? result : [result], orderRef);
}

# The text returned when the payment is not on the stored reservation.
#
# + storeAnswer - ReservationStore answer
# + orderRef - Telr order reference
# + return - The text; it always ends with "Requires reconciliation."
public isolated function reconciliationMessage(json storeAnswer, string orderRef) returns string {
    json storeErrors = fieldOf(storeAnswer, "data", "reservationStore", "errors");
    if storeErrors is json[] && storeErrors.length() > 0 {
        json warning = fieldOf(storeErrors[0], "message");
        return "Order reference " + orderRef + " not found in Seaware store response. Additionally, Seaware returned"
            + " a warning: " + (warning is string ? warning : "unknown warning") + ". Requires reconciliation.";
    }
    return "Order reference " + orderRef + " not found in Seaware store response. Requires reconciliation.";
}

// ---------------------------------------------------------------------------------------------
// Payment context and attempt audit (DB system API requests)
// ---------------------------------------------------------------------------------------------

# Select of the payment context saved when the Telr session was created.
#
# + orderRef - Telr order reference
# + return - DB system API request
public isolated function contextSelectOf(string orderRef) returns map<json> => {
    "connectionKey": "PG_Guest",
    "operation": "select",
    "query": "SELECT booking_ref, telr_order_ref, payload FROM cs_mule_framework.cs_payment_transaction_context"
        + " WHERE telr_order_ref = :telr_order_ref",
    "params": {"telr_order_ref": orderRef}
};

# Insert of the payment context when a Telr session is requested.
#
# + sessionRequest - Body of POST /sessions
# + return - DB system API request
public isolated function contextInsertOf(json sessionRequest) returns map<json> => {
    "connectionKey": "PG_Guest",
    "operation": "select",
    "query": "WITH ins AS (INSERT INTO cs_mule_framework.cs_payment_transaction_context (booking_ref, telr_order_ref,"
        + " payload) VALUES (:booking_ref, :telr_order_ref, :payload::jsonb) RETURNING payment_context_id)"
        + " SELECT payment_context_id FROM ins",
    "params": {
        "booking_ref": fieldOf(sessionRequest, "order", "cartid"),
        "telr_order_ref": (),
        "payload": compactJson(sessionRequest)
    }
};

# The id of the inserted payment context.
#
# + answer - DB system API answer of the insert
# + return - The id, `()` when there is none
public isolated function contextIdOf(json answer) returns json {
    json[] rows = rowsOf(answer);
    return rows.length() > 0 ? fieldOf(rows[0], "payment_context_id") : ();
}

# Update of the payment context with the Telr order reference.
#
# + contextId - Id returned by the insert
# + telrSessionAnswer - Telr answer of the session request
# + return - DB system API request
public isolated function contextUpdateOf(json contextId, json telrSessionAnswer) returns map<json> => {
    "connectionKey": "PG_Guest",
    "operation": "update",
    "query": "UPDATE cs_mule_framework.cs_payment_transaction_context SET telr_order_ref = :telr_order_ref,"
        + " updated_at = CURRENT_TIMESTAMP WHERE payment_context_id = :payment_context_id",
    "params": {"telr_order_ref": fieldOf(telrSessionAnswer, "order", "ref"), "payment_context_id": contextId}
};

final readonly & [string, string][] ERROR_CODES = [
    ["has already been processed and cannot be processed again", "SW_ALREADY_PROCESSED"],
    ["Requires reconciliation", "SW_RECONCILIATION_REQUIRED"],
    ["Booking number validation failed", "SW_INVALID_BOOKING_NUMBER"],
    ["does not match any expected booking amount in the system", "SW_AMOUNT_MISMATCH"],
    ["Payment is not successful. Current status is Pending", "TELR_PENDING"],
    ["Payment is not successful. Current status is Cancelled", "TELR_CANCELLED"],
    ["Payment is not successful. Current status is Declined", "TELR_DECLINED"],
    ["Payment is not successful. Current status is Replaced", "TELR_REPLACED"],
    ["Payment is not successful. Current status is Expired", "TELR_EXPIRED"],
    ["Payment is not successful. Current status is Payment Requested", "TELR_PAYMENT_REQUESTED"]
];

# The code recorded for a failed attempt (Mule `errorMappings`).
#
# + message - Failure text
# + return - The code, "SW_UNKNOWN" when no rule matches
public isolated function errorCodeOf(string message) returns string {
    foreach [string, string] [text, code] in ERROR_CODES {
        if message.includes(text) {
            return code;
        }
    }
    return "SW_UNKNOWN";
}

isolated function sqlText(string value) returns string => "'" + re `'`.replaceAll(value, "''") + "'";

# Insert of one row in the payment-attempt audit table. Same statement as Mule: the values are
# written into the SQL text, text values between single quotes with quotes doubled.
#
# + input - The request
# + correlationId - Correlation id of the attempt
# + channel - Caller's `client_channel` header, if any
# + httpStatus - Status returned to the caller
# + message - Text returned to the caller
# + errorCode - Code for a failed attempt; `()` on success
# + return - DB system API request
public isolated function auditInsertOf(PaymentInput input, string correlationId, string? channel, int httpStatus,
        string message, string? errorCode) returns map<json> {
    string[] cols = ["booking_no", "telr_ref_no", "attempt_correlation_id"];
    string[] vals = [sqlText(input.bookingNumber), sqlText(input.orderRef), sqlText(correlationId)];
    if channel is string && channel != "" {
        cols.push("source");
        vals.push(sqlText(channel));
    }
    cols.push("status", "http_status");
    vals.push(sqlText(errorCode is () ? "Success" : "Failed"), httpStatus.toString());
    if errorCode is string {
        cols.push("error_code");
        vals.push(sqlText(errorCode));
    }
    cols.push("remarks");
    vals.push(sqlText(message));
    return {
        "connectionKey": "PG_Guest",
        "operation": "insert",
        "query": "INSERT INTO cs_mule_framework.cs_payment_process_attempt_audit (" + string:'join(", ", ...cols)
            + ") VALUES (" + string:'join(", ", ...vals) + ")"
    };
}
