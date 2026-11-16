// Pure helpers of telr-pay-gw-sys-api: the requests sent to Telr. Testable without HTTP.

# Store identity and fixed request values (Mule `stores.*`, `method.*`, `framed`, `order.test`,
# `telr.returnUrls.*`). Telr received all of these as text from Mule, so they stay text.
#
# + storeId - Telr store id
# + authKey - Telr store authentication key
# + sessionsMethod - Value of `method` when a session is created
# + statusMethod - Value of `method` when a status is asked
# + framed - Telr `framed` flag
# + orderTest - Telr test flag: "1" test mode, "0" real payments
# + returnAuthorised - Address the guest returns to after an authorised payment
# + returnDeclined - Address the guest returns to after a declined payment
# + returnCancelled - Address the guest returns to after a cancelled payment
public type TelrStore record {|
    string storeId;
    string authKey;
    string sessionsMethod = "create";
    string statusMethod = "check";
    string framed = "0";
    string orderTest;
    string returnAuthorised;
    string returnDeclined;
    string returnCancelled;
|};

# True while a backend address is still the generator's placeholder.
#
# + url - Configured address
# + return - True when it is empty or points at localhost
public isolated function isPlaceholderAddress(string url) returns boolean {
    string u = url.trim().toLowerAscii();
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

# The part of a caller's body that holds `order` and `customer`: the body itself, or its
# `session` member when the caller wrapped it.
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

# The "create session" request sent to Telr (Mule transform "Session Request").
# Fields the caller did not send are sent as null, as Mule did.
#
# + payload - Caller's body
# + store - Store settings
# + return - The Telr request, or an error when the body has no order
public isolated function sessionRequestOf(json payload, TelrStore store) returns map<json>|error {
    json doc = sessionDocumentOf(payload);
    if !(fieldOf(doc, "order") is map<json>) {
        return error("order is required");
    }
    return {
        "method": store.sessionsMethod,
        "store": store.storeId,
        "authkey": store.authKey,
        "framed": store.framed,
        "order": {
            "cartid": fieldOf(doc, "order", "cartid"),
            "test": store.orderTest,
            "amount": fieldOf(doc, "order", "amount"),
            "currency": fieldOf(doc, "order", "currency"),
            "description": fieldOf(doc, "order", "description"),
            "trantype": fieldOf(doc, "order", "trantype")
        },
        "return": {
            "authorised": store.returnAuthorised,
            "declined": store.returnDeclined,
            "cancelled": store.returnCancelled
        },
        "customer": {
            "ref": fieldOf(doc, "customer", "ref"),
            "email": fieldOf(doc, "customer", "email"),
            "name": {
                "title": fieldOf(doc, "customer", "name", "title"),
                "forenames": fieldOf(doc, "customer", "name", "forenames"),
                "surname": fieldOf(doc, "customer", "name", "surname")
            },
            "address": {
                "line1": fieldOf(doc, "customer", "address", "line1"),
                "line2": fieldOf(doc, "customer", "address", "line2"),
                "line3": fieldOf(doc, "customer", "address", "line3"),
                "city": fieldOf(doc, "customer", "address", "city"),
                "state": fieldOf(doc, "customer", "address", "state"),
                "country": fieldOf(doc, "customer", "address", "country"),
                "areacode": fieldOf(doc, "customer", "address", "areacode")
            },
            "phone": fieldOf(doc, "customer", "phone")
        },
        "extra": {
            "extra1": fieldOf(doc, "extra", "extra1"),
            "extra2": fieldOf(doc, "extra", "extra2"),
            "extra3": fieldOf(doc, "extra", "extra3")
        }
    };
}

# The "check status" request sent to Telr (Mule transform "Status Request").
#
# + payload - Caller's body, `{ orderRef }`
# + store - Store settings
# + return - The Telr request, or an error when `orderRef` is missing
public isolated function statusRequestOf(json payload, TelrStore store) returns map<json>|error {
    json orderRef = fieldOf(payload, "orderRef");
    if orderRef is () || (orderRef is string && orderRef.trim() == "") {
        return error("orderRef is required");
    }
    return {
        "method": store.statusMethod,
        "store": store.storeId,
        "authkey": store.authKey,
        "order": {"ref": orderRef}
    };
}
