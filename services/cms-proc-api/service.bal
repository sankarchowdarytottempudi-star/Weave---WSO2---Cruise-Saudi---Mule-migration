// cms-proc-api on WSO2 (Ballerina). The seven operations of the old CMS application:
//   GET {basePath}/descriptions/{type}                                -> Jease, answer returned verbatim
//   GET {basePath}/images/{type}/{code}                               -> Jease image
//   GET {basePath}/images/{type}/{ship}/{code}                        -> Jease image
//   GET {basePath}/cms/content                                        -> Strapi
//   GET {basePath}/cms/content/{slug}                                 -> Strapi
//   GET {basePath}/cms/content/{slug}/categories                      -> Strapi
//   GET {basePath}/cms/content/{slug}/categories/{categoryType}       -> Strapi
// No auth of its own (the old application had none; the gateway in front asks for the OAuth key).
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;
import aroya/cms_proc_api.core;

final http:Client cmsClient = check commons:newDownstreamClient(cms);
final http:Client cmsImagesClient = check newClient(cms, cmsImagesTimeoutSeconds);
final http:Client strapiClient = check newClient(strapi, strapi.timeoutSeconds);

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(cmsService, basePath);
    string[] unset = from string name in core:PATH_KEYS where !strapiPaths.hasKey(name) select name;
    if unset.length() > 0 {
        log:printWarn("Strapi path settings without a value; requests that need them answer 500", names = unset);
    }
    log:printInfo("cms-proc-api starting", env = env, basePath = basePath, cms = cms.url, strapi = strapi.url,
            contentCache = contentCacheState());
}

// Same connection rules as commons:newDownstreamClient, and redirects are followed as the old
// application's HTTP requests did.
isolated function newClient(commons:DownstreamSettings settings, decimal timeoutSeconds) returns http:Client|http:ClientError {
    http:ClientConfiguration config = {
        timeout: timeoutSeconds,
        httpVersion: settings.http2 ? http:HTTP_2_0 : http:HTTP_1_1,
        followRedirects: {enabled: true}
    };
    if settings.url.startsWith("https") {
        if !settings.tlsValidation {
            config.secureSocket = {enable: false};
        } else if settings.caCertPath != "" {
            config.secureSocket = {cert: settings.caCertPath};
        }
    }
    return new (settings.url, config);
}

final commons:AuditSink errorRecordSink = errorRecordSinkOf();

function errorRecordSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    return sink is commons:AuditSink ? sink : new commons:NoopAuditSink();
}

isolated service class ErrorRecordedApi {
    *http:InterceptableService;

    // Mule global error handler: every failed call goes to kafka.errorTopic as
    // [saved payload, {"errorMessage": error body}] (off unless switched on in the settings)
    public function createInterceptors() returns http:Interceptor[] => commons:errorRecordInterceptors(errorRecordSink);


    // GET {basePath}/descriptions/{type}  ->  Jease CMS, returned as-is (same body, same type).
    isolated resource function get descriptions/[string descType](http:Request req) returns http:Response {
        // Mule: an error goes to Global_Error_Handler - the CMS's own status and body, or 500 with the
        // old error body when the CMS cannot be reached (was 502 with a body of its own here)
        final string address = cmsDescPath + "/" + descType;
        return cachedRelay("d:" + address, isolated function() returns http:Response|http:ClientError {
                    return cmsClient->get(address);
                },
                commons:correlationIdOf(req), "The CMS source");
    }

    // GET {basePath}/images/{type}/{code}  ->  Jease images/{type}/{code}
    isolated resource function get images/[string imgType]/[string code](http:Request req) returns http:Response {
        http:Response|http:ClientError r = cmsImagesClient->get(cmsImagesPath + "/" + segment(imgType) + "/" + segment(code));
        return relay(r, commons:correlationIdOf(req), "The image source");
    }

    // GET {basePath}/images/{type}/{ship}/{code}  ->  Jease images/{type}/{ship}_{code}
    isolated resource function get images/[string imgType]/[string ship]/[string code](http:Request req) returns http:Response {
        http:Response|http:ClientError r = cmsImagesClient->get(cmsImagesPath + "/" + segment(imgType) + "/"
            + segment(ship + "_" + code));
        return relay(r, commons:correlationIdOf(req), "The image source");
    }

    isolated resource function get cms/content(http:Request req) returns http:Response => content(req, "", ());

    isolated resource function get cms/content/[string slug](http:Request req) returns http:Response =>
        content(req, slug, ());

    isolated resource function get cms/content/[string slug]/categories(http:Request req) returns http:Response =>
        content(req, slug, ());

    isolated resource function get cms/content/[string slug]/categories/[string categoryType](http:Request req)
            returns http:Response => content(req, slug, categoryType);

    // Anything else: the answers the old application's router gave.
    isolated resource function 'default [string... parts](http:Request req) returns http:Response {
        http:Response out = new;
        if req.method != "GET" && isOperation(parts) {
            out.statusCode = 405;
            out.setJsonPayload({message: "Method not allowed"});
        } else {
            out.statusCode = 404;
            out.setJsonPayload({message: "Resource not found"});
        }
        return out;
    }
}

final ErrorRecordedApi cmsService = new;

isolated function isOperation(string[] parts) returns boolean {
    int n = parts.length();
    if n == 0 {
        return false;
    }
    if parts[0] == "descriptions" {
        return n == 2;
    }
    if parts[0] == "images" {
        return n == 3 || n == 4;
    }
    if parts[0] == "cms" && n >= 2 && parts[1] == "content" {
        return n == 2 || n == 3 || (n == 4 && parts[3] == "categories") || (n == 5 && parts[3] == "categories");
    }
    return false;
}

// One path part, safe to put into the address of the image source.
isolated function segment(string text) returns string {
    string encoded = core:encodeUri(text);
    encoded = re `/`.replaceAll(encoded, "%2F");
    encoded = re `\?`.replaceAll(encoded, "%3F");
    return re `#`.replaceAll(encoded, "%23");
}

// A content request: the slug decides which Strapi collection is read and with which query.
isolated function content(http:Request req, string slug, string? categoryType) returns http:Response {
    string correlationId = commons:correlationIdOf(req);
    string raw = req.rawPath;
    int? mark = raw.indexOf("?");
    string path = mark is int ? raw.substring(0, mark) : raw;
    string rawQuery = mark is int ? raw.substring(mark + 1) : "";
    map<string> params = core:firstParams(rawQuery);
    core:Target target = core:contentTarget(slug, categoryType, path, rawQuery, params);
    string? collection = strapiPaths[target.pathKey];
    if collection is () {
        log:printError("Strapi path setting has no value", correlationId = correlationId, name = target.pathKey);
        http:Response out = new;
        out.statusCode = 500;
        out.setJsonPayload({
            messageType: "CONFIGURATION",
            message: "The setting strapiPaths." + target.pathKey + " has no value on this server",
            responseCode: (),
            responsePayload: (),
            errorDoesNotExist: false
        });
        return out;
    }
    final string address = target.query == "" ? collection : collection + "?" + target.query;
    return cachedRelay("c:" + address, isolated function() returns http:Response|http:ClientError => fetch(address),
            correlationId, "The content source");
}

// One GET to Strapi. Repeated only when a retry count is set and the failure is one of the
// listed kinds (the old application's error.httpRetryCount, 0 in every environment of the upload).
isolated function fetch(string address) returns http:Response|http:ClientError {
    int left = httpRetryCount;
    while true {
        http:Response|http:ClientError r = strapiClient->get(address);
        string kind = "";
        if r is http:ClientError {
            kind = commons:errorTypeOfClientError(r);
        } else if r.statusCode >= 400 {
            kind = commons:errorTypeOfStatus(r.statusCode);
        }
        if kind == "" || left <= 0 || httpRetryErrorTypes.indexOf(kind) is () {
            return r;
        }
        left -= 1;
        runtime:sleep(httpRetryWaitSeconds);
    }
}

// The caller's answer, as the old application gave it:
//   backend answered 2xx  -> 200, the backend's body and content type, unchanged
//   backend answered else -> the backend's status and body
//   backend not reached   -> 500 with the old error body
isolated function relay(http:Response|http:ClientError r, string correlationId, string backend) returns http:Response {
    http:Response out = new;
    if r is http:ClientError {
        string kind = commons:errorTypeOfClientError(r);
        log:printError(backend + " did not answer", correlationId = correlationId, errorType = kind, 'error = r);
        mailError(kind, backend + (kind == "TIMEOUT" ? " did not answer in time" : " could not be reached"), r.message(),
                correlationId);
        out.statusCode = 500;
        out.setJsonPayload({
            messageType: kind,
            message: backend + (kind == "TIMEOUT" ? " did not answer in time" : " could not be reached"),
            responseCode: (),
            responsePayload: (),
            errorDoesNotExist: false
        });
        return out;
    }
    byte[]|http:ClientError body = r.getBinaryPayload();
    byte[] bytes = body is byte[] ? body : [];
    string|http:HeaderNotFoundError sent = r.getHeader("content-type");
    string contentType = sent is string ? sent : "";
    boolean ok = r.statusCode >= 200 && r.statusCode < 300;
    out.statusCode = ok ? 200 : r.statusCode;
    if bytes.length() > 0 {
        out.setBinaryPayload(bytes);
        // the backend's own content type, letter for letter
        out.setHeader("content-type", contentType == "" ? "application/octet-stream" : contentType);
    } else if !ok {
        out.setJsonPayload({
            messageType: commons:errorTypeOfStatus(r.statusCode),
            message: backend + " answered " + r.statusCode.toString(),
            responseCode: r.statusCode,
            responsePayload: (),
            errorDoesNotExist: false
        });
    }
    if !ok {
        log:printWarn(backend + " answered with an error", correlationId = correlationId, status = r.statusCode);
        string|error text = string:fromBytes(bytes);
        mailError(commons:errorTypeOfStatus(r.statusCode), backend + " answered " + r.statusCode.toString(),
                text is string ? text : "", correlationId);
    }
    return out;
}

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};
    isolated resource function get ready() returns json => {status: "UP"};
}
