-- ============================================================================
-- Fase 4 — PGP-014: isolamento da fixture (cidade fictícia única).
--
-- O caso falhava no STAGING porque a fixture usava "Pato Branco/PR", a mesma
-- cidade de um parceiro REAL do staging (Clínica Staging SST) — que então
-- disputava e vencia a 1ª posição da sugestão por proximidade. A função
-- parceiros_sugerir_para_lead está correta (passa na réplica isolada); o que
-- faltava era a fixture não colidir com dado real. Aqui o lead e o parceiro
-- "QA Perto" passam a usar uma CIDADE FICTÍCIA ÚNICA, de modo que só a fixture
-- é "mesma cidade" e a sugestão fica determinística em qualquer ambiente.
-- (Só o caso de teste muda; nenhuma regra do sistema é alterada.)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_014()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_lead uuid; v_perto uuid; v_longe uuid; v_sug jsonb; v_atrib text; v_sa uuid;
        v_cidade text := 'QA Cidade Fixture PGP014';   -- fictícia e única: isola de parceiros reais
BEGIN
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-PERTO', 'QA Perto', 'representante', 'ativo', v_cidade, 'PR') RETURNING id INTO v_perto;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, status, cidade, uf) VALUES ('QA-PGP-LONGE', 'QA Longe', 'representante', 'ativo', 'Manaus', 'AM') RETURNING id INTO v_longe;
  INSERT INTO public.leads (nome, empresa, cidade, uf) VALUES ('QA Lead', 'QA Empresa Local', v_cidade, 'pr') RETURNING id INTO v_lead;
  -- simula superadmin para as funções que exigem
  SELECT user_id INTO v_sa FROM public.superadmins WHERE ativo LIMIT 1;
  IF v_sa IS NULL THEN
    v_sa := gen_random_uuid();
    INSERT INTO auth.users (id, email) VALUES (v_sa, 'qa-sa-' || left(v_sa::text,8) || '@exemplo.test');
    INSERT INTO public.superadmins (user_id, email) VALUES (v_sa, 'qa-sa@exemplo.test');
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_sa, 'role', 'authenticated')::text, true);

  r.passo_ordem := 1; r.passo_acao := 'Sugerir parceiros para lead da cidade-fixture (mesma cidade só do QA Perto)';
  r.esperado := 'Parceiro da mesma cidade em primeiro';
  v_sug := public.parceiros_sugerir_para_lead(v_lead);
  r.passo_ordem := 2; r.passo_acao := 'Encaminhar o lead ao parceiro sugerido';
  r.esperado := 'leads.atribuicao = casa';
  PERFORM public.superadmin_lead_encaminhar(v_lead, v_perto);
  SELECT atribuicao INTO v_atrib FROM public.leads WHERE id = v_lead;

  IF (v_sug->0->>'id')::uuid = v_perto AND v_atrib = 'casa' THEN
    r.situacao := 'passou'; r.obtido := format('1º sugerido: %s (%s); atribuição %s', v_sug->0->>'nome', v_sug->0->>'motivo', v_atrib);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: 1º sugerido = %s (esperado QA Perto); atribuição = %s (esperado casa).', v_sug->0->>'nome', v_atrib);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
