-- ============================================================================
-- Escopo "subordinados diretos" — aplicação no módulo PONTO
--
-- O dado por pessoa do ponto vive em ponto_marcacoes (as batidas) e
-- ponto_espelhos (o espelho mensal). É nelas que entra o filtro de 3 vias:
--
--   USING (
--     perfil_amplo_sem_subordinados(tenant,'ponto','colaboradores')
--     OR <a batida é minha>
--     OR ( perfil_tem_escopo_subordinados(tenant,'ponto','colaboradores')
--          AND <a batida é de um subordinado meu> )
--   )
--
-- ponto_diario NÃO entra de propósito: é lido de forma AGREGADA por telas de
-- outros módulos (PONTO-396, 20260818150000), então a trava por pessoa foi
-- retirada dela — um recorte ali daria indicador errado em silêncio. O gestor
-- com escopo subordinados vê as batidas/espelhos só dos subordinados, mas a
-- visão agregada diária segue abrangente (não é dado pessoal detalhado).
--
-- Mudança intencional: perfil de ponto com escopo 'subordinados_diretos' passa
-- de "empresa inteira" para "próprias + dos subordinados diretos". Gestão e
-- escopos amplos seguem vendo tudo; auto-serviço (ver a própria batida)
-- preservado. Atômico: falha ao recriar reverte tudo.
-- ============================================================================

DO $rls$
DECLARE
  v_tabela text;
  c_admin   CONSTANT text := $a$public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY['ponto','colaboradores'])$a$;
  c_proprio CONSTANT text := $p$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = public.cpf_do_usuario_logado()$p$;
  c_tem_sub CONSTANT text := $s$public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ARRAY['ponto','colaboradores'])$s$;
  c_sub     CONSTANT text := $b$public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)$b$;
BEGIN
  FOREACH v_tabela IN ARRAY ARRAY['ponto_marcacoes', 'ponto_espelhos'] LOOP
    IF to_regclass('public.' || v_tabela) IS NULL THEN
      RAISE NOTICE 'Tabela % nao existe nesta base; pulada.', v_tabela;
      CONTINUE;
    END IF;

    EXECUTE format('DROP POLICY IF EXISTS perfil_restringe_leitura_%1$s ON public.%1$I', v_tabela);
    EXECUTE format(
      'CREATE POLICY perfil_restringe_leitura_%1$s ON public.%1$I '
      || 'AS RESTRICTIVE FOR SELECT TO authenticated '
      || 'USING (%2$s OR %3$s OR (%4$s AND %5$s))',
      v_tabela, c_admin, c_proprio, c_tem_sub, c_sub);
    RAISE NOTICE 'Ponto: subordinados aplicado em %.', v_tabela;
  END LOOP;
END $rls$;
