# Launch any agent for a few seconds in a pseudo-terminal (with a throwaway HOME) and record the real process list while it runs.
# Usage: FAKEHOME=/tmp/h RUNDIR=/tmp/w OUT=/tmp/name python3 launch_in_pty.py SECONDS /path/to/agent [args]
# Then: python3 tree_only.py /tmp/name.ps agent > /tmp/name.only   and   bash yare-doctor.sh --from /tmp/name.only --json
import pty, os, sys, time, subprocess, signal, select
cmd = sys.argv[2:]; secs = float(sys.argv[1])
env = dict(os.environ, HOME=os.environ['FAKEHOME'], BROWSER='true', NO_COLOR='1', TERM='xterm-256color', CI='')
pid, fd = pty.fork()
if pid == 0:
    os.chdir(os.environ.get('RUNDIR', '.')); os.execvpe(cmd[0], cmd, env)
t0 = time.time(); out = b''
while time.time() - t0 < secs:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try: out += os.read(fd, 65536)
        except OSError: break
# capture the real process tree while it is running
ps = subprocess.run(['ps','-axww','-o','pid=,ppid=,stat=,pcpu=,rss=,etime=,time=,command='], capture_output=True, text=True).stdout
open(os.environ['OUT']+'.ps','w').write(ps)
alive = subprocess.run(['ps','-p',str(pid)],capture_output=True).returncode == 0
print('child alive at capture:', alive)
try: os.kill(pid, signal.SIGTERM)
except Exception: pass
time.sleep(0.5)
try: os.kill(pid, signal.SIGKILL)
except Exception: pass
open(os.environ['OUT']+'.tty','wb').write(out)
