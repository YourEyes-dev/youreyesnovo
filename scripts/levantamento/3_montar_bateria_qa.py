import subprocess, os
PS=['psql','-h','/tmp/rs','-p','55441','-U','postgres','-X','-A','-t','-F','|']
def q(sql):
    r=subprocess.run(PS+['-c',sql],capture_output=True,text=True)
    if r.returncode: raise SystemExit(r.stderr)
    return [l for l in r.stdout.split('\n') if l]
G={
 '1_rh_nucleo':['desenvolvimento-performance/mapa-comportamental','jornada-rotina/ferias','jornada-rotina/afastamentos','estrutura-organizacional/colaboradores/admissao','rh-dp/admissao','estrutura-organizacional/colaboradores/desligamento','estrutura-organizacional/colaboradores','saude-ocupacional/atestados'],
 '2_ponto_folha_epi':['jornada-rotina/ponto','financeiro/folha-pagamento','financeiro/decimo-terceiro','jornada-rotina/beneficios','saude-ocupacional/epi'],
 '3_demais_modulos':['estrutura-organizacional/empresa','estrutura-organizacional/estabelecimentos','estrutura-organizacional/cargos','estrutura-organizacional/departamentos','estrutura-organizacional/organograma','estrutura-organizacional/prestadores','seguranca-acesso/perfis','infraestrutura-auth/usuarios-permissoes','infraestrutura-auth/rls','infraestrutura-auth/edge-functions','documentos-governanca/documentos','documentos-governanca/hub-contabil','planejamento-gestao/metas','planejamento-gestao/plano-de-acao','planejamento-gestao/planejamento-estrategico','planejamento-gestao/identidade-estrategica','saude-seguranca/psicossocial','saude-seguranca/compliance-sst','pessoas-cultura/ouvidoria','rede-parceiros/programa-parceiros','rede-parceiros','sistema/central-controle-clientes'],
}
ab={'passou':'p','falhou':'f','nao_implementado':'n','erro':'e'}
os.makedirs('/tmp/rs/out/bateria',exist_ok=True)
for nome,mods in G.items():
    lista=",".join("'%s'"%m for m in mods)
    base=q(f"""with ult as (select distinct on (modulo_path) id, modulo_path from qa_execucoes where modulo_path in ({lista}) order by modulo_path, iniciada_em desc)
     select u.modulo_path||'|'||r.codigo||'|'||case r.situacao when 'passou' then 'p' when 'falhou' then 'f' when 'nao_implementado' then 'n' else 'e' end
     from ult u join qa_resultados r on r.execucao_id=u.id order by 1""")
    lit="'"+"\n".join(base)+"'"; assert "\\" not in lit
    mods_sql=",\n    ".join("'%s'"%m for m in mods)
    sql=f"""-- =====================================================================
-- BATERIA DE QA NA PRODUCAO — parte {nome.split('_')[0]}/3: {nome.split('_',1)[1].replace('_',' ')}
-- Cole no SQL Editor da PRODUCAO, numa aba nova e vazia. Roda as rotinas de teste dos modulos listados.
-- Cada caso roda numa subtransacao que e DESFEITA no fim (nada de dado de cliente fica); o que a bateria
-- grava sao so as tabelas do proprio motor (qa_execucoes, qa_resultados). O resultado compara com o que a
-- main espera (banco montado com as migrations): so aparece o que ficou PIOR na producao.
-- Leia: RESUMO por modulo, depois os casos que passam na main e nao passam aqui.
-- =====================================================================
SET lock_timeout = '10s';

DO $bat$
DECLARE m text;
BEGIN
  FOREACH m IN ARRAY ARRAY[
    {mods_sql}
  ] LOOP
    BEGIN
      PERFORM public.qa_rodar_bateria('manual', m);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'bateria de % falhou: %', m, SQLERRM;
    END;
  END LOOP;
END
$bat$;

WITH base AS MATERIALIZED (
  SELECT split_part(l,'|',1) AS modulo, split_part(l,'|',2) AS codigo, split_part(l,'|',3) AS sit
  FROM unnest(string_to_array({lit}, E'\\n')) l WHERE l <> ''
), ult AS MATERIALIZED (
  SELECT DISTINCT ON (modulo_path) id, modulo_path
  FROM public.qa_execucoes WHERE modulo_path IN ({mods_sql})
  ORDER BY modulo_path, iniciada_em DESC
), prod AS MATERIALIZED (
  SELECT u.modulo_path AS modulo, r.codigo, r.situacao::text AS situacao, r.obtido, r.erro_tecnico
  FROM ult u JOIN public.qa_resultados r ON r.execucao_id = u.id
), resumo AS (
  SELECT 0 AS g, p.modulo AS modulo, 'RESUMO' AS codigo,
         'producao: ' || count(*) || ' casos, ' || count(*) FILTER (WHERE situacao='passou') || ' passou, '
         || count(*) FILTER (WHERE situacao='falhou') || ' falhou, ' || count(*) FILTER (WHERE situacao='erro') || ' erro, '
         || count(*) FILTER (WHERE situacao='nao_implementado') || ' sem rotina' AS situacao,
         'main espera ' || (SELECT count(*) FROM base b WHERE b.modulo = p.modulo AND b.sit='p') || ' passou' AS detalhe
  FROM prod p GROUP BY p.modulo
), piora AS (
  SELECT 1 AS g, b.modulo, b.codigo, p.situacao AS situacao,
         left(coalesce(p.erro_tecnico, p.obtido, ''), 220) AS detalhe
  FROM base b JOIN prod p ON p.modulo = b.modulo AND p.codigo = b.codigo
  WHERE b.sit = 'p' AND p.situacao <> 'passou'
)
SELECT modulo, codigo, situacao, detalhe FROM (
  SELECT * FROM resumo UNION ALL SELECT * FROM piora
) x ORDER BY g, modulo, codigo;
"""
    open(f'/tmp/rs/out/bateria/BAT_{nome}.sql','w').write(sql)
    print(nome,len(sql),len(base))
