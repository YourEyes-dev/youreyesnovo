-- =========================================================
-- QA — RLS (segurança de dados): primeira documentação do módulo (7 casos)
--
-- Módulo infraestrutura-auth/rls, zero casos até aqui.
-- Casos de INFRAESTRUTURA (nivel api): documentam as garantias da camada de
-- Row-Level Security — isolamento por tenant, políticas RESTRICTIVE
-- perfil_restringe_leitura_* nas tabelas sensíveis, perfil_permite_modulo e a
-- proteção de dado de saúde (LGPD art. 11). São a espinha de segurança do
-- produto; ficam documentados aqui (rotina do motor SQL a implementar).
--
-- Regra da casa: caso api sem rotina fica 'nao_implementado' (não é erro).
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/rls';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo infraestrutura-auth/rls não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'RLS-001', 'Tabelas sensíveis têm RLS habilitada',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 46 (segurança)',
   'RLS desligada numa tabela sensível expõe dados a qualquer sessão. A base deve ter RLS ativa em todas as tabelas de negócio sensíveis.',
   'Simular sessão authenticated.',
   '[{"ordem":1,"acao":"Conferir rowsecurity nas tabelas sensíveis (atestados, ponto_diario, férias, psico, benefícios, documentos...)","resultado_esperado":"Todas com RLS habilitada"}]'::jsonb,
   'Nenhuma tabela sensível fica sem RLS.', NULL),

  (v_mod, 'RLS-002', 'Isolamento por tenant: não se lê dado de outra empresa',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 6º / multi-tenant',
   'O sistema é multiempresa. Um usuário de um tenant não pode, em hipótese alguma, ler linhas de outro tenant.',
   'Duas empresas (tenants) com dados; simular usuário do tenant A.',
   '[{"ordem":1,"acao":"Como usuário do tenant A, consultar tabelas de negócio","resultado_esperado":"Só retornam linhas do tenant A; nada do tenant B"}]'::jsonb,
   'O isolamento por tenant é garantido pela RLS.', NULL),

  (v_mod, 'RLS-003', 'Políticas RESTRICTIVE de perfil aplicadas nas tabelas sensíveis',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 6º (necessidade)',
   'A camada de perfil usa políticas RESTRICTIVE perfil_restringe_leitura_* para limitar leitura por escopo do perfil. Cada tabela sensível prevista precisa ter a sua.',
   'Simular usuário com perfil restrito.',
   '[{"ordem":1,"acao":"Conferir a existência das políticas perfil_restringe_leitura_* nas tabelas cobertas","resultado_esperado":"Presentes nas tabelas sensíveis (ponto, férias, saúde, psico, benefícios, documentos)"}]'::jsonb,
   'As políticas RESTRICTIVE de perfil estão presentes.',
   'Alinhado à rotina de QA PERFIL-003 (acusa tabela sensível sem política).'),

  (v_mod, 'RLS-004', 'Dado de saúde só é lido por perfil autorizado',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 11 (dado sensível de saúde)',
   'Atestados, afastamentos e eventos de saúde são dado sensível. Perfil sem escopo de saúde não pode lê-los, mesmo dentro do tenant.',
   'Usuário do tenant com perfil sem escopo de saúde.',
   '[{"ordem":1,"acao":"Consultar atestados/afastamentos/eventos_saude com perfil sem escopo de saúde","resultado_esperado":"Leitura bloqueada pela política RESTRICTIVE"}]'::jsonb,
   'O dado de saúde é protegido por perfil.', NULL),

  (v_mod, 'RLS-005', 'perfil_permite_modulo barra módulo não liberado ao perfil',
   'negativo', 'alta', 'aprovado', 'api', 'Menor privilégio',
   'A função perfil_permite_modulo é o portão de módulo. Um perfil sem o módulo não deve ler as tabelas daquele módulo.',
   'Perfil sem um módulo específico.',
   '[{"ordem":1,"acao":"Consultar tabelas do módulo não liberado ao perfil","resultado_esperado":"Retorno vazio/bloqueado pela camada de perfil"}]'::jsonb,
   'O acesso por módulo respeita o perfil.', NULL),

  (v_mod, 'RLS-006', 'Sessão sem autenticação não lê dado de negócio',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD art. 46',
   'auth.uid() nulo (não autenticado) não pode enxergar dado de negócio. É a linha de base da RLS.',
   'Sessão sem claims (auth.uid() NULL).',
   '[{"ordem":1,"acao":"Consultar tabelas de negócio sem autenticação","resultado_esperado":"Nada é retornado"}]'::jsonb,
   'O anônimo não lê dado de negócio.', NULL),

  (v_mod, 'RLS-007', 'Tabela sensível nova precisa de política de perfil',
   'excecao', 'alta', 'aprovado', 'api', 'LGPD art. 6º',
   'Toda tabela sensível nova tem de entrar na camada de perfil (ou ter exceção documentada). É o que evita vazamento por esquecimento ao crescer o schema.',
   'Rotina de QA que varre tabelas sensíveis.',
   '[{"ordem":1,"acao":"Rodar a checagem de cobertura de perfil (PERFIL-003)","resultado_esperado":"Nenhuma tabela sensível sem política/exceção"}]'::jsonb,
   'A camada de perfil acompanha o crescimento do schema.', NULL)

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'RLS: antes=%, depois=% (esperado +7)', v_antes, v_depois;
END $doc$;
