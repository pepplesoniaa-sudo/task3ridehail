-- FOLLOW UP 2, section 3: statements run while CONNECTED AS the test login role (not SET ROLE from the superuser).
-- No password appears in this file. The role is created and dropped by the surrounding command.
\set SHOW_CONTEXT always
\echo '--- who am I? connected over the container address, not loopback, so password authentication applied'
SELECT current_user, session_user, inet_client_addr() <> '127.0.0.1'::inet AS not_loopback;
SELECT rolname, rolcanlogin, rolsuper, rolinherit, pg_has_role(current_user, 'ridehail_app', 'USAGE') AS is_member_of_ridehail_app,
       pg_has_role(current_user, 'ridehail_erasure_owner', 'USAGE') AS member_of_erasure_owner,
       pg_has_role(current_user, 'ridehail_writer', 'USAGE') AS member_of_writer,
       pg_has_role(current_user, 'ridehail', 'USAGE') AS member_of_dev_superuser
FROM pg_roles WHERE rolname = current_user;

\echo '--- 1. cannot INSERT into trip_status_history'
BEGIN;
INSERT INTO trip_status_history (trip_id, from_status, to_status, actor_role, actor_rider_id)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', NULL, 'requested', 'rider', 'aaaaaaaa-0000-0000-0000-000000000001');
ROLLBACK;

\echo '--- 2. cannot UPDATE a rating'
BEGIN;
UPDATE rating SET comment = NULL WHERE trip_id = 'eeeeeeee-0000-0000-0000-000000000001';
ROLLBACK;

\echo '--- 3. can request a trip (bulk rider 3000, rolled back)'
BEGIN;
SELECT set_config('app.actor_role', 'rider', true), set_config('app.actor_id', '10000000-0000-0000-0000-000000003000', true);
INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude, estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
VALUES ('50000000-0000-0000-0000-0000000c0001', '10000000-0000-0000-0000-000000003000', 6.45, 3.39, 6.50, 3.35, 5000, 900, 100000, 'NGN', now() + interval '1 hour');
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address)
VALUES ('10000000-0000-0000-0000-000000003000', '50000000-0000-0000-0000-0000000c0001', 'login test pickup', 'login test dropoff')
RETURNING id, status, rider_id;
SELECT count(*) AS history_rows_written_for_it_by_the_trigger FROM trip_status_history h JOIN trip t ON t.id = h.trip_id WHERE t.fare_quote_id = '50000000-0000-0000-0000-0000000c0001';
ROLLBACK;

\echo '--- 4. RESET ROLE has no effect (no role was set)'
RESET ROLE;
SELECT current_user, session_user;

\echo '--- 5. SET ROLE ridehail (the dev superuser) is refused'
SET ROLE ridehail;
SELECT current_user, session_user;

\echo '--- 6. SET SESSION AUTHORIZATION ridehail is refused'
SET SESSION AUTHORIZATION ridehail;
SELECT current_user, session_user;

\echo '--- 7. SET ROLE ridehail_erasure_owner and ridehail_writer are refused (not a member of them)'
SET ROLE ridehail_erasure_owner;
SET ROLE ridehail_writer;
SELECT current_user, session_user;

\echo '--- 8. what it MAY do: SET ROLE ridehail_app (it is a member), then go back'
SET ROLE ridehail_app;
SELECT current_user, session_user;
RESET ROLE;
SELECT current_user, session_user;

\echo '--- 9. add_support_note IS executable by members of ridehail_app, but this session claims no support actor, so it is refused; pg_authid cannot be read'
SELECT add_support_note('trip', 'eeeeeeee-0000-0000-0000-000000000001', 'x');
SELECT rolpassword FROM pg_authid WHERE rolname = current_user;
