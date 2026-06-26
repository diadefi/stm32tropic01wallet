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

    Write-Host "${Name}_AUTH_UNCHANGED before=$Before after=$After"
}

function Open-WalletSerial {
    param(
        [string]$Port,
        [int]$Baud
    )

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
        if ($Serial.IsOpen) {
            $Serial.Close()
        }
        $Serial.Dispose()
    }
}

function Invoke-HostNetworkReject {
    param(
        [string]$Network,
        [string]$Name
    )

    Write-Host ""
    Write-Host "--- C7.0 HOST $Network CHECK REJECTS BEFORE SIGN ---"

    $baseArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Generator,
        "-Port", $Port,
        "-Network", $Network,
        "-TxidLe", "09f6ce894fc3f8c5de72f787386039a54eeb2aded45b4087fc0992e40023a632",
        "-Vout", "1",
        "-InputSats", "100000",
        "-PaySats", "60000",
        "-ChangeSats", "30000",
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
        throw "$Name failed: host generator unexpectedly exited 0"
    }

    Assert-Contains $joined "HOST_TX_GENERATOR_FAIL"
    Assert-Contains $joined "POLICY_DECISION=REJECTED_BY_DEVICE_CHECK"
    Assert-Contains $joined "DEVICE_ERROR=ERR POLICY -42"
    Assert-Contains $joined "RAW_TX_PRESENT=0"
    Assert-Contains $joined "SIGN_SENT=0"
    Assert-Contains $joined "NO_SIGN_SENT"
    Assert-NoRawTx $joined $Name

    if ($joined -match "--- SEND SIGN COMMAND LINE BY LINE ---" -or
        $joined -match "(?m)^>> SIGN\r?$") {
        throw "$Name failed: SIGN command was sent"
    }

    if ($Name -eq "C7_0_TESTNET") {
        Write-Host "C7_0_TESTNET_HOST_NO_SIGN_PASS"
    } elseif ($Name -eq "C7_0_MAINNET") {
        Write-Host "C7_0_MAINNET_HOST_NO_SIGN_PASS"
    } else {
        Write-Host "${Name}_HOST_NO_SIGN_PASS"
    }
    $global:LASTEXITCODE = 0
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
    Write-Host " STM32 C7.0 REAL NETWORK SAFETY REGRESSION"
    Write-Host "============================================================"
    Write-Host "Port: $Port"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud

    Write-Host ""
    Write-Host "--- C7.0 VERSION/POLICYINFO REAL NETWORK LABELS ---"
    $version = Send-CommandLines -Serial $serial -Lines @("VERSION") -RequiredPattern "REAL_BITCOIN_SIGNING_ENABLED=0" -TimeoutSeconds $TimeoutSeconds
    Write-Host $version
    Assert-Contains $version "REAL_BITCOIN_STAGE="
    Assert-Contains $version "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $version "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $version "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $version "MAINNET_SIGNING_ENABLED=0"

    $policy = Send-CommandLines -Serial $serial -Lines @("POLICYINFO") -RequiredPattern "REAL_BITCOIN_SIGNING_ENABLED=0" -TimeoutSeconds $TimeoutSeconds
    Write-Host $policy
    Assert-Contains $policy "REAL_BITCOIN_STAGE="
    Assert-Contains $policy "NETWORK_REQUIRED=REGTEST"
    Assert-Contains $policy "NETWORK_ALLOWED=REGTEST"
    Assert-Contains $policy "REAL_BITCOIN_SIGNING_ENABLED=0"
    Assert-Contains $policy "TESTNET_SIGNING_ENABLED=0"
    Assert-Contains $policy "MAINNET_SIGNING_ENABLED=0"
    Write-Host "C7_0_REAL_NETWORK_LABELS_PASS"

    $authBefore = Get-AuthCount -Serial $serial

    foreach ($network in @("TESTNET", "MAINNET")) {
        Write-Host ""
        Write-Host "--- C7.0 DEVICE $network CHECK REJECT ---"
        $check = Send-CommandLines -Serial $serial -Lines (@("NETWORK=$network") + $validFields + @("CHECK")) -RequiredPattern "ERR POLICY -42" -TimeoutSeconds $TimeoutSeconds
        Write-Host $check
        Assert-Contains $check "POLICY_DECISION=REJECTED"
        Assert-Contains $check "DEVICE_ERROR=ERR POLICY -42"
        Assert-Contains $check "SIGNATURE_PRODUCED=0"
        Assert-NoRawTx $check "DEVICE_${network}_CHECK"
        if ($network -eq "TESTNET") {
            Write-Host "C7_0_DEVICE_TESTNET_CHECK_REJECT_PASS"
        } elseif ($network -eq "MAINNET") {
            Write-Host "C7_0_DEVICE_MAINNET_CHECK_REJECT_PASS"
        }
    }

    $authAfterChecks = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authBefore -After $authAfterChecks -Name "C7_0_REAL_NETWORK_CHECKS"

    Close-WalletSerial -Serial $serial
    $serial = $null

    Invoke-HostNetworkReject -Network "TESTNET" -Name "C7_0_TESTNET"
    Invoke-HostNetworkReject -Network "MAINNET" -Name "C7_0_MAINNET"

    $serial = Open-WalletSerial -Port $Port -Baud $Baud
    $authAfterHost = Get-AuthCount -Serial $serial
    Assert-AuthUnchanged -Before $authAfterChecks -After $authAfterHost -Name "C7_0_HOST_REAL_NETWORK_REJECTS"

    Write-Host ""
    Write-Host "C7_0_REAL_NETWORK_SAFETY_REGRESSION_PASS"
    exit 0
}
finally {
    Close-WalletSerial -Serial $serial
}
