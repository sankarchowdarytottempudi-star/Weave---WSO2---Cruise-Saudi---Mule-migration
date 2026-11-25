# integration_commons

The reusable framework library that every migrated API (Exp, Proc and Sys) compiles in. It is the
WSO2/Ballerina replacement for the copy-pasted Mule pieces that each Mule project carried on its own:
the global error handler, the Kafka audit and error sub-flows, the email notification sub-flow, the
Object Store circuit breaker, the `http-error-retrySub_Flow` and the GraphQL operation extraction
DataWeave.

| File | Replaces in Mule | What it gives a service |
|------|------------------|-------------------------|
| `correlation.bal` | `set-variable correlationId` at the start of every flow | `correlationIdOf(request)`: header `correlationId`, otherwise a new UUID |
| `graphql.bal` | "Extract Operation Name" and "rootFields" DataWeave | `operationTypeOf`, `operationNameOf`, `rootFieldOf`, with the same rules |
| `errors.bal` | `Global_Error_Handler` status and envelope mapping | `ErrorEnvelope`, `statusForErrorType`, `errorResponse` |
| `circuit_breaker.bal` | `circuit-breaker.xml` (Object Store) | `CircuitBreaker` on Redis. Uses atomic `INCR`, so the counter is correct across replicas (the Mule retrieve/increment/store was not) |
| `retry.bal` | `http-error-retrySub_Flow`, `resilience.nonRetryableOperations` | `RetryPolicy`, `isRetryable` |
| `audit.bal` | `savepayload` and `kafka` sub-flows | `AuditSink` object type with a Kafka sink and a no-op sink |
| `notify.bal` | `exception-email-sub-flow.xml` | `ErrorNotifier`, email through `email-sys-api`, importance rules kept |
| `downstream.bal` | `http:request-config` blocks | `newDownstreamClient`, timeouts, TLS validation on by default, HTTP/2 |
| `redis.bal` | Object Store configuration | `newRedisClient` (same settings shape as `seaware_cache_commons`) |
| `headers.bal` | "Build Request Headers" DataWeave | `forwardHeaders`: which headers pass to the next layer, never logged |

Rules for this library:

- No business logic. A rule that belongs to one API stays in that API's `core` module.
- Every function that can be tested without a network is pure and has a test in `tests/`.
- Nothing here logs a request body, an `Authorization` header or a client secret.
