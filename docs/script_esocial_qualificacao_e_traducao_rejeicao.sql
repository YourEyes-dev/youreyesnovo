-- ============================================================================
-- eSocial — fecha a familia da admissao (ADM-092 + ADM-093) — ENTREGA producao.
--
-- ADM-092: qualificacao cadastral (consistencia local de CPF/nome/nascimento
--          antes do S-2200 — a causa nº 1 de rejeicao).
-- ADM-093: traducao de rejeicao do eSocial (codigo -> instrucao clara).
--
-- So cria funcoes + 1 coluna nullable. Nao altera dado existente. Idempotente.
-- ============================================================================

ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS qualificacao_cadastral text;

CREATE OR REPLACE FUNCTION public.admissao_qualificacao_cadastral(p_admissao uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE a RECORD; v_cpf text; v_probs text[] := '{}'; v_status text;
BEGIN
  -- Qualificacao cadastral: consistencia dos dados que o eSocial cruza com a
  -- base do governo antes de aceitar o S-2200 (CPF x nome x nascimento).
  SELECT * INTO a FROM public.admissoes WHERE id = p_admissao;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_cpf := regexp_replace(COALESCE(a.cpf,''), '\D', '', 'g');
  IF length(v_cpf) <> 11 THEN v_probs := array_append(v_probs, 'CPF incompleto'); END IF;
  IF COALESCE(btrim(a.nome_completo),'') = '' THEN v_probs := array_append(v_probs, 'nome ausente'); END IF;
  IF a.data_nascimento IS NULL THEN v_probs := array_append(v_probs, 'data de nascimento ausente'); END IF;
  IF a.data_nascimento IS NOT NULL AND a.data_nascimento > CURRENT_DATE THEN
    v_probs := array_append(v_probs, 'data de nascimento no futuro'); END IF;
  IF array_length(v_probs,1) IS NULL THEN v_status := 'apto';
  ELSE v_status := 'divergente: ' || array_to_string(v_probs, '; '); END IF;
  UPDATE public.admissoes SET qualificacao_cadastral = v_status WHERE id = p_admissao;
  RETURN v_status;
END $fn$;

CREATE OR REPLACE FUNCTION public.esocial_rejeicao_traduzir(p_codigo text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $fn$
  -- Traduz o codigo de retorno do eSocial: interpreta a rejeicao em instrucao
  -- clara, para conduzir retificacao (nunca reenviar clonado).
  SELECT CASE regexp_replace(COALESCE(p_codigo,''), '\D', '', 'g')
    WHEN '0'    THEN 'Aceito sem pendencias.'
    WHEN '301'  THEN 'CPF nao localizado na base do governo — confira o CPF do colaborador (qualificacao cadastral).'
    WHEN '302'  THEN 'Nome divergente do CPF na base do governo — corrija o nome completo (qualificacao cadastral).'
    WHEN '303'  THEN 'Data de nascimento divergente do CPF — corrija o nascimento (qualificacao cadastral).'
    WHEN '1010' THEN 'Erro de leiaute/schema — o XML nao segue a versao vigente do eSocial.'
    WHEN '1020' THEN 'Certificado digital invalido ou vencido.'
    WHEN '1030' THEN 'Evento duplicado — ja existe este evento aceito; use retificacao, nao reenvio.'
    ELSE 'Rejeicao ' || COALESCE(p_codigo,'(sem codigo)') || ': consulte o retorno tecnico e retifique o evento (nao reenviar clonado).'
  END;
$fn$;

GRANT EXECUTE ON FUNCTION public.admissao_qualificacao_cadastral(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.esocial_rejeicao_traduzir(text) TO authenticated;

-- Conferencia
SELECT 'ADM-092' AS caso, (public.qa_executar_descartavel('qa_caso_adm_092')).situacao::text AS situacao
UNION ALL
SELECT 'ADM-093', (public.qa_executar_descartavel('qa_caso_adm_093')).situacao::text
ORDER BY caso;
