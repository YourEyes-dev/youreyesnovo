-- =====================================================================
-- MIGRATION — PREM-0002 parte 2, FASE 1
-- Psicossocial: persistir EVIDENCIA por dimensao (13 fatores do Guia MTE)
-- Equivalente 1:1 ao script de entrega
-- docs/script_psicossocial_evidencias_fase1.sql (mesmo corpo). Esta migration
-- e o que a esteira aplica no STAGING via db push; o script de entrega e o
-- que vai, a mao, para homologacao e depois producao.
--
-- Fundamentacao fechada: Guia MTE 2025 + ISO 45003 + NR-1. Ancora = os 13
-- fatores de src/data/catalogoRiscosPsicossociais.ts. Dimensao = fator (13),
-- rollup para 5 macro-categorias. Naturezas: ATUACAO (prova de cuidado) e
-- CONTRAPROVA (indicador que corrobora/contradiz). SEM pesos no veredito.
--
-- Idempotente; tabelas novas por EXECUTE (sem a pegadinha do auto-RLS do
-- editor); funcoes sem SELECT INTO; REVOKE EXECUTE FROM PUBLIC em toda funcao.
-- =====================================================================
SET lock_timeout = '10s';

-- =====================================================================
-- 1) psicossocial_evidencias: colunas de dimensao/natureza/sentido/origem
-- =====================================================================
ALTER TABLE public.psicossocial_evidencias
  ADD COLUMN IF NOT EXISTS fator_id            text,
  ADD COLUMN IF NOT EXISTS dimensao_categoria  text,
  ADD COLUMN IF NOT EXISTS natureza            text,
  ADD COLUMN IF NOT EXISTS sentido             text,
  ADD COLUMN IF NOT EXISTS origem_tabela       text,
  ADD COLUMN IF NOT EXISTS origem_id           uuid;

DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'psicossocial_evidencias_natureza_chk') THEN
    ALTER TABLE public.psicossocial_evidencias
      ADD CONSTRAINT psicossocial_evidencias_natureza_chk
      CHECK (natureza IS NULL OR natureza IN ('atuacao','contraprova'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'psicossocial_evidencias_sentido_chk') THEN
    ALTER TABLE public.psicossocial_evidencias
      ADD CONSTRAINT psicossocial_evidencias_sentido_chk
      CHECK (sentido IS NULL OR sentido IN ('comprova','corrobora','contradiz','neutro'));
  END IF;
END
$chk$;

-- Indice de leitura por dimensao/natureza
CREATE INDEX IF NOT EXISTS idx_psico_evid_tenant_camp_fator_nat
  ON public.psicossocial_evidencias (tenant_id, campanha_id, fator_id, natureza);

-- Chave natural para UPSERT idempotente (origem_id sempre preenchido pelas RPCs:
-- id do registro de origem na atuacao; uuid deterministico no indicador agregado)
CREATE UNIQUE INDEX IF NOT EXISTS uq_psico_evid_origem
  ON public.psicossocial_evidencias (tenant_id, campanha_id, tipo_modulo, indicador, origem_id);

-- =====================================================================
-- 2) Tabelas de referencia (criadas por EXECUTE p/ evitar o auto-RLS do editor)
-- =====================================================================
DO $mk$
BEGIN
  IF to_regclass('public.psicossocial_fatores_catalogo') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.psicossocial_fatores_catalogo (
      fator_id          text PRIMARY KEY,
      nome              text NOT NULL,
      categoria         text NOT NULL,
      categoria_label   text NOT NULL,
      severidade_padrao int  NOT NULL,
      aliases           text[] NOT NULL DEFAULT ''{}'',
      ordem             int  NOT NULL DEFAULT 0
    )';
  END IF;

  IF to_regclass('public.psicossocial_evidencia_mapa') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.psicossocial_evidencia_mapa (
      id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      tipo_modulo   text NOT NULL,
      indicador     text NOT NULL,
      fator_id      text NOT NULL,
      natureza      text NOT NULL CHECK (natureza IN (''atuacao'',''contraprova'')),
      regra_sentido text NOT NULL DEFAULT ''comprova_cuidado'',
      peso          numeric NOT NULL DEFAULT 1.0,
      ativo         boolean NOT NULL DEFAULT true,
      observacao    text,
      created_at    timestamptz NOT NULL DEFAULT now()
    )';
  END IF;
END
$mk$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_psico_evid_mapa
  ON public.psicossocial_evidencia_mapa (tipo_modulo, fator_id, natureza);

-- Dados de referencia globais (metodologia, nao dado de tenant): leitura p/ autenticados
ALTER TABLE public.psicossocial_fatores_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.psicossocial_evidencia_mapa  ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='psicossocial_fatores_catalogo' AND policyname='psico_fatores_catalogo_select') THEN
    CREATE POLICY psico_fatores_catalogo_select ON public.psicossocial_fatores_catalogo FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='psicossocial_evidencia_mapa' AND policyname='psico_evidencia_mapa_select') THEN
    CREATE POLICY psico_evidencia_mapa_select ON public.psicossocial_evidencia_mapa FOR SELECT TO authenticated USING (true);
  END IF;
END
$pol$;

-- =====================================================================
-- 3) SEED — os 13 fatores (espelho 1:1 de catalogoRiscosPsicossociais.ts)
-- =====================================================================
INSERT INTO public.psicossocial_fatores_catalogo (fator_id, nome, categoria, categoria_label, severidade_padrao, aliases, ordem) VALUES
 ('excesso-demandas','Excesso de demandas (sobrecarga)','demandas','Demandas do Trabalho',4,
   ARRAY['Sobrecarga Quantitativa','Demandas Quantitativas','Demanda Quantitativa','Sobrecarga de Trabalho','Ritmo de Trabalho','Pressao por Tempo','Sobrecarga Cognitiva','Demandas Cognitivas','Demanda Cognitiva','Carga Mental','Atencao Constante','Demanda Emocional','Demandas Emocionais','Trabalho Emocional','Esgotamento Empatico','Demandas no Trabalho','Demanda','Organizacao do Trabalho','Sofrimento Patogenico','Danos Relacionados ao Trabalho','Demandas Quantitativas e Ritmo','Burnout','Esgotamento','Sinais Precoces','Recuperacao e Equilibrio','Equilibrio Trabalho-Vida','Conciliacao Trabalho-Vida'],1),
 ('baixa-demanda','Baixa demanda de trabalho (subcarga)','demandas','Demandas do Trabalho',2,
   ARRAY['Subcarga','Boreout','Monotonia','Sentido do Trabalho','Proposito'],2),
 ('baixo-controle','Baixo controle no trabalho / Falta de autonomia','organizacao','Organizacao e Conteudo',3,
   ARRAY['Baixa Autonomia / Controle','Autonomia e Controle','Autonomia','Influencia e Controle','Influencia e Desenvolvimento','Influencia','Controle','Margem de Decisao'],3),
 ('baixa-clareza-papel','Baixa clareza de papel/funcao','organizacao','Organizacao e Conteudo',3,
   ARRAY['Clareza de Papeis','Clareza de Funcao','Definicao de Papeis','Conflito de Papeis','Exigencias Contraditorias','Ambiguidade de Papeis','Funcao','Papel na Organizacao'],4),
 ('ma-gestao-mudancas','Ma gestao de mudancas organizacionais','organizacao','Organizacao e Conteudo',3,
   ARRAY['Previsibilidade','Gestao de Mudancas','Mudancas Organizacionais','Inseguranca no Trabalho','Inseguranca','Estabilidade'],5),
 ('falta-suporte','Falta de suporte no trabalho','relacoes','Relacoes Sociais e Lideranca',3,
   ARRAY['Suporte da Lideranca','Suporte do Gestor','Lideranca','Suporte dos Pares','Suporte dos Colegas','Suporte Social','Apoio Social','Estilo de Gestao'],6),
 ('mas-relacoes','Mas relacoes no ambiente de trabalho','relacoes','Relacoes Sociais e Lideranca',3,
   ARRAY['Relacionamentos','Relacionamentos e Suporte','Qualidade das Relacoes','Clima de Equipe','Conflitos Interpessoais','Lacos Sociais','Relacoes Socioprofissionais'],7),
 ('baixa-justica','Baixa justica organizacional','relacoes','Relacoes Sociais e Lideranca',3,
   ARRAY['Justica Organizacional','Equidade','Imparcialidade'],8),
 ('baixas-recompensas','Baixas recompensas e reconhecimento','relacoes','Relacoes Sociais e Lideranca',3,
   ARRAY['Reconhecimento','Reconhecimento e Justica','Reconhecimento e Recompensas','Recompensa','Recompensas','Esforco-Recompensa','Satisfacao no Trabalho'],9),
 ('assedio','Assedio de qualquer natureza','relacoes','Relacoes Sociais e Lideranca',4,
   ARRAY['Assedio','Assedio Moral','Assedio e Comportamentos Ofensivos','Comportamentos Ofensivos','Assedio Sexual','Hostilidade','Discriminacao','Seguranca Psicologica'],10),
 ('trabalho-remoto-isolado','Trabalho remoto e isolado','interface','Interface Trabalho-Individuo',3,
   ARRAY['Trabalho Remoto','Home Office','Trabalho Isolado','Isolamento','Teletrabalho','Trabalho a Distancia'],11),
 ('dificil-comunicacao','Trabalho em condicoes de dificil comunicacao','interface','Interface Trabalho-Individuo',2,
   ARRAY['Comunicacao Deficiente','Barreiras de Comunicacao','Comunicacao Organizacional'],12),
 ('eventos-violentos','Eventos violentos ou traumaticos','manifestacoes','Manifestacoes e Desfechos',5,
   ARRAY['Violencia','Eventos Traumaticos','Ameacas e Violencia','Ameacas','Trauma','TEPT','Agressoes'],13)
ON CONFLICT (fator_id) DO UPDATE
  SET nome=EXCLUDED.nome, categoria=EXCLUDED.categoria, categoria_label=EXCLUDED.categoria_label,
      severidade_padrao=EXCLUDED.severidade_padrao, aliases=EXCLUDED.aliases, ordem=EXCLUDED.ordem;

-- =====================================================================
-- 4) SEED — mapa modulo -> fator -> natureza (metodologia fechada)
--    indicador: rotulo canonico do modulo; regra_sentido: nome da regra;
--    peso: so metadado (o veredito por dimensao NAO usa peso).
-- =====================================================================
INSERT INTO public.psicossocial_evidencia_mapa (tipo_modulo, indicador, fator_id, natureza, regra_sentido, peso, observacao) VALUES
 -- treino -> atuacao
 ('treino','treinamento','falta-suporte','atuacao','comprova_cuidado',1.0,'Capacitacao/lideranca fortalece suporte'),
 ('treino','treinamento','assedio','atuacao','comprova_cuidado',1.0,'Treino de prevencao ao assedio (Lei 14.457)'),
 ('treino','treinamento','mas-relacoes','atuacao','comprova_cuidado',1.0,'Treino de convivencia/comunicacao'),
 ('treino','treinamento','baixa-justica','atuacao','comprova_cuidado',1.0,'Treino de criterios/decisoes justas'),
 -- feedback -> atuacao + contraprova
 ('feedback','feedback','baixas-recompensas','atuacao','comprova_cuidado',1.0,'Reconhecimento via feedback'),
 ('feedback','feedback','falta-suporte','atuacao','comprova_cuidado',1.0,'Suporte via feedback'),
 ('feedback','feedback','baixa-clareza-papel','atuacao','comprova_cuidado',1.0,'Alinhamento de papel via feedback'),
 ('feedback','feedback','baixas-recompensas','contraprova','alinhamento_corrobora',1.0,'Muito alinhamento x pouco reconhecimento corrobora'),
 ('feedback','feedback','falta-suporte','contraprova','alinhamento_corrobora',1.0,NULL),
 ('feedback','feedback','baixa-clareza-papel','contraprova','alinhamento_corrobora',1.0,NULL),
 -- ouvidoria -> atuacao + contraprova
 ('ouvidoria','ouvidoria','assedio','atuacao','comprova_cuidado',1.0,'Canal tratado = cuidado'),
 ('ouvidoria','ouvidoria','baixa-justica','atuacao','comprova_cuidado',1.0,NULL),
 ('ouvidoria','ouvidoria','eventos-violentos','atuacao','comprova_cuidado',1.0,NULL),
 ('ouvidoria','ouvidoria','assedio','contraprova','denuncia_corrobora',1.0,'Denuncias corroboram risco'),
 ('ouvidoria','ouvidoria','baixa-justica','contraprova','denuncia_corrobora',1.0,NULL),
 ('ouvidoria','ouvidoria','eventos-violentos','contraprova','denuncia_corrobora',1.0,NULL),
 -- ergonomia -> atuacao + contraprova
 ('ergonomia','ergonomia','excesso-demandas','atuacao','comprova_cuidado',1.0,'Acao ergonomica (NR-17 org. do trabalho)'),
 ('ergonomia','ergonomia','baixo-controle','atuacao','comprova_cuidado',1.0,NULL),
 ('ergonomia','ergonomia','excesso-demandas','contraprova','risco_alto_corrobora',1.0,'Risco ergonomico alto corrobora sobrecarga'),
 ('ergonomia','ergonomia','baixo-controle','contraprova','risco_alto_corrobora',1.0,NULL),
 -- metas -> atuacao
 ('metas','meta','excesso-demandas','atuacao','comprova_cuidado',1.0,'Metas realistas e acompanhadas'),
 ('metas','meta','baixa-clareza-papel','atuacao','comprova_cuidado',1.0,NULL),
 ('metas','meta','baixo-controle','atuacao','comprova_cuidado',1.0,NULL),
 -- plano_acao -> atuacao (acao de origem psicossocial)
 ('plano_acao','acao','excesso-demandas','atuacao','comprova_cuidado',1.0,'Plano de acao 5W2H'),
 ('plano_acao','acao','baixa-clareza-papel','atuacao','comprova_cuidado',1.0,NULL),
 ('plano_acao','acao','baixo-controle','atuacao','comprova_cuidado',1.0,NULL),
 -- PDI -> atuacao
 ('pdi','pdi','baixas-recompensas','atuacao','comprova_cuidado',1.0,'Desenvolvimento/carreira'),
 ('pdi','pdi','baixa-demanda','atuacao','comprova_cuidado',1.0,'Enriquecimento de tarefas contra subcarga'),
 ('pdi','pdi','baixo-controle','atuacao','comprova_cuidado',1.0,NULL),
 -- avaliacao -> atuacao (so preventiva: avaliacao concluida = cuidado preventivo)
 ('avaliacao','avaliacao','baixa-clareza-papel','atuacao','comprova_cuidado',1.0,'Avaliacao esclarece expectativas'),
 ('avaliacao','avaliacao','baixa-justica','atuacao','comprova_cuidado',1.0,NULL),
 ('avaliacao','avaliacao','baixas-recompensas','atuacao','comprova_cuidado',1.0,NULL),
 -- cultura -> atuacao
 ('cultura','cultura','mas-relacoes','atuacao','comprova_cuidado',1.0,'Rituais/convivencia'),
 ('cultura','cultura','baixas-recompensas','atuacao','comprova_cuidado',1.0,NULL),
 ('cultura','cultura','falta-suporte','atuacao','comprova_cuidado',1.0,NULL),
 -- documentos -> atuacao
 ('documentos','documento','assedio','atuacao','comprova_cuidado',1.0,'Politicas/PGR/SST vigentes'),
 ('documentos','documento','baixa-clareza-papel','atuacao','comprova_cuidado',1.0,NULL),
 ('documentos','documento','baixa-justica','atuacao','comprova_cuidado',1.0,NULL),
 -- ponto -> contraprova
 ('ponto','horas_extras','excesso-demandas','contraprova','he_alto_corrobora',1.0,'Jornada excessiva corrobora sobrecarga'),
 ('ponto','horas_extras','baixo-controle','contraprova','he_alto_corrobora',1.0,NULL),
 -- bem-estar -> contraprova
 ('bem_estar','bem_estar','excesso-demandas','contraprova','bemestar_baixo_corrobora',1.0,'Bem-estar baixo corrobora risco'),
 ('bem_estar','bem_estar','falta-suporte','contraprova','bemestar_baixo_corrobora',1.0,NULL),
 ('bem_estar','bem_estar','baixas-recompensas','contraprova','bemestar_baixo_corrobora',1.0,NULL),
 ('bem_estar','bem_estar','baixo-controle','contraprova','bemestar_baixo_corrobora',1.0,NULL),
 ('bem_estar','bem_estar','baixa-demanda','contraprova','bemestar_baixo_corrobora',1.0,NULL),
 -- incidentes/CAT -> contraprova
 ('incidentes','incidente_cat','eventos-violentos','contraprova','incidente_presente_corrobora',1.0,'CAT/incidente corrobora'),
 ('incidentes','incidente_cat','excesso-demandas','contraprova','incidente_presente_corrobora',1.0,NULL),
 -- EPI -> atuacao (peso baixo; so quando ha exposicao a violencia/acidente grave)
 ('epi','epi','eventos-violentos','atuacao','comprova_cuidado',0.3,'Somente atividade com exposicao a violencia/acidente grave'),
 ('epi','epi','falta-suporte','atuacao','comprova_cuidado',0.3,'Somente atividade com exposicao a violencia/acidente grave')
ON CONFLICT (tipo_modulo, fator_id, natureza) DO UPDATE
  SET indicador=EXCLUDED.indicador, regra_sentido=EXCLUDED.regra_sentido,
      peso=EXCLUDED.peso, observacao=EXCLUDED.observacao, ativo=true;

-- =====================================================================
-- 5) HELPERS — normalizacao + resolver de fator por subject (espelho do TS)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.psicossocial_norm(p text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $norm$
  SELECT trim(regexp_replace(
           translate(lower(coalesce(p,'')),
             'áàâãäéèêëíìîïóòôõöúùûüçñ',
             'aaaaaeeeeiiiiooooouuuucn'),
           '[^a-z0-9]+', ' ', 'g'))
$norm$;

CREATE OR REPLACE FUNCTION public.psicossocial_fator_por_subject(p_subject text)
RETURNS text
LANGUAGE plpgsql STABLE
SET search_path = public
AS $resolv$
DECLARE
  v_norm  text;
  v_fator text;
BEGIN
  v_norm := public.psicossocial_norm(p_subject);
  IF v_norm = '' THEN
    RETURN NULL;
  END IF;

  -- Nome exato ou alias exato
  v_fator := (
    SELECT c.fator_id
    FROM public.psicossocial_fatores_catalogo c
    WHERE public.psicossocial_norm(c.nome) = v_norm
       OR EXISTS (SELECT 1 FROM unnest(c.aliases) a WHERE public.psicossocial_norm(a) = v_norm)
    ORDER BY c.ordem
    LIMIT 1
  );
  IF v_fator IS NOT NULL THEN
    RETURN v_fator;
  END IF;

  -- Alias mais longo contido no subject (>= 8 chars normalizados, com fronteira)
  v_fator := (
    SELECT c.fator_id
    FROM public.psicossocial_fatores_catalogo c
    CROSS JOIN LATERAL unnest(c.aliases) a
    WHERE length(public.psicossocial_norm(a)) >= 8
      AND (' ' || v_norm || ' ') LIKE ('% ' || public.psicossocial_norm(a) || ' %')
    ORDER BY length(public.psicossocial_norm(a)) DESC
    LIMIT 1
  );
  RETURN v_fator;
END
$resolv$;

-- =====================================================================
-- 6) RPC — recalcular evidencias (read-only sobre os modulos; UPSERT idempotente)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.psicossocial_recalcular_evidencias(p_campanha_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $recalc$
DECLARE
  v_tenant uuid;
  v_ini    date;
  v_fim    date;
  v_total  int;
BEGIN
  v_tenant := (SELECT tenant_id   FROM public.questionario_psicossocial_campanhas WHERE id = p_campanha_id);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'campanha_inexistente');
  END IF;

  -- Isolamento de tenant para chamadas autenticadas (SECURITY DEFINER ignora RLS)
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'acesso negado: campanha de outro tenant';
  END IF;

  v_ini := (SELECT data_inicio FROM public.questionario_psicossocial_campanhas WHERE id = p_campanha_id);
  v_fim := (SELECT data_fim    FROM public.questionario_psicossocial_campanhas WHERE id = p_campanha_id);

  -- Idempotencia: limpa a evidencia auto-gerada anterior (preserva linhas legadas natureza IS NULL)
  DELETE FROM public.psicossocial_evidencias
   WHERE tenant_id = v_tenant AND campanha_id = p_campanha_id AND natureza IS NOT NULL;

  -- ---------- TREINO (atuacao, por registro) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'treino', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'funcao_treinamento_evidencias', t.id, NULL, t.colaborador_nome, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN t.data_conclusao IS NOT NULL OR COALESCE(t.aprovado,false) THEN 'executada' ELSE 'planejada' END,
                              'tipo_treinamento', t.tipo_treinamento)
    FROM public.funcao_treinamento_evidencias t
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='treino' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE t.tenant_id=v_tenant AND t.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET fator_id=EXCLUDED.fator_id, dimensao_categoria=EXCLUDED.dimensao_categoria, natureza=EXCLUDED.natureza,
          sentido=EXCLUDED.sentido, origem_tabela=EXCLUDED.origem_tabela, valor=EXCLUDED.valor,
          valor_texto=EXCLUDED.valor_texto, periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim,
          peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo treino ignorado: %', SQLERRM;
  END;

  -- ---------- FEEDBACK (atuacao, por registro) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'feedback', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'feedbacks', f.id, NULL, f.categoria::text, v_ini, v_fim, m.peso,
           jsonb_build_object('estado','executada','categoria', f.categoria::text)
    FROM public.feedbacks f
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='feedback' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE f.tenant_id=v_tenant AND f.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET fator_id=EXCLUDED.fator_id, dimensao_categoria=EXCLUDED.dimensao_categoria, natureza=EXCLUDED.natureza,
          sentido=EXCLUDED.sentido, origem_tabela=EXCLUDED.origem_tabela, valor=EXCLUDED.valor,
          valor_texto=EXCLUDED.valor_texto, periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim,
          peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo feedback(atuacao) ignorado: %', SQLERRM;
  END;

  -- ---------- FEEDBACK (contraprova, agregado por fator) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'feedback', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN a.n_alinhamento > 0 AND a.n_alinhamento >= a.n_reconhecimento THEN 'corrobora'
                WHEN a.n_reconhecimento > 0 AND a.n_alinhamento = 0 THEN 'contradiz'
                ELSE 'neutro' END,
           'feedbacks',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|feedback|'||m.fator_id||'|contraprova')::uuid,
           a.n_alinhamento, NULL, v_ini, v_fim, m.peso,
           jsonb_build_object('n_alinhamento',a.n_alinhamento,'n_reconhecimento',a.n_reconhecimento,'n_total',a.n_total)
    FROM (
      SELECT COUNT(*) FILTER (WHERE f.categoria::text='alinhamento')      AS n_alinhamento,
             COUNT(*) FILTER (WHERE f.categoria::text='reconhecimento')   AS n_reconhecimento,
             COUNT(*)                                                     AS n_total
      FROM public.feedbacks f
      WHERE f.tenant_id=v_tenant AND f.created_at::date BETWEEN v_ini AND v_fim
    ) a
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='feedback' AND m.natureza='contraprova' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo feedback(contraprova) ignorado: %', SQLERRM;
  END;

  -- ---------- OUVIDORIA (atuacao, por registro tratado) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'ouvidoria', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'ouvidoria', o.id, NULL, o.tipo,  v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN o.status IN ('respondido','arquivado') THEN 'executada' ELSE 'planejada' END,
                              'tipo', o.tipo, 'status', o.status)
    FROM public.ouvidoria o
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='ouvidoria' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE o.tenant_id=v_tenant AND o.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo ouvidoria(atuacao) ignorado: %', SQLERRM;
  END;

  -- ---------- OUVIDORIA (contraprova: denuncias corroboram) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'ouvidoria', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN a.n_denuncia > 0 THEN 'corrobora' ELSE 'neutro' END,
           'ouvidoria',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|ouvidoria|'||m.fator_id||'|contraprova')::uuid,
           a.n_denuncia, NULL, v_ini, v_fim, m.peso,
           jsonb_build_object('n_denuncia',a.n_denuncia,'n_total',a.n_total)
    FROM (
      SELECT COUNT(*) FILTER (WHERE o.tipo='denuncia') AS n_denuncia, COUNT(*) AS n_total
      FROM public.ouvidoria o
      WHERE o.tenant_id=v_tenant AND o.created_at::date BETWEEN v_ini AND v_fim
    ) a
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='ouvidoria' AND m.natureza='contraprova' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo ouvidoria(contraprova) ignorado: %', SQLERRM;
  END;

  -- ---------- ERGONOMIA (atuacao via ergonomia_acoes) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'ergonomia', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'ergonomia_acoes', e.id, NULL, e.titulo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN e.status='concluida' AND e.data_conclusao IS NOT NULL THEN 'executada' ELSE 'planejada' END,
                              'status', e.status::text)
    FROM public.ergonomia_acoes e
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='ergonomia' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE e.tenant_id=v_tenant AND e.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo ergonomia(atuacao) ignorado: %', SQLERRM;
  END;

  -- ---------- ERGONOMIA (contraprova: risco ergonomico alto corrobora) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'ergonomia', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN a.n_alto > 0 THEN 'corrobora' ELSE 'neutro' END,
           'ergonomia_riscos',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|ergonomia|'||m.fator_id||'|contraprova')::uuid,
           a.n_alto, NULL, v_ini, v_fim, m.peso,
           jsonb_build_object('n_alto',a.n_alto,'n_total',a.n_total)
    FROM (
      SELECT COUNT(*) FILTER (WHERE r.severidade::text IN ('alto','critico')) AS n_alto, COUNT(*) AS n_total
      FROM public.ergonomia_riscos r
      WHERE r.tenant_id=v_tenant AND COALESCE(r.ativo,true) AND r.created_at::date BETWEEN v_ini AND v_fim
    ) a
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='ergonomia' AND m.natureza='contraprova' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo ergonomia(contraprova) ignorado: %', SQLERRM;
  END;

  -- ---------- METAS (atuacao) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'metas', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'metas', g.id, NULL, g.titulo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN g.status::text='concluida' THEN 'executada' ELSE 'planejada' END,
                              'status', g.status::text)
    FROM public.metas g
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='metas' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE g.tenant_id=v_tenant AND g.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo metas ignorado: %', SQLERRM;
  END;

  -- ---------- PLANO DE ACAO (atuacao via plano_acoes origem psicossocial) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'plano_acao', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'plano_acoes', pa.id, NULL, pa.titulo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado',
             CASE WHEN pa.status::text='concluida' AND pa.data_conclusao IS NOT NULL
                       AND (NOT COALESCE(pa.exige_evidencia,false)
                            OR EXISTS (SELECT 1 FROM public.plano_evidencias pe WHERE pe.acao_id=pa.id))
                  THEN 'executada' ELSE 'planejada' END,
             'status', pa.status::text, 'exige_evidencia', COALESCE(pa.exige_evidencia,false))
    FROM public.plano_acoes pa
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='plano_acao' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE pa.tenant_id=v_tenant AND pa.origem_modulo='psicossocial'
      AND pa.status::text <> 'cancelada'
      AND pa.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo plano_acao(plano_acoes) ignorado: %', SQLERRM;
  END;

  -- ---------- PLANO DE ACAO (planejado via psicossocial_plano_acao.selecionada, por fator direto) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'plano_acao', 'atuacao:'||c.fator_id, c.fator_id, c.categoria, 'atuacao', 'comprova',
           'psicossocial_plano_acao', pa.id, NULL, pa.o_que, v_ini, v_fim, 1.0,
           jsonb_build_object('estado','planejada','selecionada',pa.selecionada,'nivel_gro',pa.nivel_gro)
    FROM public.psicossocial_plano_acao pa
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=pa.fator_id
    WHERE pa.tenant_id=v_tenant AND pa.selecionada = true
      AND p_campanha_id = ANY (pa.campanha_ids)
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET fator_id=EXCLUDED.fator_id, dimensao_categoria=EXCLUDED.dimensao_categoria, valor_texto=EXCLUDED.valor_texto,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo plano_acao(psicossocial_plano_acao) ignorado: %', SQLERRM;
  END;

  -- ---------- PDI (atuacao via pdi_acoes) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'pdi', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'pdi_acoes', pa.id, NULL, pa.titulo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN pa.status::text='concluida' THEN 'executada' ELSE 'planejada' END,
                              'status', pa.status::text)
    FROM public.pdi_acoes pa
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='pdi' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE pa.tenant_id=v_tenant AND pa.created_at::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo pdi ignorado: %', SQLERRM;
  END;

  -- ---------- AVALIACAO (atuacao preventiva via avaliacao_respostas concluidas) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'avaliacao', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'avaliacao_respostas', ar.id, NULL, ar.avaliado_nome, v_ini, v_fim, m.peso,
           jsonb_build_object('estado','executada','status', ar.status::text,'preventiva',true)
    FROM public.avaliacao_respostas ar
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='avaliacao' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE ar.tenant_id=v_tenant AND ar.status::text='concluida'
      AND COALESCE(ar.data_conclusao, ar.created_at)::date BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo avaliacao ignorado: %', SQLERRM;
  END;

  -- ---------- CULTURA (atuacao via cultura_acoes) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'cultura', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'cultura_acoes', ca.id, NULL, ca.titulo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN ca.status='concluida' THEN 'executada' ELSE 'planejada' END,
                              'status', ca.status)
    FROM public.cultura_acoes ca
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='cultura' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE ca.tenant_id=v_tenant
      AND COALESCE(ca.data_execucao, ca.data_referencia, ca.created_at::date) BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo cultura ignorado: %', SQLERRM;
  END;

  -- ---------- DOCUMENTOS (atuacao via sst_documentos vigentes) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'documentos', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'sst_documentos', d.id, NULL, d.tipo, v_ini, v_fim, m.peso,
           jsonb_build_object('estado', CASE WHEN COALESCE(d.status,'vigente')='vigente' THEN 'executada' ELSE 'planejada' END,
                              'tipo', d.tipo, 'status', d.status)
    FROM public.sst_documentos d
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='documentos' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE d.tenant_id=v_tenant
      AND COALESCE(d.data_emissao, d.created_at::date) BETWEEN v_ini AND v_fim
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo documentos ignorado: %', SQLERRM;
  END;

  -- ---------- PONTO (contraprova: jornada excessiva corrobora) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'ponto', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN a.dias = 0 THEN 'neutro'
                WHEN (a.he_min / NULLIF(a.dias,0)) >= 60 THEN 'corrobora'
                WHEN (a.he_min / NULLIF(a.dias,0)) < 30 THEN 'contradiz'
                ELSE 'neutro' END,
           'ponto_diario',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|ponto|'||m.fator_id||'|contraprova')::uuid,
           ROUND((a.he_min / NULLIF(a.dias,0))::numeric, 1), NULL, v_ini, v_fim, m.peso,
           jsonb_build_object('he_min_total',a.he_min,'dias',a.dias,'faltas',a.faltas)
    FROM (
      SELECT COALESCE(SUM(COALESCE(p.horas_extras_50_minutos,0)+COALESCE(p.horas_extras_100_minutos,0)),0) AS he_min,
             COUNT(*) FILTER (WHERE p.status='falta') AS faltas,
             COUNT(*) AS dias
      FROM public.ponto_diario p
      WHERE p.tenant_id=v_tenant AND p.data BETWEEN v_ini AND v_fim
    ) a
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='ponto' AND m.natureza='contraprova' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo ponto ignorado: %', SQLERRM;
  END;

  -- ---------- BEM-ESTAR (contraprova: media baixa corrobora) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'bem_estar', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN a.n = 0 THEN 'neutro'
                WHEN a.media < 2.5 THEN 'corrobora'
                WHEN a.media >= 3.5 THEN 'contradiz'
                ELSE 'neutro' END,
           'bem_estar_respostas',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|bem_estar|'||m.fator_id||'|contraprova')::uuid,
           ROUND(a.media::numeric, 2), NULL, v_ini, v_fim, m.peso,
           jsonb_build_object('media',a.media,'n',a.n)
    FROM (
      SELECT AVG(b.valor_numerico) AS media, COUNT(*) FILTER (WHERE b.valor_numerico IS NOT NULL) AS n
      FROM public.bem_estar_respostas b
      WHERE b.tenant_id=v_tenant AND b.created_at::date BETWEEN v_ini AND v_fim
    ) a
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='bem_estar' AND m.natureza='contraprova' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo bem_estar ignorado: %', SQLERRM;
  END;

  -- ---------- INCIDENTES/CAT (contraprova: incidente presente corrobora) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'incidentes', 'contraprova:'||m.fator_id, m.fator_id, c.categoria, 'contraprova',
           CASE WHEN (
                  (SELECT COUNT(*) FROM public.afastamentos_cat ac WHERE ac.tenant_id=v_tenant AND COALESCE(ac.cat_aplicavel,false) AND ac.data_acidente BETWEEN v_ini AND v_fim)
                + (SELECT COUNT(*) FROM public.desvios_seguranca ds WHERE ds.tenant_id=v_tenant AND ds.potencial_risco IN ('alto','critico') AND ds.data_desvio BETWEEN v_ini AND v_fim)
                ) > 0 THEN 'corrobora' ELSE 'neutro' END,
           'afastamentos_cat',
           md5(v_tenant::text||'|'||p_campanha_id::text||'|incidentes|'||m.fator_id||'|contraprova')::uuid,
           ( (SELECT COUNT(*) FROM public.afastamentos_cat ac WHERE ac.tenant_id=v_tenant AND COALESCE(ac.cat_aplicavel,false) AND ac.data_acidente BETWEEN v_ini AND v_fim)
           + (SELECT COUNT(*) FROM public.desvios_seguranca ds WHERE ds.tenant_id=v_tenant AND ds.potencial_risco IN ('alto','critico') AND ds.data_desvio BETWEEN v_ini AND v_fim) ),
           NULL, v_ini, v_fim, m.peso,
           jsonb_build_object(
             'cat', (SELECT COUNT(*) FROM public.afastamentos_cat ac WHERE ac.tenant_id=v_tenant AND COALESCE(ac.cat_aplicavel,false) AND ac.data_acidente BETWEEN v_ini AND v_fim),
             'desvios_graves', (SELECT COUNT(*) FROM public.desvios_seguranca ds WHERE ds.tenant_id=v_tenant AND ds.potencial_risco IN ('alto','critico') AND ds.data_desvio BETWEEN v_ini AND v_fim))
    FROM public.psicossocial_evidencia_mapa m
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE m.tipo_modulo='incidentes' AND m.natureza='contraprova' AND m.ativo
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET sentido=EXCLUDED.sentido, valor=EXCLUDED.valor, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo incidentes ignorado: %', SQLERRM;
  END;

  -- ---------- EPI (atuacao, peso baixo, SO com exposicao a violencia/acidente grave) ----------
  BEGIN
    INSERT INTO public.psicossocial_evidencias
      (tenant_id, campanha_id, tipo_modulo, indicador, fator_id, dimensao_categoria, natureza, sentido,
       origem_tabela, origem_id, valor, valor_texto, periodo_inicio, periodo_fim, peso, metadados)
    SELECT v_tenant, p_campanha_id, 'epi', 'atuacao:'||m.fator_id, m.fator_id, c.categoria, 'atuacao', 'comprova',
           'epi_entregas', ee.id, NULL, ee.colaborador_nome, v_ini, v_fim, m.peso,
           jsonb_build_object('estado','executada','exposicao_grave',true)
    FROM public.epi_entregas ee
    JOIN public.psicossocial_evidencia_mapa m ON m.tipo_modulo='epi' AND m.natureza='atuacao' AND m.ativo
    JOIN public.psicossocial_fatores_catalogo c ON c.fator_id=m.fator_id
    WHERE ee.tenant_id=v_tenant AND ee.data_entrega::date BETWEEN v_ini AND v_fim
      AND ( EXISTS (SELECT 1 FROM public.afastamentos_cat ac WHERE ac.tenant_id=v_tenant AND COALESCE(ac.cat_aplicavel,false) AND ac.data_acidente BETWEEN v_ini AND v_fim)
         OR EXISTS (SELECT 1 FROM public.desvios_seguranca ds WHERE ds.tenant_id=v_tenant AND ds.potencial_risco IN ('alto','critico') AND ds.data_desvio BETWEEN v_ini AND v_fim) )
    ON CONFLICT (tenant_id, campanha_id, tipo_modulo, indicador, origem_id) DO UPDATE
      SET valor_texto=EXCLUDED.valor_texto, dimensao_categoria=EXCLUDED.dimensao_categoria,
          periodo_inicio=EXCLUDED.periodo_inicio, periodo_fim=EXCLUDED.periodo_fim, peso=EXCLUDED.peso, metadados=EXCLUDED.metadados;
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modulo epi ignorado: %', SQLERRM;
  END;

  v_total := (SELECT COUNT(*) FROM public.psicossocial_evidencias
               WHERE tenant_id=v_tenant AND campanha_id=p_campanha_id AND natureza IS NOT NULL);

  RETURN jsonb_build_object(
    'ok', true,
    'campanha_id', p_campanha_id,
    'periodo', jsonb_build_object('inicio', v_ini, 'fim', v_fim),
    'total_evidencias', v_total
  );
END
$recalc$;

-- =====================================================================
-- 7) RPC — sincronizar evidencias de ATUACAO para gro_riscos.medidas_existentes
--    (so gerencia entradas com prefixo [auto]; preserva as manuais; idempotente)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.psicossocial_sincronizar_gro_medidas(p_campanha_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $sync$
DECLARE
  v_tenant    uuid;
  v_afetados  int := 0;
BEGIN
  v_tenant := (SELECT tenant_id FROM public.questionario_psicossocial_campanhas WHERE id = p_campanha_id);
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'campanha_inexistente');
  END IF;
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'acesso negado: campanha de outro tenant';
  END IF;

  WITH labels AS MATERIALIZED (
    SELECT e.fator_id,
           array_agg(DISTINCT '[auto] ' || e.tipo_modulo || ': ' ||
                     (SELECT COUNT(*) FROM public.psicossocial_evidencias e2
                        WHERE e2.tenant_id=e.tenant_id AND e2.campanha_id=e.campanha_id
                          AND e2.fator_id=e.fator_id AND e2.tipo_modulo=e.tipo_modulo
                          AND e2.natureza='atuacao' AND e2.metadados->>'estado'='executada')::text
                     || ' acao(oes) executada(s)'
           ) AS medidas
    FROM public.psicossocial_evidencias e
    WHERE e.tenant_id=v_tenant AND e.campanha_id=p_campanha_id
      AND e.natureza='atuacao' AND e.metadados->>'estado'='executada'
    GROUP BY e.fator_id
  ),
  alvo AS MATERIALIZED (
    SELECT g.id,
           public.psicossocial_fator_por_subject(COALESCE(g.dimensao_psicossocial, g.titulo)) AS fator
    FROM public.gro_riscos g
    WHERE g.tenant_id=v_tenant AND g.campanha_id=p_campanha_id
      AND g.subtipo='psicossocial' AND COALESCE(g.ativo,true)
  )
  UPDATE public.gro_riscos g
  SET medidas_existentes = (
        SELECT array_agg(DISTINCT x ORDER BY x) FROM (
          SELECT x FROM unnest(COALESCE(g.medidas_existentes, '{}'::text[])) AS x WHERE x NOT LIKE '[auto]%'
          UNION ALL
          SELECT x FROM unnest(l.medidas) AS x
        ) z
      ),
      updated_at = now()
  FROM alvo a
  JOIN labels l ON l.fator_id = a.fator
  WHERE g.id = a.id;

  GET DIAGNOSTICS v_afetados = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'campanha_id', p_campanha_id, 'riscos_atualizados', v_afetados);
END
$sync$;

-- =====================================================================
-- 8) RPC — status por dimensao (COBERTA/PARCIAL/DESCOBERTA + ALERTA + fonte)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.psicossocial_status_por_dimensao(p_campanha_id uuid)
RETURNS TABLE (
  fator_id             text,
  fator_nome           text,
  categoria            text,
  categoria_label      text,
  severidade_padrao    int,
  cobertura            text,
  tem_risco            boolean,
  nivel_risco          text,
  alerta               boolean,
  atuacao_executada    int,
  atuacao_planejada    int,
  contraprova_corrobora int,
  contraprova_contradiz int,
  contraprova_neutro    int,
  fontes               jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $status$
DECLARE
  v_tenant uuid;
BEGIN
  v_tenant := (SELECT tenant_id FROM public.questionario_psicossocial_campanhas WHERE id = p_campanha_id);
  IF v_tenant IS NULL THEN
    RETURN;
  END IF;
  IF auth.uid() IS NOT NULL AND public.get_user_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'acesso negado: campanha de outro tenant';
  END IF;

  RETURN QUERY
  WITH ev AS MATERIALIZED (
    SELECT e.fator_id,
           COUNT(*) FILTER (WHERE e.natureza='atuacao'     AND e.metadados->>'estado'='executada') AS at_exec,
           COUNT(*) FILTER (WHERE e.natureza='atuacao'     AND e.metadados->>'estado'='planejada') AS at_plan,
           COUNT(*) FILTER (WHERE e.natureza='contraprova' AND e.sentido='corrobora')              AS cp_corr,
           COUNT(*) FILTER (WHERE e.natureza='contraprova' AND e.sentido='contradiz')              AS cp_contra,
           COUNT(*) FILTER (WHERE e.natureza='contraprova' AND e.sentido='neutro')                 AS cp_neutro,
           jsonb_agg(DISTINCT e.tipo_modulo) FILTER (WHERE e.natureza='atuacao')     AS mod_atuacao,
           jsonb_agg(DISTINCT e.tipo_modulo) FILTER (WHERE e.natureza='contraprova') AS mod_contraprova
    FROM public.psicossocial_evidencias e
    WHERE e.tenant_id=v_tenant AND e.campanha_id=p_campanha_id AND e.natureza IS NOT NULL
    GROUP BY e.fator_id
  ),
  riscos AS (
    SELECT pa.fator_id AS fator, pa.nivel_gro AS nivel
    FROM public.psicossocial_plano_acao pa
    WHERE pa.tenant_id=v_tenant AND p_campanha_id = ANY (pa.campanha_ids)
    UNION ALL
    SELECT public.psicossocial_fator_por_subject(COALESCE(g.dimensao_psicossocial, g.titulo)) AS fator, g.nivel_risco AS nivel
    FROM public.gro_riscos g
    WHERE g.tenant_id=v_tenant AND g.campanha_id=p_campanha_id AND g.subtipo='psicossocial' AND COALESCE(g.ativo,true)
  ),
  risco_fator AS (
    SELECT r.fator,
           MAX(CASE r.nivel WHEN 'critico' THEN 4 WHEN 'alto' THEN 3 WHEN 'medio' THEN 2 WHEN 'baixo' THEN 1 ELSE 0 END) AS nivel_num
    FROM riscos r
    WHERE r.fator IS NOT NULL
    GROUP BY r.fator
  )
  SELECT
    c.fator_id,
    c.nome,
    c.categoria,
    c.categoria_label,
    c.severidade_padrao,
    CASE WHEN COALESCE(ev.at_exec,0) > 0 THEN 'coberta'
         WHEN COALESCE(ev.at_plan,0) > 0 THEN 'parcial'
         ELSE 'descoberta' END AS cobertura,
    COALESCE(rf.nivel_num,0) >= 2 AS tem_risco,
    CASE COALESCE(rf.nivel_num,0) WHEN 4 THEN 'critico' WHEN 3 THEN 'alto' WHEN 2 THEN 'medio' WHEN 1 THEN 'baixo' ELSE 'sem_risco' END AS nivel_risco,
    ( (CASE WHEN COALESCE(ev.at_exec,0) > 0 THEN 'coberta'
            WHEN COALESCE(ev.at_plan,0) > 0 THEN 'parcial'
            ELSE 'descoberta' END) = 'descoberta'
      AND COALESCE(rf.nivel_num,0) >= 2 ) AS alerta,
    COALESCE(ev.at_exec,0),
    COALESCE(ev.at_plan,0),
    COALESCE(ev.cp_corr,0),
    COALESCE(ev.cp_contra,0),
    COALESCE(ev.cp_neutro,0),
    jsonb_build_object(
      'modulos_atuacao',     COALESCE(ev.mod_atuacao, '[]'::jsonb),
      'modulos_contraprova', COALESCE(ev.mod_contraprova, '[]'::jsonb)
    )
  FROM public.psicossocial_fatores_catalogo c
  LEFT JOIN ev          ON ev.fator_id = c.fator_id
  LEFT JOIN risco_fator rf ON rf.fator = c.fator_id
  ORDER BY c.ordem;
END
$status$;

-- =====================================================================
-- 9) Permissoes — REVOKE PUBLIC em toda funcao; GRANT so p/ authenticated
-- =====================================================================
REVOKE ALL ON FUNCTION public.psicossocial_norm(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.psicossocial_fator_por_subject(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.psicossocial_recalcular_evidencias(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.psicossocial_sincronizar_gro_medidas(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.psicossocial_status_por_dimensao(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.psicossocial_norm(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.psicossocial_fator_por_subject(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.psicossocial_recalcular_evidencias(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.psicossocial_sincronizar_gro_medidas(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.psicossocial_status_por_dimensao(uuid) TO authenticated;

-- =====================================================================
-- 10) QA — documentacao de testes (casos nivel api)
-- =====================================================================
INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-003',
       'Status por dimensao: atuacao executada=Coberta, so planejada=Parcial, risco sem acao=Alerta',
       'feliz'::public.qa_caso_tipo, 'alta'::public.qa_prioridade, 'aprovado'::public.qa_caso_status, 'api',
       'A RPC psicossocial_status_por_dimensao deve classificar cada um dos 13 fatores como coberta (>=1 atuacao executada), parcial (so planejada) ou descoberta, e marcar ALERTA quando a dimensao esta descoberta E tem risco percebido (nunca "nao conforme").',
       'Rotina read-only confere as colunas novas da evidencia, os CHECK de natureza/sentido e as regras de cobertura/alerta no corpo da funcao.'
FROM public.qa_modulos m WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-004',
       'Mapa de evidencia fiel ao Guia MTE (EPI so exposicao/peso baixo; naturezas por modulo)',
       'feliz'::public.qa_caso_tipo, 'alta'::public.qa_prioridade, 'aprovado'::public.qa_caso_status, 'api',
       'O seed psicossocial_evidencia_mapa deve refletir a metodologia fechada: EPI mapeia SO eventos-violentos e falta-suporte como atuacao com peso baixo; ponto/bem_estar/incidentes sao contraprova; treino cobre os 4 fatores previstos; e todo fator do mapa existe no catalogo dos 13.',
       'Rotina read-only consulta as tabelas de referencia semeadas.'
FROM public.qa_modulos m WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_casos_teste
  (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, observacoes)
SELECT m.id, 'PSICO-API-005',
       'Recalculo classifica natureza/sentido e executado>planejado; sincroniza medidas no GRO',
       'feliz'::public.qa_caso_tipo, 'alta'::public.qa_prioridade, 'aprovado'::public.qa_caso_status, 'api',
       'A RPC psicossocial_recalcular_evidencias deve ser idempotente (UPSERT), classificar atuacao/contraprova e sentido (comprova/corrobora/contradiz/neutro), distinguir executada vs planejada (PDCA), e a sincronizar_gro_medidas deve alimentar gro_riscos.medidas_existentes sem apagar medidas manuais.',
       'Rotina read-only confere os marcadores no corpo das funcoes.'
FROM public.qa_modulos m WHERE m.path = 'saude-seguranca/psicossocial'
ON CONFLICT (codigo) DO NOTHING;

-- =====================================================================
-- 11) QA — rotinas de execucao (somente leitura)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.qa_caso_psico_api_003()
RETURNS public.qa_retorno LANGUAGE plpgsql
SET search_path = public
AS $qa3$
DECLARE
  r public.qa_retorno;
  v_def text;
  v_cols int;
  v_chk  int;
BEGIN
  IF to_regprocedure('public.psicossocial_status_por_dimensao(uuid)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Funcao psicossocial_status_por_dimensao nao existe nesta base.';
    RETURN r;
  END IF;

  v_cols := (SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema='public' AND table_name='psicossocial_evidencias'
               AND column_name IN ('fator_id','dimensao_categoria','natureza','sentido','origem_tabela','origem_id'));
  v_chk  := (SELECT COUNT(*) FROM pg_constraint
             WHERE conname IN ('psicossocial_evidencias_natureza_chk','psicossocial_evidencias_sentido_chk'));
  v_def  := pg_get_functiondef('public.psicossocial_status_por_dimensao(uuid)'::regprocedure);

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir colunas de dimensao, CHECK e regras de cobertura/alerta';
  r.esperado    := '6 colunas novas + 2 CHECK; corpo com coberta/parcial/descoberta e alerta=descoberta AND tem_risco';

  IF v_cols = 6 AND v_chk = 2
     AND position('coberta' in v_def) > 0 AND position('parcial' in v_def) > 0
     AND position('descoberta' in v_def) > 0 AND position('alerta' in v_def) > 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Evidencia por dimensao com colunas/CHECK e a funcao classifica cobertura e marca ALERTA (descoberta com risco).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('colunas=%s/6; checks=%s/2; corpo cobertura/alerta presente=%s',
                       v_cols, v_chk,
                       (position('descoberta' in v_def) > 0 AND position('alerta' in v_def) > 0));
    r.erro_tecnico := 'Faltam colunas/CHECK ou a logica de cobertura/alerta no corpo da funcao.';
  END IF;
  RETURN r;
END
$qa3$;

CREATE OR REPLACE FUNCTION public.qa_caso_psico_api_004()
RETURNS public.qa_retorno LANGUAGE plpgsql
SET search_path = public
AS $qa4$
DECLARE
  r public.qa_retorno;
  v_epi_err   int;
  v_epi_ok    int;
  v_contra    int;
  v_treino    int;
  v_orfaos    int;
BEGIN
  IF to_regclass('public.psicossocial_evidencia_mapa') IS NULL OR to_regclass('public.psicossocial_fatores_catalogo') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Tabelas de referencia (mapa/catalogo) nao existem nesta base.';
    RETURN r;
  END IF;

  -- EPI so pode mapear eventos-violentos/falta-suporte como atuacao, peso < 1
  v_epi_err := (SELECT COUNT(*) FROM public.psicossocial_evidencia_mapa
                WHERE tipo_modulo='epi'
                  AND (natureza <> 'atuacao' OR peso >= 1.0 OR fator_id NOT IN ('eventos-violentos','falta-suporte')));
  v_epi_ok  := (SELECT COUNT(*) FROM public.psicossocial_evidencia_mapa WHERE tipo_modulo='epi');
  -- ponto/bem_estar/incidentes sao contraprova
  v_contra  := (SELECT COUNT(*) FROM public.psicossocial_evidencia_mapa
                WHERE tipo_modulo IN ('ponto','bem_estar','incidentes') AND natureza <> 'contraprova');
  -- treino cobre os 4 fatores previstos (atuacao)
  v_treino  := (SELECT COUNT(*) FROM public.psicossocial_evidencia_mapa
                WHERE tipo_modulo='treino' AND natureza='atuacao'
                  AND fator_id IN ('falta-suporte','assedio','mas-relacoes','baixa-justica'));
  -- todo fator do mapa existe no catalogo dos 13
  v_orfaos  := (SELECT COUNT(*) FROM public.psicossocial_evidencia_mapa m
                WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_fatores_catalogo c WHERE c.fator_id=m.fator_id));

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir fidelidade do mapa a metodologia fechada';
  r.esperado    := 'EPI so exposicao/peso baixo; ponto/bem_estar/incidentes contraprova; treino com 4 fatores; sem fator orfao';

  IF v_epi_err = 0 AND v_epi_ok >= 2 AND v_contra = 0 AND v_treino = 4 AND v_orfaos = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Mapa fiel: EPI restrito e peso baixo, contraprovas corretas, treino completo, nenhum fator fora do catalogo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('epi_invalidos=%s; epi_linhas=%s; contraprova_invalidas=%s; treino_fatores=%s/4; orfaos=%s',
                       v_epi_err, v_epi_ok, v_contra, v_treino, v_orfaos);
    r.erro_tecnico := 'Seed do mapa divergente da metodologia fechada (Guia MTE + ISO 45003 + NR-1).';
  END IF;
  RETURN r;
END
$qa4$;

CREATE OR REPLACE FUNCTION public.qa_caso_psico_api_005()
RETURNS public.qa_retorno LANGUAGE plpgsql
SET search_path = public
AS $qa5$
DECLARE
  r public.qa_retorno;
  v_rec text;
  v_syn text;
  v_tem_natureza boolean;
  v_tem_sentido  boolean;
  v_tem_estado   boolean;
  v_tem_upsert   boolean;
  v_tem_medidas  boolean;
BEGIN
  IF to_regprocedure('public.psicossocial_recalcular_evidencias(uuid)') IS NULL
     OR to_regprocedure('public.psicossocial_sincronizar_gro_medidas(uuid)') IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'RPCs de recalculo/sincronizacao nao existem nesta base.';
    RETURN r;
  END IF;

  v_rec := pg_get_functiondef('public.psicossocial_recalcular_evidencias(uuid)'::regprocedure);
  v_syn := pg_get_functiondef('public.psicossocial_sincronizar_gro_medidas(uuid)'::regprocedure);

  v_tem_natureza := position('atuacao' in v_rec) > 0 AND position('contraprova' in v_rec) > 0;
  v_tem_sentido  := position('corrobora' in v_rec) > 0 AND position('contradiz' in v_rec) > 0 AND position('comprova' in v_rec) > 0;
  v_tem_estado   := position('executada' in v_rec) > 0 AND position('planejada' in v_rec) > 0;
  v_tem_upsert   := position('ON CONFLICT' in v_rec) > 0;
  v_tem_medidas  := position('medidas_existentes' in v_syn) > 0 AND position('[auto]' in v_syn) > 0;

  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir classificacao, PDCA, idempotencia e sincronismo do GRO';
  r.esperado    := 'recalculo com naturezas/sentidos, executada vs planejada e ON CONFLICT; sync alimenta medidas_existentes [auto]';

  IF v_tem_natureza AND v_tem_sentido AND v_tem_estado AND v_tem_upsert AND v_tem_medidas THEN
    r.situacao := 'passou';
    r.obtido := 'Recalculo classifica natureza/sentido, distingue executado>planejado e e idempotente; sync preserva medidas manuais e adiciona [auto].';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('natureza=%s sentido=%s estado=%s upsert=%s medidas=%s',
                       v_tem_natureza, v_tem_sentido, v_tem_estado, v_tem_upsert, v_tem_medidas);
    r.erro_tecnico := 'Falta classificacao, distincao PDCA, idempotencia ou sincronismo de medidas no corpo das RPCs.';
  END IF;
  RETURN r;
END
$qa5$;

REVOKE ALL ON FUNCTION public.qa_caso_psico_api_003() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qa_caso_psico_api_004() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qa_caso_psico_api_005() FROM PUBLIC;
-- O motor de QA (qa_rodar_bateria) roda como INVOKER; o SuperAdmin autenticado
-- precisa poder executar as rotinas.
GRANT EXECUTE ON FUNCTION public.qa_caso_psico_api_003() TO authenticated;
GRANT EXECUTE ON FUNCTION public.qa_caso_psico_api_004() TO authenticated;
GRANT EXECUTE ON FUNCTION public.qa_caso_psico_api_005() TO authenticated;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('PSICO-API-003','qa_caso_psico_api_003'),
  ('PSICO-API-004','qa_caso_psico_api_004'),
  ('PSICO-API-005','qa_caso_psico_api_005')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- =====================================================================
-- Fim da migration (a conferencia final por SELECT fica so no script de entrega).
