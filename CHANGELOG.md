# Changelog

Versions follow [semver](https://semver.org). The 0.x line means the output format and options can still change.

## 0.1.0 (2026-11-08)

First numbered public release. (Earlier uploads of this script used other numbers; they were withdrawn and this release replaces them.)

- Recognises 22 coding agents, including ones started through node, python, bun, uv or npx, and npm installs that ship `claude.exe`-style binaries.
- Desktop apps (Claude.app, Codex.app, Cursor.app), `--version`, `login`, `mcp` and background daemons (`codex app-server --managed-daemon`, `opencode serve --service`) are not counted as sessions.
- Sessions are numbered oldest first, so labels stay put. The host is found from the app, tmux or ssh.
- Per session: git branch (read from `.git/HEAD`, no git run), MCP servers, network bytes, program version, what it is running now.
- Findings: sessions building in the same folder, stale git locks, a session waiting for a password or login, a spawn storm, two versions of one agent running, an overloaded Mac, VM memory, forgotten sessions, idle and repeated helpers, held ports.
- Views: `--tree`, `--cleanup` (prints kill commands, never runs them), `--card`, `--awards`, `--zoo`, `--vibe`, `--slow`, `--compare`, `--rules`, `--live`, `--watch`, `--why`.
- Output: `--json`, `--prom`, `--md`, `--ascii`, `--light`, `--share`, `--redact`, `--oneline`, `--check` with budget limits, `--completions bash|zsh`.
- Trust: `--selftest` (about 180 checks), `--checksum`, `--capture` and `--from FILE` to replay a process list on another machine.
- A health score and grade. Works from cron and launchd with an empty environment.

Read-only: no network, no files written, nothing stopped. One bash script that works with the bash that ships with macOS (3.2).
