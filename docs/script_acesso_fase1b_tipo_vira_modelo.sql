-- ============================================================================
-- ENTREGA — Acesso Fase 1b: o "tipo" vira MODELO (usuario novo nasce com perfil)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: a camada de perfil ja existe (perfil_padrao_colaborador etc.).
--
-- Roda em UMA transacao, idempotente (CREATE OR REPLACE). NAO cria tabela ->
-- sem auto-RLS. Nao altera nem apaga dado de usuarios existentes.
--
-- O que muda: a partir de agora, todo usuario NOVO nasce com um perfil =
-- modelo do seu tipo. Administrador e Gestor ganham um modelo de ACESSO AMPLO
-- (empresa inteira, todos os modulos) -> mesma largura de hoje, agora editavel
-- num so lugar. Colaborador segue com o "Colaborador (padrao)" (proprio).
-- Usuarios EXISTENTES nao sao tocados (o trigger vale so para INSERT novo).
--
-- O vinculo do modelo e NAO-principal: ao escolher um perfil de verdade, ele
-- vira principal e o modelo automatico e desativado (trigger generalizado).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.perfil_modelo_acesso_total(
  p_tenant_id uuid, p_nome text, p_descricao text, p_icone text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid;
  m text;
  v_modulos text[] := ARRAY[
    'empresa','filiais','departamentos','cargos','colaboradores','terceiros','organograma',
    'identidade_estrategica','planejamento_estrategico','metas','plano_acao',
    'onboarding','contratos_experiencia','cultura_celebracoes','feed','bem_estar','feedback','ouvidoria',
    'aprendizado','trilhas','avaliacoes','pdi','mapa_comportamental',
    'ponto','analise_jornada','ferias','atestados','beneficios',
    'sst','psicossocial','ergonomia','epi','incidentes',
    'documentos','hub_contabil',
    'financeiro','marketplace','academia',
    'usuarios','perfis_acesso','configuracoes','suporte','auditoria',
    'admissoes'
  ];
BEGIN
  IF p_tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_id
  FROM public.perfis_acesso
  WHERE tenant_id = p_tenant_id AND nome = p_nome
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.perfis_acesso
    (tenant_id, nome, descricao, tipo, ativo, permite_acumulo, cor, icone, criado_por_nome, pode_ver_salario)
  VALUES
    (p_tenant_id, p_nome, p_descricao, 'padrao_sistema', true, true, '#6366F1', p_icone,
     'Sistema (modelo)', true)
  RETURNING id INTO v_id;

  FOREACH m IN ARRAY v_modulos LOOP
    INSERT INTO public.perfil_permissoes
      (perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, observacao)
    VALUES
      (v_id, p_tenant_id, m, 'geral', 'administrar', 'empresa_inteira', true,
       'Modelo de acesso (gerado pelo sistema)');
  END LOOP;

  RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.perfil_modelo_administrador(p_tenant_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT public.perfil_modelo_acesso_total(
    p_tenant_id, 'Administrador (padrão)',
    'Modelo do tipo Administrador: acesso amplo (empresa inteira) a todos os módulos. Editável em um só lugar.',
    'shield');
$fn$;

CREATE OR REPLACE FUNCTION public.perfil_modelo_gestor(p_tenant_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT public.perfil_modelo_acesso_total(
    p_tenant_id, 'Gestor (padrão)',
    'Modelo do tipo Gestor: acesso amplo (empresa inteira) a todos os módulos. Edite este modelo para restringir (ex.: Ponto/Férias por subordinados diretos).',
    'users');
$fn$;

DO $g$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY[
    'public.perfil_modelo_acesso_total(uuid, text, text, text)',
    'public.perfil_modelo_administrador(uuid)',
    'public.perfil_modelo_gestor(uuid)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r);
  END LOOP;
END $g$;

CREATE OR REPLACE FUNCTION public.trg_vincular_perfil_padrao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_perfil uuid;
  v_tipo text := COALESCE(NEW.tipo_usuario::text, 'colaborador');
BEGIN
  IF v_tipo = 'administrador' THEN
    v_perfil := public.perfil_modelo_administrador(NEW.tenant_id);
  ELSIF v_tipo = 'gestor' THEN
    v_perfil := public.perfil_modelo_gestor(NEW.tenant_id);
  ELSE
    v_perfil := public.perfil_padrao_colaborador(NEW.tenant_id);
  END IF;

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

CREATE OR REPLACE FUNCTION public.trg_substituir_perfil_padrao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_novo_tipo text;
BEGIN
  IF COALESCE(NEW.ativo, true) = false THEN
    RETURN NEW;
  END IF;

  SELECT pa.tipo::text INTO v_novo_tipo
  FROM public.perfis_acesso pa
  WHERE pa.id = NEW.perfil_id
  LIMIT 1;

  IF v_novo_tipo = 'padrao_sistema' THEN
    RETURN NEW;
  END IF;

  UPDATE public.usuario_perfil_vinculos v
  SET ativo = false,
      observacao = COALESCE(v.observacao, '')
        || ' [desativado automaticamente: perfil escolhido vinculado em '
        || to_char(now(), 'DD/MM/YYYY') || ']'
  FROM public.perfis_acesso pa
  WHERE v.perfil_id = pa.id
    AND pa.tipo::text = 'padrao_sistema'
    AND v.tenant_id = NEW.tenant_id
    AND v.usuario_id = NEW.usuario_id
    AND v.id <> NEW.id
    AND COALESCE(v.ativo, true) = true;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'substituicao do modelo falhou para %: %', NEW.usuario_id, SQLERRM;
  RETURN NEW;
END;
$fn$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_proc
     WHERE proname IN ('perfil_modelo_acesso_total','perfil_modelo_administrador','perfil_modelo_gestor')) AS funcs_modelo_esperado_3,
  (SELECT count(*) FROM pg_proc
     WHERE proname = 'trg_vincular_perfil_padrao'
       AND pg_get_functiondef(oid) LIKE '%perfil_modelo_administrador%') AS vincular_ok_esperado_1,
  (SELECT count(*) FROM pg_proc
     WHERE proname = 'trg_substituir_perfil_padrao'
       AND pg_get_functiondef(oid) LIKE '%padrao_sistema%') AS substituir_ok_esperado_1;
