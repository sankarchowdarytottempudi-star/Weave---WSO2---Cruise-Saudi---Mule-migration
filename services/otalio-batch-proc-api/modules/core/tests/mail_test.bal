import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

// A local stand-in for the e-mail system service and the CRM (127.0.0.1 only; nothing real is called).
isolated json[] mailsSeen = [];

listener http:Listener mailStandIn = new (19581);

service / on mailStandIn {
    isolated resource function post mail(@http:Payload json body) returns json {
        lock {
            mailsSeen.push(body.clone());
        }
        return {status: "sent"};
    }

    // every CRM / guest / database call fails, so every block fails
    isolated resource function 'default [string... path]() returns http:InternalServerError =>
        {body: {message: "stand-in: down"}};
}

isolated function mails() returns json[] {
    lock {
        return mailsSeen.clone();
    }
}

isolated function clearMails() {
    lock {
        mailsSeen = [];
    }
}

final MailSettings MAIL_ON = {enabled: true, url: "http://127.0.0.1:19581/mail", toAddress: "to@example.invalid",
                              ccAddress: "cc@example.invalid", env: "uat"};

@test:Config {}
function errorMailIsTheOldOneFieldByField() returns error? {
    json body = errorMailBody(MAIL_ON, "BAD_GATEWAY", "it failed", "{\"x\":1}", "{\"x\":1}");
    json msg = check body.message;
    test:assertEquals(check msg.subject, "uat - otalio-batch-proc-api");
    test:assertEquals(check msg.importance, "High");
    test:assertEquals(check msg.toRecipients, [{"emailAddress": {"address": "to@example.invalid"}}]);
    test:assertEquals(check msg.ccRecipients, [{"emailAddress": {"address": "cc@example.invalid"}}]);
    json[] files = <json[]>check msg.attachments;
    test:assertEquals(check files[0].name, "batch_errors.txt");
    test:assertEquals(check files[0].contentBytes, "eyJ4IjoxfQ==");
    test:assertEquals(check (check errorMailBody(MAIL_ON, "TIMEOUT", "", "", "").message).importance, "Low");
}

@test:Config {dependsOn: [errorMailIsTheOldOneFieldByField]}
function aFailedRunSendsOneErrorMail() returns error? {
    clearMails();
    SyncSettings sync = {mode: "full", retryWaitSeconds: 0};
    Backend nowhere = check new ("CRM system service", {url: "http://127.0.0.1:19581/zoho"}, sync);
    StateStore state = check new ({enabled: false, host: "", port: 6379}, "mailtest1:");
    OtalioSync job = new (state, new FakeRows([]), nowhere, nowhere, (), check new ErrorMail(MAIL_ON), sync, {});
    test:assertTrue(job.run().startsWith("failed: "));
    runtime:sleep(0.3);
    json[] seen = mails();
    test:assertEquals(seen.length(), 1);
    test:assertEquals(check (check seen[0].message).subject, "uat - otalio-batch-proc-api");
}

@test:Config {dependsOn: [aFailedRunSendsOneErrorMail]}
function aFailedBlockSendsNoMail() returns error? {
    clearMails();
    SyncSettings sync = {mode: "delta", retryWaitSeconds: 0, retryCount: 0, errorTable: "t", skipBookingNumbers: "('0')"};
    Backend down = check new ("CRM system service", {url: "http://127.0.0.1:19581/zoho"}, sync);
    StateStore state = check new ({enabled: false, host: "", port: 6379}, "mailtest2:");
    FakeRows fake = new ([[{"booking_number": "1001"}], sampleRows(), sampleRevenue(), sampleTransactions(), sampleItems()]);
    OtalioSync job = new (state, fake, down, down, down, check new ErrorMail(MAIL_ON), sync, {});
    string outcome = job.run();
    test:assertTrue(outcome.includes("1 failed block(s)"), outcome);
    runtime:sleep(0.3);
    test:assertEquals(mails().length(), 0, "a failed block stays inside the batch job, as in the old application");
}
