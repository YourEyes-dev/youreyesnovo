-- =====================================================================
-- PROGRAMA DE PARCEIROS · APROVAÇÃO EM DUAS TRAVAS, INDICAÇÃO NO SITE E
-- PORTA LIVRE DE CADASTRO DE EMPRESA FECHADA (com chave para reabrir)
--
-- 1) Aprovação antes do contrato. Representante e Operador nascem
--    "pendente". Enquanto pendente, NÃO se gera o Contrato de Parceria
--    (nada para assinar) e a Área do Parceiro mostra só a tela de espera.
--    Quando o SuperAdmin aprova, o contrato pendente é gerado na hora e o
--    parceiro é chamado a assinar. Indicador continua automático (ativo →
--    contrato imediato). Suspenso/encerrado: sem contrato novo.
-- 2) Faixa de indicação no site: função pública que devolve o nome do
--    parceiro a partir do código do link, para o site dizer "Você foi
--    indicado por X".
-- 3) Porta livre fechada: a tela "Cadastre sua empresa" (criar empresa sem
--    plano/pagamento) passa a obedecer a chave app_config
--    'cadastro_empresa_livre' (padrão 'nao'). A chave
--    'cadastro_empresa_trial_dias' fica reservada para o futuro período de
--    teste (guardada, ainda sem efeito no motor). Ambas editáveis pelo
--    SuperAdmin › Dados da YourEyes › Portas de entrada.
--
-- Idempotente. Só cria/substitui funções e semeia chaves de configuração
-- (sem sobrescrever valor existente). Não altera assinatura nem parceiro.
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
