-- =====================================================================
-- ENTREGA — Unificacao de feriados, FASE 4 (tres conferencias / QA)
--
-- Documenta e liga a execucao dos testes da unificacao:
--  (1) FER-006 (api, motor): guard do resolver — feriados_da_empresa NAO le
--      mais a abrangencia 'filial' de public.feriados. Rotina SOMENTE LEITURA
--      (le a definicao da funcao); nao semeia nada.
--  (2) PONTO-HOM-F1 (e2e, tela): a tela de Feriados tem as duas secoes
--      (Calendario da unidade / Feriados por localizacao) e o cadastro por
--      localizacao nao oferece 'Filial'. Ligado ao it() de ponto.cy.ts.
--
-- So-cria-funcao (nao cria tabela): nao aciona o auto-RLS do editor. Idempotente
-- (ON CONFLICT). Rode o arquivo inteiro de uma vez.
-- Conferencia esperada no fim: casos_documentados=2, impl_fer006=1,
-- ponte_e2e=1, fer006_situacao='passou'.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_caso_fer_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_def text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Ler a definicao de feriados_da_empresa e checar a origem filial';
  r.esperado    := 'O resolver nao le mais a abrangencia filial de public.feriados (unificada no Calendario da unidade).';

  IF to_regprocedure('public.feriados_da_empresa(uuid,uuid,date,date)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcao feriados_da_empresa ausente nesta base.';
    RETURN r;
  END IF;

  v_def := pg_get_functiondef('public.feriados_da_empresa(uuid,uuid,date,date)'::regprocedure);

  IF position('abrangencia = ''filial''' IN v_def) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Resolver sem o ramo filial: feriado de unidade vem do calendario (modelo B).';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'O resolver ainda le a abrangencia filial de public.feriados — unificacao revertida?';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos de feriados nao documentados.';
    RETURN;
  END IF;

  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo jornada-rotina/ponto ausente; casos de feriados nao documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'FER-006',
   'O resolver de feriados nao le mais a abrangencia filial (unificada no Calendario da unidade)',
   'feliz', 'alta', 'aprovado', 'api',
   'Portaria 671/2021 MTP; CLT art. 68 e Lei 605/1949 (feriados)',
   'Apos a unificacao (Fases 1-2), feriado especifico de uma unidade mora so no Calendario da unidade (feriado_tabela_*). A fonte unica feriados_da_empresa deixou de ler a abrangencia filial de public.feriados. Guard contra reversao acidental.',
   'Resolver feriados_da_empresa presente.',
   '[{"ordem":1,"acao":"Ler a definicao de public.feriados_da_empresa","resultado_esperado":"A definicao nao contem o ramo da abrangencia filial do lado de public.feriados"}]'::jsonb,
   'O resolver resolve feriado de unidade pelo calendario (modelo B); a abrangencia filial de public.feriados nao e mais lida.',
   'Unificacao de feriados, Fase 4. Complementa FER-001..005 (gestao do calendario).'),

  (v_mod, 'PONTO-HOM-F1',
   'Tela de Feriados unificada: Calendario da unidade e Feriados por localizacao, sem a abrangencia Filial',
   'feliz', 'media', 'aprovado', 'e2e',
   'Portaria 671/2021 MTP (art. 94); CLT art. 68',
   'A tela de Feriados separa com clareza o Calendario da unidade (feriado so daquela unidade) dos Feriados por localizacao (nacional/estadual/municipal). O cadastro por localizacao nao oferece mais a opcao Filial — feriado de unidade vai no calendario.',
   'Usuario RH/gestor; ambiente de teste.',
   '[{"ordem":1,"acao":"Em Ponto > Configuracoes > Feriados, abrir a aba","resultado_esperado":"Aparecem as duas secoes: Calendario da unidade e Feriados por localizacao"},
     {"ordem":2,"acao":"Clicar em Adicionar feriado e abrir a Abrangencia","resultado_esperado":"So Estadual e Municipal; a opcao Filial nao existe mais"}]'::jsonb,
   'A tela mostra as duas secoes e o cadastro por localizacao nao oferece Filial.',
   'Bateria de Homologacao do Ponto, caso F1. Onde: Ponto > Configuracoes > Feriados.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('FER-006', 'qa_caso_fer_006', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;

  IF to_regclass('public.qa_cobertura_e2e') IS NOT NULL THEN
    INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste, ativo, criado_em) VALUES
      ('PONTO-HOM-F1', 'cypress/e2e/ponto.cy.ts',
       'abre Configurações › Feriados com as duas seções e sem a abrangência Filial',
       true, now())
    ON CONFLICT (codigo) DO UPDATE SET
      spec = EXCLUDED.spec, teste = EXCLUDED.teste, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao de feriados (Fase 4) nao registrada: %', SQLERRM;
END $doc$;

-- ---------------------------------------------------------------------
-- CONFERENCIA (o editor mostra so o ultimo resultado):
--   casos_documentados = 2 ; impl_fer006 = 1 ; ponte_e2e = 1 ;
--   fer006_situacao = 'passou'
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.qa_casos_teste   WHERE codigo IN ('FER-006','PONTO-HOM-F1')) AS casos_documentados,
  (SELECT count(*) FROM public.qa_implementacoes WHERE codigo = 'FER-006' AND ativo)          AS impl_fer006,
  (SELECT count(*) FROM public.qa_cobertura_e2e  WHERE codigo = 'PONTO-HOM-F1' AND ativo)      AS ponte_e2e,
  (public.qa_caso_fer_006()).situacao                                                         AS fer006_situacao;
