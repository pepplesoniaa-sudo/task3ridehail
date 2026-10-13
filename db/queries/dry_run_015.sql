\set ON_ERROR_STOP 0
\set VERBOSITY default
\set SHOW_CONTEXT never
BEGIN;
\echo '=== DRY RUN: apply migration 015 inside BEGIN ... ROLLBACK'
-- 015 one SQLSTATE per rule (custom class RH), message text unchanged
-- Serves: B1, B2, B4, B5, B6, B7, B8, B9, B10, A1 to A5 (the API maps database errors by SQLSTATE, not by message text).
-- Until now every rule raised by a trigger or function used the default SQLSTATE P0001, so the API would have had to read
-- the message text to choose a status. Each RAISE EXCEPTION now carries USING ERRCODE = 'RHnnn'. Nothing else changes:
-- the message text, the logic, the owner, SECURITY DEFINER, the search_path (ending in pg_temp) and the grants are kept.
-- CREATE OR REPLACE FUNCTION keeps the owner and the ACL of an existing function; the bodies below are the live bodies
-- (pg_get_functiondef of the database after migration 014) with only ' USING ERRCODE = ''RHnnn''' added to each RAISE.
-- RH is a custom class (letters R and H, not a PostgreSQL class). RH0xx = trip, RH02x = payment, RH03x = ping and provider_event,
-- RH04x = rating, RH05x = refund, RH06x = setting and notes, RH07x = erasure, RH08x = generic append-only guard.
-- Table: code | rule | function | message start | API error code (06b_error_catalogue.md)
-- RH001 | only the rider may request a trip | trip_enforce_transition | only the rider may request a trip | internal_error
-- RH002 | a new trip must start as requested | trip_enforce_transition | a new trip must start as requested | internal_error
-- RH003 | a new trip cannot carry start, end or cancel times | trip_enforce_transition | a new trip cannot carry | internal_error
-- RH004 | fare quote has expired | trip_enforce_transition | fare quote % has expired | quote_expired
-- RH005 | trip is terminal | trip_enforce_transition | trip is % (terminal) | trip_finished
-- RH006 | driver_id cannot change once set | trip_enforce_transition | driver_id cannot change once set | internal_error
-- RH007 | actor role not set | trip_enforce_transition, payment_enforce_rules | app.actor_role is not set | internal_error
-- RH008 | illegal trip transition | trip_enforce_transition | illegal transition % | illegal_transition
-- RH009 | actor is not the trip rider | trip_enforce_transition | actor is not this trip's rider | internal_error
-- RH010 | actor is not the trip driver | trip_enforce_transition | actor is not this trip's driver | internal_error
-- RH011 | support actor id required | trip_enforce_transition, payment_enforce_rules | a support actor id is required | internal_error
-- RH012 | vehicle required to assign | trip_enforce_transition | a vehicle is required | internal_error
-- RH013 | cancellation fee setting missing | trip_enforce_transition | setting cancellation_fee_minor is missing | service_not_configured
-- RH014 | unexpected target status | trip_enforce_transition | unexpected target status | internal_error
-- RH015 | columns outside the move changed (trip) | trip_enforce_transition | these columns may not change | internal_error
-- RH016 | trips are never deleted | trip_block_delete | trips are never deleted | internal_error
-- RH020 | payment must start pending | payment_enforce_rules | a payment must be created as pending | internal_error
-- RH021 | only the trip rider may start a payment | payment_enforce_rules | only the trip's rider may start a payment | internal_error
-- RH022 | fare payment needs a completed trip | payment_enforce_rules | a fare payment needs | trip_not_payable
-- RH023 | payment amount differs from fare | payment_enforce_rules | payment amount % does not equal the trip fare | internal_error
-- RH024 | cancellation fee payment needs a fee | payment_enforce_rules | a cancellation fee payment needs | nothing_to_pay
-- RH025 | payment amount differs from fee | payment_enforce_rules | payment amount % does not equal the cancellation fee | internal_error
-- RH026 | payment is terminal | payment_enforce_rules | payment is % (terminal) | payment_final
-- RH027 | illegal payment transition | payment_enforce_rules | illegal payment transition | internal_error
-- RH028 | P3 proof missing | payment_enforce_rules | support may fail a pending payment | payment_proof_missing
-- RH029 | columns outside the move changed (payment) | payment_enforce_rules | these payment columns may not change | internal_error
-- RH030 | ping needs an open trip | ping_enforce_trip_status | a location ping needs | trip_not_in_progress
-- RH031 | provider_event never deleted | provider_event_guard | provider_event rows are never deleted | internal_error
-- RH032 | provider_event already processed | provider_event_guard | provider_event is already processed | internal_error
-- RH033 | provider_event received fields frozen | provider_event_guard | the received fields of a provider_event | internal_error
-- RH040 | rating rows are append-only | rating_block_change | rating is append-only | internal_error
-- RH041 | rating needs a completed trip | rating_enforce_rules | a rating needs a completed trip | trip_not_completed
-- RH042 | rating window setting missing | rating_enforce_rules | setting rating_window_days is missing | service_not_configured
-- RH043 | rating window passed | rating_enforce_rules | the rating window of | rating_window_closed
-- RH044 | rating must come from the trip rider | rating_enforce_rules | the rating must come from this trip's rider | internal_error
-- RH045 | rating must come from the trip driver | rating_enforce_rules | the rating must come from this trip's driver | internal_error
-- RH050 | refund needs a succeeded payment | refund_enforce_total | a refund needs a succeeded payment | payment_not_succeeded
-- RH051 | refund currency differs | refund_enforce_total | refund currency | internal_error
-- RH052 | refunds exceed payment | refund_enforce_total | refunds % + % | refund_exceeds_payment
-- RH060 | only support may change a setting | setting_write_audit | only a support actor may change a setting | internal_error
-- RH061 | only support may write a note | add_support_note | only a support actor may write a support note | internal_error
-- RH062 | support note empty | add_support_note | a support note cannot be empty | validation_failed
-- RH070 | person does not exist (erasure) | erase_rider, erase_driver | rider % does not exist / driver % does not exist | not_found
-- RH071 | person has an active trip (erasure) | erase_rider, erase_driver | rider % has an active trip / driver % has an active trip | person_has_active_trip
-- RH080 | append-only table | append_only_guard | % is append-only: % is not allowed | internal_error
-- A repeated code (RH007, RH011, RH070, RH071) is the same rule raised from two functions.
CREATE OR REPLACE FUNCTION public.add_support_note(p_entity_type text, p_entity_id uuid, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  r   text := nullif(current_setting('app.actor_role', true), '');
  a   uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  nid uuid := gen_random_uuid();
BEGIN
  IF r IS DISTINCT FROM 'support' OR a IS NULL THEN
    RAISE EXCEPTION 'only a support actor may write a support note (actor % / %)', r, a USING ERRCODE = 'RH061';
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) = 0 THEN
    RAISE EXCEPTION 'a support note cannot be empty' USING ERRCODE = 'RH062';
  END IF;
  INSERT INTO audit_log (id, actor_role, actor_admin_id, action, entity_type, entity_id, note)
  VALUES (nid, 'support', a, 'dispute_note', p_entity_type, p_entity_id, p_note);
  RETURN nid;
END
$function$
;

CREATE OR REPLACE FUNCTION public.append_only_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP USING ERRCODE = 'RH080';
END
$function$
;

CREATE OR REPLACE FUNCTION public.erase_driver(p_driver uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM driver WHERE id = p_driver) THEN
    RAISE EXCEPTION 'driver % does not exist', p_driver USING ERRCODE = 'RH070';
  END IF;
  IF EXISTS (SELECT 1 FROM trip WHERE driver_id = p_driver
             AND status IN ('assigned','arrived','started')) THEN
    RAISE EXCEPTION 'driver % has an active trip: cannot erase (B8)', p_driver USING ERRCODE = 'RH071';
  END IF;
  UPDATE trip SET driver_name_snapshot = 'erased', vehicle_plate_snapshot = 'erased'
   WHERE driver_id = p_driver;
  UPDATE rating SET comment = NULL
   WHERE rater_role = 'driver' AND comment IS NOT NULL
     AND trip_id IN (SELECT id FROM trip WHERE driver_id = p_driver);
  UPDATE vehicle SET plate_number = 'deleted-' || id::text, is_active = false,
                     deleted_at = COALESCE(deleted_at, now())
   WHERE driver_id = p_driver;
  UPDATE driver SET full_name = 'Deleted driver', phone = 'deleted-' || id::text,
                    licence_number = 'deleted-' || id::text, deleted_at = COALESCE(deleted_at, now())
   WHERE id = p_driver;
END
$function$
;

CREATE OR REPLACE FUNCTION public.erase_rider(p_rider uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM rider WHERE id = p_rider) THEN
    RAISE EXCEPTION 'rider % does not exist', p_rider USING ERRCODE = 'RH070';
  END IF;
  IF EXISTS (SELECT 1 FROM trip WHERE rider_id = p_rider
             AND status IN ('requested','assigned','arrived','started')) THEN
    RAISE EXCEPTION 'rider % has an active trip: cannot erase (B8)', p_rider USING ERRCODE = 'RH071';
  END IF;
  UPDATE trip SET pickup_address = 'erased', dropoff_address = 'erased'
   WHERE rider_id = p_rider;
  UPDATE rating SET comment = NULL
   WHERE rater_role = 'rider' AND comment IS NOT NULL
     AND trip_id IN (SELECT id FROM trip WHERE rider_id = p_rider);
  UPDATE rider SET full_name = 'Deleted rider', phone = 'deleted-' || id::text, email = NULL,
                   deleted_at = COALESCE(deleted_at, now())
   WHERE id = p_rider;
END
$function$
;

CREATE OR REPLACE FUNCTION public.payment_enforce_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  r        text := nullif(current_setting('app.actor_role', true), '');
  a        uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  t        trip%ROWTYPE;
  allowed  text[];
  diff     text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending' THEN
      RAISE EXCEPTION 'a payment must be created as pending, not %', NEW.status USING ERRCODE = 'RH020';
    END IF;
    SELECT * INTO t FROM trip WHERE id = NEW.trip_id;
    IF NOT FOUND THEN
      RETURN NEW;  -- the foreign key reports the missing trip
    END IF;
    IF r IS DISTINCT FROM 'rider' OR a IS DISTINCT FROM t.rider_id THEN
      RAISE EXCEPTION 'only the trip''s rider may start a payment (actor % / %)', r, a USING ERRCODE = 'RH021';
    END IF;
    IF NEW.purpose = 'fare' THEN
      IF t.status <> 'completed' THEN
        RAISE EXCEPTION 'a fare payment needs a completed trip (status is %)', t.status USING ERRCODE = 'RH022';
      END IF;
      IF NEW.amount_minor <> t.fare_amount_minor THEN
        RAISE EXCEPTION 'payment amount % does not equal the trip fare %', NEW.amount_minor, t.fare_amount_minor USING ERRCODE = 'RH023';
      END IF;
    ELSIF NEW.purpose = 'cancellation_fee' THEN
      IF t.status <> 'cancelled' OR COALESCE(t.cancellation_fee_minor, 0) <= 0 THEN
        RAISE EXCEPTION 'a cancellation fee payment needs a cancelled trip with a fee above 0' USING ERRCODE = 'RH024';
      END IF;
      IF NEW.amount_minor <> t.cancellation_fee_minor THEN
        RAISE EXCEPTION 'payment amount % does not equal the cancellation fee %', NEW.amount_minor, t.cancellation_fee_minor USING ERRCODE = 'RH025';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status IN ('succeeded','failed') THEN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
      RAISE EXCEPTION 'payment is % (terminal): only updated_at may change', OLD.status USING ERRCODE = 'RH026';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    allowed := ARRAY['updated_at'];
  ELSE
    IF r IS NULL THEN
      RAISE EXCEPTION 'app.actor_role is not set' USING ERRCODE = 'RH007';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM status_transition_rule
                   WHERE entity = 'payment' AND from_status = OLD.status
                     AND to_status = NEW.status AND actor_role = r) THEN
      RAISE EXCEPTION 'illegal payment transition % -> % by %', OLD.status, NEW.status, r USING ERRCODE = 'RH027';
    END IF;
    IF r = 'support' THEN
      IF a IS NULL THEN
        RAISE EXCEPTION 'a support actor id is required' USING ERRCODE = 'RH011';
      END IF;
      IF NOT EXISTS (
           SELECT 1 FROM provider_event e
           WHERE e.provider_reference = OLD.provider_reference
             AND e.event_type = 'payment_not_found'
             AND e.received_at >= OLD.created_at
             AND e.received_at >= (SELECT max(x.received_at) FROM provider_event x
                                   WHERE x.provider_reference = OLD.provider_reference)) THEN
        RAISE EXCEPTION 'support may fail a pending payment only after a payment_not_found event for this reference, received after the payment was created and not superseded by a later event (P3)' USING ERRCODE = 'RH028';
      END IF;
    END IF;
    IF NEW.status = 'succeeded' THEN
      allowed := ARRAY['status','updated_at','paid_at'];
    ELSE
      allowed := ARRAY['status','updated_at','failure_reason'];
    END IF;
  END IF;

  SELECT array_agg(k) INTO diff
  FROM jsonb_object_keys(to_jsonb(NEW)) AS k
  WHERE (to_jsonb(NEW) -> k) IS DISTINCT FROM (to_jsonb(OLD) -> k);
  IF diff IS NOT NULL AND NOT (diff <@ allowed) THEN
    RAISE EXCEPTION 'these payment columns may not change in this move: %', diff USING ERRCODE = 'RH029';
  END IF;
  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.ping_enforce_trip_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  s text;
BEGIN
  SELECT status INTO s FROM trip WHERE id = NEW.trip_id;
  IF FOUND AND s NOT IN ('assigned','arrived','started') THEN
    RAISE EXCEPTION 'a location ping needs a trip that is assigned, arrived or started (status is %)', s USING ERRCODE = 'RH030';
  END IF;
  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.provider_event_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  open_cols CONSTANT text[] := ARRAY['processed_at','outcome','updated_at'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'provider_event rows are never deleted' USING ERRCODE = 'RH031';
  END IF;
  IF OLD.processed_at IS NOT NULL THEN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
      RAISE EXCEPTION 'provider_event is already processed: it cannot change' USING ERRCODE = 'RH032';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - open_cols) IS DISTINCT FROM (to_jsonb(OLD) - open_cols) THEN
    RAISE EXCEPTION 'the received fields of a provider_event cannot change' USING ERRCODE = 'RH033';
  END IF;
  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.rating_block_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND current_user = 'ridehail_erasure_owner'
     AND (to_jsonb(NEW) - ARRAY['comment','updated_at']) = (to_jsonb(OLD) - ARRAY['comment','updated_at']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'rating is append-only: % is not allowed (current_user is %)', TG_OP, current_user USING ERRCODE = 'RH040';
END
$function$
;

CREATE OR REPLACE FUNCTION public.rating_enforce_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  r   text := nullif(current_setting('app.actor_role', true), '');
  a   uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  t   trip%ROWTYPE;
  win bigint;
BEGIN
  SELECT * INTO t FROM trip WHERE id = NEW.trip_id;
  IF NOT FOUND THEN
    RETURN NEW;  -- the foreign key reports the missing trip
  END IF;
  IF t.status <> 'completed' THEN
    RAISE EXCEPTION 'a rating needs a completed trip (status is %) (B7)', t.status USING ERRCODE = 'RH041';
  END IF;
  SELECT int_value INTO win FROM setting WHERE key = 'rating_window_days';
  IF win IS NULL THEN
    RAISE EXCEPTION 'setting rating_window_days is missing' USING ERRCODE = 'RH042';
  END IF;
  IF now() > t.completed_at + make_interval(days => win::int) THEN
    RAISE EXCEPTION 'the rating window of % days has passed (B7)', win USING ERRCODE = 'RH043';
  END IF;
  IF NEW.rater_role = 'rider'  AND (r IS DISTINCT FROM 'rider'  OR a IS DISTINCT FROM t.rider_id) THEN
    RAISE EXCEPTION 'the rating must come from this trip''s rider (actor % / %)', r, a USING ERRCODE = 'RH044';
  END IF;
  IF NEW.rater_role = 'driver' AND (r IS DISTINCT FROM 'driver' OR a IS DISTINCT FROM t.driver_id) THEN
    RAISE EXCEPTION 'the rating must come from this trip''s driver (actor % / %)', r, a USING ERRCODE = 'RH045';
  END IF;
  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.refund_enforce_total()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  p    payment%ROWTYPE;
  used bigint;
BEGIN
  SELECT * INTO p FROM payment WHERE id = NEW.payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;  -- the foreign key reports the missing payment
  END IF;
  IF p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'a refund needs a succeeded payment (status is %)', p.status USING ERRCODE = 'RH050';
  END IF;
  IF NEW.currency <> p.currency THEN
    RAISE EXCEPTION 'refund currency % differs from payment currency %', NEW.currency, p.currency USING ERRCODE = 'RH051';
  END IF;
  SELECT COALESCE(sum(amount_minor), 0) INTO used FROM refund WHERE payment_id = NEW.payment_id;
  IF used + NEW.amount_minor > p.amount_minor THEN
    RAISE EXCEPTION 'refunds % + % would exceed the payment amount % (B10)', used, NEW.amount_minor, p.amount_minor USING ERRCODE = 'RH052';
  END IF;
  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.setting_write_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  r text := nullif(current_setting('app.actor_role', true), '');
  a uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
BEGIN
  IF r IS DISTINCT FROM 'support' OR a IS NULL THEN
    RAISE EXCEPTION 'only a support actor may change a setting (actor % / %)', r, a USING ERRCODE = 'RH060';
  END IF;
  INSERT INTO audit_log (actor_role, actor_admin_id, action, entity_type, entity_id, details)
  VALUES ('support', a, 'setting_change', 'setting', NULL,
          jsonb_build_object('key', NEW.key,
                             'from', CASE WHEN TG_OP = 'UPDATE' THEN OLD.int_value END,
                             'to', NEW.int_value));
  RETURN NULL;
END
$function$
;

CREATE OR REPLACE FUNCTION public.trip_block_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION 'trips are never deleted (B4, B5)' USING ERRCODE = 'RH016';
END
$function$
;

CREATE OR REPLACE FUNCTION public.trip_enforce_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  r        text := nullif(current_setting('app.actor_role', true), '');
  a        uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  q        fare_quote%ROWTYPE;
  fee      bigint;
  allowed  text[];
  diff     text[];
  erasure_cols CONSTANT text[] := ARRAY['updated_at','pickup_address','dropoff_address',
                                        'driver_name_snapshot','vehicle_plate_snapshot'];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'requested' THEN
      RAISE EXCEPTION 'a new trip must start as requested (A1), not %', NEW.status USING ERRCODE = 'RH002';
    END IF;
    IF NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.cancelled_at IS NOT NULL THEN
      RAISE EXCEPTION 'a new trip cannot carry start, end or cancel times' USING ERRCODE = 'RH003';
    END IF;
    IF r IS DISTINCT FROM 'rider' OR a IS DISTINCT FROM NEW.rider_id THEN
      RAISE EXCEPTION 'only the rider may request a trip (actor % / %)', r, a USING ERRCODE = 'RH001';
    END IF;
    SELECT * INTO q FROM fare_quote WHERE id = NEW.fare_quote_id;
    IF FOUND AND q.expires_at < now() THEN
      RAISE EXCEPTION 'fare quote % has expired', q.id USING ERRCODE = 'RH004';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status IN ('completed','cancelled') THEN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
      IF current_user = 'ridehail_erasure_owner'
         AND (to_jsonb(NEW) - erasure_cols) = (to_jsonb(OLD) - erasure_cols) THEN
        RETURN NEW;
      END IF;
      RAISE EXCEPTION 'trip is % (terminal): only updated_at may change (B4)', OLD.status USING ERRCODE = 'RH005';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.driver_id IS NOT NULL AND NEW.driver_id IS DISTINCT FROM OLD.driver_id THEN
    RAISE EXCEPTION 'driver_id cannot change once set (F10)' USING ERRCODE = 'RH006';
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    allowed := ARRAY['updated_at'];
  ELSE
    IF r IS NULL THEN
      RAISE EXCEPTION 'app.actor_role is not set' USING ERRCODE = 'RH007';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM status_transition_rule
                   WHERE entity = 'trip' AND from_status = OLD.status
                     AND to_status = NEW.status AND actor_role = r) THEN
      RAISE EXCEPTION 'illegal transition % -> % by %', OLD.status, NEW.status, r USING ERRCODE = 'RH008';
    END IF;
    IF r = 'rider'  AND a IS DISTINCT FROM NEW.rider_id  THEN RAISE EXCEPTION 'actor is not this trip''s rider (F9)' USING ERRCODE = 'RH009'; END IF;
    IF r = 'driver' AND a IS DISTINCT FROM NEW.driver_id THEN RAISE EXCEPTION 'actor is not this trip''s driver (F9)' USING ERRCODE = 'RH010'; END IF;
    IF r = 'support' AND a IS NULL THEN RAISE EXCEPTION 'a support actor id is required' USING ERRCODE = 'RH011'; END IF;

    CASE NEW.status
      WHEN 'assigned' THEN
        IF NEW.vehicle_id IS NULL THEN RAISE EXCEPTION 'a vehicle is required to assign a trip' USING ERRCODE = 'RH012'; END IF;
        SELECT full_name    INTO NEW.driver_name_snapshot  FROM driver  WHERE id = NEW.driver_id;
        SELECT plate_number INTO NEW.vehicle_plate_snapshot FROM vehicle WHERE id = NEW.vehicle_id;
        allowed := ARRAY['status','updated_at','driver_id','vehicle_id','driver_name_snapshot','vehicle_plate_snapshot'];
      WHEN 'arrived' THEN
        allowed := ARRAY['status','updated_at'];
      WHEN 'started' THEN
        NEW.started_at := now();
        allowed := ARRAY['status','updated_at','started_at'];
      WHEN 'completed' THEN
        NEW.completed_at := now();
        allowed := ARRAY['status','updated_at','completed_at','fare_amount_minor','fare_currency','distance_m'];
      WHEN 'cancelled' THEN
        NEW.cancelled_at := now();
        NEW.cancelled_by_role := r;
        IF r = 'rider' AND OLD.status IN ('assigned','arrived') THEN
          SELECT int_value INTO fee FROM setting WHERE key = 'cancellation_fee_minor';
          IF fee IS NULL THEN RAISE EXCEPTION 'setting cancellation_fee_minor is missing' USING ERRCODE = 'RH013'; END IF;
        ELSE
          fee := 0;
        END IF;
        NEW.cancellation_fee_minor := fee;
        NEW.cancellation_fee_currency := 'NGN';
        allowed := ARRAY['status','updated_at','cancelled_at','cancelled_by_role',
                         'cancellation_fee_minor','cancellation_fee_currency'];
      ELSE
        RAISE EXCEPTION 'unexpected target status %', NEW.status USING ERRCODE = 'RH014';
    END CASE;
  END IF;

  SELECT array_agg(k) INTO diff
  FROM jsonb_object_keys(to_jsonb(NEW)) AS k
  WHERE (to_jsonb(NEW) -> k) IS DISTINCT FROM (to_jsonb(OLD) -> k);
  IF diff IS NOT NULL AND NOT (diff <@ allowed) THEN
    RAISE EXCEPTION 'these columns may not change in this move: %', diff USING ERRCODE = 'RH015';
  END IF;
  RETURN NEW;
END
$function$;
\echo '=== catalogue after the migration, same transaction'
-- Migration 015 catalogue snapshot (read only). Run before and after; diff the two outputs.
-- Part 1: every function in public: owner, SECURITY DEFINER, settings (search_path), ACL, attributes.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS definer,
       coalesce(array_to_string(p.proconfig, ','), '') AS settings, coalesce(p.proacl::text, '(default)') AS acl,
       p.provolatile, p.proleakproof, p.proisstrict, p.proparallel, l.lanname, pg_get_function_result(p.oid) AS returns
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'public' ORDER BY p.proname;
-- Part 2: every trigger: table, function, enabled state, full definition.
SELECT c.relname AS tbl, t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) AS def
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid WHERE NOT t.tgisinternal ORDER BY c.relname, t.tgname;
-- Part 3: function body with every USING ERRCODE = 'RHnnn' removed, as a hash. Equal before and after = text, logic and messages unchanged.
SELECT p.proname, md5(regexp_replace(p.prosrc, ' USING ERRCODE = ''RH[0-9]{3}''', '', 'g')) AS body_without_errcode_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' ORDER BY p.proname;
-- Part 4: number of RAISE statements and of ERRCODE clauses per function.
SELECT p.proname, (length(p.prosrc) - length(replace(lower(p.prosrc), 'raise exception', ''))) / 15 AS raise_exceptions,
       (length(p.prosrc) - length(replace(p.prosrc, 'USING ERRCODE', ''))) / 13 AS errcodes
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.prosrc ILIKE '%raise exception%' ORDER BY p.proname;
-- Part 5: roles and database ACL.
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname LIKE 'ridehail%' ORDER BY 1;
SELECT datacl FROM pg_database WHERE datname = 'ridehail_design';
\echo '=== D1 trip_finished (RH005): driver 1 moves completed trip 01 to started'
SAVEPOINT s1; SET LOCAL ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000001',true);
UPDATE trip SET status='started' WHERE id='eeeeeeee-0000-0000-0000-000000000001';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK TO s1;
\echo '=== D2 refund_exceeds_payment (RH052)'
SAVEPOINT s2; SET LOCAL ROLE ridehail_app; SELECT current_user AS cu;
SELECT set_config('app.actor_role','support',true), set_config('app.actor_id','dddddddd-0000-0000-0000-000000000001',true);
INSERT INTO refund (payment_id, amount_minor, currency, reason, created_by_admin_id, provider_reference)
SELECT id, 250000, 'NGN', 'too much', 'dddddddd-0000-0000-0000-000000000001', 'RF-X-1' FROM payment WHERE provider_reference='PRV-T01-A';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK TO s2;
\echo '=== D3 person_has_active_trip (RH071): erase_rider for rider 2'
SAVEPOINT s3; SET LOCAL ROLE ridehail_app; SELECT current_user AS cu;
SELECT erase_rider('aaaaaaaa-0000-0000-0000-000000000002');
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK TO s3;
\echo '=== D4 a normal move still works after the migration: rider 1 trip history untouched, a real accept-like check is in the full re-run after apply'
ROLLBACK;
\echo '=== after ROLLBACK: errcodes in the live function bodies (expect 0)'
SELECT count(*) AS live_errcode_clauses FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosrc LIKE '%USING ERRCODE%';
