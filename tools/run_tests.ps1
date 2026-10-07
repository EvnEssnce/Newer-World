# Runs the unit tests in tests/ headless. Exits 0 on pass, 1 on fail.
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
. "$PSScriptRoot\find_godot.ps1"

$logDir = Join-Path $ProjectRoot 'build\tests'
New-Item -ItemType Directory -Force $logDir | Out-Null
$out = Join-Path $logDir 'tests.log'
$err = Join-Path $logDir 'tests.err.log'

$proc = Start-Process $Godot -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru -Wait `
    -ArgumentList '--headless', 'res://tests/framework/run_tests.tscn' `
    -RedirectStandardOutput $out -RedirectStandardError $err

Get-Content $out | Where-Object { $_ -match '^(FAIL|\d+ passed)' }
$scriptErrors = Select-String -Path $err -Pattern 'SCRIPT ERROR|ERROR:'
if ($scriptErrors) {
    Write-Host "Script errors (a test may have crashed partway):" -ForegroundColor Red
    Get-Content $err | Write-Host
    exit 1
}
if ($proc.ExitCode -ne 0) { exit 1 }
