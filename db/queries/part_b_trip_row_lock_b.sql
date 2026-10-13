-- STAGE 4 PART B: session B tries a move on the same trip 11 while A holds the lock. lock_timeout 800ms shows it has to wait.
BEGIN; SET LOCAL ROLE ridehail_app; SELECT current_user AS cu, pg_backend_pid() AS session_b_pid;
SET LOCAL lock_timeout = '800ms';
SELECT set_config('app.actor_role','driver',true), set_config('app.actor_id','bbbbbbbb-0000-0000-0000-000000000004',true);
UPDATE trip SET status='started' WHERE id='eeeeeeee-0000-0000-0000-000000000011';
\echo SQLSTATE :LAST_ERROR_SQLSTATE
ROLLBACK;
