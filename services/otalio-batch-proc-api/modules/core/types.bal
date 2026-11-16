# Switch and pace of the timed job.
#
# + enabled - false: the job is not started and nothing is connected or called
# + intervalSeconds - Pause between two runs
# + startDelaySeconds - Wait before the first run
public type TimerSettings record {|
    boolean enabled = false;
    decimal intervalSeconds = 200;
    decimal startDelaySeconds = 0;
|};

# The Otalio database the job reads from (MySQL). Read only: the job runs SELECT statements.
#
# + host - Server ("" = not set)
# + port - Port
# + username - User
# + password - Password
# + database - Default schema ("" for none; the queries name their schemas)
# + connectTimeoutSeconds - How long to wait for a connection
public type DbSettings record {|
    string host = "";
    int port = 3306;
    string username = "";
    string password = "";
    string database = "";
    decimal connectTimeoutSeconds = 10;
|};

# How the job reads and retries.
#
# + mode - "delta": follow the clock; anything else: walk from `fromDate` to `toDate`
# + chunkSize - Bookings read and written per block
# + blockSize - Most records in one CRM write
# + skipBookingNumbers - Booking numbers left out, as an SQL list, e.g. ('1','2')
# + fromDate - Start of the fixed range
# + toDate - End of the fixed range
# + windowDays - Step of the fixed range, in days
# + deltaFromMinutes - Minutes before now a "delta" slice starts
# + deltaToMinutes - Minutes after now a "delta" slice ends
# + errorTable - Table that failed records are written to
# + retryCount - Extra tries for a failed call
# + retryWaitSeconds - Pause between tries
# + retryErrorTypes - Kinds of failure that are tried again
public type SyncSettings record {|
    string mode = "delta";
    int chunkSize = 20;
    int blockSize = 99;
    string skipBookingNumbers = "('')";
    string fromDate = "";
    string toDate = "";
    int windowDays = 1;
    int deltaFromMinutes = 5;
    int deltaToMinutes = 2;
    string errorTable = "";
    int retryCount = 3;
    decimal retryWaitSeconds = 5;
    string[] retryErrorTypes = ["BAD_GATEWAY", "CONNECTIVITY", "TIMEOUT", "GATEWAY_TIMEOUT", "INTERNAL_SERVER_ERROR",
        "RETRY_EXHAUSTED"];
|};

# CRM paths the job writes to and searches (sent to the CRM system service in the `zohoPath` header).
#
# + coql - Query endpoint (voyage look-up by dates)
# + accountSearch - Reservation search (mismatch report)
# + reservations - Reservation upsert
# + voyages - Voyage upsert
# + cabinInfo - Cabin upsert
# + cabinInfoSearch - Cabin search
# + reservationLinking - Reservation-to-guest links (create and update)
# + reservationLinkingSearch - Reservation-to-guest link search
# + spendTransactions - Spend transaction upsert
# + spendItems - Spend item upsert
public type CrmPaths record {|
    string coql = "/crm/v8/coql";
    string accountSearch = "/crm/v6/Accounts/search";
    string reservations = "/crm/v6/Accounts/upsert";
    string voyages = "/crm/v6/Voyages/upsert";
    string cabinInfo = "/crm/v6/Cabin_Info/upsert";
    string cabinInfoSearch = "/crm/v6/Cabin_Info/search";
    string reservationLinking = "/crm/v2/Reservation_Names";
    string reservationLinkingSearch = "/crm/v6/Reservation_Names/search";
    string spendTransactions = "/crm/v6/Spend_Transactions/upsert";
    string spendItems = "/crm/v6/Spend_Item/upsert";
|};

# One block of guest rows on its way through the CRM steps, with what each step answered.
#
# + rows - Guest rows from the Otalio database (one per guest of a booking), each with its
# `revenue` rows and its `transactions` (each transaction with its `items`)
# + correlationId - Run id
# + jobName - Written to error rows
# + reservationData - Per row: the CRM's answer entry to the reservation write
# + guestAnswers - Per row: the guest service's answer entry
# + crmVoyages - CRM voyages found for the rows' dates (`Arrival_Date`, `Departure_Date`, `Package_Key`)
# + spendAnswers - Per row: the CRM's answer entries to its spend transactions
# + voyageData - Per row: the CRM's answer entry to the voyage write
public type Block record {|
    json[] rows;
    string correlationId;
    string jobName;
    json[] reservationData = [];
    json[] guestAnswers = [];
    json[] crmVoyages = [];
    json[][] spendAnswers = [];
    json[] voyageData = [];
|};

# Records that belong to one booking and are written together.
#
# + key - Booking number
# + records - Records
public type Group record {|
    string key;
    json[] records;
|};

# Reservation-to-guest links to create and to update; every entry is one request body with one link.
#
# + creates - Bodies to POST
# + updates - Bodies to PUT
public type LinkingPlan record {|
    json[] creates = [];
    json[] updates = [];
|};

# The spend items of one transaction.
#
# + row - The guest row the transaction belongs to
# + sourceItems - The items as read from the database, those that are written
# + records - What is written to the CRM, same sequence as `sourceItems`
public type ItemGroup record {|
    json row;
    json[] sourceItems;
    json[] records;
|};
