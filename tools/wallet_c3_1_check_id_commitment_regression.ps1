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

function Sync-FreshPrompt {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $Serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $Serial.WriteLine("VERSION")

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial
        if (($buf -match "OK VERSION") -and ($buf -match "(?s)READY.*>\s*$")) {
            $Serial.DiscardInBuffer()
            return $buf
        }
        Start-Sleep -Milliseconds 50
    }

    Write-Host ""
    Write-Host "--- FRESH PROMPT SYNC TIMEOUT BUFFER ---"
    Write-Host $buf
    throw "Timeout waiting for fresh VERSION/READY prompt"
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

function Get-CheckId {
    param([string]$Text)
    $m = [regex]::Match($Text, "(?m)^CHECK_ID=([0-9a-f]{64})\s*$")
    if (-not $m.Success) {
        Write-Host ""
        Write-Host "--- TEXT MISSING CHECK_ID ---"
        Write-Host $Text
        throw "CHECK_ID missing or malformed"
    }
    return $m.Groups[1].Value
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

$changedFields = @(
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
$changedCheck = @($changedFields + "CHECK")
$changedSign = @($changedFields + "SIGN")
$badPayCheck = @($badPayFields + "CHECK")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C3.1 CHECK_ID COMMITMENT REGRESSION"
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
    $sync = Sync-FreshPrompt -Serial $serial -TimeoutSeconds $TimeoutSeconds
    Write-Host ""
    Write-Host "--- C3.1 FRESH UART SYNC ---"
    Write-Host $sync

    Write-Host ""
    Write-Host "--- CLEAR ANY PENDING APPROVAL WITH REJECTED CHECK ---"
    $clear = Send-CommandLines -Serial $serial -Lines $badPayCheck -RequiredPattern "ERR POLICY -38" -TimeoutSeconds $TimeoutSeconds
    Write-Host $clear
    Assert-Contains $clear "POLICY_DECISION=REJECTED"
    Assert-NoRawTx $clear "C3_1_CLEAR_PENDING"

    Write-Host ""
    Write-Host "--- C3.1 CHECK_ID PRESENT ---"
    $check1 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check1
    Assert-Contains $check1 "SUMMARY_VERSION=C3.1_DEVICE_POLICY_SUMMARY_CHECK_ID"
    Assert-Contains $check1 "POLICY_DECISION=APPROVED"
    Assert-Contains $check1 "SIGNATURE_PRODUCED=0"
    Assert-Matches $check1 "(?m)^CHECK_ID=[0-9a-f]{64}\s*$"
    Assert-NoRawTx $check1 "C3_1_CHECK"
    $checkId1 = Get-CheckId $check1
    Write-Host "C3_1_CHECK_ID_PRESENT_PASS CHECK_ID=$checkId1"

    Write-Host ""
    Write-Host "--- C3.1 CHECK_ID DETERMINISTIC ---"
    $check2 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check2
    $checkId2 = Get-CheckId $check2
    if ($checkId1 -ne $checkId2) {
        throw "CHECK_ID not deterministic for identical candidate: $checkId1 vs $checkId2"
    }
    Write-Host "C3_1_CHECK_ID_DETERMINISTIC_PASS CHECK_ID=$checkId2"

    Write-Host ""
    Write-Host "--- C3.1 CHECK_ID CHANGES WITH CANDIDATE ---"
    $changed = Send-CommandLines -Serial $serial -Lines $changedCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $changed
    Assert-Contains $changed "POLICY_DECISION=APPROVED"
    $changedId = Get-CheckId $changed
    if ($changedId -eq $checkId1) {
        throw "CHECK_ID did not change after PAY_SATS changed"
    }
    Write-Host "C3_1_CHECK_ID_CHANGE_PASS ORIGINAL=$checkId1 CHANGED=$changedId"

    Write-Host ""
    Write-Host "--- C3.1 MATCHING SIGN USES STORED CHECK_ID ---"
    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    Assert-Contains $unlock "OK UNLOCK"
    $check3 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check3
    $confirm = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check3)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirm
    Assert-Contains $confirm "OK CONFIRM"
    $sign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=" -TimeoutSeconds 180
    Write-Host $sign
    Assert-Contains $sign "OK"
    Assert-Contains $sign "RAW_TX="
    Write-Host "C3_1_CHECK_ID_MATCH_SIGN_PASS"

    Write-Host ""
    Write-Host "--- C3.1 MISMATCHED SIGN REJECTED BY CHECK_ID ---"
    $check4 = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "SUMMARY_BEGIN" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check4
    $confirmMismatch = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$(Get-ConfirmCode $check4)") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $confirmMismatch
    Assert-Contains $confirmMismatch "OK CONFIRM"
    $mismatch = Send-CommandLines -Serial $serial -Lines $changedSign -RequiredPattern "ERR POLICY -44" -TimeoutSeconds $TimeoutSeconds
    Write-Host $mismatch
    Assert-Contains $mismatch "ERR POLICY -44"
    Assert-NoRawTx $mismatch "C3_1_MISMATCH_SIGN"
    Write-Host "C3_1_CHECK_ID_MISMATCH_REJECT_PASS"

    Write-Host ""
    Write-Host "C3_1_CHECK_ID_COMMITMENT_REGRESSION_PASS"
    $global:LASTEXITCODE = 0
}
finally {
    if ($serial -ne $null -and $serial.IsOpen) {
        $serial.Close()
    }
}
