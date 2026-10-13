# 06 API Contracts (Part A)

Contracts only: no code, no database change. A second engineer must be able to build every endpoint from this file and `06b_error_catalogue.md` without asking a question. Field names are the column names of `02_entities.md`, statuses are those of `03_state_machine.md`, and every endpoint cites requirement IDs from `01_requirements.md`. CONFIRMED means I ran it and kept the output (`evidence/api_*.txt`, test ids E01 to E43 are in `evidence/api_error_mapping_tests.txt`). INFERRED means I reasoned it. The over-fetching and real-time analyses are Part B and are not written here.

## 1. Conventions that apply to every endpoint

### 1.1 Format
- Base path `/v1`. Requests and responses are JSON, UTF-8, `Content-Type: application/json` (otherwise 415). The body is at most 16 KiB (otherwise 413).
- **Unknown body fields are rejected** (422 `validation_failed`, the field is named). Reason: the caller must not be able to send `rater_role`, `status`, `amount_minor` or `driver_id` and have them used. Those values come from the token or from the database.
- Ids are uuids. Timestamps are RFC 3339 UTC with microseconds (`2026-09-16T23:53:32.458283Z`).
- **Money is an integer number of kobo** in a field ending `_minor`, with a `currency` field beside it, always `"NGN"` (B3). A number that is not an integer (for example 10.5) is rejected with 422, because the database would round it silently (10.5 became 11, CONFIRMED in 04 question 2). One amount is at most 1,000,000,000 kobo.
- Coordinates are JSON numbers with at most 6 decimals (the columns are `numeric(8,6)` and `numeric(9,6)`; more decimals would be rounded silently). Latitude is -90 to 90, longitude is -180 to 180.
- Lists use the envelope `{"items": [...], "next_cursor": "..." or null}` (section 1.9).

### 1.2 Who calls (the authentication design assumption is in section 1.10)
A bearer token (`Authorization: Bearer <token>`) gives the API a **role** and a **subject id** (`sub`, a uuid). The API trusts only these two values from the token.

| Caller | How it is identified | `sub` is |
|---|---|---|
| rider | bearer token, role `rider` | `rider.id` |
| driver | bearer token, role `driver` | `driver.id` |
| support | bearer token, role `support` | `support_admin.id` |
| provider | no token. HMAC signature of the body (section EP19) | none |
| scheduler | internal process, no HTTP (section 5) | none |

A token of a person whose `deleted_at` is set, or of a support admin with `is_active = false`, is refused with 401 (INFERRED: the database does not check this).

### 1.3 Ownership checks (a random id is NOT authorisation)
Every endpoint that takes an id compares a column with `sub`. The comparison is part of the same SQL statement as the read or write (`... WHERE id = $1 AND rider_id = $2`), so there is no gap between the check and the use.

| Resource | Rider is allowed when | Driver is allowed when | Support |
|---|---|---|---|
| fare quote | `fare_quote.rider_id = sub` | never | never |
| trip (read, status history, ratings) | `trip.rider_id = sub` | `trip.driver_id = sub` | any |
| trip moves arrive, start, complete, locations | never | `trip.driver_id = sub` | never |
| trip accept | never | no ownership before assignment (any driver may take an open request); the move itself writes `driver_id = sub` | never |
| trip cancel | `trip.rider_id = sub` | `trip.driver_id = sub` | any |
| driver location | `trip.rider_id = sub` | never | any |
| payment (read) | the payment's trip has `trip.rider_id = sub` | never | any |
| payment start | `trip.rider_id = sub` | never | never |
| rating | `trip.rider_id = sub` (becomes `rater_role = rider`) | `trip.driver_id = sub` (becomes `rater_role = driver`) | read only |
| support endpoints | never | never | role `support` |

**Rule:** a failed ownership check returns **404 `not_found`** with the same body as an id that does not exist (never 403), so a stranger cannot learn that an id exists. A role that may never call an endpoint gets **403 `forbidden_role`**. The ownership column for a driver is `trip.driver_id`; while a trip is `requested` it is NULL and equals no caller, so a driver cannot touch a trip it has not accepted.

### 1.4 Session settings the API sets for the database
Every request runs in one database transaction on the role `ridehail_app` (never the dev superuser). The **first statement** of the transaction is:

`SELECT set_config('app.actor_role', $1, true), set_config('app.actor_id', $2, true);`

- The value comes **only from the authenticated caller**: `$1` is the token role (`rider`, `driver`, `support`), `$2` is `sub`. For the webhook it is `provider` and the empty string. For scheduled jobs it is `system` and the empty string. **Never from the request body, a header or a query string.**
- The third argument is `true` (transaction-local). Reason: with a connection pool the same database connection serves different callers, and a session-level value would leak to the next caller. Every database call of a request is inside that one transaction.
- The database trusts the claim. It checks that the claimed actor may make the move and that the claimed id is the trip's own rider or driver (`trip_enforce_transition`), but it cannot prove who the caller is. That proof is the API's job (limit 7 in docs 05).

### 1.5 Error body, and what never leaves the server
```
{"error": {"code": "rider_has_active_trip", "message": "You already have a trip in progress.", "request_id": "req_01J8...", "details": {"current_status": "requested"}}}
```
- `code` is machine readable and comes from `06b_error_catalogue.md`. `message` is a fixed plain-English sentence per code. `details` holds only safe, named fields.
- **A 500 never carries a database message.** A Postgres message can contain ids and values: `Key (rider_id)=(aaaaaaaa-...) already exists` and `Failing row contains (2812167e-..., ..., USD, ...)` are real examples (CONFIRMED, `evidence/proofs_rejected_and_extra.txt`). A 500 body has `code: internal_error`, the fixed message and the `request_id`, nothing else. The real error goes to the server log with the same `request_id`.
- Every response carries `X-Request-Id`. The caller may send its own (up to 64 characters); otherwise the API makes one.

### 1.6 How a database error becomes an HTTP status
The database driver gives the API the SQLSTATE, the constraint name (for 23xxx errors) and the message. **The API reads the SQLSTATE (and, for 23xxx, the constraint name). It never parses the message text: the text is for the server log only.** The API maps in this order:
1. **23505, 23503, 23514 (unique, foreign key, check):** by the constraint name (for example `trip_one_active_per_rider`).
2. **RHnnn (a trigger or function `RAISE EXCEPTION`, migration 015):** by the SQLSTATE alone. Every rule has its own code in the custom class `RH`; the table of 45 codes is in `06b` section 3. A SQLSTATE in class RH that is not in the table, and the old generic `P0001`, are `internal_error` plus an alert, never a guess (after migration 015 no function of ours raises P0001: CONFIRMED, 0 of 60 re-run tests, and all 45 codes have been raised: `evidence/untested_rh_codes_proofs.txt`).
3. **55P03 (lock timeout) on the idempotency insert:** `request_in_progress`. **40001 or 40P01 (serialization or deadlock):** retry the whole transaction once, then `service_unavailable`.
4. **42501 (permission denied), 23502 (not null), anything else:** `internal_error` (a role or API bug). Decision 14 of Part A (a distinct SQLSTATE for each rule) is done by migration 015: CONFIRMED in `evidence/migration_015_error_tests_compare.txt` (27 tests changed from P0001 to their RH code; every message text is unchanged).

**Driver note (INFERRED, to confirm in the chosen driver; no driver is installed and none was tested).** The API reads the SQLSTATE and the constraint name in exactly one place, a database error mapper that every request goes through, and nowhere else. The field name differs between drivers, so the mapper is the only code that must change when the driver is chosen. From each driver's documentation as I remember it, not verified: node-postgres `error.code` (SQLSTATE) and `error.constraint`; Go pgx `PgError.Code` and `PgError.ConstraintName`; Python psycopg 3 `exc.sqlstate` and `exc.diag.constraint_name`, psycopg2 `exc.pgcode` and `exc.diag.constraint_name`; Java JDBC `SQLException.getSQLState()` and, for the constraint name, the driver's server-error object (pgjdbc `ServerErrorMessage.getConstraint()`); a driver that gives no field for the constraint name must not be chosen, because this contract forbids reading the message; an ORM may wrap the driver error (SQLAlchemy `exc.orig`). Mark: **to confirm in the chosen driver**, by raising `RH005` and a 23505 and printing the two fields.

### 1.7 Idempotency in this API
Three mechanisms. Each endpoint says which one it uses.

**(a) Keyed: the `Idempotency-Key` header.** Only two rider actions use the table `idempotency_key`: `POST /v1/trips` (action `request_trip`) and `POST /v1/trips/{trip_id}/payments` (action `pay_trip`). Support refunds also take the header but cannot use the table (its `rider_id` is required), see EP21.
- The key is 1 to 128 printable ASCII characters without spaces; otherwise 400 `invalid_idempotency_key` (the database backstop is check `idem_key_length`, CONFIRMED E32).
- `request_hash` = SHA-256, 64 lowercase hex characters (check `idem_hash_format`), of: the action name, a newline, the path id (the `trip_id` for `pay_trip`, empty for `request_trip`), a newline, and the body as canonical JSON (keys sorted, no whitespace).
- The unique constraint is `idem_one_key_per_rider_action` on (`rider_id`, `action`, `key`): a key is unique **per rider and action, not global** (CONFIRMED E31c: the same key under another action and under another rider is accepted).
- The first statement after the settings is `INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES (...) ON CONFLICT (rider_id, action, key) DO NOTHING RETURNING id`, with `expires_at` = now + 24 hours.

| Situation | What the API returns |
|---|---|
| The insert returned a row (first request) | does the work, stores `response_status` and `response_body` with `UPDATE`, answers normally |
| Same key, **same body**, response stored | replays the stored status and body, adds header `Idempotent-Replay: true` (CONFIRMED E31b: the insert returns no row, then the stored answer is read) |
| Same key, **different body** | 422 `idempotency_key_reuse` (the stored `request_hash` differs) |
| Same key, first request **still running** | for `POST /v1/trips` the work and the key are one transaction, so the second insert waits on the unique index until the first commits or rolls back. The API sets `lock_timeout = 800ms`; on timeout the answer is 409 `request_in_progress` with `Retry-After: 1` (CONFIRMED, concurrency test: SQLSTATE 55P03 "canceling statement due to lock timeout"; and a second session without a timeout waited about 3 seconds until the first ended, `evidence/api_idempotency_concurrency_test.txt`). For `POST /v1/trips/{trip_id}/payments` the key row is committed first (a provider call must not hold a database lock), so a row with `response_status` empty means running: 409 `request_in_progress` at once. If that row is older than 120 seconds the API treats the first request as crashed and finishes the work (section EP15) |
| First attempt failed with an error | nothing stored: the key row is rolled back (or, for payments, deleted), so the same key tries again |
| Key older than 24 hours | the row was deleted by job JB3 (or `expires_at` has passed): a new request |

Only **successful** (2xx) responses are stored. A retry after a 4xx gets the same 4xx again from the current state, which is the right answer.

**(b) State-based replay for trip moves.** `accept`, `arrive`, `start`, `complete`, `cancel` have no key. A repeated move by the caller who already made it returns **200 with the current trip** and `Idempotent-Replay: true`: the trip is already in the target status and the caller is the owner (for cancel also `cancelled_by_role` equals the caller role). Anything else is 409. CONFIRMED E07 and the walkthrough: the guarded update returns zero rows, a second query classifies the state.

**(c) Natural idempotency.** Reads. Erasure (running it twice is harmless). Ratings are not keyed: a second rating by the same side is 409 `already_rated` (`rating_one_per_role_per_trip`), and a client that timed out treats `already_rated` as success after reading `GET .../ratings`. Location pings and support notes are not idempotent: a duplicate ping or note is harmless.

### 1.8 Rate limits (assumption, decision 13)
Per caller: quotes 10 per minute; location pings 1 per second per trip; every other write 30 per minute; reads 120 per minute. Over the limit: 429 `rate_limited` with `Retry-After`.

### 1.9 List endpoints: the shared contract
Applies to EP06, EP07 (keyset pagination) and EP08 (bounded list). Worked example and plans are in EP06.
- **Sort: `created_at` descending, ties broken by `id` descending. Nothing else is offered.** Reason: the indexes are `trip_rider_history_idx` (`rider_id, created_at DESC, id DESC`) and `trip_driver_history_idx` (`driver_id, created_at DESC, id DESC`). Any other sort needs a sort of all of a person's trips (CONFIRMED P7: Sort over a Bitmap Heap Scan, `evidence/api_list_endpoint_tests.txt`) and breaks keyset paging.
- **Keyset, not OFFSET.** The query asks for `limit + 1` rows; if the extra row exists there is a next page and `next_cursor` is built from the last item returned.
- **Page size:** `limit` default 20, minimum 1, maximum 100. Outside that range: 400 `invalid_filter` (the field `limit` is named).
- **Cursor:** opaque to the client. It is `base64url(payload) + "." + base64url(signature)`. The payload is JSON `{"v":1,"c":"<created_at of the last item>","i":"<id of the last item>","f":"<16 hex of SHA-256 of the caller and the filters>"}`. The signature is HMAC-SHA256 of the payload with a server secret read from the environment (never in code or in this project). The API refuses a cursor when the signature does not verify, `v` is not 1, `f` differs from the current caller and filters, or `c` or `i` do not parse: **400 `invalid_cursor`**. Binding `f` means a cursor cannot be moved to another caller or reused with other filters.
- **Filters** (rider and driver lists): `status` (one or more of `requested`, `assigned`, `arrived`, `started`, `completed`, `cancelled`, comma separated), `created_from` and `created_to` (RFC 3339; `created_at >= created_from` and `created_at < created_to`). Any other query parameter, an unknown status, a bad date, or `created_from` not before `created_to`: **400 `invalid_filter`**. `status` is applied as a filter on the index scan (CONFIRMED P2), and the date range is an index condition because `created_at` is the second index column (CONFIRMED P3).
- A page after the last returns `{"items": [], "next_cursor": null}` with 200.

### 1.10 Authentication design assumption (D13)
**DESIGN ASSUMPTION, owner may replace.** Owner decision D13 stays open in `09_open_items.md`. This section is written so that a second engineer can build the token check without asking anyone. Nothing in it was run; every statement is a design (INFERRED) except the one database fact marked CONFIRMED.

**The API verifies tokens. It never issues them.** An identity service outside this project, not named here, issues them.

**1. Token format.** A signed bearer token, sent as `Authorization: Bearer <token>`. It is a compact token with a header, a set of claims and a signature. The identity service signs it with a private key; the API holds only public verification keys. One signature algorithm is fixed in the API configuration (for example ES256). The API accepts only that algorithm, and refuses a token that asks for no signature or for another algorithm. The header carries a key id. The API keeps two public keys at a time, the current one and the previous one, so a key can be rotated without refusing tokens that are still alive. The keys come from configuration or from the environment, never from the repository.

**2. Claims the API trusts (seven).**
* `iss`, the issuer. It must equal the issuer in the configuration.
* `aud`, the audience. It must equal the audience configured for this API.
* `sub`, the subject, a uuid. It becomes `app.actor_id`.
* `role`, one of `rider`, `driver` or `support`. It becomes `app.actor_role`.
* `iat`, issued at, and `exp`, expiry, both in seconds since 1 January 1970.
* `jti`, a unique token id (a uuid).
Two of these carry data the API uses (`sub` and `role`). The other five are used only to decide whether to accept the token.

**3. Claims the API ignores.** Every other claim: names, phone numbers, emails, scopes, permissions, a `rider_id`, `driver_id` or `actor_id` claim, or a claim that names a database role. They are never copied into a session setting, a response or a log line. Reasons: personal data is kept to the minimum that is needed (B8), and a token must not be able to widen itself.

**4. An example set of claims** (values masked):
```json
{"iss": "****", "aud": "****", "sub": "****", "role": "rider", "iat": 1790000000, "exp": 1790000900, "jti": "****"}
```

**5. Lifetime.** An access token lives 15 minutes. The API refuses a token when `exp` minus `iat` is more than 900 seconds, and it allows 30 seconds of clock difference on `iat` and `exp`. Refresh is handled outside this API: the app presents its refresh credential to the identity service and receives a new access token. This API never sees, stores or checks a refresh credential.

**6. Who issues it, and how the role claim is obtained.** The identity service, from its own account records. One account has exactly one role. A person who is both a rider and a driver has two accounts, with two different subject ids (`rider.id` and `driver.id` are different rows). A support person's subject id is `support_admin.id`. The client cannot choose its role: the API never reads a role from a header, a query string or a body.

**7. Revocation. Baseline: short life only. Option: a denylist.**

*The baseline (what the API does unless the owner adds the option).*
* An access token lives at most 15 minutes (item 5).
* On every request the API checks the person's status by primary key: `deleted_at` for a rider or a driver, `is_active` and `deleted_at` for a support admin (item 8). The answer may be remembered for at most 60 seconds. So a deleted rider or a deactivated admin is cut off at the API within about a minute, whatever the token says.
* **The exposure, stated plainly:** a stolen token that is still valid works until it expires, for up to 15 minutes, as the person it names, and the API has no way to refuse it before then. For a support token that means up to 15 minutes of access to every trip and payment (the known limit D7). The status check does not help, because the stolen token belongs to a person who is still active.
* Cost of the baseline: nothing extra to run and nothing to keep in step. It adds one read by primary key per request, usually answered from the 60 second memory.

*The option (the owner may add it at deployment): a denylist.*
* What it is: a list kept in a shared fast key value store outside this database. It has two kinds of entry. A token id entry refuses one token (`jti`). A subject cutoff entry refuses every token of one subject that was issued before a stated time. Entries are removed when they can no longer matter: a token id entry at that token's `exp`, a subject cutoff entry 15 minutes and 30 seconds after its time. When the option is deployed, the API checks the list on every request and at every stream connect (step 6 of item 9). The identity service writes entries when someone logs out, is deactivated or reports a stolen token, and the API writes a subject cutoff itself in EP25 and EP26.
* Cost: one keyed read per request (INFERRED; not measured); a new component to run, watch and secure; and a new way to fail. The API **fails closed**: if the store cannot be reached it answers 503 `service_unavailable` (not 401, because the caller is not at fault). **An outage of the store therefore takes the whole API down for every caller.** That is the price of never accepting a revoked token.
* When it is worth it (INFERRED): for support tokens, because they reach every trip and every payment, or for a high value deployment where 15 minutes of use of a stolen token is not acceptable. For a small deployment of riders and drivers the baseline is simpler and cheaper.
* The list is not a table of `ridehail_design`. No table and no migration is added to the database either way.

**8. A deleted rider or a deactivated admin is refused in two layers (three if the optional denylist is added).**
1. The identity service stops issuing tokens for that account (outside this project). Tokens that were already issued stay valid until they expire.
2. The API reads the person's status for the subject of the token: `rider.deleted_at`, `driver.deleted_at`, or `support_admin.is_active` and `support_admin.deleted_at`. A rider or driver with `deleted_at` set, or an admin with `is_active` false or `deleted_at` set, is refused with 401 `unauthenticated`. The read is by primary key. The answer may be remembered for up to 60 seconds, so the person is cut off at the API within about a minute even though the token is still valid. These columns exist and have these types (CONFIRMED, `evidence/stage5_prep2_design_columns.txt`, C1).
3. Optional, only if the denylist of item 7 is deployed: a subject cutoff entry cuts the person off at once.
The database does not make this check (it only checks that the claimed actor may make the move), so layer 2 is the only protection at the API that does not depend on the identity service (section 1.2).

**9. The order of checks on every request.** The first failure ends the request.
1. A token is present and is well formed.
2. The signature verifies with the configured algorithm and a key from the key set.
3. `iss` and `aud` match the configuration.
4. `exp` has not passed, `iat` is not in the future, and `exp` minus `iat` is at most 900 seconds (with the 30 second allowance).
5. `role` is one of the three values, and `sub` is a valid uuid.
6. Only if the optional denylist is deployed (item 7): `jti` and `sub` are not in the denylist. Without the denylist this step does nothing.
7. The person is active (item 8, layer 2).
8. The role is allowed to call this endpoint, otherwise 403 `forbidden_role`.
9. Ownership of the resource is checked inside the SQL statement (section 1.3), otherwise 404 `not_found`.
Checks 1 to 7 all fail with the same answer: 401 `unauthenticated`, the same body each time, with no hint about which check failed. The one exception is a key set that cannot be reached, or the optional denylist when it is deployed and cannot be reached, which is 503 `service_unavailable` (item 7). The server log keeps the reason with the request id.

**10. How the database actor settings are filled.** Only from the verified token. After checks 1 to 8, the first statement of the database transaction is `SELECT set_config('app.actor_role', $1, true), set_config('app.actor_id', $2, true)` with `$1` the `role` claim and `$2` the `sub` claim (section 1.4). Nothing else ever fills them: not the body, not a header, not a query string, not another claim. The provider webhook uses `provider` with an empty id and the scheduler uses `system` with an empty id; neither uses a token.

**11. The event stream (EP27).** The stream is verified at connect with checks 1 to 8. It ends when the token expires (the last event is `end` with reason `token_expired`) or after 15 minutes, whichever comes first. The person status (and the denylist, if it is deployed) is checked at connect only, so a token that stops being acceptable during a stream, for example a stolen token or a deleted person, is cut off within the 15 minute limit and not before (this matches `08_real_time.md`). The client then gets a fresh access token from the identity service and reconnects with the last event id it saw (the resume rule of EP27). A stream never carries the token in its address.
**12. Out of scope for this API.** Sign up, login (passwords, one time codes, social login), password reset, creating and deleting accounts in the identity service, multi factor checks, handling of refresh credentials, issuing tokens, custody of the signing key, throttling of login attempts, and lists of a person's sessions. EP25 and EP26 erase ride hailing records only; they do not delete the account in the identity service.

**13. What the owner may replace.** The 15 minute lifetime, the 30 second allowance, the 60 second status memory, whether to add the optional denylist (and with it the fail closed rule for the store), the algorithm, and the identity service itself. What must stay: the API verifies and never issues, `role` and `sub` come only from the verified token, and the database actor settings are filled only from them.

### 1.11 Payment provider contract the API needs (D5)
**DESIGN ASSUMPTION, owner may replace.** Owner decision D5 stays open in `09_open_items.md`. The provider is not named. This section lists what the API needs from ANY provider, as five capabilities, and says what in the design would change if a provider lacked one. All of it is a design (INFERRED); the database facts quoted are CONFIRMED in `evidence/stage5_prep2_design_columns.txt` (C2 and C3).

Money rule for every capability: amounts are whole kobo in an integer, currency NGN. If a provider counts in naira with decimals, the adapter converts at the edge. The database is never asked to convert (a decimal such as 10.5 would be rounded silently, `04_hard_questions.md` question 2).

**C1. Create a payment with our idempotency key and return a reference.**
* Input: the amount in kobo, the currency, the payment method token from the provider's own client library, and our idempotency key (the key the rider sent for the payment request).
* Output: a provider reference (text, unique for this payment) and a status of pending. The same key with the same input must return the same reference and must not charge twice.
* Used by: EP15, step 2.
* If a provider lacks it: the API cannot safely repeat step 2 after a crash, so a double charge becomes possible. The design would have to change: a payment attempt must be recorded before the provider is called, which needs a new table or a reference on `payment` that may be empty, and both need a migration (today `payment.provider_reference` is required, CONFIRMED, C2). A reconciliation that finds charges at the provider that have no payment row would also be needed.

**C2. Query a payment by reference, including a clear answer of no record.**
* Input: a provider reference. Output: succeeded, failed, pending, or no record.
* Used by: JB2 (the reconciliation job), which turns a no record answer into a `payment_not_found` event. That event is the proof that move P3 needs.
* If a provider lacks it: JB2 cannot learn the result of a payment whose webhook was lost, and nothing can produce the proof for P3. The design would change in one of two ways: a new support endpoint to record a `payment_not_found` event by hand after support has checked the provider's own dashboard, or accepting that a stuck payment waits for its webhook for ever.

**C3. Send a signed webhook with a unique event id.**
* Output: a message with a signature we can verify, and an event id that is unique for each event and the same when the provider sends it again.
* Used by: EP19. The unique id is what makes a repeated message harmless (`provider_event_provider_event_id_key`, CONFIRMED, C3).
* If a provider has no signature: the signature check is replaced by a shared secret in the address plus a list of allowed source addresses. That is weaker and must be stated to the owner.
* If a provider has no unique event id: the API builds one by hashing the reference, the event type, the status and the provider's own time. Repeat detection then works only if the provider repeats identical data.
* If a provider has no webhooks at all: JB2 becomes the main way a result is learned, run at a short interval, and the rider waits up to one interval. EP19 is not used. C2 becomes required.

**C4. Refund by reference with our idempotency key.**
* Input: the provider reference of the payment, the amount in kobo, our idempotency key. Output: a refund reference, unique for this refund.
* Used by: EP21.
* If a provider lacks it: refunds are made by hand at the provider. EP21 changes so that support types the provider's refund reference into the request, and the API writes the refund row from it. The unique `refund_provider_reference_key` still stops the same refund being written twice. There is no automatic confirmation.

**C5. A sandbox mode.**
* A test environment with the same five capabilities and no real money.
* Used by: all tests of EP15, EP19 and EP21.
* If a provider lacks it: the team must write a fake provider that meets C1 to C4, test only against that fake, and take the first real money test at launch. That is a risk to state to the owner.

**The webhook scheme stays a placeholder.** The header names, the signature algorithm, the five minute replay window and the shape of the provider's own message are provider specific and will be replaced. What the database side needs from any webhook is fixed by the `provider_event` table:
* `provider_event_id`, text, required, unique.
* `provider_reference`, text, required.
* `event_type`, required, one of `payment_succeeded`, `payment_failed`, `payment_not_found`, `refund_succeeded` (`payment_not_found` is made by JB2, never sent by a provider).
* `amount_minor` and `currency`, optional, but both present or both absent. If a provider sends no amount, the API applies the result by reference alone and cannot compare amounts.
* `occurred_at`, optional, the provider's own time (its clock is not trusted).
The database fills `received_at`, `processed_at` and `outcome` itself. One more field is used by the API but is not stored in `provider_event`: `failure_reason`, which is copied to `payment.failure_reason` when the event type is `payment_failed` (the API writes a default text if the provider gives none, because a failed payment needs a reason).

## 2. Endpoint index

| Id | Method and path | Caller | App | Requirement IDs |
|---|---|---|---|---|
| EP01 | POST /v1/fare-quotes | rider | rider app | A1, B3, Q1 |
| EP02 | POST /v1/trips | rider | rider app | A1, B0, B1, B6 |
| EP03 | GET /v1/trips/{trip_id} | rider, driver, support | all three | A3, B4, U1, U2, U3 |
| EP04 | GET /v1/trips/{trip_id}/status-history | rider, driver, support | all three | A3, B5, U3 |
| EP05 | GET /v1/trips/{trip_id}/driver-location | rider, support | rider app, support console | A3, B8 |
| EP06 | GET /v1/riders/me/trips | rider | rider app | A3, U1, B8 |
| EP07 | GET /v1/drivers/me/trips | driver | driver app | A3, U2, B8 |
| EP08 | GET /v1/trip-requests | driver | driver app | A2, U2 |
| EP09 | POST /v1/trips/{trip_id}/accept | driver | driver app | A2, B2, U2 |
| EP10 | POST /v1/trips/{trip_id}/arrive | driver | driver app | A3, B5 |
| EP11 | POST /v1/trips/{trip_id}/start | driver | driver app | A3, B5 |
| EP12 | POST /v1/trips/{trip_id}/complete | driver | driver app | A3, B3, B4 |
| EP13 | POST /v1/trips/{trip_id}/locations | driver | driver app | A3, B8 |
| EP14 | POST /v1/trips/{trip_id}/cancel | rider, driver, support | all three | B9, B1, B2, B5, Q2, U3 |
| EP15 | POST /v1/trips/{trip_id}/payments | rider | rider app | A4, B3, B6, U1 |
| EP16 | GET /v1/payments/{payment_id} | rider, support | rider app, support console | A4, U3 |
| EP17 | POST /v1/trips/{trip_id}/ratings | rider, driver | rider app, driver app | A5, B7, Q3 |
| EP18 | GET /v1/trips/{trip_id}/ratings | rider, driver, support | all three | A5, B7 |
| EP19 | POST /v1/provider/webhooks | provider | provider only | A4, B5, B6, U4 |
| EP20 | POST /v1/support/payments/{payment_id}/fail | support | support console | A4, B6, U3, U4 |
| EP21 | POST /v1/support/payments/{payment_id}/refunds | support | support console | B10, B3, B4, U3, Q4 |
| EP22 | GET /v1/support/settings | support | support console | B9, U3 |
| EP23 | PUT /v1/support/settings/{key} | support | support console | B3, B7, B9, U3, Q1, Q2, Q3 |
| EP24 | POST /v1/support/notes | support | support console | B5, U3 |
| EP25 | POST /v1/support/riders/{rider_id}/erasure | support | support console | B8, U3 |
| EP26 | POST /v1/support/drivers/{driver_id}/erasure | support | support console | B8, U3 |
| EP27 | GET /v1/trips/{trip_id}/events | rider, support | rider app, support console | A3, B8, U1, U3 |
| JB1 | request timeout job (internal) | scheduler | none, not public | B9, B1 |
| JB2 | payment reconciliation job (internal) | scheduler | none, not public | A4, B6, U4 |
| JB3 | idempotency cleanup job (internal) | scheduler | none, not public | B6 |

## 3. Representations (what the response bodies contain)

**Derived fields (not columns; defined here):** `pickup_latitude`, `pickup_longitude`, `dropoff_latitude`, `dropoff_longitude` (from the trip's `fare_quote`), `estimated_amount_minor` and `estimated_currency` (the quote's `amount_minor` and `currency`), `payments` (array, see below), `refunds` and `provider_events` (support view of a payment), `items`, `next_cursor`, `outcome` (webhook answer), `estimate_confidence` (EP01, from the distance estimator, not stored). **Request-only fields (never stored):** `payment_method_token`, `confirm`.

**Quote** (EP01): `id`, `pickup_latitude`, `pickup_longitude`, `dropoff_latitude`, `dropoff_longitude`, `estimated_distance_m` (integer), `estimated_duration_s` (integer), `amount_minor` (integer), `currency`, `expires_at`, `created_at`, `estimate_confidence` (string, `routed` or `approximate`; derived, not stored).

**Trip** (EP02, EP03, EP09 to EP12, EP14). Visibility by caller:

| Field | Type | Rider | Driver | Support |
|---|---|---|---|---|
| `id` | uuid | yes | yes | yes |
| `status` | string, one of requested, assigned, arrived, started, completed, cancelled | yes | yes | yes |
| `rider_id` | uuid | yes (own) | no | yes |
| `driver_id`, `vehicle_id` | uuid or null | no | yes (own) | yes |
| `fare_quote_id` | uuid | yes | no | yes |
| `pickup_address`, `dropoff_address` | string | yes | pickup always; dropoff only after the driver accepted | yes |
| `pickup_latitude`, `pickup_longitude`, `dropoff_latitude`, `dropoff_longitude` | number | yes | pickup always; dropoff after accept | yes |
| `estimated_amount_minor`, `estimated_currency` | integer, string | yes | yes | yes |
| `driver_name_snapshot`, `vehicle_plate_snapshot` | string or null | yes | no | yes |
| `started_at`, `completed_at`, `cancelled_at` | timestamp or null | yes | yes | yes |
| `cancelled_by_role` | string or null | yes | yes | yes |
| `cancellation_fee_minor`, `cancellation_fee_currency` | integer or null, string or null | yes | no | yes |
| `fare_amount_minor`, `fare_currency` | integer or null, string or null | yes | yes | yes |
| `distance_m` | integer or null | yes | yes | yes |
| `payments` | array of {`id`, `purpose`, `status`, `amount_minor`, `currency`} | yes | no | yes |
| `created_at`, `updated_at` | timestamp | yes | yes | yes |

The rider never receives `driver_id`, and the driver never receives `rider_id` (data minimisation, B8). After an erasure `pickup_address`, `dropoff_address`, `driver_name_snapshot` and `vehicle_plate_snapshot` read `erased`.

**TripSummary** (list items EP06, EP07): `id`, `status`, `pickup_address`, `dropoff_address`, `created_at`, `completed_at`, `cancelled_at`, `fare_amount_minor`, `fare_currency`, `cancellation_fee_minor`, `cancellation_fee_currency`, and, **in the rider's list (EP06) only, `driver_name_snapshot`** (string or null). Source: `trip.driver_name_snapshot`, copied by the database when the driver accepts (null while the trip is `requested`; reads `erased` after the driver is erased). Who sees it: the rider, in the list of their own trips (EP06), and support (in EP03); the driver's list (EP07) does not carry it, nor the cancellation fee fields. The rider list item therefore has 12 fields and the driver list item 9. Added in Stage 4 close so that the rider's list row (status, pickup, dropoff, driver name, fare) needs no second request per row (`07_over_fetching.md` finding 1). This is a contract change; it is not built (no API exists).

**Payment** (EP15, EP16): `id`, `trip_id`, `purpose` (`fare` or `cancellation_fee`), `amount_minor`, `currency`, `status` (`pending`, `succeeded`, `failed`), `paid_at`, `failure_reason`, `created_at`. The support view adds `provider_reference`, `refunds` (array of Refund) and `provider_events` (up to 20 newest: `provider_event_id`, `event_type`, `received_at`, `outcome`).

**Refund**: `id`, `payment_id`, `amount_minor`, `currency`, `reason`, `created_by_admin_id`, `provider_reference`, `created_at`. **Rating**: `id`, `trip_id`, `rater_role`, `stars`, `comment`, `created_at`. **Setting**: `key`, `int_value`, `currency`, `description`, `updated_by_admin_id`, `updated_at`. **Location**: `latitude`, `longitude`, `accuracy_m`, `recorded_at`. **StatusHistoryItem**: `seq`, `from_status`, `to_status`, `actor_role`, `created_at`; support also gets `actor_rider_id`, `actor_driver_id`, `actor_admin_id`.

**Common errors** (every endpoint can return them; they are not repeated in each table): 401 `unauthenticated`, 403 `forbidden_role`, 404 `not_found`, 400 `bad_request`, 413 `payload_too_large`, 415 `unsupported_media_type`, 422 `validation_failed`, 429 `rate_limited`, 500 `internal_error`, 503 `service_unavailable`. Each endpoint table lists the errors specific to it and says which common ones apply.

## 4. Endpoints

### EP01 POST /v1/fare-quotes  (rider app; A1, B3, Q1)
**Who and ownership:** role `rider`. The quote's `rider_id` is `sub` (never from the body).
**Request:** headers `Authorization`, `Content-Type`. Body:

| Field | Type | Required | Limits |
|---|---|---|---|
| `pickup_latitude` | number | yes | -90 to 90, at most 6 decimals |
| `pickup_longitude` | number | yes | -180 to 180, at most 6 decimals |
| `dropoff_latitude` | number | yes | same |
| `dropoff_longitude` | number | yes | same |

**How the price is made (one rule, integer arithmetic).** **DESIGN ASSUMPTION, owner may replace** (D16 stays open in `09_open_items.md`).
1. The API asks the distance estimator (next paragraph) for `estimated_distance_m` and `estimated_duration_s`, both whole numbers.
2. It reads `base_fare_minor`, `per_km_minor` and `per_minute_minor` from `setting`.
3. It computes the price once. `amount_minor` is `base_fare_minor + per_km_minor * estimated_distance_m / 1000 + per_minute_minor * estimated_duration_s / 60`, **rounded half up to the whole kobo**. **There is exactly one rounding rule, and it is applied once, at the end. The three parts are never rounded on their own.** The estimator rounds its own distance and duration to whole metres and seconds; that is not fare rounding.
4. In integers, so that no floating point number is ever used: `amount_minor` is `(base_fare_minor * 3000 + per_km_minor * estimated_distance_m * 3 + per_minute_minor * estimated_duration_s * 50 + 1500) / 3000`, with integer division that drops the remainder, in 64 bit integers. The number 3000 is the smallest number that clears both divisions (1000 and 60), and 1500 is half of 3000, which makes the division round half up. The largest value the contract allows (every price at 1,000,000,000 kobo, 1,000,000 metres, 86,400 seconds) gives 7,323,000,000,001,500 before the division, which fits in a 64 bit integer (CONFIRMED, `evidence/stage5_prep2_fare_arithmetic.txt`, S6).
5. `currency` is `NGN`. `expires_at` is now plus `quote_validity_seconds`. Pickup and dropoff must both lie inside the rectangle of the four `service_area_*_e6` settings (degrees times 1,000,000).

**Worked example with the real setting values (CONFIRMED, `evidence/stage5_prep2_fare_arithmetic.txt`, S1 to S3).** The stored settings are base 50000, per kilometre 15000 and per minute 3000 kobo. Pickup 6.45, 3.39 and dropoff 6.50, 3.35 give, with the placeholder estimator, a straight line of 7110.249 metres, so 9243 metres and 1110 seconds. The parts are 15000 * 9243 / 1000 = 138645 kobo and 3000 * 1110 / 60 = 55500 kobo. The fare is 50000 + 138645 + 55500 = **244145 kobo** (2441 naira 45 kobo). The exact decimal sum, the sum rounded once, and the integer formula all give 244145. With these three prices no fraction ever appears (the kilometre part is 15 times the metres and the minute part is 50 times the seconds), so the rounding rule matters only if the owner changes the prices.

**Why one rounding (CONFIRMED, S4 and S5).** Take a hypothetical price list that is not stored: base 50000, per kilometre 12345, per minute 777, for 5001 metres and 1111 seconds. The parts are 61737.345 and 14387.450 kobo and the exact total is 126124.795. Rounding once at the end gives **126125**. Rounding each part and then adding gives 126124, one kobo less. The contract uses 126125, and the integer formula returns it. At the edge, exactly half a kobo rounds up to 1, 1.499 rounds to 1 and 1.5 rounds to 2.

**Distance estimator interface (D16, DESIGN ASSUMPTION, owner may replace).** No vendor is named.
* **Input:** two points, each a latitude and a longitude in decimal degrees (at most 6 decimals), the pickup and the dropoff.
* **Output:** `distance_m`, whole metres from 0 to 1,000,000; `duration_s`, whole seconds from 0 to 86,400; and a confidence flag, `routed` (the answer comes from a road route) or `approximate` (a straight line or another estimate). The two numbers fit the integer columns `fare_quote.estimated_distance_m` and `estimated_duration_s`, which must not be negative (CONFIRMED, C4).
* **Time limit:** the answer must arrive within 2 seconds (a placeholder). The API does not retry inside one request; the rider can ask again (the limit of 10 quotes a minute applies).
* **Failure:** no answer in time, a refusal, an unreadable answer, or any value outside the ranges above. The API answers **503 `estimator_unavailable`** (a new code, in `06b_error_catalogue.md`). **If the estimator does not answer, no quote is created:** no row is written to `fare_quote`, and the log keeps the reason with the request id.
* **The confidence flag** is returned to the app as the derived field `estimate_confidence` so the app can say "approximate price". It is not stored (the table has no column for it, and no migration is added), and it does not change the price. The price is fixed once it is quoted (D1, approved), so a poor estimate is a loss to the platform or an overcharge to the rider.
* **The placeholder:** a straight line, flat earth, `dy = (dropoff latitude minus pickup latitude) * 111320` metres and `dx = (dropoff longitude minus pickup longitude) * 111320 * cosine of the mean latitude` metres; the distance is the square root of `dx` squared plus `dy` squared, times 1.3, rounded to a whole metre; the duration is that distance divided by 8.33 metres per second (about 30 kilometres an hour), rounded to a whole second. It always reports `approximate`.
* **Why it must be replaced before real use (INFERRED):** it ignores roads, one way streets, water and traffic. The factor 1.3 and the speed 8.33 were not measured for any city. Because the fare is fixed upfront, every error in distance or time goes straight into the price.
**Success:** 201, header `Location: /v1/fare-quotes/{id}` is not offered (no read endpoint; the quote is used by id in EP02). Body: Quote, including the derived field `estimate_confidence`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 422 | `validation_failed` | a coordinate is out of range, has more than 6 decimals, or a field is missing or unknown | backstop: check `quote_coordinates_valid` (never reached) |
| 422 | `outside_service_area` | pickup or dropoff is outside the service area | none: API rule from the `setting` rows |
| 503 | `estimator_unavailable` | the distance estimator did not answer within 2 seconds, refused, or returned a value outside the allowed ranges (section: Distance estimator interface above) | none: no database object is involved and no `fare_quote` row is written |
| 503 | `service_not_configured` | a setting needed for the price, the validity or the area has no row | none. **CONFIRMED:** before the sample settings seed was applied the table held only 4 settings and the check found 0 of the 8 keys (`evidence/seed_sample_settings_before.txt`), so EP01 answered this error; after the seed it finds 8 of 8 (`evidence/seed_sample_settings_ep01_after.txt`). The error stays the answer whenever one of the 8 rows is missing |

Also: 401, 403, 429, 500, 503 (common).
**Idempotency:** not idempotent, on purpose. Every call makes a new quote (append-only, expires by itself, limited to 10 per minute per rider). The idempotent step is EP02.
**Session settings:** `app.actor_role = rider`, `app.actor_id = sub`.

### EP02 POST /v1/trips  (rider app; A1, B0, B1, B6)
**Who and ownership:** role `rider`. The trip's `rider_id` is `sub`. The quote must satisfy `fare_quote.id = body.fare_quote_id AND fare_quote.rider_id = sub`.
**Request:** headers `Authorization`, `Content-Type`, **`Idempotency-Key` (required)**. Body:

| Field | Type | Required | Limits |
|---|---|---|---|
| `fare_quote_id` | uuid | yes | a quote of this rider that has not expired and has not started a trip |
| `pickup_address` | string | yes | 1 to 300 characters, not blank |
| `dropoff_address` | string | yes | 1 to 300 characters, not blank |

**Flow (one transaction):** set the actor; insert the idempotency row; read the quote with the ownership condition; `INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)` (status defaults to `requested`; the trigger writes the history row `(new) > requested`); `UPDATE idempotency_key SET response_status = 201, response_body = ..., trip_id = ...`. CONFIRMED in the walkthrough, `evidence/api_walkthrough_tests.txt`.
**Success:** 201, header `Location: /v1/trips/{id}`, body Trip (rider view, `status` = `requested`). A replay returns the same 201 body with `Idempotent-Replay: true`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `rider_has_active_trip` | the rider already has a trip in requested, assigned, arrived or started | unique index `trip_one_active_per_rider`, "duplicate key value violates unique constraint "trip_one_active_per_rider"" (E01) |
| 404 | `quote_not_found` | no quote with that id for this rider (unknown id, or another rider's quote) | ownership query; backstop FK `trip_quote_belongs_to_rider`, "insert or update on table "trip" violates foreign key constraint "trip_quote_belongs_to_rider"" (E02a, E02b) |
| 409 | `quote_already_used` | the quote already started a trip | unique `trip_fare_quote_id_key` (E03) |
| 422 | `quote_expired` | the quote's `expires_at` has passed | trigger `trip_enforce_transition`, SQLSTATE `RH004` (message "fare quote % has expired", E04); the API also checks `expires_at` first |
| 400 | `invalid_idempotency_key` | header missing, empty, longer than 128, or has a space | backstop check `idem_key_length` (E32) |
| 422 | `idempotency_key_reuse` | the key was used with a different body | none: the stored `request_hash` differs |
| 409 | `request_in_progress` | the same key is still being processed | SQLSTATE 55P03 on the idempotency insert (concurrency test) |
| 422 | `validation_failed` | an address is blank or too long, `fare_quote_id` is not a uuid, a field is unknown | none |

Also: 401, 403, 429, 500, 503 (common). **Order of checks:** replay and key checks come first, so a retry with the same key never returns `rider_has_active_trip` (it replays the 201). A new key after a success does return it.
**Idempotency:** keyed (section 1.7a), action `request_trip`. A retry cannot create a second trip: the stored answer is replayed, and even without it `trip_one_active_per_rider` and `trip_fare_quote_id_key` refuse a second trip.
**Session settings:** `rider`, `sub`.

### EP03 GET /v1/trips/{trip_id}  (all three apps; A3, B4, U1, U2, U3)
**Who and ownership:** rider (`trip.rider_id = sub`), driver (`trip.driver_id = sub`), support (any). Not the owner: 404.
**Request:** path `trip_id` (uuid). No query parameters, no body.
**Success:** 200, body Trip in the caller's view (section 3). This is what the rider polls to watch the trip (A3). Header `ETag` is the `updated_at` value (decision: lets the app send `If-None-Match` and get 304).
**Errors:** `not_found` (404; id unknown or not the caller's), `validation_failed` (422; `trip_id` is not a uuid). Also 401, 403, 429, 500, 503 (common). **Database cause:** none (a read). **Index (migration 016, CONFIRMED, `evidence/migration_016_measure_before.txt` and `_after.txt`):** the `payments` array reads every payment of the trip. Before migration 016 no index served that read (the only trip index, `payment_one_live_per_purpose`, is partial), so it was a parallel sequential scan of the payment table, 14.5 to 17.7 ms at 169,410 rows. It now uses `payment_trip_id_idx`: 0.06 to 0.10 ms for the payments read and 0.14 to 0.32 ms for the whole EP03 read. See `07_over_fetching.md` finding 2.
**Idempotency:** natural (read). **Session settings:** the caller's role and `sub` (the same transaction setup is used for reads so that every request is handled the same way).

### EP04 GET /v1/trips/{trip_id}/status-history  (A3, B5, U3)
**Who and ownership:** as EP03.
**Success:** 200, `{"items": [StatusHistoryItem, ...]}` ordered by `seq` ascending (CONFIRMED, plan uses `trip_status_history_trip_seq_idx`). A trip has at most about 6 rows, so there is no cursor and `next_cursor` is not sent. Riders and drivers get no actor ids; support does.
**Errors:** `not_found`. Common as EP03. **Database cause:** none.
**Idempotency:** natural. **Session settings:** the caller's.

### EP05 GET /v1/trips/{trip_id}/driver-location  (A3, B8)
**Who and ownership:** rider (`trip.rider_id = sub`) and support. Not the owner: 404.
**Success:** 200, `{"location": Location}` with the newest ping, or `{"location": null}` if the driver has not sent one yet. Query: `SELECT latitude, longitude, accuracy_m, recorded_at FROM location_ping WHERE trip_id = $1 ORDER BY recorded_at DESC LIMIT 1` (index `location_ping_trip_recorded_idx`, CONFIRMED). Rate: at most 1 call per second per rider and trip.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `trip_not_in_progress` | the trip is not assigned, arrived or started (a rider may see the driver's position only while the trip runs, B8) | none: API rule on `trip.status` |
| 404 | `not_found` | unknown or not the rider's trip | none |

Also common. **Idempotency:** natural. **Session settings:** the caller's.

### EP06 GET /v1/riders/me/trips  (rider app; A3, U1, B8)
**Who and ownership:** role `rider`. The list is `WHERE rider_id = sub`; there is no `rider_id` parameter.
**Request:** query `limit`, `cursor`, `status`, `created_from`, `created_to` (section 1.9). Example: `GET /v1/riders/me/trips?limit=3`.
**Query:** `SELECT id, status, pickup_address, dropoff_address, driver_name_snapshot, created_at, completed_at, cancelled_at, fare_amount_minor, fare_currency, cancellation_fee_minor, cancellation_fee_currency FROM trip WHERE rider_id = $1 [AND status = ANY($2)] [AND created_at >= $3] [AND created_at < $4] [AND (created_at, id) < ($5, $6)] ORDER BY created_at DESC, id DESC LIMIT $7 + 1`. **Index: `trip_rider_history_idx`**. CONFIRMED (`evidence/api_list_endpoint_tests.txt`): no filter, `Index Scan using trip_rider_history_idx`; with `status`, the same index plus `Filter: status = ANY(...)`; with a date range, an index condition on `created_at`; with cursor, status and range together, the same index. No Seq Scan.
**Success:** 200, TripSummary items. **Worked example** (real rows of rider `10000000-0000-0000-0000-000000000777`, who has 40 trips; the signature is masked):

Request: `GET /v1/riders/me/trips?limit=3`

```
{"items": [
  {"id": "40000000-0000-0000-0000-000000198904", "status": "completed", "pickup_address": "BULK pickup 198904", "dropoff_address": "BULK dropoff 198904", "driver_name_snapshot": "BULK Driver 217", "created_at": "2026-10-04T08:33:32.458283Z", "completed_at": "2026-10-06T18:11:00.519301Z", "cancelled_at": null, "fare_amount_minor": 108000, "fare_currency": "NGN", "cancellation_fee_minor": null, "cancellation_fee_currency": null},
  {"id": "40000000-0000-0000-0000-000000193904", "status": "completed", "created_at": "2026-09-25T16:13:32.458283Z", "...": "same fields"},
  {"id": "40000000-0000-0000-0000-000000188904", "status": "completed", "created_at": "2026-09-16T23:53:32.458283Z", "...": "same fields"}],
 "next_cursor": "eyJ2IjoxLCJjIjoiMjAyNi0wOS0xNlQyMzo1MzozMi40NTgyODNaIiwiaSI6IjQwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDE4ODkwNCIsImYiOiJkMzdjMGVjNmRkNWQzM2RmIn0.****"}
```
The cursor payload decodes to `{"v":1,"c":"2026-09-16T23:53:32.458283Z","i":"40000000-0000-0000-0000-000000188904","f":"d37c0ec6dd5d33df"}`. The database returned 4 rows for `limit + 1`, and the fourth (`...183904`) is why a next page exists. Page 2: `GET /v1/riders/me/trips?limit=3&cursor=<that value>` runs the query with `(created_at, id) < ('2026-09-16 23:53:32.458283+00', '...188904')` and returns `...183904`, `...178904`, `...173904` (CONFIRMED, L2). With filters: `?status=completed,cancelled&created_from=2026-05-01T00:00:00Z&created_to=2026-07-01T00:00:00Z&limit=5` gives a different `f` (`f856a01ad82920b7`), so a cursor from the unfiltered list is refused.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 400 | `invalid_cursor` | signature fails, `v` is not 1, `f` does not match this caller and these filters, or `c` or `i` do not parse | none |
| 400 | `invalid_filter` | unknown query parameter, `limit` outside 1 to 100, unknown status, bad date, `created_from` not before `created_to` | none |

Also common (401, 403, 429, 500, 503). **Idempotency:** natural. **Session settings:** `rider`, `sub`.

### EP07 GET /v1/drivers/me/trips  (driver app; A3, U2, B8)
Identical to EP06 with these differences: role `driver`; `WHERE driver_id = sub`; **no `driver_name_snapshot`** (a driver's list does not carry the driver's own name); index **`trip_driver_history_idx`** (CONFIRMED P5 and P6: `Index Only Scan` without filters, `Index Scan` with cursor and status, no Seq Scan); the item fields are TripSummary as the driver may see them (no `cancellation_fee_minor`, no `cancellation_fee_currency`); the driver has 249 trips in the example data (driver `20000000-0000-0000-0000-000000000500`). Errors, idempotency and session settings as EP06 (`driver`, `sub`).

### EP08 GET /v1/trip-requests  (driver app; A2, U2)
**Who and ownership:** role `driver`. No ownership check: open requests are visible to every driver in range. Data minimisation: the item has no rider identity and no dropoff.
**Request:** query `latitude`, `longitude` (the driver's position, required), `radius_m` (default 3000, 100 to 10000), `limit` (default 20, 1 to 50). The API turns the radius into a rectangle: latitude plus or minus `radius_m / 111320`, longitude plus or minus `radius_m / (111320 * cos(latitude))`.
**Query:** the A2.1 query with `LIMIT $limit`: `FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.status = 'requested' AND q.pickup_latitude BETWEEN ... AND q.pickup_longitude BETWEEN ... ORDER BY t.created_at LIMIT n`. **Order: `created_at` ascending (oldest request first, for fairness)**, the opposite of the history lists, because this is a queue and not a history. The query must repeat `status = 'requested'` exactly or `trip_requested_created_at_idx` is not used (CONFIRMED in 04 question 7).
**Pagination:** none (decision 9). The list is a live set that changes every second, so a cursor would skip or repeat rows; it is bounded by `limit` and the envelope has `next_cursor: null` always. **Cost warning (CONFIRMED):** the plan is a bitmap scan, a sort and one `fare_quote` lookup per waiting trip, 1.1 to 3.5 ms for 401 waiting trips, and it grows with the waiting list (the rectangle is on `fare_quote`).
**Success:** 200, `{"items": [{"id", "pickup_address", "pickup_latitude", "pickup_longitude", "estimated_amount_minor", "estimated_currency", "estimated_distance_m", "created_at"}], "next_cursor": null}`.
**Errors:** `validation_failed` (422: position missing or out of range), `invalid_filter` (400: `radius_m` or `limit` out of range, unknown parameter). Common. **Database cause:** none.
**Idempotency:** natural. **Session settings:** `driver`, `sub`.

### EP09 POST /v1/trips/{trip_id}/accept  (driver app; A2, B2, U2)
**Who and ownership:** role `driver`. Before the move there is no owner. The move writes `driver_id = sub`; the trigger then requires the claimed actor to equal `NEW.driver_id`.
**Request:** path `trip_id`. Body (optional): `vehicle_id` (uuid). If absent, the API uses the driver's only active vehicle: `SELECT id FROM vehicle WHERE driver_id = sub AND is_active AND deleted_at IS NULL` (index `vehicle_driver_id_idx`). Zero vehicles: 422 `no_active_vehicle`; several vehicles and no `vehicle_id`: 422 `validation_failed`.
**Move (all moves share this shape):** `UPDATE trip SET status = 'assigned', driver_id = $sub, vehicle_id = $v WHERE id = $trip AND status = 'requested' RETURNING ...`. The trigger copies the driver name and the plate into the snapshots. **Zero rows** means: the trip does not exist (404), or it is already assigned to this caller (200 replay), or it is not open (409 `trip_not_open`). CONFIRMED E07 and the walkthrough.
**Success:** 200, Trip (driver view, including `dropoff_address` and the dropoff coordinates now that the driver accepted).
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `trip_not_open` | the trip is not `requested` any more (another driver took it, the rider cancelled, the timeout job cancelled it) | zero rows from the guarded update (E07). Without the guard the trigger would raise `RH005` ("trip is cancelled (terminal)...") or `RH006` ("driver_id cannot change once set (F10)", E39, internal) |
| 409 | `driver_has_active_trip` | the driver already has an assigned, arrived or started trip | unique index `trip_one_active_per_driver` (E08) |
| 404 | `vehicle_not_found` | `vehicle_id` is not an active vehicle of this driver | API query; backstop FK `trip_vehicle_belongs_to_driver` (E09) |
| 422 | `no_active_vehicle` | the driver has no active vehicle | none: API query |
| 404 | `not_found` | unknown trip id | none |

Also common. **Idempotency:** state-based replay (1.7b): trip already `assigned` with `driver_id = sub` returns 200 with `Idempotent-Replay: true`. Two drivers accepting at once: the second update waits for the row lock and then finds the status changed, so it returns zero rows and 409 (INFERRED from Postgres behaviour; not raced).
**Session settings:** `driver`, `sub`.

### EP10 POST /v1/trips/{trip_id}/arrive  (driver app; A3, B5)
**Who and ownership:** role `driver`; `trip.driver_id = sub` (in the `WHERE`). **Request:** path only, no body. **Move:** `UPDATE trip SET status = 'arrived' WHERE id = $1 AND driver_id = $sub AND status = 'assigned' RETURNING ...`. Zero rows: classify by reading the trip: not the caller's or missing: 404; status already `arrived`: 200 replay; `completed` or `cancelled`: 409 `trip_finished`; any other status: 409 `illegal_transition` with `details.current_status`.
**Success:** 200, Trip (driver view).
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `illegal_transition` | the trip is `requested`, `started`, and so on, not `assigned` | trigger `trip_enforce_transition`, SQLSTATE `RH008` (message "illegal transition % -> % by %", E05) when the API did not guard the status |
| 409 | `trip_finished` | the trip is completed or cancelled | trigger SQLSTATE `RH005` (message "trip is % (terminal): only updated_at may change (B4)", E06) |
| 404 | `not_found` | unknown trip or not this driver's | none: the ownership condition |

Also common. **Idempotency:** state-based replay. **Session settings:** `driver`, `sub`.

### EP11 POST /v1/trips/{trip_id}/start  (driver app; A3, B5)
As EP10 with `status = 'arrived'` as the required status and target `started`. The trigger writes `started_at`. Replay: status already `started` returns 200. Errors, replay and session settings as EP10 (`illegal_transition` when the trip is `assigned`: a start cannot skip `arrived`, forbidden move F5; E05 shows the message for the same rule).

### EP12 POST /v1/trips/{trip_id}/complete  (driver app; A3, B3, B4)
**Who and ownership:** role `driver`; `trip.driver_id = sub`.
**Request:** body `distance_m` (integer, required, 0 to 1,000,000). **The client never sends the fare.** The API sets `fare_amount_minor` to the quote's `amount_minor` (a fixed upfront price, D1 (approved)) and `fare_currency` to `NGN`.
**Move:** `UPDATE trip t SET status = 'completed', fare_amount_minor = q.amount_minor, fare_currency = 'NGN', distance_m = $d FROM fare_quote q WHERE t.id = $1 AND q.id = t.fare_quote_id AND t.driver_id = $sub AND t.status = 'started' RETURNING ...` (CONFIRMED in the walkthrough: fare 135000 NGN, distance 6820, `completed_at` set by the trigger).
**Success:** 200, Trip (driver view) with `fare_amount_minor`, `fare_currency`, `distance_m`, `completed_at`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `illegal_transition` | the trip is not `started` | trigger SQLSTATE `RH008` (E05) |
| 409 | `trip_finished` | already completed or cancelled | trigger SQLSTATE `RH005` (E06) |
| 422 | `validation_failed` | `distance_m` missing, not an integer or out of range | backstop checks `trip_amounts_not_negative`, `trip_completed_has_facts` (E42: completing without the facts is refused) |
| 404 | `not_found` | unknown trip or not this driver's | none |

Also common. **Idempotency:** state-based replay (status already `completed` by the owner: 200, the stored fare is returned, `distance_m` of the repeat is ignored). **Session settings:** `driver`, `sub`.

### EP13 POST /v1/trips/{trip_id}/locations  (driver app; A3, B8)
**Who and ownership:** role `driver`; `trip.driver_id = sub`.
**Request:** body `latitude`, `longitude` (numbers, required), `accuracy_m` (integer, optional, 0 to 100000), `recorded_at` (timestamp, required; not more than 5 minutes in the future, not older than 24 hours). Rate: 1 per second per trip.
**Success:** 201, `{"id": uuid, "recorded_at": timestamp}`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `trip_not_in_progress` | the trip is not assigned, arrived or started | trigger `ping_enforce_trip_status`, SQLSTATE `RH030` (message "a location ping needs a trip that is assigned, arrived or started (status is %)", E10) |
| 422 | `validation_failed` | a coordinate is out of range or has more than 6 decimals, a field is missing | backstops `ping_latitude_range`, `ping_longitude_range`, `ping_accuracy_not_negative` (E11) |
| 404 | `not_found` | unknown trip or not this driver's | none |

Also common (429 `rate_limited` is the usual one). **Idempotency:** not idempotent; a duplicate ping is harmless (decision 11). **Session settings:** `driver`, `sub`.

### EP14 POST /v1/trips/{trip_id}/cancel  (all three apps; B9, B1, B2, B5, Q2, U3)
**Who and ownership:** rider (`trip.rider_id = sub`), driver (`trip.driver_id = sub`), support (any trip). A driver cannot cancel a `requested` trip: `driver_id` is NULL, so ownership fails and the answer is 404.
**Request:** path only. No body: there is no column for a reason, and unknown fields are rejected.
**Move:** `UPDATE trip SET status = 'cancelled' WHERE id = $1 AND [rider_id = $sub | driver_id = $sub] AND status IN ('requested','assigned','arrived','started') RETURNING ...`. The trigger writes `cancelled_at`, `cancelled_by_role` (the caller role) and the fee: **50000 kobo (the setting `cancellation_fee_minor`) only when a rider cancels from `assigned` or `arrived`, otherwise 0** (CONFIRMED E43, and the walkthrough: rider fee 50000, support from started 0). The rule that only support may cancel a `started` trip is the trigger's: a rider or driver gets `illegal_transition`. **Open question Q6:** a rider is still charged if the driver never arrives.
**Success:** 200, Trip (caller's view) with `status = cancelled`, `cancelled_by_role`, `cancellation_fee_minor`, `cancellation_fee_currency`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `illegal_transition` | a rider or driver cancels a `started` trip (only support may) | trigger SQLSTATE `RH008` ("illegal transition started -> cancelled by rider", E05b) |
| 409 | `trip_finished` | the trip is already completed, or cancelled by someone else | trigger SQLSTATE `RH005` (message "trip is % (terminal): only updated_at may change (B4)", E06) |
| 404 | `not_found` | unknown trip or not the caller's | none |

Also common. **Idempotency:** state-based replay: status `cancelled` and `cancelled_by_role` equal to the caller role returns 200 with the same fee (CONFIRMED in the walkthrough: the repeat updates zero rows, the classification says "cancelled by the caller role"). **Session settings:** the caller's role and `sub` (for support `app.actor_id` is the admin id; the trigger refuses a support actor without one).

### EP15 POST /v1/trips/{trip_id}/payments  (rider app; A4, B3, B6, U1)
**Who and ownership:** role `rider`; `trip.rider_id = sub`.
**Request:** headers `Authorization`, `Content-Type`, **`Idempotency-Key` (required)**. Body: `payment_method_token` (string, 1 to 200 characters, an opaque token from the provider's own client library; the API never receives or stores card data). **The client sends no amount and no purpose.** The API reads the trip: status `completed` gives `purpose = fare` and `amount_minor = fare_amount_minor`; status `cancelled` with `cancellation_fee_minor > 0` gives `purpose = cancellation_fee` and that fee. Currency is `NGN`.
**Flow (three transactions, because a provider call must not hold a database lock):**
1. Transaction 1: set the actor; `INSERT INTO idempotency_key ... ON CONFLICT DO NOTHING` (action `pay_trip`, `request_hash` includes the `trip_id`); commit. Replay rules of 1.7a apply here.
2. Call the provider to start the charge, passing our `Idempotency-Key` as the provider's own idempotency key (assumption, decision 5). The provider returns a `provider_reference`. Provider unreachable or refusing: delete the key row, 502 `provider_error`, **no payment row exists**.
3. Transaction 2: set the actor; `INSERT INTO payment (id, trip_id, purpose, amount_minor, currency, provider_reference)` (status `pending`); `UPDATE idempotency_key SET response_status = 202, response_body = ..., payment_id = ...`; commit.
If the process dies after step 2, a retry after 120 seconds repeats step 2 (the provider returns the same reference for the same key) and finishes step 3. If the client never retries, the provider's later webhook finds no payment with that reference and is stored as `needs_support` (EP19). This is a known gap.
**Provider capabilities used here (D5, DESIGN ASSUMPTION, owner may replace; full list in section 1.11).** Step 2 needs capability C1: create a payment with our idempotency key and get back a provider reference, with the same key giving the same reference and no second charge. Step 3 needs the reference to be unique (`payment_provider_reference_key`). The recovery after a crash (the retry after 120 seconds) needs C1 to behave that way. If a provider lacks C1, the retry is unsafe and the design must change: a payment attempt has to be recorded before the provider is called, which needs a migration, because `payment.provider_reference` is required today. Testing this endpoint needs C5, a sandbox.
**Success:** 202, header `Location: /v1/payments/{id}`, body `{"payment": Payment}` with `status = pending`. The result arrives later by the provider webhook (EP19); the rider polls EP16 or EP03 (`payments`).
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `trip_not_payable` | the trip is not completed (and not cancelled with a fee) | trigger `payment_enforce_rules`, SQLSTATE `RH022` (message "a fare payment needs a completed trip (status is %)", E13) |
| 409 | `nothing_to_pay` | the trip is cancelled with no fee | trigger SQLSTATE `RH024` (message "a cancellation fee payment needs a cancelled trip with a fee above 0", E14) |
| 409 | `payment_already_exists` | a pending or succeeded payment already exists for this trip and purpose (made with another key) | unique index `payment_one_live_per_purpose` (E12) |
| 502 | `provider_error` | the provider refused or did not answer; or it returned a reference already used by another payment | none for the first two; the second is unique `payment_provider_reference_key` |
| 400 | `invalid_idempotency_key` | key missing or malformed | backstop `idem_key_length` (E32) |
| 422 | `idempotency_key_reuse` | same key, different body or different `trip_id` | none |
| 409 | `request_in_progress` | the same key is still running | key row without a stored response, or 55P03 (concurrency test) |
| 422 | `validation_failed` | `payment_method_token` missing or too long, unknown field | none |

A wrong amount reaching the database (SQLSTATE `RH023`, "payment amount % does not equal the trip fare %", E15) is `internal_error`, because the API computes the amount. Also common.
**Idempotency:** keyed (1.7a), action `pay_trip`. A retry creates no second charge: the key row, the provider's idempotency key, and `payment_one_live_per_purpose` each refuse it.
**Session settings:** `rider`, `sub`.

### EP16 GET /v1/payments/{payment_id}  (rider app, support console; A4, U3)
**Who and ownership:** rider: the payment's `trip_id` must belong to a trip with `trip.rider_id = sub` (one join in the `WHERE`); support: any; a driver never. Not the owner: 404.
**Success:** 200, Payment (rider view) or Payment with the support additions. The rider view hides `provider_reference`.
**Errors:** `not_found`. Common. **Database cause:** none. **Idempotency:** natural. **Session settings:** the caller's.

### EP17 POST /v1/trips/{trip_id}/ratings  (rider app, driver app; A5, B7, Q3)
**Who and ownership:** rider (`trip.rider_id = sub`, so `rater_role = rider`) or driver (`trip.driver_id = sub`, so `rater_role = driver`). **The role comes from the token, never the body.**
**Request:** body `stars` (integer 1 to 5, required), `comment` (string, optional, at most 500 characters).
**Success:** 201, Rating. The trigger updates the other person's rating totals in the same transaction (CONFIRMED in the walkthrough).
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `trip_not_completed` | the trip is not completed | trigger `rating_enforce_rules`, SQLSTATE `RH041` (message "a rating needs a completed trip (status is %) (B7)", E23) |
| 409 | `rating_window_closed` | more than `rating_window_days` (7) have passed since `completed_at` | trigger SQLSTATE `RH043` ("the rating window of % days has passed (B7)", E24) |
| 409 | `already_rated` | this side already rated this trip | unique `rating_one_per_role_per_trip` (E22) |
| 422 | `validation_failed` | `stars` out of range, `comment` too long, unknown field | backstops `rating_stars_range`, `rating_comment_length` (E25) |
| 404 | `not_found` | unknown trip or not a participant | none |

Also common. **Idempotency:** not keyed. A retry after a timeout gets 409 `already_rated`; the client reads EP18 and treats it as success. **Session settings:** `rider` or `driver`, `sub` (the trigger compares the claimed actor with the trip's own rider or driver).

### EP18 GET /v1/trips/{trip_id}/ratings  (all three apps; A5, B7)
**Who and ownership:** as EP03. **Success:** 200, `{"items": [Rating, ...]}` with at most 2 items (one per side), no cursor. **Visibility (decision 12):** both stars are visible to both participants; a `comment` is visible only to its author and to support (the rated person does not see it). **Errors:** `not_found`. Common. **Database cause:** none. **Idempotency:** natural. **Session settings:** the caller's.

### EP19 POST /v1/provider/webhooks  (provider only; A4, B5, B6, U4)
**Who and ownership:** the payment provider. No token and no ownership. **Authentication (assumption, decision 5):** header `X-Provider-Signature` = HMAC-SHA256 (hex) of `X-Provider-Timestamp + "." + raw body` with a shared secret read from the environment; a timestamp more than 5 minutes old is refused (replay window). The adapter maps the provider's payload to the canonical body below; the names are those of `provider_event`.
**Provider capabilities used here (D5, DESIGN ASSUMPTION, owner may replace; full list in section 1.11).** This endpoint needs capability C3: a signed webhook with a unique event id. Without a signature the check is replaced by a shared secret in the address plus a list of allowed source addresses, which is weaker. Without a unique event id the API builds one by hashing the reference, the event type, the status and the provider's time. Without webhooks the endpoint is not used and JB2 becomes the main source of results (it then needs C2). **The scheme below is a placeholder.** What the database side needs from any provider message is only this: `provider_event_id` (required, unique), `provider_reference` (required), `event_type` (required), `amount_minor` and `currency` (optional, together), and `occurred_at` (optional). The database fills `received_at`, `processed_at` and `outcome`. The field `failure_reason` is not stored in `provider_event`; it is copied to the payment on a failure.
**Request:** headers `X-Provider-Signature`, `X-Provider-Timestamp`, `Content-Type`. Body:

| Field | Type | Required | Limits |
|---|---|---|---|
| `provider_event_id` | string | yes | 1 to 200 characters; the provider's own id, the repeat detector |
| `provider_reference` | string | yes | 1 to 200 characters; the payment's or the refund's reference |
| `event_type` | string | yes | `payment_succeeded`, `payment_failed` or `refund_succeeded` (`payment_not_found` is made by the reconciliation job, never sent by the provider) |
| `amount_minor` | integer | optional | above 0; with `currency` |
| `currency` | string | with `amount_minor` | `NGN` |
| `occurred_at` | timestamp | optional | the provider's own time |
| `failure_reason` | string | optional | at most 500; used when `event_type = payment_failed` (default text "provider declined, no reason given", because a failed payment needs a reason) |

**Handling (one transaction, docs 03 section 4a):**
1. Set `app.actor_role = provider`, `app.actor_id = ''`.
2. `INSERT INTO provider_event (...) ON CONFLICT (provider_event_id) DO NOTHING RETURNING id`. **No row returned = the provider repeated an event we already stored: answer 200 `{"received": true, "outcome": "duplicate_event"}` and stop** (CONFIRMED E33a and E33b: the plain insert raises the unique error, `ON CONFLICT DO NOTHING` returns no row and the table keeps one row).
3. A new event: find the payment by `provider_reference` (index `payment_provider_reference_key`), or the refund by reference.
4. `payment_succeeded` and the payment is `pending`: `UPDATE payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = $1 AND status = 'pending'` (amount must equal the payment's, otherwise outcome `needs_support`); `payment_failed` and pending: `UPDATE ... SET status = 'failed', failure_reason = $2`. Outcome `applied`. (CONFIRMED E33e.)
5. The payment already has that result, or the refund already exists: outcome `ignored_duplicate`.
6. Anything that conflicts (the payment is terminal with another result, the reference is unknown, a `refund_succeeded` with no refund row, an amount mismatch): payment not changed, outcome `needs_support` (the trigger `provider_event_write_audit` writes the audit row).
7. `UPDATE provider_event SET processed_at = now(), outcome = $1`.
**Success:** always 200 for a valid, signed event: `{"received": true, "outcome": "applied" or "ignored_duplicate" or "needs_support" or "duplicate_event"}`. The provider must never be told to retry a message we have already stored.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 401 | `invalid_signature` | signature missing or wrong, or timestamp too old | none |
| 400 | `invalid_event` | a required field missing, `event_type` not one of the three, amount without currency, amount not above 0 | backstops `provider_event_type_valid` (E33c), `provider_event_money_pair` (E33d), `provider_event_amount_positive`, `provider_event_currency_ngn` |
| 413 | `payload_too_large` | body over 16 KiB | none |
| 503 | `service_unavailable` | the database is down, so the provider retries later (safe: the event id makes a retry harmless) | connection errors |

500 is never returned: an unexpected error is 503 so that the provider retries. **Idempotency:** keyed by the provider's own id: unique `provider_event_provider_event_id_key`. **Session settings:** `provider`, empty id.

### EP20 POST /v1/support/payments/{payment_id}/fail  (support console; A4, B6, U3, U4)
**Who and ownership:** role `support`; no ownership (support acts on any payment). **This is move P3**, the way out of a stuck pending payment.
**Request:** body `failure_reason` (string, 1 to 500, required).
**Move:** `UPDATE payment SET status = 'failed', failure_reason = $1 WHERE id = $2 AND status = 'pending' RETURNING ...`. The trigger requires a `payment_not_found` provider event for the same `provider_reference`, received after the payment was created and not superseded by a later event of any type.
**Success:** 200, Payment (support view). **Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `payment_proof_missing` | no valid `payment_not_found` event (none, wrong reference, older than the payment, or superseded by a later event) | trigger `payment_enforce_rules`, SQLSTATE `RH028` (message "support may fail a pending payment only after a payment_not_found event ... (P3)", E17) |
| 409 | `payment_final` | the payment is already succeeded or failed (failed by this caller: replay below) | trigger SQLSTATE `RH026` ("payment is % (terminal): only updated_at may change", E16) |
| 404 | `not_found` | unknown payment | none |
| 422 | `validation_failed` | `failure_reason` missing or too long | backstop check `payment_failed_has_reason` |

Also common. **Idempotency:** state-based: a payment already `failed` returns 200 with the stored payment. (The move "support marks a payment succeeded" does not exist: SQLSTATE `RH027` "illegal payment transition pending -> succeeded by support", E18, internal.) **Session settings:** `support`, `sub` (the admin id; the trigger refuses P3 without it).

### EP21 POST /v1/support/payments/{payment_id}/refunds  (support console; B10, B3, B4, U3, Q4)
**Who and ownership:** role `support`.
**Request:** headers `Authorization`, `Content-Type`, `Idempotency-Key` (required, forwarded to the provider; not stored in the `idempotency_key` table, whose `rider_id` is required). Body: `amount_minor` (integer above 0, required), `currency` (`NGN`, required), `reason` (string 1 to 500, required).
**Flow:** read the payment (must be `succeeded`); pre-check the total; call the provider's refund with our key; the provider returns `provider_reference`; **only then** `INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)` with `created_by_admin_id = sub`. The trigger `refund_enforce_total` locks the payment row, so two refunds at the same moment wait for each other.
**Provider capabilities used here (D5, DESIGN ASSUMPTION, owner may replace; full list in section 1.11).** This endpoint needs capability C4: refund by reference with our idempotency key, returning a refund reference that is unique for this refund (`refund_provider_reference_key`). If a provider lacks C4, refunds are made by hand at the provider; this endpoint then takes the provider's refund reference from the support person in the request body and writes the refund row from it, the unique constraint still stops the same refund being written twice, and there is no automatic confirmation. The webhook event `refund_succeeded` needs C3; without it a refund is trusted when the provider call returns. Testing this endpoint needs C5, a sandbox.
**Success:** 201, Refund. A repeat with the same key and body returns 200 with the existing refund and `Idempotent-Replay: true`.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `payment_not_succeeded` | the payment is pending or failed (the refund table only covers succeeded payments) | trigger `refund_enforce_total`, SQLSTATE `RH050` (message "a refund needs a succeeded payment (status is %)", E20) |
| 409 | `refund_exceeds_payment` | the sum of refunds would exceed `payment.amount_minor` (B10) | trigger SQLSTATE `RH052` ("refunds % + % would exceed the payment amount % (B10)", E19) |
| 409 | `refund_reference_conflict` | the provider's reference already belongs to a different refund | unique `refund_provider_reference_key` (E21), when the existing refund has another payment or amount; the same payment and amount is the replay (200) |
| 502 | `provider_error` | the provider refused or did not answer (no refund row is written) | none |
| 404 | `not_found` | unknown payment | none |
| 422 | `validation_failed` | amount not an integer above 0, currency not NGN, reason blank | backstops `refund_amount_positive`, `refund_currency_ngn`, `refund_reason_not_blank` |
| 400 | `invalid_idempotency_key` | header missing or malformed | none (API) |

Also common. **Idempotency:** the provider's idempotency key plus unique `refund_provider_reference_key` (limit: not the table, decision 6). A manual refund made at the provider with no API call has no refund row: known gap (docs 05, item 1). **Session settings:** `support`, `sub`.

### EP22 GET /v1/support/settings  (support console; B9, U3)
**Who:** role `support`. **Success:** 200, `{"items": [Setting, ...]}` ordered by `key`. About 20 rows at most, so no cursor. **Errors:** common only (403 for any role but support). **Database cause:** none. **Idempotency:** natural. **Session settings:** `support`, `sub`.

### EP23 PUT /v1/support/settings/{key}  (support console; B3, B7, B9, U3, Q1, Q2, Q3)
**Who:** role `support`. **Allowed keys** (an allow-list in the API): `cancellation_fee_minor`, `rating_window_days`, `request_timeout_seconds`, `quote_validity_seconds`, `base_fare_minor`, `per_km_minor`, `per_minute_minor`, `payment_reconcile_after_seconds`, `request_timeout_check_interval_seconds`, `payment_reconcile_check_interval_seconds`, `service_area_min_lat_e6`, `service_area_max_lat_e6`, `service_area_min_lon_e6`, `service_area_max_lon_e6`. Any other key: 422 `unknown_setting`.
**Request:** body `int_value` (integer, 0 or more, required), `currency` (`NGN` for keys ending `_minor`, absent for all others), `description` (string 1 to 300, required when the key does not exist yet).
**Statement:** `INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES (...) ON CONFLICT (key) DO UPDATE SET int_value = EXCLUDED.int_value, updated_by_admin_id = EXCLUDED.updated_by_admin_id RETURNING ...` (CONFIRMED E28d: a new key and an existing key, each with its `audit_log` row `setting_change` showing from and to). `updated_by_admin_id = sub`.
**Success:** 200 (or 201 when the key was created), Setting.
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 422 | `unknown_setting` | key not in the allow-list | none |
| 422 | `validation_failed` | value negative or not an integer, currency missing for a `_minor` key or present for another, currency not NGN, description missing for a new key | backstops `setting_value_not_negative` (E28a), `setting_money_has_currency` (E28b), `setting_currency_ngn` (E28c) |

A setting change claimed by a non-support actor (SQLSTATE `RH060`, "only a support actor may change a setting", E29) is `internal_error`. Also common. **Idempotency:** the same value twice is harmless (the audit trail shows two changes). **Session settings:** `support`, `sub`.

### EP24 POST /v1/support/notes  (support console; B5, U3)
**Who:** role `support`. **Request:** body `entity_type` (one of `trip`, `payment`, `refund`, `rating`, `rider`, `driver`, `setting`, `provider_event`), `entity_id` (uuid; required for every type except `setting`, where it must be absent), `note` (string, 1 to 2000, no card data or secrets: application validation only). **Statement:** `SELECT add_support_note($entity_type, $entity_id, $note)`.
**Success:** 201, `{"id": uuid}`. **Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 422 | `validation_failed` | `note` blank, `entity_type` not allowed, `entity_id` missing (or present for `setting`) | function `add_support_note`, SQLSTATE `RH062` (message "a support note cannot be empty", E30a); backstops `audit_entity_type_valid` (E30b), `audit_entity_id_matches_type` (E30c) |

A claimed non-support actor (SQLSTATE `RH061`, "only a support actor may write a support note", E30d) is `internal_error`. Also common. **Idempotency:** not idempotent; a duplicate note is harmless. **Session settings:** `support`, `sub`.

### EP25 POST /v1/support/riders/{rider_id}/erasure  and EP26 POST /v1/support/drivers/{driver_id}/erasure  (support console; B8, U3)
**Who:** role `support`. **Request:** body `confirm` (boolean, must be `true`; the action cannot be undone). **Statement:** `SELECT erase_rider($rider_id)` (EP25) or `SELECT erase_driver($driver_id)` (EP26), then, in the same transaction, `SELECT add_support_note('rider' or 'driver', $id, 'erasure performed')` so there is an audit trail with no personal data (the function itself writes none).
**Optional denylist (D13 design assumption, section 1.10 item 7):** if the owner deploys the denylist, the API also writes a subject cutoff entry for the erased person after the erasure, so tokens that were already issued stop working at once. This applies to EP25 and to EP26. Without the denylist (the baseline) the person status check cuts the erased person off at the API within about a minute.
**Success:** 200, `{"id": uuid, "erased": true}` (CONFIRMED in Stage 3 proofs X6a, X6e: names become `Deleted rider` or `Deleted driver`, addresses and plates become `erased`, money and times unchanged).
**Errors:**

| Status | Code | When | Database cause |
|---|---|---|---|
| 409 | `person_has_active_trip` | the person has an active trip | functions `erase_rider` and `erase_driver`, SQLSTATE `RH071` (messages "rider % has an active trip: cannot erase (B8)", E26, and "driver % ..." E26b) |
| 404 | `not_found` | the id is not a rider or driver | SQLSTATE `RH070` ("rider % does not exist", E27; the driver version is the same code) |
| 422 | `validation_failed` | `confirm` missing or not `true` | none |

Also common. **Idempotency:** natural: running it again sets the same values (`COALESCE(deleted_at, now())` keeps the first erasure time). **Session settings:** `support`, `sub`.

### EP27 GET /v1/trips/{trip_id}/events  (rider app, support console; A3, B8, U1, U3)
Server-Sent Events stream of one trip's status changes and the driver's latest position, so the rider app does not poll (design and reasons: `08_real_time.md`). EP03 and EP05 remain as the polling fallback.
**Who and ownership:** rider (`trip.rider_id = sub`) and support (any trip). A driver gets 403 `forbidden_role` (the driver app reads its own trip with EP03). Not the owner: 404 `not_found`, the same body as an unknown id. The check is the first statement: `SELECT id, status FROM trip WHERE id = $1 AND rider_id = $2` (support: no `rider_id` condition). It is repeated on every reconnect. `trip.rider_id` never changes (`02_entities.md`), so one check at connect holds for the life of the stream.
**Request:** headers `Authorization: Bearer <token>`, `Accept: text/event-stream`, optional `Last-Event-ID` (a whole number of 0 or more: the `seq` of the last status event the client saw). Optional query `last_seq` with the same meaning for clients that cannot set the header; if both are sent the header wins. No body. Any other query parameter is a 400 `invalid_filter`.
**Success:** `200`, `Content-Type: text/event-stream`, `Cache-Control: no-store`, `X-Accel-Buffering: no`. The first line is `retry: 3000`. Events (data is one line of JSON):

| Event | `id:` | `data` fields (type) | When |
|---|---|---|---|
| `status` | the `seq` of the history row | `seq` (integer), `from_status` (string or null), `to_status` (string, one of requested, assigned, arrived, started, completed, cancelled), `created_at` (timestamp) | every status change after `Last-Event-ID` (all of them when it is absent), in `seq` order. Support also gets `actor_role`, `actor_rider_id`, `actor_driver_id`, `actor_admin_id` |
| `location` | none | `latitude` (number), `longitude` (number), `accuracy_m` (integer or null), `recorded_at` (timestamp) | at most one every 2 seconds, only when a newer ping exists, only while the trip is assigned, arrived or started |
| `end` | none | `reason` (string: `completed`, `cancelled`, `token_expired`, `max_duration`) | last event, then the server closes the response |
| `error` | none | `code` (a code of `06b`), `request_id` (string) | the database fails after the 200 was sent, then the server closes |
| comment `: keepalive` | none | none | after every 20 seconds of silence |

The client must stop (not reconnect) when it receives `end` with `reason` `completed` or `cancelled`; it reconnects with `Last-Event-ID` after `token_expired` (with a fresh token), `max_duration`, an `error` event or a lost connection. A reconnect after the trip finished gets the missed events, then `end`, then the close.
**Stream rules:** the stream ends at the token's expiry and after 15 minutes at most; at most 2 open streams per rider per trip; a connection whose write buffer stays full is closed (the client resumes by `seq`).
**Reads behind it (CONFIRMED plans, `evidence/part_b_realtime_plans.txt`):** status events `WHERE trip_id = ANY($open_trips) ... ORDER BY trip_id, seq` or, on connect, `WHERE trip_id = $1 AND seq > $2 ORDER BY seq`, index `trip_status_history_trip_seq_idx` (0.046 ms for one trip, 0.33 ms for 50 trips); latest ping by a lateral read of `location_ping_trip_recorded_idx` (0.09 ms for one trip, 0.28 ms for 50). The `seq` order per trip equals commit order because a second move of the same trip waits for the first (CONFIRMED lock wait; ordering INFERRED). Reads never poll globally by `seq`.
**Errors (before the stream starts):**

| Status | Code | When | Database cause |
|---|---|---|---|
| 400 | `invalid_cursor` | `Last-Event-ID` or `last_seq` is not a whole number of 0 or more | none (API) |
| 400 | `invalid_filter` | an unknown query parameter | none (API) |
| 403 | `forbidden_role` | the caller is a driver | none |
| 404 | `not_found` | unknown trip id, or not the rider's trip | none: the ownership query returns no row |
| 429 | `rate_limited` | more than 2 open streams for this rider and trip | none |
| 503 | `service_unavailable` | the database is not reachable at connect | connection errors |

Also 401 `unauthenticated`, 500 `internal_error`. After the 200 is sent an error cannot change the status; it is an `error` event (above). **Idempotency:** safe (a GET that only reads); a repeat or a resume gives the same events by `seq`. **Session settings:** `app.actor_role` and `app.actor_id` from the token (`rider` or `support`, and `sub`), set at the start of every database transaction of the stream, never from the request.

## 5. Internal jobs (not public; run as `ridehail_app`, never the dev superuser)

### JB1 Request timeout job  (B9, B1, T9)
**Who runs it:** the application's scheduler, any single worker, every `request_timeout_check_interval_seconds` (setting; placeholder 60 seconds, applied by the sample seed, needs the owner). **Does:** cancels trips still `requested` after `request_timeout_seconds` (600, placeholder, needs owner approval). If the setting has no row the job refuses to run and alerts.
**Statement (one batch of up to 200):** `WITH due AS (SELECT id FROM trip WHERE status = 'requested' AND created_at < now() - make_interval(secs => $timeout) ORDER BY created_at LIMIT 200 FOR UPDATE SKIP LOCKED) UPDATE trip t SET status = 'cancelled' FROM due WHERE t.id = due.id AND t.status = 'requested' RETURNING ...` (uses `trip_requested_created_at_idx`). **CONFIRMED** in the walkthrough: 3 trips cancelled with `cancelled_by_role = system`, fee 0, 3 history rows by actor `system`. The `status = 'requested'` condition in the update protects against a driver accepting at the same moment.
**Session settings:** `app.actor_role = system`, `app.actor_id = ''`. **If it is down:** unaccepted requests are not cancelled and the rider stays blocked by B1 until they cancel. **Safe to run twice:** yes.

### JB2 Payment reconciliation job  (A4, B6, U4)
Every `payment_reconcile_check_interval_seconds` (setting; placeholder 300 seconds, applied by the sample seed, needs the owner). Selects payments `pending` for more than `payment_reconcile_after_seconds` (900, placeholder): `SELECT id, provider_reference FROM payment WHERE status = 'pending' AND created_at < now() - make_interval(secs => $s) ORDER BY created_at LIMIT 100` (index `payment_pending_created_at_idx`, CONFIRMED in the walkthrough). For each, asks the provider and acts as in docs 03 section 4b: succeeded and failed are applied as in EP19 steps 2 to 7 (actor `provider`); "no record" inserts a `payment_not_found` event with outcome `needs_support` and leaves the payment pending for support (EP20); no answer: nothing. **Session settings:** `provider` for results from the provider, `system` for its own bookkeeping. **If it is down:** payments stay pending. Safe to run twice (the event ids make repeats harmless; the job builds its own event id for a "no record" answer).

### JB3 Idempotency cleanup job  (B6)
Hourly: `DELETE FROM idempotency_key WHERE expires_at < now()` (CONFIRMED in the walkthrough: an expired row inserted in the transaction was deleted, so `ridehail_app` holds the DELETE right). The table is small and short-lived, so no index on `expires_at`. **Session settings:** not needed (no trigger depends on them), the job still sets `system`.

## 6. What this contract does not cover
Sign up, login and password reset, and the identity service itself (section 1.10 lists what is out of scope); the real routing method (an interface, a failure rule and a placeholder are written in EP01); the real provider's field names and signature scheme (the capabilities needed are written in section 1.11); support lists and search (stuck payments, events that need support); push notifications to a phone in the background (EP27 streams only while the app is in the foreground); real-time delivery to the driver app (the driver app polls EP08 and EP03; `08_real_time.md` explains why a stream was designed only for the rider watch); the over-fetching analysis is in `07_over_fetching.md`.

## 7. Unconfirmed assumptions
Each item below is a placeholder or an owner decision that the contract uses but that nobody has confirmed. The label is INFERRED unless stated.
1. **Webhook signature and field names (EP19).** The provider is unnamed. The header names, the HMAC-SHA256 scheme over timestamp and body, the five-minute replay window and the canonical body fields (`provider_event_id`, `provider_reference`, `event_type`, `amount_minor`, `currency`, `occurred_at`, `failure_reason`) are placeholders. The real provider's documentation replaces them; the database side (`provider_event` and its checks) does not change.
2. **Fixed upfront fare (EP12, D1).** The fare equals the quote and the driver cannot change it. This is an owner decision, approved (`docs/09_open_items.md` section 6). Metered pricing would need a different completion rule and a fare change after the ride.
3. **Rate limits (section 1.8, D6).** Quotes 10 per minute, pings 1 per second per trip, other writes 30 per minute, reads 120 per minute are placeholders chosen without traffic figures.
4. **Support sees all trips (decision 1 and section 1.3).** Any support admin can read and cancel any trip and payment. This is a known limit: the database checks the claimed role, not a region or a case. Role-scoped access (by region, case or admin level) is added later and would need a new rule in the API and, for the database, a new check; it is not designed here.
5. **Distance estimator (EP01, D16).** A design assumption, owner may replace: the interface, the failure rule and the placeholder are written in EP01. The placeholder (flat earth distance times 1.3, 8.33 metres per second) is not a real route and must be replaced before real use. CONFIRMED in `evidence/stage5_prep2_fare_arithmetic.txt`: 9243 metres, 1110 seconds and 244145 kobo for the example trip.
6. **Setting values (D4).** The fare, quote life, service-area box and the two job intervals applied by `db/seed/seed_sample_settings.sql` are placeholders (the city is assumed to be Lagos) and need the owner.
7. **Database driver field names (section 1.6, driver note).** To confirm in the chosen driver.
8. **Event stream (EP27, D14).** Server-Sent Events as the transport, the heartbeat of 20 seconds, the location rate of one event per 2 seconds, the 15-minute maximum stream life, the limit of 2 open streams per rider per trip and the 1-second poller are designs and placeholders (`08_real_time.md`); no stream has been served over HTTP. Whether the rider app's HTTP client supports streaming with an Authorization header is to confirm in the chosen client.
9. **Authentication design (D13).** A design assumption, owner may replace, written in section 1.10: a signed bearer token with seven trusted claims, an access lifetime of 15 minutes, a status check of the person on every request (remembered for at most 60 seconds), and revocation by short life only as the baseline, with a denylist as an optional hardening that the owner may add at deployment. Nothing was run. The identity service is outside this project and not named.
10. **Payment provider capabilities (D5).** A design assumption, owner may replace, written in section 1.11 and in EP15, EP19 and EP21: five capabilities the API needs from any provider, and what changes if one is missing. The webhook scheme remains a placeholder.