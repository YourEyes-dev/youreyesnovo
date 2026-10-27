-- VALIDAÇÃO (homologação): proprio_usuario na Ouvidoria NÃO vê manifestação de outro,
-- mesmo com papel de gestão (manager). Avalia o predicado real da política sob o
-- usuário logado. Rollback por bloco (não suja o sandbox).
SET lock_timeout = '10s';
DO $$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_uidA uuid := gen_random_uuid();
  v_uidB uuid := gen_random_uuid();
  v_a uuid; v_perf uuid;
  v_permite boolean; v_ve_outro boolean; v_ve_propria boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('OUVTEST', 1, '11144477735', 'ativo', v_uidA);
  INSERT INTO public.user_roles(user_id, role) VALUES (v_uidA, 'manager') ON CONFLICT DO NOTHING;
  v_perf := public.qa_up_perfil('OUVTEST', 'Ouvidoria Proprio', 'ouvidoria', 'proprio_usuario', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_permite    := public.perfil_permite_modulo(v_t, VARIADIC ARRAY['ouvidoria'::text]);
  -- Manifestação de OUTRO: autor_id = uidB, sem responsavel/respondido
  v_ve_outro   := v_permite OR (v_uidB = auth.uid());
  -- Própria: autor_id = uidA
  v_ve_propria := v_permite OR (v_uidA = auth.uid());
  PERFORM public.qa_up_sair();

  RAISE NOTICE 'OUVIDORIA proprio_usuario (c/ papel manager): permite_modulo=% | ve_manifestacao_de_OUTRO=% | ve_PROPRIA=%',
               v_permite, v_ve_outro, v_ve_propria;
  RAISE EXCEPTION 'ROLLBACK_ME';
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM public.qa_up_sair(); EXCEPTION WHEN OTHERS THEN NULL; END;
  IF SQLERRM <> 'ROLLBACK_ME' THEN RAISE NOTICE 'OUVIDORIA teste ERRO: %', SQLERRM; END IF;
END $$;
