-- 002 reference tables: support_admin, setting, status_transition_rule
-- Serves: U3, B3, B5, B7, B9 (docs 02 entities 12, 13, 15; 03 sections 2 and 4).

CREATE TABLE support_admin (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  full_name   text        NOT NULL,
  email       text        NOT NULL,
  is_active   boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT support_admin_pkey PRIMARY KEY (id),
  CONSTRAINT support_admin_email_key UNIQUE (email),
  CONSTRAINT support_admin_email_format CHECK (position('@' in email) > 1),
  CONSTRAINT support_admin_name_not_blank CHECK (length(btrim(full_name)) > 0)
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON support_admin
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- setting.int_value holds two kinds of value (docs 02): kobo for keys ending in _minor,
-- degrees x 1,000,000 for the service_area_*_e6 keys, plain counts for the rest.
CREATE TABLE setting (
  key                  text        NOT NULL,
  int_value            bigint      NOT NULL,
  currency             char(3),
  description          text        NOT NULL,
  updated_by_admin_id  uuid,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT setting_pkey PRIMARY KEY (key),
  CONSTRAINT setting_updated_by_fkey FOREIGN KEY (updated_by_admin_id)
    REFERENCES support_admin (id) ON DELETE RESTRICT,
  CONSTRAINT setting_value_not_negative CHECK (int_value >= 0),
  CONSTRAINT setting_currency_ngn CHECK (currency IS NULL OR currency = 'NGN'),
  CONSTRAINT setting_money_has_currency CHECK ((key LIKE '%\_minor') = (currency IS NOT NULL))
);
CREATE TRIGGER set_updated_at BEFORE UPDATE ON setting
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- status_transition_rule: one row per legal move for an actor (B5, B9). 14 trip rows, 3 payment rows.
CREATE TABLE status_transition_rule (
  entity       text        NOT NULL,
  from_status  text        NOT NULL,
  to_status    text        NOT NULL,
  actor_role   text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rule_pkey PRIMARY KEY (entity, from_status, to_status, actor_role),
  CONSTRAINT rule_entity_valid CHECK (entity IN ('trip', 'payment')),
  CONSTRAINT rule_actor_role_valid CHECK (actor_role IN ('rider', 'driver', 'support', 'provider', 'system')),
  CONSTRAINT rule_from_differs_to CHECK (from_status <> to_status)
);

INSERT INTO status_transition_rule (entity, from_status, to_status, actor_role) VALUES
  -- trip, docs 03 section 2
  ('trip', 'requested', 'assigned',  'driver'),    -- T1 (A2, B2)
  ('trip', 'assigned',  'arrived',   'driver'),    -- T2 (A3)
  ('trip', 'arrived',   'started',   'driver'),    -- T3 (A3)
  ('trip', 'started',   'completed', 'driver'),    -- T4 (A3, B4)
  ('trip', 'requested', 'cancelled', 'rider'),     -- T5 (B9)
  ('trip', 'requested', 'cancelled', 'support'),   -- T5 (B9)
  ('trip', 'assigned',  'cancelled', 'rider'),     -- T6 (B9)
  ('trip', 'assigned',  'cancelled', 'driver'),    -- T6 (B9)
  ('trip', 'assigned',  'cancelled', 'support'),   -- T6 (B9)
  ('trip', 'arrived',   'cancelled', 'rider'),     -- T7 (B9)
  ('trip', 'arrived',   'cancelled', 'driver'),    -- T7 (B9)
  ('trip', 'arrived',   'cancelled', 'support'),   -- T7 (B9)
  ('trip', 'started',   'cancelled', 'support'),   -- T8 (B9)
  ('trip', 'requested', 'cancelled', 'system'),    -- T9 (B9, B1) timeout
  -- payment, docs 03 section 4
  ('payment', 'pending', 'succeeded', 'provider'), -- P1 (A4)
  ('payment', 'pending', 'failed',    'provider'), -- P2 (A4)
  ('payment', 'pending', 'failed',    'support');  -- P3 (A4, B6) only with a payment_not_found event (trigger, migration 005)
