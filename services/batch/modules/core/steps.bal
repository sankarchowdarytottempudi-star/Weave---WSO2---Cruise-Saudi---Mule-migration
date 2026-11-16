// What is sent to the CRM for a block of Seaware reservations. Pure functions: no calls are made here.

const OWNER = "Seaware";

isolated function guestsOf(json node) returns json[] => items(f(node, "guests"));

isolated function guestCabin(json guest) returns json =>
    at(f(deep(f(guest, "voyages", "cabinChain"), "cabin"), "number"), 0);

isolated function guestPackage(json guest) returns json => at(f(guest, "voyages", "pkg", "key"), 0);

isolated function upsertBody(json[] data, string checkField) returns json =>
    {"data": data, "duplicate_check_fields": [checkField], "trigger": ["workflow"]};

isolated function isError(json entry) returns boolean => f(entry, "status") == "error";

# One row for the error table.
#
# + c - The block
# + module - Which step failed
# + reservation - Reservation number
# + cabin - Cabin number
# + pkg - Package key
# + clientId - Guest's client id
# + reason - Why it failed
# + code - Error code (500 when none was given)
# + return - The row
public isolated function errorRow(Chunk c, string module, json reservation, json cabin, json pkg, json clientId,
        json reason, json code) returns map<json> {
    return {
        "reservation_number": reservation,
        "correlation_id": c.correlationId,
        "cabin_number": cabin,
        "source_system": OWNER,
        "module_name": module,
        "package_name": pkg,
        "client_id": clientId,
        "batch_job_name": c.jobName,
        "failure_reason": reason is string ? re `'`.replaceAll(reason, "\"") : reason,
        "error_code": code is () ? 500 : code
    };
}

// ---------------------------------------------------------------- reservations

# The reservation write for a block. Links to guests, cabins, groups, invoices and voyages are
# added when the earlier steps have answered (the step runs first and last in every block).
#
# + c - The block
# + return - Request body
public isolated function reservationRequest(Chunk c) returns json {
    json[] data = [];
    foreach int i in 0 ..< c.edges.length() {
        data.push(reservationRecord(f(c.edges[i], "node"), i, c));
    }
    return upsertBody(data, "Account_Name");
}

isolated function reservationRecord(json node, int i, Chunk c) returns map<json> {
    json agency = f(node, "agency");
    json[] addresses = items(f(agency, "addresses"));
    json firstAddress = at(addresses, 0);
    json emailAddress = ();
    foreach json a in addresses {
        if f(a, "type", "key") == "EMAIL" {
            emailAddress = a;
            break;
        }
    }
    json agent = f(node, "secondaryAgent");
    json[] guests = guestsOf(node);
    json[] addons = flat(deep(guests, "addons"));
    json contact = at(c.contactAnswers, i);
    json primaryGuestId = f(at(contact, 0), "zohoId");
    string agencyPhone = textOr(at(f(agency, "phones", "intlCode"), 0), "") + textOr(at(f(agency, "phones", "number"), 0), "");
    json agentPhone = at(f(agent, "phones"), 0);
    boolean flight = false;
    foreach json a in flat(items(f(guests, "addons"))) {
        if textOr(f(a, "addon", "key"), "").endsWith("-F") {
            flight = true;
            break;
        }
    }
    map<json> out = {
        "Agency_ID": f(agency, "key"),
        "Agency_is_Internal": f(agency, "isInternal"),
        "External_System": blank(f(agency, "isInternal")),
        "Agency_Name": f(agency, "name"),
        "Agency_Type": f(agency, "type", "key"),
        "Agency_Phone": orNull(agencyPhone),
        "Address_Type": addressField(emailAddress, firstAddress, "type", "key"),
        "Address_Line_1": addressField(emailAddress, firstAddress, "line1"),
        "Address_Line_2": addressField(emailAddress, firstAddress, "line2"),
        "Agency_City": addressField(emailAddress, firstAddress, "city"),
        "Agency_Country": addressField(emailAddress, firstAddress, "country", "name"),
        "Commission_Code": commissionCodes(f(node, "commissions", "code")),
        "Agent_ID": f(agent, "key"),
        "First_Name": f(agent, "firstName"),
        "Last_Name": f(agent, "lastName"),
        "Email": f(agent, "email"),
        "Agent_Phone": textOr(f(agentPhone, "intlCode"), "") + textOr(f(agentPhone, "number"), ""),
        "Balance_Due": f(node, "invoiceTotals", "currentDue", "amount"),
        "Booking_Channel": f(node, "sourceCode"),
        "Booking_Status": f(node, "status", "name"),
        "Currency": f(node, "currency", "key"),
        "Price_Addons": sum(f(addons, "price")),
        "Price_Shorex": sum(f(flat(deep(guests, "shorex")), "price")),
        "Due_Date": dateOnly(f(node, "invoiceTotals", "currentDue", "date")),
        "Group_ID": f(node, "group", "key"),
        "Invoice_Total": f(node, "invoiceTotals", "invoiceTotal"),
        "Number_of_Guests": f(node, "guestCount"),
        "Account_Name": f(node, "id"),
        "Account_Number": f(node, "key"),
        "Reservation_Status": f(node, "status", "name"),
        "Reservation_Version": text(f(node, "version")),
        "Reservation_Confirmation_Date": orNull(f(node, "confirmationDate")),
        "Reservation_Created_On": orNull(f(node, "initialDate")),
        "Reservation_Last_Updated": orNull(f(node, "lastUpdated")),
        "Reservation_Original_Initial_Date": orNull(f(node, "originalInitialDate")),
        "Flight_Cruise_Enabled": flight,
        "Source_System": OWNER
    };
    link(out, "Group_Agency_Name", f(at(f(c.groupAnswer, "data"), i), "details", "id"));
    link(out, "Finance_Name", f(at(f(c.invoiceAnswer, "data"), i), "details", "id"));
    link(out, "Reservation_Contact", primaryGuestId);
    link(out, "Cabin_Info", primaryCabinId(c, f(node, "key"), primaryGuestId));
    link(out, "Voyage", at(f(at(c.voyageAnswers, i), "data", "details", "id"), 0));
    if !blank(f(at(f(contact, "data"), 0), "details", "id")) {
        out["Preferred_Language"] = f(at(guests, 0), "client", "language", "name");
    }
    return out;
}

isolated function link(map<json> rec, string name, json id) {
    if !blank(id) {
        rec[name] = {"id": id};
    }
}

isolated function addressField(json preferred, json fallback, string... path) returns json {
    json v = f(preferred, ...path);
    if blank(v) {
        v = f(fallback, ...path);
    }
    return blank(v) ? "" : v;
}

isolated function commissionCodes(json codes) returns json {
    if codes is json[] {
        return string:'join(",", ...from json code in codes select textOr(code, ""));
    }
    return codes;
}

# The CRM id of the primary guest's cabin, when exactly one active, written cabin belongs to them.
#
# + c - The block (cabins written by the cabin step)
# + reservationNumber - Reservation number
# + guestId - CRM id of the primary guest
# + return - The cabin's CRM id or ()
public isolated function primaryCabinId(Chunk c, json reservationNumber, json guestId) returns json {
    if blank(guestId) {
        return ();
    }
    json[] hits = [];
    foreach json g in c.cabinCorrelation {
        if f(g, "reservationNumber") != reservationNumber {
            continue;
        }
        foreach json cabin in items(f(g, "cabins")) {
            if f(cabin, "reservationNumber") == reservationNumber && f(cabin, "activeInactive") == "Active"
                && f(cabin, "status") == "success" && !blank(f(cabin, "zohoId"))
                && text(f(cabin, "guestId")) == text(guestId) {
                hits.push(f(cabin, "zohoId"));
            }
        }
    }
    return hits.length() == 1 ? hits[0] : ();
}

# Error rows for reservations the CRM refused.
#
# + c - The block, after the reservation write
# + return - Rows
public isolated function reservationErrors(Chunk c) returns map<json>[] {
    map<json>[] rows = [];
    json data = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json entry = at(data, i);
        if isError(entry) {
            json node = f(c.edges[i], "node");
            json guest = at(guestsOf(node), 0);
            rows.push(errorRow(c, "Reservation", f(node, "key"), guestCabin(guest), guestPackage(guest),
                    f(guest, "client", "key"), f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}

// ---------------------------------------------------------------- guests

# What is sent to the guest service for one reservation: one entry per guest.
#
# + node - The reservation
# + return - Request body
public isolated function guestRequest(json node) returns json[] {
    json[] out = [];
    foreach json g in guestsOf(node) {
        json person = f(g, "client");
        string intlCode = textOr(at(f(person, "phones", "intlCode"), 0), "");
        json number = at(f(person, "phones", "number"), 0);
        json city = at(f(person, "household", "addresses", "city"), 0);
        out.push({
            "title": f(person, "title", "key"),
            "firstName": f(person, "firstName"),
            "lastName": f(person, "lastName"),
            "gender": f(person, "gender"),
            "email": f(person, "eMail"),
            "nationalityKey": f(person, "citizenship", "key"),
            "nationalityName": f(person, "citizenship", "name"),
            "dateOfBirth": f(person, "birthday"),
            "countryOfResidenceName": f(person, "countryOfResidence", "name"),
            "countryOfResidenceKey": f(person, "countryOfResidence", "key"),
            "city": city,
            "languageKey": f(person, "language", "key"),
            "languageName": f(person, "language", "name"),
            "intlCode": intlCode,
            "phone": number,
            "age": blank(f(g, "age")) ? () : text(f(g, "age")),
            "clientId": f(person, "key"),
            "clubAccount": f(g, "calculatedFields", "pointsInfo", "balance", "clubAccountNumber"),
            "countryOfBirth": f(person, "countryOfBirth", "name"),
            "householdId": f(person, "household", "key"),
            "middleName": f(person, "middleName"),
            "mobile": intlCode + textOr(number, ""),
            "mailingCity": city,
            "accountName": f(node, "id")
        });
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
    return from int i in 0 ..< (guestCount < 1 ? 1 : guestCount) select entry;
}

# Error rows for guests the guest service refused.
#
# + c - The block, after the guest step
# + return - Rows
public isolated function guestErrors(Chunk c) returns map<json>[] {
    map<json>[] rows = [];
    foreach int i in 0 ..< c.edges.length() {
        json node = f(c.edges[i], "node");
        json[] guests = guestsOf(node);
        foreach int g in 0 ..< guests.length() {
            json entry = at(at(c.contactAnswers, i), g);
            if isError(entry) && !blank(f(entry, "message")) {
                rows.push(errorRow(c, "Guest", f(node, "key"), guestCabin(guests[g]), guestPackage(guests[g]),
                        f(guests[g], "client", "key"), f(entry, "message"), 400));
            }
        }
    }
    return rows;
}

// ---------------------------------------------------------------- reservation-to-guest links

# CRM ids of the reservations written in this block (to look up their existing guest links).
#
# + c - The block
# + return - Ids
public isolated function reservationIds(Chunk c) returns json[] => items(f(c.reservationAnswer, "data", "details", "id"));

# Which reservation-to-guest links to create, keep active, or switch off.
#
# Every guest of a written reservation gets an active link. Links the CRM already has for these
# reservations but that are no longer wanted are set inactive. Links last changed by another
# system are left alone.
#
# + c - The block, after the reservation and guest steps
# + existing - Links the CRM already has for these reservations
# + return - Request bodies, one per reservation and kind
public isolated function linkingPlan(Chunk c, json[] existing) returns LinkingPlan {
    string[] wantedKeys = [];
    map<json> wanted = {};
    json data = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        string? reservationId = text(f(at(data, i), "details", "id"));
        if reservationId is () || reservationId == "" {
            continue;
        }
        foreach json guest in items(at(c.contactAnswers, i)) {
            string? guestId = text(f(guest, "zohoId"));
            if guestId is string && guestId != "" && !wanted.hasKey(reservationId + "|" + guestId) {
                wanted[reservationId + "|" + guestId] = {"reservationId": reservationId, "guestId": guestId};
                wantedKeys.push(reservationId + "|" + guestId);
            }
        }
    }
    map<json> present = {};
    string[] presentKeys = [];
    foreach json e in existing {
        string key = textOr(f(e, "Reservation_Names", "id"), "") + "|" + textOr(f(e, "Guest_Names", "id"), "");
        if !present.hasKey(key) {
            present[key] = e;
            presentKeys.push(key);
        }
    }
    string[] sequence = [];
    map<json[]> creates = {};
    map<json[]> updates = {};
    foreach string key in wantedKeys {
        json w = wanted[key];
        string reservationId = textOr(f(w, "reservationId"), "");
        map<json> rec = {
            "Reservation_Names": {"id": reservationId},
            "Guest_Names": {"id": f(w, "guestId")},
            "Active_Inactive": "Active",
            "Modified_By_System": OWNER
        };
        if present.hasKey(key) {
            json e = present[key];
            if textOr(f(e, "Modified_By_System"), OWNER) != OWNER {
                continue;
            }
            rec["id"] = f(e, "id");
            addTo(updates, sequence, reservationId, rec);
        } else {
            addTo(creates, sequence, reservationId, rec);
        }
    }
    foreach string key in presentKeys {
        json e = present[key];
        if wanted.hasKey(key) || textOr(f(e, "Modified_By_System"), OWNER) != OWNER {
            continue;
        }
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
        json[]? c1 = creates[reservationId];
        if c1 is json[] {
            plan.creates.push({"data": c1});
        }
        json[]? u1 = updates[reservationId];
        if u1 is json[] {
            plan.updates.push({"data": u1});
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

// ---------------------------------------------------------------- shared by cabins and add-ons

# Merges the records wanted now with the ones the CRM already has, by `Name`.
#
# Wanted and already there: written again, unless another system changed it last (then left alone).
# Wanted and new: written. Already there, no longer wanted, and ours: set inactive.
#
# + fresh - Records wanted now
# + existing - Records the CRM has
# + return - Records to write (or to report, when marked as not writable)
public isolated function ownedMerge(json[] fresh, json[] existing) returns json[] {
    json[] out = [];
    string[] seen = [];
    foreach json n in fresh {
        string? name = text(f(n, "Name"));
        if name is () || name == "" || seen.indexOf(name) !is () || n !is map<json> {
            continue;
        }
        seen.push(name);
        json e = byName(existing, name);
        if e !is () && textOr(f(e, "Modified_By_System"), OWNER) != OWNER {
            continue;
        }
        map<json> rec = n.clone();
        rec["Modified_By_System"] = OWNER;
        rec["Active_Inactive"] = "Active";
        out.push(rec);
    }
    foreach json e in existing {
        string? name = text(f(e, "Name"));
        if name is () || name == "" || seen.indexOf(name) !is () {
            continue;
        }
        seen.push(name);
        if textOr(f(e, "Modified_By_System"), OWNER) == OWNER {
            out.push({"Name": name, "Modified_By_System": OWNER, "Active_Inactive": "Inactive"});
        }
    }
    return out;
}

isolated function byName(json[] records, string name) returns json {
    foreach json r in records {
        if f(r, "Name") == name {
            return r;
        }
    }
    return ();
}

# Groups records by the reservation number at the start of their `Name` (`number|client|item`).
#
# + records - Records
# + return - Groups in first-seen sequence
public isolated function byReservation(json[] records) returns Group[] {
    Group[] out = [];
    foreach json r in records {
        string key = namePart(r, 0);
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

isolated function namePart(json rec, int index) returns string {
    string[] parts = re `\|`.split(textOr(f(rec, "Name"), ""));
    return index < parts.length() ? parts[index] : "";
}

# The records of a group that can be written (those not marked as an error).
#
# + g - Group
# + return - Records to send
public isolated function writable(Group g) returns json[] => from json r in g.records where !isError(r) select r;

# Lines up a group's records with what the CRM answered: a record that was not sent answers for itself.
#
# + g - Group
# + answer - CRM answer for the records that were sent (`{data: [...]}`), () when none were sent
# + return - One answer entry per record
public isolated function answersFor(Group g, json answer) returns json[] {
    json data = f(answer, "data");
    json[] out = [];
    int sent = 0;
    foreach json r in g.records {
        if isError(r) {
            out.push(r);
        } else {
            json entry = at(data, sent);
            out.push(entry is () ? at(data, 0) : entry);
            sent += 1;
        }
    }
    return out;
}

// ---------------------------------------------------------------- cabins

# The cabin records wanted for a block: one per guest and cabin; a guest without a cabin gives a
# record marked "No cabin assigned" that is reported instead of written.
#
# + c - The block, after the reservation and guest steps
# + return - Records
public isolated function cabinRecords(Chunk c) returns json[] {
    json[] out = [];
    json data = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json node = f(c.edges[i], "node");
        string key = textOr(f(node, "key"), "");
        json[] guests = guestsOf(node);
        foreach int g in 0 ..< guests.length() {
            json guest = guests[g];
            string clientKey = textOr(f(guest, "client", "key"), "");
            json chain = at(f(guest, "voyages", "cabinChain"), 0);
            if blank(chain) {
                out.push({
                    "Name": key + "|" + clientKey + "|",
                    "Package_Key": guestPackage(guest),
                    "status": "error",
                    "errorCode": 400,
                    "message": "No cabin assigned"
                });
                continue;
            }
            foreach json link in items(chain) {
                json cabin = f(link, "cabin");
                out.push({
                    "Cabin_Number": f(cabin, "number"),
                    "Cabin_Type": f(cabin, "category", "comments"),
                    "Package_Key": guestPackage(guest),
                    "Name": key + "|" + clientKey + "|" + textOr(f(cabin, "number"), ""),
                    "Guest_Name": {"id": f(at(at(c.contactAnswers, i), g), "zohoId")},
                    "Reservation": {"id": f(at(data, i), "details", "id")}
                });
            }
        }
    }
    return out;
}

# The cabin write for one reservation.
#
# + records - Records to send
# + return - Request body
public isolated function cabinRequest(json[] records) returns json => upsertBody(records, "Name");

# What the reservation step needs to know about the cabins written for one reservation.
#
# + g - Group
# + answers - One answer entry per record
# + return - `{reservationNumber, cabins: [...]}`
public isolated function cabinCorrelation(Group g, json[] answers) returns json {
    json[] cabins = [];
    foreach int i in 0 ..< g.records.length() {
        json r = g.records[i];
        cabins.push({
            "reservationNumber": g.key,
            "name": f(r, "Name"),
            "guestId": f(r, "Guest_Name", "id"),
            "activeInactive": f(r, "Active_Inactive"),
            "zohoId": f(at(answers, i), "details", "id"),
            "status": f(at(answers, i), "status")
        });
    }
    return {"reservationNumber": g.key, "cabins": cabins};
}

# Error rows for cabins that were refused or could not be written.
#
# + c - The block
# + g - Group
# + answers - One answer entry per record
# + return - Rows
public isolated function cabinErrors(Chunk c, Group g, json[] answers) returns map<json>[] {
    map<json>[] rows = [];
    foreach int i in 0 ..< g.records.length() {
        json entry = at(answers, i);
        if isError(entry) {
            json r = g.records[i];
            rows.push(errorRow(c, "Cabin", namePart(r, 0), orNull(namePart(r, 2)), f(r, "Package_Key"), namePart(r, 1),
                    f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}

// ---------------------------------------------------------------- add-ons

# The add-on records wanted for a block: one per guest and add-on; a guest without add-ons gives a
# record marked "No addons assigned" that is reported instead of written.
#
# + c - The block, after the reservation and guest steps
# + return - Records
public isolated function addonRecords(Chunk c) returns json[] {
    json[] out = [];
    json data = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json node = f(c.edges[i], "node");
        string key = textOr(f(node, "key"), "");
        json[] guests = guestsOf(node);
        foreach int g in 0 ..< guests.length() {
            json guest = guests[g];
            string clientKey = textOr(f(guest, "client", "key"), "");
            json[] addons = items(f(guest, "addons"));
            if addons.length() == 0 {
                out.push({
                    "Name": key + "|" + clientKey + "|",
                    "Cabin_Number": at(f(at(f(guest, "voyages"), 0), "cabinChain", "cabin", "number"), 0),
                    "Package_Key": guestPackage(guest),
                    "status": "error",
                    "errorCode": 400,
                    "message": "No addons assigned"
                });
                continue;
            }
            foreach json a in addons {
                out.push({
                    "Addon_Code": f(a, "addon", "key"),
                    "Name": key + "|" + clientKey + "|" + textOr(f(a, "addon", "key"), ""),
                    "Addon_Price": f(a, "price"),
                    "Addon_Category": f(a, "addon", "category", "key"),
                    "Addon_Is_Special_Request": f(a, "isSpecialRequest"),
                    "Addon_Qty": text(f(a, "quantity")),
                    "Addon_Type": f(a, "addon", "type", "key"),
                    "Addons_ID": f(a, "addon", "id"),
                    "Client_ID": f(guest, "client", "key"),
                    "Reservation_Addon": f(at(data, i), "details", "id"),
                    "Guest_Name": f(at(at(c.contactAnswers, i), g), "zohoId")
                });
            }
        }
    }
    return out;
}

# Error rows for add-ons that were refused or could not be written.
#
# + c - The block
# + g - Group
# + answers - One answer entry per record
# + return - Rows
public isolated function addonErrors(Chunk c, Group g, json[] answers) returns map<json>[] {
    map<json>[] rows = [];
    foreach int i in 0 ..< g.records.length() {
        json entry = at(answers, i);
        if isError(entry) && !blank(f(entry, "message")) {
            json r = g.records[i];
            rows.push(errorRow(c, "Addons", namePart(r, 0), f(r, "Cabin_Number"), f(r, "Package_Key"), namePart(r, 1),
                    f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}

// ---------------------------------------------------------------- shore excursions

# The shore excursion records wanted for a block (old zoho-shorex-upsertSub_Flow): one per guest and
# excursion; a guest without excursions gives a record marked "No shorex assigned" that is reported
# instead of written.
#
# + c - The block, after the reservation and guest steps
# + return - Records
public isolated function shorexRecords(Chunk c) returns json[] {
    json[] out = [];
    json data = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json node = f(c.edges[i], "node");
        string key = textOr(f(node, "key"), "");
        json version = f(node, "version");
        json[] guests = guestsOf(node);
        foreach int g in 0 ..< guests.length() {
            json guest = guests[g];
            string clientKey = textOr(f(guest, "client", "key"), "");
            json[] shorex = items(f(guest, "shorex"));
            if shorex.length() == 0 {
                out.push({
                    "Name": key + "|" + clientKey + "|",
                    "Package_Key": at(f(guestsOf(node)[0], "voyages", "pkg", "key"), 0),
                    "status": "error",
                    "errorCode": 400,
                    "message": "No shorex assigned"
                });
                continue;
            }
            foreach json x in shorex {
                json price = f(x, "price");
                map<json> rec = {
                    "Shorex_Code": f(x, "code"),
                    "Name": key + "|" + clientKey + "|" + textOr(f(x, "code"), ""),
                    "Shorex_Price": blank(price) ? () : text(price),
                    "Shorex_Package_Key": f(x, "pkg", "key"),
                    "Shorex_Package_Description": f(x, "pkg", "description"),
                    "Reservation_Shorex": f(at(data, i), "details", "id"),
                    "Client_ID": f(guest, "client", "key"),
                    "Guest_Shorex": f(at(at(c.contactAnswers, i), g), "zohoId"),
                    "Shorex_Version": blank(version) ? () : text(version)
                };
                out.push(withoutNulls(rec));
            }
        }
    }
    return out;
}

isolated function withoutNulls(map<json> rec) returns map<json> {
    map<json> out = {};
    foreach [string, json] [k, v] in rec.entries() {
        if v !is () {
            out[k] = v;
        }
    }
    return out;
}

# Error rows for shore excursions that were refused or could not be written (the old flow's
# columns: no cabin number; the package of the reservation's first guest).
#
# + c - The block
# + g - Group
# + answers - One answer entry per record
# + return - Rows
public isolated function shorexErrors(Chunk c, Group g, json[] answers) returns map<json>[] {
    map<json>[] rows = [];
    foreach int i in 0 ..< g.records.length() {
        json entry = at(answers, i);
        if isError(entry) && !blank(f(entry, "message")) {
            json r = g.records[i];
            json pkg = f(r, "Package_Key");
            if pkg is () {
                pkg = packageOf(c, namePart(r, 0));
            }
            map<json> row = errorRow(c, "Shorex", namePart(r, 0), (), pkg, namePart(r, 1), f(entry, "message"),
                    f(entry, "errorCode"));
            _ = row.remove("cabin_number");
            rows.push(row);
        }
    }
    return rows;
}

isolated function packageOf(Chunk c, string reservation) returns json {
    foreach json e in c.edges {
        if textOr(f(e, "node", "key"), "") == reservation {
            json[] guests = guestsOf(f(e, "node"));
            return guests.length() > 0 ? at(f(guests[0], "voyages", "pkg", "key"), 0) : ();
        }
    }
    return ();
}

// ---------------------------------------------------------------- groups and agencies

# The group and agency write for a block.
#
# + c - The block
# + return - Request body
public isolated function groupRequest(Chunk c) returns json {
    json[] data = [];
    foreach json e in c.edges {
        json node = f(e, "node");
        data.push({
            "Agency_ID": f(node, "agency", "key"),
            "Agent_ID": f(node, "group", "agent", "key"),
            "Email": f(node, "group", "agent", "email"),
            "Group_ID": f(node, "group", "key"),
            "Source_System": OWNER,
            "Name": f(node, "group", "name")
        });
    }
    return upsertBody(data, "Group_ID");
}

# Error rows for groups the CRM refused.
#
# + c - The block, after the group step
# + return - Rows
public isolated function groupErrors(Chunk c) returns map<json>[] {
    map<json>[] rows = [];
    json data = f(c.groupAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json entry = at(data, i);
        if isError(entry) {
            json node = f(c.edges[i], "node");
            json guest = at(guestsOf(node), 0);
            rows.push(errorRow(c, "Group-Agency", f(node, "key"), guestCabin(guest), guestPackage(guest),
                    f(guest, "client", "key"), f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}

// ---------------------------------------------------------------- voyages

# The voyage write for one reservation (taken from its first guest).
#
# + node - The reservation
# + return - Request body
public isolated function voyageRequest(json node) returns json {
    json voyages = f(at(guestsOf(node), 0), "voyages");
    json destinations = at(f(voyages, "pkg", "destinations"), 0);
    return upsertBody([
                {
                    "Name": at(f(voyages, "pkg", "key"), 0),
                    "Arrival_Date_and_Time": at(f(voyages, "sail", "to", "dateTime"), 0),
                    "Arrival_Port_ID": at(f(voyages, "sail", "to", "port", "id"), 0),
                    "Arrival_Port_Key": at(f(voyages, "sail", "to", "port", "key"), 0),
                    "Arrival_Port_Name": at(f(voyages, "sail", "to", "port", "name"), 0),
                    "Cruise_Duration_Number_of_Nights": at(f(voyages, "pkg", "sailDays"), 0),
                    "Departure_Date_and_Time": at(f(voyages, "sail", "from", "dateTime"), 0),
                    "Departure_Port_ID": at(f(voyages, "sail", "from", "port", "id"), 0),
                    "Departure_Port_Key": at(f(voyages, "sail", "from", "port", "key"), 0),
                    "Departure_Port_Name": at(f(voyages, "sail", "from", "port", "name"), 0),
                    "Destination_Comment": at(f(destinations, "comments"), 0),
                    "Destination_ID": at(f(destinations, "id"), 0),
                    "Destination_Key": at(f(destinations, "key"), 0),
                    "Destination_Name": at(f(destinations, "name"), 0),
                    // The old mapping read the guest count as a list entry, which is always empty.
                    "Number_of_Guests": (),
                    "Package_ID": at(f(voyages, "pkg", "id"), 0),
                    "Package_Key": at(f(voyages, "pkg", "key"), 0),
                    "Package_Name": at(f(voyages, "pkg", "type", "name"), 0),
                    "Ship_ID": at(f(voyages, "ship", "key"), 0),
                    "Package": at(f(voyages, "pkg", "type", "comments"), 0)
                }
            ], "Name");
}

# Error rows for voyages the CRM refused (one per guest of the reservation).
#
# + c - The block, after the voyage step
# + return - Rows
public isolated function voyageErrors(Chunk c) returns map<json>[] {
    map<json>[] rows = [];
    foreach int i in 0 ..< c.edges.length() {
        json entry = at(f(at(c.voyageAnswers, i), "data"), 0);
        if !isError(entry) {
            continue;
        }
        json node = f(c.edges[i], "node");
        foreach json guest in guestsOf(node) {
            rows.push(errorRow(c, "Voyage", f(node, "key"), guestCabin(guest), guestPackage(guest), f(guest, "client", "key"), f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}

// ---------------------------------------------------------------- invoices

# The invoice write for a block.
#
# + c - The block, after the reservation and guest steps
# + return - Request body
public isolated function invoiceRequest(Chunk c) returns json {
    json[] data = [];
    json answers = f(c.reservationAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json node = f(c.edges[i], "node");
        json[] guests = guestsOf(node);
        json invoiceId = f(node, "lastInvoice", "invoiceId");
        json[] schedule = from json p in items(f(node, "paymentSchedule"))
            select {
                "Paid": f(p, "paid"),
                "Payment_Amount_Paid": blank(f(p, "paidAmount")) ? () : text(f(p, "paidAmount")),
                "Payment_Date": dateOnly(f(p, "dueDate")),
                "Payment_Type": f(p, "dueType")
            };
        json[] received = from json t in items(f(node, "transactions"))
            select {
                "Payment_Amount_Paid": blank(f(t, "amount")) ? () : text(f(t, "amount")),
                "Payment_Date": dateOnly(f(t, "dateTime")),
                "Payment_Method": f(t, "form", "key"),
                "Price_to_Base_Currency_Rate": blank(f(t, "priceToBaseCurrencyRate")) ? () : text(f(t, "priceToBaseCurrencyRate"))
            };
        map<json> rec = {
            "Name": textOr(invoiceId, ""),
            // Coupon amount, promotion amount and promotion type were always empty in the old
            // application (its mapping looked in the wrong place); kept empty so the CRM sees no change.
            "Coupon_Amount_Discount": (),
            "Coupon_key_discount": f(node, "coupons", "coupon", "key"),
            "Currency": f(node, "currency", "key"),
            "Invoice_Number": blank(invoiceId) ? () : text(invoiceId),
            "Promotion_Amount": (),
            "Promotion_Code": at(f(at(f(at(f(node, "guests", "voyages"), 0), "promotions"), 0), "promotion", "code"), 0),
            "Promotion_Type": (),
            "Reservation_Name": {"id": f(at(answers, i), "details", "id")},
            "Total_Invoice": f(node, "invoiceTotals", "invoiceTotal"),
            "Due_Date": dateOnly(f(node, "invoiceTotals", "currentDue", "date")),
            "Addons_Total": sum(f(flat(deep(guests, "addons")), "price")),
            "Balance_Due": blank(f(node, "invoiceTotals", "currentDue", "amount")) ? "0" : f(node, "invoiceTotals", "currentDue", "amount"),
            "Due_Type": at(f(node, "paymentSchedule", "dueType"), 0),
            "Shorex_Total": sum(f(flat(deep(guests, "shorex")), "price")),
            "Source_System": OWNER,
            "Payment_Schedule": schedule,
            "Payment_Received": received
        };
        json contactId = f(at(at(c.contactAnswers, i), 0), "zohoId");
        if !blank(contactId) {
            rec["Contact"] = {"id": contactId};
        }
        data.push(rec);
    }
    return upsertBody(data, "Name");
}

# Error rows for invoices the CRM refused (one per guest of the reservation).
#
# + c - The block, after the invoice step
# + return - Rows
public isolated function invoiceErrors(Chunk c) returns map<json>[] {
    map<json>[] rows = [];
    json data = f(c.invoiceAnswer, "data");
    foreach int i in 0 ..< c.edges.length() {
        json entry = at(data, i);
        if !isError(entry) {
            continue;
        }
        json node = f(c.edges[i], "node");
        foreach json guest in guestsOf(node) {
            rows.push(errorRow(c, "Invoice", f(node, "key"), guestCabin(guest), guestPackage(guest),
                    f(guest, "client", "key"), f(entry, "message"), f(entry, "errorCode")));
        }
    }
    return rows;
}
