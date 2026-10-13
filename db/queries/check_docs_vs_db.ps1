# Three-pass check of the documents against the live database (read only). Run from C:\dev\task3ridehail:
#   powershell -File db\queries\check_docs_vs_db.ps1
# Catalogue check: tables, constraints, indexes, triggers, functions, columns, roles (documents against database).
# Pass 1 fields (docs\02 against columns), pass 2 constraints and indexes (docs\04 question 6 and 7), pass 3 requirement IDs (docs\01 against the other docs).
# No secrets are used: the database is reached through docker exec as the dev login inside the container.
$ErrorActionPreference = 'Stop'
$root = 'C:\dev\task3ridehail'
function Q($sql) { $sql | docker exec -i task3-pg psql -U ridehail -d ridehail_design -At -F '|' | Where-Object { $_ -ne '' } }
$d = Join-Path $root 'docs'
$doc4 = (Get-Content "$d\04_hard_questions.md" -Raw -Encoding utf8)
$doc2 = (Get-Content "$d\02_entities.md" -Raw -Encoding utf8)
$doc2 = $doc2.Substring(0, $doc2.IndexOf('## Database roles'))   # the roles table below the entities is not a table of fields

# ---------- database side
$dbTbl = @(Q "select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by 1")
$dbCon = @(Q "select conname from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname='public' and contype in ('p','u','f','c') order by 1")
$dbIdx = @(Q "select indexname from pg_indexes where schemaname='public' order by 1")
$dbTrg = @(Q "select c.relname||'|'||t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal order by 1")
$dbFn  = @(Q "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by 1")
$dbCol = @(Q "select table_name||'|'||column_name from information_schema.columns where table_schema='public' order by 1")
$dbRole = @(Q "select rolname from pg_roles where rolname like 'ridehail%' order by 1")

# ---------- documents side: question 6 rows (kind | name) per table heading
$s = $doc4.IndexOf('## Question 6'); $e = $doc4.IndexOf('### Invalid states'); $q6 = $doc4.Substring($s, $e - $s)
$docCon = @(); $docIdxBacked = @(); $docTrg = @(); $tbl = ''
foreach ($l in ($q6 -split "`n")) {
  if ($l -match '^### ([a-z_]+)\s*$') { $tbl = $matches[1]; continue }
  if ($l -match '^\| (PK|UNIQUE|UNIQUE \(partial\)|FK|FK \(composite\)|CHECK|Trigger) \| ([a-z_0-9]+) \|') {
    $k = $matches[1]; $n = $matches[2]
    if ($k -in 'PK','UNIQUE','FK','FK (composite)','CHECK') { $docCon += $n }
    if ($k -in 'PK','UNIQUE','UNIQUE (partial)') { $docIdxBacked += $n }
    if ($k -eq 'Trigger') { $docTrg += "$tbl|$n" }
  }
}
# vehicle_plate_number_active_key is a partial unique INDEX, listed as UNIQUE (partial): not a constraint
$s7 = $doc4.IndexOf('## Question 7'); $q7 = $doc4.Substring($s7)
$docChosen = @([regex]::Matches($q7, '`([a-z_0-9]+_idx)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique | Where-Object { $dbIdx -contains $_ })
$docIdx = @(($docIdxBacked + $docChosen) | Sort-Object -Unique)

function Cmp($label, $expected, $actual) {
  $exp = @($expected | Sort-Object -Unique); $act = @($actual | Sort-Object -Unique)
  $miss = @($exp | Where-Object { $act -notcontains $_ }); $extra = @($act | Where-Object { $exp -notcontains $_ })
  '{0,-5}: documents {1,4} | database {2,4} | in documents not in database: {3} | in database not in documents: {4}' -f $label, $exp.Count, $act.Count, $(if ($miss) { $miss -join ',' } else { 'none' }), $(if ($extra) { $extra -join ',' } else { 'none' })
  return ($miss.Count + $extra.Count)
}
'######## CATALOGUE CHECK'
$mm = 0
# tables: headings "## n. name" of docs\02
$docTbl = @([regex]::Matches($doc2, '(?m)^## \d+\. ([a-z_]+)') | ForEach-Object { $_.Groups[1].Value })
foreach ($pair in @(@('TBL', $docTbl, $dbTbl), @('CON', $docCon, $dbCon), @('IDX', $docIdx, $dbIdx), @('TRG', $docTrg, $dbTrg))) {
  $r = Cmp $pair[0] $pair[1] $pair[2]; $r | Select-Object -SkipLast 1; $mm += $r[-1]
}
# functions: each database function name must appear in docs\04 or docs\02
$fnMiss = @($dbFn | Where-Object { ($doc4 + $doc2) -notmatch ('\b' + $_ + '\b') })
'FN   : database {0} | named in documents: {1} | not named: {2}' -f $dbFn.Count, ($dbFn.Count - $fnMiss.Count), $(if ($fnMiss) { $fnMiss -join ',' } else { 'none' }); $mm += $fnMiss.Count
'ROLE : database {0} ({1})' -f $dbRole.Count, ($dbRole -join ',')
'TOTAL MISMATCHES: {0}' -f $mm
''
'######## PASS 1 fields (docs\02 against database columns)'
$colMiss = @(); $secs = [regex]::Split($doc2, '(?m)^## \d+\. ')
$doc2Cols = @()
foreach ($sec in $secs[1..($secs.Count - 1)]) {
  $name = ($sec -split "`n")[0] -replace ' \(added\)', '' -replace '\s+$', ''
  foreach ($l in ($sec -split "`n")) { if ($l -match '^\| ([a-z_0-9]+) \| ') { if ($matches[1] -notin 'Field') { $doc2Cols += "$name|$($matches[1])" } } }
}
$p1a = @($dbCol | Where-Object { $doc2Cols -notcontains $_ }); $p1b = @($doc2Cols | Sort-Object -Unique | Where-Object { $dbCol -notcontains $_ })
'tables {0} | columns in database {1} | field rows in docs\02 {2} | columns in db not in 02: {3} | in 02 not in db: {4}' -f $dbTbl.Count, $dbCol.Count, $doc2Cols.Count, $(if ($p1a) { $p1a -join ',' } else { 'none' }), $(if ($p1b) { $p1b -join ',' } else { 'none' })
''
'######## PASS 2 constraints and indexes (docs\04 question 6 and 7)'
$fkRows = @([regex]::Matches($q6, '(?m)^\| FK[^|]*\| ([a-z_0-9]+) \| [^|]+\| ([^|]+)\|') | ForEach-Object { $_.Groups[2].Value.Trim() })
$fkNoJust = @($fkRows | Where-Object { $_ -eq '' -or $_ -eq 'none' }).Count
$checkRows = @([regex]::Matches($q6, '(?m)^\| CHECK \| ([a-z_0-9]+) \| [^|]+\| ([^|]+)\|') | ForEach-Object { $_.Groups[2].Value.Trim() })
$checkNotNone = @($checkRows | Where-Object { $_ -notmatch '^(none|no index needed|n/a)' }).Count
$pkUq = @($docIdxBacked)
'FK rows {0} without a justification text: {1} | CHECK rows {2} not "none needed": {3} | PK/UNIQUE rows {4}' -f $fkRows.Count, $fkNoJust, $checkRows.Count, $checkNotNone, $pkUq.Count
'index count from documents: constraint-backed {0} + chosen {1} = {2} | database indexes {3}' -f $docIdxBacked.Count, ($docIdx.Count - $docIdxBacked.Count), $docIdx.Count, $dbIdx.Count
''
'######## PASS 3 requirement IDs (docs\01 against the other documents)'
$req = Get-Content "$d\01_requirements.md" -Raw -Encoding utf8
$defined = @([regex]::Matches($req, '(?m)^- (A\d|B\d+|U\d|Q\d) ') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$files = Get-ChildItem $d -Filter '0*.md' | Where-Object { $_.Name -notmatch 'before_fix' -and $_.Name -notmatch '^01_' }
$cited = @(); foreach ($f in $files) { $cited += [regex]::Matches((Get-Content $f.FullName -Raw -Encoding utf8), '\b([ABQU]\d{1,2})\b(?!\.\d)') | ForEach-Object { $_.Groups[1].Value } }
$cited = @($cited | Sort-Object -Unique)
$trace = Get-Content "$d\05_traceability.md" -Raw -Encoding utf8
'defined {0} | cited but undefined: {1} | defined but not in docs\05: {2}' -f $defined.Count, $(($cited | Where-Object { $defined -notcontains $_ }) -join ',' | ForEach-Object { if ($_) { $_ } else { 'none' } }), $(($defined | Where-Object { $trace -notmatch ('\b' + $_ + '\b') }) -join ',' | ForEach-Object { if ($_) { $_ } else { 'none' } })
