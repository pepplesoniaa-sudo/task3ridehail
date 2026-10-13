# 11 Word Document Outline

Written on 7 October 2026. This is a plan for ONE Word document, in the order of the brief. It is not the document. The document is written only on the owner's request.

Target: 42 pages in total, inside the brief's range of 35 to 45. Page counts below assume A4, 11 point body text, tables at 9 point, and an image at about half a page.

Labels: CONFIRMED means the output was run and kept in `evidence/`. INFERRED means reasoned. Paths are relative to the project folder `C:\dev\task3ridehail` (the project is API DESIGN AND DATA MODELLING). Page counts are plans, not measurements.

## Rules for the whole document
1. One voice, plain English, the same as the source files. No new claims: every sentence comes from a source file named below, and every number is copied from it.
2. Keep the labels CONFIRMED and INFERRED where the source has them. Keep the requirement IDs (A1 to A5, B0 to B10, U1 to U4, Q1 to Q6) so a reader can follow a rule from requirement to table to test.
3. Number the chapters as below. Number tables and images inside each chapter, for example Table 3.1 and Image 4.2, and give each a one line caption.
4. Put a short "Source" line under each chapter heading naming the files it was built from.
5. Anything that is a long list of names (every constraint, every endpoint, every evidence file) goes to the appendix as a file list, not as pages of text.

## Page budget
1. Front matter: 1 page.
2. Chapter 1, Requirements: 2 pages.
3. Chapter 2, Entities and relationships with the diagram: 5 pages.
4. Chapter 3, The seven hard questions (questions 1 to 5 in full, questions 6 and 7 as a pointer): 8 pages.
5. Chapter 4, The state machine with its drawing: 4 pages.
6. Chapter 5, Constraints and indexes (hard questions 6 and 7): 4 pages.
7. Chapter 6, API contracts: 5 pages.
8. Chapter 7, Over fetching: 3 pages.
9. Chapter 8, Real time: 3 pages.
10. Chapter 9, The proof: plans and the three rejected inserts: 4 pages.
11. Chapter 10, Open items and decisions: 2 pages.
12. Appendix, file lists: 1 page.
Total: 1 + 2 + 5 + 8 + 4 + 4 + 5 + 3 + 3 + 4 + 2 + 1 = 42 pages.

## Front matter (1 page)
Source files: `docs/05_traceability.md` (the first paragraph), `docs/10_brief_checklist.md` (section 4, the summary), `docs/09_open_items.md` (section 6, owner decisions recorded).
Contents: title, the owner's name and date (supplied by the owner), a contents list, one paragraph saying what was built (a ride hailing database of 16 tables with 116 constraints, 42 indexes, 27 triggers and 18 functions, CONFIRMED in `evidence/catalogue_check_016.txt`, and the API contracts, with no API built), and a short "how to read" paragraph explaining the labels and the requirement IDs.
Tables: none. Images: none. Class notes: none.

## Chapter 1. Requirements (2 pages)
Source files: `docs/01_requirements.md`.
Tables: the source holds lists, not tables. Reproduce in full the four users U1 to U4, the five key actions A1 to A5, the rules B0 to B10 and the questions Q1 to Q6 (answered and open). Summarise the non goals in three lines.
Excerpts: none.
Images: none.
Appendix: nothing.
Notes: explain once that Q5 (location retention) and Q6 (a driver who never arrives) are open on purpose and point to chapter 10.
Class notes: none.

## Chapter 2. Entities and relationships, with the diagram (5 pages)
Source files: `docs/02_entities.md`, `docs/02b_relationships.md`.
Tables in full: the relationship table R1 to R20 from `docs/02b_relationships.md` (20 rows, with cardinality); the field tables of the two richest entities, `trip` and `payment`, from `docs/02_entities.md` (sections 4 and 8).
Tables summarised: one table with one row per entity, 16 rows, columns: entity, identifier, number of fields, what it is for. Build it from the first line of each section of `docs/02_entities.md`. Summarise the conventions section (every table has an identifier `id`, `created_at` and `updated_at`) in one paragraph, and the section "Three links that are NOT foreign keys, and why" in one paragraph.
Excerpts: none. The one SQL style fact (the identifier is a random uuid) goes in a sentence, not an excerpt.
Images: Image 2.1, the entity diagram, file `images/diagram_entity_relationships.png`, full text width, placed right after the relationship table. It is produced by the owner from the Mermaid block in the section "Diagram (Mermaid)" of `docs/02b_relationships.md`. The plain ASCII diagram is not used in the Word document.
Appendix: the field tables of the other 14 entities stay in `docs/02_entities.md`, sections 1 to 3, 5 to 7 and 9 to 16, listed by name.
Class notes: none.

## Chapter 3. The seven hard questions (8 pages)
Source files: `docs/04_hard_questions.md`, questions 1 to 5 in full; questions 6 and 7 get one paragraph each here and their full treatment in chapter 5.
Page plan: question 1 two pages, question 2 one page, question 3 one and a half pages, question 4 two pages, question 5 one page, a half page summary that states in one sentence the answer to each of the seven questions.
Tables in full: question 1, the table of where each fact lives (8 rows); question 2, the money table (7 rows); question 4, the delete style table (5 rows). Summarised: question 3, the table of rules and enforcers has 17 rows; show the 6 that matter most (one active trip per rider, one active trip per driver, support fails a stuck payment only with proof, a completed trip is frozen, payment moves need a rule row, refunds never exceed the payment) and point to chapter 4 and chapter 5 for the rest. Add one sentence saying that the rating rule (a rating needs a completed trip) is not in this table and is found in the table of invalid states in chapter 5.
Excerpts to quote (at most 15 lines each): question 1, the two deliberate denormalisations, the paragraphs headed "Denormalisation 1" and "Denormalisation 2" (about 10 lines in all); question 2, the finding that the database rounds 10.5 kobo to 11 and what that means for the API (about 6 lines); question 5, the reason identifiers are random uuids (about 6 lines). No SQL here except the one drift detecting query of the speed cache, only if space allows (it is about 12 lines).
Images: none.
Appendix: the worked tests quoted in the questions (the "Tested" ids) are not repeated; the evidence file list covers them.
Class notes: none are marked. If the course notes cover normalisation or identifiers, the owner may add a reference at the start of questions 1 and 5; no marker exists today.

## Chapter 4. The state machine, with its drawing (4 pages)
Source files: `docs/03_state_machine.md` sections 1 to 4, 4a and 4b, 6, and 5 (as a short summary).
Tables in full: the allowed trip transitions (section 2, T0 to T9, 10 rows) and the allowed payment transitions (section 4, P0 to P3, 4 rows). Tables summarised: the forbidden trip moves F1 to F19 and the forbidden payment moves PF1 to PF12; show in full the non obvious ones, F3, F9, F10, PF2 and PF10, and give the other rows as one line each in a smaller type size.
Excerpts to quote: the P3 rule in one paragraph (about 5 lines), the section 4b opening about the stuck payment (about 8 lines). No SQL.
Images: Image 4.1, the trip state machine, file `images/diagram_state_machine_trip.png`; Image 4.2, the payment state machine, file `images/diagram_state_machine_payment.png`. Each is half a page, placed before its table. The owner produces both from the Mermaid blocks "Mermaid, trip" and "Mermaid, payment" in section 6 of `docs/03_state_machine.md`.
Appendix: section 7 (the test of the trigger idea) and section 8 (scheduled jobs) are summarised in two paragraphs; the full text stays in the file, listed by name.
Class notes: none.

## Chapter 5. Constraints and indexes (4 pages)
Source files: `docs/04_hard_questions.md` questions 6 and 7; `evidence/catalogue_check_016.txt`.
Tables in full: the table of invalid states that are now impossible (question 6; 32 rows, set in a small type size across one page and a half) and a count table: 16 tables, 116 constraints, 42 indexes, 27 triggers, 18 functions, 4 roles, all from the catalogue check. Tables summarised: the 16 per entity constraint tables of question 6 (147 rows in the source) are not reproduced; show the table for `payment` only, as the model, and list the other 15 in the appendix by name.
Indexes: one table of the 10 chosen indexes (name, table, columns, the query it serves, taken from question 7) and one sentence saying the other 32 exist because a constraint made them.
Excerpts to quote (at most 15 lines each): the statements that create `trip_one_active_per_rider` and `trip_one_active_per_driver` (`db/migrations/004_quotes_trips.sql`, lines 108 to 111, 4 lines); the statement that creates `payment_one_live_per_purpose` (`db/migrations/005_money.sql`, lines 30 to 31); the statement that creates `payment_trip_id_idx` (`db/migrations/016_payment_trip_id_index.sql`, 1 statement) with the two plans before and after from `evidence/migration_016_measure_before.txt` and `_after.txt` (the node lines only, about 6 lines each).
Images: none here. The two heaviest query plans are in chapter 9.
Appendix: the list of migrations 001 to 016 by file name (Appendix B).
Class notes: none.

## Chapter 6. API contracts (5 pages)
Source files: `docs/06_api_contracts.md`, `docs/06b_error_catalogue.md`, `docs/06c_endpoint_matrix.md`.
Page plan: conventions one page (format, who calls, ownership, session settings, error body, how a database error becomes a status, idempotency in three mechanisms); one worked endpoint a page and a half (use EP02, request a trip, because it shows the key, the transaction and the errors); the list contract half a page (keyset pagination, EP06); the endpoint matrix one page; the error catalogue one page.
Tables in full: the endpoint index of `docs/06_api_contracts.md` section 2 (30 rows, small type); the EP02 error table (8 rows); the endpoint against role matrix of `docs/06c_endpoint_matrix.md` part 1. Tables summarised: the error catalogue of 45 codes, show the 12 most important in a table (for example `rider_has_active_trip`, `quote_expired`, `illegal_transition`, `trip_finished`, `payment_already_exists`, `refund_exceeds_payment`, `already_rated`, `idempotency_key_reuse`, `request_in_progress`, `invalid_cursor`, `rate_limited`, `internal_error`) and give the other 33 as a file reference; the table of 45 SQLSTATE codes goes to the appendix by reference.
Excerpts to quote (at most 15 lines each): the error body (3 lines, section 1.5); the EP06 list response with the cursor, first item only (about 10 lines, with the signature shown as four stars); the three transaction flow of EP15 (about 8 lines).
Images: none.
Appendix: the full text of each of the 27 endpoints stays in `docs/06_api_contracts.md` section 4, listed by id and name; the three internal jobs likewise.
Class notes: none.

## Chapter 7. Over fetching (3 pages)
Source files: `docs/07_over_fetching.md`.
Page plan: the endpoint and why (a quarter page); the real response and its size (three quarters of a page, with the sizes table); what each client uses (half a page); the GraphQL design sketch (three quarters of a page); when REST is still fine and what GraphQL costs (three quarters of a page); decisions (a quarter page).
Tables in full: the sizes table (section 2, 5 rows after the contract fix) and the clients table (section 3, 3 rows). Tables summarised: none other.
Excerpts to quote (at most 15 lines each): the first 12 lines of the EP03 rider response (section 2); the rider list query in GraphQL (7 lines) and its first response item (6 lines); the Trip type of the schema sketch (15 lines at most). All excerpts keep the label "design sketch" where they are GraphQL.
Images: none.
Appendix: the measuring queries are listed by file name (`db/queries/measure_over_fetch.sql`, `db/queries/measure_tripsummary_with_driver_name.sql`, `db/queries/part_b_payments_by_trip.sql`).
Class notes needed here, two places, both marked in the source: `docs/07_over_fetching.md` line 166 (start of section 5) and line 200 (end of section 5). Topic for both: REST for an MVP. In the Word document they go at the start and the end of the section "When REST is still fine".

## Chapter 8. Real time (3 pages)
Source files: `docs/08_real_time.md`.
Page plan: the place and the choice (half a page); the comparison of Server Sent Events and WebSockets (one page, as a table of 7 rows); the recommendation and the polling cost table (half a page); the feed and the LISTEN and NOTIFY tests (half a page); the event format, resume and ending (half a page).
Tables in full: the comparison table of section 2 (7 rows) and the polling cost table of section 3 (4 rows, as measured again after migration 016, with the visible assumptions as a short list under it). Tables summarised: the LISTEN and NOTIFY test table of section 4 (8 rows) shown as the 4 rows that matter: rollback is not delivered, delivery only after commit, lost while nobody listens, payload limit under 8000 bytes.
Excerpts to quote (at most 15 lines each): the first connection and the resume example of section 5 (two excerpts of about 12 lines each, with the bearer token shown as four stars).
Images: none.
Appendix: the test outputs are listed by file name (`evidence/part_b_listen_notify.txt`, `evidence/part_b_listen_notify_cross_session.txt`, `evidence/part_b_realtime_plans.txt`, `evidence/part_b_trip_row_lock_b.txt`, `evidence/migration_016_polling_remeasure.txt`).
Class notes needed here, two places, both marked in the source: `docs/08_real_time.md` line 15 (before the comparison table) and line 30 (the recommendation). Topic for both: bidirectional versus unidirectional.

## Chapter 9. The proof: plans and the three rejected inserts (4 pages)
Source files: `evidence/plans_for_grader_after_016.txt`, `evidence/proofs_rejected_and_extra.txt`, `docs/04_hard_questions.md` question 7 (the plan commentary), `evidence/migration_016_measure_before.txt` and `_after.txt`.
Page plan: the two heaviest queries, A2.1 and A1.3, with their plans and what each shows (two pages); the three rejected inserts with the real error messages (one page and a half); a half page stating the limits (timings vary about three times between runs; the plans are orders of magnitude).
Tables in full: a table of the three rejected inserts (rule, statement in words, error message, constraint or trigger that refused it) with 5 rows (1, 2a, 2b, 3a, 3b). Tables summarised: the estimated against actual rows lists of the plan annotations, one line per plan node.
Excerpts to quote (at most 15 lines each): the A2.1 plan, the node lines that name the indexes (about 12 lines, from plan (a) of `evidence/plans_for_grader.txt`); the A1.3 plan summary with the trigger times (about 8 lines, from plan (c)); for each rejected insert, the line that prints the current user as `ridehail_app` and the error line (about 4 lines each).
Images: Image 9.1, the screenshot of rejected insert 1 (a second active trip for a rider), file `images/screenshot_violation_1_second_active_trip.png`. Image 9.2, rejected insert 2 (a rating on a trip that is not completed), file `images/screenshot_violation_2_rating_on_unfinished_trip.png`. Image 9.3, rejected insert 3 (a payment in USD), file `images/screenshot_violation_3_payment_in_usd.png`. Optional: Image 9.4, the A2.1 plan, file `images/screenshot_plan_a2_open_requests.png`; Image 9.5, the A1.3 plan, file `images/screenshot_plan_a1_trip_insert.png`. Each screenshot must show the output of the SQL file `db/queries/proofs_rejected_and_extra.sql` for the numbered part (parts 1, 2a and 3a), with the line that prints `ridehail_app` as the current user and the error line both visible.
Appendix: all other proofs (error mapping, the 45 SQLSTATE tests, the search path attacks, the login role test, the idempotency concurrency test) are listed by evidence file name (Appendix C).
Class notes: none.

## Chapter 10. Open items and decisions (2 pages)
Source files: `docs/09_open_items.md`, `docs/10_brief_checklist.md`.
Tables in full: the decisions recorded (section 6 of `docs/09_open_items.md`, 12 approved and 5 open, as two short lists); the placeholder table (section 1, 19 rows, small type). Tables summarised: the known limits of section 3, shown as the 8 that matter most (62 bulk trips with a misplaced `seq`, trust on loopback inside the container, only three table names attacked, almost no concurrency tests, no driver installed, nothing run over HTTP, the actor is claimed by the application, Q5 and Q6 open).
Excerpts: none.
Images: none.
Appendix: the class notes table of section 4 of `docs/09_open_items.md` is repeated in this outline below; the document itself shows only the four unfilled places in chapters 7 and 8.
Class notes: none in this chapter.

## Appendix (1 page): file lists
Appendix A, documents: `docs/01_requirements.md`, `02_entities.md`, `02b_relationships.md`, `03_state_machine.md`, `04_hard_questions.md`, `05_traceability.md`, `06_api_contracts.md`, `06b_error_catalogue.md`, `06c_endpoint_matrix.md`, `07_over_fetching.md`, `08_real_time.md`, `09_open_items.md`, `10_brief_checklist.md`, `11_word_outline.md`.
Appendix B, migrations: `db/migrations/001_roles_and_functions.sql` to `db/migrations/016_payment_trip_id_index.sql`, 16 files, by name.
Appendix C, evidence: the groups of `evidence/00_index.md` section B and the later sections, by group and file name only (do not paste the index; refer to it).
Appendix D, queries and seeds: `db/queries/` (the proof, plan and measure files) and `db/seed/` (the seeds, including `seed_sample_settings.sql`), by name.

## Every place that still needs a class note (four, in two files)
1. `docs/07_over_fetching.md` line 166, topic REST for an MVP. Word document: chapter 7, start of the section "When REST is still fine".
2. `docs/07_over_fetching.md` line 200, topic REST for an MVP. Word document: chapter 7, end of the same section.
3. `docs/08_real_time.md` line 15, topic bidirectional versus unidirectional. Word document: chapter 8, before the comparison table.
4. `docs/08_real_time.md` line 30, topic bidirectional versus unidirectional. Word document: chapter 8, the recommendation.
No other marker exists. The owner may add references in chapters 3 and 4 (normalisation, state machines) if the course notes cover them, but no marker is placed there because the brief named only the two topics above.

## Every image the owner must supply, with its exact file name
Put all images in a folder named `images` inside the project folder `C:\dev\task3ridehail`. Names use underscores and lower case letters only.
1. `images/diagram_entity_relationships.png`. Chapter 2, Image 2.1. Render the Mermaid block under "Diagram (Mermaid)" in `docs/02b_relationships.md`.
2. `images/diagram_state_machine_trip.png`. Chapter 4, Image 4.1. Render the block "Mermaid, trip" in `docs/03_state_machine.md` section 6.
3. `images/diagram_state_machine_payment.png`. Chapter 4, Image 4.2. Render the block "Mermaid, payment" in the same section.
4. `images/screenshot_violation_1_second_active_trip.png`. Chapter 9, Image 9.1. Screenshot of the output for part 1 (B1) of `db/queries/proofs_rejected_and_extra.sql`.
5. `images/screenshot_violation_2_rating_on_unfinished_trip.png`. Chapter 9, Image 9.2. Part 2a (B7).
6. `images/screenshot_violation_3_payment_in_usd.png`. Chapter 9, Image 9.3. Part 3a (B3).
7. Optional: `images/screenshot_plan_a2_open_requests.png`. Chapter 9, Image 9.4. Plan (a) of `evidence/plans_for_grader.txt`.
8. Optional: `images/screenshot_plan_a1_trip_insert.png`. Chapter 9, Image 9.5. Plan (c) of the same file.
Six images are required (items 1 to 6). Items 7 and 8 are optional. None of these files exists today (CONFIRMED: the folder `images` does not exist in the project).
Rendering the Mermaid blocks needs a Mermaid aware tool, which is not installed in this project; installing one needs the owner's permission, so the owner renders them. Nothing in this outline asks anyone to install anything.
