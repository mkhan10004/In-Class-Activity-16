param([string]$YourName = 'YourName')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
$src = 'build/app/outputs/flutter-apk/app-release.apk'
$dest = "ICA16_A_$YourName.apk"
Copy-Item $src $dest -Force
Write-Host "Built $dest. Install-test it before submitting." -ForegroundColor Green
