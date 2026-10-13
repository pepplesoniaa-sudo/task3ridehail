-- PROOFS on the SMALL set (seed A). Every proof runs after SET ROLE ridehail_app, never as the dev login,
-- and prints current_user. Each proof is its own BEGIN ... ROLLBACK, so nothing is kept.
-- Run with: psql (no ON_ERROR_STOP): a refused statement aborts its transaction, ROLLBACK ends it.
-- SHOW_CONTEXT always makes a trigger error name the PL/pgSQL function (= the trigger) that raised it.
\set SHOW_CONTEXT always
\set VERBOSITY default

\echo '=================== THE THREE REJECTED INSERTS ==================='

\echo '--- 1. B1: rider 5 already has an active trip (trip 09, requested) and requests another'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000005', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('ffffffff-0000-0000-0000-0000000000a1', 'aaaaaaaa-0000-0000-0000-000000000005', 6.45, 3.39, 6.50, 3.35,
        5000, 900, 120000, 'NGN', now() + interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('aaaaaaaa-0000-0000-0000-000000000005', 'ffffffff-0000-0000-0000-0000000000a1', 'Second pickup', 'Second dropoff');
ROLLBACK;

\echo '--- 2a. B7: rating on a trip that is not completed (trip 12 is started), by its rider'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000002', true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000012', 'rider', 5);
ROLLBACK;

\echo '--- 2b. B7: a second rating by the same side (rider 1 already rated trip 01)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'rider', 1);
ROLLBACK;

\echo '--- 3a. B3: payment with currency USD for trip 01 (rider 1, correct amount 250000)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'fare', 250000, 'USD', 'PRV-PROOF-USD');
ROLLBACK;

\echo '--- 3b. B3: payment with a negative amount (-5) for trip 01'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'fare', -5, 'NGN', 'PRV-PROOF-NEG');
ROLLBACK;

\echo '=================== EXTRA PROOFS ==================='

\echo '--- X1. B4: edit the fare of completed trip 01 (as driver 1)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000001', true);
UPDATE trip SET fare_amount_minor = 1 WHERE id = 'eeeeeeee-0000-0000-0000-000000000001';
ROLLBACK;

\echo '--- X2. F9: driver 4 moves driver 3''s assigned trip 10 to arrived'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000004', true);
UPDATE trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010';
ROLLBACK;

\echo '--- X3a. U4: a provider callback repeated, plain INSERT (evt-pay-t01 already stored)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ('evt-pay-t01', 'PRV-T01-A', 'payment_succeeded', 250000, 'NGN');
ROLLBACK;

\echo '--- X3b. U4: the same callback with ON CONFLICT DO NOTHING (expect INSERT 0 0), then count rows for that id'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ('evt-pay-t01', 'PRV-T01-A', 'payment_succeeded', 250000, 'NGN')
ON CONFLICT (provider_event_id) DO NOTHING RETURNING id;
SELECT count(*) AS rows_for_evt_pay_t01 FROM provider_event WHERE provider_event_id = 'evt-pay-t01';
ROLLBACK;

\echo '--- X4a. B10: refund up to the payment amount is accepted (200000 more; 50000 already refunded of 250000)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 200000, 'NGN', 'proof: exactly the rest', 'dddddddd-0000-0000-0000-000000000001', 'RF-PROOF-1'
FROM payment WHERE provider_reference = 'PRV-T01-A';
SELECT sum(amount_minor) AS refunded_total, (SELECT amount_minor FROM payment WHERE provider_reference = 'PRV-T01-A') AS payment_amount
FROM refund WHERE payment_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T01-A');
ROLLBACK;

\echo '--- X4b. B10: a refund above the payment amount (250000 more when 50000 is already refunded)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 250000, 'NGN', 'proof: too much', 'dddddddd-0000-0000-0000-000000000001', 'RF-PROOF-2'
FROM payment WHERE provider_reference = 'PRV-T01-A';
ROLLBACK;

\echo '--- X5a. P3 WITHOUT proof: support fails pending payment PRV-T03-A, no payment_not_found event'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE payment SET status = 'failed', failure_reason = 'support: no record' WHERE provider_reference = 'PRV-T03-A';
ROLLBACK;

\echo '--- X5b. P3 WITH proof: a payment_not_found event for PRV-T03-A is stored, then support fails the payment'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome)
VALUES ('evt-nf-t03', 'PRV-T03-A', 'payment_not_found', now(), 'needs_support');
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE payment SET status = 'failed', failure_reason = 'support: provider has no record' WHERE provider_reference = 'PRV-T03-A';
SELECT provider_reference, status, failure_reason FROM payment WHERE provider_reference = 'PRV-T03-A';
SELECT actor_role, action, entity_type, details FROM audit_log WHERE entity_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T03-A') ORDER BY created_at;
ROLLBACK;

\echo '--- X5c. P3 with a SUPERSEDED proof: a later payment_succeeded event arrived after the payment_not_found event'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome)
VALUES ('evt-nf-t03', 'PRV-T03-A', 'payment_not_found', now(), 'needs_support');
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ('evt-late-ok-t03', 'PRV-T03-A', 'payment_succeeded', 150000, 'NGN');
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
UPDATE payment SET status = 'failed', failure_reason = 'support: provider has no record' WHERE provider_reference = 'PRV-T03-A';
ROLLBACK;

\echo '--- X6a. Erasure BY FUNCTION: erase_rider(rider 1) as ridehail_app (rider 1 has only terminal trips)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000001');
RESET ROLE;
SELECT full_name, phone, email, deleted_at IS NOT NULL AS deleted FROM rider WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT right(id::text, 2) AS trip, status, pickup_address, dropoff_address, fare_amount_minor FROM trip WHERE rider_id = 'aaaaaaaa-0000-0000-0000-000000000001' ORDER BY id;
SELECT rater_role, stars, comment FROM rating WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000001' ORDER BY rater_role;
ROLLBACK;

\echo '--- X6b. DIRECT erase refused: ridehail_app updates pickup_address of completed trip 01'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
UPDATE trip SET pickup_address = 'erased' WHERE id = 'eeeeeeee-0000-0000-0000-000000000001';
ROLLBACK;

\echo '--- X6c. DIRECT comment blanking refused: ridehail_app updates a rating comment'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
UPDATE rating SET comment = NULL WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000001';
ROLLBACK;

\echo '--- X6d. erase_rider refused for a rider with an active trip (rider 2, trip 12 started)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000002');
ROLLBACK;

\echo '--- X6e. erase_driver(driver 1) as ridehail_app (driver 1 has only terminal trips)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT erase_driver('bbbbbbbb-0000-0000-0000-000000000001');
RESET ROLE;
SELECT full_name, phone, licence_number, deleted_at IS NOT NULL AS deleted FROM driver WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001';
SELECT plate_number, is_active, deleted_at IS NOT NULL AS deleted FROM vehicle WHERE driver_id = 'bbbbbbbb-0000-0000-0000-000000000001';
SELECT right(id::text, 2) AS trip, driver_name_snapshot, vehicle_plate_snapshot, fare_amount_minor FROM trip WHERE driver_id = 'bbbbbbbb-0000-0000-0000-000000000001' ORDER BY id;
ROLLBACK;

\echo '--- X6f. a role with no grant cannot call the erasure function (SET ROLE to a role that has no EXECUTE: the dev login is a superuser, so use an unprivileged role created and dropped inside this transaction)'
BEGIN;
CREATE ROLE ridehail_proof_nogrant NOLOGIN;
SET ROLE ridehail_proof_nogrant;
SELECT current_user, session_user;
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000003');
ROLLBACK;

\echo '--- nothing left behind'
SELECT (SELECT count(*) FROM pg_roles WHERE rolname = 'ridehail_proof_nogrant') AS proof_roles_left,
       (SELECT count(*) FROM trip) AS trips, (SELECT count(*) FROM payment) AS payments,
       (SELECT count(*) FROM refund) AS refunds, (SELECT count(*) FROM provider_event) AS events,
       (SELECT full_name FROM rider WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001') AS rider1_name;
