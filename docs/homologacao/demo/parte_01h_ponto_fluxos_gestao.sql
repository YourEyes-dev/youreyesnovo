-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01h: Ponto: fluxos de gestao
--
-- PARA QUE SERVE
-- Fluxos de gestao pela via oficial: troca de turno (5 situacoes), compensacao de falta (todas as
-- situacoes), decisao sobre excedente de hora extra retido, excecoes de feriado e folgas
-- compensatorias. Depois reapura o banco de horas das competencias ainda abertas.
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
-- (11) Fluxos de gestao pela via oficial: troca de turno, compensacao de falta,
--      excedente de hora extra retido, excecoes de feriado e folgas compensatorias
-- ---------------------------------------------------------------------------
DO $fluxos$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_uid uuid;
  v_id uuid;
  v_res jsonb;
  v_status text;
  r record;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  END IF;

  -- ---- Troca de turno (aba Escalas > Troca de turno) ----
  FOR r IN
    SELECT * FROM (VALUES
      (1, 22, 23, 5, NULL::int, 'solicitada', 'Consulta médica de acompanhamento; combinei a troca com o colega do turno A.', NULL::text),
      (2, 1, 2, 4, 6, 'aprovada', 'Troca temporária por uma semana para curso de capacitação em horário de turno.', NULL),
      (3, 9, 10, 2, 7, 'efetivada', 'Troca de semana entre soldadores para acompanhar a manutenção programada da linha 2.', NULL),
      (4, 11, 12, 3, NULL, 'recusada', 'Preciso trocar de turno para resolver assunto pessoal.', 'Sem cobertura no turno B nesta semana; reapresentar após o fechamento da produção.'),
      (5, 25, 26, 6, NULL, 'cancelada', 'Troca solicitada e depois desnecessária.', NULL)
    ) AS t(k, na, nb, d_ini, d_dur, alvo, motivo, recusa)
  LOOP
    BEGIN
      IF EXISTS (SELECT 1 FROM public.ponto_troca_turno t WHERE t.id = public.demo_id('ponto_troca:' || r.k)) THEN
        CONTINUE;
      END IF;
      v_id := public.ponto_troca_turno_solicitar(
        c_t, public.demo_id('ponto_atrib:' || r.na || ':atual'), public.demo_id('ponto_atrib:' || r.nb || ':atual'),
        v_hoje + r.d_ini, CASE WHEN r.d_dur IS NULL THEN NULL ELSE v_hoje + r.d_ini + r.d_dur END,
        public.demo_id('admissao:' || r.na),
        (SELECT a.nome_completo FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || r.na)),
        r.motivo);
      UPDATE public.ponto_troca_turno SET id = public.demo_id('ponto_troca:' || r.k) WHERE id = v_id;
      v_id := public.demo_id('ponto_troca:' || r.k);
      IF r.alvo IN ('aprovada', 'efetivada') THEN
        PERFORM public.ponto_troca_turno_aprovar(v_id, v_uid, 'Leiri');
      END IF;
      IF r.alvo = 'efetivada' THEN
        PERFORM public.ponto_troca_turno_efetivar(v_id);
      END IF;
      IF r.alvo = 'recusada' THEN
        PERFORM public.ponto_troca_turno_recusar(v_id, v_uid, 'Leiri', r.recusa);
      END IF;
      IF r.alvo = 'cancelada' THEN
        UPDATE public.ponto_troca_turno SET status = 'cancelada' WHERE id = v_id;
      END IF;
      UPDATE public.ponto_troca_turno SET solicitada_em = now() - make_interval(days => 2 + r.k) WHERE id = v_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Troca de turno % nao criada: % (%)', r.k, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  -- ---- Compensacao de falta (aba Apuracao > Comp. Faltas) ----
  FOR r IN
    SELECT q.*, row_number() OVER (ORDER BY q.data DESC, q.cpf) AS rn
    FROM (
      SELECT DISTINCT ON (d.colaborador_cpf) d.colaborador_cpf AS cpf, d.data
      FROM public.ponto_diario d
      WHERE d.tenant_id = c_t AND d.status = 'falta'
        AND d.data BETWEEN v_hoje - 38 AND v_hoje - 2
        AND NOT EXISTS (SELECT 1 FROM public.ponto_compensacao_falta c WHERE c.tenant_id = c_t)
      ORDER BY d.colaborador_cpf, d.data DESC
    ) q
    ORDER BY q.data DESC, q.cpf
    LIMIT 8
  LOOP
    BEGIN
      v_res := public.ponto_registrar_compensacao_falta(c_t, r.cpf, r.data,
                 'Colaborador solicita compensar a falta com horas do banco (acordo coletivo vigente).');
      IF COALESCE((v_res ->> 'success')::boolean, false) IS NOT TRUE THEN
        RAISE NOTICE 'Compensacao de falta % / %: %', r.cpf, r.data, v_res ->> 'motivo';
        CONTINUE;
      END IF;
      v_id := (v_res ->> 'id')::uuid;
      IF r.rn BETWEEN 3 AND 6 THEN
        v_res := public.ponto_autorizar_compensacao_falta(c_t, v_id, 'Leiri');
        v_status := v_res ->> 'status';
        IF r.rn >= 4 AND v_status = 'pendente_homologacao' THEN
          PERFORM public.ponto_homologar_compensacao_falta(c_t, v_id, 'Leiri');
        END IF;
        IF r.rn >= 5 THEN
          PERFORM public.ponto_dar_ciencia_compensacao_falta(c_t, v_id, 'Colaborador (ciência registrada no espelho)');
        END IF;
      ELSIF r.rn = 7 THEN
        UPDATE public.ponto_compensacao_falta
           SET status = 'recusada', updated_at = now(),
               motivo = 'Falta sem justificativa; compensação não autorizada neste mês.'
         WHERE id = v_id;
      ELSIF r.rn = 8 THEN
        UPDATE public.ponto_compensacao_falta SET status = 'cancelada', updated_at = now() WHERE id = v_id;
      END IF;
      UPDATE public.ponto_compensacao_falta
         SET created_at = LEAST(now(), (r.data + 1)::timestamp AT TIME ZONE 'America/Sao_Paulo' + interval '10 hours')
       WHERE id = v_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Compensacao de falta % / % nao registrada: % (%)', r.cpf, r.data, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  -- ---- Excedente de hora extra retido (decisao do gestor, art. 61 CLT) ----
  FOR r IN
    SELECT p.*, row_number() OVER (ORDER BY p.dia, p.colaborador_cpf) AS rn
    FROM public.ponto_excedente_pendentes(c_t,
           to_char(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month', 'YYYY-MM'), c_e) p
    WHERE NOT EXISTS (SELECT 1 FROM public.ponto_excedente_decisao x0 WHERE x0.tenant_id = c_t)
  LOOP
    BEGIN
      IF r.rn = 1 THEN
        PERFORM public.ponto_excedente_decidir(c_t, r.colaborador_cpf, r.dia, 'liberado',
          'Pico de produção autorizado pelo gestor para atender pedido urgente de cliente (necessidade imperiosa, art. 61 CLT).');
      ELSIF r.rn = 2 THEN
        PERFORM public.ponto_excedente_decidir(c_t, r.colaborador_cpf, r.dia, 'irregularidade',
          'Permanência além do limite sem autorização prévia; orientar o líder do setor e registrar advertência verbal.');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Decisao de excedente % / % nao registrada: % (%)', r.colaborador_cpf, r.dia, SQLERRM, SQLSTATE;
    END;
  END LOOP;

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Fluxos de gestao do ponto nao concluidos: % (%)', SQLERRM, SQLSTATE;
END $fluxos$;

-- Excecoes de feriado (aba Configuracoes > Feriados > Excecoes por colaborador):
-- a equipe de expedicao trabalha em feriados por escala de plantao
DO $w1$
BEGIN
INSERT INTO public.feriado_excecao (id, tenant_id, colaborador_id, data, comportamento, observacao)
SELECT public.demo_id('feriado_exc:' || s.n || ':' || h.data::text), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('admissao:' || s.n), h.data, 'trabalha',
       'Plantão de feriado da produção (escala combinada com o líder).'
FROM generate_series(1, 59) s(n)
CROSS JOIN (VALUES (DATE '2026-09-07'), (DATE '2026-10-12')) AS h(data)
WHERE s.n % 7 = 0
  AND EXISTS (SELECT 1 FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || s.n) AND a.status = 'concluido')
  AND NOT EXISTS (SELECT 1 FROM public.feriado_excecao e WHERE e.id = public.demo_id('feriado_exc:' || s.n || ':' || h.data::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_excecao nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w1$;

-- Folga compensatoria do feriado trabalhado em 12/10 (quem nao a tem recebe adicional de 100%)
DO $w2$
BEGIN
INSERT INTO public.feriado_folga_compensatoria (id, tenant_id, colaborador_id, colaborador_cpf, data_feriado, data_folga, observacao)
SELECT public.demo_id('feriado_folga:' || s.n), 'd3e00000-0000-4000-8000-000000000001', a.id, a.cpf,
       DATE '2026-10-12', (timezone('America/Sao_Paulo', now()))::date + 3 + (s.n % 3),
       'Folga compensatória do feriado de Nossa Senhora Aparecida (acordada com o gestor).'
FROM generate_series(1, 59) s(n)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
WHERE s.n IN (7, 14, 21) AND a.status = 'concluido'
  AND NOT EXISTS (SELECT 1 FROM public.feriado_folga_compensatoria f WHERE f.id = public.demo_id('feriado_folga:' || s.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bloco feriado_folga_compensatoria nao concluido: % (%)', SQLERRM, SQLSTATE;
END $w2$;

-- Reapuracao final do banco de horas das competencias ainda abertas (depois dos
-- fluxos acima), para a fotografia do banco bater com a apuracao oficial
DO $reap$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_comp text;
  v_cpf text;
BEGIN
  FOR v_comp IN
    SELECT to_char(m, 'YYYY-MM')
    FROM generate_series(date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '3 months',
                         date_trunc('month', timezone('America/Sao_Paulo', now())), interval '1 month') m
    ORDER BY 1
  LOOP
    IF EXISTS (SELECT 1 FROM public.ponto_fechamentos f
               WHERE f.tenant_id = c_t AND f.empresa_id = c_e AND f.competencia = v_comp AND f.status = 'fechado') THEN
      CONTINUE;
    END IF;
    FOR v_cpf IN
      SELECT DISTINCT d.colaborador_cpf FROM public.ponto_diario d
      WHERE d.tenant_id = c_t AND to_char(d.data, 'YYYY-MM') = v_comp AND d.colaborador_cpf IS NOT NULL
    LOOP
      PERFORM public.apurar_banco_horas_colaborador(c_t, v_cpf, v_comp, c_e);
    END LOOP;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Reapuracao final do banco de horas nao concluida: % (%)', SQLERRM, SQLSTATE;
END $reap$;

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_troca_turno WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS trocas_de_turno,
  (SELECT count(*) FROM public.ponto_compensacao_falta WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS compensacoes_de_falta,
  (SELECT count(*) FROM public.ponto_excedente_decisao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS decisoes_excedente,
  (SELECT count(*) FROM public.feriado_excecao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS excecoes_feriado,
  CASE WHEN (SELECT count(*) FROM public.ponto_troca_turno WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 3 THEN 'OK' ELSE 'CONFERIR' END AS situacao;