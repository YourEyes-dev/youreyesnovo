-- =========================================================
-- QA — Autenticação: primeira documentação do módulo (12 casos)
--
-- Módulo infraestrutura-auth/autenticacao, zero casos até aqui.
-- Casos de TELA (nivel e2e) ancorados em src/pages/auth/Login.tsx,
-- ForgotPassword/ResetPassword, ProtectedRoute e SuperAdminRoute: login,
-- logout, sessão, recuperação de senha e proteção de rotas. Autenticação é
-- a porta para dados sensíveis (LGPD art. 11) — casos de alto valor.
--
-- Regra da casa: caso e2e sem spec só gera aviso na guarda.
-- Idempotente: ON CONFLICT (codigo) DO NOTHING.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'infraestrutura-auth/autenticacao';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo infraestrutura-auth/autenticacao não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  (v_mod, 'AUTH-001', 'Tela de login monta com os campos e ações',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A porta de entrada do sistema. Se não monta, ninguém entra.',
   'Sessão deslogada; rota /login.',
   '[{"ordem":1,"acao":"Abrir /login","resultado_esperado":"Título Login; campos E-mail e Senha; botão Entrar; links Esqueceu a senha? e Cadastre sua empresa"}]'::jsonb,
   'A tela de login monta completa.', NULL),

  (v_mod, 'AUTH-002', 'Login com credenciais válidas entra no sistema',
   'feliz', 'critica', 'aprovado', 'e2e', 'LGPD art. 11 (acesso a dado sensível)',
   'É o fluxo que autentica e libera o app. Deve entrar e levar ao destino.',
   'Conta válida.',
   '[{"ordem":1,"acao":"Informar e-mail e senha corretos e clicar em Entrar","resultado_esperado":"Aviso Login realizado com sucesso!; entra no app (rota inicial ou a de origem)"}]'::jsonb,
   'O login válido autentica e redireciona.', NULL),

  (v_mod, 'AUTH-003', 'Login com senha errada mostra erro genérico',
   'negativo', 'critica', 'aprovado', 'e2e', 'Segurança (anti-enumeração)',
   'Errar a senha (ou o e-mail) deve dar a MESMA mensagem genérica — sem revelar se o e-mail existe.',
   'Rota /login.',
   '[{"ordem":1,"acao":"Informar e-mail válido e senha errada e Entrar","resultado_esperado":"Aviso Não foi possível entrar / E-mail ou senha incorretos..."},
     {"ordem":2,"acao":"Informar um e-mail inexistente","resultado_esperado":"A mesma mensagem genérica (não diz que o e-mail não existe)"}]'::jsonb,
   'O erro de login não permite enumerar contas.', NULL),

  (v_mod, 'AUTH-004', 'Campos vazios/ inválidos barram o envio',
   'negativo', 'alta', 'aprovado', 'e2e', NULL,
   'E-mail malformado ou senha curta não podem ser enviados. A validação inline deve barrar antes do envio.',
   'Rota /login.',
   '[{"ordem":1,"acao":"Informar e-mail inválido e senha curta e tentar Entrar","resultado_esperado":"E-mail inválido e Senha deve ter pelo menos 6 caracteres; não envia"}]'::jsonb,
   'A validação do formulário barra entradas inválidas.', NULL),

  (v_mod, 'AUTH-005', 'Mostrar/ocultar a senha',
   'alternativo', 'baixa', 'aprovado', 'e2e', NULL,
   'O olho revela/oculta a senha — ajuda a digitar certo sem expor por padrão.',
   'Rota /login com senha digitada.',
   '[{"ordem":1,"acao":"Alternar o botão de exibir senha","resultado_esperado":"O campo troca entre oculto e visível"}]'::jsonb,
   'A alternância de visibilidade da senha funciona.', NULL),

  (v_mod, 'AUTH-010', 'A sessão persiste ao recarregar a página',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'Recarregar não pode deslogar. A sessão persistida deve manter o usuário dentro.',
   'Usuário logado.',
   '[{"ordem":1,"acao":"Recarregar a página autenticado","resultado_esperado":"Continua logado (sem voltar ao login)"}]'::jsonb,
   'A sessão sobrevive ao reload.', NULL),

  (v_mod, 'AUTH-011', 'Logout limpa a sessão',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD (encerramento de acesso)',
   'Sair precisa encerrar de verdade: depois do logout, rota protegida volta ao login.',
   'Usuário logado.',
   '[{"ordem":1,"acao":"Sair da conta","resultado_esperado":"Sessão encerrada"},
     {"ordem":2,"acao":"Tentar abrir uma rota protegida","resultado_esperado":"Redireciona para /login"}]'::jsonb,
   'O logout encerra a sessão.', NULL),

  (v_mod, 'AUTH-020', 'Rota protegida sem login redireciona para o login',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 11',
   'Ninguém acessa dado protegido sem autenticar. Rota protegida sem sessão deve mandar ao login e voltar depois.',
   'Sessão deslogada.',
   '[{"ordem":1,"acao":"Abrir direto uma rota protegida sem login","resultado_esperado":"Redireciona para /login"},
     {"ordem":2,"acao":"Fazer login","resultado_esperado":"Retorna à rota que tentou abrir"}]'::jsonb,
   'A proteção de rota barra o não autenticado.', NULL),

  (v_mod, 'AUTH-021', 'Área de superadmin barra usuário comum',
   'negativo', 'critica', 'aprovado', 'e2e', 'Menor privilégio',
   'As áreas /admin e /academia são só de superadmin. Um usuário comum logado não pode entrar.',
   'Usuário comum logado.',
   '[{"ordem":1,"acao":"Abrir /admin como usuário comum","resultado_esperado":"Tela Acesso Restrito / Esta área é restrita a Super Administradores."}]'::jsonb,
   'A área de superadmin é protegida.', NULL),

  (v_mod, 'AUTH-022', 'Conta bloqueada não acessa o sistema',
   'negativo', 'alta', 'aprovado', 'e2e', 'LGPD / governança',
   'Uma conta bloqueada até autentica, mas não pode usar o sistema — só sair.',
   'Conta bloqueada por um administrador.',
   '[{"ordem":1,"acao":"Entrar com a conta bloqueada","resultado_esperado":"Tela Acesso Bloqueado com a única ação Sair da conta"}]'::jsonb,
   'A conta bloqueada é impedida de usar o sistema.', NULL),

  (v_mod, 'AUTH-030', 'Recuperação de senha envia o link',
   'alternativo', 'media', 'aprovado', 'e2e', NULL,
   'Esquecer a senha não pode travar o acesso. Informar o e-mail deve disparar o link de recuperação.',
   'Rota /forgot-password.',
   '[{"ordem":1,"acao":"Informar o e-mail e Enviar link de recuperação","resultado_esperado":"Confirmação Verifique seu e-mail / E-mail enviado!"}]'::jsonb,
   'A recuperação de senha dispara o link.',
   'Não confirma nem nega a existência da conta.'),

  (v_mod, 'AUTH-031', 'Redefinir senha sem sessão de recuperação é barrado',
   'negativo', 'media', 'aprovado', 'e2e', 'Segurança',
   'A tela de nova senha só vale com um link de recuperação válido. Sem ele, deve barrar e oferecer novo link.',
   'Rota /reset-password sem sessão de recuperação.',
   '[{"ordem":1,"acao":"Abrir /reset-password sem link válido","resultado_esperado":"Link inválido ou expirado + Solicitar novo link"}]'::jsonb,
   'A redefinição exige um link válido.',
   'A nova senha exige a política (mín. 12, com complexidade).')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Autenticação: antes=%, depois=% (esperado +12)', v_antes, v_depois;
END $doc$;
