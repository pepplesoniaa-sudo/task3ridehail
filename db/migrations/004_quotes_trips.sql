-- 004 quotes and trips: fare_quote, trip, trip_status_history, audit_log and their triggers
-- Serves: A1, A2, A3, B0, B1, B2, B3, B4, B5, B8, B9 (docs 02 entities 4, 5, 7, 14; 03 sections 2, 3, 5).
--
-- Session settings the application must set (docs 03 section 5): app.actor_role (rider, driver,
-- support, provider, system) and app.actor_id (uuid of the actor; empty for system and provider).
-- The database checks that the CLAIMED actor may make the move. It cannot prove who the actor is.

-- ---------------------------------------------------------------- fare_quote (A1, B3)
CREATE TABLE fare_quote (
  id                    uuid          NOT NULL DEFAULT gen_random_uuid(),
  rider_id              uuid          NOT NULL,
  pickup_latitude       numeric(8,6)  NOT NULL,
  pickup_longitude      numeric(9,6)  NOT NULL,
  dropoff_latitude      numeric(8,6)  NOT NULL,
  dropoff_longitude     numeric(9,6)  NOT NULL,
  estimated_distance_m  integer       NOT NULL,
  estimated_duration_s  integer       NOT NULL,
  amount_minor          bigint        NOT NULL,
  currency              char(3)       NOT NULL,
  expires_at            timestamptz   NOT NULL,
  created_at            timestamptz   NOT NULL DEFAULT now(),
  updated_at            timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT fare_quote_pkey PRIMARY KEY (id),
  -- helper unique so that trip can point at the pair (id, rider_id): a quote belongs to the trip's rider (A1)
  CONSTRAINT fare_quote_id_rider_id_key UNIQUE (id, rider_id),
  CONSTRAINT quote_rider_id_fkey FOREIGN KEY (rider_id) REFERENCES rider (id) ON DELETE RESTRICT,
  CONSTRAINT quote_amount_not_negative CHECK (amount_minor >= 0),
  CONSTRAINT quote_currency_ngn CHECK (currency = 'NGN'),
  CONSTRAINT quote_coordinates_valid CHECK (
    pickup_latitude  BETWEEN -90 AND 90  AND dropoff_latitude  BETWEEN -90 AND 90 AND
    pickup_longitude BETWEEN -180 AND 180 AND dropoff_longitude BETWEEN -180 AND 180),
  CONSTRAINT quote_estimates_not_negative CHECK (estimated_distance_m >= 0 AND estimated_duration_s >= 0),
  CONSTRAINT quote_expires_after_created CHECK (expires_at > created_at)
);
CREATE TRIGGER append_only_guard BEFORE UPDATE OR DELETE ON fare_quote
  FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- ---------------------------------------------------------------- trip (A1 to A4, B0 to B5, B9)
CREATE TABLE trip (
  id                         uuid          NOT NULL DEFAULT gen_random_uuid(),
  rider_id                   uuid          NOT NULL,
  driver_id                  uuid,
  vehicle_id                 uuid,
  fare_quote_id              uuid          NOT NULL,
  status                     text          NOT NULL DEFAULT 'requested',
  pickup_address             text          NOT NULL,
  dropoff_address            text          NOT NULL,
  driver_name_snapshot       text,          -- HISTORY snapshot at assignment (docs 04 question 1)
  vehicle_plate_snapshot     text,          -- HISTORY snapshot at assignment
  started_at                 timestamptz,   -- derived copy of the history time
  completed_at               timestamptz,   -- derived copy
  cancelled_at               timestamptz,   -- derived copy
  cancelled_by_role          text,
  cancellation_fee_minor     bigint,        -- HISTORY snapshot of the setting at cancellation (B9)
  cancellation_fee_currency  char(3),
  fare_amount_minor          bigint,
  fare_currency              char(3),
  distance_m                 integer,
  created_at                 timestamptz   NOT NULL DEFAULT now(),
  updated_at                 timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT trip_pkey PRIMARY KEY (id),
  CONSTRAINT trip_fare_quote_id_key UNIQUE (fare_quote_id),
  CONSTRAINT trip_rider_id_fkey  FOREIGN KEY (rider_id)  REFERENCES rider (id)  ON DELETE RESTRICT,
  CONSTRAINT trip_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES driver (id) ON DELETE RESTRICT,
  CONSTRAINT trip_vehicle_belongs_to_driver FOREIGN KEY (vehicle_id, driver_id)
    REFERENCES vehicle (id, driver_id) ON DELETE RESTRICT,
  CONSTRAINT trip_quote_belongs_to_rider FOREIGN KEY (fare_quote_id, rider_id)
    REFERENCES fare_quote (id, rider_id) ON DELETE RESTRICT,
  CONSTRAINT trip_status_valid CHECK (status IN ('requested','assigned','arrived','started','completed','cancelled')),
  CONSTRAINT trip_driver_matches_status CHECK (
    (status <> 'requested' OR driver_id IS NULL) AND
    (status NOT IN ('assigned','arrived','started','completed') OR driver_id IS NOT NULL)),
  CONSTRAINT trip_snapshots_match_assignment CHECK (
    (driver_id IS NULL) = (vehicle_id IS NULL) AND
    (driver_id IS NULL) = (driver_name_snapshot IS NULL) AND
    (vehicle_id IS NULL) = (vehicle_plate_snapshot IS NULL)),
  CONSTRAINT trip_started_has_time CHECK (status NOT IN ('started','completed') OR started_at IS NOT NULL),
  CONSTRAINT trip_completed_has_facts CHECK (
    (status = 'completed' AND completed_at IS NOT NULL AND fare_amount_minor IS NOT NULL
       AND fare_currency IS NOT NULL AND distance_m IS NOT NULL)
    OR
    (status <> 'completed' AND completed_at IS NULL AND fare_amount_minor IS NULL
       AND fare_currency IS NULL AND distance_m IS NULL)),
  CONSTRAINT trip_cancelled_has_facts CHECK (
    (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancelled_by_role IS NOT NULL
       AND cancellation_fee_minor IS NOT NULL AND cancellation_fee_currency IS NOT NULL)
    OR
    (status <> 'cancelled' AND cancelled_at IS NULL AND cancelled_by_role IS NULL
       AND cancellation_fee_minor IS NULL AND cancellation_fee_currency IS NULL)),
  CONSTRAINT trip_cancelled_by_valid CHECK (
    cancelled_by_role IS NULL OR cancelled_by_role IN ('rider','driver','support','system')),
  CONSTRAINT trip_times_in_order CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at),
  CONSTRAINT trip_amounts_not_negative CHECK (
    (fare_amount_minor IS NULL OR fare_amount_minor >= 0) AND
    (cancellation_fee_minor IS NULL OR cancellation_fee_minor >= 0) AND
    (distance_m IS NULL OR distance_m >= 0)),
  CONSTRAINT trip_currency_ngn CHECK (
    (fare_currency IS NULL OR fare_currency = 'NGN') AND
    (cancellation_fee_currency IS NULL OR cancellation_fee_currency = 'NGN')),
  CONSTRAINT trip_fee_needs_driver CHECK (
    cancellation_fee_minor IS NULL OR cancellation_fee_minor = 0 OR driver_id IS NOT NULL),
  CONSTRAINT trip_fee_only_when_rider_cancels CHECK (
    cancellation_fee_minor IS NULL OR cancellation_fee_minor = 0 OR cancelled_by_role = 'rider')
);

-- B0, B1, B2: ACTIVE means requested, assigned, arrived, started. A trip with no driver (driver_id empty)
-- never collides in the driver index, so it counts for the rider only.
CREATE UNIQUE INDEX trip_one_active_per_rider ON trip (rider_id)
  WHERE status IN ('requested','assigned','arrived','started');
CREATE UNIQUE INDEX trip_one_active_per_driver ON trip (driver_id)
  WHERE status IN ('requested','assigned','arrived','started');

-- ---------------------------------------------------------------- trip_status_history (B5)
CREATE TABLE trip_status_history (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  trip_id          uuid        NOT NULL,
  from_status      text,
  to_status        text        NOT NULL,
  actor_role       text        NOT NULL,
  actor_rider_id   uuid,
  actor_driver_id  uuid,
  actor_admin_id   uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trip_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT history_trip_id_fkey      FOREIGN KEY (trip_id)         REFERENCES trip (id)          ON DELETE RESTRICT,
  CONSTRAINT history_actor_rider_fkey  FOREIGN KEY (actor_rider_id)  REFERENCES rider (id)         ON DELETE RESTRICT,
  CONSTRAINT history_actor_driver_fkey FOREIGN KEY (actor_driver_id) REFERENCES driver (id)        ON DELETE RESTRICT,
  CONSTRAINT history_actor_admin_fkey  FOREIGN KEY (actor_admin_id)  REFERENCES support_admin (id) ON DELETE RESTRICT,
  CONSTRAINT history_to_status_valid CHECK (to_status IN ('requested','assigned','arrived','started','completed','cancelled')),
  CONSTRAINT history_from_status_valid CHECK (
    from_status IS NULL OR from_status IN ('requested','assigned','arrived','started','completed','cancelled')),
  CONSTRAINT history_status_changes CHECK (from_status IS NULL OR from_status <> to_status),
  CONSTRAINT history_first_row_is_requested CHECK (from_status IS NOT NULL OR to_status = 'requested'),
  CONSTRAINT history_actor_matches_role CHECK (
    (actor_role = 'rider'   AND actor_rider_id IS NOT NULL AND actor_driver_id IS NULL     AND actor_admin_id IS NULL) OR
    (actor_role = 'driver'  AND actor_driver_id IS NOT NULL AND actor_rider_id IS NULL     AND actor_admin_id IS NULL) OR
    (actor_role = 'support' AND actor_admin_id IS NOT NULL AND actor_rider_id IS NULL      AND actor_driver_id IS NULL) OR
    (actor_role = 'system'  AND actor_rider_id IS NULL     AND actor_driver_id IS NULL     AND actor_admin_id IS NULL))
);
CREATE TRIGGER append_only_guard BEFORE UPDATE OR DELETE ON trip_status_history
  FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- ---------------------------------------------------------------- audit_log (B5, B4, U3)
CREATE TABLE audit_log (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  actor_role       text        NOT NULL,
  actor_rider_id   uuid,
  actor_driver_id  uuid,
  actor_admin_id   uuid,
  action           text        NOT NULL,
  entity_type      text        NOT NULL,
  entity_id        uuid,
  note             text,        -- the rule "no card data or secrets" is application validation only
  details          jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_log_pkey PRIMARY KEY (id),
  CONSTRAINT audit_actor_rider_fkey  FOREIGN KEY (actor_rider_id)  REFERENCES rider (id)         ON DELETE RESTRICT,
  CONSTRAINT audit_actor_driver_fkey FOREIGN KEY (actor_driver_id) REFERENCES driver (id)        ON DELETE RESTRICT,
  CONSTRAINT audit_actor_admin_fkey  FOREIGN KEY (actor_admin_id)  REFERENCES support_admin (id) ON DELETE RESTRICT,
  CONSTRAINT audit_actor_matches_role CHECK (
    (actor_role = 'rider'    AND actor_rider_id IS NOT NULL AND actor_driver_id IS NULL     AND actor_admin_id IS NULL) OR
    (actor_role = 'driver'   AND actor_driver_id IS NOT NULL AND actor_rider_id IS NULL     AND actor_admin_id IS NULL) OR
    (actor_role = 'support'  AND actor_admin_id IS NOT NULL AND actor_rider_id IS NULL      AND actor_driver_id IS NULL) OR
    (actor_role IN ('provider','system') AND actor_rider_id IS NULL AND actor_driver_id IS NULL AND actor_admin_id IS NULL)),
  -- DEVIATION from docs 02/04: 'provider_event' is added to the list, because a provider message about an
  -- unknown reference has no payment or refund to cite (docs 03 section 4a step 4 requires an audit note).
  CONSTRAINT audit_entity_type_valid CHECK (
    entity_type IN ('trip','payment','refund','rating','rider','driver','setting','provider_event')),
  CONSTRAINT audit_entity_id_matches_type CHECK ((entity_id IS NULL) = (entity_type = 'setting'))
);
CREATE TRIGGER append_only_guard BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- ---------------------------------------------------------------- trip_enforce_transition (B1 to B5, B8, B9)
-- BEFORE INSERT OR UPDATE on trip. Does, in order:
--  insert:  new trip must be requested, by its rider, on an unexpired quote (A1).
--  terminal rows (completed, cancelled): only updated_at may change (B4). One exception: when
--           current_user is ridehail_erasure_owner, five text columns may change (B8, docs 04 question 4).
--  other rows: rider and quote never change, the driver is set once, a status change must have a row in
--           status_transition_rule for the claimed actor and the actor must be the right person; the
--           derived columns (snapshots, times, cancellation fee) are written HERE, not by the application;
--           only the columns that belong to the move may change.
CREATE FUNCTION trip_enforce_transition() RETURNS trigger
LANGUAGE plpgsql AS $fn$
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
      RAISE EXCEPTION 'a new trip must start as requested (A1), not %', NEW.status;
    END IF;
    IF NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.cancelled_at IS NOT NULL THEN
      RAISE EXCEPTION 'a new trip cannot carry start, end or cancel times';
    END IF;
    IF r IS DISTINCT FROM 'rider' OR a IS DISTINCT FROM NEW.rider_id THEN
      RAISE EXCEPTION 'only the rider may request a trip (actor % / %)', r, a;
    END IF;
    SELECT * INTO q FROM fare_quote WHERE id = NEW.fare_quote_id;
    IF FOUND AND q.expires_at < now() THEN
      RAISE EXCEPTION 'fare quote % has expired', q.id;
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
      RAISE EXCEPTION 'trip is % (terminal): only updated_at may change (B4)', OLD.status;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.driver_id IS NOT NULL AND NEW.driver_id IS DISTINCT FROM OLD.driver_id THEN
    RAISE EXCEPTION 'driver_id cannot change once set (F10)';
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    allowed := ARRAY['updated_at'];
  ELSE
    IF r IS NULL THEN
      RAISE EXCEPTION 'app.actor_role is not set';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM status_transition_rule
                   WHERE entity = 'trip' AND from_status = OLD.status
                     AND to_status = NEW.status AND actor_role = r) THEN
      RAISE EXCEPTION 'illegal transition % -> % by %', OLD.status, NEW.status, r;
    END IF;
    IF r = 'rider'  AND a IS DISTINCT FROM NEW.rider_id  THEN RAISE EXCEPTION 'actor is not this trip''s rider (F9)'; END IF;
    IF r = 'driver' AND a IS DISTINCT FROM NEW.driver_id THEN RAISE EXCEPTION 'actor is not this trip''s driver (F9)'; END IF;
    IF r = 'support' AND a IS NULL THEN RAISE EXCEPTION 'a support actor id is required'; END IF;

    CASE NEW.status
      WHEN 'assigned' THEN
        IF NEW.vehicle_id IS NULL THEN RAISE EXCEPTION 'a vehicle is required to assign a trip'; END IF;
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
          IF fee IS NULL THEN RAISE EXCEPTION 'setting cancellation_fee_minor is missing'; END IF;
        ELSE
          fee := 0;
        END IF;
        NEW.cancellation_fee_minor := fee;
        NEW.cancellation_fee_currency := 'NGN';
        allowed := ARRAY['status','updated_at','cancelled_at','cancelled_by_role',
                         'cancellation_fee_minor','cancellation_fee_currency'];
      ELSE
        RAISE EXCEPTION 'unexpected target status %', NEW.status;
    END CASE;
  END IF;

  SELECT array_agg(k) INTO diff
  FROM jsonb_object_keys(to_jsonb(NEW)) AS k
  WHERE (to_jsonb(NEW) -> k) IS DISTINCT FROM (to_jsonb(OLD) -> k);
  IF diff IS NOT NULL AND NOT (diff <@ allowed) THEN
    RAISE EXCEPTION 'these columns may not change in this move: %', diff;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER trip_enforce_transition BEFORE INSERT OR UPDATE ON trip
  FOR EACH ROW EXECUTE FUNCTION trip_enforce_transition();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON trip
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------- trip_write_history (B5)
CREATE FUNCTION trip_write_history() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  r text := nullif(current_setting('app.actor_role', true), '');
  a uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;
  INSERT INTO trip_status_history
    (trip_id, from_status, to_status, actor_role, actor_rider_id, actor_driver_id, actor_admin_id)
  VALUES
    (NEW.id,
     CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
     NEW.status, r,
     CASE WHEN r = 'rider'   THEN a END,
     CASE WHEN r = 'driver'  THEN a END,
     CASE WHEN r = 'support' THEN a END);
  RETURN NULL;
END
$fn$;
CREATE TRIGGER trip_write_history AFTER INSERT OR UPDATE ON trip
  FOR EACH ROW EXECUTE FUNCTION trip_write_history();

-- ---------------------------------------------------------------- trip_block_delete (B4, B5)
CREATE FUNCTION trip_block_delete() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'trips are never deleted (B4, B5)';
END
$fn$;
CREATE TRIGGER trip_block_delete BEFORE DELETE ON trip
  FOR EACH ROW EXECUTE FUNCTION trip_block_delete();

-- ---------------------------------------------------------------- setting_write_audit (B9, U3)
-- Setting changes are written to audit_log (docs 04 question 4). Only support may change a setting
-- (assumption: docs say changes are audited and the audit actor must be an admin).
CREATE FUNCTION setting_write_audit() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  r text := nullif(current_setting('app.actor_role', true), '');
  a uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
BEGIN
  IF r IS DISTINCT FROM 'support' OR a IS NULL THEN
    RAISE EXCEPTION 'only a support actor may change a setting (actor % / %)', r, a;
  END IF;
  INSERT INTO audit_log (actor_role, actor_admin_id, action, entity_type, entity_id, details)
  VALUES ('support', a, 'setting_change', 'setting', NULL,
          jsonb_build_object('key', NEW.key,
                             'from', CASE WHEN TG_OP = 'UPDATE' THEN OLD.int_value END,
                             'to', NEW.int_value));
  RETURN NULL;
END
$fn$;
CREATE TRIGGER setting_write_audit AFTER INSERT OR UPDATE ON setting
  FOR EACH ROW EXECUTE FUNCTION setting_write_audit();
