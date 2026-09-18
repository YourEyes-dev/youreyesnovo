-- ============================================================================
-- SCRIPT DE ENTREGA — camada de perfil (RESTRICTIVE) faltante em 5 tabelas
-- sensiveis: beneficios_colaboradores, folha_rescisoes, ferias_alertas,
-- ferias_coletivas, ferias_coletivas_comunicados.
--
-- Achado pelas auditorias RLS-003/RLS-007: essas politicas existem no ambiente
-- de teste, mas nao foram entregues (as de ferias nunca tiveram script). Sem
-- elas, dado sensivel (beneficios, rescisoes, ferias) fica legivel por qualquer
-- usuario autenticado do tenant, sem passar pela camada de perfil.
--
-- MUDANCA DE ACESSO: a politica RESTRINGE a leitura. Quem JA passa hoje continua
-- passando (superadmin, gestor/manager para cima, tipo administrador/gestor,
-- perfil com o modulo em escopo amplo, e o proprio titular pelo CPF). So deixa
-- de ver quem NAO tem nenhum desses. Aplicar na HOMOLOGACAO, conferir as telas
-- de Beneficios/Rescisoes/Ferias com um perfil restrito e com um gestor, e SO
-- ENTAO produção.
--
-- DEADLOCK (licao 09/2026): criar politica trava a tabela em ACCESS EXCLUSIVE.
-- Em cinco tabelas movimentadas numa transacao so, isso da deadlock contra a
-- leitura do app. Este script foi feito para NAO travar quem nao precisa:
--   1) cada tabela e um bloco DO independente, guardado por IF NOT EXISTS —
--      rodar de novo NAO pega lock nenhum (nada a fazer);
--   2) lock_timeout curto: se a tabela estiver ocupada, o bloco falha rapido
--      em vez de travar, e a transacao volta atras inteira.
-- MELHOR CAMINHO: rode com a homologacao OCIOSA (sem testador mexendo). Se ainda
-- assim der deadlock/timeout, rode CADA bloco DO separado (selecione um bloco e
-- execute) — cada um e uma transacao de uma tabela so, a prova de deadlock.
-- ============================================================================

SET lock_timeout = '5s';

-- Tabela: beneficios_colaboradores
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.beneficios_colaboradores'::regclass) THEN
    EXECUTE 'ALTER TABLE public.beneficios_colaboradores ENABLE ROW LEVEL SECURITY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='beneficios_colaboradores' AND policyname='perfil_restringe_leitura_beneficios_colaboradores') THEN
    EXECUTE $ddl$CREATE POLICY perfil_restringe_leitura_beneficios_colaboradores ON public.beneficios_colaboradores AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['beneficios'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())))$ddl$;
  END IF;
END $blk$;

-- Tabela: ferias_alertas
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ferias_alertas'::regclass) THEN
    EXECUTE 'ALTER TABLE public.ferias_alertas ENABLE ROW LEVEL SECURITY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ferias_alertas' AND policyname='perfil_restringe_leitura_ferias_alertas') THEN
    EXECUTE $ddl$CREATE POLICY perfil_restringe_leitura_ferias_alertas ON public.ferias_alertas AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())))$ddl$;
  END IF;
END $blk$;

-- Tabela: ferias_coletivas
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ferias_coletivas'::regclass) THEN
    EXECUTE 'ALTER TABLE public.ferias_coletivas ENABLE ROW LEVEL SECURITY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ferias_coletivas' AND policyname='perfil_restringe_leitura_ferias_coletivas') THEN
    EXECUTE $ddl$CREATE POLICY perfil_restringe_leitura_ferias_coletivas ON public.ferias_coletivas AS RESTRICTIVE FOR SELECT TO public USING (perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text]))$ddl$;
  END IF;
END $blk$;

-- Tabela: ferias_coletivas_comunicados
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ferias_coletivas_comunicados'::regclass) THEN
    EXECUTE 'ALTER TABLE public.ferias_coletivas_comunicados ENABLE ROW LEVEL SECURITY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ferias_coletivas_comunicados' AND policyname='perfil_restringe_leitura_ferias_coletivas_comunicados') THEN
    EXECUTE $ddl$CREATE POLICY perfil_restringe_leitura_ferias_coletivas_comunicados ON public.ferias_coletivas_comunicados AS RESTRICTIVE FOR SELECT TO public USING (perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text]))$ddl$;
  END IF;
END $blk$;

-- Tabela: folha_rescisoes
DO $blk$
BEGIN
  PERFORM set_config('lock_timeout', '5s', true);
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.folha_rescisoes'::regclass) THEN
    EXECUTE 'ALTER TABLE public.folha_rescisoes ENABLE ROW LEVEL SECURITY';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='folha_rescisoes' AND policyname='perfil_restringe_leitura_folha_rescisoes') THEN
    EXECUTE $ddl$CREATE POLICY perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())))$ddl$;
  END IF;
END $blk$;


-- ----------------------------------------------------------------------------
-- CONFERENCIA (unico SELECT): as 5 tabelas devem ter a politica RESTRICTIVE.
-- ----------------------------------------------------------------------------
SELECT t AS tabela,
       (EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=t
                 AND p.policyname LIKE 'perfil_restringe_leitura_%' AND p.permissive='RESTRICTIVE'))::text AS tem_politica
FROM unnest(ARRAY['beneficios_colaboradores','folha_rescisoes','ferias_alertas','ferias_coletivas','ferias_coletivas_comunicados']) AS t
ORDER BY t;
