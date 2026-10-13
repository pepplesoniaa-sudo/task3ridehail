$ErrorActionPreference = 'Stop'

Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Single path variable: set this to the project root. Everything else is derived.
$script:root  = 'C:\dev\task3ridehail'
# The markup files sit beside this script.
$script:tmp   = $PSScriptRoot
$script:build = Join-Path $script:root 'build'
$script:docx  = Join-Path $script:build 'API_Design_and_Data_Modelling_Ride_Hailing.docx'
$script:pdf   = Join-Path $script:build 'API_Design_and_Data_Modelling_Ride_Hailing.pdf'

function Clean([string]$t){
  if([string]::IsNullOrEmpty($t)){ return '' }
  $x = $t
  $x = $x -replace '\*\*',''
  $x = $x -replace '`',''
  $x = $x -replace '\s+[\u2013\u2014]\s+',', '
  $x = $x -replace '[\u2013\u2014]',' '
  $x = $x -replace '\s+--+\s+',', '
  $x = $x -replace '(?<=[A-Za-z])-(?=[A-Za-z])',' '
  $x = $x -replace '\s+',' '
  return $x.Trim()
}

$script:word = New-Object -ComObject Word.Application
$script:word.Visible = $false
$script:word.DisplayAlerts = 0
$script:doc = $script:word.Documents.Add()
$script:sel = $script:word.Selection

$ps = $script:doc.PageSetup
$ps.PageWidth  = $script:word.CentimetersToPoints(21.0)
$ps.PageHeight = $script:word.CentimetersToPoints(29.7)
$ps.TopMargin    = $script:word.CentimetersToPoints(1.8)
$ps.BottomMargin = $script:word.CentimetersToPoints(1.8)
$ps.LeftMargin   = $script:word.CentimetersToPoints(1.8)
$ps.RightMargin  = $script:word.CentimetersToPoints(1.8)

$normal = $script:doc.Styles.Item(-1)
$normal.Font.Name = 'Calibri'
$normal.Font.Size = 11
$normal.ParagraphFormat.SpaceBefore = 0
$normal.ParagraphFormat.SpaceAfter = 0
$normal.ParagraphFormat.LineSpacingRule = 0
foreach($hid in -2,-3,-4){
  $st = $script:doc.Styles.Item($hid)
  $st.Font.Name = 'Calibri'
  if($hid -eq -2){ $st.Font.Size = 14 }
  elseif($hid -eq -3){ $st.Font.Size = 12 }
  else { $st.Font.Size = 10.5 }
  $st.ParagraphFormat.SpaceBefore = 4
  $st.ParagraphFormat.SpaceAfter = 0
  $st.ParagraphFormat.LineSpacingRule = 0
  $st.ParagraphFormat.KeepWithNext = $true
}

function ResetFont(){
  $script:sel.Font.Name = 'Calibri'
  $script:sel.Font.Size = 10.5
  $script:sel.Font.Bold = $false
  $script:sel.Font.Italic = $false
  $script:sel.ParagraphFormat.Alignment = 0
}
function AddH1([string]$t){
  [void]$script:sel.InsertBreak(7)
  $script:sel.Style = $script:doc.Styles.Item(-2)
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddH2([string]$t){
  $script:sel.Style = $script:doc.Styles.Item(-3)
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddH3([string]$t){
  $script:sel.Style = $script:doc.Styles.Item(-4)
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddSource([string]$t){
  ResetFont
  $script:sel.Font.Italic = $true
  $script:sel.Font.Size = 9
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddParagraph([string]$t){
  ResetFont
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddBullet([string]$t){
  ResetFont
  $script:sel.ParagraphFormat.SpaceAfter = 0
  $script:sel.ParagraphFormat.SpaceBefore = 0
  [void]$script:sel.TypeText(([char]0x2022) + '  ' + (Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddCaption([string]$t){
  ResetFont
  $script:sel.Font.Italic = $true
  $script:sel.Font.Size = 9
  $script:sel.ParagraphFormat.Alignment = 1
  [void]$script:sel.TypeText((Clean $t))
  [void]$script:sel.TypeParagraph()
  ResetFont
}
function AddCode([string[]]$lines){
  ResetFont
  $script:sel.Font.Name = 'Consolas'
  $script:sel.Font.Size = 8
  $script:sel.ParagraphFormat.SpaceAfter = 0
  $script:sel.ParagraphFormat.SpaceBefore = 0
  foreach($ln in $lines){
    [void]$script:sel.TypeText($ln)
    [void]$script:sel.TypeParagraph()
  }
  ResetFont
}
function AddImage([string]$rel,[string]$caption,[double]$widthCm = 12.5){
  $p = Join-Path $script:root $rel
  if(-not (Test-Path -LiteralPath $p)){ Write-Warning "missing image $rel"; AddParagraph "(Image not found: $rel)"; return }
  [void]$script:sel.EndKey(6)
  $shape = $script:sel.InlineShapes.AddPicture($p, $false, $true)
  $shape.LockAspectRatio = -1
  $shape.Width = $script:word.CentimetersToPoints($widthCm)
  [void]$script:sel.EndKey(6)
  [void]$script:sel.TypeParagraph()
  if(-not [string]::IsNullOrEmpty($caption)){ AddCaption $caption }
  ResetFont
}
function AddTable([string[]]$rows,[int]$size){
  [void]$script:sel.EndKey(6)
  $data = @()
  foreach($r in $rows){ $data += ,(@($r.Split('|') | ForEach-Object { $_.Trim() })) }
  if($data.Count -eq 0){ return }
  $nRows = $data.Count
  $nCols = 1
  foreach($d in $data){ if($d.Count -gt $nCols){ $nCols = $d.Count } }
  $t = $script:doc.Tables.Add($script:sel.Range, $nRows, $nCols)
  $t.Borders.Enable = $true
  for($i=0; $i -lt $nRows; $i++){
    for($j=0; $j -lt $nCols; $j++){
      $v = ''
      if($j -lt $data[$i].Count){ $v = $data[$i][$j] }
      $t.Cell($i+1,$j+1).Range.Text = (Clean $v)
    }
  }
  $t.Range.Font.Name = 'Calibri'
  $t.Range.Font.Size = $size
  $t.Range.ParagraphFormat.SpaceAfter = 0
  $t.Range.ParagraphFormat.SpaceBefore = 0
  $t.Rows.Item(1).Range.Font.Bold = $true
  [void]$script:sel.EndKey(6)
  [void]$script:sel.TypeParagraph()
  ResetFont
}

# ---------- title page ----------
$script:sel.Style = $script:doc.Styles.Item(-1)
$script:sel.ParagraphFormat.Alignment = 1
$script:sel.Font.Size = 26
$script:sel.Font.Bold = $true
[void]$script:sel.TypeText('API Design and Data Modelling: a ride hailing service')
[void]$script:sel.TypeParagraph()
$script:sel.Font.Bold = $false
$script:sel.Font.Size = 14
[void]$script:sel.TypeParagraph()
[void]$script:sel.TypeText('Sonia Pepple')
[void]$script:sel.TypeParagraph()
[void]$script:sel.TypeText('13 October 2026')
[void]$script:sel.TypeParagraph()
ResetFont
[void]$script:sel.InsertBreak(7)

# ---------- contents ----------
$script:sel.Style = $script:doc.Styles.Item(-2)
[void]$script:sel.TypeText('Contents')
[void]$script:sel.TypeParagraph()
$rng = $script:sel.Range
[void]$script:doc.TablesOfContents.Add($rng, $true, 1, 3)
[void]$script:sel.EndKey(6)
ResetFont

# ---------- content ----------
$files = @(
  'ch00_front.txt',
  'ch01_requirements.txt',
  'ch02_entities.txt',
  'ch03_hard.txt',
  'ch04_state.txt',
  'ch05_constraints.txt',
  'ch06_api.txt',
  'ch07_overfetch.txt',
  'ch08_realtime.txt',
  'ch09_proof.txt',
  'ch10_open.txt',
  'ch11_appendix.txt',
  'appendix_ef.txt'
)

foreach($f in $files){
  $path = Join-Path $script:tmp $f
  if(-not (Test-Path -LiteralPath $path)){ Write-Warning "missing content file $f"; continue }
  $lines = Get-Content -LiteralPath $path -Encoding UTF8
  $i = 0
  while($i -lt $lines.Count){
    $ln = $lines[$i]
    if($ln -match '^#\s+(.*)$'){ AddH1 $matches[1] }
    elseif($ln -match '^##\s+(.*)$'){ AddH2 $matches[1] }
    elseif($ln -match '^###\s+(.*)$'){ AddH3 $matches[1] }
    elseif($ln -match '^@SRC\s+(.*)$'){ AddSource $matches[1] }
    elseif($ln -match '^@CAP\s+(.*)$'){ AddCaption $matches[1] }
    elseif($ln -match '^@P\s+(.*)$'){ AddParagraph $matches[1] }
    elseif($ln -match '^@B\s+(.*)$'){ AddBullet $matches[1] }
    elseif($ln -match '^@PAGE\s*$'){ [void]$script:sel.InsertBreak(7) }
    elseif($ln -match '^@IMG\s+(.+)$'){
      $parts = $matches[1].Split('|')
      $cap = ''
      if($parts.Count -gt 1){ $cap = $parts[1].Trim() }
      $w = 12.5
      if($parts.Count -gt 2){ $wval = 0.0; if([double]::TryParse($parts[2].Trim(), [ref]$wval)){ $w = $wval } }
      AddImage $parts[0].Trim() $cap $w
    }
    elseif($ln -match '^@CODE\s*$'){
      $i++; $code = @()
      while($i -lt $lines.Count -and $lines[$i] -notmatch '^@END\s*$'){ $code += $lines[$i]; $i++ }
      AddCode $code
    }
    elseif($ln -match '^@TBL\s+(\d+)\s*$'){
      $sz = [int]$matches[1]; $i++; $rows = @()
      while($i -lt $lines.Count -and $lines[$i] -notmatch '^@END\s*$'){ $rows += $lines[$i]; $i++ }
      AddTable $rows $sz
    }
    $i++
  }
  Write-Output ("PG " + $f + "=" + $script:doc.ComputeStatistics(2))
}

# ---------- footer page number ----------
$fr = $script:doc.Sections.Item(1).Footers.Item(1).Range
$fr.Text = ''
$fr = $script:doc.Sections.Item(1).Footers.Item(1).Range
$fr.Text = 'Page '
[void]$script:doc.Fields.Add($fr, 33)
$script:doc.Sections.Item(1).Footers.Item(1).Range.ParagraphFormat.Alignment = 1

# ---------- update fields, save, export ----------
if($script:doc.TablesOfContents.Count -gt 0){ $script:doc.TablesOfContents.Item(1).Update() }
try { $script:doc.Fields.Update() | Out-Null } catch {}

$pages = $script:doc.ComputeStatistics(2)

$all = $script:doc.Content.Text
$hasMarker = $all -match '\[CLASS NOTE NEEDED'
$hasDash = $all -match '[\u2013\u2014]'

$saved = $false
$e1 = ''; $e2 = ''; $e3 = ''
$out = [string]$script:docx
Write-Output ("DBG_PATH=[" + $out + "] len=" + $out.Length + " active=" + $script:word.ActiveDocument.Name)
try { $script:doc.SaveAs([ref]$out, [ref]16); $saved = $true } catch { $e1 = $_.Exception.Message }
if(-not $saved){ try { $script:doc.SaveAs2([ref]$out, [ref]16); $saved = $true } catch { $e2 = $_.Exception.Message } }
if(-not $saved){ try { $script:doc.SaveAs([ref]$out, [ref]16); $saved = $true } catch { $e3 = $_.Exception.Message } }

try { [void]$script:doc.ExportAsFixedFormat($script:pdf, 17) } catch { Write-Output ("EXPORT_ERR=" + $_.Exception.Message) }

Write-Output ("PAGES=" + $pages)
Write-Output ("SAVED=" + $saved)
Write-Output ("E1=" + $e1)
Write-Output ("E2=" + $e2)
Write-Output ("E3=" + $e3)
Write-Output ("HAS_CLASS_NOTE_MARKER=" + $hasMarker)
Write-Output ("HAS_DASH_OR_EM_DASH=" + $hasDash)
Write-Output ("DOCX=" + $script:docx)
Write-Output ("PDF=" + $script:pdf)

$script:doc.Close([ref]$false)
$script:word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:sel) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:doc) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:word) | Out-Null
[GC]::Collect()
