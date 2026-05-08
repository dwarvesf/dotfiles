# Privacy gate for incident reports

Two privacy levels: **private repo** (this is the default) and **public repo** (sanitization required before save).

## Private repo

Full forensic detail OK. Allowed in command outputs:

- HMAC hashes (the hash, never the secret value)
- Account IDs, exchange UIDs, broker IDs
- Internal IPs (`45.32.53.122`, `10.0.2.2`)
- Internal hostnames (`trading-egress-tokyo`, `mon-ingest`)
- Internal file paths (`/var/lib/vps-mon/`)
- Error stack traces with internal paths
- Wrangler / D1 / KV / cloud-resource IDs
- Internal tracking IDs (H-NN, OD-NNN, INC-NNN)
- Real names of clients / contractors / family **only when business-relevant**

Still forbidden (per the project's `secrets — never-paste rule`):

- Raw API keys / OAuth tokens / bearer tokens (any form)
- Raw HMAC values (the hash is fine; the value is not)
- 1Password URIs that contain credentials (`op://Toolkit/foo/api_key` is fine to mention as a reference; the resolved value is not)
- Seed phrases, recovery codes, mnemonics
- Owner PII not already documented in the repo (medical, financial-account-numbers, etc.)

If you accidentally write one of these, redact + amend before committing. If already pushed, treat as compromised: rotate the secret, file a separate `op-incident` note (don't depend on the cycle through git).

## Public repo

Sanitization-first. Run this checklist for **every** diagnostic step before commit:

```
[ ] No internal IPs (search for: 10.*, 192.168.*, 172.16-31.*, public IPs in your fleet)
[ ] No internal hostnames (search for: known hostnames, *.internal, *.local)
[ ] No account IDs (search for: digit runs near "account", "id:", "uid:", "user:", "broker", "exchange")
[ ] No 1Password URIs (search for: op://)
[ ] No internal file paths (search for: /var/, /opt/, /home/, /root/, /Users/<owner>)
[ ] No screenshots of internal dashboards (only screenshots of recreated/generic examples)
[ ] No owner-shape tells (search for: "for my $", "on my M", "my account", "my portfolio", "my <coin>")
[ ] No real names (clients, contractors, family - use role not name if context matters)
[ ] No internal tracking IDs (H-NN, OD-NNN, internal SPEC IDs from private repos)
[ ] Raw error stack traces stripped of internal paths
[ ] Numbers either omitted or in generic units (10× spike, 60% error rate)

Result: PASS / FAIL (and which items failed)
```

Any FAIL halts the commit.

## Sanitized cross-publish (private → public)

If a private incident has lessons reusable in a public engineering context (e.g. for a public TIL repo or external blog post), the cross-publish flow:

1. Take the private `_TEMPLATE-private.md` filing.
2. Copy it to a scratch file. Do NOT edit the private original.
3. Apply every rule in the public checklist above.
4. Drop the local-tz timeline column. Drop internal tracking IDs.
5. Rewrite owner-specific phrasing in third person ("the team observed" not "I observed").
6. Re-run the checklist on the rewrite.
7. Only on clean PASS + explicit owner publish signal → commit to the public repo as `<incidents_path>/YYYY-MM-DD-<slug>.md` using `_TEMPLATE-public.md` structure.
8. Add a `## References` link in the private original pointing at the public version (one-way; the public version does NOT link back to private).

Cross-publish is a separate explicit step, not auto-triggered. The default for any incident is private only.

## Common failure modes

- **"Just one number" leak**: a portfolio dollar figure leaked in an offhand sentence ("our setup with $X account does Y"). Even one number breaks the privacy line. Replace with "our setup at semi-pro scale" or similar.
- **Implicit ID via path**: writing `/Users/tieubao/...` reveals the owner. Strip to `~/` or `<owner-home>`.
- **Stack trace residue**: error messages copied verbatim include internal package paths. Sanitize package names, line numbers can stay.
- **Screenshot baggage**: screenshots include browser tabs, system UI, dashboard names. Crop to the smallest meaningful viewport; recreate as a clean reproduction if helpful.
- **External tool URLs**: `https://internal.example.com/...` leaks org. Replace with `<internal-tool>`.
