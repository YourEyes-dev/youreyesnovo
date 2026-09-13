-- ============================================================================
-- Fase 1 (guardas de integridade) — Batch 2: Empresa, Enquadramento, Feriados,
-- TAC e Certidões.
--
-- Casos: EMP-020/021/070/071, DADO-010, HIER-002, FER-002/003/004,
-- ENQ-010/011/013, TAC-003, CERT-010/011.
--
-- CHECKs sobre tabela com dado real vão NOT VALID (enforçam em linha nova/
-- alterada sem quebrar em dado legado). Índices únicos não aceitam NOT VALID:
-- se a produção tiver duplicata ATIVA preexistente, a criação falha e o script
-- de entrega deverá limpar antes (conferência no fim).
-- ============================================================================

-- ── Agregados min/max(uuid) — o Postgres não os traz de fábrica ─────────────
-- Corrige o bug de rotinas do Motor que agregam colunas uuid (ex.: FER-002 usa
-- min(tabela_id)) e habilita usos latentes. uuid tem operadores de ordenação.
CREATE OR REPLACE FUNCTION public.uuid_smaller(uuid, uuid)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT CASE WHEN $1 < $2 THEN $1 ELSE $2 END $$;
CREATE OR REPLACE FUNCTION public.uuid_larger(uuid, uuid)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT CASE WHEN $1 > $2 THEN $1 ELSE $2 END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_aggregate a JOIN pg_proc p ON p.oid=a.aggfnoid
    JOIN pg_type t ON t.oid = p.proargtypes[0]
    WHERE p.proname='min' AND t.typname='uuid') THEN
    EXECUTE 'CREATE AGGREGATE public.min(uuid) (SFUNC=public.uuid_smaller, STYPE=uuid, COMBINEFUNC=public.uuid_smaller, PARALLEL=SAFE, SORTOP=OPERATOR(pg_catalog.<))';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_aggregate a JOIN pg_proc p ON p.oid=a.aggfnoid
    JOIN pg_type t ON t.oid = p.proargtypes[0]
    WHERE p.proname='max' AND t.typname='uuid') THEN
    EXECUTE 'CREATE AGGREGATE public.max(uuid) (SFUNC=public.uuid_larger, STYPE=uuid, COMBINEFUNC=public.uuid_larger, PARALLEL=SAFE, SORTOP=OPERATOR(pg_catalog.>))';
  END IF;
END $$;

-- ── EMP-020/021/070/071: um documento ATIVO por tenant (CNPJ e CPF) ─────────
-- Espelha uq_admissoes_cpf_ativa: normaliza o documento (só dígitos) e vale só
-- entre registros ativos; duplicata INATIVA é permitida (EMP-071). Pega tanto o
-- INSERT (EMP-020/070) quanto o UPDATE ativo=true (EMP-021/071).
DROP INDEX IF EXISTS public.uq_empresa_cnpj_ativa;
CREATE UNIQUE INDEX uq_empresa_cnpj_ativa ON public.empresa_cadastro
  (tenant_id, regexp_replace(cnpj, '[^0-9]', '', 'g'))
  WHERE ativo AND cnpj IS NOT NULL;
DROP INDEX IF EXISTS public.uq_empresa_cpf_ativa;
CREATE UNIQUE INDEX uq_empresa_cpf_ativa ON public.empresa_cadastro
  (tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g'))
  WHERE ativo AND cpf IS NOT NULL;

-- ── DADO-010: tipo de pessoa só PJ ou PF ────────────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tipo_pessoa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tipo_pessoa
  CHECK (tipo_pessoa IS NULL OR tipo_pessoa IN ('pj', 'pf')) NOT VALID;

-- ── HIER-002: apagar grupo econômico preserva as empresas (SET NULL) ────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS empresa_cadastro_grupo_economico_id_fkey;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT empresa_cadastro_grupo_economico_id_fkey
  FOREIGN KEY (grupo_economico_id) REFERENCES public.grupos_economicos(id) ON DELETE SET NULL;

-- ── ENQ-010: FAP na faixa legal 0,5–2,0 (Lei 10.666/2003) ───────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_fap_faixa;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_fap_faixa
  CHECK (fap_atual IS NULL OR fap_atual BETWEEN 0.5 AND 2.0) NOT VALID;

-- ── ENQ-011: grau de risco ajustado exige justificativa ─────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_grau_ajustado_justificado;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_grau_ajustado_justificado
  CHECK (grau_risco_ajustado IS NULL
         OR grau_risco IS NULL
         OR grau_risco_ajustado = grau_risco
         OR COALESCE(btrim(grau_risco_justificativa), '') <> '') NOT VALID;

-- ── ENQ-013: mandato da CIPA com fim ≥ início ───────────────────────────────
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_cipa_mandato_coerente;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_cipa_mandato_coerente
  CHECK (cipa_data_mandato_fim IS NULL OR cipa_data_mandato_inicio IS NULL
         OR cipa_data_mandato_fim >= cipa_data_mandato_inicio) NOT VALID;

-- ── TAC-003: vigência do TAC coerente (fim ≥ início) em cada item do JSON ───
CREATE OR REPLACE FUNCTION public.tac_vigencia_coerente(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p) = 'array' THEN p ELSE '[]'::jsonb END) e
    WHERE NULLIF(e->>'vigencia_inicio', '') IS NOT NULL
      AND NULLIF(e->>'vigencia_fim', '') IS NOT NULL
      AND to_date(e->>'vigencia_fim', 'YYYY-MM-DD') < to_date(e->>'vigencia_inicio', 'YYYY-MM-DD')
  );
$$;
ALTER TABLE public.empresa_cadastro DROP CONSTRAINT IF EXISTS chk_empresa_tac_vigencia;
ALTER TABLE public.empresa_cadastro ADD CONSTRAINT chk_empresa_tac_vigencia
  CHECK (tac_detalhes IS NULL OR public.tac_vigencia_coerente(tac_detalhes)) NOT VALID;

-- ── FERIADOS ────────────────────────────────────────────────────────────────
-- FER-003 (+ FER-002): uma tabela de feriados por unidade. A troca (FER-002)
-- é DELETE + INSERT, então convive com a unicidade.
ALTER TABLE public.feriado_tabela_empresas DROP CONSTRAINT IF EXISTS uq_feriado_tabela_empresa_por_unidade;
ALTER TABLE public.feriado_tabela_empresas ADD CONSTRAINT uq_feriado_tabela_empresa_por_unidade
  UNIQUE (tenant_id, empresa_id);

-- FER-004: tabela e unidade do mesmo tenant (reusa trg_valida_mesmo_tenant do batch 1).
DROP TRIGGER IF EXISTS trg_feriado_vinculo_tabela_tenant ON public.feriado_tabela_empresas;
CREATE TRIGGER trg_feriado_vinculo_tabela_tenant
  BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('tabela_id', 'feriado_tabelas');
DROP TRIGGER IF EXISTS trg_feriado_vinculo_empresa_tenant ON public.feriado_tabela_empresas;
CREATE TRIGGER trg_feriado_vinculo_empresa_tenant
  BEFORE INSERT OR UPDATE ON public.feriado_tabela_empresas
  FOR EACH ROW EXECUTE FUNCTION public.trg_valida_mesmo_tenant('empresa_id', 'empresa_cadastro');

-- ── CERTIDÕES ───────────────────────────────────────────────────────────────
-- CERT-010: emissão não pode ser posterior à validade.
ALTER TABLE public.hub_certidoes DROP CONSTRAINT IF EXISTS chk_hub_certidoes_datas;
ALTER TABLE public.hub_certidoes ADD CONSTRAINT chk_hub_certidoes_datas
  CHECK (data_emissao IS NULL OR data_validade IS NULL OR data_emissao <= data_validade) NOT VALID;

-- CERT-011: status 'irregular' é decisão explícita e não pode ser sobrescrito
-- pela derivação automática por data de validade.
CREATE OR REPLACE FUNCTION public.atualizar_status_certidao()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  -- Marca manual de irregularidade prevalece sobre a validade.
  IF NEW.status = 'irregular' THEN
    RETURN NEW;
  END IF;
  IF NEW.data_validade < CURRENT_DATE THEN
    NEW.status := 'vencida';
  ELSIF NEW.data_validade <= CURRENT_DATE + INTERVAL '30 days' THEN
    NEW.status := 'a_vencer';
  ELSE
    NEW.status := 'valida';
  END IF;
  RETURN NEW;
END;
$$;

-- ── EMP-020/021: rotinas do Motor testavam a duplicidade via qa_nova_empresa,
-- que desde 20260901240000 REAPROVEITA a empresa de mesmo CNPJ (UPDATE, nao
-- INSERT) — logo nunca criava a duplicata e o teste nao exercia a trava. Os
-- inserts passam a ser diretos (a assercao e identica). A trava em si e o
-- gatilho prevent_duplicate_active_cnpj + o indice uq_empresa_cnpj_ativa acima.
CREATE OR REPLACE FUNCTION public.qa_caso_emp_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar empresa ativa com um CNPJ';
  r.esperado := 'Segunda empresa ativa com o mesmo CNPJ e recusada';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ativa 1', '[QA-EMP] Ativa 1', '11222333000848', true);
  r.passo_ordem := 2; r.passo_acao := 'Tentar segunda empresa ATIVA com o mesmo CNPJ';
  BEGIN
    INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
    VALUES (v_t, '[QA-EMP] Ativa 2', '[QA-EMP] Ativa 2', '11222333000848', true);
    r.situacao := 'falhou'; r.obtido := 'ACEITOU duas empresas ativas com o mesmo CNPJ.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: a trava impede CNPJ ativo duplicado.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_emp_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_inativa uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem := 1; r.passo_acao := 'Criar uma empresa ATIVA e outra INATIVA com o mesmo CNPJ';
  r.esperado := 'Ativar a inativa (UPDATE ativo=true) e recusado';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Ja Ativa', '[QA-EMP] Ja Ativa', '11222333000929', true);
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, '[QA-EMP] Inativa', '[QA-EMP] Inativa', '11222333000929', false)
  RETURNING id INTO v_inativa;
  r.passo_ordem := 2; r.passo_acao := 'Tentar ativar a segunda (mesmo CNPJ ja ativo na primeira)';
  BEGIN
    UPDATE public.empresa_cadastro SET ativo = true WHERE id = v_inativa;
    r.situacao := 'falhou'; r.obtido := 'ATIVOU a duplicata — a trava nao pega o UPDATE.';
  EXCEPTION WHEN unique_violation THEN
    r.situacao := 'passou'; r.obtido := 'Recusado: nao da pra ativar duplicata de CNPJ.';
  END;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
