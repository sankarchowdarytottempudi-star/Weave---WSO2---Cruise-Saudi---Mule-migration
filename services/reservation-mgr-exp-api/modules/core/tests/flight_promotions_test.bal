import ballerina/test;

const string FLIGHT_QUERY = "query flightpromotion { flightpromotion(params: { pkg: { key: \"AC01261006KUSIST-7\" } "
    + "category: { key: \"BC\" } guests: [{ seqN: 1 }, { seqN: 2 }] }) { promoKey } }";

@test:Config {}
function flightPromotionRequestIsReadLikeMule() {
    FlightPromotionRequest req = parseFlightPromotionRequest(FLIGHT_QUERY);
    test:assertEquals(req.pkgKey, "AC01261006KUSIST-7");
    test:assertEquals(req.cabinCategoryKey, ["BC"]);
    test:assertEquals(req.guests, [1, 2]);
}

@test:Config {}
function severalCategoriesAreSplitOnCommas() {
    FlightPromotionRequest req = parseFlightPromotionRequest("category: { key: \"AC01, BC\" }");
    test:assertEquals(req.cabinCategoryKey, ["AC01", "BC"]);
    test:assertEquals(req.pkgKey, "");
    test:assertEquals(req.guests, []);
}

@test:Config {}
function promotionsQueryDeclaresPackageCategoryAndGuests() returns error? {
    json body = availablePromotionsQuery(parseFlightPromotionRequest(FLIGHT_QUERY));
    string q = check body.query;
    test:assertTrue(q.includes("category: { key: \"BC\" }"));
    test:assertTrue(q.includes("pkg: { key: \"AC01261006KUSIST-7\" }"));
    test:assertTrue(q.includes("guests: [1,2]"));
}

@test:Config {}
function pricingQueryDeclaresAdultThenChildrenAndThePromotion() returns error? {
    json body = priceWithPromotionQuery(parseFlightPromotionRequest(FLIGHT_QUERY), "PROMO|1");
    string q = check body.query;
    test:assertTrue(q.includes("{ seqN: 1, ageCategoryId: \"AgeCategory|SHIP|ADULT\" }, { seqN: 2, ageCategoryId: \"AgeCategory|SHIP|CHILD\" }"));
    test:assertTrue(q.includes("promotions: [{ key: \"PROMO|1\" }]"));
    test:assertTrue(q.includes("sourceCode: \"INT-CON\""));
}

@test:Config {}
function promotionKeysAreRead() {
    json answer = {data: {availablePromotions: [{promotion: {key: "P1"}}, {promotion: {key: "P2"}}, {promotion: {}}]}};
    test:assertEquals(promotionKeysOf(answer), ["P1", "P2"]);
    test:assertEquals(promotionKeysOf({data: {}}), []);
}

@test:Config {}
function onlyTransferPromotionsOnTheRequestedCategoryRemain() {
    json transfer = {cabinCategory: {key: "BC"}, usedPromotions: [{promotion: {'type: "transfer"}}]};
    json discount = {cabinCategory: {key: "BC"}, usedPromotions: [{promotion: {'type: "DISCOUNT"}}]};
    json otherCabin = {cabinCategory: {key: "AC01"}, usedPromotions: [{promotion: {'type: "TRANSFER"}}]};
    [string, json][] priced = [
        ["P1", {data: {availableVoyages: [{pkg: {key: "K"}, availableCategories: [transfer, discount, otherCabin]}]}}],
        ["P2", {data: {availableVoyages: [{pkg: {key: "K"}, availableCategories: [discount]}]}}]
    ];
    json[] result = transferPromotionsOf(priced, parseFlightPromotionRequest(FLIGHT_QUERY));
    test:assertEquals(result, [{promoKey: "P1", availableVoyages: [{pkg: {key: "K"}, availableCategories: [transfer]}]}]);
}
