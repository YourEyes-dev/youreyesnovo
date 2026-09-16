-- ============================================================================
-- Fase 4 (motores) — Afastamentos: efeitos legais, prazos e travas.
--
-- AFAST-010: tabela de efeito por tipo (interrupção × suspensão, FGTS, código
--            da Tabela 18 do eSocial), com vigência — a matriz que faltava.
-- AFAST-021: prazo diferenciado do S-2230 na recaída (evento no 1º dia).
-- AFAST-030: prazo da pendência de CAT preenchido (1º dia útil seguinte).
-- AFAST-032: efeito do afastamento no FGTS (acidente/serviço militar mantêm).
-- AFAST-040: adesão ao Empresa Cidadã + estabilidade gestante (parto + 5 meses).
-- AFAST-050: catálogo das hipóteses do art. 473 (inciso, dias, frequência).
-- AFAST-070: encerramento retido enquanto houver ASO de retorno pendente (NR-7),
--            com exceção justificada em trilha.
--
-- Observação honesta: a matriz exata de efeitos por tipo e os códigos da
-- Tabela 18 são [VAL] jurídico por cliente (CLAUDE/seção 30). Aqui vão os
-- efeitos consolidados e inequívocos (acidente = interrupção + FGTS mantido;
-- doença comum/licença sem remuneração = suspensão), como padrão da casa a
-- refinar por convenção — a estrutura é o que o Motor cobra.
-- ============================================================================

-- ── AFAST-010: matriz de efeito por tipo de afastamento ─────────────────────
CREATE TABLE IF NOT EXISTS public.afastamento_tipo_config (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid,                    -- NULL = padrão da casa (global)
  tipo             text NOT NULL,           -- afastamento_tipo_principal
  efeito           text NOT NULL DEFAULT 'suspensao',  -- interrupcao | suspensao | misto
  efeito_fgts      text NOT NULL DEFAULT 'suspende',   -- mantem | suspende
  conta_tempo_servico boolean NOT NULL DEFAULT false,
  codigo_tabela_18 text,                    -- código do motivo no eSocial (S-2230)
  vigencia_inicio  date,
  vigencia_fim     date,
  observacao       text,
  ativo            boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT afastamento_tipo_config_efeito_chk
    CHECK (efeito = ANY (ARRAY['interrupcao','suspensao','misto'])),
  CONSTRAINT afastamento_tipo_config_fgts_chk
    CHECK (efeito_fgts = ANY (ARRAY['mantem','suspende']))
);

COMMENT ON TABLE public.afastamento_tipo_config IS
  'AFAST-010: efeito legal por tipo de afastamento (interrupcao/suspensao, FGTS, Tabela 18 eSocial).';

CREATE UNIQUE INDEX IF NOT EXISTS afastamento_tipo_config_uidx
  ON public.afastamento_tipo_config (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo)
  WHERE ativo;

ALTER TABLE public.afastamento_tipo_config ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Leitura afastamento_tipo_config') THEN
    CREATE POLICY "Leitura afastamento_tipo_config"
      ON public.afastamento_tipo_config FOR SELECT
      USING (tenant_id IS NULL OR tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Escrita afastamento_tipo_config') THEN
    CREATE POLICY "Escrita afastamento_tipo_config"
      ON public.afastamento_tipo_config FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

-- Seed dos padrões da casa (globais, tenant_id NULL). Idempotente.
INSERT INTO public.afastamento_tipo_config (tipo, efeito, efeito_fgts, conta_tempo_servico, observacao)
SELECT v.tipo, v.efeito, v.fgts, v.conta, 'Padrao da casa (refinar por CCT/cliente).'
FROM (VALUES
  ('acidente_tipico',        'interrupcao','mantem', true),
  ('acidente_trajeto',       'interrupcao','mantem', true),
  ('doenca_ocupacional',     'interrupcao','mantem', true),
  ('beneficio_b91',          'interrupcao','mantem', true),
  ('reabilitacao_b92',       'interrupcao','mantem', true),
  ('licenca_maternidade',    'interrupcao','mantem', true),
  ('licenca_paternidade',    'interrupcao','mantem', true),
  ('licenca_adocao',         'interrupcao','mantem', true),
  ('aborto_nao_criminoso',   'interrupcao','mantem', true),
  ('atestado_odontologico',  'interrupcao','mantem', true),
  ('falta_justificada_legal','interrupcao','mantem', true),
  ('determinacao_judicial_legal','interrupcao','mantem', true),
  ('doenca_comum',           'misto',      'suspende', false),
  ('beneficio_b31',          'suspensao',  'suspende', false),
  ('auxilio_acidente_b94',   'suspensao',  'suspende', false),
  ('licenca_nao_remunerada', 'suspensao',  'suspende', false),
  ('suspensao_disciplinar',  'suspensao',  'suspende', false),
  ('mandato_sindical',       'suspensao',  'suspende', false),
  ('outro_cct_act_politica_interna','suspensao','suspende', false)
) AS v(tipo, efeito, fgts, conta)
WHERE NOT EXISTS (
  SELECT 1 FROM public.afastamento_tipo_config c
   WHERE c.tenant_id IS NULL AND c.tipo = v.tipo
);

-- ── AFAST-050: catálogo das hipóteses do art. 473 da CLT ────────────────────
CREATE TABLE IF NOT EXISTS public.afastamento_hipoteses_art473 (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid,                       -- NULL = padrão da casa
  inciso        text,
  descricao     text NOT NULL,
  dias          integer,
  unidade       text NOT NULL DEFAULT 'dias',
  frequencia    text,                       -- ex.: '1 por ano' (doação de sangue)
  base_legal    text NOT NULL DEFAULT 'CLT art. 473',
  ativo         boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.afastamento_hipoteses_art473 IS
  'AFAST-050: catalogo das hipoteses de falta justificada do art. 473 (inciso, dias, frequencia).';

ALTER TABLE public.afastamento_hipoteses_art473 ENABLE ROW LEVEL SECURITY;
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Leitura afastamento_hipoteses_art473') THEN
    CREATE POLICY "Leitura afastamento_hipoteses_art473"
      ON public.afastamento_hipoteses_art473 FOR SELECT
      USING (tenant_id IS NULL OR tenant_id = public.get_user_tenant_id());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Escrita afastamento_hipoteses_art473') THEN
    CREATE POLICY "Escrita afastamento_hipoteses_art473"
      ON public.afastamento_hipoteses_art473 FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END;
$pol$;

INSERT INTO public.afastamento_hipoteses_art473 (inciso, descricao, dias, unidade, frequencia)
SELECT v.inciso, v.descricao, v.dias, v.unidade, v.freq
FROM (VALUES
  ('I',    'Falecimento de conjuge, ascendente, descendente, irmao ou dependente', 2, 'dias', 'por ocorrencia'),
  ('II',   'Casamento', 3, 'dias', 'por ocorrencia'),
  ('III',  'Nascimento de filho (licenca-paternidade base)', 5, 'dias', 'por ocorrencia'),
  ('IV',   'Doacao voluntaria de sangue', 1, 'dias', '1 por ano'),
  ('V',    'Alistamento eleitoral', 2, 'dias', 'por ocorrencia'),
  ('VI',   'Servico militar obrigatorio', NULL, 'necessario', 'conforme convocacao'),
  ('VII',  'Prova de vestibular/ensino superior', NULL, 'necessario', 'dias de prova'),
  ('VIII', 'Comparecimento em juizo', NULL, 'necessario', 'tempo necessario'),
  ('IX',   'Representacao sindical em reuniao oficial', NULL, 'necessario', 'tempo necessario'),
  ('X',    'Acompanhar consultas/exames de conjuge/companheira gestante', 2, 'dias', 'por ano'),
  ('XI',   'Acompanhar filho de ate 6 anos em consulta medica', 1, 'dias', 'por ano')
) AS v(inciso, descricao, dias, unidade, freq)
WHERE NOT EXISTS (
  SELECT 1 FROM public.afastamento_hipoteses_art473 h
   WHERE h.tenant_id IS NULL AND h.inciso = v.inciso
);

-- ── AFAST-032: efeito do afastamento no FGTS ────────────────────────────────
CREATE OR REPLACE FUNCTION public.afastamento_efeito_fgts(
  p_tenant uuid,
  p_tipo   text
) RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  -- Lê a matriz do AFAST-010: acidente/serviço militar mantêm o depósito de
  -- FGTS durante o afastamento; doença comum (após o 15º) e licença sem
  -- remuneração suspendem. Preferência ao override do tenant sobre o padrão.
  SELECT c.efeito_fgts
    FROM public.afastamento_tipo_config c
   WHERE c.tipo = p_tipo
     AND (c.tenant_id = p_tenant OR c.tenant_id IS NULL)
     AND c.ativo
   ORDER BY c.tenant_id NULLS LAST
   LIMIT 1;
$$;

COMMENT ON FUNCTION public.afastamento_efeito_fgts(uuid, text) IS
  'AFAST-032: efeito do afastamento no FGTS (mantem/suspende) por tipo, da matriz AFAST-010.';

-- ── AFAST-021: prazo diferenciado do S-2230 na recaída ──────────────────────
CREATE OR REPLACE FUNCTION public.afastamento_prazo_recaida_s2230(
  p_data_inicio date,
  p_is_recaida  boolean
) RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- Na recaida (mesmo CID em ate 60 dias) o S-2230 é devido já no 1º DIA do
  -- novo afastamento — não no 16º nem no dia 15 do mês seguinte. Fora da
  -- recaida, o prazo padrão do afastamento >15 dias vale (dia 15 do mês seguinte).
  SELECT CASE
    WHEN COALESCE(p_is_recaida, false) THEN p_data_inicio
    ELSE (date_trunc('month', p_data_inicio + INTERVAL '1 month') + INTERVAL '14 days')::date
  END;
$$;

COMMENT ON FUNCTION public.afastamento_prazo_recaida_s2230(date, boolean) IS
  'AFAST-021: prazo do S-2230; na recaida o evento vai no 1o dia do afastamento.';

-- ── AFAST-040: Empresa Cidadã + estabilidade gestante ───────────────────────
ALTER TABLE public.empresa_cadastro
  ADD COLUMN IF NOT EXISTS empresa_cidada boolean NOT NULL DEFAULT false;
ALTER TABLE public.empresa_cadastro
  ADD COLUMN IF NOT EXISTS empresa_cidada_vigencia_inicio date;

COMMENT ON COLUMN public.empresa_cadastro.empresa_cidada IS
  'AFAST-040: adesao ao Programa Empresa Cidada (licenca 180d/paternidade 20d).';

CREATE OR REPLACE FUNCTION public.afastamento_estabilidade_gestante_fim(p_data_parto date)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- Estabilidade da gestante (ADCT art. 10, II, b): da confirmacao da gravidez
  -- ate 5 meses APOS o parto. O vencimento é parto + 5 meses (regra propria,
  -- diferente do "fim + 12 meses" do acidente).
  SELECT (p_data_parto + INTERVAL '5 months')::date;
$$;

COMMENT ON FUNCTION public.afastamento_estabilidade_gestante_fim(date) IS
  'AFAST-040: fim da estabilidade gestante = parto + 5 meses (ADCT art. 10).';

-- ── AFAST-030: prazo da pendência de CAT (1º dia útil seguinte) ─────────────
CREATE OR REPLACE FUNCTION public.afastamento_proximo_dia_util(
  p_tenant uuid,
  p_data   date
) RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_dia date := p_data + 1;   -- "1º dia útil SEGUINTE"
  v_i   int := 0;
BEGIN
  WHILE v_i < 30 LOOP
    -- Pula fim de semana (6=sábado, 0=domingo) e feriados cadastrados.
    IF EXTRACT(DOW FROM v_dia) NOT IN (0, 6)
       AND NOT EXISTS (
         SELECT 1 FROM public.feriados f
          WHERE f.ativo
            AND (f.tenant_id = p_tenant OR f.tenant_id IS NULL)
            AND f.data = v_dia
       ) THEN
      RETURN v_dia;
    END IF;
    v_dia := v_dia + 1;
    v_i := v_i + 1;
  END LOOP;
  RETURN v_dia;
END;
$$;

CREATE OR REPLACE FUNCTION public.afastamento_pendencia_preenche_prazo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_inicio date;
BEGIN
  -- Só age quando a inteligência criou a pendência sem prazo.
  IF NEW.prazo IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT a.data_inicio INTO v_inicio
    FROM public.afastamentos a WHERE a.id = NEW.afastamento_id;

  IF NEW.tipo_pendencia = 'cat' AND v_inicio IS NOT NULL THEN
    -- Art. 22 da Lei 8.213: CAT ate o 1º dia util seguinte ao acidente.
    NEW.prazo := public.afastamento_proximo_dia_util(NEW.tenant_id, v_inicio);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_afastamento_pendencia_prazo ON public.afastamentos_pendencias;
CREATE TRIGGER trg_afastamento_pendencia_prazo
  BEFORE INSERT ON public.afastamentos_pendencias
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_pendencia_preenche_prazo();

-- ── AFAST-070: encerramento retido enquanto ASO de retorno pendente ─────────
ALTER TABLE public.afastamentos
  ADD COLUMN IF NOT EXISTS encerramento_justificativa text;

COMMENT ON COLUMN public.afastamentos.encerramento_justificativa IS
  'AFAST-070: justificativa (alta administrativa) para encerrar com ASO de retorno pendente.';

CREATE OR REPLACE FUNCTION public.afastamento_bloqueia_encerramento_sem_aso()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status::text = 'encerrado'
     AND COALESCE(OLD.status::text, '') <> 'encerrado'
     AND COALESCE(NEW.encerramento_justificativa, '') = ''
     AND EXISTS (
       SELECT 1 FROM public.afastamentos_pendencias p
        WHERE p.afastamento_id = NEW.id
          AND p.tipo_pendencia = 'aso_retorno'
          AND COALESCE(p.status, 'pendente') NOT IN ('resolvido', 'cancelado')
     ) THEN
    RAISE EXCEPTION
      'Retorno de afastamento com ASO de retorno pendente nao pode ser encerrado (NR-7). Registre o exame ou uma justificativa (alta administrativa).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_afastamento_bloqueia_encerramento_sem_aso ON public.afastamentos;
CREATE TRIGGER trg_afastamento_bloqueia_encerramento_sem_aso
  BEFORE UPDATE OF status ON public.afastamentos
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_bloqueia_encerramento_sem_aso();
