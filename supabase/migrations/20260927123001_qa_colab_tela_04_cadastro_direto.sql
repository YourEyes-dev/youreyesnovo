-- ============================================================================
-- QA — Atualiza COLAB-TELA-04 para o novo comportamento do Novo Cadastro.
--
-- Antes: o botão Novo Cadastro abria a caixa "O que deseja cadastrar?" (Colaborador
-- vs Empresa Terceira). Essa etapa foi removida — agora o botão abre DIRETO o
-- formulário de novo colaborador. Este script alinha o caso documentado e a ponte
-- de cobertura e2e ao it() renomeado em cypress/e2e/colaboradores.cy.ts.
--
-- Idempotente: só UPDATE por codigo (não cria caso novo).
-- ============================================================================

SET lock_timeout = '10s';

UPDATE public.qa_casos_teste
   SET titulo = 'Novo Cadastro abre direto o formulário de colaborador',
       objetivo = 'Cadastrar é o ato central. O botão Novo Cadastro deve abrir direto o formulário de novo colaborador (a etapa de escolha colaborador/terceiro foi removida).',
       pre_condicoes = 'Rota /colaboradores.',
       passos = '[{"ordem":1,"acao":"Clicar em Novo Cadastro","resultado_esperado":"Abre direto o formulário Novo Colaborador (Preencha os dados para cadastrar um novo colaborador)"},
     {"ordem":2,"acao":"Fechar sem preencher","resultado_esperado":"O formulário fecha sem criar nada"}]'::jsonb,
       resultado_esperado = 'O formulário de novo colaborador abre direto e fecha sem efeito colateral.'
 WHERE codigo = 'COLAB-TELA-04';

-- A ponte liga o caso ao it() pelo TÍTULO exato; o it() foi renomeado.
UPDATE public.qa_cobertura_e2e
   SET teste = 'abre direto o formulário de novo colaborador'
 WHERE codigo = 'COLAB-TELA-04';
