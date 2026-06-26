param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 30,
    [int]$ApprovalTimeoutSeconds = 12
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
$confirm = @("CONFIRM")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C3.4 APPROVAL TIMEOUT REGRESSION"
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
    Assert-NoRawTx $clear "C3_4_CLEAR_PENDING"

    Write-Host ""
    Write-Host "--- C3.4 POLICYINFO REPORTS TIMEOUT ---"
    $policyInfo = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "APPROVAL_TIMEOUT_MS=10000" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policyInfo
    Assert-Contains $policyInfo "ERR_APPROVAL_EXPIRED=-48"
    Assert-Contains $policyInfo "APPROVAL_TIMEOUT_MS=10000"
    Write-Host "C3_4_POLICYINFO_TIMEOUT_PASS"

    Write-Host ""
    Write-Host "--- C3.4 PENDING CHECK EXPIRES BEFORE CONFIRM ---"
    $check = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "POLICY_DECISION=APPROVED"
    Write-Host "Waiting $ApprovalTimeoutSeconds seconds for pending CHECK to expire..."
    Start-Sleep -Seconds $ApprovalTimeoutSeconds
    $expiredConfirm = Send-CommandLines -Serial $serial -Lines $confirm -RequiredPattern "ERR POLICY -48" -TimeoutSeconds $TimeoutSeconds
    Write-Host $expiredConfirm
    Assert-Contains $expiredConfirm "ERR POLICY -48"
    Assert-NoRawTx $expiredConfirm "CONFIRM_AFTER_EXPIRED_CHECK"
    $buttonInfo = Send-CommandLines -Serial $serial -Lines @("BUTTONINFO") -RequiredPattern "OK BUTTONINFO" -TimeoutSeconds $TimeoutSeconds
    Write-Host $buttonInfo
    Assert-Contains $buttonInfo "APPROVED_CHECK_PENDING=0"
    Assert-Contains $buttonInfo "APPROVED_CHECK_CONFIRMED=0"
    Write-Host "C3_4_PENDING_CHECK_TIMEOUT_PASS"

    Write-Host ""
    Write-Host "--- C3.4 CONFIRMED APPROVAL EXPIRES BEFORE SIGN ---"
    $check2 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check2
    Assert-Contains $check2 "POLICY_DECISION=APPROVED"
    $confirmOk = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check2)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirmOk
    Assert-Contains $confirmOk "OK CONFIRM"
    $beforeExpiredSign = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authBeforeExpiredSign = Get-AuthCount $beforeExpiredSign
    Write-Host "Waiting $ApprovalTimeoutSeconds seconds for confirmed approval to expire..."
    Start-Sleep -Seconds $ApprovalTimeoutSeconds
    $expiredSign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -48" -TimeoutSeconds $TimeoutSeconds
    Write-Host $expiredSign
    Assert-Contains $expiredSign "ERR POLICY -48"
    Assert-NoRawTx $expiredSign "SIGN_AFTER_EXPIRED_CONFIRM"
    $afterExpiredSign = Send-CommandLines -Serial $serial -Lines @("SEINFO") -RequiredPattern "OK SEINFO" -TimeoutSeconds $TimeoutSeconds
    $authAfterExpiredSign = Get-AuthCount $afterExpiredSign
    if ($authBeforeExpiredSign -ne $authAfterExpiredSign) { throw "SIGN_AFTER_EXPIRED_CONFIRM changed AUTH_COUNT" }
    Write-Host "C3_4_CONFIRMED_SIGN_TIMEOUT_PASS"

    Write-Host ""
    Write-Host "--- C3.4 FRESH CONFIRM SIGN STILL WORKS AND CLEARS ONCE ---"
    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    Assert-Contains $unlock "OK UNLOCK"
    $check3 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check3
    Assert-Contains $check3 "POLICY_DECISION=APPROVED"
    $confirmFresh = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check3)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirmFresh
    Assert-Contains $confirmFresh "OK CONFIRM"
    $signFresh = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=" -TimeoutSeconds 180
    Write-Host $signFresh
    Assert-Contains $signFresh "OK"
    Assert-Contains $signFresh "RAW_TX="
    $twice = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "ERR POLICY -43" -TimeoutSeconds $TimeoutSeconds
    Write-Host $twice
    Assert-Contains $twice "ERR POLICY -43"
    Assert-NoRawTx $twice "SIGN_TWICE_AFTER_FRESH_SIGN"
    Write-Host "C3_4_FRESH_SIGN_ONE_SHOT_PASS"

    Write-Host ""
    Write-Host "C3_4_APPROVAL_TIMEOUT_REGRESSION_PASS"
    exit 0
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) { $serial.Close() }
        $serial.Dispose()
    }
}
