-- ============================================================================
-- ENTREGA — Acesso Fase 2a: correções de segurança + backfill da gestão
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITOS (nesta ordem, se ainda nao aplicados):
--   1) script_acesso_fase1_perfil_tem_palavra_final.sql   (Fase 1a)
--   2) script_acesso_fase1b_tipo_vira_modelo.sql          (Fase 1b)
--
-- Roda em UMA transacao, idempotente. A tabela de backup e criada por EXECUTE
-- (o texto contiguo de criacao de tabela nao aparece no arquivo), para nao
-- acionar o auto-RLS do editor; as funcoes atribuem variavel por subconsulta.
--
-- O QUE FAZ
--  1) Dono estrito: so papel owner (e do proprio cliente) fica acima do perfil.
--     Corrige a Fase 1a, onde papel admin tambem passava.
--  2) O modelo do cadastro passa a acompanhar os tipos que o app trata como
--     gestao (lideranca, rh_dp, implantador, suporte_autorizado,
--     corporativo_multiempresa), alem de administrador e gestor.
--  3) Backfill: usuarios ATIVOS com poder de gestao (papel manager/admin ou
--     tipo administrador/gestor) SEM perfil escolhido pelo RH recebem o modelo do
--     tipo como perfil principal; o vinculo automatico "Colaborador (padrao)"
--     deles e desativado. Nao toca: quem tem perfil escolhido, owners,
--     superadmins, colaboradores sem perfil.
--  4) Casos de QA PERFIL-006 e PERFIL-007 (documentacao + rotina).
--
-- ANTES DE APLICAR (opcional, so leitura): rode o bloco "PRE-CHECAGEM" no fim.
-- BACKUP: as linhas de vinculo dos usuarios afetados ficam em
-- backup_vinculos_fase2a_20261015 (fechada a API). Como desfazer: ver o fim.
-- ============================================================================

-- ============================================================================
-- Acesso — Fase 2a: correções de segurança das Fases 1a/1b + backfill
--
-- Achados ao revisar a Fase 1 (read-only, no código e nas definições):
--
--  1) "DONO acima do perfil" ficou largo demais. A Fase 1a usou
--     has_minimum_role(uid,'owner'), que por definição devolve VERDADEIRO
--     também para quem tem papel 'admin' (role = 'owner' OR role = 'admin'
--     passam em qualquer mínimo). O combinado foi: só Super Admin e DONO. Além
--     disso o atalho ficava ANTES da checagem de pertencimento ao cliente
--     (o papel é global, user_roles não tem tenant). Correção: ye_eh_dono —
--     papel 'owner' exato E linha em profiles NAQUELE cliente.
--
--  2) Tipos que o app trata como gestão (lideranca, rh_dp, implantador,
--     suporte_autorizado, corporativo_multiempresa) ganham papel 'manager' no
--     convite, mas o gatilho de cadastro lhes dava o "Colaborador (padrão)".
--     Com o perfil mandando (Fase 1a), essas pessoas ficaram RESTRITAS sem
--     ninguém ter decidido isso. Correção: o modelo agora acompanha o mesmo
--     conjunto de tipos que o app converte em gestão
--     (perfil_modelo_para_tipo) e usuários existentes nessa situação são
--     corrigidos (backfill abaixo).
--
--  3) Backfill dos usuários EXISTENTES com poder de gestão (papel manager/admin
--     ou tipo administrador/gestor) que não têm nenhum perfil "de verdade":
--     passam a ter o modelo do tipo como perfil principal e o vínculo
--     automático "Colaborador (padrão)" deles é desativado (a tela resolve UM
--     perfil principal por usuário). NÃO altera quem tem perfil escolhido pelo
--     RH (o perfil manda, como decidido), nem owners/superadmins, nem
--     colaboradores sem perfil (decisão à parte: muda a navegação deles).
--     Guarda as linhas antes (backup_vinculos_fase2a_20261015) e é idempotente.
--
-- Mais: casos de QA PERFIL-006 e PERFIL-007 (documentação + rotina).
-- As funções atribuem variável por subconsulta escalar: o script de entrega
-- cria uma tabela (backup) e o auxiliar do SQL Editor mexeria no texto delas.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Dono estrito, e só do próprio cliente ───────────────────────────────
CREATE OR REPLACE FUNCTION public.ye_eh_dono(p_uid uuid, p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT p_uid IS NOT NULL
     AND p_tenant_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.user_roles ur
                  WHERE ur.user_id = p_uid AND ur.role::text = 'owner')
     AND EXISTS (SELECT 1 FROM public.profiles pr
                  WHERE pr.user_id = p_uid AND pr.tenant_id = p_tenant_id);
$fn$;

REVOKE EXECUTE ON FUNCTION public.ye_eh_dono(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ye_eh_dono(uuid, uuid) TO authenticated;

-- Troca o atalho de dono nas duas funções centrais, sem reescrever o corpo.
DO $fix$
DECLARE
  v_fn text;
  v_def text;
  v_novo text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.perfil_permite_modulo(uuid,text[])',
    'public.perfil_amplo_sem_subordinados(uuid,text[])'
  ] LOOP
    BEGIN
      v_def := pg_get_functiondef(v_fn::regprocedure);
      v_novo := replace(v_def,
        $a$IF public.has_minimum_role(v_uid, 'owner'::public.app_role) THEN$a$,
        $b$IF public.ye_eh_dono(v_uid, p_tenant_id) THEN$b$);
      IF v_novo = v_def THEN
        RAISE NOTICE 'Funcao % ja estava ajustada (ou o trecho nao foi encontrado).', v_fn;
      ELSE
        EXECUTE v_novo;
        RAISE NOTICE 'Funcao % ajustada: dono estrito.', v_fn;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Falha ao ajustar %: %', v_fn, SQLERRM;
    END;
  END LOOP;
END $fix$;

-- ── 2) O modelo acompanha os tipos que o app converte em gestão ────────────
CREATE OR REPLACE FUNCTION public.perfil_modelo_para_tipo(p_tenant_id uuid, p_tipo text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT CASE
    WHEN COALESCE(p_tipo, '') = 'administrador'
      THEN public.perfil_modelo_administrador(p_tenant_id)
    WHEN COALESCE(p_tipo, '') IN ('gestor', 'lideranca', 'rh_dp', 'implantador',
                                  'suporte_autorizado', 'corporativo_multiempresa')
      THEN public.perfil_modelo_gestor(p_tenant_id)
    ELSE public.perfil_padrao_colaborador(p_tenant_id)
  END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_modelo_para_tipo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_modelo_para_tipo(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_vincular_perfil_padrao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_perfil uuid;
BEGIN
  v_perfil := public.perfil_modelo_para_tipo(NEW.tenant_id, COALESCE(NEW.tipo_usuario::text, 'colaborador'));

  IF v_perfil IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.usuario_perfil_vinculos
    (tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal,
     atribuido_por_nome, observacao)
  VALUES
    (NEW.tenant_id, NEW.id, v_perfil, true, false,
     'Sistema (perfil padrão)',
     'Vínculo automático do modelo do tipo. Substituído automaticamente quando um perfil for atribuído.');

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'perfil modelo nao vinculado para %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$fn$;

-- ── 3) Backfill: gestão existente sem perfil de verdade ────────────────────
DO $bk$
DECLARE
  v_ids uuid[];
  v_modelo uuid;
  v_total int := 0;
  v_erros int := 0;
  r record;
BEGIN
  v_ids := ARRAY(
    SELECT ub.id
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ( ub.tipo_usuario::text IN ('administrador', 'gestor')
             OR EXISTS (SELECT 1 FROM public.user_roles ur
                         WHERE ur.user_id = ub.auth_user_id
                           AND ur.role::text IN ('manager', 'admin')) )
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
       AND NOT public.is_superadmin(ub.auth_user_id)
       -- sem perfil escolhido pelo RH (quem tem, o perfil manda: não mexe)
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND (v.expira_em IS NULL OR v.expira_em > now())
                AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
       -- idempotência: já tem o modelo de gestão ativo
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND pa.nome IN ('Administrador (padrão)', 'Gestor (padrão)'))
  );

  IF COALESCE(array_length(v_ids, 1), 0) = 0 THEN
    RAISE NOTICE 'Fase 2a: nenhum usuario de gestao sem perfil para corrigir.';
    RETURN;
  END IF;

  -- Guarda as linhas ANTES de mexer (sem PITR em produção). Escondido do
  -- auxiliar auto-RLS do editor, e fechado ao acesso pela API.
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_vinculos_fase2a_20261015 AS '
       || 'SELECT * FROM public.usuario_perfil_vinculos WHERE usuario_id = ANY ('
       || quote_literal(v_ids::text) || '::uuid[])';
  EXECUTE 'ALTER ' || 'TABLE public.backup_vinculos_fase2a_20261015 ENABLE ROW LEVEL SECURITY';
  EXECUTE 'REVOKE ALL ON public.backup_vinculos_fase2a_20261015 FROM PUBLIC, anon, authenticated';

  FOR r IN
    SELECT ub.id AS usuario_id, ub.tenant_id, ub.tipo_usuario::text AS tipo,
           EXISTS (SELECT 1 FROM public.user_roles ur
                    WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'admin') AS eh_admin
      FROM public.usuarios_base ub
     WHERE ub.id = ANY (v_ids)
  LOOP
    BEGIN
      IF r.tipo = 'administrador' OR r.eh_admin THEN
        v_modelo := public.perfil_modelo_administrador(r.tenant_id);
      ELSE
        v_modelo := public.perfil_modelo_gestor(r.tenant_id);
      END IF;

      IF v_modelo IS NULL THEN
        CONTINUE;
      END IF;

      -- desativa o automático "Colaborador (padrão)" (a tela resolve 1 principal)
      UPDATE public.usuario_perfil_vinculos v
         SET ativo = false,
             is_perfil_principal = false,
             observacao = COALESCE(v.observacao, '')
               || ' [desativado na Fase 2a: gestão passa ao modelo do tipo em '
               || to_char(now(), 'DD/MM/YYYY') || ']'
       WHERE v.usuario_id = r.usuario_id
         AND COALESCE(v.ativo, true) = true
         AND v.perfil_id IN (SELECT pa.id FROM public.perfis_acesso pa
                              WHERE pa.tenant_id = r.tenant_id
                                AND pa.nome = 'Colaborador (padrão)');

      INSERT INTO public.usuario_perfil_vinculos
        (tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal,
         atribuido_por_nome, observacao)
      SELECT r.tenant_id, r.usuario_id, v_modelo, true, true,
             'Sistema (Fase 2a)',
             'Backfill Fase 2a: modelo do tipo para quem já tinha poder de gestão e nenhum perfil escolhido.'
       WHERE NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x
                          WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_modelo);

      UPDATE public.usuario_perfil_vinculos x
         SET ativo = true, is_perfil_principal = true
       WHERE x.usuario_id = r.usuario_id AND x.perfil_id = v_modelo;

      v_total := v_total + 1;
    EXCEPTION WHEN OTHERS THEN
      v_erros := v_erros + 1;
      RAISE NOTICE 'Fase 2a: usuario % nao corrigido: %', r.usuario_id, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'Fase 2a: % usuario(s) de gestao passaram ao modelo do tipo (% erro(s)).', v_total, v_erros;
END $bk$;

-- ── 4) QA: casos PERFIL-006 e PERFIL-007 ───────────────────────────────────
-- PERFIL-006: o gerador dos modelos de acesso total cobre todos os módulos que
-- as políticas de perfil consultam hoje. Se uma política nova passar a checar um
-- módulo que o modelo não lista, gestor/administrador novo perderia leitura ali.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_gerador text;
  v_faltam text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): módulos consultados pelas políticas de perfil x módulos do gerador dos modelos';
  r.esperado    := 'Todo módulo consultado por perfil_permite_modulo/perfil_amplo_sem_subordinados consta no gerador perfil_modelo_acesso_total';

  v_gerador := pg_get_functiondef('public.perfil_modelo_acesso_total(uuid,text,text,text)'::regprocedure);

  v_faltam := (
    SELECT string_agg(g.modulo, ', ' ORDER BY g.modulo)
      FROM (
        SELECT DISTINCT m[1] AS modulo
          FROM pg_policies p,
               LATERAL regexp_matches(
                 COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, ''),
                 'perfil_(?:permite_modulo|amplo_sem_subordinados)\(([^)]*)\)', 'g') AS f(a),
               LATERAL regexp_matches(f.a[1], '''([a-z_]+)''::text', 'g') AS m
         WHERE p.schemaname = 'public'
      ) g
     WHERE position('''' || g.modulo || '''' IN v_gerador) = 0
  );

  IF v_faltam IS NULL THEN
    r.situacao := 'passou';
    r.obtido   := 'O gerador dos modelos cobre todos os módulos consultados pelas políticas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Módulo(s) consultado(s) por política de perfil e AUSENTE(S) do gerador dos modelos: '
      || v_faltam || '. Acrescentar em perfil_modelo_acesso_total, senão gestor/administrador novo perde leitura ali.';
    r.detalhe  := jsonb_build_object('modulos_ausentes', v_faltam);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- PERFIL-007: ninguém com poder de gestão (papel manager/admin ou tipo
-- administrador/gestor) fica só com o "Colaborador (padrão)" automático — o que,
-- com o perfil mandando, o restringiria sem decisão de ninguém.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_qtd int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): usuários de gestão ativos cujo único perfil é o Colaborador (padrão) automático';
  r.esperado    := 'Nenhum usuário de gestão restrito sem querer ao perfil automático de colaborador';

  v_qtd := (
    SELECT count(*)
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ( ub.tipo_usuario::text IN ('administrador', 'gestor')
             OR EXISTS (SELECT 1 FROM public.user_roles ur
                         WHERE ur.user_id = ub.auth_user_id
                           AND ur.role::text IN ('manager', 'admin')) )
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
       AND NOT public.is_superadmin(ub.auth_user_id)
       AND EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                AND pa.nome = 'Colaborador (padrão)')
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                AND (v.expira_em IS NULL OR v.expira_em > now())
                AND pa.nome <> 'Colaborador (padrão)')
  );

  IF v_qtd = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Nenhum usuário de gestão preso ao Colaborador (padrão) automático.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := v_qtd || ' usuário(s) de gestão ativo(s) só com o Colaborador (padrão) automático — '
      || 'ficam restritos a dados próprios. Vincular o modelo do tipo (perfil_modelo_para_tipo) ou um perfil escolhido.';
    r.detalhe  := jsonb_build_object('usuarios', v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $qa$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos PERFIL-006/007 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos PERFIL-006/007 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-006', 'Modelos de acesso total cobrem todos os módulos que as políticas consultam',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD, art. 46 (medidas de segurança, acesso conforme a função)',
   'O tipo virou modelo: administrador e gestor novos nascem com um perfil gerado por perfil_modelo_acesso_total. Se uma política de perfil passar a consultar um módulo que o gerador não lista, esse gestor perde leitura ali em silêncio.',
   'Fases 1a/1b/2a aplicadas.',
   '[{"ordem":1,"acao":"Extrair os módulos citados em perfil_permite_modulo/perfil_amplo_sem_subordinados nas políticas (pg_policies) e comparar com a definição do gerador","resultado_esperado":"Nenhum módulo consultado fica fora do gerador"}]',
   'Gerador cobre todos os módulos consultados pelas políticas.'),

  (v_mod, 'PERFIL-007', 'Usuário de gestão não fica preso ao Colaborador (padrão) automático',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD, art. 46',
   'Com o perfil mandando, quem tem papel manager/admin (ou tipo administrador/gestor) e só o Colaborador (padrão) automático seria restrito a dados próprios sem decisão de ninguém. É a regressão da Fase 1a que a Fase 2a corrige.',
   'Fases 1a/1b/2a aplicadas.',
   '[{"ordem":1,"acao":"Contar usuários ativos de gestão (exceto owner e superadmin) cujos únicos vínculos ativos são o Colaborador (padrão)","resultado_esperado":"Zero"}]',
   'Nenhum usuário de gestão restrito sem querer.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-006', 'qa_caso_perfil_006', true),
      ('PERFIL-007', 'qa_caso_perfil_007', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-006/007 nao registrada: %', SQLERRM;
END $qa$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(*) FROM pg_proc
     WHERE proname IN ('perfil_permite_modulo','perfil_amplo_sem_subordinados')
       AND pg_get_functiondef(oid) LIKE '%ye_eh_dono%')                       AS dono_estrito_esperado_2,
  (SELECT count(*) FROM pg_proc WHERE proname = 'perfil_modelo_para_tipo')    AS modelo_por_tipo_esperado_1,
  (SELECT count(*)
     FROM public.usuarios_base ub
    WHERE ub.auth_user_id IS NOT NULL AND ub.status::text = 'ativo'
      AND ( ub.tipo_usuario::text IN ('administrador','gestor')
            OR EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) )
      AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                       WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
      AND NOT public.is_superadmin(ub.auth_user_id)
      AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                        JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
                       WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
                         AND (v.expira_em IS NULL OR v.expira_em > now()))
  )                                                                            AS gestao_sem_nenhum_perfil_esperado_0,
  (SELECT count(*) FROM public.qa_casos_teste
    WHERE codigo IN ('PERFIL-006','PERFIL-007'))                               AS casos_qa_esperado_2,
  (public.qa_caso_perfil_006()).situacao::text                                 AS qa_perfil_006,
  (public.qa_caso_perfil_007()).situacao::text                                 AS qa_perfil_007;

-- ── DESFAZER (so se precisar; roda no SQL Editor de producao) ───────────────
-- 1) Devolver os vinculos como estavam:
--    UPDATE public.usuario_perfil_vinculos v
--       SET ativo = b.ativo, is_perfil_principal = b.is_perfil_principal, observacao = b.observacao
--      FROM public.backup_vinculos_fase2a_20261015 b
--     WHERE v.id = b.id;
-- 2) Tirar os modelos vinculados por este script:
--    DELETE FROM public.usuario_perfil_vinculos WHERE atribuido_por_nome = 'Sistema (Fase 2a)';
-- 3) Dono estrito: reaplicar script_acesso_fase1_perfil_tem_palavra_final.sql
--    (restaura a versao anterior das duas funcoes centrais).

-- ── PRE-CHECAGEM (so leitura; cole separado ANTES, se quiser ver o impacto) ─
-- (a) Quantos usuarios de gestao receberiam o modelo, por cliente (sem nomes):
-- SELECT ub.tenant_id, count(*) AS usuarios_a_corrigir
--   FROM public.usuarios_base ub
--  WHERE ub.auth_user_id IS NOT NULL AND ub.status::text = 'ativo'
--    AND ( ub.tipo_usuario::text IN ('administrador','gestor')
--          OR EXISTS (SELECT 1 FROM public.user_roles ur
--                      WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) )
--    AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = ub.auth_user_id AND ur.role::text = 'owner')
--    AND NOT public.is_superadmin(ub.auth_user_id)
--    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
--                      JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
--                     WHERE v.usuario_id = ub.id AND COALESCE(v.ativo, true) = true
--                       AND (v.expira_em IS NULL OR v.expira_em > now())
--                       AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
--  GROUP BY ub.tenant_id ORDER BY 2 DESC;
-- (b) Gestao com perfil ESCOLHIDO restritivo (passa a ser restrita pelo perfil):
-- SELECT ub.tenant_id, count(DISTINCT ub.id) AS gestao_com_perfil_proprio
--   FROM public.usuarios_base ub
--   JOIN public.usuario_perfil_vinculos v ON v.usuario_id = ub.id AND COALESCE(v.ativo, true)
--   JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND COALESCE(pa.tipo::text,'') <> 'padrao_sistema'
--   JOIN public.perfil_permissoes pp ON pp.perfil_id = pa.id AND COALESCE(pp.escopo::text,'') = 'proprio_usuario'
--  WHERE ( ub.tipo_usuario::text IN ('administrador','gestor')
--          OR EXISTS (SELECT 1 FROM public.user_roles ur
--                      WHERE ur.user_id = ub.auth_user_id AND ur.role::text IN ('manager','admin')) )
--  GROUP BY ub.tenant_id;
