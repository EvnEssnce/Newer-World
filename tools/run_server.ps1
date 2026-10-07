# Runs the dedicated server headless in this terminal. Ctrl+C stops it.
#   powershell -ExecutionPolicy Bypass -File tools\run_server.ps1 [-Port 24565]
param([int]$Port = 0)
. "$PSScriptRoot\find_godot.ps1"

$gameArgs = @('--server')
if ($Port) { $gameArgs += "--port=$Port" }
Push-Location $ProjectRoot
try { & $Godot --headless -- @gameArgs } finally { Pop-Location }
