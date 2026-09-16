-- =========================================================
-- QA — Onboarding (RH): primeira documentação do módulo (13 casos)
--
-- Módulo pessoas-cultura/onboarding, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Onboarding.tsx (rota
-- /onboarding-rh, "Onboarding Gamificado") + components/onboarding/*: abas
-- Processos / Indicadores / Templates; construção de templates (trilhas) com
-- etapas gamificadas, acompanhamento dos processos e indicadores.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'pessoas-cultura/onboarding';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo pessoas-cultura/onboarding não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'ONB-001', 'Onboarding Gamificado abre com as três abas',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'É o console de RH do onboarding: templates, processos e indicadores. Se não monta, o RH perde a gestão da integração de novos colaboradores.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Acessar Onboarding pelo menu","resultado_esperado":"Título Onboarding Gamificado carrega"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Processos, Indicadores, Templates"}]'::jsonb,
   'A tela monta com as três abas.', NULL),

  (v_mod, 'ONB-010', 'Criar um template de onboarding',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'O template é a trilha reutilizável de integração. Sem criar template não há onboarding para atribuir.',
   'Aba Templates; perfil com permissão.',
   '[{"ordem":1,"acao":"Clicar em Novo Template","resultado_esperado":"Modal Novo Template de Onboarding abre"},
     {"ordem":2,"acao":"Informar o Nome e salvar","resultado_esperado":"Aviso Template criado!; template aparece na lista"}]'::jsonb,
   'O template é criado e listado.',
   'Só o Nome é obrigatório; demais campos têm padrão.'),

  (v_mod, 'ONB-011', 'Não criar template sem nome',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Template sem nome não se identifica. O botão de criar deve ficar desabilitado sem o nome.',
   'Modal Novo Template aberto.',
   '[{"ordem":1,"acao":"Deixar o Nome vazio","resultado_esperado":"O botão Criar Template fica desabilitado"}]'::jsonb,
   'Template sem nome não é criado.', NULL),

  (v_mod, 'ONB-012', 'Editar um template e persistir',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Ajustar prazo, certificado, PDI e abrangência mantém a trilha atualizada. A edição deve persistir.',
   'Um template criado.',
   '[{"ordem":1,"acao":"Abrir a edição do template, alterar um campo e salvar","resultado_esperado":"Aviso Template atualizado!; a alteração permanece"}]'::jsonb,
   'A edição de template persiste.', NULL),

  (v_mod, 'ONB-013', 'Ativar/inativar um template',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Só templates ativos entram no fluxo. O botão de ativação alterna o estado imediatamente.',
   'Um template na lista.',
   '[{"ordem":1,"acao":"Alternar o estado ativo do template","resultado_esperado":"O selo Ativo/Inativo reflete a mudança"}]'::jsonb,
   'A ativação do template funciona.', NULL),

  (v_mod, 'ONB-020', 'Adicionar uma etapa à trilha do template',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'As etapas são o corpo da trilha (apresentação, cultura, quiz, reflexão...). Montar etapas é o que dá conteúdo ao onboarding.',
   'Um template aberto (Detalhe).',
   '[{"ordem":1,"acao":"Clicar em Adicionar Etapa","resultado_esperado":"Modal Nova Etapa abre"},
     {"ordem":2,"acao":"Informar o Título, tipo e salvar","resultado_esperado":"Aviso Etapa adicionada!; etapa numerada na trilha"}]'::jsonb,
   'A etapa é adicionada à trilha.',
   'Título obrigatório; campos condicionais por tipo/formato (ex.: URL para vídeo).'),

  (v_mod, 'ONB-021', 'Não adicionar etapa sem título',
   'negativo', 'media', 'aprovado', 'e2e', NULL,
   'Etapa sem título não se identifica na trilha. O adicionar deve exigir o título.',
   'Modal Nova Etapa aberto.',
   '[{"ordem":1,"acao":"Deixar o Título vazio","resultado_esperado":"O botão Adicionar Etapa fica desabilitado"}]'::jsonb,
   'Etapa sem título não é adicionada.', NULL),

  (v_mod, 'ONB-030', 'Excluir template e etapa com confirmação',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Remover template/etapa é destrutivo. Deve pedir confirmação antes de apagar.',
   'Um template com etapa.',
   '[{"ordem":1,"acao":"Remover uma etapa e confirmar","resultado_esperado":"Confirmação Remover etapa; após confirmar, some da trilha"},
     {"ordem":2,"acao":"Remover o template e confirmar","resultado_esperado":"Confirmação Remover template; após confirmar, some da lista"}]'::jsonb,
   'A exclusão pede confirmação e efetiva.', NULL),

  (v_mod, 'ONB-040', 'Processos mostram o andamento de cada novo colaborador',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado de novo colaborador)',
   'A aba Processos é o acompanhamento: quem está pendente, em andamento, concluído, com progresso e pontos.',
   'Aba Processos.',
   '[{"ordem":1,"acao":"Abrir a aba Processos","resultado_esperado":"Cards Total/Pendentes/Em andamento/Concluídos e a lista com progresso e status"}]'::jsonb,
   'O acompanhamento dos processos monta.', NULL),

  (v_mod, 'ONB-050', 'Indicadores consolidam conclusão e percepção cultural',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Os indicadores dizem se o onboarding engaja: taxa de conclusão, tempo médio e as respostas de percepção cultural agregadas.',
   'Aba Indicadores.',
   '[{"ordem":1,"acao":"Abrir Indicadores","resultado_esperado":"KPIs (Total, Taxa Conclusão, Tempo Médio, Em Andamento, Respostas Culturais) montam"},
     {"ordem":2,"acao":"Filtrar a Percepção Cultural por categoria","resultado_esperado":"As respostas filtram; vazio mostra a orientação"}]'::jsonb,
   'Os indicadores de onboarding montam com filtro de percepção.', NULL),

  (v_mod, 'ONB-051', 'Estados vazios de templates, etapas e percepção orientam',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Empresa nova abre tudo vazio. Cada área deve orientar a começar, não exibir erro.',
   'Ambiente sem templates/etapas/respostas.',
   '[{"ordem":1,"acao":"Abrir Templates sem templates","resultado_esperado":"Nenhum template de onboarding + Criar Primeiro Template"},
     {"ordem":2,"acao":"Abrir um template sem etapas e a percepção sem respostas","resultado_esperado":"Mensagens orientativas; sem erro"}]'::jsonb,
   'Os vazios são tratados com orientação.', NULL),

  (v_mod, 'ONB-060', 'Abrangência vazia significa aplicar a todos',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Deixar funções/departamentos/vínculos em branco faz o template valer para todos — regra que precisa ficar visível.',
   'Modal de template.',
   '[{"ordem":1,"acao":"Salvar um template sem escolher funções/departamentos","resultado_esperado":"O card indica Aplica a todos os colaboradores"}]'::jsonb,
   'A abrangência vazia é interpretada como todos.', NULL),

  (v_mod, 'ONB-070', 'Processos isolados por empresa/tenant',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º',
   'Processos trazem nome e CPF de novos colaboradores. A lista não pode misturar outra empresa/tenant.',
   'Base com processos de mais de um tenant.',
   '[{"ordem":1,"acao":"Abrir Processos autenticado num tenant","resultado_esperado":"Só aparecem processos do tenant do usuário"}]'::jsonb,
   'O escopo por tenant é respeitado.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Onboarding (RH): antes=%, depois=% (esperado +13)', v_antes, v_depois;
END $doc$;
