# 15 Appendix F: entity field tables

This appendix holds the field tables for 14 of the 16 entities, copied without change from `02_entities.md` so a reader can see every column in one place. The two entities left out are `trip` (section 4 of `02_entities.md`) and `payment` (section 8 of `02_entities.md`); they are the two largest tables and are kept in `02_entities.md` itself. The source line numbers below are from `02_entities.md` as it stands at this fix.

## 1. rider (source: `02_entities.md` lines 21 to 34)

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

## 2. driver (source: `02_entities.md` lines 36 to 49)

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

## 3. vehicle (source: `02_entities.md` lines 51 to 66)

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

## 5. trip_status_history (source: `02_entities.md` lines 95 to 112)

One row for every status change of a trip, written by the database itself (B5). Append-only. Identifier: `id`. Serves B5, A1, A2, A3.

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

## 6. location_ping (source: `02_entities.md` lines 118 to 130)

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

## 7. fare_quote (source: `02_entities.md` lines 132 to 149)

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

## 9. refund (source: `02_entities.md` lines 168 to 181)

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

## 10. rating (source: `02_entities.md` lines 183 to 194)

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

## 11. idempotency_key (source: `02_entities.md` lines 196 to 212)

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

## 12. setting (source: `02_entities.md` lines 214 to 225)

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

## 13. support_admin (source: `02_entities.md` lines 229 to 240)

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

## 14. audit_log (source: `02_entities.md` lines 242 to 258)

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

## 15. status_transition_rule (source: `02_entities.md` lines 264 to 274)

One row per legal status change for a given actor, for the trip and for the payment. Identifier: the whole row (`entity`, `from_status`, `to_status`, `actor_role`) is the primary key, because the row has no existence apart from those four values. Serves B5, B9, A2, A3, A4.

| Field | Type | Req | Notes |
|---|---|---|---|
| entity | text | required | trip or payment |
| from_status | text | required | |
| to_status | text | required | |
| actor_role | text | required | rider, driver, support, provider or system |
| created_at | timestamptz | required | |
| updated_at | timestamptz | required | |

## 16. provider_event (source: `02_entities.md` lines 278 to 294)

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
