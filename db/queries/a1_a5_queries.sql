-- THE FIVE QUERIES (A1 to A5): the exact queries of docs/04_hard_questions.md question 7, with real parameter
-- values taken from the BULK data (see evidence/query_parameters.txt). Run as ridehail_app.
-- Writes run inside BEGIN ... ROLLBACK so the data set stays the same for the plans.
-- Parameters:
--   A1 retry key:   rider 10000000-...-004001, key bulk-1000          new trip: rider 10000000-...-002000 (no active trip)
--   A2 position:    near lat 6.485, lon 3.395 (a requested trip is there)   driver 20000000-...-000400, vehicle 30000000-...-000400
--                   requested trip 40000000-...-199850
--   A3 trip with pings 40000000-...-000100;  assigned trip 40000000-...-199303 (driver 20000000-...-000003)
--   A4 completed trip 40000000-...-001000 (rider ...004001);  cancelled-with-fee trip 40000000-...-000090 (rider ...002711);
--      pending payment BULK-PRV-500
--   A5 completed trip without a rider rating 40000000-...-001001 (rider ...001920)
\set SHOW_CONTEXT always
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '################ A1: a rider requests a trip'
\echo '--- A1.1 retry check (idempotency key)'
SELECT response_status, response_body FROM idempotency_key
WHERE rider_id = '10000000-0000-0000-0000-000000004001' AND action = 'request_trip' AND key = 'bulk-1000';

\echo '--- A1.2 settings for fare and service area (only 4 settings exist in the placeholder set, the area and fare keys have no owner-approved value yet)'
SELECT key, int_value FROM setting WHERE key LIKE 'service_area%' OR key IN ('base_fare_minor','per_km_minor','per_minute_minor');

\echo '--- A1.3 create the quote, then the trip (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('50000000-0000-0000-0000-0000000a0001', '10000000-0000-0000-0000-000000002000', 6.485, 3.395, 6.52, 3.36,
        6500, 1100, 135000, 'NGN', now() + interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('10000000-0000-0000-0000-000000002000', '50000000-0000-0000-0000-0000000a0001', 'A1 pickup', 'A1 dropoff')
RETURNING id, status, rider_id;
ROLLBACK;

\echo '################ A2: a nearby driver accepts'
\echo '--- A2.1 open requests near the driver (rectangle of coordinates)'
SELECT t.id, t.pickup_address, q.pickup_latitude, q.pickup_longitude, q.amount_minor
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id
WHERE t.status = 'requested'
  AND q.pickup_latitude  BETWEEN 6.475 AND 6.495
  AND q.pickup_longitude BETWEEN 3.385 AND 3.405
ORDER BY t.created_at LIMIT 20;

\echo '--- A2.2 the driver''s vehicle'
SELECT id, plate_number FROM vehicle
WHERE driver_id = '20000000-0000-0000-0000-000000000400' AND is_active AND deleted_at IS NULL;

\echo '--- A2.3 accept (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', '20000000-0000-0000-0000-000000000400', true);
UPDATE trip SET status = 'assigned', driver_id = '20000000-0000-0000-0000-000000000400',
                vehicle_id = '30000000-0000-0000-0000-000000000400'
WHERE id = '40000000-0000-0000-0000-000000199850' AND status = 'requested'
RETURNING id, status, driver_name_snapshot, vehicle_plate_snapshot;
ROLLBACK;

\echo '################ A3: the rider watches, the driver moves the trip'
\echo '--- A3.1 latest driver position'
SELECT latitude, longitude, recorded_at FROM location_ping
WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY recorded_at DESC LIMIT 1;

\echo '--- A3.2 driver moves the trip, assigned to arrived (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', '20000000-0000-0000-0000-000000000003', true);
UPDATE trip SET status = 'arrived'
WHERE id = '40000000-0000-0000-0000-000000199303' AND driver_id = '20000000-0000-0000-0000-000000000003' AND status = 'assigned'
RETURNING id, status;
ROLLBACK;

\echo '--- A3.3 status timeline (ordered by seq since migration 010)'
SELECT from_status, to_status, actor_role, created_at FROM trip_status_history
WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY seq;

\echo '################ A4: the rider pays'
\echo '--- A4.1 look up the trip and what is owed'
SELECT id, status, fare_amount_minor, cancellation_fee_minor FROM trip
WHERE id = '40000000-0000-0000-0000-000000001000' AND rider_id = '10000000-0000-0000-0000-000000004001';

\echo '--- A4.2 start a cancellation-fee payment for the cancelled trip with a 50000 fee (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002711', true);
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference, status)
VALUES ('40000000-0000-0000-0000-000000000090', 'cancellation_fee', 50000, 'NGN', 'PRV-A4-PROOF', 'pending')
RETURNING id, purpose, amount_minor, status;
ROLLBACK;

\echo '--- A4.3 provider callback for pending payment BULK-PRV-500: record the event, then apply it (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ('evt-a4-proof', 'BULK-PRV-500', 'payment_succeeded', 80000, 'NGN') ON CONFLICT (provider_event_id) DO NOTHING RETURNING id;
UPDATE payment SET status = 'succeeded', paid_at = now()
WHERE provider_reference = 'BULK-PRV-500' AND status = 'pending' RETURNING provider_reference, status;
ROLLBACK;

\echo '################ A5: both sides rate'
\echo '--- A5.1 rider rates trip 001001 (rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000001920', true);
INSERT INTO rating (trip_id, rater_role, stars, comment)
VALUES ('40000000-0000-0000-0000-000000001001', 'rider', 5, 'A5 proof') RETURNING id, trip_id, rater_role, stars;
ROLLBACK;
