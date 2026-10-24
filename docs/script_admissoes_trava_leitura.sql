-- ============================================================================
-- ENTREGA — Cadastro de colaboradores (2.6, PARTE 2): trava de leitura da tabela admissoes por perfil
--
-- ATENCAO — SO APLIQUE DEPOIS de (1) a PARTE 1 aplicada (script_admissoes_funcoes_leitura.sql) e (2) as TELAS PUBLICADAS
-- na Vercel com os hooks novos. Antes disso, o mural, os seletores de pessoas, o PDI, as trilhas e o "meu time" ficariam
-- vazios para o colaborador comum, porque ainda leriam a tabela direto.
--
-- O que faz: politica RESTRICTIVE de leitura na tabela admissoes (e, por consequencia, na visao admissoes_segura, que e
-- security_invoker). Le a ficha COMPLETA (CPF, banco, saude do exame admissional, salario...):
--   * quem tem escopo amplo em qualquer modulo de dados de pessoas (lista em ye_modulos_dados_pessoas(): colaboradores, ponto,
--     ferias, financeiro, beneficios, psicossocial, sst, atestados, epi, incidentes, avaliacoes, onboarding, contratos, usuarios,
--     hub contabil, configuracoes, cargos, departamentos, filiais, empresa, ergonomia, analise de jornada);
--   * a PROPRIA ficha (CPF do cadastro de usuarios);
--   * o lider com escopo de subordinados le a ficha dos subordinados diretos.
-- Quem nao esta nessa lista continua vendo o diretorio de pessoas (nome, cargo, departamento, foto...) pelas funcoes da PARTE 1.
-- Sem perfil vinculado vale o legado por papel (gestao), como nas demais travas.
-- UPDATE e DELETE tambem passam a exigir que a linha seja visivel. Funcoes security definer, o agendador e as funcoes de borda
-- (chave de servico) nao sao afetados; o cadastro por link/token (admissao digital) segue pelas funcoes proprias.
-- Nao altera dado. Idempotente. Rode ANTES a consulta_admissoes_quem_muda.sql. Termina com UMA conferencia SELECT.
-- ============================================================================

SET lock_timeout = '10s';

DO $adm$
BEGIN
  IF to_regclass('public.admissoes') IS NULL THEN
    RAISE NOTICE 'admissoes ausente nesta base; nada a fazer.';
    RETURN;
  END IF;
  IF to_regprocedure('public.ye_modulos_dados_pessoas()') IS NULL THEN
    RAISE EXCEPTION 'Aplique antes o script_admissoes_funcoes_leitura.sql (PARTE 1).';
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
END $adm$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='admissoes' AND permissive='RESTRICTIVE'
      AND policyname = 'perfil_restringe_leitura_admissoes') AS politica_nova,
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='admissoes' AND cmd IN ('SELECT','ALL')) AS politicas_de_leitura_no_total;
-- Esperado: 1 e (o numero que ja havia + 1).
-- DESFAZER (devolve a leitura aberta a empresa, como era): DROP POLICY IF EXISTS perfil_restringe_leitura_admissoes ON public.admissoes;
