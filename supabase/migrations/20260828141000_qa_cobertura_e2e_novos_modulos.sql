-- =========================================================
-- QA — Ponte de cobertura e2e para os specs dos novos módulos (27 ligações)
--
-- Liga cada it() novo (cypress/e2e/*.cy.ts) ao caso documentado que ele
-- executa, na tabela qa_cobertura_e2e (codigo -> spec + título do it()).
-- Sem esta ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os
-- it() novos como "inventados" e reprovaria a corrida.
--
-- Os títulos abaixo são o texto EXATO do it() (normalizado por espaços),
-- como o Cypress reporta e como a guarda cruza. Renomear um it() sem
-- atualizar aqui quebra a ligação (a guarda avisa).
--
-- Só INSERE dados. Idempotente: ON CONFLICT (codigo) DO NOTHING.
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
