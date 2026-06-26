param(
    [string]$BitcoinCli = "C:\Program Files\Bitcoin\daemon\bitcoin-cli.exe",
    [string]$RawTxFile = ".\tools\last_raw_tx.txt",
    [switch]$NoBroadcast
)

$ErrorActionPreference = "Stop"

function Run-BitcoinCli {
    param(
        [string[]]$ArgsList
    )

    Write-Host ""
    Write-Host ("bitcoin-cli -regtest " + ($ArgsList -join " "))

    $out = & $BitcoinCli -regtest @ArgsList

    if ($LASTEXITCODE -ne 0) {
        throw "bitcoin-cli failed with exit code $LASTEXITCODE"
    }

    return $out
}

function Run-BitcoinCli-OneStdinArg {
    param(
        [string]$Command,
        [string]$StdinArg
    )

    Write-Host ""
    Write-Host ("bitcoin-cli -regtest -stdin " + $Command)
    Write-Host ("STDIN_ARG=" + $StdinArg)

    $out = $StdinArg | & $BitcoinCli -regtest -stdin $Command

    if ($LASTEXITCODE -ne 0) {
        throw "bitcoin-cli -stdin failed with exit code $LASTEXITCODE"
    }

    return $out
}

if (-not (Test-Path $RawTxFile)) {
    throw "Raw tx file not found: $RawTxFile"
}

$rawTx = (Get-Content $RawTxFile -Raw).Trim()

if ($rawTx.Length -eq 0) {
    throw "Raw tx file is empty: $RawTxFile"
}

Write-Host ""
Write-Host "--- RAW TX ---"
Write-Host $rawTx

Write-Host ""
Write-Host "--- DECODE RAW TRANSACTION ---"
$decoded = Run-BitcoinCli -ArgsList @("decoderawtransaction", $rawTx)
$decoded | Write-Host

Write-Host ""
Write-Host "--- TEST MEMPOOL ACCEPT ---"

$testArg = '["' + $rawTx + '"]'

$testOut = Run-BitcoinCli-OneStdinArg `
    -Command "testmempoolaccept" `
    -StdinArg $testArg

$testOut | Write-Host

$testJson = ($testOut | Out-String) | ConvertFrom-Json
$allowed = $testJson[0].allowed

if ($allowed -ne $true) {
    Write-Host ""
    Write-Host "REGTEST_MEMPOOL_REJECTED"

    if ($testJson[0]."reject-reason") {
        Write-Host ("REJECT_REASON=" + $testJson[0]."reject-reason")
    }

    if ($testJson[0]."package-error") {
        Write-Host ("PACKAGE_ERROR=" + $testJson[0]."package-error")
    }

    exit 1
}

Write-Host ""
Write-Host "REGTEST_MEMPOOL_ACCEPTED"

if ($NoBroadcast) {
    Write-Host ""
    Write-Host "NO_BROADCAST_REQUESTED"
    exit 0
}

Write-Host ""
Write-Host "--- SEND RAW TRANSACTION ---"
$txid = Run-BitcoinCli -ArgsList @("sendrawtransaction", $rawTx)
$txid = ($txid | Out-String).Trim()

Write-Host ""
Write-Host "BROADCAST_TXID=$txid"

Write-Host ""
Write-Host "--- MINE ONE BLOCK ---"
$miningAddress = Run-BitcoinCli -ArgsList @("getnewaddress", "stm32-wallet-mining", "bech32")
$miningAddress = ($miningAddress | Out-String).Trim()

$mineOut = Run-BitcoinCli -ArgsList @("generatetoaddress", "1", $miningAddress)
$mineOut | Write-Host

Write-Host ""
Write-Host "--- CONFIRM TRANSACTION ---"
$getTxOut = Run-BitcoinCli -ArgsList @("gettransaction", $txid)
$getTxOut | Write-Host

Write-Host ""
Write-Host "REGTEST_BROADCAST_AND_MINE_PASS"
