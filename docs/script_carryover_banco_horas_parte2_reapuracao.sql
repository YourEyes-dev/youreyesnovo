-- ============================================================================
-- ENTREGA — Banco de horas: carry-over — PARTE 2 (BACKUP + REAPURAÇÃO)
-- Itens 1/3/5 do pacote de correções do Ponto
--
-- Rode a PARTE 1 (função) ANTES desta. Depois cole este arquivo INTEIRO no SQL
-- Editor de PRODUÇÃO e rode. Roda em uma única transação (se falhar, desfaz).
--
-- O QUE FAZ:
--   1) BACKUP das linhas de ponto_banco_horas que serão reescritas (produção
--      não tem PITR). A tabela de backup é criada por EXECUTE (string montada)
--      de propósito, para o SQL Editor não detectar a criação de tabela e não
--      ligar o auto-RLS. Aqui não há função definida, então nada é corrompido.
--   2) REAPURA, em ordem cronológica por colaborador, as competências ABERTAS a
--      partir de v_inicio (fechadas não são tocadas — Súmula 338), usando a
--      função corrigida da parte 1.
--   3) CONFERÊNCIA: lista as descontinuidades que ainda restarem (idealmente
--      nenhuma — "No rows returned").
--
-- AJUSTE ANTES DE RODAR: v_inicio abaixo é o primeiro mês a reapurar (padrão
-- 2026-08). O mês anterior a v_inicio precisa estar correto — é a âncora.
-- Idempotente: rodar de novo reconfirma os mesmos números.
-- ============================================================================

-- 1) BACKUP -----------------------------------------------------------------
DO $bkp$
BEGIN
  IF to_regclass('public.backup_ponto_banco_horas_20260929') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_ponto_banco_horas_20260929 AS '
         || 'SELECT * FROM public.ponto_banco_horas WHERE competencia >= ''2026-08''';
    RAISE NOTICE 'Backup criado em backup_ponto_banco_horas_20260929.';
  ELSE
    RAISE NOTICE 'Backup ja existe (backup_ponto_banco_horas_20260929) — mantido.';
  END IF;
END;
$bkp$;

-- 2) REAPURACAO em ordem cronologica, so competencias ABERTAS ---------------
DO $reap$
DECLARE
  v_inicio text := '2026-08';   -- primeiro mes a reapurar (ajuste se necessario)
  rec RECORD;
  v_n int := 0;
BEGIN
  FOR rec IN
    SELECT b.tenant_id, b.colaborador_cpf, b.competencia, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.competencia >= v_inicio
      AND NOT EXISTS (
        SELECT 1 FROM public.ponto_fechamentos f
        WHERE f.tenant_id = b.tenant_id
          AND f.competencia = b.competencia
          AND f.status = 'fechado'
          AND (f.empresa_id IS NULL OR f.empresa_id = b.empresa_id)
      )
    ORDER BY b.tenant_id, b.colaborador_cpf, b.competencia
  LOOP
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(
        rec.tenant_id, rec.colaborador_cpf, rec.competencia, rec.empresa_id);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Falha ao reapurar %/%/%: %',
        rec.tenant_id, rec.colaborador_cpf, rec.competencia, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'Reapuracao concluida: % competencia(s) reapurada(s).', v_n;
END;
$reap$;

-- 3) CONFERENCIA: descontinuidades restantes (idealmente "No rows returned")
-- Para cada colaborador, o saldo_atual de um mes deve bater com o
-- saldo_anterior do mes seguinte. Meses pulados ou fechados no meio podem
-- aparecer e sao esperados.
WITH x AS (
  SELECT tenant_id, colaborador_cpf, competencia,
         saldo_anterior_minutos,
         saldo_atual_minutos,
         LAG(saldo_atual_minutos) OVER (
           PARTITION BY tenant_id, colaborador_cpf ORDER BY competencia) AS fim_mes_anterior,
         LAG(competencia) OVER (
           PARTITION BY tenant_id, colaborador_cpf ORDER BY competencia) AS competencia_anterior
  FROM public.ponto_banco_horas
  WHERE competencia >= '2026-08'
)
SELECT colaborador_cpf, competencia_anterior, competencia,
       fim_mes_anterior AS fim_do_mes_anterior,
       saldo_anterior_minutos AS abertura_deste_mes,
       (fim_mes_anterior - saldo_anterior_minutos) AS diferenca
FROM x
WHERE fim_mes_anterior IS NOT NULL
  AND fim_mes_anterior <> saldo_anterior_minutos
ORDER BY colaborador_cpf, competencia;

-- ============================================================================
-- PARA DESFAZER (se necessario), restaurar do backup:
--   UPDATE public.ponto_banco_horas b
--      SET saldo_anterior_minutos = k.saldo_anterior_minutos,
--          creditos_minutos       = k.creditos_minutos,
--          debitos_minutos        = k.debitos_minutos,
--          compensados_minutos    = k.compensados_minutos,
--          saldo_atual_minutos    = k.saldo_atual_minutos,
--          prazo_compensacao      = k.prazo_compensacao
--     FROM public.backup_ponto_banco_horas_20260929 k
--    WHERE b.id = k.id;
-- ============================================================================
