-- ============================================================================
-- PRODUCAO — FOTOGRAFIA DA APURACAO (passo 0 da transicao)
--
-- Rode ANTES de colar o primeiro pacote. Ele guarda, numa tabela propria, o
-- que a apuracao devolve HOJE para cada colaborador e cada competencia.
--
-- POR QUE ISSO EXISTE
-- Varios pacotes corrigem o MOTOR de apuracao (tolerancia dos dois tetos, hora
-- extra sem truncar, adicional noturno prorrogado, turno da virada, domingo em
-- dobro, escala 12x36). A apuracao e calculada na hora, a partir das batidas —
-- entao corrigir o motor muda tambem o resultado de competencias ANTIGAS, ja
-- fechadas e ja pagas. Isso e o objetivo das correcoes, nao um efeito colateral.
--
-- Mas alguem precisa saber QUAIS folhas se mexeram e em quanto. Sem esta
-- fotografia, a informacao se perde no momento em que o primeiro pacote entra,
-- e nao volta mais. Com ela, ao final roda-se a comparacao e sai a lista:
-- competencia por competencia, quantos dias mudaram e quantos minutos.
--
-- O QUE FAZ: cria a tabela ponto_apuracao_fotografia (so dela) e grava o
-- retrato rotulado como 'antes'. NAO toca em nenhum dado de ponto, folha ou
-- colaborador. Idempotente: rodar de novo regrava o 'antes'.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.ponto_apuracao_fotografia (
  momento               text        NOT NULL,   -- 'antes' | 'depois'
  tenant_id             uuid        NOT NULL,
  colaborador_cpf       text        NOT NULL,
  competencia           text        NOT NULL,
  competencia_fechada   boolean     NOT NULL,
  dia                   date        NOT NULL,
  entrada               time,
  saida                 time,
  trabalhado_min        integer,
  jornada_min           integer,
  saldo_min             integer,
  protegido             boolean,
  equalizacao           boolean,
  excedente_retido_min  integer,
  tirada_em             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (momento, tenant_id, colaborador_cpf, competencia, dia)
);

COMMENT ON TABLE public.ponto_apuracao_fotografia IS
  'Retrato da apuracao antes e depois da transicao do modulo Ponto para producao. Serve para listar quais competencias fechadas tiveram o resultado alterado pelas correcoes do motor. Pode ser descartada depois da conferencia.';

DELETE FROM public.ponto_apuracao_fotografia WHERE momento = 'antes';

INSERT INTO public.ponto_apuracao_fotografia
  (momento, tenant_id, colaborador_cpf, competencia, competencia_fechada, dia,
   entrada, saida, trabalhado_min, jornada_min, saldo_min, protegido,
   equalizacao, excedente_retido_min)
SELECT 'antes', a.tenant_id, a.colaborador_cpf, a.comp,
       (f.tenant_id IS NOT NULL), s.dia,
       s.entrada, s.saida, s.trabalhado_min, s.jornada_min, s.saldo_min,
       s.protegido, s.equalizacao, s.excedente_retido_min
FROM (
  SELECT DISTINCT d.tenant_id, d.colaborador_cpf, to_char(d.data, 'YYYY-MM') AS comp
  FROM public.ponto_diario d
) a
LEFT JOIN public.ponto_fechamentos f
  ON f.tenant_id = a.tenant_id AND f.competencia = a.comp AND f.status = 'fechado'
CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(
  a.tenant_id, a.colaborador_cpf, a.comp) s
ON CONFLICT (momento, tenant_id, colaborador_cpf, competencia, dia) DO NOTHING;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Guarde estes numeros. Nao ha valor "esperado": e o retrato de partida.
-- ---------------------------------------------------------------------------
SELECT
  to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') AS tirada_em,
  (SELECT count(*) FROM public.ponto_marcacoes)                          AS marcacoes,
  (SELECT count(*) FROM public.ponto_diario)                             AS dias_apurados,
  (SELECT count(*) FROM public.ponto_fechamentos WHERE status='fechado')  AS competencias_fechadas,
  (SELECT count(*) FROM public.ponto_apuracao_fotografia WHERE momento='antes') AS linhas_fotografadas,
  (SELECT count(*) FROM public.ponto_apuracao_fotografia
     WHERE momento='antes' AND competencia_fechada)                       AS linhas_de_competencia_fechada,
  CASE WHEN (SELECT count(*) FROM public.ponto_apuracao_fotografia WHERE momento='antes') > 0
       THEN 'OK — fotografia guardada, pode comecar'
       ELSE 'CONFERIR — nada foi fotografado' END                         AS erro_tecnico;
