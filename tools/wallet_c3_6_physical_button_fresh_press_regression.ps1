param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 30,
    [int]$ButtonTimeoutSeconds = 120,
    [string]$ReadyFlagFile = ""
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

function Wait-ForReadyFlag {
    param(
        [string]$Path,
        [int]$TimeoutSeconds
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }

    Write-Host ""
    Write-Host "C3_6_WAITING_FOR_HELD_BUTTON_READY_FLAG=$Path"
    Write-Host "Hold the USER button down now. The harness will create this flag when it is time to continue."

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
            Write-Host "C3_6_HELD_BUTTON_READY_FLAG_SEEN"
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timeout waiting for C3.6 ready flag: $Path"
}

function Wait-ForButtonHeld {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $info = Send-CommandLines -Serial $Serial -Lines @("BUTTONINFO") -RequiredPattern "OK BUTTONINFO" -TimeoutSeconds 5
        Write-Host $info
        if ($info -match "BUTTON_USER_PRESSED_ACTIVE_HIGH=1") {
            return $info
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Timed out waiting for USER button to be held"
}

function Wait-ForButtonConfirm {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    Write-Host ""
    Write-Host "RELEASE_THEN_PRESS_USER_BUTTON_NOW"
    Write-Host "Waiting up to $TimeoutSeconds seconds for a fresh OK BUTTON_CONFIRM..."

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match "OK BUTTON_CONFIRM") -and ($buf -match "CONFIRM_SOURCE=BUTTON_USER")) {
            return $buf
        }
        Start-Sleep -Milliseconds 50
    }

    Write-Host ""
    Write-Host "--- BUTTON TIMEOUT BUFFER ---"
    Write-Host $buf
    throw "Timeout waiting for fresh physical USER button confirmation"
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

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Name)
    if ($Text -match [regex]::Escape($Needle)) {
        Write-Host ""
        Write-Host "--- TEXT THAT FAILED NEGATIVE ASSERTION ---"
        Write-Host $Text
        throw "$Name unexpectedly contained: $Needle"
    }
}

function Assert-NoRawTx {
    param([string]$Text, [string]$Name)
    if ($Text -match "RAW_TX=[0-9a-fA-F]+") {
        throw "$Name unexpectedly produced RAW_TX"
    }
}

$validFields = @(
    "NETWORK=REGTEST",
    "TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "VOUT=1",
    "INPUT_SATS=100000",
    "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PAY_SATS=60000",
    "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "CHANGE_SATS=30000"
)

$badPayFields = @(
    "NETWORK=REGTEST",
    "TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "VOUT=1",
    "INPUT_SATS=100000",
    "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_SCRIPT=76a914111111111111111111111111111111111111111188ac",
    "PAY_SATS=60000",
    "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "CHANGE_SATS=30000"
)

$validCheck = @($validFields + "CHECK")
$validSign = @($validFields + "SIGN")
$badPayCheck = @($badPayFields + "CHECK")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C3.6 PHYSICAL BUTTON FRESH PRESS REGRESSION"
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
    Write-Host "--- CLEAR ANY PENDING APPROVAL WITH REJECTED CHECK ---"
    $clear = Send-CommandLines -Serial $serial -Lines $badPayCheck -RequiredPattern "ERR POLICY -38" -TimeoutSeconds $TimeoutSeconds
    Write-Host $clear
    Assert-Contains $clear "POLICY_DECISION=REJECTED"
    Assert-NoRawTx $clear "C3_6_CLEAR_PENDING"

    Write-Host ""
    Write-Host "--- C3.6 HOLD BUTTON BEFORE CHECK ---"
    Wait-ForReadyFlag -Path $ReadyFlagFile -TimeoutSeconds $ButtonTimeoutSeconds
    $heldInfo = Wait-ForButtonHeld -Serial $serial -TimeoutSeconds $ButtonTimeoutSeconds
    Assert-Contains $heldInfo "BUTTON_USER_PRESSED_ACTIVE_HIGH=1"

    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    Assert-Contains $unlock "OK UNLOCK"

    Write-Host ""
    Write-Host "--- C3.6 CHECK WHILE BUTTON IS ALREADY HELD ---"
    $check = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "POLICY_DECISION=APPROVED"
    Assert-NotContains $check "OK BUTTON_CONFIRM" "STALE_HELD_BUTTON_CHECK"

    Start-Sleep -Milliseconds 1000
    $heldNoise = Read-Available -Serial $serial
    Write-Host $heldNoise
    Assert-NotContains $heldNoise "OK BUTTON_CONFIRM" "STALE_HELD_BUTTON_IDLE"

    $pendingInfo = Send-CommandLines -Serial $serial -Lines @("BUTTONINFO") -RequiredPattern "OK BUTTONINFO" -TimeoutSeconds $TimeoutSeconds
    Write-Host $pendingInfo
    Assert-Contains $pendingInfo "APPROVED_CHECK_PENDING=1"
    Assert-Contains $pendingInfo "APPROVED_CHECK_CONFIRMED=0"
    Assert-Contains $pendingInfo "BUTTON_CONFIRM_ARMED=0"
    Write-Host "C3_6_STALE_HELD_BUTTON_IGNORED_PASS"

    $button = Wait-ForButtonConfirm -Serial $serial -TimeoutSeconds $ButtonTimeoutSeconds
    Write-Host $button
    Assert-Contains $button "OK BUTTON_CONFIRM"
    Assert-Contains $button "USER_APPROVED=1"
    Assert-Contains $button "CONFIRM_SOURCE=BUTTON_USER"
    Write-Host "C3_6_RELEASE_REARMS_BUTTON_PASS"

    $sign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=" -TimeoutSeconds 180
    Write-Host $sign
    Assert-Contains $sign "OK"
    Assert-Contains $sign "RAW_TX="
    Write-Host "C3_6_FRESH_BUTTON_PRESS_SIGN_PASS"

    Write-Host ""
    Write-Host "C3_6_PHYSICAL_BUTTON_FRESH_PRESS_REGRESSION_PASS"
    exit 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
