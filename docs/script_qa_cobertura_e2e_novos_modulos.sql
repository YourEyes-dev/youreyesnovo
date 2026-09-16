-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e dos specs dos novos módulos (27 ligações)
--
-- Cole no SQL Editor da HOMOLOGACAO (projeto fgsblefvdabgdouipigz), DEPOIS
-- de já ter rodado docs/script_qa_casos_novos_modulos_leva2.sql (os 92 casos
-- documentados). Esta ponte liga cada it() novo dos specs Cypress ao caso
-- que ele executa, para a guarda de cobertura reconhecer os testes como
-- documentados (e não como "inventados").
--
-- Só INSERE dados em qa_cobertura_e2e (não mexe em estrutura nem na
-- fidelidade com a produção). Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- Ao final, uma conferência SELECT mostra as 27 ligações registradas.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Avaliações
  ('AVAL-001',  'cypress/e2e/avaliacoes.cy.ts',            'carrega o módulo de Avaliações com as abas do fluxo'),
  ('AVAL-002',  'cypress/e2e/avaliacoes.cy.ts',            'mostra a Inbox de avaliações'),
  ('AVAL-050',  'cypress/e2e/avaliacoes.cy.ts',            'abre a aba de Resultados de um ciclo'),
  ('AVAL-051',  'cypress/e2e/avaliacoes.cy.ts',            'abre a matriz 9-Box'),
  -- Trilhas
  ('TRILHA-001','cypress/e2e/trilhas.cy.ts',               'carrega o módulo de Trilhas com as abas'),
  ('TRILHA-002','cypress/e2e/trilhas.cy.ts',               'mostra as trilhas atribuídas em Minhas Trilhas'),
  ('TRILHA-040','cypress/e2e/trilhas.cy.ts',               'abre a aba de Gamificação'),
  -- Feedback & Ocorrências
  ('FBK-001',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'carrega o módulo com as quatro abas'),
  ('FBK-011',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'mantém o registro de feedback desabilitado sem os campos obrigatórios'),
  ('FBK-020',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'abre o histórico de Feedbacks'),
  ('FBK-040',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'abre o histórico de Ocorrências'),
  -- Saúde Ocupacional (ASO)
  ('ASO-001',   'cypress/e2e/saude-ocupacional.cy.ts',     'carrega o painel de ASOs com os cards de resumo'),
  ('ASO-010',   'cypress/e2e/saude-ocupacional.cy.ts',     'abre o formulário de Novo ASO'),
  ('ASO-020',   'cypress/e2e/saude-ocupacional.cy.ts',     'filtra a lista pela busca'),
  ('ASO-021',   'cypress/e2e/saude-ocupacional.cy.ts',     'mostra vazio orientativo quando a busca não acha'),
  -- Mural Interno
  ('MURAL-001', 'cypress/e2e/mural.cy.ts',                 'carrega o Mural com o compositor e o feed'),
  ('MURAL-050', 'cypress/e2e/mural.cy.ts',                 'trata o feed (posts ou estado vazio) sem erro'),
  ('MURAL-060', 'cypress/e2e/mural.cy.ts',                 'atualiza o feed'),
  -- Meu Bem-Estar
  ('BEM-001',   'cypress/e2e/bem-estar.cy.ts',             'carrega o Mapa de Bem-Estar'),
  ('BEM-002',   'cypress/e2e/bem-estar.cy.ts',             'exibe o aviso de espaço seguro'),
  ('BEM-011',   'cypress/e2e/bem-estar.cy.ts',             'abre o painel ao clicar num eixo'),
  -- Configurações
  ('CFG-001',   'cypress/e2e/configuracoes.cy.ts',         'carrega Configurações com as abas administrativas'),
  ('CFG-010',   'cypress/e2e/configuracoes.cy.ts',         'abre a aba de Usuários'),
  ('CFG-011',   'cypress/e2e/configuracoes.cy.ts',         'abre a aba de Perfis & Acessos'),
  ('CFG-020',   'cypress/e2e/configuracoes.cy.ts',         'abre a aba de eSocial'),
  ('CFG-030',   'cypress/e2e/configuracoes.cy.ts',         'abre a aba de Auditoria'),
  ('CFG-040',   'cypress/e2e/configuracoes.cy.ts',         'abre a aba de Logo')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

-- =========================================================
-- CONFERÊNCIA (o SQL Editor mostra só o último resultado)
-- Esperado: 27 linhas ligando código -> spec -> título do it().
-- =========================================================
SELECT c.codigo, c.spec, c.teste
FROM public.qa_cobertura_e2e c
WHERE c.spec IN (
        'cypress/e2e/avaliacoes.cy.ts',
        'cypress/e2e/trilhas.cy.ts',
        'cypress/e2e/feedback-ocorrencias.cy.ts',
        'cypress/e2e/saude-ocupacional.cy.ts',
        'cypress/e2e/mural.cy.ts',
        'cypress/e2e/bem-estar.cy.ts',
        'cypress/e2e/configuracoes.cy.ts')
ORDER BY c.spec, c.codigo;
