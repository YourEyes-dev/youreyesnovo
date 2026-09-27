-- ============================================================================
-- ENTREGA (QA docs): atualiza COLAB-TELA-04 para o novo comportamento.
-- Equivalente à migration 20260927123001_qa_colab_tela_04_cadastro_direto.sql
-- Cole INTEIRO no SQL Editor (homologação e depois produção). Idempotente.
--
-- O botão Novo Cadastro deixou de abrir a caixa "O que deseja cadastrar?" e passa
-- a abrir DIRETO o formulário de novo colaborador. Este script alinha o caso
-- documentado (qa_casos_teste) e a ponte de cobertura e2e (qa_cobertura_e2e).
--
-- Só UPDATE de linhas existentes (metadados de QA). Guarda backup antes, via
-- EXECUTE, para não acionar o auxiliar de RLS do editor.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Backup da linha do caso antes de alterar.
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.backup_qa_colab_tela_04_20260927 AS '
       || 'SELECT * FROM public.qa_casos_teste WHERE codigo = ''COLAB-TELA-04''';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup nao recriado (provavelmente ja existe): %', SQLERRM;
END
$bkp$;

-- 2) Atualiza o caso documentado.
UPDATE public.qa_casos_teste
   SET titulo = 'Novo Cadastro abre direto o formulário de colaborador',
       objetivo = 'Cadastrar é o ato central. O botão Novo Cadastro deve abrir direto o formulário de novo colaborador (a etapa de escolha colaborador/terceiro foi removida).',
       pre_condicoes = 'Rota /colaboradores.',
       passos = '[{"ordem":1,"acao":"Clicar em Novo Cadastro","resultado_esperado":"Abre direto o formulário Novo Colaborador (Preencha os dados para cadastrar um novo colaborador)"},
     {"ordem":2,"acao":"Fechar sem preencher","resultado_esperado":"O formulário fecha sem criar nada"}]'::jsonb,
       resultado_esperado = 'O formulário de novo colaborador abre direto e fecha sem efeito colateral.'
 WHERE codigo = 'COLAB-TELA-04';

-- 3) Atualiza a ponte (liga o caso ao it() pelo título exato, que foi renomeado).
UPDATE public.qa_cobertura_e2e
   SET teste = 'abre direto o formulário de novo colaborador'
 WHERE codigo = 'COLAB-TELA-04';

-- 4) Conferência (único resultado): título_ok=1 e ponte_ok=1.
SELECT
  (SELECT count(*) FROM public.qa_casos_teste
     WHERE codigo = 'COLAB-TELA-04'
       AND titulo = 'Novo Cadastro abre direto o formulário de colaborador') AS titulo_ok,
  (SELECT count(*) FROM public.qa_cobertura_e2e
     WHERE codigo = 'COLAB-TELA-04'
       AND teste = 'abre direto o formulário de novo colaborador') AS ponte_ok;

-- Desfazer (se precisar) com a linha guardada no backup:
--   UPDATE public.qa_casos_teste c
--      SET titulo = b.titulo, objetivo = b.objetivo, pre_condicoes = b.pre_condicoes,
--          passos = b.passos, resultado_esperado = b.resultado_esperado
--     FROM public.backup_qa_colab_tela_04_20260927 b
--    WHERE b.codigo = c.codigo;
--   UPDATE public.qa_cobertura_e2e
--      SET teste = 'abre a escolha de Novo Cadastro (colaborador ou terceiro)'
--    WHERE codigo = 'COLAB-TELA-04';
