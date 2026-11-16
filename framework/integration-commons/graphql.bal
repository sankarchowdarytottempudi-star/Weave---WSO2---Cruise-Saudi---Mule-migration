// GraphQL text inspection, ported from the DataWeave in reservation-mgr-exp-api
// (reservation-mgr-exp-api-implementation-v1.xml / -v2.xml, "extraction" and "Transform
// Message" -> rootFields). The Mule code reads the text with regular expressions rather than
// parsing GraphQL; the rules below are the same, written as a small scanner so each rule can
// be unit-tested on its own.

import ballerina/lang.regexp;

# The kind of GraphQL operation.
public enum OperationType {
    QUERY = "query",
    MUTATION = "mutation",
    SUBSCRIPTION = "subscription"
}

final string:RegExp COMMENT = re `#[^\r\n]*`;
final string:RegExp OPERATION_HEADER = re `^\s*(mutation|query|subscription)\s+([A-Za-z0-9_]+)`;

# The operation type. Mule: `startsWith "mutation"` / `"subscription"`, otherwise query.
#
# + query - The GraphQL document
# + return - The operation type
public isolated function operationTypeOf(string query) returns OperationType {
    string text = query.trim();
    if text.startsWith("mutation") {
        return MUTATION;
    }
    if text.startsWith("subscription") {
        return SUBSCRIPTION;
    }
    return QUERY;
}

# The operation name written after the operation type, for example `AvailableVoyages` in
# `query AvailableVoyages { ... }`. Mule default: `Anonymous`.
#
# + query - The GraphQL document
# + return - The operation name, or `Anonymous`
public isolated function operationNameOf(string query) returns string {
    regexp:Groups? groups = OPERATION_HEADER.findGroups(query.trim());
    if groups is () || groups.length() < 3 {
        return "Anonymous";
    }
    regexp:Span? name = groups[2];
    return name is () ? "Anonymous" : name.substring();
}

# The first root field of the operation: the field the request is about (`availableVoyages`,
# `reservationCreate`, ...). This is what the Exp API routes on.
#
# Same rules as the Mule DataWeave, in the same order:
# 1. comments (`#` to end of line) are removed;
# 2. the body is the text after the first `{`;
# 3. a direct field (optionally behind an alias `alias: field`) wins;
# 4. otherwise an inline fragment `... on Type { field }`;
# 5. otherwise a fragment spread `...Name`, resolved to the first field of `fragment Name on T { field }`.
#
# + query - The GraphQL document
# + return - The root field, or `()` when none can be found
public isolated function rootFieldOf(string query) returns string? {
    string gql = COMMENT.replaceAll(query, "");
    int? open = gql.indexOf("{");
    if open is () {
        return ();
    }
    string body = gql.substring(open + 1);
    int pos = skipSpace(body, 0);
    if body.substring(pos).startsWith("...") {
        int afterDots = skipSpace(body, pos + 3);
        [string, int] word = readName(body, afterDots);
        if word[0] == "on" && afterDots + 2 < body.length() && isSpace(body[afterDots + 2]) {
            // Inline fragment: ... on Type { field
            [string, int] typeName = readName(body, skipSpace(body, word[1]));
            int brace = skipSpace(body, typeName[1]);
            if typeName[0] == "" || brace >= body.length() || body[brace] != "{" {
                return ();
            }
            return fieldAt(body, skipSpace(body, brace + 1));
        }
        if word[0] == "" {
            return ();
        }
        return fragmentFirstField(gql, word[0]);
    }
    return fieldAt(body, pos);
}

// A field at `pos`, optionally behind an alias, followed by `(`, `{`, `@` or `}`.
isolated function fieldAt(string text, int pos) returns string? {
    [string, int] first = readName(text, pos);
    if first[0] == "" {
        return ();
    }
    int next = skipSpace(text, first[1]);
    string fieldName = first[0];
    if next < text.length() && text[next] == ":" {
        [string, int] aliased = readName(text, skipSpace(text, next + 1));
        if aliased[0] == "" {
            return ();
        }
        fieldName = aliased[0];
        next = skipSpace(text, aliased[1]);
    }
    if next < text.length() && (text[next] == "(" || text[next] == "{" || text[next] == "@" || text[next] == "}") {
        return fieldName;
    }
    return ();
}

// First field of `fragment <name> on <Type> { field`.
isolated function fragmentFirstField(string gql, string name) returns string? {
    int? at = gql.indexOf("fragment");
    while at is int {
        int pos = skipSpace(gql, at + 8);
        [string, int] fragmentName = readName(gql, pos);
        if fragmentName[0] == name {
            [string, int] onWord = readName(gql, skipSpace(gql, fragmentName[1]));
            if onWord[0] == "on" {
                [string, int] typeName = readName(gql, skipSpace(gql, onWord[1]));
                int brace = skipSpace(gql, typeName[1]);
                if typeName[0] != "" && brace < gql.length() && gql[brace] == "{" {
                    return fieldAt(gql, skipSpace(gql, brace + 1));
                }
            }
        }
        at = gql.indexOf("fragment", at + 8);
    }
    return ();
}

isolated function isSpace(string c) returns boolean => c == " " || c == "\n" || c == "\r" || c == "\t" || c == ",";

isolated function isNameChar(string c, boolean first) returns boolean {
    if c == "_" || (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") {
        return true;
    }
    return !first && c >= "0" && c <= "9";
}

isolated function skipSpace(string text, int pos) returns int {
    int i = pos;
    while i < text.length() && isSpace(text[i]) {
        i += 1;
    }
    return i;
}

isolated function readName(string text, int pos) returns [string, int] {
    if pos >= text.length() || !isNameChar(text[pos], true) {
        return ["", pos];
    }
    int i = pos + 1;
    while i < text.length() && isNameChar(text[i], false) {
        i += 1;
    }
    return [text.substring(pos, i), i];
}
