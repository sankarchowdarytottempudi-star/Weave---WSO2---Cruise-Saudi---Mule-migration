// Pure functions, one per source transformation. Each carries the source script as its
// specification; replace the body and add a test in tests/.

# Source: `get:\items:sample-api-config` / Transform -> set-payload (DataWeave 2.0, 8 lines).
# Output fields: id, name, price.
#
# + input - The source payload
# + return - The mapped value
public isolated function getItemsSampleApiConfigTransformSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// payload.items map (item) -> {
//   id: item.itemId,
//   name: upper(item.title),
//   price: item.amount as Number
// }
    return input;
}

# Source: `get:\items\(itemId):sample-api-config` / Transform -> set-payload (DataWeave 2.0, 8 lines).
# Output fields: id, name, inStock.
#
# + input - The source payload
# + return - The mapped value
public isolated function getItemsItemIdSampleApiConfigTransformSetPayload(json input) returns json {
// %dw 2.0
// output application/json
// ---
// {
//   id: payload.itemId,
//   name: payload.title,
//   inStock: payload.quantity > 0
// }
    return input;
}
