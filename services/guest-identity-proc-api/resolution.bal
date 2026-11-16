// Guest Identity Resolution ingress (plan v2.1 section 14.1). Runs only with
// identityResolution.enabled = true; with the flag off resolutionApplies is always false.

import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/uuid;

import aroya/integration_commons as commons;

final http:Client identityIntegrationClient = check commons:newDownstreamClient(identityResolution.integration);

# Whether the guest goes through Guest Identity Resolution instead of the inline ID generation.
isolated function resolutionApplies(map<json> guest) returns boolean =>
    identityResolution.enabled && core:inResolutionScope(guest, identityResolution.sourceCodeField,
        identityResolution.agencyNameField, identityResolution.sourceCodes, identityResolution.agencyNames);

isolated function pendingContact(map<json> guest, map<json> contact) returns map<json> =>
    core:pendingContactOf(contact, identityResolution.sourceSystem,
        core:textOf(guest[identityResolution.sourceCodeField]).trim(), identityResolution.sourceCodeCrmField);

# Hands the guest's snapshot to the identity integration service, which publishes the evaluation
# event. A failure leaves the contact PENDING_IDENTITY; the nightly reconciliation republishes it.
isolated function requestEvaluation(map<json> & readonly guest, map<json> & readonly contact, json & readonly answer,
        string correlationId) {
    map<json>? event = core:evaluationEventOf(guest, contact, answer, identityResolution.sourceSystem,
            core:textOf(guest[identityResolution.sourceCodeField]).trim(),
            core:textOf(guest[identityResolution.agencyNameField]).trim(), correlationId, uuid:createType4AsString());
    if event is () {
        log:printWarn("Identity evaluation not requested: the CRM answer has no record id or Modified_Time",
                correlationId = correlationId);
        return;
    }
    map<string> headers = {"X-Webhook-Token": identityResolution.ingressToken, "X-Correlation-Id": correlationId};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response|http:ClientError sent = identityIntegrationClient->post(identityResolution.ingressPath, event, headers);
    if sent is http:ClientError || sent.statusCode >= 300 {
        log:printWarn("Identity evaluation not requested now; the reconciliation republishes the pending guest",
                correlationId = correlationId, status = sent is http:Response ? sent.statusCode : 0);
        return;
    }
    log:printInfo("Identity evaluation requested", correlationId = correlationId);
}
