-- ============================================================================
-- Acesso: quem tem papel de gestão e pertence ao cliente volta a entrar
--
-- REGRESSÃO INTRODUZIDA POR MIM, em 20260916230000, e pega pelo motor de QA
-- (casos MKY-075 e MKY-122, do MarketYE: "empresa não lê o documento (RLS)" e
-- "empresa não conseguiu versionar").
--
-- O que eu troquei lá: perfil_permite_modulo conferia o status do cadastro com
-- uma lista do que BARRA —
--     IF v_status IN ('inativo','bloqueado','suspenso','arquivado') THEN nega
-- e passou a conferir com uma lista do que PASSA —
--     IF v_status IS DISTINCT FROM 'ativo' THEN nega
--
-- Parece a mesma coisa. Não é: quem NÃO TEM cadastro naquele cliente tem
-- status nulo. Nulo não estava na lista do que barra, então passava; nulo é
-- diferente de 'ativo', então passou a barrar — e barra ANTES do ramo que
-- atende papel de gestão. Resultado: quem tem papel de gestor mas nenhum
-- cadastro no cliente perdeu a leitura das tabelas protegidas pelas políticas
-- RESTRICTIVE de perfil.
--
-- NÃO é só teatro de QA: a medição na produção (16/09/2026) achou UMA pessoa
-- real exatamente nessa situação — papel de gestão, perfil de acesso no
-- cliente, sem cadastro em usuarios_base. No dia em que aquilo chegasse à
-- produção, essa pessoa perderia acesso.
--
-- POR QUE NÃO BASTA DESFAZER
--
-- O ramo de gestão lê user_roles, que NÃO TEM cliente: o papel é global. Sem
-- nenhuma trava, um gestor do cliente A passaria no porteiro do cliente B —
-- que é justamente o buraco que o aperto fechou. Desfazer reabre.
--
-- A SAÍDA: a trava continua, mas passa a perguntar a coisa certa
--
-- "Pertence a este cliente?" tem resposta sem usuarios_base: é a linha de
-- profiles, que TEM tenant_id e é a âncora de isolamento do sistema inteiro
-- (get_user_tenant_id() lê dela). Então, quando não há cadastro no cliente, a
-- porta só abre para quem soma as DUAS coisas: papel de gestão E perfil de
-- acesso NAQUELE cliente. O gestor do cliente A continua barrado no cliente B,
-- porque o perfil dele aponta para o A.
--
-- Todo o resto da função segue idêntico, empresa ativa da Etapa 2 inclusive.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.perfil_permite_modulo(
  p_tenant_id uuid,
  VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_empresa uuid;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  LIMIT 1;

  -- SEM CADASTRO NO CLIENTE. Aqui mora a correção desta migration: em vez de
  -- negar sempre, pergunta as duas coisas que juntas significam "é gestão
  -- DESTE cliente". Uma sozinha não basta — o papel é global, e o perfil de
  -- acesso sozinho não dá poder de gestão.
  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (
             SELECT 1 FROM public.profiles pr
             WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id
           );
  END IF;

  -- COM CADASTRO: só 'ativo' abre porta. Terminal (desligado, bloqueado,
  -- suspenso, arquivado) nega, e pré-ativação também.
  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

  -- Quem administra o cliente administra as empresas dele: estes dois ramos
  -- seguem valendo no cliente inteiro, de propósito.
  IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
      AND ub.tipo_usuario::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;

  -- O CONTEXTO. Nulo = a sessão ainda não registrou empresa nenhuma.
  v_empresa := public.empresa_ativa();

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  -- Vínculo. O recorte por empresa veio da Etapa 2: com contexto, só contam os
  -- vínculos DAQUELA empresa.
  --
  -- O vínculo sem empresa (empresa_id nulo) conta em qualquer contexto, e isso
  -- é seguro: quem nasce assim é o vínculo automático do perfil
  -- "Colaborador (padrão)", cujas permissões são TODAS de escopo
  -- proprio_usuario — ele nunca concede acesso amplo.
  IF EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    JOIN public.perfil_permissoes pp
      ON pp.perfil_id = v.perfil_id
     AND COALESCE(pp.ativo, true) = true
     AND pp.modulo = ANY (p_modulos)
     AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  -- Liberação pontual: mesmo recorte. Uma liberação dada na Empresa A não
  -- pode valer quando a pessoa está na Empresa B — era o achado LIB-002.
  RETURN EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.perfil_excecoes pe
      ON pe.usuario_id = ub.id
     AND pe.tenant_id = ub.tenant_id
     AND COALESCE(pe.ativo, true) = true
     AND COALESCE(pe.tipo, 'adicional') = 'adicional'
     AND (pe.expira_em IS NULL OR pe.expira_em > now())
     AND pe.modulo = ANY (p_modulos)
     AND COALESCE(pe.escopo::text, '') <> 'proprio_usuario'
     AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END $fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) TO authenticated;

COMMENT ON FUNCTION public.perfil_permite_modulo(uuid, text[]) IS
  'Porteiro das políticas RESTRICTIVE de perfil. Sem cadastro no cliente, só passa quem soma papel de gestão E perfil de acesso NAQUELE cliente (o papel é global; o perfil é que diz de qual cliente a pessoa é). Com cadastro, só status ativo passa. Vínculos e liberações são recortados pela empresa ativa da sessão.';
