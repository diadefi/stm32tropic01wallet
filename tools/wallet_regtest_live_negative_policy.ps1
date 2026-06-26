param(
    [string]$Port = "COM3",
    [string]$BitcoinCli = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe",
    [string]$Wallet = "stm32-host-live",
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Continue"

function Invoke-ExpectedPolicyReject {
    param(
        [string]$Name,
        [string]$ExpectedError,
        [string[]]$ExtraArgs
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "NEGATIVE_TEST $Name"
    Write-Host "EXPECT $ExpectedError"
    Write-Host "============================================================"

    $baseArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000"
    )

    $output = & powershell.exe @baseArgs @ExtraArgs 2>&1
    $code = $LASTEXITCODE

    $output | ForEach-Object { Write-Host $_ }

    $joined = ($output | Out-String)

    if ($joined -notmatch [regex]::Escape($ExpectedError)) {
        throw "$Name failed: expected $ExpectedError but did not see it"
    }

    if ($joined -notmatch "HOST_TX_GENERATOR_FAIL") {
        throw "$Name failed: expected host generator failure marker"
    }

    if ($joined -notmatch "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK") {
        throw "$Name failed: expected rejection during device CHECK"
    }

    if ($joined -notmatch "RAW_TX_PRESENT=0") {
        throw "$Name failed: expected RAW_TX_PRESENT=0"
    }

    if ($joined -notmatch "SIGN_SENT=0") {
        throw "$Name failed: expected SIGN_SENT=0"
    }

    if ($joined -notmatch "NO_SIGN_SENT") {
        throw "$Name failed: expected NO_SIGN_SENT marker"
    }

    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---") {
        throw "$Name failed: SIGN send section was reached"
    }

    if ($joined -match "(?m)^>> SIGN\r?$") {
        throw "$Name failed: SIGN command was sent"
    }

    if ($joined -match "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name failed: RAW_TX appeared"
    }

    Write-Host "C2_9_NO_SIGN_AFTER_FAILED_CHECK_CONFIRMED"
    Write-Host ""
    Write-Host "PASS $Name -> $ExpectedError"

    # The generator is supposed to fail for negative tests.
    # Clear stale native exit code so this regression can pass.
    $global:LASTEXITCODE = 0
}

Write-Host ""
Write-Host "============================================================"
Write-Host " STM32 LIVE NEGATIVE POLICY REGRESSION"
Write-Host "============================================================"
Write-Host "Port: $Port"
Write-Host "BitcoinCli: $BitcoinCli"
Write-Host "Wallet: $Wallet"

Invoke-ExpectedPolicyReject `
    -Name "NETWORK_NOT_REGTEST_REJECTED" `
    -ExpectedError "ERR POLICY -42" `
    -ExtraArgs @("-Network", "MAINNET", "-PaySats", "60000", "-ChangeSats", "30000")

Invoke-ExpectedPolicyReject `
    -Name "FEE_TOO_HIGH_REJECTED" `
    -ExpectedError "ERR POLICY -35" `
    -ExtraArgs @("-PaySats", "60000", "-ChangeSats", "10000")

Invoke-ExpectedPolicyReject `
    -Name "PAY_TOO_HIGH_REJECTED" `
    -ExpectedError "ERR POLICY -41" `
    -ExtraArgs @("-PaySats", "80000", "-ChangeSats", "10000")

Invoke-ExpectedPolicyReject `
    -Name "PAY_NOT_ALLOWED_REJECTED" `
    -ExpectedError "ERR POLICY -38" `
    -ExtraArgs @("-PayScript", "76a914111111111111111111111111111111111111111188ac", "-PaySats", "60000", "-ChangeSats", "30000")

Invoke-ExpectedPolicyReject `
    -Name "CHANGE_NOT_OWN_REJECTED" `
    -ExpectedError "ERR POLICY -39" `
    -ExtraArgs @("-ChangeScript", "76a914222222222222222222222222222222222222222288ac", "-PaySats", "60000", "-ChangeSats", "30000")

Invoke-ExpectedPolicyReject `
    -Name "INPUT_NOT_OWN_REJECTED" `
    -ExpectedError "ERR POLICY -40" `
    -ExtraArgs @("-PrevScript", "76a914333333333333333333333333333333333333333388ac", "-PaySats", "60000", "-ChangeSats", "30000")

Write-Host ""
Write-Host "C2_9_NO_SIGN_AFTER_FAILED_CHECK_REGRESSION_PASS"
Write-Host "LIVE_NEGATIVE_POLICY_REGRESSION_PASS"
$global:LASTEXITCODE = 0

