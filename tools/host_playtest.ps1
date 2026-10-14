# Hosts a playtest with other people on this PC: a dedicated server in its own
# console window (close it to stop the server) and your game window connected to
# it. Friends connect to this PC's Tailscale address (printed below). See
# HOSTING.md.
#   powershell -ExecutionPolicy Bypass -File tools\host_playtest.ps1 [-Class mage] [-NoClassChange]
# -NoClassChange turns off the K panel's Class picker (a test tool) for everyone:
# the server's data\*.cfg values are what every player gets.
param([string]$Class = 'fighter', [switch]$NoClassChange, [int]$Port = 0)
. "$PSScriptRoot\find_godot.ps1"

$serverArgs = @('--headless', '--', '--server')
if ($Port) { $serverArgs += "--port=$Port" }
if ($NoClassChange) { $serverArgs += '--tune=testing/class_change/enabled=false' }
Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList $serverArgs
Start-Sleep -Seconds 2

$address = if ($Port) { "127.0.0.1:$Port" } else { '127.0.0.1' }
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--', '--connect', "--address=$address", "--class=$Class"

$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscale -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
    $tailscale = "$env:ProgramFiles\Tailscale\tailscale.exe"
}
$portText = if ($Port) { ":$Port" } else { '' }
if ($tailscale) {
    $ip = (& $tailscale ip -4 2>$null | Select-Object -First 1)
    if ($ip) { "Friends connect to: $ip$portText" } else { "Tailscale isn't connected: sign in to Tailscale first." }
} else {
    "Tailscale isn't installed (see HOSTING.md). On your own network, friends can use this PC's LAN address."
}
