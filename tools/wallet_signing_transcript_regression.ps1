param(
    [string]$Port = "COM3",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 SIGNING TRANSCRIPT REGRESSION"
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
    "CONFIRMATION_TRANSCRIPT_BEGIN",
    "TRANSCRIPT_VERSION=C2.2_HOST_CONFIRMATION_TRANSCRIPT",
    "TRANSCRIPT_SOURCE=HOST_FROM_DEVICE_IDENTITY_AND_SIGN_COMMAND",
    "SECURE_DISPLAY=0",
    "NETWORK=REGTEST",
    "SPEND_FROM_DEVICE_ADDRESS=mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r",
    "SPEND_FROM_DEVICE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_TO_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PAY_SATS=60000",
    "CHANGE_SATS=30000",
    "FEE_SATS=10000",
    "PIN_SESSION_REQUESTED=1",
    "UNLOCK_SECRET_PRESENT=0",
    "HOST_EXPECTS_DEVICE_POLICY_CHECK=1",
    "CONFIRMATION_TRANSCRIPT_END",
    "CONFIRMATION_RESULT_BEGIN",
    "POLICY_DECISION=APPROVED_AND_SIGNED",
    "RAW_TX_PRESENT=1",
    "CONFIRMATION_RESULT_END",
    "HOST_TX_GENERATOR_PASS"
)

foreach ($needle in $required) {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "Transcript regression missing: $needle"
    }
}

Write-Host ""
Write-Host "SIGNING_TRANSCRIPT_REGRESSION_PASS"
$global:LASTEXITCODE = 0
