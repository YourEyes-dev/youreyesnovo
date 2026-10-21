-- Administrador Master: acrescenta os modulos do plano que faltam no perfil.
--
-- Por que: o Administrador Master da CLINICA MEDICA AMBULATORIAL MAGALHAES LOPES S/S LTDA (producao)
-- nao tinha todos os modulos. O perfil e gravado uma vez; modulo criado depois (ou plano que
-- cresceu) nao entra sozinho. Esta entrega cruza, para TODOS os clientes, os modulos que o plano
-- libera (tenant_has_feature) com as permissoes ativas do Administrador Master e acrescenta so o
-- que falta.
--
-- Regras:
--  - so perfis de nome "Administrador Master" que NAO sejam o modelo do sistema (padrao_sistema);
--  - so clientes com assinatura viva (nao pausada/cancelada); sem assinatura nao mexe;
--  - so acrescenta modulo SEM nenhuma permissao ativa; nunca altera nem remove o que existe;
--  - verbos comuns + Administrar, escopo empresa inteira; verbos sensiveis (dados sensiveis,
--    dados individualizados) NAO sao concedidos aqui;
--  - guarda copia antes (backup_perfil_master_modulos_20261021, fechada para a API); sem a copia
--    nao altera nada; cada linha nova leva marca na observacao para o desfazer ser exato.

SET lock_timeout = '10s';

-- 1) Funcao de apoio (somente leitura): quais modulos do plano faltam em cada Administrador Master.
--    Mapa modulo do perfil -> funcionalidade do plano (NULL = modulo de base, sempre liberado).
--    So olha clientes com assinatura viva (nao pausada/cancelada); sem assinatura nao mexe.
CREATE OR REPLACE FUNCTION public.admin_master_modulos_faltantes()
RETURNS TABLE(perfil_id uuid, tenant_id uuid, modulo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $amf$
  SELECT pa.id, pa.tenant_id, m.modulo
    FROM public.perfis_acesso pa
    JOIN public.subscriptions s
      ON s.tenant_id = pa.tenant_id AND s.status NOT IN ('paused', 'canceled')
   CROSS JOIN (VALUES
      ('empresa', NULL), ('filiais', NULL), ('departamentos', NULL), ('cargos', NULL),
      ('colaboradores', NULL), ('terceiros', NULL), ('organograma', NULL),
      ('identidade_estrategica', 'mod.estrategia'), ('planejamento_estrategico', 'mod.estrategia'),
      ('metas', 'mod.metas'), ('plano_acao', 'mod.metas'),
      ('onboarding', 'mod.onboarding'), ('contratos_experiencia', 'mod.contratos_exp'),
      ('cultura_celebracoes', 'mod.cultura'), ('feed', 'mod.cultura'),
      ('feedback', 'mod.cultura'), ('ouvidoria', 'mod.cultura'),
      ('bem_estar', 'mod.bem_estar'),
      ('aprendizado', 'mod.trilhas'), ('trilhas', 'mod.trilhas'),
      ('avaliacoes', 'mod.avaliacoes'), ('pdi', 'mod.pdi'),
      ('mapa_comportamental', 'mod.mapa_comportamental'),
      ('ponto', 'mod.ponto'), ('analise_jornada', 'mod.analise_jornada'),
      ('ferias', 'mod.ferias'), ('atestados', 'mod.ferias'),
      ('beneficios', 'mod.beneficios'), ('documentos', 'mod.beneficios'),
      ('hub_contabil', 'mod.beneficios'),
      ('sst', 'mod.nr1'), ('psicossocial', 'mod.psicossocial'),
      ('ergonomia', 'mod.epi_ergo'), ('epi', 'mod.epi_ergo'),
      ('incidentes', 'mod.incidentes'), ('financeiro', 'mod.financeiro'),
      ('marketplace', NULL), ('academia', NULL),
      ('usuarios', NULL), ('perfis_acesso', NULL), ('configuracoes', NULL),
      ('suporte', NULL), ('auditoria', NULL)
   ) AS m(modulo, feature)
   WHERE pa.nome = 'Administrador Master'
     AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
     AND COALESCE(pa.ativo, true) = true
     AND (m.feature IS NULL OR public.tenant_has_feature(pa.tenant_id, m.feature))
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = pa.id AND x.modulo = m.modulo
                        AND COALESCE(x.ativo, true) = true);
$amf$;

REVOKE ALL ON FUNCTION public.admin_master_modulos_faltantes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_master_modulos_faltantes() TO service_role;

-- 2) Copia de seguranca das permissoes dos Administradores Master (fechada para a API).
DO $amb$
BEGIN
  IF to_regclass('public.backup_perfil_master_modulos_20261021') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfil_master_modulos_20261021 AS '
         || 'SELECT pp.* FROM public.perfil_permissoes pp '
         || 'JOIN public.perfis_acesso pa ON pa.id = pp.perfil_id '
         || 'WHERE pa.nome = ''Administrador Master'' '
         || 'AND COALESCE(pa.tipo::text, '''') <> ''padrao_sistema''';
    EXECUTE 'ALTER TABLE public.backup_perfil_master_modulos_20261021 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_perfil_master_modulos_20261021 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'copia de seguranca nao criada: % (%)', SQLERRM, SQLSTATE;
END
$amb$;

-- 3) Acrescenta os modulos que faltam (so modulo SEM nenhuma permissao ativa; nunca mexe no que ja existe).
--    Verbos comuns + Administrar; os verbos sensiveis (dados sensiveis, individualizados) ficam de fora.
DO $amc$
DECLARE
  v_marca text := 'Acrescentado em 21/10/2026 (script de modulos do Administrador Master)';
  v_novos int := 0;
BEGIN
  IF to_regclass('public.backup_perfil_master_modulos_20261021') IS NULL THEN
    RAISE NOTICE 'sem copia de seguranca: nada foi alterado';
    RETURN;
  END IF;

  INSERT INTO public.perfil_permissoes
    (perfil_id, tenant_id, modulo, acao, escopo, ativo, is_sensivel, observacao)
  SELECT f.perfil_id, f.tenant_id, f.modulo, v.acao::public.perfil_acao,
         'empresa_inteira'::public.perfil_escopo_tipo, true, (v.acao = 'administrar'), v_marca
    FROM public.admin_master_modulos_faltantes() f
   CROSS JOIN (VALUES ('visualizar'), ('criar'), ('editar'), ('excluir'), ('inativar'),
                      ('exportar'), ('importar'), ('aprovar'), ('assinar'), ('compartilhar'),
                      ('parametrizar'), ('administrar'), ('ver_indicadores')) AS v(acao);
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  IF v_novos > 0 THEN
    INSERT INTO public.perfil_audit_log
      (tenant_id, perfil_id, acao, descricao, dados_novos, realizado_por_nome)
    SELECT p.tenant_id, p.perfil_id, 'alteracao',
           'Modulos do plano acrescentados ao Administrador Master por script de entrega (21/10/2026)',
           jsonb_build_object('modulos', jsonb_agg(DISTINCT p.modulo)),
           'Sistema (script de entrega)'
      FROM public.perfil_permissoes p
     WHERE p.observacao = v_marca AND p.created_at = now()
     GROUP BY p.tenant_id, p.perfil_id;
  END IF;

  RAISE NOTICE 'linhas de permissao acrescentadas: %', v_novos;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'acerto de modulos nao aplicado: % (%)', SQLERRM, SQLSTATE;
END
$amc$;

-- 4) QA — PERFIL-018 (nivel api, somente leitura): todo Administrador Master tem os modulos do plano.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_018()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_qtd bigint;
  v_perfis bigint;
  v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): cada Administrador Master tem permissao ativa em todo modulo liberado pelo plano';
  r.esperado    := 'Nenhum par perfil/modulo liberado pelo plano e sem permissao no Administrador Master';

  IF to_regprocedure('public.admin_master_modulos_faltantes()') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido   := 'Funcao admin_master_modulos_faltantes ausente.';
    RETURN r;
  END IF;

  v_qtd := (SELECT count(*) FROM public.admin_master_modulos_faltantes());
  v_perfis := (SELECT count(DISTINCT perfil_id) FROM public.admin_master_modulos_faltantes());
  v_lista := (SELECT string_agg(x.modulo, ', ' ORDER BY x.modulo)
                FROM (SELECT DISTINCT modulo FROM public.admin_master_modulos_faltantes() LIMIT 15) x);

  IF v_qtd = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Todos os Administradores Master tem os modulos do plano do cliente.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := v_perfis || ' perfil(is) Administrador Master sem ' || v_qtd
               || ' modulo(s) do plano (ex.: ' || COALESCE(v_lista, '-') || ').';
    r.detalhe  := jsonb_build_object('perfis', v_perfis, 'faltas', v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $amq$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; PERFIL-018 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-018 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-018', 'Administrador Master tem todos os modulos liberados pelo plano do cliente',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46 (acesso conforme a funcao)',
   'O perfil Administrador Master e o acesso total do cliente: deve ter permissao ativa em todo modulo que o plano da empresa libera (mais os modulos de base). Modulo novo ou plano que cresce nao pode deixar o Administrador Master sem acesso. Cliente sem assinatura viva fica fora da conferencia.',
   'Perfil Administrador Master (nao modelo do sistema) em cliente com assinatura ativa.',
   '[{"ordem":1,"acao":"Cruzar os modulos do plano (tenant_has_feature) com as permissoes ativas de cada Administrador Master","resultado_esperado":"Nenhum modulo liberado sem permissao"}]',
   'Nenhum Administrador Master com modulo do plano faltando.')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-018 nao registrada: %', SQLERRM;
END $amq$;
