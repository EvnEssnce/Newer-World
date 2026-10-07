# Dot-source this to get $Godot (console exe, prints logs), $GodotGui (windowed exe)
# and $ProjectRoot. Set the GODOT environment variable to override the location.
$ProjectRoot = Split-Path $PSScriptRoot -Parent

if ($env:GODOT) {
    $Godot = $env:GODOT
} else {
    $Godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot not found. Set the GODOT environment variable to the path of Godot's _console.exe."
}
$GodotGui = $Godot -replace '_console\.exe$', '.exe'
