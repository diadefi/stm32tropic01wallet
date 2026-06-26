param(
    [string]$Port = "COM3",
    [string]$Probe = ".\tools\wallet_probe_info.ps1"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 WALLET TRUTH-LABEL ASSERTIONS"
Write-Host "============================================================"
Write-Host "Port: $Port"

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Probe,
    "-Port", $Port
)

$output = @()
$code = 1

for ($attempt = 1; $attempt -le 3; $attempt++) {
    $output = & powershell.exe @args 2>&1
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        break
    }

    Write-Host "TRUTH_LABEL_PROBE_RETRY attempt=$attempt exit=$code"
    Start-Sleep -Seconds 2
}

$text = ($output | Out-String)

Write-Host $text

if ($code -ne 0) {
    throw "Probe failed before truth-label assertions"
}

$required = @(
    "UART_PROBE_PASS",
    "CURRENT_BITCOIN_KEY_MODEL=KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE",
    "CURRENT_DEV_KEY_ENABLED=0",
    "TROPIC_CURVE_SECP256K1=0",
    "BITCOIN_DIRECT_TROPIC_SIGNING=0",
    "BITCOIN_REQUIRED_CURVE=SECP256K1",
    "REAL_BITCOIN_STAGE=C9.6_TESTNET_SIGNING_ENABLE_ON_TEST_FUNDS_ONLY",
    "NETWORK_ALLOWED=REGTEST,TESTNET",
    "REAL_BITCOIN_SIGNING_ENABLED=1",
    "TESTNET_SIGNING_ENABLED=1",
    "MAINNET_SIGNING_ENABLED=0",
    "TESTNET_SIGNING_BUILD_FLAG=1",
    "TESTNET_SIGNING_ENABLE_BLOCKED=0",
    "TESTNET_SIGNING_ENABLE_ACTIVE=1"
)

foreach ($r in $required) {
    if ($text -notmatch [regex]::Escape($r)) {
        throw "TRUTH_LABEL_ASSERT_FAIL missing: $r"
    }
}

Write-Host ""
Write-Host "TRUTH_LABEL_ASSERT_PASS"



