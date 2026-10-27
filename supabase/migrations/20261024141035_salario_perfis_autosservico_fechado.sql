-- ============================================================================
-- SALARIO (passo 2.3, 2a fatia): perfis de AUTOSSERVICO nao veem salario
--
-- A consulta de impacto do passo anterior mostrou, em producao, dezenas de perfis "Colaborador com Acesso" (modelo
-- criado para cada cliente) e outros perfis que so liberam os PROPRIOS dados, com "Pode ver salario" LIGADO. Para um perfil
-- que so enxerga os proprios dados, ver salario nao faz sentido (o proprio holerite continua visivel pela regra da folha) e
-- quem fosse vinculado a ele leria o salario de todos pela visao do cadastro.
--
-- Regra: perfil ativo, com "Pode ver salario" ligado e SEM nenhuma permissao em escopo diferente de "proprio usuario"
-- (inclui perfil sem permissao nenhuma) tem o salario DESLIGADO. Antes, copia as linhas para
-- backup_perfis_salario_autoss_20261024, com o comando de desfazer no fim.
-- NAO toca perfis com algum acesso amplo ou de equipe (gestor, RH, administrador, "Perfil Basico" da Taeco...): esses sao
-- decisao de cada cliente (a opcao fica na tela de Perfis de acesso).
-- Idempotente. Nao apaga dado.
-- ============================================================================

SET lock_timeout = '10s';

DO $aut$
BEGIN
  IF to_regclass('public.perfis_acesso') IS NULL OR to_regclass('public.perfil_permissoes') IS NULL THEN
    RAISE NOTICE 'perfis_acesso/perfil_permissoes ausentes; nada a fazer.';
    RETURN;
  END IF;

  -- a tabela de copia e criada por EXECUTE para o editor de SQL nao acionar o RLS automatico
  IF to_regclass('public.backup_perfis_salario_autoss_20261024') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_perfis_salario_autoss_20261024 AS '
         || 'SELECT pa.id, pa.tenant_id, pa.nome, pa.pode_ver_salario, now() AS copiado_em FROM public.perfis_acesso pa '
         || 'WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario '
         || 'AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true) '
         || 'AND COALESCE(pp.escopo::text, '''') <> ''proprio_usuario'')';
  END IF;

  UPDATE public.perfis_acesso pa
     SET pode_ver_salario = false
   WHERE COALESCE(pa.ativo, true) AND pa.pode_ver_salario
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes pp
                      WHERE pp.perfil_id = pa.id AND COALESCE(pp.ativo, true)
                        AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario');
  RAISE NOTICE 'Salario: perfis de autosservico desligados.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: perfis de autosservico nao foram ajustados: %', SQLERRM;
END $aut$;
