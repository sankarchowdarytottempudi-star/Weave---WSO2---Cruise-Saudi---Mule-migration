// The Kafka starting point of the old application, "currency-rateFlow": what is done with one
// message of the currency-rate topic. Pure functions only; the listener is in ratefeed.bal of the
// service.
//
// A message is a JSON list. Each item may carry `errorMessage`, a list of change events of the
// source database. The events of table CURRENCY_EXCHANGE that carry an `after` image become rows
// of cs_mule_framework.cs_fx_rates, the table GET /currency-rates reads (rates.bal).

const string FX_UPSERT_HEAD = "INSERT INTO " + FX_TABLE
    + " (id, from_currency, to_currency, rate, currency_date, op_type, op_ts) VALUES ";
const string FX_UPSERT_TAIL = " ON CONFLICT (id) DO UPDATE SET rate = EXCLUDED.rate, op_type = EXCLUDED.op_type,"
    + " op_ts = EXCLUDED.op_ts, updated_at = now()";

# Settings of the currency-rate listener.
#
# + enabled - The listener runs only when this is true. Leave it false while the old application
# still consumes the topic
# + bootstrapServers - Broker addresses, `host:port`, comma separated (Mule `kafkaConsume.bootstrapServers`)
# + groupId - Consumer group (Mule `kafkaConsume.groupId`)
# + topic - Topic (Mule `kafkaConsume.topic`)
# + autoOffsetReset - Where a group without a stored position starts: latest, earliest or none
# (Mule `kafkaConsume.autoOffsetReset`)
# + maxRetries - How often a failed database call is repeated (Mule `UntilSuccess.maxRetries`)
# + millisBetweenRetries - Pause between two tries, in milliseconds (Mule `UntilSuccess.millisBetweenRetries`)
# + alertTo - Receiver of the alert e-mail for a skipped message (Mule `email.toAddress`)
# + alertCc - Copy receiver of the alert e-mail (Mule `email.ccAddress`)
public type RateListenerSettings record {|
    boolean enabled = false;
    string bootstrapServers = "";
    string groupId = "";
    string topic = "";
    string autoOffsetReset = "latest";
    int maxRetries = 3;
    int millisBetweenRetries = 300000;
    string alertTo = "";
    string alertCc = "";
|};

# One currency event of a message (the fields Mule reads from it).
#
# + id - `after.ID`
# + fromCurrency - `after.CURRENCY_CD`
# + toCurrency - `after.CURRENCY_TO`
# + rate - `after.CURRENCY_RTE`
# + currencyDate - `after.CURRENCY_DT`
# + opType - `op_type`
# + opTs - `op_ts`
public type RateEvent record {|
    json id;
    json fromCurrency;
    json toCurrency;
    json rate;
    json currencyDate;
    json opType;
    json opTs;
|};

# What is reported when a message could not be stored (Mule's error payload of the database step).
#
# + messageType - Kind of failure
# + message - What happened
# + responseCode - Status the failure stands for
# + responsePayload - The cause
public type RateFailure record {|
    string messageType;
    string message;
    string responseCode;
    string responsePayload;
|};

# The name of the first listener setting without a usable value.
#
# + settings - The listener's settings
# + return - The setting's name, or `()` when the listener can be started
public isolated function listenerGapOf(RateListenerSettings settings) returns string? {
    if settings.bootstrapServers.trim() == "" {
        return "bootstrapServers";
    }
    if settings.groupId.trim() == "" {
        return "groupId";
    }
    if settings.topic.trim() == "" {
        return "topic";
    }
    if offsetResetOf(settings.autoOffsetReset) == "" {
        return "autoOffsetReset";
    }
    return ();
}

# The offset-reset word in the form the Kafka client takes ("LATEST" in the old settings).
#
# + word - The configured value
# + return - latest, earliest or none; "" when it is none of these
public isolated function offsetResetOf(string word) returns string {
    string lower = word.trim().toLowerAscii();
    return lower == "latest" || lower == "earliest" || lower == "none" ? lower : "";
}

# How often the database call is made for one message: the first try plus the retries.
#
# + settings - The listener's settings
# + return - Number of tries, at least 1
public isolated function attemptsOf(RateListenerSettings settings) returns int =>
    settings.maxRetries > 0 ? settings.maxRetries + 1 : 1;

# The pause between two tries.
#
# + settings - The listener's settings
# + return - Seconds
public isolated function retryPauseOf(RateListenerSettings settings) returns decimal =>
    settings.millisBetweenRetries > 0 ? <decimal>settings.millisBetweenRetries / 1000 : 0;

# The currency events of one message (Mule transform "Extract CURRENCY_EXCHANGE events").
#
# + text - The message's value as text
# + return - The events, an empty list when the message holds none, or an error when the message
# is not a JSON list
public isolated function rateEventsOf(string text) returns RateEvent[]|error {
    // numbers are read as decimals so that a rate keeps every digit it was sent with
    json|error decoded = text.fromJsonDecimalString();
    if decoded is error {
        return error("the message is not JSON");
    }
    if decoded is () {
        return [];
    }
    if decoded is json[] {
        json[] entries = [];
        foreach json item in decoded {
            json part = item is map<json> ? item["errorMessage"] : ();
            if part is json[] {
                foreach json entry in part {
                    entries.push(entry);
                }
            } else if part !is () {
                entries.push(part);
            }
        }
        RateEvent[] events = [];
        foreach json entry in entries {
            if entry is map<json> && entry["table"] == "CURRENCY_EXCHANGE" && entry["after"] != () {
                json after = entry["after"];
                events.push({
                    id: fieldOf(after, "ID"),
                    fromCurrency: fieldOf(after, "CURRENCY_CD"),
                    toCurrency: fieldOf(after, "CURRENCY_TO"),
                    rate: fieldOf(after, "CURRENCY_RTE"),
                    currencyDate: fieldOf(after, "CURRENCY_DT"),
                    opType: entry["op_type"],
                    opTs: entry["op_ts"]
                });
            }
        }
        return events;
    }
    return error("the message is not a JSON list");
}

# The request that stores the events through the DB system API (Mule transform "Build DB Upsert
# Request"): one statement for all events of the message, an existing id is updated.
#
# Unlike Mule, a quote inside a value is doubled and the rate must be a number, so a value cannot
# change the statement.
#
# + events - The events of one message, at least one
# + return - The DB system API request, or an error when an event has no id or no usable rate
public isolated function rateUpsertOf(RateEvent[] events) returns map<json>|error {
    string[] rows = [];
    foreach RateEvent event in events {
        if event.id is () {
            return error("a currency event has no ID");
        }
        if event.rate is () {
            return error("a currency event has no rate");
        }
        string rate = textOf(event.rate).trim();
        if !re `[-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?`.isFullMatch(rate) {
            return error("a currency event has a rate that is not a number");
        }
        rows.push("('" + fxText(event.id, "") + "','" + fxText(event.fromCurrency, "USD") + "','"
            + fxText(event.toCurrency, "") + "'," + rate + ",'" + fxText(event.currencyDate, "") + "','"
            + fxText(event.opType, "I") + "','" + fxText(event.opTs, "") + "')");
    }
    return {
        "connectionKey": "PG_Guest",
        "operation": "insert",
        "query": FX_UPSERT_HEAD + string:'join(",", ...rows) + FX_UPSERT_TAIL
    };
}

// A value as it is placed between quotes in the statement; `fallback` when the event has none.
isolated function fxText(json value, string fallback) returns string {
    string text = value is () ? fallback : textOf(value);
    return re `'`.replaceAll(text, "''");
}

# What is reported when the database call failed on every try (Mule "Build 503 Error Payload").
#
# + rootCause - The last failure
# + return - The failure
public isolated function retryExhaustedOf(string rootCause) returns RateFailure => {
    messageType: "RETRY_EXHAUSTED",
    message: "Database call failed after all retries",
    responseCode: "503",
    responsePayload: rootCause
};

# The alert e-mail sent when a message is skipped (Mule sub-flow
# "financial-transactions-proc-exceptionSub_Flow"), in the form the e-mail system API takes.
#
# + errorType - Kind of failure
# + description - What happened
# + details - More about it, "N/A" when there is nothing
# + to - Receiver
# + cc - Copy receiver, "" for none
# + return - The e-mail system API request
public isolated function alertEmailOf(string errorType, string description, string details, string to, string cc)
        returns map<json> {
    boolean high = errorType == "BAD_GATEWAY" || errorType == "INTERNAL_SERVER_ERROR"
        || errorType == "SERVICE_UNAVAILABLE" || errorType == "CONNECTIVITY";
    string apiName = "financial-transactions-proc-api";
    json[] copies = cc.trim() == "" ? [] : [{"emailAddress": {"address": cc.trim()}}];
    return {
        "message": {
            "subject": high ? "⚠️ " + apiName : apiName,
            "importance": high ? "High" : "Low",
            "body": {
                "contentType": "HTML",
                "content": "<b>Error type :</b> " + errorType + "<br/><b>Description :</b> " + description
                    + "<br/><b>Details :</b> " + details
                    + "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information,"
                    + " please refer to the MuleSoft application logs or contact the support team.</span>"
            },
            "toRecipients": [{"emailAddress": {"address": to.trim()}}],
            "ccRecipients": copies
        }
    };
}
