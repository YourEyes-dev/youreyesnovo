-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto, Fase 2 / F2: catálogo de justificativas com
-- natureza e "aparece no app" (espelho da migration
-- 20261029180255_ponto_fase2_f2_catalogo_natureza.sql).
--
-- Colar INTEIRO no SQL Editor. Idempotente (pode rodar duas vezes). Não cria
-- tabela. Só cria colunas novas, uma trava, funções e casos de QA; nos dados,
-- só PREENCHE as colunas novas (natureza / aparece_no_app) e insere as linhas
-- APP_* — nenhum valor antigo é alterado, por isso não há backup.
-- O app atual do colaborador NÃO muda (as APP_* são do sistema e a lista do
-- app de hoje só mostra as criadas pela empresa).
--
-- Desfazer (se preciso):
--   DELETE FROM public.ponto_justificativas WHERE codigo LIKE 'APP\_%';
--   UPDATE public.ponto_justificativas SET natureza = NULL, aparece_no_app = false;
--   DROP TRIGGER IF EXISTS trg_justificativa_trava_natureza ON public.ponto_justificativas;
--
-- A última consulta mostra, por empresa (só o id e contagens): quantas APP_*,
-- ausências no app, criadas pela empresa ainda sem natureza (somem do app
-- novo até o RH classificar), divergências nome x regra, e o resultado dos
-- casos PONTO-491 e PONTO-497.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Colunas + CHECKs ---------------------------------------------------------
ALTER TABLE public.ponto_justificativas
  ADD COLUMN IF NOT EXISTS natureza text,
  ADD COLUMN IF NOT EXISTS aparece_no_app boolean NOT NULL DEFAULT false;

DO $ck$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ponto_justificativas_natureza_chk'
                    AND conrelid = 'public.ponto_justificativas'::regclass) THEN
    ALTER TABLE public.ponto_justificativas
      ADD CONSTRAINT ponto_justificativas_natureza_chk
      CHECK (natureza IS NULL OR natureza IN ('correcao_batida', 'ausencia'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ponto_justificativas_app_natureza_chk'
                    AND conrelid = 'public.ponto_justificativas'::regclass) THEN
    ALTER TABLE public.ponto_justificativas
      ADD CONSTRAINT ponto_justificativas_app_natureza_chk
      CHECK (NOT aparece_no_app OR natureza IS NOT NULL);
  END IF;
END $ck$;

COMMENT ON COLUMN public.ponto_justificativas.natureza IS
  'correcao_batida = corrige horário (grava como trabalho, não abona); ausencia = declaração/atestado (exige anexo); NULL = lançamento do RH (folga, day off...), fora do app.';
COMMENT ON COLUMN public.ponto_justificativas.aparece_no_app IS
  'true = o colaborador pode escolher no app novo de ajuste (exige natureza).';

-- 2) Trava de natureza ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_justificativa_trava_natureza()
RETURNS trigger LANGUAGE plpgsql SET search_path = 'public' AS $trava$
BEGIN
  IF NEW.base_legal IS NOT NULL AND btrim(NEW.base_legal) <> ''
     AND NEW.natureza = 'correcao_batida' THEN
    NEW.natureza := 'ausencia';          -- a lei prevalece: abono legal é ausência
  END IF;
  IF NEW.natureza = 'correcao_batida' THEN
    NEW.tipo_abono := 'nao';             -- correção de batida é trabalho, não abono
  END IF;
  IF NEW.natureza = 'ausencia' THEN
    NEW.requer_anexo := true;            -- ausência exige a declaração/atestado
  END IF;
  RETURN NEW;
END $trava$;

DROP TRIGGER IF EXISTS trg_justificativa_trava_natureza ON public.ponto_justificativas;
CREATE TRIGGER trg_justificativa_trava_natureza
  BEFORE INSERT OR UPDATE ON public.ponto_justificativas
  FOR EACH ROW EXECUTE FUNCTION public.ponto_justificativa_trava_natureza();

-- 3) Semente do app --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_justificativas_app(p_tenant uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $seedapp$
DECLARE rec RECORD;
BEGIN
  IF p_tenant IS NULL THEN RETURN; END IF;
  IF auth.uid() IS NOT NULL
     AND NOT COALESCE(public.is_superadmin(auth.uid()), false)
     AND p_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
    RAISE EXCEPTION 'Sem permissão para semear justificativas de outra empresa.';
  END IF;

  -- (a) Ausências que já existem: entram no app. Só as que JÁ exigem anexo
  --     (classificar uma sem anexo forçaria o anexo e mudaria o fluxo atual do RH).
  UPDATE public.ponto_justificativas
     SET natureza = 'ausencia', aparece_no_app = true, updated_at = now()
   WHERE tenant_id = p_tenant
     AND natureza IS NULL
     AND requer_anexo IS TRUE
     AND (codigo IN ('DECLARACAO_COMPARECIMENTO', 'ATESTADO_ACOMPANHAMENTO')
          OR codigo LIKE 'LEI\_%');

  -- (b) As 6 APP_*
  FOR rec IN
    SELECT * FROM (VALUES
      (101, 'APP_ESQUECI_REGISTRAR', 'Esqueci de registrar o ponto',              'correcao_batida', 'nao', false, NULL::text),
      (102, 'APP_FALHA_EQUIPAMENTO', 'Falha no equipamento / aplicativo',         'correcao_batida', 'nao', false, NULL::text),
      (103, 'APP_SEM_SINAL',         'Sem sinal de internet no momento',          'correcao_batida', 'nao', false, NULL::text),
      (104, 'APP_ERRO_REGISTRO',     'Erro ao registrar (horário incorreto)',     'correcao_batida', 'nao', false, NULL::text),
      (105, 'APP_REUNIAO_EXTERNA',   'Reunião externa / atendimento em cliente',  'correcao_batida', 'nao', false, NULL::text),
      (110, 'APP_ATESTADO_MEDICO',   'Atestado médico',                           'ausencia',        'sim', true,  'Lei 605/1949, art. 6º, § 1º, f')
    ) AS t(ordem, codigo, nome, natureza, tipo_abono, requer_anexo, base_legal)
  LOOP
    -- já existe pelo código: preserva nome, ativo, aparece_no_app e abono do cliente
    UPDATE public.ponto_justificativas
       SET sistema = true,
           ordem = rec.ordem,
           natureza = COALESCE(natureza, rec.natureza),
           base_legal = COALESCE(rec.base_legal, base_legal),
           updated_at = now()
     WHERE tenant_id = p_tenant AND empresa_id IS NULL AND codigo = rec.codigo;
    IF FOUND THEN CONTINUE; END IF;

    -- nome já usado pelo cliente: não adota nem duplica (o RH classifica a dele)
    IF EXISTS (SELECT 1 FROM public.ponto_justificativas
                WHERE tenant_id = p_tenant
                  AND lower(btrim(nome)) = lower(btrim(rec.nome))) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.ponto_justificativas
      (tenant_id, empresa_id, nome, codigo, tipo_abono, sistema, ativo, ordem,
       requer_anexo, horas_abono, base_legal, natureza, aparece_no_app)
    VALUES
      (p_tenant, NULL, rec.nome, rec.codigo, rec.tipo_abono, true, true, rec.ordem,
       rec.requer_anexo, 0, rec.base_legal, rec.natureza, true);
  END LOOP;
END $seedapp$;

REVOKE EXECUTE ON FUNCTION public.seed_justificativas_app(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_justificativas_app(uuid) TO authenticated;

DO $todos$
DECLARE t RECORD;
BEGIN
  FOR t IN SELECT DISTINCT tenant_id FROM public.usuarios_base WHERE tenant_id IS NOT NULL
  LOOP
    BEGIN
      PERFORM public.seed_justificativas_app(t.tenant_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'seed_justificativas_app falhou para tenant %: %', t.tenant_id, SQLERRM;
    END;
  END LOOP;
END $todos$;

-- 4) Aviso nome x regra -------------------------------------------------------------
-- Mesma regra de src/lib/ponto/justificativaDivergencia.ts (manter as duas iguais).
CREATE OR REPLACE FUNCTION public.ponto_justificativa_divergencia(p_nome text, p_tipo text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = 'public'
AS $diverg$
  WITH n AS (
    SELECT lower(translate(COALESCE(p_nome, ''),
             'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç',
             'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc')) AS s
  )
  SELECT CASE
    WHEN n.s ~ '(nao|sem)[[:space:]-]*abon' AND p_tipo = 'sim'
      THEN 'O nome diz que NÃO abona, mas a regra é Abona'
    WHEN n.s ~ 'nao[[:space:]-]*justificad' AND p_tipo = 'sim'
      THEN 'O nome diz que a falta NÃO é justificada, mas a regra é Abona'
    WHEN n.s ~ 'abon' AND n.s !~ '(nao|sem)[[:space:]-]*abon' AND p_tipo = 'nao'
      THEN 'O nome diz que abona, mas a regra é Não abona'
    ELSE NULL
  END
  FROM n
$diverg$;

GRANT EXECUTE ON FUNCTION public.ponto_justificativa_divergencia(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ponto_justificativas_divergencias(p_tenant uuid DEFAULT NULL)
RETURNS TABLE (tenant_id uuid, justificativa_id uuid, nome text, tipo_abono text, divergencia text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $divergs$
  SELECT j.tenant_id, j.id, j.nome, j.tipo_abono,
         public.ponto_justificativa_divergencia(j.nome, j.tipo_abono)
    FROM public.ponto_justificativas j
   WHERE public.ponto_justificativa_divergencia(j.nome, j.tipo_abono) IS NOT NULL
     AND CASE
           WHEN auth.uid() IS NULL OR COALESCE(public.is_superadmin(auth.uid()), false)
             THEN (p_tenant IS NULL OR j.tenant_id = p_tenant)
           ELSE j.tenant_id = public.get_user_tenant_id()
         END
   ORDER BY j.tenant_id, j.nome
$divergs$;

REVOKE EXECUTE ON FUNCTION public.ponto_justificativas_divergencias(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_justificativas_divergencias(uuid) TO authenticated;

-- 5) QA ---------------------------------------------------------------------------------

-- PONTO-491 — semente do app + travas (tudo desfeito no fim: qa_rollback)
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_491()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa491$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_app int; v_app_dist int; v_corr int; v_atest int; v_aus_sem_anexo int;
  v_id1 uuid := gen_random_uuid();
  v_id2 uuid := gen_random_uuid();
  v_abono_corr text; v_nat_legal text; v_anexo_legal boolean;
  v_check_ok boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Semear o catálogo do app 2 vezes no cercado e testar as travas de natureza';
  r.esperado    := '6 APP_* sem duplicar; 5 correções no app com abono Não; Atestado médico abona com anexo; '
                || 'ausência sempre exige anexo; correção forçada a Não abona; base legal vira ausência; '
                || 'CHECK recusa "no app" sem natureza';

  IF to_regprocedure('public.seed_justificativas_app(uuid)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'seed_justificativas_app ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  BEGIN
    PERFORM public.seed_justificativas_app(v_t);
    PERFORM public.seed_justificativas_app(v_t);

    v_app := (SELECT count(*) FROM public.ponto_justificativas
               WHERE tenant_id = v_t AND codigo LIKE 'APP\_%');
    v_app_dist := (SELECT count(DISTINCT codigo) FROM public.ponto_justificativas
                    WHERE tenant_id = v_t AND codigo LIKE 'APP\_%');
    v_corr := (SELECT count(*) FROM public.ponto_justificativas
                WHERE tenant_id = v_t AND codigo LIKE 'APP\_%'
                  AND natureza = 'correcao_batida' AND aparece_no_app AND tipo_abono = 'nao');
    v_atest := (SELECT count(*) FROM public.ponto_justificativas
                 WHERE tenant_id = v_t AND codigo = 'APP_ATESTADO_MEDICO'
                   AND natureza = 'ausencia' AND aparece_no_app AND tipo_abono = 'sim'
                   AND requer_anexo AND base_legal IS NOT NULL);
    v_aus_sem_anexo := (SELECT count(*) FROM public.ponto_justificativas
                         WHERE tenant_id = v_t AND natureza = 'ausencia' AND NOT requer_anexo);

    -- trava: correção com abono Sim vira Não abona
    INSERT INTO public.ponto_justificativas
      (id, tenant_id, empresa_id, nome, tipo_abono, natureza, aparece_no_app, ativo, ordem)
    VALUES (v_id1, v_t, NULL, '[QA-PONTO] F2 correção ' || v_id1, 'sim', 'correcao_batida', true, true, 900);
    v_abono_corr := (SELECT tipo_abono FROM public.ponto_justificativas WHERE id = v_id1);

    -- trava: base legal + correção vira ausência com anexo
    INSERT INTO public.ponto_justificativas
      (id, tenant_id, empresa_id, nome, tipo_abono, natureza, aparece_no_app, ativo, ordem,
       requer_anexo, base_legal)
    VALUES (v_id2, v_t, NULL, '[QA-PONTO] F2 legal ' || v_id2, 'nao', 'correcao_batida', true, true, 901,
            false, 'QA base legal');
    v_nat_legal := (SELECT natureza FROM public.ponto_justificativas WHERE id = v_id2);
    v_anexo_legal := (SELECT requer_anexo FROM public.ponto_justificativas WHERE id = v_id2);

    -- CHECK: "aparece no app" sem natureza é recusado
    BEGIN
      INSERT INTO public.ponto_justificativas
        (tenant_id, empresa_id, nome, natureza, aparece_no_app, ativo, ordem)
      VALUES (v_t, NULL, '[QA-PONTO] F2 sem natureza ' || gen_random_uuid(), NULL, true, true, 902);
      v_check_ok := false;
    EXCEPTION WHEN check_violation THEN
      v_check_ok := true;
    END;

    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('app', v_app, 'app_distintos', v_app_dist, 'correcoes_no_app', v_corr,
                                  'atestado_medico', v_atest, 'ausencias_sem_anexo', v_aus_sem_anexo,
                                  'abono_correcao', v_abono_corr, 'natureza_legal', v_nat_legal,
                                  'anexo_legal', v_anexo_legal, 'check_ok', v_check_ok);

  IF v_app = 6 AND v_app_dist = 6 AND v_corr = 5 AND v_atest = 1 AND v_aus_sem_anexo = 0
     AND v_abono_corr = 'nao' AND v_nat_legal = 'ausencia' AND v_anexo_legal IS TRUE
     AND v_check_ok THEN
    r.situacao := 'passou';
    r.obtido := 'Semente idempotente (6 APP_*); 5 correções no app sem abono; Atestado médico abona com anexo; '
             || 'travas de natureza e CHECK do app funcionando.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: APP_*=%s (distintos %s), correções no app=%s, atestado médico ok=%s, '
             || 'ausências sem anexo=%s, abono da correção=%s, natureza com base legal=%s (anexo %s), CHECK ok=%s.',
             v_app, v_app_dist, v_corr, v_atest, v_aus_sem_anexo, coalesce(v_abono_corr, '—'),
             coalesce(v_nat_legal, '—'), coalesce(v_anexo_legal::text, '—'), v_check_ok);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa491$;

-- PONTO-497 — aviso nome x regra (rotina que lista divergências)
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_497()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa497$
DECLARE
  r public.qa_retorno;
  v_pega int; v_falso int;
  v_por_tenant jsonb;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir o aviso nome x regra nos três padrões e contar as divergências da base';
  r.esperado    := 'Os 3 padrões divergentes são apontados; nomes coerentes não; detalhe traz a contagem por tenant';

  IF to_regprocedure('public.ponto_justificativa_divergencia(text,text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'ponto_justificativa_divergencia ausente.'; RETURN r;
  END IF;

  v_pega := (SELECT count(*) FROM (VALUES
               ('Falta não abonada', 'sim'),
               ('FALTA JUSTIFICADA NÃO ABONADA', 'sim'),
               ('Abono de horas', 'nao'),
               ('Falta não justificada', 'sim')) AS t(nome, tipo)
             WHERE public.ponto_justificativa_divergencia(t.nome, t.tipo) IS NOT NULL);
  v_falso := (SELECT count(*) FROM (VALUES
               ('Falta não abonada', 'nao'),
               ('FALTA JUSTIFICADA ABONADA', 'sim'),
               ('Abono', 'sim'),
               ('Folga', 'sim'),
               ('Esqueci de registrar o ponto', 'nao'),
               ('Falta não justificada', 'nao')) AS t(nome, tipo)
             WHERE public.ponto_justificativa_divergencia(t.nome, t.tipo) IS NOT NULL);

  -- só id do tenant e contagem (sem nomes)
  v_por_tenant := (SELECT COALESCE(jsonb_object_agg(x.tenant_id::text, x.n), '{}'::jsonb)
                     FROM (SELECT d.tenant_id, count(*) AS n
                             FROM public.ponto_justificativas_divergencias(NULL) d
                            GROUP BY d.tenant_id) x);
  r.detalhe := jsonb_build_object('divergencias_por_tenant', v_por_tenant);

  IF v_pega = 4 AND v_falso = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Aviso nome x regra pega os padrões divergentes e ignora os coerentes. Tenants com divergência: %s.',
                       (SELECT count(*) FROM jsonb_object_keys(v_por_tenant)));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: divergentes apontados=%s de 4; coerentes apontados por engano=%s.', v_pega, v_falso);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa497$;

-- Documentação dos casos + pontes
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-491/497/498 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-491',
   'Catálogo do app: semente APP_* idempotente e travas de natureza',
   'negativo', 'alta', 'aprovado', 'api',
   'Portaria MTP 671/2021 (tratamento de marcações); Lei 605/1949, art. 6º, § 1º, f; CLT art. 473',
   'O catálogo de justificativas separa correção de batida (trabalho, nunca abona) de ausência (declaração/atestado, sempre com anexo). '
   || 'A semente do app cria 5 correções e o Atestado médico (abona por lei) sem duplicar, e as travas garantem as regras mesmo via API.',
   'Cercado de QA (tenant sandbox).',
   '[{"ordem":1,"acao":"Rodar seed_justificativas_app 2 vezes no cercado","resultado_esperado":"6 APP_* sem duplicar; 5 correções no app com abono Não; Atestado médico abona, exige anexo e tem base legal"},
     {"ordem":2,"acao":"Gravar correção de batida com abono Sim","resultado_esperado":"A trava grava Não abona"},
     {"ordem":3,"acao":"Gravar correção com base legal","resultado_esperado":"Vira ausência e exige anexo"},
     {"ordem":4,"acao":"Gravar justificativa no app sem natureza","resultado_esperado":"Recusada pelo CHECK"}]'::jsonb,
   'Semente idempotente e travas ativas.',
   'Fase 2 do Ponto, F2 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).'),

  (v_mod, 'PONTO-497',
   'Aviso nome × regra: justificativa cujo nome contradiz o abono',
   'negativo', 'media', 'aprovado', 'api',
   'CLT art. 462 (descontos) e art. 473 (abonos)',
   'Evita cadastro que engana o RH: nome "Falta não abonada" com regra Abona (ou o inverso). '
   || 'A função ponto_justificativa_divergencia aponta os três padrões e ponto_justificativas_divergencias lista os casos por empresa.',
   'Nenhuma.',
   '[{"ordem":1,"acao":"Avaliar nomes divergentes (não abonada + Abona; abono + Não abona; não justificada + Abona)","resultado_esperado":"Os três padrões são apontados"},
     {"ordem":2,"acao":"Avaliar nomes coerentes","resultado_esperado":"Nenhum aviso"},
     {"ordem":3,"acao":"Contar divergências da base por empresa","resultado_esperado":"Detalhe com id da empresa e contagem (sem nomes)"}]'::jsonb,
   'Divergências apontadas e listadas por empresa.',
   'Fase 2 do Ponto, F2 (out/2026). A tela usa a mesma regra (src/lib/ponto/justificativaDivergencia.ts).'),

  (v_mod, 'PONTO-498',
   'Configurações › Justificativas mostra natureza, app e o aviso de nome × regra',
   'feliz', 'media', 'aprovado', 'e2e',
   'Portaria MTP 671/2021',
   'A janela de Justificativas mostra as colunas Natureza e No app, e avisa ao vivo quando o nome contradiz a regra de abono (ex.: "Falta não abonada" com "Sim (abona)").',
   'Usuário admin/RH; ambiente de teste.',
   '[{"ordem":1,"acao":"Em Ponto > Configurações > Geral, clicar em Configurar Justificativas","resultado_esperado":"A tabela mostra as colunas Natureza e No app"},
     {"ordem":2,"acao":"Digitar o nome Falta não abonada e escolher Sim (abona)","resultado_esperado":"Aparece o aviso de que o nome contradiz a regra (sem salvar)"}]'::jsonb,
   'Colunas novas visíveis e aviso ao vivo.',
   'Fase 2 do Ponto, F2 (out/2026). Não salva nada.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-491', 'qa_caso_ponto_491', true),
      ('PONTO-497', 'qa_caso_ponto_497', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;

  IF to_regclass('public.qa_cobertura_e2e') IS NOT NULL THEN
    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
      ('PONTO-498', 'cypress/e2e/ponto.cy.ts',
       'abre Configurações › Geral › Justificativas com natureza, app e aviso de nome × regra',
       true, now())
    ON CONFLICT (codigo) DO UPDATE SET
      spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-491/497/498 não registrada: %', SQLERRM;
END $doc$;

-- ── Conferência (única) ─────────────────────────────────────────────────────
WITH t AS MATERIALIZED (
  SELECT DISTINCT tenant_id FROM public.usuarios_base WHERE tenant_id IS NOT NULL
),
j AS MATERIALIZED (
  SELECT tenant_id,
         count(*) FILTER (WHERE codigo LIKE 'APP\_%')                              AS app_semeadas,
         count(*) FILTER (WHERE natureza = 'correcao_batida' AND aparece_no_app)  AS correcoes_no_app,
         count(*) FILTER (WHERE natureza = 'ausencia' AND aparece_no_app)         AS ausencias_no_app,
         count(*) FILTER (WHERE natureza = 'ausencia' AND NOT requer_anexo)       AS ausencias_sem_anexo,
         count(*) FILTER (WHERE natureza IS NULL AND NOT sistema)                 AS da_empresa_sem_natureza,
         count(*) FILTER (WHERE codigo = 'ATESTADO_ACOMPANHAMENTO' AND natureza IS NULL) AS acompanhamento_sem_natureza
    FROM public.ponto_justificativas
   GROUP BY tenant_id
),
d AS MATERIALIZED (
  SELECT x.tenant_id, count(*) AS divergencias
    FROM public.ponto_justificativas_divergencias(NULL) x
   GROUP BY x.tenant_id
),
q491 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_491() r),
q497 AS MATERIALIZED (SELECT r.situacao::text AS s, r.erro_tecnico FROM public.qa_caso_ponto_497() r)
SELECT t.tenant_id,
       COALESCE(j.app_semeadas, 0)                AS app_semeadas_esperado_6,
       COALESCE(j.correcoes_no_app, 0)            AS correcoes_no_app,
       COALESCE(j.ausencias_no_app, 0)            AS ausencias_no_app,
       COALESCE(j.ausencias_sem_anexo, 0)         AS ausencias_sem_anexo_esperado_0,
       COALESCE(j.da_empresa_sem_natureza, 0)     AS da_empresa_sem_natureza,
       COALESCE(j.acompanhamento_sem_natureza, 0) AS acompanhamento_sem_natureza,
       COALESCE(d.divergencias, 0)                AS divergencias_nome_regra,
       (SELECT position('trava_natureza' IN pg_get_triggerdef(tg.oid)) > 0
          FROM pg_trigger tg
         WHERE tg.tgrelid = 'public.ponto_justificativas'::regclass
           AND tg.tgname = 'trg_justificativa_trava_natureza')  AS trava_ok,
       (SELECT s FROM q491)            AS qa_ponto_491,
       (SELECT s FROM q497)            AS qa_ponto_497,
       concat_ws(' | ', (SELECT erro_tecnico FROM q491), (SELECT erro_tecnico FROM q497),
                 CASE WHEN (SELECT s FROM q491) <> 'passou' THEN (SELECT obtido FROM q491) END) AS erro_tecnico
  FROM t
  LEFT JOIN j ON j.tenant_id = t.tenant_id
  LEFT JOIN d ON d.tenant_id = t.tenant_id
 ORDER BY t.tenant_id;
