-- ============================================================================
-- SEG-0007 / NAC-002 — o modelo do Tecnico de SST vira PARAMETRO DE TABELA.
--
-- Problema (NAC-002, critico): perfil_modelo_tecnico_sst decidia qual perfil e o
-- "modelo do Tecnico de Seguranca" COMPARANDO O NOME do perfil com um texto fixo
-- (pa.nome = 'Tecnico de Seguranca (padrao)'). Regra de acesso presa no codigo:
-- renomear o perfil na tela mudava o acesso sem ninguem perceber (e a funcao
-- passava a criar um perfil duplicado), nao se auditava e nao se ajustava por
-- cliente. O motor de QA reprova por essa classe de bug.
--
-- Correcao (table-driven): o perfil ganha um MARCADOR estavel, a coluna
-- perfis_acesso.modelo_sistema (chave de maquina, ex.: 'tecnico_sst'),
-- independente do nome exibido. A funcao passa a achar o modelo pelo marcador.
-- Renomear o perfil na tela deixa de mudar o acesso.
--
-- Efeito colateral conferido: o acesso efetivo dos tecnicos NAO muda. O backfill
-- marca os perfis que hoje casam pelo nome (um por cliente), entao a funcao
-- devolve exatamente o MESMO perfil de antes. Consumidores (perfil_modelo_para_tipo,
-- o gatilho de cadastro, o backfill de tecnicos) continuam iguais.
--
-- NAC-002 nao precisa de ajuste: ele cata 'pa.nome = <texto>'; a nova forma
-- compara 'pa.modelo_sistema = <chave>', que ele (corretamente) nao acusa.
-- ============================================================================

-- 1) MARCADOR DE TABELA -------------------------------------------------------
ALTER TABLE public.perfis_acesso
  ADD COLUMN IF NOT EXISTS modelo_sistema text;

COMMENT ON COLUMN public.perfis_acesso.modelo_sistema IS
  'SEG-0007: marcador do modelo de sistema deste perfil (ex.: tecnico_sst). Identifica o modelo por chave estavel, nao pelo nome exibido. NULL = perfil comum. Regra em CLAUDE.md.';

-- 2) BACKFILL DO MARCADOR (um por cliente) + copia de seguranca ---------------
-- Marca o perfil que hoje e achado pelo nome. DISTINCT ON (tenant) com desempate
-- pelo mais usado por tecnicos ativos e depois o mais antigo: se um cliente ja
-- tinha duplicado pelo bug, so o em uso recebe o marcador (o outro fica inerte).
-- A copia das linhas afetadas vai para o schema privado backup (fora da API).
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.perfis_modelo_sst_20261026 AS '
       || 'SELECT * FROM public.perfis_acesso '
       || 'WHERE nome = ''Técnico de Segurança (padrão)'' AND tipo = ''padrao_sistema'' '
       || 'AND modelo_sistema IS NULL';
  -- reexecucao: completa a copia com alvos ainda nao guardados
  EXECUTE 'INSERT INTO backup.perfis_modelo_sst_20261026 '
       || 'SELECT p.* FROM public.perfis_acesso p '
       || 'WHERE p.nome = ''Técnico de Segurança (padrão)'' AND p.tipo = ''padrao_sistema'' '
       || 'AND p.modelo_sistema IS NULL '
       || 'AND NOT EXISTS (SELECT 1 FROM backup.perfis_modelo_sst_20261026 b WHERE b.id = p.id)';

  WITH alvo AS MATERIALIZED (
    SELECT DISTINCT ON (pa.tenant_id) pa.id
      FROM public.perfis_acesso pa
     WHERE pa.nome = 'Técnico de Segurança (padrão)'
       AND pa.tipo = 'padrao_sistema'
       AND pa.modelo_sistema IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.perfis_acesso p2
                        WHERE p2.tenant_id = pa.tenant_id
                          AND p2.modelo_sistema = 'tecnico_sst')
     ORDER BY pa.tenant_id,
              (SELECT count(*) FROM public.usuario_perfil_vinculos v
                WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true) = true) DESC,
              pa.created_at ASC
  )
  UPDATE public.perfis_acesso p
     SET modelo_sistema = 'tecnico_sst'
    FROM alvo a
   WHERE p.id = a.id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SEG-0007: backfill do marcador nao concluido: % (%)', SQLERRM, SQLSTATE;
END
$bkp$;

-- 3) INTEGRIDADE: um modelo por cliente (indice unico parcial) ----------------
DO $idx$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS perfis_acesso_modelo_sistema_uidx
    ON public.perfis_acesso (tenant_id, modelo_sistema)
    WHERE modelo_sistema IS NOT NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SEG-0007: indice unico do marcador nao criado (duplicados?): % (%)', SQLERRM, SQLSTATE;
END
$idx$;

-- 4) A FUNCAO LE O MARCADOR, NAO O NOME ---------------------------------------
CREATE OR REPLACE FUNCTION public.perfil_modelo_tecnico_sst(p_tenant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $tsst$
DECLARE
  v_id uuid;
  m text;
  a text;
BEGIN
  IF p_tenant_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- SEG-0007: o modelo e achado pelo MARCADOR de tabela (modelo_sistema), nao
  -- pelo nome exibido. Renomear o perfil na tela deixou de mudar o acesso.
  v_id := (SELECT pa.id FROM public.perfis_acesso pa
            WHERE pa.tenant_id = p_tenant_id
              AND pa.modelo_sistema = 'tecnico_sst'
            LIMIT 1);
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.perfis_acesso
    (tenant_id, nome, descricao, tipo, ativo, permite_acumulo, cor, icone,
     criado_por_nome, pode_ver_salario, modelo_sistema)
  VALUES
    (p_tenant_id, 'Técnico de Segurança (padrão)',
     'Modelo do tipo Técnico de Segurança: empresa inteira em Compliance SST, Ergonomia, EPIs, Incidentes e Documentos (visualizar, criar e editar); no resto, só os próprios dados. Não vê salário. Editável em Perfis de acesso.',
     'padrao_sistema', true, true, '#0EA5E9', 'shield', 'Sistema (modelo)', false, 'tecnico_sst');

  -- o nome e apenas o rotulo inicial; a identidade e o marcador acima
  v_id := (SELECT pa.id FROM public.perfis_acesso pa
            WHERE pa.tenant_id = p_tenant_id
              AND pa.modelo_sistema = 'tecnico_sst'
            LIMIT 1);

  FOREACH m IN ARRAY ARRAY['sst', 'ergonomia', 'epi', 'incidentes', 'documentos'] LOOP
    FOREACH a IN ARRAY ARRAY['visualizar', 'criar', 'editar'] LOOP
      INSERT INTO public.perfil_permissoes
        (perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, observacao)
      VALUES
        (v_id, p_tenant_id, m, 'geral', a::public.perfil_acao, 'empresa_inteira', true,
         'Modelo do Técnico de Segurança (gerado pelo sistema)');
    END LOOP;
  END LOOP;

  FOREACH m IN ARRAY ARRAY['colaboradores', 'atestados', 'financeiro', 'bem_estar',
                           'trilhas', 'pdi', 'feedback'] LOOP
    INSERT INTO public.perfil_permissoes
      (perfil_id, tenant_id, modulo, recurso, acao, escopo, ativo, observacao)
    VALUES
      (v_id, p_tenant_id, m, 'geral', 'visualizar', 'proprio_usuario', true,
       'Autosserviço do modelo do Técnico de Segurança');
  END LOOP;

  RETURN v_id;
END;
$tsst$;

REVOKE EXECUTE ON FUNCTION public.perfil_modelo_tecnico_sst(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_modelo_tecnico_sst(uuid) TO authenticated, service_role;

-- 5) GUARDA DE REGRESSAO QUE CASAVA PELO NOME: passa a casar pelo marcador -----
-- PERFIL-016 continua contando tecnicos ativos sem perfil escolhido e fora do
-- modelo de SST, mas identifica o modelo pelo marcador (robusto a renomear).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_016()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $p016$
DECLARE
  r public.qa_retorno;
  v_qtd bigint;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): tecnicos de seguranca ativos sem perfil escolhido e fora do modelo de SST';
  r.esperado    := 'Todo tecnico de seguranca ativo sem perfil escolhido tem o modelo marcado modelo_sistema = tecnico_sst';

  v_qtd := (
    SELECT count(*)
      FROM public.usuarios_base ub
     WHERE ub.auth_user_id IS NOT NULL
       AND ub.tenant_id IS NOT NULL
       AND ub.status::text = 'ativo'
       AND ub.tipo_usuario::text = 'tecnico_seguranca'
       AND NOT EXISTS (SELECT 1 FROM public.user_roles ur
                        WHERE ur.user_id = ub.auth_user_id
                          AND ur.role::text IN ('owner', 'manager', 'admin'))
       AND NOT public.is_superadmin(ub.auth_user_id)
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND (v.expira_em IS NULL OR v.expira_em > now())
                AND COALESCE(pa.ativo, true) = true
                AND (pa.expira_em IS NULL OR pa.expira_em > now())
                AND COALESCE(pa.tipo::text, '') <> 'padrao_sistema')
       AND NOT EXISTS (
             SELECT 1 FROM public.usuario_perfil_vinculos v
               JOIN public.perfis_acesso pa ON pa.id = v.perfil_id
              WHERE v.usuario_id = ub.id
                AND COALESCE(v.ativo, true) = true
                AND pa.modelo_sistema = 'tecnico_sst')
  );

  IF v_qtd = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Todo técnico de segurança ativo sem perfil escolhido está no modelo de SST.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := v_qtd::text || ' técnico(s) de segurança ativo(s) fora do modelo de SST (rodar o backfill de técnicos).';
    r.detalhe  := jsonb_build_object('fora_do_modelo', v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $p016$;

-- 6) NOVA GUARDA (PERFIL-042): o modelo e achado por marcador, nao pelo nome ----
-- Auditoria de estrutura, somente leitura. Fecha SEG-0007: garante que a funcao
-- le o marcador e nao voltou a decidir pelo nome (texto fixo).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $p042$
DECLARE
  r public.qa_retorno;
  v_proc regprocedure;
  v_def text;
  v_tem_coluna boolean;
  v_falhas text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): o modelo do Tecnico de SST e achado por marcador de tabela, nao pelo nome';
  r.esperado    := 'Coluna perfis_acesso.modelo_sistema existe; perfil_modelo_tecnico_sst le o marcador e nao compara o nome do perfil com texto fixo';

  v_tem_coluna := (SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'perfis_acesso'
       AND column_name = 'modelo_sistema'
  ));
  IF NOT v_tem_coluna THEN
    v_falhas := v_falhas || 'coluna perfis_acesso.modelo_sistema ausente'::text;
  END IF;

  v_proc := to_regprocedure('public.perfil_modelo_tecnico_sst(uuid)');
  IF v_proc IS NULL THEN
    v_falhas := v_falhas || 'função perfil_modelo_tecnico_sst ausente'::text;
  ELSE
    v_def := COALESCE(pg_get_functiondef(v_proc), '');
    IF position('modelo_sistema' IN v_def) = 0 THEN
      v_falhas := v_falhas || 'perfil_modelo_tecnico_sst não lê o marcador modelo_sistema'::text;
    END IF;
    IF v_def ~* '(pa|perfis_acesso|perfil)\.nome\s*(=|<>|ilike|like)\s*''' THEN
      v_falhas := v_falhas || 'perfil_modelo_tecnico_sst ainda decide pelo nome do perfil (texto fixo)'::text;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'O modelo do Técnico de SST é parâmetro de tabela (modelo_sistema = tecnico_sst); renomear o perfil na tela não muda mais o acesso.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $p042$;

-- 7) DOCUMENTACAO DOS CASOS (qa_casos_teste / qa_implementacoes) ---------------
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos SEG-0007 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos SEG-0007 nao documentados.';
    RETURN;
  END IF;

  -- PERFIL-016: atualiza o objetivo para refletir o marcador
  UPDATE public.qa_casos_teste
     SET objetivo = 'Técnicos de segurança criados antes da correção do cadastro nasceram com o Colaborador (padrão) e ficaram sem tela de trabalho. Garante que todo técnico ativo sem perfil escolhido (e sem papel de dono, manager ou admin) está no modelo de SST, identificado pelo marcador de tabela modelo_sistema = tecnico_sst (não pelo nome do perfil).',
         resultado_esperado = 'Nenhum técnico fora do modelo de SST (marcado por modelo_sistema).'
   WHERE codigo = 'PERFIL-016';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-042', 'O modelo do Técnico de SST é achado por marcador de tabela, não pelo nome',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'SEG-0007/NAC-002: a função que escolhe o modelo do Técnico de Segurança comparava o nome do perfil com um texto fixo (regra de acesso presa no código: renomear o perfil na tela mudava o acesso e criava duplicado). A correção marca o perfil por uma coluna estável (modelo_sistema = tecnico_sst) e a função passa a ler o marcador. Audita que a coluna existe, que a função lê o marcador e que não decide mais pelo nome.',
   'Migration SEG-0007 aplicada (coluna modelo_sistema e função ajustada).',
   '[{"ordem":1,"acao":"Conferir a coluna perfis_acesso.modelo_sistema e a definição de perfil_modelo_tecnico_sst","resultado_esperado":"Coluna presente; a função lê modelo_sistema e não compara o nome do perfil com texto fixo"}]',
   'Modelo identificado por parâmetro de tabela; nenhuma decisão presa ao nome.')
  ON CONFLICT (codigo) DO UPDATE
    SET titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
        passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
        prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-016', 'qa_caso_perfil_016', true),
      ('PERFIL-042', 'qa_caso_perfil_042', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao SEG-0007 nao registrada: %', SQLERRM;
END $doc$;
