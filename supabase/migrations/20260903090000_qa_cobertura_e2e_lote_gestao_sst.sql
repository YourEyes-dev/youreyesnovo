-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela dos módulos Metas, Plano de Ação,
-- Compliance SST e Afastamentos (24 ligações).
--
-- Liga cada it() novo (cypress/e2e/{metas,plano-acao,compliance-sst,
-- afastamentos}.cy.ts) ao caso documentado que ele executa, na tabela
-- qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta ponte, a guarda
-- scripts/verificar-cobertura-e2e.mjs trataria os it() novos como "inventados"
-- e reprovaria a corrida.
--
-- Os títulos abaixo são o texto EXATO do it() (normalizado por espaços), como
-- o Cypress reporta e como a guarda cruza. Renomear um it() sem atualizar aqui
-- quebra a ligação (a guarda avisa).
--
-- Só INSERE dados. Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Metas
  ('METAS-TELA-01', 'cypress/e2e/metas.cy.ts',           'abre o módulo Metas com o cabeçalho e as abas'),
  ('METAS-TELA-03', 'cypress/e2e/metas.cy.ts',           'abre o formulário de Nova Meta'),
  ('METAS-TELA-04', 'cypress/e2e/metas.cy.ts',           'abre Minhas Metas com o filtro por nível'),
  ('METAS-TELA-05', 'cypress/e2e/metas.cy.ts',           'abre a aba Consolidação'),
  ('METAS-TELA-06', 'cypress/e2e/metas.cy.ts',           'abre a aba Assistente IA'),
  -- Plano de Ação
  ('PACAO-TELA-01', 'cypress/e2e/plano-acao.cy.ts',      'abre o módulo Plano de Ação com as estatísticas e as abas'),
  ('PACAO-TELA-02', 'cypress/e2e/plano-acao.cy.ts',      'abre o formulário de Nova Ação'),
  ('PACAO-TELA-03', 'cypress/e2e/plano-acao.cy.ts',      'tem a busca por código, título, descrição ou responsável'),
  ('PACAO-TELA-04', 'cypress/e2e/plano-acao.cy.ts',      'filtra pela situação com os chips de status'),
  ('PACAO-TELA-06', 'cypress/e2e/plano-acao.cy.ts',      'abre a aba Minha Caixa'),
  ('PACAO-TELA-07', 'cypress/e2e/plano-acao.cy.ts',      'abre a aba Críticas'),
  -- Compliance SST
  ('CSST-TELA-01',  'cypress/e2e/compliance-sst.cy.ts',  'abre o módulo Compliance SST com o aviso legal e as abas'),
  ('CSST-TELA-02',  'cypress/e2e/compliance-sst.cy.ts',  'abre a aba Importação IA'),
  ('CSST-TELA-03',  'cypress/e2e/compliance-sst.cy.ts',  'abre a aba Documentos'),
  ('CSST-TELA-04',  'cypress/e2e/compliance-sst.cy.ts',  'abre a aba Ordem De Serviço'),
  ('CSST-TELA-05',  'cypress/e2e/compliance-sst.cy.ts',  'abre a aba Painel'),
  ('CSST-TELA-08',  'cypress/e2e/compliance-sst.cy.ts',  'abre a aba eSocial com a auditoria de eventos'),
  ('CSST-TELA-09',  'cypress/e2e/compliance-sst.cy.ts',  'mostra o aviso legal de escopo (PGR, PCMSO, LTCAT)'),
  -- Afastamentos (Central GAF)
  ('AFAST-TELA-01', 'cypress/e2e/afastamentos.cy.ts',    'abre a Central GAF com as abas'),
  ('AFAST-TELA-02', 'cypress/e2e/afastamentos.cy.ts',    'abre a aba Afastamentos'),
  ('AFAST-TELA-03', 'cypress/e2e/afastamentos.cy.ts',    'abre o formulário de Novo Afastamento'),
  ('AFAST-TELA-04', 'cypress/e2e/afastamentos.cy.ts',    'abre a aba Atestados com a ação de Novo Atestado'),
  ('AFAST-TELA-08', 'cypress/e2e/afastamentos.cy.ts',    'abre a aba Pendências'),
  ('AFAST-TELA-09', 'cypress/e2e/afastamentos.cy.ts',    'tem a busca por trabalhador ou CID')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
