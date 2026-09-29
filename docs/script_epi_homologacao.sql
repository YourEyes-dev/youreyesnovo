-- ============================================================================
-- ENTREGA — EPI na HOMOLOGAÇÃO (fila de porte: 10 casos vermelhos)
--
-- Cole INTEIRO no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na
-- PRODUÇÃO. Traz as guardas/motores de EPI já verdes no teste (via migrations)
-- e nunca colados aqui.
--
-- Cobre: EPI-011, 021, 022, 030, 040, 042, 044, 050, 051, 052.
--
-- SEGURANÇA: NÃO cria tabela (sem a pegadinha do auto-RLS do editor); só ALTER
-- ADD COLUMN/CONSTRAINT, CREATE OR REPLACE FUNCTION, triggers, um índice único
-- (embrulhado com pré-checagem de duplicata: se houver chave repetida ele AVISA
-- e não cria, em vez de abortar) e agendamentos pg_cron guardados. As constraints
-- são NOT VALID / permissivas — não quebram dado existente. Idempotente, roda
-- numa transação. Ordem: fase1 → fase3 → fase4.
--
-- Montado das definições mais recentes do repositório (fase1 20260913150500,
-- fase3 20260913160300, fase4 20260914130000), só as partes de EPI. Ao fim,
-- conferência única — esperado tudo 'ok'.
-- ============================================================================

SET lock_timeout = '10s';

-- ════════════════════ 1) FASE 1 — EPI-030: chave da NF única e 44 dígitos ═════
ALTER TABLE public.epi_notas_fiscais DROP CONSTRAINT IF EXISTS chk_epi_nf_chave_44;
ALTER TABLE public.epi_notas_fiscais ADD CONSTRAINT chk_epi_nf_chave_44
  CHECK (chave_acesso IS NULL OR chave_acesso ~ '^[0-9]{44}$') NOT VALID;

DO $epi030idx$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.epi_notas_fiscais
    WHERE chave_acesso IS NOT NULL
    GROUP BY tenant_id, chave_acesso HAVING count(*) > 1
  ) THEN
    RAISE NOTICE 'EPI-030: ha chave_acesso de NF duplicada — indice unico NAO criado. Limpe as duplicatas e rode de novo.';
  ELSE
    DROP INDEX IF EXISTS public.uq_epi_nf_chave_acesso;
    CREATE UNIQUE INDEX uq_epi_nf_chave_acesso ON public.epi_notas_fiscais
      (tenant_id, chave_acesso) WHERE chave_acesso IS NOT NULL;
  END IF;
END $epi030idx$;

-- ════════════════════ 2) FASE 3 — vigilâncias e ciclo (011, 022, 050, 052) ════
-- Helper: abre uma ação no Plano de Ação sem duplicar (por origem_id + origem_modulo).
CREATE OR REPLACE FUNCTION public.plano_acao_abrir(
  p_tenant uuid, p_modulo text, p_origem_id uuid, p_titulo text, p_descricao text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tenant IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.plano_acoes
              WHERE tenant_id = p_tenant AND origem_modulo = p_modulo
                AND origem_id = p_origem_id AND COALESCE(arquivada,false) = false) THEN
    RETURN;
  END IF;
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, descricao, origem_modulo, origem_id, arquivada)
  VALUES (p_tenant,
          upper(left(p_modulo,3)) || '-' || to_char(now(),'YYYYMMDDHH24MISS') || '-' || left(replace(p_origem_id::text,'-',''),6),
          p_titulo, p_descricao, p_modulo, p_origem_id, false);
END;
$$;

-- ── EPI-011: vigia a validade do CA (rotina diária) ─────────────────────────
CREATE OR REPLACE FUNCTION public.epi_ca_vigiar()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- CA vencido ou a vencer em 30 dias abre ação de renovação/recompra.
  FOR t IN
    SELECT id, tenant_id, nome, ca_numero, ca_validade
      FROM public.epi_tipos
     WHERE ca_validade IS NOT NULL
       AND ca_validade <= (CURRENT_DATE + INTERVAL '30 days')
       AND COALESCE(is_active, true) = true
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      CASE WHEN t.ca_validade < CURRENT_DATE
           THEN 'CA vencido: renovar/recomprar ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')'
           ELSE 'CA a vencer: providenciar renovação de ' || COALESCE(t.nome,'EPI') || ' (CA ' || COALESCE(t.ca_numero,'?') || ')' END,
      'ca_validade em ' || to_char(t.ca_validade,'DD/MM/YYYY'));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-022: saldo abaixo do mínimo abre reposição no Plano de Ação ─────────
CREATE OR REPLACE FUNCTION public.epi_verificar_estoque_minimo()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_n integer := 0; t RECORD;
BEGIN
  -- Cada item abaixo do mínimo vira uma reposição em public.plano_acoes
  -- (o helper plano_acao_abrir cuida da não-duplicidade).
  FOR t IN
    SELECT et.id, et.tenant_id, et.nome, et.estoque_minimo,
           COALESCE(SUM(e.quantidade_estoque), 0) AS saldo
      FROM public.epi_tipos et
      LEFT JOIN public.epis e ON e.tipo_id = et.id
     WHERE et.estoque_minimo IS NOT NULL AND et.estoque_minimo > 0
     GROUP BY et.id, et.tenant_id, et.nome, et.estoque_minimo
    HAVING COALESCE(SUM(e.quantidade_estoque), 0) < et.estoque_minimo
  LOOP
    PERFORM public.plano_acao_abrir(
      t.tenant_id, 'epi', t.id,
      'Reposição de EPI: ' || COALESCE(t.nome,'item') || ' abaixo do estoque mínimo',
      'Saldo ' || t.saldo || ' < mínimo ' || t.estoque_minimo);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── EPI-050: entrega calcula a data prevista de troca ───────────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_calcula_troca()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_periodicidade_troca_dias integer;
BEGIN
  IF NEW.data_devolucao_prevista IS NULL AND NEW.data_entrega IS NOT NULL THEN
    SELECT et.periodicidade_troca_dias INTO v_periodicidade_troca_dias
      FROM public.epis e JOIN public.epi_tipos et ON et.id = e.tipo_id
     WHERE e.id = NEW.epi_id;
    IF v_periodicidade_troca_dias IS NOT NULL AND v_periodicidade_troca_dias > 0 THEN
      NEW.data_devolucao_prevista := NEW.data_entrega + v_periodicidade_troca_dias;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_entrega_calcula_troca ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_calcula_troca
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_calcula_troca();

-- ── EPI-052: desligamento gera checklist de devolução dos EPIs ativos ───────
CREATE OR REPLACE FUNCTION public.epi_checklist_devolucao_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ativos integer;
BEGIN
  IF NEW.status = 'desligado' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT count(*) INTO v_ativos
      FROM public.epi_entregas ee
     WHERE ee.tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(ee.colaborador_cpf,''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(NEW.cpf,''), '[^0-9]', '', 'g')
       AND COALESCE(ee.status::text,'') NOT IN ('devolvido', 'descartado');
    IF v_ativos > 0 THEN
      -- Cobra a devolução SEM travar a rescisão (a rescisão segue).
      PERFORM public.plano_acao_abrir(
        NEW.tenant_id, 'epi', NEW.id,
        'Devolução de EPI no desligamento de ' || COALESCE(NEW.nome_completo,'colaborador'),
        v_ativos || ' entrega(s) ativa(s) a conferir/devolver (sem reter verbas — CLT art. 462).');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_epi_checklist_devolucao_desligamento ON public.admissoes;
CREATE TRIGGER trg_epi_checklist_devolucao_desligamento
  AFTER UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.epi_checklist_devolucao_desligamento();

-- ── Agendamentos diários de EPI (pg_cron), guardados ────────────────────────
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('epi-ca-vigiar-diario',      '0 6 * * *', $$SELECT public.epi_ca_vigiar()$$);
    PERFORM cron.schedule('epi-estoque-minimo-diario', '5 6 * * *', $$SELECT public.epi_verificar_estoque_minimo()$$);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento pg_cron de EPI nao aplicado: %', SQLERRM;
END $cron$;

-- ════════════════════ 3) FASE 4 — ciclo físico e entrega (021,040,042,044,051) ═
-- ── EPI-040: trava de entrega de item vencido ───────────────────────────────
CREATE OR REPLACE FUNCTION public.epi_entrega_bloqueia_vencido()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_validade date;
BEGIN
  SELECT e.data_validade INTO v_validade
    FROM public.epis e
   WHERE e.id = NEW.epi_id;

  IF v_validade IS NOT NULL AND v_validade < NEW.data_entrega THEN
    RAISE EXCEPTION
      'EPI vencido em % nao pode ser entregue (data da entrega %): item vencido fica segregado, fora do saldo entregavel (NR-6).',
      to_char(v_validade, 'DD/MM/YYYY'), to_char(NEW.data_entrega, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_bloqueia_vencido ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_bloqueia_vencido
  BEFORE INSERT ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_bloqueia_vencido();

-- ── EPI-021: FEFO — sugestão do lote que vence primeiro ─────────────────────
-- Devolve os lotes com saldo do tipo pedido, ordenados pela validade mais
-- próxima (o que vence primeiro sai primeiro), respeitando tamanho e local
-- quando informados. Vencidos ficam de fora (casa com o EPI-040).
CREATE OR REPLACE FUNCTION public.epi_sugerir_lote_fefo(
  p_tenant   uuid,
  p_tipo_id  uuid,
  p_tamanho  text DEFAULT NULL,
  p_local    text DEFAULT NULL
) RETURNS TABLE (epi_id uuid, codigo text, data_validade date, quantidade_estoque integer)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT e.id, e.codigo, e.data_validade, e.quantidade_estoque
    FROM public.epis e
   WHERE e.tenant_id = p_tenant
     AND e.tipo_id   = p_tipo_id
     AND COALESCE(e.quantidade_estoque, 0) > 0
     AND (e.data_validade IS NULL OR e.data_validade >= CURRENT_DATE)
     AND (p_tamanho IS NULL OR e.tamanho IS NOT DISTINCT FROM p_tamanho)
     AND (p_local   IS NULL OR e.localizacao IS NOT DISTINCT FROM p_local)
   ORDER BY e.data_validade ASC NULLS LAST, e.codigo;
$$;

COMMENT ON FUNCTION public.epi_sugerir_lote_fefo(uuid, uuid, text, text) IS
  'EPI-021: sugere o lote de EPI pela validade mais proxima (FEFO), por tipo x tamanho x local.';

-- ── EPI-042: lacre de integridade (hash) da ficha assinada ──────────────────
ALTER TABLE public.epi_entregas
  ADD COLUMN IF NOT EXISTS assinatura_hash text;

COMMENT ON COLUMN public.epi_entregas.assinatura_hash IS
  'EPI-042: hash SHA-256 do recibo no ato da assinatura — detecta modificacao posterior (Lei 14.063/2020, art. 4, II).';

CREATE OR REPLACE FUNCTION public.epi_entrega_sela_integridade()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- No momento em que a entrega é assinada, grava o hash que lacra o recibo.
  IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL
     AND NEW.assinatura_hash IS NULL THEN
    NEW.assinatura_hash := encode(
      public.digest(
        COALESCE(NEW.assinatura_url, '') || '|' ||
        COALESCE(NEW.recebido_por_assinatura, '') || '|' ||
        NEW.signed_at::text || '|' || NEW.id::text,
        'sha256'),
      'hex');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_sela_integridade ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_sela_integridade
  BEFORE UPDATE OF signed_at ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_sela_integridade();

-- ── EPI-044: arquiva a ficha assinada no módulo Documentos ──────────────────
-- Ao gravar signed_at, registra o recibo em documentos (pasta do colaborador),
-- com tipo e vínculo à entrega. Defensivo: nunca bloqueia a assinatura.
CREATE OR REPLACE FUNCTION public.epi_entrega_arquivar_documento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Ponte epi_entregas -> documentos: leva a ficha assinada para a pasta do
  -- colaborador no modulo Documentos, com vinculo a entrega.
  IF NEW.signed_at IS NOT NULL AND OLD.signed_at IS NULL
     AND COALESCE(NEW.assinatura_url, '') <> '' THEN
    BEGIN
      INSERT INTO public.documentos
        (tenant_id, colaborador_nome, colaborador_cpf, nome_arquivo, nome_original,
         tipo, tamanho, mime_type, storage_path, status, classificacao, observacoes)
      SELECT NEW.tenant_id, NEW.colaborador_nome, NEW.colaborador_cpf,
             'ficha-epi-' || NEW.id::text || '.pdf',
             'Ficha de entrega de EPI',
             'ficha_epi', 0, 'application/pdf', NEW.assinatura_url,
             'ativo', 'documento_epi',
             'Recibo de entrega de EPI ' || NEW.id::text
      WHERE NOT EXISTS (
        SELECT 1 FROM public.documentos d
         WHERE d.tenant_id = NEW.tenant_id
           AND d.storage_path = NEW.assinatura_url
           AND d.tipo = 'ficha_epi'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Arquivamento da ficha de EPI % pulado: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_epi_entrega_arquivar_documento ON public.epi_entregas;
CREATE TRIGGER trg_epi_entrega_arquivar_documento
  AFTER UPDATE OF signed_at ON public.epi_entregas
  FOR EACH ROW EXECUTE FUNCTION public.epi_entrega_arquivar_documento();

-- ── EPI-051: kit inicial de EPI da admissão em função de risco ──────────────
-- Lista os EPIs exigidos pela função do admitido (epi_tipos.obrigatorio_para_
-- funcoes) que ainda não têm entrega assinada — a pendência do kit inicial que
-- o painel de onboarding acompanha até a última ficha (NR-6 c/c NR-1).
CREATE OR REPLACE FUNCTION public.epi_kit_admissao_pendencias(p_admissao_id uuid)
RETURNS TABLE (epi_tipo_id uuid, epi_nome text, ja_entregue boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tenant uuid;
  v_cargo  text;
  v_cpf    text;
BEGIN
  SELECT a.tenant_id, a.cargo, a.cpf
    INTO v_tenant, v_cargo, v_cpf
    FROM public.admissoes a
   WHERE a.id = p_admissao_id;

  IF v_cargo IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT et.id, et.nome,
           EXISTS (
             SELECT 1 FROM public.epi_entregas ee
              JOIN public.epis e ON e.id = ee.epi_id
             WHERE ee.tenant_id = v_tenant
               AND e.tipo_id = et.id
               AND regexp_replace(COALESCE(ee.colaborador_cpf,''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(v_cpf,''), '[^0-9]', '', 'g')
               AND ee.signed_at IS NOT NULL
           ) AS ja_entregue
      FROM public.epi_tipos et
     WHERE et.tenant_id = v_tenant
       AND et.obrigatorio_para_funcoes IS NOT NULL
       AND v_cargo = ANY (et.obrigatorio_para_funcoes);
END;
$$;

COMMENT ON FUNCTION public.epi_kit_admissao_pendencias(uuid) IS
  'EPI-051: EPIs exigidos pela funcao do admitido (obrigatorio_para_funcoes) e o que falta entregar.';

-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('EPI-011 · vigia validade do CA (epi_ca_vigiar)',        (to_regprocedure('public.epi_ca_vigiar()') IS NOT NULL)),
    ('EPI-021 · FEFO na saída (epi_sugerir_lote_fefo)',       (to_regprocedure('public.epi_sugerir_lote_fefo(uuid,uuid,text,text)') IS NOT NULL)),
    ('EPI-022 · estoque mínimo → reposição',                 (to_regprocedure('public.epi_verificar_estoque_minimo()') IS NOT NULL)),
    ('EPI-030 · CHECK 44 dígitos da chave da NF',            EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_epi_nf_chave_44')),
    ('EPI-030 · índice único da chave da NF (ou duplicata pendente)',
       (EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_epi_nf_chave_acesso')
        OR EXISTS (SELECT 1 FROM public.epi_notas_fiscais WHERE chave_acesso IS NOT NULL
                   GROUP BY tenant_id, chave_acesso HAVING count(*) > 1))),
    ('EPI-040 · trava de item vencido na entrega',           (to_regprocedure('public.epi_entrega_bloqueia_vencido()') IS NOT NULL)),
    ('EPI-042 · lacre de integridade (coluna + função)',
       (EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='epi_entregas' AND column_name='assinatura_hash')
        AND to_regprocedure('public.epi_entrega_sela_integridade()') IS NOT NULL)),
    ('EPI-044 · ficha assinada ao módulo Documentos',        (to_regprocedure('public.epi_entrega_arquivar_documento()') IS NOT NULL)),
    ('EPI-050 · calcula data de troca',                      (to_regprocedure('public.epi_entrega_calcula_troca()') IS NOT NULL)),
    ('EPI-051 · kit inicial na admissão',                    (to_regprocedure('public.epi_kit_admissao_pendencias(uuid)') IS NOT NULL)),
    ('EPI-052 · checklist de devolução no desligamento',     (to_regprocedure('public.epi_checklist_devolucao_desligamento()') IS NOT NULL))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao
FROM alvo ORDER BY item;
