-- ============================================================================
-- AJUSTE DE DADOS — Taeco: usuarios do "Perfil Basico" deixam de ter papel de gestao
--
-- Cole no SQL Editor do projeto de PRODUCAO. UMA transacao, idempotente. SO a Taeco.
-- Motivo: o cadastro criou estas pessoas com tipo "Gestor", que grava o papel tecnico
-- "manager". O perfil delas (Perfil Basico) so da "Proprio usuario" em Ouvidoria, mas o papel
-- abria tudo. Este script corrige o CADASTRO: tipo Colaborador e papel user.
--
-- Quem e afetado: usuarios ATIVOS da Taeco com tipo gestor, papel manager (e nenhum owner/admin)
-- e perfil vinculado ativo chamado Perfil Basico. NAO mexe em RH/Gestao de Pessoas, no
-- Administrador Master nem em quem tem outro perfil.
--
-- Guarda as linhas antes (a producao nao tem PITR): backup_taeco_usuarios_base_20261022 e
-- backup_taeco_user_roles_20261022. Para DESFAZER, ver o comentario final.
-- Sem funcoes neste arquivo: o auto-RLS do editor nao tem o que corromper.
-- ============================================================================

SET lock_timeout = '10s';

DO $taeco$
DECLARE
  v_n_tenants int;
  v_tenant uuid;
  v_alvos int;
BEGIN
  -- Backups (a marca de criacao de tabela fica quebrada de proposito para o auto-RLS do editor).
  -- Criados antes de qualquer retorno antecipado, para a conferencia final sempre achar as tabelas.
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_taeco_usuarios_base_20261022 AS '
       || 'SELECT ub.* FROM public.usuarios_base ub WHERE false';
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_taeco_user_roles_20261022 AS '
       || 'SELECT ur.* FROM public.user_roles ur WHERE false';

  v_n_tenants := (SELECT count(*) FROM public.tenants WHERE nome ILIKE '%taeco%');
  IF v_n_tenants <> 1 THEN
    RAISE NOTICE 'Esperava exatamente 1 cliente Taeco, achei %. Nada foi alterado.', v_n_tenants;
    RETURN;
  END IF;
  v_tenant := (SELECT id FROM public.tenants WHERE nome ILIKE '%taeco%');

  -- Alvos (mesmo filtro nos backups e nos updates)
  v_alvos := (
    SELECT count(*) FROM public.usuarios_base ub
    WHERE ub.tenant_id = v_tenant AND ub.status::text = 'ativo' AND ub.tipo_usuario::text = 'gestor'
      AND ub.auth_user_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                   WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) AND btrim(pa.nome) = 'Perfil Básico')
      AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'manager')
      AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','admin','superadmin'))
  );
  RAISE NOTICE 'Taeco: % usuario(s) a ajustar.', v_alvos;
  IF v_alvos = 0 THEN
    RETURN;
  END IF;

  INSERT INTO public.backup_taeco_usuarios_base_20261022
  SELECT ub.* FROM public.usuarios_base ub
  WHERE ub.tenant_id = v_tenant AND ub.status::text = 'ativo' AND ub.tipo_usuario::text = 'gestor'
    AND ub.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                 WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) AND btrim(pa.nome) = 'Perfil Básico')
    AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'manager')
    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('owner','admin','superadmin'))
    AND NOT EXISTS (SELECT 1 FROM public.backup_taeco_usuarios_base_20261022 b WHERE b.id = ub.id);

  INSERT INTO public.backup_taeco_user_roles_20261022
  SELECT ur.* FROM public.user_roles ur
  WHERE ur.role::text = 'manager'
    AND ur.user_id IN (SELECT b.auth_user_id FROM public.backup_taeco_usuarios_base_20261022 b)
    AND NOT EXISTS (SELECT 1 FROM public.backup_taeco_user_roles_20261022 x WHERE x.id = ur.id);

  -- Ajuste: papel manager -> user e tipo gestor -> colaborador (so quem esta no backup)
  INSERT INTO public.user_roles (user_id, role)
  SELECT b.auth_user_id, 'user'::public.app_role FROM public.backup_taeco_usuarios_base_20261022 b
  ON CONFLICT (user_id, role) DO NOTHING;

  DELETE FROM public.user_roles ur
  WHERE ur.role::text = 'manager'
    AND ur.user_id IN (SELECT b.auth_user_id FROM public.backup_taeco_usuarios_base_20261022 b);

  UPDATE public.usuarios_base ub SET tipo_usuario = 'colaborador'
  WHERE ub.id IN (SELECT b.id FROM public.backup_taeco_usuarios_base_20261022 b)
    AND ub.tipo_usuario::text = 'gestor';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: ajuste da Taeco nao aplicado: %', SQLERRM;
END $taeco$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM public.backup_taeco_usuarios_base_20261022)                       AS pessoas_no_backup,
  (SELECT count(*) FROM public.usuarios_base ub
    WHERE ub.id IN (SELECT id FROM public.backup_taeco_usuarios_base_20261022)
      AND ub.tipo_usuario::text = 'colaborador')                                          AS agora_colaborador,
  (SELECT count(*) FROM public.user_roles ur
    WHERE ur.user_id IN (SELECT auth_user_id FROM public.backup_taeco_usuarios_base_20261022)
      AND ur.role::text = 'manager')                                                      AS ainda_manager,
  (SELECT count(*) FROM public.user_roles ur
    WHERE ur.user_id IN (SELECT auth_user_id FROM public.backup_taeco_usuarios_base_20261022)
      AND ur.role::text = 'user')                                                         AS agora_user;

-- PARA DESFAZER (so se necessario):
--   UPDATE public.usuarios_base ub SET tipo_usuario = b.tipo_usuario
--     FROM public.backup_taeco_usuarios_base_20261022 b WHERE b.id = ub.id;
--   INSERT INTO public.user_roles SELECT * FROM public.backup_taeco_user_roles_20261022 b
--     WHERE NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.id = b.id);
--   DELETE FROM public.user_roles ur WHERE ur.role::text = 'user'
--     AND ur.user_id IN (SELECT user_id FROM public.backup_taeco_user_roles_20261022);
