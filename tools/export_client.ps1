# Exports the Windows game (client; it can also run a server) to
# build\export\NewerWorld.exe (one file: data\*.cfg is packed inside) and zips it
# as build\export\NewerWorld.zip to send to friends. See HOSTING.md.
#   powershell -ExecutionPolicy Bypass -File tools\export_client.ps1
# Needs Godot's export templates once: open the project in the Godot editor,
# Editor > Manage Export Templates > Download and Install.
# Re-export and re-send after every code change: a friend's game must run the
# same code as the server, which refuses it otherwise (the connect screen says
# so; the server sends its data\*.cfg values on connect, so tuning edits alone
# don't need a new export).
. "$PSScriptRoot\find_godot.ps1"

# "Godot_v4.7.2-stable_win64_console.exe" -> "4.7.2.stable" (the templates' folder
# name). From the file name: running Godot to ask would open a console window.
if ((Split-Path $Godot -Leaf) -notmatch '^Godot_v([\d.]+)-([a-z]+)_') {
    throw "Can't tell Godot's version from $Godot."
}
$templateVersion = "$($Matches[1]).$($Matches[2])"
$templates = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
if (-not (Test-Path (Join-Path $templates 'windows_release_x86_64.exe'))) {
    throw "Godot's export templates for $templateVersion aren't installed ($templates). In the Godot editor: Editor > Manage Export Templates > Download and Install."
}

$outDir = Join-Path $ProjectRoot 'build\export'
New-Item -ItemType Directory -Force $outDir | Out-Null
$exe = Join-Path $outDir 'NewerWorld.exe'
Remove-Item $exe -ErrorAction SilentlyContinue
# The code version (CodeVersion) of what's exported, packed in as
# code_version.txt: the server refuses a friend whose exe isn't on its code,
# with a message. Only there for the export (a game run from the project
# folder hashes its scripts itself).
$stamp = Join-Path $ProjectRoot 'code_version.txt'
try {
    Start-Process $Godot -WorkingDirectory $ProjectRoot -WindowStyle Hidden -Wait `
        -ArgumentList '--headless', '--script', 'res://tools/write_code_version.gd' `
        -RedirectStandardOutput (Join-Path $outDir 'version.log') `
        -RedirectStandardError (Join-Path $outDir 'version.err.log')
    if (-not (Test-Path $stamp)) {
        Get-Content (Join-Path $outDir 'version.log'), (Join-Path $outDir 'version.err.log') | Select-Object -Last 20
        throw "Couldn't write the code version (logs in build\export)."
    }
    $version = (Get-Content $stamp -Raw).Trim()
    Start-Process $Godot -WorkingDirectory $ProjectRoot -WindowStyle Hidden -Wait `
        -ArgumentList '--headless', '--export-release', '"Windows Desktop"', '"build/export/NewerWorld.exe"' `
        -RedirectStandardOutput (Join-Path $outDir 'export.log') `
        -RedirectStandardError (Join-Path $outDir 'export.err.log')
} finally {
    Remove-Item $stamp -ErrorAction SilentlyContinue
}
if (-not (Test-Path $exe)) {
    Get-Content (Join-Path $outDir 'export.log'), (Join-Path $outDir 'export.err.log') | Select-Object -Last 20
    throw "Export failed (logs in build\export)."
}
$zip = Join-Path $outDir 'NewerWorld.zip'
# The console wrapper (NewerWorld.console.exe) shows the game's log; handy if a
# friend can't connect. The godot-sqlite DLL is exported beside the exe; without
# it the game logs an extension error at start (clients don't use the database).
$files = @(Get-ChildItem $outDir -Filter 'NewerWorld*.exe') + @(Get-ChildItem $outDir -Filter '*.dll') |
    Select-Object -ExpandProperty FullName
Compress-Archive -Path $files -DestinationPath $zip -Force
"Exported $exe (code version $version: the connect screen shows it)"
"Send $zip to your friends (unzip, run NewerWorld.exe, enter your Tailscale address)."
