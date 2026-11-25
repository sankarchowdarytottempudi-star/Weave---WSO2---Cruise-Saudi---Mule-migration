import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import ballerinax/redis;

// A short-lived cache shared by every copy of a service, with coalescing of identical requests.
//
//   - Values are text (callers keep JSON text, a token, a response body ...).
//   - Kept in Redis (shared by all copies, survives a restart) and in a small memory copy per
//     service copy, so a hit costs no round trip. Without Redis: memory only.
//   - Every value lives `ttlSeconds` from the moment it was fetched. The fetch time travels with
//     the value, so a copy that reads it from Redis keeps it no longer than the copy that fetched it.
//   - Identical requests at the same time: one leader fetches, the others wait for it and share its
//     value. The leader's in-flight mark expires after `waitSeconds`, so waiters are always released,
//     even when the leader fails or never comes back; a waiter that finds nothing fetches itself.
//   - Only what the caller marks as `keep` is kept. Errors are never kept.
//
// Lessons kept from cms-proc-api (2026-11-17): no read-only record literals (a `T & readonly`
// literal crashed the request handler inside the runtime); in-flight marks always expire.

# What a fetch produced.
#
# + value - The value as text
# + keep - True when it may be kept and shared (a successful answer); false = given to this caller only
public type CacheFill record {|
    string value;
    boolean keep = true;
|};

# A value and where it came from.
#
# + value - The value
# + origin - "cache" (kept value), "shared" (fetched by an identical request at the same time) or
# "fetched" (fetched for this request)
public type CacheAnswer record {|
    string value;
    string origin;
|};

# Where a shared cache keeps its values between copies of a service.
public type CacheStore isolated object {
    # + key - Key (the store adds its own prefix)
    # + return - The value, `()` when there is none
    public isolated function get(string key) returns string?|error;

    # + key - Key
    # + value - Value
    # + ttlSeconds - Seconds it is kept
    # + return - An error when it could not be kept
    public isolated function put(string key, string value, int ttlSeconds) returns error?;

    # + key - Key
    # + return - An error when it could not be removed
    public isolated function remove(string key) returns error?;

    # + return - Name of the store, for start-up logs
    public isolated function location() returns string;
};

# A CacheStore in Redis.
public isolated class RedisCacheStore {
    *CacheStore;
    private final redis:Client redisClient;
    private final string prefix;

    # + redisClient - Redis client
    # + prefix - Put in front of every key
    public isolated function init(redis:Client redisClient, string prefix) {
        self.redisClient = redisClient;
        self.prefix = prefix;
    }

    public isolated function get(string key) returns string?|error {
        return check self.redisClient->get(self.prefix + key);
    }

    public isolated function put(string key, string value, int ttlSeconds) returns error? {
        _ = check self.redisClient->setEx(self.prefix + key, value, ttlSeconds);
    }

    public isolated function remove(string key) returns error? {
        _ = check self.redisClient->del([self.prefix + key]);
    }

    public isolated function location() returns string => "Redis";
}

# A CacheStore in memory, shared by every SharedCache given the same object. Used in tests to play
# two copies of a service that share one store.
public isolated class MemoryCacheStore {
    *CacheStore;
    private final map<string> values = {};
    private final map<decimal> expires = {};

    public isolated function get(string key) returns string?|error {
        lock {
            decimal? until = self.expires[key];
            if until is decimal && until <= epochNow() {
                _ = self.values.removeIfHasKey(key);
                _ = self.expires.removeIfHasKey(key);
                return ();
            }
            return self.values[key];
        }
    }

    public isolated function put(string key, string value, int ttlSeconds) returns error? {
        lock {
            self.values[key] = value;
            self.expires[key] = epochNow() + <decimal>ttlSeconds;
        }
    }

    public isolated function remove(string key) returns error? {
        lock {
            _ = self.values.removeIfHasKey(key);
            _ = self.expires.removeIfHasKey(key);
        }
    }

    public isolated function location() returns string => "shared memory";
}

# A short-lived cache shared by every copy of a service, with coalescing of identical requests.
public isolated class SharedCache {
    private final CacheStore? store;
    private final int ttlSeconds;
    private final decimal waitSeconds;
    private final int memoryLimitBytes;
    // memory copy: key -> value, and key -> when it was fetched (epoch seconds)
    private final map<string> values = {};
    private final map<decimal> fetchedAt = {};
    private int memoryBytes = 0;
    // key -> monotonic clock reading when its fetch started; older than waitSeconds = abandoned
    private final map<decimal> inFlight = {};

    # + ttlSeconds - Seconds a value is used (0 or less: the cache is off, every call fetches)
    # + store - The store shared by the copies; `()` = memory of this copy only
    # + waitSeconds - Longest wait for an identical request's fetch (set it above the fetch's time limit)
    # + memoryLimitBytes - Size of the memory copy; it starts over when full
    public isolated function init(int ttlSeconds, CacheStore? store = (), decimal waitSeconds = 30,
            int memoryLimitBytes = 32000000) {
        self.ttlSeconds = ttlSeconds;
        self.store = store;
        self.waitSeconds = waitSeconds;
        self.memoryLimitBytes = memoryLimitBytes;
    }

    # + return - True when values are kept (ttlSeconds above 0)
    public isolated function isOn() returns boolean => self.ttlSeconds > 0;

    # + return - "off", or where values are kept and for how long, for start-up logs
    public isolated function describe() returns string {
        if self.ttlSeconds <= 0 {
            return "off";
        }
        CacheStore? store = self.store;
        return (store is () ? "memory" : store.location()) + ", " + self.ttlSeconds.toString() + " s";
    }

    # A kept value younger than ttlSeconds: the memory copy first, then the shared store.
    #
    # + key - Key
    # + return - The value, `()` when there is none (store problems count as none)
    public isolated function get(string key) returns string? {
        if self.ttlSeconds <= 0 {
            return ();
        }
        decimal now = epochNow();
        lock {
            decimal? at = self.fetchedAt[key];
            if at is decimal {
                if now - at < <decimal>self.ttlSeconds {
                    return self.values[key];
                }
                self.forgetLocked(key);
            }
        }
        CacheStore? store = self.store;
        if store is () {
            return ();
        }
        string?|error raw = store.get(key);
        if raw is error {
            log:printWarn("Shared cache could not be read", reason = raw.message());
            return ();
        }
        if raw is () {
            return ();
        }
        // stored as "<fetched at, epoch seconds>\n<value>"
        int? cut = raw.indexOf("\n");
        if cut is () {
            return ();
        }
        decimal|error at = decimal:fromString(raw.substring(0, cut));
        if at is error || now - at >= <decimal>self.ttlSeconds {
            return ();
        }
        string value = raw.substring(cut + 1);
        self.remember(key, value, at);
        return value;
    }

    # Keeps a value for ttlSeconds, in memory and in the shared store.
    #
    # + key - Key
    # + value - Value
    public isolated function put(string key, string value) {
        if self.ttlSeconds <= 0 {
            return;
        }
        decimal at = epochNow();
        self.remember(key, value, at);
        CacheStore? store = self.store;
        if store is () {
            return;
        }
        error? failed = store.put(key, at.toString() + "\n" + value, self.ttlSeconds + 1);
        if failed is error {
            log:printWarn("Shared cache could not be written", reason = failed.message());
        }
    }

    # Removes a value everywhere.
    #
    # + key - Key
    public isolated function remove(string key) {
        lock {
            self.forgetLocked(key);
        }
        CacheStore? store = self.store;
        if store is () {
            return;
        }
        error? failed = store.remove(key);
        if failed is error {
            log:printWarn("Shared cache value could not be removed", reason = failed.message());
        }
    }

    # Removes a value only while it is still `value` (for example a session token that stopped
    # working, without removing the new one another request has already put there).
    #
    # + key - Key
    # + value - The value that is no longer good
    # + return - True when it was removed
    public isolated function removeIfValue(string key, string value) returns boolean {
        string? now = self.get(key);
        if now is () || now != value {
            return false;
        }
        self.remove(key);
        return true;
    }

    # Becomes the one request that fetches `key`, unless an identical request is already fetching it.
    # A mark older than waitSeconds is taken over (its fetch is treated as abandoned).
    #
    # + key - Key
    # + return - The mark to give to `release`, or `()` when another request is fetching
    public isolated function lead(string key) returns decimal? {
        decimal now = time:monotonicNow();
        lock {
            decimal? since = self.inFlight[key];
            if since is () || now - since >= self.waitSeconds {
                self.inFlight[key] = now;
                return now;
            }
            return ();
        }
    }

    # Ends a fetch started with `lead`. Only the mark's own fetch is ended.
    #
    # + key - Key
    # + mark - What `lead` returned
    public isolated function release(string key, decimal mark) {
        lock {
            decimal? since = self.inFlight[key];
            if since is decimal && since == mark {
                _ = self.inFlight.removeIfHasKey(key);
            }
        }
    }

    # Waits for the identical request that is fetching `key` (at most until its mark expires), then
    # reads the kept value.
    #
    # + key - Key
    # + return - The value it kept, `()` when it kept none (failed, or not to be kept)
    public isolated function awaitShared(string key) returns string? {
        decimal mark = -1;
        lock {
            decimal? since = self.inFlight[key];
            if since is decimal {
                mark = since;
            }
        }
        while mark >= 0d && time:monotonicNow() - mark < self.waitSeconds {
            runtime:sleep(0.02);
            boolean busy;
            lock {
                decimal? since = self.inFlight[key];
                busy = since is decimal && since == mark;
            }
            if !busy {
                break;
            }
        }
        return self.get(key);
    }

    # The value of `key`: kept, shared with an identical request running at the same time, or fetched.
    #
    # + key - Key: everything the answer depends on
    # + fetcher - Produces the value when it is not kept; an error it returns is given to the caller
    # and never kept. (Written as a function type, not a type alias: the 2201.13.4 compiler crashes
    # on calls through an alias of an isolated function type.)
    # + return - The value and its origin, or the fetcher's error
    public isolated function getOrFetch(string key, isolated function () returns CacheFill|error fetcher)
            returns CacheAnswer|error {
        if self.ttlSeconds <= 0 {
            CacheFill fill = check fetcher();
            return {value: fill.value, origin: "fetched"};
        }
        string? kept = self.get(key);
        if kept is string {
            return {value: kept, origin: "cache"};
        }
        decimal? mark = self.lead(key);
        if mark is () {
            string? shared = self.awaitShared(key);
            if shared is string {
                return {value: shared, origin: "shared"};
            }
            // the other request kept nothing: fetch for this request
            CacheFill fill = check fetcher();
            if fill.keep {
                self.put(key, fill.value);
            }
            return {value: fill.value, origin: "fetched"};
        }
        CacheFill|error fill = fetcher();
        if fill is CacheFill && fill.keep {
            // kept before the mark is released, so the waiters find it
            self.put(key, fill.value);
        }
        self.release(key, mark);
        if fill is error {
            return fill;
        }
        return {value: fill.value, origin: "fetched"};
    }

    isolated function remember(string key, string value, decimal at) {
        lock {
            decimal? mine = self.fetchedAt[key];
            if mine is decimal && mine > at {
                return;
            }
            self.forgetLocked(key);
            if self.memoryBytes + value.length() > self.memoryLimitBytes {
                // keep it simple: start over when the memory budget is reached
                self.values.removeAll();
                self.fetchedAt.removeAll();
                self.memoryBytes = 0;
            }
            self.values[key] = value;
            self.fetchedAt[key] = at;
            self.memoryBytes += value.length();
        }
    }

    // removes the memory copy of one key (locks are re-entrant, so callers may hold the lock already)
    isolated function forgetLocked(string key) {
        lock {
            string? old = self.values[key];
            if old is string {
                self.memoryBytes -= old.length();
                _ = self.values.remove(key);
            }
            _ = self.fetchedAt.removeIfHasKey(key);
        }
    }
}

# A SharedCache kept in Redis when `settings.enabled`, else in this copy's memory.
#
# + settings - Redis settings (the platform Redis, intg-redis)
# + prefix - Put in front of every key in Redis, e.g. "cms-proc-api:content:"
# + ttlSeconds - Seconds a value is used (0 = off)
# + waitSeconds - Longest wait for an identical request's fetch
# + memoryLimitBytes - Size of the memory copy
# + return - The cache, or an error when Redis is switched on but cannot be set up
public isolated function newSharedCache(RedisSettings settings, string prefix, int ttlSeconds,
        decimal waitSeconds = 30, int memoryLimitBytes = 32000000) returns SharedCache|error {
    redis:Client? redisClient = check newRedisClient(settings, prefix);
    CacheStore? store = redisClient is () ? () : new RedisCacheStore(redisClient, prefix);
    return new SharedCache(ttlSeconds, store, waitSeconds, memoryLimitBytes);
}

isolated function epochNow() returns decimal {
    [int, decimal] t = time:utcNow();
    return <decimal>t[0] + t[1];
}
