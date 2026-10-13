-- SAMPLE SETTINGS SEED. NOT A MIGRATION. EVERY VALUE BELOW IS A PLACEHOLDER THAT NEEDS THE OWNER (city, prices, box, intervals).
-- Serves: A1 (fare quote, EP01 in docs\06_api_contracts.md), B3 (money in kobo, NGN), B9, Q1.
-- Why: POST /v1/fare-quotes reads these rows, and the two background jobs read the two interval rows. Before this seed the setting table
-- held only 4 rows (cancellation fee, rating window, request timeout, reconcile after), so EP01 answered 503 service_not_configured (CONFIRMED).
--
-- Key naming rules kept (constraints on the setting table):
--   * a key that ends in _minor is money in kobo and carries currency NGN (setting_money_has_currency, setting_currency_ngn);
--   * every other key has NO currency (NULL);
--   * values are whole numbers of 0 or more (setting_value_not_negative).
-- Naira to kobo: 1 naira = 100 kobo, written as an expression so the conversion can be read: base fare 500 naira = 50000 kobo,
--   per kilometre 150 naira = 15000 kobo, per minute 30 naira = 3000 kobo.
-- Service area: degrees times 1,000,000, stored as a whole number (6.38 degrees = 6380000), written as an expression for the same reason.
-- Rules for the writer: only a claimed support actor with an id may write a setting (trigger setting_write_audit), and every row written
-- is audited. ON CONFLICT DO NOTHING: this seed never overwrites a value support has already set.
-- The admin id below is an existing support admin (the test admin of seed A): replace it with a real one before any real use.
-- To run (only after the owner confirms the placeholders):
--   docker exec -i task3-pg psql -U ridehail -d ridehail_design -v ON_ERROR_STOP=1 < db\seed\seed_sample_settings.sql
BEGIN;
SET LOCAL ROLE ridehail_app;
SELECT current_user AS applied_as;
SELECT set_config('app.actor_role', 'support', true), set_config('app.actor_id', 'dddddddd-0000-0000-0000-000000000001', true);

INSERT INTO setting (key, int_value, currency, description) VALUES
 -- PLACEHOLDER (needs owner): the city is ASSUMED to be Lagos.
 ('base_fare_minor',        (500 * 100),  'NGN', 'PLACEHOLDER, needs owner: flat starting price of a trip, 500 naira = 50000 kobo.'),
 ('per_km_minor',           (150 * 100),  'NGN', 'PLACEHOLDER, needs owner: price per kilometre, 150 naira = 15000 kobo.'),
 ('per_minute_minor',       (30 * 100),   'NGN', 'PLACEHOLDER, needs owner: price per minute, 30 naira = 3000 kobo.'),
 ('quote_validity_seconds', 300,          NULL,  'PLACEHOLDER, needs owner: seconds a fare quote can be used to request a trip (5 minutes).'),
 -- PLACEHOLDER (needs owner): a rough rectangle around Lagos, 6.38 to 6.70 degrees north and 3.10 to 3.70 degrees east.
 -- A rectangle also contains sea and land the service will not cover; the real boundary needs the owner and a map.
 ('service_area_min_lat_e6', (6.38 * 1000000)::bigint, NULL, 'PLACEHOLDER, needs owner: southern edge of the service area, 6.38 degrees north times 1,000,000.'),
 ('service_area_max_lat_e6', (6.70 * 1000000)::bigint, NULL, 'PLACEHOLDER, needs owner: northern edge of the service area, 6.70 degrees north times 1,000,000.'),
 ('service_area_min_lon_e6', (3.10 * 1000000)::bigint, NULL, 'PLACEHOLDER, needs owner: western edge of the service area, 3.10 degrees east times 1,000,000.'),
 ('service_area_max_lon_e6', (3.70 * 1000000)::bigint, NULL, 'PLACEHOLDER, needs owner: eastern edge of the service area, 3.70 degrees east times 1,000,000.'),
 -- PLACEHOLDER (needs owner): how often the two background jobs run (JB1 request timeout, JB2 payment reconciliation).
 ('request_timeout_check_interval_seconds',   60,  NULL, 'PLACEHOLDER, needs owner: how often the timeout job looks for unaccepted requests (60 seconds).'),
 ('payment_reconcile_check_interval_seconds', 300, NULL, 'PLACEHOLDER, needs owner: how often the payment check job runs (300 seconds).')
ON CONFLICT (key) DO NOTHING;

COMMIT;
