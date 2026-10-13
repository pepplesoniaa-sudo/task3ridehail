-- Migration 015 catalogue snapshot (read only). Run before and after; diff the two outputs.
-- Part 1: every function in public: owner, SECURITY DEFINER, settings (search_path), ACL, attributes.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS definer,
       coalesce(array_to_string(p.proconfig, ','), '') AS settings, coalesce(p.proacl::text, '(default)') AS acl,
       p.provolatile, p.proleakproof, p.proisstrict, p.proparallel, l.lanname, pg_get_function_result(p.oid) AS returns
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'public' ORDER BY p.proname;
-- Part 2: every trigger: table, function, enabled state, full definition.
SELECT c.relname AS tbl, t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) AS def
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid WHERE NOT t.tgisinternal ORDER BY c.relname, t.tgname;
-- Part 3: function body with every USING ERRCODE = 'RHnnn' removed, as a hash. Equal before and after = text, logic and messages unchanged.
SELECT p.proname, md5(regexp_replace(p.prosrc, ' USING ERRCODE = ''RH[0-9]{3}''', '', 'g')) AS body_without_errcode_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' ORDER BY p.proname;
-- Part 4: number of RAISE statements and of ERRCODE clauses per function.
SELECT p.proname, (length(p.prosrc) - length(replace(lower(p.prosrc), 'raise exception', ''))) / 15 AS raise_exceptions,
       (length(p.prosrc) - length(replace(p.prosrc, 'USING ERRCODE', ''))) / 13 AS errcodes
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.prosrc ILIKE '%raise exception%' ORDER BY p.proname;
-- Part 5: roles and database ACL.
SELECT rolname, rolsuper, rolcanlogin FROM pg_roles WHERE rolname LIKE 'ridehail%' ORDER BY 1;
SELECT datacl FROM pg_database WHERE datname = 'ridehail_design';
