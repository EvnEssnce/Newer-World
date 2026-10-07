# Automated networking check: a headless server and two headless bot clients run
# for a few seconds, then each client must have seen the other one move.
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

$server = Start-Godot 'server' @('--server', "--port=$Port", "--quit-after=$($Seconds + 4)")
Start-Sleep -Seconds 1
$clients = @(
    (Start-Godot 'client1' @('--bot', "--address=127.0.0.1:$Port", "--quit-after=$Seconds")),
    (Start-Godot 'client2' @('--bot', "--address=127.0.0.1:$Port", "--quit-after=$Seconds"))
)
$clients | ForEach-Object { $_.WaitForExit() }
if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }

$failed = $false
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
}
$errors = Get-ChildItem $logDir -Filter '*.err.log' | Select-String -Pattern 'ERROR|SCRIPT ERROR'
if ($errors) {
    Write-Host "Errors were logged:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "  $($_.Filename): $($_.Line)" }
    $failed = $true
}
if ($failed) { exit 1 }
Write-Host "Smoke test passed." -ForegroundColor Green
