#!/bin/sh
# macOS (or Linux) version of run_local_test.ps1: a headless server, your window
# and a bot's window, all on this machine over localhost.
#   sh tools/run_local_mac.sh [--no-bot] [--party] [--class=ID]
# --no-bot: the second window is a normal player instead of the bot.
# --party:  the bot accepts your party invite (T), or invites you (Y to join).
# --class:  the class the character screen offers first (default fighter).
# Godot: $GODOT, else /Applications/Godot.app. The server keeps accounts and
# characters in Godot's user folder (user://newer_world.db), like on Windows.
# Closing your window stops the server and the bot. The server's log is
# build/local/server.log.
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
	echo "Godot not found at $GODOT: install Godot 4.7 or set GODOT to its binary." >&2
	exit 1
fi
BOT=1
PARTY=""
CLASS="fighter"
for arg in "$@"; do
	case "$arg" in
		--no-bot) BOT=0 ;;
		--party) PARTY="--bot-party" ;;
		--class=*) CLASS="${arg#--class=}" ;;
		*) echo "Unknown option $arg" >&2; exit 1 ;;
	esac
done

# Registers new class_name scripts after a pull (else scripts fail to parse).
"$GODOT" --headless --path . --import > /dev/null 2>&1

mkdir -p build/local
"$GODOT" --headless --path . -- --server > build/local/server.log 2>&1 &
SERVER=$!
sleep 1
if [ "$BOT" = 1 ]; then
	"$GODOT" --path . --resolution 960x540 --position 960,40 -- \
		--bot --account=localbot --character=Localbot $PARTY > build/local/bot.log 2>&1 &
else
	"$GODOT" --path . --resolution 960x540 --position 960,40 -- --connect > build/local/player2.log 2>&1 &
fi
SECOND=$!
"$GODOT" --path . --resolution 960x540 --position 0,40 -- --connect "--class=$CLASS"
kill "$SECOND" "$SERVER" 2>/dev/null
