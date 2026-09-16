-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 05 de 16: Integridade e imutabilidade do registro
--
-- Cadeia de hash encadeada e conferivel, desconsideracao de marcacao por
-- acrescimo (nunca apagando), deteccao de marcacoes uniformes, monitoramento
-- do relogio contra a Hora Legal Brasileira e reabertura formal de
-- competencia fechada.
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
--   * script_ponto_onda2_cadeia_hash.sql
--   * script_ponto_onda2_desconsiderar_marcacao.sql
--   * script_ponto_onda2_marcacoes_uniformes.sql
--   * script_ponto_onda2_relogio_e_origem.sql
--   * script_ponto_onda2_reabertura_competencia.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_ponto_onda2_cadeia_hash.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 2 (parte 1): cadeia de hash encadeado + verificação
-- Alvos: coluna hash_anterior, gerar_hash_marcacao (trigger), ponto_verificar_cadeia_hash,
--        ponto_cadeia_hash_monitorar
-- PONTO-191
--
-- O QUE FAZ
--   O hash de cada marcação nova passa a incorporar o hash da marcação anterior
--   da mesma sequência (por NSR/estabelecimento) — remover uma linha passa a
--   quebrar a cadeia. Uma rotina de verificação recomputa cada hash (detecta
--   alteração de conteúdo) e confere o encadeamento e a continuidade da NSR
--   (detecta remoção). Uma companheira agendável alerta o RH.
--
-- RETROCOMPATÍVEL: o append é de COALESCE(hash_anterior,''), que é vazio para as
--   marcações antigas — e append de '' não muda o sha256. As marcações já
--   gravadas continuam com o MESMO hash e verificam limpas; nada é reprocessado.
--
-- SEGURO E IDEMPOTENTE: ADD COLUMN IF NOT EXISTS + CREATE OR REPLACE. A geração
--   do hash é defensiva: se a leitura do hash anterior falhar, a marcação é
--   gravada mesmo assim (sem encadear). Sem backfill.
-- ============================================================================

ALTER TABLE public.ponto_marcacoes
  ADD COLUMN IF NOT EXISTS hash_anterior text;

COMMENT ON COLUMN public.ponto_marcacoes.hash_anterior IS
  'Hash da marcacao anterior na mesma sequencia (NSR/estabelecimento). Encadeia a prova: remover uma linha quebra a cadeia. Nulo na primeira da cadeia e nas marcacoes anteriores ao encadeamento.';

-- ---------------------------------------------------------------------------
-- Geração do hash, agora ENCADEADA (BEFORE INSERT; roda depois da atribuição
-- do NSR, cuja trigger vem antes na ordem alfabética).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.gerar_hash_marcacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sentinela uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  -- Encadeia com o hash da marcação anterior (NSR imediatamente menor no mesmo
  -- balde tenant/estabelecimento). Nunca deixa a leitura derrubar o insert.
  IF NEW.nsr IS NOT NULL AND NEW.tenant_id IS NOT NULL THEN
    BEGIN
      SELECT m.hash_marcacao
        INTO NEW.hash_anterior
      FROM public.ponto_marcacoes m
      WHERE m.tenant_id = NEW.tenant_id
        AND COALESCE(m.empresa_id, v_sentinela) = COALESCE(NEW.empresa_id, v_sentinela)
        AND m.nsr = NEW.nsr - 1
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      NEW.hash_anterior := NULL;
    END;
  END IF;

  -- Instante fixado em UTC: `created_at` e timestamptz e o seu ::text depende do
  -- FUSO DA SESSAO. Sob UTC esta forma e byte-identica ao ::text solto (logo
  -- reproduz os hashes ja gravados), e sob qualquer outro fuso continua igual.
  NEW.hash_marcacao := encode(
    sha256(
      (NEW.colaborador_cpf || NEW.data_marcacao::text || NEW.hora_marcacao::text
       || NEW.tipo_marcacao || ((NEW.created_at AT TIME ZONE 'UTC')::text || '+00')
       || COALESCE(NEW.hash_anterior, ''))::bytea
    ),
    'hex'
  );
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Verificação da cadeia (somente leitura): devolve as quebras encontradas.
--   · hash_adulterado : o hash gravado não confere com o recomputado do conteúdo
--   · cadeia_quebrada : o hash_anterior não bate com o hash da marcação anterior
--   · nsr_faltante    : há um salto na numeração sequencial (linha removida)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_verificar_cadeia_hash(
  p_tenant_id uuid DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS TABLE(
  tenant_id uuid,
  empresa_id uuid,
  nsr bigint,
  marcacao_id uuid,
  tipo_quebra text,
  detalhe text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Verificacao da cadeia: recomputa cada hash_marcacao e confere o
  -- encadeamento pelo hash_anterior e a continuidade da NSR.
  WITH marcs AS (
    SELECT m.id, m.tenant_id, m.empresa_id, m.nsr,
           m.hash_marcacao, m.hash_anterior,
           m.colaborador_cpf, m.data_marcacao, m.hora_marcacao,
           m.tipo_marcacao, m.created_at,
           lag(m.hash_marcacao) OVER w AS prev_hash,
           lag(m.nsr)           OVER w AS prev_nsr
    FROM public.ponto_marcacoes m
    WHERE m.hash_marcacao IS NOT NULL
      AND m.nsr IS NOT NULL
      AND (p_tenant_id  IS NULL OR m.tenant_id  = p_tenant_id)
      AND (p_empresa_id IS NULL OR m.empresa_id = p_empresa_id)
    WINDOW w AS (
      PARTITION BY m.tenant_id, COALESCE(m.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
      ORDER BY m.nsr
    )
  )
  SELECT tenant_id, empresa_id, nsr, id AS marcacao_id,
         CASE
           WHEN encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
                    || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
                <> hash_marcacao
             THEN 'hash_adulterado'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'cadeia_quebrada'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN 'nsr_faltante'
         END AS tipo_quebra,
         CASE
           WHEN encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
                    || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
                <> hash_marcacao
             THEN 'Hash gravado nao confere com o recomputado do conteudo (marcacao alterada).'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'Encadeamento rompido: o hash_anterior nao bate com o hash da marcacao anterior.'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN format('Salto de NSR (%s -> %s): pode haver marcacao removida.', prev_nsr, nsr)
         END AS detalhe
  FROM marcs
  WHERE encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
             || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
             <> hash_marcacao
     OR (hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash)
     OR (prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1)
  ORDER BY tenant_id, empresa_id NULLS FIRST, nsr;
$$;

COMMENT ON FUNCTION public.ponto_verificar_cadeia_hash(uuid, uuid) IS
  'Verificacao da cadeia de hash das marcacoes: recomputa cada hash_marcacao e confere o encadeamento (hash_anterior) e a continuidade da NSR. Devolve as quebras. Somente leitura.';

-- ---------------------------------------------------------------------------
-- Companheira agendável: roda a verificação e alerta o RH por tenant quando
-- houver quebra. Idempotente por dia (um alerta por tenant/dia).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_cadeia_hash_monitorar()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_hoje date := CURRENT_DATE;
  v_total int := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT q.tenant_id, count(*) AS quebras
    FROM public.ponto_verificar_cadeia_hash() q
    GROUP BY q.tenant_id
  LOOP
    v_total := v_total + r.quebras;
    INSERT INTO public.ponto_alertas
      (tenant_id, tipo, severidade, titulo, descricao, data_referencia)
    SELECT r.tenant_id, 'cadeia_hash_quebrada', 'critica',
           'Cadeia de hash das marcacoes com quebra',
           format('Verificacao encontrou %s quebra(s) na cadeia de hash das marcacoes. '
               || 'Investigar remocao ou alteracao direta de marcacao.', r.quebras),
           v_hoje
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = r.tenant_id
        AND a.tipo = 'cadeia_hash_quebrada'
        AND a.data_referencia = v_hoje
    );
  END LOOP;
  RETURN v_total;
END;
$$;

COMMENT ON FUNCTION public.ponto_cadeia_hash_monitorar() IS
  'Roda ponto_verificar_cadeia_hash e emite alerta ao RH por tenant quando ha quebra na cadeia. Idempotente por dia. Para agendar via pg_cron.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | 0 | OK
--   coluna_criada    : t  (hash_anterior existe)
--   hash_encadeado   : t  (gerar_hash_marcacao incorpora o hash anterior)
--   verificacao_ok   : t  (rotina de verificação existe)
--   quebras_hoje     : 0  (a base atual verifica limpa — sem falso positivo)
-- ---------------------------------------------------------------------------
SELECT
  (EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='hash_anterior')) AS coluna_criada,
  (position('hash_anterior' in pg_get_functiondef('public.gerar_hash_marcacao()'::regprocedure)) > 0) AS hash_encadeado,
  (to_regprocedure('public.ponto_verificar_cadeia_hash(uuid,uuid)') IS NOT NULL) AS verificacao_ok,
  (SELECT count(*) FROM public.ponto_verificar_cadeia_hash()) AS quebras_hoje,
  CASE
    WHEN (EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='hash_anterior'))
     AND position('hash_anterior' in pg_get_functiondef('public.gerar_hash_marcacao()'::regprocedure)) > 0
     AND to_regprocedure('public.ponto_verificar_cadeia_hash(uuid,uuid)') IS NOT NULL
     AND (SELECT count(*) FROM public.ponto_verificar_cadeia_hash()) = 0
      THEN 'OK'
    ELSE 'CONFERIR: se quebras_hoje > 0, ha marcacao adulterada/removida em producao (investigar); o resto deve ser t'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda2_desconsiderar_marcacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 2 (parte 5): correção por acréscimo (desconsiderar, nunca apagar)
-- Alvos: colunas desconsiderada* em ponto_marcacoes; desconsiderar_marcacao_ponto;
--        excluir_marcacao_ponto (passa a delegar); processar_ajuste_ponto;
--        _ponto_calc_dia, ponto_reordena_tipos_dia, ponto_corte_virada
-- PONTO-004 (resto)
--
-- O QUE FAZ
--   A batida original nunca é apagada. Passa a ser DESCONSIDERADA: fica no acervo
--   (e na cadeia de hash), marcada com motivo e responsável, e sai do cálculo do
--   dia. Fecha o buraco dos RPCs que ainda apagavam pelo flag app.allow_ponto_delete.
--   (Portaria 671/2021 veda apagar; CLT art. 74; Súmula 338 do TST.)
--
-- ATENÇÃO — TEM PARTE DE TELA. Este script cuida do BANCO. A tela (o botão
--   "Excluir" do espelho vira "Desconsiderar", com motivo) vai no código do
--   frontend e entra em produção pelo **Publicar no Lovable** — não por este
--   script. Enquanto a tela antiga não for publicada, o botão "Excluir" já se
--   comporta como desconsiderar (o RPC antigo passou a delegar), só com o rótulo
--   antigo.
--
-- Aditivo e idempotente (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE). Sem backfill.
-- ============================================================================

ALTER TABLE public.ponto_marcacoes
  ADD COLUMN IF NOT EXISTS desconsiderada        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS desconsiderada_motivo text,
  ADD COLUMN IF NOT EXISTS desconsiderada_por    text,
  ADD COLUMN IF NOT EXISTS desconsiderada_em     timestamptz;

COMMENT ON COLUMN public.ponto_marcacoes.desconsiderada IS
  'Marcacao mantida no acervo mas retirada do calculo do dia (correcao por acrescimo). A batida original nunca e apagada (Portaria 671; Sumula 338).';

-- RPC próprio: desconsiderar (não apaga) ------------------------------------
CREATE OR REPLACE FUNCTION public.desconsiderar_marcacao_ponto(
  p_marcacao_id uuid,
  p_motivo      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_marc public.ponto_marcacoes%ROWTYPE;
  v_has_access boolean := false;
  v_is_gestor boolean := false;
  v_vinculo_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Não autenticado'; END IF;

  SELECT * INTO v_marc FROM public.ponto_marcacoes WHERE id = p_marcacao_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Marcação não encontrada'; END IF;

  -- Via 1: cadastro ativo no tenant
  SELECT EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_marc.tenant_id AND ub.status = 'ativo'
  ) INTO v_has_access;

  -- Via 2: vínculo multi-empresa ativo no tenant
  IF NOT v_has_access THEN
    SELECT uv.tipo_vinculo::text INTO v_vinculo_role
    FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
    WHERE ub2.auth_user_id = v_uid
      AND uv.tenant_id = v_marc.tenant_id
      AND uv.status = 'ativo'
      AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE)
    LIMIT 1;
    IF v_vinculo_role IS NOT NULL THEN
      v_has_access := true;
      v_is_gestor := v_vinculo_role IN ('gestor','administrador','rh','rh_dp');
    END IF;
  END IF;

  -- Via 3: perfil no tenant
  IF NOT v_has_access THEN
    SELECT EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.user_id = v_uid AND p.tenant_id = v_marc.tenant_id
    ) INTO v_has_access;
  END IF;

  IF NOT v_has_access THEN RAISE EXCEPTION 'Sem acesso a este tenant'; END IF;

  -- Papel mínimo: gestor/RH
  IF NOT v_is_gestor THEN
    v_is_gestor :=
      public.has_role(v_uid, 'manager'::public.app_role)
      OR public.has_role(v_uid, 'admin'::public.app_role)
      OR public.has_role(v_uid, 'owner'::public.app_role)
      OR public.is_superadmin(v_uid);
  END IF;
  IF NOT v_is_gestor THEN
    SELECT EXISTS (
      SELECT 1 FROM public.usuarios_base ub3
      WHERE ub3.auth_user_id = v_uid
        AND ub3.tipo_usuario IN ('gestor','administrador','rh_dp')
    ) INTO v_is_gestor;
  END IF;
  IF NOT v_is_gestor THEN
    RAISE EXCEPTION 'Apenas gestor/RH pode desconsiderar marcações';
  END IF;

  IF COALESCE(v_marc.desconsiderada, false) THEN
    RETURN jsonb_build_object('success', true, 'ja_desconsiderada', true);
  END IF;

  -- Trilha (mantém a batida; registra a desconsideração).
  INSERT INTO public.ponto_audit_log (
    tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id
  ) VALUES (
    v_marc.tenant_id, 'ponto_marcacoes', v_marc.id, 'AJUSTE',
    to_jsonb(v_marc),
    jsonb_build_object('operacao','DESCONSIDERACAO',
                       'motivo', COALESCE(NULLIF(btrim(p_motivo),''), 'Marcacao duplicada/incorreta'),
                       'por', v_uid),
    v_uid
  );

  -- Correção por ACRÉSCIMO: a batida fica, marcada como desconsiderada.
  UPDATE public.ponto_marcacoes
     SET desconsiderada = true,
         desconsiderada_motivo = COALESCE(NULLIF(btrim(p_motivo),''), 'Marcacao duplicada/incorreta'),
         desconsiderada_por = v_uid::text,
         desconsiderada_em = now()
   WHERE id = p_marcacao_id;

  PERFORM public.consolidar_ponto_diario_manual(
    v_marc.tenant_id, v_marc.colaborador_cpf, v_marc.data_marcacao
  );

  RETURN jsonb_build_object('success', true, 'desconsiderada', true);
END;
$function$;

COMMENT ON FUNCTION public.desconsiderar_marcacao_ponto(uuid, text) IS
  'Desconsidera uma marcacao (correcao por acrescimo): mantem a batida no acervo, marca como desconsiderada com motivo/responsavel e retira do calculo. Nunca apaga (Portaria 671; Sumula 338). Papel minimo gestor/RH.';

GRANT EXECUTE ON FUNCTION public.desconsiderar_marcacao_ponto(uuid, text) TO authenticated;

-- Compatibilidade: o antigo "Excluir" passa a DESCONSIDERAR (não apaga mais).
CREATE OR REPLACE FUNCTION public.excluir_marcacao_ponto(p_marcacao_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN public.desconsiderar_marcacao_ponto(
    p_marcacao_id,
    'Marcacao duplicada/incorreta desconsiderada pela gestao'
  );
END;
$function$;

COMMENT ON FUNCTION public.excluir_marcacao_ponto(uuid) IS
  'Mantido por compatibilidade: agora DELEGA para desconsiderar_marcacao_ponto (correcao por acrescimo). Nao apaga a marcacao.';


-- Consolidacao diaria: ignora as marcacoes desconsideradas.
CREATE OR REPLACE FUNCTION public._ponto_calc_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_cid uuid, OUT o_pent time without time zone, OUT o_salm time without time zone, OUT o_ralm time without time zone, OUT o_usai time without time zone, OUT o_horas interval, OUT o_status text, OUT o_obs text)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_marc RECORD;
  v_count INT := 0;
  v_ins TIME[] := '{}'; v_outs TIME[] := '{}';
  v_abr TIME; v_classe TEXT; v_esp TEXT := 'in';
  v_min INT := 0; v_dif INT;
  v_anom BOOLEAN := false; v_aberta BOOLEAN := false;
  v_pend BOOLEAN := false; v_esc RECORD;
  v_corte TIME := public.ponto_corte_virada(p_tenant_id, p_colaborador_cpf, p_data);
BEGIN
  FOR v_marc IN
    SELECT hora_marcacao, tipo_marcacao FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
    ORDER BY (EXTRACT(EPOCH FROM hora_marcacao)
              + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                     THEN 86400 ELSE 0 END) ASC,
             created_at ASC
  LOOP
    v_count := v_count + 1;
    v_classe := COALESCE(public.ponto_classifica_tipo(v_marc.tipo_marcacao), v_esp);
    IF v_classe = 'in' THEN
      o_pent := COALESCE(o_pent, v_marc.hora_marcacao);
      v_ins := v_ins || v_marc.hora_marcacao;
      IF v_abr IS NOT NULL THEN v_anom := true; END IF;
      v_abr := v_marc.hora_marcacao; v_esp := 'out';
    ELSE
      IF v_abr IS NOT NULL THEN
        -- Trunca os segundos (FLOOR) para alinhar com a exibição do Espelho
        v_dif := FLOOR(EXTRACT(EPOCH FROM (v_marc.hora_marcacao - v_abr)) / 60)::INT;
        IF v_dif < 0 THEN v_dif := v_dif + 1440; END IF;
        v_min := v_min + GREATEST(0, v_dif);
        v_abr := NULL;
      ELSE
        v_anom := true;
      END IF;
      v_outs := v_outs || v_marc.hora_marcacao;
      o_usai := v_marc.hora_marcacao; v_esp := 'in';
    END IF;
  END LOOP;

  v_aberta := (v_abr IS NOT NULL);
  IF array_length(v_outs,1) >= 2 THEN
    o_salm := v_outs[1];
    SELECT t INTO o_ralm FROM unnest(v_ins) AS t WHERE t > v_outs[1] ORDER BY t ASC LIMIT 1;
  END IF;
  IF v_aberta AND array_length(v_outs,1) >= 1 AND array_length(v_ins,1) >= 2 THEN
    o_salm := v_outs[1];
    SELECT t INTO o_ralm FROM unnest(v_ins) AS t WHERE t > v_outs[1] ORDER BY t ASC LIMIT 1;
    o_usai := NULL;
  END IF;
  o_horas := make_interval(mins => v_min);

  SELECT EXISTS (SELECT 1 FROM public.ponto_ajustes
    WHERE tenant_id = p_tenant_id AND colaborador_cpf = p_colaborador_cpf
      AND data_referencia = p_data AND status = 'pendente') INTO v_pend;

  IF v_pend THEN o_status := 'ajuste_pendente';
  ELSIF v_count = 0 THEN o_status := 'falta';
  ELSIF v_aberta OR v_anom THEN o_status := 'incompleto';
  ELSE
    o_status := 'regular';
    SELECT * INTO v_esc FROM public.ponto_escala_do_dia(p_tenant_id, p_colaborador_cpf, p_cid, p_data);
    IF v_esc.hora_entrada IS NOT NULL AND o_pent IS NOT NULL
       AND o_pent > (v_esc.hora_entrada + make_interval(mins => v_esc.tolerancia_min)) THEN
      o_status := 'atraso';
    END IF;
  END IF;

  IF o_status = 'atraso' AND EXISTS (
    SELECT 1 FROM public.atestados a
    WHERE a.tenant_id = p_tenant_id AND a.colaborador_cpf = p_colaborador_cpf
      AND a.data_inicio_afastamento IS NOT NULL
      AND COALESCE(a.unidade_afastamento,'dias') = 'horas'
      AND a.data_inicio_afastamento <= p_data
      AND COALESCE(a.data_fim_afastamento, a.data_inicio_afastamento) >= p_data
  ) THEN
    o_status := 'regular';
    o_obs := COALESCE(NULLIF(o_obs, '') || ' ', '') || 'Atraso justificado por atestado de horas no dia.';
  END IF;

  IF v_anom AND NOT v_pend THEN
    o_obs := 'Sequência de marcações incompleta (entrada/saída sem par) — horas do período não pareado não contabilizadas. Solicite ajuste de ponto.';
  END IF;
END;
$function$;

-- Reordenacao de rotulos: ignora as desconsideradas.
CREATE OR REPLACE FUNCTION public.ponto_reordena_tipos_dia(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n       int;
  v_min_gap numeric;
  v_corte   time := public.ponto_corte_virada(p_tenant_id, p_colaborador_cpf, p_data);
  v_changed uuid[];
  v_id      uuid;
  v_antes   jsonb;
BEGIN
  -- Contagem e menor vão entre batidas JÁ na ordem cíclica (guarda de ruído).
  SELECT count(*), min(gap) INTO v_n, v_min_gap
  FROM (
    SELECT (ordk - lag(ordk) OVER (ORDER BY ordk)) / 60 AS gap
    FROM (
      SELECT EXTRACT(EPOCH FROM hora_marcacao)
             + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                    THEN 86400 ELSE 0 END AS ordk
      FROM public.ponto_marcacoes
      WHERE tenant_id = p_tenant_id
        AND colaborador_cpf = p_colaborador_cpf
        AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
    ) e
  ) g;

  IF v_n IS NULL OR v_n = 0
     OR v_n % 2 = 1
     OR (v_min_gap IS NOT NULL AND v_min_gap < 15) THEN
    RETURN false;
  END IF;

  -- Retrato de antes, para o log de auditoria.
  SELECT jsonb_agg(jsonb_build_object('hora', hora_marcacao, 'tipo', tipo_marcacao)
                   ORDER BY hora_marcacao)
    INTO v_antes
  FROM public.ponto_marcacoes
  WHERE tenant_id = p_tenant_id
    AND colaborador_cpf = p_colaborador_cpf
    AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false);

  PERFORM set_config('app.ponto_reordena', 'on', true);

  WITH reord AS (
    SELECT id,
           row_number() OVER (
             ORDER BY (EXTRACT(EPOCH FROM hora_marcacao)
                       + CASE WHEN v_corte IS NOT NULL AND hora_marcacao < v_corte
                              THEN 86400 ELSE 0 END),
                      created_at
           ) AS pos
    FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
  ), upd AS (
    UPDATE public.ponto_marcacoes m
    SET    tipo_marcacao = CASE WHEN r.pos % 2 = 1 THEN 'entrada' ELSE 'saida' END
    FROM   reord r
    WHERE  m.id = r.id
      AND  m.tipo_marcacao IS DISTINCT FROM
           (CASE WHEN r.pos % 2 = 1 THEN 'entrada' ELSE 'saida' END)
    RETURNING m.id
  )
  SELECT array_agg(id) INTO v_changed FROM upd;

  PERFORM set_config('app.ponto_reordena', 'off', true);

  IF v_changed IS NOT NULL THEN
    FOREACH v_id IN ARRAY v_changed LOOP
      BEGIN
        PERFORM public.classificar_marcacao_clt(v_id);
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- classificação CLT é auxiliar; nunca quebra o fluxo
      END;
    END LOOP;

    BEGIN
      INSERT INTO public.ponto_audit_log (
        tenant_id, tabela_origem, registro_id, acao,
        dados_anteriores, dados_novos, usuario_id
      )
      SELECT p_tenant_id, 'ponto_marcacoes', v_changed[1], 'AJUSTE',
             jsonb_build_object('operacao', 'REORDENACAO_ROTULOS',
                                'data', p_data, 'sequencia', v_antes),
             jsonb_build_object('operacao', 'REORDENACAO_ROTULOS',
                                'data', p_data,
                                'motivo', 'Batida incluída em horário anterior às existentes; '
                                       || 'rótulos entrada/saída reencaixados pelo relógio '
                                       || '(ordem cíclica, virada reconhecida). '
                                       || 'Nenhum horário foi alterado.',
                                'marcacoes_afetadas', to_jsonb(v_changed),
                                'sequencia', (
                                  SELECT jsonb_agg(jsonb_build_object('hora', hora_marcacao,
                                                                      'tipo', tipo_marcacao)
                                                   ORDER BY hora_marcacao)
                                  FROM public.ponto_marcacoes
                                  WHERE tenant_id = p_tenant_id
                                    AND colaborador_cpf = p_colaborador_cpf
                                    AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
                                )),
             auth.uid();
    EXCEPTION WHEN OTHERS THEN
      NULL;  -- auditoria é registro acessório; nunca derruba a aprovação
    END;
  END IF;

  RETURN (v_changed IS NOT NULL);
END;
$function$;

-- Corte da virada: ignora as desconsideradas.
CREATE OR REPLACE FUNCTION public.ponto_corte_virada(p_tenant_id uuid, p_colaborador_cpf text, p_data date)
 RETURNS time without time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH m AS (
    SELECT hora_marcacao AS h
    FROM public.ponto_marcacoes
    WHERE tenant_id = p_tenant_id
      AND colaborador_cpf = p_colaborador_cpf
      AND data_marcacao = p_data AND NOT COALESCE(desconsiderada, false)
  ),
  g AS (
    SELECT h, EXTRACT(EPOCH FROM (h - lag(h) OVER (ORDER BY h)))/60 AS gap
    FROM m
  ),
  stats AS (
    SELECT (SELECT max(gap) FROM g) AS max_int,
           1440 - EXTRACT(EPOCH FROM ((SELECT max(h) FROM m) - (SELECT min(h) FROM m)))/60 AS wrap_gap
  )
  SELECT CASE
           WHEN (SELECT count(*) FROM m) < 2 THEN NULL
           WHEN s.max_int > s.wrap_gap
             THEN (SELECT h FROM g WHERE gap = s.max_int ORDER BY h LIMIT 1)
           ELSE NULL
         END
  FROM stats s;
$function$;

-- processar_ajuste_ponto: correcao (tipo 'correcao') desconsidera em vez de apagar.
CREATE OR REPLACE FUNCTION public.processar_ajuste_ponto(p_ajuste_id uuid, p_aprovado boolean, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ajuste public.ponto_ajustes%ROWTYPE;
  v_has_access boolean := false;
  v_is_gestor boolean := false;
  v_vinculo_role text;
  v_aprovador_nome text;
  v_aprovador_cpf text;
  v_auto_lancado boolean := false;
  v_just_tipo_abono text;
  v_just_nome text;
  v_deve_abonar boolean := false;
  v_colab_uuid uuid;
  v_tipo text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Não autenticado'; END IF;

  SELECT * INTO v_ajuste FROM public.ponto_ajustes WHERE id = p_ajuste_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ajuste não encontrado'; END IF;
  IF v_ajuste.status <> 'pendente' THEN RAISE EXCEPTION 'Este ajuste já foi processado'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid AND ub.tenant_id = v_ajuste.tenant_id AND ub.status = 'ativo'
  ) INTO v_has_access;

  IF NOT v_has_access THEN
    SELECT uv.tipo_vinculo::text INTO v_vinculo_role
    FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub2 ON ub2.id = uv.usuario_id
    WHERE ub2.auth_user_id = v_uid
      AND uv.tenant_id = v_ajuste.tenant_id
      AND uv.status = 'ativo'
      AND (uv.data_fim IS NULL OR uv.data_fim >= CURRENT_DATE)
    LIMIT 1;
    IF v_vinculo_role IS NOT NULL THEN
      v_has_access := true;
      v_is_gestor := v_vinculo_role IN ('gestor','administrador','proprietario','rh');
    END IF;
  END IF;

  IF NOT v_has_access THEN
    SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = v_uid AND p.tenant_id = v_ajuste.tenant_id) INTO v_has_access;
  END IF;
  IF NOT v_has_access THEN RAISE EXCEPTION 'Sem acesso a este tenant'; END IF;

  IF NOT v_is_gestor THEN
    v_is_gestor :=
      public.has_role(v_uid, 'manager'::public.app_role)
      OR public.has_role(v_uid, 'admin'::public.app_role)
      OR public.has_role(v_uid, 'owner'::public.app_role)
      OR public.has_role(v_uid, 'superadmin'::public.app_role);
  END IF;

  IF NOT v_is_gestor THEN
    SELECT EXISTS (
      SELECT 1 FROM public.usuarios_base ub3
      WHERE ub3.auth_user_id = v_uid AND ub3.tipo_usuario IN ('gestor','administrador','proprietario','rh')
    ) INTO v_is_gestor;
  END IF;

  IF NOT v_is_gestor THEN RAISE EXCEPTION 'Apenas gestor/RH pode processar ajustes de ponto'; END IF;

  SELECT nome_completo, regexp_replace(COALESCE(cpf,''), '\D', '', 'g')
    INTO v_aprovador_nome, v_aprovador_cpf
  FROM public.usuarios_base
  WHERE auth_user_id = v_uid AND tenant_id = v_ajuste.tenant_id
  LIMIT 1;
  IF v_aprovador_nome IS NULL THEN
    SELECT nome_completo INTO v_aprovador_nome FROM public.profiles WHERE user_id = v_uid LIMIT 1;
  END IF;

  -- =========================================================
  -- Bloco 3 — Segregação de funções (MTP 671 / auditoria)
  -- 1) Ninguém aprova ajuste do PRÓPRIO ponto.
  -- 2) Quem lançou o ajuste e aprova o mesmo ajuste precisa
  --    justificar (observação >= 10 caracteres) e o registro
  --    fica marcado como auto-lançamento.
  -- =========================================================
  IF COALESCE(v_aprovador_cpf, '') <> ''
     AND regexp_replace(COALESCE(v_ajuste.colaborador_cpf,''), '\D', '', 'g') = v_aprovador_cpf THEN
    RAISE EXCEPTION 'Segregação de funções: não é permitido aprovar ou rejeitar ajuste do próprio ponto. Outro gestor/RH deve analisar.';
  END IF;

  v_auto_lancado := (v_ajuste.created_by IS NOT NULL AND v_ajuste.created_by = v_uid);

  IF v_auto_lancado AND p_aprovado AND length(COALESCE(btrim(p_observacao), '')) < 10 THEN
    RAISE EXCEPTION 'Você foi quem solicitou este ajuste. Informe uma observação de aprovação com no mínimo 10 caracteres justificando o auto-lançamento.';
  END IF;

  UPDATE public.ponto_ajustes
  SET status = CASE WHEN p_aprovado THEN 'aprovado' ELSE 'rejeitado' END,
      aprovado_por = v_uid,
      aprovado_por_nome = v_aprovador_nome,
      data_aprovacao = now(),
      observacao_aprovador = p_observacao,
      auto_lancado = v_auto_lancado
  WHERE id = p_ajuste_id;

  IF v_auto_lancado THEN
    BEGIN
      INSERT INTO public.audit_logs (tenant_id, user_id, acao, entidade, entidade_id, detalhes)
      VALUES (
        v_ajuste.tenant_id, v_uid,
        CASE WHEN p_aprovado THEN 'ajuste_ponto_auto_aprovado' ELSE 'ajuste_ponto_auto_rejeitado' END,
        'ponto_ajustes', p_ajuste_id,
        jsonb_build_object(
          'colaborador_cpf', v_ajuste.colaborador_cpf,
          'data_referencia', v_ajuste.data_referencia,
          'observacao', p_observacao,
          'aprovador_nome', v_aprovador_nome
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  IF p_aprovado AND v_ajuste.justificativa_id IS NOT NULL THEN
    SELECT tipo_abono, nome INTO v_just_tipo_abono, v_just_nome
    FROM public.ponto_justificativas WHERE id = v_ajuste.justificativa_id;
    v_deve_abonar := (v_just_tipo_abono = 'sim')
      OR (v_just_tipo_abono = 'configuravel' AND COALESCE(v_ajuste.abonar_se_aprovado, false));
    IF v_deve_abonar THEN
      BEGIN v_colab_uuid := v_ajuste.colaborador_id::uuid;
      EXCEPTION WHEN OTHERS THEN v_colab_uuid := NULL;
      END;
    END IF;
  END IF;

  IF NOT p_aprovado OR v_ajuste.tipo_ajuste IN ('justificativa', 'abono') THEN
    IF v_deve_abonar AND v_colab_uuid IS NOT NULL AND COALESCE(v_ajuste.dia_inteiro, false) THEN
      PERFORM public._ponto_gera_batidas_dia_inteiro(
        v_ajuste.tenant_id, v_colab_uuid, v_ajuste.colaborador_nome,
        v_ajuste.colaborador_cpf, v_ajuste.data_referencia, v_ajuste.id, v_uid
      );
    END IF;
    PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);
    IF v_deve_abonar AND v_colab_uuid IS NOT NULL THEN
      PERFORM public._ponto_grava_abono(
        v_ajuste.tenant_id, v_colab_uuid, v_ajuste.colaborador_nome,
        v_ajuste.colaborador_cpf, v_ajuste.data_referencia,
        COALESCE(v_just_nome, v_ajuste.motivo)
      );
    END IF;
    BEGIN
      PERFORM public.apurar_banco_horas_colaborador(
        v_ajuste.tenant_id, v_ajuste.colaborador_cpf, to_char(v_ajuste.data_referencia, 'YYYY-MM')
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN jsonb_build_object('success', true, 'auto_lancado', v_auto_lancado);
  END IF;

  -- ── Ajustes de marcação (inclusão / correção) ────────────────────────
  -- Colunas reais da tabela: data_marcacao (date) + hora_marcacao (time) +
  -- tipo_marcacao. Lógica restaurada da versão de 24/07, que traz as travas
  -- construídas ao longo de meses de correções.
  v_tipo := COALESCE(v_ajuste.tipo_marcacao, 'batida');
  IF v_tipo = 'saida_almoco'   THEN v_tipo := 'saida';   END IF;
  IF v_tipo = 'retorno_almoco' THEN v_tipo := 'entrada'; END IF;

  -- CORREÇÃO SEGURA: só apaga quando é correção COM hora_original explícita.
  -- Sem essa trava, uma inclusão apagaria em massa as batidas do mesmo tipo
  -- no dia (problema real já vivido neste sistema).
  IF v_ajuste.tipo_ajuste = 'correcao' AND v_ajuste.hora_original IS NOT NULL THEN
    -- Correcao por ACRESCIMO: a batida original nao e apagada, e desconsiderada.
    UPDATE public.ponto_marcacoes
       SET desconsiderada = true,
           desconsiderada_motivo = COALESCE(NULLIF(btrim(v_ajuste.motivo), ''), 'Correcao por ajuste aprovado'),
           desconsiderada_por = COALESCE(v_ajuste.aprovado_por::text, v_ajuste.created_by::text),
           desconsiderada_em = now()
     WHERE tenant_id = v_ajuste.tenant_id
       AND colaborador_cpf = v_ajuste.colaborador_cpf
       AND data_marcacao = v_ajuste.data_referencia
       AND to_char(hora_marcacao, 'HH24:MI') = to_char(v_ajuste.hora_original, 'HH24:MI')
       AND NOT COALESCE(desconsiderada, false);
  END IF;

  -- Não duplica se a batida solicitada já existir no minuto.
  IF v_ajuste.hora_solicitada IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ponto_marcacoes
    WHERE tenant_id = v_ajuste.tenant_id
      AND colaborador_cpf = v_ajuste.colaborador_cpf
      AND data_marcacao = v_ajuste.data_referencia
      AND tipo_marcacao = v_tipo
      AND to_char(hora_marcacao, 'HH24:MI') = to_char(v_ajuste.hora_solicitada, 'HH24:MI')
  ) THEN
    INSERT INTO public.ponto_marcacoes (
      tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, created_by, hash_marcacao
    ) VALUES (
      v_ajuste.tenant_id, v_ajuste.empresa_id, v_ajuste.colaborador_id,
      v_ajuste.colaborador_nome, v_ajuste.colaborador_cpf,
      v_ajuste.data_referencia, v_ajuste.hora_solicitada, v_tipo, false, v_uid,
      'AJUSTE-' || p_ajuste_id
    );
  END IF;

  PERFORM public.consolidar_ponto_diario_manual(v_ajuste.tenant_id, v_ajuste.colaborador_cpf, v_ajuste.data_referencia);
  BEGIN
    PERFORM public.apurar_banco_horas_colaborador(
      v_ajuste.tenant_id, v_ajuste.colaborador_cpf, to_char(v_ajuste.data_referencia, 'YYYY-MM')
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true, 'auto_lancado', v_auto_lancado);
END;
$function$;

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | t | OK
--   coluna_desconsid   : t  (ponto_marcacoes.desconsiderada existe)
--   rpc_desconsiderar  : t  (desconsiderar_marcacao_ponto existe)
--   excluir_delega     : t  (excluir_marcacao_ponto agora delega, nao apaga)
--   calc_ignora        : t  (_ponto_calc_dia ignora desconsideradas)
--   ajuste_nao_apaga   : t  (processar_ajuste_ponto desconsidera em vez de apagar)
-- ---------------------------------------------------------------------------
SELECT
  (EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='desconsiderada')) AS coluna_desconsid,
  (to_regprocedure('public.desconsiderar_marcacao_ponto(uuid,text)') IS NOT NULL) AS rpc_desconsiderar,
  (position('desconsiderar_marcacao_ponto' in pg_get_functiondef('public.excluir_marcacao_ponto(uuid)'::regprocedure)) > 0) AS excluir_delega,
  (position('desconsiderada' in pg_get_functiondef('public._ponto_calc_dia(uuid,text,date,uuid)'::regprocedure)) > 0) AS calc_ignora,
  (position('desconsiderada = true' in pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure)) > 0) AS ajuste_nao_apaga,
  CASE
    WHEN (EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='desconsiderada'))
     AND to_regprocedure('public.desconsiderar_marcacao_ponto(uuid,text)') IS NOT NULL
     AND position('desconsiderar_marcacao_ponto' in pg_get_functiondef('public.excluir_marcacao_ponto(uuid)'::regprocedure)) > 0
     AND position('desconsiderada' in pg_get_functiondef('public._ponto_calc_dia(uuid,text,date,uuid)'::regprocedure)) > 0
     AND position('desconsiderada = true' in pg_get_functiondef('public.processar_ajuste_ponto(uuid,boolean,text)'::regprocedure)) > 0
      THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda2_marcacoes_uniformes.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 2 (parte 3): detecção de marcações uniformes ("britânico")
-- Alvos: ponto_verificar_marcacoes_uniformes, ponto_marcacoes_uniformes_monitorar
-- PONTO-377
--
-- O QUE FAZ
--   Por colaborador na competência, mede o desvio-padrão dos horários de entrada
--   e de saída ao longo dos dias. Desvio quase nulo por muitos dias = espelho
--   uniforme ("britânico"), que a Súmula 338, III, do TST considera INVÁLIDO
--   como prova. Uma companheira agendável alerta o RH, idempotente por
--   competência.
--
-- Somente leitura sobre ponto_diario; aditivo e idempotente (CREATE OR REPLACE).
-- Sem backfill.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ponto_verificar_marcacoes_uniformes(
  p_tenant_id          uuid    DEFAULT NULL,
  p_competencia        text    DEFAULT to_char(CURRENT_DATE, 'YYYY-MM'),
  p_min_dias           integer DEFAULT 10,
  p_limiar_desvio_seg  numeric DEFAULT 60
)
RETURNS TABLE(
  tenant_id          uuid,
  colaborador_cpf    text,
  colaborador_nome   text,
  dias               integer,
  desvio_entrada_seg numeric,
  desvio_saida_seg   numeric,
  uniforme           boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Deteccao de marcacoes uniformes (espelho "britanico"): variancia dos
  -- horarios por colaborador. Desvio-padrao quase nulo por muitos dias sinaliza
  -- registro invalido como prova (Sumula 338, III, do TST).
  WITH v_periodo AS (
    SELECT to_date(p_competencia || '-01', 'YYYY-MM-DD') AS ini,
           (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date AS fim
  ),
  dias AS (
    SELECT d.tenant_id,
           regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') AS cpf,
           d.colaborador_nome AS nome,
           EXTRACT(EPOCH FROM d.entrada) AS ent_seg,
           EXTRACT(EPOCH FROM d.saida)   AS sai_seg
    FROM public.ponto_diario d, v_periodo p
    WHERE d.data BETWEEN p.ini AND p.fim
      AND d.entrada IS NOT NULL
      AND d.saida   IS NOT NULL
      AND (p_tenant_id IS NULL OR d.tenant_id = p_tenant_id)
  ),
  agg AS (
    SELECT tenant_id, cpf,
           max(nome)              AS nome,
           count(*)::int          AS dias,
           round(stddev_pop(ent_seg)::numeric, 1) AS dp_ent,
           round(stddev_pop(sai_seg)::numeric, 1) AS dp_sai
    FROM dias
    GROUP BY tenant_id, cpf
  )
  SELECT tenant_id, cpf AS colaborador_cpf, nome AS colaborador_nome, dias,
         dp_ent AS desvio_entrada_seg, dp_sai AS desvio_saida_seg,
         (dias >= p_min_dias
          AND COALESCE(dp_ent, 0) <= p_limiar_desvio_seg
          AND COALESCE(dp_sai, 0) <= p_limiar_desvio_seg) AS uniforme
  FROM agg
  ORDER BY uniforme DESC, dias DESC;
$$;

COMMENT ON FUNCTION public.ponto_verificar_marcacoes_uniformes(uuid, text, integer, numeric) IS
  'Mede a variancia dos horarios de entrada/saida por colaborador na competencia. Desvio quase nulo por muitos dias sinaliza espelho uniforme ("britanico"), invalido como prova (Sumula 338, III, TST). Somente leitura.';

-- Companheira agendável: alerta o RH sobre os espelhos uniformes da competência.
CREATE OR REPLACE FUNCTION public.ponto_marcacoes_uniformes_monitorar(
  p_competencia text DEFAULT to_char(CURRENT_DATE, 'YYYY-MM')
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ref  date := (to_date(p_competencia || '-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_qtd  int  := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT * FROM public.ponto_verificar_marcacoes_uniformes(NULL, p_competencia)
    WHERE uniforme
  LOOP
    v_qtd := v_qtd + 1;
    INSERT INTO public.ponto_alertas
      (tenant_id, colaborador_cpf, colaborador_nome, tipo, severidade,
       titulo, descricao, data_referencia)
    SELECT r.tenant_id, r.colaborador_cpf, r.colaborador_nome,
           'marcacoes_uniformes', 'alta',
           'Marcacoes uniformes (espelho britanico)',
           format('Em %s, %s dias com horarios praticamente identicos (desvio de %s s na entrada e %s s na saida). '
               || 'Registros uniformes sao invalidos como prova (Sumula 338, III, TST) — conferir a fidelidade das batidas.',
               p_competencia, r.dias, r.desvio_entrada_seg, r.desvio_saida_seg),
           v_ref
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = r.tenant_id
        AND a.colaborador_cpf = r.colaborador_cpf
        AND a.tipo = 'marcacoes_uniformes'
        AND a.data_referencia = v_ref
    );
  END LOOP;
  RETURN v_qtd;
END;
$$;

COMMENT ON FUNCTION public.ponto_marcacoes_uniformes_monitorar(text) IS
  'Roda a deteccao de marcacoes uniformes da competencia e alerta o RH por colaborador. Idempotente por competencia. Para agendar via pg_cron.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | OK
--   detecta_uniforme : t  (função de verificação existe)
--   monitor_alerta   : t  (companheira de alerta existe)
-- ---------------------------------------------------------------------------
SELECT
  (to_regprocedure('public.ponto_verificar_marcacoes_uniformes(uuid,text,integer,numeric)') IS NOT NULL) AS detecta_uniforme,
  (to_regprocedure('public.ponto_marcacoes_uniformes_monitorar(text)') IS NOT NULL) AS monitor_alerta,
  CASE
    WHEN to_regprocedure('public.ponto_verificar_marcacoes_uniformes(uuid,text,integer,numeric)') IS NOT NULL
     AND to_regprocedure('public.ponto_marcacoes_uniformes_monitorar(text)') IS NOT NULL
      THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda2_relogio_e_origem.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 2 (parte 2): relógio confiável e origem da batida
-- Alvos: colunas origem_offline/sincronizado_em em ponto_marcacoes;
--        tabela ponto_relogio_checagens; função ponto_monitorar_hora_legal
-- PONTO-378 / PONTO-379
--
-- O QUE FAZ (requisitos do REP-P, Portaria 671/2021, Anexo IX)
--   378: a marcação passa a registrar se nasceu on-line ou off-line e o momento
--        da sincronização, preservando a hora da batida como a oficial.
--   379: monitoração do relógio do servidor contra a Hora Legal Brasileira
--        (Observatório Nacional), com trilha das checagens e alerta quando o
--        desvio passa da tolerância. A hora oficial é fornecida por quem chama
--        (Edge Function que consulta a fonte); esta rotina avalia e registra.
--
-- ADITIVO E IDEMPOTENTE: ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS,
--   CREATE OR REPLACE. Nada do fluxo atual muda. Sem backfill.
-- ============================================================================

ALTER TABLE public.ponto_marcacoes
  ADD COLUMN IF NOT EXISTS origem_offline boolean NOT NULL DEFAULT false;

ALTER TABLE public.ponto_marcacoes
  ADD COLUMN IF NOT EXISTS sincronizado_em timestamptz;

COMMENT ON COLUMN public.ponto_marcacoes.origem_offline IS
  'Marca se a batida foi feita off-line (registrada no dispositivo e enviada depois). A hora_marcacao continua sendo a hora oficial do fato; sincronizado_em guarda o momento do envio.';
COMMENT ON COLUMN public.ponto_marcacoes.sincronizado_em IS
  'Momento em que a batida off-line foi sincronizada com o servidor. Nulo para batidas on-line (nascem sincronizadas).';

-- (379) Trilha de checagens do relógio contra a Hora Legal Brasileira ---------
CREATE TABLE IF NOT EXISTS public.ponto_relogio_checagens (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verificado_em  timestamptz NOT NULL DEFAULT now(),
  hora_servidor  timestamptz NOT NULL,
  hora_legal     timestamptz,           -- Hora Legal Brasileira (Observatório Nacional)
  desvio_seg     numeric,
  tolerancia_seg integer,
  dentro_tolerancia boolean
);

COMMENT ON TABLE public.ponto_relogio_checagens IS
  'Trilha das checagens do relogio do ponto contra a Hora Legal Brasileira (Observatorio Nacional), exigidas do REP-P pela Portaria 671/2021.';

ALTER TABLE public.ponto_relogio_checagens ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
     WHERE schemaname='public' AND tablename='ponto_relogio_checagens'
       AND policyname='ponto_relogio_checagens_leitura') THEN
    CREATE POLICY ponto_relogio_checagens_leitura
      ON public.ponto_relogio_checagens FOR SELECT
      TO authenticated USING (true);
  END IF;
END $rls$;

-- Monitoração do relógio contra a Hora Legal Brasileira.
-- A hora_legal é obtida da fonte oficial (Observatório Nacional / NTP) por quem
-- chama — tipicamente uma Edge Function, que é quem pode sair para a rede. Esta
-- rotina avalia o desvio, registra a checagem na trilha e, se passar da
-- tolerância, alerta os tenants ativos (idempotente por dia).
CREATE OR REPLACE FUNCTION public.ponto_monitorar_hora_legal(
  p_hora_legal timestamptz,
  p_tolerancia_seg integer DEFAULT 60,
  p_tenant_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_servidor timestamptz := clock_timestamp();
  v_desvio   numeric;
  v_ok       boolean;
  v_hoje     date := CURRENT_DATE;
BEGIN
  IF p_hora_legal IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'hora_legal_ausente');
  END IF;

  v_desvio := EXTRACT(EPOCH FROM (v_servidor - p_hora_legal));
  v_ok := abs(v_desvio) <= COALESCE(p_tolerancia_seg, 60);

  INSERT INTO public.ponto_relogio_checagens
    (hora_servidor, hora_legal, desvio_seg, tolerancia_seg, dentro_tolerancia)
  VALUES (v_servidor, p_hora_legal, v_desvio, p_tolerancia_seg, v_ok);

  IF NOT v_ok THEN
    -- Alerta os tenants com movimento recente (ou o informado), um por dia.
    INSERT INTO public.ponto_alertas
      (tenant_id, tipo, severidade, titulo, descricao, data_referencia)
    SELECT t.id, 'relogio_fora_hora_legal', 'critica',
           'Relogio do ponto fora da Hora Legal Brasileira',
           format('Desvio de %s segundos do relogio contra a Hora Legal Brasileira '
               || '(tolerancia de %s s). O carimbo das marcacoes pode estar incorreto — '
               || 'verificar a sincronizacao do servidor.', round(v_desvio,1), p_tolerancia_seg),
           v_hoje
    FROM public.tenants t
    WHERE (p_tenant_id IS NULL OR t.id = p_tenant_id)
      AND (p_tenant_id IS NOT NULL OR EXISTS (
            SELECT 1 FROM public.ponto_marcacoes m
            WHERE m.tenant_id = t.id AND m.data_marcacao >= v_hoje - 30))
      AND NOT EXISTS (
            SELECT 1 FROM public.ponto_alertas a
            WHERE a.tenant_id = t.id
              AND a.tipo = 'relogio_fora_hora_legal'
              AND a.data_referencia = v_hoje);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'hora_servidor', v_servidor,
    'hora_legal', p_hora_legal,
    'desvio_seg', v_desvio,
    'tolerancia_seg', p_tolerancia_seg,
    'dentro_tolerancia', v_ok
  );
END;
$$;

COMMENT ON FUNCTION public.ponto_monitorar_hora_legal(timestamptz, integer, uuid) IS
  'Compara o relogio do servidor com a Hora Legal Brasileira (Observatorio Nacional) fornecida pelo chamador, registra a checagem na trilha e alerta quando o desvio passa da tolerancia. Requisito do REP-P (Portaria 671/2021).';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | OK
--   colunas_origem   : t  (origem_offline e sincronizado_em existem)
--   trilha_relogio   : t  (tabela ponto_relogio_checagens existe)
--   monitor_hlb      : t  (função de monitoração da Hora Legal existe)
-- ---------------------------------------------------------------------------
SELECT
  (2 = (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='public' AND table_name='ponto_marcacoes'
          AND column_name IN ('origem_offline','sincronizado_em')))          AS colunas_origem,
  (to_regclass('public.ponto_relogio_checagens') IS NOT NULL)                AS trilha_relogio,
  (to_regprocedure('public.ponto_monitorar_hora_legal(timestamptz,integer,uuid)') IS NOT NULL) AS monitor_hlb,
  CASE
    WHEN 2 = (SELECT count(*) FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ponto_marcacoes'
                AND column_name IN ('origem_offline','sincronizado_em'))
     AND to_regclass('public.ponto_relogio_checagens') IS NOT NULL
     AND to_regprocedure('public.ponto_monitorar_hora_legal(timestamptz,integer,uuid)') IS NOT NULL
      THEN 'OK'
    ELSE 'CONFERIR'
  END                                                                        AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda2_reabertura_competencia.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 2 (parte 4): reabertura formal de competência + versão do espelho
-- Alvos: colunas de reabertura em ponto_fechamentos; tabela ponto_espelhos_historico
--        (com a trava do cercado); função ponto_reabrir_competencia
-- PONTO-358
--
-- O QUE FAZ
--   Cria a saída FORMAL para o erro legítimo descoberto após o fechamento:
--   ponto_reabrir_competencia valida que a competência está fechada, exige
--   motivo, confere a alçada (papéis de gestão), ARQUIVA a versão corrente dos
--   espelhos (a que o colaborador recebeu) no histórico — recuperável —, marca
--   o fechamento como 'reaberto' e registra a trilha. O re-fechamento seguinte
--   gera a próxima versão do espelho, sem regravar a anterior.
--
-- A tabela nova recebe a trava do cercado do QA (isolamento de tenant), como
-- toda tabela de ponto. Aditivo e idempotente. Sem backfill.
-- ============================================================================

-- (1) Metadados de reabertura -------------------------------------------------
ALTER TABLE public.ponto_fechamentos
  ADD COLUMN IF NOT EXISTS reaberto_em         timestamptz,
  ADD COLUMN IF NOT EXISTS reaberto_por        text,
  ADD COLUMN IF NOT EXISTS reaberto_por_nome   text,
  ADD COLUMN IF NOT EXISTS motivo_reabertura   text;

-- (2) Histórico de versões do espelho ----------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_espelhos_historico (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL,
  empresa_id         uuid,
  competencia        text NOT NULL,
  colaborador_cpf    text,
  colaborador_nome   text,
  versao             integer NOT NULL,
  espelho_snapshot   jsonb NOT NULL,
  motivo_reabertura  text,
  reaberto_por       text,
  reaberto_por_nome  text,
  arquivado_em       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ponto_espelhos_historico_lookup
  ON public.ponto_espelhos_historico (tenant_id, competencia, colaborador_cpf, versao);

COMMENT ON TABLE public.ponto_espelhos_historico IS
  'Versoes anteriores dos espelhos de ponto, arquivadas quando a competencia e reaberta. Preserva o documento que o colaborador cientificou — recuperavel por versao.';

ALTER TABLE public.ponto_espelhos_historico ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
     WHERE schemaname='public' AND tablename='ponto_espelhos_historico'
       AND policyname='ponto_espelhos_historico_leitura') THEN
    CREATE POLICY ponto_espelhos_historico_leitura
      ON public.ponto_espelhos_historico FOR SELECT
      TO authenticated
      USING (tenant_id = (auth.jwt() ->> 'tenant_id')::uuid OR auth.uid() IS NULL);
  END IF;
END $rls$;

-- Trava do cercado do QA (isolamento de tenant): toda tabela do módulo com
-- tenant_id precisa dela (a rotina PONTO-270 acusa quando falta).
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_espelhos_historico'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_espelhos_historico
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_espelhos_historico', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_espelhos_historico');

-- (3) Reabertura formal da competência ---------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_reabrir_competencia(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text,
  p_motivo      text,
  p_por         text DEFAULT NULL,
  p_por_nome    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_fech   RECORD;
  v_uid    uuid := auth.uid();
  v_alcada boolean := false;
  v_versao int;
  v_qtd    int := 0;
BEGIN
  -- Motivo é obrigatório (reabertura é ato formal).
  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio');
  END IF;

  -- A competência precisa existir e estar FECHADA.
  SELECT * INTO v_fech
  FROM public.ponto_fechamentos f
  WHERE f.tenant_id = p_tenant_id
    AND f.competencia = p_competencia
    AND (p_empresa_id IS NULL OR f.empresa_id IS NOT DISTINCT FROM p_empresa_id)
  ORDER BY f.data_fechamento DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_sem_fechamento');
  END IF;
  IF COALESCE(v_fech.status, '') <> 'fechado' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'competencia_nao_esta_fechada', 'status_atual', v_fech.status);
  END IF;

  -- Alçada: só papéis de gestão reabrem. No SQL Editor (auth.uid() nulo), o
  -- administrador executa direto e o responsavel fica registrado por p_por.
  IF v_uid IS NULL THEN
    v_alcada := true;
  ELSE
    SELECT public.has_role(v_uid, 'manager'::public.app_role)
        OR public.has_role(v_uid, 'admin'::public.app_role)
        OR public.has_role(v_uid, 'owner'::public.app_role)
        OR public.has_role(v_uid, 'superadmin'::public.app_role)
      INTO v_alcada;
  END IF;
  IF NOT COALESCE(v_alcada, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_alcada_para_reabrir');
  END IF;

  -- Arquiva a versão corrente dos espelhos (a que o colaborador recebeu).
  SELECT COALESCE(max(h.versao), 0) + 1 INTO v_versao
  FROM public.ponto_espelhos_historico h
  WHERE h.tenant_id = p_tenant_id AND h.competencia = p_competencia
    AND h.empresa_id IS NOT DISTINCT FROM p_empresa_id;

  INSERT INTO public.ponto_espelhos_historico
    (tenant_id, empresa_id, competencia, colaborador_cpf, colaborador_nome,
     versao, espelho_snapshot, motivo_reabertura, reaberto_por, reaberto_por_nome)
  SELECT e.tenant_id, e.empresa_id, e.competencia, e.colaborador_cpf, e.colaborador_nome,
         v_versao, to_jsonb(e.*), p_motivo, p_por, p_por_nome
  FROM public.ponto_espelhos e
  WHERE e.tenant_id = p_tenant_id AND e.competencia = p_competencia
    AND (p_empresa_id IS NULL OR e.empresa_id IS NOT DISTINCT FROM p_empresa_id);
  GET DIAGNOSTICS v_qtd = ROW_COUNT;

  -- Marca o fechamento como reaberto (libera novas marcações/edição no periodo).
  UPDATE public.ponto_fechamentos
     SET status = 'reaberto',
         reaberto_em = now(),
         reaberto_por = p_por,
         reaberto_por_nome = p_por_nome,
         motivo_reabertura = p_motivo,
         updated_at = now()
   WHERE id = v_fech.id;

  -- Trilha.
  BEGIN
    INSERT INTO public.ponto_audit_log
      (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id)
    VALUES (p_tenant_id, 'ponto_fechamentos', v_fech.id, 'REABERTURA',
            jsonb_build_object('status', 'fechado', 'competencia', p_competencia),
            jsonb_build_object('status', 'reaberto', 'competencia', p_competencia,
                               'motivo', p_motivo, 'por', p_por, 'por_nome', p_por_nome,
                               'espelhos_arquivados', v_qtd, 'versao_arquivada', v_versao),
            v_uid);
  EXCEPTION WHEN OTHERS THEN
    NULL;  -- trilha é acessória; nunca derruba a reabertura
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'competencia', p_competencia,
    'espelhos_arquivados', v_qtd,
    'versao_arquivada', v_versao,
    'status', 'reaberto'
  );
END;
$$;

COMMENT ON FUNCTION public.ponto_reabrir_competencia(uuid, uuid, text, text, text, text) IS
  'Reabertura formal de competencia fechada: exige motivo, confere alcada (papeis de gestao), arquiva a versao corrente dos espelhos no historico (recuperavel), marca o fechamento como reaberto e registra a trilha. O re-fechamento seguinte gera a proxima versao do espelho.';

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | OK
--   colunas_reabertura : t  (motivo_reabertura em ponto_fechamentos)
--   historico_espelho  : t  (tabela ponto_espelhos_historico existe)
--   trava_cercado      : t  (a tabela nova tem a trava do cercado — PONTO-270)
--   reabrir_existe     : t  (função de reabertura formal existe)
-- ---------------------------------------------------------------------------
SELECT
  (EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ponto_fechamentos' AND column_name='motivo_reabertura')) AS colunas_reabertura,
  (to_regclass('public.ponto_espelhos_historico') IS NOT NULL) AS historico_espelho,
  (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='qa_guarda_cercado'
     AND tgrelid='public.ponto_espelhos_historico'::regclass AND NOT tgisinternal)) AS trava_cercado,
  (to_regprocedure('public.ponto_reabrir_competencia(uuid,uuid,text,text,text,text)') IS NOT NULL) AS reabrir_existe,
  CASE
    WHEN (EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='ponto_fechamentos' AND column_name='motivo_reabertura'))
     AND to_regclass('public.ponto_espelhos_historico') IS NOT NULL
     AND (EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='qa_guarda_cercado'
            AND tgrelid='public.ponto_espelhos_historico'::regclass AND NOT tgisinternal))
     AND to_regprocedure('public.ponto_reabrir_competencia(uuid,uuid,text,text,text,text)') IS NOT NULL
      THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'gerar_hash_marcacao', NULL),
    ('funcao', 'ponto_verificar_cadeia_hash', NULL),
    ('funcao', 'ponto_cadeia_hash_monitorar', 'Cadeia de hash das marcacoes com quebra'),
    ('funcao', 'desconsiderar_marcacao_ponto', 'Apenas gestor/RH pode desconsiderar marcações'),
    ('funcao', 'excluir_marcacao_ponto', 'Marcacao duplicada/incorreta desconsiderada pela gestao'),
    ('funcao', '_ponto_calc_dia', 'Atraso justificado por atestado de horas no dia.'),
    ('funcao', 'ponto_reordena_tipos_dia', 'Batida incluída em horário anterior às existentes; '),
    ('funcao', 'ponto_corte_virada', NULL),
    ('funcao', 'processar_ajuste_ponto', 'Apenas gestor/RH pode processar ajustes de ponto'),
    ('funcao', 'ponto_verificar_marcacoes_uniformes', NULL),
    ('funcao', 'ponto_marcacoes_uniformes_monitorar', 'Marcacoes uniformes (espelho britanico)'),
    ('funcao', 'ponto_monitorar_hora_legal', 'Relogio do ponto fora da Hora Legal Brasileira'),
    ('funcao', 'ponto_reabrir_competencia', NULL),
    ('tabela', 'ponto_relogio_checagens', NULL),
    ('tabela', 'ponto_espelhos_historico', NULL),
    ('indice', 'idx_ponto_espelhos_historico_lookup', NULL),
    ('coluna', 'ponto_marcacoes.hash_anterior', NULL),
    ('coluna', 'ponto_marcacoes.desconsiderada', NULL),
    ('coluna', 'ponto_marcacoes.origem_offline', NULL),
    ('coluna', 'ponto_marcacoes.sincronizado_em', NULL),
    ('coluna', 'ponto_fechamentos.reaberto_em', NULL)
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
