# Changelog

Versions follow [semver](https://semver.org). The 0.x line means the output format and options can still change.

## 0.3.1 (2026-11-08)

Kiro, Devin and Plandex were launched for real (the vendors' own downloads, checksum-verified or inspected first, run with a throwaway HOME; Kiro and Plandex from their release archives instead of the installers, which write to /Applications and /usr/local) and their real process lists replayed. All three were detected correctly. With these, every one of the 25 agents has a real launch or a real live sighting behind it (the community `grok-cli` package needs an API key and exits at once; the Grok covered is xAI's). Self-test: 222 checks. No behaviour change.

## 0.3.0 (2026-11-08)

- New `--html`: the whole report as one self-contained web page (light and dark, markup in process names escaped). Print-only: `yare-doctor.sh --html > report.html`. Works with `--redact` and the other views.
- New `--snippet launchd|cron|tmux|zsh|statusline`: configuration to paste so the doctor runs on its own (a notification every 10 minutes, a tmux status bar, the Claude Code status line). It prints; it installs nothing. The launchd plist passes `plutil -lint`.
- Self-test: 217 checks.

## 0.2.1 (2026-11-08)

Five more agents were launched for real (npm and uv installs in throwaway folders, a pseudo-terminal, 7 seconds each) and their actual process lists replayed through the detection: Cline, Jules, Grok (xAI), Junie and OpenHands. That found one more miss:

- **Fixed: Junie was not detected.** It runs as `~/.local/share/junie/versions/VERSION/Applications/junie.app/Contents/MacOS/junie`, an app-bundle binary, which the "desktop apps are hosts" rule skipped. Agents that run from a versioned bundle of their own (this, and the Claude desktop app's `claude.app`) now count.
- Verified against real launches: Cline (a node wrapper, a hidden `.cline` binary and a `--cline-hub-daemon` that all fold into one session; the daemon is not counted as a second session), Jules, Grok, OpenHands.
- Still never launched for real: Kiro, Plandex and Devin (their installers are curl-pipe-bash). The community "grok-cli" package needs an API key and exits at once.
- `tests/launch_in_pty.py` and `tests/tree_only.py` record a real launch so it can be replayed. Self-test: 213 checks.

## 0.2.0 (2026-11-08)

- New `--installed`: which coding agents (by name in your PATH and the usual install folders) and agent apps (Claude, Codex, Cursor, Windsurf, Zed, Conductor, Warp, VS Code, T3 Code, Xcode ...) are installed here, and which are running now. Nothing is run.
- New `--sessions`: just the sessions table.
- New `--notify` for `--check`: a macOS notification when there is something to look at or a budget is exceeded, for cron or launchd.
- **Faster:** the network-usage step (`nettop`) waited about 5 seconds on some Macs; a snapshot took 6 s and now takes about 1.4 s.
- `--json` sessions now include `agent` and `pid`.
- Three more agents recognised by program name: Grok, Junie (JetBrains) and Jules. 25 in total. These are matched by name only, not tested against a real launch.
- Self-test: 207 checks (was 199); the generated test has about 1,300 cases.

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
