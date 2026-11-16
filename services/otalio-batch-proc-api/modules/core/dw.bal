// Small helpers that read JSON the way the old DataWeave scripts did.

# Reads a field path. On a list the field is read from every entry (entries without it are left
# out), which is what `a.b.c` did in the old scripts.
#
# + v - Value to read from
# + path - Field names, outermost first
# + return - The value, or () when nothing is there
public isolated function f(json v, string... path) returns json {
    json cur = v;
    foreach string key in path {
        cur = step(cur, key);
        if cur is () {
            return ();
        }
    }
    return cur;
}

isolated function step(json v, string key) returns json {
    if v is map<json> {
        return v[key];
    }
    if v is json[] {
        json[] out = [];
        foreach json item in v {
            json x = step(item, key);
            if x !is () {
                out.push(x);
            }
        }
        return out.length() == 0 ? () : out;
    }
    return ();
}

# Entry of a list by position; negative positions count from the end.
#
# + v - A list (anything else gives ())
# + index - Position
# + return - The entry or ()
public isolated function at(json v, int index) returns json {
    if v is json[] {
        int i = index < 0 ? v.length() + index : index;
        return i >= 0 && i < v.length() ? v[i] : ();
    }
    return ();
}

# The old scripts' `isEmpty`: nothing, empty text, empty list or empty object.
#
# + v - Value to test
# + return - true when empty
public isolated function blank(json v) returns boolean {
    return v is () || (v is string && v == "") || (v is json[] && v.length() == 0)
        || (v is map<json> && v.length() == 0);
}

# Text form of a value, () for nothing.
#
# + v - Value
# + return - Text or ()
public isolated function text(json v) returns string? {
    if v is () {
        return ();
    }
    return v is string ? v : v.toJsonString();
}

# Text form of a value with a fallback for nothing.
#
# + v - Value
# + fallback - Used when the value is nothing
# + return - Text
public isolated function textOr(json v, string fallback) returns string {
    string? t = text(v);
    return t is () ? fallback : t;
}

# A value as a list: lists stay, nothing becomes an empty list, anything else a one-entry list.
#
# + v - Value
# + return - List
public isolated function items(json v) returns json[] {
    if v is json[] {
        return v;
    }
    if v is () {
        return [];
    }
    return [v];
}

# Every value stored under a field name anywhere inside a value (the old `..name`).
#
# + v - Value to search
# + key - Field name
# + return - Values found, in document order
public isolated function deep(json v, string key) returns json[] {
    json[] out = [];
    collect(v, key, out);
    return out;
}

isolated function collect(json v, string key, json[] out) {
    if v is map<json> {
        foreach [string, json] [k, x] in v.entries() {
            if k == key && x !is () {
                out.push(x);
            }
            collect(x, key, out);
        }
    } else if v is json[] {
        foreach json x in v {
            collect(x, key, out);
        }
    }
}

# Removes one level of nesting from a list of lists.
#
# + v - List
# + return - Flattened list
public isolated function flat(json[] v) returns json[] {
    json[] out = [];
    foreach json x in v {
        if x is json[] {
            out.push(...x);
        } else {
            out.push(x);
        }
    }
    return out;
}

# Adds up a list of numbers (the old `reduce ($$ + $)`); nothing when there is nothing to add.
#
# + v - List of numbers (numeric text counts)
# + return - The total or ()
public isolated function sum(json v) returns json {
    if v !is json[] || v.length() == 0 {
        return ();
    }
    decimal total = 0;
    boolean whole = true;
    foreach json x in v {
        if x is int {
            total += <decimal>x;
        } else if x is float|decimal {
            total += <decimal>x;
            whole = false;
        } else if x is string {
            decimal|error d = decimal:fromString(x);
            if d is decimal {
                total += d;
                whole = false;
            }
        }
    }
    return whole ? <int>total : total;
}

# Splits a list into blocks of a fixed size.
#
# + v - List
# + size - Block size
# + return - Blocks
public isolated function chunks(json[] v, int size) returns json[][] {
    json[][] out = [];
    int n = size < 1 ? 1 : size;
    int i = 0;
    while i < v.length() {
        int end = i + n > v.length() ? v.length() : i + n;
        out.push(v.slice(i, end));
        i = end;
    }
    return out;
}

# Removes repeated entries, keeping the first of each.
#
# + v - List
# + return - List without repeats
public isolated function unique(json[] v) returns json[] {
    json[] out = [];
    foreach json x in v {
        boolean seen = false;
        foreach json y in out {
            if x == y {
                seen = true;
                break;
            }
        }
        if !seen {
            out.push(x);
        }
    }
    return out;
}

# The date part (yyyy-MM-dd) of a date or date-time text.
#
# + v - Text
# + return - Date text, or () for nothing
public isolated function dateOnly(json v) returns json {
    if v is string && v.length() >= 10 {
        return v.substring(0, 10);
    }
    return blank(v) ? () : v;
}

# Nothing for empty values, otherwise the value (the old `if (!isEmpty(x)) x else null`).
#
# + v - Value
# + return - The value or ()
public isolated function orNull(json v) returns json {
    return blank(v) ? () : v;
}
