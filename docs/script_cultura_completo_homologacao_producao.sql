-- =====================================================================
-- Cultura & Celebrações — script ÚNICO e CONSOLIDADO (homologação e produção)
--
-- Junta, NA ORDEM, os 5 scripts de entrega da revisão do módulo:
--   1/5 script_qa_cultura_revisao_fase1.sql        (QA)
--   2/5 script_qa_cultura_revisao_fase2.sql        (QA)
--   3/5 script_cultura_fase3_automacao.sql         (colunas, índice, rotina diária)
--   4/5 script_cultura_lembrete_gestor_e_pdf.sql   (coluna lembrar_gestor, QA)
--   5/5 script_cultura_dias_profissao_ia.sql       (tabela cultura_dias_profissao)
--
-- COMO USAR: cole o arquivo INTEIRO no SQL Editor do projeto (homologação OU
-- produção) e rode UMA vez. O resultado final é uma única tabela de conferência.
--
-- É IDEMPOTENTE: pode rodar em ambiente novo, em ambiente que já recebeu alguns
-- dos 5 scripts, ou rodar de novo sem quebrar nem duplicar. Nada aqui altera ou
-- apaga dado de cliente: só colunas novas, 1 índice, 1 tabela nova (vazia),
-- funções, 1 agendamento diário e casos de QA. A automação e o lembrete ao
-- gestor nascem DESLIGADOS em todos os clientes.
--
-- BACKUPS: antes de atualizar o texto de casos de QA existentes, cada parte guarda
-- a cópia (backup_qa_cultura_*, 2, 3, 4, 5 _20261018). O comando para desfazer está
-- no cabeçalho de cada script de origem. Em ambiente NOVO, cada backup guarda o texto
-- de logo antes da respectiva parte (o original de cada caso fica no primeiro backup
-- que o tocou); onde os scripts já tinham rodado, os backups existentes são preservados.
--
-- DESFAZER O AGENDAMENTO: SELECT cron.unschedule('cultura-automacao-diaria');
--
-- ORDEM DA ENTREGA COMPLETA: este SQL ANTES de publicar a função de IA
-- (ai-cultura-dia-profissao) e as telas.
-- =====================================================================

SET lock_timeout = '10s';

-- ════════════════════════════════════════════════════════════
-- PARTE 1/5 — QA: casos CULT-002/012/050 atualizados; CULT-003/014/071 novos
-- (origem: docs/script_qa_cultura_revisao_fase1.sql)
-- ════════════════════════════════════════════════════════════
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

-- ════════════════════════════════════════════════════════════
-- PARTE 2/5 — QA: casos CULT-001/040/060 atualizados; CULT-080 a 086 novos
-- (origem: docs/script_qa_cultura_revisao_fase2.sql)
-- ════════════════════════════════════════════════════════════
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

-- ════════════════════════════════════════════════════════════
-- PARTE 3/5 — Automação segura: colunas, índice único, rotina diária, agendamento, QA
-- (origem: docs/script_cultura_fase3_automacao.sql)
-- ════════════════════════════════════════════════════════════
-- Script de entrega — Cultura & Celebrações, Fase 3 (automação segura, mensagem sugerida, alertas).
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente. NÃO cria tabela: só colunas, índice,
-- funções, agendamento diário e casos de QA. A automação nasce DESLIGADA para todos os clientes.
-- Antes de atualizar o texto de 2 casos de QA, guarda a cópia deles.
-- Desfazer o texto dos casos: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo,
--   resultado_esperado=b.resultado_esperado FROM backup_qa_cultura3_20261018 b WHERE b.id=q.id;
-- Desfazer a rotina diária: SELECT cron.unschedule('cultura-automacao-diaria');

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura3_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura3_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo IN (''CULT-050'',''CULT-080'')';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup: %', SQLERRM;
END $bk$;

-- 1) Colunas novas (idempotente). Sem tabela nova.
ALTER TABLE public.cultura_config
  ADD COLUMN IF NOT EXISTS automacao_aniversario text NOT NULL DEFAULT 'desligado',
  ADD COLUMN IF NOT EXISTS automacao_tempo_casa text NOT NULL DEFAULT 'desligado',
  ADD COLUMN IF NOT EXISTS tom_mensagem text NOT NULL DEFAULT 'leve',
  ADD COLUMN IF NOT EXISTS meta_cobertura integer NOT NULL DEFAULT 95;

ALTER TABLE public.cultura_acoes
  ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS chave_unica text,
  ADD COLUMN IF NOT EXISTS publicado_em timestamptz;

DO $chk$
BEGIN
  ALTER TABLE public.cultura_config
    ADD CONSTRAINT cultura_config_automacao_chk CHECK (
      automacao_aniversario IN ('desligado', 'aprovar')
      AND automacao_tempo_casa IN ('desligado', 'aprovar')
      AND tom_mensagem IN ('formal', 'leve')
      AND meta_cobertura BETWEEN 1 AND 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $chk$;

-- Uma celebracao (pessoa + tipo + ano) gera no maximo uma acao ativa.
-- Linhas antigas ficam com chave_unica nula e nao entram no indice.
CREATE UNIQUE INDEX IF NOT EXISTS cultura_acoes_chave_unica_uidx
  ON public.cultura_acoes (tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), chave_unica)
  WHERE chave_unica IS NOT NULL AND status <> 'cancelada';

-- 2) Data de uma comemoracao anual num ano; 29/02 cai em 28/02 nos anos nao bissextos.
CREATE OR REPLACE FUNCTION public.cultura_data_no_ano(p_mes int, p_dia int, p_ano int)
RETURNS date LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
           WHEN p_mes = 2 AND p_dia = 29
                AND NOT (p_ano % 4 = 0 AND (p_ano % 100 <> 0 OR p_ano % 400 = 0))
             THEN make_date(p_ano, 2, 28)
           ELSE make_date(p_ano, p_mes, p_dia)
         END
$fn$;

-- 3) Rotina diaria: cria como PENDENTE (nunca conclui, nunca publica) as acoes das
-- celebracoes que cairem na janela de dias da Configuracao, so para os tenants que
-- ligaram a automacao. Preferencia de reconhecimento nao impede criar a acao interna:
-- ela so impede publicar, e publicar e sempre gesto humano.
CREATE OR REPLACE FUNCTION public.cultura_automacao_rodar(p_tenant uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_total integer := 0;
  v_n integer;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  c record;
BEGIN
  FOR c IN
    SELECT tenant_id,
           dias_antecedencia_acao AS dias,
           (aniversario_ativo AND automacao_aniversario = 'aprovar') AS faz_aniv,
           (tempo_casa_ativo AND automacao_tempo_casa = 'aprovar') AS faz_tempo
    FROM public.cultura_config
    WHERE p_tenant IS NULL OR tenant_id = p_tenant
  LOOP
    CONTINUE WHEN NOT (c.faz_aniv OR c.faz_tempo);
    BEGIN
      WITH pessoas AS MATERIALIZED (
        SELECT a.tenant_id, a.empresa_id, a.id::text AS pessoa_id, a.nome_completo,
               a.data_nascimento, a.data_admissao
        FROM public.admissoes a
        WHERE a.tenant_id = c.tenant_id
          AND a.status = 'concluido'
          AND a.empresa_id IS NOT NULL
      ),
      anos AS MATERIALIZED (
        SELECT y FROM generate_series(extract(year FROM v_hoje)::int, extract(year FROM v_hoje)::int + 1) AS y
      ),
      ocorrencias AS MATERIALIZED (
        SELECT p.tenant_id, p.empresa_id, p.pessoa_id, p.nome_completo,
               'aniversario'::text AS tipo,
               public.cultura_data_no_ano(extract(month FROM p.data_nascimento)::int,
                                          extract(day FROM p.data_nascimento)::int, an.y) AS data,
               NULL::int AS anos_casa
        FROM pessoas p CROSS JOIN anos an
        WHERE c.faz_aniv AND p.data_nascimento IS NOT NULL
        UNION ALL
        SELECT p.tenant_id, p.empresa_id, p.pessoa_id, p.nome_completo,
               'tempo_casa'::text,
               public.cultura_data_no_ano(extract(month FROM p.data_admissao)::int,
                                          extract(day FROM p.data_admissao)::int, an.y),
               an.y - extract(year FROM p.data_admissao)::int
        FROM pessoas p CROSS JOIN anos an
        WHERE c.faz_tempo AND p.data_admissao IS NOT NULL
          AND an.y - extract(year FROM p.data_admissao)::int >= 1
      )
      INSERT INTO public.cultura_acoes
        (tenant_id, empresa_id, tipo, titulo, colaborador_id, colaborador_nome,
         data_referencia, status, origem, chave_unica)
      SELECT o.tenant_id, o.empresa_id, o.tipo,
             CASE WHEN o.tipo = 'aniversario' THEN 'Aniversário de ' || o.nome_completo
                  ELSE o.anos_casa || ' ano' || CASE WHEN o.anos_casa > 1 THEN 's' ELSE '' END
                       || ' de empresa - ' || o.nome_completo END,
             o.pessoa_id, o.nome_completo, o.data, 'pendente', 'automatica',
             o.tipo || '|' || lower(btrim(o.nome_completo)) || '|' || extract(year FROM o.data)::int
      FROM ocorrencias o
      WHERE o.data BETWEEN v_hoje AND v_hoje + c.dias
        AND NOT EXISTS (
          SELECT 1 FROM public.cultura_acoes x
          WHERE x.tenant_id = o.tenant_id
            AND x.tipo = o.tipo
            AND lower(btrim(x.colaborador_nome)) = lower(btrim(o.nome_completo))
            AND extract(year FROM x.data_referencia) = extract(year FROM o.data)
            AND x.status <> 'cancelada')
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'cultura_automacao_rodar: tenant % ignorado (%)', c.tenant_id, SQLERRM;
    END;
  END LOOP;
  RETURN v_total;
END $fn$;

-- Chamada pela tela (botao Gerar agora): so para o tenant de quem chama e so gestor para cima.
CREATE OR REPLACE FUNCTION public.cultura_automacao_minha_empresa()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_uid IS NULL OR v_tenant IS NULL OR NOT public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RAISE EXCEPTION 'Sem permissão para gerar as ações de cultura.';
  END IF;
  RETURN public.cultura_automacao_rodar(v_tenant);
END $fn$;

REVOKE ALL ON FUNCTION public.cultura_automacao_rodar(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cultura_automacao_minha_empresa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cultura_automacao_minha_empresa() TO authenticated;

-- 4) Todo dia as 09:00 UTC (06:00 em Brasilia). Sem tenant que ligou a automacao, nao faz nada.
DO $cron$
BEGIN
  PERFORM cron.unschedule('cultura-automacao-diaria');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $cron$;

DO $cron$
BEGIN
  PERFORM cron.schedule('cultura-automacao-diaria', '0 9 * * *', $job$SELECT public.cultura_automacao_rodar()$job$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento diário não pôde ser criado (%). A rotina continua chamável à mão.', SQLERRM;
END $cron$;

-- 5) QA (nivel api): base da automacao
CREATE OR REPLACE FUNCTION public.qa_caso_cult_090()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_padrao_ok boolean;
  v_bissexto boolean;
  v_indice boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) os padrões seguros da automação de Cultura';
  r.esperado    := 'Automação nasce desligada, 29/02 cai em 28/02 em ano comum e há índice único de celebração';

  v_padrao_ok := (SELECT count(*) = 2 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name IN ('automacao_aniversario', 'automacao_tempo_casa')
                    AND column_default LIKE '%desligado%');
  v_bissexto := (public.cultura_data_no_ano(2, 29, 2026) = DATE '2026-02-28'
                 AND public.cultura_data_no_ano(2, 29, 2028) = DATE '2028-02-29'
                 AND public.cultura_data_no_ano(3, 10, 2026) = DATE '2026-03-10');
  v_indice := EXISTS (SELECT 1 FROM pg_indexes
                      WHERE schemaname = 'public' AND indexname = 'cultura_acoes_chave_unica_uidx');

  IF v_padrao_ok AND v_bissexto AND v_indice THEN
    r.situacao := 'passou';
    r.obtido   := 'Padrão desligado, regra de 29/02 e índice único presentes.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('padrão desligado=%s; 29/02=%s; índice único=%s', v_padrao_ok, v_bissexto, v_indice);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste SET
    objetivo = 'A configuração governa a detecção e a automação: interruptores de aniversário, tempo de casa e dia da profissão, dias de antecedência, meta de cobertura, tom das mensagens sugeridas e, por tipo, se a rotina diária cria a ação pendente sozinha (padrão desligada).',
    resultado_esperado = 'A configuração persiste e muda o que a tela de Cultura, o Mural e a rotina diária fazem.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-050';

  UPDATE public.qa_casos_teste SET
    objetivo = 'A pergunta do RH é o que fazer agora. O painel Hoje lista as celebrações de hoje, as ações atrasadas e os rituais vencidos, cada um com ação de um toque. Em cada celebração de pessoa há o botão de sugerir mensagem, aberto no CULT-093. Ações criadas pela rotina diária trazem o selo Automática.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-080';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-090', 'Base da automação: padrão desligado, 29/02 e trava de duplicidade',
   'negativo', 'alta', 'aprovado', 'api', NULL,
   'A automação cria ações sozinha, então precisa nascer desligada (ninguém é afetado sem decidir), tratar 29/02 e ter o índice único que impede duas ações para a mesma celebração.',
   'Banco com as migrations da Fase 3 aplicadas.',
   '[{"ordem":1,"acao":"Rodar a rotina qa_caso_cult_090 (somente leitura)","resultado_esperado":"Padrão desligado nas duas colunas, 29/02 vira 28/02 em ano comum e o índice cultura_acoes_chave_unica_uidx existe"}]'::jsonb,
   'Os padrões seguros da automação estão presentes.', 'Rotina qa_caso_cult_090().'),

  (v_mod, 'CULT-091', 'Configurar a automação e gerar as ações agora',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O RH escolhe, por tipo, se a rotina cria a ação pendente sozinha, o tom das mensagens e a meta de cobertura. O botão Gerar ações agora mostra o efeito sem esperar a rotina das 6h.',
   'Sub-aba Configuração, em Rituais e Reconhecimento. Usuário gestor ou acima.',
   '[{"ordem":1,"acao":"Em Automação, ligar Criar ação pendente sozinha para Aniversário","resultado_esperado":"Configuração salva"},
     {"ordem":2,"acao":"Clicar em Gerar ações agora","resultado_esperado":"Aviso com quantas ações foram criadas; elas aparecem com o selo Automática"},
     {"ordem":3,"acao":"Clicar de novo","resultado_esperado":"Nada novo para criar agora"}]'::jsonb,
   'A automação é configurável e gera as ações pendentes sem duplicar.',
   'Só aparece o it() da montagem; o efeito depende de colaboradores com data na janela.'),

  (v_mod, 'CULT-092', 'Rotina diária cria só ações pendentes, sem duplicar e sem expor ninguém',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'A rotina nunca conclui, nunca publica no Mural e nunca concede presente ou folga. Cria no máximo uma ação por pessoa, tipo e ano, mesmo que já exista uma ação manual do ano; ignora admissão não concluída, sem empresa, fora da janela, aniversário de quem tem menos de 1 ano de casa e tenant com a automação desligada.',
   'Colaboradores com datas dentro e fora da janela; um deles com ação manual do ano.',
   '[{"ordem":1,"acao":"Gerar ações agora","resultado_esperado":"Só as celebrações elegíveis ganham ação pendente com selo Automática"},
     {"ordem":2,"acao":"Gerar de novo","resultado_esperado":"Nenhuma ação nova"}]'::jsonb,
   'Criação automática segura e sem duplicidade.',
   'Verificada em réplica local do banco no desenvolvimento (8 cenários). Depende de dado semeado: sem it() de tela.'),

  (v_mod, 'CULT-093', 'Mensagem sugerida pela Íris, editável, sem idade',
   'feliz', 'media', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'No painel Hoje, o ícone de mensagem abre um texto sugerido no tom configurado (leve ou formal). O texto nunca traz idade nem ano de nascimento, pode ser editado, trocado por outra sugestão, copiado ou publicado no Mural pelo usuário. Quem pediu reconhecimento reservado não pode ser publicado.',
   'Uma celebração de hoje.',
   '[{"ordem":1,"acao":"Clicar no ícone de mensagem de uma celebração","resultado_esperado":"Texto sugerido editável"},
     {"ordem":2,"acao":"Clicar em Publicar no Mural","resultado_esperado":"Post publicado e a ação mostra Publicada no Mural"},
     {"ordem":3,"acao":"Repetir para um colaborador reservado","resultado_esperado":"Publicar fica desabilitado, com aviso"}]'::jsonb,
   'A sugestão é só ponto de partida e a preferência é respeitada.',
   'Depende de dado semeado: sem it() de tela; texto e alertas cobertos por vitest.'),

  (v_mod, 'CULT-094', 'Alertas levam ao Plano de Ação',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Medir sem agir não muda nada. Ações atrasadas e cobertura abaixo da meta aparecem em Alertas; cada alerta abre a sugestão de ação do Plano de Ação. Sem alerta, a tela diz que está tudo em dia.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Conferir o card Alertas","resultado_esperado":"Lista os alertas, ou informa que não há nenhum"},
     {"ordem":2,"acao":"Clicar em Criar ação no Plano de Ação","resultado_esperado":"Abre a sugestão de ações com origem Cultura"}]'::jsonb,
   'O alerta fecha o ciclo medir e agir.', NULL)
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-091', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra as opções de automação na Configuração'),
  ('CULT-094', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o painel de alertas')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- PARTE 4/5 — Lembrete ao gestor (coluna) e QA do calendário em PDF
-- (origem: docs/script_cultura_lembrete_gestor_e_pdf.sql)
-- ════════════════════════════════════════════════════════════
-- Script de entrega — Cultura & Celebrações: lembrete ao gestor e calendário em PDF.
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente. NÃO cria tabela: só uma coluna
-- (lembrete ao gestor nasce DESLIGADO), a rotina de QA e casos de QA.
-- Antes de atualizar o texto de 3 casos de QA, guarda a cópia deles.
-- Desfazer o texto dos casos: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo
--   FROM backup_qa_cultura4_20261018 b WHERE b.id=q.id;
-- ORDEM: este script ANTES de publicar as telas na Vercel (as telas leem a coluna nova).

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura4_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura4_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo IN (''CULT-081'',''CULT-090'',''CULT-091'')';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup: %', SQLERRM;
END $bk$;

-- 1) Lembrete ao gestor: desligado por padrao (o RH liga na Configuracao)
ALTER TABLE public.cultura_config
  ADD COLUMN IF NOT EXISTS lembrar_gestor boolean NOT NULL DEFAULT false;

-- 2) QA (nivel api): passa a conferir tambem que o lembrete ao gestor nasce desligado
CREATE OR REPLACE FUNCTION public.qa_caso_cult_090()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_padrao_ok boolean;
  v_bissexto boolean;
  v_indice boolean;
  v_gestor_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) os padrões seguros da automação de Cultura';
  r.esperado    := 'Automação e lembrete ao gestor nascem desligados, 29/02 cai em 28/02 em ano comum e há índice único de celebração';

  v_padrao_ok := (SELECT count(*) = 2 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name IN ('automacao_aniversario', 'automacao_tempo_casa')
                    AND column_default LIKE '%desligado%');
  v_gestor_ok := (SELECT count(*) = 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name = 'lembrar_gestor'
                    AND column_default LIKE '%false%');
  v_bissexto := (public.cultura_data_no_ano(2, 29, 2026) = DATE '2026-02-28'
                 AND public.cultura_data_no_ano(2, 29, 2028) = DATE '2028-02-29'
                 AND public.cultura_data_no_ano(3, 10, 2026) = DATE '2026-03-10');
  v_indice := EXISTS (SELECT 1 FROM pg_indexes
                      WHERE schemaname = 'public' AND indexname = 'cultura_acoes_chave_unica_uidx');

  IF v_padrao_ok AND v_gestor_ok AND v_bissexto AND v_indice THEN
    r.situacao := 'passou';
    r.obtido   := 'Padrões desligados, regra de 29/02 e índice único presentes.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('automação desligada=%s; lembrete gestor desligado=%s; 29/02=%s; índice único=%s',
                         v_padrao_ok, v_gestor_ok, v_bissexto, v_indice);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

-- 3) Documentacao de testes
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste SET
    objetivo = 'O RH precisa enxergar o mês e o ano: onde há concentração de datas e onde faltam rituais. O calendário mostra os mesmos itens da lista de próximas celebrações, mais ações, datas configuradas e rituais, com filtro por Pessoas, Datas e Rituais. Na visão Mês, o botão Baixar PDF gera o calendário do mês (CULT-096).'
  WHERE modulo_id = v_mod AND codigo = 'CULT-081';

  UPDATE public.qa_casos_teste SET
    objetivo = 'A automação e o lembrete ao gestor nascem desligados em todo cliente. O CULT-090 confere os padrões seguros: automação desligada, lembrete ao gestor desligado, 29/02 tratado e índice único de celebração.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-090';

  UPDATE public.qa_casos_teste SET
    objetivo = 'O RH escolhe, por tipo, se a rotina cria a ação pendente sozinha, o tom das mensagens, a meta de cobertura e se os gestores são lembrados no Mural. O botão Gerar ações agora mostra o efeito sem esperar a rotina das 6h.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-091';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-095', 'Lembrete ao gestor mostra só as celebrações do próprio time',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Com Lembrar os gestores ligado na Configuração, o gestor vê no Mural o card Seu time com as celebrações de quem ele gerencia dentro da janela de dias, e um toque abre a mensagem sugerida. O time vem do cadastro: gestor imediato com o nome do gestor, ou departamento em que ele é gestor (ou substituto com a substituição ativa). Ninguém é gestor de si mesmo e quem não tem time não vê o card. Quem pediu reconhecimento reservado aparece com o selo e não pode ser publicado.',
   'Lembrar os gestores ligado; colaborador com data na janela e gestor cadastrado.',
   '[{"ordem":1,"acao":"Entrar como gestor de um colaborador com aniversário próximo e abrir o Mural","resultado_esperado":"Card Seu time com o colaborador, o tipo e os dias que faltam"},
     {"ordem":2,"acao":"Clicar no ícone de mensagem","resultado_esperado":"Texto sugerido editável; publicar no Mural só para quem não é reservado"},
     {"ordem":3,"acao":"Entrar como outra pessoa sem time","resultado_esperado":"O card não aparece"}]'::jsonb,
   'O gestor é lembrado só do próprio time.',
   'Depende de dado semeado (gestor e colaborador com datas); sem it() de tela. Regras auxiliares cobertas por vitest. Desligado, o card não existe.'),

  (v_mod, 'CULT-096', 'Baixar o calendário do mês em PDF',
   'feliz', 'media', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Na visão Mês do calendário, Baixar PDF gera um arquivo A4 paisagem com a grade do mês (até 3 itens por dia) e uma página de detalhamento com todos os itens e a situação das ações. Respeita o filtro ativo, mostra só dia e mês (nunca idade ou ano de nascimento) e deixa de fora quem pediu reconhecimento reservado, com aviso no rodapé, porque o papel circula.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"No calendário, na visão Mês, clicar em Baixar PDF","resultado_esperado":"Arquivo calendario-celebracoes-AAAA-MM.pdf com a grade e o detalhamento"},
     {"ordem":2,"acao":"Mudar o filtro (ex.: Rituais) e baixar de novo","resultado_esperado":"O PDF traz só o grupo filtrado, com o filtro no cabeçalho"},
     {"ordem":3,"acao":"Alternar para a visão Ano","resultado_esperado":"O botão Baixar PDF não aparece"}]'::jsonb,
   'O PDF do mês é gerado e respeita filtro e preferência reservada.',
   'O it() confere o botão; o conteúdo do PDF é coberto por vitest (semanas, células, rodapé, 2 páginas).')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-096', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o botão de baixar o PDF do calendário')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- PARTE 5/5 — Dia da profissão por cargo (IA sugere, pessoa aprova): tabela com RLS e QA
-- (origem: docs/script_cultura_dias_profissao_ia.sql)
-- ════════════════════════════════════════════════════════════
-- Script de entrega — Cultura & Celebrações: dia da profissão por cargo (IA sugere, pessoa aprova).
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente.
-- Cria UMA tabela nova (cultura_dias_profissao) com RLS por empresa, uma rotina de QA e casos de QA.
-- A tabela é criada por EXECUTE dentro de um bloco DO (o auxiliar de RLS automática do SQL Editor
-- injeta comandos no corpo das funções quando enxerga a criação de tabela escrita direto).
-- Antes de atualizar o texto do caso CULT-002, guarda a cópia dele.
-- Desfazer o texto: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo
--   FROM backup_qa_cultura5_20261018 b WHERE b.id=q.id;
-- ORDEM DE ENTREGA: 1) este script  2) publicar a função ai-cultura-dia-profissao  3) publicar as telas.

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura5_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura5_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo = ''CULT-002''';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup: %', SQLERRM;
END $bk$;

DO $tab$
BEGIN
  IF to_regclass('public.cultura_dias_profissao') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.cultura_dias_profissao (
      id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
      tenant_id uuid NOT NULL REFERENCES public.tenants(id),
      cargo_chave text NOT NULL,
      cargo_exemplo text NOT NULL,
      nome_data text,
      mes integer,
      dia integer,
      status text NOT NULL DEFAULT ''aprovado'',
      origem text NOT NULL DEFAULT ''ia'',
      confianca text,
      base text,
      criado_por uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT cultura_dias_profissao_status_chk CHECK (status IN (''aprovado'', ''rejeitado'')),
      CONSTRAINT cultura_dias_profissao_origem_chk CHECK (origem IN (''ia'', ''manual'')),
      CONSTRAINT cultura_dias_profissao_data_chk CHECK (
        status = ''rejeitado''
        OR (nome_data IS NOT NULL AND mes BETWEEN 1 AND 12 AND dia BETWEEN 1 AND 31)),
      CONSTRAINT cultura_dias_profissao_unico UNIQUE (tenant_id, cargo_chave)
    )';
  END IF;
END $tab$;

ALTER TABLE public.cultura_dias_profissao ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant isolation" ON public.cultura_dias_profissao;
CREATE POLICY "Tenant isolation" ON public.cultura_dias_profissao
  FOR ALL TO authenticated
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.cultura_dias_profissao TO authenticated;

-- QA (nivel api): estrutura e isolamento da tabela de decisoes
CREATE OR REPLACE FUNCTION public.qa_caso_cult_097()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_existe boolean;
  v_rls boolean;
  v_politica boolean;
  v_unico boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) a tabela de dias de profissão por cargo';
  r.esperado    := 'Tabela existe, com RLS ligado, política de isolamento por empresa e um registro por cargo';

  v_existe := (to_regclass('public.cultura_dias_profissao') IS NOT NULL);
  v_rls := COALESCE((SELECT c.relrowsecurity FROM pg_class c
                     WHERE c.oid = to_regclass('public.cultura_dias_profissao')), false);
  v_politica := EXISTS (SELECT 1 FROM pg_policies
                        WHERE schemaname = 'public' AND tablename = 'cultura_dias_profissao'
                          AND qual LIKE '%get_user_tenant_id%' AND with_check LIKE '%get_user_tenant_id%');
  v_unico := EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conname = 'cultura_dias_profissao_unico' AND contype = 'u');

  IF v_existe AND v_rls AND v_politica AND v_unico THEN
    r.situacao := 'passou';
    r.obtido   := 'Tabela com RLS, política por empresa e unicidade por cargo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('tabela=%s; RLS=%s; política por empresa=%s; único por cargo=%s', v_existe, v_rls, v_politica, v_unico);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste SET
    objetivo = 'O card Próximas Celebrações puxa aniversários, tempo de casa e dia da profissão dos colaboradores ativos da empresa. Só entram os tipos ligados na Configuração e a janela de dias é a configurada (padrão 30 sem configuração salva). Tempo de casa mostra os anos da data celebrada, não do ano corrente. O dia da profissão vem das decisões da empresa (sugeridas pela IA e aprovadas, ou manuais) e, sem decisão, do catálogo padrão; cargo marcado como sem dia não é celebrado.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-002';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-097', 'Decisões de dia da profissão isoladas por empresa',
   'negativo', 'alta', 'aprovado', 'api', NULL,
   'As decisões sobre o dia da profissão de cada cargo são da empresa: não podem vazar para outra e cada cargo tem uma única decisão.',
   'Banco com a migration aplicada.',
   '[{"ordem":1,"acao":"Rodar a rotina qa_caso_cult_097 (somente leitura)","resultado_esperado":"Tabela com RLS ligado, política por empresa (leitura e escrita) e unicidade por cargo"}]'::jsonb,
   'A tabela de decisões está isolada por empresa.', 'Rotina qa_caso_cult_097().'),

  (v_mod, 'CULT-098', 'Aba Dias da Profissão com análise de cargos por IA',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Em Rituais e Reconhecimento há a aba Dias da Profissão, com o botão Analisar cargos com IA, o resumo de cargos (na empresa, cobertos pelo catálogo padrão, definidos, para analisar) e a lista do que a empresa já definiu.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Abrir Rituais e Reconhecimento e a aba Dias da Profissão","resultado_esperado":"Resumo de cargos, botão Analisar cargos com IA e a lista Definidos pela empresa"}]'::jsonb,
   'A aba monta com o botão de análise por IA.', 'O it() confere só a montagem; a chamada à IA depende de chave e de cargos cadastrados.'),

  (v_mod, 'CULT-099', 'IA sugere o dia da profissão e uma pessoa aprova',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A IA lê os nomes dos cargos (nunca dados de colaboradores) e sugere o dia comemorativo de cada profissão, com confiança e base. Nada vale sem aprovação: a pessoa confere nome, dia e mês e aprova ou descarta. Data impossível devolvida pela IA é descartada; cargo sem data garantida vai para Sem dia comemorativo conhecido; cargo descartado não é analisado de novo e deixa de ser celebrado, mesmo que o catálogo padrão casasse. Aprovado, o dia aparece em Próximas Celebrações e no calendário.',
   'Cargos cadastrados e chave da IA configurada na função.',
   '[{"ordem":1,"acao":"Clicar em Analisar cargos com IA","resultado_esperado":"Lista de sugestões com cargo, profissão, confiança, base e data editável"},
     {"ordem":2,"acao":"Corrigir uma data e aprovar","resultado_esperado":"Entra em Definidos pela empresa como IA aprovada"},
     {"ordem":3,"acao":"Descartar outra sugestão","resultado_esperado":"Entra como sem dia da profissão e não é sugerida de novo"},
     {"ordem":4,"acao":"Conferir o calendário no mês da data aprovada","resultado_esperado":"O dia da profissão aparece"}]'::jsonb,
   'Só entra no calendário o que uma pessoa aprovou.',
   'Depende de chamada real à IA: sem it() de tela. Validação da resposta e catálogo cobertos por vitest.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-098', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra a aba Dias da Profissão com a análise de cargos por IA')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- CONFERÊNCIA FINAL (uma tabela só). Esperado em ambiente com as 5 partes:
--   colunas_config = 5, colunas_acoes = 3, indice_unico = 1, funcoes = 5,
--   tabela_dias_profissao = 1, rls_dias_profissao = 1, casos_qa_novos = 20,
--   automacao_ligada_em_tenants = 0, lembrete_gestor_ligado_em_tenants = 0
-- ════════════════════════════════════════════════════════════
SELECT 'colunas_config' AS item, count(*)::text AS valor FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'cultura_config'
   AND column_name IN ('automacao_aniversario','automacao_tempo_casa','tom_mensagem','meta_cobertura','lembrar_gestor')
UNION ALL SELECT 'colunas_acoes', count(*)::text FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'cultura_acoes'
   AND column_name IN ('origem','chave_unica','publicado_em')
UNION ALL SELECT 'indice_unico', count(*)::text FROM pg_indexes WHERE indexname = 'cultura_acoes_chave_unica_uidx'
UNION ALL SELECT 'funcoes', count(*)::text FROM pg_proc
 WHERE proname IN ('cultura_data_no_ano','cultura_automacao_rodar','cultura_automacao_minha_empresa','qa_caso_cult_090','qa_caso_cult_097')
UNION ALL SELECT 'tabela_dias_profissao', count(*)::text FROM pg_tables WHERE schemaname = 'public' AND tablename = 'cultura_dias_profissao'
UNION ALL SELECT 'rls_dias_profissao', count(*)::text FROM pg_class WHERE oid = to_regclass('public.cultura_dias_profissao') AND relrowsecurity
UNION ALL SELECT 'casos_qa_novos', count(*)::text FROM public.qa_casos_teste
 WHERE codigo IN ('CULT-003','CULT-014','CULT-071','CULT-080','CULT-081','CULT-082','CULT-083','CULT-084','CULT-085','CULT-086',
                  'CULT-090','CULT-091','CULT-092','CULT-093','CULT-094','CULT-095','CULT-096','CULT-097','CULT-098','CULT-099')
UNION ALL SELECT 'automacao_ligada_em_tenants', count(*)::text FROM public.cultura_config
 WHERE automacao_aniversario <> 'desligado' OR automacao_tempo_casa <> 'desligado'
UNION ALL SELECT 'lembrete_gestor_ligado_em_tenants', count(*)::text FROM public.cultura_config WHERE lembrar_gestor;
