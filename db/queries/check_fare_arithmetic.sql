/* STAGE 5 PREP 2, D16: check the fare arithmetic of docs/06 EP01 against the database. READ ONLY, as ridehail_app.
   Rule under test: amount = round half up to the whole kobo, applied ONCE at the end, of
   base + per_km * distance_m / 1000 + per_minute * duration_s / 60.
   Integer form used by the contract: floor((base * 3000 + per_km * distance_m * 3 + per_minute * duration_s * 50 + 1500) / 3000). */
SET ROLE ridehail_app;
SELECT current_user AS cu;

\echo '=== S1 the three price settings as stored'
SELECT key, int_value, currency FROM setting WHERE key IN ('base_fare_minor', 'per_km_minor', 'per_minute_minor') ORDER BY key;

\echo '=== S2 the placeholder estimator for pickup 6.45, 3.39 and dropoff 6.50, 3.35: flat earth distance times 1.3, speed 8.33 metres per second'
WITH p AS (SELECT 6.45::numeric AS plat, 3.39::numeric AS plon, 6.50::numeric AS dlat, 3.35::numeric AS dlon),
e AS (SELECT sqrt(power((dlat - plat) * 111320, 2) + power((dlon - plon) * 111320 * cos(radians((plat + dlat) / 2)), 2)) AS straight_m FROM p)
SELECT round(straight_m::numeric, 3) AS straight_line_m, round((straight_m * 1.3)::numeric) AS distance_m, round(round((straight_m * 1.3)::numeric) / 8.33) AS duration_s FROM e;

\echo '=== S3 worked example with the REAL setting values: three ways to compute the same fare must agree'
WITH s AS (SELECT max(int_value) FILTER (WHERE key = 'base_fare_minor') AS base, max(int_value) FILTER (WHERE key = 'per_km_minor') AS per_km,
                  max(int_value) FILTER (WHERE key = 'per_minute_minor') AS per_min FROM setting),
i AS (SELECT 9243::bigint AS distance_m, 1110::bigint AS duration_s)
SELECT s.base, s.per_km, s.per_min, i.distance_m, i.duration_s,
       s.per_km * i.distance_m / 1000.0 AS km_part_exact,
       s.per_min * i.duration_s / 60.0 AS minute_part_exact,
       s.base + s.per_km * i.distance_m / 1000.0 + s.per_min * i.duration_s / 60.0 AS fare_exact,
       floor(s.base + s.per_km * i.distance_m / 1000.0 + s.per_min * i.duration_s / 60.0 + 0.5) AS fare_round_once_numeric,
       (s.base * 3000 + s.per_km * i.distance_m * 3 + s.per_min * i.duration_s * 50 + 1500) / 3000 AS fare_integer_formula
FROM s, i;

\echo '=== S4 why ONE rounding: a HYPOTHETICAL price list (not stored) where rounding each part gives a different answer. base 50000, per_km 12345, per_minute 777, distance 5001 m, duration 1111 s'
WITH h AS (SELECT 50000::bigint AS base, 12345::bigint AS per_km, 777::bigint AS per_min, 5001::bigint AS distance_m, 1111::bigint AS duration_s)
SELECT per_km * distance_m / 1000.0 AS km_part_exact, per_min * duration_s / 60.0 AS minute_part_exact,
       base + per_km * distance_m / 1000.0 + per_min * duration_s / 60.0 AS fare_exact,
       floor(base + per_km * distance_m / 1000.0 + per_min * duration_s / 60.0 + 0.5) AS round_once_at_the_end,
       base + round(per_km * distance_m / 1000.0) + round(per_min * duration_s / 60.0) AS round_each_part_then_add,
       (base * 3000 + per_km * distance_m * 3 + per_min * duration_s * 50 + 1500) / 3000 AS integer_formula
FROM h;

\echo '=== S5 the half case: exact 0.5 kobo rounds up to 1; 1.499 rounds to 1; 1.5 rounds to 2; 0 stays 0'
SELECT (500 * 1 * 3 + 1500) / 3000 AS half_of_a_kobo_gives, (1499 * 1 * 3 + 1500) / 3000 AS one_point_499_gives, (1500 * 1 * 3 + 1500) / 3000 AS one_point_5_gives, (0 + 1500) / 3000 AS zero_gives;

\echo '=== S6 limits: the largest values the contract allows must fit in bigint (numerator below 9.2e18)'
SELECT (1000000000::numeric * 3000 + 1000000000::numeric * 1000000 * 3 + 1000000000::numeric * 86400 * 50 + 1500) AS largest_numerator,
       (1000000000::numeric * 3000 + 1000000000::numeric * 1000000 * 3 + 1000000000::numeric * 86400 * 50 + 1500) < 9223372036854775807::numeric AS fits_in_bigint;
