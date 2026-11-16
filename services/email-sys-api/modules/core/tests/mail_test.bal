import ballerina/test;

@test:Config {}
function exchangeMailWrapsTheBodyLikeTheOldFlow() {
    Mail|string mail = exchangeMailOf({to: ["guest@example.invalid"], subject: "Your code", body: "<p>123456</p>"});
    test:assertEquals(mail, <Mail>{to: ["guest@example.invalid"], subject: "Your code",
        body: "<!DOCTYPE html><html><body><p>123456</p></body></html>"});
}

@test:Config {}
function exchangeMailTakesOneAddressAsText() {
    Mail|string mail = exchangeMailOf({to: " guest@example.invalid ", subject: "s", body: 42});
    test:assertEquals(mail, <Mail>{to: ["guest@example.invalid"], subject: "s",
        body: "<!DOCTYPE html><html><body>42</body></html>"});
}

@test:Config {}
function exchangeMailNamesWhatIsMissing() {
    test:assertEquals(exchangeMailOf("text"), "The body must be an object with to, subject and body");
    test:assertEquals(exchangeMailOf({subject: "s", body: "b"}), "to is required");
    test:assertEquals(exchangeMailOf({to: [], subject: "s", body: "b"}), "to is required");
    test:assertEquals(exchangeMailOf({to: ["not an address"], subject: "s", body: "b"}), "to must hold e-mail addresses");
    test:assertEquals(exchangeMailOf({to: [7], subject: "s", body: "b"}), "to must hold e-mail addresses");
    test:assertEquals(exchangeMailOf({to: ["a@example.invalid\nBcc: x@example.invalid"], subject: "s", body: "b"}),
            "to must hold e-mail addresses");
    test:assertEquals(exchangeMailOf({to: ["a@example.invalid"], body: "b"}), "subject is required");
    test:assertEquals(exchangeMailOf({to: ["a@example.invalid"], subject: " ", body: "b"}), "subject is required");
    test:assertEquals(exchangeMailOf({to: ["a@example.invalid"], subject: "s"}), "body is required");
    test:assertEquals(exchangeMailOf({to: ["a@example.invalid"], subject: "s", body: {}}), "body is required");
}

@test:Config {}
function shipMailUsesTheFixedRecipients() {
    json payload = {message: {subject: "Report", body: {contentType: "HTML", content: "<b>done</b>"},
        toRecipients: [{emailAddress: {address: "ignored@example.invalid"}}]}};
    test:assertEquals(shipMailOf(payload, ["ops@example.invalid"], ["copy@example.invalid"]),
            <Mail>{to: ["ops@example.invalid"], cc: ["copy@example.invalid"], subject: "Report", body: "<b>done</b>"});
}

@test:Config {}
function shipMailCarriesTheFirstAttachment() {
    json payload = {message: {subject: "Report", body: {content: "x"}, attachments: [
        {name: "a.csv", contentType: "text/csv", contentBytes: "YSxiCg=="},
        {name: "b.csv", contentType: "text/csv", contentBytes: "Yyxk"}]}};
    Mail|string mail = shipMailOf(payload, ["ops@example.invalid"], []);
    test:assertTrue(mail is Mail);
    if mail is Mail {
        test:assertEquals(mail.attachment, <Attachment>{name: "a.csv", contentType: "text/csv", contentBase64: "YSxiCg=="});
    }
}

@test:Config {}
function shipMailNamesWhatIsMissing() {
    test:assertEquals(shipMailOf({}, [], []), "message is required");
    test:assertEquals(shipMailOf({message: {subject: "s"}}, [], []), "message.body.content is required");
    test:assertEquals(shipMailOf({message: {body: {content: "x"}, attachments: [{name: "a"}]}}, [], []),
            "message.attachments[0] needs name and contentBytes");
}

@test:Config {}
function onlyTheTwoHundredRangeCountsAsSent() {
    test:assertTrue(accepted(200));
    test:assertTrue(accepted(202));
    test:assertFalse(accepted(308));
    test:assertFalse(accepted(301));
    test:assertFalse(accepted(401));
    test:assertFalse(accepted(500));
    test:assertFalse(accepted(199));
}

@test:Config {}
function missingSettingsAreNamed() {
    test:assertEquals(missingOf({"smtpZepto.host": "mail.example.invalid", "smtpZepto.user": "", "smtpZepto.password": " ",
        "sendEmailHTTPRequestConfig.url": "http://localhost"}),
            ["smtpZepto.user", "smtpZepto.password", "sendEmailHTTPRequestConfig.url"]);
    test:assertEquals(missingOf({"a": "x"}), []);
}

@test:Config {}
function addressesNeverReachALogLine() {
    test:assertEquals(withoutAddresses("550 5.1.1 <guest.one@example.invalid>: user unknown"),
            "550 5.1.1 <<address>>: user unknown");
    test:assertEquals(withoutAddresses("no address here"), "no address here");
    test:assertEquals(withoutAddresses("".padEnd(400, "x")).length(), 300);
}

@test:Config {}
function plainHttpToAnOutsideHostIsFlagged() {
    test:assertTrue(shouldBeHttps("http://mail.example.invalid/v1.0/users/x/sendMail"));
    test:assertFalse(shouldBeHttps("https://mail.example.invalid/v1.0/users/x/sendMail"));
    test:assertFalse(shouldBeHttps("http://localhost"));
    test:assertFalse(shouldBeHttps("http://127.0.0.1:18190/send"));
    test:assertFalse(shouldBeHttps("http://email-sys-api.wso2.svc:80"));
    test:assertFalse(shouldBeHttps("http://provider-double:8080/send"));
}
