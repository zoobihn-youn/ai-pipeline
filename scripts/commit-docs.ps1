# Commit and push document or script edits in one line (PROJECT.md 21, item A).
# Usage, from the project folder:  powershell -ExecutionPolicy Bypass -File C:\dev\ai-pipeline\scripts\commit-docs.ps1 "message"
# Runs only on main: right after a run the folder is on run/<RunId>, so judge (stage 7) first.
# ASCII only (Windows PowerShell 5.1). The message may be Korean: it goes to git through a UTF-8 file.
param([Parameter(Mandatory = $true)][string]$Message, [string]$ProjectRoot = (Get-Location).Path)

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Fail([string]$m) { Write-Host ("FAILED: " + $m); exit 1 }
# git with an argument array (no cmd.exe quoting); stderr is merged into the text.
function G([string[]]$gitArgs) {
    $out = & git -C $ProjectRoot @gitArgs 2>&1
    return @{ code = $LASTEXITCODE; out = ((@($out) | ForEach-Object { "$_" }) -join "`n") }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) { Fail "not a git folder: $ProjectRoot" }
$b = (G @("rev-parse", "--abbrev-ref", "HEAD")).out.Trim()
if ($b -ne "main") { Fail "on branch '$b', not main. Judge the run first (n8n judge workflow)." }
$s = G @("status", "--porcelain")
if ($s.code -ne 0) { Fail $s.out }
if (-not $s.out.Trim()) { Write-Host "Nothing to commit."; exit 0 }
Write-Host "Files to commit:"
Write-Host $s.out

$msgFile = Join-Path ([System.IO.Path]::GetTempPath()) ("commit-docs-" + [guid]::NewGuid().ToString("N") + ".txt")
[System.IO.File]::WriteAllText($msgFile, $Message, $utf8)
$r = G @("add", "-A"); if ($r.code -ne 0) { Remove-Item $msgFile -ErrorAction SilentlyContinue; Fail ("add: " + $r.out) }
$r = G @("commit", "-F", $msgFile); Remove-Item $msgFile -ErrorAction SilentlyContinue
if ($r.code -ne 0) { Fail ("commit: " + $r.out) }
Write-Host $r.out
$r = G @("push", "origin", "main")
if ($r.code -ne 0) { Fail ("committed locally but push failed: " + $r.out) }
Write-Host ("Pushed. main = " + (G @("rev-parse", "--short", "HEAD")).out.Trim())
