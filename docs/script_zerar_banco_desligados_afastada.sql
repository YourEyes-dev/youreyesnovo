-- ============================================================================
-- CORRETIVO — Encerrar banco de Cacilda/Mila (desligadas) e Fabieli (afastada)
-- Zera de 2026-08 em diante. Cole INTEIRO no SQL Editor de PRODUÇÃO.
--
-- POR QUE UM SCRIPT SEPARADO: essas colaboradoras não têm mais apuração diária
-- (ponto_diario), então apurar_banco_horas_colaborador retorna cedo e NÃO
-- reajusta a fotografia nem propaga o zero. Aqui a cadeia é ajustada
-- diretamente: no primeiro mês lança-se um movimento de ABSORÇÃO que zera o
-- saldo devedor herdado; nos meses seguintes o saldo abre em 0. O saldo continua
-- sendo a soma dos movimentos + o saldo anterior (não é escrita arbitrária).
--
-- Os débitos que sobraram vieram da apuração ter rodado em dias sem trabalho
-- (Cacilda apurada ate 31/07 desligada 02/07; Mila ate 30/06 desligada 09/06;
-- Fabieli afastada, debito de 06/2026) — a causa de fundo é a apuração debitar
-- dia de quem nao trabalhou; este script só limpa o efeito nessas três.
--
-- NÃO cria função (sem auto-RLS). Backup por EXECUTE. Idempotente.
-- ============================================================================

DO $z$
DECLARE
  v_inicio text := '2026-08';
  v_cpfs text[] := ARRAY['03343755923','14023338974','07444157995']::text[];  -- Cacilda, Mila, Fabieli
  rec RECORD;
  v_prev_cpf text := NULL;
  v_prev_saldo int := 0;
  v_anterior int;
  v_net int;
  v_cur int;
  v_cred int; v_deb int; v_comp int;
  v_fimmes date;
BEGIN
  -- BACKUP das linhas que serão reescritas.
  IF to_regclass('public.backup_encerra_deslig_afast_20260929') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_encerra_deslig_afast_20260929 '
         || '(LIKE public.ponto_banco_horas INCLUDING DEFAULTS)';
    INSERT INTO public.backup_encerra_deslig_afast_20260929
      SELECT * FROM public.ponto_banco_horas
      WHERE competencia >= v_inicio
        AND regexp_replace(COALESCE(colaborador_cpf,''), '[^0-9]', '', 'g') IN (
              SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x);
    RAISE NOTICE 'Backup criado em backup_encerra_deslig_afast_20260929.';
  ELSE
    RAISE NOTICE 'Backup ja existe — mantido.';
  END IF;

  FOR rec IN
    SELECT b.id, b.tenant_id, b.colaborador_cpf, b.colaborador_nome, b.competencia,
           b.saldo_anterior_minutos,
           regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') AS cpfn
    FROM public.ponto_banco_horas b
    WHERE b.competencia >= v_inicio
      AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
            SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(v_cpfs) AS x)
    ORDER BY cpfn, b.competencia
  LOOP
    v_fimmes := (to_date(rec.competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;

    IF v_prev_cpf IS DISTINCT FROM rec.cpfn THEN
      -- Primeiro mês deste colaborador: mantém o saldo anterior herdado e, se o
      -- saldo do mês não for zero, lança a absorção que o zera.
      v_anterior := COALESCE(rec.saldo_anterior_minutos, 0);
      -- COALESCE em CADA soma (a ausência de um tipo tornaria o total NULL).
      v_net := COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'credito'), 0)
             - COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'debito'), 0)
             - COALESCE((SELECT SUM(minutos) FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id AND tipo = 'compensacao'), 0);
      v_cur := v_anterior + v_net;
      IF v_cur < 0 AND NOT EXISTS (
           SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
           WHERE m.banco_horas_id = rec.id AND m.origem = 'liquidacao_absorcao') THEN
        INSERT INTO public.ponto_banco_horas_movimentacoes (
          tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem
        ) VALUES (
          rec.tenant_id, rec.id, rec.colaborador_cpf, v_fimmes, 'credito', -v_cur,
          'Encerramento por desligamento/afastamento - absorcao de saldo devedor', 'liquidacao_absorcao');
        RAISE NOTICE 'Absorvido: % % (% min)', rec.colaborador_nome, rec.competencia, v_cur;
      ELSIF v_cur > 0 THEN
        RAISE NOTICE 'CREDOR nao tocado (rever manualmente): % % (+% min)', rec.colaborador_nome, rec.competencia, v_cur;
      END IF;
    ELSE
      -- Meses seguintes: abrem no saldo final do mês anterior (0).
      v_anterior := v_prev_saldo;
    END IF;

    -- Recalcula a fotografia a partir dos movimentos (mesma fórmula da apuração).
    v_cred := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo = 'credito')
                        FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id), 0);
    v_deb  := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo = 'debito')
                        FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id), 0);
    v_comp := COALESCE((SELECT SUM(minutos) FILTER (WHERE tipo = 'compensacao')
                        FROM public.ponto_banco_horas_movimentacoes WHERE banco_horas_id = rec.id), 0);

    UPDATE public.ponto_banco_horas
    SET saldo_anterior_minutos = v_anterior,
        creditos_minutos = v_cred,
        debitos_minutos = v_deb,
        compensados_minutos = v_comp,
        saldo_atual_minutos = v_anterior + v_cred - v_deb - v_comp,
        updated_at = now()
    WHERE id = rec.id;

    v_prev_cpf := rec.cpfn;
    v_prev_saldo := v_anterior + v_cred - v_deb - v_comp;
  END LOOP;

  RAISE NOTICE 'Encerramento concluido.';
END;
$z$;

-- CONFERÊNCIA: fotografia x oficial das três, de 2026-08 em diante (esperado 0/0).
SELECT b.competencia, b.colaborador_nome,
       b.saldo_atual_minutos AS saldo_foto,
       o.saldo_atual_min     AS saldo_oficial
FROM public.ponto_banco_horas b
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE b.competencia >= '2026-08'
  AND regexp_replace(COALESCE(b.colaborador_cpf,''), '[^0-9]', '', 'g') IN (
        '03343755923','14023338974','07444157995')
ORDER BY b.colaborador_nome, b.competencia;
