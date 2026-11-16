import ballerina/test;

const string FX_HEAD = "INSERT INTO cs_mule_framework.cs_fx_rates (id, from_currency, to_currency, rate, currency_date,"
    + " op_type, op_ts) VALUES ";
const string FX_TAIL = " ON CONFLICT (id) DO UPDATE SET rate = EXCLUDED.rate, op_type = EXCLUDED.op_type,"
    + " op_ts = EXCLUDED.op_ts, updated_at = now()";

function sampleMessage() returns string => [
    {
        "errorMessage": [
            {
                "table": "CURRENCY_EXCHANGE",
                "op_type": "U",
                "op_ts": "2026-01-05 10:00:00.000000",
                "after": {"ID": 101, "CURRENCY_CD": "USD", "CURRENCY_TO": "SAR", "CURRENCY_RTE": 3.7512345678, "CURRENCY_DT": "2026-01-05"}
            },
            {"table": "GUEST", "op_type": "I", "after": {"ID": 5}},
            {"table": "CURRENCY_EXCHANGE", "op_type": "D", "before": {"ID": 99}}
        ]
    },
    {"somethingElse": true},
    {
        "errorMessage": [
            {"table": "CURRENCY_EXCHANGE", "after": {"ID": "102", "CURRENCY_TO": "EUR", "CURRENCY_RTE": "0.92", "CURRENCY_DT": "2026-01-05"}}
        ]
    }
].toJsonString();

@test:Config {}
function onlyCurrencyEventsWithAnAfterImageAreTaken() returns error? {
    RateEvent[] events = check rateEventsOf(sampleMessage());
    test:assertEquals(events.length(), 2);
    test:assertEquals(events[0].id, 101d);
    test:assertEquals(events[0].fromCurrency, "USD");
    test:assertEquals(events[0].toCurrency, "SAR");
    test:assertEquals(events[0].opType, "U");
    test:assertEquals(events[0].opTs, "2026-01-05 10:00:00.000000");
    test:assertEquals(events[1].id, "102");
    test:assertEquals(events[1].fromCurrency, ());
    test:assertEquals(events[1].opType, ());
}

@test:Config {}
function aMessageWithoutCurrencyEventsGivesNothingToStore() returns error? {
    test:assertEquals((check rateEventsOf("[]")).length(), 0);
    test:assertEquals((check rateEventsOf("null")).length(), 0);
    test:assertEquals((check rateEventsOf("[{\"id\": 1}, {\"errorMessage\": []}]")).length(), 0);
    test:assertEquals((check rateEventsOf("[{\"errorMessage\": [\"text\", 5, {\"table\": \"OTHER\", \"after\": {}}]}]")).length(), 0);
}

@test:Config {}
function aSingleEventInsteadOfAListIsTakenAsOneEvent() returns error? {
    RateEvent[] events = check rateEventsOf("[{\"errorMessage\": {\"table\": \"CURRENCY_EXCHANGE\", \"op_type\": \"I\","
            + " \"after\": {\"ID\": 7, \"CURRENCY_RTE\": 1.5}}}]");
    test:assertEquals(events.length(), 1);
    test:assertEquals(events[0].id, 7d);
}

@test:Config {}
function aMessageThatIsNotAJsonListIsRefused() {
    RateEvent[]|error notJson = rateEventsOf("this is not json {");
    test:assertTrue(notJson is error);
    RateEvent[]|error anObject = rateEventsOf("{\"errorMessage\": []}");
    test:assertTrue(anObject is error);
    RateEvent[]|error empty = rateEventsOf("");
    test:assertTrue(empty is error);
    if notJson is error {
        // the reason never repeats the message itself
        test:assertEquals(notJson.message(), "the message is not JSON");
    }
}

@test:Config {}
function theUpsertFollowsTheMuleStatement() returns error? {
    map<json> request = check rateUpsertOf(check rateEventsOf(sampleMessage()));
    test:assertEquals(request.get("connectionKey"), "PG_Guest");
    test:assertEquals(request.get("operation"), "insert");
    test:assertEquals(request.get("query"), FX_HEAD
            + "('101','USD','SAR',3.7512345678,'2026-01-05','U','2026-01-05 10:00:00.000000'),"
            + "('102','USD','EUR',0.92,'2026-01-05','I','')" + FX_TAIL);
    test:assertEquals(request.keys().length(), 3);
}

@test:Config {}
function aRateKeepsEveryDigit() returns error? {
    RateEvent[] events = check rateEventsOf("[{\"errorMessage\": [{\"table\": \"CURRENCY_EXCHANGE\", \"after\":"
            + " {\"ID\": 1, \"CURRENCY_RTE\": 0.26659557451346309}}]}]");
    string query = (check rateUpsertOf(events)).get("query").toString();
    test:assertTrue(query.includes(",0.26659557451346309,"), query);
}

@test:Config {}
function anEventWithoutIdOrUsableRateStopsTheMessage() returns error? {
    RateEvent good = {id: 1d, fromCurrency: "USD", toCurrency: "SAR", rate: 3.75d, currencyDate: "2026-01-05", opType: "I", opTs: "t"};
    test:assertTrue(rateUpsertOf([good]) is map<json>);
    RateEvent noId = good.clone();
    noId.id = ();
    test:assertTrue(rateUpsertOf([good, noId]) is error);
    RateEvent noRate = good.clone();
    noRate.rate = ();
    test:assertTrue(rateUpsertOf([noRate]) is error);
    RateEvent badRate = good.clone();
    badRate.rate = "1); DROP TABLE x; --";
    test:assertTrue(rateUpsertOf([badRate]) is error);
}

@test:Config {}
function aQuoteInAValueCannotChangeTheStatement() returns error? {
    RateEvent event = {id: "5", fromCurrency: "US'D", toCurrency: "x'); DELETE FROM t; --", rate: "1.25", currencyDate: (), opType: (), opTs: ()};
    string query = (check rateUpsertOf([event])).get("query").toString();
    test:assertEquals(query, FX_HEAD + "('5','US''D','x''); DELETE FROM t; --',1.25,'','I','')" + FX_TAIL);
}

@test:Config {}
function theFailureAfterAllRetriesIsReportedAsInMule() {
    RateFailure failure = retryExhaustedOf("database system API answered 500");
    test:assertEquals(failure, {
        messageType: "RETRY_EXHAUSTED",
        message: "Database call failed after all retries",
        responseCode: "503",
        responsePayload: "database system API answered 500"
    });
}

@test:Config {}
function theAlertEmailHasTheMuleShape() {
    map<json> low = alertEmailOf("RETRY_EXHAUSTED", "Database call failed after all retries", "N/A", " ops@example.test ", "copy@example.test");
    json message = low.get("message");
    test:assertEquals(fieldOf(message, "subject"), "financial-transactions-proc-api");
    test:assertEquals(fieldOf(message, "importance"), "Low");
    test:assertEquals(fieldOf(message, "body", "contentType"), "HTML");
    string content = textOf(fieldOf(message, "body", "content"));
    test:assertTrue(content.startsWith("<b>Error type :</b> RETRY_EXHAUSTED<br/><b>Description :</b> Database call failed after all"
            + " retries<br/><b>Details :</b> N/A<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b>"), content);
    test:assertEquals(fieldOf(message, "toRecipients"), [{"emailAddress": {"address": "ops@example.test"}}]);
    test:assertEquals(fieldOf(message, "ccRecipients"), [{"emailAddress": {"address": "copy@example.test"}}]);

    map<json> high = alertEmailOf("CONNECTIVITY", "d", "N/A", "ops@example.test", "");
    test:assertEquals(fieldOf(high.get("message"), "subject"), "⚠️ financial-transactions-proc-api");
    test:assertEquals(fieldOf(high.get("message"), "importance"), "High");
    test:assertEquals(fieldOf(high.get("message"), "ccRecipients"), []);
}

@test:Config {}
function theListenerIsOffUntilItIsSwitchedOnAndFullySet() {
    RateListenerSettings defaults = {};
    test:assertFalse(defaults.enabled);
    test:assertEquals(listenerGapOf(defaults), "bootstrapServers");
    test:assertEquals(listenerGapOf({bootstrapServers: "broker:9092"}), "groupId");
    test:assertEquals(listenerGapOf({bootstrapServers: "broker:9092", groupId: "g"}), "topic");
    test:assertEquals(listenerGapOf({bootstrapServers: "broker:9092", groupId: "g", topic: "t", autoOffsetReset: "sometimes"}),
            "autoOffsetReset");
    test:assertEquals(listenerGapOf({bootstrapServers: "broker:9092", groupId: "g", topic: "t", autoOffsetReset: "LATEST"}), ());
    test:assertEquals(offsetResetOf("LATEST"), "latest");
    test:assertEquals(offsetResetOf(" Earliest "), "earliest");
    test:assertEquals(offsetResetOf("none"), "none");
}

@test:Config {}
function theDatabaseCallIsRepeatedAsOftenAsInMule() {
    test:assertEquals(attemptsOf({}), 4);
    test:assertEquals(retryPauseOf({}), 300d);
    test:assertEquals(attemptsOf({maxRetries: 0}), 1);
    test:assertEquals(attemptsOf({maxRetries: -2}), 1);
    test:assertEquals(retryPauseOf({millisBetweenRetries: 1500}), 1.5d);
    test:assertEquals(retryPauseOf({millisBetweenRetries: 0}), 0d);
}
