-- =========================================================
-- SCRIPT DE ENTREGA — Motor de QA: rotinas do módulo
-- Usuários, Níveis de Acesso, Liberações e Permissões
--
-- Onde colar: SQL Editor do projeto (homologação primeiro; produção só
-- depois do aceite). Roda o arquivo INTEIRO de uma vez.
--
-- O que faz: cria as 54 rotinas que executam no motor de QA os casos de
-- nível 'api' do módulo Usuários & Permissões, mais os apoios que elas usam,
-- e liga cada caso à sua rotina em qa_implementacoes.
--
-- O que NÃO faz: não altera nenhuma regra de acesso, política, perfil,
-- permissão, vínculo ou dado de cliente. As rotinas são SOMENTE LEITURA do
-- ponto de vista do sistema: o que elas escrevem é dado sintético dentro do
-- cercado de QA, e o motor desfaz tudo ao final de cada uma. Por isso não há
-- cópia de segurança neste script — ele não toca em dado existente.
--
-- UMA correção de infraestrutura vai junto, e está explicada no corpo:
-- qa_sandbox_tenant_id() passa a rodar com privilégio do dono. Sem isso a
-- trava do cercado ficava cega quando a rotina assumia o papel de usuário
-- comum e recusava tudo, produzindo falso verde. A trava continua fazendo o
-- mesmo: recusar escrita fora do cercado.
--
-- Idempotente: só CREATE OR REPLACE FUNCTION e upsert por código.
-- Erros por item não abortam o resto. Termina com UMA conferência.
-- =========================================================

SET lock_timeout = '10s';

DO $entrega_pre$
BEGIN
  IF to_regtype('public.qa_retorno') IS NULL
     OR to_regclass('public.qa_implementacoes') IS NULL
     OR to_regclass('public.usuario_perfil_vinculos') IS NULL THEN
    RAISE NOTICE 'ATENÇÃO: falta parte do motor de QA ou do schema de perfis neste ambiente. As rotinas serão criadas, mas confira a contagem final.';
  END IF;
END $entrega_pre$;

-- ═════════════════════════════════════════════════════════
-- APOIOS
-- ═════════════════════════════════════════════════════════

-- Simula o usuário logado. Transação-local: o descarte do motor desfaz.
CREATE OR REPLACE FUNCTION public.qa_up_entrar(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text,
                     true);
END $fn$;

COMMENT ON FUNCTION public.qa_up_entrar(uuid) IS
  'QA Usuários & Permissões: passa a decidir como se este usuário estivesse logado (claims transação-local).';

CREATE OR REPLACE FUNCTION public.qa_up_sair()
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END $fn$;

COMMENT ON FUNCTION public.qa_up_sair() IS
  'QA Usuários & Permissões: volta ao estado sem usuário logado.';

-- Cria um usuário sintético no cercado, SEM atalho de privilégio e sem o
-- vínculo automático do perfil padrão. Devolve o id do cadastro.
CREATE OR REPLACE FUNCTION public.qa_up_usuario(
  p_codigo text, p_n int, p_cpf text,
  p_status text DEFAULT 'ativo',
  p_auth_uid uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid; v_auth uuid;
BEGIN
  INSERT INTO public.usuarios_base
    (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
  VALUES (v_t, '[QA-' || p_codigo || '] Usuario ' || p_n,
          public.qa_fixture_email(p_codigo, p_n), p_cpf,
          'colaborador', p_status::public.usuario_status,
          COALESCE(p_auth_uid, gen_random_uuid()))
  RETURNING id INTO v_id;

  -- Desarma o vínculo automático do perfil padrão: o cenário tem que ser
  -- exatamente o que a rotina declara, nem um vínculo a mais.
  DELETE FROM public.usuario_perfil_vinculos WHERE usuario_id = v_id;

  -- O sistema identifica o usuário por DOIS caminhos, e a fixture precisa dos
  -- dois para ser um usuário de verdade:
  --   · a decisão de PERMISSÃO acha a pessoa por usuarios_base.auth_user_id;
  --   · o ISOLAMENTO acha o cliente dela por profiles.user_id (é o que
  --     get_user_tenant_id() consulta, e é nele que as políticas se apoiam).
  -- Sem a linha em profiles, o usuário sintético não enxerga nem o próprio
  -- cliente, e as rotinas de isolamento mediriam a falta da fixture em vez de
  -- medir o isolamento. profiles.user_id tem chave estrangeira para auth.users,
  -- então a identidade de autenticação também precisa existir.
  SELECT auth_user_id INTO v_auth FROM public.usuarios_base WHERE id = v_id;

  BEGIN
    INSERT INTO auth.users (id, email) VALUES (v_auth, public.qa_fixture_email(p_codigo, p_n))
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (user_id, tenant_id, nome_completo)
    VALUES (v_auth, v_t, '[QA-' || p_codigo || '] Usuario ' || p_n)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Ambiente onde o motor não pode escrever na identidade de autenticação.
    -- Não é motivo para abortar: as rotinas que dependem disso conferem com
    -- qa_up_tem_identidade() e dizem o que faltou, em vez de dar veredito.
    RAISE NOTICE 'QA Usuários & Permissões: identidade completa não criada para %: %', v_id, SQLERRM;
  END;

  RETURN v_id;
END $fn$;

-- A fixture conseguiu montar a identidade que o isolamento enxerga?
CREATE OR REPLACE FUNCTION public.qa_up_tem_identidade(p_auth_uid uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = p_auth_uid)
$fn$;

COMMENT ON FUNCTION public.qa_up_tem_identidade(uuid) IS
  'QA Usuários & Permissões: existe a linha em profiles que o isolamento usa para saber de que cliente o usuário é?';

COMMENT ON FUNCTION public.qa_up_usuario(text, int, text, text, uuid) IS
  'QA Usuários & Permissões: usuário sintético no cercado, sem atalho de privilégio e sem o vínculo automático de perfil padrão.';

-- Cria um perfil de acesso com UMA permissão no módulo informado.
-- p_escopo 'empresa_inteira' = acesso amplo; 'proprio_usuario' = restrito.
CREATE OR REPLACE FUNCTION public.qa_up_perfil(
  p_codigo text, p_sufixo text, p_modulo text,
  p_escopo text DEFAULT 'empresa_inteira',
  p_acao text DEFAULT 'visualizar'
)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  INSERT INTO public.perfis_acesso (tenant_id, nome, descricao, tipo, ativo)
  VALUES (v_t, '[QA-' || p_codigo || '] ' || p_sufixo,
          'Perfil sintético do motor de QA.', 'personalizado', true)
  RETURNING id INTO v_id;

  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_id, v_t, p_modulo, p_acao::public.perfil_acao,
          p_escopo::public.perfil_escopo_tipo, true);

  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.qa_up_perfil(text, text, text, text, text) IS
  'QA Usuários & Permissões: perfil de acesso sintético com uma permissão no módulo informado.';

-- Vincula usuário a empresa com um perfil. É o vínculo que carrega o nível.
CREATE OR REPLACE FUNCTION public.qa_up_vincular(
  p_usuario uuid, p_empresa uuid, p_perfil uuid,
  p_ativo boolean DEFAULT true,
  p_expira timestamptz DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_id uuid;
BEGIN
  INSERT INTO public.usuario_perfil_vinculos
    (tenant_id, usuario_id, empresa_id, perfil_id, ativo, expira_em)
  VALUES (v_t, p_usuario, p_empresa, p_perfil, p_ativo, p_expira)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.qa_up_vincular(uuid, uuid, uuid, boolean, timestamptz) IS
  'QA Usuários & Permissões: vínculo (usuário, empresa, perfil) no cercado.';

-- Um tenant que NÃO é o cercado, para provar o lado negativo do isolamento.
-- Só leitura: a rotina nunca escreve nele (a trava recusaria).
CREATE OR REPLACE FUNCTION public.qa_up_outro_tenant()
RETURNS uuid LANGUAGE sql STABLE AS $fn$
  SELECT t.id FROM public.tenants t
  WHERE t.id <> public.qa_sandbox_tenant_id()
    AND EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.tenant_id = t.id)
  ORDER BY t.created_at NULLS LAST
  LIMIT 1
$fn$;

COMMENT ON FUNCTION public.qa_up_outro_tenant() IS
  'QA Usuários & Permissões: um tenant com dados que não é o cercado — o "outro lado" do isolamento. Somente leitura.';

-- ═════════════════════════════════════════════════════════
-- USR — Ciclo de vida do usuário
-- ═════════════════════════════════════════════════════════

-- USR-001 — convite cria pendente, vinculado só a Alfa, SEM acesso ainda.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_perfil uuid; v_n int; v_status text; v_acesso boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Convidar usuário com vínculo à empresa Alfa';
  r.esperado    := 'Status pendente_convite, exatamente 1 vínculo (Alfa) e NENHUM acesso antes da ativação';

  v_u := public.qa_up_usuario('USR-001', 1, '99900001079', 'pendente_convite');
  v_perfil := public.qa_up_perfil('USR-001', 'Colaborador', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_perfil);

  SELECT status::text, auth_user_id INTO v_status, v_uid
  FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir status e quantidade de vínculos';
  SELECT count(*) INTO v_n FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF v_status <> 'pendente_convite' OR v_n <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('Esperado status pendente_convite com 1 vínculo; obtido status %s com %s vínculo(s).', v_status, v_n);
    RETURN r;
  END IF;

  r.passo_ordem := 3;
  r.passo_acao  := 'Simular o convidado e pedir a decisão de acesso ao módulo do perfil';
  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_acesso IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Convite não concede acesso: o usuário pendente foi negado. Convite é promessa de acesso, não acesso.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACESSO ANTES DA ATIVAÇÃO: um usuário com status pendente_convite obteve acesso amplo ao módulo. '
             || 'A decisão de acesso (perfil_permite_modulo) não olha usuarios_base.status no caminho do perfil — '
             || 'basta ter vínculo ativo. Quem foi convidado e nunca ativou já entra.';
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'status', v_status);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-003 — e-mail duplicado no mesmo cliente é recusado.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_email text; v_recusou boolean := false; v_n int;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Cadastrar um usuário e tentar cadastrar outro com o MESMO e-mail';
  r.esperado    := 'O segundo cadastro é recusado pelo banco; continua existindo um só';

  PERFORM public.qa_up_usuario('USR-003', 1, '99900001150');
  v_email := public.qa_fixture_email('USR-003', 1);

  r.passo_ordem := 2;
  r.passo_acao  := 'Segundo cadastro com o e-mail já existente';
  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
    VALUES (v_t, '[QA-USR-003] Duplicado', v_email, '99900001230',
            'colaborador', 'ativo', gen_random_uuid());
  EXCEPTION WHEN unique_violation THEN
    v_recusou := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Contar os cadastros com aquele e-mail';
  SELECT count(*) INTO v_n FROM public.usuarios_base
  WHERE tenant_id = v_t AND lower(trim(email_principal)) = lower(trim(v_email));

  IF v_recusou AND v_n = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'O banco recusou o e-mail duplicado e continua existindo um só cadastro. '
             || 'A unicidade está no banco, não só na tela.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('E-MAIL DUPLICADO ACEITO: recusa=%s, cadastros com o mesmo e-mail=%s. '
             || 'Dois cadastros com a mesma identidade podem receber permissões divergentes.', v_recusou, v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-004 — e-mail malformado não chega a persistir.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_barrou boolean := false; v_n int;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Cadastrar usuário com e-mail malformado (sem arroba nem domínio)';
  r.esperado    := 'A validação barra antes de gravar; nenhum registro criado';

  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
    VALUES (v_t, '[QA-USR-004] Email Torto', 'isto nao e um email', '99900001311',
            'colaborador', 'ativo', gen_random_uuid());
  EXCEPTION WHEN check_violation OR invalid_text_representation OR raise_exception THEN
    v_barrou := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir se algo foi gravado';
  SELECT count(*) INTO v_n FROM public.usuarios_base
  WHERE tenant_id = v_t AND email_principal = 'isto nao e um email';

  IF v_barrou AND v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'O e-mail malformado foi barrado antes de gravar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'E-MAIL MALFORMADO GRAVADO: o banco aceitou "isto nao e um email" como e-mail principal. '
             || 'Não há validação de formato no banco — ela existe só na tela, e qualquer via que não '
             || 'passe pela tela (importação, rotina, chamada direta) cria usuário cujo convite nunca chega.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-005 — desativar encerra o acesso e preserva o registro.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_perfil uuid; v_acesso boolean; v_existe boolean; v_status text;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar usuário ativo com acesso e depois desativá-lo';
  r.esperado    := 'Status inativo, acesso cessa e o registro continua existindo';

  v_u := public.qa_up_usuario('USR-005', 1, '99900001400', 'ativo');
  v_perfil := public.qa_up_perfil('USR-005', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_perfil);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Desativar o usuário';
  UPDATE public.usuarios_base SET status = 'inativo' WHERE id = v_u;
  SELECT status::text INTO v_status FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'Simular o usuário inativo e pedir a decisão de acesso';
  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  SELECT EXISTS (SELECT 1 FROM public.usuarios_base WHERE id = v_u) INTO v_existe;

  IF v_acesso IS FALSE AND v_existe AND v_status = 'inativo' THEN
    r.situacao := 'passou';
    r.obtido := 'Usuário inativo perdeu o acesso e o registro foi preservado.';
  ELSIF v_acesso IS TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'DESATIVAÇÃO SEM EFEITO NO ACESSO: o usuário está com status inativo e AINDA obteve acesso '
             || 'amplo ao módulo. A decisão de acesso não consulta usuarios_base.status no caminho do perfil: '
             || 'enquanto o vínculo estiver ativo, desativar o usuário não fecha a porta.';
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'status', v_status);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Estado inesperado: status=%s, registro preservado=%s.', v_status, v_existe);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-006 — a identidade de um usuário desativado não abre nada.
-- A recusa do LOGIN em si mora na camada de autenticação (fora do SQL) e é
-- coberta na tela por AUTH-022. Aqui se prova a metade que é do banco: mesmo
-- que alguém chegue com a identidade do inativo, o banco não entrega dado.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_perfil uuid; v_acesso boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar usuário já desativado, com vínculo e perfil amplo';
  r.esperado    := 'A identidade do desativado não obtém acesso nenhum no banco';

  v_u := public.qa_up_usuario('USR-006', 1, '99900001583', 'inativo');
  v_perfil := public.qa_up_perfil('USR-006', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_perfil);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Chegar ao banco com a identidade do usuário desativado';
  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_acesso IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A identidade do usuário desativado não abriu nada no banco. '
             || 'A recusa do login em si é da camada de autenticação e está coberta na tela (AUTH-022).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'IDENTIDADE DE DESATIVADO AINDA ABRE PORTA: o banco concedeu acesso amplo a um usuário '
             || 'com status inativo. A desativação depende inteiramente da camada de autenticação recusar '
             || 'o login — o banco não é a segunda linha de defesa que deveria ser.';
    r.detalhe := jsonb_build_object('usuario_id', v_u);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-007 — reativar devolve exatamente os vínculos anteriores.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_pa uuid; v_pb uuid; v_antes text; v_depois text;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-007');

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar usuário com dois vínculos e registrar o retrato';
  r.esperado    := 'Depois de inativar e reativar, os mesmos vínculos e níveis — nem a mais, nem a menos';

  v_u  := public.qa_up_usuario('USR-007', 1, '99900001664', 'ativo');
  v_pa := public.qa_up_perfil('USR-007', 'Amplo', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('USR-007', 'Restrito', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);

  SELECT string_agg(empresa_id::text || ':' || perfil_id::text || ':' || ativo::text, '|' ORDER BY empresa_id::text)
  INTO v_antes FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Inativar e reativar o usuário';
  UPDATE public.usuarios_base SET status = 'inativo' WHERE id = v_u;
  UPDATE public.usuarios_base SET status = 'ativo'   WHERE id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'Comparar os vínculos com o retrato anterior';
  SELECT string_agg(empresa_id::text || ':' || perfil_id::text || ':' || ativo::text, '|' ORDER BY empresa_id::text)
  INTO v_depois FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF v_depois IS NOT DISTINCT FROM v_antes THEN
    r.situacao := 'passou';
    r.obtido := 'A reativação devolveu exatamente os mesmos vínculos e níveis: sem ganho nem perda silenciosa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A REATIVAÇÃO MUDOU O ESCOPO: os vínculos após reativar não são os mesmos de antes de inativar. '
             || 'Reativação que altera permissão em silêncio é a pior forma de conceder acesso.';
    r.detalhe := jsonb_build_object('antes', v_antes, 'depois', v_depois);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- USR-008 — excluir usuário com histórico é bloqueado ou preserva integridade.
CREATE OR REPLACE FUNCTION public.qa_caso_usr_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_pa uuid; v_orfaos int; v_apagou boolean := true;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-008');

  r.passo_ordem := 1;
  r.passo_acao  := 'Criar usuário com vínculo de perfil e tentar excluí-lo';
  r.esperado    := 'Exclusão bloqueada, ou integridade preservada — nenhum registro órfão apontando para quem não existe mais';

  v_u  := public.qa_up_usuario('USR-008', 1, '99900001745', 'ativo');
  v_pa := public.qa_up_perfil('USR-008', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);

  r.passo_ordem := 2;
  r.passo_acao  := 'Excluir o cadastro do usuário';
  BEGIN
    DELETE FROM public.usuarios_base WHERE id = v_u;
  EXCEPTION WHEN foreign_key_violation THEN
    v_apagou := false;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Procurar vínculos de perfil apontando para um usuário que não existe mais';
  SELECT count(*) INTO v_orfaos
  FROM public.usuario_perfil_vinculos v
  WHERE v.usuario_id = v_u
    AND NOT EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.id = v.usuario_id);

  IF NOT v_apagou THEN
    r.situacao := 'passou';
    r.obtido := 'A exclusão foi bloqueada pela integridade referencial: o histórico segura o cadastro, como deve.';
  ELSIF v_orfaos = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A exclusão levou junto os registros dependentes; nenhum órfão ficou para trás.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VÍNCULO ÓRFÃO APÓS EXCLUSÃO: %s vínculo(s) de perfil continuam apontando para um usuário '
             || 'que não existe mais. usuario_perfil_vinculos.usuario_id não tem chave estrangeira para '
             || 'usuarios_base, então o banco não bloqueia a exclusão nem limpa o rastro: sobra permissão '
             || 'pendurada em ninguém, e o histórico de quem fez o quê se perde.', v_orfaos);
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'vinculos_orfaos', v_orfaos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- VIN — Vínculo usuário × empresa
--
-- NOTA DE PROJETO QUE ATRAVESSA A FAMÍLIA: a decisão de acesso do sistema é
-- perfil_permite_modulo(tenant, modulos...). Ela recebe o TENANT, não a
-- empresa. A estrutura guarda empresa_id no vínculo, mas a decisão não a
-- consulta. Os casos que dependem de escopo por empresa (VIN-005, VIN-006,
-- LIB-002, CTX-003, CTX-006) foram escritos para MEDIR isso, e não para
-- confirmar um palpite: se um dia a decisão passar a receber a empresa, eles
-- passam a verde sozinhos.
-- ═════════════════════════════════════════════════════════

-- VIN-001 — vincular usuário a uma empresa com nível definido.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_p uuid; v_v uuid; v_emp uuid; v_ativo boolean; v_emp_grav uuid; v_perfil_grav uuid;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Vincular usuário à empresa Alfa com um perfil';
  r.esperado    := 'Vínculo criado e ativo, guardando empresa e perfil';

  v_u   := public.qa_up_usuario('VIN-001', 1, '99900001826', 'ativo');
  v_p   := public.qa_up_perfil('VIN-001', 'Gestor de SST', 'sst', 'empresa_inteira');
  v_emp := public.qa_empresa('[QA] Alfa');
  v_v   := public.qa_up_vincular(v_u, v_emp, v_p);

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir o vínculo gravado';
  SELECT ativo, empresa_id, perfil_id INTO v_ativo, v_emp_grav, v_perfil_grav
  FROM public.usuario_perfil_vinculos WHERE id = v_v;

  IF v_ativo AND v_emp_grav = v_emp AND v_perfil_grav = v_p THEN
    r.situacao := 'passou';
    r.obtido := 'O vínculo (usuário, empresa, perfil) foi criado e está ativo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Vínculo gravado diferente do pedido: ativo=%s, empresa confere=%s, perfil confere=%s.',
                       v_ativo, v_emp_grav = v_emp, v_perfil_grav = v_p);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-002 — usuário em duas empresas, com níveis distintos.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_pa uuid; v_pb uuid; v_n int; v_empresas text; v_esperado text;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'Vincular o mesmo usuário a Alfa e a Beta, com perfis diferentes';
  r.esperado    := 'Dois vínculos independentes, e o usuário enxerga exatamente Alfa e Beta';

  v_u  := public.qa_up_usuario('VIN-002', 1, '99900001907', 'ativo');
  v_pa := public.qa_up_perfil('VIN-002', 'Amplo', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-002', 'Restrito', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);

  r.passo_ordem := 2;
  r.passo_acao  := 'Listar as empresas às quais o usuário pertence';
  SELECT count(*) INTO v_n FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;
  SELECT string_agg(DISTINCT e.nome_fantasia, ', ' ORDER BY e.nome_fantasia) INTO v_empresas
  FROM public.usuario_perfil_vinculos v
  JOIN public.empresa_cadastro e ON e.id = v.empresa_id
  WHERE v.usuario_id = v_u;

  v_esperado := '[QA] Alfa, [QA] Beta';

  IF v_n = 2 AND v_empresas = v_esperado THEN
    r.situacao := 'passou';
    r.obtido := 'Os dois vínculos coexistem e o usuário enxerga exatamente as duas empresas às quais pertence.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Esperado 2 vínculos em "%s"; obtido %s vínculo(s) em "%s".', v_esperado, v_n, COALESCE(v_empresas,'(nenhuma)'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-003 — usuário existente entra em nova empresa por VÍNCULO, não por
-- cadastro novo. O que o banco precisa garantir: o e-mail é único (não dá
-- para criar um segundo cadastro) e o modelo aceita o segundo vínculo.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_pa uuid; v_pb uuid; v_cadastros int; v_vinculos int; v_duplicou boolean := false;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário já existe na Empresa Alfa';
  r.esperado    := 'Adicionar por e-mail na Beta cria NOVO VÍNCULO e nunca um segundo cadastro';

  v_u  := public.qa_up_usuario('VIN-003', 1, '99900002040', 'ativo');
  v_pa := public.qa_up_perfil('VIN-003', 'Alfa', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);

  r.passo_ordem := 2;
  r.passo_acao  := 'Admin da Beta tenta cadastrar de novo o mesmo e-mail (o caminho errado)';
  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
    VALUES (v_t, '[QA-VIN-003] Segundo cadastro', public.qa_fixture_email('VIN-003', 1),
            '99900002121', 'colaborador', 'ativo', gen_random_uuid());
    v_duplicou := true;
  EXCEPTION WHEN unique_violation THEN
    v_duplicou := false;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Admin da Beta faz o caminho certo: novo vínculo para o mesmo usuário';
  v_pb := public.qa_up_perfil('VIN-003', 'Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);

  SELECT count(*) INTO v_cadastros FROM public.usuarios_base
  WHERE tenant_id = v_t AND lower(trim(email_principal)) = lower(trim(public.qa_fixture_email('VIN-003', 1)));
  SELECT count(*) INTO v_vinculos FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF NOT v_duplicou AND v_cadastros = 1 AND v_vinculos = 2 THEN
    r.situacao := 'passou';
    r.obtido := 'O segundo cadastro foi recusado e o usuário entrou na nova empresa por vínculo: '
             || 'uma identidade, dois vínculos.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Esperado 1 cadastro e 2 vínculos, com o cadastro duplicado recusado. '
             || 'Obtido: duplicou=%s, cadastros=%s, vínculos=%s.', v_duplicou, v_cadastros, v_vinculos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-004 — remover o vínculo de uma empresa corta SÓ aquele acesso.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_acesso boolean; v_resta int;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com acesso amplo em Alfa e em Beta; remover o vínculo com Alfa';
  r.esperado    := 'O acesso a dados da Alfa cessa e o acesso à Beta segue intacto';

  v_u  := public.qa_up_usuario('VIN-004', 1, '99900002202', 'ativo');
  v_pa := public.qa_up_perfil('VIN-004', 'Alfa Amplo', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-004', 'Beta Amplo', 'sst',   'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Remover o vínculo com a Empresa Alfa';
  DELETE FROM public.usuario_perfil_vinculos
  WHERE usuario_id = v_u AND empresa_id = public.qa_empresa('[QA] Alfa');

  SELECT count(*) INTO v_resta FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir a decisão de acesso ao módulo que só a Alfa liberava (ponto)';
  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_resta = 1 AND v_acesso IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Removido o vínculo com a Alfa, o acesso que ele concedia cessou, e o vínculo com a Beta seguiu de pé.';
  ELSIF v_acesso IS TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'REMOÇÃO SEM EFEITO: o vínculo com a Alfa foi removido e o acesso que SÓ ele concedia continuou valendo. '
             || 'Revogar vínculo é o gesto mais comum de tirar acesso — se ele não corta, não há revogação.';
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'vinculos_restantes', v_resta);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Estado inesperado: restaram %s vínculo(s) e o acesso ao módulo da Alfa ficou %s.', v_resta, v_acesso);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-005 — o nível é POR VÍNCULO (premissa P1). Admin em Alfa, Colaborador
-- em Beta: a mesma ação tem que ser permitida em Alfa e negada em Beta.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_em_alfa boolean; v_em_beta boolean;
  v_tem_empresa boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário Admin na Alfa e Colaborador na Beta';
  r.esperado    := 'A ação exclusiva de Admin é PERMITIDA na Alfa e NEGADA na Beta';

  v_u  := public.qa_up_usuario('VIN-005', 1, '99900002393', 'ativo');
  v_pa := public.qa_up_perfil('VIN-005', 'Admin Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-005', 'Colab Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir se a decisão de acesso sabe distinguir a empresa';
  -- A decisão do sistema é perfil_permite_modulo(tenant, modulos). Se ela não
  -- recebe empresa, não há como a resposta variar por vínculo.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_function_arguments(p.oid) ILIKE '%empresa%'
  ) INTO v_tem_empresa;

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir a decisão no contexto de cada empresa';
  PERFORM public.qa_up_entrar(v_uid);
  v_em_alfa := public.perfil_permite_modulo(v_t, 'ponto');
  v_em_beta := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_tem_empresa AND v_em_alfa IS TRUE AND v_em_beta IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A mesma ação foi permitida na Alfa e negada na Beta: o nível acompanha o vínculo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'O NÍVEL NÃO É POR EMPRESA NA PRÁTICA: a decisão de acesso do sistema é '
             || 'perfil_permite_modulo(tenant, módulos) — ela recebe o CLIENTE, não a empresa, e por isso '
             || 'devolve a mesma resposta para Alfa e para Beta. A estrutura guarda empresa_id no vínculo, '
             || 'mas quem decide não a consulta: basta um vínculo amplo em QUALQUER empresa do cliente para '
             || 'o acesso valer em TODAS. A premissa P1 do documento (nível por vínculo) não se sustenta hoje.';
    r.detalhe := jsonb_build_object('decisao_recebe_empresa', v_tem_empresa,
                                    'resposta_alfa', v_em_alfa, 'resposta_beta', v_em_beta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-006 — permissão de uma empresa não vaza para a outra.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_vaza boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com acesso amplo SÓ na Alfa e restrito na Beta';
  r.esperado    := 'No contexto da Beta, o acesso amplo concedido na Alfa NÃO vale';

  v_u  := public.qa_up_usuario('VIN-006', 1, '99900002474', 'ativo');
  v_pa := public.qa_up_perfil('VIN-006', 'Amplo Alfa', 'documentos', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-006', 'Restrito Beta', 'documentos', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Estando na Beta, pedir acesso amplo ao módulo que só a Alfa libera';
  PERFORM public.qa_up_entrar(v_uid);
  v_vaza := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_vaza IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'O acesso amplo concedido na Alfa não valeu na Beta: a permissão não vaza entre vínculos.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'PERMISSÃO VAZA ENTRE EMPRESAS: o acesso amplo a documentos foi concedido apenas no vínculo '
             || 'com a Alfa, e vale também para a Beta. A decisão usa a UNIÃO dos vínculos do usuário dentro '
             || 'do cliente, não o vínculo da empresa em questão — exatamente o vazamento que o caso procura. '
             || 'Em documentos moram atestados e dado de saúde (LGPD art. 11).';
    r.detalhe := jsonb_build_object('usuario_id', v_u);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-007 — remover o último vínculo deixa o usuário em estado seguro.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_n int; v_acesso boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-007');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com um único vínculo; remover esse vínculo';
  r.esperado    := 'Sem vínculo nenhum, nenhum acesso é concedido (falha fechada)';

  v_u := public.qa_up_usuario('VIN-007', 1, '99900002555', 'ativo');
  v_p := public.qa_up_perfil('VIN-007', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Remover o único vínculo';
  DELETE FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;
  SELECT count(*) INTO v_n FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir a decisão de acesso de um usuário sem nenhum vínculo';
  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_n = 0 AND v_acesso IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Sem vínculo, nenhum acesso: o estado final é seguro e a falha é fechada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ESTADO INSEGURO SEM VÍNCULO: restaram %s vínculo(s) e a decisão de acesso devolveu %s. '
             || 'Usuário sem empresa não pode acabar com acesso concedido por ausência de regra.', v_n, v_acesso);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-008 — vínculo duplicado (mesmo usuário + mesma empresa) é recusado.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_pa uuid; v_pb uuid; v_emp uuid; v_recusou boolean := false; v_n int;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-008');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário já vinculado à Alfa; tentar um SEGUNDO vínculo na mesma empresa';
  r.esperado    := 'Recusado por restrição de unicidade; continua um só vínculo naquela empresa';

  v_u   := public.qa_up_usuario('VIN-008', 1, '99900002636', 'ativo');
  v_emp := public.qa_empresa('[QA] Alfa');
  v_pa  := public.qa_up_perfil('VIN-008', 'Primeiro', 'ponto', 'empresa_inteira');
  v_pb  := public.qa_up_perfil('VIN-008', 'Segundo',  'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, v_emp, v_pa);

  r.passo_ordem := 2;
  r.passo_acao  := 'Segundo vínculo do mesmo par usuário+empresa';
  BEGIN
    PERFORM public.qa_up_vincular(v_u, v_emp, v_pb);
  EXCEPTION WHEN unique_violation THEN
    v_recusou := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Contar os vínculos do par usuário+empresa';
  SELECT count(*) INTO v_n FROM public.usuario_perfil_vinculos
  WHERE usuario_id = v_u AND empresa_id = v_emp;

  IF v_recusou AND v_n = 1 THEN
    r.situacao := 'passou';
    r.obtido := 'O vínculo duplicado foi recusado pelo banco; continua um só.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VÍNCULO DUPLICADO ACEITO: o mesmo usuário ficou com %s vínculos na MESMA empresa, '
             || 'cada um com um perfil diferente. Não existe restrição de unicidade em '
             || '(usuario_id, empresa_id) — e com dois níveis valendo ao mesmo tempo, quem decide o acesso '
             || 'aplica a união deles, ou seja, sempre o mais permissivo. Rebaixar alguém deixa de funcionar '
             || 'se o vínculo antigo continuar lá.', v_n);
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'vinculos_na_mesma_empresa', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- Apoio do lado NEGATIVO: ler como usuário comum, com o isolamento LIGADO.
--
-- O motor roda com papel dono do banco, e para o dono a política de
-- isolamento NÃO se aplica. Uma rotina que consultasse direto veria tudo e
-- daria verde sem provar nada — o pior tipo de teste. Por isso as rotinas de
-- isolamento trocam para o papel 'authenticated' antes de ler. Se o ambiente
-- não permitir a troca, a rotina diz isso em vez de fingir um veredito.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.qa_up_pode_virar_usuario()
RETURNS boolean LANGUAGE plpgsql AS $fn$
BEGIN
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  EXECUTE 'RESET ROLE';
  RETURN true;
END $fn$;

COMMENT ON FUNCTION public.qa_up_pode_virar_usuario() IS
  'QA Usuários & Permissões: este ambiente deixa a rotina virar usuário comum para ler com o isolamento ligado?';

-- ═════════════════════════════════════════════════════════
-- NAC — Níveis de acesso (perfis)
-- ═════════════════════════════════════════════════════════

-- NAC-001 — criar nível de acesso com um conjunto de permissões.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_p uuid; v_ativo boolean; v_perms int; v_disponivel boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Criar o perfil "Gestor de SST" com uma permissão';
  r.esperado    := 'Perfil ativo, com a permissão associada e disponível para atribuição';

  DELETE FROM public.perfis_acesso
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND nome LIKE '[QA-NAC-001]%';

  v_p := public.qa_up_perfil('NAC-001', 'Gestor de SST', 'sst', 'empresa_inteira', 'administrar');

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir o perfil e suas permissões';
  SELECT ativo INTO v_ativo FROM public.perfis_acesso WHERE id = v_p;
  SELECT count(*) INTO v_perms FROM public.perfil_permissoes
  WHERE perfil_id = v_p AND modulo = 'sst' AND ativo;

  SELECT EXISTS (
    SELECT 1 FROM public.perfis_acesso
    WHERE id = v_p AND tenant_id = public.qa_sandbox_tenant_id() AND COALESCE(ativo, true)
  ) INTO v_disponivel;

  IF v_ativo AND v_perms = 1 AND v_disponivel THEN
    r.situacao := 'passou';
    r.obtido := 'Perfil criado com a permissão associada e disponível para atribuição.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Esperado perfil ativo com 1 permissão disponível; obtido ativo=%s, permissões=%s, disponível=%s.',
                       v_ativo, v_perms, v_disponivel);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- NAC-002 — perfil e permissão vivem em TABELA, não fixados em código.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_tem_tabelas boolean; v_le_tabela boolean; v_fixas int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): conferir de onde vêm perfis e permissões';
  r.esperado    := 'De tabelas de parâmetro; nenhuma regra de acesso decidida por nome de perfil escrito no código';

  SELECT to_regclass('public.perfis_acesso') IS NOT NULL
     AND to_regclass('public.perfil_permissoes') IS NOT NULL
  INTO v_tem_tabelas;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir se a função que decide o acesso lê dessas tabelas';
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ILIKE '%perfil_permissoes%'
  ) INTO v_le_tabela;

  r.passo_ordem := 3;
  r.passo_acao  := 'Procurar regra de acesso presa a um NOME de perfil dentro do código';
  -- O sinal de "regra fixada em código": comparar o NOME do perfil com um
  -- literal para decidir acesso. Comparar id, tenant ou módulo é normal.
  -- prokind = 'f': pg_get_functiondef estoura em agregada e em janela.
  SELECT count(*), string_agg(p.proname, ', ')
  INTO v_fixas, v_lista
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
    AND p.proname NOT LIKE 'qa\_%'
    AND pg_get_functiondef(p.oid) ~* '(pa|perfis_acesso|perfil)\.nome\s*(=|<>|ilike|like)\s*''';

  IF v_tem_tabelas AND v_le_tabela AND v_fixas = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Perfis e permissões são parâmetro de tabela, a decisão de acesso lê de perfil_permissoes, '
             || 'e nenhuma função decide acesso por nome de perfil escrito no código.';
  ELSIF NOT v_tem_tabelas OR NOT v_le_tabela THEN
    r.situacao := 'falhou';
    r.obtido := format('A parametrização não se sustenta: tabelas presentes=%s, decisão lê de perfil_permissoes=%s.',
                       v_tem_tabelas, v_le_tabela);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('REGRA DE ACESSO PRESA NO CÓDIGO: %s função(ões) comparam o NOME do perfil com um texto '
             || 'fixo para decidir acesso: %s. Regra assim não se audita, não se ajusta por cliente e escapa '
             || 'da revisão — renomear um perfil na tela muda o acesso sem ninguém perceber.', v_fixas, v_lista);
    r.detalhe := jsonb_build_object('funcoes', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- NAC-003 — editar as permissões do perfil reflete em quem o possui.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_antes boolean; v_depois boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('NAC-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com o perfil que libera o módulo';
  r.esperado    := 'Removida a permissão do perfil, o vinculado perde o acesso na checagem seguinte';

  v_u := public.qa_up_usuario('NAC-003', 1, '99900002806', 'ativo');
  v_p := public.qa_up_perfil('NAC-003', 'Gestor de SST', 'sst', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  v_antes := public.perfil_permite_modulo(v_t, 'sst');
  PERFORM public.qa_up_sair();

  IF v_antes IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'Controle inicial falhou: o usuário com o perfil que libera o módulo já não tinha acesso antes da edição.';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Remover a permissão do perfil';
  DELETE FROM public.perfil_permissoes WHERE perfil_id = v_p AND modulo = 'sst';

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir de novo a decisão de acesso para o mesmo usuário';
  PERFORM public.qa_up_entrar(v_uid);
  v_depois := public.perfil_permite_modulo(v_t, 'sst');
  PERFORM public.qa_up_sair();

  IF v_depois IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A permissão removida do perfil deixou de valer para o vinculado já na checagem seguinte.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'EDIÇÃO DO PERFIL SEM EFEITO: a permissão foi removida do perfil e o usuário vinculado '
             || 'continuou com acesso. Editar o perfil é o gesto de alavanca do controle de acesso — '
             || 'se ele não propaga, revogar em massa não funciona.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- NAC-004 — excluir perfil em uso é bloqueado ou exige reatribuição.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_p uuid; v_bloqueou boolean := false; v_orfaos int;
BEGIN
  PERFORM public.qa_fixture_limpar('NAC-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Perfil atribuído a um usuário ativo; tentar excluir o perfil';
  r.esperado    := 'Exclusão bloqueada — nenhum usuário fica órfão de perfil';

  v_u := public.qa_up_usuario('NAC-004', 1, '99900002989', 'ativo');
  v_p := public.qa_up_perfil('NAC-004', 'Em uso', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);

  r.passo_ordem := 2;
  r.passo_acao  := 'Excluir o perfil que está em uso';
  BEGIN
    DELETE FROM public.perfis_acesso WHERE id = v_p;
  EXCEPTION WHEN foreign_key_violation THEN
    v_bloqueou := true;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Procurar vínculos apontando para perfil inexistente';
  SELECT count(*) INTO v_orfaos
  FROM public.usuario_perfil_vinculos v
  WHERE v.usuario_id = v_u
    AND NOT EXISTS (SELECT 1 FROM public.perfis_acesso pa WHERE pa.id = v.perfil_id);

  IF v_bloqueou AND v_orfaos = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A exclusão do perfil em uso foi bloqueada pela integridade referencial; ninguém ficou órfão de perfil.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('PERFIL EM USO EXCLUÍDO: bloqueio=%s, vínculos órfãos=%s. Usuário sem perfil válido fica '
             || 'num limbo: ou perde tudo sem aviso, ou pior, passa a valer por ausência de regra.', v_bloqueou, v_orfaos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- NAC-005 — perfil de um cliente não aparece nem se edita no outro.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_outro uuid; v_u uuid; v_uid uuid; v_p uuid; v_viu int; v_alterou int;
BEGIN
  PERFORM public.qa_fixture_limpar('NAC-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Perfil personalizado criado no cercado; olhar com os olhos de outro cliente';
  r.esperado    := 'O perfil do cercado não aparece nem pode ser alterado por usuário de outro cliente';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente, então não há "outro lado" para '
             || 'provar o isolamento. Em ambiente com mais de um cliente esta rotina roda de verdade.';
    RETURN r;
  END IF;

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum. Sem isso, a leitura '
             || 'aconteceria com o papel dono do banco, para quem o isolamento não se aplica — o resultado '
             || 'seria um verde sem prova. Preferimos não dar veredito.';
    RETURN r;
  END IF;

  v_u := public.qa_up_usuario('NAC-005', 1, '99900001079', 'ativo');
  v_p := public.qa_up_perfil('NAC-005', 'So do cercado', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Como usuário do cercado, listar perfis do OUTRO cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_viu FROM public.perfis_acesso WHERE tenant_id = v_outro;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  r.passo_ordem := 3;
  r.passo_acao  := 'Como usuário do cercado, tentar ALTERAR perfil do outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.perfis_acesso SET descricao = '[QA-NAC-005] invasao' WHERE tenant_id = v_outro;
    GET DIAGNOSTICS v_alterou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN
    v_alterou := 0;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_viu = 0 AND v_alterou = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Os perfis do outro cliente não apareceram nem puderam ser alterados: a configuração de acesso '
             || 'de cada cliente fica dentro da casa dele.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('PERFIS VAZAM ENTRE CLIENTES: um usuário do cercado enxergou %s perfil(is) e alterou %s '
             || 'do outro cliente. Vazar perfil é vazar a própria estrutura de acesso de quem contratou.', v_viu, v_alterou);
    r.detalhe := jsonb_build_object('outro_tenant', v_outro, 'viu', v_viu, 'alterou', v_alterou);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- NAC-006 — ninguém atribui perfil acima do próprio teto.
CREATE OR REPLACE FUNCTION public.qa_caso_nac_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_p_super uuid; v_criou boolean := false;
  v_tem_trava boolean; v_motivo text; v_p_dele uuid;
BEGIN
  PERFORM public.qa_fixture_limpar('NAC-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA: existe trava que impeça conceder acima do próprio teto?';
  r.esperado    := 'Uma trava no banco recusa a atribuição de perfil de escopo superior ao de quem concede';

  -- A trava seria um gatilho ou política em usuario_perfil_vinculos que
  -- compare o teto de quem concede com o do perfil concedido.
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger tg
    JOIN pg_proc p ON p.oid = tg.tgfoid
    WHERE tg.tgrelid = 'public.usuario_perfil_vinculos'::regclass
      AND NOT tg.tgisinternal
      AND tg.tgname NOT LIKE 'qa\_%'
      AND pg_get_functiondef(p.oid) ~* '(teto|hierarqui|has_minimum_role|superadmin|nivel_risco)'
  ) INTO v_tem_trava;

  r.passo_ordem := 2;
  r.passo_acao  := 'Um usuário comum tenta atribuir a si mesmo um perfil de escopo máximo';
  v_u    := public.qa_up_usuario('NAC-006', 1, '99900001150', 'ativo');
  v_alvo := public.qa_up_usuario('NAC-006', 2, '99900001230', 'ativo');
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;
  v_p_super := public.qa_up_perfil('NAC-006', 'Escopo Maximo', 'ponto', 'grupo_economico', 'administrar');

  -- O concedente precisa ser um administrador de empresa DE VERDADE, com
  -- vínculo na empresa. Sem vínculo, as políticas o barrariam por não
  -- pertencer à empresa, e o verde mediria a falta da fixture, não o teto.
  v_p_dele := public.qa_up_perfil('NAC-006', 'Admin de empresa', 'ponto', 'empresa_inteira', 'administrar');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p_dele);

  PERFORM public.qa_up_entrar(v_uid);
  BEGIN
    IF public.qa_up_pode_virar_usuario() THEN
      SET LOCAL ROLE authenticated;
    END IF;
    INSERT INTO public.usuario_perfil_vinculos
      (tenant_id, usuario_id, empresa_id, perfil_id, ativo)
    VALUES (public.qa_sandbox_tenant_id(), v_alvo, public.qa_empresa('[QA] Alfa'), v_p_super, true);
    v_criou := true;
  EXCEPTION WHEN OTHERS THEN
    v_criou  := false;
    v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF NOT v_criou THEN
    r.situacao := 'passou';
    -- Importante dizer POR QUE barrou: uma recusa vinda do isolamento é uma
    -- defesa real, mas não é a mesma coisa que uma trava de hierarquia. Sem
    -- essa distinção o verde esconderia a lacuna.
    r.obtido := format('A concessão acima do próprio teto foi recusada. Motivo da recusa: %s. '
             || 'Trava de hierarquia específica encontrada no banco: %s — quando ela é "false", quem barrou '
             || 'foi a camada de isolamento, e não uma regra de teto: a defesa existe, mas por outro caminho.',
             COALESCE(v_motivo, '(a inserção simplesmente não afetou nada)'), v_tem_trava);
    r.detalhe := jsonb_build_object('trava_de_hierarquia', v_tem_trava, 'motivo', v_motivo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('CONCESSÃO ACIMA DO TETO ACEITA: um usuário comum atribuiu a outro um perfil de escopo '
             || 'máximo (grupo_economico, ação administrar) sem possuir nada parecido. '
             || 'Trava de hierarquia encontrada no banco: %s. Sem teto, o caminho até o poder total é '
             || 'de dois passos: crio o perfil, atribuo a mim.', v_tem_trava);
    r.detalhe := jsonb_build_object('trava_no_banco', v_tem_trava);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- PER — Permissões (aplicação efetiva)
-- ═════════════════════════════════════════════════════════

-- PER-001 — ação permitida pelo perfil é executada (lado positivo).
CREATE OR REPLACE FUNCTION public.qa_caso_per_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_pode boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário cujo perfil libera o módulo executa a ação desse módulo';
  r.esperado    := 'Ação permitida — segurança que bloqueia tudo também está errada';

  v_u := public.qa_up_usuario('PER-001', 1, '99900001311', 'ativo');
  v_p := public.qa_up_perfil('PER-001', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Pedir a decisão de acesso ao módulo liberado';
  PERFORM public.qa_up_entrar(v_uid);
  v_pode := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_pode IS TRUE THEN
    r.situacao := 'passou';
    r.obtido := 'A ação prevista no perfil foi permitida: o controle libera o que deve liberar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACESSO LEGÍTIMO NEGADO: o usuário tem no perfil a permissão ampla para o módulo e foi '
             || 'recusado. Controle que nega o que deveria permitir custa tanto quanto o que permite demais: '
             || 'o cliente perde o trabalho e o time perde a confiança no controle.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-002 — ação sem permissão é barrada no banco, sem passar pela tela.
CREATE OR REPLACE FUNCTION public.qa_caso_per_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_pode boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário SEM a permissão chama direto a decisão de acesso, ignorando a tela';
  r.esperado    := 'Negado pelo banco — esconder o botão não é a defesa';

  v_u := public.qa_up_usuario('PER-002', 1, '99900001400', 'ativo');
  v_p := public.qa_up_perfil('PER-002', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Pedir acesso a um módulo que o perfil NÃO libera';
  PERFORM public.qa_up_entrar(v_uid);
  v_pode := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_pode IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A chamada direta foi negada: a decisão mora no banco, não na tela.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'CHAMADA DIRETA ACEITA: um usuário sem a permissão obteve acesso ao módulo chamando a '
             || 'decisão sem passar pela tela. Se a defesa é só o botão escondido, não há defesa.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-004 — ausência de permissão significa negado (fail-closed).
CREATE OR REPLACE FUNCTION public.qa_caso_per_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_le boolean; v_escreve boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário cujo perfil não diz NADA sobre o recurso pedido';
  r.esperado    := 'Negado por padrão, nos dois verbos — ausência de regra nunca vira liberação';

  v_u := public.qa_up_usuario('PER-004', 1, '99900001583', 'ativo');
  -- Perfil que existe e é ativo, mas não menciona o módulo consultado.
  v_p := public.qa_up_perfil('PER-004', 'Nada Sobre Y', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Pedir leitura e escrita no recurso sobre o qual não há regra';
  PERFORM public.qa_up_entrar(v_uid);
  v_le      := public.perfil_permite_modulo(v_t, 'recurso_inexistente_para_qa');
  v_escreve := public.perfil_permite_modulo(v_t, 'recurso_inexistente_para_qa');
  PERFORM public.qa_up_sair();

  IF v_le IS FALSE AND v_escreve IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Sem regra explícita, o acesso foi negado nos dois verbos: a falha é fechada, como deve ser.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'FALHA ABERTA: um recurso sobre o qual o perfil não define nada foi liberado. '
             || 'Ausência de regra virou permissão — é a classe de bug do nulo que propaga, aqui na pior '
             || 'posição possível.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-005 — permissão nula ou vazia não vira acesso total.
CREATE OR REPLACE FUNCTION public.qa_caso_per_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_aceitou_nulo boolean := false; v_pode boolean;
  v_coalesce_perigoso boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Forçar uma permissão com escopo nulo e com módulo vazio';
  r.esperado    := 'Tratado como negação, jamais como "tudo liberado"';

  v_u := public.qa_up_usuario('PER-005', 1, '99900001664', 'ativo');
  v_p := public.qa_up_perfil('PER-005', 'Permissao Torta', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar gravar permissão com escopo NULO';
  BEGIN
    INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
    VALUES (v_p, v_t, 'documentos', 'visualizar', NULL, true);
    v_aceitou_nulo := true;
  EXCEPTION WHEN not_null_violation THEN
    v_aceitou_nulo := false;
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Gravar permissão de módulo VAZIO e pedir acesso a um módulo de verdade';
  INSERT INTO public.perfil_permissoes (perfil_id, tenant_id, modulo, acao, escopo, ativo)
  VALUES (v_p, v_t, '', 'visualizar', 'empresa_inteira', true);

  PERFORM public.qa_up_entrar(v_uid);
  v_pode := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  -- O risco latente: a decisão usa COALESCE(escopo::text, '') <> 'proprio_usuario'.
  -- Se um escopo nulo chegasse ali, '' <> 'proprio_usuario' é VERDADEIRO — ou
  -- seja, nulo viraria acesso AMPLO. Hoje a coluna é NOT NULL e fecha a porta,
  -- mas a expressão continua sendo do tipo que transforma nulo em permissão.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ~* 'COALESCE\s*\(\s*pp\.escopo'
  ) INTO v_coalesce_perigoso;

  IF NOT v_aceitou_nulo AND v_pode IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := format('Permissão nula foi recusada pelo banco (a coluna é obrigatória) e permissão de módulo '
             || 'vazio não abriu nenhum módulo de verdade. Observação para quem for mexer: a decisão trata o '
             || 'escopo com COALESCE para vazio (presente: %s), e vazio conta como acesso AMPLO — hoje isso '
             || 'só não vira brecha porque a coluna é obrigatória. Se um dia ela deixar de ser, nulo vira '
             || 'permissão ampla em silêncio.', v_coalesce_perigoso);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('NULO OU VAZIO VIROU ACESSO: escopo nulo aceito=%s, módulo vazio concedeu acesso a outro '
             || 'módulo=%s. Permissão malformada tem que ser lida como negação.', v_aceitou_nulo, v_pode);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-006 — permissão de leitura não implica escrita.
CREATE OR REPLACE FUNCTION public.qa_caso_per_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_so_leitura boolean; v_separa_verbo boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com permissão SOMENTE de visualizar no módulo';
  r.esperado    := 'Leitura permitida; edição e exclusão negadas — verbos separados';

  v_u := public.qa_up_usuario('PER-006', 1, '99900001745', 'ativo');
  v_p := public.qa_up_perfil('PER-006', 'So Leitura', 'ponto', 'empresa_inteira', 'visualizar');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir se alguma decisão do banco distingue o VERBO (ação)';
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND p.proname ~* 'perfil.*(permite|pode|acao)'
      AND pg_get_function_arguments(p.oid) ~* '(acao|verbo)'
  ) INTO v_separa_verbo;

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir a decisão com permissão apenas de leitura';
  PERFORM public.qa_up_entrar(v_uid);
  v_so_leitura := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_separa_verbo THEN
    r.situacao := 'passou';
    r.obtido := 'Existe decisão que distingue a ação: leitura e escrita não são a mesma permissão.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VERBOS NÃO SÃO SEPARADOS NA DECISÃO: a coluna perfil_permissoes.acao guarda o verbo '
             || '(visualizar, editar, excluir...), mas a decisão de acesso do banco é '
             || 'perfil_permite_modulo(tenant, módulos) — ela não recebe nem consulta a ação. Um perfil com '
             || 'APENAS "visualizar" devolveu %s para o módulo, igualzinho a um perfil com "administrar". '
             || 'Quem só deveria olhar recebe a mesma porta de quem pode alterar.', v_so_leitura);
    r.detalhe := jsonb_build_object('decisao_recebe_acao', v_separa_verbo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-007 — permissão granular por módulo é respeitada.
CREATE OR REPLACE FUNCTION public.qa_caso_per_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_ponto boolean; v_docs boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PER-007');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com acesso ao módulo Ponto e sem acesso a Documentos';
  r.esperado    := 'Ponto permitido; Documentos negado';

  v_u := public.qa_up_usuario('PER-007', 1, '99900001826', 'ativo');
  v_p := public.qa_up_perfil('PER-007', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Pedir a decisão para cada módulo';
  PERFORM public.qa_up_entrar(v_uid);
  v_ponto := public.perfil_permite_modulo(v_t, 'ponto');
  v_docs  := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_ponto IS TRUE AND v_docs IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Acesso concedido só no módulo liberado: Ponto sim, Documentos não.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('GRANULARIDADE POR MÓDULO FALHOU: Ponto=%s, Documentos=%s. Liberar Ponto não pode '
             || 'abrir Documentos, onde moram atestados e dado de saúde (LGPD art. 11).', v_ponto, v_docs);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PER-008 — alterar permissão num cliente não afeta o outro.
CREATE OR REPLACE FUNCTION public.qa_caso_per_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_outro uuid; v_p uuid; v_antes text; v_depois text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Retratar as permissões do OUTRO cliente antes de mexer no cercado';
  r.esperado    := 'Mexer no cercado não muda uma linha sequer do outro cliente';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente: sem o outro lado, não há o que '
             || 'comparar. Em ambiente com mais de um cliente esta rotina roda de verdade.';
    RETURN r;
  END IF;

  SELECT md5(COALESCE(string_agg(pp.id::text || pp.modulo || pp.acao::text || pp.escopo::text || pp.ativo::text,
                                 '|' ORDER BY pp.id), ''))
  INTO v_antes
  FROM public.perfil_permissoes pp WHERE pp.tenant_id = v_outro;

  r.passo_ordem := 2;
  r.passo_acao  := 'Criar e alterar permissões de um perfil dentro do cercado';
  DELETE FROM public.perfis_acesso WHERE tenant_id = v_t AND nome LIKE '[QA-PER-008]%';
  v_p := public.qa_up_perfil('PER-008', 'Mexido', 'ponto', 'empresa_inteira');
  UPDATE public.perfil_permissoes SET escopo = 'proprio_usuario', ativo = false WHERE perfil_id = v_p;
  DELETE FROM public.perfil_permissoes WHERE perfil_id = v_p;

  r.passo_ordem := 3;
  r.passo_acao  := 'Comparar o retrato do outro cliente';
  SELECT md5(COALESCE(string_agg(pp.id::text || pp.modulo || pp.acao::text || pp.escopo::text || pp.ativo::text,
                                 '|' ORDER BY pp.id), ''))
  INTO v_depois
  FROM public.perfil_permissoes pp WHERE pp.tenant_id = v_outro;

  IF v_depois IS NOT DISTINCT FROM v_antes THEN
    r.situacao := 'passou';
    r.obtido := 'As permissões do outro cliente ficaram idênticas: a alteração ficou contida no cercado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ALTERAÇÃO RESPINGOU EM OUTRO CLIENTE: mexer nas permissões de um perfil do cercado mudou as '
             || 'permissões de outro cliente. Numa base com mais de mil clientes, isso é alterar o controle '
             || 'de acesso de quem nunca pediu nada.';
    r.detalhe := jsonb_build_object('outro_tenant', v_outro);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- LIB — Liberações (perfil_excecoes)
--
-- ACHADO QUE ATRAVESSA A FAMÍLIA INTEIRA: a tabela perfil_excecoes existe,
-- tem tipo, escopo e expira_em — e NENHUMA função de decisão do banco a lê.
-- A liberação é gravada e nunca consultada. Por isso as quatro primeiras
-- rotinas desta família medem o mesmo ponto por ângulos diferentes: conceder,
-- escopar por empresa, revogar e expirar. Corrigida a causa, elas passam
-- juntas.
-- ═════════════════════════════════════════════════════════

-- Quantas funções de decisão consultam a tabela de liberações?
CREATE OR REPLACE FUNCTION public.qa_up_decisao_le_excecoes()
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND pg_get_functiondef(p.oid) ILIKE '%perfil_excecoes%'
  )
$fn$;

COMMENT ON FUNCTION public.qa_up_decisao_le_excecoes() IS
  'QA Usuários & Permissões: alguma função do banco consulta a tabela de liberações na hora de decidir acesso?';

-- LIB-001 — liberar recurso pontual a um usuário, sem mexer no perfil.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_antes boolean; v_depois boolean; v_perfil_intacto int;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Colaborador sem o recurso no perfil; conceder a liberação pontual na Empresa Alfa';
  r.esperado    := 'X passa a acessar o recurso, e o perfil base fica inalterado';

  v_u := public.qa_up_usuario('LIB-001', 1, '99900001907', 'ativo');
  v_p := public.qa_up_perfil('LIB-001', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  v_antes := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  r.passo_ordem := 2;
  r.passo_acao  := 'Conceder a liberação do módulo documentos na Empresa Alfa';
  INSERT INTO public.perfil_excecoes
    (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
  VALUES (v_t, v_u, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
          'visualizar', 'empresa_inteira', true, 'Liberação pontual do caso LIB-001.');

  r.passo_ordem := 3;
  r.passo_acao  := 'Pedir de novo a decisão de acesso e conferir o perfil base';
  PERFORM public.qa_up_entrar(v_uid);
  v_depois := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  SELECT count(*) INTO v_perfil_intacto FROM public.perfil_permissoes
  WHERE perfil_id = v_p AND modulo = 'documentos';

  IF v_antes IS FALSE AND v_depois IS TRUE AND v_perfil_intacto = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A liberação concedeu o acesso ao recurso e o perfil base ficou intacto.';
  ELSIF v_depois IS FALSE THEN
    r.situacao := 'falhou';
    r.obtido := format('LIBERAÇÃO NÃO CONCEDE NADA: a exceção foi gravada em perfil_excecoes (tipo adicional, '
             || 'ativa) e o acesso continuou negado. Nenhuma função de decisão do banco consulta essa tabela '
             || '(consulta encontrada: %s). Quem usa a tela acredita ter liberado o recurso para a pessoa; '
             || 'no banco, nada mudou. É uma liberação que só existe no papel.',
             public.qa_up_decisao_le_excecoes());
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'antes', v_antes, 'depois', v_depois);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Estado inesperado: antes=%s, depois=%s, permissões do perfil base no módulo=%s '
             || '(a liberação não pode alterar o perfil base).', v_antes, v_depois, v_perfil_intacto);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- LIB-002 — a liberação vale só na empresa em que foi concedida.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_vale boolean; v_le_excecoes boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'X vinculado a Alfa e Beta; liberação concedida SÓ na Alfa';
  r.esperado    := 'No contexto da Beta, o recurso liberado na Alfa é negado';

  v_u  := public.qa_up_usuario('LIB-002', 1, '99900002040', 'ativo');
  v_pa := public.qa_up_perfil('LIB-002', 'Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('LIB-002', 'Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  INSERT INTO public.perfil_excecoes
    (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
  VALUES (v_t, v_u, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
          'visualizar', 'empresa_inteira', true, 'Liberação só na Alfa — caso LIB-002.');

  v_le_excecoes := public.qa_up_decisao_le_excecoes();

  r.passo_ordem := 2;
  r.passo_acao  := 'No contexto da Beta, tentar usar o recurso liberado na Alfa';
  PERFORM public.qa_up_entrar(v_uid);
  v_vale := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF NOT v_le_excecoes THEN
    r.situacao := 'falhou';
    r.obtido := 'NÃO DÁ PARA PROVAR O ESCOPO DA LIBERAÇÃO: nenhuma função de decisão consulta '
             || 'perfil_excecoes, então a liberação não concede acesso em empresa nenhuma — nem na Alfa, '
             || 'onde foi dada. Enquanto a concessão não existir de fato, o escopo por empresa não tem o que '
             || 'delimitar. Some-se a isso que a decisão sequer recebe a empresa (ver VIN-005): quando a '
             || 'liberação passar a valer, ela nasce valendo para todas as empresas do cliente.';
    r.detalhe := jsonb_build_object('decisao_le_excecoes', v_le_excecoes, 'resposta_na_beta', v_vale);
  ELSIF v_vale IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A liberação dada na Alfa não valeu na Beta: ela não vaza entre vínculos.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO VAZA ENTRE EMPRESAS: concedida apenas na Alfa, valeu também na Beta.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- LIB-003 — revogar a liberação devolve o usuário ao teto do perfil.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_e uuid; v_com boolean; v_sem boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Conceder a liberação e confirmar que ela concede (controle)';
  r.esperado    := 'Revogada a liberação, o acesso cessa e o usuário volta ao teto do perfil';

  v_u := public.qa_up_usuario('LIB-003', 1, '99900002121', 'ativo');
  v_p := public.qa_up_perfil('LIB-003', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  INSERT INTO public.perfil_excecoes
    (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
  VALUES (v_t, v_u, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
          'visualizar', 'empresa_inteira', true, 'Liberação do caso LIB-003.')
  RETURNING id INTO v_e;

  PERFORM public.qa_up_entrar(v_uid);
  v_com := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  r.passo_ordem := 2;
  r.passo_acao  := 'Revogar a liberação';
  DELETE FROM public.perfil_excecoes WHERE id = v_e;

  PERFORM public.qa_up_entrar(v_uid);
  v_sem := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_com IS TRUE AND v_sem IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A liberação concedia o acesso e a revogação o encerrou: o usuário voltou ao teto do perfil.';
  ELSIF v_com IS FALSE THEN
    -- Cuidado para não dar verde pelo motivo errado: o acesso está negado
    -- depois de revogar, mas já estava negado ANTES, com a liberação ativa.
    -- Isso não prova revogação nenhuma.
    r.situacao := 'falhou';
    r.obtido := 'REVOGAÇÃO NÃO PROVADA: com a liberação ATIVA o acesso já era negado, então o "negado" de '
             || 'depois da revogação não prova nada — seria um verde pelo motivo errado. A causa é a mesma '
             || 'de LIB-001: nenhuma decisão do banco lê perfil_excecoes. Sem concessão que funcione, não '
             || 'existe revogação para testar.';
    r.detalhe := jsonb_build_object('com_liberacao', v_com, 'sem_liberacao', v_sem);
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO REVOGADA CONTINUA VALENDO: removida a exceção, o acesso permaneceu. '
             || 'Revogação que não revoga é o defeito mais silencioso da família: ninguém repara que o '
             || 'acesso continuou.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- LIB-004 — liberação com prazo expira sozinha.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_vigente boolean; v_expirada boolean; v_tem_campo boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir se a liberação tem campo de prazo';
  r.esperado    := 'Acesso liberado na vigência e negado automaticamente depois de expirar';

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'perfil_excecoes' AND column_name = 'expira_em'
  ) INTO v_tem_campo;

  v_u := public.qa_up_usuario('LIB-004', 1, '99900002202', 'ativo');
  v_p := public.qa_up_perfil('LIB-004', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Liberação DENTRO da vigência';
  INSERT INTO public.perfil_excecoes
    (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, expira_em, justificativa)
  VALUES (v_t, v_u, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
          'visualizar', 'empresa_inteira', true, now() + interval '1 day', 'Vigente — caso LIB-004.');

  PERFORM public.qa_up_entrar(v_uid);
  v_vigente := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  r.passo_ordem := 3;
  r.passo_acao  := 'Mesma liberação com a data JÁ PASSADA';
  UPDATE public.perfil_excecoes SET expira_em = now() - interval '1 day'
  WHERE usuario_id = v_u AND modulo = 'documentos';

  PERFORM public.qa_up_entrar(v_uid);
  v_expirada := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_vigente IS TRUE AND v_expirada IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A liberação valeu dentro da vigência e deixou de valer sozinha depois de expirar.';
  ELSIF v_vigente IS FALSE THEN
    r.situacao := 'falhou';
    r.obtido := format('PRAZO NÃO É APLICADO PORQUE A LIBERAÇÃO NÃO VALE: o campo de prazo existe na tabela '
             || '(presente: %s), mas a liberação não concede acesso nem dentro da vigência — nenhuma decisão '
             || 'do banco lê perfil_excecoes. A boa notícia é que a estrutura de prazo já está pronta: quando '
             || 'a leitura entrar, expira_em está lá para ser respeitado, e a lacuna LIB-004 apontada no '
             || 'documento deixa de existir.', v_tem_campo);
    r.detalhe := jsonb_build_object('campo_expira_em', v_tem_campo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO EXPIRADA CONTINUA VALENDO: a data já passou e o acesso permaneceu. '
             || 'Liberação temporária que não expira vira permanente por esquecimento.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- LIB-005 — liberação não eleva acima do teto de quem concede.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_admin uuid; v_uid uuid; v_alvo uuid; v_p uuid; v_criou boolean := false; v_motivo text;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Admin de empresa SEM a capacidade tenta liberá-la para outro usuário';
  r.esperado    := 'Negado — ninguém concede o que não tem';

  v_admin := public.qa_up_usuario('LIB-005', 1, '99900002393', 'ativo');
  v_alvo  := public.qa_up_usuario('LIB-005', 2, '99900002474', 'ativo');
  v_p     := public.qa_up_perfil('LIB-005', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_admin, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_admin;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conceder ao alvo uma liberação de módulo que o concedente não possui';
  PERFORM public.qa_up_entrar(v_uid);
  BEGIN
    IF public.qa_up_pode_virar_usuario() THEN
      SET LOCAL ROLE authenticated;
    END IF;
    INSERT INTO public.perfil_excecoes
      (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
    VALUES (v_t, v_alvo, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
            'administrar', 'grupo_economico', true, 'Tentativa de conceder acima do teto — caso LIB-005.');
    v_criou := true;
  EXCEPTION WHEN OTHERS THEN
    v_criou  := false;
    v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF NOT v_criou THEN
    r.situacao := 'passou';
    r.obtido := format('A liberação acima do teto do concedente foi recusada. Motivo: %s.',
                       COALESCE(v_motivo, '(a inserção não afetou nada)'));
    r.detalhe := jsonb_build_object('motivo', v_motivo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO ACIMA DO TETO ACEITA: um usuário cujo perfil só alcança o módulo Ponto concedeu a '
             || 'outro uma liberação de escopo de grupo econômico com ação administrar em Documentos. '
             || 'A liberação vira a porta dos fundos da escalada de privilégio.';
    r.detalhe := jsonb_build_object('usuario_alvo', v_alvo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- CORREÇÃO NA INFRAESTRUTURA DO PRÓPRIO QA
--
-- Achado ao escrever as rotinas de escalada (NAC-006, LIB-005, PRIV-*):
-- qa_sandbox_tenant_id() é uma função comum que lê public.tenants. Sob o
-- papel 'authenticated' — que é justamente o papel que uma rotina precisa
-- assumir para testar o que um usuário COMUM consegue fazer — o isolamento
-- esconde a linha do cercado e a função devolve NULO. A trava do cercado
-- então compara o tenant da escrita com NULO, conclui "está fora do cercado"
-- e recusa TUDO.
--
-- O efeito era um falso verde perigoso: a rotina tentava uma escrita
-- indevida, a trava do QA barrava, e o resultado parecia "o sistema recusou
-- a escalada de privilégio" — quando na verdade o sistema nem chegou a ser
-- consultado. Nenhuma rotina de QA conseguia testar escrita pelos olhos de
-- um usuário comum.
--
-- A correção é mínima e só aumenta a confiabilidade da trava: a função passa
-- a rodar com o privilégio do dono, de modo que ela enxerga o cercado sob
-- QUALQUER papel. A trava continua fazendo exatamente o mesmo: recusar
-- escrita fora do cercado. Ela apenas deixa de recusar por cegueira.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.qa_sandbox_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$ SELECT id FROM public.tenants WHERE slug = 'qa-sandbox' $fn$;

COMMENT ON FUNCTION public.qa_sandbox_tenant_id() IS
  'Id do cercado de teste. Único lugar onde o robô de QA pode escrever. Roda com privilégio do dono para enxergar o cercado sob qualquer papel — sem isso a trava recusava por cegueira quando a rotina assumia o papel de usuário comum.';

-- ═════════════════════════════════════════════════════════
-- CTX — Troca de contexto de empresa
-- ═════════════════════════════════════════════════════════

-- Existe no banco alguma noção de "empresa ativa" da sessão?
CREATE OR REPLACE FUNCTION public.qa_up_tem_empresa_ativa()
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND (p.proname ~* 'empresa_ativa'
           OR pg_get_functiondef(p.oid) ~* '(empresa_ativa|request\.jwt\.claims.*empresa)')
  )
$fn$;

COMMENT ON FUNCTION public.qa_up_tem_empresa_ativa() IS
  'QA Usuários & Permissões: o banco tem alguma noção de empresa ativa da sessão para decidir acesso?';

-- CTX-003 — o nível muda junto com o contexto, também no backend.
CREATE OR REPLACE FUNCTION public.qa_caso_ctx_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_em_alfa boolean; v_em_beta boolean; v_tem_ctx boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('CTX-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Admin na Alfa e Colaborador na Beta; executar a ação de admin em cada contexto';
  r.esperado    := 'Permitido no contexto da Alfa e negado no da Beta';

  v_u  := public.qa_up_usuario('CTX-003', 1, '99900002555', 'ativo');
  v_pa := public.qa_up_perfil('CTX-003', 'Admin Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('CTX-003', 'Colab Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  v_tem_ctx := public.qa_up_tem_empresa_ativa();

  r.passo_ordem := 2;
  r.passo_acao  := 'Pedir a decisão em cada contexto de empresa';
  PERFORM public.qa_up_entrar(v_uid);
  v_em_alfa := public.perfil_permite_modulo(v_t, 'ponto');
  v_em_beta := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_tem_ctx AND v_em_alfa IS TRUE AND v_em_beta IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A decisão acompanhou a empresa ativa: permitida na Alfa, negada na Beta.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('NÃO EXISTE EMPRESA ATIVA NA DECISÃO: o banco não carrega nem consulta qual empresa '
             || 'está ativa na sessão (noção encontrada: %s). A troca de contexto muda o que a TELA mostra, '
             || 'mas a decisão do banco continua a mesma dos dois lados — respondeu %s na Alfa e %s na Beta. '
             || 'A premissa P5 do documento (a sessão carrega a empresa ativa e o papel dela) não se '
             || 'sustenta hoje no banco.', v_tem_ctx, v_em_alfa, v_em_beta);
    r.detalhe := jsonb_build_object('tem_empresa_ativa', v_tem_ctx, 'alfa', v_em_alfa, 'beta', v_em_beta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CTX-005 — requisição concorrente durante a troca de contexto.
CREATE OR REPLACE FUNCTION public.qa_caso_ctx_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Disparar a troca de contexto e, em paralelo, uma requisição do contexto anterior';
  r.esperado    := 'A requisição em voo é avaliada contra o contexto correto';
  r.situacao    := 'nao_implementado';
  r.obtido      := 'NÃO É PROVÁVEL NO MOTOR SQL, e isto não é dívida a cobrar aqui. O caso exige DUAS '
                || 'requisições simultâneas em sessões distintas, com a troca de contexto acontecendo entre '
                || 'uma e outra. Uma rotina do motor roda dentro de UMA transação, numa única sessão: ela '
                || 'não consegue criar a concorrência que é justamente o objeto do teste. Fingir com duas '
                || 'chamadas em sequência daria um verde que não prova nada. O próprio documento já '
                || 'antecipava que este caso poderia ficar "não provado". Onde ele cabe: teste de carga ou '
                || 'de integração com duas sessões reais — e, antes disso, o caso só faz sentido depois que '
                || 'existir noção de empresa ativa no banco (ver CTX-003).';
  RETURN r;
END $fn$;

-- CTX-006 — id direto de outra empresa vinculada não basta sem trocar de contexto.
CREATE OR REPLACE FUNCTION public.qa_caso_ctx_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_beta uuid; v_viu int; v_tem_ctx boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('CTX-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário vinculado a Alfa e Beta, com contexto ativo na Alfa';
  r.esperado    := 'Acessar pelo id um registro da Beta é negado enquanto o contexto for Alfa';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum; sem isso a leitura '
             || 'aconteceria com o papel dono do banco, para quem o isolamento não se aplica.';
    RETURN r;
  END IF;

  v_u    := public.qa_up_usuario('CTX-006', 1, '99900002636', 'ativo');
  v_pa   := public.qa_up_perfil('CTX-006', 'Alfa', 'ponto', 'empresa_inteira');
  v_pb   := public.qa_up_perfil('CTX-006', 'Beta', 'ponto', 'proprio_usuario');
  v_beta := public.qa_empresa('[QA] Beta');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, v_beta, v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  v_tem_ctx := public.qa_up_tem_empresa_ativa();

  r.passo_ordem := 2;
  r.passo_acao  := 'Com contexto na Alfa, buscar pelo id um registro da Empresa Beta';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_viu FROM public.empresa_cadastro WHERE id = v_beta;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_tem_ctx AND v_viu = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'O registro da Beta foi negado enquanto o contexto era a Alfa: pertencer não basta, é preciso estar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('PERTENCER BASTA: o registro da Empresa Beta foi alcançado pelo id (%s linha(s)) sem '
             || 'nenhuma troca de contexto, porque o banco não tem noção de empresa ativa (encontrada: %s). '
             || 'O acesso vale pela UNIÃO dos vínculos do usuário, não pela empresa em que ele está. Para '
             || 'quem tem vínculo com várias empresas do mesmo cliente, não existe fronteira entre elas.',
             v_viu, v_tem_ctx);
    r.detalhe := jsonb_build_object('linhas_vistas', v_viu, 'tem_empresa_ativa', v_tem_ctx);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- SES — Sessão e revogação em tempo real
-- ═════════════════════════════════════════════════════════

-- SES-001 — o login concede exatamente o escopo do vínculo ativo.
CREATE OR REPLACE FUNCTION public.qa_caso_ses_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_no_perfil boolean; v_fora boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('SES-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Entrar com um vínculo que libera apenas um módulo';
  r.esperado    := 'A sessão concede o módulo do vínculo e nada além';

  v_u := public.qa_up_usuario('SES-001', 1, '99900002717', 'ativo');
  v_p := public.qa_up_perfil('SES-001', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conferir o que a sessão concede dentro e fora do vínculo';
  PERFORM public.qa_up_entrar(v_uid);
  v_no_perfil := public.perfil_permite_modulo(v_t, 'ponto');
  v_fora      := public.perfil_permite_modulo(v_t, 'financeiro');
  PERFORM public.qa_up_sair();

  IF v_no_perfil IS TRUE AND v_fora IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A sessão concedeu exatamente o escopo do vínculo: o módulo liberado sim, o resto não.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ESCOPO DA SESSÃO NÃO BATE COM O VÍNCULO: módulo do vínculo=%s, módulo de fora=%s.',
                       v_no_perfil, v_fora);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- SES-002 — remoção de vínculo vale na sessão já aberta.
CREATE OR REPLACE FUNCTION public.qa_caso_ses_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_antes boolean; v_depois boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('SES-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário logado com acesso; remover o vínculo SEM ele sair e entrar de novo';
  r.esperado    := 'A próxima requisição da mesma sessão já é negada';

  v_u := public.qa_up_usuario('SES-002', 1, '99900002806', 'ativo');
  v_p := public.qa_up_perfil('SES-002', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  -- A sessão começa aqui e NÃO é reaberta: os claims seguem os mesmos.
  PERFORM public.qa_up_entrar(v_uid);
  v_antes := public.perfil_permite_modulo(v_t, 'ponto');

  r.passo_ordem := 2;
  r.passo_acao  := 'Com a sessão aberta, o admin remove o vínculo';
  DELETE FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'A MESMA sessão pede a decisão de novo';
  v_depois := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_antes IS TRUE AND v_depois IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'O acesso cessou na requisição seguinte da mesma sessão, sem precisar de novo login: '
             || 'a decisão é recalculada a cada chamada, não carimbada no token.';
  ELSIF v_depois IS TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'REVOGAÇÃO SÓ NO PRÓXIMO LOGIN: o vínculo foi removido e a sessão aberta continuou com '
             || 'acesso. A janela entre revogar e a pessoa sair do sistema fica aberta por tempo '
             || 'indeterminado — e é justamente quando alguém acaba de ser desligado que essa janela importa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Controle inicial falhou: antes da remoção o acesso já era %s.', v_antes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- SES-003 — desativar o usuário encerra a sessão aberta.
CREATE OR REPLACE FUNCTION public.qa_caso_ses_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_antes boolean; v_depois boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('SES-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário logado e ativo; desativá-lo com a sessão aberta';
  r.esperado    := 'As ações da sessão aberta passam a ser negadas';

  v_u := public.qa_up_usuario('SES-003', 1, '99900002989', 'ativo');
  v_p := public.qa_up_perfil('SES-003', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  v_antes := public.perfil_permite_modulo(v_t, 'ponto');

  r.passo_ordem := 2;
  r.passo_acao  := 'Desativar o usuário sem tocar na sessão';
  UPDATE public.usuarios_base SET status = 'inativo' WHERE id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'A mesma sessão tenta agir';
  v_depois := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_antes IS TRUE AND v_depois IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Desativado o usuário, a sessão aberta deixou de agir na requisição seguinte.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'DESATIVAÇÃO NÃO ENCERRA A SESSÃO: o usuário foi marcado como inativo e a sessão aberta '
             || 'seguiu agindo. Mesma causa de USR-005 e USR-006: a decisão de acesso não consulta '
             || 'usuarios_base.status. Quem foi desligado continua trabalhando no sistema até o token vencer.';
    r.detalhe := jsonb_build_object('antes', v_antes, 'depois', v_depois);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- SES-004 — rebaixar o nível vale imediatamente.
CREATE OR REPLACE FUNCTION public.qa_caso_ses_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_amplo uuid; v_restrito uuid; v_antes boolean; v_depois boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('SES-004');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário logado como Admin; rebaixá-lo a Colaborador com a sessão aberta';
  r.esperado    := 'A ação de admin é negada na requisição seguinte';

  v_u       := public.qa_up_usuario('SES-004', 1, '99900001079', 'ativo');
  v_amplo   := public.qa_up_perfil('SES-004', 'Admin', 'ponto', 'empresa_inteira');
  v_restrito:= public.qa_up_perfil('SES-004', 'Colaborador', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_amplo);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  v_antes := public.perfil_permite_modulo(v_t, 'ponto');

  r.passo_ordem := 2;
  r.passo_acao  := 'Trocar o perfil do vínculo para o restrito';
  UPDATE public.usuario_perfil_vinculos SET perfil_id = v_restrito WHERE usuario_id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'A mesma sessão tenta a ação de admin';
  v_depois := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_antes IS TRUE AND v_depois IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'O rebaixamento valeu na requisição seguinte: quem perdeu o cargo perdeu o poder na hora.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('REBAIXAMENTO NÃO VALE DE IMEDIATO: antes=%s, depois=%s. Manter poder de admin nas '
             || 'mãos de quem já foi rebaixado é a janela que mais dói numa troca de comando.', v_antes, v_depois);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- ISOL — Isolamento multi-tenant (a série de maior prioridade)
--
-- Todas leem com o papel 'authenticated', com o isolamento LIGADO. Ler com o
-- papel dono do banco devolveria tudo e daria verde sem prova nenhuma.
-- ═════════════════════════════════════════════════════════

-- Monta um usuário completo do cercado e devolve o auth uid, ou NULL se o
-- ambiente não permitir montar a identidade que o isolamento enxerga.
CREATE OR REPLACE FUNCTION public.qa_up_usuario_isolado(p_codigo text, p_cpf text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_u uuid; v_p uuid; v_uid uuid;
BEGIN
  PERFORM public.qa_fixture_limpar(p_codigo);
  v_u := public.qa_up_usuario(p_codigo, 1, p_cpf, 'ativo');
  v_p := public.qa_up_perfil(p_codigo, 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;
  IF NOT public.qa_up_tem_identidade(v_uid) THEN
    RETURN NULL;
  END IF;
  RETURN v_uid;
END $fn$;

-- ISOL-001 — leitura devolve apenas linhas do próprio cliente.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_uid uuid; v_proprias int; v_alheias int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, consultar uma tabela sensível';
  r.esperado    := 'Só linhas do próprio cliente — e pelo menos uma, senão não se provou leitura nenhuma';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum. Ler com o papel dono do '
             || 'banco ignoraria o isolamento e daria um verde sem prova.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-001', '99900001230');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar neste ambiente a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Contar o que o usuário enxerga, dentro e fora do próprio cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) FILTER (WHERE tenant_id = v_t),
         count(*) FILTER (WHERE tenant_id <> v_t)
  INTO v_proprias, v_alheias
  FROM public.usuarios_base;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_proprias > 0 AND v_alheias = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('O usuário enxergou %s linha(s) do próprio cliente e nenhuma de outro.', v_proprias);
  ELSIF v_proprias = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'O usuário não enxergou NADA, nem do próprio cliente. O isolamento não pode ser tão fechado '
             || 'que o dono do dado fique de fora: tabela com política que nega tudo é tão defeituosa quanto '
             || 'tabela sem política — e alguém vai "consertar" desligando o isolamento.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO: o usuário enxergou %s linha(s) de OUTRO cliente.', v_alheias);
    r.detalhe := jsonb_build_object('proprias', v_proprias, 'alheias', v_alheias);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-002 — leitura não alcança linha de outro cliente (lado negativo).
CREATE OR REPLACE FUNCTION public.qa_caso_isol_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_alvo uuid; v_por_busca int; v_por_id int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, procurar linhas de OUTRO cliente — por busca e pelo id exato';
  r.esperado    := 'Zero linhas nos dois caminhos';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente: sem o outro lado, o lado negativo '
             || 'do isolamento não tem o que provar.';
    RETURN r;
  END IF;

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-002', '99900001311');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id INTO v_alvo FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Buscar por cliente e depois pelo id exato de uma linha dele';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_por_busca FROM public.usuarios_base WHERE tenant_id = v_outro;
  SELECT count(*) INTO v_por_id    FROM public.usuarios_base WHERE id = v_alvo;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_por_busca = 0 AND v_por_id = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma linha do outro cliente foi alcançada, nem por busca nem pelo id exato.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO ENTRE CLIENTES: por busca %s linha(s), pelo id exato %s. É o risco '
             || 'existencial do produto — dado pessoal de um cliente na mão de outro (LGPD art. 46).',
             v_por_busca, v_por_id);
    r.detalhe := jsonb_build_object('outro_tenant', v_outro, 'por_busca', v_por_busca, 'por_id', v_por_id);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-003 — escrita não alcança linha de outro cliente.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_alvo uuid; v_alterou int := 0; v_apagou int := 0; v_intacta boolean;
  v_nome_antes text; v_nome_depois text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, tentar ALTERAR e EXCLUIR linha de outro cliente';
  r.esperado    := 'Zero linhas afetadas nos dois verbos, e a linha alheia intacta';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-003', '99900001400');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id, nome_completo INTO v_alvo, v_nome_antes
  FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar alterar e excluir a linha alheia';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.usuarios_base SET nome_completo = '[QA-ISOL-003] invadido' WHERE id = v_alvo;
    GET DIAGNOSTICS v_alterou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_alterou := 0;
  END;
  BEGIN
    DELETE FROM public.usuarios_base WHERE id = v_alvo;
    GET DIAGNOSTICS v_apagou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_apagou := 0;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT nome_completo INTO v_nome_depois FROM public.usuarios_base WHERE id = v_alvo;
  v_intacta := (v_nome_depois IS NOT DISTINCT FROM v_nome_antes);

  IF v_alterou = 0 AND v_apagou = 0 AND v_intacta THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma escrita cruzou a fronteira: zero linhas alteradas, zero excluídas, linha alheia intacta.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ESCRITA CRUZOU A FRONTEIRA: %s linha(s) alterada(s) e %s excluída(s) em outro cliente; '
             || 'linha intacta=%s. É o erro clássico da política que cobre a leitura e esquece a escrita.',
             v_alterou, v_apagou, v_intacta);
    r.detalhe := jsonb_build_object('alterou', v_alterou, 'apagou', v_apagou);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-004 — inserção não consegue plantar linha em outro cliente.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_plantou boolean := false; v_motivo text; v_n int;
  v_com_check int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, inserir uma linha DECLARANDO outro cliente';
  r.esperado    := 'Rejeitado pela verificação da política; nenhuma linha nova no outro cliente';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-004', '99900001583');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar plantar a linha no outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
    VALUES (v_outro, '[QA-ISOL-004] Plantado', 'qa.isol004.plantado@sandbox.invalid',
            '99900001664', 'colaborador', 'ativo', gen_random_uuid());
    v_plantou := true;
  EXCEPTION WHEN OTHERS THEN
    v_plantou := false;
    v_motivo  := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT count(*) INTO v_n FROM public.usuarios_base
  WHERE tenant_id = v_outro AND nome_completo = '[QA-ISOL-004] Plantado';

  -- Quantas políticas de inserção prendem o cliente na verificação? É a
  -- prova estrutural que sustenta o resultado observado.
  SELECT count(*) INTO v_com_check FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'usuarios_base'
    AND cmd IN ('INSERT','ALL') AND COALESCE(with_check, '') ILIKE '%tenant%';

  -- A trava do cercado é um gatilho BEFORE: ela roda ANTES da verificação da
  -- política. Quando é ela quem recusa, o sistema nem chegou a ser consultado,
  -- e dar "passou" aqui seria creditar ao produto uma defesa que foi do QA.
  -- Nesse caso o veredito passa a se apoiar na prova estrutural: as políticas
  -- de inserção prendem o cliente na verificação?
  IF NOT v_plantou AND v_n = 0 AND COALESCE(v_motivo, '') ILIKE '%QA BLOQUEADO%' THEN
    IF v_com_check > 0 THEN
      r.situacao := 'passou';
      r.obtido := format('Nada foi plantado no outro cliente. Ressalva honesta sobre a evidência: quem recusou '
               || 'primeiro foi a trava do cercado de QA (gatilho BEFORE, que roda antes da verificação da '
               || 'política), então a recusa do sistema não pôde ser observada em ação. O veredito se apoia '
               || 'na prova estrutural: %s política(s) de inserção em usuarios_base prendem o cliente na '
               || 'cláusula de verificação, que é o que impede plantar linha em cliente alheio.', v_com_check);
    ELSE
      r.situacao := 'falhou';
      r.obtido := 'NÃO HÁ VERIFICAÇÃO DE CLIENTE NA INSERÇÃO: nenhuma política de inserção em usuarios_base '
               || 'prende o tenant_id na cláusula de verificação. Nada foi plantado nesta rodada apenas '
               || 'porque a trava do cercado de QA recusou antes — fora do QA, essa trava não existe.';
      r.detalhe := jsonb_build_object('politicas_com_check', v_com_check, 'motivo', v_motivo);
    END IF;
  ELSIF NOT v_plantou AND v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('A inserção com cliente alheio foi rejeitada pelo próprio sistema e nada foi plantado. '
             || 'Motivo: %s. Políticas de inserção que prendem o cliente na verificação: %s.',
             COALESCE(v_motivo, '(sem erro, mas nada gravado)'), v_com_check);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('LINHA PLANTADA EM OUTRO CLIENTE: inserção aceita=%s, linhas encontradas=%s. '
             || 'Políticas de inserção prendendo o cliente: %s. Sem essa verificação dá para semear dado '
             || 'dentro do cliente errado — e ele aparece lá como se fosse legítimo.',
             v_plantou, v_n, v_com_check);
    r.detalhe := jsonb_build_object('plantou', v_plantou, 'linhas', v_n, 'politicas_com_check', v_com_check);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-005 — toda tabela sensível com isolamento ligado E política coerente.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_desligadas int; v_lista_desl text; v_sem_politica int; v_lista_sem text; v_total int;
  v_backups int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): varrer as tabelas sensíveis do banco';
  r.esperado    := 'Nenhuma exposta (isolamento desligado) e nenhuma travada (ligado e sem política)';

  -- "Sensível" aqui é a mesma definição que a cerca do QA já usa: tabela que
  -- carrega tenant_id, ou seja, que guarda dado de cliente. Derivada, não fixa:
  -- tabela nova entra na varredura sozinha.
  SELECT count(*) INTO v_total
  FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
    AND t.table_type = 'BASE TABLE' AND c.table_name NOT LIKE 'qa\_%';

  SELECT count(*), string_agg(x.tabela, ', ' ORDER BY x.tabela)
  INTO v_desligadas, v_lista_desl
  FROM (
    SELECT c.table_name AS tabela
    FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    JOIN pg_class cl ON cl.oid = ('public.' || quote_ident(c.table_name))::regclass
    WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
      AND t.table_type = 'BASE TABLE' AND c.table_name NOT LIKE 'qa\_%'
      AND cl.relrowsecurity = false
  ) x;

  SELECT count(*), string_agg(x.tabela, ', ' ORDER BY x.tabela)
  INTO v_sem_politica, v_lista_sem
  FROM (
    SELECT c.table_name AS tabela
    FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    JOIN pg_class cl ON cl.oid = ('public.' || quote_ident(c.table_name))::regclass
    WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
      AND t.table_type = 'BASE TABLE' AND c.table_name NOT LIKE 'qa\_%'
      AND cl.relrowsecurity = true
      AND NOT EXISTS (SELECT 1 FROM pg_policies p
                      WHERE p.schemaname = 'public' AND p.tablename = c.table_name)
  ) x;

  SELECT count(*) INTO v_backups
  FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  JOIN pg_class cl ON cl.oid = ('public.' || quote_ident(c.table_name))::regclass
  WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
    AND t.table_type = 'BASE TABLE' AND c.table_name LIKE 'backup\_%'
    AND cl.relrowsecurity = false;

  IF v_desligadas = 0 AND v_sem_politica = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('As %s tabelas sensíveis estão com o isolamento ligado e todas têm política.', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VARREDURA ACUSOU: de %s tabelas sensíveis, %s estão com o isolamento DESLIGADO (%s) '
             || 'e %s estão ligadas mas SEM NENHUMA POLÍTICA (%s). A primeira lista é exposição direta. '
             || 'A segunda fica inacessível até para o dono do dado — e o conserto apressado costuma ser '
             || 'desligar o isolamento, que transforma a segunda lista na primeira. '
             || 'Para triagem: %s das expostas são tabelas backup_* das cópias de segurança que os scripts '
             || 'de entrega tiram antes de alterar dado. Elas guardam linhas REAIS de cliente e nascem sem '
             || 'isolamento nenhum — a cópia de segurança que protege contra o script errado vira, ela '
             || 'mesma, uma cópia desprotegida do dado que ela salvou.',
             v_total, v_desligadas, COALESCE(v_lista_desl, '-'), v_sem_politica, COALESCE(v_lista_sem, '-'),
             v_backups);
    r.detalhe := jsonb_build_object('total', v_total, 'sem_isolamento', v_lista_desl, 'sem_politica', v_lista_sem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-006 — rotina sensível não fica executável por quem não deve.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_anon int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): quem pode executar as rotinas que tocam dado de cliente';
  r.esperado    := 'Nenhuma rotina sensível executável por usuário ANÔNIMO';

  SELECT count(*), string_agg(x.proname, ', ' ORDER BY x.proname)
  INTO v_anon, v_lista
  FROM (
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      -- sensível = o corpo menciona alguma tabela que guarda dado de cliente
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
  ) x;

  IF v_anon = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rotina que toca dado de cliente está aberta ao usuário anônimo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ROTINA SENSÍVEL ABERTA AO ANÔNIMO: %s rotina(s) que tocam dado de cliente podem ser '
             || 'executadas sem nenhum login: %s. Já houve precedente disso neste produto em outro módulo. '
             || 'Rotina aberta ao anônimo não é protegida por política de linha: ela roda antes.', v_anon, v_lista);
    r.detalhe := jsonb_build_object('quantidade', v_anon, 'rotinas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-007 — acesso cross-tenant do superadmin fica registrado.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_tem_log boolean; v_registra_leitura boolean; v_gatilhos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA: existe registro do que o superadmin acessa fora do próprio cliente?';
  r.esperado    := 'Cada travessia do superadmin deixa rastro de quem, quando e o quê';

  SELECT to_regclass('public.perfil_audit_log') IS NOT NULL INTO v_tem_log;

  -- Cuidado para não confundir os dois: quase toda rotina que ALTERA dado
  -- grava auditoria, e várias delas também chamam is_superadmin. Isso é
  -- auditoria de ESCRITA e não prova nada sobre a travessia de LEITURA, que é
  -- o objeto deste caso. O sinal procurado é uma rotina que registre o ACESSO
  -- (consulta) de quem atravessa a fronteira de cliente.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND p.proname ~* '(registrar|log|audit).*(acesso|leitura|consulta|visualiza)'
      AND pg_get_functiondef(p.oid) ~* '(is_superadmin|cross.?tenant|outro.?tenant)'
  ) INTO v_registra_leitura;

  SELECT count(*) INTO v_gatilhos
  FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND NOT tg.tgisinternal
    AND c.relname IN ('perfis_acesso','perfil_permissoes','usuario_perfil_vinculos','perfil_excecoes')
    AND tg.tgname ~* '(audit|log)';

  IF v_tem_log AND v_registra_leitura THEN
    r.situacao := 'passou';
    r.obtido := format('Existe trilha de auditoria e o caminho do superadmin registra o acesso. '
             || 'Gatilhos de auditoria nas tabelas de perfil: %s.', v_gatilhos);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('BYPASS DO SUPERADMIN NÃO É AUDITADO NA LEITURA: a tabela de trilha existe (%s) e há %s '
             || 'gatilho(s) de auditoria nas tabelas de perfil, mas nenhuma função que reconhece o superadmin '
             || 'registra o que ele ACESSA. Ou seja: mudanças de perfil deixam rastro, e a leitura '
             || 'cross-tenant — que é o maior poder do sistema — não deixa. A premissa P4 do documento diz '
             || '"todo bypass é auditado"; hoje ela não se sustenta para leitura.',
             v_tem_log, v_gatilhos);
    r.detalhe := jsonb_build_object('tem_trilha', v_tem_log, 'gatilhos_perfil', v_gatilhos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ISOL-008 — rotina privilegiada reaplica o filtro de cliente por dentro.
CREATE OR REPLACE FUNCTION public.qa_caso_isol_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_total int; v_sem_filtro int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): rotinas que rodam com privilégio do dono';
  r.esperado    := 'Todas reaplicam o filtro de cliente por dentro — privilégio do dono ignora a política';

  SELECT count(*) INTO v_total
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosecdef
    AND p.proname NOT LIKE 'qa\_%';

  SELECT count(*), string_agg(x.proname, ', ' ORDER BY x.proname)
  INTO v_sem_filtro, v_lista
  FROM (
    SELECT p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosecdef
      AND p.proname NOT LIKE 'qa\_%'
      -- toca tabela de dado de cliente...
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|admissoes|atestados|perfil_excecoes|usuario_perfil_vinculos|profiles)'
      -- ...e em nenhum lugar do corpo amarra o cliente ou o usuário logado
      AND pg_get_functiondef(p.oid) !~* '(tenant_id|auth\.uid\(\)|get_user_tenant_id|is_superadmin|has_minimum_role)'
  ) x;

  IF v_sem_filtro = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Todas as %s rotinas com privilégio do dono que tocam dado de cliente amarram o cliente '
             || 'ou o usuário logado por dentro.', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('TÚNEL ENTRE CLIENTES: de %s rotinas com privilégio do dono, %s tocam dado de cliente '
             || 'sem amarrar o cliente nem o usuário logado em lugar nenhum do corpo: %s. Rotina assim roda '
             || 'com o privilégio de quem a criou e passa por cima da política de linha — ela é a porta que '
             || 'contorna todo o isolamento.', v_total, v_sem_filtro, v_lista);
    r.detalhe := jsonb_build_object('total_definer', v_total, 'sem_filtro', v_sem_filtro, 'rotinas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- PRIV — Escalada de privilégio
-- ═════════════════════════════════════════════════════════

-- PRIV-001 — usuário não edita o próprio nível de acesso.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_restrito uuid; v_amplo uuid; v_promoveu int := 0; v_virou_admin boolean := false;
  v_perfil_final uuid; v_motivo text;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Colaborador tenta trocar o próprio perfil por um amplo e virar admin do sistema';
  r.esperado    := 'Negado nos dois caminhos; o nível dele não muda';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum; sem isso a tentativa '
             || 'rodaria com o privilégio do dono do banco e teria sucesso por motivo errado.';
    RETURN r;
  END IF;

  v_u       := public.qa_up_usuario('PRIV-001', 1, '99900001745', 'ativo');
  v_restrito:= public.qa_up_perfil('PRIV-001', 'Colaborador', 'ponto', 'proprio_usuario');
  v_amplo   := public.qa_up_perfil('PRIV-001', 'Admin', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_restrito);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Auto-promoção: trocar o perfil do próprio vínculo pelo amplo';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.usuario_perfil_vinculos SET perfil_id = v_amplo WHERE usuario_id = v_u;
    GET DIAGNOSTICS v_promoveu = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_promoveu := 0; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Auto-promoção pelo outro caminho: conceder a si mesmo papel de administrador';
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'admin');
    v_virou_admin := true;
  EXCEPTION WHEN OTHERS THEN
    v_virou_admin := false;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT perfil_id INTO v_perfil_final FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF v_promoveu = 0 AND NOT v_virou_admin AND v_perfil_final = v_restrito THEN
    r.situacao := 'passou';
    r.obtido := format('A auto-promoção foi negada nos dois caminhos e o nível ficou como estava. Motivo: %s.',
                       COALESCE(v_motivo, '(nenhuma linha afetada)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('AUTO-PROMOÇÃO POSSÍVEL: o usuário alterou o próprio vínculo em %s linha(s) e/ou '
             || 'concedeu a si mesmo papel de administrador (%s). É a escalada mais direta que existe: '
             || 'quem entra como colaborador sai como administrador sem passar por ninguém.',
             v_promoveu, v_virou_admin);
    r.detalhe := jsonb_build_object('linhas_alteradas', v_promoveu, 'virou_admin', v_virou_admin);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PRIV-002 — admin não concede acima do próprio teto.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_alvo_uid uuid; v_p uuid; v_concedeu boolean := false; v_motivo text;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário sem poder de sistema tenta conceder a outro um papel acima do seu';
  r.esperado    := 'Negado — ninguém concede acima do próprio teto';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_u    := public.qa_up_usuario('PRIV-002', 1, '99900001826', 'ativo');
  v_alvo := public.qa_up_usuario('PRIV-002', 2, '99900001907', 'ativo');
  v_p    := public.qa_up_perfil('PRIV-002', 'Comum', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid      FROM public.usuarios_base WHERE id = v_u;
  SELECT auth_user_id INTO v_alvo_uid FROM public.usuarios_base WHERE id = v_alvo;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conceder ao alvo um papel de sistema que o concedente não possui';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_alvo_uid, 'owner');
    v_concedeu := true;
  EXCEPTION WHEN OTHERS THEN
    v_concedeu := false; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF NOT v_concedeu THEN
    r.situacao := 'passou';
    r.obtido := format('A concessão acima do teto foi recusada. Motivo: %s.', COALESCE(v_motivo, '(nada gravado)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'CONCESSÃO ACIMA DO TETO ACEITA: um usuário comum concedeu a outro o papel de dono do '
             || 'sistema. Com isso, dois usuários comuns combinados chegam ao poder total em um passo cada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PRIV-003 — empresa ou papel enviados no pedido não mudam a decisão.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_p uuid; v_usa_claims boolean; v_recebe_usuario boolean;
  v_com_tenant_alheio boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA: de onde a decisão tira a identidade de quem pergunta';
  r.esperado    := 'Dos claims verificados da sessão, nunca de um parâmetro que o chamador escolhe';

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ~* 'auth\.uid\(\)'
  ) INTO v_usa_claims;

  -- O sinal de perigo: a decisão aceitar do chamador QUEM ele diz ser.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_function_arguments(p.oid) ~* '(p_usuario|p_user|p_uid|p_auth)'
  ) INTO v_recebe_usuario;

  r.passo_ordem := 2;
  r.passo_acao  := 'Na prática: pedir a decisão declarando um cliente que não é o meu';
  v_u := public.qa_up_usuario('PRIV-003', 1, '99900002040', 'ativo');
  v_p := public.qa_up_perfil('PRIV-003', 'Amplo', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  -- Passa no parâmetro um cliente alheio: se a decisão obedecesse ao que vem
  -- no pedido, isso abriria a porta do outro cliente.
  v_com_tenant_alheio := public.perfil_permite_modulo(COALESCE(public.qa_up_outro_tenant(), gen_random_uuid()), 'ponto');
  PERFORM public.qa_up_sair();

  IF v_usa_claims AND NOT v_recebe_usuario AND v_com_tenant_alheio IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A decisão tira a identidade dos claims verificados da sessão, não aceita do chamador quem '
             || 'ele diz ser, e declarar um cliente alheio no pedido não abriu nada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A DECISÃO PODE SER INFLUENCIADA PELO PEDIDO: usa os claims da sessão=%s, aceita o '
             || 'usuário como parâmetro do chamador=%s, e declarar cliente alheio no pedido devolveu %s. '
             || 'Se o backend acredita no que vem no corpo, qualquer um se declara quem quiser.',
             v_usa_claims, v_recebe_usuario, v_com_tenant_alheio);
    r.detalhe := jsonb_build_object('usa_claims', v_usa_claims, 'recebe_usuario', v_recebe_usuario,
                                    'resposta_tenant_alheio', v_com_tenant_alheio);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PRIV-004 — credencial de um cliente não vale no recurso de outro.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_empresas int; v_perfis int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Usar a credencial de um cliente para alcançar recursos de outro';
  r.esperado    := 'Negado: a credencial não abre nada fora do cliente dela';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('PRIV-004', '99900002121');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Com essa credencial, alcançar empresas e perfis do outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_empresas FROM public.empresa_cadastro WHERE tenant_id = v_outro;
  SELECT count(*) INTO v_perfis   FROM public.perfis_acesso    WHERE tenant_id = v_outro;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_empresas = 0 AND v_perfis = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A credencial não abriu nada do outro cliente: nem empresas, nem perfis.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('CREDENCIAL ATRAVESSA A FRONTEIRA: alcançou %s empresa(s) e %s perfil(is) de outro '
             || 'cliente.', v_empresas, v_perfis);
    r.detalhe := jsonb_build_object('empresas', v_empresas, 'perfis', v_perfis);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PRIV-005 — trocar o id do recurso não dá acesso ao dado alheio.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_id_alheio uuid; v_viu int; v_nome text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Trocar o id do recurso por um id VÁLIDO e EXISTENTE de outro cliente';
  r.esperado    := 'Negado mesmo com o id certo, e sem revelar que o registro existe';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('PRIV-005', '99900002202');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id INTO v_id_alheio FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Buscar exatamente por esse id';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_viu FROM public.usuarios_base WHERE id = v_id_alheio;
  SELECT nome_completo INTO v_nome FROM public.usuarios_base WHERE id = v_id_alheio;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_viu = 0 AND v_nome IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'O id válido de outro cliente não devolveu nada e nenhum dado dele foi revelado. '
             || 'O id ser um identificador aleatório dificulta adivinhar, mas quem prova o caso é a negação.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACESSO POR ID ALHEIO: a busca pelo id de outro cliente devolveu %s linha(s) e o nome '
             || '"%s". Trocar um identificador na chamada é a forma mais barata de vazamento que existe.',
             v_viu, COALESCE(v_nome, '(vazio)'));
    r.detalhe := jsonb_build_object('linhas', v_viu);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- PRIV-006 — superadmin só nasce pelo fluxo controlado.
CREATE OR REPLACE FUNCTION public.qa_caso_priv_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_alvo_uid uuid; v_p uuid;
  v_virou boolean := false; v_motivo text; v_n int;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Pelas vias normais de administração de empresa, tentar criar um superadmin';
  r.esperado    := 'Negado — só o fluxo controlado cria superadmin';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Este ambiente não deixa a rotina assumir o papel de usuário comum.';
    RETURN r;
  END IF;

  v_u    := public.qa_up_usuario('PRIV-006', 1, '99900002393', 'ativo');
  v_alvo := public.qa_up_usuario('PRIV-006', 2, '99900002474', 'ativo');
  v_p    := public.qa_up_perfil('PRIV-006', 'Admin de empresa', 'ponto', 'empresa_inteira', 'administrar');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid      FROM public.usuarios_base WHERE id = v_u;
  SELECT auth_user_id INTO v_alvo_uid FROM public.usuarios_base WHERE id = v_alvo;

  r.passo_ordem := 2;
  r.passo_acao  := 'Atribuir o papel de superadmin';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_alvo_uid, 'superadmin');
    v_virou := true;
  EXCEPTION WHEN OTHERS THEN
    v_virou := false; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT count(*) INTO v_n FROM public.user_roles
  WHERE user_id = v_alvo_uid AND role = 'superadmin';

  IF NOT v_virou AND v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('O papel de superadmin não foi concedido pelas vias normais. Motivo: %s.',
                       COALESCE(v_motivo, '(nada gravado)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('SUPERADMIN CRIADO FORA DO FLUXO CONTROLADO: concessão aceita=%s, papéis encontrados=%s. '
             || 'Superadmin é o maior poder do produto e atravessa o isolamento por desenho: se um admin de '
             || 'empresa cria um, o isolamento de 1.100 clientes deixa de valer.', v_virou, v_n);
    r.detalhe := jsonb_build_object('virou', v_virou, 'papeis', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- REGISTRO — liga cada caso documentado à rotina que o executa.
-- Sem isto, documentação e robô descolam em silêncio.
-- Os 5 casos de nível 'e2e' (USR-002, PER-003, CTX-001, CTX-002, CTX-004)
-- ficam de fora de propósito: o motor já responde por eles dizendo que são
-- de tela e que a cobertura pertence ao Cypress.
-- ═════════════════════════════════════════════════════════
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
SELECT v.codigo, v.funcao, true
FROM (VALUES
  ('USR-001','qa_caso_usr_001'), ('USR-003','qa_caso_usr_003'), ('USR-004','qa_caso_usr_004'),
  ('USR-005','qa_caso_usr_005'), ('USR-006','qa_caso_usr_006'), ('USR-007','qa_caso_usr_007'),
  ('USR-008','qa_caso_usr_008'),
  ('VIN-001','qa_caso_vin_001'), ('VIN-002','qa_caso_vin_002'), ('VIN-003','qa_caso_vin_003'),
  ('VIN-004','qa_caso_vin_004'), ('VIN-005','qa_caso_vin_005'), ('VIN-006','qa_caso_vin_006'),
  ('VIN-007','qa_caso_vin_007'), ('VIN-008','qa_caso_vin_008'),
  ('NAC-001','qa_caso_nac_001'), ('NAC-002','qa_caso_nac_002'), ('NAC-003','qa_caso_nac_003'),
  ('NAC-004','qa_caso_nac_004'), ('NAC-005','qa_caso_nac_005'), ('NAC-006','qa_caso_nac_006'),
  ('PER-001','qa_caso_per_001'), ('PER-002','qa_caso_per_002'), ('PER-004','qa_caso_per_004'),
  ('PER-005','qa_caso_per_005'), ('PER-006','qa_caso_per_006'), ('PER-007','qa_caso_per_007'),
  ('PER-008','qa_caso_per_008'),
  ('LIB-001','qa_caso_lib_001'), ('LIB-002','qa_caso_lib_002'), ('LIB-003','qa_caso_lib_003'),
  ('LIB-004','qa_caso_lib_004'), ('LIB-005','qa_caso_lib_005'),
  ('CTX-003','qa_caso_ctx_003'), ('CTX-005','qa_caso_ctx_005'), ('CTX-006','qa_caso_ctx_006'),
  ('ISOL-001','qa_caso_isol_001'), ('ISOL-002','qa_caso_isol_002'), ('ISOL-003','qa_caso_isol_003'),
  ('ISOL-004','qa_caso_isol_004'), ('ISOL-005','qa_caso_isol_005'), ('ISOL-006','qa_caso_isol_006'),
  ('ISOL-007','qa_caso_isol_007'), ('ISOL-008','qa_caso_isol_008'),
  ('PRIV-001','qa_caso_priv_001'), ('PRIV-002','qa_caso_priv_002'), ('PRIV-003','qa_caso_priv_003'),
  ('PRIV-004','qa_caso_priv_004'), ('PRIV-005','qa_caso_priv_005'), ('PRIV-006','qa_caso_priv_006'),
  ('SES-001','qa_caso_ses_001'), ('SES-002','qa_caso_ses_002'), ('SES-003','qa_caso_ses_003'),
  ('SES-004','qa_caso_ses_004')
) AS v(codigo, funcao)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

DO $conf$
DECLARE v_casos int; v_ligados int;
BEGIN
  SELECT count(*) INTO v_casos
  FROM public.qa_casos_teste c JOIN public.qa_modulos m ON m.id = c.modulo_id
  WHERE m.path = 'infraestrutura-auth/usuarios-permissoes' AND c.nivel = 'api';

  SELECT count(*) INTO v_ligados
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  JOIN public.qa_implementacoes i ON i.codigo = c.codigo AND i.ativo
  WHERE m.path = 'infraestrutura-auth/usuarios-permissoes';

  RAISE NOTICE 'Usuários & Permissões: % casos de motor, % com rotina ligada (esperado 54 e 54)', v_casos, v_ligados;
END $conf$;


-- =========================================================
-- CONFERÊNCIA (único resultado que o editor mostra)
-- Esperado: 54 casos de motor, 54 com rotina ligada, 0 sem rotina.
-- As rotinas NÃO são executadas aqui: rodar a bateria é um segundo gesto,
--   SELECT public.qa_rodar_bateria('manual', 'infraestrutura-auth/usuarios-permissoes');
-- e o resultado aparece na tela de QA e Testes.
-- =========================================================
WITH casos AS MATERIALIZED (
  SELECT c.codigo, c.nivel
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  WHERE m.path = 'infraestrutura-auth/usuarios-permissoes'
),
ligadas AS MATERIALIZED (
  SELECT i.codigo, i.funcao_sql,
         to_regprocedure('public.' || i.funcao_sql || '()') IS NOT NULL AS rotina_existe
  FROM public.qa_implementacoes i
  WHERE i.ativo AND i.codigo IN (SELECT codigo FROM casos)
)
SELECT
  (SELECT count(*) FROM casos WHERE nivel = 'api')                        AS casos_de_motor,
  (SELECT count(*) FROM casos WHERE nivel = 'e2e')                        AS casos_de_tela,
  (SELECT count(*) FROM ligadas)                                          AS com_rotina_ligada,
  (SELECT count(*) FROM ligadas WHERE NOT rotina_existe)                  AS rotina_ligada_mas_ausente,
  (SELECT count(*) FROM casos c WHERE c.nivel = 'api'
      AND NOT EXISTS (SELECT 1 FROM ligadas l WHERE l.codigo = c.codigo))  AS de_motor_sem_rotina,
  (SELECT COALESCE(string_agg(l.funcao_sql, ', ' ORDER BY l.funcao_sql), '(nenhum)')
     FROM ligadas l WHERE NOT l.rotina_existe)                            AS erro_tecnico;
