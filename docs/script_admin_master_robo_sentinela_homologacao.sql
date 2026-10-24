-- ============================================================================
-- AJUSTE — colocar robo-sentinela@youreyes.com.br no perfil de acesso
-- "Administrador Master", no ambiente de HOMOLOGACAO
--
-- O QUE FAZ
--   1. acha o usuario (auth.users) e o cadastro dele (usuarios_base); se o
--      cadastro existe pelo e-mail mas nao esta ligado ao login (auth_user_id
--      vazio), religa. Cadastro ligado a OUTRO login nunca e tocado;
--   2. acha o perfil "Administrador Master" da MESMA empresa-cliente (tenant);
--   3. desativa o vinculo de perfil ativo que ele tinha (se tinha outro) e
--      ativa o vinculo com o Administrador Master como perfil principal;
--   4. ajusta usuarios_base.tipo_usuario para 'administrador'.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO. O arquivo se RECUSA a rodar na
-- producao (compara a URL de app_config com a da producao).
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra.
--   - Guarda o estado anterior em backup_admin_master_sentinela_<aaaammdd>,
--     com o comando de desfazer no fim.
--   - Nao cria usuario nem perfil: se faltar um dos dois, aborta dizendo qual.
--   - Nao concede SuperAdmin; so o perfil de acesso Administrador Master.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

DO $ajuste$
DECLARE
  v_email      text := 'robo-sentinela@youreyes.com.br';
  v_url        text;
  v_uid        uuid;
  v_ub         uuid;
  v_tenant     uuid;
  v_perfil     uuid;
  v_religou    boolean := false;
  v_bkp        text := 'backup_admin_master_sentinela_' || to_char(CURRENT_DATE, 'YYYYMMDD');
BEGIN
  -- (1) TRAVA DE AMBIENTE
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url');
  IF v_url IS NOT NULL AND v_url ILIKE '%diayjpsrcerycycyaxst%' THEN
    RAISE EXCEPTION 'RECUSADO: este banco e a PRODUCAO (%). Este ajuste e para a homologacao.', v_url;
  END IF;

  -- (2) ACHAR USUARIO, CADASTRO E PERFIL
  v_uid := (SELECT u.id FROM auth.users u
             WHERE lower(u.email) = lower(v_email) ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'RECUSADO: o e-mail % nao existe em auth.users deste ambiente.', v_email;
  END IF;

  v_ub := (SELECT ub.id FROM public.usuarios_base ub
            WHERE ub.auth_user_id = v_uid ORDER BY ub.created_at LIMIT 1);
  IF v_ub IS NULL THEN
    v_ub := (SELECT ub.id FROM public.usuarios_base ub
              WHERE lower(ub.email_principal) = lower(v_email) AND ub.auth_user_id IS NULL
              ORDER BY ub.created_at LIMIT 1);
    v_religou := v_ub IS NOT NULL;
    IF v_ub IS NULL AND EXISTS (SELECT 1 FROM public.usuarios_base ub
                                 WHERE lower(ub.email_principal) = lower(v_email)) THEN
      RAISE EXCEPTION 'RECUSADO: o cadastro de % esta ligado a OUTRO login; nada foi alterado.', v_email;
    END IF;
  END IF;
  v_tenant := (SELECT ub.tenant_id FROM public.usuarios_base ub WHERE ub.id = v_ub);
  IF v_ub IS NULL THEN
    RAISE EXCEPTION 'RECUSADO: % tem login mas nao tem cadastro em usuarios_base (nao esta vinculado a nenhuma empresa-cliente).', v_email;
  END IF;

  v_perfil := (SELECT pa.id FROM public.perfis_acesso pa
                WHERE pa.tenant_id = v_tenant AND pa.nome = 'Administrador Master'
                ORDER BY pa.created_at LIMIT 1);
  IF v_perfil IS NULL THEN
    RAISE EXCEPTION 'RECUSADO: a empresa-cliente (tenant %) nao tem o perfil "Administrador Master".', v_tenant;
  END IF;

  -- (3) BACKUP do que sera tocado (tabela nasce fechada para a API)
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.' || quote_ident(v_bkp) || ' (
            momento timestamptz NOT NULL DEFAULT now(),
            usuario_id uuid, auth_user_id_antes uuid, tipo_usuario_antes text,
            vinculo_id uuid, vinculo_perfil_id uuid, vinculo_ativo boolean, vinculo_principal boolean)';
  EXECUTE 'ALTER TABLE public.' || quote_ident(v_bkp) || ' ENABLE ROW LEVEL SECURITY';
  EXECUTE 'REVOKE ALL ON TABLE public.' || quote_ident(v_bkp) || ' FROM anon, authenticated';

  EXECUTE 'INSERT INTO public.' || quote_ident(v_bkp) ||
          ' (usuario_id, auth_user_id_antes, tipo_usuario_antes, vinculo_id, vinculo_perfil_id, vinculo_ativo, vinculo_principal)
            SELECT $1, ub.auth_user_id, ub.tipo_usuario::text, v.id, v.perfil_id, v.ativo, v.is_perfil_principal
              FROM public.usuarios_base ub
              LEFT JOIN public.usuario_perfil_vinculos v
                     ON v.usuario_id = ub.id AND v.empresa_id IS NULL
             WHERE ub.id = $1'
    USING v_ub;

  -- (4) DESATIVAR outro perfil ativo (o indice permite so um ativo por usuario)
  UPDATE public.usuario_perfil_vinculos v
     SET ativo = false,
         is_perfil_principal = false,
         observacao = COALESCE(v.observacao, '') || ' [desativado: Administrador Master atribuido em ' || to_char(now(), 'DD/MM/YYYY') || ']'
   WHERE v.usuario_id = v_ub AND v.empresa_id IS NULL
     AND COALESCE(v.ativo, true) AND v.perfil_id <> v_perfil;

  -- (5) ATIVAR / CRIAR o vinculo com o Administrador Master
  UPDATE public.usuario_perfil_vinculos v
     SET ativo = true, is_perfil_principal = true
   WHERE v.usuario_id = v_ub AND v.empresa_id IS NULL AND v.perfil_id = v_perfil;

  INSERT INTO public.usuario_perfil_vinculos
    (tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal, atribuido_por_nome, observacao)
  SELECT v_tenant, v_ub, v_perfil, true, true, 'Sistema', 'Administrador Master atribuido por ajuste de homologacao'
   WHERE NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x
                      WHERE x.usuario_id = v_ub AND x.empresa_id IS NULL AND x.perfil_id = v_perfil);

  -- (6) TIPO DE USUARIO
  UPDATE public.usuarios_base
     SET tipo_usuario = 'administrador',
         auth_user_id = COALESCE(auth_user_id, v_uid)
   WHERE id = v_ub;

  RAISE NOTICE 'Administrador Master atribuido a % (usuario_base %).', v_email, v_ub;
END $ajuste$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL. Esperado: 1 vinculo ativo, perfil Administrador Master, OK
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT u.email, ub.tipo_usuario::text AS tipo_usuario,
         pa.nome AS perfil_ativo, v.is_perfil_principal AS principal,
         (SELECT count(*) FROM public.usuario_perfil_vinculos y
           WHERE y.usuario_id = ub.id AND COALESCE(y.ativo, true)) AS qtd_vinculos_ativos
    FROM auth.users u
    JOIN public.usuarios_base ub ON ub.auth_user_id = u.id
    LEFT JOIN public.usuario_perfil_vinculos v
           ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
    LEFT JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
   WHERE lower(u.email) = 'robo-sentinela@youreyes.com.br'
)
SELECT email, tipo_usuario, perfil_ativo, principal, qtd_vinculos_ativos,
       CASE WHEN perfil_ativo = 'Administrador Master' AND tipo_usuario = 'administrador'
                 AND qtd_vinculos_ativos = 1
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
  FROM x;

-- ---------------------------------------------------------------------------
-- COMO DESFAZER (troque AAAAMMDD pela data da tabela de backup)
--
--   UPDATE public.usuarios_base ub SET tipo_usuario = b.tipo_usuario_antes,
--          auth_user_id = b.auth_user_id_antes
--     FROM public.backup_admin_master_sentinela_AAAAMMDD b
--    WHERE ub.id = b.usuario_id AND b.tipo_usuario_antes IS NOT NULL;
--
--   -- desativa o Administrador Master e religa o vinculo anterior
--   UPDATE public.usuario_perfil_vinculos v SET ativo = false, is_perfil_principal = false
--     FROM public.backup_admin_master_sentinela_AAAAMMDD b
--    WHERE v.usuario_id = b.usuario_id AND v.empresa_id IS NULL
--      AND v.perfil_id <> COALESCE(b.vinculo_perfil_id, v.perfil_id) AND v.ativo;
--   UPDATE public.usuario_perfil_vinculos v SET ativo = b.vinculo_ativo, is_perfil_principal = b.vinculo_principal
--     FROM public.backup_admin_master_sentinela_AAAAMMDD b
--    WHERE v.id = b.vinculo_id;
-- ---------------------------------------------------------------------------
