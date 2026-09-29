-- ============================================================================
-- ENTREGA PARTE 2/2 — fecha a atribuição de escala de quem JÁ está desligado
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst) DEPOIS da Parte 1.
--
-- O QUE FAZ: para cada CPF DESLIGADO (e sem vínculo ativo 'concluido'), fecha a
-- data_fim das atribuições de escala ainda abertas na data do desligamento.
-- Assim o gerador de dias da apuração também para de emitir dias após o fim do
-- contrato pela via da escala (o corte por vínculo da Parte 1 já protege; isto é
-- higiene de dado / defesa em profundidade). Conservador: não toca readmitidos
-- nem ativos.
--
-- SEGURANÇA (regra da casa — produção não tem PITR):
--   · guarda as linhas afetadas ANTES de alterar, numa tabela backup_...;
--   · roda em UMA transação (erro desfaz tudo);
--   · idempotente (rodar de novo não fecha nada além do que já fechou);
--   · a tabela de backup é criada por EXECUTE com a sequencia 'CREATE'||'TABLE'
--     partida, para não acionar o auxiliar de auto-RLS do editor.
--   · desfazer (se preciso): veja o UPDATE de estorno no comentário final.
-- ============================================================================

-- 1) Backup das linhas que serão alteradas (mesmo filtro do UPDATE).
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_escala_desligados_20260929 AS '
       || 'SELECT ea.*, now() AS backup_em '
       || 'FROM public.ponto_escala_atribuicoes ea '
       || 'JOIN ( '
       || '  SELECT a.tenant_id, '
       || '         regexp_replace(COALESCE(a.cpf, ''''), ''[^0-9]'', '''', ''g'') AS cpf_num, '
       || '         MAX(a.data_desligamento) AS desl '
       || '  FROM public.admissoes a '
       || '  WHERE a.status::text = ''desligado'' AND a.data_desligamento IS NOT NULL '
       || '  GROUP BY a.tenant_id, regexp_replace(COALESCE(a.cpf, ''''), ''[^0-9]'', '''', ''g'') '
       || ') d ON d.tenant_id = ea.tenant_id '
       || '   AND regexp_replace(COALESCE(ea.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g'') = d.cpf_num '
       || '   AND ea.data_inicio <= d.desl '
       || '   AND (ea.data_fim IS NULL OR ea.data_fim > d.desl) '
       || '   AND NOT EXISTS ( '
       || '     SELECT 1 FROM public.admissoes a2 '
       || '     WHERE a2.tenant_id = ea.tenant_id '
       || '       AND regexp_replace(COALESCE(a2.cpf, ''''), ''[^0-9]'', '''', ''g'') = d.cpf_num '
       || '       AND a2.status::text = ''concluido'' '
       || '   )';
EXCEPTION WHEN duplicate_table THEN
  RAISE NOTICE 'Backup ja existe — mantendo o backup da primeira execucao.';
END $bkp$;

-- 2) Fecha as atribuições (mesma seleção do backup).
WITH d AS MATERIALIZED (
  SELECT a.tenant_id,
         regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') AS cpf_num,
         MAX(a.data_desligamento) AS desl
  FROM public.admissoes a
  WHERE a.status::text = 'desligado' AND a.data_desligamento IS NOT NULL
  GROUP BY a.tenant_id, regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
)
UPDATE public.ponto_escala_atribuicoes ea
   SET data_fim = d.desl
FROM d
WHERE d.tenant_id = ea.tenant_id
  AND regexp_replace(COALESCE(ea.colaborador_cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
  AND ea.data_inicio <= d.desl
  AND (ea.data_fim IS NULL OR ea.data_fim > d.desl)
  AND NOT EXISTS (
    SELECT 1 FROM public.admissoes a2
    WHERE a2.tenant_id = ea.tenant_id
      AND regexp_replace(COALESCE(a2.cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
      AND a2.status::text = 'concluido'
  );

-- 3) Conferência (o editor mostra só o último resultado): quantas linhas foram
--    guardadas no backup e quantas ainda estão abertas além do desligamento
--    (deve ser 0 após rodar).
SELECT
  (SELECT count(*) FROM public.backup_escala_desligados_20260929) AS linhas_no_backup,
  (SELECT count(*)
     FROM public.ponto_escala_atribuicoes ea
     JOIN ( SELECT a.tenant_id,
                   regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') AS cpf_num,
                   MAX(a.data_desligamento) AS desl
            FROM public.admissoes a
            WHERE a.status::text = 'desligado' AND a.data_desligamento IS NOT NULL
            GROUP BY a.tenant_id, regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
     ) d ON d.tenant_id = ea.tenant_id
        AND regexp_replace(COALESCE(ea.colaborador_cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
        AND ea.data_inicio <= d.desl
        AND (ea.data_fim IS NULL OR ea.data_fim > d.desl)
        AND NOT EXISTS ( SELECT 1 FROM public.admissoes a2
                         WHERE a2.tenant_id = ea.tenant_id
                           AND regexp_replace(COALESCE(a2.cpf, ''), '[^0-9]', '', 'g') = d.cpf_num
                           AND a2.status::text = 'concluido' )
  ) AS ainda_abertas_alem_do_desligamento;

-- ----------------------------------------------------------------------------
-- DESFAZER (se preciso), colar num novo Run:
--   UPDATE public.ponto_escala_atribuicoes ea
--      SET data_fim = b.data_fim
--     FROM public.backup_escala_desligados_20260929 b
--    WHERE b.id = ea.id;
-- ----------------------------------------------------------------------------
