#!/bin/bash
# yare-doctor: read-only check of what your coding agents are running on this Mac.
# Uses only `ps`, `sysctl`, `memory_pressure`, `pmset`, `df`, `sw_vers`, `vm_stat`, `ioreg`, `tmutil` (status only) and `lsof` (listing, never connecting). No network, no files
# written, nothing killed or changed. Early prototype helper from the Yare project. It reports; it does not claim a speed-up.
# Works with the bash that ships with macOS (3.2).
#
# What it does that Activity Monitor does not: it follows the parent chain of every process, so it can say which agent
# session started what, how much of the Mac each session is holding, who is using the CPU, and what was left behind.
VERSION="0.1.0"; RELEASED="2026-11-08"
set -u
# cron and launchd start scripts with almost no environment: make sure HOME and the system tool folders exist
if [ -z "${HOME:-}" ]; then HOME=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{ print $2 }'); HOME=${HOME:-/var/root}; export HOME; fi
PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin:/usr/bin:/bin"; export PATH

usage() {
  local b="" d="" x=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then b=$'\033[1m'; d=$'\033[2m'; x=$'\033[0m'; fi
  cat <<EOF
${b}yare-doctor $VERSION${x}  ${d}what are your coding agents doing to this Mac? Read-only.${x}

${b}yare-doctor${x}            the tabbed screen (click or use the arrow keys): overview, sessions, processes, activity, findings, tree, agents
${b}yare-doctor plain${x}      the same picture as one plain report (this is what you get when it is piped)
${b}yare-doctor watch${x} [S]  sample for S seconds (default 60): did an agent's build overlap yours?
${b}yare-doctor live${x}       the same, refreshing (q quits)
${b}yare-doctor tree${x}       every process each session started, as a tree
${b}yare-doctor why${x} PID    who started this process, and which agent session it belongs to
${b}yare-doctor cleanup${x}    what could be closed, with the kill commands (printed, never run)
${b}yare-doctor share${x}      add a line of counts (no paths or names) to paste in a reply;  add ${b}redact${x} to hide folder names
${b}yare-doctor json${x}       the same data as JSON         ${b}yare-doctor help all${x}  every option (installed, html, check, snippet ...)

${d}It never changes anything: no network, no files written, nothing stopped. Read it first.${x}
EOF
}

usage_all() {
  local b="" d="" x=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then b=$'\033[1m'; d=$'\033[2m'; x=$'\033[0m'; fi
  cat <<EOF
${b}yare-doctor $VERSION${x}  ${d}what are your coding agents doing to this Mac? Read-only.${x}

${b}USAGE${x}   bash yare-doctor.sh [option]

${b}LOOK${x}
  ${b}(no option)${x}      one snapshot now. Run it while your agents are working.
  ${b}--watch [SECS]${x}   sample every 5 s (default 60): how often an agent's build ran at the same time as one
                    of yours, and how long agents squeezed a busy Mac.
  ${b}--live${x}           the dashboard, refreshed every 3 seconds (q quits, space pauses).
  ${b}--sessions${x}       just the sessions table, no other sections.   ${b}--installed${x}  which coding agents are installed on this Mac (nothing is run).
  ${b}--tree [NAME]${x}    every process each session started, as a tree (NAME like claude#2 shows one session).
  ${b}--why PID${x}        who started this process? Its chain up to the agent session, and whether it is an agent itself.
  ${b}--cleanup${x}        what could be closed, with the exact kill commands. It only prints them; it never runs them.

${b}SUMMARIES${x}
  ${b}--card${x}           a small boxed summary with a health score, made for screenshots.
  ${b}--awards${x}         superlatives for your sessions (the heavyweight, the marathoner, the sleeper ...).
  ${b}--vibe${x}           how the Mac feels, in one line.   ${b}--zoo${x}  every session as the animal it behaves like.
  ${b}--slow${x}           why the Mac may feel slow right now, and how much of it the agents are to blame for.
  ${b}--compare A B${x}    what changed between two --json runs (before and after you closed something).
  ${b}--oneline${x}        one short status line, for a tmux or shell prompt status bar (fast).

${b}AUTOMATION${x}
  ${b}--check${x}          quiet; exit code 0 = nothing to do, 1 = worth a look, 2 = act on it. For scripts and cron.
  ${b}--notify${x}         with --check: also show a macOS notification when there is something to look at (the one thing it does besides printing).
  ${b}--limit-mem MB${x}   with --check (exit code 2) or --oneline (red mark): when agent sessions hold more than this much memory.
  ${b}--limit-cpu PCT${x}  ... when agents and their apps use more than PCT of one core.   ${b}--limit-sessions N${x}  ... more than N sessions.
  ${b}--prom${x}           Prometheus text format, for node_exporter's textfile collector.
  ${b}--json${x}           machine-readable output instead of the report.
  ${b}--completions SH${x} shell completions: bash or zsh (eval "\$(bash yare-doctor.sh --completions bash)").

${b}SHARE${x}
  ${b}--share${x}          add one line of counts (no paths, user names or commands) to paste in a reply.
  ${b}--redact${x}         hide folder names, branch names, helper names and leftover commands so the whole report can be pasted.
  ${b}--html${x}           the report as one self-contained web page (yare-doctor.sh --html > report.html), light and dark.
  ${b}--snippet${x} KIND   config to paste so the doctor runs on its own: launchd, cron, tmux, zsh or statusline. It prints; it installs nothing.
  ${b}--md${x}             plain text inside a code fence, ready for an issue, chat or post.   ${b}--ascii${x}  no special characters.
  ${b}--light${x}          darker colours for a light terminal background (or set YARE_DOCTOR_THEME=light).

${b}TRUST${x}
  ${b}--capture${x}        the process list with arguments trimmed, for a bug report. ${b}--from FILE${x} replays it on any machine.
  ${b}--rules${x}          every rule and threshold the tool uses: what counts as an agent, what makes a finding.
  ${b}--selftest${x}       does every part work on this Mac? Detection fixtures and live checks, PASS or FAIL for each.
  ${b}--checksum${x}       this file's sha256, to compare with the one in the GitHub release notes.
  ${b}--no-color${x}       plain text (also automatic when piped, or when NO_COLOR is set).  ${b}--version${x}

${d}It never changes anything: no network, no files written, nothing stopped. Read it first.${x}
EOF
}

MODE=snapshot; PLAIN=0; FORCE_TABS=0; HTML=0; SNIP=; NOTIFY=0; WATCH_SECS=60; SHARE=0; JSON=0; INTERVAL=5; REDACT=0; WHY_PID=; COLOR=auto; TREE_LABEL=; COMPL_SHELL=; WANT_TREE=0; MD=0; ASCII=0; THEME=${YARE_DOCTOR_THEME:-dark}; FROM_FILE=; FIXTURE=0; CMP_A=; CMP_B=; LIMIT_MEM=0; LIMIT_CPU=0; LIMIT_SESS=0
while [ $# -gt 0 ]; do
  # plain words work like the options: yare-doctor watch 60, tree, why 1234, share redact, json ...
  case $1 in
    help) if [ "${2:-}" = all ]; then usage_all; else usage; fi; exit 0 ;;
    ui) set -- --tabs "${@:2}" ;;
    watch|live|tree|why|cleanup|share|redact|json|sessions|installed|check|card|awards|zoo|vibe|slow|compare|rules|selftest|version|license|capture|html|snippet|completions|prom|oneline|checksum|notify|plain|tabs) set -- "--$1" "${@:2}" ;;
  esac
  case $1 in
    --help-all|--all) usage_all; exit 0 ;;
    --plain) PLAIN=1 ;;
    --tabs) FORCE_TABS=1 ;;
    --watch) MODE=watch; if [[ ${2:-} =~ ^[0-9]+$ ]]; then WATCH_SECS=$2; shift; fi ;;
    --share) SHARE=1 ;;
    --json) JSON=1 ;;
    --selftest) MODE=selftest ;;
    --live) MODE=live ;;
    --oneline) MODE=oneline ;;
    --check) MODE=check ;;
    --card) MODE=card ;;
    --installed) MODE=installed ;;
    --notify) NOTIFY=1 ;;
    --html) HTML=1; COLOR=0; ASCII=0 ;;
    --snippet) MODE=snippet; SNIP=${2:-}; if [ $# -ge 2 ]; then shift; fi ;;
    --sessions) MODE=sessions ;;
    --zoo) MODE=zoo ;;
    --slow) MODE=slow ;;
    --compare) MODE=compare; CMP_A=${2:-}; CMP_B=${3:-}; if [ ! -r "$CMP_A" ] || [ ! -r "$CMP_B" ]; then echo "--compare needs two files made by --json: --compare BEFORE.json AFTER.json" >&2; exit 2; fi; shift 2 ;;
    --capture) MODE=capture ;;
    --from) FROM_FILE=${2:-}; if [ -z "$FROM_FILE" ] || [ ! -r "$FROM_FILE" ]; then echo "--from needs a file made by --capture" >&2; exit 2; fi; FIXTURE=1; shift ;;
    --md|--markdown) MD=1; COLOR=0 ;;
    --ascii) ASCII=1 ;;
    --light) THEME=light ;;
    --awards) MODE=awards ;;
    --vibe) MODE=vibe ;;
    --cleanup) MODE=cleanup ;;
    --rules) MODE=rules ;;
    --prom) MODE=prom ;;
    --tree) MODE=tree; if [[ ${2:-} =~ ^[a-z][a-z0-9-]*#[0-9]+$ ]]; then TREE_LABEL=$2; shift; fi ;;
    --completions) MODE=completions; COMPL_SHELL=${2:-}; if [ $# -ge 2 ]; then shift; fi ;;
    --limit-mem) LIMIT_MEM=${2:-0}; shift ;;
    --limit-cpu) LIMIT_CPU=${2:-0}; shift ;;
    --limit-sessions) LIMIT_SESS=${2:-0}; shift ;;
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
# plain `yare-doctor` in a terminal opens the tabbed screen; piped, with another view option, or with `plain`, it prints the report
if [ "$MODE" = snapshot ] && (( ! JSON && ! MD && ! HTML && ! SHARE )) && [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then
  if (( FORCE_TABS )); then MODE="tabs"
  elif (( ! PLAIN )) && [ -z "$FROM_FILE" ] && [ -z "${YARE_DOCTOR_PLAIN:-}" ]; then MODE="tabs"; fi
fi
if (( WATCH_SECS < 10 )); then WATCH_SECS=10; fi
if (( WATCH_SECS > 3600 )); then WATCH_SECS=3600; fi

CPUS=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
MEM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
CORES=$CPUS; [[ $CORES =~ ^[0-9]+$ ]] || CORES=1
TAB=$'\t'

# One pass over the process list. Every process is placed in the tree of the agent that started it (its topmost agent
# ancestor), so one agent session = the agent plus everything below it. Prints tab-separated lines:
#   TOT allcpu allmemMB agentcpu agentmemMB nprocs unionCpu         whole machine vs. everything inside agent sessions
#   AGENT name count cpu% memMB                            agent processes by name
#   SESS label rootpid age procs cpu% memMB cpuminutes idlecount idleMB builds forgotten stopped nestedagents host lastSpawnSecs spawnsLastMinute lastSpawnText   one line per agent session
#   RUN pid owner cpu% age name        a process inside a session at 70%+ CPU for 10+ minutes (possible runaway)
#   STUCK pid owner state name         suspended (stopped) or zombie process inside a session
#   MEM pid owner memMB name           processes holding 300 MB or more, with the owner
#   HOSTAPP name pid cpu% memMB procs sessions sessionCpu%   the app (and all its windows and helpers) that sessions run in
#   BLIST pid owner cpu% ageSecs age name   every build or test process, with the agent session that started it (- = yours)
#   GRP name count memMB cpu% inSessions   a program running 2+ times and 200+ MB in total (all processes, grouped by name)
#   DETACH pid cpu% name starter       a busy process with no agent or app above it (its starter already exited)
#   HUNG pid owner age name            a compiler or linker running 15+ minutes at almost no CPU
#   TOP pid owner cpu% memMB name                          processes using CPU, with the agent session that owns them
#   BUILD agent|own count cpu%                             builds and tests, by whether an agent started them
#   DUP signature count memMB sessions                     the same helper started 3+ times inside agent sessions
#   LEFT pid cpu% memMB elapsed command                    helpers with no parent that look left over from ended sessions
#   MAP pid owner                                          processes owned by a session or left over (to match ports)
#   WAIT pid owner age name                                a process in a session that is probably waiting for a person to answer
#   MCPS label count memMB                                 MCP servers a session started
#   NOW label pid cpu% age name                            the busiest process a session is running right now
#   UNK name pid age                                       a process that looks like a coding agent we do not recognise
#   SVC agent pid age memMB                                an agent running as a background service (hermes gateway, a daemon): listed, not a session
real_procs() { ps -axww -o pid=,ppid=,stat=,pcpu=,rss=,etime=,time=,command= 2>/dev/null; }
procs() { if [ -n "$FROM_FILE" ]; then cat "$FROM_FILE"; else real_procs; fi; }
SAMPLE_GAP=0.7; INSTANT=1
if [ -n "$FROM_FILE" ]; then INSTANT=0; fi   # a saved list has no second sample: use the CPU figures in it
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s; }
# CPU is measured, not read from ps: ps %cpu on macOS is an average that lags (a process that just got busy still shows
# a few percent). Two snapshots of every process's cumulative CPU time, SAMPLE_GAP seconds apart, give the real current load.
first_snapshot() { ps -axo pid=,time= 2>/dev/null; }
scan() {
  local first="" t0="" t1="" dt=0 second
  if (( INSTANT )); then first=$(first_snapshot); t0=$(now); sleep "$SAMPLE_GAP"; fi
  t1=$(now); second=$(procs)
  if (( INSTANT )); then dt=$(awk -v a="$t0" -v b="$t1" -v g="$SAMPLE_GAP" 'BEGIN { d = b - a; if (d < 0.3) d = g; printf "%.3f", d }'); fi
  { if (( INSTANT )); then printf '%s\n' "$first" | awk '{ print "T0 " $1 " " $2 }'; fi; printf '%s\n' "$second"; } | awk -v EXTRA="$(printf ',%s,' "${YARE_DOCTOR_AGENTS:-}" | tr 'A-Z ' 'a-z,' | tr -cd 'a-z0-9._,-' | tr -s ',')" -v dt="$dt" -v SELF=$$ -v TREE="${WANT_TREE:-0}" '
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
  function ago(v) { if (v < 0) return "-"; if (v < 5) return "now"; if (v < 60) return sprintf("%ds ago", v); if (v < 3600) return sprintf("%dm ago", v / 60); return sprintf("%dh ago", v / 3600) }
  function human(s,   d, h, m) {
    d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60)
    if (d > 0) return d "d " h "h"
    if (h > 0) return h "h " m "m"
    return m "m"
  }
  # ---- which processes are coding agents ----
  # An agent is recognised by its program name, or, for tools that run on an interpreter (node, python, bun, uv ...), by the
  # script it runs. Desktop apps (their Contents/MacOS binary) are hosts, not agents. Subcommands that are not a working
  # session (--version, login, mcp, update ...) are ignored. See --rules for the full list.
  function stripext(s) { sub(/\.(js|mjs|cjs|ts|py|rb|jar|exe)$/, "", s); return s }
  function isinterp(b) { return b ~ /^(node|nodejs|bun|deno|python|python2|python3|python[0-9]+\.[0-9]+|ruby|uv|uvx|npx|bunx|pnpm|pnpx|yarn|tsx|ts-node|java|perl)$/ }
  function canon(b) {
    if (EXTRA != "" && index(EXTRA, "," b ",")) return b
    if (b == "claude" || b == "claude-code") return "claude"
    if (b == "codex" || b == "codex-cli") return "codex"
    if (b == "gemini" || b == "gemini-cli") return "gemini"
    if (b == "qwen" || b == "qwen-code") return "qwen"
    if (b == "kiro" || b == "kiro-cli") return "kiro-cli"
    if (b == "kilo" || b == "kilocode") return "kilo"
    if (b == "opencode" || b == "aider" || b == "cursor-agent" || b == "amp" || b == "goose" || b == "crush" || b == "droid" || b == "copilot" || b == "hermes" || b == "auggie" || b == "cline" || b == "plandex" || b == "openhands" || b == "kimi" || b == "devin" || b == "grok" || b == "junie" || b == "jules") return b
    return ""
  }
  function pkgagent(low) {
    if (low ~ /@anthropic-ai\/claude-(code|agent-sdk)|\/claude-code\//) return "claude"
    if (low ~ /@openai\/codex|\/codex\/bin\//) return "codex"
    if (low ~ /@google\/gemini-cli/) return "gemini"
    if (low ~ /@github\/copilot/) return "copilot"
    if (low ~ /@sourcegraph\/amp/) return "amp"
    if (low ~ /@qwen-code\/qwen-code/) return "qwen"
    if (low ~ /@augmentcode\/auggie/) return "auggie"
    if (low ~ /opencode-ai/) return "opencode"
    if (low ~ /@charmland\/crush/) return "crush"
    if (low ~ /@continuedev\/cli|node_modules\/\.bin\/cn( |$)|\/\.continue\//) return "continue"
    if (low ~ /@kilocode\/cli/) return "kilo"
    if (low ~ /\.hermes\/hermes-agent|hermes_cli/) return "hermes"
    return ""
  }
  # the executable of a command line: the first word, or the file inside an app bundle (bundle names can contain spaces)
  function exe0(low,   i, r, t) {
    i = index(low, ".app/contents/")
    if (i && substr(low, i + 14, 6) != "macos/") { r = substr(low, i + 14); split(r, t, " "); return t[1] }
    split(low, t, " "); return t[1]
  }
  # agents started by their full install path (argv[0] is a version folder or an install directory, not the word "claude")
  function exeagent(e) {
    if (e ~ /\/claude\/versions\/[0-9]/) return "claude"
    if (e ~ /\/cursor-agent\/versions\//) return "cursor-agent"
    if (e ~ /\/\.opencode\/bin\//) return "opencode"
    if (e ~ /\/\.hermes\/hermes-agent\//) return "hermes"
    return ""
  }
  function daemonargs(low) { return (low ~ / --managed-daemon( |$)| --service( |$)| app-server daemon | daemon pid-update-loop|--daemonize| --chrome-native-host( |$)|chrome-extension:\/\/|moz-extension:\/\//) }
  # An agent started as a background service (a gateway, a daemon, a cron runner) waits for messages or jobs: it is not a working
  # session. agentname() returns "" for it and leaves the agent name in SVCNAME so the report can list it as a service.
  function svcmark(a) { SVCNAME = a; return "" }
  function servicecmd(w) { return (w ~ /^(gateway|daemon|cron|supervisor|relay|hub-daemon)$/) }
  function nonsession(w) { return (w ~ /^(--version|-v|-version|version|--help|-h|help|login|logout|update|upgrade|doctor|config|completion|install|uninstall|setup-token|migrate-installer|auth|plugin|plugins|mcp)$/) }
  # The program an interpreter runs: the script after the interpreter own flags (node --import x script.js), the module after -m
  # (python -m aider), or the package after a runner flags and subcommands (npx -y pkg, uv tool run x, bun run x). Anything after
  # that is the program own arguments (node server.js --name claude is not a Claude session). Returns its word number, or 0.
  function interptarget(t, n, b,   i, w, runner, hops) {
    runner = (b ~ /^(npx|bunx|pnpx|uvx|uv|pnpm|yarn|bun|deno)$/)
    for (i = 2; i <= n && hops < 6; i++) {
      w = t[i]
      if (w == "-m" && !runner) return (i < n) ? i + 1 : 0
      if (w ~ /^(-e|--eval|-c|--print)$/ || (w == "-p" && !runner)) return 0
      if (substr(w, 1, 1) == "-") {
        if (index(w, "=") == 0 && w ~ /^(-r|--require|--import|--loader|--experimental-loader|--conditions|-C|-W|-X|--from|--with|--with-requirements|-p|--package|--python|--registry|--cwd|--prefix|-w|--workspace|--env-file)$/) i++
        continue
      }
      if (runner && w ~ /^(run|exec|x|dlx|tool)$/) { hops++; continue }
      return i
    }
    return 0
  }
  function agentname(low,   t, n, b, a, i, k, w, tok, rest, bp) {
    # Some agents run from a bundle of their own (an .app with the same name as the program) inside a versioned folder:
    #   .../Application Support/Claude/claude-code/2.1.317/<hash>/claude.app/Contents/MacOS/claude   (the Claude desktop app runs this)
    #   ~/.local/share/junie/versions/3110.7/Applications/junie.app/Contents/MacOS/junie
    # These are the agent itself, not a desktop app. (The paths can contain spaces, so the line is not split on spaces here.)
    i = index(low, ".app/contents/macos/")
    if (i && (low ~ /\/versions\// || low ~ /\/claude-code\/[0-9]/)) {
      rest = substr(low, i + 20); split(rest, t, " "); tok = t[1]
      n = split(substr(low, 1, i - 1), bp, "/")
      if (canon(tok) != "" && bp[n] == tok) {
        rest = substr(rest, length(tok) + 2); split(rest, t, " ")
        if (daemonargs(low)) return svcmark(canon(tok))
        if (nonsession(t[1])) return ""
        return canon(tok)
      }
    }
    if (index(low, ".app/contents/macos/")) return ""
    n = split(low, t, " "); b = base(exe0(low)); a = ""
    if (isinterp(b)) {
      k = interptarget(t, n, b)
      if (k == 0) {   # inline code (python -c) that loads the Hermes agent: its gateway and cron runners are services
        if (low ~ /\.hermes\/hermes-agent/) { if (low ~ / (gateway|cron)( |$)|--external-supervisor|--run-module hermes_cli\.stderr_timestamp/) return svcmark("hermes"); return "hermes" }
        return ""
      }
      tok = t[k]; sub(/@[^\/@]*$/, "", tok)
      if (t[k - 1] == "-m") sub(/\..*/, "", tok)
      a = canon(stripext(base(tok)))
      if (a == "") a = pkgagent(tok)
    } else { a = canon(stripext(b)); k = 1; if (a == "") a = exeagent(exe0(low)) }
    if (a == "") return ""
    if (daemonargs(low)) return svcmark(a)
    w = t[k + 1]
    if (nonsession(w)) return ""
    if (servicecmd(w)) return svcmark(a)
    if (a == "goose" && w !~ /^(session|run|web|acp)$/) return ""
    if (a == "hermes" && low !~ /hermes-agent|\.hermes\/|hermes_cli/) return ""
    return a
  }
  # the program a command line runs: the script for an interpreter (node .../tsc, python -m pytest), otherwise the file name
  function progname(low,   t, n, i, b) {
    n = split(low, t, " "); b = base(exe0(low))
    if (!isinterp(b)) return b
    for (i = 2; i <= n; i++) {
      if (t[i] == "-m" && (i + 1) <= n) return stripext(base(t[i + 1]))
      if (substr(t[i], 1, 1) != "-") return stripext(base(t[i]))
    }
    return b
  }
  function isbuild(low,   b, watch) {
    b = progname(low)
    watch = (low ~ / (dev|serve|start|--watch|--watchall|-w|--serve|--hot)( |$)/)
    if (b ~ /^(clang|clang\+\+|cc1|swiftc|swift-frontend|swift-build|rustc|xcodebuild|make|ninja|ld|gcc|g\+\+|cmake)$/) return 1
    if (b ~ /^(tsc|webpack|esbuild|vite|rollup|parcel|turbo|next)$/) { if (b == "next" || b == "vite") return (low ~ / build( |$)/) ? 1 : 0; return watch ? 0 : 1 }
    if (b == "cargo") return (low ~ / (build|test|check|clippy|bench|doc|install)( |$)/) ? 1 : 0
    if (b == "gradle" || b == "gradlew" || b == "mvn") return watch ? 0 : 1
    if (b ~ /^(xctest|swift-test|swiftpm-testing-helper|pytest|py\.test|jest|vitest|mocha|playwright|cypress)$/) return watch ? 0 : 1
    if (b == "go") return (low ~ / (build|test|vet|install)( |$)/) ? 1 : 0
    return 0
  }
  function short(c,   i, t, k, n, r) {
    i = index(c, ".app/Contents/MacOS/"); if (i) return appname(c)
    n = split(c, t, " "); r = base(t[1])
    for (k = 2; k <= n && k <= 3; k++) r = r " " ((t[k] ~ /\//) ? base(t[k]) : substr(t[k], 1, 26))
    return substr(r, 1, 58)
  }
  function appname(cmd,   i, s, t) {
    i = index(cmd, ".app/Contents/MacOS/")
    if (i) { s = substr(cmd, i + 20); sub(/ -.*/, "", s); return substr(s, 1, 44) }
    split(cmd, t, " "); return substr(base(t[1]), 1, 44)
  }
  # the program a process is: the bundle name for the main binary of an app, otherwise the file name
  function exelabel(cmd,   i, s, t) {
    i = index(cmd, ".app/Contents/MacOS/")
    if (i) { s = substr(cmd, 1, i - 1); sub(/.*\//, "", s); return s }
    split(cmd, t, " "); return base(t[1])
  }
  function hostcanon(nm,   l) {
    l = tolower(nm)
    if (l ~ /^iterm/) return "iTerm"
    if (l == "terminal") return "Terminal"
    if (l == "ghostty" || l == "warp" || l == "alacritty" || l == "kitty" || l == "wezterm" || l == "hyper" || l == "tabby" || l == "rio" || l == "zed" || l == "cursor" || l == "windsurf" || l == "xcode" || l == "conductor") return toupper(substr(nm, 1, 1)) substr(nm, 2)
    if (l ~ /^(visual studio code|vscodium|vs code)/ || l == "code" || l ~ /^code - /) return "VS Code"
    if (l ~ /^codex/) return "Codex"
    if (l ~ /^claude/) return "Claude"
    if (l ~ /^t3 code/) return "T3 Code"
    if (l ~ /^(intellij|idea|pycharm|webstorm|clion|goland|rider|phpstorm|rubymine|datagrip|android studio|studio|fleet|appcode|rustrover|aqua|dataspell|writerside)/) return "JetBrains"
    return nm
  }
  function hostof(pid,   q, s, e, l) {
    q = P[pid]
    for (s = 0; s < 40 && q != "" && q > 1; s++) {
      if (!(q in n)) break
      e = exelabel(CMD[q]); l = tolower(e); sub(/:$/, "", l)
      if (l ~ /^(tmux|screen|zellij)$/) return l
      if (l == "sshd" || l == "sshd-session") return "ssh"
      if (index(CMD[q], ".app/Contents/MacOS/") && l !~ /helper|renderer|gpu|plugin/) return hostcanon(e)
      q = P[q]
    }
    if (P[pid] == 1) return "background"
    return "-"
  }
  function sig(low,   t, b, k) {
    split(low, t, " "); b = base(t[1])
    if (b ~ /^(node|python|python3|bun|deno|npx|uvx|uv|ruby|java)$/) {
      for (k = 2; (k in t) && k < 8; k++) if (substr(t[k], 1, 1) != "-") return b " " substr(base(t[k]), 1, 30)
    }
    return b
  }
  $1 == "T0" { t0[$2] = cpusecs($3); next }
  {
    cmd = ""
    for (i = 8; i <= NF; i++) cmd = cmd (i > 8 ? " " : "") $i
    low = tolower(cmd)
    split(low, ft, " "); fb = base(ft[1])
    pid = $1; P[pid] = $2; ST[pid] = $3; PC[pid] = $4 + 0; R[pid] = $5;
    tsec = cpusecs($7)
    if (dt > 0) {
      if (pid in t0) cc = (tsec - t0[pid]) / dt * 100
      else { a0 = etsecs($6); el = (a0 > 0 && a0 < dt) ? a0 : dt; cc = tsec / el * 100 }
      if (cc < 0) cc = 0
    } else cc = $4 + 0
    C[pid] = cc; E[pid] = $6; T[pid] = $7; CMD[pid] = cmd; LOW[pid] = low
    n[pid] = 1
    if (low ~ /--type=(renderer|gpu-process|utility|zygote|crashpad-handler|broker|ppapi)/ || (index(cmd, ".app/Contents/MacOS/") && exelabel(cmd) ~ /[Hh]elper/)) HELP[pid] = 1
  }
  END {
    # this script and the tools it runs are not part of the picture: drop every process below our own shell
    for (pid in n) { q = pid; for (s = 0; s < 40 && q != "" && q > 1; s++) { if (q == SELF) { drop[pid] = 1; break } q = P[q] } }
    for (pid in drop) delete n[pid]
    for (pid in n) {
      if (pid in HELP) continue
      SVCNAME = ""; a = agentname(LOW[pid])
      if (a != "") { AG[pid] = a; ac[a]++; acpu[a] += C[pid]; amem[a] += R[pid] / 1024 }
      else if (SVCNAME != "") SV[pid] = SVCNAME
    }
    for (pid in SV) { q = pid; for (s = 0; s < 40 && (P[q] in SV); s++) q = P[q]; svmem[q] += R[pid] / 1024 }
    for (pid in SV) if (!(P[pid] in SV) && etsecs(E[pid]) >= 120) printf "SVC\t%s\t%s\t%s\t%d\n", SV[pid], pid, human(etsecs(E[pid])), svmem[pid]
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
    # oldest session first, so labels stay put when process ids wrap around or new sessions start
    for (i = 1; i <= nroots; i++) rage[roots[i]] = etsecs(E[roots[i]])
    for (i = 2; i <= nroots; i++) { v = roots[i]; j = i - 1; while (j > 0 && (rage[roots[j]] < rage[v] || (rage[roots[j]] == rage[v] && roots[j] > v))) { roots[j + 1] = roots[j]; j-- } roots[j + 1] = v }
    for (i = 1; i <= nroots; i++) { r = roots[i]; cnt[AG[r]]++; LABEL[r] = AG[r] "#" cnt[AG[r]] }

    for (pid in n) {
      r = ROOT[pid]
      if (r == "" || pid == r || (pid in HELP) || C[pid] < 3) continue
      split(LOW[pid], nt, " "); if (base(nt[1]) ~ /^(sh|bash|zsh|fish|dash|-bash|-zsh|sleep|env|caffeinate|login)$/) continue
      if (!(r in nowc) || C[pid] > nowc[r]) { nowc[r] = C[pid]; nowp[r] = pid }
    }
    for (r in nowp) printf "NOW\t%s\t%s\t%.1f\t%s\t%s\n", LABEL[r], nowp[r], nowc[r], human(etsecs(E[nowp[r]])), appname(CMD[nowp[r]])
    # waiting for a person: a password, keychain or login prompt an agent cannot answer
    for (pid in n) {
      r = ROOT[pid]
      if (r == "" || pid == r || (pid in HELP) || C[pid] >= 1) continue
      pw = progname(LOW[pid]); wage = etsecs(E[pid])
      if ((pw ~ /^(sudo|security|pinentry|pinentry-mac|git-credential-osxkeychain|git-credential-manager|ssh-askpass|passwd|su)$/ && wage > 60) || (LOW[pid] ~ /(gh auth login|npm login|npm adduser|aws sso login|gcloud auth login|vercel login|firebase login|op signin)/ && wage > 60) || (pw == "osascript" && wage > 180))
        printf "WAIT\t%s\t%s\t%s\t%s\n", pid, LABEL[r], human(wage), appname(CMD[pid])
    }
    # MCP servers: tool servers an agent starts for itself (one chain, such as npm exec -> node, counts once)
    for (pid in n) {
      r = ROOT[pid]; low = LOW[pid]
      if (r == "" || pid == r || (pid in HELP)) continue
      if (low ~ /(^|[ \/@._-])mcp([ \/@._-]|$)|modelcontextprotocol|playwright-mcp/ && agentname(low) == "" && progname(low) !~ /^-?(sh|bash|zsh|fish|dash|env|npm|npx)$/) MCPP[pid] = 1
    }
    # agents we do not recognise: a process outside every session that starts MCP servers (found by walking up from the server past
    # shells and npm), or that runs with an agent-style flag. They are listed so they can be added (YARE_DOCTOR_AGENTS) or reported.
    for (pid in n) {
      if (ROOT[pid] != "" || (pid in HELP) || (pid in SV)) continue
      low = LOW[pid]
      if (low ~ /--output-format[ =]stream-json|--dangerously-skip-permissions|--mcp-config|--allowedtools/) { SVCNAME = ""; if (agentname(low) == "" && SVCNAME == "") UNK[pid] = 1; continue }
      if (!(low ~ /(^|[ \/@._-])mcp([ \/@._-]|$)|modelcontextprotocol|playwright-mcp/)) continue
      q = P[pid]
      for (s = 0; s < 12 && (q in n); s++) {
        lq = LOW[q]; b = progname(lq)
        if (index(CMD[q], ".app/Contents/MacOS/") || b ~ /^(login|sshd|sshd-session|tmux|screen|su|sudo|launchd)$/) { q = ""; break }
        if (b ~ /^-?(sh|bash|zsh|fish|dash|env|npm|npx)$/ || lq ~ /(^|[ \/@._-])mcp([ \/@._-]|$)|modelcontextprotocol|playwright-mcp/) { q = P[q]; continue }
        break
      }
      if (q != "" && (q in n) && ROOT[q] == "" && !(q in HELP) && !(q in SV)) { SVCNAME = ""; if (agentname(LOW[q]) == "" && SVCNAME == "") UNK[q] = 1 }
    }
    for (pid in UNK) if (!(P[pid] in UNK)) printf "UNK\t%s\t%s\t%s\n", progname(LOW[pid]), pid, human(etsecs(E[pid]))
    for (pid in MCPP) { r = ROOT[pid]; mcpm[r] += R[pid] / 1024; if (!(P[pid] in MCPP)) mcpn[r]++ }
    for (r in mcpn) printf "MCPS\t%s\t%d\t%d\n", LABEL[r], mcpn[r], mcpm[r]
    # the app each session runs in = the topmost ancestor below launchd; its whole tree counts as the host app of the session
    for (pid in n) { q = pid; for (s = 0; s < 40 && P[q] > 1 && (P[q] in n); s++) q = P[q]; TOPANC[pid] = q }
    for (i = 1; i <= nroots; i++) { r = roots[i]; if (TOPANC[r] != r && (index(CMD[TOPANC[r]], ".app/Contents/MacOS/") || hostof(r) !~ /^(-|background)$/)) { appset[TOPANC[r]] = 1; appsess[TOPANC[r]]++; appscpu[TOPANC[r]] += 0; appname_of[TOPANC[r]] = hostof(r) } }
    allcpu = 0; allmem = 0; agcpu = 0; agmem = 0; np = 0; ucpu = 0
    for (pid in n) {
      np++; allcpu += C[pid]; allmem += R[pid] / 1024
      if (ROOT[pid] != "" || (TOPANC[pid] in appset)) ucpu += C[pid]
      if (TOPANC[pid] in appset) { acpu[TOPANC[pid]] += C[pid]; amem[TOPANC[pid]] += R[pid] / 1024; anp[TOPANC[pid]]++ }
      if (ROOT[pid] != "" && pid != ROOT[pid] && !(pid in HELP)) { ag0 = etsecs(E[pid]); if (!(ROOT[pid] in yng) || ag0 < yng[ROOT[pid]]) yng[ROOT[pid]] = ag0; if (ag0 <= 60) rec[ROOT[pid]]++ }
      r = ROOT[pid]
      if (r == "") continue
      sp[r]++; scpu[r] += C[pid]; smem[r] += R[pid] / 1024; stime[r] += cpusecs(T[pid])
      agcpu += C[pid]; agmem += R[pid] / 1024
      age = etsecs(E[pid])
      if (pid != r && !(pid in HELP) && age > 1800 && C[pid] < 1 && cpusecs(T[pid]) / age < 0.005) { idn[r]++; idm[r] += R[pid] / 1024 }
      if (pid != r && !(pid in HELP) && substr(ST[pid], 1, 1) ~ /[TZ]/) { stp[r]++; stuck = stuck sprintf("STUCK\t%s\t%s\t%s\t%s\n", pid, LABEL[r], substr(ST[pid], 1, 1), appname(CMD[pid])) }
      if (pid != r && !(pid in HELP) && C[pid] >= 70 && PC[pid] >= 20 && age > 600) runaway = runaway sprintf("RUN\t%s\t%s\t%.1f\t%s\t%s\n", pid, LABEL[r], C[pid], human(age), appname(CMD[pid]))
    }
    printf "%s%s", stuck, runaway
    printf "TOT\t%.1f\t%d\t%.1f\t%d\t%d\t%.1f\n", allcpu, allmem, agcpu, agmem, np, ucpu
    for (i = 1; i <= nroots; i++) { r = roots[i]; if (TOPANC[r] in appset) scs[TOPANC[r]] += scpu[r] }
    for (a in appset) printf "HOSTAPP\t%s\t%s\t%.1f\t%d\t%d\t%d\t%.1f\n", ((appname_of[a] != "-") ? appname_of[a] : appname(CMD[a])), a, acpu[a], amem[a], anp[a], appsess[a], scs[a]
    for (i = 1; i <= nroots; i++) {
      r = roots[i]
      forgot = (etsecs(E[r]) > 43200 && scpu[r] < 0.5 && hostof(r) !~ /^(-|background)$/) ? 1 : 0
      printf "SESS\t%s\t%s\t%s\t%d\t%.1f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\n", LABEL[r], r, human(etsecs(E[r])), sp[r], scpu[r], smem[r], stime[r] / 60, idn[r] + 0, idm[r] + 0, sb[r] + 0, forgot, stp[r] + 0, nest[r] + 0, hostof(r), (r in yng ? yng[r] : -1), rec[r] + 0, ago(r in yng ? yng[r] : -1), etsecs(E[r])
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
      bage = etsecs(E[pid]); bown = (ROOT[pid] != "") ? LABEL[ROOT[pid]] : "-"; split(LOW[pid], bt, " ")
      printf "BLIST\t%s\t%s\t%.1f\t%d\t%s\t%s\n", pid, bown, C[pid], bage, human(bage), appname(CMD[pid])
      if (bage > 900 && C[pid] < 0.5 && base(bt[1]) ~ /^(clang|clang\+\+|cc1|swiftc|swift-frontend|rustc|tsc|ld|esbuild)$/) printf "HUNG\t%s\t%s\t%s\t%s\n", pid, bown, human(bage), appname(CMD[pid])
    }
    printf "BUILD\tagent\t%d\t%.1f\n", bc["agent"], bcpu["agent"]
    printf "BUILD\town\t%d\t%.1f\n", bc["own"], bcpu["own"]

    for (pid in n) {
      low = LOW[pid]
      if (pid in HELP) continue
      if (P[pid] == 1 && !(pid in AG) && low !~ /^\/(system|usr|library)\// && ((low ~ /(mcp|claude|codex|opencode|gemini|aider)/ && low ~ /(node|python|bun|deno|uvx|npx|mcp)/ && low !~ /\.app\/contents\/macos\//) || low ~ /(--remote-debugging|--headless|playwright|puppeteer|chromedriver|geckodriver|chrome-for-testing|tsserver|typescript-language-server|sourcekit-lsp|pyright|rust-analyzer|gopls|esbuild --service|next dev|next-server|storybook|webpack serve|vite)/)) {
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
      gk = appname(CMD[pid]); gc[gk]++; gm[gk] += R[pid] / 1024; gu[gk] += C[pid]; if (ROOT[pid] != "") ga[gk]++
    }
    # busy processes with no agent above them whose top-level starter is not an app or a system program: background work
    # that was started by something that has already exited (for example a dev server an agent left running)
    for (pid in n) if (ROOT[pid] == "" && C[pid] >= 25) {
      t = TOPANC[pid]
      if (LOW[t] !~ /\.app\/|^\/system\/|^\/usr\/(libexec|sbin)|^\/sbin|^\/library\//) printf "DETACH\t%s\t%.1f\t%s\t%s\n", pid, C[pid], appname(CMD[pid]), appname(CMD[t])
    }
    for (gk in gc) if (gc[gk] >= 2 && gm[gk] >= 200) printf "GRP\t%s\t%d\t%d\t%.1f\t%d\n", gk, gc[gk], gm[gk], gu[gk], ga[gk] + 0
    if (TREE + 0) for (pid in n) if (ROOT[pid] != "") printf "PROC\t%s\t%s\t%s\t%.1f\t%d\t%s\t%s\n", pid, P[pid], LABEL[ROOT[pid]], C[pid], R[pid] / 1024, human(etsecs(E[pid])), short(CMD[pid])
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
agent_list() { echo "$SCAN" | awk -F'\t' '$1 == "SESS" { split($2, a, "#"); if (!(a[1] in c)) o[++m] = a[1]; c[a[1]]++ } END { for (i = 1; i <= m; i++) printf "%s%s %d", (i > 1 ? ", " : ""), o[i], c[o[i]]; if (!m) printf "none" }'; }
pct() { awk -v a="$1" -v c="$CORES" 'BEGIN { v = a / c; if (v < 10) printf "%.1f", v; else printf "%.0f", v }'; } # points of ps %CPU -> % of the whole machine

# Listening TCP ports held by processes that belong to an agent session or look left over (lsof only lists, never connects)
ports() {
  [ "$FIXTURE" = 1 ] && return
  local map; map=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" { print $2 " " $3 }')
  [ -z "$map" ] && return
  awk 'NR == FNR { own[$1] = $2; next }
    $1 != "COMMAND" && ($2 in own) { name = $(NF - 1); sub(/.*:/, "", name); k = $2 ":" name
      if (!(k in seen)) { seen[k] = 1; printf "%s\t%s\t%s\n", $1, name, own[$2] } }' <(echo "$map") <(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null)
}

# Folder each session works in: the current directory of the agent process (lsof only lists it, nothing is opened)
folders() {
  [ "$FIXTURE" = 1 ] && return
  local pids; pids=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "%s%s", (n++ ? "," : ""), $3 }')
  [ -z "$pids" ] && return
  lsof -a -d cwd -Fpn -p "$pids" 2>/dev/null | awk '/^p/ { pid = substr($0, 2) } /^n/ { printf "%s\t%s\n", pid, substr($0, 2) }'
}

# Branch (or short commit) of a folder's git checkout, read straight from .git/HEAD; handles worktrees. Runs no git.
git_branch() {
  local d=$1 g h
  while [ -n "$d" ] && [ "$d" != / ]; do
    if [ -e "$d/.git" ]; then
      g="$d/.git"
      if [ -f "$g" ]; then g=$(sed -n 's/^gitdir: //p' "$g" 2>/dev/null | head -1); case $g in /*) ;; *) g="$d/$g" ;; esac; fi
      h=$(head -1 "$g/HEAD" 2>/dev/null)
      case $h in "ref: refs/heads/"*) echo "${h#ref: refs/heads/}" ;; "") ;; *) echo "${h:0:7}" ;; esac
      return
    fi
    d=${d%/*}
  done
}
branches() { # pid<TAB>branch for every session folder, from the FOLDERS list
  local pid path b
  while IFS=$'\t' read -r pid path; do
    [ -n "${pid:-}" ] || continue
    b=$(git_branch "$path"); [ -n "$b" ] && printf '%s\t%s\n' "$pid" "$b"
  done <<< "$FOLDERS"
}
# Version of each session's program, from the install path of its executable (.../versions/2.1.319, .../releases/0.166.0).
# Reads lsof -F output on stdin: p<pid> then the n<path> lines, the first of which is the program itself.
parse_versions() {
  awk '/^p/ { pid = substr($0, 2); got = 0; next } /^n/ { if (!got) { got = 1; path = substr($0, 2); if (match(path, /\/(versions|releases)\/[0-9][^\/]*/)) { v = substr(path, RSTART, RLENGTH); sub(/.*\//, "", v); printf "%s\t%s\n", pid, v } } }'
}
session_versions() {
  [ "$FIXTURE" = 1 ] && return
  local pids; pids=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "%s%s", (n++ ? "," : ""), $3 }')
  [ -z "$pids" ] && return
  lsof -a -d txt -Fpn -p "$pids" 2>/dev/null | parse_versions
}
# agents running more than one version at once: "claude 2.1.319 (claude#1), 2.1.300 (claude#2)"
versions_report() {
  awk -F'\t' 'FNR == NR { ver[$1] = $2; next } $1 == "SESS" && ($3 in ver) { split($2, a, "#"); k = a[1]; key = k SUBSEP ver[$3]; if (!(key in seen)) { seen[key] = 1; nv[k]++; list[k] = list[k] (list[k] != "" ? ", " : "") ver[$3] " (" $2 ")" } }
    END { for (k in nv) if (nv[k] > 1) printf "%s%s %s", (m++ ? "; " : ""), k, list[k] }' <(printf '%s\n' "$VERSIONS") <(echo "$SCAN")
}
# Bytes each process has moved over the network (nettop only reads counters; it sends nothing): pid<TAB>in<TAB>out
net_usage() {
  [ "$FIXTURE" = 1 ] && return
  nettop -P -L 1 -n -J bytes_in,bytes_out -x 2>/dev/null | awk -F, 'NR > 1 && NF >= 3 { n = split($1, a, "."); pid = a[n]; if (pid ~ /^[0-9]+$/) printf "%s\t%s\t%s\n", pid, $2, $3 }'
}
# The same, added up per session: label<TAB>in<TAB>out
net_by_session() {
  awk -F'\t' 'FNR == NR { if ($1 == "MAP") own[$2] = $3; next } ($1 in own) && own[$1] != "leftover" { i[own[$1]] += $2; o[own[$1]] += $3 } END { for (k in i) printf "%s\t%d\t%d\n", k, i[k], o[k] }' <(echo "$SCAN") <(echo "$NET")
}
git_running() { pgrep -x git >/dev/null 2>&1; }
# Lock files git leaves behind when it is killed mid-command. While one exists, every git command in that repository fails with
# "Unable to create index.lock". Reported only when no git process is running at all and the file is older than two minutes.
git_locks() { # path<TAB>session pid<TAB>age in seconds
  [ "$FIXTURE" = 1 ] && return
  # a live git command holds a lock for seconds, so 2 minutes old is stale; while git runs elsewhere (editors poll it constantly) wait 10
  local min=120; git_running && min=600
  local pid path d g f age now; now=$(date +%s)
  while IFS=$'\t' read -r pid path; do
    [ -n "${pid:-}" ] || continue
    d=$path; g=""
    while [ -n "$d" ] && [ "$d" != / ]; do if [ -e "$d/.git" ]; then g="$d/.git"; break; fi; d=${d%/*}; done
    [ -n "$g" ] || continue
    if [ -f "$g" ]; then g=$(sed -n 's/^gitdir: //p' "$g" 2>/dev/null | head -1); case $g in /*) ;; *) g="$d/$g" ;; esac; fi
    for f in index.lock HEAD.lock shallow.lock packed-refs.lock; do
      if [ -f "$g/$f" ]; then age=$(( now - $(stat -f %m "$g/$f" 2>/dev/null || echo "$now") )); if (( age > min )); then printf '%s\t%s\t%d\n' "$g/$f" "$pid" "$age"; fi; fi
    done
  done <<< "$FOLDERS"
}
# What is keeping the Mac from sleeping, and which agent session started it (pmset only lists)
awake() {
  [ "$FIXTURE" = 1 ] && return
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
  [ "$FIXTURE" = 1 ] && return
  local map pids; map=$(echo "$SCAN" | awk -F'\t' '$1 == "MAP" && $3 != "leftover" { print $2 " " $3 }')
  [ -z "$map" ] && return
  pids=$(echo "$map" | awk '{ printf "%s%s", (n++ ? "," : ""), $1 }')
  awk 'NR == FNR { own[$1] = $2; next } /^p/ { p = substr($0, 2) } /^f[0-9]/ { if (p in own) c[own[p]]++ } END { for (o in c) printf "%s\t%d\n", o, c[o] }' <(printf '%s\n' "$map") <(lsof -p "$pids" -Fpf 2>/dev/null)
}
gpu_info() { ioreg -r -d 1 -w0 -c IOAccelerator 2>/dev/null | awk '/"Device Utilization %"=/ && !u { match($0, /"Device Utilization %"=[0-9]+/); u = substr($0, RSTART + 24, RLENGTH - 24) } /"In use system memory"=/ && !m { match($0, /"In use system memory"=[0-9]+/); m = substr($0, RSTART + 23, RLENGTH - 23) } END { if (u != "") printf "%d %.1f", u, m / 1073741824 }'; }
compressed_gb() { vm_stat 2>/dev/null | awk '/page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) } /occupied by compressor/ { v = $NF; sub(/\./, "", v); pg = v } END { if (ps && pg) printf "%.1f", pg * ps / 1073741824 }'; }
timemachine() { tmutil status 2>/dev/null | awk '/Running/ { v = $3; gsub(/;/, "", v); r = v } /Percent/ { p = $3; gsub(/[";]/, "", p) } END { if (r == 1) printf "%s", (p + 0 > 0 ? sprintf("%d", p * 100) : "?") }'; }
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
  A_N=$(total AGENT "" 3)
  B_AGENT=$(total BUILD agent 3); B_AGENT_CPU=$(total BUILD agent 4)
  B_OWN=$(total BUILD own 3); B_OWN_CPU=$(total BUILD own 4)
  UNK_N=$(count UNK); SVC_N=$(count SVC); LEFT_N=$(count LEFT); SESS_N=$(count SESS); DUP_N=$(count DUP); RUN_N=$(count RUN); STUCK_N=$(count STUCK)
  ALL_CPU=$(total TOT "" 2); AG_CPU=$(total TOT "" 4); AG_MB=$(total TOT "" 5); P_NOW=$(total TOT "" 6)
  AG_PCT=$(pct "$AG_CPU"); UN_PTS=$(total TOT "" 7); UN_PCT=$(pct "$UN_PTS")
  IDLE_N=$(total SESS "" 9); IDLE_MB=$(total SESS "" 10); FORGOT_N=$(total SESS "" 12)
  PORTS=$(ports); PORT_N=$(echo "$PORTS" | awk 'NF { n++ } END { print n + 0 }')
  FOLDERS=$(folders)
  if (( REDACT )); then BRANCHES=""; else BRANCHES=$(branches); fi
  LOCKS=$(git_locks | sort -u -t"$TAB" -k1,1)
  NET=$(net_usage); NETSESS=$(net_by_session); VERSIONS=$(session_versions)
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
  read -r GPU GPU_GB <<< "$(gpu_info)"; COMPR=$(compressed_gb); TM=$(timemachine); HUNG_N=$(count HUNG)
}

# folders where two or more sessions are running builds at the same moment: "folder<TAB>claude#1 and claude#2"
# sessions starting processes at a runaway rate (120+ in the last minute) or holding 400+ processes: label<TAB>processes<TAB>started
storms() { echo "$SCAN" | awk -F'\t' '$1 == "SESS" && ($17 >= 120 || $5 >= 400) { printf "%s\t%d\t%d\n", $2, $5, $17 }'; }
collisions() {
  awk -F'\t' 'FNR == NR { if ($1 == "SESS") { lab[$3] = $2; bld[$3] = $11 } next }
    NF == 2 && ($1 in lab) && bld[$1] > 0 { who[$2] = who[$2] (who[$2] != "" ? " and " : "") lab[$1]; c[$2]++ }
    END { for (k in c) if (c[k] > 1) { n = split(k, a, "/"); printf "%s\t%s\n", a[n], who[k] } }' <(echo "$SCAN") <(echo "$FOLDERS")
}

stand_out() { # builds NOTES from what gather found
  NOTES=""
  local line top
  if (( UNK_N > 0 )); then
    line=$(echo "$SCAN" | awk -F'\t' '$1 == "UNK" { printf "%s%s (pid %s, open %s)", (n++ ? ", " : ""), $2, $3, $4 }')
    note 3 "$(pl "$UNK_N" "process looks" "processes look") like a coding agent the doctor does not recognise: $line. It is not counted. If it is one, run YARE_DOCTOR_AGENTS=NAME yare-doctor to include it, and please send the output of yare-doctor capture so the next version knows it."
  fi
  if (( SVC_N > 0 )); then
    line=$(echo "$SCAN" | awk -F'\t' '$1 == "SVC" { printf "%s%s (open %s, %d MB)", (n++ ? ", " : ""), $2, $4, $5 }')
    note 3 "$(pl "$SVC_N" "agent is" "agents are") running as a background service: $line. A service waits for messages or jobs, so it is not counted as a session. What it starts while it works appears under no session."
  fi
  while IFS=$'\t' read -r _ pid owner cpu age name; do
    [ -n "${pid:-}" ] && note 1 "$name (pid $pid, started by $owner) is using ${cpu}% CPU and has been running $age. It may be stuck in a loop."
  done <<< "$(echo "$SCAN" | awk -F'\t' '$1 == "RUN"')"
  while IFS=$'\t' read -r _ pid owner age name; do
    [ -n "${pid:-}" ] && note 2 "A $name build (pid $pid, $( [ "$owner" = - ] && echo yours || echo "started by $owner")) has been running $age at almost no CPU. It may be hung."
  done <<< "$(echo "$SCAN" | awk -F'\t' '$1 == "HUNG"')"
  while IFS=$'\t' read -r pid cpu cnt name starter; do
    [ -n "${pid:-}" ] || continue
    if (( cnt > 1 )); then
      note 3 "$cnt $name processes (for example pid $pid) are using $(awk -v c="$cpu" 'BEGIN { printf "%.0f", c }')% of a core together and have no agent or app above them: they were started by $starter, which started under the system. If an agent left them running, they keep going after its command ended. Try --why $pid."
    else
      note 3 "$name (pid $pid, $(awk -v c="$cpu" 'BEGIN { printf "%.0f", c }')% of a core) has no agent or app above it: it was started by $starter, which started under the system. If an agent left it running (a dev server, a test watcher), it keeps going after the agent's command ended. Try --why $pid."
    fi
  done <<< "$(echo "$SCAN" | awk -F'\t' '$1 == "DETACH" { k = $4 SUBSEP $5; c[k]++; cpu[k] += $3; if (!(k in pid)) pid[k] = $2; nm[k] = $4; st[k] = $5 } END { for (k in c) printf "%s\t%.1f\t%d\t%s\t%s\n", pid[k], cpu[k], c[k], nm[k], st[k] }' | sort -t"$TAB" -k2 -nr | head -2)"
  if [ -n "${TM:-}" ]; then note 2 "Time Machine is backing up right now${TM:+ ($TM%)}. Backups use the disk and CPU and can slow builds."; fi
  if [[ ${THERM:-100} =~ ^[0-9]+$ ]] && (( ${THERM:-100} < 100 )); then note 1 "macOS has recorded a CPU speed limit of ${THERM}% (heat or power). The Mac is running slower than normal."; fi
  local swap_mb; swap_mb=$(echo "${SWAP:-0}" | awk '/G/ { v = $1; sub(/G/, "", v); print int(v * 1024); next } { v = $1; sub(/M/, "", v); print int(v) }')
  if [[ ${swap_mb:-0} =~ ^[0-9]+$ ]] && (( ${swap_mb:-0} >= 2048 )) && [[ ${FREE:-100} =~ ^[0-9]+$ ]] && (( ${FREE:-100} < 30 )); then
    local big; big=$(echo "$SCAN" | awk -F'\t' '$1 == "MEM"' | sort -t"$TAB" -k4 -nr | head -1)
    note 1 "Swap use is $(fmt_size "$SWAP") and free memory is ${FREE}%. The Mac is short of memory.${big:+ The biggest holder is $(echo "$big" | cut -f5) at $(fmt_size "$(echo "$big" | cut -f4)M") ($(echo "$big" | cut -f3 | sed 's/^-$/not an agent/'))}."
  fi
  while IFS=$'\t' read -r _ name _ acpu _ _ asess ascpu; do
    [ -n "${name:-}" ] || continue
    if awk -v a="$acpu" -v s="$ascpu" 'BEGIN { exit !(a >= 20 && a >= 3 * s) }'; then
      note 2 "$name is using $(awk -v a="$acpu" 'BEGIN { printf "%.0f", a }')% of a core while the $(pl "$asess" "agent session" "agent sessions") inside it use only $(awk -v a="$ascpu" 'BEGIN { printf "%.0f", a }')%. The load is in the app itself (its windows, rendering and helper processes), not in the agent's own processes."
    fi
  done <<< "$(echo "$SCAN" | awk -F'\t' '$1 == "HOSTAPP"')"
  if awk -v p="$UN_PCT" 'BEGIN { exit !(p >= 25) }'; then note 2 "Agents and the apps they run in are using a quarter or more of the CPU right now, so your own builds are sharing the machine with them."; fi
  if (( STUCK_N > 0 )); then note 2 "$(pl "$STUCK_N" process processes) inside agent sessions $( [ "$STUCK_N" = 1 ] && echo is || echo are) suspended or zombies. A suspended one still holds its memory."; fi
  line=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $12 == 1 { printf "%s%s (open %s, %d MB)", (n++ ? "; " : ""), $2, $4, $7 }')
  if [ -n "$line" ]; then note 2 "Looks forgotten (open over 12 hours, almost no CPU used): $line. Closing it would free that memory."; fi
  line=$(collisions | awk -F'\t' '{ printf "%s%s are both running builds in %s", (n++ ? "; " : ""), $2, $1 }')
  if [ -n "$line" ]; then note 1 "$line right now. They share one build folder, so the builds can corrupt each other or fail with lock errors."; fi
  if [ -n "$LOCKS" ]; then
    local lk_n lk_first lk_age
    lk_n=$(echo "$LOCKS" | awk 'NF { n++ } END { print n + 0 }')
    IFS=$'\t' read -r lk_first _ lk_age <<< "$(echo "$LOCKS" | head -1)"
    if (( REDACT )); then lk_first="a lock file"; else lk_first="${lk_first##*/.git/}"; fi
    note 2 "$(pl "$lk_n" "stale git lock" "stale git locks") ($lk_first, left $(awk -v s="$lk_age" 'BEGIN { if (s >= 3600) printf "%dh ago", s / 3600; else printf "%dm ago", s / 60 }')) and old enough that nothing is using it. Git commands in those folders fail with 'Unable to create index.lock' until the file is removed (--cleanup shows the command)."
  fi
  line=$(storms | awk -F'\t' '{ printf "%s%s (%d processes, %d started in the last minute)", (n++ ? "; " : ""), $1, $2, $3 }')
  if [ -n "$line" ]; then note 2 "A session is starting processes at a very high rate, which usually means a tool loop or a retry storm: $line."; fi
  line=$(echo "$SCAN" | awk -F'\t' '$1 == "WAIT" { printf "%s%s (%s has waited %s with no CPU)", (n++ ? "; " : ""), $3, $5, $4 }')
  if [ -n "$line" ]; then note 2 "A session is probably waiting for you: $line. An agent cannot type a password or click a prompt, so it sits there until you answer or close it."; fi
  line=$(versions_report)
  if [ -n "$line" ]; then note 3 "Sessions of the same agent run different versions: $line. A session keeps the build it started with, so older ones miss updates and fixes until restarted."; fi
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
  local cpu_in_use; cpu_in_use=$(awk -v a="${ALL_CPU:-0}" -v c="$CORES" 'BEGIN { printf "%.0f", a / c }')
  if awk -v l="${LOAD:-0}" -v c="$CORES" 'BEGIN { exit !(l / c >= 1.0) }' && (( cpu_in_use < 50 )); then
    note 3 "The load average is high (${LOAD} on $CORES cores) but only ${cpu_in_use}% of the CPU is in use. The Mac is probably waiting on something else, often disk work such as Spotlight or media indexing after a restart, not on the CPU."
  fi
  if awk -v l="${LOAD:-0}" -v c="$CORES" 'BEGIN { exit !(l / c >= 1.0) }' && (( cpu_in_use >= 50 )); then
    local who="" tn tc to tk
    top=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP" { k = $3 SUBSEP $6; c[k]++; cpu[k] += $4; own[k] = $3; nm[k] = $6 } END { for (k in c) printf "%s\t%.1f\t%s\t%d\n", nm[k], cpu[k], own[k], c[k] }' | sort -t"$TAB" -k2 -nr | head -1)
    if [ -n "$top" ]; then
      IFS=$'\t' read -r tn tc to tk <<< "$top"
      who=" The biggest CPU user is $tn"
      if (( tk > 1 )); then who="$who ($tk processes)"; fi
      who="$who at ${tc}% of a core ($( [ "$to" = - ] && echo "not an agent" || echo "started by $to"))."
    fi
    note 2 "The Mac is overloaded: ${cpu_in_use}% of the CPU is in use and its load is ${LOAD} on $CORES cores (1.0 per core means fully busy).$who"
  fi
  top=$(echo "$SCAN" | awk -F'\t' '$1 == "MEM" && tolower($5) ~ /virtualization\.virtualmachine|qemu-system|com\.docker|docker desktop|vmmem|orbstack|colima|limactl|utm|prl_vm_app|virtualboxvm|krunkit/' | sort -t"$TAB" -k4 -nr | head -1)
  if [ -n "$top" ]; then
    local vmmb; vmmb=$(echo "$top" | cut -f4)
    note "$( (( vmmb >= 8192 )) && echo 2 || echo 3 )" "A virtual machine ($(echo "$top" | cut -f5)) holds $(fmt_size "${vmmb}M") of memory. Containers and VMs that agents start live inside it, so it is a common reason memory runs out."
  fi
  if [ "$ENERGY" = low ]; then note 2 "Low Power Mode is on. macOS slows CPU-heavy work such as builds in that mode."; fi
  if [[ ${DISK:-99} =~ ^[0-9]+$ ]] && (( ${DISK:-99} < 20 )); then note 2 "Only ${DISK} GB of disk is free. Builds, swap and caches can fail or slow down when the disk is this full."; fi
  if (( ${F_MAX:-0} > 0 && ${F_OPEN:-0} * 100 / ${F_MAX:-1} >= 60 )); then note 2 "The Mac has ${F_OPEN} files open out of a limit of ${F_MAX}. Agents and file watchers can hit that limit (errors like 'too many open files')."; fi
  if (( ${P_MAX:-0} > 0 && ${P_NOW:-0} * 100 / ${P_MAX:-1} >= 60 )); then note 2 "${P_NOW} processes are running out of a limit of ${P_MAX}. New processes can fail to start near the limit."; fi
  if [[ ${GPU:-0} =~ ^[0-9]+$ ]] && (( ${GPU:-0} >= 70 )); then note 3 "The GPU is ${GPU}% busy (${GPU_GB:-?} GB in use). Local models, screen recording and GPU-heavy apps compete for it."; fi
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
    note 3 "$(pl "$SESS_N" "agent session") $( [ "$SESS_N" = 1 ] && echo is || echo are) running. $( [ "$SESS_N" = 1 ] && echo "It and the app it runs in" || echo "Together they and the apps they run in") use about $(cpu_txt "$UN_PTS") and $(fmt_size "${AG_MB}M") of memory (agent processes alone: $(cpu_txt "$AG_CPU"))."
  fi
  if [ -z "$NOTES" ]; then note 4 "Nothing stands out right now. Run it again while an agent is working hard."; fi
}

# ---- terminal styling: colour only on a terminal (and when NO_COLOR is unset); plain text when piped ----
# On a 256-colour terminal (almost every Mac terminal) it uses a soft palette, gradient gauges, coloured status dots and severity pills.
# On an 8-colour terminal it falls back to the basic colours. Piped, or with NO_COLOR set, everything is plain text.
setup_ui() {
  COLS=${COLUMNS:-}; [[ $COLS =~ ^[0-9]+$ ]] || COLS=$(tput cols 2>/dev/null || echo 100); [[ $COLS =~ ^[0-9]+$ ]] || COLS=100
  if (( COLS > 110 )); then COLS=110; fi
  if (( COLS < 80 )); then COLS=80; fi
  ON=0; P256=0
  GRAD_LIST="78 114 150 186 222 215 209 203"; SPAL_LIST="75 141 213 80 117 183 150 105"; EMPC=238; BAN_LIST="81 75 69 105 141 177 213"; RULC_LIST="30 31 67 103 139 175"
  if [ "$COLOR" = 1 ] || { [ "$COLOR" = auto ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }; then ON=1; fi
  if (( ON )); then
    local e=$'\033'
    case "${TERM:-}" in *256*) P256=1 ;; esac
    if [ -n "${COLORTERM:-}" ] || [ -n "${TERM_PROGRAM:-}" ] || [ -z "${TERM:-}" ] || { [ "$COLOR" = 1 ] && [ "${TERM:-}" = dumb ]; }; then P256=1; fi
    B="${e}[1m"; D="${e}[2m"; U="${e}[4m"; X="${e}[0m"
    if (( P256 )) && [ "$THEME" = light ]; then
      # darker colours for a light terminal background
      R="${e}[38;5;160m"; Y="${e}[38;5;130m"; G="${e}[38;5;28m"; C="${e}[38;5;31m"
      CM="${e}[38;5;91m"; CB="${e}[38;5;25m"; CO="${e}[38;5;166m"; CP="${e}[38;5;163m"; CK="${e}[38;5;240m"
      PILL_R="${e}[1;38;5;231;48;5;160m"; PILL_Y="${e}[1;38;5;231;48;5;130m"; PILL_C="${e}[1;38;5;231;48;5;31m"; PILL_G="${e}[1;38;5;231;48;5;28m"; PILL_B="${e}[1;38;5;231;48;5;62m"
      GRAD_LIST="28 64 100 136 172 166 160 124"; SPAL_LIST="25 91 163 30 67 133 64 61"; EMPC=252; BAN_LIST="31 25 61 97 133 169 163"; RULC_LIST="153 146 139 175 218 224"
    elif (( P256 )); then
      R="${e}[38;5;203m"; Y="${e}[38;5;214m"; G="${e}[38;5;78m"; C="${e}[38;5;81m"
      CM="${e}[38;5;141m"; CB="${e}[38;5;75m"; CO="${e}[38;5;209m"; CP="${e}[38;5;213m"; CK="${e}[38;5;244m"
      PILL_R="${e}[1;38;5;231;48;5;160m"; PILL_Y="${e}[1;38;5;16;48;5;214m"; PILL_C="${e}[1;38;5;16;48;5;80m"; PILL_G="${e}[1;38;5;16;48;5;78m"; PILL_B="${e}[1;38;5;231;48;5;62m"
    else
      R="${e}[31m"; Y="${e}[33m"; G="${e}[32m"; C="${e}[36m"; CM="${e}[35m"; CB="${e}[34m"; CO="${e}[33m"; CP="${e}[95m"; CK="${e}[2m"
      PILL_R="${e}[1;97;41m"; PILL_Y="${e}[1;30;43m"; PILL_C="${e}[1;30;46m"; PILL_G="${e}[1;30;42m"; PILL_B="${e}[1;97;44m"
    fi
  else
    B=""; D=""; R=""; Y=""; G=""; C=""; U=""; X=""; CM=""; CB=""; CO=""; CP=""; CK=""
    PILL_R=""; PILL_Y=""; PILL_C=""; PILL_G=""; PILL_B=""
  fi
  local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if [ "${ASCII:-0}" = 1 ]; then loc=C; fi
  case "$loc" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) FULL="█"; EMPTY="░"; DOT="●"; RUL="─"; ELL="…"; MID="·"; OK="✓"; NO="✗"; ARR="↳"; ARW="→"; ACC="▌"; ICONS="◆ ◉ ▣ ◈ ✦ ◐ ▤ ▥"; SPARKS="▁ ▂ ▃ ▄ ▅ ▆ ▇ █" ;;
    *) FULL="#"; EMPTY="."; DOT="*"; RUL="-"; ELL="~"; MID="|"; OK="ok"; NO="X"; ARR=">"; ARW="->"; ACC="|"; ICONS="+ + + + + + + +"; SPARKS="_ . , : - = + #" ;;
  esac
}
uawk() { awk -v ON="$ON" -v P256="$P256" -v ELL="$ELL" -v FULL="$FULL" -v EMPTY="$EMPTY" -v RED="$R" -v YEL="$Y" -v GRN="$G" -v CYA="$C" -v MAG="$CM" -v BLU="$CB" -v ORG="$CO" -v PNK="$CP" -v GRY="$CK" \
  -v PLR="$PILL_R" -v PLY="$PILL_Y" -v PLC="$PILL_C" -v PLG="$PILL_G" -v PLB="$PILL_B" -v DIM="$D" -v BLD="$B" -v UND="$U" -v RST="$X" -v W="$COLS" -v RUL="$RUL" -v DOT="$DOT" -v ARR="$ARR" -v MID="$MID" -v ACC="$ACC" -v ICONS="$ICONS" -v SPARKS="$SPARKS" \
  -v GRAD="$GRAD_LIST" -v SPAL="$SPAL_LIST" -v SPAL8="36 35 34 96 95 94 92 37" -v EMPC="$EMPC" -v BAN="$BAN_LIST" -v RULC="$RULC_LIST" -v CH="abcdefghijklmnopqrstuvwxyz0123456789" "$@"; }
AWKLIB='
# awk counts bytes, so cutting a name with accents or CJK characters could split a character in two and print garbage.
# These count and cut whole UTF-8 characters instead (a character is one lead byte plus its continuation bytes 0x80-0xBF).
function u8init(   i) { if (U8) return; U8 = 1; for (i = 128; i < 256; i++) BV[sprintf("%c", i)] = i }
function ulen(s,   i, n, b) {
  if (s !~ /[^ -~]/) return length(s)
  u8init(); n = 0
  for (i = 1; i <= length(s); i++) { b = BV[substr(s, i, 1)] + 0; if (b < 128 || b >= 192) n++ }
  return n
}
function ucut(s, k,   i, n, b, e) { # the first k characters of s
  if (s !~ /[^ -~]/) return substr(s, 1, k)
  u8init(); n = 0; e = length(s)
  for (i = 1; i <= length(s); i++) { b = BV[substr(s, i, 1)] + 0; if (b < 128 || b >= 192) { if (n == k) { e = i - 1; break } n++ } }
  return substr(s, 1, e)
}
function fit(s, w) { if (ulen(s) <= w) return s; return ucut(s, w - 1) ELL }
function rp(s, w,   t, n) { t = fit(s, w); n = w - ulen(t); return (n > 0 ? sprintf("%" n "s", "") : "") t }
function pad(s, w,   t, n) { t = fit(s, w); n = w - ulen(t); return t (n > 0 ? sprintf("%" n "s", "") : "") }
function c256(n, fb) { if (!ON) return ""; return P256 ? sprintf("%c[38;5;%dm", 27, n) : sprintf("%c[%dm", 27, fb) }
function gcol(f,   a, n, k) {
  if (!ON) return ""
  if (!P256) return (f < 0.6) ? GRN : (f < 0.85) ? YEL : RED
  n = split(GRAD, a, " "); k = int(f * (n - 1) + 0.5) + 1; if (k < 1) k = 1; if (k > n) k = n
  return c256(a[k], 0)
}
function emp() { return c256(EMPC, 2) }
function bar(f, w,   n, i, o, e) { if (f < 0) f = 0; if (f > 1) f = 1; n = int(f * w + 0.5); o = ""; e = ""; for (i = 1; i <= n; i++) o = o FULL; for (; i <= w; i++) e = e EMPTY; return o (e == "" ? "" : emp() e RST) }
function gbar(f, w,   n, i, o, e) { if (f < 0) f = 0; if (f > 1) f = 1; n = int(f * w + 0.5); o = ""; e = ""; for (i = 1; i <= n; i++) o = o gcol(i / w) FULL; for (; i <= w; i++) e = e EMPTY; return o RST (e == "" ? "" : emp() e RST) }
function heat(v, w, c) { return (v + 0 >= c) ? RED : (v + 0 >= w) ? YEL : GRN }
function lvl(v, w, c) { return (v + 0 >= c) ? 2 : (v + 0 >= w) ? 1 : 0 }
function lcol(l) { return (l >= 2) ? RED : (l == 1) ? YEL : GRN }
function chip(l, a, b, c,   t) { t = (l >= 2) ? c : (l == 1) ? b : a; return lcol(l) DOT RST " " lcol(l) BLD pad(t, 12) RST }
function pill(k, t,   code) { code = (k == "r") ? PLR : (k == "y") ? PLY : (k == "c") ? PLC : (k == "b") ? PLB : PLG; if (!ON) return "[" t "]"; return code " " t " " RST }
function mb(v) { return (v >= 1024) ? sprintf("%.1f GB", v / 1024) : sprintf("%d MB", v) }
function scol(l,   p, kind, num, h, i, n, k, a, f) {
  if (!ON) return ""
  p = index(l, "#"); kind = p ? substr(l, 1, p - 1) : l; num = p ? substr(l, p + 1) + 0 : 0
  h = 0; for (i = 1; i <= length(kind); i++) h = (h * 31 + index(CH, tolower(substr(kind, i, 1)))) % 997
  n = split(SPAL, a, " "); split(SPAL8, f, " "); k = (h * 3 + num) % n + 1
  return c256(a[k], f[k])
}
function paint(s,   o, t, pre, col) {
  if (!ON) return s
  o = ""
  while (match(s, /[A-Za-z]+#[0-9]+|[0-9][0-9.]*(%| GB| MB| CPU-min| core| cores)|--[a-z]+|pid [0-9]+/)) {
    t = substr(s, RSTART, RLENGTH); pre = substr(s, 1, RSTART - 1)
    if (t ~ /#/) col = scol(t) BLD; else if (t ~ /^--/) col = CYA; else if (t ~ /^pid/) col = DIM; else col = BLD
    o = o pre col t RST; s = substr(s, RSTART + RLENGTH)
  }
  return o s
}
function spark(vals, mx,   n, a, i, g, ng, o, k) {
  ng = split(SPARKS, g, " "); n = split(vals, a, " "); o = ""
  if (mx < 1) mx = 1
  for (i = 1; i <= n; i++) { k = int(a[i] / mx * (ng - 1) + 0.5) + 1; if (k < 1) k = 1; if (k > ng) k = ng; o = o gcol((k - 1) / (ng - 1)) g[k] }
  return o RST
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
fmt_size() { echo "$1" | awk '/G/ { v = $1; sub(/G/, "", v); printf "%.1f GB", v; next } { v = $1; sub(/M/, "", v); v = v + 0; if (v >= 1024) printf "%.1f GB", v / 1024; else printf "%d MB", v }'; }
pl() { if [ "$1" = 1 ]; then echo "$1 $2"; else echo "$1 ${3:-${2}s}"; fi; }
# CPU in the unit Activity Monitor uses (100% = one core), plus the share of the whole Mac so the two are never confused
cpu_txt() { awk -v p="$1" -v c="$CORES" 'BEGIN { m = p / c; printf "%.0f%% of one core (%s%% of the whole Mac)", p, (m < 10 ? sprintf("%.1f", m) : sprintf("%.0f", m)) }'; }
fmt_k() { awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n / 1000; else printf "%d", n }'; }

rule() { uawk "$AWKLIB"'BEGIN { n = split(RULC, a, " "); m = W - 2; for (i = 0; i < m; i++) { k = int(i * n / m) + 1; printf "%s%s", (k != pk ? c256(a[k], 2) : ""), RUL; pk = k }; printf "%s\n", RST }'; }
banner() {
  uawk -v t="$1" "$AWKLIB"'BEGIN { s = "yare-doctor"; n = split(BAN, a, " "); for (i = 1; i <= length(s); i++) printf "%s%s%s", c256(a[int((i - 1) * n / length(s)) + 1], 36), BLD, substr(s, i, 1); printf "%s  %s%s%s\n", RST, DIM, t, RST }'
  rule
}
# each section gets its own accent colour
section() {
  local t
  case "$1" in
    "WHAT STANDS OUT"|"NEEDS A LOOK") t=$R ;;
    "AGENT SESSIONS") t=$CM ;;
    "HOST APPS") t=$CB ;;
    "WHO IS USING THE CPU") t=$CO ;;
    "WHO HOLDS THE MOST MEMORY"|"MEMORY BY PROGRAM") t=$CP ;;
    "BUILDS AND TESTS"|RESULT|TOOLS|PARSER|"THIS MAC") t=$G ;;
    "THE SAME HELPER STARTED MANY TIMES"|"WHAT KEEPS THIS MAC AWAKE"|"POSSIBLE LEFTOVERS") t=$Y ;;
    *) t=$C ;;
  esac
  printf '\n%s%s%s %s%s%s%s' "$t" "$ACC" "$X" "$B" "$t" "$1" "$X"
  if [ -n "${2:-}" ]; then printf '  %s%s%s' "$D" "$2" "$X"; fi
  printf '\n'
}

# the one-line answer: how many things to act on, to look at, to know
verdict() {
  local n1 n2 n3
  n1=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 1' | wc -l | tr -d ' ')
  n2=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 2' | wc -l | tr -d ' ')
  n3=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 3' | wc -l | tr -d ' ')
  uawk -v a="$n1" -v l="$n2" -v g="$n3" -v hs="${HSCORE:-100}" -v hg="${HGRADE:-A}" "$AWKLIB"'BEGIN {
    p = (a > 0) ? pill("r", "ACT ON IT") : (l > 0) ? pill("y", "WORTH A LOOK") : pill("g", "ALL CLEAR")
    sep = "  " DIM MID RST "  "
    gc = (hg == "A" || hg == "B") ? GRN : (hg == "C") ? YEL : (hg == "D") ? ORG : RED
    printf "  %s  %s%d to act on%s%s%s%d worth a look%s%s%s%d good to know%s%s%shealth %s%s%d/100 %s%s\n", p, (a > 0 ? RED BLD : DIM), a, RST, sep, (l > 0 ? YEL BLD : DIM), l, RST, sep, (g > 0 ? CYA BLD : DIM), g, RST, sep, DIM, RST, gc BLD, hs, hg, RST
  }'
}

print_notes() {
  local lv max=${1:-999}
  for lv in 1 2 3 4; do printf '%s' "$NOTES" | awk -F'\t' -v l="$lv" '$1 == l'; done | uawk -F'\t' -v max="$max" "$AWKLIB"'
    { if (++cnt > max) next
      k = ($1 == 1) ? "r" : ($1 == 2) ? "y" : ($1 == 3) ? "c" : "g"; t = ($1 == 1) ? "ACT " : ($1 == 2) ? "LOOK" : ($1 == 3) ? "INFO" : " OK "
      n = split(wrap($2, W - 12, "       "), L, "\n")
      for (i = 1; i <= n; i++) printf "  %s%s\n", (i == 1 ? pill(k, t) " " : ""), paint(L[i]) }'
}

# ---- the machine at a glance ----
dash() {
  local ver chip used pw en swmb onbat=0
  ver=${OSINFO%%,*}; chip=${OSINFO#*, }
  used=$(( 100 - ${FREE:-100} ))
  case $ENERGY in low) en="low power mode" ;; high) en="high power mode" ;; *) en="normal power mode" ;; esac
  if [ "${PSRC:-}" = battery ]; then pw="on battery"; onbat=1; else pw="plugged in"; fi
  swmb=$(echo "${SWAP:-0M}" | awk '/G/ { v = $1; sub(/G/, "", v); print v * 1024; next } { v = $1; sub(/M/, "", v); print v + 0 }')
  uawk -v cpus="$CORES" -v load="${LOAD:-0}" -v inuse="$(awk -v a="${ALL_CPU:-0}" -v c="$CORES" 'BEGIN { printf "%.1f", a / c }')" -v used="$used" -v unp="$UN_PCT" -v untxt="$(cpu_txt "$UN_PTS")" -v ns="$SESS_N" -v chipname="$chip" -v ver="$ver" -v mem="$MEM_GB" -v up="${UPD:-?}" \
    -v swap="$(fmt_size "${SWAP:-0M}")" -v swmb="$swmb" -v agmem="$(fmt_size "${AG_MB}M")" -v pw="$pw" -v onbat="$onbat" -v batt="${BATT:-}" -v en="$en" -v disk="${DISK:-?}" -v files="$(fmt_k "${F_OPEN:-0}")" -v procs="${P_NOW:-?}" -v compr="${COMPR:-}" -v gpu="${GPU:-}" -v gpugb="${GPU_GB:-}" -v mix="$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { split($2, a, "#"); c[a[1]]++ } END { for (k in c) printf "%s%s x%d", (n++ ? ", " : ""), k, c[k] }')" "$AWKLIB"'
  function lbl(i, name, col,   a) { split(ICONS, a, " "); return col a[i] RST " " col BLD pad(name, 8) RST }
  function blank(w,   s) { s = sprintf("%" w "s", ""); return s }
  BEGIN {
    sep = " " DIM MID RST " "
    printf "  %s %s%s%s%s%d cores%s%d GB%s%s%sup %s %s\n", lbl(1, "Mac", BLU), BLD, chipname, RST, sep, cpus, sep, mem, sep, ver, sep, up, (up == 1 ? "day" : "days")
    pct = inuse + 0; if (pct > 100) pct = 100; l = lvl(pct, 70, 90)
    hint = (load / cpus >= 1 && l == 0) ? "  " DIM "(load is high but little CPU is in use: the Mac may be waiting on disk or indexing)" RST : ""
    print "  " lbl(2, "CPU", ORG) " " gbar(pct / 100, 20) " " chip(l, "calm", "busy", "overloaded") " " lcol(l) BLD sprintf("%.0f%%", pct) RST " in use now" sep "load " sprintf("%.1f", load) " on " cpus " cores" hint
    ml = lvl(used, 80, 90); sl = lvl(swmb, 2048, 8192); if (used < 70) sl = 0; l = (sl > ml) ? sl : ml
    t = sprintf("%s%s%d%%%s used%s%s%s%s swap%s", lcol(ml), BLD, used, RST, sep, lcol(sl), BLD swap, RST, "")
    if (compr != "") t = t sep compr " GB compressed"
    printf "  %s %s %s %s\n", lbl(3, "Memory", PNK), gbar(used / 100, 20), chip(l, "fine", "tight", "short"), t
    if (gpu != "") { l = lvl(gpu, 70, 90); printf "  %s %s %s %s%s%d%%%s busy%s%s GB in use\n", lbl(4, "GPU", CYA), gbar(gpu / 100, 20), chip(l, "fine", "busy", "maxed"), lcol(l), BLD, gpu, RST, sep, gpugb }
    l = lvl(unp, 25, 50)
    printf "  %s %s %s %s%s%s%s%s%d%s\n", lbl(5, "Agents", MAG), gbar(unp / 100, 20), chip(l, "light", "noticeable", "heavy"), BLD, untxt, RST, sep, agmem sep, ns, (ns == 1 ? " session" : " sessions") (mix != "" ? " (" mix ")" : "")
    if (onbat) { bl = (batt + 0 < 20) ? 2 : (batt + 0 < 40) ? 1 : 0; printf "  %s %s %s %s%s%s%%%s%s%s\n", lbl(6, "Power", YEL), gbar(1 - batt / 100, 20), chip(bl, "on battery", "on battery", "low battery"), lcol(bl), BLD, batt, RST, sep, en }
    else printf "  %s %s %s %s\n", lbl(6, "Power", YEL), blank(20), chip(0, "plugged in", "", ""), en
    l = (disk != "?") ? ((disk + 0 < 10) ? 2 : (disk + 0 < 25) ? 1 : 0) : 0
    printf "  %s %s %s %s%s%s GB%s free\n", lbl(7, "Disk", BLU), blank(20), chip(l, "roomy", "getting full", "almost full"), lcol(l), BLD, disk, RST
    printf "  %s %s %s%s%s%s files open%s%s processes\n", lbl(8, "System", GRY), blank(20), blank(13), BLD, files, RST, sep, procs
  }'
}

# ---- tables ----
sessions_table() {
  if (( SESS_N == 0 )); then printf '  %sNo coding agent found running.%s\n' "$D" "$X"; return; fi
  uawk -F'\t' "$AWKLIB"'
    FNR == 1 { fi++ }
    fi == 1 { n = split($2, a, "/"); fold[$1] = a[n]; next }
    fi == 2 { fc[$1] = $2; next }
    fi == 3 { br[$1] = $2; next }
    fi == 4 { nin[$1] = $2; nout[$1] = $3; next }
    fi == 5 { ver[$1] = $2; next }
    $1 == "MCPS" { mcp[$2] = sprintf("%d MCP %s (%s)", $3, ($3 == 1 ? "server" : "servers"), mb($4)); next }
    $1 == "NOW" { now[$2] = $6 " " sprintf("%.0f%%", $4) " for " $5; next }
    $1 == "SESS" {
      if (!hdr++) {
        G = (W >= 98 ? "  " : " "); FW = W - 68 - 9 * length(G); if (FW < 10) FW = 10; if (FW > 26) FW = 26
        print "  " DIM "  " pad("SESSION", 10) G pad("FOLDER", FW) G pad("HOST", 10) G rp("RUNNING", 7) G rp("ACTIVE", 7) G rp("PROCS", 5) G rp("CPU", 6) G rp("MEMORY", 8) G rp("FILES", 5) G rp("BUILDS", 6) RST
      }
      files = ($2 in fc) ? fc[$2] : "-"
      sc = scol($2)
      dc = ($12 == 1) ? RED : ($16 >= 0 && $16 < 30) ? GRN : ($16 >= 0 && $16 < 600) ? CYA : ($16 >= 0 && $16 < 7200) ? DIM : ($16 >= 0) ? YEL : DIM
      print "  " dc DOT RST " " sc BLD pad($2, 10) RST G BLU pad(($3 in fold) ? fold[$3] : "-", FW) RST G scol($15) pad($15, 10) RST G rp($4, 7) G dc rp($18, 7) RST G rp($5, 5) G heat($6, 50, 100) rp(sprintf("%.1f%%", $6), 6) RST G heat($7, 1500, 4000) rp(mb($7), 8) RST G heat(files, 2000, 8000) rp(files, 5) RST G ($11 > 0 ? YEL : DIM) rp($11, 6) RST
      s = ""
      if ($3 in ver) s = s GRY "v" ver[$3] RST "  "
      if ($3 in br) s = s CYA "on " br[$3] RST "  "
      if ($2 in mcp) s = s MAG mcp[$2] RST "  "
      if (($2 in nin) && nin[$2] + nout[$2] >= 5242880) s = s BLU "network " mb(nin[$2] / 1048576) " in, " mb(nout[$2] / 1048576) " out" RST "  "
      if ($2 in now) s = s GRN "now" RST DIM ": " now[$2] RST "  "
      if ($12 == 1) s = s pill("r", "looks forgotten") " "
      if ($13 > 0) s = s pill("y", $13 " suspended") " "
      if ($14 > 0) s = s MAG pl($14, "nested agent", "nested agents") RST "  "
      if ($9 > 0) s = s YEL pl($9, "idle helper", "idle helpers") RST DIM " holding " mb($10) RST "  "
      if ($8 >= 5) s = s DIM sprintf("used %d CPU-min", $8) RST
      if (s != "") printf "      %s%s%s %s\n", DIM, ARR, RST, s
    }
    END { if (hdr) printf "  %s%s active now%s  %s%s recent%s  %s%s idle%s  %s%s idle over 2 h%s  %s%s looks forgotten%s\n", GRN, DOT, RST, CYA, DOT, RST, DIM, DOT, RST, YEL, DOT, RST, RED, DOT, RST }' <(printf '%s\n' "$FOLDERS") <(printf '%s\n' "$FILES") <(printf '%s\n' "$BRANCHES") <(printf '%s\n' "$NETSESS") <(printf '%s\n' "$VERSIONS") <(echo "$SCAN")
}

apps_table() {
  local ap; ap=$(echo "$SCAN" | awk -F'\t' '$1 == "HOSTAPP"' | sort -t"$TAB" -k4 -nr | head -5)
  [ -z "$ap" ] && return
  section "HOST APPS" "the app each session runs in, counting all its windows and helper processes"
  echo "$ap" | uawk -F'\t' "$AWKLIB"'{ nm[NR] = $2; cpu[NR] = $4; mem[NR] = $5; np[NR] = $6; ns[NR] = $7; sc[NR] = $8; if ($4 > mx) mx = $4 }
    END {
      NW = (W >= 104 ? 36 : 26)
      print "  " DIM "  " pad("APP", NW) "  " pad("", 8) " " rp("CPU", 7) " " rp("MEMORY", 9) "  " rp("PROCS", 5) "  " rp("SESSIONS", 8) "  " rp("AGENTS", 7) RST
      for (i = 1; i <= NR; i++) print "  " scol(nm[i]) DOT RST " " scol(nm[i]) BLD pad(nm[i], NW) RST "  " heat(cpu[i], 100, 250) bar(cpu[i] / (mx > 0 ? mx : 1), 8) RST " " heat(cpu[i], 100, 250) rp(sprintf("%.1f%%", cpu[i]), 7) RST " " heat(mem[i], 2000, 6000) rp(mb(mem[i]), 9) RST "  " rp(np[i], 5) "  " MAG rp(ns[i], 8) RST "  " CYA rp(sprintf("%.1f%%", sc[i]), 7) RST
    }'
}

cpu_table() {
  local top; top=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP" { k = $3 SUBSEP $6; c[k]++; cpu[k] += $4; mem[k] += $5; if (!(k in pid)) pid[k] = $2; own[k] = $3; nm[k] = $6 }
    END { for (k in c) printf "TOP\t%s\t%s\t%.1f\t%d\t%s%s\n", pid[k], own[k], cpu[k], mem[k], nm[k], (c[k] > 1 ? " x" c[k] : "") }' | sort -t"$TAB" -k4 -nr | head -6)
  if [ -z "$top" ]; then printf '  %sNothing above 1%% CPU.%s\n' "$D" "$X"; return; fi
  echo "$top" | uawk -F'\t' "$AWKLIB"'
    { name[NR] = $6; cpu[NR] = $4; mem[NR] = $5; own[NR] = $3; if ($4 > mx) mx = $4 }
    END {
      NW = (W >= 104 ? 40 : 30)
      print "  " DIM "  " pad("PROCESS", NW) "  " pad("", 8) " " rp("CPU", 7) " " rp("MEMORY", 9) "  " "STARTED BY" RST
      for (i = 1; i <= NR; i++) {
        a = (own[i] != "-")
        print "  " (a ? scol(own[i]) DOT : DIM "○") RST " " (a ? scol(own[i]) : "") pad(name[i], NW) RST "  " heat(cpu[i], 100, 250) bar(cpu[i] / mx, 8) RST " " heat(cpu[i], 100, 250) rp(sprintf("%.1f%%", cpu[i]), 7) RST " " heat(mem[i], 2000, 6000) rp(mb(mem[i]), 9) RST "  " (a ? scol(own[i]) BLD own[i] RST : DIM "not an agent" RST)
      }
    }'
  printf '  %sAgent processes: %s%s%s. Everything else: %s%s%s.%s\n' "$D" "$X$B$G" "$(cpu_txt "$AG_CPU")" "$X$D" "$X$B$Y" "$(cpu_txt "$(awk -v a="$ALL_CPU" -v g="$AG_CPU" 'BEGIN { v = a - g; if (v < 0) v = 0; print v }')")" "$X$D" "$X"
}

mem_table() {
  local mt; mt=$(echo "$SCAN" | awk -F'\t' '$1 == "MEM"' | sort -t"$TAB" -k4 -nr | head -5)
  [ -z "$mt" ] && return
  section "WHO HOLDS THE MOST MEMORY" "300 MB or more each"
  echo "$mt" | uawk -F'\t' "$AWKLIB"'
    { name[NR] = $5; mem[NR] = $4; own[NR] = $3; if ($4 > mx) mx = $4 }
    END {
      NW = (W >= 104 ? 40 : 30)
      print "  " DIM "  " pad("PROCESS", NW) "  " pad("", 8) " " rp("MEMORY", 9) "  " "STARTED BY" RST
      for (i = 1; i <= NR; i++) {
        a = (own[i] != "-")
        print "  " (a ? scol(own[i]) DOT : DIM "○") RST " " (a ? scol(own[i]) : "") pad(name[i], NW) RST "  " heat(mem[i], 2000, 6000) bar(mem[i] / mx, 8) RST " " heat(mem[i], 2000, 6000) rp(mb(mem[i]), 9) RST "  " (a ? scol(own[i]) BLD own[i] RST : DIM "not an agent" RST)
      }
    }'
}

footer() {
  local fw=$(( ${COLS:-100} > 100 ? 100 : ${COLS:-100} - 2 ))
  (( fw < 40 )) && fw=40
  printf '\n%s%s%s\n' "$D" "$(printf '%s' 'A rough snapshot, not a benchmark: the idle, leftover and runaway checks are heuristics. CPU is measured over about a second, so a short spike can be missed or caught.' | fold -s -w "$fw")" "$X"
  printf '%s%s%s\n' "$D" "$(printf '%s' 'More: yare-doctor tree (every process), cleanup, watch 60 (while an agent builds), live, share, help all.' | fold -s -w "$fw")" "$X"
  if (( SHARE )); then
    section "PASTE-ABLE SUMMARY" "counts only: no paths, user names or commands"
    echo "$1"
  fi
  local age_days; age_days=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$RELEASED" +%s 2>/dev/null || date +%s) ) / 86400 ))
  if (( age_days > 120 )); then printf '\n%sThis copy is %s days old (version %s). Newer versions detect more agents; check %s%s\n' "$D" "$age_days" "$VERSION" "https://github.com/Yare-Org/yare-doctor" "$X"; fi
  printf '\n%sWe would like to hear what it found. Yare is an early prototype Mac tool, not released yet:%s\n%s%s%s%s\n' "$D" "$X" "$C$U" "$LINK" "$X" ""
}

sec_needs() {
  if (( RUN_N + STUCK_N > 0 )); then
    section "NEEDS A LOOK" "inside agent sessions"
    echo "$SCAN" | uawk -F'\t' "$AWKLIB"'
      $1 == "RUN" { printf "  %s %s%s%s is at %s%s%% CPU%s after running %s: it may be stuck in a loop %s(started by %s%s%s, pid %s)%s\n", pill("r", "LOOP?"), BLD, pad($6, 22), RST, RED BLD, $4, RST, $5, DIM, scol($3) BLD, $3, RST DIM, $2, RST }
      $1 == "STUCK" { printf "  %s %s%s%s is %s %s(started by %s%s%s, pid %s): %s%s\n", pill("y", ($4 == "Z" ? "ZOMBIE" : "PAUSED")), BLD, pad($5, 22), RST, ($4 == "Z" ? "a zombie" : "suspended"), DIM, scol($3) BLD, $3, RST DIM, $2, ($4 == "Z" ? "already finished, waiting for its parent" : "it still holds its memory"), RST }'
  fi
}
sec_groups() {
  local gt; gt=$(echo "$SCAN" | awk -F'\t' '$1 == "GRP"' | sort -t"$TAB" -k4 -nr | head -5)
  if [ -n "$gt" ]; then
    section "MEMORY BY PROGRAM" "the same program counted together, so many small processes show up"
    echo "$gt" | uawk -F'\t' "$AWKLIB"'{ nm[NR] = $2; cnt[NR] = $3; mem[NR] = $4; cpu[NR] = $5; ag[NR] = $6; if ($4 > mx) mx = $4 }
      END { printf "  %s%-30s  %-8s %6s %9s  %s%s\n", DIM, "PROGRAM", "", "COUNT", "MEMORY", "INSIDE AGENT SESSIONS", RST
        for (i = 1; i <= NR; i++) printf "  %s%-30s%s  %s%s%s %6d %s%9s%s  %s\n", (ag[i] > 0 ? BLD : ""), pad(nm[i], 30), RST, heat(mem[i], 2000, 6000), bar(mem[i] / mx, 8), RST, cnt[i], heat(mem[i], 2000, 6000), mb(mem[i]), RST, (ag[i] > 0 ? MAG BLD ag[i] " of " cnt[i] RST : DIM "none" RST) }'
  fi
}
sec_builds() {
  section "BUILDS AND TESTS" "agent-started and yours"
  printf '  %s%s%s %-34s %s%3d%s   %s%s%% CPU%s\n' "$CM" "$DOT" "$X" "started by an agent" "$B$CM" "$B_AGENT" "$X" "$D" "$B_AGENT_CPU" "$X"
  printf '  %s%s%s %-34s %s%3d%s   %s%s%% CPU%s\n' "$CB" "$DOT" "$X" "not under any agent (likely yours)" "$B$CB" "$B_OWN" "$X" "$D" "$B_OWN_CPU" "$X"
  if (( B_AGENT > 0 && B_OWN > 0 )); then printf '  %s COLLIDING %s  both kinds are running at the same time right now\n' "$PILL_Y" "$X"; fi
  if (( B_AGENT + B_OWN > 0 )); then
    echo "$SCAN" | awk -F'\t' '$1 == "BLIST"' | sort -t"$TAB" -k5 -nr | head -6 | uawk -F'\t' "$AWKLIB"'{ if (!h++) printf "  %s%-26s %7s %7s  %s%s\n", DIM, "RUNNING NOW", "CPU", "FOR", "STARTED BY", RST
      printf "  %s%s%s %s%-26s%s %s%6.1f%%%s %7s  %s\n", ($3 == "-" ? BLU : scol($3)), DOT, RST, BLD, pad($7, 26), RST, heat($4, 100, 250), $4, RST, $6, ($3 == "-" ? BLU "you (not under an agent)" RST : scol($3) BLD $3 RST) }'
  fi
}
sec_helpers() {
  if (( DUP_N > 0 )); then
    section "THE SAME HELPER STARTED MANY TIMES" "3 or more inside agent sessions"
    echo "$SCAN" | awk -F'\t' '$1 == "DUP"' | sort -t"$TAB" -k3 -nr | head -5 | uawk -F'\t' "$AWKLIB"'{ printf "  %s%3d x%s  %-34s %s%9s%s  %sacross %s%s\n", YEL BLD, $3, RST, pad($2, 34), heat($4, 500, 2000), mb($4), RST, DIM, pl($5, "session", "sessions"), RST }'
  fi
}
sec_ports() {
  if (( PORT_N > 0 )); then
    section "PORTS HELD OPEN" "by agent sessions, or things they left behind"
    echo "$PORTS" | uawk -F'\t' "$AWKLIB"'{ printf "  %s:%-6s%s %-14s %s\n", CYA BLD, $2, RST, pad($1, 14), ($3 == "leftover" ? YEL "no parent: looks left over" RST : scol($3) BLD $3 RST) }'
  fi
}
sec_awake() {
  if [ -n "$AWAKE" ]; then
    section "WHAT KEEPS THIS MAC AWAKE" "apart from macOS itself"
    echo "$AWAKE" | uawk -F'\t' "$AWKLIB"'NF { k = $1 SUBSEP $4; if (!(k in seen)) { seen[k] = 1; ord[++n] = k; nm[k] = $1; ow[k] = $4; du[k] = $3 } kinds[k] = (k in kinds) ? ((index(kinds[k], $2) ? kinds[k] : kinds[k] " and " $2)) : $2 }
      END { for (i = 1; i <= n; i++) { k = ord[i]; printf "  %s%s%s  keeps the %s awake %s(%s)%s  %s\n", YEL, pad(nm[k], 14), RST, kinds[k], DIM, du[k], RST, (ow[k] == "-" ? DIM "not an agent" RST : scol(ow[k]) BLD ow[k] RST) } }'
  fi
}
sec_left() {
  if (( LEFT_N > 0 )); then
    section "POSSIBLE LEFTOVERS" "no parent, alive over 30 minutes: may be from sessions that ended"
    echo "$SCAN" | uawk -F'\t' "$AWKLIB"'$1 == "LEFT" { if (!h++) printf "  %s%8s %6s %9s %-10s %s%s\n", DIM, "PID", "CPU", "MEMORY", "RUNNING", "COMMAND", RST; printf "  %8s %5s%% %9s %-10s %s\n", $2, $3, mb($4), $5, $6 }'
    printf '  %sCheck before closing any of them. To close one yourself: kill PID. This script never does.%s\n' "$D" "$X"
  fi
}

snapshot() {
  prepare

  if (( JSON )); then
    local sj; sj=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { split($2, ag, "#"); printf "%s{\"label\":\"%s\",\"agent\":\"%s\",\"pid\":%d,\"processes\":%d,\"cpu_percent\":%s,\"memory_mb\":%d,\"cpu_minutes\":%d,\"idle_helpers\":%d,\"builds\":%d,\"looks_forgotten\":%s,\"host\":\"%s\",\"age_seconds\":%d}", (n++ ? "," : ""), $2, ag[1], $3, $5, $6, $7, $8, $9, $11, ($12 == 1 ? "true" : "false"), $15, $19 }')
    local ukj; ukj=$(echo "$SCAN" | awk -F'\t' '$1 == "UNK" { printf "%s{\"name\":\"%s\",\"pid\":%d,\"age\":\"%s\"}", (n++ ? "," : ""), $2, $3, $4 }')
    local svj; svj=$(echo "$SCAN" | awk -F'\t' '$1 == "SVC" { printf "%s{\"agent\":\"%s\",\"pid\":%d,\"age\":\"%s\",\"memory_mb\":%d}", (n++ ? "," : ""), $2, $3, $4, $5 }')
    local fj; fj=$(printf '%s' "$NOTES" | awk -F'\t' 'NF { t = $2; gsub(/\\/, "\\\\", t); gsub(/"/, "\\\"", t); printf "%s{\"level\":\"%s\",\"text\":\"%s\"}", (n++ ? "," : ""), ($1 == 1 ? "act" : $1 == 2 ? "look" : $1 == 3 ? "info" : "ok"), t }')
    printf '{"version":"%s","macos":"%s","cores":%s,"memory_gb":%s,"load_1m":%s,"swap_used":"%s","agents":%s,"agent_sessions":%s,"agent_cpu_percent_of_machine":%s,"agent_memory_mb":%s,"agent_builds":%s,"other_builds":%s,"possible_leftovers":%s,"idle_helpers":%s,"idle_helper_mb":%s,"repeated_helpers":%s,"ports_held":%s,"possible_runaways":%s,"suspended_or_zombie":%s,"forgotten_sessions":%s,"sleep_locks_by_agents":%s,"shared_folders":%s,"disk_free_gb":%s,"energy_mode":"%s","agent_cpu_percent_with_host_apps":%s,"agent_cpu_points_one_core":%s,"agent_with_host_apps_points_one_core":%s,"gpu_percent":%s,"compressed_memory_gb":%s,"time_machine_running":%s,"hung_builds":%s,"health_score":%s,"health_grade":"%s","reclaimable_mb":%s,"findings":[%s],"sessions":[%s],"services":[%s],"unknown_agents":[%s]}\n' \
      "$VERSION" "$OSINFO" "$CPUS" "$MEM_GB" "${LOAD:-null}" "${SWAP:-?}" "$A_N" "$SESS_N" "$AG_PCT" "$AG_MB" "$B_AGENT" "$B_OWN" "$LEFT_N" "$IDLE_N" "$IDLE_MB" "$DUP_N" "$PORT_N" "$RUN_N" "$STUCK_N" "$FORGOT_N" "$AWAKE_N" "$SHARED_N" "${DISK:-null}" "$ENERGY" "$UN_PCT" "$AG_CPU" "$UN_PTS" "${GPU:-null}" "${COMPR:-null}" "$([ -n "${TM:-}" ] && echo true || echo false)" "$HUNG_N" "$HSCORE" "$HGRADE" "$RECLAIM_MB" "$fj" "$sj" "$svj" "$ukj"
    return
  fi

  banner "$VERSION $MID read-only $MID nothing was changed"
  echo
  verdict
  echo
  dash
  section "WHAT STANDS OUT"
  print_notes
  section "AGENT SESSIONS" "each agent and everything it started"
  sessions_table
  local idle_installed; idle_installed=$(installed_scan | awk -F'\t' '$3 == 0 { printf "%s%s", (n++ ? ", " : ""), $1 }')
  if [ -n "$idle_installed" ]; then printf '  %sInstalled here, not running: %s  (yare-doctor installed shows where)%s\n' "$D" "$idle_installed" "$X"; fi
  apps_table
  section "WHO IS USING THE CPU" "measured over about a second; the owner is the agent session that started it"
  cpu_table
  mem_table
  sec_needs
  sec_groups
  sec_builds
  sec_helpers
  sec_ports
  sec_awake
  sec_left
  footer "$( (( SHARE )) && share_line )"
}

# ---- --watch: a table that fills in as it samples, then a short result ----
watch_mode() {
  local samples=$(( WATCH_SECS / INTERVAL )) i
  local peak_agents=0 peak_ab=0 peak_ob=0 peak_load=0 peak_sess=0 overlap=0 agent_build_samples=0 own_build_samples=0
  local sstat="" squeezed=0 busy=0 rows="" srows="" first_mem="" last_mem=0 allpids="" n0="" spk="" roots_first="" roots_all="" roots_last="" prows=""
  local swap_start; swap_start=$(swap_used)
  if (( ! JSON )); then
    banner "$VERSION $MID watching for ${WATCH_SECS}s $MID a sample every ${INTERVAL}s $MID read-only"
    printf '%sUse your Mac and your agents as you normally do.%s\n\n' "$D" "$X"
    printf '  %s%-9s %-23s %6s %9s %13s %12s%s\n' "$D" "TIME" "AGENTS+APPS, % OF MAC" "LOAD" "SESSIONS" "AGENT BUILDS" "YOUR BUILDS" "$X"
  fi
  for (( i = 1; i <= samples; i++ )); do
    SCAN=$(scan)
    local a ab ob l ns allc agc sp
    a=$(total AGENT "" 3); ab=$(total BUILD agent 3); ob=$(total BUILD own 3); l=$(load1); ns=$(count SESS)
    allc=$(total TOT "" 2); agc=$(total TOT "" 7); sp=$(pct "$agc")
    spk="$spk $sp"
    if (( ! JSON )); then
      uawk -v t="$(date +%H:%M:%S)" -v sp="$sp" -v l="${l:-0}" -v cores="$CORES" -v ns="$ns" -v ab="$ab" -v ob="$ob" "$AWKLIB"'BEGIN {
        mark = (ab > 0 && ob > 0) ? "  " pill("y", "COLLIDING") : ""
        printf "  %s%-9s%s %s %s%5s%%%s %s%6s%s %9s %s%13s%s %s%12s%s%s\n", DIM, t, RST, gbar(sp / 100, 16), heat(sp, 25, 50), sp, RST, heat(l / cores * 100, 70, 100), l, RST, ns, (ab > 0 ? MAG BLD : DIM), ab, RST, (ob > 0 ? BLU BLD : DIM), ob, RST, mark }'
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
    roots_last=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $3 }'); [ -z "$roots_first" ] && roots_first=$roots_last
    roots_all="${roots_all}${roots_last}"$'\n'
    prows="${prows}$(echo "$SCAN" | awk -F'\t' '$1 == "MEM" { print $2 "\t" $3 "\t" $4 "\t" $5 }')"$'\n'
    rows="${rows}${allc} ${agc}"$'\n'
    srows="${srows}$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $3, $2, $6, $7 }')"$'\n'
    sstat="${sstat}$(echo "$SCAN" | awk -F'\t' -v i="$i" '$1 == "SESS" { print i "\t" $3 "\t" $2 "\t" $6 "\t" $7 }')"$'\n'
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
  local started ended n_first n_last
  n_first=$(echo "$roots_first" | awk 'NF { n++ } END { print n + 0 }'); n_last=$(echo "$roots_last" | awk 'NF { n++ } END { print n + 0 }')
  started=$(echo "$roots_all" | sort -u | awk 'NR == FNR { f[$1] = 1; next } NF && !($1 in f) { n++ } END { print n + 0 }' <(echo "$roots_first") -)
  ended=$(echo "$roots_all" | sort -u | awk 'NR == FNR { l[$1] = 1; next } NF && !($1 in l) { n++ } END { print n + 0 }' <(echo "$roots_last") -)
  local pgrow; pgrow=$(printf '%s' "$prows" | awk -F'\t' 'NF { if (!($1 in f)) { f[$1] = $3; nm[$1] = $4; ow[$1] = $2 } l[$1] = $3 } END { for (p in l) { d = l[p] - f[p]; if (d > m) { m = d; b = nm[p] " (" (ow[p] == "-" ? "not an agent" : "started by " ow[p]) ")" } } if (m >= 100) printf "%s grew by %d MB", b, m }')
  LOAD=$peak_load; SWAP=$swap_end; B_AGENT=$peak_ab; B_OWN=$peak_ob
  if (( JSON )); then
    printf '{"version":"%s","watch_seconds":%s,"peak_agents":%s,"peak_sessions":%s,"peak_agent_builds":%s,"peak_other_builds":%s,"seconds_agent_builds_overlapped_other_builds":%s,"seconds_with_agent_builds":%s,"seconds_with_other_builds":%s,"seconds_machine_busy":%s,"seconds_squeezed_by_agents":%s,"agent_cpu_minutes":%s,"other_cpu_minutes":%s,"agent_memory_mb_start":%s,"agent_memory_mb_end":%s,"sessions_started":%s,"sessions_ended":%s,"new_processes_seen":%s,"peak_load_1m":%s,"swap_used_start":"%s","swap_used_end":"%s"}\n' \
      "$VERSION" "$WATCH_SECS" "$peak_agents" "$peak_sess" "$peak_ab" "$peak_ob" "$ov_s" "$ab_s" "$ob_s" "$busy_s" "$sq_s" "$ag_min" "$oth_min" "${first_mem:-0}" "${last_mem:-0}" "$started" "$ended" "$newp" "${peak_load:-0}" "${swap_start:-?}" "${swap_end:-?}"
    return
  fi
  local line_sparks; line_sparks=$(uawk -v v="$spk" "$AWKLIB"'BEGIN { mx = 0; n = split(v, a, " "); for (i = 1; i <= n; i++) if (a[i] + 0 > mx) mx = a[i] + 0; print spark(v, mx) }')
  if [ -n "$sstat" ]; then
    section "SESSIONS DURING THE WATCH" "average and peak CPU, memory at the start and the end"
    printf '%s' "$sstat" | uawk -F'\t' -v n="$samples" -v iv="$INTERVAL" "$AWKLIB"'
      NF >= 5 { r = $2; if (!(r in first)) { first[r] = $1; order[++no] = r; m0[r] = $5 } last[r] = $1; lab[r] = $3; c[r]++; sum[r] += $4; if ($4 > pk[r]) pk[r] = $4; m1[r] = $5 }
      END {
        if (!no) exit
        printf "  %s%-12s %8s  %8s  %9s  %9s  %s%s\n", DIM, "SESSION", "AVG CPU", "PEAK CPU", "MEM START", "MEM END", "WHEN", RST
        for (i = 1; i <= no; i++) {
          r = order[i]; w = ""
          if (first[r] > 1) w = w YEL "started " (first[r] - 1) * iv "s in" RST " "
          if (last[r] < n) w = w RED "ended " last[r] * iv "s in" RST " "
          if (w == "") w = DIM "whole time" RST
          printf "  %s%s%-12s%s %s%7.1f%%%s  %s%7.1f%%%s  %9s  %9s  %s\n", scol(lab[r]), BLD, lab[r], RST, heat(sum[r] / c[r], 50, 100), sum[r] / c[r], RST, heat(pk[r], 50, 100), pk[r], RST, mb(m0[r]), mb(m1[r]), w
        }
      }'
  fi
  section "RESULT" "over ${WATCH_SECS}s"
  printf '  %s%-16s%s agents and their apps, CPU over time  %s%s%s\n' "$D" "Trend" "$X" "$C" "$line_sparks" "$X"
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
  printf '  %s%-16s%s %s at the start, %s at the end %s(%s started, %s ended)%s\n' "$D" "Sessions" "$X" "$n_first" "$n_last" "$D" "$started" "$ended" "$X"
  if [ -n "$pgrow" ]; then printf '  %s%-16s%s %s%s%s %s\n' "$D" "Fastest growth" "$X" "$Y" "$DOT" "$X" "$pgrow"; fi
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
    function shortpath(x,   q, m) { m = split(x, q, "/"); if (length(x) <= 28) return x; return (m > 2 && length(q[m - 1] "/" q[m]) <= 30) ? ".../" q[m - 1] "/" q[m] : q[m] }
    function short(c,   a, k, o, i, r, n, j) {
      j = index(c, ".app/Contents/MacOS/"); if (j) { r = substr(c, j + 20); sub(/ -.*/, "", r); return substr(r, 1, 40) }
      k = split(c, a, " "); n = split(a[1], o, "/"); r = o[n]
      for (i = 2; i <= k && i <= 3; i++) r = r " " ((a[i] ~ /\//) ? shortpath(a[i]) : a[i])
      return substr(r, 1, 60)
    }
    { P[$1] = $2; C[$1] = $4; R[$1] = $5; E[$1] = $6; cmd = ""; for (i = 8; i <= NF; i++) cmd = cmd (i > 8 ? " " : "") $i; N[$1] = cmd }
    END {
      if (!(t in N)) { print "No process with pid " t "."; exit 1 }
      q = t; d = 0
      while (q in N && d < 30) { chain[++d] = q; q = P[q]; if (q <= 1) break }
      for (i = d; i >= 1; i--) {
        pad2 = ""; for (j = 0; j < d - i; j++) pad2 = pad2 "  "
        printf "  %s%s%s%s%s%s  %s(pid %s) %s%.1f%% CPU%s%s, %s, running %s%s\n", pad2, CYA, (i < d ? ARR " " : ""), (i == 1 ? GRN BLD : (i == d ? BLD : "")), short(N[chain[i]]), RST, DIM, chain[i], heat(C[chain[i]], 50, 100), C[chain[i]], RST, DIM, mb(R[chain[i]] / 1024), human(etsecs(E[chain[i]])), RST
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
  local line rec
  line=$(real_procs | awk -v p="$WHY_PID" '$1 == p')
  if [ -n "$line" ]; then
    procs() { printf '%s\n' "$line"; }
    rec=$(INSTANT=0 scan | awk -F'\t' '$1 == "AGENT" { print $2; exit }')
    procs() { real_procs; }
    if [ -n "$rec" ]; then printf '  %s this process is itself a coding agent (%s)\n' "$(uawk "$AWKLIB"'BEGIN { printf "%s", pill("g", "AGENT") }')" "$rec"
    else printf '  %s%s this process is not recognised as a coding agent (see --rules)%s\n' "$D" "$ARW" "$X"; fi
  fi
  if [ -n "$owner" ] && [ "$owner" != leftover ]; then printf '  %s %s\n' "$(uawk "$AWKLIB"'BEGIN { printf "%s", pill("c", "OWNER") }')" "it belongs to agent session $(uawk -v o="$owner" "$AWKLIB"'BEGIN { printf "%s%s%s%s", scol(o), BLD, o, RST }')"; else printf '  %s %s%s%s\n' "$(uawk "$AWKLIB"'BEGIN { printf "%s", pill("b", "NO AGENT") }')" "$D" "it is not under any coding agent we recognise" "$X"; fi
}

# ---- --oneline: a short status for a tmux or prompt status bar (skips the slower checks) ----
oneline() {
  SAMPLE_GAP=0.4; SCAN=$(scan)
  SESS_N=$(count SESS); AG_MB=$(total TOT "" 5); LOAD=$(load1); FREE=$(mem_free_pct)
  local pts; pts=$(awk -v v="$(total TOT "" 7)" 'BEGIN { printf "%.0f", v }')
  local mark="$OK"; if (( $(count RUN) > 0 )); then mark="$DOT"; fi
  UN_PTS=$(total TOT "" 7); AG_MB=$(total TOT "" 5)
  if [ -n "$(over_budget)" ]; then mark="$DOT"; fi
  printf '%s %s %s %s %s %s%% of a core incl. apps %s load %s %s %s%% memory free\n' "$mark" "$(pl "$SESS_N" agent agents)" "$MID" "$(fmt_size "${AG_MB}M")" "$MID" "$pts" "$MID" "${LOAD:-?}" "$MID" "${FREE:-?}"
}

# ---- --check: quiet, exit code 0 nothing to do / 1 worth a look / 2 act on it ----
# --notify (with --check): also show a macOS notification when there is something to look at. The only thing it ever "does".
notify_mac() {
  (( NOTIFY )) || return 0
  local t="${2//\\/}"; t="${t//\"/}"; t="${t:0:200}"
  osascript -e "display notification \"$t\" with title \"yare-doctor: $1\"" >/dev/null 2>&1 || true
}
check() {
  prepare
  local over; over=$(over_budget)
  if [ -n "$over" ]; then printf '%s%s over budget:%s %s\n' "$R" "$DOT" "$X" "$(echo "$over" | head -1)"; notify_mac "Over budget" "$(echo "$over" | head -1)"; return 2; fi
  local worst; worst=$(printf '%s' "$NOTES" | awk -F'\t' 'NF && $1 < 3 { if (!w || $1 < w) w = $1 } END { print w + 0 }')
  local first; first=$(printf '%s' "$NOTES" | awk -F'\t' 'NF && $1 < 3' | sort -t"$TAB" -k1,1 | head -1 | cut -f2)
  case $worst in
    1) printf '%s%s act on it:%s %s\n' "$R" "$DOT" "$X" "$first"; notify_mac "Act on it" "$first"; return 2 ;;
    2) printf '%s%s worth a look:%s %s\n' "$Y" "$DOT" "$X" "$first"; notify_mac "Worth a look" "$first"; return 1 ;;
    *) printf '%s%s nothing to do%s\n' "$G" "$OK" "$X"; return 0 ;;
  esac
}

# ---- --live: the same sessions and CPU tables, refreshed in place ----
live() {
  local hist="" mhist="" frame tty=0 key=""
  [ -t 1 ] && tty=1
  if (( tty )); then trap 'printf "\033[?25h\n"; exit 0' INT TERM; printf '\033[?25l\033[2J'; else trap 'exit 0' INT TERM; fi
  while true; do
    SCAN=$(scan); gather
    mhist=$(echo "$mhist $AG_MB" | awk '{ n = NF; s = (n > 48) ? n - 47 : 1; o = ""; for (i = s; i <= n; i++) o = o " " $i; print substr(o, 2) }')
    hist=$(echo "$hist $AG_PCT" | awk '{ n = NF; s = (n > 48) ? n - 47 : 1; o = ""; for (i = s; i <= n; i++) o = o " " $i; print substr(o, 2) }')
    frame=$(
      banner "$VERSION $MID live $MID every 3 s $MID Ctrl-C to quit $MID read-only"
      echo
      dash
      printf '  %s%-9s%s agent CPU, last %s samples  %s%s%s\n' "$D" "Trend" "$X" "$(echo "$hist" | wc -w | tr -d ' ')" "$C" "$(uawk -v v="$hist" "$AWKLIB"'BEGIN { n = split(v, a, " "); for (i = 1; i <= n; i++) if (a[i] + 0 > mx) mx = a[i] + 0; print spark(v, mx) }')" "$X"
      printf '  %s%-9s%s agent memory          %s%s%s\n' "$D" "Trend" "$X" "$CP" "$(uawk -v v="$mhist" "$AWKLIB"'BEGIN { n = split(v, a, " "); for (i = 1; i <= n; i++) if (a[i] + 0 > mx) mx = a[i] + 0; print spark(v, mx) }')" "$X"
      echo "$mhist" | awk -v d="$D" -v y="$Y" -v x="$X" '{ n = NF; if (n >= 10 && $n - $(n - 9) >= 300) printf "  %s%-9s%s %sagent memory grew by %d MB over the last 10 samples%s\n", d, "Growing", x, y, $n - $(n - 9), x }'
      section "AGENT SESSIONS"
      sessions_table
      section "WHO IS USING THE CPU"
      cpu_table
      printf '\n%s q quit %s space pause %s r refresh now%s\n' "$D" "$MID" "$MID" "$X"
    )
    if (( tty )); then printf '\033[H%s\033[J' "$frame"; else printf '%s\n\n' "$frame"; fi
    if (( tty )); then
      key=""; read -rsn1 -t 3 key || true
      case $key in q|Q) printf '\033[?25h\n'; exit 0 ;; " ") read -rsn1 key || true ;; esac
    else
      sleep 3
    fi
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
101 100 S 0.0 90000 01:30:00 00:00.10 node /x/mcp-server.js
102 100 S 0.0 90000 01:30:00 00:00.10 node /y/mcp-server.js
103 100 S 0.0 90000 01:30:00 00:00.10 node /z/mcp-server.js
104 100 S 5.0 20000 01:00 00:02.00 /usr/bin/clang -c a.c
105 104 T 0.0 1000 20:00 00:00.00 worker
106 100 R 90.0 80000 20:00 00:12.00 python3 loop.py
107 106 S 0.0 1000 01:00 00:00.01 /usr/local/bin/claude -p subtask
108 100 S 0.0 1000 30:00 00:00.50 /usr/bin/clang -c hung.c
300 1 S 0.0 40000 01:00:00 00:00.10 node /w/mcp-leftover.js
400 1 S 80.0 100000 10:00 05:00.00 /opt/homebrew/bin/node /srv/dev-server.js
EOF
  }
  INSTANT=0; SCAN=$(scan); INSTANT=1
  section "PARSER" "a made-up process list with known answers"
  chk "one agent session found" "$(count SESS)" 1
  chk "session has 9 processes" "$(total SESS "" 5)" 9
  chk "nested agent found" "$(total SESS "" 14)" 1
  chk "terminal app found (iTerm)" "$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" { print $15 }')" iTerm
  chk "agent builds found under the agent" "$(total BUILD agent 3)" 2
  chk "hung build found" "$(count HUNG)" 1
  chk "same helper 3 times found" "$(echo "$SCAN" | awk -F'\t' '$1 == "DUP" { print $3 }')" 3
  chk "program group found (node x5)" "$(echo "$SCAN" | awk -F'\t' '$1 == "GRP" && $2 == "node" { print $3 }')" 5
  chk "leftover found" "$(count LEFT)" 1
  chk "busy detached process found" "$(count DETACH)" 1
  chk "suspended process found" "$(count STUCK)" 1
  chk "runaway process found" "$(count RUN)" 1
  chk "MCP servers counted per session" "$(echo "$SCAN" | awk -F'\t' '$1 == "MCPS" { print $3 }')" 3
  chk "busiest thing the session runs now" "$(echo "$SCAN" | awk -F'\t' '$1 == "NOW" { print $6 }')" python3
  chk "this script and its tools are not counted" "$(echo "$SCAN" | awk -F'\t' '$1 == "TOT" { print $6 }')" 12
  # 1b) which command lines are coding agents: every case is one process; "-" means it must NOT be recognised
  section "DETECTION" "what counts as a coding agent, and what must not"
  det() { # expected, command line
    local want=$1 cmd=$2 got
    procs() { printf '5000 1 S 0.0 1000 01:00:00 00:00.10 %s\n' "$cmd"; }
    INSTANT=0; got=$(scan | awk -F'\t' '$1 == "AGENT" { print $2; exit }'); INSTANT=1
    chk "${cmd:0:62}" "${got:--}" "$want"
  }
  det claude        '/Users/me/.local/share/claude/versions/2.1.319 --resume'
  det cursor-agent  '/Users/me/.local/bin/cursor-agent --use-system-ca /Users/me/.local/share/cursor-agent/versions/2026.05.20-2b5dd59/index.js'
  det codex         '/Users/me/.local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex'
  det gemini        '/Users/me/.hermes/node/bin/node --max-old-space-size=18432 /opt/homebrew/bin/gemini'
  det -             '/Users/me/.codex/packages/app-server-daemon/releases/0.166.0-aarch64-apple-darwin/bin/codex app-server --listen unix:// --managed-daemon'
  det -             '/Users/me/.codex/packages/app-server-daemon/releases/0.166.0-aarch64-apple-darwin/bin/codex app-server daemon pid-update-loop'
  det -             '/Users/me/.opencode/bin/opencode serve --service'
  det claude        'claude --resume'
  det grok          '/opt/homebrew/bin/grok'
  det junie         'node /opt/homebrew/bin/junie --resume'
  det jules         '/Users/me/.local/bin/jules'
  det -             'grok --version'
  det kiro-cli      '/tmp/live/kiro/kirocli/bin/kiro-cli chat'
  det devin         '/tmp/live/home/.local/bin/devin'
  det plandex       '/tmp/live/plandex/plandex'
  det -             '/tmp/live/kiro/kirocli/bin/kiro-cli --version'
  det -             '/tmp/live/home/.local/bin/devin login'
  det -             '/Users/me/.hermes/hermes-agent/.hermes/bin/hermes gateway run --external-supervisor'
  det -             '/Users/me/.hermes/tools/python-3.14.7/bin/python3 -I -c import os, re, sys\012sys.path.insert(0, /Users/me/.hermes/hermes-agent)\012from hermes_cli.main import main\012sys.exit(main())\012 gateway run --external-supervisor'
  det hermes        '/Users/me/.hermes/hermes-agent/.hermes/bin/hermes'
  det hermes        '/Users/me/.hermes/hermes-agent/.hermes/bin/hermes chat'
  det -             '/Users/me/.cline/bin/.cline --cline-hub-daemon --cwd /tmp/w'
  det -             '/Users/me/.local/bin/claude --chrome-native-host'
  det -             '/Users/me/.local/share/claude/versions/2.1.319 --chrome-native-host chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn/'
  det claude        '/Users/me/.local/bin/claude --chrome'
  det junie         '/Users/me/.local/share/junie/versions/3110.7/Applications/junie.app/Contents/MacOS/junie'
  det junie         '/Users/me/.local/share/junie/versions/3110.7/Applications/junie.app/Contents/MacOS/junie --resume'
  det -             '/Users/me/.local/share/junie/versions/3110.7/Applications/junie.app/Contents/MacOS/junie --version'
  det openhands     '/tmp/live/oh/tools/openhands/bin/python /tmp/live/oh/bin/openhands'
  det -             '/tmp/live/cline/node_modules/cline/bin/.cline --cline-hub-daemon --cwd /tmp/work'
  det -             'junie login'
  det claude        '/Users/me/Library/Application Support/Claude/claude-code/2.1.317/91184d3d9ba3/claude.app/Contents/MacOS/claude --output-format stream-json --verbose'
  det -             '/Users/me/Library/Application Support/Claude/claude-code/2.1.317/91184d3d9ba3/claude.app/Contents/MacOS/claude --version'
  det -             '/Applications/Claude.app/Contents/MacOS/Claude'
  det -             'node /Users/me/app/server.js --name claude'
  det -             'python3 /Users/me/tools/report.py --agent codex'
  det -             'node /Users/me/app/index.js gemini'
  det -             'node -e console.log("claude")'
  det -             'python3 -c print("aider")'
  det aider         'python3 -m aider --model sonnet'
  det aider         '/Users/me/venv/bin/python3 -m aider'
  det claude        'node --max-old-space-size=8192 --import tsx /Users/me/.nvm/versions/node/v22.1.0/lib/node_modules/@anthropic-ai/claude-code/cli.js'
  det claude        'npx -y @anthropic-ai/claude-code@latest'
  det codex         'bunx @openai/codex@0.1.2'
  det aider         'uvx --from aider-chat aider'
  det aider         'uv tool run aider'
  det gemini        'bun run /Users/me/.bun/bin/gemini'
  det claude        '/Users/me/.local/bin/claude --output-format stream-json --verbose'
  det claude        'node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js'
  det claude        '/Applications/T3 Code (Beta).app/Contents/Resources/bin/claude --model x'
  det codex         'codex'
  det codex         'node /opt/homebrew/bin/codex'
  det codex         '/Applications/Codex.app/Contents/Resources/codex app-server --listen stdio'
  det codex         'npx @openai/codex'
  det gemini        'node /Users/me/proj/node_modules/.bin/gemini'
  det gemini        'node /usr/lib/node_modules/@google/gemini-cli/dist/index.js'
  det aider         'python3 -m aider --model sonnet'
  det aider         '/usr/bin/python3 /Users/me/.local/bin/aider'
  det aider         'uvx --from aider-chat aider'
  det opencode      'opencode'
  det opencode      'bunx opencode-ai'
  det cursor-agent  'cursor-agent --print'
  det goose         'goose session'
  det copilot       'copilot'
  det amp           'amp'
  det hermes        '/Users/me/.hermes/hermes-agent/.hermes/bin/hermes --run-module cli'
  det hermes        "/Users/me/.hermes/tools/python-3.14.7/bin/python3 -I -c import sys, runpy; sys.path.insert(0, '/Users/me/.hermes/hermes-agent')"
  det -             'python3 -c print(1)'
  det aider         '/tmp/live/aider2.hGD9/venv/bin/python3 /tmp/live/aider2.hGD9/venv/bin/aider --no-check-update --no-analytics'
  det kimi          '/tmp/live/kimi.i9O9/venv/bin/python3 /tmp/live/kimi.i9O9/venv/bin/kimi'
  det goose         '/tmp/live/goose.DVic/x/goose session'
  det claude        '/usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe --resume'
  det opencode      '/opt/homebrew/lib/node_modules/opencode-ai/bin/opencode.exe'
  det amp           '/opt/homebrew/lib/node_modules/@sourcegraph/amp/node_modules/@ampcode/cli/bin/amp.exe'
  det kilo          'node /opt/homebrew/lib/node_modules/@kilocode/cli/bin/kilo'
  det continue      'node /opt/homebrew/lib/node_modules/@continuedev/cli/dist/cn.js'
  det continue      'node /tmp/live/cn.NKo7/node_modules/.bin/cn'
  det -             'node /tmp/proj/node_modules/.bin/cnpm install'
  det copilot       'node /tmp/live/copilot.wofm/node_modules/.bin/copilot'
  det copilot       '/tmp/live/copilot.wofm/node_modules/@github/copilot-darwin-arm64/copilot'
  det amp           '/tmp/live/amp.c9S5/node_modules/.bin/amp'
  det qwen          'node /tmp/live/qwen.McGW/node_modules/.bin/qwen'
  det auggie        'node /tmp/live/auggie.bbzh/node_modules/.bin/auggie'
  det crush         'node /tmp/live/crush.jqyC/node_modules/.bin/crush'
  det kilo          'node /tmp/live/kilo.uCfb/node_modules/.bin/kilo'
  det droid         '/tmp/live/droid.coMv/node_modules/.bin/droid'
  det droid         '/Users/me/.local/bin/droid'
  det copilot       'node /opt/homebrew/lib/node_modules/@github/copilot/npm-loader.js'
  det qwen          'node /opt/homebrew/lib/node_modules/@qwen-code/qwen-code/cli-entry.js'
  det auggie        'node /opt/homebrew/lib/node_modules/@augmentcode/auggie/augment.mjs'
  det crush         'node /opt/homebrew/lib/node_modules/@charmland/crush/run-crush.js'
  det qwen          'qwen'
  det kiro-cli      'kiro-cli chat'
  det -             '/Applications/Claude.app/Contents/MacOS/Claude'
  det -             '/Applications/Codex.app/Contents/MacOS/Codex'
  det -             '/Applications/Cursor.app/Contents/MacOS/Cursor'
  det -             'claude --version'
  det -             'claude mcp serve'
  det -             'codex login'
  det -             'gemini --help'
  det -             'goose up'
  det -             '/usr/local/bin/hermes app.js'
  det -             'node server.js'
  det -             'node /Users/me/proj/codex/server.js'
  det -             'python3 /Users/me/claude_notes.py'
  det -             'grep -r claude .'
  det -             'tail -f /tmp/claude.log'
  det -             'sh -c exec t3-claude claude --output-format stream-json'
  det -             'vim claude.md'
  det claude        'claude -p write a helper script for the build'
  det -             '/Applications/Foo.app/Contents/MacOS/Foo Helper (Renderer) --type=renderer'
  det -             '/usr/bin/ssh claude-box'
  # 1b2) what counts as a build or test: compilers and test runners yes, long-running watchers and dev servers no
  bld() { # 1 = counted as a build, 0 = not; command line
    local want=$1 cmd=$2 got
    procs() { printf '5000 1 S 0.0 1000 01:00:00 00:00.10 %s\n' "$cmd"; }
    INSTANT=0; got=$(scan | awk -F'\t' '$1 == "BLIST" { n++ } END { print n + 0 }'); INSTANT=1
    chk "build? ${cmd:0:56}" "$got" "$want"
  }
  bld 1 'xcodebuild -scheme Yare build'
  bld 1 'swift-build --build-tests'
  bld 1 'swiftpm-testing-helper --test-bundle-path x'
  bld 1 '/usr/bin/clang -c a.c'
  bld 1 'node /x/node_modules/.bin/tsc -p .'
  bld 1 'vite build'
  bld 1 'python3 -m pytest tests'
  bld 1 'cargo test --release'
  bld 1 'go test ./...'
  bld 1 'next build'
  bld 0 'vite --host'
  bld 0 'vite dev'
  bld 0 'node /x/node_modules/.bin/webpack serve'
  bld 0 'tsc --watch'
  bld 0 'cargo run --bin server'
  bld 0 'jest --watch'
  bld 0 'next dev'
  bld 0 'node server.js'
  bld 0 'go run main.go'
  # 1b2b) which app or program a session runs in, and how sessions are numbered
  hostchk() { # expected host; the fixture is on stdin (pid ppid state cpu rss etime time command)
    local want=$1 fx got; fx=$(cat)
    procs() { printf '%s\n' "$fx"; }
    INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" { print $15; exit }'); INSTANT=1
    chk "host: $want" "${got:--}" "$want"
  }
  hostchk tmux <<'EOF3'
20 1 S 0.0 1000 02:00:00 00:00.10 tmux: server
21 20 S 0.0 1000 02:00:00 00:00.10 -zsh
22 21 S 0.0 9000 02:00:00 00:01.00 claude
EOF3
  hostchk "VS Code" <<'EOF3'
30 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Visual Studio Code.app/Contents/MacOS/Electron
31 30 S 0.0 1000 02:00:00 00:00.10 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin) --type=utility
32 31 S 0.0 1000 02:00:00 00:00.10 /bin/zsh -l
33 32 S 0.0 9000 02:00:00 00:01.00 claude
EOF3
  hostchk ssh <<'EOF3'
40 1 S 0.0 1000 02:00:00 00:00.10 sshd-session: me [priv]
41 40 S 0.0 1000 02:00:00 00:00.10 -zsh
42 41 S 0.0 9000 02:00:00 00:01.00 codex
EOF3
  hostchk JetBrains <<'EOF3'
50 1 S 0.0 1000 02:00:00 00:00.10 /Applications/IntelliJ IDEA.app/Contents/MacOS/idea
51 50 S 0.0 1000 02:00:00 00:00.10 -zsh
52 51 S 0.0 9000 02:00:00 00:01.00 claude
EOF3
  hostchk Nimbalyst <<'EOF3'
60 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Nimbalyst.app/Contents/MacOS/Nimbalyst
61 60 S 0.0 9000 02:00:00 00:01.00 claude
EOF3
  hostchk Codex <<'EOF3'
80 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Codex.app/Contents/MacOS/Codex
81 80 S 0.0 9000 02:00:00 00:01.00 /Applications/Codex.app/Contents/Resources/codex app-server --listen stdio
EOF3
  hostchk Claude <<'EOF3'
82 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Claude.app/Contents/MacOS/Claude
83 82 S 0.0 1000 02:00:00 00:00.10 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility
84 82 S 0.0 9000 02:00:00 00:01.00 /Users/me/Library/Application Support/Claude/claude-code/2.1.317/91184d3d9ba3/claude.app/Contents/MacOS/claude --output-format stream-json
EOF3
  hostchk "Provider" <<'EOF3'
85 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Provider.app/Contents/MacOS/Provider
86 85 S 0.0 9000 02:00:00 00:01.00 claude
EOF3
  hostchk Zed <<'EOF3'
87 1 S 0.0 1000 02:00:00 00:00.10 /Applications/Zed.app/Contents/MacOS/zed
88 87 S 0.0 1000 02:00:00 00:00.10 /bin/zsh -l
89 88 S 0.0 9000 02:00:00 00:01.00 gemini
EOF3
  hostchk background <<'EOF3'
70 1 S 0.0 9000 02:00:00 00:01.00 claude -p run the nightly job
EOF3
  # real process shapes recorded on a Mac (npm installs launched for 7 seconds): Cline runs a hidden native binary and a hub daemon below its node wrapper
  procs() { printf '%s\n' '47283 1 Ss+ 0.0 46976 00:07 0:00.06 node /tmp/live/cline/node_modules/cline/bin/cline' \
    '47284 47283 S+ 5.6 312192 00:07 0:00.95 /tmp/live/cline/node_modules/cline/bin/.cline' \
    '47331 47284 Ss 0.3 229312 00:04 0:00.51 /tmp/live/cline/node_modules/cline/bin/.cline --cline-hub-daemon --cwd /tmp/work' \
    '48315 1 Ss+ 0.0 54528 00:07 0:00.06 node /tmp/live/jules/node_modules/.bin/jules' \
    '48316 48315 S+ 0.0 29744 00:07 0:00.07 /tmp/live/jules/node_modules/@google/jules/node_modules/.bin/jules' \
    '48505 1 Ss+ 0.1 87792 00:08 0:00.21 /tmp/live/grok/node_modules/.bin/grok'; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" { printf "%s:%d\n", $2, $5 }' | sort | tr '\n' ' '); INSTANT=1
  chk "real Cline (3 processes), Jules (2) and Grok (1) shapes are one session each" "$got" "cline#1:3 grok#1:1 jules#1:2 "
  # the Hermes gateway seen on a real Mac (osascript wrapper, then two python processes): a service, not a session
  procs() { printf '%s\n' '1163 1 S 0.0 3000 05:57:23 0:00.06 /usr/bin/osascript -l JavaScript -e exec /Users/me/.hermes/hermes-agent/.hermes/bin/hermes --run-module hermes_cli.stderr_timestamp -- /Users/me/.hermes/hermes-agent/.hermes/bin/hermes gateway run --external-supervisor' \
    '1452 1163 S 0.0 14000 05:57:20 0:11.71 /Users/me/.hermes/tools/py/bin/python3 -I -c import sys\012sys.path.insert(0, /Users/me/.hermes/hermes-agent)\012from hermes_cli.main import main\012 --run-module hermes_cli.stderr_timestamp -- hermes gateway run --external-supervisor' \
    '2067 1452 S 0.3 99000 05:57:15 5:13.24 /Users/me/.hermes/tools/py/bin/python3 -I -c import sys\012sys.path.insert(0, /Users/me/.hermes/hermes-agent)\012from hermes_cli.main import main\012 gateway run --external-supervisor'; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" { s++ } $1 == "SVC" { v++; m += $5 } END { printf "%d sessions %d service %d MB", s, v, m }'); INSTANT=1
  chk "an idle Hermes gateway is listed as a service, not counted as a session" "$got" "0 sessions 1 service 110 MB"
  # agents the doctor does not know: listed once, never counted as sessions; YARE_DOCTOR_AGENTS adds one by name
  unk() { # fixture on stdin -> "UNK names" found
    local fx; fx=$(cat); procs() { printf '%s\n' "$fx"; }
    INSTANT=0; got=$(scan | awk -F'\t' '$1 == "UNK" { printf "%s ", $2 } $1 == "SESS" { printf "session:%s ", $2 }'); INSTANT=1; echo "${got:-none}"
  }
  chk "an unknown agent that starts MCP servers is listed" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 /opt/newagent/bin/newagent --resume
101 100 S 0.0 9000 02:00:00 00:01.00 npm exec some-mcp-server@latest
102 101 S 0.0 9000 02:00:00 00:01.00 node /x/some-mcp-server
EOF3
)" "newagent "
  chk "an unknown agent with agent-style flags is listed" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 /opt/newagent2/bin/newagent2 --output-format stream-json --verbose
EOF3
)" "newagent2 "
  chk "MCP servers under a desktop app are not an unknown agent" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 /Applications/Some Editor.app/Contents/MacOS/Some Editor
101 100 S 0.0 9000 02:00:00 00:01.00 node /x/some-mcp-server
EOF3
)" none
  chk "an MCP server started by hand in a terminal is not an unknown agent" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 /usr/bin/login -fp me
101 100 S 0.0 9000 02:00:00 00:01.00 -zsh
102 101 S 0.0 9000 02:00:00 00:01.00 node /x/some-mcp-server
EOF3
)" none
  chk "MCP servers under a known agent are not an unknown agent" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 claude --resume
101 100 S 0.0 9000 02:00:00 00:01.00 npm exec some-mcp-server@latest
102 101 S 0.0 9000 02:00:00 00:01.00 node /x/some-mcp-server
EOF3
)" "session:claude#1 "
  chk "a plain program with no MCP servers is not an unknown agent" "$(unk <<'EOF3'
100 1 S 0.0 9000 02:00:00 00:01.00 node /Users/me/app/server.js
EOF3
)" none
  procs() { printf '%s\n' '100 1 S 0.0 9000 02:00:00 00:01.00 /opt/newagent/bin/newagent --resume'; }
  INSTANT=0; got=$(YARE_DOCTOR_AGENTS="NewAgent, other" scan | awk -F'\t' '$1 == "SESS" { printf "%s", $2 }'); INSTANT=1
  chk "YARE_DOCTOR_AGENTS adds an agent by name" "$got" "newagent#1"
  # a high load average with a quiet CPU (a Mac right after a restart, busy indexing) is a note, not an "overloaded" warning
  procs() { printf '%s\n' '100 1 S 0.0 9000 02:00:00 00:01.00 claude --resume'; }
  local save_cores=$CORES save_fixture=$FIXTURE; CORES=12; FIXTURE=1
  load1() { echo 15.58; }
  INSTANT=0; prepare; INSTANT=1
  chk "high load with a quiet CPU is noted, not called overloaded" "$(printf '%s' "$NOTES" | grep -c 'load average is high')$(printf '%s' "$NOTES" | grep -c 'is overloaded')" 10
  procs() { printf '%s\n' '100 1 S 0.0 9000 02:00:00 00:01.00 claude --resume' '101 100 R 700.0 9000 02:00:00 20:00.00 clang -c big.c'; }
  INSTANT=0; prepare; INSTANT=1
  chk "high load with a busy CPU is called overloaded" "$(printf '%s' "$NOTES" | grep -c 'is overloaded')" 1
  CORES=$save_cores; FIXTURE=$save_fixture; load1() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }
  # a capture replayed with --from detects the same agents, and its masking leaves no secret behind
  local capf; capf=$(mktemp)
  printf '%s\n' '10 1 S 0.0 1000 02:00:00 00:00.10 /usr/local/bin/node --max-old-space-size=8192 /Users/me/SECRETPROJ/node_modules/@google/gemini-cli/dist/index.js --token=hunter2' \
    '11 1 S 0.0 1000 02:00:00 00:00.10 /Users/me/.hermes/tools/py/bin/python3 -I -c import sys\012sys.path.insert(0, /Users/me/.hermes/hermes-agent)' \
    '12 1 S 0.0 1000 02:00:00 00:00.10 psql postgres://user:hunter2@db.internal/prod' '13 1 S 0.0 1000 02:00:00 00:00.10 /Users/me/.local/bin/claude -p summarize SECRETPROJ' > "$capf"
  procs() { cat "$capf"; }
  capture_mode > "$capf.cap"
  chk "--capture drops private words (secrets, project names)" "$(cut -d' ' -f8- "$capf.cap" | grep -c 'hunter2\|SECRETPROJ')" 0
  procs() { cat "$capf.cap"; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" { n++ } END { print n + 0 }'); INSTANT=1
  chk "a capture replayed with --from finds the same sessions" "$got" 3
  rm -f "$capf" "$capf.cap"
  procs() { printf '%s\n' '900 1 S 0.0 9000 01:00:00 00:01.00 claude' '50 1 S 0.0 9000 05:00 00:01.00 claude'; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" && $2 == "claude#1" { print $3 }'); INSTANT=1
  chk "oldest session is #1 even with a higher pid" "$got" 900
  # 1b2c) CPU is measured from two snapshots of cumulative CPU time, not read from ps's lagging average
  first_snapshot() { printf '5000 00:05.00\n'; }
  procs() { printf '5000 1 S 0.0 1000 01:00:00 00:10.00 /usr/local/bin/claude\n'; }
  SAMPLE_GAP=0.5; got=$(scan | awk -F'\t' '$1 == "TOT" { printf "%d", $4 }'); SAMPLE_GAP=0.7
  chk "measured CPU uses the time delta (5 CPU-seconds in about 0.5 s)" "$([ "${got:-0}" -ge 400 ] && echo ok || echo "only $got")" ok
  first_snapshot() { ps -axo pid=,time= 2>/dev/null; }
  # 1b2g) garbage in, no crash out: odd lines, cycles, duplicates, empty commands, huge arguments, control characters
  local fz; fz=$(mktemp)
  {
    printf '%s\n' '1 1 S 0.0 100 00:01 00:00.01 launchd' '5 6 S 0.0 100 00:01 00:00.01 claude' '6 5 S 0.0 100 00:01 00:00.01 claude' '7 7 S 0.0 100 00:01 00:00.01 codex' '8 1 Z 0.0 0 00:01 00:00.00' '9 1 S x y z w v u claude' '10 1 S 0.0 100 00:01 00:00.01' '11 1 S 9999.9 99999999999 99-23:59:59 999:59:59.99 claude -p'
    printf '12 1 S 1.0 100 00:05 00:00.01 claude %s\n' "$(printf 'x%.0s' $(seq 1 3000))"
    printf '13 1 S 1.0 100 00:05 00:00.01 /Applications/日本語.app/Contents/MacOS/日本語 --type=renderer\n'
    printf '14 1 S 1.0 100 00:05 00:00.01 node /x/ünïcödé/gemini\n'
    printf '15 1 S 1.0 100 00:05 00:00.01 claude \001\002 \t tab\n'
    printf '5 1 S 1.0 100 00:05 00:00.01 claude duplicate pid\n'
    awk 'BEGIN { srand(7); for (i = 0; i < 400; i++) { printf "%d %d %s %.1f %d %02d:%02d %d:%02d.%02d %s\n", 100 + i, int(rand() * 500), (rand() < .1 ? "T" : "S"), rand() * 120, int(rand() * 1e6), int(rand() * 59), int(rand() * 59), int(rand() * 99), int(rand() * 59), int(rand() * 99), (rand() < .3 ? "claude -p job" : (rand() < .5 ? "node /x/mcp.js" : "/usr/bin/clang -c f.c")) } }'
  } > "$fz"
  local fzout; fzout=$(INSTANT=0 bash "${BASH_SOURCE[0]}" --from "$fz" --json --no-color 2>&1); local fzrc=$?
  chk "garbage process lines do not crash the scan (exit code)" "$fzrc" 0
  chk "garbage process lines give valid JSON and no awk errors" "$(echo "$fzout" | grep -c 'awk:\|unbound\|syntax error')$(echo "$fzout" | head -1 | cut -c1-1)" "0{"
  chk "the full report survives garbage too" "$(bash "${BASH_SOURCE[0]}" --from "$fz" --no-color 2>&1 | grep -cE 'awk:|unbound|syntax error|command not found')" 0
  find "$fz" -delete
  # 1b2h) a big machine: 6,000 processes must not take long
  local big t0 t1; big=$(mktemp)
  awk 'BEGIN { srand(3); print "1 0 S 0.0 100 10:00:00 0:01.00 launchd"; print "2 1 S 0.0 9000 05:00:00 0:01.00 -zsh"; print "3 2 S 0.0 90000 05:00:00 0:20.00 claude"; for (i = 10; i < 6010; i++) printf "%d %d S %.1f %d 02:00:00 0:%02d.00 %s\n", i, (i % 3 == 0 ? 3 : 1 + int(rand() * 30)), rand() * 3, int(rand() * 50000), int(rand() * 59), (i % 5 == 0 ? "node /x/mcp-server.js" : "/usr/bin/worker --id " i) }' > "$big"
  t0=$(date +%s); bash "${BASH_SOURCE[0]}" --from "$big" --json --no-color >/dev/null 2>&1; t1=$(date +%s)
  chk "6,000 processes are analysed in under 15 seconds" "$([ $((t1 - t0)) -le 15 ] && echo ok || echo "took $((t1 - t0))s")" ok
  find "$big" -delete
  # 1b2f) names with accents or CJK characters are cut on a character boundary and padded by characters
  chk "a long CJK name is cut into valid UTF-8" "$(uawk "$AWKLIB"'BEGIN { printf "%s", fit("日本語フォルダ名", 5) }' | iconv -f UTF-8 -t UTF-8 2>&1 | head -c 40)" "日本語フ$ELL"
  chk "padding counts characters, not bytes" "$(uawk "$AWKLIB"'BEGIN { printf "%s|", pad("日本語", 5) }')" "日本語  |"
  chk "an accented name that fits is left alone" "$(uawk "$AWKLIB"'BEGIN { printf "%s|", pad("café-é", 8) }')" "café-é  |"
  chk "ASCII is unchanged" "$(uawk "$AWKLIB"'BEGIN { printf "%s|", pad("abcdefghij", 6) }')" "abcde$ELL|"
  # 1b2e) an agent running detached for days (a gateway or a nightly job) is deliberate: not "looks forgotten"
  procs() { printf '%s\n' '80 1 S 0.0 9000 3-02:00:00 00:01.00 claude -p watch the inbox' '81 10 S 0.0 9000 3-02:00:00 00:01.00 claude --resume' '10 2 S 0.0 9000 3-02:00:00 00:01.00 -zsh' '2 1 S 0.0 9000 3-02:00:00 00:01.00 /Applications/iTerm.app/Contents/MacOS/iTerm2'; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "SESS" { printf "%s=%s;", $3, $12 }'); INSTANT=1
  chk "detached agent is not 'forgotten', an attached idle one is" "$got" "80=0;81=1;"
  # 1b2d) leftovers: orphaned helpers and headless browsers yes; an agent run in the background, or a service, no
  left() { # expected count; the fixture is on stdin
    local want=$1 fx n; fx=$(cat)
    procs() { printf '%s\n' "$fx"; }
    INSTANT=0; n=$(scan | awk -F'\t' '$1 == "LEFT" { n++ } END { print n + 0 }'); INSTANT=1
    chk "leftovers: expect $want" "$n" "$want"
  }
  left 1 <<'EOF3'
300 1 S 0.0 40000 01:00:00 00:00.10 node /w/mcp-leftover.js
EOF3
  left 1 <<'EOF3'
301 1 S 0.0 90000 01:00:00 00:00.10 /x/Google Chrome for Testing --headless --remote-debugging-port=9222
EOF3
  left 1 <<'EOF3'
302 1 S 0.0 90000 01:00:00 00:00.10 node /w/node_modules/.bin/next dev
EOF3
  left 0 <<'EOF3'
303 1 S 0.0 90000 02:00:00 00:01.00 node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js -p nightly job
EOF3
  left 0 <<'EOF3'
304 1 S 0.0 90000 02:00:00 00:01.00 /opt/homebrew/bin/caddy run
305 1 S 0.0 90000 02:00:00 00:01.00 /Users/me/.hermes/hermes-agent/.hermes/bin/hermes --run-module cli
EOF3
  left 0 <<'EOF3'
306 1 S 0.0 40000 00:10:00 00:00.10 node /w/mcp-recent.js
EOF3
  # 1b3) the git branch of a session folder comes from .git/HEAD (a plain checkout, a detached HEAD, a worktree), without running git
  local gtmp; gtmp=$(mktemp -d)
  mkdir -p "$gtmp/repo/.git" "$gtmp/repo/src/deep" "$gtmp/wt" "$gtmp/repo/.git/worktrees/wt" "$gtmp/plain"
  echo "ref: refs/heads/feature/x" > "$gtmp/repo/.git/HEAD"
  echo "ref: refs/heads/other" > "$gtmp/repo/.git/worktrees/wt/HEAD"
  echo "gitdir: $gtmp/repo/.git/worktrees/wt" > "$gtmp/wt/.git"
  chk "git branch of a checkout" "$(git_branch "$gtmp/repo")" "feature/x"
  chk "git branch from a sub folder" "$(git_branch "$gtmp/repo/src/deep")" "feature/x"
  chk "git branch of a worktree" "$(git_branch "$gtmp/wt")" "other"
  chk "no branch outside a repo" "$(git_branch "$gtmp/plain")" ""
  echo "0123456789abcdef0123456789abcdef01234567" > "$gtmp/repo/.git/HEAD"
  chk "detached HEAD shows a short commit" "$(git_branch "$gtmp/repo")" "0123456"
  find "$gtmp" -depth -delete
  # 1b4) the other modes produce what they promise (on a made-up process list)
  procs() { cat <<'EOF2'
10 1 S 0.5 90000 05:00:00 00:30.00 /Applications/iTerm.app/Contents/MacOS/iTerm2
100 10 S 1.0 100000 02:00:00 00:10.00 /usr/local/bin/claude --resume
104 100 S 5.0 20000 01:00 00:02.00 /usr/bin/clang -c a.c
300 1 S 0.0 40000 01:00:00 00:00.10 node /w/mcp-leftover.js
EOF2
  }
  chk "--prom has the session metric" "$( (COLOR=0; prom_mode) 2>/dev/null | grep -c '^yare_doctor_session_memory_bytes{session="claude#1"')" 1
  chk "--cleanup suggests the leftover" "$( (cleanup_mode) 2>/dev/null | grep -c 'kill 300')" 1
  chk "--tree shows the clang under claude#1" "$( (WANT_TREE=1; tree_mode) 2>/dev/null | grep -c 'clang')" 1
  local cap; cap=$(mktemp)
  printf '%s\n' '10 1 S 0.5 90000 05:00:00 0:30.00 /Applications/iTerm.app/Contents/MacOS/iTerm2' '100 10 S 1.0 100000 02:00:00 0:10.00 claude --resume' '101 100 S 0.0 9000 01:30:00 0:00.10 node /x/mcp-server.js' > "$cap"
  local one2; one2=$(mktemp); printf '4001 1 S 0.0 9000 02:00:00 00:01.00 /Users/me/.local/bin/claude --resume\n' > "$one2"
  chk "--json lists each session with its agent and pid" "$(bash "${BASH_SOURCE[0]}" --from "$one2" --json 2>/dev/null | grep -o '"agent":"claude","pid":4001')" '"agent":"claude","pid":4001'
  local mk; mk=$(mktemp); printf '%s\n' '5000 1 S 0.0 9000 02:00:00 00:01.00 claude --resume' '5001 5000 S 0.0 9000 02:00:00 00:01.00 <b>hello&amp;' > "$mk"
  chk "--html escapes markup in process names" "$(bash "${BASH_SOURCE[0]}" --from "$mk" --html --tree 2>/dev/null | grep -c '&lt;b&gt;hello&amp;amp;')" 1
  rm -f "$mk"
  chk "--html is a complete page" "$(bash "${BASH_SOURCE[0]}" --from "$one2" --html 2>/dev/null | grep -c '</html>')" 1
  chk "--snippet launchd prints a plist" "$(bash "${BASH_SOURCE[0]}" --snippet launchd 2>/dev/null | grep -c '<key>StartInterval</key>')" 1
  chk "--snippet with an unknown kind fails" "$(bash "${BASH_SOURCE[0]}" --snippet nope >/dev/null 2>&1; echo $?)" 2
  local tw; for tw in 80 100 110; do
    chk "sessions table: header and rows are the same width at $tw columns" "$(COLUMNS=$tw bash "${BASH_SOURCE[0]}" --from "$one2" --sessions --ascii --no-color 2>/dev/null | awk '/^    SESSION/ { h = length($0) } /^  [^ ] claude#1/ { r = length($0) } END { print (h == r && h > 0) ? "same" : "differs " h " " r }')" same
  done
  chk "piped, plain yare-doctor prints the report and never opens the tabbed screen" "$(bash "${BASH_SOURCE[0]}" --from "$one2" --tabs 2>&1 | grep -c 'AGENT SESSIONS')$(bash "${BASH_SOURCE[0]}" --from "$one2" --tabs 2>&1 | grep -c $'\033\\[?1049h')" 10
  chk "the word plain works like --plain" "$(bash "${BASH_SOURCE[0]}" --from "$one2" plain --no-color 2>&1 | grep -c 'AGENT SESSIONS')" 1
  chk "--sessions shows only the sessions table" "$(bash "${BASH_SOURCE[0]}" --from "$one2" --sessions --no-color 2>/dev/null | grep -c 'claude#1')" 1
  chk "--installed runs and never launches an agent" "$(bash "${BASH_SOURCE[0]}" --from "$one2" --installed --no-color 2>&1 | grep -c 'CODING AGENTS FOUND')" 1
  rm -f "$one2"
  chk "--from replays a saved process list" "$(bash "${BASH_SOURCE[0]}" --from "$cap" --json 2>/dev/null | grep -o '"agent_sessions":[0-9]*')" '"agent_sessions":1'
  find "$cap" -delete
  chk "--capture trims commands and keeps the process list" "$(bash "${BASH_SOURCE[0]}" --capture | awk 'END { print (NR > 20 ? "ok" : "short") }')" ok
  chk "--capture hides =values and the home folder" "$(bash "${BASH_SOURCE[0]}" --capture | grep -c "$HOME")" 0
  UN_PTS=50; ALL_CPU=200; AG_MB=3072; MEM_GB=36
  chk "agents' share of CPU and memory" "$(blame)" "25 8"
  local ca cb; ca=$(mktemp); cb=$(mktemp)
  printf '%s\n' '{"agent_sessions":2,"agent_memory_mb":900,"health_score":86,"findings":[{"level":"look","text":"3 helpers are left over"},{"level":"look","text":"Looks forgotten: codex#1"}]}' > "$ca"
  printf '%s\n' '{"agent_sessions":3,"agent_memory_mb":500,"health_score":100,"findings":[{"level":"look","text":"7 helpers are left over"},{"level":"look","text":"A new thing appeared"}]}' > "$cb"
  CMP_A=$ca; CMP_B=$cb
  chk "--compare shows memory going down" "$( (compare_mode) 2>/dev/null | grep -c 'agent memory mb.*down 400')" 1
  chk "--compare ignores changed numbers in a finding" "$( (compare_mode) 2>/dev/null | grep -c 'helpers are left over')" 0
  chk "--compare reports a gone and a new finding" "$( (compare_mode) 2>/dev/null | grep -cE 'gone  Looks forgotten|new   A new thing')" 2
  find "$ca" "$cb" -delete
  chk "--zoo names the animal (a small quiet session is a mouse)" "$( (INSTANT=0; zoo_mode) 2>/dev/null | grep -c 'Mouse')" 1
  chk "runs with an empty environment (cron, launchd): no HOME, no PATH" "$(env -i /bin/bash "${BASH_SOURCE[0]}" --check --no-color 2>&1 | grep -ciE 'unbound|command not found|syntax error')" 0
  chk "--completions bash" "$( (COMPL_SHELL=bash; completions_mode) | grep -c 'complete -F')" 1
  chk "--completions zsh" "$( (COMPL_SHELL=zsh; completions_mode) | grep -c compdef)" 1
  procs() { real_procs; }
  # 1b5a) waiting for a person; program versions from install paths
  procs() { printf '%s\n' '10 1 S 0.0 9000 01:00:00 00:01.00 claude' '11 10 S 0.0 900 07:00 00:00.01 sudo -S npm install -g foo' '12 10 S 0.0 900 00:20 00:00.01 sudo ls' '13 10 S 5.0 900 07:00 00:00.01 sudo make install'; }
  INSTANT=0; got=$(scan | awk -F'\t' '$1 == "WAIT" { printf "%s;", $2 }'); INSTANT=1
  chk "a sudo waiting for 7 minutes is reported; a fresh or busy one is not" "$got" "11;"
  chk "program version from an install path" "$(printf 'p10\nn/Users/me/.local/share/claude/versions/2.1.319\nn/usr/lib/x.dylib\np11\nn/opt/homebrew/bin/node\np12\nn/Users/me/.codex/releases/0.166.0-aarch64/bin/codex\n' | parse_versions | tr '\t\n' ' ')" "10 2.1.319 12 0.166.0-aarch64 "
  SCAN=$(printf 'SESS\tclaude#1\t10\nSESS\tclaude#2\t20\nSESS\tclaude#3\t30\nSESS\tcodex#1\t40\n'); VERSIONS=$(printf '10\t2.1.319\n20\t2.1.300\n30\t2.1.319\n40\t0.166.0\n')
  chk "two claude versions at once are reported, one codex version is not" "$(versions_report)" "claude 2.1.319 (claude#1), 2.1.300 (claude#2)"
  procs() { real_procs; }
  # 1b5) stale git locks are found only when no git command is running and the file is old enough; network is added up per session
  local ltmp; ltmp=$(mktemp -d)
  mkdir -p "$ltmp/r/.git" "$ltmp/r/src"
  echo "ref: refs/heads/main" > "$ltmp/r/.git/HEAD"
  : > "$ltmp/r/.git/index.lock"; touch -t 202001010000 "$ltmp/r/.git/index.lock"
  : > "$ltmp/r/.git/HEAD.lock"
  FIXTURE=0; FOLDERS=$(printf '123\t%s\n' "$ltmp/r/src")
  git_running() { return 1; }
  chk "an old index.lock is reported" "$(git_locks | cut -f1 | sed "s#^$ltmp##")" "/r/.git/index.lock"
  chk "a fresh lock is not reported" "$(git_locks | wc -l | tr -d ' ')" 1
  git_running() { return 0; }
  chk "an old lock is still reported while git runs elsewhere" "$(git_locks | wc -l | tr -d ' ')" 1
  : > "$ltmp/r/.git/shallow.lock"; touch -t "$(date -v-5M +%Y%m%d%H%M)" "$ltmp/r/.git/shallow.lock"
  rm "$ltmp/r/.git/index.lock"
  chk "a 5-minute-old lock is not reported while git runs, and is when git is idle" "$(git_locks | wc -l | tr -d ' ')$(git_running() { return 1; }; git_locks | wc -l | tr -d ' ')" 01
  git_running() { pgrep -x git >/dev/null 2>&1; }
  find "$ltmp" -depth -delete
  FOLDERS=""
  SCAN=$(printf 'MAP\t10\tclaude#1\nMAP\t11\tclaude#1\nMAP\t12\tcodex#1\nMAP\t13\tleftover\n')
  NET=$(printf '10\t100\t50\n11\t200\t0\n12\t7\t8\n13\t999\t999\n99\t5\t5\n')
  chk "network is added up per session" "$(net_by_session | sort | tr '\t\n' ' ')" "claude#1 300 50 codex#1 7 8 "
  # 1b6) a session starting processes at a runaway rate is flagged
  SCAN=$(printf 'SESS\tcodex#1\t100\t1h\t3\t1.0\t100\t1\t0\t0\t0\t0\t0\t0\t-\t5\t310\t-\t3600\nSESS\tclaude#1\t200\t1h\t3\t1.0\t100\t1\t0\t0\t0\t0\t0\t0\t-\t5\t12\t-\t3600\n')
  chk "a spawn storm is reported, a calm session is not" "$(storms | cut -f1 | tr '\n' ';')" "codex#1;"
  # 1c) two sessions building in one folder are reported; one building, or two in different folders, are not
  SCAN=$(printf 'SESS\tclaude#1\t100\t1h\t3\t1.0\t100\t1\t0\t0\t1\t0\t0\t0\t-\t5\t0\t-\nSESS\tcodex#1\t200\t1h\t3\t1.0\t100\t1\t0\t0\t2\t0\t0\t0\t-\t5\t0\t-\nSESS\tgemini#1\t300\t1h\t3\t1.0\t100\t1\t0\t0\t1\t0\t0\t0\t-\t5\t0\t-\n')
  FOLDERS=$(printf '100\t/w/app\n200\t/w/app\n300\t/w/other\n')
  chk "two sessions building in one folder" "$(collisions)" "$(printf 'app\tclaude#1 and codex#1')"
  FOLDERS=$(printf '100\t/w/app\n200\t/w/elsewhere\n300\t/w/other\n')
  chk "different folders do not collide" "$(collisions)" ""
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
  chk "open-port listing works (lsof exits 1 when nothing is listening, which is fine)" "$(lsof -nP -iTCP -sTCP:LISTEN >/dev/null 2>&1; rc=$?; [ "$rc" -le 1 ] && echo 0 || echo "$rc")" 0
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

# ---- one number for "how is this Mac doing, because of the agents" ----
# Start at 100; every "act on it" finding costs 20 points, every "worth a look" finding 7. A to F is 90 / 80 / 70 / 55.
# It is a summary of the findings above it, not a benchmark: the list of findings is the real answer.
health_calc() {
  local n1 n2
  n1=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 1' | wc -l | tr -d ' ')
  n2=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 2' | wc -l | tr -d ' ')
  HSCORE=$(( 100 - 20 * n1 - 7 * n2 )); if (( HSCORE < 0 )); then HSCORE=0; fi
  if (( HSCORE >= 90 )); then HGRADE=A; elif (( HSCORE >= 80 )); then HGRADE=B; elif (( HSCORE >= 70 )); then HGRADE=C; elif (( HSCORE >= 55 )); then HGRADE=D; else HGRADE=F; fi
  # memory you would get back by closing sessions that look forgotten and the helpers they left behind
  RECLAIM_MB=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $12 == 1 { s += $7 } $1 == "LEFT" { s += $4 } END { printf "%d", s }')
}

prepare() { SCAN=$(scan); gather; stand_out; health_calc; }

# limits the user sets with --limit-mem MB, --limit-cpu PERCENT_OF_ONE_CORE, --limit-sessions N (0 = no limit)
over_budget() { # prints one line per limit that is exceeded
  if (( LIMIT_MEM > 0 )) && (( AG_MB > LIMIT_MEM )); then echo "agent sessions hold ${AG_MB} MB, over the limit of ${LIMIT_MEM} MB"; fi
  if (( LIMIT_CPU > 0 )) && awk -v a="$UN_PTS" -v l="$LIMIT_CPU" 'BEGIN { exit !(a > l) }'; then echo "agents and their apps use $(awk -v a="$UN_PTS" 'BEGIN { printf "%.0f", a }')% of a core, over the limit of ${LIMIT_CPU}%"; fi
  if (( LIMIT_SESS > 0 )) && (( SESS_N > LIMIT_SESS )); then echo "${SESS_N} agent sessions are open, over the limit of ${LIMIT_SESS}"; fi
}

# a short, deterministic-per-state one-liner for --vibe and --card
vibe() {
  local n1 n2 f="" pick over=0
  n1=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 1' | wc -l | tr -d ' ')
  n2=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 2' | wc -l | tr -d ' ')
  f=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $12 == 1 { print $2; exit }')
  if awk -v l="${LOAD:-0}" -v c="$CORES" 'BEGIN { exit !(l / c >= 1.0) }'; then over=1; fi
  local calm=("Everything is humming. Go touch grass." "Calm seas. Your agents are behaving." "Nothing to see here, and that is the point." "A tidy Mac. Somebody is doing their dishes.")
  local none=("No agents running. Your Mac is enjoying the quiet." "Zero agents. Zero problems. Suspicious, but nice." "Silence. Even the fans are taking a break.")
  local busy=("Your Mac is sweating, but it is not the agents. Look at the top CPU user." "Fans spinning? Do not blame the agents this time." "Overloaded, and the agents are innocent. Rare.")
  if (( n1 > 0 )); then echo "Something needs you. Scroll up. Sorry."
  elif [ -n "$f" ]; then echo "$f has been open for ages and is doing nothing. Say goodbye."
  elif (( over )); then pick=$(( RANDOM % ${#busy[@]} )); echo "${busy[$pick]}"
  elif (( n2 > 0 )); then echo "Mostly fine. A couple of things are worth a look."
  elif (( SESS_N == 0 )); then pick=$(( RANDOM % ${#none[@]} )); echo "${none[$pick]}"
  else pick=$(( RANDOM % ${#calm[@]} )); echo "${calm[$pick]}"; fi
}

# ---- --capture: the process list with arguments trimmed, to attach to a bug report or replay with --from FILE ----
# Keeps pid, parent, state, CPU, memory, times and the first four words of each command. Your home folder becomes ~, any
# word containing "=" becomes <arg>, long words are cut. Read it before you share it; nothing is sent anywhere.
capture_mode() {
  # Every command line is kept in shape (so --from FILE detects the same sessions) but anything that could be private is masked:
  # words that are not a known agent, subcommand or ordinary system folder become <arg> or _, and flag values are dropped.
  procs | awk -v home="$HOME" '
  function safeseg(s,   l) {
    sub(/@[^\/@]*$/, "", s); l = tolower(s)
    if (s == "" || s == "~" || s == "." || s == "..") return 1
    if (l ~ /^v?[0-9]+(\.[0-9a-z]+)+(-[a-z0-9.]+)?$/) return 1
    if (l ~ /\.app$/) return 1
    if (l ~ /^(usr|local|bin|sbin|lib|lib64|libexec|opt|homebrew|cellar|node_modules|applications|library|system|private|var|tmp|share|versions|releases|dist|contents|macos|resources|frameworks|venv|site-packages|node|nodejs|npm|npx|bun|uv|tools|packages|plugins|cache|vendor|current|latest|stable|extensions|helpers|helper|app|build|index|cli|main|bin\.js|index\.js|cli\.js|main\.js|cli\.mjs|index\.mjs|aarch64-apple-darwin|x86_64-apple-darwin|python[0-9.]*|application|support|nvm|asdf|pyenv|volta|fnm|deno|cargo|mise|n|pnpm|yarn)$/) return 1
    if (l ~ /^\.(local|nvm|npm|npm-global|bun|cargo|claude|codex|hermes|opencode|continue|config|cache|volta|asdf|pyenv|fnm|deno|cursor|bin|kilocode|augment|qwen|factory|goose|amp|gemini|aider|kimi|copilot|kiro|cline|crush|plandex|openhands|devin|npm-packages|yarn|pnpm)$/) return 1
    if (l ~ /^@(anthropic-ai|openai|google|github|sourcegraph|qwen-code|augmentcode|charmland|continuedev|kilocode|zed-industries|agentclientprotocol)$/) return 1
    if (l ~ /^(claude|codex|gemini|opencode|aider|cursor-agent|amp|goose|crush|droid|qwen|kiro|kiro-cli|copilot|hermes|hermes-agent|hermes_cli|auggie|cline|plandex|openhands|kimi|devin|grok|junie|jules|kilo|kilocode|continue)(-code|-cli|-agent|-ai|-chat|-sdk|-acp|-darwin-arm64|-darwin-x64|-darwin-universal)*(\.(js|mjs|cjs|exe|py))?$/) return 1
    return 0
  }
  function known(w,   l) {
    l = tolower(w)
    return (l ~ /^(claude|codex|gemini|opencode|aider|cursor-agent|amp|goose|crush|droid|qwen|kiro|kiro-cli|copilot|hermes|auggie|cline|plandex|openhands|kimi|devin|grok|junie|jules|kilo|kilocode|continue|claude-code|codex-cli|gemini-cli|qwen-code|opencode-ai|aider-chat|kimi-cli|cn|login|logout|update|upgrade|doctor|config|completion|install|uninstall|setup-token|migrate-installer|auth|plugin|plugins|mcp|version|help|session|run|web|acp|serve|app-server|daemon|pid-update-loop|exec|x|dlx|tool|resume|chat|tui|listen|stdio|start|build|test|dev|watch|install|add|remove|npm|node|bun|deno|python|python3)$/)
  }
  function sw(w,   n, p, i, o) {
    if (substr(w, 1, 1) == "-") {
      if (index(w, "=")) return substr(w, 1, index(w, "=")) "<arg>"
      if (w ~ /^--[A-Za-z0-9][A-Za-z0-9-]*$/ || w ~ /^-[A-Za-z0-9]$/) return w
      return "-<arg>"
    }
    if (index(w, "/")) {
      n = split(w, p, "/"); o = ""
      for (i = 1; i <= n; i++) o = o (i > 1 ? "/" : "") (safeseg(p[i]) ? p[i] : "_")
      return o
    }
    if (known(w)) return w
    return "<arg>"
  }
  { out = $1 " " $2 " " $3 " " $4 " " $5 " " $6 " " $7
    line = ""; for (i = 8; i <= NF; i++) line = line (i > 8 ? " " : "") $i
    gsub(home, "~", line)
    n = split(line, t, " "); cmd = ""
    for (k = 1; k <= n && k <= 12; k++) {
      w = sw(t[k])
      if (k == 1 && !index(t[k], "/") && t[k] ~ /^[A-Za-z0-9._+-]+$/) w = t[k]   # the program name itself is not private
      if (k == 1 && index(t[k], "/")) { m = split(t[k], q, "/"); sub(/\/[^\/]*$/, "", w); w = w "/" q[m] }   # the program name itself is not private
      cmd = cmd (k > 1 ? " " : "") w
    }
    if (index(line, ".hermes/hermes-agent") && !index(cmd, "hermes-agent")) cmd = cmd " ~/.hermes/hermes-agent"
    print out " " cmd }'
}

# share of the Mac that the agents (and the apps they run in) account for, as whole percents: "cpu mem"
blame() {
  awk -v u="$UN_PTS" -v a="$ALL_CPU" -v m="$AG_MB" -v g="$MEM_GB" 'BEGIN { c = (a > 0) ? 100 * u / a : 0; if (c > 100) c = 100; printf "%d %d", c, (g > 0) ? 100 * m / (g * 1024) : 0 }'
}

# ---- --slow: why the Mac may feel slow right now, and whether the agents are to blame ----
slow_mode() {
  prepare
  banner "$VERSION $MID why is it slow? $MID read-only"
  section "WHAT IS LIKELY SLOWING IT DOWN" "the most serious findings first"
  local causes; causes=$(printf '%s' "$NOTES" | awk -F'\t' '$1 <= 2' | sort -t"$TAB" -k1,1n | head -4)
  if [ -n "$causes" ]; then
    printf '%s\n' "$causes" | uawk -F'\t' "$AWKLIB"'{ n++; printf "  %s%d.%s %s\n", BLD, n, RST, paint(wrap($2, W - 8, "     ")) }'
  else
    printf '  %s%s Nothing obvious: no memory pressure, no overload, no throttling, no backup or indexing job.%s\n' "$G" "$OK" "$X"
  fi
  section "ARE THE AGENTS TO BLAME?"
  local bc bm; read -r bc bm <<< "$(blame)"
  local verdict="mostly not"
  if (( bc >= 50 || bm >= 50 )); then verdict="yes, largely"; elif (( bc >= 25 || bm >= 25 )); then verdict="partly"; fi
  uawk -v bc="$bc" -v bm="$bm" -v v="$verdict" -v ns="$SESS_N" "$AWKLIB"'BEGIN {
    printf "  %-8s %s %s%d%%%s of all CPU use is agents and the apps they run in\n", "CPU", gbar(bc / 100, 20), BLD, bc, RST
    printf "  %-8s %s %s%d%%%s of memory is held by agent sessions\n", "Memory", gbar(bm / 100, 20), BLD, bm, RST
    col = (v == "mostly not") ? GRN : (v == "partly") ? YEL : RED
    printf "\n  %s%s%s%s  with %d %s open\n", col, BLD, v, RST, ns, (ns == 1 ? "session" : "sessions")
  }'
}

# ---- --compare BEFORE.json AFTER.json: what changed between two runs ----
compare_mode() {
  banner "$VERSION $MID compare $MID read-only"
  jnum() { grep -o "\"$2\":[-0-9.]*" "$1" | head -1 | cut -d: -f2; }
  jtexts() { grep -oE '"text":"([^"\\]|\\.)*"' "$1" | sed 's/^"text":"//; s/"$//' | sort -u; }
  section "WHAT CHANGED" "left is before, right is after; green is better"
  local rows="" k
  for k in agent_sessions agent_memory_mb agent_cpu_points_one_core possible_leftovers forgotten_sessions idle_helpers idle_helper_mb ports_held health_score load_1m; do
    rows="${rows}${k}	$(jnum "$CMP_A" $k)	$(jnum "$CMP_B" $k)"$'\n'
  done
  printf '%s' "$rows" | uawk -F'\t' -v AR="$ARW" "$AWKLIB"'
    NF == 3 && $2 != "" && $3 != "" {
      d = $3 - $2; good = ($1 == "health_score") ? (d > 0) : (d < 0); bad = ($1 == "health_score") ? (d < 0) : (d > 0)
      nm = $1; gsub(/_/, " ", nm)
      col = (d == 0) ? DIM : good ? GRN : bad ? RED : DIM
      if (d == 0) printf "  %-30s %10s  %s  %10s   %sno change%s\n", nm, $2, AR, $3, DIM, RST
      else printf "  %-30s %10s  %s  %10s   %s%s %.4g%s\n", nm, $2, AR, $3, col, (d > 0 ? "up" : "down"), (d < 0 ? -d : d), RST
    }'
  local gone new
  # findings are matched with their numbers blanked out, so "3 sessions" turning into "4 sessions" is not a new finding
  gone=$(awk 'FNR == NR { t = $0; gsub(/[0-9][0-9.,]*/, "#", t); b[t] = 1; next } { t = $0; gsub(/[0-9][0-9.,]*/, "#", t); if (!(t in b)) print }' <(jtexts "$CMP_B") <(jtexts "$CMP_A"))
  new=$(awk 'FNR == NR { t = $0; gsub(/[0-9][0-9.,]*/, "#", t); b[t] = 1; next } { t = $0; gsub(/[0-9][0-9.,]*/, "#", t); if (!(t in b)) print }' <(jtexts "$CMP_A") <(jtexts "$CMP_B"))
  section "FINDINGS"
  if [ -n "$gone" ]; then printf '%s\n' "$gone" | uawk -v OKM="$OK" "$AWKLIB"'{ printf "  %s%s%s %sgone%s  %s\n", GRN, OKM, RST, GRN, RST, fit($0, W - 14) }'; fi
  if [ -n "$new" ]; then printf '%s\n' "$new" | uawk "$AWKLIB"'{ printf "  %s%s%s %snew%s   %s\n", YEL, DOT, RST, YEL, RST, fit($0, W - 14) }'; fi
  if [ -z "$gone$new" ]; then printf '  %sThe findings are the same.%s\n' "$D" "$X"; fi
}

# ---- --zoo: every session as the animal it behaves like ----
zoo_mode() {
  prepare
  banner "$VERSION $MID the agent zoo $MID read-only"
  section "YOUR ZOO" "each session is the animal it behaves like right now"
  if (( SESS_N == 0 )); then printf '  %sThe zoo is empty. Open an agent and come back.%s\n' "$D" "$X"; return; fi
  local utf=1; [ "$RUL" = "-" ] && utf=0
  echo "$SCAN" | uawk -F'\t' -v utf="$utf" "$AWKLIB"'
    $1 == "MCPS" { mc[$2] = $3; next }
    $1 == "SESS" {
      lab = $2; cpu = $6; mem = $7; age = $19; quiet = $16; sp = $17; procs = $5; idle = $9
      if ($12 == 1 || (quiet > 7200 && cpu < 1)) { an = "Sloth"; em = "🦥"; ch = "S"; why = "has not moved in " int(quiet / 3600) "h" }
      else if (cpu >= 50) { an = "Cheetah"; em = "🐆"; ch = "C"; why = sprintf("sprinting at %.0f%% CPU", cpu) }
      else if (sp >= 20) { an = "Rabbit"; em = "🐇"; ch = "R"; why = sprintf("%d processes started in the last minute", sp) }
      else if (mem >= 1500) { an = "Elephant"; em = "🐘"; ch = "E"; why = "holds " mb(mem) }
      else if (mc[lab] >= 3) { an = "Octopus"; em = "🐙"; ch = "O"; why = mc[lab] " MCP servers on the go" }
      else if (age >= 21600) { an = "Tortoise"; em = "🐢"; ch = "T"; why = "steady, open for " int(age / 3600) "h" }
      else if (procs <= 3 && mem < 200) { an = "Mouse"; em = "🐭"; ch = "M"; why = "tiny: " procs " processes, " mb(mem) }
      else { an = "Owl"; em = "🦉"; ch = "W"; why = "calm and watching" }
      printf "  %s %s%s%-12s%s %s%-9s%s %s%s%s\n", (utf ? em : "[" ch "]"), scol(lab), BLD, lab, RST, BLD, an, RST, DIM, why, RST
    }'
  printf '\n%s%s%s\n' "$D" "$(vibe)" "$X"
}

# ---- --vibe: how the Mac feels, in one line ----
vibe_mode() { prepare; printf '%s%s%s\n' "$B" "$(vibe)" "$X"; }

# ---- --card: a compact summary that fits a screenshot ----
card() {
  prepare
  local w=58 plain top bot gcol
  local mem_used=$(( 100 - ${FREE:-100} ))
  local hl V="│" tl="╭" tr="╮" bl="╰" br="╯"
  hl=$(printf '%*s' $((w + 2)) '' | sed "s/ /$RUL/g")
  if [ "$RUL" = "-" ]; then V="|"; tl="+"; tr="+"; bl="+"; br="+"; fi
  top="$tl$hl$tr"; bot="$bl$hl$br"
  crow() { printf '%s %s%*s %s\n' "$V" "$2" $((w - ${#1})) "" "$V"; }
  gcol=$X; case $HGRADE in A|B) gcol=$G ;; C) gcol=$Y ;; D) gcol=$CO ;; *) gcol=$R ;; esac
  local bar_cpu bar_mem bar_ag
  bar_cpu=$(uawk -v f="$(awk -v a="${ALL_CPU:-0}" -v c="$CORES" 'BEGIN { v = a / c / 100; if (v > 1) v = 1; printf "%.3f", v }')" "$AWKLIB"'BEGIN { printf "%s", gbar(f, 18) }')
  bar_mem=$(uawk -v f="$(awk -v u="$mem_used" 'BEGIN { printf "%.3f", u / 100 }')" "$AWKLIB"'BEGIN { printf "%s", gbar(f, 18) }')
  bar_ag=$(uawk -v f="$(awk -v u="$UN_PCT" 'BEGIN { printf "%.3f", u / 100 }')" "$AWKLIB"'BEGIN { printf "%s", gbar(f, 18) }')
  printf '%s%s%s\n' "$D" "$top" "$X"
  local title="yare-doctor" right="health ${HSCORE}/100  ${HGRADE}"
  plain="$title$(printf '%*s' $((w - ${#title} - ${#right})) '')$right"
  crow "$plain" "$B$C$title$X$(printf '%*s' $((w - ${#title} - ${#right})) '')${D}health${X} ${gcol}${B}${HSCORE}/100  ${HGRADE}${X}"
  crow "${OSINFO#*, } $MID ${MEM_GB} GB $MID ${OSINFO%%,*}" "$D${OSINFO#*, } $MID ${MEM_GB} GB $MID ${OSINFO%%,*}$X"
  crow "" ""
  cpu_use=$(awk -v a="${ALL_CPU:-0}" -v c="$CORES" 'BEGIN { printf "%.0f", a / c }'); plain="CPU     xxxxxxxxxxxxxxxxxx  ${cpu_use}% in use · load ${LOAD:-?}"
  crow "$plain" "${CO}CPU${X}     $bar_cpu  ${B}${cpu_use}%${X} in use · load ${LOAD:-?}"
  plain="Memory  xxxxxxxxxxxxxxxxxx  ${mem_used}% used $MID swap $(fmt_size "${SWAP:-0M}")"
  crow "$plain" "${CP}Memory${X}  $bar_mem  ${B}${mem_used}%${X} used $MID swap $(fmt_size "${SWAP:-0M}")"
  plain="Agents  xxxxxxxxxxxxxxxxxx  $(pl "$SESS_N" session) $MID $(fmt_size "${AG_MB}M")"
  crow "$plain" "${CM}Agents${X}  $bar_ag  ${B}$(pl "$SESS_N" session)${X} $MID $(fmt_size "${AG_MB}M")"
  crow "" ""
  local heavy; heavy=$(echo "$SCAN" | awk -F'\t' '$1 == "SESS" && $7 > m { m = $7; l = $2 } END { if (l != "") printf "%s (%d MB)", l, m }')
  if [ -n "$heavy" ]; then crow "* heaviest: $heavy" "${Y}*${X} heaviest: ${B}$heavy${X}"; fi
  crow "* reclaimable: $(fmt_size "${RECLAIM_MB}M")" "${Y}*${X} reclaimable: ${B}$(fmt_size "${RECLAIM_MB}M")${X}"
  crow "* findings: $(printf '%s' "$NOTES" | awk -F'\t' '$1 <= 2' | wc -l | tr -d ' ') need a look" "${Y}*${X} findings: ${B}$(printf '%s' "$NOTES" | awk -F'\t' '$1 <= 2' | wc -l | tr -d ' ')${X} need a look"
  crow "" ""
  local v; v=$(vibe)
  crow "\"$v\"" "${D}\"$v\"${X}"
  printf '%s%s%s\n' "$D" "$bot" "$X"
}

# ---- --awards: fun superlatives for the sessions ----
awards() {
  prepare
  banner "$VERSION $MID awards $MID read-only"
  section "HALL OF FAME" "who is doing what, with a straight face"
  if (( SESS_N == 0 )); then printf '  %sNo agents running, so nobody gets a trophy. Everyone gets a participation sticker.%s\n' "$D" "$X"; return; fi
  uawk -F'\t' "$AWKLIB"'
    FNR == 1 { fi++ }
    fi == 1 { nt[$1] = $2 + $3; next }
    $1 == "MCPS" { mc[$2] = $3; next }
    $1 == "SESS" { n++; l[n] = $2; net[n] = nt[$2] + 0; mcn[n] = mc[$2] + 0; age[n] = $19; procs[n] = $5; cpu[n] = $6; mem[n] = $7; cm[n] = $8; idm[n] = $10; bld[n] = $11; quiet[n] = $16; host[n] = $15; spawn[n] = $17 }
    function best(arr, dir,   i, b) { b = 1; for (i = 2; i <= n; i++) if ((dir > 0 && arr[i] > arr[b]) || (dir < 0 && arr[i] < arr[b])) b = i; return b }
    function award(title, who, what) { printf "  %s*%s %s%-17s%s %s%s%s%-12s%s %s%s%s\n", YEL, RST, BLD, title, RST, scol(who), BLD, "", who, RST, DIM, what, RST }
    END {
      i = best(mem, 1);   award("The Heavyweight", l[i], sprintf("holds %s", mb(mem[i])))
      i = best(cpu, 1);   if (cpu[i] >= 1) award("The Sprinter", l[i], sprintf("%.1f%% CPU right now", cpu[i]))
      i = best(cm, 1);    if (cm[i] >= 1) award("The Workhorse", l[i], sprintf("%d CPU-%s used so far", cm[i], (cm[i] == 1 ? "minute" : "minutes")))
      i = best(age, 1);   award("The Marathoner", l[i], sprintf("open for %s", human2(age[i])))
      i = best(procs, 1); award("The Crowd", l[i], sprintf("%d processes in one session", procs[i]))
      i = best(idm, 1);   if (idm[i] >= 20) award("The Packrat", l[i], sprintf("%s of helpers sitting idle", mb(idm[i])))
      i = best(spawn, 1); if (spawn[i] >= 20) award("The Spawner", l[i], sprintf("%d processes started in the last minute", spawn[i]))
      i = best(mcn, 1);   if (mcn[i] >= 2) award("The Toolbelt", l[i], sprintf("%d MCP servers running", mcn[i]))
      i = best(net, 1);   if (net[i] >= 5242880) award("The Chatterbox", l[i], sprintf("%s over the network", mb(net[i] / 1048576)))
      i = best(bld, 1);   if (bld[i] >= 1) award("The Builder", l[i], sprintf("%d builds or tests running", bld[i]))
      i = best(quiet, 1); if (quiet[i] > 3600) award("The Sleeper", l[i], sprintf("nothing started for %s", human2(quiet[i])))
      if (n >= 2) { i = best(mem, -1); award("The Minimalist", l[i], sprintf("only %s", mb(mem[i]))) }
    }
    function human2(s,   d, h, m) { d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60); if (d > 0) return d "d " h "h"; if (h > 0) return h "h " m "m"; return m "m" }' <(printf '%s\n' "$NETSESS") <(echo "$SCAN")
  local trouble; trouble=$(echo "$SCAN" | awk -F'\t' '$1 == "TOP" && $3 == "-" { k = $6; c[k]++; cpu[k] += $4 } END { for (k in c) printf "%s\t%.0f\t%d\n", k, cpu[k], c[k] }' | sort -t"$TAB" -k2 -nr | head -1)
  if [ -n "$trouble" ]; then
    printf '  %s*%s %s%-17s%s %s%-12s%s %s%s%% CPU, and it is not even an agent%s\n' "$Y" "$X" "$B" "The Troublemaker" "$X" "$B" "$(echo "$trouble" | cut -f1)" "$X" "$D" "$(echo "$trouble" | cut -f2)" "$X"
  fi
  printf '\n%s%s%s\n' "$D" "$(vibe)" "$X"
}

# ---- --rules: every rule and threshold this tool uses, so nothing is a black box ----
rules_mode() {
  banner "$VERSION $MID rules $MID read-only"
  section "WHAT COUNTS AS A CODING AGENT" "by program name, or by the script an interpreter runs"
  cat <<'EOF'
  claude  codex  gemini  opencode  aider  cursor-agent  amp  goose  crush  droid  qwen  kiro-cli
  copilot  hermes  auggie  cline  plandex  openhands  kimi  devin  kilo  continue  grok  junie  jules

  - Also found when launched through node, bun, deno, python, ruby, uv, uvx, npx, bunx or pnpm,
    for example `node .../@google/gemini-cli/...` or `python -m aider`. Only the script or module the interpreter
    runs counts; its arguments never do (`node server.js --name claude` is not a Claude session).
  - Desktop apps (the Contents/MacOS binary of Claude.app, Codex.app, Cursor.app ...) are hosts, not agents.
    An agent inside an app bundle still counts: Contents/Resources/.../codex, and the claude.app that the
    Claude desktop app runs for its Code tab (.../Claude/claude-code/VERSION/HASH/claude.app).
  - Not a session: --version, --help, login, logout, update, upgrade, doctor, config, completion, install,
    mcp, auth, plugin. `goose` counts only for session / run / web / acp; `hermes` only for the Hermes agent.
  - Helper processes of apps (--type=, "helper") are never agents. This script and its own tools are ignored.
EOF
  section "SESSIONS" "everything below an agent is one session"
  cat <<'EOF'
  - The topmost agent above a process is its session. An agent inside another agent is part of the outer session.
  - Labels (claude#1, claude#2 ...) go oldest first, so they stay put while sessions come and go.
  - The host is the app or program the session runs in: a terminal, an editor, an agent app, tmux or ssh.
EOF
  section "THRESHOLDS" "what makes a finding"
  cat <<'EOF'
  looks forgotten      open over 12 hours and under 0.5% CPU in total
  idle helper          alive over 30 minutes, under 1% CPU, almost no CPU time used (MCP servers look like this)
  possible runaway     a process in a session at 70%+ CPU for 10+ minutes
  hung build           a compiler or linker running 15+ minutes at under 0.5% CPU
  leftover             no parent, alive over 30 minutes, and an agent helper, MCP server, headless browser,
                       language server or dev server
  same helper repeated started 3+ times inside agent sessions
  big memory holder    300 MB or more
  many open files      2,000+ in one session, 60% of the system limit overall
  busy background      25%+ CPU, started by something that has already exited
  CPU measure          two samples of cumulative CPU time about 0.7 s apart (not ps's lifetime average)
  overloaded           load average at or above the number of cores AND half the CPU in use (a high load with a quiet CPU is only noted)
  health score         100, minus 20 per "act on it" and 7 per "worth a look" (A 90, B 80, C 70, D 55)
EOF
  printf '\n%sAll of this is read-only: ps, sysctl, pmset, vm_stat, ioreg, tmutil (status), lsof (listing). No network, no files.%s\n' "$D" "$X"
}

# ---- --tree [LABEL]: every process a session started, as a tree ----
tree_mode() {
  WANT_TREE=1; prepare
  banner "$VERSION $MID process tree $MID read-only"
  tree_body
}
tree_body() {
  if (( SESS_N == 0 )); then printf '\n  %sNo coding agent found running.%s\n' "$D" "$X"; return; fi
  echo "$SCAN" | uawk -F'\t' -v want="$TREE_LABEL" -v redact="$REDACT" "$AWKLIB"'
    $1 == "SESS" { sl[++ns] = $2; sroot[$2] = $3; sage[$2] = $4; sproc[$2] = $5; smem[$2] = $7; shost[$2] = $15 }
    $1 == "PROC" { pid = $2; ppid[pid] = $3; own[pid] = $4; pcpu[pid] = $5; pmem[pid] = $6; page[pid] = $7; pname[pid] = $8; np++; byparent[$3] = byparent[$3] " " pid }
    function sorted(par, out,   a, n, i, j, t) {
      n = split(byparent[par], a, " ")
      for (i = 2; i <= n; i++) { t = a[i]; j = i - 1; while (j > 0 && pmem[a[j]] < pmem[t]) { a[j + 1] = a[j]; j-- } a[j + 1] = t }
      for (i = 1; i <= n; i++) out[i] = a[i]
      return n
    }
    function show(pid, prefix, last, depth,   kids, n, i, line, c, g, k, j, same, tot) {
      line = pname[pid]; if (redact + 0) { sub(/ .*/, "", line) }
      printf "  %s%s%s%s%s%s%-46s%s %s%5.1f%%%s %s%8s%s %s%s%s\n", DIM, prefix, (depth ? (last ? "└─ " : "├─ ") : ""), RST, "", BLD, fit(line, 46), RST, heat(pcpu[pid], 50, 100), pcpu[pid], RST, heat(pmem[pid], 1500, 4000), mb(pmem[pid]), RST, DIM, page[pid], RST
      n = sorted(pid, kids)
      for (i = 1; i <= n; i++) {
        k = kids[i]
        # three or more identical leaf siblings collapse into one line
        if (!(k in done) && !(byparent[k] ~ /[0-9]/)) {
          same = 0; tot = 0
          for (j = 1; j <= n; j++) if (pname[kids[j]] == pname[k] && !(byparent[kids[j]] ~ /[0-9]/)) { same++; tot += pmem[kids[j]] }
          if (same >= 3) {
            for (j = 1; j <= n; j++) if (pname[kids[j]] == pname[k] && !(byparent[kids[j]] ~ /[0-9]/)) done[kids[j]] = 1
            printf "  %s%s%s%s %s%-46s%s %s%6s%s %s%8s%s\n", DIM, prefix (depth ? (last ? "   " : "│  ") : ""), "├─ ", RST, BLD, fit(sprintf("%s  x%d", pname[k], same), 46), RST, "", "", RST, DIM, mb(tot), RST
            continue
          }
        }
        if (k in done) continue
        show(k, prefix (depth ? (last ? "   " : "│  ") : ""), (i == n), depth + 1)
      }
    }
    END {
      for (s = 1; s <= ns; s++) {
        l = sl[s]; if (want != "" && l != want) continue
        printf "\n%s%s%s%s%s  %s%s %s %s %s %s %s%s\n", scol(l), BLD, l, RST, "", DIM, shost[l], MID, sproc[l], (sproc[l] == 1 ? "process" : "processes"), MID, mb(smem[l]), RST
        # the session root is the process whose parent is not part of the session
        for (pid in own) if (own[pid] == l && !(ppid[pid] in own && own[ppid[pid]] == l)) show(pid, "", 1, 0)
      }
      if (want != "" && !(want in sroot)) printf "\n  %sNo session called %s. Labels: ", DIM, want; if (want != "" && !(want in sroot)) { for (s = 1; s <= ns; s++) printf "%s ", sl[s]; printf "%s\n", RST }
    }'
}

# ---- --cleanup: what could be closed, with the commands. It only prints; nothing is ever run ----
cleanup_mode() {
  prepare
  banner "$VERSION $MID cleanup suggestions $MID read-only, prints commands only"
  local any=0 out
  section "SAFE TO CLOSE" "left behind by sessions that ended"
  out=$(echo "$SCAN" | uawk -F'\t' -v redact="$REDACT" "$AWKLIB"'$1 == "LEFT" { printf "  %s%s%s kill %-7s %s# %s, %s, running %s%s\n", GRN, DOT, RST, $2, DIM, ((redact + 0) ? "helper" : fit($6, 40)), mb($4), $5, RST }')
  if [ -n "$out" ]; then echo "$out"; any=1; else printf '  %snothing left behind%s\n' "$D" "$X"; fi
  section "CHECK FIRST" "may still be wanted"
  out=$(echo "$SCAN" | uawk -F'\t' "$AWKLIB"'$1 == "SESS" && $12 == 1 { printf "  %s%s%s kill %-7s %s# %s looks forgotten: open %s, %s. Better: close it from %s%s\n", YEL, DOT, RST, $3, DIM, $2, $4, mb($7), ($15 == "-" ? "its window" : $15), RST }
    $1 == "STUCK" { printf "  %s%s%s kill -9 %-4s %s# %s in %s is %s%s\n", YEL, DOT, RST, $2, DIM, $5, $3, ($4 == "Z" ? "a zombie (its parent has to collect it)" : "suspended; kill -CONT to resume instead"), RST }
    $1 == "DETACH" { printf "  %s%s%s kill %-7s %s# %s at %.0f%% CPU, started by %s: yours? look before closing%s\n", YEL, DOT, RST, $2, DIM, $4, $3, $5, RST }')
  if [ -n "$LOCKS" ]; then
    local lk; lk=$(echo "$LOCKS" | uawk -F'\t' -v r="$REDACT" "$AWKLIB"'{ printf "  %s%s%s rm %-7s %s# stale git lock, %dm old%s\n", YEL, DOT, RST, (r + 0 ? "<lock file>" : "\"" $1 "\""), DIM, $3 / 60, RST }')
    out="${out:+$out$'\n'}$lk"
  fi
  if [ -n "$out" ]; then echo "$out"; any=1; else printf '  %snothing to check%s\n' "$D" "$X"; fi
  section "SUMMARY"
  printf '  Closing the safe ones and the forgotten sessions frees about %s%s%s of memory.\n' "$B" "$(fmt_size "${RECLAIM_MB}M")" "$X"
  printf '  %sThis tool never runs any of these. Use kill PID (polite), then kill -9 PID only if it ignores that.%s\n' "$D" "$X"
  if (( ! any )); then printf '\n  %s%s Nothing to clean up.%s\n' "$G" "$OK" "$X"; fi
}

# ---- --prom: Prometheus text format, for node_exporter's textfile collector ----
prom_mode() {
  COLOR=0; setup_ui; prepare
  echo "# HELP yare_doctor_info yare-doctor version"; echo "# TYPE yare_doctor_info gauge"
  printf 'yare_doctor_info{version="%s"} 1\n' "$VERSION"
  echo "# TYPE yare_doctor_agent_sessions gauge"; printf 'yare_doctor_agent_sessions %s\n' "$SESS_N"
  echo "# TYPE yare_doctor_agent_memory_bytes gauge"; printf 'yare_doctor_agent_memory_bytes %s\n' "$(( AG_MB * 1048576 ))"
  echo "# TYPE yare_doctor_agent_cpu_cores gauge"; printf 'yare_doctor_agent_cpu_cores %s\n' "$(awk -v p="$UN_PTS" 'BEGIN { printf "%.3f", p / 100 }')"
  echo "# TYPE yare_doctor_health_score gauge"; printf 'yare_doctor_health_score %s\n' "$HSCORE"
  echo "# TYPE yare_doctor_reclaimable_bytes gauge"; printf 'yare_doctor_reclaimable_bytes %s\n' "$(( RECLAIM_MB * 1048576 ))"
  echo "# TYPE yare_doctor_findings gauge"
  local lv; for lv in 1 2 3; do printf 'yare_doctor_findings{level="%s"} %s\n' "$( [ $lv = 1 ] && echo act || { [ $lv = 2 ] && echo look || echo info; } )" "$(printf '%s' "$NOTES" | awk -F'\t' -v l="$lv" '$1 == l' | wc -l | tr -d ' ')"; done
  echo "# TYPE yare_doctor_leftover_processes gauge"; printf 'yare_doctor_leftover_processes %s\n' "$LEFT_N"
  echo "# TYPE yare_doctor_forgotten_sessions gauge"; printf 'yare_doctor_forgotten_sessions %s\n' "$FORGOT_N"
  echo "# TYPE yare_doctor_session_memory_bytes gauge"
  echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "yare_doctor_session_memory_bytes{session=\"%s\",host=\"%s\"} %d\n", $2, $15, $7 * 1048576 }'
  echo "# TYPE yare_doctor_session_cpu_percent gauge"
  echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "yare_doctor_session_cpu_percent{session=\"%s\"} %s\n", $2, $6 }'
  echo "# TYPE yare_doctor_session_network_bytes gauge"
  echo "$NETSESS" | awk -F'\t' 'NF { printf "yare_doctor_session_network_bytes{session=\"%s\",direction=\"in\"} %d\nyare_doctor_session_network_bytes{session=\"%s\",direction=\"out\"} %d\n", $1, $2, $1, $3 }'
  echo "# TYPE yare_doctor_stale_git_locks gauge"; printf 'yare_doctor_stale_git_locks %s\n' "$(echo "$LOCKS" | awk 'NF { n++ } END { print n + 0 }')"
  echo "# TYPE yare_doctor_session_processes gauge"
  echo "$SCAN" | awk -F'\t' '$1 == "SESS" { printf "yare_doctor_session_processes{session=\"%s\"} %s\n", $2, $5 }'
}

# ---- --installed: which coding agents are installed on this Mac (nothing is run, only looked for) ----
# Prints one line per agent found, by name in PATH and the usual install folders: name<TAB>path (or "-")<TAB>sessions running now
installed_scan() {
  local dirs d a f found run
  dirs="${PATH//:/ } $HOME/.local/bin $HOME/.claude/local $HOME/.npm-global/bin $HOME/.bun/bin $HOME/.cargo/bin $HOME/.opencode/bin $HOME/.cursor/bin $HOME/.volta/bin $HOME/go/bin /opt/homebrew/bin /usr/local/bin"
  for a in claude codex gemini opencode aider cursor-agent amp goose crush droid qwen kiro-cli copilot hermes auggie cline plandex openhands kimi devin kilo cn grok junie jules; do
    found=""
    for d in $dirs; do
      [ -n "$d" ] || continue
      f="$d/$a"
      if [ -x "$f" ] && [ ! -d "$f" ]; then found="$f"; break; fi
    done
    run=$(echo "$SCAN" | awk -F'\t' -v a="$a" '$1 == "SESS" { split($2, p, "#"); if (p[1] == a || (a == "cn" && p[1] == "continue")) c++ } END { print c + 0 }')
    if [ -n "$found" ] || [ "$run" -gt 0 ]; then printf '%s\t%s\t%s\n' "$a" "${found:--}" "$run"; fi
  done
}

installed_mode() {
  prepare
  banner "$VERSION $MID installed agents $MID read-only, nothing is run"
  installed_body
}
installed_body() {
  section "CODING AGENTS FOUND ON THIS MAC" "looked for by name in your PATH and the usual install folders"
  local n=0 a where run state
  while IFS=$'\t' read -r a where run; do
    [ -n "$a" ] || continue
    n=$((n + 1))
    if [ "$where" = "-" ]; then where="(running, not found in PATH)"; else where="${where/#$HOME/~}"; fi
    if [ "$run" -gt 0 ]; then state="$run running now"; else state="installed, not running"; fi
    printf '  %s%-14s%s %-48s %s\n' "$B" "$a" "$X" "$where" "$state"
  done <<< "$(installed_scan)"
  if (( n == 0 )); then printf '  %sNo coding agent found in PATH or the usual install folders.%s\n' "$D" "$X"; fi
  section "APPS THAT RUN AGENTS" "installed in /Applications or ~/Applications"
  local app m=0 d
  for app in "Claude" "Codex" "ChatGPT" "Cursor" "Windsurf" "Zed" "Conductor" "Warp" "Ghostty" "iTerm" "Visual Studio Code" "T3 Code" "T3 Code (Beta)" "Xcode"; do
    for d in /Applications "$HOME/Applications"; do
      if [ -d "$d/$app.app" ]; then printf '  %s%-20s%s %s\n' "$B" "$app" "$X" "${d/#$HOME/~}/$app.app"; m=$((m + 1)); break; fi
    done
  done
  if (( m == 0 )); then printf '  %sNone of the common ones found.%s\n' "$D" "$X"; fi
}

# ---- --sessions: just the sessions table ----
sessions_mode() {
  prepare
  banner "$VERSION $MID sessions $MID read-only"
  section "AGENT SESSIONS" "each agent and everything it started"
  sessions_table
}

# ---- --snippet launchd|cron|tmux|zsh|statusline: config you can paste to run the doctor automatically (printed, nothing is installed) ----
snippet_mode() {
  local me; me=$(command -v yare-doctor 2>/dev/null || true)
  [ -n "$me" ] || me="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
  case ${SNIP:-} in
    launchd) cat <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.yare.doctor</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$me</string><string>--check</string><string>--notify</string></array>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><false/>
</dict></plist>
<!-- Save everything above as ~/Library/LaunchAgents/com.yare.doctor.plist and run:
       launchctl load ~/Library/LaunchAgents/com.yare.doctor.plist
     Every 10 minutes it shows a macOS notification when something needs a look. Remove it with launchctl unload (same file). -->
EOF2
    ;;
    cron) printf '# crontab -e   (cron cannot show notifications; use launchd for those). Writes one line to a log every 10 minutes:
*/10 * * * * /bin/bash %s --oneline >> $HOME/yare-doctor.log 2>&1
' "$me" ;;
    tmux) printf '# ~/.tmux.conf: the one-line status on the right of the tmux bar, refreshed every 15 seconds
set -g status-interval 15
set -g status-right "#(/bin/bash %s --oneline) %%H:%%M"
' "$me" ;;
    zsh) printf '# ~/.zshrc: a command that prints the one-line status when you want it (about a second per call, so not in your prompt)
agents() { /bin/bash %s --oneline; }
alias doctor="/bin/bash %s"
' "$me" "$me" ;;
    statusline) printf '# ~/.claude/settings.json: the Claude Code status line shows the one-line status
{
  "statusLine": { "type": "command", "command": "/bin/bash %s --oneline" }
}
' "$me" ;;
    *) echo "usage: yare-doctor.sh --snippet launchd|cron|tmux|zsh|statusline   (prints configuration to paste; installs nothing)" >&2; return 2 ;;
  esac
}

# ---- --html: the report as one self-contained web page (redirect it to a file; it is printed, not saved) ----
html_wrap() {
  local body; body=$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  cat <<EOF2
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>yare-doctor report</title>
<style>
:root { --bg:#fbfbfa; --fg:#1d1f24; --dim:#6b7280; }
@media (prefers-color-scheme: dark) { :root { --bg:#0f1117; --fg:#e6e8ee; --dim:#8b93a5; } }
body { margin:0; background:var(--bg); color:var(--fg); font:14px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace; }
main { max-width:110ch; margin:0 auto; padding:24px 16px; }
pre { white-space:pre-wrap; word-break:break-word; margin:0; }
footer { color:var(--dim); margin-top:16px; font-size:12px; }
</style></head><body><main><pre>
$body
</pre><footer>Made with yare-doctor $VERSION, a read-only script: https://github.com/Yare-Org/yare-doctor</footer></main></body></html>
EOF2
}

# ---- the tabbed screen: what plain `yare-doctor` opens in a terminal (clickable tabs, scrolling, refresh) ----
TAB_NAMES=(Overview Sessions Processes Activity Findings Tree Agents Help)
tab_para() { printf '%s\n' "$1" | fold -s -w $((COLS - 4)) | sed "s/^/  ${D}/;s/\$/${X}/"; }
sec_services() {
  (( SVC_N > 0 )) || return 0
  section "BACKGROUND SERVICES" "agents waiting for messages or jobs; not counted as sessions"
  echo "$SCAN" | uawk -F'\t' "$AWKLIB"'$1 == "SVC" { print "  " YEL DOT RST " " BLD pad($2, 14) RST "  " DIM "open " RST rp($4, 8) "   " rp(mb($5), 8) }'
}
sec_unknown() {
  (( UNK_N > 0 )) || return 0
  section "NOT RECOGNISED" "look like coding agents, but are not on the list"
  echo "$SCAN" | uawk -F'\t' "$AWKLIB"'$1 == "UNK" { print "  " MAG DOT RST " " BLD pad($2, 22) RST "  " DIM "pid " $3 ", open " $4 RST }'
  tab_para "Run YARE_DOCTOR_AGENTS=NAME yare-doctor to include one, and send the output of: yare-doctor capture"
}
tab_overview() {
  verdict; echo; dash
  section "WHAT STANDS OUT" "the most important findings; the Findings tab has all of them"
  print_notes 4
  local n_all; n_all=$(printf '%s' "$NOTES" | awk 'NF { n++ } END { print n + 0 }')
  if (( n_all > 4 )); then printf '  %s+ %d more on the Findings tab%s\n' "$D" "$((n_all - 4))" "$X"; fi
  echo; tab_para "Tabs: Sessions (who is running what), Processes (CPU and memory), Activity (builds, ports, leftovers), Findings, Tree, Agents, Help."
}
tab_sessions() {
  section "AGENT SESSIONS" "each agent and everything it started"
  sessions_table
  local idle_installed; idle_installed=$(installed_scan | awk -F'\t' '$3 == 0 { printf "%s%s", (n++ ? ", " : ""), $1 }')
  if [ -n "$idle_installed" ]; then printf '  %sInstalled here, not running: %s%s\n' "$D" "$idle_installed" "$X"; fi
  sec_services
  apps_table
}
tab_processes() {
  section "WHO IS USING THE CPU" "measured over about a second; the owner is the agent session that started it"
  cpu_table
  mem_table
  sec_groups
}
tab_activity() {
  sec_builds
  sec_needs
  sec_helpers
  sec_ports
  sec_awake
  sec_left
}
tab_findings() {
  section "ALL FINDINGS" "most important first"
  if [ -z "$(printf '%s' "$NOTES" | awk 'NF')" ]; then printf '  %s%s Nothing to report.%s\n' "$G" "$OK" "$X"; else print_notes; fi
  echo; tab_para "ACT = fix it now   LOOK = worth a look   INFO = good to know. The health score drops 20 per ACT and 7 per LOOK."
  sec_unknown
}
tab_tree() {
  section "PROCESS TREE" "every process each session started"
  tree_body
}
tab_agents() {
  installed_body
  sec_services
  sec_unknown
}
tab_help() {
  section "KEYS"
  printf '  %s%-26s%s %s\n' "$B" "Left / Right, Tab" "$X" "previous / next tab (or click a tab name)"
  printf '  %s%-26s%s %s\n' "$B" "1 to 8" "$X" "jump to a tab"
  printf '  %s%-26s%s %s\n' "$B" "Up / Down, mouse wheel" "$X" "scroll;  PgUp / PgDn or space / b: a page;  g / G: top / bottom"
  printf '  %s%-26s%s %s\n' "$B" "r" "$X" "refresh now (a snapshot takes about a second)"
  printf '  %s%-26s%s %s\n' "$B" "a" "$X" "turn auto-refresh (every 5 seconds) on or off"
  printf '  %s%-26s%s %s\n' "$B" "q, Ctrl-C" "$X" "quit"
  section "OTHER WAYS TO RUN IT"
  printf '  %s%-26s%s %s\n' "$B" "yare-doctor plain" "$X" "this report as plain text (what you get when piped)"
  printf '  %s%-26s%s %s\n' "$B" "yare-doctor watch 60" "$X" "sample for a minute: did an agent build overlap yours?"
  printf '  %s%-26s%s %s\n' "$B" "yare-doctor why 1234" "$X" "who started process 1234"
  printf '  %s%-26s%s %s\n' "$B" "yare-doctor share" "$X" "one line of counts to paste in a reply (add redact to hide names)"
  printf '  %s%-26s%s %s\n' "$B" "yare-doctor help all" "$X" "every option"
  section "ABOUT"
  tab_para "Read-only: no network, no files written, nothing stopped. It reads the process list, follows each process up to the agent session that started it, and reports."
  tab_para "Something missed or wrong? Run  yare-doctor capture > capture.txt  and send the file: it keeps the shape of each command and masks private words."
}
tabs_render() {
  local i fn
  for i in 0 1 2 3 4 5 6 7; do
    case $i in 0) fn=tab_overview ;; 1) fn=tab_sessions ;; 2) fn=tab_processes ;; 3) fn=tab_activity ;; 4) fn=tab_findings ;; 5) fn=tab_tree ;; 6) fn=tab_agents ;; *) fn=tab_help ;; esac
    TAB_TXT[$i]=$($fn | sed '1{/^[[:space:]]*$/d;}')
    TAB_N[$i]=$(printf '%s\n' "${TAB_TXT[$i]}" | wc -l | tr -d ' ')
  done
  local n1 n2
  n1=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 1' | wc -l | tr -d ' '); n2=$(printf '%s' "$NOTES" | awk -F'\t' '$1 == 2' | wc -l | tr -d ' ')
  TAB_BADGE[1]=""; (( SESS_N > 0 )) && TAB_BADGE[1]=" $SESS_N"
  TAB_BADGE[4]=""; TAB_BCOL[4]=""
  if (( n1 > 0 )); then TAB_BADGE[4]=" $n1"; TAB_BCOL[4]=$'\033[31;1m'; elif (( n2 > 0 )); then TAB_BADGE[4]=" $n2"; TAB_BCOL[4]=$'\033[33;1m'; fi
}
tabs_draw() {
  local out i x vis h total maxs lines shown n hint auto_t
  h=$((TROWS - 4))
  total=${TAB_N[$TAB_CUR]}; maxs=$((total - h)); (( maxs < 0 )) && maxs=0
  (( TAB_SCROLL > maxs )) && TAB_SCROLL=$maxs; (( TAB_SCROLL < 0 )) && TAB_SCROLL=0
  out=$'\033[H'"  ${B}yare-doctor${X} ${D}${VERSION}  read-only, nothing is changed${X}   ${D}health${X} ${B}${HSCORE:-100}/100 ${HGRADE:-A}${X}"$'\033[K\n'
  out="$out  "; x=3
  for i in 0 1 2 3 4 5 6 7; do
    vis=" ${TAB_NAMES[$i]}${TAB_BADGE[$i]:-} "
    TAB_X0[$i]=$x; TAB_X1[$i]=$((x + ${#vis} - 1))
    if (( i == TAB_CUR )); then out="$out"$'\033[7;1m'"$vis"$'\033[0m'
    elif [ -n "${TAB_BCOL[$i]:-}" ]; then out="$out${TAB_BCOL[$i]}$vis"$'\033[0m'
    else out="$out"$'\033[2m'"$vis"$'\033[0m'; fi
    out="$out "; x=$((x + ${#vis} + 1))
  done
  out="$out"$'\033[K\n'"$(rule)"$'\033[K\n'
  lines=$(printf '%s\n' "${TAB_TXT[$TAB_CUR]}" | sed -n "$((TAB_SCROLL + 1)),$((TAB_SCROLL + h))p")
  shown=0
  while IFS= read -r line; do out="$out$line"$'\033[K\n'; shown=$((shown + 1)); done <<< "$lines"
  while (( shown < h )); do out="$out"$'\033[K\n'; shown=$((shown + 1)); done
  if (( TAB_AUTO )); then auto_t="auto-refresh on"; else auto_t="r refresh"; fi
  hint="  Left/Right or click: tabs   Up/Down: scroll   $auto_t   a: auto   ?: help   q: quit"
  n=""; (( total > h )) && n="  lines $((TAB_SCROLL + 1))-$((TAB_SCROLL + h > total ? total : TAB_SCROLL + h)) of $total"
  out="$out"$'\033[2m'"$hint$n  ${TAB_STAMP:+updated $TAB_STAMP}${TAB_STATUS:+  $TAB_STATUS}"$'\033[0m\033[K'
  printf '%s' "$out"
}
tabs_size() {
  local sz; sz=$(stty size 2>/dev/null) || sz=""
  TROWS=${sz%% *}; TCOLS=${sz##* }
  [[ $TROWS =~ ^[0-9]+$ ]] && (( TROWS > 0 )) || TROWS=$(tput lines 2>/dev/null || echo 30)
  [[ $TCOLS =~ ^[0-9]+$ ]] && (( TCOLS > 0 )) || TCOLS=$(tput cols 2>/dev/null || echo 100)
  [[ $TROWS =~ ^[0-9]+$ ]] || TROWS=30; [[ $TCOLS =~ ^[0-9]+$ ]] || TCOLS=100
}
tabs_refresh() {
  TAB_STATUS="refreshing..."; tabs_draw
  prepare; tabs_render
  TAB_STATUS=""; TAB_STAMP=$(date +%H:%M:%S); TAB_LAST=$(date +%s)
}
tabs_key() { # reads one key; sets KEY (TIMEOUT, ESC, UP DOWN LEFT RIGHT PGUP PGDN HOME END BTAB TAB ENTER, MOUSE:<seq> or the character)
  local c c2 seq=""
  KEY=""
  IFS= read -rsn1 -t 1 c || { KEY=TIMEOUT; return; }
  if [ -z "$c" ]; then KEY=ENTER; return; fi
  if [ "$c" = $'\033' ]; then
    IFS= read -rsn1 -t 1 c2 || { KEY=ESC; return; }
    if [ "$c2" = "[" ]; then
      while IFS= read -rsn1 -t 1 c; do
        seq="$seq$c"
        case $c in [A-Za-z~]) break ;; esac
      done
      case $seq in
        A) KEY=UP ;; B) KEY=DOWN ;; C) KEY=RIGHT ;; D) KEY=LEFT ;; Z) KEY=BTAB ;; H|1~) KEY=HOME ;; F|4~) KEY=END ;; 5~) KEY=PGUP ;; 6~) KEY=PGDN ;;
        "<"*) KEY="MOUSE:$seq" ;;
        *) KEY=OTHER ;;
      esac
    elif [ "$c2" = "O" ]; then
      IFS= read -rsn1 -t 1 c || true
      case $c in A) KEY=UP ;; B) KEY=DOWN ;; C) KEY=RIGHT ;; D) KEY=LEFT ;; *) KEY=OTHER ;; esac
    else KEY=OTHER; fi
    return
  fi
  if [ "$c" = $'\t' ]; then KEY=TAB; return; fi
  KEY=$c
}
tabs_mode() {
  tabs_size
  if (( TROWS < 14 || TCOLS < 80 )); then
    printf 'The terminal is too small for the tabbed view (%dx%d, needs 80x14). Showing the plain report.\n' "$TCOLS" "$TROWS" >&2
    snapshot; return
  fi
  local saved_stty dirty=1 mb mx my fin m now
  TAB_CUR=0; TAB_SCROLL=0; TAB_AUTO=0; TAB_STAMP=""; TAB_STATUS=""; TAB_LAST=$(date +%s); RESIZED=0
  TAB_TXT=(); TAB_N=(); TAB_BADGE=(); TAB_BCOL=(); TAB_X0=(); TAB_X1=()
  WANT_TREE=1
  saved_stty=$(stty -g 2>/dev/null || true)
  tabs_cleanup() { printf '\033[?1006l\033[?1000l\033[?25h\033[?1049l'; [ -n "$saved_stty" ] && stty "$saved_stty" 2>/dev/null; return 0; }
  trap 'tabs_cleanup; exit 0' EXIT
  trap 'exit 130' INT TERM
  trap 'RESIZED=1' WINCH
  stty -echo 2>/dev/null || true
  printf '\033[?1049h\033[?25l\033[?1000h\033[?1006h\033[2J\033[H'
  COLUMNS=$TCOLS; setup_ui
  printf '\033[H  %sReading the process list...%s\033[J' "$D" "$X"
  prepare; tabs_render; TAB_STAMP=$(date +%H:%M:%S); TAB_LAST=$(date +%s)
  while true; do
    if (( RESIZED )); then RESIZED=0; tabs_size; COLUMNS=$TCOLS; setup_ui; tabs_render; printf '\033[2J'; dirty=1; fi
    if (( dirty )); then tabs_draw; dirty=0; fi
    tabs_key
    case $KEY in
      TIMEOUT) now=$(date +%s); if (( TAB_AUTO )) && (( now - TAB_LAST >= 5 )); then tabs_refresh; dirty=1; fi ;;
      q|Q) break ;;
      RIGHT|TAB|l) TAB_CUR=$(( (TAB_CUR + 1) % 8 )); TAB_SCROLL=0; dirty=1 ;;
      LEFT|BTAB|h) TAB_CUR=$(( (TAB_CUR + 7) % 8 )); TAB_SCROLL=0; dirty=1 ;;
      [1-8]) TAB_CUR=$((KEY - 1)); TAB_SCROLL=0; dirty=1 ;;
      "?") TAB_CUR=7; TAB_SCROLL=0; dirty=1 ;;
      DOWN|j|ENTER) TAB_SCROLL=$((TAB_SCROLL + 1)); dirty=1 ;;
      UP|k) TAB_SCROLL=$((TAB_SCROLL - 1)); dirty=1 ;;
      PGDN|" "|f) TAB_SCROLL=$((TAB_SCROLL + TROWS - 5)); dirty=1 ;;
      PGUP|b) TAB_SCROLL=$((TAB_SCROLL - TROWS + 5)); dirty=1 ;;
      HOME|g) TAB_SCROLL=0; dirty=1 ;;
      END|G) TAB_SCROLL=99999; dirty=1 ;;
      r|R) tabs_refresh; dirty=1 ;;
      a|A) TAB_AUTO=$((1 - TAB_AUTO)); dirty=1 ;;
      MOUSE:*)
        m=${KEY#MOUSE:<}; fin=${m: -1}; m=${m%?}
        IFS=';' read -r mb mx my <<< "$m"
        case $mb in
          64) TAB_SCROLL=$((TAB_SCROLL - 3)); dirty=1 ;;
          65) TAB_SCROLL=$((TAB_SCROLL + 3)); dirty=1 ;;
          0) if [ "$fin" = M ] && [ "${my:-0}" = 2 ]; then
               for m in 0 1 2 3 4 5 6 7; do
                 if (( mx >= TAB_X0[m] && mx <= TAB_X1[m] )); then TAB_CUR=$m; TAB_SCROLL=0; dirty=1; fi
               done
             fi ;;
        esac ;;
    esac
  done
  exit 0
}

# ---- --completions bash|zsh ----
completions_mode() {
  local opts="watch live tree why cleanup share redact json sessions installed check plain tabs help --watch --live --why --oneline --check --card --awards --vibe --tree --cleanup --installed --sessions --notify --html --snippet --rules --prom --share --redact --json --selftest --checksum --no-color --color --version --help --limit-mem --limit-cpu --limit-sessions --completions --capture --from --md --ascii --light --slow --compare --zoo"
  case ${COMPL_SHELL:-} in
    bash) printf '_yare_doctor() { COMPREPLY=( $(compgen -W "%s" -- "${COMP_WORDS[COMP_CWORD]}") ); }\ncomplete -F _yare_doctor yare-doctor yare-doctor.sh\n' "$opts" ;;
    zsh) printf '#compdef yare-doctor yare-doctor.sh\n_arguments "*: :(%s)"\n' "$opts" ;;
    *) echo "usage: yare-doctor.sh --completions bash|zsh   (for example: eval \"\$(bash yare-doctor.sh --completions bash)\")" >&2; return 2 ;;
  esac
}

setup_ui
run_mode() {
  case $MODE in rules|completions|checksum) ;; *) if [ "$(uname -s)" != Darwin ]; then echo "yare-doctor reads macOS process and power information, so it only runs on a Mac." >&2; return 2; fi ;; esac
  case $MODE in
    watch) watch_mode ;; selftest) selftest ;; live) live ;; why) why ;; checksum) checksum ;; oneline) oneline ;;
    check) check ;; card) card ;; awards) awards ;; vibe) vibe_mode ;; cleanup) cleanup_mode ;; rules) rules_mode ;;
    prom) prom_mode ;; zoo) zoo_mode ;; slow) slow_mode ;; compare) compare_mode ;; capture) capture_mode ;; tree) tree_mode ;; completions) completions_mode ;; snippet) snippet_mode ;; tabs) tabs_mode ;; installed) installed_mode ;; sessions) sessions_mode ;; *) snapshot ;;
  esac
}
if (( MD )) && (( ! JSON )); then echo '```'; run_mode; rc=$?; echo '```'; exit "$rc"; fi
if (( HTML )) && (( ! JSON )); then run_mode 2>&1 | html_wrap; exit "${PIPESTATUS[0]}"; fi
run_mode
exit $?
