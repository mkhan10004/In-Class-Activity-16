$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
Write-Host 'ICA16 A Undergraduate — Windows setup' -ForegroundColor Cyan
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK is not on PATH. Install it, then run flutter doctor.'
}
flutter create . --platforms=android --project-name=ica16_quiz
# Flutter creates the platform-generated Gradle wrapper and metadata.
# Existing project source and its Internet-enabled manifest are preserved by default.
if ($LASTEXITCODE -ne 0) { throw 'Flutter project generation failed.' }
# Ensure the release manifest retains Internet access even if Flutter created it.
$manifestPath = 'android/app/src/main/AndroidManifest.xml'
$manifestText = Get-Content $manifestPath -Raw
if ($manifestText -notmatch 'android.permission.INTERNET') {
  $permission = '    <uses-permission android:name="android.permission.INTERNET" />'
  $manifestText = $manifestText.Replace('<application', "$permission`r`n    <application")
  Set-Content -Path $manifestPath -Value $manifestText -Encoding UTF8
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
if (-not (Get-Command flutterfire -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing FlutterFire CLI...' -ForegroundColor Yellow
  dart pub global activate flutterfire_cli
  if ($LASTEXITCODE -ne 0) { throw 'FlutterFire CLI installation failed.' }
  Write-Host 'If flutterfire is still unavailable, add the Dart Pub Cache bin directory to PATH.' -ForegroundColor Yellow
}
Write-Host 'Next: enable Email/Password and Firestore in YOUR Firebase Console, then select the correct project.' -ForegroundColor Yellow
if (Get-Command flutterfire -ErrorAction SilentlyContinue) {
  flutterfire configure --platforms=android --out=lib/firebase_options.dart
} else {
  dart pub global run flutterfire_cli:flutterfire configure --platforms=android --out=lib/firebase_options.dart
}
if ($LASTEXITCODE -ne 0) { throw 'FlutterFire configuration failed. Re-run flutterfire configure after logging in.' }
Write-Host 'Now run firebase deploy --only firestore:rules --project YOUR_FIREBASE_PROJECT_ID and flutter run.' -ForegroundColor Green
