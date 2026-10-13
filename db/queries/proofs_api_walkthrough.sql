-- API PART A: the contract's SQL sequence for A1 to A5 end to end, then the three scheduled jobs. ONE transaction, rolled back. As ridehail_app.
-- Rider 10000000-...-003000 (no active trip), driver 20000000-...-000400 with vehicle 30000000-...-000400, support admin dddddddd-...-001.
-- The set_config calls are exactly what the API sends first in every request (transaction-local).
\set VERBOSITY default
\set SHOW_CONTEXT never
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '--- A1 request: idempotency row first, then the quote ownership check, then the trip, then the stored response (one transaction)'
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('50000000-0000-0000-0000-0000000f0001','10000000-0000-0000-0000-000000003000',6.485,3.395,6.52,3.36,6500,1100,135000,'NGN',now()+interval '10 minutes')
RETURNING id, amount_minor, currency, expires_at > now() AS still_valid;
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at)
VALUES ('10000000-0000-0000-0000-000000003000','request_trip','walk-key-1',repeat('e',64),now()+interval '24 hours')
ON CONFLICT (rider_id, action, key) DO NOTHING RETURNING id IS NOT NULL AS first_request;
SELECT id AS quote_id FROM fare_quote WHERE id='50000000-0000-0000-0000-0000000f0001' AND rider_id='10000000-0000-0000-0000-000000003000';
INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('90000000-0000-0000-0000-0000000f0001','10000000-0000-0000-0000-000000003000','50000000-0000-0000-0000-0000000f0001','12 Admiralty Way, Lekki','5 Allen Avenue, Ikeja')
RETURNING id, status, rider_id;
UPDATE idempotency_key SET response_status = 201, response_body = jsonb_build_object('id','90000000-0000-0000-0000-0000000f0001','status','requested'), trip_id = '90000000-0000-0000-0000-0000000f0001'
WHERE rider_id='10000000-0000-0000-0000-000000003000' AND action='request_trip' AND key='walk-key-1' RETURNING response_status, trip_id IS NOT NULL AS has_trip;

\echo '--- the retry with the same key: the insert returns no row, the stored answer is read (replay)'
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at)
VALUES ('10000000-0000-0000-0000-000000003000','request_trip','walk-key-1',repeat('e',64),now()+interval '24 hours')
ON CONFLICT (rider_id, action, key) DO NOTHING RETURNING id;
SELECT response_status, response_body, request_hash = repeat('e',64) AS same_body FROM idempotency_key WHERE rider_id='10000000-0000-0000-0000-000000003000' AND action='request_trip' AND key='walk-key-1';

\echo '--- A2 driver lists open requests (rectangle), then accepts with the guarded update'
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','20000000-0000-0000-0000-000000000400',true);
SELECT t.id, t.pickup_address FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id
WHERE t.status='requested' AND q.pickup_latitude BETWEEN 6.475 AND 6.495 AND q.pickup_longitude BETWEEN 3.385 AND 3.405 AND t.id = '90000000-0000-0000-0000-0000000f0001';
SELECT id AS the_drivers_active_vehicle FROM vehicle WHERE driver_id='20000000-0000-0000-0000-000000000400' AND is_active AND deleted_at IS NULL;
UPDATE trip SET status='assigned', driver_id='20000000-0000-0000-0000-000000000400', vehicle_id='30000000-0000-0000-0000-000000000400'
WHERE id='90000000-0000-0000-0000-0000000f0001' AND status='requested' RETURNING status, driver_name_snapshot, vehicle_plate_snapshot;
\echo '--- the driver retries the accept: zero rows, then the classification query says "already mine" (state-based replay)'
UPDATE trip SET status='assigned', driver_id='20000000-0000-0000-0000-000000000400', vehicle_id='30000000-0000-0000-0000-000000000400'
WHERE id='90000000-0000-0000-0000-0000000f0001' AND status='requested';
SELECT status, driver_id = '20000000-0000-0000-0000-000000000400' AS assigned_to_the_caller FROM trip WHERE id='90000000-0000-0000-0000-0000000f0001';

\echo '--- A3 ping while assigned, then arrived, started, ping, complete (fare comes from the quote, never from the client)'
INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at) SELECT id, 6.480, 3.390, 8, now() FROM trip WHERE id='90000000-0000-0000-0000-0000000f0001' AND driver_id='20000000-0000-0000-0000-000000000400' RETURNING id IS NOT NULL AS ping_stored;
UPDATE trip SET status='arrived' WHERE id='90000000-0000-0000-0000-0000000f0001' AND driver_id='20000000-0000-0000-0000-000000000400' AND status='assigned' RETURNING status;
UPDATE trip SET status='started' WHERE id='90000000-0000-0000-0000-0000000f0001' AND driver_id='20000000-0000-0000-0000-000000000400' AND status='arrived' RETURNING status, started_at IS NOT NULL AS has_started_at;
UPDATE trip t SET status='completed', fare_amount_minor = q.amount_minor, fare_currency = 'NGN', distance_m = 6820
FROM fare_quote q WHERE t.id='90000000-0000-0000-0000-0000000f0001' AND q.id = t.fare_quote_id AND t.driver_id='20000000-0000-0000-0000-000000000400' AND t.status='started'
RETURNING t.status, t.fare_amount_minor, t.fare_currency, t.distance_m, t.completed_at IS NOT NULL AS has_completed_at;

\echo '--- the rider watches: latest location (only while the trip is in progress; here it is already completed, so the API would answer trip_not_in_progress)'
SELECT status IN ('assigned','arrived','started') AS in_progress FROM trip WHERE id='90000000-0000-0000-0000-0000000f0001';

\echo '--- A4 pay: the amount comes from the trip, the payment row is created after the provider returned its reference, pending'
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
SELECT id, status, fare_amount_minor, cancellation_fee_minor FROM trip WHERE id='90000000-0000-0000-0000-0000000f0001' AND rider_id='10000000-0000-0000-0000-000000003000';
INSERT INTO payment (id, trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('90000000-0000-0000-0000-0000000f00a1','90000000-0000-0000-0000-0000000f0001','fare',135000,'NGN','PRV-WALK-1') RETURNING id, status, amount_minor;
\echo '--- the provider webhook: record the event, apply it, mark it processed'
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency, occurred_at) VALUES ('evt-walk-1','PRV-WALK-1','payment_succeeded',135000,'NGN',now()) ON CONFLICT (provider_event_id) DO NOTHING RETURNING provider_event_id;
SELECT id, status, amount_minor FROM payment WHERE provider_reference='PRV-WALK-1';
UPDATE payment SET status='succeeded', paid_at=now() WHERE provider_reference='PRV-WALK-1' AND status='pending' RETURNING provider_reference, status;
UPDATE provider_event SET processed_at=now(), outcome='applied' WHERE provider_event_id='evt-walk-1' RETURNING outcome;
\echo '--- the same webhook delivered again: no row, nothing changes'
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency) VALUES ('evt-walk-1','PRV-WALK-1','payment_succeeded',135000,'NGN') ON CONFLICT (provider_event_id) DO NOTHING RETURNING provider_event_id;

\echo '--- A5 both sides rate (the role decides rater_role, never the body)'
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);
INSERT INTO rating (trip_id, rater_role, stars, comment) VALUES ('90000000-0000-0000-0000-0000000f0001','rider',5,'Smooth ride') RETURNING rater_role, stars;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','20000000-0000-0000-0000-000000000400',true);
INSERT INTO rating (trip_id, rater_role, stars) VALUES ('90000000-0000-0000-0000-0000000f0001','driver',4) RETURNING rater_role, stars;

\echo '--- support refunds 35000 kobo (the refund row is written after the provider confirmed RF-WALK-1)'
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
VALUES ('90000000-0000-0000-0000-0000000f00a1',35000,'NGN','Long route','dddddddd-0000-0000-0000-000000000001','RF-WALK-1') RETURNING amount_minor, currency;
SELECT add_support_note('trip','90000000-0000-0000-0000-0000000f0001','Refund of 35000 kobo agreed') IS NOT NULL AS note_written;

\echo '--- what the status-history endpoint returns for this trip (ORDER BY seq)'
SELECT seq IS NOT NULL AS has_seq, coalesce(from_status,'(new)')||' > '||to_status AS move, actor_role FROM trip_status_history WHERE trip_id='90000000-0000-0000-0000-0000000f0001' ORDER BY seq;
SELECT actor_role, action, entity_type FROM audit_log WHERE (entity_type='payment' AND entity_id='90000000-0000-0000-0000-0000000f00a1') OR (entity_type='trip' AND entity_id='90000000-0000-0000-0000-0000000f0001') ORDER BY created_at, action;

\echo '--- the cancel contract: rider cancels an assigned trip (fee 50000), then the replay classification'
RESET ROLE; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','aaaaaaaa-0000-0000-0000-000000000004',true);
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010' AND rider_id='aaaaaaaa-0000-0000-0000-000000000004' AND status IN ('requested','assigned','arrived','started') RETURNING status, cancelled_by_role, cancellation_fee_minor, cancellation_fee_currency;
UPDATE trip SET status='cancelled' WHERE id='eeeeeeee-0000-0000-0000-000000000010' AND rider_id='aaaaaaaa-0000-0000-0000-000000000004' AND status IN ('requested','assigned','arrived','started');
SELECT status, cancelled_by_role = 'rider' AS cancelled_by_the_caller_role FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000010';

\echo '--- J1 the request timeout job (actor system): cancel up to 3 unaccepted trips older than request_timeout_seconds'
SELECT set_config('app.actor_role','system',true), set_config('app.actor_id','',true);
SELECT int_value AS request_timeout_seconds FROM setting WHERE key='request_timeout_seconds';
WITH due AS (SELECT id FROM trip WHERE status='requested' AND created_at < now() - make_interval(secs => (SELECT int_value FROM setting WHERE key='request_timeout_seconds')::int) ORDER BY created_at LIMIT 3 FOR UPDATE SKIP LOCKED)
UPDATE trip t SET status='cancelled' FROM due WHERE t.id = due.id AND t.status='requested'
RETURNING right(t.id::text,6) AS trip, t.status, t.cancelled_by_role, t.cancellation_fee_minor;
SELECT actor_role, count(*) AS history_rows_by_system FROM trip_status_history WHERE actor_role='system' AND to_status='cancelled' AND created_at = now() GROUP BY 1;

\echo '--- J2 the reconciliation job: pending payments older than payment_reconcile_after_seconds (read only)'
SELECT id, provider_reference, status FROM payment WHERE status='pending' AND created_at < now() - make_interval(secs => (SELECT int_value FROM setting WHERE key='payment_reconcile_after_seconds')::int) ORDER BY created_at LIMIT 3;

\echo '--- J3 idempotency cleanup: delete expired rows (an expired row is created inside this transaction to prove the DELETE right)'
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at) VALUES ('10000000-0000-0000-0000-000000003000','pay_trip','expired-key',repeat('f',64),now()-interval '1 minute');
DELETE FROM idempotency_key WHERE expires_at < now();
ROLLBACK;
SELECT (SELECT count(*) FROM trip WHERE id::text LIKE '90000000%') AS proof_trips_left, (SELECT count(*) FROM idempotency_key WHERE key IN ('walk-key-1','expired-key')) AS proof_keys_left, (SELECT count(*) FROM provider_event WHERE provider_event_id='evt-walk-1') AS proof_events_left, (SELECT status FROM trip WHERE id='eeeeeeee-0000-0000-0000-000000000010') AS trip_10_status;
