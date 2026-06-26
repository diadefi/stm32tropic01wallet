param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 45
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
    param(
        [uint32]$Before,
        [uint32]$After,
        [string]$Name
    )

    if ($After -ne $Before) {
        throw "$Name changed AUTH_COUNT: before=$Before after=$After"
    }

    Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After"
}

$validFields = @(
    "TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "VOUT=1",
    "INPUT_SATS=100000",
    "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PAY_SATS=60000",
    "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "CHANGE_SATS=30000"
)

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C8.0 REAL BITCOIN READINESS REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $Port
    $serial.BaudRate = $Baud
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.DataBits = 8
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.Handshake = [System.IO.Ports.Handshake]::None
    $serial.ReadTimeout = 200
    $serial.WriteTimeout = 2000
    $serial.NewLine = "`n"
    $serial.DtrEnable = $true
    $serial.RtsEnable = $true
    $serial.Open()

    Start-Sleep -Milliseconds 1500
    Drain-Stale -Serial $serial

    $authBefore = Get-AuthCount -Serial $serial

    Write-Host ""
    Write-Host "--- C8.0 VERSION READINESS SAFETY LABELS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "REAL_BITCOIN_STAGE=" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $version "REAL_BITCOIN_STAGE="
    Assert-Contains $version "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $version "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $version "MAINNET_SIGNING_ENABLED=0"
    Write-Host "C8_0_VERSION_STAGE_PASS"

    Write-Host ""
    Write-Host "--- C8.0 POLICYINFO READINESS SAFETY LABELS ---"
    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "REAL_BITCOIN_STAGE=" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $policy "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $policy "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $policy "MAINNET_SIGNING_ENABLED=0"
    Write-Host "C8_0_POLICYINFO_STAGE_PASS"

    Write-Host ""
    Write-Host "--- C8.0 REALINFO READINESS MANIFEST ---"
    $realinfo = Send-CommandLines -Serial $serial -Lines @("REALINFO") -RequiredPattern "REAL_BITCOIN_READINESS_VERSION=" -TimeoutSeconds $TimeoutSeconds
    Write-Host $realinfo
    Assert-Contains $realinfo "REAL_BITCOIN_READINESS=NOT_READY"
    Assert-Contains $realinfo "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $realinfo "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "MAINNET_SIGNING_ENABLED=0"
    Assert-Contains $realinfo "HOST_REAL_NETWORK_OVERRIDE_SUPPORTED=0"
    Assert-Contains $realinfo "REAL_SIGNING_ACTIVATION_REQUIRES_FIRMWARE_CHANGE=1"
    Assert-Contains $realinfo "BLOCKER_SECURE_DISPLAY=1"
    Assert-Contains $realinfo "BLOCKER_TROPIC_SECP256K1=1"
    Assert-Contains $realinfo "BLOCKER_REAL_NETWORK_POLICY=1"
    Assert-Contains $realinfo "BLOCKER_REAL_ADDRESS_DERIVATION=1"
    Assert-Contains $realinfo "BLOCKER_CHANGE_DERIVATION=1"
    Assert-Contains $realinfo "BLOCKER_REAL_FEE_POLICY=1"
    Assert-Contains $realinfo "C9_TARGET=TESTNET_SIGNING_ONLY_AFTER_EXPLICIT_USER_APPROVAL_AND_TEST_FUNDS"
    Write-Host "C8_0_REALINFO_MANIFEST_PASS"
    Write-Host "C8_0_REAL_SIGNING_DISABLED_PASS"
    Write-Host "C8_0_READINESS_BLOCKERS_PASS"

    foreach ($network in @("TESTNET", "MAINNET")) {
        Write-Host ""
        Write-Host "--- C8.0 $network STILL REJECTED ---"
        $check = Send-CommandLines -Serial $serial -Lines (@("NETWORK=$network") + $validFields + @("CHECK")) -RequiredPattern "ERR POLICY -42" -TimeoutSeconds $TimeoutSeconds
        Write-Host $check
        Assert-Contains $check "POLICY_DECISION=REJECTED"
        Assert-Contains $check "DEVICE_ERROR=ERR POLICY -42"
        Assert-Contains $check "SIGNATURE_PRODUCED=0"
        Assert-NoRawTx $check "C8_0_${network}_CHECK"
    }
    Write-Host "C8_0_REAL_NETWORK_STILL_REJECTS_PASS"

    $authAfter = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfter -Name "C8_0_READINESS"

    Write-Host ""
    Write-Host "C8_0_REAL_BITCOIN_READINESS_REGRESSION_PASS"
    exit 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}
