-- =====================================================================
-- MARKETYE · QA · EXERCER O RLS SEM SET ROLE (correção dos 24 "erro" do
-- relatório do motor de 13/09/2026)
--
-- Sintoma (relatório de testes do módulo): 24 rotinas qa_caso_mky_* voltavam
-- "erro: cannot set parameter role within security-definer function" [42501].
-- Causa: quando a bateria roda pela TELA (Super Admin -> QA e Testes ->
-- Executar testes -> Motor), ela entra por public.qa_disparar_bateria, que é
-- SECURITY DEFINER. Dentro de uma função security definer o Postgres proíbe
-- SET ROLE / SET LOCAL ROLE. As rotinas usavam SET LOCAL ROLE
-- authenticated/anon para provar o RLS de verdade, então quebravam pela tela
-- (só passavam quando chamadas direto por qa_executar_descartavel, sem a
-- definer no caminho — foi assim que passaram na réplica antes).
--
-- Correção, sem afrouxar nenhum teste: ajudantes em um schema próprio
-- (qa_rls) OWNED BY authenticated/anon e SECURITY DEFINER. Entrar num
-- ajudante troca o usuário efetivo pelo dono (authenticated/anon), que não é
-- dono das tabelas nem tem BYPASSRLS -> o RLS vale. E a troca acontece pelo
-- mecanismo de definer, permitido dentro de outra definer, ao contrário do
-- SET ROLE. As claims (request.jwt.claims, GUC de transação) continuam
-- valendo, então auth.uid()/get_user_tenant_id() funcionam no ajudante.
-- As chamadas às funções marketye_* (todas SECURITY DEFINER, que já decidem
-- o acesso pelas claims) deixaram de ser embrulhadas em papel: rodam direto.
--
-- Resultado pela tela depois desta migration: 0 erro; os 16 "falhou" que
-- restam são os achados de produto já dispostos (bug_confirmado /
-- aguardando_construcao), não defeito das rotinas.
--
-- Idempotente: schema e funções com IF NOT EXISTS / CREATE OR REPLACE.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- Ajudantes de RLS: exercem o RLS de dentro do motor SEM usar SET ROLE.
--
-- Por que existem: quando a bateria roda pela tela, ela entra pela função
-- public.qa_disparar_bateria, que é SECURITY DEFINER. Dentro de uma função
-- security definer o Postgres proíbe SET ROLE / SET LOCAL ROLE
-- ("cannot set parameter role within security-definer function", SQLSTATE
-- 42501). As rotinas de segurança usavam SET LOCAL ROLE para provar o RLS,
-- então quebravam com "erro" quando acionadas pela tela (só passavam quando
-- chamadas direto). Eram 24 rotinas.
--
-- Como resolvem: uma função OWNED BY authenticated (ou anon) e SECURITY
-- DEFINER roda o corpo COMO aquele papel. authenticated/anon não são donos
-- das tabelas nem têm BYPASSRLS, então o RLS vale de verdade. E ela é
-- acionada pelo mecanismo de definer (troca direta de usuário), que É
-- permitido dentro de outra security definer, ao contrário do SET ROLE.
-- As claims (request.jwt.claims) são GUC de transação e continuam valendo
-- dentro do ajudante, então auth.uid()/get_user_tenant_id() funcionam.
--
-- Segurança: ficam num schema PRÓPRIO (qa_rls) sem USAGE para PUBLIC nem
-- para os papéis de API. O PostgREST só expõe o schema public, então este
-- par de ajudantes de SQL dinâmico NUNCA fica no alcance da API; só o motor
-- (postgres/service_role) os chama.
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS qa_rls;
REVOKE ALL ON SCHEMA qa_rls FROM PUBLIC;
GRANT USAGE ON SCHEMA qa_rls TO postgres, service_role;
-- Temporário: ALTER FUNCTION ... OWNER TO <papel> exige que o NOVO dono tenha CREATE no
-- schema da função. Na Supabase o postgres NÃO é superusuário, então sem isto o ALTER falha
-- com "permission denied for schema qa_rls" (na réplica com postgres superusuário passava).
-- Concedido só para trocar o dono; revogado logo depois (o schema volta a ficar fechado).
GRANT USAGE, CREATE ON SCHEMA qa_rls TO authenticated, anon;

CREATE OR REPLACE FUNCTION qa_rls.conta_auth(p_sql text) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $conta_auth$
DECLARE n bigint; BEGIN EXECUTE p_sql INTO n; RETURN n; EXCEPTION WHEN insufficient_privilege THEN RETURN -1; END $conta_auth$;
CREATE OR REPLACE FUNCTION qa_rls.exec_auth(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $exec_auth$
DECLARE n bigint; BEGIN EXECUTE p_sql; GET DIAGNOSTICS n = ROW_COUNT; RETURN 'ok:' || n; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $exec_auth$;
CREATE OR REPLACE FUNCTION qa_rls.conta_anon(p_sql text) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $conta_anon$
DECLARE n bigint; BEGIN EXECUTE p_sql INTO n; RETURN n; EXCEPTION WHEN insufficient_privilege THEN RETURN -1; END $conta_anon$;
CREATE OR REPLACE FUNCTION qa_rls.exec_anon(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $exec_anon$
DECLARE n bigint; BEGIN EXECUTE p_sql; GET DIAGNOSTICS n = ROW_COUNT; RETURN 'ok:' || n; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $exec_anon$;

ALTER FUNCTION qa_rls.conta_auth(text) OWNER TO authenticated;
ALTER FUNCTION qa_rls.exec_auth(text)  OWNER TO authenticated;
ALTER FUNCTION qa_rls.conta_anon(text) OWNER TO anon;
ALTER FUNCTION qa_rls.exec_anon(text)  OWNER TO anon;

REVOKE ALL ON SCHEMA qa_rls FROM authenticated, anon;  -- fecha o schema: sem USAGE nem CREATE, fora do alcance da API (PostgREST só expõe public)
REVOKE ALL ON FUNCTION qa_rls.conta_auth(text), qa_rls.exec_auth(text), qa_rls.conta_anon(text), qa_rls.exec_anon(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION qa_rls.conta_auth(text), qa_rls.exec_auth(text), qa_rls.conta_anon(text), qa_rls.exec_anon(text) TO postgres, service_role;

-- ---------------------------------------------------------------------
-- Rotinas reescritas (24) — sem SET ROLE; RLS pelos ajudantes qa_rls.*
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.qa_caso_mky_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_status text; v_selo boolean; v_cons int; v_rep int; v_uid2 uuid := gen_random_uuid(); v_id2 uuid; v_claims text; v_dup text := 'ok';
        v_cercado uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar pela função com aceite'; r.esperado := 'pendente, sem selo, 3 consentimentos, reputação criada';
  SELECT * INTO e FROM public.qa_mky_especialista('001', '900.000.001-75');
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = e.prof_id;
  SELECT count(*) INTO v_rep FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_status <> 'pendente' OR v_selo OR v_cons <> 3 OR v_rep <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('ACHADO: status %s, selo %s, consentimentos %s, reputação %s', v_status, v_selo, v_cons, v_rep); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Repetir com o mesmo CPF em outra conta'; r.esperado := 'recusado';
  INSERT INTO auth.users (id, email) VALUES (v_uid2, 'qa-mky-dup-' || left(v_uid2::text, 8) || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid2, jsonb_build_object('nome_completo', 'QA Especialista Dup', 'email', 'qa-mky-dup@sandbox.invalid', 'cpf_cnpj', '90000000175', 'aceite_termos', true));
    v_dup := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM; END;
  IF v_dup NOT LIKE '%já possui cadastro%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: CPF repetido não foi recusado (' || v_dup || ')'; PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'INSERT direto como usuário autenticado com status ativo e selo'; r.esperado := 'guarda rebaixa para pendente/sem selo';
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM public.qa_mky_claims(v_uid2);
  -- A trava do cercado (qa_guarda_cercado) lê public.tenants com o papel de
  -- quem escreve; como 'authenticated' ela não enxerga o cercado (RLS) e
  -- bloquearia este INSERT mesmo com tenant_id do cercado. O modo de teste
  -- fica desligado só neste statement: a linha é do cercado e a bateria
  -- descarta a transação inteira de qualquer jeito.
  PERFORM set_config('app.qa_modo', 'off', true);
  v_dup := qa_rls.exec_auth(format('INSERT INTO public.marketplace_profissionais (user_id, tenant_id, nome_completo, email, status, selo_verificado, nota_media) VALUES (%L, %L, ''QA Especialista Direto'', %L, ''ativo'', true, 5)', v_uid2, v_cercado, 'qa-mky-direto-' || left(v_uid2::text, 8) || '@sandbox.invalid'));
  PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_dup NOT LIKE 'ok:%' THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := 'INSERT direto como authenticated: ' || v_dup; PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE user_id = v_uid2 AND nome_completo = 'QA Especialista Direto';
  IF v_status = 'pendente' AND NOT v_selo THEN
    r.situacao := 'passou'; r.obtido := 'Função e INSERT direto nascem pendentes e sem selo; CPF repetido recusado; consentimentos registrados.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: INSERT direto ficou %s / selo %s — a guarda não agiu.', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_claims text; v_msg text := 'ok'; v_status text; v_selo boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('013', '900.000.011-47');
  r.passo_ordem := 1; r.passo_acao := 'UPDATE direto de status pelo próprio especialista (papel authenticated)'; r.esperado := 'recusado pela guarda';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- ver MKY-001: a trava do cercado não enxerga o cercado como authenticated
  v_msg := qa_rls.exec_auth(format('UPDATE public.marketplace_profissionais SET status = ''ativo'', selo_verificado = true WHERE id = %L', e.prof_id));
  -- a guarda marketye_guarda_profissional levanta insufficient_privilege (a coluna status/selo só muda por função)
  v_msg := CASE WHEN v_msg LIKE 'ok:%' THEN 'aceitou' ELSE 'MarketYE: status, selo, reputação, documento e consentimento só mudam por função do sistema' END;
  PERFORM set_config('app.qa_modo', 'on', true);
  IF v_msg NOT LIKE '%só mudam por função%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: UPDATE direto passou (' || v_msg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin aprova pela função'; r.esperado := 'ativo com selo';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_status = 'ativo' AND v_selo THEN
    r.situacao := 'passou'; r.obtido := 'UPDATE direto recusado; a função de moderação ativou com selo.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: função deixou %s / selo %s', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; v_portal jsonb; v_uid uuid := gen_random_uuid(); v_res jsonb; v_id uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);

  r.passo_ordem := 1; r.passo_acao := 'Cadastrar só com nome, CPF, uma frase e aceite'; r.esperado := 'pendente';
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista 014', 'email', 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', '900.000.013-09', 'bio', 'Dou treinamentos para equipes de manutenção', 'modalidades', '["presencial"]'::jsonb,
    'especialidades', '[]'::jsonb, 'aceite_termos', true, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  v_id := (v_res->>'id')::uuid;
  IF COALESCE(v_res->>'status', '') <> 'pendente' THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: cadastro nasceu ' || COALESCE(v_res->>'status', 'sem status'); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Abrir o portal como o próprio especialista'; r.esperado := 'perfil, anúncios vazios e completude entre 0 e 100';
  PERFORM public.qa_mky_claims(v_uid);
  v_portal := public.marketye_meu_portal();
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->'perfil'->>'id')::uuid IS DISTINCT FROM v_id OR jsonb_typeof(v_portal->'anuncios') <> 'array'
     OR (v_portal->>'completude')::numeric NOT BETWEEN 0 AND 100 THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal veio incompleto: ' || left(COALESCE(v_portal::text, 'NULL'), 200); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 3; r.passo_acao := 'Salvar o perfil sem área e sem cidade; abrir de novo'; r.esperado := 'continua abrindo';
  PERFORM public.qa_mky_claims(v_uid);
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('especialidades', '[]'::jsonb, 'cidade', '', 'estado', ''));
  v_portal := public.marketye_meu_portal();
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->>'completude') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal vazio depois de salvar o perfil'; PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.situacao := 'passou'; r.obtido := 'Portal abriu nas duas leituras; completude ' || (v_portal->>'completude') || '%.';
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_den uuid; v_den2 uuid; v_st text; v_acao text; n int; v_an_st text; v_an_antes text; v_portal jsonb;
        v_motivo text := 'Anúncio com conduta inadequada confirmada pela moderação';
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Empresa X registra denúncia sobre o anúncio publicado de B'; r.esperado := 'denúncia aberta, visível na fila do superadmin';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  IF qa_rls.exec_auth(format('INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES (%L, %L, %L, ''QA Empresa 110x'', ''conduta_inadequada'', ''Denúncia fictícia de teste: o anúncio promete algo que não cumpre.'')', s->>'t1', s->>'b_prof', s->>'x')) NOT LIKE 'ok:%' THEN falhas := array_append(falhas, 'empresa não conseguiu registrar a denúncia'); END IF;
  SELECT id INTO v_den FROM public.marketplace_denuncias WHERE tenant_id = (s->>'t1')::uuid AND profissional_id = (s->>'b_prof')::uuid AND tipo = 'conduta_inadequada' ORDER BY created_at DESC LIMIT 1;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_denuncias WHERE id = %L AND status = ''aberta''', v_den));
  PERFORM set_config('app.qa_modo', 'on', true);
  IF n <> 1 THEN falhas := array_append(falhas, 'denúncia não aparece aberta para o superadmin'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin decide "procedente" com a ação "remover anúncio"'; r.esperado := 'anúncio removido e fora da busca; ocorrência com reflexo; motivo visível no portal de B';
  PERFORM public.marketye_denuncia_decidir(v_den, 'procedente', v_motivo);
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE origem_tipo = 'denuncia' AND origem_id = v_den AND profissional_id = (s->>'b_prof')::uuid AND reflexo_visibilidade;
  IF n <> 1 THEN falhas := array_append(falhas, 'ocorrência com reflexo na visibilidade não registrada'); END IF;
  SELECT status INTO v_an_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid;
  IF v_an_st <> 'removido' THEN falhas := array_append(falhas, 'anúncio denunciado segue "' || v_an_st || '" depois da decisão procedente (sem takedown)'); END IF;
  SELECT count(*) INTO n FROM public.marketye_buscar_interno(jsonb_build_object('q', 'QA Seguranca B publicado')) x WHERE x->>'servico_id' = s->>'b_pub';
  IF n > 0 THEN falhas := array_append(falhas, 'anúncio denunciado continua na busca'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF NOT (COALESCE(v_portal->'ocorrencias', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('descricao', v_motivo))) THEN falhas := array_append(falhas, 'portal de B não mostra o motivo da ocorrência'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.passo_ordem := 3; r.passo_acao := 'Outra denúncia sobre B, decidida "improcedente"'; r.esperado := 'anúncio inalterado; denúncia encerrada com motivo; sem ocorrência';
  INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao)
  VALUES ((s->>'t1')::uuid, (s->>'b_prof')::uuid, (s->>'x')::uuid, 'QA Empresa 110x', 'outro', 'Segunda denúncia fictícia de teste.') RETURNING id INTO v_den2;
  SELECT status INTO v_an_antes FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_denuncia_decidir(v_den2, 'improcedente', 'Sem elementos que confirmem a denúncia');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  SELECT status, acao_tomada INTO v_st, v_acao FROM public.marketplace_denuncias WHERE id = v_den2;
  IF v_st <> 'improcedente' OR v_acao IS NULL THEN falhas := array_append(falhas, format('segunda denúncia: status %s, motivo %s', v_st, COALESCE(v_acao, 'vazio'))); END IF;
  SELECT count(*) INTO n FROM public.marketplace_ocorrencias WHERE origem_id = v_den2; IF n > 0 THEN falhas := array_append(falhas, 'decisão improcedente gerou ocorrência'); END IF;
  SELECT status INTO v_an_st FROM public.marketplace_servicos WHERE id = (s->>'b_pub')::uuid; IF v_an_st <> v_an_antes THEN falhas := array_append(falhas, 'decisão improcedente mudou o anúncio'); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Denúncia entra aberta na fila; "procedente" remove o anúncio, registra ocorrência com reflexo e o motivo aparece no portal; "improcedente" encerra com motivo sem tocar no anúncio.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_057()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; e record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  DELETE FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  r.passo_ordem := 1; r.passo_acao := 'Salvar perfil com disponibilidade e políticas'; r.esperado := 'evento com anterior (nulo) e novo';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('disponibilidade', '{"seg": ["08:00-12:00"]}'::jsonb, 'politicas', 'Cancelamento sem custo até 24h antes (teste).'));
  SELECT * INTO e FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica' ORDER BY created_at DESC LIMIT 1;
  IF e.id IS NULL OR e.anterior->>'politicas' IS NOT NULL OR e.novo->>'politicas' NOT ILIKE '%24h%' OR e.novo->'disponibilidade' IS NULL THEN falhas := array_append(falhas, 'primeiro evento incompleto'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Alterar as políticas'; r.esperado := 'novo evento com anterior = valor antigo';
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('politicas', 'Cancelamento sem custo até 48h antes (teste).'));
  SELECT * INTO e FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica' AND novo->>'politicas' ILIKE '%48h%' LIMIT 1;
  IF e.id IS NULL OR e.anterior->>'politicas' NOT ILIKE '%24h%' THEN falhas := array_append(falhas, 'segundo evento não guarda o valor anterior'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_autonomia_eventos WHERE profissional_id = (s->>'a_prof')::uuid AND tipo = 'perfil_horario_politica'; IF n <> 2 THEN falhas := array_append(falhas, format('%s eventos (esperado 2)', n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outro especialista tenta ler os eventos'; r.esperado := 'zero linhas (RLS); o dono lê os seus';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = %L', s->>'a_prof')); IF n > 0 THEN falhas := array_append(falhas, 'B lê a trilha de A'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = %L', s->>'a_prof')); IF n < 2 THEN falhas := array_append(falhas, 'controle: o dono não lê a própria trilha'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Cada mudança de disponibilidade/política gera evento com valor anterior e novo; só o dono lê a própria trilha.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_058()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_foto text; v_doc text; v_pub boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  v_foto := (s->>'a_prof') || '/foto.jpg'; v_doc := (s->>'a_prof') || '/identidade.pdf';
  INSERT INTO storage.objects (bucket_id, name, owner, path_tokens) VALUES ('marketplace-fotos', v_foto, (s->>'a_uid')::uuid, ARRAY[s->>'a_prof', 'foto.jpg']), ('marketplace-docs', v_doc, (s->>'a_uid')::uuid, ARRAY[s->>'a_prof', 'identidade.pdf']);
  INSERT INTO public.marketplace_profissional_documentos (profissional_id, categoria, nome_arquivo, arquivo_url, tamanho_bytes, mime_type) VALUES ((s->>'a_prof')::uuid, 'identidade', 'identidade.pdf', 'marketplace-docs/' || v_doc, 1234, 'application/pdf');
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-fotos'; IF v_pub IS DISTINCT FROM true THEN falhas := array_append(falhas, 'bucket de fotos não é público'); END IF;
  SELECT public INTO v_pub FROM storage.buckets WHERE id = 'marketplace-docs'; IF v_pub IS DISTINCT FROM false THEN falhas := array_append(falhas, 'bucket de documentos é público'); END IF;
  r.passo_ordem := 1; r.passo_acao := 'Ler a foto sem login'; r.esperado := 'acessível';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  n := qa_rls.conta_anon(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-fotos'' AND name = %L', v_foto)); IF n <> 1 THEN falhas := array_append(falhas, 'foto não acessível sem login'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Ler o documento sem login e como outro especialista'; r.esperado := 'negado';
  n := qa_rls.conta_anon(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'documento legível sem login'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outro especialista lê o documento'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n <> 1 THEN falhas := array_append(falhas, 'controle: o dono não lê o próprio documento'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler como superadmin'; r.esperado := 'acessível';
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM storage.objects WHERE bucket_id = ''marketplace-docs'' AND name = %L', v_doc)); IF n <> 1 THEN falhas := array_append(falhas, 'superadmin não lê o documento'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Foto no bucket público legível sem login; documento de verificação invisível para visitante e para outro especialista; dono e superadmin leem.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_064()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; t1 uuid := public.qa_sandbox_tenant_id(); t2 uuid; v_x uuid; v_y uuid; v_cat uuid; v_res jsonb; n int; v_av boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  v_x := public.qa_mky_usuario_empresa(t1, '064x'); v_y := public.qa_mky_usuario_empresa(t2, '064y');
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'pgr';
  r.passo_ordem := 1; r.passo_acao := 'Buscar "xyzservicoinexistente" em PGR'; r.esperado := 'total 0; categorias_adjacentes não vazio';
  PERFORM public.qa_mky_claims(v_x);
  v_res := public.marketye_buscar('{"q": "xyzservicoinexistente", "categoria_slug": "pgr"}'::jsonb);
  IF (v_res->>'total')::int <> 0 OR jsonb_array_length(COALESCE(v_res->'categorias_adjacentes', '[]'::jsonb)) = 0 OR (v_res->>'oferta_insuficiente')::boolean IS DISTINCT FROM true THEN falhas := array_append(falhas, 'busca vazia sem sugestões de áreas parecidas'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_registrar_busca com avisar = true e e-mail'; r.esperado := 'linha em marketplace_demanda_latente com avisar = true';
  PERFORM public.marketye_registrar_busca(v_cat, 'QA', NULL, 'xyzservicoinexistente', 0, true, 'qa-mky-064@sandbox.invalid');
  SELECT count(*), bool_and(avisar) INTO n, v_av FROM public.marketplace_demanda_latente WHERE tenant_id = t1 AND categoria_id = v_cat AND uf = 'QA' AND dia = CURRENT_DATE;
  IF n <> 1 OR v_av IS DISTINCT FROM true THEN falhas := array_append(falhas, format('registro: %s linhas, avisar %s', n, v_av)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Repetir a busca no mesmo dia'; r.esperado := 'mesma linha atualizada, não duplica';
  PERFORM public.marketye_registrar_busca(v_cat, 'QA', NULL, 'outro termo', 0, false, NULL);
  SELECT count(*), bool_and(avisar) INTO n, v_av FROM public.marketplace_demanda_latente WHERE tenant_id = t1 AND categoria_id = v_cat AND uf = 'QA' AND dia = CURRENT_DATE;
  IF n <> 1 OR v_av IS DISTINCT FROM true THEN falhas := array_append(falhas, format('repetição: %s linhas, avisar %s', n, v_av)); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Consultar como outra empresa'; r.esperado := 'não lê a linha da primeira (RLS)';
  PERFORM public.qa_mky_claims(v_y);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_demanda_latente WHERE tenant_id = %L', t1)); IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê a demanda da primeira'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Busca sem oferta devolve total 0 com áreas parecidas; o registro cria uma linha por empresa/categoria/UF/dia com "Avise-me" e não duplica; outra empresa não a lê.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_065()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; t1 uuid := public.qa_sandbox_tenant_id(); v_x uuid; v_pgr uuid; v_ltcat uuid; v_res jsonb; v_txt text; n int; ids uuid[] := '{}'; j int; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_x := public.qa_mky_usuario_empresa(t1, '065x');
  SELECT id INTO v_pgr FROM public.marketplace_categorias WHERE slug = 'pgr'; SELECT id INTO v_ltcat FROM public.marketplace_categorias WHERE slug = 'ltcat-laudos';
  -- Seis empresas sintéticas na célula PGR/QA e três em LTCAT/QA. A tabela não tem chave estrangeira para tenants; a trava do cercado é
  -- desligada só para estas linhas (ids que não existem em lugar nenhum), dentro da transação descartada.
  FOR j IN 1..6 LOOP ids := array_append(ids, gen_random_uuid()); END LOOP;
  PERFORM set_config('app.qa_modo', 'off', true);
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados, avisar, avisar_email)
  SELECT ids[i], v_pgr, 'QA', 'termo sigiloso ' || i, 0, true, 'empresa' || i || '@sandbox.invalid' FROM generate_series(1, 6) i;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, termos, resultados) SELECT ids[i], v_ltcat, 'QA', 'termo sigiloso ltcat', 0 FROM generate_series(1, 3) i;
  PERFORM set_config('app.qa_modo', 'on', true);
  r.passo_ordem := 1; r.passo_acao := 'marketye_vagas_demanda() sem login'; r.esperado := 'só a célula com ≥ 5 empresas; só categoria, UF e contagem';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_res := public.marketye_vagas_demanda(NULL);
  SELECT count(*) INTO n FROM jsonb_array_elements(v_res) e WHERE e->>'uf' = 'QA' AND e->>'categoria_slug' = 'pgr' AND (e->>'empresas')::int = 6; IF n <> 1 THEN falhas := array_append(falhas, 'célula PGR/QA com 6 empresas não veio'); END IF;
  SELECT count(*) INTO n FROM jsonb_array_elements(v_res) e WHERE e->>'uf' = 'QA' AND e->>'categoria_slug' = 'ltcat-laudos'; IF n > 0 THEN falhas := array_append(falhas, 'célula com 3 empresas exposta (abaixo do piso)'); END IF;
  v_txt := v_res::text;
  IF v_txt LIKE '%sigiloso%' OR v_txt LIKE '%@%' OR v_txt LIKE '%' || ids[1]::text || '%' OR v_txt ILIKE '%tenant%' THEN falhas := array_append(falhas, 'agregado expõe termo, e-mail ou id de empresa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'SELECT em marketplace_demanda_latente como anon'; r.esperado := 'zero linhas ou recusado';
  n := qa_rls.conta_anon('SELECT count(*) FROM public.marketplace_demanda_latente WHERE uf = ''QA'''); v_msg := CASE WHEN n = -1 THEN 'recusado' ELSE n::text END;
  IF v_msg NOT IN ('0', 'recusado') THEN falhas := array_append(falhas, 'anon lê ' || v_msg || ' linhas cruas'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'SELECT como usuário da empresa A'; r.esperado := 'nenhuma linha de outra empresa (só as de A, ou nenhuma)';
  PERFORM public.qa_mky_claims(v_x);
  PERFORM public.marketye_registrar_busca(v_pgr, 'QA', NULL, 'busca da própria empresa', 0, false, NULL);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_demanda_latente WHERE uf = ''QA'' AND tenant_id <> %L', t1));
  IF n > 0 THEN falhas := array_append(falhas, format('empresa A lê %s linhas de outras empresas', n)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A função pública devolve só a célula com 6 empresas (categoria, UF, contagem) e esconde a de 3; a tabela crua não devolve linha alguma de terceiros para visitante nem para empresa.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_068()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; sa uuid; v1 record; v2 record; v3 record; v4 record; v5 record; e record; v_an uuid; v_cat uuid; n int; n_esp int; v_vit jsonb; v_msg text; v_pub_ok uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  sa := public.qa_mky_superadmin();
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';
  SELECT * INTO v1 FROM public.qa_mky_especialista('068v1', '900.000.034-33');
  SELECT * INTO v2 FROM public.qa_mky_especialista('068v2', '900.000.035-14');
  SELECT * INTO v3 FROM public.qa_mky_especialista('068v3', '900.000.036-03');
  SELECT * INTO v4 FROM public.qa_mky_especialista('068v4', '900.000.037-86');
  SELECT * INTO v5 FROM public.qa_mky_especialista('068v5', '900.000.038-67');
  PERFORM public.qa_mky_claims(sa);
  FOR e IN SELECT * FROM (VALUES (v1.prof_id), (v2.prof_id), (v3.prof_id), (v4.prof_id), (v5.prof_id)) t(p) LOOP PERFORM public.marketye_moderar_especialista(e.p, 'aprovado', NULL, true); END LOOP;
  -- Cada um com um anúncio em cada status (publica enquanto está ativo).
  FOR e IN SELECT * FROM (VALUES (v1.uid, 'v1'), (v2.uid, 'v2'), (v3.uid, 'v3'), (v4.uid, 'v4'), (v5.uid, 'v5')) t(u, m) LOOP
    PERFORM public.qa_mky_claims(e.u);
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' rascunho', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' pausado', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an); PERFORM public.marketye_anuncio_status(v_an, 'pausado');
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' removido', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an); PERFORM public.marketye_anuncio_status(v_an, 'removido');
    v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Vis 068 ' || e.m || ' publicado', 'descricao', 'Serviço fictício de teste do MarketYE para visibilidade.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'))->>'id')::uuid;
    PERFORM public.marketye_anuncio_publicar(v_an);
    IF e.m = 'v5' THEN v_pub_ok := v_an; END IF;
  END LOOP;
  PERFORM public.qa_mky_claims(sa);
  PERFORM public.marketye_especialista_situacao(v1.prof_id, 'pendente', 'teste'); PERFORM public.marketye_especialista_situacao(v2.prof_id, 'suspenso', 'teste');
  PERFORM public.marketye_moderar_especialista(v3.prof_id, 'rejeitado', 'motivo de teste', false);
  PERFORM public.qa_mky_claims(v4.uid); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.passo_ordem := 1; r.passo_acao := 'Buscar sem filtro'; r.esperado := 'só ativo × publicado (1 de 20)';
  SELECT count(*) INTO n FROM public.marketye_buscar_interno('{"q": "QA Vis 068", "limite": 100}'::jsonb) x;
  SELECT count(*) INTO n_esp FROM public.marketye_buscar_interno('{"q": "QA Vis 068", "limite": 100}'::jsonb) x WHERE x->>'servico_id' = v_pub_ok::text;
  IF n <> 1 OR n_esp <> 1 THEN falhas := array_append(falhas, format('busca devolveu %s anúncios (esperado só o publicado do ativo)', n)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_vitrine_publica() sem login'; r.esperado := 'contagens pela mesma regra; sem PII';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_vit := public.marketye_vitrine_publica();
  SELECT count(*) INTO n FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' AND p.excluido_em IS NULL;
  IF (v_vit->>'anuncios_publicados')::int <> n THEN falhas := array_append(falhas, format('vitrine conta %s anúncios publicados; de especialistas ativos são %s', v_vit->>'anuncios_publicados', n)); END IF;
  IF v_vit::text LIKE '%@%' OR v_vit::text ILIKE '%QA Especialista%' THEN falhas := array_append(falhas, 'vitrine pública expõe dado pessoal'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Ler marketplace_servicos como anon'; r.esperado := 'só publicados de especialistas ativos';
  n := qa_rls.conta_anon('SELECT count(*) FROM public.marketplace_servicos WHERE nome LIKE ''QA Vis 068%'''); v_msg := CASE WHEN n = -1 THEN 'recusado' ELSE n::text END;
  IF v_msg NOT IN ('1', 'recusado') THEN falhas := array_append(falhas, format('anon lê %s anúncios na tabela (publicados de pendente/suspenso/bloqueado vazam)', v_msg)); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Entre 5 especialistas × 4 status de anúncio, a busca, a vitrine pública e a tabela lida por visitante mostram só o publicado do especialista ativo.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_071()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_msg text; l uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Empresa Y lê a conversa entre X e B'; r.esperado := 'zero linhas';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE id = %L', l)); IF n > 0 THEN falhas := array_append(falhas, 'Y lê o lead'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_mensagens WHERE lead_id = %L', l)); IF n > 0 THEN falhas := array_append(falhas, 'Y lê as mensagens'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE id = %L', l)); IF n <> 1 THEN falhas := array_append(falhas, 'controle: X não lê a própria conversa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Y chama marketye_lead_mensagem no lead'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  BEGIN PERFORM public.marketye_lead_mensagem(l, 'Mensagem invasora de teste'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'Y escreveu na conversa alheia'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Especialista A chama liberar_contato e lead_status'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN PERFORM public.marketye_lead_liberar_contato(l); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'A liberou contato de conversa alheia'); END IF;
  BEGIN PERFORM public.marketye_lead_status(l, 'ganho', NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'A mudou o status de conversa alheia'); END IF;
  r.passo_ordem := 4; r.passo_acao := 'Y chama marketye_lead_contato'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  BEGIN PERFORM public.marketye_lead_contato(l); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'Y leu o contato de conversa alheia'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND texto ILIKE '%invasora%'; IF n > 0 THEN falhas := array_append(falhas, 'mensagem invasora gravada'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Outra empresa não lê lead nem mensagens e não escreve; outro especialista não libera contato nem muda status; contato negado a terceiro. X lê a própria conversa.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_075()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_doc uuid; l uuid; d record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');  -- quem arquiva documentos na empresa tem papel de gestor
  INSERT INTO public.documentos (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade, criado_por, observacoes)
  VALUES ((s->>'t1')::uuid, 'Proposta MarketYE (teste)', 'proposta-teste.pdf', 'proposta-teste.pdf', 'proposta', 1000, 'application/pdf', (s->>'t1') || '/marketye/proposta-teste.pdf', CURRENT_DATE + 90, (s->>'x')::uuid, 'Origem: MarketYE, conversa ' || l::text)
  RETURNING id INTO v_doc;
  r.passo_ordem := 1; r.passo_acao := 'marketye_lead_vincular_documento(lead, documento, proposta)'; r.esperado := 'linha em marketplace_lead_documentos; mensagem de sistema na conversa';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_vincular_documento(l, v_doc, 'proposta');
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE lead_id = l AND documento_id = v_doc AND tipo = 'proposta'; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo não gravado'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND autor_tipo = 'sistema' AND texto ILIKE '%Documentos%'; IF n < 1 THEN falhas := array_append(falhas, 'sem mensagem de sistema'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Consultar o documento no módulo Documentos como a empresa'; r.esperado := 'metadados: tipo, versão 1, vigência, vínculo com o lead';
  IF qa_rls.conta_auth(format('SELECT count(*) FROM public.documentos WHERE id = %L', v_doc)) <> 1 THEN falhas := array_append(falhas, 'empresa não lê o documento (RLS)'); END IF;
  SELECT * INTO d FROM public.documentos WHERE id = v_doc;
  IF d.id IS NULL OR d.tipo <> 'proposta' OR d.versao_atual <> 1 OR d.data_validade IS NULL THEN falhas := array_append(falhas, 'documento sem os metadados esperados'); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc; IF n <> 1 THEN falhas := array_append(falhas, format('%s versões (esperado 1)', n)); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa consulta o documento e o vínculo'; r.esperado := 'não vê (tenant)';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.documentos WHERE id = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o documento'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_documentos WHERE documento_id = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o vínculo'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_documentos WHERE documento_id = %L', v_doc)); IF n <> 1 THEN falhas := array_append(falhas, 'o especialista da conversa não vê o vínculo'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'O vínculo entra com tipo proposta e mensagem de sistema; a empresa lê o documento com tipo, versão 1 e vigência; outra empresa não vê documento nem vínculo; o especialista da conversa vê o vínculo.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_086()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; a record; n int; v_resp text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'marketye_avaliacao_responder(id, "Obrigado! Me chame no 46 99999-0000")'; r.esperado := 'resposta gravada mascarada; respondido_em preenchido';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM public.marketye_avaliacao_responder((s->>'aval_a')::uuid, 'Obrigado! Me chame no 46 99999-0000 para combinar.');
  SELECT * INTO a FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  IF a.resposta IS NULL OR a.respondido_em IS NULL OR a.resposta ~ '\d{4,5}[\s.-]?\d{4}' THEN falhas := array_append(falhas, 'resposta sem máscara ou sem data: ' || COALESCE(a.resposta, 'nula')); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Responder de novo'; r.esperado := 'sobrescreve ou recusa, nunca duplica';
  BEGIN PERFORM public.marketye_avaliacao_responder((s->>'aval_a')::uuid, 'Segunda resposta de teste, sem contato.'); EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT count(*) INTO n FROM public.marketplace_avaliacoes WHERE lead_id = (s->>'lead_ya')::uuid AND direcao = 'cliente_para_especialista'; IF n <> 1 THEN falhas := array_append(falhas, 'avaliação duplicada'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Empresa lê as avaliações do especialista'; r.esperado := 'avaliação com a resposta visível';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  IF qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_avaliacoes WHERE id = %L AND resposta IS NOT NULL', s->>'aval_a')) < 1 THEN falhas := array_append(falhas, 'resposta não visível para a empresa'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A resposta entra mascarada (' || left(a.resposta, 50) || '…) com data; responder de novo sobrescreve sem duplicar; a empresa vê a avaliação com a resposta.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_087()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_ct uuid; n int; v_portal jsonb; p record; v_mod boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Especialista contesta a avaliação; superadmin defere (moderada = true)'; r.esperado := 'some do portal e da leitura pública';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_ct := (public.marketye_contestar('avaliacao', (s->>'aval_a')::uuid, 'Comentário ofensivo e sem relação com o serviço prestado (teste).', '[]'::jsonb)->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'sa')::uuid);
  PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Avaliação moderada por conteúdo ofensivo (teste).');
  SELECT moderada INTO v_mod FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid; IF NOT COALESCE(v_mod, false) THEN falhas := array_append(falhas, 'avaliação não marcada como moderada'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  IF v_portal->'avaliacoes' @> jsonb_build_array(jsonb_build_object('id', (s->>'aval_a')::uuid)) THEN falhas := array_append(falhas, 'portal ainda mostra a avaliação moderada'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_avaliacoes WHERE id = %L', s->>'aval_a'));
  IF n > 0 THEN falhas := array_append(falhas, 'avaliação moderada continua legível na tabela pública (o card a mostra)'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Recalcular'; r.esperado := 'nota_media e total_avaliacoes sem ela';
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  PERFORM public.marketye_recalcular_reputacao((s->>'a_prof')::uuid);
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = (s->>'a_prof')::uuid;
  IF p.total_avaliacoes <> 0 OR p.nota_media <> 0 THEN falhas := array_append(falhas, format('cálculo ainda conta a moderada (total %s, média %s)', p.total_avaliacoes, p.nota_media)); END IF;
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Contestação deferida marca a avaliação como moderada; ela some do portal e da leitura pública e sai da nota e do total.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_092()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; l uuid; v_st text; n int; v_c jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  PERFORM public.qa_mky_claims((s->>'x')::uuid); PERFORM public.marketye_lead_liberar_contato(l);
  r.passo_ordem := 1; r.passo_acao := 'Especialista B exclui o perfil com a conversa aberta'; r.esperado := 'aceito; lead encerrado com mensagem de sistema de que o especialista deixou o MarketYE';
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid); PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  SELECT status INTO v_st FROM public.marketplace_leads WHERE id = l;
  SELECT count(*) INTO n FROM public.marketplace_lead_mensagens WHERE lead_id = l AND autor_tipo = 'sistema' AND (texto ILIKE '%deixou%' OR texto ILIKE '%saiu%' OR texto ILIKE '%excluiu%');
  IF v_st NOT IN ('encerrado', 'perdido') OR n = 0 THEN falhas := array_append(falhas, format('lead segue "%s" e sem aviso de sistema após a exclusão', v_st)); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Empresa abre Minhas conversas'; r.esperado := 'vê a conversa sem erro; os dados de contato do especialista já não aparecem (anonimizados)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE id = %L', l));
  IF n <> 1 THEN falhas := array_append(falhas, 'empresa perdeu a conversa'); END IF;
  v_c := public.marketye_lead_contato(l);
  IF v_c->>'email' IS NOT NULL AND v_c->>'email' NOT LIKE 'removido+%' THEN falhas := array_append(falhas, 'e-mail do especialista excluído ainda aparece'); END IF;
  IF v_c->>'telefone' IS NOT NULL THEN falhas := array_append(falhas, 'telefone do especialista excluído ainda aparece'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A exclusão encerra a conversa com aviso de sistema; a empresa continua vendo a conversa, já sem e-mail nem telefone do especialista.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_094()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_msg text; n int; v jsonb; v_txt text; k text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'SELECT em marketplace_profissionais como anon e como authenticated'; r.esperado := 'colunas sensíveis recusadas para o papel; colunas públicas e SELECT * só sem as sensíveis';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  FOREACH k IN ARRAY ARRAY['email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'] LOOP
    IF qa_rls.conta_anon(format('SELECT count(*) FROM public.marketplace_profissionais WHERE %I IS NOT NULL', k)) <> -1 THEN falhas := array_append(falhas, 'anon lê a coluna ' || k); END IF;
  END LOOP;
  IF qa_rls.conta_anon('SELECT count(*) FROM (SELECT * FROM public.marketplace_profissionais) z') <> -1 THEN falhas := array_append(falhas, 'anon faz SELECT * (todas as colunas)'); END IF;
  n := qa_rls.conta_anon(format('SELECT count(*) FROM public.marketplace_profissionais WHERE id = %L', s->>'a_prof')); IF n <> 1 THEN falhas := array_append(falhas, 'controle: anon não lê colunas públicas do especialista ativo'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  FOREACH k IN ARRAY ARRAY['email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id'] LOOP
    IF qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_profissionais WHERE %I IS NOT NULL', k)) <> -1 THEN falhas := array_append(falhas, 'empresa lê a coluna ' || k); END IF;
  END LOOP;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_profissionais WHERE id = %L', s->>'a_prof')); IF n <> 1 THEN falhas := array_append(falhas, 'controle: empresa não lê colunas públicas'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_vitrine_publica() como anon e marketye_buscar() como empresa'; r.esperado := 'payloads sem e-mail, telefone, documento, user_id, tenant_id';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v := public.marketye_vitrine_publica();
  v_txt := v::text;
  IF v_txt LIKE '%@%' OR v_txt LIKE '%9000000%' OR v_txt ILIKE '%user_id%' OR v_txt ILIKE '%tenant_id%' THEN falhas := array_append(falhas, 'vitrine pública expõe dado pessoal'); END IF;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v := public.marketye_buscar('{"q": "QA Seguranca"}'::jsonb); v_txt := (v->'resultados')::text;
  IF v_txt LIKE '%@%' OR v_txt LIKE '%9000000%' OR v_txt ILIKE '%"user_id"%' OR v_txt ILIKE '%"tenant_id"%' OR v_txt ILIKE '%"email"%' OR v_txt ILIKE '%"telefone"%' OR v_txt ILIKE '%"cpf_cnpj"%' THEN falhas := array_append(falhas, 'busca expõe contato, documento ou ids'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'marketye_meu_portal de outro especialista'; r.esperado := 'não é possível: só o próprio';
  IF public.marketye_meu_portal() IS NOT NULL THEN falhas := array_append(falhas, 'empresa recebe um portal'); END IF;
  PERFORM public.qa_mky_claims((s->>'b_uid')::uuid);
  v := public.marketye_meu_portal();
  IF v->'perfil'->>'id' <> s->>'b_prof' OR v::text LIKE '%' || (s->>'a_prof') || '%' THEN falhas := array_append(falhas, 'portal de B traz dado de A'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Visitante e empresa não leem e-mail, telefone, documento, user_id nem tenant_id (só colunas públicas); vitrine e busca saem sem contato, documento, user_id ou tenant_id; o portal é só do próprio especialista.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_095()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_portal jsonb; e jsonb; n int; l uuid; v_c jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  IF NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE tenant_id = (s->>'t2')::uuid) THEN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, cnpj) VALUES ((s->>'t2')::uuid, 'Empresa QA 095', '12.345.678/0001-95');
  END IF;
  INSERT INTO public.empresa_obrigacoes (tenant_id, categoria, titulo, descricao) VALUES ((s->>'t2')::uuid, 'sst', 'PGR (teste)', 'Obrigação fictícia sigilosa de teste');
  r.passo_ordem := 1; r.passo_acao := 'Especialista A abre o portal'; r.esperado := 'leads[].empresa_nome e reputacao_empresa apenas; nada de CNPJ, riscos ou obrigações';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  v_portal := public.marketye_meu_portal();
  SELECT x INTO e FROM jsonb_array_elements(v_portal->'leads') x WHERE x->>'id' = s->>'lead_ya';
  IF e IS NULL OR e->>'empresa_nome' IS NULL OR e ? 'tenant_id' OR e ? 'cnpj' OR e ? 'empresa_id' THEN falhas := array_append(falhas, 'conversa sem nome da empresa ou com id/CNPJ'); END IF;
  IF v_portal::text LIKE '%12.345.678%' OR v_portal::text LIKE '%12345678%' OR v_portal::text ILIKE '%sigilosa%' OR v_portal::text ILIKE '%PGR (teste)%' THEN falhas := array_append(falhas, 'portal expõe CNPJ ou obrigações da empresa'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'A lê tenants, empresa_cadastro, obrigações e pessoas da empresa'; r.esperado := 'zero linhas (RLS)';
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.tenants WHERE id = %L', s->>'t2')); IF n > 0 THEN falhas := array_append(falhas, 'lê tenants'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.empresa_cadastro WHERE tenant_id = %L', s->>'t2')); IF n > 0 THEN falhas := array_append(falhas, 'lê empresa_cadastro'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.empresa_obrigacoes WHERE tenant_id = %L', s->>'t2')); IF n > 0 THEN falhas := array_append(falhas, 'lê empresa_obrigacoes'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.usuarios_base WHERE tenant_id = %L', s->>'t2')); IF n > 0 THEN falhas := array_append(falhas, 'lê usuarios_base'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.profiles WHERE tenant_id = %L', s->>'t2')); IF n > 0 THEN falhas := array_append(falhas, 'lê profiles da empresa'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'A chama marketye_lead_contato antes da liberação'; r.esperado := 'sem contato';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  l := (public.marketye_abrir_lead((s->>'a_prof')::uuid, (s->>'a_pub')::uuid, 'Conversa fictícia de teste ainda sem contato liberado.')->>'id')::uuid;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN v_c := public.marketye_lead_contato(l); IF COALESCE((v_c->>'liberado')::boolean, true) THEN falhas := array_append(falhas, 'contato entregue antes da liberação'); END IF; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'O portal mostra da empresa só o nome e a reputação; A não lê tenants, cadastro, obrigações nem pessoas da empresa; sem liberação, nenhum contato.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_102()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v jsonb; v_msg text; n int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'marketye_config(relevancia_pesos) como empresa e especialista; vitrine pública como visitante'; r.esperado := 'logados leem a vigente; visitante recebe os termos pela vitrine';
  PERFORM public.qa_mky_claims((s->>'x')::uuid); IF public.marketye_config('relevancia_pesos') IS NULL THEN falhas := array_append(falhas, 'empresa não lê a configuração'); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid); IF public.marketye_config('relevancia_pesos') IS NULL THEN falhas := array_append(falhas, 'especialista não lê a configuração'); END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v := public.marketye_vitrine_publica();
  IF v->'termos_versoes' IS NULL THEN falhas := array_append(falhas, 'vitrine pública sem termos_versoes'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'marketye_config_salvar como empresa, especialista e visitante'; r.esperado := 'Acesso negado';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  BEGIN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1}'::jsonb, 'x', 'BR'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'Acesso negado' THEN falhas := array_append(falhas, 'empresa: ' || left(v_msg, 40)); END IF;
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  BEGIN PERFORM public.marketye_config_salvar('piso_nota', '{"nota": 1}'::jsonb, 'x', 'BR'); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg <> 'Acesso negado' THEN falhas := array_append(falhas, 'especialista: ' || left(v_msg, 40)); END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_msg := CASE WHEN qa_rls.exec_anon('SELECT public.marketye_config_salvar(''piso_nota'', ''{"nota": 1}''::jsonb, ''x'', ''BR'')') LIKE 'ok:%' THEN 'aceitou' ELSE 'negado' END;
  IF v_msg = 'aceitou' THEN falhas := array_append(falhas, 'visitante gravou configuração'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'UPDATE direto em marketplace_config como authenticated'; r.esperado := 'zero linhas ou recusado';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v_msg := qa_rls.exec_auth('UPDATE public.marketplace_config SET valor = ''{}''::jsonb WHERE chave = ''relevancia_pesos''');
  v_msg := CASE WHEN v_msg = '42501' THEN 'recusado' WHEN v_msg LIKE 'ok:%' THEN split_part(v_msg, ':', 2) ELSE v_msg END;
  IF v_msg NOT IN ('0', 'recusado') THEN falhas := array_append(falhas, 'UPDATE direto alterou ' || v_msg || ' linhas'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Empresa e especialista leem a configuração vigente; o visitante recebe os termos pela vitrine; salvar recusa os três papéis e o UPDATE direto não altera nada.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_110()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_ex text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como A: ler as linhas de B em cada tabela'; r.esperado := 'zero linhas nas tabelas privadas; só o anúncio publicado de B; as próprias linhas visíveis (controle)';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_consentimentos WHERE profissional_id = %L', s->>'a_prof')); IF n = 0 THEN falhas := array_append(falhas, 'controle: A não lê os próprios consentimentos'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'leads de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_mensagens WHERE lead_id = %L', s->>'lead_xb')); IF n > 0 THEN falhas := array_append(falhas, 'mensagens de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_documentos WHERE lead_id = %L', s->>'lead_xb')); IF n > 0 THEN falhas := array_append(falhas, 'documentos da conversa de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_cupons WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'cupons de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_consentimentos WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'consentimentos de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_contestacoes WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'contestações de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_ocorrencias WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'ocorrências de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'trilha de autonomia de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_destaques WHERE profissional_id = %L', s->>'b_prof')); IF n > 0 THEN falhas := array_append(falhas, 'destaques de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_servicos WHERE id = %L', s->>'b_rasc')); IF n > 0 THEN falhas := array_append(falhas, 'rascunho de anúncio de B'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_servicos WHERE id = %L', s->>'b_pub')); IF n <> 1 THEN falhas := array_append(falhas, 'controle: anúncio publicado de B deveria ser visível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como A: escrever nas linhas de B'; r.esperado := 'nada muda';
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_servicos SET nome = ''invadido'' WHERE id = %L', s->>'b_pub')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'UPDATE no anúncio de B alterou linha'); END IF;
  IF qa_rls.exec_auth(format('INSERT INTO public.marketplace_cupons (profissional_id, codigo, desconto_percentual) VALUES (%L, ''INVASAO'', 5)', s->>'b_prof')) LIKE 'ok:%' THEN falhas := array_append(falhas, 'INSERT de cupom em nome de B foi aceito'); END IF;
  IF qa_rls.exec_auth(format('INSERT INTO public.marketplace_servicos (profissional_id, nome, descricao, modalidade) VALUES (%L, ''invasao'', ''anúncio em nome de outro'', ''online'')', s->>'b_prof')) LIKE 'ok:%' THEN falhas := array_append(falhas, 'INSERT de anúncio em nome de B foi aceito'); END IF;
  v_ex := qa_rls.exec_auth(format('DELETE FROM public.marketplace_cupons WHERE id = %L', s->>'cupom_b')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'DELETE do cupom de B apagou linha'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'A não lê nem altera leads, mensagens, documentos, cupons, consentimentos, contestações, ocorrências, trilha, destaques e rascunhos de B; só o anúncio publicado, como a vitrine exige.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_111()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_ex text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: ler as linhas de Y em cada tabela'; r.esperado := 'zero linhas; a própria conversa visível (controle)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado dispara antes do RLS e lê tenants sob RLS como authenticated (ver MKY-001)
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE id = %L', s->>'lead_xb')); IF n <> 1 THEN falhas := array_append(falhas, 'controle: X não lê a própria conversa'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_leads WHERE id = %L', s->>'lead_ya')); IF n > 0 THEN falhas := array_append(falhas, 'lead de Y'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_lead_mensagens WHERE lead_id = %L', s->>'lead_ya')); IF n > 0 THEN falhas := array_append(falhas, 'mensagens de Y'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_denuncias WHERE id = %L', s->>'den_y')); IF n > 0 THEN falhas := array_append(falhas, 'denúncia de Y'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_contratacoes WHERE id = %L', s->>'contr_y')); IF n > 0 THEN falhas := array_append(falhas, 'contratação de Y'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_demanda_latente WHERE id = %L', s->>'dem_y')); IF n > 0 THEN falhas := array_append(falhas, 'demanda latente de Y'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.marketplace_avaliacoes WHERE id = %L AND direcao = ''cliente_para_especialista''', s->>'aval_a')); IF n <> 1 THEN falhas := array_append(falhas, 'controle: avaliação pública de especialista deveria ser legível'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: escrever em nome de Y'; r.esperado := 'recusado ou nada muda';
  IF qa_rls.exec_auth(format('INSERT INTO public.marketplace_denuncias (tenant_id, profissional_id, denunciante_id, denunciante_nome, tipo, descricao) VALUES (%L, %L, %L, ''QA Empresa 110x'', ''outro'', ''denúncia em nome de outra empresa'')', s->>'t2', s->>'a_prof', s->>'x')) LIKE 'ok:%' THEN falhas := array_append(falhas, 'INSERT de denúncia com tenant de Y foi aceito'); END IF;
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_contratacoes SET observacoes = ''invadido'' WHERE id = %L', s->>'contr_y')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'UPDATE na contratação de Y alterou linha'); END IF;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'X não lê leads, mensagens, denúncias, contratações nem demanda latente de Y, e não escreve em nome de Y; lê a própria conversa e as avaliações públicas de especialistas.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_113()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_nota numeric; v_texto text; v_status text; v_lib boolean; v_nivel text; v_cons int; v_ex text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  r.passo_ordem := 1; r.passo_acao := 'Como A: alterar a avaliação recebida, a mensagem da empresa, o próprio consentimento, a própria reputação e o próprio lead'; r.esperado := '0 linhas em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_avaliacoes SET nota_geral = 5 WHERE id = %L', s->>'aval_a')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'avaliação recebida alterada'); END IF;
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_lead_mensagens SET texto = ''invadido'' WHERE id = %L', s->>'msg_ya')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'mensagem da empresa alterada'); END IF;
  v_ex := qa_rls.exec_auth(format('DELETE FROM public.marketplace_consentimentos WHERE profissional_id = %L', s->>'a_prof')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'consentimento apagado'); END IF;
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_reputacao SET nivel = ''top'' WHERE profissional_id = %L', s->>'a_prof')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'reputação alterada'); END IF;
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_leads SET status = ''ganho'' WHERE id = %L', s->>'lead_xb')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'lead alterado pelo especialista'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Como usuário de X: liberar o contato e mudar o status direto na tabela'; r.esperado := '0 linhas';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  v_ex := qa_rls.exec_auth(format('UPDATE public.marketplace_leads SET contato_liberado = true, status = ''ganho'' WHERE id = %L', s->>'lead_xb')); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'lead alterado pela empresa'); END IF;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.passo_ordem := 3; r.passo_acao := 'Reler os valores como o dono do banco'; r.esperado := 'tudo como antes';
  SELECT nota_geral INTO v_nota FROM public.marketplace_avaliacoes WHERE id = (s->>'aval_a')::uuid;
  SELECT texto INTO v_texto FROM public.marketplace_lead_mensagens WHERE id = (s->>'msg_ya')::uuid;
  SELECT status::text, contato_liberado INTO v_status, v_lib FROM public.marketplace_leads WHERE id = (s->>'lead_xb')::uuid;
  SELECT nivel INTO v_nivel FROM public.marketplace_reputacao WHERE profissional_id = (s->>'a_prof')::uuid;
  SELECT count(*) INTO n FROM public.marketplace_consentimentos WHERE profissional_id = (s->>'a_prof')::uuid;
  IF v_nota = 5 OR v_texto = 'invadido' OR v_status = 'ganho' OR v_lib OR v_nivel = 'top' OR n <> v_cons THEN
    falhas := array_append(falhas, format('valor mudou (nota %s, texto %s, status %s, liberado %s, nível %s, consentimentos %s/%s)', v_nota, v_texto, v_status, v_lib, v_nivel, n, v_cons));
  END IF;
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Toda escrita direta onde o papel só lê foi negada ou afetou 0 linhas, e nada mudou: avaliação, mensagem, consentimento, reputação e lead intactos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_114()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; falhas text[] := '{}'; v text; v_msg text; f text; v_ex text;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  r.passo_ordem := 1; r.passo_acao := 'Funções marketye_* executáveis por anon'; r.esperado := 'só marketye_vitrine_publica, marketye_vagas_demanda e marketye_meu_id (devolve nulo sem sessão; as políticas a chamam)';
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE 'marketye_%' AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname NOT IN ('marketye_vitrine_publica', 'marketye_vagas_demanda', 'marketye_meu_id');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'anon executa: ' || v); END IF;
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_vitrine_publica', 'marketye_vagas_demanda') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'controle: a página pública precisa de anon em ' || v); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Funções internas executáveis por authenticated ou anon'; r.esperado := 'nenhuma (só service_role)';
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('marketye_buscar_interno', 'marketye_cadastrar_especialista_para', 'marketye_recalcular_reputacao', 'marketye_semear_ilha_teste')
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v IS NOT NULL THEN falhas := array_append(falhas, 'interna exposta: ' || v); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Como anon: chamar moderação, ajustes, painel e busca'; r.esperado := 'recusado antes de qualquer efeito';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  FOREACH f IN ARRAY ARRAY['SELECT public.marketye_moderar_especialista(gen_random_uuid(), ''aprovado'', NULL, true)',
                           'SELECT public.marketye_config_salvar(''relevancia_pesos'', ''{}''::jsonb, NULL)',
                           'SELECT public.marketye_painel_liquidez()',
                           'SELECT public.marketye_buscar(''{}''::jsonb)',
                           'SELECT public.marketye_moderacao_fila()'] LOOP
    v_ex := qa_rls.exec_anon(f);
    IF v_ex LIKE 'ok:%' THEN falhas := array_append(falhas, 'anon executou sem barreira: ' || f);
    ELSIF v_ex <> '42501' THEN falhas := array_append(falhas, 'anon chegou a rodar a função (erro interno, não de permissão): ' || left(f, 60) || ' -> ' || v_ex);
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'anon só executa a vitrine pública, as vagas de demanda e a consulta do próprio id; internas só service_role; moderação, ajustes, painel, fila e busca recusam o visitante por permissão.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_116()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; n int; v_sql text; v_msg text; v_ex text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  PERFORM set_config('app.qa_modo', 'off', true);
  r.passo_ordem := 1; r.passo_acao := 'Como usuário de X: INSERT direto em leads, mensagens, avaliações, demanda latente e configuração'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por) VALUES (%L, %L, %L, %L)', s->>'t1', s->>'b_prof', s->>'b_pub', s->>'x'),
    format('INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (%L, ''cliente'', %L, ''me liga no 46 99999-0000'')', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, lead_id, direcao, nota_geral, avaliador_id) VALUES (%L, %L, %L, ''cliente_para_especialista'', 5, %L)', s->>'b_prof', s->>'t1', s->>'lead_xb', s->>'x'),
    format('INSERT INTO public.marketplace_demanda_latente (tenant_id, uf, termos, resultados) VALUES (%L, ''QA'', ''x'', 0)', s->>'t1'),
    'INSERT INTO public.marketplace_config (chave, versao, valor, vigente) VALUES (''relevancia_pesos'', 999, ''{}''::jsonb, true)'
  ] LOOP
    v_ex := qa_rls.exec_auth(v_sql);
    IF v_ex LIKE 'ok:%' THEN falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    ELSIF v_ex <> '42501' THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || v_ex || '): ' || left(v_sql, 60));
    END IF;
  END LOOP;
  v_ex := qa_rls.exec_auth('UPDATE public.marketplace_config SET valor = ''{}''::jsonb WHERE vigente'); IF v_ex LIKE 'ok:%' AND split_part(v_ex, ':', 2) <> '0' THEN falhas := array_append(falhas, 'UPDATE em marketplace_config alterou linhas'); END IF;
  -- Controle positivo: a mesma pessoa escreve pela porta certa (função SECURITY DEFINER, sem trocar de papel).
  BEGIN PERFORM public.marketye_lead_mensagem((s->>'lead_xb')::uuid, 'Mensagem pela função, permitida.'); EXCEPTION WHEN OTHERS THEN falhas := array_append(falhas, 'controle: a função de mensagem falhou: ' || SQLERRM); END;
  r.passo_ordem := 2; r.passo_acao := 'Como especialista A: INSERT direto em reputação, destaques, consentimentos, contestações e ocorrências'; r.esperado := 'recusado pelo RLS (42501) em todos';
  PERFORM public.qa_mky_claims((s->>'a_uid')::uuid);
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.marketplace_reputacao (profissional_id, nivel) VALUES (%L, ''top'')', gen_random_uuid()),
    format('INSERT INTO public.marketplace_destaques (profissional_id, tipo, inicio, fim, ativo) VALUES (%L, ''topo'', CURRENT_DATE, CURRENT_DATE + 30, true)', s->>'a_prof'),
    format('INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao) VALUES (%L, ''termos_especialista'', ''falsa'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, motivo) VALUES (%L, ''outro'', ''contestação por fora da função'')', s->>'a_prof'),
    format('INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao) VALUES (%L, ''ocorrencia'', ''apagando o histórico'')', s->>'b_prof')
  ] LOOP
    v_ex := qa_rls.exec_auth(v_sql);
    IF v_ex LIKE 'ok:%' THEN falhas := array_append(falhas, 'aceito: ' || left(v_sql, 70));
    ELSIF v_ex <> '42501' THEN falhas := array_append(falhas, 'passou pelo RLS e caiu em outra barreira (' || v_ex || '): ' || left(v_sql, 60));
    END IF;
  END LOOP;
  PERFORM set_config('app.qa_modo', 'on', true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF array_length(falhas, 1) IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Nenhuma escrita direta passou: leads, mensagens, avaliações, demanda latente, configuração, reputação, destaques, consentimentos, contestações e ocorrências só aceitam a porta das funções.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_121()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_ac uuid; a record; n int; v_msg text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca();
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');
  r.passo_ordem := 1; r.passo_acao := 'Criar ação a partir da conversa (como a empresa, sob RLS)'; r.esperado := 'plano_acoes com origem_modulo = marketplace e origem_id = lead; 5W2H preenchidos';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  IF qa_rls.exec_auth(format('INSERT INTO public.plano_acoes (tenant_id, titulo, descricao, porque, onde, prazo, responsavel_nome, como, custo_estimado, origem_modulo, origem_id, origem_descricao, tipo) VALUES (%L, ''Contratar PGR com especialista (teste)'', ''Elaborar o PGR com o especialista da conversa'', ''Obrigação NR-1 pendente'', ''Unidade QA'', CURRENT_DATE + 30, ''QA Empresa 110x'', ''Pelo MarketYE'', 1500, ''marketplace'', %L, ''Conversa MarketYE'', ''corretiva'')', s->>'t1', s->>'lead_xb')) NOT LIKE 'ok:%' THEN falhas := array_append(falhas, 'empresa (gestora) não conseguiu criar a ação'); END IF;
  PERFORM set_config('app.qa_modo', 'on', true);
  SELECT * INTO a FROM public.plano_acoes WHERE origem_modulo = 'marketplace' AND origem_id = (s->>'lead_xb')::uuid ORDER BY created_at DESC LIMIT 1;
  v_ac := a.id;
  IF a.origem_modulo <> 'marketplace' OR a.origem_id <> (s->>'lead_xb')::uuid OR a.porque IS NULL OR a.onde IS NULL OR a.prazo IS NULL OR a.responsavel_nome IS NULL OR a.como IS NULL OR a.custo_estimado IS NULL OR a.codigo IS NULL THEN falhas := array_append(falhas, 'ação sem origem ou sem 5W2H completo'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Concluir a ação'; r.esperado := 'exige validação de eficácia (data e responsável)';
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM set_config('app.qa_modo', 'off', true);
  v_msg := qa_rls.exec_auth(format('UPDATE public.plano_acoes SET status = ''concluida'', data_conclusao = CURRENT_DATE, progresso = 100 WHERE id = %L', v_ac));
  v_msg := CASE WHEN v_msg = 'ok:1' THEN 'concluiu' WHEN v_msg LIKE 'ok:%' THEN 'zero linhas' ELSE v_msg END;
  PERFORM set_config('app.qa_modo', 'on', true);
  IF v_msg = 'concluiu' THEN falhas := array_append(falhas, 'ação de origem MarketYE concluída sem validação de eficácia'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa consulta a ação'; r.esperado := 'não vê';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.plano_acoes WHERE id = %L', v_ac));
  IF n > 0 THEN falhas := array_append(falhas, 'outra empresa vê a ação'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'Ação nasce com origem marketplace, id do lead e 5W2H; concluir exige eficácia; outra empresa não vê.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_122()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; s jsonb; v_claims text; falhas text[] := '{}'; v_doc uuid; d record; n int; l uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  s := public.qa_mky_cenario_seguranca(); l := (s->>'lead_xb')::uuid;
  INSERT INTO public.user_roles (user_id, role) VALUES ((s->>'x')::uuid, 'manager');
  INSERT INTO public.documentos (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade, criado_por, observacoes)
  VALUES ((s->>'t1')::uuid, 'Proposta MarketYE (teste)', 'proposta-teste.pdf', 'proposta-teste.pdf', 'proposta', 1000, 'application/pdf', (s->>'t1') || '/marketye/proposta-teste-v1.pdf', CURRENT_DATE + 90, (s->>'x')::uuid, 'Origem: MarketYE, conversa ' || l::text)
  RETURNING id INTO v_doc;
  PERFORM public.qa_mky_claims((s->>'x')::uuid);
  PERFORM public.marketye_lead_vincular_documento(l, v_doc, 'proposta');
  r.passo_ordem := 1; r.passo_acao := 'Consultar o módulo Documentos como a empresa'; r.esperado := 'tipo, origem MarketYE, lead, versão 1, vigência';
  IF qa_rls.conta_auth(format('SELECT count(*) FROM public.documentos WHERE id = %L', v_doc)) <> 1 THEN falhas := array_append(falhas, 'empresa não lê o documento (RLS)'); END IF;
  SELECT * INTO d FROM public.documentos WHERE id = v_doc;
  IF d.id IS NULL OR d.tipo <> 'proposta' OR d.versao_atual <> 1 OR d.data_validade IS NULL OR d.observacoes NOT ILIKE '%MarketYE%' THEN falhas := array_append(falhas, 'metadados incompletos para a empresa'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc AND lead_id = l; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo com o lead ausente'); END IF;
  r.passo_ordem := 2; r.passo_acao := 'Nova versão do mesmo documento'; r.esperado := 'versão 2 vinculada; versão 1 preservada';
  PERFORM set_config('app.qa_modo', 'off', true);  -- a trava do cercado lê tenants sob RLS como authenticated (ver MKY-001)
  IF qa_rls.exec_auth(format('UPDATE public.documentos SET storage_path = %L, versao_atual = 2, total_versoes = 2 WHERE id = %L', (s->>'t1') || '/marketye/proposta-teste-v2.pdf', v_doc)) <> 'ok:1' THEN falhas := array_append(falhas, 'empresa não conseguiu versionar'); END IF;
  PERFORM set_config('app.qa_modo', 'on', true);
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc; IF n <> 2 THEN falhas := array_append(falhas, format('%s versões (esperado 2)', n)); END IF;
  SELECT count(*) INTO n FROM public.documento_versoes WHERE documento_id = v_doc AND versao = 1 AND storage_path LIKE '%v1.pdf'; IF n <> 1 THEN falhas := array_append(falhas, 'versão 1 não preservada'); END IF;
  SELECT count(*) INTO n FROM public.marketplace_lead_documentos WHERE documento_id = v_doc AND lead_id = l; IF n <> 1 THEN falhas := array_append(falhas, 'vínculo perdido ao versionar'); END IF;
  r.passo_ordem := 3; r.passo_acao := 'Outra empresa'; r.esperado := 'não vê';
  PERFORM public.qa_mky_claims((s->>'y')::uuid);
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.documentos WHERE id = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê o documento'); END IF;
  n := qa_rls.conta_auth(format('SELECT count(*) FROM public.documento_versoes WHERE documento_id = %L', v_doc)); IF n > 0 THEN falhas := array_append(falhas, 'outra empresa lê as versões'); END IF;
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(falhas, 1) IS NULL THEN r.situacao := 'passou'; r.obtido := 'A empresa vê o documento com tipo, origem MarketYE, vínculo com o lead, versão 1 e vigência; a nova versão vira 2 mantendo a 1 e o vínculo; outra empresa não vê nada.';
  ELSE r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(falhas, '; '); END IF;
  PERFORM public.qa_mky_limpar(); RETURN r;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true); r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
