# Starts a headless server (in its own console window) and two client windows
# side by side, all connected over localhost. The second window is a bot that
# moves, dodges and attacks on its own, so one person can test.
#   powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 [-NoBot] [-Party]
# -NoBot makes both windows normal players (for two people, or one person
# switching windows).
# -Party makes the bot party up: it accepts your invite (T), or invites you (Y to join).
# -Class picks your class (default fighter; e.g. juggernaut). The bot plays a Fighter.
param([switch]$NoBot, [switch]$Party, [string]$Class = 'fighter')
. "$PSScriptRoot\find_godot.ps1"

Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList '--headless', '--', '--server'
Start-Sleep -Seconds 1

$secondArgs = if ($NoBot) { @('--connect') } elseif ($Party) { @('--bot', '--bot-party') } else { @('--bot') }
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '0,40', '--', '--connect', "--class=$Class"
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList (@('--resolution', '960x540', '--position', '960,40', '--') + $secondArgs)
