-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 02a: pessoas, admissoes, contratos de
-- experiencia, onboarding, cadastros (departamentos/cargos/filiais) e empresa
--
-- PARA QUE SERVE
-- Completa, na "Metalurgica Exemplo Ltda" (100% ficticia), as telas
-- /colaboradores (Ativos, Admissoes, Desligados e a ficha completa com as abas
-- Dados, Documentos, Aprovacao e Historico), /contratos-experiencia,
-- /onboarding-rh, /cadastros/departamentos, /cadastros/cargos,
-- /cadastros/filiais e /empresa (todas as abas). Roda DEPOIS da parte 00.
-- A parte 02b (ferias, atestados, afastamentos e saude) roda depois desta.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO. O arquivo se RECUSA a rodar em qualquer
-- outro banco: so aceita a URL gravada em app_config da homologacao ou do
-- teste. Nunca na producao.
--
-- O QUE FAZ (tudo no tenant demo d3e00000-0000-4000-8000-000000000001)
--   1. acrescenta 27 pessoas ficticias em admissoes: 8 contratados em periodo
--      de experiencia (um deles ja desligado), 4 aprendizes, 1 PCD, 1
--      reabilitado do INSS, 2 vendedores veteranos e 11 candidatos no funil
--      (rascunho, aguardando documentos, em analise, aprovado e reprovado);
--   2. completa a ficha dos colaboradores da parte 00 (nome do pai, PIX,
--      clinica/medico do exame admissional, dependentes, situacao do
--      pre-cadastro) SO onde esses campos estao vazios;
--   3. cria, para TODAS as admissoes do tenant demo, a lista de documentos, as
--      etapas de aprovacao e o historico;
--   4. contratos de experiencia (1o periodo, 2o periodo, vencendo, vencido,
--      efetivado, encerrado), historico e links de assinatura;
--   5. onboarding: modelos, etapas, checklists, mensagens, processos e
--      percepcao cultural;
--   6. complementa departamentos (gestores, filial), cargos (descricao de
--      funcao e SST), filiais (obra com CNO, geolocalizacao) e o cadastro da
--      empresa (SESMT, CIPA, PCD, aprendiz, FAP, TAC, jornada, condicoes
--      especiais) — por UPDATE somente da empresa demo.
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, e-mails @metalurgica-exemplo.demo,
--     CPFs 900.000.0XX com digito valido (public.demo_cpf).
--   - Idempotente: ids fixos (public.demo_id) + "so insere se nao existe"; os
--     UPDATEs so preenchem campos vazios (ou regravam o mesmo valor fixo).
--   - Nao toca em nenhum outro tenant e nao cria tabelas.
--   - Roda numa transacao so; sem tabela temporaria entre comandos.
--
-- ATENCAO: a conferencia final da parte 00 compara colaboradores = 64; depois
-- desta parte o total passa de 64 (de proposito) e aquela linha mostra CONFERIR.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) Trava de ambiente + helpers (os mesmos da parte 00)
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
    RAISE EXCEPTION 'RECUSADO: o tenant demo nao existe. Rode antes a parte 00 (parte_00_base_empresa_demo.sql).';
  END IF;
END $trava$;

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

CREATE OR REPLACE FUNCTION public.demo_id(chave text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT md5('youreyes-demo:' || chave)::uuid
$fn$;

-- ---------------------------------------------------------------------------
-- (2) Novas pessoas em admissoes (ids 'admissao:701' em diante; CPFs 900.000.7XX)
--     701-708 experiencia | 709-712 aprendizes | 713 PCD | 714 reabilitado
--     715-716 veteranos do Comercial | 720-730 funil de admissao
-- ---------------------------------------------------------------------------
INSERT INTO public.admissoes (
  id, tenant_id, empresa_id, status, nome_completo, cpf, rg, data_nascimento, estado_civil, genero, nacionalidade,
  naturalidade, nome_mae, nome_pai, email, telefone, celular, endereco, numero, complemento, bairro, cidade, estado, cep,
  cargo, cargo_id, departamento, filial, data_admissao, tipo_contrato, jornada_trabalho, salario, gestor_imediato,
  centro_custo, banco, agencia, conta, tipo_conta, chave_pix, tipo_vinculo, bate_ponto, cbo,
  exame_admissional_data, exame_admissional_validade, exame_admissional_resultado,
  exame_admissional_clinica, exame_admissional_medico, exame_admissional_crm, exame_admissional_observacoes,
  aso_admissional_data, aso_admissional_resultado,
  data_desligamento, motivo_desligamento, tipo_aviso_previo, dias_aviso_previo,
  contrato_aprendiz, enquadramento_pcd, reabilitado_inss, prazo_determinado, data_fim_contrato,
  onboarding_status, dependentes_irrf, matricula_esocial
)
SELECT public.demo_id('admissao:' || x.n),
       'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       x.status::public.admissao_status,
       x.nome, public.demo_cpf(x.n),
       lpad((2000000 + x.n * 6007)::text, 7, '0'),
       CASE WHEN x.aprendiz THEN CURRENT_DATE - (17 * 365 + 90 + (x.n % 7) * 20)
            ELSE DATE '1980-03-01' + ((x.n * 173) % 7300) END,
       CASE WHEN x.aprendiz THEN 'solteiro' WHEN x.n % 3 = 0 THEN 'solteiro' WHEN x.n % 3 = 1 THEN 'casado' ELSE 'uniao_estavel' END,
       x.genero, 'Brasileira', 'Joinville/SC',
       'Maria ' || x.sobrenome, 'José ' || x.sobrenome,
       'colaborador' || x.n || '@metalurgica-exemplo.demo',
       '(47) 3000-' || lpad((x.n % 10000)::text, 4, '0'), '(47) 99100-' || lpad((x.n % 10000)::text, 4, '0'),
       'Rua ' || x.rua, (x.n % 900 + 10)::text,
       CASE WHEN x.n % 4 = 0 THEN 'Apto ' || (x.n % 40 + 1) ELSE NULL END,
       x.bairro, 'Joinville', 'SC', '89201-' || lpad((x.n % 900)::text, 3, '0'),
       x.cargo, public.demo_id('cargo:' || x.cargo), x.depto,
       CASE WHEN x.n % 5 = 0 THEN 'Filial Curitiba' WHEN x.n % 7 = 0 THEN 'Centro de Distribuição Itajaí' ELSE 'Matriz' END,
       CURRENT_DATE + x.adm_off,
       CASE WHEN x.aprendiz THEN 'aprendiz' WHEN x.exp THEN 'clt_experiencia' ELSE 'CLT' END,
       CASE WHEN x.aprendiz THEN '30h semanais (aprendiz)'
            WHEN x.depto IN ('Produção','Manutenção') AND x.n % 2 = 0 THEN '6x2 - turno B' ELSE '44h semanais' END,
       x.salario, x.gestor, 'CC-0' || (1 + x.n % 4), '341', (2000 + x.n % 1000)::text, (70000 + x.n * 13)::text, 'corrente',
       'colaborador' || x.n || '@metalurgica-exemplo.demo',
       CASE WHEN x.exp THEN 'CLT_PRAZO_DETERMINADO' ELSE 'CLT_PRAZO_INDETERMINADO' END,
       true, x.cbo,
       x.exame_data, x.exame_data + 365, x.exame_res,
       CASE WHEN x.exame_data IS NOT NULL THEN 'Clínica Saúde Ocupacional Exemplo' END,
       CASE WHEN x.exame_data IS NOT NULL THEN 'Dra. Helena Prado Marques' END,
       CASE WHEN x.exame_data IS NOT NULL THEN 'CRM/SC 00000-DEMO' END,
       CASE WHEN x.exame_res = 'inapto' THEN 'Inapto para a função: restrição osteomuscular em coluna lombar (caso fictício de demonstração).'
            WHEN x.exame_data IS NOT NULL THEN 'Sem restrições para a função.' END,
       x.exame_data, x.exame_res,
       CASE WHEN x.status = 'desligado' THEN CURRENT_DATE - 20 END,
       CASE WHEN x.status = 'desligado' THEN 'Término antecipado do contrato de experiência' END,
       CASE WHEN x.status = 'desligado' THEN 'indenizado' END,
       CASE WHEN x.status = 'desligado' THEN 0 END,
       x.aprendiz, x.pcd, x.reab,
       (x.exp OR x.aprendiz),
       CASE WHEN x.aprendiz THEN CURRENT_DATE + x.adm_off + 700
            WHEN x.exp THEN CURRENT_DATE + x.adm_off + 89 END,
       CASE WHEN x.status = 'concluido' THEN 'concluido'
            WHEN x.status IN ('em_analise','aprovado') THEN 'em_analise' ELSE 'pendente' END,
       CASE WHEN x.n % 3 = 1 THEN 1 WHEN x.n % 5 = 0 THEN 2 ELSE 0 END,
       'DEMO-' || lpad(x.n::text, 5, '0')
FROM (
  SELECT v.n, v.nome, v.genero, v.status, v.adm_off, v.exp, v.aprendiz, v.pcd, v.reab,
         c.cargo, c.depto, c.salario, c.cbo, c.gestor,
         split_part(v.nome, ' ', 2) AS sobrenome,
         (ARRAY['das Flores','Sete de Setembro','XV de Novembro','das Palmeiras','do Comércio','Santos Dumont'])[1 + (v.n % 6)] AS rua,
         (ARRAY['Centro','Boa Vista','Atiradores','Costa e Silva','Glória','Iririú'])[1 + (v.n % 6)] AS bairro,
         CASE WHEN v.status IN ('concluido','desligado','em_analise','aprovado') THEN CURRENT_DATE + v.adm_off - 3
              WHEN v.status = 'reprovado' THEN CURRENT_DATE + v.adm_off - 5 END AS exame_data,
         CASE WHEN v.status = 'reprovado' AND v.n = 729 THEN 'inapto'
              WHEN v.status IN ('concluido','desligado','em_analise','aprovado','reprovado') THEN 'apto' END AS exame_res
  FROM (VALUES
    (701, 'Henrique Valadares Souto',   'masculino', 'concluido',              -18, true,  false, false, false, 'Operador de Usinagem CNC'),
    (702, 'Isadora Carvalho Menezes',   'feminino',  'concluido',              -33, true,  false, false, false, 'Auxiliar de Logística'),
    (703, 'Otávio Brandão Linhares',    'masculino', 'concluido',              -39, true,  false, false, false, 'Montador de Estruturas Metálicas'),
    (704, 'Natália Figueiredo Rosa',    'feminino',  'concluido',              -43, true,  false, false, false, 'Soldador'),
    (705, 'Caio Mendes Albuquerque',    'masculino', 'concluido',              -62, true,  false, false, false, 'Vendedor Interno'),
    (706, 'Yasmin Teixeira Borges',     'feminino',  'concluido',              -84, true,  false, false, false, 'Mecânico de Manutenção'),
    (707, 'Ronaldo Pacheco Vasques',    'masculino', 'desligado',              -75, true,  false, false, false, 'Auxiliar de Logística'),
    (708, 'Beatriz Cardoso Lemos',      'feminino',  'concluido',             -100, true,  false, false, false, 'Analista Financeiro'),
    (709, 'Ana Clara Bittencourt',      'feminino',  'concluido',             -210, false, true,  false, false, 'Auxiliar de Logística'),
    (710, 'Matheus Rocha Camargo',      'masculino', 'concluido',             -170, false, true,  false, false, 'Vendedor Interno'),
    (711, 'Letícia Andrade Fonseca',    'feminino',  'concluido',             -120, false, true,  false, false, 'Auxiliar de Logística'),
    (712, 'Pedro Henrique Salles',      'masculino', 'concluido',              -95, false, true,  false, false, 'Vendedor Interno'),
    (713, 'Sandra Regina Moura',        'feminino',  'concluido',             -420, false, false, true,  false, 'Analista da Qualidade'),
    (714, 'Valdemar Oliveira Cunha',    'masculino', 'concluido',             -800, false, false, false, true,  'Operador de Empilhadeira'),
    (715, 'Cláudia Fernandes Teles',    'feminino',  'concluido',             -900, false, false, false, false, 'Vendedor Interno'),
    (716, 'Anderson Pereira Duarte',    'masculino', 'concluido',             -400, false, false, false, false, 'Vendedor Interno'),
    (720, 'Luan Gabriel Siqueira',      'masculino', 'rascunho',                15, false, false, false, false, 'Operador de Usinagem CNC'),
    (721, 'Kelly Cristina Prado',       'feminino',  'rascunho',                20, false, false, false, false, 'Soldador'),
    (722, 'Ricardo Nascimento Alves',   'masculino', 'aguardando_documentos',   10, false, false, false, false, 'Mecânico de Manutenção'),
    (723, 'Mônica Barros Vilela',       'feminino',  'aguardando_documentos',   12, false, false, false, false, 'Auxiliar de Logística'),
    (724, 'Everton Silveira Maia',      'masculino', 'aguardando_documentos',   18, false, false, false, false, 'Técnico de Segurança do Trabalho'),
    (725, 'Talita Rodrigues Cunha',     'feminino',  'em_analise',               8, false, false, false, false, 'Operador de Empilhadeira'),
    (726, 'Jonas Batista Ferraz',       'masculino', 'em_analise',               9, false, false, false, false, 'Eletricista de Manutenção'),
    (727, 'Wesley Moraes Tavares',      'masculino', 'aprovado',                 5, false, false, false, false, 'Soldador'),
    (728, 'Cíntia Lopes Quintela',      'feminino',  'aprovado',                 6, false, false, false, false, 'Comprador'),
    (729, 'Douglas Ribeiro Falcão',     'masculino', 'reprovado',               -3, false, false, false, false, 'Operador de Usinagem CNC'),
    (730, 'Elaine Santos Peixoto',      'feminino',  'reprovado',               -2, false, false, false, false, 'Auxiliar de Logística')
  ) AS v(n, nome, genero, status, adm_off, exp, aprendiz, pcd, reab, cargo)
  JOIN (VALUES
    ('Operador de Usinagem CNC', 'Produção', 3700, '721315', 'Líder de Produção'),
    ('Soldador', 'Produção', 3900, '724315', 'Líder de Produção'),
    ('Montador de Estruturas Metálicas', 'Produção', 2900, '724410', 'Líder de Produção'),
    ('Mecânico de Manutenção', 'Manutenção', 4100, '914405', 'Supervisor de Manutenção'),
    ('Eletricista de Manutenção', 'Manutenção', 4300, '951105', 'Supervisor de Manutenção'),
    ('Operador de Empilhadeira', 'Logística', 3100, '782220', 'Coordenador de Logística'),
    ('Auxiliar de Logística', 'Logística', 2500, '414105', 'Coordenador de Logística'),
    ('Analista Financeiro', 'Administrativo', 4400, '252105', 'Gerente Administrativo'),
    ('Analista da Qualidade', 'Administrativo', 4400, '391205', 'Gerente Administrativo'),
    ('Comprador', 'Administrativo', 4000, '354405', 'Gerente Administrativo'),
    ('Técnico de Segurança do Trabalho', 'Recursos Humanos', 4500, '351605', 'Gerente Administrativo'),
    ('Vendedor Interno', 'Comercial', 3300, '521110', 'Gerente Administrativo')
  ) AS c(cargo, depto, salario, cbo, gestor) ON c.cargo = v.cargo
) x
WHERE NOT EXISTS (SELECT 1 FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || x.n));

-- ---------------------------------------------------------------------------
-- (3) Ficha completa dos colaboradores da parte 00: preenche SO o que esta vazio
--     (nome do pai, complemento, PIX, dados do exame admissional, dependentes
--     para o IRRF, matricula do eSocial e situacao do pre-cadastro).
-- ---------------------------------------------------------------------------
UPDATE public.admissoes a
   SET nome_pai = COALESCE(a.nome_pai, 'José ' || substr(a.nome_mae, 7)),
       complemento = COALESCE(a.complemento,
                              CASE WHEN get_byte(decode(substr(md5(a.id::text), 1, 2), 'hex'), 0) % 4 = 0
                                   THEN 'Apto ' || (get_byte(decode(substr(md5(a.id::text), 3, 2), 'hex'), 0) % 40 + 1) END),
       chave_pix = COALESCE(a.chave_pix, a.email),
       exame_admissional_clinica = COALESCE(a.exame_admissional_clinica,
                                            CASE WHEN a.exame_admissional_data IS NOT NULL THEN 'Clínica Saúde Ocupacional Exemplo' END),
       exame_admissional_medico = COALESCE(a.exame_admissional_medico,
                                           CASE WHEN a.exame_admissional_data IS NOT NULL THEN 'Dra. Helena Prado Marques' END),
       exame_admissional_crm = COALESCE(a.exame_admissional_crm,
                                        CASE WHEN a.exame_admissional_data IS NOT NULL THEN 'CRM/SC 00000-DEMO' END),
       exame_admissional_observacoes = COALESCE(a.exame_admissional_observacoes,
                                                CASE WHEN a.exame_admissional_data IS NOT NULL THEN 'Sem restrições para a função.' END),
       dependentes_irrf = CASE WHEN COALESCE(a.dependentes_irrf, 0) = 0
                               THEN get_byte(decode(substr(md5(a.id::text), 5, 2), 'hex'), 0) % 4
                               ELSE a.dependentes_irrf END,
       matricula_esocial = COALESCE(a.matricula_esocial, 'DEMO-' || upper(substr(md5(a.id::text), 1, 6))),
       onboarding_status = CASE WHEN a.status IN ('concluido', 'desligado') AND a.onboarding_status = 'pendente'
                                     AND get_byte(decode(substr(md5(a.id::text), 7, 2), 'hex'), 0) % 12 <> 0 THEN 'concluido'
                                WHEN a.status IN ('concluido', 'desligado') AND a.onboarding_status = 'pendente'
                                     AND get_byte(decode(substr(md5(a.id::text), 7, 2), 'hex'), 0) % 24 = 0 THEN 'em_analise'
                                ELSE a.onboarding_status END
 WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND (a.nome_pai IS NULL OR a.chave_pix IS NULL OR a.matricula_esocial IS NULL
        OR (a.exame_admissional_data IS NOT NULL AND a.exame_admissional_clinica IS NULL)
        OR (a.status IN ('concluido', 'desligado') AND a.onboarding_status = 'pendente'));

-- ---------------------------------------------------------------------------
-- (4) Documentos, etapas de aprovacao e historico de TODAS as admissoes do demo
-- ---------------------------------------------------------------------------
INSERT INTO public.admissao_documentos (
  id, admissao_id, tenant_id, nome, tipo, obrigatorio, status, arquivo_url, arquivo_nome, arquivo_tamanho,
  data_envio, observacao, aprovado_por, data_aprovacao
)
SELECT public.demo_id('admdoc:' || a.id::text || ':' || d.nome),
       a.id, a.tenant_id, d.nome, d.tipo, d.obrigatorio,
       s.status::public.documento_status,
       CASE WHEN s.status <> 'pendente' THEN 'demo/admissoes/' || left(a.id::text, 8) || '/' || d.slug || '.pdf' END,
       CASE WHEN s.status <> 'pendente' THEN d.slug || '.pdf' END,
       CASE WHEN s.status <> 'pendente' THEN 150000 + d.ordem * 23000 END,
       CASE WHEN s.status <> 'pendente' THEN LEAST(now(), (LEAST(a.data_admissao, CURRENT_DATE) - 14 + d.ordem)::timestamptz + interval '10 hours') END,
       CASE WHEN s.status = 'rejeitado' THEN
              CASE WHEN d.nome = 'Exame Admissional' THEN 'ASO com resultado inapto: candidato não pode ser admitido na função.'
                   ELSE 'Imagem ilegível: reenviar o documento com melhor resolução.' END
            END,
       CASE WHEN s.status = 'aprovado' THEN (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1) END,
       CASE WHEN s.status = 'aprovado' THEN LEAST(now(), (LEAST(a.data_admissao, CURRENT_DATE) - 12 + d.ordem)::timestamptz + interval '15 hours') END
FROM public.admissoes a
CROSS JOIN (VALUES
  (1, 'RG', 'identidade', true, 'rg'),
  (2, 'CPF', 'identidade', true, 'cpf'),
  (3, 'Comprovante de Residência', 'endereco', true, 'comprovante-residencia'),
  (4, 'Título de Eleitor', 'identidade', true, 'titulo-eleitor'),
  (5, 'Carteira de Trabalho (CTPS)', 'trabalho', true, 'ctps'),
  (6, 'Carteira de Reservista', 'identidade', false, 'reservista'),
  (7, 'Certidão de Nascimento/Casamento', 'civil', true, 'certidao-civil'),
  (8, 'Foto 3x4', 'foto', true, 'foto-3x4'),
  (9, 'Comprovante de Escolaridade', 'formacao', true, 'escolaridade'),
  (10, 'Exame Admissional', 'saude', true, 'aso-admissional'),
  (11, 'Certificado de Cursos', 'formacao', false, 'certificados'),
  (12, 'Certidão de Nascimento dos Filhos', 'dependentes', false, 'certidao-filhos')
) AS d(ordem, nome, tipo, obrigatorio, slug)
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN a.status IN ('concluido', 'desligado', 'aprovado') THEN
      CASE WHEN d.obrigatorio THEN 'aprovado'
           WHEN d.ordem = 6 AND a.genero = 'feminino' THEN 'pendente'
           WHEN d.ordem = 12 AND get_byte(decode(substr(md5(a.id::text), 9, 2), 'hex'), 0) % 3 <> 0 THEN 'pendente'
           ELSE 'aprovado' END
    WHEN a.status = 'em_analise' THEN
      CASE WHEN d.ordem <= 6 THEN 'aprovado' WHEN d.obrigatorio THEN 'enviado' ELSE 'pendente' END
    WHEN a.status = 'aguardando_documentos' THEN
      CASE WHEN d.ordem IN (1, 2) THEN 'enviado'
           WHEN d.ordem = 3 AND get_byte(decode(substr(md5(a.id::text), 11, 2), 'hex'), 0) % 2 = 0 THEN 'rejeitado'
           WHEN d.ordem IN (3, 5) THEN 'enviado'
           ELSE 'pendente' END
    WHEN a.status = 'reprovado' THEN
      CASE WHEN d.ordem <= 5 THEN 'aprovado'
           WHEN d.ordem = 10 AND a.exame_admissional_resultado = 'inapto' THEN 'rejeitado'
           WHEN d.obrigatorio THEN 'enviado' ELSE 'pendente' END
    ELSE 'pendente'  -- rascunho
  END AS status
) s
WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.admissao_documentos x WHERE x.admissao_id = a.id AND x.nome = d.nome);

INSERT INTO public.admissao_workflow (
  id, admissao_id, tenant_id, etapa, ordem, status, responsavel_nome, observacao, data_acao
)
SELECT public.demo_id('admwf:' || a.id::text || ':' || w.ordem),
       a.id, a.tenant_id, w.etapa, w.ordem,
       s.status::public.workflow_status,
       CASE WHEN w.ordem = 1 THEN 'Sistema'
            WHEN s.status = 'pendente' THEN 'Pendente'
            WHEN w.ordem = 2 THEN 'Camila Duarte (RH)'
            WHEN w.ordem = 3 THEN 'Camila Duarte (RH)'
            ELSE 'Fábio Lacerda (Gerência)' END,
       CASE WHEN s.status = 'rejeitado' THEN 'Candidato reprovado: ' ||
              CASE WHEN a.exame_admissional_resultado = 'inapto' THEN 'ASO inapto para a função.' ELSE 'não atendeu aos requisitos da vaga.' END
            WHEN s.status = 'aprovado' AND w.ordem = 2 THEN 'Documentação conferida.'
            WHEN s.status = 'aprovado' AND w.ordem = 3 THEN 'Aprovado pelo RH.' END,
       CASE WHEN s.status <> 'pendente'
            THEN LEAST(now(), (LEAST(a.data_admissao, CURRENT_DATE) - 14 + w.ordem * 3)::timestamptz + interval '11 hours') END
FROM public.admissoes a
CROSS JOIN (VALUES
  (1, 'Cadastro Inicial'), (2, 'Análise Documental'), (3, 'Aprovação RH'), (4, 'Aprovação Final')
) AS w(ordem, etapa)
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN w.ordem = 1 THEN 'aprovado'
    WHEN a.status IN ('concluido', 'desligado') THEN 'aprovado'
    WHEN a.status = 'aprovado' THEN CASE WHEN w.ordem <= 3 THEN 'aprovado' ELSE 'pendente' END
    WHEN a.status = 'em_analise' THEN CASE WHEN w.ordem = 2 THEN 'aprovado' ELSE 'pendente' END
    WHEN a.status = 'reprovado' THEN CASE WHEN w.ordem = 2 THEN 'aprovado' WHEN w.ordem = 3 THEN 'rejeitado' ELSE 'pendente' END
    ELSE 'pendente'
  END AS status
) s
WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.admissao_workflow x WHERE x.admissao_id = a.id AND x.ordem = w.ordem);

INSERT INTO public.admissao_historico (id, admissao_id, tenant_id, acao, descricao, usuario_nome, created_at)
SELECT public.demo_id('admhist:' || a.id::text || ':' || h.seq),
       a.id, a.tenant_id, h.acao, replace(h.descricao, '{nome}', a.nome_completo), h.usuario,
       LEAST(now(), (LEAST(a.data_admissao, CURRENT_DATE) - 15 + h.dia)::timestamptz + interval '9 hours 30 minutes')
FROM public.admissoes a
CROSS JOIN (VALUES
  (1, 1, 'Admissão criada', 'Nova admissão criada para {nome}', 'Camila Duarte (RH)', 'rascunho'),
  (2, 3, 'Link de pré-cadastro enviado', 'Link para completar o cadastro enviado ao candidato {nome}', 'Camila Duarte (RH)', 'aguardando_documentos'),
  (3, 6, 'Documentos recebidos', 'Documentos pessoais de {nome} recebidos e em conferência', 'Camila Duarte (RH)', 'em_analise'),
  (4, 9, 'Exame admissional registrado', 'ASO admissional de {nome} anexado ao cadastro', 'Clínica Saúde Ocupacional Exemplo', 'aprovado'),
  (5, 11, 'Admissão aprovada', 'Admissão de {nome} aprovada pelo RH', 'Camila Duarte (RH)', 'concluido'),
  (6, 14, 'Admissão concluída', 'Cadastro de {nome} concluído e enviado ao eSocial (S-2200)', 'Sistema', 'concluido')
) AS h(seq, dia, acao, descricao, usuario, ate)
WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND (   (h.ate = 'rascunho')
       OR (h.ate = 'aguardando_documentos' AND a.status <> 'rascunho')
       OR (h.ate = 'em_analise' AND a.status IN ('em_analise', 'aprovado', 'reprovado', 'concluido', 'desligado'))
       OR (h.ate = 'aprovado' AND a.status IN ('aprovado', 'reprovado', 'concluido', 'desligado'))
       OR (h.ate = 'concluido' AND a.status IN ('concluido', 'desligado')))
  AND NOT EXISTS (SELECT 1 FROM public.admissao_historico x WHERE x.id = public.demo_id('admhist:' || a.id::text || ':' || h.seq));

-- ---------------------------------------------------------------------------
-- (5) Contratos de experiencia: configuracao da empresa, contratos, historico
--     e links de assinatura. As datas seguem a data de admissao de cada pessoa.
-- ---------------------------------------------------------------------------
INSERT INTO public.empresa_experiencia_config (
  id, tenant_id, empresa_id, modelo_periodos, duracao_primeiro_periodo, duracao_segundo_periodo,
  clausula_assecuratoria_padrao, dias_antecedencia_acao, alerta_15_dias, alerta_7_dias, alerta_2_dias, politica_interna
)
SELECT public.demo_id('expcfg:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       '2_periodos', 45, 45, true, 10, true, true, true,
       'Contratos de experiência de 45 + 45 dias. O gestor imediato avalia o colaborador até 10 dias antes do fim de cada período; a efetivação ou o encerramento é decidido pelo RH com a gerência.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.empresa_experiencia_config c
   WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND c.empresa_id = 'd3e00000-0000-4000-8000-000000000002');

INSERT INTO public.contratos_experiencia (
  id, tenant_id, empresa_id, admissao_id, colaborador_nome, colaborador_cpf, cargo, departamento, filial,
  gestor_imediato, salario, jornada_trabalho, data_admissao, duracao_primeiro_periodo, data_fim_primeiro_periodo,
  prorrogado, duracao_prorrogacao, data_inicio_prorrogacao, data_fim_prorrogacao, data_prorrogacao_registro,
  prorrogado_por_nome, clausula_assecuratoria, status, data_efetivacao, efetivado_por_nome,
  data_encerramento, tipo_encerramento, motivo_encerramento, encerrado_por_nome,
  alerta_15_dias_enviado, alerta_7_dias_enviado, alerta_2_dias_enviado, observacoes, created_at, updated_at
)
SELECT public.demo_id('exp:' || e.n),
       a.tenant_id, a.empresa_id, a.id, a.nome_completo, a.cpf, a.cargo, a.departamento, a.filial,
       a.gestor_imediato, a.salario, a.jornada_trabalho, a.data_admissao,
       e.dur1, a.data_admissao + e.dur1 - 1,
       e.dur2 IS NOT NULL, e.dur2,
       CASE WHEN e.dur2 IS NOT NULL THEN a.data_admissao + e.dur1 END,
       CASE WHEN e.dur2 IS NOT NULL THEN a.data_admissao + e.dur1 + e.dur2 - 1 END,
       CASE WHEN e.dur2 IS NOT NULL THEN (a.data_admissao + e.dur1 - 6)::timestamptz + interval '14 hours' END,
       CASE WHEN e.dur2 IS NOT NULL THEN 'Camila Duarte (RH)' END,
       (get_byte(decode(substr(md5(a.id::text), 13, 2), 'hex'), 0) % 3 = 0),
       e.status,
       CASE WHEN e.status = 'efetivado' THEN a.data_admissao + COALESCE(e.dur1 + e.dur2, e.dur1) END,
       CASE WHEN e.status = 'efetivado' THEN 'Fábio Lacerda (Gerência)' END,
       CASE WHEN e.status = 'encerrado' THEN CURRENT_DATE - 20 END,
       CASE WHEN e.status = 'encerrado' THEN 'rescisao_antecipada_empregador' END,
       CASE WHEN e.status = 'encerrado' THEN 'Desempenho abaixo do esperado no 2º período de experiência.' END,
       CASE WHEN e.status = 'encerrado' THEN 'Camila Duarte (RH)' END,
       (CASE WHEN e.dur2 IS NOT NULL THEN a.data_admissao + e.dur1 + e.dur2 - 1 ELSE a.data_admissao + e.dur1 - 1 END - CURRENT_DATE) <= 15,
       (CASE WHEN e.dur2 IS NOT NULL THEN a.data_admissao + e.dur1 + e.dur2 - 1 ELSE a.data_admissao + e.dur1 - 1 END - CURRENT_DATE) <= 7,
       (CASE WHEN e.dur2 IS NOT NULL THEN a.data_admissao + e.dur1 + e.dur2 - 1 ELSE a.data_admissao + e.dur1 - 1 END - CURRENT_DATE) <= 2,
       e.obs,
       a.data_admissao::timestamptz + interval '8 hours',
       now()
FROM (VALUES
  (57,  45, NULL::int, 'em_experiencia',            'Recém-contratado: acompanhamento semanal com o gestor.'),
  (58,  45, NULL,      'em_experiencia',            'Recém-contratada: integração em andamento.'),
  (59,  45, NULL,      'em_experiencia',            NULL),
  (701, 45, NULL,      'em_experiencia',            'Boa adaptação à máquina CNC; treinamento de NR-12 concluído.'),
  (702, 45, NULL,      'em_experiencia',            NULL),
  (703, 45, NULL,      'em_experiencia',            'Avaliação do gestor agendada para esta semana.'),
  (704, 45, NULL,      'em_experiencia',            'Prazo curto: decidir prorrogação ou efetivação com a gerência.'),
  (705, 45, 45,        'em_experiencia_2_periodo',  'Prorrogado por mais 45 dias após avaliação do gestor.'),
  (706, 45, 45,        'em_experiencia_2_periodo',  'Segundo período próximo do fim: decidir efetivação.'),
  (1,   45, 45,        'em_experiencia_2_periodo',  NULL),
  (2,   45, 45,        'efetivado',                 'Efetivado após os dois períodos, com avaliação positiva.'),
  (3,   30, 60,        'efetivado',                 'Modelo 30 + 60 dias; efetivado ao final do segundo período.'),
  (707, 45, 45,        'encerrado',                 'Contrato encerrado antes do prazo (rescisão antecipada).'),
  (708, 45, NULL,      'vencido_automatico',        'Prazo do 1º período venceu sem decisão: contrato passou a prazo indeterminado. Regularizar o registro.')
) AS e(n, dur1, dur2, status, obs)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || e.n)
WHERE NOT EXISTS (SELECT 1 FROM public.contratos_experiencia c WHERE c.id = public.demo_id('exp:' || e.n));

-- Quem esta em experiencia ativa passa a constar como "clt_experiencia" na ficha.
-- (Os contratos acima ja existem; por isso o gatilho de criacao automatica nao duplica.)
UPDATE public.admissoes a
   SET tipo_contrato = 'clt_experiencia'
  FROM public.contratos_experiencia c
 WHERE c.admissao_id = a.id
   AND c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND c.status IN ('em_experiencia', 'em_experiencia_2_periodo')
   AND a.tipo_contrato = 'CLT';

INSERT INTO public.contratos_experiencia_historico (id, tenant_id, contrato_id, acao, descricao, usuario_nome, created_at)
SELECT public.demo_id('exphist:' || c.id::text || ':' || h.seq),
       c.tenant_id, c.id, h.acao,
       CASE h.acao
         WHEN 'criacao' THEN 'Contrato de experiência criado: ' || c.duracao_primeiro_periodo || ' dias, término em ' || to_char(c.data_fim_primeiro_periodo, 'DD/MM/YYYY') || '.'
         WHEN 'alerta' THEN 'Alerta enviado ao gestor e ao RH: o período de experiência está perto do fim.'
         WHEN 'prorrogacao' THEN 'Contrato prorrogado por ' || c.duracao_prorrogacao || ' dias. Novo término: ' || to_char(c.data_fim_prorrogacao, 'DD/MM/YYYY') || '. Total: ' || (c.duracao_primeiro_periodo + c.duracao_prorrogacao) || ' dias.'
         WHEN 'efetivacao' THEN 'Colaborador efetivado em ' || to_char(c.data_efetivacao, 'DD/MM/YYYY') || '. Vínculo convertido para prazo indeterminado.'
         ELSE 'Contrato encerrado: rescisão antecipada pelo empregador. Data: ' || to_char(c.data_encerramento, 'DD/MM/YYYY') || '.'
       END,
       CASE WHEN h.acao = 'criacao' THEN 'Sistema' WHEN h.acao = 'alerta' THEN 'Sistema' ELSE 'Camila Duarte (RH)' END,
       CASE h.acao
         WHEN 'criacao' THEN c.created_at
         WHEN 'alerta' THEN (COALESCE(c.data_fim_prorrogacao, c.data_fim_primeiro_periodo) - 15)::timestamptz + interval '7 hours'
         WHEN 'prorrogacao' THEN c.data_prorrogacao_registro
         WHEN 'efetivacao' THEN c.data_efetivacao::timestamptz + interval '10 hours'
         ELSE c.data_encerramento::timestamptz + interval '10 hours'
       END
FROM public.contratos_experiencia c
CROSS JOIN (VALUES (1, 'criacao'), (2, 'alerta'), (3, 'prorrogacao'), (4, 'efetivacao'), (5, 'encerramento')) AS h(seq, acao)
WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND (   h.acao = 'criacao'
       OR (h.acao = 'alerta' AND c.alerta_15_dias_enviado AND c.status <> 'vencido_automatico'
           AND COALESCE(c.data_fim_prorrogacao, c.data_fim_primeiro_periodo) - 15 <= CURRENT_DATE)
       OR (h.acao = 'prorrogacao' AND c.prorrogado)
       OR (h.acao = 'efetivacao' AND c.status = 'efetivado')
       OR (h.acao = 'encerramento' AND c.status = 'encerrado'))
  AND NOT EXISTS (SELECT 1 FROM public.contratos_experiencia_historico x
                   WHERE x.id = public.demo_id('exphist:' || c.id::text || ':' || h.seq));

INSERT INTO public.experiencia_assinatura_links (
  id, tenant_id, contrato_id, token, signatario_nome, signatario_papel, signatario_email, documento_html,
  tipo_documento, status, assinado_em, expira_em, criado_por_nome, created_at
)
SELECT public.demo_id('expass:' || c.id::text || ':' || d.tipo),
       c.tenant_id, c.id, 'demo-exp-' || substr(md5(c.id::text || d.tipo), 1, 24),
       c.colaborador_nome, 'colaborador', NULL,
       '<h1>' || d.titulo || '</h1><p>Documento fictício de demonstração para ' || c.colaborador_nome || '.</p>',
       d.tipo,
       CASE WHEN d.assinado THEN 'assinado' ELSE 'pendente' END,
       CASE WHEN d.assinado THEN d.quando::timestamptz + interval '16 hours' END,
       now() + interval '30 days',
       'Camila Duarte (RH)',
       d.quando::timestamptz + interval '9 hours'
FROM public.contratos_experiencia c
CROSS JOIN LATERAL (VALUES
  ('contrato', 'Contrato de Experiência', c.data_admissao, c.data_admissao + 20 < CURRENT_DATE OR c.status IN ('efetivado', 'encerrado', 'vencido_automatico')),
  ('prorrogacao', 'Termo de Prorrogação', c.data_inicio_prorrogacao - 5, true),
  ('efetivacao', 'Termo de Efetivação', c.data_efetivacao, true),
  ('rescisao', 'Termo de Rescisão', c.data_encerramento, true)
) AS d(tipo, titulo, quando, assinado)
WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND d.quando IS NOT NULL
  AND (d.tipo = 'contrato'
       OR (d.tipo = 'prorrogacao' AND c.prorrogado)
       OR (d.tipo = 'efetivacao' AND c.status = 'efetivado')
       OR (d.tipo = 'rescisao' AND c.status = 'encerrado'))
  AND NOT EXISTS (SELECT 1 FROM public.experiencia_assinatura_links x
                   WHERE x.id = public.demo_id('expass:' || c.id::text || ':' || d.tipo));

-- ---------------------------------------------------------------------------
-- (6) Onboarding RH: modelos, etapas, checklists, mensagens, processos,
--     andamento do checklist e percepcao cultural
-- ---------------------------------------------------------------------------
INSERT INTO public.onboarding_templates (
  id, tenant_id, nome, descricao, ativo, funcoes, unidades, departamentos, tipos_vinculo, prazo_dias,
  pontuacao_total, emitir_certificado, conexao_pdi, criado_por_nome, created_at
)
SELECT public.demo_id('onbtpl:' || t.k), 'd3e00000-0000-4000-8000-000000000001',
       t.nome, t.descricao, t.ativo, NULL, NULL, t.deptos, t.vinculos, t.prazo, t.pontos, true, t.pdi,
       'Camila Duarte (RH)', now() - (t.dias || ' days')::interval
FROM (VALUES
  (1, 'Integração Chão de Fábrica',
      'Trilha de acolhimento para Produção, Manutenção e Logística: segurança em primeiro lugar, EPIs, 5S e rotina do turno.',
      true, ARRAY['Produção','Manutenção','Logística']::text[], NULL::text[], 15, 100, true, 120),
  (2, 'Integração Administrativa e Comercial',
      'Trilha para Administrativo, RH e Comercial: cultura, sistemas internos, políticas e relacionamento com clientes.',
      true, ARRAY['Administrativo','Recursos Humanos','Comercial']::text[], NULL::text[], 20, 100, true, 110),
  (3, 'Integração Geral — Todos os colaboradores',
      'Modelo-base com apresentação institucional, cultura e valores. Usado quando nenhuma trilha específica se aplica.',
      true, NULL::text[], NULL::text[], 30, 100, false, 100),
  (4, 'Integração de Jovem Aprendiz (em construção)',
      'Rascunho da trilha para aprendizes, com foco em formação profissional e acompanhamento do orientador.',
      false, NULL::text[], ARRAY['aprendiz']::text[], 45, 60, true, 20)
) AS t(k, nome, descricao, ativo, deptos, vinculos, prazo, pontos, pdi, dias)
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_templates x WHERE x.id = public.demo_id('onbtpl:' || t.k));

INSERT INTO public.onboarding_etapas (
  id, tenant_id, template_id, titulo, descricao, tipo, conteudo_texto, formato, ordem, pontuacao, obrigatoria,
  tempo_estimado_min, ativo
)
SELECT public.demo_id('onbetp:' || e.k || ':' || e.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('onbtpl:' || e.k), e.titulo, e.descricao, e.tipo::public.onboarding_etapa_tipo, e.texto,
       'texto', e.ordem, e.pontos, e.obrig, e.min, true
FROM (VALUES
  (1, 1, 'Boas-vindas e apresentação da empresa', 'Quem somos, o que fabricamos e como a fábrica está organizada.', 'apresentacao_institucional',
     'A Metalúrgica Exemplo fabrica estruturas e esquadrias de metal. Você vai conhecer os setores, os turnos e as pessoas com quem vai trabalhar.', 10, true, 15),
  (1, 2, 'Segurança do trabalho e EPIs', 'Regras de ouro de segurança, uso correto dos EPIs e como comunicar um risco.', 'conteudo_livre',
     'Use sempre os EPIs da sua função, respeite a sinalização e interrompa a atividade diante de qualquer condição insegura. Comunique o líder imediatamente.', 25, true, 30),
  (1, 3, 'Mural de boas-vindas', 'Mensagens da liderança e da equipe para você.', 'mural_boas_vindas', NULL, 5, false, 5),
  (1, 4, 'Checklist de integração', 'Itens práticos dos primeiros dias: crachá, vestiário, EPIs, treinamentos e ponto.', 'checklist_integracao', NULL, 20, true, 30),
  (1, 5, 'Quiz: segurança na prática', 'Cinco perguntas rápidas para fixar as regras de segurança.', 'quiz',
     '1) Quando devo usar protetor auricular? 2) O que fazer ao ver um risco? 3) Onde ficam as saídas de emergência?', 25, true, 10),
  (1, 6, 'Reflexão: minhas primeiras semanas', 'Conte como foi a recepção e o que ainda ficou confuso.', 'reflexao',
     'Como você se sentiu acolhido(a)? Há algo da rotina que ainda não ficou claro?', 15, false, 15),
  (2, 1, 'Boas-vindas e apresentação da empresa', 'Visão geral da empresa, organograma e áreas de apoio.', 'apresentacao_institucional',
     'Conheça a história, o organograma e os canais de comunicação internos da Metalúrgica Exemplo.', 10, true, 15),
  (2, 2, 'Nossa cultura e valores', 'Os valores que orientam as decisões do dia a dia.', 'cultura_valores',
     'Segurança, respeito, qualidade e melhoria contínua: como cada valor aparece na prática.', 20, true, 20),
  (2, 3, 'Mural de boas-vindas', 'Mensagens da gestão e dos colegas de área.', 'mural_boas_vindas', NULL, 5, false, 5),
  (2, 4, 'Checklist de integração', 'Acessos, sistemas, políticas internas e reuniões de apresentação.', 'checklist_integracao', NULL, 20, true, 30),
  (2, 5, 'Quiz: conhecendo a empresa', 'Perguntas sobre política de ponto, benefícios e canais de ouvidoria.', 'quiz',
     '1) Como registro o ponto? 2) Onde consulto meus benefícios? 3) Como acesso a ouvidoria?', 25, true, 10),
  (2, 6, 'Reflexão: expectativas e primeiras entregas', 'Alinhe com o gestor o que se espera nos primeiros 90 dias.', 'reflexao',
     'Quais são as três primeiras entregas combinadas com seu gestor?', 20, false, 15),
  (3, 1, 'Boas-vindas e apresentação da empresa', 'Visão geral e primeiros passos.', 'apresentacao_institucional',
     'Seja bem-vindo(a)! Esta trilha apresenta a empresa e a sua função.', 20, true, 15),
  (3, 2, 'Nossa cultura e valores', 'Valores e comportamentos esperados.', 'cultura_valores', 'Nossos valores no dia a dia.', 30, true, 20),
  (3, 3, 'Checklist de integração', 'Itens essenciais da primeira semana.', 'checklist_integracao', NULL, 30, true, 20),
  (3, 4, 'Reflexão final', 'Feedback sobre a integração.', 'reflexao', 'O que podemos melhorar na sua recepção?', 20, false, 10),
  (4, 1, 'Boas-vindas ao programa de aprendizagem', 'Como funciona o programa e quem é seu orientador.', 'apresentacao_institucional',
     'Aprendizagem profissional: teoria na instituição de ensino e prática na empresa.', 30, true, 15),
  (4, 2, 'Plano de formação', 'Metas de aprendizado do primeiro semestre.', 'reflexao', 'Quais habilidades você quer desenvolver?', 30, true, 15)
) AS e(k, ordem, titulo, descricao, tipo, texto, pontos, obrig, min)
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_etapas x WHERE x.id = public.demo_id('onbetp:' || e.k || ':' || e.ordem));

INSERT INTO public.onboarding_checklist_items (id, tenant_id, etapa_id, titulo, descricao, ordem, obrigatorio)
SELECT public.demo_id('onbitem:' || i.k || ':' || i.etapa || ':' || i.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('onbetp:' || i.k || ':' || i.etapa), i.titulo, i.descricao, i.ordem, i.obrig
FROM (VALUES
  (1, 4, 1, 'Retirar crachá e armário no vestiário', 'Com o RH, no primeiro dia.', true),
  (1, 4, 2, 'Receber e assinar a ficha de EPIs', 'Entrega conforme a função, com treinamento de uso.', true),
  (1, 4, 3, 'Treinamento de integração em segurança', 'Duração de 4 horas, com o técnico de segurança.', true),
  (1, 4, 4, 'Apresentação ao líder e à equipe do turno', 'Visita guiada pelo setor.', true),
  (1, 4, 5, 'Cadastrar a biometria do ponto eletrônico', 'Na portaria ou com o RH.', false),
  (2, 4, 1, 'Receber notebook, e-mail e acessos aos sistemas', 'Solicitação aberta pelo RH ao TI.', true),
  (2, 4, 2, 'Ler e aceitar a política de privacidade (LGPD)', 'Aceite digital no sistema.', true),
  (2, 4, 3, 'Reunião de alinhamento de metas com o gestor', 'Primeira semana.', true),
  (2, 4, 4, 'Conhecer os benefícios e o plano de saúde', 'Apresentação feita pelo RH.', false),
  (3, 3, 1, 'Entregar documentos pendentes ao RH', NULL, true),
  (3, 3, 2, 'Conhecer o gestor e a equipe', NULL, true),
  (3, 3, 3, 'Realizar o treinamento obrigatório de integração', NULL, true)
) AS i(k, etapa, ordem, titulo, descricao, obrig)
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_checklist_items x
                   WHERE x.id = public.demo_id('onbitem:' || i.k || ':' || i.etapa || ':' || i.ordem));

INSERT INTO public.onboarding_mensagens (id, tenant_id, etapa_id, autor_nome, autor_cargo, mensagem, tipo, ordem)
SELECT public.demo_id('onbmsg:' || m.k || ':' || m.etapa || ':' || m.ordem), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('onbetp:' || m.k || ':' || m.etapa), m.autor, m.cargo, m.mensagem, 'texto', m.ordem
FROM (VALUES
  (1, 3, 1, 'Fábio Lacerda', 'Gerente Industrial', 'Seja muito bem-vindo(a)! Aqui, a segurança de cada pessoa vem antes de qualquer meta.'),
  (1, 3, 2, 'Rogério Pimentel', 'Líder de Produção', 'Qualquer dúvida no turno, pode me chamar. Estamos juntos!'),
  (1, 3, 3, 'Equipe de Manutenção', 'Time', 'Chegou gente boa! Passe na oficina para um café quando puder.'),
  (2, 3, 1, 'Camila Duarte', 'Analista de RH', 'Estamos felizes com a sua chegada. Conte comigo na sua integração.'),
  (2, 3, 2, 'Fábio Lacerda', 'Gerente Industrial', 'Bem-vindo(a) ao time! Queremos ouvir suas ideias desde o primeiro dia.')
) AS m(k, etapa, ordem, autor, cargo, mensagem)
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_mensagens x
                   WHERE x.id = public.demo_id('onbmsg:' || m.k || ':' || m.etapa || ':' || m.ordem));

-- Processos: quem entrou recentemente (e os aprendizes). Status segue o tempo de casa.
INSERT INTO public.onboarding_processos (
  id, tenant_id, admissao_id, template_id, colaborador_nome, colaborador_cpf, status, data_inicio, data_conclusao,
  progresso, pontos_obtidos, certificado_emitido, pdi_alimentado, created_at, updated_at
)
SELECT public.demo_id('onbproc:' || p.n), a.tenant_id, a.id,
       public.demo_id('onbtpl:' || CASE WHEN a.departamento IN ('Produção','Manutenção','Logística') THEN 1 ELSE 2 END),
       a.nome_completo, a.cpf, p.status,
       a.data_admissao::timestamptz + interval '8 hours',
       CASE WHEN p.status = 'concluido' THEN (a.data_admissao + p.dias_conclusao)::timestamptz + interval '17 hours' END,
       p.progresso, (p.progresso * 100) / 100, p.status = 'concluido' AND p.dias_conclusao >= 10, p.status = 'concluido',
       a.data_admissao::timestamptz + interval '8 hours', now()
FROM (VALUES
  (57,  'em_andamento', 40, NULL::int), (58,  'em_andamento', 25, NULL), (59,  'pendente', 0, NULL),
  (701, 'em_andamento', 80, NULL), (702, 'em_andamento', 100, NULL), (703, 'concluido', 100, 9),
  (704, 'concluido', 100, 12), (705, 'concluido', 100, 14), (706, 'concluido', 100, 11),
  (1,   'concluido', 100, 13), (2,   'concluido', 100, 16), (3,   'concluido', 100, 10),
  (707, 'cancelado', 35, NULL), (708, 'concluido', 100, 18),
  (709, 'concluido', 100, 20), (710, 'concluido', 100, 17), (711, 'concluido', 100, 15), (712, 'em_andamento', 60, NULL),
  (713, 'concluido', 100, 12), (716, 'concluido', 100, 9)
) AS p(n, status, progresso, dias_conclusao)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || p.n)
WHERE NOT EXISTS (SELECT 1 FROM public.onboarding_processos x WHERE x.id = public.demo_id('onbproc:' || p.n));

-- Andamento do checklist: cada processo marca a fracao de itens compativel com o progresso
INSERT INTO public.onboarding_checklist_progresso (id, tenant_id, processo_id, checklist_item_id, concluido, data_conclusao, observacao)
SELECT public.demo_id('onbprog:' || pr.id::text || ':' || it.id::text), pr.tenant_id, pr.id, it.id,
       (it.rn * 100.0 / it.total) <= pr.progresso,
       CASE WHEN (it.rn * 100.0 / it.total) <= pr.progresso THEN pr.data_inicio + (it.rn || ' days')::interval END,
       NULL
FROM public.onboarding_processos pr
JOIN LATERAL (
  SELECT i.id, row_number() OVER (ORDER BY i.ordem) AS rn, count(*) OVER () AS total
    FROM public.onboarding_checklist_items i
    JOIN public.onboarding_etapas e ON e.id = i.etapa_id
   WHERE e.template_id = pr.template_id AND e.tipo = 'checklist_integracao'
) it ON true
WHERE pr.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND NOT EXISTS (SELECT 1 FROM public.onboarding_checklist_progresso x
                   WHERE x.processo_id = pr.id AND x.checklist_item_id = it.id);

-- Percepcao cultural: respostas de quem concluiu a trilha (cada processo concluido responde 5 perguntas)
INSERT INTO public.onboarding_percepcao_cultural (
  id, tenant_id, processo_id, colaborador_id, colaborador_nome, pergunta_chave, pergunta_texto, resposta, categoria, created_at
)
SELECT public.demo_id('onbperc:' || pr.id::text || ':' || q.chave), pr.tenant_id, pr.id, pr.admissao_id::text, pr.colaborador_nome,
       q.chave, q.texto,
       CASE WHEN q.chave = 'observacao_livre' THEN
              (ARRAY['A integração foi bem organizada e o líder esteve presente.',
                     'Gostei da parte de segurança; poderia ter mais tempo de prática com os EPIs.',
                     'Recepção muito acolhedora. Sugiro um mapa da fábrica no primeiro dia.',
                     'Tudo claro. Quero conhecer melhor os outros setores.'])[1 + (h.v % 4)]
            ELSE (ARRAY['Concordo totalmente','Concordo totalmente','Concordo','Concordo','Neutro'])[1 + ((h.v + q.ordem * 3) % 5)] END,
       q.categoria, pr.data_conclusao
FROM public.onboarding_processos pr
CROSS JOIN (VALUES
  (1, 'clareza_valores',   'Os valores da empresa ficaram claros para mim.', 'cultura'),
  (2, 'acolhimento_equipe', 'Me senti acolhido(a) pela minha equipe.', 'integracao'),
  (3, 'clareza_funcao',    'As responsabilidades da minha função estão claras.', 'integracao'),
  (4, 'orgulho_empresa',   'Sinto orgulho de trabalhar nesta empresa.', 'engajamento'),
  (5, 'orientacao_seguranca', 'Recebi orientação adequada sobre segurança do trabalho.', 'geral'),
  (6, 'observacao_livre',  'Comentário livre sobre a sua integração.', 'geral')
) AS q(ordem, chave, texto, categoria)
CROSS JOIN LATERAL (SELECT get_byte(decode(substr(md5(pr.id::text), 1, 2), 'hex'), 0) AS v) h
WHERE pr.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
  AND pr.status = 'concluido'
  AND NOT EXISTS (SELECT 1 FROM public.onboarding_percepcao_cultural x
                   WHERE x.id = public.demo_id('onbperc:' || pr.id::text || ':' || q.chave));

-- ---------------------------------------------------------------------------
-- (7) Cadastros: filiais (obra com CNO e geolocalizacao), departamentos
--     (filial, gestor e substituto) e cargos (descricao de funcao e SST)
-- ---------------------------------------------------------------------------
INSERT INTO public.filiais (id, tenant_id, empresa_id, nome, cnpj, endereco, cidade, estado, cep, telefone, email, ativo, tipo, cno)
SELECT public.demo_id('filial:3'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'Obra Ampliação Galpão 4', '98.765.432/0001-02', 'Rua das Indústrias, 1000 (fundos)', 'Joinville', 'SC', '89200-000',
       '(47) 3000-3000', 'obra.galpao4@metalurgica-exemplo.demo', true, 'obra', '51.234.56789/72'
WHERE NOT EXISTS (SELECT 1 FROM public.filiais f WHERE f.id = public.demo_id('filial:3'));

UPDATE public.filiais f
   SET tipo = CASE WHEN f.tipo = 'filial' THEN 'estabelecimento' ELSE f.tipo END,
       latitude = COALESCE(f.latitude, v.lat),
       longitude = COALESCE(f.longitude, v.lon),
       raio_geofence_metros = COALESCE(f.raio_geofence_metros, 150),
       geofence_ativo = COALESCE(f.geofence_ativo, true)
  FROM (VALUES
    (public.demo_id('filial:1'), -25.4284::numeric, -49.2733::numeric),
    (public.demo_id('filial:2'), -26.9078::numeric, -48.6619::numeric),
    (public.demo_id('filial:3'), -26.3044::numeric, -48.8487::numeric)
  ) AS v(id, lat, lon)
 WHERE f.id = v.id
   AND f.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND (f.tipo = 'filial' OR f.latitude IS NULL OR f.longitude IS NULL OR f.raio_geofence_metros IS NULL OR f.geofence_ativo IS NULL);

UPDATE public.departamentos d
   SET filial_id = COALESCE(d.filial_id, v.filial_id),
       gestor_admissao_id = COALESCE(d.gestor_admissao_id, v.gestor),
       gestor_substituto_admissao_id = COALESCE(d.gestor_substituto_admissao_id, v.substituto),
       substituto_ativo = CASE WHEN d.nome = 'Logística' THEN true ELSE COALESCE(d.substituto_ativo, false) END
  FROM (VALUES
    ('Produção',         NULL::uuid,               public.demo_id('admissao:28'),  public.demo_id('admissao:29')),
    ('Manutenção',       NULL::uuid,               public.demo_id('admissao:40'),  public.demo_id('admissao:30')),
    ('Logística',        public.demo_id('filial:2'), public.demo_id('admissao:52'),  public.demo_id('admissao:41')),
    ('Administrativo',   NULL::uuid,               public.demo_id('admissao:53'),  public.demo_id('admissao:55')),
    ('Recursos Humanos', NULL::uuid,               public.demo_id('admissao:58'),  public.demo_id('admissao:59')),
    ('Comercial',        public.demo_id('filial:1'), public.demo_id('admissao:715'), public.demo_id('admissao:716'))
  ) AS v(nome, filial_id, gestor, substituto)
 WHERE d.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND d.id = public.demo_id('depto:' || v.nome)
   AND (d.gestor_admissao_id IS NULL OR d.gestor_substituto_admissao_id IS NULL);

UPDATE public.cargos c
   SET requisitos_formacao = v.formacao,
       requisitos_experiencia = v.experiencia,
       interfaces_cargo = v.interfaces,
       padroes_execucao = v.padroes,
       cultura_esperada = v.cultura,
       erros_riscos = v.erros,
       criterios_sucesso = v.criterios,
       ferramentas_cargo = v.ferramentas,
       subordinacao = v.subordinacao,
       aposentadoria_especial = CASE WHEN c.nome = 'Soldador' THEN true ELSE c.aposentadoria_especial END,
       aposentadoria_especial_anos = CASE WHEN c.nome = 'Soldador' THEN 25 ELSE c.aposentadoria_especial_anos END
  FROM (VALUES
    ('Operador de Usinagem CNC', 'Ensino médio completo; curso técnico em mecânica ou usinagem.', '1 a 2 anos operando centros de usinagem ou torno CNC.',
       'Programação, Qualidade e Manutenção.', 'Seguir a folha de processo e as tolerâncias do desenho em todas as peças.',
       'Disciplina com segurança, cuidado com a máquina e melhoria contínua.', 'Peça fora de tolerância, colisão de ferramenta, trabalho sem proteção.',
       'Refugo abaixo da meta, cumprimento do plano de produção e zero incidentes.', 'Centro de usinagem CNC, paquímetro, micrômetro, relógio comparador.', 'Líder de Produção'),
    ('Soldador', 'Ensino fundamental completo; certificação de soldador (qualificação).', '2 anos em soldagem MIG/MAG e eletrodo revestido.',
       'Montagem, Qualidade e Segurança do Trabalho.', 'Soldar conforme o procedimento (EPS/RQPS) e inspecionar o cordão.',
       'Atenção à qualidade e ao uso correto dos EPIs.', 'Porosidade, falta de fusão, exposição a fumos sem proteção respiratória.',
       'Aprovação em inspeção visual e ensaios; baixo retrabalho.', 'Máquina MIG/MAG, esmerilhadeira, gabaritos, EPIs de solda.', 'Líder de Produção'),
    ('Montador de Estruturas Metálicas', 'Ensino fundamental completo.', 'Experiência com leitura de desenho e montagem é desejável.',
       'Soldagem, Logística e Qualidade.', 'Montar estruturas conforme desenho, esquadro e prumo.',
       'Trabalho em equipe e atenção a trabalho em altura.', 'Queda de materiais, montagem fora de esquadro, uso incorreto do cinto de segurança.',
       'Conjuntos montados no prazo e sem retrabalho.', 'Talhas, nível, trena, chaves, ferramentas manuais e pneumáticas.', 'Líder de Produção'),
    ('Líder de Produção', 'Ensino técnico em mecânica ou administração industrial.', '4 anos na área industrial, 1 ano em liderança.',
       'Todos os setores da fábrica, RH e Segurança do Trabalho.', 'Conduzir o turno cumprindo plano, qualidade e segurança.',
       'Liderança pelo exemplo, comunicação clara e escuta da equipe.', 'Não repassar informações de turno, tolerar desvio de segurança.',
       'Meta de produção, absenteísmo baixo e equipe engajada.', 'Sistema de gestão da produção, indicadores, quadro de metas.', 'Gerente Industrial'),
    ('Mecânico de Manutenção', 'Curso técnico em mecânica.', '3 anos em manutenção industrial.',
       'Produção, Compras e Segurança do Trabalho.', 'Executar a manutenção preventiva e corretiva seguindo o plano.',
       'Responsabilidade com bloqueio e etiquetagem (LOTO).', 'Intervir sem bloqueio de energia, não registrar a manutenção.',
       'Disponibilidade das máquinas e baixo tempo de parada.', 'Ferramentas manuais, alinhador a laser, ordens de serviço.', 'Supervisor de Manutenção'),
    ('Eletricista de Manutenção', 'Curso técnico em eletrotécnica; NR-10 em dia.', '3 anos em manutenção elétrica industrial.',
       'Produção, Segurança do Trabalho e fornecedores.', 'Atuar em instalações elétricas conforme NR-10.',
       'Cultura de segurança e rigor técnico.', 'Trabalhar energizado sem autorização, deixar de registrar intervenção.',
       'Zero incidente elétrico e quadros organizados.', 'Multímetro, alicate amperímetro, termovisor, projetos elétricos.', 'Supervisor de Manutenção'),
    ('Supervisor de Manutenção', 'Engenharia ou técnico com experiência em gestão.', '6 anos em manutenção, 2 em supervisão.',
       'Produção, Compras e Diretoria.', 'Planejar a manutenção e gerir a equipe e o orçamento.',
       'Visão de resultado com foco em segurança.', 'Manutenção reativa em excesso, falta de peças críticas.',
       'MTBF/MTTR em meta e orçamento cumprido.', 'Sistema de manutenção (CMMS), indicadores.', 'Gerente Industrial'),
    ('Operador de Empilhadeira', 'Ensino fundamental; curso de operador de empilhadeira (NR-11).', '1 ano operando empilhadeira.',
       'Expedição, Produção e Segurança do Trabalho.', 'Movimentar cargas com segurança conforme as regras internas.',
       'Atenção e respeito à sinalização.', 'Excesso de velocidade, carga mal posicionada, operar sem habilitação.',
       'Zero avarias e movimentação no prazo.', 'Empilhadeira, paleteira, checklist diário.', 'Coordenador de Logística'),
    ('Auxiliar de Logística', 'Ensino médio.', 'Não exige experiência.',
       'Produção, Expedição e fornecedores.', 'Separar, conferir e organizar materiais.',
       'Organização e agilidade.', 'Troca de itens, erro de contagem.',
       'Inventário sem divergências e pedidos no prazo.', 'Coletor de dados, paleteira, sistema de estoque.', 'Coordenador de Logística'),
    ('Coordenador de Logística', 'Superior em Logística ou Administração.', '5 anos em logística, 2 em coordenação.',
       'Compras, Produção, Comercial e transportadoras.', 'Coordenar recebimento, armazenagem e expedição.',
       'Visão de processo e relacionamento com fornecedores.', 'Ruptura de estoque, atraso de entrega.',
       'Nível de serviço e giro de estoque em meta.', 'Sistema de gestão (ERP), indicadores logísticos.', 'Gerente Industrial'),
    ('Analista Financeiro', 'Superior em Ciências Contábeis, Administração ou Economia.', '2 anos em rotinas financeiras.',
       'Compras, Comercial e Contabilidade externa.', 'Conciliar, pagar e projetar o fluxo de caixa.',
       'Precisão e sigilo das informações.', 'Pagamento em duplicidade, conciliação atrasada.',
       'Fluxo de caixa sem divergência e fechamentos no prazo.', 'ERP, planilhas, internet banking.', 'Gerente Administrativo'),
    ('Analista da Qualidade', 'Superior ou técnico em Qualidade.', '2 anos em sistemas de gestão da qualidade.',
       'Produção, Compras e clientes.', 'Manter o sistema da qualidade e tratar não conformidades.',
       'Foco em dados e melhoria contínua.', 'Não conformidade sem tratativa, auditoria sem evidências.',
       'Índice de não conformidades em queda e auditorias aprovadas.', 'Software de qualidade, instrumentos de medição.', 'Gerente Administrativo'),
    ('Comprador', 'Superior ou técnico em Administração.', '2 anos em compras industriais.',
       'Logística, Financeiro e fornecedores.', 'Cotar, negociar e acompanhar pedidos.',
       'Ética nas negociações.', 'Compra fora de especificação, atraso na reposição.',
       'Economia gerada e prazos de entrega cumpridos.', 'ERP, planilhas de cotação.', 'Gerente Administrativo'),
    ('Analista de RH', 'Superior em Psicologia, Administração ou Gestão de RH.', '2 anos em departamento pessoal e recrutamento.',
       'Todos os gestores, sindicato e contabilidade.', 'Conduzir admissões, folha de ponto e relacionamento com colaboradores.',
       'Sigilo, empatia e cumprimento da legislação.', 'Prazo do eSocial vencido, documento incompleto na admissão.',
       'Admissões sem pendência e indicadores de RH atualizados.', 'Sistema YourEyes, eSocial, planilhas.', 'Gerente Administrativo'),
    ('Técnico de Segurança do Trabalho', 'Curso técnico em Segurança do Trabalho (registro no MTE).', '2 anos em indústria metalúrgica.',
       'Produção, Manutenção, RH e medicina do trabalho.', 'Implantar e acompanhar o PGR, o PCMSO e as normas regulamentadoras.',
       'Presença no chão de fábrica e postura educativa.', 'Deixar de investigar incidente, EPI vencido em uso.',
       'Redução de acidentes e de dias perdidos; treinamentos em dia.', 'Sistema YourEyes, luxímetro, decibelímetro, checklists.', 'Gerente Administrativo'),
    ('Vendedor Interno', 'Ensino médio ou superior em andamento.', '1 ano em vendas técnicas (desejável).',
       'Orçamentos, Produção e Logística.', 'Atender clientes, elaborar propostas e acompanhar pedidos.',
       'Clareza com o cliente e cumprimento de prazos.', 'Prometer prazo sem consultar a produção.',
       'Meta de vendas e satisfação do cliente.', 'CRM, planilha de orçamentos, telefone.', 'Gerente Administrativo')
  ) AS v(nome, formacao, experiencia, interfaces, padroes, cultura, erros, criterios, ferramentas, subordinacao)
 WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND c.id = public.demo_id('cargo:' || v.nome)
   AND c.requisitos_formacao IS NULL;

INSERT INTO public.cargo_departamentos (id, tenant_id, cargo_id, departamento_id)
SELECT public.demo_id('cargodep:' || v.cargo || ':' || v.depto), 'd3e00000-0000-4000-8000-000000000001',
       public.demo_id('cargo:' || v.cargo), public.demo_id('depto:' || v.depto)
FROM (VALUES
  ('Operador de Usinagem CNC', 'Produção'), ('Soldador', 'Produção'), ('Montador de Estruturas Metálicas', 'Produção'),
  ('Líder de Produção', 'Produção'), ('Mecânico de Manutenção', 'Manutenção'), ('Eletricista de Manutenção', 'Manutenção'),
  ('Supervisor de Manutenção', 'Manutenção'), ('Operador de Empilhadeira', 'Logística'), ('Operador de Empilhadeira', 'Produção'),
  ('Auxiliar de Logística', 'Logística'), ('Coordenador de Logística', 'Logística'), ('Analista Financeiro', 'Administrativo'),
  ('Analista da Qualidade', 'Administrativo'), ('Analista da Qualidade', 'Produção'), ('Comprador', 'Administrativo'),
  ('Comprador', 'Logística'), ('Analista de RH', 'Recursos Humanos'), ('Técnico de Segurança do Trabalho', 'Recursos Humanos'),
  ('Técnico de Segurança do Trabalho', 'Produção'), ('Técnico de Segurança do Trabalho', 'Manutenção'), ('Vendedor Interno', 'Comercial')
) AS v(cargo, depto)
WHERE NOT EXISTS (SELECT 1 FROM public.cargo_departamentos x
                   WHERE x.cargo_id = public.demo_id('cargo:' || v.cargo) AND x.departamento_id = public.demo_id('depto:' || v.depto));

-- ---------------------------------------------------------------------------
-- (8) Cadastro da empresa demo: todas as abas (UPDATE somente da empresa demo)
--     Os numeros de cota PCD e aprendiz sao recalculados pelos gatilhos do
--     proprio sistema a partir das admissoes.
-- ---------------------------------------------------------------------------
UPDATE public.empresa_cadastro e
   SET inscricao_estadual = '255.123.456',
       inscricao_municipal = '11223344',
       complemento = 'Galpões 1 a 3',
       cnaes_secundarios = '[{"codigo":"2511-0/00","descricao":"Fabricação de estruturas metálicas"},{"codigo":"2539-0/01","descricao":"Serviços de usinagem, tornearia e solda"},{"codigo":"3329-5/99","descricao":"Instalação de outros equipamentos não especificados anteriormente"}]'::jsonb,
       grau_risco = 3,
       grau_risco_ajustado = NULL,
       grau_risco_justificativa = NULL,
       sesmt_obrigatorio = true,
       sesmt_situacao = 'proprio',
       sesmt_profissionais = '[{"tipo":"Engenheiro de Segurança do Trabalho","nome":"Marcos Aurélio Tavares","registro":"CREA-SC 000000-DEMO"},{"tipo":"Técnico de Segurança do Trabalho","nome":"Rogério Antunes Pimentel","registro":"MTE 00000-DEMO"},{"tipo":"Médico do Trabalho","nome":"Dra. Helena Prado Marques","registro":"CRM/SC 00000-DEMO"},{"tipo":"Enfermeira do Trabalho","nome":"Simone Aparecida Brito","registro":"COREN-SC 000000-DEMO"}]'::jsonb,
       cipa_obrigatoria = true,
       cipa_situacao = 'ativa',
       cipa_data_mandato_inicio = CURRENT_DATE - 215,
       cipa_data_mandato_fim = CURRENT_DATE + 150,
       cipa_membros = '[{"nome":"Eduardo Prado Leme","funcao":"Presidente (indicado pelo empregador)","tipo":"titular"},{"nome":"Larissa Nogueira Paes","funcao":"Vice-presidente (eleita pelos empregados)","tipo":"titular"},{"nome":"Diego Rezende Matos","funcao":"Titular (eleito)","tipo":"titular"},{"nome":"Patrícia Queiroz Bastos","funcao":"Titular (indicada)","tipo":"titular"},{"nome":"Paulo Leal Fontes","funcao":"Suplente (eleito)","tipo":"suplente"},{"nome":"Aline Sampaio Valente","funcao":"Suplente (indicada)","tipo":"suplente"}]'::jsonb,
       pcd_obrigatoria = true,
       pcd_percentual_exigido = 2,
       aprendiz_obrigatorio = true,
       fap_atual = 0.8934,
       fap_classificacao = 'Bônus',
       fap_historico = '[{"ano":2023,"valor":1.0412},{"ano":2024,"valor":0.965},{"ano":2025,"valor":0.8934}]'::jsonb,
       tac_possui = true,
       tac_detalhes = '[{"numero":"TAC nº 0000/2025 (fictício)","orgao_emissor":"Ministério Público do Trabalho (demonstração)","data_assinatura":"2025-03-10","obrigacoes":"Manter proteção de máquinas conforme NR-12 e laudos atualizados; treinar 100% dos operadores.","prazo":"2026-12-31","penalidades":"Multa diária prevista no termo (valor fictício).","status":"Em cumprimento"},{"numero":"TAC nº 0000/2022 (fictício)","orgao_emissor":"Ministério Público do Trabalho (demonstração)","data_assinatura":"2022-06-20","obrigacoes":"Adequar o refeitório e o ambiente de descanso.","prazo":"2023-06-30","penalidades":"Multa prevista no termo (valor fictício).","status":"Arquivado","arquivado":true,"arquivado_em":"2023-07-05T12:00:00Z","motivo_arquivamento":"Obrigações cumpridas e validadas pelo órgão."}]'::jsonb,
       jornada_padrao = '44h semanais',
       turnos = '[{"nome":"1º turno","horario_inicio":"06:00","horario_fim":"14:20"},{"nome":"2º turno","horario_inicio":"14:00","horario_fim":"22:20"},{"nome":"Administrativo","horario_inicio":"08:00","horario_fim":"17:48"}]'::jsonb,
       possui_terceiro_turno = false,
       possui_escalas_especiais = true,
       trabalho_altura = true,
       espaco_confinado = false,
       insalubridade = true,
       periculosidade = true,
       aposentadoria_especial = true,
       condicoes_especiais_detalhes = '{"trabalho_altura":"Montagem de estruturas metálicas acima de 2 m, com cinto tipo paraquedista, linha de vida e treinamento de NR-35 em dia.","insalubridade":"Ruído contínuo acima de 85 dB(A) na usinagem e fumos metálicos na solda; laudo (LTCAT) revisado anualmente.","periculosidade":"Eletricistas de manutenção expostos a instalações elétricas energizadas (NR-10).","aposentadoria_especial":"Soldadores: agentes nocivos registrados no PPP e no LTCAT."}'::jsonb,
       total_colaboradores = (SELECT count(*) FROM public.admissoes a
                               WHERE a.empresa_id = e.id AND a.status = 'concluido'),
       latitude = -26.3044, longitude = -48.8487, raio_geofence_metros = 150, geofence_ativo = true,
       atualizado_por = 'Equipe de demonstração'
 WHERE e.id = 'd3e00000-0000-4000-8000-000000000002'
   AND e.tenant_id = 'd3e00000-0000-4000-8000-000000000001';

-- Obrigacoes de conformidade: o sistema ja gera as de cadastro (grau de risco, TAC...).
-- Aqui acrescentamos as de condicoes especiais e variamos a situacao para a tela ficar completa.
INSERT INTO public.empresa_obrigacoes (
  id, tenant_id, empresa_id, categoria, subcategoria, titulo, descricao, base_legal, status, criticidade,
  prazo_sugerido, responsavel_sugerido, origem, origem_campo, ativo
)
SELECT public.demo_id('empobr:' || o.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       o.categoria, o.subcategoria, o.titulo, o.descricao, o.base_legal, o.status, o.criticidade,
       CURRENT_DATE + o.prazo, o.responsavel, 'cadastro_empresa', o.campo, true
FROM (VALUES
  ('altura',  'sst',   'condicoes_especiais', 'Implantar treinamento de trabalho em altura', 'Atividades em altura requerem treinamento obrigatório (NR-35).', 'NR-35', 'conforme', 'alta', -20, 'Técnico de Segurança do Trabalho', 'trabalho_altura'),
  ('insal',   'legal', 'condicoes_especiais', 'Revisar laudos de insalubridade', 'Condições de insalubridade requerem laudos técnicos atualizados.', 'NR-15', 'em_adequacao', 'media', 45, 'Engenheiro de Segurança do Trabalho', 'insalubridade'),
  ('peric',   'legal', 'condicoes_especiais', 'Revisar laudos de periculosidade', 'Condições de periculosidade requerem laudos técnicos atualizados.', 'NR-16', 'pendente', 'media', 60, 'Engenheiro de Segurança do Trabalho', 'periculosidade'),
  ('cipa',    'sst',   'cipa', 'Renovar mandato da CIPA', 'O mandato da CIPA vence nos próximos meses: iniciar o processo eleitoral.', 'NR-05', 'pendente', 'alta', 90, 'Técnico de Segurança do Trabalho', 'cipa_data_mandato_fim')
) AS o(chave, categoria, subcategoria, titulo, descricao, base_legal, status, criticidade, prazo, responsavel, campo)
WHERE NOT EXISTS (SELECT 1 FROM public.empresa_obrigacoes x WHERE x.id = public.demo_id('empobr:' || o.chave));

UPDATE public.empresa_obrigacoes o
   SET status = CASE o.subcategoria WHEN 'tac' THEN 'em_adequacao' WHEN 'grau_risco' THEN 'conforme' ELSE o.status END,
       responsavel_sugerido = COALESCE(o.responsavel_sugerido, 'Técnico de Segurança do Trabalho'),
       prazo_sugerido = COALESCE(o.prazo_sugerido, CURRENT_DATE + 30)
 WHERE o.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND o.empresa_id = 'd3e00000-0000-4000-8000-000000000002'
   AND o.origem = 'cadastro_empresa'
   AND o.subcategoria IN ('tac', 'grau_risco')
   AND o.status = 'pendente';

-- ---------------------------------------------------------------------------
-- Conferencia final (parte 02a)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.admissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pessoas_total,
  (SELECT count(*) FROM public.admissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND status NOT IN ('concluido', 'desligado')) AS funil_admissao,
  (SELECT count(*) FROM public.admissao_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS documentos,
  (SELECT count(*) FROM public.admissao_workflow WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS etapas_aprovacao,
  (SELECT count(*) FROM public.contratos_experiencia WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS contratos_experiencia,
  (SELECT count(*) FROM public.onboarding_templates WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS modelos_onboarding,
  (SELECT count(*) FROM public.onboarding_processos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS processos_onboarding,
  (SELECT count(*) FROM public.filiais WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS filiais,
  (SELECT count(*) FROM public.departamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND gestor_admissao_id IS NOT NULL) AS deptos_com_gestor,
  (SELECT count(*) FROM public.empresa_obrigacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS obrigacoes_empresa,
  CASE WHEN (SELECT count(*) FROM public.admissoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 91
        AND (SELECT count(*) FROM public.contratos_experiencia WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 14
        AND (SELECT count(*) FROM public.onboarding_processos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 20
        AND (SELECT sesmt_situacao FROM public.empresa_cadastro WHERE id = 'd3e00000-0000-4000-8000-000000000002') = 'proprio'
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
