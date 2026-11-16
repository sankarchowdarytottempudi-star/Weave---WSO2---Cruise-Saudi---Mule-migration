// What is sent to the CRM and the guest service for a block of Otalio guest rows, and which
// refused records are reported. Pure functions: no calls are made here.

const OWNER = "Otalio";

isolated function orEmpty(json v) returns json => v is () ? "" : v;

isolated function quoteSwap(json reason) returns json => reason is string ? re `'`.replaceAll(reason, "\"") : reason;

# true when an answer entry says "error" anywhere inside it.
#
# + entry - Answer entry
# + return - true for a refusal
public isolated function hasError(json entry) returns boolean => deep(entry, "status").indexOf("error") !is ();

isolated function isDuplicate(json entry) returns boolean => deep(entry, "code").indexOf("DUPLICATE_DATA") !is ();

# The CRM id in an answer entry: the record that already existed, otherwise the one written.
#
# + entry - Answer entry
# + return - Id or ()
public isolated function recordId(json entry) returns json {
    json existing = f(entry, "details", "duplicate_record", "id");
    return blank(existing) ? f(entry, "details", "id") : existing;
}

# Lines up what the CRM answered with the records that were sent.
#
# + data - The `data` list of the answer
# + count - Records sent
# + return - One entry per record. No answer at all gives "No content" errors; a refusal with
# fewer entries than records is repeated for the records it does not name.
public isolated function aligned(json data, int count) returns json[] {
    json[] entries = items(data);
    json[] out = [];
    foreach int i in 0 ..< count {
        if entries.length() == 0 {
            out.push({"status": "error", "message": "No content (204)"});
        } else if i < entries.length() {
            out.push(entries[i]);
        } else {
            out.push(hasError(entries[0]) ? entries[0] : ());
        }
    }
    return out;
}

# One row for the error table.
#
# + b - The block
# + row - The guest row the failure belongs to
# + module - Which step failed
# + reason - Why it failed
# + code - Error code
# + fallbackCode - Used when no code was given
# + extra - Further columns, placed before `batch_job_name`
# + return - The row
public isolated function errorRow(Block b, json row, string module, json reason, json code, int fallbackCode,
        map<json> extra = {}) returns map<json> {
    map<json> out = {
        "reservation_number": f(row, "booking_number"),
        "correlation_id": b.correlationId,
        "cabin_number": f(row, "Cabin_Code"),
        "source_system": OWNER,
        "module_name": module,
        "package_name": orEmpty(f(row, "cruise_product")),
        "client_id": orEmpty(f(row, "clientId")),
        "profile_id": f(row, "profile_id")
    };
    foreach [string, json] [key, value] in extra.entries() {
        out[key] = value;
    }
    out["batch_job_name"] = b.jobName;
    out["failure_reason"] = quoteSwap(reason);
    out["error_code"] = code is () ? fallbackCode : code;
    return out;
}

// ---------------------------------------------------------------- what the read phase reports

# Booking numbers that are not plain digits are reported and left out.
#
# + bookings - Rows of the changed-bookings query
# + return - [rows to carry on with, rows left out]
public isolated function splitBookings(json[] bookings) returns [json[], json[]] {
    json[] good = [];
    json[] bad = [];
    foreach json b in bookings {
        if re `^\d+$`.isFullMatch(textOr(f(b, "booking_number"), "")) {
            good.push(b);
        } else {
            bad.push(b);
        }
    }
    return [good, bad];
}

# Error rows for booking numbers that were left out.
#
# + bad - Rows left out
# + correlationId - Run id
# + jobName - Written to the rows
# + return - Rows
public isolated function invalidBookingRows(json[] bad, string correlationId, string jobName) returns map<json>[] {
    return from json item in bad
        select {
            "correlation_id": correlationId,
            "reservation_number": f(item, "booking_number"),
            "source_system": OWNER,
            "batch_job_name": jobName,
            "module_name": "Reservation",
            "profile_id": orEmpty(f(item, "profile_id")),
            "cabin_number": orEmpty(f(item, "Cabin_Code")),
            "client_id": orEmpty(f(item, "clientId")),
            "failure_reason": "Invalid booking_number: " + textOr(f(item, "booking_number"), ""),
            "error_code": 455
        };
}

# A list of values as SQL text: `'a','b'`; `''` for an empty list.
#
# + values - Values
# + return - Text for an IN list
public isolated function sqlList(json[] values) returns string {
    string[] parts = from json v in values where v !is () select "'" + textOr(v, "") + "'";
    return parts.length() == 0 ? "''" : string:'join(",", ...parts);
}

# Puts the revenue rows and the spend transactions (with their items) on the guest rows they belong to.
#
# + rows - Guest rows
# + revenue - Revenue rows (`payer_id` = row id)
# + transactions - Spend transactions (`buyerAccountId` = row id)
# + postingItems - Spend items (`posting_id` = transaction id)
# + return - The rows with `revenue` and `transactions`
public isolated function attach(json[] rows, json[] revenue, json[] transactions, json[] postingItems) returns json[] {
    json[] withItems = [];
    foreach json t in transactions {
        map<json> copy = mutableCopy(t);
        copy["items"] = from json item in postingItems where f(item, "posting_id") == f(t, "id") && f(t, "id") !is () select item;
        withItems.push(copy);
    }
    json[] out = [];
    foreach json row in rows {
        map<json> copy = mutableCopy(row);
        json id = f(row, "id");
        copy["revenue"] = from json r in revenue where id !is () && f(r, "payer_id") == id select r;
        copy["transactions"] = from json t in withItems where id !is () && f(t, "buyerAccountId") == id select t;
        out.push(copy);
    }
    return out;
}

# Search text for the reservations the CRM already has for these bookings.
#
# + rows - Guest rows
# + return - Search text
public isolated function accountCriteria(json[] rows) returns string {
    string[] numbers = from json n in unique(from json row in rows let json n = f(row, "booking_number") where n !is () select n)
        select textOr(n, "");
    return "(Account_Name:in:" + string:'join(",", ...numbers) + ")";
}

isolated function mutableCopy(json v) returns map<json> {
    map<json> out = {};
    if v is map<json> {
        foreach [string, json] [key, value] in v.entries() {
            out[key] = value;
        }
    }
    return out;
}

isolated function packageId(json raw) returns string {
    string value = textOr(raw, "");
    if value.includes("|") {
        string[] parts = re `\|`.split(value);
        return parts.length() > 1 ? parts[1] : "";
    }
    return value;
}

# Differences between Otalio and the CRM that are only reported: a booking checked out in Otalio
# but cancelled in the CRM, and a voyage package that is missing in Otalio or differs from the CRM's.
#
# + rows - Guest rows
# + accounts - The CRM reservations for these bookings
# + correlationId - Run id
# + jobName - Written to the rows
# + return - Rows for the error table
public isolated function mismatchRows(json[] rows, json[] accounts, string correlationId, string jobName)
        returns map<json>[] {
    map<json>[] out = [];
    foreach json account in accounts {
        string crmBooking = textOr(f(account, "Account_Number"), "");
        string crmStatus = textOr(f(account, "Reservation_Status"), "");
        string crmPackage = packageId(f(account, "Package_ID"));
        foreach json row in rows {
            if textOr(f(row, "booking_number"), "") != crmBooking {
                continue;
            }
            string dbStatus = textOr(f(row, "reservation_status_id"), "");
            string dbPackage = textOr(f(row, "cruise_product"), "");
            if dbStatus == "CHECKED_OUT" && (crmStatus == "CANCELED" || crmStatus == "Cancelled") {
                out.push(mismatch(correlationId, jobName, "Reservation", f(row, "booking_number"), row,
                        orEmpty(f(row, "Cabin_Code")), dbStatus, crmStatus));
            }
            if dbPackage == "" || (crmPackage != "" && dbPackage != crmPackage) {
                out.push(mismatch(correlationId, jobName, "Voyage", f(account, "Account_Number"), row, "", dbPackage,
                        crmPackage));
            }
        }
    }
    return out;
}

isolated function mismatch(string correlationId, string jobName, string module, json reservation, json row, json cabin,
        string otalioValue, string crmValue) returns map<json> => {
    "correlation_id": correlationId,
    "reservation_number": reservation,
    "source_system": OWNER,
    "batch_job_name": jobName,
    "module_name": module,
    "profile_id": orEmpty(f(row, "profile_id")),
    "cabin_number": cabin,
    "package_name": orEmpty(f(row, "cruise_product")),
    "client_id": orEmpty(f(row, "clientId")),
    "failure_reason": "Otalio: " + otalioValue + ", CRM: " + crmValue,
    "error_code": 455
};

// ---------------------------------------------------------------- reservations

# The reservation records for a block, one per guest row. The link to the voyage is added once
# the voyage step has answered (the step runs first and last in every block).
#
# + b - The block
# + return - Records
public isolated function reservationRecords(Block b) returns json[] {
    json[] out = [];
    foreach int i in 0 ..< b.rows.length() {
        json number = f(b.rows[i], "booking_number");
        map<json> rec = {"Account_Name": "Reservation|" + textOr(number, ""), "Account_Number": number};
        json voyageId = recordId(at(b.voyageData, i));
        if !blank(voyageId) {
            rec["Voyage"] = {"id": voyageId};
        }
        out.push(rec);
    }
    return out;
}

# A CRM write: records, the field that makes a record unique, and whether CRM workflows run.
#
# + data - Records
# + checkField - Field the CRM uses to find an existing record
# + workflow - true to trigger CRM workflows
# + return - Request body
public isolated function upsertBody(json[] data, string checkField, boolean workflow) returns json {
    map<json> body = {"data": data, "duplicate_check_fields": [checkField]};
    if workflow {
        body["trigger"] = ["workflow"];
    }
    return body;
}

# Error rows for records a step's write refused; "already there" does not count as refused.
#
# + b - The block
# + module - Step name for the error table
# + answers - Per row: the CRM's answer entry
# + return - Rows
public isolated function refusedRows(Block b, string module, json[] answers) returns map<json>[] {
    map<json>[] out = [];
    foreach int i in 0 ..< b.rows.length() {
        json entry = at(answers, i);
        if hasError(entry) && !isDuplicate(entry) {
            out.push(errorRow(b, b.rows[i], module, at(deep(entry, "message"), 0), at(deep(entry, "errorCode"), 0), 400));
        }
    }
    return out;
}

// ---------------------------------------------------------------- guests

isolated function dateText(json v) returns json => blank(v) ? () : dateOnly(v);

# The guest service request: one entry per guest row.
#
# + rows - Guest rows
# + return - Entries
public isolated function guestRequest(json[] rows) returns json[] {
    json[] out = [];
    foreach json row in rows {
        json phone = f(row, "phone_number");
        PhoneParts parts = splitPhone(phone is string ? phone : ());
        string method = textOr(f(row, "preferred_communication_method"), "");
        map<json> entry = {
            "firstName": f(row, "first_name"),
            "lastName": f(row, "last_name"),
            "dateOfBirth": f(row, "dateOfBirth"),
            "email": f(row, "email"),
            "nationalityName": f(row, "nationality"),
            "intlCode": parts.valid ? parts.countryCode : "",
            "phone": parts.valid ? parts.number : "",
            "clientId": f(row, "clientId"),
            "mailingCity": f(row, "city"),
            "addressType": f(row, "address_type_cd"),
            "mailingStreet": f(row, "street_1"),
            "mailingStreet2": f(row, "street_2"),
            "mailingStreet3": f(row, "street_3"),
            "mailingState": f(row, "STATE"),
            "mailingZip": f(row, "zip_code"),
            "mailingCountry": f(row, "country"),
            "profileId": f(row, "profile_id"),
            "accountType": f(row, "account_type"),
            "documentNumber": f(row, "document_nr"),
            "documentType": f(row, "document_type"),
            "visaType": f(row, "visa_type"),
            "issueCountry": f(row, "issue_country"),
            "issueDate": dateText(f(row, "issue_date")),
            "expirationDate": dateText(f(row, "expiry_date")),
            "issuePlace": f(row, "issue_place"),
            "birthPlace": f(row, "birth_place"),
            "validFrom": f(row, "valid_from"),
            "issueAuthority": f(row, "issue_authority"),
            "countryId": f(row, "country_id"),
            "marketingConsent": f(row, "marketing_consent"),
            "onboard": f(row, "onboard")
        };
        json primary = f(row, "is_primary_document");
        if !blank(primary) {
            string flag = textOr(primary, "");
            entry["isPrimaryDocument"] = flag == "1" ? true : (flag == "0" ? false : ());
        }
        entry["externalId"] = f(row, "external_id");
        entry["boardCardId"] = f(row, "board_card_id");
        entry["bookingNumber"] = f(row, "booking_number");
        entry["preferredCommunicationEmail"] = method == "E_MAIL";
        entry["preferredCommunicationPhone"] = method == "PHONE";
        out.push(entry);
    }
    return out;
}

# The guest service's refusal, shaped like its normal answer: one entry per guest.
#
# + answer - The refusal
# + guestCount - Guests in the request
# + return - Entries
public isolated function guestRefusal(Answer answer, int guestCount) returns json[] {
    json entry;
    if answer.unreadable {
        entry = {"status": "error", "errorCode": 500, "message": answer.failure};
    } else {
        string? apiName = text(f(answer.body, "details", "api_name"));
        string? message = text(f(answer.body, "message"));
        entry = {
            "status": "error",
            "errorCode": 400,
            "message": apiName is string && apiName != "" ? apiName + "-" + (message ?: "") : (message ?: answer.failure)
        };
    }
    return from int i in 0 ..< guestCount select entry;
}

# Error rows for guests the guest service refused.
#
# + b - The block, after the guest step
# + return - Rows
public isolated function guestErrors(Block b) returns map<json>[] {
    map<json>[] out = [];
    foreach int i in 0 ..< b.rows.length() {
        json entry = at(b.guestAnswers, i);
        if hasError(entry) {
            out.push(errorRow(b, b.rows[i], "Guest", at(deep(entry, "message"), 0), at(deep(entry, "errorCode"), 0), 500));
        }
    }
    return out;
}

// ---------------------------------------------------------------- reservation-to-guest links

# CRM ids of the reservations written in this block (to look up their existing guest links).
#
# + b - The block
# + return - Ids, each once
public isolated function reservationIds(Block b) returns json[] {
    json[] ids = [];
    foreach json entry in b.reservationData {
        ids.push(...items(f(deep(entry, "details"), "id")));
    }
    return unique(ids);
}

# Which reservation-to-guest links to create, keep active, or switch off.
#
# Every guest row whose guest the guest service knows gets an active link to its reservation.
# Links the CRM already has for these reservations but that are not among them are set inactive.
#
# + b - The block, after the reservation and guest steps
# + existing - Links the CRM already has for these reservations
# + return - Request bodies, one link each, grouped by reservation
public isolated function linkingPlan(Block b, json[] existing) returns LinkingPlan {
    map<json> present = {};
    string[] presentKeys = [];
    foreach json e in existing {
        string key = textOr(f(e, "Reservation_Names", "id"), "") + "|" + textOr(f(e, "Guest_Names", "id"), "");
        if !present.hasKey(key) {
            present[key] = e;
            presentKeys.push(key);
        }
    }
    string[] wantedKeys = [];
    string[] sequence = [];
    map<json[]> creates = {};
    map<json[]> updates = {};
    foreach int i in 0 ..< b.rows.length() {
        json guestId = f(at(b.guestAnswers, i), "zohoId");
        json reservationId = recordId(at(b.reservationData, i));
        if blank(guestId) || blank(reservationId) {
            continue;
        }
        string key = textOr(reservationId, "") + "|" + textOr(guestId, "");
        wantedKeys.push(key);
        map<json> rec = {
            "Reservation_Names": {"id": reservationId},
            "Guest_Names": {"id": guestId},
            "Reservation_Status_Otalio": f(b.rows[i], "reservation_status_id"),
            "Active_Inactive": "Active",
            "Modified_By_System": OWNER
        };
        if present.hasKey(key) {
            rec["id"] = f(present[key], "id");
            addTo(updates, sequence, textOr(reservationId, ""), rec);
        } else {
            addTo(creates, sequence, textOr(reservationId, ""), rec);
        }
    }
    foreach string key in presentKeys {
        if wantedKeys.indexOf(key) !is () {
            continue;
        }
        json e = present[key];
        addTo(updates, sequence, textOr(f(e, "Reservation_Names", "id"), ""), {
            "Reservation_Names": {"id": f(e, "Reservation_Names", "id")},
            "Guest_Names": {"id": f(e, "Guest_Names", "id")},
            "Active_Inactive": "Inactive",
            "Modified_By_System": OWNER,
            "id": f(e, "id")
        });
    }
    LinkingPlan plan = {};
    foreach string reservationId in sequence {
        foreach json rec in unique(creates[reservationId] ?: []) {
            plan.creates.push({"data": [rec]});
        }
    }
    foreach string reservationId in sequence {
        foreach json rec in unique(updates[reservationId] ?: []) {
            plan.updates.push({"data": [rec]});
        }
    }
    return plan;
}

isolated function addTo(map<json[]> groups, string[] sequence, string key, json rec) {
    json[]? list = groups[key];
    if list is json[] {
        list.push(rec);
    } else {
        groups[key] = [rec];
    }
    if sequence.indexOf(key) is () {
        sequence.push(key);
    }
}

// ---------------------------------------------------------------- voyage look-up by dates

isolated function datePart(json v) returns string {
    string[] parts = re `T`.split(textOr(v, ""));
    return parts.length() > 0 ? parts[0] : "";
}

isolated function dateRange(string fieldName, string date) returns string =>
    fieldName + " between '" + date + "T00:00:00-00:00' and '" + date + "T23:59:59-00:00'";

isolated function buildWhere(string[] expressions) returns string {
    if expressions.length() == 0 {
        return "";
    }
    if expressions.length() == 1 {
        return expressions[0];
    }
    return "(" + expressions[0] + " OR (" + buildWhere(expressions.slice(1)) + "))";
}

# The CRM queries that find the voyages sailing on the rows' dates (12 date pairs per query).
#
# + rows - Guest rows
# + return - Request bodies for the CRM query endpoint
public isolated function voyageDateQueries(json[] rows) returns json[] {
    json[] pairs = [];
    foreach json row in rows {
        if blank(f(row, "scheduled_embarkation_date")) || blank(f(row, "scheduled_disembarkation_date")) {
            continue;
        }
        pairs.push([datePart(f(row, "scheduled_disembarkation_date")), datePart(f(row, "scheduled_embarkation_date"))]);
    }
    json[] out = [];
    foreach json[] group in chunks(unique(pairs), 12) {
        string[] expressions = from json pair in group
            select "(" + dateRange("Arrival_Date_and_Time", textOr(at(pair, 0), "")) + " AND "
                + dateRange("Departure_Date_and_Time", textOr(at(pair, 1), "")) + ")";
        out.push({
            "select_query": "select Arrival_Date_and_Time,Departure_Date_and_Time,Package_Key from Voyages where "
                + buildWhere(expressions)
                + " and Package_Key is not null group by Package_Key,Departure_Date_and_Time,Arrival_Date_and_Time"
        });
    }
    return out;
}

# The voyages the CRM found, reduced to dates and package key.
#
# + found - Records from the CRM queries
# + return - `{Arrival_Date, Departure_Date, Package_Key}`, complete ones only, each once
public isolated function crmVoyages(json[] found) returns json[] {
    json[] out = [];
    foreach json v in found {
        string arrival = datePart(f(v, "Arrival_Date_and_Time"));
        string departure = datePart(f(v, "Departure_Date_and_Time"));
        json key = f(v, "Package_Key");
        if arrival != "" && departure != "" && !blank(key) {
            out.push({"Arrival_Date": arrival, "Departure_Date": departure, "Package_Key": key});
        }
    }
    return unique(out);
}

# The voyage package of a guest row: the CRM voyage sailing on the row's dates when there is
# exactly one, otherwise the package named in Otalio.
#
# + b - The block, after the voyage look-up
# + row - Guest row
# + return - Package key
public isolated function packageKey(Block b, json row) returns json {
    string arrival = datePart(f(row, "scheduled_disembarkation_date"));
    string departure = datePart(f(row, "scheduled_embarkation_date"));
    json[] matches = from json v in b.crmVoyages
        where arrival != "" && f(v, "Arrival_Date") == arrival && f(v, "Departure_Date") == departure
        select v;
    json key = matches.length() == 1 ? f(matches[0], "Package_Key") : ();
    return blank(key) ? f(row, "cruise_product") : key;
}

// ---------------------------------------------------------------- spend transactions and items

# The spend transactions of one guest row.
#
# + b - The block, after the reservation, guest and voyage look-up steps
# + index - Position of the row in the block
# + return - Records (none when the guest has no transactions)
public isolated function spendRecords(Block b, int index) returns json[] {
    json row = b.rows[index];
    json voyage = packageKey(b, row);
    json guestId = f(at(b.guestAnswers, index), "zohoId");
    json reservationId = recordId(at(b.reservationData, index));
    string prefix = textOr(f(row, "booking_number"), "") + "|" + textOr(f(row, "clientId"), "") + "|";
    return from json t in items(f(row, "transactions"))
        select {
            "Business_Date": f(t, "businessDate"),
            "Buyer_Account_Type": f(t, "buyerAccountType"),
            "Check_ID": f(t, "checkId"),
            "Check_Number": f(t, "check_number"),
            "Comments": f(t, "comments"),
            "Currency": f(t, "currencyCode"),
            "Main_Department": f(t, "mainDepartmentDescription"),
            "Non_Refundable": f(t, "nonRefundCredit"),
            "Posting_Created": f(t, "postingCreatedDate"),
            "Posting_Updated": f(t, "postingUpdatedDate"),
            "Ship": f(t, "shipName"),
            "Voyage": voyage,
            "Guest_Otalio_ID": f(t, "profile_id"),
            "Reservation_Otalio_ID": f(t, "buyerAccountId"),
            "Posting_ID": f(t, "id"),
            "Transaction_Type": f(t, "transactionType"),
            "Main_Department_Description": f(t, "mainDepartmentDescription"),
            "Main_Department_Id": f(t, "mainDepartmentId"),
            "Settlement_Status": f(t, "settlementStatus"),
            "Settlement_Date_Time": f(t, "settlementDateTime"),
            "Settlement_Amount": f(t, "settlementAmount"),
            "Settlement_Id": f(t, "settlementId"),
            "Name": prefix + textOr(f(t, "id"), ""),
            "Guest_Seaware_Info": {"id": guestId},
            "Reservation_Seaware_Info": {"id": reservationId}
        };
}

# Error rows for spend transactions the CRM refused.
#
# + b - The block, after the spend transaction step
# + return - Rows
public isolated function spendErrors(Block b) returns map<json>[] {
    map<json>[] out = [];
    foreach int i in 0 ..< b.rows.length() {
        json[] transactions = items(f(b.rows[i], "transactions"));
        foreach int t in 0 ..< transactions.length() {
            json entry = i < b.spendAnswers.length() ? at(b.spendAnswers[i], t) : ();
            if hasError(entry) {
                map<json> row = errorRow(b, b.rows[i], "Spend Transactions", at(deep(entry, "message"), 0),
                        at(deep(entry, "errorCode"), 0), 400, {"posting_id": f(transactions[t], "id")});
                row["profile_id"] = f(transactions[t], "profile_id");
                out.push(row);
            }
        }
    }
    return out;
}

# The spend items of every transaction in the block, each linked to its transaction in the CRM.
#
# + b - The block, after the spend transaction step
# + return - One group per transaction that has items to write
public isolated function spendItemGroups(Block b) returns ItemGroup[] {
    ItemGroup[] out = [];
    foreach int i in 0 ..< b.rows.length() {
        json[] transactions = items(f(b.rows[i], "transactions"));
        foreach int t in 0 ..< transactions.length() {
            json transactionId = recordId(i < b.spendAnswers.length() ? at(b.spendAnswers[i], t) : ());
            json[] sourceItems = from json item in items(f(transactions[t], "items")) where !blank(f(item, "id")) select item;
            if sourceItems.length() == 0 {
                continue;
            }
            json[] records = from json item in sourceItems
                select {
                    "Amount": f(item, "subDepartmentAmount"),
                    "Article_Description": f(item, "articleDescription"),
                    "Article_ID": f(item, "articleId"),
                    "Count": f(item, "postingCount"),
                    "Created_Timestamp": f(item, "createdDateTime"),
                    "Discount_Amount": f(item, "discountAmount"),
                    "On_Board_Currency": f(item, "onboardCurrency"),
                    "Package_Amount": f(item, "packageAmount"),
                    "Posting_Code": f(item, "postingCode"),
                    "Posting_Description": f(item, "postingDescription"),
                    "Posting_Detail_ID_PK": f(item, "posting_id"),
                    "Posting_Type": f(item, "postingType"),
                    "Name": f(item, "id"),
                    "Sub_Department": f(item, "subDepartmentDescription"),
                    "Tax_Total": f(item, "addonTaxTotal"),
                    "Transaction_ID": f(item, "transactionId"),
                    "Updated_Timestamp": f(item, "updatedDateTime"),
                    "VAT_Total": f(item, "vatTotal"),
                    "Folio_Number": f(item, "folio_number"),
                    "New_Payer_ID": f(item, "newPayerId"),
                    "Source_Posting_ID_Link": f(item, "sourcePostingIdLink"),
                    "Posting_Before_ID": f(item, "postingBeforeId"),
                    "Is_Posting_Closed": f(item, "isPostingClosed"),
                    "Checks_Package_ID": f(item, "checksPackageId"),
                    "Package_Description": f(item, "packageDescription"),
                    "Check_Total": f(item, "checkTotal"),
                    "Pkg_Payment_Sub_Dep_Entity_ID": f(item, "pkgPaymentSubDepEntityId"),
                    "Pkg_Payment_Sub_Department_Description": f(item, "pkgPaymentSubDeptDesc"),
                    "Is_Deposit": f(item, "isDeposit"),
                    "Payer_Account_Type": f(item, "payerAccountType"),
                    "Payer_ID": f(item, "payerId"),
                    "Spend_Transaction": {"id": transactionId}
                };
            out.push({row: b.rows[i], sourceItems, records});
        }
    }
    return out;
}

# Error rows for spend items the CRM refused.
#
# + b - The block
# + g - The items of one transaction
# + answers - The CRM's answer entries, one per item
# + return - Rows
public isolated function spendItemErrors(Block b, ItemGroup g, json[] answers) returns map<json>[] {
    map<json>[] out = [];
    foreach int i in 0 ..< g.sourceItems.length() {
        json entry = at(answers, i);
        if hasError(entry) {
            out.push(errorRow(b, g.row, "Spend Articles", at(deep(entry, "message"), 0), at(deep(entry, "errorCode"), 0),
                    400, {"posting_id": f(g.sourceItems[i], "posting_id"), "article_id": f(g.sourceItems[i], "id")}));
        }
    }
    return out;
}

// ---------------------------------------------------------------- cabins

# Booking numbers whose CRM cabins are looked up.
#
# + rows - Guest rows
# + return - Booking numbers, each once
public isolated function cabinBookings(json[] rows) returns json[] =>
    unique(from json row in rows let json n = f(row, "booking_number") where n !is () select n);

# The cabin records for a block: one active record per guest row, and an "Inactive" record for
# every cabin the CRM has for these bookings that Otalio no longer lists. Grouped by booking.
#
# + b - The block, after the reservation, guest and voyage look-up steps
# + existing - Cabins the CRM has for the block's bookings
# + return - One group per booking
public isolated function cabinGroups(Block b, json[] existing) returns Group[] {
    json[] records = [];
    string[] names = [];
    foreach int i in 0 ..< b.rows.length() {
        json row = b.rows[i];
        string name = textOr(f(row, "booking_number"), "") + "|" + textOr(f(row, "clientId"), "") + "|"
            + textOr(f(row, "Cabin_Code"), "");
        names.push(name);
        records.push({
            "Name": name,
            "Cabin_Number": f(row, "Cabin_Code"),
            "Package_Key": packageKey(b, row),
            "Cabin_Type": f(row, "description"),
            "Pax_ID": f(row, "profile_id"),
            "Assigned_Deck": f(row, "assigned_deck"),
            "Assigned_Cabin_Category": f(row, "assigned_cabin_category"),
            "Assigned_Category_Name": f(row, "description"),
            "Reservation_ID": f(row, "id"),
            "Profile_ID": f(row, "profile_id"),
            "Board_Card_ID": f(row, "board_card_id"),
            "Credit_Total": at(f(row, "revenue", "credit_total"), 0),
            "Debit_Total": at(f(row, "revenue", "debit_total"), 0),
            "Current_Balance": at(f(row, "revenue", "current_balance"), 0),
            "Reservation_Status_Otalio": f(row, "reservation_status_id"),
            "Guest_Name": {"id": f(at(b.guestAnswers, i), "zohoId")},
            "Reservation": {"id": recordId(at(b.reservationData, i))},
            "Modified_By_System": OWNER,
            "Active_Inactive": "Active"
        });
    }
    foreach json e in existing {
        json name = f(e, "Name");
        if name is string && names.indexOf(name) !is () {
            continue;
        }
        records.push({"Name": name, "Modified_By_System": OWNER, "Active_Inactive": "Inactive"});
    }
    Group[] out = [];
    foreach json r in records {
        string[] parts = re `\|`.split(textOr(f(r, "Name"), ""));
        string key = parts.length() > 0 ? parts[0] : "";
        boolean placed = false;
        foreach Group g in out {
            if g.key == key {
                g.records.push(r);
                placed = true;
                break;
            }
        }
        if !placed {
            out.push({key, records: [r]});
        }
    }
    return out;
}

# Error rows for the cabin step. As in the old job, rows are written only when at least one
# answer is an error, and then for every record whose answer is not "success".
#
# + b - The block
# + groups - The groups that were written
# + answers - Per group: the CRM's answer entries, one per record
# + return - Rows
public isolated function cabinErrors(Block b, Group[] groups, json[][] answers) returns map<json>[] {
    boolean anyError = false;
    foreach json[] group in answers {
        foreach json entry in group {
            anyError = anyError || hasError(entry);
        }
    }
    map<json>[] out = [];
    if !anyError {
        return out;
    }
    foreach int g in 0 ..< groups.length() {
        foreach int i in 0 ..< groups[g].records.length() {
            json entry = g < answers.length() ? at(answers[g], i) : ();
            if f(entry, "status") == "success" {
                continue;
            }
            json rec = groups[g].records[i];
            string[] parts = re `\|`.split(textOr(f(rec, "Name"), ""));
            out.push({
                "reservation_number": parts.length() > 0 ? parts[0] : "",
                "correlation_id": b.correlationId,
                "cabin_number": f(rec, "Cabin_Number"),
                "source_system": OWNER,
                "module_name": "Cabin",
                "package_name": orEmpty(f(rec, "Package_Key")),
                "client_id": parts.length() > 1 ? parts[1] : "",
                "profile_id": f(rec, "Profile_ID"),
                "batch_job_name": b.jobName,
                "failure_reason": quoteSwap(f(entry, "message")),
                "error_code": f(entry, "errorCode") is () ? 400 : f(entry, "errorCode")
            });
        }
    }
    return out;
}

// ---------------------------------------------------------------- voyages

isolated function dateTime(json date, json time) returns json {
    if blank(date) || blank(time) {
        return ();
    }
    string[] parts = re `T`.split(textOr(time, ""));
    return textOr(date, "") + "T" + parts[parts.length() - 1];
}

# The voyage records for a block, one per guest row.
#
# + b - The block, after the voyage look-up
# + return - Records
public isolated function voyageRecords(Block b) returns json[] {
    return from json row in b.rows
        let json key = packageKey(b, row)
        select {
            "Name": key,
            "Package_Key": key,
            "Actual_Embarkation_Port_ID": f(row, "actual_embarkation_port_id"),
            "Scheduled_Embarkation_Date": f(row, "scheduled_embarkation_date"),
            "Actual_Embarkation_Date": f(row, "actual_embarkation_date"),
            "Actual_Embarkation_Time": dateTime(f(row, "actual_embarkation_date"), f(row, "actual_embarkation_time")),
            "Display_Embarkation_Date": f(row, "display_embarkation_date"),
            "Is_Mismatch_Embarkation_Port": f(row, "is_mismatch_embarkation_port"),
            "Actual_Disembarkation_Port_ID": f(row, "actual_disembarkation_port_id"),
            "Scheduled_Disembarkation_Date": f(row, "scheduled_disembarkation_date"),
            "Actual_Disembarkation_Date": f(row, "actual_disembarkation_date"),
            "Actual_Disembarkation_Time": dateTime(f(row, "actual_disembarkation_date"), f(row, "actual_disembarkation_time")),
            "Display_Disembarkation_Date": f(row, "display_disembarkation_date"),
            "Is_Mismatch_Disembarkation_Port": f(row, "is_mismatch_disembarkation_port"),
            "Port_Code_Embarkation": f(row, "emb_port_code"),
            "Port_Code_Disembarkation": f(row, "disemb_port_code"),
            "Port_Name_Embarkation": f(row, "defaultDescription"),
            "Port_Name_Disembarkation": f(row, "defaultDescription")
        };
}
