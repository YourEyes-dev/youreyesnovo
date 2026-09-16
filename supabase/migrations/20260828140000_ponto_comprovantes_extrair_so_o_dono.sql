-- ============================================================================
-- Comprovantes (onda 7, parte 1) — a extração passa a ser MESMO do dono
--
-- ponto_comprovantes_extrair() é SECURITY DEFINER e recebe o CPF por
-- parâmetro. O comentário diz "restrita ao proprio CPF", mas a restrição não
-- estava escrita em lugar nenhum: qualquer usuário autenticado podia chamar a
-- função com o CPF de um colega e receber os comprovantes dele — data, hora e
-- NSR de cada batida. Dado pessoal de terceiro (LGPD arts. 6º, 46 e 47), e o
-- RLS não protege: SECURITY DEFINER passa por cima.
--
-- Isso aparece agora porque a tela do trabalhador ("meus comprovantes") vai
-- chamar esta função. Sem a trava, bastaria trocar o CPF na chamada.
--
-- O QUE FAZ
--   Mantém a assinatura e o retorno. Antes de devolver qualquer linha,
--   confere quem está chamando:
--     · o próprio dono do CPF (usuarios_base.auth_user_id = auth.uid()) — o
--       caso do trabalhador extraindo os seus;
--     · quem tem papel de gestão no tenant (has_minimum_role >= manager) — RH
--       e gestor, que precisam disso para fiscalização e conferência;
--     · execução sem sessão (rotina do banco, SQL Editor), onde auth.uid() é
--       NULL e a chamada não veio de um usuário logado.
--   Fora esses casos, devolve VAZIO — sem erro, para não virar oráculo de
--   "este CPF existe".
--
-- GARANTIAS: não altera dado nenhum (função só de leitura), não muda a
-- assinatura nem o formato do retorno. Aditivo e idempotente.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_comprovantes_extrair(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_ini date,
  p_fim date
)
RETURNS TABLE(
  data_hora timestamptz,
  nsr       bigint,
  empregador text,
  conteudo  jsonb,
  hash_comprovante text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $extrair$
DECLARE
  v_uid       uuid;
  v_cpf_alvo  text := regexp_replace(COALESCE(p_colaborador_cpf,''), '[^0-9]', '', 'g');
  v_cpf_dono  text;
  v_pode      boolean := false;
BEGIN
  BEGIN v_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;

  IF v_uid IS NULL THEN
    -- Sem sessão: rotina do banco / SQL Editor. Não há usuário a restringir.
    v_pode := true;
  ELSE
    -- O próprio dono do CPF.
    BEGIN
      SELECT regexp_replace(COALESCE(ub.cpf,''), '[^0-9]', '', 'g')
        INTO v_cpf_dono
      FROM public.usuarios_base ub
      WHERE ub.auth_user_id = v_uid
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_cpf_dono := NULL; END;

    IF v_cpf_dono IS NOT NULL AND v_cpf_dono <> '' AND v_cpf_dono = v_cpf_alvo THEN
      v_pode := true;
    END IF;

    -- RH e gestão: precisam extrair o de terceiros (conferência, fiscalização).
    IF NOT v_pode AND to_regprocedure('public.has_minimum_role(uuid, app_role)') IS NOT NULL THEN
      BEGIN
        v_pode := public.has_minimum_role(v_uid, 'manager'::app_role);
      EXCEPTION WHEN OTHERS THEN v_pode := false; END;
    END IF;
  END IF;

  IF NOT v_pode THEN
    RETURN;  -- vazio: nem dado de terceiro, nem confirmação de que ele existe
  END IF;

  RETURN QUERY
  SELECT c.data_hora_marcacao, c.nsr, c.empregador_nome, c.conteudo, c.hash_comprovante
  FROM public.ponto_comprovantes c
  WHERE c.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf_alvo
    AND c.data_hora_marcacao::date BETWEEN p_ini AND p_fim
  ORDER BY c.data_hora_marcacao;
END;
$extrair$;

COMMENT ON FUNCTION public.ponto_comprovantes_extrair(uuid, text, date, date) IS
  'Extracao dos comprovantes de um periodo. So devolve linhas para o DONO do CPF (usuarios_base.auth_user_id = auth.uid()), para quem tem papel de gestao (has_minimum_role >= manager) ou em execucao sem sessao; nos demais casos devolve vazio. Portaria 671; LGPD arts. 6, 46 e 47. PONTO-359.';

REVOKE EXECUTE ON FUNCTION public.ponto_comprovantes_extrair(uuid, text, date, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ponto_comprovantes_extrair(uuid, text, date, date) TO authenticated;
