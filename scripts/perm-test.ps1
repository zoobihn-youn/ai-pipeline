# claude -p permission test (PROJECT.md section 7 item 3, section 14)
# AI calls: claude 1, codex 0.
# Checks in one run: allowed write succeeds, non-allowed shell command is denied,
# and what exit code / permission_denials look like when something is denied.
$root    = Split-Path -Parent $PSScriptRoot
$claude  = "C:\Users\apter\.local\bin\claude.exe"
$testDir = Join-Path $root "tests\perm-test"
$logDir  = Join-Path $root ".pipeline\logs"
$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonOut = Join-Path $logDir "perm-test-$stamp.json"
$errOut  = Join-Path $logDir "perm-test-$stamp.stderr.txt"
$log     = Join-Path $logDir "perm-test-$stamp.txt"
$target  = "out/hello-$stamp.txt"   # new name every run, so an old file can't look like success

if (-not (Test-Path $claude)) { Write-Host "claude not found: $claude"; exit 1 }
New-Item -ItemType Directory -Force -Path (Join-Path $testDir "out"), $logDir | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$prompt = "Do exactly two steps, then stop. " +
          "Step 1: create the file $target containing the single line: pipeline ok. " +
          "Step 2: run this shell command: node -p 42. " +
          "If a step is denied, do not retry it and do not try another way. " +
          "Finally report each step on its own line as STEP1=done or STEP1=denied, then STEP2=done or STEP2=denied."

$claudeArgs = @(
    "-p", $prompt,
    "--permission-mode", "dontAsk",
    "--allowedTools", "Edit(./out/**)",
    "--permission-prompts", "none",
    "--output-format", "json",
    "--max-turns", "6",
    "--model", "haiku"
)

# UTF-8 without BOM, so n8n and other tools read the files the same way (PROJECT.md 14).
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Log($text) {
    Write-Host $text
    [System.IO.File]::AppendAllText($log, ([string]$text + "`r`n"), $utf8)
}

Log ("started: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"))
Log ("cwd: $testDir")
Log ("command: claude " + (($claudeArgs | ForEach-Object { if ($_ -match ' ') { '"' + $_ + '"' } else { $_ } }) -join ' '))

Push-Location $testDir
$ErrorActionPreference = "Continue"
$raw  = & $claude @claudeArgs 2> $errOut
$code = $LASTEXITCODE
Pop-Location

Log ("finished: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"))
Log ("exit code: $code")
[System.IO.File]::WriteAllText($jsonOut, ($raw -join "`n"), $utf8)

try {
    $r = ($raw -join "`n") | ConvertFrom-Json
    Log ("is_error: " + $r.is_error + " / subtype: " + $r.subtype + " / num_turns: " + $r.num_turns)
    Log ("total_cost_usd (client estimate, usage reference only): " + $r.total_cost_usd)
    $denials = if ($null -eq $r.permission_denials) { @() } else { @($r.permission_denials) }
    Log ("permission_denials count: " + $denials.Count)
    # Stop rule (PROJECT.md 5, 14): any one of these means the stage failed.
    $stop = ($code -ne 0) -or ($r.is_error -eq $true) -or ($denials.Count -gt 0)
    Log ("stop rule -> " + $(if ($stop) { "STOP" } else { "PASS" }) + " (exit=$code, is_error=" + $r.is_error + ", denials=" + $denials.Count + ")")
    if ($denials.Count -gt 0) { Log ($denials | ConvertTo-Json -Depth 6) }
    Log "--- result text ---"
    Log $r.result
} catch {
    Log ("JSON parse FAILED: " + $_.Exception.Message + " (see $jsonOut and $errOut)")
}

$file = Join-Path $testDir $target
if (Test-Path $file) { Log ("file created: yes / content: " + (Get-Content $file -Raw).Trim()) }
else { Log "file created: no" }

Log "expected: file created yes, node denied (denials >= 1), stop rule -> STOP."
Log "AI calls: claude 1, codex 0"
"saved: $log"
