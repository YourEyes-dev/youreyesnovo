-- ============================================================================
-- ENTREGA (SQL Editor de producao): documenta o caso de QA INICIO-DESL-01.
--
-- Contexto: bug reportado por cliente — a tela inicial (Dashboard) e a Central
-- de Pendencias traziam lembretes de colaboradores JA DESLIGADOS. A correcao e
-- de tela (frontend): o Inicio passou a considerar so colaboradores ativos.
-- Este script SO registra o caso de teste (nivel e2e) em qa_casos_teste, para a
-- tela de QA do SuperAdmin em producao refletir a mudanca de comportamento.
--
-- Seguro para o SQL Editor: roda em UMA transacao, idempotente, NAO cria tabela
-- (nao aciona o auto-RLS), nao usa marca de aspas-dolar em comentario, bloco DO
-- com EXCEPTION por item e uma conferencia SELECT no fim.
-- ============================================================================

DO $qa_desl$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; INICIO-DESL-01 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'sistema/pendencias' LIMIT 1);
  IF v_mod IS NULL THEN
    v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'sistema' LIMIT 1);
  END IF;
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo sistema/pendencias ausente; INICIO-DESL-01 nao documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'INICIO-DESL-01',
   'Inicio e Central de Pendencias nao mostram lembrete de colaborador desligado',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 46 (tratamento adequado a finalidade)',
   'A tela inicial trazia pendencias/alertas de colaboradores JA DESLIGADOS, porque desligar so muda admissoes.status e as linhas dos modulos permanecem. O Inicio agora considera apenas colaboradores ativos (admissao nao desligada/reprovada). O grupo Desligamentos segue listando o desligado de proposito.',
   'Colaborador com uma pendencia e depois DESLIGADO no ambiente.',
   '[{"ordem":1,"acao":"Concluir o desligamento de um colaborador que tem pendencia","resultado_esperado":"admissoes.status vira desligado e data_desligamento e preenchida"},
     {"ordem":2,"acao":"Abrir a tela inicial e a Central de Pendencias","resultado_esperado":"O desligado NAO aparece nos lembretes nem nos contadores"},
     {"ordem":3,"acao":"Conferir o grupo Desligamentos","resultado_esperado":"O desligado aparece ali, pois a pendencia e concluir o processo"}]',
   'Lembretes/indicadores do Inicio consideram so colaboradores ativos; desligado some de tudo exceto do grupo Desligamentos.')
  ON CONFLICT (codigo) DO UPDATE
    SET titulo = EXCLUDED.titulo,
        objetivo = EXCLUDED.objetivo,
        passos = EXCLUDED.passos,
        resultado_esperado = EXCLUDED.resultado_esperado,
        nivel = EXCLUDED.nivel;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao INICIO-DESL-01 nao registrada: %', SQLERRM;
END $qa_desl$;

-- Conferencia (o editor mostra so o ultimo resultado):
SELECT codigo, nivel, status, titulo
  FROM public.qa_casos_teste
 WHERE codigo = 'INICIO-DESL-01';
