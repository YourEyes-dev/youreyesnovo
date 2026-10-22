-- ============================================================================
-- Perfil de acesso: o que aparece na TELA INICIAL (Início) de cada perfil
--
-- Achado de campo (10/2026): a tela Início mostrava para TODO usuário os quatro
-- blocos do painel (visão dos pilares, indicadores, pendências e alertas), com
-- números da empresa e alertas sensíveis, e o perfil de acesso não tinha como
-- esconder isso.
--
-- Esta entrega cria a configuração por perfil:
--   perfis_acesso.inicio_blocos text[]  (NULL = painel completo, como era antes)
-- Valores aceitos: 'pilares', 'indicadores', 'pendencias', 'alertas'.
-- Lista vazia = a pessoa vê só a saudação e os atalhos pessoais.
--
-- NULL é o padrão de propósito: nenhum perfil existente muda de comportamento.
-- Quem quiser restringir edita o perfil (Usuários > Perfis de Acesso).
-- Só o que aparece na tela é afetado; os dados continuam protegidos pela RLS
-- (perfil_restringe_leitura_*) exatamente como antes.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.perfis_acesso
  ADD COLUMN IF NOT EXISTS inicio_blocos text[];

COMMENT ON COLUMN public.perfis_acesso.inicio_blocos IS
  'Blocos da tela Início visíveis para o perfil: pilares, indicadores, pendencias, alertas. NULL = todos (legado). Vazio = só saudação e atalhos.';

DO $chk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'perfis_acesso_inicio_blocos_validos'
       AND conrelid = 'public.perfis_acesso'::regclass
  ) THEN
    ALTER TABLE public.perfis_acesso
      ADD CONSTRAINT perfis_acesso_inicio_blocos_validos
      CHECK (inicio_blocos IS NULL
             OR inicio_blocos <@ ARRAY['pilares','indicadores','pendencias','alertas']::text[]);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Constraint inicio_blocos nao criada: %', SQLERRM;
END $chk$;

-- QA — PERFIL-021 (nivel api, somente leitura): a coluna existe, aceita NULL e valida os blocos.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_tipo text;
  v_nulo text;
  v_chk boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): perfis_acesso.inicio_blocos existe, aceita NULL (painel completo) e valida os blocos';
  r.esperado    := 'Coluna text[] anulavel com a trava dos quatro blocos validos';

  v_tipo := (SELECT data_type || ':' || udt_name FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'perfis_acesso' AND column_name = 'inicio_blocos');
  v_nulo := (SELECT is_nullable FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'perfis_acesso' AND column_name = 'inicio_blocos');
  IF v_tipo IS NULL THEN
    v_falhas := v_falhas || 'coluna inicio_blocos ausente'::text;
  ELSE
    IF v_tipo <> 'ARRAY:_text' THEN
      v_falhas := v_falhas || ('tipo inesperado: ' || v_tipo);
    END IF;
    IF v_nulo <> 'YES' THEN
      v_falhas := v_falhas || 'coluna nao aceita NULL (NULL e o painel completo, legado)'::text;
    END IF;
  END IF;

  v_chk := EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'perfis_acesso_inicio_blocos_validos'
                      AND conrelid = 'public.perfis_acesso'::regclass);
  IF NOT v_chk THEN
    v_falhas := v_falhas || 'sem a trava perfis_acesso_inicio_blocos_validos'::text;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'inicio_blocos presente, anulavel e validada';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $qa21$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; PERFIL-021 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-021 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-021', 'Perfil de acesso define quais blocos da tela Início a pessoa enxerga',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46 (acesso conforme a funcao)',
   'A tela Início mostrava pilares, indicadores, pendencias e alertas da empresa para qualquer usuario. O perfil agora escolhe os blocos (perfis_acesso.inicio_blocos); NULL mantem o painel completo dos perfis antigos e lista vazia deixa so saudacao e atalhos. Conferencia de tela: editar o perfil, desmarcar blocos em Informacoes gerais > Tela inicial e entrar com um usuario desse perfil. Tambem garante que o cabecalho mostra o nome do perfil de acesso (e nao o papel tecnico Gestor).',
   'Entrega da tela inicial por perfil aplicada.',
   '[{"ordem":1,"acao":"Conferir a coluna inicio_blocos (text[], anulavel) e a trava dos quatro blocos validos","resultado_esperado":"Coluna e trava presentes"},
     {"ordem":2,"acao":"Na tela: perfil com todos os blocos desmarcados, entrar com um usuario dele e abrir Inicio","resultado_esperado":"So saudacao e atalhos; sem numeros nem alertas da empresa. O cabecalho mostra o nome do perfil"}]',
   'Coluna e trava presentes; a tela Início respeita os blocos do perfil.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-021', 'qa_caso_perfil_021', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-021 nao registrada: %', SQLERRM;
END $qa21$;

DO $roda$
BEGIN
  PERFORM public.qa_rodar_bateria('manual', 'seguranca-acesso/perfis');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bateria nao rodou agora (%). A rotina fica registrada e entra na proxima execucao agendada.', SQLERRM;
END $roda$;
