-- ============================================================================
-- ENTREGA — Perfil "pode ver salário" · FOLHA (esconde o registro)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
-- PRE-REQUISITO: o script da FUNDACAO
-- (script_perfil_pode_ver_salario_fundacao.sql) ja aplicado nesta base.
--
-- Roda em UMA transacao. Adiciona uma politica RESTRICTIVE NOVA por tabela de
-- folha (ANDada com as que ja existem):
--   USING ( public.pode_ver_salario(tenant_id) OR <e o proprio colaborador> )
-- Resultado: perfil sem "pode ver salario" so ve o PROPRIO holerite; com a flag
-- (ou dono/superadmin), como antes. Nao altera dado; so leitura. Atomico.
--
-- O "proprio colaborador" so entra onde ha colaborador_cpf; nas agregadas
-- (periodos, lotes) a trava e so pela flag.
--
-- OBS de editor: NAO cria tabela -> sem auto-RLS. Nao altera nem apaga dado.
-- ============================================================================

DO $rls$
DECLARE
  v_tabela text;
  v_tem_cpf boolean;
  v_using text;
BEGIN
  FOREACH v_tabela IN ARRAY ARRAY[
    'folha_itens', 'folha_rescisoes', 'folha_13_calculo', 'folha_ferias_calculo',
    'folha_provisoes', 'folha_memoria_calculo', 'folha_lancamentos',
    'folha_periodos', 'folha_lotes'
  ] LOOP
    IF to_regclass('public.' || v_tabela) IS NULL THEN
      RAISE NOTICE 'Tabela % nao existe nesta base; pulada.', v_tabela;
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = v_tabela
         AND column_name = 'colaborador_cpf'
    ) INTO v_tem_cpf;

    v_using := $using$public.pode_ver_salario(tenant_id)$using$;
    IF v_tem_cpf THEN
      v_using := v_using || $using$ OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()$using$;
    END IF;

    EXECUTE format('DROP POLICY IF EXISTS perfil_restringe_salario_%1$s ON public.%1$I', v_tabela);
    EXECUTE format(
      'CREATE POLICY perfil_restringe_salario_%1$s ON public.%1$I '
      || 'AS RESTRICTIVE FOR SELECT TO authenticated USING (%2$s)',
      v_tabela, v_using);
    RAISE NOTICE 'Folha: trava de salario aplicada em %.', v_tabela;
  END LOOP;
END $rls$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT count(*) AS tabelas_folha_com_trava_salario
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname LIKE 'perfil_restringe_salario_folha_%';
