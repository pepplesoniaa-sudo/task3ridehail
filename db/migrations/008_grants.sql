-- 008 grants
-- ridehail_app (the API): exactly what the application needs, per docs 04 question 4 (delete styles) and
-- question 6 (triggers run as the calling role, so the app role must be able to do what the triggers do).
-- ridehail_erasure_owner: only what erase_rider and erase_driver need, at column level.
-- No PUBLIC privilege exists on any table (PostgreSQL default). EXECUTE is revoked from PUBLIC on the
-- two erasure functions and granted to ridehail_app only.

-- ======================================================= ridehail_app
-- People and staff: soft delete only (deleted_at), so no DELETE (B4, B8).
GRANT SELECT, INSERT, UPDATE ON rider         TO ridehail_app;  -- the rating cache trigger updates rider and driver rows
GRANT SELECT, INSERT, UPDATE ON driver        TO ridehail_app;
GRANT SELECT, INSERT, UPDATE ON vehicle       TO ridehail_app;
GRANT SELECT, INSERT, UPDATE ON support_admin TO ridehail_app;

-- Settings: support changes them through the API; audited by trigger setting_write_audit. Never deleted.
GRANT SELECT, INSERT, UPDATE ON setting TO ridehail_app;

-- Rule rows change only by migration. The triggers (running as the app role) read them.
GRANT SELECT ON status_transition_rule TO ridehail_app;

-- Quotes are never edited or deleted (append-only trigger as well).
GRANT SELECT, INSERT ON fare_quote TO ridehail_app;

-- Trips: requested by insert, moved by update, never deleted (B4, trip_block_delete as well).
GRANT SELECT, INSERT, UPDATE ON trip TO ridehail_app;

-- History and audit rows are written by triggers that run as the calling role, so the app role needs INSERT.
-- (Limit: it could also insert a false row directly. See the Stage 3 report, doc changes.) Never updated or deleted.
GRANT SELECT, INSERT ON trip_status_history TO ridehail_app;
GRANT SELECT, INSERT ON audit_log           TO ridehail_app;

-- Payments move pending to a final status; never deleted. Provider events get processed_at and outcome once.
GRANT SELECT, INSERT, UPDATE ON payment        TO ridehail_app;
GRANT SELECT, INSERT, UPDATE ON provider_event TO ridehail_app;

-- Refunds are never edited or deleted (new rows only, B4, B10). SELECT FOR UPDATE on payment (B10) needs UPDATE on payment, granted above.
GRANT SELECT, INSERT ON refund TO ridehail_app;

-- Ratings are never edited or deleted by the app (only the erasure owner may blank a comment).
GRANT SELECT, INSERT ON rating TO ridehail_app;

-- The two tables the design says are hard deleted: location_ping (retention, Q5, no period chosen yet) and
-- idempotency_key (after expires_at).
GRANT SELECT, INSERT, DELETE         ON location_ping    TO ridehail_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON idempotency_key  TO ridehail_app;

-- Erasure: the app may call the two functions and nothing else touches the erased columns.
REVOKE ALL ON FUNCTION erase_rider(uuid)  FROM PUBLIC;
REVOKE ALL ON FUNCTION erase_driver(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION erase_rider(uuid)  TO ridehail_app;
GRANT EXECUTE ON FUNCTION erase_driver(uuid) TO ridehail_app;

-- ======================================================= ridehail_erasure_owner (column level)
-- erase_rider and erase_driver run with these rights (SECURITY DEFINER). Reads first, then the columns they blank.
GRANT SELECT (id, rider_id, driver_id, status) ON trip   TO ridehail_erasure_owner;  -- active-trip check, row selection
GRANT SELECT (id, trip_id, rater_role, comment) ON rating TO ridehail_erasure_owner;
GRANT SELECT (id)             ON rider   TO ridehail_erasure_owner;
GRANT SELECT (id)             ON driver  TO ridehail_erasure_owner;
GRANT SELECT (id, driver_id)  ON vehicle TO ridehail_erasure_owner;

GRANT UPDATE (pickup_address, dropoff_address)                ON trip    TO ridehail_erasure_owner;  -- erase_rider
GRANT UPDATE (driver_name_snapshot, vehicle_plate_snapshot)   ON trip    TO ridehail_erasure_owner;  -- erase_driver
GRANT UPDATE (comment)                                        ON rating  TO ridehail_erasure_owner;  -- both
GRANT UPDATE (full_name, phone, email, deleted_at)            ON rider   TO ridehail_erasure_owner;  -- erase_rider
GRANT UPDATE (full_name, phone, licence_number, deleted_at)   ON driver  TO ridehail_erasure_owner;  -- erase_driver
GRANT UPDATE (plate_number, is_active, deleted_at)            ON vehicle TO ridehail_erasure_owner;  -- erase_driver
