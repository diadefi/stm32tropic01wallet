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
        [int]$TimeoutSeconds,
        [switch]$NoDrain
    )

    if (-not $NoDrain) {
        Drain-Stale -Serial $Serial
    }

    foreach ($line in $Lines) {
        if ($line -match "^UNLOCK_PIN=") {
            Write-Host ">> UNLOCK_PIN=<redacted>"
        } else {
            Write-Host ">> $line"
        }
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

    Write-Host "$Name AUTH_COUNT_UNCHANGED=$After"
}

function Assert-AuthIncrementedByOne {
    param(
        [uint32]$Before,
        [uint32]$After,
        [string]$Name
    )

    if ($After -ne ($Before + 1)) {
        throw "$Name did not increment AUTH_COUNT by one: before=$Before after=$After"
    }

    Write-Host "$Name AUTH_COUNT_INCREMENTED_BY_ONE=$After"
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
$changedSign = @($changedFields + "SIGN")
$badPayCheck = @($badPayFields + "CHECK")

$serial = $null
try {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " STM32 C4.3 TROPIC AUTH POLICY REGRESSION"
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
    Write-Host "--- C4.3 BASELINE AUTH COUNT ---"
    $baseline = Get-AuthCount -Serial $serial
    Write-Host "AUTH_COUNT_BASELINE=$baseline"

    Write-Host ""
    Write-Host "--- C4.3 CHECK DOES NOT AUTH ---"
    $check = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "POLICY_DECISION=APPROVED" -TimeoutSeconds $TimeoutSeconds
    Write-Host $check
    Assert-Contains $check "SIGNATURE_PRODUCED=0"
    Assert-NoRawTx $check "CHECK_DOES_NOT_AUTH"
    $afterCheck = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $baseline -After $afterCheck -Name "C4_3_CHECK_NO_AUTH"

    Write-Host ""
    Write-Host "--- C4.3 FAILED POLICY DOES NOT AUTH ---"
    $badPolicy = Send-CommandLines -Serial $serial -Lines $badPayCheck -RequiredPattern "ERR POLICY -38" -TimeoutSeconds $TimeoutSeconds
    Write-Host $badPolicy
    Assert-Contains $badPolicy "POLICY_DECISION=REJECTED"
    Assert-NoRawTx $badPolicy "FAILED_POLICY_DOES_NOT_AUTH"
    $afterBadPolicy = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $afterCheck -After $afterBadPolicy -Name "C4_3_FAILED_POLICY_NO_AUTH"

    Write-Host ""
    Write-Host "--- C4.3 WRONG PIN DOES NOT AUTH ---"
    $lock = Send-CommandLines -Serial $serial -Lines @("LOCK") -RequiredPattern "OK LOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $lock
    $wrongPin = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=000000") -RequiredPattern "ERR KEYPROVIDER -23" -TimeoutSeconds $TimeoutSeconds
    Write-Host $wrongPin
    Assert-NoRawTx $wrongPin "WRONG_PIN_DOES_NOT_AUTH"
    $afterWrongPin = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $afterBadPolicy -After $afterWrongPin -Name "C4_3_WRONG_PIN_NO_AUTH"
    Start-Sleep -Milliseconds 1200

    Write-Host ""
    Write-Host "--- C4.3 SIGN MISMATCH DOES NOT AUTH ---"
    $unlockForMismatch = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlockForMismatch
    $mismatchCheck = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "POLICY_DECISION=APPROVED" -TimeoutSeconds $TimeoutSeconds
    Write-Host $mismatchCheck
    $mismatchCode = Get-ConfirmCode $mismatchCheck
    $mismatchConfirm = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$mismatchCode") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $mismatchConfirm
    $mismatch = Send-CommandLines -Serial $serial -Lines $changedSign -RequiredPattern "ERR POLICY -44" -TimeoutSeconds $TimeoutSeconds
    Write-Host $mismatch
    Assert-NoRawTx $mismatch "SIGN_MISMATCH_DOES_NOT_AUTH"
    $afterMismatch = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $afterWrongPin -After $afterMismatch -Name "C4_3_SIGN_MISMATCH_NO_AUTH"

    Write-Host ""
    Write-Host "--- C4.3 SUCCESSFUL SIGN AUTHS EXACTLY ONCE ---"
    $unlock = Send-CommandLines -Serial $serial -Lines @("UNLOCK_PIN=123456") -RequiredPattern "OK UNLOCK" -TimeoutSeconds $TimeoutSeconds
    Write-Host $unlock
    $successCheck = Send-CommandLines -Serial $serial -Lines $validCheck -RequiredPattern "POLICY_DECISION=APPROVED" -TimeoutSeconds $TimeoutSeconds
    Write-Host $successCheck
    $successCode = Get-ConfirmCode $successCheck
    $successConfirm = Send-CommandLines -Serial $serial -Lines @("CONFIRM_CODE=$successCode") -RequiredPattern "OK CONFIRM" -TimeoutSeconds $TimeoutSeconds
    Write-Host $successConfirm
    $sign = Send-CommandLines -Serial $serial -Lines $validSign -RequiredPattern "RAW_TX=[0-9a-fA-F]+" -TimeoutSeconds $TimeoutSeconds
    Write-Host $sign
    Assert-Contains $sign "RAW_TX="
    $afterSign = Get-AuthCount -Serial $serial
    Assert-AuthIncrementedByOne -Before $afterMismatch -After $afterSign -Name "C4_3_SUCCESSFUL_SIGN_AUTH"

    Write-Host ""
    Write-Host "C4_3_CHECK_NO_AUTH_PASS"
    Write-Host "C4_3_FAILED_POLICY_NO_AUTH_PASS"
    Write-Host "C4_3_WRONG_PIN_NO_AUTH_PASS"
    Write-Host "C4_3_SIGN_MISMATCH_NO_AUTH_PASS"
    Write-Host "C4_3_SUCCESSFUL_SIGN_AUTH_ONCE_PASS"
    Write-Host "C4_3_TROPIC_AUTH_POLICY_REGRESSION_PASS"
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}
