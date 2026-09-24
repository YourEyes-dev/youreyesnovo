-- ============================================================================
-- ENTREGA — ponto_registrar_folga_compensatoria (drift teste -> producao)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   A producao esta com a versao ANTIGA desta funcao, que tem um bug: ela
--   pede a coluna "j.minutos" de ponto_jornada_do_dia, que NAO existe (a
--   coluna certa e jornada_min). O erro cai no bloco de excecao em silencio e
--   a funcao passa a usar 480 minutos (8h) de jornada para TODO MUNDO. Em quem
--   tem jornada diferente de 8h (ex.: 8h48 = 528 min), cada folga compensatoria
--   de dia inteiro DEBITA MENOS banco de horas do que deveria, sem avisar.
--
--   O teste (fonte da verdade) ja corrigiu isso: le j.jornada_min E ganhou o
--   parametro p_minutos, que permite registrar folga compensatoria PARCIAL
--   (so parte da jornada). Este script traz a producao para esse estado.
--
-- CUIDADO DE COMPATIBILIDADE (tratado abaixo):
--   A producao tem a assinatura de 4 argumentos e o teste a de 5 (p_minutos
--   com valor padrao). Se as duas coexistirem, uma chamada com 4 argumentos
--   fica ambigua ("function is not unique"). Por isso o passo 1 REMOVE a de 4
--   argumentos antes de criar a de 5 — reproduzindo o estado do teste, onde so
--   existe a de 5.
--
-- SEGURANCA: este script so cria/substitui uma FUNCAO. Nao altera nem apaga
--   dado de tabela, entao nao ha linhas a copiar para backup. E idempotente
--   (rodar duas vezes nao quebra nem duplica).
-- ============================================================================

SET lock_timeout = '10s';

-- ── Passo 1: remove a assinatura antiga de 4 argumentos (sem p_minutos) ─────
-- IF EXISTS torna o passo idempotente: na segunda execucao nao ha o que remover.
DROP FUNCTION IF EXISTS public.ponto_registrar_folga_compensatoria(uuid, text, date, text);

-- ── Passo 2: cria/substitui a versao correta (5 argumentos, do teste) ───────
CREATE OR REPLACE FUNCTION public.ponto_registrar_folga_compensatoria(p_tenant_id uuid, p_colaborador_cpf text, p_data date, p_observacao text DEFAULT NULL::text, p_minutos integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf     text := regexp_replace(coalesce(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_id      uuid; v_cid uuid; v_cnome text; v_eid uuid;
  v_min     int;
  v_jornada int;
  v_comp    text := to_char(p_data, 'YYYY-MM');
  v_banco   uuid;
  v_obs     text;
  v_parcial boolean := (p_minutos IS NOT NULL AND p_minutos > 0);
BEGIN
  IF v_cpf = '' OR p_data IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'CPF e data sao obrigatorios');
  END IF;

  SELECT d.id, d.colaborador_id, d.colaborador_nome, d.empresa_id
    INTO v_id, v_cid, v_cnome, v_eid
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND regexp_replace(d.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND d.data = p_data
  ORDER BY d.empresa_id NULLS LAST
  LIMIT 1;

  IF v_cid IS NULL THEN
    SELECT a.id, a.nome_completo, a.empresa_id INTO v_cid, v_cnome, v_eid
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(coalesce(a.cpf, ''), '[^0-9]', '', 'g') = v_cpf
      AND coalesce(a.inativo, false) = false
    ORDER BY a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_cid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'motivo', 'colaborador nao encontrado');
  END IF;

  -- A jornada prevista do dia, que e o teto da folga.
  -- A coluna chama-se jornada_min. A versao anterior pedia "j.minutos", que
  -- nao existe: o erro caia no EXCEPTION e a funcao usava 480 para todo
  -- mundo, em silencio. Numa jornada de 8h48 (528 min) isso debitava 48
  -- minutos a MENOS do banco a cada folga de dia inteiro.
  BEGIN
    SELECT j.jornada_min INTO v_jornada
    FROM public.ponto_jornada_do_dia(p_tenant_id, v_cpf, v_cid::text, p_data) j;
  EXCEPTION WHEN OTHERS THEN
    v_jornada := NULL;
  END;
  v_jornada := COALESCE(NULLIF(v_jornada, 0), 480);

  IF v_parcial THEN
    IF p_minutos > v_jornada THEN
      RETURN jsonb_build_object('success', false,
        'motivo', format('A folga pedida (%s min) e maior que a jornada do dia (%s min).',
                         p_minutos, v_jornada));
    END IF;
    v_min := p_minutos;
  ELSE
    v_min := v_jornada;
  END IF;

  v_obs := COALESCE(p_observacao,
    CASE WHEN v_parcial
         THEN 'Folga compensatoria parcial (banco de horas)'
         ELSE 'Folga compensatoria (banco de horas)' END);

  -- (1) O dia: neutro, nunca falta.
  --     Na folga do dia INTEIRO as horas vao a zero, como sempre foi.
  --     Na folga PARCIAL o que foi trabalhado PERMANECE — zerar apagaria a
  --     manha que a pessoa cumpriu. O deficit da tarde nao vira debito da
  --     apuracao porque o dia fica justificado; quem debita e a
  --     movimentacao de compensacao abaixo, uma vez so.
  IF v_id IS NOT NULL THEN
    UPDATE public.ponto_diario
       SET tipo_dia          = 'folga_compensatoria',
           status            = 'justificado',
           horas_trabalhadas = CASE WHEN v_parcial THEN horas_trabalhadas
                                    ELSE make_interval(mins => 0) END,
           horas_faltantes   = make_interval(mins => 0),
           atraso_minutos    = 0,
           observacao        = v_obs,
           updated_at        = now()
     WHERE id = v_id;
  ELSE
    INSERT INTO public.ponto_diario
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
       horas_trabalhadas, horas_faltantes, status, tipo_dia, observacao)
    VALUES
      (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, p_data,
       make_interval(mins => 0), make_interval(mins => 0), 'justificado',
       'folga_compensatoria', v_obs);
  END IF;

  -- (2) O banco: debito do tipo 'compensacao', separado das ausencias.
  SELECT b.id INTO v_banco
  FROM public.ponto_banco_horas b
  WHERE b.tenant_id = p_tenant_id
    AND regexp_replace(b.colaborador_cpf, '[^0-9]', '', 'g') = v_cpf
    AND b.competencia = v_comp
  ORDER BY b.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_banco IS NULL THEN
    INSERT INTO public.ponto_banco_horas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
       competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
       compensados_minutos, saldo_atual_minutos, convertido_extras)
    VALUES (p_tenant_id, v_eid, v_cid, v_cnome, v_cpf, 'mensal',
            v_comp, 0, 0, 0, 0, 0, false)
    RETURNING id INTO v_banco;
  END IF;

  -- Idempotente: a mesma folga nao debita duas vezes.
  IF EXISTS (
    SELECT 1 FROM public.ponto_banco_horas_movimentacoes m
    WHERE m.banco_horas_id = v_banco AND m.tipo = 'compensacao'
      AND m.data_referencia = p_data
  ) THEN
    RETURN jsonb_build_object('success', true, 'ja_registrada', true,
                              'minutos', v_min, 'parcial', v_parcial,
                              'competencia', v_comp);
  END IF;

  INSERT INTO public.ponto_banco_horas_movimentacoes
    (tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao, origem)
  VALUES (p_tenant_id, v_banco, v_cpf, p_data, 'compensacao', v_min,
          v_obs || ' — ' || to_char(p_data, 'DD/MM/YYYY')
          || CASE WHEN v_parcial THEN format(' (%s de %s min da jornada)', v_min, v_jornada) ELSE '' END,
          'folga_compensatoria');

  UPDATE public.ponto_banco_horas
     SET compensados_minutos = COALESCE(compensados_minutos, 0) + v_min,
         saldo_atual_minutos = COALESCE(saldo_atual_minutos, 0) - v_min,
         updated_at = now()
   WHERE id = v_banco;

  RETURN jsonb_build_object('success', true, 'minutos', v_min, 'parcial', v_parcial,
                            'jornada_min', v_jornada, 'competencia', v_comp);
END;
$fn$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Esperado: com_p_minutos = 1, sem_p_minutos = 0, total = 1, status = OK.
SELECT
  count(*) FILTER (WHERE pg_get_function_arguments(p.oid) LIKE '%p_minutos%')     AS com_p_minutos,
  count(*) FILTER (WHERE pg_get_function_arguments(p.oid) NOT LIKE '%p_minutos%') AS sem_p_minutos,
  count(*)                                                                        AS total,
  CASE
    WHEN count(*) = 1
     AND bool_or(pg_get_function_arguments(p.oid) LIKE '%p_minutos%')
    THEN 'OK'
    ELSE 'CONFERIR'
  END                                                                            AS status
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'ponto_registrar_folga_compensatoria';
