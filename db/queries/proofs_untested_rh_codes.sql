-- STAGE 4 PART A CLOSE: raise the 20 RH codes that no earlier test raised (RH002 RH003 RH007 RH009 RH011 RH013 RH014 RH016 RH020 RH021
-- RH025 RH029 RH031 RH033 RH040 RH042 RH044 RH045 RH051 RH080). Every test is its own BEGIN ... ROLLBACK, as ridehail_app, current_user printed.
-- Setups that the application role cannot do (delete a setting, add a rule row) are done by the dev login INSIDE the rolled-back transaction
-- and are labelled SETUP; the statement under test always runs after SET ROLE ridehail_app. A statement stopped by a privilege (42501)
-- is shown, and the same statement is then run by the dev login (a superuser still fires triggers) to show the code is live.
-- Seed A ids: trip eeeeeeee-...-0000000000NN, riders aaaaaaaa-...-0000000000NN, drivers bbbbbbbb-..., support admin dddddddd-...-000000000001.
\set VERBOSITY default
\set SHOW_CONTEXT never

\echo '=== U-RH002 a new trip must start as requested: rider 3000 inserts a trip with status assigned'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000f1','10000000-0000-0000-0000-000000003000',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address, status) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000f1','p','d','assigned');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH003 a new trip cannot carry start, end or cancel times: started_at set on insert'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000f2','10000000-0000-0000-0000-000000003000',6.45,3.39,6.50,3.35,5000,900,120000,'NGN',now()+interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address, started_at) VALUES ('10000000-0000-0000-0000-000000003000','ffffffff-0000-0000-0000-0000000000f2','p','d',now());
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH007a actor role not set (trip): a move with no claim at all'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
UPDATE trip SET status='arrived' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH007b actor role not set (payment): fail a pending payment with no claim'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
UPDATE payment SET status='failed', failure_reason='x' WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH009 actor is not this trip rider: rider 1 cancels the assigned trip 10 of rider 4'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000001',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH011a support actor id required (trip): support claim with an empty id cancels trip 10'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH011b support actor id required (payment): support claim with an empty id fails pending payment PRV-T03-A'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','',true);
UPDATE payment SET status='failed', failure_reason='x' WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH013 cancellation fee setting missing. SETUP by the dev login: delete the row (the app role has no DELETE on setting). Then rider 4 cancels assigned trip 10 as ridehail_app'
BEGIN; SELECT current_user AS setup_user;
DELETE FROM setting WHERE key='cancellation_fee_minor';
SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000004',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH013b the app role cannot create that state: DELETE on setting as ridehail_app'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
DELETE FROM setting WHERE key='cancellation_fee_minor';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH014a unexpected target status: which target statuses do the trip rule rows allow? (expect only arrived assigned cancelled completed started)'
SELECT string_agg(DISTINCT to_status, ' ' ORDER BY to_status) AS trip_rule_targets FROM status_transition_rule WHERE entity='trip';
\echo '=== U-RH014b the app role cannot add a rule row (INSERT on status_transition_rule as ridehail_app)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
INSERT INTO status_transition_rule (entity, from_status, to_status, actor_role) VALUES ('trip','assigned','requested','rider');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH014c SETUP by the dev login: add a rule row assigned -> requested for riders. Then rider 4 makes that move as ridehail_app'
BEGIN; SELECT current_user AS setup_user;
INSERT INTO status_transition_rule (entity, from_status, to_status, actor_role) VALUES ('trip','assigned','requested','rider');
SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000004',true);
UPDATE trip SET status='requested' WHERE id='eeeeeeee-0000-0000-0000-000000000010';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH016a trips are never deleted: DELETE FROM trip as ridehail_app'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
DELETE FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000009';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH016b the same DELETE by the dev login (superuser): the trigger still fires'
BEGIN; SELECT current_user AS cu;
DELETE FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000009';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH020 a payment must be created as pending: insert with status succeeded'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000001',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference, status, paid_at)
SELECT id, 'fare', fare_amount_minor, 'NGN', 'PRV-U-020', 'succeeded', now() FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000001';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH021 only the trip rider may start a payment: rider 5 pays the fare of trip 02 (rider 2)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000005',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
SELECT id, 'fare', fare_amount_minor, 'NGN', 'PRV-U-021' FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000002';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH025 payment amount differs from the cancellation fee: trip 04 (cancelled, fee 50000), amount 1'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000004',true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
VALUES ('eeeeeeee-0000-0000-0000-000000000004','cancellation_fee',1,'NGN','PRV-U-025');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH029 payment columns may not change in this move: provider fails PRV-T03-A and also changes amount_minor'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
UPDATE payment SET status='failed', failure_reason='x', amount_minor=amount_minor+1 WHERE provider_reference='PRV-T03-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH031a provider_event rows are never deleted: DELETE as ridehail_app'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
DELETE FROM provider_event WHERE provider_event_id='evt-pay-t01';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH031b the same DELETE by the dev login (superuser)'
BEGIN; SELECT current_user AS cu;
DELETE FROM provider_event WHERE provider_event_id='evt-pay-t01';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH033 the received fields of a provider_event cannot change: an unprocessed event gets a new amount'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type) VALUES ('evt-u-033','PRV-U-033','payment_failed');
UPDATE provider_event SET amount_minor=5, currency='NGN' WHERE provider_event_id='evt-u-033';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH040a rating is append-only: UPDATE and DELETE as ridehail_app'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
UPDATE rating SET stars=1 WHERE id=(SELECT id FROM rating LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
DELETE FROM rating WHERE id=(SELECT id FROM rating LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH040b the same UPDATE by the dev login (superuser, not the erasure owner)'
BEGIN; SELECT current_user AS cu;
UPDATE rating SET stars=1 WHERE id=(SELECT id FROM rating LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH042 rating window setting missing. SETUP by the dev login: delete rating_window_days. Then rider 3 rates completed trip 03 as ridehail_app'
BEGIN; SELECT current_user AS setup_user;
DELETE FROM setting WHERE key='rating_window_days';
SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000003',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003','rider',5);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH044 the rating must come from this trip rider: support widens the window to 36500 days (as E24 did), then rider 5 rates trip 03 as rater_role rider'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value=36500 WHERE key='rating_window_days';
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000005',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003','rider',5);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH045 the rating must come from this trip driver: same, driver 4 rates trip 03 (driver 1) as rater_role driver'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value=36500 WHERE key='rating_window_days';
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000003','driver',5);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH051 refund currency differs from payment currency: refund in USD against succeeded payment PRV-T01-A'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 1000, 'USD', 'wrong currency', 'dddddddd-0000-0000-0000-000000000001', 'RF-U-051' FROM payment WHERE provider_reference='PRV-T01-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;

\echo '=== U-RH080a append-only table: UPDATE of fare_quote, refund, audit_log, trip_status_history, location_ping as ridehail_app (privilege stops each)'
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
UPDATE fare_quote SET amount_minor=amount_minor WHERE id=(SELECT id FROM fare_quote LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
UPDATE refund SET reason='x' WHERE true;
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
UPDATE audit_log SET note='x' WHERE id=(SELECT id FROM audit_log LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
UPDATE trip_status_history SET to_status=to_status WHERE id=(SELECT id FROM trip_status_history LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN; SET ROLE ridehail_app;
UPDATE location_ping SET latitude=latitude WHERE id=(SELECT id FROM location_ping LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
\echo '=== U-RH080b the same UPDATEs by the dev login (superuser): the trigger fires'
BEGIN; SELECT current_user AS cu;
UPDATE fare_quote SET amount_minor=amount_minor WHERE id=(SELECT id FROM fare_quote LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN;
UPDATE refund SET reason='x' WHERE true;
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN;
UPDATE audit_log SET note='x' WHERE id=(SELECT id FROM audit_log LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN;
UPDATE trip_status_history SET to_status=to_status WHERE id=(SELECT id FROM trip_status_history LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
BEGIN;
UPDATE location_ping SET latitude=latitude WHERE id=(SELECT id FROM location_ping LIMIT 1);
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
