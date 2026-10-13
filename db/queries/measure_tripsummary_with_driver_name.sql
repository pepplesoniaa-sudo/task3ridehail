-- STAGE 4 CLOSE: sizes of the rider's TripSummary (EP06) AFTER the contract fix that adds driver_name_snapshot. Read only, as ridehail_app.
-- Compact JSON bytes (no space after ':' or ','), same method as db\queries\measure_over_fetch.sql.
SET ROLE ridehail_app;
SELECT current_user AS cu;
\echo '=== T1 one item (seed trip 0001): TripSummary for the rider before and after the fix'
WITH t AS (SELECT * FROM trip WHERE id = 'eeeeeeee-0000-0000-0000-000000000001'),
j AS (SELECT
  jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
    'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'cancelled_at', t.cancelled_at, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency,
    'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency) AS before_fix,
  jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address, 'driver_name_snapshot', t.driver_name_snapshot,
    'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'cancelled_at', t.cancelled_at, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency,
    'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency) AS after_fix FROM t)
SELECT 'before fix' AS version, (SELECT count(*) FROM jsonb_object_keys(before_fix)) AS fields, octet_length(replace(replace(before_fix::text, '": ', '":'), ', "', ',"')) AS bytes FROM j
UNION ALL
SELECT 'after fix', (SELECT count(*) FROM jsonb_object_keys(after_fix)), octet_length(replace(replace(after_fix::text, '": ', '":'), ', "', ',"')) FROM j;

\echo '=== T2 a page of 20 rows of rider 777: TripSummary with the name against the 7 fields the list row shows'
WITH items AS (
  SELECT replace(replace(jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address, 'driver_name_snapshot', t.driver_name_snapshot,
      'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'cancelled_at', t.cancelled_at, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency,
      'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency)::text, '": ', '":'), ', "', ',"') AS summary,
    replace(replace(jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address, 'driver_name_snapshot', t.driver_name_snapshot,
      'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency)::text, '": ', '":'), ', "', ',"') AS used7
  FROM trip t WHERE t.rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY t.created_at DESC, t.id DESC LIMIT 20)
SELECT count(*) AS items, sum(octet_length(summary)) AS page_bytes_after_fix, sum(octet_length(used7)) AS used_bytes, round(100.0 * sum(octet_length(used7)) / sum(octet_length(summary)), 1) AS pct_used, round(100.0 - 100.0 * sum(octet_length(used7)) / sum(octet_length(summary)), 1) AS pct_ignored FROM items;

\echo '=== T3 the real driver name values of the first 3 rows (for the worked example of 06 EP06)'
SELECT id, driver_name_snapshot FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 3;
