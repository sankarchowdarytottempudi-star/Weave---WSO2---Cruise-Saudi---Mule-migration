// Types of the database system API. The logic in this module is pure: it reads the request,
// takes the statement apart, builds the bound query and shapes the answers. The database itself
// is only touched from the root module.

# Connection key of the ship tracking account (Mule: `Database_Config_PG_ShipTracking`).
public const string KEY_SHIP_TRACKING = "PG_ShipTracking";
# Connection key of the guest account (Mule: `Database_Config_PG_GuestData`).
public const string KEY_GUEST = "PG_Guest";

# What the caller asked for (Mule: the `DBData` variable).
#
# + connectionKey - Which database account to use
# + operation - `select`, `insert` or `update`, in lower case
# + query - The SQL text, with `:name` where a value goes
# + params - The values, by name
public type DbRequest record {|
    string connectionKey;
    string operation;
    string query;
    map<json> params;
|};

# The database both accounts connect to (Mule: `postgresDB.url`).
#
# + host - Server name
# + port - Server port
# + name - Database name
# + connectTimeoutSeconds - Longest wait for a new connection
# + maxOpenConnections - Most connections per account (Mule pool: 100)
# + minIdleConnections - Connections kept open per account once it is used (Mule pool: 10)
# + allowSeveralStatements - `true` lets one call carry more than one statement (off)
public type DatabaseSettings record {|
    string host = "";
    int port = 5432;
    string name = "";
    decimal connectTimeoutSeconds = 10;
    int maxOpenConnections = 100;
    int minIdleConnections = 10;
    boolean allowSeveralStatements = false;
|};

# One database account.
#
# + username - Login name
# + password - Its password
public type AccountSettings record {|
    string username = "";
    string password = "";
|};

# A statement taken apart at its `:name` places.
#
# + parts - The text around the places; always one more than `names`
# + names - The names, in the order they stand in the text
# + firstWord - First word of the statement, in upper case
# + severalStatements - `true` when text follows a `;`
public type ParsedSql record {|
    string[] parts;
    string[] names;
    string firstWord;
    boolean severalStatements;
|};

# A refusal with the error type and status the old application answered with.
#
# + errorType - Error type identifier of the answer
# + status - HTTP status of the answer
public type RefusalDetail record {|
    string errorType;
    int status;
|};

# Error raised by this module when a call is refused before or after the database.
public type Refusal error<RefusalDetail>;
