import ballerina/sql;
import ballerina/test;

@test:Config {}
function namesAreCutOutOfTheText() {
    ParsedSql parsed = parsedOf("SELECT a FROM t WHERE id = :id AND name = :name_1");
    test:assertEquals(parsed.parts, ["SELECT a FROM t WHERE id = ", " AND name = ", ""]);
    test:assertEquals(parsed.names, ["id", "name_1"]);
    test:assertEquals(parsed.firstWord, "SELECT");
    test:assertFalse(parsed.severalStatements);

    ParsedSql none = parsedOf("select 1");
    test:assertEquals(none.parts, ["select 1"]);
    test:assertEquals(none.names, []);
    test:assertEquals(none.firstWord, "SELECT");
}

@test:Config {}
function castsStayInTheText() {
    ParsedSql parsed = parsedOf("INSERT INTO t (a, b, c) VALUES (:a::timestamptz, :b::jsonb, CAST(:c AS jsonb)) -- :not");
    test:assertEquals(parsed.names, ["a", "b", "c"]);
    test:assertEquals(parsed.parts, ["INSERT INTO t (a, b, c) VALUES (", "::timestamptz, ", "::jsonb, CAST(", " AS jsonb)) -- :not"]);

    ParsedSql cast = parsedOf("SELECT COALESCE(x, 0)::int AS n, '{}'::jsonb FROM t WHERE y := 1");
    test:assertEquals(cast.names, []);
    test:assertEquals(cast.parts.length(), 1);
}

@test:Config {}
function quotedTextAndCommentsAreLeftAlone() {
    test:assertEquals(parsedOf("SELECT ':a', 'it''s :b', \":c\" FROM t WHERE d = :d").names, ["d"]);
    test:assertEquals(parsedOf("SELECT 1 /* :a /* :b */ :c */ WHERE x = :x -- :y\n AND z = :z").names, ["x", "z"]);
    test:assertEquals(parsedOf("SELECT $$ :a $$, $tag$ :b $$ :c $tag$, :d").names, ["d"]);
    test:assertEquals(parsedOf("SELECT E'a\\' :a', :b").names, ["b"]);
    test:assertEquals(parsedOf("SELECT 'a\\', :b, ':c'").names, ["b"]);
    test:assertEquals(parsedOf("SELECT $1, col$x, :a").names, ["a"]);
    test:assertEquals(parsedOf("SELECT arr[1:2], '10:15:30'::time, :t").names, ["t"]);
    // A quote that never closes swallows the rest; the database then refuses the statement.
    test:assertEquals(parsedOf("SELECT 'abc :a").names, []);
}

@test:Config {}
function aNameMayStandMoreThanOnce() returns error? {
    ParsedSql parsed = parsedOf("INSERT INTO t (id, ref) VALUES (:uuid, :uuid)");
    test:assertEquals(parsed.names, ["uuid", "uuid"]);
    sql:ParameterizedQuery query = check boundQueryOf(parsed, {"uuid": "u-1", "unused": 5});
    test:assertEquals(query.strings, ["INSERT INTO t (id, ref) VALUES (", ", ", ")"]);
    test:assertEquals(query.insertions.length(), 2);
    test:assertEquals(query.insertions[0], "u-1");
    test:assertEquals(query.insertions[1], "u-1");
}

@test:Config {}
function firstWordSkipsCommentsAndBrackets() {
    test:assertEquals(parsedOf("  -- note\n /* more */ ( select 1 )").firstWord, "SELECT");
    test:assertEquals(parsedOf("with x as (select 1) select * from x").firstWord, "WITH");
    test:assertEquals(parsedOf("").firstWord, "");
    test:assertEquals(parsedOf("   ").firstWord, "");
    test:assertEquals(parsedOf("'x'").firstWord, "");
    test:assertEquals(parsedOf("1 select").firstWord, "");
}

@test:Config {}
function textAfterASemicolonIsASecondStatement() {
    test:assertFalse(parsedOf("SELECT 1;").severalStatements);
    test:assertFalse(parsedOf("SELECT 1 ;  -- done\n /* end */ ").severalStatements);
    test:assertFalse(parsedOf("SELECT ';' , \"a;b\" FROM t").severalStatements);
    test:assertTrue(parsedOf("SELECT 1; DROP TABLE t").severalStatements);
    test:assertFalse(parsedOf("SELECT 1;;").severalStatements);
    test:assertTrue(parsedOf("SELECT 1; -- x\n SELECT 2").severalStatements);
}

@test:Config {}
function theOperationDecidesWhichStatementsAreTaken() {
    test:assertTrue(statementRefusal("select", parsedOf("SELECT 1"), false) is ());
    test:assertTrue(statementRefusal("select", parsedOf("WITH u AS (INSERT INTO t VALUES (1) RETURNING id) SELECT id FROM u"), false) is ());
    test:assertTrue(statementRefusal("insert", parsedOf("insert into t values (1)"), false) is ());
    test:assertTrue(statementRefusal("update", parsedOf("UPDATE t SET a = 1"), false) is ());
    test:assertTrue(statementRefusal("update", parsedOf("MERGE INTO t USING s ON true WHEN MATCHED THEN DO NOTHING"), false) is ());
    test:assertTrue(statementRefusal("update", parsedOf("TRUNCATE t"), false) is ());

    string[][] refused = [
        ["select", "DELETE FROM t"],
        ["select", "DROP TABLE t"],
        ["select", "UPDATE t SET a = 1"],
        ["insert", "UPDATE t SET a = 1"],
        ["insert", "SELECT 1"],
        ["insert", "WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x"],
        ["update", "DELETE FROM t"],
        ["update", "INSERT INTO t VALUES (1)"],
        ["update", "CALL p()"],
        ["update", "ALTER TABLE t ADD c int"],
        ["select", ""],
        ["select", "'x'"]
    ];
    foreach string[] pair in refused {
        Refusal? result = statementRefusal(pair[0], parsedOf(pair[1]), false);
        test:assertTrue(result is Refusal, pair[0] + " / " + pair[1]);
        if result is Refusal {
            test:assertEquals(result.detail().status, 400);
            test:assertEquals(result.detail().errorType, "BAD_REQUEST");
        }
    }
    Refusal? empty = statementRefusal("select", parsedOf("  "), false);
    test:assertEquals(empty is Refusal ? empty.message() : "", "query is empty");
    Refusal? wrong = statementRefusal("insert", parsedOf("select 1"), false);
    test:assertEquals(wrong is Refusal ? wrong.message() : "",
            "The operation \"insert\" takes a statement that starts with INSERT; this one starts with SELECT");
}

@test:Config {}
function oneStatementPerCallUnlessSwitchedOn() {
    Refusal? result = statementRefusal("select", parsedOf("SELECT 1; DROP TABLE t"), false);
    test:assertEquals(result is Refusal ? result.message() : "", "Send one statement per call");
    test:assertTrue(statementRefusal("select", parsedOf("SELECT 1; SELECT 2"), true) is ());
    test:assertTrue(statementRefusal("select", parsedOf("SELECT 1;"), false) is ());
}

@test:Config {}
function valuesNotSentAreNamed() {
    sql:ParameterizedQuery|Refusal result = boundQueryOf(parsedOf("SELECT :a, :b, :a, :c"), {"b": 1});
    test:assertTrue(result is Refusal);
    if result is Refusal {
        test:assertEquals(result.message(), "No value was sent for: a, c");
        test:assertEquals(result.detail().status, 400);
    }
    // null is a value.
    test:assertTrue(boundQueryOf(parsedOf("SELECT :a"), {"a": ()}) is sql:ParameterizedQuery);
}

@test:Config {}
function valuesNeverBecomeText() returns error? {
    string hostile = "x'; DROP TABLE t; --";
    sql:ParameterizedQuery query = check boundQueryOf(parsedOf("SELECT * FROM t WHERE a = :a AND b = :b"),
            {"a": hostile, "b": ":a"});
    test:assertEquals(query.strings, ["SELECT * FROM t WHERE a = ", " AND b = ", ""]);
    test:assertEquals(query.insertions[0], hostile);
    test:assertEquals(query.insertions[1], ":a");
    foreach string part in query.strings {
        test:assertFalse(part.includes("DROP"));
    }
}

@test:Config {}
function valuesKeepTheirKind() {
    test:assertEquals(parameterOf("text"), "text");
    test:assertEquals(parameterOf(true), true);
    test:assertEquals(parameterOf(()), ());
    test:assertEquals(parameterOf(1.5d), 1.5d);
    test:assertEquals(parameterOf(9000000000), 9000000000);
    sql:Value small = parameterOf(42);
    test:assertTrue(small is sql:IntegerValue);
    if small is sql:IntegerValue {
        test:assertEquals(small.value, 42);
    }
    test:assertEquals(parameterOf({"a": [1, "b"]}), "{\"a\":[1, \"b\"]}");
    test:assertEquals(parameterOf([1, 2]), "[1, 2]");
}

@test:Config {}
function wholeNumbersOfARequestStayWhole() returns error? {
    json body = check "{\"params\": {\"n\": 5, \"d\": 1.25}}".fromJsonString();
    DbRequest request = check requestOf(body);
    test:assertTrue(request.params["n"] is int);
    test:assertTrue(request.params["d"] is decimal|float);
}
