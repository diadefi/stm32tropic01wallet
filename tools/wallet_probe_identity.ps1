param(
    [string]$Port = "COM3",
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"

$ExpectedAddress = "mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r"
$ExpectedPubkey  = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
$ExpectedScript  = "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac"
$ExpectedModel   = "KDF_AES_GCM_WRAPPED_SECP256K1_KEY_BLOB_TROPIC_AUTH_GATE"

function Read-Available {
    param([System.IO.Ports.SerialPort]$Serial)

    $s = ""
    while ($Serial.BytesToRead -gt 0) {
        $s += $Serial.ReadExisting()
        Start-Sleep -Milliseconds 20
    }
    return $s
}

function Send-Command {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Command,
        [int]$TimeoutSeconds
    )

    Write-Host ""
    Write-Host "--- UART $Command ---"

    $Serial.DiscardInBuffer()
    $Serial.WriteLine($Command)

    $buf = ""
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        $buf += Read-Available -Serial $Serial

        if ($buf -match "READY") {
            Write-Host $buf
            return $buf
        }

        Start-Sleep -Milliseconds 50
    }

    Write-Host $buf
    throw "Timeout waiting for READY after $Command"
}

$serial = $null

try {
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

    Start-Sleep -Milliseconds 1200
    $startup = Read-Available -Serial $serial

    Write-Host ""
    Write-Host "--- UART STARTUP ---"
    if ($startup.Length -gt 0) {
        Write-Host $startup
    } else {
        Write-Host "(none)"
    }

    $version  = Send-Command -Serial $serial -Command "VERSION"  -TimeoutSeconds $TimeoutSeconds
    $identity = Send-Command -Serial $serial -Command "IDENTITY" -TimeoutSeconds $TimeoutSeconds
    $addr     = Send-Command -Serial $serial -Command "ADDR"     -TimeoutSeconds $TimeoutSeconds
    $pubkey   = Send-Command -Serial $serial -Command "PUBKEY"   -TimeoutSeconds $TimeoutSeconds
    $script   = Send-Command -Serial $serial -Command "SCRIPT"   -TimeoutSeconds $TimeoutSeconds

    if ($version -match "VERSION=([^\r\n]+)") {
        Write-Host ""
        Write-Host "APP_VERSION_SEEN=$($Matches[1])"
    } else {
        Write-Host ""
        Write-Host "APP_VERSION_SEEN=(none)"
    }

    # C2.0 identity validation is based on the IDENTITY command below.
    # Do not fail only because the cosmetic app VERSION string was not updated.

    if ($identity -notmatch "OK IDENTITY") { throw "Missing OK IDENTITY" }
    if ($identity -notmatch "IDENTITY_VERSION=C2.0_DEVICE_IDENTITY_REPORTING") { throw "IDENTITY_VERSION mismatch" }
    if ($identity -notmatch "ADDRESS=$ExpectedAddress") { throw "IDENTITY address mismatch" }
    if ($identity -notmatch "PUBKEY_COMPRESSED=$ExpectedPubkey") { throw "IDENTITY pubkey mismatch" }
    if ($identity -notmatch "SCRIPT_P2PKH=$ExpectedScript") { throw "IDENTITY script mismatch" }
    if ($identity -notmatch "CURRENT_BITCOIN_KEY_MODEL=$ExpectedModel") { throw "IDENTITY key model mismatch" }
    if ($identity -notmatch "CURRENT_DEV_KEY_ENABLED=0") { throw "IDENTITY dev key flag mismatch" }

    if ($addr -notmatch "OK ADDR") { throw "Missing OK ADDR" }
    if ($addr -notmatch "ADDRESS=$ExpectedAddress") { throw "ADDR address mismatch" }
    if ($addr -notmatch "SCRIPT_P2PKH=$ExpectedScript") { throw "ADDR script mismatch" }

    if ($pubkey -notmatch "OK PUBKEY") { throw "Missing OK PUBKEY" }
    if ($pubkey -notmatch "PUBKEY_COMPRESSED=$ExpectedPubkey") { throw "PUBKEY mismatch" }

    if ($script -notmatch "OK SCRIPT") { throw "Missing OK SCRIPT" }
    if ($script -notmatch "SCRIPT_P2PKH=$ExpectedScript") { throw "SCRIPT mismatch" }

    Write-Host ""
    Write-Host "IDENTITY_PROBE_PASS"
}
finally {
    if ($serial -ne $null) {
        if ($serial.IsOpen) {
            $serial.Close()
        }
        $serial.Dispose()
    }
}

