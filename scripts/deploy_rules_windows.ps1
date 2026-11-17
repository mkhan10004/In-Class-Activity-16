param([Parameter(Mandatory=$true)][string]$ProjectId)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
firebase deploy --only firestore:rules --project $ProjectId
if ($LASTEXITCODE -ne 0) { throw 'Rule deployment failed. Check login, project, and Firebase CLI.' }
Write-Host 'Confirm deployed rules in Firebase Console > Firestore > Rules.'
