-- 006 the rest: rating, idempotency_key, location_ping, and the two erasure functions
-- Serves: A3, A5, B6, B7, B8 (docs 02 entities 6, 10, 11; 04 questions 1, 4, 6).

-- ---------------------------------------------------------------- rating (A5, B7)
CREATE TABLE rating (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  trip_id     uuid        NOT NULL,
  rater_role  text        NOT NULL,
  stars       smallint    NOT NULL,
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rating_pkey PRIMARY KEY (id),
  CONSTRAINT rating_one_per_role_per_trip UNIQUE (trip_id, rater_role),
  CONSTRAINT rating_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES trip (id) ON DELETE RESTRICT,
  CONSTRAINT rating_role_valid CHECK (rater_role IN ('rider','driver')),
  CONSTRAINT rating_stars_range CHECK (stars BETWEEN 1 AND 5),
  CONSTRAINT rating_comment_length CHECK (comment IS NULL OR char_length(comment) <= 500)
);

-- B7: the trip must be completed, the rating must come inside rating_window_days of completion, and the
-- claimed actor must be that side of the trip.
CREATE FUNCTION rating_enforce_rules() RETURNS trigger
LANGUAGE plpgsql AS $fn$
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
    RAISE EXCEPTION 'a rating needs a completed trip (status is %) (B7)', t.status;
  END IF;
  SELECT int_value INTO win FROM setting WHERE key = 'rating_window_days';
  IF win IS NULL THEN
    RAISE EXCEPTION 'setting rating_window_days is missing';
  END IF;
  IF now() > t.completed_at + make_interval(days => win::int) THEN
    RAISE EXCEPTION 'the rating window of % days has passed (B7)', win;
  END IF;
  IF NEW.rater_role = 'rider'  AND (r IS DISTINCT FROM 'rider'  OR a IS DISTINCT FROM t.rider_id) THEN
    RAISE EXCEPTION 'the rating must come from this trip''s rider (actor % / %)', r, a;
  END IF;
  IF NEW.rater_role = 'driver' AND (r IS DISTINCT FROM 'driver' OR a IS DISTINCT FROM t.driver_id) THEN
    RAISE EXCEPTION 'the rating must come from this trip''s driver (actor % / %)', r, a;
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER rating_enforce_rules BEFORE INSERT ON rating
  FOR EACH ROW EXECUTE FUNCTION rating_enforce_rules();

-- SPEED cache (docs 04 question 1): add the stars to the OTHER person's totals, in the same transaction.
CREATE FUNCTION rating_update_cache() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  t trip%ROWTYPE;
BEGIN
  SELECT * INTO t FROM trip WHERE id = NEW.trip_id;
  IF NEW.rater_role = 'rider' THEN
    UPDATE driver SET rating_sum = rating_sum + NEW.stars, rating_count = rating_count + 1 WHERE id = t.driver_id;
  ELSE
    UPDATE rider  SET rating_sum = rating_sum + NEW.stars, rating_count = rating_count + 1 WHERE id = t.rider_id;
  END IF;
  RETURN NULL;
END
$fn$;
CREATE TRIGGER rating_update_cache AFTER INSERT ON rating
  FOR EACH ROW EXECUTE FUNCTION rating_update_cache();

-- Ratings are never edited or deleted. Exception (B8): when current_user is ridehail_erasure_owner, the
-- comment column alone may change (blanked by erase_rider / erase_driver).
CREATE FUNCTION rating_block_change() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF TG_OP = 'UPDATE' AND current_user = 'ridehail_erasure_owner'
     AND (to_jsonb(NEW) - ARRAY['comment','updated_at']) = (to_jsonb(OLD) - ARRAY['comment','updated_at']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'rating is append-only: % is not allowed (current_user is %)', TG_OP, current_user;
END
$fn$;
CREATE TRIGGER rating_block_change BEFORE UPDATE OR DELETE ON rating
  FOR EACH ROW EXECUTE FUNCTION rating_block_change();

-- ---------------------------------------------------------------- idempotency_key (A1, A4, B6)
CREATE TABLE idempotency_key (
  id               uuid        NOT NULL DEFAULT gen_random_uuid(),
  rider_id         uuid        NOT NULL,
  action           text        NOT NULL,
  key              text        NOT NULL,
  request_hash     text        NOT NULL,
  response_status  smallint,
  response_body    jsonb,
  trip_id          uuid,
  payment_id       uuid,
  expires_at       timestamptz NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT idempotency_key_pkey PRIMARY KEY (id),
  -- B6: unique per rider AND action, not global
  CONSTRAINT idem_one_key_per_rider_action UNIQUE (rider_id, action, key),
  CONSTRAINT idem_rider_id_fkey   FOREIGN KEY (rider_id)   REFERENCES rider (id)   ON DELETE RESTRICT,
  CONSTRAINT idem_trip_id_fkey    FOREIGN KEY (trip_id)    REFERENCES trip (id)    ON DELETE RESTRICT,
  CONSTRAINT idem_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES payment (id) ON DELETE RESTRICT,
  CONSTRAINT idem_action_valid CHECK (action IN ('request_trip','pay_trip')),
  CONSTRAINT idem_key_length CHECK (char_length(key) BETWEEN 1 AND 128),
  CONSTRAINT idem_hash_format CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT idem_response_complete CHECK ((response_status IS NULL) = (response_body IS NULL))
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON idempotency_key
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------- location_ping (A3, B8)
CREATE TABLE location_ping (
  id           uuid          NOT NULL DEFAULT gen_random_uuid(),
  trip_id      uuid          NOT NULL,
  latitude     numeric(8,6)  NOT NULL,
  longitude    numeric(9,6)  NOT NULL,
  accuracy_m   integer,
  recorded_at  timestamptz   NOT NULL,
  created_at   timestamptz   NOT NULL DEFAULT now(),
  updated_at   timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT location_ping_pkey PRIMARY KEY (id),
  CONSTRAINT ping_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES trip (id) ON DELETE RESTRICT,
  CONSTRAINT ping_latitude_range CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ping_longitude_range CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT ping_accuracy_not_negative CHECK (accuracy_m IS NULL OR accuracy_m >= 0)
);

CREATE FUNCTION ping_enforce_trip_status() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  s text;
BEGIN
  SELECT status INTO s FROM trip WHERE id = NEW.trip_id;
  IF FOUND AND s NOT IN ('assigned','arrived','started') THEN
    RAISE EXCEPTION 'a location ping needs a trip that is assigned, arrived or started (status is %)', s;
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER ping_enforce_trip_status BEFORE INSERT ON location_ping
  FOR EACH ROW EXECUTE FUNCTION ping_enforce_trip_status();
-- a ping is never edited; deleting it is allowed (retention, Q5)
CREATE TRIGGER append_only_guard BEFORE UPDATE ON location_ping
  FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- ---------------------------------------------------------------- erasure functions (B8, docs 04 question 4)
-- Owned by ridehail_erasure_owner (NOLOGIN, not a superuser). SECURITY DEFINER with a fixed search_path.
-- They refuse a person with an active trip. They blank personal text; they never touch money or times.
-- The owner needs CREATE on the schema only while creating the functions, so it is granted and revoked here.
GRANT CREATE ON SCHEMA public TO ridehail_erasure_owner;
SET LOCAL ROLE ridehail_erasure_owner;

CREATE FUNCTION erase_rider(p_rider uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM rider WHERE id = p_rider) THEN
    RAISE EXCEPTION 'rider % does not exist', p_rider;
  END IF;
  IF EXISTS (SELECT 1 FROM trip WHERE rider_id = p_rider
             AND status IN ('requested','assigned','arrived','started')) THEN
    RAISE EXCEPTION 'rider % has an active trip: cannot erase (B8)', p_rider;
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
$fn$;

CREATE FUNCTION erase_driver(p_driver uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM driver WHERE id = p_driver) THEN
    RAISE EXCEPTION 'driver % does not exist', p_driver;
  END IF;
  IF EXISTS (SELECT 1 FROM trip WHERE driver_id = p_driver
             AND status IN ('assigned','arrived','started')) THEN
    RAISE EXCEPTION 'driver % has an active trip: cannot erase (B8)', p_driver;
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
$fn$;

RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM ridehail_erasure_owner;
