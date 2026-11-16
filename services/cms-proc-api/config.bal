// cms-proc-api: serves CMS descriptions (Jease) — a verbatim pass-through to the CMS.
import aroya/integration_commons as commons;

configurable string env = "vm";
configurable int httpPort = 8081;
configurable string basePath = "/cms-proc-api/v1";
configurable string cmsDescPath = "/jease/ary/descriptions";
configurable commons:DownstreamSettings cms = {url: "https://uat.booking.aroya.com", tlsValidation: false, timeoutSeconds: 40};

// Images of the same Jease CMS (the old flow waited up to 90 seconds for one).
configurable string cmsImagesPath = "/jease/ary/images";
configurable decimal cmsImagesTimeoutSeconds = 90;

// Website content (Strapi). The address and the collection paths are the old application's
// strapi.* properties; they are set in the installed settings file, not here.
configurable commons:DownstreamSettings strapi = {url: "http://localhost", timeoutSeconds: 90};
configurable map<string> strapiPaths = {};

// The old error.httpRetryCount / httpRetryFrequency / httpErrorTypes (count 0 = no repeat).
configurable int httpRetryCount = 0;
configurable decimal httpRetryWaitSeconds = 5;
configurable string[] httpRetryErrorTypes = ["BAD_GATEWAY", "CONNECTIVITY", "TIMEOUT"];

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};
