# Judge (stage 7) for one pipeline run: approve = merge run/<RunId> into main, push, delete the branch;
# reject = save the branch as a patch, go back to main, delete the branch. (PROJECT.md 21, item A)
# Called by the n8n "judge" workflow. Same output rule as stage.ps1: always exit 0, the last stdout line is JSON with "ok".
# ASCII only (Windows PowerShell 5.1, STANDARD.md 3). Project folder = PROJECT_ROOT set by scripts\start-n8n.ps1.
param([string]$RunId = "", [string]$Decision = "", [string]$ProjectRoot = $env:PROJECT_ROOT)

$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:steps = New-Object System.Collections.Generic.List[string]
$script:logDir = $null

function Finish([bool]$ok, [string]$note) {
    $o = [ordered]@{ tool = "judge"; run = $RunId; decision = $Decision; ok = $ok; note = $note
                     steps = @($script:steps); at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz") }
    $line = $o | ConvertTo-Json -Compress
    if ($script:logDir) { try { [System.IO.File]::WriteAllText((Join-Path $script:logDir "judge-$RunId.json"), $line, $utf8) } catch {} }
    Write-Output $line
    exit 0
}

# git through cmd.exe (git.exe or git.cmd), no prompts, closed stdin, 2-minute limit.
function Invoke-GitCmd([string]$gitArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = '/d /s /c "git ' + $gitArgs + '"'
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outT = $p.StandardOutput.ReadToEndAsync()
    $errT = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {}; return @{ code = -1; out = ""; err = "timeout after 120s" } }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = $outT.Result; err = $errT.Result }
}
function OneLine([string]$s) { return (($s -replace "\s+", " ").Trim()) }
function Step([string]$name, $r) {
    $script:steps.Add($name + ": exit " + $r.code + $(if ($r.code -ne 0) { " - " + (OneLine ($r.out + " " + $r.err)) } else { "" }))
}

# ---- Input checks (the n8n workflow checks the same; this is the second check) ----
if ($RunId -notmatch '^\d{8}-\d{6}$') { Finish $false "RunId must look like 20261123-151448" }
if (@("approve", "reject") -notcontains $Decision) { Finish $false "Decision must be approve or reject" }
if (-not $ProjectRoot -or -not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) { Finish $false "PROJECT_ROOT not set or not a git folder: $ProjectRoot" }
$script:logDir = Join-Path $ProjectRoot ".pipeline\logs"
if (-not (Test-Path -LiteralPath $script:logDir)) { New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null }

$branch = "run/$RunId"
$r = Invoke-GitCmd "rev-parse --verify --quiet refs/heads/$branch"; Step "branch exists" $r
if ($r.code -ne 0) { Finish $false "branch $branch not found (already judged, or the run did not commit)" }
$r = Invoke-GitCmd "rev-parse --abbrev-ref HEAD"; Step "current branch" $r
$script:steps.Add("was on: " + (OneLine $r.out))

if ($Decision -eq "reject") {
    # Keep a copy first: the run commit can also hold files changed before the run (PROJECT.md 18).
    $rejDir = Join-Path $ProjectRoot ".pipeline\rejected"
    if (-not (Test-Path -LiteralPath $rejDir)) { New-Item -ItemType Directory -Path $rejDir -Force | Out-Null }
    $patchFile = Join-Path $rejDir "$RunId.patch"
    $r = Invoke-GitCmd "format-patch --stdout main..$branch"; Step "save patch" $r
    if ($r.code -ne 0) { Finish $false "could not save the patch; nothing deleted" }
    [System.IO.File]::WriteAllText($patchFile, $r.out, $utf8)
    $r = Invoke-GitCmd "switch main"; Step "switch main" $r
    if ($r.code -ne 0) { Finish $false "could not switch to main (uncommitted changes in the way?); branch kept" }
    $r = Invoke-GitCmd "branch -D $branch"; Step "delete branch" $r
    if ($r.code -ne 0) { Finish $false "on main, but could not delete $branch" }
    Finish $true "rejected: $branch deleted, patch saved to .pipeline/rejected/$RunId.patch"
}

# approve
$r = Invoke-GitCmd "switch main"; Step "switch main" $r
if ($r.code -ne 0) { Finish $false "could not switch to main (uncommitted changes in the way?); nothing merged" }
$r = Invoke-GitCmd "merge --ff-only $branch"; Step "merge --ff-only" $r
if ($r.code -ne 0) { Finish $false "merge failed (main moved after the run?); branch kept" }
$h = OneLine (Invoke-GitCmd "rev-parse --short HEAD").out
$script:steps.Add("main now: $h")
$r = Invoke-GitCmd "push origin main"; Step "push" $r
if ($r.code -ne 0) { Finish $false "merged locally (main = $h) but push failed; branch kept" }
$r = Invoke-GitCmd "branch -d $branch"; Step "delete branch" $r
if ($r.code -ne 0) { Finish $false "merged and pushed (main = $h), but could not delete $branch" }
Finish $true "approved: merged and pushed (main = $h), $branch deleted"
