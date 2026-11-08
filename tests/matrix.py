# Generated detection test: every agent x every way of launching it, plus things that merely mention an agent.
# Usage: python3 scripts/doctor-tests/matrix.py scripts/yare-doctor.sh
import subprocess, json, sys, tempfile, os
script = sys.argv[1] if len(sys.argv) > 1 else 'yare-doctor.sh'
tmp = tempfile.mkdtemp()
# agent -> (binary names, npm/pypi package path fragment used in node_modules or site-packages, extra real shapes)
A = {
 'claude':      ('claude',       '@anthropic-ai/claude-code/cli.js'),
 'codex':       ('codex',        '@openai/codex/bin/codex.js'),
 'gemini':      ('gemini',       '@google/gemini-cli/dist/index.js'),
 'opencode':    ('opencode',     'opencode-ai/bin/opencode'),
 'aider':       ('aider',        None),
 'cursor-agent':('cursor-agent', None),
 'amp':         ('amp',          '@sourcegraph/amp/dist/main.js'),
 'goose':       ('goose',        None),
 'crush':       ('crush',        '@charmland/crush/bin/crush'),
 'droid':       ('droid',        None),
 'qwen':        ('qwen',         '@qwen-code/qwen-code/cli.js'),
 'kiro-cli':    ('kiro-cli',     None),
 'copilot':     ('copilot',      '@github/copilot/index.js'),
 'auggie':      ('auggie',       '@augmentcode/auggie/augment.mjs'),
 'cline':       ('cline',        None),
 'plandex':     ('plandex',      None),
 'openhands':   ('openhands',    None),
 'kimi':        ('kimi',         None),
 'kilo':        ('kilo',         '@kilocode/cli/bin/kilo'),
}
cases = []  # (expected, command)
H = '/Users/me'
for ag,(b,pkg) in A.items():
    for form in ['%s', '/opt/homebrew/bin/%s', '/usr/local/bin/%s', H+'/.local/bin/%s', H+'/.npm-global/bin/%s', H+'/.bun/bin/%s', '/opt/homebrew/bin/%s --resume', '%s -p "fix the failing test"', '%s --dangerously-skip-permissions']:
        if ag in ('goose',): form = form.replace('%s','%s session') if '--' not in form else None
        if form is None: continue
        cases.append((ag, form % b))
    for interp in ['node', '/opt/homebrew/bin/node', '/usr/local/bin/node --max-old-space-size=8192', 'bun']:
        if pkg: cases.append((ag, '%s %s/.nvm/versions/node/v22.1.0/lib/node_modules/%s' % (interp, H, pkg)))
        cases.append((ag, '%s /opt/homebrew/bin/%s' % (interp, b) if ag != 'goose' else '%s /opt/homebrew/bin/goose session' % interp))
    for py in ['python3', H+'/venv/bin/python', '/opt/homebrew/bin/python3.12']:
        cases.append((ag, '%s %s/venv/bin/%s' % (py, H, b) if ag != 'goose' else '%s %s/venv/bin/goose session' % (py, H)))
    # runners (npx/bunx/uvx), with the package name as published
    PK={'claude':'@anthropic-ai/claude-code','codex':'@openai/codex','gemini':'@google/gemini-cli','opencode':'opencode-ai','amp':'@sourcegraph/amp','crush':'@charmland/crush','qwen':'@qwen-code/qwen-code','copilot':'@github/copilot','auggie':'@augmentcode/auggie','kilo':'@kilocode/cli'}
    sub = ' session' if ag == 'goose' else ''
    cases.append((ag, 'uvx %s%s' % (b, sub)))
    cases.append((ag, 'npx -y %s%s' % (PK.get(ag, b), sub)))
    cases.append((ag, 'bunx %s@latest%s' % (PK.get(ag, b), sub)))
# negatives: things that mention an agent but are not a session
neg = []
for ag,(b,pkg) in A.items():
    neg += [
     '%s --version' % b, '%s --help' % b, '%s -h' % b, '%s login' % b, '%s logout' % b, '%s update' % b, '%s mcp list' % b,
     'tail -f /var/log/%s.log' % b, 'vim %s.md' % b, 'grep -r %s /Users/me/src' % b, 'cat /Users/me/.%s/config.toml' % b,
     'less /Users/me/notes/%s.txt' % b, 'man %s' % b, 'git clone https://github.com/example/%s.git' % b,
     'brew upgrade %s' % b, 'brew install %s' % b, 'npm install -g %s' % (pkg.split('/bin')[0].split('/cli')[0].split('/dist')[0].split('/index')[0].split('/augment')[0] if pkg else b),
     'pip install %s' % b, 'open -a %s' % b, 'ssh devbox %s' % b, 'which %s' % b, 'cd /Users/me/code/%s && ls' % b,
     'node /Users/me/app/server.js --name %s' % b, 'python3 /Users/me/tools/report.py --agent %s' % b,
     '/bin/zsh -c echo %s' % b, 'rg %s' % b, 'code /Users/me/projects/%s' % b, 'ps aux | grep %s' % b, 'kill $(pgrep %s)' % b,
     'sh -c "%s --version"' % b, 'docker run --rm example/%s' % b,
     '/Users/me/projects/%s/node_modules/.bin/vite' % b, '/Users/me/projects/%s-demo/server' % b, '/Applications/%s.app/Contents/MacOS/%s' % (b.title(), b.title()),
     '/Applications/%s.app/Contents/Frameworks/%s Helper.app/Contents/MacOS/%s Helper --type=renderer' % (b.title(), b.title(), b.title()),
     'tmux new -s %s' % b, 'tmux attach -t %s' % b, 'xcodebuild -scheme %s build' % b,
    ]
for c in neg: cases.append(('-', c))
# put each case on its own age so results can be matched back
lines = []
for i,(exp,c) in enumerate(cases):
    secs = 5000 + i * 7          # distinct, spread so no two get the same age
    et = '%02d:%02d:%02d' % (secs//3600, (secs%3600)//60, secs%60)
    lines.append('%d 1 S 0.0 1000 %s 00:00.10 %s' % (20000+i, et, c))
open(os.path.join(tmp,'procs.txt'),'w').write('\n'.join(lines)+'\n')
out = subprocess.run(['bash', script, '--from', os.path.join(tmp,'procs.txt'), '--json'], capture_output=True, text=True).stdout
d = json.loads(out)
got = {s['age_seconds']: s['label'].split('#')[0] for s in d['sessions']}
bad = 0; tot = 0; fp = fn = wrong = 0
for i,(exp,c) in enumerate(cases):
    secs = 5000 + i * 7
    g = got.get(secs, '-'); tot += 1
    if g != exp:
        bad += 1
        kind = 'FALSE-POSITIVE' if exp == '-' else ('MISSED' if g == '-' else 'WRONG-AGENT')
        if exp == '-': fp += 1
        elif g == '-': fn += 1
        else: wrong += 1
        print('%-15s expected %-12s got %-12s  %s' % (kind, exp, g, c))
print('\n%d cases, %d wrong (%d false positives, %d missed, %d wrong agent)' % (tot, bad, fp, fn, wrong))

sys.exit(1 if bad else 0)
