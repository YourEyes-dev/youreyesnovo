-- =========================================================
-- QA — Configurações: primeira documentação do módulo (14 casos)
--
-- Módulo sistema/configuracoes, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/Configuracoes.tsx +
-- components/configuracoes/*: 5 abas restritas a admin (Usuários,
-- Perfis & Acessos, eSocial, Auditoria, Logo), banner de configuração
-- inicial pendente. Área administrativa sensível — toda a superfície é
-- gated por isAdmin.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'sistema/configuracoes';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo sistema/configuracoes não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'CFG-001', 'Configurações abre com as abas administrativas (admin)',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'A tela concentra a administração do tenant. Para o admin, precisa montar com as cinco abas.',
   'Usuário administrador autenticado.',
   '[{"ordem":1,"acao":"Acessar Configurações pelo menu como admin","resultado_esperado":"Título Configurações e as abas carregam"},
     {"ordem":2,"acao":"Conferir as abas","resultado_esperado":"Usuários, Perfis & Acessos, eSocial, Auditoria e Logo presentes"}]'::jsonb,
   'As cinco abas administrativas montam para o admin.',
   'Âncoras: value usuarios, perfis, esocial, auditoria, logo.'),

  (v_mod, 'CFG-002', 'Configurações é inacessível ao usuário comum',
   'negativo', 'critica', 'aprovado', 'e2e',
   'LGPD art. 37 (governança) / princípio do menor privilégio',
   'Usuários, perfis, auditoria e eSocial são poder administrativo. Colaborador comum não pode alcançar essa superfície.',
   'Conta de colaborador comum.',
   '[{"ordem":1,"acao":"Tentar abrir Configurações como colaborador comum","resultado_esperado":"Abas administrativas ausentes/acesso negado"}]'::jsonb,
   'A superfície administrativa é restrita ao admin.',
   'Todas as TabsTrigger/TabsContent gated por isAdmin.'),

  (v_mod, 'CFG-010', 'Aba Usuários lista e gerencia usuários',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (registro de operações)',
   'É onde se cria e administra quem entra no sistema. A aba deve montar a gestão de usuários.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Usuários","resultado_esperado":"Lista/gestão de usuários monta"}]'::jsonb,
   'A gestão de usuários é acessível ao admin.',
   'Componente UsuariosContent.'),

  (v_mod, 'CFG-011', 'Aba Perfis & Acessos monta a gestão de perfis',
   'feliz', 'critica', 'aprovado', 'e2e',
   'LGPD art. 6º (necessidade) / camada perfil_permite_modulo',
   'Perfis definem o que cada papel vê e faz — o coração da camada de acesso. A aba deve montar a gestão de perfis.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Perfis & Acessos","resultado_esperado":"Gestão de perfis e permissões monta"}]'::jsonb,
   'A gestão de perfis é acessível ao admin.',
   'Componente PerfisContent.'),

  (v_mod, 'CFG-012', 'Editar um perfil altera o acesso do papel',
   'feliz', 'critica', 'aprovado', 'e2e',
   'camada perfil_permite_modulo + políticas RESTRICTIVE',
   'A edição de perfil precisa persistir e valer: liberar/restringir um módulo muda o que o papel enxerga. É o teste que prova que a camada de acesso é operável pela tela.',
   'Admin; um perfil editável.',
   '[{"ordem":1,"acao":"Abrir um perfil e alterar o acesso a um módulo","resultado_esperado":"Alteração aceita"},
     {"ordem":2,"acao":"Salvar e reabrir o perfil","resultado_esperado":"A alteração persiste"}]'::jsonb,
   'A edição de perfil persiste e reflete no acesso.',
   'Sensível: mudança de perfil afeta a camada de leitura.'),

  (v_mod, 'CFG-020', 'Aba eSocial monta a configuração de integração',
   'feliz', 'alta', 'aprovado', 'e2e',
   'eSocial (obrigações trabalhistas)',
   'O eSocial é a ponte com as obrigações do governo. A aba deve montar a configuração sem erro.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba eSocial","resultado_esperado":"Configuração do eSocial monta"}]'::jsonb,
   'A configuração do eSocial é acessível ao admin.',
   'Componente EsocialConfig.'),

  (v_mod, 'CFG-030', 'Aba Auditoria mostra o histórico de operações',
   'feliz', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (registro das operações de tratamento)',
   'A auditoria é a prova de quem fez o quê. A aba deve montar o histórico para consulta.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Abrir a aba Auditoria","resultado_esperado":"Registro de auditoria monta"}]'::jsonb,
   'A auditoria é consultável pelo admin.',
   'Componente AuditoriaTab.'),

  (v_mod, 'CFG-031', 'Auditoria é somente leitura',
   'negativo', 'alta', 'aprovado', 'e2e',
   'LGPD art. 37 (integridade do registro)',
   'Registro de auditoria que se pode apagar não vale como prova. A aba não deve oferecer edição/exclusão dos eventos.',
   'Admin na aba Auditoria com eventos.',
   '[{"ordem":1,"acao":"Conferir as ações disponíveis sobre um evento de auditoria","resultado_esperado":"Apenas consulta; sem editar ou excluir registros"}]'::jsonb,
   'A auditoria preserva a integridade do histórico.', NULL),

  (v_mod, 'CFG-040', 'Aba Logo permite personalizar a marca da empresa',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'A logo aparece no sistema e em documentos. A aba deve montar o envio e a troca da imagem da empresa.',
   'Admin autenticado; imagem válida.',
   '[{"ordem":1,"acao":"Abrir a aba Logo","resultado_esperado":"Gestão da logo da empresa monta"},
     {"ordem":2,"acao":"Enviar uma imagem de logo","resultado_esperado":"Upload conclui e a logo é atualizada"}]'::jsonb,
   'A logo da empresa é personalizável.',
   'Componente EmpresaLogoTab.'),

  (v_mod, 'CFG-050', 'Banner de configuração inicial pendente aparece quando há pendência',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Tenant recém-criado precisa ser guiado a finalizar a configuração. O aviso e o atalho devem aparecer enquanto houver pendência.',
   'Tenant com configuração inicial incompleta.',
   '[{"ordem":1,"acao":"Abrir Configurações com a configuração inicial pendente","resultado_esperado":"Banner Configuração inicial pendente e ação Finalizar Configuração visíveis"}]'::jsonb,
   'O onboarding de configuração é sinalizado.',
   'Textos Configuração inicial pendente / Finalizar Configuração.'),

  (v_mod, 'CFG-051', 'Sem pendência, o banner de configuração não aparece',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'Depois de configurado, o aviso não deve poluir a tela.',
   'Tenant com configuração inicial concluída.',
   '[{"ordem":1,"acao":"Abrir Configurações com a configuração concluída","resultado_esperado":"Banner de pendência ausente"}]'::jsonb,
   'O banner some quando a configuração está completa.', NULL),

  (v_mod, 'CFG-060', 'Alternar entre as abas mantém a tela estável',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'O admin transita entre as áreas o tempo todo. A troca de abas deve montar cada conteúdo sem erro nem estado preso.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Percorrer as abas Usuários, Perfis, eSocial, Auditoria e Logo","resultado_esperado":"Cada aba monta seu conteúdo sem erro"}]'::jsonb,
   'A navegação entre abas é estável.', NULL),

  (v_mod, 'CFG-070', 'Criar usuário exige os campos essenciais',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'Usuário sem e-mail/identificação ou sem papel não entra de forma útil. A criação deve exigir os campos essenciais.',
   'Admin na aba Usuários.',
   '[{"ordem":1,"acao":"Tentar criar um usuário deixando campos essenciais em branco","resultado_esperado":"Sistema impede e aponta os campos obrigatórios"}]'::jsonb,
   'Não há criação de usuário incompleto.', NULL),

  (v_mod, 'CFG-080', 'Tela de Configurações responde em largura de celular',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O admin às vezes ajusta algo pelo celular. As abas colapsam para ícones e o conteúdo se ajusta sem estourar o layout.',
   'Admin; viewport de celular.',
   '[{"ordem":1,"acao":"Abrir Configurações em largura de celular","resultado_esperado":"Abas viram ícones e o conteúdo se ajusta sem quebra"}]'::jsonb,
   'Configurações é utilizável no celular.',
   'Rótulos das abas usam hidden sm:inline.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Configurações: antes=%, depois=% (esperado +14)', v_antes, v_depois;
END $doc$;
