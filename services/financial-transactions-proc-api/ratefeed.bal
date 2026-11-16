import financial_transactions_proc_api.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;

import aroya/integration_commons as commons;

// source-entry: currency-rateFlow
//
// The Kafka starting point of the old application (Mule flow "currency-rateFlow"). It fills the
// table GET /currency-rates reads.
//
// For every message of the topic:
//   1. the position is committed on receipt, before the message is worked on (Mule
//      ackMode="IMMEDIATE"): a message is handled at most once and is never delivered again;
//   2. the currency events are taken out of it (core:rateEventsOf);
//   3. no events: nothing is stored;
//   4. otherwise one upsert goes to the DB system API (core:rateUpsertOf); a failed call is
//      repeated currencyRateListener.maxRetries times with a pause of millisBetweenRetries;
//   5. a message that cannot be read, or cannot be stored after all tries, is skipped: an error is
//      logged, an alert e-mail is sent in the background, and the next message is taken.
//
// The listener runs only when currencyRateListener.enabled = true. While the old application
// still consumes the topic it must stay off: with the same group the two would share the
// messages, with another group every message would be stored twice.
//
// Nothing of a message is written to the log: only sizes, counts and the correlation id.

// E-mail system API for the alert. Source: HTTP_Request_configuration
final http:Client emailSysClient = check commons:newDownstreamClient(hTTPRequestConfiguration);

# Starts the listener when it is switched on and fully set. A listener that cannot be started is
# reported in the log; the HTTP operations work in every case.
function startCurrencyRateListener() {
    core:RateListenerSettings settings = currencyRateListener;
    if !settings.enabled {
        log:printInfo("Currency-rate listener is off (currencyRateListener.enabled = false)");
        return;
    }
    string? gap = core:listenerGapOf(settings);
    if gap is string {
        log:printError("Currency-rate listener not started: a setting has no usable value",
                setting = "currencyRateListener." + gap);
        return;
    }
    error? failed = trap openCurrencyRateListener(settings);
    if failed is error {
        log:printError("Currency-rate listener not started; the HTTP operations are not affected",
                reason = failed.message());
        return;
    }
    log:printInfo("Currency-rate listener started", offsetReset = core:offsetResetOf(settings.autoOffsetReset),
            tries = core:attemptsOf(settings), pauseSeconds = core:retryPauseOf(settings));
}

function openCurrencyRateListener(core:RateListenerSettings settings) returns error? {
    string word = core:offsetResetOf(settings.autoOffsetReset);
    kafka:OffsetResetMethod offsetReset = word == "earliest" ? kafka:OFFSET_RESET_EARLIEST
        : (word == "none" ? kafka:OFFSET_RESET_NONE : kafka:OFFSET_RESET_LATEST);
    // one message per poll, committed by hand on receipt: the commit covers exactly the message
    // that is about to be worked on
    kafka:Listener rateListener = check new (settings.bootstrapServers.trim(), {
        groupId: settings.groupId.trim(),
        topics: [settings.topic.trim()],
        offsetReset: offsetReset,
        autoCommit: false,
        maxPollRecords: 1,
        pollingInterval: 1
    });
    check rateListener.attach(currencyRateConsumer);
    check rateListener.'start();
    runtime:registerListener(rateListener);
}

final kafka:Service currencyRateConsumer = service object {
    remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) {
        kafka:Error? committed = caller->'commit();
        if committed is kafka:Error {
            log:printWarn("Currency-rate position could not be committed", reason = committed.message());
        }
        foreach kafka:BytesConsumerRecord entry in records {
            handleRateMessage(entry.value);
        }
    }

    remote function onError(kafka:Error failure) {
        // an unreachable broker reports once per poll; one line a minute is enough
        decimal now = time:monotonicNow();
        boolean report = false;
        lock {
            if listenerErrorLoggedAt < 0d || now - listenerErrorLoggedAt >= 60d {
                listenerErrorLoggedAt = now;
                report = true;
            }
        }
        if report {
            log:printError("Currency-rate listener reported an error; it keeps trying", reason = failure.message());
        }
    }
};

isolated decimal listenerErrorLoggedAt = -1;

# Everything that is done with one message.
#
# + value - The message's value
function handleRateMessage(byte[] value) {
    string correlationId = uuid:createType4AsString();
    log:printInfo("Currency-rate message received", correlationId = correlationId, bytes = value.length());
    string|error text = string:fromBytes(value);
    core:RateEvent[]|error events = text is error ? error("the message is not text") : core:rateEventsOf(text);
    if events is error {
        skipRateMessage("EXPRESSION", events.message(), "N/A", correlationId);
        return;
    }
    log:printInfo("Currency events extracted", correlationId = correlationId, records = events.length());
    if events.length() == 0 {
        log:printInfo("No currency events found to process.", correlationId = correlationId);
        return;
    }
    map<json>|error upsert = core:rateUpsertOf(events);
    if upsert is error {
        skipRateMessage("EXPRESSION", upsert.message(), "N/A", correlationId);
        return;
    }
    error? failed = storeRates(upsert, correlationId);
    if failed is error {
        core:RateFailure failure = core:retryExhaustedOf(failed.message());
        log:printError("Currency rates were not stored after all tries", correlationId = correlationId,
                messageType = failure.messageType, responseCode = failure.responseCode,
                reason = failure.responsePayload);
        skipRateMessage(failure.messageType, failure.message + ". Last failure: " + failure.responsePayload, "N/A",
                correlationId);
        return;
    }
    log:printInfo("Currency rates stored", correlationId = correlationId, records = events.length());
}

# The upsert through the DB system API, repeated as often as Mule's until-successful.
#
# + upsert - DB system API request
# + correlationId - Correlation id
# + return - The last failure when no try succeeded
function storeRates(map<json> upsert, string correlationId) returns error? {
    if !dbConfigured() {
        return error("hTTPDBSystemAPIConfig.url is not set");
    }
    int tries = core:attemptsOf(currencyRateListener);
    decimal pause = core:retryPauseOf(currencyRateListener);
    string reason = "";
    foreach int attempt in 1 ... tries {
        json|error stored = dbCall(upsert, correlationId);
        if stored !is error {
            return;
        }
        reason = stored.message();
        log:printWarn("Currency rates not stored", correlationId = correlationId, attempt = attempt, tries = tries,
                reason = reason);
        if attempt < tries {
            runtime:sleep(pause);
        }
    }
    return error(reason);
}

// A message that is given up: logged, alert e-mail in the background, on to the next message.
function skipRateMessage(string errorType, string description, string details, string correlationId) {
    log:printError("INVALID MESSAGE - SKIPPING", correlationId = correlationId, errorType = errorType,
            reason = description);
    future<()> _ = start sendRateAlert(errorType, description, details, correlationId);
    log:printWarn("Invalid message SKIPPED - Kafka will move to next message", correlationId = correlationId);
}

isolated function sendRateAlert(string errorType, string description, string details, string correlationId) {
    if core:isPlaceholderAddress(hTTPRequestConfiguration.url) || currencyRateListener.alertTo.trim() == "" {
        log:printWarn("Alert e-mail not sent: hTTPRequestConfiguration.url or currencyRateListener.alertTo is not set",
                correlationId = correlationId);
        return;
    }
    map<json> mail = core:alertEmailOf(errorType, description, details, currencyRateListener.alertTo,
            currencyRateListener.alertCc);
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response|http:ClientError reply = emailSysClient->post(emailApiPath, mail.toJsonString().toBytes(), headers);
    if reply is http:ClientError {
        log:printError("Alert e-mail not sent", correlationId = correlationId,
                errorType = commons:errorTypeOfClientError(reply));
    } else if reply.statusCode >= 400 {
        log:printError("Alert e-mail not sent", correlationId = correlationId, status = reply.statusCode);
    } else {
        log:printInfo("Alert e-mail sent", correlationId = correlationId);
    }
}
