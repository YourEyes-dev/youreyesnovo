-- ============================================================================
-- CADASTRO DE COLABORADORES (passo 2.6, PARTE 2): trava de leitura da tabela admissoes por perfil
--
-- Ja aplicada a mao em teste, homologacao e producao (docs/script_admissoes_trava_leitura.sql); esta migration traz o
-- mesmo para o repositorio e para bases novas. Idempotente.
--
-- Le a ficha COMPLETA (CPF, banco, saude do exame admissional, salario...) quem tem escopo amplo em algum modulo de dados de
-- pessoas (lista em ye_modulos_dados_pessoas()), a PROPRIA ficha (CPF do cadastro de usuarios) e, com escopo de subordinados,
-- a ficha dos subordinados diretos. Quem nao esta na lista segue vendo o diretorio de pessoas pelas funcoes da PARTE 1. Vale
-- tambem para a visao admissoes_segura (security_invoker). UPDATE e DELETE passam a exigir linha visivel. Sem perfil vinculado
-- vale o legado por papel. Funcoes security definer, agendador e borda (chave de servico) nao sao afetados.
-- ============================================================================

SET lock_timeout = '10s';

DO $adm$
BEGIN
  IF to_regclass('public.admissoes') IS NULL THEN
    RAISE NOTICE 'admissoes ausente nesta base; nada a fazer.';
    RETURN;
  END IF;
  IF to_regprocedure('public.ye_modulos_dados_pessoas()') IS NULL THEN
    RAISE NOTICE 'ATENCAO: ye_modulos_dados_pessoas ausente; a trava de admissoes nao foi aplicada.';
    RETURN;
  END IF;

  ALTER TABLE public.admissoes ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS perfil_restringe_leitura_admissoes ON public.admissoes;
  CREATE POLICY perfil_restringe_leitura_admissoes ON public.admissoes
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC public.ye_modulos_dados_pessoas())
      OR regexp_replace(COALESCE(cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
      OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC public.ye_modulos_dados_pessoas())
          AND public.ye_cpf_eh_subordinado_direto(tenant_id, cpf))
    );
  RAISE NOTICE 'admissoes: leitura por perfil aplicada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: admissoes ficou SEM a trava de leitura: %', SQLERRM;
END $adm$;
