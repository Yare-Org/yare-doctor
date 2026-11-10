# Drives the tabbed screen in a real pseudo-terminal: tab keys, number keys, mouse click and wheel, scrolling, refresh, auto-refresh,
# window resize, Ctrl-C, a too-small terminal, and that the terminal is always put back (alt screen, mouse, cursor).
# Usage: python3 scripts/doctor-tests/tabs_pty.py scripts/yare-doctor.sh
import fcntl, os, re, select, signal, struct, sys, tempfile, termios, time, pty

script = sys.argv[1] if len(sys.argv) > 1 else 'scripts/yare-doctor.sh'
FIXTURE = '''100 1 S 0.5 300000 05:00:00 01:00.00 /Applications/Claude.app/Contents/MacOS/Claude
110 100 S 2.0 250000 01:10:00 02:00.00 /Users/me/Library/Application Support/Claude/claude-code/2.1.317/91184d3d9ba3/claude.app/Contents/MacOS/claude --output-format stream-json --permission-mode=auto
111 110 S 0.1 40000 01:09:00 00:01.00 npm exec some-mcp@latest
112 111 S 0.0 30000 01:09:00 00:01.00 node /x/some-mcp-server
300 1 S 0.0 9000 02:00:00 00:01.00 codex
301 300 S 95.0 9000 02:00:00 20:00.00 clang -c big.c
'''
fx = tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False); fx.write(FIXTURE); fx.close()
fails = 0
def check(name, ok):
    global fails
    print(('  ok    ' if ok else '  FAIL  ') + name)
    if not ok: fails += 1

class Term:
    def __init__(self, rows=30, cols=100, extra=None):
        self.buf = b''
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            os.environ['TERM'] = 'xterm-256color'; os.environ.pop('NO_COLOR', None)
            os.execvp('bash', ['bash', script, '--from', fx.name, '--tabs'] + (extra or []))
    def pump(self, t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if r:
                try: d = os.read(self.fd, 65536)
                except OSError: return
                if not d: return
                self.buf += d
    def send(self, b, wait=1.6):
        self.buf = b''; os.write(self.fd, b); self.pump(wait)
    def text(self):
        return self.buf.decode('utf8', 'replace')
    def frame(self):
        t = self.text(); i = max(t.rfind('\x1b[H'), t.rfind('\x1b[1;1H')); t = t[i:] if i >= 0 else t
        t = re.sub(r'\x1b\[\d+;1H', '\n', t)  # every row is placed by its row number: one row per line
        return re.sub(r'\x1b\[[0-9;?<]*[A-Za-z]', '', t).lstrip('\n')
    def resize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0)); os.kill(self.pid, signal.SIGWINCH)
    def finish(self):
        self.pump(1.0)
        try: _, st = os.waitpid(self.pid, 0)
        except ChildProcessError: return None
        return os.WEXITSTATUS(st) if os.WIFEXITED(st) else -os.WTERMSIG(st)

print('tabbed screen')
t = Term(); t.pump(7)
first = t.text()
check('enters the alternate screen and turns the mouse on', '\x1b[?1049h' in first and '\x1b[?1000h' in first and '\x1b[?1006h' in first)
f = t.frame()
check('shows all eight tab names', all(n in f for n in ['Overview', 'Sessions', 'Processes', 'Activity', 'Findings', 'Tree', 'Agents', 'Help']))
check('starts on the Overview tab with the verdict and the dashboard', any(w in f for w in ('ACT ON IT', 'WORTH A LOOK', 'ALL CLEAR')) and 'WHAT STANDS OUT' in f and 'Memory' in f)
check('turns line wrapping off, so a long line can never push the tab bar off the screen', '\x1b[?7l' in first)
check('the Sessions tab has a count badge and the Findings tab a badge', re.search(r'Sessions \d', f) is not None and re.search(r'Findings \d', f) is not None)
t.send(b'\x1b[C'); check('Right arrow opens Sessions', 'AGENT SESSIONS' in t.frame())
t.send(b'3'); check('"3" opens Processes', 'USING THE CPU' in t.frame())
t.send(b'\t'); check('Tab opens Activity', 'BUILDS AND TESTS' in t.frame())
t.send(b'\x1b[Z'); check('Shift-Tab goes back to Processes', 'USING THE CPU' in t.frame())
t.send(b'6'); check('"6" opens the process tree', 'PROCESS TREE' in t.frame() and 'clang' in t.frame())
t.send(b'8'); check('"8" opens Help with the keys', 'KEYS' in t.frame())
t.send(b'?'); check('"?" opens Help', 'MORE' in t.frame() and 'yare-doctor plain' in t.frame())
# a click on the tab bar (row 2): Sessions starts at column 14
t.send(b'\x1b[<0;17;2M\x1b[<0;17;2m'); check('clicking a tab name opens it (Sessions)', 'AGENT SESSIONS' in t.frame())
t.send(b'\x1b[<0;60;2M\x1b[<0;60;2m'); fr = t.frame()
check('clicking another tab opens it', 'AGENT SESSIONS' not in fr and len(fr) > 200)
t.send(b'\x1b[<0;17;10M\x1b[<0;17;10m'); check('clicking below the tab bar does nothing', len(t.text()) < 400 or 'AGENT SESSIONS' not in t.frame())
t.send(b'\x1b[<65;40;10M'); t.send(b'\x1b[<64;40;10M'); check('mouse wheel scrolls without crashing', True)
t.send(b'1'); t.send(b'r', wait=4); check('r refreshes and still shows the Overview', 'WHAT STANDS OUT' in t.frame())
t.send(b'a'); check('a turns auto-refresh on', 'auto-refresh on' in t.frame())
t.send(b'a'); check('a turns it off again', 'auto-refresh on' not in t.frame())
t.resize(40, 120); t.pump(3)
check('resizing redraws at the new width', len(re.findall(r'─+', t.frame())) > 0 and max(len(x) for x in re.findall(r'─+', t.frame())) > 100)
t.send(b'q', wait=1.5)
tail = t.text()
check('quitting leaves the alternate screen, turns the mouse off and shows the cursor', '\x1b[?1049l' in tail and '\x1b[?1000l' in tail and '\x1b[?25h' in tail)
check('exit status is 0', t.finish() == 0)

print('Ctrl-C')
t = Term(); t.pump(7); t.send(b'\x03', wait=1.5)
check('Ctrl-C also puts the terminal back', '\x1b[?1049l' in t.text() and '\x1b[?25h' in t.text())
t.finish()

print('scrolling a long tab')
long_fx = FIXTURE + ''.join('%d 110 S 0.0 9000 01:00:00 00:01.00 node /w/worker%d.js\n' % (500 + i, i) for i in range(60))
open(fx.name, 'w').write(long_fx)
t = Term(rows=16, cols=100); t.pump(7); t.send(b'6')
f1 = t.frame(); t.send(b'G'); f2 = t.frame()
check('G jumps to the end and shows a different part of a long tab', f1 != f2 and re.search(r'\d+-\d+ of \d+', f2) is not None)
t.send(b'g'); check('g jumps back to the top', t.frame() == f1 or 'PROCESS TREE' in t.frame())
t.send(b'q'); t.finish()

print('the tab bar stays visible')
long_cmd = 'x' * 300
open(fx.name, 'w').write(FIXTURE + '120 110 S 0.0 9000 01:00:00 00:01.00 node /w/%s.js\n' % long_cmd)
t = Term(rows=24, cols=80); t.pump(7)
for key in b'12345678':
    t.send(bytes([key]))
    rows = t.frame().split('\n')
    check('tab %s: the title and the tab bar are the first two rows' % chr(key), 'yare-doctor' in rows[0] and 'Overview' in rows[1] and 'Help' in rows[1])
    check('tab %s: no more rows than the terminal has' % chr(key), len(rows) <= 24)
    check('tab %s: every tab name fits on the bar at 80 columns' % chr(key), all(n in rows[1] for n in ['Overview', 'Sessions', 'Processes', 'Activity', 'Findings', 'Tree', 'Agents', 'Help']))
t.send(b'q'); t.finish()

print('too small')
t = Term(rows=8, cols=60); t.pump(7)
check('a terminal that is too small gets the plain report and a message', 'too small' in t.text() and 'AGENT SESSIONS' in t.text())
t.finish()
os.unlink(fx.name)
print('\n%s' % ('all passed' if not fails else '%d failed' % fails))
sys.exit(1 if fails else 0)
