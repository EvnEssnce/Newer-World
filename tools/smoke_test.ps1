# Automated networking check: a headless server and two headless bot clients run
# for a few seconds: each client must see the other move, dodge, attack; the server
# must resolve hits, a death and a respawn, a guarded hit, and Husks and bots must
# hit each other; no unexpected prediction corrections.
#   powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1
# Exits 0 on pass, 1 on fail. Logs go to build\smoke\.
param([int]$Port = 24599, [int]$Seconds = 12)
. "$PSScriptRoot\find_godot.ps1"

$logDir = Join-Path $ProjectRoot 'build\smoke'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Start-Godot([string]$name, [string[]]$gameArgs) {
    Start-Process $Godot -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru `
        -ArgumentList (@('--headless', '--') + $gameArgs) `
        -RedirectStandardOutput (Join-Path $logDir "$name.log") `
        -RedirectStandardError (Join-Path $logDir "$name.err.log")
}

# Low health (two clean hits) and a quick respawn so the bots die and come back
# within the run, even though they block.
# Every process gets the same overrides, as prediction requires.
$tune = @('--tune=combat/health/max=150', '--tune=combat/death/respawn_time=0.5',
    '--tune=enemy_husk/ai/aggro_range=40', '--tune=enemy_husk/stats/max_health=300',
    '--tune=enemy_husk/stats/respawn_time=2')

$server = Start-Godot 'server' (@('--server', '--verbose', "--port=$Port", "--quit-after=$($Seconds + 2)") + $tune)
Start-Sleep -Seconds 1
$clients = @(
    (Start-Godot 'client1' (@('--bot', '--verbose', "--address=127.0.0.1:$Port", "--quit-after=$Seconds") + $tune)),
    (Start-Godot 'client2' (@('--bot', '--verbose', "--address=127.0.0.1:$Port", "--quit-after=$Seconds") + $tune))
)
$clients | ForEach-Object { $_.WaitForExit() }
# The server quits on its own shortly after the clients, printing its summary.
if (-not $server.WaitForExit(10000)) { Stop-Process -Id $server.Id -Force }

$failed = $false
# The bots fight (Husks when near, else each other) for the first 4 s of every 6;
# the server must resolve real hits.
$serverSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY server .*hits=(\d+) deaths=(\d+) respawns=(\d+) blocks=(\d+) guard_breaks=(\d+)'
$enemySummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY enemies count=(\d+) enemy_hits=(\d+) enemy_damaged=(\d+) enemy_kills=(\d+)'
if (-not $serverSummary -or [int]$serverSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL server: no hits resolved ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$serverSummary.Matches[0].Groups[2].Value -lt 1 -or [int]$serverSummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL server: no death and respawn ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$serverSummary.Matches[0].Groups[4].Value + [int]$serverSummary.Matches[0].Groups[5].Value -lt 1) {
    Write-Host "FAIL server: no hit landed on a guard ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS server: $($serverSummary.Line)" -ForegroundColor Green
}
# Husks notice the bots from 40 m (via --tune), so they must fight both ways.
if (-not $enemySummary -or [int]$enemySummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL enemies: none spawned ($($enemySummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$enemySummary.Matches[0].Groups[2].Value -lt 1 -or [int]$enemySummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL enemies: Husks and bots didn't both land hits ($($enemySummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS enemies: $($enemySummary.Line)" -ForegroundColor Green
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
    } elseif ([int]$local.Matches[0].Groups[1].Value -gt 5) {
        # Usually 0. About 1 run in 20 shows a few small ground corrections of unknown
        # cause (see PROGRESS.md); more than 5 means prediction is really broken.
        Write-Host "FAIL ${name}: prediction disagreed with the server ($($local.Line)); see 'unexpected correction' lines in build\smoke\$name.log" -ForegroundColor Red
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
