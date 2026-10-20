-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 00: empresa de demonstracao + estrutura + colaboradores
--
-- PARA QUE SERVE
-- Monta a "Metalurgica Exemplo Ltda" (100% ficticia) num TENANT PROPRIO e liga
-- o login leirinuernberg@gmail.com a ele, para a equipe comercial demonstrar o
-- sistema a clientes com todas as telas preenchidas. As partes 01 em diante
-- (docs/homologacao/demo/parte_NN_*.sql) preenchem os modulos; esta e a base e
-- tem que rodar PRIMEIRO.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO. O arquivo se RECUSA a rodar em qualquer
-- outro banco: so aceita se a URL gravada em app_config for a da homologacao
-- ou a do teste. Nunca na producao.
--
-- O QUE FAZ
--   1. cria o tenant demo (plano enterprise), a empresa matriz e 2 filiais;
--   2. cria 6 departamentos, 16 cargos e 64 colaboradores ficticios
--      (CPFs 900.000.0XX com digito verificador valido), incluindo
--      contratacoes recentes, admissoes em andamento e desligados;
--   3. liga o login (profiles + usuarios_base) ao tenant demo e garante o
--      papel owner. O vinculo ANTERIOR e guardado numa tabela de backup, com o
--      comando de desfazer no fim do arquivo. Papel de SuperAdmin nao e tocado.
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, CPFs da faixa ficticia da casa.
--   - Idempotente: ids fixos + "so insere se nao existe". Rodar de novo nao
--     duplica nada e nao muda o que ja existe.
--   - O unico dado existente que e ALTERADO e o vinculo do login ao tenant
--     (profiles / usuarios_base), com backup antes.
--   - Roda numa transacao so; sem tabela temporaria entre comandos.
--
-- Se o e-mail nao existir em auth.users deste ambiente, a parte do vinculo
-- apenas avisa (NOTICE) e o resto segue; cadastre o login e rode de novo.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) Trava de ambiente + helpers
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
END $trava$;

-- CPF ficticio da casa: 900.000.0XX com digito verificador valido (n de 0 a 999).
CREATE OR REPLACE FUNCTION public.demo_cpf(n integer)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  b text := '900000' || lpad(n::text, 3, '0');
  s integer := 0;
  d1 integer;
  d2 integer;
  i integer;
BEGIN
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (11 - i);
  END LOOP;
  d1 := (s * 10) % 11;
  IF d1 = 10 THEN d1 := 0; END IF;
  s := 0;
  FOR i IN 1..9 LOOP
    s := s + substr(b, i, 1)::integer * (12 - i);
  END LOOP;
  s := s + d1 * 2;
  d2 := (s * 10) % 11;
  IF d2 = 10 THEN d2 := 0; END IF;
  RETURN b || d1::text || d2::text;
END
$fn$;

-- Id deterministico por (tabela, numero): torna tudo idempotente.
CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

-- ---------------------------------------------------------------------------
-- (2) Tenant, empresa e filiais
-- ---------------------------------------------------------------------------
INSERT INTO public.tenants (id, nome, slug, plano, ativo, configuracoes)
VALUES ('d3e00000-0000-4000-8000-000000000001', 'Metalúrgica Exemplo Ltda', 'metalurgica-exemplo-demo',
        'enterprise', true,
        '{"demo": true, "ambiente": "homologacao", "finalidade": "demonstracao_comercial"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.empresa_cadastro (
  id, tenant_id, razao_social, nome_fantasia, cnpj, endereco, numero, bairro, cidade, estado, cep,
  telefone, email, website, cnae_principal, cnae_descricao, grau_risco, tipo_pessoa, tipo_unidade,
  total_colaboradores, ativo, jornada_padrao, usa_controle_ponto, controle_ponto_obrigatorio,
  sesmt_obrigatorio, cipa_obrigatoria, ai_context
)
SELECT 'd3e00000-0000-4000-8000-000000000002', 'd3e00000-0000-4000-8000-000000000001',
       'Metalúrgica Exemplo Ltda', 'Metalúrgica Exemplo', '98.765.432/0001-02',
       'Rua das Indústrias', '1000', 'Distrito Industrial', 'Joinville', 'SC', '89200-000',
       '(47) 3000-0000', 'contato@metalurgica-exemplo.demo', 'https://metalurgica-exemplo.demo',
       '2512800', 'Fabricação de esquadrias de metal', 3, 'pj', 'matriz',
       64, true, '44h semanais', true, true, true, true,
       'Metalúrgica de médio porte (fictícia, demonstração). Usinagem CNC, solda e montagem de estruturas metálicas em dois turnos; manutenção com sobreaviso; logística com empilhadeiras.'
WHERE NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE id = 'd3e00000-0000-4000-8000-000000000002');

INSERT INTO public.filiais (id, tenant_id, empresa_id, nome, cnpj, endereco, cidade, estado, cep, telefone, email, ativo, tipo)
SELECT v.id, 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.nome, v.cnpj, v.endereco, v.cidade, v.estado, v.cep, v.tel, v.email, true, 'filial'
FROM (VALUES
  (public.demo_id('filial:1'), 'Filial Curitiba', '98.765.432/0002-93', 'Av. das Araucárias, 500', 'Curitiba', 'PR', '81000-000', '(41) 3000-1000', 'curitiba@metalurgica-exemplo.demo'),
  (public.demo_id('filial:2'), 'Centro de Distribuição Itajaí', '98.765.432/0003-74', 'Rod. BR-101, km 110', 'Itajaí', 'SC', '88300-000', '(47) 3000-2000', 'itajai@metalurgica-exemplo.demo')
) AS v(id, nome, cnpj, endereco, cidade, estado, cep, tel, email)
WHERE NOT EXISTS (SELECT 1 FROM public.filiais f WHERE f.id = v.id);

-- ---------------------------------------------------------------------------
-- (3) Departamentos e cargos
-- ---------------------------------------------------------------------------
INSERT INTO public.departamentos (id, tenant_id, empresa_id, nome, descricao, ativo)
SELECT public.demo_id('depto:' || v.nome), 'd3e00000-0000-4000-8000-000000000001',
       'd3e00000-0000-4000-8000-000000000002', v.nome, v.descricao, true
FROM (VALUES
  ('Produção', 'Usinagem, solda e montagem de estruturas metálicas'),
  ('Manutenção', 'Manutenção mecânica e elétrica de máquinas e utilidades'),
  ('Logística', 'Recebimento, armazenagem e expedição'),
  ('Administrativo', 'Financeiro, compras e qualidade'),
  ('Recursos Humanos', 'Departamento pessoal, recrutamento e SST'),
  ('Comercial', 'Vendas, atendimento e pós-venda')
) AS v(nome, descricao)
WHERE NOT EXISTS (SELECT 1 FROM public.departamentos d WHERE d.id = public.demo_id('depto:' || v.nome));

INSERT INTO public.cargos (
  id, tenant_id, empresa_id, nome, descricao, departamento_id, nivel, faixa_salarial_min, faixa_salarial_max,
  ativo, periodicidade_exame_meses, exames_obrigatorios, insalubridade, insalubridade_grau,
  insalubridade_agente_nocivo, periculosidade, periculosidade_tipo,
  objetivo_funcao, escopo_geral, responsabilidade
)
SELECT public.demo_id('cargo:' || v.nome), 'd3e00000-0000-4000-8000-000000000001',
       'd3e00000-0000-4000-8000-000000000002', v.nome,
       v.nome || ' — ' || v.depto || ' (empresa de demonstração)',
       public.demo_id('depto:' || v.depto), v.nivel, v.sal_min, v.sal_max, true, v.periodo,
       v.exames, v.insal, v.grau, v.agente, v.peric, v.tipo_peric,
       'Executar as atividades de ' || lower(v.nome) || ' com segurança e qualidade.',
       'Atividades do departamento de ' || v.depto || '.',
       'Cumprir procedimentos, normas de SST e metas do setor.'
FROM (VALUES
  ('Operador de Usinagem CNC', 'Produção', 'pleno', 3200, 4200, 12, ARRAY['Audiometria','Clínico'], true, 'medio', 'Ruído contínuo acima de 85 dB(A)', false, NULL),
  ('Soldador', 'Produção', 'pleno', 3400, 4600, 12, ARRAY['Audiometria','Espirometria','Clínico'], true, 'medio', 'Fumos metálicos e radiação não ionizante', false, NULL),
  ('Montador de Estruturas Metálicas', 'Produção', 'junior', 2600, 3400, 12, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Líder de Produção', 'Produção', 'senior', 5200, 6800, 12, ARRAY['Clínico','Audiometria'], false, NULL, NULL, false, NULL),
  ('Mecânico de Manutenção', 'Manutenção', 'pleno', 3600, 4800, 12, ARRAY['Clínico','Audiometria'], true, 'minimo', 'Óleos e graxas minerais', false, NULL),
  ('Eletricista de Manutenção', 'Manutenção', 'pleno', 3800, 5000, 12, ARRAY['Clínico','Eletrocardiograma'], false, NULL, NULL, true, 'Eletricidade (NR-10)'),
  ('Supervisor de Manutenção', 'Manutenção', 'senior', 6200, 8200, 12, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Operador de Empilhadeira', 'Logística', 'pleno', 2800, 3600, 12, ARRAY['Clínico','Acuidade visual'], false, NULL, NULL, false, NULL),
  ('Auxiliar de Logística', 'Logística', 'junior', 2200, 2900, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Coordenador de Logística', 'Logística', 'senior', 6000, 7800, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Analista Financeiro', 'Administrativo', 'pleno', 3800, 5200, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Analista da Qualidade', 'Administrativo', 'pleno', 3800, 5200, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Comprador', 'Administrativo', 'pleno', 3500, 4800, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Analista de RH', 'Recursos Humanos', 'pleno', 3600, 5000, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL),
  ('Técnico de Segurança do Trabalho', 'Recursos Humanos', 'pleno', 3900, 5200, 12, ARRAY['Clínico','Audiometria'], false, NULL, NULL, false, NULL),
  ('Vendedor Interno', 'Comercial', 'junior', 2600, 4200, 24, ARRAY['Clínico'], false, NULL, NULL, false, NULL)
) AS v(nome, depto, nivel, sal_min, sal_max, periodo, exames, insal, grau, agente, peric, tipo_peric)
WHERE NOT EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.nome));

-- ---------------------------------------------------------------------------
-- (4) Colaboradores (64) — 3 contratados ha poucos dias (57 a 59), 2 desligados
--     (60 e 61) e 3 admissoes em andamento (62 a 64)
-- ---------------------------------------------------------------------------
INSERT INTO public.admissoes (
  id, tenant_id, empresa_id, status, nome_completo, cpf, rg, data_nascimento, estado_civil, genero, nacionalidade,
  naturalidade, nome_mae, email, telefone, celular, endereco, numero, bairro, cidade, estado, cep,
  cargo, cargo_id, departamento, filial, data_admissao, tipo_contrato, jornada_trabalho, salario, gestor_imediato,
  centro_custo, banco, agencia, conta, tipo_conta, tipo_vinculo, bate_ponto, cbo,
  exame_admissional_data, exame_admissional_validade, exame_admissional_resultado,
  aso_admissional_data, aso_admissional_resultado,
  data_desligamento, motivo_desligamento, tipo_aviso_previo, dias_aviso_previo
)
SELECT public.demo_id('admissao:' || x.n),
       'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       x.status::public.admissao_status,
       x.nome, public.demo_cpf(x.n),
       lpad((1000000 + x.n * 7919)::text, 7, '0'),
       x.nasc,
       CASE WHEN x.n % 3 = 0 THEN 'solteiro' WHEN x.n % 3 = 1 THEN 'casado' ELSE 'uniao_estavel' END,
       x.genero, 'Brasileira', 'Joinville/SC',
       'Maria ' || x.sobrenome,
       'colaborador' || x.n || '@metalurgica-exemplo.demo',
       '(47) 3000-' || lpad(x.n::text, 4, '0'), '(47) 99000-' || lpad(x.n::text, 4, '0'),
       'Rua ' || x.rua, (x.n * 13)::text, x.bairro, 'Joinville', 'SC', '89200-' || lpad((x.n * 3)::text, 3, '0'),
       x.cargo, public.demo_id('cargo:' || x.cargo), x.depto,
       CASE WHEN x.n % 9 = 0 THEN 'Filial Curitiba' WHEN x.n % 11 = 0 THEN 'Centro de Distribuição Itajaí' ELSE 'Matriz' END,
       x.adm, 'CLT',
       CASE WHEN x.depto IN ('Produção','Manutenção') AND x.n % 2 = 0 THEN '6x2 - turno B' ELSE '44h semanais' END,
       x.salario, x.gestor, 'CC-' || x.cc, '341', (1000 + x.n)::text, (50000 + x.n * 17)::text, 'corrente', 'clt',
       true, x.cbo,
       x.adm - 3, x.adm + 362, 'apto',
       x.adm - 3, 'apto',
       CASE WHEN x.status = 'desligado' THEN CURRENT_DATE - 40 END,
       CASE WHEN x.status = 'desligado' THEN CASE WHEN x.n % 2 = 0 THEN 'Pedido de demissão' ELSE 'Dispensa sem justa causa' END END,
       CASE WHEN x.status = 'desligado' THEN 'trabalhado' END,
       CASE WHEN x.status = 'desligado' THEN 30 END
FROM (
  SELECT s.n,
         (ARRAY['Carlos','Mariana','José','Juliana','Marcos','Patrícia','Rafael','Fernanda','Diego','Camila','Paulo','Aline',
                'André','Tatiane','Lucas','Renata','Thiago','Larissa','Fábio','Priscila','Rodrigo','Simone','Eduardo','Débora',
                'Gustavo','Vanessa','Leandro','Cristiane','Márcio','Luciana','Renato','Bianca','Sérgio','Daniela','Vinícius','Eliane',
                'Wagner','Gabriela','Bruno','Helena'])[1 + (s.n % 40)]
         || ' ' ||
         (ARRAY['Albuquerque Teles','Barreto Nunes','Campos Lacerda','Dantas Moreira','Esteves Prado','Falcão Brito','Gouveia Leme',
                'Holanda Pires','Imbassahy Costa','Jardim Siqueira','Leal Fontes','Macedo Arruda','Nogueira Paes','Ornelas Vidal',
                'Peixoto Rangel','Queiroz Bastos','Rezende Matos','Sampaio Valente','Toledo Quintana','Uchôa Ferraz'])[1 + ((s.n * 7) % 20)] AS nome,
         (ARRAY['Albuquerque Teles','Barreto Nunes','Campos Lacerda','Dantas Moreira','Esteves Prado'])[1 + (s.n % 5)] AS sobrenome,
         CASE WHEN (s.n % 2) = 1 THEN 'masculino' ELSE 'feminino' END AS genero,
         c.cargo, c.depto, c.salario, c.cbo, c.gestor,
         CASE WHEN s.n = 62 THEN 'rascunho' WHEN s.n = 63 THEN 'aguardando_documentos' WHEN s.n = 64 THEN 'em_analise'
              WHEN s.n IN (60, 61) THEN 'desligado' ELSE 'concluido' END AS status,
         DATE '1972-01-01' + ((s.n * 211) % 8800) AS nasc,
         CASE WHEN s.n BETWEEN 57 AND 59 THEN CURRENT_DATE - (s.n - 50)
              WHEN s.n BETWEEN 62 AND 64 THEN CURRENT_DATE + (s.n - 55)
              ELSE CURRENT_DATE - (40 + (s.n * 29) % 2100) END AS adm,
         (ARRAY['das Flores','Sete de Setembro','XV de Novembro','das Palmeiras','do Comércio','Santos Dumont'])[1 + (s.n % 6)] AS rua,
         (ARRAY['Centro','Boa Vista','Atiradores','Costa e Silva','Glória','Iririú'])[1 + (s.n % 6)] AS bairro,
         (ARRAY['01','02','03','04'])[1 + (s.n % 4)] AS cc
  FROM generate_series(1, 64) AS s(n)
  JOIN (VALUES
    (1, 12, 'Operador de Usinagem CNC', 'Produção', 3700, '721315', 'Líder de Produção'),
    (13, 21, 'Soldador', 'Produção', 3900, '724315', 'Líder de Produção'),
    (22, 27, 'Montador de Estruturas Metálicas', 'Produção', 2900, '724410', 'Líder de Produção'),
    (28, 29, 'Líder de Produção', 'Produção', 6000, '710205', 'Gerente Industrial'),
    (30, 35, 'Mecânico de Manutenção', 'Manutenção', 4100, '914405', 'Supervisor de Manutenção'),
    (36, 39, 'Eletricista de Manutenção', 'Manutenção', 4300, '951105', 'Supervisor de Manutenção'),
    (40, 40, 'Supervisor de Manutenção', 'Manutenção', 7000, '710210', 'Gerente Industrial'),
    (41, 45, 'Operador de Empilhadeira', 'Logística', 3100, '782220', 'Coordenador de Logística'),
    (46, 51, 'Auxiliar de Logística', 'Logística', 2500, '414105', 'Coordenador de Logística'),
    (52, 52, 'Coordenador de Logística', 'Logística', 6800, '342415', 'Gerente Industrial'),
    (53, 54, 'Analista Financeiro', 'Administrativo', 4400, '252105', 'Gerente Administrativo'),
    (55, 56, 'Analista da Qualidade', 'Administrativo', 4400, '391205', 'Gerente Administrativo'),
    (57, 57, 'Comprador', 'Administrativo', 4000, '354405', 'Gerente Administrativo'),
    (58, 59, 'Analista de RH', 'Recursos Humanos', 4200, '252405', 'Gerente Administrativo'),
    (60, 61, 'Técnico de Segurança do Trabalho', 'Recursos Humanos', 4500, '351605', 'Gerente Administrativo'),
    (62, 64, 'Vendedor Interno', 'Comercial', 3300, '521110', 'Gerente Administrativo')
  ) AS c(lo, hi, cargo, depto, salario, cbo, gestor) ON s.n BETWEEN c.lo AND c.hi
) x
WHERE NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || x.n));

-- ---------------------------------------------------------------------------
-- (5) Liga o login ao tenant demo (com backup do vinculo anterior)
-- ---------------------------------------------------------------------------
DO $vinculo$
DECLARE
  v_email  text := 'leirinuernberg@gmail.com';
  v_uid    uuid;
  v_nome   text;
  v_bkp    text := 'backup_demo_vinculo_' || to_char(CURRENT_DATE, 'YYYYMMDD');
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = lower(v_email) ORDER BY u.created_at LIMIT 1);
  IF v_uid IS NULL THEN
    RAISE NOTICE 'O e-mail % nao existe em auth.users deste ambiente: cadastre o login e rode esta parte de novo. O restante da base ja foi criado.', v_email;
    RETURN;
  END IF;
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1),
                     (SELECT u.raw_user_meta_data ->> 'nome' FROM auth.users u WHERE u.id = v_uid),
                     'Leiri Nuernberg');

  -- Backup do vinculo anterior (so na primeira vez que o login e movido).
  -- A sequencia contigua que cria tabela e montada em texto para o SQL Editor nao
  -- confundir este arquivo com um que cria tabela nova.
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS public.' || quote_ident(v_bkp)
       || ' (momento timestamptz DEFAULT now(), origem text, user_id uuid, tenant_id uuid)';
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = v_uid AND p.tenant_id = 'd3e00000-0000-4000-8000-000000000001') THEN
    EXECUTE format('INSERT INTO public.%I (origem, user_id, tenant_id) SELECT %L, p.user_id, p.tenant_id FROM public.profiles p WHERE p.user_id = %L',
                   v_bkp, 'profiles', v_uid);
    EXECUTE format('INSERT INTO public.%I (origem, user_id, tenant_id) SELECT %L, u.auth_user_id, u.tenant_id FROM public.usuarios_base u WHERE u.auth_user_id = %L',
                   v_bkp, 'usuarios_base', v_uid);
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE user_id = v_uid) THEN
    UPDATE public.profiles SET tenant_id = 'd3e00000-0000-4000-8000-000000000001', onboarding_concluido = true
     WHERE user_id = v_uid;
  ELSE
    INSERT INTO public.profiles (user_id, tenant_id, nome_completo, cargo, onboarding_concluido)
    VALUES (v_uid, 'd3e00000-0000-4000-8000-000000000001', v_nome, 'Gestora de RH', true);
  END IF;

  IF EXISTS (SELECT 1 FROM public.usuarios_base WHERE auth_user_id = v_uid) THEN
    UPDATE public.usuarios_base SET tenant_id = 'd3e00000-0000-4000-8000-000000000001'
     WHERE auth_user_id = v_uid;
  ELSE
    INSERT INTO public.usuarios_base (tenant_id, auth_user_id, nome_completo, email_principal, tipo_usuario, status, cargo_funcao, cpf)
    VALUES ('d3e00000-0000-4000-8000-000000000001', v_uid, v_nome, v_email, 'administrador', 'ativo', 'Gestora de RH', public.demo_cpf(1000 % 1000));
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  SELECT v_uid, 'owner'
  WHERE NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = v_uid AND r.role = 'owner');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Vinculo do login nao concluido: % (%)', SQLERRM, SQLSTATE;
END $vinculo$;

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') AS tenant,
  (SELECT count(*) FROM public.empresa_cadastro WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS empresas,
  (SELECT count(*) FROM public.filiais WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS filiais,
  (SELECT count(*) FROM public.departamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS departamentos,
  (SELECT count(*) FROM public.cargos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS cargos,
  (SELECT count(*) FROM public.admissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS colaboradores,
  (SELECT count(*) FROM public.profiles WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND user_id IN (SELECT id FROM auth.users WHERE lower(email) = 'leirinuernberg@gmail.com')) AS login_ligado_ao_demo,
  CASE WHEN (SELECT count(*) FROM public.admissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 64
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;

-- ---------------------------------------------------------------------------
-- COMO DESFAZER O VINCULO DO LOGIN (devolve o login ao tenant de antes):
--   UPDATE public.profiles p SET tenant_id = b.tenant_id
--     FROM public.backup_demo_vinculo_<aaaammdd> b
--    WHERE b.origem = 'profiles' AND b.user_id = p.user_id;
--   UPDATE public.usuarios_base u SET tenant_id = b.tenant_id
--     FROM public.backup_demo_vinculo_<aaaammdd> b
--    WHERE b.origem = 'usuarios_base' AND b.user_id = u.auth_user_id;
-- ---------------------------------------------------------------------------
