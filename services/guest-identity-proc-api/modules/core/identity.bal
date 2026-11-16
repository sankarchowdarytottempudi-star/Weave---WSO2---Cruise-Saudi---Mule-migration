// One guest of POST /processGuestIdentity (Mule: guest_identity-impl, guest_zoho-impl,
// guest_seaware-impl, guest-crm-upsert-impl, db-implementation).

# What is sent to Seaware for a guest.
#
# + kind - "none" (nothing is sent), "update" or "create"
# + query - The GraphQL mutation; "" for "none"
# + updateClient - For "none": the client id the caller gave
public type ClientPlan record {|
    string kind;
    string query = "";
    string updateClient = "";
|};

# Mule: `p('data.channelCheck') contains vars.channel`.
#
# + channels - Channels that also write to the CRM
# + channel - The caller's channel
# + return - True when the CRM is part of the processing
public isolated function channelAllowed(string[] channels, string? channel) returns boolean =>
    channel is string && channels.indexOf(channel) is int;

isolated function put(map<json> target, string name, json value) {
    if has(value) {
        target[name] = value;
    }
}

isolated function putText(map<json> target, string name, json value, boolean capital = false, boolean upper = false) {
    if has(value) {
        string text = textOf(value);
        target[name] = capital ? capitalize(text) : (upper ? text.toUpperAscii() : text);
    }
}

# Mule `gen`: M or Male -> Male, F or Female -> Female, anything else -> Others.
#
# + gender - The guest's gender as sent
# + return - The CRM's gender name
public isolated function genderName(json gender) returns string {
    string g = capitalize(textOf(gender));
    if g == "M" || g == "Male" {
        return "Male";
    }
    if g == "F" || g == "Female" {
        return "Female";
    }
    return "Others";
}

# Mule `completeFiveFieldMatch`: first name, last name, phone and date of birth are given and the
# e-mail address is usable. Only then is the CRM searched for the guest.
#
# + guest - The guest as sent
# + return - True when all five are there
public isolated function completeMatch(map<json> guest) returns boolean =>
    trimmed(guest["firstName"]) != "" && trimmed(guest["lastName"]) != "" && trimmed(guest["phone"]) != ""
        && trimmed(guest["dateOfBirth"]) != "" && emailValid(guest["email"]);

# The CRM search for an existing contact of the guest.
#
# + guest - The guest as sent
# + return - Zoho search criteria
public isolated function searchCriteriaOf(map<json> guest) returns string {
    string[] parts = [
        "(First_Name:equals:" + textOf(guest["firstName"]).toUpperAscii() + ")",
        "(Last_Name:equals:" + textOf(guest["lastName"]).toUpperAscii() + ")",
        "(Mobile:equals:" + textOf(guest["intlCode"]) + textOf(guest["phone"]) + ")"
    ];
    if emailValid(guest["email"]) {
        parts.push("(Email:equals:" + textOf(guest["email"]).toUpperAscii() + ")");
    }
    parts.push("(Date_of_Birth:equals:" + textOf(guest["dateOfBirth"]) + ")");
    return "(" + string:'join("and", ...parts) + ")";
}

# The contact whose ids are reused: of the contacts that have a loyalty id and a guest id without
# a hyphen, the one changed last.
#
# + records - Contacts found in the CRM
# + return - The contact, `()` when none qualifies
public isolated function selectedRecordOf(json[] records) returns map<json>? {
    map<json>? selected = ();
    string latest = "";
    foreach json item in records {
        if item is map<json> {
            string guestId = textOf(item["Global_Guest_ID"]);
            if !has(item["Aroya_Loyalty_ID"]) || guestId == "" || guestId.includes("-") {
                continue;
            }
            string modified = textOf(item["Modified_Time"]);
            if selected is () || modified >= latest {
                selected = item;
                latest = modified;
            }
        }
    }
    return selected;
}

isolated function birthCountryOf(map<json> guest) returns string {
    string residence = textOf(guest["countryOfResidenceName"]);
    return residence != "" ? residence : textOf(guest["countryOfBirthName"]);
}

# The update of the contacts already in the CRM (Mule: crmRequest in guest_zoho-impl).
#
# + records - Contacts found in the CRM
# + guest - The guest as sent
# + globalId - Guest id to write
# + loyaltyId - Loyalty id to write
# + return - One update per contact
public isolated function existingUpdatesOf(json[] records, map<json> guest, string globalId, string loyaltyId)
        returns json[] {
    json[] updates = [];
    foreach json existing in records {
        map<json> row = {"id": fieldOf(existing, "id")};
        putText(row, "Age", guest["age"]);
        put(row, "Profile_ID", guest["profileId"]);
        row["Client_ID"] = fieldOf(existing, "Client_ID");
        put(row, "Club_Account", guest["clubAccount"]);
        putText(row, "Country_of_Birth", birthCountryOf(guest), capital = true);
        put(row, "Date_of_Birth", guest["dateOfBirth"]);
        if emailValid(guest["email"]) {
            row["Email"] = guest["email"];
        }
        putText(row, "First_Name", guest["firstName"], upper = true);
        if has(guest["gender"]) {
            row["Gender"] = genderName(guest["gender"]);
        }
        put(row, "Household_ID", guest["householdId"]);
        put(row, "IQAMA_ID_Expiration_Date", guest["nationalIdExpiryDate"]);
        put(row, "IQAMA_ID_Number", guest["nationalId"]);
        putText(row, "Last_Name", guest["lastName"], upper = true);
        // Mule reads `maillingCity` (two l) here; kept.
        put(row, "Mailing_City", guest["maillingCity"]);
        put(row, "Middle_Name", guest["middleName"]);
        row["Mobile"] = textOf(guest["intlCode"]) + textOf(guest["phone"]);
        put(row, "City", guest["city"]);
        putText(row, "Nationality", guest["nationalityName"], capital = true);
        row["Passport_Expiration_Date"] = guest["passportExpiryDate"];
        row["Passport_Number"] = guest["passportNumber"];
        put(row, "Phone", guest["phone"]);
        putText(row, "Preferred_Language", guest["languageName"], capital = true);
        row["Global_Guest_ID"] = globalId;
        row["Aroya_Loyalty_ID"] = loyaltyId;
        put(row, "Account_Name", fieldOf(existing, "Account_Name", "name"));
        putText(row, "Residency", guest["countryOfResidenceName"], capital = true);
        put(row, "Salutation", guest["title"]);
        updates.push(row);
    }
    return updates;
}

// ---------------------------------------------------------------------------------------------
// Seaware client
// ---------------------------------------------------------------------------------------------

# True when the guest carries something to search Seaware clients by. Mule searched with no
# criteria at all in that case, which matches any client; here nothing is searched.
#
# + guest - The guest as sent
# + return - True when a search can be made
public isolated function hasClientSearch(map<json> guest) returns boolean =>
    has(guest["firstName"]) || has(guest["lastName"]) || emailValid(guest["email"]) || has(guest["phone"]);

# The Seaware client search for the guest.
#
# + guest - The guest as sent
# + return - Request body
public isolated function clientsQueryOf(map<json> guest) returns map<json> {
    string[] params = [];
    if has(guest["firstName"]) {
        params.push("firstName: \"" + gqlText(textOf(guest["firstName"])) + "\"");
    }
    if has(guest["lastName"]) {
        params.push("lastName: \"" + gqlText(textOf(guest["lastName"])) + "\"");
    }
    if emailValid(guest["email"]) {
        params.push("eMail: \"" + gqlText(textOf(guest["email"])) + "\"");
    }
    if has(guest["phone"]) {
        params.push("phoneNumber: \"" + gqlText(textOf(guest["phone"])) + "\"");
    }
    return {
        "query": "query Clients { clients( params: {" + string:'join(", ", ...params) + "} first: 1000 ) { edges { node {"
            + " key countryOfBirth { key name } citizenship { name key } countryOfResidence { key } documents { type { key }"
            + " number expirationDate } } } pageInfo { hasPreviousPage hasNextPage startCursor endCursor position count"
            + " totalCount } } }"
    };
}

isolated function quoted(string name, json value, boolean upper = false) returns string {
    if !has(value) {
        return "";
    }
    string text = textOf(value);
    return name + ": \"" + gqlText(upper ? text.toUpperAscii() : text) + "\", ";
}

isolated function bare(string name, json value) returns string {
    string word = bareWord(textOf(value));
    return word == "" ? "" : name + ": " + word + ", ";
}

isolated function keyed(string name, string key) returns string =>
    key == "" ? "" : name + ": { key: [\"" + gqlText(key.toUpperAscii()) + "\"] }, ";

isolated function firstText(json... values) returns string {
    foreach json value in values {
        if has(value) {
            return textOf(value);
        }
    }
    return "";
}

isolated function documentsOf(map<json> guest, boolean alreadyOnClient) returns string {
    if alreadyOnClient || !has(guest["nationalId"]) || !has(guest["nationalIdExpiryDate"]) {
        return "";
    }
    return "documents: { type: { key: \"NATIONAL ID\" } number: \"" + gqlText(textOf(guest["nationalId"]))
        + "\" expirationDate: \"" + gqlText(textOf(guest["nationalIdExpiryDate"])) + "\" } ";
}

isolated function passportOf(map<json> guest) returns string {
    if !has(guest["passportNumber"]) {
        return "";
    }
    string expiry = has(guest["passportExpiryDate"])
        ? " expirationDate: \"" + gqlText(textOf(guest["passportExpiryDate"])) + "\"" : "";
    return "passport: { number: \"" + gqlText(textOf(guest["passportNumber"]).toUpperAscii()) + "\"" + expiry + " } ";
}

isolated function titleOf(map<json> guest) returns string =>
    has(guest["title"]) ? "title: { key: [\"" + gqlText(textOf(guest["title"])) + "\"] } " : "";

const CLIENT_UPDATE_HEAD = "mutation ClientUpdate { clientUpdate( input: {";
const CLIENT_UPDATE_TAIL = "} ) { clientMutationId operationResult result { key firstName lastName gender } } }";

# Decides what Seaware gets for the guest (Mule: the choice in guest_seaware-impl).
#
# + guest - The guest as sent
# + clientsAnswer - Answer of the client search, `()` when nothing was searched
# + ids - "<loyalty id>|<guest id>", written to the client's comments
# + return - The plan
public isolated function clientPlanOf(map<json> guest, json clientsAnswer, string ids) returns ClientPlan {
    json[] edges = listOf(fieldOf(clientsAnswer, "data", "clients", "edges"));
    json found = edges.length() > 0 ? fieldOf(edges[edges.length() - 1], "node") : ();
    string givenClientId = textOf(guest["clientId"]);
    string comments = "comments: \"" + gqlText(ids) + "\", ";

    if givenClientId != "" {
        if edges.length() == 0 {
            return {kind: "none", updateClient: givenClientId};
        }
        string input = "client: {" + quoted("firstName", guest["firstName"]) + comments
            + "}, store: true, updateCollections: true, id: \"Client|" + gqlText(givenClientId) + "\"";
        return {kind: "update", query: CLIENT_UPDATE_HEAD + input + CLIENT_UPDATE_TAIL};
    }

    // Same citizenship and same country of residence as the client found -> that client is updated.
    boolean sameCitizenship = fieldOf(found, "citizenship", "key") == guest["nationalityKey"]
        || fieldOf(found, "citizenship", "name") == guest["nationalityName"];
    boolean sameResidence = fieldOf(found, "countryOfResidence", "key") == guest["countryOfResidenceKey"]
        || fieldOf(found, "countryOfResidence", "name") == guest["countryOfResidenceName"];
    boolean nationalIdOnClient = false;
    foreach json document in listOf(fieldOf(found, "documents")) {
        if fieldOf(document, "type", "key") == "NATIONAL ID" && has(guest["nationalId"])
            && fieldOf(document, "number") == guest["nationalId"] {
            nationalIdOnClient = true;
        }
    }
    string email = emailValid(guest["email"]) ? quoted("eMail", guest["email"]) : "";
    string foundBirthKey = textOf(fieldOf(found, "countryOfBirth", "key"));
    string foundResidenceKey = textOf(fieldOf(found, "countryOfResidence", "key"));

    if edges.length() > 0 && sameCitizenship && sameResidence {
        string input = "client: {" + quoted("birthday", guest["dateOfBirth"]) + email
            + quoted("firstName", guest["firstName"]) + bare("gender", guest["gender"])
            + quoted("lastName", guest["lastName"]) + comments + quoted("mobilePhoneNumber", guest["phone"])
            + bare("mobileIntlCode", guest["intlCode"])
            + keyed("citizenship", textOf(guest["nationalityKey"]))
            + keyed("countryOfBirth", firstText(guest["countryOfBirthKey"], foundBirthKey))
            + keyed("countryOfResidence", firstText(guest["countryOfResidenceKey"], foundResidenceKey))
            + keyed("language", textOf(guest["languageKey"]))
            + documentsOf(guest, nationalIdOnClient) + passportOf(guest) + titleOf(guest)
            + "}, store: true, updateCollections: true, id: \"Client|" + gqlText(textOf(fieldOf(found, "key"))) + "\"";
        return {kind: "update", query: CLIENT_UPDATE_HEAD + input + CLIENT_UPDATE_TAIL};
    }

    string household = "household: { data: { addresses: { " + quoted("city", guest["city"]) + "type: { key: \"PRIMARY\" } } "
        + (has(guest["lastName"]) ? "lastName: \"" + gqlText(textOf(guest["lastName"])) + "\"" : "") + " } }, ";
    string input = "store: true, client: {" + quoted("birthday", guest["dateOfBirth"])
        + keyed("citizenship", textOf(guest["nationalityKey"]))
        + keyed("countryOfBirth", firstText(guest["countryOfBirthKey"], guest["countryOfResidenceKey"], foundBirthKey))
        + keyed("countryOfResidence", firstText(guest["countryOfResidenceKey"], foundResidenceKey))
        + email + quoted("firstName", guest["firstName"]) + bare("gender", guest["gender"])
        + quoted("lastName", guest["lastName"]) + quoted("middleName", guest["middleName"]) + comments
        + keyed("language", textOf(guest["languageKey"])) + bare("mobileIntlCode", guest["intlCode"])
        + documentsOf(guest, nationalIdOnClient) + passportOf(guest) + quoted("mobilePhoneNumber", guest["phone"])
        + (has(guest["title"]) ? titleOf(guest) + ", " : "") + household + "web: { allowAccess: true } }";
    return {
        kind: "create",
        query: "mutation ClientCreate { clientCreate( input: {" + input + "} ) { clientMutationId operationResult"
            + " errors { code message advice severity } result { key } } }"
    };
}

# The client key of a ClientUpdate or ClientCreate answer.
#
# + answer - Seaware's answer
# + return - [updated client, created client], "" where there is none
public isolated function clientKeysOf(json answer) returns [string, string] => [
    textOf(fieldOf(answer, "data", "clientUpdate", "result", "key")),
    textOf(fieldOf(answer, "data", "clientCreate", "result", "key"))
];

# The guest's Seaware client id: the updated one, else the created one.
#
# + updateClient - Key of the updated client
# + createClient - Key of the created client
# + return - The client id, "" when there is none
public isolated function clientIdOf(string updateClient, string createClient) returns string =>
    updateClient != "" ? updateClient : createClient;

# The answer for a guest whose channel does not write to the CRM, or whose CRM step runs afterwards.
#
# + clientId - Seaware client id
# + return - Answer for the guest
public isolated function clientOnlyAnswerOf(string clientId) returns map<json> =>
    {"status": clientId == "" ? "Error" : "Success", "clientId": clientId};

// ---------------------------------------------------------------------------------------------
// CRM upsert
// ---------------------------------------------------------------------------------------------

# The CRM contact of the guest (Mule: guest-crm-upsert-impl).
#
# + guest - The guest as sent
# + clientId - Seaware client id from the Seaware step, "" when there is none
# + globalId - Guest id
# + loyaltyId - Loyalty id
# + return - The contact, or an error when no client id is known
public isolated function crmRecordOf(map<json> guest, string clientId, string globalId, string loyaltyId)
        returns map<json>|error {
    string clientKey = clientId != "" ? clientId : textOf(guest["clientId"]);
    if clientKey == "" {
        return error("Client Id is empty");
    }
    map<json> row = {};
    putText(row, "Age", guest["age"]);
    put(row, "Profile_ID", guest["profileId"]);
    row["Client_ID"] = clientKey;
    put(row, "Club_Account", guest["clubAccount"]);
    putText(row, "Country_of_Birth", birthCountryOf(guest), capital = true);
    put(row, "Date_of_Birth", guest["dateOfBirth"]);
    if emailValid(guest["email"]) {
        row["Email"] = guest["email"];
    }
    putText(row, "First_Name", guest["firstName"], upper = true);
    if has(guest["gender"]) {
        row["Gender"] = genderName(guest["gender"]);
    }
    put(row, "Household_ID", guest["householdId"]);
    put(row, "IQAMA_ID_Expiration_Date", guest["nationalIdExpiryDate"]);
    put(row, "IQAMA_ID_Number", guest["nationalId"]);
    putText(row, "Last_Name", guest["lastName"], upper = true);
    put(row, "Address_Type", guest["addressType"]);
    put(row, "Mailing_City", guest["mailingCity"]);
    put(row, "Mailing_Country", guest["mailingCountry"]);
    put(row, "Mailing_State", guest["mailingState"]);
    put(row, "Mailing_Street", guest["mailingStreet"]);
    put(row, "Mailing_Street_2", guest["mailingStreet2"]);
    put(row, "Mailing_Street_3", guest["mailingStreet3"]);
    put(row, "Mailing_Zip", guest["mailingZip"]);
    put(row, "Middle_Name", guest["middleName"]);
    row["Mobile"] = textOf(guest["intlCode"]) + textOf(guest["phone"]);
    put(row, "City", guest["city"]);
    putText(row, "Nationality", guest["nationalityName"], capital = true);
    row["Passport_Expiration_Date"] = guest["passportExpiryDate"];
    row["Passport_Number"] = guest["passportNumber"];
    put(row, "Phone", guest["phone"]);
    putText(row, "Preferred_Language", guest["languageName"], capital = true);
    row["Global_Guest_ID"] = globalId;
    row["Aroya_Loyalty_ID"] = loyaltyId;
    put(row, "Account_Name", guest["accountName"]);
    put(row, "Account_Type", guest["accountType"]);
    put(row, "Document_Number", guest["documentNumber"]);
    put(row, "Document_Type", guest["documentType"]);
    put(row, "Visa_Type", guest["visaType"]);
    put(row, "Issue_Country", guest["issueCountry"]);
    put(row, "Issue_Date", guest["issueDate"]);
    put(row, "Expiration_Date", guest["expirationDate"]);
    put(row, "Issue_Place", guest["issuePlace"]);
    put(row, "Birth_Place", guest["birthPlace"]);
    putText(row, "Residency", guest["countryOfResidenceName"], capital = true);
    put(row, "Salutation", guest["title"]);
    put(row, "Valid_From", guest["validFrom"]);
    put(row, "Issue_Authority", guest["issueAuthority"]);
    put(row, "Country_ID", guest["countryId"]);
    put(row, "Marketing_Consent", guest["marketingConsent"]);
    put(row, "Onboard", guest["onboard"]);
    put(row, "Is_Primary_Document", guest["isPrimaryDocument"]);
    put(row, "External_ID", guest["externalId"]);
    put(row, "Board_Card_ID", guest["boardCardId"]);
    put(row, "Booking_Number", guest["bookingNumber"]);
    put(row, "Preferred_Communication_Email", guest["preferredCommunicationEmail"]);
    put(row, "Preferred_Communication_Phone", guest["preferredCommunicationPhone"]);
    return row;
}

# The CRM upsert request for one contact, matched on its Seaware client id.
#
# + contact - The contact
# + return - Request body
public isolated function crmUpsertBodyOf(map<json> contact) returns map<json> =>
    {"data": [contact], "duplicate_check_fields": ["Client_ID"], "trigger": ["workflow"]};

# True when a CRM answer says the request, or its first record, failed.
#
# + answer - CRM answer
# + return - True for an error
public isolated function isCrmError(json answer) returns boolean =>
    fieldOf(answer, "status") == "error" || fieldOf(firstRecordOf(answer), "status") == "error";

isolated function firstRecordOf(json answer) returns json {
    json[] records = listOf(fieldOf(answer, "data"));
    return records.length() > 0 ? records[0] : ();
}

# The id of the contact a CRM upsert answer is about.
#
# + answer - CRM answer
# + return - Contact id, "" when there is none
public isolated function crmContactIdOf(json answer) returns string =>
    textOf(fieldOf(firstRecordOf(answer), "details", "id"));

# The CRM path of a contact's photo.
#
# + template - Path with `{contactId}` in it
# + contactId - Contact id
# + return - The path
public isolated function photoPathOf(string template, string contactId) returns string =>
    re `\{contactId\}`.replaceAll(template, contactId);

# A picture as plain base64: a `data:image/...;base64,` start is taken off.
#
# + picture - The picture as sent
# + return - Base64 text
public isolated function plainBase64(string picture) returns string =>
    re `^data:image/(png|jpeg|jpg);base64,`.replace(picture.trim(), "");

# The answer for one guest after the CRM upsert.
#
# + upsertAnswer - CRM answer of the contact upsert
# + imageAnswer - CRM answer of the photo upload, `()` when no photo was sent
# + contact - The contact that was sent
# + clientId - Seaware client id
# + return - Answer for the guest
public isolated function identityAnswerOf(json upsertAnswer, json imageAnswer, map<json> contact, string clientId)
        returns map<json> {
    json first = firstRecordOf(upsertAnswer);
    boolean failed = isCrmError(upsertAnswer);
    boolean imageFailed = fieldOf(imageAnswer, "status") == "error";
    string message = "";
    if failed {
        message = first is () ? textOf(fieldOf(upsertAnswer, "message"))
            : textOf(fieldOf(first, "details", "api_name")) + " - " + textOf(fieldOf(first, "message")) + " "
                + textOf(fieldOf(first, "details", "id"));
    } else if imageFailed {
        message = textOf(fieldOf(imageAnswer, "message"));
    }
    string zohoId = crmContactIdOf(upsertAnswer);
    return {
        "status": failed || imageFailed ? "Error" : "Success",
        "clientId": clientId,
        "globalGuestId": contact["Global_Guest_ID"],
        "loyaltyId": contact["Aroya_Loyalty_ID"],
        "zohoId": zohoId == "" ? () : zohoId,
        "errorMessage": message.trim()
    };
}

// ---------------------------------------------------------------------------------------------
// Guest store
// ---------------------------------------------------------------------------------------------

# The guest-core upsert that follows a CRM upsert (Mule: db-implementation).
#
# + contact - The contact that was sent to the CRM
# + crmAnswer - CRM answer
# + return - Request for the database system API
public isolated function guestCoreUpsertOf(map<json> contact, json crmAnswer) returns map<json> {
    [string, json][] columns = [
        ["global_guest_id", contact["Global_Guest_ID"]],
        ["loyalty_id", contact["Aroya_Loyalty_ID"]],
        ["zoho_contact_id", crmContactIdOf(crmAnswer)],
        ["seaware_client_id", contact["Client_ID"]]
    ];
    if has(contact["Profile_ID"]) {
        columns.push(["otalio_person_id", contact["Profile_ID"]]);
    }
    columns.push(["first_name", contact["First_Name"]], ["last_name", contact["Last_Name"]]);
    if has(contact["Email"]) {
        columns.push(["email", contact["Email"]]);
    }
    if has(contact["Phone"]) {
        columns.push(["phone", contact["Phone"]]);
    }
    string[] names = from [string, json] [name, _] in columns
        select name;
    string[] values = from [string, json] [_, value] in columns
        select has(value) ? sqlText(textOf(value)) : "NULL";
    return dbRequestOf("select", "WITH upsert_guest AS ( INSERT INTO cs_guest_mgmt.cs_guest_core ("
            + string:'join(", ", ...names) + ") VALUES (" + string:'join(", ", ...values)
            + ") ON CONFLICT (seaware_client_id) DO UPDATE SET global_guest_id = EXCLUDED.global_guest_id,"
            + " loyalty_id = EXCLUDED.loyalty_id, zoho_contact_id = EXCLUDED.zoho_contact_id,"
            + " otalio_person_id = EXCLUDED.otalio_person_id, first_name = EXCLUDED.first_name,"
            + " last_name=EXCLUDED.last_name, email=EXCLUDED.email, phone=EXCLUDED.phone RETURNING id)"
            + " SELECT id FROM upsert_guest");
}

# Links the caller's device to the guest (Mule: second statement of db-implementation).
#
# + guestCoreId - Id of the guest-core row
# + deviceId - Device id
# + channel - Channel, stored as the device type
# + return - Request for the database system API
public isolated function deviceLinkOf(string guestCoreId, string deviceId, string channel) returns map<json> =>
    dbRequestOf("insert", "INSERT INTO cs_guest_mgmt.cs_device_link (global_guest_id, device_id, device_type) VALUES ("
            + sqlText(guestCoreId) + ", " + sqlText(deviceId) + ", " + sqlText(channel)
            + ") ON CONFLICT (global_guest_id, device_id) DO UPDATE SET device_type = EXCLUDED.device_type");
