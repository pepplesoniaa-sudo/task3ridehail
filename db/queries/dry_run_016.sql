\set VERBOSITY default
BEGIN;
\echo '=== D0 indexes in the database before the migration (inside the transaction)'
SELECT count(*) AS indexes_before FROM pg_indexes WHERE schemaname = 'public';
\echo '=== D1 apply migration 016 (timed)'
\timing on
-- 016 an ordinary index on payment (trip_id)
-- Serves: A4, B6, U1, U3 (EP03 payments[] of a trip, EP15 payment lookup per trip, support payment views).
-- Why: the only index that starts with trip_id on payment is payment_one_live_per_purpose, which is PARTIAL (pending and succeeded only).
-- A read of every payment of a trip (any status, as EP03 needs so that a failed attempt stays visible) cannot use it, so it was a parallel
-- sequential scan of the whole table (169,410 rows, about 15 ms; CONFIRMED in evidence\part_b_payments_by_trip.txt and
-- evidence\migration_016_measure_before.txt). The foreign key payment_trip_id_fkey (trip_id -> trip.id) did not have an index on its
-- referencing column either: PostgreSQL does not create one for a foreign key. This index also covers that column.
-- Cost: one more index to maintain on every payment insert (small: see evidence\migration_016_measure_after.txt) and the disk size of the index.
-- Lock: CREATE INDEX (not CONCURRENTLY, because a migration is one transaction) takes a SHARE lock on payment while it builds, so payment
-- inserts and updates wait for the few seconds that takes; reads continue. Run it when no payment is being made.
-- No grants are needed: an index has no privileges, and ridehail_app already has SELECT on payment.
CREATE INDEX payment_trip_id_idx ON payment (trip_id);
\timing off
\echo '=== D2 indexes after the migration, size of the new index'
SELECT count(*) AS indexes_after FROM pg_indexes WHERE schemaname = 'public';
SELECT indexrelid::regclass AS index_name, pg_relation_size(indexrelid) AS bytes, round(pg_relation_size(indexrelid) / 1048576.0, 2) AS mb, pg_get_indexdef(indexrelid) AS definition FROM pg_index WHERE indexrelid = 'payment_trip_id_idx'::regclass;
ANALYZE payment;
\echo '=== D3 the all-payments-of-a-trip read inside the transaction: which plan now?'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904';
\echo '=== D4 the FK now has an index on its referencing column: indexes of payment that start with trip_id'
SELECT indexrelid::regclass AS index_name, indpred IS NOT NULL AS is_partial FROM pg_index WHERE indrelid = 'payment'::regclass AND indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'payment'::regclass AND attname = 'trip_id') ORDER BY 1;
ROLLBACK;
\echo '=== D5 after ROLLBACK: the index must not exist'
SELECT count(*) AS indexes_after_rollback, (SELECT count(*) FROM pg_class WHERE relname = 'payment_trip_id_idx') AS index_exists FROM pg_indexes WHERE schemaname = 'public';
