import ballerina/test;

function target(string slug, string? cat = (), string path = "", string rawQuery = "", map<string> params = {})
        returns Target => contentTarget(slug, cat, path == "" ? "/cms-proc-api/v1/cms/content/" + slug : path, rawQuery, params);

const ALL_EN = "populate=%2A&locale=en";
const SLUG_EQ = "filters%5Bpage_slug%5D%5B%24eq%5D=";

@test:Config {}
function everyListedSlugHasItsHandler() {
    test:assertEquals(handlerOf("header"), "header");
    test:assertEquals(handlerOf("add-ons"), "addons");
    test:assertEquals(handlerOf("offer2"), "offers");
    test:assertEquals(handlerOf("errors"), "docs");
    test:assertEquals(handlerOf("onboarding"), "mobile-page-pre-cruises");
    test:assertEquals(handlerOf("explore-banner-mobile"), "mobile-page-cruises");
    test:assertEquals(handlerOf("packages-policy"), "mobile-page-generals");
    test:assertEquals(handlerOf("home"), "pages");
    test:assertEquals(handlerOf(""), "pages");
    // every handler asks only for path settings that exist
    foreach string slug in SLUG_HANDLERS.keys() {
        test:assertTrue(PATH_KEYS.indexOf(target(slug).pathKey) is int, slug);
        test:assertTrue(PATH_KEYS.indexOf(target(slug, "x").pathKey) is int, slug);
    }
}

@test:Config {}
function headerAndTheOtherPlainCollections() {
    test:assertEquals(target("header"), {pathKey: "header", query: ALL_EN});
    test:assertEquals(target("footer", params = {"locale": "ar"}), {pathKey: "footer", query: "populate=%2A&locale=ar"});
    test:assertEquals(target("onboard-excursion").pathKey, "onboardExcursion");
    test:assertEquals(target("spas").pathKey, "spas");
    test:assertEquals(target("dinings").pathKey, "dinings");
    test:assertEquals(target("configurations"), {pathKey: "configurations", query: ALL_EN});
}

@test:Config {}
function cabinsAndPackages() {
    test:assertEquals(target("cabin"), {pathKey: "cabin-categories", query: ALL_EN});
    test:assertEquals(target("cabin", "IS"), {pathKey: "cabin-categories",
        query: "filters%5Bcabin_types%5D%5Bcabin_type_detail%5D%5Bcode%5D=IS&" + ALL_EN});
    test:assertEquals(target("packages"), {pathKey: "packages", query: ALL_EN});
    test:assertEquals(target("packages", "PK1", params = {"destination": "red-sea"}).query,
        "filters%5Bpkg_code%5D%5B%24eq%5D=PK1&" + ALL_EN);
    test:assertEquals(target("packages", params = {"destination": "red-sea", "duration": "7"}).query,
        "filters%5Bdestination%5D%5Bpage_slug%5D%5B%24eq%5D=red-sea&" + ALL_EN);
    test:assertEquals(target("packages", params = {"duration": "7"}).query,
        "filters%5Bduration%5D%5B%24eq%5D=7&" + ALL_EN);
}

@test:Config {}
function itinerariesPassTheCallersQueryOn() {
    test:assertEquals(target("itineraries"), {pathKey: "itineraries", query: "populate=*&locale=en"});
    test:assertEquals(target("itineraries", "jeddah").query, "filters%5Bpage_slug%5D%5B$eq%5D=jeddah&populate=*&locale=en");
    // the caller's query wins over the category, list indexes are dropped, populate is added once
    test:assertEquals(target("itineraries", "jeddah", rawQuery = "filters[code][$in][0]=A&filters[code][$in][1]=B",
            params = {}).query, "filters%5Bcode%5D%5B$in%5D=A&filters%5Bcode%5D%5B$in%5D=B&populate=*");
    test:assertEquals(target("itineraries", rawQuery = "locale=ar&populate=deep").query, "locale=ar&populate=deep");
    // The query reaches the service percent-encoded when it comes through the WSO2 gateway (the old
    // flow saw it raw), so it is decoded once and then encoded as the old flow's encodeURI did: an
    // encoded space stays one encoded space instead of becoming %2520.
    test:assertEquals(target("itineraries", rawQuery = "name=a%20b").query, "name=a%20b&populate=*");
}

@test:Config {}
function excursionsAndAddOns() {
    test:assertEquals(target("excursions"), {pathKey: "excursions", query: "populate=*&locale=en"});
    test:assertEquals(target("excursions", params = {"shorex_code": "A1,B2", "locale": "ar"}).query,
        "shorex_code=A1,B2&populate=*&locale=ar");
    test:assertEquals(target("add-ons"), {pathKey: "add-ons", query: "populate=*&locale=en"});
    test:assertEquals(target("add-ons", "spa-pass", rawQuery = "locale=en", params = {"locale": "en"}).query,
        "filters%5Bpage_slug%5D%5B$eq%5D=spa-pass&populate=*&locale=en");
    test:assertEquals(target("add-ons", rawQuery = "filters%5Btype%5D=x&a=b c").query,
        "filters%5Btype%5D=x&a=b%20c&populate=*");
}

@test:Config {}
function destinationsPortsAndActivities() {
    string byPageName = "filters%5Bpage_name%5D%5B%24eq%5D=";
    test:assertEquals(target("destinations", "Jeddah"), {pathKey: "destinations", query: byPageName + "Jeddah&" + ALL_EN});
    test:assertEquals(target("port-details", "Jeddah").query, byPageName + "Jeddah&" + ALL_EN);
    test:assertEquals(target("destination-activities").query, ALL_EN);
    test:assertEquals(target("destination-experiences", "diving").query, SLUG_EQ + "diving&" + ALL_EN);
    test:assertEquals(target("embarkations", "jeddah"), {pathKey: "embarkations", query: SLUG_EQ + "jeddah&" + ALL_EN});
}

@test:Config {}
function offersDocsAndMobilePages() {
    test:assertEquals(target("offers"), {pathKey: "offers", query: ALL_EN});
    test:assertEquals(target("offer1"), {pathKey: "offers", query: SLUG_EQ + "offer1&" + ALL_EN});
    test:assertEquals(target("privacy-policy"), {pathKey: "docs", query: SLUG_EQ + "privacy-policy&" + ALL_EN});
    test:assertEquals(target("spa-policy"), {pathKey: "mobile-page-generals", query: SLUG_EQ + "spa-policy&" + ALL_EN});
    test:assertEquals(target("safety"), {pathKey: "mobile-page-cruises", query: SLUG_EQ + "safety&" + ALL_EN});
    test:assertEquals(target("onboarding"), {pathKey: "mobile-page-pre-cruises", query: SLUG_EQ + "onboarding&" + ALL_EN});
    test:assertEquals(target("travel-trade-partners"), {pathKey: "travelTradePartners", query: ALL_EN});
    test:assertEquals(target("travel-trade-partners", "uae"), {pathKey: "travelPartnersLists", query: SLUG_EQ + "uae&" + ALL_EN});
}

@test:Config {}
function pages() {
    test:assertEquals(target(""), {pathKey: "pages", query: ""});
    test:assertEquals(target("home"), {pathKey: "pages", query: SLUG_EQ + "home&" + ALL_EN});
    test:assertEquals(target("faq", path = "/cms-proc-api/v1/cms/content/faq/categories").query,
        SLUG_EQ + "faq&populate%5Bcomponents%5D%5Bon%5D%5Bshared.faq%5D%5Bpopulate%5D=faq_categories&locale=en");
    test:assertEquals(target("faq", "Booking", "/cms-proc-api/v1/cms/content/faq/categories/Booking").query,
        SLUG_EQ + "faq&populate%5Bcomponents%5D%5Bon%5D%5Bshared.faq%5D%5Bpopulate%5D%5Bfaq_categories%5D%5Bfilters%5D%5Bcategory_title%5D%5B%24eq%5D=Booking"
        + "&populate%5Bcomponents%5D%5Bon%5D%5Bshared.faq%5D%5Bpopulate%5D%5Bfaq_categories%5D%5Bpopulate%5D%5Bfaq_items%5D=%2A&locale=en");
    test:assertEquals(target("home", "hero-banner", "/x/cms/content/home/categories/hero-banner").query,
        SLUG_EQ + "home&populate%5Bcomponents%5D%5Bon%5D%5Bshared.hero-banner%5D%5Bpopulate%5D%5Bhero_banner%5D%5Bpopulate%5D=%2A&locale=en");
    string tab = "populate%5Bcomponents%5D%5Bon%5D%5Bshared.feature-section%5D%5Bpopulate%5D%5Btab_items%5D%5Bpopulate%5D%5Btab_item%5D%5Bpopulate%5D%5Bmedia%5D%5Bpopulate%5D";
    test:assertEquals(target("home", "feature-section", "/x/cms/content/home/categories/feature-section").query,
        SLUG_EQ + "home&locale=en&" + tab + "%5Bcta%5D=%2A&" + tab + "%5Bimage%5D=true");
    test:assertEquals(target("profile", "My details", "/x/cms/content/profile/categories/My details").query,
        SLUG_EQ + "profile&populate%5Bcomponents%5D%5Bon%5D%5Binformation.info%5D%5Bpopulate%5D%5Binfo%5D%5Bfilters%5D%5Bheading%5D=My%20details&locale=en");
}

@test:Config {}
function encodeUriWorksLikeTheOldOne() {
    test:assertEquals(encodeUri("a b[c]=$1&d=é%"), "a%20b%5Bc%5D=$1&d=%C3%A9%25");
    test:assertEquals(encodeUri("a b[c]=%20", true), "a%20b%5Bc%5D=%20");
    test:assertEquals(encodeUri("-_.*!'()~;,/?:@&=+$#"), "-_.*!'()~;,/?:@&=+$#");
}

@test:Config {}
function queryParametersAreReadAsTheOldApplicationReadThem() {
    test:assertEquals(firstParams(""), {});
    test:assertEquals(firstParams("shorex_code=A1,B2&locale=ar&locale=en"), {"shorex_code": "A1,B2", "locale": "ar"});
    test:assertEquals(firstParams("destination=red%20sea&x=a+b&flag&filters%5Ba%5D=1"),
        {"destination": "red sea", "x": "a b", "flag": "", "filters[a]": "1"});
    test:assertEquals(firstParams("bad=%ZZ"), {"bad": "%ZZ"});
}

// ---- pagination reaches Strapi whether the caller encodes the brackets or not (old flow read the query decoded)

@test:Config {}
function itinerariesPaginationEncodedAndRawGiveTheSameStrapiQuery() {
    string encoded = "pagination%5Bpage%5D=1&pagination%5BpageSize%5D=10&site=website&locale=en";
    string raw = "pagination[page]=1&pagination[pageSize]=10&site=website&locale=en";
    Target a = contentTarget("itineraries", (), "/cms/content/itineraries", encoded, firstParams(encoded));
    Target b = contentTarget("itineraries", (), "/cms/content/itineraries", raw, firstParams(raw));
    test:assertEquals(a.query, b.query);
    test:assertEquals(a.query, "pagination%5Bpage%5D=1&pagination%5BpageSize%5D=10&site=website&locale=en&populate=*");
    test:assertFalse(a.query.includes("%25"), "no double encoding");
}

@test:Config {}
function addonsQueryDecodedOnceToo() {
    string encoded = "filters%5Bcode%5D%5B%24eq%5D=SPA&locale=en";
    Target t = contentTarget("add-ons", (), "/cms/content/add-ons", encoded, firstParams(encoded));
    test:assertFalse(t.query.includes("%25"), "no double encoding");
}

@test:Config {}
function plainQueriesUnchanged() {
    string q = "site=website&locale=en";
    test:assertEquals(percentDecoded(q), q);
    Target t = contentTarget("itineraries", (), "/cms/content/itineraries", q, firstParams(q));
    test:assertEquals(t.query, "site=website&locale=en&populate=*");
    test:assertEquals(percentDecoded("a%ZZb%2"), "a%ZZb%2");
}
