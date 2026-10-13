# 06b Error Catalogue

Every error code the API can return. Companion of `06_api_contracts.md`. Test ids E01 to E43 are in `evidence/api_error_mapping_tests.txt` (CONFIRMED: each ran rolled back as `ridehail_app`, `current_user` printed, real Postgres message kept; re-run after migration 015 in `evidence/migration_015_rerun_api_error_mapping.txt`, compared in `evidence/migration_015_error_tests_compare.txt`). INFERRED means reasoned only.

**Rules.** (1) The body is always `{"error": {"code", "message", "request_id", "details"}}`. (2) **A 500 never carries a database message.** A Postgres message can contain ids and row values (CONFIRMED, `evidence/proofs_rejected_and_extra.txt`: `Key (rider_id)=(...) already exists`, `Failing row contains (...)`). The 500 body has only `internal_error`, the fixed message and the `request_id`; the real error goes to the server log under the same `request_id`. (3) **The mapping uses the SQLSTATE only** (migration 015): by constraint name for 23xxx, by the `RHnnn` code for every trigger and function rule (table in section 3). **The Postgres message text is for the server log only and is never parsed.** The SQLSTATE and the constraint name are read in one place, the API's database error mapper; the field name differs between drivers (see `06_api_contracts.md` section 1.6, driver note). A SQLSTATE not in this file, including the old generic `P0001`, is `internal_error` plus an alert, never a guess. (4) Retryable means the same request may be repeated unchanged and can succeed later.

## 1. Every error code

| Code | HTTP | Meaning | Retryable | Database cause (constraint name, or SQLSTATE of the rule) | Test |
|---|---|---|---|---|---|
| bad_request | 400 | body is not valid JSON or a path value is malformed | no | none | n/a |
| invalid_idempotency_key | 400 | `Idempotency-Key` missing, empty, over 128 characters or has a space | no, fix the key | backstop check `idem_key_length` | E32 |
| invalid_cursor | 400 | cursor signature, version, filter fingerprint or fields invalid; or a `Last-Event-ID` / `last_seq` (EP27) that is not a whole number of 0 or more | no, restart the list | none (API) | n/a |
| invalid_filter | 400 | unknown query parameter, `limit` out of range, bad status or date | no | none (API) | n/a |
| invalid_event | 400 | webhook body missing a field or inconsistent | no | backstops `provider_event_type_valid`, `provider_event_money_pair`, `provider_event_amount_positive`, `provider_event_currency_ngn` | E33c, E33d |
| unauthenticated | 401 | token missing, expired, or of a deleted or inactive person | no, sign in | none | n/a |
| invalid_signature | 401 | webhook signature wrong or timestamp too old | no | none | n/a |
| forbidden_role | 403 | the caller's role may never call this endpoint | no | none | n/a |
| not_found | 404 | unknown id, or an id that is not the caller's (same answer for both, so ids cannot be probed) | no | none (ownership condition in the SQL); erasure of an unknown id: SQLSTATE `RH070` | E27 |
| quote_not_found | 404 | no such quote for this rider | no | ownership query; backstop FK `trip_quote_belongs_to_rider`: "insert or update on table "trip" violates foreign key constraint" | E02a, E02b |
| vehicle_not_found | 404 | vehicle is not an active vehicle of this driver | no | API query; backstop FK `trip_vehicle_belongs_to_driver` | E09 |
| rider_has_active_trip | 409 | rider already has a requested, assigned, arrived or started trip | no, until that trip ends | unique index `trip_one_active_per_rider`: "duplicate key value violates unique constraint" | E01 |
| driver_has_active_trip | 409 | driver already has an assigned, arrived or started trip | no, until it ends | unique index `trip_one_active_per_driver` | E08 |
| quote_already_used | 409 | the quote already started a trip | no | unique `trip_fare_quote_id_key` | E03 |
| illegal_transition | 409 | the move is not allowed from the trip's current status for this actor | no | SQLSTATE `RH008` (trigger `trip_enforce_transition`) | E05, E05b |
| trip_finished | 409 | the trip is completed or cancelled | no | SQLSTATE `RH005` (trigger `trip_enforce_transition`) | E06 |
| trip_not_open | 409 | accept: the trip is no longer `requested` | no | zero rows from the guarded update; unguarded it would be `RH006` (internal) | E07, E39 |
| trip_not_in_progress | 409 | location read or ping on a trip that is not assigned, arrived or started | no | SQLSTATE `RH030` (trigger `ping_enforce_trip_status`) | E10 |
| trip_not_payable | 409 | payment on a trip that is not completed (nor cancelled with a fee) | no, until completed | SQLSTATE `RH022` (trigger `payment_enforce_rules`) | E13 |
| nothing_to_pay | 409 | cancelled trip with fee 0 | no | SQLSTATE `RH024` (trigger `payment_enforce_rules`) | E14 |
| payment_already_exists | 409 | a pending or succeeded payment already exists for this trip and purpose | no | partial unique index `payment_one_live_per_purpose` | E12 |
| payment_final | 409 | payment already succeeded or failed | no | SQLSTATE `RH026` (trigger `payment_enforce_rules`) | E16 |
| payment_proof_missing | 409 | support tried P3 with no valid `payment_not_found` event | yes, after the reconciliation job records the event | SQLSTATE `RH028` (trigger `payment_enforce_rules`, move P3) | E17 |
| payment_not_succeeded | 409 | refund on a payment that is not succeeded | no | SQLSTATE `RH050` (trigger `refund_enforce_total`) | E20 |
| refund_exceeds_payment | 409 | refunds would exceed the payment amount (B10) | no | SQLSTATE `RH052` (trigger `refund_enforce_total`) | E19 |
| refund_reference_conflict | 409 | provider refund reference already belongs to another refund | no | unique `refund_provider_reference_key` | E21 |
| already_rated | 409 | this side already rated the trip | no | unique `rating_one_per_role_per_trip` | E22 |
| trip_not_completed | 409 | rating on a trip that is not completed | no | SQLSTATE `RH041` (trigger `rating_enforce_rules`) | E23 |
| rating_window_closed | 409 | more than 7 days after completion | no | SQLSTATE `RH043` (trigger `rating_enforce_rules`) | E24 |
| person_has_active_trip | 409 | erasure of a rider or driver with an active trip | yes, after the trip ends | SQLSTATE `RH071` (functions `erase_rider`, `erase_driver`) | E26 |
| request_in_progress | 409 | the same idempotency key is still being processed | yes, after `Retry-After` | SQLSTATE 55P03 "canceling statement due to lock timeout" on the idempotency insert (T1); key row without a stored response (payments) | concurrency test (`evidence/api_idempotency_concurrency_test.txt`) |
| payload_too_large | 413 | body over 16 KiB | no | none | n/a |
| unsupported_media_type | 415 | not `application/json` | no | none | n/a |
| validation_failed | 422 | a field is missing, unknown, wrong type, out of range or too long | no | API validation first; backstop CHECK constraints listed in section 2 | E11, E25, E28, E30, E42 |
| quote_expired | 422 | the quote's `expires_at` has passed | no, get a new quote | SQLSTATE `RH004` (trigger `trip_enforce_transition`) | E04 |
| no_active_vehicle | 422 | the driver has no active vehicle | no | none (API query) | n/a |
| outside_service_area | 422 | pickup or dropoff outside the service area | no | none (API, from settings) | n/a |
| idempotency_key_reuse | 422 | same key with a different body | no, use a new key | none (stored `request_hash` differs) | E31 |
| unknown_setting | 422 | key not in the allow-list | no | none | n/a |
| rate_limited | 429 | too many requests | yes, after `Retry-After` | none | n/a |
| internal_error | 500 | any unexpected error, including every RH code marked `internal_error` in section 3 | maybe: reads yes, writes only with an Idempotency-Key | every other RH code (section 3, mapped to `internal_error`), 42501, 23502, any unknown SQLSTATE | E15, E18, E29, E36 to E41 |
| provider_error | 502 | the payment provider refused or did not answer | yes | none | n/a |
| service_unavailable | 503 | database down, serialization or deadlock after one retry | yes | SQLSTATE 40001, 40P01, connection errors | n/a |
| service_not_configured | 503 | a needed setting has no row (fare, validity, area) | no, until support sets it | SQLSTATE `RH013` (cancellation fee setting missing, trigger `trip_enforce_transition`) or `RH042` (rating window setting missing, trigger `rating_enforce_rules`); for the fare, validity and area settings the API checks the rows itself. CONFIRMED the seed has only 4 settings | n/a |
| estimator_unavailable | 503 | the distance estimator did not answer within 2 seconds, refused, or returned a value outside the allowed ranges (0 to 1,000,000 metres, 0 to 86,400 seconds); no quote is created | yes, ask again after the retry hint | none: no database object is involved and no quote row is written | n/a |

## 2. Every constraint and trigger of `04_hard_questions.md` question 6, mapped

"Mapped" = becomes the named code. "Backstop" = the API validates first, so the constraint is a second line of defence and, if reached, is mapped to `validation_failed` (the contract's validation was not applied: also logged as a bug). "Internal" = must never reach a client: the API computes the value or sets the claim itself, so reaching it is a bug, answered `internal_error`.

| Object | Kind | Status | Code or reason |
|---|---|---|---|
| rider_pkey, driver_pkey, vehicle_pkey, trip_pkey, trip_status_history_pkey, location_ping_pkey, fare_quote_pkey, payment_pkey, provider_event_pkey, refund_pkey, rating_pkey, idempotency_key_pkey, setting_pkey, support_admin_pkey, audit_log_pkey, rule_pkey | PK | internal | ids are generated by the server; a clash is a bug |
| rider_phone_key, driver_phone_key, driver_licence_number_key, support_admin_email_key, vehicle_plate_number_active_key, vehicle_id_driver_id_key, fare_quote_id_rider_id_key | UNIQUE | internal | only used by account creation and by the key pairs; no Part A endpoint writes them |
| trip_fare_quote_id_key | UNIQUE | mapped | quote_already_used |
| trip_one_active_per_rider | UNIQUE | mapped | rider_has_active_trip |
| trip_one_active_per_driver | UNIQUE | mapped | driver_has_active_trip |
| payment_provider_reference_key | UNIQUE | mapped | provider_error (EP15: the provider returned a reference already used) |
| payment_one_live_per_purpose | UNIQUE | mapped | payment_already_exists |
| provider_event_provider_event_id_key | UNIQUE | mapped | not an error: the webhook uses ON CONFLICT DO NOTHING and answers 200 `duplicate_event` |
| refund_provider_reference_key | UNIQUE | mapped | refund_reference_conflict (or the 200 replay) |
| rating_one_per_role_per_trip | UNIQUE | mapped | already_rated |
| idem_one_key_per_rider_action | UNIQUE | mapped | not an error: ON CONFLICT DO NOTHING, then replay, `idempotency_key_reuse` or `request_in_progress` |
| trip_quote_belongs_to_rider | FK | mapped | quote_not_found |
| trip_vehicle_belongs_to_driver | FK | mapped | vehicle_not_found |
| trip_rider_id_fkey, trip_driver_id_fkey, vehicle_driver_id_fkey, history_trip_id_fkey, history_actor_rider_fkey, history_actor_driver_fkey, history_actor_admin_fkey, ping_trip_id_fkey, quote_rider_id_fkey, payment_trip_id_fkey, refund_payment_id_fkey, refund_created_by_admin_fkey, rating_trip_id_fkey, idem_rider_id_fkey, idem_trip_id_fkey, idem_payment_id_fkey, setting_updated_by_fkey, audit_actor_rider_fkey, audit_actor_driver_fkey, audit_actor_admin_fkey | FK | internal | the ids come from the token or from rows the API just read; an unknown id is caught earlier as `not_found` |
| ping_latitude_range, ping_longitude_range, ping_accuracy_not_negative | CHECK | backstop | validation_failed (E11) |
| rating_stars_range, rating_comment_length | CHECK | backstop | validation_failed (E25) |
| setting_value_not_negative, setting_money_has_currency, setting_currency_ngn | CHECK | backstop | validation_failed (E28a to c) |
| audit_entity_type_valid, audit_entity_id_matches_type | CHECK | backstop | validation_failed (E30b, E30c) |
| idem_key_length | CHECK | backstop | invalid_idempotency_key (E32) |
| idem_hash_format, idem_action_valid, idem_response_complete | CHECK | internal | the API builds hash, action and response itself |
| provider_event_type_valid, provider_event_money_pair, provider_event_amount_positive, provider_event_currency_ngn | CHECK | backstop | invalid_event (E33c, E33d) |
| provider_event_outcome_valid, provider_event_processed_has_outcome | CHECK | internal | set by the handler |
| payment_failed_has_reason | CHECK | backstop | validation_failed (EP20: failure_reason required) |
| payment_purpose_valid, payment_status_valid, payment_amount_positive, payment_currency_ngn, payment_succeeded_has_proof | CHECK | internal | purpose, amount and currency are computed by the API; status is moved by triggers |
| refund_amount_positive, refund_currency_ngn, refund_reason_not_blank | CHECK | backstop | validation_failed |
| trip_completed_has_facts, trip_amounts_not_negative | CHECK | backstop | validation_failed (EP12 `distance_m`; E42) |
| trip_status_valid, trip_driver_matches_status, trip_snapshots_match_assignment, trip_started_has_time, trip_cancelled_has_facts, trip_cancelled_by_valid, trip_times_in_order, trip_currency_ngn, trip_fee_needs_driver, trip_fee_only_when_rider_cancels | CHECK | internal | written by the trigger or fixed by the move; reaching one is a bug |
| quote_amount_not_negative, quote_currency_ngn, quote_estimates_not_negative, quote_expires_after_created | CHECK | internal | computed by the API |
| quote_coordinates_valid | CHECK | backstop | validation_failed (EP01) |
| rider_phone_format, rider_name_not_blank, rider_rating_cache_valid, driver_phone_format, driver_name_not_blank, driver_rating_cache_valid, vehicle_seat_count_range, vehicle_plate_not_blank, support_admin_email_format, support_admin_name_not_blank | CHECK | internal | account data, no Part A endpoint writes it; rating caches are written by a trigger |
| history_to_status_valid, history_from_status_valid, history_status_changes, history_first_row_is_requested, history_actor_matches_role, audit_actor_matches_role | CHECK | internal | written only by the writer functions |
| rating_role_valid | CHECK | internal | `rater_role` comes from the token, never the body |
| rule_entity_valid, rule_actor_role_valid, rule_from_differs_to | CHECK | internal | rule table data, not reachable from the API |
| trip_enforce_transition | trigger | mapped | by SQLSTATE: `RH004` quote_expired, `RH005` trip_finished, `RH008` illegal_transition, `RH013` service_not_configured; internal: `RH001`, `RH002`, `RH003`, `RH006`, `RH007`, `RH009`, `RH010`, `RH011`, `RH012`, `RH014`, `RH015` |
| payment_enforce_rules | trigger | mapped | by SQLSTATE: `RH022` trip_not_payable, `RH024` nothing_to_pay, `RH026` payment_final, `RH028` payment_proof_missing; internal: `RH007`, `RH011`, `RH020`, `RH021`, `RH023`, `RH025`, `RH027`, `RH029` |
| refund_enforce_total | trigger | mapped | by SQLSTATE: `RH050` payment_not_succeeded, `RH052` refund_exceeds_payment; internal: `RH051` |
| rating_enforce_rules | trigger | mapped | by SQLSTATE: `RH041` trip_not_completed, `RH043` rating_window_closed, `RH042` service_not_configured; internal: `RH044`, `RH045` |
| ping_enforce_trip_status | trigger | mapped | by SQLSTATE `RH030`: trip_not_in_progress |
| provider_event_guard | trigger | internal | `RH031`, `RH032`, `RH033`: the handler only inserts, then fills `processed_at` and `outcome` once |
| setting_write_audit | trigger | internal | `RH060`: the role check precedes the call |
| trip_write_history, payment_write_audit, provider_event_write_audit | trigger | internal | writer functions; "permission denied for table trip_status_history" is E36 |
| trip_block_delete, append_only_guard, rating_block_change | trigger | internal | `RH016`, `RH080`, `RH040`: the API has no endpoint that edits or deletes these rows |
| rating_update_cache, set_updated_at | trigger | n/a | write derived columns, no error path |
| add_support_note (function) | function | mapped | `RH062` validation_failed; internal: `RH061` |
| erase_rider, erase_driver (functions) | function | mapped | `RH071` person_has_active_trip, `RH070` not_found |

## 3. SQLSTATE per rule (migration 015, custom class RH)

Every `RAISE EXCEPTION` of our triggers and functions carries its own SQLSTATE (45 codes, 49 statements; the codes RH007, RH011, RH070 and RH071 are one rule raised from two functions). The message text is unchanged and is for logs only. A row whose API code is `internal_error` must never reach a client: the API computes the value or sets the claim itself, so reaching it is a bug. Test = the test that raised this code as printed in `evidence/migration_015_error_tests_compare.txt` (E ids) or `evidence/untested_rh_codes_proofs.txt` (U ids); all 45 codes have now been raised (CONFIRMED). "Reachable by the application role" says whether `ridehail_app` can raise it: "yes" = raised as `ridehail_app` with the grants that exist; "only if the setting row is missing" = the code is live but the app role cannot create that state; "no, a privilege stops it first" = the application role is refused with SQLSTATE 42501 before the trigger runs (the trigger still fires for the dev login, so the code is live for other roles); "no, dead under the current rule table" = nothing the application role can do reaches it.

| SQLSTATE | Rule | Trigger or function | Message start (log only) | API error code | Test | Reachable by the application role |
|---|---|---|---|---|---|---|
| `RH001` | only the rider may request a trip | trip_enforce_transition | only the rider may request a trip | internal_error | E37 | yes, raised as ridehail_app |
| `RH002` | a new trip must start as requested | trip_enforce_transition | a new trip must start as requested | internal_error | U-RH002 | yes, raised as ridehail_app |
| `RH003` | a new trip cannot carry start, end or cancel times | trip_enforce_transition | a new trip cannot carry | internal_error | U-RH003 | yes, raised as ridehail_app |
| `RH004` | fare quote has expired | trip_enforce_transition | fare quote % has expired | quote_expired | E04 | yes, raised as ridehail_app |
| `RH005` | trip is terminal | trip_enforce_transition | trip is % (terminal) | trip_finished | E06 | yes, raised as ridehail_app |
| `RH006` | driver_id cannot change once set | trip_enforce_transition | driver_id cannot change once set | internal_error | E39 | yes, raised as ridehail_app |
| `RH007` | actor role not set | trip_enforce_transition, payment_enforce_rules | app.actor_role is not set | internal_error | U-RH007a, U-RH007b | yes, raised as ridehail_app (trip and payment) |
| `RH008` | illegal trip transition | trip_enforce_transition | illegal transition % | illegal_transition | E05, E05b | yes, raised as ridehail_app |
| `RH009` | actor is not the trip rider | trip_enforce_transition | actor is not this trip's rider | internal_error | U-RH009 | yes, raised as ridehail_app |
| `RH010` | actor is not the trip driver | trip_enforce_transition | actor is not this trip's driver | internal_error | E38 | yes, raised as ridehail_app |
| `RH011` | support actor id required | trip_enforce_transition, payment_enforce_rules | a support actor id is required | internal_error | U-RH011a, U-RH011b | yes, raised as ridehail_app (trip and payment) |
| `RH012` | vehicle required to assign | trip_enforce_transition | a vehicle is required | internal_error | E40 | yes, raised as ridehail_app |
| `RH013` | cancellation fee setting missing | trip_enforce_transition | setting cancellation_fee_minor is missing | service_not_configured | U-RH013, U-RH013b | only if the setting row is missing: raised as ridehail_app after the dev login deleted the row; the app role cannot delete it (42501) |
| `RH014` | unexpected target status | trip_enforce_transition | unexpected target status | internal_error | U-RH014a, b, c | no, dead under the current rule table: no rule row targets a status outside the CASE; the app role cannot add a rule row (42501); raised only after the dev login added one |
| `RH015` | columns outside the move changed (trip) | trip_enforce_transition | these columns may not change | internal_error | E41 | yes, raised as ridehail_app |
| `RH016` | trips are never deleted | trip_block_delete | trips are never deleted | internal_error | U-RH016a, U-RH016b | no, a privilege stops it first (42501, no DELETE on trip); raised for the dev login |
| `RH020` | payment must start pending | payment_enforce_rules | a payment must be created as pending | internal_error | U-RH020 | yes, raised as ridehail_app |
| `RH021` | only the trip rider may start a payment | payment_enforce_rules | only the trip's rider may start a payment | internal_error | U-RH021 | yes, raised as ridehail_app |
| `RH022` | fare payment needs a completed trip | payment_enforce_rules | a fare payment needs | trip_not_payable | E13 | yes, raised as ridehail_app |
| `RH023` | payment amount differs from fare | payment_enforce_rules | payment amount % does not equal the trip fare | internal_error | E15 | yes, raised as ridehail_app |
| `RH024` | cancellation fee payment needs a fee | payment_enforce_rules | a cancellation fee payment needs | nothing_to_pay | E14 | yes, raised as ridehail_app |
| `RH025` | payment amount differs from fee | payment_enforce_rules | payment amount % does not equal the cancellation fee | internal_error | U-RH025 | yes, raised as ridehail_app |
| `RH026` | payment is terminal | payment_enforce_rules | payment is % (terminal) | payment_final | E16 | yes, raised as ridehail_app |
| `RH027` | illegal payment transition | payment_enforce_rules | illegal payment transition | internal_error | E18 | yes, raised as ridehail_app |
| `RH028` | P3 proof missing | payment_enforce_rules | support may fail a pending payment | payment_proof_missing | E17 | yes, raised as ridehail_app |
| `RH029` | columns outside the move changed (payment) | payment_enforce_rules | these payment columns may not change | internal_error | U-RH029 | yes, raised as ridehail_app |
| `RH030` | ping needs an open trip | ping_enforce_trip_status | a location ping needs | trip_not_in_progress | E10 | yes, raised as ridehail_app |
| `RH031` | provider_event never deleted | provider_event_guard | provider_event rows are never deleted | internal_error | U-RH031a, U-RH031b | no, a privilege stops it first (42501, no DELETE on provider_event); raised for the dev login |
| `RH032` | provider_event already processed | provider_event_guard | provider_event is already processed | internal_error | E34 | yes, raised as ridehail_app |
| `RH033` | provider_event received fields frozen | provider_event_guard | the received fields of a provider_event | internal_error | U-RH033 | yes, raised as ridehail_app |
| `RH040` | rating rows are append-only | rating_block_change | rating is append-only | internal_error | U-RH040a, U-RH040b | no, a privilege stops it first (42501, no UPDATE or DELETE on rating); raised for the dev login |
| `RH041` | rating needs a completed trip | rating_enforce_rules | a rating needs a completed trip | trip_not_completed | E23 | yes, raised as ridehail_app |
| `RH042` | rating window setting missing | rating_enforce_rules | setting rating_window_days is missing | service_not_configured | U-RH042 | only if the setting row is missing: raised as ridehail_app after the dev login deleted the row; the app role cannot delete it (42501) |
| `RH043` | rating window passed | rating_enforce_rules | the rating window of | rating_window_closed | E24 | yes, raised as ridehail_app |
| `RH044` | rating must come from the trip rider | rating_enforce_rules | the rating must come from this trip's rider | internal_error | U-RH044 | yes, raised as ridehail_app |
| `RH045` | rating must come from the trip driver | rating_enforce_rules | the rating must come from this trip's driver | internal_error | U-RH045 | yes, raised as ridehail_app |
| `RH050` | refund needs a succeeded payment | refund_enforce_total | a refund needs a succeeded payment | payment_not_succeeded | E20 | yes, raised as ridehail_app |
| `RH051` | refund currency differs | refund_enforce_total | refund currency | internal_error | U-RH051 | yes, raised as ridehail_app |
| `RH052` | refunds exceed payment | refund_enforce_total | refunds % + % | refund_exceeds_payment | E19 | yes, raised as ridehail_app |
| `RH060` | only support may change a setting | setting_write_audit | only a support actor may change a setting | internal_error | E29 | yes, raised as ridehail_app |
| `RH061` | only support may write a note | add_support_note | only a support actor may write a support note | internal_error | E30d | yes, raised as ridehail_app |
| `RH062` | support note empty | add_support_note | a support note cannot be empty | validation_failed | E30a | yes, raised as ridehail_app |
| `RH070` | person does not exist (erasure) | erase_rider, erase_driver | rider % does not exist / driver % does not exist | not_found | E27 | yes, raised as ridehail_app |
| `RH071` | person has an active trip (erasure) | erase_rider, erase_driver | rider % has an active trip / driver % has an active trip | person_has_active_trip | E26, E26b | yes, raised as ridehail_app |
| `RH080` | append-only table | append_only_guard | % is append-only: % is not allowed | internal_error | U-RH080a, U-RH080b | no, a privilege stops it first (42501, no UPDATE on fare_quote, refund, audit_log, trip_status_history or location_ping); raised for the dev login |

Other SQLSTATEs: 23505, 23503, 23514 are mapped by constraint name (section 2); 55P03 gives `request_in_progress`; 40001 and 40P01 are retried once, then `service_unavailable`; 42501 and 23502 are `internal_error`. Internal-only reasons by group: append-only and never-deleted rules (RH016, RH031, RH032, RH033, RH040, RH080): the API has no endpoint that edits or deletes those rows. Insert-shape rules (RH002, RH003, RH020): the insert statements never set those columns. Claim rules (RH001, RH007, RH009, RH010, RH011, RH021, RH044, RH045, RH060, RH061): the claim comes from the token and the SQL carries the ownership condition, so a stranger gets 404 first. Computed values (RH023, RH025, RH051): the API takes amount and currency from the trip or payment row. Move shape (RH006, RH012, RH014, RH015, RH027, RH029): each update names only its own columns and carries the status guard.

**Unreachable by the application role (6 codes, CONFIRMED in evidence/untested_rh_codes_proofs.txt):** RH016 (delete a trip), RH031 (delete a provider event), RH040 (change or delete a rating) and RH080 (change a row of an append-only table) are stopped by a privilege first (42501, a different layer from the trigger). RH014 is dead under the current rule table: every trip rule row targets arrived, assigned, started, completed or cancelled, and the app role has no INSERT on the rule table. RH013 and RH042 are live only in a database where the setting row is missing, a state the app role cannot create (it has no DELETE on setting). None of the six may reach a client; if one does it is internal_error plus an alert, as for every unknown SQLSTATE.

## 4. Codes used and unused
Every code in section 1 appears in at least one endpoint of `06_api_contracts.md`; the check script (see the report) confirms it both ways.
