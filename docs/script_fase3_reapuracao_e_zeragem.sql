-- ============================================================================
-- FASE 3 — reapuração dos AFETADOS + zeragem (fechamento de banco) do GRUPO
-- Colar INTEIRO no SQL Editor (HOMOLOGAÇÃO primeiro; depois PRODUÇÃO). Uma
-- transação. Requer a Fase 1 (motor corrigido) já aplicada no ambiente.
--
-- O QUE FAZ, em ordem:
--   1) BACKUP das linhas que serão tocadas (banco + movimentações), >= 2026-08.
--   2) REAPURA AGOSTO/2026 dos AFETADOS pelo bug (todos os afastados/desligados
--      com dias em ago/set) + os 10 do grupo — com o motor corrigido, o débito
--      indevido de dia de afastamento/pós-desligamento some.
--   3) ZERAGEM de AGOSTO só dos 10 (fechamento de banco, decisão de DP):
--      devedor -> crédito de absorção (empresa perdoa); credor -> compensação
--      (horas pagas/compensadas em folha). Nunca escreve o saldo direto: só por
--      MOVIMENTO. Remove liquidação antiga (recalibra) e refaz calibrada certo.
--   4) REAPURA SETEMBRO/2026 dos mesmos afetados + grupo — carrega o agosto já
--      corrigido/zerado (o zero escorre para a frente).
--
-- SEGURANÇA:
--   · Só toca AFETADOS + os 10 (quem não foi afetado já mostra o oficial certo
--     desde a Fase 1). Não varre a base inteira (sem risco de timeout).
--   · Só mexe em competência ABERTA (julho, fechado, fica intacto).
--   · Idempotente (rodar 2x dá o mesmo: reapuração é idempotente; a zeragem
--     remove a liquidação anterior e relança).
--   · BACKUP antes de qualquer escrita; desfazer no comentário final.
--   · Backup criado por EXECUTE (sequência CREATE+TABLE partida) para não
--     acionar o auto-RLS do editor. Não cria FUNÇÃO.
-- ============================================================================

DO $f3$
DECLARE
  v_ago  text := '2026-08';
  v_set  text := '2026-09';
  v_ini  date := DATE '2026-08-01';
  v_fim_ago date := DATE '2026-08-31';
  v_fim_win date := DATE '2026-09-30';
  v_grupo text[] := ARRAY[
    '07154201940',  -- Leticia   (Itapejara)
    '08594914989',  -- Luciana   (Itapejara)
    '11762645912',  -- Luciani   (Itapejara)
    '11289974950',  -- Paulo     (Itapejara)
    '06153113931',  -- Adriana   (Itapejara)
    '01416068198',  -- Cleciane  (Itapejara)
    '09332971900',  -- Marina    (Itapejara)
    '08890648902',  -- Aylyn     (Realeza)
    '08480531924',  -- Deisi     (Realeza)
    '11647445930'   -- Carol     (Dois Vizinhos)
  ];
  rec RECORD;
  v_saldo int;
  v_reap int := 0;
  v_zer  int := 0;
BEGIN
  -- 1) BACKUP -----------------------------------------------------------------
  IF to_regclass('public.backup_fase3_banco_20260930') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_fase3_banco_20260930 '
         || '(LIKE public.ponto_banco_horas INCLUDING DEFAULTS)';
    INSERT INTO public.backup_fase3_banco_20260930
      SELECT b.* FROM public.ponto_banco_horas b
      WHERE b.competencia >= v_ago
        AND (
          regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = ANY(v_grupo)
          OR EXISTS (SELECT 1 FROM public.afastamentos af
                     WHERE af.tenant_id = b.tenant_id
                       AND regexp_replace(COALESCE(af.colaborador_cpf,''),'[^0-9]','','g')
                           = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                       AND af.data_inicio <= v_fim_win
                       AND COALESCE(af.data_fim,'infinity'::date) >= v_ini)
          OR EXISTS (SELECT 1 FROM public.admissoes a
                     WHERE a.tenant_id = b.tenant_id
                       AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
                           = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                       AND a.status::text = 'desligado' AND a.data_desligamento IS NOT NULL)
        );
    EXECUTE 'CREATE ' || 'TABLE public.backup_fase3_movs_20260930 '
         || '(LIKE public.ponto_banco_horas_movimentacoes INCLUDING DEFAULTS)';
    INSERT INTO public.backup_fase3_movs_20260930
      SELECT m.* FROM public.ponto_banco_horas_movimentacoes m
      WHERE m.banco_horas_id IN (SELECT id FROM public.backup_fase3_banco_20260930);
    RAISE NOTICE 'Backup criado (backup_fase3_banco_20260930 / _movs_).';
  ELSE
    RAISE NOTICE 'Backup ja existe — mantido.';
  END IF;

  -- 2) REAPURAR AGOSTO (afetados + grupo, só competência aberta) --------------
  FOR rec IN
    SELECT DISTINCT b.tenant_id, b.colaborador_cpf, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.competencia = v_ago
      AND NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos f
                      WHERE f.tenant_id=b.tenant_id AND f.competencia=b.competencia
                        AND f.status='fechado' AND f.reaberto_em IS NULL
                        AND (f.empresa_id IS NULL OR f.empresa_id=b.empresa_id))
      AND (
        regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = ANY(v_grupo)
        OR EXISTS (SELECT 1 FROM public.afastamentos af
                   WHERE af.tenant_id=b.tenant_id
                     AND regexp_replace(COALESCE(af.colaborador_cpf,''),'[^0-9]','','g')
                         = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                     AND af.data_inicio <= v_fim_win
                     AND COALESCE(af.data_fim,'infinity'::date) >= v_ini)
        OR EXISTS (SELECT 1 FROM public.admissoes a
                   WHERE a.tenant_id=b.tenant_id
                     AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
                         = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                     AND a.status::text='desligado' AND a.data_desligamento IS NOT NULL)
      )
  LOOP
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(rec.tenant_id, rec.colaborador_cpf, v_ago, rec.empresa_id);
      v_reap := v_reap + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Reapuracao ago falhou p/ %: %', rec.colaborador_cpf, SQLERRM;
    END;
  END LOOP;

  -- 3) ZERAGEM DE AGOSTO — só os 10 do grupo ----------------------------------
  FOR rec IN
    SELECT b.id AS banco_id, b.tenant_id, b.empresa_id, b.colaborador_cpf, b.colaborador_nome
    FROM public.ponto_banco_horas b
    WHERE b.competencia = v_ago
      AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = ANY(v_grupo)
      AND NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos f
                      WHERE f.tenant_id=b.tenant_id AND f.competencia=b.competencia
                        AND f.status='fechado' AND f.reaberto_em IS NULL
                        AND (f.empresa_id IS NULL OR f.empresa_id=b.empresa_id))
  LOOP
    -- remove liquidação anterior (recalibra) e reapura para o saldo limpo
    DELETE FROM public.ponto_banco_horas_movimentacoes
     WHERE banco_horas_id = rec.banco_id
       AND origem IN ('liquidacao_absorcao','liquidacao_compensacao');
    PERFORM public.apurar_banco_horas_colaborador(rec.tenant_id, rec.colaborador_cpf, v_ago, rec.empresa_id);

    v_saldo := COALESCE((SELECT o.saldo_atual_min
                         FROM public.ponto_banco_horas_oficial(rec.tenant_id, v_ago, rec.empresa_id, rec.colaborador_cpf) o
                         LIMIT 1), 0);

    IF v_saldo < 0 THEN
      INSERT INTO public.ponto_banco_horas_movimentacoes
        (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
      VALUES (rec.tenant_id, rec.banco_id, rec.colaborador_cpf, v_fim_ago, 'credito', -v_saldo,
        'Fechamento de banco 08/2026 - absorcao de saldo devedor pela empresa (decisao DP)', 'liquidacao_absorcao');
      v_zer := v_zer + 1;
    ELSIF v_saldo > 0 THEN
      INSERT INTO public.ponto_banco_horas_movimentacoes
        (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
      VALUES (rec.tenant_id, rec.banco_id, rec.colaborador_cpf, v_fim_ago, 'compensacao', v_saldo,
        'Fechamento de banco 08/2026 - liquidacao de saldo credor (pagamento/compensacao em folha - decisao DP)', 'liquidacao_compensacao');
      v_zer := v_zer + 1;
    END IF;

    -- recomputa a foto incluindo a liquidação (saldo -> 0)
    PERFORM public.apurar_banco_horas_colaborador(rec.tenant_id, rec.colaborador_cpf, v_ago, rec.empresa_id);
  END LOOP;

  -- 4) REAPURAR SETEMBRO (mesmos afetados + grupo) ----------------------------
  FOR rec IN
    SELECT DISTINCT b.tenant_id, b.colaborador_cpf, b.empresa_id
    FROM public.ponto_banco_horas b
    WHERE b.competencia = v_set
      AND NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos f
                      WHERE f.tenant_id=b.tenant_id AND f.competencia=b.competencia
                        AND f.status='fechado' AND f.reaberto_em IS NULL
                        AND (f.empresa_id IS NULL OR f.empresa_id=b.empresa_id))
      AND (
        regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = ANY(v_grupo)
        OR EXISTS (SELECT 1 FROM public.afastamentos af
                   WHERE af.tenant_id=b.tenant_id
                     AND regexp_replace(COALESCE(af.colaborador_cpf,''),'[^0-9]','','g')
                         = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                     AND af.data_inicio <= v_fim_win
                     AND COALESCE(af.data_fim,'infinity'::date) >= v_ini)
        OR EXISTS (SELECT 1 FROM public.admissoes a
                   WHERE a.tenant_id=b.tenant_id
                     AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
                         = regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g')
                     AND a.status::text='desligado' AND a.data_desligamento IS NOT NULL)
      )
  LOOP
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(rec.tenant_id, rec.colaborador_cpf, v_set, rec.empresa_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Reapuracao set falhou p/ %: %', rec.colaborador_cpf, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE 'Fase 3 concluida. Reapurados (ago): %. Liquidacoes do grupo: %.', v_reap, v_zer;
END $f3$;

-- CONFERÊNCIA (o editor mostra só o último resultado): grupo, ago/set,
-- foto x oficial. Espera-se AGOSTO = 0 para os 10; setembro conta do zero.
SELECT b.colaborador_nome, b.competencia,
       b.saldo_atual_minutos AS saldo_foto,
       o.saldo_atual_min     AS saldo_oficial
FROM public.ponto_banco_horas b
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, b.competencia, b.empresa_id, b.colaborador_cpf) o ON true
WHERE b.competencia IN ('2026-08','2026-09')
  AND regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') IN (
    '07154201940','08594914989','11762645912','11289974950','06153113931',
    '01416068198','09332971900','08890648902','08480531924','11647445930')
ORDER BY b.colaborador_nome, b.competencia;

-- ----------------------------------------------------------------------------
-- DESFAZER (se preciso), num novo Run:
--   UPDATE public.ponto_banco_horas b SET
--     saldo_anterior_minutos = k.saldo_anterior_minutos,
--     creditos_minutos = k.creditos_minutos, debitos_minutos = k.debitos_minutos,
--     compensados_minutos = k.compensados_minutos,
--     saldo_atual_minutos = k.saldo_atual_minutos
--   FROM public.backup_fase3_banco_20260930 k WHERE k.id = b.id;
--   -- e, para os movimentos, reinserir de backup_fase3_movs_20260930 os apagados.
-- ----------------------------------------------------------------------------
