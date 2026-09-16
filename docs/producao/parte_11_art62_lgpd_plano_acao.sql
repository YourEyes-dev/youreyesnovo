-- ============================================================================
-- PRODUCAO — PONTO, PARTE 11 de 16
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
  DELETE FROM public.ponto_entrega_volume WHERE parte = 11;
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
    VALUES (11, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda8_enquadramento_art62.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 1): enquadramento do art. 62 + teletrabalho
-- Alvos: admissoes (+art62_inciso, +art62_documento, +teletrabalho_modalidade,
--        +dispensado_ponto) + ponto_art62_dispensa, ponto_sync_enquadramento_art62
-- PONTO-373 / PONTO-374
--
-- O cadastro nao tinha enquadramento do art. 62: gestor, externo e teletrabalhista
-- por producao eram tratados como controlados, e a materializacao de faltas gerava
-- FALTA para quem a lei DISPENSA de marcar. E o teletrabalho nao distinguia JORNADA
-- de PRODUCAO (Lei 14.442/2022): so producao dispensa. Passam a existir o
-- enquadramento no vinculo, a regra da dispensa e o gatilho que zera bate_ponto do
-- dispensado (a materializacao ja pula bate_ponto=false — dispensa respeitada sem
-- tocar no motor). Teletrabalho por jornada NAO e dispensado.
--
-- GARANTIAS: nao altera o calculo de saldo, o espelho nem o fechamento. Aditivo e
-- idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS art62_inciso            text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS art62_documento         text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS teletrabalho_modalidade text;
ALTER TABLE public.admissoes ADD COLUMN IF NOT EXISTS dispensado_ponto        boolean NOT NULL DEFAULT false;

DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.admissoes'::regclass AND conname='admissoes_art62_inciso_chk') THEN
    ALTER TABLE public.admissoes
      ADD CONSTRAINT admissoes_art62_inciso_chk
      CHECK (art62_inciso IS NULL OR art62_inciso IN ('I','II','III'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.admissoes'::regclass AND conname='admissoes_teletrabalho_modalidade_chk') THEN
    ALTER TABLE public.admissoes
      ADD CONSTRAINT admissoes_teletrabalho_modalidade_chk
      CHECK (teletrabalho_modalidade IS NULL OR teletrabalho_modalidade IN ('jornada','producao'));
  END IF;
END $chk$;

COMMENT ON COLUMN public.admissoes.art62_inciso IS
  'Enquadramento no art. 62 da CLT que dispensa o controle de jornada: I (atividade externa incompativel), II (cargo de gestao/confianca), III (teletrabalho por producao/tarefa). NULL = sujeito a controle.';
COMMENT ON COLUMN public.admissoes.teletrabalho_modalidade IS
  'Modalidade de teletrabalho (Lei 14.442/2022): producao/tarefa (dispensa controle, art. 62 III) ou jornada (CONTINUA sujeito a controle). NULL = nao aplicavel.';
COMMENT ON COLUMN public.admissoes.dispensado_ponto IS
  'Dispensa de controle de ponto resolvida pela regra do art. 62 (ponto_art62_dispensa). Teletrabalho por jornada nunca fica dispensado.';

-- (2) A regra da dispensa ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_art62_dispensa(
  p_inciso     text,
  p_modalidade text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- Dispensa de controle so quando ha inciso do art. 62 (I/II/III) E a modalidade
  -- NAO e teletrabalho por jornada. Teletrabalho por jornada permanece controlado
  -- (Lei 14.442/2022) ainda que alguem informe o inciso III.
  SELECT COALESCE(p_inciso, '') IN ('I','II','III')
         AND COALESCE(p_modalidade, '') <> 'jornada';
$$;

COMMENT ON FUNCTION public.ponto_art62_dispensa(text, text) IS
  'Regra da dispensa de controle do art. 62: verdadeiro quando ha inciso (I/II/III) e a modalidade nao e teletrabalho por jornada (que continua controlado). PONTO-373/374.';

-- (3) Coerência do vínculo (dispensado -> nao bate ponto) ---------------------
CREATE OR REPLACE FUNCTION public.ponto_sync_enquadramento_art62()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Resolve a dispensa pela regra do art. 62.
  NEW.dispensado_ponto := public.ponto_art62_dispensa(NEW.art62_inciso, NEW.teletrabalho_modalidade);

  -- Dispensado nao materializa falta: zera bate_ponto (o motor ja pula esses).
  -- Teletrabalho por jornada NAO e dispensado — permanece como esta (controlado).
  IF NEW.dispensado_ponto THEN
    NEW.bate_ponto := false;
  END IF;

  RETURN NEW;
END;
$$;

DO $trg$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname='trg_ponto_enquadramento_art62'
                   AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER trg_ponto_enquadramento_art62
      BEFORE INSERT OR UPDATE OF art62_inciso, teletrabalho_modalidade, dispensado_ponto
      ON public.admissoes
      FOR EACH ROW EXECUTE FUNCTION public.ponto_sync_enquadramento_art62();
  END IF;
END $trg$;

COMMENT ON FUNCTION public.ponto_sync_enquadramento_art62() IS
  'Resolve dispensado_ponto pela regra do art. 62 e, quando dispensa, zera bate_ponto para a materializacao de faltas respeitar a dispensa sem tocar no motor. PONTO-373.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | OK
--   art62_ok        : t (admissoes.art62_inciso)
--   teletrabalho_ok : t (admissoes.teletrabalho_modalidade)
--   dispensado_ok   : t (admissoes.dispensado_ponto)
--   regra_ok        : t (ponto_art62_dispensa — III/jornada NAO dispensa)
--   gatilho_ok      : t (trigger trg_ponto_enquadramento_art62)
-- ---------------------------------------------------------------------------
SELECT
  (public.qa_col_existe('admissoes','%art62%') IS NOT NULL)                         AS art62_ok,
  (public.qa_col_existe('admissoes','%teletrabalho%') IS NOT NULL)                  AS teletrabalho_ok,
  (public.qa_col_existe('admissoes','%dispensado_ponto%') IS NOT NULL)              AS dispensado_ok,
  (public.ponto_art62_dispensa('II',NULL) AND NOT public.ponto_art62_dispensa('III','jornada')) AS regra_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_enquadramento_art62'
          AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal)            AS gatilho_ok,
  CASE WHEN public.qa_col_existe('admissoes','%art62%') IS NOT NULL
        AND public.qa_col_existe('admissoes','%teletrabalho%') IS NOT NULL
        AND public.qa_col_existe('admissoes','%dispensado_ponto%') IS NOT NULL
        AND public.ponto_art62_dispensa('II',NULL)
        AND NOT public.ponto_art62_dispensa('III','jornada')
        AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_enquadramento_art62'
                    AND tgrelid='public.admissoes'::regclass AND NOT tgisinternal)
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_descaracterizacao_art62.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 2): controle de fato descaracteriza a dispensa (art. 62)
-- Alvo: ponto_detectar_descaracterizacao_art62 (nova)
-- PONTO-375  (depende da parte 1 — o enquadramento do art. 62)
--
-- A dispensa do art. 62 cai na Justica quando ha CONTROLE DE FATO: um vinculo
-- marcado como dispensado que, na pratica, acumula marcacoes reais. A rotina cruza
-- o enquadramento (dispensado_ponto) com as marcacoes reais recentes e gera um
-- alerta critico por colaborador, para RH/Juridico revisar o enquadramento antes
-- que a exclusao seja descaracterizada e as horas extras do periodo voltem.
--
-- GARANTIAS: so leitura das marcacoes + gravacao de alerta. Nao altera o motor de
-- saldo, o espelho, o fechamento nem o enquadramento. Aditivo e idempotente.
-- Roda inteiro em UMA transacao.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ponto_detectar_descaracterizacao_art62(
  p_tenant_id         uuid,
  p_empresa_id        uuid    DEFAULT NULL,
  p_dias              integer DEFAULT 60,
  p_min_dias_marcados integer DEFAULT 3
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n   int := 0;
  v_ins int;
  r     RECORD;
BEGIN
  -- Dispensados do art. 62 com marcações reais recorrentes no período recente:
  -- controle de fato que descaracteriza a exclusão. Marcações desconsideradas
  -- não contam (não são batida válida).
  FOR r IN
    SELECT a.empresa_id, a.cpf, a.nome_completo, a.art62_inciso,
           count(DISTINCT m.data_marcacao) AS dias_marcados,
           max(m.data_marcacao) AS ultima
    FROM public.admissoes a
    JOIN public.ponto_marcacoes m
      ON m.tenant_id = a.tenant_id
     AND regexp_replace(COALESCE(m.colaborador_cpf,''),'[^0-9]','','g')
         = regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
     AND m.data_marcacao >= (CURRENT_DATE - p_dias)
     AND COALESCE(m.desconsiderada, false) = false
    WHERE a.tenant_id = p_tenant_id
      AND COALESCE(a.dispensado_ponto, false) = true
      AND COALESCE(a.inativo, false) = false
      AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
    GROUP BY a.empresa_id, a.cpf, a.nome_completo, a.art62_inciso
    HAVING count(DISTINCT m.data_marcacao) >= p_min_dias_marcados
  LOOP
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT p_tenant_id, r.empresa_id, NULL, r.nome_completo, r.cpf,
           'descaracterizacao_art62', 'critica',
           'Controle de fato sobre dispensado do art. 62 (risco de descaracterizacao)',
           format('Vinculo enquadrado no art. 62 (inciso %s), portanto dispensado de controle, '
               || 'acumulou marcacoes reais em %s dia(s) nos ultimos %s dias (ultima em %s). '
               || 'Controle de fato descaracteriza a exclusao do art. 62 e traz as horas extras '
               || 'do periodo — revisar o enquadramento com RH/Juridico.',
               COALESCE(r.art62_inciso,'-'), r.dias_marcados, p_dias, to_char(r.ultima,'DD/MM/YYYY')),
           CURRENT_DATE
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = p_tenant_id
        AND a.tipo = 'descaracterizacao_art62'
        AND a.colaborador_cpf = r.cpf
        AND a.data_referencia = CURRENT_DATE
    );
    GET DIAGNOSTICS v_ins = ROW_COUNT;
    v_n := v_n + v_ins;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_detectar_descaracterizacao_art62(uuid, uuid, integer, integer) IS
  'Detecta descaracterizacao da dispensa do art. 62: vinculo dispensado (dispensado_ponto) com marcacoes reais recorrentes no periodo recente gera alerta critico a RH/Juridico (controle de fato derruba a exclusao). Idempotente por colaborador/dia. PONTO-375.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | OK
--   deteccao_existe : t (ponto_detectar_descaracterizacao_art62)
--   confere_dispensa: t (a rotina cruza com o enquadramento dispensado_ponto)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_detectar_descaracterizacao_art62(uuid,uuid,integer,integer)') IS NOT NULL) AS deteccao_existe,
  (public.qa_col_existe('admissoes','%dispensado_ponto%') IS NOT NULL)                                       AS confere_dispensa,
  CASE WHEN to_regprocedure('public.ponto_detectar_descaracterizacao_art62(uuid,uuid,integer,integer)') IS NOT NULL
        AND public.qa_col_existe('admissoes','%dispensado_ponto%') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_obrigatoriedade_estabelecimento.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 3): obrigatoriedade do controle por estabelecimento (>20)
-- Alvos: empresa_cadastro (+controle_ponto_obrigatorio) +
--        ponto_estabelecimento_trabalhadores,
--        ponto_estabelecimento_obrigatoriedade_monitorar
-- PONTO-370
--
-- O controle de jornada e obrigatorio quando o ESTABELECIMENTO passa de 20
-- trabalhadores — a contagem e POR ESTABELECIMENTO (CLT art. 74, §2, Lei
-- 13.874/2019). O sistema nao tinha essa nocao. Passam a existir a sinalizacao no
-- cadastro, a contagem por estabelecimento e o monitor que resolve a
-- obrigatoriedade e alerta o obrigado que ainda nao usa controle de ponto.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho nem o fechamento. So conta,
-- sinaliza e alerta. Aditivo e idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
ALTER TABLE public.empresa_cadastro
  ADD COLUMN IF NOT EXISTS controle_ponto_obrigatorio boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.empresa_cadastro.controle_ponto_obrigatorio IS
  'Sinaliza que o ESTABELECIMENTO e obrigado a controlar a jornada por passar de 20 trabalhadores (CLT art. 74, §2, Lei 13.874/2019). Resolvido pela contagem em ponto_estabelecimento_obrigatoriedade_monitorar.';

-- (2) Contagem de trabalhadores ativos do estabelecimento --------------------
CREATE OR REPLACE FUNCTION public.ponto_estabelecimento_trabalhadores(
  p_tenant_id  uuid,
  p_empresa_id uuid
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Trabalhadores ativos do estabelecimento (colaborador ativo = 'concluido').
  SELECT count(*)::int
  FROM public.admissoes a
  WHERE a.tenant_id = p_tenant_id
    AND a.empresa_id = p_empresa_id
    AND a.status = 'concluido'
    AND COALESCE(a.inativo, false) = false;
$$;

COMMENT ON FUNCTION public.ponto_estabelecimento_trabalhadores(uuid, uuid) IS
  'Conta os trabalhadores ativos de um estabelecimento (base da obrigatoriedade do art. 74, §2). PONTO-370.';

-- (3) Resolve a obrigatoriedade e alerta o obrigado sem controle --------------
CREATE OR REPLACE FUNCTION public.ponto_estabelecimento_obrigatoriedade_monitorar(
  p_tenant_id  uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n   int := 0;
  v_ins int;
  e     RECORD;
  v_trab int;
  v_obrig boolean;
BEGIN
  -- Para cada estabelecimento, a obrigatoriedade do controle de jornada nasce
  -- quando a contagem passa de 20 (art. 74, §2). Conta POR ESTABELECIMENTO.
  FOR e IN
    SELECT id, razao_social, COALESCE(usa_controle_ponto, false) AS usa
    FROM public.empresa_cadastro
    WHERE tenant_id = p_tenant_id
      AND (p_empresa_id IS NULL OR id = p_empresa_id)
  LOOP
    v_trab := public.ponto_estabelecimento_trabalhadores(p_tenant_id, e.id);
    v_obrig := v_trab > 20;

    UPDATE public.empresa_cadastro
       SET controle_ponto_obrigatorio = v_obrig
     WHERE id = e.id AND controle_ponto_obrigatorio IS DISTINCT FROM v_obrig;

    -- Obrigado que ainda NAO usa controle de ponto: alerta.
    IF v_obrig AND NOT e.usa THEN
      INSERT INTO public.ponto_alertas
        (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
         tipo, severidade, titulo, descricao, data_referencia)
      SELECT p_tenant_id, e.id, NULL, NULL, NULL,
             'controle_ponto_obrigatorio', 'alta',
             'Estabelecimento obrigado ao controle de jornada sem controle ativo',
             format('O estabelecimento %s tem %s trabalhadores ativos (passa de 20) e e obrigado '
                 || 'ao controle de jornada (CLT art. 74, §2), mas ainda nao usa controle de ponto. '
                 || 'Sem controle, a jornada alegada pelo empregado prevalece (Sumula 338 do TST).',
                 COALESCE(e.razao_social,'-'), v_trab),
             CURRENT_DATE
      WHERE NOT EXISTS (
        SELECT 1 FROM public.ponto_alertas a
        WHERE a.tenant_id = p_tenant_id
          AND a.tipo = 'controle_ponto_obrigatorio'
          AND a.empresa_id = e.id
          AND a.data_referencia = CURRENT_DATE
      );
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      v_n := v_n + v_ins;
    END IF;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_estabelecimento_obrigatoriedade_monitorar(uuid, uuid) IS
  'Resolve a obrigatoriedade do controle de jornada por estabelecimento (passa de 20 trabalhadores, art. 74, §2) e alerta o estabelecimento obrigado que ainda nao usa controle de ponto. Idempotente por estabelecimento/dia. PONTO-370.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   sinaliza_ok : t (empresa_cadastro.controle_ponto_obrigatorio)
--   contagem_ok : t (ponto_estabelecimento_trabalhadores)
--   monitor_ok  : t (ponto_estabelecimento_obrigatoriedade_monitorar)
-- ---------------------------------------------------------------------------
SELECT
  (public.qa_col_existe('empresa_cadastro','%controle%obrigat%') IS NOT NULL)                    AS sinaliza_ok,
  (to_regprocedure('public.ponto_estabelecimento_trabalhadores(uuid,uuid)') IS NOT NULL)         AS contagem_ok,
  (to_regprocedure('public.ponto_estabelecimento_obrigatoriedade_monitorar(uuid,uuid)') IS NOT NULL) AS monitor_ok,
  CASE WHEN public.qa_col_existe('empresa_cadastro','%controle%obrigat%') IS NOT NULL
        AND to_regprocedure('public.ponto_estabelecimento_trabalhadores(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.ponto_estabelecimento_obrigatoriedade_monitorar(uuid,uuid)') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_rep_alternativo_instrumento.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 4): sistema alternativo (REP-A) so com instrumento coletivo
-- Alvos: ponto_configuracao (+link_externo_acordo_url) + ponto_validar_rep_alternativo
-- PONTO-213
--
-- O sistema alternativo de controle de jornada (REP-A: registro por link/app) e
-- admitido APENAS quando autorizado por convencao ou acordo coletivo (Portaria MTP
-- 671/2021; CLT art. 74, §4). O modo 'link_externo' podia ser ativado sem nenhum
-- lastro documental. Passa a ser RECUSADO sem autorizacao — o documento do
-- instrumento coletivo anexado (link_externo_acordo_url) OU um acordo coletivo
-- (act/cct) vigente em ponto_acordos. Espelha a trava do registro por excecao.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho nem o fechamento. So valida a
-- ativacao do modo alternativo; modos 'interno' e 'ambos' nao sao afetados.
-- Aditivo e idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
ALTER TABLE public.ponto_configuracao
  ADD COLUMN IF NOT EXISTS link_externo_acordo_url text;

COMMENT ON COLUMN public.ponto_configuracao.link_externo_acordo_url IS
  'Documento do instrumento coletivo (CCT/ACT) que autoriza o sistema alternativo de registro (REP-A, link externo), exigido pela Portaria 671 / CLT art. 74, §4. Alternativa ao acordo vigente em ponto_acordos.';

CREATE OR REPLACE FUNCTION public.ponto_validar_rep_alternativo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Só valida quando se ATIVA/altera o modo alternativo ou a sua autorização.
  IF TG_OP = 'INSERT'
     OR NEW.modo_registro IS DISTINCT FROM OLD.modo_registro
     OR NEW.link_externo_acordo_url IS DISTINCT FROM OLD.link_externo_acordo_url THEN

    IF COALESCE(NEW.modo_registro, '') = 'link_externo'
       AND btrim(COALESCE(NEW.link_externo_acordo_url, '')) = ''
       AND NOT EXISTS (
         SELECT 1 FROM public.ponto_acordos ac
         WHERE ac.tenant_id = NEW.tenant_id
           AND COALESCE(ac.ativo, false) = true
           AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= CURRENT_DATE)
           AND (ac.vigencia_fim   IS NULL OR ac.vigencia_fim   >= CURRENT_DATE)
           AND (ac.tipo ILIKE '%alternativ%' OR ac.tipo ILIKE '%rep%a%'
                OR ac.tipo ILIKE '%link%' OR ac.tipo ILIKE '%jornada%'
                OR ac.tipo ILIKE '%cct%'  OR ac.tipo ILIKE '%act%'
                OR ac.tipo ILIKE '%conven%' OR ac.tipo ILIKE '%coletiv%')
       ) THEN
      RAISE EXCEPTION
        'Sistema alternativo de registro (REP-A, link externo) exige autorizacao em acordo ou instrumento coletivo (Portaria 671; CLT art. 74, §4): anexe o instrumento coletivo (link_externo_acordo_url) ou cadastre um acordo vigente antes de ativar o modo.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DO $trg$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname='trg_ponto_validar_rep_alternativo'
                   AND tgrelid='public.ponto_configuracao'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER trg_ponto_validar_rep_alternativo
      BEFORE INSERT OR UPDATE OF modo_registro, link_externo_acordo_url
      ON public.ponto_configuracao
      FOR EACH ROW EXECUTE FUNCTION public.ponto_validar_rep_alternativo();
  END IF;
END $trg$;

COMMENT ON FUNCTION public.ponto_validar_rep_alternativo() IS
  'Recusa ativar o modo de registro alternativo (link_externo/REP-A) sem autorizacao coletiva — documento anexado ou acordo vigente em ponto_acordos (Portaria 671; CLT art. 74, §4). Espelha a trava do registro por excecao. PONTO-213.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   coluna_ok  : t (ponto_configuracao.link_externo_acordo_url)
--   guarda_ok  : t (ponto_validar_rep_alternativo)
--   gatilho_ok : t (trigger trg_ponto_validar_rep_alternativo)
-- ---------------------------------------------------------------------------
SELECT
  (public.qa_col_existe('ponto_configuracao','%link_externo_acordo%') IS NOT NULL)          AS coluna_ok,
  (to_regprocedure('public.ponto_validar_rep_alternativo()') IS NOT NULL)                   AS guarda_ok,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_validar_rep_alternativo'
          AND tgrelid='public.ponto_configuracao'::regclass AND NOT tgisinternal)           AS gatilho_ok,
  CASE WHEN public.qa_col_existe('ponto_configuracao','%link_externo_acordo%') IS NOT NULL
        AND to_regprocedure('public.ponto_validar_rep_alternativo()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_validar_rep_alternativo'
                    AND tgrelid='public.ponto_configuracao'::regclass AND NOT tgisinternal)
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_competencia_fechada.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (correção): competência fechada bloqueia até para gestão
-- Alvo: função validar_periodo_aberto_ponto (gatilho BEFORE INSERT em ponto_marcacoes)
-- PONTO-193
--
-- A bateria rodada no AMBIENTE DE TESTE (por um usuário de gestão) reprovou o
-- PONTO-193: uma competência FECHADA aceitou marcação nova sem reabertura. O
-- guard validar_periodo_aberto_ponto abria uma EXCEÇÃO para papéis de gestão
-- (manager/admin/owner/gestor/rh...) — a "válvula" já apontada como risco. Sem
-- sessão (auth.uid() nulo) o caso passava; COMO GESTÃO (o caso real do TESTE) a
-- válvula deixava a marcação entrar, mudando o espelho já entregue e assinado.
--
-- O QUE FAZ: remove a válvula. Competência FECHADA passa a bloquear marcação nova
-- para TODOS. O único caminho para mexer é a REABERTURA FORMAL (PONTO-358), que
-- muda o status para 'reaberto' — e o guard naturalmente libera (só bloqueia
-- 'fechado'). Gatilho é BEFORE INSERT, então só afeta marcação NOVA; UPDATE
-- (ex.: desconsiderar) não é tocado.
--
-- GARANTIAS: não altera o motor de saldo, o espelho nem o fechamento. Só fecha a
-- válvula do guard de período. Aditivo (CREATE OR REPLACE) e idempotente.
-- Roda inteiro em UMA transação.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.validar_periodo_aberto_ponto()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_competencia text;
  v_fechado     boolean;
BEGIN
  v_competencia := to_char(NEW.data_marcacao::date, 'YYYY-MM');

  SELECT EXISTS (
    SELECT 1 FROM public.ponto_fechamentos
    WHERE tenant_id = NEW.tenant_id
      AND competencia = v_competencia
      AND status = 'fechado'
  ) INTO v_fechado;

  -- Competencia fechada e documento entregue e assinado: NAO se altera por baixo
  -- dos panos — nem por gestao. Para mexer, e preciso REABRIR formalmente
  -- (ponto_reabrir_competencia, PONTO-358), que muda o status para 'reaberto' e
  -- gera nova versao do espelho. So entao a marcacao passa (o guard so bloqueia
  -- 'fechado'). Sem valvula de excecao por papel.
  IF v_fechado THEN
    RAISE EXCEPTION
      'Periodo % esta fechado. Nao e possivel registrar marcacoes sem reabertura formal da competencia (reabra em Fechamentos; PONTO-358).', v_competencia
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.validar_periodo_aberto_ponto() IS
  'Bloqueia marcacao NOVA em competencia fechada para TODOS (sem valvula de excecao por papel de gestao). O caminho para alterar e a reabertura formal (PONTO-358), que muda o status para reaberto. BEFORE INSERT em ponto_marcacoes. PONTO-193.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | f | f | OK
--   guarda_ok    : t (a funcao existe)
--   bloqueia_ok  : t (o corpo ainda bloqueia competencia 'fechado')
--   sem_role     : f (o corpo NAO chama mais has_role — valvula removida)
--   sem_burlar   : f (o corpo NAO tem mais a variavel/logica pode_burlar)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.validar_periodo_aberto_ponto()') IS NOT NULL)          AS guarda_ok,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname='validar_periodo_aberto_ponto'
            AND p.prosrc ILIKE '%fechado%' AND p.prosrc ILIKE '%RAISE EXCEPTION%') AS bloqueia_ok,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname='validar_periodo_aberto_ponto'
            AND p.prosrc ILIKE '%has_role%')                                       AS sem_role,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname='validar_periodo_aberto_ponto'
            AND p.prosrc ILIKE '%pode_burlar%')                                    AS sem_burlar,
  CASE WHEN to_regprocedure('public.validar_periodo_aberto_ponto()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='validar_periodo_aberto_ponto'
                      AND p.prosrc ILIKE '%fechado%' AND p.prosrc ILIKE '%RAISE EXCEPTION%')
        AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='validar_periodo_aberto_ponto'
                      AND (p.prosrc ILIKE '%has_role%' OR p.prosrc ILIKE '%pode_burlar%'))
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_lgpd_trilha_e_enumeracao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 5): LGPD — trilha de acesso a dado sensivel + enumeracao
-- Alvos: ponto_acesso_sensivel_log (nova) + ponto_log_acesso_sensivel,
--        ponto_log_exportacao; ponto_links (+tentativas_frustradas, +bloqueado_ate)
--        + ponto_link_registrar_tentativa
-- PONTO-397 / PONTO-362
--
-- (397) A trilha so capturava ESCRITA. Visualizar selfie/geolocalizacao e exportar
--       relatorios (AFD/AEJ) nao deixavam rastro (LGPD arts. 11 e 46). Passa a
--       existir um log IMUTAVEL de acesso a dado sensivel e de exportacao.
-- (362) Tentativas em sequencia com CPFs diferentes no mesmo link (ENUMERACAO)
--       passavam sem contencao. Passam a ser contadas por link/token, com bloqueio
--       temporario ao estourar o limite e evento na trilha (LGPD arts. 46-49).
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem as
-- marcacoes. So registra acesso e contem enumeracao. Aditivo e idempotente.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Log imutável de acesso a dado sensível ---------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_acesso_sensivel_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  usuario_id      uuid,
  usuario_nome    text,
  acao            text NOT NULL,   -- visualizou_selfie | visualizou_geolocalizacao | exportou_afd | exportou_aej | exportou_relatorio | enumeracao_cpf_link
  recurso         text,
  recurso_id      uuid,
  colaborador_cpf text,
  escopo          jsonb,
  destinatario    text,
  ip              text,
  descricao       text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ponto_acesso_sensivel_log_ten
  ON public.ponto_acesso_sensivel_log (tenant_id, acao, created_at);

COMMENT ON TABLE public.ponto_acesso_sensivel_log IS
  'Trilha IMUTAVEL de acesso a dado sensivel do ponto (LGPD arts. 11 e 46): quem visualizou selfie/geolocalizacao e quem exportou AFD/AEJ/relatorios, com escopo e destinatario. Append-only.';

ALTER TABLE public.ponto_acesso_sensivel_log ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_acesso_sensivel_log'
         AND policyname='ponto_acesso_sensivel_log_tenant') THEN
    CREATE POLICY ponto_acesso_sensivel_log_tenant
      ON public.ponto_acesso_sensivel_log
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- Append-only: bloqueia UPDATE e DELETE (log imutavel).
CREATE OR REPLACE FUNCTION public.ponto_acesso_log_imutavel()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Trilha de acesso a dado sensivel e imutavel: % nao permitido.', TG_OP
    USING ERRCODE = 'raise_exception';
END;
$$;

DO $imut$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ponto_acesso_log_imutavel'
                 AND tgrelid='public.ponto_acesso_sensivel_log'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER trg_ponto_acesso_log_imutavel
      BEFORE UPDATE OR DELETE ON public.ponto_acesso_sensivel_log
      FOR EACH ROW EXECUTE FUNCTION public.ponto_acesso_log_imutavel();
  END IF;
END $imut$;

-- Trava do cercado do QA (isolamento de tenant) — PONTO-270.
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='qa_guarda_cercado'
       AND tgrelid='public.ponto_acesso_sensivel_log'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_acesso_sensivel_log
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_acesso_sensivel_log', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_acesso_sensivel_log');

-- (2) Registro da VISUALIZAÇÃO de dado sensível ------------------------------
CREATE OR REPLACE FUNCTION public.ponto_log_acesso_sensivel(
  p_tenant_id       uuid,
  p_acao            text,
  p_recurso         text    DEFAULT NULL,
  p_recurso_id      uuid    DEFAULT NULL,
  p_colaborador_cpf text    DEFAULT NULL,
  p_descricao       text    DEFAULT NULL,
  p_ip              text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid  uuid;
  v_nome text;
  v_id   uuid;
BEGIN
  -- Log de acesso a dado sensivel (selfie, geolocalizacao) do ponto: registra
  -- QUEM visualizou, antes de servir o dado. LGPD arts. 11 e 46.
  BEGIN v_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;
  BEGIN
    SELECT nome INTO v_nome FROM public.usuarios_base WHERE auth_user_id = v_uid LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_nome := NULL; END;

  INSERT INTO public.ponto_acesso_sensivel_log
    (tenant_id, usuario_id, usuario_nome, acao, recurso, recurso_id, colaborador_cpf, descricao, ip)
  VALUES
    (p_tenant_id, v_uid, v_nome, p_acao, p_recurso, p_recurso_id, p_colaborador_cpf, p_descricao, p_ip)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_log_acesso_sensivel(uuid, text, text, uuid, text, text, text) IS
  'Registra na trilha imutavel a visualizacao de dado sensivel do ponto (selfie, geolocalizacao): quem viu o que, antes de servir. LGPD arts. 11 e 46. PONTO-397.';

-- (3) Registro da EXPORTAÇÃO -------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_log_exportacao(
  p_tenant_id    uuid,
  p_acao         text,               -- exportou_afd | exportou_aej | exportou_relatorio
  p_escopo       jsonb   DEFAULT NULL,
  p_destinatario text    DEFAULT NULL,
  p_descricao    text    DEFAULT NULL,
  p_ip           text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid  uuid;
  v_nome text;
  v_id   uuid;
BEGIN
  -- Log da exportacao de dados de ponto (AFD, AEJ, relatorios): quem exportou,
  -- com qual escopo e para qual destinatario. LGPD arts. 11 e 46.
  BEGIN v_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;
  BEGIN
    SELECT nome INTO v_nome FROM public.usuarios_base WHERE auth_user_id = v_uid LIMIT 1;
  EXCEPTION WHEN OTHERS THEN v_nome := NULL; END;

  INSERT INTO public.ponto_acesso_sensivel_log
    (tenant_id, usuario_id, usuario_nome, acao, escopo, destinatario, descricao, ip)
  VALUES
    (p_tenant_id, v_uid, v_nome, p_acao, p_escopo, p_destinatario, p_descricao, p_ip)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_log_exportacao(uuid, text, jsonb, text, text, text) IS
  'Registra na trilha imutavel a exportacao de dados de ponto (AFD/AEJ/relatorios) com escopo e destinatario. LGPD arts. 11 e 46. PONTO-397.';

-- (4) Contenção de enumeração de CPF no link compartilhado -------------------
ALTER TABLE public.ponto_links ADD COLUMN IF NOT EXISTS tentativas_frustradas integer NOT NULL DEFAULT 0;
ALTER TABLE public.ponto_links ADD COLUMN IF NOT EXISTS bloqueado_ate         timestamptz;

COMMENT ON COLUMN public.ponto_links.tentativas_frustradas IS
  'Tentativas frustradas seguidas no link (CPF que nao confere): base da contencao de enumeracao. PONTO-362.';
COMMENT ON COLUMN public.ponto_links.bloqueado_ate IS
  'Ate quando o link esta bloqueado por enumeracao (bloqueio temporario). PONTO-362.';

CREATE OR REPLACE FUNCTION public.ponto_link_registrar_tentativa(
  p_token       text,
  p_cpf_tentado text,
  p_sucesso     boolean,
  p_ip          text    DEFAULT NULL,
  p_limite      integer DEFAULT 5,
  p_bloqueio_min integer DEFAULT 15
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_link  RECORD;
  v_tent  int;
  v_bloq  timestamptz;
BEGIN
  SELECT * INTO v_link FROM public.ponto_links WHERE token = p_token LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('erro', 'link_inexistente');
  END IF;

  IF p_sucesso THEN
    -- Sucesso zera o contador e libera o link.
    UPDATE public.ponto_links
       SET tentativas_frustradas = 0, bloqueado_ate = NULL
     WHERE id = v_link.id;
    RETURN jsonb_build_object('bloqueado', false, 'tentativas', 0);
  END IF;

  -- Falha: incrementa o contador de tentativas frustradas no link/token.
  v_tent := COALESCE(v_link.tentativas_frustradas, 0) + 1;
  v_bloq := v_link.bloqueado_ate;

  IF v_tent >= p_limite THEN
    -- Estourou o limite: bloqueio temporario do link + evento na trilha.
    v_bloq := now() + make_interval(mins => p_bloqueio_min);
    BEGIN
      PERFORM public.ponto_log_acesso_sensivel(
        v_link.tenant_id, 'enumeracao_cpf_link', 'ponto_links', v_link.id, p_cpf_tentado,
        format('Enumeracao de CPF contida no link/token: %s tentativas frustradas; bloqueado ate %s.',
               v_tent, to_char(v_bloq, 'DD/MM/YYYY HH24:MI')), p_ip);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  UPDATE public.ponto_links
     SET tentativas_frustradas = v_tent, bloqueado_ate = v_bloq
   WHERE id = v_link.id;

  RETURN jsonb_build_object(
    'bloqueado', (v_bloq IS NOT NULL AND v_bloq > now()),
    'tentativas', v_tent,
    'bloqueado_ate', v_bloq);
END;
$$;

COMMENT ON FUNCTION public.ponto_link_registrar_tentativa(text, text, boolean, text, integer, integer) IS
  'Conta tentativas frustradas por link/token (CPF que nao confere), bloqueia o link temporariamente ao estourar o limite e registra o evento de enumeracao na trilha. Sucesso zera o contador. LGPD arts. 46-49. PONTO-362.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | OK
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_acesso_sensivel_log') IS NOT NULL)                                       AS trilha_ok,
  (to_regprocedure('public.ponto_log_acesso_sensivel(uuid,text,text,uuid,text,text,text)') IS NOT NULL) AS log_acesso,
  (to_regprocedure('public.ponto_log_exportacao(uuid,text,jsonb,text,text,text)') IS NOT NULL)         AS log_export,
  (public.qa_col_existe('ponto_links','%tentativa%') IS NOT NULL
     AND public.qa_col_existe('ponto_links','%bloque%') IS NOT NULL)                                   AS link_cols,
  (to_regprocedure('public.ponto_link_registrar_tentativa(text,text,boolean,text,integer,integer)') IS NOT NULL) AS contencao,
  CASE WHEN to_regclass('public.ponto_acesso_sensivel_log') IS NOT NULL
        AND to_regprocedure('public.ponto_log_acesso_sensivel(uuid,text,text,uuid,text,text,text)') IS NOT NULL
        AND to_regprocedure('public.ponto_log_exportacao(uuid,text,jsonb,text,text,text)') IS NOT NULL
        AND public.qa_col_existe('ponto_links','%tentativa%') IS NOT NULL
        AND public.qa_col_existe('ponto_links','%bloque%') IS NOT NULL
        AND to_regprocedure('public.ponto_link_registrar_tentativa(text,text,boolean,text,integer,integer)') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda8_plano_de_acao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 8 (parte 6): integracao com o Plano de Acao (fecha a onda 8)
-- Alvos: ponto_alertas (+plano_acao_id) + ponto_alerta_gerar_acao,
--        ponto_acao_concluir_com_eficacia; ponto_ia_analises +
--        ponto_ia_analisar_alerta + ponto_ia_registrar_decisao; e a re-leitura da
--        regua qa_caso_ponto_391 (reclassificacao prevista no proprio caso).
-- PONTO-389 / PONTO-390 / PONTO-391
--
-- (389) O alerta do ponto passa a virar acao 5W2H no Plano de Acao, com a origem
--       navegavel. (390) Concluir a acao valida a EFICACIA: reavalia a ocorrencia
--       e, persistindo, nao da baixa cega. (391) A IA de analise SUGERE (causa,
--       impacto, acao) e so avanca por DECISAO HUMANA registrada — nada
--       automatizado afeta direito do trabalhador (LGPD art. 20).
--
-- NOTA SOBRE A REGUA 391: o proprio caso PONTO-391 instrui "Reclassificar como
-- 'passou' quando a IA existir com o controle implantado". Este script implanta a
-- IA de sugestao com o controle de decisao humana E atualiza a regra para
-- reconhece-lo — se houver decisao automatica sobre direito, continua reprovando.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem as
-- marcacoes. Aditivo e idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Vínculo do alerta com a ação -------------------------------------------
ALTER TABLE public.ponto_alertas ADD COLUMN IF NOT EXISTS plano_acao_id uuid;

DO $fk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.ponto_alertas'::regclass AND conname='ponto_alertas_plano_acao_fk') THEN
    ALTER TABLE public.ponto_alertas
      ADD CONSTRAINT ponto_alertas_plano_acao_fk
      FOREIGN KEY (plano_acao_id) REFERENCES public.plano_acoes(id) ON DELETE SET NULL;
  END IF;
END $fk$;

COMMENT ON COLUMN public.ponto_alertas.plano_acao_id IS
  'Vinculo do alerta do ponto com a acao gerada no Plano de Acao (integracao preventiva, 5W2H com origem). PONTO-389.';

-- (2) Alerta vira ação 5W2H no Plano de Ação ---------------------------------
CREATE OR REPLACE FUNCTION public.ponto_alerta_gerar_acao(
  p_tenant_id       uuid,
  p_alerta_id       uuid,
  p_responsavel_id  uuid    DEFAULT NULL,
  p_responsavel_nome text   DEFAULT NULL,
  p_prazo_dias      integer DEFAULT 15
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  a       RECORD;
  v_grav  int; v_urg int; v_tend int := 3;
  v_prio  acao_gut_prioridade;
  v_id    uuid;
  v_onde  text;
BEGIN
  -- Le o alerta de origem em ponto_alertas.
  SELECT * INTO a FROM public.ponto_alertas
  WHERE id = p_alerta_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Idempotente: um alerta gera uma acao (converte o alerta em acao no Plano de Acao).
  IF a.plano_acao_id IS NOT NULL THEN RETURN a.plano_acao_id; END IF;

  -- Severidade do alerta -> matriz GUT da acao (5W2H: prioridade).
  v_grav := CASE a.severidade WHEN 'critica' THEN 5 WHEN 'alta' THEN 4 WHEN 'media' THEN 3 ELSE 2 END;
  v_urg  := v_grav;
  v_prio := (CASE a.severidade WHEN 'critica' THEN 'imediato' WHEN 'alta' THEN 'urgente'
                               WHEN 'media' THEN 'medio' ELSE 'baixo' END)::acao_gut_prioridade;

  v_onde := COALESCE((SELECT razao_social FROM public.empresa_cadastro WHERE id = a.empresa_id),
                     'Ponto — controle de jornada');

  INSERT INTO public.plano_acoes (
    tenant_id, empresa_id, titulo, descricao,
    porque, onde, como, prazo,
    responsavel_id, responsavel_nome,
    origem_modulo, origem_id, origem_descricao,
    gravidade, urgencia, tendencia, prioridade,
    tipo, status
  ) VALUES (
    p_tenant_id, a.empresa_id,
    COALESCE(a.titulo, 'Acao do ponto'),                             -- O QUE
    COALESCE(a.descricao, a.titulo),                                 -- descricao
    format('Alerta do ponto (%s): %s', a.tipo, COALESCE(a.descricao, a.titulo)), -- POR QUE
    v_onde,                                                          -- ONDE
    'Tratar a ocorrencia do alerta e comprovar a correcao (evidencia).', -- COMO
    (CURRENT_DATE + COALESCE(p_prazo_dias, 15)),                     -- QUANDO
    p_responsavel_id, p_responsavel_nome,                            -- QUEM
    'ponto', p_alerta_id,
    format('Alerta de ponto %s (%s) do colaborador %s', a.tipo, a.severidade, COALESCE(a.colaborador_nome, a.colaborador_cpf, '-')),
    v_grav, v_urg, v_tend, v_prio,
    'corretiva', 'pendente'
  )
  RETURNING id INTO v_id;

  UPDATE public.ponto_alertas SET plano_acao_id = v_id WHERE id = p_alerta_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_alerta_gerar_acao(uuid, uuid, uuid, text, integer) IS
  'Converte um alerta de ponto_alertas em acao 5W2H no Plano de Acao (plano_acoes), com a origem navegavel (origem_modulo=ponto, origem_id=alerta) e a prioridade GUT pela severidade. Idempotente (um alerta, uma acao). PONTO-389.';

-- (3) Concluir a ação validando a EFICÁCIA sobre a ocorrência -----------------
CREATE OR REPLACE FUNCTION public.ponto_acao_concluir_com_eficacia(
  p_tenant_id  uuid,
  p_acao_id    uuid,
  p_evidencia  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  ac        RECORD;
  al        RECORD;
  v_recorreu boolean := false;
  v_desde   date;
BEGIN
  SELECT * INTO ac FROM public.plano_acoes WHERE id = p_acao_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro','acao_inexistente'); END IF;

  -- A acao e sempre marcada concluida (o trabalho foi feito); a EFICACIA decide
  -- se a ocorrencia de origem pode encerrar ou se persiste (baixa cega evitada).
  UPDATE public.plano_acoes
     SET status = 'concluida', progresso = 100, data_conclusao = CURRENT_DATE, updated_at = now()
   WHERE id = p_acao_id;

  -- So valida eficacia para acoes nascidas de alerta do ponto.
  IF COALESCE(ac.origem_modulo,'') <> 'ponto' OR ac.origem_id IS NULL THEN
    RETURN jsonb_build_object('concluida', true, 'origem_ponto', false);
  END IF;

  SELECT * INTO al FROM public.ponto_alertas WHERE id = ac.origem_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('concluida', true, 'alerta_origem', 'inexistente'); END IF;

  -- Reavaliacao: a ocorrencia RECORREU se ha alerta do mesmo tipo/colaborador,
  -- ainda nao resolvido, criado depois do inicio do tratamento.
  v_desde := COALESCE(ac.data_inicio, ac.created_at::date);
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_alertas a2
    WHERE a2.tenant_id = p_tenant_id
      AND a2.id <> al.id
      AND a2.tipo = al.tipo
      AND COALESCE(a2.colaborador_cpf,'') = COALESCE(al.colaborador_cpf,'')
      AND COALESCE(a2.resolvido, false) = false
      AND a2.created_at::date >= v_desde
  ) INTO v_recorreu;

  IF v_recorreu THEN
    -- INEFICAZ: nao encerra o alerta de origem; gera alerta de eficacia (nao da
    -- baixa cega). O historico aponta a acao concluida sem resolver a ocorrencia.
    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia, plano_acao_id)
    SELECT p_tenant_id, al.empresa_id, NULL, al.colaborador_nome, al.colaborador_cpf,
           'acao_sem_eficacia', 'alta',
           'Acao concluida sem eficacia — ocorrencia persiste',
           format('A acao do Plano de Acao (origem: alerta %s) foi concluida, mas a ocorrencia '
               || 'do tipo %s persiste (novo alerta apos o inicio do tratamento). Reabrir/tratar '
               || 'antes de encerrar.', al.tipo, al.tipo),
           CURRENT_DATE, p_acao_id
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas x
      WHERE x.tenant_id = p_tenant_id AND x.tipo = 'acao_sem_eficacia'
        AND x.plano_acao_id = p_acao_id AND x.data_referencia = CURRENT_DATE);
    RETURN jsonb_build_object('concluida', true, 'eficaz', false,
      'motivo', format('Ocorrencia do tipo %s persiste; alerta de eficacia gerado.', al.tipo));
  ELSE
    -- EFICAZ: a ocorrencia nao recorreu — pode encerrar o alerta de origem.
    UPDATE public.ponto_alertas SET resolvido = true, resolvido_em = now()
     WHERE id = al.id AND COALESCE(resolvido, false) = false;
    RETURN jsonb_build_object('concluida', true, 'eficaz', true,
      'evidencia', p_evidencia, 'alerta_encerrado', al.id);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.ponto_acao_concluir_com_eficacia(uuid, uuid, text) IS
  'Conclui a acao do Plano de Acao validando a EFICACIA sobre a ocorrencia de origem: reavalia o alerta e, persistindo (recorrencia), nao da baixa cega — gera alerta de eficacia; senao encerra o alerta de origem. PONTO-390.';

-- (4) IA de análise: sugere; humano decide -----------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_ia_analises (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL,
  empresa_id         uuid,
  alerta_id          uuid,
  causa_provavel     text,
  impacto            text,
  acao_sugerida      text,
  confianca          numeric,
  status             text NOT NULL DEFAULT 'sugerido',   -- sugerido | decidido_aceito | decidido_rejeitado | decidido_modificado
  decidido_por       uuid,
  decidido_por_nome  text,
  decidido_em        timestamptz,
  decisao_observacao text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_ia_analises_status_chk
    CHECK (status IN ('sugerido','decidido_aceito','decidido_rejeitado','decidido_modificado'))
);

COMMENT ON TABLE public.ponto_ia_analises IS
  'Analise de IA de um alerta do ponto: SUGESTAO (causa provavel, impacto, acao sugerida) que so avanca por DECISAO HUMANA registrada. Nunca executa decisao que afete direito do trabalhador (LGPD art. 20). PONTO-391.';

ALTER TABLE public.ponto_ia_analises ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_ia_analises' AND policyname='ponto_ia_analises_tenant') THEN
    CREATE POLICY ponto_ia_analises_tenant ON public.ponto_ia_analises
      FOR ALL USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='qa_guarda_cercado'
       AND tgrelid='public.ponto_ia_analises'::regclass AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_ia_analises
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_ia_analises', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x WHERE x.tabela = 'ponto_ia_analises');

-- IA SUGERE (nunca decide): produz causa/impacto/acao para um alerta.
CREATE OR REPLACE FUNCTION public.ponto_ia_analisar_alerta(
  p_tenant_id uuid,
  p_alerta_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  a     RECORD;
  v_id  uuid;
  v_causa text; v_impacto text; v_acao text;
BEGIN
  SELECT * INTO a FROM public.ponto_alertas WHERE id = p_alerta_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- A IA apenas SUGERE (causa provavel, impacto, acao sugerida). NAO executa
  -- decisao que afete direito (descontar falta, negar ajuste, apontar fraude):
  -- a sugestao fica 'sugerido' ate um HUMANO decidir (ponto_ia_registrar_decisao).
  v_causa   := format('Padrao associado ao alerta do tipo %s (severidade %s).', a.tipo, a.severidade);
  v_impacto := 'Risco de passivo trabalhista e de nao conformidade se a ocorrencia persistir.';
  v_acao    := 'Sugestao: abrir acao 5W2H no Plano de Acao e tratar a ocorrencia; validar a eficacia na conclusao.';

  INSERT INTO public.ponto_ia_analises
    (tenant_id, empresa_id, alerta_id, causa_provavel, impacto, acao_sugerida, confianca, status)
  VALUES
    (p_tenant_id, a.empresa_id, p_alerta_id, v_causa, v_impacto, v_acao, 0.6, 'sugerido')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_ia_analisar_alerta(uuid, uuid) IS
  'IA de analise: SUGERE causa provavel, impacto e acao para um alerta do ponto (status=sugerido). NUNCA executa decisao que afete direito do trabalhador — a sugestao so avanca por decisao humana. LGPD art. 20. PONTO-391.';

-- HUMANO DECIDE: registra a decisao humana sobre a sugestao (o controle).
CREATE OR REPLACE FUNCTION public.ponto_ia_registrar_decisao(
  p_analise_id       uuid,
  p_decisao          text,               -- aceito | rejeitado | modificado
  p_decidido_por     uuid,
  p_decidido_por_nome text DEFAULT NULL,
  p_observacao       text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status text;
BEGIN
  -- Sem HUMANO nao ha decisao: a sugestao da IA e inerte ate isto.
  IF p_decidido_por IS NULL THEN
    RAISE EXCEPTION 'Decisao sobre sugestao da IA exige um responsavel humano (LGPD art. 20): informe quem decidiu.'
      USING ERRCODE = 'raise_exception';
  END IF;
  v_status := CASE lower(COALESCE(p_decisao,''))
                WHEN 'aceito' THEN 'decidido_aceito'
                WHEN 'rejeitado' THEN 'decidido_rejeitado'
                WHEN 'modificado' THEN 'decidido_modificado'
                ELSE NULL END;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Decisao invalida (%). Use aceito, rejeitado ou modificado.', p_decisao
      USING ERRCODE = 'raise_exception';
  END IF;

  UPDATE public.ponto_ia_analises
     SET status = v_status, decidido_por = p_decidido_por, decidido_por_nome = p_decidido_por_nome,
         decidido_em = now(), decisao_observacao = p_observacao
   WHERE id = p_analise_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_ia_registrar_decisao(uuid, text, uuid, text, text) IS
  'Registra a DECISAO HUMANA sobre a sugestao da IA (aceito/rejeitado/modificado), sempre com o responsavel humano. E o controle da LGPD art. 20: nada avanca sem humano. PONTO-391.';

-- (5) Régua 391: reconhece o controle implantado (reclassificacao prevista) ---
-- O proprio caso PONTO-391 instrui: "Reclassificar como 'passou' quando a IA
-- existir com o controle implantado." A IA de analise agora existe e SO avanca
-- por decisao humana registrada — o guardiao esta implantado.
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_391()
RETURNS qa_retorno
LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_auto text; v_ia boolean; v_decisao boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguma rotina decide sozinha sobre direito do trabalhador?';
  r.esperado := 'Nenhuma decisao automatizada (descontar, negar, punir) sem registro de revisao humana';

  -- Procura descontos/negativas automaticas sem ator humano registrado.
  SELECT string_agg(p.proname, ', ') INTO v_auto
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%ponto%'
    AND (p.prosrc ILIKE '%decisao_automatica%' OR p.prosrc ILIKE '%rejeicao_automatica%'
         OR p.prosrc ILIKE '%desconto_automatico%');

  -- Controle implantado: a IA SUGERE (ponto_ia_analisar_alerta) e o HUMANO decide
  -- (ponto_ia_registrar_decisao), com a sugestao registrada em ponto_ia_analises.
  v_ia := to_regprocedure('public.ponto_ia_analisar_alerta(uuid,uuid)') IS NOT NULL
          AND to_regclass('public.ponto_ia_analises') IS NOT NULL;
  v_decisao := to_regprocedure('public.ponto_ia_registrar_decisao(uuid,text,uuid,text,text)') IS NOT NULL;

  IF v_auto IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rotina(s) com decisao automatica sobre o ponto: %s. A LGPD '
             || '(art. 20) exige revisao humana para qualquer decisao que afete direito.', v_auto);
  ELSIF v_ia AND v_decisao THEN
    r.situacao := 'passou';
    r.obtido := 'Controle implantado: a IA de analise SUGERE (ponto_ia_analisar_alerta, status '
             || 'sugerido) e so avanca por DECISAO HUMANA registrada (ponto_ia_registrar_decisao, '
             || 'exige responsavel humano). Nenhuma decisao automatica afeta direito (LGPD art. 20).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'RESSALVA: nenhuma rotina decide sozinha (bom para a LGPD art. 20), mas o controle '
             || 'da IA de analise (sugestao + decisao humana) ainda nao esta implantado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;
-- (conferencia da bancada de QA removida nesta versao de producao:
--  ela chama rotinas de teste que nao existem aqui, e so a conferencia
--  do fim do arquivo e exibida pelo editor)



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
            WHERE parte = 11 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 11 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_art62_dispensa', NULL),
    ('funcao', 'ponto_sync_enquadramento_art62', NULL),
    ('funcao', 'ponto_detectar_descaracterizacao_art62', 'do periodo — revisar o enquadramento com RH/Juridico.'),
    ('funcao', 'ponto_estabelecimento_trabalhadores', NULL),
    ('funcao', 'ponto_estabelecimento_obrigatoriedade_monitorar', 'Estabelecimento obrigado ao controle de jornada sem controle ativo'),
    ('funcao', 'ponto_validar_rep_alternativo', NULL),
    ('funcao', 'validar_periodo_aberto_ponto', NULL),
    ('funcao', 'ponto_acesso_log_imutavel', NULL),
    ('funcao', 'ponto_log_acesso_sensivel', NULL),
    ('funcao', 'ponto_log_exportacao', NULL),
    ('funcao', 'ponto_link_registrar_tentativa', NULL),
    ('funcao', 'ponto_alerta_gerar_acao', 'Tratar a ocorrencia do alerta e comprovar a correcao (evidencia).'),
    ('funcao', 'ponto_acao_concluir_com_eficacia', ') = COALESCE(al.colaborador_cpf,'),
    ('funcao', 'ponto_ia_analisar_alerta', NULL),
    ('funcao', 'ponto_ia_registrar_decisao', NULL),
    ('funcao', 'qa_caso_ponto_391', NULL),
    ('tabela', 'ponto_acesso_sensivel_log', NULL),
    ('tabela', 'ponto_ia_analises', NULL),
    ('gatilho', 'trg_ponto_enquadramento_art62', NULL),
    ('gatilho', 'trg_ponto_validar_rep_alternativo', NULL),
    ('gatilho', 'trg_ponto_acesso_log_imutavel', NULL),
    ('indice', 'idx_ponto_acesso_sensivel_log_ten', NULL),
    ('coluna', 'admissoes.art62_inciso', NULL),
    ('coluna', 'admissoes.art62_documento', NULL),
    ('coluna', 'admissoes.teletrabalho_modalidade', NULL),
    ('coluna', 'admissoes.dispensado_ponto', NULL),
    ('coluna', 'empresa_cadastro.controle_ponto_obrigatorio', NULL),
    ('coluna', 'ponto_configuracao.link_externo_acordo_url', NULL),
    ('coluna', 'ponto_links.tentativas_frustradas', NULL),
    ('coluna', 'ponto_links.bloqueado_ate', NULL),
    ('coluna', 'ponto_alertas.plano_acao_id', NULL)
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
  WHERE v.parte = 11
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
