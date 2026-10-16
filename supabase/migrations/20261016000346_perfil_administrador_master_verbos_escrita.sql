-- Perfil "Administrador Master": acrescenta os verbos Excluir (6 modulos) e Aprovar (Ferias e
-- Financeiro) onde o perfil JA tem acesso amplo ao modulo e esses verbos faltam.
--
-- Por que: a partir das Fases 2b a 2e, quem tem perfil vinculado so grava com o verbo no modulo.
-- A pre-checagem de producao mostrou que o Administrador Master (12 usuarios em 2 clientes)
-- nao tem Excluir em varios modulos nem Aprovar em Ferias e Financeiro; sem este acerto,
-- ele deixaria de excluir e de aprovar ferias e 13o. Mantem o que esses usuarios fazem hoje.
--
-- Regras do acerto:
--  - so perfis de nome "Administrador Master" que NAO sejam o modelo do sistema;
--  - so modulos onde o perfil ja tem acesso amplo (escopo diferente de proprio usuario);
--    nunca abre modulo novo;
--  - copia o escopo ja existente do modulo; nao duplica verbo; se o verbo existir desligado,
--    religa; se o perfil ja tem Administrar no modulo, nao faz nada ali;
--  - antes de tocar, guarda uma copia das permissoes do perfil em
--    backup_perfil_verbos_20261016 (fechada para a API); sem a copia, nao altera nada;
--  - cada linha nova leva uma marca na observacao, para o desfazer ser exato.
DO $acc1$
BEGIN
  IF to_regclass('public.backup_perfil_verbos_20261016') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfil_verbos_20261016 AS '
         || 'SELECT pp.* FROM public.perfil_permissoes pp '
         || 'JOIN public.perfis_acesso pa ON pa.id = pp.perfil_id '
         || 'WHERE pa.nome = ''Administrador Master'' '
         || 'AND COALESCE(pa.tipo::text, '''') <> ''padrao_sistema''';
    EXECUTE 'ALTER TABLE public.backup_perfil_verbos_20261016 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_perfil_verbos_20261016 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'copia de seguranca das permissoes nao criada: % (%)', SQLERRM, SQLSTATE;
END
$acc1$;

DO $acc2$
DECLARE
  v_marca text := 'Acrescentado em 16/10/2026 (script de verbos de escrita)';
  v_religados int := 0;
  v_novos int := 0;
BEGIN
  IF to_regclass('public.backup_perfil_verbos_20261016') IS NULL THEN
    RAISE NOTICE 'sem copia de seguranca: nada foi alterado';
    RETURN;
  END IF;

  -- 1) religa verbo que existe desligado
  UPDATE public.perfil_permissoes pp
     SET ativo = true
    FROM public.perfis_acesso pa,
         (VALUES ('ferias','excluir'), ('ferias','aprovar'), ('financeiro','excluir'),
                 ('financeiro','aprovar'), ('psicossocial','excluir'), ('ponto','excluir'),
                 ('beneficios','excluir'), ('analise_jornada','excluir')) AS w(modulo, acao)
   WHERE pa.id = pp.perfil_id
     AND pa.nome = 'Administrador Master'
     AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
     AND pp.modulo = w.modulo
     AND pp.acao::text = w.acao
     AND pp.ativo = false
     AND EXISTS (SELECT 1 FROM public.perfil_permissoes x
                  WHERE x.perfil_id = pp.perfil_id AND x.modulo = pp.modulo
                    AND COALESCE(x.ativo, true) = true
                    AND COALESCE(x.escopo::text, '') <> 'proprio_usuario');
  GET DIAGNOSTICS v_religados = ROW_COUNT;

  -- 2) acrescenta o verbo que nao existe
  INSERT INTO public.perfil_permissoes
    (perfil_id, tenant_id, modulo, acao, escopo, ativo, is_sensivel, observacao)
  SELECT a.perfil_id, a.tenant_id, a.modulo, w.acao::public.perfil_acao, a.escopo,
         true, false, v_marca
    FROM (
      SELECT pa.id AS perfil_id, pa.tenant_id, pp.modulo,
             (array_agg(pp.escopo ORDER BY (pp.escopo::text = 'empresa_inteira') DESC, pp.escopo::text))[1] AS escopo
        FROM public.perfis_acesso pa
        JOIN public.perfil_permissoes pp
          ON pp.perfil_id = pa.id AND COALESCE(pp.ativo, true) = true
         AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
       WHERE pa.nome = 'Administrador Master'
         AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
       GROUP BY pa.id, pa.tenant_id, pp.modulo
    ) a
    JOIN (VALUES ('ferias','excluir'), ('ferias','aprovar'), ('financeiro','excluir'),
                 ('financeiro','aprovar'), ('psicossocial','excluir'), ('ponto','excluir'),
                 ('beneficios','excluir'), ('analise_jornada','excluir')) AS w(modulo, acao)
      ON w.modulo = a.modulo
   WHERE NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = a.perfil_id AND x.modulo = a.modulo
                        AND x.acao::text IN (w.acao, 'administrar')
                        AND COALESCE(x.ativo, true) = true);
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  -- 3) registro de auditoria do perfil (uma linha por perfil alterado)
  IF v_novos > 0 THEN
    INSERT INTO public.perfil_audit_log
      (tenant_id, perfil_id, acao, descricao, dados_novos, realizado_por_nome)
    SELECT p.tenant_id, p.perfil_id, 'alteracao',
           'Verbos Excluir/Aprovar acrescentados por script de entrega (16/10/2026)',
           jsonb_build_object('linhas_acrescentadas', count(*)),
           'Sistema (script de entrega)'
      FROM public.perfil_permissoes p
     WHERE p.observacao = v_marca AND p.created_at = now()
     GROUP BY p.tenant_id, p.perfil_id;
  END IF;

  RAISE NOTICE 'verbos religados: %, acrescentados: %', v_religados, v_novos;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'acerto de verbos nao aplicado: % (%)', SQLERRM, SQLSTATE;
END
$acc2$;
