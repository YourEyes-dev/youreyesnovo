-- ============================================================================
-- Normaliza empresa_cadastro.tipo_pessoa para os valores canônicos ('pj','pf').
--
-- Contexto: a constraint chk_empresa_tipo_pessoa (fase1, NOT VALID) só aceita
-- 'pj' | 'pf' | NULL. O frontend sempre grava 'pj'/'pf', mas o seed de staging e
-- duas funções de QA gravavam o legado 'juridica'. Como a constraint é NOT VALID,
-- a linha legada existia, porém QUALQUER update dela passava a falhar — inclusive
-- o UPDATE de recontagem de cotas disparado pelo trigger de admissão
-- (trg_admissao_realizado_cotas) ao cadastrar um colaborador. Resultado: erro
-- 23514 (chk_empresa_tipo_pessoa) na tela de Novo Colaborador.
--
-- Aditivo/idempotente: normaliza os valores legados e valida a constraint.
-- ============================================================================

SET lock_timeout = '10s';

UPDATE public.empresa_cadastro
   SET tipo_pessoa = 'pj'
 WHERE lower(btrim(tipo_pessoa)) IN ('juridica', 'jurídica', 'pessoa juridica', 'pessoa jurídica');

UPDATE public.empresa_cadastro
   SET tipo_pessoa = 'pf'
 WHERE lower(btrim(tipo_pessoa)) IN ('fisica', 'física', 'pessoa fisica', 'pessoa física');

-- Com o legado normalizado, valida a constraint. Se restar algum valor
-- inesperado, apenas registra e segue (não aborta a esteira).
DO $valida$
BEGIN
  EXECUTE 'ALTER TABLE public.empresa_cadastro VALIDATE CONSTRAINT chk_empresa_tipo_pessoa';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'chk_empresa_tipo_pessoa nao validada: %', SQLERRM;
END
$valida$;
