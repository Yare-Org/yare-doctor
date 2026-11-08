# Random process forests (agents nested in agents, helpers, orphans, shuffled pids) checked against an independent oracle.
# Usage: python3 scripts/doctor-tests/forest.py [seed] [forests] [path to yare-doctor.sh]
import random, subprocess, json, sys, tempfile, os
S=sys.argv[3] if len(sys.argv)>3 else 'yare-doctor.sh'
TMP=os.path.join(tempfile.mkdtemp(),'forest.txt')
AG=['claude','codex','gemini','opencode','aider','amp','kimi']
HELP=['node /x/helper.js','zsh -l','sleep 100','python3 /y/tool.py','npm exec foo','/usr/bin/git status','node /z/mcp-server.js']
random.seed(int(sys.argv[1]) if len(sys.argv)>1 else 1)
bad=0; trials=int(sys.argv[2]) if len(sys.argv)>2 else 150
for t in range(trials):
    n=random.randint(5,70)
    pids=random.sample(range(100,99999),n)
    parent={}; kind={}; cmd={}
    for i,p in enumerate(pids):
        parent[p]= 1 if i==0 or random.random()<0.12 else random.choice(pids[:i])
        if random.random()<0.22:
            a=random.choice(AG); kind[p]=a; cmd[p]=a+' --resume'
        else:
            kind[p]=None; cmd[p]=random.choice(HELP)
    ages={p:random.randint(60,500000) for p in pids}
    # ensure parents are older than children (real life), and ages distinct
    used=set()
    def order():
        return None
    # assign age so child age <= parent age
    done={}
    def age(p):
        if p in done: return done[p]
        par=parent[p]
        mx = age(par) if par in parent else 600000
        a=random.randint(60, max(61, mx-1)) if mx>61 else 60
        while a in used: a-=1
        used.add(a); done[p]=a; return a
    sys.setrecursionlimit(10000)
    for p in pids: age(p)
    lines=[]
    for p in pids:
        et=done[p]; h=et//3600; m=(et%3600)//60; s=et%60
        lines.append('%d %d S 0.0 1000 %02d:%02d:%02d 00:00.10 %s'%(p,parent[p],h,m,s,cmd[p]))
    random.shuffle(lines)
    open(TMP,'w').write('\n'.join(lines)+'\n')
    # oracle
    def top(p):
        res=None; q=p
        while q in parent:
            if kind[q]: res=q
            q=parent[q]
        return res
    groups={}
    for p in pids:
        tp=top(p)
        if tp: groups.setdefault(tp,[]).append(p)
    exp={}
    byagent={}
    for tp in groups: byagent.setdefault(kind[tp],[]).append(tp)
    for a,l in byagent.items():
        l.sort(key=lambda p:-done[p])   # oldest first
        for i,tp in enumerate(l): exp['%s#%d'%(a,i+1)]=len(groups[tp])
    out=subprocess.run(['bash',S,'--from',TMP,'--json'],capture_output=True,text=True).stdout
    try: d=json.loads(out)
    except Exception as e:
        print('trial',t,'JSON error',e); bad+=1; continue
    got={x['label']:x['processes'] for x in d['sessions']}
    if got!=exp:
        bad+=1
        if bad<=3: print('trial',t,'MISMATCH\n exp',sorted(exp.items()),'\n got',sorted(got.items()))
print('forests',trials,'mismatches',bad)

sys.exit(1 if bad else 0)
