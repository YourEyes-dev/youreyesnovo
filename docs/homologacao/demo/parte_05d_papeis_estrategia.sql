-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 05d: Aprendizado & Papeis + Planejamento Estrategico
--
-- PARA QUE SERVE
-- Preenche /aprendizado-papeis (Funcoes com atividades, competencias, POPs, EPIs,
-- treinamentos, indicadores e evidencias; Assinaturas de manual; Visao geral;
-- Configuracoes) e /estrategia (SWOT, Oceano Azul, Cultura e Organograma) da
-- "Metalurgica Exemplo Ltda" (100% ficticia). Depende da PARTE 00 (cargos e
-- colaboradores) e, para o card de perfil ideal, da PARTE 05b.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, depois da parte 00. O arquivo se RECUSA a
-- rodar fora da homologacao/teste (mesma trava da parte 00). Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo, empresa matriz)
--   1. 16 funcoes (cargos) com niveis diferentes de completude: 5 completas
--      (atividades, competencias, POPs, EPIs, treinamentos, manual gerado), 6 parciais,
--      4 minimas e 1 vazia; indicadores, evidencias de treinamento (aprovados,
--      reprovados e em andamento) e 8 envios de manual para assinatura;
--   2. EPIs do catalogo usados nas funcoes (so cria o que ainda nao existir pelo nome);
--   3. Estrategia: cultura (missao, visao, valores, manual), 3 analises SWOT com
--      itens, 2 matrizes Oceano Azul e organograma com ~35 posicoes.
--
-- GARANTIAS
--   - Nenhum dado real; nomes de executivos do organograma sao inventados.
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe".
--   - Nao cria tabela, nao apaga nada, nao altera linhas existentes.
--   - Sem arquivos de storage: URLs de treinamentos/documentos sao enderecos
--     ficticios do dominio .demo; manuais sao HTML pequeno gravado no banco.
-- ============================================================================

SET lock_timeout = '10s';

DO $trava$
DECLARE
  v_url text;
BEGIN
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url' LIMIT 1);
  IF v_url IS NULL
     OR (v_url NOT ILIKE '%fgsblefvdabgdouipigz%' AND v_url NOT ILIKE '%bmehdgthciuvdbvutsdv%') THEN
    RAISE EXCEPTION
      'RECUSADO: app_config.supabase_url (%) nao e a homologacao nem o teste. Os dados de demonstracao nunca entram em producao.',
      COALESCE(v_url, '(vazio)');
  END IF;
END $trava$;

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

CREATE OR REPLACE FUNCTION public.demo_dev_rnd(chave text, m integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT (('x' || substr(md5('youreyes-demo-rnd:' || chave), 1, 7))::bit(28)::int) % GREATEST(m, 1)
$fn$;

-- ---------------------------------------------------------------------------
-- (1) Configuracao do modulo e atividades das funcoes
-- ---------------------------------------------------------------------------
INSERT INTO public.funcao_config (tenant_id, treinamento_epi_obrigatorio, nota_minima_padrao, reaplicacao_meses, ativar_onboarding, ativar_mudanca_funcao)
SELECT 'd3e00000-0000-4000-8000-000000000001', true, 70, 12, true, true
WHERE NOT EXISTS (SELECT 1 FROM public.funcao_config c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001');

INSERT INTO public.funcao_atividades (
  id, tenant_id, cargo_id, nome, descricao, frequencia, complexidade, classificacao, como, resultado_esperado, processo, created_at, updated_at
)
SELECT public.demo_id('fativ:' || v.cargo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('cargo:' || v.cargo),
       v.nome, v.nome || ' — atividade da função de ' || v.cargo || '.', v.freq::public.frequencia_atividade,
       v.comp::public.complexidade_atividade, v.classif::public.classificacao_atividade,
       'Executar "' || v.nome || '" seguindo o procedimento padrão da área, respeitando as regras de segurança e registrando o resultado no sistema.',
       'Atividade concluída dentro do padrão de qualidade e segurança, sem retrabalho.',
       (SELECT c.departamento_id FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo) LIMIT 1)::text,
       now() - interval '120 days', now() - interval '120 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 1, 'Preparar e ajustar o setup da máquina', 'diaria', 'media', 'critica'),
  ('Operador de Usinagem CNC', 2, 'Operar o centro de usinagem CNC', 'diaria', 'alta', 'critica'),
  ('Operador de Usinagem CNC', 3, 'Inspecionar a primeira peça e por amostragem', 'diaria', 'media', 'critica'),
  ('Operador de Usinagem CNC', 4, 'Registrar apontamento de produção e refugo', 'diaria', 'baixa', 'rotineira'),
  ('Operador de Usinagem CNC', 5, 'Realizar manutenção autônoma e limpeza da máquina', 'semanal', 'baixa', 'rotineira'),
  ('Soldador', 1, 'Preparar juntas e conferir o procedimento de soldagem', 'diaria', 'media', 'critica'),
  ('Soldador', 2, 'Soldar estruturas pelo processo MIG/MAG', 'diaria', 'alta', 'critica'),
  ('Soldador', 3, 'Inspecionar visualmente as soldas executadas', 'diaria', 'media', 'critica'),
  ('Soldador', 4, 'Organizar o posto e armazenar consumíveis', 'diaria', 'baixa', 'rotineira'),
  ('Soldador', 5, 'Soldar em posição vertical e sobre cabeça', 'eventual', 'alta', 'excepcional'),
  ('Mecânico de Manutenção', 1, 'Executar manutenção preventiva conforme o cronograma', 'semanal', 'media', 'critica'),
  ('Mecânico de Manutenção', 2, 'Atender chamados de manutenção corretiva', 'diaria', 'alta', 'critica'),
  ('Mecânico de Manutenção', 3, 'Lubrificar e inspecionar equipamentos', 'semanal', 'baixa', 'rotineira'),
  ('Mecânico de Manutenção', 4, 'Registrar ordens de serviço e peças utilizadas', 'diaria', 'baixa', 'rotineira'),
  ('Mecânico de Manutenção', 5, 'Participar de paradas programadas', 'mensal', 'alta', 'excepcional'),
  ('Líder de Produção', 1, 'Conduzir a reunião de início de turno (DDS e metas)', 'diaria', 'media', 'critica'),
  ('Líder de Produção', 2, 'Distribuir tarefas e acompanhar a produção do turno', 'diaria', 'alta', 'critica'),
  ('Líder de Produção', 3, 'Acompanhar indicadores de produção e qualidade', 'semanal', 'media', 'rotineira'),
  ('Líder de Produção', 4, 'Dar feedback e acompanhar o desenvolvimento da equipe', 'mensal', 'media', 'rotineira'),
  ('Líder de Produção', 5, 'Tratar ocorrências de segurança e não conformidades', 'eventual', 'alta', 'critica'),
  ('Operador de Empilhadeira', 1, 'Inspecionar a empilhadeira antes do turno', 'diaria', 'baixa', 'critica'),
  ('Operador de Empilhadeira', 2, 'Movimentar e armazenar cargas com segurança', 'diaria', 'media', 'critica'),
  ('Operador de Empilhadeira', 3, 'Carregar e descarregar caminhões', 'diaria', 'media', 'critica'),
  ('Operador de Empilhadeira', 4, 'Registrar movimentações no sistema', 'diaria', 'baixa', 'rotineira'),
  ('Eletricista de Manutenção', 1, 'Executar manutenção elétrica preventiva', 'semanal', 'media', 'critica'),
  ('Eletricista de Manutenção', 2, 'Atender falhas elétricas (corretiva)', 'diaria', 'alta', 'critica'),
  ('Eletricista de Manutenção', 3, 'Inspecionar quadros elétricos e SPDA', 'mensal', 'media', 'critica'),
  ('Montador de Estruturas Metálicas', 1, 'Montar conjuntos conforme o desenho', 'diaria', 'media', 'critica'),
  ('Montador de Estruturas Metálicas', 2, 'Conferir dimensões e esquadro', 'diaria', 'media', 'rotineira'),
  ('Montador de Estruturas Metálicas', 3, 'Registrar a produção do dia', 'diaria', 'baixa', 'rotineira'),
  ('Supervisor de Manutenção', 1, 'Programar a manutenção da semana', 'semanal', 'media', 'critica'),
  ('Supervisor de Manutenção', 2, 'Analisar indicadores de manutenção (MTBF e MTTR)', 'mensal', 'media', 'rotineira'),
  ('Supervisor de Manutenção', 3, 'Gerir peças de reposição', 'mensal', 'media', 'rotineira'),
  ('Auxiliar de Logística', 1, 'Receber e conferir mercadorias', 'diaria', 'baixa', 'critica'),
  ('Auxiliar de Logística', 2, 'Separar pedidos para expedição', 'diaria', 'baixa', 'rotineira'),
  ('Auxiliar de Logística', 3, 'Organizar o estoque (5S)', 'semanal', 'baixa', 'rotineira'),
  ('Analista da Qualidade', 1, 'Realizar auditorias internas', 'mensal', 'alta', 'critica'),
  ('Analista da Qualidade', 2, 'Tratar não conformidades', 'semanal', 'media', 'critica'),
  ('Analista da Qualidade', 3, 'Emitir relatórios de qualidade', 'mensal', 'media', 'rotineira'),
  ('Analista Financeiro', 1, 'Conciliar contas a pagar e a receber', 'diaria', 'media', 'critica'),
  ('Analista Financeiro', 2, 'Fechar o mês contábil', 'mensal', 'alta', 'critica'),
  ('Analista Financeiro', 3, 'Emitir relatórios gerenciais', 'mensal', 'media', 'rotineira'),
  ('Coordenador de Logística', 1, 'Programar a expedição do dia', 'diaria', 'media', 'critica'),
  ('Coordenador de Logística', 2, 'Acompanhar o indicador de entrega no prazo (OTIF)', 'semanal', 'media', 'rotineira'),
  ('Comprador', 1, 'Cotar e negociar com fornecedores', 'semanal', 'media', 'rotineira'),
  ('Comprador', 2, 'Emitir pedidos de compra', 'diaria', 'baixa', 'rotineira'),
  ('Analista de RH', 1, 'Conduzir recrutamento e admissão', 'semanal', 'media', 'critica'),
  ('Analista de RH', 2, 'Acompanhar ponto e folha de pagamento', 'mensal', 'media', 'critica'),
  ('Técnico de Segurança do Trabalho', 1, 'Realizar inspeções de segurança nas áreas', 'semanal', 'media', 'critica'),
  ('Técnico de Segurança do Trabalho', 2, 'Conduzir DDS e treinamentos de segurança', 'semanal', 'media', 'rotineira')
) AS v(cargo, ordem, nome, freq, comp, classif)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_atividades a WHERE a.id = public.demo_id('fativ:' || v.cargo || ':' || v.ordem));

-- Responsabilidades (funcoes completas)
INSERT INTO public.funcao_responsabilidades (id, tenant_id, atividade_id, responsavel_direto, interfaces, consequencia_erro, created_at, updated_at)
SELECT public.demo_id('fresp:' || a.id::text), 'd3e00000-0000-4000-8000-000000000001', a.id,
       CASE c.nome WHEN 'Mecânico de Manutenção' THEN 'Supervisor de Manutenção'
                   WHEN 'Operador de Empilhadeira' THEN 'Coordenador de Logística'
                   WHEN 'Líder de Produção' THEN 'Gerente Industrial'
                   ELSE 'Líder de Produção' END,
       CASE c.nome WHEN 'Mecânico de Manutenção' THEN 'Produção, Almoxarifado e Compras'
                   WHEN 'Operador de Empilhadeira' THEN 'Expedição, Recebimento e Qualidade'
                   WHEN 'Líder de Produção' THEN 'Manutenção, Qualidade, PCP e RH'
                   ELSE 'Qualidade, Manutenção e PCP' END,
       CASE a.classificacao WHEN 'critica' THEN 'Risco de acidente, peça fora de especificação, retrabalho ou parada de linha.'
                            WHEN 'excepcional' THEN 'Atraso em entrega e necessidade de apoio externo.'
                            ELSE 'Retrabalho administrativo e perda de rastreabilidade.' END,
       now() - interval '120 days', now() - interval '120 days'
FROM public.funcao_atividades a
JOIN public.cargos c ON c.id = a.cargo_id
WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND c.nome IN ('Operador de Usinagem CNC', 'Soldador', 'Mecânico de Manutenção', 'Líder de Produção', 'Operador de Empilhadeira')
  AND NOT EXISTS (SELECT 1 FROM public.funcao_responsabilidades r WHERE r.id = public.demo_id('fresp:' || a.id::text));

-- Ferramentas das atividades 1 e 2 (funcoes completas)
INSERT INTO public.funcao_ferramentas (id, tenant_id, atividade_id, nome, tipo, descricao, created_at)
SELECT public.demo_id('fferr:' || v.cargo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('fativ:' || v.cargo || ':' || v.ordem), v.nome, v.tipo::public.tipo_ferramenta, v.descr, now() - interval '120 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 1, 'Centro de usinagem CNC', 'equipamento', 'Máquina utilizada na usinagem das peças.'),
  ('Operador de Usinagem CNC', 2, 'Software CAM e simulador', 'software', 'Programação e simulação dos programas de usinagem.'),
  ('Soldador', 1, 'Gabaritos e esquadros', 'equipamento', 'Fixação e conferência das juntas.'),
  ('Soldador', 2, 'Máquina de solda MIG/MAG', 'equipamento', 'Equipamento de soldagem semiautomática.'),
  ('Mecânico de Manutenção', 1, 'Ferramental de mecânica e torquímetro', 'equipamento', 'Conjunto de ferramentas calibradas.'),
  ('Mecânico de Manutenção', 2, 'Sistema de ordens de serviço', 'sistema', 'Registro e acompanhamento das OS de manutenção.'),
  ('Líder de Produção', 1, 'Painel de produção (MES)', 'sistema', 'Acompanhamento em tempo real da produção.'),
  ('Líder de Produção', 3, 'Planilha de indicadores do turno', 'planilha', 'Consolidação dos indicadores diários.'),
  ('Operador de Empilhadeira', 2, 'Empilhadeira elétrica', 'equipamento', 'Equipamento de movimentação de cargas.'),
  ('Operador de Empilhadeira', 4, 'Sistema de apontamento de movimentação', 'sistema', 'Registro de entradas e saídas do estoque.')
) AS v(cargo, ordem, nome, tipo, descr)
WHERE EXISTS (SELECT 1 FROM public.funcao_atividades a WHERE a.id = public.demo_id('fativ:' || v.cargo || ':' || v.ordem))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_ferramentas f WHERE f.id = public.demo_id('fferr:' || v.cargo || ':' || v.ordem));

-- Conteudos de apoio das atividades (links ficticios)
INSERT INTO public.funcao_conteudos (id, tenant_id, atividade_id, tipo, titulo, url, descricao, created_at)
SELECT public.demo_id('fcont:' || v.cargo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('fativ:' || v.cargo || ':' || v.ordem), v.tipo::public.tipo_conteudo_funcao, v.titulo, v.url, v.descr, now() - interval '110 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 1, 'manual', 'Manual de setup do centro de usinagem', 'https://docs.metalurgica-exemplo.demo/manuais/setup-cnc', 'Passo a passo ilustrado do setup.'),
  ('Operador de Usinagem CNC', 2, 'video', 'Operação segura da CNC (vídeo interno)', 'https://docs.metalurgica-exemplo.demo/videos/operacao-cnc', 'Boas práticas durante a operação.'),
  ('Soldador', 2, 'pop', 'POP de soldagem MIG/MAG', 'https://docs.metalurgica-exemplo.demo/pops/solda-mig-mag', 'Procedimento padrão da empresa.'),
  ('Mecânico de Manutenção', 1, 'documento', 'Cronograma de preventivas', 'https://docs.metalurgica-exemplo.demo/manutencao/cronograma', 'Planilha com as frequências por equipamento.'),
  ('Líder de Produção', 1, 'apresentacao', 'Modelo de reunião de início de turno', 'https://docs.metalurgica-exemplo.demo/lideranca/dds-modelo', 'Roteiro de 10 minutos.'),
  ('Operador de Empilhadeira', 1, 'instrucao', 'Checklist diário da empilhadeira', 'https://docs.metalurgica-exemplo.demo/nr11/checklist', 'Itens de inspeção antes do turno.')
) AS v(cargo, ordem, tipo, titulo, url, descr)
WHERE EXISTS (SELECT 1 FROM public.funcao_atividades a WHERE a.id = public.demo_id('fativ:' || v.cargo || ':' || v.ordem))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_conteudos f WHERE f.id = public.demo_id('fcont:' || v.cargo || ':' || v.ordem));

-- ---------------------------------------------------------------------------
-- (2) Competencias
-- ---------------------------------------------------------------------------
INSERT INTO public.funcao_competencias (id, tenant_id, cargo_id, nome, tipo, descricao, created_at, updated_at)
SELECT public.demo_id('fcomp:' || v.cargo || ':' || v.nome), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('cargo:' || v.cargo),
       v.nome, v.tipo::public.tipo_competencia, 'Competência esperada para a função de ' || v.cargo || ': ' || lower(v.nome) || '.',
       now() - interval '120 days', now() - interval '120 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 'Programação e operação de CNC', 'tecnica'), ('Operador de Usinagem CNC', 'Leitura de desenho técnico', 'tecnica'),
  ('Soldador', 'Soldagem MIG/MAG', 'tecnica'), ('Soldador', 'Interpretação de simbologia de solda', 'tecnica'),
  ('Mecânico de Manutenção', 'Mecânica industrial', 'tecnica'), ('Mecânico de Manutenção', 'Hidráulica e pneumática', 'tecnica'),
  ('Líder de Produção', 'Gestão de equipe e de turno', 'tecnica'), ('Líder de Produção', 'Comunicação e feedback', 'comportamental'),
  ('Operador de Empilhadeira', 'Operação de empilhadeira (NR-11)', 'tecnica'), ('Operador de Empilhadeira', 'Movimentação segura de cargas', 'tecnica'),
  ('Eletricista de Manutenção', 'Instalações elétricas (NR-10)', 'tecnica'),
  ('Montador de Estruturas Metálicas', 'Montagem de estruturas metálicas', 'tecnica'),
  ('Supervisor de Manutenção', 'Planejamento de manutenção', 'tecnica'),
  ('Auxiliar de Logística', 'Recebimento e conferência', 'tecnica'),
  ('Analista da Qualidade', 'Auditoria da qualidade (ISO 9001)', 'tecnica'),
  ('Analista Financeiro', 'Conciliação e fechamento contábil', 'tecnica'),
  ('Coordenador de Logística', 'Planejamento logístico', 'tecnica'),
  ('Comprador', 'Negociação com fornecedores', 'comportamental'),
  ('Analista de RH', 'Legislação trabalhista', 'tecnica'),
  ('Técnico de Segurança do Trabalho', 'Normas regulamentadoras', 'tecnica')
) AS v(cargo, nome, tipo)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_competencias c WHERE c.id = public.demo_id('fcomp:' || v.cargo || ':' || v.nome));

-- Competencias comuns: 4 para as funcoes completas, 2 para as parciais
INSERT INTO public.funcao_competencias (id, tenant_id, cargo_id, nome, tipo, descricao, created_at, updated_at)
SELECT public.demo_id('fcomp:' || c.nome || ':' || s.nome), 'd3e00000-0000-4000-8000-000000000001', c.id, s.nome, s.tipo::public.tipo_competencia,
       'Competência esperada para a função de ' || c.nome || ': ' || lower(s.nome) || '.', now() - interval '120 days', now() - interval '120 days'
FROM public.cargos c
JOIN (VALUES (1, 'Responsabilidade com a segurança', 'comportamental'), (2, 'Atenção a detalhes', 'cognitiva'),
             (3, 'Trabalho em equipe', 'comportamental'), (4, 'Resolução de problemas', 'cognitiva')) AS s(ordem, nome, tipo)
  ON (c.nome IN ('Operador de Usinagem CNC', 'Soldador', 'Mecânico de Manutenção', 'Líder de Produção', 'Operador de Empilhadeira'))
  OR (c.nome IN ('Eletricista de Manutenção', 'Montador de Estruturas Metálicas', 'Supervisor de Manutenção', 'Auxiliar de Logística', 'Analista da Qualidade', 'Analista Financeiro') AND s.ordem <= 2)
WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.funcao_competencias x WHERE x.id = public.demo_id('fcomp:' || c.nome || ':' || s.nome));

INSERT INTO public.funcao_competencia_recursos (id, tenant_id, competencia_id, tipo, titulo, url, descricao, created_at)
SELECT public.demo_id('fcomprec:' || v.cargo || ':' || v.comp), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('fcomp:' || v.cargo || ':' || v.comp), v.tipo::public.tipo_conteudo_funcao, v.titulo, v.url, v.descr, now() - interval '100 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 'Programação e operação de CNC', 'video', 'Introdução ao G-code', 'https://docs.metalurgica-exemplo.demo/cursos/gcode', 'Curso interno em vídeo.'),
  ('Soldador', 'Soldagem MIG/MAG', 'documento', 'Apostila de soldagem MIG/MAG', 'https://docs.metalurgica-exemplo.demo/cursos/mig-mag', 'Material de estudo da qualificação.'),
  ('Mecânico de Manutenção', 'Hidráulica e pneumática', 'link', 'Guia de hidráulica industrial', 'https://docs.metalurgica-exemplo.demo/cursos/hidraulica', 'Conteúdo complementar.')
) AS v(cargo, comp, tipo, titulo, url, descr)
WHERE EXISTS (SELECT 1 FROM public.funcao_competencias c WHERE c.id = public.demo_id('fcomp:' || v.cargo || ':' || v.comp))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_competencia_recursos r WHERE r.id = public.demo_id('fcomprec:' || v.cargo || ':' || v.comp));

-- ---------------------------------------------------------------------------
-- (3) Indicadores da funcao
-- ---------------------------------------------------------------------------
INSERT INTO public.funcao_indicadores (id, tenant_id, cargo_id, nome, descricao, meta, periodicidade, created_at, updated_at)
SELECT public.demo_id('find:' || v.cargo || ':' || v.nome), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('cargo:' || v.cargo),
       v.nome, v.descr, v.meta, v.per, now() - interval '110 days', now() - interval '110 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 'Refugo da célula', 'Percentual de peças refugadas no turno.', '≤ 1,5%', 'Mensal'),
  ('Operador de Usinagem CNC', 'Tempo de setup', 'Minutos para trocar de ordem de produção.', '≤ 30 min', 'Semanal'),
  ('Soldador', 'Retrabalho de solda', 'Peças soldadas que retornam para correção.', '≤ 2%', 'Mensal'),
  ('Soldador', 'Não conformidades de solda', 'Registros de NC por inspeção visual.', '0', 'Mensal'),
  ('Mecânico de Manutenção', 'Preventivas no prazo', 'Preventivas executadas dentro da janela.', '100%', 'Mensal'),
  ('Mecânico de Manutenção', 'Tempo médio de reparo (MTTR)', 'Horas entre o chamado e a liberação do equipamento.', '≤ 3 h', 'Mensal'),
  ('Líder de Produção', 'Aderência ao plano de produção', 'Produção realizada / planejada.', '≥ 98%', 'Semanal'),
  ('Líder de Produção', 'Acidentes no turno', 'Acidentes com e sem afastamento.', '0', 'Mensal'),
  ('Operador de Empilhadeira', 'Incidentes de movimentação', 'Quase-acidentes e danos na movimentação.', '0', 'Mensal'),
  ('Operador de Empilhadeira', 'Avarias na expedição', 'Ocorrências de avaria na carga.', '≤ 7 por mês', 'Mensal'),
  ('Eletricista de Manutenção', 'Quadros adequados à NR-10', 'Quadros identificados e aterrados.', '100%', 'Trimestral'),
  ('Supervisor de Manutenção', 'Disponibilidade das máquinas', 'Horas disponíveis / programadas.', '≥ 95%', 'Mensal'),
  ('Analista da Qualidade', 'NCs fechadas no prazo', 'Não conformidades encerradas em até 30 dias.', '≥ 90%', 'Mensal'),
  ('Analista Financeiro', 'Prazo médio de recebimento (DSO)', 'Dias entre a venda e o recebimento.', '≤ 40 dias', 'Mensal')
) AS v(cargo, nome, descr, meta, per)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_indicadores i WHERE i.id = public.demo_id('find:' || v.cargo || ':' || v.nome));

-- ---------------------------------------------------------------------------
-- (4) POPs das funcoes completas (atividades 1 e 2) com versoes
-- ---------------------------------------------------------------------------
INSERT INTO public.funcao_pops (
  id, tenant_id, atividade_id, cargo_id, codigo, titulo, status, versao_atual, gerado_por_ia, criado_por_nome, aprovado_por_nome,
  data_aprovacao, objetivo, escopo, responsabilidades, definicoes, pre_requisitos, materiais_ferramentas, epis_sst, procedimento_passos,
  criterios_qualidade, registros_evidencias, tratamento_nao_conformidades, referencias, html_completo, created_at, updated_at
)
SELECT public.demo_id('fpop:' || v.cargo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', a.id, a.cargo_id,
       'POP-' || v.sigla || '-' || lpad(v.ordem::text, 3, '0'), a.nome, v.status, v.versao, v.ia, 'Leiri',
       CASE WHEN v.status = 'publicado' THEN 'Gerente Industrial' END,
       CASE WHEN v.status = 'publicado' THEN now() - (30 + v.ordem * 10) * interval '1 day' END,
       'Padronizar a execução de "' || lower(a.nome) || '" para garantir segurança, qualidade e repetibilidade.',
       'Aplica-se aos colaboradores da função de ' || v.cargo || ' em todos os turnos da unidade.',
       jsonb_build_object('executante', v.cargo, 'supervisao', 'Líder / Supervisor da área', 'interfaces', 'Qualidade, Manutenção e PCP'),
       'POP: Procedimento Operacional Padrão. EPI: Equipamento de Proteção Individual. NC: Não Conformidade.',
       jsonb_build_array('Treinamento de integração concluído', 'EPIs conferidos e em bom estado', 'Ordem de produção ou de serviço liberada'),
       jsonb_build_array('Ferramentas e instrumentos da função', 'Checklist da atividade', 'Computador/tablet do posto'),
       'Uso obrigatório dos EPIs definidos para a função (ver aba de EPIs).',
       jsonb_build_array(
         jsonb_build_object('numero', 1, 'descricao', 'Conferir a ordem e as condições do posto: EPIs, ferramentas e área limpa.', 'tempo_estimado', '5 min', 'ponto_atencao', 'Não iniciar com condição insegura.'),
         jsonb_build_object('numero', 2, 'descricao', 'Executar "' || a.nome || '" conforme o procedimento padrão da área.', 'tempo_estimado', '30 min', 'ponto_atencao', 'Respeitar as instruções de segurança da máquina.'),
         jsonb_build_object('numero', 3, 'descricao', 'Verificar o resultado com o instrumento ou checklist definido.', 'tempo_estimado', '5 min', 'ponto_atencao', 'Registrar qualquer desvio encontrado.'),
         jsonb_build_object('numero', 4, 'descricao', 'Registrar o resultado e as ocorrências no sistema.', 'tempo_estimado', '5 min', 'ponto_atencao', 'Conferir se o apontamento foi salvo.'),
         jsonb_build_object('numero', 5, 'descricao', 'Organizar o posto e comunicar pendências ao líder.', 'tempo_estimado', '5 min', 'ponto_atencao', 'Passagem de turno registrada.')),
       'Resultado dentro da tolerância do desenho/ordem, sem retrabalho e sem desvios de segurança.',
       'Apontamento no sistema e checklist assinado ao final do turno.',
       'Isolar o item não conforme, identificar, avisar o líder e abrir o registro de NC na Qualidade.',
       'NR-12; NR-6; Manual de qualidade da Metalúrgica Exemplo.',
       '<h1>' || a.nome || '</h1><p>POP de demonstração da Metalúrgica Exemplo.</p>',
       now() - interval '90 days', now() - interval '30 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 1, 'CNC', 'publicado', '2.0', false),
  ('Operador de Usinagem CNC', 2, 'CNC', 'publicado', '1.0', true),
  ('Soldador', 1, 'SOL', 'publicado', '1.0', true),
  ('Soldador', 2, 'SOL', 'em_revisao', '1.1', false),
  ('Mecânico de Manutenção', 1, 'MEC', 'publicado', '1.0', false),
  ('Mecânico de Manutenção', 2, 'MEC', 'rascunho', '0.1', true),
  ('Líder de Produção', 1, 'LID', 'publicado', '1.0', false),
  ('Líder de Produção', 2, 'LID', 'desatualizado', '1.0', false),
  ('Operador de Empilhadeira', 1, 'EMP', 'publicado', '1.0', true),
  ('Operador de Empilhadeira', 2, 'EMP', 'publicado', '1.0', false)
) AS v(cargo, ordem, sigla, status, versao, ia)
JOIN public.funcao_atividades a ON a.id = public.demo_id('fativ:' || v.cargo || ':' || v.ordem)
WHERE NOT EXISTS (SELECT 1 FROM public.funcao_pops p WHERE p.id = public.demo_id('fpop:' || v.cargo || ':' || v.ordem));

INSERT INTO public.funcao_pop_versoes (id, tenant_id, pop_id, versao, status, titulo, conteudo_snapshot, motivo_alteracao, resumo_mudancas, alterado_por_nome, created_at)
SELECT public.demo_id('fpopv:' || p.id::text || ':' || s.versao), 'd3e00000-0000-4000-8000-000000000001', p.id, s.versao,
       s.status, p.titulo, jsonb_build_object('titulo', p.titulo, 'versao', s.versao, 'objetivo', p.objetivo),
       s.motivo, s.resumo, 'Leiri', p.created_at + s.dias * interval '1 day'
FROM public.funcao_pops p
JOIN LATERAL (VALUES
  ('1.0', 'publicado', 'Primeira publicação do procedimento.', 'Versão inicial aprovada pela gerência industrial.', 5),
  ('2.0', 'publicado', 'Revisão anual após auditoria interna.', 'Incluídos pontos de atenção e critério de aceite.', 60)
) AS s(versao, status, motivo, resumo, dias)
  ON (s.versao = '1.0' OR p.versao_atual = '2.0')
WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND p.status IN ('publicado', 'desatualizado', 'em_revisao')
  AND NOT EXISTS (SELECT 1 FROM public.funcao_pop_versoes v WHERE v.id = public.demo_id('fpopv:' || p.id::text || ':' || s.versao));

-- ---------------------------------------------------------------------------
-- (5) EPIs: catalogo (so o que nao existe pelo nome) e vinculacao as funcoes
-- ---------------------------------------------------------------------------
INSERT INTO public.epi_tipos (id, tenant_id, nome, descricao, validade_meses, categoria, ca_numero, estoque_minimo, quantidade_estoque, is_active, created_at, updated_at)
SELECT public.demo_id('epitipo:' || v.nome), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descr, v.validade, v.cat, v.ca, 10, 40, true,
       now() - interval '300 days', now() - interval '300 days'
FROM (VALUES
  ('Capacete de segurança', 'Proteção da cabeça contra impactos.', 36, 'Proteção da cabeça', 'CA 00001 (demo)'),
  ('Óculos de proteção', 'Proteção contra partículas e respingos.', 12, 'Proteção dos olhos e face', 'CA 00002 (demo)'),
  ('Protetor auricular', 'Atenuação de ruído contínuo.', 6, 'Proteção auditiva', 'CA 00003 (demo)'),
  ('Luvas de proteção', 'Proteção das mãos contra cortes e abrasão.', 6, 'Proteção das mãos', 'CA 00004 (demo)'),
  ('Calçado de segurança', 'Bota com biqueira de composite.', 12, 'Proteção dos pés', 'CA 00005 (demo)'),
  ('Máscara de solda', 'Proteção contra radiação e respingos de solda.', 24, 'Proteção dos olhos e face', 'CA 00006 (demo)'),
  ('Avental de raspa', 'Proteção do tronco contra respingos de solda.', 12, 'Proteção do tronco', 'CA 00007 (demo)'),
  ('Respirador PFF2', 'Proteção respiratória contra fumos metálicos.', 3, 'Proteção respiratória', 'CA 00008 (demo)'),
  ('Luva isolante', 'Proteção contra choque elétrico (classe 0).', 12, 'Proteção das mãos', 'CA 00009 (demo)')
) AS v(nome, descr, validade, cat, ca)
WHERE NOT EXISTS (SELECT 1 FROM public.epi_tipos e WHERE e.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND lower(e.nome) = lower(v.nome));

INSERT INTO public.funcao_epi_vinculacoes (id, tenant_id, cargo_id, epi_tipo_id, obrigatoriedade, created_at)
SELECT public.demo_id('fepivin:' || v.cargo || ':' || v.epi), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('cargo:' || v.cargo),
       e.id, v.obr::public.obrigatoriedade_epi, now() - interval '110 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 'Capacete de segurança', 'obrigatorio'), ('Operador de Usinagem CNC', 'Óculos de proteção', 'obrigatorio'),
  ('Operador de Usinagem CNC', 'Protetor auricular', 'obrigatorio'), ('Operador de Usinagem CNC', 'Calçado de segurança', 'obrigatorio'),
  ('Operador de Usinagem CNC', 'Luvas de proteção', 'recomendado'),
  ('Soldador', 'Máscara de solda', 'obrigatorio'), ('Soldador', 'Avental de raspa', 'obrigatorio'), ('Soldador', 'Luvas de proteção', 'obrigatorio'),
  ('Soldador', 'Calçado de segurança', 'obrigatorio'), ('Soldador', 'Protetor auricular', 'obrigatorio'), ('Soldador', 'Respirador PFF2', 'condicional'),
  ('Mecânico de Manutenção', 'Capacete de segurança', 'obrigatorio'), ('Mecânico de Manutenção', 'Óculos de proteção', 'obrigatorio'),
  ('Mecânico de Manutenção', 'Luvas de proteção', 'obrigatorio'), ('Mecânico de Manutenção', 'Calçado de segurança', 'obrigatorio'),
  ('Mecânico de Manutenção', 'Protetor auricular', 'obrigatorio'),
  ('Eletricista de Manutenção', 'Luva isolante', 'obrigatorio'), ('Eletricista de Manutenção', 'Capacete de segurança', 'obrigatorio'),
  ('Eletricista de Manutenção', 'Calçado de segurança', 'obrigatorio'), ('Eletricista de Manutenção', 'Óculos de proteção', 'recomendado'),
  ('Operador de Empilhadeira', 'Capacete de segurança', 'obrigatorio'), ('Operador de Empilhadeira', 'Calçado de segurança', 'obrigatorio'),
  ('Operador de Empilhadeira', 'Luvas de proteção', 'recomendado'),
  ('Líder de Produção', 'Capacete de segurança', 'obrigatorio'), ('Líder de Produção', 'Óculos de proteção', 'obrigatorio'),
  ('Líder de Produção', 'Protetor auricular', 'obrigatorio'), ('Líder de Produção', 'Calçado de segurança', 'obrigatorio'),
  ('Montador de Estruturas Metálicas', 'Capacete de segurança', 'obrigatorio'), ('Montador de Estruturas Metálicas', 'Óculos de proteção', 'obrigatorio'),
  ('Montador de Estruturas Metálicas', 'Luvas de proteção', 'obrigatorio'), ('Montador de Estruturas Metálicas', 'Calçado de segurança', 'obrigatorio'),
  ('Supervisor de Manutenção', 'Capacete de segurança', 'obrigatorio'), ('Supervisor de Manutenção', 'Óculos de proteção', 'obrigatorio'),
  ('Supervisor de Manutenção', 'Calçado de segurança', 'obrigatorio'),
  ('Auxiliar de Logística', 'Calçado de segurança', 'obrigatorio'), ('Auxiliar de Logística', 'Luvas de proteção', 'obrigatorio'),
  ('Analista da Qualidade', 'Capacete de segurança', 'condicional'), ('Analista da Qualidade', 'Calçado de segurança', 'condicional'),
  ('Analista da Qualidade', 'Óculos de proteção', 'condicional')
) AS v(cargo, epi, obr)
JOIN public.epi_tipos e ON e.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND lower(e.nome) = lower(v.epi)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_epi_vinculacoes x WHERE x.id = public.demo_id('fepivin:' || v.cargo || ':' || v.epi));

-- Material e questionario de treinamento por EPI (funcoes criticas)
INSERT INTO public.funcao_epi_conteudos (id, tenant_id, vinculacao_id, tipo, titulo, url, descricao, created_at)
SELECT public.demo_id('fepicont:' || v.cargo || ':' || v.epi), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('fepivin:' || v.cargo || ':' || v.epi), v.tipo::public.tipo_conteudo_funcao, v.titulo, v.url, v.descr, now() - interval '100 days'
FROM (VALUES
  ('Soldador', 'Máscara de solda', 'video', 'Uso correto da máscara de solda', 'https://docs.metalurgica-exemplo.demo/epi/mascara-solda', 'Ajuste de tonalidade e conservação.'),
  ('Soldador', 'Respirador PFF2', 'documento', 'Quando usar o respirador PFF2', 'https://docs.metalurgica-exemplo.demo/epi/respirador-pff2', 'Critérios de uso e troca.'),
  ('Operador de Usinagem CNC', 'Protetor auricular', 'video', 'Colocação do protetor auricular', 'https://docs.metalurgica-exemplo.demo/epi/protetor-auricular', 'Técnica correta de inserção.'),
  ('Eletricista de Manutenção', 'Luva isolante', 'documento', 'Inspeção da luva isolante', 'https://docs.metalurgica-exemplo.demo/epi/luva-isolante', 'Teste de estanqueidade e validade.')
) AS v(cargo, epi, tipo, titulo, url, descr)
WHERE EXISTS (SELECT 1 FROM public.funcao_epi_vinculacoes x WHERE x.id = public.demo_id('fepivin:' || v.cargo || ':' || v.epi))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_epi_conteudos c WHERE c.id = public.demo_id('fepicont:' || v.cargo || ':' || v.epi));

INSERT INTO public.funcao_epi_questionarios (id, tenant_id, vinculacao_id, pergunta, opcoes, resposta_correta, ordem, created_at)
SELECT public.demo_id('fepiq:' || v.cargo || ':' || v.epi || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('fepivin:' || v.cargo || ':' || v.epi), v.pergunta, v.opcoes::jsonb, v.correta, v.ordem, now() - interval '100 days'
FROM (VALUES
  ('Soldador', 'Máscara de solda', 1, 'Quando a máscara de solda deve ser baixada?', '["Depois de abrir o arco", "Antes de abrir o arco", "Somente no fim da junta", "Nunca"]', 1),
  ('Soldador', 'Máscara de solda', 2, 'O que fazer ao notar a lente trincada?', '["Continuar até o fim do turno", "Trocar a lente antes de soldar", "Colar com fita", "Usar óculos comuns"]', 1),
  ('Operador de Usinagem CNC', 'Protetor auricular', 1, 'O protetor auricular deve ser usado:', '["Somente em reuniões", "Em toda a área com ruído acima do limite", "Quando houver visita", "Apenas à noite"]', 1),
  ('Operador de Usinagem CNC', 'Protetor auricular', 2, 'Quando substituir o protetor auricular de espuma?', '["Nunca", "Quando estiver sujo, deformado ou conforme a periodicidade", "Só no fim do ano", "Quando o colega pedir"]', 1),
  ('Eletricista de Manutenção', 'Luva isolante', 1, 'Antes de usar a luva isolante, deve-se:', '["Lavar com sabão", "Inspecionar visualmente e testar o ar", "Passar óleo", "Guardar dobrada"]', 1),
  ('Eletricista de Manutenção', 'Luva isolante', 2, 'A luva isolante pode ser usada com furo pequeno?', '["Sim", "Não, deve ser descartada", "Sim, com fita", "Apenas na baixa tensão"]', 1)
) AS v(cargo, epi, ordem, pergunta, opcoes, correta)
WHERE EXISTS (SELECT 1 FROM public.funcao_epi_vinculacoes x WHERE x.id = public.demo_id('fepivin:' || v.cargo || ':' || v.epi))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_epi_questionarios q WHERE q.id = public.demo_id('fepiq:' || v.cargo || ':' || v.epi || ':' || v.ordem));

-- ---------------------------------------------------------------------------
-- (6) Treinamentos da funcao e evidencias dos colaboradores
-- ---------------------------------------------------------------------------
INSERT INTO public.funcao_treinamentos (id, tenant_id, cargo_id, titulo, tipo, url, descricao, obrigatorio, carga_horaria_min, created_at)
SELECT public.demo_id('ftrein:' || v.cargo || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('cargo:' || v.cargo),
       v.titulo, v.tipo, 'https://treinamentos.metalurgica-exemplo.demo/' || v.slug, v.descr, v.obrig, v.min, now() - interval '110 days'
FROM (VALUES
  ('Operador de Usinagem CNC', 1, 'Operação segura de centros de usinagem', 'video', 'cnc-operacao-segura', 'Procedimentos de segurança na operação.', true, 90),
  ('Operador de Usinagem CNC', 2, 'Leitura de desenho técnico aplicada', 'documento', 'cnc-desenho-tecnico', 'Estudo dirigido com desenhos reais.', false, 120),
  ('Soldador', 1, 'Segurança em operações de solda', 'video', 'solda-seguranca', 'Riscos de fumos, radiação e incêndio.', true, 60),
  ('Soldador', 2, 'Qualificação MIG/MAG nível 1', 'documento', 'solda-qualificacao', 'Roteiro de qualificação do soldador.', true, 240),
  ('Mecânico de Manutenção', 1, 'Bloqueio e etiquetagem (LOTO)', 'video', 'mec-loto', 'Procedimento de energia zero.', true, 60),
  ('Mecânico de Manutenção', 2, 'Hidráulica industrial', 'documento', 'mec-hidraulica', 'Componentes e diagnóstico.', false, 180),
  ('Líder de Produção', 1, 'Reunião de início de turno', 'video', 'lid-dds', 'Como conduzir o DDS e as metas do dia.', true, 45),
  ('Líder de Produção', 2, 'Feedback para equipes operacionais', 'documento', 'lid-feedback', 'Roteiro de feedback.', false, 60),
  ('Operador de Empilhadeira', 1, 'NR-11 — Operação de empilhadeira', 'video', 'emp-nr11', 'Conteúdo da norma aplicado ao pátio.', true, 120),
  ('Operador de Empilhadeira', 2, 'Direção defensiva no pátio', 'documento', 'emp-defensiva', 'Cenários de risco de circulação.', true, 60)
) AS v(cargo, ordem, titulo, tipo, slug, descr, obrig, min)
WHERE EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.funcao_treinamentos t WHERE t.id = public.demo_id('ftrein:' || v.cargo || ':' || v.ordem));

INSERT INTO public.funcao_treinamento_evidencias (
  id, tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, cargo_id, vinculacao_id, tipo_treinamento, data_acesso,
  data_conclusao, nota, nota_minima, aprovado, aceite_eletronico, tentativa, detalhes, created_at
)
SELECT public.demo_id('fevid:' || v.n || ':' || v.tipo), 'd3e00000-0000-4000-8000-000000000001', a.id, a.nome_completo, a.cpf, a.cargo_id,
       (SELECT x.id FROM public.funcao_epi_vinculacoes x WHERE x.cargo_id = a.cargo_id ORDER BY x.created_at, x.id LIMIT 1),
       v.tipo, now() - v.dias * interval '1 day',
       CASE WHEN v.estado <> 'andamento' THEN now() - v.dias * interval '1 day' + interval '25 minutes' END,
       CASE WHEN v.estado <> 'andamento' THEN v.nota END, 70,
       CASE v.estado WHEN 'aprovado' THEN true WHEN 'reprovado' THEN false END,
       v.estado = 'aprovado', v.tent, jsonb_build_object('origem', 'demonstracao'), now() - v.dias * interval '1 day'
FROM (VALUES
  (1, 'epi', 'aprovado', 90, 40, 1), (2, 'epi', 'aprovado', 100, 70, 1), (3, 'epi', 'aprovado', 80, 100, 1), (4, 'epi', 'reprovado', 60, 20, 1),
  (4, 'funcao', 'aprovado', 90, 15, 2), (5, 'epi', 'aprovado', 100, 150, 1), (6, 'epi', 'andamento', 0, 2, 1),
  (13, 'epi', 'aprovado', 90, 200, 1), (14, 'epi', 'aprovado', 80, 180, 1), (15, 'epi', 'reprovado', 50, 60, 1), (15, 'funcao', 'aprovado', 80, 55, 2),
  (16, 'epi', 'aprovado', 100, 140, 1), (17, 'epi', 'andamento', 0, 4, 1),
  (30, 'epi', 'aprovado', 90, 220, 1), (31, 'epi', 'aprovado', 100, 210, 1), (32, 'funcao', 'aprovado', 80, 190, 1), (33, 'epi', 'aprovado', 90, 170, 1),
  (41, 'epi', 'aprovado', 100, 120, 1), (42, 'epi', 'aprovado', 90, 110, 1), (43, 'funcao', 'reprovado', 55, 30, 1), (44, 'epi', 'aprovado', 80, 95, 1),
  (28, 'funcao', 'aprovado', 100, 260, 1), (29, 'funcao', 'aprovado', 90, 250, 1)
) AS v(n, tipo, estado, nota, dias, tent)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE a.cargo_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.funcao_treinamento_evidencias e WHERE e.id = public.demo_id('fevid:' || v.n || ':' || v.tipo));

-- ---------------------------------------------------------------------------
-- (7) Manuais gerados (funcoes completas) e envios para assinatura
-- ---------------------------------------------------------------------------
INSERT INTO public.manuais_gerados (id, tenant_id, empresa_id, tipo, referencia_id, titulo, html, gerado_por_nome, created_at, updated_at)
SELECT public.demo_id('manual:' || c.nome), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'funcao', c.id::text, 'Manual da Função — ' || c.nome,
       '<html><body><h1>Manual da Função — ' || c.nome || '</h1>'
       || '<p><strong>Metalúrgica Exemplo Ltda</strong> — documento de demonstração.</p>'
       || '<h2>Objetivo da função</h2><p>' || COALESCE(c.objetivo_funcao, '—') || '</p>'
       || '<h2>Atividades</h2><ul>'
       || COALESCE((SELECT string_agg('<li>' || a.nome || ' (' || a.frequencia::text || ')</li>', '' ORDER BY a.nome)
                      FROM public.funcao_atividades a WHERE a.cargo_id = c.id), '')
       || '</ul><h2>Competências</h2><ul>'
       || COALESCE((SELECT string_agg('<li>' || k.nome || '</li>', '' ORDER BY k.nome)
                      FROM public.funcao_competencias k WHERE k.cargo_id = c.id), '')
       || '</ul><h2>Responsabilidade</h2><p>' || COALESCE(c.responsabilidade, '—') || '</p></body></html>',
       'Leiri', now() - interval '60 days', now() - interval '60 days'
FROM public.cargos c
WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND c.nome IN ('Operador de Usinagem CNC', 'Soldador', 'Mecânico de Manutenção', 'Líder de Produção', 'Operador de Empilhadeira')
  AND NOT EXISTS (SELECT 1 FROM public.manuais_gerados m WHERE m.id = public.demo_id('manual:' || c.nome));

INSERT INTO public.manual_funcao_assinaturas (
  id, tenant_id, empresa_id, cargo_id, cargo_nome, colaborador_id, colaborador_nome, colaborador_cpf, gestor_id, gestor_nome, gestor_cpf,
  gestor_email, manual_html_snapshot, termo_html, manual_titulo, status, assinatura_colaborador, assinatura_gestor, data_envio,
  data_assinatura_colaborador, data_assinatura_gestor, data_conclusao, enviado_por_nome, observacoes, created_at, updated_at
)
SELECT public.demo_id('manualass:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.cargo_id, a.cargo, a.id, a.nome_completo, a.cpf, g.id, g.nome_completo, g.cpf, g.email,
       m.html, '<p>Declaro que recebi, li e compreendi o manual da minha função e as regras de segurança nele descritas.</p>',
       m.titulo, v.status,
       CASE WHEN v.status IN ('aguardando_gestor', 'concluido') THEN jsonb_build_object('nome', a.nome_completo, 'aceite', true, 'ip', '10.0.0.1') END,
       CASE WHEN v.status = 'concluido' THEN jsonb_build_object('nome', g.nome_completo, 'aceite', true, 'ip', '10.0.0.2') END,
       now() - v.dias * interval '1 day',
       CASE WHEN v.status IN ('aguardando_gestor', 'concluido') THEN now() - (v.dias - 1) * interval '1 day' END,
       CASE WHEN v.status = 'concluido' THEN now() - (v.dias - 2) * interval '1 day' END,
       CASE WHEN v.status = 'concluido' THEN now() - (v.dias - 2) * interval '1 day' END,
       'Leiri', CASE WHEN v.status = 'cancelado' THEN 'Cancelado: colaborador transferido de turno; reenviar após a mudança.' END,
       now() - v.dias * interval '1 day', now() - v.dias * interval '1 day'
FROM (VALUES
  (1, 'concluido', 50), (13, 'concluido', 45), (30, 'concluido', 40), (41, 'concluido', 35),
  (2, 'aguardando_gestor', 6), (14, 'aguardando_colaborador', 4), (31, 'aguardando_colaborador', 3), (42, 'cancelado', 20)
) AS v(n, status, dias)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
JOIN public.admissoes g ON g.id = public.demo_id('admissao:' || CASE WHEN a.departamento = 'Produção' THEN 28
                                                                     WHEN a.departamento = 'Manutenção' THEN 40 ELSE 52 END)
JOIN public.manuais_gerados m ON m.referencia_id = a.cargo_id::text AND m.tipo = 'funcao' AND m.tenant_id = a.tenant_id
WHERE NOT EXISTS (SELECT 1 FROM public.manual_funcao_assinaturas x WHERE x.id = public.demo_id('manualass:' || v.n));

INSERT INTO public.manual_funcao_links (id, tenant_id, assinatura_id, tipo_assinante, token, expires_at, used_at, created_at)
SELECT public.demo_id('manuallink:' || s.id::text || ':' || t.tipo), 'd3e00000-0000-4000-8000-000000000001', s.id, t.tipo,
       md5('demo-manual-link:' || s.id::text || ':' || t.tipo) || substr(md5('demo-manual-link2:' || s.id::text || ':' || t.tipo), 1, 16),
       s.data_envio + interval '30 days',
       CASE WHEN t.tipo = 'colaborador' THEN s.data_assinatura_colaborador ELSE s.data_assinatura_gestor END, s.data_envio
FROM public.manual_funcao_assinaturas s
CROSS JOIN (VALUES ('colaborador'), ('gestor')) AS t(tipo)
WHERE s.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.manual_funcao_links l WHERE l.id = public.demo_id('manuallink:' || s.id::text || ':' || t.tipo));

-- ===========================================================================
-- PLANEJAMENTO ESTRATEGICO (/estrategia)
-- ===========================================================================

-- (E1) Cultura (missao, visao, valores e manual de cultura) — um registro por empresa
INSERT INTO public.estrategia_cultura (
  id, tenant_id, empresa_id, missao, visao, valores, principios, comportamentos_esperados, comportamentos_nao_tolerados,
  proposito, carta_boas_vindas, tom_de_voz, codigo_conduta, dress_code, modelo_trabalho, criado_por_nome, created_at, updated_at
)
SELECT public.demo_id('cultura:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'Fabricar estruturas e componentes metálicos com qualidade, segurança e respeito às pessoas, gerando valor para clientes, colaboradores e comunidade.',
       'Ser reconhecida até 2030 como a metalúrgica de referência do Sul do Brasil em qualidade, segurança e desenvolvimento de pessoas.',
       '["Segurança em primeiro lugar", "Respeito às pessoas", "Qualidade no que entregamos", "Melhoria contínua", "Compromisso com o cliente", "Ética e transparência"]'::jsonb,
       '["Nenhuma meta justifica um risco para a vida", "Quem faz, conhece: decisões perto da operação", "Dados antes de opiniões", "Aprender com o erro sem procurar culpados"]'::jsonb,
       '["Usa corretamente os EPIs e interrompe a atividade diante de risco", "Pede e dá feedback com respeito", "Cumpre combinados e avisa antes de atrasar", "Propõe melhorias no seu posto", "Cuida do patrimônio e da limpeza do ambiente"]'::jsonb,
       '["Ignorar regras de segurança para ganhar tempo", "Assédio moral ou sexual", "Discriminação de qualquer natureza", "Omitir erro que afete a qualidade ou a segurança"]'::jsonb,
       'Transformar metal em estruturas que sustentam o trabalho e a vida de milhares de pessoas, sem que ninguém se machuque no caminho.',
       'Seja bem-vindo(a) à Metalúrgica Exemplo! Aqui, cada pessoa importa e a segurança vem antes de qualquer meta. Nos primeiros dias você terá um padrinho ou madrinha para ajudar na integração. Conte conosco.',
       'Direto, respeitoso e próximo. Falamos a língua da fábrica, sem jargão desnecessário.',
       'O Código de Conduta orienta relações com colegas, clientes e fornecedores: ética, respeito, confidencialidade, prevenção de conflitos de interesse e canal de denúncia confidencial (Ouvidoria).',
       'Uniforme e EPIs obrigatórios nas áreas produtivas; vestimenta casual de trabalho no administrativo.',
       'Presencial na fábrica; híbrido (2 dias remotos) para funções administrativas elegíveis.',
       'Leiri', now() - interval '200 days', now() - interval '20 days'
WHERE NOT EXISTS (SELECT 1 FROM public.estrategia_cultura c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND c.empresa_id = 'd3e00000-0000-4000-8000-000000000002');

-- (E2) Analises SWOT
INSERT INTO public.estrategia_swot (id, tenant_id, empresa_id, titulo, descricao, escopo, unidade, periodo, projeto, criado_por_nome, created_at, updated_at)
SELECT public.demo_id('swot:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.titulo, v.descr, v.escopo, v.unidade, v.periodo, v.projeto, 'Leiri', now() - v.dias * interval '1 day', now() - v.dias * interval '1 day'
FROM (VALUES
  ('corp', 'SWOT Corporativo 2026', 'Análise do ambiente interno e externo da Metalúrgica Exemplo para o planejamento anual.', 'empresa', NULL, '01/01/2026 a 31/12/2026', NULL, 280),
  ('oper', 'SWOT — Operações (Produção e Manutenção)', 'Forças e fraquezas da fábrica matriz para orientar os investimentos em máquinas e pessoas.', 'unidade', 'Fábrica Matriz', '01/07/2026 a 31/12/2026', NULL, 120),
  ('cd', 'SWOT — Expansão do CD Itajaí', 'Avaliação do projeto de ampliação da capacidade do centro de distribuição.', 'projeto', NULL, 'A partir de 01/09/2026', 'Expansão do CD Itajaí', 45)
) AS v(chave, titulo, descr, escopo, unidade, periodo, projeto, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.estrategia_swot s WHERE s.id = public.demo_id('swot:' || v.chave));

INSERT INTO public.estrategia_swot_itens (id, tenant_id, swot_id, tipo, descricao, classificacao, impacto, ordem, created_at, updated_at)
SELECT public.demo_id('swotitem:' || v.swot || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('swot:' || v.swot),
       v.tipo::public.swot_tipo, v.descr, v.classif::public.swot_classificacao, v.impacto::public.swot_impacto, v.ordem, now() - interval '100 days', now() - interval '100 days'
FROM (VALUES
  ('corp', 1, 'forca', 'Equipe técnica experiente em usinagem e solda', 'operacional', 'alto'),
  ('corp', 2, 'forca', 'Parque de máquinas CNC modernizado nos últimos 3 anos', 'operacional', 'alto'),
  ('corp', 3, 'forca', 'Certificação ISO 9001 renovada', 'estrategico', 'alto'),
  ('corp', 4, 'forca', 'Baixo índice de acidentes nos últimos 12 meses', 'pessoas', 'medio'),
  ('corp', 5, 'fraqueza', 'Dependência de poucos programadores CNC', 'pessoas', 'alto'),
  ('corp', 6, 'fraqueza', 'Retrabalho acima da meta na Filial Curitiba', 'operacional', 'medio'),
  ('corp', 7, 'fraqueza', 'Expedição do CD Itajaí ainda com processos manuais', 'operacional', 'medio'),
  ('corp', 8, 'fraqueza', 'Turnover concentrado na área de usinagem', 'pessoas', 'alto'),
  ('corp', 9, 'oportunidade', 'Crescimento da demanda do setor de estruturas para energia', 'mercado', 'alto'),
  ('corp', 10, 'oportunidade', 'Linhas de crédito e incentivos para modernização industrial', 'estrategico', 'medio'),
  ('corp', 11, 'oportunidade', 'Contratos de fornecimento de longo prazo com grandes clientes', 'mercado', 'alto'),
  ('corp', 12, 'oportunidade', 'Digitalização da gestão de pessoas e de SST', 'estrategico', 'medio'),
  ('corp', 13, 'ameaca', 'Alta do preço do aço e volatilidade cambial', 'mercado', 'alto'),
  ('corp', 14, 'ameaca', 'Escassez de soldadores qualificados na região', 'pessoas', 'alto'),
  ('corp', 15, 'ameaca', 'Concorrência de produtos importados', 'mercado', 'medio'),
  ('corp', 16, 'ameaca', 'Novas exigências regulatórias (NR-01 — riscos psicossociais)', 'estrategico', 'medio'),
  ('oper', 1, 'forca', 'Manutenção preventiva estruturada com cronograma', 'operacional', 'alto'),
  ('oper', 2, 'forca', 'Líderes de turno com tempo de casa e respeito da equipe', 'pessoas', 'medio'),
  ('oper', 3, 'fraqueza', 'Paradas não planejadas em duas máquinas CNC antigas', 'operacional', 'alto'),
  ('oper', 4, 'fraqueza', 'Pouca padronização de setup entre turnos', 'operacional', 'medio'),
  ('oper', 5, 'oportunidade', 'Manutenção preditiva com sensores de vibração', 'operacional', 'alto'),
  ('oper', 6, 'oportunidade', 'Treinamento cruzado entre usinagem e solda', 'pessoas', 'medio'),
  ('oper', 7, 'ameaca', 'Prazo de importação de peças de reposição', 'mercado', 'medio'),
  ('oper', 8, 'ameaca', 'Concorrência por mão de obra técnica na região', 'pessoas', 'alto'),
  ('cd', 1, 'forca', 'Localização próxima ao porto de Itajaí', 'estrategico', 'alto'),
  ('cd', 2, 'forca', 'Equipe de expedição treinada em NR-11', 'pessoas', 'medio'),
  ('cd', 3, 'fraqueza', 'Área de armazenagem atual próxima do limite', 'operacional', 'alto'),
  ('cd', 4, 'fraqueza', 'Sistema de endereçamento de estoque ainda manual', 'operacional', 'medio'),
  ('cd', 5, 'oportunidade', 'Crescimento das exportações de estruturas metálicas', 'mercado', 'alto'),
  ('cd', 6, 'oportunidade', 'Contratação de WMS com integração ao ERP', 'estrategico', 'medio'),
  ('cd', 7, 'ameaca', 'Custo do frete e congestionamento no acesso ao porto', 'mercado', 'medio'),
  ('cd', 8, 'ameaca', 'Prazo de licenciamento da ampliação', 'estrategico', 'medio')
) AS v(swot, ordem, tipo, descr, classif, impacto)
WHERE EXISTS (SELECT 1 FROM public.estrategia_swot s WHERE s.id = public.demo_id('swot:' || v.swot))
  AND NOT EXISTS (SELECT 1 FROM public.estrategia_swot_itens i WHERE i.id = public.demo_id('swotitem:' || v.swot || ':' || v.ordem));

-- (E3) Matrizes Oceano Azul
INSERT INTO public.estrategia_oceano_azul (id, tenant_id, empresa_id, swot_id, titulo, descricao, criado_por_nome, created_at, updated_at)
SELECT public.demo_id('oceano:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       CASE WHEN v.swot IS NOT NULL THEN public.demo_id('swot:' || v.swot) END, v.titulo, v.descr, 'Leiri',
       now() - v.dias * interval '1 day', now() - v.dias * interval '1 day'
FROM (VALUES
  ('entrega', 'corp', 'Oceano Azul — Entrega programada e engenharia de aplicação', 'Como sair da guerra de preço por tonelada e competir por previsibilidade e apoio técnico.', 200),
  ('sob_medida', NULL, 'Oceano Azul — Soluções sob medida para o setor de energia', 'Reposicionamento da oferta para estruturas sob medida com prazo garantido.', 60)
) AS v(chave, swot, titulo, descr, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.estrategia_oceano_azul o WHERE o.id = public.demo_id('oceano:' || v.chave));

INSERT INTO public.estrategia_oceano_itens (id, tenant_id, oceano_id, quadrante, descricao, swot_item_id, ordem, created_at)
SELECT public.demo_id('oceanoitem:' || v.oceano || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('oceano:' || v.oceano),
       v.quadrante::public.oceano_quadrante, v.descr,
       CASE WHEN v.swot_ordem IS NOT NULL THEN public.demo_id('swotitem:corp:' || v.swot_ordem) END, v.ordem, now() - interval '90 days'
FROM (VALUES
  ('entrega', 1, 'eliminar', 'Retrabalho causado por falha de setup', 6),
  ('entrega', 2, 'eliminar', 'Planilhas paralelas de controle de estoque', 7),
  ('entrega', 3, 'reduzir', 'Tempo de setup das máquinas CNC', 5),
  ('entrega', 4, 'reduzir', 'Dependência de poucos programadores', 5),
  ('entrega', 5, 'elevar', 'Qualidade e rastreabilidade de solda', 3),
  ('entrega', 6, 'elevar', 'Pontualidade de entrega (OTIF)', 11),
  ('entrega', 7, 'criar', 'Entrega programada com janela fixa para grandes clientes', 11),
  ('entrega', 8, 'criar', 'Engenharia de aplicação junto ao cliente', 9),
  ('sob_medida', 1, 'eliminar', 'Orçamentos manuais demorados', NULL),
  ('sob_medida', 2, 'reduzir', 'Estoque de peças padronizadas de baixo giro', NULL),
  ('sob_medida', 3, 'elevar', 'Prazo garantido por contrato', NULL),
  ('sob_medida', 4, 'elevar', 'Transparência do andamento do pedido', NULL),
  ('sob_medida', 5, 'criar', 'Portal de acompanhamento da obra para o cliente', NULL),
  ('sob_medida', 6, 'criar', 'Pacote de montagem em campo com equipe própria', NULL)
) AS v(oceano, ordem, quadrante, descr, swot_ordem)
WHERE EXISTS (SELECT 1 FROM public.estrategia_oceano_azul o WHERE o.id = public.demo_id('oceano:' || v.oceano))
  AND NOT EXISTS (SELECT 1 FROM public.estrategia_oceano_itens i WHERE i.id = public.demo_id('oceanoitem:' || v.oceano || ':' || v.ordem));

-- (E4) Organograma: diretoria, gerencias, lideres e equipes (colaboradores da parte 00)
INSERT INTO public.estrategia_organograma (
  id, tenant_id, empresa_id, parent_id, cargo_id, departamento_id, titulo, nome_ocupante, colaborador_id, tipo, ordem, created_at, updated_at
)
SELECT public.demo_id('org:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       CASE WHEN v.pai IS NOT NULL THEN public.demo_id('org:' || v.pai) END,
       CASE WHEN a.id IS NOT NULL THEN a.cargo_id END,
       CASE WHEN v.depto IS NOT NULL THEN public.demo_id('depto:' || v.depto) END,
       COALESCE(v.titulo, a.cargo), COALESCE(a.nome_completo, v.ocupante), a.id, 'funcao', v.ordem,
       now() - interval '150 days', now() - interval '150 days'
FROM (VALUES
  ('dir', NULL, 'Diretor-Presidente', 'Henrique Albuquerque Brandão', NULL::int, NULL, 1),
  ('ger_ind', 'dir', 'Gerente Industrial', 'Roberto Siqueira Maia', NULL, 'Produção', 1),
  ('ger_adm', 'dir', 'Gerente Administrativa', 'Cláudia Ferraz Montenegro', NULL, 'Administrativo', 2),
  ('ger_com', 'dir', 'Gerente Comercial', 'Alexandre Brito Cavalcanti', NULL, 'Comercial', 3),
  ('l28', 'ger_ind', NULL, NULL, 28, 'Produção', 1),
  ('l29', 'ger_ind', NULL, NULL, 29, 'Produção', 2),
  ('s40', 'ger_ind', NULL, NULL, 40, 'Manutenção', 3),
  ('c52', 'ger_ind', NULL, NULL, 52, 'Logística', 4),
  ('n1', 'l28', NULL, NULL, 1, NULL, 1), ('n2', 'l28', NULL, NULL, 2, NULL, 2), ('n3', 'l28', NULL, NULL, 3, NULL, 3),
  ('n4', 'l28', NULL, NULL, 4, NULL, 4), ('n5', 'l28', NULL, NULL, 5, NULL, 5), ('n6', 'l28', NULL, NULL, 6, NULL, 6),
  ('n13', 'l29', NULL, NULL, 13, NULL, 1), ('n14', 'l29', NULL, NULL, 14, NULL, 2), ('n15', 'l29', NULL, NULL, 15, NULL, 3),
  ('n16', 'l29', NULL, NULL, 16, NULL, 4), ('n22', 'l29', NULL, NULL, 22, NULL, 5), ('n23', 'l29', NULL, NULL, 23, NULL, 6),
  ('n30', 's40', NULL, NULL, 30, NULL, 1), ('n31', 's40', NULL, NULL, 31, NULL, 2), ('n32', 's40', NULL, NULL, 32, NULL, 3),
  ('n36', 's40', NULL, NULL, 36, NULL, 4), ('n37', 's40', NULL, NULL, 37, NULL, 5),
  ('n41', 'c52', NULL, NULL, 41, NULL, 1), ('n42', 'c52', NULL, NULL, 42, NULL, 2), ('n46', 'c52', NULL, NULL, 46, NULL, 3), ('n47', 'c52', NULL, NULL, 47, NULL, 4),
  ('rh', 'ger_adm', 'Gestora de RH', 'Leiri', NULL, 'Recursos Humanos', 1),
  ('n58', 'rh', NULL, NULL, 58, NULL, 1), ('n59', 'rh', NULL, NULL, 59, NULL, 2),
  ('n53', 'ger_adm', NULL, NULL, 53, NULL, 2), ('n54', 'ger_adm', NULL, NULL, 54, NULL, 3), ('n55', 'ger_adm', NULL, NULL, 55, NULL, 4),
  ('n56', 'ger_adm', NULL, NULL, 56, NULL, 5), ('n57', 'ger_adm', NULL, NULL, 57, NULL, 6),
  ('vend', 'ger_com', 'Vendedor Interno (vaga em seleção)', NULL, NULL, 'Comercial', 1)
) AS v(chave, pai, titulo, ocupante, n, depto, ordem)
LEFT JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.n)
WHERE NOT EXISTS (SELECT 1 FROM public.estrategia_organograma o WHERE o.id = public.demo_id('org:' || v.chave));

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.funcao_atividades WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS atividades,
  (SELECT count(*) FROM public.funcao_competencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS competencias,
  (SELECT count(*) FROM public.funcao_pops WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pops,
  (SELECT count(*) FROM public.funcao_epi_vinculacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epis_vinculados,
  (SELECT count(*) FROM public.funcao_treinamento_evidencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS evidencias,
  (SELECT count(*) FROM public.manual_funcao_assinaturas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS assinaturas_manual,
  (SELECT count(*) FROM public.estrategia_swot_itens WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS swot_itens,
  (SELECT count(*) FROM public.estrategia_oceano_itens WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS oceano_itens,
  (SELECT count(*) FROM public.estrategia_organograma WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS organograma,
  (SELECT count(*) FROM public.estrategia_cultura WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS cultura,
  CASE WHEN (SELECT count(*) FROM public.estrategia_swot WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 3
        AND (SELECT count(*) FROM public.estrategia_organograma WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 30
        AND (SELECT count(*) FROM public.funcao_atividades WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 45
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
