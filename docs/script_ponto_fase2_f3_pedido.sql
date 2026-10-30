-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto, Fase 2 / F3: pedido de ajuste com natureza
-- (Correção de batida × Ausência) + selfie no pedido. Espelho da migration
-- 20261029215356_ponto_fase2_f3_pedido_natureza.sql.
--
-- ORDEM: rodar ESTE script, depois o da F4 (script_ponto_fase2_f4_aprovacao.sql),
-- depois o da F5 (script_ponto_fase2_f5_docs_testes.sql) e SÓ ENTÃO publicar as
-- telas. Sem este script as telas novas mostram "Atualize o app em instantes".
--
-- Colar INTEIRO no SQL Editor. Idempotente (pode rodar duas vezes). Não cria
-- tabela e não altera dado existente: só colunas novas em ponto_ajustes (vazias
-- nos pedidos antigos), um gatilho de INSERT, funções novas e casos de QA.
-- As RPCs antigas do app (texto livre) continuam iguais — app em cache segue ok.
--
-- Desfazer (se preciso):
--   DROP TRIGGER IF EXISTS trg_ponto_ajuste_natureza ON public.ponto_ajustes;
--   DROP FUNCTION IF EXISTS public.solicitar_ajustes_ponto_app(text,text,jsonb,jsonb,jsonb,text);
--   DROP FUNCTION IF EXISTS externo.solicitar_ajustes_ponto_app(text,text,jsonb,jsonb,jsonb,text);
--   DROP FUNCTION IF EXISTS public.listar_justificativas_app(text);
--
-- A última consulta mostra: colunas e gatilho presentes, RPCs liberadas para o
-- app (anon), leitura da selfie do pedido e o resultado dos casos PONTO-492,
-- 493 e 494 (rodam no cercado de QA e desfazem tudo no fim).
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Colunas + CHECKs ----------------------------------------------------------
ALTER TABLE public.ponto_ajustes
  ADD COLUMN IF NOT EXISTS natureza text,
  ADD COLUMN IF NOT EXISTS ausencia_hora_inicio time,
  ADD COLUMN IF NOT EXISTS ausencia_hora_fim time,
  ADD COLUMN IF NOT EXISTS atestado_id uuid,
  ADD COLUMN IF NOT EXISTS selfie_url text;

COMMENT ON COLUMN public.ponto_ajustes.natureza IS
  'correcao_batida = corrige horário (vira marcação, não abona); ausencia = declaração/atestado (vira lançamento em Atestados na aprovação, nunca marcação); NULL = pedido antigo ou lançamento do RH.';
COMMENT ON COLUMN public.ponto_ajustes.ausencia_hora_inicio IS 'Ausência parcial: início (natureza ausencia, dia_inteiro false).';
COMMENT ON COLUMN public.ponto_ajustes.ausencia_hora_fim IS 'Ausência parcial: fim (natureza ausencia, dia_inteiro false).';
COMMENT ON COLUMN public.ponto_ajustes.atestado_id IS 'Atestado (atestados.id) lançado pela aprovação desta ausência. Sem FK (ligação macia).';
COMMENT ON COLUMN public.ponto_ajustes.selfie_url IS 'Caminho da selfie no bucket privado ponto-selfies (pedido feito pelo app quando a empresa exige selfie).';

DO $ck$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ponto_ajustes_natureza_chk'
                    AND conrelid = 'public.ponto_ajustes'::regclass) THEN
    ALTER TABLE public.ponto_ajustes
      ADD CONSTRAINT ponto_ajustes_natureza_chk
      CHECK (natureza IS NULL OR natureza IN ('correcao_batida', 'ausencia')) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'ponto_ajustes_ausencia_coerente_chk'
                    AND conrelid = 'public.ponto_ajustes'::regclass) THEN
    ALTER TABLE public.ponto_ajustes
      ADD CONSTRAINT ponto_ajustes_ausencia_coerente_chk
      CHECK (natureza IS DISTINCT FROM 'ausencia'
             OR (tipo_ajuste = 'justificativa'
                 AND hora_solicitada IS NULL
                 AND (COALESCE(dia_inteiro, false)
                      OR (ausencia_hora_inicio IS NOT NULL
                          AND ausencia_hora_fim IS NOT NULL
                          AND ausencia_hora_fim > ausencia_hora_inicio)))) NOT VALID;
  END IF;
END $ck$;

ALTER TABLE public.ponto_ajustes VALIDATE CONSTRAINT ponto_ajustes_natureza_chk;
ALTER TABLE public.ponto_ajustes VALIDATE CONSTRAINT ponto_ajustes_ausencia_coerente_chk;

CREATE INDEX IF NOT EXISTS idx_ponto_ajustes_selfie_url
  ON public.ponto_ajustes (selfie_url) WHERE selfie_url IS NOT NULL;

-- 2) Gatilho de natureza (só INSERT: pedidos antigos não são tocados) ----------
CREATE OR REPLACE FUNCTION public.ponto_ajuste_natureza()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $nat$
DECLARE
  v_just_tenant uuid;
  v_just_natureza text;
BEGIN
  IF NEW.justificativa_id IS NOT NULL THEN
    v_just_tenant := (SELECT j.tenant_id FROM public.ponto_justificativas j WHERE j.id = NEW.justificativa_id);
    IF v_just_tenant IS NULL OR v_just_tenant IS DISTINCT FROM NEW.tenant_id THEN
      RAISE EXCEPTION 'A justificativa escolhida não pertence a esta empresa.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.natureza IS NULL THEN
      -- lançamento do RH (tela antiga ou nova): a natureza vem do catálogo
      v_just_natureza := (SELECT j.natureza FROM public.ponto_justificativas j WHERE j.id = NEW.justificativa_id);
      NEW.natureza := v_just_natureza;
    END IF;
  END IF;

  IF NEW.natureza = 'ausencia' THEN
    IF NEW.tipo_ajuste IS DISTINCT FROM 'justificativa' THEN
      RAISE EXCEPTION 'Justificativa de ausência (declaração/atestado) não serve para corrigir horário. Use "Ausência" no dia, com o documento anexado.'
        USING ERRCODE = 'check_violation';
    END IF;
    IF jsonb_array_length(COALESCE(NEW.anexos, '[]'::jsonb)) < 1 THEN
      RAISE EXCEPTION 'Ausência exige a declaração ou o atestado anexado.'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.natureza = 'correcao_batida' THEN
    IF NEW.tipo_ajuste NOT IN ('inclusao', 'correcao') OR NEW.hora_solicitada IS NULL THEN
      RAISE EXCEPTION 'Justificativa de correção de batida só serve para informar um horário. Para ausência, escolha uma justificativa de ausência.'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $nat$;

DROP TRIGGER IF EXISTS trg_ponto_ajuste_natureza ON public.ponto_ajustes;
CREATE TRIGGER trg_ponto_ajuste_natureza
  BEFORE INSERT ON public.ponto_ajustes
  FOR EACH ROW EXECUTE FUNCTION public.ponto_ajuste_natureza();

-- 3a) Justificativas do app novo -----------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_justificativas_app(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $listapp$
DECLARE
  v_tenant uuid;
  v_lista jsonb;
  v_selfie boolean;
BEGIN
  v_tenant := (SELECT l.tenant_id FROM public.ponto_links l
                WHERE l.token = p_token AND l.ativo = true
                  AND (l.data_expiracao IS NULL OR l.data_expiracao > now())
                LIMIT 1);
  IF v_tenant IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado.');
  END IF;

  -- Semente preguiçosa: cliente sem as APP_* (cliente novo) recebe agora.
  IF NOT EXISTS (SELECT 1 FROM public.ponto_justificativas
                  WHERE tenant_id = v_tenant AND codigo LIKE 'APP\_%') THEN
    BEGIN
      PERFORM public.seed_justificativas_app(v_tenant);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'seed_justificativas_app falhou para %: %', v_tenant, SQLERRM;
    END;
  END IF;

  v_lista := (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'id', j.id, 'nome', j.nome, 'descricao', j.descricao,
                  'natureza', j.natureza, 'requer_anexo', j.requer_anexo, 'ordem', j.ordem)
                ORDER BY j.natureza DESC, j.ordem NULLS LAST, j.nome), '[]'::jsonb)
                FROM public.ponto_justificativas j
               WHERE j.tenant_id = v_tenant
                 AND j.ativo = true
                 AND j.aparece_no_app = true
                 AND j.natureza IS NOT NULL);

  v_selfie := COALESCE((SELECT c.exigir_selfie_link FROM public.ponto_configuracao c
                         WHERE c.tenant_id = v_tenant LIMIT 1), true);

  RETURN json_build_object('justificativas', v_lista, 'exigir_selfie', v_selfie);
END $listapp$;

REVOKE ALL ON FUNCTION public.listar_justificativas_app(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_justificativas_app(text) TO anon, authenticated;

-- 3b) Pedido do app novo (correções + ausências numa chamada só, atômica) ------
CREATE OR REPLACE FUNCTION externo.solicitar_ajustes_ponto_app(
  p_token text,
  p_cpf text DEFAULT NULL,
  p_correcoes jsonb DEFAULT '[]'::jsonb,
  p_ausencias jsonb DEFAULT '[]'::jsonb,
  p_anexos jsonb DEFAULT '[]'::jsonb,
  p_selfie_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $pedapp$
DECLARE
  v_link public.ponto_links;
  v_colab_id uuid;
  v_colab_nome text;
  v_colab_cpf text;
  v_rec record;
  v_empresa uuid;
  v_item jsonb;
  v_anexo jsonb;
  v_path text;
  v_prefixo text;
  v_data date;
  v_hora time;
  v_hora_original time;
  v_ini time;
  v_fim time;
  v_tipo text;
  v_dia_inteiro boolean;
  v_just public.ponto_justificativas;
  v_obs text;
  v_selfie text := NULLIF(btrim(COALESCE(p_selfie_url, '')), '');
  v_exige_selfie boolean;
  v_now timestamptz := now();
  v_afast public.afastamentos;
  v_ids uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_n_corr int := jsonb_array_length(COALESCE(p_correcoes, '[]'::jsonb));
  v_n_aus int := jsonb_array_length(COALESCE(p_ausencias, '[]'::jsonb));
  v_origem text;
BEGIN
  IF jsonb_typeof(COALESCE(p_correcoes, '[]'::jsonb)) <> 'array'
     OR jsonb_typeof(COALESCE(p_ausencias, '[]'::jsonb)) <> 'array'
     OR jsonb_typeof(COALESCE(p_anexos, '[]'::jsonb)) <> 'array' THEN
    RETURN json_build_object('error', 'Pedido em formato inválido. Atualize o app e tente de novo.');
  END IF;
  IF v_n_corr + v_n_aus = 0 THEN
    RETURN json_build_object('error', 'Inclua ao menos uma correção de batida ou uma ausência.');
  END IF;
  IF v_n_corr + v_n_aus > 40 THEN
    RETURN json_build_object('error', 'Máximo de 40 itens por envio.');
  END IF;
  IF jsonb_array_length(COALESCE(p_anexos, '[]'::jsonb)) > 3 THEN
    RETURN json_build_object('error', 'Máximo de 3 anexos para as correções.');
  END IF;

  v_link := (SELECT l FROM public.ponto_links l
              WHERE l.token = p_token AND l.ativo = true
                AND (l.data_expiracao IS NULL OR l.data_expiracao > now())
              LIMIT 1);
  IF v_link.id IS NULL THEN
    RETURN json_build_object('error', 'Link inválido ou expirado.');
  END IF;

  IF v_link.tipo = 'compartilhado' THEN
    FOR v_rec IN SELECT * FROM public._ponto_resolver_colaborador_cpf(v_link.tenant_id, p_cpf) LOOP
      v_colab_id := v_rec.colaborador_id;
      v_colab_nome := v_rec.colaborador_nome;
      v_colab_cpf := v_rec.colaborador_cpf;
      EXIT;
    END LOOP;
    IF v_colab_id IS NULL THEN
      RETURN json_build_object('error', 'CPF não encontrado ou colaborador sem ponto ativo.');
    END IF;
    v_origem := ' (link compartilhado)';
  ELSE
    BEGIN
      v_colab_id := v_link.colaborador_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      RETURN json_build_object('error', 'Link sem colaborador válido. Fale com o RH.');
    END;
    v_colab_nome := v_link.colaborador_nome;
    v_colab_cpf := v_link.colaborador_cpf;
    v_origem := ' (link externo)';
  END IF;

  -- Selfie: obrigatória em todo pedido quando a empresa exige selfie no link.
  v_exige_selfie := COALESCE((SELECT c.exigir_selfie_link FROM public.ponto_configuracao c
                               WHERE c.tenant_id = v_link.tenant_id LIMIT 1), true);
  IF v_exige_selfie AND v_selfie IS NULL THEN
    RETURN json_build_object('error', 'Tire a selfie para enviar o pedido de ajuste.');
  END IF;
  IF v_selfie IS NOT NULL AND (v_selfie NOT LIKE 'externo/%' OR position('..' IN v_selfie) > 0) THEN
    RETURN json_build_object('error', 'Selfie inválida. Tire a selfie de novo.');
  END IF;

  v_empresa := COALESCE(public.ponto_empresa_do_colaborador(v_colab_id),
                        public.ponto_empresa_do_cpf(v_link.tenant_id, v_colab_cpf));
  v_prefixo := 'externo/' || p_token || '/';

  -- Anexos opcionais das correções: só da pasta deste link.
  FOR v_anexo IN SELECT * FROM jsonb_array_elements(COALESCE(p_anexos, '[]'::jsonb)) LOOP
    v_path := COALESCE(v_anexo->>'url', v_anexo->>'path');
    IF v_path IS NULL OR left(v_path, length(v_prefixo)) <> v_prefixo OR position('..' IN v_path) > 0 THEN
      RETURN json_build_object('error', 'Anexo inválido. Envie o arquivo de novo pelo app.');
    END IF;
  END LOOP;

  -- ===== PRIMEIRA passada: só confere (nada é gravado se houver erro) =====
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_correcoes, '[]'::jsonb)) LOOP
    BEGIN
      v_data := (v_item->>'data')::date;
      v_hora := (v_item->>'hora')::time;
      v_hora_original := NULLIF(v_item->>'hora_original', '')::time;
    EXCEPTION WHEN OTHERS THEN
      RETURN json_build_object('error', 'Data ou horário inválido numa correção.');
    END;
    v_tipo := v_item->>'tipo';
    IF v_data IS NULL OR v_hora IS NULL THEN
      RETURN json_build_object('error', 'Data e horário são obrigatórios em cada correção de batida.');
    END IF;
    IF COALESCE(v_tipo, '') NOT IN ('entrada', 'saida', 'saida_almoco', 'retorno_almoco') THEN
      RETURN json_build_object('error', 'Tipo de marcação inválido: ' || COALESCE(v_tipo, '(vazio)'));
    END IF;
    v_just := NULL;
    BEGIN
      v_just := (SELECT j FROM public.ponto_justificativas j WHERE j.id = (v_item->>'justificativa_id')::uuid);
    EXCEPTION WHEN OTHERS THEN
      v_just := NULL;
    END;
    IF v_just.id IS NULL OR v_just.tenant_id IS DISTINCT FROM v_link.tenant_id
       OR NOT COALESCE(v_just.ativo, false) OR NOT COALESCE(v_just.aparece_no_app, false) THEN
      RETURN json_build_object('error', 'Escolha uma justificativa da lista para a correção de ' || to_char(v_data, 'DD/MM/YYYY') || '.');
    END IF;
    IF v_just.natureza IS DISTINCT FROM 'correcao_batida' THEN
      RETURN json_build_object('error', 'A justificativa "' || v_just.nome || '" é de ausência e não serve para corrigir horário (' || to_char(v_data, 'DD/MM/YYYY') || '). Use "Ausência" nesse dia.');
    END IF;
    IF length(COALESCE(v_item->>'observacao', '')) > 300 THEN
      RETURN json_build_object('error', 'A observação pode ter no máximo 300 caracteres.');
    END IF;
    IF v_data > CURRENT_DATE THEN
      RETURN json_build_object('error', 'Não é permitido solicitar ajuste para data futura.');
    END IF;
    IF v_data = CURRENT_DATE AND (v_data + v_hora) > v_now THEN
      RETURN json_build_object('error', 'Não é permitido solicitar ajuste para horário futuro.');
    END IF;
    IF public._ponto_competencia_fechada(v_link.tenant_id, v_empresa, v_data) THEN
      RETURN json_build_object('error', 'A folha de ' || to_char(v_data, 'MM/YYYY')
        || ' já foi fechada pelo RH e não aceita mais ajustes. Fale com o RH: se houver correção a fazer, ele reabre o período.');
    END IF;
    v_afast := public.afastamento_vigente(v_link.tenant_id, v_colab_cpf, v_data);
    IF v_afast.id IS NOT NULL THEN
      RETURN json_build_object('error', 'O dia ' || to_char(v_data, 'DD/MM/YYYY')
        || ' já está abonado por afastamento — não é preciso pedir ajuste para ele. Retire esse dia e envie os demais.');
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_ausencias, '[]'::jsonb)) LOOP
    BEGIN
      v_data := (v_item->>'data')::date;
      v_dia_inteiro := COALESCE((v_item->>'dia_inteiro')::boolean, false);
      v_ini := NULLIF(v_item->>'hora_inicio', '')::time;
      v_fim := NULLIF(v_item->>'hora_fim', '')::time;
    EXCEPTION WHEN OTHERS THEN
      RETURN json_build_object('error', 'Data ou horário inválido numa ausência.');
    END;
    IF v_data IS NULL THEN
      RETURN json_build_object('error', 'Informe o dia da ausência.');
    END IF;
    v_just := NULL;
    BEGIN
      v_just := (SELECT j FROM public.ponto_justificativas j WHERE j.id = (v_item->>'justificativa_id')::uuid);
    EXCEPTION WHEN OTHERS THEN
      v_just := NULL;
    END;
    IF v_just.id IS NULL OR v_just.tenant_id IS DISTINCT FROM v_link.tenant_id
       OR NOT COALESCE(v_just.ativo, false) OR NOT COALESCE(v_just.aparece_no_app, false) THEN
      RETURN json_build_object('error', 'Escolha uma justificativa da lista para a ausência de ' || to_char(v_data, 'DD/MM/YYYY') || '.');
    END IF;
    IF v_just.natureza IS DISTINCT FROM 'ausencia' THEN
      RETURN json_build_object('error', 'A justificativa "' || v_just.nome || '" é de correção de batida e não serve para ausência (' || to_char(v_data, 'DD/MM/YYYY') || ').');
    END IF;
    IF length(COALESCE(v_item->>'observacao', '')) > 300 THEN
      RETURN json_build_object('error', 'A observação pode ter no máximo 300 caracteres.');
    END IF;
    IF jsonb_typeof(COALESCE(v_item->'anexos', '[]'::jsonb)) <> 'array'
       OR jsonb_array_length(COALESCE(v_item->'anexos', '[]'::jsonb)) < 1 THEN
      RETURN json_build_object('error', 'Anexe a declaração ou o atestado da ausência de ' || to_char(v_data, 'DD/MM/YYYY') || '.');
    END IF;
    IF jsonb_array_length(v_item->'anexos') > 3 THEN
      RETURN json_build_object('error', 'Máximo de 3 anexos por ausência.');
    END IF;
    FOR v_anexo IN SELECT * FROM jsonb_array_elements(v_item->'anexos') LOOP
      v_path := COALESCE(v_anexo->>'url', v_anexo->>'path');
      IF v_path IS NULL OR left(v_path, length(v_prefixo)) <> v_prefixo OR position('..' IN v_path) > 0 THEN
        RETURN json_build_object('error', 'Anexo inválido. Envie o arquivo de novo pelo app.');
      END IF;
    END LOOP;
    IF NOT v_dia_inteiro THEN
      IF v_ini IS NULL OR v_fim IS NULL THEN
        RETURN json_build_object('error', 'Informe o início e o fim da ausência de ' || to_char(v_data, 'DD/MM/YYYY') || ', ou marque "Dia inteiro".');
      END IF;
      IF v_fim <= v_ini THEN
        RETURN json_build_object('error', 'Na ausência de ' || to_char(v_data, 'DD/MM/YYYY') || ', o fim precisa ser depois do início.');
      END IF;
    END IF;
    IF v_data > CURRENT_DATE THEN
      RETURN json_build_object('error', 'Não é permitido informar ausência em data futura.');
    END IF;
    IF v_data = CURRENT_DATE AND NOT v_dia_inteiro AND (v_data + v_fim) > v_now THEN
      RETURN json_build_object('error', 'A ausência de hoje ainda não terminou. Envie depois do horário de fim.');
    END IF;
    IF (SELECT count(*) FROM jsonb_array_elements(COALESCE(p_ausencias, '[]'::jsonb)) e
         WHERE e->>'data' = v_item->>'data') > 1 THEN
      RETURN json_build_object('error', 'Há mais de uma ausência no dia ' || to_char(v_data, 'DD/MM/YYYY') || '. Envie uma só por dia.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.ponto_ajustes a
                WHERE a.tenant_id = v_link.tenant_id
                  AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '\D', '', 'g')
                    = regexp_replace(COALESCE(v_colab_cpf, ''), '\D', '', 'g')
                  AND a.data_referencia = v_data
                  AND a.natureza = 'ausencia'
                  AND a.status IN ('pendente', 'pendente_comprovacao')) THEN
      RETURN json_build_object('error', 'Já existe uma ausência aguardando o RH no dia ' || to_char(v_data, 'DD/MM/YYYY') || '.');
    END IF;
    IF public._ponto_competencia_fechada(v_link.tenant_id, v_empresa, v_data) THEN
      RETURN json_build_object('error', 'A folha de ' || to_char(v_data, 'MM/YYYY')
        || ' já foi fechada pelo RH e não aceita mais ajustes. Fale com o RH: se houver correção a fazer, ele reabre o período.');
    END IF;
    v_afast := public.afastamento_vigente(v_link.tenant_id, v_colab_cpf, v_data);
    IF v_afast.id IS NOT NULL THEN
      RETURN json_build_object('error', 'O dia ' || to_char(v_data, 'DD/MM/YYYY')
        || ' já está abonado por afastamento — não é preciso pedir ajuste para ele. Retire esse dia e envie os demais.');
    END IF;
  END LOOP;

  -- ===== SEGUNDA passada: grava =====
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_correcoes, '[]'::jsonb)) LOOP
    v_data := (v_item->>'data')::date;
    v_hora := (v_item->>'hora')::time;
    v_hora_original := NULLIF(v_item->>'hora_original', '')::time;
    v_just := (SELECT j FROM public.ponto_justificativas j WHERE j.id = (v_item->>'justificativa_id')::uuid);
    v_obs := NULLIF(btrim(COALESCE(v_item->>'observacao', '')), '');
    v_id := gen_random_uuid();
    INSERT INTO public.ponto_ajustes (
      id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, tipo_marcacao, hora_solicitada, hora_original,
      motivo, observacao, justificativa_id, natureza, status, created_by_nome,
      anexos, selfie_url
    ) VALUES (
      v_id, v_link.tenant_id, v_empresa, v_colab_id, v_colab_nome, v_colab_cpf,
      v_data, CASE WHEN v_hora_original IS NOT NULL THEN 'correcao' ELSE 'inclusao' END,
      v_item->>'tipo', v_hora, v_hora_original,
      v_just.nome, v_obs, v_just.id, 'correcao_batida', 'pendente', v_colab_nome || v_origem,
      COALESCE(p_anexos, '[]'::jsonb), v_selfie
    );
    v_ids := v_ids || v_id;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_ausencias, '[]'::jsonb)) LOOP
    v_data := (v_item->>'data')::date;
    v_dia_inteiro := COALESCE((v_item->>'dia_inteiro')::boolean, false);
    v_ini := CASE WHEN v_dia_inteiro THEN NULL ELSE NULLIF(v_item->>'hora_inicio', '')::time END;
    v_fim := CASE WHEN v_dia_inteiro THEN NULL ELSE NULLIF(v_item->>'hora_fim', '')::time END;
    v_just := (SELECT j FROM public.ponto_justificativas j WHERE j.id = (v_item->>'justificativa_id')::uuid);
    v_obs := NULLIF(btrim(COALESCE(v_item->>'observacao', '')), '');
    v_id := gen_random_uuid();
    INSERT INTO public.ponto_ajustes (
      id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
      data_referencia, tipo_ajuste, tipo_marcacao, hora_solicitada, hora_original,
      dia_inteiro, ausencia_hora_inicio, ausencia_hora_fim,
      motivo, observacao, justificativa_id, natureza, status, created_by_nome,
      anexos, selfie_url
    ) VALUES (
      v_id, v_link.tenant_id, v_empresa, v_colab_id, v_colab_nome, v_colab_cpf,
      v_data, 'justificativa', NULL, NULL, NULL,
      v_dia_inteiro, v_ini, v_fim,
      v_just.nome, v_obs, v_just.id, 'ausencia', 'pendente', v_colab_nome || v_origem,
      v_item->'anexos', v_selfie
    );
    v_ids := v_ids || v_id;
  END LOOP;

  RETURN json_build_object('success', true, 'total', COALESCE(array_length(v_ids, 1), 0), 'ids', to_jsonb(v_ids));
END $pedapp$;

REVOKE ALL ON FUNCTION externo.solicitar_ajustes_ponto_app(text, text, jsonb, jsonb, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION externo.solicitar_ajustes_ponto_app(text, text, jsonb, jsonb, jsonb, text) TO anon, authenticated;

-- Wrapper público (SECURITY INVOKER) — mesmo padrão dos existentes.
CREATE OR REPLACE FUNCTION public.solicitar_ajustes_ponto_app(
  p_token text,
  p_cpf text DEFAULT NULL,
  p_correcoes jsonb DEFAULT '[]'::jsonb,
  p_ausencias jsonb DEFAULT '[]'::jsonb,
  p_anexos jsonb DEFAULT '[]'::jsonb,
  p_selfie_url text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY INVOKER
AS $wrapapp$
BEGIN
  RETURN externo.solicitar_ajustes_ponto_app(p_token, p_cpf, p_correcoes, p_ausencias, p_anexos, p_selfie_url);
END;
$wrapapp$;

GRANT EXECUTE ON FUNCTION public.solicitar_ajustes_ponto_app(text, text, jsonb, jsonb, jsonb, text) TO anon, authenticated;

-- 4) Selfie do pedido legível pelo RH da mesma empresa -------------------------
CREATE OR REPLACE FUNCTION public.ponto_selfie_do_meu_tenant(p_caminho text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $selfie$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_marcacoes m
    WHERE m.selfie_url IS NOT NULL
      AND public.ponto_selfie_caminho(m.selfie_url) = p_caminho
      AND m.tenant_id = public.current_user_tenant_id()
  ) OR EXISTS (
    SELECT 1 FROM public.ponto_ajustes a
    WHERE a.selfie_url = p_caminho
      AND a.tenant_id = public.current_user_tenant_id()
  );
$selfie$;

REVOKE ALL ON FUNCTION public.ponto_selfie_do_meu_tenant(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_selfie_do_meu_tenant(text) TO authenticated;

-- 5) QA --------------------------------------------------------------------------
-- Massa comum das rotinas do app novo (tudo no cercado; as rotinas desfazem
-- tudo no fim com qa_rollback). Devolve ids no jsonb.
CREATE OR REPLACE FUNCTION public.qa_ponto_app_massa(p_semente int)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $massa$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  v_emp uuid;
  v_cpf text;
  v_adm uuid;
  v_tok text := 'qa_app_' || p_semente || '_' || replace(gen_random_uuid()::text, '-', '');
  v_corr uuid := gen_random_uuid();
  v_aus uuid := gen_random_uuid();
  v_aus_nao uuid := gen_random_uuid();
  v_aus_conf uuid := gen_random_uuid();
  v_inativa uuid := gen_random_uuid();
  v_fora uuid := gen_random_uuid();
BEGIN
  v_emp := public.qa_nova_empresa('[QA-PONTO] Empresa App', '11222333000181');
  v_cpf := public.qa_ponto_admissao('[QA-PONTO] App ' || p_semente, p_semente, v_emp, DATE '2026-01-01');
  v_adm := (SELECT a.id FROM public.admissoes a WHERE a.tenant_id = v_t AND a.cpf = v_cpf
             ORDER BY (a.status = 'concluido') DESC, a.created_at NULLS LAST LIMIT 1);
  UPDATE public.admissoes SET empresa_id = v_emp WHERE id = v_adm;

  INSERT INTO public.ponto_links (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, token, ativo, tipo)
  VALUES (v_t, v_adm::text, '[QA-PONTO] App ' || p_semente, v_cpf, v_tok, true, 'colaborador');

  INSERT INTO public.ponto_justificativas
    (id, tenant_id, empresa_id, nome, tipo_abono, natureza, aparece_no_app, ativo, ordem, requer_anexo)
  VALUES
    (v_corr,     v_t, NULL, '[QA-PONTO] App correção ' || v_corr,      'nao',          'correcao_batida', true,  true,  950, false),
    (v_aus,      v_t, NULL, '[QA-PONTO] App ausência abona ' || v_aus,  'sim',          'ausencia',        true,  true,  951, true),
    (v_aus_nao,  v_t, NULL, '[QA-PONTO] App ausência não abona ' || v_aus_nao, 'nao',   'ausencia',        true,  true,  952, true),
    (v_aus_conf, v_t, NULL, '[QA-PONTO] App ausência configurável ' || v_aus_conf, 'configuravel', 'ausencia', true, true, 953, true),
    (v_inativa,  v_t, NULL, '[QA-PONTO] App inativa ' || v_inativa,     'nao',          'correcao_batida', true,  false, 954, false),
    (v_fora,     v_t, NULL, '[QA-PONTO] App fora do app ' || v_fora,    'nao',          'correcao_batida', false, true,  955, false);

  -- dia de ontem (e o de anteontem) com a folha aberta
  DELETE FROM public.ponto_fechamentos
   WHERE tenant_id = v_t
     AND competencia IN (to_char(CURRENT_DATE - 1, 'YYYY-MM'), to_char(CURRENT_DATE - 2, 'YYYY-MM'));

  RETURN jsonb_build_object('tenant', v_t, 'empresa', v_emp, 'cpf', v_cpf, 'adm', v_adm, 'token', v_tok,
                            'corr', v_corr, 'aus', v_aus, 'aus_nao', v_aus_nao, 'aus_conf', v_aus_conf,
                            'inativa', v_inativa, 'fora', v_fora,
                            'selfie', 'externo/ajustes/' || v_tok || '/qa_selfie.jpg',
                            'anexo', jsonb_build_array(jsonb_build_object(
                               'nome', 'qa_atestado.pdf', 'url', 'externo/' || v_tok || '/qa_atestado.pdf',
                               'tamanho', 1000, 'tipo', 'application/pdf')));
END $massa$;

-- PONTO-492 — justificativas do app novo
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_492()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa492$
DECLARE
  r public.qa_retorno;
  m jsonb;
  v_res json;
  v_ids text[];
  v_sem_natureza int;
  v_tem_selfie boolean;
  v_erro_token text;
  v_ok boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Listar as justificativas do app pelo link do cercado';
  r.esperado    := 'Traz correção e ausência marcadas "no app"; esconde inativa e "fora do app"; '
                || 'toda linha tem natureza; informa se a selfie é exigida; link inválido é recusado';

  IF to_regprocedure('public.listar_justificativas_app(text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'listar_justificativas_app ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  BEGIN
    m := public.qa_ponto_app_massa(49201);
    v_res := public.listar_justificativas_app(m->>'token');
    v_ids := ARRAY(SELECT e->>'id' FROM json_array_elements(v_res->'justificativas') e);
    v_sem_natureza := (SELECT count(*) FROM json_array_elements(v_res->'justificativas') e
                        WHERE COALESCE(e->>'natureza', '') = '');
    v_tem_selfie := (v_res->>'exigir_selfie') IS NOT NULL;
    v_erro_token := public.listar_justificativas_app('qa_token_inexistente_' || gen_random_uuid())->>'error';

    v_ok := (m->>'corr') = ANY (v_ids) AND (m->>'aus') = ANY (v_ids)
        AND NOT ((m->>'inativa') = ANY (v_ids)) AND NOT ((m->>'fora') = ANY (v_ids))
        AND v_sem_natureza = 0 AND v_tem_selfie AND v_erro_token IS NOT NULL;
    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('qtd', COALESCE(array_length(v_ids, 1), 0), 'sem_natureza', v_sem_natureza,
                                  'informa_selfie', v_tem_selfie, 'erro_token', v_erro_token);
  IF v_ok THEN
    r.situacao := 'passou';
    r.obtido := 'O app lista só as justificativas liberadas, com natureza; inativa e "fora do app" ficam de fora.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: lista do app incoerente (itens=%s, sem natureza=%s, informa selfie=%s, link inválido recusado=%s).',
                       COALESCE(array_length(v_ids, 1), 0), v_sem_natureza, v_tem_selfie, v_erro_token IS NOT NULL);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa492$;

-- PONTO-493 — pedido de correção de batida pelo app (+ selfie)
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_493()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa493$
DECLARE
  r public.qa_retorno;
  m jsonb;
  v_d date := CURRENT_DATE - 1;
  v_corr jsonb;
  v_res json;
  v_id uuid;
  v_aj public.ponto_ajustes;
  v_outro uuid;
  v_sem_selfie text; v_sem_selfie_livre text;
  v_err_aus text; v_err_inat text; v_err_fora text; v_err_outro text; v_err_inex text;
  v_gravou boolean := false;
  v_recusas int := 0;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Pedir correção de batida pelo app (com e sem selfie; com justificativas válidas e inválidas)';
  r.esperado    := 'Grava justificativa_id, natureza correcao_batida, empresa e selfie; recusa sem selfie quando a empresa exige; '
                || 'recusa justificativa de ausência, inativa, fora do app, de outra empresa ou inexistente';

  IF to_regprocedure('public.solicitar_ajustes_ponto_app(text,text,jsonb,jsonb,jsonb,text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'solicitar_ajustes_ponto_app ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  BEGIN
    m := public.qa_ponto_app_massa(49301);
    v_corr := jsonb_build_array(jsonb_build_object('data', v_d, 'hora', '09:00:00', 'hora_original', NULL,
                'tipo', 'entrada', 'justificativa_id', m->>'corr', 'observacao', 'QA correção'));

    -- selfie exigida (padrão sem configuração): sem selfie é recusado
    DELETE FROM public.ponto_configuracao WHERE tenant_id = (m->>'tenant')::uuid;
    v_sem_selfie := public.solicitar_ajustes_ponto_app(m->>'token', NULL, v_corr, '[]'::jsonb, '[]'::jsonb, NULL)->>'error';

    -- justificativas inválidas
    v_err_aus := public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                   jsonb_set(v_corr, '{0,justificativa_id}', to_jsonb(m->>'aus')), '[]'::jsonb, '[]'::jsonb, m->>'selfie')->>'error';
    v_err_inat := public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                   jsonb_set(v_corr, '{0,justificativa_id}', to_jsonb(m->>'inativa')), '[]'::jsonb, '[]'::jsonb, m->>'selfie')->>'error';
    v_err_fora := public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                   jsonb_set(v_corr, '{0,justificativa_id}', to_jsonb(m->>'fora')), '[]'::jsonb, '[]'::jsonb, m->>'selfie')->>'error';
    v_err_inex := public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                   jsonb_set(v_corr, '{0,justificativa_id}', to_jsonb(gen_random_uuid()::text)), '[]'::jsonb, '[]'::jsonb, m->>'selfie')->>'error';
    v_outro := (SELECT j.id FROM public.ponto_justificativas j
                 WHERE j.tenant_id <> (m->>'tenant')::uuid AND j.ativo AND j.aparece_no_app
                   AND j.natureza = 'correcao_batida' LIMIT 1);
    IF v_outro IS NOT NULL THEN
      v_err_outro := public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                     jsonb_set(v_corr, '{0,justificativa_id}', to_jsonb(v_outro::text)), '[]'::jsonb, '[]'::jsonb, m->>'selfie')->>'error';
    ELSE
      v_err_outro := '(sem justificativa de outra empresa na base: passo pulado)';
    END IF;
    v_recusas := (CASE WHEN v_err_aus IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN v_err_inat IS NOT NULL THEN 1 ELSE 0 END)
               + (CASE WHEN v_err_fora IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN v_err_inex IS NOT NULL THEN 1 ELSE 0 END)
               + (CASE WHEN v_err_outro IS NOT NULL THEN 1 ELSE 0 END);

    -- pedido válido com selfie
    v_res := public.solicitar_ajustes_ponto_app(m->>'token', NULL, v_corr, '[]'::jsonb, '[]'::jsonb, m->>'selfie');
    v_id := (v_res->'ids'->>0)::uuid;
    v_aj := (SELECT a FROM public.ponto_ajustes a WHERE a.id = v_id);
    v_gravou := v_aj.id IS NOT NULL
      AND v_aj.justificativa_id = (m->>'corr')::uuid
      AND v_aj.natureza = 'correcao_batida'
      AND v_aj.empresa_id IS NOT DISTINCT FROM (m->>'empresa')::uuid
      AND v_aj.tipo_ajuste = 'inclusao'
      AND v_aj.selfie_url = m->>'selfie'
      AND v_aj.observacao = 'QA correção';

    -- empresa que desliga a selfie no link: pedido sem selfie passa
    INSERT INTO public.ponto_configuracao (tenant_id, exigir_selfie_link) VALUES ((m->>'tenant')::uuid, false);
    v_sem_selfie_livre := COALESCE(public.solicitar_ajustes_ponto_app(m->>'token', NULL,
                            jsonb_set(v_corr, '{0,hora}', to_jsonb('10:00:00'::text)), '[]'::jsonb, '[]'::jsonb, NULL)->>'error', 'ok');

    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('gravou', v_gravou, 'sem_selfie', v_sem_selfie, 'sem_selfie_config_desligada', v_sem_selfie_livre,
                                  'recusas', v_recusas, 'err_ausencia', v_err_aus, 'err_inativa', v_err_inat,
                                  'err_fora_app', v_err_fora, 'err_inexistente', v_err_inex, 'err_outra_empresa', v_err_outro);
  IF v_gravou AND v_sem_selfie IS NOT NULL AND v_sem_selfie_livre = 'ok' AND v_recusas = 5 THEN
    r.situacao := 'passou';
    r.obtido := 'Correção pelo app grava justificativa, natureza, empresa e selfie; sem selfie é recusada quando a empresa exige; '
             || 'justificativas inválidas são recusadas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: gravou certo=%s; sem selfie recusado=%s; sem selfie com config desligada=%s; recusas=%s de 5.',
                       v_gravou, v_sem_selfie IS NOT NULL, v_sem_selfie_livre, v_recusas);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa493$;

-- PONTO-494 — pedido de ausência pelo app
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_494()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $qa494$
DECLARE
  r public.qa_retorno;
  m jsonb;
  v_d date := CURRENT_DATE - 1;
  v_d2 date := CURRENT_DATE - 2;
  v_aus jsonb;
  v_res json;
  v_aj public.ponto_ajustes;
  v_aj2 public.ponto_ajustes;
  e_sem_anexo text; e_fim text; e_futuro text; e_fora text; e_fechado text; e_dup text; e_trig_anexo text; e_trig_corr text;
  v_ok_parcial boolean := false;
  v_ok_inteiro boolean := false;
  v_recusas int := 0;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Pedir ausência pelo app (parcial e dia inteiro) e tentar os casos proibidos';
  r.esperado    := 'Ausência válida grava natureza, período e anexo, sem horário de batida; recusa sem anexo, fim antes do início, '
                || 'data futura, anexo fora da pasta do link, folha fechada e segunda ausência no mesmo dia; o gatilho recusa '
                || 'ausência sem anexo e justificativa de ausência usada para corrigir horário';

  IF to_regprocedure('public.solicitar_ajustes_ponto_app(text,text,jsonb,jsonb,jsonb,text)') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'solicitar_ajustes_ponto_app ausente.'; RETURN r;
  END IF;

  PERFORM public.qa_modo_ligar();
  BEGIN
    m := public.qa_ponto_app_massa(49401);
    v_aus := jsonb_build_array(jsonb_build_object('data', v_d, 'dia_inteiro', false, 'hora_inicio', '14:00',
               'hora_fim', '16:00', 'justificativa_id', m->>'aus', 'observacao', 'QA consulta', 'anexos', m->'anexo'));

    e_sem_anexo := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
                     jsonb_set(v_aus, '{0,anexos}', '[]'::jsonb), '[]'::jsonb, m->>'selfie')->>'error';
    e_fim := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
                     jsonb_set(v_aus, '{0,hora_fim}', to_jsonb('13:00'::text)), '[]'::jsonb, m->>'selfie')->>'error';
    e_futuro := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
                     jsonb_set(v_aus, '{0,data}', to_jsonb((CURRENT_DATE + 2)::text)), '[]'::jsonb, m->>'selfie')->>'error';
    e_fora := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
                     jsonb_set(v_aus, '{0,anexos}', jsonb_build_array(jsonb_build_object('nome', 'x.pdf',
                       'url', 'externo/outro_link/x.pdf'))), '[]'::jsonb, m->>'selfie')->>'error';

    -- válida (parcial)
    v_res := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb, v_aus, '[]'::jsonb, m->>'selfie');
    v_aj := (SELECT a FROM public.ponto_ajustes a WHERE a.id = (v_res->'ids'->>0)::uuid);
    v_ok_parcial := v_aj.id IS NOT NULL AND v_aj.natureza = 'ausencia' AND v_aj.tipo_ajuste = 'justificativa'
      AND v_aj.hora_solicitada IS NULL AND NOT COALESCE(v_aj.dia_inteiro, false)
      AND v_aj.ausencia_hora_inicio = TIME '14:00' AND v_aj.ausencia_hora_fim = TIME '16:00'
      AND jsonb_array_length(v_aj.anexos) = 1 AND v_aj.justificativa_id = (m->>'aus')::uuid
      AND v_aj.empresa_id IS NOT DISTINCT FROM (m->>'empresa')::uuid;

    -- segunda ausência no mesmo dia
    e_dup := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb, v_aus, '[]'::jsonb, m->>'selfie')->>'error';

    -- válida (dia inteiro, outro dia)
    v_res := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
               jsonb_build_array(jsonb_build_object('data', v_d2, 'dia_inteiro', true,
                 'justificativa_id', m->>'aus_nao', 'anexos', m->'anexo')), '[]'::jsonb, m->>'selfie');
    v_aj2 := (SELECT a FROM public.ponto_ajustes a WHERE a.id = (v_res->'ids'->>0)::uuid);
    v_ok_inteiro := v_aj2.id IS NOT NULL AND v_aj2.natureza = 'ausencia' AND COALESCE(v_aj2.dia_inteiro, false)
      AND v_aj2.ausencia_hora_inicio IS NULL AND v_aj2.hora_solicitada IS NULL;

    -- folha fechada
    INSERT INTO public.ponto_fechamentos (tenant_id, competencia, status)
    VALUES ((m->>'tenant')::uuid, to_char(CURRENT_DATE - 3, 'YYYY-MM'), 'fechado');
    e_fechado := public.solicitar_ajustes_ponto_app(m->>'token', NULL, '[]'::jsonb,
                   jsonb_set(v_aus, '{0,data}', to_jsonb((CURRENT_DATE - 3)::text)), '[]'::jsonb, m->>'selfie')->>'error';

    -- gatilho (gravação direta, como o RH ou uma API faria)
    BEGIN
      INSERT INTO public.ponto_ajustes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data_referencia,
        tipo_ajuste, motivo, justificativa_id, dia_inteiro, anexos)
      VALUES ((m->>'tenant')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App', m->>'cpf', CURRENT_DATE - 4,
        'justificativa', 'QA', (m->>'aus')::uuid, true, '[]'::jsonb);
    EXCEPTION WHEN check_violation THEN e_trig_anexo := SQLERRM;
    END;
    BEGIN
      INSERT INTO public.ponto_ajustes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data_referencia,
        tipo_ajuste, tipo_marcacao, hora_solicitada, motivo, justificativa_id, anexos)
      VALUES ((m->>'tenant')::uuid, (m->>'adm')::uuid, '[QA-PONTO] App', m->>'cpf', CURRENT_DATE - 4,
        'inclusao', 'entrada', TIME '08:00', 'QA', (m->>'aus')::uuid, m->'anexo');
    EXCEPTION WHEN check_violation THEN e_trig_corr := SQLERRM;
    END;

    v_recusas := (CASE WHEN e_sem_anexo IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN e_fim IS NOT NULL THEN 1 ELSE 0 END)
               + (CASE WHEN e_futuro IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN e_fora IS NOT NULL THEN 1 ELSE 0 END)
               + (CASE WHEN e_fechado IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN e_dup IS NOT NULL THEN 1 ELSE 0 END)
               + (CASE WHEN e_trig_anexo IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN e_trig_corr IS NOT NULL THEN 1 ELSE 0 END);
    RAISE EXCEPTION 'qa_rollback';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'qa_rollback' THEN
      r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
    END IF;
  END;

  r.detalhe := jsonb_build_object('parcial_ok', v_ok_parcial, 'dia_inteiro_ok', v_ok_inteiro, 'recusas', v_recusas,
                 'sem_anexo', e_sem_anexo, 'fim_antes', e_fim, 'futuro', e_futuro, 'anexo_fora', e_fora,
                 'fechado', e_fechado, 'duplicada', e_dup, 'gatilho_anexo', e_trig_anexo, 'gatilho_correcao', e_trig_corr);
  IF v_ok_parcial AND v_ok_inteiro AND v_recusas = 8 THEN
    r.situacao := 'passou';
    r.obtido := 'Ausência pelo app grava natureza, período e anexo (sem horário de batida); os 8 casos proibidos são recusados.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: parcial ok=%s; dia inteiro ok=%s; recusas=%s de 8 (ver detalhe).',
                       v_ok_parcial, v_ok_inteiro, v_recusas);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $qa494$;

-- Documentação dos casos
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-492/493/494 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-492',
   'App de ajuste: lista só as justificativas liberadas, com natureza',
   'feliz', 'alta', 'aprovado', 'api',
   'Portaria MTP 671/2021 (tratamento de marcações)',
   'O app do colaborador mostra apenas as justificativas que o RH marcou "Aparece no app", separadas em Correção de batida e Ausência. '
   || 'Inativas e as que são só lançamento do RH não aparecem. A resposta também informa se a empresa exige selfie.',
   'Cercado de QA com link de ponto e catálogo.',
   '[{"ordem":1,"acao":"Chamar listar_justificativas_app com o link do cercado","resultado_esperado":"Traz as liberadas no app, todas com natureza"},
     {"ordem":2,"acao":"Conferir a inativa e a fora do app","resultado_esperado":"Não aparecem"},
     {"ordem":3,"acao":"Chamar com link inexistente","resultado_esperado":"Erro de link inválido"}]'::jsonb,
   'Só justificativas liberadas, com natureza; link inválido recusado.',
   'Fase 2 do Ponto, F3 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).'),

  (v_mod, 'PONTO-493',
   'App de ajuste: correção de batida grava justificativa, natureza, empresa e selfie',
   'negativo', 'critica', 'aprovado', 'api',
   'Portaria MTP 671/2021, art. 74 (tratamento de marcações com motivo rastreável); LGPD art. 11 (selfie em bucket privado)',
   'O pedido de correção de batida feito pelo app passa a gravar a justificativa do catálogo (não mais texto livre), a natureza '
   || 'Correção de batida, a empresa do colaborador e a selfie. Quando a empresa exige selfie no link, pedido sem selfie é recusado. '
   || 'Justificativa de ausência, inativa, fora do app, de outra empresa ou inexistente é recusada.',
   'Cercado de QA com link de ponto e catálogo.',
   '[{"ordem":1,"acao":"Pedir correção sem selfie (empresa exige)","resultado_esperado":"Recusado: tire a selfie"},
     {"ordem":2,"acao":"Pedir correção com justificativa de ausência / inativa / fora do app / outra empresa / inexistente","resultado_esperado":"Recusado em todos"},
     {"ordem":3,"acao":"Pedir correção válida com selfie","resultado_esperado":"Gravado com justificativa_id, natureza correcao_batida, empresa, observação e selfie"},
     {"ordem":4,"acao":"Empresa desliga a selfie no link e pede sem selfie","resultado_esperado":"Aceito"}]'::jsonb,
   'Pedido rastreável e selfie obrigatória quando a empresa exige.',
   'Fase 2 do Ponto, F3 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).'),

  (v_mod, 'PONTO-494',
   'App de ajuste: ausência exige anexo e período válido, e não vira horário de batida',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 473 (abono mediante comprovação); Lei 605/1949, art. 6º, § 1º; Portaria MTP 671/2021',
   'A ausência pedida pelo app (dia inteiro ou início/fim) grava natureza Ausência, o período e o anexo, sem horário de batida. '
   || 'É recusada sem anexo, com fim antes do início, em data futura, com anexo fora da pasta do link, com a folha fechada ou '
   || 'quando já há ausência pendente no dia. O gatilho do banco recusa também gravação direta incoerente.',
   'Cercado de QA com link de ponto e catálogo.',
   '[{"ordem":1,"acao":"Pedir ausência sem anexo / fim antes do início / data futura / anexo de outra pasta","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"Pedir ausência parcial válida (14:00 a 16:00) com anexo","resultado_esperado":"Gravada com natureza ausencia, período, anexo e sem hora de batida"},
     {"ordem":3,"acao":"Pedir de novo no mesmo dia","resultado_esperado":"Recusado: já há ausência aguardando o RH"},
     {"ordem":4,"acao":"Pedir ausência de dia inteiro em outro dia","resultado_esperado":"Gravada como dia inteiro"},
     {"ordem":5,"acao":"Pedir ausência em mês com folha fechada","resultado_esperado":"Recusado"},
     {"ordem":6,"acao":"Gravar direto ausência sem anexo, e justificativa de ausência numa inclusão de horário","resultado_esperado":"O gatilho recusa as duas"}]'::jsonb,
   'Ausência só com documento e período coerente; nunca vira batida.',
   'Fase 2 do Ponto, F3 (out/2026). Tudo desfeito no fim da rotina (qa_rollback).')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-492', 'qa_caso_ponto_492', true),
      ('PONTO-493', 'qa_caso_ponto_493', true),
      ('PONTO-494', 'qa_caso_ponto_494', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-492/493/494 não registrada: %', SQLERRM;
END $doc$;

-- ── Conferência (única) ─────────────────────────────────────────────────────
WITH q492 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_492() r),
     q493 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_493() r),
     q494 AS MATERIALIZED (SELECT r.situacao::text AS s, r.obtido, r.erro_tecnico FROM public.qa_caso_ponto_494() r)
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ponto_ajustes'
      AND column_name IN ('natureza', 'ausencia_hora_inicio', 'ausencia_hora_fim', 'atestado_id', 'selfie_url')) AS colunas_novas_esperado_5,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ponto_ajuste_natureza'
            AND tgrelid = 'public.ponto_ajustes'::regclass AND NOT tgisinternal)                    AS gatilho_ok,
  has_function_privilege('anon', 'public.listar_justificativas_app(text)', 'EXECUTE')               AS app_lista_ok,
  has_function_privilege('anon', 'public.solicitar_ajustes_ponto_app(text,text,jsonb,jsonb,jsonb,text)', 'EXECUTE') AS app_pedido_ok,
  has_function_privilege('anon', 'public.solicitar_ajustes_ponto_externo_cpf_batch(text,text,jsonb,text,jsonb)', 'EXECUTE') AS app_antigo_ok,
  position('ponto_ajustes' IN pg_get_functiondef('public.ponto_selfie_do_meu_tenant(text)'::regprocedure)) > 0 AS selfie_pedido_legivel_rh,
  (SELECT s FROM q492) AS qa_ponto_492,
  (SELECT s FROM q493) AS qa_ponto_493,
  (SELECT s FROM q494) AS qa_ponto_494,
  concat_ws(' | ',
    CASE WHEN (SELECT s FROM q492) <> 'passou' THEN (SELECT coalesce(erro_tecnico, obtido) FROM q492) END,
    CASE WHEN (SELECT s FROM q493) <> 'passou' THEN (SELECT coalesce(erro_tecnico, obtido) FROM q493) END,
    CASE WHEN (SELECT s FROM q494) <> 'passou' THEN (SELECT coalesce(erro_tecnico, obtido) FROM q494) END) AS erro_tecnico;
