import aroya/integration_commons as commons;

import ballerina/http;
import ballerina/test;

// The whole timed job against a local stand-in (made-up data; nothing leaves this machine).

isolated string scenario = "";
isolated string[] seen = [];

listener http:Listener standIn = new (19095);

service / on standIn {
    resource function 'default [string... path](http:Request req) returns http:Response|error {
        string first = path.length() > 0 ? path[0] : "";
        string zp = req.hasHeader("zohoPath") ? check req.getHeader("zohoPath") : "";
        json|http:ClientError body = req.getJsonPayload();
        string sc;
        lock {
            sc = scenario;
        }
        lock {
            seen.push(req.method + " " + first + (zp == "" ? "" : " " + zp));
        }
        http:Response r = new;
        if first == "sw" {
            string q = body is json ? textOr(f(body, "query"), "") : "";
            if q.includes("mutation Login") {
                if sc == "login refused" {
                    r.statusCode = 401;
                    r.setJsonPayload({"errors": [{"message": "invalid credentials"}]});
                } else {
                    r.setJsonPayload({"data": {"login": {"token": "tok-1"}}});
                }
                return r;
            }
            json[] edges = sc == "nothing" ? [] : [sampleEdge("R1")];
            r.setJsonPayload({"data": {"reservations": {"edges": edges, "pageInfo": {"endCursor": "c1", "hasNextPage": false}}}});
            return r;
        }
        if first == "zoho" {
            if req.method == "GET" {
                r.statusCode = 204;
                return r;
            }
            if sc == "zoho down" {
                r.statusCode = 500;
                r.setJsonPayload({"message": "down"});
                return r;
            }
            json[] data = body is json ? items(f(body, "data")) : [];
            json[] out = from json _ in data select {"code": "SUCCESS", "status": "success", "details": {"id": "Z-1"}};
            r.setJsonPayload({"data": out});
            return r;
        }
        if first == "guests" {
            json[] gs = body is json[] ? body : [];
            json[] out = from json _ in gs select {"zohoId": "G-1", "status": "success"};
            r.setJsonPayload(out);
            return r;
        }
        if first == "oss" && sc == "oss down" {
            r.statusCode = 403;
            r.setTextPayload("<Error><Code>AccessDenied</Code></Error>");
            return r;
        }
        r.setJsonPayload({"status": "ok"});
        return r;
    }
}

function jobFor(string sc, boolean shorex = false) returns SeawareSync|error {
    lock {
        scenario = sc;
    }
    lock {
        seen = [];
    }
    SyncSettings sync = {mode: "delta", retryCount: 1, retryWaitSeconds: 0.01, errorTable: "error_log", writeShorex: shorex};
    string base = "http://localhost:19095/";
    commons:DownstreamSettings sw = {url: base + "sw"};
    commons:DownstreamSettings zo = {url: base + "zoho"};
    commons:DownstreamSettings gu = {url: base + "guests"};
    commons:DownstreamSettings db = {url: base + "db"};
    StateStore state = check new ({enabled: false, host: "", port: 6379}, "t:");
    return new (state, check new Backend("sw", sw, sync), check new Backend("zoho", zo, sync), check new Backend("guests", gu, sync),
        check new Backend("db", db, sync),
        check new ErrorMail({enabled: true, url: base + "mail", toAddress: "to@example.test", ccAddress: "cc@example.test", env: "uat"}),
        check new OssUploader({enabled: true, url: base + "oss", bucket: "b", accessKeyId: "id", accessKeySecret: "s"}),
        {username: "u", password: "p"}, sync, {});
}

function calls() returns string[] {
    lock {
        return seen.clone();
    }
}

function count(string[] list, string prefix) returns int => list.filter(x => x.startsWith(prefix)).length();

@test:Config {}
function normalRunWritesEveryModuleAndKeepsThePage() returns error? {
    SeawareSync job = check jobFor("");
    string out = job.run();
    test:assertEquals(out, "done: 1 reservation(s), 0 failed block(s)");
    string[] c = calls();
    test:assertEquals(count(c, "PUT oss"), 1);
    foreach string p in ["/crm/v6/Accounts/upsert", "/crm/v6/Cabin_Info/upsert", "/crm/v6/Addons/upsert", "/crm/v6/Group_Agency/upsert",
            "/crm/v6/Voyages/upsert", "/crm/v6/Finance/upsert"] {
        test:assertTrue(c.indexOf("POST zoho " + p) is int, p);
    }
    test:assertEquals(count(c, "POST guests"), 1);
    test:assertEquals(count(c, "POST mail"), 0);
    test:assertEquals(count(c, "POST zoho /crm/v6/Shorex"), 0);
    // the session token is used again on the next run
    _ = job.run();
    test:assertEquals(calls().filter(x => x == "POST sw").length(), 3, "one sign-in and two queries");
}

@test:Config {}
function refusedSignInIsEmailedAndNothingIsWritten() returns error? {
    SeawareSync job = check jobFor("login refused");
    test:assertEquals(job.run(), "failed: Seaware sign-in was refused");
    string[] c = calls();
    test:assertEquals(count(c, "POST mail"), 1);
    test:assertEquals(count(c, "POST zoho"), 0);
    test:assertEquals(count(c, "PUT oss"), 0);
}

@test:Config {}
function crmDownKeepsTheBlockAndGoesOn() returns error? {
    SeawareSync job = check jobFor("zoho down");
    test:assertEquals(job.run(), "done: 1 reservation(s), 1 failed block(s)");
    string[] c = calls();
    test:assertEquals(count(c, "POST zoho /crm/v6/Accounts/upsert"), 2, "first try and one retry");
    test:assertEquals(count(c, "POST mail"), 0);
}

@test:Config {}
function ossDownStopsTheRunAndIsEmailed() returns error? {
    SeawareSync job = check jobFor("oss down");
    string out = job.run();
    test:assertTrue(out.startsWith("failed: OSS refused the upload (HTTP 403)"), out);
    string[] c = calls();
    test:assertEquals(count(c, "POST mail"), 1);
    test:assertEquals(count(c, "POST zoho"), 0);
}

@test:Config {}
function nothingNewWritesNothing() returns error? {
    SeawareSync job = check jobFor("nothing");
    test:assertEquals(job.run(), "done: 0 reservation(s), 0 failed block(s)");
    string[] c = calls();
    test:assertEquals(count(c, "POST zoho") + count(c, "PUT oss") + count(c, "POST mail"), 0);
}

@test:Config {}
function shorexSwitchedOnIsWritten() returns error? {
    SeawareSync job = check jobFor("", true);
    _ = job.run();
    string[] c = calls();
    test:assertTrue(c.indexOf("GET zoho /crm/v6/Shorex/search") is int);
    test:assertTrue(c.indexOf("POST zoho /crm/v6/Shorex/upsert") is int);
}
