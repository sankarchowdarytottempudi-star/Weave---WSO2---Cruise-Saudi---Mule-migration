// Tells a write from a read, so that a write is never sent twice.

import aroya/integration_commons as commons;

final string:RegExp GQL_COMMENT = re `#[^\r\n]*`;

# `true` when the GraphQL document is a mutation (something that changes data, for example
# `reservationStore`). Comment lines before the operation are ignored.
#
# + query - The GraphQL document
# + return - `true` for a mutation
public isolated function isWrite(string query) returns boolean =>
    commons:operationTypeOf(GQL_COMMENT.replaceAll(query, "")) == commons:MUTATION;
