-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 06a: assinatura, usuarios e perfis de acesso,
-- auditoria, suporte, mural (feed), plano de acao e pendencias
--
-- PARA QUE SERVE
-- Preenche, para a "Metalurgica Exemplo Ltda" (tenant de demonstracao criado pela
-- parte 00), as telas: Dashboard (parte que depende do mural), Pendencias,
-- Mural Interno (/feed), Plano de Acao (/plano-acao e detalhe), Usuarios,
-- Configuracoes (usuarios, perfis, auditoria, eSocial), Perfis de Acesso,
-- Meu Perfil, Meu Plano e Suporte.
-- A parte 06b (financeiro, beneficios e Hub Contabil) e independente desta.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, DEPOIS da parte 00. O arquivo se RECUSA
-- a rodar em qualquer outro banco (mesma trava da parte 00). Nunca na producao.
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, e-mails @metalurgica-exemplo.demo,
--     CPFs da faixa ficticia 900.000.0XX (public.demo_cpf), nenhuma conta de
--     login criada em auth.users.
--   - So toca o tenant de demonstracao. Nenhum UPDATE/DELETE fora dele; os
--     unicos UPDATEs sao: (a) preencher campos vazios do perfil do login demo e
--     (b) acertar status/progresso das acoes do plano de acao criadas aqui.
--   - Idempotente: ids fixos (public.demo_id) + "so insere se nao existe".
--   - Cada bloco roda isolado: se uma tabela da homologacao tiver estrutura
--     diferente da replica, o bloco avisa (NOTICE) e o resto segue.
--   - Roda numa transacao so; sem tabela temporaria; nenhuma tabela criada.
--
-- LIMITES CONHECIDOS (por que alguns itens ficam de fora)
--   - Participantes, autores de comentario e responsaveis do plano de acao tem
--     chave estrangeira para auth.users; como nao criamos logins, so o login demo
--     pode ser participante. Responsaveis aparecem pelo nome (campo texto).
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) Trava de ambiente (copia da parte 00): so homologacao ou teste
-- ---------------------------------------------------------------------------
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
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'RECUSADO: rode antes a parte 00 (tenant de demonstracao nao existe).';
  END IF;
END $trava$;

-- ---------------------------------------------------------------------------
-- (1) Assinatura: plano Enterprise ativo (Meu Plano e liberacao de todos os modulos)
-- ---------------------------------------------------------------------------
DO $s_assinatura$
BEGIN
  INSERT INTO public.subscriptions (
    id, tenant_id, plan_id, status, trial_ends_at, current_period_start, current_period_end,
    payment_confirmed, ciclo_meses, ciclo_inicio, ciclo_fim, setup_valor_cents,
    contrato_assinado_em, go_live_homologado_em
  )
  SELECT public.demo_id('subscription:1'), 'd3e00000-0000-4000-8000-000000000001', p.id, 'active', NULL,
         date_trunc('month', now()) - interval '5 months',
         date_trunc('month', now()) + interval '7 months',
         true, 12,
         (date_trunc('month', CURRENT_DATE) - interval '5 months')::date,
         (date_trunc('month', CURRENT_DATE) + interval '7 months' - interval '1 day')::date,
         1800000,
         (date_trunc('month', CURRENT_DATE) - interval '5 months')::date - 10,
         (date_trunc('month', CURRENT_DATE) - interval '4 months')::date
  FROM public.plans p
  WHERE p.code = 'enterprise'
    AND NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.tenant_id = 'd3e00000-0000-4000-8000-000000000001');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(1) assinatura nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_assinatura$;

-- ---------------------------------------------------------------------------
-- (2) Perfis de acesso: os 8 modelos do sistema viram perfis do tenant,
--     com as permissoes de cada modelo
-- ---------------------------------------------------------------------------
DO $s_perfis$
BEGIN
  INSERT INTO public.perfis_acesso (
    id, tenant_id, nome, descricao, icone, cor, template_origem_id, tipo, ativo, permite_acumulo,
    nivel_risco, tipo_usuario_sugerido, pode_ver_salario, criado_por_nome, created_at
  )
  SELECT public.demo_id('perfil:' || t.nome), 'd3e00000-0000-4000-8000-000000000001', t.nome, t.descricao, t.icone, t.cor,
         t.id, 'clonado', true,
         t.nome IN ('Gestor / Líder', 'Profissional SST / Clínica', 'Colaborador com Acesso'),
         CASE t.nome WHEN 'Administrador Master' THEN 'critico'
                     WHEN 'Financeiro / Administrativo' THEN 'elevado'
                     WHEN 'RH / Gestão de Pessoas' THEN 'elevado'
                     ELSE 'normal' END,
         t.tipo_usuario_sugerido,
         t.nome IN ('Administrador Master', 'RH / Gestão de Pessoas', 'Financeiro / Administrativo'),
         'Leiri', now() - interval '45 days'
  FROM public.perfil_templates t
  WHERE COALESCE(t.ativo, true)
    AND NOT EXISTS (SELECT 1 FROM public.perfis_acesso p
                    WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
                      AND (p.id = public.demo_id('perfil:' || t.nome) OR p.nome = t.nome));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2a) perfis nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_perfis$;

DO $s_perfis_perm$
BEGIN
  INSERT INTO public.perfil_permissoes (id, perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, is_sensivel)
  SELECT public.demo_id('perm:' || pa.id::text || ':' || (m.value ->> 'modulo') || ':' || a.value),
         pa.id, pa.tenant_id, m.value ->> 'modulo', NULLIF(m.value ->> 'recurso', ''),
         a.value::public.perfil_acao, (m.value ->> 'escopo')::public.perfil_escopo_tipo, true,
         a.value IN ('administrar', 'acessar_sensivel', 'ver_individual')
  FROM public.perfis_acesso pa
  JOIN public.perfil_templates t ON t.id = pa.template_origem_id
  CROSS JOIN LATERAL jsonb_array_elements(t.modulos_padrao) AS m(value)
  CROSS JOIN LATERAL jsonb_array_elements_text(m.value -> 'acoes') AS a(value)
  WHERE pa.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND pa.tipo = 'clonado'
    AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x WHERE x.perfil_id = pa.id);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(2b) permissoes dos perfis nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_perfis_perm$;

-- ---------------------------------------------------------------------------
-- (3) Usuarios do tenant (sem login real): varios tipos e situacoes
-- ---------------------------------------------------------------------------
DO $s_usuarios$
BEGIN
  INSERT INTO public.usuarios_base (
    id, tenant_id, nome_completo, cpf, email_principal, telefone_principal, data_nascimento, cargo_funcao,
    matricula, idioma, origem_cadastro, tipo_usuario, status, convite_enviado_em, convite_expira_em,
    convite_aceito_em, email_validado, telefone_validado, primeiro_acesso_em, ultimo_acesso_em,
    autenticacao_2fa, qualidade_score, qualidade_pct, alerta_duplicidade, duplicidade_nivel,
    criado_por_nome, created_at
  )
  SELECT public.demo_id('usuario:' || v.n), 'd3e00000-0000-4000-8000-000000000001',
         v.nome, public.demo_cpf(100 + v.n), v.email, '(47) 99100-' || lpad((v.n * 11)::text, 4, '0'),
         DATE '1970-03-10' + (v.n * 613), v.cargo, 'USR-' || lpad(v.n::text, 3, '0'), 'pt-BR', v.origem,
         v.tipo::public.usuario_tipo, v.status::public.usuario_status,
         CASE WHEN v.status IN ('convite_enviado', 'aguardando_ativacao') THEN now() - interval '3 days' END,
         CASE WHEN v.status IN ('convite_enviado', 'aguardando_ativacao') THEN now() + interval '4 days' END,
         CASE WHEN v.status = 'aguardando_ativacao' THEN now() - interval '1 day' END,
         v.status IN ('ativo', 'suspenso', 'bloqueado', 'inativo', 'arquivado'),
         v.status IN ('ativo', 'suspenso', 'bloqueado'),
         CASE WHEN v.status IN ('ativo', 'suspenso', 'bloqueado', 'inativo', 'arquivado') THEN now() - ((v.n * 9) || ' days')::interval END,
         CASE WHEN v.status = 'ativo' THEN now() - ((v.n % 5) || ' hours')::interval - ((v.n % 3) || ' days')::interval END,
         v.tipo IN ('administrador', 'rh_dp', 'corporativo_multiempresa'),
         v.score::public.qualidade_score, v.pct, v.dup, CASE WHEN v.dup THEN 'alto' END,
         'Leiri', now() - ((v.n * 6 + 20) || ' days')::interval
  FROM (VALUES
    (1,  'Ricardo Almeida Prado',      'ricardo.prado@metalurgica-exemplo.demo',      'Diretor Administrativo',          'administrador',            'ativo',               'manual',   'completo',     100, false),
    (2,  'Camila Fontes Barreto',      'camila.barreto@metalurgica-exemplo.demo',     'Analista de RH Sênior',           'rh_dp',                    'ativo',               'manual',   'completo',     100, false),
    (3,  'Henrique Duarte Lacerda',    'henrique.lacerda@metalurgica-exemplo.demo',   'Gerente Industrial',              'gestor',                   'ativo',               'manual',   'completo',     90,  false),
    (4,  'Fernanda Quintana Leal',     'fernanda.leal@metalurgica-exemplo.demo',      'Líder de Produção',               'lideranca',                'ativo',               'importacao', 'suficiente', 80,  false),
    (5,  'Marcos Vinícius Teles',      'marcos.teles@metalurgica-exemplo.demo',       'Técnico de Segurança do Trabalho','tecnico_seguranca',        'ativo',               'manual',   'completo',     90,  false),
    (6,  'Patrícia Nogueira Vidal',    'patricia.vidal@clinica-exemplo.demo',         'Médica do Trabalho (PCMSO)',      'saude_ocupacional',        'ativo',               'convite',  'suficiente', 80,  false),
    (7,  'Clínica Vida e Trabalho',    'contato@clinica-exemplo.demo',                'Clínica parceira de exames',      'clinica_parceira',         'ativo',               'convite',  'suficiente', 70,  false),
    (8,  'Eduardo Siqueira Matos',     'eduardo.matos@consultoria-exemplo.demo',      'Consultor de SST',                'consultor_externo',        'ativo',               'convite',  'suficiente', 70,  false),
    (9,  'Beatriz Campos Arruda',      'beatriz.arruda@auditoria-exemplo.demo',       'Auditora de conformidade',        'auditor',                  'convite_enviado',     'manual',   'incompleto',   50,  false),
    (10, 'Rafael Moreira Gouveia',     'rafael.gouveia@terceira-exemplo.demo',        'Supervisor da empresa terceira',  'prestador_terceiro',       'aguardando_ativacao', 'convite',  'incompleto',   50,  false),
    (11, 'Juliana Costa Peixoto',      'juliana.peixoto@metalurgica-exemplo.demo',    'Coordenadora de Qualidade',       'gestor',                   'pendente_convite',    'manual',   'incompleto',   40,  false),
    (12, 'Thiago Brito Rezende',       'thiago.rezende@metalurgica-exemplo.demo',     'Operador de Usinagem CNC',        'colaborador',              'bloqueado',           'importacao', 'suficiente', 70,  false),
    (13, 'Larissa Pires Esteves',      'larissa.esteves@metalurgica-exemplo.demo',    'Assistente de RH',                'rh_dp',                    'suspenso',            'manual',   'suficiente', 80,  false),
    (14, 'Wagner Ornelas Sampaio',     'wagner.sampaio@implantacao-exemplo.demo',     'Implantador YourEyes',            'implantador',              'inativo',             'convite',  'suficiente', 70,  false),
    (15, 'Simone Valente Toledo',      'simone.toledo@metalurgica-exemplo.demo',      'Controller (multiunidade)',       'corporativo_multiempresa', 'ativo',               'manual',   'completo',     100, false),
    (16, 'Gustavo Holanda Imbassahy',  'gustavo.imbassahy@metalurgica-exemplo.demo',  'Supervisor de Manutenção',        'gestor',                   'rascunho',            'manual',   'inconsistente',20,  false),
    (17, 'Débora Leme Dantas',         'debora.dantas@metalurgica-exemplo.demo',      'Analista Financeiro',             'colaborador',              'ativo',               'importacao', 'completo',     90,  false),
    (18, 'André Falcão Macedo',        'andre.macedo@metalurgica-exemplo.demo',       'Ex-gestor de Logística',          'gestor',                   'arquivado',           'manual',   'suficiente', 70,  false),
    (19, 'Ricardo A. Prado (duplicado)','ricardo.prado2@metalurgica-exemplo.demo',    'Diretor Administrativo',          'administrador',            'rascunho',            'importacao', 'inconsistente',30,  true)
  ) AS v(n, nome, email, cargo, tipo, status, origem, score, pct, dup)
  WHERE NOT EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.id = public.demo_id('usuario:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND lower(u.email_principal) = lower(v.email));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3a) usuarios nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_usuarios$;

-- Vinculos usuario <-> empresa (a tela Usuarios usa para o filtro de empresa e "multiempresa")
DO $s_usuarios_vinc$
BEGIN
  INSERT INTO public.usuario_vinculos (
    id, tenant_id, usuario_id, empresa_id, tipo_vinculo, contexto_operacional, unidade_filial,
    data_inicio, status, aprovado_por_nome, observacoes, created_at
  )
  SELECT public.demo_id('usuariovinc:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('usuario:' || v.n), 'd3e00000-0000-4000-8000-000000000002',
         COALESCE(v.tipo::public.usuario_tipo, u.tipo_usuario), v.contexto, v.unidade, CURRENT_DATE - v.dias, v.status::public.vinculo_status,
         'Leiri', v.obs, now() - (v.dias || ' days')::interval
  FROM (VALUES
    (1,  1, 'Diretoria',                  'Matriz',                    300, 'ativo',     'Responsável legal da unidade', NULL),
    (2,  1, 'Departamento Pessoal e RH',  'Matriz',                    280, 'ativo',     NULL, NULL),
    (3,  1, 'Gestão industrial',          'Matriz',                    260, 'ativo',     NULL, NULL),
    (4,  1, 'Chão de fábrica - Turno A',  'Matriz',                    200, 'ativo',     NULL, NULL),
    (5,  1, 'SESMT',                      'Matriz',                    240, 'ativo',     'Atende também a filial Curitiba', NULL),
    (6,  1, 'PCMSO',                      'Matriz',                    180, 'ativo',     'Contrato de prestação de serviços de saúde ocupacional', NULL),
    (7,  1, 'Exames ocupacionais',        'Matriz',                    150, 'ativo',     NULL, NULL),
    (8,  1, 'Consultoria em SST',         'Matriz',                    120, 'ativo',     'Vínculo por projeto (NR-1 e GRO)', NULL),
    (9,  1, 'Auditoria interna',          'Matriz',                     5,  'pendente',  'Aguardando aceite do convite', NULL),
    (10, 1, 'Terceirizada de manutenção', 'Matriz',                     3,  'pendente',  'Aguardando ativação da conta', NULL),
    (11, 1, 'Qualidade',                  'Matriz',                     0,  'pendente',  NULL, NULL),
    (12, 1, 'Produção',                   'Matriz',                    400, 'suspenso',  'Acesso bloqueado após tentativas inválidas', NULL),
    (13, 1, 'Departamento Pessoal e RH',  'Matriz',                    350, 'suspenso',  'Afastamento temporário', NULL),
    (14, 1, 'Implantação do sistema',     'Matriz',                    170, 'encerrado', 'Projeto de implantação concluído', NULL),
    (15, 1, 'Controladoria',              'Matriz',                    330, 'ativo',     NULL, NULL),
    (15, 2, 'Controladoria',              'Filial Curitiba',           330, 'ativo',     'Atua também na filial', 'gestor'),
    (15, 3, 'Controladoria',              'Centro de Distribuição Itajaí', 330, 'ativo', 'Atua também no centro de distribuição', 'lideranca'),
    (17, 1, 'Financeiro',                 'Matriz',                    220, 'ativo',     NULL, NULL),
    (18, 1, 'Logística',                  'Matriz',                    500, 'encerrado', 'Desligado da função de gestão', NULL)
  ) AS v(n, seq, contexto, unidade, dias, status, obs, tipo)
  JOIN public.usuarios_base u ON u.id = public.demo_id('usuario:' || v.n)
  WHERE NOT EXISTS (SELECT 1 FROM public.usuario_vinculos x WHERE x.id = public.demo_id('usuariovinc:' || v.n || ':' || v.seq));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3b) vinculos de usuario nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_usuarios_vinc$;

-- Perfil de acesso de cada usuario (o vinculo automatico do modelo e substituido pelo perfil escolhido)
DO $s_usuarios_perfil$
BEGIN
  INSERT INTO public.usuario_perfil_vinculos (
    id, tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal, atribuido_por_nome, observacao, created_at
  )
  SELECT public.demo_id('usuarioperfil:' || v.n), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('usuario:' || v.n), pa.id, v.n NOT IN (14, 18), true, 'Leiri',
         'Perfil atribuído na implantação', now() - ((v.n * 6 + 15) || ' days')::interval
  FROM (VALUES
    (1, 'Administrador Master'), (2, 'RH / Gestão de Pessoas'), (3, 'Gestor / Líder'), (4, 'Gestor / Líder'),
    (5, 'Profissional SST / Clínica'), (6, 'Profissional SST / Clínica'), (7, 'Profissional SST / Clínica'),
    (8, 'Consultor Externo'), (9, 'Auditor'), (11, 'Gestor / Líder'), (12, 'Colaborador com Acesso'),
    (13, 'RH / Gestão de Pessoas'), (14, 'Consultor Externo'), (15, 'Financeiro / Administrativo'),
    (16, 'Gestor / Líder'), (17, 'Colaborador com Acesso'), (18, 'Gestor / Líder')
  ) AS v(n, perfil)
  JOIN public.perfis_acesso pa ON pa.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND pa.nome = v.perfil
  WHERE EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.id = public.demo_id('usuario:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x WHERE x.id = public.demo_id('usuarioperfil:' || v.n));

  -- O login demo (administrador) recebe o perfil Administrador Master
  INSERT INTO public.usuario_perfil_vinculos (
    id, tenant_id, usuario_id, perfil_id, ativo, is_perfil_principal, atribuido_por_nome, observacao, created_at
  )
  SELECT public.demo_id('usuarioperfil:login-demo'), 'd3e00000-0000-4000-8000-000000000001', ub.id, pa.id, true, true,
         'Sistema', 'Perfil principal do administrador da demonstração', now() - interval '40 days'
  FROM public.usuarios_base ub
  JOIN public.perfis_acesso pa ON pa.tenant_id = ub.tenant_id AND pa.nome = 'Administrador Master'
  WHERE ub.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND ub.auth_user_id IN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com')
    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x WHERE x.id = public.demo_id('usuarioperfil:login-demo'))
    AND NOT EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos x WHERE x.usuario_id = ub.id AND x.perfil_id = pa.id);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3c) perfis dos usuarios nao vinculados: % (%)', SQLERRM, SQLSTATE;
END $s_usuarios_perfil$;

-- Completa os dados do proprio login demo (so campos ainda vazios)
DO $s_login$
BEGIN
  UPDATE public.usuarios_base u
     SET telefone_principal = COALESCE(NULLIF(u.telefone_principal, ''), '(47) 99100-0001'),
         data_nascimento    = COALESCE(u.data_nascimento, DATE '1984-06-18'),
         nome_completo      = CASE WHEN u.nome_completo = 'Leiri' THEN 'Leiri Nuernberg' ELSE u.nome_completo END,
         matricula          = COALESCE(NULLIF(u.matricula, ''), 'USR-000'),
         email_validado     = true,
         telefone_validado  = true,
         primeiro_acesso_em = COALESCE(u.primeiro_acesso_em, now() - interval '40 days'),
         ultimo_acesso_em   = COALESCE(u.ultimo_acesso_em, now() - interval '1 hour'),
         autenticacao_2fa   = true,
         qualidade_score    = 'completo',
         qualidade_pct      = 100
   WHERE u.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     AND u.auth_user_id IN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com')
     AND (u.qualidade_pct IS NULL OR u.qualidade_pct < 100);

  UPDATE public.profiles p
     SET cargo = COALESCE(NULLIF(p.cargo, ''), 'Gestora de RH'),
         telefone = COALESCE(NULLIF(p.telefone, ''), '(47) 99100-0001'),
         nome_completo = CASE WHEN p.nome_completo = 'Leiri' THEN 'Leiri Nuernberg' ELSE p.nome_completo END
   WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     AND p.user_id IN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com');

  INSERT INTO public.usuario_vinculos (id, tenant_id, usuario_id, empresa_id, tipo_vinculo, contexto_operacional, unidade_filial,
                                       data_inicio, status, aprovado_por_nome, created_at)
  SELECT public.demo_id('usuariovinc:login-demo'), ub.tenant_id, ub.id, 'd3e00000-0000-4000-8000-000000000002',
         ub.tipo_usuario, 'Gestão de RH e administração do sistema', 'Matriz', CURRENT_DATE - 45, 'ativo', 'Sistema', now() - interval '45 days'
  FROM public.usuarios_base ub
  WHERE ub.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND ub.auth_user_id IN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com')
    AND NOT EXISTS (SELECT 1 FROM public.usuario_vinculos x WHERE x.id = public.demo_id('usuariovinc:login-demo'))
    AND NOT EXISTS (SELECT 1 FROM public.usuario_vinculos x WHERE x.usuario_id = ub.id);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3d) dados do login demo nao completados: % (%)', SQLERRM, SQLSTATE;
END $s_login$;

-- Historico de acoes sobre usuarios (aba "Logs" do detalhe do usuario)
DO $s_usuarios_log$
BEGIN
  INSERT INTO public.usuario_audit_log (id, tenant_id, usuario_id, acao, objeto, valor_anterior, valor_novo, justificativa, executor_nome, origem, created_at)
  SELECT public.demo_id('usuariolog:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('usuario:' || v.n), v.acao, v.objeto,
         CASE WHEN v.ant IS NOT NULL THEN jsonb_build_object('valor', v.ant) END,
         CASE WHEN v.novo IS NOT NULL THEN jsonb_build_object('valor', v.novo) END,
         v.just, 'Leiri Nuernberg', 'manual', now() - (v.dias || ' days')::interval
  FROM (VALUES
    (1,  1, 'usuario_criado',        'usuario', NULL,        'administrador',       NULL, 300),
    (1,  2, 'perfil_atribuido',      'perfil',  NULL,        'Administrador Master', NULL, 299),
    (2,  1, 'usuario_criado',        'usuario', NULL,        'rh_dp',               NULL, 280),
    (2,  2, 'convite_aceito',        'usuario', 'convite_enviado', 'ativo',         NULL, 278),
    (3,  1, 'usuario_criado',        'usuario', NULL,        'gestor',              NULL, 260),
    (4,  1, 'tipo_alterado',         'usuario', 'gestor',    'lideranca',           'Promovida a líder do turno A', 150),
    (5,  1, 'usuario_criado',        'usuario', NULL,        'tecnico_seguranca',   NULL, 240),
    (6,  1, 'convite_enviado',       'usuario', NULL,        'convite_enviado',     'Médica coordenadora do PCMSO', 182),
    (6,  2, 'convite_aceito',        'usuario', 'convite_enviado', 'ativo',         NULL, 180),
    (9,  1, 'convite_enviado',       'usuario', NULL,        'convite_enviado',     'Auditoria de conformidade agendada', 3),
    (10, 1, 'convite_enviado',       'usuario', NULL,        'convite_enviado',     NULL, 6),
    (10, 2, 'convite_aceito',        'usuario', 'convite_enviado', 'aguardando_ativacao', NULL, 3),
    (11, 1, 'usuario_criado',        'usuario', NULL,        'pendente_convite',    NULL, 1),
    (12, 1, 'usuario_bloqueado',     'usuario', 'ativo',     'bloqueado',           'Cinco tentativas de acesso inválidas', 12),
    (13, 1, 'usuario_suspenso',      'usuario', 'ativo',     'suspenso',            'Licença-maternidade', 60),
    (14, 1, 'vinculo_encerrado',     'vinculo', 'ativo',     'encerrado',           'Projeto de implantação concluído', 45),
    (14, 2, 'usuario_inativado',     'usuario', 'ativo',     'inativo',             NULL, 44),
    (15, 1, 'vinculo_adicionado',    'vinculo', NULL,        'Filial Curitiba',     'Atuação multiunidade', 200),
    (15, 2, 'vinculo_adicionado',    'vinculo', NULL,        'Centro de Distribuição Itajaí', 'Atuação multiunidade', 198),
    (18, 1, 'usuario_arquivado',     'usuario', 'inativo',   'arquivado',           'Desligado da empresa', 90),
    (19, 1, 'duplicidade_detectada', 'usuario', NULL,        'Ricardo Almeida Prado', 'Mesmo nome e cargo de usuário já cadastrado', 2)
  ) AS v(n, seq, acao, objeto, ant, novo, just, dias)
  WHERE EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.id = public.demo_id('usuario:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.usuario_audit_log x WHERE x.id = public.demo_id('usuariolog:' || v.n || ':' || v.seq));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3e) log de usuarios nao semeado: % (%)', SQLERRM, SQLSTATE;
END $s_usuarios_log$;

-- Historico dos perfis (aba "Auditoria" de Perfis de Acesso)
DO $s_perfil_log$
BEGIN
  INSERT INTO public.perfil_audit_log (id, tenant_id, perfil_id, acao, descricao, dados_novos, realizado_por_nome, created_at)
  SELECT public.demo_id('perfillog:' || pa.nome || ':clonagem'), pa.tenant_id, pa.id, 'clonagem',
         'Modelo "' || pa.nome || '" clonado como perfil da empresa', jsonb_build_object('template_id', pa.template_origem_id),
         'Leiri Nuernberg', pa.created_at
  FROM public.perfis_acesso pa
  WHERE pa.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND pa.tipo = 'clonado'
    AND NOT EXISTS (SELECT 1 FROM public.perfil_audit_log x WHERE x.id = public.demo_id('perfillog:' || pa.nome || ':clonagem'));

  INSERT INTO public.perfil_audit_log (id, tenant_id, perfil_id, usuario_alvo_id, acao, descricao, dados_novos, realizado_por_nome, created_at)
  SELECT public.demo_id('perfillog:vinculo:' || v.id::text), v.tenant_id, v.perfil_id, v.usuario_id, 'vinculacao',
         'Perfil "' || pa.nome || '" vinculado a ' || ub.nome_completo, jsonb_build_object('perfil', pa.nome),
         'Leiri Nuernberg', v.created_at
  FROM public.usuario_perfil_vinculos v
  JOIN public.perfis_acesso pa ON pa.id = v.perfil_id AND pa.tipo = 'clonado'
  JOIN public.usuarios_base ub ON ub.id = v.usuario_id
  WHERE v.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND NOT EXISTS (SELECT 1 FROM public.perfil_audit_log x WHERE x.id = public.demo_id('perfillog:vinculo:' || v.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(3f) log de perfis nao semeado: % (%)', SQLERRM, SQLSTATE;
END $s_perfil_log$;

-- ---------------------------------------------------------------------------
-- (4) Configuracoes: trilha de auditoria geral e certificado eSocial (ficticio)
-- ---------------------------------------------------------------------------
DO $s_auditoria$
BEGIN
  INSERT INTO public.audit_logs (id, tenant_id, user_id, user_name, user_email, action, module, description, target_type, target_name, metadata, created_at)
  SELECT public.demo_id('auditlog:' || g.n), 'd3e00000-0000-4000-8000-000000000001',
         CASE WHEN a.quem = 0 THEN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE a.quem WHEN 0 THEN 'Leiri Nuernberg' WHEN 1 THEN 'Camila Fontes Barreto'
                     WHEN 2 THEN 'Henrique Duarte Lacerda' ELSE 'Marcos Vinícius Teles' END,
         CASE a.quem WHEN 0 THEN 'leirinuernberg@gmail.com' WHEN 1 THEN 'camila.barreto@metalurgica-exemplo.demo'
                     WHEN 2 THEN 'henrique.lacerda@metalurgica-exemplo.demo' ELSE 'marcos.teles@metalurgica-exemplo.demo' END,
         a.acao, a.modulo, a.descr, a.alvo_tipo, a.alvo_nome,
         jsonb_build_object('origem', 'demonstracao'),
         now() - ((g.n * 17) || ' hours')::interval - ((g.n % 7) || ' minutes')::interval
  FROM generate_series(1, 48) AS g(n)
  JOIN (VALUES
    (1,  0, 'user.invited',          'equipe',        'Convite de acesso enviado',               'usuário',   'Beatriz Campos Arruda'),
    (2,  1, 'admissao.created',      'admissoes',     'Nova admissão cadastrada',                'admissão',  'Vendedor Interno'),
    (3,  0, 'config.updated',        'configuracoes', 'Parâmetros da empresa atualizados',       'empresa',   'Metalúrgica Exemplo'),
    (4,  2, 'ponto.ajuste_aprovado', 'ponto',         'Ajuste de ponto aprovado',                'ajuste',    'Operador de Usinagem CNC'),
    (5,  1, 'ferias.aprovadas',      'ferias',        'Solicitação de férias aprovada',          'férias',    'Soldador'),
    (6,  0, 'user.role_updated',     'equipe',        'Perfil de acesso alterado',               'usuário',   'Fernanda Quintana Leal'),
    (7,  3, 'atestado.registrado',   'atestados',     'Atestado médico registrado',              'atestado',  'Auxiliar de Logística'),
    (8,  2, 'beneficio.vinculado',   'beneficios',    'Benefício vinculado ao colaborador',      'benefício', 'Vale Alimentação'),
    (9,  0, 'sst.documento_emitido', 'sst',           'Documento de SST emitido',                'documento', 'PCMSO anual'),
    (10, 1, 'trilha.atribuida',      'trilhas',       'Trilha de integração atribuída',          'trilha',    'Integração de novos colaboradores'),
    (11, 0, 'avaliacao.ciclo_aberto','avaliacoes',    'Ciclo de avaliação de desempenho aberto', 'ciclo',     'Avaliação semestral'),
    (12, 2, 'user.invite_resent',    'equipe',        'Convite de acesso reenviado',             'usuário',   'Rafael Moreira Gouveia')
  ) AS a(idx, quem, acao, modulo, descr, alvo_tipo, alvo_nome) ON a.idx = ((g.n - 1) % 12) + 1
  WHERE NOT EXISTS (SELECT 1 FROM public.audit_logs x WHERE x.id = public.demo_id('auditlog:' || g.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(4a) auditoria nao semeada: % (%)', SQLERRM, SQLSTATE;
END $s_auditoria$;

-- Certificado digital do eSocial (ficticio: sem arquivo e sem senha; so para a lista aparecer)
DO $s_esocial_cert$
BEGIN
  INSERT INTO public.esocial_certificados (
    id, tenant_id, empresa_id, cnpj, nome_empresa, tipo, certificado_path, certificado_nome,
    validade, ambiente, ativo, criado_por_nome, created_at
  )
  SELECT public.demo_id('esocialcert:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         '98.765.432/0001-02', 'Metalúrgica Exemplo Ltda', 'propria', 'demo/certificado-ficticio-a1.pfx',
         'certificado-a1-ficticio.pfx', CURRENT_DATE + 210, 'homologacao', true, 'Leiri Nuernberg', now() - interval '60 days'
  WHERE NOT EXISTS (SELECT 1 FROM public.esocial_certificados x WHERE x.id = public.demo_id('esocialcert:1'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(4b) certificado eSocial nao semeado: % (%)', SQLERRM, SQLSTATE;
END $s_esocial_cert$;

-- ---------------------------------------------------------------------------
-- (5) Suporte: chamados abertos, em andamento, resolvidos e fechados
-- ---------------------------------------------------------------------------
DO $s_suporte$
BEGIN
  INSERT INTO public.suporte_tickets (
    id, tenant_id, titulo, descricao, tipo, status, prioridade, modulo, criado_por, criado_por_nome,
    atribuido_a_nome, resolucao, resolvido_em, created_at, updated_at
  )
  SELECT public.demo_id('ticket:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.titulo, v.descr,
         v.tipo::public.ticket_tipo, v.status::public.ticket_status, v.prio::public.ticket_prioridade, v.modulo,
         CASE WHEN v.quem = 0 THEN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE v.quem WHEN 0 THEN 'Leiri Nuernberg' WHEN 1 THEN 'Camila Fontes Barreto' ELSE 'Marcos Vinícius Teles' END,
         CASE WHEN v.status <> 'aberto' THEN 'Equipe de Suporte YourEyes' END,
         v.resolucao,
         CASE WHEN v.resolucao IS NOT NULL THEN now() - ((v.dias - v.dur) || ' days')::interval END,
         now() - (v.dias || ' days')::interval,
         now() - (GREATEST(v.dias - v.dur, 0) || ' days')::interval
  FROM (VALUES
    (1,  'Relatório de espelho de ponto não exporta em PDF no Chrome', 'Ao clicar em Exportar PDF no espelho de ponto, a página fica carregando e nada é baixado. Acontece no Chrome atualizado.', 'bug', 'aberto', 'alta', 'ponto', 0, 1, 0, NULL),
    (2,  'Dúvida sobre o cálculo do 13º para quem teve afastamento', 'Como o sistema considera os meses de afastamento por doença na contagem de avos do 13º salário?', 'duvida', 'em_analise', 'media', 'financeiro', 1, 3, 0, NULL),
    (3,  'Lentidão ao abrir a folha de uma competência com muitos colaboradores', 'A tela de folha de pagamento demora cerca de 20 segundos para listar os itens quando a competência tem mais de 60 colaboradores.', 'falha', 'em_andamento', 'alta', 'financeiro', 0, 4, 0, NULL),
    (4,  'Sugestão: filtro por filial na lista de colaboradores', 'Seria útil filtrar a lista de colaboradores por filial, pois o RH da Filial Curitiba acompanha só o seu pessoal.', 'sugestao', 'resolvido', 'media', 'colaboradores', 1, 18, 9, 'Filtro por unidade disponibilizado na lista de colaboradores na atualização de setembro.'),
    (5,  'Como cadastrar um novo benefício para um grupo de colaboradores?', 'Preciso vincular o seguro de vida a todos os soldadores. Existe forma de fazer em lote?', 'duvida', 'resolvido', 'baixa', 'beneficios', 2, 25, 24, 'Orientado a usar o vínculo individual por enquanto; o vínculo em lote está no roteiro de evolução.'),
    (6,  'Erro ao assinar documento eletrônico com certificado', 'Ao concluir a assinatura do termo de benefício, aparece mensagem de erro genérica e o documento volta para pendente.', 'falha', 'fechado', 'critica', 'documentos', 0, 32, 30, 'Falha corrigida na versão seguinte; documentos pendentes foram reprocessados pelo suporte.'),
    (7,  'Exportar o plano de ação para Excel', 'Gostaríamos de exportar a lista de ações com prazo e responsável para apresentar na reunião de diretoria.', 'sugestao', 'aberto', 'baixa', 'plano-acao', 0, 6, 0, NULL),
    (8,  'E-mail de convite de usuário cai na caixa de spam', 'Os convites enviados para usuários de provedores gratuitos estão chegando como spam.', 'reclamacao', 'em_andamento', 'media', 'usuarios', 1, 8, 0, NULL),
    (9,  'ASO emitido com a data de exame incorreta', 'O ASO gerado para um colaborador saiu com a data do dia seguinte ao exame realizado.', 'bug', 'resolvido', 'alta', 'saude-ocupacional', 2, 40, 37, 'Ajustado o fuso horário na emissão do ASO. Documento reemitido com a data correta.'),
    (10, 'Chamado duplicado sobre o espelho de ponto', 'Aberto por engano; o mesmo assunto já está no chamado sobre exportação de PDF.', 'duvida', 'cancelado', 'baixa', 'ponto', 1, 2, 1, NULL),
    (11, 'Competência não foi enviada ao Hub Contábil', 'A competência do mês anterior ficou como pronta para envio, mas a contabilidade informa que não recebeu o pacote.', 'falha', 'aberto', 'critica', 'hub-contabil', 0, 0, 0, NULL)
  ) AS v(n, titulo, descr, tipo, status, prio, modulo, quem, dias, dur, resolucao)
  WHERE NOT EXISTS (SELECT 1 FROM public.suporte_tickets x WHERE x.id = public.demo_id('ticket:' || v.n));

  INSERT INTO public.suporte_ticket_comentarios (id, tenant_id, ticket_id, autor_id, autor_nome, conteudo, created_at)
  SELECT public.demo_id('ticketcom:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('ticket:' || v.n),
         CASE WHEN v.quem = 0 THEN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE WHEN v.quem = 0 THEN 'Leiri Nuernberg' ELSE 'Equipe de Suporte YourEyes' END,
         v.texto, now() - (v.horas || ' hours')::interval
  FROM (VALUES
    (2, 1, 1, 'O sistema considera os meses em que o colaborador trabalhou 15 dias ou mais. Estamos validando a regra de afastamento previdenciário com o time de folha.', 60),
    (2, 2, 0, 'Obrigada! Pode me confirmar se a política da empresa pode ser configurada nas opções do 13º salário?', 50),
    (3, 1, 1, 'Reproduzimos a lentidão em ambiente de teste. A equipe técnica está otimizando a consulta de itens da folha.', 72),
    (3, 2, 0, 'Perfeito, aguardamos. Para a demonstração aos sócios, qual a previsão?', 60),
    (3, 3, 1, 'Previsão de correção na próxima atualização semanal.', 40),
    (4, 1, 1, 'Sugestão registrada e aprovada pelo time de produto.', 400),
    (4, 2, 1, 'Funcionalidade disponibilizada. Pode validar na lista de colaboradores?', 220),
    (4, 3, 0, 'Validado, funcionando muito bem. Obrigada!', 215),
    (6, 1, 1, 'Identificamos a causa: validação do certificado em fuso horário incorreto. Correção em andamento.', 750),
    (6, 2, 1, 'Correção publicada e documentos pendentes reprocessados. Podemos fechar o chamado?', 725),
    (6, 3, 0, 'Pode fechar. Tudo certo agora.', 720),
    (8, 1, 1, 'Orientamos cadastrar o remetente do YourEyes na lista de contatos confiáveis do provedor. Estamos avaliando a configuração de SPF e DKIM.', 150),
    (9, 1, 1, 'Ajuste aplicado. Os ASOs já emitidos foram revisados e reemitidos quando necessário.', 880)
  ) AS v(n, seq, quem, texto, horas)
  WHERE EXISTS (SELECT 1 FROM public.suporte_tickets t WHERE t.id = public.demo_id('ticket:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.suporte_ticket_comentarios x WHERE x.id = public.demo_id('ticketcom:' || v.n || ':' || v.seq));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(5) suporte nao semeado: % (%)', SQLERRM, SQLSTATE;
END $s_suporte$;

-- ---------------------------------------------------------------------------
-- (6) Mural interno (feed): publicacoes, comentarios, reacoes e lembretes
-- ---------------------------------------------------------------------------
DO $s_feed$
BEGIN
  INSERT INTO public.feed_posts (id, tenant_id, autor_id, autor_nome, tipo, conteudo, fixado, created_at, updated_at)
  SELECT public.demo_id('feedpost:' || v.n), 'd3e00000-0000-4000-8000-000000000001',
         CASE WHEN v.autor = 0 THEN COALESCE((SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1), public.demo_id('usuario:2'))
              ELSE public.demo_id('admissao:' || v.autor) END,
         CASE WHEN v.autor = 0 THEN 'Leiri Nuernberg' ELSE a.nome_completo END,
         v.tipo, v.conteudo, v.fixado, now() - (v.horas || ' hours')::interval, now() - (v.horas || ' hours')::interval
  FROM (VALUES
    (1,  'anuncio',     true,  0,  120, '📢 Comunicado: a SIPAT 2026 (Semana Interna de Prevenção de Acidentes de Trabalho) acontece de ' || to_char(CURRENT_DATE + 20, 'DD/MM') || ' a ' || to_char(CURRENT_DATE + 24, 'DD/MM') || '. Teremos palestras, simulado de emergência, ginástica laboral e sorteio de brindes. A participação é obrigatória para todos os turnos; a escala de liberação será divulgada pelos líderes.'),
    (2,  'aviso',       false, 0,  50,  '⚠️ Aviso importante: o uso do protetor auricular é obrigatório em toda a área de usinagem e solda. A fiscalização interna será reforçada a partir desta semana. Em caso de dúvida ou de EPI danificado, procure o almoxarifado ou a equipe de Segurança do Trabalho.'),
    (3,  'anuncio',     false, 0,  216, '🕒 Banco de horas: a nova política foi aprovada em acordo coletivo e passa a valer no próximo mês. O saldo individual poderá ser consultado no menu Ponto. O RH fará duas sessões de esclarecimento no refeitório.'),
    (4,  'post',        false, 58, 3,   'Bom dia, pessoal! Hoje começa a campanha de vacinação contra a gripe no ambulatório, das 8h às 16h. Levem o cartão de vacina. 💉'),
    (5,  'post',        false, 12, 26,  '🎉 A equipe de Usinagem fechou o mês com zero retrabalho nas peças da linha 2! Obrigado a todos pelo cuidado e pela parceria com a Qualidade.'),
    (6,  'aniversario', false, 0,  75,  '🎂 Parabéns a todos os aniversariantes deste mês! Que venha um novo ciclo de saúde, conquistas e muita alegria. Confira a lista ao lado.'),
    (7,  'tempo_casa',  false, 0,  300, '🏆 Homenagem de tempo de casa: agradecemos a cada pessoa que constrói a Metalúrgica Exemplo todos os dias. Neste mês, comemoramos mais um ano de parceria com colegas de todos os setores.'),
    (8,  'post',        false, 30, 96,  'Manutenção preventiva da linha 2 concluída com sucesso: trocamos rolamentos, revisamos o sistema hidráulico e atualizamos o plano de lubrificação. Qualquer ruído anormal, avisem o time da Manutenção.'),
    (9,  'post',        false, 46, 150, 'Campanha do agasalho: arrecadamos mais de 300 peças! A entrega à comunidade acontece na sexta. Obrigado a todos que contribuíram. ❤️'),
    (10, 'post',        false, 59, 170, 'Lembrete: atualização cadastral dos colaboradores até o fim do mês. Conferir endereço, telefone e dependentes no menu Meu Perfil. Qualquer dúvida, falem com o RH.'),
    (11, 'post',        false, 41, 270, 'Turma de NR-11 concluída: 12 operadores de empilhadeira receberam a certificação. Parabéns aos participantes e ao instrutor! 🚜'),
    (12, 'anuncio',     false, 0,  340, '📊 Resultado da pesquisa de clima: 87% de satisfação geral, com destaque para o relacionamento com as lideranças. As oportunidades de melhoria (comunicação entre turnos e plano de carreira) já viraram ações no Plano de Ação.'),
    (13, 'post',        false, 53, 400, 'Dica do Financeiro: os informes de rendimentos e holerites ficam disponíveis no sistema. Se encontrar qualquer divergência, procure o RH com antecedência.'),
    (14, 'post',        false, 22, 480, 'Obrigado a todos pela ajuda no mutirão de 5S do galpão de montagem! O setor ficou muito mais organizado e seguro. 🧹')
  ) AS v(n, tipo, fixado, autor, horas, conteudo)
  LEFT JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.autor)
  WHERE NOT EXISTS (SELECT 1 FROM public.feed_posts x WHERE x.id = public.demo_id('feedpost:' || v.n));

  -- Reacoes: 3 a 8 colegas por publicacao
  INSERT INTO public.feed_reacoes (id, tenant_id, post_id, user_id, user_nome, tipo, created_at)
  SELECT public.demo_id('feedreacao:' || p.n || ':' || k.k), 'd3e00000-0000-4000-8000-000000000001',
         public.demo_id('feedpost:' || p.n), a.id, a.nome_completo,
         (ARRAY['curtir','amei','parabens','apoio','inspirador'])[1 + ((p.n + k.k) % 5)],
         fp.created_at + (k.k || ' hours')::interval
  FROM generate_series(1, 14) AS p(n)
  CROSS JOIN LATERAL generate_series(1, 3 + (p.n % 6)) AS k(k)
  JOIN public.feed_posts fp ON fp.id = public.demo_id('feedpost:' || p.n)
  JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || (1 + ((p.n * 7 + k.k * 5) % 56)))
  WHERE NOT EXISTS (SELECT 1 FROM public.feed_reacoes x WHERE x.id = public.demo_id('feedreacao:' || p.n || ':' || k.k))
    AND NOT EXISTS (SELECT 1 FROM public.feed_reacoes x WHERE x.post_id = fp.id AND x.user_id = a.id);

  -- Reacao do login demo em publicacoes pares
  INSERT INTO public.feed_reacoes (id, tenant_id, post_id, user_id, user_nome, tipo, created_at)
  SELECT public.demo_id('feedreacao:login:' || p.n), 'd3e00000-0000-4000-8000-000000000001', fp.id, u.id, 'Leiri Nuernberg',
         'curtir', fp.created_at + interval '30 minutes'
  FROM generate_series(1, 14) AS p(n)
  JOIN public.feed_posts fp ON fp.id = public.demo_id('feedpost:' || p.n)
  CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
  WHERE p.n % 2 = 0
    AND NOT EXISTS (SELECT 1 FROM public.feed_reacoes x WHERE x.id = public.demo_id('feedreacao:login:' || p.n))
    AND NOT EXISTS (SELECT 1 FROM public.feed_reacoes x WHERE x.post_id = fp.id AND x.user_id = u.id);

  -- Comentarios: 0 a 3 por publicacao
  INSERT INTO public.feed_comentarios (id, tenant_id, post_id, autor_id, autor_nome, conteudo, created_at)
  SELECT public.demo_id('feedcom:' || p.n || ':' || c.c), 'd3e00000-0000-4000-8000-000000000001',
         fp.id, a.id, a.nome_completo,
         (ARRAY['Parabéns a todos! 👏', 'Ótima iniciativa, conte comigo.', 'Obrigado pela informação!', 'Isso mostra como o trabalho em equipe faz diferença.',
                'Podem contar com o nosso turno.', 'Excelente! Vamos manter o ritmo.'])[1 + ((p.n + c.c) % 6)],
         fp.created_at + ((c.c * 2) || ' hours')::interval
  FROM generate_series(1, 14) AS p(n)
  CROSS JOIN LATERAL generate_series(1, p.n % 4) AS c(c)
  JOIN public.feed_posts fp ON fp.id = public.demo_id('feedpost:' || p.n)
  JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || (1 + ((p.n * 11 + c.c * 13) % 56)))
  WHERE NOT EXISTS (SELECT 1 FROM public.feed_comentarios x WHERE x.id = public.demo_id('feedcom:' || p.n || ':' || c.c));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(6a) mural nao semeado: % (%)', SQLERRM, SQLSTATE;
END $s_feed$;

-- Lembretes do mural (acoes de cultura pendentes aparecem no quadro lateral)
DO $s_feed_lembretes$
BEGIN
  INSERT INTO public.cultura_acoes (
    id, tenant_id, empresa_id, tipo, titulo, descricao, colaborador_nome, data_referencia, responsavel_nome, status, observacoes, created_at
  )
  SELECT public.demo_id('culturaacao:feed:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
         v.tipo, v.titulo, v.descr, v.colab, CURRENT_DATE + v.dias, 'Camila Fontes Barreto', v.status, v.obs, now() - interval '10 days'
  FROM (VALUES
    (1, 'ritual',            'Café com a diretoria - turno B',          'Encontro mensal da diretoria com o turno B para ouvir sugestões.', NULL,                'pendente',     2,  NULL),
    (2, 'data_configurada',  'Dia da Segurança do Trabalho',            'Ação de conscientização com a equipe de Produção e Manutenção.',   NULL,                'em_andamento', 6,  'Brindes e cartazes já providenciados.'),
    (3, 'ritual',            'Reconhecimento: melhor ideia do trimestre','Entrega do certificado ao colaborador autor da melhor sugestão de melhoria.', 'Equipe de Usinagem','pendente',     9,  NULL),
    (4, 'tempo_casa',        'Homenagem de 5 anos de empresa',          'Entregar lembrança e cartão assinado pela diretoria.',             'Líder de Produção', 'pendente',     14, NULL)
  ) AS v(n, tipo, titulo, descr, colab, status, dias, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.cultura_acoes x WHERE x.id = public.demo_id('culturaacao:feed:' || v.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(6b) lembretes do mural nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_feed_lembretes$;

-- ---------------------------------------------------------------------------
-- (7) Pendencias: duplicidades na importacao de empresas (as demais pendencias
--     do painel nascem de ferias, ponto, avaliacoes, documentos e saude)
-- ---------------------------------------------------------------------------
DO $s_pendencias$
BEGIN
  INSERT INTO public.empresa_import_pendencias (
    id, tenant_id, cnpj, razao_social_planilha, razao_social_existente, empresa_existente_id, linha_planilha,
    arquivo_nome, motivo, status, importado_por_nome, created_at
  )
  SELECT public.demo_id('empimport:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.cnpj, v.razao, v.existente,
         CASE WHEN v.motivo = 'cnpj_ja_cadastrado' THEN 'd3e00000-0000-4000-8000-000000000002'::uuid END,
         v.linha, 'empresas-grupo-exemplo.xlsx', v.motivo, v.status, 'Leiri Nuernberg', now() - (v.dias || ' days')::interval
  FROM (VALUES
    (1, '98.765.432/0002-93', 'Metalúrgica Exemplo Filial Curitiba',  'Filial Curitiba',           4, 'cnpj_ja_cadastrado',      'pendente', 3),
    (2, '12.345.678/0001-95', 'Transportadora Exemplo Ltda',         NULL,                        7, 'cnpj_repetido_planilha',  'pendente', 3),
    (3, '12.345.678/0001-95', 'Transportadora Exemplo (duplicada)',  NULL,                        9, 'cnpj_repetido_planilha',  'pendente', 3),
    (4, '45.678.901/0001-23', 'Serviços Industriais Exemplo Ltda',   NULL,                        12,'cnpj_repetido_planilha',  'resolvido', 10)
  ) AS v(n, cnpj, razao, existente, linha, motivo, status, dias)
  WHERE NOT EXISTS (SELECT 1 FROM public.empresa_import_pendencias x WHERE x.id = public.demo_id('empimport:' || v.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(7) pendencias de importacao nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_pendencias$;

-- ---------------------------------------------------------------------------
-- (8) Plano de acao (5W2H): acoes gerais da empresa em varios status
--     8a acoes | 8b tarefas | 8c status final | 8d comentarios, evidencias,
--     participantes e historico
-- ---------------------------------------------------------------------------
DO $s_plano_acoes$
BEGIN
  INSERT INTO public.plano_acoes (
    id, tenant_id, empresa_id, codigo, titulo, descricao, porque, onde, como, prazo, responsavel_id, responsavel_nome,
    custo_estimado, custo_real, origem_modulo, origem_descricao, gravidade, urgencia, tendencia, prioridade, status,
    data_inicio, exige_evidencia, tipo, tempo_estimado_minutos, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('acao:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', '',
         v.titulo, v.descr, v.porque, v.onde, v.como, CURRENT_DATE + v.prazo,
         CASE WHEN v.resp = 'ME' THEN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE WHEN v.resp = 'ME' THEN 'Leiri Nuernberg' ELSE v.resp END,
         v.custo, v.custo_real, v.origem, v.origem_desc, v.g, v.u, v.t,
         (CASE WHEN v.g * v.u * v.t >= 64 THEN 'imediato' WHEN v.g * v.u * v.t >= 36 THEN 'urgente'
               WHEN v.g * v.u * v.t >= 16 THEN 'medio' ELSE 'baixo' END)::public.acao_gut_prioridade,
         'pendente'::public.acao_status, CURRENT_DATE + v.ini, v.exige, v.tipo, v.horas * 60,
         CASE WHEN v.resp = 'ME' OR v.n % 3 = 0 THEN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
         CASE WHEN v.resp = 'ME' OR v.n % 3 = 0 THEN 'Leiri Nuernberg' ELSE v.resp END,
         now() - ((-v.ini + 2) || ' days')::interval
  FROM (VALUES
    (1,  'Adequar os protetores auriculares da usinagem CNC', 'Substituir protetores desgastados e padronizar o modelo com atenuação adequada ao ruído medido.', 'Dosimetria apontou exposição acima de 85 dB(A) e há protetores fora de validade.', 'Setor de usinagem CNC (Produção)', 'Levantar EPIs em uso, cotar modelos, comprar, distribuir e treinar o uso correto.', 'corretiva', 'epi', 'Inventário de EPIs: protetor auricular', 4,4,3, 12, -25, 4800, 3200, true, 'ME', 24),
    (2,  'Instalar exaustão localizada nas bancadas de solda', 'Projeto de captação de fumos metálicos nas 6 bancadas de solda.', 'Reduzir a exposição a fumos metálicos identificada no inventário de riscos (GRO).', 'Galpão de solda', 'Contratar projeto, aprovar orçamento, instalar os captores e medir a concentração após a instalação.', 'corretiva', 'gro', 'Risco químico: fumos de solda (PGR)', 5,4,4, 35, -18, 38000, NULL, true, 'Marcos Vinícius Teles', 80),
    (3,  'Revisar posto de trabalho da montagem (NR-17)', 'Ajustar bancadas, apoio de pés e altura de trabalho dos montadores.', 'Análise ergonômica indicou postura inadequada e queixas de dor lombar.', 'Linha de montagem de estruturas', 'Aplicar a análise ergonômica do trabalho, ajustar o mobiliário e reavaliar após 30 dias.', 'preventiva', 'ergonomia', 'AET da montagem de estruturas', 3,3,3, 20, -3, 9500, NULL, true, 'Fernanda Quintana Leal', 40),
    (4,  'Treinar operadores de máquinas na NR-12', 'Capacitação obrigatória em segurança no trabalho em máquinas e equipamentos.', 'Parte dos operadores está sem treinamento válido, risco de autuação e de acidente.', 'Sala de treinamento e chão de fábrica', 'Contratar instrutor, montar turmas por turno, aplicar prova e registrar a presença.', 'corretiva', 'compliance_sst', 'Conformidade NR-12: treinamentos vencidos', 4,5,3, -9, -40, 6200, 2100, true, 'ME', 32),
    (5,  'Reorganizar a escala do turno B para reduzir horas extras', 'Redistribuir equipes e ajustar escala 6x2 para diminuir horas extras recorrentes.', 'Alertas do ponto mostram excesso de horas extras e interjornada insuficiente no turno B.', 'Produção - turno B', 'Mapear demanda, simular escalas, validar com o jurídico e o sindicato e implantar.', 'corretiva', 'ponto', 'Alerta de excesso de horas extras no turno B', 3,3,4, 15, -12, NULL, NULL, false, 'Henrique Duarte Lacerda', 30),
    (6,  'Tratar as manifestações de assédio moral recebidas na Ouvidoria', 'Apurar com sigilo as manifestações e adotar medidas de acolhimento e correção.', 'Quatro manifestações no trimestre apontam conduta inadequada de liderança em um setor.', 'Ouvidoria / RH', 'Abrir apuração, ouvir as partes, definir medidas, treinar lideranças e acompanhar o clima.', 'corretiva', 'ouvidoria', 'Manifestações classificadas como assédio', 5,5,3, 7, -14, NULL, NULL, true, 'ME', 20),
    (7,  'Plano psicossocial: reduzir a sobrecarga de trabalho na Produção', 'Ações de organização do trabalho para a dimensão demanda e ritmo, identificada na campanha psicossocial.', 'A campanha psicossocial classificou a dimensão como risco moderado a alto.', 'Produção', 'Revisar metas de produção, pausas, rodízio de tarefas e canal de escuta com a liderança.', 'preventiva', 'psicossocial', 'Campanha psicossocial: dimensão demandas', 4,3,3, 45, -2, 1500, NULL, false, 'Camila Fontes Barreto', 24),
    (8,  'Renovar ASOs vencidos e a vencer em 30 dias', 'Agendar exames periódicos de quem está com ASO vencido ou perto do vencimento.', 'Evitar colaboradores trabalhando com ASO vencido e multas na fiscalização.', 'Ambulatório / clínica parceira', 'Listar vencimentos, agendar com a clínica, acompanhar comparecimento e arquivar os ASOs.', 'corretiva', 'atestados', 'Painel de vencimentos de ASO', 4,4,2, -3, -35, 3800, 3650, true, 'Camila Fontes Barreto', 16),
    (9,  'Atualizar o inventário de riscos do PGR', 'Revisão anual do inventário de riscos e do plano de ação do PGR.', 'Exigência da NR-1: revisão periódica do gerenciamento de riscos ocupacionais.', 'SESMT', 'Visitar os setores, reavaliar os riscos, atualizar o inventário e comunicar os trabalhadores.', 'preventiva', 'gro', 'Revisão anual do PGR', 3,3,2, -15, -60, 2500, 2500, true, 'Marcos Vinícius Teles', 40),
    (10, 'Melhorar a sinalização de segurança no pátio logístico', 'Demarcar vias de pedestres e empilhadeiras, instalar placas e espelhos nos cruzamentos.', 'Quase-acidentes registrados entre empilhadeiras e pedestres no pátio.', 'Pátio e docas do centro de distribuição', 'Projetar a sinalização, comprar materiais, aplicar a pintura e treinar motoristas e pedestres.', 'corretiva', 'sst', 'Registro de quase-acidentes na logística', 4,4,4, -4, -30, 7200, NULL, true, 'Henrique Duarte Lacerda', 36),
    (11, 'Criar o programa de reconhecimento por tempo de casa', 'Definir marcos (1, 5, 10 anos), premiações e rituais de reconhecimento.', 'A pesquisa de clima apontou baixa percepção de reconhecimento.', 'RH / Cultura', 'Desenhar regras, orçamento e calendário; comunicar pelo mural e iniciar com o próximo marco.', 'melhoria', 'cultura', 'Pesquisa de clima: reconhecimento', 2,2,3, 60, 0, 12000, NULL, false, 'Camila Fontes Barreto', 30),
    (12, 'SIPAT 2026: organizar programação e logística', 'Montar a programação da semana, convidar palestrantes e liberar os turnos.', 'Cumprir a obrigação da CIPA e reforçar a cultura de prevenção.', 'Refeitório e áreas comuns', 'Definir temas, contratar palestrantes, reservar espaços, divulgar no mural e escalar a liberação.', 'preventiva', 'sst', 'Calendário anual de SST', 3,3,3, 18, -20, 8500, 2000, true, 'ME', 50),
    (13, 'Regularizar a documentação de empresas terceiras', 'Cobrar e conferir documentos de segurança das prestadoras de serviço antes da liberação de acesso.', 'Há prestadoras com documentos vencidos acessando as dependências.', 'Portaria / RH / SESMT', 'Listar pendências, notificar as empresas, bloquear acessos sem documento e revisar mensalmente.', 'corretiva', 'documentos', 'Conferência documental de terceiros', 4,3,3, 10, -16, NULL, NULL, true, 'Camila Fontes Barreto', 18),
    (14, 'Elevar a cobertura de feedbacks de desempenho', 'Meta de 90% de feedbacks registrados no ciclo.', 'Cobertura de feedbacks abaixo do esperado no último ciclo.', 'Todas as lideranças', 'Capacitar líderes e acompanhar o registro mensal.', 'melhoria', 'avaliacoes', 'Ciclo de avaliação anterior', 2,2,2, -30, -75, NULL, NULL, false, 'ME', 12),
    (15, 'Meta estratégica: reduzir o absenteísmo para 2,5%', 'Programa integrado de saúde e presença para reduzir faltas e atestados.', 'O absenteísmo médio está acima da meta definida no planejamento estratégico.', 'Empresa toda', 'Analisar causas por setor, ações de saúde preventiva, flexibilização de escalas e acompanhamento mensal.', 'melhoria', 'estrategia', 'Planejamento estratégico: indicador de absenteísmo', 3,2,3, 90, -1, 15000, NULL, false, 'Ricardo Almeida Prado', 60),
    (16, 'Implantar o checklist diário de empilhadeiras', 'Checklist digital antes do turno para as 8 empilhadeiras da operação.', 'Reduzir falhas mecânicas e acidentes envolvendo empilhadeiras.', 'Logística', 'Definir itens, treinar operadores, registrar diariamente e tratar as não conformidades.', 'preventiva', 'epi', 'Inspeção de equipamentos de movimentação', 3,3,2, 5, -22, 1800, 900, true, 'Henrique Duarte Lacerda', 20)
  ) AS v(n, titulo, descr, porque, onde, como, tipo, origem, origem_desc, g, u, t, prazo, ini, custo, custo_real, exige, resp, horas)
  WHERE NOT EXISTS (SELECT 1 FROM public.plano_acoes x WHERE x.id = public.demo_id('acao:' || v.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(8a) acoes do plano nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_plano_acoes$;

DO $s_plano_tarefas$
BEGIN
  INSERT INTO public.plano_tarefas (
    id, tenant_id, acao_id, titulo, descricao, ordem, responsavel_nome, status, prazo, data_conclusao, prioridade,
    tempo_estimado_minutos, concluida_por_nome, created_at
  )
  SELECT public.demo_id('tarefa:' || v.n || ':' || v.ordem), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acao:' || v.n),
         v.titulo, v.descr, v.ordem, v.resp, v.status::public.tarefa_status, CURRENT_DATE + v.prazo,
         CASE WHEN v.status = 'concluida' THEN now() - (GREATEST(-v.prazo, 1) || ' days')::interval END,
         (CASE WHEN v.ordem <= 2 THEN 'urgente' ELSE 'medio' END)::public.acao_gut_prioridade, 120 * v.ordem,
         CASE WHEN v.status = 'concluida' THEN v.resp END,
         now() - '30 days'::interval
  FROM (VALUES
    (1, 1, 'Levantar EPIs em uso e níveis de ruído',        'Conferir EPIs por posto e registrar as medições de ruído.',       'Marcos Vinícius Teles', 'concluida',    -20),
    (1, 2, 'Cotar protetores tipo concha e plug',            'Solicitar três cotações com certificado de aprovação (CA).',      'Leiri Nuernberg',       'concluida',    -12),
    (1, 3, 'Comprar e distribuir os protetores',             'Compra aprovada e entrega com registro de recebimento.',          'Leiri Nuernberg',       'concluida',    -3),
    (1, 4, 'Treinar o uso correto e registrar a entrega',    'Treinamento de 20 minutos por turno com lista de presença.',       'Marcos Vinícius Teles', 'em_andamento', 4),
    (1, 5, 'Auditar o uso na área por 30 dias',              'Ronda semanal de verificação do uso.',                            'Marcos Vinícius Teles', 'nao_iniciada', 12),
    (2, 1, 'Contratar o projeto de exaustão',                'Escolher a empresa projetista.',                                  'Marcos Vinícius Teles', 'concluida',    -10),
    (2, 2, 'Aprovar o orçamento com a diretoria',            'Apresentar o retorno esperado e o prazo de instalação.',          'Ricardo Almeida Prado', 'em_andamento', 8),
    (2, 3, 'Instalar os captores nas 6 bancadas',            'Instalação em parada programada de fim de semana.',               'Marcos Vinícius Teles', 'nao_iniciada', 28),
    (2, 4, 'Medir a concentração de fumos após a instalação','Nova avaliação ambiental para validar a eficácia.',                'Marcos Vinícius Teles', 'nao_iniciada', 34),
    (3, 1, 'Aplicar a análise ergonômica do trabalho',       'Observação e entrevistas com os montadores.',                     'Fernanda Quintana Leal','nao_iniciada', 7),
    (3, 2, 'Definir os ajustes de mobiliário',               'Lista de bancadas, apoios e ferramentas a trocar.',               'Fernanda Quintana Leal','nao_iniciada', 12),
    (3, 3, 'Implantar e reavaliar após 30 dias',             'Reaplicar o questionário de desconforto.',                        'Fernanda Quintana Leal','nao_iniciada', 20),
    (4, 1, 'Levantar os operadores com treinamento vencido', 'Cruzar a matriz de treinamentos com a lista de operadores.',      'Leiri Nuernberg',       'concluida',    -30),
    (4, 2, 'Contratar o instrutor',                          'Instrutor habilitado com carga horária mínima da norma.',         'Leiri Nuernberg',       'concluida',    -22),
    (4, 3, 'Aplicar as turmas dos turnos A e B',             'Duas turmas por turno, com avaliação ao final.',                  'Marcos Vinícius Teles', 'em_andamento', -9),
    (4, 4, 'Registrar certificados e atualizar a matriz',    'Arquivar os certificados na ficha de cada operador.',             'Leiri Nuernberg',       'nao_iniciada', -2),
    (5, 1, 'Mapear a demanda por hora e por equipe',         'Levantamento dos picos de produção.',                             'Henrique Duarte Lacerda','concluida',   -9),
    (5, 2, 'Simular as novas escalas',                       'Comparar custos e horas extras de três cenários.',                'Henrique Duarte Lacerda','em_andamento',5),
    (5, 3, 'Validar com o jurídico e o sindicato',           'Garantir aderência ao acordo coletivo.',                          'Camila Fontes Barreto', 'nao_iniciada', 10),
    (5, 4, 'Implantar a nova escala',                        'Comunicar equipes e acompanhar o primeiro mês.',                  'Henrique Duarte Lacerda','nao_iniciada',15),
    (6, 1, 'Abrir a apuração com sigilo',                    'Registrar a apuração e restringir o acesso.',                     'Leiri Nuernberg',       'concluida',    -12),
    (6, 2, 'Ouvir as partes envolvidas',                     'Entrevistas individuais registradas em ata.',                     'Leiri Nuernberg',       'concluida',    -8),
    (6, 3, 'Definir as medidas e comunicar a direção',       'Relatório com recomendações.',                                    'Leiri Nuernberg',       'em_andamento', 3),
    (6, 4, 'Treinar as lideranças em comunicação respeitosa','Workshop de duas horas.',                                         'Camila Fontes Barreto', 'nao_iniciada', 7),
    (7, 1, 'Revisar metas de produção e pausas',             'Rever a carga de trabalho por posto.',                            'Camila Fontes Barreto', 'nao_iniciada', 20),
    (7, 2, 'Criar canal de escuta com a liderança',          'Encontros quinzenais por turno.',                                 'Camila Fontes Barreto', 'nao_iniciada', 30),
    (7, 3, 'Reaplicar a pesquisa psicossocial',              'Verificar a evolução da dimensão após as ações.',                 'Camila Fontes Barreto', 'nao_iniciada', 45),
    (8, 1, 'Listar os ASOs vencidos e a vencer',             'Relatório do painel de vencimentos.',                             'Camila Fontes Barreto', 'concluida',    -33),
    (8, 2, 'Agendar os exames com a clínica parceira',       'Agenda organizada por setor para não parar a produção.',          'Camila Fontes Barreto', 'concluida',    -25),
    (8, 3, 'Acompanhar o comparecimento',                    'Reagendar faltosos.',                                             'Camila Fontes Barreto', 'concluida',    -10),
    (8, 4, 'Arquivar os ASOs no prontuário',                 'Upload dos documentos na ficha do colaborador.',                  'Camila Fontes Barreto', 'concluida',    -4),
    (9, 1, 'Visitar os setores e reavaliar os riscos',       'Vistoria com checklist do inventário.',                           'Marcos Vinícius Teles', 'concluida',    -45),
    (9, 2, 'Atualizar o inventário e o plano de ação do PGR','Registrar as alterações no sistema.',                             'Marcos Vinícius Teles', 'concluida',    -25),
    (9, 3, 'Comunicar os trabalhadores',                     'Divulgar os riscos e medidas de controle.',                       'Marcos Vinícius Teles', 'concluida',    -16),
    (10, 1, 'Projetar a sinalização do pátio',               'Planta com vias e travessias.',                                   'Henrique Duarte Lacerda','concluida',   -25),
    (10, 2, 'Comprar tintas, placas e espelhos',             'Compra com fornecedor homologado.',                               'Henrique Duarte Lacerda','em_andamento',-8),
    (10, 3, 'Aplicar a pintura e instalar as placas',        'Execução em dois fins de semana.',                                'Henrique Duarte Lacerda','nao_iniciada',-4),
    (11, 1, 'Desenhar as regras e as premiações',            'Marcos de 1, 5 e 10 anos.',                                       'Camila Fontes Barreto', 'nao_iniciada', 25),
    (11, 2, 'Definir orçamento anual',                       'Aprovar com a diretoria.',                                        'Ricardo Almeida Prado', 'nao_iniciada', 40),
    (12, 1, 'Definir temas e palestrantes',                  'Alinhar com a CIPA.',                                             'Leiri Nuernberg',       'concluida',    -10),
    (12, 2, 'Reservar espaços e equipamentos',               'Refeitório e auditório.',                                         'Leiri Nuernberg',       'em_andamento', 6),
    (12, 3, 'Divulgar no mural e escalar a liberação dos turnos','Publicar o comunicado e a escala.',                           'Camila Fontes Barreto', 'nao_iniciada', 10),
    (12, 4, 'Montar o kit de brindes e o sorteio',           'Cotação de brindes.',                                             'Camila Fontes Barreto', 'nao_iniciada', 15),
    (13, 1, 'Listar as prestadoras com documentos pendentes','Relatório do módulo de terceiros.',                               'Camila Fontes Barreto', 'concluida',    -12),
    (13, 2, 'Notificar as empresas',                         'E-mail com prazo de 10 dias.',                                    'Camila Fontes Barreto', 'em_andamento', 3),
    (13, 3, 'Bloquear os acessos sem documentação',          'Comunicar a portaria.',                                           'Marcos Vinícius Teles', 'nao_iniciada', 10),
    (14, 1, 'Capacitar as lideranças para dar feedback',     'Substituída pela ação do ciclo semestral.',                       'Leiri Nuernberg',       'nao_iniciada', -40),
    (15, 1, 'Analisar as causas de afastamentos por setor',  'Cruzar atestados, ponto e saúde ocupacional.',                    'Camila Fontes Barreto', 'nao_iniciada', 30),
    (15, 2, 'Definir ações de saúde preventiva',             'Campanhas e ginástica laboral.',                                  'Marcos Vinícius Teles', 'nao_iniciada', 60),
    (16, 1, 'Definir os itens do checklist',                 'Freios, garfos, sinal sonoro, bateria.',                          'Henrique Duarte Lacerda','concluida',   -18),
    (16, 2, 'Treinar os operadores no uso do checklist',     'Treinamento por turno.',                                          'Henrique Duarte Lacerda','concluida',   -10),
    (16, 3, 'Registrar diariamente por 30 dias',             'Acompanhar as não conformidades.',                                'Henrique Duarte Lacerda','concluida',   -2),
    (16, 4, 'Tratar as não conformidades abertas',           'Manutenção corrige e registra.',                                  'Henrique Duarte Lacerda','em_andamento', 5)
  ) AS v(n, ordem, titulo, descr, resp, status, prazo)
  WHERE EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('acao:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_tarefas x WHERE x.id = public.demo_id('tarefa:' || v.n || ':' || v.ordem));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(8b) tarefas do plano nao semeadas: % (%)', SQLERRM, SQLSTATE;
END $s_plano_tarefas$;

-- Situacao final de cada acao (o gatilho das tarefas recalcula o status; aqui fixamos o desejado
-- na demonstracao). Roda a cada execucao, so em acoes criadas por este arquivo.
DO $s_plano_status$
BEGIN
  UPDATE public.plano_acoes a
     SET status = v.status::public.acao_status,
         progresso = COALESCE(t.prog, 0),
         data_conclusao = CASE WHEN v.status = 'concluida' THEN CURRENT_DATE + v.concl END,
         custo_real = COALESCE(a.custo_real, CASE WHEN v.status = 'concluida' THEN a.custo_estimado END)
    FROM (VALUES
      (1, 'em_andamento', NULL), (2, 'em_andamento', NULL), (3, 'pendente', NULL), (4, 'atrasada', NULL),
      (5, 'em_andamento', NULL), (6, 'em_andamento', NULL), (7, 'pendente', NULL), (8, 'concluida', -4),
      (9, 'concluida', -16), (10, 'atrasada', NULL), (11, 'pendente', NULL), (12, 'em_andamento', NULL),
      (13, 'em_andamento', NULL), (14, 'cancelada', NULL), (15, 'pendente', NULL), (16, 'em_andamento', NULL)
    ) AS v(n, status, concl)
    LEFT JOIN LATERAL (
      SELECT (count(*) FILTER (WHERE tt.status = 'concluida') * 100 / NULLIF(count(*), 0))::int AS prog
      FROM public.plano_tarefas tt WHERE tt.acao_id = public.demo_id('acao:' || v.n)
    ) t ON true
   WHERE a.id = public.demo_id('acao:' || v.n)
     AND a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     AND (a.status::text <> v.status OR a.progresso IS DISTINCT FROM COALESCE(t.prog, 0)
          OR (v.status = 'concluida' AND a.data_conclusao IS NULL));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(8c) status final das acoes nao ajustado: % (%)', SQLERRM, SQLSTATE;
END $s_plano_status$;

DO $s_plano_extras$
BEGIN
  -- Comentarios (autor_id do banco exige um login existente: usa o login demo, com o nome de quem comentou)
  INSERT INTO public.plano_comentarios (id, tenant_id, acao_id, conteudo, autor_id, autor_nome, created_at)
  SELECT public.demo_id('planocom:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acao:' || v.n),
         v.texto, u.id, v.autor, now() - (v.dias || ' days')::interval
  FROM (VALUES
    (1, 1, 'Cotações recebidas: o modelo concha com CA válido saiu 12% mais barato. Seguimos com ele.', 'Leiri Nuernberg', 13),
    (1, 2, 'Entrega concluída no turno A. Falta o turno B, previsto para esta semana.', 'Marcos Vinícius Teles', 3),
    (2, 1, 'Orçamento do projeto enviado para análise da diretoria.', 'Marcos Vinícius Teles', 9),
    (2, 2, 'Precisamos definir a parada de fim de semana para a instalação. Sugiro o próximo mês.', 'Henrique Duarte Lacerda', 6),
    (4, 1, 'Turma do turno A concluída com 100% de presença. Turno B atrasou por causa da demanda.', 'Marcos Vinícius Teles', 8),
    (4, 2, 'Vamos reprogramar o turno B para a próxima semana e avisar os líderes.', 'Leiri Nuernberg', 7),
    (5, 1, 'Simulação 2 reduz em 38% as horas extras, mas exige contratar dois operadores.', 'Henrique Duarte Lacerda', 4),
    (6, 1, 'Apuração conduzida com sigilo. Duas entrevistas já registradas.', 'Leiri Nuernberg', 9),
    (6, 2, 'Direção ciente do andamento; relatório final até o prazo.', 'Camila Fontes Barreto', 2),
    (8, 1, 'Todos os ASOs vencidos foram regularizados. Obrigada, clínica!', 'Camila Fontes Barreto', 4),
    (9, 1, 'PGR atualizado e comunicado às equipes. Eficácia a validar na próxima revisão.', 'Marcos Vinícius Teles', 16),
    (10, 1, 'Compra atrasou por falta de estoque do fornecedor. Nova previsão de entrega em uma semana.', 'Henrique Duarte Lacerda', 5),
    (12, 1, 'Dois palestrantes confirmados: segurança em máquinas e saúde mental no trabalho.', 'Leiri Nuernberg', 8),
    (13, 1, 'Cinco prestadoras notificadas; duas já enviaram a documentação.', 'Camila Fontes Barreto', 2),
    (16, 1, 'Checklist em uso nas 8 empilhadeiras. Duas não conformidades abertas para a Manutenção.', 'Henrique Duarte Lacerda', 2)
  ) AS v(n, seq, texto, autor, dias)
  CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
  WHERE EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('acao:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_comentarios x WHERE x.id = public.demo_id('planocom:' || v.n || ':' || v.seq));

  -- Evidencias
  INSERT INTO public.plano_evidencias (id, tenant_id, acao_id, titulo, descricao, arquivo_nome, arquivo_tipo, tipo, enviado_por_nome, created_at)
  SELECT public.demo_id('planoev:' || v.n || ':' || v.seq), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acao:' || v.n),
         v.titulo, v.descr, v.arquivo, v.mime, v.tipo, v.quem, now() - (v.dias || ' days')::interval
  FROM (VALUES
    (1, 1, 'Comprovante de entrega dos protetores - turno A', 'Lista assinada pelos colaboradores.', 'entrega-protetores-turno-a.pdf', 'application/pdf', 'comprovante', 'Marcos Vinícius Teles', 3),
    (1, 2, 'Foto do almoxarifado com os novos protetores', 'Estoque identificado e organizado.', 'almoxarifado-protetores.jpg', 'image/jpeg', 'foto', 'Leiri Nuernberg', 4),
    (4, 1, 'Lista de presença da turma do turno A', 'Treinamento NR-12.', 'presenca-nr12-turno-a.pdf', 'application/pdf', 'documento', 'Marcos Vinícius Teles', 8),
    (6, 1, 'Ata das entrevistas (restrita)', 'Documento sigiloso.', 'ata-entrevistas-sigilosa.pdf', 'application/pdf', 'documento', 'Leiri Nuernberg', 8),
    (8, 1, 'Relatório de ASOs regularizados', 'Planilha com todos os exames em dia.', 'asos-regularizados.pdf', 'application/pdf', 'documento', 'Camila Fontes Barreto', 4),
    (9, 1, 'Inventário de riscos do PGR atualizado', 'Versão 4 assinada pelo responsável técnico.', 'inventario-pgr-v4.pdf', 'application/pdf', 'documento', 'Marcos Vinícius Teles', 16),
    (9, 2, 'Registro de comunicação aos trabalhadores', 'Lista de presença do DDS.', 'dds-comunicacao-pgr.pdf', 'application/pdf', 'anexo', 'Marcos Vinícius Teles', 17),
    (10, 1, 'Projeto da sinalização do pátio', 'Planta com as vias de pedestres.', 'projeto-sinalizacao-patio.pdf', 'application/pdf', 'anexo', 'Henrique Duarte Lacerda', 25),
    (16, 1, 'Modelo do checklist de empilhadeiras', 'Versão em uso nos turnos.', 'checklist-empilhadeiras.pdf', 'application/pdf', 'documento', 'Henrique Duarte Lacerda', 17)
  ) AS v(n, seq, titulo, descr, arquivo, mime, tipo, quem, dias)
  WHERE EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('acao:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_evidencias x WHERE x.id = public.demo_id('planoev:' || v.n || ':' || v.seq));

  -- Participantes (so o login demo existe como usuario autenticavel)
  INSERT INTO public.plano_participantes (id, tenant_id, acao_id, usuario_id, usuario_nome, tipo, aceito, data_aceite, created_at)
  SELECT public.demo_id('planopart:' || v.n), 'd3e00000-0000-4000-8000-000000000001', public.demo_id('acao:' || v.n),
         u.id, 'Leiri Nuernberg', v.tipo, true, now() - interval '20 days', now() - interval '25 days'
  FROM (VALUES (2, 'co_responsavel'), (3, 'validacao'), (5, 'co_responsavel'), (7, 'validacao'), (8, 'validacao'),
               (9, 'co_responsavel'), (10, 'apoio'), (11, 'co_responsavel'), (13, 'co_responsavel'), (15, 'validacao'), (16, 'apoio')) AS v(n, tipo)
  CROSS JOIN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com' LIMIT 1) u
  WHERE EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('acao:' || v.n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_participantes x WHERE x.acao_id = public.demo_id('acao:' || v.n) AND x.usuario_id = u.id);

  -- Historico: criacao, mudancas de situacao, tarefas concluidas e comentarios
  INSERT INTO public.plano_historico (id, tenant_id, acao_id, tipo_evento, descricao, usuario_nome, created_at)
  SELECT public.demo_id('planohist:criacao:' || a.id::text), a.tenant_id, a.id, 'criacao',
         'Ação "' || a.titulo || '" criada', COALESCE(a.criado_por_nome, 'Leiri Nuernberg'), a.created_at
  FROM public.plano_acoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.id IN (SELECT public.demo_id('acao:' || g.n) FROM generate_series(1, 16) g(n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_historico x WHERE x.id = public.demo_id('planohist:criacao:' || a.id::text));

  INSERT INTO public.plano_historico (id, tenant_id, acao_id, tipo_evento, descricao, dados_anteriores, dados_novos, usuario_nome, created_at)
  SELECT public.demo_id('planohist:status:' || a.id::text), a.tenant_id, a.id, 'status_alterado',
         'Situação alterada para "' || replace(a.status::text, '_', ' ') || '"',
         jsonb_build_object('status', 'pendente'), jsonb_build_object('status', a.status::text),
         COALESCE(a.responsavel_nome, 'Leiri Nuernberg'), a.created_at + interval '1 day'
  FROM public.plano_acoes a
  WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.id IN (SELECT public.demo_id('acao:' || g.n) FROM generate_series(1, 16) g(n))
    AND a.status::text <> 'pendente'
    AND NOT EXISTS (SELECT 1 FROM public.plano_historico x WHERE x.id = public.demo_id('planohist:status:' || a.id::text));

  INSERT INTO public.plano_historico (id, tenant_id, acao_id, tarefa_id, tipo_evento, descricao, usuario_nome, created_at)
  SELECT public.demo_id('planohist:tarefa:' || t.id::text), t.tenant_id, t.acao_id, t.id, 'tarefa_concluida',
         'Tarefa "' || t.titulo || '" concluída', COALESCE(t.concluida_por_nome, t.responsavel_nome, 'Leiri Nuernberg'),
         COALESCE(t.data_conclusao, now())
  FROM public.plano_tarefas t
  WHERE t.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND t.status = 'concluida'
    AND t.acao_id IN (SELECT public.demo_id('acao:' || g.n) FROM generate_series(1, 16) g(n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_historico x WHERE x.id = public.demo_id('planohist:tarefa:' || t.id::text));

  INSERT INTO public.plano_historico (id, tenant_id, acao_id, tipo_evento, descricao, usuario_nome, created_at)
  SELECT public.demo_id('planohist:com:' || c.id::text), c.tenant_id, c.acao_id, 'comentario',
         'Comentário adicionado: ' || left(c.conteudo, 80), c.autor_nome, c.created_at
  FROM public.plano_comentarios c
  WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND c.acao_id IN (SELECT public.demo_id('acao:' || g.n) FROM generate_series(1, 16) g(n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_historico x WHERE x.id = public.demo_id('planohist:com:' || c.id::text));

  INSERT INTO public.plano_historico (id, tenant_id, acao_id, tipo_evento, descricao, usuario_nome, created_at)
  SELECT public.demo_id('planohist:ev:' || e.id::text), e.tenant_id, e.acao_id, 'anexo',
         'Evidência anexada: ' || e.titulo, COALESCE(e.enviado_por_nome, 'Leiri Nuernberg'), e.created_at
  FROM public.plano_evidencias e
  WHERE e.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
    AND e.acao_id IN (SELECT public.demo_id('acao:' || g.n) FROM generate_series(1, 16) g(n))
    AND NOT EXISTS (SELECT 1 FROM public.plano_historico x WHERE x.id = public.demo_id('planohist:ev:' || e.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '(8d) comentarios/evidencias/historico do plano nao semeados: % (%)', SQLERRM, SQLSTATE;
END $s_plano_extras$;

-- ---------------------------------------------------------------------------
-- Conferencia final (UMA consulta): contagens do que foi semeado para o tenant demo
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.subscriptions WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS assinatura,
  (SELECT count(*) FROM public.perfis_acesso WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND tipo = 'clonado') AS perfis,
  (SELECT count(*) FROM public.perfil_permissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS permissoes,
  (SELECT count(*) FROM public.usuarios_base WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS usuarios,
  (SELECT count(*) FROM public.usuario_vinculos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS vinculos,
  (SELECT count(*) FROM public.audit_logs WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS auditoria,
  (SELECT count(*) FROM public.suporte_tickets WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS chamados,
  (SELECT count(*) FROM public.feed_posts WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS posts,
  (SELECT count(*) FROM public.feed_comentarios WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS comentarios_feed,
  (SELECT count(*) FROM public.feed_reacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS curtidas,
  (SELECT count(*) FROM public.plano_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS acoes,
  (SELECT count(*) FROM public.plano_tarefas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS tarefas,
  (SELECT count(*) FROM public.empresa_import_pendencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status = 'pendente') AS pendencias_importacao,
  CASE WHEN (SELECT count(*) FROM public.plano_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 16
        AND (SELECT count(*) FROM public.usuarios_base WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 19
        AND (SELECT count(*) FROM public.feed_posts WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 14
        AND (SELECT count(*) FROM public.subscriptions WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 1
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
