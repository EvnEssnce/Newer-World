# Starts a headless server (in its own console window) and two client windows
# side by side, all connected over localhost. The second window is a bot that
# moves, dodges and attacks on its own, so one person can test.
#   powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 [-NoBot] [-Party]
# -NoBot makes both windows normal players (for two people, or one person
# switching windows).
# -Party makes the bot party up: it accepts your invite (T), or invites you (Y to join).
# You log in (or make an account) and pick or make a character in your window;
# the server keeps them in user://newer_world.db. -Class picks the class the
# character screen offers first (default fighter; e.g. juggernaut, assassin,
# ranger, mage, paladin). The bot logs in by itself as account localbot and
# plays its character Localbot (a Fighter, made on its first run).
param([switch]$NoBot, [switch]$Party, [string]$Class = 'fighter')
. "$PSScriptRoot\find_godot.ps1"

Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList '--headless', '--', '--server'
Start-Sleep -Seconds 1

$botArgs = @('--bot', '--account=localbot', '--character=Localbot')
$secondArgs = if ($NoBot) { @('--connect') } elseif ($Party) { $botArgs + '--bot-party' } else { $botArgs }
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList '--resolution', '960x540', '--position', '0,40', '--', '--connect', "--class=$Class"
Start-Process $GodotGui -WorkingDirectory $ProjectRoot -ArgumentList (@('--resolution', '960x540', '--position', '960,40', '--') + $secondArgs)
