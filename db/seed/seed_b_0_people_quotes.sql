-- SEED B, step 0 of 2. BULK SET, FOR QUERY PLANS ONLY (all names start with BULK).
-- 5000 riders, 800 drivers, 800 vehicles, 200000 fare quotes. Inserted as ridehail_app. Triggers are on.
-- Trip index t (1..200000) decides what each quote is for:
--   t  1..199300      terminal trips (about 85% completed, 15% cancelled)         rider = 1 + (t*7919) mod 5000
--   t 199301..199600  300 active trips (assigned, arrived, started)               rider = 400 + (t - 199300)  -> riders 401..700
--   t 199601..200000  400 requested trips                                         rider = t - 199600          -> riders 1..400
-- id patterns: rider 10000000-..., driver 20000000-..., vehicle 30000000-..., trip 40000000-..., quote 50000000-...
SET ROLE ridehail_app;
SELECT current_user AS loading_as, session_user AS login_session;

INSERT INTO rider (id, full_name, phone, email)
SELECT ('10000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'BULK Rider ' || n,
       '+2347' || lpad(n::text, 9, '0'), 'bulk-rider-' || n || '@example.test'
FROM generate_series(1, 5000) n;

INSERT INTO driver (id, full_name, phone, licence_number)
SELECT ('20000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'BULK Driver ' || n,
       '+2346' || lpad(n::text, 9, '0'), 'BULK-DRV-' || lpad(n::text, 6, '0')
FROM generate_series(1, 800) n;

INSERT INTO vehicle (id, driver_id, plate_number, make, model, colour, seat_count)
SELECT ('30000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       ('20000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       'BLK-' || n || '-ZZ', 'Toyota', 'Camry', 'Black', 4
FROM generate_series(1, 800) n;

INSERT INTO fare_quote (id, rider_id, pickup_latitude, pickup_longitude, dropoff_latitude, dropoff_longitude,
                        estimated_distance_m, estimated_duration_s, amount_minor, currency, expires_at)
SELECT ('50000000-0000-0000-0000-' || lpad(t::text, 12, '0'))::uuid,
       ('10000000-0000-0000-0000-' || lpad(rider_n::text, 12, '0'))::uuid,
       6.400000 + (t % 1000) * 0.0001,        3.300000 + ((t * 7) % 1000) * 0.0001,
       6.450000 + ((t * 3) % 1000) * 0.0001,  3.350000 + ((t * 11) % 1000) * 0.0001,
       3000 + (t % 200) * 100, 600 + (t % 120) * 30, 50000 + (t % 100) * 5000, 'NGN',
       now() + interval '1 hour'   -- quotes stay valid so the real trip trigger accepts them
FROM (SELECT t, CASE WHEN t <= 199300 THEN 1 + ((t * 7919) % 5000)
                     WHEN t <= 199600 THEN 400 + (t - 199300)
                     ELSE t - 199600 END AS rider_n
      FROM generate_series(1, 200000) t) s;

RESET ROLE;
