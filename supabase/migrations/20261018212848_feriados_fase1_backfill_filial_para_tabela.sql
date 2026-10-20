-- =====================================================================
-- Unificacao de feriados — FASE 1: backfill 'filial' (A) -> calendario (B)
--
-- Contexto: o modulo Ponto tem DOIS cadastros de feriado que a apuracao le
-- por uma fonte unica (funcao public.feriados_da_empresa):
--   A = public.feriados          (por localizacao: nacional/estadual/municipal/filial)
--   B = public.feriado_tabela_*  (calendario nomeado por unidade; prioridade P0)
-- A abrangencia 'filial' de A faz EXATAMENTE o mesmo papel do calendario por
-- unidade de B — e so essa sobreposicao sera eliminada. Nacional/estadual/
-- municipal continuam em A (sao regra por localizacao, 1 linha cobre N
-- unidades; B as replicaria por unidade).
--
-- Esta fase e PURAMENTE ADITIVA: copia cada feriado 'filial' ativo de A para
-- um item no calendario (B) da mesma unidade. NAO apaga nem desativa nada em
-- A. Como B ja tem prioridade e o item e identico, a apuracao (espelho, banco
-- de horas, equalizacao, RN-23) NAO muda — a desativacao de 'filial' em A e a
-- troca no resolver ficam para a FASE 2, apos o teste golden.
--
-- FER-003 (uq_feriado_tabela_empresa_por_unidade): uma unidade tem no maximo
-- UM calendario. O backfill reusa o calendario ja vinculado a unidade; so cria
-- um quando a unidade ainda nao tem. Idempotente: reusa o calendario e
-- deduplica os itens, entao rodar de novo nao cria tabela nem item repetido.
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
      -- descarta linhas malformadas (chk_feriado_item_data)
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
