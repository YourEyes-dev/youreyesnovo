-- ============================================================================
-- PGP-014 — reforço da correção da fixture (reaplicação forward-only).
--
-- A correção da fixture (cidade fictícia única, migration 20260915235000) está
-- correta e provada robusta na réplica: mesmo com um parceiro REAL em
-- "Pato Branco/PR" (ex.: Clínica Staging SST), o QA Perto — único na cidade
-- fictícia — sai em 1º. Ainda assim o staging continuava reprovando o caso, com
-- o sintoma exato do corpo ANTIGO (empate de "mesma cidade" com o parceiro real,
-- desempatado pelo nome: "Clínica..." < "QA..."). Causa provável: o `db push`
-- do Supabase indexa a migration pelo CARIMBO; a versão 20260915235000 já
-- constava aplicada no staging e a edição posterior do arquivo foi ignorada — o
-- corpo novo nunca chegou ao banco.
--
-- Aqui o mesmo CREATE OR REPLACE é reemitido sob um carimbo NOVO, forçando a
-- esteira a aplicar o corpo corrigido. É idempotente e forward-only; nenhuma
-- regra do sistema muda — só o caso de teste.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_014()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE r public.qa_retorno; v_lead uuid; v_perto uuid; v_longe uuid; v_sug jsonb; v_atrib text; v_sa uuid;
        v_cidade text := 'QA Cidade Fixture PGP014';   -- fictícia e única: isola de parceiros reais
        v_cid_gravada text;
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
    SELECT cidade INTO v_cid_gravada FROM public.leads WHERE id = v_lead;
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: 1º sugerido = %s (motivo %s; esperado QA Perto); atribuição = %s (esperado casa). Cidade do lead gravada = %L (esperado %L).',
                       v_sug->0->>'nome', v_sug->0->>'motivo', v_atrib, v_cid_gravada, v_cidade);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
