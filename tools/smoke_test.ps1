# Automated networking check: a headless server and two headless bot clients run
# for a few seconds: each client must see the other move, dodge, attack, use an
# ability and swap weapons; the server must resolve hits, a death and a respawn, a
# guarded hit, ability hits and a build change, and Husks and bots must hit each
# other; players and Husks must be moved by force (knockback) and the Spear's
# abilities used; projectiles thrown and hitting; no unexpected prediction
# corrections.
#   powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 [-Port N] [-Party]
# -Party runs the bots with --bot-party: they form a party, so instead of hits,
# deaths and blocks between the bots, the server must report a party formed,
# 0 bot-on-bot hits and at least one bot swing ignored because they're allies
# (both clients in a party of 2), while Husk fights still happen.
# Exits 0 on pass, 1 on fail. Logs go to build\smoke\.
# 32 s = four of the bot's 8 s cycles (see World._bot_input): the default loadout
# (Broadsword out), then the Spear, the Dual Axes and the Broadsword as the focus
# weapon, so each weapon's abilities (knockback, statuses, bleed) get a turn.
param([int]$Port = 24599, [int]$Seconds = 32, [switch]$Party)
. "$PSScriptRoot\find_godot.ps1"

$logDir = Join-Path $ProjectRoot 'build\smoke'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Start-Godot([string]$name, [string[]]$gameArgs) {
    Start-Process $Godot -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru `
        -ArgumentList (@('--headless', '--') + $gameArgs) `
        -RedirectStandardOutput (Join-Path $logDir "$name.log") `
        -RedirectStandardError (Join-Path $logDir "$name.err.log")
}

# Low health (two clean hits) and a quick respawn so the bots die and come back
# within the run, even though they block.
# Every process gets the same overrides, as prediction requires.
$tune = @('--tune=combat/health/max=150', '--tune=combat/death/respawn_time=0.5',
    '--tune=enemy_husk/ai/aggro_range=40', '--tune=enemy_husk/stats/max_health=300',
    '--tune=enemy_husk/stats/respawn_time=2',
    # Bloodlust lasts the whole run, so any later hit proves bleed works.
    '--tune=status_effects/status_bloodlust/duration=30',
    # Husk swings knock players back a little (off in the real data), so forced
    # movement on predicted players happens in every run, party or not. Kept
    # short: a 1.5 m shove moved the bots out of their fights often enough to
    # fail the guard check.
    '--tune=enemy_husk/attack/force_distance=0.4',
    # Low Sweep ready again by the bot's second ability press, which then uses it
    # again (see World._bot_ability_button): more chances to knock a Husk back.
    '--tune=weapon_spear/ability_low_sweep/cooldown=0.6',
    # Bot fights are luck: these give the bleed and Husk-knockback checks a source
    # in every run (Husk swings bleed the bots; Broadsword heavies push Husks).
    '--tune=enemy_husk/attack/applies_status=bleed',
    '--tune=weapon_broadsword/heavy/force_distance=0.4',
    '--tune=wings_fighter/ability_diving_strike/force_distance=0.5',
    # More throws per run (each weapon is out for about one cycle), so a
    # projectile hit doesn't hang on one or two throws.
    '--tune=weapon_spear/ability_javelin_cast/cooldown=2.0',
    '--tune=weapon_dual_axes/ability_boomerang_axe/cooldown=2.0',
    # Skewer taunts instead of rooting, so taunts on Husks happen (nothing
    # applies them in the real data yet). Counted in "SUMMARY enemies taunts=",
    # not checked: it depends on the bot's Spear turn landing on a Husk.
    '--tune=weapon_spear/ability_skewer/applies_status=taunted',
    # A 1 s Rebirth (5 s in the real data) keeps a reborn bot in the fight, so
    # the other checks still get their hits, blocks and deaths.
    '--tune=ember/rebirth/duration=1.0')

$botFlags = @('--bot', '--verbose')
if ($Party) { $botFlags += '--bot-party' }

$server = Start-Godot 'server' (@('--server', '--verbose', "--port=$Port", "--quit-after=$($Seconds + 2)") + $tune)
Start-Sleep -Seconds 1
$clients = @(
    (Start-Godot 'client1' ($botFlags + @("--address=127.0.0.1:$Port", "--quit-after=$Seconds") + $tune)),
    (Start-Godot 'client2' ($botFlags + @("--address=127.0.0.1:$Port", "--quit-after=$Seconds") + $tune))
)
# A script that fails to parse leaves the game running without --quit-after, so
# don't wait forever: anything still running well past its time is stopped.
$clients | ForEach-Object {
    # /T: the console exe runs the game as a child process.
    if (-not $_.WaitForExit(($Seconds + 30) * 1000)) { taskkill /T /F /PID $_.Id | Out-Null }
}
# The server quits on its own shortly after the clients, printing its summary.
if (-not $server.WaitForExit(10000)) { taskkill /T /F /PID $server.Id | Out-Null }

$failed = $false
# The bots fight (Husks when near, else each other) for the first 4 s of every 8 (then use abilities for 2 s);
# the server must resolve real hits.
$serverSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY server .*hits=(\d+) deaths=(\d+) respawns=(\d+) blocks=(\d+) guard_breaks=(\d+)'
$enemySummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY enemies count=(\d+) enemy_hits=(\d+) enemy_damaged=(\d+) enemy_kills=(\d+)'
$partySummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY party formed=(\d+) parties=(\d+) pvp_hits=(\d+) ally_hits_ignored=(\d+)'
if ($Party) {
    # Party members can't hurt each other: no bot-on-bot hits at all (not even
    # evades or blocks), so the bots' deaths/blocks checks below don't apply.
    if (-not $partySummary -or [int]$partySummary.Matches[0].Groups[1].Value -lt 1) {
        Write-Host "FAIL party: no party formed on the server ($($partySummary.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$partySummary.Matches[0].Groups[3].Value -ne 0) {
        Write-Host "FAIL party: party members hit each other ($($partySummary.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$partySummary.Matches[0].Groups[4].Value -lt 1) {
        # The bots still swing at each other when no Husk is near; those swings
        # must reach the server's ally check (and be ignored there).
        Write-Host "FAIL party: no swing between allies reached the ally check ($($partySummary.Line))" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "PASS party: $($partySummary.Line)" -ForegroundColor Green
    }
} elseif (-not $serverSummary -or [int]$serverSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL server: no hits resolved ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$serverSummary.Matches[0].Groups[2].Value -lt 1 -or [int]$serverSummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL server: no death and respawn ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$serverSummary.Matches[0].Groups[4].Value + [int]$serverSummary.Matches[0].Groups[5].Value -lt 1) {
    Write-Host "FAIL server: no hit landed on a guard ($($serverSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS server: $($serverSummary.Line)" -ForegroundColor Green
}
# Husks notice the bots from 40 m (via --tune), so they must fight both ways.
if (-not $enemySummary -or [int]$enemySummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL enemies: none spawned ($($enemySummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$enemySummary.Matches[0].Groups[2].Value -lt 1 -or [int]$enemySummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL enemies: Husks and bots didn't both land hits ($($enemySummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS enemies: $($enemySummary.Line)" -ForegroundColor Green
}
# The bots use abilities (on each other or Husks), swap weapons and respec once a cycle.
$abilitySummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY abilities uses=(\d+) ability_hits=(\d+) parries=(\d+) swaps=(\d+) builds=(\d+)'
if (-not $abilitySummary) {
    Write-Host "FAIL abilities: no summary" -ForegroundColor Red
    $failed = $true
} elseif ([int]$abilitySummary.Matches[0].Groups[1].Value -lt 2 -or [int]$abilitySummary.Matches[0].Groups[2].Value -lt 1) {
    Write-Host "FAIL abilities: too few ability uses or no ability hits ($($abilitySummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$abilitySummary.Matches[0].Groups[4].Value -lt 2) {
    Write-Host "FAIL abilities: too few weapon swaps ($($abilitySummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$abilitySummary.Matches[0].Groups[5].Value -lt 1) {
    Write-Host "FAIL abilities: no build change accepted ($($abilitySummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS abilities: $($abilitySummary.Line)" -ForegroundColor Green
}
# Statuses: the bots slot their status abilities (Opening Strike, Bloodlust,
# Hamstring), so the server must apply statuses (some on Husks) and deal bleed
# damage. Allies must never debuff each other.
$statusSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY statuses applied=(\d+) on_enemies=(\d+) self_buffs=(\d+) dot_ticks=(\d+) dot_damage=(\d+) ally_refused=(\d+) ally_applied=(\d+)'
if (-not $statusSummary) {
    Write-Host "FAIL statuses: no summary" -ForegroundColor Red
    $failed = $true
} elseif ([int]$statusSummary.Matches[0].Groups[6].Value -ne 0 -or [int]$statusSummary.Matches[0].Groups[7].Value -ne 0) {
    Write-Host "FAIL statuses: a debuff was tried or applied between allies ($($statusSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif (-not $Party -and [int]$statusSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL statuses: none applied ($($statusSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif (-not $Party -and [int]$statusSummary.Matches[0].Groups[2].Value -lt 1) {
    Write-Host "FAIL statuses: none applied to a Husk ($($statusSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif (-not $Party -and [int]$statusSummary.Matches[0].Groups[4].Value -lt 1) {
    Write-Host "FAIL statuses: no bleed damage ticked ($($statusSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS statuses: $($statusSummary.Line)" -ForegroundColor Green
}
# Forced movement (Husk knockback on the bots, the bots' Low Sweep on Husks) and
# the Spear: the bots equip it after the first cycle and use its abilities. In a party, no bot may move the other.
$forceSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY force players=(\d+) pvp=(\d+) enemies=(\d+) launches=(\d+)'
$spearSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY ability_uses_by_weapon .*spear=(\d+)'
if (-not $forceSummary) {
    Write-Host "FAIL force: no summary" -ForegroundColor Red
    $failed = $true
} elseif ([int]$forceSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL force: no player was moved by force ($($forceSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$forceSummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL force: no Husk was moved by force ($($forceSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ($Party -and [int]$forceSummary.Matches[0].Groups[2].Value -ne 0) {
    Write-Host "FAIL force: party members moved each other ($($forceSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS force: $($forceSummary.Line)" -ForegroundColor Green
}
if (-not $spearSummary -or [int]$spearSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL spear: no Spear ability used ($((Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY ability_uses_by_weapon').Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS spear: $($spearSummary.Line)" -ForegroundColor Green
}
# Ember, Wings and Rebirth: the bots gain Ember by fighting, use Wing abilities
# (keeping 50 Ember for a Rebirth while one is ready), and their first death
# with 50+ Ember is a Rebirth, not a respawn.
$emberSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY ember gained=(\d+) spent=(\d+) wing_uses=(\d+) rebirths_started=(\d+) rebirths=(\d+)'
if (-not $emberSummary) {
    Write-Host "FAIL ember: no summary" -ForegroundColor Red
    $failed = $true
} elseif ([int]$emberSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL ember: no Ember gained ($($emberSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$emberSummary.Matches[0].Groups[2].Value -lt 1 -or [int]$emberSummary.Matches[0].Groups[3].Value -lt 1) {
    Write-Host "FAIL ember: no Wing ability used / Ember spent ($($emberSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$emberSummary.Matches[0].Groups[5].Value -lt 1) {
    Write-Host "FAIL ember: no Rebirth ($($emberSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS ember: $($emberSummary.Line)" -ForegroundColor Green
}
# Projectiles: the bots throw Javelin Cast (Spear) and Boomerang Axe (Dual Axes)
# at range (and in the ability phase); at least one must hit a player or a
# Husk, and party members' projectiles must never hit each other.
$projSummary = Select-String -Path (Join-Path $logDir 'server.log') -Pattern '^SUMMARY projectiles fired=(\d+) hits=(\d+) on_players=(\d+) on_enemies=(\d+) ally_hits=(\d+) ally_ignored=(\d+)'
if (-not $projSummary) {
    Write-Host "FAIL projectiles: no summary" -ForegroundColor Red
    $failed = $true
} elseif ([int]$projSummary.Matches[0].Groups[1].Value -lt 1) {
    Write-Host "FAIL projectiles: none fired ($($projSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$projSummary.Matches[0].Groups[2].Value -lt 1) {
    Write-Host "FAIL projectiles: none hit a player or a Husk ($($projSummary.Line))" -ForegroundColor Red
    $failed = $true
} elseif ([int]$projSummary.Matches[0].Groups[5].Value -ne 0) {
    Write-Host "FAIL projectiles: a projectile hit an ally ($($projSummary.Line))" -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS projectiles: $($projSummary.Line)" -ForegroundColor Green
}
foreach ($name in 'client1', 'client2') {
    $summary = Select-String -Path (Join-Path $logDir "$name.log") -Pattern '^SUMMARY client=\d+ remote=\d+ moved=([\d.]+)'
    if (-not $summary) {
        Write-Host "FAIL ${name}: never saw another player" -ForegroundColor Red
        $failed = $true
    } elseif ([double]$summary.Matches[0].Groups[1].Value -lt 1.0) {
        Write-Host "FAIL ${name}: saw another player but it didn't move ($($summary.Line))" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "PASS ${name}: $($summary.Line)" -ForegroundColor Green
    }
    # The bot dodges on the ground and in the air, and attacks. Prediction must match the server.
    $local = Select-String -Path (Join-Path $logDir "$name.log") -Pattern '^SUMMARY client=\d+ snapshots=\d+ corrections=(\d+) dodges=(\d+) air_dodges=(\d+) attacks=(\d+) hits_landed=\d+ abilities=(\d+) swaps=(\d+)'
    if (-not $local) {
        Write-Host "FAIL ${name}: no local player summary" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[2].Value -lt 1 -or [int]$local.Matches[0].Groups[3].Value -lt 1) {
        Write-Host "FAIL ${name}: bot didn't dodge on the ground and in the air ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[4].Value -lt 1) {
        Write-Host "FAIL ${name}: bot never attacked ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[5].Value -lt 1 -or [int]$local.Matches[0].Groups[6].Value -lt 1) {
        Write-Host "FAIL ${name}: bot didn't use an ability and swap weapons ($($local.Line))" -ForegroundColor Red
        $failed = $true
    } elseif ([int]$local.Matches[0].Groups[1].Value -gt 5) {
        # Usually 0. About 1 run in 20 shows a few small ground corrections of unknown
        # cause (see PROGRESS.md); more than 5 means prediction is really broken.
        Write-Host "FAIL ${name}: prediction disagreed with the server ($($local.Line)); see 'unexpected correction' lines in build\smoke\$name.log" -ForegroundColor Red
        $failed = $true
    } else {
        Write-Host "PASS ${name}: $($local.Line)" -ForegroundColor Green
    }
    if ($Party) {
        $members = Select-String -Path (Join-Path $logDir "$name.log") -Pattern '^SUMMARY client=\d+ party_members=(\d+)'
        if (-not $members -or [int]$members.Matches[0].Groups[1].Value -ne 2) {
            Write-Host "FAIL ${name}: not in a party of 2 at the end ($($members.Line))" -ForegroundColor Red
            $failed = $true
        } else {
            Write-Host "PASS ${name}: $($members.Line)" -ForegroundColor Green
        }
    }
}
$errors = Get-ChildItem $logDir -Filter '*.err.log' | Select-String -Pattern 'ERROR|SCRIPT ERROR'
if ($errors) {
    Write-Host "Errors were logged:" -ForegroundColor Yellow
    $errors | ForEach-Object { Write-Host "  $($_.Filename): $($_.Line)" }
    $failed = $true
}
if ($failed) { exit 1 }
Write-Host "Smoke test passed." -ForegroundColor Green
