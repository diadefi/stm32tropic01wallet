param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,

    [string]$Network = "REGTEST",
    [string]$TxidLe = "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
    [int]$Vout = 1,
    [long]$InputSats = 100000,
    [ValidateRange(1,2)]
    [int]$InputCount = 1,
    [string]$TxidLe1 = "19f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a633",
    [int]$Vout1 = 0,
    [long]$InputSats1 = 50000,

    [string]$PrevScript = "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    [string]$PrevScript1 = "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    [string]$PayScript = "76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
    [long]$PaySats = 60000,
    [string]$ChangeScript = "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
    [long]$ChangeSats = 30000,
    [string]$ChangeDerivation = "",

    [string]$UnlockPin = "123456",
    [switch]$OmitUnlockPin,
    [ValidateSet("Legacy", "PsbtLike")]
    [string]$CommandFormat = "Legacy",
    [string]$CheckBindingTamperField = "",
    [string]$CheckBindingTamperValue = "",

    [string]$RawTxOutFile = "",
    [int]$TimeoutSeconds = 180,
    [int]$SyncTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function Read-SerialAvailable {
    param(
        [System.IO.Ports.SerialPort]$Serial
    )

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

function Read-SerialForDuration {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$Milliseconds
    )

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-SerialAvailable -Serial $Serial
        Start-Sleep -Milliseconds 50
    }

    return $buf
}

function Read-UntilFreshVersionReady {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-SerialAvailable -Serial $Serial

        if ($buf -match "OK VERSION") {
            $afterVersion = ($buf -split "OK VERSION", 2)[1]
            if ($afterVersion -match "(?s)READY.*>\s*$") {
                return $buf
            }
        }

        Start-Sleep -Milliseconds 50
    }

    throw "UART sync failed: no fresh OK VERSION/READY response"
}

function Read-UntilCommandResponse {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-SerialAvailable -Serial $Serial

        $hasResult = ($buf -match "RAW_TX=[0-9a-fA-F]+") -or ($buf -match "ERR (POLICY|KEYPROVIDER) -?\d+")
        $hasReady = ($buf -match "READY")

        if ($hasResult -and $hasReady) {
            return $buf
        }

        Start-Sleep -Milliseconds 50
    }

    return $buf
}

function Read-UntilConfirmResponse {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-SerialAvailable -Serial $Serial

        $hasResult = ($buf -match "OK CONFIRM") -or ($buf -match "ERR POLICY -?\d+")
        $hasReady = ($buf -match "READY")

        if ($hasResult -and $hasReady) {
            return $buf
        }

        Start-Sleep -Milliseconds 50
    }

    return $buf
}

function Read-UntilUnlockResponse {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [int]$TimeoutSeconds
    )

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-SerialAvailable -Serial $Serial

        $hasResult = ($buf -match "OK UNLOCK") -or ($buf -match "ERR KEYPROVIDER -?\d+")
        $hasReady = ($buf -match "READY")

        if ($hasResult -and $hasReady) {
            return $buf
        }

        Start-Sleep -Milliseconds 50
    }

    return $buf
}

function Build-WalletCommand {
    $lines = New-Object System.Collections.Generic.List[string]

    if ($CommandFormat -eq "PsbtLike") {
        $lines.Add("WALLET_CMD_FORMAT=C5.0_PSBT_LIKE_TEXT_V1")
        $lines.Add("PSBT_GLOBAL_NETWORK=$Network")
        $lines.Add("PSBT_INPUT_COUNT=$InputCount")
        $lines.Add("PSBT_INPUT0_TXID_LE=$TxidLe")
        $lines.Add("PSBT_INPUT0_VOUT=$Vout")
        $lines.Add("PSBT_INPUT0_SATS=$InputSats")
        $lines.Add("PSBT_INPUT0_PREV_SCRIPT=$PrevScript")
        if ($InputCount -eq 2) {
            $lines.Add("PSBT_INPUT1_TXID_LE=$TxidLe1")
            $lines.Add("PSBT_INPUT1_VOUT=$Vout1")
            $lines.Add("PSBT_INPUT1_SATS=$InputSats1")
            $lines.Add("PSBT_INPUT1_PREV_SCRIPT=$PrevScript1")
        }
        $lines.Add("PSBT_OUTPUT_COUNT=2")
        $lines.Add("PSBT_OUTPUT0_ROLE=PAYMENT")
        $lines.Add("PSBT_OUTPUT0_SCRIPT=$PayScript")
        $lines.Add("PSBT_OUTPUT0_SATS=$PaySats")
        $lines.Add("PSBT_OUTPUT1_ROLE=CHANGE")
        $lines.Add("PSBT_OUTPUT1_SCRIPT=$ChangeScript")
        $lines.Add("PSBT_OUTPUT1_SATS=$ChangeSats")
        if ($ChangeDerivation -ne "") {
            $lines.Add("PSBT_OUTPUT1_DERIVATION=$ChangeDerivation")
        }
    } else {
        if ($InputCount -ne 1) {
            throw "Legacy command format only supports InputCount=1"
        }
        $lines.Add("NETWORK=$Network")
        $lines.Add("TXID_LE=$TxidLe")
        $lines.Add("VOUT=$Vout")
        $lines.Add("INPUT_SATS=$InputSats")
        $lines.Add("PREV_SCRIPT=$PrevScript")
        $lines.Add("PAY_SCRIPT=$PayScript")
        $lines.Add("PAY_SATS=$PaySats")
        $lines.Add("CHANGE_SCRIPT=$ChangeScript")
        $lines.Add("CHANGE_SATS=$ChangeSats")
    }

    $lines.Add("SIGN")

    return $lines
}

function Get-CommandFieldAlias {
    param([string]$Name)

    switch ($Name) {
        "NETWORK" { return "PSBT_GLOBAL_NETWORK" }
        "INPUT_COUNT" { return "PSBT_INPUT_COUNT" }
        "TXID_LE" { return "PSBT_INPUT0_TXID_LE" }
        "VOUT" { return "PSBT_INPUT0_VOUT" }
        "INPUT_SATS" { return "PSBT_INPUT0_SATS" }
        "PREV_SCRIPT" { return "PSBT_INPUT0_PREV_SCRIPT" }
        "PAY_SCRIPT" { return "PSBT_OUTPUT0_SCRIPT" }
        "PAY_SATS" { return "PSBT_OUTPUT0_SATS" }
        "CHANGE_SCRIPT" { return "PSBT_OUTPUT1_SCRIPT" }
        "CHANGE_SATS" { return "PSBT_OUTPUT1_SATS" }
        default { return "" }
    }
}

$serial = $null

try {
    $totalInputSats = $InputSats
    if ($InputCount -eq 2) {
        $totalInputSats += $InputSats1
    }
    $fee = $totalInputSats - $PaySats - $ChangeSats
    $cmdLines = Build-WalletCommand

    Write-Host ""
    Write-Host "--- GENERATED WALLET COMMAND ---"
    foreach ($line in $cmdLines) {
        Write-Host $line
    }

    Write-Host ""
    Write-Host "--- LOCAL AMOUNT SUMMARY ---"
    Write-Host "INPUT_COUNT=$InputCount"
    Write-Host "INPUT_SATS=$InputSats"
    if ($InputCount -eq 2) {
        Write-Host "INPUT1_SATS=$InputSats1"
    }
    Write-Host "TOTAL_INPUT_SATS=$totalInputSats"
    Write-Host "PAY_SATS=$PaySats"
    Write-Host "CHANGE_SATS=$ChangeSats"
    Write-Host "FEE_SATS=$fee"

    # C2.2: Host-side signing confirmation transcript.
    # This is not a secure display; it is an MVP transcript produced from
    # STM32-reported public identity plus the exact SIGN command fields.
    $deviceIdentityAddress = ""
    $deviceIdentityScript = ""
    $deviceIdentityNetwork = ""
    $deviceIdentityModel = ""

    if (Test-Path ".\tools\wallet_get_device_identity.ps1") {
        try {
            $identityOutput = & powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File ".\tools\wallet_get_device_identity.ps1" `
                -Port $Port `
                2>&1

            $identityText = ($identityOutput | Out-String)

            $mAddr = [regex]::Match($identityText, "(?m)^DEVICE_ADDRESS=(.+?)\s*$")
            $mScript = [regex]::Match($identityText, "(?m)^DEVICE_SCRIPT_P2PKH=(.+?)\s*$")
            $mNetwork = [regex]::Match($identityText, "(?m)^DEVICE_NETWORK=(.+?)\s*$")
            $mModel = [regex]::Match($identityText, "(?m)^DEVICE_KEY_MODEL=(.+?)\s*$")

            if ($mAddr.Success) { $deviceIdentityAddress = $mAddr.Groups[1].Value.Trim() }
            if ($mScript.Success) { $deviceIdentityScript = $mScript.Groups[1].Value.Trim() }
            if ($mNetwork.Success) { $deviceIdentityNetwork = $mNetwork.Groups[1].Value.Trim() }
            if ($mModel.Success) { $deviceIdentityModel = $mModel.Groups[1].Value.Trim() }
        } catch {
            Write-Host "DEVICE_IDENTITY_TRANSCRIPT_WARN=$($_.Exception.Message)"
        }
    }

    $unlockPresent = 1
    if ($OmitUnlockPin) {
        $unlockPresent = 0
    }

    Write-Host ""
    Write-Host "--- SIGNING CONFIRMATION TRANSCRIPT ---"
    Write-Host "CONFIRMATION_TRANSCRIPT_BEGIN"
    Write-Host "TRANSCRIPT_VERSION=C2.2_HOST_CONFIRMATION_TRANSCRIPT"
    Write-Host "TRANSCRIPT_SOURCE=HOST_FROM_DEVICE_IDENTITY_AND_SIGN_COMMAND"
    Write-Host "COMMAND_FORMAT=$CommandFormat"
    Write-Host "SECURE_DISPLAY=0"
    Write-Host "NETWORK=$Network"
    Write-Host "INPUT_COUNT=$InputCount"
    if ($deviceIdentityNetwork -ne "") {
        Write-Host "DEVICE_NETWORK=$deviceIdentityNetwork"
    }
    if ($deviceIdentityAddress -ne "") {
        Write-Host "SPEND_FROM_DEVICE_ADDRESS=$deviceIdentityAddress"
    }
    if ($deviceIdentityScript -ne "") {
        Write-Host "SPEND_FROM_DEVICE_SCRIPT=$deviceIdentityScript"
    }
    if ($deviceIdentityModel -ne "") {
        Write-Host "DEVICE_KEY_MODEL=$deviceIdentityModel"
    }
    Write-Host "INPUT_TXID_LE=$TxidLe"
    Write-Host "INPUT_VOUT=$Vout"
    Write-Host "INPUT_SATS=$InputSats"
    Write-Host "PREV_SCRIPT=$PrevScript"
    if ($InputCount -eq 2) {
        Write-Host "INPUT1_TXID_LE=$TxidLe1"
        Write-Host "INPUT1_VOUT=$Vout1"
        Write-Host "INPUT1_SATS=$InputSats1"
        Write-Host "INPUT1_PREV_SCRIPT=$PrevScript1"
    }
    Write-Host "TOTAL_INPUT_SATS=$totalInputSats"
    Write-Host "PAY_TO_SCRIPT=$PayScript"
    Write-Host "PAY_SATS=$PaySats"
    Write-Host "CHANGE_TO_SCRIPT=$ChangeScript"
    Write-Host "CHANGE_SATS=$ChangeSats"
    if ($ChangeDerivation -ne "") {
        Write-Host "CHANGE_DERIVATION=$ChangeDerivation"
    }
    Write-Host "FEE_SATS=$fee"
    Write-Host "PIN_SESSION_REQUESTED=$unlockPresent"
    Write-Host "UNLOCK_SECRET_PRESENT=0"
    Write-Host "HOST_EXPECTS_DEVICE_POLICY_CHECK=1"
    Write-Host "CONFIRMATION_TRANSCRIPT_END"

    Write-Host ""
    Write-Host "--- OPEN SERIAL $Port ---"

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
    Start-Sleep -Milliseconds 400

    Write-Host ""
    Write-Host "--- DRAIN STALE STARTUP OUTPUT ---"

    $startup = Read-SerialForDuration -Serial $serial -Milliseconds 1500
    if ($startup.Length -gt 0) {
        Write-Host $startup
    } else {
        Write-Host "(none)"
    }

    Write-Host ""
    Write-Host "--- FORCE FRESH UART SYNC WITH VERSION ---"

    $serial.DiscardInBuffer()
    $serial.WriteLine("VERSION")
    $sync = Read-UntilFreshVersionReady -Serial $serial -TimeoutSeconds $SyncTimeoutSeconds
    Write-Host $sync

    Write-Host ""
    Write-Host "--- CLEAR BUFFER BEFORE SIGN COMMAND ---"

    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $postClear = Read-SerialForDuration -Serial $serial -Milliseconds 300

    if ($postClear.Length -gt 0) {
        Write-Host "POST_CLEAR_STALE_BYTES_DISCARDED"
        Write-Host $postClear
        $serial.DiscardInBuffer()
    } else {
        Write-Host "POST_CLEAR_OK"
    }

    if (-not $OmitUnlockPin) {
        Write-Host ""
        Write-Host "--- C4.2 DEVICE PIN SESSION UNLOCK BEFORE CHECK ---"
        Write-Host ">> UNLOCK_PIN=<redacted>"
        $serial.WriteLine("UNLOCK_PIN=$UnlockPin")
        Start-Sleep -Milliseconds 80

        $unlockResponse = Read-UntilUnlockResponse -Serial $serial -TimeoutSeconds 20
        Write-Host $unlockResponse

        if ($unlockResponse -notmatch "OK UNLOCK") {
            Write-Host ""
            Write-Host "HOST_TX_GENERATOR_FAIL"
            Write-Host "CONFIRMATION_RESULT_BEGIN"
            Write-Host "POLICY_DECISION=REJECTED_BY_DEVICE_UNLOCK"
            $unlockErr = [regex]::Match($unlockResponse, "ERR KEYPROVIDER -?\d+")
            if ($unlockErr.Success) {
                Write-Host "DEVICE_ERROR=$($unlockErr.Value)"
            } else {
                Write-Host "DEVICE_ERROR=UNLOCK_REJECTED_WITHOUT_ERR_KEYPROVIDER"
            }
            Write-Host "RAW_TX_PRESENT=0"
            Write-Host "SIGN_SENT=0"
            Write-Host "NO_SIGN_SENT"
            Write-Host "CONFIRMATION_RESULT_END"
            exit 2
        }

        Write-Host "DEVICE_PIN_SESSION_UNLOCK_PASS"
    }

    Write-Host ""
    Write-Host "--- C2.4 DEVICE CHECK BEFORE SIGN ---"

    $checkLines = @()
    foreach ($line in $cmdLines) {
        $checkLines += $line
    }

    if ($checkLines.Count -lt 1) {
        throw "C2.4 CHECK failed: command line list is empty"
    }

    if ($checkLines[$checkLines.Count - 1] -ne "SIGN") {
        throw "C2.4 CHECK failed: expected final generated command line to be SIGN"
    }

    $checkLines[$checkLines.Count - 1] = "CHECK"

    $commandLineDelayMs = 80
    if ($CommandFormat -eq "PsbtLike") {
        $commandLineDelayMs = 120
    }

    foreach ($line in $checkLines) {
        Write-Host "?? $line"
        $serial.WriteLine($line)
        Start-Sleep -Milliseconds $commandLineDelayMs
    }

    $checkResponse = ""
    $checkDeadline = (Get-Date).AddSeconds(15)

    while ((Get-Date) -lt $checkDeadline) {
        $checkResponse += Read-SerialAvailable -Serial $serial

        if ($checkResponse -match "SUMMARY_END") {
            break
        }

        if ($checkResponse -match "ERR POLICY -?\d+") {
            break
        }

        Start-Sleep -Milliseconds 50
    }

    Write-Host ""
    Write-Host "--- DEVICE CHECK RESPONSE ---"
    Write-Host $checkResponse

    if ($checkResponse -notmatch "SUMMARY_BEGIN") {
        throw "C2.4 CHECK failed: missing SUMMARY_BEGIN"
    }

    if ($checkResponse -notmatch "SUMMARY_VERSION=C3\.1_DEVICE_POLICY_SUMMARY_CHECK_ID") {
        throw "C2.4 CHECK failed: missing C3.1 CHECK_ID summary version"
    }

    if ($checkResponse -notmatch "(?m)^CHECK_ID=[0-9a-f]{64}\s*$") {
        throw "C3.1 CHECK failed: missing or malformed CHECK_ID"
    }

    if ($checkResponse -notmatch "SUMMARY_END") {
        throw "C2.4 CHECK failed: missing SUMMARY_END"
    }

    if ($checkResponse -match "RAW_TX=") {
        throw "C2.4 CHECK failed: CHECK returned RAW_TX"
    }

    if ($checkResponse -notmatch "SIGNATURE_PRODUCED=0") {
        throw "C2.4 CHECK failed: missing SIGNATURE_PRODUCED=0"
    }

    if ($checkResponse -notmatch "POLICY_DECISION=APPROVED") {
        Write-Host ""
        Write-Host "HOST_TX_GENERATOR_FAIL"
        Write-Host "CONFIRMATION_RESULT_BEGIN"
        Write-Host "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK"
        $checkErr = [regex]::Match($checkResponse, "ERR POLICY -?\d+")
        if ($checkErr.Success) {
            Write-Host "DEVICE_ERROR=$($checkErr.Value)"
        } else {
            Write-Host "DEVICE_ERROR=CHECK_REJECTED_WITHOUT_ERR_POLICY"
        }
        Write-Host "RAW_TX_PRESENT=0"
        Write-Host "SIGN_SENT=0"
        Write-Host "NO_SIGN_SENT"
        Write-Host "CONFIRMATION_RESULT_END"
        exit 2
    }

    $confirmCodeMatch = [regex]::Match($checkResponse, "(?m)^CONFIRM_CODE=(\d{6})\s*$")
    if (-not $confirmCodeMatch.Success) {
        throw "C3.5 CHECK failed: approved CHECK missing or malformed CONFIRM_CODE"
    }
    $deviceConfirmCode = $confirmCodeMatch.Groups[1].Value

    # C2.5: Exact CHECK summary binding.
    # The host must prove the device CHECK summary matches the exact
    # candidate transaction fields before it is allowed to send SIGN.
    function Get-GeneratedCommandField {
        param(
            [string[]] $Lines,
            [string] $Name
        )

        foreach ($line in $Lines) {
            if ($line -match ("^" + [regex]::Escape($Name) + "=(.*)$")) {
                return $Matches[1].Trim()
            }
        }

        $alias = Get-CommandFieldAlias -Name $Name
        if ($alias -ne "") {
            foreach ($line in $Lines) {
                if ($line -match ("^" + [regex]::Escape($alias) + "=(.*)$")) {
                    return $Matches[1].Trim()
                }
            }
        }

        throw "C2.5 CHECK failed: generated command missing $Name"
    }

    function Get-DeviceSummaryField {
        param(
            [string] $Text,
            [string] $Name
        )

        $m = [regex]::Match($Text, "(?m)^" + [regex]::Escape($Name) + "=(.*)\r?$")
        if (-not $m.Success) {
            throw "C2.5 CHECK failed: device summary missing $Name"
        }

        return $m.Groups[1].Value.Trim()
    }

    function Assert-DeviceSummaryField {
        param(
            [string] $Name,
            [string] $Expected
        )

        $actual = Get-DeviceSummaryField -Text $checkResponse -Name $Name

        if ($actual -ne $Expected) {
            Write-Host ""
            Write-Host "HOST_TX_GENERATOR_FAIL"
            Write-Host "CONFIRMATION_RESULT_BEGIN"
            Write-Host "POLICY_DECISION=REJECTED_BY_HOST_CHECK_BINDING"
            Write-Host "DEVICE_FIELD=$Name"
            Write-Host "EXPECTED=$Expected"
            Write-Host "ACTUAL=$actual"
            Write-Host "RAW_TX_PRESENT=0"
            Write-Host "SIGN_SENT=0"
            Write-Host "NO_SIGN_SENT"
            Write-Host "CONFIRMATION_RESULT_END"
            throw "C2.5 CHECK failed: summary field $Name mismatch"
        }
    }

    $expectedNetwork = Get-GeneratedCommandField -Lines $cmdLines -Name "NETWORK"
    $expectedSpendScript = Get-GeneratedCommandField -Lines $cmdLines -Name "PREV_SCRIPT"
    $expectedPayScript = Get-GeneratedCommandField -Lines $cmdLines -Name "PAY_SCRIPT"
    $expectedPaySats = Get-GeneratedCommandField -Lines $cmdLines -Name "PAY_SATS"
    $expectedChangeScript = Get-GeneratedCommandField -Lines $cmdLines -Name "CHANGE_SCRIPT"
    $expectedChangeSats = Get-GeneratedCommandField -Lines $cmdLines -Name "CHANGE_SATS"

    $expectedInputCount = 1
    if ($CommandFormat -eq "PsbtLike") {
        $expectedInputCount = [uint32](Get-GeneratedCommandField -Lines $cmdLines -Name "INPUT_COUNT")
    }
    $expectedInputSats = [uint64](Get-GeneratedCommandField -Lines $cmdLines -Name "INPUT_SATS")
    $expectedInput1Sats = 0
    if ($expectedInputCount -eq 2) {
        $expectedInput1Sats = [uint64](Get-GeneratedCommandField -Lines $cmdLines -Name "PSBT_INPUT1_SATS")
    }
    $expectedTotalInputSats = $expectedInputSats + $expectedInput1Sats
    $expectedPaySatsU64 = [uint64]$expectedPaySats
    $expectedChangeSatsU64 = [uint64]$expectedChangeSats

    if ($expectedTotalInputSats -lt ($expectedPaySatsU64 + $expectedChangeSatsU64)) {
        throw "C2.5 CHECK failed: host candidate amount underflow"
    }

    $expectedFeeSats = [string]($expectedTotalInputSats - $expectedPaySatsU64 - $expectedChangeSatsU64)

    $expectedTxidLe = Get-GeneratedCommandField -Lines $cmdLines -Name "TXID_LE"
    $expectedVout = Get-GeneratedCommandField -Lines $cmdLines -Name "VOUT"
    $expectedInputSatsText = Get-GeneratedCommandField -Lines $cmdLines -Name "INPUT_SATS"

    $bindingExpected = [ordered]@{
        SUMMARY_VERSION = "C3.1_DEVICE_POLICY_SUMMARY_CHECK_ID"
        INPUT_COUNT = [string]$expectedInputCount
        INPUT_TXID_LE = $expectedTxidLe
        INPUT_VOUT = $expectedVout
        INPUT_SATS = $expectedInputSatsText
        NETWORK = $expectedNetwork
        SPEND_FROM_SCRIPT = $expectedSpendScript
        TOTAL_INPUT_SATS = [string]$expectedTotalInputSats
        PAY_TO_SCRIPT = $expectedPayScript
        PAY_SATS = $expectedPaySats
        CHANGE_TO_SCRIPT = $expectedChangeScript
        CHANGE_SATS = $expectedChangeSats
        FEE_SATS = $expectedFeeSats
        POLICY_DECISION = "APPROVED"
        SIGNATURE_PRODUCED = "0"
    }

    if ($expectedInputCount -eq 2) {
        $bindingExpected.INPUT1_TXID_LE = Get-GeneratedCommandField -Lines $cmdLines -Name "PSBT_INPUT1_TXID_LE"
        $bindingExpected.INPUT1_VOUT = Get-GeneratedCommandField -Lines $cmdLines -Name "PSBT_INPUT1_VOUT"
        $bindingExpected.INPUT1_SATS = Get-GeneratedCommandField -Lines $cmdLines -Name "PSBT_INPUT1_SATS"
        $bindingExpected.INPUT1_PREV_SCRIPT = Get-GeneratedCommandField -Lines $cmdLines -Name "PSBT_INPUT1_PREV_SCRIPT"
    }

    if ($CheckBindingTamperField -ne "") {
        if (-not $bindingExpected.Contains($CheckBindingTamperField)) {
            throw "C2.8 tamper failed: unknown field $CheckBindingTamperField"
        }

        if ($CheckBindingTamperValue -eq "") {
            $CheckBindingTamperValue = "__C2_8_TAMPERED_VALUE__"
        }

        Write-Host "C2_8_HOST_CHECK_BINDING_TAMPER_BEGIN"
        Write-Host "TAMPER_FIELD=$CheckBindingTamperField"
        Write-Host "TAMPER_EXPECTED_ORIGINAL=$($bindingExpected[$CheckBindingTamperField])"
        Write-Host "TAMPER_EXPECTED_MUTATED=$CheckBindingTamperValue"
        Write-Host "C2_8_HOST_CHECK_BINDING_TAMPER_END"
        $bindingExpected[$CheckBindingTamperField] = $CheckBindingTamperValue
    }

    foreach ($key in $bindingExpected.Keys) {
        Assert-DeviceSummaryField -Name $key -Expected $bindingExpected[$key]
    }

    $c27Mappings = @(
        @{ Name = "NETWORK"; Transcript = $Network; DeviceField = "NETWORK"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "NETWORK" },
        @{ Name = "TXID_LE"; Transcript = $TxidLe; DeviceField = "INPUT_TXID_LE"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "TXID_LE" },
        @{ Name = "VOUT"; Transcript = [string]$Vout; DeviceField = "INPUT_VOUT"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "VOUT" },
        @{ Name = "INPUT_SATS"; Transcript = [string]$InputSats; DeviceField = "INPUT_SATS"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "INPUT_SATS" },
        @{ Name = "PREV_SCRIPT"; Transcript = $PrevScript; DeviceField = "SPEND_FROM_SCRIPT"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "PREV_SCRIPT" },
        @{ Name = "PAY_SCRIPT"; Transcript = $PayScript; DeviceField = "PAY_TO_SCRIPT"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "PAY_SCRIPT" },
        @{ Name = "PAY_SATS"; Transcript = [string]$PaySats; DeviceField = "PAY_SATS"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "PAY_SATS" },
        @{ Name = "CHANGE_SCRIPT"; Transcript = $ChangeScript; DeviceField = "CHANGE_TO_SCRIPT"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "CHANGE_SCRIPT" },
        @{ Name = "CHANGE_SATS"; Transcript = [string]$ChangeSats; DeviceField = "CHANGE_SATS"; Sign = Get-GeneratedCommandField -Lines $cmdLines -Name "CHANGE_SATS" },
        @{ Name = "FEE_SATS"; Transcript = $expectedFeeSats; DeviceField = "FEE_SATS"; Sign = $expectedFeeSats }
    )

    Write-Host "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_BEGIN"
    foreach ($m in $c27Mappings) {
        $deviceValue = Get-DeviceSummaryField -Text $checkResponse -Name $m.DeviceField
        if (($m.Transcript -ne $deviceValue) -or ($m.Transcript -ne $m.Sign)) {
            throw "C2.7 consistency failed for $($m.Name): transcript=$($m.Transcript) device=$deviceValue sign=$($m.Sign)"
        }
        Write-Host "C2_7_FIELD_MATCH NAME=$($m.Name) HOST_TRANSCRIPT=$($m.Transcript) DEVICE_CHECK_SUMMARY=$deviceValue SIGN_COMMAND=$($m.Sign)"
    }
    Write-Host "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_PASS"
    Write-Host "C2_7_TRANSCRIPT_CHECK_SIGN_CONSISTENCY_END"

    Write-Host "DEVICE_CHECK_SUMMARY_EXACT_MATCH_PASS"
    Write-Host "DEVICE_CHECK_POLICY_DECISION=APPROVED"
    Write-Host "DEVICE_CHECK_RAW_TX_PRESENT=0"
    Write-Host "DEVICE_CHECK_SIGNATURE_PRODUCED=0"
    Write-Host "DEVICE_CHECK_BEFORE_SIGN_PASS"

    Write-Host ""
    Write-Host "--- CLEAR BUFFER AFTER CHECK BEFORE SIGN ---"
    $serial.DiscardInBuffer()
    Start-Sleep -Milliseconds 100
    $postCheckClear = Read-SerialForDuration -Serial $serial -Milliseconds 300
    if ($postCheckClear.Trim().Length -gt 0) {
        Write-Host $postCheckClear
    }
    Write-Host ""
    Write-Host "--- C3.5 DEVICE CONFIRM CODE BEFORE SIGN ---"
    Write-Host ">> CONFIRM_CODE=$deviceConfirmCode"
    $serial.WriteLine("CONFIRM_CODE=$deviceConfirmCode")
    Start-Sleep -Milliseconds 80

    $confirmResponse = Read-UntilConfirmResponse -Serial $serial -TimeoutSeconds 15
    Write-Host $confirmResponse

    if ($confirmResponse -notmatch "OK CONFIRM") {
        Write-Host ""
        Write-Host "HOST_TX_GENERATOR_FAIL"
        Write-Host "CONFIRMATION_RESULT_BEGIN"
        Write-Host "POLICY_DECISION=REJECTED_BY_DEVICE_CONFIRM"
        $confirmErr = [regex]::Match($confirmResponse, "ERR POLICY -?\d+")
        if ($confirmErr.Success) {
            Write-Host "DEVICE_ERROR=$($confirmErr.Value)"
        } else {
            Write-Host "DEVICE_ERROR=CONFIRM_REJECTED_WITHOUT_ERR_POLICY"
        }
        Write-Host "RAW_TX_PRESENT=0"
        Write-Host "SIGN_SENT=0"
        Write-Host "NO_SIGN_SENT"
        Write-Host "CONFIRMATION_RESULT_END"
        exit 2
    }

    Write-Host "DEVICE_CONFIRM_BEFORE_SIGN_PASS"

    Write-Host ""
    Write-Host "--- SEND SIGN COMMAND LINE BY LINE ---"

    foreach ($line in $cmdLines) {
        Write-Host ">> $line"
        $serial.WriteLine($line)
        Start-Sleep -Milliseconds $commandLineDelayMs
    }

    Write-Host ""
    Write-Host "--- WALLET RESPONSE ---"

    $response = Read-UntilCommandResponse -Serial $serial -TimeoutSeconds $TimeoutSeconds
    Write-Host $response

    if ($response -match "(ERR (POLICY|KEYPROVIDER) -?\d+)") {
        $err = $Matches[1]

        Write-Host ""
        Write-Host "--- WALLET ERROR ---"
        Write-Host $err
        Write-Host ""
        Write-Host "HOST_TX_GENERATOR_FAIL"
        Write-Host "CONFIRMATION_RESULT_BEGIN"
        Write-Host "POLICY_DECISION=REJECTED_BY_DEVICE"
        Write-Host "DEVICE_ERROR=$err"
        Write-Host "RAW_TX_PRESENT=0"
        Write-Host "CONFIRMATION_RESULT_END"

        # Expected wallet policy rejections should be machine-readable,
        # not PowerShell stack traces.
        exit 2
    }

    $rawMatch = [regex]::Match($response, "RAW_TX=([0-9a-fA-F]+)")

    if (-not $rawMatch.Success) {
        Write-Host ""
        Write-Host "--- FULL POST-SIGN CAPTURED WALLET RESPONSE ---"
        Write-Host $response
        Write-Host ""
        Write-Host "HOST_TX_GENERATOR_FAIL"

        throw "No RAW_TX found in post-SIGN wallet response"
    }

    $rawTx = $rawMatch.Groups[1].Value

    if ($RawTxOutFile -ne "") {
        Set-Content -Path $RawTxOutFile -Value $rawTx -Encoding ascii
        Write-Host ""
        Write-Host "RAW_TX_OUT_FILE=$RawTxOutFile"
    }

    Write-Host ""
    Write-Host "RAW_TX=$rawTx"
    Write-Host "CONFIRMATION_RESULT_BEGIN"
    Write-Host "POLICY_DECISION=APPROVED_AND_SIGNED"
    Write-Host "RAW_TX_PRESENT=1"
    Write-Host "CONFIRMATION_RESULT_END"
    Write-Host "HOST_TX_GENERATOR_PASS"
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}





