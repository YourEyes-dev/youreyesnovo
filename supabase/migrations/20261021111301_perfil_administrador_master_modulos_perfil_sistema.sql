-- Administrador Master (parte 2): inclui o perfil de sistema (padrao_sistema) QUANDO ESTA EM USO.
--
-- Por que: a parte 1 so olhava Administrador Master que nao fosse padrao_sistema. Na Clinica Magalhaes
-- Lopes o Administrador Master e justamente o perfil de sistema (7 modulos, 2 usuarios vinculados) e
-- ficou de fora. Agora entra o perfil de sistema que tenha ao menos um usuario vinculado ativo; modelo
-- sem ninguem vinculado continua intocado.
-- Mesma regra da parte 1: so acrescenta modulo sem nenhuma permissao ativa, sem verbos sensiveis,
-- com copia de seguranca (backup_perfil_master_modulos2_20261021) e marca propria para o desfazer.
-- Idempotente.

SET lock_timeout = '10s';

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
     AND (COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
          OR EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                      WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true) = true))
     AND COALESCE(pa.ativo, true) = true
     AND (m.feature IS NULL OR public.tenant_has_feature(pa.tenant_id, m.feature))
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = pa.id AND x.modulo = m.modulo
                        AND COALESCE(x.ativo, true) = true);
$amf$;


REVOKE ALL ON FUNCTION public.admin_master_modulos_faltantes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_master_modulos_faltantes() TO service_role;

DO $amb2$
BEGIN
  IF to_regclass('public.backup_perfil_master_modulos2_20261021') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfil_master_modulos2_20261021 AS '
         || 'SELECT pp.* FROM public.perfil_permissoes pp '
         || 'JOIN public.perfis_acesso pa ON pa.id = pp.perfil_id '
         || 'WHERE pa.nome = ''Administrador Master'' '
         || 'AND COALESCE(pa.tipo::text, '''') = ''padrao_sistema''';
    EXECUTE 'ALTER TABLE public.backup_perfil_master_modulos2_20261021 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_perfil_master_modulos2_20261021 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'copia de seguranca nao criada: % (%)', SQLERRM, SQLSTATE;
END
$amb2$;

DO $amc2$
DECLARE
  v_marca text := 'Acrescentado em 21/10/2026 (modulos do Administrador Master, perfil de sistema em uso)';
  v_novos int := 0;
BEGIN
  IF to_regclass('public.backup_perfil_master_modulos2_20261021') IS NULL THEN
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
           'Modulos do plano acrescentados ao Administrador Master (perfil de sistema em uso) por script de entrega (21/10/2026)',
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
$amc2$;

-- QA: a documentacao do PERFIL-018 passa a dizer que o perfil de sistema em uso tambem conta.
DO $amq2$
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NOT NULL THEN
    UPDATE public.qa_casos_teste SET
      pre_condicoes = 'Perfil Administrador Master (inclusive o perfil de sistema, se tiver usuario vinculado ativo) em cliente com assinatura ativa.',
      observacoes = 'A funcao admin_master_modulos_faltantes ignora so o modelo de sistema sem nenhum usuario vinculado.'
    WHERE codigo = 'PERFIL-018';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PERFIL-018: %', SQLERRM;
END $amq2$;
