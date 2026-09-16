-- =====================================================================
-- MARKETYE · PORTAL ABRE LOGO DEPOIS DO CADASTRO MÍNIMO (regressão 11/09/2026)
--
-- O que aconteceu: um prestador se cadastrou pela página pública (nome,
-- documento, uma frase sobre o que faz, e-mail) e o portal ficou preso no
-- círculo de carregamento. Causa: o cadastro guarda "especialidades" vazias
-- como nulo; ao montar o portal, a conta de completude do perfil tentava
-- medir esse nulo como lista ("cannot get array length of a scalar") e a
-- função inteira falhava. Como a tela só tratava "carregando", ninguém via
-- o erro.
--
-- Correção: a completude só mede a lista quando ela é lista. A tela passou
-- a mostrar "Tentar de novo" em vez do círculo eterno (mudança de front).
-- Caso de QA MKY-014 documenta e cobre a regressão.
--
-- Idempotente: CREATE OR REPLACE e ON CONFLICT.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.marketye_meu_portal()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_portal$
DECLARE v_id uuid := public.marketye_meu_id(); v_perfil jsonb; v_rep jsonb; v_versoes jsonb; v_niveis jsonb; v_nivel text; v_ordem text[]; v_prox text; v_i int;
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT to_jsonb(p) - 'user_id' INTO v_perfil FROM public.marketplace_profissionais p WHERE p.id = v_id;
  SELECT to_jsonb(r) INTO v_rep FROM public.marketplace_reputacao r WHERE r.profissional_id = v_id;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_niveis := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_nivel := COALESCE(v_rep->>'nivel', 'novo');
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_niveis->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_prox := NULL;
  FOR v_i IN 1..COALESCE(array_length(v_ordem, 1), 1) LOOP
    IF v_ordem[v_i] = v_nivel AND v_i < array_length(v_ordem, 1) THEN v_prox := v_ordem[v_i + 1]; END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'perfil', v_perfil,
    'reputacao', v_rep,
    'nivel', jsonb_build_object('atual', v_nivel, 'proximo', v_prox, 'requisitos_proximo', v_niveis->'requisitos'->v_prox,
                                'aviso_em', v_rep->>'nivel_aviso_em', 'aviso_motivo', v_rep->>'nivel_aviso_motivo', 'ordem', to_jsonb(v_ordem)),
    'completude', (SELECT round(100.0 * (
        (v_perfil->>'foto_url' IS NOT NULL)::int + (COALESCE(v_perfil->>'bio', '') <> '')::int + (v_perfil->>'registro_profissional' IS NOT NULL)::int
        + ((CASE WHEN jsonb_typeof(v_perfil->'especialidades') = 'array' THEN jsonb_array_length(v_perfil->'especialidades') ELSE 0 END) > 0)::int + (v_perfil->>'cidade' IS NOT NULL)::int
        + (v_perfil->>'video_url' IS NOT NULL)::int + (v_perfil->>'telefone' IS NOT NULL)::int
        + (EXISTS (SELECT 1 FROM public.marketplace_servicos s WHERE s.profissional_id = v_id AND s.status = 'publicado'))::int) / 8)),
    'anuncios', COALESCE((SELECT jsonb_agg(to_jsonb(s) || jsonb_build_object('categoria_nome', c.nome, 'categoria_slug', c.slug, 'exige_registro', c.exige_registro) ORDER BY s.created_at DESC)
                          FROM public.marketplace_servicos s LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id WHERE s.profissional_id = v_id AND s.status <> 'removido'), '[]'::jsonb),
    'leads', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'status', l.status, 'created_at', l.created_at, 'contato_liberado', l.contato_liberado, 'primeira_resposta_em', l.primeira_resposta_em,
                'ultima_mensagem_em', l.ultima_mensagem_em, 'servico_nome', s.nome, 'empresa_nome', t.nome, 'origem_modulo', l.origem_modulo,
                'obrigacao_legal', l.obrigacao_legal, 'cupom_codigo', l.cupom_codigo, 'ganho_em', l.ganho_em,
                'reputacao_empresa', (SELECT jsonb_build_object('media', round(avg(a.nota_geral)::numeric, 1), 'total', count(*))
                                      FROM public.marketplace_avaliacoes a WHERE a.tenant_id = l.tenant_id AND a.direcao = 'especialista_para_cliente'),
                'ultima_mensagem', (SELECT m.texto FROM public.marketplace_lead_mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1),
                'avaliei', EXISTS (SELECT 1 FROM public.marketplace_avaliacoes a WHERE a.lead_id = l.id AND a.direcao = 'especialista_para_cliente')
              ) ORDER BY COALESCE(l.ultima_mensagem_em, l.created_at) DESC)
              FROM public.marketplace_leads l LEFT JOIN public.marketplace_servicos s ON s.id = l.servico_id LEFT JOIN public.tenants t ON t.id = l.tenant_id
              WHERE l.profissional_id = v_id), '[]'::jsonb),
    'metricas', jsonb_build_object(
      'leads_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND created_at >= now() - interval '30 days'),
      'leads_ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'ganho' AND ganho_em >= now() - interval '30 days'),
      'sem_resposta', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'novo'),
      'avaliacoes', (SELECT count(*) FROM public.marketplace_avaliacoes WHERE profissional_id = v_id AND direcao = 'cliente_para_especialista')),
    'avaliacoes', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'nota_geral', a.nota_geral, 'comentario', a.comentario, 'created_at', a.created_at,
                              'resposta', a.resposta, 'criterios', a.criterios, 'pontualidade', a.pontualidade, 'clareza', a.clareza,
                              'aderencia_escopo', a.aderencia_escopo, 'profissionalismo', a.profissionalismo) ORDER BY a.created_at DESC)
                            FROM public.marketplace_avaliacoes a WHERE a.profissional_id = v_id AND a.direcao = 'cliente_para_especialista' AND NOT a.moderada), '[]'::jsonb),
    'consentimentos', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.aceito_em DESC) FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id), '[]'::jsonb),
    'termos_pendentes', COALESCE((SELECT jsonb_agg(jsonb_build_object('tipo', t.tipo, 'versao', v_versoes->>t.tipo))
                                  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo)
                                  WHERE v_versoes->>t.tipo IS NOT NULL AND NOT EXISTS (
                                    SELECT 1 FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id AND c.tipo = t.tipo AND c.versao = v_versoes->>t.tipo)), '[]'::jsonb),
    'contestacoes', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM public.marketplace_contestacoes x WHERE x.profissional_id = v_id), '[]'::jsonb),
    'ocorrencias', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'descricao', o.descricao, 'created_at', o.created_at, 'reflexo_visibilidade', o.reflexo_visibilidade) ORDER BY o.created_at DESC)
                             FROM public.marketplace_ocorrencias o WHERE o.profissional_id = v_id), '[]'::jsonb),
    'cupons', COALESCE((SELECT jsonb_agg(to_jsonb(k) ORDER BY k.created_at DESC) FROM public.marketplace_cupons k WHERE k.profissional_id = v_id), '[]'::jsonb),
    'destaques', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.fim DESC) FROM public.marketplace_destaques d WHERE d.profissional_id = v_id), '[]'::jsonb),
    'autonomia_eventos', (SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = v_id),
    'termos_versoes', v_versoes,
    'parceiro', CASE WHEN v_perfil->>'parceiro_id' IS NOT NULL THEN jsonb_build_object('id', v_perfil->>'parceiro_id') END
  );
END $marketye_meu_portal$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_portal() TO authenticated;

-- ---------------------------------------------------------------------
-- QA: caso MKY-014 documentado + rotina
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes) VALUES
  (v_mod, 'MKY-014', 'Portal do especialista abre logo depois do cadastro mínimo (sem área, sem registro, sem cidade)',
   'feliz', 'critica', 'aprovado', 'api', 'RN-001, RN-012 (cadastro sem acesso ao sistema); RN-021',
   'O cadastro curto (nome, documento, uma frase sobre o que faz, e-mail) precisa abrir o portal em seguida; nenhum campo opcional em branco pode derrubar a leitura do portal.',
   'Versões de termos em marketplace_config (chave termos_versoes).',
   '[{"ordem":1,"acao":"Cadastrar pela função só com nome, CPF fictício, uma frase e aceite","resultado_esperado":"status pendente"},
     {"ordem":2,"acao":"Como o próprio especialista (papel authenticated), abrir o portal (marketye_meu_portal)","resultado_esperado":"devolve o perfil, lista de anúncios vazia e completude entre 0 e 100"},
     {"ordem":3,"acao":"Salvar o perfil sem área e sem cidade; abrir o portal de novo","resultado_esperado":"continua abrindo"}]'::jsonb,
   'O portal nunca fica em branco por causa de campo opcional vazio.',
   'Regressão real de 11/09/2026: especialidades nulas derrubavam a função do portal. Roda em transação descartada.')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_mky_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_claims text; v_portal jsonb; v_uid uuid := gen_random_uuid(); v_res jsonb; v_id uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);

  r.passo_ordem := 1; r.passo_acao := 'Cadastrar só com nome, CPF, uma frase e aceite'; r.esperado := 'pendente';
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista 014', 'email', 'qa-mky-esp-014-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', '900.000.013-09', 'bio', 'Dou treinamentos para equipes de manutenção', 'modalidades', '["presencial"]'::jsonb,
    'especialidades', '[]'::jsonb, 'aceite_termos', true, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  v_id := (v_res->>'id')::uuid;
  IF COALESCE(v_res->>'status', '') <> 'pendente' THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: cadastro nasceu ' || COALESCE(v_res->>'status', 'sem status'); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Abrir o portal como o próprio especialista'; r.esperado := 'perfil, anúncios vazios e completude entre 0 e 100';
  PERFORM public.qa_mky_claims(v_uid);
  SET LOCAL ROLE authenticated;
  v_portal := public.marketye_meu_portal();
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->'perfil'->>'id')::uuid IS DISTINCT FROM v_id OR jsonb_typeof(v_portal->'anuncios') <> 'array'
     OR (v_portal->>'completude')::numeric NOT BETWEEN 0 AND 100 THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal veio incompleto: ' || left(COALESCE(v_portal::text, 'NULL'), 200); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 3; r.passo_acao := 'Salvar o perfil sem área e sem cidade; abrir de novo'; r.esperado := 'continua abrindo';
  PERFORM public.qa_mky_claims(v_uid);
  PERFORM public.marketye_meu_perfil_salvar(jsonb_build_object('especialidades', '[]'::jsonb, 'cidade', '', 'estado', ''));
  SET LOCAL ROLE authenticated;
  v_portal := public.marketye_meu_portal();
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_portal IS NULL OR (v_portal->>'completude') IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: portal vazio depois de salvar o perfil'; PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.situacao := 'passou'; r.obtido := 'Portal abriu nas duas leituras; completude ' || (v_portal->>'completude') || '%.';
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('MKY-014', 'qa_caso_mky_014')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
