-- Script de entrega — QA Cultura & Celebrações (revisão Fase 2).
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente. Atualiza o texto de 3 casos
-- e cria 7 casos novos; antes, guarda a cópia dos 3 casos atualizados.
-- Desfazer: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo, passos=b.passos,
--   resultado_esperado=b.resultado_esperado FROM backup_qa_cultura2_20261018 b WHERE b.id=q.id;

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura2_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura2_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo IN (''CULT-001'',''CULT-040'',''CULT-060'')';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup: %', SQLERRM;
END $bk$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  -- Casos existentes cujo comportamento mudou
  UPDATE public.qa_casos_teste SET
    objetivo = 'É onde a cultura vira plano. A tela se chama Cultura & Celebrações e abre pelo painel Hoje, seguido dos cards de totais, do calendário, das próximas celebrações e dos indicadores. Se não monta, o RH perde o acompanhamento.',
    passos = '[{"ordem":1,"acao":"Acessar Cultura & Celebrações pelo menu","resultado_esperado":"Título Cultura & Celebrações; painel Hoje, cards, calendário e abas carregam"},
               {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Experiência do Colaborador, Preferências, Rituais e Reconhecimento"}]'::jsonb
  WHERE modulo_id = v_mod AND codigo = 'CULT-001';

  UPDATE public.qa_casos_teste SET
    objetivo = 'Rituais são as práticas recorrentes da cultura. Cada ritual ativo mostra a próxima realização (a agendada, ou a última somada à frequência) e o botão Registrar realização grava a última e a próxima datas.',
    resultado_esperado = 'O ritual é criado, mostra a próxima realização e permite registrar que foi feito.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-040';

  UPDATE public.qa_casos_teste SET
    objetivo = 'Cobertura de celebração é o indicador principal (colaboradores celebrados nos últimos 12 meses). Taxa de Realização, no prazo, atrasadas e tempo médio completam o quadro e devem montar sem erro nem divisão por zero.',
    passos = '[{"ordem":1,"acao":"Conferir Indicadores Culturais","resultado_esperado":"Cobertura de celebração, Taxa de Realização, Ações no Prazo, Atrasadas e Tempo Médio montam; sem ações ou sem colaboradores, 0% e 0d sem quebrar"}]'::jsonb
  WHERE modulo_id = v_mod AND codigo = 'CULT-060';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-080', 'Painel Hoje reúne o que celebrar agora',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A pergunta do RH é o que precisa fazer agora. O painel Hoje lista as celebrações de hoje, as ações atrasadas e os rituais vencidos, cada um com ação de um toque.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Abrir a tela","resultado_esperado":"Painel Hoje no topo; sem pendências mostra Nada para celebrar hoje"}]'::jsonb,
   'O painel Hoje monta no topo da tela.', 'Regras de montagem cobertas por vitest em src/test/celebracoes.test.ts.'),

  (v_mod, 'CULT-081', 'Calendário mensal e anual das celebrações',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O RH precisa enxergar o mês e o ano: onde há concentração de datas e onde faltam rituais. O calendário mostra os mesmos itens da lista de próximas celebrações, mais ações, datas configuradas e rituais, com filtro por Pessoas, Datas e Rituais.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Navegar entre meses e filtrar por grupo","resultado_esperado":"Pontos coloridos por tipo; dias sem item não abrem"},
     {"ordem":2,"acao":"Clicar em um dia com itens","resultado_esperado":"Gaveta lateral lista os itens do dia"},
     {"ordem":3,"acao":"Alternar para Ano","resultado_esperado":"12 meses com a contagem de itens; clicar num mês volta à visão Mês"}]'::jsonb,
   'O calendário mostra e alterna entre mês e ano.', NULL),

  (v_mod, 'CULT-082', 'Cobertura de celebração nos indicadores',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Medir só execução não diz se as pessoas foram alcançadas. A cobertura mostra quantos colaboradores tiveram ao menos uma celebração concluída nos últimos 12 meses e quem ficou de fora. Mede se a empresa cuidou, nunca o engajamento da pessoa.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Conferir o card Cobertura de celebração","resultado_esperado":"Percentual e quantos de quantos; sem colaboradores ou sem ações, 0% sem erro"}]'::jsonb,
   'A cobertura monta e lista quem ficou sem celebração.', 'Só enxerga o que foi registrado no sistema.'),

  (v_mod, 'CULT-083', 'Parabenizar em um toque, com desfazer',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'No painel Hoje, Parabenizar cria a ação já concluída (ou conclui a existente) num só gesto. Um aviso de 10 segundos oferece Desfazer, que apaga a ação criada ou devolve a existente ao estado anterior. Celebrar todos faz o mesmo em lote.',
   'Uma celebração de hoje ou uma ação atrasada.',
   '[{"ordem":1,"acao":"Clicar em Parabenizar","resultado_esperado":"Item sai do painel; ação concluída; aviso com Desfazer"},
     {"ordem":2,"acao":"Clicar em Desfazer dentro de 10 segundos","resultado_esperado":"O item volta ao painel"}]'::jsonb,
   'A celebração é registrada em um toque e pode ser desfeita.',
   'Depende de dado semeado: sem it() de tela por ora. A trava de duplicidade (CULT-014) vale também aqui.'),

  (v_mod, 'CULT-084', 'Registrar a realização de um ritual',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Sem registrar a realização, o ritual nunca avança no calendário nem some do Hoje quando vence. O botão grava a última execução (hoje) e a próxima (hoje somado à frequência).',
   'Ritual ativo.',
   '[{"ordem":1,"acao":"Em Rituais, clicar em Registrar realização","resultado_esperado":"Aviso Realização registrada; Próximo mostra a nova data"}]'::jsonb,
   'O ritual avança para a próxima data.', 'Depende de dado semeado: sem it() de tela por ora; datas cobertas por vitest.'),

  (v_mod, 'CULT-085', 'Preferência reservada sinalizada onde se celebra',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Quem pediu reconhecimento reservado precisa ser reconhecido como tal na hora de celebrar. O selo Reservado aparece no painel Hoje, nas próximas celebrações e no detalhe do calendário.',
   'Colaborador com preferência Reservado e data na janela.',
   '[{"ordem":1,"acao":"Localizar o colaborador no Hoje, nas próximas celebrações ou no calendário","resultado_esperado":"Selo Reservado visível ao lado do nome"}]'::jsonb,
   'A preferência aparece no ponto de uso.', 'Depende de dado semeado: sem it() de tela por ora; regra coberta por vitest (pessoaReservada).'),

  (v_mod, 'CULT-086', 'Painel, calendário e cobertura cabem na tela do celular',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Gestor e colaborador usam celular. Os cards novos não podem exigir rolagem horizontal em 375 px de largura, e os filtros da agenda quebram linha.',
   'Tela de 375 px.',
   '[{"ordem":1,"acao":"Abrir a tela em 375 px","resultado_esperado":"Hoje, calendário e cobertura sem rolagem horizontal"}]'::jsonb,
   'O layout não estoura a largura.', NULL)
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- Ponte caso <-> it() (título EXATO do it() em cypress/e2e/cultura-celebracoes.cy.ts)
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-080', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o painel Hoje'),
  ('CULT-081', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o calendário e alterna para a visão anual'),
  ('CULT-082', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra a cobertura de celebração nos indicadores'),
  ('CULT-086', 'cypress/e2e/cultura-celebracoes.cy.ts', 'não estoura a largura no celular')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

SELECT codigo, titulo, nivel, status FROM public.qa_casos_teste
WHERE codigo IN ('CULT-001','CULT-040','CULT-060','CULT-080','CULT-081','CULT-082','CULT-083','CULT-084','CULT-085','CULT-086') ORDER BY codigo;
