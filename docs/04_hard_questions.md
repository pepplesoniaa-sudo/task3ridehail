# 04 Hard Questions

Each answer has: question, answer, reason, requirement IDs, enforcer. CONFIRMED means I ran it and kept the output (the numbered tests are listed in the report). INFERRED means I reasoned it. Table and field names match `02_entities.md`. The status rules are in `03_state_machine.md`.

---

## Question 1. Normalisation: where does each fact live?

**Answer.** Each fact lives in exactly one home table, and everything else finds it by a foreign key. Exceptions are the deliberate denormalisations below, each with its own reason and its own way of staying correct.

| Fact | Home | How others find it |
|---|---|---|
| A person's name, phone | rider, driver, support_admin | trip.rider_id, trip.driver_id, actor columns |
| Who paid for a trip | trip.rider_id | payment has no rider column; join through trip |
| Who is rated, and who rated | trip (rider_id, driver_id) + rating.rater_role | rating has no ratee column; join through trip |
| Whose car it is | vehicle.driver_id | trip.vehicle_id, with the composite FK |
| Pickup and dropoff coordinates | fare_quote | trip joins to its quote; not copied |
| Pickup and dropoff address text | trip (the only copy) | n/a |
| Fare price rules, fee, rating window | setting | read at the time they are needed |
| Legal status moves | status_transition_rule | read by triggers |

**Reason.** No copy means no copy can disagree (B4, B6). The one-copy rule also makes erasure under B8 possible: a name stored in six tables must be found and cleared in six tables.

**Denormalisation 1: HISTORY snapshot.** `trip.driver_name_snapshot` and `trip.vehicle_plate_snapshot` copy the driver's name and the car's plate at the moment of assignment. Also `trip.cancellation_fee_minor` copies the setting at the moment of cancellation.
- **Why:** these are facts about the past. A driver may later change name, or sell the car, or the owner may change the fee. An old receipt must still say what was true then (B4).
- **How kept correct:** they are written once, inside the same update that assigns or ends the trip, by trigger `trip_enforce_transition`. After completion or cancellation they are frozen by the same trigger (B4). They are meant to stop matching the live rows, so "drift" is the goal, not a defect. Check constraint `trip_snapshots_match_assignment` makes sure the snapshots exist exactly when a driver and a vehicle exist.

**Derived copies (not snapshots, not a third denormalisation).** `trip.started_at`, `trip.completed_at` and `trip.cancelled_at` repeat times that also exist in `trip_status_history`. They are **derived copies**: the history row is the original, and the trip column can always be recomputed from it. They are kept so the facts frozen by B4 (start and end times) sit on the trip row, and a trip can be read without a join. They are written by the same update that makes the history row (triggers `trip_enforce_transition` and `trip_write_history`), so they agree. A detect query, below, finds any disagreement. This query has not been run (INFERRED correct by reading).

```sql
-- Trips whose started_at disagrees with the history (same idea for completed_at and cancelled_at).
SELECT t.id, t.started_at, h.created_at AS history_time
FROM trip t
JOIN trip_status_history h ON h.trip_id = t.id AND h.to_status = 'started'
WHERE t.started_at IS DISTINCT FROM h.created_at;
```
- **Not a snapshot:** `pickup_address` and `dropoff_address` are the only copy of those words (nothing else stores an address), so they are plain trip data. They are personal data and are handled by question 4.

**The two real denormalisations are therefore the HISTORY snapshot (above) and the SPEED cache (below).**

**Denormalisation 2: SPEED cache.** `rider.rating_sum`, `rider.rating_count`, `driver.rating_sum`, `driver.rating_count` hold running totals of the stars each person received.
- **Why:** showing "4.8 stars" on every trip screen would otherwise mean adding up thousands of rating rows each time. I store integer totals, not an average. The average is `rating_sum / rating_count` when read. A stored average would carry rounding error and could not be corrected exactly.
- **How kept correct:** (1) trigger `rating_update_cache` adds the new stars in the same transaction as the rating insert, so they cannot disagree after a normal insert; (2) check constraints `rider_rating_cache_valid` and `driver_rating_cache_valid` refuse impossible totals (for example total stars above 5 times the count); (3) a repair-and-detect query, below, recomputes the truth from the `rating` table. Run it daily and alarm if it returns any row. It can drift if someone edits the rating table directly or bypasses the trigger, which is why the query exists.

```sql
-- Drivers whose cache disagrees with the rating rows (rider side is the mirror image).
SELECT d.id, d.rating_sum, d.rating_count,
       COALESCE(SUM(r.stars),0) AS true_sum, COUNT(r.id) AS true_count
FROM driver d
LEFT JOIN trip t   ON t.driver_id = d.id
LEFT JOIN rating r ON r.trip_id = t.id AND r.rater_role = 'rider'
GROUP BY d.id
HAVING d.rating_sum <> COALESCE(SUM(r.stars),0) OR d.rating_count <> COUNT(r.id);
```
This query has not been scheduled, because no job runner exists (the tables exist now; the query is INFERRED to be correct by reading it, not by running it on a schedule). See `docs/10_brief_checklist.md` section 3, the strictness note.

**IDs.** B4, B5, B7, B8, A5. **Enforcers.** triggers `trip_enforce_transition`, `trip_write_history`, `rating_update_cache`; checks `trip_snapshots_match_assignment`, `rider_rating_cache_valid`, `driver_rating_cache_valid`.

---

## Question 2. Money

**Answer.** Money is a whole number of kobo in a `bigint` column, with a `char(3)` currency column beside it, always `NGN`.

**Every money field in `02_entities.md`:**

| Table | Amount field | Currency field |
|---|---|---|
| fare_quote | amount_minor | currency |
| trip | fare_amount_minor | fare_currency |
| trip | cancellation_fee_minor | cancellation_fee_currency |
| payment | amount_minor | currency |
| refund | amount_minor | currency |
| provider_event | amount_minor (optional) | currency (optional, filled together with the amount) |
| setting | int_value, only for the keys ending in `_minor` (`cancellation_fee_minor`, `base_fare_minor`, `per_km_minor`, `per_minute_minor`) | currency |

That is 7 amount columns, each with its own currency column beside it (7 currency columns). `provider_event.amount_minor` was added in this fix, so the count went from 6 to 7. The `setting` column holds four different money keys, but they share one column. `fare_quote.estimated_distance_m` and `trip.distance_m` are distances, not money.

**What a bigint does with 10.5 (CONFIRMED, rolled back transaction on `ridehail_design`, PostgreSQL 16.15):**

```
INSERT INTO m(a) VALUES (10.5);            -> stored 11   (no error)
INSERT INTO m(a) VALUES (11.5);            -> stored 12   (no error)
INSERT INTO m(a) VALUES (10.5::float8);    -> stored 10   (no error)
INSERT INTO m(a) VALUES ('10.5');          -> ERROR: invalid input syntax for type bigint: "10.5"
EXECUTE p('10.5')   -- bound as bigint     -> ERROR: invalid input syntax for type bigint: "10.5"
INSERT INTO m(a) VALUES (-1);              -> ERROR: new row ... violates check constraint "m_a_check"
```
After the rollback, 0 test tables remained.

**What actually blocks decimal money?** Not the type on its own. The test shows that when the value arrives as a number (10.5) the database **silently rounds it** (10.5 became 11, a float 10.5 became 10), and nothing complains. It errors only when the value arrives as text. A check constraint cannot help either, because it runs after the rounding and only sees 11. So the real answer is, in order:
1. **API validation** is the only layer that can reject 10.5, by demanding a whole number (JSON type integer) before the value reaches the database. This is application code.
2. **The `bigint` type** blocks decimals only for text-typed parameters. That is a side effect, not a guarantee.
3. **Check constraints** block what they can see: `payment_amount_positive`, `quote_amount_not_negative`, `trip_amounts_not_negative`, `refund_amount_positive`, `provider_event_amount_positive`, `setting_value_not_negative`, and `*_currency_ngn`.

Fares computed from per-kilometre prices need one rounding rule. That rule belongs in one function in the API stage, not in a trigger (INFERRED; the contract now states one rounding rule, applied once at the end, in `06` EP01, design assumption D16).

**Reason.** Binary floats cannot hold 0.1 exactly, so sums of floats drift by fractions of a kobo. Whole kobo add and compare exactly.

**IDs.** B3, B10, A1, A4, Q1. **Enforcers.** API validation (decimals); check constraints (sign, currency); the column type (storage).

---

## Question 3. Status and state

**Answer.** The full tables, forbidden moves, diagrams and the trigger test are in `03_state_machine.md`. The enforcer for each rule:

| Rule | Enforcer |
|---|---|
| Legal trip moves (B5, B9) | table `status_transition_rule` + trigger `trip_enforce_transition` |
| New trip starts as requested (A1) | trigger `trip_enforce_transition` |
| Terminal trips frozen (B4) | trigger `trip_enforce_transition`; deletes blocked by `trip_block_delete` |
| One driver per trip, set once (A2) | trigger `trip_enforce_transition` |
| Right actor for the move | trigger compares the claimed actor to the trip; the app authenticates the caller |
| Support fails a stuck payment only with proof (A4, B6) | rule row P3 (actor support) + trigger `payment_enforce_rules`, which looks up a `payment_not_found` row in `provider_event` (03 section 4b, tested) |
| Unmatched request expires (B9) | rule row T9 for actor `system` + trigger `trip_enforce_transition`; the timer is a scheduled job (application code) |
| Provider message repeated or conflicting (U4, B6) | unique constraint `provider_event_provider_event_id_key`; triggers `provider_event_guard`, `provider_event_write_audit`; handler in 03 section 4a (application code) |
| Erasure of personal text (B8) | functions `erase_rider`, `erase_driver` owned by role `ridehail_erasure_owner`; the freeze trigger checks `current_user` (question 4) |
| One active trip per rider and per driver (B0, B1, B2) | partial unique indexes `trip_one_active_per_rider`, `trip_one_active_per_driver` |
| Status change is recorded (B5) | trigger `trip_write_history`; `payment_write_audit` for payments. Both are `SECURITY DEFINER` functions owned by role `ridehail_writer`; `ridehail_app` has no INSERT on `trip_status_history` or `audit_log` (migration 010) |
| Dispute notes (U3) | function `add_support_note`, owner `ridehail_writer`, executable by `ridehail_app` only for a claimed support actor |
| Timeline order (B5, A3) | identity column `trip_status_history.seq` and index `trip_status_history_trip_seq_idx` |
| Payment moves (A4) | table `status_transition_rule` + trigger `payment_enforce_rules` |
| One live payment per purpose (A4, B6) | partial unique index `payment_one_live_per_purpose` |
| Refund total (B10) | trigger `refund_enforce_total` |
| Row is consistent with its status | check constraints `trip_driver_matches_status`, `trip_completed_has_facts`, `trip_cancelled_has_facts`, `trip_started_has_time`, `payment_succeeded_has_proof`, `payment_failed_has_reason` |

**Reason.** See section 5 of `03_state_machine.md`. In short: checks see one row, triggers see old and new rows and other tables, unique indexes are atomic.

**IDs.** B0, B1, B2, B4, B5, B6, B9, B10, A1 to A4. **Enforcer.** as listed.

---

## Question 4. Time, deletion and personal data

**Answer.** Every table has `created_at` and `updated_at` (`timestamptz`, `NOT NULL`, default `now()`). The trigger `set_updated_at` refreshes `updated_at` on tables that are updated: rider, driver, vehicle, trip, payment, provider_event, idempotency_key, setting, support_admin. On the append-only tables `updated_at` equals `created_at` for ever (decision 3). I use `timestamptz` so a stored time is an exact moment, not a clock reading without a zone.

| Table | Delete style | Reason |
|---|---|---|
| rider, driver, vehicle, support_admin | **Soft delete**: set `deleted_at`, blank personal fields | Other rows point at them. A hard delete would break the foreign keys or destroy the financial record (B4). A soft delete lets the person leave (B8) while the money trail stays. |
| trip, payment, refund, provider_event, trip_status_history, fare_quote, rating, audit_log | **Never deleted** | These are the financial and audit record (B4, B5, B10). Personal text inside them is blanked, not the row. |
| location_ping | **Hard delete** once a retention period exists | Raw location is the most sensitive data and has no value after the trip is settled. No period is chosen (Q5), so no deletion job is designed yet. |
| idempotency_key | **Hard delete** after `expires_at` | It only exists to make a retry safe for a short time. |
| setting, status_transition_rule | Not deleted in normal use | Reference data. Changes to settings are written to `audit_log` by trigger `setting_write_audit`. |

**What happens to a deleted rider's trips and payments.** They stay. The rider row is anonymised: `full_name` becomes the text `Deleted rider`, `phone` becomes `deleted-` plus the rider's `id` (so it is still unique and still not empty), `email` is cleared, `deleted_at` is set. The rider's trips, payments and refunds keep their ids and amounts, because a business must keep a record of money (B4). The rider's `pickup_address` and `dropoff_address` on old trips are replaced with the text `erased`, and rating comments are cleared. The same is done for a driver (`driver_name_snapshot`, `vehicle_plate_snapshot`; the driver's vehicles get `deleted_at` and a blanked plate). A person with an active trip cannot be erased until the trip ends. This is now checked **inside the erasure function**, so it is a database rule, not application code (tested for riders, step X6 below).

**A conflict you must approve (decision 1).** B4 as edited says that after completion only `updated_at` may change. Blanking an address on a completed trip changes more than `updated_at`. So B4 and B8 pull against each other. My recommendation: keep B4 for every money, distance, time, party and status field, and allow exactly five text columns to be blanked: `pickup_address`, `dropoff_address`, `driver_name_snapshot`, `vehicle_plate_snapshot` (on trip) and `comment` (on rating). Only a dedicated erasure function may do it. If you reject this, the alternative is to keep addresses for ever and rely on a lawful exemption, which I cannot judge.

**How the erasure right is protected (replaces the earlier `app.erasure` flag idea).** The flag was weak, because any code that could talk to the database could set it. The new design ties the right to a database role:
- Role `ridehail_erasure_owner`: `NOLOGIN` (nobody can connect as it), not a superuser. It owns the functions `erase_rider(uuid)` and `erase_driver(uuid)`, which are `SECURITY DEFINER` (they run with their owner's rights) with a fixed `search_path` so a caller cannot trick them into using another table.
- Role `ridehail_app`: the role the API connects as. It may `EXECUTE` the two functions and has no other route to the erased columns. `EXECUTE` is revoked from everyone else (`PUBLIC`).
- The freeze trigger on `trip` (inside `trip_enforce_transition`) and the trigger `rating_block_change` allow those five columns to change only when `current_user` is `ridehail_erasure_owner`, and refuse any other column. Inside a SECURITY DEFINER function `current_user` is the function's owner, so the trigger sees the owner and lets the function through. A direct update by the app is refused.
- The dev login `ridehail` used in this project is a superuser (CONFIRMED: `rolsuper = t`), and a superuser can bypass anything. So the API must never connect as `ridehail`. That is a deployment rule for Stage 3.

**Two layers on the erased columns, and the exact grants (built in migrations 008 and 009).**
- **Privilege layer.** `ridehail_app` has no UPDATE on `rating` at all. A direct comment edit is refused before any trigger runs: "permission denied for table rating" (CONFIRMED, proof X6c). On `trip` the app does have UPDATE (it moves trips), so there the trigger layer is the one that refuses a direct change to `pickup_address` on a completed trip: "trip is completed (terminal): only updated_at may change (B4)" (CONFIRMED, proof X6b).
- **Trigger layer.** `trip_enforce_transition` and `rating_block_change` allow the five columns to change only when `current_user = ridehail_erasure_owner`, and refuse every other column even for that role (CONFIRMED test X8).
- **Exact column grants of `ridehail_erasure_owner`** (no table-level grant):
  - SELECT: `trip` (id, rider_id, driver_id, status); `rating` (id, trip_id, rater_role, comment); `rider` (id, deleted_at); `driver` (id, deleted_at); `vehicle` (id, driver_id, deleted_at).
  - UPDATE: `trip` (pickup_address, dropoff_address, driver_name_snapshot, vehicle_plate_snapshot); `rating` (comment); `rider` (full_name, phone, email, deleted_at); `driver` (full_name, phone, licence_number, deleted_at); `vehicle` (plate_number, is_active, deleted_at).
  - `deleted_at` SELECT came in migration 009: the functions write `COALESCE(deleted_at, now())`, which reads the column. The first run of `erase_rider` as `ridehail_app` failed with "permission denied for table rider" until that grant existed.

**Who writes the history and the audit trail (migrations 010 and 011).** The role `ridehail_writer` (NOLOGIN, not a superuser) owns the functions `trip_write_history`, `setting_write_audit`, `payment_write_audit`, `provider_event_write_audit` and `add_support_note`, all `SECURITY DEFINER` with a fixed search_path. It has INSERT on `trip_status_history` and `audit_log`, and SELECT on `payment` and `refund` columns `id` and `provider_reference` (for the lookup in `provider_event_write_audit`). `ridehail_app` has SELECT only on both tables. CONFIRMED as `ridehail_app`: a direct INSERT into either table is refused by privilege; a normal move, a payment status change, a setting change by support, a P3 failure and a provider_conflict still write their rows with the claimed actor. **What remains:** a superuser can still bypass all of this, and the actor name is stated by the application, so a compromised `ridehail_app` could claim another actor.

**Search path and temporary tables (found in follow-up 2, fixed by migration 013).** PostgreSQL searches the temporary schema **first** for tables unless `pg_temp` is named in the path, and `ridehail_app` has the default TEMP privilege. So a session of that role could create a temp table with the name of a real table. CONFIRMED on the real database, as `ridehail_app`: (E1) a temp `audit_log` made `payment_write_audit` (SECURITY DEFINER, fixed path `pg_catalog, public`) write the audit row into the temp table, 0 rows into `public.audit_log`, so the audit row vanished at the end of the session; (E2) the same for `trip_status_history`: the trip moved to `arrived` and the history row went into the temp table; (E4) a temp `status_transition_rule` made the NON-definer trigger `trip_enforce_transition` accept a forbidden move (assigned to started, skipping arrived, move F5). (E3) an attacker-owned schema earlier on the session search path did **not** work against the writers: their fixed path holds. **Fix (migration 013):** all 18 functions now have `search_path = pg_catalog, public, pg_temp`, so the real tables win. After the fix (CONFIRMED, `evidence/followup2_proof_1b_after_fix.txt`): E1 puts 1 row in `public.audit_log` and 0 in the temp table; E2 puts the history row in `public` (2 to 3) and 0 in the temp table; E3 unchanged; E4 is refused ("illegal transition assigned -> started by driver"). Write timings did not get worse. **Done in migration 014 (follow-up 3): `REVOKE TEMPORARY ON DATABASE ridehail_design FROM PUBLIC`.** Nothing in the project needs temp tables: the only `CREATE TEMP` statements in `db` are the three deliberate attacks (checked by search, `evidence/followup3_temp_groundwork.txt`), so no `GRANT TEMP` to any role was needed. The database ACL went from default (empty) to `{=c/ridehail,ridehail=CTc/ridehail}`: CONNECT stays with PUBLIC, TEMP does not. CONFIRMED as `ridehail_app` (`evidence/followup3_014_proofs.txt`, `followup3_014_dry_run.txt`): `CREATE TEMP TABLE` and `CREATE TABLE pg_temp.x` are refused ("permission denied to create temporary tables in database"); a trip move, a payment move, a setting change by support, a rating (the driver's rating cache moved from 5/1 to 9/2) and an erasure by function all still work; a sort of 200,012 rows with `work_mem = 64kB` still spills to disk ("external merge Disk: 6712kB"), because that uses temporary files, not temp tables. The four attacks were re-run on the applied database (`evidence/followup3_attacks_rerun_after_014.txt`): E1, E2 and E4 are refused at `CREATE TEMP TABLE`, and E3 (an attacker-owned schema on the search path) still has no effect (1 public audit row, 0 in the attacker's table). Two layers now close the temp-table attack: nobody can create the table (014), and if somebody could, the functions would not read it (013).

**Limits of this check.** (1) Only three table names were shadowed in the attacks (`audit_log`, `trip_status_history`, `status_transition_rule`); the other tables the functions read rely on the same two layers but were not each attacked. (2) `pg_hba` uses `trust` for the local socket and for 127.0.0.1 and ::1, so any process inside the container, including `docker exec psql`, connects as any role without a password. Only other addresses use `scram-sha-256`. This was not changed. A deployment needs its own `pg_hba` without `trust`. (3) Timings on this machine vary by about 3 times between runs, so every millisecond figure in these docs is an order of magnitude, not a promise.

**Test (CONFIRMED, rolled back transaction, PostgreSQL 16.15; cut-down tables and one function, both roles created inside the transaction):**

```
function owner: ridehail_erasure_owner, security definer: true
X1 app role updates pickup_address of a completed trip directly -> ERROR: terminal trip: only updated_at may change (current_user is ridehail_app)
X2 app role changes the fare of a completed trip directly       -> ERROR: terminal trip: only updated_at may change (current_user is ridehail_app)
X3 app role edits a rating comment directly                     -> ERROR: rating is append-only (current_user is ridehail_app)
X4 app role touches only updated_at on the completed trip       -> accepted
X5 app role calls erase_rider for a rider with a completed trip -> accepted
X5b after the call: address=erased fare=250000 ; comment is null: true
X6 app role calls erase_rider for a rider with an active trip   -> ERROR: rider has an active trip, cannot erase
X7 a role with no grant calls the function                      -> ERROR: permission denied for function erase_rider
X8 the owner role itself changes the fare directly              -> ERROR: terminal trip: only updated_at may change (current_user is ridehail_erasure_owner)
X9 owner rolcanlogin: false, rolsuper: false
after ROLLBACK: 0 tables, 0 functions, 0 extra roles; roles now: ridehail
```
Not tested: `erase_driver`, vehicle erasure, the real `trip_enforce_transition` (the test used a cut-down freeze trigger), and what happens if a superuser disables the trigger (nothing stops that). Later, on the built database, `erase_driver` and the vehicle erasure were run on the small set (test X6e in `evidence/proofs_rejected_and_extra.txt`, line 256, as `ridehail_app`, rolled back; run again in `evidence/migration_015_rerun_rejected_and_extra.txt`, line 317). CONFIRMED for driver 1 only.

**Gaps I did not solve.** Pickup and dropoff coordinates inside `fare_quote` are also personal data and the quote is append-only, so this design does not erase them. Retention periods for every personal field (and the NDPA's rules on erasure versus keeping financial records) are NOT verified and need legal advice (B8, Q5).

**IDs.** B8, B4, B5, B10, Q5. **Enforcers.** trigger `set_updated_at`; trigger `append_only_guard`; trigger `trip_block_delete`; foreign keys with `ON DELETE RESTRICT`; functions `erase_rider` and `erase_driver` with role `ridehail_erasure_owner`; role `ridehail_app` (execute only).

**Soft delete against hard delete, and the compliance reasoning behind the choice.**
- People are anonymised, not removed. rider, driver, vehicle and support_admin take a soft delete (`deleted_at` is set) and their personal fields are blanked, because other rows point at them and the money trail must stay (B4, B8).
- Financial and audit rows are kept for ever. trip, payment, refund, provider_event, trip_status_history, fare_quote, rating and audit_log are never deleted, because they are the financial and audit record (B4, B5, B10). Only the personal text inside them is blanked.
- Raw location is deleted after a retention period. location_ping is the most sensitive data and has no value once the trip is settled, so it is a hard delete. The period is not chosen yet, so no deletion job is designed.
- Short lived keys are deleted. idempotency_key is a hard delete after `expires_at`, because it only exists to make a retry safe for a short time.
- The legal position is not verified. This is a design view, not legal advice. The Nigeria Data Protection Act 2023 was not read for this task, the balance between a right to erasure and a duty to keep financial records is not settled here, and a qualified adviser must confirm the retention periods and the soft against hard delete choice before it is relied on.

[CLASS NOTE NEEDED: compliance reasoning for soft vs hard delete]

---

## Question 5. Identifiers

**Answer.** Every record id is a random UUID, generated by the database with `gen_random_uuid()`, not a counting number. Exceptions are `setting.key` and `status_transition_rule`'s four-column key, which are names, not records.

**Security reason.** A counting id (1, 2, 3...) lets a stranger try 4417, 4418 and read the neighbours' trips, and it tells competitors how many trips you have. A random id of 122 random bits cannot be guessed in practice.

**A random id is NOT authorisation.** Anyone who learns an id (from a log, a screenshot, a shared link or a browser history) can send it. So **every endpoint must still check ownership**: a rider may read a trip only if `trip.rider_id` is their own id, a driver only if `trip.driver_id` is theirs, and support only with a support role. Without that check the random id gives no protection at all. These checks are application code, and the database cannot do them for you.

**Generation method and test (CONFIRMED, rolled back transaction, PostgreSQL 16.15):**

```
CREATE TABLE u(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), n int);
INSERT INTO u(n) VALUES (1),(2),(3);
 76fbb4c0-510f-420f-b484-51f1df65f85f | version 4 | uuid
 659a5d5b-6b82-4f4c-be3f-50693377a563 | version 4 | uuid
 e27b777a-7919-499d-968e-5f5c9fa4c594 | version 4 | uuid
distinct ids: 3
pgcrypto installed: 0     <- the function works without the extension
leftover tables after ROLLBACK: 0
```

`gen_random_uuid()` is built into PostgreSQL 13 and later (INFERRED from the PostgreSQL release notes, not checked this session; CONFIRMED that it works on this 16.15 server without `pgcrypto`). That removes one extension to install. The extension `pgcrypto` is available if later stages want it. That the numbers come from a cryptographically secure source is INFERRED from the PostgreSQL documentation, not tested. Random ids insert into the middle of an index instead of the end, which costs some speed at very large sizes (INFERRED; not measured). I judged that acceptable and keep one rule for all tables, including `location_ping` (decision 9). A time-ordered UUID (version 7) is not built into 16 (INFERRED).

**IDs.** B6 (retry-safe ids), B8 (not leaking volumes of personal data). **Enforcers.** column default `gen_random_uuid()` (database); ownership checks (application code only).

---

## Question 6. Constraints

**Answer.** First every table, then the table of invalid states that are now impossible.

Key to the "Index or justification" column: PK and UNIQUE constraints create their own index. A foreign key does NOT create an index on the child column automatically in Postgres (INFERRED from Postgres rules). So each FK either has an index named in question 7, or a stated reason why none is needed. Check constraints need no index.

**Stage 3 rule: demonstrations of rejected inserts must run as the role `ridehail_app`.** Each demonstration of a refused insert or update (a second active trip, a negative amount, an edit of a completed trip, and so on) must be run after `SET ROLE ridehail_app` (or `SET LOCAL ROLE` inside a rolled back transaction), never as the dev login `ridehail`. Reasons: (1) `ridehail` is a superuser (CONFIRMED, `rolsuper = t`). A superuser skips privilege checks, so a "permission denied" can never appear, and a missing grant would stay invisible. (2) A superuser can switch triggers off or change tables, so a demonstration run that way does not show what the real application can do. (3) Several of my rules depend on `current_user` (the erasure rule), and the rule test CONFIRMED different results for `ridehail_app`, the owner role and a role with no grant (04 question 4, steps X1 to X9). Constraints and triggers still fire for a superuser (they did in every test I ran as `ridehail`, INFERRED to hold generally), so a demonstration as `ridehail` would show some refusals, but it would show them for the wrong audience. Stage 3 had to create the roles for real (permanent objects, in migrations) and grant only what each needs. They now exist: `ridehail_app`, `ridehail_erasure_owner` and `ridehail_writer`, all NOLOGIN. **Done in Stage 3 (migrations 001, 008, 009, 010):** every proof ran after `SET ROLE ridehail_app` from the dev login and printed `current_user`. **Login role test (follow-up 2, CONFIRMED, `evidence/followup2_login_role_test.txt`):** a temporary LOGIN role `ridehail_login_test` (member of `ridehail_app`, random 32-character password generated inside one command, never printed or written) connected over the container's non-loopback address, where `pg_hba` uses `scram-sha-256` (loopback and the local socket are `trust`, so a loopback test would not have shown password authentication). A wrong password was refused. As that role `current_user` and `session_user` were both `ridehail_login_test`; INSERT into `trip_status_history` was refused (permission denied); UPDATE of a `rating` was refused; a trip request worked and wrote its history row; `RESET ROLE` had no effect; `SET ROLE ridehail`, `SET SESSION AUTHORIZATION ridehail`, `SET ROLE ridehail_erasure_owner` and `SET ROLE ridehail_writer` were all refused ("permission denied to set role"); `SET ROLE ridehail_app` worked because it is a member; `pg_authid` could not be read. The role was then dropped (0 rows in `pg_roles`), and counting matches showed the password in 0 files of the project and 0 lines of the container log. **Limit that the test also showed:** that role inherits the app's rights, so it can call `add_support_note`, and the call is refused only because it claimed no support actor. A session that sets `app.actor_role = support` would be accepted. The actor is claimed by the application.

**Migration 015 (Stage 4 follow-up): every rule raised by a trigger or function below has its own SQLSTATE** in the custom class RH (45 codes, `RH001` to `RH080`), so the API chooses an HTTP status from the SQLSTATE and never reads the message text. The message text, the owners, SECURITY DEFINER flags, search paths and grants did not change (CONFIRMED by a before and after catalogue comparison, `evidence/migration_015_catalogue_diff.txt`: the only difference is the count of `USING ERRCODE` clauses). The table of codes is in `06b_error_catalogue.md` section 3. The rule lists below still name the triggers by what they check; the code for each rule is in that table.

### rider
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | rider_pkey | id | own index |
| UNIQUE | rider_phone_key | phone | own index |
| CHECK | rider_phone_format | `phone` looks like +2348012345678, unless `deleted_at` is set | no index needed |
| CHECK | rider_name_not_blank | name is not empty | none needed |
| CHECK | rider_rating_cache_valid | `rating_count >= 0` and `rating_sum` between `rating_count` and 5 times `rating_count` | none needed |
| Trigger | set_updated_at | refreshes `updated_at` | n/a |

### driver
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | driver_pkey | id | own index |
| UNIQUE | driver_phone_key | phone | own index |
| UNIQUE | driver_licence_number_key | licence_number | own index |
| CHECK | driver_phone_format | same as rider | none needed |
| CHECK | driver_name_not_blank | name is not empty | none needed |
| CHECK | driver_rating_cache_valid | same as rider | none needed |
| Trigger | set_updated_at | | n/a |

### vehicle
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | vehicle_pkey | id | own index |
| UNIQUE (partial) | vehicle_plate_number_active_key | `plate_number`, only rows where `deleted_at` is empty. This is a partial unique INDEX, not a constraint: PostgreSQL cannot make a unique constraint partial (found by the catalogue check in Stage 3) | own index |
| UNIQUE | vehicle_id_driver_id_key | (id, driver_id), so that `trip` can point at the pair | own index |
| FK | vehicle_driver_id_fkey | driver_id -> driver.id | index `vehicle_driver_id_idx` (question 7, A2) |
| CHECK | vehicle_seat_count_range | `seat_count` from 1 to 8 | none needed |
| CHECK | vehicle_plate_not_blank | plate is not empty | none needed |
| Trigger | set_updated_at | | n/a |

### trip
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | trip_pkey | id | own index |
| UNIQUE | trip_fare_quote_id_key | fare_quote_id (a quote starts one trip) | own index |
| UNIQUE (partial) | trip_one_active_per_rider | `rider_id` where status in requested, assigned, arrived, started (B0, B1) | own index |
| UNIQUE (partial) | trip_one_active_per_driver | `driver_id` where status in the same four (B0, B2) | own index |
| FK | trip_rider_id_fkey | rider_id -> rider.id | index `trip_rider_history_idx` (all of a rider's trips, question 7). The partial unique index `trip_one_active_per_rider` serves active trips only, so it does not serve this FK by itself |
| FK | trip_driver_id_fkey | driver_id -> driver.id | index `trip_driver_history_idx` (all of a driver's trips). `trip_one_active_per_driver` covers active trips only |
| FK (composite) | trip_vehicle_belongs_to_driver | (vehicle_id, driver_id) -> vehicle(id, driver_id) | no index: vehicles are never hard deleted and nothing looks up trips by vehicle in A1 to A5 |
| FK (composite) | trip_quote_belongs_to_rider | (fare_quote_id, rider_id) -> fare_quote(id, rider_id) | served by `trip_fare_quote_id_key` |
| CHECK | trip_status_valid | status is one of the six values | none needed |
| CHECK | trip_driver_matches_status | requested means no driver; assigned, arrived, started, completed mean a driver | none needed |
| CHECK | trip_snapshots_match_assignment | `driver_id`, `vehicle_id`, `driver_name_snapshot`, `vehicle_plate_snapshot` are all filled or all empty | none needed |
| CHECK | trip_started_has_time | started or completed means `started_at` is filled | none needed |
| CHECK | trip_completed_has_facts | completed means `completed_at`, `fare_amount_minor`, `fare_currency`, `distance_m` are filled, and only then | none needed |
| CHECK | trip_cancelled_has_facts | cancelled means `cancelled_at`, `cancelled_by_role`, `cancellation_fee_minor`, `cancellation_fee_currency` are filled, and only then | none needed |
| CHECK | trip_cancelled_by_valid | `cancelled_by_role` is rider, driver, support or system | none needed |
| CHECK | trip_times_in_order | `completed_at` is not before `started_at` | none needed |
| CHECK | trip_amounts_not_negative | fare, fee and distance are 0 or more | none needed |
| CHECK | trip_currency_ngn | currency fields are empty or NGN | none needed |
| CHECK | trip_fee_needs_driver | a fee above 0 needs `driver_id` (no fee before assignment, B9) | none needed |
| CHECK | trip_fee_only_when_rider_cancels | a fee above 0 needs `cancelled_by_role` = rider (assumption 6) | none needed |
| Trigger | trip_enforce_transition | insert: must be requested, by the trip rider (claimed actor), on an unexpired quote. Terminal rows: only `updated_at` may change, except `current_user` = `ridehail_erasure_owner` on five text columns (B4, B8). Other rows: the driver is set once; a status change needs a rule row for the claimed actor and the right person (rider, driver, support id). It WRITES the derived columns (snapshots, `started_at`, `completed_at`, `cancelled_at`, `cancelled_by_role`, the cancellation fee and currency) and lets only the columns of each move change; a status-unchanged update may change `updated_at` only (details in 03 section 5a) | n/a |
| Trigger | trip_write_history | writes `trip_status_history` with the claimed actor. SECURITY DEFINER, owner `ridehail_writer` (migration 010). EXECUTE revoked from PUBLIC (migration 012); search_path ends with pg_temp (migration 013) | n/a |
| Trigger | trip_block_delete | refuses delete | n/a |
| Trigger | set_updated_at | | n/a |

### trip_status_history
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | trip_status_history_pkey | id | own index |
| FK | history_trip_id_fkey | trip_id -> trip.id | index `trip_status_history_trip_seq_idx` (trip_id is its first column) |
| FK | history_actor_rider_fkey | actor_rider_id -> rider.id | none: never looked up by actor in A1 to A5; riders never hard deleted |
| FK | history_actor_driver_fkey | actor_driver_id -> driver.id | none: same reason |
| FK | history_actor_admin_fkey | actor_admin_id -> support_admin.id | none: same reason |
| CHECK | history_to_status_valid | `to_status` is one of the six | none needed |
| CHECK | history_from_status_valid | `from_status` is empty or one of the six | none needed |
| CHECK | history_status_changes | `from_status` differs from `to_status` | none needed |
| CHECK | history_first_row_is_requested | empty `from_status` means `to_status` is requested | none needed |
| CHECK | history_actor_matches_role | role rider needs only actor_rider_id; driver only actor_driver_id; support only actor_admin_id; system none | none needed |
| Trigger | append_only_guard | refuses update and delete | n/a |

Column `seq bigint GENERATED ALWAYS AS IDENTITY` (migration 010) is not a constraint. It orders the timeline. Its index `trip_status_history_trip_seq_idx` is listed in question 7. Both triggers that matter here are in the trip table's list: `trip_write_history` writes the rows.

### location_ping
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | location_ping_pkey | id | own index |
| FK | ping_trip_id_fkey | trip_id -> trip.id | index `location_ping_trip_recorded_idx` |
| CHECK | ping_latitude_range | -90 to 90 | none needed |
| CHECK | ping_longitude_range | -180 to 180 | none needed |
| CHECK | ping_accuracy_not_negative | `accuracy_m` empty or 0 or more | none needed |
| Trigger | ping_enforce_trip_status | the trip must be assigned, arrived or started | n/a |
| Trigger | append_only_guard | refuses update (delete is allowed for retention) | n/a |

### fare_quote
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | fare_quote_pkey | id | own index |
| UNIQUE | fare_quote_id_rider_id_key | (id, rider_id), so `trip` can point at the pair | own index |
| FK | quote_rider_id_fkey | rider_id -> rider.id | none: quotes are only fetched by id; riders never hard deleted |
| CHECK | quote_amount_not_negative | `amount_minor` is 0 or more | none needed |
| CHECK | quote_currency_ngn | currency is NGN | none needed |
| CHECK | quote_coordinates_valid | the four coordinates are in range | none needed |
| CHECK | quote_estimates_not_negative | distance and duration are 0 or more | none needed |
| CHECK | quote_expires_after_created | `expires_at` is after `created_at` | none needed |
| Trigger | append_only_guard | refuses update and delete | n/a |

### payment
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | payment_pkey | id | own index |
| UNIQUE | payment_provider_reference_key | `provider_reference`, which is a required column: a payment row exists only after the provider returned its reference, so every payment can be matched with `provider_event` rows | own index |
| UNIQUE (partial) | payment_one_live_per_purpose | (`trip_id`, `purpose`) where status is pending or succeeded | own index |
| FK | payment_trip_id_fkey | trip_id -> trip.id | index `payment_trip_id_idx` (migration 016, Stage 4: before it, this column had no index of its own; `payment_one_live_per_purpose` is partial and covers live payments only) |
| CHECK | payment_purpose_valid | fare or cancellation_fee | none needed |
| CHECK | payment_status_valid | pending, succeeded or failed | none needed |
| CHECK | payment_amount_positive | `amount_minor` above 0 | none needed |
| CHECK | payment_currency_ngn | currency is NGN | none needed |
| CHECK | payment_succeeded_has_proof | succeeded needs `provider_reference` and `paid_at`; `paid_at` only when succeeded | none needed |
| CHECK | payment_failed_has_reason | failed needs `failure_reason`, and only then | none needed |
| Trigger | payment_enforce_rules | insert: pending only, by the trip rider (claimed actor), for a completed trip fare or a cancelled trip fee, exact amount. Terminal rows: only `updated_at` may change. Pending rows: a status change needs a rule row for the claimed actor and only the columns of the move may change. For move P3 (support fails a pending payment): a `payment_not_found` event for the same `provider_reference`, received after the payment was created AND not older than the latest provider event of ANY type for that reference (a later `payment_succeeded` cancels the proof). Proved on the real database (X5a to X5c) | uses index `provider_event_reference_idx` for that lookup |
| Trigger | payment_write_audit | after a status change, writes `audit_log` (`status_change`, from and to) with the claimed actor. No row at creation. SECURITY DEFINER, owner `ridehail_writer`. EXECUTE revoked from PUBLIC (migration 012); search_path ends with pg_temp (migration 013) | n/a |
| Trigger | set_updated_at | | n/a |

### provider_event
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | provider_event_pkey | id | own index |
| UNIQUE | provider_event_provider_event_id_key | `provider_event_id` (a repeated provider message is refused) | own index (this is also the lookup the callback handler runs) |
| CHECK | provider_event_type_valid | payment_succeeded, payment_failed, payment_not_found or refund_succeeded | none needed |
| CHECK | provider_event_outcome_valid | `outcome` is empty or applied, ignored_duplicate, needs_support | none needed |
| CHECK | provider_event_amount_positive | `amount_minor` is empty or above 0 | none needed |
| CHECK | provider_event_currency_ngn | `currency` is empty or NGN | none needed |
| CHECK | provider_event_money_pair | `amount_minor` and `currency` are both filled or both empty | none needed |
| CHECK | provider_event_processed_has_outcome | `processed_at` and `outcome` are both filled or both empty | none needed |
| Trigger | provider_event_guard | refuses delete, and refuses any change to the received fields (`provider_event_id`, `provider_reference`, `event_type`, `amount_minor`, `currency`, `occurred_at`, `received_at`); only `processed_at` and `outcome` may be filled in, once | n/a |
| Trigger | provider_event_write_audit | writes an `audit_log` row (`provider_conflict`) when `outcome` becomes needs_support: entity_type `payment`, `refund` or, when nobody has the reference, `provider_event`. SECURITY DEFINER, owner `ridehail_writer`; reads payment and refund columns `id` and `provider_reference`. EXECUTE revoked from PUBLIC (migration 012); search_path ends with pg_temp (migration 013) | n/a |
| Trigger | set_updated_at | | n/a |

No foreign key: `provider_reference` is matched by value (02b, R20). `occurred_at` is the provider's own time, optional, and has no check (the provider's clock is not trusted). `received_at` defaults to `clock_timestamp()`, not `now()`: inside one transaction `now()` is the same for every row, so the order of events (needed by P3) would be lost. Extra index: `provider_event_reference_idx` on (`provider_reference`), for the payment trigger's lookup of a `payment_not_found` event (question 7).

### refund
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | refund_pkey | id | own index |
| UNIQUE | refund_provider_reference_key | `provider_reference` | own index |
| FK | refund_payment_id_fkey | payment_id -> payment.id | index `refund_payment_id_idx` |
| FK | refund_created_by_admin_fkey | created_by_admin_id -> support_admin.id | none: never looked up by admin in A1 to A5; admins never hard deleted |
| CHECK | refund_amount_positive | `amount_minor` above 0 | none needed |
| CHECK | refund_currency_ngn | currency is NGN | none needed |
| CHECK | refund_reason_not_blank | reason is not empty | none needed |
| Trigger | refund_enforce_total | payment succeeded, currencies match, total not above payment (B10) | n/a |
| Trigger | append_only_guard | refuses update and delete | n/a |

### rating
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | rating_pkey | id | own index |
| UNIQUE | rating_one_per_role_per_trip | (`trip_id`, `rater_role`) | own index |
| FK | rating_trip_id_fkey | trip_id -> trip.id | served by `rating_one_per_role_per_trip` (trip_id is its first column) |
| CHECK | rating_role_valid | rider or driver | none needed |
| CHECK | rating_stars_range | 1 to 5 | none needed |
| CHECK | rating_comment_length | comment empty or up to 500 characters | none needed |
| Trigger | rating_enforce_rules | trip completed, inside the window from setting `rating_window_days`, claimed actor is that side of the trip | n/a |
| Trigger | rating_update_cache | adds to the other person's totals | n/a |
| Trigger | rating_block_change | refuses update and delete, except blanking `comment` when `current_user` is `ridehail_erasure_owner` | n/a |

### idempotency_key
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | idempotency_key_pkey | id | own index |
| UNIQUE | idem_one_key_per_rider_action | (`rider_id`, `action`, `key`) | own index (this is also the retry lookup in A1 and A4) |
| FK | idem_rider_id_fkey | rider_id -> rider.id | served by `idem_one_key_per_rider_action` (rider_id is its first column) |
| FK | idem_trip_id_fkey | trip_id -> trip.id | none: the table is small and short-lived, rows are deleted after expiry |
| FK | idem_payment_id_fkey | payment_id -> payment.id | none: same reason |
| CHECK | idem_action_valid | request_trip or pay_trip | none needed |
| CHECK | idem_key_length | 1 to 128 characters | none needed |
| CHECK | idem_hash_format | `request_hash` is 64 lowercase hex characters | none needed |
| CHECK | idem_response_complete | `response_status` and `response_body` are both filled or both empty | none needed |
| Trigger | set_updated_at | | n/a |

### setting
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | setting_pkey | key | own index |
| FK | setting_updated_by_fkey | updated_by_admin_id -> support_admin.id | none: about a dozen rows in total |
| CHECK | setting_value_not_negative | `int_value` is 0 or more | none needed |
| CHECK | setting_currency_ngn | currency empty or NGN | none needed |
| CHECK | setting_money_has_currency | a key ending in `_minor` has a currency, and no other key does | none needed |
| Trigger | setting_write_audit | writes `audit_log` (`setting_change`, key, old and new value in `details`) on insert or update; refuses any actor but a claimed support actor with an id. SECURITY DEFINER, owner `ridehail_writer`. EXECUTE revoked from PUBLIC (migration 012); search_path ends with pg_temp (migration 013) | n/a |
| Trigger | set_updated_at | | n/a |

### support_admin
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | support_admin_pkey | id | own index |
| UNIQUE | support_admin_email_key | email | own index |
| CHECK | support_admin_email_format | email contains an @ with text before it | none needed |
| CHECK | support_admin_name_not_blank | name is not empty | none needed |
| Trigger | set_updated_at | | n/a |

### audit_log
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | audit_log_pkey | id | own index |
| FK | audit_actor_rider_fkey | actor_rider_id -> rider.id | none: see question 7, audit_log is left without extra indexes |
| FK | audit_actor_driver_fkey | actor_driver_id -> driver.id | none: same |
| FK | audit_actor_admin_fkey | actor_admin_id -> support_admin.id | none: same |
| CHECK | audit_actor_matches_role | rider, driver, support need exactly their own actor id; provider and system need none | none needed |
| CHECK | audit_entity_type_valid | one of trip, payment, refund, rating, rider, driver, setting, provider_event (`provider_event` added in Stage 3 for provider messages about an unknown reference) | none needed |
| CHECK | audit_entity_id_matches_type | `entity_id` is empty exactly when the type is setting | none needed |
| Trigger | append_only_guard | refuses update and delete | n/a |

### status_transition_rule
| Kind | Name | Rule | Index or justification |
|---|---|---|---|
| PK | rule_pkey | (`entity`, `from_status`, `to_status`, `actor_role`) | own index (this is also the lookup the triggers run) |
| CHECK | rule_entity_valid | trip or payment | none needed |
| CHECK | rule_actor_role_valid | rider, driver, support, provider or system | none needed |
| CHECK | rule_from_differs_to | `from_status` differs from `to_status` | none needed |

### Invalid states that are now impossible

"Tested" points to a rolled back run. The ids are: steps 1 to 16 are the trigger test in `03_state_machine.md` section 7; P, R, I and G ids are the payment, refund, idempotency and rating tests of the Stage 2 report; E ids are the provider_event test in 03 section 4a; X ids are the erasure test in question 4; S ids are the stuck-payment test in 03 section 4b (test 4 of the round 2 report). "Not tested" means I reasoned it only.

| Invalid state | ID | Exact blocker | Enforced by | Tested |
|---|---|---|---|---|
| A rider with two active trips | B1 | partial unique index `trip_one_active_per_rider` | database | yes, trigger test step 2 |
| A driver with two active trips | B2 | partial unique index `trip_one_active_per_driver` | database | yes, step 5 |
| A rating without a completed trip | B7 | trigger `rating_enforce_rules` | database | yes, G4 |
| A rating after the 7 days | B7 | trigger `rating_enforce_rules` | database | yes, G5 (test used a fixed 7 days; the real trigger reads the setting) |
| A second rating by the same person on a trip | B7 | unique constraint `rating_one_per_role_per_trip` | database | yes, G2 |
| Two payments for one trip fare | A4, B6 | partial unique index `payment_one_live_per_purpose` | database | yes, P2 and P4 |
| A duplicate idempotency key | B6 | unique constraint `idem_one_key_per_rider_action` | database (the replay of the stored answer is application code) | yes, I1; I2 and I3 show it is per rider and per action |
| A duplicate provider payment reference | B6 | unique constraint `payment_provider_reference_key` | database | yes, P8 |
| A negative or zero payment | B3 | `payment_amount_positive` | database | yes, P5 and P6 |
| Negative amounts elsewhere | B3 | `quote_amount_not_negative`, `trip_amounts_not_negative`, `refund_amount_positive`, `setting_value_not_negative` | database | not tested (same kind of check as P5) |
| A currency other than NGN | B3 | `payment_currency_ngn`, `quote_currency_ngn`, `trip_currency_ngn`, `refund_currency_ngn`, `setting_currency_ngn` | database | yes for payment (P7); the others not tested |
| Editing a completed trip's fare | B4 | terminal freeze in `trip_enforce_transition` | database | yes, step 12 |
| A completed trip with no fare | B4 | `trip_completed_has_facts` | database | not tested at first; later yes on the built database, E42 (SQLSTATE 23514, "violates check constraint "trip_completed_has_facts"", `evidence/migration_015_error_tests_compare.txt` line 60) |
| Refunds above the payment | B10 | trigger `refund_enforce_total` | database | yes, R2 and R4; R5 for a non-succeeded payment |
| A trip using another driver's vehicle | A2 | `trip_vehicle_belongs_to_driver` | database | not tested at first; later yes on the built database, E09 (SQLSTATE 23503, "violates foreign key constraint "trip_vehicle_belongs_to_driver"", same file, line 12) |
| A trip using another rider's quote | A1 | `trip_quote_belongs_to_rider` | database | not tested at first; later yes on the built database, E02a and E02b (SQLSTATE 23503, "violates foreign key constraint "trip_quote_belongs_to_rider"", same file, lines 3 and 4) |
| A trip started on an expired quote | A1 | trigger `trip_enforce_transition` (insert branch) | database | not tested at first; later yes on the built database, E04 (SQLSTATE RH004, "fare quote ... has expired", same file, line 6) |
| A location ping on a finished trip | A3 | trigger `ping_enforce_trip_status` | database | not tested at first; later yes on the built database, E10 (SQLSTATE RH030, "a location ping needs a trip that is assigned, arrived or started (status is completed)", same file, line 13) |
| An illegal status move | B5 | `status_transition_rule` + `trip_enforce_transition` | database | yes, steps 3, 6 to 8, 10, 11, 14, 16 |
| A status change with no history row | B5 | trigger `trip_write_history` | database | yes (9 history rows in the test) |
| A decimal amount such as 10.5 kobo | B3 | API validation | **application code only** | confirmed that the database does not stop it (question 2) |
| A person reading or changing someone else's trip | B8 | ownership check on every endpoint | **application code only** (the trigger check on the claimed actor id helps, but only trusts what the app says) | not applicable yet |
| A retry that gets a new answer instead of the stored one | B6 | code that looks up and returns `response_body` | **application code only** | not applicable yet |
| Support failing a pending payment with no proof, with the wrong reference, the wrong type, or an old event | A4, B6 | trigger `payment_enforce_rules` (move P3 lookup) | database | yes, test 4 S1 to S4 |
| Support failing a succeeded payment, or marking a pending one succeeded | A4, B6 | terminal freeze and no rule row for that move | database | yes, test 4 S7 and S8 |
| A provider callback applied twice | U4, B6 | unique constraint `provider_event_provider_event_id_key` (the second message is refused or does nothing) | database (the handler that decides outcomes is application code) | yes, test 1 steps E1 to E3b (one row after repeats) |
| Our own clock marking a pending payment as failed | A4 | no row for actor `system` in the payment rules, and trigger `payment_enforce_rules` | database | not tested (same lookup as the trip moves) |
| The API role blanking an address or editing a rating comment directly | B4, B8 | the freeze trigger and `rating_block_change` check `current_user` | database | yes, test 2 steps X1 to X3 |
| A role with no grant calling the erasure function | B8 | `EXECUTE` revoked from `PUBLIC` and granted only to `ridehail_app` | database | yes, test 2 step X7 |
| Erasing a person with an active trip | B8 | check inside `erase_rider` and `erase_driver` | database (the driver version was untested at first) | yes for riders, test 2 step X6; for drivers, later on the built database: the refusal is E26b (SQLSTATE RH071, "driver ... has an active trip: cannot erase (B8)", `evidence/migration_015_error_tests_compare.txt` line 31) and erase_driver itself ran in X6e (`evidence/proofs_rejected_and_extra.txt`, line 256) |
| A request cancelled by a non-system actor for timeout, or the system cancelling an assigned trip | B9 | rule rows in `status_transition_rule` | database | not tested |
| A timeout job that never runs | B9, B1 | the scheduled job | **application code only** | not applicable yet |

**Is a partial unique index enough for B2?** Yes for "at most one active trip per driver": rows with no driver have an empty `driver_id`, and empty values never collide in a unique index, so waiting trips do not block anyone. Completed and cancelled rows are outside the predicate, so a driver can take the next trip (test step 5 showed the second active trip refused; step 15 showed the freed slot for a rider). It is not enough for "this driver is the one calling", which needs the actor check, or "this is the driver's own car", which needs the composite foreign key. Two drivers accepting at the same instant: one insert or update waits for the other and then fails with a unique violation or finds `status` no longer requested (INFERRED; not raced).

**IDs.** B1 to B10, A1 to A5. **Enforcers.** as listed per table.

---

## Question 7. Indexes

**Answer.** I add few indexes beyond the ones constraints already create. A new index makes every write slower and takes space, so each one below earns its place by a named query. The first choice was made by reasoning (INFERRED). The choices were later measured with `EXPLAIN (ANALYZE)` on the built database (CONFIRMED, `evidence/plans_for_grader.txt` and `evidence/plans_all_candidates_after_vacuum.txt`), as the sections below show.

### A1: a rider requests a trip
```sql
-- 1 retry check
SELECT response_status, response_body FROM idempotency_key
WHERE rider_id = $1 AND action = 'request_trip' AND key = $2;
-- 2 read the owner-approved settings (fare, service area)
SELECT key, int_value FROM setting WHERE key LIKE 'service_area%' OR key IN ('base_fare_minor','per_km_minor','per_minute_minor');
-- 3 create the quote, then the trip
INSERT INTO fare_quote (...) VALUES (...);
INSERT INTO trip (rider_id, fare_quote_id, pickup_address, dropoff_address, status) VALUES (...);
```
Index: query 1 is served by the unique constraint `idem_one_key_per_rider_action`. Query 2 reads about a dozen rows by primary key, so `setting_pkey` or even a full scan is enough. The inserts need no read index. The check for an existing active trip is done by `trip_one_active_per_rider` itself at insert time. If the API also wants to *read* the rider's active trip, the query must repeat the index condition exactly: `WHERE rider_id = $1 AND status IN ('requested','assigned','arrived','started')` (see the partial index note below). Reason: B6, B1.

### A2: a nearby driver accepts
```sql
-- the driver's app asks for open requests near its position (rectangle of coordinates)
SELECT t.id, t.pickup_address, q.pickup_latitude, q.pickup_longitude, q.amount_minor
FROM trip t JOIN fare_quote q ON q.id = t.fare_quote_id
WHERE t.status = 'requested'
  AND q.pickup_latitude  BETWEEN $1 AND $2
  AND q.pickup_longitude BETWEEN $3 AND $4
ORDER BY t.created_at LIMIT 20;
-- the driver's vehicle
SELECT id, plate_number FROM vehicle WHERE driver_id = $1 AND is_active AND deleted_at IS NULL;
-- accept
UPDATE trip SET status = 'assigned', driver_id = $1, vehicle_id = $2
WHERE id = $3 AND status = 'requested';
```
Indexes:
- `trip_requested_created_at_idx` ON trip (created_at) WHERE status = 'requested'. A partial index holds only waiting trips. **It stays small only after VACUUM**: every trip that leaves `requested` leaves a dead entry in it until vacuum removes it. **The A2.1 query does not read it in order and stop after 20 rows.** The rectangle is on `fare_quote`, so Postgres must first find all waiting trips, then look up each trip's quote, filter by the rectangle, sort and cut to 20. With 401 waiting trips that is a bitmap scan, a sort and 401 lookups. It **will not scale with a large waiting list**: the cost grows with the number of waiting trips, not with the 20 rows returned. I deliberately do not index the coordinates (the waiting set is small today). At scale PostGIS and a GiST index would replace the rectangle, but PostGIS is not available here. A query that has only `status = 'requested' ORDER BY created_at LIMIT 20` (no rectangle) does read this index in order (CONFIRMED, Stage 3 plan 1a).
- `vehicle_driver_id_idx` ON vehicle (driver_id). Without it, finding a driver's car scans every vehicle. It also supports the foreign key `vehicle_driver_id_fkey`.
- The accept uses `trip_pkey`. The "driver already busy" check is `trip_one_active_per_driver`.

**Measured on the real database (Stage 3, bulk set of 200,012 trips, 401 waiting, EXPLAIN (ANALYZE, BUFFERS), as `ridehail_app`; CONFIRMED, `evidence/plan_heaviest_1_A2_open_requests.txt` and `plan_heaviest_1_A2_after_vacuum.txt`):**
- Right after the bulk load: **20.6 ms**, 5,817 buffers. `Bitmap Heap Scan on trip` (3,956 heap blocks) over a BitmapAnd of `trip_one_active_per_driver` (24,446 entries) and `trip_requested_created_at_idx` (9,354 entries) for only 401 real rows, then 401 `Index Scan using fare_quote_pkey` lookups, then Sort and Limit. No Seq Scan. The extra entries were dead index entries from 200,000 trips that had left `requested`.
- After `VACUUM (ANALYZE) trip, payment`: **3.4 ms**, 1,713 buffers, entries 708 and 403, 45 heap blocks. Same plan shape.
- **The planner also used `trip_one_active_per_driver`** (a partial index on the four active statuses) in the BitmapAnd. It is valid because `status = 'requested'` implies the four-status condition, but it is not the index the doc planned for, and it adds work.
- The 401 `fare_quote` lookups are the cost that remains, so the plan is a bitmap scan plus a sort plus 401 lookups, not a short ordered scan.

**Re-measured (follow-up 2, after `VACUUM (ANALYZE)` of `trip`, `payment` and `trip_status_history`; EXPLAIN (ANALYZE, BUFFERS), the file run twice and the second run kept; CONFIRMED, `evidence/followup2_plans_all_candidates.txt`):**
- **A2.1: 3.46 ms**, 1,722 buffers, same plan shape: `Bitmap Heap Scan on trip` (54 heap blocks) over a BitmapAnd of `trip_one_active_per_driver` (726 entries) and `trip_requested_created_at_idx` (420 entries), then 401 `Index Scan using fare_quote_pkey`, Sort, Limit. No Seq Scan. After migration 013 the same query measured 1.1 to 1.5 ms on two further runs, so single timings on this machine vary by a factor of about 3. The conclusion does not change: the cost is the 401 quote lookups and grows with the waiting list.
- **Second heaviest READ query measured:** the reconciliation query P14 (pending payments older than 900 s), **0.63 ms**, `Index Scan using payment_pending_created_at_idx`, 115 buffers, no Seq Scan (not one of A1 to A5). Among the reads of A1 to A5 the second heaviest is the A1.1 retry check, **0.26 ms**, `Index Scan using idem_one_key_per_rider_action`, 4 buffers.
- **Which two to show for the brief ("the two heaviest queries"):** A2.1 (the heaviest read, and the only one whose cost grows with data it does not return) and the A1.3 trip insert (the heaviest statement of all, 7 to 31 ms depending on cache state, almost all of it in the two triggers `trip_enforce_transition` and `trip_write_history`). The second heaviest read is under a millisecond and uses a single index lookup, so it shows nothing the other plans do not. Writes were the heaviest statements on every run: A1.3 about 7 to 31 ms, A2.3 accept 5 to 15 ms.

### A3: the rider watches, the driver moves the trip
```sql
-- latest driver position for the rider's map
SELECT latitude, longitude, recorded_at FROM location_ping
WHERE trip_id = $1 ORDER BY recorded_at DESC LIMIT 1;
-- driver moves the trip
UPDATE trip SET status = $2 WHERE id = $1 AND driver_id = $3 AND status = $4;
-- status timeline (ordered by seq, not created_at: all moves of one transaction share one created_at)
SELECT from_status, to_status, actor_role, created_at FROM trip_status_history
WHERE trip_id = $1 ORDER BY seq;
```
Indexes:
- `location_ping_trip_recorded_idx` ON location_ping (trip_id, recorded_at DESC). This is the busiest table (a ping every few seconds), and the "latest ping" query reads the first entry of one index range. It also supports `ping_trip_id_fkey`.
- `trip_status_history_trip_seq_idx` ON trip_status_history (trip_id, seq) (migration 010). Reads one trip's timeline already in order (CONFIRMED: `Index Scan using trip_status_history_trip_seq_idx`). It also supports `history_trip_id_fkey`.
- `trip_status_history_trip_idx` ON trip_status_history (trip_id, created_at) (migration 007) was **dropped by migration 012**. The timeline is ordered by `seq`, and `history_trip_id_fkey` is served by the `seq` index. Evidence (CONFIRMED, `evidence/followup2_012_a_index_usage.txt`): after resetting the usage counters and running every file in `db/queries`, three diagnostic proof statements had still used it: two that any index starting with `trip_id` can serve, and one that orders by `created_at` on purpose to show the old, wrong order. No application query used it. After the drop all three still run (they use the `seq` index; the legacy-order one sorts).
- The update uses `trip_pkey`.

### History lists for riders and drivers (not one of A1 to A5, added at your request)
```sql
-- first page, then next pages with keyset pagination (no OFFSET)
SELECT id, status, created_at FROM trip
WHERE rider_id = $1
  AND ($2::timestamptz IS NULL OR (created_at, id) < ($2, $3))
ORDER BY created_at DESC, id DESC
LIMIT 20;
-- the same for a driver, with driver_id = $1
```
Indexes: `trip_rider_history_idx` ON trip (rider_id, created_at DESC, id DESC) and `trip_driver_history_idx` ON trip (driver_id, created_at DESC, id DESC). They match the `ORDER BY` exactly, so Postgres reads the rows already in order and stops after 20, however long the history is. `id` is the tie-break, so two trips with the same `created_at` are never skipped or repeated between pages. Keyset pagination is used instead of `OFFSET` because `OFFSET 10000` still reads and throws away 10,000 rows. They also serve the foreign keys `trip_rider_id_fkey` and `trip_driver_id_fkey`.

**Tested (CONFIRMED, rolled back transaction, 60,000 generated trips over 500 riders, after ANALYZE, `EXPLAIN (COSTS OFF)`):**
```
keyset page, rider_id = 7 and (created_at, id) < (...) ORDER BY created_at DESC, id DESC LIMIT 20
  -> Limit -> Index Scan using trip_rider_history_idx   (Index Cond: rider_id = 7 AND ROW(created_at, id) < ROW(...)); no Sort node
first page, rider_id = 7 ORDER BY created_at DESC, id DESC LIMIT 20
  -> Limit -> Index Scan using trip_rider_history_idx; no Sort node
ORDER BY created_at ASC, id ASC
  -> Limit -> Index Only Scan Backward using trip_rider_history_idx
after ROLLBACK: 0 tables or indexes, 0 functions, 0 extra roles
```
The driver index is the same shape and was not run separately (INFERRED). With 60,000 rows the plans are a sample, not a promise for production data.

**A partial index is used only if the query repeats its condition.** `trip_one_active_per_rider` and `trip_one_active_per_driver` hold only rows with status in requested, assigned, arrived, started. Postgres uses such an index for a read only when it can prove that the query's condition implies the index's condition. **Tested (CONFIRMED, same transaction, a non-unique partial index with the same condition on the same 60,000 rows):**
```
WHERE rider_id = 7 AND status IN ('requested','assigned','arrived','started')  -> Index Scan using partial_active_rider
WHERE rider_id = 7 AND status <> 'completed'                                   -> Seq Scan  (index not used)
WHERE rider_id = 7                                                              -> Seq Scan  (index not used)
```
So a query must repeat the index condition exactly. Writing `status <> 'completed'` looks equivalent (it is not, because `cancelled` also matches) and silently falls back to reading the whole table. The test used a non-unique partial index; a unique one has the same condition and I expect the same behaviour (INFERRED). **Stage 3 must check every query that is meant to use a partial index with `EXPLAIN` on realistic data.** The same applies to `trip_requested_created_at_idx`, which needs the exact `status = 'requested'`, and to `payment_one_live_per_purpose`.

**Measured on the real tables (Stage 3, after VACUUM, `EXPLAIN (COSTS OFF)`; CONFIRMED, `evidence/plans_partial_and_unused_indexes.txt`):**
```
trip_requested_created_at_idx:   status = 'requested' ORDER BY created_at LIMIT 20      -> Index Scan using trip_requested_created_at_idx
                                 status IN ('requested','assigned') ...                    -> Sort + Bitmap Heap Scan via trip_one_active_per_driver (not this index)
                                 status <> 'completed' ...                                 -> Gather Merge, Sort, Parallel Seq Scan on trip
trip_one_active_per_rider:       rider_id = X AND status IN (the four active statuses)      -> Index Scan using trip_one_active_per_rider
                                 rider_id = X AND status <> 'completed'                    -> Bitmap Index Scan on trip_rider_history_idx
                                 rider_id = X                                              -> Bitmap Index Scan on trip_rider_history_idx
payment_pending_created_at_idx:  status = 'pending' AND created_at < now() ORDER BY ...     -> Index Scan using payment_pending_created_at_idx
                                 status <> 'succeeded' ...                                 -> Gather Merge, Sort, Parallel Seq Scan on payment
                                 status IN ('pending','failed') ...                        -> Gather Merge, Sort, Parallel Seq Scan on payment
```
The rule is confirmed: a query that does not repeat the condition exactly loses the partial index, and for the trip and payment status queries that means a scan of the whole table. For the rider queries the history index took over, so the loss costs less. Stage 3 checked every query that is meant to use a partial index this way; it should do so again for each new query.

### Stuck-payment lookups (reconciliation job and move P3)
```sql
-- reconciliation job: pending payments older than the setting payment_reconcile_after_seconds
SELECT id, provider_reference FROM payment
WHERE status = 'pending' AND created_at < now() - make_interval(secs => $1)
ORDER BY created_at LIMIT 100;
-- trigger payment_enforce_rules, move P3 (support fails a pending payment)
SELECT 1 FROM provider_event
WHERE provider_reference = $1 AND event_type = 'payment_not_found' AND received_at >= $2;
```
Indexes: `payment_pending_created_at_idx` ON payment (created_at) WHERE status = 'pending'. A partial index holds only pending payments, which are few, so the job reads a tiny index in age order instead of scanning every payment ever made. The query must repeat `status = 'pending'` exactly (see the partial index note above). `provider_event_reference_idx` ON provider_event (provider_reference) serves the lookup in P3. Without it, each support action would scan every provider event ever received. It is a rare query, but the trigger runs inside the support person's update, so it must not be slow. Both indexes were later run through EXPLAIN on the built database (CONFIRMED). `payment_pending_created_at_idx`: the reconciliation query P14 is an Index Scan using that index, 0.628 ms, 115 buffers (`evidence/followup2_plans_all_candidates.txt`, line 270). `provider_event_reference_idx`: the P3 lookup is an Index Scan using it (`evidence/plans_partial_and_unused_indexes.txt`, section 2c, 17544 events). The request timeout job reads `trip_requested_created_at_idx` (it needs exactly `status = 'requested'`).

### A4: the rider pays
```sql
SELECT id, status, fare_amount_minor, cancellation_fee_minor FROM trip WHERE id = $1 AND rider_id = $2;
INSERT INTO payment (trip_id, purpose, amount_minor, currency, provider_reference, status) VALUES (...);
-- provider callback: record the message first, then apply it only if it was new
INSERT INTO provider_event (provider_event_id, provider_reference, event_type, amount_minor, currency)
VALUES ($1, $2, $3, $4, $5) ON CONFLICT (provider_event_id) DO NOTHING RETURNING id;
UPDATE payment SET status = 'succeeded', paid_at = now()
WHERE provider_reference = $1 AND status = 'pending';
```
Indexes: all served by constraint indexes. The first by `trip_pkey`. The insert is guarded by `payment_one_live_per_purpose`. The event insert is guarded by `provider_event_provider_event_id_key`. The provider's callback finds the payment through `payment_provider_reference_key`. No extra index. The retry check reuses the unique constraint `idem_one_key_per_rider_action`.

### A5: both sides rate
```sql
INSERT INTO rating (trip_id, rater_role, stars, comment) VALUES ($1, $2, $3, $4);
```
Indexes: the unique constraint `rating_one_per_role_per_trip` is checked on insert and also serves lookups by trip. The trigger reads `trip` and `setting` by primary key and updates one rider or driver row by primary key.

### Refund total (B10)
`refund_payment_id_idx` ON refund (payment_id). The trigger runs `SELECT sum(amount_minor) FROM refund WHERE payment_id = $1` before each refund. It also supports `refund_payment_id_fkey`. **Not used at the current size** (CONFIRMED, Stage 3 plan 2a): the refund table has 1 row, so Postgres reads it with a Seq Scan. The index is kept for a large refund table, but that use has not been shown.

### Payments of a trip (found in Stage 4 Part B, migration 016)
`payment_trip_id_idx` ON payment (trip_id). EP03 returns every payment of a trip (any status, so a failed attempt stays visible), EP15 and the support payment views look payments up by trip. Before migration 016 that read was a parallel Seq Scan of the whole payment table (169,410 rows, 14.5 to 17.7 ms, CONFIRMED, `evidence/migration_016_measure_before.txt`), because the only index that starts with `trip_id`, `payment_one_live_per_purpose`, is partial and cannot answer a read that does not repeat its condition. After the migration the same read is an `Index Scan using payment_trip_id_idx` (0.06 to 0.10 ms), and the EP03 full read fell from 13.8 to 16.2 ms to 0.14 to 0.32 ms (CONFIRMED, `evidence/migration_016_measure_after.txt` and `migration_016_polling_remeasure.txt`). The index is 5.13 MB against a 27 MB table and 34 MB of existing indexes on it. The foreign key `payment_trip_id_fkey` did not have an index on its referencing column before (PostgreSQL does not create one for a foreign key; the partial index could not serve it for failed payments); this index now serves it. Cost on a payment insert: one more entry to write, which could not be told apart from timing noise in six runs and a paired test (see `evidence/migration_016_insert_cost_paired.txt`). **IDs.** A4, B6, U1, U3.
`rider_pkey`, `rider_phone_key`, `driver_pkey`, `driver_phone_key`, `driver_licence_number_key`, `vehicle_pkey`, `vehicle_plate_number_active_key`, `vehicle_id_driver_id_key`, `trip_pkey`, `trip_fare_quote_id_key`, `trip_one_active_per_rider`, `trip_one_active_per_driver`, `trip_status_history_pkey`, `location_ping_pkey`, `fare_quote_pkey`, `fare_quote_id_rider_id_key`, `payment_pkey`, `payment_provider_reference_key`, `payment_one_live_per_purpose`, `refund_pkey`, `refund_provider_reference_key`, `rating_pkey`, `rating_one_per_role_per_trip`, `idempotency_key_pkey`, `idem_one_key_per_rider_action`, `provider_event_pkey`, `provider_event_provider_event_id_key`, `setting_pkey`, `support_admin_pkey`, `support_admin_email_key`, `audit_log_pkey`, `rule_pkey`. That is 32 (it was 30 before `provider_event`). Ten more are created on purpose: `trip_requested_created_at_idx`, `vehicle_driver_id_idx`, `trip_status_history_trip_seq_idx`, `location_ping_trip_recorded_idx`, `refund_payment_id_idx`, `trip_rider_history_idx`, `trip_driver_history_idx`, `payment_pending_created_at_idx`, `provider_event_reference_idx` and `payment_trip_id_idx` (migration 016). The built database has **42** indexes in all (CONFIRMED by count, `SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'` returned 42): 32 + 10. History of the count: 35, then 39, then 41 (Stage 3), then 42 with `trip_status_history_trip_seq_idx` (migration 010), then 41 again when migration 012 dropped `trip_status_history_trip_idx`, then 42 again with `payment_trip_id_idx` (migration 016).

### Tables left without extra indexes, on purpose
- **audit_log:** it is write-heavy and read only by support, rarely. Support reads a trip's story from `trip_status_history`. An index on (`entity_type`, `entity_id`) should be added only when the API stage defines the support search and shows it is slow.
- **fare_quote, idempotency_key (expiry), rating, setting, support_admin, status_transition_rule:** small, or read only by primary key or by a constraint's index. The cleanup `DELETE FROM idempotency_key WHERE expires_at < now()` scans a table kept short by that same cleanup. I judged it not worth an index on `expires_at`.
- **provider_event, other than `provider_event_reference_idx`:** read by `provider_event_id` (a unique index already). No index on `event_type`, `outcome` or `received_at`: a support list of events that need support is left for the API stage.
- **all foreign keys named "none" in question 6:** not read by any of A1 to A5, and the parent rows are never hard deleted, so no cascade check scans them. (Payments by trip were on this list until Stage 4, when EP03 needed them: see "Payments of a trip" above, migration 016.)

**IDs.** A1 to A5, B1, B2, B6, B10, U4. **Enforcers.** the indexes named, plus the constraints that created the rest.


