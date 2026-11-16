import aroya/integration_commons as commons;
import db_sys_api.core;

// Settings of the database system API. Values live in Config.toml
// (deploy/vm/config/db-sys-api.toml). The database settings may be left without a value: the
// service starts, answers its health check, and answers a call with 503 and the names of the
// settings that are missing.

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/db-system-api/v1";

# The PostgreSQL database both accounts connect to (old: postgresDB.url).
configurable core:DatabaseSettings database = {};
# Account behind connectionKey "PG_ShipTracking" (old: postgresDB.shipTracking.user / password).
configurable core:AccountSettings shipTracking = {};
# Account behind connectionKey "PG_Guest" (old: postgresDB.guest.user / password).
configurable core:AccountSettings guest = {};

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};
