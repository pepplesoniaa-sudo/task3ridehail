-- STAGE 4 PART B: N6 listener side (a separate session). It listens, waits 6 seconds, then runs one command so psql prints what arrived.
SET ROLE ridehail_app;
SELECT current_user AS cu, pg_backend_pid() AS listener_backend_pid;
LISTEN rh_test6;
SELECT pg_sleep(6);
SELECT 1 AS listener_next_command;
