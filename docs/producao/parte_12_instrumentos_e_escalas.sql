-- ============================================================================
-- PRODUCAO — PONTO, PARTE 12 de 16
--
-- ANTES DE COLAR ESTA PARTE
--   * o RETRATO (passo_00_retrato_antes.sql) ja tem de ter sido tirado;
--   * as partes anteriores ja tem de ter sido aplicadas, nesta ordem, cada uma
--     com a conferencia terminando em OK.
--
-- ONDE COLAR
-- No SQL Editor do projeto de PRODUCAO. Execute o arquivo INTEIRO, uma vez.
-- Pode rodar de novo sem risco: e idempotente.
--
-- CONTEUDO
-- Identico ao que foi aplicado e conferido na homologacao, onde a bateria do
-- Ponto fechou em 133 passou / 1 falhou / 0 erro.
--
-- AO FINAL
-- Sai UMA conferencia com duas partes: as pecas que chegaram e o VOLUME —
-- quantas linhas das tabelas vivas do Ponto mudaram de quantidade. Nesta parte o esperado e ZERO.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (inicio) — a contagem de agora fica guardada para a
-- conferencia do fim comparar. Tabela propria, que nenhum sistema le.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_entrega_volume (
  parte          integer NOT NULL,
  tabela         text    NOT NULL,
  linhas_antes   bigint  NOT NULL,
  linhas_depois  bigint,
  marca_antes    text,
  marca_depois   text,
  medido_em      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parte, tabela)
);

-- Para a tabela criada por uma versao anterior desta fila continuar servindo.
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_antes  text;
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_depois text;

-- Tabela nova em public fica exposta pela API do Supabase. Esta nao tem dado
-- pessoal, mas tambem nao e da conta de ninguem: RLS ligada e sem politica.
ALTER TABLE public.ponto_entrega_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_entrega_volume FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_entrega_volume FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base.';
END $fechadura$;

DO $volume$
DECLARE
  t text;
  n bigint;
  m text;
BEGIN
  DELETE FROM public.ponto_entrega_volume WHERE parte = 12;
  FOREACH t IN ARRAY ARRAY['ponto_diario', 'ponto_marcacoes', 'ponto_espelhos', 'ponto_banco_horas', 'ponto_alertas', 'ponto_links', 'ponto_fechamentos', 'atestados']
  LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    m := NULL;
    -- A marca e a data da ultima alteracao registrada na tabela. Contagem
    -- pega linha criada ou apagada; a marca pega linha ALTERADA.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=t AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', t) INTO m;
    END IF;
    INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, marca_antes)
    VALUES (12, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda9_cct_vigencia.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 9: instrumento coletivo vigente NA competência (vigilância)
-- Alvo: nova função ponto_cct_vigiar_vigencia (leitura de ponto_cct_config)
-- PONTO-386
--
-- A apuração de horas (calcular_he_adicional_noturno_dia) JÁ escolhe o
-- instrumento coletivo cuja vigência cobre a DATA apurada — reapurar uma
-- competência antiga aplica a convenção da época (CF/88 art. 7º, XXVI). Faltava
-- a outra metade: ninguém avisa quando um instrumento vai vencer ou quando duas
-- vigências se sobrepõem. Sem isso, uma CCT vence sem renovação (competências
-- seguintes sem parâmetro) ou dois instrumentos disputam a mesma competência.
--
-- O QUE FAZ (aditivo): cria ponto_cct_vigiar_vigencia(tenant, empresa) —
-- gera alerta em ponto_alertas para (a) VENCIMENTO (60/30 dias/vencido) e
-- (b) SOBREPOSIÇÃO de vigências no mesmo escopo (empresa+categoria).
-- Idempotente; só lê ponto_cct_config e só escreve alertas. NÃO altera o motor
-- de saldo, o espelho nem o fechamento — a seleção por vigência na apuração fica
-- exatamente como está. Roda inteiro em UMA transação.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_cct_vigiar_vigencia(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n   integer := 0;
  v_ins integer;
BEGIN
  -- (a) VENCIMENTO do instrumento coletivo: 60 dias / 30 dias / já vencido.
  INSERT INTO public.ponto_alertas
    (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     tipo, severidade, titulo, descricao, data_referencia)
  SELECT c.tenant_id, c.empresa_id, NULL, NULL, NULL,
         'cct_vigencia_vencimento',
         CASE WHEN c.vigencia_fim <  CURRENT_DATE            THEN 'critica'
              WHEN c.vigencia_fim <= CURRENT_DATE + 30       THEN 'alta'
              ELSE 'media' END,
         CASE WHEN c.vigencia_fim <  CURRENT_DATE
                THEN format('Instrumento coletivo "%s" VENCIDO', c.nome)
              WHEN c.vigencia_fim <= CURRENT_DATE + 30
                THEN format('Instrumento coletivo "%s" a vencer em ate 30 dias', c.nome)
              ELSE format('Instrumento coletivo "%s" a vencer em ate 60 dias', c.nome) END,
         format('O instrumento coletivo "%s"%s tem vigencia ate %s. A apuracao usa o '
             || 'instrumento vigente NA competencia (CF art. 7, XXVI); sem renovacao, as '
             || 'competencias seguintes ficam sem parametro coletivo. Renovar o instrumento '
             || 'ou cadastrar o novo com a nova vigencia.',
             c.nome,
             COALESCE(' (' || c.sindicato || ')', ''),
             to_char(c.vigencia_fim, 'DD/MM/YYYY')),
         c.vigencia_fim
  FROM public.ponto_cct_config c
  WHERE c.tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR c.empresa_id = p_empresa_id)
    AND COALESCE(c.ativo, true) = true
    AND c.vigencia_fim IS NOT NULL
    AND c.vigencia_fim <= CURRENT_DATE + 60
    AND NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = c.tenant_id
        AND a.tipo = 'cct_vigencia_vencimento'
        AND a.data_referencia = c.vigencia_fim
        AND COALESCE(a.empresa_id::text, '') = COALESCE(c.empresa_id::text, '')
        AND a.titulo = (CASE WHEN c.vigencia_fim <  CURRENT_DATE
                    THEN format('Instrumento coletivo "%s" VENCIDO', c.nome)
                  WHEN c.vigencia_fim <= CURRENT_DATE + 30
                    THEN format('Instrumento coletivo "%s" a vencer em ate 30 dias', c.nome)
                  ELSE format('Instrumento coletivo "%s" a vencer em ate 60 dias', c.nome) END)
    );
  GET DIAGNOSTICS v_ins = ROW_COUNT;
  v_n := v_n + v_ins;

  -- (b) SOBREPOSICAO de vigencias no mesmo escopo (empresa + categoria).
  INSERT INTO public.ponto_alertas
    (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     tipo, severidade, titulo, descricao, data_referencia)
  SELECT c.tenant_id, c.empresa_id, NULL, NULL, NULL,
         'cct_vigencia_sobreposta', 'alta',
         format('Instrumentos coletivos com vigencias sobrepostas: "%s"', c.nome),
         format('O instrumento "%s" (vigencia %s a %s) se sobrepoe a outro instrumento '
             || 'ativo do mesmo escopo (empresa/categoria). Com vigencias sobrepostas, a '
             || 'apuracao fica ambigua sobre qual instrumento rege a competencia (CF art. 7, '
             || 'XXVI). Ajustar as vigencias para que cada competencia tenha um unico '
             || 'instrumento vigente.',
             c.nome,
             COALESCE(to_char(c.vigencia_inicio, 'DD/MM/YYYY'), 'aberta'),
             COALESCE(to_char(c.vigencia_fim,    'DD/MM/YYYY'), 'aberta')),
         COALESCE(c.vigencia_inicio, CURRENT_DATE)
  FROM public.ponto_cct_config c
  WHERE c.tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR c.empresa_id = p_empresa_id)
    AND COALESCE(c.ativo, true) = true
    AND EXISTS (
      SELECT 1 FROM public.ponto_cct_config o
      WHERE o.tenant_id = c.tenant_id
        AND o.id <> c.id
        AND COALESCE(o.ativo, true) = true
        AND COALESCE(o.empresa_id::text, '')            = COALESCE(c.empresa_id::text, '')
        AND COALESCE(o.categoria_profissional, '')      = COALESCE(c.categoria_profissional, '')
        AND COALESCE(c.vigencia_inicio, DATE '-infinity') <= COALESCE(o.vigencia_fim,    DATE 'infinity')
        AND COALESCE(o.vigencia_inicio, DATE '-infinity') <= COALESCE(c.vigencia_fim,    DATE 'infinity')
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = c.tenant_id
        AND a.tipo = 'cct_vigencia_sobreposta'
        AND a.titulo = format('Instrumentos coletivos com vigencias sobrepostas: "%s"', c.nome)
        AND COALESCE(a.empresa_id::text, '') = COALESCE(c.empresa_id::text, '')
    );
  GET DIAGNOSTICS v_ins = ROW_COUNT;
  v_n := v_n + v_ins;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ponto_cct_vigiar_vigencia(uuid, uuid) IS
  'Vigilancia da vigencia dos instrumentos coletivos (ponto_cct_config): alerta vencimento (60/30 dias/vencido) e sobreposicao de vigencias no mesmo escopo. Complementa a selecao por vigencia que a apuracao (calcular_he_adicional_noturno_dia) ja faz. Somente leitura de ponto_cct_config; idempotente. PONTO-386 (CF art. 7, XXVI).';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   vigilancia_ok : t (a funcao ponto_cct_vigiar_vigencia existe)
--   apuracao_ok   : t (a apuracao ja filtra por vigencia — ponto_cct_config)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_cct_vigiar_vigencia(uuid, uuid)') IS NOT NULL)  AS vigilancia_ok,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname='calcular_he_adicional_noturno_dia'
            AND p.prosrc ILIKE '%ponto_cct_config%' AND p.prosrc ILIKE '%vigencia%') AS apuracao_ok,
  CASE WHEN to_regprocedure('public.ponto_cct_vigiar_vigencia(uuid, uuid)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='calcular_he_adicional_noturno_dia'
                      AND p.prosrc ILIKE '%ponto_cct_config%' AND p.prosrc ILIKE '%vigencia%')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda10_escala_12x36_formalizacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 10 (parte 1): escala 12x36 só vale com acordo formal (ESC-001)
--
-- O art. 59-A da CLT condiciona a 12x36 a acordo individual ESCRITO, ACT ou CCT.
-- Hoje a 12x36 nasce ativa e é atribuída sem que nada cobre o acordo — as colunas
-- existem (ponto_escalas.acordo_individual_url, cct_act_url) e nenhuma função as lê.
--
-- O QUE FAZ (aditivo, NÃO bloqueia o cadastro): cria o verificador de formalização
-- da escala e um monitor que gera PENDÊNCIA (alerta) para toda 12x36 ativa sem
-- acordo formal (documento anexado ou coletivo act/cct vigente). Anexado o acordo,
-- a pendência deixa de ser gerada. Não altera o motor de saldo, a apuração do ciclo,
-- o espelho nem o fechamento. Idempotente. Roda inteiro em UMA transação.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_escala_formalizacao_status(p_escala_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  e         RECORD;
  v_tem_doc boolean;
  v_tem_col boolean;
BEGIN
  SELECT id, tenant_id, tipo, acordo_individual_url, cct_act_url
    INTO e
  FROM public.ponto_escalas
  WHERE id = p_escala_id;

  IF NOT FOUND THEN
    RETURN 'nao_se_aplica';
  END IF;

  IF COALESCE(e.tipo, '') <> '12x36' THEN
    RETURN 'nao_se_aplica';
  END IF;

  v_tem_doc := btrim(COALESCE(e.acordo_individual_url, '')) <> ''
            OR btrim(COALESCE(e.cct_act_url, '')) <> '';

  v_tem_col := EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id = e.tenant_id
      AND COALESCE(ac.ativo, false) = true
      AND ac.tipo IN ('act', 'cct')
      AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= CURRENT_DATE)
      AND (ac.vigencia_fim    IS NULL OR ac.vigencia_fim    >= CURRENT_DATE)
  );

  IF v_tem_doc OR v_tem_col THEN
    RETURN 'regular';
  END IF;

  RETURN 'pendente';
END;
$function$;

COMMENT ON FUNCTION public.ponto_escala_formalizacao_status(uuid) IS
  'Formalizacao da escala 12x36 (art. 59-A): le acordo_individual_url/cct_act_url e o coletivo vigente em ponto_acordos. Devolve regular | pendente | nao_se_aplica. ESC-001.';

CREATE OR REPLACE FUNCTION public.ponto_escala_formalizacao_monitorar(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_n   int := 0;
  v_ins int;
  esc   RECORD;
BEGIN
  FOR esc IN
    SELECT id, empresa_id, nome
    FROM public.ponto_escalas
    WHERE tenant_id = p_tenant_id
      AND COALESCE(tipo, '') = '12x36'
      AND COALESCE(ativa, true) = true
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
  LOOP
    IF public.ponto_escala_formalizacao_status(esc.id) = 'pendente' THEN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT p_tenant_id, esc.empresa_id, NULL, NULL, NULL,
             'escala_formalizacao_pendente', 'alta',
             'Escala 12x36 sem acordo formal (art. 59-A)',
             format('A escala "%s" e 12x36 e esta ativa, mas nao tem acordo formal anexado '
                 || '(acordo individual escrito, ACT ou CCT) nem coletivo vigente. O art. 59-A '
                 || 'da CLT condiciona a 12x36 a esse acordo; sem ele a jornada e invalida e '
                 || 'toda hora alem da 8a vira extra com reflexos. Anexe o acordo assinado e '
                 || 'arquive no modulo Documentos para regularizar. [escala:%s]',
                 COALESCE(esc.nome, '-'), esc.id),
             CURRENT_DATE
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = p_tenant_id
          AND a.tipo = 'escala_formalizacao_pendente'
          AND a.data_referencia = CURRENT_DATE
          AND a.descricao LIKE '%[escala:' || esc.id || ']%'
      );
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      v_n := v_n + v_ins;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ponto_escala_formalizacao_monitorar(uuid, uuid) IS
  'Gera pendencia (alerta) para 12x36 ativa sem acordo formal (art. 59-A). Idempotente por escala/dia. Nao bloqueia o cadastro. ESC-001.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK — o verificador e o monitor existem e leem o acordo.
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_escala_formalizacao_status(uuid)') IS NOT NULL)      AS verificador_ok,
  (to_regprocedure('public.ponto_escala_formalizacao_monitorar(uuid,uuid)') IS NOT NULL) AS monitor_ok,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_escala_formalizacao_status'
      AND (p.prosrc ILIKE '%acordo_individual_url%' OR p.prosrc ILIKE '%cct_act_url%')
  ) THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda10_escala_revezamento.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 10 (parte 2): revezamento — jornada de 6h, salvo coletivo (ESC-031)
--
-- O turno ininterrupto de revezamento tem jornada constitucional de 6h (CF art.
-- 7º, XIV); só a negociação coletiva amplia (STF: até 8h por CCT/ACT). Hoje o
-- revezamento não existe como conceito: a modalidade só conhece 'fixa'/'movel' e
-- nada valida as 6h.
--
-- O QUE FAZ (aditivo, NÃO bloqueia o cadastro): tipifica 'revezamento' na
-- modalidade e estende a formalização (mesmo fio do ESC-001) — revezamento acima
-- de 6h sem instrumento COLETIVO gera pendência/alerta. Não altera o motor de
-- saldo, a apuração, o espelho nem o fechamento. Idempotente. Roda em UMA transação.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.ponto_escalas DROP CONSTRAINT IF EXISTS ponto_escalas_modalidade_check;
ALTER TABLE public.ponto_escalas ADD CONSTRAINT ponto_escalas_modalidade_check
  CHECK (modalidade IS NULL OR modalidade = ANY (ARRAY['fixa'::text, 'movel'::text, 'revezamento'::text]));

CREATE OR REPLACE FUNCTION public.ponto_escala_formalizacao_status(p_escala_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  e         RECORD;
  v_tem_col boolean;
BEGIN
  SELECT id, tenant_id, tipo, modalidade, jornada_diaria_minutos,
         acordo_individual_url, cct_act_url
    INTO e
  FROM public.ponto_escalas
  WHERE id = p_escala_id;

  IF NOT FOUND THEN
    RETURN 'nao_se_aplica';
  END IF;

  v_tem_col := EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id = e.tenant_id
      AND COALESCE(ac.ativo, false) = true
      AND ac.tipo IN ('act', 'cct')
      AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= CURRENT_DATE)
      AND (ac.vigencia_fim    IS NULL OR ac.vigencia_fim    >= CURRENT_DATE)
  );

  IF COALESCE(e.tipo, '') = '12x36' THEN
    IF btrim(COALESCE(e.acordo_individual_url, '')) <> ''
       OR btrim(COALESCE(e.cct_act_url, '')) <> ''
       OR v_tem_col THEN
      RETURN 'regular';
    END IF;
    RETURN 'pendente';
  END IF;

  IF COALESCE(e.modalidade, '') = 'revezamento' THEN
    IF COALESCE(e.jornada_diaria_minutos, 0) <= 360 THEN
      RETURN 'regular';
    END IF;
    IF btrim(COALESCE(e.cct_act_url, '')) <> '' OR v_tem_col THEN
      RETURN 'regular';
    END IF;
    RETURN 'pendente';
  END IF;

  RETURN 'nao_se_aplica';
END;
$function$;

COMMENT ON FUNCTION public.ponto_escala_formalizacao_status(uuid) IS
  'Formalizacao da escala: 12x36 exige acordo (art. 59-A); revezamento acima de 6h exige instrumento COLETIVO (CF art. 7, XIV). Le acordo_individual_url/cct_act_url e o coletivo vigente. Devolve regular | pendente | nao_se_aplica. ESC-001/ESC-031.';

CREATE OR REPLACE FUNCTION public.ponto_escala_formalizacao_monitorar(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_n     int := 0;
  v_ins   int;
  esc     RECORD;
  v_tipo  text;
  v_tit   text;
  v_desc  text;
BEGIN
  FOR esc IN
    SELECT id, empresa_id, nome, tipo, modalidade, jornada_diaria_minutos
    FROM public.ponto_escalas
    WHERE tenant_id = p_tenant_id
      AND COALESCE(ativa, true) = true
      AND (COALESCE(tipo, '') = '12x36' OR COALESCE(modalidade, '') = 'revezamento')
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
  LOOP
    IF public.ponto_escala_formalizacao_status(esc.id) <> 'pendente' THEN
      CONTINUE;
    END IF;

    IF COALESCE(esc.tipo, '') = '12x36' THEN
      v_tipo := 'escala_formalizacao_pendente';
      v_tit  := 'Escala 12x36 sem acordo formal (art. 59-A)';
      v_desc := format('A escala "%s" e 12x36 e esta ativa, mas nao tem acordo formal anexado '
                 || '(acordo individual escrito, ACT ou CCT) nem coletivo vigente. O art. 59-A '
                 || 'da CLT condiciona a 12x36 a esse acordo; sem ele a jornada e invalida e '
                 || 'toda hora alem da 8a vira extra com reflexos. Anexe o acordo assinado e '
                 || 'arquive no modulo Documentos para regularizar. [escala:%s]',
                 COALESCE(esc.nome, '-'), esc.id);
    ELSE
      v_tipo := 'escala_revezamento_sem_coletivo';
      v_tit  := 'Revezamento acima de 6h sem instrumento coletivo (CF art. 7, XIV)';
      v_desc := format('A escala "%s" e de revezamento com jornada de %s min (acima de 6h) e nao '
                 || 'tem instrumento coletivo (CCT/ACT) que autorize a ampliacao. O turno '
                 || 'ininterrupto de revezamento tem jornada constitucional de 6h; so a '
                 || 'negociacao coletiva amplia (o STF admite ate 8h). Sem o coletivo, a 7a e a '
                 || '8a hora de todos os turnos viram extra. Anexe a CCT/ACT ou ajuste a jornada '
                 || 'para 6h. [escala:%s]',
                 COALESCE(esc.nome, '-'), COALESCE(esc.jornada_diaria_minutos, 0), esc.id);
    END IF;

    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT p_tenant_id, esc.empresa_id, NULL, NULL, NULL,
           v_tipo, 'alta', v_tit, v_desc, CURRENT_DATE
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = p_tenant_id
        AND a.tipo = v_tipo
        AND a.data_referencia = CURRENT_DATE
        AND a.descricao LIKE '%[escala:' || esc.id || ']%'
    );
    GET DIAGNOSTICS v_ins = ROW_COUNT;
    v_n := v_n + v_ins;
  END LOOP;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ponto_escala_formalizacao_monitorar(uuid, uuid) IS
  'Gera pendencia (alerta) para 12x36 sem acordo (art. 59-A) e revezamento acima de 6h sem coletivo (CF art. 7, XIV). Idempotente por escala/dia. Nao bloqueia o cadastro. ESC-001/ESC-031.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   modalidade_ok : a modalidade aceita 'revezamento'
--   status_ok     : o verificador menciona revezamento
--   monitor_ok    : o monitor existe
-- ---------------------------------------------------------------------------
SELECT
  (pg_get_constraintdef(c.oid) ILIKE '%revezamento%')                                    AS modalidade_ok,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='ponto_escala_formalizacao_status'
            AND p.prosrc ILIKE '%revezamento%')                                          AS status_ok,
  (to_regprocedure('public.ponto_escala_formalizacao_monitorar(uuid,uuid)') IS NOT NULL) AS monitor_ok,
  CASE WHEN (pg_get_constraintdef(c.oid) ILIKE '%revezamento%')
        AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ponto_escala_formalizacao_status'
                      AND p.prosrc ILIKE '%revezamento%')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM pg_constraint c
WHERE c.conrelid = 'public.ponto_escalas'::regclass
  AND c.conname = 'ponto_escalas_modalidade_check';



-- ############################################################
-- BLOCO: script_ponto_onda10_troca_turno.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 10 (parte 4): troca de turno com aprovação e recálculo (ESC-020)
-- Fecha a onda 10 (escalas).
--
-- Trocar o turno de dois colaboradores NÃO é editar duas linhas: precisa de
-- APROVAÇÃO (gestor), REGISTRO (quem trocou com quem, quando) e RECÁLCULO — a
-- interjornada de 11h (CLT art. 66) pode mudar para os dois. Cria a tabela
-- ponto_troca_turno (com trava do cercado e RLS por tenant) e o fluxo
-- solicitar → aprovar/recusar → efetivar, simulando a interjornada ANTES de
-- consumar e preservando o histórico de vigência das atribuições.
--
-- Não altera o motor de saldo, a apuração, o espelho nem o fechamento. Aditivo e
-- idempotente. Roda inteiro em UMA transação. SET lock_timeout na DDL.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.ponto_troca_turno (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL,
  empresa_id          uuid,
  atribuicao_a_id     uuid NOT NULL,
  colaborador_a_id    text,
  colaborador_a_nome  text,
  colaborador_a_cpf   text,
  atribuicao_b_id     uuid NOT NULL,
  colaborador_b_id    text,
  colaborador_b_nome  text,
  colaborador_b_cpf   text,
  data_troca          date NOT NULL,
  data_fim_troca      date,
  status              text NOT NULL DEFAULT 'solicitada'
                        CHECK (status IN ('solicitada','aprovada','efetivada','recusada','cancelada')),
  solicitante_id      uuid,
  solicitante_nome    text,
  motivo              text,
  aprovador_id        uuid,
  aprovador_nome      text,
  motivo_recusa       text,
  risco_interjornada  boolean NOT NULL DEFAULT false,
  risco_detalhe       text,
  solicitada_em       timestamptz NOT NULL DEFAULT now(),
  decidida_em         timestamptz,
  efetivada_em        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ponto_troca_turno IS
  'Troca de turno entre colaboradores: solicitacao, aprovacao (alcada) e efetivacao com recalculo. Simula interjornada (art. 66) antes de consumar. ESC-020.';

-- Trava do cercado do QA (isolamento de tenant) — PONTO-270.
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_troca_turno'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_troca_turno
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_troca_turno', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_troca_turno');

-- RLS por tenant (PONTO-250) — como toda tabela de ponto.
ALTER TABLE public.ponto_troca_turno ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_troca_turno'
         AND policyname='ponto_troca_turno_tenant') THEN
    CREATE POLICY ponto_troca_turno_tenant
      ON public.ponto_troca_turno
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- ── Solicitar: registra a troca e simula a interjornada dos dois ──
CREATE OR REPLACE FUNCTION public.ponto_troca_turno_solicitar(
  p_tenant_id        uuid,
  p_atribuicao_a_id  uuid,
  p_atribuicao_b_id  uuid,
  p_data_troca       date,
  p_data_fim_troca   date DEFAULT NULL,
  p_solicitante_id   uuid DEFAULT NULL,
  p_solicitante_nome text DEFAULT NULL,
  p_motivo           text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  a        RECORD;
  b        RECORD;
  ea       RECORD;
  eb       RECORD;
  v_gap_a  numeric;
  v_gap_b  numeric;
  v_risco  boolean := false;
  v_det    text := '';
  v_id     uuid;
BEGIN
  SELECT * INTO a FROM public.ponto_escala_atribuicoes WHERE id = p_atribuicao_a_id AND tenant_id = p_tenant_id;
  SELECT * INTO b FROM public.ponto_escala_atribuicoes WHERE id = p_atribuicao_b_id AND tenant_id = p_tenant_id;
  IF a.id IS NULL OR b.id IS NULL THEN
    RAISE EXCEPTION 'Atribuicao de escala nao encontrada para a troca (A=%, B=%).', p_atribuicao_a_id, p_atribuicao_b_id
      USING ERRCODE = 'raise_exception';
  END IF;

  SELECT id, empresa_id, hora_entrada_padrao, hora_saida_padrao INTO ea FROM public.ponto_escalas WHERE id = a.escala_id;
  SELECT id, hora_entrada_padrao, hora_saida_padrao INTO eb FROM public.ponto_escalas WHERE id = b.escala_id;

  IF ea.hora_saida_padrao IS NOT NULL AND eb.hora_entrada_padrao IS NOT NULL THEN
    v_gap_a := (24 - (EXTRACT(hour FROM ea.hora_saida_padrao) + EXTRACT(minute FROM ea.hora_saida_padrao)/60.0))
             + (EXTRACT(hour FROM eb.hora_entrada_padrao) + EXTRACT(minute FROM eb.hora_entrada_padrao)/60.0);
    IF v_gap_a < 11 THEN
      v_risco := true;
      v_det := v_det || format('Colaborador A tem interjornada de %sh ao assumir o turno de B (min. 11h). ', round(v_gap_a,1));
    END IF;
  END IF;
  IF eb.hora_saida_padrao IS NOT NULL AND ea.hora_entrada_padrao IS NOT NULL THEN
    v_gap_b := (24 - (EXTRACT(hour FROM eb.hora_saida_padrao) + EXTRACT(minute FROM eb.hora_saida_padrao)/60.0))
             + (EXTRACT(hour FROM ea.hora_entrada_padrao) + EXTRACT(minute FROM ea.hora_entrada_padrao)/60.0);
    IF v_gap_b < 11 THEN
      v_risco := true;
      v_det := v_det || format('Colaborador B tem interjornada de %sh ao assumir o turno de A (min. 11h). ', round(v_gap_b,1));
    END IF;
  END IF;

  INSERT INTO public.ponto_troca_turno
    (tenant_id, empresa_id, atribuicao_a_id, colaborador_a_id, colaborador_a_nome, colaborador_a_cpf,
     atribuicao_b_id, colaborador_b_id, colaborador_b_nome, colaborador_b_cpf,
     data_troca, data_fim_troca, status, solicitante_id, solicitante_nome, motivo,
     risco_interjornada, risco_detalhe)
  VALUES
    (p_tenant_id, ea.empresa_id, a.id, a.colaborador_id, a.colaborador_nome, a.colaborador_cpf,
     b.id, b.colaborador_id, b.colaborador_nome, b.colaborador_cpf,
     p_data_troca, p_data_fim_troca, 'solicitada', p_solicitante_id, p_solicitante_nome, p_motivo,
     v_risco, NULLIF(btrim(v_det), ''))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.ponto_troca_turno_solicitar(uuid,uuid,uuid,date,date,uuid,text,text) IS
  'Solicita troca de turno entre duas atribuicoes de ponto_escala_atribuicoes, simulando a interjornada de 11h (art. 66) antes de consumar. ESC-020.';

CREATE OR REPLACE FUNCTION public.ponto_troca_turno_aprovar(
  p_troca_id uuid, p_aprovador_id uuid DEFAULT NULL, p_aprovador_nome text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_status text;
BEGIN
  UPDATE public.ponto_troca_turno
     SET status = 'aprovada', aprovador_id = p_aprovador_id, aprovador_nome = p_aprovador_nome, decidida_em = now()
   WHERE id = p_troca_id AND status = 'solicitada'
   RETURNING status INTO v_status;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Troca % nao esta em situacao solicitada (nao pode ser aprovada).', p_troca_id USING ERRCODE = 'raise_exception';
  END IF;
  RETURN v_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ponto_troca_turno_recusar(
  p_troca_id uuid, p_aprovador_id uuid DEFAULT NULL, p_aprovador_nome text DEFAULT NULL, p_motivo_recusa text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_status text;
BEGIN
  UPDATE public.ponto_troca_turno
     SET status = 'recusada', aprovador_id = p_aprovador_id, aprovador_nome = p_aprovador_nome,
         motivo_recusa = p_motivo_recusa, decidida_em = now()
   WHERE id = p_troca_id AND status = 'solicitada'
   RETURNING status INTO v_status;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Troca % nao esta em situacao solicitada (nao pode ser recusada).', p_troca_id USING ERRCODE = 'raise_exception';
  END IF;
  RETURN v_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ponto_troca_turno_efetivar(p_troca_id uuid)
RETURNS text
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  tr  RECORD;
  a   RECORD;
  b   RECORD;
  d0  date;
BEGIN
  SELECT * INTO tr FROM public.ponto_troca_turno WHERE id = p_troca_id;
  IF tr.id IS NULL THEN
    RAISE EXCEPTION 'Troca % nao encontrada.', p_troca_id USING ERRCODE = 'raise_exception';
  END IF;
  IF tr.status <> 'aprovada' THEN
    RAISE EXCEPTION 'Troca % precisa estar aprovada para ser efetivada (situacao atual: %).', p_troca_id, tr.status USING ERRCODE = 'raise_exception';
  END IF;

  SELECT * INTO a FROM public.ponto_escala_atribuicoes WHERE id = tr.atribuicao_a_id;
  SELECT * INTO b FROM public.ponto_escala_atribuicoes WHERE id = tr.atribuicao_b_id;
  IF a.id IS NULL OR b.id IS NULL THEN
    RAISE EXCEPTION 'Atribuicao original da troca nao existe mais.' USING ERRCODE = 'raise_exception';
  END IF;
  d0 := tr.data_troca;

  IF a.data_inicio < d0 THEN
    UPDATE public.ponto_escala_atribuicoes SET data_fim = d0 - 1 WHERE id = a.id;
  ELSE
    UPDATE public.ponto_escala_atribuicoes SET ativa = false WHERE id = a.id;
  END IF;
  IF b.data_inicio < d0 THEN
    UPDATE public.ponto_escala_atribuicoes SET data_fim = d0 - 1 WHERE id = b.id;
  ELSE
    UPDATE public.ponto_escala_atribuicoes SET ativa = false WHERE id = b.id;
  END IF;

  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
  VALUES
    (tr.tenant_id, b.escala_id, a.colaborador_id, a.colaborador_nome, a.colaborador_cpf, d0, tr.data_fim_troca, true),
    (tr.tenant_id, a.escala_id, b.colaborador_id, b.colaborador_nome, b.colaborador_cpf, d0, tr.data_fim_troca, true);

  IF tr.data_fim_troca IS NOT NULL THEN
    INSERT INTO public.ponto_escala_atribuicoes
      (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim, ativa)
    VALUES
      (tr.tenant_id, a.escala_id, a.colaborador_id, a.colaborador_nome, a.colaborador_cpf, tr.data_fim_troca + 1, NULL, true),
      (tr.tenant_id, b.escala_id, b.colaborador_id, b.colaborador_nome, b.colaborador_cpf, tr.data_fim_troca + 1, NULL, true);
  END IF;

  UPDATE public.ponto_troca_turno SET status = 'efetivada', efetivada_em = now() WHERE id = p_troca_id;
  RETURN 'efetivada';
END;
$function$;

COMMENT ON FUNCTION public.ponto_troca_turno_efetivar(uuid) IS
  'Efetiva a troca de turno em ponto_escala_atribuicoes de forma transacional, preservando o historico de vigencia (encerra as antigas, cria as cruzadas, restaura apos o periodo). ESC-020.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | 4 | OK
--   tabela_ok  : a tabela existe
--   rls_ok     : RLS ativa (PONTO-250)
--   policy_ok  : tem politica por tenant
--   n_funcoes  : as 4 funcoes do fluxo existem
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_troca_turno') IS NOT NULL) AS tabela_ok,
  (SELECT relrowsecurity FROM pg_class WHERE relname='ponto_troca_turno') AS rls_ok,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ponto_troca_turno') AS policy_ok,
  (to_regprocedure('public.ponto_troca_turno_solicitar(uuid,uuid,uuid,date,date,uuid,text,text)') IS NOT NULL)::int
  + (to_regprocedure('public.ponto_troca_turno_aprovar(uuid,uuid,text)') IS NOT NULL)::int
  + (to_regprocedure('public.ponto_troca_turno_recusar(uuid,uuid,text,text)') IS NOT NULL)::int
  + (to_regprocedure('public.ponto_troca_turno_efetivar(uuid)') IS NOT NULL)::int AS n_funcoes,
  CASE WHEN to_regclass('public.ponto_troca_turno') IS NOT NULL
        AND (SELECT relrowsecurity FROM pg_class WHERE relname='ponto_troca_turno')
        AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ponto_troca_turno')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda10_cobertura_turno.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 10 (parte 3): radar de cobertura de turno (ESC-021)
--
-- Um turno previsto sem colaborador disponível (quem estava atribuído entrou de
-- férias, se afastou ou foi desligado) precisa aparecer ANTES do dia. Hoje o
-- sistema tem os ingredientes (atribuições com vigência, afastamentos, férias,
-- desligamentos) e não os cruza.
--
-- O QUE FAZ (aditivo, somente leitura + alerta): projeta os próximos dias de cada
-- escala com atribuição vigente e acusa o dia em que TODOS os colaboradores
-- atribuídos estão indisponíveis — turno descoberto —, com alerta ao gestor.
-- Não bloqueia nada, não altera o motor de saldo, a apuração, o espelho nem o
-- fechamento. Idempotente. Roda inteiro em UMA transação.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_escala_cobertura_listar(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL,
  p_dias_a_frente integer DEFAULT 7
)
RETURNS TABLE(escala_id uuid, escala_nome text, empresa_id uuid, data_descoberta date, motivo text)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  WITH dias AS (
    SELECT (CURRENT_DATE + g)::date AS d
    FROM generate_series(1, GREATEST(1, LEAST(COALESCE(p_dias_a_frente, 7), 60))) AS g
  ),
  esc AS (
    SELECT e.id, e.nome, e.empresa_id
    FROM public.ponto_escalas e
    WHERE e.tenant_id = p_tenant_id
      AND COALESCE(e.ativa, true) = true
      AND (p_empresa_id IS NULL OR e.empresa_id = p_empresa_id)
      AND EXISTS (SELECT 1 FROM public.ponto_escala_atribuicoes a
                  WHERE a.escala_id = e.id AND COALESCE(a.ativa, true) = true)
  ),
  cobertura AS (
    SELECT e.id AS escala_id, e.nome, e.empresa_id, dd.d,
      (
           EXISTS (SELECT 1 FROM public.afastamentos af
                   WHERE af.tenant_id = p_tenant_id
                     AND af.colaborador_cpf = a.colaborador_cpf
                     AND COALESCE(af.status::text, '') <> 'encerrado'
                     AND af.data_inicio <= dd.d
                     AND (af.data_fim IS NULL OR af.data_fim >= dd.d))
        OR EXISTS (SELECT 1 FROM public.ferias_solicitacoes fs
                   WHERE fs.tenant_id = p_tenant_id
                     AND fs.colaborador_cpf = a.colaborador_cpf
                     AND fs.status ILIKE '%aprov%'
                     AND fs.data_inicio <= dd.d
                     AND (fs.data_fim IS NULL OR fs.data_fim >= dd.d))
        OR EXISTS (SELECT 1 FROM public.admissoes ad
                   WHERE ad.tenant_id = p_tenant_id
                     AND ad.cpf = a.colaborador_cpf
                     AND ad.status = 'desligado'
                     AND (ad.data_desligamento IS NULL OR ad.data_desligamento <= dd.d))
      ) AS indisponivel
    FROM esc e
    JOIN dias dd ON true
    JOIN public.ponto_escala_atribuicoes a
      ON a.escala_id = e.id
     AND COALESCE(a.ativa, true) = true
     AND a.data_inicio <= dd.d
     AND (a.data_fim IS NULL OR a.data_fim >= dd.d)
  )
  SELECT c.escala_id, c.nome, c.empresa_id, c.d,
         'Todos os colaboradores atribuidos ao turno estao indisponiveis (afastamento, ferias ou desligamento) neste dia.'::text
  FROM cobertura c
  GROUP BY c.escala_id, c.nome, c.empresa_id, c.d
  HAVING bool_and(c.indisponivel) = true
  ORDER BY c.d, c.nome;
$function$;

COMMENT ON FUNCTION public.ponto_escala_cobertura_listar(uuid, uuid, integer) IS
  'Radar de cobertura de turno: lista os dias em que uma escala com atribuicao vigente fica com TODOS os colaboradores indisponiveis (afastamento/ferias/desligamento) — turno descoberto. Somente leitura. ESC-021.';

CREATE OR REPLACE FUNCTION public.ponto_escala_cobertura_monitorar(
  p_tenant_id uuid,
  p_empresa_id uuid DEFAULT NULL,
  p_dias_a_frente integer DEFAULT 7
)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_n   int := 0;
  v_ins int;
  rec   RECORD;
BEGIN
  FOR rec IN
    SELECT * FROM public.ponto_escala_cobertura_listar(p_tenant_id, p_empresa_id, p_dias_a_frente)
  LOOP
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT p_tenant_id, rec.empresa_id, NULL, NULL, NULL,
           'escala_cobertura_descoberta', 'alta',
           'Turno descoberto previsto — escala sem colaborador disponivel',
           format('A escala "%s" tem turno previsto para %s sem nenhum colaborador disponivel: %s '
               || 'Projete a cobertura (troca de turno, hora extra combinada ou remanejamento) ANTES '
               || 'do dia — a virada de ultima hora costuma ser dobra de turno, que estoura a '
               || 'interjornada de 11h e a hora extra. [escala:%s]',
               COALESCE(rec.escala_nome, '-'), rec.data_descoberta, rec.motivo, rec.escala_id),
           rec.data_descoberta
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = p_tenant_id
        AND a.tipo = 'escala_cobertura_descoberta'
        AND a.data_referencia = rec.data_descoberta
        AND a.descricao LIKE '%[escala:' || rec.escala_id || ']%'
    );
    GET DIAGNOSTICS v_ins = ROW_COUNT;
    v_n := v_n + v_ins;
  END LOOP;

  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ponto_escala_cobertura_monitorar(uuid, uuid, integer) IS
  'Gera alerta ao gestor para cada turno descoberto previsto (escala com atribuicao vigente e todos os colaboradores indisponiveis no dia). Idempotente por escala/dia. ESC-021.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK — o listador e o monitor existem e falam de turno/cobertura.
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_escala_cobertura_listar(uuid,uuid,integer)') IS NOT NULL)   AS listador_ok,
  (to_regprocedure('public.ponto_escala_cobertura_monitorar(uuid,uuid,integer)') IS NOT NULL) AS monitor_ok,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='ponto_escala_cobertura_monitorar'
      AND p.prosrc ILIKE '%turno%' AND (p.prosrc ILIKE '%cobertura%' OR p.prosrc ILIKE '%descobert%')
  ) THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;


-- ============================================================================

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (fim) — a mesma contagem, agora depois da parte.
-- ---------------------------------------------------------------------
DO $volume2$
DECLARE
  v record;
  n bigint;
  m text;
BEGIN
  FOR v IN SELECT tabela FROM public.ponto_entrega_volume
            WHERE parte = 12 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 12 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_cct_vigiar_vigencia', 'ou cadastrar o novo com a nova vigencia.'),
    ('funcao', 'ponto_escala_formalizacao_status', NULL),
    ('funcao', 'ponto_escala_formalizacao_monitorar', NULL),
    ('funcao', 'ponto_troca_turno_solicitar', NULL),
    ('funcao', 'ponto_troca_turno_aprovar', NULL),
    ('funcao', 'ponto_troca_turno_recusar', NULL),
    ('funcao', 'ponto_troca_turno_efetivar', ', p_troca_id, tr.status USING ERRCODE = '),
    ('funcao', 'ponto_escala_cobertura_listar', NULL),
    ('funcao', 'ponto_escala_cobertura_monitorar', 'Turno descoberto previsto — escala sem colaborador disponivel'),
    ('tabela', 'ponto_troca_turno', NULL)
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
), volume AS MATERIALIZED (
  SELECT v.tabela, v.linhas_antes AS antes, COALESCE(v.linhas_depois, v.linhas_antes) AS agora,
         v.marca_antes, v.marca_depois
  FROM public.ponto_entrega_volume v
  WHERE v.parte = 12
)
SELECT 'peca faltando'::text AS o_que, tipo || ' ' || nome AS detalhe, 'FALTOU'::text AS situacao
FROM estado WHERE NOT presente
UNION ALL
SELECT 'volume', tabela || ': ' || antes || ' para ' || agora || ' linha(s)',
       CASE WHEN agora = antes THEN 'sem alteracao' ELSE 'MUDOU ' || (agora - antes) || ' linha(s)' END
FROM volume WHERE agora <> antes
UNION ALL
SELECT 'volume', tabela || ': conteudo alterado (ultima alteracao passou de '
       || COALESCE(marca_antes, '-') || ' para ' || COALESCE(marca_depois, '-') || ')',
       'CONFERIR — ou e movimento normal de cliente durante a execucao'
FROM volume WHERE marca_antes IS DISTINCT FROM marca_depois
  AND tabela <> ''
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar; '
         || COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0)::text
         || ' linha(s) de dado vivo alteradas',
       CASE
         WHEN (SELECT count(*) FROM estado WHERE NOT presente) > 0 THEN 'CONFERIR — falta peca'
         WHEN false THEN 'OK'
         WHEN COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0) > 0
           THEN 'CONFERIR — esta parte nao deveria alterar dado vivo'
         ELSE 'OK'
       END
ORDER BY 1 DESC, 2;
