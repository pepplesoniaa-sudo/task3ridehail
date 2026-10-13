-- STAGE 4 PART B finding: EP03 returns payments[] for a trip. Is that read served by an index? Read only, as ridehail_app.
SET ROLE ridehail_app;
SELECT current_user AS cu;
\echo '=== K0 indexes of payment'
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'payment' ORDER BY indexname;
\echo '=== K1 all payments of a trip (what EP03 payments[] needs: every status, so a failed attempt is visible)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904';
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904';
\echo '=== K2 live payments only (pending or succeeded): the predicate of the partial unique index payment_one_live_per_purpose repeated exactly'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904' AND status IN ('pending','succeeded');
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT id, purpose, status, amount_minor, currency FROM payment WHERE trip_id = '40000000-0000-0000-0000-000000198904' AND status IN ('pending','succeeded');
\echo '=== K3 what statuses do payments have, and how many trips have a failed payment (is K1 different from K2 in real data?)'
SELECT status, count(*) FROM payment GROUP BY status ORDER BY status;
\echo '=== K4 the partial index definition'
SELECT pg_get_indexdef(indexrelid) FROM pg_index WHERE indexrelid = 'payment_one_live_per_purpose'::regclass;
