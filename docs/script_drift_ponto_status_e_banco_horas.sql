-- ============================================================================
-- DRIFT TECNICO — Ponto: alinhar a trava de status do ponto_diario + entregar
-- a funcao converter_banco_horas_vencido. Entrega para a producao.
--
-- Sao dois gaps de ENTREGA (existem no dev/staging, nunca chegaram a producao),
-- nao achados de produto. Fecham 11 rotinas de Ponto (10 da trava + PONTO-354).
--
-- (1) ponto_diario_status_check: a producao tem lista mais curta que o dev. So
--     alinha se NENHUMA linha existente estiver fora da lista alvo (falha
--     segura: se houver status inesperado, NAO altera e avisa). Widening: nao
--     invalida linha existente. lock_timeout curto; aplicar com ambiente calmo.
-- (2) converter_banco_horas_vencido: funcao SECURITY DEFINER que so mexe em
--     ponto_banco_horas / _movimentacoes. Aditivo (CREATE OR REPLACE).
-- Idempotente. Conferencia no fim roda as 11 rotinas afetadas.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Alinhar a trava de status (guardada: nao altera se houver status fora) ──
DO $blk$
DECLARE v_fora int;
BEGIN
  SELECT count(*) INTO v_fora FROM public.ponto_diario
   WHERE status IS NOT NULL
     AND status <> ALL (ARRAY['pendente','regular','atraso','falta','incompleto','ajuste_pendente','justificado']);
  IF v_fora > 0 THEN
    RAISE NOTICE 'Trava de status NAO alterada: % linha(s) com status fora da lista alvo. Investigar antes.', v_fora;
    RETURN;
  END IF;
  ALTER TABLE public.ponto_diario DROP CONSTRAINT IF EXISTS ponto_diario_status_check;
  ALTER TABLE public.ponto_diario ADD CONSTRAINT ponto_diario_status_check
    CHECK (status = ANY (ARRAY['pendente','regular','atraso','falta','incompleto','ajuste_pendente','justificado']::text[]));
  RAISE NOTICE 'Trava de status alinhada com o dev (7 valores).';
END $blk$;

-- (2) Funcao do banco de horas ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.converter_banco_horas_vencido(p_tenant uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_banco RECORD;
BEGIN
  FOR v_banco IN
    SELECT * FROM public.ponto_banco_horas
    WHERE convertido_extras = FALSE
      AND prazo_compensacao IS NOT NULL
      AND prazo_compensacao < CURRENT_DATE
      AND saldo_atual_minutos > 0
      -- Sem argumento, o comportamento e o de sempre: todos os tenants.
      -- Com argumento, so aquele — e a bancada de QA consegue exercitar a
      -- conversao dentro do cercado, sem tentar tocar dado de cliente.
      AND (p_tenant IS NULL OR tenant_id = p_tenant)
  LOOP
    -- Mark as converted
    UPDATE public.ponto_banco_horas
    SET convertido_extras = TRUE,
        data_conversao = CURRENT_DATE,
        observacoes = COALESCE(observacoes, '') || ' [Convertido automaticamente em HE em ' || CURRENT_DATE::TEXT || '. Saldo: ' || v_banco.saldo_atual_minutos || ' min]'
    WHERE id = v_banco.id;

    -- Register conversion movement
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao
    ) VALUES (
      v_banco.tenant_id, v_banco.id, v_banco.colaborador_cpf, CURRENT_DATE,
      'conversao_he', v_banco.saldo_atual_minutos,
      'Conversão automática: prazo de compensação vencido em ' || v_banco.prazo_compensacao::TEXT
    );
  END LOOP;
END;
$function$

;

-- Conferencia: as 11 rotinas de Ponto afetadas ──────────────────────────────
WITH alvo(codigo) AS (VALUES
  ('PONTO-131'),('PONTO-300'),('PONTO-301'),('PONTO-310'),('PONTO-311'),
  ('PONTO-320'),('PONTO-321'),('PONTO-322'),('PONTO-330'),('PONTO-394'),('PONTO-354'))
SELECT a.codigo, (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao
FROM alvo a JOIN public.qa_implementacoes i ON i.codigo=a.codigo
ORDER BY situacao, a.codigo;
