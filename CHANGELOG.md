# Changelog

Versions follow [semver](https://semver.org). The 0.x line means the output format and options can still change.

## 0.1.0 (2026-11-08)

First public release.

**Detection**
- Recognises 25 coding agents (Claude Code, Codex, Gemini, OpenCode, Aider, Cursor, Amp, Goose, Crush, Droid, Qwen, Kiro, Copilot, Hermes, Auggie, Cline, Plandex, OpenHands, Kimi, Devin, Kilo, Continue, Grok, Junie, Jules), including ones started through node, python, bun, uv, npx or an app bundle (the Claude desktop app's Code tab, Junie), and npm installs that ship `claude.exe`-style binaries.
- Only the program an interpreter runs counts, never its arguments (`node server.js --name claude` is not a session). Desktop apps, `--version`, `login`, `mcp` and background daemons (`codex app-server --managed-daemon`, `opencode serve --service`, `cline --cline-hub-daemon`) are not counted as sessions.
- Sessions are numbered oldest first, so labels stay put. The host is found from the app, tmux or ssh (19 terminals and editors tested).
- All 25 agents were launched for real on one Apple Silicon Mac (Hermes and the Claude desktop app were seen live) and their actual process lists are in `--selftest`.

**What it shows**
- Per session: folder, git branch (read from `.git/HEAD`, no git run), MCP servers, network bytes, program version, what it is running now.
- Findings: sessions building in the same folder, stale git locks, a session waiting for a password or login, a spawn storm, two versions of one agent running, an overloaded Mac, VM memory, forgotten sessions, idle and repeated helpers, held ports.
- A health score and grade. CPU is measured over a second, not read from `ps`.

**Views and outputs**
- `--sessions`, `--tree`, `--why PID`, `--installed`, `--cleanup` (prints kill commands, never runs them), `--card`, `--awards`, `--zoo`, `--vibe`, `--slow`, `--compare`, `--rules`, `--live`, `--watch`.
- `--json`, `--prom`, `--md`, `--html`, `--ascii`, `--light`, `--share`, `--redact`, `--oneline`, `--check` with budget limits and `--notify`, `--snippet launchd|cron|tmux|zsh|statusline`, `--completions bash|zsh`.

**Trust**
- `--selftest` (222 checks), `--checksum`, `--capture` (masks private words) and `--from FILE` to replay a process list on another machine. `tests/` has a generated test of about 1,300 command lines, a random process-tree test, a live end-to-end test and a recorder for real launches. CI runs them on macOS 15 (Apple silicon and Intel).
- Tested on one Mac so far. If it misses an agent on yours, send `bash yare-doctor.sh --capture` output in an issue.

Read-only: no network, no files written, nothing stopped (the optional `--notify` shows a macOS notification). One bash script that works with the bash that ships with macOS (3.2).
