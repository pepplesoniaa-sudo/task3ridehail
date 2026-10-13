-- STAGE 4 CLOSE: measure the payments-by-trip read, the EP03 read and a payment insert, before and after migration 016.
-- Run twice (before and after); the outputs are kept in evidence\migration_016_measure_before.txt and _after.txt.
-- Reads are read only. The insert runs inside BEGIN ... ROLLBACK as ridehail_app with the rider's claim; nothing is kept.
-- Timings vary by about 3 times between runs on this machine (shared 4-CPU container), so each statement is run more than once.
SET ROLE ridehail_app;
SELECT current_user AS cu;

\echo '=== S1 sizes: payment table and its indexes'
SELECT pg_size_pretty(pg_table_size('payment')) AS table_size, pg_size_pretty(pg_indexes_size('payment')) AS all_indexes_size,
       (SELECT count(*) FROM payment) AS payment_rows, (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public') AS indexes_in_database;
SELECT indexrelid::regclass AS index_name, pg_relation_size(indexrelid) AS bytes, round(pg_relation_size(indexrelid) / 1048576.0, 2) AS mb, pg_get_indexdef(indexrelid) AS definition
FROM pg_index WHERE indrelid = 'payment'::regclass ORDER BY 1;

\echo '=== P1 all payments of a trip (every status), run 1 and run 2'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904';
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904';
\echo '=== P2 a seed trip that has exactly one payment (trip 04, the cancellation fee)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000004';

\echo '=== P3 EP03 full read (trip + quote + all payments), run 1 and run 2'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.*, q.pickup_latitude, q.pickup_longitude, q.dropoff_latitude, q.dropoff_longitude, q.amount_minor,
  (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'purpose', p.purpose, 'status', p.status, 'amount_minor', p.amount_minor, 'currency', p.currency)) FROM payment p WHERE p.trip_id = t.id)
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = '40000000-0000-0000-0000-000000198904' AND t.rider_id = '10000000-0000-0000-0000-000000000777';
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.*, q.pickup_latitude, q.pickup_longitude, q.dropoff_latitude, q.dropoff_longitude, q.amount_minor,
  (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'purpose', p.purpose, 'status', p.status, 'amount_minor', p.amount_minor, 'currency', p.currency)) FROM payment p WHERE p.trip_id = t.id)
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = '40000000-0000-0000-0000-000000198904' AND t.rider_id = '10000000-0000-0000-0000-000000000777';

\echo '=== I1 a payment insert: rider 668 pays the cancellation fee of bulk trip 111893 (50000 kobo). EXPLAIN (ANALYZE) of the INSERT, rolled back. Run 1 in full:'
BEGIN; SET ROLE ridehail_app;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference)
VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-1');
ROLLBACK;
\echo '=== I2 to I6 the same insert 5 more times (only the timing lines matter; each run is rolled back)'
BEGIN; SET ROLE ridehail_app; SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-2');
ROLLBACK;
BEGIN; SET ROLE ridehail_app; SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-3');
ROLLBACK;
BEGIN; SET ROLE ridehail_app; SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-4');
ROLLBACK;
BEGIN; SET ROLE ridehail_app; SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-5');
ROLLBACK;
BEGIN; SET ROLE ridehail_app; SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000000668',true);
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference) VALUES ('40000000-0000-0000-0000-000000111893','cancellation_fee',50000,'NGN','PRV-M016-6');
ROLLBACK;
\echo '=== after the rollbacks: payments for trip 111893 and total rows (nothing kept)'
SELECT (SELECT count(*) FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000111893') AS payments_trip_111893, (SELECT count(*) FROM payment) AS payment_rows;
