-- =========================================================
-- QA — Ponte de cobertura e2e: aprofundamento dos 7 módulos (16 ligações)
--
-- Segunda leva de specs (que gravam/validam dado) dos módulos novos.
-- Liga cada it() novo ao caso documentado que ele executa, em
-- qa_cobertura_e2e. Os títulos são o texto EXATO do it() (normalizado por
-- espaços), como a guarda scripts/verificar-cobertura-e2e.mjs cruza.
--
-- Só INSERE dados. Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  -- Mural Interno
  ('MURAL-010', 'cypress/e2e/mural.cy.ts',                 'publica um post de texto'),
  ('MURAL-012', 'cypress/e2e/mural.cy.ts',                 'mantém o Publicar desabilitado com o compositor vazio'),
  ('MURAL-021', 'cypress/e2e/mural.cy.ts',                 'comenta em um post'),
  ('MURAL-030', 'cypress/e2e/mural.cy.ts',                 'exclui o próprio post'),
  -- Meu Bem-Estar
  ('BEM-020',   'cypress/e2e/bem-estar.cy.ts',             'registra uma reflexão num eixo'),
  ('BEM-021',   'cypress/e2e/bem-estar.cy.ts',             'registra uma gratidão no eixo de gratidão'),
  -- Feedback & Ocorrências
  ('FBK-010',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'registra um feedback estruturado'),
  ('FBK-013',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'permite alternar o envio por e-mail ao colaborador'),
  ('FBK-030',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'registra uma ocorrência'),
  ('FBK-050',   'cypress/e2e/feedback-ocorrencias.cy.ts',  'exibe as estatísticas para o gestor'),
  -- Trilhas
  ('TRILHA-010','cypress/e2e/trilhas.cy.ts',               'cria uma trilha na Gestão'),
  -- Saúde Ocupacional (ASO)
  ('ASO-012',   'cypress/e2e/saude-ocupacional.cy.ts',     'bloqueia salvar um ASO sem os campos obrigatórios'),
  -- Avaliações
  ('AVAL-060',  'cypress/e2e/avaliacoes.cy.ts',            'mostra as abas administrativas para o gestor/admin'),
  -- Configurações
  ('CFG-051',   'cypress/e2e/configuracoes.cy.ts',         'não mostra o aviso de configuração pendente quando já configurado'),
  ('CFG-060',   'cypress/e2e/configuracoes.cy.ts',         'percorre as abas administrativas sem erro'),
  ('CFG-070',   'cypress/e2e/configuracoes.cy.ts',         'exige os campos essenciais ao criar um usuário')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
