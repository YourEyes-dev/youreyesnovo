-- =========================================================
-- UX: o item de menu "Configurações" passa a se chamar "Usuários" (a tela
-- concentra Usuários, Perfis & Acessos, eSocial e Auditoria) e a Logo da
-- empresa saiu de lá: agora é a aba "Logo" da tela Empresa.
--
-- Esta migration só atualiza a DOCUMENTAÇÃO de testes e a ponte Cypress:
--  - CFG-001/002/010..080: texto "Configurações" vira "Usuários"; CFG-001 e
--    CFG-060 deixam de listar a aba Logo;
--  - CFG-040 (Logo) muda para o módulo Empresa, com passos novos;
--  - qa_cobertura_e2e: títulos dos it() renomeados (CFG-001) e CFG-040 passa a
--    apontar para cypress/e2e/empresa.cy.ts.
-- Não toca em dado de cliente. Idempotente. A cópia das linhas antes de alterar
-- fica em tabelas backup_* (criadas por EXECUTE e fechadas para a API).
-- =========================================================

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cfg_casos_20261020') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cfg_casos_20261020 AS '
         || 'SELECT * FROM public.qa_casos_teste WHERE codigo LIKE ''CFG-%''';
    EXECUTE 'ALTER TABLE public.backup_qa_cfg_casos_20261020 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_qa_cfg_casos_20261020 FROM anon, authenticated';
  END IF;
  IF to_regclass('public.backup_qa_cfg_ponte_20261020') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cfg_ponte_20261020 AS '
         || 'SELECT * FROM public.qa_cobertura_e2e WHERE codigo LIKE ''CFG-%''';
    EXECUTE 'ALTER TABLE public.backup_qa_cfg_ponte_20261020 ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.backup_qa_cfg_ponte_20261020 FROM anon, authenticated';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup dos casos CFG: %', SQLERRM;
END
$bk$;

-- 1) O nome do menu muda em todos os casos CFG, exceto na Logo (CFG-040, reescrita abaixo).
DO $nome$
BEGIN
  UPDATE public.qa_casos_teste
     SET titulo            = replace(titulo, 'Configurações', 'Usuários'),
         objetivo          = replace(objetivo, 'Configurações', 'Usuários'),
         passos            = replace(passos::text, 'Configurações', 'Usuários')::jsonb,
         resultado_esperado = replace(resultado_esperado, 'Configurações', 'Usuários'),
         observacoes       = replace(observacoes, 'Configurações', 'Usuários')
   WHERE codigo LIKE 'CFG-%' AND codigo <> 'CFG-040';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'renomear casos CFG: %', SQLERRM;
END
$nome$;

-- 2) CFG-001 e CFG-060: quatro abas (a Logo saiu).
DO $abas$
BEGIN
  UPDATE public.qa_casos_teste SET
    objetivo = 'A tela concentra a administração de pessoas do tenant. Para o admin, precisa montar com as quatro abas.',
    passos = '[{"ordem":1,"acao":"Acessar Usuários pelo menu (Sistema) como admin","resultado_esperado":"Título Usuários e as abas carregam"},
               {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Usuários, Perfis & Acessos, eSocial e Auditoria presentes; não há aba Logo"}]'::jsonb,
    resultado_esperado = 'As quatro abas administrativas montam para o admin.',
    observacoes = 'Âncoras: value usuarios, perfis, esocial, auditoria. A aba Logo mudou para a tela Empresa (CFG-040).'
  WHERE codigo = 'CFG-001';

  UPDATE public.qa_casos_teste SET
    passos = '[{"ordem":1,"acao":"Percorrer as abas Usuários, Perfis, eSocial e Auditoria","resultado_esperado":"Cada aba monta seu conteúdo sem erro"}]'::jsonb
  WHERE codigo = 'CFG-060';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'CFG-001/060: %', SQLERRM;
END
$abas$;

-- 3) CFG-040: a Logo agora é a aba Logo da tela Empresa (módulo Empresa).
DO $logo$
DECLARE v_emp uuid;
BEGIN
  v_emp := (SELECT id FROM public.qa_modulos WHERE path = 'estrutura-organizacional/empresa' LIMIT 1);
  IF v_emp IS NULL THEN
    RAISE NOTICE 'módulo Empresa não encontrado; CFG-040 fica onde está.';
  END IF;
  UPDATE public.qa_casos_teste SET
    modulo_id = COALESCE(v_emp, modulo_id),
    titulo = 'Aba Logo da Empresa permite personalizar a marca da empresa',
    objetivo = 'A logo aparece no sistema e em documentos. Agora é gerida na aba Logo da tela Empresa, sobre a empresa em edição. Em empresa ainda não salva, a aba orienta salvar o cadastro antes do envio.',
    pre_condicoes = 'Admin autenticado; imagem válida (PNG, JPG, WebP ou SVG, até 2 MB).',
    passos = '[{"ordem":1,"acao":"Abrir Empresa e entrar em Nova Empresa, aba Logo","resultado_esperado":"A aba monta e pede para salvar o cadastro antes de enviar a logo"},
               {"ordem":2,"acao":"Abrir uma empresa já salva, aba Logo, e enviar uma imagem","resultado_esperado":"Upload conclui e a logo é atualizada; salvar o formulário depois não desfaz a logo"}]'::jsonb,
    resultado_esperado = 'A logo da empresa é personalizável pela tela Empresa.',
    observacoes = 'Código histórico (nasceu em Configurações). Componente EmpresaLogoTab, aba value logo em src/pages/Empresa.tsx. O Salvar do formulário não regrava logo_url.'
  WHERE codigo = 'CFG-040';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'CFG-040: %', SQLERRM;
END
$logo$;

-- 4) Ponte caso ↔ it(): título exato do it() no Cypress.
DO $ponte$
BEGIN
  UPDATE public.qa_cobertura_e2e
     SET teste = 'carrega Usuários com as abas administrativas'
   WHERE codigo = 'CFG-001';
  UPDATE public.qa_cobertura_e2e
     SET spec  = 'cypress/e2e/empresa.cy.ts',
         teste = 'CFG-040: aba Logo da Empresa monta e orienta salvar o cadastro antes'
   WHERE codigo = 'CFG-040';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ponte CFG: %', SQLERRM;
END
$ponte$;
