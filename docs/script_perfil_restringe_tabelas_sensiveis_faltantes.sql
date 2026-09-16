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
-- IMPORTANTE (mudanca de acesso): a politica RESTRINGE a leitura. Quem JA passa
-- hoje continua passando -- superadmin, gestor/manager para cima, tipo
-- administrador/gestor, ou perfil com o modulo em escopo amplo, e o proprio
-- titular (mesmo CPF). So deixa de ver quem NAO tem nenhum desses. E o
-- comportamento correto da camada de perfil, mas e uma mudanca de acesso:
-- aplicar na HOMOLOGACAO, conferir as telas de Beneficios/Rescisoes/Ferias com
-- um perfil restrito e com um gestor, e SO ENTAO levar a producao.
--
-- Idempotente (DROP POLICY IF EXISTS + CREATE). Nao altera dado; so politica.
-- ============================================================================

ALTER TABLE public.beneficios_colaboradores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_beneficios_colaboradores ON public.beneficios_colaboradores;
CREATE POLICY perfil_restringe_leitura_beneficios_colaboradores ON public.beneficios_colaboradores AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['beneficios'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())));

ALTER TABLE public.ferias_alertas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_ferias_alertas ON public.ferias_alertas;
CREATE POLICY perfil_restringe_leitura_ferias_alertas ON public.ferias_alertas AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())));

ALTER TABLE public.ferias_coletivas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_ferias_coletivas ON public.ferias_coletivas;
CREATE POLICY perfil_restringe_leitura_ferias_coletivas ON public.ferias_coletivas AS RESTRICTIVE FOR SELECT TO public USING (perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text]));

ALTER TABLE public.ferias_coletivas_comunicados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_ferias_coletivas_comunicados ON public.ferias_coletivas_comunicados;
CREATE POLICY perfil_restringe_leitura_ferias_coletivas_comunicados ON public.ferias_coletivas_comunicados AS RESTRICTIVE FOR SELECT TO public USING (perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ferias'::text]));

ALTER TABLE public.folha_rescisoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes;
CREATE POLICY perfil_restringe_leitura_folha_rescisoes ON public.folha_rescisoes AS RESTRICTIVE FOR SELECT TO public USING ((perfil_permite_modulo(tenant_id, VARIADIC ARRAY['financeiro'::text, 'colaboradores'::text]) OR (regexp_replace(COALESCE(colaborador_cpf, ''::text), '[^0-9]'::text, ''::text, 'g'::text) = cpf_do_usuario_logado())));


-- ----------------------------------------------------------------------------
-- CONFERENCIA (unico SELECT): as 5 tabelas devem ter a politica RESTRICTIVE.
-- ----------------------------------------------------------------------------
SELECT t AS tabela,
       (EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=t
                 AND p.policyname LIKE 'perfil_restringe_leitura_%' AND p.permissive='RESTRICTIVE'))::text AS tem_politica
FROM unnest(ARRAY['beneficios_colaboradores','folha_rescisoes','ferias_alertas','ferias_coletivas','ferias_coletivas_comunicados']) AS t
ORDER BY t;
