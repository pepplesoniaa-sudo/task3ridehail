-- 007 indexes: only the 9 chosen indexes of docs 04 question 7.
-- (The 32 other indexes already exist because primary keys, unique constraints and the partial unique
-- indexes created them in migrations 002 to 006.)

-- A2, B9: waiting trips in age order; the request timeout job (T9) reads it too. A query must repeat
-- status = 'requested' exactly or Postgres will not use it.
CREATE INDEX trip_requested_created_at_idx ON trip (created_at) WHERE status = 'requested';

-- A2: find a driver's car; also supports vehicle_driver_id_fkey.
CREATE INDEX vehicle_driver_id_idx ON vehicle (driver_id);

-- A3: one trip's status timeline in order; supports history_trip_id_fkey.
CREATE INDEX trip_status_history_trip_idx ON trip_status_history (trip_id, created_at);

-- A3: latest driver position for one trip; supports ping_trip_id_fkey.
CREATE INDEX location_ping_trip_recorded_idx ON location_ping (trip_id, recorded_at DESC);

-- B10: the refund trigger sums refunds per payment; supports refund_payment_id_fkey.
CREATE INDEX refund_payment_id_idx ON refund (payment_id);

-- History lists with keyset pagination; support trip_rider_id_fkey and trip_driver_id_fkey.
CREATE INDEX trip_rider_history_idx  ON trip (rider_id,  created_at DESC, id DESC);
CREATE INDEX trip_driver_history_idx ON trip (driver_id, created_at DESC, id DESC);

-- Reconciliation job (docs 03 section 8): pending payments in age order. Must repeat status = 'pending'.
CREATE INDEX payment_pending_created_at_idx ON payment (created_at) WHERE status = 'pending';

-- The P3 rule in payment_enforce_rules looks up provider_event by provider_reference.
CREATE INDEX provider_event_reference_idx ON provider_event (provider_reference);
