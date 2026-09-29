-- ============================================================================
-- ENTREGA — GUARDAS ADM (cotas de aprendiz e PcD) na HOMOLOGAÇÃO (fila de porte)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Estes motores já estão verdes no teste (aplicados por migration) e
-- ainda não haviam sido colados aqui.
--
-- Cobre (só o que faltava portar):
--   ADM-040 · motor da cota de aprendiz (CLT art. 429: 5%..15% da base) —
--             recalcula piso/teto e alimenta o "realizado" das admissões ativas.
--   ADM-041 · enquadramento PcD/reabilitado na admissão alimentando o realizado
--             (pcd_quantidade_atual) automaticamente.
--
-- JÁ PORTADOS antes (NÃO repetidos): ADM-020 (CHECK de experiência ≤90 dias, em
--   script_motor_qa_fases_0a3.sql) e o motor de PcD recalcular_cota_pcd/
--   auto_cota_pcd (já vive na produção). A função admissao_atualiza_realizado_cotas
--   e seu gatilho são COMPARTILHADOS por ADM-040 e ADM-041 — entram uma vez só.
--
-- SEGURANÇA:
--   • NÃO cria tabela (auto-RLS do editor não liga); NÃO apaga dado. As colunas
--     novas nascem com default false (metadata-only, sem reescrever a tabela).
--   • Dois gatilhos em DUAS tabelas (empresa_cadastro e admissoes) com caminho de
--     escrita admissoes → empresa_cadastro. Se aparecer "deadlock detected",
--     rode o script de novo — é idempotente (aconteceu no FOLHA; limpou na 2ª).
--     O gatilho na tabela quente admissoes é criado por ÚLTIMO. lock_timeout curto.
--   • Idempotente, roda numa transação.
--
-- Origem: migration 20260913160400_fase3_admissao_cotas_e_beneficios (só a seção
--   ADM). Ao fim, conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ══════════════ Colunas de enquadramento em admissoes (ADM-040/041) ══════════
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS enquadramento_pcd boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS reabilitado_inss boolean NOT NULL DEFAULT false;
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS contrato_aprendiz boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.admissoes.enquadramento_pcd IS
  'Admitido enquadrado como PcD (Lei 8.213/91, art. 93) — alimenta a cota realizada.';
COMMENT ON COLUMN public.admissoes.reabilitado_inss IS
  'Admitido reabilitado do INSS — conta na cota de PcD (Lei 8.213/91).';
COMMENT ON COLUMN public.admissoes.contrato_aprendiz IS
  'Contrato de aprendizagem (CLT art. 429) — alimenta a cota de aprendiz realizada.';

-- ══════════════ ADM-040 — motor da cota de aprendiz (empresa_cadastro) ═══════
CREATE OR REPLACE FUNCTION public.recalcular_cota_aprendiz()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_base INTEGER := COALESCE(NEW.total_colaboradores, 0);
BEGIN
  -- Só calcula para quem está sujeito à cota de aprendiz.
  IF NOT COALESCE(NEW.aprendiz_obrigatorio, FALSE) THEN
    RETURN NEW;
  END IF;

  IF v_base > 0 THEN
    -- 5% (piso) e 15% (teto) da base — a lei arredonda a fração para cima.
    NEW.aprendiz_quantidade_minima := CEIL((v_base * 5)  / 100.0);
    NEW.aprendiz_quantidade_maxima := CEIL((v_base * 15) / 100.0);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_cota_aprendiz ON public.empresa_cadastro;
CREATE TRIGGER auto_cota_aprendiz
  BEFORE INSERT OR UPDATE OF total_colaboradores, aprendiz_obrigatorio
  ON public.empresa_cadastro
  FOR EACH ROW EXECUTE FUNCTION public.recalcular_cota_aprendiz();

-- ══════════════ ADM-040 + ADM-041 — realizado das cotas (compartilhado) ══════
CREATE OR REPLACE FUNCTION public.admissao_atualiza_realizado_cotas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_empresa uuid := COALESCE(NEW.empresa_id, OLD.empresa_id);
  v_tenant  uuid := COALESCE(NEW.tenant_id, OLD.tenant_id);
BEGIN
  IF v_empresa IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  UPDATE public.empresa_cadastro ec
     SET pcd_quantidade_atual = (
           SELECT count(*) FROM public.admissoes a
            WHERE a.empresa_id = v_empresa
              AND a.status = 'concluido'
              AND (a.enquadramento_pcd OR a.reabilitado_inss)
         ),
         aprendiz_quantidade_atual = (
           SELECT count(*) FROM public.admissoes a
            WHERE a.empresa_id = v_empresa
              AND a.status = 'concluido'
              AND a.contrato_aprendiz
         )
   WHERE ec.id = v_empresa
     AND ec.tenant_id IS NOT DISTINCT FROM v_tenant;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Gatilho na tabela quente admissoes — por ÚLTIMO.
DROP TRIGGER IF EXISTS trg_admissao_realizado_cotas ON public.admissoes;
CREATE TRIGGER trg_admissao_realizado_cotas
  AFTER INSERT OR DELETE OR
        UPDATE OF status, enquadramento_pcd, reabilitado_inss, contrato_aprendiz, empresa_id
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_atualiza_realizado_cotas();


-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('ADM-040 · coluna contrato de aprendiz',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='contrato_aprendiz')),
    ('ADM-040 · motor da cota de aprendiz (função)',
       (to_regprocedure('public.recalcular_cota_aprendiz()') IS NOT NULL)),
    ('ADM-040 · gatilho auto_cota_aprendiz (empresa_cadastro)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='auto_cota_aprendiz' AND NOT tgisinternal)),
    ('ADM-041 · colunas de enquadramento PcD/reabilitado',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='enquadramento_pcd')
        AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='reabilitado_inss'))),
    ('ADM-040/041 · realizado das cotas (função compartilhada)',
       (to_regprocedure('public.admissao_atualiza_realizado_cotas()') IS NOT NULL)),
    ('ADM-040/041 · gatilho do realizado (admissoes)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_realizado_cotas' AND NOT tgisinternal))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
