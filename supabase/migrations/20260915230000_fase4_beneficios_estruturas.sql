-- ============================================================================
-- Fase 4 (motores) — Benefícios: estruturas dos subsistemas (BEN-030/040/042/
-- 070/071). Mesma abordagem da fundação do SST: cria a estrutura de banco que o
-- módulo precisa (tabelas + RLS por tenant), sobre a qual as telas e os motores
-- de cálculo se apoiam. Cada tabela nasce com a política de isolamento.
--
-- BEN-030: dependentes de benefício (plano de saúde familiar, IRRF).
-- BEN-040: manutenção do plano na rescisão (arts. 30/31 da Lei 9.656/98).
-- BEN-042: operadoras e faturas com conciliação.
-- BEN-070: PLR (programa/acordo, limite de 2 pagamentos/ano).
-- BEN-071: consignado e margem consignável.
-- ============================================================================

-- ── BEN-030: dependentes de benefício ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_dependentes (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL,
  colaborador_cpf      text NOT NULL,
  colaborador_nome     text,
  nome                 text NOT NULL,
  data_nascimento      date,
  parentesco           text NOT NULL,          -- conjuge | filho | enteado | ...
  documento            text,
  beneficios_vinculados uuid[],                 -- beneficios_colaboradores.id
  idade_limite_meses   integer,                 -- limite de idade (dependente filho)
  reflete_irrf         boolean NOT NULL DEFAULT true,
  ativo                boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_dependentes IS
  'BEN-030: dependentes por titular (idade/parentesco/documento), refletindo na operadora e no IRRF.';

-- ── BEN-040: manutenção do plano na rescisão (arts. 30/31) ──────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_manutencao_plano (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  admissao_id       uuid,
  colaborador_cpf   text NOT NULL,
  motivo_rescisao   text,
  elegivel          boolean NOT NULL DEFAULT false,
  periodo_meses     integer,                    -- 1/3 do tempo; min 6, máx 24
  vitalicio         boolean NOT NULL DEFAULT false,  -- aposentado 10+ anos
  prazo_opcao_ate   date,                       -- 30 dias para optar
  custo_integral    numeric(14,2),
  opcao_status      text NOT NULL DEFAULT 'pendente',  -- pendente|optou|recusou|expirou
  documento_id      uuid,
  base_legal        text NOT NULL DEFAULT 'Lei 9.656/98, arts. 30 e 31',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_manutencao_plano IS
  'BEN-040: manutencao do plano do demitido/aposentado (elegibilidade, periodo, prazo de 30 dias, custo integral).';

-- ── BEN-042: operadoras e faturas com conciliação ───────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_operadoras (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL,
  nome         text NOT NULL,
  cnpj         text,
  tipo         text,                            -- saude | odonto | vida | ...
  ativo        boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_operadoras IS
  'BEN-042: operadoras/planos (base para movimentacoes e faturas).';

CREATE TABLE IF NOT EXISTS public.beneficios_faturas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  operadora_id      uuid REFERENCES public.beneficios_operadoras(id) ON DELETE SET NULL,
  competencia       text NOT NULL,              -- AAAA-MM
  vidas_cobradas    integer,
  valor_total       numeric(14,2),
  coparticipacao    numeric(14,2),
  conciliada        boolean NOT NULL DEFAULT false,   -- RN-013: paga só após conciliar
  glosa_valor       numeric(14,2) NOT NULL DEFAULT 0,
  plano_acao_id     uuid,
  status            text NOT NULL DEFAULT 'importada',  -- importada|conciliada|paga|glosada
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_faturas IS
  'BEN-042: faturas da operadora — conciliacao obrigatoria (vidas/valores) antes do pagamento.';

-- ── BEN-070: PLR (programa/acordo, limite de 2 pagamentos/ano) ──────────────
CREATE TABLE IF NOT EXISTS public.beneficios_plr (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL,
  empresa_id            uuid,
  titulo                text NOT NULL,
  acordo_documento_id   uuid,                    -- acordo previo valido (condicao da isencao)
  vigencia_inicio       date,
  vigencia_fim          date,
  limite_pagamentos_ano integer NOT NULL DEFAULT 2,   -- Lei 10.101/2000
  ativo                 boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_plr IS
  'BEN-070: programa de PLR — acordo previo como condicao da isencao, limite de 2 pagamentos/ano (Lei 10.101/2000).';

-- ── BEN-071: consignado e margem consignável ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_consignado (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL,
  colaborador_cpf      text NOT NULL,
  convenio             text,
  margem_consignavel   numeric(14,2),            -- teto sobre a remuneracao disponivel
  valor_parcela        numeric(14,2),
  parcelas_total       integer,
  status               text NOT NULL DEFAULT 'ativo',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_consignado IS
  'BEN-071: consignado e margem consignavel (validacao do desconto contra a margem, Lei 10.820/2003).';

-- ── RLS de isolamento por tenant + updated_at em todas ──────────────────────
DO $rls$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'beneficios_dependentes', 'beneficios_manutencao_plano', 'beneficios_operadoras',
    'beneficios_faturas', 'beneficios_plr', 'beneficios_consignado'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation ' || t) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL USING (tenant_id = public.get_user_tenant_id()) WITH CHECK (tenant_id = public.get_user_tenant_id())',
        'Tenant isolation ' || t, t);
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS update_%s_updated_at ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER update_%s_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()', t, t);
  END LOOP;
END;
$rls$;
