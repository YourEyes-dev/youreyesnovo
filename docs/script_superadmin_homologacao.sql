-- ============================================================================
-- AJUSTE — conceder SuperAdmin a um usuario, no ambiente de HOMOLOGACAO
--
-- POR QUE EXISTE
-- A bancada de QA (e varias telas de administracao) so aparecem para quem e
-- SuperAdmin. Depois de recriar a homologacao, o usuario que vai testar
-- precisa desse acesso no ambiente novo.
--
-- COMO O SISTEMA RECONHECE UM SUPERADMIN (duas vias, e a tela confere as duas)
--   1. uma linha ATIVA na tabela superadmins  — e o que a funcao
--      is_superadmin() consulta, usada pelas politicas de acesso do banco;
--   2. o papel superadmin em user_roles       — e o que a tela le para
--      liberar os menus.
-- Este ajuste grava as duas, para nao deixar meio acesso.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO. O arquivo se RECUSA a rodar se o
-- banco for o de producao: a primeira coisa que ele faz e comparar a URL
-- gravada em app_config com a da producao e abortar se baterem.
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra.
--   - Guarda o estado anterior antes de alterar (tabela backup_superadmin_
--     <aaaammdd>), com o comando de desfazer no fim deste arquivo.
--   - Nao cria usuario: se o e-mail nao existir no ambiente, aborta dizendo
--     isso — cadastre-se pela tela primeiro e rode de novo.
--   - Nao toca em dado de cliente nem em regra de negocio.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) QUEM RECEBE O ACESSO — o unico valor a trocar, se for outra pessoa.
-- ---------------------------------------------------------------------------
-- e-mail: leirinuernberg@gmail.com

DO $ajuste$
DECLARE
  v_email      text := 'leirinuernberg@gmail.com';
  v_url        text;
  v_uid        uuid;
  v_nome       text;
  v_ja_ativo   boolean;
  v_tabela_bkp text := 'backup_superadmin_' || to_char(CURRENT_DATE, 'YYYYMMDD');
BEGIN
  -- (1) TRAVA DE AMBIENTE — a mais importante do arquivo.
  SELECT valor INTO v_url FROM public.app_config WHERE chave = 'supabase_url';
  IF v_url IS NOT NULL AND v_url ILIKE '%diayjpsrcerycycyaxst%' THEN
    RAISE EXCEPTION
      'RECUSADO: este banco e a PRODUCAO (%). Este ajuste e para a homologacao.',
      v_url;
  END IF;

  -- (2) ACHAR O USUARIO — sem criar ninguem.
  SELECT u.id, coalesce(u.raw_user_meta_data ->> 'nome',
                        u.raw_user_meta_data ->> 'full_name',
                        split_part(u.email, '@', 1))
    INTO v_uid, v_nome
  FROM auth.users u
  WHERE lower(u.email) = lower(v_email)
  ORDER BY u.created_at
  LIMIT 1;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION
      'RECUSADO: o e-mail % nao existe neste ambiente. Faca o cadastro/primeiro acesso pela tela e rode este arquivo de novo.',
      v_email;
  END IF;

  -- (3) GUARDAR O ESTADO ANTERIOR antes de qualquer alteracao.
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS public.%I (
       momento    timestamptz NOT NULL DEFAULT now(),
       user_id    uuid,
       email      text,
       era_superadmin_tabela boolean,
       estava_ativo          boolean,
       tinha_papel_superadmin boolean
     )', v_tabela_bkp);

  SELECT s.ativo INTO v_ja_ativo
  FROM public.superadmins s WHERE s.user_id = v_uid;

  EXECUTE format(
    'INSERT INTO public.%I (user_id, email, era_superadmin_tabela, estava_ativo, tinha_papel_superadmin)
     VALUES ($1, $2, $3, $4, $5)', v_tabela_bkp)
  USING v_uid, v_email, (v_ja_ativo IS NOT NULL), coalesce(v_ja_ativo, false),
        EXISTS (SELECT 1 FROM public.user_roles r
                 WHERE r.user_id = v_uid AND r.role = 'superadmin');

  -- (4) VIA 1 — a tabela que is_superadmin() consulta.
  INSERT INTO public.superadmins (user_id, email, nome, ativo)
  VALUES (v_uid, v_email, v_nome, true)
  ON CONFLICT (user_id) DO UPDATE
    SET ativo = true,
        email = EXCLUDED.email,
        nome  = coalesce(public.superadmins.nome, EXCLUDED.nome);

  -- (5) VIA 2 — o papel que a tela le para liberar os menus.
  INSERT INTO public.user_roles (user_id, role)
  SELECT v_uid, 'superadmin'::public.app_role
  WHERE NOT EXISTS (
    SELECT 1 FROM public.user_roles r
     WHERE r.user_id = v_uid AND r.role = 'superadmin'
  );

  RAISE NOTICE 'SuperAdmin concedido a % (%). Estado anterior guardado em public.%.',
    v_email, v_uid, v_tabela_bkp;

EXCEPTION
  WHEN undefined_table THEN
    RAISE EXCEPTION
      'RECUSADO: estrutura de acesso ausente neste banco (superadmins/user_roles/app_config). Confira se e mesmo o ambiente certo. Detalhe: %',
      SQLERRM;
END $ajuste$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL — o retrato do acesso deste usuario.
-- Esperado: t | t | t | OK
-- ---------------------------------------------------------------------------
WITH alvo AS MATERIALIZED (
  SELECT u.id AS user_id, u.email
  FROM auth.users u
  WHERE lower(u.email) = lower('leirinuernberg@gmail.com')
  ORDER BY u.created_at
  LIMIT 1
),
x AS MATERIALIZED (
  SELECT a.email,
         EXISTS (SELECT 1 FROM public.superadmins s
                  WHERE s.user_id = a.user_id AND s.ativo) AS na_tabela_superadmins,
         EXISTS (SELECT 1 FROM public.user_roles r
                  WHERE r.user_id = a.user_id AND r.role = 'superadmin') AS com_papel_superadmin,
         public.is_superadmin(a.user_id) AS reconhecido_pelo_banco
  FROM alvo a
)
SELECT email, na_tabela_superadmins, com_papel_superadmin, reconhecido_pelo_banco,
       CASE WHEN na_tabela_superadmins AND com_papel_superadmin AND reconhecido_pelo_banco
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;

-- ---------------------------------------------------------------------------
-- COMO DESFAZER (cole no mesmo ambiente, trocando a data da tabela de backup)
--
--   UPDATE public.superadmins s
--      SET ativo = b.estava_ativo
--     FROM public.backup_superadmin_AAAAMMDD b
--    WHERE s.user_id = b.user_id AND NOT b.era_superadmin_tabela IS FALSE;
--
--   DELETE FROM public.superadmins s
--    USING public.backup_superadmin_AAAAMMDD b
--    WHERE s.user_id = b.user_id AND b.era_superadmin_tabela = false;
--
--   DELETE FROM public.user_roles r
--    USING public.backup_superadmin_AAAAMMDD b
--    WHERE r.user_id = b.user_id AND r.role = 'superadmin'
--      AND b.tinha_papel_superadmin = false;
-- ---------------------------------------------------------------------------
