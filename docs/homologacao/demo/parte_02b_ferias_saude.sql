-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 02b: ferias, atestados, afastamentos e saude
--
-- PARA QUE SERVE
-- Preenche, na "Metalurgica Exemplo Ltda" (100% ficticia), as telas /ferias
-- (programacao, solicitacoes, calendario, saldos, financeiro, inteligencia,
-- vencimentos, coletivas, cultura, relatorios, governanca), /atestados
-- (MOD-GAF: atestados, afastamentos, absenteismo, saude mental, FAP/RAT,
-- pendencias) e /saude-ocupacional (ASOs). Roda DEPOIS da parte 00 e da
-- parte 02a (pessoas).
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO. O arquivo se RECUSA a rodar em qualquer
-- outro banco: so aceita a URL gravada em app_config da homologacao ou do
-- teste. Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo d3e00000-0000-4000-8000-000000000001)
--   1. configuracao de ferias da empresa, vinculos familiares e, para cada
--      colaborador com mais de 1 ano de casa, periodos aquisitivos, programacao
--      e solicitacoes em todas as situacoes (gozadas, em gozo, aprovadas,
--      pendentes, recusadas, canceladas, planejadas, vencendo e vencidas);
--   2. ferias coletivas (rascunho, programado, comunicado e concluido) e os
--      alertas de vencimento (pela propria rotina de varredura do sistema);
--   3. afastamentos (doenca comum, acidente com CAT, INSS B31/B91, maternidade,
--      encerrados), atestados medicos, licencas, ASOs (admissional, periodico,
--      retorno, mudanca de funcao e demissional), eventos de saude, beneficios
--      INSS e alertas.
--
-- GARANTIAS
--   - Nenhum dado real: pessoas, CPFs (900.000.0XX), medicos e CRMs inventados;
--     CIDs sao codigos genericos da classificacao publica, sem pessoa real.
--   - Idempotente: ids fixos (public.demo_id) + "so insere se nao existe".
--   - Nao toca em nenhum outro tenant e nao cria tabelas.
--   - Os gatilhos do sistema continuam ligados: afastamentos e ferias gravam
--     'justificado'/'ferias' no ponto dos dias cobertos e geram marcadores e
--     pendencias do GAF. Isso e o comportamento normal do produto.
--   - Cada colaborador e processado num bloco proprio com EXCEPTION: se um
--     deles falhar por diferenca de estrutura, o resto segue (aparece NOTICE).
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) Trava de ambiente + helpers
-- ---------------------------------------------------------------------------
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
    RAISE EXCEPTION 'RECUSADO: o tenant demo nao existe. Rode antes a parte 00 (parte_00_base_empresa_demo.sql).';
  END IF;
END $trava$;

CREATE OR REPLACE FUNCTION public.demo_cpf(n integer)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  b text := '900000' || lpad(n::text, 3, '0');
  s integer := 0;
  d1 integer;
  d2 integer;
  i integer;
BEGIN
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (11 - i);
  END LOOP;
  d1 := (s * 10) % 11;
  IF d1 = 10 THEN d1 := 0; END IF;
  s := 0;
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (12 - i);
  END LOOP;
  s := s + d1 * 2;
  d2 := (s * 10) % 11;
  IF d2 = 10 THEN d2 := 0; END IF;
  RETURN b || d1::text || d2::text;
END
$fn$;

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

-- Segunda-feira em/antes de uma data e em/depois de uma data (ferias comecam na segunda).
CREATE OR REPLACE FUNCTION public.demo_seg_antes(d date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT d - ((extract(isodow FROM d)::int + 6) % 7)
$fn$;

CREATE OR REPLACE FUNCTION public.demo_seg_depois(d date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT d + ((8 - extract(isodow FROM d)::int) % 7)
$fn$;

-- ---------------------------------------------------------------------------
-- (2) Ferias: configuracao da empresa e vinculos familiares
-- ---------------------------------------------------------------------------
INSERT INTO public.ferias_config (
  id, tenant_id, empresa_id, metodo_calculo, encargo_inss_patronal, encargo_rat_fap, encargo_terceiros, encargo_fgts,
  simples_dispensa_patronal, media_base, media_divisor, media_vigencia_inicio
)
SELECT public.demo_id('feriascfg:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'clt_faltas', 20, 2.68, 5.8, 8, false, 'aquisitivo', 'meses_do_periodo', DATE '2026-01-01'
WHERE NOT EXISTS (
  SELECT 1 FROM public.ferias_config c
   WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND c.empresa_id = 'd3e00000-0000-4000-8000-000000000002');

INSERT INTO public.ferias_vinculo_familiar (id, tenant_id, empresa_id, cpf_a, nome_a, cpf_b, nome_b, grau, observacao)
SELECT public.demo_id('feriasfam:' || v.a || ':' || v.b), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.cpf, a.nome_completo, b.cpf, b.nome_completo, v.grau, v.obs
FROM (VALUES
  (4,  23, 'conjuge', 'Casal trabalha na empresa: evitar férias simultâneas na mesma equipe.'),
  (8,  47, 'irmao',   'Irmãos em setores diferentes; preferência por férias coincidentes no recesso.'),
  (35, 54, 'conjuge', 'Casal: Manutenção e Administrativo; férias coincidentes são desejadas.')
) AS v(a, b, grau, obs)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.a)
JOIN public.admissoes b ON b.id = public.demo_id('admissao:' || v.b)
WHERE NOT EXISTS (SELECT 1 FROM public.ferias_vinculo_familiar x WHERE x.id = public.demo_id('feriasfam:' || v.a || ':' || v.b));

-- ---------------------------------------------------------------------------
-- (3) Ferias por colaborador: periodos aquisitivos, solicitacoes, programacao,
--     historico e avisos para assinatura. Um bloco com EXCEPTION por pessoa.
-- ---------------------------------------------------------------------------
DO $ferias$
DECLARE
  v_tenant  uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_empresa uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_login   uuid;
  r         record;
  v_k       integer;
  v_ini     date;
  v_fim     date;
  v_conc    date;
  v_rem     integer;
  v_age     integer;
  v_faltas  integer;
  v_dir     integer;
  v_sc      text;
  v_abono   boolean;
  v_dias    integer;
  v_frac    boolean;
  v_st      date;
  v_en      date;
  v_p2s     date;
  v_p2e     date;
  v_p2d     integer;
  v_guard   integer;
  v_estado  text;
  v_sol_st  text;
  v_sol_id  uuid;
  v_prog_id uuid;
  v_tem_sol boolean;
  v_score   integer;
  v_nivel   text;
  v_apr_em  timestamptz;
  v_valor   numeric;
  v_ciencia timestamptz;
  v_gozados numeric;
  v_status_p text;
  v_motivo  text;
  j         integer;
  v_rn      integer;
BEGIN
  v_login := (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1);

  FOR r IN
    SELECT z.*, row_number() OVER (PARTITION BY z.in_g ORDER BY z.age DESC, md5(z.id::text)) AS gpos
      FROM (
        SELECT q.*, ((365 - q.age) >= 90 AND q.rn NOT IN (3, 11, 20)) AS in_g
          FROM (
            SELECT a.id, a.nome_completo, a.cpf, a.departamento, a.cargo, COALESCE(a.salario, 0) AS salario, a.data_admissao,
                   row_number() OVER (ORDER BY md5(a.id::text)) AS rn,
                   (CURRENT_DATE - ((a.data_admissao + make_interval(years => date_part('year', age(CURRENT_DATE, a.data_admissao))::int))::date - 1)) AS age
              FROM public.admissoes a
             WHERE a.tenant_id = v_tenant
               AND a.empresa_id = v_empresa
               AND a.status = 'concluido'
               AND a.data_admissao <= CURRENT_DATE - 366
          ) q
      ) z
     ORDER BY md5(z.id::text)
  LOOP
    BEGIN
      v_rn   := r.rn::int;
      v_k    := date_part('year', age(CURRENT_DATE, r.data_admissao))::int;
      v_ini  := (r.data_admissao + make_interval(years => v_k - 1))::date;
      v_fim  := (r.data_admissao + make_interval(years => v_k))::date - 1;
      v_conc := (v_fim + interval '12 months')::date;
      v_rem  := v_conc - CURRENT_DATE;
      v_age  := CURRENT_DATE - v_fim;

      v_faltas := CASE WHEN v_rn % 7 = 0 THEN 8 WHEN v_rn % 11 = 0 THEN 17 ELSE 0 END;
      v_dir    := CASE v_faltas WHEN 0 THEN 30 WHEN 8 THEN 24 ELSE 18 END;

      -- Cenario do periodo mais recente (o que aparece na Programacao)
      IF v_rn IN (3, 11) THEN
        v_sc := 'val_pendente'; v_faltas := 40; v_dir := 0;
      ELSIF v_rn = 20 THEN
        v_sc := 'zerado'; v_faltas := 45; v_dir := 0;
      ELSIF v_rem < 30 THEN
        v_sc := 'critico';
      ELSIF v_rem < 60 THEN
        v_sc := CASE WHEN v_rn % 2 = 0 THEN 'planejado' ELSE 'sem_prog' END;
      ELSIF v_rem < 90 THEN
        v_sc := CASE WHEN v_rn % 2 = 0 THEN 'confirmado' ELSE 'sem_prog' END;
      ELSE
        v_sc := CASE
                  WHEN NOT r.in_g THEN 'planejado'
                  WHEN r.gpos <= 8 THEN 'gozado'
                  WHEN r.gpos <= 10 THEN 'parcial'
                  WHEN r.gpos <= 13 THEN 'em_gozo'
                  WHEN r.gpos <= 15 THEN 'vencida'
                  ELSE (ARRAY['planejado','pendente','confirmado','aprovado','sugerido','planejado','sem_prog','aprovado','pendente','confirmado'])[1 + (r.gpos % 10)::int]
                END;
      END IF;

      v_abono := (v_dir = 30 AND v_rn % 4 = 0 AND v_sc IN ('gozado','planejado','confirmado','pendente','aprovado','em_gozo'));
      v_dias  := CASE WHEN v_abono THEN v_dir - 10 ELSE v_dir END;

      -- Ajustes de viabilidade (datas precisam caber no tempo disponivel)
      IF v_sc = 'gozado' AND v_age < v_dias + 25 THEN v_sc := 'planejado'; END IF;
      IF v_sc = 'em_gozo' AND v_age < 25 THEN v_sc := 'aprovado'; END IF;
      IF v_sc = 'parcial' AND (v_age < 45 OR v_dir < 24) THEN v_sc := 'planejado'; END IF;
      IF v_sc = 'vencida' AND v_k < 2 THEN v_sc := 'sem_prog'; END IF;
      IF v_sc IN ('planejado','sugerido','confirmado','pendente','aprovado')
         AND public.demo_seg_antes(v_conc - v_dias - 2) <= CURRENT_DATE + 7 THEN
        v_sc := 'sem_prog';
      END IF;

      -- ---------------- periodos aquisitivos (P, P-1, P-2) ----------------
      FOR j IN 0..2 LOOP
        EXIT WHEN v_k - j < 1;
        v_status_p := CASE WHEN j = 0 AND v_sc = 'val_pendente' THEN 'pendente_validacao'
                           WHEN j = 0 AND v_sc = 'zerado' THEN 'zerado_confirmado'
                           WHEN j = 1 AND v_sc = 'vencida' THEN 'ativo'
                           WHEN j = 0 THEN 'ativo'
                           ELSE 'encerrado' END;
        v_gozados := CASE WHEN j >= 1 AND NOT (j = 1 AND v_sc = 'vencida') THEN 30
                          WHEN j = 0 AND v_sc = 'gozado' THEN v_dir
                          WHEN j = 0 AND v_sc = 'parcial' THEN 14
                          ELSE 0 END;
        v_motivo := CASE WHEN j = 0 AND v_sc = 'val_pendente'
                         THEN 'Mais de 32 faltas no período aquisitivo: confirmar a perda do direito às férias (art. 130 da CLT) ou contestar as faltas.'
                         WHEN j = 0 AND v_sc = 'zerado'
                         THEN 'Perda do direito confirmada pelo RH após conferência das faltas.' END;
        INSERT INTO public.ferias_periodos_aquisitivos (
          id, tenant_id, empresa_id, colaborador_cpf, colaborador_nome, colaborador_id, data_admissao,
          aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados, fonte_faltas, faltas_consideradas,
          dias_direito, dias_saldo, status, validacao_motivo, validado_por, validado_em, origem, calculado_em
        )
        SELECT public.demo_id('feriasper:' || r.id::text || ':' || j),
               v_tenant, v_empresa, r.cpf, r.nome_completo, r.id, r.data_admissao,
               (r.data_admissao + make_interval(years => v_k - j - 1))::date,
               (r.data_admissao + make_interval(years => v_k - j))::date - 1,
               CASE WHEN j = 0 THEN v_faltas ELSE 0 END, v_gozados, 'carga', CASE WHEN j = 0 THEN v_faltas ELSE 0 END,
               CASE WHEN j = 0 THEN v_dir ELSE 30 END,
               GREATEST(0, (CASE WHEN j = 0 THEN v_dir ELSE 30 END) - v_gozados),
               v_status_p, v_motivo,
               CASE WHEN v_status_p = 'zerado_confirmado' THEN v_login END,
               CASE WHEN v_status_p = 'zerado_confirmado' THEN now() - interval '12 days' END,
               'importacao', now()
         WHERE NOT EXISTS (SELECT 1 FROM public.ferias_periodos_aquisitivos x WHERE x.id = public.demo_id('feriasper:' || r.id::text || ':' || j));
      END LOOP;

      -- ---------------- datas e documentos por cenario ----------------
      v_tem_sol := false;
      v_frac := false;
      v_estado := NULL;
      v_sol_st := NULL;
      v_st := NULL; v_en := NULL; v_p2s := NULL; v_p2e := NULL; v_p2d := NULL;

      IF v_sc = 'gozado' THEN
        v_st := LEAST(public.demo_seg_antes(v_fim + 25 + (v_rn % 20)), public.demo_seg_antes(CURRENT_DATE - 5 - v_dias));
        v_guard := 0;
        WHILE v_guard < 8 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_st + 1, v_st + 2)) LOOP
          v_st := v_st - 7; v_guard := v_guard + 1;
        END LOOP;
        v_en := v_st + v_dias - 1;
        v_estado := 'concluido'; v_sol_st := 'concluido'; v_tem_sol := true;
      ELSIF v_sc = 'parcial' THEN
        v_st := public.demo_seg_antes(v_fim + 14 + (v_rn % 10));
        v_guard := 0;
        WHILE v_guard < 3 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_st + 1, v_st + 2)) LOOP
          v_st := v_st + 7; v_guard := v_guard + 1;
        END LOOP;
        v_en := v_st + 13;
        v_p2s := public.demo_seg_depois(CURRENT_DATE + 30 + (v_rn % 30));
        v_p2s := LEAST(v_p2s, public.demo_seg_antes(v_conc - (v_dir - 14) - 2));
        v_guard := 0;
        WHILE v_guard < 8 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_p2s + 1, v_p2s + 2)) LOOP
          v_p2s := v_p2s + 7; v_guard := v_guard + 1;
        END LOOP;
        v_p2d := v_dir - 14;
        v_p2e := v_p2s + v_p2d - 1;
        v_estado := 'confirmado'; v_sol_st := 'concluido'; v_tem_sol := true; v_frac := true;
      ELSIF v_sc = 'em_gozo' THEN
        v_st := public.demo_seg_antes(CURRENT_DATE - 1 - (v_rn % 6));
        v_guard := 0;
        WHILE v_guard < 8 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_st + 1, v_st + 2)) LOOP
          v_st := v_st - 7; v_guard := v_guard + 1;
        END LOOP;
        v_en := v_st + v_dias - 1;
        v_estado := 'em_gozo'; v_sol_st := 'em_gozo'; v_tem_sol := true;
      ELSIF v_sc IN ('pendente', 'aprovado', 'planejado', 'sugerido', 'confirmado') THEN
        v_st := public.demo_seg_depois(CURRENT_DATE + CASE v_sc WHEN 'aprovado' THEN 10 + (v_rn * 5) % 50
                                                                  WHEN 'pendente' THEN 40 + (v_rn % 20)
                                                                  ELSE 25 + (v_rn * 3) % 40 END);
        v_st := LEAST(v_st, public.demo_seg_antes(v_conc - v_dias - 2));
        v_guard := 0;
        WHILE v_guard < 8 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_st + 1, v_st + 2)) LOOP
          v_st := v_st - 7; v_guard := v_guard + 1;
        END LOOP;
        -- fracionamento 14 + restante quando ha folga no concessivo
        IF v_rn % 3 = 0 AND v_dir >= 24 AND NOT v_abono AND v_rem >= 180 AND v_sc <> 'pendente' AND v_sc <> 'aprovado' THEN
          v_frac := true;
          v_en := v_st + 13;
          v_p2d := v_dir - 14;
          v_p2s := public.demo_seg_depois(v_en + 60);
          v_guard := 0;
          WHILE v_guard < 8 AND EXISTS (SELECT 1 FROM public.feriados_da_empresa(v_tenant, v_empresa, v_p2s + 1, v_p2s + 2)) LOOP
            v_p2s := v_p2s + 7; v_guard := v_guard + 1;
          END LOOP;
          v_p2e := v_p2s + v_p2d - 1;
          IF v_p2e > v_conc THEN v_frac := false; v_p2s := NULL; v_p2e := NULL; v_p2d := NULL; END IF;
        END IF;
        IF NOT v_frac THEN v_en := v_st + v_dias - 1; END IF;
        v_estado := CASE v_sc WHEN 'pendente' THEN 'solicitado' WHEN 'aprovado' THEN 'aprovado'
                              WHEN 'confirmado' THEN CASE WHEN v_rn % 2 = 0 THEN 'ciente' ELSE 'confirmado' END
                              ELSE v_sc END;
        v_sol_st := CASE v_sc WHEN 'pendente' THEN 'pendente' WHEN 'aprovado' THEN 'aprovado' END;
        v_tem_sol := v_sol_st IS NOT NULL;
      END IF;

      -- ---------------- solicitacao ----------------
      v_sol_id := public.demo_id('feriassol:' || r.id::text || ':a');
      IF v_tem_sol THEN
        v_score := 20 + (v_rn * 13) % 75;
        v_nivel := CASE WHEN v_score >= 75 THEN 'critico' WHEN v_score >= 55 THEN 'alto' WHEN v_score >= 35 THEN 'moderado' ELSE 'baixo' END;
        v_apr_em := CASE WHEN v_sol_st = 'pendente' THEN NULL
                         ELSE LEAST(now() - interval '1 day', (v_st - 35)::timestamptz + interval '15 hours') END;
        v_ciencia := CASE WHEN v_sol_st IN ('concluido', 'em_gozo') THEN (v_st - 25)::timestamptz + interval '11 hours'
                          WHEN v_sol_st = 'aprovado' AND v_rn % 2 = 0 THEN now() - interval '3 days' END;
        INSERT INTO public.ferias_solicitacoes (
          id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, departamento, cargo,
          data_inicio, data_fim, dias_solicitados, saldo_dias, status, abono_pecuniario, dias_abono, salario_base,
          periodo_aquisitivo_inicio, periodo_aquisitivo_fim, aprovado_por, aprovado_por_nome, data_aprovacao,
          valor_ferias, valor_terco, valor_abono, valor_total_bruto, aviso_gerado, recibo_gerado,
          aviso_ciencia_em, aviso_ciencia_origem, assinatura_status, inr_score_momento, inr_nivel_momento,
          acao_preventiva, mensagem_pre_ferias, mensagem_pre_ferias_enviada, checkin_retorno_enviado,
          checkin_retorno_respondido, checkin_retorno_respostas, observacoes, created_at, updated_at
        )
        SELECT v_sol_id, v_tenant, v_empresa, NULL::uuid, r.nome_completo, r.cpf, r.departamento, r.cargo,
               v_st, v_en, CASE WHEN v_sc = 'parcial' THEN 14 ELSE v_dias END, v_dir, v_sol_st,
               v_abono, CASE WHEN v_abono THEN 10 ELSE 0 END, r.salario,
               v_ini, v_fim,
               CASE WHEN v_sol_st <> 'pendente' THEN v_login END,
               CASE WHEN v_sol_st <> 'pendente' THEN 'Camila Duarte (RH)' END,
               v_apr_em,
               round(r.salario / 30.0 * (CASE WHEN v_sc = 'parcial' THEN 14 ELSE v_dias END), 2),
               round(r.salario / 30.0 * (CASE WHEN v_sc = 'parcial' THEN 14 ELSE v_dias END) / 3.0, 2),
               CASE WHEN v_abono THEN round(r.salario / 30.0 * 10, 2) ELSE 0 END,
               round(r.salario / 30.0 * (CASE WHEN v_sc = 'parcial' THEN 14 ELSE v_dias END) * 4.0 / 3.0, 2)
                 + CASE WHEN v_abono THEN round(r.salario / 30.0 * 10, 2) ELSE 0 END,
               v_sol_st <> 'pendente', v_sol_st = 'concluido',
               v_ciencia, CASE WHEN v_ciencia IS NOT NULL THEN CASE WHEN v_rn % 3 = 0 THEN 'papel' ELSE 'assinatura' END END,
               CASE WHEN v_sol_st = 'concluido' THEN 'assinado' WHEN v_ciencia IS NOT NULL THEN 'assinado'
                    WHEN v_sol_st = 'aprovado' THEN 'pendente' END,
               v_score, v_nivel, (v_nivel IN ('critico', 'alto') AND v_rn % 2 = 0),
               CASE WHEN v_sol_st IN ('aprovado', 'em_gozo', 'concluido') THEN 'Bom descanso! Aproveite as férias e volte com energia.' END,
               v_sol_st IN ('em_gozo', 'concluido'),
               v_sol_st = 'concluido',
               v_sol_st = 'concluido' AND v_rn % 3 <> 0,
               CASE WHEN v_sol_st = 'concluido' AND v_rn % 3 <> 0
                    THEN jsonb_build_object('descansado', 4 + (v_rn % 2), 'clima_retorno', 4, 'comentario', 'Voltei bem disposto(a).') END,
               CASE WHEN v_sol_st = 'pendente' THEN 'Aguardando decisão do gestor e do RH.'
                    WHEN v_sol_st = 'em_gozo' THEN 'Colaborador em gozo; retorno previsto para ' || to_char(v_en + 1, 'DD/MM/YYYY') || '.' END,
               LEAST(now(), COALESCE(v_apr_em, now()) - interval '4 days'), now()
         WHERE NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes x WHERE x.id = v_sol_id);

        -- historico de eventos da solicitacao
        INSERT INTO public.ferias_historico (id, tenant_id, solicitacao_id, acao, descricao, usuario_nome, created_at)
        SELECT public.demo_id('feriashist:' || v_sol_id::text || ':' || h.seq), v_tenant, v_sol_id, h.acao, h.descricao,
               h.usuario, h.quando
          FROM (VALUES
            (1, 'status_aprovado', 'Férias aprovadas por Camila Duarte (RH)', 'Camila Duarte (RH)', v_apr_em, v_sol_st IN ('aprovado', 'em_gozo', 'concluido')),
            (2, 'aviso_gerado', 'Aviso de férias gerado (PDF)', 'Camila Duarte (RH)', v_apr_em + interval '1 hour', v_sol_st IN ('aprovado', 'em_gozo', 'concluido')),
            (3, 'status_em_gozo', 'Colaborador em gozo de férias', 'Sistema', v_st::timestamptz + interval '6 hours', v_sol_st IN ('em_gozo', 'concluido')),
            (4, 'status_concluido', 'Férias concluídas — colaborador retornou', 'Sistema', (v_en + 1)::timestamptz + interval '6 hours', v_sol_st = 'concluido'),
            (5, 'recibo_gerado', 'Recibo de férias gerado (PDF)', 'Camila Duarte (RH)', (v_st - 3)::timestamptz + interval '10 hours', v_sol_st = 'concluido')
          ) AS h(seq, acao, descricao, usuario, quando, vale)
         WHERE h.vale AND h.quando IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.ferias_historico x
                            WHERE x.id = public.demo_id('feriashist:' || v_sol_id::text || ':' || h.seq));

        -- aviso aguardando assinatura (aprovadas sem ciencia)
        IF v_sol_st = 'aprovado' AND v_ciencia IS NULL THEN
          INSERT INTO public.ferias_assinatura_links (
            id, tenant_id, token, colaborador_nome, colaborador_cpf, departamento, cargo, data_inicio_ferias, data_fim_ferias,
            dias_ferias, abono_pecuniario, dias_abono, salario_base, status, expira_em, colaborador_id, empresa_id,
            ferias_solicitacao_id, tipo_documento
          )
          SELECT public.demo_id('feriaslink:' || v_sol_id::text), v_tenant, 'demo-fer-' || substr(md5(v_sol_id::text), 1, 24),
                 r.nome_completo, r.cpf, r.departamento, r.cargo, v_st::text, v_en::text, v_dias, v_abono,
                 CASE WHEN v_abono THEN 10 ELSE 0 END, r.salario, 'pendente', now() + interval '5 days', NULL::uuid, v_empresa, v_sol_id, 'aviso'
           WHERE NOT EXISTS (SELECT 1 FROM public.ferias_assinatura_links x WHERE x.id = public.demo_id('feriaslink:' || v_sol_id::text));
        END IF;
      END IF;

      -- solicitacoes que nao foram adiante: recusada e cancelada
      IF v_sc = 'sem_prog' AND v_rn % 3 = 0 THEN
        v_st := public.demo_seg_depois(CURRENT_DATE + 45);
        INSERT INTO public.ferias_solicitacoes (
          id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, departamento, cargo,
          data_inicio, data_fim, dias_solicitados, saldo_dias, status, abono_pecuniario, dias_abono, salario_base,
          periodo_aquisitivo_inicio, periodo_aquisitivo_fim, aprovado_por, aprovado_por_nome, data_aprovacao,
          motivo_recusa, valor_ferias, valor_terco, valor_total_bruto, observacoes, created_at, updated_at
        )
        SELECT public.demo_id('feriassol:' || r.id::text || ':b'), v_tenant, v_empresa, NULL::uuid, r.nome_completo, r.cpf,
               r.departamento, r.cargo, v_st, v_st + v_dir - 1, v_dir, v_dir, 'recusado', false, 0, r.salario,
               v_ini, v_fim, v_login, 'Camila Duarte (RH)', now() - interval '6 days',
               'Pico de produção no período pedido; reprogramar para o próximo trimestre, dentro do concessivo.',
               round(r.salario / 30.0 * v_dir, 2), round(r.salario / 30.0 * v_dir / 3.0, 2),
               round(r.salario / 30.0 * v_dir * 4.0 / 3.0, 2),
               'Pedido recusado pelo gestor da área.', now() - interval '9 days', now() - interval '6 days'
         WHERE NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes x WHERE x.id = public.demo_id('feriassol:' || r.id::text || ':b'));
      ELSIF v_sc = 'sugerido' AND v_rn % 2 = 0 THEN
        INSERT INTO public.ferias_solicitacoes (
          id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, departamento, cargo,
          data_inicio, data_fim, dias_solicitados, saldo_dias, status, abono_pecuniario, dias_abono, salario_base,
          periodo_aquisitivo_inicio, periodo_aquisitivo_fim, valor_ferias, valor_terco, valor_total_bruto,
          observacoes, created_at, updated_at
        )
        SELECT public.demo_id('feriassol:' || r.id::text || ':c'), v_tenant, v_empresa, NULL::uuid, r.nome_completo, r.cpf,
               r.departamento, r.cargo, v_st + 14, v_st + 14 + v_dias - 1, v_dias, v_dir, 'cancelado', false, 0, r.salario,
               v_ini, v_fim, round(r.salario / 30.0 * v_dias, 2), round(r.salario / 30.0 * v_dias / 3.0, 2),
               round(r.salario / 30.0 * v_dias * 4.0 / 3.0, 2),
               'Cancelada a pedido do colaborador (mudança de planos).', now() - interval '20 days', now() - interval '15 days'
         WHERE NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes x WHERE x.id = public.demo_id('feriassol:' || r.id::text || ':c'));
      END IF;

      -- ---------------- programacao (periodo mais recente) ----------------
      IF v_estado IS NOT NULL AND v_dir > 0 THEN
        v_prog_id := public.demo_id('feriasprog:' || r.id::text);
        INSERT INTO public.ferias_programacao (
          id, tenant_id, empresa_id, colaborador_cpf, colaborador_nome, colaborador_id, aquisitivo_inicio, aquisitivo_fim,
          p1_inicio, p1_fim, p1_dias, p2_inicio, p2_fim, p2_dias, abono_vender, abono_dias, abono_requerido_em, adiantar_13,
          estado, confirmado_por, confirmado_em, solicitacao_id, observacao, criado_por, fracionamento_concordancia,
          fracionamento_concordancia_em, fracionamento_concordancia_por, created_at, updated_at
        )
        SELECT v_prog_id, v_tenant, v_empresa, r.cpf, r.nome_completo, r.id, v_ini, v_fim,
               v_st,
               CASE WHEN v_sc = 'parcial' THEN v_en WHEN v_frac THEN v_en ELSE v_st + v_dias - 1 END,
               CASE WHEN v_sc = 'parcial' THEN 14 WHEN v_frac THEN 14 ELSE v_dias END,
               v_p2s, v_p2e, v_p2d,
               v_abono, CASE WHEN v_abono THEN 10 ELSE 0 END,
               CASE WHEN v_abono THEN v_fim - 20 END,
               (v_rn % 5 = 0),
               v_estado::public.ferias_prog_estado,
               CASE WHEN v_estado IN ('confirmado', 'ciente', 'solicitado', 'aprovado', 'em_gozo', 'concluido') THEN v_login END,
               CASE WHEN v_estado IN ('confirmado', 'ciente', 'solicitado', 'aprovado', 'em_gozo', 'concluido') THEN now() - interval '10 days' END,
               CASE WHEN v_tem_sol THEN v_sol_id END,
               CASE v_estado WHEN 'sugerido' THEN 'Sugestão do sistema: melhor janela para a equipe, dentro do concessivo.'
                             WHEN 'planejado' THEN 'Planejado com o gestor; aguardando confirmação do colaborador.'
                             WHEN 'concluido' THEN 'Férias gozadas e encerradas.'
                             ELSE NULL END,
               v_login, v_frac, CASE WHEN v_frac THEN now() - interval '20 days' END,
               CASE WHEN v_frac THEN r.nome_completo END, now() - interval '25 days', now()
         WHERE NOT EXISTS (SELECT 1 FROM public.ferias_programacao x WHERE x.id = v_prog_id)
           AND NOT EXISTS (SELECT 1 FROM public.ferias_programacao x
                            WHERE x.tenant_id = v_tenant AND x.colaborador_cpf = r.cpf AND x.aquisitivo_inicio = v_ini);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Ferias de % nao semeadas: % (%)', r.nome_completo, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END $ferias$;

-- ---------------------------------------------------------------------------
-- (4) Ferias coletivas (em varios estados) e alertas de vencimento
-- ---------------------------------------------------------------------------
DO $coletivas$
DECLARE
  v_tenant  uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_empresa uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_login   uuid;
  v_y       integer;
  v_id      uuid;
BEGIN
  v_login := (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1);
  v_y := date_part('year', CURRENT_DATE)::int;
  IF CURRENT_DATE > make_date(v_y, 12, 1) THEN v_y := v_y + 1; END IF;

  INSERT INTO public.ferias_coletivas (id, tenant_id, empresa_id, ano, departamento, p1_inicio, p1_fim, p2_inicio, p2_fim, estado, observacao, criado_por)
  SELECT public.demo_id('feriascol:' || v.chave), v_tenant, v_empresa, v.ano, v.depto, v.p1i, v.p1f, v.p2i, v.p2f, v.estado, v.obs, v_login
    FROM (VALUES
      ('producao',  v_y,     'Produção',       make_date(v_y, 12, 21), make_date(v_y + 1, 1, 4),  NULL::date, NULL::date, 'rascunho',  'Parada de fim de ano da fábrica: manutenção geral das máquinas durante o recesso.'),
      ('manutencao', v_y,    'Manutenção',     make_date(v_y, 12, 28), make_date(v_y + 1, 1, 8),  NULL, NULL, 'comunicado', 'Equipe de manutenção em recesso após a parada; plantão por escala de sobreaviso.'),
      ('logistica', v_y + 1, 'Logística',      make_date(v_y + 1, 1, 11), make_date(v_y + 1, 1, 20), make_date(v_y + 1, 7, 12), make_date(v_y + 1, 7, 21), 'rascunho', 'Dois períodos de 10 dias, alinhados à baixa temporada do centro de distribuição.'),
      ('comercial', v_y - 1, 'Comercial',      make_date(v_y - 1, 12, 22), make_date(v_y, 1, 2),  NULL, NULL, 'concluido', 'Recesso do fim do ano anterior, já concluído.'),
      ('administrativo', v_y, 'Administrativo', make_date(v_y, 11, 2), make_date(v_y, 11, 13),    NULL, NULL, 'cancelado', 'Cancelado: fechamento contábil do ano exigiu a equipe.')
    ) AS v(chave, ano, depto, p1i, p1f, p2i, p2f, estado, obs)
   WHERE NOT EXISTS (SELECT 1 FROM public.ferias_coletivas x WHERE x.id = public.demo_id('feriascol:' || v.chave));

  -- abre os comunicados (MTE, sindicato, empregados) pela rotina do proprio sistema
  FOR v_id IN SELECT id FROM public.ferias_coletivas
               WHERE tenant_id = v_tenant AND id IN (public.demo_id('feriascol:producao'), public.demo_id('feriascol:manutencao'), public.demo_id('feriascol:comercial'))
  LOOP
    PERFORM public.ferias_coletiva_abrir_comunicados(v_id);
  END LOOP;

  UPDATE public.ferias_coletivas_comunicados c
     SET status = CASE WHEN c.destino = 'empregados' THEN 'gerado' ELSE 'protocolado' END,
         protocolado_em = CASE WHEN c.destino = 'empregados' THEN NULL ELSE now() - interval '5 days' END
   WHERE c.tenant_id = v_tenant
     AND c.coletiva_id IN (public.demo_id('feriascol:manutencao'), public.demo_id('feriascol:comercial'))
     AND c.status = 'pendente';
  UPDATE public.ferias_coletivas_comunicados c
     SET status = 'gerado'
   WHERE c.tenant_id = v_tenant
     AND c.coletiva_id = public.demo_id('feriascol:producao')
     AND c.destino = 'empregados' AND c.status = 'pendente';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ferias coletivas nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $coletivas$;

-- Alertas de vencimento (D-90/60/30 e dobro): a mesma varredura que roda todo dia no sistema
DO $alertas$
BEGIN
  PERFORM public.ferias_alertas_varrer('d3e00000-0000-4000-8000-000000000001');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Varredura de alertas de ferias nao concluida: % (%)', SQLERRM, SQLSTATE;
END $alertas$;

-- ---------------------------------------------------------------------------
-- (5) Afastamentos (GAF). Cada afastamento k usa o k-esimo colaborador (em ordem
--     estavel) que nao esteja com ferias aprovadas/em gozo; a licenca-maternidade
--     usa a primeira mulher depois do 20o colaborador.
-- ---------------------------------------------------------------------------
INSERT INTO public.afastamentos (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, status,
  motivo_principal, nexo_trabalho, observacoes, cargo_id, setor_id, tipo_principal_new, status_geral_new,
  data_atestado, prazo_indeterminado, criado_por, created_at
)
SELECT public.demo_id('afast:' || s.k), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', NULL,
       e.nome_completo, e.cpf, CURRENT_DATE + s.ini, CASE WHEN s.fim IS NULL THEN NULL ELSE CURRENT_DATE + s.fim END,
       s.status::public.afastamento_status,
       s.grupo::public.grupo_clinico, s.nexo::public.nexo_trabalho, s.obs,
       public.demo_id('cargo:' || e.cargo), public.demo_id('depto:' || e.departamento),
       s.tipo::public.afastamento_tipo_principal, s.status_geral::public.afastamento_status_geral,
       CURRENT_DATE + s.ini, s.prazo_ind,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       (CURRENT_DATE + s.ini)::timestamptz + interval '10 hours'
FROM (VALUES
  (1,  'doenca_comum',          -3,  3,    'ativo',          'respiratorio',  'nao', 'registrado',          false, 'Gripe com febre; atestado de 7 dias.'),
  (2,  'doenca_comum',          -9,  2,    'ativo',          'osteomuscular', 'nao', 'aguardando_documento', false, 'Lombalgia aguda; falta anexar o atestado original.'),
  (3,  'doenca_comum',          -13, 1,    'ativo',          'digestivo',     'nao', 'retorno_pendente',   false, 'Gastrite; retorno previsto para amanhã (15 dias).'),
  (4,  'doenca_comum',          -18, 4,    'ativo',          'mental',        'nao', 'registrado',         false, 'Quadro ansioso; episódio acima de 15 dias, avaliar encaminhamento ao INSS.'),
  (5,  'acidente_tipico',       -10, 20,   'ativo',          'osteomuscular', 'sim', 'registrado',         false, 'Acidente de trabalho na montagem (fratura de dedo); CAT emitida.'),
  (6,  'beneficio_b31',         -45, NULL, 'beneficio_inss', 'osteomuscular', 'nao', 'em_beneficio',       true,  'Auxílio-doença (B31) concedido; perícia de reavaliação agendada.'),
  (7,  'licenca_maternidade',   -60, 60,   'ativo',          NULL,            'nao', 'em_beneficio',       false, 'Licença-maternidade de 120 dias.'),
  (8,  'beneficio_b91',         -100, NULL,'beneficio_inss', 'osteomuscular', 'sim', 'em_beneficio',       true,  'Auxílio-doença acidentário (B91) após acidente de trabalho; estabilidade de 12 meses.'),
  (9,  'doenca_comum',          -120, -114,'encerrado',      'respiratorio',  'nao', 'encerrado',          false, 'Resfriado com atestado de 7 dias.'),
  (10, 'doenca_comum',          -95, -90,  'encerrado',      'infeccioso',    'nao', 'encerrado',          false, 'Gastroenterite.'),
  (11, 'atestado_odontologico', -80, -80,  'encerrado',      'outro',         'nao', 'encerrado',          false, 'Tratamento odontológico (1 dia).'),
  (12, 'doenca_comum',          -70, -56,  'encerrado',      'mental',        'nao', 'encerrado',          false, 'Episódio depressivo leve; entrevista de retorno realizada.'),
  (13, 'acidente_trajeto',      -52, -30,  'encerrado',      'osteomuscular', 'sim', 'encerrado',          false, 'Acidente de trajeto (torção de tornozelo); CAT emitida.'),
  (14, 'beneficio_b31',         -48, -14,  'encerrado',      'osteomuscular', 'nao', 'encerrado',          false, 'Auxílio-doença (B31) cessado; ASO de retorno realizado.'),
  (15, 'licenca_nao_remunerada',-30, -16,  'encerrado',      NULL,            'nao', 'encerrado',          false, 'Licença não remunerada solicitada pelo colaborador.'),
  (16, 'doenca_comum',          -25, -23,  'encerrado',      'neurologico',   'nao', 'encerrado',          false, 'Enxaqueca.'),
  (17, 'doenca_comum',          -20, -17,  'encerrado',      'outro',         'nao', 'encerrado',          false, 'Conjuntivite.'),
  (18, 'doenca_comum',          -8,  -7,   'encerrado',      'dermatologico', 'nao', 'encerrado',          false, 'Dermatite de contato.')
) AS s(k, tipo, ini, fim, status, grupo, nexo, status_geral, prazo_ind, obs)
JOIN LATERAL (
  SELECT q.* FROM (
    SELECT a.id, a.nome_completo, a.cpf, a.cargo, a.departamento, a.genero,
           row_number() OVER (ORDER BY md5(a.id::text)) AS rn
      FROM public.admissoes a
     WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
       AND NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes f
                        WHERE f.tenant_id = a.tenant_id AND f.colaborador_cpf = a.cpf
                          AND f.status IN ('aprovado', 'em_gozo', 'suspenso'))
  ) q
  WHERE CASE WHEN s.k = 7 THEN q.id = (SELECT w.id FROM (
                  SELECT a2.id, row_number() OVER (ORDER BY md5(a2.id::text)) AS rn2
                    FROM public.admissoes a2
                   WHERE a2.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a2.status = 'concluido'
                     AND NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes f2
                                      WHERE f2.tenant_id = a2.tenant_id AND f2.colaborador_cpf = a2.cpf
                                        AND f2.status IN ('aprovado', 'em_gozo', 'suspenso'))
                ) w JOIN public.admissoes g ON g.id = w.id
                 WHERE g.genero = 'feminino' AND w.rn2 > 20 ORDER BY w.rn2 LIMIT 1)
             ELSE q.rn = s.k END
) e ON true
WHERE NOT EXISTS (SELECT 1 FROM public.afastamentos x WHERE x.id = public.demo_id('afast:' || s.k));

-- CID, CAT e situacao previdenciaria de cada afastamento
INSERT INTO public.afastamentos_saude (
  id, afastamento_id, tenant_id, cid_principal, cid_descricao, cid_grupo, cid_capitulo,
  profissional_nome, profissional_conselho, profissional_numero, profissional_uf, especialidade
)
SELECT public.demo_id('afastsaude:' || c.k), public.demo_id('afast:' || c.k), 'd3e00000-0000-4000-8000-000000000001',
       c.cid, c.descricao, c.grupo, c.capitulo, c.medico, c.conselho, c.numero, 'SC', c.especialidade
FROM (VALUES
  (1,  'J11.1', 'Influenza com outras manifestações respiratórias', 'J09-J18', 'X - Doenças do aparelho respiratório', 'Dr. Paulo Ricardo Menezes', 'CRM', 'DEMO-10101', 'Clínica geral'),
  (2,  'M54.5', 'Dor lombar baixa', 'M50-M54', 'XIII - Doenças do sistema osteomuscular', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (3,  'K29.7', 'Gastrite não especificada', 'K20-K31', 'XI - Doenças do aparelho digestivo', 'Dr. Paulo Ricardo Menezes', 'CRM', 'DEMO-10101', 'Clínica geral'),
  (4,  'F41.1', 'Ansiedade generalizada', 'F40-F48', 'V - Transtornos mentais e comportamentais', 'Dr. Ricardo Alves Mourão', 'CRM', 'DEMO-30303', 'Psiquiatria'),
  (5,  'S62.6', 'Fratura de outro dedo da mão', 'S60-S69', 'XIX - Lesões e causas externas', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (6,  'M51.1', 'Transtorno de disco lombar com radiculopatia', 'M50-M54', 'XIII - Doenças do sistema osteomuscular', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (8,  'S83.5', 'Entorse e distensão do ligamento cruzado do joelho', 'S80-S89', 'XIX - Lesões e causas externas', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (9,  'J06.9', 'Infecção aguda das vias aéreas superiores', 'J00-J06', 'X - Doenças do aparelho respiratório', 'Dra. Júlia Ramos Toledo', 'CRM', 'DEMO-40404', 'Clínica geral'),
  (10, 'A09',   'Gastroenterite de origem infecciosa presumível', 'A00-A09', 'I - Doenças infecciosas e parasitárias', 'Dra. Júlia Ramos Toledo', 'CRM', 'DEMO-40404', 'Clínica geral'),
  (11, 'K02.1', 'Cárie da dentina', 'K00-K14', 'XI - Doenças do aparelho digestivo', 'Dr. André Luiz Barcelos', 'CRO', 'DEMO-50505', 'Odontologia'),
  (12, 'F32.0', 'Episódio depressivo leve', 'F30-F39', 'V - Transtornos mentais e comportamentais', 'Dr. Ricardo Alves Mourão', 'CRM', 'DEMO-30303', 'Psiquiatria'),
  (13, 'S93.4', 'Entorse e distensão do tornozelo', 'S90-S99', 'XIX - Lesões e causas externas', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (14, 'M54.4', 'Lumbago com ciática', 'M50-M54', 'XIII - Doenças do sistema osteomuscular', 'Dra. Fernanda Lopes Cardoso', 'CRM', 'DEMO-20202', 'Ortopedia'),
  (16, 'G43.9', 'Enxaqueca não especificada', 'G43-G44', 'VI - Doenças do sistema nervoso', 'Dra. Júlia Ramos Toledo', 'CRM', 'DEMO-40404', 'Clínica geral'),
  (17, 'H10.9', 'Conjuntivite não especificada', 'H10-H13', 'VII - Doenças do olho e anexos', 'Dr. Paulo Ricardo Menezes', 'CRM', 'DEMO-10101', 'Clínica geral'),
  (18, 'L23.9', 'Dermatite alérgica de contato', 'L20-L30', 'XII - Doenças da pele', 'Dra. Júlia Ramos Toledo', 'CRM', 'DEMO-40404', 'Clínica geral')
) AS c(k, cid, descricao, grupo, capitulo, medico, conselho, numero, especialidade)
WHERE EXISTS (SELECT 1 FROM public.afastamentos a WHERE a.id = public.demo_id('afast:' || c.k))
  AND NOT EXISTS (SELECT 1 FROM public.afastamentos_saude x WHERE x.afastamento_id = public.demo_id('afast:' || c.k));

INSERT INTO public.afastamentos_cat (
  id, afastamento_id, tenant_id, cat_aplicavel, status_cat, tipo_cat, data_acidente, hora_acidente, local_acidente,
  parte_corpo, agente_causador, descricao_acidente, testemunhas, protocolo_esocial, numero_cat
)
SELECT public.demo_id('afastcat:' || c.k), public.demo_id('afast:' || c.k), 'd3e00000-0000-4000-8000-000000000001',
       true, c.status_cat, c.tipo_cat, a.data_inicio, c.hora::time, c.local, c.parte, c.agente, c.descricao,
       c.testemunhas::jsonb, c.protocolo, c.numero
FROM (VALUES
  (5,  'pendente_envio', 'inicial', '14:20', 'Setor de montagem', 'Dedo da mão direita', 'Peça de aço em movimentação manual',
       'Durante a montagem de uma estrutura, a peça deslizou e prensou o dedo do colaborador. Atendimento imediato e encaminhamento ao pronto atendimento.',
       '[{"nome":"Rogério Antunes Pimentel","funcao":"Técnico de Segurança"}]', NULL, 'CAT-DEMO-0001'),
  (13, 'emitida', 'inicial', '07:35', 'Trajeto residência-trabalho (Av. das Indústrias)', 'Tornozelo esquerdo', 'Queda ao desembarcar do ônibus',
       'Acidente de trajeto: torção do tornozelo ao descer do transporte. CAT emitida em até 1 dia útil.',
       '[]', 'ESOCIAL-S2210-DEMO-0002', 'CAT-DEMO-0002')
) AS c(k, status_cat, tipo_cat, hora, local, parte, agente, descricao, testemunhas, protocolo, numero)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || c.k)
WHERE NOT EXISTS (SELECT 1 FROM public.afastamentos_cat x WHERE x.afastamento_id = public.demo_id('afast:' || c.k));

INSERT INTO public.afastamentos_previdenciario (
  id, afastamento_id, tenant_id, encaminhado_inss, especie_beneficio, numero_beneficio, data_inicio_beneficio,
  data_cessacao_prevista, data_alta, houve_prorrogacao, status_previdenciario
)
SELECT public.demo_id('afastprev:' || p.k), public.demo_id('afast:' || p.k), 'd3e00000-0000-4000-8000-000000000001',
       true, p.especie, p.numero, a.data_inicio + 15, p.cessacao, p.alta, p.prorrog, p.status
FROM (VALUES
  (6,  'B31', '31/000.000.001-1 (fictício)', CURRENT_DATE + 40, NULL::date, false, 'em_gozo'),
  (8,  'B91', '91/000.000.002-2 (fictício)', CURRENT_DATE + 75, NULL::date, true,  'em_gozo'),
  (14, 'B31', '31/000.000.003-3 (fictício)', CURRENT_DATE - 14, CURRENT_DATE - 14, false, 'cessado')
) AS p(k, especie, numero, cessacao, alta, prorrog, status)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || p.k)
WHERE NOT EXISTS (SELECT 1 FROM public.afastamentos_previdenciario x WHERE x.afastamento_id = public.demo_id('afast:' || p.k));

-- Benefícios do INSS (o sistema calcula a estabilidade do B91 pelo proprio gatilho)
INSERT INTO public.beneficios_inss (
  id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, numero_beneficio, especie, data_inicio, data_fim,
  data_alta, gera_estabilidade, afastamento_id, observacoes, criado_por_nome
)
SELECT public.demo_id('beninss:' || b.k), 'd3e00000-0000-4000-8000-000000000001', NULL,
       a.colaborador_nome, a.colaborador_cpf, b.numero, b.especie::public.beneficio_inss_especie, a.data_inicio + 15, b.fim, b.alta,
       (b.especie = 'b91'), a.id, b.obs, 'Camila Duarte (RH)'
FROM (VALUES
  (6,  '31/000.000.001-1 (fictício)', 'b31', NULL::date, NULL::date, 'Benefício em curso; aguardando a próxima perícia.'),
  (8,  '91/000.000.002-2 (fictício)', 'b91', NULL, NULL, 'Acidentário: estabilidade de 12 meses após a alta (art. 118 da Lei 8.213).'),
  (14, '31/000.000.003-3 (fictício)', 'b31', CURRENT_DATE - 14, CURRENT_DATE - 14, 'Benefício cessado; colaborador retornou após o ASO de retorno.')
) AS b(k, numero, especie, fim, alta, obs)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || b.k)
WHERE NOT EXISTS (SELECT 1 FROM public.beneficios_inss x WHERE x.id = public.demo_id('beninss:' || b.k));

UPDATE public.afastamentos a
   SET beneficio_inss_id = public.demo_id('beninss:' || v.k)
  FROM (VALUES (6), (8), (14)) AS v(k)
 WHERE a.id = public.demo_id('afast:' || v.k) AND a.beneficio_inss_id IS NULL
   AND EXISTS (SELECT 1 FROM public.beneficios_inss b WHERE b.id = public.demo_id('beninss:' || v.k));

-- ---------------------------------------------------------------------------
-- (6) Atestados e licencas ligados aos afastamentos
-- ---------------------------------------------------------------------------
INSERT INTO public.atestados (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, colaborador_cargo, colaborador_departamento,
  tipo, subtipo_assistencial, data_emissao, profissional_nome, profissional_registro, profissional_tipo, profissional_uf,
  data_inicio_afastamento, data_fim_afastamento, dias_afastamento, unidade_afastamento, contem_cid, cid_codigo,
  cid_autorizado, grupo_clinico, nexo_trabalho, afastamento_id, observacoes, criado_por, criado_por_nome, created_at
)
SELECT public.demo_id('atestado:af' || k.k), a.tenant_id, a.empresa_id, NULL, a.colaborador_nome, a.colaborador_cpf,
       adm.cargo, adm.departamento,
       CASE WHEN a.tipo_principal_new IN ('licenca_nao_remunerada') THEN 'licencas' ELSE 'atestados' END::public.atestado_tipo,
       CASE a.tipo_principal_new
         WHEN 'doenca_comum' THEN 'doenca_nao_trabalho'
         WHEN 'acidente_tipico' THEN 'acidente_trabalho'
         WHEN 'acidente_trajeto' THEN 'acidente_trabalho'
         WHEN 'atestado_odontologico' THEN 'odontologico'
         WHEN 'beneficio_b31' THEN 'doenca_nao_trabalho'
         WHEN 'beneficio_b91' THEN 'acidente_trabalho'
         WHEN 'licenca_maternidade' THEN 'maternidade'
         ELSE 'outras_licencas' END::public.atestado_subtipo_assistencial,
       a.data_inicio,
       COALESCE(s.profissional_nome, 'Dra. Júlia Ramos Toledo'),
       COALESCE(s.profissional_numero, 'DEMO-40404'),
       CASE WHEN s.profissional_conselho = 'CRO' THEN 'dentista' ELSE 'medico' END,
       'SC',
       a.data_inicio,
       CASE WHEN a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91') THEN a.data_inicio + 14 ELSE a.data_fim END,
       CASE WHEN a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91') THEN 15 ELSE a.data_fim - a.data_inicio + 1 END,
       'dias',
       s.cid_principal IS NOT NULL, s.cid_principal, s.cid_principal IS NOT NULL,
       a.motivo_principal, a.nexo_trabalho, a.id,
       CASE WHEN a.tipo_principal_new IN ('beneficio_b31', 'beneficio_b91') THEN 'Primeiro atestado; depois dos 15 dias o afastamento seguiu como benefício do INSS.' END,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       'Camila Duarte (RH)', a.data_inicio::timestamptz + interval '11 hours'
FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18)) AS k(k)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || k.k)
LEFT JOIN public.afastamentos_saude s ON s.afastamento_id = a.id
JOIN public.admissoes adm ON adm.tenant_id = a.tenant_id AND adm.cpf = a.colaborador_cpf AND adm.status = 'concluido'
WHERE NOT EXISTS (SELECT 1 FROM public.atestados x WHERE x.id = public.demo_id('atestado:af' || k.k));

-- Declaracoes de comparecimento (por horas) e licencas legais
INSERT INTO public.atestados (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, colaborador_cargo, colaborador_departamento,
  tipo, subtipo_assistencial, data_emissao, profissional_nome, profissional_registro, profissional_tipo, profissional_uf,
  data_inicio_afastamento, data_fim_afastamento, dias_afastamento, horas_afastamento, unidade_afastamento,
  contem_cid, cid_autorizado, nexo_trabalho, abona, observacoes, criado_por, criado_por_nome, created_at
)
SELECT public.demo_id('atestado:' || v.chave), e.tenant_id, e.empresa_id, NULL, e.nome_completo, e.cpf, e.cargo, e.departamento,
       v.tipo::public.atestado_tipo, v.subtipo::public.atestado_subtipo_assistencial, CURRENT_DATE + v.ini,
       v.medico, v.registro, 'medico', 'SC',
       CURRENT_DATE + v.ini, CURRENT_DATE + v.fim, v.dias, v.horas, v.unidade,
       false, false, 'nao', v.abona, v.obs,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       'Camila Duarte (RH)', (CURRENT_DATE + v.ini)::timestamptz + interval '12 hours'
FROM (VALUES
  ('comp1', 31, 'atestados', 'comparecimento', -40, -40, 0, 3,    'horas', true,  'Clínica Saúde da Família', 'DEMO-60601', 'Consulta de rotina.'),
  ('comp2', 32, 'atestados', 'comparecimento', -33, -33, 0, 2,    'horas', true,  'Laboratório Análises Exemplo', 'DEMO-60602', 'Coleta de exames.'),
  ('comp3', 33, 'atestados', 'comparecimento', -26, -26, 0, 4,    'horas', true,  'Clínica Saúde da Família', 'DEMO-60601', 'Consulta com especialista.'),
  ('comp4', 34, 'atestados', 'comparecimento', -19, -19, 0, 3,    'horas', false, 'Hospital Exemplo', 'DEMO-60603', 'Acompanhamento de filho em consulta; empresa não abona (política interna).'),
  ('comp5', 35, 'atestados', 'comparecimento', -12, -12, 0, 2,    'horas', true,  'Clínica Saúde da Família', 'DEMO-60601', 'Retorno médico.'),
  ('comp6', 36, 'atestados', 'comparecimento', -5,  -5,  0, 3,    'horas', true,  'Laboratório Análises Exemplo', 'DEMO-60602', 'Exame de imagem.'),
  ('lic1',  37, 'licencas',  'casamento',      -50, -46, 5, NULL, 'dias',  false, 'Cartório Exemplo', 'DEMO-70701', 'Licença-casamento de 5 dias consecutivos (CLT art. 473).'),
  ('lic2',  38, 'licencas',  'falecimento',    -22, -21, 2, NULL, 'dias',  false, 'Cartório Exemplo', 'DEMO-70702', 'Licença por falecimento de parente (CLT art. 473).'),
  ('lic3',  39, 'licencas',  'outras_licencas',-15, -15, 1, NULL, 'dias',  false, 'Banco de Sangue Exemplo', 'DEMO-70703', 'Doação voluntária de sangue (1 dia por ano).')
) AS v(chave, pos, tipo, subtipo, ini, fim, dias, horas, unidade, abona, medico, registro, obs)
JOIN LATERAL (
  SELECT q.* FROM (
    SELECT a.id, a.tenant_id, a.empresa_id, a.nome_completo, a.cpf, a.cargo, a.departamento,
           row_number() OVER (ORDER BY md5(a.id::text)) AS rn
      FROM public.admissoes a
     WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'concluido'
       AND NOT EXISTS (SELECT 1 FROM public.ferias_solicitacoes f
                        WHERE f.tenant_id = a.tenant_id AND f.colaborador_cpf = a.cpf AND f.status IN ('aprovado', 'em_gozo', 'suspenso'))
  ) q WHERE q.rn = v.pos
) e ON true
WHERE NOT EXISTS (SELECT 1 FROM public.atestados x WHERE x.id = public.demo_id('atestado:' || v.chave));

-- ---------------------------------------------------------------------------
-- (7) ASOs (saude ocupacional): admissional, periodico, retorno ao trabalho,
--     mudanca de risco e demissional, com vencimentos regulares, a vencer e vencidos
-- ---------------------------------------------------------------------------
INSERT INTO public.atestados (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, colaborador_cargo, colaborador_departamento,
  tipo, subtipo_ocupacional, data_emissao, profissional_nome, profissional_registro, profissional_tipo, profissional_uf,
  profissional_rqe, contem_cid, cid_autorizado, nexo_trabalho, aptidao, restricoes, observacoes_ocupacionais,
  afastamento_id, criado_por, criado_por_nome, created_at
)
SELECT public.demo_id('aso:' || x.chave), x.tenant_id, x.empresa_id, NULL, x.nome_completo, x.cpf, x.cargo, x.departamento,
       'ocupacional', x.subtipo::public.atestado_subtipo_ocupacional, x.emissao,
       'Dra. Helena Prado Marques', 'DEMO-80801', 'medico', 'SC', 'RQE 00000 (Medicina do Trabalho)',
       false, false, 'nao', x.aptidao::public.aptidao_ocupacional, x.restricoes,
       COALESCE(x.obs, 'Exames realizados: ' || COALESCE((SELECT array_to_string(c.exames_obrigatorios, ', ') FROM public.cargos c
                                                           WHERE c.id = public.demo_id('cargo:' || x.cargo)), 'clínico') || '.'),
       x.afastamento_id,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       'Camila Duarte (RH)', x.emissao::timestamptz + interval '16 hours'
FROM (
  -- admissionais: quem entrou nos ultimos 12 meses (12 primeiros em ordem estavel)
  SELECT 'adm:' || a.id::text AS chave, a.tenant_id, a.empresa_id, a.nome_completo, a.cpf, a.cargo, a.departamento,
         'admissional' AS subtipo, COALESCE(a.exame_admissional_data, a.data_admissao - 3) AS emissao,
         'apto' AS aptidao, NULL::text AS restricoes, NULL::text AS obs, NULL::uuid AS afastamento_id
    FROM (SELECT b.*, row_number() OVER (ORDER BY md5(b.id::text)) AS rk FROM public.admissoes b
           WHERE b.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND b.status = 'concluido'
             AND b.data_admissao BETWEEN CURRENT_DATE - 365 AND CURRENT_DATE - 5) a
   WHERE a.rk <= 12
  UNION ALL
  -- periodicos: 16 colaboradores com mais de 1 ano de casa, em varias faixas de vencimento
  SELECT 'per:' || p.id::text, p.tenant_id, p.empresa_id, p.nome_completo, p.cpf, p.cargo, p.departamento, 'periodico',
         CURRENT_DATE - (ARRAY[60, 95, 140, 175, 210, 245, 280, 300, 320, 341, 349, 356, 376, 402, 431, 458, 120, 45])[p.rk::int],
         CASE WHEN p.rk IN (4, 7) THEN 'apto_com_restricoes' WHEN p.rk = 14 THEN 'inapto_temporario' ELSE 'apto' END,
         CASE WHEN p.rk = 4 THEN 'Uso obrigatório de protetor auricular com dupla proteção em áreas acima de 85 dB(A).'
              WHEN p.rk = 7 THEN 'Evitar trabalho em altura e esforço lombar acima de 20 kg até reavaliação.'
              WHEN p.rk = 14 THEN 'Afastar das atividades de solda até nova audiometria.' END,
         CASE WHEN p.rk IN (17, 18) THEN NULL END, NULL::uuid
    FROM (SELECT b.*, row_number() OVER (ORDER BY md5(b.id::text || 'aso')) AS rk FROM public.admissoes b
           WHERE b.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND b.status = 'concluido'
             AND b.data_admissao <= CURRENT_DATE - 366) p
   WHERE p.rk <= 16
  UNION ALL
  -- mudanca de risco (funcao): 2 colaboradores
  SELECT 'risco:' || p.id::text, p.tenant_id, p.empresa_id, p.nome_completo, p.cpf, p.cargo, p.departamento, 'mudanca_risco',
         CURRENT_DATE - (ARRAY[120, 45])[(p.rk - 16)::int], 'apto', NULL,
         'Mudança de função para ' || p.cargo || ': exame de acordo com os novos riscos do posto.', NULL::uuid
    FROM (SELECT b.*, row_number() OVER (ORDER BY md5(b.id::text || 'aso')) AS rk FROM public.admissoes b
           WHERE b.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND b.status = 'concluido'
             AND b.data_admissao <= CURRENT_DATE - 366) p
   WHERE p.rk IN (17, 18)
  UNION ALL
  -- retorno ao trabalho (apos afastamentos de 15 dias ou mais)
  SELECT 'ret:' || af.id::text, af.tenant_id, af.empresa_id, af.colaborador_nome, af.colaborador_cpf, adm.cargo, adm.departamento,
         'retorno_trabalho', af.data_fim + 1, 'apto', NULL, 'Exame de retorno ao trabalho após afastamento; apto sem restrições.', af.id
    FROM public.afastamentos af
    JOIN public.admissoes adm ON adm.tenant_id = af.tenant_id AND adm.cpf = af.colaborador_cpf AND adm.status = 'concluido'
   WHERE af.id IN (public.demo_id('afast:12'), public.demo_id('afast:13'), public.demo_id('afast:14'))
  UNION ALL
  -- demissionais: desligados
  SELECT 'dem:' || a.id::text, a.tenant_id, a.empresa_id, a.nome_completo, a.cpf, a.cargo, a.departamento, 'demissional',
         COALESCE(a.data_desligamento, CURRENT_DATE - 10) - 2, 'apto', NULL, NULL::text, NULL::uuid
    FROM public.admissoes a
   WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status = 'desligado'
) x
WHERE NOT EXISTS (SELECT 1 FROM public.atestados t WHERE t.id = public.demo_id('aso:' || x.chave));

-- liga o ASO de retorno aos afastamentos correspondentes
UPDATE public.afastamentos a
   SET aso_retorno_id = t.id
  FROM public.atestados t
 WHERE t.afastamento_id = a.id AND t.tipo = 'ocupacional' AND t.subtipo_ocupacional = 'retorno_trabalho'
   AND a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.aso_retorno_id IS NULL;

-- ---------------------------------------------------------------------------
-- (8) Eventos de saude (cada um agrupa atestados/afastamentos de uma pessoa) e alertas
-- ---------------------------------------------------------------------------
INSERT INTO public.eventos_saude (
  id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, codigo, titulo, descricao,
  grupo_clinico_principal, nexo_trabalho, status, data_inicio, data_fim, total_atestados, total_dias_afastamento,
  observacoes, criado_por_nome, created_at
)
SELECT public.demo_id('evsaude:' || v.k), a.tenant_id, NULL, a.colaborador_nome, a.colaborador_cpf, 'EVS-TMP', v.titulo, v.descricao,
       a.motivo_principal, a.nexo_trabalho, v.status::public.evento_saude_status, a.data_inicio, a.data_fim,
       (SELECT count(*) FROM public.atestados t WHERE t.afastamento_id = a.id), COALESCE(a.dias_totais, 0),
       v.obs, 'Camila Duarte (RH)', a.data_inicio::timestamptz + interval '12 hours'
FROM (VALUES
  (1, 5,  'Fratura no trabalho (dedo da mão)', 'Acidente típico na montagem; CAT emitida e acompanhamento ortopédico.', 'em_acompanhamento', 'Investigação do acidente em andamento pela SESMT.'),
  (2, 6,  'Hérnia de disco lombar', 'Afastamento previdenciário (B31) por problema de coluna; reavaliação pericial agendada.', 'aberto', 'Acompanhar a perícia e o programa de reabilitação.'),
  (3, 12, 'Quadro ansioso e depressivo leve', 'Afastamento por CID F com entrevista de retorno; acompanhamento psicossocial.', 'em_acompanhamento', 'Encaminhado ao programa de bem-estar e escuta qualificada.'),
  (4, 9,  'Infecção respiratória sazonal', 'Episódio isolado, sem recorrência.', 'encerrado', NULL)
) AS v(k, af, titulo, descricao, status, obs)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || v.af)
WHERE NOT EXISTS (SELECT 1 FROM public.eventos_saude e WHERE e.id = public.demo_id('evsaude:' || v.k));

UPDATE public.atestados t
   SET evento_saude_id = public.demo_id('evsaude:' || v.k)
  FROM (VALUES (1, 5), (2, 6), (3, 12), (4, 9)) AS v(k, af)
 WHERE t.afastamento_id = public.demo_id('afast:' || v.af) AND t.evento_saude_id IS NULL
   AND EXISTS (SELECT 1 FROM public.eventos_saude e WHERE e.id = public.demo_id('evsaude:' || v.k));

UPDATE public.afastamentos a
   SET evento_saude_id = public.demo_id('evsaude:' || v.k)
  FROM (VALUES (1, 5), (2, 6), (3, 12), (4, 9)) AS v(k, af)
 WHERE a.id = public.demo_id('afast:' || v.af) AND a.evento_saude_id IS NULL
   AND EXISTS (SELECT 1 FROM public.eventos_saude e WHERE e.id = public.demo_id('evsaude:' || v.k));

INSERT INTO public.alertas_saude (
  id, tenant_id, tipo, referencia_tipo, referencia_id, colaborador_id, colaborador_nome, titulo, descricao, prioridade,
  lido, resolvido, resolvido_em, created_at
)
SELECT public.demo_id('alertasaude:' || v.chave), a.tenant_id, v.tipo, 'afastamento', a.id, NULL, a.colaborador_nome,
       v.titulo, v.descricao, v.prioridade, v.lido, v.resolvido,
       CASE WHEN v.resolvido THEN now() - interval '3 days' END, now() - (v.dias || ' days')::interval
FROM (VALUES
  ('af3',  3,  'afastamento_15_dias',   'Afastamento chegando a 15 dias', 'Faltam poucos dias para completar 15 dias de afastamento: decidir sobre o encaminhamento ao INSS.', 'media', false, false, 1),
  ('af4',  4,  'encaminhamento_inss',   'Afastamento acima de 15 dias (CID F)', 'Episódio acima de 15 dias com CID de saúde mental: encaminhar ao INSS e acionar o acompanhamento psicossocial.', 'alta', false, false, 3),
  ('af5',  5,  'aso_retorno_pendente',  'ASO de retorno ao trabalho será necessário', 'Afastamento acidentário de mais de 30 dias: agendar o exame de retorno antes da volta.', 'alta', false, false, 4),
  ('af2',  2,  'documento_pendente',    'Atestado original pendente', 'O afastamento foi registrado, mas falta anexar o atestado original assinado.', 'media', true, false, 6),
  ('af13', 13, 'cat_registrada',        'CAT de acidente de trajeto emitida', 'CAT emitida e enviada ao eSocial; acompanhar o recibo.', 'baixa', true, true, 30)
) AS v(chave, af, tipo, titulo, descricao, prioridade, lido, resolvido, dias)
JOIN public.afastamentos a ON a.id = public.demo_id('afast:' || v.af)
WHERE NOT EXISTS (SELECT 1 FROM public.alertas_saude x WHERE x.id = public.demo_id('alertasaude:' || v.chave));

INSERT INTO public.alertas_saude (
  id, tenant_id, tipo, referencia_tipo, referencia_id, colaborador_id, colaborador_nome, titulo, descricao, prioridade,
  lido, resolvido, created_at
)
SELECT public.demo_id('alertasaude:aso:' || t.id::text), t.tenant_id, 'aso_vencido', 'atestado', t.id, NULL, t.colaborador_nome,
       'ASO periódico vencido', 'O exame periódico venceu em ' || to_char(t.data_emissao + 365, 'DD/MM/YYYY') || '. Agendar novo exame com a clínica credenciada.',
       'alta', false, false, now() - interval '2 days'
FROM public.atestados t
WHERE t.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND t.tipo = 'ocupacional' AND t.subtipo_ocupacional = 'periodico'
  AND t.data_emissao + 365 < CURRENT_DATE
  AND NOT EXISTS (SELECT 1 FROM public.alertas_saude x WHERE x.id = public.demo_id('alertasaude:aso:' || t.id::text));

-- Reprocessa a inteligencia do GAF (marcadores, pendencias, NTEP) dos afastamentos que tem CID,
-- agora que o CID foi gravado. Feito uma unica vez por afastamento.
UPDATE public.afastamentos a
   SET observacoes = a.observacoes
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND EXISTS (SELECT 1 FROM public.afastamentos_saude s WHERE s.afastamento_id = a.id AND s.cid_principal IS NOT NULL)
   AND NOT EXISTS (SELECT 1 FROM public.gaf_auditoria g WHERE g.entidade_id = a.id AND g.acao = 'alteracao');
