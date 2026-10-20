-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01j: Ponto: ponto externo, REP-C, certificado, dossie, folha e AEJ
--
-- PARA QUE SERVE
-- Links de ponto externo (compartilhado e individuais, com tokens ficticios), importacoes de AFD de
-- REP-C, certificados digitais, dossie de fiscalizacao, exportacoes para a folha, AEJ das
-- competencias fechadas e comprovantes de registro dos ultimos 15 dias.
--
-- Tenant demo d3e00000-0000-4000-8000-000000000001 (Metalurgica Exemplo Ltda). Nenhum dado real.
-- SQL Editor do projeto de HOMOLOGACAO. Recusa rodar em qualquer outro banco
-- (so aceita a URL de app_config da homologacao ou do teste). Nunca na producao.
-- Idempotente, sem COMMIT, sem criar tabela, gatilhos do sistema continuam ligados.
--
-- ORDEM DE EXECUCAO (cada arquivo e uma colagem independente, sem COMMIT, e roda em menos de 30 s):
--   parte_00_base_empresa_demo.sql           (base: empresa, colaboradores, login)
--   parte_02a / parte_02b                    (recomendado ANTES: pessoas, ferias, atestados, afastamentos)
--   parte_01a_ponto_escalas_instrumentos.sql escalas 44h e 6x2, atribuicoes, feriados, acordo, CCT, regime do banco
--   parte_01b_ponto_marcacoes_mes1.sql       marcacoes e apuracao do 1o mes (3 meses atras)
--   parte_01c_ponto_marcacoes_mes2.sql       marcacoes e apuracao do 2o mes
--   parte_01d_ponto_marcacoes_mes3.sql       marcacoes e apuracao do 3o mes (mes passado)
--   parte_01e_ponto_marcacoes_mes_atual.sql  marcacoes e apuracao do mes corrente, ate hoje
--   parte_01f_ponto_ajustes.sql              solicitacoes de ajuste (pendentes, aprovadas, recusadas)
--   parte_01g_ponto_banco_fechamento.sql     banco de horas, fechamento e espelhos (2 meses mais antigos)
--   parte_01h_ponto_fluxos_gestao.sql        troca de turno, compensacao de falta, excedente, folgas
--   parte_01i_ponto_alertas.sql              alertas CLT e analises sugeridas
--   parte_01j_ponto_externo_arquivos.sql     links de ponto externo, REP-C, certificado, dossie, folha, AEJ
--   parte_01k_analise_jornada.sql            /analise-jornada (analises, alertas, documentos)
-- Todos sao idempotentes (rodar de novo nao duplica) e recusam rodar fora da homologacao/teste.
-- Rodar de novo perto da demonstracao completa os dias novos.
-- ============================================================================

SET lock_timeout = '10s';

DO $trava$
DECLARE
  v_url text;
BEGIN
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url' LIMIT 1);
  IF v_url IS NULL
     OR (v_url NOT ILIKE '%fgsblefvdabgdouipigz%' AND v_url NOT ILIKE '%bmehdgthciuvdbvutsdv%') THEN
    RAISE EXCEPTION
      'RECUSADO: app_config.supabase_url (%) nao e a homologacao nem o teste. Os dados de demonstracao nunca entram em producao.',
      COALESCE(v_url, '(vazio)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Rode antes a parte 00 (base da empresa demo): o tenant demo nao existe.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') THEN
    RAISE EXCEPTION 'Rode antes a parte_01g (banco de horas e fechamento).';
  END IF;
END $trava$;

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

CREATE OR REPLACE FUNCTION public.demo_ponto_rnd(seed text, m integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5(seed), 1, 7))::bit(28)::int) % GREATEST(m, 1)
$fn$;


-- ---------------------------------------------------------------------------
-- (12) Links de ponto externo, REP-C, certificado digital, dossie de fiscalizacao
--      e historico de exportacoes para a folha (tokens e hashes sao ficticios)
-- ---------------------------------------------------------------------------
-- Link compartilhado da empresa (um por tenant) — valido por mais 45 dias
DO $w1$
BEGIN
INSERT INTO public.ponto_links (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, data_expiracao, tipo, tentativas_frustradas, created_at)
SELECT public.demo_id('ponto_link:compartilhado'), 'd3e00000-0000-4000-8000-000000000001',
       '00000000-0000-0000-0000-000000000000', 'Link compartilhado', '',
       md5('demo-ponto-link-compartilhado-metalurgica'), true, now() + interval '45 days', 'compartilhado', 0,
       now() - interval '135 days'
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND tipo = 'compartilhado');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_links nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

-- Links individuais (operadores de chao de fabrica, sem acesso ao sistema)
DO $w2$
BEGIN
INSERT INTO public.ponto_links (id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, data_expiracao, tipo, tentativas_frustradas, bloqueado_ate, created_at)
SELECT public.demo_id('ponto_link:' || s.n), 'd3e00000-0000-4000-8000-000000000001', a.id::text, a.nome_completo, a.cpf,
       md5('demo-ponto-link-individual-' || s.n),
       s.n <> 45,
       CASE WHEN s.n = 45 THEN now() - interval '12 days'
            WHEN s.n = 3 THEN now() + interval '9 days'
            ELSE now() + make_interval(days => 40 + public.demo_ponto_rnd('lnk' || s.n, 130)) END,
       'colaborador',
       CASE WHEN s.n = 17 THEN 5 ELSE 0 END,
       CASE WHEN s.n = 17 THEN now() + interval '40 minutes' END,
       now() - make_interval(days => 20 + public.demo_ponto_rnd('lnkc' || s.n, 100))
FROM generate_series(1, 59) s(n)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
WHERE s.n IN (1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 41, 43, 45, 47) AND a.status = 'concluido'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_links l WHERE l.id = public.demo_id('ponto_link:' || s.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_links nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

-- Importacoes de AFD de REP-C (aba Configuracoes > REP-C)
DO $w3$
BEGIN
INSERT INTO public.ponto_repc_importacoes (
  id, tenant_id, empresa_id, arquivo_nome, tipo_equipamento, fabricante, modelo, numero_serie,
  total_registros, registros_importados, registros_rejeitados, status, erros, importado_por, importado_por_id,
  arquivo_hash, crc_valido, assinatura_valida, cadeia_valida, quarentena, relatorio, created_at, updated_at)
SELECT public.demo_id('ponto_repc:' || v.k), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.arquivo, 'REP-C', 'Fabricante Demo', 'Relógio Eletrônico Modelo X1', '00001.00002.00003.0001',
       v.total, v.imp, v.rej, v.status, v.erros, 'Leiri',
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1),
       md5('demo-afd-' || v.k), v.crc, v.ass, v.cad, v.quarentena, v.relatorio,
       now() - make_interval(days => v.dias), now() - make_interval(days => v.dias)
FROM (VALUES
  (1, 'AFD00001000200030001_portaria_acesso.txt', 1480, 1480, 0, 'concluido', '[]'::jsonb, true, true, true, false,
     '{"resumo": "Arquivo íntegro: CRC, assinatura e cadeia de NSR conferidos."}'::jsonb, 52),
  (2, 'AFD00001000200030001_expedicao.txt', 912, 904, 8, 'concluido',
     '[{"linha": 118, "mensagem": "Colaborador não encontrado para o CPF informado"}, {"linha": 431, "mensagem": "Marcação duplicada no mesmo minuto"}]'::jsonb,
     true, true, true, false, '{"resumo": "8 registros rejeitados; os demais foram importados."}'::jsonb, 24),
  (3, 'AFD00001000200030001_adulterado.txt', 640, 0, 640, 'erro',
     '[{"linha": 1, "mensagem": "Assinatura digital inválida: o arquivo foi alterado após a emissão"}]'::jsonb,
     true, false, false, true, '{"resumo": "Arquivo em quarentena: assinatura e cadeia de NSR não conferem."}'::jsonb, 9)
) AS v(k, arquivo, total, imp, rej, status, erros, crc, ass, cad, quarentena, relatorio, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_repc_importacoes r WHERE r.id = public.demo_id('ponto_repc:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_repc_importacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w3$;

-- Certificados digitais ICP-Brasil (assinatura dos documentos de ponto)
DO $w4$
BEGIN
INSERT INTO public.ponto_certificados_digitais (
  id, tenant_id, empresa_id, certificado_digital_tipo, icp_brasil, titular_nome, titular_documento, numero_serie,
  emissor, fingerprint, valido_de, valido_ate, alerta_antecedencia_dias, ativo)
SELECT public.demo_id('ponto_cert:' || v.k), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'A1', true, 'METALURGICA EXEMPLO LTDA', '98.765.432/0001-02', v.serie, 'AC Demonstração ICP-Brasil (fictícia)',
       upper(md5('demo-cert-' || v.k) || substr(md5('x-demo-cert-' || v.k), 1, 8)),
       (timezone('America/Sao_Paulo', now()))::date + v.de, (timezone('America/Sao_Paulo', now()))::date + v.ate, 30, v.ativo
FROM (VALUES
  (1, '5A3F00D1C2B4E6A7', -150, 215, true),
  (2, '4C21B9E0A7D35F18', -515, -150, false)
) AS v(k, serie, de, ate, ativo)
WHERE NOT EXISTS (SELECT 1 FROM public.ponto_certificados_digitais c WHERE c.id = public.demo_id('ponto_cert:' || v.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_certificados_digitais nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w4$;

-- Dossie de fiscalizacao das competencias fechadas (pecas e hashes do pacote)
DO $w5$
BEGIN
INSERT INTO public.ponto_dossies_fiscalizacao (id, tenant_id, empresa_id, competencia, periodo_ini, periodo_fim, total_pecas, indice, hash_pacote, gerado_em, created_at)
SELECT public.demo_id('ponto_dossie:' || f.competencia), f.tenant_id, f.empresa_id, f.competencia,
       to_date(f.competencia || '-01', 'YYYY-MM-DD'), (to_date(f.competencia || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date,
       p.marc + p.esp + 1,
       jsonb_build_array(
         jsonb_build_object('peca', 'aej', 'quantidade', 1, 'hash', md5('aej' || f.competencia)),
         jsonb_build_object('peca', 'comprovantes', 'quantidade', p.marc, 'hash', md5('comp' || f.competencia)),
         jsonb_build_object('peca', 'espelhos', 'quantidade', p.esp, 'hash', md5('esp' || f.competencia)),
         jsonb_build_object('peca', 'afd_importado', 'quantidade', 1, 'hash', md5('afd' || f.competencia))),
       md5('demo-dossie|' || f.competencia),
       f.data_fechamento + interval '1 day', f.data_fechamento + interval '1 day'
FROM public.ponto_fechamentos f
CROSS JOIN LATERAL (
  SELECT (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = f.tenant_id AND to_char(m.data_marcacao, 'YYYY-MM') = f.competencia)::int AS marc,
         (SELECT count(*) FROM public.ponto_espelhos e WHERE e.tenant_id = f.tenant_id AND e.competencia = f.competencia)::int AS esp
) p
WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_dossies_fiscalizacao d
                  WHERE d.tenant_id = f.tenant_id AND d.competencia = f.competencia);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_dossies_fiscalizacao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w5$;

-- Exportacoes para a folha das competencias fechadas
DO $w6$
BEGIN
INSERT INTO public.ponto_exportacoes_folha (id, tenant_id, empresa_id, competencia, formato, sistema_destino, total_colaboradores, arquivo_nome, status, gerado_por, gerado_por_id, dados_exportados, created_at)
SELECT public.demo_id('ponto_export:' || f.competencia), f.tenant_id, f.empresa_id, f.competencia,
       'xlsx', 'generico', f.total_colaboradores, 'Folha_' || f.competencia || '.xlsx', 'processado', 'Leiri',
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1),
       jsonb_build_object('total', f.total_colaboradores, 'sistema', 'generico'),
       f.data_fechamento + interval '3 hours'
FROM public.ponto_fechamentos f
WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
  AND NOT EXISTS (SELECT 1 FROM public.ponto_exportacoes_folha x WHERE x.id = public.demo_id('ponto_export:' || f.competencia));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_exportacoes_folha nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w6$;

-- ---------------------------------------------------------------------------
-- (12b) Arquivos oficiais: AEJ das competencias fechadas (Portaria MTP 671) e
--       comprovantes de registro das marcacoes dos ultimos 15 dias
-- ---------------------------------------------------------------------------
DO $arquivos$
DECLARE
  v_comp text;
BEGIN
  FOR v_comp IN
    SELECT f.competencia FROM public.ponto_fechamentos f
    WHERE f.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND f.status = 'fechado'
    ORDER BY f.competencia
  LOOP
    BEGIN
      PERFORM public.ponto_gerar_aej('d3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', v_comp);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'AEJ % nao gerado: % (%)', v_comp, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  BEGIN
    PERFORM public.ponto_gerar_comprovante(m.tenant_id, m.id)
    FROM public.ponto_marcacoes m
    WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND m.data_marcacao >= (timezone('America/Sao_Paulo', now()))::date - 15
      AND NOT COALESCE(m.comprovante_gerado, false)
      AND to_char(m.data_marcacao, 'YYYY-MM') NOT IN (
        SELECT f.competencia FROM public.ponto_fechamentos f
        WHERE f.tenant_id = m.tenant_id AND f.status = 'fechado');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Comprovantes nao gerados: % (%)', SQLERRM, SQLSTATE;
  END;
END $arquivos$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS links,
  (SELECT count(*) FROM public.ponto_repc_importacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS repc,
  (SELECT count(*) FROM public.ponto_certificados_digitais WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS certificados,
  (SELECT count(*) FROM public.ponto_dossies_fiscalizacao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS dossies,
  (SELECT count(*) FROM public.ponto_exportacoes_folha WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS exportacoes_folha,
  (SELECT count(*) FROM public.ponto_arquivos_aej WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS aej,
  (SELECT count(*) FROM public.ponto_comprovantes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS comprovantes,
  CASE WHEN (SELECT count(*) FROM public.ponto_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 10 THEN 'OK' ELSE 'CONFERIR' END AS situacao;