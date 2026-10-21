-- ============================================================================
-- ENTREGA (QA) — documenta o caso CFG-090 (endereco antigo /configuracoes redireciona para /usuarios)
--
-- Cole ESTE arquivo inteiro no SQL Editor (HOMOLOGACAO e, depois, PRODUCAO). Espelha a migration
-- 20261021204925_qa_cfg_rota_usuarios.sql. So INSERE um caso de teste e a ponte do Cypress;
-- nao toca em dado de cliente. Roda em UMA transacao e e idempotente.
-- ============================================================================

-- =========================================================
-- QA — a tela de Usuários mudou de endereço: /configuracoes -> /usuarios
--
-- O menu Sistema > Usuários abria /configuracoes. O endereço passa a ser /usuarios (a rota
-- /usuarios antiga, uma cópia desatualizada da lista, foi removida) e /configuracoes
-- redireciona para lá, preservando a query e o hash, para link salvo continuar valendo.
--
-- Documenta o caso de TELA CFG-090 (nível e2e) e liga ao it() do Cypress pela ponte
-- qa_cobertura_e2e. Idempotente: casa por codigo. Não toca em dado de cliente.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'sistema/configuracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'módulo sistema/configuracoes não encontrado; CFG-090 não criado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CFG-090', 'O endereço antigo /configuracoes redireciona para /usuarios',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Link salvo (favorito, e-mail, atalho) com o endereço antigo precisa continuar abrindo a tela de Usuários.',
   'Usuário administrador autenticado.',
   '[{"ordem":1,"acao":"Abrir o endereço antigo /configuracoes","resultado_esperado":"O navegador vai para /usuarios"},
     {"ordem":2,"acao":"Conferir a tela","resultado_esperado":"Título Usuários e as abas administrativas"}]'::jsonb,
   'O endereço antigo redireciona para /usuarios.',
   'Rota /configuracoes = RedirecionaParaUsuarios em src/App.tsx (preserva query e hash).')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'CFG-090: %', SQLERRM;
END
$doc$;

DO $ponte$
BEGIN
  INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
  VALUES ('CFG-090', 'cypress/e2e/configuracoes.cy.ts', 'o endereço antigo /configuracoes redireciona para /usuarios')
  ON CONFLICT (codigo) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ponte CFG-090: %', SQLERRM;
END
$ponte$;

-- Conferencia. Esperado: caso_ok = true e ponte_ok = true.
SELECT EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'CFG-090') AS caso_ok,
       EXISTS (SELECT 1 FROM public.qa_cobertura_e2e WHERE codigo = 'CFG-090'
                AND teste = 'o endereço antigo /configuracoes redireciona para /usuarios') AS ponte_ok;
-- Para desfazer: DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'CFG-090'; DELETE FROM public.qa_casos_teste WHERE codigo = 'CFG-090';
