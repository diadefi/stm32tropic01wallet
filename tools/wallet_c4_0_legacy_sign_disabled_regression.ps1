param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 30
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
        Start-Sleep -Milliseconds 80
    }

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match $RequiredPattern) -and ($buf -match "READY")) {
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

function Get-AuthCount {
    param([string]$Text)
    $m = [regex]::Match($Text, "AUTH_COUNT=(\d+)")
    if (-not $m.Success) { throw "AUTH_COUNT missing" }
    return [int]$m.Groups[1].Value
}

$privkeySign = @(
    "NETWORK=REGTEST",
    "TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "VOUT=1",
    "INPUT_SATS=100000",
    "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PAY_SATS=60000",
    "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "CHANGE_SATS=30000",
    "UNLOCK_SECRET=mvp-regtest-unlock",
    "PRIVKEY=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "SIGN"
)

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C4.0 LEGACY SIGN DISABLED REGRESSION"
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

    Write-Host ""
    Write-Host "--- C4.0 POLICYINFO REPORTS LEGACY DISABLED ---"
    $policyInfo = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "ERR_LEGACY_SIGN_DISABLED=-60" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policyInfo
    Assert-Contains $policyInfo "ERR_LEGACY_SIGN_DISABLED=-60"
    Write-Host "C4_0_POLICYINFO_LEGACY_DISABLED_PASS"

    Write-Host ""
    Write-Host "--- C4.0 UART HOST PRIVKEY REJECTS BEFORE AUTH ---"
    $before = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBefore = Get-AuthCount $before
    $reject = Send-CommandLines -Serial $serial -Lines $privkeySign -RequiredPattern "ERR KEYPOLICY -21" -TimeoutSeconds $TimeoutSeconds
    Write-Host $reject
    Assert-Contains $reject "ERR KEYPOLICY -21"
    Assert-NoRawTx $reject "HOST_PRIVKEY_SIGN"
    $after = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfter = Get-AuthCount $after
    if ($authBefore -ne $authAfter) { throw "HOST_PRIVKEY_SIGN changed AUTH_COUNT" }
    Write-Host "C4_0_UART_PRIVKEY_REJECT_NO_AUTH_PASS"

    Write-Host ""
    Write-Host "C4_0_LEGACY_SIGN_DISABLED_REGRESSION_PASS"
    exit 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
