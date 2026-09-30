-- =====================================================================
-- QA — Site institucional: Pixel da Meta só no site público.
--
-- O Pixel saiu do index.html (carregava no SPA inteiro, inclusive no app
-- logado, que divide o domínio com o site) e passou a ser ligado só pelo
-- site público. Documentação: atualiza a observação do SITE-002 (citava o
-- index.html) e cria o SITE-004 (nada do app logado vai para a Meta).
-- Sem mudança de estrutura. Idempotente.
-- Script de entrega: docs/script_qa_site_pixel_so_site_publico.sql.
-- =====================================================================
SET lock_timeout = '10s';

-- 1) SITE-002: a observação citava o index.html, que não carrega mais o Pixel.
UPDATE public.qa_casos_teste
   SET observacoes = 'O Pixel não carrega mais pelo index.html: só o site público (Site.tsx e /lp) o liga, por iniciarMetaPixel() em src/lib/metaConversions.ts, e só nos hosts de src/lib/siteOrigem.ts (HOSTS_PRODUCAO). Na produção o Pixel continua disparando PageView e Lead — conferir no Events Manager. Ver também SITE-004 (app logado).'
 WHERE codigo = 'SITE-002'
   AND observacoes IS DISTINCT FROM 'O Pixel não carrega mais pelo index.html: só o site público (Site.tsx e /lp) o liga, por iniciarMetaPixel() em src/lib/metaConversions.ts, e só nos hosts de src/lib/siteOrigem.ts (HOSTS_PRODUCAO). Na produção o Pixel continua disparando PageView e Lead — conferir no Events Manager. Ver também SITE-004 (app logado).';

-- 2) SITE-004: nada do app logado vai para a Meta.
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
   base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
SELECT m.id, 'SITE-004',
  'O Pixel da Meta só roda no site público: nada do app logado vai para a Meta',
  'negativo', 'critica', 'aprovado', 'e2e',
  'LGPD art. 6º (finalidade, necessidade) e art. 46 (segurança): telas e textos internos de clientes não podem ir para terceiros',
  'O app logado e o site dividem o domínio (a raiz é o site para visitante e o painel para quem tem sessão). Em 29/09/2026 o Pixel global registrou na Meta um SubscribedButtonClick "Apuração" (tab-ponto-apuracao) de dentro do módulo Ponto. O Pixel deve existir só no site público, sem eventos automáticos (autoConfig desligado) e sem PageView por troca de rota (disablePushState); ao sair do site (login na mesma aba), o Pixel é pausado (consent revoke).',
  'Produção (youreyes.com.br). O Pixel não carrega no ambiente de teste, por isso este caso é conferido em produção pelo Events Manager.',
  '[{"ordem":1,"acao":"Abrir youreyes.com.br deslogado","resultado_esperado":"Um PageView no Events Manager (Eventos de teste), nenhum SubscribedButtonClick"},
    {"ordem":2,"acao":"Clicar em botões do site","resultado_esperado":"Nenhum evento automático (SubscribedButtonClick) na Meta"},
    {"ordem":3,"acao":"Fazer login na mesma aba e navegar pelo painel (ex.: Ponto → Apuração)","resultado_esperado":"Nenhum evento novo na Meta (nem PageView, nem clique)"},
    {"ordem":4,"acao":"Abrir o painel direto numa aba nova, já logado","resultado_esperado":"fbevents.js nem é carregado (window.fbq inexistente)"}]'::jsonb,
  'Pixel só no site público; zero eventos vindos do app logado.',
  'Sem it() no Cypress: o Pixel só carrega em produção, e o Cypress roda só no ambiente de teste. Coberto por testes unitários (src/test/siteCapturaLead.test.ts: autoConfig antes do init, disablePushState, pausa ao sair) e conferido à mão no Events Manager após cada publicação.'
  FROM public.qa_modulos m
 WHERE m.path = 'site-institucional/diagnostico'
ON CONFLICT (codigo) DO NOTHING;
