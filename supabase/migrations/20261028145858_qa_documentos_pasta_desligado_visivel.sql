-- Documentos: a pasta de um colaborador DESLIGADO deve continuar visível na
-- árvore do módulo Documentos. O módulo é a evidência de todos que passaram pela
-- empresa (guarda legal: FGTS, eSocial, PCMSO por anos) — nunca pode ocultar pasta.
-- Antes, a árvore (useDocumentoPastas) validava a pasta contra a lista de ATIVOS
-- (RPC colaboradores_diretorio, que filtra status='concluido'), derrubando todo
-- desligado. Corrigido no front: o conjunto válido passa a incluir TODAS as
-- admissões da empresa (qualquer status), mantendo o filtro de empresa.
-- Documenta o caso e2e DOCS-TELA-10. Idempotente. Não cria tabela nem função.

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'documentos-governanca/documentos';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo documentos-governanca/documentos ausente; DOCS-TELA-10 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DOCS-TELA-10',
   'Pasta de colaborador desligado continua visível na árvore de Documentos',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Guarda de documentos trabalhistas após o desligamento: FGTS (prescrição 5 anos, STF ARE 709212; guarda prática até 30 anos), PCMSO/ASO 20 anos (NR-7; 40 anos para expostos a cancerígenos), PPP 20 anos. LGPD art. 7º II e art. 16 I: retenção para cumprimento de obrigação legal.',
   'Garantir que o módulo Documentos nunca oculte a pasta de quem foi desligado — o módulo existe como evidência de TODOS que passaram pela empresa.',
   'Empresa com ao menos um colaborador desligado que possui pasta de documentos.',
   '[{"ordem":1,"acao":"Abrir o módulo Documentos","resultado_esperado":"Árvore de pastas carrega"},
     {"ordem":2,"acao":"Localizar a pasta do colaborador desligado","resultado_esperado":"A pasta do desligado aparece na árvore, com suas subpastas (Admissão, Vida Funcional, Saúde Ocupacional, Desligamento)"}]'::jsonb,
   'A pasta do colaborador desligado permanece na árvore (não é ocultada); só pastas de OUTRA empresa continuam barradas.',
   'Correção no front (useDocumentoPastas): conjunto de colaboradores válidos passa a incluir ativos + desligados da empresa. Ainda sem it() automatizado (depende de seed de desligado com pasta no staging).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'DOCS-TELA-10 documentado (e2e).';
END
$doc$;
