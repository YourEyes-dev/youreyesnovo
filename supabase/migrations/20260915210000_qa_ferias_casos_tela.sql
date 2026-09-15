-- =========================================================
-- QA — Férias ganha documentação de TELA (nível e2e) + ponte de cobertura
--
-- O módulo Férias (jornada-rotina/ferias) tem forte cobertura de MOTOR
-- (sondas api: fracionamento, concessivo, saldo, encargos...), mas ZERO
-- documentação de TELA. Este é o mesmo passo que demos em Metas, Plano de
-- Ação, Documentos e Hub Contábil: a bateria estrutural de tela (o que o
-- testador confere clicando) — o módulo monta, o modal principal abre, as
-- abas abrem e o vazio orienta.
--
-- Prefixo -TELA- não colide com as sondas de motor (FERIAS-*, CA-*, INR-*).
-- Todos os casos são DATA-INDEPENDENTES: valem mesmo na ilha vazia (o estado
-- vazio é uma asserção legítima), então não exigem fixtures.
--
-- Duas entregas, como manda a casa: esta migration (que o robô aplica no
-- staging) e docs/script_ferias_casos_tela_homologacao.sql (para colar no
-- SQL Editor da homologação e, depois, da produção).
--
-- Idempotente: ON CONFLICT (codigo) DO NOTHING. Só INSERE documentação.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════════════════════════════════════════════════════
-- FÉRIAS  (jornada-rotina/ferias)  — rota /ferias
-- ══════════════════════════════════════════════════════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/ferias';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/ferias não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'FERIAS-TELA-01', 'Módulo Férias abre com o cabeçalho, os cartões e as abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Porta de entrada do módulo: se não monta, o RH perde a gestão de férias (programação, solicitações, saldos e financeiro).',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar /ferias pelo menu","resultado_esperado":"Título Gestão de Férias carrega"},
     {"ordem":2,"acao":"Conferir a ação principal e as abas","resultado_esperado":"Botão Nova Solicitação; abas Programação, Solicitações, Calendário, Saldos, Financeiro, INR™, Vencimentos, Coletivas, Cultura, Relatórios e Governança"}]'::jsonb,
   'O módulo monta com o cabeçalho, os cartões e as abas.', NULL),

  (v_mod, 'FERIAS-TELA-02', 'Abrir o formulário de Nova Solicitação',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Criar solicitação de férias é o ato central. O modal precisa abrir com o formulário (colaborador, período de gozo, abono).',
   'Rota /ferias.',
   '[{"ordem":1,"acao":"Clicar em Nova Solicitação","resultado_esperado":"Abre o diálogo Nova Solicitação de Férias com o seletor de colaborador e o período de gozo"},
     {"ordem":2,"acao":"Fechar em Cancelar","resultado_esperado":"O diálogo fecha sem criar nada"}]'::jsonb,
   'O formulário de Nova Solicitação abre e fecha sem efeito colateral.', NULL),

  (v_mod, 'FERIAS-TELA-03', 'Solicitações lista as férias ou orienta o vazio',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'A aba Solicitações é onde se acompanham os pedidos. Sem nenhum, não pode ficar em branco: precisa orientar, sem quebrar.',
   'Aba Solicitações.',
   '[{"ordem":1,"acao":"Abrir a aba Solicitações","resultado_esperado":"Aparecem os cartões das solicitações; sem nenhuma, o vazio orientativo (Nenhuma solicitação de férias encontrada), sem quebrar"}]'::jsonb,
   'A aba Solicitações monta a lista ou o vazio orientativo.', NULL),

  (v_mod, 'FERIAS-TELA-04', 'Filtro de status abre com as opções',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O filtro de status recorta as solicitações por situação. Deve abrir com as opções, para escolher o recorte.',
   'Rota /ferias.',
   '[{"ordem":1,"acao":"Abrir o filtro de status","resultado_esperado":"Aparecem as opções Todos Status, Pendente, Aprovado, Em Gozo, Concluído e Recusado"}]'::jsonb,
   'O filtro de status abre com as opções.', NULL),

  (v_mod, 'FERIAS-TELA-05', 'Aba Calendário abre sem erro',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Calendário mostra as férias no tempo. Deve montar mesmo com poucos dados.',
   'Aba Calendário.',
   '[{"ordem":1,"acao":"Abrir a aba Calendário","resultado_esperado":"O calendário de férias carrega sem erro"}]'::jsonb,
   'A aba Calendário abre sem quebrar.', NULL),

  (v_mod, 'FERIAS-TELA-06', 'Aba Saldos abre sem erro',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Saldos mostra o direito de cada colaborador. Deve montar sem erro.',
   'Aba Saldos.',
   '[{"ordem":1,"acao":"Abrir a aba Saldos","resultado_esperado":"O painel de saldos carrega sem erro"}]'::jsonb,
   'A aba Saldos abre sem quebrar.', NULL),

  (v_mod, 'FERIAS-TELA-07', 'Aba Financeiro abre sem erro',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Financeiro traz a provisão e os valores de férias. É a leitura de passivo — deve montar sem erro.',
   'Aba Financeiro.',
   '[{"ordem":1,"acao":"Abrir a aba Financeiro","resultado_esperado":"O painel financeiro de férias carrega sem erro"}]'::jsonb,
   'A aba Financeiro abre sem quebrar.', NULL),

  (v_mod, 'FERIAS-TELA-08', 'Aba INR™ abre sem erro',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A aba INR™ (inteligência) prioriza quem precisa descansar. Deve montar mesmo sem ranking calculado.',
   'Aba INR™.',
   '[{"ordem":1,"acao":"Abrir a aba INR™","resultado_esperado":"O painel de inteligência (ranking / evidência NR-1) carrega sem erro"}]'::jsonb,
   'A aba INR™ abre sem quebrar.', NULL),

  (v_mod, 'FERIAS-TELA-09', 'Aba Vencimentos abre sem erro',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A aba Vencimentos alerta sobre férias a vencer/vencidas — risco de dobra (art. 137). Deve montar sem erro.',
   'Aba Vencimentos.',
   '[{"ordem":1,"acao":"Abrir a aba Vencimentos","resultado_esperado":"O painel de alertas de vencimento carrega sem erro"}]'::jsonb,
   'A aba Vencimentos abre sem quebrar.', NULL),

  (v_mod, 'FERIAS-TELA-10', 'Aba Coletivas abre sem erro',
   'feliz', 'baixa', 'aprovado', 'e2e', NULL,
   'A aba Coletivas trata as férias coletivas (art. 139). Deve montar sem erro.',
   'Aba Coletivas.',
   '[{"ordem":1,"acao":"Abrir a aba Coletivas","resultado_esperado":"O painel de férias coletivas carrega sem erro"}]'::jsonb,
   'A aba Coletivas abre sem quebrar.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Férias (tela): antes=%, depois=% (esperado +10)', v_antes, v_depois;
END $doc$;

-- ══════════════════════════════════════════════════════════
-- Ponte de cobertura e2e: liga cada it() de ferias.cy.ts ao caso.
-- O texto do "teste" é o título EXATO do it() (normalizado por espaços),
-- como o Cypress reporta e como a guarda cruza. Renomear um it() sem
-- atualizar aqui quebra a ligação (a guarda avisa, sem reprovar).
-- ══════════════════════════════════════════════════════════
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('FERIAS-TELA-01', 'cypress/e2e/ferias.cy.ts', 'carrega o módulo de Férias com o cabeçalho e as abas'),
  ('FERIAS-TELA-02', 'cypress/e2e/ferias.cy.ts', 'abre o formulário de Nova Solicitação e fecha sem salvar'),
  ('FERIAS-TELA-03', 'cypress/e2e/ferias.cy.ts', 'mostra as solicitações ou o estado vazio orientativo'),
  ('FERIAS-TELA-04', 'cypress/e2e/ferias.cy.ts', 'o filtro de status abre com as opções'),
  ('FERIAS-TELA-05', 'cypress/e2e/ferias.cy.ts', 'abre a aba Calendário'),
  ('FERIAS-TELA-06', 'cypress/e2e/ferias.cy.ts', 'abre a aba Saldos'),
  ('FERIAS-TELA-07', 'cypress/e2e/ferias.cy.ts', 'abre a aba Financeiro'),
  ('FERIAS-TELA-08', 'cypress/e2e/ferias.cy.ts', 'abre a aba INR™'),
  ('FERIAS-TELA-09', 'cypress/e2e/ferias.cy.ts', 'abre a aba Vencimentos'),
  ('FERIAS-TELA-10', 'cypress/e2e/ferias.cy.ts', 'abre a aba Coletivas')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
