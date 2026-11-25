import ballerina/http;
import ballerina/log;

// HTTP clients for downstream calls, replacing the http:request-config blocks.
// Differences from Mule, on purpose:
//   - TLS certificate validation is ON unless configuration switches it off (seaware-sys-api
//     had <tls:trust-store insecure="true"/> in every environment);
//   - the client never retries on its own; retries go through RetryPolicy so payment
//     operations are never repeated.

# A downstream endpoint.
#
# + url - Base URL, for example `https://int-api.aroyacruises.com`
# + timeoutSeconds - Response timeout (Mule `responseTimeout` / 1000)
# + http2 - Use HTTP/2 when the server offers it (Mule `http2-support`)
# + tlsValidation - Validate the server certificate. Switch off only for a known self-signed test host
# + caCertPath - PEM file of a private CA to trust, if the server uses one
public type DownstreamSettings record {|
    string url;
    decimal timeoutSeconds = 30;
    boolean http2 = false;
    boolean tlsValidation = true;
    string caCertPath = "";
|};

# Creates the client for a downstream.
#
# + settings - Endpoint settings
# + return - The client, or an error for an invalid URL
public isolated function newDownstreamClient(DownstreamSettings settings) returns http:Client|http:ClientError {
    http:ClientConfiguration config = {
        timeout: settings.timeoutSeconds,
        httpVersion: settings.http2 ? http:HTTP_2_0 : http:HTTP_1_1
    };
    if settings.url.startsWith("https") {
        if !settings.tlsValidation {
            log:printWarn("TLS certificate validation is disabled by configuration", url = settings.url);
            config.secureSocket = {enable: false};
        } else if settings.caCertPath != "" {
            config.secureSocket = {cert: settings.caCertPath};
        }
    }
    return new (settings.url, config);
}
