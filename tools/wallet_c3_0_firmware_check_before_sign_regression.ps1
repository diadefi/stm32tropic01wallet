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

function Get-AuthCount {
    param([string]$Text)
    $m = [regex]::Match($Text, "AUTH_COUNT=(\d+)")
    if (-not $m.Success) { throw "AUTH_COUNT missing" }
    return [int]$m.Groups[1].Value
}

function Get-ConfirmCode {
    param([string]$Text)
    $m = [regex]::Match($Text, "(?m)^CONFIRM_CODE=(\d{6})\s*$")
    if (-not $m.Success) {
        Write-Host ""
        Write-Host "--- TEXT MISSING CONFIRM_CODE ---"
        Write-Host $Text
        throw "CONFIRM_CODE missing or malformed"
    }
    return $m.Groups[1].Value
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

$mismatchSignFields = @(
    "NETWORK=REGTEST",
    "TXID_LE=09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    "VOUT=1",
    "INPUT_SATS=100000",
    "PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    "PAY_SATS=60001",
    "CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    "CHANGE_SATS=30000"
)

$validCheck = @($validFields + "CHECK")
$validSign = @($validFields + "SIGN")
$badPayCheck = @($badPayFields + "CHECK")
$mismatchSign = @($mismatchSignFields + "SIGN")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C3.0 FIRMWARE CHECK-BEFORE-SIGN REGRESSION"
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
    Assert-Contains $clear "ERR POLICY -38"
    Assert-NoRawTx $clear "CLEAR_PENDING_CHECK"

    Write-Host ""
    Write-Host "--- C3.0 NO-CHECK SIGN REJECT ---"
    $beforeNoCheck = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBeforeNoCheck = Get-AuthCount $beforeNoCheck
    $noCheck = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $noCheck
    Assert-Contains $noCheck "ERR POLICY -43"
    Assert-NoRawTx $noCheck "NO_CHECK_SIGN"
    $afterNoCheck = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfterNoCheck = Get-AuthCount $afterNoCheck
    if ($authBeforeNoCheck -ne $authAfterNoCheck) { throw "NO_CHECK_SIGN changed AUTH_COUNT" }
    Write-Host "C3_0_NO_CHECK_SIGN_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C3.0 POSITIVE CHECK THEN SIGN ---"
    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    Assert-Contains $unlock "OK UNLOCK"
    $check = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "POLICY_DECISION=APPROVED"
    Assert-Contains $check "SIGNATURE_PRODUCED=0"
    Assert-NoRawTx $check "POSITIVE_CHECK"
    $confirm = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirm
    Assert-Contains $confirm "OK CONFIRM"
    $sign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=" -TimeoutSeconds 180
    Write-Host $sign
    Assert-Contains $sign "OK"
    Assert-Contains $sign "RAW_TX="
    Write-Host "C3_0_CHECK_THEN_SIGN_PASS"

    Write-Host ""
    Write-Host "--- C3.0 SIGN TWICE REJECT ---"
    $twice = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $twice
    Assert-Contains $twice "ERR POLICY -43"
    Assert-NoRawTx $twice "SIGN_TWICE"
    Write-Host "C3_0_SIGN_TWICE_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C3.0 CHECK APPROVED THEN MISMATCHED SIGN REJECT ---"
    $check2 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check2
    Assert-Contains $check2 "POLICY_DECISION=APPROVED"
    $confirmMismatch = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check2)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirmMismatch
    Assert-Contains $confirmMismatch "OK CONFIRM"
    $beforeMismatch = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBeforeMismatch = Get-AuthCount $beforeMismatch
    $mismatch = Send-CommandLines -Serial $serial -Lines $mismatchSign -RequiredPattern "ERR POLICY -44" -TimeoutSeconds $TimeoutSeconds
    Write-Host $mismatch
    Assert-Contains $mismatch "ERR POLICY -44"
    Assert-NoRawTx $mismatch "MISMATCH_SIGN"
    $afterMismatch = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfterMismatch = Get-AuthCount $afterMismatch
    if ($authBeforeMismatch -ne $authAfterMismatch) { throw "MISMATCH_SIGN changed AUTH_COUNT" }
    Write-Host "C3_0_MISMATCH_SIGN_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C3.0 FAILED CHECK STORES NOTHING ---"
    $badCheck = Send-CommandLines -Serial $serial -Lines $badPayCheck -RequiredPattern "ERR POLICY -38" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badCheck
    Assert-Contains $badCheck "POLICY_DECISION=REJECTED"
    Assert-Contains $badCheck "ERR POLICY -38"
    Assert-NoRawTx $badCheck "FAILED_CHECK"
    $afterBadSign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $afterBadSign
    Assert-Contains $afterBadSign "ERR POLICY -43"
    Assert-NoRawTx $afterBadSign "FAILED_CHECK_THEN_SIGN"
    Write-Host "C3_0_FAILED_CHECK_STORES_NOTHING_PASS"

    Write-Host ""
    Write-Host "C3_0_FIRMWARE_CHECK_BEFORE_SIGN_REGRESSION_PASS"
    $global:LASTEXITCODE = 0
}
finally {
    if ($serial -ne $null -and $serial.IsOpen) {
        $serial.Close()
    }
}
