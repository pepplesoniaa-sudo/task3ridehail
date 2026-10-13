-- 001 roles and shared functions
-- Serves: B4, B8 (roles for the erasure design), B5 (append-only history).
-- Applied with: psql -1 -v ON_ERROR_STOP=1 (one transaction).
-- No extension is needed: gen_random_uuid() is built into PostgreSQL 13 and later (docs 04, question 5).

-- ridehail_erasure_owner: owns the two erasure functions (migration 006). NOLOGIN so nobody can
-- connect as it. Not a superuser (docs 04, question 4).
CREATE ROLE ridehail_erasure_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- ridehail_app: the role the API connects as. NOLOGIN here: a login role is a deployment step
-- and no password is stored in this project. Grants are in migration 008.
CREATE ROLE ridehail_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- Shared trigger function: refreshes updated_at on every update (docs 02, conventions).
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$fn$;

-- Shared trigger function: append-only tables refuse the operation it is attached to (B4, B5, B10).
-- Attached to UPDATE OR DELETE on trip_status_history, fare_quote, refund, audit_log,
-- and to UPDATE only on location_ping (its rows may be deleted for retention).
CREATE FUNCTION append_only_guard() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP;
END
$fn$;
