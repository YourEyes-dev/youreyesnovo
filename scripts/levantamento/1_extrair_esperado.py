import subprocess, re, glob, os, hashlib, json
PS=['psql','-h','/tmp/rs','-p','55441','-U','postgres','-X','-A','-t','-F','\t']
def q(sql):
    r=subprocess.run(PS+['-c',sql],capture_output=True,text=True)
    if r.returncode: raise SystemExit(r.stderr)
    return [l for l in r.stdout.split('\n') if l!='']
EXT="NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid=%s AND d.deptype='e')"
# tabelas + rls + md5 das colunas
tab=q("""select c.relname, c.relrowsecurity::int,
 (select md5(string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::int, ',' order by a.attname))
    from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 (select count(*) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','p') and """+EXT%'c.oid'+" order by 1")
trig=q("select t.tgname||'@'||c.relname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal order by 1")
views=q("select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('v','m') and "+EXT%'c.oid'+" order by 1")
cron=q("select jobname from cron.job order by 1")
enums=q("select t.typname||'.'||e.enumlabel from pg_enum e join pg_type t on t.oid=e.enumtypid join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' order by 1")
pol=q("select tablename||'.'||policyname from pg_policies where schemaname='public' order by 1")
idx=q("select indexname from pg_indexes where schemaname='public' order by 1")
con=q("select c.conname||'@'||cl.relname from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=cl.relnamespace where n.nspname='public' and c.contype in ('c','u','f') order by 1")
fn=q("select p.proname||'('||pg_get_function_identity_arguments(p.oid)||')', left(md5(p.prosrc),8) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and "+EXT%'p.oid'+" order by 1")
# carimbo da ultima migration que define cada funcao
rx=re.compile(r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?(\w+)"?\s*\(',re.I)
last={}
for f in sorted(glob.glob(''+os.environ.get('RAIZ','.')+'/supabase/migrations/*.sql')):
    st=os.path.basename(f)[:14]
    for m in rx.finditer(open(f,errors='ignore').read()): last[m.group(1).lower()]=st
fnl=[]
for l in fn:
    sig,h=l.split('\t'); nome=sig.split('(')[0]
    fnl.append(f"{sig}={h}@{last.get(nome.lower(),'0')[2:12]}")
def lit(lines):
    s='\n'.join(lines)
    assert "'" not in s, "aspas simples"
    return "'"+s+"'"
data=dict(tab=['|'.join(l.split('\t')[:3]) for l in tab], tabn=[l.split('\t')[0]+'='+l.split('\t')[3] for l in tab],
 trig=trig,views=views,cron=cron,enums=enums,pol=pol,idx=idx,con=con,fn=fnl)
json.dump({k:len(v) for k,v in data.items()},open('/tmp/rs/out/contagem.json','w'))
json.dump(data,open('/tmp/rs/out/fingerprint.json','w'))
print({k:len(v) for k,v in data.items()}, sum(len(lit(v)) for v in data.values()))
for k,v in data.items(): print(k,len(lit(v)))
