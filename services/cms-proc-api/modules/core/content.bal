// Content rules of the old CMS application (get-contents-implementation.xml), ported one to one.
// A content request names a "slug"; the slug picks a handler, and the handler decides which
// Strapi collection is read and with which query. Nothing here calls out; it only builds the target.
import ballerina/url;

# Where a content request goes.
#
# + pathKey - name of the Strapi path setting (the old `strapi.path.<name>` property)
# + query - query string to send, already encoded; empty when the old flow sent none
public type Target record {|
    string pathKey;
    string query;
|};

const PAGE_SLUG = "filters[page_slug][$eq]";

// slug -> handler, as in the old "content-implementationSub_Flow". Any other slug is a page.
final readonly & map<string> SLUG_HANDLERS = {
    "cabin": "cabin",
    "packages": "packages",
    "itineraries": "itineraries",
    "excursions": "excursions",
    "add-ons": "addons",
    "destinations": "destinations",
    "destination-experiences": "destination-experiences",
    "port-details": "port-details",
    "destination-activities": "destination-activities",
    "header": "header",
    "footer": "footer",
    "onboard-excursion": "onboardExcursion",
    "spas": "spas",
    "dinings": "dinings",
    "offers": "offers",
    "offer1": "offers",
    "offer2": "offers",
    "privacy-policy": "docs",
    "cookies": "docs",
    "terms-and-conditions": "docs",
    "flight-transport-terms": "docs",
    "deckInfoTranslationMap": "docs",
    "popup-msg": "docs",
    "icons": "docs",
    "visa-booking-request": "docs",
    "website-icons": "docs",
    "prohibited-items-policy": "docs",
    "booking-cancellation-policy": "docs",
    "errors": "docs",
    "embarkations": "embarkations",
    "travel-trade-partners": "travelTradePartners",
    "translation-messages": "mobile-page-generals",
    "spa-policy": "mobile-page-generals",
    "dining-policy": "mobile-page-generals",
    "packages-policy": "mobile-page-generals",
    "safety": "mobile-page-cruises",
    "onboard_homepage": "mobile-page-cruises",
    "wellness_emergency": "mobile-page-cruises",
    "guest-services": "mobile-page-cruises",
    "dis-embarkation": "mobile-page-cruises",
    "explore-banner-mobile": "mobile-page-cruises",
    "post_booking_check_in": "mobile-page-pre-cruises",
    "pre-embarkation-essentials": "mobile-page-pre-cruises",
    "precruise_homepage": "mobile-page-pre-cruises",
    "onboarding": "mobile-page-pre-cruises",
    "configurations": "configurations"
};

# The Strapi path settings the content rules can ask for.
public final readonly & string[] PATH_KEYS = [
    "pages", "cabin-categories", "packages", "itineraries", "excursions", "add-ons", "destinations",
    "destination-experiences", "port-details", "destination-activities", "header", "footer",
    "onboardExcursion", "spas", "dinings", "offers", "docs", "embarkations", "travelTradePartners",
    "travelPartnersLists", "mobile-page-generals", "mobile-page-cruises", "mobile-page-pre-cruises",
    "configurations"
];

# The handler of a slug ("pages" for any slug the old flow did not list).
#
# + slug - the {slug} part of the path, empty when the path has none
# + return - handler name
public isolated function handlerOf(string slug) returns string => SLUG_HANDLERS[slug] ?: "pages";

# Builds the Strapi target of a content request exactly as the old flow did.
#
# + slug - the {slug} part of the path, empty when the path has none
# + categoryType - the {categoryType} part of the path, () when the path has none
# + requestPath - the request path without the query string
# + rawQuery - the query string as the caller sent it (not decoded)
# + params - first value of each query parameter, decoded
# + return - path setting and query
public isolated function contentTarget(string slug, string? categoryType, string requestPath, string rawQuery,
        map<string> params) returns Target {
    string cat = categoryType ?: "";
    string locale = params["locale"] ?: "en";
    match handlerOf(slug) {
        "cabin" => {
            return {pathKey: "cabin-categories", query: cat != ""
                ? filtered("filters[cabin_types][cabin_type_detail][code]", cat, locale) : everything(locale)};
        }
        "packages" => {
            string destination = params["destination"] ?: "";
            string duration = params["duration"] ?: "";
            string query = everything(locale);
            if cat != "" {
                query = filtered("filters[pkg_code][$eq]", cat, locale);
            } else if destination != "" {
                query = filtered("filters[destination][page_slug][$eq]", destination, locale);
            } else if duration != "" {
                query = filtered("filters[duration][$eq]", duration, locale);
            }
            return {pathKey: "packages", query};
        }
        "itineraries" => {
            // The old flow passed the caller's own query on, and ran encodeURI over the whole of it.
            string cleaned = withoutIndexes(rawQuery);
            string query = "populate=*&locale=" + locale;
            if cleaned != "" {
                query = cleaned + (cleaned.includes("populate=") ? "" : "&populate=*");
            } else if cat != "" {
                query = "filters[page_slug][$eq]=" + cat + "&populate=*&locale=" + locale;
            }
            return {pathKey: "itineraries", query: encodeUri(query)};
        }
        "excursions" => {
            string codes = params["shorex_code"] ?: "";
            string query = (codes != "" ? "shorex_code=" + codes + "&" : "") + "populate=*&locale=" + locale;
            return {pathKey: "excursions", query: encodeUri(query, true)};
        }
        "addons" => {
            string cleaned = withoutIndexes(rawQuery);
            string query = "populate=*&locale=" + locale;
            if cleaned != "" && cat == "" {
                query = cleaned + (cleaned.includes("populate=") ? "" : "&populate=*");
            } else if cat != "" {
                query = "filters[page_slug][$eq]=" + cat + "&populate=*&locale=" + locale;
            }
            return {pathKey: "add-ons", query: encodeUri(query, true)};
        }
        "destinations" => {
            return {pathKey: "destinations", query: byName(cat, locale)};
        }
        "port-details" => {
            return {pathKey: "port-details", query: byName(cat, locale)};
        }
        "destination-activities" => {
            return {pathKey: "destination-activities", query: byName(cat, locale)};
        }
        "destination-experiences" => {
            return {pathKey: "destination-experiences", query: bySlug(cat, locale)};
        }
        "embarkations" => {
            return {pathKey: "embarkations", query: bySlug(cat, locale)};
        }
        "header" => {
            return {pathKey: "header", query: everything(locale)};
        }
        "footer" => {
            return {pathKey: "footer", query: everything(locale)};
        }
        "onboardExcursion" => {
            return {pathKey: "onboardExcursion", query: everything(locale)};
        }
        "spas" => {
            return {pathKey: "spas", query: everything(locale)};
        }
        "dinings" => {
            return {pathKey: "dinings", query: everything(locale)};
        }
        "configurations" => {
            return {pathKey: "configurations", query: everything(locale)};
        }
        "offers" => {
            return {pathKey: "offers", query: slug == "offer1" || slug == "offer2"
                ? filtered(PAGE_SLUG, slug, locale) : everything(locale)};
        }
        "docs" => {
            return {pathKey: "docs", query: filtered(PAGE_SLUG, slug, locale)};
        }
        "mobile-page-generals" => {
            return {pathKey: "mobile-page-generals", query: filtered(PAGE_SLUG, slug, locale)};
        }
        "mobile-page-pre-cruises" => {
            return {pathKey: "mobile-page-pre-cruises", query: filtered(PAGE_SLUG, slug, locale)};
        }
        "mobile-page-cruises" => {
            return {pathKey: "mobile-page-cruises", query: filtered(PAGE_SLUG, slug, locale)};
        }
        "travelTradePartners" => {
            return cat != ""
                ? {pathKey: "travelPartnersLists", query: filtered(PAGE_SLUG, cat, locale)}
                : {pathKey: "travelTradePartners", query: everything(locale)};
        }
    }
    return {pathKey: "pages", query: pageQuery(slug, categoryType, requestPath.includes("/categories"), locale)};
}

// The old "pages-handlerSubFlow".
isolated function pageQuery(string slug, string? categoryType, boolean inCategories, string locale) returns string {
    if slug == "profile" && categoryType is string {
        return pairs([
            [PAGE_SLUG, slug],
            ["populate[components][on][information.info][populate][info][filters][heading]", categoryType],
            ["locale", locale]
        ]);
    }
    if slug == "home" && categoryType == "hero-banner" {
        return pairs([
            [PAGE_SLUG, slug],
            ["populate[components][on][shared.hero-banner][populate][hero_banner][populate]", "*"],
            ["locale", locale]
        ]);
    }
    if slug == "home" && categoryType == "feature-section" {
        string tab = "populate[components][on][shared.feature-section][populate][tab_items][populate][tab_item][populate][media][populate]";
        return pairs([[PAGE_SLUG, slug], ["locale", locale], [tab + "[cta]", "*"], [tab + "[image]", "true"]]);
    }
    if inCategories && categoryType is string {
        string part = "populate[components][on][shared." + slug + "][populate][" + slug + "_categories]";
        return pairs([
            [PAGE_SLUG, slug],
            [part + "[filters][category_title][$eq]", categoryType],
            [part + "[populate][" + slug + "_items]", "*"],
            ["locale", locale]
        ]);
    }
    if inCategories {
        return pairs([
            [PAGE_SLUG, slug],
            ["populate[components][on][shared." + slug + "][populate]", slug + "_categories"],
            ["locale", locale]
        ]);
    }
    if slug != "" {
        return filtered(PAGE_SLUG, slug, locale);
    }
    return "";
}

isolated function everything(string locale) returns string => pairs([["populate", "*"], ["locale", locale]]);

isolated function filtered(string filter, string value, string locale) returns string =>
    pairs([[filter, value], ["populate", "*"], ["locale", locale]]);

isolated function byName(string cat, string locale) returns string =>
    cat != "" ? filtered("filters[page_name][$eq]", cat, locale) : everything(locale);

isolated function bySlug(string cat, string locale) returns string =>
    cat != "" ? filtered(PAGE_SLUG, cat, locale) : everything(locale);

// name=value pairs joined with "&", names and values percent-encoded (what the old HTTP request
// did with its query-parameter map).
isolated function pairs([string, string][] items) returns string {
    string[] parts = [];
    foreach [string, string] [name, value] in items {
        parts.push(encodeComponent(name) + "=" + encodeComponent(value));
    }
    return string:'join("&", ...parts);
}

// "[0]", "[12]" ... removed, as the old flow did with  replace /\[\d+\]/ with "".
isolated function withoutIndexes(string rawQuery) returns string => re `\[\d+\]`.replaceAll(rawQuery, "");

const UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
// Characters DataWeave's encodeURI leaves as they are.
const URI_KEPT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.*!'()~;,/?:@&=+$#";

# DataWeave's `encodeURI`: every byte outside its kept set becomes %XX, "%" included.
#
# + text - the text to encode
# + keepPercent - true leaves "%" alone, for a query that is sent on as the caller wrote it
# + return - the encoded text
public isolated function encodeUri(string text, boolean keepPercent = false) returns string =>
    encodeWith(text, keepPercent ? URI_KEPT + "%" : URI_KEPT);

isolated function encodeComponent(string text) returns string => encodeWith(text, UNRESERVED);

isolated function encodeWith(string text, string kept) returns string {
    string[] out = [];
    foreach byte b in text.toBytes() {
        string|error ch = b < 128 ? string:fromCodePointInt(b) : error("not ascii");
        if ch is string && kept.includes(ch) {
            out.push(ch);
        } else {
            string hex = int:toHexString(b).toUpperAscii();
            out.push("%" + (hex.length() == 1 ? "0" + hex : hex));
        }
    }
    return string:'join("", ...out);
}

# The first value of each query parameter, decoded, as the old application read them
# (`attributes.queryParams.<name>`). A value with commas stays one value.
#
# + rawQuery - the query string as the caller sent it
# + return - parameter name -> first value
public isolated function firstParams(string rawQuery) returns map<string> {
    map<string> params = {};
    foreach string part in re `&`.split(rawQuery) {
        if part == "" {
            continue;
        }
        int? eq = part.indexOf("=");
        string name = decoded(eq is int ? part.substring(0, eq) : part);
        if !params.hasKey(name) {
            params[name] = eq is int ? decoded(part.substring(eq + 1)) : "";
        }
    }
    return params;
}

isolated function decoded(string text) returns string {
    string spaced = re `\+`.replaceAll(text, " ");
    // a broken escape such as "%ZZ" makes the decoder panic; such a value is kept as written
    string|error plain = trap url:decode(spaced, "UTF-8");
    return plain is string ? plain : spaced;
}
