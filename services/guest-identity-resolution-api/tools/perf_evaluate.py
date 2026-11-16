"""Latency test of POST /v1/guest-identities/evaluate against a loaded index (synthetic data only).
Half the requests re-register an existing synthetic person (candidates exist), half are new people.
Prints p50/p95/p99 (ms), outcome counts and the server-side candidate-count histogram.

usage: python -I tools/perf_evaluate.py --host 13.140.56.229 --port 30960 --cafile CRT --token-file F
          --ndjson-dir /root/gen-work/gir-syn --n 1000 [--threads 4]"""
import argparse
import collections
import glob
import http.client
import json
import random
import re
import ssl
import statistics
import threading
import time
import uuid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--cafile", required=True)
    ap.add_argument("--token-file", required=True)
    ap.add_argument("--ndjson-dir", required=True)
    ap.add_argument("--n", type=int, default=1000)
    ap.add_argument("--threads", type=int, default=4)
    a = ap.parse_args()
    token = open(a.token_file).read().strip()
    rng = random.Random(11)
    files = sorted(glob.glob(a.ndjson_dir + "/*.ndjson"))
    pool = [json.loads(l) for f in rng.sample(files, 10) for l in open(f)]
    pool = [p for p in pool if p["sourceCode"] != "INT-AGENT" and p["agencyName"] != "SOME FAKE AGENCY"]
    events = []
    for i in range(a.n):
        p = dict(rng.choice(pool))
        if i % 2:
            p.update(firstName="Zzperf" + uuid.uuid4().hex[:6], lastName="Zzperfnew", email=f"perf{i}@gir-synthetic.invalid",
                     phone=f"+1 404 555 {rng.randint(0, 9999):04d}")
        events.append({"schemaVersion": "1.0", "eventId": str(uuid.uuid4()), "eventType": "GUEST_IDENTITY_EVALUATION_REQUESTED",
                       "correlationId": f"PERF-{i}", "sourceSystem": "GIR_PERF", "sourceRecordId": f"PERF-{i}",
                       "crmGuestRecordId": f"PERF-{uuid.uuid4().hex[:12]}", "crmModifiedTime": "2026-11-17T00:00:00Z",
                       "firstName": p["firstName"], "lastName": p["lastName"], "dateOfBirth": p["dateOfBirth"],
                       "phone": p["phone"], "email": p["email"], "sourceCode": "MOBAPP",
                       "agencyName": "AROYA CRUISES MAIN OFFICE"})
    ctx = ssl.create_default_context(cafile=a.cafile)
    lat, outcomes, errors, lock = [], collections.Counter(), collections.Counter(), threading.Lock()

    def worker(chunk):
        conn = http.client.HTTPSConnection(a.host, a.port, context=ctx, timeout=30)
        for ev in chunk:
            body = json.dumps(ev)
            t = time.perf_counter()
            conn.request("POST", "/v1/guest-identities/evaluate", body=body,
                         headers={"Content-Type": "application/json", "Authorization": "Bearer " + token})
            r = conn.getresponse()
            data = r.read()
            ms = (time.perf_counter() - t) * 1000
            with lock:
                if r.status == 200:
                    lat.append(ms)
                    outcomes[json.loads(data)["decisionType"]] += 1
                else:
                    errors[r.status] += 1
    chunks = [events[i::a.threads] for i in range(a.threads)]
    started = time.perf_counter()
    ts = [threading.Thread(target=worker, args=(c,)) for c in chunks]
    [t.start() for t in ts]
    [t.join() for t in ts]
    wall = time.perf_counter() - started
    lat.sort()
    q = lambda p: round(lat[min(len(lat) - 1, int(p * len(lat)))], 1)
    conn = http.client.HTTPSConnection(a.host, a.port, context=ctx, timeout=30)
    conn.request("GET", "/metrics", headers={"Authorization": "Bearer " + token})
    metrics = conn.getresponse().read().decode()
    buckets = re.findall(r'gir_candidate_count_bucket\{le="([^"]+)"\} ([0-9.e+]+)', metrics)
    print(json.dumps({"requests": a.n, "ok": len(lat), "errors": dict(errors), "threads": a.threads,
                      "throughputPerSec": round(len(lat) / wall, 1), "p50": q(0.50), "p95": q(0.95), "p99": q(0.99),
                      "max": round(lat[-1], 1), "mean": round(statistics.mean(lat), 1), "outcomes": dict(outcomes),
                      "candidateCountBuckets_onePod_cumulative": dict(buckets)}, indent=1))


if __name__ == "__main__":
    main()
