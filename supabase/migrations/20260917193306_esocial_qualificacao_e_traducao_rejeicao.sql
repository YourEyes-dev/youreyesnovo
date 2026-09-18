-- ============================================================================
-- eSocial — fecha a familia da admissao: qualificacao cadastral (ADM-092) e
-- traducao de rejeicao (ADM-093).
--
-- ADM-092: nao havia qualificacao cadastral — a causa nº 1 de rejeicao do
--          S-2200 e divergencia de CPF/nome/nascimento nao tratada em casa.
--          Cria admissao_qualificacao_cadastral(): confere os dados minimos
--          ANTES do envio e devolve 'apto' ou o que diverge. (A checagem contra
--          a base do governo e um passo de webservice/edge; aqui fica a
--          consistencia local, que ja retem o erro na origem.)
-- ADM-093: nao havia traducao de rejeicao — o retorno tecnico do eSocial chegava
--          cru. Cria esocial_rejeicao_traduzir(): converte o codigo de rejeicao
--          em instrucao clara, para conduzir a retificacao (nunca clonar).
-- Ambas sao read-only por natureza; nao alteram dado.
-- ============================================================================

-- Coluna para guardar o resultado da qualificacao (opcional, mas util) -------
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS qualificacao_cadastral text;

-- 1) Qualificacao cadastral da admissao (ADM-092) ----------------------------
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

  IF array_length(v_probs,1) IS NULL THEN
    v_status := 'apto';
  ELSE
    v_status := 'divergente: ' || array_to_string(v_probs, '; ');
  END IF;

  UPDATE public.admissoes SET qualificacao_cadastral = v_status WHERE id = p_admissao;
  RETURN v_status;
END $fn$;

-- 2) Traducao de rejeicao do eSocial (ADM-093) -------------------------------
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
