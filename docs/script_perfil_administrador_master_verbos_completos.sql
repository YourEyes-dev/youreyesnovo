-- ============================================================================
-- ENTREGA — Administrador Master (parte 3): todos os verbos nos modulos do plano
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO (depois das partes 1 e 2).
-- ============================================================================

-- Administrador Master (parte 3): acesso total aos modulos do plano, com TODOS os verbos.
--
-- Decisao do dono do produto (21/10/2026): o Administrador Master ve e movimenta tudo da empresa,
-- nos modulos que o plano libera. Isso inclui Excluir, Aprovar e os verbos sensiveis (Dados Sensiveis,
-- Dados Individualizados, Dados Anonimizados, Indicadores).
--
-- Regras:
--  - mesmos perfis da parte 2 (Administrador Master nao-modelo, ou modelo de sistema com usuario ativo)
--    em clientes com assinatura viva, e so nos modulos que o plano libera;
--  - para cada modulo x verbo sem permissao ATIVA: religa a linha desligada, se existir; senao acrescenta
--    (escopo empresa inteira). Linha ja ativa nunca e alterada;
--  - copia de seguranca das permissoes antes (backup_perfil_master_verbos3_20261021); sem ela nada muda;
--  - linhas novas e religadas levam a marca na observacao (religadas: marca no fim do texto anterior).
-- Idempotente.

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.admin_master_modulos_plano()
RETURNS TABLE(perfil_id uuid, tenant_id uuid, modulo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $amp$
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
     AND (m.feature IS NULL OR public.tenant_has_feature(pa.tenant_id, m.feature));
$amp$;

CREATE OR REPLACE FUNCTION public.admin_master_verbos_faltantes()
RETURNS TABLE(perfil_id uuid, tenant_id uuid, modulo text, acao text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $amv$
  SELECT p.perfil_id, p.tenant_id, p.modulo, v.acao
    FROM public.admin_master_modulos_plano() p
   CROSS JOIN (VALUES ('visualizar'), ('criar'), ('editar'), ('excluir'), ('inativar'),
                      ('exportar'), ('importar'), ('aprovar'), ('assinar'), ('compartilhar'),
                      ('parametrizar'), ('administrar'), ('acessar_sensivel'),
                      ('acessar_anonimizado'), ('ver_indicadores'), ('ver_individual')) AS v(acao)
   WHERE NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = p.perfil_id AND x.modulo = p.modulo
                        AND x.acao::text = v.acao AND COALESCE(x.ativo, true) = true);
$amv$;

REVOKE ALL ON FUNCTION public.admin_master_modulos_plano() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_master_verbos_faltantes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_master_modulos_plano() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_master_verbos_faltantes() TO service_role;

DO $amb3$
BEGIN
  IF to_regclass('public.backup_perfil_master_verbos3_20261021') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfil_master_verbos3_20261021 AS '
         || 'SELECT pp.* FROM public.perfil_permissoes pp '
         || 'JOIN public.perfis_acesso pa ON pa.id = pp.perfil_id '
         || 'WHERE pa.nome = ''Administrador Master''';
    EXECUTE 'ALTER TABLE public.backup_perfil_master_verbos3_20261021 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_perfil_master_verbos3_20261021 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'copia de seguranca nao criada: % (%)', SQLERRM, SQLSTATE;
END
$amb3$;

DO $amc3$
DECLARE
  v_marca text := 'Ajustado em 21/10/2026 (verbos completos do Administrador Master)';
  v_religados int := 0;
  v_novos int := 0;
BEGIN
  IF to_regclass('public.backup_perfil_master_verbos3_20261021') IS NULL THEN
    RAISE NOTICE 'sem copia de seguranca: nada foi alterado';
    RETURN;
  END IF;

  -- 1) religa a linha desligada (uma por modulo x verbo faltante)
  UPDATE public.perfil_permissoes pp
     SET ativo = true,
         observacao = left(COALESCE(pp.observacao || ' | ', '') || v_marca, 500)
   WHERE pp.id IN (
     SELECT (array_agg(x.id ORDER BY x.created_at))[1]
       FROM public.admin_master_verbos_faltantes() f
       JOIN public.perfil_permissoes x
         ON x.perfil_id = f.perfil_id AND x.modulo = f.modulo AND x.acao::text = f.acao
      GROUP BY f.perfil_id, f.modulo, f.acao);
  GET DIAGNOSTICS v_religados = ROW_COUNT;

  -- 2) acrescenta o que ainda falta (nao ha linha nenhuma desse verbo)
  INSERT INTO public.perfil_permissoes
    (perfil_id, tenant_id, modulo, acao, escopo, ativo, is_sensivel, observacao)
  SELECT f.perfil_id, f.tenant_id, f.modulo, f.acao::public.perfil_acao,
         'empresa_inteira'::public.perfil_escopo_tipo, true,
         (f.acao IN ('administrar', 'acessar_sensivel', 'ver_individual')), v_marca
    FROM public.admin_master_verbos_faltantes() f;
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  IF v_novos + v_religados > 0 THEN
    INSERT INTO public.perfil_audit_log
      (tenant_id, perfil_id, acao, descricao, dados_novos, realizado_por_nome)
    SELECT p.tenant_id, p.perfil_id, 'alteracao',
           'Verbos completos do Administrador Master nos modulos do plano, por script de entrega (21/10/2026)',
           jsonb_build_object('linhas', count(*)),
           'Sistema (script de entrega)'
      FROM public.perfil_permissoes p
     WHERE p.observacao LIKE '%'||v_marca AND p.perfil_id IN (
             SELECT DISTINCT perfil_id FROM public.admin_master_modulos_plano())
     GROUP BY p.tenant_id, p.perfil_id;
  END IF;

  RAISE NOTICE 'verbos religados: %, acrescentados: %', v_religados, v_novos;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'acerto de verbos nao aplicado: % (%)', SQLERRM, SQLSTATE;
END
$amc3$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(*) FROM public.admin_master_verbos_faltantes())                  AS verbos_faltando_esperado_0,
  (SELECT count(DISTINCT perfil_id) FROM public.perfil_permissoes
    WHERE observacao LIKE '%Ajustado em 21/10/2026 (verbos completos do Administrador Master)')                                        AS perfis_alterados,
  (SELECT count(*) FROM public.perfil_permissoes
    WHERE observacao LIKE '%Ajustado em 21/10/2026 (verbos completos do Administrador Master)')                                        AS linhas_tocadas,
  (CASE WHEN to_regclass('public.backup_perfil_master_verbos3_20261021') IS NULL
        THEN 'ATENCAO: sem copia de seguranca' ELSE 'ok' END)                     AS erro_tecnico;

-- ── DESFAZER (so se precisar; rode em separado) ─────────────────────────────
-- 1) Remover as linhas novas (as que nasceram com a marca pura):
--    DELETE FROM public.perfil_permissoes WHERE observacao = 'Ajustado em 21/10/2026 (verbos completos do Administrador Master)';
-- 2) Desligar de novo as religadas (volta ao estado da copia):
--    UPDATE public.perfil_permissoes p SET ativo = b.ativo, observacao = b.observacao
--      FROM public.backup_perfil_master_verbos3_20261021 b WHERE p.id = b.id;
