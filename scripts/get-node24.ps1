# Download latest Node 24 (win-x64 zip), verify SHA256 against nodejs.org SHASUMS256.txt,
# extract to C:\dev\tools\node24. Does not touch the system Node.
$ErrorActionPreference = "Stop"
$base = "https://nodejs.org/dist/latest-v24.x"
$tools = "C:\dev\tools"
$target = Join-Path $tools "node24"
if (Test-Path "$target\node.exe") { Write-Host "already exists: $target\node.exe"; & "$target\node.exe" -v; exit 0 }
if (Test-Path $target) { Write-Host "$target exists but has no node.exe. Check its contents first."; exit 1 }

$resp = Invoke-WebRequest "$base/SHASUMS256.txt" -UseBasicParsing
$sums = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { $resp.Content }
$line = ($sums -split "`n") | Where-Object { $_ -match 'node-v[\d\.]+-win-x64\.zip' } | Select-Object -First 1
$parts = $line.Trim() -split '\s+'
$expected = $parts[0].ToUpper(); $file = $parts[1]
Write-Host "file: $file"
Write-Host "expected SHA256: $expected"

$zip = Join-Path $env:TEMP $file
Invoke-WebRequest "$base/$file" -OutFile $zip -UseBasicParsing
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host "actual   SHA256: $actual"
if ($actual -ne $expected) { Write-Host "HASH MISMATCH - stopped. Zip left at $zip"; exit 1 }

New-Item -ItemType Directory -Force -Path $tools | Out-Null
Expand-Archive $zip -DestinationPath $tools
Rename-Item (Join-Path $tools ($file -replace '\.zip$','')) "node24"
Remove-Item $zip
Write-Host ("installed: " + (& "$target\node.exe" -v) + " at $target")
