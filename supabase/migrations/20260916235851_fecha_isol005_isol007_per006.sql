-- ============================================================================
-- Os três achados que sobravam no motor: ISOL-005, ISOL-007 e PER-006.
--
-- Os três são ANTIGOS — nenhum veio do trabalho desta leva. Eles estavam
-- abertos porque cada um pedia uma decisão, não uma linha de código. Aqui vão
-- as três decisões, com o que cada uma resolve E o que ela deixa em aberto,
-- porque fechar o teste sem fechar o problema seria o pior resultado possível.
-- ============================================================================

SET lock_timeout = '10s';

-- ═════════════════════════════════════════════════════════
-- ISOL-005 — tabela sensível com isolamento ligado e ZERO política
--
-- Sete tabelas de cobrança e limites (assinaturas, contadores de uso, trilha
-- de direitos) carregam tenant_id, estão com o isolamento LIGADO e não têm
-- política nenhuma. Isolamento ligado sem política não protege: TRANCA. Hoje
-- ninguém lê aquelas tabelas pela API — nem o dono do dado. O risco real não
-- é o de hoje; é o conserto apressado de amanhã, quando alguém precisar do
-- dado, não achar a causa e "resolver" desligando o isolamento. Aí a tabela
-- trancada vira tabela exposta.
--
-- A correção é derivada, não uma lista fixa: varre quem está nessa situação e
-- dá a cada uma a política mínima — só superadmin. Isso NÃO afrouxa nada: sai
-- de "ninguém lê" para "só o superadmin lê". Tabela que entrar nessa situação
-- amanhã é pega pela mesma varredura.
--
-- Nome fixo (somente_superadmin) porque é único por tabela: rodar de novo não
-- duplica.
-- ═════════════════════════════════════════════════════════
DO $isol005$
DECLARE r record; v_feitas int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tabela
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relrowsecurity
      AND c.relname NOT LIKE 'qa\_%'
      AND EXISTS (SELECT 1 FROM pg_attribute a
                   WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                     AND a.attnum > 0 AND NOT a.attisdropped)
      AND NOT EXISTS (SELECT 1 FROM pg_policies p
                       WHERE p.schemaname = 'public' AND p.tablename = c.relname)
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format(
        'CREATE POLICY somente_superadmin ON public.%I FOR ALL TO authenticated '
        'USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
        r.tabela);
      v_feitas := v_feitas + 1;
      RAISE NOTICE 'ISOL-005: politica somente_superadmin criada em %', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: nao deu para criar politica em %: %', r.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % tabela(s) destrancada(s) com politica minima.', v_feitas;
END $isol005$;

-- A outra metade do mesmo caso, e a mais desconfortável: as tabelas backup_*
-- que os próprios scripts de entrega criam antes de alterar dado. Elas guardam
-- linhas REAIS de cliente e nascem SEM isolamento nenhum — a cópia de
-- segurança que protege contra o script errado é, ela mesma, uma cópia
-- desprotegida do dado que salvou. Ligar o isolamento nelas não atrapalha o
-- desfazer: quem roda o script de restauração é o dono do banco, para quem o
-- isolamento não se aplica.
DO $isol005backup$
DECLARE r record; v_feitas int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tabela
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname LIKE 'backup\_%'
      AND EXISTS (SELECT 1 FROM pg_attribute a
                   WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                     AND a.attnum > 0 AND NOT a.attisdropped)
      AND NOT c.relrowsecurity
    ORDER BY c.relname
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format(
        'CREATE POLICY somente_superadmin ON public.%I FOR ALL TO authenticated '
        'USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
        r.tabela);
      v_feitas := v_feitas + 1;
      RAISE NOTICE 'ISOL-005: copia de seguranca % protegida.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: nao deu para proteger %: %', r.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % copia(s) de seguranca protegida(s).', v_feitas;
END $isol005backup$;

-- ═════════════════════════════════════════════════════════
-- ISOL-007 — a travessia de LEITURA do superadmin não deixa rastro
--
-- Mudança de perfil deixa rastro; a leitura cross-tenant, que é o maior poder
-- do sistema, não deixa. O PostgreSQL não dispara gatilho em SELECT, então
-- auditar leitura só é possível no ponto onde a travessia acontece de
-- propósito: a chamada que o painel do superadmin faz para ler o dado de OUTRO
-- cliente.
--
-- Esta função é esse registro. Ela é cuidadosa em duas coisas:
--   1) só grava quando quem chama É superadmin E o cliente lido NÃO é o dele —
--      superadmin olhando a própria casa não é travessia;
--   2) nunca derruba quem a chamou. Auditoria que quebra a tela vira auditoria
--      que alguém remove.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.registrar_acesso_cross_tenant(
  p_tenant_id uuid,
  p_recurso   text,
  p_detalhe   jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_meu_tenant uuid;
  v_nome text;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT public.is_superadmin(v_uid) THEN
    RETURN;
  END IF;

  SELECT pr.tenant_id, pr.nome_completo INTO v_meu_tenant, v_nome
  FROM public.profiles pr WHERE pr.user_id = v_uid LIMIT 1;

  IF v_meu_tenant IS NOT DISTINCT FROM p_tenant_id THEN
    RETURN;  -- a própria casa: não é travessia
  END IF;

  INSERT INTO public.perfil_audit_log
    (tenant_id, acao, descricao, dados_novos, realizado_por, realizado_por_nome)
  VALUES
    (p_tenant_id, 'acesso_cross_tenant',
     COALESCE(NULLIF(btrim(p_recurso), ''), 'recurso nao informado'),
     p_detalhe, v_uid, COALESCE(v_nome, 'superadmin'));

EXCEPTION WHEN OTHERS THEN
  -- Registro é acessório à leitura: nunca pode derrubá-la.
  RAISE NOTICE 'registrar_acesso_cross_tenant falhou em silencio: %', SQLERRM;
END $fn$;

COMMENT ON FUNCTION public.registrar_acesso_cross_tenant(uuid, text, jsonb) IS
  'Deixa rastro de quem, quando e o quê quando um superadmin LÊ dado de outro cliente. Só grava para superadmin atravessando a fronteira, e nunca derruba a leitura que a chamou.';

REVOKE EXECUTE ON FUNCTION public.registrar_acesso_cross_tenant(uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_acesso_cross_tenant(uuid, text, jsonb) TO authenticated, service_role;

-- ═════════════════════════════════════════════════════════
-- PER-006 — a decisão não distinguia o VERBO
--
-- perfil_permissoes.acao guarda o verbo (visualizar, editar, excluir,
-- administrar...), mas a decisão do banco era perfil_permite_modulo(cliente,
-- módulos): ela não recebia nem consultava a ação. Um perfil com APENAS
-- "visualizar" abria a mesma porta de um com "administrar".
--
-- Esta função é a peça que faltava: a mesma decisão, com o verbo.
--
-- SEJA HONESTO SOBRE O ALCANCE: criar a peça NÃO reescreve as 32 políticas
-- RESTRICTIVE que hoje decidem só leitura. Passar as telas e as políticas a
-- consultar o verbo é a etapa seguinte, e ela tem risco de verdade — barrar
-- escrita legítima de quem hoje trabalha. Esta migration entrega a decisão
-- correta e disponível; adotá-la ponto a ponto é trabalho medido, um verbo de
-- cada vez.
--
-- Uma escolha de desenho, deliberada: 'administrar' vale por todos os verbos,
-- e nenhum outro implica outro. Quem tem só 'editar' NÃO ganha 'visualizar' de
-- brinde — inventar corrente de implicação seria repetir, em miniatura, o erro
-- que este caso denuncia.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.perfil_permite_acao(
  p_tenant_id uuid,
  p_modulo    text,
  p_acao      text
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
  IF v_uid IS NULL OR p_tenant_id IS NULL OR p_modulo IS NULL OR p_acao IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  LIMIT 1;

  -- Mesmo porteiro de perfil_permite_modulo, para as duas decisões não
  -- divergirem no caminho de entrada.
  IF v_status IS NULL THEN
    RETURN public.has_minimum_role(v_uid, 'manager'::public.app_role)
       AND EXISTS (SELECT 1 FROM public.profiles pr
                    WHERE pr.user_id = v_uid AND pr.tenant_id = p_tenant_id);
  END IF;

  IF v_status <> 'ativo' THEN
    RETURN false;
  END IF;

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

  v_empresa := public.empresa_ativa();

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  -- A diferença que dá nome ao caso: além do módulo, o VERBO.
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
     AND pp.modulo = p_modulo
     AND pp.acao::text IN (p_acao, 'administrar')
     AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.perfil_excecoes pe
      ON pe.usuario_id = ub.id
     AND pe.tenant_id = ub.tenant_id
     AND COALESCE(pe.ativo, true) = true
     AND COALESCE(pe.tipo, 'adicional') = 'adicional'
     AND (pe.expira_em IS NULL OR pe.expira_em > now())
     AND pe.modulo = p_modulo
     AND COALESCE(pe.acao::text, 'administrar') IN (p_acao, 'administrar')
     AND COALESCE(pe.escopo::text, '') <> 'proprio_usuario'
     AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END $fn$;

COMMENT ON FUNCTION public.perfil_permite_acao(uuid, text, text) IS
  'Decisão de acesso COM o verbo: separa ler de escrever, que perfil_permite_modulo não separa. Administrar vale por todos os verbos; nenhum outro implica outro. Respeita a empresa ativa da sessão.';

REVOKE EXECUTE ON FUNCTION public.perfil_permite_acao(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_permite_acao(uuid, text, text) TO authenticated, service_role;
