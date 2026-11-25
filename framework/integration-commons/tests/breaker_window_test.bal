import ballerina/lang.runtime;
import ballerina/test;

// Circuit breaker "window" mode: N failures within a window open it, scattered failures do not, it stays
// open openSeconds, then lets exactly one trial call through; success closes, failure reopens. The default
// "consecutive" mode keeps its old behaviour.

function windowBreaker(MemoryBreakerStore store, int windowSeconds = 2, int openSeconds = 1) returns CircuitBreaker =>
    new ({dependencyName: "dep", mode: "window", failureThreshold: 5, failureWindowSeconds: windowSeconds,
            openSeconds, halfOpenTrialSeconds: 5}, store, "intg:test");

@test:Config {}
function windowOpensAtFiveFailuresWithinTheWindow() {
    CircuitBreaker b = windowBreaker(new);
    foreach int i in 1 ... 4 {
        b.recordFailure("TIMEOUT", "c");
    }
    test:assertFalse(b.isOpen("c"), "4 failures do not open it");
    b.recordFailure("GATEWAY_TIMEOUT", "c");
    test:assertTrue(b.isOpen("c"), "the 5th failure within the window opens it");
    test:assertEquals(b.retryAfterSeconds(), 1);
}

@test:Config {}
function scatteredFailuresNeverOpen() {
    CircuitBreaker b = windowBreaker(new, 1);
    foreach int i in 1 ... 7 {
        b.recordFailure("TIMEOUT", "c");
        runtime:sleep(0.3);
    }
    // 7 failures over about 2.1 s, never 5 within 1 s
    test:assertFalse(b.isOpen("c"), "scattered failures must not open the circuit");
}

@test:Config {}
function successesDoNotHideAFailureBurst() {
    CircuitBreaker b = windowBreaker(new);
    foreach int i in 1 ... 5 {
        b.recordFailure("TIMEOUT", "c");
        b.recordSuccess("c");
    }
    test:assertTrue(b.isOpen("c"), "5 failures within the window open it even with successes between them");
}

@test:Config {}
function clientErrorsAreNotFailures() {
    CircuitBreaker b = windowBreaker(new);
    foreach int i in 1 ... 10 {
        b.recordFailure("BAD_REQUEST", "c");
        b.recordFailure("NOT_FOUND", "c");
        b.recordFailure("UNAUTHORIZED", "c");
    }
    test:assertFalse(b.isOpen("c"));
}

@test:Config {}
function halfOpenLetsOneTrialThroughAndSuccessCloses() {
    CircuitBreaker b = windowBreaker(new);
    foreach int i in 1 ... 5 {
        b.recordFailure("TIMEOUT", "c");
    }
    test:assertTrue(b.isOpen("c"));
    runtime:sleep(1.2);
    test:assertFalse(b.isOpen("trial"), "after openSeconds one trial call goes through");
    test:assertTrue(b.isOpen("other"), "while the trial runs the others still fail fast");
    b.recordSuccess("trial");
    test:assertFalse(b.isOpen("c"), "a successful trial closes it");
    test:assertFalse(b.isOpen("c"));
    foreach int i in 1 ... 4 {
        b.recordFailure("TIMEOUT", "c");
    }
    test:assertFalse(b.isOpen("c"), "closed again with a fresh window");
}

@test:Config {}
function failedTrialReopens() {
    CircuitBreaker b = windowBreaker(new);
    foreach int i in 1 ... 5 {
        b.recordFailure("TIMEOUT", "c");
    }
    runtime:sleep(1.2);
    test:assertFalse(b.isOpen("trial"));
    b.recordFailure("TIMEOUT", "trial");
    test:assertTrue(b.isOpen("c"), "a failed trial opens it again");
    runtime:sleep(1.2);
    test:assertFalse(b.isOpen("trial2"), "and after openSeconds another single trial");
    test:assertTrue(b.isOpen("other"));
}

@test:Config {}
function lostTrialFreesItsPlace() {
    MemoryBreakerStore store = new;
    CircuitBreaker b = new ({dependencyName: "dep", mode: "window", failureThreshold: 2, failureWindowSeconds: 5,
            openSeconds: 1, halfOpenTrialSeconds: 1}, store, "intg:test");
    b.recordFailure("TIMEOUT", "c");
    b.recordFailure("TIMEOUT", "c");
    runtime:sleep(1.1);
    test:assertFalse(b.isOpen("trial"));
    runtime:sleep(1.1);
    test:assertFalse(b.isOpen("trial2"), "a trial that never reported back frees its place");
}

@test:Config {}
function consecutiveModeIsUnchanged() {
    CircuitBreaker b = new ({dependencyName: "dep", failureThreshold: 3, openDurationSeconds: 1}, new MemoryBreakerStore(),
        "intg:test");
    b.recordFailure("TIMEOUT", "c");
    b.recordFailure("TIMEOUT", "c");
    b.recordSuccess("c");
    b.recordFailure("TIMEOUT", "c");
    b.recordFailure("TIMEOUT", "c");
    test:assertFalse(b.isOpen("c"), "a success resets the counter");
    b.recordFailure("TIMEOUT", "c");
    test:assertTrue(b.isOpen("c"));
    runtime:sleep(1.2);
    test:assertFalse(b.isOpen("a"), "after the open time every call goes through");
    test:assertFalse(b.isOpen("b"), "no half-open single trial in this mode");
    test:assertEquals(b.retryAfterSeconds(), 1);
}

@test:Config {}
function breakerDescribesItself() {
    CircuitBreaker w = windowBreaker(new, 30, 30);
    test:assertEquals(w.describe(),
            "window: opens at 5 failures within 30 s, open 30 s, then half-open with one trial call");
    CircuitBreaker off = new ({enabled: false, dependencyName: "d"}, (), "intg:test");
    test:assertEquals(off.describe(), "off");
}
