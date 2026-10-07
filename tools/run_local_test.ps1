# Starts a headless server (in its own console window) and two client windows
# side by side, all connected over localhost. The second window is a bot that
# moves, dodges and attacks on its own, so one person can test.
#   powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 [-NoBot]
# -NoBot makes both windows normal players (for two people, or one person
# switching windows).
param([switch]$NoBot)
. "$PSScriptRoot\find_godot.ps1"

Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList '--headless', '--', '--server'
Start-Sleep -Seconds 1

$secondFlag = if ($NoBot) { '--connect' } else { '--bot' }
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '0,40', '--', '--connect'
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '960,40', '--', $secondFlag
