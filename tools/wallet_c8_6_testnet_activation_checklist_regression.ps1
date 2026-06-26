param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45,
    [string]$Generator = ".\tools\wallet_generate_tx_command.ps1"
)

$ErrorActionPreference = "Stop"

function Read-Available {
    param([System.IO.Ports.SerialPort]$Serial)
    $s = ""
    try {
        while ($Serial.BytesToRead -gt 0) {
            $s += $Serial.ReadExisting()
            Start-Sleep -Milliseconds 20
        }
    } catch {
    }
    return $s
}

function Drain-Stale {
    param([System.IO.Ports.SerialPort]$Serial)
    Start-Sleep -Milliseconds 250
    $null = Read-Available -Serial $Serial
    $Serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $null = Read-Available -Serial $Serial
    $Serial.DiscardInBuffer()
}

function Send-CommandLines {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string[]]$Lines,
        [string]$RequiredPattern,
        [int]$TimeoutSeconds
    )

    Drain-Stale -Serial $Serial
    foreach ($line in $Lines) {
        Write-Host ">> $line"
        $Serial.WriteLine($line)
        Start-Sleep -Milliseconds 100
    }

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match $RequiredPattern) -and ($buf -match "(?s)READY.*>\s*$")) {
            return $buf
        }
        Start-Sleep -Milliseconds 50
    }

    Write-Host ""
    Write-Host "--- TIMEOUT BUFFER ---"
    Write-Host $buf
    throw "Timeout waiting for required response pattern: $RequiredPattern"
}

function Assert-Contains {
    param([string]$Text, [string]$Needle)
    if ($Text -notmatch [regex]::Escape($Needle)) {
        Write-Host ""
        Write-Host "--- TEXT THAT FAILED ASSERTION ---"
        Write-Host $Text
        throw "Missing expected text: $Needle"
    }
}

function Assert-NoRawTx {
    param([string]$Text, [string]$Name)
    if ($Text -match "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name unexpectedly produced RAW_TX"
    }
}

function Get-AuthCountFromText {
    param([string]$Text)
    $m = [regex]::Match($Text, "(?m)^AUTH_COUNT=(\d+)\s*$")
    if (-not $m.Success) {
        Write-Host ""
        Write-Host "--- TEXT MISSING AUTH_COUNT ---"
        Write-Host $Text
        throw "AUTH_COUNT missing"
    }
    return [uint32]$m.Groups[1].Value
}

function Get-AuthCount {
    param([System.IO.Ports.SerialPort]$Serial)
    $seinfo = Send-CommandLines -Serial $Serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds 15
    Write-Host $seinfo
    return Get-AuthCountFromText $seinfo
}

function Assert-AuthUnchanged {
    param([uint32]$Before, [uint32]$After, [string]$Name)
    if ($After -ne $Before) {
        throw "$Name changed AUTH_COUNT: before=$Before after=$After"
    }
    Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After"
}

function Open-WalletSerial {
    param([string]$Port, [int]$Baud)
    $s = New-Object System.IO.Ports.SerialPort
    $s.PortName = $Port
    $s.BaudRate = $Baud
    $s.Parity = [System.IO.Ports.Parity]::None
    $s.DataBits = 8
    $s.StopBits = [System.IO.Ports.StopBits]::One
    $s.Handshake = [System.IO.Ports.Handshake]::None
    $s.ReadTimeout = 200
    $s.WriteTimeout = 2000
    $s.NewLine = "`n"
    $s.DtrEnable = $true
    $s.RtsEnable = $true
    $s.Open()
    Start-Sleep -Milliseconds 1500
    Drain-Stale -Serial $s
    return $s
}

function Close-WalletSerial {
    param([System.IO.Ports.SerialPort]$Serial)
    if ($Serial -ne $null) {
        if ($Serial.IsOpen) { $Serial.Close() }
        $Serial.Dispose()
    }
}

function Invoke-HostTestnetActivationReject {
    Write-Host ""
    Write-Host "--- C8.6 HOST TESTNET ACTIVATION CHECKLIST REFUSES SIGN ---"

    $baseArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", "TESTNET",
        "-CommandFormat", "PsbtLike",
        "-InputCount", "2",
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-TxidLe1", "19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a633",
        "-Vout1", "0",
        "-InputSats1", "50000",
        "-PaySats", "70000",
        "-ChangeSats", "60000",
        "-ChangeDerivation", "mvp-static-change/0",
        "-OmitUnlockPin"
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @baseArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output | Out-String)

    if ($code -eq 0) {
        throw "C8.6 host activation checklist failed: generator unexpectedly exited 0"
    }

    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined "C8_6_HOST_TESTNET_ACTIVATION"

    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or
        $joined -match "(?m)^>> SIGN\r?$") {
        throw "C8.6 host activation checklist failed: SIGN command was sent"
    }

    Write-Host "C8_6_HOST_TESTNET_ACTIVATION_NO_SIGN_PASS"
    $global:LASTEXITCODE = 0
}

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.6 TESTNET ACTIVATION CHECKLIST REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authBefore = Get-AuthCount -Serial $serial

    Write-Host ""
    Write-Host "--- C8.6 REALINFO TESTNET ACTIVATION CHECKLIST ---"
    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "TESTNET_ACTIVATION_VERSION=C8.6_TESTNET_ACTIVATION_CHECKLIST_V1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_STAGE="
    Assert-Contains $realinfo "TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_READY=0"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_STATUS=BLOCKED"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_MODE=CHECKLIST_ONLY_NO_SIGNING"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_COMPILE_TIME_FLAG=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_FLAG_STATE=0"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_TEST_FUNDS_ONLY=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_USER_CONFIRMATION=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_PHYSICAL_CONFIRM=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_REQUIRES_MAINNET_LOCKOUT=1"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_BLOCKER_COUNT=7"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_REGTEST_REGRESSIONS=PASS"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_TESTNET_POLICY_FIXTURES=PASS"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_TESTNET_DRY_RUN_PSBT=PASS"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_MAINNET_LOCKOUT=PASS"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_REAL_ADDRESS_DERIVATION=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_CHANGE_DERIVATION=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_REAL_FEE_POLICY=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_SECURE_DISPLAY=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_TROPIC_SECP256K1=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_TESTNET_SIGNING_FLAG=BLOCKED"
    Assert-Contains $realinfo "TESTNET_CHECKLIST_ITEM_TESTNET_SIGNING_REGRESSION=BLOCKED"
    Assert-Contains $realinfo "TESTNET_ACTIVATION_OUTPUT=CHECKLIST_ONLY_NO_DEVICE_SIGNATURE"
    Assert-Contains $realinfo "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "NEXT_SAFE_STAGE="
    Write-Host "C8_6_REALINFO_ACTIVATION_CHECKLIST_PASS"

    Write-Host ""
    Write-Host "--- C8.6 VERSION/POLICY ACTIVATION LABELS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "REAL_BITCOIN_STAGE="
    Assert-Contains $version "TESTNET_ACTIVATION_SIGNING_ENABLED=0"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "TESTNET_ACTIVATION_CHECKLIST_SUPPORTED=1" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "REAL_BITCOIN_STAGE="
    Assert-Contains $policy "TESTNET_ACTIVATION_SIGNING_ENABLED=0"
    Write-Host "C8_6_VERSION_POLICY_ACTIVATION_LABELS_PASS"

    Write-Host ""
    Write-Host "TESTNET_ACTIVATION_CHECKLIST_BEGIN"
    Write-Host "TESTNET_ACTIVATION_VERSION=C8.6_TESTNET_ACTIVATION_CHECKLIST_V1"
    Write-Host "TESTNET_ACTIVATION_READY=0"
    Write-Host "TESTNET_ACTIVATION_STATUS=BLOCKED"
    Write-Host "PASS_ITEMS=REGTEST_REGRESSIONS,TESTNET_POLICY_FIXTURES,TESTNET_DRY_RUN_PSBT,MAINNET_LOCKOUT"
    Write-Host "BLOCKED_ITEMS=REAL_ADDRESS_DERIVATION,CHANGE_DERIVATION,REAL_FEE_POLICY,SECURE_DISPLAY,TROPIC_SECP256K1,TESTNET_SIGNING_FLAG,TESTNET_SIGNING_REGRESSION"
    Write-Host "SIGNING_ENABLED=0"
    Write-Host "TESTNET_ACTIVATION_CHECKLIST_END"
    Write-Host "C8_6_HOST_TESTNET_ACTIVATION_CHECKLIST_TRANSCRIPT_PASS"

    $authAfterManifest = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterManifest -Name "C8_6_ACTIVATION_CHECKLIST_MANIFEST"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostTestnetActivationReject

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterManifest -After $authAfterHost -Name "C8_6_HOST_TESTNET_ACTIVATION"

    Write-Host ""
    Write-Host "C8_6_TESTNET_ACTIVATION_CHECKLIST_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
