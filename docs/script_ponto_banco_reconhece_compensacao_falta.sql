-- ============================================================================
-- ENTREGA — Banco de horas reconhece o débito de COMPENSAÇÃO DE FALTA.
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- *** Só rodar DEPOIS de validar no ambiente de teste. ***
--
-- BUG: a ciência da compensação de falta grava a movimentação com
-- tipo='compensacao_falta', mas as funções que somam o saldo do banco só
-- conheciam credito/debito/compensacao — então o débito ficava INVISÍVEL
-- (saldo não mudava; reapuração ignorava). Ex.: Luciani (Barros), falta de
-- 21/08 compensada: a ciência não alterou o saldo.
--
-- CORREÇÃO: tratar 'compensacao_falta' como DÉBITO em:
--   * ponto_banco_horas_oficial       (fonte única — tela e conferência)
--   * apurar_banco_horas_colaborador  (apuração; grava debitos_minutos)
-- Sem risco de dobra: a apuração já não debita a falta no banco
-- ([falta-fora-do-banco]); o débito da compensação vira a ÚNICA cobrança.
--
-- SEGURANÇA: só substitui FUNÇÃO (não cria tabela, não altera dado).
-- Idempotente. Validado em réplica (patch + QA PONTO-485).
-- ============================================================================
DO $fix$
DECLARE
  v_oid oid;
  v_src text;
  v_alvo_of text := 'm.tipo = ''debito''  AND COALESCE(m.origem';
  v_novo_of text := 'm.tipo IN (''debito'', ''compensacao_falta'') AND COALESCE(m.origem';
  v_alvo_ap text := 'FILTER (WHERE tipo = ''debito'')';
  v_novo_ap text := 'FILTER (WHERE tipo IN (''debito'', ''compensacao_falta''))';
BEGIN
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_banco_horas_oficial' AND p.prokind='f'
  LOOP
    v_src := pg_get_functiondef(v_oid);
    IF position('IN (''debito'', ''compensacao_falta'') AND COALESCE(m.origem' IN v_src) > 0 THEN
      RAISE NOTICE '[oficial] ja reconhece compensacao_falta.';
    ELSIF position(v_alvo_of IN v_src) = 0 THEN
      RAISE NOTICE '[oficial] ancora nao encontrada — conferir manualmente.';
    ELSE
      EXECUTE replace(v_src, v_alvo_of, v_novo_of);
      RAISE NOTICE '[oficial] corrigida.';
    END IF;
  END LOOP;

  FOR v_oid IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='apurar_banco_horas_colaborador' AND p.prokind='f'
  LOOP
    v_src := pg_get_functiondef(v_oid);
    IF position('FILTER (WHERE tipo IN (''debito'', ''compensacao_falta''))' IN v_src) > 0 THEN
      RAISE NOTICE '[apurar] ja reconhece compensacao_falta.';
    ELSIF position(v_alvo_ap IN v_src) = 0 THEN
      RAISE NOTICE '[apurar] ancora nao encontrada — conferir manualmente.';
    ELSE
      EXECUTE replace(v_src, v_alvo_ap, v_novo_ap);
      RAISE NOTICE '[apurar] corrigida.';
    END IF;
  END LOOP;
END $fix$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA: as duas funções devem vir reconhece = true.
-- ---------------------------------------------------------------------
SELECT
  p.proname AS funcao,
  (position('IN (''debito'', ''compensacao_falta'')' IN pg_get_functiondef(p.oid)) > 0) AS reconhece_compensacao_falta
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND p.proname IN ('ponto_banco_horas_oficial','apurar_banco_horas_colaborador')
ORDER BY funcao;

-- Depois, para a Luciani ficar correta, reapure agosto dela pela tela
-- ("Apurar agora" em Agosto, empresa Barros) OU confira direto o oficial.
-- O saldo de agosto deve passar a descontar as 8h38 (de 1h59 para ~ -6h39).
