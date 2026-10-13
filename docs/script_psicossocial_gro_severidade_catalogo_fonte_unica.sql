-- =====================================================================
-- SCRIPT DE ENTREGA (SQL Editor) — Fase 0.1
-- Modelo de risco psicossocial: catalogo como fonte unica no GRO
-- =====================================================================
-- Cole o arquivo inteiro no SQL Editor (homologacao primeiro; so apos
-- aprovacao, producao). Equivale a migration
-- 20261013152123_psicossocial_gro_severidade_catalogo_fonte_unica.sql.
--
-- O QUE MUDA: ao exportar riscos psicossociais para o GRO, a aplicacao
-- passou a usar a severidade FIXA do catalogo (nao mais derivada do score)
-- e o nivel da matriz unica do modulo, enviando nivel_risco ja calculado.
-- Este script ajusta o trigger de gro_riscos para PRESERVAR esse nivel nos
-- riscos psicossociais, mantendo INALTERADO o calculo dos riscos
-- fisicos/ergonomicos (a tabela e compartilhada).
--
-- NATUREZA: so CRIA/SUBSTITUI funcao, poe COMMENT e documenta QA. NAO cria
-- tabela (sem a pegadinha do auto-RLS do editor) e NAO altera nenhuma linha
-- de dado (logo, nao precisa de backup). Idempotente.
--
-- OBS sobre riscos ja gravados: linhas psicossociais antigas em gro_riscos
-- mantem o nivel que ja tinham ate serem reprocessadas (reenvio da
-- campanha). O ajuste vale para os proximos envios/reenvios.
-- =====================================================================

-- 1) Trigger: preserva o nivel enviado pela aplicacao para psicossocial
CREATE OR REPLACE FUNCTION public.calcular_nivel_gro_risco()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.subtipo = 'psicossocial' AND NEW.nivel_risco IS NOT NULL THEN
    RETURN NEW;
  END IF;

  NEW.nivel_risco := CASE
    WHEN NEW.probabilidade IN ('alta', 'muito_alta') AND NEW.severidade IN ('grave', 'gravissima') THEN 'critico'
    WHEN NEW.probabilidade IN ('alta', 'muito_alta') AND NEW.severidade = 'moderada' THEN 'alto'
    WHEN NEW.probabilidade = 'moderada' AND NEW.severidade IN ('grave', 'gravissima') THEN 'alto'
    WHEN NEW.probabilidade IN ('baixa', 'muito_baixa') AND NEW.severidade IN ('grave', 'gravissima') THEN 'medio'
    WHEN NEW.probabilidade = 'moderada' AND NEW.severidade = 'moderada' THEN 'medio'
    WHEN NEW.probabilidade IN ('alta', 'muito_alta') AND NEW.severidade = 'leve' THEN 'medio'
    ELSE 'baixo'
  END;
  RETURN NEW;
END;
$$;

-- 2) Marca a tabela orfã como depreciada (dados preservados, nao tocados)
DO $dep$
BEGIN
  IF to_regclass('public.psicossocial_inventario_riscos') IS NOT NULL THEN
    COMMENT ON TABLE public.psicossocial_inventario_riscos IS
      'DEPRECADO (Fase 0.1, 2026-10): inventario legado com enums proprios que nao batem com a matriz GRO 1-5. Nenhum codigo de aplicacao le/escreve esta tabela. Mantida so para preservar dados historicos; nao usar em recurso novo.';
  END IF;
END
$dep$;

-- 3) Documenta o caso de teste (nivel api)
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-002',
       'Nivel de risco psicossocial no GRO preserva a matriz unica (severidade de catalogo)',
       'feliz'::public.qa_caso_tipo,
       'alta'::public.qa_prioridade,
       'aprovado'::public.qa_caso_status,
       'api',
       'O trigger de gro_riscos deve preservar o nivel_risco enviado pela aplicacao quando o risco e psicossocial, sem alterar o calculo dos riscos fisicos/ergonomicos.',
       'Rotina read-only confere a guarda de subtipo no corpo da funcao calcular_nivel_gro_risco.'
FROM public.qa_modulos m
WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

-- 4) Rotina de execucao (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_psico_api_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_tem_guarda boolean;
  v_tem_calculo boolean;
BEGIN
  IF to_regprocedure('public.calcular_nivel_gro_risco()') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Funcao calcular_nivel_gro_risco nao existe nesta base.';
    RETURN r;
  END IF;

  v_def := pg_get_functiondef('public.calcular_nivel_gro_risco()'::regprocedure);

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir guarda que preserva o nivel enviado p/ psicossocial';
  r.esperado    := 'Guarda subtipo=psicossocial AND nivel_risco IS NOT NULL; calculo padrao mantido p/ os demais';

  v_tem_guarda  := position('''psicossocial''' in v_def) > 0
               AND position('nivel_risco IS NOT NULL' in v_def) > 0;
  v_tem_calculo := position('critico' in v_def) > 0
               AND position('ELSE ' in v_def) > 0;

  IF v_tem_guarda AND v_tem_calculo THEN
    r.situacao := 'passou';
    r.obtido   := 'Trigger preserva o nivel psicossocial enviado e mantem o calculo padrao para fisico/ergonomico.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Guarda psicossocial presente=%s; calculo padrao presente=%s.', v_tem_guarda, v_tem_calculo);
    r.erro_tecnico := 'Sem a guarda, o trigger sobrescreve o nivel psicossocial (matriz unica) pela matriz de 4 niveis.';
  END IF;

  RETURN r;
END;
$$;

-- 5) Liga o caso a rotina
INSERT INTO public.qa_implementacoes (codigo, funcao_sql)
VALUES ('PSICO-API-002', 'qa_caso_psico_api_002')
ON CONFLICT (codigo) DO UPDATE
  SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- 6) CONFERENCIA FINAL (o SQL Editor so mostra o ultimo resultado)
SELECT r.situacao, r.obtido, r.erro_tecnico
FROM public.qa_caso_psico_api_002() r;
