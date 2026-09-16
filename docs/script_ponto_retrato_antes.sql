-- ============================================================================
-- RETRATO ANTES — a fotografia do Ponto imediatamente antes da entrega
--
-- POR QUE ESTE ARQUIVO E O PRIMEIRO DE TODOS
-- Sem um retrato do estado atual, nenhuma conferencia depois quer dizer nada:
-- diante de qualquer numero estranho, ninguem consegue responder "isso mudou
-- por causa da entrega ou ja era assim?". Este script tira essa fotografia.
--
-- O QUE ELE FAZ
-- Le a apuracao diaria dos ultimos 13 meses e guarda, por empresa, competencia
-- e colaborador, os numeros que a entrega poderia mexer: horas trabalhadas,
-- extras, faltantes, dias de falta, dias de feriado, marcacoes, espelhos e
-- saldo de banco. Tudo numa tabela nova, ponto_retrato_pre.
--
-- O QUE ELE NAO FAZ
-- Nao altera, nao apaga e nao recalcula nada. So LE as tabelas do Ponto e
-- ESCREVE numa tabela nova, que nao existia antes e que nenhum sistema le.
-- Por isso nao precisa de copia de seguranca: ele nao tem o que desfazer.
--
-- QUANDO RODAR
-- No SQL Editor da producao, ANTES da primeira parte da entrega. Pode rodar de
-- novo: cada execucao vira um retrato datado (a coluna tirado_em), e o retrato
-- do dia e substituido em vez de duplicar.
--
-- DEPOIS
-- O script de conferencia de efeito compara este retrato com o estado de
-- entao. Guarde a tabela: ela e a prova de que o passado nao foi reescrito.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.ponto_retrato_pre (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tirado_em         date NOT NULL DEFAULT CURRENT_DATE,
  tirado_as         timestamptz NOT NULL DEFAULT now(),
  tenant_id         uuid NOT NULL,
  empresa_id        uuid,
  competencia       text NOT NULL,
  colaborador_cpf   text NOT NULL,
  dias              integer,
  trabalhadas_min   bigint,
  extras_min        bigint,
  faltantes_min     bigint,
  dias_falta        integer,
  dias_feriado      integer,
  dias_justificado  integer,
  marcacoes         integer,
  espelhos          integer,
  saldo_banco_min   bigint
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ponto_retrato_pre_grao
  ON public.ponto_retrato_pre
     (tirado_em, tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid),
      competencia, colaborador_cpf);

-- ---------------------------------------------------------------------
-- FECHADURA — a tabela guarda CPF e horas por colaborador. No Supabase,
-- tabela nova em public fica exposta pela API: sem isto, qualquer usuario
-- autenticado leria o retrato inteiro, de todos os clientes (LGPD art. 46).
-- Com RLS ligada e NENHUMA politica, ninguem le pela API. Sem FORCE de
-- proposito: o dono da tabela — que e quem o SQL Editor usa — continua lendo,
-- para a conferencia de efeito conseguir comparar com o retrato.
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_retrato_pre ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_retrato_pre FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_retrato_pre FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base — nada a revogar.';
END $fechadura$;

COMMENT ON TABLE public.ponto_retrato_pre IS
  'Fotografia da apuracao do Ponto tirada antes de uma entrega, por empresa, competencia e colaborador. Serve de referencia para provar que a entrega nao reescreveu competencia ja apurada. Somente leitura para o sistema: nenhuma rotina do produto le esta tabela.';

-- ---------------------------------------------------------------------
-- A fotografia. O SELECT e montado conforme as colunas que ESTE ambiente
-- tem: onde uma coluna nao existe, o numero correspondente sai zerado em
-- vez de o script quebrar.
-- ---------------------------------------------------------------------
DO $retrato$
DECLARE
  v_extras    text;
  v_faltantes text;
  v_tipo      text;
  v_empresa   text;
  v_linhas    bigint;

  -- Conferencia de coluna feita aqui mesmo: este script roda na producao, onde
  -- as ferramentas da bancada de testes nao existem.
BEGIN
  v_extras := CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                                 WHERE table_schema='public' AND table_name='ponto_diario'
                                   AND column_name='horas_extras')
                   THEN 'COALESCE(EXTRACT(EPOCH FROM d.horas_extras)/60, 0)' ELSE '0' END;
  v_faltantes := CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                                    WHERE table_schema='public' AND table_name='ponto_diario'
                                      AND column_name='horas_faltantes')
                      THEN 'COALESCE(EXTRACT(EPOCH FROM d.horas_faltantes)/60, 0)' ELSE '0' END;
  v_tipo := CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                               WHERE table_schema='public' AND table_name='ponto_diario'
                                 AND column_name='tipo_dia')
                 THEN 'COALESCE(d.tipo_dia, '''')' ELSE '''''' END;
  v_empresa := CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                                  WHERE table_schema='public' AND table_name='ponto_diario'
                                    AND column_name='empresa_id')
                    THEN 'd.empresa_id' ELSE 'NULL::uuid' END;

  -- O retrato de hoje e refeito do zero, para a segunda execucao no mesmo dia
  -- nao misturar dois momentos.
  DELETE FROM public.ponto_retrato_pre WHERE tirado_em = CURRENT_DATE;

  EXECUTE format($sql$
    INSERT INTO public.ponto_retrato_pre
      (tenant_id, empresa_id, competencia, colaborador_cpf, dias,
       trabalhadas_min, extras_min, faltantes_min,
       dias_falta, dias_feriado, dias_justificado, marcacoes, espelhos, saldo_banco_min)
    SELECT d.tenant_id,
           %s                                            AS empresa_id,
           to_char(d.data, 'YYYY-MM')                    AS competencia,
           d.colaborador_cpf,
           count(*)                                      AS dias,
           sum(COALESCE(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60, 0))::bigint,
           sum(%s)::bigint                               AS extras_min,
           sum(%s)::bigint                               AS faltantes_min,
           count(*) FILTER (WHERE d.status = 'falta')::int,
           count(*) FILTER (WHERE %s = 'feriado')::int,
           count(*) FILTER (WHERE d.status = 'justificado')::int,
           0, 0, 0
    FROM public.ponto_diario d
    WHERE d.data >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::date
    GROUP BY d.tenant_id, %s, to_char(d.data, 'YYYY-MM'), d.colaborador_cpf
  $sql$, v_empresa, v_extras, v_faltantes, v_tipo, v_empresa);

  GET DIAGNOSTICS v_linhas = ROW_COUNT;
  RAISE NOTICE 'Retrato: % linha(s) de apuracao diaria fotografadas.', v_linhas;
END $retrato$;

-- Marcacoes por colaborador e competencia.
UPDATE public.ponto_retrato_pre r
   SET marcacoes = x.n
  FROM (
    SELECT m.tenant_id, m.colaborador_cpf, to_char(m.data_marcacao,'YYYY-MM') AS comp,
           count(*)::int AS n
    FROM public.ponto_marcacoes m
    WHERE m.data_marcacao >= (date_trunc('month', CURRENT_DATE) - INTERVAL '12 months')::date
    GROUP BY 1,2,3
  ) x
 WHERE r.tirado_em = CURRENT_DATE
   AND r.tenant_id = x.tenant_id
   AND r.colaborador_cpf = x.colaborador_cpf
   AND r.competencia = x.comp;

-- Espelhos emitidos por colaborador e competencia.
UPDATE public.ponto_retrato_pre r
   SET espelhos = x.n
  FROM (
    SELECT e.tenant_id, e.colaborador_cpf, e.competencia, count(*)::int AS n
    FROM public.ponto_espelhos e
    GROUP BY 1,2,3
  ) x
 WHERE r.tirado_em = CURRENT_DATE
   AND r.tenant_id = x.tenant_id
   AND r.colaborador_cpf = x.colaborador_cpf
   AND r.competencia = x.competencia;

-- Horas extras: na apuracao diaria elas costumam vir vazias (o excedente e
-- calculado na competencia, nao gravado no dia). Onde o espelho ja foi emitido,
-- ele e a fonte melhor — e a que o colaborador viu.
DO $extras$
BEGIN
  UPDATE public.ponto_retrato_pre r
     SET extras_min = GREATEST(COALESCE(r.extras_min, 0), x.extras)
    FROM (
      SELECT e.tenant_id, e.colaborador_cpf, e.competencia,
             sum(COALESCE(e.total_horas_extras_50_minutos, 0)
               + COALESCE(e.total_horas_extras_100_minutos, 0))::bigint AS extras
      FROM public.ponto_espelhos e
      GROUP BY 1,2,3
    ) x
   WHERE r.tirado_em = CURRENT_DATE
     AND r.tenant_id = x.tenant_id
     AND r.colaborador_cpf = x.colaborador_cpf
     AND r.competencia = x.competencia;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel ler as horas extras do espelho (%). O resto do retrato esta completo.', SQLERRM;
END $extras$;

-- Saldo do banco de horas por colaborador e competencia.
DO $banco$
BEGIN
  IF to_regclass('public.ponto_banco_horas') IS NULL THEN
    RAISE NOTICE 'Sem tabela de banco de horas neste ambiente — saldo fica zerado no retrato.';
    RETURN;
  END IF;

  UPDATE public.ponto_retrato_pre r
     SET saldo_banco_min = x.saldo
    FROM (
      SELECT b.tenant_id, b.colaborador_cpf, b.competencia,
             sum(COALESCE(b.saldo_atual_minutos, 0))::bigint AS saldo
      FROM public.ponto_banco_horas b
      GROUP BY 1,2,3
    ) x
   WHERE r.tirado_em = CURRENT_DATE
     AND r.tenant_id = x.tenant_id
     AND r.colaborador_cpf = x.colaborador_cpf
     AND r.competencia = x.competencia;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel fotografar o saldo do banco de horas (%). O resto do retrato esta completo.', SQLERRM;
END $banco$;

-- ============================================================================
-- CONFERENCIA
-- Uma linha por competencia fotografada, da mais recente para a mais antiga,
-- e uma linha de resumo no fim. Guarde este resultado: e o retrato em resumo.
-- ============================================================================
WITH r AS MATERIALIZED (
  SELECT * FROM public.ponto_retrato_pre WHERE tirado_em = CURRENT_DATE
)
SELECT competencia,
       count(DISTINCT colaborador_cpf)::text        AS colaboradores,
       sum(dias)::text                              AS dias_apurados,
       round(sum(trabalhadas_min)/60.0, 1)::text    AS horas_trabalhadas,
       round(sum(extras_min)/60.0, 1)::text         AS horas_extras,
       sum(dias_falta)::text                        AS dias_falta,
       sum(marcacoes)::text                         AS marcacoes,
       sum(espelhos)::text                          AS espelhos,
       ''::text                                     AS situacao
FROM r
GROUP BY competencia
UNION ALL
SELECT 'RETRATO ' || to_char(CURRENT_DATE, 'DD/MM/YYYY'),
       count(DISTINCT colaborador_cpf)::text,
       sum(dias)::text,
       round(sum(trabalhadas_min)/60.0, 1)::text,
       round(sum(extras_min)/60.0, 1)::text,
       sum(dias_falta)::text,
       sum(marcacoes)::text,
       sum(espelhos)::text,
       CASE WHEN count(*) = 0 THEN 'VAZIO — nada foi fotografado, confira antes de seguir'
            ELSE 'OK — retrato guardado, pode aplicar a entrega' END
FROM r
ORDER BY 1 DESC;
