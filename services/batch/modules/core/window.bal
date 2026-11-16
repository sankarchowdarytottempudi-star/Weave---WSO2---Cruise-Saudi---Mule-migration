import ballerina/time;

# The slice of time one run asks the source for, and where in that slice to continue.
#
# + 'from - Start (yyyy-MM-ddTHH:mm:ssZ)
# + to - End (same form)
# + cursor - Page position inside the slice; "0" means from the start
public type Window record {|
    string 'from;
    string to;
    string cursor;
|};

# Works out the next slice exactly as the old job did.
#
# Incremental mode ("delta"): continue from the last finished slice, never ahead of the clock.
# Any other mode: walk from the configured start date in steps of `windowDays` up to the end date.
# A slice that still has pages left is repeated with the saved page position.
#
# + sync - Sync settings
# + state - Saved state (lastupdated, currentDate, seawareCursor, seawareNextPage)
# + now - Current time
# + return - The slice, or an error when a saved or configured date cannot be read
public isolated function nextWindow(SyncSettings sync, map<string> state, time:Utc now) returns Window|error {
    string lastUpdated = unquote(state["lastupdated"] ?: "");
    string nextPage = unquote(state["seawareNextPage"] ?: "");
    string savedCursor = unquote(state["seawareCursor"] ?: "");
    string current = state["currentDate"] ?: "";

    string cursor = savedCursor != "" && nextPage == "true" ? savedCursor : "0";
    boolean fresh = lastUpdated != "" && (nextPage == "false" || nextPage == "");
    if !fresh && current != "" && ((lastUpdated != "" && savedCursor != "" && nextPage == "true") || lastUpdated == "") {
        json saved = check current.fromJsonString();
        string? savedFrom = text(f(saved, "from"));
        string? savedTo = text(f(saved, "to"));
        if savedFrom is string && savedTo is string {
            return {'from: savedFrom, to: savedTo, cursor};
        }
    }

    time:Utc clock = [now[0], 0d];
    if sync.mode == "delta" {
        time:Utc earliest = time:utcAddSeconds(clock, <decimal>(-60 * sync.deltaFromMinutes));
        time:Utc latest = time:utcAddSeconds(clock, <decimal>(60 * sync.deltaToMinutes));
        if !fresh {
            return {'from: stamp(earliest), to: stamp(latest), cursor};
        }
        time:Utc x = check parseStamp(lastUpdated);
        time:Utc 'from = later(x, earliest) ? earliest : time:utcAddSeconds(x, -60);
        time:Utc to = later(x, clock) ? latest : time:utcAddSeconds(x, 600);
        return {'from: stamp('from), to: stamp(to), cursor};
    }
    time:Utc endDate = check parseStamp(sync.toDate);
    time:Utc x = check parseStamp(fresh ? lastUpdated : sync.fromDate);
    time:Utc reach = time:utcAddSeconds(x, <decimal>(86400 * sync.windowDays));
    return {'from: stamp(x), to: stamp(later(reach, endDate) ? endDate : reach), cursor};
}

isolated function later(time:Utc a, time:Utc b) returns boolean {
    return time:utcDiffSeconds(a, b) > 0d;
}

isolated function unquote(string value) returns string {
    return re `"`.replaceAll(value, "").trim();
}

# Formats a time the way the old job did (seconds, UTC, trailing Z).
#
# + utc - Time
# + return - Text
public isolated function stamp(time:Utc utc) returns string {
    return time:utcToString([utc[0], 0d]);
}

# Reads a saved or configured time.
#
# + value - Text such as 2026-01-31T10:00:00Z (the Z may be missing)
# + return - The time or an error
public isolated function parseStamp(string value) returns time:Utc|error {
    string v = unquote(value);
    if v == "" {
        return error("a date needed for the time slice is not set");
    }
    boolean zoned = v.endsWith("Z") || re `[+-]\d\d:?\d\d$`.find(v) !is ();
    return time:utcFromString(zoned ? v : v + "Z");
}
