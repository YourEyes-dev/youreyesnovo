-- =========================================================
-- SCRIPT DE ENTREGA — Documentacao de Testes:
-- Usuarios, Niveis de Acesso, Liberacoes e Permissoes
--
-- Onde colar: SQL Editor do projeto (homologacao primeiro; producao
-- so depois do aceite). Roda o arquivo INTEIRO de uma vez.
--
-- O que faz: cria o modulo "Usuarios & Permissoes" dentro do bloco
-- Infraestrutura & Auth da Documentacao de Testes e cadastra 59 casos
-- (USR, VIN, NAC, PER, LIB, CTX, ISOL, PRIV, SES).
--
-- O que NAO faz: nao cria, nao altera e nao remove NENHUMA regra de
-- acesso, politica, perfil, permissao ou vinculo. E documentacao pura:
-- so INSERT em qa_modulos e qa_casos_teste. Por isso nao ha copia de
-- seguranca aqui — o script nao toca em dado existente.
--
-- Idempotente: rodar duas vezes nao duplica nada (ON CONFLICT pelo
-- codigo do caso e pelo caminho do modulo).
--
-- Erros por item nao abortam o resto: cada bloco avisa e segue.
-- Termina com UMA conferencia; o editor mostra so o ultimo resultado.
-- =========================================================

SET lock_timeout = '10s';

DO $entrega$
DECLARE v_sec uuid; v_mod uuid; v_antes int; v_depois int;
BEGIN
  -- 1) Bloco pai (ja existe em todos os ambientes; criado aqui por seguranca)
  SELECT id INTO v_sec FROM public.qa_modulos WHERE path = 'infraestrutura-auth';
  IF v_sec IS NULL THEN
    INSERT INTO public.qa_modulos (label, path, icone, ordem)
    VALUES ('Infraestrutura & Auth', 'infraestrutura-auth', 'ferramenta', 12)
    RETURNING id INTO v_sec;
    RAISE NOTICE 'Bloco Infraestrutura & Auth nao existia e foi criado.';
  END IF;

  -- 2) Modulo novo
  INSERT INTO public.qa_modulos (parent_id, label, path, ordem, prioridade_doc, status_doc)
  VALUES (v_sec, 'Usuarios & Permissoes', 'infraestrutura-auth/usuarios-permissoes', 4, 2, 'documentado')
  ON CONFLICT (path) DO UPDATE
    SET label = EXCLUDED.label, status_doc = 'documentado', motivo_bloqueio = NULL;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/usuarios-permissoes';
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  -- 3) Os 59 casos
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════════════════════════════════════════════════
  -- USR — Ciclo de vida do usuario
  -- ══════════════════════════════════════════════════════
  (v_mod, 'USR-001', 'Convidar usuario com dados validos cria o cadastro pendente',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'O convite e a porta de entrada. Precisa criar o usuario ja vinculado a UMA empresa, com nivel definido e SEM acesso antes da ativacao.',
   'Admin autenticado na Empresa A.',
   '[{"ordem":1,"acao":"Admin cria usuario com nome, e-mail valido e vinculo a Empresa A no nivel Colaborador","resultado_esperado":"Registro criado em usuarios_base com status pendente_convite e token de convite gerado"},
     {"ordem":2,"acao":"Conferir os vinculos do usuario criado","resultado_esperado":"Exatamente um vinculo em usuario_perfil_vinculos, para a Empresa A, com o perfil Colaborador"},
     {"ordem":3,"acao":"Simular o usuario antes de ativar","resultado_esperado":"Nenhum dado de negocio e devolvido: convite nao e acesso"}]'::jsonb,
   'Usuario criado como pendente, vinculado apenas a Empresa A, sem nenhum acesso liberado antes da ativacao.',
   'Documento de origem: USR-001.'),

  (v_mod, 'USR-002', 'Ativar a conta pelo convite e entrar com o escopo do vinculo',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Jornada critica ponta a ponta: aceitar o convite, definir senha e entrar vendo SOMENTE o que o nivel permite.',
   'Usuario com convite valido e nao expirado na Empresa A, nivel Colaborador.',
   '[{"ordem":1,"acao":"Abrir o link do convite","resultado_esperado":"A tela de definicao de senha carrega"},
     {"ordem":2,"acao":"Definir a senha e concluir","resultado_esperado":"O status do usuario passa a ativo"},
     {"ordem":3,"acao":"Fazer o primeiro login","resultado_esperado":"O menu mostra apenas os modulos do nivel Colaborador da Empresa A; nenhuma area de administracao aparece"}]'::jsonb,
   'Conta ativada e primeiro acesso com o escopo exato do nivel Colaborador da Empresa A.',
   'Documento de origem: USR-002.'),

  (v_mod, 'USR-003', 'E-mail duplicado no mesmo escopo e recusado',
   'excecao', 'alta', 'aprovado', 'api', NULL,
   'E-mail e identidade. Criar duplicado quebra o modelo e abre porta para dois cadastros com permissoes divergentes.',
   'Usuario ja cadastrado com o e-mail alvo.',
   '[{"ordem":1,"acao":"Tentar criar outro usuario com o mesmo e-mail","resultado_esperado":"Recusado com mensagem clara; nenhum registro novo"},
     {"ordem":2,"acao":"Conferir a contagem de usuarios com aquele e-mail","resultado_esperado":"Continua um so"}]'::jsonb,
   'Cadastro duplicado recusado; o caminho correto e vincular o usuario existente a nova empresa (VIN-003).',
   'Documento de origem: USR-003. Lacuna a decidir: se o e-mail e identidade global, a tela deve OFERECER o vinculo em vez de so recusar.'),

  (v_mod, 'USR-004', 'E-mail em formato invalido nao chega a persistir',
   'excecao', 'media', 'aprovado', 'api', NULL,
   'Validacao antes da escrita: e-mail malformado vira convite que nunca chega e usuario orfao na base.',
   'Admin autenticado.',
   '[{"ordem":1,"acao":"Submeter um e-mail malformado","resultado_esperado":"A validacao barra antes de gravar"},
     {"ordem":2,"acao":"Conferir a base","resultado_esperado":"Nenhum registro criado"}]'::jsonb,
   'E-mail invalido barrado na validacao, sem registro criado.',
   'Documento de origem: USR-004.'),

  (v_mod, 'USR-005', 'Desativar usuario encerra o acesso e preserva o historico',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Desativacao nao pode apagar historico (auditoria e LGPD pedem rastro), mas tem que cortar o acesso.',
   'Usuario ativo com registros no sistema.',
   '[{"ordem":1,"acao":"Admin desativa o usuario","resultado_esperado":"Status passa a inativo"},
     {"ordem":2,"acao":"Simular o usuario inativo em leitura e escrita","resultado_esperado":"Nada e lido nem gravado"},
     {"ordem":3,"acao":"Conferir os registros que ele gerou","resultado_esperado":"Preservados: o registro do usuario nao foi apagado"}]'::jsonb,
   'Usuario inativo perde o acesso, com o registro e o historico preservados.',
   'Documento de origem: USR-005.'),

  (v_mod, 'USR-006', 'Usuario desativado nao autentica',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Se o inativo ainda entra, a desativacao e teatro. Cruza com SES-003 (sessao ja aberta).',
   'Usuario com status inativo.',
   '[{"ordem":1,"acao":"Tentar autenticar com as credenciais do usuario inativo","resultado_esperado":"Login negado"},
     {"ordem":2,"acao":"Conferir sessao anterior porventura ativa","resultado_esperado":"Invalidada: nenhuma acao passa"}]'::jsonb,
   'Login negado e sessao anterior invalidada.',
   'Documento de origem: USR-006.'),

  (v_mod, 'USR-007', 'Reativar usuario devolve exatamente os vinculos anteriores',
   'alternativo', 'media', 'aprovado', 'api', NULL,
   'Reativacao e o ponto onde permissao antiga volta em silencio (ou some sem aviso). O comportamento precisa ser o definido, nao o acidental.',
   'Usuario previamente inativado, com vinculos conhecidos.',
   '[{"ordem":1,"acao":"Registrar os vinculos e niveis antes de reativar","resultado_esperado":"Lista de referencia guardada"},
     {"ordem":2,"acao":"Reativar o usuario","resultado_esperado":"Status volta a ativo"},
     {"ordem":3,"acao":"Comparar os vinculos e niveis com a referencia","resultado_esperado":"Iguais aos anteriores, sem vinculo a mais nem permissao herdada de fora"}]'::jsonb,
   'Reativacao devolve o mesmo escopo de antes, sem ganho nem perda silenciosa.',
   'Documento de origem: USR-007. Lacuna a decidir com o time: herdar ou zerar as permissoes na reativacao.'),

  (v_mod, 'USR-008', 'Excluir usuario com historico e bloqueado ou vira anonimizacao',
   'excecao', 'alta', 'aprovado', 'api', 'LGPD art. 16 (guarda) e art. 18 (eliminacao)',
   'Excluir quem ja gerou registro quebra integridade referencial e apaga rastro de auditoria.',
   'Usuario com acoes e documentos ja gerados.',
   '[{"ordem":1,"acao":"Tentar excluir o usuario","resultado_esperado":"Exclusao bloqueada, ou substituida por anonimizacao/inativacao"},
     {"ordem":2,"acao":"Conferir os registros dependentes","resultado_esperado":"Integridade referencial preservada; nenhum orfao"}]'::jsonb,
   'Exclusao impedida ou convertida em anonimizacao, com integridade preservada.',
   'Documento de origem: USR-008. Lacuna a decidir: politica de exclusao x anonimizacao.'),

  -- ══════════════════════════════════════════════════════
  -- VIN — Vinculo usuario x empresa (N:N, multi-empresa)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'VIN-001', 'Vincular usuario a uma empresa com nivel definido',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Base do modelo: todo acesso nasce de um vinculo (usuario, empresa, perfil).',
   'Usuario e empresa existentes no mesmo tenant.',
   '[{"ordem":1,"acao":"Admin da Empresa A vincula o usuario e atribui o nivel","resultado_esperado":"Vinculo criado em usuario_perfil_vinculos, ativo"},
     {"ordem":2,"acao":"Conferir o vinculo","resultado_esperado":"Usuario, empresa e perfil corretos"}]'::jsonb,
   'Vinculo criado e ativo, com o nivel atribuido.',
   'Documento de origem: VIN-001.'),

  (v_mod, 'VIN-002', 'Usuario vinculado a mais de uma empresa, com niveis distintos',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Coracao do requisito: um usuario pode servir a varias empresas, com nivel diferente em cada uma.',
   'Usuario ja vinculado a Empresa A.',
   '[{"ordem":1,"acao":"Vincular o mesmo usuario a Empresa B com outro nivel","resultado_esperado":"Dois vinculos independentes coexistem"},
     {"ordem":2,"acao":"Listar as empresas que o usuario enxerga","resultado_esperado":"Somente A e B; nenhuma outra empresa aparece"}]'::jsonb,
   'Dois vinculos independentes, e a lista de empresas do usuario e exatamente A e B.',
   'Documento de origem: VIN-002.'),

  (v_mod, 'VIN-003', 'Vincular usuario existente por e-mail a uma nova empresa',
   'alternativo', 'alta', 'aprovado', 'api', NULL,
   'O caminho correto quando o e-mail ja existe: novo VINCULO, nunca novo usuario. E o admin de B nao pode enxergar a vida do usuario em A.',
   'Usuario cadastrado e vinculado a Empresa A.',
   '[{"ordem":1,"acao":"Admin da Empresa B adiciona o usuario informando o e-mail ja cadastrado","resultado_esperado":"Cria-se um novo vinculo; a contagem de usuarios nao muda"},
     {"ordem":2,"acao":"Admin de B consulta os dados do usuario","resultado_esperado":"Ve os dados basicos de identificacao; o historico e os registros do usuario na Empresa A permanecem invisiveis"}]'::jsonb,
   'Novo vinculo criado sem duplicar o usuario, e o historico da Empresa A segue isolado do admin de B.',
   'Documento de origem: VIN-003.'),

  (v_mod, 'VIN-004', 'Remover o vinculo de uma empresa corta so aquele acesso',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Remocao de vinculo e o gesto de revogacao mais comum. Tem que ser cirurgica: corta A, preserva B.',
   'Usuario vinculado a A e a B.',
   '[{"ordem":1,"acao":"Remover o vinculo com a Empresa A","resultado_esperado":"O vinculo com A deixa de valer"},
     {"ordem":2,"acao":"Simular o usuario contra dados da Empresa A","resultado_esperado":"Nenhum acesso: leitura e escrita negadas"},
     {"ordem":3,"acao":"Simular o usuario contra dados da Empresa B","resultado_esperado":"Acesso intacto, no nivel de B"}]'::jsonb,
   'Acesso a A cessa imediatamente e o acesso a B permanece intacto.',
   'Documento de origem: VIN-004. O efeito em sessao ja aberta e provado em SES-002.'),

  (v_mod, 'VIN-005', 'Nivel diferente por empresa e respeitado',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Prova a premissa P1: o nivel e por vinculo, nao global. Se for global, este caso falha e revela o defeito.',
   'Usuario com nivel Admin na Empresa A e Colaborador na Empresa B.',
   '[{"ordem":1,"acao":"No contexto da Empresa A, executar acao exclusiva de Admin","resultado_esperado":"Permitido"},
     {"ordem":2,"acao":"No contexto da Empresa B, tentar a mesma acao","resultado_esperado":"Negado"}]'::jsonb,
   'A mesma acao e permitida em A e negada em B: o nivel acompanha o vinculo.',
   'Documento de origem: VIN-005. Prova a premissa P1.'),

  (v_mod, 'VIN-006', 'Permissao de uma empresa nao vaza para a outra',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Prova que o enforcement usa o CONTEXTO ATIVO, e nao a uniao dos vinculos do usuario. A uniao seria um vazamento silencioso.',
   'Usuario vinculado a A (Admin) e a B (Colaborador), com contexto ativo em B.',
   '[{"ordem":1,"acao":"Com contexto ativo em B, tentar LER um registro informando o id da Empresa A","resultado_esperado":"Zero linhas"},
     {"ordem":2,"acao":"Com contexto ativo em B, tentar ALTERAR um registro da Empresa A","resultado_esperado":"Zero linhas afetadas"}]'::jsonb,
   'Negado nos dois verbos, mesmo o usuario tendo vinculo com A: vale o contexto ativo.',
   'Documento de origem: VIN-006.'),

  (v_mod, 'VIN-007', 'Remover o ultimo vinculo deixa o usuario em estado seguro',
   'excecao', 'media', 'aprovado', 'api', NULL,
   'Usuario sem nenhum vinculo e a hora classica do fail-open: sem empresa, alguma rotina pode concluir "sem restricao".',
   'Usuario com um unico vinculo restante.',
   '[{"ordem":1,"acao":"Remover o unico vinculo","resultado_esperado":"O usuario fica sem empresa ou e inativado, conforme a regra definida"},
     {"ordem":2,"acao":"Simular o usuario sem vinculo em leitura e escrita","resultado_esperado":"Nada e liberado: sem vinculo nao ha acesso"}]'::jsonb,
   'Estado final definido e seguro; sem vinculo, nenhum acesso e concedido.',
   'Documento de origem: VIN-007.'),

  (v_mod, 'VIN-008', 'Vinculo duplicado do mesmo usuario na mesma empresa e recusado',
   'excecao', 'media', 'aprovado', 'api', NULL,
   'Vinculo duplicado gera decisao ambigua de nivel: dois vinculos, dois perfis, qual vale?',
   'Usuario ja vinculado a Empresa A.',
   '[{"ordem":1,"acao":"Tentar criar um segundo vinculo do usuario com a Empresa A","resultado_esperado":"Recusado por restricao de unicidade"},
     {"ordem":2,"acao":"Contar os vinculos do par usuario e empresa","resultado_esperado":"Continua um so"}]'::jsonb,
   'Nenhum vinculo duplicado; a unicidade e garantida pelo banco, nao pela tela.',
   'Documento de origem: VIN-008. Se a restricao nao existir no banco, este caso acusa a lacuna.'),

  -- ══════════════════════════════════════════════════════
  -- NAC — Niveis de acesso (perfis)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'NAC-001', 'Criar nivel de acesso com um conjunto de permissoes',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'O perfil e o contrato de acesso. Criar um perfil com permissoes tem que deixa-lo utilizavel na atribuicao.',
   'Admin autenticado no tenant.',
   '[{"ordem":1,"acao":"Criar o perfil Gestor de SST com um conjunto de permissoes","resultado_esperado":"Perfil criado em perfis_acesso, ativo"},
     {"ordem":2,"acao":"Conferir as permissoes associadas","resultado_esperado":"As linhas de perfil_permissoes existem com modulo, acao e escopo definidos"},
     {"ordem":3,"acao":"Listar os perfis disponiveis para atribuicao","resultado_esperado":"O novo perfil aparece"}]'::jsonb,
   'Perfil criado com as permissoes e disponivel para atribuicao.',
   'Documento de origem: NAC-001.'),

  (v_mod, 'NAC-002', 'Perfil e permissao vivem em tabela, nao fixados em codigo',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Caca a classe de bug "regra de acesso fixada em codigo": regra em codigo nao se audita, nao se ajusta por cliente e escapa da revisao.',
   'Somente leitura: auditoria de estrutura.',
   '[{"ordem":1,"acao":"Conferir a origem dos perfis e das permissoes","resultado_esperado":"Residem em perfis_acesso e perfil_permissoes, parametrizados por tenant"},
     {"ordem":2,"acao":"Auditar as funcoes de decisao de acesso procurando nomes de perfil escritos no corpo","resultado_esperado":"Nenhuma regra de acesso decidida por nome de perfil embutido no codigo"}]'::jsonb,
   'Perfis e permissoes sao parametro de tabela; nenhuma regra de acesso presa no codigo.',
   'Documento de origem: NAC-002. Auditoria estrutural, roda sem fixture.'),

  (v_mod, 'NAC-003', 'Editar as permissoes do perfil reflete em quem o possui',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Perfil e o ponto de alavanca: tirar uma permissao dele tem que tirar de todos os vinculados, e no prazo definido.',
   'Perfil com ao menos um usuario vinculado.',
   '[{"ordem":1,"acao":"Remover uma permissao do perfil","resultado_esperado":"A linha correspondente sai de perfil_permissoes"},
     {"ordem":2,"acao":"Simular um usuario que possui o perfil e tentar a acao removida","resultado_esperado":"Negado na proxima checagem"}]'::jsonb,
   'A permissao removida deixa de valer para todos os vinculados ao perfil.',
   'Documento de origem: NAC-003. A latencia (imediata ou no proximo login) cruza com a familia SES.'),

  (v_mod, 'NAC-004', 'Excluir perfil em uso e bloqueado ou exige reatribuicao',
   'excecao', 'alta', 'aprovado', 'api', NULL,
   'Usuario orfao de perfil e o pior dos mundos: pode virar negacao total sem aviso, ou pior, liberacao por ausencia de regra.',
   'Perfil atribuido a usuarios ativos.',
   '[{"ordem":1,"acao":"Tentar excluir o perfil em uso","resultado_esperado":"Bloqueado, ou exigida a reatribuicao dos vinculados"},
     {"ordem":2,"acao":"Conferir os vinculos que apontavam para o perfil","resultado_esperado":"Nenhum usuario ficou sem perfil"}]'::jsonb,
   'Nenhum usuario fica orfao de perfil.',
   'Documento de origem: NAC-004.'),

  (v_mod, 'NAC-005', 'Perfil de um tenant nao aparece nem se edita no outro',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Perfil e configuracao de cliente. Vazar perfil entre tenants vaza a propria estrutura de acesso do cliente.',
   'Perfil personalizado criado no tenant A.',
   '[{"ordem":1,"acao":"Com contexto do tenant B, listar os perfis","resultado_esperado":"O perfil personalizado de A nao aparece"},
     {"ordem":2,"acao":"Com contexto do tenant B, tentar alterar o perfil de A pelo id","resultado_esperado":"Zero linhas afetadas"},
     {"ordem":3,"acao":"Conferir os perfis de catalogo padrao","resultado_esperado":"Visiveis como modelo, nao editaveis pelo tenant"}]'::jsonb,
   'Perfis personalizados ficam isolados por tenant e o catalogo padrao e somente leitura para o cliente.',
   'Documento de origem: NAC-005.'),

  (v_mod, 'NAC-006', 'Ninguem atribui perfil acima do proprio teto',
   'alternativo', 'alta', 'aprovado', 'api', NULL,
   'Hierarquia: se o admin de empresa pode conceder o que nao tem, a escalada de privilegio e so um clique.',
   'Admin de empresa autenticado.',
   '[{"ordem":1,"acao":"Admin de empresa tenta criar ou atribuir um perfil de escopo superior ao seu","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir os vinculos apos a tentativa","resultado_esperado":"Nenhum vinculo criado"}]'::jsonb,
   'Concessao acima do proprio teto e negada.',
   'Documento de origem: NAC-006. Cruza com PRIV-002 e LIB-005.'),

  -- ══════════════════════════════════════════════════════
  -- PER — Permissoes (aplicacao efetiva)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'PER-001', 'Acao permitida pelo perfil e executada e persiste',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Lado positivo do enforcement: seguranca que bloqueia tudo tambem esta errada.',
   'Usuario com a permissao X no perfil.',
   '[{"ordem":1,"acao":"Executar a acao X","resultado_esperado":"Concluida sem erro"},
     {"ordem":2,"acao":"Reconsultar o dado","resultado_esperado":"A alteracao esta persistida"}]'::jsonb,
   'A acao permitida e executada e o efeito persiste.',
   'Documento de origem: PER-001.'),

  (v_mod, 'PER-002', 'Acao sem permissao e barrada no backend, mesmo sem passar pela tela',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Prova a premissa P6: a decisao de acesso mora no banco, nao na tela. Chamada direta e o teste de verdade.',
   'Usuario cujo perfil NAO tem a permissao X.',
   '[{"ordem":1,"acao":"Chamar diretamente a rotina da acao X, ignorando a tela","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir o dado alvo","resultado_esperado":"Inalterado"}]'::jsonb,
   'Chamada direta negada e dado intacto: o botao escondido nao e a defesa.',
   'Documento de origem: PER-002.'),

  (v_mod, 'PER-003', 'Botao oculto na tela e acao recusada no backend, ao mesmo tempo',
   'excecao', 'critica', 'aprovado', 'e2e', NULL,
   'Dupla defesa. Se a tela esconde mas o backend aceita, o defeito e critico e invisivel para quem so olha a tela.',
   'Usuario sem a permissao X, autenticado na tela.',
   '[{"ordem":1,"acao":"Abrir a tela do recurso X","resultado_esperado":"O controle da acao X nao aparece para este usuario"},
     {"ordem":2,"acao":"Forcar a chamada da acao X por fora da tela","resultado_esperado":"O backend recusa"}]'::jsonb,
   'Tela oculta o controle E o backend recusa a chamada forcada.',
   'Documento de origem: PER-003. A metade de banco e provada por PER-002.'),

  (v_mod, 'PER-004', 'Ausencia de permissao significa negado (fail-closed)',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Prova a premissa P2. Caca a classe de bug "nulo que propaga": ausencia de regra jamais pode virar liberacao.',
   'Usuario cujo perfil nao define nada sobre o recurso Y.',
   '[{"ordem":1,"acao":"Tentar ler o recurso Y","resultado_esperado":"Negado por padrao"},
     {"ordem":2,"acao":"Tentar gravar no recurso Y","resultado_esperado":"Negado por padrao"}]'::jsonb,
   'Sem regra explicita, o acesso e negado nos dois verbos.',
   'Documento de origem: PER-004.'),

  (v_mod, 'PER-005', 'Permissao nula ou vazia nao vira acesso total',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'O nulo mal tratado e o caminho mais curto para liberar tudo. Aqui ele tem que ser lido como negacao.',
   'Registro de permissao com valor nulo ou vazio, criado no cercado de teste.',
   '[{"ordem":1,"acao":"Forcar um registro de permissao com valor nulo ou vazio","resultado_esperado":"O registro existe no cercado"},
     {"ordem":2,"acao":"Pedir a decisao de acesso para esse recurso","resultado_esperado":"Negado; nunca tratado como liberacao ampla"}]'::jsonb,
   'Permissao nula ou vazia e tratada como negacao.',
   'Documento de origem: PER-005. Atencao ao enum perfil_escopo_tipo: comparar sempre como texto.'),

  (v_mod, 'PER-006', 'Permissao de leitura nao implica escrita',
   'alternativo', 'alta', 'aprovado', 'api', NULL,
   'Verbos separados. Conceder leitura e ganhar escrita de brinde e um erro comum de modelagem.',
   'Usuario com permissao somente de leitura no recurso.',
   '[{"ordem":1,"acao":"Ler o recurso","resultado_esperado":"Leitura permitida"},
     {"ordem":2,"acao":"Tentar editar o recurso","resultado_esperado":"Negado"},
     {"ordem":3,"acao":"Tentar excluir o recurso","resultado_esperado":"Negado"}]'::jsonb,
   'Leitura permitida, escrita e exclusao negadas.',
   'Documento de origem: PER-006.'),

  (v_mod, 'PER-007', 'Permissao granular por modulo e respeitada',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'O acesso e por modulo. Liberar Ponto nao pode abrir Documentos, onde moram atestados e dado sensivel.',
   'Usuario com acesso ao modulo Ponto e sem acesso a Documentos.',
   '[{"ordem":1,"acao":"Acessar o modulo Ponto","resultado_esperado":"Permitido"},
     {"ordem":2,"acao":"Acessar o modulo Documentos","resultado_esperado":"Negado, tanto na tela quanto na consulta direta"}]'::jsonb,
   'Acesso concedido apenas no modulo liberado.',
   'Documento de origem: PER-007. Apoia-se em perfil_permite_modulo e nas politicas restritivas de perfil.'),

  (v_mod, 'PER-008', 'Alterar permissao em um tenant nao afeta o outro',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Configuracao de um cliente respingando em outro e vazamento de controle: 1.100 clientes dependem desse isolamento.',
   'Perfis de mesmo nome nos tenants A e B.',
   '[{"ordem":1,"acao":"Registrar as permissoes do perfil no tenant B","resultado_esperado":"Lista de referencia guardada"},
     {"ordem":2,"acao":"Ajustar a permissao do perfil de mesmo nome no tenant A","resultado_esperado":"Alteracao gravada em A"},
     {"ordem":3,"acao":"Comparar as permissoes do tenant B com a referencia","resultado_esperado":"Identicas: B nao foi tocado"}]'::jsonb,
   'A alteracao fica contida no tenant A.',
   'Documento de origem: PER-008.'),

  -- ══════════════════════════════════════════════════════
  -- LIB — Liberacoes (concessoes pontuais alem do perfil)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'LIB-001', 'Liberar um recurso pontual a um usuario, sem mexer no perfil',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Prova a premissa P3: liberacao e aditiva e pontual. Se ela alterar o perfil base, contamina todos os outros vinculados.',
   'Colaborador X vinculado a Empresa A, sem o recurso no perfil.',
   '[{"ordem":1,"acao":"Admin concede a X, na Empresa A, a liberacao do recurso","resultado_esperado":"Registro criado em perfil_excecoes, tipo adicional, ativo"},
     {"ordem":2,"acao":"Simular X na Empresa A e acessar o recurso","resultado_esperado":"Permitido"},
     {"ordem":3,"acao":"Conferir o perfil base","resultado_esperado":"Inalterado; os demais usuarios do perfil seguem sem o recurso"}]'::jsonb,
   'X acessa o recurso na Empresa A e o perfil base fica intacto.',
   'Documento de origem: LIB-001.'),

  (v_mod, 'LIB-002', 'Liberacao vale so na empresa em que foi concedida',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Ponto mais critico da familia: liberacao que vaza entre vinculos vira permissao global sem ninguem perceber.',
   'X vinculado a A e a B, com liberacao concedida apenas em A.',
   '[{"ordem":1,"acao":"No contexto da Empresa A, usar o recurso liberado","resultado_esperado":"Permitido"},
     {"ordem":2,"acao":"No contexto da Empresa B, tentar o mesmo recurso","resultado_esperado":"Negado"}]'::jsonb,
   'A liberacao vale em A e nao vale em B.',
   'Documento de origem: LIB-002.'),

  (v_mod, 'LIB-003', 'Revogar a liberacao devolve o usuario ao teto do perfil',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Revogacao que nao revoga e o defeito silencioso mais perigoso: ninguem repara que o acesso continuou.',
   'Liberacao ativa, como em LIB-001.',
   '[{"ordem":1,"acao":"Remover a liberacao","resultado_esperado":"O registro deixa de valer"},
     {"ordem":2,"acao":"Simular X e tentar o recurso","resultado_esperado":"Negado: X volta ao teto do perfil base"}]'::jsonb,
   'O acesso cessa na revogacao.',
   'Documento de origem: LIB-003.'),

  (v_mod, 'LIB-004', 'Liberacao com prazo expira sozinha',
   'alternativo', 'media', 'aprovado', 'api', NULL,
   'Liberacao temporaria que nao expira vira permanente por esquecimento. A estrutura tem o campo de expiracao; falta provar que a decisao de acesso o respeita.',
   'Liberacao concedida com data de expiracao.',
   '[{"ordem":1,"acao":"Dentro da vigencia, acessar o recurso","resultado_esperado":"Permitido"},
     {"ordem":2,"acao":"Com a data ja passada, tentar de novo","resultado_esperado":"Negado automaticamente, sem precisar de revogacao manual"}]'::jsonb,
   'Acesso liberado na vigencia e negado depois de expirar.',
   'Documento de origem: LIB-004. O campo expira_em existe em perfil_excecoes; se a decisao de acesso o ignorar, este caso acusa.'),

  (v_mod, 'LIB-005', 'Liberacao nao eleva alguem acima do teto de quem concede',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Se o admin pode liberar o que ele proprio nao tem, a liberacao vira porta de escalada.',
   'Admin de empresa sem a capacidade Z.',
   '[{"ordem":1,"acao":"Admin tenta liberar a capacidade Z para outro usuario","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir as liberacoes do usuario alvo","resultado_esperado":"Nenhuma liberacao criada"}]'::jsonb,
   'Concessao acima do teto do concedente e negada.',
   'Documento de origem: LIB-005. Cruza com NAC-006 e PRIV-002.'),

  -- ══════════════════════════════════════════════════════
  -- CTX — Troca de contexto de empresa
  -- ══════════════════════════════════════════════════════
  (v_mod, 'CTX-001', 'Escolher a empresa ativa no login',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'Primeira decisao de escopo da sessao. Escolher A tem que trazer A, e so A.',
   'Usuario vinculado a A e a B.',
   '[{"ordem":1,"acao":"Fazer login","resultado_esperado":"A escolha de empresa aparece, listando A e B"},
     {"ordem":2,"acao":"Escolher a Empresa A","resultado_esperado":"O painel carrega com os dados de A e o nivel de A; nenhuma referencia a B na tela"}]'::jsonb,
   'A sessao comeca no escopo exato da empresa escolhida.',
   'Documento de origem: CTX-001.'),

  (v_mod, 'CTX-002', 'Trocar de empresa dentro da sessao troca o escopo inteiro',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A troca precisa mudar dados E nivel. Trocar so a tela, mantendo o nivel antigo, e escalada disfarcada.',
   'Sessao aberta na Empresa A, com vinculo tambem em B.',
   '[{"ordem":1,"acao":"Trocar para a Empresa B pelo seletor","resultado_esperado":"O contexto passa a B"},
     {"ordem":2,"acao":"Conferir os dados na tela","resultado_esperado":"Os dados de A somem; aparecem os de B"},
     {"ordem":3,"acao":"Conferir o nivel em vigor","resultado_esperado":"O nivel aplicado e o de B; acoes exclusivas do nivel de A nao aparecem"}]'::jsonb,
   'Dados e nivel passam a ser os da Empresa B.',
   'Documento de origem: CTX-002.'),

  (v_mod, 'CTX-003', 'O nivel muda junto com o contexto, tambem no backend',
   'feliz', 'critica', 'aprovado', 'api', NULL,
   'Prova as premissas P1 e P5 no lado que importa: a decisao no banco acompanha a empresa ativa.',
   'Usuario Admin em A e Colaborador em B.',
   '[{"ordem":1,"acao":"Com contexto A, executar acao exclusiva de Admin","resultado_esperado":"Permitido"},
     {"ordem":2,"acao":"Trocar o contexto para B e repetir a mesma acao","resultado_esperado":"Negado"}]'::jsonb,
   'A mesma acao muda de resultado ao trocar de contexto.',
   'Documento de origem: CTX-003.'),

  (v_mod, 'CTX-004', 'Dado da empresa anterior nao fica grudado na tela',
   'excecao', 'critica', 'aprovado', 'e2e', 'LGPD art. 46 (seguranca)',
   'Vazamento por cache e o mais facil de passar despercebido: a lista certa, na empresa errada.',
   'Sessao na Empresa A, com a lista de colaboradores carregada.',
   '[{"ordem":1,"acao":"Carregar a lista de colaboradores da Empresa A","resultado_esperado":"A lista de A aparece"},
     {"ordem":2,"acao":"Trocar para a Empresa B sem recarregar a pagina","resultado_esperado":"A lista de A desaparece e a tela recarrega no escopo de B"},
     {"ordem":3,"acao":"Conferir a lista exibida","resultado_esperado":"Somente colaboradores de B; nenhum nome de A remanescente"}]'::jsonb,
   'Nenhum dado da Empresa A permanece visivel apos a troca.',
   'Documento de origem: CTX-004.'),

  (v_mod, 'CTX-005', 'Requisicao em voo durante a troca nao devolve dado da empresa antiga',
   'excecao', 'alta', 'aprovado', 'api', NULL,
   'Condicao de corrida: a resposta chega depois da troca. Se ela trouxer dado de A para a sessao que ja esta em B, vazou.',
   'Sessao em A, com vinculo tambem em B.',
   '[{"ordem":1,"acao":"Disparar uma consulta no contexto A e, em paralelo, trocar para B","resultado_esperado":"A troca se conclui"},
     {"ordem":2,"acao":"Conferir a resposta da consulta em voo","resultado_esperado":"Avaliada contra o contexto correto; nao devolve dado de A sob a sessao que ja esta em B"}]'::jsonb,
   'Nenhuma janela de corrida devolve dado da empresa anterior.',
   'Documento de origem: CTX-005. O proprio documento sinaliza que este caso pode ficar como nao provado sem ambiente concorrente real.'),

  (v_mod, 'CTX-006', 'Id direto de outra empresa vinculada nao basta sem trocar de contexto',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Confirma que o enforcement e por contexto ativo, nao pela uniao dos vinculos. Pertencer a B nao e estar em B.',
   'Usuario vinculado a A e a B, com contexto ativo em A.',
   '[{"ordem":1,"acao":"Com contexto A, acessar diretamente o id de um registro da Empresa B","resultado_esperado":"Negado; zero linhas"},
     {"ordem":2,"acao":"Trocar para B e repetir","resultado_esperado":"Agora sim permitido, conforme o nivel em B"}]'::jsonb,
   'Negado no contexto A e permitido apos a troca para B.',
   'Documento de origem: CTX-006.'),

  -- ══════════════════════════════════════════════════════
  -- ISOL — Isolamento multi-tenant (documento: serie RLS)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'ISOL-001', 'Leitura devolve apenas linhas do proprio tenant',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Lado positivo do isolamento: o usuario enxerga o que e dele.',
   'Dados de dois tenants no cercado de teste.',
   '[{"ordem":1,"acao":"Simular usuario do tenant A e consultar uma tabela sensivel","resultado_esperado":"Retornam linhas do tenant A"},
     {"ordem":2,"acao":"Conferir o tenant de cada linha devolvida","resultado_esperado":"Todas do tenant A"}]'::jsonb,
   'A consulta devolve somente linhas do proprio tenant.',
   'Documento de origem: RLS-001.'),

  (v_mod, 'ISOL-002', 'Leitura nao alcanca linha de outro tenant',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Lado negativo: o vazamento entre tenants nao aparece na tela, mora na politica. E o maior risco do produto.',
   'Dados de dois tenants no cercado de teste.',
   '[{"ordem":1,"acao":"Simular usuario do tenant A e consultar linhas do tenant B","resultado_esperado":"Zero linhas"},
     {"ordem":2,"acao":"Repetir informando o id exato de uma linha de B","resultado_esperado":"Zero linhas"}]'::jsonb,
   'Nenhuma linha de outro tenant e devolvida, nem por busca nem por id.',
   'Documento de origem: RLS-002.'),

  (v_mod, 'ISOL-003', 'Escrita nao alcanca linha de outro tenant',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Erro classico: a politica cobre leitura e esquece a escrita, que passa em silencio.',
   'Dados de dois tenants no cercado de teste.',
   '[{"ordem":1,"acao":"Simular usuario do tenant A e tentar alterar uma linha do tenant B","resultado_esperado":"Zero linhas afetadas"},
     {"ordem":2,"acao":"Tentar excluir uma linha do tenant B","resultado_esperado":"Zero linhas afetadas"},
     {"ordem":3,"acao":"Conferir a linha de B","resultado_esperado":"Intacta"}]'::jsonb,
   'Nenhuma escrita cruza a fronteira de tenant.',
   'Documento de origem: RLS-003.'),

  (v_mod, 'ISOL-004', 'Insercao nao consegue plantar linha em outro tenant',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Sem a clausula de verificacao na insercao, da para semear dado dentro do cliente errado.',
   'Usuario do tenant A no cercado de teste.',
   '[{"ordem":1,"acao":"Simular usuario do tenant A e inserir uma linha declarando o tenant B","resultado_esperado":"Rejeitado pela verificacao da politica"},
     {"ordem":2,"acao":"Conferir a tabela no tenant B","resultado_esperado":"Nenhuma linha nova"}]'::jsonb,
   'Insercao com tenant alheio e rejeitada.',
   'Documento de origem: RLS-004.'),

  (v_mod, 'ISOL-005', 'Toda tabela sensivel tem isolamento ligado e politica coerente',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 11 e art. 46',
   'Varredura estrutural: tabela sensivel com isolamento desligado fica exposta; com isolamento ligado e zero politica, fica inacessivel e alguem vai "consertar" desligando.',
   'Somente leitura: auditoria de estrutura.',
   '[{"ordem":1,"acao":"Varrer as tabelas sensiveis conferindo se o isolamento esta habilitado","resultado_esperado":"Nenhuma tabela sensivel com o isolamento desligado"},
     {"ordem":2,"acao":"Para cada uma, contar as politicas","resultado_esperado":"Nenhuma tabela sensivel com isolamento ligado e zero politica"}]'::jsonb,
   'Nenhuma tabela sensivel exposta nem travada por ausencia de politica.',
   'Documento de origem: RLS-005. Depende da lista real de tabelas sensiveis; a rotina deve deriva-la, nao fixa-la.'),

  (v_mod, 'ISOL-006', 'Rotina sensivel nao fica executavel por quem nao deve',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Precedente real: rotina aberta a usuario anonimo em outro modulo. Auditoria de permissao de execucao fecha essa porta.',
   'Somente leitura: auditoria de estrutura.',
   '[{"ordem":1,"acao":"Auditar as permissoes de execucao das rotinas sensiveis","resultado_esperado":"Nenhuma executavel por usuario anonimo"},
     {"ordem":2,"acao":"Conferir as liberadas para usuario autenticado","resultado_esperado":"Somente as previstas, e todas com checagem interna de tenant e permissao"}]'::jsonb,
   'Nenhuma rotina sensivel aberta ao anonimo, e as autenticadas checam tenant e permissao por dentro.',
   'Documento de origem: RLS-006.'),

  (v_mod, 'ISOL-007', 'Acesso cross-tenant do superadmin fica registrado',
   'alternativo', 'critica', 'aprovado', 'api', 'LGPD art. 37 (registro das operacoes)',
   'Prova a premissa P4: o superadmin atravessa o isolamento por desenho, e por isso mesmo cada travessia precisa deixar rastro.',
   'Superadmin e dados de mais de um tenant no cercado de teste.',
   '[{"ordem":1,"acao":"Superadmin acessa dado de um tenant do qual nao e membro","resultado_esperado":"Permitido, por desenho"},
     {"ordem":2,"acao":"Conferir o registro de auditoria","resultado_esperado":"Ha uma entrada com quem, quando e o que foi acessado"}]'::jsonb,
   'O acesso e permitido e auditado.',
   'Documento de origem: RLS-007. Se nao houver registro, o caso acusa a lacuna de auditoria.'),

  (v_mod, 'ISOL-008', 'Rotina privilegiada reaplica o filtro de tenant por dentro',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Rotina que roda com privilegio do dono ignora o isolamento. Se ela nao refiltrar por tenant, vira um tunel entre clientes.',
   'Somente leitura: auditoria de estrutura.',
   '[{"ordem":1,"acao":"Levantar as rotinas que rodam com privilegio do dono e tocam tabela sensivel","resultado_esperado":"Lista obtida"},
     {"ordem":2,"acao":"Conferir se cada uma reaplica o filtro de tenant no proprio corpo","resultado_esperado":"Nenhuma devolve dado de outro tenant por rodar privilegiada"}]'::jsonb,
   'Nenhuma rotina privilegiada fura o isolamento.',
   'Documento de origem: RLS-008.'),

  -- ══════════════════════════════════════════════════════
  -- PRIV — Escalada de privilegio (documento: serie ESC)
  -- ══════════════════════════════════════════════════════
  (v_mod, 'PRIV-001', 'Usuario nao edita o proprio nivel de acesso',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Auto-promocao e a escalada mais direta que existe.',
   'Usuario comum autenticado.',
   '[{"ordem":1,"acao":"Usuario chama a rotina que altera o proprio perfil para um nivel superior","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir o vinculo do usuario","resultado_esperado":"Perfil inalterado"}]'::jsonb,
   'A auto-promocao e negada e o vinculo permanece como estava.',
   'Documento de origem: ESC-001.'),

  (v_mod, 'PRIV-002', 'Admin nao concede acima do proprio teto',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Sem teto, o admin de um cliente cria para si um caminho ate o superadmin em dois passos.',
   'Admin de empresa autenticado.',
   '[{"ordem":1,"acao":"Admin tenta criar ou atribuir um perfil com capacidades que ele nao possui","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir perfis e vinculos apos a tentativa","resultado_esperado":"Nada criado nem atribuido"}]'::jsonb,
   'Concessao acima do teto e negada, sem efeito colateral.',
   'Documento de origem: ESC-002. Cruza com NAC-006 e LIB-005.'),

  (v_mod, 'PRIV-003', 'Empresa ou papel enviados no pedido nao mudam a decisao de acesso',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'A decisao tem que vir dos claims verificados da sessao. Se o backend acreditar no que vem no corpo do pedido, qualquer um se declara admin.',
   'Usuario comum autenticado na Empresa A.',
   '[{"ordem":1,"acao":"Enviar o pedido adulterando a empresa e o papel no corpo","resultado_esperado":"Os valores do corpo sao ignorados"},
     {"ordem":2,"acao":"Conferir o resultado","resultado_esperado":"O acesso continua o do vinculo real; nenhum ganho pela adulteracao"}]'::jsonb,
   'O backend decide pelos claims verificados, nao pelo conteudo do pedido.',
   'Documento de origem: ESC-003.'),

  (v_mod, 'PRIV-004', 'Credencial de um tenant nao vale no recurso de outro',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'Reuso de credencial entre tenants e o teste direto da fronteira.',
   'Credenciais validas do tenant A e recurso conhecido do tenant B.',
   '[{"ordem":1,"acao":"Usar a credencial do tenant A para chamar um recurso do tenant B","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir o recurso de B","resultado_esperado":"Nada lido nem alterado"}]'::jsonb,
   'Credencial de A nao abre nada em B.',
   'Documento de origem: ESC-004.'),

  (v_mod, 'PRIV-005', 'Trocar o id do recurso nao da acesso ao dado alheio',
   'excecao', 'critica', 'aprovado', 'api', 'LGPD art. 46 (seguranca)',
   'O id valido e existente e o teste honesto: o isolamento tem que negar mesmo quando o atacante acerta o alvo.',
   'Id valido de um registro pertencente a outro tenant.',
   '[{"ordem":1,"acao":"Substituir o id do recurso por um id existente de outro tenant","resultado_esperado":"Negado, mesmo com id valido"},
     {"ordem":2,"acao":"Conferir a mensagem devolvida","resultado_esperado":"Nao revela a existencia nem o conteudo do registro alheio"}]'::jsonb,
   'Acesso por id alheio e negado e a resposta nao vaza a existencia do registro.',
   'Documento de origem: ESC-005. O id ser um identificador aleatorio reduz a chance de adivinhar, mas nao substitui a negacao.'),

  (v_mod, 'PRIV-006', 'Superadmin so nasce pelo fluxo controlado',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Superadmin e o maior poder do sistema. Se o admin de um cliente consegue criar um, o produto inteiro cai.',
   'Admin de empresa autenticado.',
   '[{"ordem":1,"acao":"Tentar atribuir o papel de superadmin pelas vias normais de administracao de empresa","resultado_esperado":"Negado"},
     {"ordem":2,"acao":"Conferir os papeis do usuario alvo","resultado_esperado":"Nenhum papel de superadmin concedido"}]'::jsonb,
   'Superadmin nao e criado nem atribuido fora do fluxo controlado.',
   'Documento de origem: ESC-006.'),

  -- ══════════════════════════════════════════════════════
  -- SES — Sessao e revogacao em tempo real
  -- ══════════════════════════════════════════════════════
  (v_mod, 'SES-001', 'O login concede exatamente o escopo do vinculo ativo',
   'feliz', 'alta', 'aprovado', 'api', NULL,
   'Prova a premissa P5: a sessao carrega a empresa ativa e o nivel daquela empresa, e nada alem.',
   'Usuario vinculado a A e a B, entrando na Empresa A.',
   '[{"ordem":1,"acao":"Autenticar escolhendo a Empresa A","resultado_esperado":"A sessao registra a empresa ativa A"},
     {"ordem":2,"acao":"Conferir o nivel em vigor na sessao","resultado_esperado":"E o nivel do vinculo com A; nenhuma permissao herdada de B"}]'::jsonb,
   'A sessao carrega a empresa ativa e o nivel daquele vinculo, sem excedentes.',
   'Documento de origem: SES-001.'),

  (v_mod, 'SES-002', 'Remocao de vinculo vale na sessao ja aberta',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Revogacao que so vale no proximo login deixa uma janela aberta de duracao desconhecida.',
   'Usuario logado na Empresa A.',
   '[{"ordem":1,"acao":"Com o usuario logado, remover o vinculo com a Empresa A","resultado_esperado":"O vinculo deixa de existir"},
     {"ordem":2,"acao":"O usuario tenta uma nova acao na mesma sessao","resultado_esperado":"Negado ja na proxima requisicao, sem exigir novo login"}]'::jsonb,
   'O acesso cessa na proxima requisicao da sessao ja aberta.',
   'Documento de origem: SES-002. Lacuna a decidir com o time: a latencia aceitavel.'),

  (v_mod, 'SES-003', 'Desativar o usuario encerra a sessao aberta',
   'excecao', 'critica', 'aprovado', 'api', NULL,
   'Desativar alguem que segue agindo na sessao aberta e desativacao no papel.',
   'Usuario ativo e logado.',
   '[{"ordem":1,"acao":"Desativar o usuario enquanto ele esta logado","resultado_esperado":"Status passa a inativo"},
     {"ordem":2,"acao":"O usuario tenta agir na sessao aberta","resultado_esperado":"Sessao invalidada; acoes negadas"}]'::jsonb,
   'Sessao invalidada e acoes negadas apos a desativacao.',
   'Documento de origem: SES-003. Cruza com USR-006.'),

  (v_mod, 'SES-004', 'Rebaixar o nivel vale imediatamente',
   'excecao', 'alta', 'aprovado', 'api', NULL,
   'Rebaixamento que so vale no proximo login mantem poder de admin nas maos de quem ja perdeu o cargo.',
   'Usuario logado como Admin na Empresa A.',
   '[{"ordem":1,"acao":"Rebaixar o usuario de Admin para Colaborador na Empresa A","resultado_esperado":"O vinculo passa a apontar para o perfil de Colaborador"},
     {"ordem":2,"acao":"O usuario tenta uma acao exclusiva de Admin na mesma sessao","resultado_esperado":"Negado na proxima requisicao"}]'::jsonb,
   'A acao de admin e negada logo apos o rebaixamento.',
   'Documento de origem: SES-004.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Usuarios & Permissoes: antes=%, depois=% (esperado 59)', v_antes, v_depois;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'FALHA ao cadastrar a documentacao: %', SQLERRM;
END $entrega$;

-- =========================================================
-- CONFERENCIA (unico resultado que o editor mostra)
-- Esperado: 9 linhas de familia, somando 59 casos, e a linha TOTAL
-- com falta_passos = 0 e falta_texto = 0.
-- =========================================================
WITH casos AS MATERIALIZED (
  SELECT c.codigo, c.nivel, c.prioridade, c.passos, c.objetivo, c.resultado_esperado
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  WHERE m.path = 'infraestrutura-auth/usuarios-permissoes'
)
SELECT
  COALESCE(split_part(codigo, '-', 1), 'TOTAL')            AS familia,
  count(*)                                                 AS casos,
  count(*) FILTER (WHERE nivel = 'api')                    AS motor_sql,
  count(*) FILTER (WHERE nivel = 'e2e')                    AS tela_cypress,
  count(*) FILTER (WHERE prioridade = 'critica')           AS criticos,
  count(*) FILTER (WHERE jsonb_array_length(passos) = 0)   AS falta_passos,
  count(*) FILTER (WHERE objetivo IS NULL
                      OR resultado_esperado IS NULL)       AS falta_texto
FROM casos
GROUP BY ROLLUP (split_part(codigo, '-', 1))
ORDER BY familia NULLS LAST;
