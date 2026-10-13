-- STAGE 4 PART B: how LISTEN / NOTIFY behaves, tested in short sessions as ridehail_app. Nothing is stored: NOTIFY writes no table row.
-- No trigger and no migration is added; pg_notify is called by hand. psql prints a notification after the next command of the listening session.
\set VERBOSITY default
SET ROLE ridehail_app;
SELECT current_user AS cu, pg_backend_pid() AS this_backend_pid;

\echo '=== N5 payload size limit (this session is NOT listening, so nothing is printed): 7999 characters, then 8000'
SELECT length(pg_notify('rh_test', repeat('x', 7999))::text) AS ok_7999_returns_void_text;
SELECT pg_notify('rh_test', repeat('x', 8000));
\echo SQLSTATE :LAST_ERROR_SQLSTATE

\echo '=== N4a a notification sent while nobody listens'
SELECT pg_notify('rh_test', 'sent while nobody listens');

\echo '=== (new connection, a new session with a new backend pid)'
\connect - ridehail
SET ROLE ridehail_app;
SELECT current_user AS cu, pg_backend_pid() AS listener_backend_pid;
LISTEN rh_test;
\echo '=== N4b the notification above is not delivered to a session that starts listening afterwards (expect no "Asynchronous notification" line before the next echo)'
SELECT 1 AS after_listen_started;
\echo '=== N1 sent after LISTEN, committed: delivered, with the payload'
SELECT pg_notify('rh_test', '{"trip_id":"40000000-0000-0000-0000-000000198904","seq":930301,"to_status":"completed"}');
SELECT 1 AS next_command_1;
\echo '=== N2 sent inside a transaction that is rolled back: NOT delivered'
BEGIN; SELECT pg_notify('rh_test', 'sent then rolled back'); ROLLBACK;
SELECT 1 AS next_command_2;
\echo '=== N3a two IDENTICAL notifications in one transaction are folded into one'
BEGIN; SELECT pg_notify('rh_test', 'same payload'); SELECT pg_notify('rh_test', 'same payload'); COMMIT;
SELECT 1 AS next_command_3a;
\echo '=== N3b two DIFFERENT payloads in one transaction are both delivered, in the order sent'
BEGIN; SELECT pg_notify('rh_test', 'seq 1'); SELECT pg_notify('rh_test', 'seq 2'); COMMIT;
SELECT 1 AS next_command_3b;
\echo '=== N3c notification is held until COMMIT: sent inside an open transaction, delivered only after the commit'
BEGIN; SELECT pg_notify('rh_test', 'held until commit');
SELECT 1 AS inside_open_transaction_nothing_yet;
COMMIT;
SELECT 1 AS after_commit;
UNLISTEN rh_test;
