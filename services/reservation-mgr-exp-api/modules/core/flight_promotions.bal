import ballerina/lang.regexp;

// The `flightpromotion` operation, ported from
// reservation-mgr-exp-api-implementation-flight-promotions-Sub_Flow (Mule, v1).
//
// Mule called Seaware GraphQL directly from the experience layer. Here the same two queries
// go through seaware-sys-api (the system layer), so Seaware's address, TLS and retries stay
// in one place. The rules below are the DataWeave rules, unchanged:
//   1. read pkg key, cabin category keys and guest sequence numbers from the caller's text;
//   2. ask availablePromotions for that package, category and guests;
//   3. for each promotion, price availableVoyages with that promotion;
//   4. keep categories whose key equals the requested keys (joined by ",") and that use a
//      TRANSFER promotion; drop voyages and promotions left with nothing.

final string:RegExp PKG_KEY = re `pkg:\s*\{\s*key:\s*(.*?)\s*\}`;
final string:RegExp CATEGORY_KEY = re `category:\s*\{\s*key:\s*(.*?)\s*\}`;
final string:RegExp SEQ_N = re `seqN:\s*(\d+)`;
final string:RegExp QUOTES_AND_SLASHES = re `["\\]`;

# What a flightpromotion request asks for.
#
# + pkgKey - Package key
# + cabinCategoryKey - Cabin category keys
# + guests - Guest sequence numbers
public type FlightPromotionRequest record {|
    string pkgKey;
    string[] cabinCategoryKey;
    int[] guests;
|};

isolated function clean(string text) returns string => QUOTES_AND_SLASHES.replaceAll(text, "").trim();

isolated function firstGroup(string:RegExp pattern, string text) returns string {
    regexp:Groups? groups = pattern.findGroups(text);
    if groups is () || groups.length() < 2 {
        return "";
    }
    regexp:Span? span = groups[1];
    return span is () ? "" : span.substring();
}

# Reads the request (Mule "Parse Request").
#
# + query - The caller's GraphQL text
# + return - The parsed request
public isolated function parseFlightPromotionRequest(string query) returns FlightPromotionRequest {
    string category = clean(firstGroup(CATEGORY_KEY, query));
    string[] keys = category == "" ? [] : from string k in re `,`.split(category)
            select k.trim();
    int[] guests = [];
    foreach regexp:Groups g in SEQ_N.findAllGroups(query) {
        regexp:Span? span = g[1];
        if span is regexp:Span {
            int|error n = int:fromString(span.substring());
            if n is int {
                guests.push(n);
            }
        }
    }
    return {pkgKey: clean(firstGroup(PKG_KEY, query)), cabinCategoryKey: keys, guests};
}

// Mule: write(guests, "application/json") replace "\n" with "" replace " " with ""
isolated function compactJson(int[] values) returns string => re `\s`.replaceAll(values.toJsonString(), "");

# The availablePromotions query (Mule "AvailablePromotions-Map").
#
# + req - The request
# + return - GraphQL request body
public isolated function availablePromotionsQuery(FlightPromotionRequest req) returns json {
    string cabinKey = string:'join(",", ...req.cabinCategoryKey);
    return {
        query: "query AvailablePromotions {  availablePromotions(    params: {      reservation: {        voyages: [          {"
            + string `            category: { key: "${cabinKey}" }            pkg: { key: "${req.pkgKey}" }`
            + string `            guests: ${compactJson(req.guests)}          }        ]      }    }  ) {    promotion { key code name }  }}`,
        variables: {}
    };
}

# Promotion keys from an availablePromotions answer.
#
# + answer - Seaware answer
# + return - Promotion keys, in order
public isolated function promotionKeysOf(json answer) returns string[] {
    json|error list = answer.data.availablePromotions;
    if list !is json[] {
        return [];
    }
    string[] keys = [];
    foreach json p in list {
        json|error key = p.promotion.key;
        if key is string {
            keys.push(key);
        }
    }
    return keys;
}

# The availableVoyages pricing query for one promotion (Mule "AvailableVoyages-Map").
# Guest 1 is an adult, the others children; currency SAR, source code INT-CON, as in Mule.
#
# + req - The request
# + promoKey - Promotion key
# + return - GraphQL request body
public isolated function priceWithPromotionQuery(FlightPromotionRequest req, string promoKey) returns json {
    string cabinKey = string:'join(",", ...req.cabinCategoryKey);
    int maxSeq = 0;
    foreach int g in req.guests {
        if g > maxSeq {
            maxSeq = g;
        }
    }
    string[] guestDecls = [];
    foreach int n in 1 ... maxSeq {
        string age = n == 1 ? "AgeCategory|SHIP|ADULT" : "AgeCategory|SHIP|CHILD";
        guestDecls.push(string `{ seqN: ${n}, ageCategoryId: "${age}" }`);
    }
    string reservationGuests = "[" + string:'join(", ", ...guestDecls) + "]";
    return {
        query: "query AvailableVoyages {  availableVoyages(    params: {      availability: OK      productTypes: [{ key: \"CRUISE\" }]"
            + "      reservation: {        currency: { key: [\"SAR\"] }        sourceCode: \"INT-CON\""
            + string `        guests: ${reservationGuests}        voyages: [          {            cabinSeqN: 1`
            + string `            category: { key: "${cabinKey}" }            pkg: { key: "${req.pkgKey}" }`
            + string `            guests: ${compactJson(req.guests)}          }        ]      }      inactive: false`
            + string `      packages: { key: "${req.pkgKey}" }      promotions: [{ key: "${promoKey}" }]    }  ) {`
            + "    pkg { key type { key comments landDays sailDays active } }    availableCategories {      reference "
            + "      cabinCategory { key code }      price { total discount pricePerGuest { seqN total discount } }"
            + "      addons { addon { key name category { key comments } type { key comments } classifications { code } } price }"
            + "      usedPromotions { promotion { key id type group code name active } }    }  }}",
        variables: {}
    };
}

isolated function usesTransferPromotion(json category) returns boolean {
    json|error used = category.usedPromotions;
    if used !is json[] {
        return false;
    }
    foreach json u in used {
        json|error t = u.promotion.'type;
        if t is string && t.toUpperAscii() == "TRANSFER" {
            return true;
        }
    }
    return false;
}

# The final answer (Mule "AvailableVoyages-final-Map").
#
# + priced - One entry per promotion: [promotion key, Seaware answer]
# + req - The request
# + return - `[{promoKey, availableVoyages: [{pkg, availableCategories}]}]`
public isolated function transferPromotionsOf([string, json][] priced, FlightPromotionRequest req) returns json[] {
    string targetKey = req.cabinCategoryKey.length() == 0 ? "AC01,BC" : string:'join(",", ...req.cabinCategoryKey);
    json[] out = [];
    foreach [string, json] [promoKey, answer] in priced {
        json|error voyages = answer.data.availableVoyages;
        if voyages !is json[] {
            continue;
        }
        json[] kept = [];
        foreach json voyage in voyages {
            json|error categories = voyage.availableCategories;
            json[] matching = [];
            if categories is json[] {
                foreach json c in categories {
                    json|error key = c.cabinCategory.key;
                    if key is string && key.trim() == targetKey && usesTransferPromotion(c) {
                        matching.push(c);
                    }
                }
            }
            if matching.length() > 0 {
                json|error pkg = voyage.pkg;
                kept.push({pkg: pkg is json ? pkg : (), availableCategories: matching});
            }
        }
        if kept.length() > 0 {
            out.push({promoKey, availableVoyages: kept});
        }
    }
    return out;
}
