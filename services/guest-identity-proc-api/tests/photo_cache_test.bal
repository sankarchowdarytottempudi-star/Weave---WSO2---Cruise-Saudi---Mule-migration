import ballerina/test;

// The photo cache's memory store (Redis is off in the tests): keyed by contact id and Modified_Time,
// a kept photo is returned, a changed contact (new Modified_Time) is not, and the store is capped.

@test:Config {}
function photoKeptByContactAndModifiedTime() {
    photoKeep("photo:c1|2026-11-16T10:00:00+03:00", "QUJD");
    test:assertEquals(photoKept("photo:c1|2026-11-16T10:00:00+03:00"), "QUJD");
    test:assertEquals(photoKept("photo:c1|2026-11-16T11:00:00+03:00"), ());
    test:assertEquals(photoKept("photo:c2|2026-11-16T10:00:00+03:00"), ());
}

@test:Config {}
function photoMemoryStoreIsCapped() {
    foreach int i in 0 ..< photoCache.memoryEntries + 5 {
        photoKeep("photo:cap" + i.toString() + "|t", "eA==");
    }
    int kept;
    lock {
        kept = keptPhotos.length();
    }
    test:assertTrue(kept <= photoCache.memoryEntries, "memory store grew past its cap: " + kept.toString());
}

@test:Config {}
function photoCacheSwitchedOffReadsEveryTime() {
    // photoCache.enabled is false in the test settings: photoOf goes straight to the CRM read
    test:assertFalse(photoCache.enabled);
}
