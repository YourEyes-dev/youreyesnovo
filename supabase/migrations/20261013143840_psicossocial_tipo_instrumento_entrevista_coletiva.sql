-- =====================================================================
-- Fase 0.3 — Corrige regressao: entrevista_coletiva rejeitada pelo banco
-- =====================================================================
-- O front (src/types/psicossocial.ts) ja trata tres modalidades de
-- instrumento: 'questionario', 'entrevista_guiada' e 'entrevista_coletiva'
-- (isEntrevistaInstrumento cobre as duas ultimas; workshop herda o fluxo
-- da entrevista guiada). Mas o trigger de validacao do banco
-- (validate_tipo_instrumento_campanha) so aceitava as duas primeiras, de
-- modo que criar/atualizar uma campanha de entrevista COLETIVA estourava
-- "tipo_instrumento invalido" na gravacao. Esta migration alinha o banco
-- ao contrato do front, apenas AMPLIANDO o conjunto aceito.
--
-- Tres conferencias (regra da casa):
--  1. Onde afeta: so a funcao de validacao da coluna tipo_instrumento das
--     campanhas psicossociais. Nao altera nenhuma linha; so passa a aceitar
--     um valor que antes era recusado (mudanca retrocompativel).
--  2. Documentacao de Testes: caso PSICO-API-001 (nivel api) documenta os
--     valores aceitos pela guarda.
--  3. Execucao de Testes: rotina qa_caso_psico_api_001() confere, somente
--     leitura, que a guarda aceita as tres modalidades e recusa valor fora.
--
-- Idempotente: CREATE OR REPLACE / ON CONFLICT. Rodar duas vezes nao quebra.
-- Script de entrega equivalente: docs/script_psicossocial_tipo_instrumento_entrevista_coletiva.sql
-- =====================================================================

-- 1) Amplia a guarda para aceitar a entrevista coletiva (workshop)
CREATE OR REPLACE FUNCTION public.validate_tipo_instrumento_campanha()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.tipo_instrumento NOT IN ('questionario','entrevista_guiada','entrevista_coletiva') THEN
    RAISE EXCEPTION 'tipo_instrumento invalido: %', NEW.tipo_instrumento;
  END IF;
  RETURN NEW;
END;
$$;

-- 2) Documenta o caso de teste (nivel api)
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-001',
       'Guarda de tipo_instrumento aceita as 3 modalidades e recusa valor fora',
       'feliz'::public.qa_caso_tipo,
       'media'::public.qa_prioridade,
       'aprovado'::public.qa_caso_status,
       'api',
       'A validacao de tipo_instrumento das campanhas psicossociais deve aceitar questionario, entrevista_guiada e entrevista_coletiva, e recusar qualquer outro valor. Garante que campanha de workshop (entrevista coletiva) grava no banco.',
       'Rotina read-only confere o corpo da funcao validate_tipo_instrumento_campanha.'
FROM public.qa_modulos m
WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

-- 3) Rotina de execucao (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_psico_api_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_aceita_coletiva boolean;
  v_aceita_guiada boolean;
  v_aceita_questionario boolean;
BEGIN
  IF to_regprocedure('public.validate_tipo_instrumento_campanha()') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcao validate_tipo_instrumento_campanha nao existe nesta base.';
    RETURN r;
  END IF;

  v_def := pg_get_functiondef('public.validate_tipo_instrumento_campanha()'::regprocedure);

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir se a guarda aceita as tres modalidades de instrumento';
  r.esperado    := 'questionario, entrevista_guiada e entrevista_coletiva aceitos';

  v_aceita_questionario := position('''questionario''' in v_def) > 0;
  v_aceita_guiada       := position('''entrevista_guiada''' in v_def) > 0;
  v_aceita_coletiva     := position('''entrevista_coletiva''' in v_def) > 0;

  IF v_aceita_questionario AND v_aceita_guiada AND v_aceita_coletiva THEN
    r.situacao := 'passou';
    r.obtido   := 'Guarda aceita as tres modalidades (questionario, entrevista_guiada, entrevista_coletiva).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format(
      'Guarda incompleta: questionario=%s, entrevista_guiada=%s, entrevista_coletiva=%s.',
      v_aceita_questionario, v_aceita_guiada, v_aceita_coletiva);
    r.erro_tecnico := 'A campanha de entrevista coletiva (workshop) falha ao gravar enquanto a modalidade nao for aceita pela guarda.';
  END IF;

  RETURN r;
END;
$$;

-- 4) Liga o caso documentado a rotina de execucao
INSERT INTO public.qa_implementacoes (codigo, funcao_sql)
VALUES ('PSICO-API-001', 'qa_caso_psico_api_001')
ON CONFLICT (codigo) DO UPDATE
  SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
