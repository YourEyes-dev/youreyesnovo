-- ============================================================================
-- ENTREGA — Afastamentos (Fase 4): efeitos, prazos e travas — PARTE 2 de 2
--
-- Rode DEPOIS da Parte 1 (docs/script_afastamentos_efeitos_parte1.sql), e so
-- depois de conferir a Parte 1 (2 | 1 | 5 | 1 | OK). Esta parte fica sozinha de
-- proposito: cria o trigger na tabela movimentada `afastamentos`, separado do
-- trigger da Parte 1 (em afastamentos_pendencias) — a regra da casa proibe criar
-- trigger em duas tabelas movimentadas na MESMA transacao (deadlock ja ocorrido).
--
-- O QUE ENTREGA A PARTE 2 (AFAST-070):
--   * coluna afastamentos.encerramento_justificativa (ADD COLUMN aditivo);
--   * funcao afastamento_bloqueia_encerramento_sem_aso (depende da coluna acima);
--   * trigger trg_afastamento_bloqueia_encerramento_sem_aso em afastamentos:
--     barra encerrar afastamento com ASO de retorno pendente (NR-7), a nao ser
--     que haja justificativa (alta administrativa).
--
-- SEGURANCA: aditivo. ADD COLUMN IF NOT EXISTS nao mexe em linha existente; a
-- funcao e o trigger sao novos (ausentes embaixo — conferido). Nao ALTERA nem
-- APAGA dado — sem backup. Roda em UMA transacao. DDL pura no topo; a funcao
-- (aspas-dolar) depois. O RAISE EXCEPTION esta DENTRO do trigger, de proposito
-- (e o que barra o encerramento invalido) — nao e statement solto do script.
--
-- CONFERENCIA: rode a query do fim SEPARADA. Esperado: 1 | 1 | 1 | OK
-- ============================================================================

SET lock_timeout = '10s';

-- AFAST-070: coluna de justificativa do encerramento (ADD COLUMN aditivo)
ALTER TABLE public.afastamentos
  ADD COLUMN IF NOT EXISTS encerramento_justificativa text;
COMMENT ON COLUMN public.afastamentos.encerramento_justificativa IS
  'AFAST-070: justificativa (alta administrativa) para encerrar com ASO de retorno pendente.';

-- Funcao do trigger (depois da DDL)
CREATE OR REPLACE FUNCTION public.afastamento_bloqueia_encerramento_sem_aso()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $fn$
BEGIN
  IF NEW.status::text = 'encerrado'
     AND COALESCE(OLD.status::text, '') <> 'encerrado'
     AND COALESCE(NEW.encerramento_justificativa, '') = ''
     AND EXISTS (
       SELECT 1 FROM public.afastamentos_pendencias p
        WHERE p.afastamento_id = NEW.id
          AND p.tipo_pendencia = 'aso_retorno'
          AND COALESCE(p.status, 'pendente') NOT IN ('resolvido', 'cancelado')
     ) THEN
    RAISE EXCEPTION
      'Retorno de afastamento com ASO de retorno pendente nao pode ser encerrado (NR-7). Registre o exame ou uma justificativa (alta administrativa).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$fn$;

-- Trigger em afastamentos (2a das duas tabelas movimentadas — por isso separado)
DROP TRIGGER IF EXISTS trg_afastamento_bloqueia_encerramento_sem_aso ON public.afastamentos;
CREATE TRIGGER trg_afastamento_bloqueia_encerramento_sem_aso
  BEFORE UPDATE OF status ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_bloqueia_encerramento_sem_aso();

-- ---------------------------------------------------------------------------
-- CONFERENCIA PARTE 2 — rode SEPARADA. Esperado: 1 | 1 | 1 | OK
--   col_encerramento | funcao | trigger | erro_tecnico
-- ---------------------------------------------------------------------------
WITH col AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema='public' AND table_name='afastamentos'
    AND column_name='encerramento_justificativa'
),
fn AS MATERIALIZED (
  SELECT (to_regprocedure('public.afastamento_bloqueia_encerramento_sem_aso()') IS NOT NULL)::int AS n
),
trg AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_trigger
  WHERE tgname='trg_afastamento_bloqueia_encerramento_sem_aso'
    AND tgrelid = to_regclass('public.afastamentos') AND NOT tgisinternal
)
SELECT
  (SELECT n FROM col) AS col_encerramento,
  (SELECT n FROM fn)  AS funcao,
  (SELECT n FROM trg) AS trigger_bloqueio,
  CASE WHEN (SELECT n FROM col)=1 AND (SELECT n FROM fn)=1 AND (SELECT n FROM trg)=1
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;
