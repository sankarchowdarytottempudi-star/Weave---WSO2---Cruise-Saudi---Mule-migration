import ballerinax/redis;

// Same settings shape as seaware_cache_commons:RedisSettings in the Proc API, so all
// services are configured the same way and can share the integration Redis (intg-redis).

# Connection settings for Redis.
#
# + enabled - `false` runs the service without Redis (circuit breaker always closed)
# + host - Redis host, or any node of a Redis Cluster
# + port - Redis port
# + username - ACL user
# + password - Password
# + clusterMode - `true` for a Redis Cluster
# + connectionTimeoutSeconds - Time allowed to connect
public type RedisSettings record {|
    boolean enabled = true;
    string host = "localhost";
    int port = 6379;
    string username?;
    string password?;
    boolean clusterMode = false;
    int connectionTimeoutSeconds = 5;
|};

# Creates a Redis client, or `()` when Redis is switched off.
#
# + settings - Connection settings
# + clientName - Name shown in `CLIENT LIST`
# + return - The client, `()`, or an error if the server cannot be reached
public isolated function newRedisClient(RedisSettings settings, string clientName) returns redis:Client|redis:Error? {
    if !settings.enabled {
        return ();
    }
    redis:ConnectionParams connection = {
        host: settings.host,
        port: settings.port,
        options: {clientName, connectionTimeout: settings.connectionTimeoutSeconds}
    };
    string? username = settings?.username;
    if username is string {
        connection.username = username;
    }
    string? password = settings?.password;
    if password is string {
        connection.password = password;
    }
    redis:Client redisClient = check new ({connection, isClusterConnection: settings.clusterMode});
    return redisClient;
}
