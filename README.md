# yare-doctor

A small, read-only script that shows what your coding agents are doing to your Mac. It follows every process back to the agent session that started it, so it can tell you which agent is holding what.

**Install** (any one of these; the script is one file, and you should read it first):

```sh
brew install yare-org/tap/yare-doctor      # Homebrew
yare-doctor --watch 60
```

```sh
# or without Homebrew: download the release file, check it, run it
curl -fsSLO https://github.com/Yare-Org/yare-doctor/releases/latest/download/yare-doctor.sh
curl -fsSLO https://github.com/Yare-Org/yare-doctor/releases/latest/download/yare-doctor.sh.sha256
shasum -a 256 -c yare-doctor.sh.sha256     # must print: yare-doctor.sh: OK
bash yare-doctor.sh
```

```sh
bash yare-doctor.sh                 # one snapshot, run it while your agents are working (about a second)
bash yare-doctor.sh --watch 60      # sample for a minute: how often did an agent's build overlap yours?
bash yare-doctor.sh --live          # refreshing view of sessions and CPU (q quits)
bash yare-doctor.sh --tree          # every process each session started, as a tree
bash yare-doctor.sh --why 1234      # who started process 1234? its chain up to the agent session
bash yare-doctor.sh --cleanup       # what could be closed, with kill commands (printed, never run)
bash yare-doctor.sh --card          # a small boxed summary with a health score, for screenshots
bash yare-doctor.sh --share         # also prints one line of counts you can paste in a reply
bash yare-doctor.sh --redact        # hide folder, branch and helper names so the whole report is safe to paste
bash yare-doctor.sh --json          # machine-readable output (--prom for Prometheus)
bash yare-doctor.sh --check         # quiet; exit 0 nothing to do, 1 worth a look, 2 act on it (cron, scripts)
bash yare-doctor.sh --rules         # every rule and threshold it uses, including what counts as an agent
bash yare-doctor.sh --selftest      # does every part work on this Mac?
bash yare-doctor.sh --help          # all options
```

It is about 2,000 lines of bash. **Read it before you run it**; that is what it is for. Every release has a checksum (`bash yare-doctor.sh --checksum`) you can compare with the release notes. Changes are in [CHANGELOG.md](CHANGELOG.md).

## What it looks like

Colour and bars in a terminal; plain text when piped or with `--no-color`. This is the top of a real report on a Mac with four agent sessions, run with `--redact` (folder names hidden):

```text
yare-doctor  0.1.0 · read-only · nothing was changed
──────────────────────────────────────────────────────────────────────────────────────────────────

  Mac       Apple M3 Max · 14 cores · 36 GB · macOS 27.2 · up 7 days
  CPU load  ████████░░░░░░░░  6.61 on 14 cores
  Memory    ████████████░░░░  78% used · swap 9.6 GB
  Agents    ░░░░░░░░░░░░░░░░  0.2% of the CPU · 0.6 GB · 4 sessions
  Power     plugged in · high power mode · 55 GB disk free · 10.2k files open · 811 processes

WHAT STANDS OUT
  ● Swap use is 9.6 GB and free memory is 22%. The Mac is short of memory. The biggest holder is
    llama-server at 13.3 GB (not an agent).
  ● Looks forgotten (open over 12 hours, almost no CPU used): codex#1 (open 18h 43m, 21 MB).
    Closing it would free that memory.
  ● The same helper was started 3 times across 3 places inside agent sessions: helper-2 (58 MB in
    total). Often that is one tool per session, which adds up.
  ● 4 agent sessions are running. Together they and everything started under them use about 0.2%
    of this Mac's CPU and 0.6 GB.

AGENT SESSIONS  each agent and everything it started
  SESSION    FOLDER          HOST        RUNNING PROCS     CPU    MEMORY  FILES BUILDS
  claude#1   folder-1        T3 Code         15m     4    1.7%    298 MB     57      0
  codex#1    folder-2        JetBrains   18h 43m     2    0.0%     21 MB     29      0
    ↳ looks forgotten  1 idle helper holding 15 MB
  claude#2   folder-3        T3 Code         55m     5    0.6%    169 MB     60      0
    ↳ 3 idle helpers holding 17 MB
  claude#3   folder-4        T3 Code         32m     4    0.0%    116 MB     53      0
    ↳ 3 idle helpers holding 17 MB

WHO IS USING THE CPU  the owner is the agent session that started it
  PROCESS                                      CPU    MEMORY  STARTED BY
  llama-server                    ████████   43.3%   13.3 GB  not an agent
```

## How CPU is measured (and what 1% means)

CPU is **measured, not read from `ps`**: the script takes two snapshots of every process's cumulative CPU time a moment apart and works out the real load in between. (`ps %cpu` on macOS is an average that lags, so a process that just got busy still shows a few percent.) Numbers use the Activity Monitor convention: **100% is one core**, so on a 14-core Mac a process at 100% is about 7% of the whole machine. The report always says which one it means.

Two things it separates, on purpose:

- **The agent's own processes** (the `claude`, `codex`... process and everything it started) usually use very little CPU, because the model runs on a server. The heavy local load comes from what the agent starts: builds, tests, dev servers.
- **The app the session runs in** (T3 Code, VS Code, Cursor, JetBrains, a terminal) with all its windows and helper processes. Streaming output and rendering can make the *app* busy while the agent's processes stay near zero, so the report shows the host app next to its sessions and says when the load is in the app rather than the agent.

Processes that no longer have a parent (a dev server an agent left running, or anything that daemonised) cannot be traced back to a session. When one is busy, the report lists it as *detached* and suggests `--why PID` rather than guessing.

## What it reports

- **What stands out**: a few plain sentences at the top, only about things it actually found.
- **Agent sessions**: each session of the 22 coding agents it recognises (Claude Code, Codex, Gemini, OpenCode, Cursor, Copilot, Amp, Aider, Goose, Kilo and more; `--rules` lists them all) and *everything it started*, with the folder it works in, the app it runs in (Terminal, iTerm, VS Code, T3 Code, tmux, ...), how many files it holds open, how long it has been running, when it last started a process (ACTIVE), process count, CPU, memory, CPU time used so far, and builds. Activity Monitor lists processes; this groups them by which agent started them.
- **Who is using the CPU and memory right now, and who started it.** If your Mac feels slow, this shows whether it is an agent's tree or something else (often it is not the agent).
- **Idle helpers**: helper processes inside a session that have been alive over 30 minutes and barely used any CPU, with the memory they hold. (An MCP server waiting for requests looks like this too, so it is a pointer, not a verdict.)
- **Helpers started many times**: the same helper (for example one MCP server per session) running 3 or more times, and how much memory that adds up to.
- **Host apps**: the app each session runs in, with all its windows and helpers (CPU, memory, process count), and a note when the app is much busier than the agent inside it.
- **Detached busy processes**: busy processes with no agent or app above them, which may be background work an agent left running.
- **Agents inside agents**: nested agent processes (parallel workers) started by a session.
- **Needs a look**: a process inside a session using 70%+ CPU for 10+ minutes (possible runaway), suspended or zombie processes that still hold memory, and sessions that look forgotten (open 12+ hours, almost no CPU).
- **Sessions sharing a folder**: two agents working in the same folder share its files and build output, so their builds can collide.
- **Memory by program**: the same program counted together (for example 37 Chrome helper processes adding up to 4.8 GB), and how many of them are inside agent sessions. Activity Monitor lists them one by one.
- **Builds running now**: each build or test process, how long it has run, who started it, and a flag for a compiler that has run 15+ minutes at almost no CPU (possibly hung).
- **Ports held open** by agent sessions, or by things that look left behind, so you can see why a dev server will not start on its usual port.
- **Builds and test runs** (clang, swiftc, cargo, tsc, xcodebuild, make, ninja, vite, jest, ...), split into **started by an agent** and **not under any agent**, which is usually you.
- **Leftovers**: helper processes with no parent that have been alive over 30 minutes, which may belong to sessions that ended.
- **What is keeping the Mac awake** (for example `caffeinate`), and whether an agent started it.
- **Mac state that changes build speed**: load, swap, compressed memory, GPU use, free memory, battery, free disk, whether Time Machine is backing up, open-file and process limits, Low Power Mode, and any CPU speed limit macOS has recorded. When a macOS service such as Spotlight is the busiest thing, it says so, because the slowness may not be the agents' fault.
- With `--why PID`: the chain of processes that started that one, from the top (an app or terminal) down, and which agent session it belongs to, if any.
- With `--redact`: replaces folder names with `folder-1`, repeated-helper names with `helper-1` and leftover commands with a placeholder, so the report can be pasted. Process names in the CPU and memory lists are still shown (for example `Google Chrome Helper`), so look before you paste.
- With `--selftest`: checks every part of the script against a made-up process list with known answers and against your Mac, prints PASS or FAIL for each, and gives a one-line, no-personal-data summary to paste into an issue if something fails.
- With `--watch`: a sample every 5 seconds, how many seconds an agent's build and a build of yours were running together, how many seconds the Mac was at 80% CPU or more with agents making up a third or more of that, how many CPU-minutes agents used compared with everything else, the busiest session, how much memory the agent sessions gained, the fastest-growing process, how many sessions started or ended, and at least how many new processes they started.

## What it does not do

- It does not change anything. It uses only `ps`, `sysctl`, `memory_pressure`, `pmset`, `df`, `sw_vers`, `vm_stat`, `ioreg`, `tmutil status` and `lsof` (which only lists open ports and never connects).
- It makes **no network calls** and writes **no files**. It does not stop or kill any process (for leftovers it only prints a `kill PID` hint for you to use yourself).
- `--share` output contains counts only: no paths, user names or command lines. The on-screen report does print process names (for example `node twitter-server`), so look before you paste a screenshot.

## Limits, stated plainly

- It is a rough snapshot, not a benchmark. Overlap shows how often builds collided, not how much it slowed you down.
- Detection is by process name, script name and ancestry, so it can miss an agent or misflag a process. 16 of the 22 agents were launched for real on one Apple Silicon Mac and their actual process lists are in `--selftest`; the other six (kiro-cli, cline, plandex, openhands, devin, hermes) are covered by their published command lines only. The leftover and idle checks are heuristics. `ps` reports an average CPU figure, not an instant one, and macOS does not always record thermal limits, so "none" does not prove the Mac is not throttled.
- Built for macOS and tested on a small number of Macs so far (bash 3.2 as shipped with macOS; CI runs `--selftest` on macOS 15 (Apple silicon and Intel)). If it gets something wrong on yours, run `bash yare-doctor.sh --capture > capture.txt` (a process list with arguments trimmed) and attach it to an issue; `--from capture.txt` replays it here.

## About

Made by the team building **Yare**, an early, unreleased prototype Mac tool for people who run several coding agents at once. We built this script to see what the problem actually looks like on real machines, and we have not measured a speed-up. If you run 2+ agents and want to tell us what slows your Mac down, we would like to hear it: open an issue, or join the waitlist at <https://meetyare.vercel.app/?utm_source=github&utm_medium=readme&utm_campaign=doctor>.

MIT licensed.
