import db_sys_api.core;

import ballerina/log;
import ballerina/sql;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

// One connection pool per database account, opened at the first call that needs it. Nothing
// connects at start, so the service comes up without database settings. A pool that could not
// be opened is not kept: the next call tries again.

isolated class AccountPool {
    private final string connectionKey;
    private postgresql:Client? db = ();

    isolated function init(string connectionKey) {
        self.connectionKey = connectionKey;
    }

    # The pool of this account.
    #
    # + return - The database client, or the refusal to answer with (503 settings, 500 not reachable)
    isolated function clientOf() returns postgresql:Client|core:Refusal {
        core:AccountSettings & readonly account = self.connectionKey == core:KEY_SHIP_TRACKING ? shipTracking : guest;
        string[] notSet = core:settingsNotSet(self.connectionKey, database, account);
        if notSet.length() > 0 {
            return core:notConfigured(notSet);
        }
        lock {
            postgresql:Client? open = self.db;
            if open is postgresql:Client {
                return open;
            }
            postgresql:Client|sql:Error created = new (database.host.trim(), account.username.trim(), account.password,
                database.name.trim(), database.port,
                {connectTimeout: database.connectTimeoutSeconds},
                {maxOpenConnections: database.maxOpenConnections, minIdleConnections: database.minIdleConnections}
            );
            if created is sql:Error {
                // Only the kind of failure is logged; the driver's text can carry the address and the user.
                string reason = core:connectFailureOf(created);
                log:printError("db connection failed", connectionKey = self.connectionKey, reason = reason);
                return core:notReachable(reason);
            }
            self.db = created;
            return created;
        }
    }
}

final AccountPool shipTrackingPool = new (core:KEY_SHIP_TRACKING);
final AccountPool guestPool = new (core:KEY_GUEST);
