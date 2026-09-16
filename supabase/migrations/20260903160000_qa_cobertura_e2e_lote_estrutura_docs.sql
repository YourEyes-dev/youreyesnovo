-- =========================================================
-- QA — Ponte de cobertura e2e: specs de tela de Documentos, Hub Contábil,
-- Prestadores/Terceiros, Departamentos, Cargos e Estabelecimentos (26 ligações).
--
-- Liga cada it() novo (cypress/e2e/{documentos,hub-contabil,terceiros,
-- departamentos,cargos,estabelecimentos}.cy.ts) ao caso documentado que ele
-- executa, em qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta
-- ponte, a guarda scripts/verificar-cobertura-e2e.mjs trataria os it() novos
-- como "inventados" e reprovaria a corrida.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Documentos
  ('DOCS-TELA-01', 'cypress/e2e/documentos.cy.ts',        'abre o módulo Documentos com as abas'),
  ('DOCS-TELA-03', 'cypress/e2e/documentos.cy.ts',        'abre o formulário de Nova Pasta'),
  ('DOCS-TELA-04', 'cypress/e2e/documentos.cy.ts',        'abre o formulário de Upload'),
  ('DOCS-TELA-05', 'cypress/e2e/documentos.cy.ts',        'abre a aba Conformidade'),
  ('DOCS-TELA-06', 'cypress/e2e/documentos.cy.ts',        'abre a aba Governança'),
  ('DOCS-TELA-09', 'cypress/e2e/documentos.cy.ts',        'abre a aba Auditoria'),
  -- Hub Contábil
  ('HUBC-TELA-01', 'cypress/e2e/hub-contabil.cy.ts',      'abre o Hub Contábil com o painel e as abas'),
  ('HUBC-TELA-03', 'cypress/e2e/hub-contabil.cy.ts',      'abre o modal de novo processo'),
  ('HUBC-TELA-04', 'cypress/e2e/hub-contabil.cy.ts',      'abre uma aba por tipo (Férias)'),
  ('HUBC-TELA-05', 'cypress/e2e/hub-contabil.cy.ts',      'abre a aba Kanban'),
  ('HUBC-TELA-07', 'cypress/e2e/hub-contabil.cy.ts',      'abre a aba Relatórios'),
  ('HUBC-TELA-08', 'cypress/e2e/hub-contabil.cy.ts',      'abre a aba Config'),
  -- Prestadores / Terceiros
  ('TERC-TELA-01', 'cypress/e2e/terceiros.cy.ts',         'abre o módulo Terceiros com as abas'),
  ('TERC-TELA-02', 'cypress/e2e/terceiros.cy.ts',         'abre o formulário de Novo Terceiro'),
  ('TERC-TELA-03', 'cypress/e2e/terceiros.cy.ts',         'abre a aba Terceiros e tem a busca'),
  ('TERC-TELA-04', 'cypress/e2e/terceiros.cy.ts',         'abre a aba Permissões de Trabalho'),
  ('TERC-TELA-05', 'cypress/e2e/terceiros.cy.ts',         'abre a aba Vencimentos'),
  ('TERC-TELA-06', 'cypress/e2e/terceiros.cy.ts',         'abre a aba Dashboard'),
  -- Departamentos
  ('DEPTO-TELA-01', 'cypress/e2e/departamentos.cy.ts',    'abre o módulo Departamentos com a lista'),
  ('DEPTO-TELA-02', 'cypress/e2e/departamentos.cy.ts',    'abre o formulário de Novo Departamento'),
  ('DEPTO-TELA-03', 'cypress/e2e/departamentos.cy.ts',    'a busca filtra a lista de departamentos'),
  -- Cargos
  ('CARGO-TELA-01', 'cypress/e2e/cargos.cy.ts',           'abre o módulo Cargos com a lista'),
  ('CARGO-TELA-02', 'cypress/e2e/cargos.cy.ts',           'abre o formulário de Novo Cargo com as abas'),
  ('CARGO-TELA-06', 'cypress/e2e/cargos.cy.ts',           'a busca filtra a lista de cargos'),
  -- Estabelecimentos
  ('ESTAB-TELA-01', 'cypress/e2e/estabelecimentos.cy.ts', 'pede para selecionar a empresa (matriz)'),
  ('ESTAB-TELA-07', 'cypress/e2e/estabelecimentos.cy.ts', 'tem a busca de empresa por CNPJ')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
