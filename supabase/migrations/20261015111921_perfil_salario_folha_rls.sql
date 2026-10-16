-- ============================================================================
-- Perfil "pode ver salário" — FOLHA (esconde o registro de quem não pode)
--
-- Primeira fatia EFETIVA da flag pode_ver_salario. Decisão do dono do produto:
-- nas telas de folha/holerite/rescisão/13º/provisões, quem NÃO pode ver salário
-- não enxerga o registro (esses registros são, na prática, o próprio salário).
--
-- Mecanismo: uma política RESTRICTIVE NOVA por tabela
--   USING ( public.pode_ver_salario(tenant_id) OR <é o próprio colaborador> )
-- que é ANDada com as políticas que já existem (ex.: a de módulo
-- financeiro/colaboradores em folha_itens/folha_rescisoes). Resultado:
--   - perfil sem "pode ver salário": só vê o PRÓPRIO holerite (auto-serviço);
--   - perfil com "pode ver salário" (ou dono/superadmin): como antes.
-- Não altera dado; só leitura. Atômico.
--
-- O "próprio colaborador" só entra nas tabelas que têm colaborador_cpf; nas
-- agregadas (períodos, lotes) a trava é só pela flag.
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
