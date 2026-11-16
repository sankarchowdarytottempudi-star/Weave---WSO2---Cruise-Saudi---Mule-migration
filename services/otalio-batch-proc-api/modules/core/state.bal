import aroya/integration_commons as commons;

import ballerinax/redis;

# Where the job remembers how far it got (the old application's object store).
#
# With Redis switched on the values survive restarts and are shared by all copies of the service.
# Without it they live in memory: a restart forgets them and the job starts again from its
# configured start.
public isolated class StateStore {
    private final redis:Client? store;
    private final string prefix;
    private final map<string> memory = {};

    # + settings - Redis settings (`enabled = false` keeps the values in memory)
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

    # Reads one value.
    #
    # + key - Name
    # + return - The value, "" when there is none
    public isolated function get(string key) returns string|error {
        redis:Client? store = self.store;
        if store is () {
            lock {
                return self.memory[key] ?: "";
            }
        }
        string? value = check store->get(self.prefix + key);
        return value ?: "";
    }

    # Saves one value.
    #
    # + key - Name
    # + value - Value
    # + return - An error when it could not be saved
    public isolated function put(string key, string value) returns error? {
        redis:Client? store = self.store;
        if store is () {
            lock {
                self.memory[key] = value;
            }
            return;
        }
        _ = check store->set(self.prefix + key, value);
    }

    # Reads several values at once.
    #
    # + keys - Names
    # + return - Name to value ("" when there is none)
    public isolated function all(string[] keys) returns map<string>|error {
        map<string> out = {};
        foreach string key in keys {
            out[key] = check self.get(key);
        }
        return out;
    }

    # Forgets the given values.
    #
    # + keys - Names
    # + return - An error when they could not be removed
    public isolated function clear(string[] keys) returns error? {
        redis:Client? store = self.store;
        if store is () {
            readonly & string[] names = keys.cloneReadOnly();
            lock {
                foreach string key in names {
                    if self.memory.hasKey(key) {
                        _ = self.memory.remove(key);
                    }
                }
            }
            return;
        }
        string prefix = self.prefix;
        _ = check store->del(from string key in keys select prefix + key);
    }
}
