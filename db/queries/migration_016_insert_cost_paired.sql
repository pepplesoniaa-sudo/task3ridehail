-- Paired insert-cost test for index payment_trip_id_idx, in the same minute, same session type, alternating WITH and WITHOUT the index.
-- WITHOUT = the dev login drops the index INSIDE a transaction that is rolled back (DDL is transactional in PostgreSQL); nothing is kept.
-- Each round: 300 inserts of a payment (rider 668, bulk trip 111893, cancellation fee 50000) as ridehail_app, each undone by a sub-transaction,
-- timed with clock_timestamp(). Output: average milliseconds per insert (trigger payment_enforce_rules and the FK check included).
\set VERBOSITY terse
\echo '=== index present at the start?'
SELECT count(*) AS payment_trip_id_idx_exists FROM pg_class WHERE relname = 'payment_trip_id_idx';
\echo '=== round 1, WITH the index'
BEGIN;

SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITH index, round 1: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== round 1, WITHOUT the index'
BEGIN;
DROP INDEX payment_trip_id_idx;
SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITHOUT index, round 1: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== round 2, WITH the index'
BEGIN;

SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITH index, round 2: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== round 2, WITHOUT the index'
BEGIN;
DROP INDEX payment_trip_id_idx;
SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITHOUT index, round 2: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== round 3, WITH the index'
BEGIN;

SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITH index, round 3: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== round 3, WITHOUT the index'
BEGIN;
DROP INDEX payment_trip_id_idx;
SET LOCAL ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true) \gset
DO $$
DECLARE t0 timestamptz; i int;
BEGIN
  t0 := clock_timestamp();
  FOR i IN 1..300 LOOP
    BEGIN
      INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-PAIR-'||i);
      RAISE EXCEPTION 'undo' USING ERRCODE = 'RH999';
    EXCEPTION WHEN SQLSTATE 'RH999' THEN NULL;
    END;
  END LOOP;
  RAISE NOTICE 'WITHOUT index, round 3: % ms per insert (300 inserts, %)', round((extract(epoch FROM clock_timestamp() - t0) * 1000 / 300)::numeric, 3), clock_timestamp() - t0;
END $$;
ROLLBACK;
\echo '=== after all rounds: index still exists, no payment left behind'
SELECT (SELECT count(*) FROM pg_class WHERE relname = 'payment_trip_id_idx') AS payment_trip_id_idx_exists, (SELECT count(*) FROM payment) AS payment_rows, (SELECT count(*) FROM payment WHERE provider_reference LIKE 'PRV-PAIR-%') AS pair_rows_left;
