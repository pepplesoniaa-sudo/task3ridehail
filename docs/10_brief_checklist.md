# 10 Brief Checklist

Written on 7 October 2026 and updated on 7 October 2026 (Stage 5 prep 2) so that requirement 4 and the contract mapping reflect three written design assumptions (D13, D16, D5), and again on 7 October 2026 (Stage 5 prep 3) so that the authentication assumption makes short life the baseline and the denylist an optional hardening. This file answers one question: for each thing the brief asks for, where is the answer, how complete is it, and what is missing. It is deliberately strict. A claim without evidence is marked PARTIAL.

Status words used:
* DONE: the answer exists and the evidence for it exists.
* DONE BUT NEEDS OWNER IMAGE: the answer and the text evidence exist, but the brief asks for a picture or a screenshot that only the owner can produce.
* PARTIAL: something the brief asks for is missing, unconfirmed, or rests on an open decision.

Labels: CONFIRMED means the output was run and kept in `evidence/`. INFERRED means reasoned, not run. Paths are relative to the project folder `C:\dev\task3ridehail` (the project is API DESIGN AND DATA MODELLING). The database counts quoted in this file are the ones from the catalogue check after migration 016 (`evidence/catalogue_check_016.txt`: 16 tables, 116 constraints, 42 indexes, 27 triggers, 18 functions, 4 roles, 0 mismatches); the check was run again at the end of this stage, with the outputs in `evidence/catalogue_check_stage5_prep.txt`, `catalogue_check_stage5_prep2.txt` and `catalogue_check_stage5_prep3.txt` (section 5).

## 1. The brief's requirements, one by one

### Requirement 1. Requirements page
Answered in: `docs/01_requirements.md` (744 words). It holds the four users U1 to U4, the five key actions A1 to A5, the rules B0 to B10, the non goals, and the questions Q1 to Q6.
Status: DONE.
Missing: nothing the brief asks for. Two things to know. It is longer than the first target of about 450 words (CONFIRMED by a word count: 744). Q5 (location retention) and Q6 (a driver who never arrives) are open on purpose, and `docs/09_open_items.md` lists them as decisions D8 and D9.

### Requirement 2. Full entity list with fields, types, identifiers and cardinalities
Answered in: `docs/02_entities.md` (16 entities; every field has a type, a required or optional marker and a note; every entity has an "Identifier" line, 17 such lines in the file, one for the shared convention and one for each of the 16 entities) and `docs/02b_relationships.md` (section "Every related pair", rows R1 to R20, each with a cardinality; the section "Many to many"; the section "Three links that are NOT foreign keys, and why").
Evidence: the catalogue check, pass 1, compares the fields of `02` with the real columns: 165 columns in the database, 165 field rows in `02`, none missing in either direction (CONFIRMED, `evidence/catalogue_check_016.txt`).
Status: DONE.
Missing: nothing in the text. The picture of the relationships is evidence item 1 below.

### Requirement 3. All seven hard questions answered in writing
Answered in: `docs/04_hard_questions.md`, seven sections, each starting with an "Answer" paragraph (seven of seven, CONFIRMED by a count). Question 1 normalisation and denormalisation (line 7). Question 2 money (line 61). Question 3 status and state (line 104). Question 4 time, deletion and personal data (line 134). Question 5 identifiers (line 194). Question 6 constraints, with a table per entity and the table of invalid states that are now impossible (line 221). Question 7 indexes, with the queries they serve and the measured plans (line 491).
Status: DONE.
Missing: nothing is missing as a written answer. One limit is stated inside the answers and is still open: for personal data (Question 4) the Nigerian data protection law was not read and retention periods are not verified. That is decision D8 in `docs/09_open_items.md`. The answer says so, so it is honest, but the legal point itself is not settled.

### Requirement 4. Complete endpoint contracts including errors and idempotency
Answered in: `docs/06_api_contracts.md` (27 endpoints EP01 to EP27 and 3 internal jobs JB1 to JB3; for each endpoint the caller, the exact ownership check, the request, the success response, an error table with the database cause, the idempotency rule and the session settings), `docs/06b_error_catalogue.md` (45 error codes with status, meaning, retry rule and database cause; 45 SQLSTATE codes in section 3; every constraint and trigger of question 6 mapped or marked internal) and `docs/06c_endpoint_matrix.md` (endpoints against roles and against requirement IDs).
Evidence: every database error mapped to a status was run as the application role and the real message and SQLSTATE kept (`evidence/api_error_mapping_tests.txt`, `evidence/migration_015_error_tests_compare.txt`, `evidence/untested_rh_codes_proofs.txt`; all 45 RH codes raised). The SQL sequence behind the main endpoints was run end to end (`evidence/api_walkthrough_tests.txt`). Two concurrency behaviours were run (`evidence/api_idempotency_concurrency_test.txt`, `evidence/part_b_trip_row_lock_b.txt`). The fare arithmetic of the new price rule was checked against the database with read only queries (`evidence/stage5_prep2_fare_arithmetic.txt`: the real settings give 244145 kobo three ways; a hypothetical price list shows why one rounding is used), and the columns that the authentication and provider assumptions rely on were read (`evidence/stage5_prep2_design_columns.txt`).
Status: PARTIAL.
Missing: the three questions that this requirement used to leave open now have written answers in `docs/06_api_contracts.md`, each marked DESIGN ASSUMPTION, owner may replace: authentication (D13, section 1.10: a signed bearer token with seven trusted claims, a 15 minute lifetime, a person status check on every request, revocation by short life only as the baseline with a stated exposure for a stolen token, a denylist as an optional hardening with its cost, and the list of what is out of scope), the distance estimator and the price rule (D16, EP01: the interface, the 2 second limit, the new error code `estimator_unavailable` with the rule that no quote is created, the placeholder, and one rounding rule), and the payment provider (D5, section 1.11 and EP15, EP19 and EP21: five capabilities and what changes if one is missing). A second engineer no longer has to ask those three questions. The status stays PARTIAL for exactly these reasons. First, D13 is still an open owner decision: the identity service, the lifetime, the status memory and the choice whether to add the optional denylist are assumptions the owner may replace, and the baseline leaves a stolen token usable for up to 15 minutes. Second, D16 is still open: the estimator is a placeholder that must be replaced before real use, and the quoted price is only as good as the estimate. Third, D5 is still open: the provider is unnamed and the webhook scheme is a placeholder. Fourth, no API was built, so nothing was run over HTTP, and "a second engineer could implement it" rests on reading the contract plus the SQL level tests (INFERRED), not on an implementation.

### Requirement 5. The over fetching and real time analyses
Answered in: `docs/07_over_fetching.md` (the trip detail endpoint EP03 measured: 31 fields and 971 bytes in the rider view; what each client uses; a GraphQL design sketch; when REST is still fine; decisions) and `docs/08_real_time.md` (the rider watching the driver: WebSockets against Server Sent Events, a recommendation, the polling cost table measured again after migration 016, the event format with resume by `seq`, the feed from the database, and LISTEN and NOTIFY tested by hand).
Evidence: `evidence/part_b_over_fetch_measurements.txt`, `evidence/part_b_tripsummary_with_driver_name.txt`, `evidence/part_b_payments_by_trip.txt`, `evidence/part_b_realtime_plans.txt`, `evidence/part_b_listen_notify.txt`, `evidence/part_b_listen_notify_cross_session.txt`, `evidence/migration_016_polling_remeasure.txt`.
Status: PARTIAL.
Missing: four class note markers are unfilled, because the course notes were not given: `docs/07_over_fetching.md` lines 166 and 200 (topic: REST for an MVP) and `docs/08_real_time.md` lines 15 and 30 (topic: bidirectional versus unidirectional). The GraphQL part is a design sketch that was never run, and no event stream was served over HTTP; both are labelled as such. Memory per open stream, proxy behaviour and mobile background rules are INFERRED.

### Requirement 6. Implemented schema with constraints and indexes
Answered in: `db/migrations/001_roles_and_functions.sql` to `db/migrations/016_payment_trip_id_index.sql` (16 migrations), described in `docs/04_hard_questions.md` questions 6 and 7 and in `docs/05_traceability.md`.
Evidence: the catalogue check compares the documents with the live database: 16 tables, 116 constraints, 42 indexes, 27 triggers, 18 functions, 4 roles, 0 mismatches (CONFIRMED, `evidence/catalogue_check_016.txt`; script `db/queries/check_docs_vs_db.ps1`). Each migration has its applied output in `evidence/` (listed in `evidence/00_index.md`).
Status: DONE.
Missing: nothing for the brief. Known limits are listed in `docs/09_open_items.md` section 3 (for example the 62 bulk trips with a misplaced `seq`, trust on loopback inside the container, and only three table names attacked in the search path proofs).

### Requirement 7. Query plans on the two heaviest queries
Answered in: `evidence/plans_for_grader.txt` (SQL in `db/queries/plans_for_grader.sql`) and the choice explained in `docs/04_hard_questions.md` question 7 (line 537). Section (a) of the plan file is A2.1, open requests near a driver, the heaviest read. Section (c) is A1.3, the trip insert, the heaviest write. Section (b) is A1.1, the retry check on the idempotency key, the second heaviest read.
Evidence: each plan was run as the application role on the bulk data set (200,012 trips), second run kept, with estimated against actual rows and "Seq Scan remaining: none" in the annotations. The first plan shows two Bitmap Index Scans (`trip_requested_created_at_idx`, `trip_one_active_per_driver`) and an Index Scan on `fare_quote_pkey`.
Status: DONE.
Missing: nothing, with one note. "The two heaviest" can be read as the two heaviest reads or as the heaviest read and the heaviest write. `docs/04` question 7 chooses A2.1 and A1.3 and the file contains all three, so either reading is covered. The original plan file was produced in Stage 3, before migrations 015 and 016. The plans were then run again after migration 016 and kept in `evidence/plans_for_grader_after_016.txt` (CONFIRMED). The index choices did not change: plan (a) still uses `trip_requested_created_at_idx` and `trip_one_active_per_driver` with an Index Scan on `fare_quote_pkey`, and plan (b) still uses `idem_one_key_per_rider_action`. Timings vary by about three times between runs, so the numbers are orders of magnitude.

### Requirement 8. Three rejected invalid inserts
Answered in: `evidence/proofs_rejected_and_extra.txt`, first 66 lines, headed "THE THREE REJECTED INSERTS" (SQL in `db/queries/proofs_rejected_and_extra.sql`).
Evidence: (1) B1, a second active trip for a rider, refused by the unique index `trip_one_active_per_rider`. (2a) B7, a rating on a trip that is not completed, refused by the trigger; (2b) a second rating by the same side, refused by `rating_one_per_role_per_trip`. (3a) B3, a payment in USD, refused by `payment_currency_ngn`; (3b) a negative amount, refused by the payment trigger. Each ran as the application role (the output prints `current_user` as `ridehail_app`). The same file was run again after migration 015 and shows no difference in its error lines (CONFIRMED, `evidence/migration_015_rerun_rejected_and_extra.txt`).
Status: DONE BUT NEEDS OWNER IMAGE.
Missing: the screenshots (evidence item 4 below). Note that 3b is refused by the payment trigger (its message says the amount of minus 5 does not equal the trip fare of 250000) and not by the check on positive amounts, because the trigger runs first. The proof is still a rejected invalid insert.

## 2. The brief's four evidence items

### Evidence item 1. The diagram
Answered in: `docs/02b_relationships.md`, sections "Diagram (Mermaid)" (an `erDiagram` block of the 16 tables) and "Diagram (plain ASCII)".
Status: DONE BUT NEEDS OWNER IMAGE.
Missing: a rendered picture. The Mermaid text has never been rendered, because no renderer is installed in the project and nothing may be installed without asking; its syntax was checked only by reading. The owner must supply `images/diagram_entity_relationships.png` (see `docs/11_word_outline.md`).

### Evidence item 2. The state machine drawing for at least one entity
Answered in: `docs/03_state_machine.md` section 6, "Diagrams": "Mermaid, trip", "Mermaid, payment", "ASCII, trip" and "ASCII, payment". That is two entities, not one. The rules behind the drawings are in sections 2 and 3 (the creation row T0 and nine allowed moves T1 to T9, which are 14 rule rows in the database once the actors are counted, and 19 forbidden moves F1 to F19) and section 4 (the creation row P0, three allowed moves P1 to P3, and 12 forbidden moves PF1 to PF12).
Status: DONE BUT NEEDS OWNER IMAGE.
Missing: rendered pictures, for the same reason as item 1. The owner must supply `images/diagram_state_machine_trip.png` and `images/diagram_state_machine_payment.png`.

### Evidence item 3. Query plan output showing index use
Answered in: `evidence/plans_for_grader.txt`. It shows index use in plan (a) (two Bitmap Index Scans and an Index Scan) and plan (b) (an Index Scan on `idem_one_key_per_rider_action`). Plan (c), the insert, shows no index read, and the file says so ("Indexes shown in the plan: none. An insert does not read an index"). Further plan evidence: migration 016 changed a read from a Parallel Seq Scan to an Index Scan on `payment_trip_id_idx` (`evidence/migration_016_measure_before.txt` and `evidence/migration_016_measure_after.txt`).
Status: DONE.
Missing: nothing. A screenshot of plan (a) would make it easier to read in a Word document and is listed as optional in `docs/11_word_outline.md`.

### Evidence item 4. Screenshots of the three constraint violations being rejected
Answered in: text only, `evidence/proofs_rejected_and_extra.txt` (see requirement 8).
Status: DONE BUT NEEDS OWNER IMAGE.
Missing: the three screenshots. The owner must supply `images/screenshot_violation_1_second_active_trip.png`, `images/screenshot_violation_2_rating_on_unfinished_trip.png` and `images/screenshot_violation_3_payment_in_usd.png`.

## 3. The Excellent band items, mapped to the exact places that earn them

### Subtle denormalisation
Where: `docs/04_hard_questions.md`, question 1, and the matching columns in `docs/02_entities.md`.
What earns it: there are exactly two deliberate denormalisations, each with a reason and a way of staying correct, and a third group that is explicitly not a denormalisation. The text:
1. "Each fact lives in exactly one home table, and everything else finds it by a foreign key. Exceptions are the deliberate denormalisations below, each with its own reason and its own way of staying correct."
2. "The two real denormalisations are therefore the HISTORY snapshot (above) and the SPEED cache (below)."
3. On the speed cache: "I store integer totals, not an average. The average is `rating_sum / rating_count` when read. A stored average would carry rounding error and could not be corrected exactly."
4. On the group that is not a denormalisation: "They are derived copies: the history row is the original, and the trip column can always be recomputed from it."
Strictness note: the snapshots and the totals are enforced by database triggers and checked by constraints (`rider_rating_cache_valid`, `driver_rating_cache_valid`); the drift detection query is written but was not scheduled, because no job runner exists (INFERRED as a limit).

### A state machine that catches a non obvious forbidden transition
Where: `docs/03_state_machine.md`, forbidden trip move F10 (section 3) and forbidden payment moves PF2 and PF10 (section 4), with the allowed move P3 as the other side of the same idea.
What earns it:
1. F10: "driver B takes a trip driver A already holds, without changing status" and "status stays "assigned", so the transition table is never consulted." This is a forbidden change that the transition table cannot see, because the status does not change. It is caught by a separate check in the trigger (`driver_id` cannot change once set), tested in the trigger test (step 6) and raised again on the built database as test E39, which reports SQLSTATE RH006 (`evidence/migration_015_error_tests_compare.txt`); the API avoids it by guarding the accept update with the status.
2. PF2: "The rider retried and a new payment exists. Flipping the old one could double charge (B6)." This is a forbidden move that looks harmless.
3. P3: "Only if a `provider_event` of type `payment_not_found` exists for this payment's `provider_reference`, was received after the payment was created, and is not older than the latest provider event of any type for that reference (a later `payment_succeeded` or `payment_failed` cancels the proof)." The only way support may fail a stuck payment is itself guarded by evidence, and a later event cancels the proof. This was tested on the real database: P3 without proof, with proof, and with a proof cancelled by a later event (`evidence/proofs_rejected_and_extra.txt`, tests X5a, X5b and X5c, lines 147 to 204).

### An honest over fetching analysis
Where: `docs/07_over_fetching.md`.
What earns it:
1. It reports the cases against its own recommendation. The support console row of the table: "0%, but it needs four requests". The support page ignores nothing but needs four calls, so the problem there is too many requests, not too many bytes.
2. It says where the real cost was not bytes: "The expensive thing found is not the payload." A full table scan behind the payments list was found by measuring, and fixed by migration 016.
3. It corrects its own earlier number: "Part B first reported 835 B; that number counted two braces per row and left out one comma, and the exact figure is 815 B."
4. It separates judgement from measurement: "Nobody notices 3 KB" is a judgement, not a measurement.
Strictness note: the GraphQL half is a design sketch that was never run, and it says so in its first lines and in its list of things not verified.

### A contract a second engineer could implement
Where: `docs/06_api_contracts.md` and `docs/06b_error_catalogue.md`.
What earns it:
1. Ownership is explicit and uniform: "a failed ownership check returns 404 not_found with the same body as an id that does not exist (never 403), so a stranger cannot learn that an id exists."
2. The database error mapping is exact and does not depend on message text: "It never parses the message text: the text is for the server log only." Each rule has its own SQLSTATE, and each is listed with its API error code in `docs/06b_error_catalogue.md` section 3.
3. Multi step operations spell out their transactions: "Flow (three transactions, because a provider call must not hold a database lock):" (EP15, payments).
4. Order of checks is stated where it matters: "replay and key checks come first, so a retry with the same key never returns rider_has_active_trip (it replays the 201)." (EP02, trips).
5. The three questions that used to need an owner answer now have written defaults. Authentication (section 1.10): "The API verifies tokens. It never issues them." The nine checks of every request are listed in order, and every authentication failure gives the same 401. Revocation is stated honestly: "a stolen token that is still valid works until it expires, for up to 15 minutes, as the person it names, and the API has no way to refuse it before then." The cheaper baseline and the optional denylist are both priced.
6. The fare (EP01): "There is exactly one rounding rule, and it is applied once, at the end." It is given as an integer formula and was checked against the database, with a case that shows why rounding each part would be one kobo wrong.
7. The distance estimator (EP01): "If the estimator does not answer, no quote is created". The interface, the time limit, the ranges and the error code are written down.
8. The payment provider (section 1.11): "This section lists what the API needs from ANY provider, as five capabilities, and says what in the design would change if a provider lacked one."
Strictness note: this claim stays PARTIAL. A second engineer no longer has to ask the three questions, because each has a written default marked DESIGN ASSUMPTION, owner may replace. It is not complete because D5, D13 and D16 are still open owner decisions and nothing was run over HTTP (requirement 4 above).

## 4. Summary
Requirements: DONE for 1, 2, 3, 6, 7 and 8 (requirement 8 also appears below as needing screenshots); PARTIAL for 4 (D5, D13 and D16 have written design assumptions but are still open owner decisions; nothing run over HTTP) and 5 (four class notes unfilled; GraphQL not run).
Evidence items: DONE for item 3; DONE BUT NEEDS OWNER IMAGE for items 1, 2 and 4.
What closes the gaps: the owner supplies six required images (three diagrams and three screenshots of the rejected inserts) and two optional plan screenshots, fills four class notes, and confirms or replaces the written assumptions for D5, D13 and D16.

## 5. Consistency check run at the end of this stage
The three pass check and the catalogue check were run again with `db/queries/check_docs_vs_db.ps1`. The output is in `evidence/catalogue_check_stage5_prep.txt` and shows the same counts as before this stage (tables 16, constraints 116, indexes 42, triggers 27, functions 18, roles 4, no mismatches; pass 1 165 of 165 fields; pass 3 26 requirement IDs defined, none cited but undefined, none missing from `docs/05`). It was run once more after the three design assumptions were written (Stage 5 prep 2); the output is in `evidence/catalogue_check_stage5_prep2.txt`, with the database counts unchanged. It was run again after the revocation change (Stage 5 prep 3); the output is in `evidence/catalogue_check_stage5_prep3.txt`.
