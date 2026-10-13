# Evidence index

What each file in this folder shows. No file contains a credential. All database output comes from `docker exec task3-pg psql -U ridehail -d ridehail_design`, and every proof ran as the role `ridehail_app` (by `SET ROLE`, or by a real login in `followup2_login_role_test.txt`).
The SQL that produced the outputs is in `..\db\queries\`, `..\db\seed\` and `..\db\migrations\`. The documents are in `..\docs\`.

## A. What the brief asks for, and what the owner must still produce

| Item | Status | Where it is | What it shows / what is missing |
|---|---|---|---|
| Diagram source, entity relationships | EXISTS, inside a document (no standalone file) | `..\docs\02b_relationships.md`: section "Diagram (Mermaid)" (an `erDiagram` block) and section "Diagram (plain ASCII)" | the 16 tables and every foreign key, as text |
| State machine drawing | EXISTS, inside a document (no standalone file) | `..\docs\03_state_machine.md` section 6: "Mermaid, trip", "Mermaid, payment", "ASCII, trip", "ASCII, payment" | the trip lifecycle (14 allowed moves) and the payment lifecycle (3 allowed moves), as text |
| Plan output | EXISTS | `plans_for_grader.txt` (SQL: `..\db\queries\plans_for_grader.sql`) | EXPLAIN (ANALYZE, BUFFERS), second run kept, of A2.1 open requests, A1.1 retry check, and the A1.3 trip insert as a labelled extra, with the index used, estimated against actual rows, and any Seq Scan marked |
| Three rejected inserts | EXISTS | `proofs_rejected_and_extra.txt` (SQL: `..\db\queries\proofs_rejected_and_extra.sql`); re-run after migration 015: `migration_015_rerun_rejected_and_extra.txt` (0 differing lines) | B1 a second active trip (`trip_one_active_per_rider`), B7 a rating on a trip that is not completed and a second rating by the same side, B3 a payment in USD and a negative amount, plus extra proofs X1 to X6; every run prints `current_user = ridehail_app` |
| API contracts, error catalogue, endpoint matrix | EXISTS (documents) | `..\docs\06_api_contracts.md`, `06b_error_catalogue.md`, `06c_endpoint_matrix.md` | 27 endpoints and 3 internal jobs, every error code with its SQLSTATE or constraint, endpoints against roles and requirement IDs |
| Over-fetching and real-time analyses; open items | EXISTS (documents) | `..\docs\07_over_fetching.md`, `08_real_time.md`, `09_open_items.md` | measured sizes and plans, REST against GraphQL (a design sketch), SSE against WebSockets, every placeholder, owner decision and known limit |
| **Rendered diagram images (PNG or SVG)** of the entity diagram and of the state machines | **OWNER MUST PRODUCE** | none | no renderer is installed in this project (nothing may be installed without asking), the Mermaid blocks have never been rendered, and their syntax was checked only by reading. The owner renders them (for example in a Mermaid-aware editor) and saves the images |
| **Standalone diagram source files (`.mmd`)** | **OWNER MUST PRODUCE (optional)** | none | the Mermaid text exists only inside the two documents above; copy each block into its own file if a standalone source is required |
| **Screenshots** (psql output, rendered diagrams, the plans) | **OWNER MUST PRODUCE** | none | all evidence in this folder is text; nothing was captured as an image |
| API implementation (the `api\` folder) | NOT BUILT | `..\api\` is empty | no API was built; the contracts are documents only |
| Word document | NOT WRITTEN | none | written only on request |
## B. Every other file in this folder

### Migrations (one file per migration, apply output and what was listed after it)
| File | What it shows |
|---|---|
| `migration_001_applied.txt` | roles `ridehail_app` and `ridehail_erasure_owner` (NOLOGIN) and the two shared functions |
| `migration_002_applied.txt` | support_admin, setting, status_transition_rule: constraints, triggers, indexes, 14 trip rows and 3 payment rows |
| `migration_003_applied.txt` | rider, driver, vehicle |
| `migration_004_applied.txt` | fare_quote, trip, trip_status_history, audit_log and the trip triggers |
| `migration_005_applied.txt` | payment, refund, provider_event and their triggers |
| `migration_006_applied.txt` | rating, idempotency_key, location_ping and the two erasure functions |
| `migration_007_008_applied.txt` | apply output of the indexes (007) and the grants (008) |
| `migration_007_008_show.txt` | the nine chosen indexes, every grant of both roles, and row counts after 007 and 008 |
| `migration_009_applied.txt` | the fix for the missing `SELECT (deleted_at)` grant of the erasure owner |
| `migration_010_before.txt` | counts, privileges and function owners before migration 010 |
| `migration_010_dry_run.txt` | dry run of 010 in a rolled back transaction, with a real trip move after it |
| `migration_010_applied.txt` | apply output of 010: writer role, definer functions, INSERT revoked, `seq` column and index, row counts before and after |
| `migration_010_seq_investigation.txt` | why 62 bulk trips have a history row numbered out of order (heap order, rows stored on earlier pages) |
| `migration_011_applied.txt` | the fix for `add_support_note` (no `RETURNING`) |
| `migration_012_applied.txt` | the drop of `trip_status_history_trip_idx` and the revoke of EXECUTE from PUBLIC, with the four writer proofs repeated |
| `migration_013_applied.txt` | the search path with `pg_temp` last on all 18 functions |
| `migration_014_applied.txt` | `REVOKE TEMPORARY ... FROM PUBLIC`: privileges of every role and the database ACL afterwards |

### Catalogue checks (the docs compared with the database)
| File | What it shows |
|---|---|
| `catalogue_actual.txt` | the latest dump of the database catalogue (constraints, indexes, triggers, functions, tables, sequences, roles, columns), pipe separated |
| `catalogue_check.txt` | first comparison after 008: one mismatch, the plate index typed as a constraint in the doc |
| `catalogue_check_after_009.txt` | after reclassifying that index: 0 mismatches |
| `catalogue_and_passes_after_010.txt` | catalogue check and the three passes after 010 and 011 |
| `followup2_catalogue_and_passes.txt` | the same after 012 and 013 (41 indexes) |
| `followup3_catalogue_and_passes.txt` | the same after 014: 16 tables, 116 constraints, 41 indexes, 27 triggers, 18 functions, 4 roles, 0 mismatches |

### Seeds and the bulk load
| File | What it shows |
|---|---|
| `seed_a_applied.txt` | the small seed applied as `ridehail_app` through the triggers, 2.0 seconds |
| `seed_a_counts.txt` | counts, the 12 trips and their derived columns, history, payments, events, rating caches, audit rows |
| `seed_b_timing_first_chunk.txt` | bulk step 0 (people and quotes, 15.8 s) and the timing chunk of 2,000 trips (31 s), which showed one stream would take about 52 minutes |
| `seed_b_parallel_log_run1_failed_integer_overflow.txt` | the first parallel run: all four sessions failed and rolled back ("integer out of range") |
| `seed_b_parallel_err_run1_0.txt`, `seed_b_parallel_err_run1_1.txt`, `seed_b_parallel_err_run1_2.txt`, `seed_b_parallel_err_run1_3.txt` | the error text of each failed session of that run |
| `seed_b_parallel_log.txt` | the second parallel run: 40 chunks, all returned 0, 28 minutes 52 seconds |
| `seed_b_parallel_err_0.txt`, `seed_b_parallel_err_1.txt`, `seed_b_parallel_err_2.txt`, `seed_b_parallel_err_3.txt` | error output of the successful run: empty files, no errors |
| `seed_b_final_counts.txt` | bulk step 2 (active and requested trips), ANALYZE, final row counts, sizes, sanity checks |
| `vacuum_after_bulk.txt` | the first VACUUM after the bulk load and the trip index sizes |

### The five queries and the plans
| File | What it shows |
|---|---|
| `query_parameters.txt` | the real parameter values taken from the data for the queries |
| `queries_a1_a5_results.txt` | the five query groups A1 to A5 run with a few result rows |
| `plans_all_candidates_warm.txt` | EXPLAIN (ANALYZE, BUFFERS) of 15 candidate statements right after the bulk load |
| `plan_heaviest_1_A2_open_requests.txt` | the A2.1 plan right after the bulk load (20.6 ms) |
| `plan_heaviest_1_A2_after_vacuum.txt` | the A2.1 plan after VACUUM (3.4 ms) |
| `plan_heaviest_2_A1_insert_trip.txt` | the A1.3 trip insert plan with its trigger times |
| `plans_all_candidates_after_vacuum.txt` | the 15 candidates after the first VACUUM |
| `plans_partial_and_unused_indexes.txt` | partial indexes with the condition repeated exactly and changed, and the indexes the five queries did not touch |
| `followup2_vacuum.txt` | VACUUM (ANALYZE) of trip, payment and trip_status_history |
| `followup2_plans_all_candidates.txt` | the 15 candidates after that VACUUM, timeline ordered by seq |
| `followup2_plans_selected_reads.txt` | the plans of A2.1, the reconciliation query and the retry check |
| `followup2_plans_after_013.txt` | the 15 candidates after migration 013, second run |
| `followup2_plans_after_013_run3.txt` | the same, third run, to show the variation between runs |

### Proofs of rules (rejected inserts, extras, history and audit)
| File | What it shows |
|---|---|
| `proofs_rejected_and_extra.txt` | the three rejected inserts and the extra proofs, final run after migration 009 |
| `proofs_run1_erasure_failed_before_migration_009.txt` | the first run, where erase_rider and erase_driver failed with "permission denied for table rider" |
| `proofs_migration_010.txt` | history and audit written by the database, INSERT refused, actors recorded, stable order by seq, support notes (final run) |
| `proofs_migration_010_run1_before_migration_011.txt` | the first run, where `add_support_note` failed because of `RETURNING` |
| `followup2_proofs_a_c.txt` | the refund branch of the audit writer, and the timeline on a trip not among the 62 and on one that is |

### Search path, login role, index drop, TEMP revoke
| File | What it shows |
|---|---|
| `followup2_groundwork.txt` | `pg_hba` rules, logging settings, function settings and the TEMP privilege before the follow-up |
| `followup2_proof_1b_before_fix.txt` | the four search-path attacks E1 to E4 before migration 013 (audit row lost, history row redirected, forbidden move accepted) |
| `followup2_proof_1b_E2_clean_before_fix.txt` | attack E2 again with a seq default, showing the history row going into the temp table |
| `followup2_proof_1b_after_fix.txt` | the four attacks after migration 013: all fail or have no effect |
| `followup2_013_dry_run.txt` | dry run of 013 with attacks E1 and E4 |
| `followup2_login_role_test.txt` | the real login role: wrong password refused, privileges refused, SET ROLE and RESET ROLE tests, role dropped, password not found anywhere |
| `followup2_012_a_index_usage.txt` | usage counters of the two history indexes after running every query file, and the plan shapes |
| `followup2_012_a_which_statements.txt` | which three diagnostic statements used the old index |
| `followup2_012_dry_run.txt` | dry run of 012 with real moves after the revoke |
| `followup3_temp_groundwork.txt` | every use of TEMP in the project (only the three attacks) and the TEMP privilege before 014 |
| `followup3_014_dry_run.txt` | dry run of 014: temp tables refused, normal moves still work, schema attack still no effect |
| `followup3_014_proofs.txt` | the same proofs on the applied database |
| `followup3_attacks_rerun_after_014.txt` | the four attacks E1 to E4 re-run after migration 014 |

### State of the project
| File | What it shows |
|---|---|
| `stage3_followup_final_state.txt` | the state after the stage 3 follow-up: doc diff statistics, a timeline on a bulk trip, counts, roles, migrations present |

### Stage 4 follow-up: migration 015 (one SQLSTATE per rule)
| File | What it shows |
|---|---|
| `migration_015_catalogue_before.txt`, `migration_015_catalogue_after.txt`, `migration_015_catalogue_diff.txt` | owners, SECURITY DEFINER flags, search paths, ACLs, attributes, triggers, body hashes without ERRCODE, before and after; the diff shows only the ERRCODE counts changed |
| `migration_015_dry_run.txt` | the migration inside BEGIN ... ROLLBACK with the catalogue and three rule tests, then 0 ERRCODE clauses left after the rollback |
| `migration_015_applied.txt` | apply output (13 CREATE FUNCTION, single transaction, ON_ERROR_STOP) |
| `migration_015_rerun_api_error_mapping.txt`, `migration_015_error_tests_compare.txt` | every Part A error test re-run, SQLSTATE and message before and after, per test |
| `migration_015_rerun_walkthrough.txt`, `_rejected_and_extra.txt`, `_proofs_migration_010.txt`, `_attacks_search_path.txt`, `_temp_revoke.txt`, `_followup2_a_c.txt`, `_list_endpoints.txt` | the earlier proofs and the three search-path attacks re-run after 015 |
| `migration_015_state_after.txt` | row counts after the re-runs (nothing left behind) |
| `seed_sample_settings_dry_run.txt` | the sample settings seed run inside BEGIN ... ROLLBACK (not applied) |

### Stage 4 Part A close (20 untested codes, settings seed)
| File | What it shows |
|---|---|
| `untested_rh_codes_proofs.txt` | the 20 RH codes that no earlier test raised, each raised as `ridehail_app` where possible; the 42501 stops and the dev-login runs for RH016, RH031, RH040, RH080; the setups for RH013, RH014 and RH042 (SQL: `..\db\queries\proofs_untested_rh_codes.sql`) |
| `seed_sample_settings_before.txt` | before the seed: 0 of 8 EP01 keys found, EP01 would answer 503 service_not_configured |
| `seed_sample_settings_applied.txt` | the seed applied as `ridehail_app` (actor support, existing admin id): INSERT 0 10, COMMIT, the 14 setting rows and the 10 audit rows it wrote |
| `seed_sample_settings_ep01_after.txt` | after the seed: 8 of 8 keys found, a quote for a pickup inside the box (rolled back), the box test false for a pickup outside (SQL: `..\db\queries\proofs_ep01_after_seed.sql`) |
| `seed_sample_settings_dry_run.txt` | the earlier rolled-back dry run of the 8-row version of the seed |

### Stage 4 Part B (over-fetching and real time)
| File | What it shows |
|---|---|
| `part_b_over_fetch_measurements.txt` | the JSON of EP03 (rider, driver and support views), the EP06 list item and the "needed" subsets for trip 0001, with fields and bytes; the real EP03 rider response; the other REST calls of a support page (EP04, EP16, EP18); a 20-row rider list page against the fields its row uses (SQL: `..\db\queries\measure_over_fetch.sql`) |
| `part_b_payments_by_trip.txt` | the payment indexes; reading all payments of a trip is a parallel sequential scan of 169,410 rows (16.7 ms), reading live payments uses the partial index (0.07 ms) (SQL: `..\db\queries\part_b_payments_by_trip.sql`) |
| `part_b_realtime_plans.txt` | plans, run twice: resume read of one trip, latest ping of one trip, 50 trips batched (pings and status events), the EP03 read (SQL: `..\db\queries\part_b_realtime_plans.sql`) |
| `part_b_listen_notify.txt`, `part_b_listen_notify_cross_session.txt`, `part_b_listen_notify_cross_session.sender.txt` | LISTEN and NOTIFY by hand as `ridehail_app`: delivery, rollback, commit timing, folding, order, loss while not listening, payload limit, two sessions (SQL: `..\db\queries\part_b_listen_notify*.sql`) |
| `part_b_trip_row_lock_a.txt`, `part_b_trip_row_lock_b.txt` | two sessions moving the same trip: the second waits and hits lock_timeout (55P03); nothing committed (SQL: `..\db\queries\part_b_trip_row_lock_a.sql`, `_b.sql`) |

### Stage 4 close (migration 016, contract fix, re-measure)
| File | What it shows |
|---|---|
| `migration_016_measure_before.txt`, `migration_016_measure_after.txt` | sizes of `payment` and its indexes; the all-payments-of-a-trip read; the EP03 full read; six payment inserts (rolled back); before: Parallel Seq Scan 14.5 to 17.7 ms, after: Index Scan using `payment_trip_id_idx` 0.06 to 0.10 ms (SQL: `..\db\queries\migration_016_measure.sql`) |
| `migration_016_dry_run.txt` | migration 016 inside BEGIN ... ROLLBACK: index created in 493 ms, 5.13 MB, 41 to 42 indexes, plan changes, 41 again after the rollback (SQL: `..\db\queries\dry_run_016.sql`) |
| `migration_016_applied.txt` | the applied migration (single transaction, ON_ERROR_STOP, exit 0), `ANALYZE payment`, 42 indexes, index size and owner |
| `migration_016_insert_cost_paired.txt` | 300 inserts per round, with and without the index (dropped inside a rolled-back transaction), 3 rounds each (SQL: `..\db\queries\migration_016_insert_cost_paired.sql`) |
| `migration_016_polling_remeasure.txt` | EP03 read 5 + 6 runs and EP05 read 5 runs after the index (SQL: `..\db\queries\migration_016_polling_remeasure.sql`) |
| `part_b_tripsummary_with_driver_name.txt` | the rider TripSummary after the contract fix: 12 fields, 392 B for the seed item, 8,095 B for 20 rows (SQL: `..\db\queries\measure_tripsummary_with_driver_name.sql`) |
| `catalogue_check_016.txt` | the three-pass check after migration 016 and the document updates (script: `..\db\queries\check_docs_vs_db.ps1`) |

### Files with no earlier entry (added in fix 21). Every count below is quoted with the stage that produced it, so a reader can tell which stage each number belongs to.

| File | What it shows | Stage |
|---|---|---|
| `api_error_mapping_tests.txt` | every Part A error test: the database error mapped to a status, with the real message and SQLSTATE, run as `ridehail_app`; test ids E01 to E43 | Stage 4 Part A |
| `api_walkthrough_tests.txt` | the SQL sequence behind the main Part A endpoints, run end to end as `ridehail_app` | Stage 4 Part A |
| `api_list_endpoint_tests.txt` | the list endpoints (keyset pagination, EP06) tested against the database | Stage 4 Part A |
| `api_idempotency_concurrency_test.txt` | a second insert of the same idempotency key waits and times out with 55P03 | Stage 4 Part A |
| `api_idempotency_concurrency_session_a.txt` | the first session of that concurrency test (its insert, then the wait) | Stage 4 Part A |
| `catalogue_check_stage5_prep.txt` | catalogue check and three-pass check at Stage 5 prep 1: 16 tables, 116 constraints, 42 indexes, 27 triggers, 18 functions, 4 roles, 0 mismatches; pass 1 165 of 165 fields; pass 3 26 requirement IDs | Stage 5 prep 1 |
| `catalogue_check_stage5_prep2.txt` | the same at Stage 5 prep 2, after the three design assumptions were written; the database counts are unchanged | Stage 5 prep 2 |
| `catalogue_check_stage5_prep3.txt` | the same at Stage 5 prep 3, after the revocation change | Stage 5 prep 3 |
| `migration_015_rerun_api_walkthrough.txt` | the Part A walkthrough re-run after migration 015 | Stage 4 follow-up |
| `migration_015_rerun_attacks_search_path.txt` | the four search-path attacks E1 to E4 re-run after migration 015 | Stage 4 follow-up |
| `migration_015_rerun_followup2_a_c.txt` | the follow-up 2 proofs A to C re-run after migration 015 | Stage 4 follow-up |
| `migration_015_rerun_list_endpoints.txt` | the list-endpoint tests re-run after migration 015 | Stage 4 follow-up |
| `migration_015_rerun_proofs_migration_010.txt` | the migration 010 proofs re-run after migration 015 | Stage 4 follow-up |
| `migration_015_rerun_temp_revoke.txt` | the TEMP revoke proofs re-run after migration 015 | Stage 4 follow-up |
| `plans_for_grader_after_016.txt` | the three plan statements (A2.1 open requests, A1.1 retry check, A1.3 trip insert) run again after migration 016; the index choices are unchanged | Stage 4 close |
| `stage4_close_state_after.txt` | row counts and roles after the Stage 4 close (nothing left behind) | Stage 4 close |
| `stage5_export2_composite_fk.txt` | the composite foreign key test (R6, R19): a requested trip with no driver is accepted; the mixed case is refused by `trip_driver_matches_status` | Stage 5 export 2 |
| `stage5_export4_f3_race.txt` | the F3 race test: the accept guard returns UPDATE 0, and without the guard the trigger raises RH005 | Stage 5 export 4 |
| `stage5_prep2_design_columns.txt` | the columns that the authentication and provider assumptions rely on, read from the schema | Stage 5 prep 2 |
| `stage5_prep2_fare_arithmetic.txt` | the fare arithmetic of the price rule, checked against the database (244145 kobo three ways) | Stage 5 prep 2 |
