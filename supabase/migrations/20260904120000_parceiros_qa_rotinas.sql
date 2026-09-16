-- ============================================================================
-- QA PGP — rotinas dos casos do Programa de Parceiros que a Onda 1 já torna
-- testáveis (PGP-001..006). Os demais (010-015) seguem documentados e
-- aparecem como nao_implementado até as Ondas 2-4; os e2e ficam no Cypress.
--
-- Padrão da casa: sondas de escrita com linhas sintéticas (código QA-*)
-- apagadas ao final + auditorias somente leitura em pg_class/pg_policies/
-- information_schema. Nenhuma funcionalidade é alterada.
-- ============================================================================

-- PGP-001 — status inicial por tipo
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_a uuid; v_b uuid; sa text; aa text; sb text; ab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Inserir indicador e implantador sem status';
  r.esperado := 'Indicador ativo/automatica; implantador pendente/manual';
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP001-A', 'QA Indicador', 'indicador') RETURNING id INTO v_a;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP001-B', 'QA Implantador', 'implantador') RETURNING id INTO v_b;
  SELECT status, aprovacao INTO sa, aa FROM public.parceiros WHERE id = v_a;
  SELECT status, aprovacao INTO sb, ab FROM public.parceiros WHERE id = v_b;
  DELETE FROM public.parceiros WHERE id IN (v_a, v_b);
  IF sa = 'ativo' AND aa = 'automatica' AND sb = 'pendente' AND ab = 'manual' THEN
    r.situacao := 'passou'; r.obtido := format('indicador %s/%s; implantador %s/%s', sa, aa, sb, ab);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('indicador %s/%s; implantador %s/%s — a regra de aprovação por tipo não foi aplicada.', sa, aa, sb, ab);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-002 — código único + link principal automático
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_links int; v_dup boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Cadastrar parceiro QA-PGP-002 e conferir o link principal';
  r.esperado := 'Um parceiro_links com o mesmo código, campanha principal, ativo';
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP-002', 'QA Link', 'indicador') RETURNING id INTO v_id;
  SELECT count(*) INTO v_links FROM public.parceiro_links
  WHERE parceiro_id = v_id AND codigo = 'QA-PGP-002' AND campanha = 'principal' AND ativo;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar um segundo parceiro com o mesmo código';
  r.esperado := 'Recusado por unicidade';
  BEGIN
    INSERT INTO public.parceiros (codigo, nome, tipo_parceiro) VALUES ('QA-PGP-002', 'QA Dup', 'indicador');
    v_dup := true;
    DELETE FROM public.parceiros WHERE codigo = 'QA-PGP-002' AND nome = 'QA Dup';
  EXCEPTION WHEN unique_violation THEN v_dup := false;
  END;
  DELETE FROM public.parceiros WHERE id = v_id;

  IF v_links = 1 AND NOT v_dup THEN
    r.situacao := 'passou'; r.obtido := 'Link principal criado junto; código duplicado recusado.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('links principais: %s (esperado 1); duplicado aceito: %s', v_links, v_dup);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-003 — RLS ligada e sem política aberta
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_sem_rls text; v_abertas text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: RLS ligada em parceiros, parceiro_usuarios, parceiro_links, parceiro_link_cliques, parceiro_comissoes';
  r.esperado := 'relrowsecurity = true nas 5';
  SELECT string_agg(t, ', ') INTO v_sem_rls
  FROM unnest(ARRAY['parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques','parceiro_comissoes']) t
  WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = t AND c.relrowsecurity);

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: nenhuma política de SELECT permissiva com USING (true) para authenticated/anon';
  r.esperado := 'Só políticas que citam parceiro_meu_id/parceiro_usuarios ou is_superadmin';
  SELECT string_agg(tablename || '.' || policyname, ', ') INTO v_abertas
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('parceiros','parceiro_usuarios','parceiro_links','parceiro_link_cliques','parceiro_comissoes')
    AND permissive = 'PERMISSIVE'
    AND cmd IN ('SELECT','ALL')
    AND coalesce(qual,'') NOT ILIKE '%parceiro_meu_id%'
    AND coalesce(qual,'') NOT ILIKE '%parceiro_usuarios%'
    AND coalesce(qual,'') NOT ILIKE '%is_superadmin%';

  IF v_sem_rls IS NULL AND v_abertas IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'RLS ligada nas 5 tabelas; toda leitura passa por vínculo ou superadmin.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || coalesce('sem RLS: ' || v_sem_rls || '. ', '')
             || coalesce('políticas abertas: ' || v_abertas || '.', '')
             || ' Carteira e comissão são dados comerciais de cada parceiro — ligue RLS e restrinja a leitura ao vínculo.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-004 — origem no tenant e FKs SET NULL
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_faltam text; v_ruins text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: colunas de origem em tenants e leads';
  r.esperado := 'tenants.parceiro_id, parceiro_link_id, originado_em, implantador_parceiro_id; leads.parceiro_id, atribuicao';
  SELECT string_agg(x, ', ') INTO v_faltam FROM (VALUES
    ('tenants.parceiro_id'),('tenants.parceiro_link_id'),('tenants.originado_em'),('tenants.implantador_parceiro_id'),
    ('leads.parceiro_id'),('leads.atribuicao')) v(x)
  WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = split_part(x,'.',1) AND column_name = split_part(x,'.',2));

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: regra de exclusão das FKs tenants/leads → parceiros';
  r.esperado := 'SET NULL';
  SELECT string_agg(tc.table_name || '.' || tc.constraint_name || '=' || rc.delete_rule, ', ') INTO v_ruins
  FROM information_schema.table_constraints tc
  JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name AND rc.constraint_schema = tc.table_schema
  JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = rc.unique_constraint_name AND ccu.constraint_schema = rc.unique_constraint_schema
  WHERE tc.table_schema = 'public' AND tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_name IN ('tenants','leads') AND ccu.table_name IN ('parceiros','parceiro_links')
    AND rc.delete_rule <> 'SET NULL';

  IF v_faltam IS NULL AND v_ruins IS NULL THEN
    r.situacao := 'passou'; r.obtido := 'Colunas presentes; FKs com SET NULL — encerrar parceiro não arrasta cliente.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: ' || coalesce('faltam colunas: ' || v_faltam || '. ', '')
             || coalesce('FKs sem SET NULL: ' || v_ruins || '.', '');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-005 — remuneração por evento em tabela
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_linha int; v_motor boolean; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: evento setup_concluido semeado para implantador';
  r.esperado := 'Linha ativa em parceiro_eventos_remuneracao';
  SELECT count(*) INTO v_linha FROM public.parceiro_eventos_remuneracao
  WHERE tipo_parceiro = 'implantador' AND evento = 'setup_concluido' AND ativo;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: se o motor de fechamento existir, ele lê a tabela';
  r.esperado := 'parceiro_fechar_competencia referencia parceiro_eventos_remuneracao (ou ainda não existe — Onda 3)';
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'parceiro_fechar_competencia') INTO v_motor;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'parceiro_fechar_competencia'
                   AND p.prosrc ILIKE '%parceiro_eventos_remuneracao%') INTO v_le;

  IF v_linha >= 1 AND (NOT v_motor OR v_le) THEN
    r.situacao := 'passou';
    r.obtido := CASE WHEN v_motor THEN 'Tabela semeada e lida pelo motor.'
                     ELSE 'Tabela semeada; motor de fechamento ainda não existe (Onda 3) — sonda passa a exigir a leitura quando ele nascer.' END;
  ELSE
    r.situacao := 'falhou';
    r.obtido := CASE WHEN v_linha = 0 THEN 'ACHADO: sem linha de setup_concluido para implantador — o setup do implantador ficou sem valor configurável.'
                     ELSE 'ACHADO: o motor de fechamento existe e NÃO lê parceiro_eventos_remuneracao — o valor do setup está fixo no código.' END;
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-006 — níveis por trilha
CREATE OR REPLACE FUNCTION public.qa_caso_pgp_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_n int; v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA: trilha operador com ≥ 2 níveis ativos e mrr_minimo crescente com a ordem';
  r.esperado := 'Visão (0) antes de Diamante (> 0)';
  SELECT count(*) INTO v_n FROM public.parceiro_niveis WHERE trilha = 'operador' AND ativo;
  SELECT coalesce(bool_and(ok), false) INTO v_ok FROM (
    SELECT mrr_minimo_cents >= coalesce(lag(mrr_minimo_cents) OVER (ORDER BY ordem), -1) AS ok
    FROM public.parceiro_niveis WHERE trilha = 'operador' AND ativo) s;
  IF v_n >= 2 AND v_ok THEN
    r.situacao := 'passou'; r.obtido := format('%s níveis, faixas crescentes.', v_n);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s níveis; faixas crescentes: %s — a barra "faltam R$ X para o próximo nível" não tem base.', v_n, v_ok);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro no motor ──
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('PGP-001', 'qa_caso_pgp_001'),
  ('PGP-002', 'qa_caso_pgp_002'),
  ('PGP-003', 'qa_caso_pgp_003'),
  ('PGP-004', 'qa_caso_pgp_004'),
  ('PGP-005', 'qa_caso_pgp_005'),
  ('PGP-006', 'qa_caso_pgp_006')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
