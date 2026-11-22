# One pipeline stage, called by n8n (PROJECT.md 16).
# Always prints ONE JSON line to stdout and exits 0. n8n reads that line and decides what runs next.
# Mode: fake = all stages fake (no AI calls) | real:s2[,s4...] = listed stages real, others fake | real = all stages real.
# A stage asked to run real that is not implemented yet refuses, so no accidental AI call.
# Scenarios (fake only): pass | block1 (S3 BLOCK on attempt 1, then PASS) | blockall (S3 always BLOCK) | fail4 (S4 fails)
# Arguments are checked inside the script (PROJECT.md 18), so a bad value still prints the JSON line and is logged.
# Git (PROJECT.md 18): S0 checks git and records files already changed; end commits ONCE on branch run/<RunId>, only when mode=real and outcome=pass.
param(
    [string]$Stage = "",
    [string]$RunId = "",
    [string]$Attempt = "1",
    [string]$Mode = "fake",
    [string]$Scenario = "pass",
    [string]$Outcome = "pass"
)
# Attempt arrives as text so a bad value cannot crash PowerShell before the script starts; it becomes a number here.
$attemptIn = $Attempt
Remove-Variable -Name Attempt
[int]$Attempt = 0
$attemptOk = [int]::TryParse($attemptIn, [ref]$Attempt)
$ErrorActionPreference = "Continue"   # native commands write to stderr; "Stop" would turn that into a crash on PowerShell 5.1
$utf8   = New-Object System.Text.UTF8Encoding($false)   # UTF-8 without BOM (PROJECT.md 14)
$claude = "C:\Users\apter\.local\bin\claude.exe"
$codex  = "C:\Users\apter\AppData\Local\Programs\AI-DevTools\node-v26.13.0-win-x64\codex.cmd"   # fixed path (PROJECT.md 13)
$script:pipe = $null

function Now { Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz" }

function Emit([bool]$ok, [string]$verdict, [string]$note, [int]$aiClaude = 0, [int]$aiCodex = 0) {
    $o = [ordered]@{ run = $RunId; stage = $Stage; attempt = $Attempt; mode = $Mode; scenario = $Scenario
                     ok = $ok; verdict = $verdict; note = $note; ai_claude = $aiClaude; ai_codex = $aiCodex; at = (Now) }
    $line = $o | ConvertTo-Json -Compress
    if ($script:pipe) {
        [System.IO.File]::AppendAllText($script:runLog, $line + "`n", $utf8)
        $st = [ordered]@{ run = $RunId; stage = $Stage; attempt = $Attempt
                          status = $(if ($ok) { "done" } else { "stopped" }); verdict = $verdict; at = $o.at }
        [System.IO.File]::WriteAllText((Join-Path $script:pipe "STATUS.json"), ($st | ConvertTo-Json), $utf8)
    }
    Write-Output $line
    exit 0
}

# [string] turns stderr ErrorRecords (PowerShell 5.1 wraps native stderr when 2>&1) back into plain message text.
function OneLine($x) { ((($x | ForEach-Object { [string]$_ }) | Out-String).Trim() -replace '\s*\r?\n\s*', ' / ') }

function Write-Review([string]$name, [string]$verdict, [string]$body) {
    $f = Join-Path $script:revDir $name
    [System.IO.File]::WriteAllText($f, "VERDICT: $verdict`n`n$body`n", $utf8)
    return $f
}

# Same rule the real stages will use: first line must be exactly VERDICT: PASS or VERDICT: BLOCK (PROJECT.md 11-2).
function Read-Verdict([string]$file) {
    $first = Get-Content -LiteralPath $file -Encoding UTF8 -TotalCount 1
    if ($first -match '^\s*VERDICT:\s*(PASS|BLOCK)\s*$') { return $Matches[1] }
    return ""
}

# Time limit for every external call (PROJECT.md 5: stop when time runs out). User decision 2026-11-22: 3 minutes.
$script:timeoutSec = 180

function Quote-Arg([string]$a) {
    if ($a -eq "") { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    return '"' + $a.Replace('"', '\"') + '"'
}

# Start a program with stdin closed at once, read its output, and kill the whole process tree if it runs past the limit.
# $file = program, $arguments = one command-line string, $tag = log name part, $utf8Out = decode output as UTF-8.
function Invoke-Native([string]$file, [string]$arguments, [string]$tag, [bool]$utf8Out) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($utf8Out) { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8 }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()   # codex exec otherwise waits for more input forever under n8n (PROJECT.md 16)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($script:timeoutSec * 1000)
    if (-not $done) {
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        $p.WaitForExit(10000) | Out-Null
    } else {
        $p.WaitForExit()   # let the output readers finish
    }
    $out = $outTask.Result
    $err = $errTask.Result
    $base = Join-Path $logDir "run-$RunId-$tag"
    [System.IO.File]::WriteAllText("$base.stderr.txt", [string]$err, $utf8)
    $code = if ($done) { $p.ExitCode } else { -1 }
    return @{ code = $code; out = [string]$out; err = [string]$err; timedOut = (-not $done); base = $base }
}

# git through cmd.exe (works whether git is git.exe or git.cmd), same time limit and closed stdin (PROJECT.md 18).
function Invoke-Git([string]$gitArgs, [string]$tag) {
    return Invoke-Native "cmd.exe" ('/d /s /c "git ' + $gitArgs + '"') $tag $true
}

# Run one claude -p stage. Stop rule (PROJECT.md 5, 14): exit code, is_error, permission_denials - not the answer text.
function Invoke-Claude([string]$tag, [string]$prompt, [string[]]$allowed) {
    if (-not (Test-Path -LiteralPath $claude)) { Emit $false "" "claude not found: $claude" }
    $claudeArgs = @("-p", $prompt, "--permission-mode", "dontAsk")
    if (@($allowed).Count -gt 0) { $claudeArgs += @("--allowedTools") + $allowed }   # no list = read only (Read needs no permission, PROJECT.md 16)
    $claudeArgs += @("--permission-prompts", "none", "--output-format", "json", "--max-turns", "10", "--model", "haiku")
    $n = Invoke-Native $claude ((@($claudeArgs) | ForEach-Object { Quote-Arg $_ }) -join " ") $tag $true
    $base = $n.base
    [System.IO.File]::WriteAllText("$base.json", $n.out, $utf8)
    if ($n.timedOut) { Emit $false "" ("claude timeout after " + $script:timeoutSec + "s, process tree killed") 1 0 }
    $code = $n.code
    $r = $null
    try { $r = $n.out | ConvertFrom-Json } catch { }
    if ($null -eq $r) { Emit $false "" "claude exit=$code, JSON parse failed (see $base.json)" 1 0 }
    $denials = if ($null -eq $r.permission_denials) { 0 } else { @($r.permission_denials).Count }
    $ok = ($code -eq 0) -and ($r.is_error -ne $true) -and ($denials -eq 0)
    return @{ ok = $ok; result = [string]$r.result; note = ("claude exit=$code is_error=" + $r.is_error + " denials=$denials turns=" + $r.num_turns + "; json=" + (Split-Path -Leaf "$base.json")) }
}

# Run one codex exec check (read-only). Codex only answers; this script writes the review file (PROJECT.md 4).
# Invocation as in codex-usage-test.ps1 (PROJECT.md 8). Plain words only in prompts: codex.cmd goes through cmd.exe.
# Stop rule for Codex (PROJECT.md 5, 8, 11): exit code, turn.failed/error event, or no verdict line.
function Invoke-Codex([string]$tag, [string]$prompt, [string]$reviewName) {
    if (-not (Test-Path -LiteralPath $codex)) { Emit $false "" "codex not found: $codex" }
    $last = Join-Path $logDir "run-$RunId-$tag.last.txt"
    $codexArgs = @("exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "--json", "-o", $last, $prompt)
    $argStr = (@($codexArgs) | ForEach-Object { Quote-Arg $_ }) -join " "
    # codex.cmd is a batch file, so it runs through cmd.exe (/s /c strips only the outer quotes).
    $n = Invoke-Native "cmd.exe" ('/d /s /c "' + (Quote-Arg $codex) + ' ' + $argStr + '"') $tag $true
    [System.IO.File]::WriteAllText(($n.base + ".jsonl"), $n.out, $utf8)
    if ($n.timedOut) { Emit $false "" ("codex timeout after " + $script:timeoutSec + "s, process tree killed") 0 1 }
    $failed = $false
    foreach ($line in ($n.out -split "`r?`n")) {
        try { $e = $line | ConvertFrom-Json } catch { continue }
        if ($e.type -eq "turn.failed" -or $e.type -eq "error") { $failed = $true }
    }
    $f = Join-Path $script:revDir $reviewName
    $body = if (Test-Path -LiteralPath $last) { ([System.IO.File]::ReadAllText($last, $utf8)).TrimStart() } else { "" }
    [System.IO.File]::WriteAllText($f, $body, $utf8)
    $read = Read-Verdict $f
    $ok = ($n.code -eq 0) -and (-not $failed) -and ($read -ne "")
    return @{ ok = $ok; verdict = $read; note = ("codex exit=" + $n.code + " failed=$failed verdict=$read; review=$reviewName") }
}

try {
    # Argument checks (PROJECT.md 18). RunId names the log file, so a bad RunId is reported without writing any file.
    if ($RunId -notmatch '^[0-9]{8}-[0-9]{6}$') { Emit $false "" "bad -RunId '$RunId' (expected yyyyMMdd-HHmmss); nothing logged" }
    $root = $env:PROJECT_ROOT
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        Emit $false "" "PROJECT_ROOT not set or folder missing (start n8n with scripts\start-n8n.ps1)"
    }
    $script:pipe   = Join-Path $root ".pipeline"
    $script:revDir = Join-Path $script:pipe "reviews"
    $fakeDir       = Join-Path $script:pipe "fake"
    $logDir        = Join-Path $script:pipe "logs"
    New-Item -ItemType Directory -Force -Path $script:revDir, $fakeDir, $logDir | Out-Null
    $script:runLog = Join-Path $logDir "run-$RunId.jsonl"

    $bad = @()
    if (@("s0","s2","s3","s4","s5","s6","end") -notcontains $Stage) { $bad += "-Stage '$Stage'" }
    if ($Mode -notmatch '^(fake|real|real:(s[0-9])(,s[0-9])*)$') { $bad += "-Mode '$Mode'" }
    if (@("pass","block1","blockall","fail4") -notcontains $Scenario) { $bad += "-Scenario '$Scenario'" }
    if (@("pass","stopped") -notcontains $Outcome) { $bad += "-Outcome '$Outcome'" }
    if (-not $attemptOk -or $Attempt -lt 1) { $bad += "-Attempt '$attemptIn'" }
    if ($bad.Count -gt 0) { Emit $false "" ("bad argument: " + ($bad -join ", ")) }

    $realStages = if ($Mode -eq "real") { @("s2","s3","s4","s5","s6") } elseif ($Mode -like "real:*") { $Mode.Substring(5).Split(",") } else { @() }
    $isReal = $realStages -contains $Stage
    $implemented = @("s2", "s3", "s4", "s5", "s6")   # stages that have a real implementation so far (PROJECT.md 16)
    if ($isReal -and $implemented -notcontains $Stage) {
        Emit $false "" "real $Stage is not implemented yet (no AI call made)"
    }

    switch ($Stage) {
        "s0" {
            # Pre-check: required files, and both CLIs runnable from n8n. Version/login checks are not AI calls.
            $miss = @()
            foreach ($f in "PROJECT.md", "TASK.md") { if (-not (Test-Path -LiteralPath (Join-Path $root $f))) { $miss += $f } }
            if ($miss.Count -gt 0) { Emit $false "" ("missing in PROJECT_ROOT: " + ($miss -join ", ")) }
            if (-not (Test-Path -LiteralPath $claude)) { Emit $false "" "claude not found: $claude" }
            if (-not (Test-Path -LiteralPath $codex))  { Emit $false "" "codex not found: $codex" }
            $nodeV = "not found"; try { $nodeV = OneLine (& node -v 2>&1) } catch { }
            # Through Invoke-Native: same 3-minute limit and closed stdin as the AI calls (PROJECT.md 16).
            $c1 = Invoke-Native $claude "--version" "s0-claude" $true
            $c2 = Invoke-Native "cmd.exe" ('/d /s /c "' + (Quote-Arg $codex) + ' --version"') "s0-codex" $true
            $c3 = Invoke-Native "cmd.exe" ('/d /s /c "' + (Quote-Arg $codex) + ' login status"') "s0-codexlogin" $true
            $note = "node=$nodeV; claude=" + (OneLine ($c1.out + $c1.err)) + " (exit " + $c1.code + "); codex=" + (OneLine ($c2.out + $c2.err)) +
                    " (exit " + $c2.code + "); codex login=" + (OneLine ($c3.out + $c3.err)) + " (exit " + $c3.code + ")"
            if ($c1.timedOut -or $c2.timedOut -or $c3.timedOut) { $note = "timeout in version/login check; " + $note }
            # python: recorded only, not a stop condition (another project may not use python) (PROJECT.md 18)
            $py = Invoke-Native "cmd.exe" '/d /s /c "python --version"' "s0-python" $true
            $note += "; python=" + (OneLine ($py.out + $py.err)) + " (exit " + $py.code + ")"
            # git: required in every mode (PROJECT.md 18). Stop if git is missing, the folder is not a repo with a first commit, or no author is set.
            $g1 = Invoke-Git "--version" "s0-git"
            $g2 = Invoke-Git "rev-parse --verify --quiet HEAD" "s0-githead"
            $g3 = Invoke-Git "config user.name" "s0-gitname"
            $g4 = Invoke-Git "config user.email" "s0-gitmail"
            $g5 = Invoke-Git "rev-parse --abbrev-ref HEAD" "s0-gitbranch"
            $g6 = Invoke-Git "status --porcelain" "s0-gitstatus"
            # Files already changed before this run: recorded, not a stop condition (PROJECT.md 18). The end stage shows them in RESULT.
            $dirty = @(($g6.out -split "`r?`n") | Where-Object { $_.Trim() })
            [System.IO.File]::WriteAllText((Join-Path $logDir "run-$RunId-s0-gitstatus.txt"), ($dirty -join "`n"), $utf8)
            $gitOk = ($g1.code -eq 0) -and ($g2.code -eq 0) -and ($g3.code -eq 0) -and ($g4.code -eq 0) -and ($g6.code -eq 0)
            $note += "; git=" + (OneLine $g1.out) + " (exit " + $g1.code + "); head=" + $(if ($g2.code -eq 0) { "ok" } else { "no commit (exit " + $g2.code + ")" }) +
                     "; author=" + $(if (($g3.code -eq 0) -and ($g4.code -eq 0)) { "set" } else { "missing" }) +
                     "; branch=" + (OneLine $g5.out) + "; changed before run=" + $dirty.Count
            Emit (($c1.code -eq 0) -and ($c2.code -eq 0) -and ($c3.code -eq 0) -and $gitOk) "" $note
        }
        "s2" {
            if ($isReal) {
                # Real develop: claude -p, may only write under work/ and REPORT.md, may not run anything (PROJECT.md 14).
                $prompt = "You are stage 2 (develop) of an automated pipeline. Read TASK.md in the current folder and do what it asks. " +
                          "Create or edit files only under work/ and the file REPORT.md. Do not run any command or code; a later stage runs it. " +
                          "REPORT.md: add a new section at the TOP and keep any existing content below it. " +
                          "The section starts with the line: ## " + (Now) + " S2 develop (run $RunId, attempt $Attempt). " +
                          "List the files you created or changed and how each done condition in TASK.md will be checked. " +
                          "If a step is denied, do not retry it and do not try another way."
                if ($Attempt -gt 1) {
                    $prev = ".pipeline/reviews/review-$RunId-s3-" + ($Attempt - 1) + ".md"
                    $prompt += " This is attempt $Attempt. The code review blocked the previous attempt: read $prev first and fix what it says."
                }
                $c = Invoke-Claude "s2-$Attempt" $prompt @("Edit(./work/**)", "Edit(./REPORT.md)")
                Emit $c.ok "" $c.note 1 0
            }
            $f = Join-Path $fakeDir "s2-develop-$RunId-$Attempt.txt"
            [System.IO.File]::WriteAllText($f, "fake develop, attempt $Attempt`n", $utf8)
            Emit $true "" ("fake: wrote " + (Split-Path -Leaf $f))
        }
        "s3" {
            if ($isReal) {
                $prompt = "You are a read-only code reviewer, stage 3 of an automated pipeline. Read TASK.md, then review the code in the work folder against it. " +
                          "Do not run anything. Reply in at most 8 lines. The first line must be exactly VERDICT: PASS or VERDICT: BLOCK. " +
                          "Use BLOCK only for a problem that would break a done condition in TASK.md. Then list problems briefly, or write none."
                $c = Invoke-Codex "s3-$Attempt" $prompt "review-$RunId-s3-$Attempt.md"
                Emit $c.ok $c.verdict $c.note 0 1
            }
            $v = "PASS"
            if ($Scenario -eq "blockall" -or ($Scenario -eq "block1" -and $Attempt -eq 1)) { $v = "BLOCK" }
            $f = Write-Review "review-$RunId-s3-$Attempt.md" $v "fake code review (scenario=$Scenario)"
            $read = Read-Verdict $f
            if (-not $read) { Emit $false "" ("no VERDICT line in " + (Split-Path -Leaf $f)) }
            Emit $true $read ("fake review: " + (Split-Path -Leaf $f))
        }
        "s4" {
            if ($isReal) {
                # Real run WITHOUT AI (PROJECT.md 16, user decision B): stage.ps1 runs the "RUN:" command from TASK.md itself,
                # so the exit code is measured, not reported by a model. Output files are relative paths (cwd = PROJECT_ROOT).
                $runLine = Get-Content -LiteralPath (Join-Path $root "TASK.md") -Encoding UTF8 | Where-Object { $_ -match '^\s*RUN:\s*\S' } | Select-Object -First 1
                if (-not $runLine) { Emit $false "" "no 'RUN:' line in TASK.md" }
                $cmd = ($runLine -replace '^\s*RUN:\s*', '').Trim().Trim('`').Trim()
                # Old output is MOVED (not deleted) so this run's files are new for sure, and the old ones stay as evidence (PROJECT.md 18).
                $runsDir = Join-Path $root "runs"
                $moved = 0
                if (Test-Path -LiteralPath $runsDir) {
                    $oldItems = @(Get-ChildItem -LiteralPath $runsDir -Force)
                    if ($oldItems.Count -gt 0) {
                        $prevDir = Join-Path $script:pipe ("runs-prev\" + $RunId)
                        New-Item -ItemType Directory -Force -Path $prevDir | Out-Null
                        foreach ($it in $oldItems) { Move-Item -LiteralPath $it.FullName -Destination $prevDir -Force; $moved++ }
                    }
                }
                $started = Now
                $n = Invoke-Native "cmd.exe" ('/d /s /c "' + $cmd + '"') "s4" $false
                $ended = Now
                [System.IO.File]::WriteAllText(($n.base + ".stdout.txt"), $n.out, $utf8)
                $code = $n.code
                # Raw record measured by this script, for the checkers (S5, S6) to read (PROJECT.md 18).
                $raw = [ordered]@{ run = $RunId; command = $cmd; exit_code = $code; timed_out = $n.timedOut; started = $started; ended = $ended
                                   stdout_file = ".pipeline/logs/run-$RunId-s4.stdout.txt"; stderr_file = ".pipeline/logs/run-$RunId-s4.stderr.txt"
                                   moved_old_runs_files = $moved; moved_to = $(if ($moved -gt 0) { ".pipeline/runs-prev/$RunId/" } else { "" }) }
                [System.IO.File]::WriteAllText(($n.base + ".json"), ($raw | ConvertTo-Json), $utf8)
                if ($n.timedOut) { Emit $false "" ("run timeout after " + $script:timeoutSec + "s, process tree killed: $cmd") 0 0 }
                $outTxt = OneLine $n.out
                $errTxt = OneLine $n.err
                # REPORT.md: new section on top (PROJECT.md 5). Written by the script, so it states only measured facts.
                $sec = @(("## " + (Now) + " S4 run (run $RunId) - written by stage.ps1, no AI"), "",   # parentheses: "," binds before "+" in PowerShell
                         ("- command: " + [char]96 + $cmd + [char]96), "- exit code: $code",
                         "- stdout: $outTxt", "- stderr: $errTxt",
                         "- moved old runs/ files: $moved", "- raw: .pipeline/logs/run-$RunId-s4.json (exit code), .stdout.txt, .stderr.txt", "")
                $rep = Join-Path $root "REPORT.md"
                $old = if (Test-Path -LiteralPath $rep) { [System.IO.File]::ReadAllText($rep, $utf8) } else { "" }
                [System.IO.File]::WriteAllText($rep, (($sec -join "`n") + "`n" + $old), $utf8)
                Emit ($code -eq 0) "" ("ran: $cmd; exit=$code; moved old runs files=$moved; stdout=$outTxt; stderr=$errTxt") 0 0
            }
            if ($Scenario -eq "fail4") { Emit $false "" "fake: simulated failure (scenario=fail4)" }
            $f = Join-Path $fakeDir "s4-run-output-$RunId.txt"
            [System.IO.File]::WriteAllText($f, "fake run output`n", $utf8)
            Emit $true "" ("fake: wrote " + (Split-Path -Leaf $f))
        }
        "s5" {
            if ($isReal) {
                # Real first check: Codex compares REPORT.md claims with the actual files. BLOCK here does not stop the flow; S6 and the human judge (PROJECT.md 16).
                $prompt = "You are a read-only checker, stage 5 of an automated pipeline. Read TASK.md, the top sections of REPORT.md, the code in the work folder, the files in the runs folder " +
                          "and the run record .pipeline/logs/run-$RunId-s4.json (exit code measured by the pipeline script, not by an AI). " +
                          "Do not run anything. Reply in at most 8 lines. The first line must be exactly VERDICT: PASS or VERDICT: BLOCK. " +
                          "Use BLOCK if a claim in REPORT.md does not match the actual files or a done condition in TASK.md is not met. Then say briefly whether each claim matches."
                $c = Invoke-Codex "s5" $prompt "review-$RunId-s5.md"
                Emit $c.ok $c.verdict $c.note 0 1
            }
            $f = Write-Review "review-$RunId-s5.md" "PASS" "fake check of REPORT vs runs (scenario=$Scenario)"
            $read = Read-Verdict $f
            if (-not $read) { Emit $false "" ("no VERDICT line in " + (Split-Path -Leaf $f)) }
            Emit $true $read ("fake check: " + (Split-Path -Leaf $f))
        }
        "s6" {
            if ($isReal) {
                # Real second check: new claude -p session, read only (no allowed tools). Its answer goes into RESULT via the end stage (PROJECT.md 3, 15).
                $s3Last = Get-ChildItem -LiteralPath $script:revDir -Filter "review-$RunId-s3-*.md" | Sort-Object Name | Select-Object -Last 1
                $s3Name = if ($s3Last) { $s3Last.Name } else { "none" }
                $prompt = "You are stage 6, the second reviewer of an automated pipeline. Do not change any file and do not run anything. " +
                          "Read TASK.md, the code in work/, the top sections of REPORT.md, the files in runs/, the run record .pipeline/logs/run-$RunId-s4.json, and the first-round reviews " +
                          ".pipeline/reviews/$s3Name (code review) and .pipeline/reviews/review-$RunId-s5.md (check of REPORT vs files). " +
                          "Answer in Korean, at most 15 lines, in this order: 1. how important each problem the reviewers raised is; " +
                          "2. problems they missed, or none; 3. a short table of points where you disagree with the stage 5 check, or none; " +
                          "4. last line exactly RECOMMEND: PASS or RECOMMEND: BLOCK, as advice for the human who decides."
                $c = Invoke-Claude "s6" $prompt @()
                $f = Join-Path $script:revDir "review-$RunId-s6.md"
                [System.IO.File]::WriteAllText($f, $c.result, $utf8)
                Emit $c.ok "" ($c.note + "; review=review-$RunId-s6.md") 1 0
            }
            $f = Join-Path $script:revDir "review-$RunId-s6.md"
            [System.IO.File]::WriteAllText($f, "fake second review: no disagreement with s5`n", $utf8)
            Emit $true "" ("fake second review: " + (Split-Path -Leaf $f))
        }
        "end" {
            # Summary for the human (RESULT). Fake or partly real runs go to .pipeline/fake/RESULT.md so the real RESULT.md stays clean.
            $rows = @()
            if (Test-Path -LiteralPath $script:runLog) {
                $rows = @(Get-Content -LiteralPath $script:runLog -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
            }
            $aiC = 0; $aiX = 0
            foreach ($r in $rows) { $aiC += [int]$r.ai_claude; $aiX += [int]$r.ai_codex }
            $last = $rows | Select-Object -Last 1
            $md = New-Object System.Collections.Generic.List[string]
            $md.Add("## " + (Now) + " run $RunId - " + $Outcome.ToUpper() + " (mode=$Mode, scenario=$Scenario)")
            $md.Add("")
            $md.Add("| stage | attempt | ok | verdict | note |")
            $md.Add("|---|---|---|---|---|")
            foreach ($r in $rows) { $md.Add("| " + $r.stage + " | " + $r.attempt + " | " + $r.ok + " | " + $r.verdict + " | " + ([string]$r.note -replace '\|', '/') + " |") }
            $md.Add("")
            if ($Outcome -eq "stopped" -and $last) { $md.Add("- stopped at: " + $last.stage + " (attempt " + $last.attempt + ") - " + $last.note) }
            $md.Add("- AI calls: claude $aiC, codex $aiX")
            $md.Add("- raw: .pipeline/logs/run-$RunId.jsonl, .pipeline/reviews/")
            # Files that were already changed before the run (S0 record) - they are inside the commit too (PROJECT.md 18)
            $pre = Join-Path $logDir "run-$RunId-s0-gitstatus.txt"
            if (Test-Path -LiteralPath $pre) {
                $preLines = @(([System.IO.File]::ReadAllText($pre, $utf8)) -split "`n" | Where-Object { $_.Trim() })
                $shown = ($preLines | Select-Object -First 20 | ForEach-Object { $_.Trim() }) -join ", "
                $more = if ($preLines.Count -gt 20) { " ..." } else { "" }
                $md.Add("- changed before run (git status at S0): " + $preLines.Count + $(if ($preLines.Count -gt 0) { " - " + $shown + $more } else { "" }))
            }
            $doCommit = ($Mode -eq "real") -and ($Outcome -eq "pass")
            $branch = "run/$RunId"
            if ($doCommit) { $md.Add("- git: commit on branch $branch (hash in .pipeline/logs/run-$RunId.jsonl). Judge (7): git switch main, git merge --ff-only $branch, git push") }
            else { $md.Add("- git: no commit (commit only when mode=real and PASS)") }
            $md.Add("")
            $s6 = Join-Path $script:revDir "review-$RunId-s6.md"
            if (Test-Path -LiteralPath $s6) {
                $md.Add("### S6 second review")
                $md.Add("")
                $md.Add(([System.IO.File]::ReadAllText($s6, $utf8)).Trim())
                $md.Add("")
            }
            $resultFile = if ($Mode -ne "real") { Join-Path $fakeDir "RESULT.md" } else { Join-Path $root "RESULT.md" }
            $old = if (Test-Path -LiteralPath $resultFile) { [System.IO.File]::ReadAllText($resultFile, $utf8) } else { "" }
            [System.IO.File]::WriteAllText($resultFile, (($md -join "`n") + "`n" + $old), $utf8)   # newest on top (PROJECT.md 5)
            if (-not $doCommit) { Emit ($Outcome -eq "pass") $Outcome ("result written: " + $resultFile) }
            # One commit at the end, on a new branch, only for a real PASS run (PROJECT.md 18). The script runs git, not an AI.
            # The message goes through a UTF-8 file, not the command line (cmd.exe code page).
            $title = (Get-Content -LiteralPath (Join-Path $root "TASK.md") -Encoding UTF8 -TotalCount 1) -replace '^#+\s*', ''
            $msgFile = Join-Path $logDir "run-$RunId-commitmsg.txt"
            [System.IO.File]::WriteAllText($msgFile, ("pipeline run $RunId PASS`n`nTASK: $title`nResult: RESULT.md (top section)`n"), $utf8)
            $gitFail = ""
            $b1 = Invoke-Git ("checkout -b " + $branch) "end-gitbranch"
            if ($b1.code -ne 0) { $gitFail = "checkout -b failed: " + (OneLine $b1.err) }
            if (-not $gitFail) { $b2 = Invoke-Git "add -A" "end-gitadd"; if ($b2.code -ne 0) { $gitFail = "add failed: " + (OneLine $b2.err) } }
            if (-not $gitFail) { $b3 = Invoke-Git ("commit -F " + (Quote-Arg $msgFile)) "end-gitcommit"; if ($b3.code -ne 0) { $gitFail = "commit failed: " + (OneLine ($b3.out + $b3.err)) } }
            if ($gitFail) {
                # Say it in RESULT too, so the human does not read PASS without knowing the commit failed
                $md.Add("- git: FAILED - " + $gitFail)
                [System.IO.File]::WriteAllText($resultFile, (($md -join "`n") + "`n" + $old), $utf8)
                Emit $false $Outcome ("result written: $resultFile; git " + $gitFail)
            }
            $hash = OneLine (Invoke-Git "rev-parse --short HEAD" "end-githash").out
            Emit $true $Outcome ("result written: $resultFile; committed $hash on $branch")
        }
    }
} catch {
    Emit $false "" ("script error: " + $_.Exception.Message)
}
