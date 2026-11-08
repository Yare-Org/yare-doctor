#!/bin/bash
# yare-doctor: read-only check of what your coding agents are running on this Mac.
# Uses only `ps`, `sysctl`, `memory_pressure`, `pmset` and `lsof` (listing, never connecting). No network, no files
# written, nothing killed or changed. Early prototype helper from the Yare project. It reports; it does not claim a speed-up.
# Works with the bash that ships with macOS (3.2).
#
# What it does that Activity Monitor does not: it follows the parent chain of every process, so it can say which agent
# session started what, how much of the Mac each session is holding, who is using the CPU, and what was left behind.
VERSION="0.3.0"
set -u

usage() {
  cat <<'EOF'
yare-doctor: what are your coding agents doing to this Mac? (read-only)

  bash yare-doctor.sh                 one snapshot now (run it while your agents are working)
  bash yare-doctor.sh --watch [SECS]  sample every 5 s for SECS seconds (default 60): how often an agent's build ran
                                      at the same time as one of yours, and how long the Mac was squeezed by agents
  bash yare-doctor.sh --share         add one line with counts only (no paths, user names or commands) to paste in a reply
  bash yare-doctor.sh --json          machine-readable counts instead of the report
  bash yare-doctor.sh --version

The report shows: what stands out, each agent session with everything it started (CPU, memory, CPU used so far, helpers
sitting idle), who is using the CPU right now and which agent started it, helper programs started many times over,
ports that agent sessions are holding open, builds split into the agent's and yours, and leftovers from ended sessions.

It never changes anything: no network, no files, nothing is stopped. Read it first, it is short.
EOF
}

MODE=snapshot; WATCH_SECS=60; SHARE=0; JSON=0; INTERVAL=5
while [ $# -gt 0 ]; do
  case $1 in
    --watch) MODE=watch; if [[ ${2:-} =~ ^[0-9]+$ ]]; then WATCH_SECS=$2; shift; fi ;;
    --share) SHARE=1 ;;
    --json) JSON=1 ;;
    --version) echo "yare-doctor $VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
if (( WATCH_SECS < 10 )); then WATCH_SECS=10; fi
if (( WATCH_SECS > 3600 )); then WATCH_SECS=3600; fi

CPUS=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
MEM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
CORES=$CPUS; [[ $CORES =~ ^[0-9]+$ ]] || CORES=1
TAB=$'\t'

# One pass over the process list. Every process is placed in the tree of the agent that started it (its topmost agent
# ancestor), so one agent session = the agent plus everything below it. Prints tab-separated lines:
#   TOT allcpu allmemMB agentcpu agentmemMB nprocs         whole machine vs. everything inside agent sessions
#   AGENT name count cpu% memMB                            agent processes by name
#   SESS label rootpid age procs cpu% memMB cpuminutes idlecount idleMB    one line per agent session
#   TOP pid owner cpu% memMB name                          processes using CPU, with the agent session that owns them
#   BUILD agent|own count cpu%                             builds and tests, by whether an agent started them
#   DUP signature count memMB sessions                     the same helper started 3+ times inside agent sessions
#   LEFT pid cpu% memMB elapsed command                    helpers with no parent that look left over from ended sessions
#   MAP pid owner                                          processes owned by a session or left over (to match ports)
scan() {
  ps -axo pid=,ppid=,pcpu=,rss=,etime=,time=,command= 2>/dev/null | awk '
  function etsecs(t,   d, x, p, n) {
    d = 0
    if (index(t, "-")) { split(t, x, "-"); d = x[1]; t = x[2] }
    n = split(t, p, ":")
    if (n == 3) return d*86400 + p[1]*3600 + p[2]*60 + p[3]
    if (n == 2) return d*86400 + p[1]*60 + p[2]
    return d*86400 + p[1]
  }
  function cpusecs(t,   p, n) {
    n = split(t, p, ":")
    if (n == 3) return p[1]*3600 + p[2]*60 + p[3]
    if (n == 2) return p[1]*60 + p[2]
    return p[1] + 0
  }
  function base(s,   n, a) { n = split(s, a, "/"); return a[n] }
  function human(s,   d, h, m) {
    d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60)
    if (d > 0) return d "d " h "h"
    if (h > 0) return h "h " m "m"
    return m "m"
  }
  function agentname(low,   t, b) {
    split(low, t, " "); b = base(t[1])
    if (b == "claude" || b == "codex" || b == "opencode" || b == "aider" || b == "cursor-agent" || b == "gemini") return b
    if (low ~ /\/claude-code\//) return "claude"
    if (low ~ /@openai\/codex|\/codex\/bin\//) return "codex"
    return ""
  }
  function isbuild(low,   t, b) {
    split(low, t, " "); b = base(t[1])
    if (b ~ /^(clang|clang\+\+|cc1|swiftc|swift-frontend|swift-build|rustc|cargo|tsc|xcodebuild|gradle|make|ninja|webpack|esbuild|vite|ld)$/) return 1
    if (low ~ /node .*(jest|vitest|mocha|--test)/) return 1
    return 0
  }
  function appname(cmd,   i, s, t) {
    i = index(cmd, ".app/Contents/MacOS/")
    if (i) { s = substr(cmd, i + 20); sub(/ -.*/, "", s); return substr(s, 1, 34) }
    split(cmd, t, " "); return substr(base(t[1]), 1, 34)
  }
  function sig(low,   t, b, k) {
    split(low, t, " "); b = base(t[1])
    if (b ~ /^(node|python|python3|bun|deno|npx|uvx|uv|ruby|java)$/) {
      for (k = 2; (k in t) && k < 8; k++) if (substr(t[k], 1, 1) != "-") return b " " substr(base(t[k]), 1, 30)
    }
    return b
  }
  {
    cmd = ""
    for (i = 7; i <= NF; i++) cmd = cmd (i > 7 ? " " : "") $i
    low = tolower(cmd)
    split(low, ft, " "); fb = base(ft[1])
    if (low ~ /yare-doctor/ || fb ~ /^(ps|awk|sort|lsof|pmset|sysctl|memory_pressure|bc|sleep|head|tr|sed|date)$/) next
    pid = $1; P[pid] = $2; C[pid] = $3 + 0; R[pid] = $4; E[pid] = $5; T[pid] = $6; CMD[pid] = cmd; LOW[pid] = low
    n[pid] = 1
    if (low ~ /--type=|helper/) HELP[pid] = 1
  }
  END {
    for (pid in n) {
      if (pid in HELP) continue
      a = agentname(LOW[pid])
      if (a != "") { AG[pid] = a; ac[a]++; acpu[a] += C[pid]; amem[a] += R[pid] / 1024 }
    }
    for (a in ac) printf "AGENT\t%s\t%d\t%.1f\t%d\n", a, ac[a], acpu[a], amem[a]

    # topmost agent above (or at) each process = the session it belongs to
    nroots = 0
    for (pid in n) {
      root = ""; q = pid
      for (s = 0; s < 40 && q != "" && q > 1; s++) { if (q in AG) root = q; q = P[q] }
      ROOT[pid] = root
      if (root == pid) roots[++nroots] = pid + 0
    }
    for (i = 2; i <= nroots; i++) { v = roots[i]; j = i - 1; while (j > 0 && roots[j] > v) { roots[j + 1] = roots[j]; j-- } roots[j + 1] = v }
    for (i = 1; i <= nroots; i++) { r = roots[i]; cnt[AG[r]]++; LABEL[r] = AG[r] "#" cnt[AG[r]] }

    allcpu = 0; allmem = 0; agcpu = 0; agmem = 0; np = 0
    for (pid in n) {
      np++; allcpu += C[pid]; allmem += R[pid] / 1024
      r = ROOT[pid]
      if (r == "") continue
      sp[r]++; scpu[r] += C[pid]; smem[r] += R[pid] / 1024; stime[r] += cpusecs(T[pid])
      agcpu += C[pid]; agmem += R[pid] / 1024
      age = etsecs(E[pid])
      if (pid != r && !(pid in HELP) && age > 1800 && C[pid] < 1 && cpusecs(T[pid]) / age < 0.005) { idn[r]++; idm[r] += R[pid] / 1024 }
    }
    printf "TOT\t%.1f\t%d\t%.1f\t%d\t%d\n", allcpu, allmem, agcpu, agmem, np
    for (i = 1; i <= nroots; i++) {
      r = roots[i]
      printf "SESS\t%s\t%s\t%s\t%d\t%.1f\t%d\t%d\t%d\t%d\n", LABEL[r], r, human(etsecs(E[r])), sp[r], scpu[r], smem[r], stime[r] / 60, idn[r] + 0, idm[r] + 0
    }

    for (pid in n) {
      owner = (ROOT[pid] != "") ? LABEL[ROOT[pid]] : "-"
      if (C[pid] >= 1.0) printf "TOP\t%s\t%s\t%.1f\t%d\t%s\n", pid, owner, C[pid], R[pid] / 1024, appname(CMD[pid])
    }

    for (pid in n) {
      if ((pid in HELP) || !isbuild(LOW[pid])) continue
      ow = (ROOT[pid] != "") ? "agent" : "own"
      bc[ow]++; bcpu[ow] += C[pid]
    }
    printf "BUILD\tagent\t%d\t%.1f\n", bc["agent"], bcpu["agent"]
    printf "BUILD\town\t%d\t%.1f\n", bc["own"], bcpu["own"]

    for (pid in n) {
      low = LOW[pid]
      if (pid in HELP) continue
      if (P[pid] == 1 && low ~ /(mcp|claude|codex|opencode)/ && low ~ /(node|python|bun|deno|uvx|npx|mcp)/ && low !~ /^\/(system|usr|library|applications)\//) {
        if (etsecs(E[pid]) > 1800) { LEFTF[pid] = 1; printf "LEFT\t%s\t%s\t%d\t%s\t%s\n", pid, C[pid], R[pid] / 1024, E[pid], substr(CMD[pid], 1, 70) }
      }
    }

    for (pid in n) {
      if (pid in HELP) continue
      if ((ROOT[pid] != "" && ROOT[pid] != pid) || (pid in LEFTF)) {
        s = sig(LOW[pid]); if (s ~ /^(bash|sh|zsh|fish|-bash|-zsh)$/) continue
        dc[s]++; dm[s] += R[pid] / 1024
        k = s SUBSEP ((pid in LEFTF) ? "left" : ROOT[pid]); if (!(k in dseen)) { dseen[k] = 1; ds[s]++ }
      }
    }
    for (s in dc) if (dc[s] >= 3) printf "DUP\t%s\t%d\t%d\t%d\n", s, dc[s], dm[s], ds[s]

    for (pid in n) {
      if (ROOT[pid] != "") printf "MAP\t%s\t%s\n", pid, LABEL[ROOT[pid]]
      else if (pid in LEFTF) printf "MAP\t%s\tleftover\n", pid
    }
  }'
}

load1() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }
swap_used() { sysctl -n vm.swapusage 2>/dev/null | sed -E 's/.*used = ([0-9.]+[MG]).*/\1/'; }
mem_free_pct() { memory_pressure 2>/dev/null | awk '/free percentage/ {gsub("%", "", $NF); print $NF; exit}'; }

# Power settings that change how fast builds run. Read-only (pmset -g never changes anything).
energy_mode() {
  pmset -g 2>/dev/null | awk '$1 == "lowpowermode" { lp = $2 } $1 == "powermode" { pw = $2 }
    END { if (lp == 1 || pw == 1) print "low"; else if (pw == 2) print "high"; else print "automatic" }'
}
thermal_limit() { pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/ { print $NF; exit }'; }

# Sums from a scan result
total() { echo "$SCAN" | awk -F'\t' -v k="$1" -v w="$2" -v col="$3" '$1 == k && (w == "" || $2 == w) { s += $col } END { print s + 0 }'; }
count() { echo "$SCAN" | awk -F'\t' -v k="$1" '$1 == k { n++ } END { print n + 0 }'; }
agent_list() { echo "$SCAN" | awk -F'\t' '$1 == "AGENT" { printf "%s%s %d", (n++ ? ", " : ""), $2, $3 } END { if (!n) printf "none" }'; }
pct() { awk -v a="$1" -v c="$CORES" 'BEGIN { v = a / c; if (v < 10) printf "%.1f", v; else printf "%.0f", v }'; } # points of ps %CPU -> % of the whole machine

# Listening TCP ports held by processes that belong to an agent session or look left over (lsof only lists, never connects)
ports() {
  local map; map=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" { print $2 " " $3 }')
  [ -z "$map" ] && return
  awk 'NR == FNR { own[$1] = $2; next }
    $1 != "COMMAND" && ($2 in own) { name = $(NF - 1); sub(/.*:/, "", name); k = $2 ":" name
      if (!(k in seen)) { seen[k] = 1; printf "%s\t%s\t%s\n", $1, name, own[$2] } }' <(echo "$map") <(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null)
}

LINK="https://meetyare.vercel.app/?utm_source=doctor&utm_medium=tool&utm_campaign=output"

share_line() { # $1 = extra text
  echo "Yare doctor v$VERSION: $CPUS cores, ${MEM_GB} GB. Agents: $(agent_list) in ${SESS_N} sessions, using ${AG_PCT}% of CPU and ${AG_MB} MB. Builds: $B_AGENT started by agents, $B_OWN not. Load ${LOAD:-?}, swap ${SWAP:-?}, ${LEFT_N} possible leftovers, ${IDLE_N} idle helpers (${IDLE_MB} MB), ${DUP_N} repeated helpers, ${PORT_N} ports held by agent sessions.${1:-}"
}

NOTES=""
note() { NOTES="${NOTES}  - $1"$'\n'; }

gather() { # fills the globals the report and the share line use, from $SCAN
  LOAD=$(load1); SWAP=$(swap_used); FREE=$(mem_free_pct); ENERGY=$(energy_mode); THERM=$(thermal_limit)
  A_N=$(total AGENT "" 3); A_CPU=$(total AGENT "" 4); A_MEM=$(total AGENT "" 5)
  B_AGENT=$(total BUILD agent 3); B_AGENT_CPU=$(total BUILD agent 4)
  B_OWN=$(total BUILD own 3); B_OWN_CPU=$(total BUILD own 4)
  LEFT_N=$(count LEFT); SESS_N=$(count SESS); DUP_N=$(count DUP)
  ALL_CPU=$(total TOT "" 2); AG_CPU=$(total TOT "" 4); AG_MB=$(total TOT "" 5)
  AG_PCT=$(pct "$AG_CPU"); ALL_PCT=$(pct "$ALL_CPU")
  IDLE_N=$(total SESS "" 9); IDLE_MB=$(total SESS "" 10)
  PORTS=$(ports); PORT_N=$(echo "$PORTS" | awk 'NF { n++ } END { print n + 0 }')
}

stand_out() { # builds NOTES from what gather found
  NOTES=""
  if (( SESS_N > 0 )); then
    note "$SESS_N agent session(s) are running. Together they and everything they started use about ${AG_PCT}% of this Mac's CPU and $AG_MB MB of memory."
  fi
  if awk -v p="$AG_PCT" 'BEGIN { exit !(p >= 25) }'; then note "Agents are using a quarter or more of the CPU right now, so your own builds are sharing the machine with them."; fi
  if (( IDLE_N > 0 && IDLE_MB >= 100 )); then
    note "$IDLE_N helper process(es) inside agent sessions have been alive over 30 minutes and barely used any CPU, holding $IDLE_MB MB. (MCP servers waiting for requests look like this too, so it is not always a problem.)"
  fi
  local top; top=$(echo "$SCAN" | awk -F'\t' '$1 == "DUP"' | sort -t"$TAB" -k3 -nr | head -1)
  if [ -n "$top" ]; then
    note "The same helper was started $(echo "$top" | cut -f3) times across $(echo "$top" | cut -f5) place(s) inside agent sessions: $(echo "$top" | cut -f2) ($(echo "$top" | cut -f4) MB in total). Often that is one tool per session, which adds up."
  fi
  if (( PORT_N > 0 )); then note "Agent sessions (or things they left behind) are holding $PORT_N listening port(s) open. A new dev server on the same port can fail."; fi
  if (( LEFT_N > 0 )); then note "$LEFT_N helper process(es) look left over from sessions that ended."; fi
  if (( B_AGENT > 0 && B_OWN > 0 )); then note "An agent's build and a build that is not an agent's are running at the same time right now."; fi
  if [ "$ENERGY" = low ]; then note "Low Power Mode is on. macOS slows CPU-heavy work such as builds in that mode."; fi
  if [[ ${THERM:-100} =~ ^[0-9]+$ ]] && (( ${THERM:-100} < 100 )); then note "macOS has recorded a CPU speed limit of ${THERM}% (heat or power). The Mac is running slower than normal."; fi
  local swap_mb; swap_mb=$(echo "${SWAP:-0}" | awk '/G/ { v = $1; sub(/G/, "", v); print int(v * 1024); next } { v = $1; sub(/M/, "", v); print int(v) }')
  if [[ ${swap_mb:-0} =~ ^[0-9]+$ ]] && (( ${swap_mb:-0} >= 2048 )) && [[ ${FREE:-100} =~ ^[0-9]+$ ]] && (( ${FREE:-100} < 30 )); then
    note "Swap use is ${SWAP} and free memory is ${FREE}%. The Mac is short of memory."
  fi
  if [ -z "$NOTES" ]; then NOTES="  - Nothing stands out right now. Run it again while an agent is working hard."$'\n'; fi
}

snapshot() {
  SCAN=$(scan)
  gather
  stand_out

  if (( JSON )); then
    printf '{"version":"%s","cores":%s,"memory_gb":%s,"load_1m":%s,"swap_used":"%s","agents":%s,"agent_sessions":%s,"agent_cpu_percent_of_machine":%s,"agent_memory_mb":%s,"agent_builds":%s,"other_builds":%s,"possible_leftovers":%s,"idle_helpers":%s,"idle_helper_mb":%s,"repeated_helpers":%s,"ports_held":%s,"energy_mode":"%s"}\n' \
      "$VERSION" "$CPUS" "$MEM_GB" "${LOAD:-null}" "${SWAP:-?}" "$A_N" "$SESS_N" "$AG_PCT" "$AG_MB" "$B_AGENT" "$B_OWN" "$LEFT_N" "$IDLE_N" "$IDLE_MB" "$DUP_N" "$PORT_N" "$ENERGY"
    return
  fi

  echo "Yare doctor v$VERSION (read-only snapshot, nothing was changed)"
  echo "Mac: $CPUS cores, ${MEM_GB} GB memory. Load average (1 min): ${LOAD:-?}. Swap used: ${SWAP:-?}.${FREE:+ Memory free: ${FREE}%.}"
  echo "Energy mode: $ENERGY. CPU speed limit recorded by macOS: ${THERM:-none}${THERM:+%}."
  echo
  echo "WHAT STANDS OUT"
  printf '%s' "$NOTES"
  echo
  echo "AGENT SESSIONS (each agent plus everything it started)"
  if (( SESS_N == 0 )); then
    echo "  No coding agent found running."
  else
    printf '  %-12s %-8s %6s %7s %9s %9s  %s\n' "SESSION" "RUNNING" "PROCS" "CPU" "MEMORY" "CPU USED" "IDLE HELPERS"
    echo "$SCAN" | awk -F'\t' '$1 == "SESS" {
      mem = ($7 >= 1024) ? sprintf("%.1f GB", $7 / 1024) : sprintf("%d MB", $7)
      cu = ($8 >= 120) ? sprintf("%.1f h", $8 / 60) : sprintf("%d min", $8)
      idle = ($9 > 0) ? sprintf("%d (%d MB)", $9, $10) : "-"
      printf "  %-12s %-8s %6d %6.1f%% %9s %9s  %s\n", $2, $4, $5, $6, mem, cu, idle }'
    echo "  CPU USED counts only processes still alive. IDLE HELPERS: alive over 30 min and barely any CPU used."
  fi
  echo
  echo "WHO IS USING THE CPU RIGHT NOW (ps average; the owner is the agent session that started it)"
  echo "  Agent sessions: about ${AG_PCT}% of this Mac's CPU. Everything else: about $(awk -v a="$ALL_PCT" -v g="$AG_PCT" 'BEGIN { v = a - g; if (v < 0) v = 0; printf "%.0f", v }')%."
  local top; top=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP"' | sort -t"$TAB" -k4 -nr | head -6)
  if [ -n "$top" ]; then
    echo "$top" | awk -F'\t' '{ printf "  %-34s %6.1f%%  %6d MB  %s\n", $6, $4, $5, ($3 == "-" ? "not an agent" : "started by " $3) }'
  else
    echo "  Nothing above 1% CPU."
  fi
  echo
  echo "Builds and tests running: $((B_AGENT + B_OWN))"
  echo "   started by an agent:                  $B_AGENT  (about ${B_AGENT_CPU}% CPU)"
  echo "   not under any agent (likely yours):   $B_OWN  (about ${B_OWN_CPU}% CPU)"
  echo
  if (( DUP_N > 0 )); then
    echo "HELPERS STARTED MANY TIMES (3 or more of the same one inside agent sessions)"
    echo "$SCAN" | awk -F'\t' '$1 == "DUP"' | sort -t"$TAB" -k3 -nr | head -5 | awk -F'\t' '{ printf "   %3d x  %-34s %6d MB in total, across %d place(s)\n", $3, $2, $4, $5 }'
    echo
  fi
  if (( PORT_N > 0 )); then
    echo "PORTS HELD OPEN BY AGENT SESSIONS (or things they left behind)"
    echo "$PORTS" | awk -F'\t' '{ printf "   :%-6s %-12s %s\n", $2, $1, ($3 == "leftover" ? "no parent, looks left over" : "started by " $3) }'
    echo
  fi
  if (( LEFT_N > 0 )); then
    echo "Possible leftovers: $LEFT_N helper process(es) with no parent, alive over 30 minutes."
    echo "These may be from agent sessions that ended. Check before closing any of them."
    echo "   PID      CPU      MEMORY   RUNNING     COMMAND"
    echo "$SCAN" | awk -F'\t' '$1 == "LEFT" { printf "   %6s  %5s%%  %5d MB  up %-9s %s\n", $2, $3, $4, $5, $6 }'
    echo "To close one yourself: kill PID. This script never does."
  else
    echo "Possible leftovers: none found with this check."
  fi
  echo
  echo "How to read this: run it while an agent works and again when they are idle. Try --watch 60 to see how often"
  echo "an agent's build collided with yours. This is a rough snapshot, not a benchmark; the leftover and idle checks are"
  echo "heuristics that can be wrong, and ps CPU is an average, not an instant reading."
  if (( SHARE )); then
    echo
    echo "Paste-able summary (counts only, no paths, user names or commands):"
    share_line
  fi
  echo
  echo "We would like to hear what it found. Yare is an early prototype Mac tool, not released yet. Updates: $LINK"
}

watch_mode() {
  local samples=$(( WATCH_SECS / INTERVAL )) i
  local peak_agents=0 peak_ab=0 peak_ob=0 peak_load=0 peak_sess=0 overlap=0 agent_build_samples=0 own_build_samples=0
  local squeezed=0 busy=0 rows="" srows=""
  local swap_start; swap_start=$(swap_used)
  if (( ! JSON )); then
    echo "Yare doctor v$VERSION, watching for ${WATCH_SECS}s (a sample every ${INTERVAL}s, read-only). Use your Mac and your agents as you normally do."
    echo
    printf '%-9s %7s %9s %13s %12s %6s %9s\n' "time" "agents" "sessions" "agent builds" "your builds" "load" "agent CPU"
  fi
  for (( i = 1; i <= samples; i++ )); do
    SCAN=$(scan)
    local a ab ob l ns allc agc sp
    a=$(total AGENT "" 3); ab=$(total BUILD agent 3); ob=$(total BUILD own 3); l=$(load1); ns=$(count SESS)
    allc=$(total TOT "" 2); agc=$(total TOT "" 4); sp=$(pct "$agc")
    (( JSON )) || printf '%-9s %7s %9s %13s %12s %6s %8s%%\n' "$(date +%H:%M:%S)" "$a" "$ns" "$ab" "$ob" "${l:-?}" "$sp"
    (( a > peak_agents )) && peak_agents=$a
    (( ns > peak_sess )) && peak_sess=$ns
    (( ab > peak_ab )) && peak_ab=$ab
    (( ob > peak_ob )) && peak_ob=$ob
    if [ -n "${l:-}" ] && (( $(echo "${l:-0} > $peak_load" | bc 2>/dev/null || echo 0) )); then peak_load=$l; fi
    (( ab > 0 )) && agent_build_samples=$((agent_build_samples + 1))
    (( ob > 0 )) && own_build_samples=$((own_build_samples + 1))
    (( ab > 0 && ob > 0 )) && overlap=$((overlap + 1))
    # "busy": the Mac is at 80% or more of its CPU; "squeezed": busy and agents are at least a third of that load
    if awk -v a="$allc" -v g="$agc" -v c="$CORES" 'BEGIN { exit !(a / c >= 80) }'; then
      busy=$((busy + 1))
      if awk -v a="$allc" -v g="$agc" 'BEGIN { exit !(g >= a / 3) }'; then squeezed=$((squeezed + 1)); fi
    fi
    rows="${rows}${allc} ${agc}"$'\n'
    srows="${srows}$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $3, $2, $6 }')"$'\n'
    (( i < samples )) && sleep "$INTERVAL"
  done
  gather
  local swap_end; swap_end=$(swap_used)
  local ov_s=$(( overlap * INTERVAL )) ab_s=$(( agent_build_samples * INTERVAL )) ob_s=$(( own_build_samples * INTERVAL ))
  local sq_s=$(( squeezed * INTERVAL )) busy_s=$(( busy * INTERVAL ))
  local mins; mins=$(echo "$rows" | awk -v iv="$INTERVAL" 'NF { all += $1; ag += $2 } END { printf "%.1f %.1f", ag / 100 * iv / 60, (all - ag) / 100 * iv / 60 }')
  local ag_min=${mins% *} oth_min=${mins#* }
  local busiest; busiest=$(echo "$srows" | awk 'NF { s[$1] += $3; n[$1] = $2 } END { for (p in s) if (s[p] > m) { m = s[p]; b = n[p] " (pid " p ")" } print b }')
  LOAD=$peak_load; SWAP=$swap_end; B_AGENT=$peak_ab; B_OWN=$peak_ob
  if (( JSON )); then
    printf '{"version":"%s","watch_seconds":%s,"peak_agents":%s,"peak_sessions":%s,"peak_agent_builds":%s,"peak_other_builds":%s,"seconds_agent_builds_overlapped_other_builds":%s,"seconds_with_agent_builds":%s,"seconds_with_other_builds":%s,"seconds_machine_busy":%s,"seconds_squeezed_by_agents":%s,"agent_cpu_minutes":%s,"other_cpu_minutes":%s,"peak_load_1m":%s,"swap_used_start":"%s","swap_used_end":"%s"}\n' \
      "$VERSION" "$WATCH_SECS" "$peak_agents" "$peak_sess" "$peak_ab" "$peak_ob" "$ov_s" "$ab_s" "$ob_s" "$busy_s" "$sq_s" "$ag_min" "$oth_min" "${peak_load:-0}" "${swap_start:-?}" "${swap_end:-?}"
    return
  fi
  echo
  echo "Over ${WATCH_SECS}s, at most at once: $peak_agents agent processes in $peak_sess sessions, $peak_ab agent builds, $peak_ob builds not under an agent. Peak load $peak_load. Swap ${swap_start:-?} -> ${swap_end:-?}."
  echo "CPU used in the window: agents and what they started about $ag_min CPU-minutes, everything else about $oth_min."
  if [ -n "$busiest" ]; then echo "Busiest agent session: $busiest."; fi
  echo "The Mac was at 80% CPU or more for ~${busy_s}s; for ~${sq_s}s of that, agents were at least a third of the load."
  echo "An agent's build was running for ~${ab_s}s and a build of yours for ~${ob_s}s; they overlapped for ~${ov_s}s."
  if (( ov_s == 0 && sq_s == 0 )); then
    echo "No collision was seen in this window. That is a real result too: try again while an agent is building."
  fi
  if (( PORT_N > 0 )); then echo "At the end, agent sessions (or leftovers) were holding $PORT_N listening port(s) open. Run it without --watch to see which."; fi
  echo "Rough sampling, not a benchmark: it shows how often they collided, not how much it slowed you."
  if (( SHARE )); then
    echo
    echo "Paste-able summary (counts only, no paths, user names or commands):"
    share_line " Over ${WATCH_SECS}s agent builds overlapped non-agent builds for ~${ov_s}s and agents were a third or more of a busy Mac for ~${sq_s}s."
  fi
  echo
  echo "We would like to hear what it found. Yare is an early prototype Mac tool, not released yet. Updates: $LINK"
}

if [ "$MODE" = watch ]; then watch_mode; else snapshot; fi
