# Rolls a loot table for many kills and prints what actually dropped, so drop
# rates in data/loot.cfg can be tuned from real numbers.
#   powershell -ExecutionPolicy Bypass -File tools\roll_loot.ps1 [-Table husk] [-Kills 50000] [-Seed 1]
param([string]$Table = 'husk', [int]$Kills = 50000, [int]$Seed = 1)
. "$PSScriptRoot\find_godot.ps1"

Push-Location $ProjectRoot
try {
    & $Godot --headless res://tools/loot_sim.tscn -- "--table=$Table" "--kills=$Kills" "--seed=$Seed" 2>&1 |
        ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^Godot Engine v' }
} finally { Pop-Location }
