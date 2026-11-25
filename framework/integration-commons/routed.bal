import ballerina/http;
import ballerina/lang.regexp;

// One shared connection of an old application (Mule "all process APIs": one host, each call adds
// its own base path) that now reaches several separate services. Each call is routed by the start
// of its path: the longest matching prefix wins, the prefix is replaced by the address of the
// service it now lives in, and anything that matches no prefix goes to the shared address as before.

final regexp:RegExp ENV_SUFFIX = re `-(uat|dev|test|sit|qa|stg|stage|preprod|prod)[0-9]*$`;

# The first path segment without its environment ending: "/check-in-proc-api-uat/v1/x" becomes
# "/check-in-proc-api/v1/x". Query strings are kept.
#
# + path - Path of a call (or a route prefix)
# + return - The path with the first segment's environment ending removed
public isolated function normalisePath(string path) returns string {
    string p = path.startsWith("/") ? path : "/" + path;
    int? end = p.indexOf("/", 1);
    int? q = p.indexOf("?", 1);
    int stop = end is int ? end : (q is int ? q : p.length());
    if q is int && q < stop {
        stop = q;
    }
    string first = p.substring(1, stop);
    return "/" + ENV_SUFFIX.replace(first, "") + p.substring(stop);
}

isolated function prefixOf(string key) returns string {
    // a settings key with "/" must be quoted in the file, and Ballerina keeps the quotes in the key
    string k = key.trim();
    if k.length() >= 2 && k.startsWith("\"") && k.endsWith("\"") {
        k = k.substring(1, k.length() - 1);
    }
    string p = normalisePath(k);
    while p.length() > 1 && p.endsWith("/") {
        p = p.substring(0, p.length() - 1);
    }
    return p;
}

# Which route a path takes.
#
# + routes - [prefix, target address] pairs, longest prefix first
# + path - Path of the call
# + return - [target address, path to call there], or () for the shared address
isolated function routeOf(readonly & [string, string][] routes, string path) returns [string, string]? {
    string norm = normalisePath(path);
    foreach [string, string] [prefix, target] in routes {
        if norm == prefix || norm.startsWith(prefix + "/") || norm.startsWith(prefix + "?") {
            string rest = norm.substring(prefix.length());
            return [target, rest == "" ? "/" : rest];
        }
    }
    return ();
}

# A client for a shared connection whose calls are routed by path (see the top of this file).
public isolated client class RoutedClient {
    private final http:Client shared;
    private final readonly & [string, string][] routes;
    private final map<http:Client> clients = {};

    # + settings - The shared connection (its timeouts and TLS settings are used for every route)
    # + routes - Path prefix (old base path; environment endings are ignored) -> address of the
    # service that now answers it, including its base path. Empty addresses are ignored.
    # + return - An error for an invalid address
    public isolated function init(DownstreamSettings settings, map<string> routes = {}) returns http:ClientError? {
        self.shared = check newDownstreamClient(settings);
        [string, string][] list = [];
        foreach [string, string] [key, target] in routes.entries() {
            if target.trim() != "" && key.trim() != "" {
                list.push([prefixOf(key), target.trim()]);
            }
        }
        [string, string][] sorted = from [string, string] r in list order by r[0].length() descending select r;
        self.routes = sorted.cloneReadOnly();
        foreach [string, string] [_, target] in sorted {
            lock {
                if !self.clients.hasKey(target) {
                    self.clients[target] = check newDownstreamClient({
                        url: target,
                        timeoutSeconds: settings.timeoutSeconds,
                        http2: settings.http2,
                        tlsValidation: settings.tlsValidation,
                        caCertPath: settings.caCertPath
                    });
                }
            }
        }
    }

    # Sends a call to wherever its path now lives.
    #
    # + method - HTTP method
    # + path - Path as the old application built it
    # + message - The request
    # + return - The answer, or the client error
    remote isolated function execute(string method, string path, http:Request message) returns http:Response|http:ClientError {
        [string, string]? hit = routeOf(self.routes, path);
        if hit is () {
            return self.shared->execute(method, path, message);
        }
        http:Client? c;
        lock {
            c = self.clients[hit[0]];
        }
        if c is () {
            return self.shared->execute(method, path, message);
        }
        return c->execute(method, hit[1], message);
    }

    # The routes in use, longest prefix first: [prefix, target address]. For start-up logs use only
    # the prefixes; addresses are settings values.
    #
    # + return - The prefixes that are routed
    public isolated function routedPrefixes() returns string[] {
        return from [string, string] r in self.routes select r[0];
    }
}
