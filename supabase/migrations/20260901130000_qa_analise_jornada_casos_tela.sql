-- =========================================================
-- QA — Análise de Jornada: primeira documentação do módulo (14 casos)
--
-- Módulo jornada-rotina/analise-jornada, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/AnaliseJornada.tsx +
-- components/jornada/*: 8 abas (Dashboard, Importação, Individual, Coletiva,
-- Conformidade, Alertas, Documentos, Relatórios). Motor analítico de jornada
-- que lê ponto_diario, avalia critérios da CLT, gera alertas e exporta
-- relatórios (inclui o integrado NR-1/PGR).
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/analise-jornada';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/analise-jornada não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AJOR-001', 'Tela de Análise de Jornada abre com as 8 abas',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT / NR-1',
   'O módulo cruza ponto com a lei e vira monitoramento de jornada. Se não monta, o RH/SST perde o painel de conformidade e riscos.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Análise de Jornada pelo menu","resultado_esperado":"Título Análise de Carga de Trabalho & Jornada carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Dashboard, Importação, Individual, Coletiva, Conformidade, Alertas, Documentos, Relatórios"}]'::jsonb,
   'O módulo monta com as 8 abas.', NULL),

  (v_mod, 'AJOR-010', 'Executar a análise do período',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT (art. 58, 59, 66, 71)',
   'A análise é o motor: lê o ponto do mês, calcula horas/violações/risco e gera alertas. Sem rodá-la, quase todas as abas ficam vazias.',
   'Ponto do mês em ponto_diario.',
   '[{"ordem":1,"acao":"No Dashboard, clicar em Executar Análise","resultado_esperado":"Processa (Analisando...) e conclui"},
     {"ordem":2,"acao":"Conferir o retorno","resultado_esperado":"Aviso Análise concluída: N colaboradores avaliados; KPIs e gráficos preenchem"}]'::jsonb,
   'A análise roda e alimenta o painel.', NULL),

  (v_mod, 'AJOR-011', 'Dashboard mostra os KPIs e destaca risco/não conformidade',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT',
   'Os 6 KPIs resumem a situação. Risco Alto e Não Conforme em vermelho são o chamado à ação.',
   'Uma análise executada.',
   '[{"ordem":1,"acao":"Conferir os cards","resultado_esperado":"Colaboradores, Média h/dia, Total HE, Alertas, Risco Alto, Não Conforme"},
     {"ordem":2,"acao":"Conferir com risco/não conformidade > 0","resultado_esperado":"Cards correspondentes destacados em vermelho"}]'::jsonb,
   'Os indicadores refletem a análise e destacam o crítico.', NULL),

  (v_mod, 'AJOR-020', 'Estados vazios orientam a rodar a análise primeiro',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem análise, Individual/Coletiva/Conformidade não têm dados. Devem orientar a rodar a análise, não quebrar.',
   'Nenhuma análise executada.',
   '[{"ordem":1,"acao":"Abrir Individual, Coletiva e Conformidade sem análise","resultado_esperado":"Cada aba mostra Execute a análise no Dashboard primeiro; sem erro"}]'::jsonb,
   'Os vazios pré-análise são tratados.', NULL),

  (v_mod, 'AJOR-030', 'Importar arquivo de ponto pelo assistente',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A importação traz o ponto de fora (CSV/Excel) para a base. É o que alimenta a análise quando o ponto não é nativo.',
   'Arquivo CSV/Excel de jornada (até 20MB).',
   '[{"ordem":1,"acao":"Enviar o arquivo (Upload)","resultado_esperado":"Planilha lida; passo Mapeamento abre"},
     {"ordem":2,"acao":"Mapear ao menos Nome e Data, pré-visualizar e importar","resultado_esperado":"Passo Resultado mostra novos/atualizados/erros"}]'::jsonb,
   'A importação percorre os 4 passos e grava o ponto.',
   'Assistente Upload → Mapeamento → Preview → Resultado.'),

  (v_mod, 'AJOR-031', 'Importação bloqueia sem mapear Nome e Data',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Sem Nome e Data não há registro de ponto válido. O preview deve exigir esses dois campos.',
   'Arquivo carregado, no passo Mapeamento.',
   '[{"ordem":1,"acao":"Tentar pré-visualizar sem mapear Nome e Data","resultado_esperado":"Aviso Mapeie pelo menos Nome e Data; não avança"}]'::jsonb,
   'O mapeamento mínimo é exigido.', NULL),

  (v_mod, 'AJOR-032', 'Importação recusa arquivo inválido (tipo/tamanho/vazio)',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Arquivo do tipo errado, grande demais ou vazio não pode entrar. A tela deve recusar com aviso.',
   'Passo Upload.',
   '[{"ordem":1,"acao":"Tentar enviar um arquivo não CSV/Excel, acima de 20MB, ou vazio","resultado_esperado":"Recusa com aviso claro (ex.: Arquivo vazio ou sem dados)"}]'::jsonb,
   'Arquivos inválidos são recusados.', NULL),

  (v_mod, 'AJOR-040', 'Análise Individual abre a jornada de um colaborador',
   'feliz', 'alta', 'aprovado', 'e2e', 'CLT',
   'É o detalhe por pessoa: média diária, HE, atrasos, violações e o gráfico da jornada. Base para conversas e ações.',
   'Análise executada.',
   '[{"ordem":1,"acao":"Buscar e selecionar um colaborador","resultado_esperado":"Painel com risco, conformidade, métricas e o gráfico Jornada Diária"}]'::jsonb,
   'A visão individual monta com os indicadores da pessoa.',
   'Colaborador afastado exibe o selo de afastamento.'),

  (v_mod, 'AJOR-050', 'Conformidade avalia pelos parâmetros da CLT',
   'feliz', 'critica', 'aprovado', 'e2e', 'CLT (art. 58, 59, 66, 67, 71)',
   'A aba Conformidade traduz a jornada em cumprimento da lei. Os parâmetros padrão (8/44/2/60/11/24) são o alicerce do cálculo de violações.',
   'Análise executada.',
   '[{"ordem":1,"acao":"Abrir Conformidade e Parâmetros","resultado_esperado":"Padrão CLT: 8 diária, 44 semanal, 2 HE, 60 intervalo, 11 interjornada, 24 semanal"},
     {"ordem":2,"acao":"Conferir o detalhamento de violações","resultado_esperado":"Intervalo, interjornada (11h), jornada excedida, HE excedida, DSR e o total"}]'::jsonb,
   'A conformidade reflete os limites da CLT.', NULL),

  (v_mod, 'AJOR-051', 'Salvar parâmetros de conformidade',
   'feliz', 'media', 'aprovado', 'e2e', 'CLT',
   'Cada empresa pode ajustar os limites (acordo coletivo, etc.). Salvar deve persistir o perfil que rege a próxima análise.',
   'Aba Conformidade, painel Parâmetros aberto.',
   '[{"ordem":1,"acao":"Ajustar um limite e Salvar Parâmetros","resultado_esperado":"Aviso Parâmetros salvos com sucesso"}]'::jsonb,
   'Os parâmetros de conformidade persistem.', NULL),

  (v_mod, 'AJOR-060', 'Triagem de alertas: filtrar e resolver',
   'feliz', 'alta', 'aprovado', 'e2e', 'NR-1 (gestão de riscos)',
   'Os alertas apontam onde a jornada saiu do trilho. Filtrar por tipo/status e marcar como resolvido é o fluxo de tratativa.',
   'Análise executada com alertas.',
   '[{"ordem":1,"acao":"Filtrar por tipo e status na aba Alertas","resultado_esperado":"A lista restringe conforme o filtro"},
     {"ordem":2,"acao":"Marcar um alerta como Resolver","resultado_esperado":"Aviso Alerta marcado como resolvido; vira ✓ Resolvido"}]'::jsonb,
   'Os alertas são filtráveis e resolvíveis.', NULL),

  (v_mod, 'AJOR-070', 'Anexar documento de apoio (PDF) para auditoria',
   'alternativo', 'media', 'aprovado', 'e2e', 'NR-1 / auditoria',
   'Documentos (espelho de ponto, acordo, convenção) são a evidência para auditoria/NR-1. Enviar deve armazenar e vincular por tipo/período.',
   'Aba Documentos; PDF válido (até 20MB).',
   '[{"ordem":1,"acao":"Enviar Documento com nome e tipo","resultado_esperado":"Aviso Documento enviado com sucesso; aparece na lista"}]'::jsonb,
   'O documento de apoio é anexado.', NULL),

  (v_mod, 'AJOR-080', 'Exportar relatório é gated pelo perfil de acesso',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal e de saúde)',
   'O relatório tira dados pessoais e de saúde do sistema — é a ação de maior exposição. Deve seguir a permissão de exportar do perfil.',
   'Perfis com e sem permissão de exportar (módulo colaboradores).',
   '[{"ordem":1,"acao":"Abrir Relatórios com perfil sem permissão de exportar","resultado_esperado":"Botão de exportar desabilitado com aviso Seu perfil de acesso não permite exportar relatórios de jornada."},
     {"ordem":2,"acao":"Com perfil autorizado, exportar (Excel/PDF)","resultado_esperado":"Relatório gerado (ex.: integrado NR-1/PGR)"}]'::jsonb,
   'A exportação respeita a permissão do perfil.',
   'AcaoProtegida modulo=colaboradores acao=exportar.'),

  (v_mod, 'AJOR-081', 'Exportar sem análise avisa e não gera',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Sem análise não há o que exportar. A tela deve avisar em vez de gerar um relatório vazio.',
   'Nenhuma análise executada.',
   '[{"ordem":1,"acao":"Tentar exportar em Relatórios sem análise","resultado_esperado":"Aviso Nenhuma análise disponível. Execute a análise no Dashboard primeiro."}]'::jsonb,
   'A exportação sem dados é barrada com orientação.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Análise de Jornada: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;
