-- ============================================================================
-- QA — INICIO-DESL-01 (nivel e2e): o Inicio/Central de Pendencias nao lista
-- lembretes de colaboradores ja desligados.
--
-- Bug reportado por cliente: a tela inicial (Dashboard) trazia pendencias e
-- alertas de colaboradores JA DESLIGADOS. Causa: desligar so muda
-- admissoes.status para 'desligado' (grava data_desligamento); as linhas dos
-- modulos (documentos de admissao, ferias, ajustes de ponto, avaliacoes,
-- afastamentos, alertas de saude) permanecem, e as consultas do Inicio nao
-- filtravam por colaborador ativo.
--
-- Correcao (frontend): src/lib/colaboradorAtivo.ts + src/hooks/useColaboradoresEncerrados.ts
-- + src/hooks/usePendencias.ts + src/hooks/useDashboardKPIs.ts passaram a excluir
-- admissoes desligado/reprovado. Documentos sao filtrados no banco pelo join em
-- admissoes.status; os demais modulos por CPF (fallback por nome sem derrubar
-- homonimo ativo). O grupo "Desligamentos" continua mostrando o desligado de
-- proposito (a pendencia e concluir o processo).
--
-- Conferencia 1 (onde afeta): tela Inicio (src/pages/Dashboard.tsx) e Central de
-- Pendencias (src/pages/Pendencias.tsx) — ambas consomem usePendencias; os KPIs
-- consomem useDashboardKPIs. Nenhuma mudanca de schema; nenhuma funcao SQL nova.
-- A logica pura tem teste de unidade (src/test/colaboradorAtivo.test.ts).
--
-- Este arquivo SO DOCUMENTA o caso de teste (nivel e2e) em qa_casos_teste.
-- Idempotente; nao cria tabela nem funcao. O it() do Cypress fica como proximo
-- passo (depende de semear um desligado com pendencia no ambiente de teste);
-- enquanto isso a guarda de cobertura e2e apenas avisa, sem reprovar a esteira.
-- ============================================================================

SET lock_timeout = '10s';

DO $qa_desl$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; INICIO-DESL-01 nao documentado.';
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
   'A tela inicial trazia pendencias/alertas (documentos de admissao, ferias, ajustes de ponto, avaliacoes, afastamentos/CAT, alertas de saude) de colaboradores JA DESLIGADOS, porque desligar so muda admissoes.status e as linhas dos modulos permanecem. O Inicio agora considera apenas colaboradores ativos (admissao nao desligada/reprovada). O grupo Desligamentos segue listando o desligado de proposito (concluir o processo).',
   'Colaborador com uma pendencia (ex.: documento de admissao pendente ou alerta de saude) e depois DESLIGADO no ambiente de teste.',
   '[{"ordem":1,"acao":"Com um colaborador que tem pendencia, concluir o desligamento dele","resultado_esperado":"admissoes.status vira desligado e data_desligamento e preenchida"},
     {"ordem":2,"acao":"Abrir a tela inicial (Dashboard) e a Central de Pendencias","resultado_esperado":"O nome do desligado NAO aparece nos lembretes (documentos, ferias, ajustes, avaliacoes, afastamentos, alertas de saude); os contadores (KPIs e cartoes) nao o contam"},
     {"ordem":3,"acao":"Conferir o grupo Desligamentos","resultado_esperado":"O desligado APARECE ali, pois a pendencia e concluir o processo de desligamento"}]',
   'Lembretes/indicadores do Inicio consideram so colaboradores ativos; desligado some de tudo exceto do grupo Desligamentos.')
  ON CONFLICT (codigo) DO UPDATE
    SET titulo = EXCLUDED.titulo,
        objetivo = EXCLUDED.objetivo,
        passos = EXCLUDED.passos,
        resultado_esperado = EXCLUDED.resultado_esperado,
        nivel = EXCLUDED.nivel,
        updated_at = now();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao INICIO-DESL-01 nao registrada: %', SQLERRM;
END $qa_desl$;
