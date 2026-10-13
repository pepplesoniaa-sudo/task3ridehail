# 09 Open Items

One page for what is not finished, not decided, or not proven, so nothing is hidden in another document. CONFIRMED means I ran it and kept the output in `evidence/`. INFERRED means I reasoned it. The owner is the person who approves decisions for this project. Nothing in this file contains a secret; the database password lives only in the environment.

Contents: 1. placeholders, 2. owner decisions, 3. known limits, 4. class notes still needed, 5. what the owner must still produce.

## 1. Every placeholder (a value I chose so that something can run; it needs the owner)

| # | Placeholder | Current value | Where it lives | Why it is a placeholder |
|---|---|---|---|---|
| P1 | City | Lagos (assumed) | `db/seed/seed_sample_settings.sql`, applied; used by the service-area box | no city was ever given |
| P2 | Base fare | 50000 kobo (500 naira) | setting `base_fare_minor` | no fare model was given |
| P3 | Price per kilometre | 15000 kobo (150 naira) | setting `per_km_minor` | same |
| P4 | Price per minute | 3000 kobo (30 naira) | setting `per_minute_minor` | same |
| P5 | Quote validity | 300 seconds | setting `quote_validity_seconds` | same |
| P6 | Service-area box | 6.38 to 6.70 north, 3.10 to 3.70 east (stored as degrees x 1,000,000: 6380000, 6700000, 3100000, 3700000) | settings `service_area_min_lat_e6`, `service_area_max_lat_e6`, `service_area_min_lon_e6`, `service_area_max_lon_e6` | a rough rectangle; it also contains sea and land the service will not cover |
| P7 | Timeout job interval | 60 seconds | setting `request_timeout_check_interval_seconds` | not chosen by the owner |
| P8 | Payment reconciliation job interval | 300 seconds | setting `payment_reconcile_check_interval_seconds` | not chosen by the owner |
| P9 | Request timeout | 600 seconds | setting `request_timeout_seconds` (B9, T9) | marked "placeholder, needs owner approval" in `01`, `03`, `05` |
| P10 | Payment reconcile-after | 900 seconds | setting `payment_reconcile_after_seconds` | marked "placeholder, needs owner approval" in `03`, `05` |
| P11 | Cancellation fee | 50000 kobo (500 naira), flat, after assignment | setting `cancellation_fee_minor` (B9) | the owner approved it as a placeholder held in a setting, not hard coded |
| P12 | Test support admin | `dddddddd-0000-0000-0000-000000000001` | named in the settings seed; the 10 audit rows of the seed credit it | a seed-A test row; a real support admin must replace it before real use |
| P13 | Distance and duration estimator | straight-line distance x 1.3, speed 8.33 m/s | `06` EP01 | the routing method is not designed |
| P14 | Rate limits | quotes 10/min, pings 1/s per trip, other writes 30/min, reads 120/min | `06` section 1.8 | chosen without traffic figures |
| P15 | Webhook scheme | HMAC-SHA256 of timestamp + body, 5-minute window, fields `provider_event_id`, `provider_reference`, `event_type`, `amount_minor`, `currency`, `occurred_at`, `failure_reason` | `06` EP19 | the provider is unnamed |
| P16 | Idempotency timings | key lasts 24 hours; a stuck payment key is taken over after 120 seconds; lock wait 800 ms | `06` section 1.7, EP15 | chosen, not measured against real traffic |
| P17 | API limits | addresses 1 to 300 characters, reasons 1 to 500, notes 1 to 2000, comment up to 500, body up to 16 KiB, list page 20 (maximum 100), open requests maximum 50 | `06` | chosen |
| P18 | Event stream settings | heartbeat 20 s, location one event per 2 s, 15-minute maximum life, close at token expiry, 2 open streams per rider per trip, poller every 1 s | `06` EP27, `08` | designs; nothing was served over HTTP |
| P19 | Cursor secret | not created | `06` section 1.9 | the signing secret belongs in the environment, never in the project |

Applied for real in the database (CONFIRMED): P2 to P8 by the settings seed (10 rows, `evidence/seed_sample_settings_applied.txt`), and P9 to P11 since Stage 3.

## 2. Owner decisions (each blocks something; my recommendation is given, not assumed)

| # | Decision | Recommendation | What it blocks or changes |
|---|---|---|---|
| D1 | **Fare model:** fixed upfront price (the fare equals the quote and the driver cannot change it) or metered | fixed upfront (what `06` EP12 assumes) | EP12 completion rule, the refund and dispute story, whether the fare can change after the ride |
| D2 | **Cancellation fee:** flat 500 naira after assignment, none before | keep flat, held in a setting | `trip_enforce_transition` already applies it; changing the rule needs a new rule, not only a number |
| D3 | **Request timeout** (600 s) and **payment reconcile-after** (900 s) | confirm or change the two settings | the two scheduled jobs (not built) |
| D4 | **Settings values:** city, base fare, per kilometre, per minute, quote life, service-area box, job intervals (P1 to P8) | confirm city and numbers | EP01 prices, the 422 `outside_service_area` rule, the jobs |
| D5 | **Webhook provider:** name, signature scheme, field names, refund handling (P15) | pick the provider first, then replace the adapter | EP19, JB2, EP15 and EP21 (they call the provider). Design assumption written in docs\06 section 1.11 and in EP15, EP19 and EP21; owner may replace. |
| D6 | **Rate limits** (P14) | measure real traffic before fixing numbers | API gateway or middleware |
| D7 | **Support visibility:** today any support admin sees and cancels any trip and payment (known limit) | add role-scoped access (by region, case or level) before real use | `06` section 1.3, a new database rule if wanted |
| D8 | **Q5, location retention:** no period chosen, blocked on legal advice (NDPA 2023 was not read) | get legal advice, then add a purge job for `location_ping` | the only requirement with no endpoint; retention of the most sensitive data |
| D9 | **Q6, a driver who never arrives:** the rider still pays the fee if they cancel after assignment | no fee when the driver is more than a stated number of minutes late, in a setting (name reserved: `driver_late_minutes_no_fee`) | the cancellation rule and EP14; open since Stage 1 |
| D10 | **B4 against B8 (decision 1 of `04` question 4):** five text columns may be blanked by the erasure functions on frozen rows | approved; recorded in section 6, item 1 (built in migrations 006 and 009) | erasure of riders and drivers |
| D11 | **The 62 bulk trips with a misplaced `seq`:** left as they are | recorded as accepted (`05` item 13); only the bulk set is affected | replay order of those 62 trips in the stream |
| D12 | **Manual refunds of failed payments leave no money record** (known gap, non goal) | accept for the assignment, or add a record later | B10 is not checked for those refunds |
| D13 | **Authentication design:** token format, lifetime, revocation, who creates accounts | design before the API is built; the contract only assumes a role and a subject id | every endpoint; the 15-minute stream cut-off. Design assumption written in docs\06 section 1.10 (baseline: short lived tokens with a person status check on every request; a denylist is an optional hardening); owner may replace. |
| D14 | **Real-time:** adopt SSE for the rider watch (EP27); optionally a `NOTIFY` doorbell by a later migration | SSE; poller first, doorbell only if latency matters | `08`; a migration 017 if the doorbell is wanted |
| D15 | **REST `fields` and `expand` parameters;** GraphQL | stay on REST for the MVP; add `fields` and `expand` only when a client needs them | `07` |
| D16 | **Distance estimator:** choose a routing method or provider (P13) | decide before EP01 is built | quote price and duration. Design assumption written in docs\06 EP01 (the price rule and the distance estimator interface); owner may replace. |
| D17 | **TripSummary change** (driver name in the rider's list) | done in the contract in Stage 4 close; confirm | `06` EP06 |

## 3. Known limits (what the design does not do, or has not proved)

**Database and data**
- **62 bulk trips (299 history rows) have a history row numbered out of order** (`05` item 13, CONFIRMED in `evidence/migration_010_seq_investigation.txt`). Accepted by the owner. A repair would need the append-only trigger switched off, which nobody approved.
- **The bulk set is not a concurrency test and its history times equal the load time** (`05` items 11 and 12).
- **Timings vary by about 3 times between runs** on this machine (A2.1 1.1 to 3.5 ms; a trip insert 7 to 31 ms; the payment-by-trip read 14.5 to 17.7 ms before migration 016). Every millisecond figure is an order of magnitude (`05` item 22).
- **`refund_payment_id_idx` has not been shown used** (the refund table has 1 row) and the open-requests query A2.1 costs more as the waiting list grows (`05` item 15).
- **Migration 016's lock:** `CREATE INDEX` took a SHARE lock on `payment` for about half a second in the dry run (493 ms); on a busy production table it would block payment writes for that time. A concurrent build is not possible inside a migration transaction. The migration file `016_payment_trip_id_index.sql` line 10 describes the lock as lasting "a few seconds"; the measured dry run was 493 ms, so the file's wording is not matched by the measurement (documented discrepancy; the migration is not edited).

**Security**
- **`pg_hba` trusts loopback and the local socket inside the container.** Any process in the container connects as any role with no password. Only other addresses use `scram-sha-256` (CONFIRMED in the login-role test). Not changed (`05` item 20).
- **Only three table names were attacked** in the search-path proofs (`audit_log`, `trip_status_history`, `status_transition_rule`). The other tables rely on the same two protections (migrations 013 and 014) but were not each attacked (`05` item 21).
- **The actor is claimed by the application.** The database checks that the claimed actor may make a move; it cannot prove who the actor is. A login role that is a member of `ridehail_app` can claim `support` (CONFIRMED, `05` items 7 and 18). A superuser can still switch triggers off.
- **Six RH codes cannot be raised by the application role** and one is dead under the current rule table (`06b` section 3, CONFIRMED in `evidence/untested_rh_codes_proofs.txt`).
- **Revocation lag on the stream:** a revoked token is cut off within the stream's 15-minute maximum, not at once (`08`).

**Tests that do not exist**
- **No concurrency tests beyond two:** a second insert of the same idempotency key waits and times out (55P03), and a second move of the same trip waits for the first (`evidence/api_idempotency_concurrency_test.txt`, `evidence/part_b_trip_row_lock_b.txt`). Nothing was raced for two drivers accepting the same trip, two refunds on one payment, or a repeated provider event (`05` item 10).
- **The out-of-order commit risk of a global poll on `seq` is reasoned, not demonstrated** (`08`).
- **Notification queue size and LISTEN behind a transaction-mode pool were not tested** (`08`).
- **No driver is installed, so the SQLSTATE field name is unconfirmed in any driver:** `06` section 1.6 says "to confirm in the chosen driver" and gives the names I expect for node-postgres, pgx, psycopg and JDBC from memory. Nothing was installed.
- **Nothing was run over HTTP:** no API exists (the `api\` folder is empty), no endpoint, no stream, no GraphQL, no webhook. The contracts were checked only as the SQL behind them (`06`, `07`, `08`).
- **Memory per open stream, proxy and load balancer behaviour, gzip effects, mobile background rules** are INFERRED.

**Design gaps stated on purpose**
- **B3, decimal money:** the database rounds 10.5 kobo to 11; only API validation stops it (`05` item 5).
- **Two scheduled jobs (timeout, reconciliation) and the settings' consumers are application code that does not exist.** If they are down, riders stay blocked by B1 until they cancel and payments stay pending (`03` section 8).
- **A payment started at the provider whose process dies before the payment row is written** is stored as `needs_support` when the webhook arrives (`06` EP15, known gap).
- **Coordinates inside `fare_quote` are not erased** (`05` item 4).

**Operations**
- **The container stopped uncleanly once** (Docker Desktop was not running on 2026-10-07; PostgreSQL recovered its log automatically and every row count and migration was intact, CONFIRMED).

## 4. Class notes still needed

I was not given the course notes and did not invent what they say. Every place where a course reference belongs is marked with the text `CLASS NOTE NEEDED` followed by the topic. As of this file:

| File | Line | Topic |
|---|---|---|
| `docs/07_over_fetching.md` | 166 | REST for an MVP (start of section 5) |
| `docs/07_over_fetching.md` | 200 | REST for an MVP (end of section 5) |
| `docs/08_real_time.md` | 15 | bidirectional vs unidirectional (start of the WebSocket and SSE comparison) |
| `docs/08_real_time.md` | 30 | bidirectional vs unidirectional (the recommendation, section 3) |

Four markers in two files, two topics. To fill one in, replace the marker line with the course's wording or reference, and keep my reasoning only where it agrees.

## 5. What the owner must still produce

- **Rendered diagram images** (entity diagram and the two state machines) as PNG or SVG. The Mermaid source exists inside `docs/02b_relationships.md` and `docs/03_state_machine.md` but has never been rendered, and no renderer is installed (nothing may be installed without asking).
- **Screenshots** (psql output, rendered diagrams, plans). All evidence in `evidence/` is text.
- **The Word document**, written only on request.
- **The decisions in section 2**, in particular D1, D4, D5, D8 and D9, because they block real use.
- **Legal advice for Q5** (NDPA 2023 retention).

## 6. Owner decisions recorded

Recorded on 7 October 2026. This section records what the owner decided. Where section 2 above still reads earlier than this record, this record is the later word.

Approved:

1. D10, erasure of text columns. Approved: the five text columns (`pickup_address`, `dropoff_address`, `driver_name_snapshot` and `vehicle_plate_snapshot` on `trip`, and `comment` on `rating`) may be blanked only by `erase_rider` and `erase_driver`, running under `ridehail_erasure_owner`.
2. D1, fare model. Approved as written.
3. D2, cancellation fee. Approved as written.
4. D3, request timeout and payment reconcile after. Approved as written.
5. D4, settings values. Approved as written.
6. D6, rate limits. Approved as written.
7. D7, support visibility. Approved as written.
8. D11, the 62 bulk trips with a misplaced `seq`. Approved as written.
9. D12, manual refunds of failed payments leave no money record. Approved as written.
10. D14, real time with SSE. Approved as written.
11. D15, REST `fields` and `expand` parameters, and staying on REST. Approved as written.
12. D17, the driver name in the rider's TripSummary. Approved as written.

Still open:

1. D5, webhook provider. Design assumption written in docs\06 section 1.11 and in EP15, EP19 and EP21; owner may replace.
2. D8, Q5 location retention.
3. D9, Q6 a driver who never arrives.
4. D13, authentication design. Design assumption written in docs\06 section 1.10 (baseline: short lived tokens with a person status check on every request; a denylist is an optional hardening); owner may replace.
5. D16, distance estimator. Design assumption written in docs\06 EP01 (the price rule and the distance estimator interface); owner may replace.
