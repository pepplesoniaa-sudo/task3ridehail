RESET ROLE;
SELECT proname, has_function_privilege('ridehail_app', oid, 'EXECUTE') AS app_may_execute, has_function_privilege('public', oid, 'EXECUTE') AS public_may_execute, has_function_privilege('ridehail_writer', oid, 'EXECUTE') AS owner_may_execute FROM pg_proc WHERE proname IN ('trip_write_history','setting_write_audit','payment_write_audit','provider_event_write_audit') ORDER BY 1;
SET ROLE ridehail_app;
SELECT current_user, session_user;
-- a normal trip move: driver 3 moves trip 10
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000003',true);
UPDATE trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
SELECT seq IS NOT NULL AS has_seq, from_status, to_status, actor_role, actor_driver_id FROM trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010' ORDER BY seq DESC LIMIT 1;
-- a payment status change
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
UPDATE payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT actor_role, action, entity_type, details FROM audit_log WHERE entity_type='payment' AND entity_id = (SELECT id FROM payment WHERE provider_reference='PRV-T03-A');
-- a setting change by support
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
UPDATE setting SET int_value = 56000 WHERE key = 'cancellation_fee_minor' RETURNING key, int_value;
SELECT actor_role, action, details FROM audit_log WHERE entity_type='setting' ORDER BY created_at DESC LIMIT 1;
-- a provider event that needs support (refund branch)
SELECT set_config('app.actor_role','provider',true), set_config('app.actor_id','',true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, processed_at, outcome) VALUES ('evt-m012-proof','RF-T01-A','refund_succeeded', now(), 'needs_support');
SELECT actor_role, action, entity_type FROM audit_log WHERE details->>'provider_event_id' = 'evt-m012-proof';
-- the three diagnostic statements that used the dropped index still run
\echo '--- diagnostic 0a after the drop'
EXPLAIN (COSTS OFF) SELECT count(*) FROM (SELECT trip_id FROM trip_status_history GROUP BY trip_id HAVING count(*) > 1) x;
\echo '--- diagnostic 0c (legacy order) after the drop'
EXPLAIN (COSTS OFF) SELECT count(*) FROM (SELECT from_status, row_number() OVER w AS rn, lag(to_status) OVER w AS prev_to FROM trip_status_history WINDOW w AS (PARTITION BY trip_id ORDER BY created_at, id)) x WHERE (rn = 1 AND from_status IS NOT NULL) OR (rn > 1 AND from_status IS DISTINCT FROM prev_to);
