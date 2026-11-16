// GET /currency-rates: the query sent to the DB system API and the answer built from its rows.
// Same SQL as the Mule flow "currency-rates"; unlike Mule, the caller's values are checked before
// they are placed in the SQL text.

const string FX_TABLE = "cs_mule_framework.cs_fx_rates";
const string FX_COLUMNS = "id, from_currency, to_currency, rate, currency_date, op_type, op_ts, created_at, updated_at";

# Query parameters of GET /currency-rates (Mule variable `queryParams`).
#
# + date - A single day, yyyy-MM-dd
# + fromDate - Start of a period
# + toDate - End of a period
# + toCurrency - Target currency code
# + fromCurrency - Source currency code
# + distinctCurrencies - "true" to list the target currencies only
public type RatesParams record {|
    string date = "";
    string fromDate = "";
    string toDate = "";
    string toCurrency = "";
    string fromCurrency = "";
    string distinctCurrencies = "";
|};

# Reads the parameters from a request's query string (`to_currency` / `from_currency` are accepted
# as alternative names, as in Mule).
#
# + query - Query parameters of the request
# + return - The parameters
public isolated function ratesParamsOf(map<string[]> query) returns RatesParams {
    return {
        date: firstOf(query, "date"),
        fromDate: firstOf(query, "fromDate"),
        toDate: firstOf(query, "toDate"),
        toCurrency: query.hasKey("toCurrency") ? firstOf(query, "toCurrency") : firstOf(query, "to_currency"),
        fromCurrency: query.hasKey("fromCurrency") ? firstOf(query, "fromCurrency") : firstOf(query, "from_currency"),
        distinctCurrencies: firstOf(query, "distinctCurrencies")
    };
}

isolated function firstOf(map<string[]> query, string name) returns string {
    string[]? values = query[name];
    return values is string[] && values.length() > 0 ? values[0] : "";
}

# Refuses values that are not dates or currency codes.
#
# + params - The parameters
# + return - An error naming the first bad parameter, else `()`
public isolated function checkRatesParams(RatesParams params) returns error? {
    foreach [string, string] [name, value] in [["date", params.date], ["fromDate", params.fromDate], ["toDate", params.toDate]] {
        if value.trim() != "" && !re `[0-9]{4}-[0-9]{2}-[0-9]{2}`.isFullMatch(value.trim()) {
            return error(name + " must be a date in the form yyyy-MM-dd");
        }
    }
    foreach [string, string] [name, value] in [["toCurrency", params.toCurrency], ["fromCurrency", params.fromCurrency]] {
        if value.trim() != "" && !re `[A-Za-z]{3}`.isFullMatch(value.trim()) {
            return error(name + " must be a three-letter currency code");
        }
    }
}

# The request sent to the DB system API.
#
# + params - Checked parameters
# + return - The DB system API request
public isolated function ratesQueryOf(RatesParams params) returns map<json> {
    if params.distinctCurrencies == "true" {
        return dbSelect("SELECT DISTINCT to_currency FROM " + FX_TABLE + " ORDER BY to_currency");
    }
    string date = params.date.trim();
    string fd = params.fromDate.trim();
    string td = params.toDate.trim();
    string tc = params.toCurrency.trim();
    string fc = params.fromCurrency.trim();
    boolean hasRange = fd != "" && td != "";
    string baseSelect = (hasRange ? "SELECT " : "SELECT DISTINCT ON (to_currency) ") + FX_COLUMNS + " FROM " + FX_TABLE;
    string currencyFilter = (tc != "" ? " AND to_currency = '" + tc.toUpperAscii() + "'" : "")
        + (fc != "" ? " AND from_currency = '" + fc.toUpperAscii() + "'" : "");
    string whereClause;
    if hasRange {
        whereClause = " WHERE currency_date BETWEEN DATE '" + fd + "' AND DATE '" + td + "'" + currencyFilter;
    } else if date != "" {
        whereClause = " WHERE currency_date = DATE '" + date + "'" + currencyFilter;
    } else {
        whereClause = " WHERE currency_date = (SELECT MAX(currency_date) FROM " + FX_TABLE
            + " WHERE currency_date <= CURRENT_DATE)" + currencyFilter;
    }
    string orderBy = (hasRange ? " ORDER BY currency_date, to_currency," : " ORDER BY to_currency,")
        + " CASE WHEN op_type = 'U' THEN 1 ELSE 2 END, op_ts DESC";
    return dbSelect(baseSelect + whereClause + orderBy);
}

isolated function dbSelect(string query) returns map<json> => {
    "connectionKey": "PG_Guest",
    "operation": "select",
    "query": query
};

# Rows of a DB system API answer: its `data` member when present, else the answer itself.
#
# + answer - DB system API answer
# + return - The rows
public isolated function rowsOf(json answer) returns json[] {
    json rows = answer is map<json> && answer.hasKey("data") ? answer["data"] : answer;
    return rows is json[] ? rows : [];
}

# The answer of GET /currency-rates.
#
# + answer - DB system API answer
# + params - The request's parameters
# + return - The body returned to the caller
public isolated function ratesResponseOf(json answer, RatesParams params) returns json {
    json[] rows = rowsOf(answer);
    if params.distinctCurrencies == "true" {
        json[] currencies = [];
        foreach json row in rows {
            string code = textOf(fieldOf(row, "to_currency")).trim();
            if code != "" {
                currencies.push({"to_currency": code.toUpperAscii()});
            }
        }
        return {"status": "success", "count": currencies.length(), "data": currencies};
    }
    if rows.length() == 0 {
        string dateContext = params.fromDate != "" && params.toDate != ""
            ? "between " + params.fromDate + " and " + params.toDate
            : (params.date != "" ? "for date " + params.date : "for the requested period");
        string currencyContext = params.toCurrency != "" ? " for currency " + params.toCurrency.toUpperAscii() : "";
        return {"status": "success", "message": "No currency rates found " + dateContext + currencyContext, "data": []};
    }
    json[] data = [];
    foreach json row in rows {
        data.push({
            "id": fieldOf(row, "id"),
            "fromCurrency": fieldOf(row, "from_currency"),
            "toCurrency": fieldOf(row, "to_currency"),
            "rate": fieldOf(row, "rate"),
            "currencyDate": fieldOf(row, "currency_date"),
            "opType": fieldOf(row, "op_type"),
            "opTs": fieldOf(row, "op_ts")
        });
    }
    return {"status": "success", "count": data.length(), "data": data};
}
