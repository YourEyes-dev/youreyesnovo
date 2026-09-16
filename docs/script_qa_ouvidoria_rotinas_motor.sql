-- ============================================================================
-- ENTREGA — QA Ouvidoria: rotinas executaveis pelo motor
--
-- SO CRIA/LIGA ROTINAS DE TESTE. Cria 9 funcoes qa_caso_ouv_* (somente leitura
-- do catalogo), liga-as aos casos em qa_implementacoes e classifica esses 9
-- casos como 'api'. Nao cria tabela de negocio, nao altera nem apaga dado.
--
-- ONDE COLAR: no SQL Editor da homologacao (e da producao, quando aprovado).
-- Idempotente: CREATE OR REPLACE + ON CONFLICT DO UPDATE. Termina com uma
-- conferencia (o editor mostra so o ultimo resultado).
-- ============================================================================

SET lock_timeout = '10s';

-- ─────────────────────────────────────────────────────────
-- Helpers de leitura do catalogo (uma linha cada)
-- ─────────────────────────────────────────────────────────

-- OUV-003: os cinco tipos de manifestacao sao aceitos pelo banco (CHECK).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_003()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir no banco que os cinco tipos de manifestacao sao aceitos';
  r.esperado    := 'CHECK de tipo aceita sugestao, reclamacao, denuncia, elogio e duvida';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%tipo%';
  v_def := COALESCE(v_def, '');
  IF position('sugestao'  IN v_def) = 0 THEN v_faltam := v_faltam || 'sugestao '; END IF;
  IF position('reclamacao' IN v_def) = 0 THEN v_faltam := v_faltam || 'reclamacao '; END IF;
  IF position('denuncia'  IN v_def) = 0 THEN v_faltam := v_faltam || 'denuncia '; END IF;
  IF position('elogio'    IN v_def) = 0 THEN v_faltam := v_faltam || 'elogio '; END IF;
  IF position('duvida'    IN v_def) = 0 THEN v_faltam := v_faltam || 'duvida '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'Os cinco tipos estao no CHECK de tipo.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Tipos ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-004: o banco recusa manifestacao sem assunto (coluna NOT NULL).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_004()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco exige o assunto (envio sem assunto e recusado)';
  r.esperado    := 'ouvidoria.assunto e NOT NULL';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT a.attnotnull INTO v FROM pg_attribute a
  WHERE a.attrelid = 'public.ouvidoria'::regclass AND a.attname = 'assunto' AND NOT a.attisdropped;
  IF v IS TRUE THEN
    r.situacao := 'passou'; r.obtido := 'assunto e obrigatorio no banco; envio sem assunto e recusado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'assunto NAO e obrigatorio — o banco aceitaria manifestacao sem assunto.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-005: o banco recusa manifestacao sem mensagem (coluna NOT NULL).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_005()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco exige a mensagem';
  r.esperado    := 'ouvidoria.mensagem e NOT NULL';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT a.attnotnull INTO v FROM pg_attribute a
  WHERE a.attrelid = 'public.ouvidoria'::regclass AND a.attname = 'mensagem' AND NOT a.attisdropped;
  IF v IS TRUE THEN
    r.situacao := 'passou'; r.obtido := 'mensagem e obrigatoria no banco; envio sem mensagem e recusado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'mensagem NAO e obrigatoria — o banco aceitaria manifestacao sem mensagem.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-010: a politica de INSERT sustenta o anonimato (LGPD) e a autoria.
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_010()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_rls boolean; v_check text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco protege o anonimato: RLS ligada e a regra de insercao amarra anonimato e autoria';
  r.esperado    := 'RLS ligada; politica de INSERT exige (anonimo e sem autor) ou (identificado e autor = usuario logado)';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid = 'public.ouvidoria'::regclass;
  SELECT with_check INTO v_check FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'ouvidoria' AND cmd = 'INSERT'
  ORDER BY policyname LIMIT 1;
  v_check := COALESCE(v_check, '');
  IF v_rls IS NOT TRUE THEN
    r.situacao := 'falhou'; r.obtido := 'RLS esta DESLIGADA em ouvidoria — a fila ficaria exposta.';
  ELSIF position('anonimo' IN v_check) > 0 AND position('autor_id' IN v_check) > 0 THEN
    r.situacao := 'passou';
    r.obtido := 'RLS ligada e a politica de INSERT amarra anonimato e autoria; anonimo nasce sem autor.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A politica de INSERT nao amarra anonimato/autoria como esperado (with_check: ' || left(v_check, 120) || ').';
  END IF;
  r.detalhe := jsonb_build_object('rls', v_rls, 'with_check', v_check);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-023: o CHECK de status cobre o ciclo pendente -> em_analise -> respondido -> arquivado.
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_023()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco aceita todo o ciclo de status do tratamento';
  r.esperado    := 'CHECK de status aceita pendente, em_analise, respondido e arquivado';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%status%';
  v_def := COALESCE(v_def, '');
  IF position('pendente'   IN v_def) = 0 THEN v_faltam := v_faltam || 'pendente '; END IF;
  IF position('em_analise' IN v_def) = 0 THEN v_faltam := v_faltam || 'em_analise '; END IF;
  IF position('respondido' IN v_def) = 0 THEN v_faltam := v_faltam || 'respondido '; END IF;
  IF position('arquivado'  IN v_def) = 0 THEN v_faltam := v_faltam || 'arquivado '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'O ciclo de status esta completo no CHECK.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Status ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-024: o CHECK de prioridade cobre baixa/normal/alta/urgente.
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_024()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_def text; v_faltam text := '';
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que o banco aceita as prioridades de tratamento';
  r.esperado    := 'CHECK de prioridade aceita baixa, normal, alta e urgente';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT string_agg(pg_get_constraintdef(c.oid), ' ') INTO v_def
  FROM pg_constraint c
  WHERE c.conrelid = 'public.ouvidoria'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) LIKE '%prioridade%';
  v_def := COALESCE(v_def, '');
  IF position('baixa'   IN v_def) = 0 THEN v_faltam := v_faltam || 'baixa '; END IF;
  IF position('normal'  IN v_def) = 0 THEN v_faltam := v_faltam || 'normal '; END IF;
  IF position('alta'    IN v_def) = 0 THEN v_faltam := v_faltam || 'alta '; END IF;
  IF position('urgente' IN v_def) = 0 THEN v_faltam := v_faltam || 'urgente '; END IF;
  IF v_faltam = '' THEN
    r.situacao := 'passou'; r.obtido := 'As quatro prioridades estao no CHECK.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'Prioridades ausentes no CHECK: ' || v_faltam;
  END IF;
  r.detalhe := jsonb_build_object('constraint', v_def);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-031: o roteamento existe e e restrito a gestao (RLS de administrador).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_031()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_rls boolean; v_admin boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a configuracao de roteamento existe e e restrita a administrador';
  r.esperado    := 'ouvidoria_roteamento com RLS ligada e politica de gestao exigindo papel de administrador';
  IF to_regclass('public.ouvidoria_roteamento') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria_roteamento ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE oid = 'public.ouvidoria_roteamento'::regclass;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ouvidoria_roteamento'
      AND cmd IN ('ALL','INSERT','UPDATE')
      AND COALESCE(qual,'') || COALESCE(with_check,'') LIKE '%has_minimum_role%'
      AND COALESCE(qual,'') || COALESCE(with_check,'') LIKE '%admin%'
  ) INTO v_admin;
  IF v_rls IS TRUE AND v_admin THEN
    r.situacao := 'passou'; r.obtido := 'Roteamento protegido: RLS ligada e gestao restrita a administrador.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Roteamento sem a protecao esperada (rls=' || COALESCE(v_rls::text,'?')
             || ', politica_admin=' || COALESCE(v_admin::text,'?') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-033: excluir manifestacao e restrito a administrador (politica de DELETE).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_033()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_qual text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a exclusao de manifestacao exige papel de administrador';
  r.esperado    := 'politica de DELETE em ouvidoria exige has_minimum_role de administrador';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT qual INTO v_qual FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'ouvidoria' AND cmd = 'DELETE'
  ORDER BY policyname LIMIT 1;
  IF v_qual IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Nao ha politica de DELETE em ouvidoria — a exclusao nao esta restrita.';
  ELSIF position('has_minimum_role' IN v_qual) > 0 AND position('admin' IN v_qual) > 0 THEN
    r.situacao := 'passou'; r.obtido := 'A exclusao exige papel de administrador, como esperado.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'A politica de DELETE nao exige administrador (qual: ' || left(v_qual,120) || ').';
  END IF;
  r.detalhe := jsonb_build_object('delete_qual', v_qual);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- OUV-034: colaborador ve so as proprias; gestao ve todas (duas politicas de SELECT).
CREATE OR REPLACE FUNCTION public.qa_caso_ouv_034()
RETURNS public.qa_retorno LANGUAGE plpgsql STABLE AS $$
DECLARE r public.qa_retorno; v_propria boolean; v_gestor boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir que a leitura da fila e segmentada: colaborador ve so as proprias, gestao ve todas';
  r.esperado    := 'uma politica de SELECT restringe ao proprio autor e outra libera para papel de gestao';
  IF to_regclass('public.ouvidoria') IS NULL THEN
    r.situacao := 'nao_implementado'; r.obtido := 'Tabela ouvidoria ausente neste ambiente.'; RETURN r;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ouvidoria' AND cmd='SELECT'
      AND position('autor_id' IN COALESCE(qual,'')) > 0
      AND position('auth.uid' IN COALESCE(qual,'')) > 0
  ) INTO v_propria;
  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ouvidoria' AND cmd='SELECT'
      AND position('has_minimum_role' IN COALESCE(qual,'')) > 0
  ) INTO v_gestor;
  IF v_propria AND v_gestor THEN
    r.situacao := 'passou';
    r.obtido := 'A fila e segmentada por perfil: colaborador ve as proprias, gestao ve todas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'Faltou uma das politicas de leitura (propria=' || v_propria::text
             || ', gestao=' || v_gestor::text || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ─────────────────────────────────────────────────────────
-- Ligar os casos as rotinas e classificar como 'api' (motor)
-- ─────────────────────────────────────────────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('OUV-003','qa_caso_ouv_003'),
  ('OUV-004','qa_caso_ouv_004'),
  ('OUV-005','qa_caso_ouv_005'),
  ('OUV-010','qa_caso_ouv_010'),
  ('OUV-023','qa_caso_ouv_023'),
  ('OUV-024','qa_caso_ouv_024'),
  ('OUV-031','qa_caso_ouv_031'),
  ('OUV-033','qa_caso_ouv_033'),
  ('OUV-034','qa_caso_ouv_034')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- Os casos que agora rodam no motor passam a nivel 'api' (verificacao de banco).
-- O tema e o titulo continuam; a observacao registra o que o motor confere.
UPDATE public.qa_casos_teste
SET nivel = 'api',
    observacoes = COALESCE(observacoes || ' ', '')
      || 'Executavel pelo motor: verifica no banco a regra que sustenta este fluxo (coluna/CHECK/politica RLS).'
WHERE codigo IN ('OUV-003','OUV-004','OUV-005','OUV-010','OUV-023','OUV-024','OUV-031','OUV-033','OUV-034')
  AND nivel <> 'api';

DO $fim$
DECLARE v_api int; v_impl int;
BEGIN
  SELECT count(*) INTO v_api FROM public.qa_casos_teste
   WHERE codigo LIKE 'OUV-%' AND nivel = 'api';
  SELECT count(*) INTO v_impl FROM public.qa_implementacoes
   WHERE codigo LIKE 'OUV-%' AND ativo;
  RAISE NOTICE 'Ouvidoria motor: casos api=% ; rotinas ligadas=% (esperado 9 e 9)', v_api, v_impl;
END $fim$;

-- Conferencia (o editor mostra so o ultimo resultado)
SELECT 'Ouvidoria — casos executaveis pelo motor' AS item,
       count(*) FILTER (WHERE c.nivel = 'api') AS casos_api,
       (SELECT count(*) FROM public.qa_implementacoes WHERE codigo LIKE 'OUV-%' AND ativo) AS rotinas_ligadas
FROM public.qa_casos_teste c
JOIN public.qa_modulos m ON m.id = c.modulo_id AND m.path = 'pessoas-cultura/ouvidoria'
WHERE c.codigo LIKE 'OUV-%';
