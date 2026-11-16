import ballerina/time;
import ballerinax/redis;

import aroya/integration_commons as commons;

// The old application's object store, now in Redis: shared by every copy of the service and kept
// over restarts. With stateRedis.enabled = false it is kept in memory only (explicit fallback).
// Old: Object_store_accessToken (11 hours), key access_Token (accessTokenValidattionSub_Flow, accessTokenSub_Flow);
// VoyageCacheOS (8 hours) is written by seaware-live-call-flow and never read by the old application.

final StateStore state = check new (stateRedis, "reservation-common-services-process-api:");

# Keeps what the source kept in its object store.
#
# With Redis switched on the values survive restarts and are the same for every copy of the service.
# With `enabled = false` they live in memory only: a restart forgets them.
public isolated class StateStore {
    private final redis:Client? store;
    private final string prefix;
    private final map<string> memory = {};
    private final map<decimal> expires = {};

    # + settings - Redis settings
    # + prefix - Put in front of every key
    # + return - An error when Redis is switched on but cannot be set up
    public isolated function init(commons:RedisSettings settings, string prefix) returns error? {
        self.prefix = prefix;
        self.store = check commons:newRedisClient(settings, prefix);
    }

    # + return - "Redis" or "memory"
    public isolated function location() returns string {
        return self.store is () ? "memory" : "Redis";
    }

    # + key - Name
    # + return - The value, () when there is none or it has expired
    public isolated function get(string key) returns string?|error {
        redis:Client? store = self.store;
        if store is () {
            lock {
                decimal? until = self.expires[key];
                if until is decimal && until <= now() {
                    _ = self.memory.removeIfHasKey(key);
                    _ = self.expires.removeIfHasKey(key);
                    return ();
                }
                return self.memory[key];
            }
        }
        return check store->get(self.prefix + key);
    }

    # + key - Name
    # + value - Value
    # + ttlSeconds - Time to live (0 = keep)
    # + return - An error when it could not be saved
    public isolated function put(string key, string value, int ttlSeconds = 0) returns error? {
        redis:Client? store = self.store;
        if store is () {
            lock {
                self.memory[key] = value;
                if ttlSeconds > 0 {
                    self.expires[key] = now() + <decimal>ttlSeconds;
                } else {
                    _ = self.expires.removeIfHasKey(key);
                }
            }
            return;
        }
        if ttlSeconds > 0 {
            _ = check store->setEx(self.prefix + key, value, ttlSeconds);
        } else {
            _ = check store->set(self.prefix + key, value);
        }
    }

    # + key - Name
    # + return - Whether a value is kept
    public isolated function contains(string key) returns boolean|error {
        return (check self.get(key)) is string;
    }

    # + key - Name
    # + return - An error when it could not be removed
    public isolated function remove(string key) returns error? {
        redis:Client? store = self.store;
        if store is () {
            lock {
                _ = self.memory.removeIfHasKey(key);
                _ = self.expires.removeIfHasKey(key);
            }
            return;
        }
        _ = check store->del([self.prefix + key]);
    }

    # Removes every value of this service (the source's os:clear).
    #
    # + return - An error when they could not be removed
    public isolated function clear() returns error? {
        redis:Client? store = self.store;
        if store is () {
            lock {
                self.memory.removeAll();
                self.expires.removeAll();
            }
            return;
        }
        string[] all = check store->keys(self.prefix + "*");
        if all.length() > 0 {
            _ = check store->del(all);
        }
    }
}

isolated function now() returns decimal {
    [int, decimal] t = time:utcNow();
    return <decimal>t[0] + t[1];
}
