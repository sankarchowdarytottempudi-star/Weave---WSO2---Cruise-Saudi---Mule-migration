// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// error.exception.errorMessage.payload
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatus(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": error.exception.errorMessage.attributes.statusCode,
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatus(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// error.exception.errorMessage.payload
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `kafka` / Kafka Error Message -> set-payload (DataWeave 2.0, 67 lines).
# Output fields: session_id, auth_token, mule_correlation_id, step_name, source_api, target_system, request_method, endpoint_url, graphql_operation_name, correlationId, operationType, operationName, clientIp, authorization, request_payload, response_status_code, response_payload, response_headers, status, replayable.
#
# + input - The source payload
# + return - The mapped value
public isolated function kafkaKafkaErrorMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// 
// var ogp = do {
//     var bodyPayload = vars.OGPayload default vars.originalRequestPayload default {}
//     ---
//     if (!isEmpty(bodyPayload)) bodyPayload
//     else if (!isEmpty(attributes.queryParams default {})) attributes.queryParams
//     else if (!isEmpty(attributes.uriParams default {})) attributes.uriParams
//     else {}
// }
// var respPayload = payload default {}
// var opName = vars.operationName
//              default attributes.headers.'x-operation-name'
//              default attributes.headers.'x-Operation-Name'
//              default "UNKNOWN"
// 
// var resolvedUrl = vars.targetUrl default attributes.maskedRequestPath default "UNKNOWN"
// 
// var resolvedTarget = vars.targetApiName
//                      default attributes.headers.'x-target-system'
//                      default (
//                          if (resolvedUrl != "UNKNOWN")
//                              (resolvedUrl splitBy "/")[1] default "UNKNOWN"
//                          else "UNKNOWN"
//                      )
// 
// var authHeader =
//     do {
//         var rawToken = vars.authToken default ""
//         var token = if (rawToken startsWith "Bearer ")
//                 rawToken[7 to -1]
//             else rawToken
//         ---
//         if (isEmpty(token)) "UNKNOWN" else token
//     }
// 
// ---
// {
//     session_id:               authHeader,
//     auth_token:               authHeader,
//     mule_correlation_id:      vars.correlationId default "UNKNOWN",
//     step_name:                opName,
//     source_api:               "mobile-exp-api",
//     target_system:            resolvedTarget,
//     request_method:           attributes.method default "POST",
//     endpoint_url:             resolvedUrl,
//     graphql_operation_name:   opName,
//     request_headers: {
//         correlationId:  vars.correlationId default "UNKNOWN",
//         operationType:  attributes.headers.'x-operation-type' default "UNKNOWN",
//         operationName:  opName,
//         clientIp:       attributes.headers.'x-forwarded-for' default "UNKNOWN",
//         authorization:  "MASKED"
//     },
//     request_payload:          ogp,
//     response_status_code: (error.exception.errorMessage.attributes.statusCode
//                            default vars.httpStatus
//                            default 500) as Number,
//     response_payload:         respPayload,
//     response_headers:         {},
//     status:                   "FAILED",
//     replayable:               false,
//     retry_count:              0,
//     error_message:            error.description default "UNKNOWN ERROR",
//     created_at:               now()
// }
    return input;
}

# Source: `savepayload` / Kafka Audit Message -> set-payload (DataWeave 2.0, 66 lines).
# Output fields: session_id, auth_token, mule_correlation_id, step_name, source_api, target_system, request_method, endpoint_url, graphql_operation_name, correlationId, operationType, operationName, clientIp, authorization, request_payload, response_status_code, response_headers, response_payload, status, replayable.
#
# + input - The source payload
# + return - The mapped value
public isolated function savepayloadKafkaAuditMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// 
// var ogp = do {
//     var bodyPayload = vars.OGPayload default vars.originalRequestPayload default {}
//     ---
//     if (!isEmpty(bodyPayload)) bodyPayload
//     else if (!isEmpty(attributes.queryParams default {})) attributes.queryParams
//     else if (!isEmpty(attributes.uriParams default {})) attributes.uriParams
//     else {}
// }
// var respPayload = payload default {}
// 
// var opName = vars.operationName
//              default attributes.headers.'x-operation-name'
//              default attributes.headers.'x-Operation-Name'
//              default "UNKNOWN"
// 
// var resolvedUrl = vars.targetUrl default attributes.maskedRequestPath default "UNKNOWN"
// 
// var resolvedTarget = vars.targetApiName
//                      default attributes.headers.'x-target-system'
//                      default (
//                          if (resolvedUrl != "UNKNOWN")
//                              (resolvedUrl splitBy "/")[1] default "UNKNOWN"
//                          else "UNKNOWN"
//                      )
// 
// var authHeader =
//     do {
//         var rawToken = vars.authToken default ""
//         var token = if (rawToken startsWith "Bearer ")
//                 rawToken[7 to -1]
//             else rawToken
//         ---
//         if (isEmpty(token)) "UNKNOWN" else token
//     }
// 
// ---
// {
//     session_id:               authHeader,
//     auth_token:               authHeader,
//     mule_correlation_id:      vars.correlationId default "UNKNOWN",
//     step_name:                opName,
//     source_api:               "mobile-exp-api",
//     target_system:            resolvedTarget,
//     request_method:           attributes.method default "POST",
//     endpoint_url:             resolvedUrl,
//     graphql_operation_name:   opName,
//     request_headers: {
//         correlationId:  vars.correlationId default "UNKNOWN",
//         operationType:  attributes.headers.'x-operation-type' default "UNKNOWN",
//         operationName:  opName,
//         clientIp:       attributes.headers.'x-forwarded-for' default "UNKNOWN",
//         authorization:  "MASKED"
//     },
//     request_payload:          ogp,
//     response_status_code:     vars.httpStatus default 200,
//     response_headers:         {},
//     response_payload:         respPayload,
//     status:                   "SUCCESS",
//     replayable:               false,
//     retry_count:              0,
//     error_message:            null,
//     created_at:               now()
// }
    return input;
}

# Source: `http-error-retrySub_Flow` / Transform Message -> httpRetryCount (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function httpErrorRetrySubFlowTransformMessageHttpRetryCount(json input) returns json {
// %dw 2.0
// output application/java
// var retryCount = p('error.httpRetryCount')
// ---
// (vars.httpRetryCount default retryCount) - 1
    return input;
}

# Source: `http-error-retrySub_Flow` / Transform Message -> sleep (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function httpErrorRetrySubFlowTransformMessageSleep(json input) returns json {
// %dw 2.0
// import wait from dw::Runtime
// output application/java
// ---
// wait(payload, p('error.httpRetryFrequency') as Number)
    return input;
}

# Source: `mobile-exp-api-exceptionSub_Flow` / Initialize errorMessage -> errorMessage (DataWeave 2.0, 7 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiExceptionSubFlowInitializeErrorMessageErrorMessa(json input) returns json {
// %dw 2.0
// output application/java
// ---
// if ((vars.errorMessage default null) == null) 
//     error
// else 
//     vars.errorMessage
    return input;
}

# Source: `mobile-exp-api-exceptionSub_Flow` / Prepare Email Message -> set-payload (DataWeave 2.0, 48 lines).
# Output fields: subject, importance, contentType, content, toRecipients, address, ccRecipients, address.
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiExceptionSubFlowPrepareEmailMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// var component = error.failingComponent default ""
// var afterAt = (component splitBy "@")[1] default ""
// var apiName = (afterAt splitBy ":")[0] default "N/A"
// var errorType = vars.errorMessage.errorType.identifier default "N/A"
// var description = vars.errorMessage.description default "N/A"
// var details = error.exception.errorMessage.payload default "N/A"
// var detailsAsString =
//     if (details is String) details
//     else if (details is Object) write(details, "application/json")
//     else details as String
// 
// var importanceLevel =
//     if (errorType == "BAD_GATEWAY" or errorType == "INTERNAL_SERVER_ERROR" or errorType == "SERVICE_UNAVAILABLE" or errorType == "CONNECTIVITY") "High"
//     else if (errorType == "RETRY_EXHAUSTED" or errorType == "TIMEOUT") "Low"
//     else "Low"
// 
// var subjectLine = if (importanceLevel == "High") "⚠️ " ++ apiName else apiName
// ---
// {
//   message: {
//     subject: subjectLine,
//     importance: importanceLevel,
//     body: {
//       contentType: "HTML",
//       content:
//         "<b>Error type :</b> " ++ errorType ++
//         "<br/><b>Description :</b> " ++ description ++
//         "<br/><b>Details :</b> " ++ detailsAsString ++
//         "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information, please refer to the MuleSoft application logs or contact the support team.</span>"
//     },
//     toRecipients: [
//       {
//         emailAddress: {
//           address: p('email.toAddress')
//         }
//       }
//     ],
//     ccRecipients: [
//       {
//         emailAddress: {
//           address: p('email.ccAddress')
//         }
//       }
//     ]
//   }
// }
    return input;
}

# Source: `mobile-exp-api-main` / login headers -> firstName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainLoginHeadersFirstName(json input) returns json {
// %dw 2.0
// output application/java
// ---
// attributes.headers.first_name default null
    return input;
}

# Source: `mobile-exp-api-main` / login headers -> lastName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainLoginHeadersLastName(json input) returns json {
// %dw 2.0
// output application/java
// ---
// attributes.headers.last_name default null
    return input;
}

# Source: `mobile-exp-api-main` / login headers -> method (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainLoginHeadersMethod(json input) returns json {
// %dw 2.0
// output application/java
// ---
// attributes.headers.method default null
    return input;
}

# Source: `mobile-exp-api-main` / login headers -> clientDeviceId (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainLoginHeadersClientDeviceId(json input) returns json {
// %dw 2.0
// output application/java
// ---
// attributes.headers.client_deviceId default null
    return input;
}

# Source: `mobile-exp-api-main` / login headers -> clientChannel (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainLoginHeadersClientChannel(json input) returns json {
// %dw 2.0
// output application/java
// ---
// attributes.headers.client_channel default null
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Bad request"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatus(json input) returns json {
// 400
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayloadX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatusX(json input) returns json {
// 404
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayloadXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Method not allowed"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatusXX(json input) returns json {
// 405
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayloadXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not acceptable"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatusXXX(json input) returns json {
// 406
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayloadXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Unsupported media type"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatusXXXX(json input) returns json {
// 415
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageSetPayloadXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not Implemented"}
    return input;
}

# Source: `mobile-exp-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiMainTransformMessageHttpStatusXXXXX(json input) returns json {
// 501
    return input;
}

# Source: `mobile-exp-api-console` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiConsoleTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `mobile-exp-api-console` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileExpApiConsoleTransformMessageHttpStatus(json input) returns json {
// 404
    return input;
}

# Source: `mobileBackendInfo-implementationSub_Flow` / mobile backend payload -> nodejsPayload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileBackendInfoImplementationSubFlowMobileBackendPayloadNo(json input) returns json {
// %dw 2.0
// output application/json
// ---
// payload
    return input;
}

# Source: `mobileBackendInfo-implementationSub_Flow` / Transform Message -> set-payload (DataWeave 2.0, 8 lines).
# Output fields: connectionKey, operation, query.
#
# + input - The source payload
# + return - The mapped value
public isolated function mobileBackendInfoImplementationSubFlowTransformMessageSetPay(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {
//     connectionKey: "PG_Guest",
//     operation: "insert",
//     query: "INSERT INTO cs_guest_mgmt.cs_guest_device (fcm_token, device_id, device_model, manufacturer, os_type, os_version, app_version, ip_address, network_type, carrier_name, screen_resolution, locale, time_zone, is_emulator, created_by) VALUES ('" ++ (payload.fcm_token default "") ++ "', '" ++ (payload.device_id default "") ++ "', '" ++ (payload.device_model default "") ++ "', '" ++ (payload.manufacturer default "") ++ "', '" ++ (payload.os_type default "") ++ "', '" ++ (payload.os_version default "") ++ "', '" ++ (payload.app_version default "") ++ "', '" ++ (payload.ip_address default "") ++ "', '" ++ (payload.network_type default "") ++ "', '" ++ (payload.carrier_name default "") ++ "', '" ++ (payload.screen_resolution default "") ++ "', '" ++ (payload.locale default "") ++ "', '" ++ (payload.time_zone default "") ++ "', " ++ (payload.is_emulator default false) ++ ", 'system') ON CONFLICT (device_id) DO UPDATE SET fcm_token = EXCLUDED.fcm_token, device_model = EXCLUDED.device_model, manufacturer = EXCLUDED.manufacturer, os_type = EXCLUDED.os_type, os_version = EXCLUDED.os_version, app_version = EXCLUDED.app_version, ip_address = EXCLUDED.ip_address, network_type = EXCLUDED.network_type, carrier_name = EXCLUDED.carrier_name, screen_resolution = EXCLUDED.screen_resolution, locale = EXCLUDED.locale, time_zone = EXCLUDED.time_zone, is_emulator = EXCLUDED.is_emulator, updated_date = now(), updated_by = 'system'"
// }
    return input;
}

# Source: `person-profile-getPerson-search-api-implementationSub_Flow` / profileId -> set-payload (DataWeave 2.0, 37 lines).
# Output fields: profileId, seaware_client_id, first_name, last_name, email, phone, client_deviceId, client_channel.
#
# + input - The source payload
# + return - The mapped value
public isolated function personProfileGetPersonSearchApiImplementationSubFlowProfileI(json input) returns json {
// %dw 2.0
// output application/json
// 
// var matchedGuest =
//     (
//         vars.ogPayload.responsePayload.content default []
//     )
//     filter (
//         upper($.firstName default "") == upper(vars.firstName default "")
//         and
//         upper($.lastName default "") == upper(vars.lastName default "")
//     )
// 
// var guest = matchedGuest[0] default {}
// var communications = guest.communicationInfos default []
// 
// ---
// {
//     profileId: guest.profileId default null,
//     seaware_client_id: ((guest.externalId default "") splitBy "-")[-1] default null,
//     first_name: guest.firstName default null,
//     last_name: guest.lastName default null,
//     email:
//         (
//             communications filter (
//                 $.communicationType.code == "EMAIL-HOME"
//             )
//         )[0].recordValue default null,
//     phone:
//         (
//             communications filter (
//                 $.communicationType.code == "MOBILE-PRIVATE"
//             )
//         )[0].recordValue default null,
//     client_deviceId: vars.clientDeviceId default null,
//     client_channel: vars.clientChannel default null
// }
    return input;
}
