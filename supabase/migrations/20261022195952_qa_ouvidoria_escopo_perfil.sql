-- =========================================================
-- QA — Ouvidoria x escopo do perfil de acesso (achado grave, Taeco 10/2026)
--
--   OUV-060 (api)  o escopo "Próprio usuário" vale no servidor mesmo com papel de gestão:
--                  estrutura das travas + prova com o usuário de teste (papel manager)
--   OUV-061..063 (e2e)  a mesma regra na tela (spec cypress/e2e/ouvidoria-escopo.cy.ts)
--
-- O usuário de teste (ouvidoria.e2e@youreyes.local) e as três manifestações fictícias vêm do
-- seed-e2e-user. Sem eles a rotina devolve nao_implementado dizendo o que falta.
-- A rotina é SOMENTE LEITURA: exerce o RLS por claims, pelos ajudantes qa_rls (sem SET ROLE).
-- Idempotente: casos com ON CONFLICT (codigo) DO NOTHING; pontes por delete-then-insert.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_ouv_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_pol text;
  v_uid uuid;
  v_tenant uuid;
  v_claims text;
  v_proprias bigint;
  v_alheias bigint;
  v_anonimas bigint;
  v_total bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA + FUNCIONAL (somente leitura): Ouvidoria em Próprio usuário não vê manifestação de outros, mesmo com papel de gestão';
  r.esperado    := 'Travas por perfil em leitura/UPDATE/DELETE; o usuário de teste (manager + Próprio usuário) enxerga só a própria manifestação';

  -- 1) Estrutura das travas
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ouvidoria'
                  AND policyname = 'perfil_restringe_leitura_ouvidoria' AND permissive = 'RESTRICTIVE'
                  AND position('ouvidoria' IN COALESCE(qual, '')) > 0
                  AND position('configuracoes' IN COALESCE(qual, '')) = 0) THEN
    v_falhas := v_falhas || 'a trava de leitura não consulta o módulo ouvidoria (ou ainda consulta configuracoes)'::text;
  END IF;
  FOREACH v_pol IN ARRAY ARRAY['perfil_restringe_escrita_ouvidoria_upd', 'perfil_restringe_escrita_ouvidoria_del'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ouvidoria'
                    AND policyname = v_pol AND permissive = 'RESTRICTIVE'
                    AND position('perfil_escreve' IN COALESCE(qual, '') || COALESCE(with_check, '')) > 0) THEN
      v_falhas := v_falhas || ('falta a trava ' || v_pol)::text;
    END IF;
  END LOOP;

  -- 2) Prova com o usuário de teste (precisa existir, com papel de gestão)
  SELECT ub.auth_user_id, ub.tenant_id INTO v_uid, v_tenant
    FROM public.usuarios_base ub WHERE ub.email_principal = 'ouvidoria.e2e@youreyes.local' LIMIT 1;
  IF v_uid IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = v_uid AND ur.role::text = 'manager')
     OR to_regprocedure('qa_rls.conta_auth(text)') IS NULL THEN
    IF COALESCE(array_length(v_falhas, 1), 0) > 0 THEN
      r.situacao := 'falhou'; r.obtido := array_to_string(v_falhas, '; ');
      r.detalhe := jsonb_build_object('falhas', to_jsonb(v_falhas));
    ELSE
      r.situacao := 'nao_implementado';
      r.obtido := 'Travas conferidas. Falta a prova funcional: semear o usuário ouvidoria.e2e@youreyes.local (papel manager, perfil Ouvidoria em Próprio usuário) com seed-e2e-user, e ter os ajudantes qa_rls.';
    END IF;
    RETURN r;
  END IF;

  v_total := (SELECT count(*) FROM public.ouvidoria WHERE tenant_id = v_tenant AND assunto LIKE 'E2E-OUV-%');
  IF v_total < 3 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Faltam as manifestações fictícias E2E-OUV-* (esperadas 3, achadas ' || v_total || '). Rodar o seed-e2e-user.';
    RETURN r;
  END IF;

  v_claims := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  v_proprias := qa_rls.conta_auth('SELECT count(*) FROM public.ouvidoria WHERE assunto = ''E2E-OUV-PROPRIA''');
  v_alheias  := qa_rls.conta_auth('SELECT count(*) FROM public.ouvidoria WHERE assunto = ''E2E-OUV-ALHEIA''');
  v_anonimas := qa_rls.conta_auth('SELECT count(*) FROM public.ouvidoria WHERE assunto = ''E2E-OUV-ANONIMA''');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF v_proprias <> 1 THEN
    v_falhas := v_falhas || ('o usuário não vê a própria manifestação (viu ' || v_proprias || ')')::text;
  END IF;
  IF v_alheias <> 0 THEN
    v_falhas := v_falhas || ('FALHA GRAVE: com Ouvidoria em Próprio usuário, viu manifestação de outro autor (' || v_alheias || ')')::text;
  END IF;
  IF v_anonimas <> 0 THEN
    v_falhas := v_falhas || ('FALHA GRAVE: com Ouvidoria em Próprio usuário, viu manifestação anônima (' || v_anonimas || ')')::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Travas presentes; o usuário de gestão com Próprio usuário vê só a própria manifestação (própria=1, alheia=0, anônima=0).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := array_to_string(v_falhas, '; ');
    r.detalhe := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/ouvidoria' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo pessoas-cultura/ouvidoria ausente; OUV-060..063 nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'OUV-060', 'Ouvidoria em Próprio usuário vale no servidor, mesmo com papel de gestão',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD arts. 6º e 46; Lei 14.457/2022 (sigilo do canal de denúncia)',
   'Achado grave (Taeco, 10/2026): quem tinha Ouvidoria em Próprio usuário via manifestações de outras pessoas, porque o papel de gestão (gravado pelo tipo Gestor) abria tudo e a única trava por perfil olhava o módulo errado. Garante que leitura, atualização e exclusão passam pelo perfil e que o usuário de teste (papel manager) só enxerga a própria.',
   'Usuário ouvidoria.e2e@youreyes.local semeado por seed-e2e-user, com 3 manifestações fictícias.',
   '[{"ordem":1,"acao":"Conferir as travas RESTRICTIVE de leitura (módulo ouvidoria), UPDATE e DELETE (perfil_escreve)","resultado_esperado":"Presentes"},{"ordem":2,"acao":"Simular o usuário (papel manager, Ouvidoria em Próprio usuário) e contar as manifestações visíveis","resultado_esperado":"Própria 1, de outro autor 0, anônima 0"}]'::jsonb,
   'Travas presentes e usuário de gestão com Próprio usuário vendo só a própria manifestação.', 'Rotina qa_caso_ouv_060 (somente leitura).'),
  (v_mod, 'OUV-061', 'Na tela, Ouvidoria em Próprio usuário mostra só as próprias manifestações',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD arts. 6º e 46; Lei 14.457/2022',
   'A tela espelha a regra do servidor: para quem só tem Próprio usuário, a aba se chama Minhas Manifestações e a lista traz apenas as dele, mesmo com papel de gestão.',
   'Usuário ouvidoria.e2e@youreyes.local (papel manager, tipo gestor, perfil Ouvidoria em Próprio usuário).',
   '[{"ordem":1,"acao":"Entrar com o usuário e abrir /ouvidoria, aba Minhas Manifestações","resultado_esperado":"Aparece E2E-OUV-PROPRIA"},{"ordem":2,"acao":"Procurar E2E-OUV-ALHEIA e E2E-OUV-ANONIMA e a aba Todas Manifestações","resultado_esperado":"Nenhuma existe"}]'::jsonb,
   'Só a própria manifestação.', 'Spec: cypress/e2e/ouvidoria-escopo.cy.ts.'),
  (v_mod, 'OUV-062', 'Na tela, Ouvidoria em Próprio usuário não mostra controles de gestão',
   'negativo', 'alta', 'aprovado', 'e2e', 'Princípio do menor privilégio (LGPD art. 46)',
   'Responder, mudar status, excluir, criar ações, indicadores e Configurações são ferramentas de quem trata as manifestações; não aparecem para o escopo Próprio usuário.',
   'Mesmo usuário do OUV-061.',
   '[{"ordem":1,"acao":"Abrir /ouvidoria com o usuário","resultado_esperado":"Sem aba Configurações, sem botões Responder e Criar Ações, sem o cartão Anônimas"}]'::jsonb,
   'Sem controles de gestão.', 'Spec: cypress/e2e/ouvidoria-escopo.cy.ts.'),
  (v_mod, 'OUV-063', 'O dono continua vendo todas as manifestações da empresa',
   'feliz', 'critica', 'aprovado', 'e2e', 'Controle positivo da trava por perfil',
   'Controle positivo: sem ele, o teste de bloqueio poderia passar só porque a lista quebrou. Dono e Super Admin ficam acima do perfil.',
   'Conta-robô (owner) e as 3 manifestações fictícias.',
   '[{"ordem":1,"acao":"Entrar com a conta-robô, abrir /ouvidoria, aba Todas Manifestações, buscar E2E-OUV-","resultado_esperado":"Aparecem as três: própria, de outro autor e anônima"}]'::jsonb,
   'Todas visíveis ao dono.', 'Spec: cypress/e2e/ouvidoria-escopo.cy.ts.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('OUV-060', 'qa_caso_ouv_060', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao OUV-060..063 nao registrada: %', SQLERRM;
END $doc$;

-- Casos antigos que descreviam a regra POR PAPEL: passam a descrever a regra pelo PERFIL
-- (premissa da casa: mudou o comportamento, a documentacao acompanha). Idempotente.
DO $atual$
BEGIN
  UPDATE public.qa_casos_teste SET
    titulo = 'Excluir manifestacao exige o verbo Excluir da Ouvidoria em escopo amplo',
    objetivo = 'Remover manifestacao — inclusive denuncia — so e permitido a quem tem Excluir no modulo Ouvidoria com escopo amplo no perfil (o dono e o Super Admin sempre; quem nao tem perfil vinculado segue a regra antiga de administrador). Papel de gestao, sozinho, nao exclui, nem pela tela nem por baixo dela.',
    pre_condicoes = 'Contas no mesmo tenant: dono ou perfil com Excluir amplo em Ouvidoria, e usuario com papel de gestao mas perfil sem esse verbo.',
    passos = '[{"ordem":1,"acao":"Com a conta que tem Excluir amplo em Ouvidoria, excluir uma manifestacao","resultado_esperado":"Exclusao permitida"},{"ordem":2,"acao":"Com a conta sem esse verbo (mesmo com papel de gestao), tentar excluir","resultado_esperado":"A acao esta ausente ou e recusada; a manifestacao permanece"}]'::jsonb,
    resultado_esperado = 'Somente quem tem Excluir amplo no perfil exclui; os demais nao conseguem remover.',
    observacoes = 'Trava: perfil_restringe_escrita_ouvidoria_del (perfil_escreve). Cobertura de motor: OUV-060.'
  WHERE codigo = 'OUV-033';

  UPDATE public.qa_casos_teste SET
    titulo = 'Quem tem Ouvidoria em Proprio usuario ve apenas as proprias manifestacoes identificadas',
    objetivo = 'Na fila, quem tem Ouvidoria em Proprio usuario no perfil nao pode ver manifestacoes de outras pessoas — enxerga so as proprias, nao anonimas, qualquer que seja o papel tecnico (inclusive gestor). Ver a fila alheia seria vazamento de dado sensivel.',
    pre_condicoes = 'Usuario com perfil de Ouvidoria em Proprio usuario (com ou sem papel de gestao); manifestacoes de varios autores no tenant.',
    passos = '[{"ordem":1,"acao":"Com o usuario de escopo Proprio usuario, abrir a aba Minhas Manifestacoes","resultado_esperado":"Aparecem apenas as manifestacoes identificadas dele"},{"ordem":2,"acao":"Com perfil que tem Ouvidoria em escopo amplo (ou o dono), abrir a aba Todas Manifestacoes","resultado_esperado":"Aparecem todas as manifestacoes do tenant"}]'::jsonb,
    resultado_esperado = 'A visibilidade da fila respeita o perfil; quem esta em Proprio usuario nao ve manifestacao de terceiros.',
    observacoes = 'Trava: perfil_restringe_leitura_ouvidoria (modulo ouvidoria). Cobertura: OUV-060 (motor) e OUV-061..063 (tela).'
  WHERE codigo = 'OUV-034';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Atualizacao de OUV-033/034 nao aplicada: %', SQLERRM;
END $atual$;

DO $ponte$
BEGIN
  DELETE FROM public.qa_cobertura_e2e WHERE codigo IN ('OUV-061', 'OUV-062', 'OUV-063');
  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES
  ('OUV-061', 'cypress/e2e/ouvidoria-escopo.cy.ts', 'usuário com Ouvidoria em Próprio usuário vê só as próprias manifestações, mesmo com papel de gestão'),
  ('OUV-062', 'cypress/e2e/ouvidoria-escopo.cy.ts', 'usuário com Ouvidoria em Próprio usuário não recebe os controles de gestão'),
  ('OUV-063', 'cypress/e2e/ouvidoria-escopo.cy.ts', 'o dono continua vendo todas as manifestações da empresa');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ponte e2e (ouvidoria escopo) nao gravada: %', SQLERRM;
END $ponte$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'pessoas-cultura/ouvidoria');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao.', SQLERRM;
END $roda$;
