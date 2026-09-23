-- ============================================================================
-- ENTREGA — Afastamentos (Fase 4): efeitos, prazos e travas — PARTE 1 de 2
--
-- Espelha a migration 20260915120000_fase4_afastamentos_efeitos_prazos.sql (no
-- teste), ausente em homologacao e producao (passivo 09/2026).
--
-- POR QUE DUAS PARTES: a entrega cria triggers em DUAS tabelas movimentadas
-- (afastamentos_pendencias na Parte 1, afastamentos na Parte 2). A regra da casa
-- proibe criar trigger em duas tabelas movimentadas na MESMA transacao (deadlock
-- ja ocorrido). Rode a Parte 1, confira, depois a Parte 2.
--
-- O QUE ENTREGA A PARTE 1:
--   * tabela afastamento_tipo_config (matriz de efeito por tipo) + indice unico +
--     RLS + politicas + seed dos padroes da casa (globais, tenant_id NULL);
--   * tabela afastamento_hipoteses_art473 (catalogo do art. 473) + RLS + politicas
--     + seed;
--   * coluna empresa_cadastro.empresa_cidada (+ vigencia) — ADD COLUMN aditivo;
--   * 5 funcoes: afastamento_efeito_fgts, afastamento_prazo_recaida_s2230,
--     afastamento_estabilidade_gestante_fim, afastamento_proximo_dia_util,
--     afastamento_pendencia_preenche_prazo;
--   * trigger trg_afastamento_pendencia_prazo em afastamentos_pendencias.
--
-- NOTA DE DRIFT (1 funcao): afastamento_proximo_dia_util JA EXISTE embaixo com
-- corpo DIVERGENTE do teste. Aqui ela e reposta na versao do teste (fonte da
-- verdade) — o novo trigger depende dela. E funcao STABLE somente-leitura
-- (calcula o proximo dia util); a troca e reversivel. As demais estao ausentes.
--
-- SEGURANCA: aditivo. Cria tabelas/funcoes novas e ADICIONA uma coluna
-- (ADD COLUMN IF NOT EXISTS — nao mexe em linha existente). Seeds idempotentes
-- (WHERE NOT EXISTS). Nao ALTERA nem APAGA dado — sem backup. Roda em UMA
-- transacao. DDL pura no topo; blocos com aspas-dolar (funcoes) depois.
-- Dependencia ja presente embaixo: public.get_user_tenant_id(), tabelas
-- afastamentos, afastamentos_pendencias, empresa_cadastro, feriados.
--
-- CONFERENCIA: rode a query do fim SEPARADA. Esperado: 2 | 1 | 5 | 1 | OK
-- ============================================================================

SET lock_timeout = '10s';

-- ═══════════════════════════════════════════════════════════════════════════
-- DDL PURA (tabelas, indice, RLS, politicas, ADD COLUMN, seeds) — sem aspas-dolar
-- ═══════════════════════════════════════════════════════════════════════════

-- AFAST-010: matriz de efeito por tipo de afastamento
CREATE TABLE IF NOT EXISTS public.afastamento_tipo_config (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid,
  tipo                text NOT NULL,
  efeito              text NOT NULL DEFAULT 'suspensao',
  efeito_fgts         text NOT NULL DEFAULT 'suspende',
  conta_tempo_servico boolean NOT NULL DEFAULT false,
  codigo_tabela_18    text,
  vigencia_inicio     date,
  vigencia_fim        date,
  observacao          text,
  ativo               boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT afastamento_tipo_config_efeito_chk
    CHECK (efeito = ANY (ARRAY['interrupcao','suspensao','misto'])),
  CONSTRAINT afastamento_tipo_config_fgts_chk
    CHECK (efeito_fgts = ANY (ARRAY['mantem','suspende']))
);
ALTER TABLE public.afastamento_tipo_config ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.afastamento_tipo_config IS
  'AFAST-010: efeito legal por tipo de afastamento (interrupcao/suspensao, FGTS, Tabela 18 eSocial).';

CREATE UNIQUE INDEX IF NOT EXISTS afastamento_tipo_config_uidx
  ON public.afastamento_tipo_config (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo)
  WHERE ativo;

DROP POLICY IF EXISTS "Leitura afastamento_tipo_config" ON public.afastamento_tipo_config;
CREATE POLICY "Leitura afastamento_tipo_config"
  ON public.afastamento_tipo_config FOR SELECT
  USING (tenant_id IS NULL OR tenant_id = public.get_user_tenant_id());
DROP POLICY IF EXISTS "Escrita afastamento_tipo_config" ON public.afastamento_tipo_config;
CREATE POLICY "Escrita afastamento_tipo_config"
  ON public.afastamento_tipo_config FOR ALL
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

-- AFAST-050: catalogo das hipoteses do art. 473
CREATE TABLE IF NOT EXISTS public.afastamento_hipoteses_art473 (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid,
  inciso      text,
  descricao   text NOT NULL,
  dias        integer,
  unidade     text NOT NULL DEFAULT 'dias',
  frequencia  text,
  base_legal  text NOT NULL DEFAULT 'CLT art. 473',
  ativo       boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.afastamento_hipoteses_art473 ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.afastamento_hipoteses_art473 IS
  'AFAST-050: catalogo das hipoteses de falta justificada do art. 473 (inciso, dias, frequencia).';

DROP POLICY IF EXISTS "Leitura afastamento_hipoteses_art473" ON public.afastamento_hipoteses_art473;
CREATE POLICY "Leitura afastamento_hipoteses_art473"
  ON public.afastamento_hipoteses_art473 FOR SELECT
  USING (tenant_id IS NULL OR tenant_id = public.get_user_tenant_id());
DROP POLICY IF EXISTS "Escrita afastamento_hipoteses_art473" ON public.afastamento_hipoteses_art473;
CREATE POLICY "Escrita afastamento_hipoteses_art473"
  ON public.afastamento_hipoteses_art473 FOR ALL
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

-- AFAST-040: colunas do Empresa Cidada em empresa_cadastro (ADD COLUMN aditivo)
ALTER TABLE public.empresa_cadastro
  ADD COLUMN IF NOT EXISTS empresa_cidada boolean NOT NULL DEFAULT false;
ALTER TABLE public.empresa_cadastro
  ADD COLUMN IF NOT EXISTS empresa_cidada_vigencia_inicio date;
COMMENT ON COLUMN public.empresa_cadastro.empresa_cidada IS
  'AFAST-040: adesao ao Programa Empresa Cidada (licenca 180d/paternidade 20d).';

-- Seed dos padroes da casa (globais, tenant_id NULL). Idempotente.
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

-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCOES (blocos com aspas-dolar) — depois da DDL
-- ═══════════════════════════════════════════════════════════════════════════

-- AFAST-032: efeito do afastamento no FGTS
CREATE OR REPLACE FUNCTION public.afastamento_efeito_fgts(p_tenant uuid, p_tipo text)
RETURNS text LANGUAGE sql STABLE SET search_path TO 'public'
AS $$
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

-- AFAST-021: prazo diferenciado do S-2230 na recaida
CREATE OR REPLACE FUNCTION public.afastamento_prazo_recaida_s2230(p_data_inicio date, p_is_recaida boolean)
RETURNS date LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN COALESCE(p_is_recaida, false) THEN p_data_inicio
    ELSE (date_trunc('month', p_data_inicio + INTERVAL '1 month') + INTERVAL '14 days')::date
  END;
$$;
COMMENT ON FUNCTION public.afastamento_prazo_recaida_s2230(date, boolean) IS
  'AFAST-021: prazo do S-2230; na recaida o evento vai no 1o dia do afastamento.';

-- AFAST-040: fim da estabilidade gestante
CREATE OR REPLACE FUNCTION public.afastamento_estabilidade_gestante_fim(p_data_parto date)
RETURNS date LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $$
  SELECT (p_data_parto + INTERVAL '5 months')::date;
$$;
COMMENT ON FUNCTION public.afastamento_estabilidade_gestante_fim(date) IS
  'AFAST-040: fim da estabilidade gestante = parto + 5 meses (ADCT art. 10).';

-- AFAST-030: proximo dia util (REPOE a versao do teste — corrige drift)
CREATE OR REPLACE FUNCTION public.afastamento_proximo_dia_util(p_tenant uuid, p_data date)
RETURNS date LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $$
DECLARE
  v_dia date := p_data + 1;
  v_i   int := 0;
BEGIN
  WHILE v_i < 30 LOOP
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

-- AFAST-030: preenche o prazo da pendencia de CAT (funcao do trigger)
CREATE OR REPLACE FUNCTION public.afastamento_pendencia_preenche_prazo()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $$
DECLARE
  v_inicio date;
BEGIN
  IF NEW.prazo IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT a.data_inicio INTO v_inicio
    FROM public.afastamentos a WHERE a.id = NEW.afastamento_id;
  IF NEW.tipo_pendencia = 'cat' AND v_inicio IS NOT NULL THEN
    NEW.prazo := public.afastamento_proximo_dia_util(NEW.tenant_id, v_inicio);
  END IF;
  RETURN NEW;
END;
$$;

-- Trigger em afastamentos_pendencias (1a das duas tabelas movimentadas)
DROP TRIGGER IF EXISTS trg_afastamento_pendencia_prazo ON public.afastamentos_pendencias;
CREATE TRIGGER trg_afastamento_pendencia_prazo
  BEFORE INSERT ON public.afastamentos_pendencias
  FOR EACH ROW EXECUTE FUNCTION public.afastamento_pendencia_preenche_prazo();

-- ---------------------------------------------------------------------------
-- CONFERENCIA PARTE 1 — rode SEPARADA. Esperado: 2 | 1 | 5 | 1 | OK
--   tabelas_de_2 | col_empresa_cidada | funcoes_de_5 | trigger_pendencia | erro
-- ---------------------------------------------------------------------------
WITH tabs AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.afastamento_tipo_config'),('public.afastamento_hipoteses_art473')
  ) v(rel) WHERE to_regclass(v.rel) IS NOT NULL
),
col AS MATERIALIZED (
  SELECT count(*) AS n FROM information_schema.columns
  WHERE table_schema='public' AND table_name='empresa_cadastro' AND column_name='empresa_cidada'
),
fns AS MATERIALIZED (
  SELECT count(*) AS n FROM (VALUES
    ('public.afastamento_efeito_fgts(uuid, text)'),
    ('public.afastamento_prazo_recaida_s2230(date, boolean)'),
    ('public.afastamento_estabilidade_gestante_fim(date)'),
    ('public.afastamento_proximo_dia_util(uuid, date)'),
    ('public.afastamento_pendencia_preenche_prazo()')
  ) v(sig) WHERE to_regprocedure(v.sig) IS NOT NULL
),
trg AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_trigger
  WHERE tgname='trg_afastamento_pendencia_prazo'
    AND tgrelid = to_regclass('public.afastamentos_pendencias') AND NOT tgisinternal
)
SELECT
  (SELECT n FROM tabs) AS tabelas_de_2,
  (SELECT n FROM col)  AS col_empresa_cidada,
  (SELECT n FROM fns)  AS funcoes_de_5,
  (SELECT n FROM trg)  AS trigger_pendencia,
  CASE WHEN (SELECT n FROM tabs)=2 AND (SELECT n FROM col)=1
        AND (SELECT n FROM fns)=5 AND (SELECT n FROM trg)=1
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;
