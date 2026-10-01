-- ============================================================================
-- ACERTO DO BANCO — BARROS · GRUPO A: mover zeragem de AGOSTO para JULHO
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- CONTEXTO: o fechamento semestral do Grupo A da Barros foi lançado por engano
-- em AGOSTO (liquidações "Fechamento de banco 08/2026 - ...", criadas em 30/09).
-- Isso zerou o ACUMULADO de agosto (saldo do semestre + trabalho de agosto),
-- fazendo setembro começar zerado. O certo: zerar em JULHO (só o saldo do
-- semestre) e deixar agosto carregar o trabalho real (decisão confirmada pelo
-- dono do produto em 01/10: "agosto carrega o real", inclusive negativos).
--
-- O QUE FAZ (apenas Grupo A = quem tem a liquidação de agosto):
--   1) Lança em JULHO a liquidação que zera o saldo do semestre:
--        - saldo positivo  -> COMPENSAÇÃO (origem liquidacao_compensacao)
--        - saldo negativo   -> CRÉDITO/absorção (origem liquidacao_absorcao)
--      e grava saldo_atual de julho = 0.
--   2) REMOVE as liquidações de AGOSTO ("Fechamento de banco 08/2026%").
--   Junho e julho continuam FECHADOS; o migrado (ancorado em junho) fica intacto.
--   Não encosta no Grupo B (Tania, Kailaine, Natieli) nem na liquidação de
--   julho da Cacilda (desligamento) — o filtro é só a de agosto do fechamento.
--
-- VALIDADO em réplica (01/10/2026) com casos positivo, negativo e Grupo B.
--
-- SEGURANÇA: roda em UMA transação (erro desfaz tudo). As linhas originais estão
--   no backup do Passo 0 (backup_acerto_banco_20261001 / backup_acerto_mov_20261001).
--   Idempotente: rodar de novo não duplica (julho já zerado e liquidações de
--   agosto já removidas -> nada a fazer).
--
-- DEPOIS DESTE SCRIPT (obrigatório): na tela, com a empresa Barros selecionada,
--   clicar "Apurar agora" em AGOSTO, depois SETEMBRO, depois OUTUBRO (NUNCA
--   junho/julho). Só então rodar a conferência oficial.
-- ============================================================================

DO $acerto$
DECLARE
  v_cpf text; v_jul_id uuid; v_tenant uuid; v_saldo int;
  v_min int; v_tipo text; v_origem text;
  v_n_zerados int := 0; v_n_removidas int := 0;
BEGIN
  -- Grupo A = colaboradores com a liquidação de agosto do fechamento 08/2026.
  FOR v_cpf IN
    SELECT DISTINCT bh.colaborador_cpf
    FROM public.ponto_banco_horas_movimentacoes mv
    JOIN public.ponto_banco_horas bh ON bh.id = mv.banco_horas_id
    JOIN public.empresa_cadastro   ec ON ec.id = bh.empresa_id
    WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
      AND bh.competencia = '2026-08'
      AND mv.descricao LIKE 'Fechamento de banco 08/2026%'
  LOOP
    SELECT bh.id, bh.tenant_id, bh.saldo_atual_minutos
      INTO v_jul_id, v_tenant, v_saldo
    FROM public.ponto_banco_horas bh
    JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
    WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
      AND bh.competencia = '2026-07' AND bh.colaborador_cpf = v_cpf
    LIMIT 1;

    IF v_jul_id IS NULL THEN
      RAISE NOTICE 'cpf %: sem banco de julho — pulado', v_cpf; CONTINUE; END IF;
    IF COALESCE(v_saldo,0) = 0 THEN
      RAISE NOTICE 'cpf %: julho ja zerado — pulado', v_cpf; CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM public.ponto_banco_horas_movimentacoes
               WHERE banco_horas_id = v_jul_id
                 AND descricao LIKE 'Fechamento semestral jul/2026 - liquidacao (Grupo A) [acerto]%') THEN
      RAISE NOTICE 'cpf %: ja tem a liquidacao do acerto em julho — pulado', v_cpf; CONTINUE; END IF;

    v_min := abs(v_saldo);
    IF v_saldo > 0 THEN v_tipo := 'compensacao'; v_origem := 'liquidacao_compensacao';
    ELSE                v_tipo := 'credito';     v_origem := 'liquidacao_absorcao'; END IF;

    INSERT INTO public.ponto_banco_horas_movimentacoes
      (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
    VALUES (v_tenant, v_jul_id, v_cpf, DATE '2026-07-31', v_tipo, v_min,
      'Fechamento semestral jul/2026 - liquidacao (Grupo A) [acerto]', v_origem);

    UPDATE public.ponto_banco_horas
    SET compensados_minutos = compensados_minutos + CASE WHEN v_tipo='compensacao' THEN v_min ELSE 0 END,
        creditos_minutos    = creditos_minutos    + CASE WHEN v_tipo='credito'     THEN v_min ELSE 0 END,
        saldo_atual_minutos = 0, updated_at = now()
    WHERE id = v_jul_id;

    v_n_zerados := v_n_zerados + 1;
    RAISE NOTICE 'cpf %: julho zerado (% % min)', v_cpf, v_tipo, v_min;
  END LOOP;

  WITH del AS (
    DELETE FROM public.ponto_banco_horas_movimentacoes mv
    USING public.ponto_banco_horas bh, public.empresa_cadastro ec
    WHERE mv.banco_horas_id = bh.id AND ec.id = bh.empresa_id
      AND ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
      AND bh.competencia = '2026-08'
      AND mv.descricao LIKE 'Fechamento de banco 08/2026%'
    RETURNING 1
  ) SELECT count(*) INTO v_n_removidas FROM del;

  RAISE NOTICE 'TOTAL: julho zerado em % pessoa(s); % liquidacao(oes) de agosto removida(s).',
    v_n_zerados, v_n_removidas;
END $acerto$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA 1 (imediata) — julho do Grupo A deve vir 0h00.
-- Agosto ainda aparece defasado aqui (precisa de "Apurar agora" na tela).
-- ---------------------------------------------------------------------
SELECT
  bh.colaborador_nome,
  bh.competencia,
  (CASE WHEN bh.saldo_atual_minutos<0 THEN '-' ELSE '' END)
    || abs(bh.saldo_atual_minutos)/60 || 'h'
    || lpad((abs(bh.saldo_atual_minutos)%60)::text,2,'0') AS saldo_atual
FROM public.ponto_banco_horas bh
JOIN public.empresa_cadastro ec ON ec.id = bh.empresa_id
WHERE ec.razao_social ILIKE '%BARROS & NUERNBERG ENG%'
  AND bh.competencia IN ('2026-07','2026-08')
ORDER BY bh.colaborador_nome, bh.competencia;
