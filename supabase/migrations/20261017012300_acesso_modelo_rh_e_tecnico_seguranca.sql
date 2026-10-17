-- Cadastro de usuario novo: Tecnico de Seguranca e RH deixam de nascer com o
-- "Colaborador (padrao)" (so os proprios dados).
--
-- Antes: perfil_modelo_para_tipo mandava para o Colaborador (padrao) todo tipo fora de
-- administrador e da lista de gestao. Um tecnico_seguranca recem-criado (e o tipo rh,
-- sinonimo de RH nas funcoes de ponto) nascia restrito e sem tela de trabalho.
-- Agora:
--   - rh entra na lista de gestao (como rh_dp, que ja estava): modelo "Gestor (padrao)";
--   - tecnico_seguranca ganha um modelo proprio, "Tecnico de Seguranca (padrao)":
--     empresa inteira em Compliance SST, Ergonomia, EPIs, Incidentes e Documentos
--     (visualizar, criar e editar; sem excluir nem aprovar) e, no resto, o autosservico do
--     Colaborador (padrao), so os proprios dados. Nao enxerga salario (pode_ver_salario
--     desligado) e nao abre Usuarios, Perfis, Financeiro nem Psicossocial.
-- O modelo e editavel em Perfis de acesso, como os demais. Nao altera usuarios existentes.
CREATE OR REPLACE FUNCTION public.perfil_modelo_tecnico_sst(p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id uuid;
  m text;
  a text;
BEGIN
  IF p_tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_id := (SELECT pa.id FROM public.perfis_acesso pa
            WHERE pa.tenant_id = p_tenant_id AND pa.nome = 'Técnico de Segurança (padrão)'
            LIMIT 1);
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.perfis_acesso
    (tenant_id, nome, descricao, tipo, ativo, permite_acumulo, cor, icone, criado_por_nome, pode_ver_salario)
  VALUES
    (p_tenant_id, 'Técnico de Segurança (padrão)',
     'Modelo do tipo Técnico de Segurança: empresa inteira em Compliance SST, Ergonomia, EPIs, Incidentes e Documentos (visualizar, criar e editar); no resto, só os próprios dados. Não vê salário. Editável em Perfis de acesso.',
     'padrao_sistema', true, true, '#0EA5E9', 'shield', 'Sistema (modelo)', false)
  RETURNING id INTO v_id;

  FOREACH m IN ARRAY ARRAY['sst', 'ergonomia', 'epi', 'incidentes', 'documentos'] LOOP
    FOREACH a IN ARRAY ARRAY['visualizar', 'criar', 'editar'] LOOP
      INSERT INTO public.perfil_permissoes
        (perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, observacao)
      VALUES
        (v_id, p_tenant_id, m, 'geral', a::public.perfil_acao, 'empresa_inteira', true,
         'Modelo do Técnico de Segurança (gerado pelo sistema)');
    END LOOP;
  END LOOP;

  FOREACH m IN ARRAY ARRAY['colaboradores', 'atestados', 'financeiro', 'bem_estar',
                           'trilhas', 'pdi', 'feedback'] LOOP
    INSERT INTO public.perfil_permissoes
      (perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, observacao)
    VALUES
      (v_id, p_tenant_id, m, 'geral', 'visualizar', 'proprio_usuario', true,
       'Autosserviço do modelo do Técnico de Segurança');
  END LOOP;

  RETURN v_id;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_modelo_tecnico_sst(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_modelo_tecnico_sst(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.perfil_modelo_para_tipo(p_tenant_id uuid, p_tipo text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT CASE
    WHEN COALESCE(p_tipo, '') = 'administrador'
      THEN public.perfil_modelo_administrador(p_tenant_id)
    WHEN COALESCE(p_tipo, '') IN ('gestor', 'lideranca', 'rh_dp', 'rh', 'implantador',
                                  'suporte_autorizado', 'corporativo_multiempresa')
      THEN public.perfil_modelo_gestor(p_tenant_id)
    WHEN COALESCE(p_tipo, '') = 'tecnico_seguranca'
      THEN public.perfil_modelo_tecnico_sst(p_tenant_id)
    ELSE public.perfil_padrao_colaborador(p_tenant_id)
  END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_modelo_para_tipo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_modelo_para_tipo(uuid, text) TO authenticated, service_role;

-- QA PERFIL-015: o modelo por tipo cobre RH e Tecnico de Seguranca (auditoria da definicao,
-- somente leitura: a funcao cria o perfil se faltar, por isso nao e chamada aqui).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_015()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_falhas text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): perfil_modelo_para_tipo trata rh e tecnico_seguranca';
  r.esperado    := 'rh na lista de gestão e tecnico_seguranca apontando para o modelo próprio de SST';

  v_def := pg_get_functiondef('public.perfil_modelo_para_tipo(uuid,text)'::regprocedure);

  IF position('''rh''' IN v_def) = 0 THEN
    v_falhas := v_falhas || 'tipo rh fora da lista de gestão'::text;
  END IF;
  IF position('''tecnico_seguranca''' IN v_def) = 0
     OR position('perfil_modelo_tecnico_sst' IN v_def) = 0 THEN
    v_falhas := v_falhas || 'tecnico_seguranca sem o modelo próprio de SST'::text;
  END IF;
  IF to_regprocedure('public.perfil_modelo_tecnico_sst(uuid)') IS NULL THEN
    v_falhas := v_falhas || 'função perfil_modelo_tecnico_sst ausente'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'rh entra no modelo de gestão e tecnico_seguranca no modelo próprio de SST.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
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
    RAISE NOTICE 'Motor de QA ausente nesta base; caso PERFIL-015 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; caso PERFIL-015 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-015', 'Cadastro novo de RH e Técnico de Segurança recebe o modelo do tipo',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'O cadastro de usuário sem perfil escolhido aplica o modelo do tipo. RH entra no modelo de gestão e o Técnico de Segurança no modelo próprio de SST (empresa inteira em SST, Ergonomia, EPIs, Incidentes e Documentos; resto só os próprios dados). Antes ambos nasciam com o Colaborador (padrão) e ficavam sem tela de trabalho.',
   'Fase 1b e 2a aplicadas.',
   '[{"ordem":1,"acao":"Ler a definição de perfil_modelo_para_tipo e conferir rh e tecnico_seguranca","resultado_esperado":"rh na lista de gestão; tecnico_seguranca aponta para perfil_modelo_tecnico_sst"}]',
   'Modelo por tipo cobre RH e Técnico de Segurança.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-015', 'qa_caso_perfil_015', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-015 nao registrada: %', SQLERRM;
END $qa$;
