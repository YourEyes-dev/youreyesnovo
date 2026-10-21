-- =========================================================
-- QA — Onda 1 (acesso crítico e links públicos): casos e2e + pontes Cypress.
--
-- Plano: docs/PLANO_COBERTURA_CYPRESS.md. Liga ao Cypress os casos de autenticação
-- que já estavam documentados e sem teste (AUTH-002, 010, 011, 021, 031) e documenta
-- 12 casos novos: recuperação de senha (AUTH-040), ativação de conta (AUTH-041) e os
-- 10 links públicos de assinatura/ouvidoria/entrevista com token inexistente
-- (AUTH-050..059). Specs: cypress/e2e/acesso-critico.cy.ts e links-publicos.cy.ts.
--
-- Idempotente: casos com ON CONFLICT (codigo) DO NOTHING; pontes por delete-then-insert
-- (converge o título do it() em qualquer estado). Só dado de QA — sem tabela nova.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/autenticacao';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo infraestrutura-auth/autenticacao não encontrado — casos não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'AUTH-040', 'Recuperar senha barra e-mail inválido e oferece voltar ao login',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'O usuário que esqueceu a senha chega a esta tela sozinho. Se o formulário aceitar e-mail inválido ou não oferecer saída, ele fica sem caminho de volta.',
   'Visitante sem sessão.',
   '[{"ordem": 1, "acao": "Abrir /forgot-password e clicar em Enviar link de recuperação com o e-mail vazio", "resultado_esperado": "Aparece E-mail inválido e a tela não avança"}, {"ordem": 2, "acao": "Clicar em Voltar para o login", "resultado_esperado": "Volta à tela de Login"}]'::jsonb,
   'A recuperação de senha valida o e-mail e sempre oferece o caminho de volta ao login.', NULL),
  (v_mod, 'AUTH-041', 'Ativar conta sem o link do convite mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'A ativação de conta nasce de um convite por e-mail. Quem chega sem o token precisa ver uma explicação e um caminho, não uma tela em branco.',
   'Visitante sem sessão.',
   '[{"ordem": 1, "acao": "Abrir /ativar-conta sem o parâmetro do convite", "resultado_esperado": "Aparece Link Inválido com a orientação de solicitar novo convite"}, {"ordem": 2, "acao": "Clicar em Ir para Login", "resultado_esperado": "Volta à tela de Login"}]'::jsonb,
   'Ativar conta sem token explica o problema e leva ao login.', NULL),
  (v_mod, 'AUTH-050', 'Aceite de documento com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /aceite-documento/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-051', 'Assinatura de contrato com link inexistente mostra contrato não encontrado',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /contrato-assinatura/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Contrato não encontrado\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-052', 'Assinar contrato de parceiro com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /assinar-contrato/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido ou expirado.\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-053', 'Assinatura de férias com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /ferias-assinatura/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-054', 'Assinatura de PDI com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /pdi-assinatura/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-055', 'Assinatura de experiência com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /experiencia-assinatura/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido ou expirado\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-056', 'Assinatura do manual de função com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /manual-funcao/assinatura/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido.\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-057', 'Assinatura de ordem de serviço com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /os/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido.\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-058', 'Ouvidoria externa com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /ouvidoria-externa/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL),
  (v_mod, 'AUTH-059', 'Entrevista guiada com link inexistente mostra link inválido',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Link público enviado por e-mail ou WhatsApp. Se a tela quebrar com um token inválido, quem recebeu o link fica sem explicação e a falha só aparece quando alguém reclama.',
   'Visitante sem sessão (link público).',
   '[{"ordem": 1, "acao": "Abrir /entrevista/<token> com um token que não existe, sem estar logado", "resultado_esperado": "A tela monta e mostra \"Link inválido\", sem pedir login nem cair na tela de erro da aplicação"}]'::jsonb,
   'Com token inexistente a tela mostra o estado de link inválido próprio e não derruba a aplicação.', NULL)
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

DO $ponte$
BEGIN
  DELETE FROM public.qa_cobertura_e2e
  WHERE codigo IN ('AUTH-002', 'AUTH-010', 'AUTH-011', 'AUTH-021', 'AUTH-031', 'AUTH-040', 'AUTH-041', 'AUTH-050', 'AUTH-051', 'AUTH-052', 'AUTH-053', 'AUTH-054', 'AUTH-055', 'AUTH-056', 'AUTH-057', 'AUTH-058', 'AUTH-059');

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES
  ('AUTH-002', 'cypress/e2e/acesso-critico.cy.ts', 'login com credenciais válidas entra no sistema'),
  ('AUTH-010', 'cypress/e2e/acesso-critico.cy.ts', 'a sessão persiste ao recarregar a página'),
  ('AUTH-011', 'cypress/e2e/acesso-critico.cy.ts', 'logout limpa a sessão'),
  ('AUTH-021', 'cypress/e2e/acesso-critico.cy.ts', 'área de superadmin barra quem não é superadmin'),
  ('AUTH-031', 'cypress/e2e/acesso-critico.cy.ts', 'redefinir senha sem sessão de recuperação é barrado'),
  ('AUTH-040', 'cypress/e2e/acesso-critico.cy.ts', 'recuperar senha barra e-mail inválido e oferece voltar ao login'),
  ('AUTH-041', 'cypress/e2e/acesso-critico.cy.ts', 'ativar conta sem o link do convite mostra link inválido'),
  ('AUTH-050', 'cypress/e2e/links-publicos.cy.ts', 'aceite de documento com link inexistente mostra link inválido'),
  ('AUTH-051', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de contrato com link inexistente mostra contrato não encontrado'),
  ('AUTH-052', 'cypress/e2e/links-publicos.cy.ts', 'assinar contrato de parceiro com link inexistente mostra link inválido'),
  ('AUTH-053', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de férias com link inexistente mostra link inválido'),
  ('AUTH-054', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de PDI com link inexistente mostra link inválido'),
  ('AUTH-055', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de experiência com link inexistente mostra link inválido'),
  ('AUTH-056', 'cypress/e2e/links-publicos.cy.ts', 'assinatura do manual de função com link inexistente mostra link inválido'),
  ('AUTH-057', 'cypress/e2e/links-publicos.cy.ts', 'assinatura de ordem de serviço com link inexistente mostra link inválido'),
  ('AUTH-058', 'cypress/e2e/links-publicos.cy.ts', 'ouvidoria externa com link inexistente mostra link inválido'),
  ('AUTH-059', 'cypress/e2e/links-publicos.cy.ts', 'entrevista guiada com link inexistente mostra link inválido');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ponte e2e (acesso crítico) não gravada: %', SQLERRM;
END $ponte$;

SELECT 'casos AUTH novos documentados' AS item,
       (SELECT count(*)::text FROM public.qa_casos_teste WHERE codigo ~ '^AUTH-0(4[01]|5[0-9])$') AS valor
UNION ALL SELECT 'pontes AUTH ligadas ao Cypress',
       (SELECT count(*)::text FROM public.qa_cobertura_e2e WHERE codigo LIKE 'AUTH-%' AND spec IN ('cypress/e2e/acesso-critico.cy.ts','cypress/e2e/links-publicos.cy.ts'));
