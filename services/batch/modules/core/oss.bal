import ballerina/crypto;
import ballerina/http;
import ballerina/lang.array;
import ballerina/time;

// The old oss-implSub_Flow (oss-impl.xml): every page of reservations that is not empty is kept as
// a JSON file in an Alibaba Cloud OSS bucket (old Java OssUploader, aliyun-sdk-oss PutObject).
// Same object name as before: <oss.objectName><yyyyMMddHHmmss>.json.

# OSS settings (old properties `oss.endPoint`, `oss.bucketName`, `oss.accessKeyId`,
# `oss.accessKeySceret`, `oss.objectName`).
#
# + enabled - The old application always uploaded; false only to stop it on purpose
# + url - Bucket address: https://<bucket>.<endpoint>
# + bucket - Bucket name (part of the signature)
# + accessKeyId - Access key id
# + accessKeySecret - Access key secret
# + objectName - Start of the object name
# + timeoutSeconds - Time limit of the upload
public type OssSettings record {|
    boolean enabled = false;
    string url = "";
    string bucket = "";
    string accessKeyId = "";
    string accessKeySecret = "";
    string objectName = "landing-area/seaware_crm_migration-";
    decimal timeoutSeconds = 60;
|};

final readonly & string[] DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
final readonly & string[] MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

isolated function two(int n) returns string => n < 10 ? "0" + n.toString() : n.toString();

# The HTTP date of a moment (RFC 1123, GMT), as OSS expects it.
#
# + at - The moment
# + return - e.g. "Mon, 16 Nov 2026 05:00:00 GMT"
public isolated function httpDate(time:Utc at) returns string {
    time:Civil c = time:utcToCivil(at);
    int dow = c.dayOfWeek ?: 0;
    int sec = <int>(c.second ?: 0d).floor();
    return string `${DAYS[dow]}, ${two(c.day)} ${MONTHS[c.month - 1]} ${c.year} ${two(c.hour)}:${two(c.minute)}:${two(sec)} GMT`;
}

# The object name of an upload at a moment.
#
# + prefix - Start of the name
# + at - The moment
# + return - <prefix><yyyyMMddHHmmss>.json
public isolated function ossObjectName(string prefix, time:Utc at) returns string {
    time:Civil c = time:utcToCivil(at);
    int sec = <int>(c.second ?: 0d).floor();
    return string `${prefix}${c.year}${two(c.month)}${two(c.day)}${two(c.hour)}${two(c.minute)}${two(sec)}.json`;
}

# The OSS signature (version 1) of a PUT.
#
# + secret - Access key secret
# + contentType - Content type sent
# + date - HTTP date sent
# + bucket - Bucket
# + objectName - Object
# + return - Base64 HMAC-SHA1 of the string to sign
public isolated function ossSignature(string secret, string contentType, string date, string bucket, string objectName)
        returns string|error {
    string toSign = "PUT\n\n" + contentType + "\n" + date + "\n/" + bucket + "/" + objectName;
    byte[] mac = check crypto:hmacSha1(toSign.toBytes(), secret.toBytes());
    return array:toBase64(mac);
}

# Uploads pages of reservations to OSS.
public isolated class OssUploader {
    private final OssSettings & readonly settings;
    private final http:Client? ossClient;

    # + settings - OSS settings
    # + return - An error when the client cannot be created
    public isolated function init(OssSettings settings) returns error? {
        self.settings = settings.cloneReadOnly();
        if settings.enabled && settings.url != "" {
            http:Client c = check new (settings.url, {timeout: settings.timeoutSeconds});
            self.ossClient = c;
        } else {
            self.ossClient = ();
        }
    }

    # + return - true when pages are uploaded
    public isolated function active() returns boolean => self.ossClient !is ();

    # Uploads one page. An error stops the run, as in the old application.
    #
    # + edges - The page
    # + correlationId - Run id
    # + return - The object name, "" when uploads are off, or an error
    public isolated function upload(json[] edges, string correlationId) returns string|error {
        http:Client? c = self.ossClient;
        if c is () || edges.length() == 0 {
            return "";
        }
        time:Utc now = time:utcNow();
        string name = ossObjectName(self.settings.objectName, now);
        string date = httpDate(now);
        string contentType = "application/json";
        string sig = check ossSignature(self.settings.accessKeySecret, contentType, date, self.settings.bucket, name);
        http:Request req = new;
        req.setTextPayload(edges.toJsonString(), contentType);
        req.setHeader("Date", date);
        req.setHeader("Authorization", "OSS " + self.settings.accessKeyId + ":" + sig);
        req.setHeader("correlationId", correlationId);
        http:Response res = check c->put("/" + name, req);
        if res.statusCode >= 300 {
            return error(string `OSS refused the upload (HTTP ${res.statusCode})`, errorType = statusType(res.statusCode),
                details = "OSS upload of " + name);
        }
        return name;
    }
}

isolated function statusType(int status) returns string {
    if status == 401 {
        return "UNAUTHORIZED";
    }
    if status == 403 {
        return "FORBIDDEN";
    }
    if status == 404 {
        return "NOT_FOUND";
    }
    if status == 502 {
        return "BAD_GATEWAY";
    }
    if status == 503 {
        return "SERVICE_UNAVAILABLE";
    }
    if status == 504 {
        return "GATEWAY_TIMEOUT";
    }
    return status >= 500 ? "INTERNAL_SERVER_ERROR" : "BAD_REQUEST";
}
