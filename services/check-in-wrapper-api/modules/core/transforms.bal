// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `fetchNewToken` / request bodies and answers (javascript, 22 lines).
# Output fields: clientId, clientSecret.
#
# + input - The source payload
# + return - The mapped value
public isolated function fetchNewTokenRequestBodiesAndAnswers(json input) returns json {
// async function fetchNewToken() {
//   const url = process.env.TOKEN_URL;
// 
//   const body = {
//     clientId: process.env.CLIENT_ID,
//     clientSecret: process.env.CLIENT_SECRET
//   };
// 
//   const response = await axios.post(url, body, {
//     headers: { "Content-Type": "application/json" }
//   });
// 
//   const token = response.data.responsePayload.access_token;
// 
//   // Token expiration: 15 min = 900 sec → subtract 30 sec for safety
//   const expiresIn = 900 - 30;
// 
//   cachedToken = token;
//   tokenExpiry = Date.now() + expiresIn * 1000;
// 
//   return cachedToken;
// }
    return input;
}

# Source: `fetchNewToken` / request bodies and answers (javascript, 43 lines).
# Output fields: clientId, clientSecret.
#
# + input - The source payload
# + return - The mapped value
public isolated function fetchNewTokenRequestBodiesAndAnswersX(json input) returns json {
// async function fetchNewToken() {
//   const url = process.env.TOKEN_URL_PROD;
// 
//   const body = {
//     clientId: process.env.CLIENT_ID_PROD,
//     clientSecret: process.env.CLIENT_SECRET_PROD
//   };
//   try {
//     const response = await axios.post(url, body, {
//       headers: { "Content-Type": "application/json" }
//     });
// 
//     const token = response?.data?.responsePayload?.access_token;
// 
//     if (!token) {
//       throw new Error("Error: Token missing in response");
//     }
// 
//     // Token expiration: subtract 30 sec for safety
//     const expiresIn = response?.data?.responsePayload?.expires_in - 30;
// 
//     cachedToken = token;
//     tokenExpiry = Date.now() + expiresIn * 1000;
// 
//     return cachedToken;
//   } catch (err) {
//     if (err.response) {
//       const status = err.response.status;
//       const apiMessage =
//         err.response.data?.error ||
//         err.response.data?.message ||
//         "Token API error";
// 
//       const error = new Error(apiMessage);
//       error.statusCode = status;
//       throw error;
//     }
// 
//     const error = new Error(err.message || "Token API failure");
//     error.statusCode = 500;
//     throw error;
//   }
// }
    return input;
}

# Source: `fetchNewToken` / request bodies and answers (javascript, 43 lines).
# Output fields: clientId, clientSecret.
#
# + input - The source payload
# + return - The mapped value
public isolated function fetchNewTokenRequestBodiesAndAnswersXX(json input) returns json {
// async function fetchNewToken(uat = '') {
//   let url = process.env.TOKEN_URL;
// 
//   const body = {
//     clientId: process.env.CLIENT_ID,
//     clientSecret: process.env.CLIENT_SECRET
//   };
//   try {
//     const response = await axios.post(url, body, {
//       headers: { "Content-Type": "application/json" }
//     });
// 
//     const token = response?.data?.responsePayload?.access_token;
// 
//     if (!token) {
//       throw new Error("Error: Token missing in response");
//     }
// 
//     // Token expiration: subtract 30 sec for safety
//     const expiresIn = response?.data?.responsePayload?.expires_in - 30;
// 
//     cachedToken = token;
//     tokenExpiry = Date.now() + expiresIn * 1000;
// 
//     return cachedToken;
//   } catch (err) {
//     if (err.response) {
//       const status = err.response.status;
//       const apiMessage =
//         err.response.data?.error ||
//         err.response.data?.message ||
//         "Token API error";
// 
//       const error = new Error(apiMessage);
//       error.statusCode = status;
//       throw error;
//     }
// 
//     const error = new Error(err.message || "Token API failure");
//     error.statusCode = 500;
//     throw error;
//   }
// }
    return input;
}

# Source: `checkInInfo` / request bodies and answers (javascript, 18 lines).
# Output fields: success, message.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInInfoRequestBodiesAndAnswers(json input) returns json {
// export const checkInInfo = async (req, res, next) => {
//     try {
//         const { error, value } = checkInInfoSchema.validate(req.body);
//         if (error) {
//             return res.status(400).json({ success: false, message: error.details[0].message.replace(/\"/g, '') });
//         }
//         req.body = value;
//         const result = await checkInInfoService.checkInInfo(req);
//         res.status(201).json({success: true, message: getMessage(req.lang, "SUCCESS.RECORD_CREATED")});
//     } catch (error) {
//         console.log('checkInInfo.controller.error: ', error);
//         if(error.code == '23505') {
//             res.status(400).json({success: false, message: getMessage(req.lang, "ERROR.DUPLICATE_KEY_ERROR")});
//         } else {
//             res.status(500).json({success: false, message: getMessage(req.lang, "ERROR.SERVER_ERROR")});
//         }
//     }
// }
    return input;
}

# Source: `checkInSubmit` / request bodies and answers (javascript, 45 lines).
# Output fields: success, message, stage, failedSteps, checkInMarked, ticketId.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInSubmitRequestBodiesAndAnswers(json input) returns json {
// export const checkInSubmit = async (req, res, next) => {
//     try {
//         const { error: bodyError, value } = checkInSubmitSchema.validate(req.body);
//         if (bodyError) {
//             return res.status(400).json({
//                 success: false,
//                 message: bodyError.details[0].message.replace(/\"/g, '')
//             });
//         }
// 
//         req.body = value;
//         const result = await checkInSubmitService.checkInSubmit(req);
//         if(result.response && result.response.message && result.response.message.key && result.response.message.key === "ERROR.BOARDING_PASS_PROCESSING") {
//             if(result.response.message.guestName) {
//                 result.response.message = getMessage(req.lang, "ERROR.BOARDING_PASS_PROCESSING_WITH_GUEST_NAME").replace("[guest_name]", result.response.message.guestName);
//             } else {
//                 result.response.message = getMessage(req.lang, result.response.message.key);
//             }
//         }
//         return res.status(result.statusCode).json(result.response);
//     } catch (error) {
//         logger.error({
//             module: "CHECKIN_SUBMIT_CONTROLLER",
//             error: error.message,
//             stack: error.stack
//         });
// 
//         if (error.code === '23505') {
//             return res.status(400).json({
//                 success: false,
//                 message: getMessage(req.lang, "ERROR.DUPLICATE_KEY_ERROR")
//             });
//         }
// 
//         const statusCode = error.status || error.statusCode || 500;
//         return res.status(statusCode).json({
//             success: false,
//             stage: "ERROR",
//             failedSteps: [],
//             checkInMarked: false,
//             ticketId: null,
//             message: error.message || getMessage(req.lang, "ERROR.SERVER_ERROR")
//         });
//     }
// }
    return input;
}

# Source: `checkInStatus` / request bodies and answers (javascript, 32 lines).
# Output fields: success, message.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInStatusRequestBodiesAndAnswers(json input) returns json {
// export const checkInStatus = async (req, res, next) => {
//     try {
//         const { error: queryError } = checkInStatusSchema.validate(req.query);
//         if (queryError) {
//             return res.status(400).json({
//                 success: false,
//                 message: queryError.details[0].message.replace(/\"/g, '')
//             });
//         }
//         const result = await checkInSubmitService.checkInStatus(req);
//         if(result.response && result.response.message && result.response.message.key && result.response.message.key === "ERROR.BOARDING_PASS_PROCESSING") {
//             if(result.response.message.guestName) {
//                 result.response.message = getMessage(req.lang, "ERROR.BOARDING_PASS_PROCESSING_WITH_GUEST_NAME").replace("[guest_name]", result.response.message.guestName);
//             } else {
//                 result.response.message = getMessage(req.lang, result.response.message.key);
//             }
//         }
//         return res.status(result.statusCode).json(result.response);
//     } catch (error) {
//         logger.error({
//             module: "CHECKIN_STATUS_CONTROLLER",
//             error: error.message,
//             stack: error.stack
//         });
// 
//         const statusCode = error.status || error.statusCode || 500;
//         return res.status(statusCode).json({
//             success: false,
//             message: error.message || getMessage(req.lang, "ERROR.SERVER_ERROR")
//         });
//     }
// }
    return input;
}

# Source: `checkInReset` / request bodies and answers (javascript, 26 lines).
# Output fields: success, message.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInResetRequestBodiesAndAnswers(json input) returns json {
// export const checkInReset = async (req, res, next) => {
//     try {
//         const { error: bodyError } = checkInResetSchema.validate(req.body);
//         if (bodyError) {
//             return res.status(400).json({
//                 success: false,
//                 message: bodyError.details[0].message.replace(/\"/g, '')
//             });
//         }
// 
//         const result = await checkInSubmitService.checkInReset(req);
//         return res.status(result.statusCode).json(result.response);
//     } catch (error) {
//         logger.error({
//             module: "CHECKIN_RESET_CONTROLLER",
//             error: error.message,
//             stack: error.stack
//         });
// 
//         const statusCode = error.status || error.statusCode || 500;
//         return res.status(statusCode).json({
//             success: false,
//             message: error.message || getMessage(req.lang, "ERROR.SERVER_ERROR")
//         });
//     }
// }
    return input;
}

# Source: `manualCheckInRetry` / request bodies and answers (javascript, 13 lines).
# Output fields: success, message.
#
# + input - The source payload
# + return - The mapped value
public isolated function manualCheckInRetryRequestBodiesAndAnswers(json input) returns json {
// export const manualCheckInRetry = async (req, res) => {
//     const { error: bodyError } = manualCheckInRetrySchema.validate(req.body || {});
//     if (bodyError) {
//         return res.status(400).json({ success: false, message: bodyError.details[0].message.replace(/\"/g, '') });
//     }
//     try {
//         const result = await manualRetryFailedCheckIns(req);
//         return res.status(result.statusCode).json(result.response);
//     } catch (error) {
//         logger.error({ module: "CHECKIN_MANUAL_RETRY_CONTROLLER", error: error.message, stack: error.stack });
//         return res.status(500).json({ success: false, message: "Manual check-in retry failed" });
//     }
// }
    return input;
}

# Source: `notifyCheckInSuccessIfNeeded` / request bodies and answers (javascript, 183 lines).
# Output fields: notified, reason, pushResult, error.
#
# + input - The source payload
# + return - The mapped value
public isolated function notifyCheckInSuccessIfNeededRequestBodiesAndAnswers(json input) returns json {
// export async function notifyCheckInSuccessIfNeeded({
//     reservationId,
//     bookingNumber,
//     headerDetails = null,
//     priorStatus = null,
//     payload = null,
//     isSweep = false
// }) {
//     if (!reservationId || !bookingNumber) {
//         logger.warn({
//             module: "CHECKIN_NOTIFICATION",
//             stage: "VALIDATION",
//             message: "Missing reservationId or bookingNumber"
//         });
//         return { notified: false, reason: "MISSING_IDENTIFIERS" };
//     }
// 
//     try {
//         // 1. Check current database row
//         const selectSql = `
//             SELECT fcm_notified_at, header_details, payload, status
//             FROM app.guest_check_in
//             WHERE reservation_id = $1 AND booking_number = $2
//             LIMIT 1`;
//         const res = await poolQuery(selectSql, [reservationId, bookingNumber]);
// 
//         if (!res.rows || res.rows.length === 0) {
//             logger.warn({
//                 module: "CHECKIN_NOTIFICATION",
//                 stage: "FETCH_ROW",
//                 message: "Check-in record not found in DB",
//                 reservationId,
//                 bookingNumber
//             });
//             return { notified: false, reason: "ROW_NOT_FOUND" };
//         }
// 
//         const row = res.rows[0];
// 
//         // 2. If already stamped / notified, exit cleanly (idempotent)
//         if (row.fcm_notified_at) {
//             logger.info({
//                 module: "CHECKIN_NOTIFICATION",
//                 stage: "IDEMPOTENCY_CHECK",
//                 message: "Record already stamped with fcm_notified_at, skipping",
//                 reservationId,
//                 bookingNumber,
//                 fcm_notified_at: row.fcm_notified_at
//             });
//             return { notified: false, reason: "ALREADY_NOTIFIED" };
//         }
// 
//         // 3. Determine if this is a delayed / recovered SUCCESS or a clean first-attempt
//         const isRecovered = isSweep || ["FAILED", "RETRYING", "IN_PROCESS", "SWEEP"].includes(priorStatus);
// 
//         if (!isRecovered) {
//             // First-attempt SUCCESS: HTTP response already acknowledged client.
//             // Stamp fcm_notified_at = NOW() without pushing FCM.
//             const stampSql = `
//                 UPDATE app.guest_check_in
//                 SET fcm_notified_at = NOW()
//                 WHERE reservation_id = $1 AND booking_number = $2 AND fcm_notified_at IS NULL`;
//             await clientQuery(stampSql, [reservationId, bookingNumber]);
// 
//             logger.info({
//                 module: "CHECKIN_NOTIFICATION",
//                 action: "FIRST_ATTEMPT_STAMPED",
//                 message: "Clean first-attempt SUCCESS stamped without FCM push",
//                 reservationId,
//                 bookingNumber,
//                 priorStatus
//             });
// 
//             return { notified: false, reason: "FIRST_ATTEMPT_STAMPED" };
//         }
// 
//         // 4. Delayed / Recovered SUCCESS / Safety Sweep -> Resolve device & send push
//         const mergedHeaders = headerDetails || row.header_details || {};
//         const deviceId =
//             mergedHeaders.client_deviceId ||
    return input;
}

# Source: `manualRetryFailedCheckIns` / request bodies and answers (javascript, 120 lines).
# Output fields: statusCode, response, success, message, attempted, succeeded, failed.
#
# + input - The source payload
# + return - The mapped value
public isolated function manualRetryFailedCheckInsRequestBodiesAndAnswers(json input) returns json {
// export async function manualRetryFailedCheckIns(data) {
//     const reservationId = data?.body?.reservationId;
//     const bookingNumber = data?.body?.bookingNumber;
//     const params = [];
//     let filter = "retry_count >= COALESCE(max_retry_count, 6)";
// 
//     if (reservationId) {
//         params.push(reservationId);
//         filter = `reservation_id = $${params.length}`;
//     } else if (bookingNumber) {
//         params.push(bookingNumber);
//         filter = `booking_number = $${params.length}`;
//     }
// 
//     let candidates;
//     try {
//         const result = await poolQuery(
//             `SELECT reservation_id, booking_number FROM app.guest_check_in
//               WHERE status != 'SUCCESS' AND ${filter}
//               ORDER BY updated_date ASC`,
//             params
//         );
//         candidates = result.rows || [];
//     } catch (error) {
//         logger.error({ module: "CHECKIN_MANUAL_RETRY", stage: "FETCH_ROWS", error: error.message });
//         return { statusCode: 500, response: { success: false, message: "Unable to fetch failed check-ins" } };
//     }
// 
//     if (!candidates.length) {
//         return { statusCode: 200, response: { success: true, attempted: 0, succeeded: 0, failed: 0 } };
//     }
// 
//     try {
//         const claim = await poolQuery(
//             `UPDATE app.checkin_retry_config
//                 SET triggered = TRUE, triggered_at = NOW()
//               WHERE config_key = 'manual_checkin_retry' AND triggered = FALSE
//           RETURNING config_key`,
//             []
//         );
//         if (!claim.rows.length) {
//             return {
//                 statusCode: 409,
//                 response: { success: false, message: "Manual check-in retry has already been triggered" }
//             };
//         }
//     } catch (error) {
//         logger.error({ module: "CHECKIN_MANUAL_RETRY", stage: "CLAIM_TRIGGER", error: error.message });
//         return { statusCode: 500, response: { success: false, message: "Unable to claim manual retry" } };
//     }
// 
//     try {
//         let attempted = 0;
//         let succeeded = 0;
//         for (const candidate of candidates) {
//             let row;
//             try {
//                 const claimed = await poolQuery(
//                     `UPDATE app.guest_check_in
//                         SET status = 'RETRYING',
//                             manual_retry_cycle = manual_retry_cycle + 1,
//                             manual_retry_count = manual_retry_count + 1,
//                             updated_date = NOW()
//                      WHERE reservation_id = $1 AND booking_number = $2
//                   RETURNING reservation_id, booking_number, payload, header_details, correlation_id`,
//                     [candidate.reservation_id, candidate.booking_number]
//                 );
//                 row = claimed.rows[0];
//             } catch (error) {
//                 logger.error({ module: "CHECKIN_MANUAL_RETRY", stage: "CLAIM_ROW", error: error.message });
//                 continue;
//             }
//             if (!row) continue;
// 
//             attempted++;
//             try {
//                 const result = await checkInSubmit({
//                     body: typeof row.payload === "string" ? JSON.parse(row.payload) : row.payload,
//                     clientInfo: typeof row.header_details === "string" ? JSON.parse(row.header_details) : row.header_details || {},
//                     lang: "en",
    return input;
}

# Source: `resolveBaseUrls` / request bodies and answers (javascript, 7 lines).
# Output fields: spmsBaseUrl, mobileExpBaseUrl.
#
# + input - The source payload
# + return - The mapped value
public isolated function resolveBaseUrlsRequestBodiesAndAnswers(json input) returns json {
// function resolveBaseUrls() {
//     const isProdEnv = isProd();
//     const spmsBaseUrl = isProdEnv ? process.env.MULESOFT_API_URL_PROD : process.env.MULESOFT_API_URL;
//     const mobileExpBaseUrl = isProdEnv ? process.env.MOBILE_EXP_BASE_URL_PROD : process.env.MOBILE_EXP_BASE_URL_UAT;
// 
//     return { spmsBaseUrl, mobileExpBaseUrl };
// }
    return input;
}

# Source: `checkInSubmit` / request bodies and answers (javascript, 866 lines).
# Output fields: alias, placeOfBirth, preferredLanguage, personProfileId, primaryDocument, travelDocType, allowedDuration, birthPlace, documentHolderBirthDate, documentHolderFirstName, documentHolderGender, documentHolderLastName, documentHolderMiddleName, documentMrz1, documentMrz2, documentMrz3, documentNr, expiryDate, externalId, issueAuthority.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInSubmitRequestBodiesAndAnswersX(json input) returns json {
// export const checkInSubmit = async (data) => {
//     const startTime = Date.now();
//     const body = data.body || {};
//     const {
//         bookingNumber,
//         personProfileId,
//         reservationId,
//         personal = {},
//         contact = {},
//         address = {},
//         emergencyContact = {},
//         document = {}
//     } = body;
// 
//     const externalId = (body.externalId || "").trim();
//     const guestName = (body.guestName || "").trim();
//     const correlationId = randomUUID();
//     const errorId = randomUUID();
//     logger.info({
//         module: "CHECKIN_SUBMIT",
//         stage: "LOGGER",
//         status: "LOGGER.BEFORE",
//         key: "personal.placeOfBirth",
//         value: personal?.placeOfBirth,
//         bookingNumber,
//         reservationId
//     });
//     const rawPlaceOfBirth = filterAnonymized(personal.placeOfBirth || "");
//     const placeOfBirth = rawPlaceOfBirth
//         ? rawPlaceOfBirth
//             .replace(/[\(\),'&]/g, "")
//             .replace(/Å/g, "A")
//             .replace(/ç/g, "c")
//             .substring(0, 20)
//         : "";
//     logger.info({
//         module: "CHECKIN_SUBMIT",
//         stage: "LOGGER",
//         status: "LOGGER.AFTER",
//         key: "personal.placeOfBirth",
//         value: placeOfBirth,
//         bookingNumber,
//         reservationId
//     });        
//     const clientTimestamp = body.clientTimestamp || new Date().toISOString().replace('T', ',').substring(0, 19);
//     const headerDetails = getExternalApiHeaders(data.clientInfo || {});
//     
//     logger.info({
//         module: "CHECKIN_SUBMIT",
//         action: "START",
//         bookingNumber,
//         personProfileId,
//         reservationId
//     });
// 
//     // Capture initial DB status before any phase executes (to detect first-attempt vs recovery)
//     let initialStatus = null;
//     try {
//         const priorRow = await clientQuery(
//             `SELECT status, fcm_notified_at FROM app.guest_check_in WHERE reservation_id = $1 AND booking_number = $2 LIMIT 1`,
//             [reservationId, bookingNumber]
//         );
//         initialStatus = priorRow?.rows?.[0]?.status || null;
//     } catch (checkErr) {
//         logger.warn({ module: "CHECKIN_SUBMIT", stage: "CHECK_INITIAL_STATUS", error: checkErr.message });
//     }
// 
//     // 1. Resolve Credentials and Base URLs
//     let accessToken = null;
//     let clientId = "";
//     let clientSecret = "";
// 
//     if (isProd()) {
//         accessToken = await getValidToken();
//         clientId = process.env.CLIENT_ID_PROD;
//         clientSecret = process.env.CLIENT_SECRET_PROD;
//     } else {
//         accessToken = await getValidTokenUAT();
//         clientId = process.env.CLIENT_ID;
//         clientSecret = process.env.CLIENT_SECRET;
    return input;
}

# Source: `checkInStatus` / request bodies and answers (javascript, 78 lines).
# Output fields: statusCode, response, success, status, message, checkin_status, bookingNumber, successSteps, failedSteps, error, retryCount.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInStatusRequestBodiesAndAnswersX(json input) returns json {
// export const checkInStatus = async (req, res) => {
//     try {
//         const { reservationId } = req.query;
// 
//         const sql = `
//             SELECT reservation_id, booking_number, status, checkin_status, payload->>'guestName' AS guest_name,
//             success_steps, failed_steps, error_details, retry_count, updated_date
//             FROM app.guest_check_in WHERE reservation_id = $1 LIMIT 1`;
// 
//         const result = await clientQuery(sql, [reservationId]);
// 
//         if (result.rows.length === 0) {
//             return {
//                 statusCode: 200,
//                 response: {
//                     success: true,
//                     status: "NOT_FOUND",
//                     message: "No check-in record found"
//                 }
//             };
//         }
// 
//         const row = result.rows[0];
// 
//         // 1. SUCCESS: Return clean success status
//         if (row.status === "SUCCESS") {
//             return {
//                 statusCode: 200,
//                 response: {
//                     success: true,
//                     status: row.status,
//                     checkin_status: true,
//                     bookingNumber: row.booking_number,
//                     successSteps: row.success_steps,
//                     message: "Check-in completed successfully"
//                 }
//             };
//         }
// 
//         // 2. NEEDS_CORRECTION: Tells mobile app which step failed so user can fix it
//         if (row.status === "NEEDS_CORRECTION") {
//             return {
//                 statusCode: 200,
//                 response: {
//                     success: true,
//                     status: row.status,
//                     bookingNumber: row.booking_number,
//                     successSteps: row.success_steps,
//                     failedSteps: row.failed_steps,
//                     error: row.error_details,
//                     message: `Please update your information for: ${row.failed_steps?.join(", ")}`
//                 }
//             };
//         }
// 
//         // 3. FAILED (5xx / Timeout): Tell mobile app system is auto-retrying
//         return {
//             statusCode: 200,
//             response: {
//                 success: true,
//                 status: "RETRYING",
//                 bookingNumber: row.booking_number,
//                 successSteps: row.success_steps,
//                 failedSteps: row.failed_steps,
//                 retryCount: row.retry_count,
//                 message: getResponseMsg("FAILED", '', row.guest_name)
//             }
//         };
//     } catch (err) {
//         return {
//             statusCode: 500,
//             response: {
//                 success: false,
//                 message: err.message
//             }
//         };
//     }
// }
    return input;
}

# Source: `checkInReset` / request bodies and answers (javascript, 113 lines).
# Output fields: statusCode, response, success, message, resetCount, pmsRollbackCount, details.
#
# + input - The source payload
# + return - The mapped value
public isolated function checkInResetRequestBodiesAndAnswersX(json input) returns json {
// export const checkInReset = async (req) => {
//     try {
//         const body = req.body || {};
//         const { bookingNumber, reservationId } = body;
//         const headerDetails = getExternalApiHeaders(req.clientInfo || {});
// 
//         let accessToken = null;
//         let clientId = "";
//         let clientSecret = "";
// 
//         if (isProd()) {
//             accessToken = await getValidToken();
//             clientId = process.env.CLIENT_ID_PROD;
//             clientSecret = process.env.CLIENT_SECRET_PROD;
//         } else {
//             accessToken = await getValidTokenUAT();
//             clientId = process.env.CLIENT_ID;
//             clientSecret = process.env.CLIENT_SECRET;
//         }
// 
//         const { mobileExpBaseUrl } = resolveBaseUrls();
// 
//         const commonHeaders1 = {
//             ...headerDetails,
//             Authorization: `Bearer ${accessToken}`,
//             client_id: clientId,
//             client_secret: clientSecret
//         };
// 
//         let sql = "";
//         let params = [];
//         if (reservationId?.length && bookingNumber) {
//             sql = `SELECT * FROM app.guest_check_in WHERE reservation_id = ANY($1) AND booking_number = $2`;
//             params = [reservationId, bookingNumber];
//         } else if (reservationId?.length) {
//             sql = `SELECT * FROM app.guest_check_in WHERE reservation_id = ANY($1)`;
//             params = [reservationId];
//         } else {
//             sql = `SELECT * FROM app.guest_check_in WHERE booking_number = $1`;
//             params = [bookingNumber];
//         }
// 
//         const dbResult = await clientQuery(sql, params);
//         const rows = dbResult?.rows || [];
// 
//         if (rows.length === 0) {
//             return {
//                 statusCode: 404,
//                 response: {
//                     success: false,
//                     message: "No check-in record found to reset"
//                 }
//             };
//         }
// 
//         let pmsRollbackCount = 0;
//         const resetDetails = [];
// 
//         for (const row of rows) {
//             const w6ResultId = row.w6_result_id;
//             const rId = row.reservation_id;
//             const bNo = row.booking_number;
// 
//             if (w6ResultId) {
//                 try {
//                     const rollbackUrl = `${mobileExpBaseUrl}/pms/v1/custom-attribute-values/${w6ResultId}`;
//                     await axios.delete(rollbackUrl, { headers: commonHeaders1 });
//                     pmsRollbackCount++;
//                     logger.info({
//                         module: "CHECKIN_RESET",
//                         stage: "PMS_W6_ATTRIBUTE_DELETE",
//                         status: "SUCCESS",
//                         w6ResultId,
//                         bookingNumber: bNo,
//                         reservationId: rId
//                     });
//                 } catch (pmsErr) {
//                     logger.error({
//                         module: "CHECKIN_RESET",
//                         stage: "PMS_W6_ATTRIBUTE_DELETE",
    return input;
}

# Source: `personSearchInfo` / request bodies and answers (javascript, 80 lines).
# Output fields: embarkationInfo, checkInDetails, person.
#
# + input - The source payload
# + return - The mapped value
public isolated function personSearchInfoRequestBodiesAndAnswers(json input) returns json {
// export const personSearchInfo = async (data) => {
//     try {
//         const lang = data.lang || "en";
//         const queryParams = { ...(data.query || {}) };
//         const { booking_id } = queryParams;
//         delete queryParams.env;
// 
//         const headers = getExternalApiHeaders(data.clientInfo);
//         let access_token = null;
//         let baseUrl = '';
//         let voyage_itinerary_url = '';
//         if (isProd()) {
//             access_token = await getValidToken();
//             headers['client_id'] = process.env.CLIENT_ID_PROD;
//             headers['client_secret'] = process.env.CLIENT_SECRET_PROD;
//             baseUrl = `${process.env.PERSON_SEARCH_URL_PROD}`;
//             voyage_itinerary_url = `${process.env.VOYAGE_ITINERARY_URL_PROD}`;
//         } else {
//             access_token = await getValidTokenUAT();
//             headers['client_id'] = process.env.CLIENT_ID;
//             headers['client_secret'] = process.env.CLIENT_SECRET;
//             baseUrl = `${process.env.PERSON_SEARCH_URL_UAT}`;
//             voyage_itinerary_url = `${process.env.VOYAGE_ITINERARY_URL_UAT}`;
//         }
//         headers['Authorization'] = `Bearer ${access_token}`;
//         headers['first_name'] = data.headers?.['first_name'] || '';
//         headers['last_name'] = data.headers?.['last_name'] || '';
//         headers['method'] = data.headers?.['method'] || '';
// 
//         if (!queryParams.search && booking_id) {
//             queryParams.search = `bookingNumber=="${booking_id}"`;
//             delete queryParams.booking_id;
//         }
// 
//         queryParams.forcePopulate = true;
// 
//         const response = await axios.get(baseUrl, { headers, params: queryParams });
//         const persons = response.data?.responsePayload?.content || [];
//         const embarkationDetails = await getEmbarkationDetails(headers, lang);
//         const reservationIds = persons?.map(person => person.reservationId).filter(Boolean);
//         const checkInDetails = await getCheckInDetails(reservationIds, booking_id);
//         if (response.data?.responsePayload) {
//             response.data.responsePayload.content = persons?.map((person) => {
//                 const portCode = person?.embarkation?.port?.code;
//                 const cabinCode = person?.cabin?.category?.code;
//                 const deckCode = person?.cabin?.deck?.code;
//                 const date = person?.embarkation?.scheduledDate;
//                 const key = `${portCode}_${cabinCode}_${deckCode}_${date}`;
//                 const embarkationInfo = embarkationDetails.get(key);
//                 return {
//                     ...person,
//                     embarkationInfo: embarkationInfo || null,
//                     checkInDetails: checkInDetails.find(detail => detail.reservationId === person.reservationId)?.checkInDetails || null
//                 };
//             });
//         }
//         
//         let packageCode = persons?.[0]?.cruiseProduct;
//         if (packageCode) {
//             const response1 = await axios.get(`${voyage_itinerary_url}&search=code==${packageCode}`, { headers });
//             let voyagesresponse1 = response1.data?.responsePayload?.content || [];
//             console.log(`package code ${packageCode} --> itinerary-voyages-api --> voyagesresponse1.length: ${voyagesresponse1.length}`);
//             if (voyagesresponse1.length > 0 && response.data?.responsePayload?.content?.[0]) {
//                 const countryId = await getCountryId(headers);
//                 const voyageDays = voyagesresponse1[0].voyageDays || [];
//                 const travelEgyptDay = voyageDays.find(day => day.countryId === countryId);
//                 response.data.responsePayload.content[0].travelEgypt = travelEgyptDay ? true : false;
//             }
//         }
//         const responsePayload = response.data?.responsePayload || {};
//         const { content, ...paginationData } = responsePayload;
//         return {
//             person: responsePayload?.content || [],
//             ...paginationData
//         };
//     } catch (error) {
//         console.log("mobile.personSearchInfo.service.error: ", error);
//         throw error;
//     }
// }
    return input;
}

# Source: `sendWalletPassUpdatePush` / request bodies and answers (javascript, 37 lines).
# Output fields: sent, failed.
#
# + input - The source payload
# + return - The mapped value
public isolated function sendWalletPassUpdatePushRequestBodiesAndAnswers(json input) returns json {
// export const sendWalletPassUpdatePush = async (pushTokens = []) => {
//     const tokens = [...new Set(pushTokens.filter(Boolean))];
//     if (!tokens.length) {
//         return { sent: 0, failed: [] };
//     }
// 
//     const apnProvider = getProvider();
//     if (!apnProvider) {
//         return { sent: 0, failed: tokens.map((token) => ({ token, reason: "APNs not configured" })) };
//     }
// 
//     const topic = process.env.APNS_PASS_TOPIC || PASS_TYPE_IDENTIFIER;
//     const notification = new apn.Notification();
//     notification.topic = topic;
//     notification.rawPayload = { aps: {} };
//     notification.pushType = "background";
//     notification.priority = 5;
//     notification.expiry = 0;
// 
//     const result = await apnProvider.send(notification, tokens);
//     const failed = (result.failed || []).map((item) => ({
//         token: item.device,
//         reason: item.response?.reason || item.error?.message || "unknown"
//     }));
// 
//     console.log("passkit.apns.sendWalletPassUpdatePush", {
//         topic,
//         sent: tokens.length - failed.length,
//         failed: failed.length,
//         reasons: failed.map((item) => item.reason)
//     });
// 
//     return {
//         sent: tokens.length - failed.length,
//         failed
//     };
// }
    return input;
}

# Source: `rebuildPayload` / request bodies and answers (javascript, 40 lines).
# Output fields: bookingId, reservationId, guestName, env.
#
# + input - The source payload
# + return - The mapped value
public isolated function rebuildPayloadRequestBodiesAndAnswers(json input) returns json {
// const rebuildPayload = async (passRow, overrides = {}) => {
//     const currentPayload = passRow.payload_json || {};
//     const nextPayload = {
//         ...currentPayload,
//         ...overrides,
//         bookingId: overrides.bookingId || currentPayload.bookingId || passRow.booking_id,
//         reservationId: overrides.reservationId || currentPayload.reservationId || passRow.reservation_id,
//         guestName: overrides.guestName || currentPayload.guestName,
//         env: passRow.env
//     };
// 
//     let externalId =
//         overrides.externalId ||
//         passRow.external_id ||
//         currentPayload.externalId;
// 
//     if (!externalId) {
//         try {
//             externalId = await resolvePersonExternalId({
//                 env: passRow.env,
//                 bookingId: nextPayload.bookingId,
//                 reservationId: nextPayload.reservationId,
//                 guestName: nextPayload.guestName,
//                 lang: overrides.lang || currentPayload.lang,
//                 clientInfo: overrides.clientInfo || currentPayload.clientInfo
//             });
//         } catch (resolveErr) {
//             console.log(`passUpdate.resolvePersonExternalId.${passRow.serial_number}.warn:`, resolveErr.message);
//         }
//     }
// 
//     if (!externalId) {
//         const error = new Error(`externalId not found for wallet pass ${passRow.serial_number}`);
//         error.statusCode = 404;
//         throw error;
//     }
// 
//     nextPayload.externalId = externalId;
//     return nextPayload;
// }
    return input;
}

# Source: `notifyAllPassesUpdated` / request bodies and answers (javascript, 44 lines).
# Output fields: updated, pushed, serialNumbers, failed, error.
#
# + input - The source payload
# + return - The mapped value
public isolated function notifyAllPassesUpdatedRequestBodiesAndAnswers(json input) returns json {
// export const notifyAllPassesUpdated = async ({ env } = {}) => {
//     const targetEnv = (env || getAppEnv()).toLowerCase();
//     if (!targetEnv) {
//         const error = new Error("env is required to notify all wallet pass updates");
//         error.statusCode = 400;
//         throw error;
//     }
// 
//     let passes = [];
//     try {
//         passes = await findWalletPasses({ env: targetEnv, all: true });
//     } catch (error) {
//         console.log(`passkit.notifyAllPassesUpdated.findWalletPasses.${targetEnv}.error:`, error.message);
//         return { updated: 0, pushed: 0, serialNumbers: [], failed: [], error: error.message };
//     }
// 
//     if (!passes.length) {
//         return { updated: 0, pushed: 0, serialNumbers: [], failed: [] };
//     }
// 
//     let pushed = 0;
//     const serialNumbers = [];
//     const failed = [];
// 
//     for (const pass of passes) {
//         try {
//             await touchWalletPassUpdatedAt(pass.serial_number, targetEnv);
//             const tokens = await getPushTokensForSerial(pass.serial_number, targetEnv);
//             const pushResult = await sendWalletPassUpdatePush(tokens);
//             pushed += pushResult.sent || 0;
//             serialNumbers.push(pass.serial_number);
//         } catch (error) {
//             console.log(`passkit.notifyAllPassesUpdated.${pass.serial_number}.error:`, error.message);
//             failed.push({ serialNumber: pass.serial_number, reason: error.message });
//         }
//     }
// 
//     return {
//         updated: serialNumbers.length,
//         pushed,
//         serialNumbers,
//         failed
//     };
// }
    return input;
}

# Source: `notifyPassUpdated` / request bodies and answers (javascript, 67 lines).
# Output fields: updated, pushed, serialNumbers, error.
#
# + input - The source payload
# + return - The mapped value
public isolated function notifyPassUpdatedRequestBodiesAndAnswers(json input) returns json {
// export const notifyPassUpdated = async ({
//     env,
//     serialNumber,
//     bookingId,
//     reservationId,
//     refreshAll = false,
//     payloadOverrides = {},
//     lang,
//     clientInfo
// } = {}) => {
//     const normalizedSerial = serialNumber ? normalizeSerialNumber(serialNumber) : serialNumber;
//     const resolvedEnv = (env || parseEnvFromSerialNumber(normalizedSerial) || getAppEnv()).toLowerCase();
// 
//     if (refreshAll) {
//         return notifyAllPassesUpdated({ env: resolvedEnv });
//     }
// 
//     let passes = [];
//     try {
//         passes = await findWalletPasses({
//             env: resolvedEnv,
//             bookingId,
//             reservationId,
//             serialNumber: normalizedSerial
//         });
//     } catch (error) {
//         // e.g. wallet tables not migrated on this env yet
//         console.log(`passkit.notifyPassUpdated.findWalletPasses.${resolvedEnv}.error:`, error.message);
//         return { updated: 0, pushed: 0, serialNumbers: [], error: error.message };
//     }
// 
//     if (!passes.length) {
//         return { updated: 0, pushed: 0, serialNumbers: [] };
//     }
// 
//     let pushed = 0;
//     const serialNumbers = [];
// 
//     for (const pass of passes) {
//         const nextPayload = await rebuildPayload(pass, {
//             ...payloadOverrides,
//             lang,
//             clientInfo
//         });
// 
//         await touchWalletPassUpdatedAt(pass.serial_number, resolvedEnv, {
//             ...nextPayload,
//             externalId: nextPayload.externalId
//         });
// 
//         await clientQuery(
//             `UPDATE app.wallet_pass SET external_id = $2 WHERE serial_number = $1`,
//             [pass.serial_number, nextPayload.externalId]
//         );
// 
//         const tokens = await getPushTokensForSerial(pass.serial_number, resolvedEnv);
//         const pushResult = await sendWalletPassUpdatePush(tokens);
//         pushed += pushResult.sent || 0;
//         serialNumbers.push(pass.serial_number);
//     }
// 
//     return {
//         updated: serialNumbers.length,
//         pushed,
//         serialNumbers
//     };
// }
    return input;
}

# Source: `getExternalApiHeaders` / request bodies and answers (javascript, 8 lines).
# Output fields: client_channel, client_deviceId, client_platform, client_appVer.
#
# + input - The source payload
# + return - The mapped value
public isolated function getExternalApiHeadersRequestBodiesAndAnswers(json input) returns json {
// export function getExternalApiHeaders(clientInfo = {}) {
//     return {
//         client_channel: clientInfo?.client_channel || "mobile",
//         client_deviceId: clientInfo?.client_deviceid || clientInfo?.client_deviceId || "server",
//         client_platform: clientInfo?.client_platform || "ios",
//         client_appVer: clientInfo?.client_appver || clientInfo?.client_appVer || "1.0.0",
//     };
// }
    return input;
}

# Source: `getGuestDeviceToken` / request bodies and answers (javascript, 90 lines).
# Output fields: connectionKey, query.
#
# + input - The source payload
# + return - The mapped value
public isolated function getGuestDeviceTokenRequestBodiesAndAnswers(json input) returns json {
// export async function getGuestDeviceToken({ deviceId }) {
//     if (!deviceId) {
//         logger.warn({
//             module: "GUEST_DEVICE_TOKEN",
//             stage: "VALIDATION",
//             message: "Missing deviceId for FCM token resolution"
//         });
//         return null;
//     }
// 
//     const prod = isProd();
//     const dbSysUrl = prod
//         ? (process.env.DB_SYS_API_URL_PROD || "https://api.aroyacruises.com/db-sys-api/v1/db")
//         : (process.env.DB_SYS_API_URL_UAT || "https://uat-api.aroya.com/db-sys-api-uat/v1/db");
// 
//     try {
//         const token = prod ? await getValidToken() : await getValidTokenUAT();
//         const sanitizedDeviceId = String(deviceId).replace(/'/g, "''");
//         const query = `SELECT fcm_token, device_id FROM cs_guest_mgmt.cs_guest_device WHERE device_id = '${sanitizedDeviceId}' LIMIT 1`;
// 
//         const requestBody = {
//             connectionKey: "PG_Guest",
//             query
//         };
// 
//         const headers = {
//             Authorization: `Bearer ${token}`,
//             "Content-Type": "application/json",
//             Accept: "application/json"
//         };
// 
//         logger.info({
//             module: "GUEST_DEVICE_TOKEN",
//             action: "FETCH_TOKEN_START",
//             deviceId,
//             endpoint: dbSysUrl
//         });
// 
//         const response = await axios.post(dbSysUrl, requestBody, { headers, timeout: 5000 });
//         const responseData = response?.data;
// 
//         // Extract records from standard response formats
//         const records =
//             responseData?.responsePayload ||
//             responseData?.rows ||
//             responseData?.data ||
//             (Array.isArray(responseData) ? responseData : []);
// 
//         const firstRow = Array.isArray(records) ? records[0] : (records?.rows?.[0] || records);
// 
//         // Fallback for minor schema variations on UAT (fcm_token / fcmToken / device_token / token)
//         const fcmToken =
//             firstRow?.fcm_token ||
//             firstRow?.fcmToken ||
//             firstRow?.device_token ||
//             firstRow?.token ||
//             null;
// 
//         if (!fcmToken) {
//             logger.warn({
//                 module: "GUEST_DEVICE_TOKEN",
//                 status: "TOKEN_NOT_FOUND",
//                 deviceId,
//                 receivedRowKeys: firstRow && typeof firstRow === "object" ? Object.keys(firstRow) : null,
//                 recordsCount: Array.isArray(records) ? records.length : 0
//             });
//             return null;
//         }
// 
//         logger.info({
//             module: "GUEST_DEVICE_TOKEN",
//             status: "SUCCESS",
//             deviceId,
//             tokenPrefix: fcmToken.substring(0, 10)
//         });
// 
//         return fcmToken;
//     } catch (err) {
//         const statusCode = err.response?.status || 500;
//         const errMsg = err.response?.data?.message || err.response?.data?.error || err.message;
    return input;
}

# Source: `sendSinglePush` / request bodies and answers (javascript, 46 lines).
# Output fields: success, error, messageId, code, token, notification, title, body, data.
#
# + input - The source payload
# + return - The mapped value
public isolated function sendSinglePushRequestBodiesAndAnswers(json input) returns json {
// export async function sendSinglePush({ token, title, body, data = {} }) {
//     if (!token) {
//         logger.warn({
//             module: "FCM_SINGLE_PUSH",
//             status: "SKIPPED",
//             reason: "NO_FCM_TOKEN",
//             title
//         });
//         return { success: false, error: "NO_FCM_TOKEN" };
//     }
// 
//     // Ensure all data values are strings per FCM specification
//     const stringifiedData = Object.fromEntries(
//         Object.entries(data).map(([k, v]) => [k, String(v ?? "")])
//     );
// 
//     const message = {
//         token,
//         notification: {
//             title,
//             body
//         },
//         data: stringifiedData
//     };
// 
//     try {
//         const response = await admin.messaging().send(message);
//         logger.info({
//             module: "FCM_SINGLE_PUSH",
//             status: "SUCCESS",
//             messageId: response,
//             title,
//             tokenPrefix: token.substring(0, 10)
//         });
//         return { success: true, messageId: response };
//     } catch (error) {
//         logger.error({
//             module: "FCM_SINGLE_PUSH",
//             status: "FAILED",
//             error: error.message,
//             code: error.code || "UNKNOWN",
//             tokenPrefix: token.substring(0, 10)
//         });
//         return { success: false, error: error.message, code: error.code };
//     }
// }
    return input;
}
