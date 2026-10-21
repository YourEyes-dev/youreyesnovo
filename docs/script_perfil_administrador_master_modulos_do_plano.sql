-- ============================================================================
-- ENTREGA — Administrador Master: acrescenta os modulos do plano que faltam
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- Antes, rode docs/diagnostico_admin_master_modulos.sql para ver o que sera acrescentado.
-- ============================================================================

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

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Esperado depois: modulos_faltando = 0.
SELECT
  (SELECT count(*) FROM public.admin_master_modulos_faltantes())                  AS modulos_faltando_esperado_0,
  (SELECT count(DISTINCT perfil_id) FROM public.perfil_permissoes
    WHERE observacao = 'Acrescentado em 21/10/2026 (script de modulos do Administrador Master)') AS perfis_alterados,
  (SELECT count(*) FROM public.perfil_permissoes
    WHERE observacao = 'Acrescentado em 21/10/2026 (script de modulos do Administrador Master)') AS linhas_acrescentadas,
  (CASE WHEN to_regclass('public.backup_perfil_master_modulos_20261021') IS NULL
        THEN 'ATENCAO: sem copia de seguranca' ELSE 'ok' END)                      AS erro_tecnico;

-- ── DESFAZER (so se precisar; rode em separado) ─────────────────────────────
--    DELETE FROM public.perfil_permissoes
--     WHERE observacao = 'Acrescentado em 21/10/2026 (script de modulos do Administrador Master)';
