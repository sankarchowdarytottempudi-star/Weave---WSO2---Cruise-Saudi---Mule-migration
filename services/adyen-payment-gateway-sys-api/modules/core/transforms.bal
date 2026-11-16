// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPay(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Bad request"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpSt(json input) returns json {
// 400
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPayX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpStX(json input) returns json {
// 404
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPayXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Method not allowed"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpStXX(json input) returns json {
// 405
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPayXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not acceptable"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpStXXX(json input) returns json {
// 406
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPayXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Unsupported media type"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpStXXXX(json input) returns json {
// 415
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageSetPayXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not Implemented"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceMainTransformMessageHttpStXXXXX(json input) returns json {
// 501
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-console` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceConsoleTransformMessageSet(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `adyen-payment-gateway-sys-api-interface-console` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function adyenPaymentGatewaySysApiInterfaceConsoleTransformMessageHtt(json input) returns json {
// 404
    return input;
}

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
//     "responseCode": "FEIGN_CLIENT",
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

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 405
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 406
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 404
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 500
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 503
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 408
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": "FEIGN_CLIENT",
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode default 401
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, responsePayload, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayloadXXXXXXXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": error.detailedDescription,
//     "responseCode": vars.httpStatus,
//     "responsePayload": error.message.payload,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatusXXXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details  -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayloadXXXXXXXXXXXXX(json input) returns json {
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
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatusXXXXXXXXXXXXX(json input) returns json {
// error.exception.errorMessage.attributes.statusCode
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
