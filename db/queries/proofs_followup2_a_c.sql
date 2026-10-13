-- FOLLOW UP 2, proofs 1a and 1c. As ridehail_app (SET ROLE), each write proof in BEGIN ... ROLLBACK, current_user printed.
\set SHOW_CONTEXT always
\set VERBOSITY default

\echo '################ 1a: provider_event_write_audit, the REFUND branch'
\echo '--- the refund that exists in the small set (reference RF-T01-A)'
SELECT id AS refund_id, provider_reference, amount_minor FROM refund WHERE provider_reference = 'RF-T01-A';
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT count(*) AS audit_rows_for_refund_before FROM audit_log WHERE entity_type = 'refund';
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency, processed_at, outcome)
VALUES ('evt-refund-proof-1', 'RF-T01-A', 'refund_succeeded', 50000, 'NGN', now(), 'needs_support');
\echo '--- the audit row: entity_type must be refund and entity_id the refund id'
SELECT a.actor_role, a.action, a.entity_type, a.entity_id, r.id AS refund_id, a.entity_id = r.id AS entity_id_is_the_refund,
       a.details->>'provider_reference' AS provider_reference, a.details->>'event_type' AS event_type
FROM audit_log a, refund r WHERE r.provider_reference = 'RF-T01-A' AND a.details->>'provider_event_id' = 'evt-refund-proof-1';
SELECT count(*) AS audit_rows_for_refund_after FROM audit_log WHERE entity_type = 'refund';
ROLLBACK;
SELECT (SELECT count(*) FROM provider_event WHERE provider_event_id = 'evt-refund-proof-1') AS proof_event_left_behind;

\echo '################ 1c: the timeline query (ORDER BY seq) on a bulk trip NOT among the 62, and on one that IS'
SET ROLE ridehail_app;
SELECT current_user, session_user;
\echo '--- not affected: bulk trip 40000000-...-000100'
SELECT seq, from_status, to_status, actor_role FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000000100' ORDER BY seq;
\echo '--- affected: bulk trip 40000000-...-002845, ORDER BY seq (what the timeline query returns)'
SELECT seq, from_status, to_status, actor_role FROM trip_status_history WHERE trip_id = '40000000-0000-0000-0000-000000002845' ORDER BY seq;
\echo '--- the same trip with the rows in their true order (follow the chain: each row starts where the previous one ended)'
WITH RECURSIVE chain AS (
  SELECT h.*, 1 AS step FROM trip_status_history h WHERE h.trip_id = '40000000-0000-0000-0000-000000002845' AND h.from_status IS NULL
  UNION ALL
  SELECT h.*, c.step + 1 FROM trip_status_history h JOIN chain c ON h.trip_id = c.trip_id AND h.from_status = c.to_status
  WHERE h.trip_id = '40000000-0000-0000-0000-000000002845')
SELECT step, seq, from_status, to_status FROM chain ORDER BY step;
\echo '--- how many of the 62 affected trips are the same shape: the LAST row (to_status completed) has the smallest seq'
SELECT count(*) AS affected_trips, count(*) FILTER (WHERE first_by_seq = 'started>completed') AS where_completed_row_is_first_by_seq
FROM (SELECT trip_id, (array_agg(coalesce(from_status,'new') || '>' || to_status ORDER BY seq))[1] AS first_by_seq
      FROM trip_status_history WHERE trip_id IN (
        SELECT trip_id FROM (SELECT trip_id, from_status, row_number() OVER w AS rn, lag(to_status) OVER w AS prev_to
                             FROM trip_status_history WINDOW w AS (PARTITION BY trip_id ORDER BY seq)) x
        WHERE (rn = 1 AND from_status IS NOT NULL) OR (rn > 1 AND from_status IS DISTINCT FROM prev_to))
      GROUP BY trip_id) y;
RESET ROLE;
