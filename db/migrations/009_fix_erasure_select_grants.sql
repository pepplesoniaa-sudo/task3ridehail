-- 009 fix: erasure functions need to READ deleted_at
-- Found by the first run of erase_rider(...) and erase_driver(...) as ridehail_app on seed A:
--   ERROR: permission denied for table rider  (and for table vehicle)
-- Cause: both functions write deleted_at = COALESCE(deleted_at, now()), which READS deleted_at, and migration 008
-- granted only SELECT (id) on rider and driver and SELECT (id, driver_id) on vehicle to ridehail_erasure_owner.
-- Migration 008 followed its own comment ("reads first, then the columns they blank") but missed that one read.
-- Fix: one more column-level SELECT, nothing wider. Serves B8.
GRANT SELECT (deleted_at) ON rider   TO ridehail_erasure_owner;
GRANT SELECT (deleted_at) ON driver  TO ridehail_erasure_owner;
GRANT SELECT (deleted_at) ON vehicle TO ridehail_erasure_owner;
