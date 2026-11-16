// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `exceptionSub_Flow` / Initialize errorMessage -> errorMessage (DataWeave 2.0, 7 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function exceptionSubFlowInitializeErrorMessageErrorMessage(json input) returns json {
// %dw 2.0
// output application/java
// ---
// if ((vars.errorMessage default null) == null) 
//     error
// else 
//     vars.errorMessage
    return input;
}

# Source: `exceptionSub_Flow` / Prepare Email Message -> set-payload (DataWeave 2.0, 53 lines).
# Output fields: subject, importance, contentType, content, toRecipients, address, ccRecipients, address, saveToSentItems.
#
# + input - The source payload
# + return - The mapped value
public isolated function exceptionSubFlowPrepareEmailMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// 
// var component = error.failingComponent default ""
// var afterAt = (component splitBy "@")[1] default ""
// var apiName = (afterAt splitBy ":")[0] default "N/A"
// var errorType = vars.errorMessage.errorType.identifier default "N/A"
// var description = vars.errorMessage.description default "N/A"
// var details = error.exception.errorMessage.payload default "N/A"
// 
// var detailsAsString =
//     if (details is String) details
//     else if (details is Object) write(details, "application/json")
//     else details as String
// 
// var importanceLevel =
//     if (["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"] contains errorType)
//         "High"
//     else 
//         "Low"
// 
// var subjectLine = if (importanceLevel == "High") "⚠️" ++ apiName else apiName
// 
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
//   },
//   saveToSentItems: p('email.saveType')
// }
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Bad request"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatus(json input) returns json {
// 400
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayloadX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatusX(json input) returns json {
// 404
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayloadXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Method not allowed"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatusXX(json input) returns json {
// 405
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayloadXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not acceptable"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatusXXX(json input) returns json {
// 406
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayloadXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Unsupported media type"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatusXXXX(json input) returns json {
// 415
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageSetPayloadXXXXX(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Not Implemented"}
    return input;
}

# Source: `cms-proc-api-main` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiMainTransformMessageHttpStatusXXXXX(json input) returns json {
// 501
    return input;
}

# Source: `cms-proc-api-console` / Transform Message -> set-payload (DataWeave 2.0, 4 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiConsoleTransformMessageSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {message: "Resource not found"}
    return input;
}

# Source: `cms-proc-api-console` / Transform Message -> httpStatus (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function cmsProcApiConsoleTransformMessageHttpStatus(json input) returns json {
// 404
    return input;
}

# Source: `get-content-implementationSub_Flow` / Generic queryParams Handler -> queryParams (DataWeave 2.0, 55 lines).
# Output fields: locale, locale, locale, locale, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function getContentImplementationSubFlowGenericQueryParamsHandlerQuer(json input) returns json {
// %dw 2.0
// output application/java
// var slug = attributes.uriParams.slug default ""
// var site = attributes.queryParams.site default "mobile"
// var locale = attributes.queryParams.locale default "en"
// var categoryType = attributes.uriParams.categoryType default null
// var path = (attributes.requestPath default "") as String {class: "java.lang.String"}
// 
// ---
// if (slug == "profile" and categoryType != null) 
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][information.info][populate][info][filters][heading]"): categoryType,
//         "locale": locale
//     }
// else if (slug == "home" and categoryType == "hero-banner")
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ categoryType ++ "][populate][hero_banner][populate]"): "*",
//         "locale": locale
//     }
// else if (slug == "home" and categoryType == "feature-section")
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
// 		"locale": locale,
//         ("populate[components][on][shared." ++ categoryType ++ "][populate][tab_items][populate][tab_item][populate][media][populate][cta]"): "*",
// 		("populate[components][on][shared." ++ categoryType ++ "][populate][tab_items][populate][tab_item][populate][media][populate][image]"): true
//     }    
// else if ((path contains "/categories") and (categoryType != null))
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ slug ++ "][populate][" ++ slug ++ "_categories][filters][category_title][\$eq]"): categoryType,
//         ("populate[components][on][shared." ++ slug ++ "][populate][" ++ slug ++ "_categories][populate][" ++ slug ++ "_items]"): "*",
//         "locale": locale
//     }
// else if (path contains "/categories")
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ slug ++ "][populate]"): slug ++ "_categories",
//         "locale": locale
//     }
// else if (slug != "")
//     {
//         "filters[site_setting][name][\$eq]": site,
//         "filters[page_slug][\$eq]": slug,
//         "populate": "*",
//         "locale": locale
//     }
// else
//     {}
    return input;
}

# Source: `content-implementationSub_Flow` / Slug Router Resolver -> slugFlow (DataWeave 2.0, 100 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function contentImplementationSubFlowSlugRouterResolverSlugFlow(json input) returns json {
// %dw 2.0
// output application/java
// 
// var slug = attributes.uriParams.slug default ""
// 
// var map = {
//   // cabin-handlerSubFlow
//   "cabin": "cabin-handlerSubFlow",
// 
//   // packages-handlerSubFlow
//   "packages": "packages-handlerSubFlow",
// 
//   // itineraries-handlerSubFlow
//   "itineraries": "itineraries-handlerSubFlow",
// 
//   // excursions-handlerSubFlow
//   "excursions": "excursions-handlerSubFlow",
// 
//   // addons-handlerSubFlow
//   "add-ons": "addons-handlerSubFlow",
// 
//   // destinations-handlerSubFlow
//   "destinations": "destinations-handlerSubFlow",
//   
//   //destination-experiences
//   "destination-experiences": "destination-experiences-handlerSubFlow",
//   
//   //port-details
//   "port-details": "port-details-handlerSubFlow",
//   
//   //destination-activities
//   "destination-activities": "destination-activities-handlerSubFlow",
// 
//   // header-handlerSubFlow
//   "header": "header-handlerSubFlow",
// 
//   // footer-handlerSubFlow
//   "footer": "footer-handlerSubFlow",
// 
//   // onboardExcursion-handlerSubFlow
//   "onboard-excursion": "onboardExcursion-handlerSubFlow",
// 
//   // spas-handlerSubFlow
//   "spas": "spas-handlerSubFlow",
// 
//   // dinings-handlerSubFlow
//   "dinings": "dinings-handlerSubFlow",
// 
//   // offers-handlerSubFlow
//   "offers": "offers-handlerSubFlow",
//   "offer1": "offers-handlerSubFlow",
//   "offer2": "offers-handlerSubFlow",
// 
//   // docs-handlerSubFlow
//   "privacy-policy": "docs-handlerSubFlow",
//   "cookies": "docs-handlerSubFlow",
//   "terms-and-conditions": "docs-handlerSubFlow",
//   "flight-transport-terms": "docs-handlerSubFlow",
//   "deckInfoTranslationMap": "docs-handlerSubFlow",
//   "popup-msg": "docs-handlerSubFlow",
//   "icons": "docs-handlerSubFlow",
//   "visa-booking-request": "docs-handlerSubFlow",
//   "website-icons": "docs-handlerSubFlow",
//   "prohibited-items-policy": "docs-handlerSubFlow",
//   "booking-cancellation-policy": "docs-handlerSubFlow",
//   "errors": "docs-handlerSubFlow",
// 
//   // embarkations-handlerSubFlow
//   "embarkations": "embarkations-handlerSubFlow",
// 
//   // travelTradePartners-handlerSubFlow
//   "travel-trade-partners": "travelTradePartners-handlerSubFlow",
// 
//   // mobile-page-generals-handlerSubFlow
//   "translation-messages": "mobile-page-generals-handlerSubFlow",
//   "spa-policy": "mobile-page-generals-handlerSubFlow",
//   "dining-policy": "mobile-page-generals-handlerSubFlow",
//   "packages-policy": "mobile-page-generals-handlerSubFlow",
// 
//   // mobile-page-cruises-handlerSubFlow
    return input;
}

# Source: `cabin-handlerSubFlow` / Cabin Generic queryParams Handler -> queryParams (DataWeave 2.0, 18 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function cabinHandlerSubFlowCabinGenericQueryParamsHandlerQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var slug = attributes.uriParams.slug default ""
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// //var site = attributes.queryParams.site default "mobile"
// ---
// if (categoryType != "")
//     {
//         "filters[cabin_types][cabin_type_detail][code]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
// else
//     {
//         "populate": "*",
//         "locale": locale
//     }
    return input;
}

# Source: `packages-handlerSubFlow` / Packages Generic queryParams Handler -> queryParams (DataWeave 2.0, 31 lines).
# Output fields: populate, locale, populate, locale, populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function packagesHandlerSubFlowPackagesGenericQueryParamsHandlerQuery(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// var destination = attributes.queryParams.destination  default ""
// var duration = attributes.queryParams.duration  default ""
// //var site = attributes.queryParams.site default "mobile"
// ---
// if (categoryType != "")
//     {
//         "filters[pkg_code][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
// else if (destination != "")
//     {
// 		"filters[destination][page_slug][\$eq]": destination,
// 		"populate": "*",
// 		"locale": locale
//     }
// else if (duration != "")
//     {
// 		"filters[duration][\$eq]": duration,
// 		"populate": "*",
// 		"locale": locale
//     }
// else
//     {
//         "populate": "*",
//         "locale": locale
//     }
    return input;
}

# Source: `itineraries-handlerSubFlow` / Itineraries Generic queryParams Handler -> queryParams (DataWeave 2.0, 18 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function itinerariesHandlerSubFlowItinerariesGenericQueryParamsHandle(json input) returns json {
// %dw 2.0
// output application/java
// import * from dw::core::URL
// 
// var categoryType = attributes.uriParams.categoryType default ""
// var locale = attributes.queryParams.locale default "en"
// var cleanedQueryParams = attributes.queryString replace /\[\d+\]/ with ""
// 
// var finalQuery =
//     if (cleanedQueryParams != "")
//         cleanedQueryParams ++ (if (cleanedQueryParams contains "populate=") "" else "&populate=*")
//     else if (categoryType != "")
//         "filters[page_slug][\$eq]=" ++ categoryType ++ "&populate=*&locale=" ++ locale
//     else
//         "populate=*&locale=" ++ locale
// 
// ---
// encodeURI(finalQuery)
    return input;
}

# Source: `excursions-handlerSubFlow` / Excursions Generic queryParams Handler -> queryParams (DataWeave 2.0, 13 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function excursionsHandlerSubFlowExcursionsGenericQueryParamsHandlerQ(json input) returns json {
// %dw 2.0
// output application/java
// import * from dw::core::URL
// 
// var shorexCodes = attributes.queryParams.shorex_code default ""
// var locale = attributes.queryParams.locale default "en"
// 
// ---
// if (shorexCodes != "")
//     "shorex_code=" ++ shorexCodes ++ "&populate=*&locale=" ++ locale
// 	
// else 
//     "populate=*&locale=" ++ locale
    return input;
}

# Source: `addons-handlerSubFlow` / Add-ons Generic queryParams Handler -> queryParams (DataWeave 2.0, 18 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function addonsHandlerSubFlowAddOnsGenericQueryParamsHandlerQueryPara(json input) returns json {
// %dw 2.0
// output application/java
// import * from dw::core::URL
// 
// var categoryType = attributes.uriParams.categoryType default ""
// var locale = attributes.queryParams.locale default "en"
// var cleanedQueryParams = attributes.queryString replace /\[\d+\]/ with ""
// 
// var finalQuery =
//     if (cleanedQueryParams != "" and categoryType == "")
//         cleanedQueryParams ++ (if (cleanedQueryParams contains "populate=") "" else "&populate=*")
//     else if (categoryType != "")
//         "filters[page_slug][\$eq]=" ++ categoryType ++ "&populate=*&locale=" ++ locale
//     else
//         "populate=*&locale=" ++ locale
// 
// ---
// finalQuery
    return input;
}

# Source: `destinations-handlerSubFlow` / Destinations Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function destinationsHandlerSubFlowDestinationsGenericQueryParamsHand(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// ---
// if (categoryType != "")
//     {
//         "filters[page_name][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
//  else
// 	{
// 	    populate: "*",
// 	    locale: locale
// 	}
    return input;
}

# Source: `destination-experiences-handlerSubFlow` / Destination-experiences Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function destinationExperiencesHandlerSubFlowDestinationExperiencesGe(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// ---
// if (categoryType != "")
//     {
//         "filters[page_slug][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
//  else
// 	{
// 	    populate: "*",
// 	    locale: locale
// 	}
    return input;
}

# Source: `port-details-handlerSubFlow` / Port-details Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function portDetailsHandlerSubFlowPortDetailsGenericQueryParamsHandle(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// ---
// if (categoryType != "")
//     {
//         "filters[page_name][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
//  else
// 	{
// 	    populate: "*",
// 	    locale: locale
// 	}
    return input;
}

# Source: `destination-activities-handlerSubFlow` / Destination-activities Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function destinationActivitiesHandlerSubFlowDestinationActivitiesGene(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// ---
// if (categoryType != "")
//     {
//         "filters[page_name][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
//  else
// 	{
// 	    populate: "*",
// 	    locale: locale
// 	}
    return input;
}

# Source: `header-handlerSubFlow` / Header Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function headerHandlerSubFlowHeaderGenericQueryParamsHandlerQueryPara(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `footer-handlerSubFlow` / Footer Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function footerHandlerSubFlowFooterGenericQueryParamsHandlerQueryPara(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `onboardExcursion-handlerSubFlow` / onboardExcursion Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function onboardExcursionHandlerSubFlowOnboardExcursionGenericQueryPa(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `spas-handlerSubFlow` / spas Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function spasHandlerSubFlowSpasGenericQueryParamsHandlerQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `dinings-handlerSubFlow` / dinings Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function diningsHandlerSubFlowDiningsGenericQueryParamsHandlerQueryPa(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `offers-handlerSubFlow` / Offers Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function offersHandlerSubFlowOffersGenericQueryParamsHandlerQueryPara(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// var slug = attributes.uriParams.slug default ""
// ---
// if (slug == "offer1" or slug == "offer2")
// {
// 	"filters[page_slug][\$eq]": slug,
// 	"populate": "*",
//     "locale": locale
// }
// else
// {
//     populate: "*",
//     locale: locale
// }
    return input;
}

# Source: `docs-handlerSubFlow` / Docs Generic queryParams Handler -> queryParams (DataWeave 2.0, 10 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function docsHandlerSubFlowDocsGenericQueryParamsHandlerQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// var slug = attributes.uriParams.slug default ""
// ---
// {
// 	"filters[page_slug][\$eq]": slug,
// 	"populate": "*",
//     "locale": locale
// }
    return input;
}

# Source: `embarkations-handlerSubFlow` / embarkations Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function embarkationsHandlerSubFlowEmbarkationsGenericQueryParamsHand(json input) returns json {
// %dw 2.0
// output application/java
// var categoryType = attributes.uriParams.categoryType  default ""
// var locale = attributes.queryParams.locale default "en"
// ---
// if (categoryType != "")
//     {
//         "filters[page_slug][\$eq]": categoryType,
//         "populate": "*",
//         "locale": locale 
//     }
//  else
// 	{
// 	    populate: "*",
// 	    locale: locale
// 	}
    return input;
}

# Source: `travelTradePartners-handlerSubFlow` / travelTradePartners Generic queryParams Handler -> queryParams (DataWeave 2.0, 16 lines).
# Output fields: populate, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function travelTradePartnersHandlerSubFlowTravelTradePartnersGenericQ(json input) returns json {
// %dw 2.0
// output application/java
// var country = attributes.uriParams.categoryType default null
// var locale = attributes.queryParams.locale default "en"
// ---
// if (country != null and country != "")
//     {
//         "filters[page_slug][\$eq]": country,
//         "populate": "*",
//         "locale": locale
//     }
// else
//     {
//         "populate": "*",
//         "locale": locale
//     }
    return input;
}

# Source: `mobile-page-generals-handlerSubFlow` / mobile-page Generic queryParams Handler -> queryParams (DataWeave 2.0, 10 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function mobilePageGeneralsHandlerSubFlowMobilePageGenericQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// var slug = attributes.uriParams.slug default ""
// ---
// {
// 	"filters[page_slug][\$eq]": slug,
// 	"populate": "*",
//     "locale": locale
// }
    return input;
}

# Source: `mobile-page-pre-cruises-handlerSubFlow` / mobile-page-pre-cruises Generic queryParams Handler -> queryParams (DataWeave 2.0, 10 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function mobilePagePreCruisesHandlerSubFlowMobilePagePreCruisesGeneri(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// var slug = attributes.uriParams.slug default ""
// ---
// {
// 	"filters[page_slug][\$eq]": slug,
// 	"populate": "*",
//     "locale": locale
// }
    return input;
}

# Source: `mobile-page-cruises-handlerSubFlow` / mobile-page-cruise Generic queryParams Handler -> queryParams (DataWeave 2.0, 10 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function mobilePageCruisesHandlerSubFlowMobilePageCruiseGenericQueryP(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// var slug = attributes.uriParams.slug default ""
// ---
// {
// 	"filters[page_slug][\$eq]": slug,
// 	"populate": "*",
//     "locale": locale
// }
    return input;
}

# Source: `configurations-handlerSubFlow` / Configurations Generic queryParams Handler -> queryParams (DataWeave 2.0, 8 lines).
# Output fields: populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function configurationsHandlerSubFlowConfigurationsGenericQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var locale = attributes.queryParams.locale default "en"
// ---
// {
// 	"populate": "*",
//     "locale": locale
// }
    return input;
}

# Source: `pages-handlerSubFlow` / Pages Generic queryParams Handler -> queryParams (DataWeave 2.0, 48 lines).
# Output fields: locale, locale, locale, locale, locale, populate, locale.
#
# + input - The source payload
# + return - The mapped value
public isolated function pagesHandlerSubFlowPagesGenericQueryParamsHandlerQueryParams(json input) returns json {
// %dw 2.0
// output application/java
// var slug = attributes.uriParams.slug default ""
// var locale = attributes.queryParams.locale default "en"
// var categoryType = attributes.uriParams.categoryType default null
// var path = (attributes.requestPath default "") as String {class: "java.lang.String"}
// 
// ---
// if (slug == "profile" and categoryType != null) 
//     {
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][information.info][populate][info][filters][heading]"): categoryType,
//         "locale": locale
//     }
// else if (slug == "home" and categoryType == "hero-banner")
//     {
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ categoryType ++ "][populate][hero_banner][populate]"): "*",
//         "locale": locale
//     }
// else if (slug == "home" and categoryType == "feature-section")
//     {
//         "filters[page_slug][\$eq]": slug,
// 		"locale": locale,
//         ("populate[components][on][shared." ++ categoryType ++ "][populate][tab_items][populate][tab_item][populate][media][populate][cta]"): "*",
// 		("populate[components][on][shared." ++ categoryType ++ "][populate][tab_items][populate][tab_item][populate][media][populate][image]"): true
//     }    
// else if ((path contains "/categories") and (categoryType != null))
//     {
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ slug ++ "][populate][" ++ slug ++ "_categories][filters][category_title][\$eq]"): categoryType,
//         ("populate[components][on][shared." ++ slug ++ "][populate][" ++ slug ++ "_categories][populate][" ++ slug ++ "_items]"): "*",
//         "locale": locale
//     }
// else if (path contains "/categories")
//     {
//         "filters[page_slug][\$eq]": slug,
//         ("populate[components][on][shared." ++ slug ++ "][populate]"): slug ++ "_categories",
//         "locale": locale
//     }
// else if (slug != "")
//     {
//         "filters[page_slug][\$eq]": slug,
//         "populate": "*",
//         "locale": locale
//     }
// else
//     {}
    return input;
}

# Source: `descriptionSub_Flow` / create path -> path (DataWeave 2.0, 7 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function descriptionSubFlowCreatePathPath(json input) returns json {
// %dw 2.0
// output application/java
// var t = attributes.uriParams.'type'
// var s = attributes.uriParams.'ship' default ""
// var c = attributes.uriParams.'code'
// ---
// t
    return input;
}

# Source: `imagesSub_Flow` / create path -> type (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function imagesSubFlowCreatePathType(json input) returns json {
// attributes.uriParams.'type'
    return input;
}

# Source: `imagesSub_Flow` / create path -> ship (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function imagesSubFlowCreatePathShip(json input) returns json {
// attributes.uriParams.'ship'
    return input;
}

# Source: `imagesSub_Flow` / create path -> code (DataWeave 2.0, 1 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function imagesSubFlowCreatePathCode(json input) returns json {
// attributes.uriParams.'code'
    return input;
}

# Source: `imagesSub_Flow` / create path -> path (DataWeave 2.0, 10 lines).
#
# + input - The source payload
# + return - The mapped value
public isolated function imagesSubFlowCreatePathPath(json input) returns json {
// %dw 2.0
// output application/java
// var t = attributes.uriParams.'type'
// var s = attributes.uriParams.'ship' default ""
// var c = attributes.uriParams.'code'
// ---
// if (s != "")
//   t ++ "/" ++ s ++ "_" ++ c
// else
//   t ++ "/" ++ c
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
