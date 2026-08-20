$ErrorActionPreference = "Stop"

$repo = "peero-app/peero"
$url = "https://github.com/$repo/releases/latest/download/peero-setup.exe"
$out = Join-Path $env:TEMP "peero-setup.exe"

Write-Host "Downloading Peero..."
Invoke-WebRequest -Uri $url -OutFile $out

Write-Host "Installing..."
Start-Process -FilePath $out -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES" -Wait

Write-Host "Peero installed."
