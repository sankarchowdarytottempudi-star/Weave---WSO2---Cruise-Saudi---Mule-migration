// Guest profiles (Mule: guest_booking_impl, guestProfile-pagination-implementation,
// guestProfiles-clientId-implementation, bookingLogin-implementation).

const DEVICE_LINK = "cs_guest_mgmt.cs_device_link";
const GUEST_CORE = "cs_guest_mgmt.cs_guest_core";

// ---------------------------------------------------------------------------------------------
// GET /processGuestBookingInfo
// ---------------------------------------------------------------------------------------------

# The CRM search for the contact with a loyalty id and a guest id.
#
# + loyaltyId - Aroya loyalty id
# + guestId - Global guest id
# + return - Zoho search criteria
public isolated function bookingInfoCriteriaOf(string loyaltyId, string guestId) returns string =>
    "((Aroya_Loyalty_ID:equals:" + loyaltyId + ")and(Global_Guest_ID:equals:" + guestId + "))";

# The guest's details for a booking, from the CRM contact.
#
# + crmAnswer - Answer of the contact search
# + return - Answer body
public isolated function bookingInfoOf(json crmAnswer) returns map<json> {
    json guest = firstOf(fieldOf(crmAnswer, "data"));
    json phone = fieldOf(guest, "Phone");
    boolean long = phone is string && phone.length() > 7;
    return {
        "title": fieldOf(guest, "Title"),
        "firstName": fieldOf(guest, "First_Name"),
        "lastName": fieldOf(guest, "Last_Name"),
        "nativeFirstName": fieldOf(guest, "First_Name_Ar"),
        "nativeLastName": fieldOf(guest, "Last_Name_Ar"),
        "gender": fieldOf(guest, "Gender"),
        "email": fieldOf(guest, "Email"),
        "nationality": fieldOf(guest, "Nationality"),
        "dateOfBirth": fieldOf(guest, "Date_of_Birth"),
        "countryOfResidence": fieldOf(guest, "Residency"),
        "city": fieldOf(guest, "City"),
        "language": fieldOf(guest, "Preferred_Language"),
        "internationalCode": phone is string && long ? "+" + phone.substring(0, 3) : (),
        "phone": phone is string && long ? phone.substring(3) : phone
    };
}

// ---------------------------------------------------------------------------------------------
// POST /guest-profiles
// ---------------------------------------------------------------------------------------------

# The CRM search for the profiles of an e-mail address.
#
# + criteria - Criteria the caller sent, if any
# + identifier - E-mail address
# + return - Zoho search criteria
public isolated function profileCriteriaOf(string? criteria, string identifier) returns string =>
    loginCriteriaOf(criteria, identifier);

# One profile per e-mail address, first name and last name - the contact changed last - newest first.
#
# + records - All contacts found
# + return - The profiles' contacts
public isolated function latestProfilesOf(json[] records) returns json[] {
    map<json> latest = {};
    string[] keys = [];
    foreach json item in records {
        string key = textOf(fieldOf(item, "Email")).toUpperAscii() + "|" + textOf(fieldOf(item, "First_Name")).toUpperAscii()
            + "|" + textOf(fieldOf(item, "Last_Name")).toUpperAscii();
        if !latest.hasKey(key) {
            keys.push(key);
            latest[key] = item;
        } else if textOf(fieldOf(item, "Modified_Time")) >= textOf(fieldOf(latest[key], "Modified_Time")) {
            latest[key] = item;
        }
    }
    json[] chosen = from string key in keys
        select latest[key];
    return from json item in chosen
        order by textOf(fieldOf(item, "Modified_Time")) descending
        select item;
}

# The contacts of one page.
#
# + records - All profiles' contacts
# + page - Page number, from 1
# + perPage - Profiles per page
# + return - The page's contacts
public isolated function pageOf(json[] records, int page, int perPage) returns json[] {
    int 'start = (int:max(page, 1) - 1) * int:max(perPage, 1);
    if 'start >= records.length() {
        return [];
    }
    return records.slice('start, int:min(records.length(), 'start + int:max(perPage, 1)));
}

# A profile, from its CRM contact.
#
# + item - The contact
# + photo - The contact's picture in base64, `()` when it has none
# + return - The profile
public isolated function profileOf(json item, string? photo) returns map<json> {
    json gender = fieldOf(item, "Gender");
    json mobile = fieldOf(item, "Mobile");
    json country = fieldOf(item, "Mailing_Country");
    json city = fieldOf(item, "Mailing_City");
    return {
        "clientId": fieldOf(item, "Client_ID"),
        "profileImage": photo,
        "loyalty": {
            "loyaltyId": fieldOf(item, "Aroya_Loyalty_ID"),
            "loyaltyTier": fieldOf(item, "Loyalty_Tier"),
            "loyaltyPoints": fieldOf(item, "Loyalty_Points_Balance")
        },
        "personalInformation": {
            "username": fieldOf(item, "Email"),
            "fullName": fieldOf(item, "Full_Name"),
            "gender": gender == "M" ? "Male" : (gender == "F" ? "Female" : gender),
            "dateOfBirth": fieldOf(item, "Date_of_Birth"),
            "country": country is () ? fieldOf(item, "Country_of_Birth") : country,
            "city": city is () ? fieldOf(item, "City") : city,
            "email": fieldOf(item, "Email"),
            "phoneNumber": mobile is () ? () : "+" + re `^\+`.replace(textOf(mobile), ""),
            "language": fieldOf(item, "Preferred_Language")
        }
    };
}

# The answer of POST /guest-profiles.
#
# + profiles - The page's profiles
# + page - Page number
# + perPage - Profiles per page
# + total - Number of profiles on all pages
# + return - Answer body
public isolated function profilesAnswerOf(json[] profiles, int page, int perPage, int total) returns map<json> => {
    "profile": {
        "profiles": profiles,
        "pagination": {
            "page": page,
            "perPage": perPage,
            "totalRecords": total,
            "totalPages": perPage > 0 ? (total + perPage - 1) / perPage : 0
        }
    }
};

// ---------------------------------------------------------------------------------------------
// POST /guest-profiles/{guestId} - trips
// ---------------------------------------------------------------------------------------------

# Links the caller's device to the guest of a Seaware client.
#
# + deviceId - Device id
# + deviceType - Device type (the caller's source system)
# + clientId - Seaware client id
# + return - Request for the database system API
public isolated function tripsDeviceLinkOf(string deviceId, string deviceType, string clientId) returns map<json> =>
    dbRequestOf("insert", "INSERT INTO " + DEVICE_LINK + " (global_guest_id, device_id, device_type) SELECT g.id, :deviceId,"
            + " :deviceType FROM " + GUEST_CORE + " g WHERE g.seaware_client_id = :clientId ON CONFLICT (global_guest_id,"
            + " device_id) DO UPDATE SET device_type = EXCLUDED.device_type, last_seen_at = now()",
            {"deviceId": deviceId, "deviceType": deviceType, "clientId": clientId});

# The Seaware query for the reservations of a client. It asks for the fields the answer of
# POST /guest-profiles/{guestId} is built from and no others: every further field is work for
# Seaware on each reservation and each guest that nobody reads.
#
# + clientId - Seaware client id
# + return - Request body
public isolated function reservationsQueryOf(string clientId) returns map<json> => {
    "query": "query Reservations { reservations( params: { client: { key: \"" + gqlText(clientId) + "\" } } first: 500 after: \"\" )"
        + " { edges { node { key id guestCount currency { key } status { name } invoiceTotals { invoiceTotal"
        + " currentDue { amount date } payments pendingPayments pendingRefunds } contact { key } guests { seqN"
        + " client { key mobileIntlCode mobilePhoneNumber fullName eMail birthday gender household { addresses { city } }"
        + " countryOfResidence { name } language { name } } voyages { pkg { name type { name comments key }"
        + " destinations { name } } sail { from { dateTime port { name } } to { dateTime port { name } } }"
        + " cabinChain { cabin { number category { comments code } deck { number } } } } } } } } }",
    "variables": {}
};

isolated function clientKeyOf(json guest) returns string => textOf(fieldOf(guest, "client", "key"));

isolated function isFirstGuest(json guest) returns boolean => intOf(fieldOf(guest, "seqN"), 0) == 1;

isolated function firstVoyageOf(json guest) returns json => firstOf(fieldOf(guest, "voyages"));

isolated function orDefault(json value, json fallback) returns json => value is () ? fallback : value;

isolated function dateOf(json dateTime) returns string {
    string text = textOf(dateTime);
    return text.length() >= 10 ? text.substring(0, 10) : "";
}

isolated function cabinsOf(json[] guests) returns json[] {
    string[] numbers = [];
    map<map<json>> cabins = {};
    map<json[]> occupants = {};
    foreach json guest in guests {
        foreach json chain in listOf(fieldOf(firstVoyageOf(guest), "cabinChain")) {
            json cabin = fieldOf(chain, "cabin");
            if cabin is () {
                continue;
            }
            string number = textOf(fieldOf(cabin, "number"));
            if !cabins.hasKey(number) {
                numbers.push(number);
                cabins[number] = {
                    "number": fieldOf(cabin, "number"),
                    "category": fieldOf(cabin, "category", "code"),
                    "cabinType": fieldOf(cabin, "category", "comments"),
                    "deck": fieldOf(cabin, "deck", "number")
                };
                occupants[number] = [];
            }
            // Mule (guestProfiles-clientId-implementationSub_Flow, mapCabins): the rows it groups carry
            // cabinNumber -> "number", guestClientId -> "clientId" (cast to String), guestFullName -> "fullName";
            // guestSeqN only decides primarySailor (seqN == 1). Only these output names reach the caller.
            json clientKey = fieldOf(guest, "client", "key");
            occupants.get(number).push({
                "clientId": clientKey is () ? () : textOf(clientKey),
                "fullName": fieldOf(guest, "client", "fullName"),
                "primarySailor": isFirstGuest(guest)
            });
        }
    }
    json[] out = [];
    foreach string number in numbers {
        map<json> cabin = cabins.get(number);
        cabin["guests"] = occupants.get(number);
        out.push(cabin);
    }
    return out;
}

isolated function tripOf(json reservation) returns map<json> {
    json[] guests = listOf(fieldOf(reservation, "guests"));
    json voyage = guests.length() > 0 ? firstVoyageOf(guests[0]) : ();
    json pkg = fieldOf(voyage, "pkg");
    json totals = fieldOf(reservation, "invoiceTotals");
    json[] sailors = from json guest in guests
        select {
            "seqN": fieldOf(guest, "seqN"),
            "clientId": fieldOf(guest, "client", "key"),
            "fullName": fieldOf(guest, "client", "fullName"),
            "primarySailor": isFirstGuest(guest)
        };
    return {
        "bookingId": fieldOf(reservation, "id"),
        "reservationKey": fieldOf(reservation, "key"),
        "reservationStatus": fieldOf(reservation, "status", "name"),
        "guestCount": orDefault(fieldOf(reservation, "guestCount"), 0),
        "departure": {
            "port": fieldOf(voyage, "sail", "from", "port", "name"),
            "dateTime": fieldOf(voyage, "sail", "from", "dateTime")
        },
        "arrival": {
            "port": fieldOf(voyage, "sail", "to", "port", "name"),
            "dateTime": fieldOf(voyage, "sail", "to", "dateTime")
        },
        "package": {
            "code": fieldOf(pkg, "type", "key"),
            "name": orDefault(fieldOf(pkg, "type", "comments"), fieldOf(pkg, "name")),
            "typeName": fieldOf(pkg, "type", "name"),
            "destination": fieldOf(firstOf(fieldOf(pkg, "destinations")), "name")
        },
        "cabins": cabinsOf(guests),
        "financials": {
            "totalAmount": orDefault(fieldOf(totals, "invoiceTotal"), 0),
            "payments": orDefault(fieldOf(totals, "payments"), 0),
            "pendingPayments": orDefault(fieldOf(totals, "pendingPayments"), 0),
            "pendingRefunds": orDefault(fieldOf(totals, "pendingRefunds"), 0),
            "currentDue": fieldOf(totals, "currentDue", "amount"),
            "currentDueDate": fieldOf(totals, "currentDue", "date"),
            "currency": fieldOf(reservation, "currency", "key")
        },
        "guests": sailors
    };
}

isolated function companionOf(json guest) returns map<json> {
    json person = fieldOf(guest, "client");
    json gender = fieldOf(person, "gender");
    json intlCode = fieldOf(person, "mobileIntlCode");
    json number = fieldOf(person, "mobilePhoneNumber");
    return {
        "clientId": clientKeyOf(guest),
        "profileImage": (),
        "fullName": fieldOf(person, "fullName"),
        "email": fieldOf(person, "eMail"),
        "dateOfBirth": fieldOf(person, "birthday"),
        "relation": "Family & Friends",
        "gender": gender == "M" ? "Male" : (gender == "F" ? "Female" : ()),
        "country": fieldOf(person, "countryOfResidence", "name"),
        "city": fieldOf(firstOf(fieldOf(person, "household", "addresses")), "city"),
        "phoneNumber": intlCode is () || number is () ? () : "+" + textOf(intlCode) + textOf(number),
        "language": fieldOf(person, "language", "name")
    };
}

# The answer of POST /guest-profiles/{guestId}: the guest's trips, and the people who sail on the
# reservations where the guest is the primary guest.
#
# + seawareAnswer - Answer of the reservations query
# + clientId - Seaware client id of the guest
# + today - Today's date as yyyy-MM-dd
# + return - Answer body
public isolated function tripsAnswerOf(json seawareAnswer, string clientId, string today) returns map<json> {
    json[] current = [];
    json[] upcoming = [];
    json[] old = [];
    json[] companions = [];
    map<boolean> seen = {};
    foreach json edge in listOf(fieldOf(seawareAnswer, "data", "reservations", "edges")) {
        json reservation = fieldOf(edge, "node");
        json[] guests = listOf(fieldOf(reservation, "guests"));
        if !guests.some(g => clientKeyOf(g) == clientId) {
            continue;
        }
        boolean primary = textOf(fieldOf(reservation, "contact", "key")) == clientId
            || guests.some(g => isFirstGuest(g) && clientKeyOf(g) == clientId);
        if primary {
            foreach json guest in guests {
                string key = clientKeyOf(guest);
                if key != clientId && !seen.hasKey(key) {
                    seen[key] = true;
                    companions.push(companionOf(guest));
                }
            }
        }
        json sail = fieldOf(firstVoyageOf(guests[0]), "sail");
        string fromDate = dateOf(fieldOf(sail, "from", "dateTime"));
        string toDate = dateOf(fieldOf(sail, "to", "dateTime"));
        if fromDate != "" && toDate != "" && fromDate <= today && toDate >= today {
            current.push(tripOf(reservation));
        } else if fromDate != "" && fromDate > today {
            upcoming.push(tripOf(reservation));
        } else if toDate != "" && toDate < today {
            old.push(tripOf(reservation));
        }
    }
    return {
        "familyAndFriends": companions,
        "trips": {"Current Trips": current, "Future Trips": upcoming, "Old Trips": old}
    };
}

// ---------------------------------------------------------------------------------------------
// PUT /guest-profiles/{guestId} - edit
// ---------------------------------------------------------------------------------------------

isolated function personalOf(map<json> body) returns map<json> {
    json pi = body["personalInformation"];
    return pi is map<json> ? pi : {};
}

# First name and last name of a full name: the first word, and the rest.
#
# + fullName - Full name
# + return - [first name, last name], "" where there is none
public isolated function namePartsOf(json fullName) returns [string, string] {
    string[] words = from string word in re ` `.split(textOf(fullName))
        where word != ""
        select word;
    if words.length() == 0 {
        return ["", ""];
    }
    return [words[0], string:'join(" ", ...words.slice(1))];
}

isolated function mapped(map<string> names, json value) returns string {
    string text = textOf(value);
    string? known = names[text];
    return (known is string ? known : text).toUpperAscii();
}

# The Seaware client update of an edited profile.
#
# + clientId - Seaware client id
# + body - The caller's body
# + return - Request body
public isolated function clientUpdateQueryOf(string clientId, map<json> body) returns map<json> {
    map<json> pi = personalOf(body);
    [string, string] [firstName, lastName] = namePartsOf(pi["fullName"]);
    string phone = re `^\+`.replace(textOf(pi["phoneNumber"]), "");
    boolean saudi = phone.startsWith("966");
    string countryKey = mapped({"Saudi Arabia": "SA", "English": "EN"}, pi["country"]);
    string languageKey = mapped({"English": "ENG", "Arabic": "AR"}, pi["language"]);
    string gender = textOf(pi["gender"]);
    string genderKey = gender == "Male" || gender == "M" ? "M" : (gender == "Female" || gender == "F" ? "F" : "");
    string city = textOf(pi["city"]);

    string fields = quoted("birthday", pi["dateOfBirth"]) + quoted("eMail", pi["email"]) + quoted("firstName", firstName)
        + quoted("lastName", lastName) + bare("gender", genderKey) + bare("mobileIntlCode", saudi ? "966" : "")
        + quoted("mobilePhoneNumber", saudi ? phone.substring(3) : phone) + keyed("citizenship", countryKey)
        + keyed("countryOfBirth", countryKey) + keyed("countryOfResidence", countryKey) + keyed("language", languageKey)
        + "web: { allowAccess: true }, ";
    if city != "" || lastName != "" {
        fields += "household: { data: { "
            + (city == "" ? "" : "addresses: { city: \"" + gqlText(city) + "\", type: { key: \"PRIMARY\" } }, ")
            + (lastName == "" ? "" : "lastName: \"" + gqlText(lastName) + "\"") + " } }, ";
    }
    return {
        "query": "mutation ClientUpdate { clientUpdate( input: { id: \"Client|" + gqlText(clientId) + "\", store: true,"
            + " updateCollections: true, client: {" + fields + "} } ) { clientMutationId operationResult result { key type"
            + " { key reqPointsQty comments } mobileIntlCode mobilePhoneNumber guid firstName lastName household { addresses"
            + " { type { key comments } city } } middleName fullName eMail title { key } birthday birthPlace countryOfBirth"
            + " { name } gender citizenship { name } language { key } guestType { key comments } comments } errors { code"
            + " message advice severity } } }"
    };
}

isolated function emailOf(map<json> pi) returns json => pi["email"] is () ? pi["username"] : pi["email"];

# The CRM contact of an edited profile.
#
# + clientId - Seaware client id
# + body - The caller's body
# + return - The contact
public isolated function editContactOf(string clientId, map<json> body) returns map<json> {
    map<json> pi = personalOf(body);
    [string, string] [firstName, lastName] = namePartsOf(pi["fullName"]);
    map<json> row = {"Client_ID": clientId};
    put(row, "Email", emailOf(pi));
    putText(row, "First_Name", firstName, upper = true);
    putText(row, "Last_Name", lastName, upper = true);
    put(row, "Gender", pi["gender"]);
    put(row, "Date_of_Birth", pi["dateOfBirth"]);
    putText(row, "Residency", pi["country"], capital = true);
    put(row, "Mailing_Country", pi["country"]);
    put(row, "City", pi["city"]);
    put(row, "Mailing_City", pi["city"]);
    put(row, "Mobile", pi["phoneNumber"]);
    putText(row, "Preferred_Language", pi["language"], capital = true);
    return row;
}

# The guest-core update of an edited profile.
#
# + clientId - Seaware client id
# + body - The caller's body
# + now - The current moment as text (Mule writes it to created_by and updated_by)
# + return - Request for the database system API
public isolated function editGuestCoreOf(string clientId, map<json> body, string now) returns map<json> {
    map<json> pi = personalOf(body);
    [string, string] [firstName, lastName] = namePartsOf(pi["fullName"]);
    string[] sets = [];
    if firstName != "" {
        sets.push("first_name = " + sqlText(firstName.toUpperAscii()));
    }
    if lastName != "" {
        sets.push("last_name = " + sqlText(lastName.toUpperAscii()));
    }
    if has(emailOf(pi)) {
        sets.push("email = " + sqlText(textOf(emailOf(pi))));
    }
    if has(pi["phoneNumber"]) {
        sets.push("phone = " + sqlText(textOf(pi["phoneNumber"])));
    }
    sets.push("created_by = " + sqlText(now), "updated_by = " + sqlText(now));
    map<json> meta = {};
    put(meta, "gender", pi["gender"]);
    put(meta, "date_of_birth", pi["dateOfBirth"]);
    putText(meta, "residency", pi["country"], capital = true);
    put(meta, "mailing_country", pi["country"]);
    put(meta, "city", pi["city"]);
    put(meta, "mailing_city", pi["city"]);
    putText(meta, "preferred_language", pi["language"], capital = true);
    if meta.length() > 0 {
        sets.push("metadata = COALESCE(metadata, '{}'::jsonb) || " + sqlText(meta.toJsonString()) + "::jsonb");
    }
    return dbRequestOf("select", "WITH updated AS ( UPDATE " + GUEST_CORE + " SET " + string:'join(", ", ...sets)
            + " WHERE seaware_client_id = " + sqlText(clientId) + " RETURNING id) SELECT id FROM updated");
}

# The answer of PUT /guest-profiles/{guestId}.
#
# + body - The caller's body
# + seawareAnswer - Seaware's answer of the client update
# + crmAnswer - CRM answer of the contact upsert
# + imageAnswer - CRM answer of the photo upload, `()` when no photo was sent
# + return - [HTTP status, answer body]
public isolated function editAnswerOf(map<json> body, json seawareAnswer, json crmAnswer, json imageAnswer)
        returns [int, map<json>] {
    map<json> pi = personalOf(body);
    [string, string] [firstName, lastName] = namePartsOf(pi["fullName"]);
    json first = firstOf(fieldOf(crmAnswer, "data"));
    json zohoStatus = orDefault(fieldOf(first, "status"), fieldOf(crmAnswer, "status"));
    json imageStatus = orDefault(fieldOf(imageAnswer, "status"), fieldOf(firstOf(fieldOf(imageAnswer, "data")), "status"));
    string seawareKey = textOf(fieldOf(seawareAnswer, "data", "clientUpdate", "result", "key"));
    boolean hasImage = has(body["profileImage"]);

    [string, json][] candidates = [
        ["profileImage", body["profileImage"]],
        ["fullName", pi["fullName"]],
        ["firstName", firstName],
        ["lastName", lastName],
        ["gender", pi["gender"]],
        ["dateOfBirth", pi["dateOfBirth"]],
        ["country", pi["country"]],
        ["city", pi["city"]],
        ["email", pi["email"]],
        ["phoneNumber", pi["phoneNumber"]],
        ["language", pi["language"]]
    ];
    string[] updated = from [string, json] [name, value] in candidates
        where has(value)
        select name;

    string message = "";
    if zohoStatus == "error" {
        message = textOr(fieldOf(first, "message"), textOf(fieldOf(crmAnswer, "message")));
    } else if imageStatus == "error" {
        message = textOr(fieldOf(imageAnswer, "message"), textOf(fieldOf(firstOf(fieldOf(imageAnswer, "data")), "message")));
    }
    boolean failed = zohoStatus == "error" || imageStatus == "error" || seawareKey == "";
    string zohoId = crmContactIdOf(crmAnswer);
    return [failed ? 400 : 200, {
        "status": failed ? "Error" : "Success",
        "ClientId": seawareKey == "" ? () : seawareKey,
        "zohoId": zohoId == "" ? () : zohoId,
        "profileImageUpdated": hasImage && imageStatus != "error",
        "updatedFields": updated,
        "updatedFieldsCount": updated.length(),
        "errorMessage": message
    }];
}

// ---------------------------------------------------------------------------------------------
// POST /bookingLogin
// ---------------------------------------------------------------------------------------------

# Shore: links the caller's device to the guest of an Otalio profile.
#
# + body - The caller's body
# + return - Request for the database system API
public isolated function bookingLoginShoreOf(map<json> body) returns map<json> =>
    dbRequestOf("insert", "INSERT INTO " + DEVICE_LINK + " (global_guest_id, device_id, device_type, last_seen_at)"
            + " SELECT id, :deviceId, :deviceType, NOW() FROM " + GUEST_CORE + " WHERE otalio_person_id = :profileId"
            + " ON CONFLICT (global_guest_id, device_id) DO UPDATE SET last_seen_at = NOW()",
            {"profileId": body["profileId"], "deviceId": body["client_deviceId"], "deviceType": body["client_channel"]});

# Ship: stores the guest of a Seaware client before the device is linked.
#
# + body - The caller's body
# + return - Request for the database system API
public isolated function bookingLoginShipGuestOf(map<json> body) returns map<json> =>
    dbRequestOf("insert", "INSERT INTO " + GUEST_CORE + " (id, global_guest_id, loyalty_id, zoho_contact_id,"
            + " seaware_client_id, otalio_person_id, first_name, last_name, email, phone, status, created_at, updated_at)"
            + " VALUES (gen_random_uuid(), '', '', '', :seawareClientId, :profileId, :firstName, :lastName, :email, :phone,"
            + " 'guest', NOW(), NOW()) ON CONFLICT (seaware_client_id) DO UPDATE SET otalio_person_id ="
            + " EXCLUDED.otalio_person_id, first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name,"
            + " email = EXCLUDED.email, phone = EXCLUDED.phone, updated_at = NOW()",
            {
                "seawareClientId": body["seaware_client_id"],
                "profileId": body["profileId"],
                "firstName": body["first_name"],
                "lastName": body["last_name"],
                "email": body["email"],
                "phone": body["phone"]
            });

# Ship: links the caller's device to the guest of a Seaware client.
#
# + body - The caller's body
# + return - Request for the database system API
public isolated function bookingLoginShipDeviceOf(map<json> body) returns map<json> =>
    dbRequestOf("insert", "INSERT INTO " + DEVICE_LINK + " (global_guest_id, device_id, device_type, last_seen_at)"
            + " SELECT id, :deviceId, :deviceType, NOW() FROM " + GUEST_CORE + " WHERE seaware_client_id = :seawareClientId"
            + " ON CONFLICT (global_guest_id, device_id) DO UPDATE SET last_seen_at = NOW()",
            {
                "seawareClientId": body["seaware_client_id"],
                "deviceId": body["client_deviceId"],
                "deviceType": body["client_channel"]
            });
