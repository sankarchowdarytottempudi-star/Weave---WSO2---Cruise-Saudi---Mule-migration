// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `loyalty-exp-api` / fieldMapping (spec, 2 lines).
# Output fields: member.id, points.
#
# + input - The source payload
# + return - The mapped value
public isolated function loyaltyExpApiFieldMapping(json input) returns json {

    return input;
}
