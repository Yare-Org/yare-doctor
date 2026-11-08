# Changelog

Versions follow [semver](https://semver.org). The 0.x line means the output format and options can still change.

## 0.1.1 (2026-11-08)

Found by testing against every command line running on a real Mac, about 1,100 generated launch styles and 1,000 random process trees (`tests/`).

- **Fixed: Claude Code sessions started from the Claude desktop app were not detected.** The app runs its own `claude.app` from `Application Support/Claude/claude-code/VERSION/HASH/`; the report said "No coding agent found running".
- **Fixed: false sessions.** `node server.js --name claude` or `python3 report.py --agent codex` counted as an agent session, because a flag's value was read as the program. Only the script or module an interpreter runs counts now.
- **Fixed: the Codex desktop app was shown as "VS Code"**, and apps with "rider", "idea" and similar inside their name were shown as JetBrains.
- **Fixed: `--capture` leaked and lost information.** It kept the first words of every command verbatim (a password or URL could be in them) and a replay with `--from` lost some sessions. It now keeps the shape of each command and masks everything private; a replay finds the same sessions.
- The share line counts sessions per agent (`claude 4, hermes 1`), not processes. A host app row is no longer shown for a wrapper such as `osascript`. `--why` shortens long paths at a folder boundary. Footer text wraps in narrow terminals. `--tree` says "1 process".
- Self-test: 199 checks (was 177). New `tests/` folder with the generated and random-tree tests.

## 0.1.0 (2026-11-08)

First numbered public release. (Earlier uploads of this script used other numbers; they were withdrawn and this release replaces them.)

- Recognises 22 coding agents, including ones started through node, python, bun, uv or npx, and npm installs that ship `claude.exe`-style binaries.
- Desktop apps (Claude.app, Codex.app, Cursor.app), `--version`, `login`, `mcp` and background daemons (`codex app-server --managed-daemon`, `opencode serve --service`) are not counted as sessions.
- Sessions are numbered oldest first, so labels stay put. The host is found from the app, tmux or ssh.
- Per session: git branch (read from `.git/HEAD`, no git run), MCP servers, network bytes, program version, what it is running now.
- Findings: sessions building in the same folder, stale git locks, a session waiting for a password or login, a spawn storm, two versions of one agent running, an overloaded Mac, VM memory, forgotten sessions, idle and repeated helpers, held ports.
- Views: `--tree`, `--cleanup` (prints kill commands, never runs them), `--card`, `--awards`, `--zoo`, `--vibe`, `--slow`, `--compare`, `--rules`, `--live`, `--watch`, `--why`.
- Output: `--json`, `--prom`, `--md`, `--ascii`, `--light`, `--share`, `--redact`, `--oneline`, `--check` with budget limits, `--completions bash|zsh`.
- Trust: `--selftest` (177 checks), `--checksum`, `--capture` and `--from FILE` to replay a process list on another machine.
- A health score and grade. Works from cron and launchd with an empty environment.

Read-only: no network, no files written, nothing stopped. One bash script that works with the bash that ships with macOS (3.2).
