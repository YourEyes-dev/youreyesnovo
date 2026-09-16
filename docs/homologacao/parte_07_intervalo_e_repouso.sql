-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 07 de 16: Intervalo, repouso semanal e domingo
--
-- Faixas de intervalo do art. 71, indenizacao da supressao parcial (so os
-- minutos suprimidos), pre-assinalacao formal, DSR (desconto por falta e
-- reflexo das extras) e domingo/feriado trabalhado pago em dobro por
-- inteiro.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_ponto_onda4_faixas_intervalo.sql
--   * script_ponto_onda4_supressao_intervalo.sql
--   * script_ponto_onda4_pre_assinalacao.sql
--   * script_ponto_onda4_dsr.sql
--   * script_ponto_onda4_domingo_em_dobro.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda4_faixas_intervalo.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 4 (parte 1): faixas de intervalo intrajornada
-- Alvo: função public.ponto_intervalo_minimo_faixa
-- PONTO-062
--
-- O mínimo de intervalo intrajornada por FAIXA de jornada (CLT art. 71):
-- até 4h nenhum; 4-6h 15 min; acima de 6h 60 min. É a base do cálculo de
-- supressão (parte 2). Função pura (IMMUTABLE), aditiva, idempotente. Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_intervalo_minimo_faixa(p_jornada_min integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  -- Faixa de jornada -> minimo de intervalo intrajornada (CLT art. 71):
  -- ate 4h (240 min) nenhum; 4-6h (ate 360) 15 min; acima de 6h 60 min.
  SELECT CASE
           WHEN COALESCE(p_jornada_min, 0) <= 240 THEN 0
           WHEN p_jornada_min <= 360         THEN 15
           ELSE 60
         END;
$$;

COMMENT ON FUNCTION public.ponto_intervalo_minimo_faixa(integer) IS
  'Minimo legal de intervalo intrajornada por FAIXA de jornada (CLT art. 71): ate 4h nenhum; 4-6h 15 min; acima de 6h 60 min. Base do calculo de supressao.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | 0 | 15 | 15 | 60 | OK  (as faixas do art. 71)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_intervalo_minimo_faixa(integer)') IS NOT NULL) AS funcao_existe,
  public.ponto_intervalo_minimo_faixa(240) AS ate_4h,
  public.ponto_intervalo_minimo_faixa(300) AS de_4a6h,
  public.ponto_intervalo_minimo_faixa(360) AS ate_6h,
  public.ponto_intervalo_minimo_faixa(480) AS acima_6h,
  CASE
    WHEN to_regprocedure('public.ponto_intervalo_minimo_faixa(integer)') IS NOT NULL
     AND public.ponto_intervalo_minimo_faixa(240) = 0
     AND public.ponto_intervalo_minimo_faixa(300) = 15
     AND public.ponto_intervalo_minimo_faixa(360) = 15
     AND public.ponto_intervalo_minimo_faixa(480) = 60
      THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda4_supressao_intervalo.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 4 (parte 2): supressão de intervalo intrajornada
-- Alvos: ponto_supressao_intervalo; gatilho ponto_diario_supressao_intervalo
-- PONTO-060 / PONTO-061
--
-- O QUE FAZ (CLT art. 71, §4º pós-2017)
--   Jornada acima de 6h com pausa menor que a devida gera supressão de intervalo:
--   indenização de 50% sobre APENAS os minutos suprimidos, natureza indenizatória
--   (sem reflexos). A função calcula; um gatilho na consolidação grava os minutos
--   suprimidos em ponto_diario.he_intervalo_suprimido_minutos e alerta o RH
--   (parcial ou total), idempotente por colaborador/dia.
--
-- Depende da parte 1 (faixas de intervalo, #16). Aditivo e idempotente. Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_supressao_intervalo(
  p_jornada_min integer,
  p_gozado_min  integer
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  -- Supressao de intervalo (CLT art. 71, §4º pos-2017): indenizacao de 50%
  -- sobre APENAS os minutos suprimidos, com natureza indenizatoria (sem
  -- reflexos). O intervalo devido vem da faixa de jornada (parte 1).
  SELECT jsonb_build_object(
    'minutos_devidos',        d.devido,
    'minutos_gozados',        COALESCE(p_gozado_min, 0),
    'minutos_suprimidos',     GREATEST(0, d.devido - COALESCE(p_gozado_min, 0)),
    'percentual_indenizacao', 50,
    'natureza',               'indenizatoria',
    'indenizavel',            (GREATEST(0, d.devido - COALESCE(p_gozado_min, 0)) > 0)
  )
  FROM (SELECT public.ponto_intervalo_minimo_faixa(p_jornada_min) AS devido) d;
$$;

COMMENT ON FUNCTION public.ponto_supressao_intervalo(integer, integer) IS
  'Supressao de intervalo (CLT art. 71 §4º pos-2017): minutos devidos (pela faixa), gozados, suprimidos e a indenizacao de 50% sobre os suprimidos, natureza indenizatoria (sem reflexos).';

-- (061) Detecção na consolidação: grava os minutos suprimidos e alerta --------
CREATE OR REPLACE FUNCTION public.ponto_diario_supressao_intervalo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_jornada   int;
  v_gozado    int;
  v_suprimido int;
BEGIN
  v_jornada := COALESCE(floor(EXTRACT(EPOCH FROM NEW.horas_trabalhadas)/60)::int, 0);

  IF NEW.saida_almoco IS NOT NULL AND NEW.retorno_almoco IS NOT NULL THEN
    v_gozado := GREATEST(0, floor(EXTRACT(EPOCH FROM (NEW.retorno_almoco - NEW.saida_almoco))/60)::int);
  ELSE
    v_gozado := 0;
  END IF;

  v_suprimido := (public.ponto_supressao_intervalo(v_jornada, v_gozado)->>'minutos_suprimidos')::int;
  NEW.he_intervalo_suprimido_minutos := v_suprimido;

  -- Sinaliza a supressao (parcial ou total). Idempotente por colaborador/dia.
  IF v_suprimido > 0 AND NEW.tenant_id IS NOT NULL THEN
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id::text,
           NEW.colaborador_nome, NEW.colaborador_cpf,
           'intervalo_suprimido', 'alta',
           CASE WHEN v_gozado = 0 THEN 'Intervalo intrajornada nao usufruido (supressao total)'
                ELSE 'Intervalo intrajornada suprimido (parcial)' END,
           format('Jornada de %s min com %s min de pausa: %s min de intervalo suprimidos '
               || '(art. 71). Indenizacao de 50%% sobre os minutos suprimidos, natureza '
               || 'indenizatoria. Regularizar antes do fechamento.',
               v_jornada, v_gozado, v_suprimido),
           NEW.data
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = NEW.tenant_id
        AND a.colaborador_cpf = NEW.colaborador_cpf
        AND a.tipo = 'intervalo_suprimido'
        AND a.data_referencia = NEW.data
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_diario_supressao_intervalo ON public.ponto_diario;
CREATE TRIGGER trg_ponto_diario_supressao_intervalo
  BEFORE INSERT OR UPDATE ON public.ponto_diario
  FOR EACH ROW EXECUTE FUNCTION public.ponto_diario_supressao_intervalo();

COMMENT ON FUNCTION public.ponto_diario_supressao_intervalo() IS
  'Na consolidacao do dia: grava he_intervalo_suprimido_minutos e alerta o RH quando ha supressao de intervalo (parcial ou total). Idempotente por colaborador/dia. CLT art. 71.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | 60 | 0 | OK
--   funcao_existe   : t   (ponto_supressao_intervalo)
--   gatilho_existe  : t   (deteccao na consolidacao)
--   supr_total      : 60  (8h30 sem pausa suprime 60 min)
--   supr_normal     : 0   (8h com 60min de pausa nao suprime)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_supressao_intervalo(integer,integer)') IS NOT NULL) AS funcao_existe,
  (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_diario_supressao_intervalo'
     AND tgrelid='public.ponto_diario'::regclass AND NOT tgisinternal)) AS gatilho_existe,
  (public.ponto_supressao_intervalo(510,0)->>'minutos_suprimidos')::int AS supr_total,
  (public.ponto_supressao_intervalo(480,60)->>'minutos_suprimidos')::int AS supr_normal,
  CASE
    WHEN to_regprocedure('public.ponto_supressao_intervalo(integer,integer)') IS NOT NULL
     AND (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_diario_supressao_intervalo'
            AND tgrelid='public.ponto_diario'::regclass AND NOT tgisinternal))
     AND (public.ponto_supressao_intervalo(510,0)->>'minutos_suprimidos')::int = 60
     AND (public.ponto_supressao_intervalo(480,60)->>'minutos_suprimidos')::int = 0
      THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda4_pre_assinalacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 4 (parte 3): pré-assinalação formal do intervalo
-- Alvos: tabela ponto_pre_assinalacao; colunas ponto_diario.intervalo_origem /
--        intervalo_pre_assinalado_minutos; ponto_pre_assinalacao_do_dia();
--        gatilho ponto_diario_pre_assinalacao; ajuste no gatilho de supressão.
-- PONTO-064
--
-- O QUE FAZ (Súmula 338, III/TST; Portaria MTP 671/2021) — DESLIGADO por padrão
--   A jornada de duas batidas só é válida com intervalo EXPRESSAMENTE
--   pré-assinalado. Passa a existir a DECLARAÇÃO formal (por escala ou por
--   colaborador, com vigência e lastro), o espelho passa a exibir se o intervalo
--   do dia veio de batida real ou de pré-assinalação, e a supressão (parte 2)
--   deixa de acusar falsa "supressão total" num dia legitimamente pré-assinalado.
--
-- GARANTIAS
--   · Sem declaração cadastrada, nada muda: intervalo_origem fica 'marcado'
--     (dia com almoço batido) ou NULL, e a supressão fica idêntica à parte 2.
--   · NÃO altera ponto_marcacoes, horas_trabalhadas nem o motor de saldo — a
--     dedução do intervalo na apuração segue exatamente como já era.
--   · Batida real SEMPRE vence o declarado.
--
-- Depende das partes 1 e 2 (faixas e supressão, #16/#17). Aditivo, idempotente,
-- sem backfill. Um único gatilho de ponto_diario é (re)criado; a tabela nova
-- nasce vazia (sem contenção), então não há risco de deadlock entre tabelas.
-- ============================================================================
SET lock_timeout = '10s';

-- (2) Colunas de origem do intervalo no espelho ------------------------------
ALTER TABLE public.ponto_diario
  ADD COLUMN IF NOT EXISTS intervalo_origem text;
ALTER TABLE public.ponto_diario
  ADD COLUMN IF NOT EXISTS intervalo_pre_assinalado_minutos integer;

COMMENT ON COLUMN public.ponto_diario.intervalo_origem IS
  'Origem do intervalo intrajornada do dia: ''marcado'' (almoco batido) ou ''pre_assinalado'' (intervalo declarado, sem batida). NULL quando nao se aplica. Metadado de exibicao — o motor de saldo nao le.';
COMMENT ON COLUMN public.ponto_diario.intervalo_pre_assinalado_minutos IS
  'Minutos do intervalo pre-assinalado aplicado ao dia (quando intervalo_origem = ''pre_assinalado''). Metadado de exibicao.';

-- (1) Tabela da declaração formal --------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_pre_assinalacao (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  empresa_id        uuid,
  escala_id         uuid,              -- alvo por escala (amplo)
  colaborador_cpf   text,              -- alvo por colaborador (prevalece sobre a escala)
  intervalo_minutos integer NOT NULL,  -- minutos de intervalo pre-assinalados
  intervalo_inicio  time,              -- janela declarada (opcional)
  intervalo_fim     time,
  data_inicio       date NOT NULL,     -- vigencia
  data_fim          date,              -- NULL = vigente por prazo indeterminado
  lastro            text NOT NULL,     -- fundamento (CCT, acordo, politica interna)
  observacao        text,
  ativa             boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_pre_assinalacao_alvo_chk
    CHECK (escala_id IS NOT NULL OR colaborador_cpf IS NOT NULL),
  CONSTRAINT ponto_pre_assinalacao_minutos_chk
    CHECK (intervalo_minutos >= 0),
  CONSTRAINT ponto_pre_assinalacao_vigencia_chk
    CHECK (data_fim IS NULL OR data_fim >= data_inicio),
  CONSTRAINT ponto_pre_assinalacao_janela_chk
    CHECK (intervalo_inicio IS NULL OR intervalo_fim IS NULL OR intervalo_fim > intervalo_inicio)
);

CREATE INDEX IF NOT EXISTS idx_ponto_pre_assinalacao_escala
  ON public.ponto_pre_assinalacao (tenant_id, escala_id, data_inicio);
CREATE INDEX IF NOT EXISTS idx_ponto_pre_assinalacao_cpf
  ON public.ponto_pre_assinalacao (tenant_id, colaborador_cpf, data_inicio);

COMMENT ON TABLE public.ponto_pre_assinalacao IS
  'Declaracao formal do intervalo intrajornada pre-assinalado (Sumula 338/TST; Portaria MTP 671/2021), por escala ou por colaborador, com vigencia e lastro. Base da validade da jornada de duas batidas.';

ALTER TABLE public.ponto_pre_assinalacao ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_pre_assinalacao'
         AND policyname='ponto_pre_assinalacao_tenant') THEN
    CREATE POLICY ponto_pre_assinalacao_tenant
      ON public.ponto_pre_assinalacao
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- Trava do cercado do QA (isolamento de tenant): toda tabela do modulo com
-- tenant_id precisa dela (a rotina PONTO-270 acusa quando falta).
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_pre_assinalacao'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_pre_assinalacao
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_pre_assinalacao', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_pre_assinalacao');

-- (3) Resolução da declaração vigente no dia ---------------------------------
CREATE OR REPLACE FUNCTION public.ponto_pre_assinalacao_do_dia(
  p_tenant_id       uuid,
  p_cpf             text,
  p_colaborador_id  text,
  p_data            date
)
RETURNS TABLE(
  aplica            boolean,
  intervalo_minutos integer,
  intervalo_inicio  time,
  intervalo_fim     time,
  lastro            text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf       text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_escala_id uuid;
  r           RECORD;
BEGIN
  -- Escala vigente do colaborador no dia (mesma logica das demais rotinas).
  SELECT a.escala_id INTO v_escala_id
  FROM public.ponto_escala_atribuicoes a
  WHERE a.tenant_id = p_tenant_id
    AND (regexp_replace(COALESCE(a.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf
         OR a.colaborador_id::text = p_colaborador_id)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data
    AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC
  LIMIT 1;

  -- Declaracao vigente: a especifica do colaborador prevalece sobre a da escala.
  SELECT pa.intervalo_minutos, pa.intervalo_inicio, pa.intervalo_fim, pa.lastro
    INTO r
  FROM public.ponto_pre_assinalacao pa
  WHERE pa.tenant_id = p_tenant_id
    AND COALESCE(pa.ativa, true) = true
    AND pa.data_inicio <= p_data
    AND (pa.data_fim IS NULL OR pa.data_fim >= p_data)
    AND (
      (pa.colaborador_cpf IS NOT NULL
        AND regexp_replace(pa.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf)
      OR (pa.colaborador_cpf IS NULL AND pa.escala_id IS NOT NULL
        AND pa.escala_id = v_escala_id)
    )
  ORDER BY (pa.colaborador_cpf IS NOT NULL) DESC,  -- especifica primeiro
           pa.data_inicio DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;  -- sem declaracao: nenhuma linha (o chamador trata como "nao aplica")
  END IF;

  aplica            := true;
  intervalo_minutos := r.intervalo_minutos;
  intervalo_inicio  := r.intervalo_inicio;
  intervalo_fim     := r.intervalo_fim;
  lastro            := r.lastro;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.ponto_pre_assinalacao_do_dia(uuid, text, text, date) IS
  'Resolve a pre-assinalacao vigente no dia (colaborador-especifica prevalece sobre a da escala). Retorna sem linha quando nao ha declaracao. Sumula 338/TST.';

-- (4) Consolidação: marca a origem do intervalo (real vence o declarado) ------
CREATE OR REPLACE FUNCTION public.ponto_diario_pre_assinalacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_aplica boolean;
  v_min    integer;
BEGIN
  -- Recalculado a cada consolidacao -> idempotente e sem acumular.
  NEW.intervalo_pre_assinalado_minutos := NULL;

  IF NEW.saida_almoco IS NOT NULL AND NEW.retorno_almoco IS NOT NULL THEN
    -- Batida real do almoco: real SEMPRE vence o declarado.
    NEW.intervalo_origem := 'marcado';
  ELSE
    v_aplica := false;
    SELECT p.aplica, p.intervalo_minutos INTO v_aplica, v_min
    FROM public.ponto_pre_assinalacao_do_dia(
           NEW.tenant_id, NEW.colaborador_cpf, NEW.colaborador_id::text, NEW.data) p;

    IF COALESCE(v_aplica, false) THEN
      NEW.intervalo_origem := 'pre_assinalado';
      NEW.intervalo_pre_assinalado_minutos := v_min;
    ELSE
      NEW.intervalo_origem := NULL;  -- desligado: nada declarado
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_diario_pre_assinalacao ON public.ponto_diario;
CREATE TRIGGER trg_ponto_diario_pre_assinalacao
  BEFORE INSERT OR UPDATE ON public.ponto_diario
  FOR EACH ROW EXECUTE FUNCTION public.ponto_diario_pre_assinalacao();

COMMENT ON FUNCTION public.ponto_diario_pre_assinalacao() IS
  'Na consolidacao: marca ponto_diario.intervalo_origem (''marcado'' quando ha almoco batido; ''pre_assinalado'' quando nao ha e existe declaracao vigente). Roda ANTES do gatilho de supressao. Nao altera horas_trabalhadas nem o saldo. Sumula 338/TST.';

-- (5) Supressão ciente da pré-assinalação (parte 2 ajustada) -----------------
CREATE OR REPLACE FUNCTION public.ponto_diario_supressao_intervalo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_jornada   int;
  v_gozado    int;
  v_suprimido int;
BEGIN
  v_jornada := COALESCE(floor(EXTRACT(EPOCH FROM NEW.horas_trabalhadas)/60)::int, 0);

  IF NEW.saida_almoco IS NOT NULL AND NEW.retorno_almoco IS NOT NULL THEN
    v_gozado := GREATEST(0, floor(EXTRACT(EPOCH FROM (NEW.retorno_almoco - NEW.saida_almoco))/60)::int);
  ELSE
    v_gozado := 0;
  END IF;

  -- Intervalo pre-assinalado vigente conta como gozado (Sumula 338/TST): o
  -- gatilho de pre-assinalacao roda antes e ja preencheu estes campos.
  IF v_gozado = 0 AND NEW.intervalo_origem = 'pre_assinalado' THEN
    v_gozado := COALESCE(NEW.intervalo_pre_assinalado_minutos, 0);
  END IF;

  v_suprimido := (public.ponto_supressao_intervalo(v_jornada, v_gozado)->>'minutos_suprimidos')::int;
  NEW.he_intervalo_suprimido_minutos := v_suprimido;

  -- Sinaliza a supressao (parcial ou total). Idempotente por colaborador/dia.
  IF v_suprimido > 0 AND NEW.tenant_id IS NOT NULL THEN
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT NEW.tenant_id, NEW.empresa_id, NEW.colaborador_id::text,
           NEW.colaborador_nome, NEW.colaborador_cpf,
           'intervalo_suprimido', 'alta',
           CASE WHEN v_gozado = 0 THEN 'Intervalo intrajornada nao usufruido (supressao total)'
                ELSE 'Intervalo intrajornada suprimido (parcial)' END,
           format('Jornada de %s min com %s min de pausa: %s min de intervalo suprimidos '
               || '(art. 71). Indenizacao de 50%% sobre os minutos suprimidos, natureza '
               || 'indenizatoria. Regularizar antes do fechamento.',
               v_jornada, v_gozado, v_suprimido),
           NEW.data
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = NEW.tenant_id
        AND a.colaborador_cpf = NEW.colaborador_cpf
        AND a.tipo = 'intervalo_suprimido'
        AND a.data_referencia = NEW.data
    );
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.ponto_diario_supressao_intervalo() IS
  'Na consolidacao do dia: grava he_intervalo_suprimido_minutos e alerta o RH quando ha supressao de intervalo (parcial ou total). Intervalo validamente pre-assinalado conta como gozado. Idempotente por colaborador/dia. CLT art. 71; Sumula 338/TST.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | t | t | OK
--   tabela_existe    : t   (ponto_pre_assinalacao)
--   colunas_espelho  : t   (intervalo_origem + intervalo_pre_assinalado_minutos)
--   funcao_resolve   : t   (ponto_pre_assinalacao_do_dia)
--   gatilho_pre      : t   (trg_ponto_diario_pre_assinalacao na ponto_diario)
--   pre_antes_supr   : t   (o gatilho de pre roda ANTES do de supressao)
--   cerca_e_supr     : t   (cerca do QA na tabela nova + supressao ciente da pre)
-- ---------------------------------------------------------------------------
WITH chk AS MATERIALIZED (
  SELECT
    (to_regclass('public.ponto_pre_assinalacao') IS NOT NULL) AS tabela_existe,
    (EXISTS (SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='ponto_diario'
         AND column_name='intervalo_origem')
     AND EXISTS (SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='ponto_diario'
         AND column_name='intervalo_pre_assinalado_minutos')) AS colunas_espelho,
    (to_regprocedure('public.ponto_pre_assinalacao_do_dia(uuid,text,text,date)') IS NOT NULL) AS funcao_resolve,
    (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_diario_pre_assinalacao'
       AND tgrelid='public.ponto_diario'::regclass AND NOT tgisinternal)) AS gatilho_pre,
    ('trg_ponto_diario_pre_assinalacao' < 'trg_ponto_diario_supressao_intervalo') AS pre_antes_supr,
    (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='qa_guarda_cercado'
       AND tgrelid='public.ponto_pre_assinalacao'::regclass AND NOT tgisinternal)
     AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='ponto_diario_supressao_intervalo'
       AND prosrc ILIKE '%pre_assinalado%')) AS cerca_e_supr
)
SELECT tabela_existe, colunas_espelho, funcao_resolve, gatilho_pre, pre_antes_supr, cerca_e_supr,
  CASE WHEN tabela_existe AND colunas_espelho AND funcao_resolve AND gatilho_pre
        AND pre_antes_supr AND cerca_e_supr
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM chk;



-- ############################################################
-- BLOCO: script_ponto_onda4_dsr.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 4 (parte 5): DSR e repouso semanal de 24h
-- Alvos: ponto_dsr_competencia; ponto_repouso_semanal_verificar;
--        ponto_repouso_semanal_monitorar
-- PONTO-132 / PONTO-133
--
-- Fecha a onda 4 com o repouso semanal, hoje ausente do calculo:
--   (132) DSR (Lei 605/1949): apuracao semanal de assiduidade que alimenta a
--         folha com o REFLEXO das horas extras sobre o repouso (Sumula 172) e a
--         PERDA do DSR por falta injustificada na semana (art. 6).
--   (133) Repouso semanal de 24 HORAS CONSECUTIVAS (CLT art. 67): sete dias
--         seguidos de trabalho sem esse repouso e violacao autonoma — verificacao
--         semanal + alerta ao gestor (idempotente).
--
-- Tres funcoes novas (duas somente-leitura e um monitor que so insere alertas,
-- idempotente). Aditivo e idempotente (CREATE OR REPLACE). Nada e chamado
-- automaticamente, sem gatilho em tabela quente, sem tocar no motor de saldo
-- nem em tabela com tenant_id (sem tabela nova = sem cerca). A folha e o espelho
-- consomem estas funcoes quando forem ligados. Sem backfill.
-- ============================================================================

-- (132) Apuração semanal do DSR: reflexo das HE + perda por falta -------------
CREATE OR REPLACE FUNCTION public.ponto_dsr_competencia(
  p_tenant_id       uuid,
  p_colaborador_cpf text,
  p_competencia     text
)
RETURNS TABLE(
  semana_inicio             date,
  semana_fim                date,
  dias_uteis_trabalhados    integer,
  he_semana_min             integer,
  reflexo_he_dsr_min        integer,
  teve_falta_injustificada  boolean,
  dsr_perdido               boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- DSR (Descanso Semanal Remunerado, Lei 605/1949): repouso semanal remunerado.
  -- Duas apuracoes semanais que alimentam a folha:
  --   (132a) REFLEXO das horas extras sobre o repouso (Sumula 172 do TST): a
  --          media das HE da semana entra no valor do DSR;
  --   (132b) PERDA do DSR por falta injustificada na semana (Lei 605/49 art. 6).
  -- Semana ISO (segunda a domingo), com o domingo como dia de repouso. Le os
  -- dias ja consolidados em ponto_diario.
  WITH dias AS (
    SELECT d.data,
           date_trunc('week', d.data)::date       AS semana,
           EXTRACT(ISODOW FROM d.data)::int        AS isodow,   -- 7 = domingo
           COALESCE(d.horas_extras_50_minutos, 0)
             + COALESCE(d.horas_extras_100_minutos, 0)          AS he_min,
           COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) AS trab_min,
           d.status,
           d.tipo_dia,
           d.observacao
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id
      AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND to_char(d.data, 'YYYY-MM') = p_competencia
  ),
  por_semana AS (
    SELECT semana                                             AS semana_inicio,
           (semana + 6)                                       AS semana_fim,
           COUNT(*) FILTER (WHERE isodow <= 6 AND trab_min > 0) AS dias_uteis_trab,
           COALESCE(SUM(he_min), 0)                            AS he_semana,
           bool_or(
             isodow <= 6
             AND status = 'falta'
             AND COALESCE(tipo_dia, '') NOT IN ('ferias','atestado','afastamento','feriado')
             AND COALESCE(observacao, '') NOT ILIKE '%atestado%'
             AND COALESCE(observacao, '') NOT ILIKE '%justific%'
           )                                                   AS teve_falta
    FROM dias
    GROUP BY semana
  )
  SELECT
    semana_inicio,
    semana_fim,
    dias_uteis_trab::int,
    he_semana::int,
    CASE WHEN dias_uteis_trab > 0
         THEN ROUND(he_semana::numeric / dias_uteis_trab)::int
         ELSE 0 END                          AS reflexo_he_dsr_min,
    COALESCE(teve_falta, false)              AS teve_falta_injustificada,
    COALESCE(teve_falta, false)              AS dsr_perdido
  FROM por_semana
  ORDER BY semana_inicio;
$$;

COMMENT ON FUNCTION public.ponto_dsr_competencia(uuid, text, text) IS
  'Apuracao semanal do DSR (Lei 605/49): reflexo das HE sobre o repouso (Sumula 172) e perda do DSR por falta injustificada (art. 6). Alimenta a folha. Semana ISO, somente leitura.';

-- (133) Verificação do repouso semanal de 24h consecutivas --------------------
CREATE OR REPLACE FUNCTION public.ponto_repouso_semanal_verificar(
  p_tenant_id       uuid,
  p_colaborador_cpf text,
  p_ini             date,
  p_fim             date
)
RETURNS TABLE(
  sequencia_inicio   date,
  sequencia_fim      date,
  dias_consecutivos  integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- CLT art. 67: a cada semana e devido repouso semanal de 24 HORAS
  -- CONSECUTIVAS. Sete dias seguidos de trabalho sem esse repouso semanal e
  -- violacao autonoma — devida ainda que tudo seja pago em dobro. Detecta as
  -- sequencias de dias trabalhados consecutivos com 7 ou mais dias (ilhas por
  -- descontinuidade de datas: dias consecutivos tem (data - row_number) constante).
  WITH trab AS (
    SELECT DISTINCT d.data
    FROM public.ponto_diario d
    WHERE d.tenant_id = p_tenant_id
      AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND d.data BETWEEN p_ini AND p_fim
      AND COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) > 0
  ),
  ilhas AS (
    SELECT data,
           data - (row_number() OVER (ORDER BY data))::int AS grupo
    FROM trab
  )
  SELECT MIN(data)   AS sequencia_inicio,
         MAX(data)   AS sequencia_fim,
         COUNT(*)::int AS dias_consecutivos
  FROM ilhas
  GROUP BY grupo
  HAVING COUNT(*) >= 7
  ORDER BY 1;
$$;

COMMENT ON FUNCTION public.ponto_repouso_semanal_verificar(uuid, text, date, date) IS
  'Detecta sequencias de 7+ dias trabalhados consecutivos sem repouso semanal de 24 horas consecutivas (CLT art. 67). Somente leitura.';

-- (133) Monitor: alerta o gestor sobre violacao do repouso semanal -----------
CREATE OR REPLACE FUNCTION public.ponto_repouso_semanal_monitorar(p_competencia text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_n   int  := 0;
  v_ins int;
  r     RECORD;
  s     RECORD;
BEGIN
  FOR r IN
    SELECT d.tenant_id,
           MAX(d.empresa_id::text)::uuid AS empresa_id,
           d.colaborador_cpf,
           MAX(d.colaborador_nome)    AS nome,
           MAX(d.colaborador_id::text) AS cid
    FROM public.ponto_diario d
    WHERE d.data BETWEEN v_ini AND v_fim
      AND d.tenant_id IS NOT NULL
    GROUP BY d.tenant_id, d.colaborador_cpf
  LOOP
    -- Alarga a janela em 6 dias para pegar a sequencia que cruza a virada do mes.
    FOR s IN
      SELECT * FROM public.ponto_repouso_semanal_verificar(
                      r.tenant_id, r.colaborador_cpf, v_ini - 6, v_fim)
    LOOP
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT r.tenant_id, r.empresa_id, r.cid, r.nome, r.colaborador_cpf,
             'repouso_semanal_art67', 'alta',
             'Sem repouso semanal de 24h (CLT art. 67)',
             format('%s dias trabalhados consecutivos (%s a %s) sem repouso semanal de 24 horas '
                 || 'consecutivas. Violacao autonoma do art. 67 — devida ainda que o trabalho seja '
                 || 'pago em dobro. Conceder o descanso semanal.',
                 s.dias_consecutivos, s.sequencia_inicio, s.sequencia_fim),
             s.sequencia_fim
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = r.tenant_id
          AND a.colaborador_cpf = r.colaborador_cpf
          AND a.tipo = 'repouso_semanal_art67'
          AND a.data_referencia = s.sequencia_fim
      );
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      v_n := v_n + v_ins;
    END LOOP;
  END LOOP;
  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_repouso_semanal_monitorar(text) IS
  'Varre a competencia e alerta o gestor sobre violacao do repouso semanal de 24h consecutivas (CLT art. 67). Idempotente por colaborador/sequencia. Retorna a quantidade de alertas novos.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   dsr_apuracao      : t  (132 — ponto_dsr_competencia)
--   repouso_verificar : t  (133 — ponto_repouso_semanal_verificar)
--   repouso_monitor   : t  (133 — ponto_repouso_semanal_monitorar)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_dsr_competencia(uuid,text,text)') IS NOT NULL)               AS dsr_apuracao,
  (to_regprocedure('public.ponto_repouso_semanal_verificar(uuid,text,date,date)') IS NOT NULL) AS repouso_verificar,
  (to_regprocedure('public.ponto_repouso_semanal_monitorar(text)') IS NOT NULL)               AS repouso_monitor,
  CASE
    WHEN to_regprocedure('public.ponto_dsr_competencia(uuid,text,text)') IS NOT NULL
     AND to_regprocedure('public.ponto_repouso_semanal_verificar(uuid,text,date,date)') IS NOT NULL
     AND to_regprocedure('public.ponto_repouso_semanal_monitorar(text)') IS NOT NULL
      THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda4_domingo_em_dobro.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 4 (parte 4): domingo trabalhado em dobro
-- Alvo: calcular_he_adicional_noturno_dia (substituição completa da função)
-- PONTO-130
--
-- O trabalho em DOMINGO (descanso semanal) sem folga compensatória é pago EM
-- DOBRO por INTEIRO — jornada normal inclusive — e não apenas o que excede a
-- jornada (Lei 605/1949, art. 9º; Súmula 146 do TST). O cálculo tratava o
-- domingo como mera hora extra 100%, dobrando só o excedente.
--
-- O QUE FAZ (mínimo e aditivo): quando o dia é DOMINGO trabalhado e o domingo
-- NÃO é dia de trabalho previsto na escala (é o repouso da semana), a jornada
-- trabalhada inteira vira 100% (dobra). Domingo previsto na escala (6x1 etc.)
-- já carrega o repouso noutro dia e cai no cálculo normal. Sem escala, o domingo
-- é o repouso padrão e a dobra vale.
--
-- GARANTIAS
--   · Só muda o domingo de repouso trabalhado — dia útil, sábado e domingo
--     previsto na escala ficam idênticos ao cálculo atual.
--   · Não toca no motor de saldo (ele lê horas_extras/horas_faltantes, não
--     horas_extras_100_minutos). O alerta do art. 59 segue igual.
--   · Substitui a função inteira (mantendo as partes 2 e 3 da onda 3: leitura
--     da jornada pela escala, HE sem truncar, adicional noturno prorrogado) —
--     a conferência abaixo confirma que esses marcos continuam no corpo.
--
-- LIMITAÇÃO CONHECIDA: escala legada sem dias_config (jornada fixa em todos os
-- dias) reporta o domingo como dia útil e não dobra — critério conservador.
-- Aditivo e idempotente (CREATE OR REPLACE). Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calcular_he_adicional_noturno_dia(p_colaborador_id uuid, p_data date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_diario RECORD;
  v_cct RECORD;
  v_jornada_diaria_min INTEGER := 480; -- 8h (fallback; a escala do vínculo tem prioridade)
  v_he50_pct NUMERIC := 50;
  v_he100_pct NUMERIC := 100;
  v_adn_pct NUMERIC := 20;
  v_noturno_inicio TIME := '22:00';
  v_noturno_fim TIME := '05:00';
  v_usa_hora_ficta BOOLEAN := true;
  v_he_limite_diario_min INTEGER := 120;
  v_he50 INTEGER := 0;
  v_he100 INTEGER := 0;
  v_adn_min INTEGER := 0;
  v_trab_min INTEGER := 0;
  v_dow INTEGER;
  v_empresa UUID;
  v_j_escala INTEGER;
  v_excesso INTEGER;
  v_domingo_dobra BOOLEAN := false;
BEGIN
  SELECT * INTO v_diario FROM public.ponto_diario
   WHERE colaborador_id = p_colaborador_id AND data = p_data
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_diario');
  END IF;

  v_empresa := v_diario.empresa_id;

  -- CCT vigente (se houver) prioriza acordo individual, depois ACT, depois CCT
  SELECT c.* INTO v_cct
    FROM public.ponto_cct_config c
   WHERE c.tenant_id = v_diario.tenant_id
     AND (c.vigencia_inicio IS NULL OR c.vigencia_inicio <= p_data)
     AND (c.vigencia_fim IS NULL OR c.vigencia_fim >= p_data)
   ORDER BY c.created_at DESC
   LIMIT 1;
  IF FOUND THEN
    v_jornada_diaria_min := COALESCE(v_cct.jornada_diaria_horas,8) * 60;
    v_he50_pct := COALESCE(v_cct.he_percentual_dia_util,50);
    v_he100_pct := COALESCE(v_cct.he_percentual_domingos,100);
    v_adn_pct := COALESCE(v_cct.adicional_noturno_percentual,20);
    v_noturno_inicio := COALESCE(v_cct.hora_noturna_inicio,'22:00'::time);
    v_noturno_fim := COALESCE(v_cct.hora_noturna_fim,'05:00'::time);
    v_usa_hora_ficta := COALESCE(v_cct.usa_hora_ficta,true);
    v_he_limite_diario_min := COALESCE(v_cct.he_limite_diario_min,120);
  END IF;

  -- (091) Jornada do dia pela ESCALA vigente do vínculo — tem prioridade sobre
  -- a CCT/8h fixas. Respeita o versionamento de parâmetros da onda 1 (a própria
  -- ponto_jornada_do_dia aplica o overlay). Sem escala com jornada para o dia,
  -- mantém-se o que a CCT/8h definiram acima.
  BEGIN
    SELECT j.jornada_min INTO v_j_escala
      FROM public.ponto_jornada_do_dia(v_diario.tenant_id, v_diario.colaborador_cpf,
                                       v_diario.colaborador_id::text, p_data) j;
    IF COALESCE(v_j_escala, 0) > 0 THEN
      v_jornada_diaria_min := v_j_escala;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_j_escala := NULL; -- qualquer falha na leitura da escala: mantém o fallback CCT/8h
  END;

  -- Total trabalhado em minutos (a partir das marcações entrada/saida)
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    v_trab_min := EXTRACT(EPOCH FROM (v_diario.saida::time - v_diario.entrada::time))/60;
    IF v_diario.saida_almoco IS NOT NULL AND v_diario.retorno_almoco IS NOT NULL THEN
      v_trab_min := v_trab_min - EXTRACT(EPOCH FROM (v_diario.retorno_almoco::time - v_diario.saida_almoco::time))/60;
    END IF;
  END IF;
  IF v_trab_min < 0 THEN v_trab_min := 0; END IF;

  v_dow := EXTRACT(DOW FROM p_data); -- 0=domingo

  -- (130) Domingo trabalhado como descanso semanal, sem folga
  -- compensatória: Lei 605/1949 art. 9º + Súmula 146 do TST -> a jornada
  -- trabalhada é paga EM DOBRO por inteiro (não só o que excede a jornada). Só
  -- vale quando o domingo NÃO é dia de trabalho previsto na escala — a escala
  -- 6x1 e afins já carregam o repouso noutro dia e caem no cálculo normal. Sem
  -- escala atribuída, o domingo é o repouso padrão da semana e a dobra vale.
  v_domingo_dobra := (v_dow = 0 AND v_trab_min > 0 AND COALESCE(v_j_escala, 0) = 0);

  -- (092) Horas extras: TODO o tempo que excede a jornada é apurado. O limite
  -- de 2h do art. 59 é norma de conduta, não de cálculo — não se trunca a
  -- apuração; apura-se tudo e sinaliza-se o excesso ao RH.
  IF v_trab_min > v_jornada_diaria_min THEN
    v_excesso := v_trab_min - v_jornada_diaria_min;
  ELSE
    v_excesso := 0;
  END IF;

  IF v_domingo_dobra THEN
    -- Jornada inteira em dobro (o eventual excedente também é do domingo).
    v_he100 := v_trab_min;
    v_he50  := 0;
  ELSIF v_excesso > 0 THEN
    IF v_dow = 0 THEN
      v_he100 := v_excesso;   -- domingo previsto na escala: excedente a 100%
    ELSE
      v_he50 := v_excesso;    -- dia útil / sábado: excedente a 50%
    END IF;
  END IF;

  -- Sinalização do excesso ao limite do art. 59 (sem deixar de apurar).
  -- Idempotente: um alerta por colaborador/dia.
  IF v_excesso > v_he_limite_diario_min THEN
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT v_diario.tenant_id, v_empresa, v_diario.colaborador_id::text,
           v_diario.colaborador_nome, v_diario.colaborador_cpf,
           'excesso_he_art59', 'alta',
           'Excesso ao limite de 2h extras (CLT art. 59)',
           format('Apuradas %s min de hora extra no dia, acima do limite de %s min do art. 59. '
               || 'O tempo foi apurado por inteiro (continua devido); regularizar o excesso.',
               v_excesso, v_he_limite_diario_min),
           p_data
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = v_diario.tenant_id
        AND a.colaborador_cpf = v_diario.colaborador_cpf
        AND a.data_referencia = p_data
        AND a.tipo = 'excesso_he_art59'
    );
  END IF;

  -- Adicional noturno: minutos trabalhados na janela 22h-05h
  -- Aproximação: se entrada < 05:00 OU saida > 22:00, calcula sobreposição da jornada bruta
  IF v_diario.entrada IS NOT NULL AND v_diario.saida IS NOT NULL THEN
    DECLARE
      v_e TIMESTAMP := (p_data::text || ' ' || v_diario.entrada::text)::timestamp;
      v_s TIMESTAMP := (p_data::text || ' ' || v_diario.saida::text)::timestamp;
      v_n_ini TIMESTAMP := (p_data::text || ' ' || v_noturno_inicio::text)::timestamp;
      v_n_fim TIMESTAMP := ((p_data + 1)::text || ' ' || v_noturno_fim::text)::timestamp;
      v_overlap_min INTEGER := 0;
      v_prorrog_min INTEGER := 0;
    BEGIN
      IF v_s < v_e THEN v_s := v_s + INTERVAL '1 day'; END IF;
      -- Parte estritamente noturna: minutos dentro da janela legal 22h-05h,
      -- convertidos pela hora ficta (52min30s) quando aplicavel.
      v_overlap_min := GREATEST(0,
        EXTRACT(EPOCH FROM (LEAST(v_s, v_n_fim) - GREATEST(v_e, v_n_ini)))/60
      )::INTEGER;
      v_adn_min := v_overlap_min;
      IF v_usa_hora_ficta AND v_adn_min > 0 THEN
        v_adn_min := ROUND(v_adn_min * 60.0 / 52.5);
      END IF;
      -- Súmula 60, II do TST: jornada cumprida integralmente no período noturno
      -- (entrada ate as 22h, cobrindo toda a janela) e prorrogada alem das 05h ->
      -- o adicional acompanha as horas prorrogadas. Criterio conservador: essas
      -- horas entram pelo tempo REAL (sem hora ficta, cuja aplicacao a prorrogacao
      -- e controvertida). A parte noturna acima ja levou a ficta.
      IF v_e <= v_n_ini AND v_s > v_n_fim THEN
        v_prorrog_min := GREATEST(0, EXTRACT(EPOCH FROM (v_s - v_n_fim))/60)::INTEGER;
        v_adn_min := v_adn_min + v_prorrog_min;
      END IF;
    END;
  END IF;

  UPDATE public.ponto_diario
     SET horas_extras_50_minutos = v_he50,
         horas_extras_100_minutos = v_he100,
         adicional_noturno_minutos = v_adn_min,
         updated_at = now()
   WHERE id = v_diario.id;

  RETURN jsonb_build_object(
    'ok', true,
    'he50_min', v_he50,
    'he100_min', v_he100,
    'adicional_noturno_min', v_adn_min,
    'percentual_he50', v_he50_pct,
    'percentual_he100', v_he100_pct,
    'percentual_adn', v_adn_pct,
    'domingo_dobra', v_domingo_dobra
  );
END;
$function$;

COMMENT ON FUNCTION public.calcular_he_adicional_noturno_dia(uuid, date) IS
  'Apura HE (50/100%), adicional noturno e a DOBRA de domingo trabalhado sem folga compensatoria (Lei 605/49 art. 9; Sumula 146). Domingo de repouso trabalhado -> jornada inteira a 100%; domingo previsto na escala -> calculo normal. CLT art. 59/73.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | t | OK
--   dobra_domingo       : t  (parte 4 — dobra do domingo de repouso)
--   le_jornada_escala   : t  (parte 2 preservada — lê ponto_jornada_do_dia)
--   nao_trunca_2h       : t  (parte 2 preservada — sem o corte LEAST)
--   sinaliza_excesso    : t  (parte 2 preservada — alerta do art. 59)
--   adicional_prorrogado: t  (parte 3 preservada — Súmula 60, II)
-- ---------------------------------------------------------------------------
WITH def AS (
  SELECT pg_get_functiondef(p.oid) AS src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'calcular_he_adicional_noturno_dia'
    AND pg_get_function_identity_arguments(p.oid) = 'p_colaborador_id uuid, p_data date'
  LIMIT 1
)
SELECT
  (position('v_domingo_dobra' in src) > 0)                        AS dobra_domingo,
  (position('ponto_jornada_do_dia' in src) > 0)                   AS le_jornada_escala,
  (position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0) AS nao_trunca_2h,
  (position('excesso_he_art59' in src) > 0)                       AS sinaliza_excesso,
  (position('v_prorrog_min' in src) > 0)                          AS adicional_prorrogado,
  CASE
    WHEN position('v_domingo_dobra' in src) > 0
     AND position('ponto_jornada_do_dia' in src) > 0
     AND position('LEAST(v_trab_min - v_jornada_diaria_min' in src) = 0
     AND position('excesso_he_art59' in src) > 0
     AND position('v_prorrog_min' in src) > 0
      THEN 'OK'
    ELSE 'PENDENTE: corpo inesperado — conferir'
  END                                                             AS erro_tecnico
FROM def;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_intervalo_minimo_faixa', NULL),
    ('funcao', 'ponto_supressao_intervalo', NULL),
    ('funcao', 'ponto_diario_supressao_intervalo', NULL),
    ('funcao', 'ponto_pre_assinalacao_do_dia', NULL),
    ('funcao', 'ponto_diario_pre_assinalacao', NULL),
    ('funcao', 'ponto_dsr_competencia', NULL),
    ('funcao', 'ponto_repouso_semanal_verificar', NULL),
    ('funcao', 'ponto_repouso_semanal_monitorar', 'Sem repouso semanal de 24h (CLT art. 67)'),
    ('funcao', 'calcular_he_adicional_noturno_dia', 'Excesso ao limite de 2h extras (CLT art. 59)'),
    ('tabela', 'ponto_pre_assinalacao', NULL),
    ('gatilho', 'trg_ponto_diario_supressao_intervalo', NULL),
    ('gatilho', 'trg_ponto_diario_pre_assinalacao', NULL),
    ('indice', 'idx_ponto_pre_assinalacao_escala', NULL),
    ('indice', 'idx_ponto_pre_assinalacao_cpf', NULL),
    ('coluna', 'ponto_diario.intervalo_origem', NULL),
    ('coluna', 'ponto_diario.intervalo_pre_assinalado_minutos', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
