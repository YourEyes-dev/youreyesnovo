-- ============================================================================
-- Motor de QA — MarketYE: rotinas dos casos api com superfície de banco.
--
-- Destes casos, a fatia testável no motor SQL:
--   MKY-131 — anti-leakage: o filtro de saída mascara telefone/e-mail/link.
--   MKY-091 — LGPD: excluir o perfil apaga o pessoal e retém o transacional.
--   MKY-117 — cadastro atômico: entrada inválida é recusada e não deixa conta
--             órfã (o profissional só nasce inteiro).
-- (O miolo de IA/HTTP dos demais — 069/104/130/132/133/134 — é de runtime/tela;
--  fica para cobertura edge/e2e, não para o motor SQL.)
-- ============================================================================

-- ── MKY-131: anti-leakage na saída (mascaramento de contato) ────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_mky_131()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_in text; v_out text; v_falhas text[] := '{}';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Passar uma "resposta da IA" com telefone, e-mail e link pelo filtro de saída';
  r.esperado := 'Telefone, e-mail e link saem mascarados; nenhum chega cru ao usuário';

  v_in := 'Fecho direto: (11) 98888-7777, meu e-mail joao.teste@exemplo.com e o site https://wa.me/5511988887777';
  v_out := public.marketye_mascarar_contato(v_in);

  IF v_out ~ '\d{4,5}[\s.-]?\d{4}' THEN v_falhas := array_append(v_falhas, 'telefone não mascarado'); END IF;
  IF v_out ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' THEN v_falhas := array_append(v_falhas, 'e-mail não mascarado'); END IF;
  IF v_out ~ '(https?://|www\.)' THEN v_falhas := array_append(v_falhas, 'link não mascarado'); END IF;

  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Telefone, e-mail e link foram mascarados na saída — a IA não vira canal direto.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ') || '. Saída: ' || v_out;
  END IF;
  r.detalhe := jsonb_build_object('entrada', v_in, 'saida', v_out);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── MKY-091: LGPD — exclusão apaga o pessoal e retém o transacional ─────────
CREATE OR REPLACE FUNCTION public.qa_caso_mky_091()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_claims text; a record; v_falhas text[] := '{}';
        v_prof record; n_audit int;
BEGIN
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM public.qa_mky_limpar();

  r.passo_ordem := 1; r.passo_acao := 'Especialista com foto e dados pessoais pede exclusão';
  r.esperado := 'Campos pessoais (foto, CPF, e-mail, telefone) anonimizados; auditoria retida';

  SELECT * INTO a FROM public.qa_mky_especialista('091', public.qa_cpf(91));
  PERFORM public.qa_mky_claims(a.uid);
  UPDATE public.marketplace_profissionais SET foto_url = 'https://exemplo/foto.jpg', bio = 'bio pessoal' WHERE id = a.prof_id;

  PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');

  SELECT nome_completo, cpf_cnpj, foto_url, telefone, email, bio, status, excluido_em
    INTO v_prof FROM public.marketplace_profissionais WHERE id = a.prof_id;
  IF v_prof.cpf_cnpj IS NOT NULL THEN v_falhas := array_append(v_falhas, 'CPF/CNPJ não apagado'); END IF;
  IF v_prof.foto_url IS NOT NULL THEN v_falhas := array_append(v_falhas, 'foto não apagada'); END IF;
  IF v_prof.telefone IS NOT NULL THEN v_falhas := array_append(v_falhas, 'telefone não apagado'); END IF;
  IF v_prof.bio IS NOT NULL THEN v_falhas := array_append(v_falhas, 'bio não apagada'); END IF;
  IF v_prof.excluido_em IS NULL THEN v_falhas := array_append(v_falhas, 'exclusão não marcada'); END IF;

  -- Transacional retido: o registro de auditoria da exclusão permanece.
  SELECT count(*) INTO n_audit FROM public.marketplace_audit_log
   WHERE profissional_id = a.prof_id AND acao = 'exclusao_lgpd';
  IF n_audit < 1 THEN v_falhas := array_append(v_falhas, 'auditoria da exclusão não retida'); END IF;

  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Exclusão apagou o pessoal (CPF, foto, telefone, bio) e marcou a saída; a auditoria transacional ficou retida.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(NULLIF(v_claims, ''), '{}'), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── MKY-117: cadastro atômico — entrada inválida não deixa conta órfã ───────
CREATE OR REPLACE FUNCTION public.qa_caso_mky_117()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_uid uuid := gen_random_uuid(); v_tag text := left(v_uid::text, 8);
        v_recusou boolean := false; n_orfa int; v_falhas text[] := '{}'; v_res jsonb; v_ok_id uuid;
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar especialista com entrada inválida (dados vazios)';
  r.esperado := 'Recusa com erro claro; nenhuma conta parcial criada';

  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky117-' || v_tag || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN v_recusou := true;
  END;
  SELECT count(*) INTO n_orfa FROM public.marketplace_profissionais WHERE user_id = v_uid;

  IF NOT v_recusou THEN v_falhas := array_append(v_falhas, 'entrada inválida foi aceita'); END IF;
  IF n_orfa > 0 THEN v_falhas := array_append(v_falhas, format('sobrou conta órfã (%s linha)', n_orfa)); END IF;

  r.passo_ordem := 2; r.passo_acao := 'Cadastrar com entrada válida'; r.esperado := 'Profissional criado inteiro';
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Cadastro 117', 'email', 'qa-mky117-' || v_tag || '@sandbox.invalid',
    'cpf_cnpj', public.qa_cpf(117), 'cidade', 'Cidade QA', 'estado', 'QA',
    'modalidades', '["online"]'::jsonb, 'aceite_termos', true, 'conselho', 'CREA',
    'registro_profissional', 'QA-117', 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  v_ok_id := (v_res->>'id')::uuid;
  IF v_ok_id IS NULL THEN v_falhas := array_append(v_falhas, 'entrada válida não criou o profissional'); END IF;

  IF array_length(v_falhas, 1) IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Entrada inválida recusada sem deixar conta órfã; entrada válida criou o profissional inteiro.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || array_to_string(v_falhas, '; ');
  END IF;
  r.detalhe := jsonb_build_object('recusou_invalida', v_recusou, 'orfas', n_orfa);
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── Ligar caso ↔ rotina ─────────────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('MKY-131', 'qa_caso_mky_131', true),
  ('MKY-091', 'qa_caso_mky_091', true),
  ('MKY-117', 'qa_caso_mky_117', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
