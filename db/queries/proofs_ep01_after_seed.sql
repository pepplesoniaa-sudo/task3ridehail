-- EP01 (POST /v1/fare-quotes) after the sample settings seed, as ridehail_app, rolled back, current_user printed.
-- Shows: (1) the settings read finds all 8 keys, so service_not_configured does not trigger; (2) a pickup and dropoff inside the box
-- get a quote priced with the contract formula; (3) a pickup outside the box is refused by the box test (outside_service_area).
-- The distance and duration estimator is NOT designed (decision 8); the placeholder is straight-line metres times 1.3 and 8.33 m/s.
\set VERBOSITY default
\set SHOW_CONTEXT never
BEGIN; SET ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','rider',true), set_config('app.actor_id','10000000-0000-0000-0000-000000003000',true);

\echo '=== Q1 the settings read of EP01: missing = 0 means service_not_configured does not trigger'
SELECT count(*) AS found, 8 - count(*) AS missing,
       CASE WHEN count(*) = 8 THEN 'configured' ELSE '503 service_not_configured' END AS ep01_outcome
FROM setting WHERE key IN ('base_fare_minor','per_km_minor','per_minute_minor','quote_validity_seconds',
                           'service_area_min_lat_e6','service_area_max_lat_e6','service_area_min_lon_e6','service_area_max_lon_e6');

\echo '=== Q2 which required keys are missing (empty list = none)'
SELECT k AS missing_key FROM unnest(ARRAY['base_fare_minor','per_km_minor','per_minute_minor','quote_validity_seconds',
  'service_area_min_lat_e6','service_area_max_lat_e6','service_area_min_lon_e6','service_area_max_lon_e6']) k
WHERE k NOT IN (SELECT key FROM setting);

\echo '=== Q3 inside the box: pickup 6.45,3.39 dropoff 6.50,3.35 -> quote created (rolled back)'
WITH s AS (
  SELECT max(int_value) FILTER (WHERE key='base_fare_minor') AS base, max(int_value) FILTER (WHERE key='per_km_minor') AS per_km,
         max(int_value) FILTER (WHERE key='per_minute_minor') AS per_min, max(int_value) FILTER (WHERE key='quote_validity_seconds') AS valid_s,
         max(int_value) FILTER (WHERE key='service_area_min_lat_e6') AS min_lat, max(int_value) FILTER (WHERE key='service_area_max_lat_e6') AS max_lat,
         max(int_value) FILTER (WHERE key='service_area_min_lon_e6') AS min_lon, max(int_value) FILTER (WHERE key='service_area_max_lon_e6') AS max_lon
  FROM setting),
p AS (SELECT 6.45::numeric AS plat, 3.39::numeric AS plon, 6.50::numeric AS dlat, 3.35::numeric AS dlon),
e AS (SELECT p.*, round(sqrt(power((dlat-plat)*111320, 2) + power((dlon-plon)*111320*cos(radians((plat+dlat)/2)), 2)) * 1.3)::int AS dist_m FROM p),
d AS (SELECT e.*, round(dist_m / 8.33)::int AS dur_s FROM e)
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
SELECT 'ffffffff-0000-0000-0000-0000000000f3', '10000000-0000-0000-0000-000000003000', plat, plon, dlat, dlon, dist_m, dur_s,
       s.base + round(s.per_km * dist_m / 1000.0)::bigint + round(s.per_min * dur_s / 60.0)::bigint, 'NGN', now() + make_interval(secs => s.valid_s)
FROM d, s
WHERE plat*1000000 BETWEEN s.min_lat AND s.max_lat AND plon*1000000 BETWEEN s.min_lon AND s.max_lon
  AND dlat*1000000 BETWEEN s.min_lat AND s.max_lat AND dlon*1000000 BETWEEN s.min_lon AND s.max_lon
RETURNING id, estimated_distance_m, estimated_duration_s, amount_minor, currency, (expires_at - created_at) AS valid_for;

\echo '=== Q4 outside the box: pickup 9.05,7.49 (Abuja) -> the box test is false, EP01 answers 422 outside_service_area (no quote)'
SELECT (9.05*1000000 BETWEEN min_lat AND max_lat AND 7.49*1000000 BETWEEN min_lon AND max_lon) AS pickup_inside_box
FROM (SELECT max(int_value) FILTER (WHERE key='service_area_min_lat_e6') AS min_lat, max(int_value) FILTER (WHERE key='service_area_max_lat_e6') AS max_lat,
             max(int_value) FILTER (WHERE key='service_area_min_lon_e6') AS min_lon, max(int_value) FILTER (WHERE key='service_area_max_lon_e6') AS max_lon FROM setting) b;
ROLLBACK;
\echo '=== after ROLLBACK: the quote is gone'
SELECT count(*) AS quotes_with_test_id FROM fare_quote WHERE id='ffffffff-0000-0000-0000-0000000000f3';
