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

function Assert-Matches {
    param([string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) {
        Write-Host ""
        Write-Host "--- TEXT THAT FAILED REGEX ASSERTION ---"
        Write-Host $Text
        throw "Missing expected regex: $Pattern"
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

$validCheck = @($validFields + "CHECK")
$validSign = @($validFields + "SIGN")
$badPayCheck = @($badPayFields + "CHECK")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C3.5 CONFIRM CODE REGRESSION"
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
    Assert-NoRawTx $clear "C3_5_CLEAR_PENDING"

    Write-Host ""
    Write-Host "--- C3.5 POLICYINFO REPORTS CONFIRM CODE ERRORS ---"
    $policyInfo = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "ERR_CONFIRM_CODE_MISMATCH=-50" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policyInfo
    Assert-Contains $policyInfo "ERR_CONFIRM_CODE_REQUIRED=-49"
    Assert-Contains $policyInfo "ERR_CONFIRM_CODE_MISMATCH=-50"
    Write-Host "C3_5_POLICYINFO_CONFIRM_CODE_PASS"

    Write-Host ""
    Write-Host "--- C3.5 APPROVED CHECK EMITS CONFIRM CODE ---"
    $check = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "POLICY_DECISION=APPROVED"
    Assert-Matches $check "(?m)^CHECK_ID=[0-9a-f]{64}\s*$"
    Assert-Matches $check "(?m)^CONFIRM_CODE=\d{6}\s*$"
    $confirmCode = Get-ConfirmCode $check
    Write-Host "C3_5_CONFIRM_CODE_PRESENT_PASS CONFIRM_CODE=$confirmCode"

    Write-Host ""
    Write-Host "--- C3.5 BARE CONFIRM REJECTS WHEN CODE IS REQUIRED ---"
    $bare = Send-CommandLines -Serial $serial -Lines @("CONFIRM") -RequiredPattern "ERR POLICY -49" -TimeoutSeconds $TimeoutSeconds
    Write-Host $bare
    Assert-Contains $bare "ERR POLICY -49"
    Assert-NoRawTx $bare "BARE_CONFIRM"
    Write-Host "C3_5_BARE_CONFIRM_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C3.5 WRONG CONFIRM CODE REJECTS AND CLEARS APPROVAL ---"
    $check2 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check2
    Assert-Contains $check2 "POLICY_DECISION=APPROVED"
    $check2Code = Get-ConfirmCode $check2
    $wrongCode = "000000"
    if ($check2Code -eq $wrongCode) { $wrongCode = "000001" }
    $wrong = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$wrongCode") -RequiredPattern "ERR POLICY -50" -TimeoutSeconds $TimeoutSeconds
    Write-Host $wrong
    Assert-Contains $wrong "ERR POLICY -50"
    Assert-NoRawTx $wrong "WRONG_CONFIRM_CODE"
    $afterWrongSign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $afterWrongSign
    Assert-Contains $afterWrongSign "ERR POLICY -43"
    Assert-NoRawTx $afterWrongSign "SIGN_AFTER_WRONG_CONFIRM_CODE"
    Write-Host "C3_5_WRONG_CONFIRM_CODE_REJECT_PASS"

    Write-Host ""
    Write-Host "--- C3.5 RIGHT CONFIRM CODE SIGNS ONCE ---"
    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    Assert-Contains $unlock "OK UNLOCK"
    $check3 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check3
    Assert-Contains $check3 "POLICY_DECISION=APPROVED"
    $rightCode = Get-ConfirmCode $check3
    $confirm = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$rightCode") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirm
    Assert-Contains $confirm "OK CONFIRM"
    Assert-Contains $confirm "CONFIRM_SOURCE=UART_CONFIRM_CODE"
    $beforeSign = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBeforeSign = Get-AuthCount $beforeSign
    $sign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=" -TimeoutSeconds 180
    Write-Host $sign
    Assert-Contains $sign "OK"
    Assert-Contains $sign "RAW_TX="
    $afterSign = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfterSign = Get-AuthCount $afterSign
    if ($authAfterSign -le $authBeforeSign) { throw "RIGHT_CONFIRM_CODE_SIGN did not increment AUTH_COUNT" }
    $twice = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $twice
    Assert-Contains $twice "ERR POLICY -43"
    Assert-NoRawTx $twice "SIGN_TWICE_AFTER_RIGHT_CONFIRM_CODE"
    Write-Host "C3_5_RIGHT_CONFIRM_CODE_SIGN_PASS"

    Write-Host ""
    Write-Host "C3_5_CONFIRM_CODE_REGRESSION_PASS"
    exit 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
