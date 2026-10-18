-- =====================================================================
-- ENTREGA — Unificacao de feriados, FASE 1
-- Backfill dos feriados de abrangencia 'filial' (tabela A: public.feriados)
-- para o calendario por unidade (modelo B: public.feriado_tabela_*).
--
-- SEGURO / ADITIVO: so CRIA itens (e, quando falta, o calendario da unidade e
-- o vinculo). NAO apaga nem desativa nada em public.feriados. Como o modelo B
-- ja tem prioridade na fonte unica public.feriados_da_empresa e o item copiado
-- e identico ao feriado 'filial', a apuracao (espelho, banco de horas,
-- equalizacao, RN-23) NAO muda. A retirada de 'filial' de A e a simplificacao
-- do resolver ficam para a FASE 2 (apos o teste golden).
--
-- Por ser so-cria-coisa-nova, NAO leva backup (a regra exige backup apenas
-- quando o script ALTERA ou APAGA dado existente).
--
-- Idempotente: reusa o calendario ja vinculado a unidade (FER-003: um por
-- unidade) e deduplica os itens. Rode o arquivo inteiro de uma vez.
--
-- Conferencia esperada no fim: faltando = 0.
-- =====================================================================

DO $backfill$
DECLARE
  v_unit   RECORD;
  v_tabela uuid;
BEGIN
  FOR v_unit IN
    SELECT DISTINCT f.tenant_id, f.empresa_id
    FROM public.feriados f
    WHERE f.abrangencia = 'filial'
      AND f.tenant_id IS NOT NULL
      AND f.empresa_id IS NOT NULL
      AND COALESCE(f.ativo, true) = true
  LOOP
    -- 1) Calendario da unidade: reusa o vinculado (FER-003) ou cria um novo.
    SELECT v.tabela_id INTO v_tabela
    FROM public.feriado_tabela_empresas v
    WHERE v.tenant_id = v_unit.tenant_id
      AND v.empresa_id = v_unit.empresa_id
    LIMIT 1;

    IF v_tabela IS NULL THEN
      INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, descricao, ativo)
      SELECT v_unit.tenant_id, 'Calendario da unidade',
             ec.estado, ec.cidade, NULL,
             'Criado na unificacao de feriados (migracao da abrangencia Filial).',
             true
      FROM public.empresa_cadastro ec
      WHERE ec.id = v_unit.empresa_id
      RETURNING id INTO v_tabela;

      -- Unidade sem cadastro de empresa: nada a vincular, pula.
      IF v_tabela IS NULL THEN
        CONTINUE;
      END IF;

      INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
      VALUES (v_unit.tenant_id, v_tabela, v_unit.empresa_id)
      ON CONFLICT (tenant_id, empresa_id) DO NOTHING;

      -- Em caso de corrida, usa o vinculo vencedor.
      SELECT v.tabela_id INTO v_tabela
      FROM public.feriado_tabela_empresas v
      WHERE v.tenant_id = v_unit.tenant_id AND v.empresa_id = v_unit.empresa_id
      LIMIT 1;
    END IF;

    -- 2) Itens: copia cada 'filial' da unidade que ainda nao exista no
    --    calendario. O trigger feriado_item_before normaliza dia/mes<->data.
    INSERT INTO public.feriado_tabela_itens
      (tenant_id, tabela_id, nome, data, recorrente, dia, mes, tipo, ativo)
    SELECT f.tenant_id, v_tabela, f.nome,
           CASE WHEN COALESCE(f.recorrente, false) THEN NULL ELSE f.data END,
           COALESCE(f.recorrente, false),
           CASE WHEN COALESCE(f.recorrente, false) THEN f.dia ELSE NULL END,
           CASE WHEN COALESCE(f.recorrente, false) THEN f.mes ELSE NULL END,
           CASE WHEN f.tipo = 'facultativo' THEN 'facultativo' ELSE 'feriado' END,
           COALESCE(f.ativo, true)
    FROM public.feriados f
    WHERE f.abrangencia = 'filial'
      AND f.tenant_id = v_unit.tenant_id
      AND f.empresa_id = v_unit.empresa_id
      AND COALESCE(f.ativo, true) = true
      AND (
        (COALESCE(f.recorrente, false) = true  AND f.dia BETWEEN 1 AND 31 AND f.mes BETWEEN 1 AND 12)
        OR (COALESCE(f.recorrente, false) = false AND f.data IS NOT NULL)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.feriado_tabela_itens it
        WHERE it.tabela_id = v_tabela
          AND it.nome = f.nome
          AND COALESCE(it.recorrente, false) = COALESCE(f.recorrente, false)
          AND (
            (COALESCE(f.recorrente, false) = true  AND it.dia = f.dia AND it.mes = f.mes)
            OR (COALESCE(f.recorrente, false) = false AND it.data = f.data)
          )
      );
  END LOOP;
END
$backfill$;

-- ---------------------------------------------------------------------
-- CONFERENCIA (o editor mostra so o ultimo resultado):
--   filial_em_A    = feriados 'filial' ativos e validos na tabela A
--   migrado_para_B = quantos ja tem item correspondente no calendario da unidade
--   faltando       = quantos ainda NAO foram para B (esperado: 0)
-- ---------------------------------------------------------------------
WITH fil AS (
  SELECT f.tenant_id, f.empresa_id, f.nome,
         COALESCE(f.recorrente, false) AS recorrente, f.data, f.dia, f.mes,
         (SELECT v.tabela_id FROM public.feriado_tabela_empresas v
           WHERE v.tenant_id = f.tenant_id AND v.empresa_id = f.empresa_id
           LIMIT 1) AS tabela_id
  FROM public.feriados f
  WHERE f.abrangencia = 'filial'
    AND f.tenant_id IS NOT NULL
    AND f.empresa_id IS NOT NULL
    AND COALESCE(f.ativo, true) = true
    AND (
      (COALESCE(f.recorrente, false) = true  AND f.dia BETWEEN 1 AND 31 AND f.mes BETWEEN 1 AND 12)
      OR (COALESCE(f.recorrente, false) = false AND f.data IS NOT NULL)
    )
),
marcado AS (
  SELECT fil.*,
         (fil.tabela_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.feriado_tabela_itens it
            WHERE it.tabela_id = fil.tabela_id
              AND it.nome = fil.nome
              AND COALESCE(it.recorrente, false) = fil.recorrente
              AND (
                (fil.recorrente = true  AND it.dia = fil.dia AND it.mes = fil.mes)
                OR (fil.recorrente = false AND it.data = fil.data)
              )
         )) AS tem_em_b
  FROM fil
)
SELECT
  count(*)                               AS filial_em_A,
  count(*) FILTER (WHERE tem_em_b)       AS migrado_para_B,
  count(*) FILTER (WHERE NOT tem_em_b)   AS faltando
FROM marcado;
