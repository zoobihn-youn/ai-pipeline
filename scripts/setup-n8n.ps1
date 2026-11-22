# One-time: install n8n into C:\dev\tools\n8n using dedicated Node 24 (not global).
$node24 = "C:\dev\tools\node24"
$n8nDir = "C:\dev\tools\n8n"
if (-not (Test-Path "$node24\node.exe")) {
    Write-Host "node.exe not found in $node24"
    Write-Host "Download node-v24.x.x-win-x64.zip from https://nodejs.org/dist/latest-v24.x/ and extract so that $node24\node.exe exists."
    exit 1
}
$env:Path = "$node24;" + $env:Path   # this window only
Write-Host ("node: " + (node -v))
New-Item -ItemType Directory -Force -Path $n8nDir | Out-Null
npm install n8n --prefix $n8nDir
& "$n8nDir\node_modules\.bin\n8n.cmd" --version
