-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 01e: Ponto: marcacoes e apuracao do mes corrente ate hoje
--
-- PARA QUE SERVE
-- Marcacoes do mes corrente ate hoje dos 59 colaboradores que batem ponto. Cada marcacao entra por INSERT em
-- ponto_marcacoes e os gatilhos do sistema geram NSR, hash, classificacao CLT, auditoria, a
-- apuracao diaria (ponto_diario) e os alertas de falta/atraso. Faltas: consolidar_ponto_diario_manual.
-- Feriados e folgas de escala: funcoes oficiais. Dia que o sistema recusa (afastado) fica sem batida
-- e dia ja apurado (ferias, atestado, afastamento) nao e refeito.
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
  IF NOT EXISTS (SELECT 1 FROM public.ponto_escalas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Rode antes a parte_01a (escalas e instrumentos do ponto).';
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
-- (6) Gerador de marcacoes do historico (funcoes auxiliares, removidas no fim)
--     Cada marcacao entra por INSERT em ponto_marcacoes e os gatilhos do sistema
--     fazem o resto (hash, NSR, classificacao, apuracao diaria, alertas).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.demo_ponto_marca_dia(
  p_cpf text, p_colab uuid, p_nome text, p_dia date, p_horas time[], p_tipos text[], p_disp text, p_agora time)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_n integer;
BEGIN
  -- Todas as batidas do dia entram num unico INSERT: os gatilhos de apuracao so
  -- rodam depois que o dia esta completo (sem estados intermediarios).
  INSERT INTO public.ponto_marcacoes (
    id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    data_marcacao, hora_marcacao, tipo_marcacao, ip_origem, user_agent, latitude, longitude, dispositivo,
    hash_marcacao, marcacao_original, created_at)
  SELECT public.demo_id('marc:' || p_cpf || '|' || p_dia::text || '|' || u.ord::text),
         'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         p_colab, p_nome, p_cpf, p_dia, u.hora, u.tipo,
         '10.20.' || (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text, 4) + 1) || '.' || (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'i', 200) + 10),
         CASE WHEN p_disp = 'Mobile' THEN 'Mozilla/5.0 (Linux; Android 13) YourEyes/1.0 Mobile'
              ELSE 'Mozilla/5.0 (Windows NT 10.0; Win64) YourEyes/1.0' END,
         -26.3045 + CASE WHEN public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'fc', 100) < 2 THEN 0.006
                         ELSE (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'la', 800) - 400) / 1000000.0 END,
         -48.8487 + (public.demo_ponto_rnd(p_cpf || p_dia::text || u.ord::text || 'lo', 800) - 400) / 1000000.0,
         p_disp, 'demo', true,
         (p_dia + u.hora) AT TIME ZONE 'America/Sao_Paulo'
  FROM unnest(p_horas, p_tipos) WITH ORDINALITY AS u(hora, tipo, ord)
  WHERE (p_dia < (timezone('America/Sao_Paulo', now()))::date OR (p_agora > time '00:10' AND u.hora <= p_agora - interval '8 minutes'))
    AND NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m WHERE m.id = public.demo_id('marc:' || p_cpf || '|' || p_dia::text || '|' || u.ord::text))
  ORDER BY u.ord;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$fn$;

CREATE OR REPLACE FUNCTION public.demo_ponto_gerar(p_ini date, p_fim date)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
  c_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  c_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_hoje date := (timezone('America/Sao_Paulo', now()))::date;
  v_agora time := (timezone('America/Sao_Paulo', now()))::time;
  v_fechado_ate date := (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '1 month')::date - 1;
  r record;
  v_dia date;
  v_dow int;
  v_dk text;
  v_cfg jsonb;
  v_rev boolean;
  v_trab_dia boolean;
  v_feriado text;
  v_k text;
  v_ent time; v_sai time; v_ia time; v_fa time;
  v_ent_r time; v_sai_r time; v_ai_r time; v_af_r time;
  v_ioff int; v_soff int; v_ldur int; v_x int;
  v_heavy boolean; v_late boolean; v_saidor boolean; v_faltoso boolean; v_intcurto boolean; v_extra boolean; v_over boolean;
  v_jorn int; v_trab int; v_short int;
  v_disp text;
  v_hs time[];
  v_ts text[];
  v_i int;
  v_total int := 0;
  v_acao text;
  v_erros integer := 0;
  v_ultimo_erro text;
BEGIN
  FOR r IN
    SELECT s.n, a.id, a.nome_completo AS nome, a.cpf, a.data_admissao, a.departamento, a.cargo
    FROM generate_series(1, 59) s(n)
    JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || s.n)
    WHERE a.status = 'concluido' AND COALESCE(a.bate_ponto, true)
    ORDER BY s.n
  LOOP
    v_heavy := r.n % 6 = 0;
    v_late := r.n % 9 = 4;
    v_saidor := r.n % 8 = 3;
    v_faltoso := r.n % 13 = 5;
    v_intcurto := r.n % 11 = 3;
    v_extra := r.n % 5 = 2;
    v_over := r.n IN (29, 41, 53);
    v_disp := CASE WHEN r.departamento IN ('Administrativo', 'Recursos Humanos', 'Comercial') THEN 'Desktop' ELSE 'Mobile' END;

    FOR v_dia IN
      SELECT g::date FROM generate_series(GREATEST(p_ini, r.data_admissao), LEAST(p_fim, v_hoje), interval '1 day') g
    LOOP
      -- dia passado que ja tem apuracao: nao refaz (idempotencia e competencia fechada)
      -- (dia que ainda estava incompleto pode ter sido "hoje" numa execucao anterior: replaneja, e
      --  o que ja existe nao e regravado porque cada batida tem id fixo)
      IF v_dia < v_hoje AND EXISTS (
           SELECT 1 FROM public.ponto_diario d
           WHERE d.tenant_id = c_t AND d.colaborador_cpf = r.cpf AND d.data = v_dia AND d.status <> 'incompleto') THEN
        CONTINUE;
      END IF;

      v_dow := EXTRACT(DOW FROM v_dia)::int;
      v_dk := (ARRAY['domingo','segunda','terca','quarta','quinta','sexta','sabado'])[v_dow + 1];
      v_k := r.n::text || '|' || v_dia::text;

      v_cfg := (SELECT e.dias_config -> v_dk
                FROM public.ponto_escala_atribuicoes pa
                JOIN public.ponto_escalas e ON e.id = pa.escala_id
                WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                  AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                ORDER BY pa.data_inicio DESC LIMIT 1);
      v_rev := COALESCE((SELECT e.modalidade = 'revezamento'
                FROM public.ponto_escala_atribuicoes pa
                JOIN public.ponto_escalas e ON e.id = pa.escala_id
                WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                  AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                ORDER BY pa.data_inicio DESC LIMIT 1), false);
      IF v_cfg IS NULL THEN
        CONTINUE;  -- sem escala vigente neste dia
      END IF;
      v_trab_dia := COALESCE((v_cfg ->> 'trabalha')::boolean, false);
      v_feriado := (SELECT h.nome FROM public.feriados_da_empresa(c_t, c_e, v_dia, v_dia) h LIMIT 1);

      v_acao := 'nada';
      v_hs := ARRAY[]::time[];
      v_ts := ARRAY[]::text[];

      IF v_trab_dia THEN
        v_ent := (v_cfg ->> 'entrada')::time;
        v_sai := (v_cfg ->> 'saida')::time;
        v_ia := (v_cfg ->> 'inicio_almoco')::time;
        v_fa := (v_cfg ->> 'fim_almoco')::time;

        IF v_feriado IS NOT NULL AND r.n % 7 <> 0 THEN
          v_acao := 'neutro';
        ELSIF v_dia < v_hoje
              AND v_dia > r.data_admissao + 3
              AND public.demo_ponto_rnd(v_k || 'f', 1000) < (CASE WHEN v_faltoso THEN 55 ELSE 16 END) THEN
          v_acao := 'falta';
        ELSE
          v_acao := 'marcar';
          -- entrada
          v_x := public.demo_ponto_rnd(v_k || 'e', 1000);
          IF v_late AND v_x < 190 THEN
            v_ioff := 11 + public.demo_ponto_rnd(v_k || 'e2', 30);
          ELSIF v_x < 30 THEN
            v_ioff := 11 + public.demo_ponto_rnd(v_k || 'e2', 18);
          ELSIF v_x < 130 THEN
            v_ioff := -(6 + public.demo_ponto_rnd(v_k || 'e2', 10));
          ELSE
            v_ioff := -5 + public.demo_ponto_rnd(v_k || 'e2', 10);
          END IF;
          -- saida
          v_x := public.demo_ponto_rnd(v_k || 's', 1000);
          IF v_rev THEN
            -- 6x2: quase sem hora extra (acima de 6 h o intervalo teria de ser de 1 h)
            IF v_heavy AND v_x < 150 THEN v_soff := 15 + public.demo_ponto_rnd(v_k || 's2', 45);
            ELSIF v_saidor AND v_x < 250 THEN v_soff := -(10 + public.demo_ponto_rnd(v_k || 's2', 26));
            ELSIF v_x < 40 THEN v_soff := -(6 + public.demo_ponto_rnd(v_k || 's2', 25));
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSIF v_heavy THEN
            IF v_x < 330 THEN v_soff := 30 + public.demo_ponto_rnd(v_k || 's2', 90);
            ELSIF v_x < 345 THEN v_soff := 125 + public.demo_ponto_rnd(v_k || 's2', 80);
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSIF v_saidor THEN
            IF v_x < 300 THEN v_soff := -(15 + public.demo_ponto_rnd(v_k || 's2', 36));
            ELSIF v_x < 360 THEN v_soff := 10 + public.demo_ponto_rnd(v_k || 's2', 25);
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          ELSE
            IF v_x < (CASE WHEN v_extra THEN 260 ELSE 130 END) THEN v_soff := 12 + public.demo_ponto_rnd(v_k || 's2', 48);
            ELSIF v_x < (CASE WHEN v_extra THEN 290 ELSE 165 END) THEN v_soff := -(6 + public.demo_ponto_rnd(v_k || 's2', 40));
            ELSE v_soff := public.demo_ponto_rnd(v_k || 's2', 5);
            END IF;
          END IF;
          -- sobrecarga recente: tres colaboradores com jornadas muito longas nas ultimas 7 semanas
          IF v_over AND v_dia >= v_hoje - 50 AND public.demo_ponto_rnd(v_k || 'ov', 100) < 55 THEN
            v_soff := 140 + public.demo_ponto_rnd(v_k || 'ov2', 95);
            v_ioff := -public.demo_ponto_rnd(v_k || 'ov3', 8);
          END IF;
          v_ent_r := v_ent + make_interval(mins => v_ioff, secs => public.demo_ponto_rnd(v_k || 'es', 60));
          v_sai_r := v_sai + make_interval(mins => v_soff, secs => public.demo_ponto_rnd(v_k || 'ss', 60));

          -- intervalo (almoco, ou 15 min no turno B)
          v_x := public.demo_ponto_rnd(v_k || 'l', 1000);
          IF v_rev THEN v_ldur := 15 + public.demo_ponto_rnd(v_k || 'l2', 4);
          ELSIF v_intcurto AND v_x < 250 THEN v_ldur := 32 + public.demo_ponto_rnd(v_k || 'l2', 20);
          ELSIF v_x < 15 THEN v_ldur := 40 + public.demo_ponto_rnd(v_k || 'l2', 15);
          ELSIF v_x < 260 THEN v_ldur := 63 + public.demo_ponto_rnd(v_k || 'l2', 13);
          ELSE v_ldur := 60 + public.demo_ponto_rnd(v_k || 'l2', 3);
          END IF;
          v_ai_r := v_ia + make_interval(mins => public.demo_ponto_rnd(v_k || 'a', 8) - 2, secs => public.demo_ponto_rnd(v_k || 'as', 60));
          v_af_r := v_ai_r + make_interval(mins => v_ldur, secs => public.demo_ponto_rnd(v_k || 'fs', 40));
          v_hs := ARRAY[v_ent_r, v_ai_r, v_af_r, v_sai_r];
          v_ts := ARRAY['entrada', 'saida_almoco', 'retorno_almoco', 'saida'];

          -- dia curto sem motivo: nas competencias fechadas (e em 90% das demais) o
          -- gerador evita ficar 60 min ou mais abaixo da jornada (isso viraria pendencia)
          v_jorn := (EXTRACT(EPOCH FROM (v_sai - v_ent)) / 60)::int - (EXTRACT(EPOCH FROM (v_fa - v_ia)) / 60)::int;
          v_trab := ((EXTRACT(EPOCH FROM (v_ai_r - v_ent_r)) + EXTRACT(EPOCH FROM (v_sai_r - v_af_r))) / 60)::int;
          v_short := v_jorn - v_trab;
          IF v_short >= 56 AND (v_dia <= v_fechado_ate OR public.demo_ponto_rnd(v_k || 'c', 100) < 90) THEN
            v_sai_r := v_sai_r + make_interval(mins => v_short - 38 + public.demo_ponto_rnd(v_k || 'c2', 8));
            v_hs[4] := v_sai_r;
          END IF;

          -- turno A: em alguns dias o colaborador nao bate o almoco (vale o intervalo pre-assinalado)
          IF NOT v_rev AND r.departamento IN ('Produção', 'Manutenção', 'Logística')
             AND public.demo_ponto_rnd(v_k || 'p2', 100) < 12 THEN
            v_hs := ARRAY[v_ent_r, v_hs[4]];
            v_ts := ARRAY['entrada', 'saida'];
          END IF;

          -- hoje: quem costuma atrasar chega tarde e sai cedo para uma consulta (dia completo, com atraso)
          IF v_dia = v_hoje AND v_late AND NOT v_rev THEN
            v_hs := ARRAY[v_ent + make_interval(mins => 12 + public.demo_ponto_rnd(v_k || 'td', 14), secs => public.demo_ponto_rnd(v_k || 'tds', 60)),
                          '11:40'::time + make_interval(mins => public.demo_ponto_rnd(v_k || 'tf', 10), secs => public.demo_ponto_rnd(v_k || 'tfs', 60))];
            v_ts := ARRAY['entrada', 'saida'];
          END IF;

          -- esquecimento de batida de saida (vira ajuste de inclusao mais adiante)
          IF v_dia < v_hoje AND public.demo_ponto_rnd(v_k || 'x', 1000) < 6 THEN
            v_hs := v_hs[1:(array_length(v_hs, 1) - 1)];
            v_ts := v_ts[1:(array_length(v_ts, 1) - 1)];
          END IF;
        END IF;

      ELSE
        -- dia de folga na escala
        IF v_rev AND v_dow BETWEEN 1 AND 5 THEN
          v_acao := 'folga';
        ELSIF NOT v_rev AND v_feriado IS NULL THEN
          v_ent := (SELECT (e.dias_config -> 'segunda' ->> 'entrada')::time
                    FROM public.ponto_escala_atribuicoes pa JOIN public.ponto_escalas e ON e.id = pa.escala_id
                    WHERE pa.tenant_id = c_t AND pa.colaborador_id = r.id::text
                      AND pa.data_inicio <= v_dia AND (pa.data_fim IS NULL OR pa.data_fim >= v_dia)
                    ORDER BY pa.data_inicio DESC LIMIT 1);
          IF v_dow = 6 AND v_ent IS NOT NULL THEN
            -- sabado extra: forte na equipe de muita hora extra, raro nos demais
            IF public.demo_ponto_rnd(v_k || 'sab', 1000) < (CASE WHEN v_heavy THEN 300 ELSE 25 END) THEN
              v_ent_r := v_ent + make_interval(mins => public.demo_ponto_rnd(v_k || 'e2', 10) - 3, secs => public.demo_ponto_rnd(v_k || 'es', 60));
              v_sai_r := v_ent_r + make_interval(mins => 190 + public.demo_ponto_rnd(v_k || 's2', 45), secs => public.demo_ponto_rnd(v_k || 'ss', 60));
              v_hs := ARRAY[v_ent_r, v_sai_r];
              v_ts := ARRAY['entrada', 'saida'];
              v_acao := 'marcar';
            END IF;
          ELSIF v_dow = 0 AND v_ent IS NOT NULL AND r.cargo = 'Mecânico de Manutenção' THEN
            -- plantao de domingo da manutencao (hora extra 100%)
            IF public.demo_ponto_rnd(v_k || 'dom', 1000) < 50 THEN
              v_ent_r := '08:00'::time + make_interval(mins => public.demo_ponto_rnd(v_k || 'e2', 8), secs => public.demo_ponto_rnd(v_k || 'es', 60));
              v_sai_r := v_ent_r + make_interval(mins => 200 + public.demo_ponto_rnd(v_k || 's2', 35), secs => public.demo_ponto_rnd(v_k || 'ss', 60));
              v_hs := ARRAY[v_ent_r, v_sai_r];
              v_ts := ARRAY['entrada', 'saida'];
              v_acao := 'marcar';
            END IF;
          END IF;
        END IF;
      END IF;

      IF v_acao = 'marcar' THEN
        -- hoje: so entra o que ja "aconteceu" (o sistema recusa marcacao no futuro)
        BEGIN
          v_total := v_total + public.demo_ponto_marca_dia(r.cpf, r.id, r.nome, v_dia, v_hs, v_ts, v_disp, v_agora);
        EXCEPTION WHEN OTHERS THEN
          -- dia que o sistema recusa (ex.: colaborador afastado): fica sem batida, e a
          -- apuracao do dia segue a regra do afastamento
          v_erros := v_erros + 1;
          v_ultimo_erro := SQLERRM;
          BEGIN
            PERFORM public.consolidar_ponto_diario_manual(c_t, r.cpf, v_dia);
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END;
      ELSIF v_acao IN ('falta', 'neutro', 'folga') THEN
        BEGIN
          IF v_acao = 'falta' THEN
            PERFORM public.consolidar_ponto_diario_manual(c_t, r.cpf, v_dia);
          ELSIF v_acao = 'neutro' THEN
            PERFORM public.ponto_grava_feriado_neutro(c_t, c_e, r.id, r.nome, r.cpf, v_dia, v_feriado);
          ELSE
            PERFORM public._ponto_grava_abono(c_t, r.id, r.nome, r.cpf, v_dia, 'Folga de escala 6x2 (rodízio do turno B)');
          END IF;
          v_total := v_total + 1;
        EXCEPTION WHEN OTHERS THEN
          v_erros := v_erros + 1;
          v_ultimo_erro := SQLERRM;
        END;
      END IF;
    END LOOP;
  END LOOP;
  IF v_erros > 0 THEN
    RAISE NOTICE 'Informativo: % dia(s) ficaram sem batida porque o sistema as recusou (ex.: afastamento): %', v_erros, v_ultimo_erro;
  END IF;
  RETURN v_total;
END
$fn$;

DO $g1$
BEGIN
  PERFORM public.demo_ponto_gerar((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 0, LEAST((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 6, ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date - 1));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 1 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g1$;

DO $g2$
BEGIN
  PERFORM public.demo_ponto_gerar((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 7, LEAST((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 13, ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date - 1));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 2 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g2$;

DO $g3$
BEGIN
  PERFORM public.demo_ponto_gerar((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 14, LEAST((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 20, ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date - 1));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 3 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g3$;

DO $g4$
BEGIN
  PERFORM public.demo_ponto_gerar((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 21, LEAST((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 27, ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date - 1));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 4 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g4$;

DO $g5$
BEGIN
  PERFORM public.demo_ponto_gerar((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 28, LEAST((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + 34, ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date - 1));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Marcacoes da semana 5 nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $g5$;

DROP FUNCTION IF EXISTS public.demo_ponto_marca_dia(text, uuid, text, date, time without time zone[], text[], text, time without time zone);
DROP FUNCTION IF EXISTS public.demo_ponto_gerar(date, date);

DROP FUNCTION IF EXISTS public.demo_ponto_rnd(text, integer);

-- Conferencia final (uma linha)
SELECT
  (SELECT count(*) FROM public.ponto_marcacoes m WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.data_marcacao >= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date AND m.data_marcacao < ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date) AS marcacoes_do_mes,
  (SELECT count(*) FROM public.ponto_diario m WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.data >= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date AND m.data < ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date) AS dias_apurados,
  (SELECT count(DISTINCT m.colaborador_cpf) FROM public.ponto_marcacoes m WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.data_marcacao >= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date AND m.data_marcacao < ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date) AS colaboradores,
  CASE WHEN (SELECT count(*) FROM public.ponto_marcacoes m WHERE m.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND m.data_marcacao >= (date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date AND m.data_marcacao < ((date_trunc('month', timezone('America/Sao_Paulo', now())) - interval '0 months')::date + interval '1 month')::date) > 500 THEN 'OK' ELSE 'CONFERIR' END AS situacao;