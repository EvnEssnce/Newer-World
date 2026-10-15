# Playtesting with friends over the internet

The server runs on your PC; friends connect over **Tailscale** (free), which gives
your PC a private address they can reach without opening ports on your router.
Nothing here costs money.

## Once

1. **Tailscale on your PC.** Install it from tailscale.com/download and sign in
   (a free Personal account).
2. **Export templates.** Open the project in the Godot editor:
   *Editor → Manage Export Templates → Download and Install* (Godot 4.7.2).
3. **Windows Firewall.** The first time the server starts, Windows asks whether
   Godot may use the network: allow it. If friends still can't connect, add a rule
   for the game's UDP port in an administrator PowerShell:

   ```powershell
   New-NetFirewallRule -DisplayName "Newer World server" -Direction Inbound -Protocol UDP -LocalPort 24565 -Action Allow
   ```

## For each friend

1. They install Tailscale and make a free account.
2. You share your PC with them: in the Tailscale admin console (login.tailscale.com),
   *Machines → your PC → ⋯ → Share…*, and send them the invite link. They accept it
   and see your PC in their Tailscale app. (Sharing only lets them reach your PC,
   not your other devices.)
3. You send them the game: run

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\export_client.ps1
   ```

   and send `build\export\NewerWorld.zip`. They unzip it anywhere and run
   `NewerWorld.exe` (Windows only for now).

**After any code change, export and send the zip again**: everyone must run the
same code as the server. Tuning edits (`data\*.cfg`) don't need a new export: the
server sends its values to every client when it connects.

## Each playtest

```powershell
powershell -ExecutionPolicy Bypass -File tools\host_playtest.ps1
```

It opens the server in a console window (close it to stop the server) and your own
game window, and prints your Tailscale address (`100.x.y.z`). Friends type that
address into the connect screen, then make an account (name + password) and a
character with the class they want. Accounts and characters are kept in the server's
`user://newer_world.db` (Godot's user data folder on your PC). Options: `-Class mage`
(the class your create-character screen offers first), `-NoClassChange` (turns off the
K panel's Class picker for everyone).

Tuning comes from **your** `data\*.cfg` files: edit them, restart the server, and
everyone gets the new values when they reconnect.

## What to look at

- **Hits feel right at your friends' ping**: what you see your swing hit, hits.
  Melee and beam hits are tested where your screen showed the target
  (`[lag_compensation]` in `data/network.cfg`; set `enabled=false` to compare).
  Projectiles aren't rewound: lead moving targets a little.
- **No jerks when your position is corrected**: your model and camera glide to the
  server's position (`correction_smoothing` in `data/network.cfg`). The debug line
  (top left) shows ping and the correction count; a few per minute over the
  internet is expected, a steady climb isn't.
- Write down anything that felt laggy with roughly what you were doing; the server
  console prints joins and leaves.
