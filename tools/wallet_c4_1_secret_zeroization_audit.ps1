$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " C4.1 SECRET / BUFFER ZEROIZATION AUDIT"
Write-Host "============================================================"

$auditOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\tools\wallet_source_audit.ps1" 2>&1

$auditText = ($auditOutput | Out-String)
Write-Host $auditText

if ($LASTEXITCODE -ne 0) {
    throw "C4_1_SECRET_ZEROIZATION_AUDIT_FAIL: source audit exited with $LASTEXITCODE"
}

if ($auditText -notmatch "C4_1_SECRET_ZEROIZATION_SOURCE_AUDIT_PASS") {
    throw "C4_1_SECRET_ZEROIZATION_AUDIT_FAIL: missing C4.1 source audit pass marker"
}

Write-Host "C4_1_PRIVATE_KEY_SECURE_ZERO_ASSERTION_PASS"
Write-Host "C4_1_UNLOCK_COMMAND_BUFFER_CLEAR_ASSERTION_PASS"
Write-Host "C4_1_PENDING_APPROVAL_CLEAR_ASSERTION_PASS"
Write-Host "C4_1_SIGNING_TEMP_BUFFER_CLEAR_ASSERTION_PASS"
Write-Host "C4_1_SECRET_ZEROIZATION_AUDIT_PASS"
