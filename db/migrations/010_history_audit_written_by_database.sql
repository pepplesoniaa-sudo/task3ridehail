-- 010 history and audit rows are written by the database, not by the application role (B5)
-- Serves: B5, B4, U3, A3 (docs 03 section 5; 04 questions 4 and 6).
--
-- Before: ridehail_app had INSERT on trip_status_history and audit_log (the trigger functions ran as the
-- calling role), so the application could also insert a false history or audit row directly.
-- After: the four trigger functions that write those rows are SECURITY DEFINER, owned by ridehail_writer, and
-- ridehail_app has no INSERT on either table.
--
-- How the claimed actor is still recorded: the functions read the session settings app.actor_role and
-- app.actor_id with current_setting(..., true). Custom settings belong to the SESSION, not to the user the
-- function runs as, so they are unchanged inside a SECURITY DEFINER function. current_user inside the function
-- is ridehail_writer, but none of these four functions uses current_user: they store the claimed actor.
-- (Verified by the proofs in db/queries/proofs_migration_010.sql.)

-- ======================================================= a. the role
CREATE ROLE ridehail_writer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- ======================================================= b. exactly the rights the functions need
-- INSERT on the two tables is the only write ridehail_writer has anywhere.
GRANT INSERT ON trip_status_history TO ridehail_writer;  -- trip_write_history
GRANT INSERT ON audit_log           TO ridehail_writer;  -- setting_write_audit, payment_write_audit,
                                                         -- provider_event_write_audit, add_support_note
-- provider_event_write_audit looks up which payment or refund a provider reference belongs to.
GRANT SELECT (id, provider_reference) ON payment TO ridehail_writer;
GRANT SELECT (id, provider_reference) ON refund  TO ridehail_writer;
-- The foreign keys of the two tables are checked with the privileges of the table owner, so no REFERENCES or
-- SELECT grant on rider, driver, support_admin or trip is needed (proved by the dry run).

-- The four trigger functions: SECURITY DEFINER, fixed search_path, owner ridehail_writer.
-- The bodies are unchanged (migrations 004 and 005); only the security attributes and the owner change.
ALTER FUNCTION trip_write_history()           SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION setting_write_audit()          SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION payment_write_audit()          SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION provider_event_write_audit()   SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION trip_write_history()           OWNER TO ridehail_writer;
ALTER FUNCTION setting_write_audit()          OWNER TO ridehail_writer;
ALTER FUNCTION payment_write_audit()          OWNER TO ridehail_writer;
ALTER FUNCTION provider_event_write_audit()   OWNER TO ridehail_writer;

-- ======================================================= new function (NOT in the brief, see the report)
-- Dispute notes ("a dispute is only a support note in the audit log", docs 01 section 4 and 02 audit_log) used
-- to be plain INSERTs by the application. With INSERT revoked below, support would have no way to write one.
-- This function is the one door: it records the CLAIMED actor, and only a support actor may use it.
CREATE FUNCTION add_support_note(p_entity_type text, p_entity_id uuid, p_note text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE
  r  text := nullif(current_setting('app.actor_role', true), '');
  a  uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  nid uuid;
BEGIN
  IF r IS DISTINCT FROM 'support' OR a IS NULL THEN
    RAISE EXCEPTION 'only a support actor may write a support note (actor % / %)', r, a;
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) = 0 THEN
    RAISE EXCEPTION 'a support note cannot be empty';
  END IF;
  INSERT INTO audit_log (actor_role, actor_admin_id, action, entity_type, entity_id, note)
  VALUES ('support', a, 'dispute_note', p_entity_type, p_entity_id, p_note)
  RETURNING id INTO nid;
  RETURN nid;
END
$fn$;
ALTER FUNCTION add_support_note(text, uuid, text) OWNER TO ridehail_writer;
REVOKE ALL ON FUNCTION add_support_note(text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION add_support_note(text, uuid, text) TO ridehail_app;

-- ======================================================= d. the application can no longer insert them
-- It keeps SELECT. UPDATE and DELETE were never granted, and append_only_guard blocks them for everyone.
REVOKE INSERT ON trip_status_history FROM ridehail_app;
REVOKE INSERT ON audit_log           FROM ridehail_app;

-- ======================================================= e. a stable order for the status timeline
-- created_at is the same for every move made inside one transaction, so it cannot order a timeline.
-- seq is assigned by the database in insert order. GENERATED ALWAYS: nobody can supply a value.
-- Existing rows are numbered by PostgreSQL while it rewrites the table, in the order it reads the heap
-- (physical order). That is NOT created_at order. The proofs check that the numbering still follows each
-- trip's chain of statuses.
ALTER TABLE trip_status_history ADD COLUMN seq bigint GENERATED ALWAYS AS IDENTITY;
CREATE INDEX trip_status_history_trip_seq_idx ON trip_status_history (trip_id, seq);
