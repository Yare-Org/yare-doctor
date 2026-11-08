import sys
rows=[l.rstrip('\n') for l in open(sys.argv[1])]; marker=sys.argv[2]
par={}; line={}
for l in rows:
    p=l.split(None,8)
    if len(p)<8: continue
    par[p[0]]=p[1]; line[p[0]]=l
cand=[p for p,l in line.items() if marker in l and 'run_pty' not in l and 'tree_only' not in l]
if not cand: print('NO PROCESS matched', marker); sys.exit(1)
roots=[p for p in cand if par[p] not in cand]
keep=set(roots)
ch=True
while ch:
    ch=False
    for p,pp in par.items():
        if pp in keep and p not in keep: keep.add(p); ch=True
out=[]
for p in keep:
    parts=line[p].split(None,2); parts[1]='1' if p in roots else par[p]; out.append(' '.join(parts))
sys.stdout.write('\n'.join(out)+'\n')
