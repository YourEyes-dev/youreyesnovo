-- ============================================================================
-- EMP-020/021/070/071 — unicidade de documento (CNPJ E CPF) entre empresas
-- ATIVAS no mesmo tenant. ENTREGA producao.
--
-- O gatilho prevent_duplicate_active_cnpj so olhava a coluna cnpj: empresa PF
-- (documento em cpf) passava sem verificacao (EMP-070/071). Agora cobre CNPJ E
-- CPF, no INSERT e no UPDATE (ativar duplicata tambem e barrado), levantando
-- unique_violation. Duplicata INATIVA continua permitida.
--
-- Seguranca do legado: o gatilho barra gravacoes NOVAS sem validar a tabela
-- inteira (seguro mesmo com duplicatas ativas historicas). Os indices unicos
-- parciais entram como reforco so quando a base esta limpa (bloco DO que cai em
-- NOTICE se houver duplicata no legado). So cria/atualiza 1 funcao, 1 gatilho e
-- (quando possivel) 2 indices — nao altera nem apaga dado. Idempotente. Uma
-- transacao. A conferencia final mostra tambem quantas duplicatas ativas ja
-- existem (leitura), para decidir a limpeza a parte se houver.
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

-- Conferencia (leve) + diagnostico do legado (read-only) ---------------------
SELECT 'EMP-020' AS caso, (public.qa_executar_descartavel('qa_caso_emp_020')).situacao::text AS situacao
UNION ALL SELECT 'EMP-021', (public.qa_executar_descartavel('qa_caso_emp_021')).situacao::text
UNION ALL SELECT 'EMP-070', (public.qa_executar_descartavel('qa_caso_emp_070')).situacao::text
UNION ALL SELECT 'EMP-071', (public.qa_executar_descartavel('qa_caso_emp_071')).situacao::text
UNION ALL
SELECT 'LEGADO: grupos de CNPJ ativo duplicado', count(*)::text FROM (
  SELECT tenant_id, regexp_replace(cnpj,'[^0-9]','','g') AS d
  FROM public.empresa_cadastro WHERE ativo AND cnpj IS NOT NULL
    AND regexp_replace(cnpj,'[^0-9]','','g') <> ''
  GROUP BY 1,2 HAVING count(*) > 1) g
UNION ALL
SELECT 'LEGADO: grupos de CPF ativo duplicado', count(*)::text FROM (
  SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS d
  FROM public.empresa_cadastro WHERE ativo AND cpf IS NOT NULL
    AND regexp_replace(cpf,'[^0-9]','','g') <> ''
  GROUP BY 1,2 HAVING count(*) > 1) g
ORDER BY caso;
