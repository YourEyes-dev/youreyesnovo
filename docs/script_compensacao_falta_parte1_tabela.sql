-- ============================================================================
-- ENTREGA — Compensação de falta, PARTE 1 de 2: tabela e colunas
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- RODAR A PARTE 1 ANTES DA PARTE 2 (as funções da parte 2 usam esta tabela).
--
-- Por que em duas partes: o SQL Editor liga um auxiliar de "auto-RLS" quando o
-- script cria tabela, e esse auxiliar corrompe funções que usam SELECT ... INTO
-- no MESMO script. Por isso a tabela vem sozinha aqui (sem funções), e as
-- funções vêm na parte 2 (sem criar tabela). Assim nenhuma das duas quebra.
--
-- SEGURANÇA: só CRIA coisa nova (colunas, tabela, índice, políticas). Não altera
-- nem apaga dado existente — não precisa de backup. Idempotente (rodar 2x não
-- quebra nem duplica).
-- ============================================================================

-- 1) Acordo pode autorizar compensação de falta, e ser individual (por CPF).
ALTER TABLE public.ponto_acordos
  ADD COLUMN IF NOT EXISTS permite_compensacao_falta boolean NOT NULL DEFAULT false;
ALTER TABLE public.ponto_acordos
  ADD COLUMN IF NOT EXISTS colaborador_cpf text;

-- 2) Limite acima do qual a compensação exige homologação do RH (D-17).
ALTER TABLE public.ponto_banco_horas_config
  ADD COLUMN IF NOT EXISTS homologacao_rh_acima_min integer;

-- 3) Tabela de solicitação/estado da compensação de falta.
CREATE TABLE IF NOT EXISTS public.ponto_compensacao_falta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  empresa_id uuid,
  colaborador_cpf text NOT NULL,
  colaborador_id uuid,
  data_falta date NOT NULL,
  minutos integer NOT NULL,
  acordo_id uuid REFERENCES public.ponto_acordos(id) ON DELETE SET NULL,
  regime_id uuid REFERENCES public.ponto_banco_horas_config(id) ON DELETE SET NULL,
  prazo_compensacao_dias integer,
  prazo_ate date,
  status text NOT NULL DEFAULT 'pendente_autorizacao'
    CHECK (status IN ('pendente_autorizacao','pendente_homologacao','autorizada','efetivada','recusada','cancelada')),
  motivo text,
  autorizado_por uuid,
  autorizado_por_nome text,
  autorizado_em timestamptz,
  homologado_por uuid,
  homologado_por_nome text,
  homologado_em timestamptz,
  ciencia_em timestamptz,
  ciencia_por text,
  movimentacao_id uuid,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_compensacao_falta_viva
  ON public.ponto_compensacao_falta (tenant_id, colaborador_cpf, data_falta)
  WHERE status NOT IN ('recusada','cancelada');

ALTER TABLE public.ponto_compensacao_falta ENABLE ROW LEVEL SECURITY;

DO $rls$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE tablename='ponto_compensacao_falta' AND policyname='compfalta tenant select') THEN
    CREATE POLICY "compfalta tenant select" ON public.ponto_compensacao_falta
      FOR SELECT USING (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant insert" ON public.ponto_compensacao_falta
      FOR INSERT WITH CHECK (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant update" ON public.ponto_compensacao_falta
      FOR UPDATE USING (tenant_id = public.get_user_tenant_id());
    CREATE POLICY "compfalta tenant delete" ON public.ponto_compensacao_falta
      FOR DELETE USING (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- Conferência (o editor mostra só o último resultado): tudo no lugar? (espera t)
SELECT
  to_regclass('public.ponto_compensacao_falta') IS NOT NULL AS tabela_ok,
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_name='ponto_acordos' AND column_name='permite_compensacao_falta') AS col_acordo_ok,
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_name='ponto_acordos' AND column_name='colaborador_cpf') AS col_cpf_ok,
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_name='ponto_banco_horas_config' AND column_name='homologacao_rh_acima_min') AS col_limite_ok;
