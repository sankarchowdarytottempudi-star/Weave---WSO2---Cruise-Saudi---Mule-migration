# Guest identity test corpus (plan §21.7)

Each file in `cases/` is one case, validated against `corpus-case.schema.json`:

| part | meaning |
|---|---|
| `existing` | Guest snapshots evaluated (and committed) first, in order |
| `input` | the snapshot under test (a `GuestIdentityEvent`) |
| `expectedNormalization` | canonical names, DOB key, E.164 + confidence, email key |
| `expected` | decision, decision type, reason codes that must be present, review flag, the CRM patch Integration writes, final processing state |
| `evidence` | filled by the runner: rule version, build, migration version, correlation id, timings, CRM calls (always 0 in Python) |

`provenance` is `SYNTHETIC` for every case here. Masked production examples
(`MASKED_PRODUCTION`) are added only after client approval and must be masked
before they are committed. Never commit real names, phones, e-mails or DOBs.

Synthetic conventions: obviously fake names (`Zztest Fakeperson`),
`@gir-synthetic.invalid` e-mails, and phones in the North-American fictional range
`+1 202 555 01xx`. That range is reserved for fiction but still valid in
libphonenumber, so it can exercise HIGH_E164 (the UK drama range `+44 7700 900xxx` is not valid). `+999` numbers are invalid in libphonenumber, so they can never
be phone evidence.

Run: `pytest tests/integration/test_corpus.py` (needs `GIR_TEST_DATABASE_URL`).
