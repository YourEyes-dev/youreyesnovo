-- =========================================================
-- QA — Ponte de cobertura e2e: "gaps pequenos" — casos de entrada restantes em
-- módulos que já tinham spec (17 ligações), estendendo os specs existentes.
--
-- Liga cada it() novo aos casos documentados (XXX-TELA-*) que faltavam, em
-- qa_cobertura_e2e (codigo -> spec + título do it()). Sem esta ponte, a guarda
-- scripts/verificar-cobertura-e2e.mjs trataria os it() novos como "inventados".
--
-- Escopo dos it(): entrada segura — abas abrem, guia/formulário abre (só abrir,
-- sem submeter), cartões/chips estáticos aparecem, estados vazios (naturais na
-- ilha de QA ou forçados por busca sem resultado). Nada cria/salva dado.
--
-- Títulos = texto EXATO do it() (normalizado por espaços). Só INSERE dados.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Afastamentos
  ('AFAST-TELA-07', 'cypress/e2e/afastamentos.cy.ts',   'abre a aba FAP/RAT com o cartão de CAT Pendente'),
  -- Cargos
  ('CARGO-TELA-03', 'cypress/e2e/cargos.cy.ts',         'abre a aba SST no formulário de Cargo'),
  ('CARGO-TELA-04', 'cypress/e2e/cargos.cy.ts',         'mostra o seletor de departamentos no formulário de Cargo'),
  ('CARGO-TELA-05', 'cypress/e2e/cargos.cy.ts',         'mostra os campos de faixa salarial no formulário de Cargo'),
  ('CARGO-TELA-07', 'cypress/e2e/cargos.cy.ts',         'mostra o estado vazio ao buscar um cargo inexistente'),
  -- Departamentos
  ('DEPTO-TELA-04', 'cypress/e2e/departamentos.cy.ts',  'mostra o seletor de estabelecimento/obra no formulário de Departamento'),
  ('DEPTO-TELA-05', 'cypress/e2e/departamentos.cy.ts',  'mostra os seletores de gestor titular e substituto'),
  ('DEPTO-TELA-06', 'cypress/e2e/departamentos.cy.ts',  'mostra o estado vazio ao buscar um departamento inexistente'),
  -- Metas
  ('METAS-TELA-02', 'cypress/e2e/metas.cy.ts',          'mostra os cards por nível na Visão Geral'),
  ('METAS-TELA-07', 'cypress/e2e/metas.cy.ts',          'abre o guia rápido do módulo de Metas'),
  ('METAS-TELA-09', 'cypress/e2e/metas.cy.ts',          'mostra o estado vazio em Minhas Metas'),
  -- Plano de Ação
  ('PACAO-TELA-05', 'cypress/e2e/plano-acao.cy.ts',     'tem os chips de prioridade Imediato e Urgente'),
  ('PACAO-TELA-08', 'cypress/e2e/plano-acao.cy.ts',     'abre o painel de filtros avançados'),
  ('PACAO-TELA-09', 'cypress/e2e/plano-acao.cy.ts',     'mostra os cartões de estatística'),
  -- Terceiros
  ('TERC-TELA-07',  'cypress/e2e/terceiros.cy.ts',      'mostra o estado vazio orientando a cadastrar o primeiro terceiro'),
  -- Documentos
  ('DOCS-TELA-07',  'cypress/e2e/documentos.cy.ts',     'abre a aba PDCA'),
  ('DOCS-TELA-08',  'cypress/e2e/documentos.cy.ts',     'abre a aba Notificações')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
