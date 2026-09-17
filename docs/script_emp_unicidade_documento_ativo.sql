-- ============================================================================
-- EMP-020/021/070/071 — unicidade de documento (CNPJ E CPF) entre empresas
-- ATIVAS no mesmo tenant. ENTREGA producao — SO DDL (parte de aplicar).
--
-- IMPORTANTE (deadlock): esta parte e SO o DDL (funcao + gatilho + indices),
-- curta e com lock minimo, para nao cruzar com a atividade concorrente da base.
-- A CONFERENCIA (que roda as rotinas de QA e conta o legado) esta em arquivo
-- separado — docs/conferencia_emp_unicidade.sql — para rodar DEPOIS, em
-- transacao propria. Nao junte os dois: foi a juncao (DDL segurando lock
-- exclusivo + conferencia pesada na mesma transacao) que causou o deadlock.
--
-- O gatilho passa a cobrir CNPJ E CPF (normalizados), no INSERT e no UPDATE
-- (ativar duplicata tambem e barrado), levantando unique_violation. Duplicata
-- INATIVA continua permitida. Barra gravacoes NOVAS sem validar a tabela
-- inteira — seguro mesmo com duplicatas ativas historicas. Os indices unicos
-- parciais entram como reforco so onde a base esta limpa (bloco DO que cai em
-- NOTICE no legado). So cria/atualiza — nao altera dado. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.prevent_duplicate_active_cnpj()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  cnpj_norm text := regexp_replace(coalesce(NEW.cnpj,''), '[^0-9]', '', 'g');
  cpf_norm  text := regexp_replace(coalesce(NEW.cpf,''),  '[^0-9]', '', 'g');
BEGIN
  IF NEW.ativo IS TRUE AND cnpj_norm <> '' THEN
    IF EXISTS (
      SELECT 1 FROM public.empresa_cadastro
      WHERE id <> NEW.id AND tenant_id = NEW.tenant_id AND ativo = true
        AND regexp_replace(coalesce(cnpj,''), '[^0-9]', '', 'g') = cnpj_norm
    ) THEN
      RAISE EXCEPTION 'Ja existe outra empresa ATIVA com o CNPJ % neste tenant. Desative a duplicata antes de ativar esta.', NEW.cnpj
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  IF NEW.ativo IS TRUE AND cpf_norm <> '' THEN
    IF EXISTS (
      SELECT 1 FROM public.empresa_cadastro
      WHERE id <> NEW.id AND tenant_id = NEW.tenant_id AND ativo = true
        AND regexp_replace(coalesce(cpf,''), '[^0-9]', '', 'g') = cpf_norm
    ) THEN
      RAISE EXCEPTION 'Ja existe outra empresa ATIVA com o CPF % neste tenant. Desative a duplicata antes de ativar esta.', NEW.cpf
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_prevent_duplicate_active_cnpj ON public.empresa_cadastro;
CREATE TRIGGER trg_prevent_duplicate_active_cnpj
  BEFORE INSERT OR UPDATE OF cnpj, cpf, ativo, tenant_id ON public.empresa_cadastro
  FOR EACH ROW EXECUTE FUNCTION public.prevent_duplicate_active_cnpj();

-- Reforco: indices unicos parciais (so onde a base esta limpa) ----------------
DO $do$
BEGIN
  IF to_regclass('public.uq_empresa_cnpj_ativa') IS NULL THEN
    CREATE UNIQUE INDEX uq_empresa_cnpj_ativa ON public.empresa_cadastro
      (tenant_id, regexp_replace(cnpj, '[^0-9]', '', 'g')) WHERE (ativo AND cnpj IS NOT NULL);
  END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'uq_empresa_cnpj_ativa nao criado: ha CNPJ ativo duplicado no legado. O gatilho protege as gravacoes novas.';
END $do$;

DO $do$
BEGIN
  IF to_regclass('public.uq_empresa_cpf_ativa') IS NULL THEN
    CREATE UNIQUE INDEX uq_empresa_cpf_ativa ON public.empresa_cadastro
      (tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g')) WHERE (ativo AND cpf IS NOT NULL);
  END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'uq_empresa_cpf_ativa nao criado: ha CPF ativo duplicado no legado. O gatilho protege as gravacoes novas.';
END $do$;

-- Confirmacao leve (so catalogo — nao toca empresa_cadastro) ------------------
SELECT 'gatilho' AS objeto,
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                          WHERE tgname='trg_prevent_duplicate_active_cnpj'
                            AND tgrelid='public.empresa_cadastro'::regclass)
            THEN 'instalado' ELSE 'AUSENTE' END AS estado
UNION ALL
SELECT 'indice CNPJ',
       COALESCE((SELECT 'presente' FROM pg_class WHERE relname='uq_empresa_cnpj_ativa'), 'ausente (legado ou a criar)')
UNION ALL
SELECT 'indice CPF',
       COALESCE((SELECT 'presente' FROM pg_class WHERE relname='uq_empresa_cpf_ativa'), 'ausente (legado ou a criar)')
ORDER BY objeto;
