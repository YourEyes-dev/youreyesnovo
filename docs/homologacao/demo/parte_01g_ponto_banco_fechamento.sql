-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01g: Ponto: banco de horas e fechamento
--
-- PARA QUE SERVE
-- Banco de horas (apuracao oficial, saldo de implantacao, folga compensada, credito e debito
-- manuais) e fechamento das competencias dos 2 meses mais antigos pelo mesmo caminho do botao
-- Fechar periodo (fechamento, espelhos com ciencia/ressalva e regra RN29). O mes passado e o
-- corrente ficam abertos. Competencia que ainda tem pendencia critica nao e fechada (aviso).
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


-- ---------------------------------------------------------------------------
-- (9) Banco de horas e fechamento de competencias
--     Para cada mes, do mais antigo ao atual: saldo de implantacao (so no 1o mes),
--     apuracao oficial, lancamentos manuais (folga compensada, credito, debito) e
--     reapuracao, os meses mais antigos (ate 2 meses atras) sao FECHADOS pelo mesmo
--     caminho do botao "Fechar periodo": fechamento + espelhos + regra RN29.
--     Competencias ja fechadas numa execucao anterior nao sao tocadas.
-- ---------------------------------------------------------------------------
DO $banco$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_uid uuid;
  v_comp text;
  v_ini date;
  v_fim date;
  v_primeira text := to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months', 'YYYY-MM');
  v_ate_fechar text := to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '2 months', 'YYYY-MM');
  v_cpf text;
  v_n int;
  v_fech uuid;
  v_dias_fech date;
  rr record;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);

  FOR v_comp IN
    SELECT to_char(m, 'YYYY-MM')
    FROM generate_series(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months',
                         date_trunc('month', timezone('America/Sao_Paulo', now())), interval '1 month') m
    ORDER BY 1
  LOOP
    v_ini := to_date(v_comp || '-01', 'YYYY-MM-DD');
    v_fim := (v_ini + interval '1 month - 1 day')::date;

    -- competencia ja fechada: nada a refazer
    IF EXISTS (SELECT 1 FROM public.ponto_fechamentos f
               WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp AND f.status = 'fechado') THEN
      CONTINUE;
    END IF;

    BEGIN
      -- (a) saldo de implantacao no primeiro mes: horas que vieram do controle anterior
      IF v_comp = v_primeira THEN
        INSERT INTO public.ponto_banco_horas (id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo, competencia, saldo_anterior_minutos, observacoes)
        SELECT public.demo_id('bh:' || a.cpf || '|' || v_comp), c_t, c_e, a.id::text, a.nome_completo, a.cpf, 'mensal', v_comp,
               (ARRAY[300, -150, 480, 0, 120, -240, 0, 600, 0, -60, 90, 180])[1 + public.demo_ponto_rnd(a.cpf, 12)],
               'Saldo de implantação (controle anterior à adoção do sistema).'
        FROM generate_series(1, 59) s(n)
        JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
        WHERE a.status = 'concluido' AND s.n % 3 = 1 AND a.data_admissao < v_ini
          AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas b
                          WHERE b.tenant_id = c_t AND b.colaborador_cpf = a.cpf AND b.competencia = v_comp);
      END IF;

      -- (b) apuracao oficial de todos que tem dia apurado no mes
      FOR v_cpf IN
        SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
        WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.colaborador_cpf IS NOT NULL
      LOOP
        PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
      END LOOP;

      -- (c) lancamentos manuais (a tela "Movimentar")
      -- folga compensada: quem acumulou saldo positivo tira folga no meio do mes
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:comp:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 14 + public.demo_ponto_rnd(b.colaborador_cpf || v_comp, 8)), 'compensacao',
             CASE WHEN b.saldo_anterior_minutos + b.creditos_minutos - b.debitos_minutos - b.compensados_minutos >= 700 THEN 480 ELSE 240 END,
             'Folga compensada autorizada pelo gestor (banco de horas).', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 10)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp AND v_comp > v_primeira
        AND b.saldo_anterior_minutos + b.creditos_minutos - b.debitos_minutos - b.compensados_minutos >= 360
        AND v_ini + 14 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:comp:' || b.colaborador_cpf || '|' || v_comp));

      -- credito manual: horas de inventario / evento autorizadas fora do ponto
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:cred:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 19), 'credito', 180,
             'Inventário geral do almoxarifado (horas autorizadas e registradas pelo gestor).', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 20)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp
        AND b.colaborador_cpf IN (SELECT a2.cpf FROM generate_series(1, 59) s2(n)
                                  JOIN public.admissoes a2 ON a2.id = public.demo_id('admissao:' || s2.n)
                                  WHERE s2.n IN (42, 44, 47, 49) AND v_comp = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'))
        AND v_ini + 19 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:cred:' || b.colaborador_cpf || '|' || v_comp));

      -- debito manual: saida antecipada autorizada para compensar no banco
      INSERT INTO public.ponto_banco_horas_movimentacoes (id, tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, created_by, origem, created_at)
      SELECT public.demo_id('bh_mov:deb:' || b.colaborador_cpf || '|' || v_comp), c_t, b.id, b.colaborador_cpf,
             LEAST(v_hoje, v_ini + 8), 'debito', (ARRAY[120, 150, 180])[1 + public.demo_ponto_rnd(b.colaborador_cpf || v_comp, 3)],
             'Saída antecipada autorizada (compromisso pessoal) a compensar no banco de horas.', v_uid::text, 'manual',
             LEAST(now(), (v_ini + 9)::timestamp AT TIME ZONE 'America/Sao_Paulo')
      FROM public.ponto_banco_horas b
      WHERE b.tenant_id = c_t AND b.competencia = v_comp
        AND b.colaborador_cpf IN (SELECT a2.cpf FROM generate_series(1, 59) s2(n)
                                  JOIN public.admissoes a2 ON a2.id = public.demo_id('admissao:' || s2.n)
                                  WHERE s2.n IN (3, 19, 35) AND v_comp = to_char(date_trunc('month', timezone('America/Sao_Paulo', now())), 'YYYY-MM'))
        AND v_ini + 8 <= v_hoje
        AND NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes m WHERE m.id = public.demo_id('bh_mov:deb:' || b.colaborador_cpf || '|' || v_comp));

      -- (d) reapura para os totais do banco refletirem os lancamentos manuais
      FOR v_cpf IN
        SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
        WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.colaborador_cpf IS NOT NULL
      LOOP
        PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
      END LOOP;

      -- (e) fechamento das competencias antigas (mesmo caminho do botao Fechar periodo)
      IF v_comp <= v_ate_fechar
         AND EXISTS (SELECT 1 FROM public.ponto_diario d WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim) THEN
        -- o portao do fechamento: se houver pendencia critica, nao fecha (avisa)
        BEGIN
          PERFORM public.ponto_fechar_competencia_verificar(c_t, c_e, v_comp);
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'Competencia % NAO fechada: %', v_comp, SQLERRM;
          CONTINUE;
        END;

        -- 5o dia util aproximado do mes seguinte
        v_dias_fech := v_fim + 6;

        INSERT INTO public.ponto_fechamentos (
          id, tenant_id, empresa_id, competencia, data_fechamento, status, fechado_por, fechado_por_nome,
          total_colaboradores, total_horas_normais_minutos, total_horas_extras_minutos, total_adicional_noturno_minutos,
          total_faltas, total_atrasos, observacoes, created_at)
        SELECT public.demo_id('ponto_fech:' || v_comp), c_t, c_e, v_comp,
               (v_dias_fech::timestamp + time '10:30') AT TIME ZONE 'America/Sao_Paulo', 'fechado',
               v_uid::text, 'Leiri',
               count(*), COALESCE(sum(r.total_trabalhado_min), 0), COALESCE(sum(r.total_creditos_min), 0), 0,
               COALESCE(sum(r.total_faltas), 0),
               (SELECT count(*) FROM public.ponto_diario d
                 WHERE d.tenant_id = c_t AND d.data BETWEEN v_ini AND v_fim AND d.status = 'atraso'),
               'Fechamento da competência conferido pelo RH e enviado à folha.',
               (v_dias_fech::timestamp + time '10:30') AT TIME ZONE 'America/Sao_Paulo'
        FROM public.ponto_espelho_resumo_empresa(c_t, c_e, v_comp) r
        ON CONFLICT (tenant_id, empresa_id, competencia) DO NOTHING;

        v_fech := (SELECT f.id FROM public.ponto_fechamentos f WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp);

        INSERT INTO public.ponto_espelhos (
          id, tenant_id, empresa_id, fechamento_id, colaborador_id, colaborador_nome, colaborador_cpf, competencia,
          total_horas_normais_minutos, total_trabalhado_minutos, total_jornada_prevista_minutos,
          total_creditos_minutos, total_debitos_minutos, total_horas_extras_50_minutos, total_horas_extras_100_minutos,
          total_atrasos_minutos, banco_horas_saldo_minutos, total_faltas, total_dias_trabalhados, total_dias_protegidos,
          total_excedente_retido_minutos, dia_equalizacao, status, created_at)
        SELECT public.demo_id('ponto_espelho:' || r.colaborador_cpf || '|' || v_comp), c_t, c_e, v_fech,
               r.colaborador_id::text, r.colaborador_nome, r.colaborador_cpf, v_comp,
               COALESCE(r.total_trabalhado_min, 0), COALESCE(r.total_trabalhado_min, 0), COALESCE(r.total_jornada_prevista_min, 0),
               COALESCE(r.total_creditos_min, 0), COALESCE(r.total_debitos_min, 0), COALESCE(r.he_50_min, 0), COALESCE(r.he_100_min, 0),
               COALESCE(r.atrasos_min, 0), COALESCE(r.saldo_banco_min, r.saldo_min, 0), COALESCE(r.total_faltas, 0),
               COALESCE(r.dias_trabalhados, 0), COALESCE(r.dias_protegidos, 0),
               COALESCE(r.excedente_retido_min, 0), r.dia_equalizacao, 'gerado',
               (v_dias_fech::timestamp + time '10:31') AT TIME ZONE 'America/Sao_Paulo'
        FROM public.ponto_espelho_resumo_empresa(c_t, c_e, v_comp) r
        WHERE NOT EXISTS (SELECT 1 FROM public.ponto_espelhos e
                          WHERE e.tenant_id = c_t AND e.colaborador_cpf = r.colaborador_cpf AND e.competencia = v_comp);

        -- regra RN29: so o saldo negativo transita para o mes seguinte
        PERFORM public.ponto_fechar_competencia_banco(c_t, c_e, v_comp);

        -- ciencia dos colaboradores (a maioria confirmou, alguns com ressalva)
        UPDATE public.ponto_espelhos e
           SET status = CASE WHEN public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'sc', 100) < 6 THEN 'ressalva' ELSE 'confirmado' END,
               ressalva_texto = CASE WHEN public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'sc', 100) < 6
                                     THEN 'Discordo de uma das faltas do mês: estava em consulta e o atestado foi entregue ao RH.' END,
               data_confirmacao = ((v_dias_fech - 2)::timestamp + time '09:00' + make_interval(mins => public.demo_ponto_rnd(e.colaborador_cpf || v_comp || 'dc', 480)))
                                  AT TIME ZONE 'America/Sao_Paulo',
               confirmado_por = e.colaborador_nome,
               assinatura_hash = md5('demo-espelho|' || e.colaborador_cpf || '|' || v_comp)
         WHERE e.tenant_id = c_t AND e.competencia = v_comp AND e.status = 'gerado'
           AND e.id = public.demo_id('ponto_espelho:' || e.colaborador_cpf || '|' || v_comp);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Banco/fechamento da competencia % nao concluido: % (%)', v_comp, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END $banco$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS bancos_de_horas,
  (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS movimentacoes,
  (SELECT count(*) FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') AS competencias_fechadas,
  (SELECT count(*) FROM public.ponto_espelhos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS espelhos,
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND saldo_atual_minutos > 0) AS saldos_positivos,
  (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND saldo_atual_minutos < 0) AS saldos_negativos,
  CASE WHEN (SELECT count(*) FROM public.ponto_fechamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'fechado') >= 2 AND (SELECT count(*) FROM public.ponto_banco_horas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 100 THEN 'OK' ELSE 'CONFERIR' END AS situacao;