-- ============================================================================
-- SEG-0008 / NAC-002 — o Administrador Master vira PARAMETRO DE TABELA.
--
-- Problema (NAC-002, alta): admin_master_modulos_plano() e
-- admin_master_modulos_faltantes() decidiam quem e o "Administrador Master"
-- COMPARANDO O NOME do perfil com um texto fixo (pa.nome = 'Administrador
-- Master'). Regra de acesso presa no codigo: renomear o perfil na tela mudava
-- o acesso efetivo (a sincronia automatica deixaria de reconhece-lo) sem
-- ninguem perceber; nao se auditava nem se ajustava por cliente. O motor de QA
-- (NAC-002) reprova por essa classe de bug. E a MESMA correcao do SEG-0007.
--
-- Correcao (table-driven): reaproveita a coluna perfis_acesso.modelo_sistema
-- (criada pelo SEG-0007; aqui com ADD COLUMN IF NOT EXISTS para independer da
-- ordem de merge) com um marcador estavel 'admin_master'. As duas funcoes
-- passam a achar o perfil pelo marcador, nao pelo nome exibido.
--
-- Efeito colateral conferido: o acesso efetivo do Administrador Master NAO muda.
-- O backfill marca o perfil que hoje casa pelo nome (um por cliente, respeitando
-- o indice unico parcial do SEG-0007), entao as funcoes devolvem exatamente o
-- MESMO conjunto de antes. Consumidores (admin_master_verbos_faltantes,
-- admin_master_sincronizar, qa_caso_perfil_018/019/020) continuam iguais: nenhum
-- deles compara o nome; todos passam pelas funcoes corrigidas.
--
-- NAC-002 nao precisa de ajuste: ele cata 'pa.nome = <texto>'; a nova forma
-- compara 'pa.modelo_sistema = <chave>', que ele (corretamente) nao acusa.
-- Com o SEG-0007 tratando perfil_modelo_tecnico_sst, nao resta funcao presa ao
-- nome e NAC-002 fica verde.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) MARCADOR DE TABELA (reaproveita a coluna do SEG-0007) --------------------
ALTER TABLE public.perfis_acesso
  ADD COLUMN IF NOT EXISTS modelo_sistema text;

COMMENT ON COLUMN public.perfis_acesso.modelo_sistema IS
  'Marcador do modelo de sistema deste perfil (chave estavel, ex.: tecnico_sst [SEG-0007], admin_master [SEG-0008]). Identifica o modelo por chave, nao pelo nome exibido. NULL = perfil comum. Regra em CLAUDE.md.';

-- 2) SCHEMA PRIVADO backup (idempotente; igual ao SEG-0006, caso ainda nao
--    tenha sido aplicado nesta base). Fora da API: anon/authenticated nao veem.
DO $bkpschema$
BEGIN
  CREATE SCHEMA IF NOT EXISTS backup;
  REVOKE ALL ON SCHEMA backup FROM public;
  REVOKE ALL ON SCHEMA backup FROM anon, authenticated;
  GRANT USAGE, CREATE ON SCHEMA backup TO postgres;
  GRANT USAGE ON SCHEMA backup TO service_role;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SEG-0008: schema backup nao preparado (seguindo): % (%)', SQLERRM, SQLSTATE;
END
$bkpschema$;

-- 3) BACKFILL DO MARCADOR (um por cliente) + copia de seguranca ---------------
-- Marca o perfil Administrador Master que hoje e achado pelo nome. DISTINCT ON
-- (tenant) com desempate pelo em uso (ativo, mais vinculos ativos, perfil comum
-- antes do modelo de sistema, mais antigo): se um cliente tiver mais de um perfil
-- com esse nome, so o em uso recebe o marcador (os outros ficam inertes, com as
-- permissoes que ja tinham; as funcoes nunca removem permissao). A copia das
-- linhas afetadas vai para o schema privado backup. A tabela de backup e criada
-- por EXECUTE (nao aciona o auto-RLS do SQL Editor).
DO $bkp$
BEGIN
  EXECUTE 'CREATE ' || 'TABLE IF NOT EXISTS backup.perfis_modelo_admin_master_20261026 AS '
       || 'SELECT * FROM public.perfis_acesso '
       || 'WHERE nome = ''Administrador Master'' AND modelo_sistema IS NULL';
  -- reexecucao: completa a copia com alvos ainda nao guardados
  EXECUTE 'INSERT INTO backup.perfis_modelo_admin_master_20261026 '
       || 'SELECT p.* FROM public.perfis_acesso p '
       || 'WHERE p.nome = ''Administrador Master'' AND p.modelo_sistema IS NULL '
       || 'AND NOT EXISTS (SELECT 1 FROM backup.perfis_modelo_admin_master_20261026 b WHERE b.id = p.id)';
  EXECUTE 'REVOKE ALL ON TABLE backup.perfis_modelo_admin_master_20261026 FROM anon, authenticated';

  WITH alvo AS MATERIALIZED (
    SELECT DISTINCT ON (pa.tenant_id) pa.id
      FROM public.perfis_acesso pa
     WHERE pa.nome = 'Administrador Master'
       AND pa.modelo_sistema IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.perfis_acesso p2
                        WHERE p2.tenant_id = pa.tenant_id
                          AND p2.modelo_sistema = 'admin_master')
     ORDER BY pa.tenant_id,
              COALESCE(pa.ativo, true) DESC,
              (SELECT count(*) FROM public.usuario_perfil_vinculos v
                WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true) = true) DESC,
              (COALESCE(pa.tipo::text, '') <> 'padrao_sistema') DESC,
              pa.created_at ASC
  )
  UPDATE public.perfis_acesso p
     SET modelo_sistema = 'admin_master'
    FROM alvo a
   WHERE p.id = a.id;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SEG-0008: backfill do marcador nao concluido: % (%)', SQLERRM, SQLSTATE;
END
$bkp$;

-- 4) INTEGRIDADE: um modelo por cliente (mesmo indice do SEG-0007) ------------
DO $idx$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS perfis_acesso_modelo_sistema_uidx
    ON public.perfis_acesso (tenant_id, modelo_sistema)
    WHERE modelo_sistema IS NOT NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'SEG-0008: indice unico do marcador nao criado (duplicados?): % (%)', SQLERRM, SQLSTATE;
END
$idx$;

-- 5) AS FUNCOES LEEM O MARCADOR, NAO O NOME -----------------------------------
--    admin_master_modulos_plano: identica a antes, so a 1a linha do WHERE muda
--    (pa.nome = 'Administrador Master'  ->  pa.modelo_sistema = 'admin_master').
CREATE OR REPLACE FUNCTION public.admin_master_modulos_plano()
RETURNS TABLE(perfil_id uuid, tenant_id uuid, modulo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $amp$
  SELECT pa.id, pa.tenant_id, m.modulo
    FROM public.perfis_acesso pa
    JOIN public.subscriptions s
      ON s.tenant_id = pa.tenant_id AND s.status NOT IN ('paused', 'canceled')
   CROSS JOIN (VALUES
      ('empresa', NULL), ('filiais', NULL), ('departamentos', NULL), ('cargos', NULL),
      ('colaboradores', NULL), ('terceiros', NULL), ('organograma', NULL),
      ('identidade_estrategica', 'mod.estrategia'), ('planejamento_estrategico', 'mod.estrategia'),
      ('metas', 'mod.metas'), ('plano_acao', 'mod.metas'),
      ('onboarding', 'mod.onboarding'), ('contratos_experiencia', 'mod.contratos_exp'),
      ('cultura_celebracoes', 'mod.cultura'), ('feed', 'mod.cultura'),
      ('feedback', 'mod.cultura'), ('ouvidoria', 'mod.cultura'),
      ('bem_estar', 'mod.bem_estar'),
      ('aprendizado', 'mod.trilhas'), ('trilhas', 'mod.trilhas'),
      ('avaliacoes', 'mod.avaliacoes'), ('pdi', 'mod.pdi'),
      ('mapa_comportamental', 'mod.mapa_comportamental'),
      ('ponto', 'mod.ponto'), ('analise_jornada', 'mod.analise_jornada'),
      ('ferias', 'mod.ferias'), ('atestados', 'mod.ferias'),
      ('beneficios', 'mod.beneficios'), ('documentos', 'mod.beneficios'),
      ('hub_contabil', 'mod.beneficios'),
      ('sst', 'mod.nr1'), ('psicossocial', 'mod.psicossocial'),
      ('ergonomia', 'mod.epi_ergo'), ('epi', 'mod.epi_ergo'),
      ('incidentes', 'mod.incidentes'), ('financeiro', 'mod.financeiro'),
      ('marketplace', NULL), ('academia', NULL),
      ('usuarios', NULL), ('perfis_acesso', NULL), ('configuracoes', NULL),
      ('suporte', NULL), ('auditoria', NULL)
   ) AS m(modulo, feature)
   WHERE pa.modelo_sistema = 'admin_master'
     AND (COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
          OR EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                      WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true) = true))
     AND COALESCE(pa.ativo, true) = true
     AND (m.feature IS NULL OR public.tenant_has_feature(pa.tenant_id, m.feature));
$amp$;

--    admin_master_modulos_faltantes: identica a antes, so a 1a linha do WHERE
--    muda; mantem o NOT EXISTS (modulo sem nenhuma permissao ativa).
CREATE OR REPLACE FUNCTION public.admin_master_modulos_faltantes()
RETURNS TABLE(perfil_id uuid, tenant_id uuid, modulo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $amf$
  SELECT pa.id, pa.tenant_id, m.modulo
    FROM public.perfis_acesso pa
    JOIN public.subscriptions s
      ON s.tenant_id = pa.tenant_id AND s.status NOT IN ('paused', 'canceled')
   CROSS JOIN (VALUES
      ('empresa', NULL), ('filiais', NULL), ('departamentos', NULL), ('cargos', NULL),
      ('colaboradores', NULL), ('terceiros', NULL), ('organograma', NULL),
      ('identidade_estrategica', 'mod.estrategia'), ('planejamento_estrategico', 'mod.estrategia'),
      ('metas', 'mod.metas'), ('plano_acao', 'mod.metas'),
      ('onboarding', 'mod.onboarding'), ('contratos_experiencia', 'mod.contratos_exp'),
      ('cultura_celebracoes', 'mod.cultura'), ('feed', 'mod.cultura'),
      ('feedback', 'mod.cultura'), ('ouvidoria', 'mod.cultura'),
      ('bem_estar', 'mod.bem_estar'),
      ('aprendizado', 'mod.trilhas'), ('trilhas', 'mod.trilhas'),
      ('avaliacoes', 'mod.avaliacoes'), ('pdi', 'mod.pdi'),
      ('mapa_comportamental', 'mod.mapa_comportamental'),
      ('ponto', 'mod.ponto'), ('analise_jornada', 'mod.analise_jornada'),
      ('ferias', 'mod.ferias'), ('atestados', 'mod.ferias'),
      ('beneficios', 'mod.beneficios'), ('documentos', 'mod.beneficios'),
      ('hub_contabil', 'mod.beneficios'),
      ('sst', 'mod.nr1'), ('psicossocial', 'mod.psicossocial'),
      ('ergonomia', 'mod.epi_ergo'), ('epi', 'mod.epi_ergo'),
      ('incidentes', 'mod.incidentes'), ('financeiro', 'mod.financeiro'),
      ('marketplace', NULL), ('academia', NULL),
      ('usuarios', NULL), ('perfis_acesso', NULL), ('configuracoes', NULL),
      ('suporte', NULL), ('auditoria', NULL)
   ) AS m(modulo, feature)
   WHERE pa.modelo_sistema = 'admin_master'
     AND (COALESCE(pa.tipo::text, '') <> 'padrao_sistema'
          OR EXISTS (SELECT 1 FROM public.usuario_perfil_vinculos v
                      WHERE v.perfil_id = pa.id AND COALESCE(v.ativo, true) = true))
     AND COALESCE(pa.ativo, true) = true
     AND (m.feature IS NULL OR public.tenant_has_feature(pa.tenant_id, m.feature))
     AND NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = pa.id AND x.modulo = m.modulo
                        AND COALESCE(x.ativo, true) = true);
$amf$;

REVOKE ALL ON FUNCTION public.admin_master_modulos_plano() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_master_modulos_faltantes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_master_modulos_plano() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_master_modulos_faltantes() TO service_role;

-- 6) NOVA GUARDA (PERFIL-043): o Administrador Master e achado por marcador -----
-- Auditoria de estrutura, somente leitura. Fecha SEG-0008: garante que as duas
-- funcoes leem o marcador e nao voltaram a decidir pelo nome (texto fixo).
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $p043$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_tem_coluna boolean;
  v_falhas text[] := ARRAY[]::text[];
  fn text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): o Administrador Master e achado por marcador de tabela, nao pelo nome';
  r.esperado    := 'Coluna perfis_acesso.modelo_sistema existe; admin_master_modulos_plano e admin_master_modulos_faltantes leem o marcador e nao comparam o nome do perfil com texto fixo';

  v_tem_coluna := (SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'perfis_acesso'
       AND column_name = 'modelo_sistema'
  ));
  IF NOT v_tem_coluna THEN
    v_falhas := v_falhas || 'coluna perfis_acesso.modelo_sistema ausente'::text;
  END IF;

  FOREACH fn IN ARRAY ARRAY['admin_master_modulos_plano', 'admin_master_modulos_faltantes'] LOOP
    IF to_regprocedure('public.' || fn || '()') IS NULL THEN
      v_falhas := v_falhas || (fn || ' ausente')::text;
    ELSE
      v_def := COALESCE(pg_get_functiondef(('public.' || fn || '()')::regprocedure), '');
      IF position('modelo_sistema' IN v_def) = 0 THEN
        v_falhas := v_falhas || (fn || ' nao le o marcador modelo_sistema')::text;
      END IF;
      IF v_def ~* '(pa|perfis_acesso|perfil)\.nome\s*(=|<>|ilike|like)\s*''' THEN
        v_falhas := v_falhas || (fn || ' ainda decide pelo nome do perfil (texto fixo)')::text;
      END IF;
    END IF;
  END LOOP;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'O Administrador Master e parametro de tabela (modelo_sistema = admin_master); renomear o perfil na tela nao muda mais o acesso.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $p043$;

-- 7) DOCUMENTACAO DOS CASOS (qa_casos_teste / qa_implementacoes) ---------------
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; casos SEG-0008 nao documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; casos SEG-0008 nao documentados.';
    RETURN;
  END IF;

  -- PERFIL-018/019/020: o Administrador Master passa a ser identificado por marcador.
  UPDATE public.qa_casos_teste
     SET pre_condicoes = 'Perfil Administrador Master (identificado pelo marcador de tabela modelo_sistema = admin_master, inclusive o perfil de sistema com usuario vinculado ativo) em cliente com assinatura ativa.'
   WHERE codigo IN ('PERFIL-018', 'PERFIL-019', 'PERFIL-020');

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-043', 'O Administrador Master e achado por marcador de tabela, nao pelo nome',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46',
   'SEG-0008/NAC-002: as funcoes admin_master_modulos_plano e admin_master_modulos_faltantes comparavam o nome do perfil com um texto fixo (regra de acesso presa no codigo: renomear o perfil na tela mudava o acesso e a sincronia deixava de reconhece-lo). A correcao marca o perfil por uma coluna estavel (modelo_sistema = admin_master) e as funcoes passam a ler o marcador. Audita que a coluna existe, que as duas funcoes leem o marcador e que nao decidem mais pelo nome.',
   'Migration SEG-0008 aplicada (coluna modelo_sistema reaproveitada e as duas funcoes ajustadas).',
   '[{"ordem":1,"acao":"Conferir a coluna perfis_acesso.modelo_sistema e a definicao de admin_master_modulos_plano e admin_master_modulos_faltantes","resultado_esperado":"Coluna presente; as funcoes leem modelo_sistema e nao comparam o nome do perfil com texto fixo"}]',
   'Administrador Master identificado por parametro de tabela; nenhuma decisao presa ao nome.')
  ON CONFLICT (codigo) DO UPDATE
    SET titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
        passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
        prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-043', 'qa_caso_perfil_043', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao SEG-0008 nao registrada: %', SQLERRM;
END $doc$;
