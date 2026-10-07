# Starts a headless server (in its own console window) and two client windows
# side by side, all connected over localhost.
#   powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 [-Bot]
# -Bot makes the second client walk in circles on its own, so one person can test.
param([switch]$Bot)
. "$PSScriptRoot\find_godot.ps1"

Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList '--headless', '--', '--server'
Start-Sleep -Seconds 1

$secondFlag = if ($Bot) { '--bot' } else { '--connect' }
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '0,40', '--', '--connect'
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '960,40', '--', $secondFlag
