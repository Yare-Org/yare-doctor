# yare-doctor

A small, read-only script that shows what your coding agents are running on your Mac, and whether their builds are running at the same time as yours.

**Install** (optional; or just download the one file and run it with `bash`):

```sh
brew install yare-org/tap/yare-doctor
yare-doctor --watch 60
```

```sh
bash yare-doctor.sh                 # one snapshot, run it while your agents are working
bash yare-doctor.sh --watch 60      # sample for a minute: how often did an agent's build overlap yours?
bash yare-doctor.sh --share         # also prints one line of counts you can paste in a reply
bash yare-doctor.sh --json          # counts as JSON
```

It is about 200 lines of bash. **Read it before you run it**; that is what it is for.

## What it reports

- How many coding agent processes are running (Claude Code, Codex, OpenCode, Aider, Cursor agent, Gemini), per agent, with CPU and memory.
- How many builds and test runs are going (clang, swiftc, cargo, tsc, xcodebuild, make, ninja, vite, jest, ...), split into **started by an agent** (an agent process is an ancestor) and **not under any agent**, which is usually you.
- Load, swap and memory-free on your Mac.
- Helper processes (MCP servers and similar) that have no parent and have been alive for over 30 minutes, which may be left over from sessions that ended.
- With `--watch`: a sample every 5 seconds, and how many seconds an agent's build and a build of yours were running together.

## What it does not do

- It does not change anything. It uses only `ps`, `sysctl` and `memory_pressure`.
- It makes **no network calls** and writes **no files**. It does not stop or kill any process (for leftovers it only prints a `kill PID` hint for you to use yourself).
- `--share` output contains counts only: no paths, user names or command lines.

## Limits, stated plainly

- It is a rough snapshot, not a benchmark. Overlap shows how often builds collided, not how much it slowed you down.
- Detection is by process name and ancestry, so it can miss an agent or misflag a process. The leftover check is a heuristic.
- Built for macOS and tested on a small number of Macs so far (bash 3.2 as shipped with macOS). If it gets something wrong on yours, please open an issue with the process name.

## About

Made by the team building **Yare**, an early, unreleased prototype Mac tool for people who run several coding agents at once. We built this script to see what the problem actually looks like on real machines, and we have not measured a speed-up. If you run 2+ agents and want to tell us what slows your Mac down, we would like to hear it: open an issue, or join the waitlist at <https://meetyare.vercel.app/?utm_source=github&utm_medium=readme&utm_campaign=doctor>.

MIT licensed.
