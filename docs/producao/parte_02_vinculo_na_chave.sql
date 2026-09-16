-- ============================================================================
-- PRODUCAO — PONTO, PARTE 02 de 16
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
  DELETE FROM public.ponto_entrega_volume WHERE parte = 2;
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
    VALUES (2, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda1_vinculo_na_chave.sql
-- ############################################################

-- ============================================================================
-- SCRIPT DE ENTREGA — PONTO, ONDA 1 (parte 2): vínculo/empresa na chave
-- Cole no SQL Editor do banco de PRODUÇÃO (projeto diayjpsrcerycycyaxst)
-- SOMENTE após aprovar no ambiente de teste. Idempotente (pode rodar 2x).
--
-- O QUE FAZ (PONTO-394)
--   Inclui a empresa na chave da apuração diária, para que dois vínculos do
--   mesmo trabalhador (duas empresas do grupo, dois estabelecimentos) tenham
--   cada um a sua linha — hoje o segundo contrato colide com o primeiro.
--
-- O QUE NÃO FAZ
--   Não altera cálculo de jornada. Para quem tem UM vínculo, o dia continua
--   sendo uma única linha, apurada exatamente como antes. Um gatilho de
--   reconciliação garante isso: ao reapurar um dia legado (empresa nula), a
--   escrita adota o nulo existente e funde na linha legada, em vez de criar
--   uma segunda. Dois vínculos reais (ambos com empresa) permanecem separados.
--
-- A parte de QA (fixtures e rotina do PONTO-394) fica no ambiente de teste,
-- que roda o motor de QA; não faz parte deste script de produção.
-- ============================================================================

SET LOCAL lock_timeout = '10s';


-- ---------------------------------------------------------------------
-- 1) Gatilho de reconciliação de empresa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_diario_reconcilia_empresa()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- Preenche a empresa quando veio vazia, para que a nova chave não separe
  -- em duas linhas o dia de quem tem um único vínculo. Alinha-se ao
  -- PONTO-311 ("linha sem empresa é resolvida pelo cadastro").
  IF NEW.empresa_id IS NULL THEN
    NEW.empresa_id := public.ponto_empresa_do_cpf(NEW.tenant_id, NEW.colaborador_cpf);
  END IF;

  -- Reconciliação de legado: se já existe uma linha do mesmo dia com
  -- empresa ainda NÃO resolvida (nula), a escrita nova adota esse nulo
  -- para casar com a linha legada — em vez de criar uma segunda. Só vale
  -- quando a linha existente tem empresa nula; dois vínculos reais (ambos
  -- com empresa preenchida) permanecem separados.
  IF TG_OP = 'INSERT' AND NEW.empresa_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.ponto_diario d
      WHERE d.tenant_id = NEW.tenant_id
        AND d.colaborador_cpf = NEW.colaborador_cpf
        AND d.data = NEW.data
        AND d.empresa_id IS NULL
    ) THEN
      NEW.empresa_id := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_diario_reconcilia_empresa ON public.ponto_diario;
CREATE TRIGGER trg_ponto_diario_reconcilia_empresa
BEFORE INSERT OR UPDATE ON public.ponto_diario
FOR EACH ROW
EXECUTE FUNCTION public.ponto_diario_reconcilia_empresa();

-- ---------------------------------------------------------------------
-- 2) Nova chave única: inclui a empresa (nula tratada por sentinela)
-- ---------------------------------------------------------------------
-- Dados existentes têm no máximo uma linha por (tenant, cpf, data), então
-- acrescentar a empresa à chave nunca gera colisão na construção.
ALTER TABLE public.ponto_diario DROP CONSTRAINT IF EXISTS unique_ponto_diario;
DROP INDEX IF EXISTS public.unique_ponto_diario;
CREATE UNIQUE INDEX unique_ponto_diario ON public.ponto_diario
  (tenant_id, colaborador_cpf, data,
   COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid));

COMMENT ON INDEX public.unique_ponto_diario IS
  'PONTO-394 — a apuracao diaria e por vinculo: (tenant, cpf, data, empresa). Empresa nula usa sentinela zerada, mantendo uma linha por dia para quem tem um unico vinculo.';

-- ---------------------------------------------------------------------
-- 3) Os 5 escritores de ponto_diario: arbiter do ON CONFLICT atualizado
--    para a nova chave. Nenhuma outra linha do corpo muda.
-- ---------------------------------------------------------------------
-- ---- consolidar_ponto_diario_manual: arbiter da chave atualizado (unica mudanca) ----
CREATE OR REPLACE FUNCTION public.consolidar_ponto_diario_manual(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_afast public.afastamentos;
  v_ferias public.ferias_solicitacoes;
  v_atest public.atestados;
  v_cid UUID; v_cnome TEXT; v_eid UUID; v_obs TEXT;
  c RECORD;
BEGIN
  SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
  FROM public.ponto_marcacoes
  WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
  ORDER BY created_at DESC LIMIT 1;
  IF v_cid IS NULL THEN
    SELECT colaborador_id, colaborador_nome INTO v_cid, v_cnome
    FROM public.ponto_ajustes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
    ORDER BY created_at DESC LIMIT 1;
  END IF;

  -- Quem nunca bateu ponto nem teve ajuste também precisa existir no
  -- espelho: é exatamente o caso que a materialização de faltas procura.
  -- Antes desta linha, a função saía sem gravar e a falta ficava invisível.
  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo INTO v_cid, v_cnome
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
      AND COALESCE(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  SELECT f.* INTO v_ferias FROM public.ferias_solicitacoes f
  WHERE f.tenant_id = p_tenant_id AND f.colaborador_cpf = p_colaborador_cpf
    AND f.status IN ('aprovado','em_gozo','concluido')
    AND f.data_inicio <= p_data AND f.data_fim >= p_data
  ORDER BY f.data_inicio DESC LIMIT 1;
  IF v_ferias.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_ferias.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_ferias.colaborador_nome);
    v_obs := 'Férias: ' || to_char(v_ferias.data_inicio,'DD/MM/YYYY') || ' a ' || to_char(v_ferias.data_fim,'DD/MM/YYYY');
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  SELECT a.* INTO v_atest FROM public.atestados a
  WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
    AND a.data_inicio_afastamento IS NOT NULL
    AND a.data_inicio_afastamento <= p_data
    AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
  ORDER BY a.data_inicio_afastamento DESC LIMIT 1;
  IF v_atest.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_atest.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_atest.colaborador_nome);
    v_obs := 'Atestado: ' || to_char(v_atest.data_inicio_afastamento,'DD/MM/YYYY')
      || CASE WHEN v_atest.data_fim_afastamento IS NOT NULL THEN ' a ' || to_char(v_atest.data_fim_afastamento,'DD/MM/YYYY') ELSE '' END;
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  v_afast := public.afastamento_vigente(p_tenant_id, p_colaborador_cpf, p_data);
  IF v_afast.id IS NOT NULL THEN
    v_cid := COALESCE(v_cid, v_afast.colaborador_id);
    v_cnome := COALESCE(v_cnome, v_afast.colaborador_nome);
    v_obs := 'Afastamento (' || COALESCE(replace(v_afast.motivo_principal::text,'_',' '),'registrado')
      || '): de ' || to_char(v_afast.data_inicio,'DD/MM/YYYY')
      || CASE WHEN v_afast.data_fim IS NOT NULL THEN ' a ' || to_char(v_afast.data_fim,'DD/MM/YYYY') ELSE ' — em aberto' END;
    PERFORM public._ponto_grava_abono(p_tenant_id, v_cid, v_cnome, p_colaborador_cpf, p_data, v_obs);
    RETURN;
  END IF;

  IF v_cid IS NULL THEN RETURN; END IF;
  v_eid := COALESCE(public.ponto_empresa_do_colaborador(v_cid),
                    public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf));

  c := public._ponto_calc_dia(p_tenant_id, p_colaborador_cpf, p_data, v_cid);

  INSERT INTO public.ponto_diario (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
    entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status, observacao
  ) VALUES (
    p_tenant_id, v_eid, v_cid, v_cnome, p_colaborador_cpf, p_data,
    c.o_pent, c.o_salm, c.o_ralm, c.o_usai, c.o_horas, c.o_status, c.o_obs
  )
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET
    empresa_id = COALESCE(EXCLUDED.empresa_id, public.ponto_diario.empresa_id),
    colaborador_nome = EXCLUDED.colaborador_nome,
    entrada = EXCLUDED.entrada, saida_almoco = EXCLUDED.saida_almoco,
    retorno_almoco = EXCLUDED.retorno_almoco, saida = EXCLUDED.saida,
    horas_trabalhadas = EXCLUDED.horas_trabalhadas,
    status = CASE WHEN public.ponto_diario.status = 'justificado' THEN 'justificado' ELSE EXCLUDED.status END,
    observacao = CASE WHEN public.ponto_diario.status = 'justificado'
                        AND public.ponto_diario.observacao LIKE 'Abonado por afastamento%'
                      THEN public.ponto_diario.observacao ELSE EXCLUDED.observacao END,
    updated_at = now();
END;
$function$;

-- ---- _ponto_grava_abono: arbiter da chave atualizado (unica mudanca) ----
CREATE OR REPLACE FUNCTION public._ponto_grava_abono(p_tenant_id uuid, p_colaborador_id uuid, p_colaborador_nome text, p_colaborador_cpf text, p_data date, p_observacao text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_colaborador_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.ponto_diario (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
    entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status, observacao
  ) VALUES (
    p_tenant_id, public.ponto_empresa_do_colaborador(p_colaborador_id),
    p_colaborador_id, p_colaborador_nome, p_colaborador_cpf, p_data,
    NULL, NULL, NULL, NULL, make_interval(mins => 0), 'justificado', p_observacao
  )
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
  DO UPDATE SET
    empresa_id = COALESCE(EXCLUDED.empresa_id, public.ponto_diario.empresa_id),
    status = 'justificado', observacao = EXCLUDED.observacao, updated_at = now();
END;
$function$;

-- ---- Remove a sobrecarga ORFA de 7 args de _ponto_grava_abono ----
-- Drift de producao: uma versao de 7 argumentos (…, p_tipo_dia text) foi criada
-- direto na producao no passado, superada depois pela versao de 6 args (os
-- chamadores migraram) e nunca removida. Ela NAO esta no repositorio, NADA no
-- codigo atual a chama, e ainda usava o arbiter antigo de 3 colunas — quebraria
-- em execucao agora que este pacote troca o indice de ponto_diario. IF EXISTS:
-- no-op onde ela nao existe (teste/homologacao ja limpa); remove onde existe.
DROP FUNCTION IF EXISTS public._ponto_grava_abono(uuid, uuid, text, text, date, text, text);

-- ---- justificar_ponto_por_atestado: arbiter da chave atualizado (unica mudanca) ----
CREATE OR REPLACE FUNCTION public.justificar_ponto_por_atestado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_data_inicio date;
  v_data_fim date;
  v_dia date;
BEGIN
  IF NEW.data_inicio_afastamento IS NULL THEN
    RETURN NEW;
  END IF;

  -- Atestado por horas reduz apenas a jornada do dia inicial. A consolidação
  -- específica já é executada por trg_consolida_atestado; jamais expandir
  -- dias_afastamento como se fosse um atestado de dia inteiro.
  IF COALESCE(NEW.unidade_afastamento, 'dias') = 'horas' THEN
    RETURN NEW;
  END IF;

  v_data_inicio := NEW.data_inicio_afastamento::date;
  v_data_fim := COALESCE(
    NEW.data_fim_afastamento::date,
    v_data_inicio + GREATEST(COALESCE(NEW.dias_afastamento, 1), 1) - 1
  );

  UPDATE public.ponto_diario
  SET status = 'justificado',
      observacao = COALESCE(observacao, '') || ' [Atestado médico - ' || COALESCE(NEW.profissional_nome, 'N/I') || ' - CID: ' || COALESCE(NEW.cid_codigo, 'N/I') || ']'
  WHERE tenant_id = NEW.tenant_id
    AND regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') = regexp_replace(NEW.colaborador_cpf, '[^0-9]', '', 'g')
    AND data BETWEEN v_data_inicio AND v_data_fim
    AND status IN ('falta', 'atraso', 'incompleto');

  v_dia := v_data_inicio;
  WHILE v_dia <= v_data_fim LOOP
    INSERT INTO public.ponto_diario (
      tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data, status, observacao, horas_trabalhadas, tipo_dia
    ) VALUES (
      NEW.tenant_id,
      COALESCE(NEW.colaborador_id, gen_random_uuid()),
      NEW.colaborador_nome,
      NEW.colaborador_cpf,
      v_dia,
      'justificado',
      'Atestado médico - ' || COALESCE(NEW.profissional_nome, 'N/I') || ' - ' || COALESCE(NEW.dias_afastamento::text, '1') || ' dia(s)',
      interval '0',
      'atestado'
    )
    ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)) DO UPDATE
    SET status = 'justificado',
        observacao = EXCLUDED.observacao,
        tipo_dia = 'atestado'
    WHERE ponto_diario.status IN ('falta', 'atraso', 'incompleto');

    v_dia := v_dia + 1;
  END LOOP;

  RETURN NEW;
END;
$function$;

-- ---- registrar_ferias_no_ponto: arbiter da chave atualizado (unica mudanca) ----
CREATE OR REPLACE FUNCTION public.registrar_ferias_no_ponto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_dia DATE;
  v_data_inicio DATE;
  v_data_fim DATE;
BEGIN
  -- Only process when status changes to 'assinado'
  IF NEW.status != 'assinado' THEN
    RETURN NEW;
  END IF;
  
  -- Skip if old status was already 'assinado' (no re-process)
  IF TG_OP = 'UPDATE' AND OLD.status = 'assinado' THEN
    RETURN NEW;
  END IF;

  v_data_inicio := NEW.data_inicio_ferias;
  v_data_fim := NEW.data_fim_ferias;

  IF v_data_inicio IS NULL OR v_data_fim IS NULL THEN
    RETURN NEW;
  END IF;

  v_dia := v_data_inicio;
  WHILE v_dia <= v_data_fim LOOP
    INSERT INTO public.ponto_diario (
      tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data, status, observacao, horas_trabalhadas
    ) VALUES (
      NEW.tenant_id,
      gen_random_uuid(),
      NEW.colaborador_nome,
      NEW.colaborador_cpf,
      v_dia,
      'justificado',
      'Férias - ' || NEW.dias_ferias || ' dias (' || NEW.data_inicio_ferias::TEXT || ' a ' || NEW.data_fim_ferias::TEXT || ')',
      INTERVAL '0'
    )
    ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)) DO UPDATE
    SET status = 'justificado',
        observacao = EXCLUDED.observacao;

    v_dia := v_dia + 1;
  END LOOP;

  RETURN NEW;
END;
$function$;

-- ---- afastamento_sincroniza_ponto: arbiter da chave atualizado (unica mudanca) ----
CREATE OR REPLACE FUNCTION public.afastamento_sincroniza_ponto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_data           DATE;
    v_limite         DATE;
    v_colaborador_id UUID;
    v_cpf            TEXT;
    v_motivo         TEXT;
    v_observacao     TEXT;
BEGIN
    -- Só reage a insert ou a mudanca real de periodo/status
    IF NOT (TG_OP = 'INSERT'
            OR (TG_OP = 'UPDATE'
                AND (OLD.data_inicio IS DISTINCT FROM NEW.data_inicio
                  OR OLD.data_fim    IS DISTINCT FROM NEW.data_fim
                  OR OLD.status      IS DISTINCT FROM NEW.status))) THEN
        RETURN NEW;
    END IF;

    IF NEW.status NOT IN ('ativo', 'beneficio_inss') THEN
        RETURN NEW;
    END IF;

    -- ponto_diario casa por CPF (constraint unique_ponto_diario). Sem CPF nao
    -- ha como fazer o upsert com seguranca.
    v_cpf := NEW.colaborador_cpf;
    IF v_cpf IS NULL OR btrim(v_cpf) = '' THEN
        RETURN NEW;
    END IF;

    -- colaborador_id do afastamento e sempre null hoje; resolve pela admissao.
    v_colaborador_id := NEW.colaborador_id;
    IF v_colaborador_id IS NULL THEN
        SELECT a.id INTO v_colaborador_id
          FROM public.admissoes a
         WHERE a.tenant_id = NEW.tenant_id
           AND a.cpf = v_cpf
           AND a.status = 'concluido'
         ORDER BY a.created_at DESC
         LIMIT 1;
    END IF;

    -- ponto_diario.colaborador_id e NOT NULL. Sem conseguir resolver, pula a
    -- sincronizacao em vez de abortar a criacao do afastamento.
    IF v_colaborador_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_motivo     := COALESCE(NEW.motivo_principal::text, 'Motivo nao informado');
    v_observacao := 'Abonado: Afastamento (' || v_motivo || ')';

    v_data   := NEW.data_inicio;
    -- Teto de 2 anos como trava de seguranca para prazo indeterminado
    v_limite := LEAST(COALESCE(NEW.data_fim, CURRENT_DATE), NEW.data_inicio + 730);

    WHILE v_data <= v_limite LOOP
        INSERT INTO public.ponto_diario (
            tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
            data, status, observacao
        ) VALUES (
            NEW.tenant_id, NEW.empresa_id, v_colaborador_id, NEW.colaborador_nome, v_cpf,
            v_data, 'justificado', v_observacao
        )
        ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
        DO UPDATE SET status     = 'justificado',
                      observacao = EXCLUDED.observacao;

        v_data := v_data + 1;
    END LOOP;

    RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------

-- ============================================================================
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | 5 | OK
-- ============================================================================
SELECT
  (SELECT count(*) FROM pg_indexes WHERE schemaname='public'
     AND indexname='unique_ponto_diario'
     AND indexdef ILIKE '%COALESCE(empresa_id%') = 1                 AS chave_por_vinculo,

  (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
     AND tgname='trg_ponto_diario_reconcilia_empresa') = 1           AS gatilho_reconciliacao,

  NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN ('consolidar_ponto_diario_manual','_ponto_grava_abono',
                        'justificar_ponto_por_atestado','registrar_ferias_no_ponto',
                        'afastamento_sincroniza_ponto')
      AND pg_get_functiondef(p.oid) ~ 'ON CONFLICT \(tenant_id, colaborador_cpf, data\)([^,]|$)'
  )                                                                  AS escritores_sem_arbiter_antigo,

  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN ('consolidar_ponto_diario_manual','_ponto_grava_abono',
                        'justificar_ponto_por_atestado','registrar_ferias_no_ponto',
                        'afastamento_sincroniza_ponto')
      AND pg_get_functiondef(p.oid) LIKE '%COALESCE(empresa_id%00000000%') AS escritores_migrados,

  CASE
    WHEN (SELECT count(*) FROM pg_indexes WHERE schemaname='public'
            AND indexname='unique_ponto_diario' AND indexdef ILIKE '%COALESCE(empresa_id%') = 0
      THEN 'ERRO: a chave nova nao foi criada'
    WHEN (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
            AND tgname='trg_ponto_diario_reconcilia_empresa') = 0
      THEN 'ERRO: o gatilho de reconciliacao nao foi criado — dia de vinculo unico pode partir'
    WHEN EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prokind='f'
        AND p.proname IN ('consolidar_ponto_diario_manual','_ponto_grava_abono',
                          'justificar_ponto_por_atestado','registrar_ferias_no_ponto',
                          'afastamento_sincroniza_ponto')
        AND pg_get_functiondef(p.oid) ~ 'ON CONFLICT \(tenant_id, colaborador_cpf, data\)([^,]|$)')
      THEN 'ERRO: algum escritor ainda usa o arbiter antigo — vai quebrar em execucao'
    ELSE 'OK'
  END                                                                AS erro_tecnico;


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
            WHERE parte = 2 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 2 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_diario_reconcilia_empresa', NULL),
    ('funcao', 'consolidar_ponto_diario_manual', ' || to_char(v_ferias.data_inicio,'),
    ('funcao', '_ponto_grava_abono', NULL),
    ('funcao', 'justificar_ponto_por_atestado', ') = regexp_replace(NEW.colaborador_cpf, '),
    ('funcao', 'registrar_ferias_no_ponto', ' || NEW.data_inicio_ferias::TEXT || '),
    ('funcao', 'afastamento_sincroniza_ponto', NULL),
    ('gatilho', 'trg_ponto_diario_reconcilia_empresa', NULL),
    ('indice', 'unique_ponto_diario', NULL)
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
  WHERE v.parte = 2
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
