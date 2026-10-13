-- STAGE 4 PART B: measure the REST responses of docs\06_api_contracts.md (read only, as ridehail_app, current_user printed).
-- Builds, from real rows of the small seed (trip eeeeeeee-...-0001: completed, one succeeded payment, two ratings, five history rows),
-- the JSON each endpoint would return, counts fields and bytes (UTF-8, compact form: no space after ':' or ','), and the share a client uses.
-- Nothing is written, no temporary table is used (TEMP is revoked). Seed data is synthetic ("Pickup 1, Lagos", "Driver 1"): no personal data.
-- Field count = top-level keys + 5 keys per payments element. Bytes are of the compact text of the JSON value.
SET ROLE ridehail_app;
SELECT current_user AS cu;

\echo '=== M1 sizes of the JSON documents for trip 0001'
WITH b AS (
  SELECT t.*, q.pickup_latitude, q.pickup_longitude, q.dropoff_latitude, q.dropoff_longitude, q.amount_minor AS est_amount, q.currency AS est_currency
  FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = 'eeeeeeee-0000-0000-0000-000000000001'),
pay AS (SELECT jsonb_agg(jsonb_build_object('id', id, 'purpose', purpose, 'status', status, 'amount_minor', amount_minor, 'currency', currency) ORDER BY created_at) AS p
        FROM payment WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000001'),
ts AS (SELECT to_char(b.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS c,
              to_char(b.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS u,
              to_char(b.started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS s,
              to_char(b.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS d FROM b),
docs AS (
  SELECT
   jsonb_build_object('id', b.id, 'status', b.status, 'rider_id', b.rider_id, 'fare_quote_id', b.fare_quote_id,
     'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
     'pickup_latitude', b.pickup_latitude, 'pickup_longitude', b.pickup_longitude, 'dropoff_latitude', b.dropoff_latitude, 'dropoff_longitude', b.dropoff_longitude,
     'estimated_amount_minor', b.est_amount, 'estimated_currency', b.est_currency,
     'driver_name_snapshot', b.driver_name_snapshot, 'vehicle_plate_snapshot', b.vehicle_plate_snapshot,
     'started_at', ts.s, 'completed_at', ts.d, 'cancelled_at', b.cancelled_at, 'cancelled_by_role', b.cancelled_by_role,
     'cancellation_fee_minor', b.cancellation_fee_minor, 'cancellation_fee_currency', b.cancellation_fee_currency,
     'fare_amount_minor', b.fare_amount_minor, 'fare_currency', b.fare_currency, 'distance_m', b.distance_m,
     'payments', pay.p, 'created_at', ts.c, 'updated_at', ts.u) AS ep03_rider_view,
   jsonb_build_object('id', b.id, 'status', b.status, 'driver_id', b.driver_id, 'vehicle_id', b.vehicle_id,
     'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
     'pickup_latitude', b.pickup_latitude, 'pickup_longitude', b.pickup_longitude, 'dropoff_latitude', b.dropoff_latitude, 'dropoff_longitude', b.dropoff_longitude,
     'estimated_amount_minor', b.est_amount, 'estimated_currency', b.est_currency,
     'started_at', ts.s, 'completed_at', ts.d, 'cancelled_at', b.cancelled_at, 'cancelled_by_role', b.cancelled_by_role,
     'fare_amount_minor', b.fare_amount_minor, 'fare_currency', b.fare_currency, 'distance_m', b.distance_m,
     'created_at', ts.c, 'updated_at', ts.u) AS ep03_driver_view,
   jsonb_build_object('id', b.id, 'status', b.status, 'rider_id', b.rider_id, 'driver_id', b.driver_id, 'vehicle_id', b.vehicle_id, 'fare_quote_id', b.fare_quote_id,
     'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
     'pickup_latitude', b.pickup_latitude, 'pickup_longitude', b.pickup_longitude, 'dropoff_latitude', b.dropoff_latitude, 'dropoff_longitude', b.dropoff_longitude,
     'estimated_amount_minor', b.est_amount, 'estimated_currency', b.est_currency,
     'driver_name_snapshot', b.driver_name_snapshot, 'vehicle_plate_snapshot', b.vehicle_plate_snapshot,
     'started_at', ts.s, 'completed_at', ts.d, 'cancelled_at', b.cancelled_at, 'cancelled_by_role', b.cancelled_by_role,
     'cancellation_fee_minor', b.cancellation_fee_minor, 'cancellation_fee_currency', b.cancellation_fee_currency,
     'fare_amount_minor', b.fare_amount_minor, 'fare_currency', b.fare_currency, 'distance_m', b.distance_m,
     'payments', pay.p, 'created_at', ts.c, 'updated_at', ts.u) AS ep03_support_view,
   jsonb_build_object('id', b.id, 'status', b.status, 'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
     'created_at', ts.c, 'completed_at', ts.d, 'cancelled_at', b.cancelled_at,
     'fare_amount_minor', b.fare_amount_minor, 'fare_currency', b.fare_currency,
     'cancellation_fee_minor', b.cancellation_fee_minor, 'cancellation_fee_currency', b.cancellation_fee_currency) AS ep06_summary_item,
   jsonb_build_object('id', b.id, 'status', b.status, 'pickup_address', b.pickup_address, 'dropoff_address', b.dropoff_address,
     'driver_name_snapshot', b.driver_name_snapshot, 'fare_amount_minor', b.fare_amount_minor, 'fare_currency', b.fare_currency) AS need_rider_list_row,
   jsonb_build_object('id', b.id, 'status', b.status, 'pickup_address', b.pickup_address, 'pickup_latitude', b.pickup_latitude, 'pickup_longitude', b.pickup_longitude,
     'dropoff_address', b.dropoff_address, 'dropoff_latitude', b.dropoff_latitude, 'dropoff_longitude', b.dropoff_longitude,
     'estimated_amount_minor', b.est_amount, 'estimated_currency', b.est_currency) AS need_driver_card
  FROM b, pay, ts),
flat AS (
  SELECT v.label, v.j,
         replace(replace(replace(replace(v.j::text, '": ', '":'), ', "', ',"'), '}, {', '},{'), '], [', '],[') AS compact
  FROM docs d, LATERAL (VALUES ('EP03 rider view', d.ep03_rider_view), ('EP03 driver view', d.ep03_driver_view), ('EP03 support view', d.ep03_support_view),
                               ('EP06 TripSummary item', d.ep06_summary_item), ('NEEDED rider list row', d.need_rider_list_row),
                               ('NEEDED driver active-trip card', d.need_driver_card)) v(label, j))
SELECT label, octet_length(compact) AS bytes,
       (SELECT count(*) FROM jsonb_object_keys(j)) + coalesce(jsonb_array_length(j->'payments') * 5, 0) AS fields
FROM flat ORDER BY bytes DESC;

\echo '=== M2 the REST responses as the client would receive them (pretty printed here only for reading)'
SELECT jsonb_pretty(jsonb_build_object('id', t.id, 'status', t.status, 'rider_id', t.rider_id, 'fare_quote_id', t.fare_quote_id,
     'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
     'pickup_latitude', q.pickup_latitude, 'pickup_longitude', q.pickup_longitude, 'dropoff_latitude', q.dropoff_latitude, 'dropoff_longitude', q.dropoff_longitude,
     'estimated_amount_minor', q.amount_minor, 'estimated_currency', q.currency,
     'driver_name_snapshot', t.driver_name_snapshot, 'vehicle_plate_snapshot', t.vehicle_plate_snapshot,
     'started_at', to_char(t.started_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
     'cancelled_at', t.cancelled_at, 'cancelled_by_role', t.cancelled_by_role,
     'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency,
     'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency, 'distance_m', t.distance_m,
     'payments', (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'purpose', p.purpose, 'status', p.status, 'amount_minor', p.amount_minor, 'currency', p.currency)) FROM payment p WHERE p.trip_id = t.id),
     'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'updated_at', to_char(t.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))) AS ep03_rider_response
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id WHERE t.id = 'eeeeeeee-0000-0000-0000-000000000001';

\echo '=== M3 the other REST calls a support console page needs for the same trip (EP04 history, EP18 ratings, EP16 payment with events and refunds)'
SELECT 'EP04 status-history' AS call, 5 AS items_expected, octet_length(replace(replace(replace(jsonb_build_object('items',
   (SELECT jsonb_agg(jsonb_build_object('seq', h.seq, 'from_status', h.from_status, 'to_status', h.to_status, 'actor_role', h.actor_role,
      'created_at', to_char(h.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'actor_rider_id', h.actor_rider_id, 'actor_driver_id', h.actor_driver_id, 'actor_admin_id', h.actor_admin_id) ORDER BY h.seq)
    FROM trip_status_history h WHERE h.trip_id = 'eeeeeeee-0000-0000-0000-000000000001'))::text, '": ', '":'), ', "', ',"'), '}, {', '},{')) AS bytes
UNION ALL
SELECT 'EP18 ratings', 2, octet_length(replace(replace(replace(jsonb_build_object('items',
   (SELECT jsonb_agg(jsonb_build_object('id', r.id, 'trip_id', r.trip_id, 'rater_role', r.rater_role, 'stars', r.stars, 'comment', r.comment,
      'created_at', to_char(r.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))
    FROM rating r WHERE r.trip_id = 'eeeeeeee-0000-0000-0000-000000000001'))::text, '": ', '":'), ', "', ',"'), '}, {', '},{'))
UNION ALL
SELECT 'EP16 payment (support view)', 1, octet_length(replace(replace(replace(jsonb_build_object('id', p.id, 'trip_id', p.trip_id, 'purpose', p.purpose, 'amount_minor', p.amount_minor, 'currency', p.currency,
      'status', p.status, 'paid_at', to_char(p.paid_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'failure_reason', p.failure_reason,
      'created_at', to_char(p.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'provider_reference', p.provider_reference,
      'refunds', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'payment_id', f.payment_id, 'amount_minor', f.amount_minor, 'currency', f.currency, 'reason', f.reason,
          'created_by_admin_id', f.created_by_admin_id, 'provider_reference', f.provider_reference, 'created_at', to_char(f.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))), '[]'::jsonb) FROM refund f WHERE f.payment_id = p.id),
      'provider_events', (SELECT coalesce(jsonb_agg(jsonb_build_object('provider_event_id', e.provider_event_id, 'event_type', e.event_type,
          'received_at', to_char(e.received_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'outcome', e.outcome)), '[]'::jsonb) FROM provider_event e WHERE e.provider_reference = p.provider_reference))::text, '": ', '":'), ', "', ',"'), '}, {', '},{'))
FROM payment p WHERE p.trip_id = 'eeeeeeee-0000-0000-0000-000000000001';

\echo '=== M4 a rider list page: the rows of rider 777 (40 trips, bulk data), page of 20, EP06 TripSummary items against the five fields the row shows'
WITH items AS (
  SELECT jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
      'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'cancelled_at', t.cancelled_at, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency,
      'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency) AS summary,
    jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
      'driver_name_snapshot', t.driver_name_snapshot, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency) AS needed
  FROM trip t WHERE t.rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY t.created_at DESC, t.id DESC LIMIT 20),
sz AS (SELECT sum(octet_length(replace(replace(summary::text, '": ', '":'), ', "', ',"'))) AS summary_bytes,
              sum(octet_length(replace(replace(needed::text, '": ', '":'), ', "', ',"'))) AS needed_bytes, count(*) AS n FROM items)
SELECT n AS items, summary_bytes, needed_bytes, round(100.0 * needed_bytes / summary_bytes, 1) AS pct_used, round(100.0 - 100.0 * needed_bytes / summary_bytes, 1) AS pct_ignored FROM sz;

\echo '=== M5 the same page, honest version: the rider row uses 6 of the 11 TripSummary fields; the driver name it also shows is NOT in TripSummary (contract gap). Cost of the two ways to get it:'
WITH items AS (
  SELECT t.id,
    replace(replace(jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
      'created_at', to_char(t.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'completed_at', to_char(t.completed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'cancelled_at', t.cancelled_at, 'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency,
      'cancellation_fee_minor', t.cancellation_fee_minor, 'cancellation_fee_currency', t.cancellation_fee_currency)::text, '": ', '":'), ', "', ',"') AS summary,
    replace(replace(jsonb_build_object('id', t.id, 'status', t.status, 'pickup_address', t.pickup_address, 'dropoff_address', t.dropoff_address,
      'fare_amount_minor', t.fare_amount_minor, 'fare_currency', t.fare_currency)::text, '": ', '":'), ', "', ',"') AS used6,
    replace(replace(jsonb_build_object('driver_name_snapshot', t.driver_name_snapshot)::text, '": ', '":'), ', "', ',"') AS dn,
    t.driver_name_snapshot
  FROM trip t WHERE t.rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY t.created_at DESC, t.id DESC LIMIT 20)
SELECT count(*) AS items, count(driver_name_snapshot) AS rows_with_driver_name,
       sum(octet_length(summary)) AS summary_bytes, sum(octet_length(used6)) AS used_bytes,
       round(100.0 * sum(octet_length(used6)) / sum(octet_length(summary)), 1) AS pct_used,
       round(100.0 - 100.0 * sum(octet_length(used6)) / sum(octet_length(summary)), 1) AS pct_ignored,
       sum(octet_length(dn)) AS driver_name_bytes_if_added
FROM items;
