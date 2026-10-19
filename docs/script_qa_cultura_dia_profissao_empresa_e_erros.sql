-- Script de entrega — QA Cultura & Celebrações: IA do dia da profissão só com a empresa logada
-- e mensagens de erro claras. Cole no SQL Editor do projeto de PRODUÇÃO (e da homologação).
-- Idempotente. SÓ documentação de testes: atualiza o texto de 1 caso; as telas funcionam sem ele.
-- Antes de atualizar, guarda a cópia do caso.
-- Desfazer: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo, passos=b.passos,
--   resultado_esperado=b.resultado_esperado FROM backup_qa_cultura6_20261019 b WHERE b.id=q.id;

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura6_20261019') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura6_20261019 AS SELECT * FROM public.qa_casos_teste WHERE codigo = ''CULT-099''';
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

  UPDATE public.qa_casos_teste SET
    objetivo = 'A IA lê os nomes dos cargos (nunca dados de colaboradores) e sugere o dia comemorativo de cada profissão, com confiança e base. Só entram na análise os cargos da EMPRESA ATIVA: a tela busca os cargos dela e o servidor confere que a empresa pertence ao usuário logado e que cada cargo existe nela, descartando qualquer outro. Nada vale sem aprovação: a pessoa confere nome, dia e mês e aprova ou descarta. Data impossível devolvida pela IA é descartada; cargo sem data garantida vai para Sem dia comemorativo conhecido; cargo descartado não é analisado de novo e deixa de ser celebrado, mesmo que o catálogo padrão casasse. Ao trocar de empresa as sugestões pendentes são limpas. Aprovado, o dia aparece em Próximas Celebrações e no calendário. Quando a IA falha, a tela diz o motivo e o que fazer (chave não configurada, sessão expirada, serviço indisponível neste ambiente, limite de uso, sem conexão) em vez de uma mensagem genérica.',
    passos = '[{"ordem":1,"acao":"Com uma empresa ativa, abrir Dias da Profissão","resultado_esperado":"O resumo mostra o nome da empresa e só os cargos dela; sem empresa ativa, pede para selecionar uma"},
               {"ordem":2,"acao":"Clicar em Analisar cargos com IA","resultado_esperado":"Lista de sugestões com cargo, profissão, confiança, base e data editável, só de cargos da empresa ativa"},
               {"ordem":3,"acao":"Corrigir uma data e aprovar","resultado_esperado":"Entra em Definidos pela empresa como IA aprovada"},
               {"ordem":4,"acao":"Descartar outra sugestão","resultado_esperado":"Entra como sem dia da profissão e não é sugerida de novo"},
               {"ordem":5,"acao":"Trocar de empresa","resultado_esperado":"As sugestões pendentes somem e a lista passa a mostrar os cargos da nova empresa"},
               {"ordem":6,"acao":"Provocar uma falha (ex.: ambiente sem a chave da IA)","resultado_esperado":"A tela mostra o motivo e o que fazer, não só uma mensagem genérica"}]'::jsonb,
    resultado_esperado = 'Só entra no calendário o que uma pessoa aprovou, a análise considera apenas a empresa logada e a falha da IA é explicada.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-099';
END $doc$;

SELECT codigo, nivel, left(objetivo, 90) AS objetivo FROM public.qa_casos_teste WHERE codigo = 'CULT-099';
