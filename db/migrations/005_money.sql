-- 005 money: payment, refund, provider_event and their triggers
-- Serves: U4, A4, B3, B5, B6, B10 (docs 02 entities 8, 9, 16; 03 sections 4, 4a, 4b).

-- ---------------------------------------------------------------- payment (A4, B3, B6)
CREATE TABLE payment (
  id                  uuid        NOT NULL DEFAULT gen_random_uuid(),
  trip_id             uuid        NOT NULL,
  purpose             text        NOT NULL,
  amount_minor        bigint      NOT NULL,
  currency            char(3)     NOT NULL,
  status              text        NOT NULL DEFAULT 'pending',
  provider_reference  text        NOT NULL,  -- required: a payment exists only after the provider returned it (docs 02)
  paid_at             timestamptz,
  failure_reason      text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_pkey PRIMARY KEY (id),
  CONSTRAINT payment_provider_reference_key UNIQUE (provider_reference),
  CONSTRAINT payment_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES trip (id) ON DELETE RESTRICT,
  CONSTRAINT payment_purpose_valid CHECK (purpose IN ('fare','cancellation_fee')),
  CONSTRAINT payment_status_valid CHECK (status IN ('pending','succeeded','failed')),
  CONSTRAINT payment_amount_positive CHECK (amount_minor > 0),
  CONSTRAINT payment_currency_ngn CHECK (currency = 'NGN'),
  CONSTRAINT payment_succeeded_has_proof CHECK (
    (status <> 'succeeded' OR (provider_reference IS NOT NULL AND paid_at IS NOT NULL))
    AND (paid_at IS NULL OR status = 'succeeded')),
  CONSTRAINT payment_failed_has_reason CHECK ((status = 'failed') = (failure_reason IS NOT NULL))
);
-- A4, B6: one live (pending or succeeded) payment per trip and purpose. A failed one does not block a retry.
CREATE UNIQUE INDEX payment_one_live_per_purpose ON payment (trip_id, purpose)
  WHERE status IN ('pending','succeeded');

-- ---------------------------------------------------------------- provider_event (U4, A4, B6)
CREATE TABLE provider_event (
  id                  uuid        NOT NULL DEFAULT gen_random_uuid(),
  provider_event_id   text        NOT NULL,
  provider_reference  text        NOT NULL,   -- matched by value to payment or refund, no foreign key (docs 02b R20)
  event_type          text        NOT NULL,
  amount_minor        bigint,
  currency            char(3),
  occurred_at         timestamptz,            -- the provider's own time; evidence only
  -- DEVIATION from docs 02 ("default now()"): clock_timestamp() gives each event its own moment even inside one
  -- transaction, which the P3 rule below needs to order events ("a later payment_succeeded cancels the proof").
  received_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  processed_at        timestamptz,
  outcome             text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_event_pkey PRIMARY KEY (id),
  CONSTRAINT provider_event_provider_event_id_key UNIQUE (provider_event_id),
  CONSTRAINT provider_event_type_valid CHECK (
    event_type IN ('payment_succeeded','payment_failed','payment_not_found','refund_succeeded')),
  CONSTRAINT provider_event_outcome_valid CHECK (
    outcome IS NULL OR outcome IN ('applied','ignored_duplicate','needs_support')),
  CONSTRAINT provider_event_amount_positive CHECK (amount_minor IS NULL OR amount_minor > 0),
  CONSTRAINT provider_event_currency_ngn CHECK (currency IS NULL OR currency = 'NGN'),
  CONSTRAINT provider_event_money_pair CHECK ((amount_minor IS NULL) = (currency IS NULL)),
  CONSTRAINT provider_event_processed_has_outcome CHECK ((processed_at IS NULL) = (outcome IS NULL))
);

-- ---------------------------------------------------------------- refund (B3, B4, B10, U3)
CREATE TABLE refund (
  id                    uuid        NOT NULL DEFAULT gen_random_uuid(),
  payment_id            uuid        NOT NULL,
  amount_minor          bigint      NOT NULL,
  currency              char(3)     NOT NULL,
  reason                text        NOT NULL,
  created_by_admin_id   uuid        NOT NULL,
  provider_reference    text        NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT refund_pkey PRIMARY KEY (id),
  CONSTRAINT refund_provider_reference_key UNIQUE (provider_reference),
  CONSTRAINT refund_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES payment (id) ON DELETE RESTRICT,
  CONSTRAINT refund_created_by_admin_fkey FOREIGN KEY (created_by_admin_id)
    REFERENCES support_admin (id) ON DELETE RESTRICT,
  CONSTRAINT refund_amount_positive CHECK (amount_minor > 0),
  CONSTRAINT refund_currency_ngn CHECK (currency = 'NGN'),
  CONSTRAINT refund_reason_not_blank CHECK (length(btrim(reason)) > 0)
);
CREATE TRIGGER append_only_guard BEFORE UPDATE OR DELETE ON refund
  FOR EACH ROW EXECUTE FUNCTION append_only_guard();

-- ---------------------------------------------------------------- payment_enforce_rules (A4, B3, B5, B6)
--  insert: only pending, only by the trip's rider, only for a completed trip's fare or a cancelled trip's
--          fee, and for exactly the amount owed.
--  terminal rows (succeeded, failed): only updated_at may change.
--  pending rows: a status change needs a row in status_transition_rule for the claimed actor (P1, P2, P3);
--          P3 (support fails a pending payment) also needs proof in provider_event: a payment_not_found event
--          for the same provider_reference, received after the payment was created, and not older than the
--          latest provider event of ANY type for that reference (a later payment_succeeded cancels the proof).
CREATE FUNCTION payment_enforce_rules() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  r        text := nullif(current_setting('app.actor_role', true), '');
  a        uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
  t        trip%ROWTYPE;
  allowed  text[];
  diff     text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending' THEN
      RAISE EXCEPTION 'a payment must be created as pending, not %', NEW.status;
    END IF;
    SELECT * INTO t FROM trip WHERE id = NEW.trip_id;
    IF NOT FOUND THEN
      RETURN NEW;  -- the foreign key reports the missing trip
    END IF;
    IF r IS DISTINCT FROM 'rider' OR a IS DISTINCT FROM t.rider_id THEN
      RAISE EXCEPTION 'only the trip''s rider may start a payment (actor % / %)', r, a;
    END IF;
    IF NEW.purpose = 'fare' THEN
      IF t.status <> 'completed' THEN
        RAISE EXCEPTION 'a fare payment needs a completed trip (status is %)', t.status;
      END IF;
      IF NEW.amount_minor <> t.fare_amount_minor THEN
        RAISE EXCEPTION 'payment amount % does not equal the trip fare %', NEW.amount_minor, t.fare_amount_minor;
      END IF;
    ELSIF NEW.purpose = 'cancellation_fee' THEN
      IF t.status <> 'cancelled' OR COALESCE(t.cancellation_fee_minor, 0) <= 0 THEN
        RAISE EXCEPTION 'a cancellation fee payment needs a cancelled trip with a fee above 0';
      END IF;
      IF NEW.amount_minor <> t.cancellation_fee_minor THEN
        RAISE EXCEPTION 'payment amount % does not equal the cancellation fee %', NEW.amount_minor, t.cancellation_fee_minor;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status IN ('succeeded','failed') THEN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
      RAISE EXCEPTION 'payment is % (terminal): only updated_at may change', OLD.status;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    allowed := ARRAY['updated_at'];
  ELSE
    IF r IS NULL THEN
      RAISE EXCEPTION 'app.actor_role is not set';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM status_transition_rule
                   WHERE entity = 'payment' AND from_status = OLD.status
                     AND to_status = NEW.status AND actor_role = r) THEN
      RAISE EXCEPTION 'illegal payment transition % -> % by %', OLD.status, NEW.status, r;
    END IF;
    IF r = 'support' THEN
      IF a IS NULL THEN
        RAISE EXCEPTION 'a support actor id is required';
      END IF;
      IF NOT EXISTS (
           SELECT 1 FROM provider_event e
           WHERE e.provider_reference = OLD.provider_reference
             AND e.event_type = 'payment_not_found'
             AND e.received_at >= OLD.created_at
             AND e.received_at >= (SELECT max(x.received_at) FROM provider_event x
                                   WHERE x.provider_reference = OLD.provider_reference)) THEN
        RAISE EXCEPTION 'support may fail a pending payment only after a payment_not_found event for this reference, received after the payment was created and not superseded by a later event (P3)';
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
    RAISE EXCEPTION 'these payment columns may not change in this move: %', diff;
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER payment_enforce_rules BEFORE INSERT OR UPDATE ON payment
  FOR EACH ROW EXECUTE FUNCTION payment_enforce_rules();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON payment
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------- payment_write_audit (B5)
CREATE FUNCTION payment_write_audit() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  r text := nullif(current_setting('app.actor_role', true), '');
  a uuid := nullif(current_setting('app.actor_id', true), '')::uuid;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;
  INSERT INTO audit_log (actor_role, actor_rider_id, actor_driver_id, actor_admin_id,
                         action, entity_type, entity_id, details)
  VALUES (r,
          CASE WHEN r = 'rider'   THEN a END,
          CASE WHEN r = 'driver'  THEN a END,
          CASE WHEN r = 'support' THEN a END,
          'status_change', 'payment', NEW.id,
          jsonb_build_object('from', OLD.status, 'to', NEW.status));
  RETURN NULL;
END
$fn$;
CREATE TRIGGER payment_write_audit AFTER UPDATE ON payment
  FOR EACH ROW EXECUTE FUNCTION payment_write_audit();

-- ---------------------------------------------------------------- refund_enforce_total (B10)
-- Locks the payment row so two refunds at the same moment wait for each other.
CREATE FUNCTION refund_enforce_total() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  p    payment%ROWTYPE;
  used bigint;
BEGIN
  SELECT * INTO p FROM payment WHERE id = NEW.payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;  -- the foreign key reports the missing payment
  END IF;
  IF p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'a refund needs a succeeded payment (status is %)', p.status;
  END IF;
  IF NEW.currency <> p.currency THEN
    RAISE EXCEPTION 'refund currency % differs from payment currency %', NEW.currency, p.currency;
  END IF;
  SELECT COALESCE(sum(amount_minor), 0) INTO used FROM refund WHERE payment_id = NEW.payment_id;
  IF used + NEW.amount_minor > p.amount_minor THEN
    RAISE EXCEPTION 'refunds % + % would exceed the payment amount % (B10)', used, NEW.amount_minor, p.amount_minor;
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER refund_enforce_total BEFORE INSERT ON refund
  FOR EACH ROW EXECUTE FUNCTION refund_enforce_total();

-- ---------------------------------------------------------------- provider_event_guard (U4, B6)
-- Rows are never deleted. The received fields never change. processed_at and outcome are filled in once.
CREATE FUNCTION provider_event_guard() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  open_cols CONSTANT text[] := ARRAY['processed_at','outcome','updated_at'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'provider_event rows are never deleted';
  END IF;
  IF OLD.processed_at IS NOT NULL THEN
    IF (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
      RAISE EXCEPTION 'provider_event is already processed: it cannot change';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - open_cols) IS DISTINCT FROM (to_jsonb(OLD) - open_cols) THEN
    RAISE EXCEPTION 'the received fields of a provider_event cannot change';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER provider_event_guard BEFORE UPDATE OR DELETE ON provider_event
  FOR EACH ROW EXECUTE FUNCTION provider_event_guard();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON provider_event
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------- provider_event_write_audit (U4, B5)
-- When an event gets outcome needs_support, write an audit_log row (docs 03 section 4a step 4).
-- Entity: the payment with that reference; else the refund; else the event itself (DEVIATION, see audit_log).
CREATE FUNCTION provider_event_write_audit() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  pid uuid;
  rid uuid;
  etype text;
  eid uuid;
BEGIN
  IF NEW.outcome IS DISTINCT FROM 'needs_support' THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.outcome IS NOT DISTINCT FROM 'needs_support' THEN
    RETURN NULL;
  END IF;
  SELECT id INTO pid FROM payment WHERE provider_reference = NEW.provider_reference;
  IF pid IS NOT NULL THEN
    etype := 'payment'; eid := pid;
  ELSE
    SELECT id INTO rid FROM refund WHERE provider_reference = NEW.provider_reference;
    IF rid IS NOT NULL THEN
      etype := 'refund'; eid := rid;
    ELSE
      etype := 'provider_event'; eid := NEW.id;
    END IF;
  END IF;
  INSERT INTO audit_log (actor_role, action, entity_type, entity_id, details)
  VALUES ('provider', 'provider_conflict', etype, eid,
          jsonb_build_object('provider_event_id', NEW.provider_event_id,
                             'provider_reference', NEW.provider_reference,
                             'event_type', NEW.event_type));
  RETURN NULL;
END
$fn$;
CREATE TRIGGER provider_event_write_audit AFTER INSERT OR UPDATE ON provider_event
  FOR EACH ROW EXECUTE FUNCTION provider_event_write_audit();
