-- VALIDAÇÃO (homologação) do 2º lote: humor por setor + ouvidoria anônima.
-- Rollback por bloco (não suja o sandbox).
SET lock_timeout = '10s';
DO $$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_uidA uuid := gen_random_uuid();   -- gestor setor RH
  v_uidB uuid := gen_random_uuid();   -- pessoa do RH
  v_uidC uuid := gen_random_uuid();   -- pessoa da TI
  v_a uuid; v_perf uuid;
  v_cpfB text; v_cpfC text;
  -- humor
  v_ve_humor_B boolean; v_ve_humor_C boolean;
  -- ouvidoria
  v_ve_ouv_RH boolean; v_ve_ouv_anon boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- usuários com cadastro + cpf (p/ resolver user_id->cpf)
  v_a := public.qa_up_usuario('LOTE2', 1, '11144477735', 'ativo', v_uidA);
  PERFORM public.qa_up_usuario('LOTE2', 2, '52998224725', 'ativo', v_uidB);
  PERFORM public.qa_up_usuario('LOTE2', 3, '39053344705', 'ativo', v_uidC);
  -- admissões com departamento (setor) e cpf
  PERFORM public.qa_esc_admissao('11144477735', 'Gestor RH', NULL, 'RH');
  PERFORM public.qa_esc_admissao('52998224725', 'Pessoa RH', NULL, 'RH');
  PERFORM public.qa_esc_admissao('39053344705', 'Pessoa TI', NULL, 'TI');
  -- perfil do A: bem_estar e ouvidoria em escopo SETOR
  v_perf := public.qa_up_perfil('LOTE2', 'Setor BemEstar', 'bem_estar', 'setor', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);
  v_perf := public.qa_up_perfil('LOTE2', 'Setor Ouvidoria', 'ouvidoria', 'setor', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  -- HUMOR: predicado real (user_id -> cpf -> setor)
  v_ve_humor_B := public.perfil_ve_cpf(v_t,
      (SELECT ub.cpf FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uidB AND ub.tenant_id = v_t LIMIT 1),
      'bem_estar','psicossocial') OR (v_uidB = auth.uid());
  v_ve_humor_C := public.perfil_ve_cpf(v_t,
      (SELECT ub.cpf FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uidC AND ub.tenant_id = v_t LIMIT 1),
      'bem_estar','psicossocial') OR (v_uidC = auth.uid());
  -- OUVIDORIA: manifestação de autor do RH (visível) vs anônima (autor nulo -> NÃO visível p/ setor)
  v_ve_ouv_RH := public.perfil_ve_cpf(v_t,
      (SELECT ub.cpf FROM public.usuarios_base ub WHERE ub.auth_user_id = v_uidB AND ub.tenant_id = v_t LIMIT 1),
      'ouvidoria') OR (v_uidB = auth.uid());
  v_ve_ouv_anon := public.perfil_ve_cpf(v_t,
      (SELECT ub.cpf FROM public.usuarios_base ub WHERE ub.auth_user_id = NULL AND ub.tenant_id = v_t LIMIT 1),
      'ouvidoria');  -- autor anônimo = cpf nulo
  PERFORM public.qa_up_sair();

  RAISE NOTICE 'LOTE2 setor RH: humor_RH=% (esperado t) humor_TI=% (esperado f) | ouvidoria_autorRH=% (esperado t) ouvidoria_ANONIMA=% (esperado f)',
               v_ve_humor_B, v_ve_humor_C, v_ve_ouv_RH, v_ve_ouv_anon;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM public.qa_up_sair(); EXCEPTION WHEN OTHERS THEN NULL; END;
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'LOTE2 teste ERRO: %', SQLERRM; END IF;
END $$;
