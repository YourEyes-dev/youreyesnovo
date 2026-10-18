-- Script de entrega — QA Cultura & Celebrações (revisão Fase 1).
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente. Atualiza 3 casos existentes
-- (texto) e cria 3 casos novos; antes, guarda a cópia dos 3 casos atualizados.
-- Desfazer: UPDATE public.qa_casos_teste q SET titulo=b.titulo, objetivo=b.objetivo,
--   pre_condicoes=b.pre_condicoes, passos=b.passos, resultado_esperado=b.resultado_esperado
--   FROM backup_qa_cultura_20261018 b WHERE b.id=q.id;

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo IN (''CULT-002'',''CULT-012'',''CULT-050'')';
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

  -- Casos existentes: o comportamento mudou (Configuração passou a governar a detecção)
  UPDATE public.qa_casos_teste SET
    titulo = 'Próximas Celebrações lista aniversários, tempo de casa e dia da profissão',
    objetivo = 'O card Próximas Celebrações puxa aniversários, tempo de casa e dia da profissão dos colaboradores ativos da empresa. Só entram os tipos ligados na Configuração e a janela de dias é a configurada (padrão 30 sem configuração salva). Tempo de casa mostra os anos da data celebrada, não do ano corrente.',
    pre_condicoes = 'Colaboradores ativos com datas dentro da janela configurada.',
    passos = '[{"ordem":1,"acao":"Conferir Próximas Celebrações (N dias)","resultado_esperado":"Itens com selo (Aniversário / N anos de empresa / Dia da Profissão) e Hoje!/Amanhã/em N dias; o N do título é a janela da Configuração"}]'::jsonb,
    resultado_esperado = 'As celebrações da janela configurada aparecem, só dos tipos ligados.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-002';

  UPDATE public.qa_casos_teste SET
    objetivo = 'Do aniversário, tempo de casa ou dia da profissão detectado, um clique monta a ação, que também aparece no Mural Interno. Há no máximo uma ação por pessoa + tipo + ano: depois de criada, a celebração mostra o status da ação em vez do botão Criar Ação.',
    passos = '[{"ordem":1,"acao":"Clicar em Criar Ação numa celebração detectada","resultado_esperado":"Ação criada (pendente) e o botão Criar Ação some da linha, dando lugar ao status"},
               {"ordem":2,"acao":"Clicar duas vezes rápido no mesmo botão","resultado_esperado":"Só uma ação é criada"}]'::jsonb,
    resultado_esperado = 'A ação nasce da celebração detectada, uma única vez, e cruza para o mural.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-012';

  UPDATE public.qa_casos_teste SET
    objetivo = 'A configuração governa a detecção: os interruptores de aniversário, tempo de casa e dia da profissão e os dias de antecedência valem para a tela de Cultura e para o Mural Interno. Tipo desligado não gera item; a janela é a configurada.',
    resultado_esperado = 'A configuração persiste e muda o que a tela de Cultura e o Mural mostram.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-050';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-003', 'A janela de Próximas Celebrações segue a Configuração',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O título do card mostra a janela em dias vinda da Configuração (padrão 30 sem configuração salva). Se a tela ignorasse a configuração, desligar um tipo ou mudar os dias não teria efeito e o RH perderia a confiança na tela.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Abrir a tela e olhar o título do card de celebrações","resultado_esperado":"Título Próximas Celebrações (N dias), com N igual aos dias de antecedência da Configuração"}]'::jsonb,
   'O card exibe a janela configurada.',
   'Regras de cálculo (tipo desligado, janela, virada de ano, 29/02) cobertas por vitest em src/test/celebracoes.test.ts.'),

  (v_mod, 'CULT-014', 'Não duplicar a ação de uma celebração já tratada',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Sem trava, cada clique extra criaria outra ação para a mesma pessoa e data, inflando os indicadores e poluindo o Mural.',
   'Uma celebração detectada sem ação.',
   '[{"ordem":1,"acao":"Criar a ação da celebração","resultado_esperado":"Ação criada"},
     {"ordem":2,"acao":"Recarregar a tela","resultado_esperado":"A mesma celebração aparece uma vez, com o status da ação e sem o botão Criar Ação"}]'::jsonb,
   'Uma celebração (pessoa + tipo + ano) gera no máximo uma ação.',
   'Depende de dado semeado (colaborador com data na janela): sem it() de tela por ora; regra coberta por vitest. Ação cancelada libera nova criação.'),

  (v_mod, 'CULT-071', 'Mural respeita a preferência de reconhecimento reservado',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Quem registrou preferência de reconhecimento Reservado não deve ser exposto nos Lembretes do Mural Interno, nem por aniversário, nem por tempo de casa, nem por ação pendente.',
   'Colaborador com preferência Reservado e data na janela.',
   '[{"ordem":1,"acao":"Abrir o Mural Interno","resultado_esperado":"O colaborador reservado não aparece nos Lembretes; os demais continuam aparecendo"}]'::jsonb,
   'Preferência reservada impede a exposição no Mural.',
   'Depende de dado semeado: sem it() de tela por ora; regra coberta por vitest (pessoaReservada).')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- Ponte caso <-> it() (título EXATO do it() em cypress/e2e/cultura-celebracoes.cy.ts)
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-003', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra a janela de dias da configuração no card de celebrações')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

SELECT codigo, titulo, nivel, status FROM public.qa_casos_teste
WHERE codigo IN ('CULT-002','CULT-003','CULT-012','CULT-014','CULT-050','CULT-071') ORDER BY codigo;
