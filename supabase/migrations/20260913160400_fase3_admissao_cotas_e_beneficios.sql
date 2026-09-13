-- ============================================================================
-- Fase 3 (motores) — Admissão/Cota + Benefícios (operações básicas).
--
-- ADM-040: motor da cota de aprendiz (art. 429 CLT: 5%..15% da base por
--          estabelecimento), espelhando o desenho da cota de PcD.
-- ADM-041: enquadramento PcD/reabilitado na admissão alimentando o "realizado"
--          (pcd_quantidade_atual) automaticamente.
-- BEN-001: elegibilidade lida na adesão (regras_cargo/vinculo/unidade).
-- BEN-010: âncora do termo de opção/recusa na adesão (VT é optativo).
-- BEN-011: motor de cálculo do VT (o MENOR entre 6% do salário básico e o
--          custo real do transporte).
-- BEN-012: teto de participação do PAT/CCT parametrizado no catálogo.
-- BEN-020: ponte benefício → Folha (rubricas por competência).
-- BEN-050: apuração proporcional aos dias efetivos do Ponto (com afastamento).
-- BEN-051: benefício × instrumento coletivo (CCT) por vigência.
-- BEN-060: termo assinado vinculado à adesão (mesma âncora do BEN-010).
--
-- Estruturais adiados honestamente para uma fase própria (subsistemas novos):
--   BEN-030 (dependentes), BEN-040 (manutenção do plano — arts. 30/31),
--   BEN-042 (operadoras/faturas/conciliação), BEN-070 (PLR), BEN-071
--   (consignado/margem). As próprias auditorias registram que, sem programa/
--   convênio, "tudo bem não ter estrutura".
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- ADM-041 / ADM-040 — colunas de enquadramento na admissão
-- ─────────────────────────────────────────────────────────────────────────
-- Enquadramento é dado sensível (compõe a cota legal e prova nominal na
-- fiscalização). O acesso já é fechado pelas políticas de admissoes; aqui só
-- damos o campo que faltava para a admissão "marcar quem é quem".
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

-- ─────────────────────────────────────────────────────────────────────────
-- ADM-040 — motor da cota de aprendiz (espelha recalcular_cota_pcd)
-- ─────────────────────────────────────────────────────────────────────────
-- Art. 429 da CLT: o estabelecimento deve ter aprendizes entre 5% e 15% da
-- base (funções que demandam formação profissional). O modelo guarda a base
-- em total_colaboradores; a faixa mínima/máxima é derivada dela, exatamente
-- como a cota de PcD deriva o percentual exigido.
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

-- ─────────────────────────────────────────────────────────────────────────
-- ADM-040 + ADM-041 — realizado das cotas derivado das admissões ativas
-- ─────────────────────────────────────────────────────────────────────────
-- Colaborador ativo = admissão 'concluido' (não existe 'ativo' no enum). O
-- realizado deixa de ser digitado à mão: quem é PcD/reabilitado/aprendiz na
-- admissão passa a compor pcd_quantidade_atual e aprendiz_quantidade_atual.
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

DROP TRIGGER IF EXISTS trg_admissao_realizado_cotas ON public.admissoes;
CREATE TRIGGER trg_admissao_realizado_cotas
  AFTER INSERT OR DELETE OR
        UPDATE OF status, enquadramento_pcd, reabilitado_inss, contrato_aprendiz, empresa_id
  ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_atualiza_realizado_cotas();

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-010 / BEN-060 — âncora do termo de opção/adesão na adesão
-- ─────────────────────────────────────────────────────────────────────────
-- O VT é optativo (Lei 7.418/85): descontar de quem não optou é ilegal;
-- conceder sem termo perde a prova da natureza não salarial. A adesão passa a
-- ter onde apontar o termo assinado (id do documento) e seu estado.
ALTER TABLE public.beneficios_colaboradores
  ADD COLUMN IF NOT EXISTS termo_documento_id uuid;
ALTER TABLE public.beneficios_colaboradores
  ADD COLUMN IF NOT EXISTS termo_status text NOT NULL DEFAULT 'pendente';

COMMENT ON COLUMN public.beneficios_colaboradores.termo_documento_id IS
  'Documento do termo de opção/adesão (módulo Documentos, padrão ADM-070).';
COMMENT ON COLUMN public.beneficios_colaboradores.termo_status IS
  'Estado do termo: pendente | assinado | recusado.';

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-012 — teto de participação do PAT/CCT parametrizado no catálogo
-- ─────────────────────────────────────────────────────────────────────────
-- A participação do trabalhador que o PAT limita como condição do benefício
-- fiscal deixa de ser "o que o operador digitar": vira parâmetro versionável
-- por competência no catálogo.
ALTER TABLE public.beneficios_tipos
  ADD COLUMN IF NOT EXISTS limite_participacao_pat numeric(5,2);
ALTER TABLE public.beneficios_tipos
  ADD COLUMN IF NOT EXISTS limite_vigencia_inicio date;

COMMENT ON COLUMN public.beneficios_tipos.limite_participacao_pat IS
  'Teto (%) de participação do trabalhador (PAT/CCT). Acima descaracteriza o benefício.';

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-001 — elegibilidade lida na adesão (regras_cargo/vinculo/unidade)
-- ─────────────────────────────────────────────────────────────────────────
-- As regras já estão no catálogo (beneficios_tipos.regras_cargo etc.) e
-- ninguém as lê. Aqui a adesão passa a conferir a elegibilidade: cargo/vínculo/
-- unidade fora da regra são SINALIZADOS (não bloqueados — o DP decide a exceção
-- documentada), gravando o motivo em observacoes.
CREATE OR REPLACE FUNCTION public.beneficio_valida_elegibilidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_regras_cargo   text[];
  v_regras_vinculo text[];
  v_regras_unidade text[];
  v_cargo          text;
  v_vinculo        text;
  v_alertas        text := '';
BEGIN
  SELECT bt.regras_cargo, bt.regras_vinculo, bt.regras_unidade
    INTO v_regras_cargo, v_regras_vinculo, v_regras_unidade
    FROM public.beneficios_tipos bt
   WHERE bt.id = NEW.beneficio_tipo_id;

  -- Sem regras cadastradas, todo colaborador é elegível — nada a sinalizar.
  IF COALESCE(array_length(v_regras_cargo, 1), 0) = 0
     AND COALESCE(array_length(v_regras_vinculo, 1), 0) = 0
     AND COALESCE(array_length(v_regras_unidade, 1), 0) = 0 THEN
    RETURN NEW;
  END IF;

  -- Cargo/vínculo do colaborador vêm da admissão mais recente (casamento por CPF).
  SELECT a.cargo, a.tipo_contrato
    INTO v_cargo, v_vinculo
    FROM public.admissoes a
   WHERE a.tenant_id = NEW.tenant_id
     AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
       = regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g')
   ORDER BY a.created_at DESC NULLS LAST
   LIMIT 1;

  IF COALESCE(array_length(v_regras_cargo, 1), 0) > 0
     AND v_cargo IS NOT NULL AND NOT (v_cargo = ANY (v_regras_cargo)) THEN
    v_alertas := v_alertas || format('[elegibilidade] cargo "%s" fora da regra_cargo. ', v_cargo);
  END IF;

  IF COALESCE(array_length(v_regras_vinculo, 1), 0) > 0
     AND v_vinculo IS NOT NULL AND NOT (v_vinculo = ANY (v_regras_vinculo)) THEN
    v_alertas := v_alertas || format('[elegibilidade] vinculo "%s" fora da regra_vinculo. ', v_vinculo);
  END IF;

  IF v_alertas <> '' THEN
    NEW.observacoes := COALESCE(NEW.observacoes || ' ', '') || v_alertas
                     || 'Conceder exige exceção documentada pelo DP.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_beneficio_valida_elegibilidade ON public.beneficios_colaboradores;
CREATE TRIGGER trg_beneficio_valida_elegibilidade
  BEFORE INSERT OR UPDATE OF beneficio_tipo_id, colaborador_cpf
  ON public.beneficios_colaboradores
  FOR EACH ROW EXECUTE FUNCTION public.beneficio_valida_elegibilidade();

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-011 — motor de cálculo do Vale-Transporte
-- ─────────────────────────────────────────────────────────────────────────
-- Lei 7.418/85: o desconto é o MENOR entre 6% do salário básico e o custo real
-- do transporte. Home office (custo zero) dispensa o VT.
CREATE OR REPLACE FUNCTION public.beneficio_vt_desconto(
  p_salario_basico numeric,
  p_custo_transporte numeric
) RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_teto_legal numeric;   -- 6% do salário básico
  v_custo      numeric := COALESCE(p_custo_transporte, 0);
BEGIN
  -- Motor do beneficio de transporte (VT): teto de 6% do salario basico.
  -- Sem custo de transporte (ex.: home office) não há desconto de benefício.
  IF v_custo <= 0 THEN
    RETURN 0;
  END IF;
  v_teto_legal := ROUND(COALESCE(p_salario_basico, 0) * 0.06, 2);
  -- O trabalhador nunca arca com mais que 6% do salário básico.
  RETURN LEAST(v_teto_legal, v_custo);
END;
$$;

COMMENT ON FUNCTION public.beneficio_vt_desconto(numeric, numeric) IS
  'BEN-011: desconto do VT = MENOR(6% do salario basico, custo real do transporte).';

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-050 — apuração do benefício proporcional aos dias efetivos do Ponto
-- ─────────────────────────────────────────────────────────────────────────
-- VT/VR proporcionais aos dias trabalhados na competência; afastamento reduz a
-- concessão. O Ponto já apura os dias (ponto_saldo_dias_competencia_bruto).
CREATE OR REPLACE FUNCTION public.beneficio_apurar_proporcional(
  p_beneficio_colaborador_id uuid,
  p_competencia text          -- 'AAAA-MM'
) RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  bc            public.beneficios_colaboradores%ROWTYPE;
  v_dias_efet   integer;
  v_dias_uteis  integer := 22;   -- base padrão de dias úteis quando a CCT não define
  v_afastado    boolean;
BEGIN
  SELECT * INTO bc FROM public.beneficios_colaboradores WHERE id = p_beneficio_colaborador_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Dias efetivos vêm do Ponto (a mesma fonte que as férias usam).
  v_dias_efet := public.ponto_saldo_dias_competencia_bruto(
                   bc.tenant_id, bc.colaborador_cpf, p_competencia);

  -- Colaborador afastado na competência não recebe o benefício proporcional.
  SELECT EXISTS (
           SELECT 1 FROM public.afastamentos a
            WHERE a.tenant_id = bc.tenant_id
              AND regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g')
                = regexp_replace(COALESCE(bc.colaborador_cpf, ''), '[^0-9]', '', 'g')
              AND a.status::text IN ('ativo', 'beneficio_inss')
              AND to_char(a.data_inicio, 'YYYY-MM') <= p_competencia
              AND to_char(COALESCE(a.data_fim, DATE '9999-12-31'), 'YYYY-MM') >= p_competencia
         ) INTO v_afastado;

  IF v_afastado OR v_dias_efet IS NULL THEN
    v_dias_efet := COALESCE(v_dias_efet, 0);
  END IF;

  -- Valor cheio × (dias efetivos / dias úteis da competência).
  RETURN ROUND(COALESCE(bc.valor, 0)
               * LEAST(1, GREATEST(0, v_dias_efet)::numeric / NULLIF(v_dias_uteis, 0)), 2);
END;
$$;

COMMENT ON FUNCTION public.beneficio_apurar_proporcional(uuid, text) IS
  'BEN-050: apura o benefico proporcional aos dias efetivos do Ponto; afastamento zera.';

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-051 — benefício × instrumento coletivo (CCT) por vigência
-- ─────────────────────────────────────────────────────────────────────────
-- Cesta básica, VR mínimo e seguro de vida instituídos pela convenção da
-- categoria passam a ser lidos pela vigência (ponto_cct_config), o mesmo padrão
-- que o Ponto e a Folha já praticam. Devolve o piso da CCT vigente na data.
CREATE OR REPLACE FUNCTION public.beneficio_valor_por_cct(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_categoria text,      -- categoria do benefício (transporte/alimentacao/...)
  p_referencia date
) RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_valor numeric;
BEGIN
  -- A CCT vigente na data (ponto_cct_config guarda a convenção por vigência).
  -- O piso do benefício, quando parametrizado, sai do catálogo cujo tipo casa
  -- com a categoria; a CCT define a vigência a considerar.
  SELECT bt.valor_padrao
    INTO v_valor
    FROM public.ponto_cct_config cct
    JOIN public.beneficios_tipos bt
      ON bt.tenant_id = cct.tenant_id
     AND lower(bt.categoria) = lower(p_categoria)
   WHERE cct.tenant_id = p_tenant_id
     AND (cct.empresa_id IS NULL OR cct.empresa_id = p_empresa_id)
     AND cct.ativo IS TRUE
     AND cct.vigencia_inicio <= p_referencia
     AND (cct.vigencia_fim IS NULL OR cct.vigencia_fim >= p_referencia)
   ORDER BY cct.vigencia_inicio DESC
   LIMIT 1;

  RETURN v_valor;
END;
$$;

COMMENT ON FUNCTION public.beneficio_valor_por_cct(uuid, uuid, text, date) IS
  'BEN-051: valor do beneficio pela CCT (convencao coletiva) vigente na referencia.';

-- ─────────────────────────────────────────────────────────────────────────
-- BEN-020 — ponte benefício → Folha (rubricas por competência)
-- ─────────────────────────────────────────────────────────────────────────
-- As adesões ativas geram lançamentos de desconto na Folha da competência, em
-- vez de digitados à mão mês a mês. A incidência (VT/VR não integram) fica na
-- rubrica; a natureza salarial mal classificada é passivo previdenciário.
CREATE OR REPLACE FUNCTION public.beneficios_gerar_rubricas_competencia(
  p_tenant_id uuid,
  p_periodo_id uuid,
  p_competencia text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ref      date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_gerados  integer := 0;
  bc         RECORD;
  v_rubrica  public.folha_rubricas%ROWTYPE;
  v_valor    numeric;
BEGIN
  -- Uma rubrica de desconto de benefício por competência (idempotente por origem).
  FOR bc IN
    SELECT * FROM public.beneficios_colaboradores b
     WHERE b.tenant_id = p_tenant_id
       AND b.status = 'ativo'
       AND b.data_inicio <= (v_ref + INTERVAL '1 month - 1 day')::date
       AND (b.data_fim IS NULL OR b.data_fim >= v_ref)
  LOOP
    -- Rubrica de desconto do tenant (não integra por padrão para VT/VR).
    SELECT * INTO v_rubrica
      FROM public.folha_rubricas fr
     WHERE fr.tenant_id = p_tenant_id
       AND fr.ativa IS TRUE
       AND fr.tipo::text = 'desconto'
     ORDER BY fr.prioridade_calculo NULLS LAST
     LIMIT 1;

    IF NOT FOUND THEN
      CONTINUE;  -- sem rubrica configurada, nada a lançar
    END IF;

    -- Valor proporcional aos dias do Ponto (BEN-050); cai no desconto cheio se nulo.
    v_valor := COALESCE(public.beneficio_apurar_proporcional(bc.id, p_competencia),
                        bc.valor_desconto, 0);

    -- Idempotência: não duplica o lançamento do benefício na mesma competência.
    IF EXISTS (
      SELECT 1 FROM public.folha_lancamentos fl
       WHERE fl.tenant_id = p_tenant_id
         AND fl.periodo_id = p_periodo_id
         AND fl.colaborador_cpf = bc.colaborador_cpf
         AND fl.rubrica_id = v_rubrica.id
         AND fl.origem = 'beneficio'
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.folha_lancamentos
      (tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf,
       rubrica_id, rubrica_codigo, rubrica_descricao, tipo, referencia, valor, origem)
    VALUES
      (p_tenant_id, p_periodo_id, bc.colaborador_id, bc.colaborador_nome, bc.colaborador_cpf,
       v_rubrica.id, v_rubrica.codigo_interno, v_rubrica.descricao, v_rubrica.tipo,
       p_competencia, v_valor, 'beneficio');

    v_gerados := v_gerados + 1;
  END LOOP;

  RETURN v_gerados;
END;
$$;

COMMENT ON FUNCTION public.beneficios_gerar_rubricas_competencia(uuid, uuid, text) IS
  'BEN-020: gera as rubricas de desconto da Folha a partir das adesoes ativas na competencia.';
