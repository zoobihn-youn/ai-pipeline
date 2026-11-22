# ai-pipeline environment check (PROJECT.md section 7, items 1-2)
# No AI model calls: version/path checks only.
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root ".pipeline\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("env-check-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")

function Check($label, $cmd) {
    "=== $label ===" | Tee-Object -FilePath $log -Append
    try {
        $out = Invoke-Expression $cmd 2>&1 | Out-String
        $out.Trim() | Tee-Object -FilePath $log -Append
    } catch {
        ("FAILED: " + $_.Exception.Message) | Tee-Object -FilePath $log -Append
    }
}

("checked at: " + (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")) | Tee-Object -FilePath $log -Append
Check "node version (need 20.19 - 24.x)" "node -v"
Check "where claude" "where.exe claude"
Check "where codex" "where.exe codex"
Check "claude version" "claude --version"
Check "codex version" "codex --version"
Check "where n8n" "where.exe n8n"
Check "n8n version" "n8n --version"
Check "NODES_EXCLUDE (this window)" "`$env:NODES_EXCLUDE"
"AI calls: claude 0, codex 0" | Tee-Object -FilePath $log -Append
"saved: $log"
