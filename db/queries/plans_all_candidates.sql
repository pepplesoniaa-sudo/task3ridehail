-- EXPLAIN (ANALYZE, BUFFERS) of every candidate query on the BULK set, run as ridehail_app.
-- Writes are inside BEGIN ... ROLLBACK. Run the file twice and keep the second run (warm cache).
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '=== P01 A1.1 retry check'
EXPLAIN (ANALYZE, BUFFERS) SELECT response_status, response_body FROM idempotency_key
WHERE rider_id = '10000000-0000-0000-0000-000000004001' AND action = 'request_trip' AND key = 'bulk-1000';

\echo '=== P02 A1.3 insert the trip (the trigger checks actor, quote and the one-active-trip index)'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('50000000-0000-0000-0000-0000000a0001', '10000000-0000-0000-0000-000000002000', 6.485, 3.395, 6.52, 3.36,
        6500, 1100, 135000, 'NGN', now() + interval '1 hour');
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('10000000-0000-0000-0000-000000002000', '50000000-0000-0000-0000-0000000a0001', 'A1 pickup', 'A1 dropoff');
ROLLBACK;

\echo '=== P03 A2.1 open requests near the driver'
EXPLAIN (ANALYZE, BUFFERS) SELECT t.id, t.pickup_address, q.pickup_latitude, q.pickup_longitude, q.amount_minor
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id
WHERE t.status = 'requested' AND q.pickup_latitude BETWEEN 6.475 AND 6.495 AND q.pickup_longitude BETWEEN 3.385 AND 3.405
ORDER BY t.created_at LIMIT 20;

\echo '=== P04 A2.2 the driver''s vehicle'
EXPLAIN (ANALYZE, BUFFERS) SELECT id, plate_number FROM vehicle
WHERE driver_id = '20000000-0000-0000-0000-000000000400' AND is_active AND deleted_at IS NULL;

\echo '=== P05 A2.3 accept'
BEGIN;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', '20000000-0000-0000-0000-000000000400', true);
EXPLAIN (ANALYZE, BUFFERS) UPDATE trip SET status = 'assigned', driver_id = '20000000-0000-0000-0000-000000000400',
                vehicle_id = '30000000-0000-0000-0000-000000000400'
WHERE id = '40000000-0000-0000-0000-000000199850' AND status = 'requested';
ROLLBACK;

\echo '=== P06 A3.1 latest driver position'
EXPLAIN (ANALYZE, BUFFERS) SELECT latitude, longitude, recorded_at FROM location_ping
WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY recorded_at DESC LIMIT 1;

\echo '=== P07 A3.2 driver moves the trip'
BEGIN;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', '20000000-0000-0000-0000-000000000003', true);
EXPLAIN (ANALYZE, BUFFERS) UPDATE trip SET status = 'arrived'
WHERE id = '40000000-0000-0000-0000-000000199303' AND driver_id = '20000000-0000-0000-0000-000000000003' AND status = 'assigned';
ROLLBACK;

\echo '=== P08 A3.3 status timeline'
EXPLAIN (ANALYZE, BUFFERS) SELECT from_status, to_status, actor_role, created_at FROM trip_status_history
WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY seq;

\echo '=== P09 A4.1 trip lookup'
EXPLAIN (ANALYZE, BUFFERS) SELECT id, status, fare_amount_minor, cancellation_fee_minor FROM trip
WHERE id = '40000000-0000-0000-0000-000000001000' AND rider_id = '10000000-0000-0000-0000-000000004001';

\echo '=== P10 A4.2 start a payment'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002711', true);
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference, status)
VALUES ('40000000-0000-0000-0000-000000000090', 'cancellation_fee', 50000, 'NGN', 'PRV-A4-PROOF', 'pending');
ROLLBACK;

\echo '=== P11a A4.3 callback: record the event'
BEGIN;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ('evt-a4-proof', 'BULK-PRV-500', 'payment_succeeded', 80000, 'NGN') ON CONFLICT (provider_event_id) DO NOTHING;
\echo '=== P11b A4.3 callback: apply it to the payment'
EXPLAIN (ANALYZE, BUFFERS) UPDATE payment SET status = 'succeeded', paid_at = now()
WHERE provider_reference = 'BULK-PRV-500' AND status = 'pending';
ROLLBACK;

\echo '=== P12 A5.1 rate'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000001920', true);
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO rating (trip_id, rater_role, stars, comment)
VALUES ('40000000-0000-0000-0000-000000001001', 'rider', 5, 'A5 proof');
ROLLBACK;

\echo '=== P13 history list, keyset page 1 for rider 777 (not one of A1 to A5)'
EXPLAIN (ANALYZE, BUFFERS) SELECT id, status, created_at FROM trip
WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 20;

\echo '=== P14 reconciliation job: pending payments older than 900 seconds'
EXPLAIN (ANALYZE, BUFFERS) SELECT id, provider_reference FROM payment
WHERE status = 'pending' AND created_at < now() - make_interval(secs => 900) ORDER BY created_at LIMIT 100;
