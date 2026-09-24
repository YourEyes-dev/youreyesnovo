-- ============================================================================
-- ENTREGA — reverter ponto ao excluir atestado (funcao de gatilho + trigger)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   No teste (fonte da verdade), excluir um atestado REVERTE o ponto que ele
--   havia abonado: para cada dia do periodo do atestado, se houve batida real
--   o dia e reconsolidado (o motor redecide o status), e se nao houve batida a
--   linha 'justificado' que so existia por causa do atestado e removida (apenas
--   as marcadas como 'Atestado médico', para nao apagar ferias/folga/etc.).
--   Na producao faltam AS DUAS pecas: a funcao de gatilho E o trigger que a
--   dispara. Este script cria as duas.
--
--   Pecas:
--     1. funcao public.reverter_ponto_por_atestado_excluido() — envelopada em
--        DO/EXECUTE (ela tem SELECT ... INTO, que o SQL Editor confunde com
--        criacao de tabela);
--     2. trigger trigger_reverter_ponto_atestado AFTER DELETE em atestados —
--        DDL pura, idempotente (DROP IF EXISTS antes do CREATE).
--
-- SEGURANCA: cria funcao + trigger; nao altera nem apaga dado existente.
--   lock_timeout protege a criacao do trigger na tabela atestados. E UM trigger
--   em UMA tabela, entao a regra de deadlock (dois triggers em duas tabelas
--   movimentadas) nao se aplica. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── BLOCO 1: a funcao de gatilho ────────────────────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.reverter_ponto_por_atestado_excluido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_data_inicio date;
  v_data_fim    date;
  v_dia         date;
  v_tem_batida  boolean;
BEGIN
  -- Só atestados que afetaram o ponto têm data de afastamento.
  IF OLD.data_inicio_afastamento IS NULL THEN
    RETURN OLD;
  END IF;

  v_data_inicio := OLD.data_inicio_afastamento::date;
  v_data_fim    := COALESCE(
    OLD.data_fim_afastamento::date,
    v_data_inicio + COALESCE(OLD.dias_afastamento, 1) - 1
  );

  v_dia := v_data_inicio;
  WHILE v_dia <= v_data_fim LOOP
    -- Havia marcação real de ponto nesse dia?
    SELECT EXISTS (
      SELECT 1 FROM public.ponto_marcacoes
      WHERE tenant_id = OLD.tenant_id
        AND colaborador_cpf = OLD.colaborador_cpf
        AND data_marcacao = v_dia
    ) INTO v_tem_batida;

    IF v_tem_batida THEN
      -- Deixa o motor de cálculo redecidir o status a partir das batidas.
      PERFORM public.consolidar_ponto_diario_manual(
        OLD.tenant_id, OLD.colaborador_cpf, v_dia
      );
    ELSE
      -- Sem batida, o registro 'justificado' só existia por causa do
      -- atestado. Remove — mas apenas se a marca for de atestado, para não
      -- apagar justificativa de outra origem (férias, folga, etc.).
      DELETE FROM public.ponto_diario
      WHERE tenant_id = OLD.tenant_id
        AND colaborador_cpf = OLD.colaborador_cpf
        AND data = v_dia
        AND status = 'justificado'
        AND observacao ILIKE '%Atestado médico%';
    END IF;

    v_dia := v_dia + 1;
  END LOOP;

  RETURN OLD;
END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 2: o trigger (idempotente) ────────────────────────────────────────
DROP TRIGGER IF EXISTS trigger_reverter_ponto_atestado ON public.atestados;
CREATE TRIGGER trigger_reverter_ponto_atestado
  AFTER DELETE ON public.atestados
  FOR EACH ROW EXECUTE FUNCTION public.reverter_ponto_por_atestado_excluido();

-- ── CONFERENCIA — RODE SEPARADO (numa consulta nova). Esperado: 1 linha ─────
-- md5 de referencia da funcao (CSV inicial; se o teste foi editado, compare
-- com o md5 atual do teste): d75c4830a253c73da2f25a551f45f20d
--   SELECT
--     md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) AS md5_funcao,
--     (SELECT count(*) FROM pg_trigger t
--       WHERE t.tgname = 'trigger_reverter_ponto_atestado'
--         AND t.tgrelid = 'public.atestados'::regclass
--         AND NOT t.tgisinternal) AS trigger_existe
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   WHERE p.proname = 'reverter_ponto_por_atestado_excluido';
