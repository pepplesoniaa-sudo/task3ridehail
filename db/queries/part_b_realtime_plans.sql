-- STAGE 4 PART B: the database reads behind the rider's watch (docs\08_real_time.md). Read only, as ridehail_app, current_user printed.
-- Each statement is run twice with EXPLAIN (ANALYZE, BUFFERS); the second run is the one the document quotes (warm cache).
SET ROLE ridehail_app;
SELECT current_user AS cu;
SELECT 'ARRAY[' || string_agg(quote_literal(trip_id::text), ',') || ']::uuid[]' AS ids50
FROM (SELECT trip_id FROM location_ping GROUP BY trip_id LIMIT 50) x \gset

\echo '=== R1 resume read: status events of one trip after a seq (trip 40000000-...-198904, seq > 0 shows the whole timeline)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT seq, from_status, to_status, created_at FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000198904' AND seq > 0 ORDER BY seq;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT seq, from_status, to_status, created_at FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000198904' AND seq > 0 ORDER BY seq;
SELECT seq, from_status, to_status FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000198904' ORDER BY seq;

\echo '=== R2 the latest ping of one trip (EP05 and the stream)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT latitude, longitude, accuracy_m, recorded_at FROM location_ping WHERE trip_id = '40000000-0000-0000-0000-000000060152' ORDER BY recorded_at DESC LIMIT 1;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT latitude, longitude, accuracy_m, recorded_at FROM location_ping WHERE trip_id = '40000000-0000-0000-0000-000000060152' ORDER BY recorded_at DESC LIMIT 1;

\echo '=== R3 batched: the latest ping of 50 open streams in ONE query (an API instance does this once per interval, not once per rider)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.trip_id, p.latitude, p.longitude, p.accuracy_m, p.recorded_at
FROM unnest(:ids50) AS t(trip_id) CROSS JOIN LATERAL (SELECT latitude, longitude, accuracy_m, recorded_at FROM location_ping WHERE trip_id = t.trip_id ORDER BY recorded_at DESC LIMIT 1) p;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.trip_id, p.latitude, p.longitude, p.accuracy_m, p.recorded_at
FROM unnest(:ids50) AS t(trip_id) CROSS JOIN LATERAL (SELECT latitude, longitude, accuracy_m, recorded_at FROM location_ping WHERE trip_id = t.trip_id ORDER BY recorded_at DESC LIMIT 1) p;

\echo '=== R4 batched: new status events of 50 open streams in ONE query (seq greater than the last one each stream has seen is filtered by the API)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT trip_id, seq, from_status, to_status, created_at FROM trip_status_history WHERE trip_id = ANY(:ids50) ORDER BY trip_id, seq;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT trip_id, seq, from_status, to_status, created_at FROM trip_status_history WHERE trip_id = ANY(:ids50) ORDER BY trip_id, seq;

\echo '=== R5 the polling read: EP03 trip detail (trip + quote + payments) for one trip, what each 5-second poll costs the database'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.*, q.pickup_latitude, q.pickup_longitude, q.dropoff_latitude, q.dropoff_longitude, q.amount_minor,
  (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status)) FROM payment p WHERE p.trip_id = t.id)
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = '40000000-0000-0000-0000-000000198904' AND t.rider_id = '10000000-0000-0000-0000-000000000777';
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT t.*, q.pickup_latitude, q.pickup_longitude, q.dropoff_latitude, q.dropoff_longitude, q.amount_minor,
  (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'status', p.status)) FROM payment p WHERE p.trip_id = t.id)
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = '40000000-0000-0000-0000-000000198904' AND t.rider_id = '10000000-0000-0000-0000-000000000777';
