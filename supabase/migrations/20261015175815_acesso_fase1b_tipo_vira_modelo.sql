-- ============================================================================
-- Acesso — Fase 1b: o "tipo" vira MODELO (todo usuário novo nasce com perfil)
--
-- Hoje usuários tipo administrador/gestor NÃO recebem perfil automático (o
-- trigger de 20260808110000 pula os dois, de propósito, para não reduzir o
-- acesso deles). Com a Fase 1a no ar (perfil vinculado tem a palavra final),
-- queremos o oposto: TODO usuário novo nasce com um PERFIL correspondente ao
-- seu "modelo" (o antigo tipo). Assim o tipo deixa de ser uma régua paralela e
-- vira só o molde inicial.
--
-- Como não reduzir ninguém: cada modelo é um perfil de ESCOPO AMPLO adequado:
--   • Administrador (padrão): acesso amplo a TODOS os módulos (empresa inteira)
--     -> mesma largura que um administrador tem hoje.
--   • Gestor (padrão): idem, acesso amplo (empresa inteira) a todos os módulos
--     -> mesma largura de hoje; fica editável num lugar só (basta editar este
--     modelo para, por ex., passar Ponto/Férias a "subordinados diretos").
--   • Colaborador (padrão): o que já existe (tudo próprio usuário).
--
-- Os modelos são perfis 'padrao_sistema' por cliente, criados sob demanda e
-- idempotentes por (tenant, nome). O vínculo é NÃO-principal: se o RH escolher
-- um perfil de verdade, ele vira principal e o modelo automático é desativado
-- (trigger de substituição, abaixo, agora generalizado para qualquer modelo).
--
-- NENHUM usuário existente é alterado: a regra vale só para cadastros NOVOS
-- (trigger AFTER INSERT em usuarios_base). Trazer os usuários atuais para o
-- modelo "todo mundo com perfil" é um passo à parte (backfill), com a consulta
-- de quem seria afetado, e só vai à produção com aprovação.
--
-- Cobertura dos módulos: a lista inclui os 43 módulos do sistema
-- (MODULOS_SISTEMA) + 'admissoes' (usado por políticas de RLS) — cobre todos os
-- porteiros perfil_permite_modulo/perfil_amplo hoje existentes.
-- ============================================================================

-- 1) MODELO DE ACESSO TOTAL (usado por Administrador e Gestor) ----------------
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

-- 2) CADASTRO NOVO: o modelo é escolhido pelo tipo --------------------------
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
  -- O modelo acompanha o tipo escolhido no cadastro.
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
  RAISE NOTICE 'perfil modelo não vinculado para %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$fn$;

-- 3) PERFIL DE VERDADE SUBSTITUI QUALQUER MODELO AUTOMÁTICO ------------------
-- Generalizado: ao vincular um perfil que NÃO é 'padrao_sistema' (modelo), os
-- vínculos de modelo automático ativos do usuário são desativados.
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

  -- Se o que está entrando é um modelo do sistema, não desativa nada.
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
  RAISE NOTICE 'substituição do modelo falhou para %: %', NEW.usuario_id, SQLERRM;
  RETURN NEW;
END;
$fn$;
