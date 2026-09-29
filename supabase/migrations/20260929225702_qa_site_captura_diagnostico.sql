-- =====================================================================
-- QA — Site institucional: captura do lead do diagnóstico psicossocial.
--
-- Entrega da captura do tráfego pago (29/09/2026): Pixel só no domínio de
-- produção, UTMs da primeira visita acompanhando o lead, Lead enviado também
-- pelo servidor (função meta-capi, mesmo event_id do navegador) e contato
-- criado/atualizado no HubSpot pelo servidor (função hubspot-lead).
--
-- O site ainda não tinha módulo nem caso na Documentação de Testes; este
-- arquivo cria o módulo "Site institucional → Diagnóstico do site" e os três
-- casos de TELA (nível e2e), já ligados aos it() de
-- cypress/e2e/site-diagnostico.cy.ts pela ponte qa_cobertura_e2e.
--
-- Não há caso de motor (api): nada mudou no banco. As UTMs vão dentro do
-- JSON diagnostico_resultado (chave origem), que já existia.
--
-- Idempotente (ON CONFLICT DO NOTHING). Script de entrega equivalente:
-- docs/script_qa_site_captura_diagnostico.sql.
-- =====================================================================
SET lock_timeout = '10s';

DO $doc$
DECLARE v_pai uuid; v_mod uuid;
BEGIN
  v_pai := (SELECT id FROM public.qa_modulos WHERE path = 'site-institucional' LIMIT 1);
  IF v_pai IS NULL THEN
    INSERT INTO public.qa_modulos (label, path, icone, ordem)
    VALUES ('Site institucional', 'site-institucional', '🌐', 95)
    RETURNING id INTO v_pai;
  END IF;

  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'site-institucional/diagnostico' LIMIT 1);
  IF v_mod IS NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, icone, ordem)
    VALUES (v_pai, 'Diagnóstico do site (tráfego pago)', 'site-institucional/diagnostico', '🎯', 1)
    RETURNING id INTO v_mod;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'SITE-001',
     'Conclusão do diagnóstico envia o Lead ao servidor da Meta e o contato ao HubSpot, com as UTMs da chegada e sem as respostas',
     'feliz', 'critica', 'aprovado', 'e2e',
     'LGPD art. 6º (finalidade e necessidade) e art. 11 (dado sensível): ao CRM vai só o índice agregado',
     'O lead pago só vale se chegar ao CRM com a campanha de origem e se a Meta receber a conversão pelo servidor (mesmo event_id do Pixel, para deduplicar). As UTMs ficam só na primeira tela; precisam sobreviver à navegação. As respostas do questionário nunca saem para o HubSpot.',
     'Visitante sem login no site, chegando pelo endereço de anúncio (?utm_source=...&utm_campaign=...#diagnostico).',
     '[{"ordem":1,"acao":"Abrir o site com ?utm_source=qa&utm_campaign=sst_qa&utm_content=cypress#diagnostico e depois perder a query (navegação)","resultado_esperado":"As UTMs continuam guardadas na sessão"},
       {"ordem":2,"acao":"Responder porte, setor, as 8 perguntas e o contato; clicar Ver meu resultado","resultado_esperado":"O lead gravado leva diagnostico_resultado.origem com as UTMs"},
       {"ordem":3,"acao":"Conferir a chamada à função meta-capi","resultado_esperado":"event_name Lead, event_id preenchido, e-mail informado, envio em text/plain (sem preflight)"},
       {"ordem":4,"acao":"Conferir a chamada à função hubspot-lead","resultado_esperado":"formulario site-diagnostico-psicossocial, score numérico, angulo_dor sst, fonte_origem qa / sst_qa / cypress e NENHUMA resposta individual"}]'::jsonb,
     'Lead gravado com a origem; Meta (servidor) e HubSpot acionados com os dados certos; respostas não saem para o CRM.',
     'O teste intercepta a gravação e as duas funções: confere o que a tela manda. A entrega real na Meta (Eventos de teste, META_TEST_EVENT_CODE) e no HubSpot é conferida à mão com contato fictício.'),

    (v_mod, 'SITE-002',
     'Fora do domínio de produção o Pixel da Meta não carrega',
     'negativo', 'alta', 'aprovado', 'e2e',
     NULL,
     'Acessos do site de teste (github.io), dos domínios do Lovable e de pré-visualizações estavam contaminando o conjunto de dados da Meta (49,5 mil de ~63 mil PageViews em 09/2026). O Pixel só pode inicializar em youreyes.com.br e www.youreyes.com.br.',
     'Site de teste aberto (host diferente de youreyes.com.br).',
     '[{"ordem":1,"acao":"Abrir o site de teste com UTMs de anúncio","resultado_esperado":"window.fbq não existe"},
       {"ordem":2,"acao":"Observar a rede","resultado_esperado":"Nenhuma chamada a connect.facebook.net nem a facebook.com/tr"}]'::jsonb,
     'Pixel ausente fora da produção.',
     'A lista de hosts vive em index.html e em src/lib/siteOrigem.ts (HOSTS_PRODUCAO). Na produção o Pixel continua disparando PageView e Lead — conferir no Events Manager.'),

    (v_mod, 'SITE-003',
     'Falha no servidor da Meta ou do HubSpot não impede o resultado do diagnóstico',
     'excecao', 'alta', 'aprovado', 'e2e',
     NULL,
     'Os envios à Meta e ao HubSpot são fire-and-forget: se qualquer um cair, o visitante vê o resultado e o botão do WhatsApp normalmente, sem aviso de erro.',
     'Função meta-capi sem rede e hubspot-lead devolvendo 500.',
     '[{"ordem":1,"acao":"Concluir o diagnóstico com as duas funções falhando","resultado_esperado":"Tela Seu resultado e botão Falar com um especialista visíveis"},
       {"ordem":2,"acao":"Procurar aviso de erro","resultado_esperado":"Nenhum aviso de falha ao registrar"}]'::jsonb,
     'Experiência do visitante intacta com Meta/HubSpot fora do ar.',
     NULL)
  ON CONFLICT (codigo) DO NOTHING;

  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste) VALUES
    ('SITE-001', 'cypress/e2e/site-diagnostico.cy.ts',
     'SITE-001: conclusão envia o Lead ao servidor e o contato ao HubSpot com as UTMs da chegada, sem as respostas'),
    ('SITE-002', 'cypress/e2e/site-diagnostico.cy.ts',
     'SITE-002: fora do domínio de produção o Pixel da Meta não carrega'),
    ('SITE-003', 'cypress/e2e/site-diagnostico.cy.ts',
     'SITE-003: falha no servidor da Meta ou do HubSpot não impede o resultado')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: SITE-001..003 (e2e) documentados e ligados ao Cypress.';
END $doc$;
