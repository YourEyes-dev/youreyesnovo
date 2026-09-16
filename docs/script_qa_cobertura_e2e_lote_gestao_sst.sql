-- =========================================================
-- ENTREGA QA — Ponte de cobertura e2e (24 ligações caso↔teste)
--
-- Cole no SQL Editor da HOMOLOGAÇÃO (e depois, quando aprovado, na produção).
-- Liga os it() de cypress/e2e/{metas,plano-acao,compliance-sst,afastamentos}
-- .cy.ts aos casos <MOD>-TELA-* já documentados. Sem esta ponte, a guarda de
-- cobertura reprova a corrida de Cypress na homologação (it() sem caso).
--
-- Pré-requisito: os casos METAS-TELA-*, PACAO-TELA-*, CSST-TELA-* e
-- AFAST-TELA-* já documentados (scripts dos lotes 1, 2 e 3). Só INSERE dados,
-- idempotente: ON CONFLICT (codigo) DO NOTHING. Termina com uma conferência.
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

-- ── Conferência (última query: é o que o SQL Editor exibe) ──
SELECT split_part(c.codigo,'-TELA-',1) AS familia, count(*) AS ligacoes
FROM public.qa_cobertura_e2e c
WHERE c.spec IN ('cypress/e2e/metas.cy.ts','cypress/e2e/plano-acao.cy.ts',
                 'cypress/e2e/compliance-sst.cy.ts','cypress/e2e/afastamentos.cy.ts')
GROUP BY 1 ORDER BY 1;
