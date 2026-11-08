#!/bin/bash
# yare-doctor: read-only check of what your coding agents are running on this Mac.
# Uses only `ps`, `sysctl`, `memory_pressure`, `pmset`, `df`, `sw_vers` and `lsof` (listing, never connecting). No network, no files
# written, nothing killed or changed. Early prototype helper from the Yare project. It reports; it does not claim a speed-up.
# Works with the bash that ships with macOS (3.2).
#
# What it does that Activity Monitor does not: it follows the parent chain of every process, so it can say which agent
# session started what, how much of the Mac each session is holding, who is using the CPU, and what was left behind.
VERSION="0.6.0"
set -u

usage() {
  local b="" d="" x=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then b=$'\033[1m'; d=$'\033[2m'; x=$'\033[0m'; fi
  cat <<EOF
${b}yare-doctor $VERSION${x}  ${d}what are your coding agents doing to this Mac? Read-only.${x}

${b}USAGE${x}   bash yare-doctor.sh [option]

${b}LOOK${x}
  ${b}(no option)${x}      one snapshot now. Run it while your agents are working.
  ${b}--watch [SECS]${x}   sample every 5 s (default 60): how often an agent's build ran at the same time as one
                    of yours, and how long agents squeezed a busy Mac.
  ${b}--live${x}           the sessions and CPU tables, refreshed every 3 seconds (Ctrl-C to quit).
  ${b}--why PID${x}        who started this process? Prints its chain up to the agent session, if any.

${b}SHARE${x}
  ${b}--share${x}          add one line of counts (no paths, user names or commands) to paste in a reply.
  ${b}--redact${x}         hide folder names, helper names and leftover commands so the whole report can be pasted.
  ${b}--json${x}           machine-readable output instead of the report.

${b}CHECK${x}
  ${b}--selftest${x}       does every part work on this Mac? Prints PASS or FAIL for each (a few seconds).
  ${b}--checksum${x}       this file's sha256, to compare with the one in the GitHub release notes.
  ${b}--no-color${x}       plain text (also automatic when piped, or when NO_COLOR is set).  ${b}--version${x}

${d}It never changes anything: no network, no files written, nothing stopped. Read it first.${x}
EOF
}

MODE=snapshot; WATCH_SECS=60; SHARE=0; JSON=0; INTERVAL=5; REDACT=0; WHY_PID=; COLOR=auto
while [ $# -gt 0 ]; do
  case $1 in
    --watch) MODE=watch; if [[ ${2:-} =~ ^[0-9]+$ ]]; then WATCH_SECS=$2; shift; fi ;;
    --share) SHARE=1 ;;
    --json) JSON=1 ;;
    --selftest) MODE=selftest ;;
    --live) MODE=live ;;
    --redact) REDACT=1 ;;
    --checksum) MODE=checksum ;;
    --no-color|--no-colour) COLOR=0 ;;
    --color|--colour) COLOR=1 ;;
    --why) MODE=why; if [[ ${2:-} =~ ^[0-9]+$ ]]; then WHY_PID=$2; shift; else echo "--why needs a process id, for example: --why 1234" >&2; exit 2; fi ;;
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
#   SESS label rootpid age procs cpu% memMB cpuminutes idlecount idleMB builds forgotten stopped nestedagents host   one line per agent session
#   RUN pid owner cpu% age name        a process inside a session at 70%+ CPU for 10+ minutes (possible runaway)
#   STUCK pid owner state name         suspended (stopped) or zombie process inside a session
#   MEM pid owner memMB name           processes holding 300 MB or more, with the owner
#   TOP pid owner cpu% memMB name                          processes using CPU, with the agent session that owns them
#   BUILD agent|own count cpu%                             builds and tests, by whether an agent started them
#   DUP signature count memMB sessions                     the same helper started 3+ times inside agent sessions
#   LEFT pid cpu% memMB elapsed command                    helpers with no parent that look left over from ended sessions
#   MAP pid owner                                          processes owned by a session or left over (to match ports)
real_procs() { ps -axo pid=,ppid=,stat=,pcpu=,rss=,etime=,time=,command= 2>/dev/null; }
procs() { real_procs; }
scan() {
  procs | awk '
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
    if (b == "claude" || b == "codex" || b == "opencode" || b == "aider" || b == "cursor-agent" || b == "gemini" || b == "amp" || b == "goose" || b == "crush" || b == "droid" || b == "qwen" || b == "kiro-cli") return b
    if (low ~ /\/claude-code\//) return "claude"
    if (low ~ /@openai\/codex|\/codex\/bin\//) return "codex"
    return ""
  }
  function isbuild(low,   t, b) {
    split(low, t, " "); b = base(t[1])
    if (b ~ /^(clang|clang\+\+|cc1|swiftc|swift-frontend|swift-build|rustc|cargo|tsc|xcodebuild|gradle|make|ninja|webpack|esbuild|vite|ld)$/) return 1
    if (b ~ /^(xctest|swift-test|swiftpm-testing-helper|pytest)$/) return 1
    if (low ~ /node .*(jest|vitest|mocha|--test)/ || low ~ /(python|python3) .*(pytest|py\.test)/) return 1
    return 0
  }
  function appname(cmd,   i, s, t) {
    i = index(cmd, ".app/Contents/MacOS/")
    if (i) { s = substr(cmd, i + 20); sub(/ -.*/, "", s); return substr(s, 1, 34) }
    split(cmd, t, " "); return substr(base(t[1]), 1, 34)
  }
  function hostof(pid,   q, s, l) {
    q = P[pid]
    for (s = 0; s < 40 && q != "" && q > 1; s++) {
      l = LOW[q]
      if (l ~ /tmux/) return "tmux"
      if (l ~ /iterm/) return "iTerm"
      if (l ~ /terminal\.app/) return "Terminal"
      if (l ~ /ghostty/) return "Ghostty"
      if (l ~ /warp/) return "Warp"
      if (l ~ /alacritty/) return "Alacritty"
      if (l ~ /kitty/) return "kitty"
      if (l ~ /wezterm/) return "WezTerm"
      if (l ~ /visual studio code|vscode|code helper/) return "VS Code"
      if (l ~ /cursor/) return "Cursor"
      if (l ~ /windsurf/) return "Windsurf"
      if (l ~ /t3 code/) return "T3 Code"
      if (l ~ /conductor/) return "Conductor"
      if (l ~ /jetbrains|intellij/) return "JetBrains"
      q = P[q]
    }
    return "-"
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
    for (i = 8; i <= NF; i++) cmd = cmd (i > 8 ? " " : "") $i
    low = tolower(cmd)
    split(low, ft, " "); fb = base(ft[1])
    if (low ~ /yare-doctor/ || fb ~ /^(ps|awk|sort|lsof|pmset|sysctl|memory_pressure|bc|sleep|head|tr|sed|date)$/) next
    pid = $1; P[pid] = $2; ST[pid] = $3; C[pid] = $4 + 0; R[pid] = $5; E[pid] = $6; T[pid] = $7; CMD[pid] = cmd; LOW[pid] = low
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
    for (pid in n) if ((pid in AG) && ROOT[pid] != "" && ROOT[pid] != pid && P[pid] != ROOT[pid]) nest[ROOT[pid]]++
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
      if (pid != r && !(pid in HELP) && substr(ST[pid], 1, 1) ~ /[TZ]/) { stp[r]++; stuck = stuck sprintf("STUCK\t%s\t%s\t%s\t%s\n", pid, LABEL[r], substr(ST[pid], 1, 1), appname(CMD[pid])) }
      if (pid != r && !(pid in HELP) && C[pid] >= 70 && age > 600) runaway = runaway sprintf("RUN\t%s\t%s\t%.1f\t%s\t%s\n", pid, LABEL[r], C[pid], human(age), appname(CMD[pid]))
    }
    printf "%s%s", stuck, runaway
    printf "TOT\t%.1f\t%d\t%.1f\t%d\t%d\n", allcpu, allmem, agcpu, agmem, np
    for (i = 1; i <= nroots; i++) {
      r = roots[i]
      forgot = (etsecs(E[r]) > 43200 && scpu[r] < 0.5) ? 1 : 0
      printf "SESS\t%s\t%s\t%s\t%d\t%.1f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", LABEL[r], r, human(etsecs(E[r])), sp[r], scpu[r], smem[r], stime[r] / 60, idn[r] + 0, idm[r] + 0, sb[r] + 0, forgot, stp[r] + 0, nest[r] + 0, hostof(r)
    }

    for (pid in n) {
      owner = (ROOT[pid] != "") ? LABEL[ROOT[pid]] : "-"
      if (C[pid] >= 1.0) printf "TOP\t%s\t%s\t%.1f\t%d\t%s\n", pid, owner, C[pid], R[pid] / 1024, appname(CMD[pid])
      if (R[pid] / 1024 >= 300) printf "MEM\t%s\t%s\t%d\t%s\n", pid, owner, R[pid] / 1024, appname(CMD[pid])
    }

    for (pid in n) {
      if ((pid in HELP) || !isbuild(LOW[pid])) continue
      ow = (ROOT[pid] != "") ? "agent" : "own"
      bc[ow]++; bcpu[ow] += C[pid]; if (ROOT[pid] != "") sb[ROOT[pid]]++
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

# Folder each session works in: the current directory of the agent process (lsof only lists it, nothing is opened)
folders() {
  local pids; pids=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "%s%s", (n++ ? "," : ""), $3 }')
  [ -z "$pids" ] && return
  lsof -a -d cwd -Fpn -p "$pids" 2>/dev/null | awk '/^p/ { pid = substr($0, 2) } /^n/ { printf "%s\t%s\n", pid, substr($0, 2) }'
}

# What is keeping the Mac from sleeping, and which agent session started it (pmset only lists)
awake() {
  local map; map=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" { print $2 " " $3 }')
  awk 'NR == FNR { own[$1] = $2; next }
    /^ *pid [0-9]+\(/ && ($5 ~ /^(PreventUserIdleSystemSleep|PreventSystemSleep|NoIdleSleepAssertion|PreventUserIdleDisplaySleep|NoDisplaySleepAssertion)$/) {
      pid = $2; sub(/\(.*/, "", pid); name = $2; sub(/^[0-9]+\(/, "", name); sub(/\).*/, "", name)
      if (name == "powerd" || name == "coreaudiod") next
      kind = ($5 ~ /Display/) ? "screen" : "system"; k = pid SUBSEP kind; if (k in seen) next; seen[k] = 1
      printf "%s\t%s\t%s\t%s\n", name, kind, $4, ((pid in own) ? own[pid] : "-") }' <(printf '%s\n' "$map") <(pmset -g assertions 2>/dev/null)
}

disk_free_gb() { df -k "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }'; }
power_source() { pmset -g batt 2>/dev/null | awk -F"'" '/Now drawing/ { print ($2 ~ /Battery/ ? "battery" : "plug"); exit }'; }
battery_pct() { pmset -g batt 2>/dev/null | awk '/InternalBattery/ { for (i = 1; i <= NF; i++) if ($i ~ /%;?$/) { v = $i; gsub(/[%;]/, "", v); print v; exit } }'; }
macos_info() { echo "macOS $(sw_vers -productVersion 2>/dev/null), $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"; }
uptime_days() { sysctl -n kern.boottime 2>/dev/null | awk -v now="$(date +%s)" '{ for (i = 1; i <= NF; i++) if ($i == "sec") { v = $(i + 2); gsub(/,/, "", v); printf "%d", (now - v) / 86400; exit } }'; }
# Open files (numeric file descriptors) held by each session's processes. lsof only lists.
session_files() {
  local map pids; map=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" && $3 != "leftover" { print $2 " " $3 }')
  [ -z "$map" ] && return
  pids=$(echo "$map" | awk '{ printf "%s%s", (n++ ? "," : ""), $1 }')
  awk 'NR == FNR { own[$1] = $2; next } /^p/ { p = substr($0, 2) } /^f[0-9]/ { if (p in own) c[own[p]]++ } END { for (o in c) printf "%s\t%d\n", o, c[o] }' <(printf '%s\n' "$map") <(lsof -p "$pids" -Fpf 2>/dev/null)
}
limits() { echo "$(sysctl -n kern.num_files 2>/dev/null || echo 0) $(sysctl -n kern.maxfiles 2>/dev/null || echo 0) $(sysctl -n kern.maxproc 2>/dev/null || echo 0)"; }

LINK="https://meetyare.vercel.app/?utm_source=doctor&utm_medium=tool&utm_campaign=output"

share_line() { # $1 = extra text
  echo "Yare doctor v$VERSION ($OSINFO): $CPUS cores, ${MEM_GB} GB. Agents: $(agent_list) in ${SESS_N} sessions, using ${AG_PCT}% of CPU and ${AG_MB} MB. Builds: $B_AGENT started by agents, $B_OWN not. Load ${LOAD:-?}, swap ${SWAP:-?}, ${LEFT_N} possible leftovers, ${IDLE_N} idle helpers (${IDLE_MB} MB), ${DUP_N} repeated helpers, ${PORT_N} ports held, ${RUN_N} possible runaways, ${STUCK_N} suspended, ${FORGOT_N} forgotten sessions, ${AWAKE_N} sleep locks by agents, ${SHARED_N} shared folders.${1:-}"
}

# ---- notes: what stands out, sorted by how much it matters (1 act on it, 2 worth a look, 3 good to know) ----
NOTES=""
note() { NOTES="${NOTES}$1${TAB}$2"$'\n'; }

gather() { # fills the globals the report and the share line use, from $SCAN
  LOAD=$(load1); SWAP=$(swap_used); FREE=$(mem_free_pct); ENERGY=$(energy_mode); THERM=$(thermal_limit)
  A_N=$(total AGENT "" 3); A_CPU=$(total AGENT "" 4); A_MEM=$(total AGENT "" 5)
  B_AGENT=$(total BUILD agent 3); B_AGENT_CPU=$(total BUILD agent 4)
  B_OWN=$(total BUILD own 3); B_OWN_CPU=$(total BUILD own 4)
  LEFT_N=$(count LEFT); SESS_N=$(count SESS); DUP_N=$(count DUP); RUN_N=$(count RUN); STUCK_N=$(count STUCK)
  ALL_CPU=$(total TOT "" 2); AG_CPU=$(total TOT "" 4); AG_MB=$(total TOT "" 5); P_NOW=$(total TOT "" 6)
  AG_PCT=$(pct "$AG_CPU"); ALL_PCT=$(pct "$ALL_CPU")
  IDLE_N=$(total SESS "" 9); IDLE_MB=$(total SESS "" 10); FORGOT_N=$(total SESS "" 12)
  PORTS=$(ports); PORT_N=$(echo "$PORTS" | awk 'NF { n++ } END { print n + 0 }')
  FOLDERS=$(folders)
  if (( REDACT )); then
    FOLDERS=$(echo "$FOLDERS" | awk -F'\t' 'NF == 2 { if (!($2 in m)) m[$2] = "folder-" ++n; print $1 "\t/" m[$2] }')
    SCAN=$(echo "$SCAN" | awk -F'\t' -v OFS='\t' '$1 == "DUP" { if (!($2 in m)) m[$2] = "helper-" ++n; $2 = m[$2] } $1 == "LEFT" { $6 = "(command hidden)" } $1 == "RUN" { $6 = "process" } $1 == "STUCK" { $5 = "process" } 1')
  fi
  FILES=$(session_files)
  SHARED=$(echo "$FOLDERS" | awk -F'\t' -v h="$HOME" 'NF == 2 && $2 != "/" && $2 != h { c[$2]++ } END { for (p in c) if (c[p] > 1) { n = split(p, a, "/"); print c[p] "\t" a[n] } }')
  SHARED_N=$(echo "$SHARED" | awk 'NF { n++ } END { print n + 0 }')
  AWAKE=$(awake); AWAKE_N=$(echo "$AWAKE" | awk -F'\t' 'NF && $4 != "-" { n++ } END { print n + 0 }')
  UPD=$(uptime_days); DISK=$(disk_free_gb); PSRC=$(power_source); BATT=$(battery_pct); OSINFO=$(macos_info)
  read -r F_OPEN F_MAX P_MAX <<< "$(limits)"
}

stand_out() { # builds NOTES from what gather found
  NOTES=""
  local line top
  while IFS=$'\t' read -r _ pid owner cpu age name; do
    [ -n "${pid:-}" ] && note 1 "$name (pid $pid, started by $owner) is using ${cpu}% CPU and has been running $age. It may be stuck in a loop."
  done <<< "$(echo "$SCAN" | awk -F'\t' '$1 == "RUN"')"
  if [[ ${THERM:-100} =~ ^[0-9]+$ ]] && (( ${THERM:-100} < 100 )); then note 1 "macOS has recorded a CPU speed limit of ${THERM}% (heat or power). The Mac is running slower than normal."; fi
  local swap_mb; swap_mb=$(echo "${SWAP:-0}" | awk '/G/ { v = $1; sub(/G/, "", v); print int(v * 1024); next } { v = $1; sub(/M/, "", v); print int(v) }')
  if [[ ${swap_mb:-0} =~ ^[0-9]+$ ]] && (( ${swap_mb:-0} >= 2048 )) && [[ ${FREE:-100} =~ ^[0-9]+$ ]] && (( ${FREE:-100} < 30 )); then
    local big; big=$(echo "$SCAN" | awk -F'\t' '$1 == "MEM"' | sort -t"$TAB" -k4 -nr | head -1)
    note 1 "Swap use is $(fmt_size "$SWAP") and free memory is ${FREE}%. The Mac is short of memory.${big:+ The biggest holder is $(echo "$big" | cut -f5) at $(fmt_size "$(echo "$big" | cut -f4)M") ($(echo "$big" | cut -f3 | sed 's/^-$/not an agent/'))}."
  fi
  if awk -v p="$AG_PCT" 'BEGIN { exit !(p >= 25) }'; then note 2 "Agents are using a quarter or more of the CPU right now, so your own builds are sharing the machine with them."; fi
  if (( STUCK_N > 0 )); then note 2 "$(pl "$STUCK_N" process processes) inside agent sessions $( [ "$STUCK_N" = 1 ] && echo is || echo are) suspended or zombies. A suspended one still holds its memory."; fi
  line=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $12 == 1 { printf "%s%s (open %s, %d MB)", (n++ ? "; " : ""), $2, $4, $7 }')
  if [ -n "$line" ]; then note 2 "Looks forgotten (open over 12 hours, almost no CPU used): $line. Closing it would free that memory."; fi
  if (( SHARED_N > 0 )); then
    note 2 "More than one agent session is working in the same folder: $(echo "$SHARED" | awk -F'\t' '{ printf "%s%s (%d sessions)", (n++ ? ", " : ""), $2, $1 }'). They share its files and build output, so their builds can collide."
  fi
  line=$(echo "$FILES" | awk -F'\t' 'NF && $2 >= 2000 { printf "%s%s has %d files open", (n++ ? "; " : ""), $1, $2 }')
  if [ -n "$line" ]; then note 2 "Many open files: $line. Hitting the per-process limit causes 'too many open files' errors."; fi
  if (( AWAKE_N > 0 )); then note 2 "$(pl "$AWAKE_N" thing things) started by agent sessions $( [ "$AWAKE_N" = 1 ] && echo is || echo are) keeping this Mac from sleeping."; fi
  if (( LEFT_N > 0 )); then note 2 "$(pl "$LEFT_N" "helper process" "helper processes") $( [ "$LEFT_N" = 1 ] && echo looks || echo look) left over from sessions that ended."; fi
  if (( B_AGENT > 0 && B_OWN > 0 )); then note 2 "An agent's build and a build that is not an agent's are running at the same time right now."; fi
  # Slowness that is not the agents' doing: name the busiest background process when it is a known macOS or sync service
  top=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP" && $3 == "-" && $4 >= 15 && $6 ~ /^(mds|mds_stores|mdworker|mdworker_shared|backupd|photoanalysisd|photolibraryd|cloudd|fileproviderd|syspolicyd|trustd|kernel_task|XprotectService|XProtect|Dropbox|OneDrive|Google Drive)/' | sort -t"$TAB" -k4 -nr | head -1)
  if [ -n "$top" ]; then
    note 2 "$(echo "$top" | cut -f6) is using $(echo "$top" | cut -f4)% CPU and it is not an agent. If your Mac feels slow, this may be the cause."
    case $(echo "$top" | cut -f6) in mds*|mdworker*) note 3 "Spotlight indexes folders that agents write into (node_modules, build output). Excluding them in System Settings > Spotlight can help." ;; esac
  fi
  if [ "$ENERGY" = low ]; then note 2 "Low Power Mode is on. macOS slows CPU-heavy work such as builds in that mode."; fi
  if [[ ${DISK:-99} =~ ^[0-9]+$ ]] && (( ${DISK:-99} < 20 )); then note 2 "Only ${DISK} GB of disk is free. Builds, swap and caches can fail or slow down when the disk is this full."; fi
  if (( ${F_MAX:-0} > 0 && ${F_OPEN:-0} * 100 / ${F_MAX:-1} >= 60 )); then note 2 "The Mac has ${F_OPEN} files open out of a limit of ${F_MAX}. Agents and file watchers can hit that limit (errors like 'too many open files')."; fi
  if (( ${P_MAX:-0} > 0 && ${P_NOW:-0} * 100 / ${P_MAX:-1} >= 60 )); then note 2 "${P_NOW} processes are running out of a limit of ${P_MAX}. New processes can fail to start near the limit."; fi
  if [ "${PSRC:-}" = battery ]; then note 3 "The Mac is on battery${BATT:+ (${BATT}%)}. Builds and agents drain it fast, and macOS may slow them down."; fi
  line=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $14 > 0 { printf "%s%s runs %d nested agent process(es)", (n++ ? "; " : ""), $2, $14 }')
  if [ -n "$line" ]; then note 3 "Agents inside agents (parallel workers): $line."; fi
  if (( IDLE_N > 0 && IDLE_MB >= 100 )); then
    note 3 "$(pl "$IDLE_N" "helper process" "helper processes") inside agent sessions $( [ "$IDLE_N" = 1 ] && echo has || echo have) been alive over 30 minutes and barely used any CPU, holding $IDLE_MB MB. (MCP servers waiting for requests look like this too, so it is not always a problem.)"
  fi
  top=$(echo "$SCAN" | awk -F'\t' '$1 == "DUP"' | sort -t"$TAB" -k3 -nr | head -1)
  if [ -n "$top" ]; then
    note 3 "The same helper was started $(echo "$top" | cut -f3) times across $(pl "$(echo "$top" | cut -f5)" place places) inside agent sessions: $(echo "$top" | cut -f2) ($(echo "$top" | cut -f4) MB in total). Often that is one tool per session, which adds up."
  fi
  if (( PORT_N > 0 )); then note 3 "Agent sessions (or things they left behind) $( [ "$PORT_N" = 1 ] && echo is || echo are) holding $(pl "$PORT_N" "listening port") open. A new dev server on the same port can fail."; fi
  if (( SESS_N > 0 )); then
    note 3 "$(pl "$SESS_N" "agent session") $( [ "$SESS_N" = 1 ] && echo is || echo are) running. Together $( [ "$SESS_N" = 1 ] && echo it || echo they) and everything started under $( [ "$SESS_N" = 1 ] && echo it || echo them) use about ${AG_PCT}% of this Mac's CPU and $(fmt_size "${AG_MB}M")."
  fi
  if [ -z "$NOTES" ]; then note 4 "Nothing stands out right now. Run it again while an agent is working hard."; fi
}

# ---- terminal styling: colour only on a terminal (and when NO_COLOR is unset); plain text when piped ----
setup_ui() {
  COLS=${COLUMNS:-}; [[ $COLS =~ ^[0-9]+$ ]] || COLS=$(tput cols 2>/dev/null || echo 100); [[ $COLS =~ ^[0-9]+$ ]] || COLS=100
  if (( COLS > 110 )); then COLS=110; fi
  if (( COLS < 80 )); then COLS=80; fi
  if [ "$COLOR" = 1 ] || { [ "$COLOR" = auto ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }; then
    local e=$'\033'; B="$e[1m"; D="$e[2m"; R="$e[31m"; Y="$e[33m"; G="$e[32m"; C="$e[36m"; U="$e[4m"; X="$e[0m"
  else
    B=""; D=""; R=""; Y=""; G=""; C=""; U=""; X=""
  fi
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) FULL="█"; EMPTY="░"; DOT="●"; RUL="─"; ELL="…"; MID="·"; OK="✓"; NO="✗"; ARR="↳"; ARW="→"; SPARKS="▁ ▂ ▃ ▄ ▅ ▆ ▇ █" ;;
    *) FULL="#"; EMPTY="."; DOT="*"; RUL="-"; ELL="~"; MID="|"; OK="ok"; NO="X"; ARR=">"; ARW="->"; SPARKS="_ . , : - = + #" ;;
  esac
}
uawk() { awk -v ELL="$ELL" -v FULL="$FULL" -v EMPTY="$EMPTY" -v RED="$R" -v YEL="$Y" -v GRN="$G" -v CYA="$C" -v DIM="$D" -v BLD="$B" -v UND="$U" -v RST="$X" -v W="$COLS" -v RUL="$RUL" -v DOT="$DOT" -v ARR="$ARR" -v MID="$MID" -v SPARKS="$SPARKS" "$@"; }
AWKLIB='
function fit(s, w) { if (length(s) <= w) return s; return substr(s, 1, w - 1) ELL }
function pad(s, w) { return sprintf("%-" w "s", fit(s, w)) }
function bar(f, w,   n, i, o) { if (f < 0) f = 0; if (f > 1) f = 1; n = int(f * w + 0.5); o = ""; for (i = 1; i <= n; i++) o = o FULL; for (; i <= w; i++) o = o EMPTY; return o }
function heat(v, w, c) { return (v + 0 >= c) ? RED : (v + 0 >= w) ? YEL : "" }
function mb(v) { return (v >= 1024) ? sprintf("%.1f GB", v / 1024) : sprintf("%d MB", v) }
function spark(vals, mx,   n, a, i, g, ng, o, k) {
  ng = split(SPARKS, g, " "); n = split(vals, a, " "); o = ""
  if (mx < 1) mx = 1
  for (i = 1; i <= n; i++) { k = int(a[i] / mx * (ng - 1) + 0.5) + 1; if (k < 1) k = 1; if (k > ng) k = ng; o = o g[k] }
  return o
}
function pl(n, one, many) { return n (n == 1 ? " " one : " " many) }
function wrap(s, w, ind,   n, a, i, line, out) {
  n = split(s, a, " "); line = ""; out = ""
  for (i = 1; i <= n; i++) {
    if (line != "" && length(line) + 1 + length(a[i]) > w) { out = out line "\n" ind; line = a[i] }
    else line = (line == "" ? a[i] : line " " a[i])
  }
  return out line
}
'
fmt_size() { echo "$1" | awk '/G/ { v = $1; sub(/G/, "", v); printf "%.1f GB", v; next } { v = $1; sub(/M/, "", v); if (v >= 1024) printf "%.1f GB", v / 1024; else printf "%d MB", v }'; }
pl() { if [ "$1" = 1 ]; then echo "$1 $2"; else echo "$1 ${3:-${2}s}"; fi; }
fmt_k() { awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n / 1000; else printf "%d", n }'; }

rule() { printf '%s' "$D"; uawk 'BEGIN { for (i = 0; i < W - 2; i++) printf "%s", RUL }'; printf '%s\n' "$X"; }
banner() { printf '%syare-doctor%s  %s%s%s\n' "$B$C" "$X" "$D" "$1" "$X"; rule; }
section() { printf '\n%s%s%s' "$B" "$1" "$X"; if [ -n "${2:-}" ]; then printf '  %s%s%s' "$D" "$2" "$X"; fi; printf '\n'; }

print_notes() {
  local lv
  for lv in 1 2 3 4; do printf '%s' "$NOTES" | awk -F'\t' -v l="$lv" '$1 == l'; done | uawk -F'\t' -v OKM="$OK" "$AWKLIB"'
    { col = ($1 == 1) ? RED : ($1 == 2) ? YEL : ($1 == 3) ? CYA : GRN; mark = ($1 == 4) ? OKM : DOT
      printf "  %s%s%s %s\n", col, mark, RST, wrap($2, W - 6, "    ") }'
}

# ---- the machine at a glance ----
dash() {
  local ver chip used pw en
  ver=${OSINFO%%,*}; chip=${OSINFO#*, }
  used=$(( 100 - ${FREE:-100} ))
  case $ENERGY in low) en="low power mode" ;; high) en="high power mode" ;; *) en="normal power mode" ;; esac
  if [ "${PSRC:-}" = battery ]; then pw="on battery${BATT:+ ${BATT}%}"; else pw="plugged in"; fi
  uawk -v cpus="$CORES" -v load="${LOAD:-0}" -v used="$used" -v agp="$AG_PCT" -v ns="$SESS_N" -v chip="$chip" -v ver="$ver" -v mem="$MEM_GB" -v up="${UPD:-?}" \
    -v swap="$(fmt_size "${SWAP:-0M}")" -v agmem="$(fmt_size "${AG_MB}M")" -v pw="$pw" -v en="$en" -v disk="${DISK:-?}" -v files="$(fmt_k "${F_OPEN:-0}")" -v procs="${P_NOW:-?}" "$AWKLIB"'BEGIN {
    printf "  %s%-9s%s %s %s %s cores %s %s GB %s %s %s up %s %s\n", DIM, "Mac", RST, chip, MID, cpus, MID, mem, MID, ver, MID, up, (up == 1 ? "day" : "days")
    printf "  %s%-9s%s %s%s%s  %s on %s cores\n", DIM, "CPU load", RST, heat(load / cpus * 100, 70, 100), bar(load / cpus, 16), RST, load, cpus
    printf "  %s%-9s%s %s%s%s  %d%% used %s swap %s\n", DIM, "Memory", RST, heat(used, 80, 90), bar(used / 100, 16), RST, used, MID, swap
    printf "  %s%-9s%s %s%s%s  %s%% of the CPU %s %s %s %d %s\n", DIM, "Agents", RST, heat(agp, 25, 50), bar(agp / 100, 16), RST, agp, MID, agmem, MID, ns, (ns == 1 ? "session" : "sessions")
    printf "  %s%-9s%s %s %s %s %s %s GB disk free %s %s files open %s %s processes\n", DIM, "Power", RST, pw, MID, en, MID, disk, MID, files, MID, procs
  }'
}

# ---- tables ----
sessions_table() {
  if (( SESS_N == 0 )); then printf '  %sNo coding agent found running.%s\n' "$D" "$X"; return; fi
  uawk -F'\t' "$AWKLIB"'
    FNR == 1 { fi++ }
    fi == 1 { n = split($2, a, "/"); fold[$1] = a[n]; next }
    fi == 2 { fc[$1] = $2; next }
    $1 == "SESS" {
      if (!hdr++) printf "  %s%-10s %-15s %-10s %8s %5s %7s %9s %6s %6s%s\n", DIM, "SESSION", "FOLDER", "HOST", "RUNNING", "PROCS", "CPU", "MEMORY", "FILES", "BUILDS", RST
      files = ($2 in fc) ? fc[$2] : "-"
      printf "  %s%-10s%s %-15s %-10s %8s %5d %s%7s%s %s%9s%s %s%6s%s %6d\n", BLD, $2, RST, pad(($3 in fold) ? fold[$3] : "-", 15), pad($15, 10), $4, $5, heat($6, 50, 100), sprintf("%.1f%%", $6), RST, heat($7, 1500, 4000), mb($7), RST, heat(files, 2000, 8000), files, RST, $11
      s = ""
      if ($12 == 1) s = s YEL "looks forgotten" RST DIM
      if ($13 > 0) s = s (s == "" ? "" : "  ") YEL $13 " suspended" RST DIM
      if ($14 > 0) s = s (s == "" ? "" : "  ") pl($14, "nested agent", "nested agents")
      if ($9 > 0) s = s (s == "" ? "" : "  ") pl($9, "idle helper", "idle helpers") " holding " mb($10)
      if ($8 >= 5) s = s (s == "" ? "" : "  ") sprintf("used %d CPU-min", $8)
      if (s != "") printf "  %s  %s %s%s\n", DIM, ARR, s, RST
    }' <(printf '%s\n' "$FOLDERS") <(printf '%s\n' "$FILES") <(echo "$SCAN")
}

cpu_table() {
  local top; top=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP"' | sort -t"$TAB" -k4 -nr | head -6)
  if [ -z "$top" ]; then printf '  %sNothing above 1%% CPU.%s\n' "$D" "$X"; return; fi
  echo "$top" | uawk -F'\t' "$AWKLIB"'
    { name[NR] = $6; cpu[NR] = $4; mem[NR] = $5; own[NR] = $3; if ($4 > mx) mx = $4 }
    END {
      printf "  %s%-30s  %-8s %7s %9s  %s%s\n", DIM, "PROCESS", "", "CPU", "MEMORY", "STARTED BY", RST
      for (i = 1; i <= NR; i++)
        printf "  %-30s  %s%s%s %s%7s%s %9s  %s\n", pad(name[i], 30), heat(cpu[i], 100, 250), bar(cpu[i] / mx, 8), RST, heat(cpu[i], 100, 250), sprintf("%.1f%%", cpu[i]), RST, mb(mem[i]), (own[i] == "-" ? DIM "not an agent" RST : CYA own[i] RST)
    }'
  printf '  %sAgent sessions use about %s%% of the CPU, everything else about %s%% (ps shows an average).%s\n' "$D" "$AG_PCT" "$(awk -v a="$ALL_PCT" -v g="$AG_PCT" 'BEGIN { v = a - g; if (v < 0) v = 0; printf "%.0f", v }')" "$X"
}

mem_table() {
  local mt; mt=$(echo "$SCAN" | awk -F'\t' '$1 == "MEM"' | sort -t"$TAB" -k4 -nr | head -5)
  [ -z "$mt" ] && return
  section "WHO HOLDS THE MOST MEMORY" "300 MB or more each"
  echo "$mt" | uawk -F'\t' "$AWKLIB"'
    { name[NR] = $5; mem[NR] = $4; own[NR] = $3; if ($4 > mx) mx = $4 }
    END {
      printf "  %s%-30s  %-8s %9s  %s%s\n", DIM, "PROCESS", "", "MEMORY", "STARTED BY", RST
      for (i = 1; i <= NR; i++)
        printf "  %-30s  %s%s%s %s%9s%s  %s\n", pad(name[i], 30), heat(mem[i], 2000, 6000), bar(mem[i] / mx, 8), RST, heat(mem[i], 2000, 6000), mb(mem[i]), RST, (own[i] == "-" ? DIM "not an agent" RST : CYA own[i] RST)
    }'
}

footer() {
  printf '\n%sA rough snapshot, not a benchmark: the idle, leftover and runaway checks are heuristics, and ps CPU is an average.%s\n' "$D" "$X"
  printf '%sTry --watch 60 while an agent builds, --live for a refreshing view, --why PID for who started a process.%s\n' "$D" "$X"
  if (( SHARE )); then
    section "PASTE-ABLE SUMMARY" "counts only: no paths, user names or commands"
    echo "$1"
  fi
  printf '\n%sWe would like to hear what it found. Yare is an early prototype Mac tool, not released yet: %s%s\n' "$D" "$LINK" "$X"
}

snapshot() {
  SCAN=$(scan)
  gather
  stand_out

  if (( JSON )); then
    local sj; sj=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "%s{\"label\":\"%s\",\"processes\":%d,\"cpu_percent\":%s,\"memory_mb\":%d,\"cpu_minutes\":%d,\"idle_helpers\":%d,\"builds\":%d,\"looks_forgotten\":%s}", (n++ ? "," : ""), $2, $5, $6, $7, $8, $9, $11, ($12 == 1 ? "true" : "false") }')
    printf '{"version":"%s","macos":"%s","cores":%s,"memory_gb":%s,"load_1m":%s,"swap_used":"%s","agents":%s,"agent_sessions":%s,"agent_cpu_percent_of_machine":%s,"agent_memory_mb":%s,"agent_builds":%s,"other_builds":%s,"possible_leftovers":%s,"idle_helpers":%s,"idle_helper_mb":%s,"repeated_helpers":%s,"ports_held":%s,"possible_runaways":%s,"suspended_or_zombie":%s,"forgotten_sessions":%s,"sleep_locks_by_agents":%s,"shared_folders":%s,"disk_free_gb":%s,"energy_mode":"%s","sessions":[%s]}\n' \
      "$VERSION" "$OSINFO" "$CPUS" "$MEM_GB" "${LOAD:-null}" "${SWAP:-?}" "$A_N" "$SESS_N" "$AG_PCT" "$AG_MB" "$B_AGENT" "$B_OWN" "$LEFT_N" "$IDLE_N" "$IDLE_MB" "$DUP_N" "$PORT_N" "$RUN_N" "$STUCK_N" "$FORGOT_N" "$AWAKE_N" "$SHARED_N" "${DISK:-null}" "$ENERGY" "$sj"
    return
  fi

  banner "$VERSION $MID read-only $MID nothing was changed"
  echo
  dash
  section "WHAT STANDS OUT"
  print_notes
  section "AGENT SESSIONS" "each agent and everything it started"
  sessions_table
  section "WHO IS USING THE CPU" "the owner is the agent session that started it"
  cpu_table
  mem_table
  if (( RUN_N + STUCK_N > 0 )); then
    section "NEEDS A LOOK" "inside agent sessions"
    echo "$SCAN" | uawk -F'\t' "$AWKLIB"'
      $1 == "RUN" { printf "  %s%s%s %s is at %s%% CPU after running %s: it may be stuck in a loop %s(started by %s, pid %s)%s\n", RED, DOT, RST, pad($6, 22), $4, $5, DIM, $3, $2, RST }
      $1 == "STUCK" { printf "  %s%s%s %s is %s %s(started by %s, pid %s): %s%s\n", YEL, DOT, RST, pad($5, 22), ($4 == "Z" ? "a zombie" : "suspended"), DIM, $3, $2, ($4 == "Z" ? "already finished, waiting for its parent" : "it still holds its memory"), RST }'
  fi
  section "BUILDS AND TESTS" "agent-started and yours"
  printf '  %-36s %3d   %s%s%% CPU%s\n' "started by an agent" "$B_AGENT" "$D" "$B_AGENT_CPU" "$X"
  printf '  %-36s %3d   %s%s%% CPU%s\n' "not under any agent (likely yours)" "$B_OWN" "$D" "$B_OWN_CPU" "$X"
  if (( B_AGENT > 0 && B_OWN > 0 )); then printf '  %s%s both kinds are running at the same time right now%s\n' "$Y" "$DOT" "$X"; fi
  if (( DUP_N > 0 )); then
    section "THE SAME HELPER STARTED MANY TIMES" "3 or more inside agent sessions"
    echo "$SCAN" | awk -F'\t' '$1 == "DUP"' | sort -t"$TAB" -k3 -nr | head -5 | uawk -F'\t' "$AWKLIB"'{ printf "  %s%3d x%s  %-34s %9s  %sacross %s%s\n", BLD, $3, RST, pad($2, 34), mb($4), DIM, pl($5, "session", "sessions"), RST }'
  fi
  if (( PORT_N > 0 )); then
    section "PORTS HELD OPEN" "by agent sessions, or things they left behind"
    echo "$PORTS" | uawk -F'\t' "$AWKLIB"'{ printf "  %s:%-6s%s %-14s %s\n", BLD, $2, RST, pad($1, 14), ($3 == "leftover" ? DIM "no parent: looks left over" RST : CYA $3 RST) }'
  fi
  if [ -n "$AWAKE" ]; then
    section "WHAT KEEPS THIS MAC AWAKE" "apart from macOS itself"
    echo "$AWAKE" | uawk -F'\t' "$AWKLIB"'NF { k = $1 SUBSEP $4; if (!(k in seen)) { seen[k] = 1; ord[++n] = k; nm[k] = $1; ow[k] = $4; du[k] = $3 } kinds[k] = (k in kinds) ? ((index(kinds[k], $2) ? kinds[k] : kinds[k] " and " $2)) : $2 }
      END { for (i = 1; i <= n; i++) { k = ord[i]; printf "  %s  keeps the %s awake %s(%s)%s  %s\n", pad(nm[k], 14), kinds[k], DIM, du[k], RST, (ow[k] == "-" ? DIM "not an agent" RST : CYA ow[k] RST) } }'
  fi
  if (( LEFT_N > 0 )); then
    section "POSSIBLE LEFTOVERS" "no parent, alive over 30 minutes: may be from sessions that ended"
    echo "$SCAN" | uawk -F'\t' "$AWKLIB"'$1 == "LEFT" { if (!h++) printf "  %s%8s %6s %9s %-10s %s%s\n", DIM, "PID", "CPU", "MEMORY", "RUNNING", "COMMAND", RST; printf "  %8s %5s%% %9s %-10s %s\n", $2, $3, mb($4), $5, $6 }'
    printf '  %sCheck before closing any of them. To close one yourself: kill PID. This script never does.%s\n' "$D" "$X"
  fi
  footer "$( (( SHARE )) && share_line )"
}

# ---- --watch: a table that fills in as it samples, then a short result ----
watch_mode() {
  local samples=$(( WATCH_SECS / INTERVAL )) i
  local peak_agents=0 peak_ab=0 peak_ob=0 peak_load=0 peak_sess=0 overlap=0 agent_build_samples=0 own_build_samples=0
  local squeezed=0 busy=0 rows="" srows="" first_mem="" last_mem=0 allpids="" n0="" spk=""
  local swap_start; swap_start=$(swap_used)
  if (( ! JSON )); then
    banner "$VERSION $MID watching for ${WATCH_SECS}s $MID a sample every ${INTERVAL}s $MID read-only"
    printf '%sUse your Mac and your agents as you normally do.%s\n\n' "$D" "$X"
    printf '  %s%-9s %-24s %6s %9s %13s %12s%s\n' "$D" "TIME" "AGENT CPU" "LOAD" "SESSIONS" "AGENT BUILDS" "YOUR BUILDS" "$X"
  fi
  for (( i = 1; i <= samples; i++ )); do
    SCAN=$(scan)
    local a ab ob l ns allc agc sp
    a=$(total AGENT "" 3); ab=$(total BUILD agent 3); ob=$(total BUILD own 3); l=$(load1); ns=$(count SESS)
    allc=$(total TOT "" 2); agc=$(total TOT "" 4); sp=$(pct "$agc")
    spk="$spk $sp"
    if (( ! JSON )); then
      uawk -v t="$(date +%H:%M:%S)" -v sp="$sp" -v l="${l:-0}" -v cores="$CORES" -v ns="$ns" -v ab="$ab" -v ob="$ob" "$AWKLIB"'BEGIN {
        mark = (ab > 0 && ob > 0) ? "  " YEL "< both building" RST : ""
        printf "  %-9s %s%s%s %5s%% %s%6s%s %9s %13s %12s%s\n", t, heat(sp, 25, 50), bar(sp / 100, 16), RST, sp, heat(l / cores * 100, 70, 100), l, RST, ns, ab, ob, mark }'
    fi
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
    srows="${srows}$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $3, $2, $6, $7 }')"$'\n'
    last_mem=$(total TOT "" 5); [ -z "$first_mem" ] && first_mem=$last_mem
    local pl; pl=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" && $3 != "leftover" { print $2 }')
    allpids="${allpids}${pl}"$'\n'; [ -z "$n0" ] && n0=$(echo "$pl" | awk 'NF { n++ } END { print n + 0 }')
    (( i < samples )) && sleep "$INTERVAL"
  done
  gather
  local swap_end; swap_end=$(swap_used)
  local ov_s=$(( overlap * INTERVAL )) ab_s=$(( agent_build_samples * INTERVAL )) ob_s=$(( own_build_samples * INTERVAL ))
  local sq_s=$(( squeezed * INTERVAL )) busy_s=$(( busy * INTERVAL ))
  local mins; mins=$(echo "$rows" | awk -v iv="$INTERVAL" 'NF { all += $1; ag += $2 } END { printf "%.1f %.1f", ag / 100 * iv / 60, (all - ag) / 100 * iv / 60 }')
  local ag_min=${mins% *} oth_min=${mins#* }
  local busiest; busiest=$(echo "$srows" | awk 'NF { s[$1] += $3; n[$1] = $2 } END { for (p in s) if (s[p] > m) { m = s[p]; b = n[p] " (pid " p ")" } print b }')
  local grow; grow=$(echo "$srows" | awk 'NF { if (!($1 in f)) { f[$1] = $4; nm[$1] = $2 } l[$1] = $4 } END { for (p in l) { d = l[p] - f[p]; if (d > m) { m = d; b = nm[p] " (pid " p ")" } } if (m >= 50) printf "%s +%d MB", b, m }')
  local newp; newp=$(echo "$allpids" | sort -u | awk -v n0="${n0:-0}" 'NF { n++ } END { v = n - n0; print (v > 0 ? v : 0) }')
  LOAD=$peak_load; SWAP=$swap_end; B_AGENT=$peak_ab; B_OWN=$peak_ob
  if (( JSON )); then
    printf '{"version":"%s","watch_seconds":%s,"peak_agents":%s,"peak_sessions":%s,"peak_agent_builds":%s,"peak_other_builds":%s,"seconds_agent_builds_overlapped_other_builds":%s,"seconds_with_agent_builds":%s,"seconds_with_other_builds":%s,"seconds_machine_busy":%s,"seconds_squeezed_by_agents":%s,"agent_cpu_minutes":%s,"other_cpu_minutes":%s,"agent_memory_mb_start":%s,"agent_memory_mb_end":%s,"new_processes_seen":%s,"peak_load_1m":%s,"swap_used_start":"%s","swap_used_end":"%s"}\n' \
      "$VERSION" "$WATCH_SECS" "$peak_agents" "$peak_sess" "$peak_ab" "$peak_ob" "$ov_s" "$ab_s" "$ob_s" "$busy_s" "$sq_s" "$ag_min" "$oth_min" "${first_mem:-0}" "${last_mem:-0}" "$newp" "${peak_load:-0}" "${swap_start:-?}" "${swap_end:-?}"
    return
  fi
  local line_sparks; line_sparks=$(uawk -v v="$spk" "$AWKLIB"'BEGIN { mx = 0; n = split(v, a, " "); for (i = 1; i <= n; i++) if (a[i] + 0 > mx) mx = a[i] + 0; print spark(v, mx) }')
  section "RESULT" "over ${WATCH_SECS}s"
  printf '  %s%-16s%s agent CPU over time  %s%s%s\n' "$D" "Trend" "$X" "$C" "$line_sparks" "$X"
  if (( ov_s > 0 )); then
    printf '  %s%-16s%s %s%s%s an agent build ran for ~%ss and a build of yours for ~%ss; they overlapped for ~%ss\n' "$D" "Collisions" "$X" "$Y" "$DOT" "$X" "$ab_s" "$ob_s" "$ov_s"
  else
    printf '  %s%-16s%s %s%s%s no overlap seen (agent builds ~%ss, yours ~%ss)\n' "$D" "Collisions" "$X" "$G" "$OK" "$X" "$ab_s" "$ob_s"
  fi
  if (( sq_s > 0 )); then
    printf '  %s%-16s%s %s%s%s the Mac was at 80%% CPU or more for ~%ss; agents were a third or more of it for ~%ss\n' "$D" "Squeeze" "$X" "$Y" "$DOT" "$X" "$busy_s" "$sq_s"
  else
    printf '  %s%-16s%s %s%s%s the Mac was at 80%% CPU or more for ~%ss, with agents never a third of it\n' "$D" "Squeeze" "$X" "$G" "$OK" "$X" "$busy_s"
  fi
  printf '  %s%-16s%s agents and what they started: %s CPU-min %s everything else: %s CPU-min\n' "$D" "CPU used" "$X" "$ag_min" "$MID" "$oth_min"
  printf '  %s%-16s%s agent sessions: %s %s %s%s\n' "$D" "Memory" "$X" "$(fmt_size "${first_mem:-0}M")" "$ARW" "$(fmt_size "${last_mem:-0}M")" "${grow:+  $MID biggest growth: $grow}"
  printf '  %s%-16s%s at least %s started by agent sessions %s(very short-lived ones between samples are missed)%s\n' "$D" "New processes" "$X" "$newp" "$D" "$X"
  if [ -n "$busiest" ]; then printf '  %s%-16s%s %s\n' "$D" "Busiest session" "$X" "$busiest"; fi
  printf '  %s%-16s%s %s in %s %s load %s %s swap %s %s %s\n' "$D" "Peak" "$X" "$(pl "$peak_agents" "agent process" "agent processes")" "$(pl "$peak_sess" session sessions)" "$MID" "$peak_load" "$MID" "$(fmt_size "${swap_start:-0M}")" "$ARW" "$(fmt_size "${swap_end:-0M}")"
  if (( ov_s == 0 && sq_s == 0 )); then
    printf '\n  %sNo collision in this window. That is a real result too: try again while an agent is building.%s\n' "$D" "$X"
  fi
  printf '\n%sRough sampling, not a benchmark: it shows how often they collided, not how much it slowed you.%s\n' "$D" "$X"
  if (( SHARE )); then
    section "PASTE-ABLE SUMMARY" "counts only: no paths, user names or commands"
    share_line " Over ${WATCH_SECS}s agent builds overlapped non-agent builds for ~${ov_s}s and agents were a third or more of a busy Mac for ~${sq_s}s."
  fi
  printf '\n%sWe would like to hear what it found. Yare is an early prototype Mac tool, not released yet: %s%s\n' "$D" "$LINK" "$X"
}

# ---- --why PID: the chain of processes that started one process ----
why() {
  SCAN=$(scan)
  local out; out=$(real_procs | uawk -v t="$WHY_PID" "$AWKLIB"'
    function etsecs(x,   d, y, p, n) { d = 0; if (index(x, "-")) { split(x, y, "-"); d = y[1]; x = y[2] }; n = split(x, p, ":"); if (n == 3) return d*86400 + p[1]*3600 + p[2]*60 + p[3]; if (n == 2) return d*86400 + p[1]*60 + p[2]; return d*86400 + p[1] }
    function human(v,   d, h, m) { d = int(v / 86400); h = int((v % 86400) / 3600); m = int((v % 3600) / 60); if (d > 0) return d "d " h "h"; if (h > 0) return h "h " m "m"; return m "m" }
    function short(c,   a, k, o, i, r, n, j) {
      j = index(c, ".app/Contents/MacOS/"); if (j) { r = substr(c, j + 20); sub(/ -.*/, "", r); return substr(r, 1, 40) }
      k = split(c, a, " "); n = split(a[1], o, "/"); r = o[n]
      for (i = 2; i <= k && i <= 3; i++) r = r " " ((a[i] ~ /\//) ? substr(a[i], length(a[i]) - 24) : a[i])
      return substr(r, 1, 60)
    }
    { P[$1] = $2; C[$1] = $4; R[$1] = $5; E[$1] = $6; cmd = ""; for (i = 8; i <= NF; i++) cmd = cmd (i > 8 ? " " : "") $i; N[$1] = cmd }
    END {
      if (!(t in N)) { print "No process with pid " t "."; exit 1 }
      q = t; d = 0
      while (q in N && d < 30) { chain[++d] = q; q = P[q]; if (q <= 1) break }
      for (i = d; i >= 1; i--) {
        pad2 = ""; for (j = 0; j < d - i; j++) pad2 = pad2 "  "
        printf "  %s%s%s%s%s  %s(pid %s) %.1f%% CPU, %s, running %s%s\n", pad2, (i == 1 ? BLD : ""), (i < d ? ARR " " : ""), short(N[chain[i]]), RST, DIM, chain[i], C[chain[i]], mb(R[chain[i]] / 1024), human(etsecs(E[chain[i]])), RST
      }
      list = ""; for (i = 1; i <= d; i++) list = list " " chain[i]
      print "@@CHAIN" list
    }') || { echo "$out"; return 1; }
  banner "$VERSION $MID who started pid $WHY_PID?"
  echo
  echo "$out" | grep -v '^@@CHAIN'
  local owner="" p
  for p in $(echo "$out" | awk '/^@@CHAIN/ { $1 = ""; print }'); do
    owner=$(echo "$SCAN" | awk -F'\t' -v p="$p" '$1 == "MAP" && $2 == p { print $3; exit }')
    [ -n "$owner" ] && break
  done
  echo
  if [ -n "$owner" ] && [ "$owner" != leftover ]; then printf '  %s%s%s it belongs to agent session %s%s%s\n' "$C" "$ARW" "$X" "$B" "$owner" "$X"; else printf '  %s%s it is not under any coding agent we recognise%s\n' "$D" "$ARW" "$X"; fi
}

# ---- --live: the same sessions and CPU tables, refreshed in place ----
live() {
  local hist="" frame tty=0
  [ -t 1 ] && tty=1
  if (( tty )); then trap 'printf "\033[?25h\n"; exit 0' INT TERM; printf '\033[?25l\033[2J'; else trap 'exit 0' INT TERM; fi
  while true; do
    SCAN=$(scan); gather
    hist=$(echo "$hist $AG_PCT" | awk '{ n = NF; s = (n > 48) ? n - 47 : 1; o = ""; for (i = s; i <= n; i++) o = o " " $i; print substr(o, 2) }')
    frame=$(
      banner "$VERSION $MID live $MID every 3 s $MID Ctrl-C to quit $MID read-only"
      echo
      dash
      printf '  %s%-9s%s agent CPU, last %s samples  %s%s%s\n' "$D" "Trend" "$X" "$(echo "$hist" | wc -w | tr -d ' ')" "$C" "$(uawk -v v="$hist" "$AWKLIB"'BEGIN { n = split(v, a, " "); for (i = 1; i <= n; i++) if (a[i] + 0 > mx) mx = a[i] + 0; print spark(v, mx) }')" "$X"
      section "AGENT SESSIONS"
      sessions_table
      section "WHO IS USING THE CPU"
      cpu_table
    )
    if (( tty )); then printf '\033[H%s\033[J' "$frame"; else printf '%s\n\n' "$frame"; fi
    sleep 3
  done
}

checksum() {
  local f="${BASH_SOURCE[0]:-$0}"
  if [ -f "$f" ]; then
    echo "sha256 $(shasum -a 256 "$f" | cut -d' ' -f1)  yare-doctor $VERSION"
    echo "Compare it with the checksum in the release notes at https://github.com/Yare-Org/yare-doctor/releases"
  else
    echo "Not running from a file (for example piped into bash), so there is nothing to hash. Download the file and run it with bash."
  fi
}

# ---- --selftest: does every part work on this Mac? ----
selftest() {
  local pass=0 fail=0 t
  chk() {
    if [ "$2" = "$3" ]; then printf '  %s%s%s  %s\n' "$G" "$OK" "$X" "$1"; pass=$((pass + 1))
    else printf '  %s%s%s  %s %s(expected %s, got %s)%s\n' "$R" "$NO" "$X" "$1" "$D" "$3" "${2:-nothing}" "$X"; fail=$((fail + 1)); fi
  }
  banner "$VERSION $MID self-test $MID read-only"
  printf '%sbash %s, %s%s\n' "$D" "$BASH_VERSION" "$(macos_info)" "$X"
  section "TOOLS" "everything the script relies on"
  for t in ps sysctl pmset lsof df sw_vers memory_pressure awk sort sed; do
    if command -v "$t" >/dev/null 2>&1; then chk "$t is available" ok ok; else chk "$t is available" missing ok; fi
  done
  # 1) the parser on a made-up process list with known answers
  procs() { cat <<'EOF'
10 1 S 0.5 90000 05:00:00 00:30.00 /Applications/iTerm.app/Contents/MacOS/iTerm2
100 10 S 1.0 100000 02:00:00 00:10.00 /usr/local/bin/claude --resume
101 100 S 0.0 50000 01:30:00 00:00.10 node /x/mcp-server.js
102 100 S 0.0 50000 01:30:00 00:00.10 node /y/mcp-server.js
103 100 S 0.0 50000 01:30:00 00:00.10 node /z/mcp-server.js
104 100 S 5.0 20000 01:00 00:02.00 /usr/bin/clang -c a.c
105 104 T 0.0 1000 20:00 00:00.00 worker
106 100 R 90.0 80000 20:00 00:12.00 python3 loop.py
107 106 S 0.0 1000 01:00 00:00.01 /usr/local/bin/claude -p subtask
300 1 S 0.0 40000 01:00:00 00:00.10 node /w/mcp-leftover.js
EOF
  }
  SCAN=$(scan)
  section "PARSER" "a made-up process list with known answers"
  chk "one agent session found" "$(count SESS)" 1
  chk "session has 8 processes" "$(total SESS "" 5)" 8
  chk "nested agent found" "$(total SESS "" 14)" 1
  chk "terminal app found (iTerm)" "$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $15 }')" iTerm
  chk "agent build found under the agent" "$(total BUILD agent 3)" 1
  chk "same helper 3 times found" "$(echo "$SCAN" | awk -F'\t' '$1 == "DUP" { print $3 }')" 3
  chk "leftover found" "$(count LEFT)" 1
  chk "suspended process found" "$(count STUCK)" 1
  chk "runaway process found" "$(count RUN)" 1
  procs() { real_procs; }
  # 2) the real Mac
  SCAN=$(scan)
  section "THIS MAC" "live readings"
  chk "process list read (more than 20 processes)" "$([ "$(total TOT "" 6)" -gt 20 ] 2>/dev/null && echo ok || echo no)" ok
  chk "load average readable" "$([ -n "$(load1)" ] && echo ok || echo no)" ok
  chk "swap readable" "$([ -n "$(swap_used)" ] && echo ok || echo no)" ok
  chk "memory pressure readable" "$([ -n "$(mem_free_pct)" ] && echo ok || echo no)" ok
  chk "disk space readable" "$([ -n "$(disk_free_gb)" ] && echo ok || echo no)" ok
  chk "power settings readable" "$([ -n "$(energy_mode)" ] && echo ok || echo no)" ok
  chk "open-port listing works" "$(lsof -nP -iTCP -sTCP:LISTEN >/dev/null 2>&1; echo $?)" 0
  chk "sleep-lock listing works" "$(pmset -g assertions >/dev/null 2>&1; echo $?)" 0
  echo
  if (( fail == 0 )); then
    printf '%s%s All %s checks passed.%s\n' "$G$B" "$OK" "$pass" "$X"
  else
    printf '%s%s %s of %s checks failed.%s Please send this line when you report it (it has no personal data):\n' "$R$B" "$NO" "$fail" "$((pass + fail))" "$X"
    echo "yare-doctor $VERSION, bash $BASH_VERSION, $(macos_info), $fail failed"
    return 1
  fi
}

setup_ui
case $MODE in watch) watch_mode ;; selftest) selftest ;; live) live ;; why) why ;; checksum) checksum ;; *) snapshot ;; esac
