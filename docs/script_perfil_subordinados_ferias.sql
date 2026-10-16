-- ============================================================================
-- ENTREGA — Escopo "subordinados diretos" · modulo FERIAS
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_escopo_subordinados_fundacao.sql) ja deve ter sido aplicado
-- nesta base (cria as funcoes ye_* / perfil_amplo_sem_subordinados /
-- perfil_tem_escopo_subordinados). Sem elas, este script falha ao criar as
-- politicas — e, por ser atomico, nao aplica nada (seguro).
--
-- Roda em UMA transacao. Reescreve as politicas RESTRICTIVE das tabelas
-- PESSOAIS de ferias para o desenho de 3 vias (amplo OU proprio OU
-- (tem escopo subordinados E a linha e de um subordinado meu)). Nao mexe em
-- ferias_coletivas / _comunicados (organizacionais).
--
-- Mudanca de comportamento (intencional): perfil de ferias com escopo
-- 'subordinados_diretos' passa de "empresa inteira" para "proprios + dos
-- subordinados diretos". Gestao (manager/administrador/gestor) e escopos amplos
-- (empresa inteira, setor, unidade...) seguem vendo tudo. O gestor VE os
-- valores/salario das fichas dos subordinados.
--
-- OBS de editor: NAO cria tabela (so recria politicas), entao o auto-RLS do
-- editor nao e acionado. Nao altera nem apaga dado — so politicas de leitura.
-- E atomico: se uma politica falhar, o editor desfaz tudo e as politicas atuais
-- permanecem intactas.
-- ============================================================================

DO $rls$
DECLARE
  r record;
  c_admin   CONSTANT text := $a$public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY['ferias','colaboradores'])$a$;
  c_tem_sub CONSTANT text := $s$public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ARRAY['ferias','colaboradores'])$s$;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ferias_periodos_aquisitivos', 'perfil_restringe_leitura_ferias_periodos',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('ferias_programacao', 'perfil_restringe_leitura_ferias_programacao',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('ferias_solicitacoes', 'perfil_restringe_leitura_ferias_solicitacoes',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('folha_ferias_calculo', 'perfil_restringe_leitura_folha_ferias_calculo',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('ferias_assinatura_links', 'perfil_restringe_leitura_ferias_assinatura',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('ferias_alertas', 'perfil_restringe_leitura_ferias_alertas',
       $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$),

      ('ferias_historico', 'perfil_restringe_leitura_ferias_historico',
       $p$EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                   WHERE s.id = ferias_historico.solicitacao_id
                     AND regexp_replace(COALESCE(s.colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado())$p$,
       $b$EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                   WHERE s.id = ferias_historico.solicitacao_id
                     AND public.ye_cpf_eh_subordinado_direto(ferias_historico.tenant_id, s.colaborador_cpf))$b$),

      ('ferias_vinculo_familiar', 'perfil_restringe_leitura_ferias_vinculo_familiar',
       $p$public.cpf_do_usuario_logado() IN (
            regexp_replace(COALESCE(cpf_a,''),'[^0-9]','','g'),
            regexp_replace(COALESCE(cpf_b,''),'[^0-9]','','g'))$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, cpf_a)
          OR public.ye_cpf_eh_subordinado_direto(tenant_id, cpf_b)$b$)
    ) AS t(tabela, politica, predicado_proprio, predicado_sub)
  LOOP
    IF to_regclass('public.' || r.tabela) IS NULL THEN
      RAISE NOTICE 'Tabela % nao existe nesta base; pulada.', r.tabela;
      CONTINUE;
    END IF;

    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.politica, r.tabela);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated '
      || 'USING (%s OR %s OR (%s AND (%s)))',
      r.politica, r.tabela, c_admin, r.predicado_proprio, c_tem_sub, r.predicado_sub);
    RAISE NOTICE 'Ferias: subordinados aplicado em %.', r.tabela;
  END LOOP;
END $rls$;

-- ── Conferencia: quantas politicas de ferias ja citam o motor de subordinados ─
SELECT count(*) AS politicas_ferias_com_subordinados
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname LIKE 'perfil_restringe_leitura_ferias_%'
   AND qual LIKE '%ye_cpf_eh_subordinado_direto%';
