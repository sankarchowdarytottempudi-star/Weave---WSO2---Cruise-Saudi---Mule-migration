# Switch and pace of the timed job.
#
# + enabled - false: the job is not started and nothing is connected or called
# + intervalSeconds - Pause between two runs
# + startDelaySeconds - Wait before the first run
public type TimerSettings record {|
    boolean enabled = false;
    decimal intervalSeconds = 90;
    decimal startDelaySeconds = 0;
|};

# Switch and address of the message queue.
#
# + enabled - false: the queue is not connected
# + brokerUrl - Broker address
# + username - Broker user ("" for none)
# + password - Broker password
# + clientId - Client id for the topic subscription ("" for none)
# + topic - Topic to listen on
public type QueueSettings record {|
    boolean enabled = false;
    string brokerUrl = "";
    string username = "";
    string password = "";
    string clientId = "";
    string topic = "";
|};

# The account the job signs in to Seaware with.
#
# + username - User
# + password - Password
public type SeawareLogin record {|
    string username = "";
    string password = "";
|};

# How the job reads and retries.
#
# + mode - "delta": follow the clock; anything else: walk from `fromDate` to `toDate`
# + pageSize - Reservations asked for per run
# + chunkSize - Reservations written to the CRM per block
# + fromDate - Start of the fixed range
# + toDate - End of the fixed range
# + windowDays - Step of the fixed range, in days
# + deltaFromMinutes - Minutes before now a "delta" slice starts
# + deltaToMinutes - Minutes after now a "delta" slice ends
# + errorTable - Table that failed records are written to
# + retryCount - Extra tries for a failed call
# + retryWaitSeconds - Pause between tries
# + retryErrorTypes - Kinds of failure that are tried again
# + writeShorex - Write shore excursions to the CRM. Off, as in the old application, where the
# shorex step (zoho-shorex-upsertSub_Flow) is ported but switched off in Batch_zoho_modules
# + identityScopeFields - Guest Identity Resolution (plan v2.1): also send each guest's booking source
# code and agency name to the guest service, which needs them for the direct-scope filter. Off = the
# guest request is exactly what it was
public type SyncSettings record {|
    string mode = "delta";
    int pageSize = 100;
    int chunkSize = 50;
    string fromDate = "";
    string toDate = "";
    int windowDays = 2;
    int deltaFromMinutes = 5;
    int deltaToMinutes = 2;
    string errorTable = "";
    int retryCount = 3;
    decimal retryWaitSeconds = 5;
    string[] retryErrorTypes = ["BAD_GATEWAY", "CONNECTIVITY", "TIMEOUT", "GATEWAY_TIMEOUT", "INTERNAL_SERVER_ERROR",
        "RETRY_EXHAUSTED"];
    boolean writeShorex = false;
    boolean identityScopeFields = false;
|};

# CRM paths the job writes to and searches (sent to the CRM system service in the `zohoPath` header).
#
# + reservations - Reservation upsert
# + invoices - Invoice upsert
# + voyages - Voyage upsert
# + cabinInfo - Cabin upsert
# + cabinInfoSearch - Cabin search
# + addons - Add-on upsert
# + addonsSearch - Add-on search
# + groupAgency - Group and agency upsert
# + reservationLinking - Reservation-to-guest links (create and update)
# + reservationLinkingSearch - Reservation-to-guest link search
# + shorex - Shore excursion upsert (old `httpRequest.zohoCRM.shorexPath`)
# + shorexSearch - Shore excursion search
public type CrmPaths record {|
    string reservations = "/crm/v6/Accounts/upsert";
    string invoices = "/crm/v6/Finance/upsert";
    string voyages = "/crm/v6/Voyages/upsert";
    string cabinInfo = "/crm/v6/Cabin_Info/upsert";
    string cabinInfoSearch = "/crm/v6/Cabin_Info/search";
    string addons = "/crm/v6/Addons/upsert";
    string addonsSearch = "/crm/v6/Addons/search";
    string groupAgency = "/crm/v6/Group_Agency/upsert";
    string reservationLinking = "/crm/v2/Reservation_Names";
    string reservationLinkingSearch = "/crm/v6/Reservation_Names/search";
    string shorex = "/crm/v6/Shorex/upsert";
    string shorexSearch = "/crm/v6/Shorex/search";
|};

# One block of reservations on its way through the CRM steps, with what each step answered.
#
# + edges - The reservations as Seaware returned them
# + correlationId - Run id
# + jobName - Written to error rows
# + reservationAnswer - CRM answer to the reservation write
# + contactAnswers - Per reservation: the guest service's answer (one entry per guest)
# + cabinCorrelation - Per reservation: the cabins written and their CRM ids
# + groupAnswer - CRM answer to the group and agency write
# + voyageAnswers - Per reservation: CRM answer to the voyage write
# + invoiceAnswer - CRM answer to the invoice write
public type Chunk record {|
    json[] edges;
    string correlationId;
    string jobName;
    json reservationAnswer = ();
    json[] contactAnswers = [];
    json[] cabinCorrelation = [];
    json groupAnswer = ();
    json[] voyageAnswers = [];
    json invoiceAnswer = ();
|};

# Records that belong to one reservation and are written together.
#
# + key - Reservation number
# + records - Records, including ones marked as not writable
public type Group record {|
    string key;
    json[] records;
|};

# Reservation-to-guest links to create and to update, one request body per reservation.
#
# + creates - Bodies to POST
# + updates - Bodies to PUT
public type LinkingPlan record {|
    json[] creates = [];
    json[] updates = [];
|};
