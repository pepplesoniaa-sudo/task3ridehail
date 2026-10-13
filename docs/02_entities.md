# 02 Entities

Every entity cites the IDs in `01_requirements.md`. Plain-English reasons are given for each choice. Labels: CONFIRMED means I ran it (see the test list in the report); INFERRED means I reasoned it.

## Conventions used by every table

- **Identifier:** `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`. It is random, not sequential (reason and test in 04, question 5). Two exceptions, `setting` and `status_transition_rule`, are named in their sections. `provider_event` has our own uuid `id` and also carries the provider's id in `provider_event_id`.
- **Timestamps:** `created_at timestamptz NOT NULL DEFAULT now()` and `updated_at timestamptz NOT NULL DEFAULT now()` on every table (04, question 4). A shared trigger `set_updated_at` refreshes `updated_at` on every update. On append-only tables (marked below) no update is ever allowed, so `updated_at` always equals `created_at`. It is kept only so every table looks the same (decision 3 in the report).
- **Money:** `bigint` count of kobo, with a `char(3)` currency column beside it (B3). No float, no `numeric` for money.
- **Location:** latitude is `numeric(8,6)` and longitude is `numeric(9,6)`. Six decimal places is about 0.1 metre, which is more precise than a phone GPS can deliver, so nothing useful is lost. I chose `numeric` and not `double precision` so the same value always reads back exactly (a float can come back as 6.524379000000001). It is not money, so this is the one justified use of `numeric`. Latitude needs 2 digits before the point (up to 90) and longitude needs 3 (up to 180), which is why the sizes differ.
- **PostGIS:** I would use it in production for "drivers within 3 km" (a `geography(Point,4326)` column and a GiST index). CONFIRMED: it is NOT available in this container (`pg_available_extensions` returns only `pg_trgm` and `uuid-ossp` for my query on postgis, pg_trgm and uuid-ossp). I did not install anything. This design uses a rectangle on plain numbers instead (04, question 7, A2).
- **Required** means `NOT NULL`. **Optional** means `NULL` allowed.
- **Text sizes:** Postgres `text` has no speed penalty over `varchar(n)`. Limits are set with check constraints where they matter.

The entity list you gave has 14 entries. I **added two** and **dropped none**. Total: 16 entities.
- `status_transition_rule` (entity 15). Reason: the legal status changes (B5, B9) are best kept as rows in a table, so a person can read, query and review them, and one trigger function can use them for both the trip and the payment. Hard coding them inside trigger code would hide them.
- `provider_event` (entity 16, added at your request in Stage 2 fixes). Reason: the payment provider can send the same message twice or send a message that contradicts an earlier one (U4, B6). Each message gets one row with the provider's own event id, so a repeat is recognised.

---

## 1. rider
A person who requests and pays for trips. Identifier: `id`. Serves U1, A1, A4, A5, B1, B8.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| full_name | text | required | personal data (B8); replaced on erasure |
| phone | text | required | personal data (B8); E.164 format such as +2348012345678; replaced on erasure |
| email | text | optional | personal data (B8); cleared on erasure |
| rating_sum | integer | required | SPEED cache, default 0: total stars received from drivers |
| rating_count | integer | required | SPEED cache, default 0: number of ratings received |
| deleted_at | timestamptz | optional | set when the account is erased (soft delete) |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 2. driver
A person who accepts and drives trips. Identifier: `id`. Serves U2, A2, A3, A5, B2, B8.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| full_name | text | required | personal data (B8) |
| phone | text | required | personal data (B8) |
| licence_number | text | required | personal data (B8); needed to vet a driver |
| rating_sum | integer | required | SPEED cache, default 0 |
| rating_count | integer | required | SPEED cache, default 0 |
| deleted_at | timestamptz | optional | soft delete |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 3. vehicle
A car that belongs to one driver. Identifier: `id`. Serves U2, A2, B2, B8.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| driver_id | uuid | required | foreign key to driver |
| plate_number | text | required | the number plate; unique while not deleted |
| make | text | required | |
| model | text | required | |
| colour | text | optional | |
| seat_count | smallint | required | 1 to 8 |
| is_active | boolean | required | default true; false means the driver no longer uses it |
| deleted_at | timestamptz | optional | soft delete |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 4. trip
One ride from request to a final state. It is also the join between a rider and a driver (many riders can ride with many drivers over time). Identifier: `id`. Serves A1, A2, A3, A4, B0, B1, B2, B3, B4, B5, B9.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| rider_id | uuid | required | foreign key to rider; never changes |
| driver_id | uuid | optional | foreign key to driver; empty until assigned (B2); never changes once set |
| vehicle_id | uuid | optional | foreign key to vehicle; empty until assigned; must belong to the same driver |
| fare_quote_id | uuid | required | foreign key to fare_quote; one quote makes at most one trip |
| status | text | required | requested, assigned, arrived, started, completed, cancelled (default requested) |
| pickup_address | text | required | the address text the rider confirmed; the only copy |
| dropoff_address | text | required | same |
| driver_name_snapshot | text | optional | HISTORY snapshot of driver.full_name at assignment |
| vehicle_plate_snapshot | text | optional | HISTORY snapshot of vehicle.plate_number at assignment |
| started_at | timestamptz | optional | set when status becomes started |
| completed_at | timestamptz | optional | set when status becomes completed |
| cancelled_at | timestamptz | optional | set when status becomes cancelled |
| cancelled_by_role | text | optional | rider, driver, support or system (the timeout in B9); set when cancelled |
| cancellation_fee_minor | bigint | optional | kobo; set when cancelled (0 means no fee); copied from the setting at that moment |
| cancellation_fee_currency | char(3) | optional | NGN; set with the fee |
| fare_amount_minor | bigint | optional | final fare in kobo; set when completed |
| fare_currency | char(3) | optional | NGN; set with the fare |
| distance_m | integer | optional | driven distance in metres; set when completed |
| created_at | timestamptz | required | this is the moment of request |
| updated_at | timestamptz | required | the only field that may change after completion (B4) |

## 5. trip_status_history
One row for every status change of a trip, written by the database itself (B5). Append-only. Identifier: `id`. Serves B5, A1, A2, A3.

**Who writes it (built in migration 010):** only the trigger function `trip_write_history`, which is `SECURITY DEFINER` and owned by the role `ridehail_writer`. The application role `ridehail_app` can read the table (SELECT) but has no INSERT, UPDATE or DELETE, so it cannot add a false row. The function still records the **claimed** actor (`app.actor_role`, `app.actor_id`): custom session settings are the same inside a SECURITY DEFINER function. Remaining limits: a superuser can still bypass all of this, and the actor name is stated by the application.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| trip_id | uuid | required | foreign key to trip |
| from_status | text | optional | empty on the first row (creation) |
| to_status | text | required | |
| actor_role | text | required | rider, driver, support or system |
| actor_rider_id | uuid | optional | foreign key to rider; set when actor_role is rider |
| actor_driver_id | uuid | optional | foreign key to driver; set when actor_role is driver |
| actor_admin_id | uuid | optional | foreign key to support_admin; set when actor_role is support |
| created_at | timestamptz | required | the time of the change |
| updated_at | timestamptz | required | equals created_at (append-only) |
| seq | bigint | required | `GENERATED ALWAYS AS IDENTITY` (migration 010). The database numbers each new row in insert order, and nobody can supply a value. Timelines are ordered by `seq`, not by `created_at`: every move made inside one transaction has the same `created_at` |

Three actor columns, not one untyped id, so the database can check the actor really exists.

**The `seq` of the 932,072 rows that existed before migration 010** was assigned by PostgreSQL while it rewrote the table, in the order it read the heap (physical order). That is not `created_at` order, and no tie-break was applied. Checked afterwards (CONFIRMED, `evidence/proofs_migration_010.txt`): the 12 small-set trips are all correct, but 62 bulk trips (299 rows) have one row numbered out of order, because a later row had been stored on an earlier heap page freed by vacuum. Rows written after migration 010 are numbered at insert time and are correct by construction (one trip's rows come from one session, and `nextval` rises within a session). In the bulk set the ties on `created_at` carry no information at all: every row of a trip was written in one load transaction. See the Stage 3 follow-up report for the decision on those 62 trips. **Lesson:** a column numbered by `ADD COLUMN ... GENERATED ... AS IDENTITY` on a table that already has rows takes the physical order of the rows, which is only an insert order until deletes, updates or vacuum free space on earlier pages and later rows are stored there. Add an order column BEFORE the data exists, or number existing rows from an explicit order, and always check the result afterwards with the chain query (each row starts where the previous one ended). In the 62 trips, 23 have the `started > completed` row numbered first; the other 39 have a different row out of place.

## 6. location_ping
One GPS point sent by the driver's phone while a trip is in progress. Append-only except for scheduled deletion. Identifier: `id`. Serves A3, B8.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| trip_id | uuid | required | foreign key to trip; the driver is found through the trip |
| latitude | numeric(8,6) | required | -90 to 90 |
| longitude | numeric(9,6) | required | -180 to 180 |
| accuracy_m | integer | optional | phone's stated accuracy in metres; not negative |
| recorded_at | timestamptz | required | time on the phone |
| created_at | timestamptz | required | time the server stored it |
| updated_at | timestamptz | required | equals created_at |

## 7. fare_quote
The price estimate shown to the rider before the trip exists. It is never edited. Identifier: `id`. Serves A1, B3.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| rider_id | uuid | required | foreign key to rider |
| pickup_latitude | numeric(8,6) | required | |
| pickup_longitude | numeric(9,6) | required | |
| dropoff_latitude | numeric(8,6) | required | |
| dropoff_longitude | numeric(9,6) | required | |
| estimated_distance_m | integer | required | not negative |
| estimated_duration_s | integer | required | not negative |
| amount_minor | bigint | required | estimated fare in kobo |
| currency | char(3) | required | NGN |
| expires_at | timestamptz | required | after this the quote cannot start a trip |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | equals created_at |

## 8. payment
One attempt to collect one fare or one cancellation fee through the payment provider (A4). Identifier: `id`. Serves U4, A4, B3, B5, B6.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| trip_id | uuid | required | foreign key to trip; the rider is found through the trip |
| purpose | text | required | fare or cancellation_fee |
| amount_minor | bigint | required | kobo; more than 0; must equal the trip's fare or fee |
| currency | char(3) | required | NGN |
| status | text | required | pending, succeeded, failed (default pending). The provider moves it out of pending. Support may only fail a pending payment after a `payment_not_found` provider_event exists for it (03, move P3) |
| provider_reference | text | required | the provider's own id for this payment; unique. The payment row is created only after the provider returns this reference (A4). That is what lets a stuck pending payment be matched with `provider_event` rows. Matches `provider_event.provider_reference` by value, not by foreign key |
| paid_at | timestamptz | optional | required when succeeded |
| failure_reason | text | optional | required when failed |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 9. refund
Money returned to the rider against one payment, whole or part. Never edited. Identifier: `id`. Serves B3, B4, B10, U3.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| payment_id | uuid | required | foreign key to payment |
| amount_minor | bigint | required | kobo; more than 0 |
| currency | char(3) | required | NGN |
| reason | text | required | why support refunded |
| created_by_admin_id | uuid | required | foreign key to support_admin |
| provider_reference | text | required | the provider's refund id; unique. A refund row is created only after the provider confirms it (assumption 5) |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | equals created_at |

## 10. rating
One person's rating of the other after a completed trip. Never edited. Identifier: `id`. Serves A5, B7.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| trip_id | uuid | required | foreign key to trip |
| rater_role | text | required | rider or driver. The rater and the person rated are both found through the trip, so nothing is copied |
| stars | smallint | required | 1 to 5 |
| comment | text | optional | up to 500 characters; personal data (B8) |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | equals created_at |

## 11. idempotency_key
A client-chosen key that makes a retry safe. Stores the first answer so a retry gets it back unchanged. Identifier: `id`. Serves A1, A4, B6.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| rider_id | uuid | required | foreign key to rider |
| action | text | required | request_trip or pay_trip |
| key | text | required | the client's key, 1 to 128 characters |
| request_hash | text | required | SHA-256 of the request body, 64 hex characters; a retry with the same key but a different body is refused |
| response_status | smallint | optional | HTTP status of the first answer; empty while the first request is still running |
| response_body | jsonb | optional | the first answer, returned unchanged on a retry |
| trip_id | uuid | optional | foreign key to trip, set when the action made a trip |
| payment_id | uuid | optional | foreign key to payment, set when the action made a payment |
| expires_at | timestamptz | required | the row is deleted after this (04, question 4) |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | changes once, when the response is stored |

## 12. setting
Named whole-number settings that the owner can change without a code release. Identifier: `key` (text), not a uuid. Reason: it is a short fixed name the code looks up (for example `cancellation_fee_minor`). It is never created by users and never shown in a URL, so a random id adds nothing. Serves B9, B7, A1, B3.

| Field | Type | Req | Notes |
|---|---|---|---|
| key | text | required | primary key |
| int_value | bigint | required | not negative. **Holds two kinds of value:** kobo for keys ending in `_minor`, and degrees multiplied by 1,000,000 for the four `service_area_*_e6` keys. Other keys hold plain counts (days, seconds). The key name says which |
| currency | char(3) | optional | NGN; required exactly when the key ends in `_minor` |
| description | text | required | plain English meaning |
| updated_by_admin_id | uuid | optional | foreign key to support_admin |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

Keys defined by this design: `cancellation_fee_minor` (50000, NGN, B9), `rating_window_days` (7, B7), `request_timeout_seconds` (600, B9, a placeholder that needs owner approval), `quote_validity_seconds`, `base_fare_minor`, `per_km_minor`, `per_minute_minor` (A1), and `payment_reconcile_after_seconds` (900, a placeholder that needs owner approval, 03 scheduled jobs), `request_timeout_check_interval_seconds` and `payment_reconcile_check_interval_seconds` (how often the two jobs run; placeholders of 60 and 300 seconds were applied by the sample settings seed in Stage 4 and need the owner), and four service-area edges `service_area_min_lat_e6`, `service_area_max_lat_e6`, `service_area_min_lon_e6`, `service_area_max_lon_e6` (A1). The first two have values from the requirements. `request_timeout_seconds` has your placeholder of 600 and needs owner approval. The others got **placeholder** values in Stage 4 from `db/seed/seed_sample_settings.sql` (base fare 50000, per kilometre 15000, per minute 3000, quote life 300 seconds, a rough Lagos box, job intervals 60 and 300 seconds); they are not owner-approved and are listed in `09_open_items.md`.

## 13. support_admin
A staff member who investigates trips, cancels and refunds. Identifier: `id`. Serves U3, B9, B10.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| full_name | text | required | personal data (B8) |
| email | text | required | unique; personal data (B8) |
| is_active | boolean | required | default true |
| deleted_at | timestamptz | optional | soft delete |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 14. audit_log
A permanent record of sensitive actions: setting changes, payment status changes, refunds, cancellations by support, and support notes about disputes. Append-only. Identifier: `id`. Serves B5, B4, U3, and the dispute rule in section 4 of the requirements.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| actor_role | text | required | rider, driver, support, provider or system |
| actor_rider_id | uuid | optional | foreign key to rider |
| actor_driver_id | uuid | optional | foreign key to driver |
| actor_admin_id | uuid | optional | foreign key to support_admin |
| action | text | required | for example status_change, setting_change, refund_created, dispute_note |
| entity_type | text | required | trip, payment, refund, rating, rider, driver, setting or provider_event. `provider_event` was added in Stage 3: a provider message about a reference we do not know has no payment or refund to cite, so the audit row cites the event itself |
| entity_id | uuid | optional | the id of the thing acted on (not a foreign key, because it points to different tables). Required for every entity_type except setting, whose key is text and is stored in details |
| note | text | optional | a support note. Written only through the function `add_support_note` (see below). The rule that it must not contain card data or secrets is application validation only. The database does not check it |
| details | jsonb | optional | for example `{"from":"pending","to":"succeeded"}` |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | equals created_at |

A `setting` key is text and cannot fit in a uuid column, so setting changes leave `entity_id` empty and store the key in `details` (for example `{"key":"cancellation_fee_minor","from":50000,"to":60000}`). A check constraint makes `entity_id` required for every other entity type.

**Who writes it (migrations 010 and 011):** the trigger functions `setting_write_audit`, `payment_write_audit` and `provider_event_write_audit`, and the function `add_support_note(entity_type, entity_id, note)`. All four are `SECURITY DEFINER`, owned by `ridehail_writer`, with a fixed search_path. `ridehail_app` has SELECT only on this table. `add_support_note` is the only door for a dispute note: it records the claimed actor and refuses any actor but `support`. It was added because revoking INSERT from the application would otherwise have left support with no way to write the note that docs 01 requires. Limits: a superuser can bypass it, and the actor name is stated by the application.

## 15. status_transition_rule (added)
One row per legal status change for a given actor, for the trip and for the payment. Identifier: the whole row (`entity`, `from_status`, `to_status`, `actor_role`) is the primary key, because the row has no existence apart from those four values. Serves B5, B9, A2, A3, A4.

| Field | Type | Req | Notes |
|---|---|---|---|
| entity | text | required | trip or payment |
| from_status | text | required | |
| to_status | text | required | |
| actor_role | text | required | rider, driver, support, provider or system |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

The full list of rows is in `03_state_machine.md`: 14 rows for the trip and 3 for the payment.

## 16. provider_event (added)
One row for each message the payment provider sends us (a payment or refund result). It is how a repeated or contradicting message is recognised (U4, A4, B6). Identifier: `id` (our uuid). The provider's own id, `provider_event_id`, is unique. Serves U4, A4, B5, B6.

| Field | Type | Req | Notes |
|---|---|---|---|
| id | uuid | required | primary key |
| provider_event_id | text | required | the provider's own id for this message; unique. A repeated message carries the same value |
| provider_reference | text | required | the provider's id of the payment or refund the message is about. Matches `payment.provider_reference` or `refund.provider_reference` by value. It is not a foreign key, because a message about an unknown reference must still be stored |
| event_type | text | required | payment_succeeded, payment_failed, payment_not_found (the provider answered a reconciliation check with "no record of this payment") or refund_succeeded |
| amount_minor | bigint | optional | kobo, more than 0; filled together with currency |
| currency | char(3) | optional | NGN; filled together with the amount |
| occurred_at | timestamptz | optional | the provider's own time of the event, as the provider states it. Not trusted for ordering, only kept for evidence |
| received_at | timestamptz | required | when we received the message. Default `clock_timestamp()`, not `now()`. Reason: `now()` is the start time of the transaction, so every event stored in one transaction would get the same value, and the rule P3 ("not older than the latest provider event of any type for that reference") could not tell which event came last. `clock_timestamp()` gives each row its own moment |
| processed_at | timestamptz | optional | when we finished handling it; filled together with outcome |
| outcome | text | optional | applied, ignored_duplicate or needs_support; filled together with processed_at |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | changes once, when `processed_at` and `outcome` are filled |

The unique constraint on `provider_event_id` makes a repeated message harmless: the second insert is refused or does nothing (tested, see 03 section 4a). Outcome `applied` means the payment or refund row changed. `ignored_duplicate` means a new message id arrived, but the payment already had that result. `needs_support` means the message contradicts the payment's status, or is a `payment_not_found` answer, and a person must act.



---

## Database roles and functions (built in Stage 3, migrations 001, 006, 008 to 011)

| Role | Can log in | What it is for | What it may do |
|---|---|---|---|
| `ridehail` | yes (dev login, superuser) | creating and changing the database during development | everything. The API must never connect as this role |
| `ridehail_app` | no (a login role is a deployment step) | the role the API connects as | the table privileges of migration 008, EXECUTE on `erase_rider`, `erase_driver` and `add_support_note`. SELECT only on `trip_status_history` and `audit_log` |
| `ridehail_erasure_owner` | no | owns `erase_rider` and `erase_driver` | only the column-level SELECT and UPDATE grants of migrations 008 and 009, listed in 04 question 4 |
| `ridehail_writer` | no | owns the history and audit writers | INSERT on `trip_status_history` and `audit_log`, and SELECT on `payment` and `refund` columns `id` and `provider_reference`. Nothing else |

Every function has `search_path = pg_catalog, public, pg_temp` (migration 013, with the reason in 04 question 4), and the TEMP privilege on the database is revoked from PUBLIC (migration 014), so none of the roles above can create temp tables. The four history and audit trigger functions are not executable by PUBLIC (migration 012). A temporary LOGIN role `ridehail_login_test` (member of `ridehail_app`) was created, used to prove the app role's limits as a real login (04 question 6), and dropped; it no longer exists.

Functions in the public schema: 18 = 15 trigger functions (the two shared ones `set_updated_at` and `append_only_guard`, plus 13 table-specific ones) and 3 callable functions (`erase_rider`, `erase_driver`, `add_support_note`). Listed in the catalogue check of the Stage 3 follow-up report.
