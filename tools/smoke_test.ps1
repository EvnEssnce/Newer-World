# Automated networking check: a headless server and two headless bot clients run
# for a few seconds: each client must see the other move, dodge, attack, and the
# server must resolve hits, all without prediction corrections.
#   powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1
# Exits 0 on pass, 1 on fail. Logs go to build\smoke\.
param([int]$Port = 24599, [int]$Seconds = 8)
. "$PSScriptRoot\find_godot.ps1"

$logDir = Join-Path $ProjectRoot 'build\smoke'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Start-Godot([string]$name, [string[]]$gameArgs) {
    Start-Process $Godot -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru `
        -ArgumentList (@('--headless', '--') + $gameArgs) `
        -RedirectStandardOutput (Join-Path $logDir "$name.log") `
        -RedirectStandardError (Join-Path $logDir "$name.err.log")
}

$server = Start-Godot 'server' @('--server', '--verbose', "--port=$Port", "--quit-after=$($Seconds + 2)")
Start-Sleep -Seconds 1
$clients = @(
    (Start-Godot 'client1' @('--bot', "--address=127.0.0.1:$Port", "--quit-after=$Seconds")),
    (Start-Godot 'client2' @('--bot', "--address=127.0.0.1:$Port", "--quit-after=$Seconds"))
)
$clients | ForEach-Object { $_.WaitForExit() }
# The server quits on its own shortly after the clients, printing its summary.
if (-not $server.WaitForExit(10000)) { Stop-Process -Id $server.Id -Force }

$failed = $false
# The bots fight for the first 3.5 s of every 6; the server must resolve real hits.
$serverSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY server .*hits=(\d+)'
if (-not $serverSummary -or [int]$serverSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL server: no hits resolved ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS server: $($serverSummary.Line)" -ForegroundColor Green
}
foreach ($name in 'client1', 'client2') {
    $summary = Select-String -Path (Join-Path $logDir "$name.log") -Pattern '^SUMMARY client=\d+ remote=\d+ moved=([\d.]+)'
    if (-not $summary) {
        Write-Host "FAIL ${name}: never saw another player" -ForegroundColor Red
        $failed = $true
    } elseif ([double]$summary.Matches[0].Groups[1].Value -lt 1.0) {
        Write-Host "FAIL ${name}: saw another player but it didn't move ($($summary.Line))" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "PASS ${name}: $($summary.Line)" -ForegroundColor Green
    }
    # The bot dodges on the ground and in the air, and attacks. Prediction must match the server.
    $local = Select-String -Path (Join-Path $logDir "$name.log") -Pattern '^SUMMARY client=\d+ snapshots=\d+ corrections=(\d+) dodges=(\d+) air_dodges=(\d+) attacks=(\d+)'
    if (-not $local) {
        Write-Host "FAIL ${name}: no local player summary" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[2].Value -lt 1 -or [int]$local.Matches[0].Groups[3].Value -lt 1) {
        Write-Host "FAIL ${name}: bot didn't dodge on the ground and in the air ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[4].Value -lt 1) {
        Write-Host "FAIL ${name}: bot never attacked ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[1].Value -gt 2) {
        Write-Host "FAIL ${name}: prediction disagreed with the server ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "PASS ${name}: $($local.Line)" -ForegroundColor Green
    }
}
$errors = Get-ChildItem $logDir -Filter '*.err.log' | Select-String -Pattern 'ERROR|SCRIPT ERROR'
if ($errors) {
    Write-Host "Errors were logged:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "  $($_.Filename): $($_.Line)" }
    $failed = $true
}
if ($failed) { exit 1 }
Write-Host "Smoke test passed." -ForegroundColor Green
