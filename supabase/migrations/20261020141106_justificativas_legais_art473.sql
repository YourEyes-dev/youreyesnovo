-- =====================================================================
-- Declaracao de comparecimento — FATIA 1: catalogo de abono completo
--
-- Hoje o seed de justificativas traz 12 padroes OPERACIONAIS, mas NAO traz
-- as situacoes de abono OBRIGATORIO POR LEI (art. 473 da CLT). Esta fatia:
--
--  1) Adiciona a coluna public.ponto_justificativas.base_legal (a citacao
--     legal). base_legal NOT NULL = "por lei": o abono e obrigatorio (sim) e
--     nao pode ser editado nem a linha excluida.
--  2) Trava por gatilho: em qualquer INSERT/UPDATE, se base_legal esta
--     preenchida, forca tipo_abono='sim' e sistema=true. Garante a lei mesmo
--     que a UI ou a API tentem mudar.
--  3) Semeia o catalogo do art. 473 (falecimento, casamento, doacao de
--     sangue, alistamento, vestibular, Justica, acompanhar gestante/filho,
--     exame preventivo de cancer) como sistema + abona=sim + base_legal, para
--     todo tenant ja nascer em conformidade.
--
-- NAO mexe em lancamento nem no calculo do espelho. So catalogo (dados) + a
-- trava legal. A "Declaracao de comparecimento" como documento vem na Fatia 2.
-- Idempotente (casa por codigo, depois por nome, senao insere).
-- =====================================================================

SET lock_timeout = '10s';

ALTER TABLE public.ponto_justificativas
  ADD COLUMN IF NOT EXISTS base_legal text;

COMMENT ON COLUMN public.ponto_justificativas.base_legal IS
  'Citacao legal quando o abono e obrigatorio por lei (art. 473 CLT). NOT NULL => abono travado em sim, linha nao editavel/excluivel.';

-- Trava legal: base_legal preenchida => abono obrigatorio por lei.
CREATE OR REPLACE FUNCTION public.ponto_justificativa_trava_legal()
RETURNS trigger LANGUAGE plpgsql SET search_path = 'public' AS $trava$
BEGIN
  IF NEW.base_legal IS NOT NULL AND btrim(NEW.base_legal) <> '' THEN
    NEW.tipo_abono := 'sim';   -- abono obrigatorio por lei (nao editavel)
    NEW.sistema    := true;    -- nao excluivel
  END IF;
  RETURN NEW;
END $trava$;

DROP TRIGGER IF EXISTS trg_justificativa_trava_legal ON public.ponto_justificativas;
CREATE TRIGGER trg_justificativa_trava_legal
  BEFORE INSERT OR UPDATE ON public.ponto_justificativas
  FOR EACH ROW EXECUTE FUNCTION public.ponto_justificativa_trava_legal();

-- Seed do catalogo legal (art. 473) para um tenant. Idempotente:
--   1) casa por codigo; 2) adota uma linha de mesmo nome (evita duplicar um
--   cadastro manual); 3) senao, insere.
CREATE OR REPLACE FUNCTION public.seed_justificativas_legais(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $seed$
DECLARE rec RECORD;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      (21, 'Falecimento (luto)',                          'LEI_FALECIMENTO',           'CLT art. 473, I — 2 dias'),
      (22, 'Casamento (gala)',                            'LEI_CASAMENTO',             'CLT art. 473, II — 3 dias'),
      (23, 'Doacao de sangue',                            'LEI_DOACAO_SANGUE',         'CLT art. 473, IV — 1 dia a cada 12 meses'),
      (24, 'Alistamento eleitoral',                       'LEI_ALISTAMENTO_ELEITORAL', 'CLT art. 473, V — ate 2 dias'),
      (25, 'Vestibular / ENEM',                           'LEI_VESTIBULAR',            'CLT art. 473, VII'),
      (26, 'Comparecimento a Justica',                    'LEI_COMPARECIMENTO_JUIZO',  'CLT art. 473, VIII'),
      (27, 'Acompanhar gestante (consultas e exames)',    'LEI_ACOMP_GESTANTE',        'CLT art. 473, X — ate 2 dias'),
      (28, 'Acompanhar filho ate 6 anos (consulta)',      'LEI_ACOMP_FILHO',           'CLT art. 473, XI — 1 dia por ano'),
      (29, 'Exame preventivo de cancer',                  'LEI_PREVENTIVO_CANCER',     'CLT art. 473, XII — ate 3 dias a cada 12 meses')
    ) AS t(ordem, nome, codigo, base_legal)
  LOOP
    -- 1) por codigo
    UPDATE public.ponto_justificativas
      SET base_legal = rec.base_legal, tipo_abono = 'sim', sistema = true,
          ordem = rec.ordem, updated_at = now()
    WHERE tenant_id = p_tenant_id AND empresa_id IS NULL AND codigo = rec.codigo;
    IF FOUND THEN CONTINUE; END IF;

    -- 2) adota uma linha de mesmo nome (sem codigo ou com o mesmo codigo)
    UPDATE public.ponto_justificativas
      SET codigo = rec.codigo, base_legal = rec.base_legal, tipo_abono = 'sim',
          sistema = true, ordem = rec.ordem, updated_at = now()
    WHERE tenant_id = p_tenant_id AND empresa_id IS NULL
      AND lower(btrim(nome)) = lower(btrim(rec.nome))
      AND (codigo IS NULL OR codigo = rec.codigo);
    IF FOUND THEN CONTINUE; END IF;

    -- 3) insere
    INSERT INTO public.ponto_justificativas
      (tenant_id, empresa_id, nome, codigo, tipo_abono, sistema, ativo, ordem,
       requer_anexo, horas_abono, base_legal)
    VALUES
      (p_tenant_id, NULL, rec.nome, rec.codigo, 'sim', true, true, rec.ordem,
       true, 0, rec.base_legal);
  END LOOP;
END $seed$;

REVOKE EXECUTE ON FUNCTION public.seed_justificativas_legais(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seed_justificativas_legais(uuid) TO authenticated;

-- Semeia para todos os tenants existentes.
DO $todos$
DECLARE t RECORD;
BEGIN
  FOR t IN SELECT DISTINCT tenant_id FROM public.usuarios_base WHERE tenant_id IS NOT NULL
  LOOP
    BEGIN
      PERFORM public.seed_justificativas_legais(t.tenant_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'seed_justificativas_legais falhou para tenant %: %', t.tenant_id, SQLERRM;
    END;
  END LOOP;
END $todos$;

-- ── QA: caso ABONO-473 (nivel api) — o catalogo legal existe e esta travado ──
CREATE OR REPLACE FUNCTION public.qa_caso_abono_473()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $qa$
DECLARE r public.qa_retorno; v_t uuid; v_n int; v_fora int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Semear e conferir o catalogo legal do art. 473 no sandbox';
  r.esperado    := 'As 9 situacoes do art. 473 existem como base_legal + abona=sim (travado).';

  IF to_regprocedure('public.seed_justificativas_legais(uuid)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'seed_justificativas_legais ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  PERFORM public.seed_justificativas_legais(v_t);

  v_n := (SELECT count(*) FROM public.ponto_justificativas
          WHERE tenant_id = v_t AND base_legal IS NOT NULL);
  v_fora := (SELECT count(*) FROM public.ponto_justificativas
             WHERE tenant_id = v_t AND base_legal IS NOT NULL AND tipo_abono <> 'sim');

  IF v_n >= 9 AND v_fora = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('%s situacoes legais, todas abona=sim (travadas).', v_n);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('legais=%s (esperado >=9), fora_da_lei=%s (esperado 0).', v_n, v_fora);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; caso ABONO-473 nao documentado.'; RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN RAISE NOTICE 'Modulo jornada-rotina/ponto ausente.'; RETURN; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'ABONO-473',
   'As justificativas de abono obrigatorio por lei (art. 473) vem cadastradas e travadas',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT art. 473',
   'O catalogo de justificativas deve trazer as situacoes de abono obrigatorio por lei (art. 473), como abona=sim e nao editaveis/excluiveis, separando-as das discricionarias da empresa.',
   'seed_justificativas_legais presente.',
   '[{"ordem":1,"acao":"Semear o catalogo legal no sandbox e contar as linhas com base_legal","resultado_esperado":"9+ situacoes do art. 473, todas abona=sim e travadas"}]'::jsonb,
   'O catalogo legal esta semeado e travado em abona=sim.',
   'Declaracao de comparecimento, Fatia 1.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('ABONO-473', 'qa_caso_abono_473', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao ABONO-473 nao registrada: %', SQLERRM;
END $doc$;
