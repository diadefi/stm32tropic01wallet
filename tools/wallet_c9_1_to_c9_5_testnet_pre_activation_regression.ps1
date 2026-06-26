param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

function Read-Available { param([System.IO.Ports.SerialPort]$Serial) $s = ""; try { while ($Serial.BytesToRead -gt 0) { $s += $Serial.ReadExisting(); Start-Sleep -Milliseconds 20 } } catch {}; return $s }
function Drain-Stale { param([System.IO.Ports.SerialPort]$Serial) Start-Sleep -Milliseconds 250; $null = Read-Available -Serial $Serial; $Serial.DiscardInBuffer(); Start-Sleep -Milliseconds 100; $null = Read-Available -Serial $Serial; $Serial.DiscardInBuffer() }
function Send-CommandLines {
    param([System.IO.Ports.SerialPort]$Serial, [string[]]$Lines, [string]$RequiredPattern, [int]$TimeoutSeconds)
    Drain-Stale -Serial $Serial
    foreach ($line in $Lines) { Write-Host ">> $line"; $Serial.WriteLine($line); Start-Sleep -Milliseconds 100 }
    $buf = ""; $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) { $buf += Read-Available -Serial $Serial; if (($buf -match $RequiredPattern) -and ($buf -match "(?s)READY.*>\s*$")) { return $buf }; Start-Sleep -Milliseconds 50 }
    Write-Host ""; Write-Host "--- TIMEOUT BUFFER ---"; Write-Host $buf; throw "Timeout waiting for required response pattern: $RequiredPattern"
}
function Assert-Contains { param([string]$Text, [string]$Needle) if ($Text -notmatch [regex]::Escape($Needle)) { Write-Host ""; Write-Host "--- TEXT THAT FAILED ASSERTION ---"; Write-Host $Text; throw "Missing expected text: $Needle" } }
function Assert-NoRawTx { param([string]$Text, [string]$Name) if ($Text -match "RAW_TX=[0-9a-fA-F]+") { throw "$Name unexpectedly produced RAW_TX" } }
function Get-AuthCountFromText { param([string]$Text) $m = [regex]::Match($Text, "(?m)^AUTH_COUNT=(\d+)\s*$"); if (-not $m.Success) { Write-Host $Text; throw "AUTH_COUNT missing" }; return [uint32]$m.Groups[1].Value }
function Get-AuthCount { param([System.IO.Ports.SerialPort]$Serial) $seinfo = Send-CommandLines -Serial $Serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds 15; Write-Host $seinfo; return Get-AuthCountFromText $seinfo }
function Assert-AuthUnchanged { param([uint32]$Before, [uint32]$After, [string]$Name) if ($After -ne $Before) { throw "$Name changed AUTH_COUNT: before=$Before after=$After" }; Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After" }
function Open-WalletSerial {
    param([string]$Port, [int]$Baud)
    $s = New-Object System.IO.Ports.SerialPort
    $s.PortName = $Port; $s.BaudRate = $Baud; $s.Parity = [System.IO.Ports.Parity]::None; $s.DataBits = 8; $s.StopBits = [System.IO.Ports.StopBits]::One; $s.Handshake = [System.IO.Ports.Handshake]::None; $s.ReadTimeout = 200; $s.WriteTimeout = 2000; $s.NewLine = "`n"; $s.DtrEnable = $true; $s.RtsEnable = $true
    $s.Open(); Start-Sleep -Milliseconds 1500; Drain-Stale -Serial $s; return $s
}
function Close-WalletSerial { param([System.IO.Ports.SerialPort]$Serial) if ($Serial -ne $null) { if ($Serial.IsOpen) { $Serial.Close() }; $Serial.Dispose() } }

function Invoke-HostTestnetPreActivationReject {
    Write-Host ""
    Write-Host "--- C9.1-C9.5 HOST TESTNET PRE-ACTIVATION STILL REFUSES SIGN ---"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-CommandFormat", "PsbtLike",
        "-InputCount", "1",
        "-TxidLe", "19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
        "-ChangeDerivation", "mvp-static-change/0",
        "-OmitUnlockPin"
    )
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = & powershell.exe @args 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $oldErrorActionPreference }
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output | Out-String)
    if ($code -eq 0) { throw "C9.1-C9.5 host testnet pre-activation unexpectedly exited 0" }
    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C9_1_TO_C9_5_HOST_TESTNET_PRE_ACTIVATION"
    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or $joined -match "(?m)^>> SIGN\r?$") { throw "C9.1-C9.5 host testnet pre-activation sent SIGN" }
    Write-Host "C9_1_TO_C9_5_HOST_TESTNET_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C9.1-C9.5 TESTNET PRE-ACTIVATION REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_SIGNING_ACTIVATION_DRY_RUN_VERSION=C9.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE=C9.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN"

    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_VERSION=C9.1_TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_V1"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_NETWORK=TESTNET"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_MODEL=BIP84_TESTNET_P2WPKH_ACCOUNT"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_ACCOUNT_PATH=m/84h/1h/0h"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_RECEIVE_PATH=m/84h/1h/0h/0/{index}"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_CHANGE_PATH=m/84h/1h/0h/1/{index}"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_ADDRESS_FORMAT=tb1q_P2WPKH"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_DEVICE_DERIVES_KEYS=0"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_HOST_DERIVED_METADATA_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_XPUB_EXPORT=BLOCKED"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_DERIVATION_IMPLEMENTATION_OUTPUT=FOUNDATION_ONLY_NO_DEVICE_SIGNATURE"
    Write-Host "C9_1_REALINFO_DERIVATION_IMPLEMENTATION_FOUNDATION_PASS"

    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_VERSION=C9.2_TESTNET_CHANGE_DERIVATION_ENFORCEMENT_V1"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_PATH=m/84h/1h/0h/1/{index}"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_METADATA_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SCRIPT_MATCH_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SIGNING_ENABLED=0"
    Write-Host "C9_2_REALINFO_CHANGE_DERIVATION_ENFORCEMENT_PASS"

    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_VERSION=C9.3_TESTNET_REAL_FEE_POLICY_V1"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_MODEL=FEE_RATE_AND_ABSOLUTE_CAP_DRAFT"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_MIN_SATS=546"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_MAX_SATS=20000"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_MIN_SATS_PER_KVB=1000"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_MAX_SATS_PER_KVB=100000"
    Assert-Contains $realinfo "TESTNET_REAL_FEE_POLICY_SIGNING_ENABLED=0"
    Write-Host "C9_3_REALINFO_REAL_FEE_POLICY_PASS"

    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_VERSION=C9.4_TESTNET_UNSIGNED_TX_VALIDATION_V1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_FORMAT=PSBT_LIKE_TEXT_V1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_TESTNET=1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_DERIVED_INPUTS=1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_DERIVED_CHANGE=1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_REQUIRES_FEE_POLICY=1"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_DEVICE_SIGNATURE=0"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_RAW_TX=0"
    Assert-Contains $realinfo "TESTNET_UNSIGNED_TX_VALIDATION_BROADCAST=0"
    Write-Host "C9_4_REALINFO_UNSIGNED_TX_VALIDATION_PASS"

    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_VERSION=C9.5_GUARDED_TESTNET_SIGNING_ACTIVATION_DRY_RUN_V1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_STATUS=BLOCKED_BY_BUILD_FLAG_AND_REAL_DERIVATION"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_ALL_RUNTIME_GATES_REQUIRED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_PROVES_NO_SIGN_WHEN_FLAG_OFF=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ACTIVATION_DRY_RUN_RAW_TX=0"
    Write-Host "C9_5_REALINFO_SIGNING_ACTIVATION_DRY_RUN_PASS"

    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BLOCKED=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BLOCKED_VERSION=C9.6_TESTNET_SIGNING_ENABLE_BLOCKED_V1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_BLOCK_REASON=BUILD_FLAG_OFF_REAL_TEST_FUNDS_REQUIRED_PHYSICAL_CONFIRM_REQUIRED"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_REQUIRES_USER_PROVIDED_TEST_FUNDS=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_REQUIRES_PHYSICAL_CONFIRM=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_REQUIRES_EXPLICIT_REBUILD=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_MAINNET_LOCKOUT=1"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLE_ACTUAL_SIGNING_ENABLED=0"
    Write-Host "C9_6_TESTNET_SIGNING_ENABLE_BLOCKED_PASS"

    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    foreach ($text in @($version, $policy)) {
        Assert-Contains $text "TESTNET_DERIVATION_IMPLEMENTATION_FOUNDATION_SUPPORTED=1"
        Assert-Contains $text "TESTNET_CHANGE_DERIVATION_ENFORCEMENT_SUPPORTED=1"
        Assert-Contains $text "TESTNET_REAL_FEE_POLICY_SUPPORTED=1"
        Assert-Contains $text "TESTNET_UNSIGNED_TX_VALIDATION_SUPPORTED=1"
        Assert-Contains $text "TESTNET_SIGNING_ACTIVATION_DRY_RUN_SUPPORTED=1"
        Assert-Contains $text "TESTNET_SIGNING_ENABLE_BLOCKED=1"
    }
    Write-Host "C9_1_TO_C9_5_VERSION_POLICY_LABELS_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetPreActivationReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C9_1_TO_C9_5_HOST_TESTNET_PRE_ACTIVATION"

    Write-Host ""
    Write-Host "C9_1_TO_C9_5_TESTNET_PRE_ACTIVATION_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
