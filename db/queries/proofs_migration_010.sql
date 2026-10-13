-- PROOFS for migration 010: history and audit are written by the database, not by ridehail_app.
-- Every proof is its own BEGIN ... ROLLBACK, runs after SET ROLE ridehail_app, and prints current_user.
-- Small set = the 12 trips eeeeeeee-... of seed A. Run without ON_ERROR_STOP.
\set SHOW_CONTEXT always
\set VERBOSITY default

\echo '################ PART 0: how the existing rows were numbered (read only, as ridehail_app)'
SET ROLE ridehail_app;
SELECT current_user, session_user;
\echo '--- 0a rows, trips with several history rows, and how many of those trips have ALL their rows at one created_at'
SELECT (SELECT count(*) FROM trip_status_history) AS history_rows,
       (SELECT count(*) FROM (SELECT trip_id FROM trip_status_history GROUP BY trip_id HAVING count(*) > 1) x) AS trips_with_several_rows,
       (SELECT count(*) FROM (SELECT trip_id FROM trip_status_history GROUP BY trip_id HAVING count(*) > 1 AND count(DISTINCT created_at) = 1) y) AS trips_whose_rows_all_tie_on_created_at;
\echo '--- 0b chain check: ordered by seq, each trip''s first row has no from_status and each next row starts where the previous one ended. Expect 0 violations'
SELECT count(*) AS chain_violations_by_seq FROM (
  SELECT from_status, row_number() OVER w AS rn, lag(to_status) OVER w AS prev_to
  FROM trip_status_history WINDOW w AS (PARTITION BY trip_id ORDER BY seq)) x
WHERE (rn = 1 AND from_status IS NOT NULL) OR (rn > 1 AND from_status IS DISTINCT FROM prev_to);
\echo '--- 0b2 the same chain check for the 12 small-set trips only (the trips the proofs and the demonstrations use)'
SELECT count(*) AS small_set_chain_violations_by_seq FROM (
  SELECT from_status, row_number() OVER w AS rn, lag(to_status) OVER w AS prev_to
  FROM trip_status_history WHERE trip_id::text LIKE 'eeeeeeee%' WINDOW w AS (PARTITION BY trip_id ORDER BY seq)) x
WHERE (rn = 1 AND from_status IS NOT NULL) OR (rn > 1 AND from_status IS DISTINCT FROM prev_to);
\echo '--- 0c the same check ordered by created_at then id (what the old query would have given). Expect many violations, because the ties are broken by random uuids'
SELECT count(*) AS chain_violations_by_created_at_then_id FROM (
  SELECT from_status, row_number() OVER w AS rn, lag(to_status) OVER w AS prev_to
  FROM trip_status_history WINDOW w AS (PARTITION BY trip_id ORDER BY created_at, id)) x
WHERE (rn = 1 AND from_status IS NOT NULL) OR (rn > 1 AND from_status IS DISTINCT FROM prev_to);
\echo '--- 0d seq is unique and strictly increasing with insert order inside each trip of the small set'
SELECT right(trip_id::text, 2) AS trip, string_agg(seq || ':' || coalesce(from_status,'new') || '>' || to_status, '  ' ORDER BY seq) AS timeline_by_seq
FROM trip_status_history WHERE trip_id IN ('eeeeeeee-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000008') GROUP BY trip_id ORDER BY 1;
RESET ROLE;

\echo '################ F1: direct INSERT into trip_status_history is refused by privilege'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
INSERT INTO trip_status_history (trip_id, from_status, to_status, actor_role, actor_rider_id)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', NULL, 'requested', 'rider', 'aaaaaaaa-0000-0000-0000-000000000001');
ROLLBACK;

\echo '################ F2: direct INSERT into audit_log is refused by privilege'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
INSERT INTO audit_log (actor_role, action, entity_type, entity_id) VALUES ('provider', 'fake', 'payment', 'eeeeeeee-0000-0000-0000-000000000001');
ROLLBACK;

\echo '################ F3: a normal trip move still writes its history row, with the claimed actor (driver 3 moves trip 10, small set)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT count(*) AS history_rows_before FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010';
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
UPDATE trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
SELECT count(*) AS history_rows_after FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010';
SELECT seq, from_status, to_status, actor_role, actor_driver_id,
       actor_driver_id = 'bbbbbbbb-0000-0000-0000-000000000003' AS matches_claimed_actor
FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010' ORDER BY seq DESC LIMIT 1;
ROLLBACK;

\echo '################ F3b + H: every kind of actor is recorded right, and the timeline order is stable when several moves share one created_at'
\echo '################ (one transaction: trip 1 by rider 2000 and driver 400, trip 2 cancelled by the system, trip 3 cancelled by support)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
SELECT ('ffffffff-0000-0000-0000-0000000000b' || n)::uuid, '10000000-0000-0000-0000-000000002000', 6.45, 3.39, 6.50, 3.35, 5000, 900, 100000, 'NGN', now() + interval '1 hour' FROM generate_series(1,3) n;
INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000002000', 'ffffffff-0000-0000-0000-0000000000b1', 'p1', 'd1');
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', '20000000-0000-0000-0000-000000000400', true);
UPDATE trip SET status = 'assigned', driver_id = '20000000-0000-0000-0000-000000000400', vehicle_id = '30000000-0000-0000-0000-000000000400' WHERE id = '90000000-0000-0000-0000-000000000001';
UPDATE trip SET status = 'arrived' WHERE id = '90000000-0000-0000-0000-000000000001';
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
UPDATE trip SET status = 'cancelled' WHERE id = '90000000-0000-0000-0000-000000000001';
-- trip 2: requested then cancelled by the system (timeout)
INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000002000', 'ffffffff-0000-0000-0000-0000000000b2', 'p2', 'd2');
SELECT set_config('app.actor_role', 'system', true), set_config('app.actor_id', '', true);
UPDATE trip SET status = 'cancelled' WHERE id = '90000000-0000-0000-0000-000000000002';
-- trip 3: requested then cancelled by support admin 1
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('90000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000002000', 'ffffffff-0000-0000-0000-0000000000b3', 'p3', 'd3');
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE trip SET status = 'cancelled' WHERE id = '90000000-0000-0000-0000-000000000003';
\echo '--- every history row of the three trips: the actor columns match the claimed actor'
SELECT right(trip_id::text, 1) AS trip, seq, coalesce(from_status, '(new)') || ' > ' || to_status AS move, actor_role,
       right(actor_rider_id::text, 4) AS rider, right(actor_driver_id::text, 4) AS driver, right(actor_admin_id::text, 4) AS admin
FROM trip_status_history WHERE trip_id::text LIKE '90000000%' ORDER BY seq;
\echo '--- H: trip 1, all four rows share ONE created_at'
SELECT count(*) AS rows, count(DISTINCT created_at) AS distinct_created_at FROM trip_status_history WHERE trip_id = '90000000-0000-0000-0000-000000000001';
\echo '--- H: the old order (created_at, then id as tie-break): the chain is scrambled'
SELECT coalesce(from_status, '(new)') || ' > ' || to_status AS move FROM trip_status_history WHERE trip_id = '90000000-0000-0000-0000-000000000001' ORDER BY created_at, id;
\echo '--- H: the new order (seq): the chain is correct and stable'
SELECT seq, coalesce(from_status, '(new)') || ' > ' || to_status AS move FROM trip_status_history WHERE trip_id = '90000000-0000-0000-0000-000000000001' ORDER BY seq;
\echo '--- A3.3 timeline query rewritten to ORDER BY seq, on the same trip (index trip_status_history_trip_seq_idx)'
EXPLAIN (COSTS OFF) SELECT from_status, to_status, actor_role, created_at FROM trip_status_history WHERE trip_id = '90000000-0000-0000-0000-000000000001' ORDER BY seq;
ROLLBACK;

\echo '################ F4: a refused move writes nothing (driver 4 tries to move driver 3''s trip 10)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000004', true);
SELECT count(*) AS history_rows_before FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010' \gset
SAVEPOINT s;
UPDATE trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010';
ROLLBACK TO s;
SELECT count(*) AS history_rows_after, :history_rows_before AS history_rows_before FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010';
ROLLBACK;

\echo '################ F5: a payment status change still writes its audit row (provider succeeds pending payment PRV-T03-A)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT count(*) AS audit_rows_for_payment_before FROM audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T03-A');
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
UPDATE payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT actor_role, action, entity_type, details FROM audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T03-A') ORDER BY created_at;
ROLLBACK;

\echo '################ F6: a setting change by support still writes its audit row; a change by anyone else is refused'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT count(*) AS setting_audit_rows_before FROM audit_log WHERE entity_type = 'setting' \gset
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE setting SET int_value = 55000 WHERE key = 'cancellation_fee_minor' RETURNING key, int_value;
SELECT :setting_audit_rows_before AS setting_audit_rows_before, count(*) AS setting_audit_rows_after FROM audit_log WHERE entity_type = 'setting';
SELECT actor_role, right(actor_admin_id::text, 4) AS admin, action, entity_type, entity_id, details FROM audit_log WHERE entity_type = 'setting' ORDER BY created_at DESC LIMIT 1;
ROLLBACK;

\echo '--- F6b: the same change claimed by a rider'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
UPDATE setting SET int_value = 55000 WHERE key = 'cancellation_fee_minor';
ROLLBACK;

\echo '################ F7: P3 and provider_conflict audit rows still appear (stuck payment PRV-T03-A)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome)
VALUES ('evt-nf-t03-m10', 'PRV-T03-A', 'payment_not_found', now(), 'needs_support');
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE payment SET status = 'failed', failure_reason = 'support: provider has no record' WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT actor_role, right(actor_admin_id::text, 4) AS admin, action, entity_type, details FROM audit_log
WHERE entity_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T03-A') ORDER BY created_at;
ROLLBACK;

\echo '################ F7b: provider_conflict for a reference nobody knows (entity_type provider_event)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome)
VALUES ('evt-nf-nobody-m10', 'PRV-NOBODY', 'payment_not_found', now(), 'needs_support');
SELECT actor_role, action, entity_type, details FROM audit_log WHERE details->>'provider_event_id' = 'evt-nf-nobody-m10';
ROLLBACK;

\echo '################ F8: support notes go through add_support_note only'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000002', true);
SELECT add_support_note('trip', 'eeeeeeee-0000-0000-0000-000000000001', 'Rider disputes the route. Refund of 50000 kobo agreed by phone.') IS NOT NULL AS note_written;
SELECT actor_role, right(actor_admin_id::text, 4) AS admin, action, entity_type, right(entity_id::text, 2) AS trip, note FROM audit_log WHERE action = 'dispute_note';
ROLLBACK;

\echo '--- F8b: the same call claimed by a rider'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
SELECT add_support_note('trip', 'eeeeeeee-0000-0000-0000-000000000001', 'I am not support');
ROLLBACK;

\echo '--- F8c: a role with no grant cannot call it either (role created and rolled back inside the transaction)'
BEGIN;
CREATE ROLE ridehail_proof_nogrant NOLOGIN;
SET ROLE ridehail_proof_nogrant;
SELECT current_user, session_user;
SELECT add_support_note('trip', 'eeeeeeee-0000-0000-0000-000000000001', 'x');
ROLLBACK;

\echo '################ nothing left behind'
SELECT (SELECT count(*) FROM pg_roles WHERE rolname = 'ridehail_proof_nogrant') AS proof_roles_left,
       (SELECT count(*) FROM trip_status_history) AS history_rows, (SELECT count(*) FROM trip_status_history WHERE trip_id::text LIKE '90000000%') AS proof_history_rows_left,
       (SELECT count(*) FROM audit_log) AS audit_rows, (SELECT count(*) FROM audit_log WHERE action = 'dispute_note') AS notes_left,
       (SELECT count(*) FROM trip WHERE id::text LIKE '90000000%') AS proof_trips_left;
