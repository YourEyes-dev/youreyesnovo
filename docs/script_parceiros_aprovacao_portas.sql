-- =====================================================================
-- SCRIPT DE ENTREGA · PROGRAMA DE PARCEIROS · APROVAÇÃO EM DUAS TRAVAS,
-- FAIXA DE INDICAÇÃO NO SITE, PORTA LIVRE DE CADASTRO FECHADA E ENDEREÇO
-- DO PARCEIRO NA ASSINATURA
--
-- Cole no SQL Editor do projeto. Roda em UMA transação; pode ser executado
-- mais de uma vez. Cria/substitui funções, adiciona parceiros.endereco,
-- documenta o caso de QA PGP-017 e semeia as chaves 'cadastro_empresa_livre'
-- ('nao') e 'cadastro_empresa_trial_dias' ('0') SEM sobrescrever valor que
-- já exista. Não altera parceiro, contrato nem assinatura existente.
--
-- Pré-requisito: script_parceiros_contrato_assinatura.sql já aplicado.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Contrato só depois da aprovação
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_contrato_iniciar_assinatura_para(p_parceiro_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_iniciar_assinatura_para$
DECLARE v_p public.parceiros%ROWTYPE; v_v public.parceiro_contratos_versoes%ROWTYPE; v_modelo uuid; v_a public.contratos_assinaturas%ROWTYPE; v_html text;
BEGIN
  SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Parceiro não encontrado'; END IF;
  -- Trava 1: a casa precisa aprovar antes de existir contrato para assinar
  IF v_p.status = 'pendente' THEN
    RETURN jsonb_build_object('ok', false, 'aguardando_aprovacao', true, 'status', v_p.status);
  END IF;
  IF v_p.status IN ('suspenso','encerrado') THEN
    RETURN jsonb_build_object('ok', false, 'bloqueado', true, 'status', v_p.status, 'motivo', v_p.motivo_recusa);
  END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RAISE EXCEPTION 'Nenhuma versão vigente do contrato'; END IF;
  v_modelo := public.parceiro_contrato_modelo_vigente();

  IF EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites WHERE parceiro_id = v_p.id AND versao = v_v.versao) THEN
    SELECT * INTO v_a FROM public.contratos_assinaturas WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'assinado' ORDER BY assinado_em DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', true, 'versao', v_v.versao, 'assinatura_id', v_a.id, 'assinado_em', v_a.assinado_em);
  END IF;

  SELECT * INTO v_a FROM public.contratos_assinaturas
  WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente' AND (expira_em IS NULL OR expira_em > now())
  ORDER BY created_at DESC LIMIT 1;
  v_html := public.parceiro_contrato_render_abnt(v_p.id, v_v.html);
  IF v_a.id IS NOT NULL THEN
    UPDATE public.contratos_assinaturas SET html_assinado = v_html,
      signatario_nome = coalesce(signatario_nome, v_p.nome), signatario_email = coalesce(signatario_email, v_p.email)
    WHERE id = v_a.id;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
  END IF;

  UPDATE public.contratos_assinaturas SET status = 'expirado' WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente';
  INSERT INTO public.contratos_assinaturas (contrato_id, parceiro_id, signatario_nome, signatario_email, signatario_telefone,
    signatario_cpf, signatario_cnpj, signatario_razao_social, html_assinado, link_enviado_para, expira_em, status, observacoes)
  VALUES (v_modelo, v_p.id, v_p.nome, v_p.email, v_p.telefone,
    CASE WHEN v_p.tipo_pessoa = 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.nome END,
    v_html, v_p.email, now() + interval '30 days', 'pendente',
    'Contrato de Parceria gerado para o parceiro ' || v_p.codigo || ' · trilha ' || coalesce(v_p.trilha, '—') || ' · versão ' || v_v.versao || ' · aguardando assinatura eletrônica')
  RETURNING * INTO v_a;
  RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
END $parceiro_contrato_iniciar_assinatura_para$;
REVOKE ALL ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) TO service_role;

-- Aprovar gera o contrato pendente na hora; recusar/suspender guarda o motivo
CREATE OR REPLACE FUNCTION public.superadmin_parceiro_status(_parceiro_id uuid, _status text, _motivo text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_status$
DECLARE v_antes text;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF _status NOT IN ('pendente','ativo','suspenso','encerrado') THEN RAISE EXCEPTION 'Status inválido: %', _status; END IF;
  SELECT status INTO v_antes FROM public.parceiros WHERE id = _parceiro_id;
  UPDATE public.parceiros SET
    status = _status,
    aprovado_em = CASE WHEN _status = 'ativo' THEN coalesce(aprovado_em, now()) ELSE aprovado_em END,
    aprovado_por = CASE WHEN _status = 'ativo' THEN coalesce(aprovado_por, auth.uid()) ELSE aprovado_por END,
    motivo_recusa = CASE WHEN _status IN ('suspenso','encerrado') THEN _motivo ELSE NULL END
  WHERE id = _parceiro_id;
  -- Trava 2 abre: aprovado → contrato pendente pronto para assinar
  IF _status = 'ativo' AND coalesce(v_antes, '') <> 'ativo' THEN
    BEGIN
      PERFORM public.parceiro_contrato_iniciar_assinatura_para(_parceiro_id);
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'contrato pós-aprovação: %', SQLERRM;
    END;
  END IF;
END $superadmin_parceiro_status$;

-- Situação contratual informa se ainda falta a aprovação da casa
CREATE OR REPLACE FUNCTION public.parceiro_contrato_situacao(p_parceiro_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $parceiro_contrato_situacao$
  SELECT jsonb_build_object(
    'versao_vigente', (SELECT versao FROM public.parceiro_contratos_versoes WHERE vigente),
    'titulo_vigente', (SELECT titulo FROM public.parceiro_contratos_versoes WHERE vigente),
    'versao_aceita', (SELECT max(versao) FROM public.parceiro_contratos_aceites WHERE parceiro_id = p_parceiro_id),
    'aceito_em', (SELECT max(aceito_em) FROM public.parceiro_contratos_aceites WHERE parceiro_id = p_parceiro_id),
    'pendente', NOT EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites a
                            JOIN public.parceiro_contratos_versoes v ON v.versao = a.versao AND v.vigente
                            WHERE a.parceiro_id = p_parceiro_id),
    'aguardando_aprovacao', (SELECT p.status = 'pendente' FROM public.parceiros p WHERE p.id = p_parceiro_id),
    'assinatura_token', (SELECT s.token FROM public.contratos_assinaturas s
                         JOIN public.contratos_aceite c ON c.id = s.contrato_id AND c.categoria = 'parceria'
                         JOIN public.parceiro_contratos_versoes v ON v.versao = c.versao AND v.vigente
                         WHERE s.parceiro_id = p_parceiro_id AND s.status = 'pendente' AND (s.expira_em IS NULL OR s.expira_em > now())
                         ORDER BY s.created_at DESC LIMIT 1),
    'assinatura_id', (SELECT s.id FROM public.contratos_assinaturas s
                      JOIN public.contratos_aceite c ON c.id = s.contrato_id AND c.categoria = 'parceria'
                      JOIN public.parceiro_contratos_versoes v ON v.versao = c.versao AND v.vigente
                      WHERE s.parceiro_id = p_parceiro_id AND s.status = 'assinado'
                      ORDER BY s.assinado_em DESC LIMIT 1))
$parceiro_contrato_situacao$;

-- Portal: além do contrato, devolve a situação do cadastro (motivo, datas)
CREATE OR REPLACE FUNCTION public.parceiro_meu_portal_com_contrato()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_portal_com_contrato$
  SELECT CASE WHEN public.parceiro_meu_id() IS NULL THEN NULL
         ELSE public.parceiro_meu_portal()
              || jsonb_build_object('contrato', public.parceiro_contrato_situacao(public.parceiro_meu_id()))
              || jsonb_build_object('situacao', (SELECT jsonb_build_object('status', p.status, 'motivo', p.motivo_recusa,
                                                        'aprovado_em', p.aprovado_em, 'criado_em', p.created_at, 'trilha', p.trilha)
                                                 FROM public.parceiros p WHERE p.id = public.parceiro_meu_id()))
         END
$parceiro_meu_portal_com_contrato$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_portal_com_contrato() TO authenticated;

-- ---------------------------------------------------------------------
-- 2) Faixa de indicação no site: quem indicou (dado público mínimo)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_ref_publico(p_codigo text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_ref_publico$
  SELECT jsonb_build_object('nome', p.nome, 'cidade', p.cidade, 'uf', p.uf, 'trilha', p.trilha, 'codigo', k.codigo)
  FROM public.parceiro_links k JOIN public.parceiros p ON p.id = k.parceiro_id
  WHERE k.ativo AND p.status = 'ativo'
    AND upper(k.codigo) = upper(regexp_replace(coalesce(p_codigo,''), '[^A-Za-z0-9-]', '', 'g'))
  LIMIT 1
$parceiro_ref_publico$;
GRANT EXECUTE ON FUNCTION public.parceiro_ref_publico(text) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) Porta livre de cadastro de empresa: fechada por padrão, com chave
-- ---------------------------------------------------------------------
INSERT INTO public.app_config (chave, valor) VALUES
  ('cadastro_empresa_livre', 'nao'),
  ('cadastro_empresa_trial_dias', '0')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.cadastro_empresa_livre_ativo()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $cadastro_empresa_livre_ativo$
  SELECT coalesce((SELECT lower(btrim(valor)) IN ('sim','true','1') FROM public.app_config WHERE chave = 'cadastro_empresa_livre'), false)
$cadastro_empresa_livre_ativo$;
GRANT EXECUTE ON FUNCTION public.cadastro_empresa_livre_ativo() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.portas_entrada_config()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $portas_entrada_config$
  SELECT jsonb_build_object(
    'cadastro_empresa_livre', public.cadastro_empresa_livre_ativo(),
    'cadastro_empresa_trial_dias', coalesce((SELECT nullif(btrim(valor),'')::int FROM public.app_config WHERE chave = 'cadastro_empresa_trial_dias'), 0))
$portas_entrada_config$;
GRANT EXECUTE ON FUNCTION public.portas_entrada_config() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.superadmin_portas_entrada_salvar(_dados jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_portas_entrada_salvar$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF _dados ? 'cadastro_empresa_livre' THEN
    INSERT INTO public.app_config (chave, valor) VALUES ('cadastro_empresa_livre', CASE WHEN (_dados->>'cadastro_empresa_livre')::boolean THEN 'sim' ELSE 'nao' END)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
  END IF;
  IF _dados ? 'cadastro_empresa_trial_dias' THEN
    INSERT INTO public.app_config (chave, valor) VALUES ('cadastro_empresa_trial_dias', greatest(0, coalesce((_dados->>'cadastro_empresa_trial_dias')::int, 0))::text)
    ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
  END IF;
END $superadmin_portas_entrada_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_portas_entrada_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 4) QA — PGP-017 (api): pendente não gera contrato; aprovação gera
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros/programa-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PGP-017', 'Aprovação em duas travas: parceiro pendente não recebe contrato; a aprovação gera o contrato para assinar',
   'feliz', 'alta', 'aprovado', 'api',
   'Política de Parceiros (Representante e Operador dependem de aprovação); Código Civil, art. 107',
   'Representante e Operador só assinam o contrato depois que a YourEyes aprova o cadastro. Enquanto pendente, nada é gerado e o link não atribui. Ao aprovar, o contrato pendente nasce na hora.',
   'Versão vigente do contrato publicada.',
   '[{"ordem":1,"acao":"Criar parceiro representante (nasce pendente) e tentar iniciar a assinatura","resultado_esperado":"Resposta aguardando_aprovacao; nenhuma assinatura criada; situação contratual com aguardando_aprovacao = true; link não resolve"},
     {"ordem":2,"acao":"Aprovar o parceiro (status ativo)","resultado_esperado":"Contrato pendente criado com token; aguardando_aprovacao = false; link passa a resolver"}]'::jsonb,
   'Nada antes da aprovação; contrato pronto logo depois dela.',
   'A rotina cria e apaga o parceiro QA-PGP-APR e a assinatura gerada.')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes;
END $qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_017()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_p uuid; v_ini jsonb; v_sit jsonb; v_n int; v_ref record; v_a uuid;
BEGIN
  DELETE FROM public.parceiros WHERE codigo = 'QA-PGP-APR';
  IF NOT EXISTS (SELECT 1 FROM public.parceiro_contratos_versoes WHERE vigente) THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: nenhuma versão vigente do contrato'; RETURN r;
  END IF;
  INSERT INTO public.parceiros (codigo, nome, tipo_pessoa, email, tipo_parceiro, trilha)
  VALUES ('QA-PGP-APR', 'QA Aprovação', 'pj', 'qa-apr@exemplo.test', 'representante', 'representante') RETURNING id INTO v_p;

  r.passo_ordem := 1; r.passo_acao := 'Parceiro representante pendente tenta iniciar assinatura';
  r.esperado := 'aguardando_aprovacao, sem assinatura criada, link não resolve';
  v_ini := public.parceiro_contrato_iniciar_assinatura_para(v_p);
  SELECT count(*) INTO v_n FROM public.contratos_assinaturas WHERE parceiro_id = v_p;
  v_sit := public.parceiro_contrato_situacao(v_p);
  SELECT * INTO v_ref FROM public.parceiro_resolver_ref('QA-PGP-APR');
  IF (SELECT status FROM public.parceiros WHERE id = v_p) <> 'pendente' OR (v_ini->>'aguardando_aprovacao')::boolean IS NOT TRUE
     OR v_n <> 0 OR (v_sit->>'aguardando_aprovacao')::boolean IS NOT TRUE OR v_ref.parceiro_id IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: status=%s, resposta=%s, assinaturas=%s, situacao=%s, link_resolve=%s',
      (SELECT status FROM public.parceiros WHERE id = v_p), v_ini::text, v_n, v_sit->>'aguardando_aprovacao', v_ref.parceiro_id IS NOT NULL);
    DELETE FROM public.parceiros WHERE id = v_p; RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Aprovar o parceiro';
  r.esperado := 'Contrato pendente com token; aguardando_aprovacao false; link resolve';
  UPDATE public.parceiros SET status = 'ativo', aprovado_em = now() WHERE id = v_p;   -- mesmo efeito da aprovação do SuperAdmin
  v_ini := public.parceiro_contrato_iniciar_assinatura_para(v_p);
  SELECT id INTO v_a FROM public.contratos_assinaturas WHERE parceiro_id = v_p AND status = 'pendente' LIMIT 1;
  v_sit := public.parceiro_contrato_situacao(v_p);
  SELECT * INTO v_ref FROM public.parceiro_resolver_ref('QA-PGP-APR');
  IF (v_ini->>'ok')::boolean AND v_ini->>'token' IS NOT NULL AND v_a IS NOT NULL
     AND (v_sit->>'aguardando_aprovacao')::boolean IS FALSE AND v_sit->>'assinatura_token' = v_ini->>'token' AND v_ref.parceiro_id = v_p THEN
    r.situacao := 'passou'; r.obtido := 'Pendente sem contrato e sem link; aprovado gera o contrato para assinar e o link passa a valer.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: resposta=%s, assinatura=%s, situacao=%s, link_resolve=%s', v_ini::text, v_a, v_sit::text, v_ref.parceiro_id = v_p);
  END IF;
  DELETE FROM public.parceiros WHERE id = v_p;
  DELETE FROM public.contratos_assinaturas WHERE id = v_a;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('PGP-017', 'qa_caso_pgp_017')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ===================== parte 2: endereço na assinatura =====================
ALTER TABLE public.parceiros ADD COLUMN IF NOT EXISTS endereco text;

-- Endereço de uma linha, para o contrato e para a assinatura
CREATE OR REPLACE FUNCTION public.parceiro_endereco_linha(p public.parceiros)
RETURNS text LANGUAGE sql IMMUTABLE
AS $parceiro_endereco_linha$
  SELECT nullif(concat_ws(', ', nullif(btrim(p.endereco), ''), nullif(concat_ws('/', p.cidade, p.uf), ''),
                          CASE WHEN p.cep IS NOT NULL AND btrim(p.cep) <> '' THEN 'CEP ' || p.cep END), '')
$parceiro_endereco_linha$;

-- Perfil e cadastro aceitam o endereço
CREATE OR REPLACE FUNCTION public.parceiro_meu_perfil_salvar(_dados jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_perfil_salvar$
DECLARE v_pid uuid := public.parceiro_meu_id();
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  UPDATE public.parceiros SET
    telefone = coalesce(nullif(_dados->>'telefone',''), telefone),
    email = coalesce(nullif(_dados->>'email',''), email),
    cidade = coalesce(nullif(_dados->>'cidade',''), cidade),
    uf = coalesce(nullif(upper(_dados->>'uf'),''), uf),
    cep = coalesce(nullif(_dados->>'cep',''), cep),
    endereco = CASE WHEN _dados ? 'endereco' THEN nullif(btrim(_dados->>'endereco'),'') ELSE endereco END,
    raio_atuacao_km = coalesce((_dados->>'raio_atuacao_km')::int, raio_atuacao_km),
    pix_chave = CASE WHEN _dados ? 'pix_chave' THEN nullif(_dados->>'pix_chave','') ELSE pix_chave END
  WHERE id = v_pid;
END $parceiro_meu_perfil_salvar$;

CREATE OR REPLACE FUNCTION public.parceiro_cadastrar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_cadastrar$
DECLARE v_id uuid; v_uid uuid := auth.uid(); v_mp uuid; v_email text; v_contrato jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'É preciso estar autenticado'; END IF;
  IF public.parceiro_meu_id() IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'ja_existia', true, 'parceiro_id', public.parceiro_meu_id());
  END IF;
  IF coalesce(btrim(_dados->>'nome'),'') = '' THEN RAISE EXCEPTION 'Informe o nome'; END IF;
  IF coalesce((_dados->>'aceite_termos')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'É preciso aceitar o Contrato de Parceria'; END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  SELECT id INTO v_mp FROM public.marketplace_profissionais WHERE user_id = v_uid LIMIT 1;

  INSERT INTO public.parceiros
    (nome, tipo_pessoa, documento, tipo_parceiro, trilha, email, telefone, cidade, uf, cep, endereco,
     raio_atuacao_km, aceite_termos_em, marketplace_profissional_id, created_by)
  VALUES
    (_dados->>'nome', coalesce(_dados->>'tipo_pessoa','pj'), nullif(_dados->>'documento',''),
     coalesce(_dados->>'tipo_parceiro','indicador'),
     CASE WHEN _dados->>'trilha' IN ('indicador','representante','operador') THEN _dados->>'trilha' END,
     coalesce(nullif(_dados->>'email',''), v_email),
     nullif(_dados->>'telefone',''), nullif(_dados->>'cidade',''), nullif(upper(_dados->>'uf'),''),
     nullif(_dados->>'cep',''), nullif(btrim(_dados->>'endereco'),''),
     coalesce((_dados->>'raio_atuacao_km')::int, 50), now(), v_mp, v_uid)
  RETURNING id INTO v_id;

  INSERT INTO public.parceiro_usuarios (parceiro_id, user_id, papel) VALUES (v_id, v_uid, 'dono');
  BEGIN
    v_contrato := public.parceiro_contrato_iniciar_assinatura_para(v_id);
  EXCEPTION WHEN OTHERS THEN v_contrato := jsonb_build_object('erro', SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'parceiro_id', v_id,
    'status', (SELECT status FROM public.parceiros WHERE id = v_id),
    'codigo', (SELECT codigo FROM public.parceiros WHERE id = v_id),
    'contrato', v_contrato);
END $parceiro_cadastrar$;

-- Assinatura pendente nasce com o endereço conhecido
CREATE OR REPLACE FUNCTION public.parceiro_contrato_iniciar_assinatura_para(p_parceiro_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_iniciar_assinatura_para$
DECLARE v_p public.parceiros%ROWTYPE; v_v public.parceiro_contratos_versoes%ROWTYPE; v_modelo uuid; v_a public.contratos_assinaturas%ROWTYPE; v_html text;
BEGIN
  SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Parceiro não encontrado'; END IF;
  IF v_p.status = 'pendente' THEN
    RETURN jsonb_build_object('ok', false, 'aguardando_aprovacao', true, 'status', v_p.status);
  END IF;
  IF v_p.status IN ('suspenso','encerrado') THEN
    RETURN jsonb_build_object('ok', false, 'bloqueado', true, 'status', v_p.status, 'motivo', v_p.motivo_recusa);
  END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RAISE EXCEPTION 'Nenhuma versão vigente do contrato'; END IF;
  v_modelo := public.parceiro_contrato_modelo_vigente();

  IF EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites WHERE parceiro_id = v_p.id AND versao = v_v.versao) THEN
    SELECT * INTO v_a FROM public.contratos_assinaturas WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'assinado' ORDER BY assinado_em DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', true, 'versao', v_v.versao, 'assinatura_id', v_a.id, 'assinado_em', v_a.assinado_em);
  END IF;

  SELECT * INTO v_a FROM public.contratos_assinaturas
  WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente' AND (expira_em IS NULL OR expira_em > now())
  ORDER BY created_at DESC LIMIT 1;
  v_html := public.parceiro_contrato_render_abnt(v_p.id, v_v.html);
  IF v_a.id IS NOT NULL THEN
    UPDATE public.contratos_assinaturas SET html_assinado = v_html,
      signatario_nome = coalesce(signatario_nome, v_p.nome), signatario_email = coalesce(signatario_email, v_p.email),
      signatario_telefone = coalesce(signatario_telefone, v_p.telefone),
      signatario_endereco = coalesce(signatario_endereco, public.parceiro_endereco_linha(v_p))
    WHERE id = v_a.id;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
  END IF;

  UPDATE public.contratos_assinaturas SET status = 'expirado' WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente';
  INSERT INTO public.contratos_assinaturas (contrato_id, parceiro_id, signatario_nome, signatario_email, signatario_telefone, signatario_endereco,
    signatario_cpf, signatario_cnpj, signatario_razao_social, html_assinado, link_enviado_para, expira_em, status, observacoes)
  VALUES (v_modelo, v_p.id, v_p.nome, v_p.email, v_p.telefone, public.parceiro_endereco_linha(v_p),
    CASE WHEN v_p.tipo_pessoa = 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.nome END,
    v_html, v_p.email, now() + interval '30 days', 'pendente',
    'Contrato de Parceria gerado para o parceiro ' || v_p.codigo || ' · trilha ' || coalesce(v_p.trilha, '—') || ' · versão ' || v_v.versao || ' · aguardando assinatura eletrônica')
  RETURNING * INTO v_a;
  RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
END $parceiro_contrato_iniciar_assinatura_para$;
REVOKE ALL ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) TO service_role;

-- A tela de assinatura recebe o endereço pré-preenchido
CREATE OR REPLACE FUNCTION public.obter_contrato_publico(_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_assinatura public.contratos_assinaturas%ROWTYPE;
  v_contrato public.contratos_aceite%ROWTYPE;
  v_total_assinados INTEGER;
BEGIN
  SELECT * INTO v_assinatura FROM public.contratos_assinaturas WHERE token = _token;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro','token_invalido'); END IF;
  IF v_assinatura.status = 'assinado' THEN
    RETURN jsonb_build_object('erro','ja_assinado','assinado_em',v_assinatura.assinado_em, 'parceiro_id', v_assinatura.parceiro_id);
  END IF;
  IF v_assinatura.status = 'revogado' THEN RETURN jsonb_build_object('erro','revogado'); END IF;
  IF v_assinatura.expira_em IS NOT NULL AND v_assinatura.expira_em < now() THEN
    UPDATE public.contratos_assinaturas SET status='expirado' WHERE id = v_assinatura.id;
    RETURN jsonb_build_object('erro','expirado');
  END IF;

  SELECT * INTO v_contrato FROM public.contratos_aceite WHERE id = v_assinatura.contrato_id;
  IF NOT v_contrato.ativo THEN RETURN jsonb_build_object('erro','contrato_inativo'); END IF;

  IF v_contrato.limite_assinaturas IS NOT NULL THEN
    SELECT COUNT(*) INTO v_total_assinados FROM public.contratos_assinaturas
      WHERE contrato_id = v_contrato.id AND status='assinado';
    IF v_total_assinados >= v_contrato.limite_assinaturas THEN
      RETURN jsonb_build_object('erro','limite_atingido');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'titulo', v_contrato.titulo,
      'categoria', v_contrato.categoria,
      'descricao_publica', v_contrato.descricao_publica,
      'corpo_html', coalesce(v_assinatura.html_assinado, v_contrato.corpo_html),
      'versao', v_contrato.versao,
      'requer_cpf', v_contrato.requer_cpf,
      'requer_rg', v_contrato.requer_rg,
      'requer_endereco', v_contrato.requer_endereco,
      'requer_telefone', v_contrato.requer_telefone,
      'requer_selfie', v_contrato.requer_selfie,
      'requer_geolocalizacao', v_contrato.requer_geolocalizacao,
      'requer_cnpj', v_contrato.requer_cnpj,
      'requer_razao_social', v_contrato.requer_razao_social,
      'requer_representante', v_contrato.requer_representante
    ),
    'assinatura', jsonb_build_object(
      'id', v_assinatura.id,
      'signatario_email', v_assinatura.signatario_email,
      'signatario_nome', v_assinatura.signatario_nome,
      'signatario_cpf', v_assinatura.signatario_cpf,
      'signatario_telefone', v_assinatura.signatario_telefone,
      'signatario_endereco', v_assinatura.signatario_endereco,
      'signatario_cnpj', v_assinatura.signatario_cnpj,
      'signatario_razao_social', v_assinatura.signatario_razao_social,
      'expira_em', v_assinatura.expira_em,
      'parceiro_id', v_assinatura.parceiro_id
    )
  );
END;
$function$;

-- O endereço confirmado na assinatura volta para o cadastro do parceiro
CREATE OR REPLACE FUNCTION public.registrar_assinatura_contrato(
    _token text, _nome text, _cpf text DEFAULT NULL::text, _email text DEFAULT NULL::text, _telefone text DEFAULT NULL::text,
    _rg text DEFAULT NULL::text, _endereco text DEFAULT NULL::text, _assinatura_imagem text DEFAULT NULL::text,
    _selfie_imagem text DEFAULT NULL::text, _ip text DEFAULT NULL::text, _user_agent text DEFAULT NULL::text,
    _geo_lat numeric DEFAULT NULL::numeric, _geo_lng numeric DEFAULT NULL::numeric, _hash text DEFAULT NULL::text,
    _cnpj text DEFAULT NULL::text, _razao_social text DEFAULT NULL::text, _representante text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_assinatura public.contratos_assinaturas%ROWTYPE; v_versao int; v_uid uuid; v_ip text := _ip;
BEGIN
  SELECT * INTO v_assinatura FROM public.contratos_assinaturas WHERE token = _token FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'erro','token_invalido'); END IF;
  IF v_assinatura.status = 'assinado' THEN RETURN jsonb_build_object('ok',false,'erro','ja_assinado'); END IF;
  IF v_assinatura.expira_em IS NOT NULL AND v_assinatura.expira_em < now() THEN
    UPDATE public.contratos_assinaturas SET status='expirado' WHERE id=v_assinatura.id;
    RETURN jsonb_build_object('ok',false,'erro','expirado');
  END IF;

  IF v_ip IS NULL THEN
    BEGIN
      v_ip := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
                       current_setting('request.headers', true)::json->>'cf-connecting-ip');
    EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;
  END IF;

  UPDATE public.contratos_assinaturas SET
    signatario_nome = _nome, signatario_cpf = _cpf, signatario_email = COALESCE(_email, signatario_email),
    signatario_telefone = _telefone, signatario_rg = _rg, signatario_endereco = _endereco,
    signatario_cnpj = _cnpj, signatario_razao_social = _razao_social, signatario_representante = _representante,
    assinatura_imagem = _assinatura_imagem, selfie_imagem = _selfie_imagem,
    ip_address = v_ip, user_agent = _user_agent, geo_lat = _geo_lat, geo_lng = _geo_lng,
    hash_documento = _hash, assinado_em = now(), status = 'assinado'
  WHERE id = v_assinatura.id;

  IF v_assinatura.parceiro_id IS NOT NULL THEN
    SELECT c.versao INTO v_versao FROM public.contratos_aceite c WHERE c.id = v_assinatura.contrato_id;
    IF v_versao IS NOT NULL AND EXISTS (SELECT 1 FROM public.parceiro_contratos_versoes WHERE versao = v_versao) THEN
      SELECT user_id INTO v_uid FROM public.parceiro_usuarios WHERE parceiro_id = v_assinatura.parceiro_id ORDER BY (papel = 'dono') DESC, created_at LIMIT 1;
      INSERT INTO public.parceiro_contratos_aceites (parceiro_id, versao, user_id, ip, user_agent, hash_texto)
      VALUES (v_assinatura.parceiro_id, v_versao, coalesce(auth.uid(), v_uid), v_ip, left(_user_agent, 300),
              coalesce(_hash, encode(sha256(convert_to(coalesce(v_assinatura.html_assinado, ''), 'UTF8')), 'hex')))
      ON CONFLICT (parceiro_id, versao) DO NOTHING;
      UPDATE public.parceiros SET aceite_termos_em = coalesce(aceite_termos_em, now()),
        documento = coalesce(documento, nullif(_cpf, ''), nullif(_cnpj, '')),
        telefone = coalesce(telefone, nullif(_telefone, '')),
        endereco = coalesce(nullif(btrim(_endereco), ''), endereco)
      WHERE id = v_assinatura.parceiro_id;
      UPDATE public.contratos_assinaturas SET observacoes = replace(coalesce(observacoes, ''), 'aguardando assinatura eletrônica', 'assinado eletronicamente (assinatura, selfie, IP, dispositivo, localização, hash)')
      WHERE id = v_assinatura.id;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok',true,'assinatura_id',v_assinatura.id, 'parceiro_id', v_assinatura.parceiro_id);
END;
$function$;

-- Contrato ABNT: linha Endereço do parceiro
CREATE OR REPLACE FUNCTION public.parceiro_contrato_render_abnt(p_parceiro_id uuid, p_html text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_render_abnt$
DECLARE
  v_p    public.parceiros%ROWTYPE;
  v_ye   jsonb := public.youreyes_empresa_publica();
  v_v    public.parceiro_contratos_versoes%ROWTYPE;
  v_corpo text; v_css text; v_titulo text; v_doc_rotulo text; v_cidade_ye text; v_end text;
BEGIN
  IF p_parceiro_id IS NOT NULL THEN SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id; END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  v_corpo  := public.parceiro_contrato_render(p_parceiro_id, coalesce(p_html, v_v.html));
  v_titulo := coalesce(v_v.titulo, 'Contrato de Parceria Comercial');
  v_corpo := regexp_replace(v_corpo, '^\s*<h2>.*?</h2>\s*', '', 'i');
  v_corpo := regexp_replace(v_corpo, '^\s*<p><strong>Versão \d+</strong>[^<]*</p>\s*', '', 'i');
  v_doc_rotulo := CASE WHEN v_p.tipo_pessoa = 'pf' THEN 'CPF' ELSE 'CNPJ' END;
  v_cidade_ye := nullif(concat_ws('/', v_ye->>'cidade', v_ye->>'uf'), '');
  v_end := CASE WHEN v_p.id IS NOT NULL THEN public.parceiro_endereco_linha(v_p) END;

  v_css := '<style>'
    || '.contrato-abnt{font-family:"Times New Roman",Times,"Liberation Serif",serif;font-size:12pt;line-height:1.5;color:#111;background:#fff;text-align:justify;text-justify:inter-word;hyphens:auto;-webkit-hyphens:auto;padding:3cm 2cm 2cm 3cm;max-width:21cm;margin:0 auto;box-sizing:border-box;}'
    || '.contrato-abnt *{color:#111;}'
    || '.contrato-abnt h1{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:center;margin:0 0 1.5em 0;letter-spacing:.02em;}'
    || '.contrato-abnt h2{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:left;margin:1.5em 0 .75em 0;}'
    || '.contrato-abnt h3{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:left;margin:1.5em 0 .75em 0;}'
    || '.contrato-abnt p{margin:0 0 .75em 0;text-indent:1.25cm;text-align:justify;}'
    || '.contrato-abnt p.sem-recuo,.contrato-abnt .partes p,.contrato-abnt .fecho p,.contrato-abnt .assinaturas p{text-indent:0;}'
    || '.contrato-abnt .partes{margin:0 0 1.5em 0;}'
    || '.contrato-abnt .partes table{width:100%;border-collapse:collapse;font-size:12pt;margin:.5em 0 1em 0;}'
    || '.contrato-abnt .partes th,.contrato-abnt .partes td{border:1px solid #333;padding:.25em .5em;text-align:left;vertical-align:top;}'
    || '.contrato-abnt .partes th{width:32%;font-weight:bold;background:#f2f2f2;}'
    || '.contrato-abnt .fecho{margin-top:2em;}'
    || '.contrato-abnt .assinaturas{display:flex;gap:2cm;justify-content:space-between;margin-top:3em;page-break-inside:avoid;}'
    || '.contrato-abnt .assinaturas > div{flex:1;text-align:center;border-top:1px solid #111;padding-top:.5em;}'
    || '.contrato-abnt .assinaturas small{display:block;font-size:10pt;line-height:1.3;}'
    || '.contrato-abnt .rodape{margin-top:2em;font-size:10pt;line-height:1.3;text-align:justify;border-top:1px solid #999;padding-top:.5em;}'
    || '.contrato-abnt em{font-style:italic;}'
    || '@media (max-width:640px){.contrato-abnt{padding:1.5cm 1cm 1cm 1.25cm;font-size:11pt;}.contrato-abnt .assinaturas{flex-direction:column;gap:2.5em;}}'
    || '@media print{@page{size:A4;margin:3cm 2cm 2cm 3cm;}.contrato-abnt{padding:0;max-width:none;}}'
    || '</style>';

  RETURN v_css
    || '<div class="contrato-abnt">'
    || '<h1>' || v_titulo || '</h1>'
    || '<p class="sem-recuo"><strong>Versão ' || coalesce(v_v.versao::text, '—') || '</strong>, publicada em '
    || coalesce(to_char(v_v.publicado_em, 'DD/MM/YYYY'), '—') || '. Instrumento particular gerado em ' || to_char(now(), 'DD/MM/YYYY') || '.</p>'
    || '<div class="partes"><h2>Qualificação das partes</h2>'
    || '<table><tbody>'
    || '<tr><th colspan="2">CONTRATADA (“YourEyes”)</th></tr>'
    || '<tr><th>Razão social</th><td>' || coalesce(v_ye->>'razao_social', 'YourEyes') || coalesce(' (' || nullif(v_ye->>'nome_fantasia','') || ')', '') || '</td></tr>'
    || '<tr><th>CNPJ</th><td>' || coalesce(nullif(v_ye->>'cnpj',''), '________________') || '</td></tr>'
    || '<tr><th>Endereço</th><td>' || coalesce(nullif(v_ye->>'endereco_completo',''), '________________') || '</td></tr>'
    || '<tr><th>E-mail</th><td>' || coalesce(nullif(v_ye->>'email_contato',''), '________________') || '</td></tr>'
    || '<tr><th>Representante legal</th><td>' || coalesce(nullif(v_ye->>'representante_nome',''), '________________') || coalesce(' — ' || nullif(v_ye->>'representante_cargo',''), '') || '</td></tr>'
    || '<tr><th colspan="2">PARCEIRO(A)</th></tr>'
    || '<tr><th>Nome / razão social</th><td>' || coalesce(v_p.nome, '________________') || '</td></tr>'
    || '<tr><th>' || v_doc_rotulo || '</th><td>' || coalesce(v_p.documento, '________________') || '</td></tr>'
    || '<tr><th>E-mail</th><td>' || coalesce(v_p.email, '________________') || '</td></tr>'
    || '<tr><th>Telefone</th><td>' || coalesce(v_p.telefone, '________________') || '</td></tr>'
    || '<tr><th>Endereço</th><td>' || coalesce(v_end, '________________') || '</td></tr>'
    || '<tr><th>Código no programa</th><td>' || coalesce(v_p.codigo, '________________') || '</td></tr>'
    || '<tr><th>Perfil e trilha</th><td>' || coalesce(v_p.tipo_parceiro, '________') || ' — trilha ' || coalesce(initcap(v_p.trilha), '________') || '</td></tr>'
    || '</tbody></table></div>'
    || v_corpo
    || '<div class="fecho"><p>E, por estarem justas e contratadas, as partes firmam o presente instrumento em meio eletrônico, em uma única via digital, que produz os mesmos efeitos de documento físico assinado, na forma da Medida Provisória nº 2.200-2/2001, art. 10, § 2º, da Lei nº 14.063/2020 e do Código Civil, art. 107.</p>'
    || '<p>' || coalesce(v_cidade_ye, 'Brasil') || ', ' || to_char(now(), 'DD') || ' de '
    || (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'])[extract(month from now())::int]
    || ' de ' || to_char(now(), 'YYYY') || '.</p></div>'
    || '<div class="assinaturas">'
    || '<div><strong>' || coalesce(v_ye->>'razao_social', 'YourEyes') || '</strong><small>CNPJ ' || coalesce(nullif(v_ye->>'cnpj',''), '________________') || '</small><small>' || coalesce(nullif(v_ye->>'representante_nome',''), 'Representante legal') || '</small><small>CONTRATADA</small></div>'
    || '<div><strong>' || coalesce(v_p.nome, '________________') || '</strong><small>' || v_doc_rotulo || ' ' || coalesce(v_p.documento, '________________') || '</small><small>Assinatura eletrônica registrada com selfie, IP, dispositivo, localização e hash</small><small>PARCEIRO(A)</small></div>'
    || '</div>'
    || '<p class="rodape">Documento assinado eletronicamente. A autoria e a integridade são comprovadas pelo registro de assinatura da YourEyes: imagem da assinatura, fotografia (selfie) do signatário, endereço IP, identificação do dispositivo e navegador, coordenadas geográficas, data e hora e hash SHA-256 deste texto, guardados junto ao contrato e apresentados no relatório de assinatura.</p>'
    || '</div>';
END $parceiro_contrato_render_abnt$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_render_abnt(uuid, text) TO authenticated;

-- Portal: o objeto parceiro passa a trazer o endereço (para Meu cadastro)
CREATE OR REPLACE FUNCTION public.parceiro_meu_portal_com_contrato()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_portal_com_contrato$
  SELECT CASE WHEN public.parceiro_meu_id() IS NULL THEN NULL
         ELSE jsonb_set(public.parceiro_meu_portal(), '{parceiro,endereco}',
                        coalesce(to_jsonb((SELECT p.endereco FROM public.parceiros p WHERE p.id = public.parceiro_meu_id())), 'null'::jsonb), true)
              || jsonb_build_object('contrato', public.parceiro_contrato_situacao(public.parceiro_meu_id()))
              || jsonb_build_object('situacao', (SELECT jsonb_build_object('status', p.status, 'motivo', p.motivo_recusa,
                                                        'aprovado_em', p.aprovado_em, 'criado_em', p.created_at, 'trilha', p.trilha)
                                                 FROM public.parceiros p WHERE p.id = public.parceiro_meu_id()))
         END
$parceiro_meu_portal_com_contrato$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_portal_com_contrato() TO authenticated;

-- ---------------------------------------------------------------------
-- CONFERÊNCIA (único resultado exibido pelo editor)
-- ---------------------------------------------------------------------
WITH f AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE p.proname = 'parceiro_ref_publico') AS ref_publico,
         count(*) FILTER (WHERE p.proname = 'cadastro_empresa_livre_ativo') AS porta_livre_fn,
         count(*) FILTER (WHERE p.proname = 'superadmin_portas_entrada_salvar') AS portas_salvar,
         count(*) FILTER (WHERE p.proname = 'parceiro_endereco_linha') AS endereco_fn,
         count(*) FILTER (WHERE p.proname = 'qa_caso_pgp_017') AS qa017
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
), c AS MATERIALIZED (
  SELECT public.cadastro_empresa_livre_ativo() AS porta_livre_aberta,
         (SELECT valor FROM public.app_config WHERE chave = 'cadastro_empresa_trial_dias') AS trial_dias,
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'parceiros' AND column_name = 'endereco') AS coluna_endereco
), q AS MATERIALIZED (
  SELECT r.situacao, r.erro_tecnico FROM public.qa_caso_pgp_017() r
), q2 AS MATERIALIZED (
  SELECT r.situacao AS situacao16 FROM public.qa_caso_pgp_016() r
)
SELECT CASE WHEN f.ref_publico = 1 AND f.porta_livre_fn = 1 AND f.portas_salvar = 1 AND f.endereco_fn = 1 AND f.qa017 = 1
             AND c.coluna_endereco AND q.situacao = 'passou' AND q2.situacao16 = 'passou'
            THEN 'OK' ELSE 'REVISAR' END AS resultado,
       f.ref_publico, f.porta_livre_fn, f.portas_salvar, f.endereco_fn, f.qa017,
       c.porta_livre_aberta, c.trial_dias, c.coluna_endereco, q.situacao AS qa_pgp_017, q2.situacao16 AS qa_pgp_016, q.erro_tecnico
FROM f, c, q, q2;
