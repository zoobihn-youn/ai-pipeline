# claude -p usage measurement (PROJECT.md section 7 item 4, section 8)
# AI calls: claude = $Count (default 5), codex 0.
# Do NOT use Claude chat between the "before" and "after" readings: chat shares the same plan limit.
param(
    [int]$Count = 5,
    [string]$Model = "haiku"
)
$root    = Split-Path -Parent $PSScriptRoot
$claude  = "C:\Users\apter\.local\bin\claude.exe"
$testDir = Join-Path $root "tests\usage-test"
$logDir  = Join-Path $root ".pipeline\logs"
$stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$log     = Join-Path $logDir "usage-test-$stamp.txt"
$csv     = Join-Path $logDir "usage-test-$stamp.csv"

if (-not (Test-Path $claude)) { Write-Host "claude not found: $claude"; exit 1 }
New-Item -ItemType Directory -Force -Path (Join-Path $testDir "out"), $logDir | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Log($text) {
    Write-Host $text
    [System.IO.File]::AppendAllText($log, ([string]$text + "`r`n"), $utf8)
}

Log ("started: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz") + " / model: $Model / calls: $Count")
Write-Host ""
Write-Host "Open claude.ai > Settings > Usage now (refresh the page)."
$before5h = Read-Host "BEFORE - current session (5-hour) % used"
$beforeWk = Read-Host "BEFORE - weekly % used"
Log ("before: session=$before5h% weekly=$beforeWk%")

[System.IO.File]::WriteAllText($csv, "call,exit,is_error,denials,stop,turns,duration_ms,input,cache_write,cache_read,output,cost_usd_estimate`r`n", $utf8)
$sum = @{ input = 0; cw = 0; cr = 0; output = 0; cost = 0.0; stops = 0 }

for ($i = 1; $i -le $Count; $i++) {
    $target = "out/call-$stamp-$i.txt"
    $prompt = "Create the file $target containing the single line: call $i ok. Then reply with exactly: DONE"
    $claudeArgs = @(
        "-p", $prompt,
        "--permission-mode", "dontAsk",
        "--allowedTools", "Edit(./out/**)",
        "--permission-prompts", "none",
        "--output-format", "json",
        "--max-turns", "4",
        "--model", $Model
    )
    Push-Location $testDir
    $ErrorActionPreference = "Continue"
    $raw  = & $claude @claudeArgs 2> (Join-Path $logDir "usage-test-$stamp-$i.stderr.txt")
    $code = $LASTEXITCODE
    Pop-Location
    [System.IO.File]::WriteAllText((Join-Path $logDir "usage-test-$stamp-$i.json"), ($raw -join "`n"), $utf8)

    try {
        $r = ($raw -join "`n") | ConvertFrom-Json
        $denials = if ($null -eq $r.permission_denials) { 0 } else { @($r.permission_denials).Count }
        $stop = ($code -ne 0) -or ($r.is_error -eq $true) -or ($denials -gt 0)
        $u = $r.usage
        $row = @($i, $code, $r.is_error, $denials, $(if ($stop) { "STOP" } else { "PASS" }), $r.num_turns, $r.duration_ms,
                 $u.input_tokens, $u.cache_creation_input_tokens, $u.cache_read_input_tokens, $u.output_tokens, $r.total_cost_usd) -join ","
        $sum.input += [int]$u.input_tokens; $sum.cw += [int]$u.cache_creation_input_tokens
        $sum.cr += [int]$u.cache_read_input_tokens; $sum.output += [int]$u.output_tokens
        $sum.cost += [double]$r.total_cost_usd
        if ($stop) { $sum.stops++ }
    } catch {
        $row = "$i,$code,PARSE_FAILED,,STOP,,,,,,,"
        $sum.stops++
    }
    [System.IO.File]::AppendAllText($csv, $row + "`r`n", $utf8)
    Log ("call $i : " + $row)
}

Write-Host ""
Write-Host "All calls finished. Wait about 1 minute, then refresh Settings > Usage."
$after5h = Read-Host "AFTER - current session (5-hour) % used"
$afterWk = Read-Host "AFTER - weekly % used"
Log ("after: session=$after5h% weekly=$afterWk%")
Log ("token totals: input=" + $sum.input + " cache_write=" + $sum.cw + " cache_read=" + $sum.cr + " output=" + $sum.output)
Log ("cost_usd_estimate total (list price, not plan usage): " + $sum.cost)
Log ("calls with STOP: " + $sum.stops + " of $Count")
Log ("finished: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"))
Log "AI calls: claude $Count, codex 0"
"saved: $log"
