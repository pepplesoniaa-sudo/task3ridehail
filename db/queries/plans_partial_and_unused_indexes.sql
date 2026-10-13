-- Index usage checks on the BULK set, as ridehail_app (SET ROLE), after VACUUM (ANALYZE).
-- Part 1: partial indexes, condition repeated EXACTLY versus changed (docs/04 question 7).
-- Part 2: the chosen indexes that the A1 to A5 plans did not touch (refund, driver history, provider_event, vehicle).
SET ROLE ridehail_app;
SELECT current_user, session_user;

\echo '################ PART 1: partial indexes'
\echo '=== 1a trip_requested_created_at_idx: condition repeated exactly (status = requested)'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE status = 'requested' ORDER BY created_at LIMIT 20;
\echo '=== 1b condition changed: status IN (requested, assigned)'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE status IN ('requested','assigned') ORDER BY created_at LIMIT 20;
\echo '=== 1c condition changed: status <> completed'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE status <> 'completed' ORDER BY created_at LIMIT 20;

\echo '=== 1d trip_one_active_per_rider: condition repeated exactly (the four active statuses), one rider'
EXPLAIN (COSTS OFF) SELECT id, status FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' AND status IN ('requested','assigned','arrived','started');
\echo '=== 1e condition changed: status <> completed'
EXPLAIN (COSTS OFF) SELECT id, status FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' AND status <> 'completed';
\echo '=== 1f no status condition at all'
EXPLAIN (COSTS OFF) SELECT id, status FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777';

\echo '=== 1g payment_pending_created_at_idx: condition repeated exactly (status = pending)'
EXPLAIN (COSTS OFF) SELECT id FROM payment WHERE status = 'pending' AND created_at < now() ORDER BY created_at LIMIT 100;
\echo '=== 1h condition changed: status <> succeeded'
EXPLAIN (COSTS OFF) SELECT id FROM payment WHERE status <> 'succeeded' AND created_at < now() ORDER BY created_at LIMIT 100;
\echo '=== 1i condition changed: status IN (pending, failed)'
EXPLAIN (COSTS OFF) SELECT id FROM payment WHERE status IN ('pending','failed') AND created_at < now() ORDER BY created_at LIMIT 100;

\echo '################ PART 2: chosen indexes not touched by A1 to A5'
\echo '=== 2a refund_payment_id_idx: the refund trigger sum (the refund table has 1 row)'
EXPLAIN (COSTS OFF) SELECT COALESCE(sum(amount_minor), 0) FROM refund WHERE payment_id = (SELECT id FROM payment WHERE provider_reference = 'PRV-T01-A');
\echo '=== 2b trip_driver_history_idx: a driver''s history, keyset page'
EXPLAIN (COSTS OFF) SELECT id, status, created_at FROM trip WHERE driver_id = '20000000-0000-0000-0000-000000000500' ORDER BY created_at DESC, id DESC LIMIT 20;
\echo '=== 2c provider_event_reference_idx: the P3 proof lookup (17544 events)'
EXPLAIN (COSTS OFF) SELECT 1 FROM provider_event e
WHERE e.provider_reference = 'BULK-PRV-500' AND e.event_type = 'payment_not_found' AND e.received_at >= now() - interval '1 year'
  AND e.received_at >= (SELECT max(x.received_at) FROM provider_event x WHERE x.provider_reference = 'BULK-PRV-500');
\echo '=== 2d vehicle_driver_id_idx'
EXPLAIN (COSTS OFF) SELECT id, plate_number FROM vehicle WHERE driver_id = '20000000-0000-0000-0000-000000000400' AND is_active AND deleted_at IS NULL;
\echo '=== 2e trip_status_history_trip_seq_idx (the timeline is ordered by seq since migration 010; the old created_at index was dropped by migration 012)'
EXPLAIN (COSTS OFF) SELECT from_status, to_status FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY seq;
\echo '=== 2f location_ping_trip_recorded_idx'
EXPLAIN (COSTS OFF) SELECT latitude, longitude FROM location_ping WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY recorded_at DESC LIMIT 1;
\echo '=== 2g trip_rider_history_idx'
EXPLAIN (COSTS OFF) SELECT id FROM trip WHERE rider_id = '10000000-0000-0000-0000-000000000777' ORDER BY created_at DESC, id DESC LIMIT 20;
