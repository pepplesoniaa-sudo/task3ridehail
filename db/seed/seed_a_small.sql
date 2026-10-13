-- SEED A: SMALL set. 5 riders, 5 drivers, 5 vehicles, 2 support admins, 4 settings, 12 trips,
-- quotes, payments, a refund, ratings, history rows (written by the trigger), pings, one provider_event
-- of each type, idempotency keys.
-- Everything is inserted as ridehail_app through the real triggers. No trigger is turned off.
-- Trips are never inserted as completed: each one walks through legal moves only (docs 03 section 2).
-- Run with: psql -1 -v ON_ERROR_STOP=1  (one transaction: if any rule refuses a row, nothing is kept)
--
-- id patterns (readable on purpose):
--   rider  aaaaaaaa-0000-0000-0000-00000000000N    driver  bbbbbbbb-...    vehicle cccccccc-...
--   admin  dddddddd-...    trip eeeeeeee-...    quote ffffffff-...

SET ROLE ridehail_app;
SELECT current_user AS seeding_as, session_user AS login_session;

-- ---------------------------------------------------------------- people and staff
INSERT INTO support_admin (id, full_name, email)
SELECT ('dddddddd-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Support Admin ' || n, 'admin' || n || '@example.test'
FROM generate_series(1, 2) n;

INSERT INTO rider (id, full_name, phone, email)
SELECT ('aaaaaaaa-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Rider ' || n,
       '+23480123456' || lpad(n::text, 2, '0'), 'rider' || n || '@example.test'
FROM generate_series(1, 5) n;

INSERT INTO driver (id, full_name, phone, licence_number)
SELECT ('bbbbbbbb-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Driver ' || n,
       '+23470123456' || lpad(n::text, 2, '0'), 'LAG-DRV-' || lpad(n::text, 5, '0')
FROM generate_series(1, 5) n;

INSERT INTO vehicle (id, driver_id, plate_number, make, model, colour, seat_count)
SELECT ('cccccccc-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       ('bbbbbbbb-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'LAG-' || (100 + n) || '-AA', 'Toyota', 'Corolla', 'Silver', 4
FROM generate_series(1, 5) n;

-- ---------------------------------------------------------------- settings (placeholder values from the docs)
-- Only a support actor may change a setting (trigger setting_write_audit), so act as support admin 1.
SELECT set_config('app.actor_role', 'support', true),
       set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);
INSERT INTO setting (key, int_value, currency, description, updated_by_admin_id) VALUES
  ('cancellation_fee_minor',          50000, 'NGN', 'Flat fee in kobo when a rider cancels after assignment (B9). Placeholder, owner approved.', 'dddddddd-0000-0000-0000-000000000001'),
  ('rating_window_days',                  7, NULL,  'Days after completion in which a rating is accepted (B7).',                                  'dddddddd-0000-0000-0000-000000000001'),
  ('request_timeout_seconds',           600, NULL,  'Seconds before the system cancels an unaccepted requested trip (T9). Placeholder, needs owner approval.', 'dddddddd-0000-0000-0000-000000000001'),
  ('payment_reconcile_after_seconds',   900, NULL,  'Seconds a payment may stay pending before reconciliation (03 section 4b). Placeholder, needs owner approval.', 'dddddddd-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------- 12 trips, legal moves only
DO $seed$
DECLARE
  spec  record;
  step  text;
  rid   uuid;
  did   uuid;
  vid   uuid;
  tid   uuid;
  qid   uuid;
  admin1 uuid := 'dddddddd-0000-0000-0000-000000000001';
BEGIN
  FOR spec IN
    SELECT * FROM (VALUES
      ( 1, 1, 1, 'assign,arrive,start,complete', NULL::text, 250000),   -- completed
      ( 2, 2, 2, 'assign,arrive,start,complete', NULL,       480000),   -- completed
      ( 3, 3, 1, 'assign,arrive,start,complete', NULL,       150000),   -- completed
      ( 4, 4, 2, 'assign,cancel',                'rider',    NULL),     -- cancelled by rider after assignment: fee
      ( 5, 1, 0, 'cancel',                       'rider',    NULL),     -- cancelled by rider from requested: no fee
      ( 6, 2, 0, 'cancel',                       'system',   NULL),     -- request timeout (T9)
      ( 7, 5, 3, 'assign,arrive,cancel',         'driver',   NULL),     -- cancelled by driver from arrived
      ( 8, 3, 4, 'assign,arrive,start,cancel',   'support',  NULL),     -- cancelled by support after start
      ( 9, 5, 0, '',                             NULL,       NULL),     -- requested (active)
      (10, 4, 3, 'assign',                       NULL,       NULL),     -- assigned (active)
      (11, 3, 4, 'assign,arrive',                NULL,       NULL),     -- arrived (active)
      (12, 2, 5, 'assign,arrive,start',          NULL,       NULL)      -- started (active)
    ) AS v(n, rider_n, driver_n, steps, cancel_by, fare)
    ORDER BY n
  LOOP
    rid := ('aaaaaaaa-0000-0000-0000-' || lpad(spec.rider_n::text, 12, '0'))::uuid;
    did := CASE WHEN spec.driver_n > 0 THEN ('bbbbbbbb-0000-0000-0000-' || lpad(spec.driver_n::text, 12, '0'))::uuid END;
    vid := CASE WHEN spec.driver_n > 0 THEN ('cccccccc-0000-0000-0000-' || lpad(spec.driver_n::text, 12, '0'))::uuid END;
    tid := ('eeeeeeee-0000-0000-0000-' || lpad(spec.n::text, 12, '0'))::uuid;
    qid := ('ffffffff-0000-0000-0000-' || lpad(spec.n::text, 12, '0'))::uuid;

    -- A1: the rider asks for a quote, then requests the trip
    PERFORM set_config('app.actor_role', 'rider', true);
    PERFORM set_config('app.actor_id', rid::text, true);
    INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                            estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
    VALUES (qid, rid, 6.452000 + spec.n * 0.001, 3.390000 + spec.n * 0.001,
            6.500000 + spec.n * 0.001, 3.350000 + spec.n * 0.001,
            7000 + spec.n * 100, 1200 + spec.n * 10, 100000 + spec.n * 25000, 'NGN', now() + interval '1 hour');
    INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address)
    VALUES (tid, rid, qid, 'Pickup ' || spec.n || ', Lagos', 'Dropoff ' || spec.n || ', Lagos');

    FOREACH step IN ARRAY string_to_array(spec.steps, ',') LOOP
      CASE step
        WHEN 'assign' THEN
          PERFORM set_config('app.actor_role', 'driver', true);
          PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'assigned', driver_id = did, vehicle_id = vid WHERE id = tid;
        WHEN 'arrive' THEN
          PERFORM set_config('app.actor_role', 'driver', true);
          PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'arrived' WHERE id = tid;
          INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at)
          VALUES (tid, 6.452000 + spec.n * 0.001, 3.390000 + spec.n * 0.001, 8, now());
        WHEN 'start' THEN
          PERFORM set_config('app.actor_role', 'driver', true);
          PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'started' WHERE id = tid;
          INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at)
          VALUES (tid, 6.470000 + spec.n * 0.001, 3.370000 + spec.n * 0.001, 6, now());
        WHEN 'complete' THEN
          PERFORM set_config('app.actor_role', 'driver', true);
          PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'completed', fare_amount_minor = spec.fare, fare_currency = 'NGN',
                          distance_m = 7000 + spec.n * 100 WHERE id = tid;
        WHEN 'cancel' THEN
          PERFORM set_config('app.actor_role', spec.cancel_by, true);
          PERFORM set_config('app.actor_id',
            CASE spec.cancel_by WHEN 'rider' THEN rid::text WHEN 'driver' THEN did::text
                                WHEN 'support' THEN admin1::text ELSE '' END, true);
          UPDATE trip SET status = 'cancelled' WHERE id = tid;
        ELSE
          NULL;
      END CASE;
    END LOOP;
  END LOOP;
END
$seed$;

-- ---------------------------------------------------------------- payments, provider events, refund
DO $seed$
DECLARE
  rid1 uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  rid2 uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  rid3 uuid := 'aaaaaaaa-0000-0000-0000-000000000003';
  rid4 uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
  admin1 uuid := 'dddddddd-0000-0000-0000-000000000001';
  t1 uuid := 'eeeeeeee-0000-0000-0000-000000000001';
  t2 uuid := 'eeeeeeee-0000-0000-0000-000000000002';
  t3 uuid := 'eeeeeeee-0000-0000-0000-000000000003';
  t4 uuid := 'eeeeeeee-0000-0000-0000-000000000004';
  p1 uuid; p2a uuid; p2b uuid; p3 uuid; p4 uuid;
BEGIN
  -- trip 1: fare 250000, succeeded
  PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid1::text, true);
  INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
  VALUES (t1, 'fare', 250000, 'NGN', 'PRV-T01-A') RETURNING id INTO p1;
  PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
  INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency, occurred_at)
  VALUES ('evt-pay-t01', 'PRV-T01-A', 'payment_succeeded', 250000, 'NGN', now() - interval '1 minute');
  UPDATE payment SET status = 'succeeded', paid_at = now() WHERE id = p1;
  UPDATE provider_event SET processed_at = now(), outcome = 'applied' WHERE provider_event_id = 'evt-pay-t01';

  -- trip 2: first attempt declined, second attempt succeeds (a failed payment does not block a retry)
  PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid2::text, true);
  INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
  VALUES (t2, 'fare', 480000, 'NGN', 'PRV-T02-A') RETURNING id INTO p2a;
  PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
  INSERT INTO provider_event (provider_event_id, provider_reference, event_type, occurred_at)
  VALUES ('evt-pay-t02a', 'PRV-T02-A', 'payment_failed', now() - interval '2 minutes');
  UPDATE payment SET status = 'failed', failure_reason = 'card declined' WHERE id = p2a;
  UPDATE provider_event SET processed_at = now(), outcome = 'applied' WHERE provider_event_id = 'evt-pay-t02a';
  PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid2::text, true);
  INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
  VALUES (t2, 'fare', 480000, 'NGN', 'PRV-T02-B') RETURNING id INTO p2b;
  PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
  INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
  VALUES ('evt-pay-t02b', 'PRV-T02-B', 'payment_succeeded', 480000, 'NGN');
  UPDATE payment SET status = 'succeeded', paid_at = now() WHERE id = p2b;
  UPDATE provider_event SET processed_at = now(), outcome = 'applied' WHERE provider_event_id = 'evt-pay-t02b';

  -- trip 3: fare 150000, left PENDING (a stuck payment: used by the P3 proofs, no provider event yet)
  PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid3::text, true);
  INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
  VALUES (t3, 'fare', 150000, 'NGN', 'PRV-T03-A') RETURNING id INTO p3;

  -- trip 4: rider cancelled after assignment, so the 50000 kobo fee is paid
  PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid4::text, true);
  INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
  VALUES (t4, 'cancellation_fee', 50000, 'NGN', 'PRV-T04-A') RETURNING id INTO p4;
  PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
  UPDATE payment SET status = 'succeeded', paid_at = now() WHERE id = p4;

  -- refund of 50000 kobo against trip 1's payment (partial), by support, plus the provider's refund_succeeded event
  PERFORM set_config('app.actor_role', 'support', true); PERFORM set_config('app.actor_id', admin1::text, true);
  INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
  VALUES (p1, 50000, 'NGN', 'Rider complaint: long route', admin1, 'RF-T01-A');
  PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
  INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency,
                              processed_at, outcome)
  VALUES ('evt-rf-t01', 'RF-T01-A', 'refund_succeeded', 50000, 'NGN', now(), 'applied');

  -- a "no record" answer about a reference we do not know: stored and flagged for support
  -- (the audit row for it uses entity_type provider_event, see the Stage 3 report)
  INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome)
  VALUES ('evt-nf-unknown', 'PRV-UNKNOWN', 'payment_not_found', now(), 'needs_support');
END
$seed$;

-- ---------------------------------------------------------------- ratings (the cache trigger updates the totals)
DO $seed$
BEGIN
  PERFORM set_config('app.actor_role', 'rider', true);
  PERFORM set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000001', true);
  INSERT INTO rating (trip_id, rater_role, stars, comment)
  VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'rider', 5, 'Great driver');
  PERFORM set_config('app.actor_role', 'driver', true);
  PERFORM set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000001', true);
  INSERT INTO rating (trip_id, rater_role, stars, comment)
  VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'driver', 4, 'Polite rider');
  PERFORM set_config('app.actor_role', 'rider', true);
  PERFORM set_config('app.actor_id', 'aaaaaaaa-0000-0000-0000-000000000002', true);
  INSERT INTO rating (trip_id, rater_role, stars)
  VALUES ('eeeeeeee-0000-0000-0000-000000000002', 'rider', 3);
  PERFORM set_config('app.actor_role', 'driver', true);
  PERFORM set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000001', true);
  INSERT INTO rating (trip_id, rater_role, stars)
  VALUES ('eeeeeeee-0000-0000-0000-000000000003', 'driver', 5);
END
$seed$;

-- ---------------------------------------------------------------- idempotency keys (B6)
INSERT INTO idempotency_key (rider_id, action, key, request_hash, response_status, response_body, trip_id, payment_id, expires_at)
SELECT t.rider_id, 'request_trip', 'req-' || right(t.id::text, 4),
       md5('request-' || t.id::text) || md5(t.id::text), 201,
       jsonb_build_object('trip_id', t.id, 'status', 'requested'), t.id, NULL, now() + interval '24 hours'
FROM trip t WHERE t.id IN ('eeeeeeee-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000002',
                           'eeeeeeee-0000-0000-0000-000000000010');
INSERT INTO idempotency_key (rider_id, action, key, request_hash, response_status, response_body, trip_id, payment_id, expires_at)
SELECT t.rider_id, 'pay_trip', 'pay-' || right(p.id::text, 4),
       md5('pay-' || p.id::text) || md5(p.id::text), 201,
       jsonb_build_object('payment_id', p.id, 'status', p.status), t.id, p.id, now() + interval '24 hours'
FROM payment p JOIN trip t ON t.id = p.trip_id WHERE p.provider_reference IN ('PRV-T01-A', 'PRV-T02-B');
-- one key whose first request has not finished yet (no stored response)
INSERT INTO idempotency_key (rider_id, action, key, request_hash, expires_at)
VALUES ('aaaaaaaa-0000-0000-0000-000000000005', 'request_trip', 'req-in-flight',
        md5('in-flight') || md5('flight'), now() + interval '24 hours');

RESET ROLE;
