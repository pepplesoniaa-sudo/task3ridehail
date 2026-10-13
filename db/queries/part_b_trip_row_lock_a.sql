-- STAGE 4 PART B: session A holds the row lock of trip 11 (arrived -> started by its driver), uncommitted, for 5 seconds, then ROLLBACK.
BEGIN; SET LOCAL ROLE ridehail_app; SELECT current_user AS cu, pg_backend_pid() AS session_a_pid;
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
UPDATE trip SET status='started' WHERE id='eeeeeeee-0000-0000-0000-000000000011';
SELECT pg_sleep(5);
ROLLBACK;
