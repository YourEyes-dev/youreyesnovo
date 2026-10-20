-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01f: Ponto: solicitacoes de ajuste
--
-- PARA QUE SERVE
-- Solicitacoes de ajuste de ponto que nascem dos proprios dias do historico (saida esquecida,
-- atraso contestado, falta justificada). Entram pendentes e as mais antigas sao aprovadas ou
-- recusadas pela rotina oficial processar_ajuste_ponto, com o login da demo. Tambem corrige a cor
-- da volta do almoco (o sistema a marca como interjornada).
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
  IF NOT EXISTS (SELECT 1 FROM public.ponto_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Rode antes as partes 01b a 01e (marcacoes e apuracao).';
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


-- Ajuste de cor dos registros: a classificacao CLT automatica trata a volta do almoco
-- como "nova entrada" e a marca de vermelho (interjornada) por causa da saida do almoco do
-- MESMO dia. Aqui so se corrige essa leitura nos registros desta demonstracao, mantendo o
-- vermelho de verdade (menos de 11 h desde a saida do dia anterior).
DO $w1$
BEGIN
UPDATE public.ponto_marcacoes m
   SET classificacao_clt = 'verde'
 WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND m.classificacao_clt = 'vermelho'
   AND m.tipo_marcacao = 'entrada'
   AND EXISTS (SELECT 1 FROM public.ponto_marcacoes p
               WHERE p.tenant_id = m.tenant_id AND p.colaborador_cpf = m.colaborador_cpf
                 AND p.data_marcacao = m.data_marcacao AND p.tipo_marcacao = 'saida'
                 AND p.hora_marcacao < m.hora_marcacao);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_marcacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

-- ---------------------------------------------------------------------------
-- (8) Solicitacoes de ajuste de ponto: nascem dos proprios dias do historico
--     (batida de saida esquecida, atraso contestado, falta justificada).
--     Entram PENDENTES e os mais antigos sao aprovados/recusados pela rotina
--     oficial processar_ajuste_ponto, como o gestor faz na tela.
-- ---------------------------------------------------------------------------
-- Regra de decisao (deterministica): competencias fechadas -> tudo resolvido,
-- mes anterior -> metade resolvida, mes corrente -> quase tudo pendente.
CREATE OR REPLACE FUNCTION public.demo_ponto_decisao(p_id uuid, p_tipo text, p_data date)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT CASE
    WHEN p_tipo = 'inclusao' THEN
      CASE
        WHEN p_data <= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1 THEN 'aprovado'
        WHEN p_data < date_trunc('month', timezone('America/Sao_Paulo', now()))::date
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 55 THEN 'aprovado' ELSE 'pendente' END
        WHEN p_data < (timezone('America/Sao_Paulo', now()))::date - 12
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 25 THEN 'aprovado' ELSE 'pendente' END
        ELSE 'pendente'
      END
    ELSE
      CASE
        WHEN p_data <= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 84 THEN 'aprovado' ELSE 'rejeitado' END
        WHEN p_data < date_trunc('month', timezone('America/Sao_Paulo', now()))::date
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 40 THEN 'aprovado'
                    WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 55 THEN 'rejeitado' ELSE 'pendente' END
        WHEN p_data < (timezone('America/Sao_Paulo', now()))::date - 5
          THEN CASE WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 20 THEN 'aprovado'
                    WHEN public.demo_ponto_rnd(p_id::text || 'dec', 100) < 26 THEN 'rejeitado' ELSE 'pendente' END
        ELSE 'pendente'
      END
  END
$fn$;

DO $w2$
BEGIN
INSERT INTO public.ponto_ajustes (
  id, tenant_id, empresa_id, ponto_diario_id, colaborador_id, colaborador_nome, colaborador_cpf, data_referencia,
  tipo_ajuste, tipo_marcacao, hora_original, hora_solicitada, motivo, status, created_at, created_by_nome,
  justificativa_id, anexos, dia_inteiro, abonar_se_aprovado)
SELECT public.demo_id('ponto_ajuste:' || x.colaborador_cpf || '|' || x.data::text),
       x.tenant_id, x.empresa_id, x.id, x.colaborador_id, x.colaborador_nome, x.colaborador_cpf, x.data,
       x.tipo_ajuste, x.tipo_marcacao, x.hora_original, x.hora_solicitada, x.motivo, 'pendente',
       LEAST(now() - interval '3 hours', ((x.data + 1)::timestamp + time '08:10') AT TIME ZONE 'America/Sao_Paulo'),
       x.colaborador_nome,
       x.justificativa_id, x.anexos, x.dia_inteiro, x.abonar
FROM (
  SELECT d.*,
         CASE WHEN d.status = 'incompleto' THEN 'inclusao'
              WHEN d.status = 'atraso' THEN 'correcao'
              ELSE 'justificativa' END AS tipo_ajuste,
         CASE WHEN d.status = 'incompleto' THEN 'saida' WHEN d.status = 'atraso' THEN 'entrada' END AS tipo_marcacao,
         CASE WHEN d.status = 'atraso' THEN d.entrada END AS hora_original,
         CASE WHEN d.status = 'incompleto'
                THEN (esc.cfg ->> 'saida')::time + make_interval(mins => public.demo_ponto_rnd(d.id::text || 'hs', 9))
              WHEN d.status = 'atraso'
                THEN (esc.cfg ->> 'entrada')::time + make_interval(mins => public.demo_ponto_rnd(d.id::text || 'hs', 4))
         END AS hora_solicitada,
         CASE
           WHEN d.status = 'incompleto' THEN
             (ARRAY['Esqueci de registrar a saída ao final do expediente.',
                    'Celular sem bateria na hora de sair; saí no horário normal.',
                    'Saí às pressas por urgência familiar e não bati a saída.',
                    'O aplicativo não carregou na saída; informo o horário correto.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 4)]
           WHEN d.status = 'atraso' THEN
             (ARRAY['Cheguei no horário, mas a fila na portaria atrasou o registro.',
                    'Trânsito interditado na BR-101; avisei o líder por mensagem.',
                    'Registrei a entrada após guardar meus pertences; já estava no posto às 08:00.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 3)]
           ELSE
             (ARRAY['Atestado médico apresentado ao RH (consulta de urgência).',
                    'Consulta com especialista agendada pelo plano de saúde; comprovante anexo.',
                    'Acompanhamento de filho menor em consulta pediátrica; declaração anexa.'])[1 + public.demo_ponto_rnd(d.id::text || 'mt', 3)]
         END AS motivo,
         CASE WHEN d.status = 'falta'
              THEN (SELECT j.id FROM public.ponto_justificativas j
                    WHERE j.tenant_id = d.tenant_id AND j.empresa_id IS NULL
                      AND j.codigo = CASE WHEN public.demo_ponto_rnd(d.id::text || 'jt', 100) < 60
                                          THEN 'FALTA_JUSTIFICADA_ABONADA' ELSE 'CONSULTA_MEDICA' END
                    LIMIT 1)
         END AS justificativa_id,
         CASE WHEN d.status = 'falta'
              THEN jsonb_build_array(jsonb_build_object(
                     'nome', 'comprovante-' || to_char(d.data, 'YYYYMMDD') || '.pdf',
                     'url', 'demo/anexos/ponto/comprovante-' || to_char(d.data, 'YYYYMMDD') || '.pdf',
                     'tamanho', 184320, 'tipo', 'application/pdf'))
              ELSE '[]'::jsonb END AS anexos,
         (d.status = 'falta') AS dia_inteiro,
         (d.status = 'falta') AS abonar
  FROM public.ponto_diario d
  LEFT JOIN LATERAL (
    SELECT e.dias_config -> (ARRAY['domingo','segunda','terca','quarta','quinta','sexta','sabado'])[EXTRACT(DOW FROM d.data)::int + 1] AS cfg
    FROM public.ponto_escala_atribuicoes pa
    JOIN public.ponto_escalas e ON e.id = pa.escala_id
    WHERE pa.tenant_id = d.tenant_id AND pa.colaborador_id = d.colaborador_id::text
      AND pa.data_inicio <= d.data AND (pa.data_fim IS NULL OR pa.data_fim >= d.data)
    ORDER BY pa.data_inicio DESC LIMIT 1
  ) esc ON true
  WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND d.data < (timezone('America/Sao_Paulo', now()))::date
    AND (
      d.status = 'incompleto'
      OR (d.status = 'atraso' AND public.demo_ponto_rnd(d.id::text || 'cor', 100) < 20)
      OR (d.status = 'falta' AND d.data < (timezone('America/Sao_Paulo', now()))::date - 1
          AND public.demo_ponto_rnd(d.id::text || 'jus', 100) < 30)
    )
) x
WHERE (x.status <> 'falta' OR x.justificativa_id IS NOT NULL)
  AND (x.status NOT IN ('incompleto', 'atraso') OR x.hora_solicitada IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.ponto_ajustes a WHERE a.id = public.demo_id('ponto_ajuste:' || x.colaborador_cpf || '|' || x.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_ajustes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

-- Decisao do gestor: a mesma rotina da tela (aprovar / recusar), com o login da demo.
DO $ajuste$
DECLARE
  v_uid uuid;
  r record;
  v_dec text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NULL THEN
    RAISE NOTICE 'Login leirinuernberg@gmail.com nao existe neste ambiente: os ajustes ficam todos pendentes.';
    RETURN;
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  FOR r IN
    SELECT a.id, a.tipo_ajuste, a.data_referencia
    FROM public.ponto_ajustes a
    WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND a.status = 'pendente'
      AND a.id = public.demo_id('ponto_ajuste:' || a.colaborador_cpf || '|' || a.data_referencia::text)
    ORDER BY a.data_referencia, a.id
  LOOP
    v_dec := public.demo_ponto_decisao(r.id, r.tipo_ajuste, r.data_referencia);
    IF v_dec = 'pendente' THEN
      CONTINUE;
    END IF;
    BEGIN
      PERFORM public.processar_ajuste_ponto(
        r.id, v_dec = 'aprovado',
        CASE WHEN v_dec = 'aprovado'
             THEN (ARRAY['Conferido com o gestor imediato e com o registro de portaria.',
                         'Aprovado conforme documento apresentado ao RH.',
                         'Horário confirmado pelo líder do setor.'])[1 + public.demo_ponto_rnd(r.id::text || 'ob', 3)]
             ELSE (ARRAY['Sem comprovação do horário informado. Procure o RH com o documento.',
                         'Divergência com o registro da portaria; solicitação não acatada.'])[1 + public.demo_ponto_rnd(r.id::text || 'ob', 2)]
        END);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Ajuste % nao processado: % (%)', r.id, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  PERFORM set_config('request.jwt.claims', '', true);
END $ajuste$;

-- Datas de aprovacao coerentes com a data do pedido (a rotina carimba "agora").
DO $w3$
BEGIN
UPDATE public.ponto_ajustes a
   SET data_aprovacao = LEAST(now() - interval '1 hour',
         a.created_at + interval '1 day' + make_interval(mins => public.demo_ponto_rnd(a.id::text || 'da', 360)))
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND a.data_aprovacao IS NOT NULL
   AND a.id = public.demo_id('ponto_ajuste:' || a.colaborador_cpf || '|' || a.data_referencia::text);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco ponto_ajustes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w3$;
DROP FUNCTION IF EXISTS public.demo_ponto_decisao(uuid, text, date);

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'pendente') AS ajustes_pendentes,
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'aprovado') AS ajustes_aprovados,
  (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'rejeitado') AS ajustes_recusados,
  CASE WHEN (SELECT count(*) FROM public.ponto_ajustes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 20 THEN 'OK' ELSE 'CONFERIR' END AS situacao;