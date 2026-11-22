# Start n8n with Node 24 and Execute Command enabled (this window only).
# PROJECT_ROOT = the project folder the pipeline works on (PROJECT.md 11-4). Change folder = restart n8n.
param([string]$ProjectRoot = "C:\dev\ai-pipeline")
$node24 = "C:\dev\tools\node24"
$n8n = "C:\dev\tools\n8n\node_modules\.bin\n8n.cmd"
if (-not (Test-Path $n8n)) { Write-Host "n8n not installed. Run scripts\setup-n8n.ps1 first."; exit 1 }
$env:Path = "$node24;" + $env:Path
$env:NODES_EXCLUDE = '["n8n-nodes-base.localFileTrigger"]'
$env:PROJECT_ROOT = $ProjectRoot
$env:GENERIC_TIMEZONE = "Asia/Seoul"   # n8n $now / runId in Korean time (PROJECT.md 16)
Write-Host ("node: " + (node -v) + " / NODES_EXCLUDE=" + $env:NODES_EXCLUDE + " / PROJECT_ROOT=" + $env:PROJECT_ROOT + " / TZ=" + $env:GENERIC_TIMEZONE)
& $n8n start
