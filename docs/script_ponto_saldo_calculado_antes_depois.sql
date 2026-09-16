-- ============================================================================
-- SALDO CALCULADO — a medida do efeito das cinco correcoes
--
-- POR QUE ESTE ARQUIVO EXISTE
-- As cinco correcoes da auditoria de DP nao mexem em NENHUMA linha gravada:
-- elas mudam a CONTA, que e refeita a cada consulta. Por isso o retrato
-- comum (script_ponto_retrato_antes.sql), que fotografa o que esta GRAVADO,
-- continua igual antes e depois — e nao consegue mostrar o efeito.
--
-- Este arquivo fotografa o que a conta RESPONDE. Rodando uma vez antes da
-- entrega e outra depois, a diferenca entre as duas fotografias e, exatamente,
-- o efeito das correcoes. Nada mais.
--
-- COMO USAR — RODE O MESMO ARQUIVO DUAS VEZES
--   1a execucao (ANTES da entrega): grava a fotografia "antes";
--   2a execucao (DEPOIS da entrega): grava a fotografia "depois".
-- Ele decide sozinho qual das duas esta gravando e diz na conferencia. Uma
-- terceira execucao refaz a "depois" (util se voce rodar de novo mais tarde).
-- Para recomecar do zero: DROP TABLE public.ponto_efeito_apuracao;
--
-- O QUE ELE LE
-- So os colaboradores que REALMENTE batem ponto (tem marcacao no periodo), das
-- empresas com o controle de ponto LIGADO, nas duas ultimas competencias. E o
-- universo em que as correcoes podem mudar alguma coisa — e mante-lo pequeno e
-- o que faz o script caber no tempo do SQL Editor.
--
-- O QUE ELE NAO FAZ
-- Nao altera, nao apaga e nao recalcula nada do produto. So LE a apuracao e
-- ESCREVE numa tabela nova, que nenhuma rotina do sistema consulta.
-- ============================================================================

SET lock_timeout = '10s';
SET statement_timeout = '600s';

CREATE TABLE IF NOT EXISTS public.ponto_efeito_apuracao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  momento         text NOT NULL,          -- 'antes' | 'depois'
  tirado_as       timestamptz NOT NULL DEFAULT now(),
  tenant_id       uuid NOT NULL,
  empresa_id      uuid,
  empresa_nome    text,
  competencia     text NOT NULL,
  colaborador_cpf text NOT NULL,
  dias            integer,
  trabalhado_min  bigint,
  creditos_min    bigint,
  debitos_min     bigint,
  saldo_min       bigint
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ponto_efeito_apuracao_grao
  ON public.ponto_efeito_apuracao
     (momento, tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid),
      competencia, colaborador_cpf);

-- ---------------------------------------------------------------------
-- FECHADURA — a tabela guarda CPF e horas por colaborador. No Supabase,
-- tabela nova em public fica exposta pela API: sem isto, qualquer usuario
-- autenticado leria a fotografia inteira, de todos os clientes (LGPD art. 46).
-- Com RLS ligada e NENHUMA politica, ninguem le pela API. Sem FORCE de
-- proposito: o dono da tabela — que e quem o SQL Editor usa — continua lendo,
-- para a comparacao conseguir ser feita.
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_efeito_apuracao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_efeito_apuracao FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_efeito_apuracao FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base — nada a revogar.';
END $fechadura$;

COMMENT ON TABLE public.ponto_efeito_apuracao IS
  'Fotografia do saldo CALCULADO pela apuracao do Ponto, tirada antes e depois de uma entrega. A diferenca entre os dois momentos e o efeito da entrega. Apoio de operacao: nenhuma rotina do produto le esta tabela.';

-- ---------------------------------------------------------------------
-- A fotografia
-- ---------------------------------------------------------------------
DO $foto$
DECLARE
  v_momento text;
  v_linhas  bigint;
  v_comp1   text := to_char(CURRENT_DATE, 'YYYY-MM');
  v_comp2   text := to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM');
BEGIN
  SELECT CASE WHEN EXISTS (SELECT 1 FROM public.ponto_efeito_apuracao WHERE momento = 'antes')
              THEN 'depois' ELSE 'antes' END
    INTO v_momento;

  DELETE FROM public.ponto_efeito_apuracao WHERE momento = v_momento;

  INSERT INTO public.ponto_efeito_apuracao
    (momento, tenant_id, empresa_id, empresa_nome, competencia, colaborador_cpf,
     dias, trabalhado_min, creditos_min, debitos_min, saldo_min)
  SELECT v_momento,
         q.tenant_id,
         q.empresa_id,
         q.empresa_nome,
         q.competencia,
         q.cpf,
         count(*)::int,
         COALESCE(SUM(s.trabalhado_min), 0)::bigint,
         COALESCE(SUM(CASE WHEN s.saldo_min > 0 THEN s.saldo_min ELSE 0 END), 0)::bigint,
         COALESCE(SUM(CASE WHEN s.saldo_min < 0 THEN -s.saldo_min ELSE 0 END), 0)::bigint,
         COALESCE(SUM(s.saldo_min), 0)::bigint
  FROM (
    -- Quem realmente bate ponto, em empresa com o modulo ligado.
    SELECT DISTINCT
           d.tenant_id,
           d.empresa_id,
           COALESCE(e.nome_fantasia, e.razao_social)                          AS empresa_nome,
           to_char(d.data, 'YYYY-MM')                                         AS competencia,
           regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf
    FROM public.ponto_diario d
    JOIN public.empresa_cadastro e ON e.id = d.empresa_id
    WHERE COALESCE(e.usa_controle_ponto, false) = true
      AND to_char(d.data, 'YYYY-MM') IN (v_comp1, v_comp2)
      AND EXISTS (
        SELECT 1 FROM public.ponto_marcacoes m
        WHERE m.tenant_id = d.tenant_id
          AND regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g')
            = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g')
          AND to_char(m.data_marcacao, 'YYYY-MM') = to_char(d.data, 'YYYY-MM'))
  ) q
  CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(q.tenant_id, q.cpf, q.competencia) s
  GROUP BY q.tenant_id, q.empresa_id, q.empresa_nome, q.competencia, q.cpf;

  GET DIAGNOSTICS v_linhas = ROW_COUNT;
  RAISE NOTICE 'Fotografia "%" gravada: % linha(s).', v_momento, v_linhas;
END $foto$;

-- ============================================================================
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- ============================================================================
WITH n AS MATERIALIZED (
  SELECT momento, count(*) AS linhas, max(tirado_as) AS quando
  FROM public.ponto_efeito_apuracao
  GROUP BY momento
),
linhas AS MATERIALIZED (
  SELECT m.momento,
         COALESCE(n.linhas, 0) AS linhas,
         n.quando
  FROM (VALUES ('antes'), ('depois')) m(momento)
  LEFT JOIN n ON n.momento = m.momento
)
SELECT momento                                                    AS fotografia,
       CASE WHEN quando IS NULL THEN 'ainda nao tirada'
            ELSE linhas::text || ' colaborador(es) x competencia' END AS detalhe,
       COALESCE(to_char(quando, 'DD/MM/YYYY HH24:MI'), '-')        AS tirada_em,
       CASE
         WHEN momento = 'antes' AND quando IS NULL
           THEN 'PENDENTE: a fotografia "antes" nao foi gravada'
         WHEN momento = 'antes' AND linhas = 0
           THEN 'ATENCAO: nenhum colaborador entrou na fotografia. Confira se ha empresa com o controle de ponto LIGADO e com marcacoes nas duas ultimas competencias.'
         WHEN momento = 'antes'
           THEN 'OK — agora rode as partes da entrega e volte a rodar ESTE MESMO arquivo'
         WHEN quando IS NULL
           THEN 'Ainda nao — rode este arquivo de novo DEPOIS das partes da entrega'
         ELSE 'OK — as duas fotografias existem: rode agora o script_ponto_efeito_das_correcoes.sql'
       END                                                        AS erro_tecnico
FROM linhas
ORDER BY (momento = 'depois');
