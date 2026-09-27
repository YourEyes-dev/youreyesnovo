-- Seed para ambiente de staging/testes internos
-- Este script popula um tenant fictício com empresa, departamentos, cargos e colaboradores.
-- IMPORTANTE: crie o usuário de autenticação primeiro (via Supabase Dashboard ou API) e
-- substitua o user_id fixo abaixo pelo UUID real do usuário, ou ajuste o script para inserir
-- o profile com o UUID correto.
--
-- Recomendação: executar em uma instância Supabase limpa (staging) para não misturar dados.

BEGIN;

-- IDs fixos para referência cruzada (pode ser alterado conforme necessário)
SET LOCAL seed.tenant_id = '11111111-1111-1111-1111-111111111111';
SET LOCAL seed.empresa_id = '22222222-2222-2222-2222-222222222222';
SET LOCAL seed.user_id = '00000000-0000-0000-0000-000000000000';

-- 1. Tenant de testes
INSERT INTO public.tenants (id, nome, slug, plano, ativo, configuracoes, created_at, updated_at)
VALUES (
  current_setting('seed.tenant_id')::uuid,
  'Empresa Staging LTDA',
  'empresa-staging',
  'enterprise',
  true,
  '{"demo": true, "ambiente": "staging"}'::jsonb,
  now(),
  now()
)
ON CONFLICT (id) DO UPDATE SET
  nome = EXCLUDED.nome,
  slug = EXCLUDED.slug,
  plano = EXCLUDED.plano,
  ativo = EXCLUDED.ativo,
  updated_at = now();

-- 2. Empresa (matriz) de testes
INSERT INTO public.empresa_cadastro (
  id, tenant_id, razao_social, nome_fantasia, cnpj, cidade, estado, cep, telefone, email,
  cnae_principal, cnae_descricao, grau_risco, tipo_pessoa, tipo_unidade, ativo, created_at, updated_at
)
VALUES (
  current_setting('seed.empresa_id')::uuid,
  current_setting('seed.tenant_id')::uuid,
  'Empresa Staging LTDA',
  'Empresa Staging',
  '00.000.000/0001-00',
  'São Paulo', 'SP', '01000-000', '(11) 99999-9999', 'staging@youreyes.local',
  '6201501', 'Desenvolvimento de programas de computador sob encomenda', 2,
  'pj', 'matriz',
  true, now(), now()
)
ON CONFLICT (id) DO UPDATE SET
  razao_social = EXCLUDED.razao_social,
  nome_fantasia = EXCLUDED.nome_fantasia,
  cnpj = EXCLUDED.cnpj,
  updated_at = now();

-- 3. Departamentos
INSERT INTO public.departamentos (id, tenant_id, nome, descricao, ativo, empresa_id, created_at, updated_at)
VALUES
  (gen_random_uuid(), current_setting('seed.tenant_id')::uuid, 'Administrativo', 'Gestão administrativa e financeira', true, current_setting('seed.empresa_id')::uuid, now(), now()),
  (gen_random_uuid(), current_setting('seed.tenant_id')::uuid, 'Recursos Humanos', 'Departamento pessoal e SST', true, current_setting('seed.empresa_id')::uuid, now(), now()),
  (gen_random_uuid(), current_setting('seed.tenant_id')::uuid, 'Operações', 'Operações e produção', true, current_setting('seed.empresa_id')::uuid, now(), now()),
  (gen_random_uuid(), current_setting('seed.tenant_id')::uuid, 'Tecnologia', 'Desenvolvimento e infraestrutura', true, current_setting('seed.empresa_id')::uuid, now(), now())
ON CONFLICT DO NOTHING;

-- 4. Cargos de exemplo
WITH dept AS (
  SELECT id, nome FROM public.departamentos
  WHERE tenant_id = current_setting('seed.tenant_id')::uuid
)
INSERT INTO public.cargos (
  id, tenant_id, nome, descricao, departamento_id, ativo, empresa_id, created_at, updated_at,
  objetivo_funcao, escopo_geral, responsabilidade, nivel
)
SELECT
  gen_random_uuid(),
  current_setting('seed.tenant_id')::uuid,
  CASE d.nome
    WHEN 'Administrativo' THEN 'Analista Financeiro'
    WHEN 'Recursos Humanos' THEN 'Analista de RH'
    WHEN 'Operações' THEN 'Operador de Produção'
    WHEN 'Tecnologia' THEN 'Desenvolvedor Full Stack'
  END,
  'Cargo de testes para ambiente staging',
  d.id,
  true,
  current_setting('seed.empresa_id')::uuid,
  now(), now(),
  'Objetivo genérico da função',
  'Escopo genérico da função',
  'Responsabilidade genérica',
  'pleno'
FROM dept d
ON CONFLICT DO NOTHING;

-- 5. Colaboradores fictícios
DO $$
DECLARE
  v_tenant_id uuid := current_setting('seed.tenant_id')::uuid;
  v_empresa_id uuid := current_setting('seed.empresa_id')::uuid;
BEGIN
  INSERT INTO public.admissoes (
    id, tenant_id, empresa_id, status, nome_completo, cpf, data_nascimento, estado_civil, genero,
    email, telefone, cidade, estado, cargo, departamento, data_admissao,
    tipo_contrato, jornada_trabalho, salario, gestor_imediato, criado_por, created_at, updated_at
  )
  SELECT
    gen_random_uuid(),
    v_tenant_id,
    -- sem empresa_id os painéis filtrados pela empresa do topo mostram zero
    v_empresa_id,
    'concluido'::public.admissao_status,
    'Colaborador ' || n,
    -- CPFs fictícios com dígito verificador válido (o sistema valida)
    (ARRAY['90000000175','90000000256','90000000337','90000000418','90000000507','90000000680','90000000760','90000000841','90000000922','90000001066','90000001147','90000001228','90000001309','90000001490','90000001570','90000001651','90000001732','90000001813','90000001902','90000002038'])[n],
    '1990-01-01',
    'solteiro',
    'masculino',
    'colaborador' || n || '@youreyes.local',
    '(11) 99999-' || LPAD(n::text, 4, '0'),
    'São Paulo', 'SP',
    CASE (n % 4)
      WHEN 0 THEN 'Analista Financeiro'
      WHEN 1 THEN 'Analista de RH'
      WHEN 2 THEN 'Operador de Produção'
      ELSE 'Desenvolvedor Full Stack'
    END,
    CASE (n % 4)
      WHEN 0 THEN 'Administrativo'
      WHEN 1 THEN 'Recursos Humanos'
      WHEN 2 THEN 'Operações'
      ELSE 'Tecnologia'
    END,
    '2024-01-01',
    'CLT',
    '8h diárias',
    5000.00,
    'Gestor Staging',
    current_setting('seed.user_id')::uuid,
    now(),
    now()
  FROM generate_series(1, 20) AS n
  ON CONFLICT DO NOTHING;
END $$;

-- 6. Contexto de IA (ai_context) para testes de geração de funções
UPDATE public.empresa_cadastro
SET ai_context = 'Empresa de tecnologia e serviços de SST. Processos: financeiros, DP, operação de produção e desenvolvimento de software. Atividades esperadas: contas a pagar/receber, folha de pagamento, admissão/demissão, controle de EPIs, desenvolvimento de funcionalidades, suporte a clientes internos.'
WHERE id = current_setting('seed.empresa_id')::uuid;

-- 8. Acesso do administrador de teste: perfil, papel e vínculo com o tenant
--    (sem isto, o login entra num sistema vazio)
INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido)
VALUES (current_setting('seed.user_id')::uuid,
        current_setting('seed.tenant_id')::uuid,
        'Administrador de Testes', true)
ON CONFLICT (user_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id;

INSERT INTO public.user_roles (user_id, role)
VALUES (current_setting('seed.user_id')::uuid, 'owner')
ON CONFLICT (user_id, role) DO NOTHING;

INSERT INTO public.usuarios_base
  (tenant_id, auth_user_id, nome_completo, email_principal, cpf, tipo_usuario, status)
SELECT current_setting('seed.tenant_id')::uuid,
       current_setting('seed.user_id')::uuid,
       'Administrador de Testes', 'admin@teste.youreyes.local',
       '90000009989', 'administrador', 'ativo'
WHERE NOT EXISTS (SELECT 1 FROM public.usuarios_base
                  WHERE auth_user_id = current_setting('seed.user_id')::uuid);

COMMIT;
