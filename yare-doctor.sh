#!/bin/bash
# yare-doctor: read-only check of what your coding agents are running on this Mac.
# Uses only `ps`, `sysctl` and `memory_pressure`. No network, no files written, nothing killed or changed.
# Early prototype helper from the Yare project. It reports; it does not claim a speed-up.
# Works with the bash that ships with macOS (3.2).
VERSION="0.2.0"
set -u

usage() {
  cat <<'EOF'
yare-doctor: what are your coding agents running on this Mac? (read-only)

  bash yare-doctor.sh                 one snapshot now (run it while your agents are working)
  bash yare-doctor.sh --watch [SECS]  sample every 5 s for SECS seconds (default 60) and report how often an agent's
                                      build ran at the same time as one of yours
  bash yare-doctor.sh --share         add one line with counts only (no paths, user names or commands) to paste in a reply
  bash yare-doctor.sh --json          machine-readable counts instead of the report
  bash yare-doctor.sh --version

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

# One pass over the process list. Prints tab-separated lines:
#   AGENT name count cpu% memMB          one line per coding agent found
#   BUILD agent|own count cpu%           builds and tests, split by whether an agent started them (it is an ancestor)
#   LEFT pid cpu% memMB elapsed command  helper processes that look left over from ended sessions
scan() {
  ps -axo pid=,ppid=,pcpu=,rss=,etime=,command= 2>/dev/null | awk '
  function etsecs(t,   d, x, p, n) {
    d = 0
    if (index(t, "-")) { split(t, x, "-"); d = x[1]; t = x[2] }
    n = split(t, p, ":")
    if (n == 3) return d*86400 + p[1]*3600 + p[2]*60 + p[3]
    if (n == 2) return d*86400 + p[1]*60 + p[2]
    return d*86400 + p[1]
  }
  function base(s,   n, a) { n = split(s, a, "/"); return a[n] }
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
  {
    cmd = ""
    for (i = 6; i <= NF; i++) cmd = cmd (i > 6 ? " " : "") $i
    low = tolower(cmd)
    if (low ~ /yare-doctor/ || low ~ /(^|\/)ps / || low ~ /--type=|helper/) next
    pid = $1; P[pid] = $2; C[pid] = $3; R[pid] = $4; E[pid] = $5; CMD[pid] = cmd; LOW[pid] = low
    n[pid] = 1
  }
  END {
    for (pid in n) {
      a = agentname(LOW[pid])
      if (a != "") { AG[pid] = a; ac[a]++; acpu[a] += C[pid]; amem[a] += R[pid] / 1024 }
    }
    for (a in ac) printf "AGENT\t%s\t%d\t%.1f\t%d\n", a, ac[a], acpu[a], amem[a]
    for (pid in n) {
      if (!isbuild(LOW[pid])) continue
      q = P[pid]; owner = "own"
      for (s = 0; s < 40 && q > 1; s++) { if (q in AG) { owner = "agent"; break } q = P[q] }
      bc[owner]++; bcpu[owner] += C[pid]
    }
    printf "BUILD\tagent\t%d\t%.1f\n", bc["agent"], bcpu["agent"]
    printf "BUILD\town\t%d\t%.1f\n", bc["own"], bcpu["own"]
    for (pid in n) {
      low = LOW[pid]
      if (P[pid] == 1 && low ~ /(mcp|claude|codex|opencode)/ && low ~ /(node|python|bun|deno|uvx|npx|mcp)/ && low !~ /^\/(system|usr|library|applications)\//) {
        if (etsecs(E[pid]) > 1800) printf "LEFT\t%s\t%s\t%d\t%s\t%s\n", pid, C[pid], R[pid] / 1024, E[pid], substr(CMD[pid], 1, 70)
      }
    }
  }'
}

load1() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }
swap_used() { sysctl -n vm.swapusage 2>/dev/null | sed -E 's/.*used = ([0-9.]+[MG]).*/\1/'; }
mem_free_pct() { memory_pressure 2>/dev/null | awk '/free percentage/ {gsub("%", "", $NF); print $NF; exit}'; }

# Sums from a scan result
total() { echo "$SCAN" | awk -F'\t' -v k="$1" -v w="$2" -v col="$3" '$1 == k && (w == "" || $2 == w) { s += $col } END { print s + 0 }'; }
agent_list() { echo "$SCAN" | awk -F'\t' '$1 == "AGENT" { printf "%s%s %d", (n++ ? ", " : ""), $2, $3 } END { if (!n) printf "none" }'; }

LINK="https://meetyare.vercel.app/?utm_source=doctor&utm_medium=tool&utm_campaign=output"

share_line() { # $1 = extra text
  echo "Yare doctor v$VERSION: $CPUS cores, ${MEM_GB} GB. Agents: $(agent_list). Builds: $B_AGENT started by agents, $B_OWN not. Load ${LOAD:-?}, swap ${SWAP:-?}, ${LEFT_N} possible leftovers.${1:-}"
}

snapshot() {
  SCAN=$(scan)
  LOAD=$(load1); SWAP=$(swap_used); FREE=$(mem_free_pct)
  A_N=$(total AGENT "" 3); A_CPU=$(total AGENT "" 4); A_MEM=$(total AGENT "" 5)
  B_AGENT=$(total BUILD agent 3); B_AGENT_CPU=$(total BUILD agent 4)
  B_OWN=$(total BUILD own 3); B_OWN_CPU=$(total BUILD own 4)
  LEFT_N=$(echo "$SCAN" | awk -F'\t' '$1 == "LEFT" { n++ } END { print n + 0 }')

  if (( JSON )); then
    printf '{"version":"%s","cores":%s,"memory_gb":%s,"load_1m":%s,"swap_used":"%s","agents":%s,"agent_builds":%s,"other_builds":%s,"possible_leftovers":%s}\n' \
      "$VERSION" "$CPUS" "$MEM_GB" "${LOAD:-null}" "${SWAP:-?}" "$A_N" "$B_AGENT" "$B_OWN" "$LEFT_N"
    return
  fi

  echo "Yare doctor v$VERSION (read-only snapshot, nothing was changed)"
  echo "Mac: $CPUS cores, ${MEM_GB} GB memory. Load average (1 min): ${LOAD:-?}. Swap used: ${SWAP:-?}.${FREE:+ Memory free: ${FREE}%.}"
  echo
  echo "Coding agents running: $A_N  (about ${A_CPU}% CPU, $((${A_MEM%.*} + 0)) MB memory in total)"
  echo "$SCAN" | awk -F'\t' '$1 == "AGENT" { printf "   %-14s %3d process(es)  %6.1f%% CPU  %6d MB\n", $2, $3, $4, $5 }'
  echo
  echo "Builds and tests running: $((B_AGENT + B_OWN))"
  echo "   started by an agent:                  $B_AGENT  (about ${B_AGENT_CPU}% CPU)"
  echo "   not under any agent (likely yours):   $B_OWN  (about ${B_OWN_CPU}% CPU)"
  if (( B_AGENT > 0 && B_OWN > 0 )); then
    echo "   -> An agent's build and a build that is not an agent's are running at the same time right now."
  fi
  echo
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
  echo "How to read this: run it while an agent works and again when they are idle."
  echo "Try --watch to see how often an agent's build overlaps yours over a minute."
  echo "This is a rough snapshot, not a benchmark, and the leftover check is a heuristic that can be wrong."
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
  local peak_agents=0 peak_ab=0 peak_ob=0 peak_load=0 overlap=0 agent_build_samples=0 own_build_samples=0
  local swap_start; swap_start=$(swap_used)
  if (( ! JSON )); then
    echo "Yare doctor v$VERSION, watching for ${WATCH_SECS}s (a sample every ${INTERVAL}s, read-only). Use your Mac and your agents as you normally do."
    echo
    printf '%-9s %7s %14s %13s %6s\n' "time" "agents" "agent builds" "your builds" "load"
  fi
  for (( i = 1; i <= samples; i++ )); do
    SCAN=$(scan)
    local a ab ob l
    a=$(total AGENT "" 3); ab=$(total BUILD agent 3); ob=$(total BUILD own 3); l=$(load1)
    (( JSON )) || printf '%-9s %7s %14s %13s %6s\n' "$(date +%H:%M:%S)" "$a" "$ab" "$ob" "${l:-?}"
    (( a > peak_agents )) && peak_agents=$a
    (( ab > peak_ab )) && peak_ab=$ab
    (( ob > peak_ob )) && peak_ob=$ob
    if [ -n "${l:-}" ] && (( $(echo "${l:-0} > $peak_load" | bc 2>/dev/null || echo 0) )); then peak_load=$l; fi
    (( ab > 0 )) && agent_build_samples=$((agent_build_samples + 1))
    (( ob > 0 )) && own_build_samples=$((own_build_samples + 1))
    (( ab > 0 && ob > 0 )) && overlap=$((overlap + 1))
    (( i < samples )) && sleep "$INTERVAL"
  done
  local swap_end; swap_end=$(swap_used)
  local ov_s=$(( overlap * INTERVAL )) ab_s=$(( agent_build_samples * INTERVAL )) ob_s=$(( own_build_samples * INTERVAL ))
  LOAD=$peak_load; SWAP=$swap_end; B_AGENT=$peak_ab; B_OWN=$peak_ob; LEFT_N=$(echo "$SCAN" | awk -F'\t' '$1 == "LEFT" { n++ } END { print n + 0 }')
  if (( JSON )); then
    printf '{"version":"%s","watch_seconds":%s,"peak_agents":%s,"peak_agent_builds":%s,"peak_other_builds":%s,"seconds_agent_builds_overlapped_other_builds":%s,"seconds_with_agent_builds":%s,"seconds_with_other_builds":%s,"peak_load_1m":%s,"swap_used_start":"%s","swap_used_end":"%s"}\n' \
      "$VERSION" "$WATCH_SECS" "$peak_agents" "$peak_ab" "$peak_ob" "$ov_s" "$ab_s" "$ob_s" "${peak_load:-0}" "${swap_start:-?}" "${swap_end:-?}"
    return
  fi
  echo
  echo "Over ${WATCH_SECS}s, at most at once: $peak_agents agents, $peak_ab agent builds, $peak_ob builds not under an agent. Peak load $peak_load. Swap ${swap_start:-?} -> ${swap_end:-?}."
  echo "An agent's build was running for ~${ab_s}s and a build of yours for ~${ob_s}s; they overlapped for ~${ov_s}s."
  if (( ov_s == 0 )); then
    echo "No overlap was seen in this window. That is a real result too: try again while an agent is building."
  fi
  echo "Rough sampling, not a benchmark: it shows how often they collided, not how much it slowed you."
  if (( SHARE )); then
    echo
    echo "Paste-able summary (counts only, no paths, user names or commands):"
    share_line " Over ${WATCH_SECS}s agent builds overlapped non-agent builds for ~${ov_s}s."
  fi
  echo
  echo "We would like to hear what it found. Yare is an early prototype Mac tool, not released yet. Updates: $LINK"
}

if [ "$MODE" = watch ]; then watch_mode; else snapshot; fi
