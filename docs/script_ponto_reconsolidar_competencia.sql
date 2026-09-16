-- ============================================================================
-- RECONSOLIDAR UMA COMPETENCIA — para a correcao do minuto alcancar o passado
--
-- ESTE ARQUIVO REESCREVE ponto_diario. Leia antes de colar.
--
-- SO RODE DEPOIS DE:
--   1. rodar o script_ponto_quanto_mudaria_reconsolidar.sql, e conferir cada
--      dia divergente com o script_ponto_detalhe_dos_dias_divergentes.sql;
--   2. reabrir a competencia, se ela estiver fechada (ver o fim deste arquivo).
--
-- A TRAVA QUE DISPENSA O VEREDITO PERFEITO
-- Este arquivo NAO reescreve dia que PERDERIA tempo. Antes de tocar em cada
-- dia, ele pergunta a conta quanto daria; se o resultado for MENOR que o
-- gravado, o dia fica exatamente como esta e sai listado na conferencia.
-- Isso e o oposto de uma reconsolidacao cega: o objetivo e recuperar o minuto
-- descartado, nunca apagar hora que ja esta registrada. Na medicao da
-- producao de 01/09/2026, um unico dia derrubava o ganho da competencia
-- inteira de +762 min para -8 min — com esta trava, esse dia e simplesmente
-- deixado de lado, e os +762 min chegam a quem tem direito.
--
-- O QUE FAZ
-- Manda a consolidacao diaria recalcular, dia a dia, os colaboradores que
-- REALMENTE bateram ponto na competencia, em empresa com o modulo ligado. E o
-- unico caminho para a correcao do minuto (PONTO-470) alcancar dias que ja
-- estavam gravados: as outras quatro correcoes agem na hora de calcular o
-- saldo e ja valem para o passado sem reescrever nada.
--
-- O QUE NAO FAZ, DE PROPOSITO
--   * NAO toca em quem nunca bateu ponto. Reconsolidar essa gente e
--     exatamente o que recria as faltas fantasma que limpamos em 01/09/2026 —
--     por isso o alvo exige marcacao no dia;
--   * NAO usa consolidar_ponto_dia_todos, que varre o quadro inteiro pelo
--     cadastro de admissoes e traria de volta o mesmo problema;
--   * NAO mexe em dia JA TRATADO por uma pessoa — justificado, incompleto,
--     com ajuste pendente, ou coberto por atestado. A consolidacao preserva o
--     ROTULO do dia justificado, mas sobrescreveria as HORAS; num dia de
--     atestado com marcacoes (a pessoa trabalhou parte e tem abono do resto)
--     isso recontaria o tempo. Por isso esses dias sao excluidos na origem,
--     e nao so protegidos pela trava — a trava so pega o dia que PERDE tempo,
--     e o dia de atestado aparece como GANHO;
--   * NAO apaga marcacao nenhuma. Ajuste aprovado vira marcacao no ato da
--     aprovacao, entao ele sobrevive a reconsolidacao.
--
-- A COPIA DE SEGURANCA
-- Antes de reescrever, guarda a linha inteira de cada dia que sera tocado em
-- backup_ponto_diario_reconsolidacao_AAAAMMDD. O comando que desfaz esta no
-- fim do arquivo. A producao nao tem Point-in-Time Recovery: esta copia e o
-- resgate.
--
-- SE DER TEMPO ESGOTADO: nada foi alterado — o editor roda o arquivo inteiro
-- numa transacao so. Me avise que eu divido por empresa.
--
-- Idempotente: rodar de novo recalcula os mesmos dias para os mesmos numeros
-- e mantem a copia do dia.
-- ============================================================================

SET lock_timeout = '10s';
SET statement_timeout = '600s';

-- ---------------------------------------------------------------------
-- 0) O alvo, definido uma vez e usado por todos os passos
-- ---------------------------------------------------------------------
DO $reconsolida$
DECLARE
  v_comp   text := '2026-08';   -- AJUSTE AQUI: competencia
  -- AJUSTE AQUI: CNPJs a deixar de fora (empresa que ainda vai configurar
  -- pre-assinalacao, por exemplo). Deixe ARRAY[]::text[] para nao excluir
  -- ninguem.
  v_fora   text[] := ARRAY[]::text[];
  v_nome   text := 'backup_ponto_diario_reconsolidacao_' || to_char(CURRENT_DATE, 'YYYYMMDD');
  v_n      bigint;
  c        RECORD;
  v_dias   int := 0;
  v_pulou  int := 0;
  v_calc   RECORD;
  v_fora_n text[];
BEGIN
  -- CNPJ so com digitos, uma vez, para comparar com o cadastro.
  SELECT COALESCE(array_agg(regexp_replace(x, '[^0-9]', '', 'g')), ARRAY[]::text[])
    INTO v_fora_n FROM unnest(v_fora) x;
  -- 1) COPIA DE SEGURANCA da linha inteira de cada dia que sera tocado.
  IF to_regclass('public.' || v_nome) IS NOT NULL THEN
    EXECUTE format('SELECT count(*) FROM public.%I', v_nome) INTO v_n;
    RAISE NOTICE 'A copia % ja existe com % linha(s) — mantida como esta.', v_nome, v_n;
  ELSE
    EXECUTE format($sql$
      CREATE TABLE public.%I AS
      SELECT d.*
      FROM public.ponto_diario d
      JOIN public.empresa_cadastro e ON e.id = d.empresa_id
      WHERE COALESCE(e.usa_controle_ponto, false) = true
        AND to_char(d.data, 'YYYY-MM') = %L
        AND NOT (regexp_replace(COALESCE(e.cnpj, ''), '[^0-9]', '', 'g') = ANY (%L::text[]))
        -- [ja-tratado] dia justificado, incompleto, com ajuste ou coberto por
        -- atestado NAO entra: ele ja foi resolvido por uma pessoa, e a
        -- reconsolidacao (que so recupera o minuto do dia trabalhado)
        -- sobrescreveria as horas de um dia de abono, com risco de recontar.
        AND COALESCE(d.status, '') NOT IN ('justificado', 'incompleto', 'ajuste_pendente')
        AND NOT EXISTS (
          SELECT 1 FROM public.atestados a
          WHERE a.tenant_id = d.tenant_id
            AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
              = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g')
            AND a.data_inicio_afastamento IS NOT NULL
            AND a.data_inicio_afastamento <= d.data
            AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= d.data)
        AND EXISTS (
          SELECT 1 FROM public.ponto_marcacoes m
          WHERE m.tenant_id = d.tenant_id
            AND m.colaborador_cpf = d.colaborador_cpf
            AND m.data_marcacao = d.data)
    $sql$, v_nome, v_comp, v_fora_n);
    EXECUTE format('SELECT count(*) FROM public.%I', v_nome) INTO v_n;
    RAISE NOTICE 'Copia de seguranca criada: % com % linha(s).', v_nome, v_n;
  END IF;

  -- 2) A reconsolidacao, dia a dia, colaborador a colaborador.
  FOR c IN
    SELECT DISTINCT d.tenant_id, d.colaborador_cpf, d.colaborador_id, d.data,
           COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas) / 60)::int, 0) AS min_gravado
    FROM public.ponto_diario d
    JOIN public.empresa_cadastro e ON e.id = d.empresa_id
    WHERE COALESCE(e.usa_controle_ponto, false) = true
      AND to_char(d.data, 'YYYY-MM') = v_comp
      AND NOT (regexp_replace(COALESCE(e.cnpj, ''), '[^0-9]', '', 'g') = ANY (v_fora_n))
      -- [ja-tratado] mesmo filtro do backup: dia de abono nao se reconsolida.
      AND COALESCE(d.status, '') NOT IN ('justificado', 'incompleto', 'ajuste_pendente')
      AND NOT EXISTS (
        SELECT 1 FROM public.atestados a
        WHERE a.tenant_id = d.tenant_id
          AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
            = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g')
          AND a.data_inicio_afastamento IS NOT NULL
          AND a.data_inicio_afastamento <= d.data
          AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= d.data)
      AND EXISTS (
        SELECT 1 FROM public.ponto_marcacoes m
        WHERE m.tenant_id = d.tenant_id
          AND m.colaborador_cpf = d.colaborador_cpf
          AND m.data_marcacao = d.data)
    ORDER BY d.data
  LOOP
    BEGIN
      -- A TRAVA: pergunta a conta quanto daria ANTES de gravar. Dia que
      -- perderia tempo fica exatamente como esta.
      SELECT * INTO v_calc
      FROM public._ponto_calc_dia(c.tenant_id, c.colaborador_cpf, c.data, c.colaborador_id::uuid);

      IF COALESCE(EXTRACT(EPOCH FROM v_calc.o_horas) / 60, 0)::int < c.min_gravado THEN
        v_pulou := v_pulou + 1;
        RAISE NOTICE 'PULADO — dia % do CPF ...%: gravado % min, a conta daria % min. Nao reescrevo dia que perde tempo.',
          c.data, right(c.colaborador_cpf, 3), c.min_gravado,
          COALESCE(EXTRACT(EPOCH FROM v_calc.o_horas) / 60, 0)::int;
        CONTINUE;
      END IF;

      PERFORM public.consolidar_ponto_diario_manual(c.tenant_id, c.colaborador_cpf, c.data);
      v_dias := v_dias + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Um dia problematico nao pode derrubar a competencia inteira.
      RAISE NOTICE 'Dia % do CPF ...%: %', c.data, right(c.colaborador_cpf, 3), SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '% dia(s) reconsolidado(s) e % dia(s) preservado(s) por perderiam tempo, na competencia %.',
    v_dias, v_pulou, v_comp;
END $reconsolida$;

-- ============================================================================
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- ============================================================================
WITH nome AS MATERIALIZED (
  SELECT 'backup_ponto_diario_reconsolidacao_' || to_char(CURRENT_DATE, 'YYYYMMDD') AS t,
         '2026-08'::text AS competencia   -- AJUSTE AQUI: a mesma competencia acima
),
copia AS MATERIALIZED (
  SELECT (xpath('/row/c/text()',
           query_to_xml('SELECT count(*) AS c, COALESCE(SUM(EXTRACT(EPOCH FROM horas_trabalhadas)/60), 0) AS m FROM public.'
                        || quote_ident(n.t), false, true, '')))[1]::text::bigint AS linhas,
         (xpath('/row/m/text()',
           query_to_xml('SELECT count(*) AS c, COALESCE(SUM(EXTRACT(EPOCH FROM horas_trabalhadas)/60), 0) AS m FROM public.'
                        || quote_ident(n.t), false, true, '')))[1]::text::numeric AS minutos
  FROM nome n
),
agora AS MATERIALIZED (
  -- O estado ATUAL das MESMAS linhas que a copia guardou (join por id). Antes
  -- esta contagem varria TODOS os dias com marcacao, incluindo os de atestado
  -- e abono que a reconsolidacao nao toca — e a diferenca (esses dias a mais)
  -- disparava um "CONFERIR" falso. Comparando linha a linha as mesmas linhas,
  -- a contagem bate e o "so somou tempo" passa a ser uma verdade sobre o que
  -- foi de fato reescrito.
  SELECT (xpath('/row/c/text()',
           query_to_xml('SELECT count(*) AS c, COALESCE(SUM(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60), 0) AS m'
                        || ' FROM public.ponto_diario d WHERE d.id IN (SELECT b.id FROM public.'
                        || quote_ident(n.t) || ' b)', false, true, '')))[1]::text::bigint AS linhas,
         (xpath('/row/m/text()',
           query_to_xml('SELECT count(*) AS c, COALESCE(SUM(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60), 0) AS m'
                        || ' FROM public.ponto_diario d WHERE d.id IN (SELECT b.id FROM public.'
                        || quote_ident(n.t) || ' b)', false, true, '')))[1]::text::numeric AS minutos
  FROM nome n
)
SELECT 'dias na copia'::text                                        AS o_que,
       (SELECT linhas::text FROM copia)                             AS antes,
       (SELECT linhas::text FROM agora)                             AS depois,
       'guardados linha a linha em ' || (SELECT t FROM nome)         AS detalhe,
       CASE WHEN (SELECT linhas FROM copia) = (SELECT linhas FROM agora)
            THEN 'OK' ELSE 'CONFERIR: o numero de dias mudou' END    AS erro_tecnico
UNION ALL
SELECT 'minutos trabalhados',
       to_char((SELECT minutos FROM copia), 'FM999990'),
       to_char((SELECT minutos FROM agora), 'FM999990'),
       CASE WHEN (SELECT minutos FROM agora) >= (SELECT minutos FROM copia)
            THEN '+' ELSE '' END
         || to_char((SELECT minutos FROM agora) - (SELECT minutos FROM copia), 'FM999990')
         || ' min recuperados',
       CASE WHEN (SELECT minutos FROM agora) >= (SELECT minutos FROM copia)
            THEN 'OK — a reconsolidacao so somou tempo'
            ELSE 'PARE: a competencia PERDEU tempo. Desfaca com o comando no fim do arquivo e me avise.' END;

-- ---------------------------------------------------------------------
-- PARA DESFAZER (troque AAAAMMDD pela data de hoje):
--   UPDATE public.ponto_diario d
--      SET entrada = b.entrada, saida_almoco = b.saida_almoco,
--          retorno_almoco = b.retorno_almoco, saida = b.saida,
--          horas_trabalhadas = b.horas_trabalhadas, status = b.status,
--          observacao = b.observacao, updated_at = now()
--     FROM public.backup_ponto_diario_reconsolidacao_AAAAMMDD b
--    WHERE d.id = b.id;
--
-- REABRIR A COMPETENCIA, se estiver fechada (rode ANTES da reconsolidacao).
-- Arquiva os espelhos vigentes em ponto_espelhos_historico com numero de
-- versao e registra motivo, responsavel e trilha de auditoria:
--   SELECT public.ponto_reabrir_competencia(
--     '<tenant_id>'::uuid, '<empresa_id>'::uuid, '2026-08',
--     'Correcao do truncamento de minutos apurada em 01/09/2026 (PONTO-470)',
--     'contato@ustudy.com.br', 'Nome de quem autorizou');
--
-- DEPOIS DA RECONSOLIDACAO, atualizar o banco de horas e reemitir espelhos:
--   SELECT public.apurar_banco_horas('<tenant_id>'::uuid, '2026-08', '<empresa_id>'::uuid);
--   SELECT public.ponto_gerar_espelhos_competencia('<tenant_id>'::uuid, '2026-08', '<empresa_id>'::uuid);
-- E entao colher a ciencia do colaborador sobre o espelho novo.
-- ---------------------------------------------------------------------
