-- PLANS FOR THE GRADER: EXPLAIN (ANALYZE, BUFFERS) of the two heaviest read queries of A1 to A5 and, as a labelled extra, the heaviest write.
-- Run as ridehail_app (SET ROLE). The file is run twice and the SECOND run is kept in evidence\plans_for_grader.txt.
-- Data: the BULK set (200,012 trips, 401 waiting), after VACUUM (ANALYZE) of trip, payment and trip_status_history.
-- Parameters are real values from the data (evidence\query_parameters.txt).
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '################################################################'
\echo '(a) A2.1 OPEN REQUESTS NEAR THE DRIVER  (the heaviest READ of A1 to A5)'
\echo '################################################################'
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.id, t.pickup_address, q.pickup_latitude, q.pickup_longitude, q.amount_minor
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id
WHERE t.status = 'requested'
  AND q.pickup_latitude  BETWEEN 6.475 AND 6.495
  AND q.pickup_longitude BETWEEN 3.385 AND 3.405
ORDER BY t.created_at LIMIT 20;

\echo '################################################################'
\echo '(b) A1.1 RETRY CHECK ON THE IDEMPOTENCY KEY  (the second heaviest READ of A1 to A5)'
\echo '################################################################'
EXPLAIN (ANALYZE, BUFFERS)
SELECT response_status, response_body FROM idempotency_key
WHERE rider_id = '10000000-0000-0000-0000-000000004001' AND action = 'request_trip' AND key = 'bulk-1000';

\echo '################################################################'
\echo '(c) EXTRA, LABELLED: A1.3 THE TRIP INSERT  (the heaviest WRITE; includes the trigger work). Rolled back.'
\echo '################################################################'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000002000', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('50000000-0000-0000-0000-0000000a0001', '10000000-0000-0000-0000-000000002000', 6.485, 3.395, 6.52, 3.36,
        6500, 1100, 135000, 'NGN', now() + interval '1 hour');
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('10000000-0000-0000-0000-000000002000', '50000000-0000-0000-0000-0000000a0001', 'A1 pickup', 'A1 dropoff');
ROLLBACK;

\echo '--- the indexes the insert in (c) has to maintain (a plan does not list them): the indexes of trip'
SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'trip' ORDER BY 1;
