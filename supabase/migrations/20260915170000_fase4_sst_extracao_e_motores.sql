-- ============================================================================
-- Fase 4 (motores) — SST: extração estruturada (fundação) e motores.
--
-- SST-002 é a FUNDAÇÃO: a camada de dados extraídos (dado + tipo + documento
-- de origem + confiança + revisão humana) entre a IA e os efeitos. Os demais
-- casos consomem essa base.
--
-- SST-002: tabela sst_dados_extraidos + confiança/revisão em sst_documentos.
-- SST-003: PGR → tarefas do Plano de Ação (sst_pgr_gera_acoes).
-- SST-010: OS por função gerada dos riscos (sst_gera_os_por_funcao).
-- SST-030: prazo do S-2220 (dia 15 do mês seguinte ao ASO).
-- SST-031: histórico de exposição a agentes + S-2240.
-- SST-040: dimensionamento da CIPA pelo Quadro I + atas.
-- SST-050: enquadramento do laudo → adicional, com neutralização por EPI.
-- SST-060: estrutura do PPP (perfil profissiográfico).
-- SST-070: conferência de coerência PGR × PCMSO × LTCAT × S-2240.
-- ============================================================================

-- ── SST-002: revisão/confiança no documento + tabela de extração ────────────
ALTER TABLE public.sst_documentos
  ADD COLUMN IF NOT EXISTS analise_ia_confianca numeric(5,2);
ALTER TABLE public.sst_documentos
  ADD COLUMN IF NOT EXISTS analise_ia_revisado_por uuid;
ALTER TABLE public.sst_documentos
  ADD COLUMN IF NOT EXISTS analise_ia_revisado_em timestamptz;

COMMENT ON COLUMN public.sst_documentos.analise_ia_confianca IS
  'SST-002: confianca (0-100) da extracao da IA; baixa confianca exige revisao humana.';

CREATE TABLE IF NOT EXISTS public.sst_dados_extraidos (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL,
  documento_id   uuid NOT NULL REFERENCES public.sst_documentos(id) ON DELETE CASCADE,
  tipo_dado      text NOT NULL,       -- risco | exame | periodicidade | enquadramento | medida | agente
  chave          text,
  valor          jsonb NOT NULL DEFAULT '{}'::jsonb,
  confianca      numeric(5,2),
  revisado       boolean NOT NULL DEFAULT false,
  revisado_por   uuid,
  revisado_em    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sst_dados_extraidos IS
  'SST-002: camada de dados extraidos do documento (risco/exame/enquadramento/medida) entre a IA e os efeitos, com confianca e revisao.';

ALTER TABLE public.sst_dados_extraidos ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation sst_dados_extraidos') THEN
    CREATE POLICY "Tenant isolation sst_dados_extraidos"
      ON public.sst_dados_extraidos FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

DROP TRIGGER IF EXISTS update_sst_dados_extraidos_updated_at ON public.sst_dados_extraidos;
CREATE TRIGGER update_sst_dados_extraidos_updated_at
  BEFORE UPDATE ON public.sst_dados_extraidos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── SST-031: histórico de exposição a agentes nocivos ───────────────────────
CREATE TABLE IF NOT EXISTS public.sst_exposicao_agentes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL,
  empresa_id       uuid,
  colaborador_cpf  text NOT NULL,
  colaborador_nome text,
  agente           text NOT NULL,       -- agente nocivo (quimico/fisico/biologico)
  intensidade      text,
  data_inicio      date NOT NULL,
  data_fim         date,
  epi_atenua       boolean NOT NULL DEFAULT false,
  epi_ca           text,
  ltcat_documento_id uuid REFERENCES public.sst_documentos(id) ON DELETE SET NULL,
  s2240_enviado    boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sst_exposicao_agentes IS
  'SST-031: quem esta exposto a qual agente nocivo desde quando (com EPI que atenua) — base do S-2240 e do PPP.';

ALTER TABLE public.sst_exposicao_agentes ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation sst_exposicao_agentes') THEN
    CREATE POLICY "Tenant isolation sst_exposicao_agentes"
      ON public.sst_exposicao_agentes FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

DROP TRIGGER IF EXISTS update_sst_exposicao_agentes_updated_at ON public.sst_exposicao_agentes;
CREATE TRIGGER update_sst_exposicao_agentes_updated_at
  BEFORE UPDATE ON public.sst_exposicao_agentes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── SST-040: atas da CIPA ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cipa_atas (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL,
  empresa_id   uuid NOT NULL,
  data_reuniao date NOT NULL,
  tipo         text NOT NULL DEFAULT 'ordinaria',   -- ordinaria | extraordinaria
  pauta        text,
  documento_id uuid,                                -- ata arquivada em Documentos
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cipa_atas IS
  'SST-040: atas das reunioes mensais da CIPA (prova de que a comissao funciona, NR-5).';

ALTER TABLE public.cipa_atas ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation cipa_atas') THEN
    CREATE POLICY "Tenant isolation cipa_atas"
      ON public.cipa_atas FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

-- ── SST-060: estrutura do PPP ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sst_ppp (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL,
  empresa_id       uuid,
  colaborador_cpf  text NOT NULL,
  colaborador_nome text,
  emitido_em       date NOT NULL DEFAULT CURRENT_DATE,
  motivo           text NOT NULL DEFAULT 'desligamento',  -- desligamento | sob_demanda
  conteudo         jsonb NOT NULL DEFAULT '{}'::jsonb,     -- histórico de exposição consolidado
  documento_id     uuid,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.sst_ppp IS
  'SST-060: Perfil Profissiografico Previdenciario, montado do historico de exposicao (S-2240).';

ALTER TABLE public.sst_ppp ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation sst_ppp') THEN
    CREATE POLICY "Tenant isolation sst_ppp"
      ON public.sst_ppp FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

-- ── SST-003: PGR → tarefas do Plano de Ação ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.sst_pgr_gera_acoes(p_documento_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tenant uuid;
  v_qtd    integer := 0;
  rec RECORD;
BEGIN
  SELECT tenant_id INTO v_tenant FROM public.sst_documentos WHERE id = p_documento_id;
  IF v_tenant IS NULL THEN RETURN 0; END IF;

  -- Cada medida extraida do PGR (sst_dados_extraidos) vira acao rastreavel em
  -- plano_acoes, vinculada ao risco de origem. Idempotente por origem_id.
  FOR rec IN
    SELECT * FROM public.sst_dados_extraidos d
     WHERE d.documento_id = p_documento_id AND d.tipo_dado = 'medida'
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.plano_acoes pa
       WHERE pa.tenant_id = v_tenant AND pa.origem_modulo = 'sst'
         AND pa.origem_id = rec.id
    ) THEN
      INSERT INTO public.plano_acoes
        (tenant_id, codigo, titulo, descricao, origem_modulo, origem_id, origem_descricao, status)
      VALUES (v_tenant,
              'SST-' || substr(rec.id::text, 1, 8),
              COALESCE(rec.valor->>'titulo', 'Medida do PGR'),
              rec.valor->>'descricao', 'sst', rec.id,
              'Medida do PGR (documento ' || p_documento_id::text || ')', 'pendente');
      v_qtd := v_qtd + 1;
    END IF;
  END LOOP;
  RETURN v_qtd;
END;
$$;

COMMENT ON FUNCTION public.sst_pgr_gera_acoes(uuid) IS
  'SST-003: converte as medidas do PGR (sst_documentos/sst_dados_extraidos) em tarefas do plano_acoes.';

-- ── SST-010: OS por função gerada dos riscos ────────────────────────────────
CREATE OR REPLACE FUNCTION public.sst_gera_os_por_funcao(
  p_documento_id uuid,
  p_colaborador_id uuid,
  p_cargo_nome text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tenant uuid;
  v_os     uuid;
  v_seq    integer;
  v_riscos jsonb;
BEGIN
  SELECT tenant_id INTO v_tenant FROM public.sst_documentos WHERE id = p_documento_id;
  IF v_tenant IS NULL THEN RETURN NULL; END IF;

  -- Consolida os riscos da funcao a partir da extracao do PGR (sst_documentos).
  SELECT jsonb_agg(d.valor) INTO v_riscos
    FROM public.sst_dados_extraidos d
   WHERE d.documento_id = p_documento_id AND d.tipo_dado = 'risco';

  SELECT COALESCE(max(numero_sequencial), 0) + 1 INTO v_seq
    FROM public.ordens_servico WHERE tenant_id = v_tenant AND ano = EXTRACT(YEAR FROM CURRENT_DATE)::int;

  -- Gera a OS da funcao com os riscos do PGR; a ciencia (assinatura) fica
  -- pendente para o colaborador (admitidos e mudanca de funcao).
  INSERT INTO public.ordens_servico
    (tenant_id, colaborador_id, cargo_nome, numero_sequencial, ano,
     pgr_id, conteudo_json, data_emissao, status, versao)
  VALUES (v_tenant, p_colaborador_id, p_cargo_nome, v_seq,
          EXTRACT(YEAR FROM CURRENT_DATE)::int, p_documento_id,
          jsonb_build_object('riscos', COALESCE(v_riscos, '[]'::jsonb)),
          CURRENT_DATE, 'pendente_ciencia', 1)
  RETURNING id INTO v_os;

  RETURN v_os;
END;
$$;

COMMENT ON FUNCTION public.sst_gera_os_por_funcao(uuid, uuid, text) IS
  'SST-010: gera a Ordem de Servico por funcao a partir dos riscos do PGR (sst_documentos), com ciencia pendente.';

-- ── SST-030: prazo do S-2220 ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.esocial_s2220_prazo(p_data_aso date)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- S-2220 (ASO/monitoramento da saude): prazo ate o dia 15 do mes SEGUINTE
  -- ao da emissao do ASO.
  SELECT (date_trunc('month', p_data_aso + INTERVAL '1 month') + INTERVAL '14 days')::date;
$$;

COMMENT ON FUNCTION public.esocial_s2220_prazo(date) IS
  'SST-030: prazo do S-2220 = dia 15 do mes seguinte ao ASO.';

-- ── SST-031: geração do S-2240 a partir da exposição ────────────────────────
CREATE OR REPLACE FUNCTION public.sst_exposicao_gera_s2240(p_exposicao_id uuid)
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE v_inicio date;
BEGIN
  -- O S-2240 (condicoes ambientais/agentes nocivos) é devido na admissao e a
  -- cada alteracao de exposicao; prazo dia 15 do mes seguinte ao inicio.
  SELECT data_inicio INTO v_inicio FROM public.sst_exposicao_agentes WHERE id = p_exposicao_id;
  IF v_inicio IS NULL THEN RETURN NULL; END IF;
  RETURN (date_trunc('month', v_inicio + INTERVAL '1 month') + INTERVAL '14 days')::date;
END;
$$;

COMMENT ON FUNCTION public.sst_exposicao_gera_s2240(uuid) IS
  'SST-031: prazo do S-2240 a partir do inicio da exposicao a agente nocivo.';

-- ── SST-040: dimensionamento da CIPA pelo Quadro I ──────────────────────────
CREATE OR REPLACE FUNCTION public.cipa_dimensionar_quadro_i(
  p_efetivo integer,
  p_grupo   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_titulares integer;
  v_suplentes integer;
BEGIN
  -- Dimensiona a CIPA pelo Quadro I da NR-5 (efetivo x grupo do CNAE decide
  -- titulares/suplentes; abaixo do minimo, designado). Faixas simplificadas —
  -- a matriz completa por grupo é [VAL] (o efetivo e o CNAE o cadastro ja tem).
  IF COALESCE(p_efetivo, 0) < 20 THEN
    RETURN jsonb_build_object('modalidade', 'designado', 'titulares', 0, 'suplentes', 0);
  ELSIF p_efetivo <= 50 THEN
    v_titulares := 1; v_suplentes := 1;
  ELSIF p_efetivo <= 100 THEN
    v_titulares := 2; v_suplentes := 2;
  ELSIF p_efetivo <= 500 THEN
    v_titulares := 3; v_suplentes := 3;
  ELSIF p_efetivo <= 1000 THEN
    v_titulares := 4; v_suplentes := 3;
  ELSE
    v_titulares := 6; v_suplentes := 4;
  END IF;

  RETURN jsonb_build_object('modalidade', 'comissao',
    'titulares', v_titulares, 'suplentes', v_suplentes, 'quadro', 'I');
END;
$$;

COMMENT ON FUNCTION public.cipa_dimensionar_quadro_i(integer, text) IS
  'SST-040: dimensionamento da CIPA pelo Quadro I da NR-5 (efetivo x grupo do CNAE).';

-- ── SST-050: enquadramento do laudo → adicional (com neutralização) ─────────
CREATE OR REPLACE FUNCTION public.sst_enquadramento_adicional(
  p_documento_id uuid,
  p_cargo_nome   text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tenant uuid;
  v_enq    text;
  v_neutralizado boolean := false;
BEGIN
  SELECT tenant_id INTO v_tenant FROM public.sst_documentos WHERE id = p_documento_id;

  -- Enquadramento (insalubridade/periculosidade) sai do laudo extraido, ligado
  -- a funcao que a Folha usa para os 10/20/40% ou 30%. EPI eficaz NEUTRALIZA a
  -- insalubridade (CLT art. 191) — CA vencido religa (ver SST-011).
  SELECT d.valor->>'enquadramento' INTO v_enq
    FROM public.sst_dados_extraidos d
   WHERE d.documento_id = p_documento_id AND d.tipo_dado = 'enquadramento'
   LIMIT 1;

  -- Neutralizacao viva: ha entrega de EPI com CA vigente atenuando o agente?
  SELECT EXISTS (
    SELECT 1 FROM public.sst_exposicao_agentes e
     WHERE e.tenant_id = v_tenant AND e.epi_atenua
       AND (e.data_fim IS NULL OR e.data_fim >= CURRENT_DATE)
  ) INTO v_neutralizado;

  RETURN jsonb_build_object(
    'enquadramento', COALESCE(v_enq, 'nenhum'),
    'cargo', p_cargo_nome,
    'neutralizado_por_epi', v_neutralizado,
    'adicional_devido', (COALESCE(v_enq,'nenhum') <> 'nenhum' AND NOT v_neutralizado)
  );
END;
$$;

COMMENT ON FUNCTION public.sst_enquadramento_adicional(uuid, text) IS
  'SST-050: enquadramento do laudo (insalubridade/periculosidade) -> adicional, com neutralizacao por EPI.';

-- ── SST-060: geração do PPP ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sst_gerar_ppp(
  p_tenant uuid,
  p_colaborador_cpf text,
  p_motivo text DEFAULT 'desligamento'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ppp uuid;
  v_hist jsonb;
BEGIN
  -- Monta o PPP do historico de exposicao (S-2240 / sst_exposicao_agentes).
  SELECT jsonb_agg(jsonb_build_object(
           'agente', e.agente, 'inicio', e.data_inicio, 'fim', e.data_fim,
           'epi_ca', e.epi_ca))
    INTO v_hist
    FROM public.sst_exposicao_agentes e
   WHERE e.tenant_id = p_tenant
     AND regexp_replace(COALESCE(e.colaborador_cpf,''),'[^0-9]','','g')
       = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g');

  INSERT INTO public.sst_ppp (tenant_id, colaborador_cpf, motivo, conteudo)
  VALUES (p_tenant, p_colaborador_cpf, p_motivo, COALESCE(v_hist, '[]'::jsonb))
  RETURNING id INTO v_ppp;

  RETURN v_ppp;
END;
$$;

COMMENT ON FUNCTION public.sst_gerar_ppp(uuid, text, text) IS
  'SST-060: gera o PPP do historico de exposicao, no desligamento e sob demanda.';

-- ── SST-070: conferência de coerência documental ────────────────────────────
CREATE OR REPLACE FUNCTION public.sst_confere_coerencia_documental(
  p_tenant uuid,
  p_empresa uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_riscos_sem_exame int := 0;
  v_agentes_sem_inventario int := 0;
BEGIN
  -- Cruza PGR x PCMSO x LTCAT x S-2240 sobre a base extraida (sst_dados_extraidos):
  -- risco inventariado (PGR) sem exame previsto (PCMSO), agente medido (LTCAT/
  -- exposicao) que o inventario nao conhece. A NR-7 exige o PCMSO baseado no PGR.
  SELECT count(*) INTO v_riscos_sem_exame
    FROM public.sst_dados_extraidos d
   WHERE d.tenant_id = p_tenant AND d.tipo_dado = 'risco'
     AND NOT EXISTS (
       SELECT 1 FROM public.sst_dados_extraidos e
        WHERE e.tenant_id = p_tenant AND e.tipo_dado = 'exame'
          AND e.chave = d.chave);

  SELECT count(*) INTO v_agentes_sem_inventario
    FROM public.sst_exposicao_agentes a
   WHERE a.tenant_id = p_tenant
     AND NOT EXISTS (
       SELECT 1 FROM public.sst_dados_extraidos d
        WHERE d.tenant_id = p_tenant AND d.tipo_dado = 'risco'
          AND d.chave = a.agente);

  RETURN jsonb_build_object(
    'riscos_sem_exame', v_riscos_sem_exame,
    'agentes_sem_inventario', v_agentes_sem_inventario,
    'coerente', (v_riscos_sem_exame = 0 AND v_agentes_sem_inventario = 0)
  );
END;
$$;

COMMENT ON FUNCTION public.sst_confere_coerencia_documental(uuid, uuid) IS
  'SST-070: conferencia de coerencia PGR x PCMSO x LTCAT x S-2240 (risco sem exame, agente sem inventario).';
