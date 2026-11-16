// The reconciliation job (Mule: payment-reconciliation-scheduler-flow).
//
// Every run:
//   1. reads the payment audit rows of the last minutes through the database system API;
//   2. for each row takes the order reference and the booking number out of the stored request
//      and response;
//   3. calls process-payment of financial-transactions-proc-api when the row has no attempt yet
//      or its latest attempt may be repeated (HTTP 500, or HTTP 400 with TELR_PENDING or
//      CUSTOM-ERROR); other rows are left alone;
//   4. writes the counts to the log and, when the summary e-mail is on, sends the summary.
// A row that fails does not stop the run; a run that fails does not stop the timer.

import payment_reconciliation_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/task;
import ballerina/uuid;
import aroya/integration_commons as commons;

# The clients of a run.
#
# + db - The database system API
# + payments - financial-transactions-proc-api
# + email - The e-mail system API; `()` while the summary e-mail is off
type Backends record {|
    http:Client db;
    http:Client payments;
    http:Client? email;
|};

# An answer with a status from 200 to 299.
#
# + status - HTTP status
# + body - Body as JSON, as text when it is not JSON, `()` when it is empty
type Reply record {|
    int status;
    json body;
|};

# A call that failed: no answer, or a status outside 200 to 299 (Mule raises an error for both).
#
# + errorType - Kind of failure
# + statusCode - HTTP status; empty text when there was no answer
# + description - The failure in words
# + response - Answer body; `()` when there was none
type Failure record {|
    string errorType;
    json statusCode;
    string description;
    json response;
|};

// One run at a time (Mule: maxConcurrency="1").
isolated boolean runActive = false;

isolated function claimRun() returns boolean {
    lock {
        if runActive {
            return false;
        }
        runActive = true;
        return true;
    }
}

isolated function releaseRun() {
    lock {
        runActive = false;
    }
}

class ReconciliationJob {
    *task:Job;
    private final Backends backends;

    function init(Backends backends) {
        self.backends = backends;
    }

    public function execute() {
        if !claimRun() {
            log:printWarn("Payment reconciliation run skipped: the previous run is still working");
            return;
        }
        error? failure = trap reconcile(self.backends);
        if failure is error {
            log:printError("Payment reconciliation scheduler failed", errorType = "UNEXPECTED",
                    description = failure.message());
        }
        releaseRun();
    }
}

# Starts the timer when it is switched on and everything it needs is set.
#
# + return - The state of the timer, for the start-up line
function startTimer() returns string {
    if !scheduler.enabled {
        return "off";
    }
    string[] notSet = core:settingsNotSet({
        frequencyMinutes: scheduler.frequencyMinutes,
        sql: query.sql,
        connectionKey: dbSysApi.connectionKey,
        dbUrl: dBSysAPIHTTPRequestConfig.url,
        paymentsUrl: financialTransactionsHTTPRequestConfig.url,
        emailEnabled: email.enabled,
        emailUrl: emailSysAPIHTTPRequestConfig.url,
        emailTo: email.to
    });
    if notSet.length() > 0 {
        return "NOT STARTED, settings not set: " + string:'join(", ", ...notSet);
    }
    do {
        Backends backends = {
            db: check commons:newDownstreamClient(dBSysAPIHTTPRequestConfig),
            payments: check commons:newDownstreamClient(financialTransactionsHTTPRequestConfig),
            email: email.enabled ? check commons:newDownstreamClient(emailSysAPIHTTPRequestConfig) : ()
        };
        // The first run starts at once and the next ones follow every frequencyMinutes, as the old
        // fixed-frequency timer did. A failed run does not cancel the timer (LOG_AND_CONTINUE).
        // source-entry: payment-reconciliation-scheduler-flow
        _ = check task:scheduleJobRecurByFrequency(new ReconciliationJob(backends), <decimal>(scheduler.frequencyMinutes * 60),
                taskPolicy = {errorPolicy: task:LOG_AND_CONTINUE, waitingPolicy: task:LOG_AND_IGNORE});
        return string `ON, every ${scheduler.frequencyMinutes} min`;
    } on fail error e {
        log:printError("The timed job could not be started", reason = e.message());
        return "NOT STARTED, see the error line above";
    }
}

# One run of the job.
#
# + backends - The clients of the run
function reconcile(Backends backends) {
    string correlationId = "payment-reconciliation-" + uuid:createType4AsString();
    log:printInfo("Payment reconciliation scheduler started", frequencyMinutes = scheduler.frequencyMinutes,
            lookbackMinutes = query.lookbackMinutes, graceMinutes = query.graceMinutes, batchSize = query.batchSize,
            correlationId = correlationId);
    map<json>[] success = [];
    map<json>[] failed = [];
    map<json>[] skipped = [];

    log:printInfo("Fetching payment audit records through db-sys-api", connectionKey = dbSysApi.connectionKey,
            correlationId = correlationId);
    Reply|Failure fetched = post(backends.db, dbSysApi.dbPath,
            core:dbSelectRequest(query, dbSysApi.connectionKey, dbSysApi.sessionId), {}, correlationId);
    if fetched is Failure {
        runFailed(correlationId, "reading the audit rows", fetched);
        return;
    }
    json[] rows = core:rowsOf(core:recordsOf(fetched.body));
    log:printInfo("Payment reconciliation fetched audit record(s)", count = rows.length(), correlationId = correlationId);

    foreach json row in rows {
        string paymentCorrelationId = "payment-reconciliation-record-" + uuid:createType4AsString();
        core:PaymentRequest|error request = core:paymentRequestOf(row);
        if request is error {
            // The stored text is not written to the log: it holds the payment's data.
            string description = "The stored request or response of the audit row is not JSON";
            failed.push(core:failedRecord((), paymentCorrelationId, "MULE:EXPRESSION", "", description, ()));
            log:printError("Payment reconciliation record failed", schedulerCorrelationId = correlationId,
                    paymentCorrelationId = paymentCorrelationId, errorType = "MULE:EXPRESSION", description = description);
            continue;
        }
        string sessionId = core:textOf(request.sessionId);
        string orderRef = core:textOf(request.orderRef);
        string bookingNumber = core:textOf(request.bookingNumber);
        if !core:isComplete(request) {
            skipped.push(core:missingRecord(request, paymentCorrelationId));
            log:printWarn("Skipping payment reconciliation record because orderRef or bookingNumber is missing",
                    sessionId = sessionId, orderRef = orderRef, bookingNumber = bookingNumber, rowKeys = core:rowKeysOf(row),
                    schedulerCorrelationId = correlationId, paymentCorrelationId = paymentCorrelationId);
            continue;
        }
        core:RetryDecision decision = core:retryDecisionOf(row);
        if !decision.shouldProcess {
            skipped.push(core:notRetryableRecord(request, paymentCorrelationId, decision));
            log:printInfo("Skipping process-payment because latest attempt is not retryable", bookingNumber = bookingNumber,
                    orderRef = orderRef, reason = decision.reason, httpStatus = decision.httpStatus,
                    errorCode = decision.errorCode, schedulerCorrelationId = correlationId,
                    paymentCorrelationId = paymentCorrelationId);
            continue;
        }
        log:printInfo("Invoking process-payment", retryReason = decision.reason, sessionId = sessionId, orderRef = orderRef,
                bookingNumber = bookingNumber, schedulerCorrelationId = correlationId,
                paymentCorrelationId = paymentCorrelationId);
        Reply|Failure paid = post(backends.payments, financialTransactions.processPaymentPath, core:requestBodyOf(request),
                {"client_channel": financialTransactions.clientChannel}, paymentCorrelationId);
        if paid is Failure {
            failed.push(core:failedRecord(request, paymentCorrelationId, paid.errorType, paid.statusCode, paid.description,
                    paid.response));
            log:printError("Payment reconciliation record failed", sessionId = sessionId,
                    schedulerCorrelationId = correlationId, paymentCorrelationId = paymentCorrelationId,
                    errorType = paid.errorType, statusCode = paid.statusCode.toString(), description = paid.description);
            continue;
        }
        log:printInfo("process-payment completed", statusCode = paid.status, sessionId = sessionId,
                schedulerCorrelationId = correlationId, paymentCorrelationId = paymentCorrelationId);
        success.push(core:successRecord(request, paymentCorrelationId, paid.status, paid.body));
    }

    log:printInfo("Payment reconciliation scheduler completed", successCount = success.length(),
            failedCount = failed.length(), skippedCount = skipped.length(), correlationId = correlationId);

    http:Client? emailClient = backends.email;
    if !email.enabled || emailClient is () {
        log:printInfo("Payment reconciliation email is disabled", correlationId = correlationId);
        return;
    }
    Reply|Failure sent = post(emailClient, email.sendEmailPath,
            core:emailMessage(email.to, email.subjectPrefix, correlationId, query, success, failed, skipped),
            {"provider": email.provider}, correlationId);
    if sent is Failure {
        runFailed(correlationId, "sending the summary e-mail", sent);
        return;
    }
    log:printInfo("Payment reconciliation email sent", statusCode = sent.status, correlationId = correlationId);
}

function runFailed(string correlationId, string step, Failure failure) {
    log:printError("Payment reconciliation scheduler failed", correlationId = correlationId, step = step,
            errorType = failure.errorType, statusCode = failure.statusCode.toString(), description = failure.description);
}

# Sends a JSON body with POST.
#
# + backend - Client of the backend
# + path - Path to call
# + body - JSON body
# + headers - Extra headers
# + correlationId - Value of the `correlationId` header
# + return - The answer, or the failure when there was none or its status is outside 200 to 299
function post(http:Client backend, string path, json body, map<string> headers, string correlationId)
        returns Reply|Failure {
    http:Request request = new;
    request.setJsonPayload(body);
    foreach [string, string] [name, value] in headers.entries() {
        request.setHeader(name, value);
    }
    request.setHeader(commons:CORRELATION_HEADER, correlationId);
    http:Response|http:ClientError answer = backend->post(path, request);
    if answer is http:ClientError {
        // The library's text can contain the backend's address, so it is not passed on.
        boolean timedOut = answer is http:IdleTimeoutError;
        Failure failure = {
            errorType: timedOut ? "HTTP:TIMEOUT" : "HTTP:CONNECTIVITY",
            statusCode: "",
            description: core:failureDescription(path, (), timedOut),
            response: ()
        };
        return failure;
    }
    int status = answer.statusCode;
    json payload = payloadOf(answer);
    if status < 200 || status > 299 {
        Failure failure = {
            errorType: core:errorTypeOfStatus(status),
            statusCode: status,
            description: core:failureDescription(path, status),
            response: payload
        };
        return failure;
    }
    Reply reply = {status, body: payload};
    return reply;
}

function payloadOf(http:Response answer) returns json {
    string|http:ClientError text = answer.getTextPayload();
    if text is http:ClientError || text.trim() == "" {
        return ();
    }
    json|error parsed = text.fromJsonString();
    return parsed is error ? text : parsed;
}
