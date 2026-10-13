-- SEED B, step 1 of 2. BULK SET, FOR QUERY PLANS ONLY. One chunk of trips, row by row through the REAL triggers.
-- Why row by row: every move is checked against the claimed actor (the trip's own rider or driver), so the actor
-- must be set per row. A single UPDATE over many rows cannot do that. No trigger is turned off.
-- Usage:  psql -1 -v ON_ERROR_STOP=1 -v from=1 -v to=20000 -v mod=4 -v res=0 -f seed_b_1_trips_chunk.sql
-- mod and res let several sessions load in parallel without ever touching the same rider or driver:
-- rider_n-1 and driver_n-1 are both determined by t mod 4 (8 divides 5000 and 800, 7919 mod 4 = 3, 104729 mod 4 = 1),
-- so session res handles only the trips with t mod mod = res. Use mod=1 res=0 for one session.
-- Trip index t: see seed_b_0_people_quotes.sql. Terminal trips must be loaded BEFORE t > 199300 (the active
-- and requested trips), because a rider or driver may have only one active trip at a time (B1, B2).
-- Per completed trip: trip, 4 moves (5 history rows by trigger), payment (about 1 in 500 left pending),
-- a provider_event for 1 in 10, a rider rating for half, 3 pings for 1 in 4, an idempotency key for 1 in 5.
SET ROLE ridehail_app;
SELECT set_config('bulk.from', :'from', false), set_config('bulk.to', :'to', false),
       set_config('bulk.mod', :'mod', false), set_config('bulk.res', :'res', false);

DO $bulk$
DECLARE
  t_from bigint := current_setting('bulk.from')::bigint;
  t_to   bigint := current_setting('bulk.to')::bigint;
  t_mod  bigint := current_setting('bulk.mod')::bigint;
  t_res  bigint := current_setting('bulk.res')::bigint;
  i integer; t bigint; j bigint; rn bigint; dn bigint; m int;
  rid uuid; did uuid; vid uuid; tid uuid; qid uuid; pid uuid;
  steps text[]; step text; cancel_by text; fare bigint; created timestamptz;
  admin1 CONSTANT uuid := 'dddddddd-0000-0000-0000-000000000001';
BEGIN
  -- the FOR variable is always integer in PL/pgSQL and shadows a declared bigint, so loop on i and copy to the bigint t
  FOR i IN t_from .. t_to LOOP
    t := i;
    CONTINUE WHEN t % t_mod <> t_res;
    cancel_by := NULL; fare := NULL;
    IF t <= 199300 THEN
      rn := 1 + ((t * 7919) % 5000);  dn := 1 + ((t * 104729) % 800);  m := (t % 100)::int;
      created := now() - ((199300 - t + 1000) * interval '150 seconds');
      IF    m < 85 THEN steps := ARRAY['assign','arrive','start','complete']; fare := 80000 + (t % 50) * 7000;
      ELSIF m < 90 THEN steps := ARRAY['cancel'];                         cancel_by := 'rider';   dn := 0;
      ELSIF m < 95 THEN steps := ARRAY['assign','cancel'];                cancel_by := 'rider';
      ELSIF m < 97 THEN steps := ARRAY['assign','arrive','cancel'];       cancel_by := 'driver';
      ELSIF m = 97 THEN steps := ARRAY['assign','arrive','start','cancel']; cancel_by := 'support';
      ELSE               steps := ARRAY['cancel'];                         cancel_by := 'system';  dn := 0;
      END IF;
    ELSIF t <= 199600 THEN
      j := t - 199300; rn := 400 + j; dn := j; created := now() - (j * interval '3 seconds');
      steps := CASE j % 3 WHEN 0 THEN ARRAY['assign'] WHEN 1 THEN ARRAY['assign','arrive'] ELSE ARRAY['assign','arrive','start'] END;
    ELSE
      j := t - 199600; rn := j; dn := 0; created := now() - (j * interval '2 seconds'); steps := ARRAY[]::text[];
    END IF;

    rid := ('10000000-0000-0000-0000-' || lpad(rn::text, 12, '0'))::uuid;
    did := CASE WHEN dn > 0 THEN ('20000000-0000-0000-0000-' || lpad(dn::text, 12, '0'))::uuid END;
    vid := CASE WHEN dn > 0 THEN ('30000000-0000-0000-0000-' || lpad(dn::text, 12, '0'))::uuid END;
    tid := ('40000000-0000-0000-0000-' || lpad(t::text, 12, '0'))::uuid;
    qid := ('50000000-0000-0000-0000-' || lpad(t::text, 12, '0'))::uuid;

    PERFORM set_config('app.actor_role', 'rider', true);
    PERFORM set_config('app.actor_id', rid::text, true);
    INSERT INTO trip (id, rider_id, fare_quote_id, pickup_address, dropoff_address, created_at)
    VALUES (tid, rid, qid, 'BULK pickup ' || t, 'BULK dropoff ' || t, created);

    FOREACH step IN ARRAY steps LOOP
      CASE step
        WHEN 'assign' THEN
          PERFORM set_config('app.actor_role', 'driver', true); PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'assigned', driver_id = did, vehicle_id = vid WHERE id = tid;
        WHEN 'arrive' THEN
          PERFORM set_config('app.actor_role', 'driver', true); PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'arrived' WHERE id = tid;
          IF t % 4 = 0 THEN
            INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at)
            VALUES (tid, 6.400000 + (t % 1000) * 0.0001, 3.300000 + ((t * 7) % 1000) * 0.0001, 8, created + interval '5 minutes');
          END IF;
        WHEN 'start' THEN
          PERFORM set_config('app.actor_role', 'driver', true); PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'started' WHERE id = tid;
          IF t % 4 = 0 THEN
            INSERT INTO location_ping (trip_id, latitude, longitude, accuracy_m, recorded_at)
            SELECT tid, 6.420000 + (t % 1000) * 0.0001, 3.320000 + ((t * 7) % 1000) * 0.0001, 6, created + interval '6 minutes' + g * interval '30 seconds'
            FROM generate_series(1, 2) g;
          END IF;
        WHEN 'complete' THEN
          PERFORM set_config('app.actor_role', 'driver', true); PERFORM set_config('app.actor_id', did::text, true);
          UPDATE trip SET status = 'completed', fare_amount_minor = fare, fare_currency = 'NGN',
                          distance_m = 3000 + (t % 200) * 100 WHERE id = tid;
        WHEN 'cancel' THEN
          PERFORM set_config('app.actor_role', cancel_by, true);
          PERFORM set_config('app.actor_id',
            CASE cancel_by WHEN 'rider' THEN rid::text WHEN 'driver' THEN did::text
                           WHEN 'support' THEN admin1::text ELSE '' END, true);
          UPDATE trip SET status = 'cancelled' WHERE id = tid;
        ELSE NULL;
      END CASE;
    END LOOP;

    IF fare IS NOT NULL THEN   -- a completed trip: payment, event, rating, idempotency key
      PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid::text, true);
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
      VALUES (tid, 'fare', fare, 'NGN', 'BULK-PRV-' || t) RETURNING id INTO pid;
      IF t % 500 <> 0 THEN
        PERFORM set_config('app.actor_role', 'provider', true); PERFORM set_config('app.actor_id', '', true);
        UPDATE payment SET status = 'succeeded', paid_at = now() WHERE id = pid;
        IF t % 10 = 0 THEN
          INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency, processed_at, outcome)
          VALUES ('BULK-EVT-' || t, 'BULK-PRV-' || t, 'payment_succeeded', fare, 'NGN', now(), 'applied');
        END IF;
      END IF;
      IF t % 2 = 0 THEN
        PERFORM set_config('app.actor_role', 'rider', true); PERFORM set_config('app.actor_id', rid::text, true);
        INSERT INTO rating (trip_id, rater_role, stars) VALUES (tid, 'rider', 1 + (t % 5)::int);
      END IF;
      IF t % 5 = 0 THEN
        INSERT INTO idempotency_key (rider_id, action, key, request_hash, response_status, response_body, trip_id, expires_at)
        VALUES (rid, 'request_trip', 'bulk-' || t, md5('r' || t) || md5('q' || t), 201,
                jsonb_build_object('trip_id', tid), tid, now() + interval '24 hours');
      END IF;
    END IF;
  END LOOP;
END
$bulk$;
RESET ROLE;
