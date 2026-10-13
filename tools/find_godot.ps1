# Dot-source this to get $Godot (console exe, prints logs), $GodotGui (windowed exe)
# and $ProjectRoot. It also runs Godot's import first (see the end). Set the GODOT environment variable to override the location.
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

# Register new class_name scripts (after a pull, merge or fresh worktree), or
# scripts that use them fail to parse ("Could not find type ..."). ~3 s.
# Hidden window: when the caller has no console (an agent's shell), a console
# program started any other way opens a new console window that takes focus.
Start-Process $Godot -WorkingDirectory $ProjectRoot -ArgumentList '--headless', '--import' `
    -WindowStyle Hidden -Wait
