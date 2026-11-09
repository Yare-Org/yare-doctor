#!/bin/bash
# End-to-end test of the live-only code paths (lsof folders, git branches, stale git locks, listening ports, shared folders, hosts)
# using real processes started under agent names. Starts 3 fake sessions, checks the live report, then stops everything it started.
# Usage: bash tests/live_e2e.sh yare-doctor.sh
S=${1:-yare-doctor.sh}; T=$(mktemp -d); fail=0
for n in alpha beta; do mkdir -p "$T/$n/.git"; echo "ref: refs/heads/feature-$n" > "$T/$n/.git/HEAD"; done
touch -t 202001010000 "$T/alpha/.git/index.lock"
start() { ( cd "$1" && exec -a "$2" bash -c "python3 -c 'import socket,time;s=socket.socket();s.bind((\"127.0.0.1\",$3));s.listen(1);time.sleep(90)' & exec -a 'npx some-mcp-server' sleep 90 & sleep 90" >/dev/null 2>&1 & ); }
start "$T/alpha" claude 48611; start "$T/beta" codex 48612; start "$T/beta" gemini 48613
sleep 2
J=$(bash "$S" --json --no-color); R=$(bash "$S" --sessions --no-color)
ck() { if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (expected $3, got $2)"; fail=1; fi; }
ck "three fake sessions found"        "$(echo "$J" | grep -o '"label":"\(codex\|gemini\)#1"' | wc -l | tr -d ' ')" 2
ck "folder and branch shown"          "$(echo "$R" | grep -c 'feature-beta')" 2
ck "same-folder collision found (codex and gemini in beta)" "$(echo "$J" | grep -c 'beta (2 sessions)')" 1
ck "stale git lock found (even while editors run git)" "$(echo "$J" | grep -c 'stale git lock')" 1
ck "held ports counted (3 or more)"   "$(echo "$J" | grep -o '"ports_held":[0-9]*' | cut -d: -f2 | awk '{ print ($1 >= 3) ? "yes" : "no" }')" yes
ck "--redact hides folders and branches" "$(bash "$S" --redact --no-color | grep -c 'feature-\|/alpha\|/beta')" 0
for p in 48611 48612 48613; do pid=$(lsof -nP -iTCP:$p -sTCP:LISTEN -t 2>/dev/null); [ -n "$pid" ] && kill "$pid"; done
pkill -f "some-mcp-server"; pkill -x -f "^(claude|codex|gemini) -c python3" 2>/dev/null
sleep 1; rm -r "$T"
exit $fail
