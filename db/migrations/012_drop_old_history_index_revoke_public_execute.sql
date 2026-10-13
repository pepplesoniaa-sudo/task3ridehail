-- 012 two clean-ups after migration 010
-- Serves: B5 (history and audit are written only by the writer functions).

-- a. The timeline is now ordered by seq (migration 010), so the index on (trip_id, created_at) no longer serves
--    any application query. Evidence (follow-up 2, section 4a): after resetting the usage counters and running
--    every file in db/queries, the only statements that used it were three DIAGNOSTIC proof statements: two
--    that any index starting with trip_id can serve, and one that deliberately orders by created_at to show the
--    old, wrong order. The foreign key history_trip_id_fkey is served by trip_status_history_trip_seq_idx
--    (trip_id is its first column). DROP INDEX without CASCADE: nothing depends on this index.
DROP INDEX trip_status_history_trip_idx;

-- b. The four history and audit trigger functions were executable by PUBLIC (PostgreSQL default). They return
--    "trigger" and cannot be called as ordinary functions, but there is no reason to leave the right in place.
--    The owner (ridehail_writer) keeps EXECUTE. Firing a trigger does not check the caller's EXECUTE right:
--    that right is checked once, when the trigger is created. Proved by the dry run and after applying.
REVOKE EXECUTE ON FUNCTION trip_write_history()         FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION setting_write_audit()        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION payment_write_audit()        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION provider_event_write_audit() FROM PUBLIC;
