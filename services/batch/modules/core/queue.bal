import ballerina/log;
import ballerina/uuid;

isolated function localName(xml:Element e) returns string {
    string name = e.getName();
    int? brace = name.lastIndexOf("}");
    name = brace is int ? name.substring(brace + 1) : name;
    int? colon = name.indexOf(":");
    return colon is int ? name.substring(colon + 1) : name;
}

isolated function child(xml:Element? parent, string name) returns xml:Element? {
    if parent is xml:Element {
        foreach var item in parent.getChildren() {
            if item is xml:Element && localName(item) == name {
                return item;
            }
        }
    }
    return ();
}

isolated function find(xml doc, string name) returns xml:Element? {
    foreach var item in doc {
        if item is xml:Element {
            if localName(item) == name {
                return item;
            }
            xml:Element? inner = find(item.getChildren(), name);
            if inner is xml:Element {
                return inner;
            }
        }
    }
    return ();
}

isolated function value(xml:Element? root, string... path) returns json {
    xml:Element? cur = root;
    foreach string name in path {
        cur = child(cur, name);
    }
    if cur is xml:Element {
        string content = cur.data().trim();
        return content == "" ? () : content;
    }
    return ();
}

# The reservation header inside a queue message.
#
# + content - The message as received: JSON with the Seaware notification (XML) under `subscription.message`
# + return - The `ResHeader` element, or an error when the message has a different shape
public isolated function reservationHeader(string content) returns xml:Element|error {
    json message = check content.fromJsonString();
    string? notification = text(f(message, "subscription", "message"));
    if notification is () || notification.trim() == "" {
        return error("the queue message has no subscription.message");
    }
    xml:Element? header = find(check xml:fromString(notification), "ResHeader");
    return header ?: error("the queue message has no reservation header");
}

# The reservation write for a queue message.
#
# + header - The reservation header
# + return - Request body
public isolated function queueReservationRequest(xml:Element header) returns json {
    json resId = value(header, "ResID");
    return upsertBody([
                {
                    "Agency_ID": value(header, "AgencyID"),
                    "Balance_Due": value(header, "InvoiceTotals", "CurrentDue", "AmountDue"),
                    "Currency": value(header, "Currency"),
                    "Due_Date": dateOnly(value(header, "InvoiceTotals", "CurrentDue", "DueDate")),
                    "Invoice_Total": value(header, "InvoiceTotals", "InvoiceTotal"),
                    "Account_Name": resId is () ? () : "Reservation|" + textOr(resId, ""),
                    "Account_Number": resId,
                    "Reservation_Status": value(header, "ResStatus"),
                    "Reservation_Version": value(header, "Version"),
                    "Reservation_Created_On": value(header, "InitialDate"),
                    "Reservation_Last_Updated": value(header, "LastUpdatedAt"),
                    "Agency_key": value(header, "AgencyID")
                }
            ], "Account_Name");
}

# The invoice write for a queue message.
#
# + header - The reservation header
# + reservationId - CRM id of the reservation written just before
# + return - Request body
public isolated function queueInvoiceRequest(xml:Element header, json reservationId) returns json {
    json paidInFull = value(header, "InvoiceTotals", "IsPaidInFull");
    json amountDue = value(header, "InvoiceTotals", "CurrentDue", "AmountDue");
    return upsertBody([
                {
                    "Name": value(header, "LastInvoice", "InvoiceID"),
                    "Currency": value(header, "Currency"),
                    "Invoice_Number": value(header, "LastInvoice", "InvoiceID"),
                    "Reservation_Name": {"id": reservationId},
                    "Total_Invoice": value(header, "InvoiceTotals", "InvoiceTotal"),
                    "Due_Date": dateOnly(value(header, "InvoiceTotals", "CurrentDue", "DueDate")),
                    "Balance_Due": amountDue is () ? "0" : amountDue,
                    "Due_Type": value(header, "InvoiceTotals", "CurrentDue", "DueType"),
                    "Payment_Schedule": [
                        {
                            "Paid": paidInFull == "Y" ? true : (paidInFull == "N" ? false : ()),
                            "Payment_Amount_Paid": value(header, "InvoiceTotals", "NetDue")
                        }
                    ],
                    "Payment_Received": [{"Payment_Amount_Paid": value(header, "InvoiceTotals", "InvoicePaid")}]
                }
            ], "Name");
}

# The queue job: one Seaware reservation notification in, reservation and invoice written to the CRM.
public isolated class QueueWork {
    private final Backend zoho;
    private final readonly & CrmPaths paths;

    # + zoho - CRM system service
    # + paths - CRM paths
    public isolated function init(Backend zoho, CrmPaths paths) {
        self.zoho = zoho;
        self.paths = paths.cloneReadOnly();
    }

    # Handles one message: reservation, invoice, then the reservation again (as the old flow did).
    #
    # + content - The message text
    # + return - An error when the message cannot be read or the CRM cannot be reached
    public isolated function process(string content) returns error? {
        string correlationId = uuid:createType4AsString();
        xml:Element header = check reservationHeader(content);
        json reservation = queueReservationRequest(header);
        json first = check crmWrite(self.zoho, "POST", self.paths.reservations, reservation, correlationId, "reservation : ", true, 1);
        json reservationId = f(at(f(first, "data"), 0), "details", "id");
        json invoice = check crmWrite(self.zoho, "POST", self.paths.invoices, queueInvoiceRequest(header, reservationId),
                correlationId, "invoice : ", true, 1);
        json second = check crmWrite(self.zoho, "POST", self.paths.reservations, reservation, correlationId, "reservation : ", true, 1);
        log:printInfo("Seaware queue message written to the CRM", correlationId = correlationId,
                reservation = textOr(f(at(f(second, "data"), 0), "status"), "unknown"),
                invoice = textOr(f(at(f(invoice, "data"), 0), "status"), "unknown"));
    }
}
