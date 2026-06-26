param(
    [string]$Port = "COM3",
    [int]$Baud = 115200
)

try {
    if ($sp -ne $null) {
        if ($sp.IsOpen) { $sp.Close() }
        $sp.Dispose()
    }
} catch {}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, None, 8, One
$sp.ReadTimeout = 5000
$sp.WriteTimeout = 5000
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.Open()

function Wait-Ready {
    $ready = ""
    $deadline = (Get-Date).AddSeconds(45)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $chunk = $sp.ReadExisting()

        if ($chunk.Length -gt 0) {
            $ready += $chunk
            $ready
        }

        if ($ready -match "READY" -and $ready -match ">") {
            Start-Sleep -Milliseconds 500
            $null = $sp.ReadExisting()
            return $true
        }

        if ($ready -match "ERR SECURE_ELEMENT_INIT") {
            return $false
        }
    }

    return $false
}

function Send-Lines {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    "`r`n--- $Name ---"

    foreach ($line in $Lines) {
        $sp.Write($line + "`r`n")
        Start-Sleep -Milliseconds 80
    }

    $out = ""
    $deadline = (Get-Date).AddSeconds(45)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $chunk = $sp.ReadExisting()

        if ($chunk.Length -gt 0) {
            $out += $chunk
            $out
        }

        if ($out -match "RAW_TX=" -or
            $out -match "ERR " -or
            $out -match "READY") {
            break
        }
    }

    Start-Sleep -Seconds 1
    $out += $sp.ReadExisting()
    $out
}

function Send-Seinfo {
    param([string]$Name)
    Send-Lines -Name $Name -Lines @("SEINFO")
}

function Get-AuthCount {
    param([string]$Text)

    $m = [regex]::Match($Text, "AUTH_COUNT=(\d+)")
    if ($m.Success) {
        return [int]$m.Groups[1].Value
    }

    return -1
}

if (-not (Wait-Ready)) {
    "BOARD DID NOT REACH READY"
    $sp.Close()
    $sp.Dispose()
    exit 1
}

$seinfo_before = Send-Seinfo "SEINFO BEFORE FULL POLICY REGRESSION"
$auth_before = Get-AuthCount $seinfo_before

$policyinfo = Send-Lines -Name "TEST 01 POLICYINFO EXPECT OK POLICYINFO" -Lines @(
"POLICYINFO"
)

$normal = Send-Lines -Name "TEST 02 NORMAL REGTEST EXPECT OK RAW_TX" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$missing_network = Send-Lines -Name "TEST 03 MISSING NETWORK EXPECT ERR POLICY -42" -Lines @(
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$wrong_network = Send-Lines -Name "TEST 04 WRONG NETWORK EXPECT ERR POLICY -42" -Lines @(
"NETWORK=MAINNET",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$privkey = Send-Lines -Name "TEST 05 PRIVKEY INJECTION EXPECT ERR KEYPOLICY -21" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"PRIVKEY=0000000000000000000000000000000000000000000000000000000000000001",
"SIGN"
)

$high_fee = Send-Lines -Name "TEST 06 HIGH FEE EXPECT ERR POLICY -35" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=10000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=10000",
"SIGN"
)

$bad_script = Send-Lines -Name "TEST 07 BAD SCRIPT EXPECT ERR POLICY -37" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=6a",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$bad_pay = Send-Lines -Name "TEST 08 BAD PAY EXPECT ERR POLICY -38" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$bad_change = Send-Lines -Name "TEST 09 BAD CHANGE EXPECT ERR POLICY -39" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"CHANGE_SATS=30000",
"SIGN"
)

$bad_input = Send-Lines -Name "TEST 10 BAD INPUT EXPECT ERR POLICY -40" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=60000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=30000",
"SIGN"
)

$pay_too_high = Send-Lines -Name "TEST 11 PAY TOO HIGH EXPECT ERR POLICY -41" -Lines @(
"NETWORK=REGTEST",
"TXID_LE=c2bd530ed9d7e40ba47027e8ffee41aa5b62c0ba36e5c20003ca63309dad31c8",
"VOUT=1",
"INPUT_SATS=100000",
"PREV_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"PAY_SCRIPT=76a914f2124d94cabdb95d49479627cbbe5d7be609f73888ac",
"PAY_SATS=80000",
"CHANGE_SCRIPT=76a914751e76e8199196d454941c45d1b3a323f1433bd688ac",
"CHANGE_SATS=10000",
"SIGN"
)

$seinfo_after = Send-Seinfo "SEINFO AFTER FULL POLICY REGRESSION"
$auth_after = Get-AuthCount $seinfo_after

"`r`n--- SUMMARY ---"

$checks = @(
    @("POLICYINFO works",              ([string]$policyinfo -match "OK POLICYINFO")),
    @("POLICYINFO shows REGTEST",      ([string]$policyinfo -match "NETWORK_REQUIRED=REGTEST")),
    @("POLICYINFO shows max fee",      ([string]$policyinfo -match "MAX_FEE_SATS=20000")),
    @("POLICYINFO shows max pay",      ([string]$policyinfo -match "MAX_PAY_SATS=70000")),
    @("Normal signs",                  ([string]$normal -match "RAW_TX=")),
    @("Missing network rejected -42",  ([string]$missing_network -match "ERR POLICY -42")),
    @("Wrong network rejected -42",    ([string]$wrong_network -match "ERR POLICY -42")),
    @("PRIVKEY rejected -21",          ([string]$privkey -match "ERR KEYPOLICY -21")),
    @("High fee rejected -35",         ([string]$high_fee -match "ERR POLICY -35")),
    @("Bad script rejected -37",       ([string]$bad_script -match "ERR POLICY -37")),
    @("Bad pay rejected -38",          ([string]$bad_pay -match "ERR POLICY -38")),
    @("Bad change rejected -39",       ([string]$bad_change -match "ERR POLICY -39")),
    @("Bad input rejected -40",        ([string]$bad_input -match "ERR POLICY -40")),
    @("Pay too high rejected -41",     ([string]$pay_too_high -match "ERR POLICY -41")),
    @("AUTH_COUNT before parsed",      ($auth_before -ge 0)),
    @("AUTH_COUNT after parsed",       ($auth_after -ge 0)),
    @("AUTH_COUNT increased by only 1",(($auth_before -ge 0) -and ($auth_after -eq ($auth_before + 1))))
)

$all_ok = $true

foreach ($check in $checks) {
    $name = $check[0]
    $ok = [bool]$check[1]

    "{0}: {1}" -f $name, $ok

    if (-not $ok) {
        $all_ok = $false
    }
}

"`r`nAUTH_COUNT_BEFORE=$auth_before"
"AUTH_COUNT_AFTER=$auth_after"

if ($all_ok) {
    "`r`nFULL_POLICY_REGRESSION_PASS"
} else {
    "`r`nFULL_POLICY_REGRESSION_FAIL"
}

$sp.Close()
$sp.Dispose()

if (-not $all_ok) {
    exit 1
}
