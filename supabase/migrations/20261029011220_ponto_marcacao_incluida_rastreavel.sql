-- ============================================================================
-- Ponto — marcação incluída por ajuste nasce identificada e ligada ao ajuste
-- Plano do Ponto, Fase 2 / F1  (Portaria MTP 671/2021: marcação tratada deve
-- ser distinguível da original e rastreável até o motivo)
-- ----------------------------------------------------------------------------
-- Defeito: a coluna origem_marcacao tem DEFAULT 'O'. O gatilho
-- ponto_marcacoes_origem_sync só trocava para 'A' quando a origem chegava NULL —
-- mas o DEFAULT é aplicado ANTES do gatilho. Resultado: a marcação gravada pela
-- aprovação de ajuste (processar_ajuste_ponto, _ponto_gera_batidas_dia_inteiro)
-- nascia rotulada como ORIGINAL e saía sem marca no espelho e no AEJ.
-- Além disso, a ligação marcação <-> ajuste (hash 'AJUSTE-<id>') era
-- sobrescrita pelo gatilho de hash; não havia como chegar ao motivo.
--
-- Correção (sem tocar nas funções de aprovação):
--   * coluna nova ponto_marcacoes.ajuste_id (ligação, sem FK);
--   * gatilho de origem: na INSERÇÃO, marcação não original nasce 'A'; e se o
--     hash veio 'AJUSTE-<uuid>...', guarda o uuid em ajuste_id. O gatilho roda
--     antes de trigger_gerar_hash_marcacao (ordem alfabética), então ainda vê
--     o hash do ajuste;
--   * dados antigos: não originais com origem 'O' passam a 'A'; ajuste_id é
--     preenchido onde o casamento com o ajuste aprovado é inequívoco (1:1).
--     A trava de imutabilidade não protege essas duas colunas e a cadeia de hash
--     não as inclui; o gatilho de auditoria registra cada mudança.
-- Caso QA PONTO-490.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS ajuste_id uuid;
CREATE INDEX IF NOT EXISTS idx_ponto_marcacoes_ajuste_id
  ON public.ponto_marcacoes (ajuste_id) WHERE ajuste_id IS NOT NULL;
COMMENT ON COLUMN public.ponto_marcacoes.ajuste_id IS
  'Ajuste de ponto (ponto_ajustes.id) que originou esta marcação incluída. NULL = batida original.';

CREATE OR REPLACE FUNCTION public.ponto_marcacoes_origem_sync()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.origem_marcacao IS NULL THEN
    NEW.origem_marcacao := CASE WHEN COALESCE(NEW.marcacao_original, true) THEN 'O' ELSE 'A' END;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- O DEFAULT 'O' chega antes do gatilho: marcação não original nasce 'A'.
    IF COALESCE(NEW.marcacao_original, true) IS FALSE AND NEW.origem_marcacao = 'O' THEN
      NEW.origem_marcacao := 'A';
    END IF;
    -- Liga ao ajuste antes de trigger_gerar_hash_marcacao sobrescrever o hash.
    IF NEW.ajuste_id IS NULL AND COALESCE(NEW.hash_marcacao, '') ~ '^AJUSTE-[0-9a-fA-F-]{36}' THEN
      NEW.ajuste_id := substring(NEW.hash_marcacao FROM 8 FOR 36)::uuid;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND COALESCE(OLD.marcacao_original, true) IS TRUE
     AND COALESCE(NEW.marcacao_original, true) IS FALSE
     AND NEW.origem_marcacao = 'O' THEN
    NEW.origem_marcacao := 'A';
  END IF;
  RETURN NEW;
END;
$$;

-- Dados antigos (idempotente)
UPDATE public.ponto_marcacoes
   SET origem_marcacao = 'A'
 WHERE marcacao_original IS FALSE AND origem_marcacao = 'O';

WITH cand AS MATERIALIZED (
  SELECT m.id AS marcacao_id, a.id AS ajuste_id
  FROM public.ponto_marcacoes m
  JOIN public.ponto_ajustes a
    ON a.tenant_id = m.tenant_id
   AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
     = regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g')
   AND a.data_referencia = m.data_marcacao
   AND a.status = 'aprovado'
   AND a.tipo_ajuste IN ('inclusao', 'correcao')
   AND a.hora_solicitada IS NOT NULL
   AND to_char(a.hora_solicitada, 'HH24:MI') = to_char(m.hora_marcacao, 'HH24:MI')
  WHERE m.marcacao_original IS FALSE
    AND m.ajuste_id IS NULL
),
unicos AS MATERIALIZED (
  SELECT c.marcacao_id, min(c.ajuste_id::text)::uuid AS ajuste_id
  FROM cand c
  WHERE NOT EXISTS (SELECT 1 FROM cand c2 WHERE c2.marcacao_id = c.marcacao_id AND c2.ajuste_id <> c.ajuste_id)
    AND NOT EXISTS (SELECT 1 FROM cand c3 WHERE c3.ajuste_id = c.ajuste_id AND c3.marcacao_id <> c.marcacao_id)
  GROUP BY c.marcacao_id
)
UPDATE public.ponto_marcacoes m
   SET ajuste_id = u.ajuste_id
  FROM unicos u
 WHERE m.id = u.marcacao_id AND m.ajuste_id IS NULL;

-- ---------------------------------------------------------------------
-- QA PONTO-490 — inclusão por ajuste nasce 'A' e ligada ao ajuste
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_490()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_cpf text := public.qa_cpf(49001);
  v_aj uuid := gen_random_uuid();
  v_o_comum text; v_aj_comum uuid;
  v_o_ajuste text; v_aj_ajuste uuid;
  v_o_dia text; v_aj_dia uuid;
  v_restantes int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Gravar batida comum e marcações de ajuste SEM informar origem (como a aprovação faz)';
  r.esperado    := 'Comum = O sem ajuste; ajuste = A ligado ao ajuste (inclusive dia inteiro com sufixo); nenhuma não original com O';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao, hash_marcacao)
  VALUES (v_t, gen_random_uuid(), '[QA-PONTO] F1', v_cpf, CURRENT_DATE - 1, TIME '08:00', 'entrada',
          encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex'))
  RETURNING origem_marcacao, ajuste_id INTO v_o_comum, v_aj_comum;

  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, hash_marcacao)
  VALUES (v_t, gen_random_uuid(), '[QA-PONTO] F1', v_cpf, CURRENT_DATE - 1, TIME '12:00', 'saida',
          false, 'AJUSTE-' || v_aj)
  RETURNING origem_marcacao, ajuste_id INTO v_o_ajuste, v_aj_ajuste;

  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, hash_marcacao)
  VALUES (v_t, gen_random_uuid(), '[QA-PONTO] F1', v_cpf, CURRENT_DATE - 2, TIME '08:00', 'entrada',
          false, 'AJUSTE-' || v_aj || '-E')
  RETURNING origem_marcacao, ajuste_id INTO v_o_dia, v_aj_dia;

  v_restantes := (SELECT count(*) FROM public.ponto_marcacoes
                   WHERE marcacao_original IS FALSE AND origem_marcacao = 'O');

  IF v_o_comum = 'O' AND v_aj_comum IS NULL
     AND v_o_ajuste = 'A' AND v_aj_ajuste = v_aj
     AND v_o_dia = 'A' AND v_aj_dia = v_aj
     AND v_restantes = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Batida comum nasce O; marcação de ajuste nasce A e ligada ao ajuste; nenhuma não original rotulada O na base.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: comum=%s/%s; ajuste=%s/%s; dia inteiro=%s/%s; não originais rotuladas O na base=%s. '
             || 'Marcação incluída por ajuste precisa ser distinguível da original (Portaria 671).',
             v_o_comum, coalesce(v_aj_comum::text,'—'), v_o_ajuste, coalesce(v_aj_ajuste::text,'—'),
             v_o_dia, coalesce(v_aj_dia::text,'—'), v_restantes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-490', m.id,
  'Marcação incluída por ajuste nasce identificada (A) e ligada ao ajuste',
  'A aprovação de ajuste grava marcações sem informar a origem. Elas precisam nascer como '
  || 'incluídas (A), distinguíveis da batida original no espelho e no AEJ, e ligadas ao ajuste '
  || 'que as originou (motivo rastreável).',
  'negativo', 'api', 'critica', 'aprovado',
  'Portaria MTP 671/2021, art. 74 e anexos do AEJ (marcação incluída × original); CLT art. 74, §2º',
  jsonb_build_array(
    jsonb_build_object('ordem', 1, 'acao', 'Batida comum sem origem', 'esperado', 'origem O, sem ajuste'),
    jsonb_build_object('ordem', 2, 'acao', 'Marcação de ajuste (hash AJUSTE-<id>) sem origem', 'esperado', 'origem A, ajuste_id = id'),
    jsonb_build_object('ordem', 3, 'acao', 'Marcação de dia inteiro (hash AJUSTE-<id>-E)', 'esperado', 'origem A, ajuste_id = id'),
    jsonb_build_object('ordem', 4, 'acao', 'Contar não originais com origem O na base', 'esperado', '0')),
  'em_triagem',
  'Fase 2 do plano do Ponto (F1), out/2026: o DEFAULT O chegava antes do gatilho; 65 casos na SUDOMED.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-490', 'qa_caso_ponto_490', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
