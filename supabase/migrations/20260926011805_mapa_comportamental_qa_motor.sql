-- ============================================================================
-- QA — Mapa Comportamental: módulo no motor + primeiras rotinas (nível api)
--
-- Registra o módulo na árvore de QA (filho de desenvolvimento-performance) e
-- documenta dois casos de motor, somente leitura:
--   MAPA-001 — o instrumento vigente v1 existe com 28 itens.
--   MAPA-002 — a tabela de respostas tem a política RESTRICTIVE de perfil
--              (PERFIL-003: tabela com dado pessoal precisa da trava).
-- As regras de apuração (desempate, consistência, arquétipo) são cobertas por
-- teste unitário TS (src/test/mapaComportamental.test.ts), porque o cálculo é
-- uma função pura versionada. Casos e2e (tela) entram na fatia de fechamento.
--
-- Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE
  v_parent uuid;
  v_mod    uuid;
BEGIN
  SELECT id INTO v_parent FROM public.qa_modulos WHERE path = 'desenvolvimento-performance';

  INSERT INTO public.qa_modulos (parent_id, label, path, ordem)
  VALUES (v_parent, 'Mapa Comportamental', 'desenvolvimento-performance/mapa-comportamental', 50)
  ON CONFLICT (path) DO NOTHING;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'desenvolvimento-performance/mapa-comportamental';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
    (v_mod, 'MAPA-001', 'Instrumento vigente v1 com 28 itens', 'feliz', 'alta', 'aprovado', 'api',
     'Garante que o instrumento de referência foi semeado e está vigente.',
     'Migration de fundação aplicada.',
     '[{"ordem":1,"acao":"Consultar mapa_comportamental_instrumentos vigente","resultado_esperado":"versao=1, total_itens=28, vigente=true"}]'::jsonb,
     'Existe exatamente um instrumento vigente v1 com 28 itens.',
     'Cobre RF-016 (versionamento do instrumento).'),
    (v_mod, 'MAPA-002', 'Respostas protegidas por política RESTRICTIVE de perfil', 'feliz', 'critica', 'aprovado', 'api',
     'PERFIL-003: tabela com dado pessoal precisa da política RESTRICTIVE de perfil.',
     'Migration de fundação aplicada.',
     '[{"ordem":1,"acao":"Verificar pg_policies em mapa_comportamental_respostas","resultado_esperado":"existe perfil_restringe_leitura_mapa_comportamental_respostas (RESTRICTIVE)"}]'::jsonb,
     'A política RESTRICTIVE de perfil existe na tabela de respostas.',
     'Cobre RN-003/RN-002 (leitura restrita ao titular/perfil).')
  ON CONFLICT (codigo) DO NOTHING;

  RAISE NOTICE 'OK: módulo QA mapa-comportamental + casos MAPA-001/002 documentados.';
END $doc$;

-- ── Rotina MAPA-001 ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_mapa_001()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_qt int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Consultar instrumento vigente v1 (somente leitura)';
  r.esperado    := 'Um instrumento vigente com versao=1 e total_itens=28';

  SELECT count(*) INTO v_qt
  FROM public.mapa_comportamental_instrumentos
  WHERE versao = 1 AND vigente = true AND total_itens = 28;

  IF v_qt = 1 THEN
    r.situacao := 'passou';
    r.obtido   := 'Instrumento v1 vigente com 28 itens encontrado';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('Encontrados %s instrumentos v1 vigentes com 28 itens (esperado 1)', v_qt);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro';
  r.obtido   := 'A rotina quebrou';
  r.erro_tecnico := SQLERRM;
  RETURN r;
END;
$fn$;

-- ── Rotina MAPA-002 ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_mapa_002()
RETURNS public.qa_retorno
LANGUAGE plpgsql
AS $fn$
DECLARE
  r public.qa_retorno;
  v_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Verificar política RESTRICTIVE de perfil na tabela de respostas';
  r.esperado    := 'perfil_restringe_leitura_mapa_comportamental_respostas existe como RESTRICTIVE';

  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'mapa_comportamental_respostas'
      AND policyname = 'perfil_restringe_leitura_mapa_comportamental_respostas'
      AND permissive = 'RESTRICTIVE'
  ) INTO v_ok;

  IF v_ok THEN
    r.situacao := 'passou';
    r.obtido   := 'Política RESTRICTIVE de perfil presente';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := 'Política RESTRICTIVE de perfil ausente';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro';
  r.obtido   := 'A rotina quebrou';
  r.erro_tecnico := SQLERRM;
  RETURN r;
END;
$fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MAPA-001', 'qa_caso_mapa_001'),
  ('MAPA-002', 'qa_caso_mapa_002')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
