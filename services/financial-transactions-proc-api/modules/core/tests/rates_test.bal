import ballerina/test;

@test:Config {}
function ratesParametersAreReadAndChecked() {
    RatesParams params = ratesParamsOf({"date": ["2026-01-05"], "to_currency": ["usd"], "fromCurrency": ["sar"]});
    test:assertEquals(params.toCurrency, "usd");
    test:assertEquals(params.fromCurrency, "sar");
    test:assertTrue(checkRatesParams(params) is ());
    test:assertTrue(checkRatesParams({date: "2026-01-05' OR 1=1"}) is error);
    test:assertTrue(checkRatesParams({fromDate: "05/01/2026", toDate: "2026-01-06"}) is error);
    test:assertTrue(checkRatesParams({toCurrency: "US'"}) is error);
    test:assertTrue(checkRatesParams({}) is ());
}

@test:Config {}
function ratesQueryFollowsTheMuleSql() {
    string cols = "id, from_currency, to_currency, rate, currency_date, op_type, op_ts, created_at, updated_at";
    test:assertEquals(ratesQueryOf({}).get("query"), "SELECT DISTINCT ON (to_currency) " + cols
            + " FROM cs_mule_framework.cs_fx_rates WHERE currency_date = (SELECT MAX(currency_date) FROM"
            + " cs_mule_framework.cs_fx_rates WHERE currency_date <= CURRENT_DATE) ORDER BY to_currency,"
            + " CASE WHEN op_type = 'U' THEN 1 ELSE 2 END, op_ts DESC");
    test:assertEquals(ratesQueryOf({date: "2026-01-05", toCurrency: "usd"}).get("query"), "SELECT DISTINCT ON (to_currency) "
            + cols + " FROM cs_mule_framework.cs_fx_rates WHERE currency_date = DATE '2026-01-05' AND to_currency = 'USD'"
            + " ORDER BY to_currency, CASE WHEN op_type = 'U' THEN 1 ELSE 2 END, op_ts DESC");
    test:assertEquals(ratesQueryOf({fromDate: "2026-01-01", toDate: "2026-01-31", fromCurrency: "sar"}).get("query"),
            "SELECT " + cols + " FROM cs_mule_framework.cs_fx_rates WHERE currency_date BETWEEN DATE '2026-01-01' AND DATE"
            + " '2026-01-31' AND from_currency = 'SAR' ORDER BY currency_date, to_currency, CASE WHEN op_type = 'U' THEN 1"
            + " ELSE 2 END, op_ts DESC");
    test:assertEquals(ratesQueryOf({distinctCurrencies: "true"}).get("query"),
            "SELECT DISTINCT to_currency FROM cs_mule_framework.cs_fx_rates ORDER BY to_currency");
    test:assertEquals(ratesQueryOf({}).get("connectionKey"), "PG_Guest");
    test:assertEquals(ratesQueryOf({}).get("operation"), "select");
}

@test:Config {}
function ratesAnswerFollowsTheMuleShape() {
    json row = {"id": 7, "from_currency": "SAR", "to_currency": "USD", "rate": 0.2666, "currency_date": "2026-01-05",
        "op_type": "U", "op_ts": "2026-01-05T01:00:00Z", "created_at": "x", "updated_at": "y"};
    test:assertEquals(ratesResponseOf({"data": [row]}, {}), {"status": "success", "count": 1, "data": [
        {"id": 7, "fromCurrency": "SAR", "toCurrency": "USD", "rate": 0.2666, "currencyDate": "2026-01-05", "opType": "U",
            "opTs": "2026-01-05T01:00:00Z"}]});
    test:assertEquals(ratesResponseOf([], {date: "2026-01-05", toCurrency: "usd"}),
            {"status": "success", "message": "No currency rates found for date 2026-01-05 for currency USD", "data": []});
    test:assertEquals(ratesResponseOf([], {fromDate: "2026-01-01", toDate: "2026-01-31"}),
            {"status": "success", "message": "No currency rates found between 2026-01-01 and 2026-01-31", "data": []});
    test:assertEquals(ratesResponseOf([], {}),
            {"status": "success", "message": "No currency rates found for the requested period", "data": []});
    test:assertEquals(ratesResponseOf([{"to_currency": "usd"}, {"to_currency": " "}, {"to_currency": "EUR"}],
            {distinctCurrencies: "true"}).toJsonString().includes("USD"), true);
}

@test:Config {}
function helpersBehave() {
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress(""));
    test:assertFalse(isPlaceholderAddress("http://telr-pay-gw-sys-api.wso2.svc"));
    test:assertEquals(withQuery("/x/v1/integration-tasks", {"operationName": ["getFolio"]}), "/x/v1/integration-tasks?operationName=getFolio");
    test:assertEquals(withQuery("/x?operationName=getArticles", {"q": ["a b&c"]}), "/x?operationName=getArticles&q=a%20b%26c");
    test:assertEquals(gqlText("a\"b\\c\nd"), "a\\\"b\\\\c\\nd");
    test:assertEquals(decimalOf("12.50"), 12.5d);
    test:assertEquals(decimalOf(3), 3d);
    test:assertEquals(decimalOf("x"), ());
    test:assertEquals(sessionDocumentOf({"session": {"order": {"cartid": "c"}}}), {"order": {"cartid": "c"}});
}
