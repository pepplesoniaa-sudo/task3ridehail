-- 003 people: rider, driver, vehicle
-- Serves: U1, U2, A1, A2, B1, B2, B8 (docs 02 entities 1 to 3).

CREATE TABLE rider (
  id            uuid        NOT NULL DEFAULT gen_random_uuid(),
  full_name     text        NOT NULL,
  phone         text        NOT NULL,
  email         text,
  rating_sum    integer     NOT NULL DEFAULT 0,   -- SPEED cache (docs 04, question 1)
  rating_count  integer     NOT NULL DEFAULT 0,   -- SPEED cache
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rider_pkey PRIMARY KEY (id),
  CONSTRAINT rider_phone_key UNIQUE (phone),
  CONSTRAINT rider_phone_format CHECK (phone ~ '^\+[1-9][0-9]{7,14}$' OR deleted_at IS NOT NULL),
  CONSTRAINT rider_name_not_blank CHECK (length(btrim(full_name)) > 0),
  CONSTRAINT rider_rating_cache_valid CHECK (
    rating_count >= 0 AND rating_sum >= rating_count AND rating_sum <= 5 * rating_count)
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON rider
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE driver (
  id              uuid        NOT NULL DEFAULT gen_random_uuid(),
  full_name       text        NOT NULL,
  phone           text        NOT NULL,
  licence_number  text        NOT NULL,
  rating_sum      integer     NOT NULL DEFAULT 0,
  rating_count    integer     NOT NULL DEFAULT 0,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT driver_pkey PRIMARY KEY (id),
  CONSTRAINT driver_phone_key UNIQUE (phone),
  CONSTRAINT driver_licence_number_key UNIQUE (licence_number),
  CONSTRAINT driver_phone_format CHECK (phone ~ '^\+[1-9][0-9]{7,14}$' OR deleted_at IS NOT NULL),
  CONSTRAINT driver_name_not_blank CHECK (length(btrim(full_name)) > 0),
  CONSTRAINT driver_rating_cache_valid CHECK (
    rating_count >= 0 AND rating_sum >= rating_count AND rating_sum <= 5 * rating_count)
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON driver
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE vehicle (
  id            uuid        NOT NULL DEFAULT gen_random_uuid(),
  driver_id     uuid        NOT NULL,
  plate_number  text        NOT NULL,
  make          text        NOT NULL,
  model         text        NOT NULL,
  colour        text,
  seat_count    smallint    NOT NULL,
  is_active     boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_pkey PRIMARY KEY (id),
  -- helper unique so that trip can point at the pair (id, driver_id): a trip's car is its driver's car (A2)
  CONSTRAINT vehicle_id_driver_id_key UNIQUE (id, driver_id),
  CONSTRAINT vehicle_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES driver (id) ON DELETE RESTRICT,
  CONSTRAINT vehicle_seat_count_range CHECK (seat_count BETWEEN 1 AND 8),
  CONSTRAINT vehicle_plate_not_blank CHECK (length(btrim(plate_number)) > 0)
);
-- a plate is unique while the vehicle is not deleted (partial unique index; docs 04 question 6)
CREATE UNIQUE INDEX vehicle_plate_number_active_key ON vehicle (plate_number) WHERE deleted_at IS NULL;
CREATE TRIGGER set_updated_at BEFORE UPDATE ON vehicle
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
