// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `accessTokenSub_Flow` / Login details -> set-payload (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function accessTokenSubFlowLoginDetailsSetPayload(json input) returns json {
// %dw 2.0
// output application/json
//  
// ---
// {   "query": "mutation Login { login(role: Internal, totalTimeout: \"PT12H\", inactivityTimeout: \"PT12H\") { sessionGUID role username sourceCode versionInfo expiration { timeout inactivityTimeout expires autoExtend } objects { isLocked lockInfo { timeout inactivityTimeout expires autoExtend lockedBy lockedByMe } } token }} " }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> set-payload (DataWeave 2.0, 18 lines).
# Output fields: timestamp, statusCode, message, correlationId, error, targetError.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {
// 	timestamp: now(),
// 	statusCode: if ( error.errorType.identifier == "BAD_REQUEST" ) 400
//         else if ( error.errorType.identifier == "UNAUTHORIZED" ) 401
//         else if ( error.errorType.identifier == "INVALID_REQUEST" ) 400
//         else if ( error.errorType.identifier == "INVALID_CONNECTION_KEY" ) 400
//         else if ( error.errorType.identifier == "SYNTAX_ERROR" ) 400
//         else if ( error.errorType.identifier == "EMPTY_RESPONSE" ) 404
// 		 else if ( error.errorType.identifier == "VALIDATION_ERROR" ) 406
//         else error.exception.errorMessage.attributes.statusCode default 500,
// 	message: error.exception.errorMessage.payload.message default error.description,
// 	correlationId: vars.correlationId  default attributes.correlationId default "UNKNOWN",
// 	error: error.errorType.identifier,
// 	targetError: error.exception.errorMessage.payload default  error.detailedDescription,
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Custom Error variable -> httpStatus (DataWeave 2.0, 6 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetCustomErrorVariableHttpStatus(json input) returns json {
// if (error.errorType.identifier == "REQUEST") 400
// else if (error.errorType.identifier == "INVALID_CONNECTION_KEY") 400
// else if (error.errorType.identifier == "BAD_REQUEST") 400
// else if (error.errorType.identifier == "UNAUTHORIZED") 401
// else if (error.errorType.identifier == "INVALID_REQUEST") 400
// else error.exception.errorMessage.attributes.statusCode default 500
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details -> set-payload (DataWeave 2.0, 11 lines).
# Output fields: messageType, message, responseCode, errorDoesNotExist.
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {
//     "messageType": error.errorType.identifier,
//     "message": if (error.description != null) error.description else error.detailedDescription,
//     "responseCode": if (error.errorType.identifier == "BAD_REQUEST") 400
//                     else if (error.errorType.identifier == "INVALID_CONNECTION_KEY") 400
//                     else error.exception.errorMessage.attributes.statusCode default 500,
//     "errorDoesNotExist": false
// }
    return input;
}

# Source: `Global_Error_Handler` / Set Variable Error Details -> httpStatus (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function globalErrorHandlerSetVariableErrorDetailsHttpStatus(json input) returns json {
// if (error.errorType.identifier == "REQUEST") 400
// else if (error.errorType.identifier == "INVALID_CONNECTION_KEY") 400
// else if (error.errorType.identifier == "BAD_REQUEST") 400
// else error.exception.errorMessage.attributes.statusCode default 500
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

# Source: `unauthorized-error-retrySub_Flow` / Transform Message -> unauthorizedRetryCount (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function unauthorizedErrorRetrySubFlowTransformMessageUnauthorizedRet(json input) returns json {
// %dw 2.0
// output application/java
// var retryCount = p('error.unauthorizedRetryCount')
// ---
// (vars.unauthorizedRetryCount default retryCount) - 1
    return input;
}

# Source: `httpRequest_AccessToken_Sub_Flow` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function httpRequestAccessTokenSubFlowTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// error.errorMessage.payload
    return input;
}

# Source: `httpRequest_cache_proc_Sub_Flow` / Transform Message -> set-payload (DataWeave 2.0, 9 lines).
# Output fields: status, errorMessage.
#
# + input - The source payload
# + return - The mapped value
public isolated function httpRequestCacheProcSubFlowTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {
// 	
// 		"status": "error",
// 		"errorMessage": error.detailedDescription
// 	
// }
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> guestCount (DataWeave 2.0, 18 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageGuestCount(json input) returns json {
// %dw 2.0
// output application/json
// 
// var queryString = vars.inputPayload.query default ""
// var payloadVars = vars.inputPayload.variables default {}
// 
// // ---------- Extract guest count ----------
// var guestCount =
//     if (payloadVars.guests? and !isEmpty(payloadVars.guests))
//         sizeOf(payloadVars.guests)
//     else do {
//         var matches = queryString scan /seqN\s*:\s*\d+/
//         ---
//         sizeOf(matches)
//     }
// 
// ---
// guestCount
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> operationName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageOperationName(json input) returns json {
// %dw 2.0
// output application/json
// ---
// "availableVoyages"
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> set-payload (DataWeave 2.0, 103 lines).
# Output fields: availableVoyages.
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// var queryString = vars.inputPayload.query default ""
// var queryVariable = vars.inputPayload.variables default ""
// 
// fun extractPackageTypesArr(query) = do {
//   var blockMatch = query scan (/packageTypes\s*:\s*(\{[\s\S]*?\}|\[[\s\S]*?\])/)
//   var block = if (!isEmpty(blockMatch))
//     blockMatch[0][1]
//   else
//     ""
//   var keys = block scan (/key\s*:\s*"([^"]+)"/)
//   ---
//   if (isEmpty(keys))
//     []
//   else
//     keys map (k) -> upper(k[1])
// }
// 
// fun extractPackage(query) = do {
//   var m = query scan (/packages:\s*\{\s*key:\s*"([^"]+)"/)
//   ---
//   if (!isEmpty(m))
//     upper(m[0][1])
//   else
//     null
// }
// 
// fun extractDestinationsArr(query) = do {
//   var blockMatch = query scan (/destinations\s*:\s*(\[[\s\S]*?\]|\{[\s\S]*?\})/)
//   var block = if (!isEmpty(blockMatch))
//     blockMatch[0][1]
//   else
//     ""
//   var keys = block scan (/key\s*:\s*"([^"]+)"/)
//   ---
//   if (isEmpty(keys))
//     []
//   else
//     keys map (k) -> upper(k[1])
// }
// 
// fun extractDeparturePortsArr(query) = do {
//   var blockMatch = query scan (/departurePorts\s*:\s*(\[[\s\S]*?\]|\{[\s\S]*?\})/)
//   var block = if (!isEmpty(blockMatch))
//     blockMatch[0][1]
//   else
//     ""
//   var keys = block scan (/key\s*:\s*"([^"]+)"/)
//   ---
//   if (isEmpty(keys))
//     []
//   else
//     keys map (k) -> upper(k[1])
// }
// var destinationsArr = if(!isEmpty(queryVariable)) queryVariable.destination.key else extractDestinationsArr(queryString)
// var departurePortsArr = if(!isEmpty(queryVariable)) queryVariable.depraturePort.key else extractDeparturePortsArr(queryString)
// var fromMatch = queryString scan /from:\s*"([^"]+)"/
// var toMatch = queryString scan /to:\s*"([^"]+)"/
// var fromDate = if(!isEmpty(queryVariable)) queryVariable.startDateRange.from else if (!isEmpty(fromMatch)) fromMatch[0][1] as Date {format: "yyyy-MM-dd"} else  null
// var toDate = if(!isEmpty(queryVariable)) queryVariable.startDateRange.to else if (!isEmpty(toMatch)) toMatch[0][1] as Date {format: "yyyy-MM-dd"} else  null
// var pakageType = if(!isEmpty(queryVariable)) queryVariable.packageType.key else extractPackageTypesArr(queryString) 
// var packageId = if(!isEmpty(queryVariable)) queryVariable.packages.key else extractPackage(queryString)
// // --------------------------------------------------
// // FINAL FILTER
// // --------------------------------------------------
// var filteredVoyages = 
// (payload.data.availableVoyages default []) filter (v) ->
//         (
//             packageId == null or (v.pkg.key? and (packageId contains upper(v.pkg.key)))
//         )
//         and
//         (
//             fromDate == null
//             or (v.sail.from.dateTime as Date) >= fromDate
//         )
//         and
//         (
//             toDate == null
//             or (v.sail.from.dateTime as Date) <= toDate
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> guestCount (DataWeave 2.0, 19 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageGuestCountX(json input) returns json {
// %dw 2.0
// output application/json
// 
// var queryString = vars.inputPayload.query default ""
// var payloadVars = vars.inputPayload.variables default {}
// 
// // -------- Extract guestCount --------
// var guestCount =
//     if (payloadVars.guestCount?)
//         payloadVars.guestCount
//     else do {
//         var m = queryString scan /guestCount\s*:\s*(\d+)/
//         ---
//         if (isEmpty(m)) 0
//         else (m[0][1] as Number)
//     }
// 
// ---
// guestCount
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> operationName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageOperationNameX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// "PackagePromotions"
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> set-payload (DataWeave 2.0, 160 lines).
# Output fields: promotionalPricesInfo, promotionalPricesInfo, category.
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageSetPayloadX(json input) returns json {
// %dw 2.0
// output application/json
// 
// //---------------------------------------
// // INPUT
// //---------------------------------------
// var queryString = vars.inputPayload.query default ""
// var variables   = vars.inputPayload.variables default {}
// var params      = variables.params default {}
// var body        = vars.inputPayload default {}
// var seaware     = payload default []
// 
// //---------------------------------------
// // INLINE EXTRACTION
// //---------------------------------------
// fun extractPkgKey(q) =
//     (q scan(/pkgKey\s*:\s*"([^"]+)"/))[0][1] default null
// 
// fun extractGuestCount(q) =
//     ((q scan(/guestCount\s*:\s*(\d+)/))[0][1]) as Number default null
// 
// fun extractCabinCategory(q) =
//     (q scan(/cabinCategoryKeys\s*:\s*\["([^"]+)"\]/))[0][1] default null
// 
// fun extractFromDate(q) =
//     (q scan(/startDateRange\s*:\s*\{\s*from\s*:\s*"([^"]+)"/))[0][1] default null
// 
// fun extractToDate(q) =
//     (q scan(/startDateRange\s*:\s*\{[^}]*to\s*:\s*"([^"]+)"/))[0][1] default null
// 
// //---------------------------------------
// // PARAMETERS
// //---------------------------------------
// var pkgKey =
//     upper(
//         variables.pkgKey
//         default params.pkgKey
//         default body.pkgKey
//         default extractPkgKey(queryString)
//     )
// 
// var guestCount =
//     variables.guestCount
//     default params.guestCount
//     default body.guestCount
//     default extractGuestCount(queryString)
// 
// var cabinCategoryKey =
//     upper(
//         (variables.cabinCategoryKeys default params.cabinCategoryKeys default [])[0]
//         default extractCabinCategory(queryString)
//     )
// 
// var fromDate =
//     variables.startDateRange.from
//     default params.startDateRange.from
//     default body.startDateRange.from
//     default extractFromDate(queryString)
// 
// var toDate =
//     variables.startDateRange.to
//     default params.startDateRange.to
//     default body.startDateRange.to
//     default extractToDate(queryString)
// 
// //---------------------------------------
// // PACKAGE FILTER
// //---------------------------------------
// var pkgFiltered =
//     if (pkgKey != null)
//         seaware filter (p) ->
//             upper(p.package.key default "") == pkgKey
//     else
//         seaware
// 
// //---------------------------------------
// // DATE FILTER (always applied when dates provided)
// //---------------------------------------
// var dateFiltered =
//     if (fromDate != null and toDate != null)
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> operationName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageOperationNameXX(json input) returns json {
// %dw 2.0
// output application/java
// ---
// "cities"
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> set-payload (DataWeave 2.0, 82 lines).
# Output fields: keys, key, id, locationType, code, name, cities.
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageSetPayloadXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// var queryString = vars.inputPayload.query default ""
// var queryVars   = vars.inputPayload.variables default {}
// var cacheResponse = if (payload is Object) payload else {}
// 
// // ---------------------------------------------------
// // Extract INLINE country key
// // ---------------------------------------------------
// var inlineMatch =
//     queryString scan /country\s*:\s*\{\s*key\s*:\s*"([^"]+)"/
// 
// var inlineCountryKey =
//     if (!isEmpty(inlineMatch))
//         upper(inlineMatch[0][1])
//     else
//         null
// 
// // ---------------------------------------------------
// // Extract VARIABLE name
// // ---------------------------------------------------
// var variableMatch =
//     queryString scan /country\s*:\s*\{\s*key\s*:\s*\$([A-Za-z0-9_]+)/
// 
// var variableName =
//     if (!isEmpty(variableMatch))
//         variableMatch[0][1]
//     else
//         null
// 
// // ---------------------------------------------------
// // Resolve variable value
// // ---------------------------------------------------
// var variableCountryKey =
//     if (variableName != null and queryVars[variableName]?)
//         upper((queryVars[variableName][0]) as String)
//     else
//         null
// 
// // ---------------------------------------------------
// // Final country key
// // ---------------------------------------------------
// var countryKey =
//     if (inlineCountryKey != null)
//         inlineCountryKey
//     else
//         variableCountryKey
// 
// // ---------------------------------------------------
// // Filter cities
// // ---------------------------------------------------
// var filteredCities =
//     (cacheResponse.data.cities default [])
//         filter (city) ->
//             countryKey == null
//             or (
//                 city.country?
//                 and city.country.key?
//                 and upper(city.country.key) == countryKey
//             )
// 
// // ---------------------------------------------------
// // Shape GraphQL response fields
// // ---------------------------------------------------
// var citiesResponse =
//     filteredCities map (city) -> {
//         keys: city.keys,
//         key: city.key,
//         id: city.id,
//         locationType: city.locationType,
//         code: city.code,
//         name: city.name
//     }
// 
// ---
// {
//     data: {
//         cities: citiesResponse
//     }
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> guestCount (DataWeave 2.0, 9 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageGuestCountXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// var query = vars.inputPayload.query default ""
// 
// 
// var match = query scan /guestCount\s*:\s*(\d+)/
// ---
// match[0][1] as Number default 1
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> operationName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageOperationNameXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// "countries"
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> guestCount (DataWeave 2.0, 9 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageGuestCountXXX(json input) returns json {
// %dw 2.0
// output application/json
// 
// var query = vars.inputPayload.query default ""
// 
// 
// var match = query scan /guestCount\s*:\s*(\d+)/
// ---
// match[0][1] as Number default 1
    return input;
}

# Source: `run-time-request-flow` / Transform Message -> operationName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function runTimeRequestFlowTransformMessageOperationNameXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// "languages"
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> inputPayload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformM(json input) returns json {
// %dw 2.0
// output application/json
// ---
// payload
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> clientIp (DataWeave 2.0, 6 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// attributes.headers['x-client-ip']
//             default attributes.headers['x-forwarded-for']
//             default (attributes.remoteAddress splitBy ':')[0] replace '/' with ''
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> opType (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// attributes.headers['x-operation-type'] default 'query'
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> opName (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// attributes.headers['x-operation-name'] default ''
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> currentPool (DataWeave 2.0, 9 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// if (upper(vars.opName) == 'CREATE' or upper(vars.opName) == 'STORE')
//     'reservation'
//   else if (vars.opType == 'mutation')
//     'mutation'
//   else
//     'query'
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> isReservationOp (DataWeave 2.0, 5 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// upper(vars.opName) == 'CREATE'
//             or upper(vars.opName) == 'STORE'
    return input;
}

# Source: `reservation-common-services-proc-api-implementationFlow` / Transform Message -> clientVersion (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcApiImplementationFlowTransformMXXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// attributes.headers['client_version'] default 'v2'
    return input;
}

# Source: `Seaware_System_API_Sub_Flow` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function seawareSystemAPISubFlowTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// payload
    return input;
}

# Source: `reservation-common-services-process-api-console` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcessApiConsoleTransformMessageSe(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `reservation-common-services-process-api-console` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function reservationCommonServicesProcessApiConsoleTransformMessageHt(json input) returns json {
// 404
    return input;
}
