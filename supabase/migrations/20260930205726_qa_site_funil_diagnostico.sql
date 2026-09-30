-- =====================================================================
-- QA — Site institucional: funil do diagnóstico no Pixel (SITE-005).
-- Só documenta o caso novo; sem mudança de estrutura. Idempotente.
-- Script de entrega: docs/script_qa_site_funil_diagnostico.sql.
-- =====================================================================
SET lock_timeout = '10s';

INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
   base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
SELECT m.id, 'SITE-005',
  'Funil do diagnóstico: cada etapa vira um evento do Pixel, uma vez por sessão, sem o conteúdo das respostas',
  'feliz', 'alta', 'aprovado', 'e2e',
  'LGPD art. 6º (necessidade): ao Pixel vai só o número da etapa, nunca a resposta',
  'Com 289 visitas e 0 diagnósticos em 1,5 dia (30/09/2026), era impossível saber se o visitante não começa ou desiste no meio. O site público passa a mandar ao Pixel: ViewContent (content_name diagnostico) quando a seção aparece pela 1ª vez; DiagnosticoIniciado na 1ª resposta; DiagnosticoEtapa com etapa e total (11: porte, setor, 8 perguntas, contato enviado); DiagnosticoContato ao chegar ao formulário. Todos com utm_campaign quando houver. Só Pixel (sem CAPI), só no site público em produção.',
  'Produção (youreyes.com.br), deslogado, Events Manager → Eventos de teste aberto. O Pixel não carrega no ambiente de teste.',
  '[{"ordem":1,"acao":"Abrir https://www.youreyes.com.br/?utm_source=teste&utm_campaign=sst#diagnostico e rolar até a seção","resultado_esperado":"1 ViewContent com content_name diagnostico"},
    {"ordem":2,"acao":"Escolher o porte","resultado_esperado":"DiagnosticoIniciado e DiagnosticoEtapa etapa 1 total 11, com utm_campaign sst"},
    {"ordem":3,"acao":"Responder setor e as 8 perguntas","resultado_esperado":"DiagnosticoEtapa 2 a 10 e DiagnosticoContato ao abrir o formulário"},
    {"ordem":4,"acao":"Voltar uma pergunta e responder de novo","resultado_esperado":"Nenhum evento repetido"},
    {"ordem":5,"acao":"Enviar o contato","resultado_esperado":"DiagnosticoEtapa 11 e o Lead (navegador + servidor) como antes"},
    {"ordem":6,"acao":"Conferir os parâmetros dos eventos","resultado_esperado":"Só etapa, total, content_name e utm_campaign — nenhuma resposta, porte ou setor"}]'::jsonb,
  'Funil completo no Pixel, sem duplicar e sem conteúdo de resposta.',
  'Sem it() no Cypress: o Pixel só carrega em produção. Coberto por testes unitários (src/test/funilDiagnostico.test.ts e DiagnosticoPsicossocialFunil.test.tsx) e conferido à mão no Events Manager.'
  FROM public.qa_modulos m
 WHERE m.path = 'site-institucional/diagnostico'
ON CONFLICT (codigo) DO NOTHING;
