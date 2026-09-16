-- ============================================================================
-- ENTREGA — Comprovantes de ponto: a extracao passa a ser MESMO do dono
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- POR QUE
--   ponto_comprovantes_extrair() e SECURITY DEFINER e recebe o CPF por
--   parametro. O comentario dizia "restrita ao proprio CPF", mas a restricao
--   nao estava escrita: qualquer usuario autenticado podia chamar a funcao com
--   o CPF de um colega e receber os comprovantes dele — data, hora e NSR de
--   cada batida. Dado pessoal de terceiro (LGPD arts. 6, 46 e 47); o RLS nao
--   protege, porque SECURITY DEFINER passa por cima.
--   Isso passa a importar agora porque a tela "Meus comprovantes" chama esta
--   funcao: sem a trava, bastaria trocar o CPF na chamada.
--
-- O QUE MUDA
--   Mesma assinatura, mesmo retorno. Antes de devolver qualquer linha, confere
--   quem chama: o dono do CPF, quem tem papel de gestao (manager ou acima) ou
--   execucao sem sessao (rotina/SQL Editor). Fora disso devolve VAZIO — sem
--   erro, para nao virar oraculo de "este CPF existe".
--
-- SEGURANCA DO DADO
--   Funcao de LEITURA: nao altera nem apaga linha nenhuma, entao nao ha copia
--   de seguranca a fazer. CREATE OR REPLACE, idempotente.
--
-- PROVADO em replica local: com a versao antiga, um colaborador lia os
-- comprovantes de outro (1 linha); com esta, le 0. O dono continua lendo os
-- seus, o gestor continua lendo os de terceiros e a execucao sem sessao segue
-- funcionando.
-- ============================================================================

SET lock_timeout = '10s';

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

-- ============================================================================
-- CONFERENCIA (o editor mostra so o ultimo resultado)
-- ============================================================================
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_comprovantes_extrair') = 1
    AS funcao_existe,
  (SELECT p.prolang = (SELECT oid FROM pg_language WHERE lanname='plpgsql')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_comprovantes_extrair' LIMIT 1)
    AS versao_com_trava,
  (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_comprovantes_extrair' LIMIT 1)
    AS security_definer,
  CASE
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname='public' AND p.proname='ponto_comprovantes_extrair') <> 1
      THEN 'FALHOU — funcao nao encontrada'
    WHEN (SELECT p.prolang FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname='public' AND p.proname='ponto_comprovantes_extrair' LIMIT 1)
         <> (SELECT oid FROM pg_language WHERE lanname='plpgsql')
      THEN 'FALHOU — ainda esta a versao antiga (sem a trava)'
    ELSE 'OK'
  END AS erro_tecnico;
