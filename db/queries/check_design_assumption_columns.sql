/* STAGE 5 PREP 2: read only facts the written design assumptions rely on (D13 person status columns, D5 provider columns). */
SET ROLE ridehail_app;
SELECT current_user AS cu;
\echo '=== C1 person status columns the API reads to refuse a deleted rider, a deleted driver or a deactivated admin (D13)'
SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_schema = 'public' AND ((table_name IN ('rider', 'driver') AND column_name IN ('id', 'deleted_at')) OR (table_name = 'support_admin' AND column_name IN ('id', 'is_active', 'deleted_at')))
ORDER BY table_name, column_name;
\echo '=== C2 provider columns (D5): which fields the database side stores'
SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_schema = 'public' AND ((table_name = 'provider_event') OR (table_name IN ('payment', 'refund') AND column_name IN ('provider_reference', 'amount_minor', 'currency', 'failure_reason')))
ORDER BY table_name, ordinal_position;
\echo '=== C3 uniqueness the provider contract relies on'
SELECT conrelid::regclass AS table_name, conname, contype FROM pg_constraint WHERE conname IN ('payment_provider_reference_key', 'refund_provider_reference_key', 'provider_event_provider_event_id_key') ORDER BY 1, 2;
\echo '=== C4 quote columns the estimator output must fit (D16)'
SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fare_quote' AND column_name IN ('estimated_distance_m', 'estimated_duration_s', 'amount_minor', 'currency', 'expires_at') ORDER BY column_name;
SELECT conname, pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid = 'fare_quote'::regclass AND contype = 'c' ORDER BY conname;
