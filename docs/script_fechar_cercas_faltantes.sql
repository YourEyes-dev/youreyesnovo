-- ============================================================================
-- ENTREGA — Fechar as cercas do cercado que faltam (reconciliação)
--
-- Cole no SQL Editor da HOMOLOGAÇÃO primeiro; depois de conferido, na PRODUÇÃO.
-- Mesmo script nos dois (forward-only).
--
-- POR QUÊ: o caso PONTO-270 acusou, na produção, tabelas de ponto com coluna
-- tenant_id SEM a trava do cercado (qa_guarda_cercado) — ex.:
-- ponto_equalizacao_mensal, ponto_escala_copia_tenant, ponto_excedente_decisao,
-- ponto_retencao_config, ponto_saldo_fix_intervalo_snapshot. No teste isso já
-- está fechado (a migration de 24/09 rodou o instalador depois dessas tabelas
-- nascerem); a produção, forward-only, não recebeu esse passo. Sem a trava,
-- uma rotina de teste com erro de tenant escreveria em dado REAL por esse
-- caminho — por isso é imprudente rodar a bateria completa aqui antes de fechar.
--
-- O QUE FAZ: instala qa_guarda_cercado em TODA tabela de public com tenant_id
-- que ainda não a tenha, EXCETO as duas multi-tenant por desenho
-- (marketplace_demanda_latente, parceiro_mrr_snapshots — revertidas de propósito
-- em script anterior). A trava é NO-OP fora do modo de teste (só age com
-- app.qa_modo = 'on'), então não muda nada na operação normal.
--
-- SEGURANÇA: cada tabela é tratada num bloco próprio com EXCEPTION — se uma
-- estiver ocupada e o lock não vier em 10s (ou houver deadlock), ELA é pulada
-- e reportada, sem abortar as demais. Não cria tabela (sem auto-RLS do editor),
-- não apaga dado. Idempotente (rodar de novo só cobre o que faltou). Se sobrar
-- alguma pulada por lock, rode de novo numa janela mais calma.
-- ============================================================================

SET lock_timeout = '10s';

DO $fechar$
DECLARE
  c record;
  v_novas int := 0;
  v_falhou text := '';
  v_excecoes CONSTANT text[] := ARRAY['marketplace_demanda_latente', 'parceiro_mrr_snapshots'];
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
    RAISE NOTICE 'Cercado ausente nesta base (qa_bloqueia_fora_do_cercado não existe) — nada a fazer.';
    RETURN;
  END IF;

  FOR c IN
    SELECT col.table_name AS t
    FROM information_schema.columns col
    JOIN information_schema.tables tb
      ON tb.table_schema = col.table_schema AND tb.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND tb.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
      AND col.table_name <> ALL (v_excecoes)
      AND NOT EXISTS (
        SELECT 1 FROM pg_trigger tg
        WHERE tg.tgname = 'qa_guarda_cercado'
          AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
          AND NOT tg.tgisinternal)
    ORDER BY col.table_name
  LOOP
    BEGIN
      EXECUTE format(
        'CREATE TRIGGER qa_guarda_cercado
           BEFORE INSERT OR UPDATE OR DELETE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()',
        c.t);

      IF to_regclass('public.qa_tabelas_protegidas') IS NOT NULL THEN
        INSERT INTO public.qa_tabelas_protegidas AS p (tabela, motivo)
        SELECT c.t, 'Cerca generica: tabela tem tenant_id'
        WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x WHERE x.tabela = c.t);
      END IF;

      v_novas := v_novas + 1;
      RAISE NOTICE 'Cerca instalada em public.%', c.t;
    EXCEPTION WHEN OTHERS THEN
      v_falhou := v_falhou || ' ' || c.t || ' (' || left(SQLERRM, 60) || ')';
    END;
  END LOOP;

  RAISE NOTICE 'Cercas novas: %.', v_novas;
  IF v_falhou <> '' THEN
    RAISE NOTICE 'Puladas por lock/erro (rode de novo numa janela calma):%', v_falhou;
  END IF;
END $fechar$;

-- Conferência (única): tem de voltar VAZIO — nenhuma tabela com tenant_id sem
-- a trava, fora as duas exceções por desenho.
SELECT col.table_name AS ainda_sem_cerca
FROM information_schema.columns col
JOIN information_schema.tables tb
  ON tb.table_schema = col.table_schema AND tb.table_name = col.table_name
WHERE col.table_schema = 'public'
  AND col.column_name  = 'tenant_id'
  AND tb.table_type     = 'BASE TABLE'
  AND col.table_name NOT LIKE 'qa\_%'
  AND col.table_name NOT IN ('marketplace_demanda_latente', 'parceiro_mrr_snapshots')
  AND NOT EXISTS (
    SELECT 1 FROM pg_trigger tg
    WHERE tg.tgname = 'qa_guarda_cercado'
      AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
      AND NOT tg.tgisinternal)
ORDER BY 1;
