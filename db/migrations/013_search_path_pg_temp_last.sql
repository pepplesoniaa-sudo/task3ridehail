-- 013 fix: the search path of every function must name pg_temp LAST
-- Not in the brief. Found by follow-up 2 proof 1b (db/queries/proofs_followup2_b_search_path.sql, evidence
-- followup2_proof_1b_before_fix.txt and followup2_proof_1b_E2_clean_before_fix.txt):
--   PostgreSQL searches the TEMPORARY schema FIRST for tables, unless pg_temp is written explicitly in the
--   search path. ridehail_app has the default TEMP privilege on the database, so any session of that role can create
--   a temp table with the name of a real table and:
--   E1  make the SECURITY DEFINER audit writers (fixed path "pg_catalog, public") insert the audit row into the
--       temp table. The audit row is silently lost when the session ends.
--   E2  the same for trip_status_history: the trip moved and its history row went into the temp table.
--   E4  make the NON-definer trigger trip_enforce_transition read a temp status_transition_rule, so a forbidden move
--       (assigned -> started, skipping arrived, move F5) was accepted.
--   E3  (an attacker-owned schema in the session search_path) did NOT work against the writers: their fixed path holds.
-- Fix: give all 18 functions the path  pg_catalog, public, pg_temp  (pg_temp named last, so the real tables win).
-- This also fixes the non-definer trigger functions, which used the caller's session path.
-- Bodies, owners, grants and SECURITY DEFINER settings do not change. Serves B4, B5, B8, B9, A4.

-- the two shared trigger functions
ALTER FUNCTION set_updated_at()                SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION append_only_guard()             SET search_path = pg_catalog, public, pg_temp;
-- trip
ALTER FUNCTION trip_enforce_transition()       SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION trip_write_history()            SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION trip_block_delete()             SET search_path = pg_catalog, public, pg_temp;
-- setting
ALTER FUNCTION setting_write_audit()           SET search_path = pg_catalog, public, pg_temp;
-- payment, refund, provider_event
ALTER FUNCTION payment_enforce_rules()         SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION payment_write_audit()           SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION refund_enforce_total()          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION provider_event_guard()          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION provider_event_write_audit()    SET search_path = pg_catalog, public, pg_temp;
-- rating, location_ping
ALTER FUNCTION rating_enforce_rules()          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION rating_update_cache()           SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION rating_block_change()           SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION ping_enforce_trip_status()      SET search_path = pg_catalog, public, pg_temp;
-- the three callable functions
ALTER FUNCTION erase_rider(uuid)               SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION erase_driver(uuid)              SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION add_support_note(text, uuid, text) SET search_path = pg_catalog, public, pg_temp;
