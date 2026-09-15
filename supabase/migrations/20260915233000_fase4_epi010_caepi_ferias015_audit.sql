-- ============================================================================
-- Fase 4 — EPI-010 (conferência CAEPI) e correção do caso FERIAS-015.
--
-- EPI-010: cache da base oficial CAEPI + função que confere o CA cadastrado
--          contra ela (a edge function que busca a base pública popula o cache;
--          a conferência no banco marca o tipo como conferido/não confirmado).
-- FERIAS-015: o caso tem um FALSO-POSITIVO — a auditoria casa a SUBSTRING
--          "idade" em palavras inocentes (severidade, prioridade, unidade...).
--          O sistema não tem trava etária (a do art. 134, §2º foi revogada pela
--          Lei 13.467/2017). Aqui o caso é corrigido para casar a PALAVRA
--          "idade" (limite de palavra) ou "data_nascimento" — o sinal real de
--          uma trava por idade —, sem alterar o comportamento do sistema.
-- ============================================================================

-- ── EPI-010: cache e conferência CAEPI ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.caepi_cache (
  ca_numero    text PRIMARY KEY,
  equipamento  text,
  fabricante   text,
  cnpj_fabricante text,
  validade     date,
  situacao     text,                 -- VÁLIDO | VENCIDO | ... (da base oficial)
  bruto        jsonb,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.caepi_cache IS
  'EPI-010: cache local da base oficial CAEPI (populado por edge function); base da conferencia do CA.';

CREATE OR REPLACE FUNCTION public.epi_ca_conferir_caepi(p_ca_numero text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE c public.caepi_cache%ROWTYPE;
BEGIN
  -- Confere o CA informado contra a base oficial CAEPI (cache). Sem registro no
  -- cache, o tipo fica "nao_confirmado" ate a edge function trazer a base.
  SELECT * INTO c FROM public.caepi_cache WHERE ca_numero = regexp_replace(COALESCE(p_ca_numero,''), '[^0-9]', '', 'g');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ca_numero', p_ca_numero, 'conferido', false, 'situacao', 'nao_confirmado');
  END IF;
  RETURN jsonb_build_object(
    'ca_numero', c.ca_numero, 'conferido', true,
    'equipamento', c.equipamento, 'fabricante', c.fabricante,
    'validade', c.validade, 'situacao', c.situacao,
    'vencido', (c.validade IS NOT NULL AND c.validade < CURRENT_DATE));
END;
$$;

COMMENT ON FUNCTION public.epi_ca_conferir_caepi(text) IS
  'EPI-010: confere o CA de epi_tipos contra o cache da base oficial CAEPI.';

-- ── FERIAS-015: corrige o falso-positivo do caso (palavra inteira) ──────────
CREATE OR REPLACE FUNCTION public.qa_caso_ferias_015()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_n int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): procurar trava por idade nas funções de férias';
  r.esperado := 'Nenhuma — a restrição etária do antigo art. 134, §2º foi revogada pela Lei 13.467/2017';

  -- Corrigido: casa a PALAVRA "idade" (limite de palavra) ou "data_nascimento";
  -- a substring solta pegava severidade/prioridade/unidade/liberalidade e
  -- acusava trava onde não há (falso-positivo).
  SELECT count(*), string_agg(p.proname, ', ')
  INTO v_n, v_lista
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE '%ferias%'
    AND p.proname NOT LIKE 'qa\_%'
    AND (pg_get_functiondef(p.oid) ~* '\midade\M'
         OR pg_get_functiondef(p.oid) ILIKE '%data_nascimento%');

  IF v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma função de férias condiciona o gozo à idade — o sistema não carrega a trava revogada (erro comum em legados).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('POSSÍVEL TRAVA ETÁRIA em %s função(ões) de férias: %s. A obrigação de período único para menor de 18/maior de 50 foi REVOGADA pela Lei 13.467/2017 — conferir e remover se for restrição de gozo.', v_n, v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
