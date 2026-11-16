// Start-up: a few harmless read-only requests to this service itself, so the first caller after a
// deployment does not wait for the JVM, the connections to the backends and a Seaware session.
// The requests: a login password for an address that cannot exist (answers "not registered"
// after reading the guest store and the CRM; nothing is written and no e-mail is sent) and the
// trips of Seaware client 0 (no such client; the session it opens is kept for the first caller).

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import aroya/integration_commons as commons;

const WARM_UP_IDENTIFIER = "weave-warm-up@example.invalid";
const WARM_UP_ROUNDS = 3;
// "Ready" does not wait longer than this for the warm-up.
const decimal WARM_UP_LIMIT_SECONDS = 45;

final decimal startedAt = time:monotonicNow();
isolated boolean warm = false;

isolated function warmUpDone() {
    lock {
        warm = true;
    }
}

isolated function isReady() returns boolean {
    lock {
        if warm {
            return true;
        }
    }
    return time:monotonicNow() - startedAt > WARM_UP_LIMIT_SECONDS;
}

isolated function warmUp() {
    decimal began = time:monotonicNow();
    http:Client|error own = new ("http://localhost:" + httpPort.toString(), timeout = 30);
    int rounds = 0;
    if own is http:Client {
        foreach int attempt in 1 ... 15 {
            map<string> headers = {"source-system": "warm-up"};
            headers[commons:CORRELATION_HEADER] = "warm-up-" + attempt.toString();
            http:Response|error login = own->post(basePath + "/otp/generate",
                    {"identifier": WARM_UP_IDENTIFIER, "channel": "email", "context": "login"}, headers);
            if login is error {
                // The listener is not open yet.
                runtime:sleep(1);
                continue;
            }
            http:Response|error trips = own->post(basePath + "/guest-profiles/0", {}, headers);
            if trips is error {
                log:printWarn("Warm-up request did not finish", operation = "POST /guest-profiles/{guestId}");
            }
            rounds += 1;
            if rounds >= WARM_UP_ROUNDS {
                break;
            }
        }
    }
    warmUpDone();
    log:printInfo("Warm-up finished", rounds = rounds, durationMs = millisSince(began));
}
