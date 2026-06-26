param(
    [string]$Port = "COM3",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 C2.7 TRANSCRIPT/CHECK/SIGN CONSISTENCY REGRESSION"
Write-Host "============================================================"
Write-Host "Port: $Port"

$output = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Generator `
    -Port $Port `
    -TxidLe "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632" `
    -Vout 1 `
    -InputSats 100000 `
    -PaySats 60000 `
    -ChangeSats 30000 `
    -TimeoutSeconds 180 `
    2>&1

$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }

if ($code -ne 0) {
    throw "Generator failed with exit code $code"
}

$text = ($output | Out-String)

$required = @(
    "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_BEGIN",
    "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_PASS",
    "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_END",
    "HOST_TX_GENERATOR_PASS",
    "RAW_TX_PRESENT=1"
)

foreach ($needle in $required) {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "C2.7 regression missing: $needle"
    }
}

$fields = @(
    "NETWORK",
    "TXID_LE",
    "VOUT",
    "INPUT_SATS",
    "PREV_SCRIPT",
    "PAY_SCRIPT",
    "PAY_SATS",
    "CHANGE_SCRIPT",
    "CHANGE_SATS",
    "FEE_SATS"
)

foreach ($field in $fields) {
    if ($text -notmatch "C2_7_FIELD_MATCH NAME=$([regex]::Escape($field)) ") {
        throw "C2.7 regression missing field match for $field"
    }
}

Write-Host ""
Write-Host "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_REGRESSION_PASS"
$global:LASTEXITCODE = 0
