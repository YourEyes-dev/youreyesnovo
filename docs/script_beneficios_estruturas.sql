-- ============================================================================
-- ENTREGA — Beneficios (Fase 4): estruturas dos subsistemas BEN-030/040/042/
-- 070/071 que existem no ambiente de desenvolvimento/teste mas nunca desceram
-- para homologacao e producao (passivo medido em 09/2026 pelo inventario dos
-- tres bancos).
--
-- Espelha exatamente a migration 20260915230000_fase4_beneficios_estruturas.sql
-- (fonte da verdade, ja aplicada no teste): NADA a mais, NADA a menos.
--
-- BEN-030  beneficios_dependentes       dependentes por titular (saude/IRRF).
-- BEN-040  beneficios_manutencao_plano  manutencao do plano na rescisao.
-- BEN-042  beneficios_operadoras        operadoras/planos.
-- BEN-042  beneficios_faturas           faturas com conciliacao (FK -> operadoras).
-- BEN-070  beneficios_plr               programa de PLR.
-- BEN-071  beneficios_consignado        consignado e margem consignavel.
--
-- Cada tabela nasce com RLS de isolamento por tenant e trigger de updated_at,
-- iguais as demais tabelas da casa. Depende de duas funcoes que ja existem nos
-- tres bancos (conferido no inventario): public.get_user_tenant_id() e
-- public.update_updated_at_column().
--
-- SEGURANCA: script de CRIACAO pura. So cria estrutura nova (CREATE ... IF NOT
-- EXISTS); nao ALTERA nem APAGA nenhuma linha existente, entao nao ha backup a
-- fazer. Idempotente: rodar duas vezes nao quebra nem duplica. Roda inteiro em
-- UMA transacao no SQL Editor. Ausencia de RESTRICTIVE de perfil aqui e
-- proposital: o teste tambem nao tem — igualar isso e um passo separado, no
-- teste primeiro.
-- ============================================================================

-- ── BEN-030: dependentes de beneficio ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_dependentes (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL,
  colaborador_cpf       text NOT NULL,
  colaborador_nome      text,
  nome                  text NOT NULL,
  data_nascimento       date,
  parentesco            text NOT NULL,
  documento             text,
  beneficios_vinculados uuid[],
  idade_limite_meses    integer,
  reflete_irrf          boolean NOT NULL DEFAULT true,
  ativo                 boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_dependentes IS
  'BEN-030: dependentes por titular (idade/parentesco/documento), refletindo na operadora e no IRRF.';

-- ── BEN-040: manutencao do plano na rescisao (arts. 30/31) ──────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_manutencao_plano (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  admissao_id       uuid,
  colaborador_cpf   text NOT NULL,
  motivo_rescisao   text,
  elegivel          boolean NOT NULL DEFAULT false,
  periodo_meses     integer,
  vitalicio         boolean NOT NULL DEFAULT false,
  prazo_opcao_ate   date,
  custo_integral    numeric(14,2),
  opcao_status      text NOT NULL DEFAULT 'pendente',
  documento_id      uuid,
  base_legal        text NOT NULL DEFAULT 'Lei 9.656/98, arts. 30 e 31',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_manutencao_plano IS
  'BEN-040: manutencao do plano do demitido/aposentado (elegibilidade, periodo, prazo de 30 dias, custo integral).';

-- ── BEN-042: operadoras (criada ANTES das faturas por causa da FK) ──────────
CREATE TABLE IF NOT EXISTS public.beneficios_operadoras (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL,
  nome         text NOT NULL,
  cnpj         text,
  tipo         text,
  ativo        boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_operadoras IS
  'BEN-042: operadoras/planos (base para movimentacoes e faturas).';

-- ── BEN-042: faturas com conciliacao ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_faturas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL,
  operadora_id      uuid REFERENCES public.beneficios_operadoras(id) ON DELETE SET NULL,
  competencia       text NOT NULL,
  vidas_cobradas    integer,
  valor_total       numeric(14,2),
  coparticipacao    numeric(14,2),
  conciliada        boolean NOT NULL DEFAULT false,
  glosa_valor       numeric(14,2) NOT NULL DEFAULT 0,
  plano_acao_id     uuid,
  status            text NOT NULL DEFAULT 'importada',
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
  acordo_documento_id   uuid,
  vigencia_inicio       date,
  vigencia_fim          date,
  limite_pagamentos_ano integer NOT NULL DEFAULT 2,
  ativo                 boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_plr IS
  'BEN-070: programa de PLR — acordo previo como condicao da isencao, limite de 2 pagamentos/ano (Lei 10.101/2000).';

-- ── BEN-071: consignado e margem consignavel ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.beneficios_consignado (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL,
  colaborador_cpf      text NOT NULL,
  convenio             text,
  margem_consignavel   numeric(14,2),
  valor_parcela        numeric(14,2),
  parcelas_total       integer,
  status               text NOT NULL DEFAULT 'ativo',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.beneficios_consignado IS
  'BEN-071: consignado e margem consignavel (validacao do desconto contra a margem, Lei 10.820/2003).';

-- ── RLS de isolamento por tenant + trigger de updated_at (por item, resiliente) ─
-- Bloco DO com tratamento por tabela: se um item falhar, os outros seguem e o
-- erro vira aviso (a conferencia no fim revela o que ficou de fora).
DO $rls$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'beneficios_dependentes', 'beneficios_manutencao_plano', 'beneficios_operadoras',
    'beneficios_faturas', 'beneficios_plr', 'beneficios_consignado'
  ] LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'Tenant isolation ' || t) THEN
        EXECUTE format(
          'CREATE POLICY %I ON public.%I FOR ALL USING (tenant_id = public.get_user_tenant_id()) WITH CHECK (tenant_id = public.get_user_tenant_id())',
          'Tenant isolation ' || t, t);
      END IF;
      EXECUTE format('DROP TRIGGER IF EXISTS update_%s_updated_at ON public.%I', t, t);
      EXECUTE format('CREATE TRIGGER update_%s_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()', t, t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'RLS/trigger nao aplicado em %: %', t, SQLERRM;
    END;
  END LOOP;
END;
$rls$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: 6 | 6 | 6 | t | OK  (as 6 tabelas, 6 policies de tenant, 6 triggers
-- de updated_at e a FK de faturas presentes).
-- ---------------------------------------------------------------------------
WITH alvo AS MATERIALIZED (
  SELECT unnest(ARRAY[
    'beneficios_dependentes', 'beneficios_manutencao_plano', 'beneficios_operadoras',
    'beneficios_faturas', 'beneficios_plr', 'beneficios_consignado'
  ]) AS tabela
),
tab AS MATERIALIZED (
  SELECT count(*) AS n FROM alvo a
  WHERE to_regclass('public.' || a.tabela) IS NOT NULL
),
pol AS MATERIALIZED (
  SELECT count(*) AS n FROM alvo a
  JOIN pg_policies p ON p.schemaname='public' AND p.tablename=a.tabela
   AND p.policyname = 'Tenant isolation ' || a.tabela
),
trg AS MATERIALIZED (
  SELECT count(*) AS n FROM alvo a
  JOIN pg_trigger g ON g.tgrelid = to_regclass('public.' || a.tabela)
   AND g.tgname = 'update_' || a.tabela || '_updated_at'
   AND NOT g.tgisinternal
),
fk AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'beneficios_faturas_operadora_id_fkey'
      AND conrelid = to_regclass('public.beneficios_faturas')
  ) AS ok
)
SELECT
  (SELECT n FROM tab)  AS tabelas_de_6,
  (SELECT n FROM pol)  AS policies_tenant_de_6,
  (SELECT n FROM trg)  AS triggers_updated_at_de_6,
  (SELECT ok FROM fk)  AS fk_faturas_operadora,
  CASE
    WHEN (SELECT n FROM tab)=6 AND (SELECT n FROM pol)=6
     AND (SELECT n FROM trg)=6 AND (SELECT ok FROM fk)
    THEN 'OK' ELSE 'CONFERIR'
  END AS erro_tecnico;
