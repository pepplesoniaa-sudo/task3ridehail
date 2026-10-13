-- API PART A: the list queries behind GET /v1/riders/me/trips and GET /v1/drivers/me/trips (keyset pagination), as ridehail_app.
-- Bulk data: rider 10000000-...-000777 has 40 trips; driver 20000000-...-000500 has many. Read only.
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '=== L1 worked example, page 1: the rider app asks for limit 3 (the API fetches limit + 1 = 4 rows to know whether another page exists)'
SELECT id, status, created_at, fare_amount_minor, cancellation_fee_minor
FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777'
ORDER BY created_at DESC, id DESC LIMIT 4;

\echo '=== L2 page 2: the cursor carries the (created_at, id) of the LAST item of page 1 (item 3)'
\echo '    (the values below are taken from the third row of L1)'
SELECT id, status, created_at FROM trip
WHERE rider_id = '10000000-0000-0000-0000-000000000777'
  AND (created_at, id) < ((SELECT created_at FROM (SELECT created_at, id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 3) x ORDER BY created_at, id LIMIT 1),
                          (SELECT id FROM (SELECT created_at, id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 3) x ORDER BY created_at, id LIMIT 1))
ORDER BY created_at DESC, id DESC LIMIT 4;

\echo '=== L3 filter by status (completed or cancelled) and a date range, page 1, limit 5'
SELECT id, status, created_at FROM trip
WHERE rider_id = '10000000-0000-0000-0000-000000000777'
  AND status = ANY (ARRAY['completed','cancelled'])
  AND created_at >= now() - interval '200 days' AND created_at < now() - interval '100 days'
ORDER BY created_at DESC, id DESC LIMIT 6;

\echo '=== P1 plan: no filter, no cursor (rider)'
EXPLAIN (COSTS OFF) SELECT id, status, pickup_address, dropoff_address, created_at, fare_amount_minor, fare_currency, cancellation_fee_minor, cancellation_fee_currency
FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P2 plan: status filter (rider)'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' AND status = ANY (ARRAY['completed','cancelled']) ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P3 plan: date range (rider)'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' AND created_at >= now() - interval '200 days' AND created_at < now() - interval '100 days' ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P4 plan: cursor + status + date range together (rider)'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' AND status = ANY (ARRAY['completed']) AND created_at >= now() - interval '200 days' AND created_at < now() - interval '100 days' AND (created_at, id) < (now() - interval '150 days', 'ffffffff-ffff-ffff-ffff-ffffffffffff') ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P5 plan: driver, no filter'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE driver_id = '20000000-0000-0000-0000-000000000500' ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P6 plan: driver, cursor + status'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE driver_id = '20000000-0000-0000-0000-000000000500' AND status = ANY (ARRAY['completed']) AND (created_at, id) < (now() - interval '150 days', 'ffffffff-ffff-ffff-ffff-ffffffffffff') ORDER BY created_at DESC, id DESC LIMIT 21;
\echo '=== P7 a sort the contract refuses (ORDER BY fare_amount_minor) would need a sort of all the rider trips: shown only to explain why the API does not offer it'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY fare_amount_minor DESC NULLS LAST, id LIMIT 21;
\echo '=== P8 open requests for drivers (bounded list, not keyset): the A2.1 query with limit 20'
EXPLAIN (COSTS OFF) SELECT t.id FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.status = 'requested' AND q.pickup_latitude BETWEEN 6.475 AND 6.495 AND q.pickup_longitude BETWEEN 3.385 AND 3.405 ORDER BY t.created_at LIMIT 20;
\echo '=== counts for the example'
SELECT (SELECT count(*) FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777') AS trips_of_rider_777,
       (SELECT count(*) FROM trip WHERE driver_id = '20000000-0000-0000-0000-000000000500') AS trips_of_driver_500;
