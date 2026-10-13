# Visual check without a person, and without stealing the developer's focus:
# a hidden headless server plus one windowed --bot client that saves frames.
# The client window can't take focus (a temporary override.cfg sets
# display/window/size/no_focus; it still renders and saves frames), and the
# server writes its log to a file instead of opening a console window.
#   powershell -ExecutionPolicy Bypass -File tools\screenshot_run.ps1 -Dir shots [-Seconds 30] [-Port 24650] [-Class fighter] [-Resolution 1280x720] [-ClientArgs '--inventory-panel','--verbose'] [-Tune 'loot/table_husk/drop_chance=1']
# Frames land in <Dir>\frame_<N>.png (relative to the project); logs in build\screenshot.
# While it runs, other Godot launches from this same checkout also can't take
# focus (override.cfg is per checkout), so prefer running it in a worktree.
param(
    [Parameter(Mandatory)][string]$Dir,
    [int]$Seconds = 30,
    [int]$Port = 24650,
    [string]$Class = 'fighter',
    [string]$Resolution = '1280x720',
    [string[]]$ClientArgs = @(),
    [string[]]$Tune = @()
)
. "$PSScriptRoot\find_godot.ps1"

$override = Join-Path $ProjectRoot 'override.cfg'
if (Test-Path $override) { throw "override.cfg already exists in $ProjectRoot; not touching it." }
$logDir = Join-Path $ProjectRoot 'build\screenshot'
New-Item -ItemType Directory -Force $logDir | Out-Null
# The game saves into this folder but doesn't create it.
New-Item -ItemType Directory -Force (Join-Path $ProjectRoot $Dir) | Out-Null
$tuneArgs = @($Tune | ForEach-Object { "--tune=$_" })

[IO.File]::WriteAllText($override, "[display]`n`nwindow/size/no_focus=true`n")
try {
    $server = Start-Process $Godot -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru `
        -ArgumentList (@('--headless', '--', '--server', "--port=$Port", "--quit-after=$($Seconds + 3)") + $tuneArgs) `
        -RedirectStandardOutput (Join-Path $logDir 'server.log') `
        -RedirectStandardError (Join-Path $logDir 'server.err.log')
    Start-Sleep -Seconds 1
    $client = Start-Process $GodotGui -WorkingDirectory $ProjectRoot -PassThru `
        -ArgumentList (@('--resolution', $Resolution, '--', '--bot', "--class=$Class",
            "--address=127.0.0.1:$Port", "--screenshot-dir=$Dir", "--quit-after=$Seconds") + $ClientArgs + $tuneArgs) `
        -RedirectStandardOutput (Join-Path $logDir 'client.log') `
        -RedirectStandardError (Join-Path $logDir 'client.err.log')
    # The client reads override.cfg at startup; once it's up, the file can go.
    Start-Sleep -Seconds 3
} finally {
    Remove-Item $override -ErrorAction SilentlyContinue
}
$client | Wait-Process -Timeout ($Seconds + 20) -ErrorAction SilentlyContinue
$server | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
foreach ($p in @($client, $server)) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
"Frames: $(Join-Path $ProjectRoot $Dir)  Logs: $logDir"
