# yare-doctor detection tests

Run from the repo root. Both need only python3 and the script; neither touches your processes (they replay made-up process lists with `--from`).

| Test | What it checks |
|---|---|
| `python3 tests/matrix.py yare-doctor.sh` | About 1,100 generated command lines: 19 agents launched 20+ ways (bare, full path, node, bun, python, venv, uvx, npx, bunx), and 40 things per agent that only mention it (`--version`, `login`, `tail -f x.log`, `npm install -g`, `node server.js --name claude`...) that must not count |
| `python3 tests/forest.py 1 200 yare-doctor.sh` | Random process trees (agents inside agents, orphans, shuffled pids) compared with an independent calculation of which processes belong to which session |

`bash yare-doctor.sh --selftest` runs the fixed cases (real process lists recorded from 16 agents, hosts, formats, fuzzing, privacy).
