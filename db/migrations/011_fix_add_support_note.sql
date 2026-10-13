-- 011 fix: add_support_note must not need SELECT on audit_log
-- Found by proof F8 of migration 010: calling add_support_note as ridehail_app failed with
--   ERROR: permission denied for table audit_log
-- Cause: the function used INSERT ... RETURNING id, and RETURNING needs SELECT on the column.
-- ridehail_writer has INSERT only on audit_log (by design: it must not be able to read or change it).
-- Fix: make the id first (gen_random_uuid(), built in) and insert it, with no RETURNING. No new privilege.
-- CREATE OR REPLACE keeps the owner (ridehail_writer) and the grants of migration 010. Serves B5, U3.
CREATE OR REPLACE FUNCTION add_support_note(p_entity_type text, p_entity_id uuid, p_note text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE
  r   text := nullif(current_setting('app.actor_role', true), '');
  a   uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  nid uuid := gen_random_uuid();
BEGIN
  IF r IS DISTINCT FROM 'support' OR a IS NULL THEN
    RAISE EXCEPTION 'only a support actor may write a support note (actor % / %)', r, a;
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) = 0 THEN
    RAISE EXCEPTION 'a support note cannot be empty';
  END IF;
  INSERT INTO audit_log (id, actor_role, actor_admin_id, action, entity_type, entity_id, note)
  VALUES (nid, 'support', a, 'dispute_note', p_entity_type, p_entity_id, p_note);
  RETURN nid;
END
$fn$;
