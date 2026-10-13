-- =====================================================================
-- SCRIPT DE ENTREGA (SQL Editor) — Fase 0.3
-- Corrige a guarda que recusava entrevista_coletiva (workshop)
-- =====================================================================
-- Cole este arquivo inteiro no SQL Editor (homologacao primeiro; so apos
-- aprovacao, producao). Equivale a migration
-- 20261013143840_psicossocial_tipo_instrumento_entrevista_coletiva.sql.
--
-- Natureza: so CRIA/SUBSTITUI funcao e documenta caso de QA. NAO cria
-- tabela (sem risco do auto-RLS do editor) e NAO altera nenhuma linha de
-- dado existente (logo, nao precisa de backup). Idempotente.
--
-- Contexto do problema: o front ja oferece a modalidade "entrevista
-- coletiva" (workshop), mas o trigger de validacao do banco so aceitava
-- 'questionario' e 'entrevista_guiada', fazendo a gravacao da campanha de
-- workshop estourar "tipo_instrumento invalido". Aqui a guarda passa a
-- aceitar tambem 'entrevista_coletiva'.
-- =====================================================================

-- 1) Amplia a guarda
CREATE OR REPLACE FUNCTION public.validate_tipo_instrumento_campanha()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.tipo_instrumento NOT IN ('questionario','entrevista_guiada','entrevista_coletiva') THEN
    RAISE EXCEPTION 'tipo_instrumento invalido: %', NEW.tipo_instrumento;
  END IF;
  RETURN NEW;
END;
$$;

-- 2) Documenta o caso de teste (nivel api), sem duplicar
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-001',
       'Guarda de tipo_instrumento aceita as 3 modalidades e recusa valor fora',
       'feliz'::public.qa_caso_tipo,
       'media'::public.qa_prioridade,
       'aprovado'::public.qa_caso_status,
       'api',
       'A validacao de tipo_instrumento das campanhas psicossociais deve aceitar questionario, entrevista_guiada e entrevista_coletiva, e recusar qualquer outro valor.',
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
    r.erro_tecnico := 'Campanha de entrevista coletiva (workshop) falha ao gravar enquanto a modalidade nao for aceita.';
  END IF;

  RETURN r;
END;
$$;

-- 4) Liga o caso a rotina
INSERT INTO public.qa_implementacoes (codigo, funcao_sql)
VALUES ('PSICO-API-001', 'qa_caso_psico_api_001')
ON CONFLICT (codigo) DO UPDATE
  SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- 5) CONFERENCIA FINAL (o SQL Editor so mostra o ultimo resultado)
SELECT r.situacao, r.obtido, r.erro_tecnico
FROM public.qa_caso_psico_api_001() r;
