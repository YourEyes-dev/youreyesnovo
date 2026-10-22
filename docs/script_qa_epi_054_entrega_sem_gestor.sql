-- ============================================================================
-- ENTREGA — QA do EPI: caso EPI-054 (entrega sem papel de gestor) e sua rotina
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE depois do script
-- script_epi_fix_movimentacao_por_rotina_de_sistema.sql. Só documenta o caso e
-- cria a rotina (que cria e apaga um usuário e um perfil de teste no sandbox);
-- não altera comportamento nem dado de cliente. UMA transação, idempotente.
-- ============================================================================

-- =========================================================
-- QA — EPI-054: quem tem perfil para entregar EPI consegue entregar e devolver,
-- mesmo sem o papel de gestor.
--
-- O defeito, achado na primeira entrega ponta a ponta no staging: as políticas
-- de epi_entregas aceitam quem tem perfil de "criar" no módulo (o vínculo de
-- empresa é verdadeiro quando a entrega não tem empresa), mas a política de
-- epi_movimentacoes aceita SÓ quem tem o papel de gestor. O wizard antigo
-- ignorava o erro do registro de movimentação (nunca verificava o resultado) e
-- a entrega concluía sem ele; epi_registrar_entrega, que é atômica, propaga o
-- erro e derruba a entrega inteira com "new row violates row-level security
-- policy". Quem entrega por perfil, como o Super Admin do teste, fica sem
-- conseguir entregar.
--
-- A rotina cria um usuário com perfil de "criar" e "editar" no módulo EPI (sem papel de
-- gestor), age COMO esse usuário (papel authenticated) e exige: entrega com
-- local, movimentação registrada, devolução com descarte e saldo correto.
--
-- Só documenta e liga o teste; não altera comportamento. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi');
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-ocupacional/epi não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'EPI-054',
   'Quem tem perfil para entregar EPI entrega e devolve, mesmo sem o papel de gestor',
   'negativo', 'alta', 'aprovado', 'api',
   'NR-6 (fornecimento e registro do EPI); Documento YE-DP-EPI-001 (perfis de acesso por módulo)',
   'O acesso ao módulo EPI é dado por perfil. Quem pode entregar pela tela precisa conseguir concluir a entrega e a devolução, com a movimentação de estoque registrada, sem depender de um papel de gestor que o perfil não concede.',
   'Sandbox QA com um usuário com perfil de criar e editar no módulo EPI, sem papel de gestor.',
   '[{"ordem":1,"acao":"Entregar um EPI escolhendo o local de estoque, como esse usuário","resultado_esperado":"Entrega concluída, saldo global e do local baixados, uma movimentação de saída registrada"},
     {"ordem":2,"acao":"Devolver a entrega para descarte, como esse usuário","resultado_esperado":"Devolução concluída; o saldo não volta; movimentações de devolução e de descarte registradas"},
     {"ordem":3,"acao":"Chamar direto as rotinas de sistema do histórico, sem entrega ou devolução recente","resultado_esperado":"Recusado: não dá para gravar histórico solto"}]'::jsonb,
   'A entrega e a devolução funcionam para quem tem perfil, sem exigir papel de gestor, e deixam as movimentações.',
   'Guarda a correção do registro de movimentação por rotina de sistema. O usuário da rotina vem das fixtures qa_up_*.')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_054()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_u uuid; v_p uuid; v_uid uuid; v_tipo uuid; v_epi uuid; v_loc uuid; v_ent uuid;
        v_err_entrega text; v_err_devolucao text;
        v_global int; v_local int; v_movs int; v_papel_gestor boolean; v_err_forja text; v_err_forja2 text; v_epi_outro uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_fixture_limpar('EPI054');
  DELETE FROM public.perfis_acesso WHERE tenant_id = v_t AND nome LIKE '[QA-EPI054]%';

  r.passo_ordem := 1;
  r.passo_acao := 'Criar um usuário só com perfil de criar no módulo EPI e preparar o estoque';
  r.esperado := 'Usuário sem papel de gestor, com identidade de autenticação';
  v_u := public.qa_up_usuario('EPI054', 1, public.qa_cpf(54), 'ativo');
  v_p := public.qa_up_perfil('EPI054', 'Entrega EPI', 'epi', 'empresa_inteira', 'criar');
  -- Devolver é uma atualização da entrega: a política de UPDATE exige o perfil
  -- "editar" (a de INSERT, "criar"). O usuário tem os dois, como um técnico de
  -- segurança; o que NÃO tem é o papel de gestor.
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_p, v_t, 'epi', 'editar'::public.perfil_acao, 'empresa_inteira'::public.perfil_escopo_tipo, true);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  v_uid := (SELECT auth_user_id FROM public.usuarios_base WHERE id = v_u);
  IF NOT public.qa_up_tem_identidade(v_uid) THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'O motor não conseguiu criar a identidade de autenticação do usuário sintético neste ambiente.';
    PERFORM public.qa_fixture_limpar('EPI054');
    DELETE FROM public.perfis_acesso WHERE tenant_id = v_t AND nome LIKE '[QA-EPI054]%';
    RETURN r;
  END IF;
  v_papel_gestor := public.has_minimum_role(v_uid, 'manager'::public.app_role);

  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active, periodicidade_troca_dias)
  VALUES (v_t, 'QA — Luva sem gestor', '99054', CURRENT_DATE + 365, true, 180) RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-054', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-054B', 10, CURRENT_DATE + 365) RETURNING id INTO v_epi_outro;
  INSERT INTO public.epi_locais_estoque (tenant_id, nome) VALUES (v_t, 'QA — Almox 054') RETURNING id INTO v_loc;
  INSERT INTO public.epi_estoque_local (tenant_id, epi_id, local_estoque_id, quantidade, tamanho)
  VALUES (v_t, v_epi, v_loc, 10, '');

  r.passo_ordem := 2;
  r.passo_acao := 'Como esse usuário: entregar com local e devolver para descarte';
  r.esperado := 'Entrega e devolução concluídas, com as movimentações registradas';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    v_ent := (public.epi_registrar_entrega(jsonb_build_object(
      'tenant_id', v_t, 'epi_id', v_epi, 'colaborador_nome', 'QA Colaborador 054',
      'colaborador_cpf', public.qa_cpf(54), 'quantidade', 2, 'data_entrega', CURRENT_DATE,
      'status', 'ativa', 'assinatura_url', 'qa/a.png', 'signed_at', now()), v_loc)->>'id')::uuid;
  EXCEPTION WHEN OTHERS THEN v_err_entrega := SQLERRM;
  END;
  IF v_ent IS NOT NULL THEN
    BEGIN
      PERFORM public.epi_devolver_entrega(v_ent, 'descarte', 'QA');
    EXCEPTION WHEN OTHERS THEN v_err_devolucao := SQLERRM;
    END;
  END IF;
  -- Forjar histórico chamando as rotinas de sistema direto, sem operação recente.
  BEGIN
    PERFORM public.epi_registrar_movimentacao(v_t, v_epi_outro, 'saida', 'entrega', NULL, 5, 8, 3,
                                              'Movimento forjado', NULL, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN v_err_forja := SQLERRM;
  END;
  BEGIN
    PERFORM public.epi_baixar_saldo_descarte(v_t, v_epi_outro, 1);
  EXCEPTION WHEN OTHERS THEN v_err_forja2 := SQLERRM;
  END;
  EXECUTE 'RESET ROLE';

  v_global := (SELECT quantidade_estoque FROM public.epis WHERE id = v_epi);
  v_local  := (SELECT quantidade FROM public.epi_estoque_local WHERE epi_id = v_epi AND local_estoque_id = v_loc);
  v_movs   := (SELECT count(*) FROM public.epi_movimentacoes WHERE epi_id = v_epi);
  v_movs   := v_movs + (SELECT count(*) FROM public.epi_movimentacoes WHERE epi_id = v_epi_outro);
  PERFORM public.qa_fixture_limpar('EPI054');
  DELETE FROM public.perfis_acesso WHERE tenant_id = v_t AND nome LIKE '[QA-EPI054]%';

  IF v_papel_gestor THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'O usuário sintético tem papel de gestor neste ambiente; o teste não prova o caso.';
  ELSIF v_err_entrega IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: quem tem perfil de criar no módulo EPI, sem papel de gestor, não consegue entregar: %s', v_err_entrega);
  ELSIF v_err_forja IS NULL OR v_err_forja2 IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('As rotinas de sistema aceitaram uma chamada direta sem operação recente (movimentação: %s; descarte: %s); isso deixaria qualquer usuário com perfil gravar histórico de estoque.',
                       COALESCE(v_err_forja, 'ACEITA'), COALESCE(v_err_forja2, 'ACEITA'));
  ELSIF v_err_devolucao IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('A entrega passou, mas a devolução para descarte falhou para esse usuário: %s', v_err_devolucao);
  ELSIF v_global <> 8 OR v_local <> 8 OR v_movs <> 3 THEN
    r.situacao := 'falhou';
    r.obtido := format('Saldos ou movimentações incorretos: global %s (esperado 8), local %s (esperado 8), movimentações %s (esperado 3: saída da entrega, entrada da devolução e saída do descarte).',
                       v_global, v_local, v_movs);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Usuário só com perfil (sem papel de gestor) entregou com local e devolveu para descarte (global 8, local 8, 3 movimentações) e não conseguiu forjar histórico chamando as rotinas de sistema direto.';
  END IF;
  r.detalhe := jsonb_build_object('erro_entrega', v_err_entrega, 'erro_devolucao', v_err_devolucao, 'forja_movimentacao', v_err_forja, 'forja_descarte', v_err_forja2,
                                  'global', v_global, 'local', v_local, 'movimentacoes', v_movs);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN EXECUTE 'RESET ROLE'; EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-054', 'qa_caso_epi_054')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'EPI-054') AS caso_documentado,
  EXISTS (SELECT 1 FROM public.qa_implementacoes WHERE codigo = 'EPI-054'
           AND funcao_sql = 'qa_caso_epi_054') AS rotina_registrada,
  (SELECT count(*) FROM pg_proc WHERE proname = 'qa_caso_epi_054') AS funcao_criada,
  NULL::text AS erro_tecnico;

-- Para desfazer:
--   DELETE FROM public.qa_implementacoes WHERE codigo = 'EPI-054';
--   DROP FUNCTION IF EXISTS public.qa_caso_epi_054();
--   DELETE FROM public.qa_casos_teste WHERE codigo = 'EPI-054';
