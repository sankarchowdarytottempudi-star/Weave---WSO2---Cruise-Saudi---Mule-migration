import ballerina/sql;

// The statement: where its `:name` places are, what kind it is, and the bound query.
//
// A value never becomes part of the SQL text. The text is cut at each `:name`, and the values
// travel beside it as parameters of a prepared statement (Mule: `input-parameters`).

const int QUOTE = 39;
const int DOUBLE_QUOTE = 34;
const int COLON = 58;
const int DASH = 45;
const int SLASH = 47;
const int STAR = 42;
const int DOLLAR = 36;
const int SEMICOLON = 59;
const int BACKSLASH = 92;
const int OPEN_BRACKET = 40;
const int UNDERSCORE = 95;

# Takes a statement apart at its `:name` places.
#
# Left alone: `::` casts, `:=`, text between single quotes (also `E'..'` with backslashes),
# names between double quotes, `$tag$ .. $tag$` text and both kinds of comment.
#
# + query - The SQL text
# + return - The parts around the places, the names, the first word and whether text follows a `;`
public isolated function parsedOf(string query) returns ParsedSql {
    int[] c = query.toCodePointInts();
    int n = c.length();
    string[] parts = [];
    string[] names = [];
    string firstWord = "";
    boolean firstWordSeen = false;
    boolean afterSemicolon = false;
    boolean several = false;
    int partStart = 0;
    int i = 0;
    while i < n {
        int ch = c[i];
        int next = i + 1 < n ? c[i + 1] : -1;
        if ch == DASH && next == DASH {
            i = lineCommentEnd(c, i);
            continue;
        }
        if ch == SLASH && next == STAR {
            i = blockCommentEnd(c, i);
            continue;
        }
        if isSpace(ch) {
            i += 1;
            continue;
        }
        if ch == SEMICOLON {
            afterSemicolon = true;
            i += 1;
            continue;
        }
        if afterSemicolon {
            several = true;
        }
        if !firstWordSeen && ch != OPEN_BRACKET {
            firstWordSeen = true;
            if isWordStart(ch) {
                int wordEnd = wordEndOf(c, i);
                firstWord = textOfPoints(c, i, wordEnd).toUpperAscii();
                i = wordEnd;
                continue;
            }
        }
        if ch == QUOTE {
            boolean backslashes = i > 0 && (c[i - 1] == 69 || c[i - 1] == 101) && (i < 2 || !isWordChar(c[i - 2]));
            i = quotedEnd(c, i, QUOTE, backslashes);
        } else if ch == DOUBLE_QUOTE {
            i = quotedEnd(c, i, DOUBLE_QUOTE, false);
        } else if ch == DOLLAR && (i == 0 || !isWordChar(c[i - 1])) {
            i = dollarQuotedEnd(c, i);
        } else if ch == COLON && next == COLON {
            i += 2;
        } else if ch == COLON && isWordStart(next) {
            int nameEnd = wordEndOf(c, i + 1);
            parts.push(textOfPoints(c, partStart, i));
            names.push(textOfPoints(c, i + 1, nameEnd));
            partStart = nameEnd;
            i = nameEnd;
        } else if isWordChar(ch) {
            i = wordEndOf(c, i);
        } else {
            i += 1;
        }
    }
    parts.push(textOfPoints(c, partStart, n));
    return {parts, names, firstWord, severalStatements: several};
}

# Why a statement is not run, or `()` when it may be.
#
# As in the old application, the operation decides which statements are taken: `select` reads
# (SELECT, or WITH .. SELECT), `insert` takes INSERT, `update` takes UPDATE, MERGE and TRUNCATE.
# Anything else (DELETE, DROP, ALTER, a procedure call, ...) is refused.
#
# + operation - `select`, `insert` or `update`
# + parsed - The statement
# + allowSeveral - `true` when one call may carry more than one statement
# + return - The refusal, or `()`
public isolated function statementRefusal(string operation, ParsedSql parsed, boolean allowSeveral) returns Refusal? {
    if parsed.firstWord == "" {
        return refusal("BAD_REQUEST", 400, parsed.parts.length() == 1 && parsed.parts[0].trim() == ""
                    ? "query is empty" : "query does not start with a statement");
    }
    string[] taken = operation == "select" ? ["SELECT", "WITH"]
        : operation == "insert" ? ["INSERT"] : ["UPDATE", "MERGE", "TRUNCATE"];
    if taken.indexOf(parsed.firstWord) is () {
        string word = parsed.firstWord.length() > 20 ? parsed.firstWord.substring(0, 20) : parsed.firstWord;
        return refusal("BAD_REQUEST", 400, "The operation \"" + operation + "\" takes a statement that starts with "
                + " or ".'join(...taken) + "; this one starts with " + word);
    }
    if parsed.severalStatements && !allowSeveral {
        return refusal("BAD_REQUEST", 400, "Send one statement per call");
    }
    return ();
}

# The statement with its values bound as parameters.
#
# + parsed - The statement, taken apart
# + params - The values by name
# + return - The query for the database client, or a refusal that names the values not sent
public isolated function boundQueryOf(ParsedSql parsed, map<json> params) returns sql:ParameterizedQuery|Refusal {
    sql:Value[] values = [];
    string[] notSent = [];
    foreach string name in parsed.names {
        if params.hasKey(name) {
            values.push(parameterOf(params[name]));
        } else if notSent.indexOf(name) is () {
            notSent.push(name);
        }
    }
    if notSent.length() > 0 {
        return refusal("BAD_REQUEST", 400, "No value was sent for: " + ", ".'join(...notSent));
    }
    sql:ParameterizedQuery query = ``;
    query.strings = parsed.parts.cloneReadOnly();
    query.insertions = values;
    return query;
}

# One value as a statement parameter.
# Text stays text, a whole number that fits 32 bits is an integer (as the old application
# sent it), a larger one a big integer, null is NULL, and an object or a list goes as its
# JSON text (for `CAST(:x AS jsonb)` or `:x::jsonb`).
#
# + value - The value from `params`
# + return - The parameter
public isolated function parameterOf(json value) returns sql:Value {
    if value is int {
        if value >= -2147483648 && value <= 2147483647 {
            return new sql:IntegerValue(value);
        }
        return value;
    }
    if value is ()|string|boolean|decimal|float {
        return value;
    }
    return value.toJsonString();
}

isolated function lineCommentEnd(int[] c, int 'start) returns int {
    int i = 'start;
    while i < c.length() && c[i] != 10 {
        i += 1;
    }
    return i;
}

// PostgreSQL block comments nest.
isolated function blockCommentEnd(int[] c, int 'start) returns int {
    int depth = 0;
    int i = 'start;
    while i < c.length() {
        int next = i + 1 < c.length() ? c[i + 1] : -1;
        if c[i] == SLASH && next == STAR {
            depth += 1;
            i += 2;
        } else if c[i] == STAR && next == SLASH {
            depth -= 1;
            i += 2;
            if depth == 0 {
                return i;
            }
        } else {
            i += 1;
        }
    }
    return i;
}

// Index after the closing quote; a doubled quote stays inside.
isolated function quotedEnd(int[] c, int 'start, int quote, boolean backslashes) returns int {
    int i = 'start + 1;
    while i < c.length() {
        if backslashes && c[i] == BACKSLASH {
            i += 2;
        } else if c[i] == quote {
            if i + 1 < c.length() && c[i + 1] == quote {
                i += 2;
            } else {
                return i + 1;
            }
        } else {
            i += 1;
        }
    }
    return c.length();
}

// `$$ .. $$` or `$tag$ .. $tag$`; a lone `$` (or `$1`) is passed over.
isolated function dollarQuotedEnd(int[] c, int 'start) returns int {
    int n = c.length();
    int tagEnd = 'start + 1;
    if tagEnd < n && isDigit(c[tagEnd]) {
        return 'start + 1;
    }
    while tagEnd < n && isWordChar(c[tagEnd]) {
        tagEnd += 1;
    }
    if tagEnd >= n || c[tagEnd] != DOLLAR {
        return 'start + 1;
    }
    int tagLength = tagEnd - 'start + 1;
    int i = tagEnd + 1;
    while i + tagLength <= n {
        boolean same = true;
        foreach int k in 0 ..< tagLength {
            if c[i + k] != c['start + k] {
                same = false;
                break;
            }
        }
        if same {
            return i + tagLength;
        }
        i += 1;
    }
    return n;
}

isolated function wordEndOf(int[] c, int 'start) returns int {
    int i = 'start;
    while i < c.length() && isWordChar(c[i]) {
        i += 1;
    }
    return i;
}

isolated function isSpace(int ch) returns boolean => ch == 32 || (ch >= 9 && ch <= 13);

isolated function isDigit(int ch) returns boolean => ch >= 48 && ch <= 57;

isolated function isWordStart(int ch) returns boolean =>
    (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == UNDERSCORE;

isolated function isWordChar(int ch) returns boolean => isWordStart(ch) || isDigit(ch);

isolated function textOfPoints(int[] c, int 'start, int end) returns string {
    string|error text = string:fromCodePointInts(c.slice('start, end));
    return text is string ? text : "";
}
