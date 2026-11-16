"""Generates CLEARLY FAKE bootstrap records for capacity/performance tests (never real data).
Names come from invented syllables; e-mails use @gir-synthetic.invalid; phones use the fictional
NANP 555 exchange (+1 <area> 555 XXXX). ~12% of guests are re-registrations of an earlier fake person
(same name/DOB, sometimes same phone/e-mail) so candidate distributions are realistic.

usage: python -I tools/gen_synthetic.py --count 500000 --batch-size 2000 --out-dir /tmp/x   (NDJSON files)"""
import argparse
import json
import os
import random

SYL = ["zor", "vak", "lun", "mir", "tes", "qua", "ber", "nix", "dal", "fen", "rho", "kip", "sol", "yar", "gex", "pum"]
AREAS = [201, 202, 203, 205, 206, 207, 208, 209, 210, 212, 213, 214, 215, 216, 217, 218, 219, 224, 225, 228, 229,
         231, 234, 239, 240, 248, 251, 252, 253, 254, 256, 260, 262, 267, 269, 270, 272, 276, 281, 301, 302, 303,
         304, 305, 307, 308, 309, 310, 312, 313]


def fake_name(rng):
    return "Zz" + "".join(rng.choice(SYL) for _ in range(rng.randint(1, 2)))


def make(i, rng, people):
    if people and rng.random() < 0.12:
        p = dict(rng.choice(people))
        if rng.random() < 0.5:
            p["phone"] = None
        if rng.random() < 0.5:
            p["email"] = f"zz.{i}@gir-synthetic.invalid"
    else:
        p = {"firstName": fake_name(rng), "lastName": fake_name(rng) + "fake",
             "dateOfBirth": f"{rng.randint(1940, 2008)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}",
             "phone": f"+1 {rng.choice(AREAS)} 555 {rng.randint(0, 9999):04d}",
             "email": f"zz.person{i}@gir-synthetic.invalid"}
        if len(people) < 200000:
            people.append(p)
    has_ids = rng.random() < 0.6
    gid = f"01SYN{i:021d}" if has_ids else None
    return {"crmGuestRecordId": f"SYN{i:09d}", "sourceSystem": "GIR_SYNTHETIC", "crmModifiedTime": "2026-11-01T00:00:00Z",
            **p, "sourceCode": rng.choice(["MOBAPP", "INT-CON", "WHATSAPP", "INT-AGENT"]),
            "agencyName": rng.choice(["AROYA CRUISES MAIN OFFICE", "RIYADH SEASON", "SOME FAKE AGENCY"]),
            "currentGlobalId": gid, "currentLoyaltyId": (f"9{i:09d}" if has_ids else None)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=500000)
    ap.add_argument("--batch-size", type=int, default=2000)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rng, people = random.Random(a.seed), []
    os.makedirs(a.out_dir, exist_ok=True)
    f, n = None, 0
    for i in range(a.count):
        if i % a.batch_size == 0:
            if f:
                f.close()
            n += 1
            f = open(os.path.join(a.out_dir, f"syn-{n:05d}.ndjson"), "w")
        f.write(json.dumps(make(i, rng, people)) + "\n")
    f.close()
    print(n)


if __name__ == "__main__":
    main()
