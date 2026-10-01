-- ============================================================================
-- ACERTO DO BANCO — SUDOMED · PASSO 0: BACKUP (rodar ANTES de tudo)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- Copia, para tabelas de backup datadas, TUDO que o acerto pode tocar nas 4
-- empresas: banco de horas, movimentações, fechamentos e atribuições de escala.
-- NÃO altera nada do sistema — só CRIA cópias. Idempotente (IF NOT EXISTS).
-- A produção não tem PITR; este é o resgate se algo sair errado.
--
-- Para DESFAZER depois (se precisar), os dados originais estarão nessas tabelas
-- backup_acerto_*_20261001. (Restaurar é um INSERT a partir delas — me chame.)
-- ============================================================================
WITH emp AS (
  SELECT id FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
)
SELECT count(*) AS empresas_no_escopo FROM emp;

-- 1) Banco de horas (linhas por competência)
CREATE TABLE IF NOT EXISTS public.backup_acerto_banco_20261001 AS
SELECT b.* FROM public.ponto_banco_horas b
WHERE b.empresa_id IN (
  SELECT id FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260'));

-- 2) Movimentações do banco (apuradas, manuais, liquidações)
CREATE TABLE IF NOT EXISTS public.backup_acerto_mov_20261001 AS
SELECT mv.* FROM public.ponto_banco_horas_movimentacoes mv
JOIN public.ponto_banco_horas b ON b.id = mv.banco_horas_id
WHERE b.empresa_id IN (
  SELECT id FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260'));

-- 3) Fechamentos (para reabrir/refechar com rastro do estado anterior)
CREATE TABLE IF NOT EXISTS public.backup_acerto_fech_20261001 AS
SELECT f.* FROM public.ponto_fechamentos f
WHERE f.empresa_id IN (
  SELECT id FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260'));

-- 4) Atribuições de escala (segurança extra; não serão alteradas, mas copiamos)
CREATE TABLE IF NOT EXISTS public.backup_acerto_escala_atrib_20261001 AS
SELECT a.* FROM public.ponto_escala_atribuicoes a
WHERE a.tenant_id IN (
  SELECT DISTINCT tenant_id FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260'));

-- CONFERÊNCIA (o editor mostra o último resultado): quantas linhas guardamos.
SELECT
  (SELECT count(*) FROM public.backup_acerto_banco_20261001)        AS backup_banco,
  (SELECT count(*) FROM public.backup_acerto_mov_20261001)          AS backup_movimentacoes,
  (SELECT count(*) FROM public.backup_acerto_fech_20261001)         AS backup_fechamentos,
  (SELECT count(*) FROM public.backup_acerto_escala_atrib_20261001) AS backup_atribuicoes;
