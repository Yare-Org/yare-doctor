# yare-doctor

A small, read-only script that shows what your coding agents are doing to your Mac. It follows every process back to the agent session that started it, so it can tell you which agent is holding what.

**Install** (optional; or just download the one file and run it with `bash`):

```sh
brew install yare-org/tap/yare-doctor
yare-doctor --watch 60
```

```sh
bash yare-doctor.sh                 # one snapshot, run it while your agents are working (about a quarter of a second)
bash yare-doctor.sh --watch 60      # sample for a minute: how often did an agent's build overlap yours?
bash yare-doctor.sh --share         # also prints one line of counts you can paste in a reply
bash yare-doctor.sh --json          # counts as JSON
```

It is about 400 lines of bash. **Read it before you run it**; that is what it is for.

## What it reports

- **What stands out**: a few plain sentences at the top, only about things it actually found.
- **Agent sessions**: each Claude Code, Codex, OpenCode, Aider, Cursor agent or Gemini session and *everything it started*, with how long it has been running, process count, CPU, memory, and CPU time used so far. Activity Monitor lists processes; this groups them by which agent started them.
- **Who is using the CPU right now, and who started it.** If your Mac feels slow, this shows whether it is an agent's tree or something else (often it is not the agent).
- **Idle helpers**: helper processes inside a session that have been alive over 30 minutes and barely used any CPU, with the memory they hold. (An MCP server waiting for requests looks like this too, so it is a pointer, not a verdict.)
- **Helpers started many times**: the same helper (for example one MCP server per session) running 3 or more times, and how much memory that adds up to.
- **Ports held open** by agent sessions, or by things that look left behind, so you can see why a dev server will not start on its usual port.
- **Builds and test runs** (clang, swiftc, cargo, tsc, xcodebuild, make, ninja, vite, jest, ...), split into **started by an agent** and **not under any agent**, which is usually you.
- **Leftovers**: helper processes with no parent that have been alive over 30 minutes, which may belong to sessions that ended.
- **Mac state that changes build speed**: load, swap, free memory, Low Power Mode, and any CPU speed limit macOS has recorded.
- With `--watch`: a sample every 5 seconds, how many seconds an agent's build and a build of yours were running together, how many seconds the Mac was at 80% CPU or more with agents making up a third or more of that, how many CPU-minutes agents used compared with everything else, and the busiest session.

## What it does not do

- It does not change anything. It uses only `ps`, `sysctl`, `memory_pressure`, `pmset` and `lsof` (which only lists open ports and never connects).
- It makes **no network calls** and writes **no files**. It does not stop or kill any process (for leftovers it only prints a `kill PID` hint for you to use yourself).
- `--share` output contains counts only: no paths, user names or command lines. The on-screen report does print process names (for example `node twitter-server`), so look before you paste a screenshot.

## Limits, stated plainly

- It is a rough snapshot, not a benchmark. Overlap shows how often builds collided, not how much it slowed you down.
- Detection is by process name and ancestry, so it can miss an agent or misflag a process. The leftover and idle checks are heuristics. `ps` reports an average CPU figure, not an instant one, and macOS does not always record thermal limits, so "none" does not prove the Mac is not throttled.
- Built for macOS and tested on a small number of Macs so far (bash 3.2 as shipped with macOS). If it gets something wrong on yours, please open an issue with the process name.

## About

Made by the team building **Yare**, an early, unreleased prototype Mac tool for people who run several coding agents at once. We built this script to see what the problem actually looks like on real machines, and we have not measured a speed-up. If you run 2+ agents and want to tell us what slows your Mac down, we would like to hear it: open an issue, or join the waitlist at <https://meetyare.vercel.app/?utm_source=github&utm_medium=readme&utm_campaign=doctor>.

MIT licensed.
