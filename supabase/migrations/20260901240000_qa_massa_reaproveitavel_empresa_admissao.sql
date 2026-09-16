-- =====================================================================
-- QA — a massa de teste passa a ser REAPROVEITADA, não recriada
--
-- MOTIVO: as duas ferramentas de massa mais usadas pelas sondas do Ponto
-- (qa_nova_empresa e qa_ponto_admissao) sempre INSERIAM. Enquanto tudo
-- corre bem isso não aparece, porque a sonda roda uma vez por bateria.
-- Aparece quando uma sonda é interrompida no meio — por exemplo num
-- ambiente onde a peça que ela exercita ainda não chegou: fica a empresa
-- criada e o resto não. Na execução seguinte, a segunda tentativa de
-- criar a MESMA empresa/admissão bate nas travas do próprio sistema:
--
--   "Já existe outra empresa ATIVA com o CNPJ ... neste tenant"
--   duplicate key value violates unique constraint "uq_admissoes_cpf_ativa"
--
-- e a sonda passa a devolver ERRO para sempre, num ambiente que talvez já
-- esteja correto. O relatório mostra "a rotina quebrou" e o achado
-- verdadeiro some. Foi o que se viu ao simular a homologação em réplica:
-- seis casos do feriado/apuração travados por massa pela metade.
--
-- CORREÇÃO: procurar antes de criar. Se a empresa (mesmo CNPJ) ou a
-- admissão (mesmo CPF) já existe no cercado de testes, ela é reaproveitada
-- e ajustada para o estado que a sonda pediu. Nada muda para quem roda a
-- bateria num ambiente limpo: a primeira execução cria igual.
--
-- NADA DE REGRA DE NEGÓCIO MUDA. Só a bancada que a verifica — e as travas
-- do sistema continuam valendo, inclusive para ela.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.qa_nova_empresa(
  p_razao text, p_cnpj text, p_ativo boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
  v_t  uuid := public.qa_sandbox_tenant_id();
  v_id uuid;
BEGIN
  -- Reaproveita a empresa do cercado com o mesmo CNPJ, se ela ja existe.
  SELECT e.id INTO v_id
  FROM public.empresa_cadastro e
  WHERE e.tenant_id = v_t AND e.cnpj = p_cnpj
  ORDER BY (e.ativo IS TRUE) DESC, e.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.empresa_cadastro
       SET razao_social = p_razao, nome_fantasia = p_razao, ativo = p_ativo
     WHERE id = v_id;
    RETURN v_id;
  END IF;

  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (v_t, p_razao, p_razao, p_cnpj, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.qa_ponto_admissao(
  p_nome text, p_cpf_semente integer, p_empresa_id uuid DEFAULT NULL::uuid,
  p_data_admissao date DEFAULT (CURRENT_DATE - 60))
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
  v_t   uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(p_cpf_semente);
  v_id  uuid;
BEGIN
  -- Reaproveita a admissao do cercado com o mesmo CPF, se ela ja existe.
  SELECT a.id INTO v_id
  FROM public.admissoes a
  WHERE a.tenant_id = v_t AND a.cpf = v_cpf
  ORDER BY (a.status = 'concluido') DESC, a.created_at NULLS LAST
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.admissoes
       SET nome_completo = p_nome,
           status        = 'concluido',
           data_admissao = p_data_admissao,
           empresa_id    = COALESCE(p_empresa_id, empresa_id)
     WHERE id = v_id;
    RETURN v_cpf;
  END IF;

  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao, empresa_id)
  VALUES (v_t, p_nome, v_cpf,
          public.qa_fixture_email('PONTO-AGO', p_cpf_semente),
          'Operador', 'concluido', p_data_admissao, p_empresa_id);
  RETURN v_cpf;
END $function$;

DO $fim$
BEGIN
  RAISE NOTICE 'Massa de teste reaproveitavel: qa_nova_empresa e qa_ponto_admissao procuram antes de criar.';
END $fim$;
