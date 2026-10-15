-- ============================================================================
-- ENTREGA — Escopo "subordinados diretos" · modulo PONTO
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_escopo_subordinados_fundacao.sql) ja aplicado nesta base.
--
-- Roda em UMA transacao. Reescreve as politicas RESTRICTIVE de ponto_marcacoes
-- e ponto_espelhos (o dado por pessoa do ponto) para o desenho de 3 vias
-- (amplo OU proprio OU (tem escopo subordinados E a batida e de subordinado)).
--
-- ponto_diario NAO entra: e lido de forma AGREGADA por telas de outros modulos
-- (a trava por pessoa foi retirada dela de proposito, PONTO-396). O gestor com
-- escopo subordinados ve as batidas/espelhos so dos subordinados; a visao
-- agregada diaria segue abrangente (nao e dado pessoal detalhado).
--
-- Mudanca intencional: perfil de ponto com escopo 'subordinados_diretos' passa
-- de "empresa inteira" para "proprias + dos subordinados diretos". Gestao e
-- escopos amplos seguem vendo tudo; auto-servico (ver a propria batida)
-- preservado.
--
-- OBS de editor: NAO cria tabela (so recria politicas) -> sem auto-RLS. Nao
-- altera nem apaga dado. Atomico: se falhar, o editor desfaz tudo e as
-- politicas atuais permanecem.
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

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT count(*) AS politicas_ponto_com_subordinados
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname IN ('perfil_restringe_leitura_ponto_marcacoes',
                      'perfil_restringe_leitura_ponto_espelhos')
   AND qual LIKE '%ye_cpf_eh_subordinado_direto%';
