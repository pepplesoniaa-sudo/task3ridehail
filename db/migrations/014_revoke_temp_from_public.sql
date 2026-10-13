-- 014 revoke the TEMP privilege from PUBLIC on ridehail_design
-- Serves: B4, B5, B8, B9, A4 (closes the attack class found in follow-up 2, proof 1b; migration 013 already makes
-- every function ignore temp tables with the same names, this removes the ability to create them).
-- PostgreSQL gives PUBLIC the TEMPORARY privilege on every new database. ridehail_app, ridehail_erasure_owner and
-- ridehail_writer all got it through PUBLIC. Nothing in this project needs temp tables (checked in follow-up 3:
-- the only CREATE TEMP statements in db\ are the three deliberate attacks in proofs_followup2_b_search_path.sql).
-- Sorts and hashes that spill to disk use temporary FILES, which do not need this privilege (proved after applying).
-- The superuser and the database owner are not affected. CONNECT stays with PUBLIC.
REVOKE TEMPORARY ON DATABASE ridehail_design FROM PUBLIC;
