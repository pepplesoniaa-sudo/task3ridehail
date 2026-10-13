-- API PART A: evidence for the database error -> HTTP status mapping (docs 06_api_contracts.md, 06b_error_catalogue.md).
-- Every test is its own BEGIN ... ROLLBACK, runs as ridehail_app (SET ROLE), prints current_user, and ends with the statement that causes the error.
-- After a failing statement the SQLSTATE is printed (psql variable LAST_ERROR_SQLSTATE). A line "UPDATE 0" or "INSERT 0 0" means "no database error, zero rows".
-- Nothing is kept. Small set = the 12 trips eeeeeeee-... of seed A; bulk riders 10000000-...-3000 and -3001 have no active trip.
\set VERBOSITY default
\set SHOW_CONTEXT never

\echo '=== E01 rider_has_active_trip: rider 5 already has trip 09 (requested) and requests another'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000005',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000d1','aaaaaaaa-0000-0000-0000-000000000005',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('aaaaaaaa-0000-0000-0000-000000000005','ffffffff-0000-0000-0000-0000000000d1','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E02a quote_not_found: rider 3000 uses a quote that belongs to rider 3001'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003001',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-000000003001',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000d2','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E02b quote_not_found: a quote id that does not exist'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000ee','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E03 quote_already_used: the same quote starts a second trip after the first one was cancelled'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000d3','10000000-0000-0000-0000-000000003000',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('90000000-0000-0000-0000-0000000000d3','10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000d3','p','d');
UPDATE trip SET status='cancelled' WHERE id='90000000-0000-0000-0000-0000000000d3' RETURNING status, cancellation_fee_minor;
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000d3','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E04 quote_expired: a quote created 2 hours ago that expired 1 hour ago'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, created_at, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000d4','10000000-0000-0000-0000-000000003000',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()-interval '2 hours',now()-interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000d4','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E05 illegal_transition: driver 4 tries to start trip 09 (status requested)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
UPDATE trip SET status='started' WHERE id='eeeeeeee-0000-0000-0000-000000000009';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E05b illegal_transition: rider 2 tries to cancel trip 12 (status started)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000002',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000012';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E06 trip_finished: driver 1 tries to move completed trip 01 to started'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000001',true);
UPDATE trip SET status='started' WHERE id='eeeeeeee-0000-0000-0000-000000000001';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E07 trip_not_open: accept with the guard WHERE status = requested on a trip that is already started (no error, zero rows)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000001',true);
UPDATE trip SET status='assigned', driver_id='bbbbbbbb-0000-0000-0000-000000000001', vehicle_id='cccccccc-0000-0000-0000-000000000001' WHERE id='eeeeeeee-0000-0000-0000-000000000012' AND status='requested';
ROLLBACK;

\echo '=== E08 driver_has_active_trip: driver 3 (active trip 10) accepts trip 09'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000003',true);
UPDATE trip SET status='assigned', driver_id='bbbbbbbb-0000-0000-0000-000000000003', vehicle_id='cccccccc-0000-0000-0000-000000000003' WHERE id='eeeeeeee-0000-0000-0000-000000000009' AND status='requested';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E09 vehicle_not_yours: driver 1 (free) accepts trip 09 with the vehicle of driver 4'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000001',true);
UPDATE trip SET status='assigned', driver_id='bbbbbbbb-0000-0000-0000-000000000001', vehicle_id='cccccccc-0000-0000-0000-000000000004' WHERE id='eeeeeeee-0000-0000-0000-000000000009' AND status='requested';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E10 trip_not_in_progress: a location ping for completed trip 01'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO location_ping (trip_id, latitude, longitude, recorded_at) VALUES ('eeeeeeee-0000-0000-0000-000000000001', 6.45, 3.39, now());
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E11 validation_failed (database backstop): latitude 95 on started trip 12; accuracy -1'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO location_ping (trip_id, latitude, longitude, recorded_at) VALUES ('eeeeeeee-0000-0000-0000-000000000012', 95, 3.39, now());
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at) VALUES ('eeeeeeee-0000-0000-0000-000000000012', 6.45, 3.39, -1, now());
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E12 payment_already_exists: rider 3 pays trip 03 again (a pending fare payment exists)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('eeeeeeee-0000-0000-0000-000000000003','fare',150000,'NGN','PRV-T03-DUP');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E13 trip_not_payable: rider 2 pays trip 12 (started)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000002',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('eeeeeeee-0000-0000-0000-000000000012','fare',100000,'NGN','PRV-T12-X');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E14 nothing_to_pay: rider 1 pays a cancellation fee for trip 05 (cancelled, fee 0)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000001',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('eeeeeeee-0000-0000-0000-000000000005','cancellation_fee',50000,'NGN','PRV-T05-X');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E15 internal: a wrong amount (the API computes the amount, so this means an API bug)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('eeeeeeee-0000-0000-0000-000000000003','fare',1,'NGN','PRV-T03-WRONG');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E16 payment_final: the provider tries to fail payment PRV-T01-A that already succeeded'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
UPDATE payment SET status='failed', failure_reason='late failure' WHERE provider_reference='PRV-T01-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E17 payment_proof_missing: support fails pending payment PRV-T03-A with no payment_not_found event'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE payment SET status='failed', failure_reason='support: no record' WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E18 internal: support marks a pending payment succeeded (no such move exists; the API has no endpoint for it)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE payment SET status='succeeded', paid_at=now() WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E19 refund_exceeds_payment: refund 250000 when 50000 of 250000 is already refunded'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 250000, 'NGN', 'too much', 'dddddddd-0000-0000-0000-000000000001', 'RF-X-1' FROM payment WHERE provider_reference='PRV-T01-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E20 payment_not_succeeded: refund against pending payment PRV-T03-A'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 100, 'NGN', 'x', 'dddddddd-0000-0000-0000-000000000001', 'RF-X-2' FROM payment WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E21 refund_already_recorded: a refund with the provider reference RF-T01-A again (small amount so the total rule passes)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 1, 'NGN', 'duplicate', 'dddddddd-0000-0000-0000-000000000001', 'RF-T01-A' FROM payment WHERE provider_reference='PRV-T01-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E22 already_rated: rider 2 rates trip 02 a second time'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000002',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000002','rider',1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E23 trip_not_completed: rider 2 rates trip 12 (started)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000002',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000012','rider',5);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E24 rating_window_closed: the window set to 0 days by support inside the test, then rider 3 rates completed trip 03'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value = 0 WHERE key = 'rating_window_days' RETURNING key, int_value;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003','rider',5);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E25a validation_failed (database backstop): stars 6'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003','rider',6);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E25b validation_failed (database backstop): a comment of 501 characters'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO rating (trip_id, rater_role, stars, comment) VALUES ('eeeeeeee-0000-0000-0000-000000000003','rider',5,repeat('x',501));
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E26 person_has_active_trip: erase_rider for rider 2 (active trip 12)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000002');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E26b person_has_active_trip: erase_driver for driver 3 (active trip 10)'
BEGIN; SET ROLE ridehail_app;
SELECT erase_driver('bbbbbbbb-0000-0000-0000-000000000003');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E27 not_found: erase_rider for an id that does not exist'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT erase_rider('00000000-0000-0000-0000-0000000000ff');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E28a validation_failed (database backstop): setting value -1'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value = -1 WHERE key = 'cancellation_fee_minor';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E28b validation_failed (database backstop): a _minor key with no currency'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES ('base_fare_minor', 50000, NULL, 'x', 'dddddddd-0000-0000-0000-000000000001');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E28c validation_failed (database backstop): currency USD'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES ('base_fare_minor', 50000, 'USD', 'x', 'dddddddd-0000-0000-0000-000000000001');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E28d the setting UPSERT the API uses works: INSERT ... ON CONFLICT (key) DO UPDATE as support (new key, then existing key)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES ('base_fare_minor', 50000, 'NGN', 'Base fare in kobo', 'dddddddd-0000-0000-0000-000000000001')
ON CONFLICT (key) DO UPDATE SET int_value = EXCLUDED.int_value, updated_by_admin_id = EXCLUDED.updated_by_admin_id RETURNING key, int_value, currency;
INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES ('cancellation_fee_minor', 60000, 'NGN', 'Fee', 'dddddddd-0000-0000-0000-000000000001')
ON CONFLICT (key) DO UPDATE SET int_value = EXCLUDED.int_value, updated_by_admin_id = EXCLUDED.updated_by_admin_id RETURNING key, int_value, currency;
SELECT actor_role, action, details FROM audit_log WHERE entity_type = 'setting' ORDER BY created_at DESC, id LIMIT 2;
ROLLBACK;

\echo '=== E29 internal: a setting change claimed by a rider (the API only lets support call it)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value = 1 WHERE key = 'rating_window_days';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E30a validation_failed: add_support_note with an empty note'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000002',true);
SELECT add_support_note('trip','eeeeeeee-0000-0000-0000-000000000001','   ');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E30b validation_failed (database backstop): an entity_type that is not allowed'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000002',true);
SELECT add_support_note('invoice','eeeeeeee-0000-0000-0000-000000000001','note');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E30c validation_failed (database backstop): no entity_id for a trip note'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000002',true);
SELECT add_support_note('trip', NULL, 'note');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E30d internal: add_support_note claimed by a rider'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000001',true);
SELECT add_support_note('trip','eeeeeeee-0000-0000-0000-000000000001','x');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E30e the note works for support (returns the new id, one audit row)'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000002',true);
SELECT add_support_note('trip','eeeeeeee-0000-0000-0000-000000000001','Dispute: rider says the route was long') IS NOT NULL AS note_written;
SELECT actor_role, action, entity_type, note FROM audit_log WHERE action='dispute_note';
ROLLBACK;

\echo '=== E31a idempotency: the same rider, action and key inserted twice (key req-0001 exists in seed A for rider 1)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','request_trip','req-0001',repeat('a',64),now()+interval '24 hours');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E31b the replay path: INSERT ... ON CONFLICT DO NOTHING returns no row, then the stored answer is read'
BEGIN; SET ROLE ridehail_app;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','request_trip','req-0001',repeat('a',64),now()+interval '24 hours')
ON CONFLICT (rider_id, action, key) DO NOTHING RETURNING id;
SELECT response_status, response_body, (request_hash = md5('request-eeeeeeee-0000-0000-0000-000000000001') || md5('eeeeeeee-0000-0000-0000-000000000001')) AS stored_hash_matches_the_seed_formula, trip_id IS NOT NULL AS has_trip
FROM idempotency_key WHERE rider_id='aaaaaaaa-0000-0000-0000-000000000001' AND action='request_trip' AND key='req-0001';
ROLLBACK;
\echo '=== E31c the same key under another action, and under another rider, is accepted (unique per rider AND action)'
BEGIN; SET ROLE ridehail_app;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','pay_trip','req-0001',repeat('b',64),now()+interval '24 hours') RETURNING action, key;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000003','request_trip','req-0001',repeat('c',64),now()+interval '24 hours') RETURNING right(rider_id::text,1) AS rider, action, key;
ROLLBACK;
\echo '=== E31d the in-flight row of seed A (key req-in-flight): response not stored yet'
BEGIN; SET ROLE ridehail_app;
SELECT key, response_status IS NULL AS first_request_still_running, expires_at > now() AS not_expired FROM idempotency_key WHERE key = 'req-in-flight';
ROLLBACK;

\echo '=== E32a invalid_idempotency_key (database backstop): empty key; E32b 129 characters; E32c bad hash'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','request_trip','',repeat('a',64),now()+interval '24 hours');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','request_trip',repeat('k',129),repeat('a',64),now()+interval '24 hours');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','request_trip','k1','NOT-A-HASH',now()+interval '24 hours');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E33a webhook: the same provider_event_id twice (evt-pay-t01 exists)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency) VALUES ('evt-pay-t01','PRV-T01-A','payment_succeeded',250000,'NGN');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E33b the webhook path: ON CONFLICT DO NOTHING returns no row for a repeated event id'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency) VALUES ('evt-pay-t01','PRV-T01-A','payment_succeeded',250000,'NGN') ON CONFLICT (provider_event_id) DO NOTHING RETURNING id;
ROLLBACK;
\echo '=== E33c invalid_event (database backstop): an event type the provider may not send as a webhook value'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type) VALUES ('evt-bad-1','PRV-X','payment_pending');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E33d invalid_event (database backstop): an amount with no currency'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor) VALUES ('evt-bad-2','PRV-X','payment_succeeded',100);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== E33e the webhook applies a success to the pending payment and records the event (the happy path of 03 section 4a)'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency, occurred_at) VALUES ('evt-hook-ok','PRV-T03-A','payment_succeeded',150000,'NGN',now()) ON CONFLICT (provider_event_id) DO NOTHING RETURNING provider_event_id;
UPDATE payment SET status='succeeded', paid_at=now() WHERE provider_reference='PRV-T03-A' AND status='pending' RETURNING provider_reference, status;
UPDATE provider_event SET processed_at=now(), outcome='applied' WHERE provider_event_id='evt-hook-ok' RETURNING provider_event_id, outcome;
ROLLBACK;

\echo '=== E34 internal: an update to a received field of a provider_event; E35 internal: processing an event twice'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
UPDATE provider_event SET provider_reference='OTHER' WHERE provider_event_id='evt-pay-t01';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E36 internal: a direct INSERT into trip_status_history, and into audit_log (the API role has no INSERT)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO trip_status_history (trip_id, from_status, to_status, actor_role, actor_rider_id) VALUES ('eeeeeeee-0000-0000-0000-000000000001', NULL, 'requested', 'rider', 'aaaaaaaa-0000-0000-0000-000000000001');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E37 internal: the actor claimed for a trip insert is not the trip rider'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003001',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000d5','10000000-0000-0000-0000-000000003000',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000d5','p','d');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E38 internal: driver 4 moves driver 3 trip 10 (the API compares trip.driver_id with the caller first, so this means an API bug)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
UPDATE trip SET status='arrived' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E39 internal: driver_id changed after it was set (an accept without the status guard)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
UPDATE trip SET status='assigned', driver_id='bbbbbbbb-0000-0000-0000-000000000004', vehicle_id='cccccccc-0000-0000-0000-000000000004' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E40 internal: assign with no vehicle'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000001',true);
UPDATE trip SET status='assigned', driver_id='bbbbbbbb-0000-0000-0000-000000000001' WHERE id='eeeeeeee-0000-0000-0000-000000000009';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E41 internal: a column that does not belong to the move (pickup_address changed together with the move to arrived)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000003',true);
UPDATE trip SET status='arrived', pickup_address='changed' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E42 complete without the facts: completed needs fare, currency and distance (the API always sets them; the check is the backstop)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000005',true);
UPDATE trip SET status='completed' WHERE id='eeeeeeee-0000-0000-0000-000000000012';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== E43 the support cancel from started, and the rider cancel fee, work as the contract says (fee shown)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000012' RETURNING status, cancelled_by_role, cancellation_fee_minor, cancellation_fee_currency;
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000004',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010' RETURNING status, cancelled_by_role, cancellation_fee_minor, cancellation_fee_currency;
ROLLBACK;
