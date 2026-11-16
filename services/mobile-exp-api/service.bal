import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// mobile-exp-api on WSO2 (Ballerina): generated skeleton. Every resource answers NOT_IMPLEMENTED
// until its logic is migrated (see the Mapping document).

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("mobile-exp-api starting", env = env, basePath = basePath,
            routedToMigrated = string:'join(",", ...hTTPRequestAllProcsClient.routedPrefixes()));
    log:printInfo("state store", keptIn = state.location());
}

final http:Service apiService = isolated service object {
    # Source: GET /mobile-exp-api/v1/activity-planner/v1/activities (get:\activity-planner\v1\activities:mobile-exp-api-config)
    isolated resource function get activity\-planner/v1/activities(http:Request request) returns http:Response {
        return operation(request, {}, flowget__activity_planner_v1_activities_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_activity_planner_v1_activities);
    }

    # Source: GET /mobile-exp-api/v1/activity-planner/v1/activity-items (get:\activity-planner\v1\activity-items:mobile-exp-api-config)
    isolated resource function get activity\-planner/v1/activity\-items(http:Request request) returns http:Response {
        return operation(request, {}, flowget__activity_planner_v1_activity_items_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_activity_planner_v1_activity_items);
    }

    # Source: GET /mobile-exp-api/v1/activity-planner/v1/event-bookings (get:\activity-planner\v1\event-bookings:mobile-exp-api-config)
    isolated resource function get activity\-planner/v1/event\-bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowget__activity_planner_v1_event_bookings_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_activity_planner_v1_event_bookings);
    }

    # Source: GET /mobile-exp-api/v1/core/v1/itinerary-voyages (get:\core\v1\itinerary-voyages:mobile-exp-api-config)
    isolated resource function get core/v1/itinerary\-voyages(http:Request request) returns http:Response {
        return operation(request, {}, flowget__core_v1_itinerary_voyages_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_core_v1_itinerary_voyages);
    }

    # Source: GET /mobile-exp-api/v1/core/v1/itinerary-voyages/active-itinerary-voyage (get:\core\v1\itinerary-voyages\active-itinerary-voyage:mobile-exp-api-config)
    isolated resource function get core/v1/itinerary\-voyages/active\-itinerary\-voyage(http:Request request) returns http:Response {
        return operation(request, {}, flowget__core_v1_itinerary_voyages_active_itinerary_voyage_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_core_v1_itinerary_voyages_active_itinerary_voya);
    }

    # Source: GET /mobile-exp-api/v1/dining/v1/reservation-vendor/inventory (get:\dining\v1\reservation-vendor\inventory:mobile-exp-api-config)
    isolated resource function get dining/v1/reservation\-vendor/inventory(http:Request request) returns http:Response {
        return operation(request, {}, flowget__dining_v1_reservation_vendor_inventory_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_dining_v1_reservation_vendor_inventory);
    }

    # Source: GET /mobile-exp-api/v1/dining/v1/reservation-vendor/location (get:\dining\v1\reservation-vendor\location:mobile-exp-api-config)
    isolated resource function get dining/v1/reservation\-vendor/location(http:Request request) returns http:Response {
        return operation(request, {}, flowget__dining_v1_reservation_vendor_location_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_dining_v1_reservation_vendor_location);
    }

    # Source: GET /mobile-exp-api/v1/dining/v1/reservation-vendor/reservation/passenger (get:\dining\v1\reservation-vendor\reservation\passenger:mobile-exp-api-config)
    isolated resource function get dining/v1/reservation\-vendor/reservation/passenger(http:Request request) returns http:Response {
        return operation(request, {}, flowget__dining_v1_reservation_vendor_reservation_passenger_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_dining_v1_reservation_vendor_reservation_passen);
    }

    # Source: GET /mobile-exp-api/v1/excursion/v1/bookable-tours (get:\excursion\v1\bookable-tours:mobile-exp-api-config)
    isolated resource function get excursion/v1/bookable\-tours(http:Request request) returns http:Response {
        return operation(request, {}, flowget__excursion_v1_bookable_tours_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_excursion_v1_bookable_tours);
    }

    # Source: GET /mobile-exp-api/v1/excursion/v1/bookable-tours/with-sales-channels (get:\excursion\v1\bookable-tours\with-sales-channels:mobile-exp-api-config)
    isolated resource function get excursion/v1/bookable\-tours/with\-sales\-channels(http:Request request) returns http:Response {
        return operation(request, {}, flowget__excursion_v1_bookable_tours_with_sales_channels_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_excursion_v1_bookable_tours_with_sales_channels);
    }

    # Source: GET /mobile-exp-api/v1/excursion/v1/bookings (get:\excursion\v1\bookings:mobile-exp-api-config)
    isolated resource function get excursion/v1/bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowget__excursion_v1_bookings_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_excursion_v1_bookings);
    }

    # Source: GET /mobile-exp-api/v1/excursion/v1/departure-age-groups (get:\excursion\v1\departure-age-groups:mobile-exp-api-config)
    isolated resource function get excursion/v1/departure\-age\-groups(http:Request request) returns http:Response {
        return operation(request, {}, flowget__excursion_v1_departure_age_groups_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_excursion_v1_departure_age_groups);
    }

    # Source: GET /mobile-exp-api/v1/galley-display/v1/menu-schedulers (get:\galley-display\v1\menu-schedulers:mobile-exp-api-config)
    isolated resource function get galley\-display/v1/menu\-schedulers(http:Request request) returns http:Response {
        return operation(request, {}, flowget__galley_display_v1_menu_schedulers_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_galley_display_v1_menu_schedulers);
    }

    # Source: GET /mobile-exp-api/v1/ism/v1/amenity (get:\ism\v1\amenity:mobile-exp-api-config)
    isolated resource function get ism/v1/amenity(http:Request request) returns http:Response {
        return operation(request, {}, flowget__ism_v1_amenity_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_ism_v1_amenity);
    }

    # Source: GET /mobile-exp-api/v1/ism/v1/amenity-codes (get:\ism\v1\amenity-codes:mobile-exp-api-config)
    isolated resource function get ism/v1/amenity\-codes(http:Request request) returns http:Response {
        return operation(request, {}, flowget__ism_v1_amenity_codes_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_ism_v1_amenity_codes);
    }

    # Source: GET /mobile-exp-api/v1/pms/v1/travel-documents (get:\pms\v1\travel-documents:mobile-exp-api-config)
    isolated resource function get pms/v1/travel\-documents(http:Request request) returns http:Response {
        return operation(request, {}, flowget__pms_v1_travel_documents_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_pms_v1_travel_documents);
    }

    # Source: GET /mobile-exp-api/v1/pms/v1/travel-documents/(id) (get:\pms\v1\travel-documents\(id):mobile-exp-api-config)
    isolated resource function get pms/v1/travel\-documents/[string id](http:Request request) returns http:Response {
        return operation(request, {"id": id}, flowget__pms_v1_travel_documents__id__mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_pms_v1_travel_documents__id);
    }

    # Source: POST /mobile-exp-api/v1/activity-planner/v1/event-bookings/create-multiple-bookings (post:\activity-planner\v1\event-bookings\create-multiple-bookings:application\json:mobile-exp-api-config)
    isolated resource function post activity\-planner/v1/event\-bookings/create\-multiple\-bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__activity_planner_v1_event_bookings_create_multiple_bookings_application_js, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_activity_planner_v1_event_bookings_create_mult);
    }

    # Source: POST /mobile-exp-api/v1/activity-planner/v1/event-bookings/post-multiple-bookings (post:\activity-planner\v1\event-bookings\post-multiple-bookings:application\json:mobile-exp-api-config)
    isolated resource function post activity\-planner/v1/event\-bookings/post\-multiple\-bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__activity_planner_v1_event_bookings_post_multiple_bookings_application_json, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_activity_planner_v1_event_bookings_post_multip);
    }

    # Source: POST /mobile-exp-api/v1/dining/v1/reservation-vendor/reservation/actions/activate (post:\dining\v1\reservation-vendor\reservation\actions\activate:application\json:mobile-exp-api-config)
    isolated resource function post dining/v1/reservation\-vendor/reservation/actions/activate(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__dining_v1_reservation_vendor_reservation_actions_activate_application_json, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_dining_v1_reservation_vendor_reservation_actio);
    }

    # Source: POST /mobile-exp-api/v1/dining/v1/reservation-vendor/reservation (post:\dining\v1\reservation-vendor\reservation:application\json:mobile-exp-api-config)
    isolated resource function post dining/v1/reservation\-vendor/reservation(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__dining_v1_reservation_vendor_reservation_application_json_mobile_exp_api_c, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_dining_v1_reservation_vendor_reservation);
    }

    # Source: POST /mobile-exp-api/v1/payment-gateway/v1/payment-method-authorization (post:\payment-gateway\v1\payment-method-authorization:application\json:mobile-exp-api-config)
    isolated resource function post payment\-gateway/v1/payment\-method\-authorization(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__payment_gateway_v1_payment_method_authorization_application_json_mobile_ex, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_payment_gateway_v1_payment_method_authorizatio);
    }

    # Source: POST /mobile-exp-api/v1/pms/v1/travel-documents/(id)/file (post:\pms\v1\travel-documents\(id)\file:multipart\form-data:mobile-exp-api-config)
    isolated resource function post pms/v1/travel\-documents/[string id]/file(http:Request request) returns http:Response {
        return operation(request, {"id": id}, flowpost__pms_v1_travel_documents__id__file_multipart_form_data_mobile_exp_api_confi, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_pms_v1_travel_documents__id__file);
    }

    # Source: POST /mobile-exp-api/v1/pms/v1/travel-documents (post:\pms\v1\travel-documents:application\json:mobile-exp-api-config)
    isolated resource function post pms/v1/travel\-documents(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__pms_v1_travel_documents_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_pms_v1_travel_documents);
    }

    # Source: GET /mobile-exp-api/v1/reservation/v1/person-search (get:\reservation\v1\person-search:mobile-exp-api-config)
    isolated resource function get reservation/v1/person\-search(http:Request request) returns http:Response {
        return operation(request, {}, flowget__reservation_v1_person_search_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_reservation_v1_person_search);
    }

    # Source: GET /mobile-exp-api/v1/pos/v1/packages (get:\pos\v1\packages:mobile-exp-api-config)
    isolated resource function get pos/v1/packages(http:Request request) returns http:Response {
        return operation(request, {}, flowget__pos_v1_packages_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main);
    }

    # Source: POST /mobile-exp-api/v1/excursion/v1/bookings/book (post:\excursion\v1\bookings\book:application\json:mobile-exp-api-config)
    isolated resource function post excursion/v1/bookings/book(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__excursion_v1_bookings_book_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_excursion_v1_bookings_book);
    }

    # Source: POST /mobile-exp-api/v1/mobile-backend/(webhook-type) (post:\mobile-backend\(webhook-type):application\json:mobile-exp-api-config)
    isolated resource function post mobile\-backend/\(webhook\-type\)(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__mobile_backend__webhook_type__application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main);
    }

    # Source: POST /mobile-exp-api/v1/pms/v1/person-profiles/(profileId)/picture (post:\pms\v1\person-profiles\(profileId)\picture:multipart\form-data:mobile-exp-api-config)
    isolated resource function post pms/v1/person\-profiles/[string profileId]/picture(http:Request request) returns http:Response {
        return operation(request, {"profileId": profileId}, flowpost__pms_v1_person_profiles__profileId__picture_multipart_form_data_mobile_exp_, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_pms_v1_person_profiles__profileId__picture);
    }

    # Source: POST /mobile-exp-api/v1/integration-tasks/graphql (post:\integration-tasks\graphql:application\json:mobile-exp-api-config)
    isolated resource function post integration\-tasks/graphql(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__integration_tasks_graphql_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_integration_tasks_graphql);
    }

    # Source: POST /mobile-exp-api/v1/excursion/v1/bookings/create-multiple-bookings (post:\excursion\v1\bookings\create-multiple-bookings:mobile-exp-api-config)
    isolated resource function post excursion/v1/bookings/create\-multiple\-bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__excursion_v1_bookings_create_multiple_bookings_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_excursion_v1_bookings_create_multiple_bookings);
    }

    # Source: PUT /mobile-exp-api/v1/updateEmergencyContact (put:\updateEmergencyContact:application\json:mobile-exp-api-config)
    isolated resource function put updateEmergencyContact(http:Request request) returns http:Response {
        return operation(request, {}, flowput__updateEmergencyContact_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_PUT__mobile_exp_api_v1_updateEmergencyContact);
    }

    # Source: GET /mobile-exp-api/v1/getLinkedPerson (get:\getLinkedPerson:mobile-exp-api-config)
    isolated resource function get getLinkedPerson(http:Request request) returns http:Response {
        return operation(request, {}, flowget__getLinkedPerson_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_GET__mobile_exp_api_v1_getLinkedPerson);
    }

    # Source: POST /mobile-exp-api/v1/pms/v1/custom-attribute-values (post:\pms\v1\custom-attribute-values:mobile-exp-api-config)
    isolated resource function post pms/v1/custom\-attribute\-values(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__pms_v1_custom_attribute_values_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_pms_v1_custom_attribute_values);
    }

    # Source: POST /mobile-exp-api/v1/excursion/v1/bookings/post-bookings (post:\excursion\v1\bookings\post-bookings:application\json:mobile-exp-api-config)
    isolated resource function post excursion/v1/bookings/post\-bookings(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__excursion_v1_bookings_post_bookings_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_excursion_v1_bookings_post_bookings);
    }

    # Source: POST /mobile-exp-api/v1/ism/v1/service-item-requests (post:\ism\v1\service-item-requests:application\json:mobile-exp-api-config)
    isolated resource function post ism/v1/service\-item\-requests(http:Request request) returns http:Response {
        return operation(request, {}, flowpost__ism_v1_service_item_requests_application_json_mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_POST__mobile_exp_api_v1_ism_v1_service_item_requests);
    }

    # Source: PATCH /mobile-exp-api/v1/reservation/v1/person-reservations/actions/bulk-update (patch:\reservation\v1\person-reservations\actions\bulk-update:application\json:mobile-exp-api-config)
    isolated resource function patch reservation/v1/person\-reservations/actions/bulk\-update(http:Request request) returns http:Response {
        return operation(request, {}, flowpatch__reservation_v1_person_reservations_actions_bulk_update_application_json_m, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_PATCH__mobile_exp_api_v1_reservation_v1_person_reservations_actions_bu);
    }

    # Source: DELETE /mobile-exp-api/v1/pms/v1/custom-attribute-values/(id) (delete:\pms\v1\custom-attribute-values\(id):mobile-exp-api-config)
    isolated resource function delete pms/v1/custom\-attribute\-values/[string id](http:Request request) returns http:Response {
        return operation(request, {"id": id}, flowdelete__pms_v1_custom_attribute_values__id__mobile_exp_api_config, onError_mobile_exp_api_main, respond_mobile_exp_api_main, APIKIT_DELETE__mobile_exp_api_v1_pms_v1_custom_attribute_values__id);
    }

    # Requests no operation takes: the old APIkit router answered not found / method not allowed
    isolated resource function 'default [string... path](http:Request request) returns http:Response {
        return apikitUnmatched(request, path, APIKIT_ROUTES, onError_mobile_exp_api_main, respond_mobile_exp_api_main);
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

isolated function notImplemented(http:Request request, string sourceEndpoint) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    log:printWarn("Not migrated yet", correlationId = correlationId, sourceEndpoint = sourceEndpoint);
    return commons:errorResponse(commons:envelopeOf(commons:NOT_IMPLEMENTED, "Not migrated yet: " + sourceEndpoint,
            correlationId));
}
