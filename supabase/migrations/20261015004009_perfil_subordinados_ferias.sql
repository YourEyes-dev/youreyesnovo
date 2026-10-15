-- ============================================================================
-- Escopo "subordinados diretos" — aplicação no módulo FÉRIAS
--
-- Primeiro filtro REAL do escopo subordinados. Reescreve as políticas
-- RESTRICTIVE das tabelas pessoais de férias para o desenho de 3 vias:
--
--   USING (
--     perfil_amplo_sem_subordinados(tenant, 'ferias','colaboradores')   -- admin/empresa inteira
--     OR <a linha é minha>                                              -- próprio usuário
--     OR ( perfil_tem_escopo_subordinados(tenant,'ferias','colaboradores')
--          AND <a linha é de um subordinado meu> )                      -- subordinados diretos
--   )
--
-- Mudança de comportamento (intencional): quem tem o perfil de férias com
-- escopo 'subordinados_diretos' passa de "vê a empresa inteira" para "vê os
-- próprios + os dos subordinados diretos". Quem tem escopo amplo (empresa
-- inteira, setor, unidade…) e gestão (manager/administrador/gestor) segue vendo
-- tudo — perfil_amplo_sem_subordinados só EXCLUI o tier subordinados do que
-- conta como amplo. O gestor VÊ os valores/salário das fichas de férias dos
-- subordinados (decisão do dono do produto).
--
-- NÃO mexe em ferias_coletivas / ferias_coletivas_comunicados: são
-- organizacionais (evento por empresa/departamento, sem pessoa), seguem por
-- módulo (perfil_permite_modulo) — um gestor segue enxergando o coletivo.
--
-- Atômico de propósito: se qualquer política falhar ao recriar, a migration
-- inteira reverte (db push falha visível) e NENHUMA tabela fica sem camada —
-- mais seguro, para dado sensível, que aplicar pela metade.
-- ============================================================================

DO $rls$
DECLARE
  r record;
  c_admin   CONSTANT text := $a$public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY['ferias','colaboradores'])$a$;
  c_tem_sub CONSTANT text := $s$public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ARRAY['ferias','colaboradores'])$s$;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- Tabelas com colaborador_cpf direto
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

      -- Histórico: dono via a solicitação de origem (não tem CPF próprio)
      ('ferias_historico', 'perfil_restringe_leitura_ferias_historico',
       $p$EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                   WHERE s.id = ferias_historico.solicitacao_id
                     AND regexp_replace(COALESCE(s.colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado())$p$,
       $b$EXISTS (SELECT 1 FROM public.ferias_solicitacoes s
                   WHERE s.id = ferias_historico.solicitacao_id
                     AND public.ye_cpf_eh_subordinado_direto(ferias_historico.tenant_id, s.colaborador_cpf))$b$),

      -- Vínculo familiar: liga duas pessoas por CPF; cada uma vê os pares de que
      -- participa; o gestor vê os pares em que um subordinado participa.
      ('ferias_vinculo_familiar', 'perfil_restringe_leitura_ferias_vinculo_familiar',
       $p$public.cpf_do_usuario_logado() IN (
            regexp_replace(COALESCE(cpf_a,''),'[^0-9]','','g'),
            regexp_replace(COALESCE(cpf_b,''),'[^0-9]','','g'))$p$,
       $b$public.ye_cpf_eh_subordinado_direto(tenant_id, cpf_a)
          OR public.ye_cpf_eh_subordinado_direto(tenant_id, cpf_b)$b$)
    ) AS t(tabela, politica, predicado_proprio, predicado_sub)
  LOOP
    -- Tabela ausente (base parcial): pula sem erro.
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
