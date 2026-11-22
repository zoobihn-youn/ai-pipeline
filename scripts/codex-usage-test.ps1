# codex exec usage measurement (PROJECT.md section 7 item 5, section 8)
# AI calls: codex = 4 (step 3 review x3 = first + 2 re-reviews, step 5 check x1), claude 0.
# Before/after: open interactive codex, type /status, read "1-month limit % remaining".
# Do NOT use Codex (CLI or VS Code) between the before and after readings.
$root    = Split-Path -Parent $PSScriptRoot
$codex   = "C:\Users\apter\AppData\Local\Programs\AI-DevTools\node-v26.13.0-win-x64\codex.cmd"
$testDir = Join-Path $root "tests\codex-test"
$logDir  = Join-Path $root ".pipeline\logs"
$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$log     = Join-Path $logDir "codex-usage-test-$stamp.txt"
$csv     = Join-Path $logDir "codex-usage-test-$stamp.csv"

if (-not (Test-Path $codex))   { Write-Host "codex not found: $codex"; exit 1 }
if (-not (Test-Path (Join-Path $testDir "sample.py"))) { Write-Host "dummy files missing in $testDir"; exit 1 }
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Log($text) {
    Write-Host $text
    [System.IO.File]::AppendAllText($log, ([string]$text + "`r`n"), $utf8)
}

# Plain words only in prompts: codex.cmd goes through cmd.exe, which mangles quotes and symbols.
$review = "You are a read-only code reviewer. Read TASK.md and sample.py. Reply in at most 5 lines. " +
          "The first line must be exactly VERDICT: PASS or VERDICT: BLOCK. Then list problems briefly."
$check  = "You are a read-only checker. Read REPORT.md and the files in the runs folder. Reply in at most 5 lines. " +
          "The first line must be exactly VERDICT: PASS or VERDICT: BLOCK. Then say whether each claim in REPORT.md matches the actual files."
$calls = @(
    @{ name = "step3-review-1"; prompt = $review },
    @{ name = "step3-review-2"; prompt = $review },
    @{ name = "step3-review-3"; prompt = $review },
    @{ name = "step5-check";    prompt = $check  }
)

Log ("started: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz") + " / codex: $codex")
Log ("codex version: " + ((& $codex --version 2>&1) -join " "))
Write-Host ""
Write-Host "In another window run: codex   then type: /status"
$before = Read-Host "BEFORE - Codex 1-month limit % REMAINING"
Log ("before: monthly remaining=$before%")

[System.IO.File]::WriteAllText($csv, "call,exit,verdict,stop,duration_s,input,cached_input,output,reasoning_output`r`n", $utf8)
$sum = @{ input = 0; cached = 0; output = 0; reasoning = 0; stops = 0 }

foreach ($c in $calls) {
    $name    = $c.name
    $jsonl   = Join-Path $logDir "codex-usage-test-$stamp-$name.jsonl"
    $lastMsg = Join-Path $logDir "codex-usage-test-$stamp-$name.last.txt"
    $codexArgs = @("exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "--json", "-o", $lastMsg, $c.prompt)

    Push-Location $testDir
    $ErrorActionPreference = "Continue"
    $t0   = Get-Date
    $raw  = & $codex @codexArgs 2> (Join-Path $logDir "codex-usage-test-$stamp-$name.stderr.txt")
    $code = $LASTEXITCODE
    $secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    Pop-Location
    [System.IO.File]::WriteAllText($jsonl, ($raw -join "`n"), $utf8)

    # Token usage is on the turn.completed event (Codex non-interactive docs).
    $usage = $null; $failed = $false
    foreach ($line in $raw) {
        try { $e = $line | ConvertFrom-Json } catch { continue }
        if ($e.type -eq "turn.completed") { $usage = $e.usage }
        if ($e.type -eq "turn.failed" -or $e.type -eq "error") { $failed = $true }
    }
    $verdict = ""
    if (Test-Path $lastMsg) {
        $first = (Get-Content $lastMsg -Encoding UTF8 | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if ($first -match "VERDICT:\s*(PASS|BLOCK)") { $verdict = $Matches[1] }
    }
    # Stop rule for Codex: command failed, turn failed, or no verdict line (PROJECT.md 5, 11).
    $stop = ($code -ne 0) -or $failed -or ($verdict -eq "")
    if ($stop) { $sum.stops++ }
    if ($usage) {
        $sum.input += [int]$usage.input_tokens; $sum.cached += [int]$usage.cached_input_tokens
        $sum.output += [int]$usage.output_tokens; $sum.reasoning += [int]$usage.reasoning_output_tokens
    }
    $row = @($name, $code, $verdict, $(if ($stop) { "STOP" } else { "OK" }), $secs,
             $usage.input_tokens, $usage.cached_input_tokens, $usage.output_tokens, $usage.reasoning_output_tokens) -join ","
    [System.IO.File]::AppendAllText($csv, $row + "`r`n", $utf8)
    Log ("call : " + $row)
}

Write-Host ""
Write-Host "All calls finished. Wait about 1 minute, then check /status again (restart codex if it shows old numbers)."
$after = Read-Host "AFTER - Codex 1-month limit % REMAINING"
Log ("after: monthly remaining=$after%")
Log ("token totals: input=" + $sum.input + " cached_input=" + $sum.cached + " output=" + $sum.output + " reasoning_output=" + $sum.reasoning)
Log ("calls with STOP: " + $sum.stops + " of " + $calls.Count)
Log "expected verdicts: step3 = BLOCK (empty list bug), step5 = BLOCK (REPORT claims empty list returns 0)"
Log ("finished: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"))
Log "AI calls: codex 4, claude 0"
"saved: $log"
