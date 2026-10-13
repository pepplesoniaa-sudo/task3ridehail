-- FOLLOW UP 3, migration 014: proofs that the TEMP revoke closes the temp-table door and breaks nothing else.
-- All as ridehail_app (SET ROLE), current_user printed, nothing kept (the whole file is one transaction that is rolled back).
-- The dry run of the migration feeds only the part between the BODY markers inside its own BEGIN ... ROLLBACK.
\set SHOW_CONTEXT always
BEGIN;
-- BODY START
SELECT has_database_privilege('ridehail_app','ridehail_design','TEMP') AS app_may_create_temp,
       has_database_privilege('ridehail_erasure_owner','ridehail_design','TEMP') AS owner_may_create_temp,
       has_database_privilege('ridehail_writer','ridehail_design','TEMP') AS writer_may_create_temp,
       has_database_privilege('ridehail_app','ridehail_design','CONNECT') AS app_may_still_connect;
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '--- T1 CREATE TEMP TABLE is refused (both spellings)'
SAVEPOINT t1a;
CREATE TEMP TABLE proof_temp (a int);
ROLLBACK TO t1a;
SAVEPOINT t1b;
CREATE TABLE pg_temp.proof_temp2 (a int);
ROLLBACK TO t1b;

\echo '--- T1b the three shadow tables of the earlier attacks are refused at the first step'
SAVEPOINT t1c; CREATE TEMP TABLE audit_log (LIKE public.audit_log INCLUDING DEFAULTS); ROLLBACK TO t1c;
SAVEPOINT t1d; CREATE TEMP TABLE trip_status_history (LIKE public.trip_status_history INCLUDING DEFAULTS); ROLLBACK TO t1d;
SAVEPOINT t1e; CREATE TEMP TABLE status_transition_rule (entity text, from_status text, to_status text, actor_role text); ROLLBACK TO t1e;

\echo '--- T2 a normal trip move: driver 3 moves trip 10 assigned -> arrived, the trigger writes the history row'
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
UPDATE trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
SELECT seq IS NOT NULL AS has_seq, from_status, to_status, actor_role, actor_driver_id FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010' ORDER BY seq DESC LIMIT 1;

\echo '--- T3 a payment move: the provider succeeds PRV-T03-A, the trigger writes the audit row'
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
UPDATE payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT actor_role, action, entity_type, details FROM audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T03-A');

\echo '--- T4 a setting change by support: the trigger writes the audit row'
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE setting SET int_value = 57000 WHERE key = 'cancellation_fee_minor' RETURNING key, int_value;
SELECT actor_role, action, details FROM audit_log WHERE entity_type = 'setting' ORDER BY created_at DESC LIMIT 1;

\echo '--- T5 a rating: rider 3 rates trip 3, the cache of driver 1 changes'
SELECT rating_sum, rating_count FROM driver WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001';
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000003', true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003', 'rider', 4) RETURNING trip_id, rater_role, stars;
SELECT rating_sum, rating_count FROM driver WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001';

\echo '--- T6 an erasure by function: erase_rider(rider 1)'
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000001');
RESET ROLE;
SELECT full_name, phone, deleted_at IS NOT NULL AS deleted FROM rider WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT right(id::text, 2) AS trip, pickup_address, dropoff_address, fare_amount_minor FROM trip WHERE rider_id = 'aaaaaaaa-0000-0000-0000-000000000001' ORDER BY id;
SET ROLE ridehail_app;

\echo '--- T7 a sort that spills to disk still works without the TEMP privilege (temporary FILES, not temp tables)'
SET LOCAL work_mem = '64kB';
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF) SELECT count(*) FROM (SELECT id FROM trip ORDER BY created_at DESC, id) x;
RESET ROLE;
-- BODY END
ROLLBACK;
