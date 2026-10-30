-- ============================================================================
-- PONTO — BANCO DE HORAS CONFIGURÁVEL, FATIA 1 (só cadastros, sem mudar o cálculo)
--
-- Desenho: vault 01-Produto "Ponto - Banco de Horas Configurável (desenho)".
--
-- O QUE FAZ
--   (1) Instrumentos coletivos, N por conta: EVOLUI public.ponto_acordos (não
--       cria tabela paralela). Motivo: ponto_acordos já é o cadastro de
--       ACT/CCT/acordo individual que o sistema consulta hoje (12x36 art. 59-A,
--       REP alternativo, compensação de falta, ponto_banco_regime_vigente via
--       acordo_id) e já tem as travas de leitura/escrita por perfil. Uma tabela
--       nova deixaria dois cadastros de convenção e as regras atuais cegas para
--       o novo. Ganha: sindicatos, abrangência, categoria (preponderante ou
--       diferenciada), empresa representada, anexo privado, CBOs/cargos da
--       categoria (para sugestão de vínculo). tipo continua individual|act|cct;
--       "acordo individual modelo" = tipo individual sem colaborador_cpf.
--   (2) ponto_acordo_empresas: vínculo N:N instrumento x empresa.
--       ponto_instrumento_colaborador: vínculo do colaborador (admissão) ao
--       instrumento, com vigência e sem sobreposição.
--       ponto_instrumento_do_colaborador(tenant, admissao, data): precedência
--       ACT da empresa > instrumento vinculado > CCT preponderante.
--   (3) ponto_banco_horas_config ampliado (modalidade, ciclo, fim de ciclo,
--       rescisão, o que debita, fatores, limites, extrato). TODOS os campos
--       novos têm padrão que reproduz o comportamento de hoje e NENHUM é lido
--       pelo cálculo nesta fatia (a tela mostra o selo "em breve no cálculo").
--   (4) Bloqueios legais: não existe opção de transportar saldo positivo
--       (forma_pagamento_vencer só aceita horas_extras em gravação nova);
--       não existe configuração para debitar ausência legal/atestado (CLT 473;
--       Lei 605 art. 6º §1º) — por desenho, nenhuma coluna faz isso;
--       teto de crédito diário entre 0 e 120 min (a Fatia 3 aplica, no
--       cálculo, "600 - jornada do dia", exceção 12x36 do art. 59-A; o teto
--       bloqueia o CRÉDITO, nunca a batida).
--   (5) Avisos sem bloqueio: ponto_banco_config_avisos(_previa) e
--       ponto_banco_avisos_colaborador (aprendiz art. 432, menor art. 413,
--       insalubre art. 60).
--   (6) ponto_banco_regime_vigente: config 'sem_banco' passa a significar
--       "sem banco" (antes contava como regime), respeita data_fim e ignora
--       regras atreladas a instrumento (entram na Fatia 2). Só essa mudança no
--       cálculo. A função não tem remendos injetados por outras migrations
--       (conferido), então é CREATE OR REPLACE da única versão.
--   (7) ponto_banco_horas_movimentacoes.natureza_debito: ausencia_empregado x
--       dispensa_empresa (dispensa pode ser reposta, nunca descontada) — só a
--       coluna; o cálculo passa a preencher na Fatia 3.
--   (8) ponto_cct_config.instrumento_id + ponto_importar_cct_legado: a tela
--       antiga vira só leitura e oferece "trazer para o novo cadastro" (cria o
--       instrumento INATIVO, para não mudar 12x36/REP-A sem revisão do RH).
--
-- Atribuição só por subconsulta escalar e tabelas criadas por EXECUTE: o mesmo texto
-- vai para o script de entrega (auto-RLS do SQL Editor). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1) Instrumentos coletivos: evolução de ponto_acordos ────────────────────
ALTER TABLE public.ponto_acordos
  ADD COLUMN IF NOT EXISTS sindicato_laboral text,
  ADD COLUMN IF NOT EXISTS sindicato_patronal text,
  ADD COLUMN IF NOT EXISTS abrangencia_uf text,
  ADD COLUMN IF NOT EXISTS abrangencia_municipio text,
  ADD COLUMN IF NOT EXISTS abrangencia_texto text,
  ADD COLUMN IF NOT EXISTS categoria text NOT NULL DEFAULT 'preponderante',
  ADD COLUMN IF NOT EXISTS empresa_representada boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS anexo_path text,
  ADD COLUMN IF NOT EXISTS cbos_categoria text[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS cargos_categoria text[] NOT NULL DEFAULT '{}'::text[];

DO $ck$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ponto_acordos_categoria_chk') THEN
    ALTER TABLE public.ponto_acordos
      ADD CONSTRAINT ponto_acordos_categoria_chk CHECK (categoria IN ('preponderante', 'diferenciada'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ponto_acordos_vigencia_chk') THEN
    ALTER TABLE public.ponto_acordos
      ADD CONSTRAINT ponto_acordos_vigencia_chk
      CHECK (vigencia_fim IS NULL OR vigencia_inicio IS NULL OR vigencia_fim >= vigencia_inicio) NOT VALID;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: restricoes de ponto_acordos nao aplicadas: %', SQLERRM;
END $ck$;

COMMENT ON COLUMN public.ponto_acordos.categoria IS
  'preponderante = categoria da atividade preponderante do empregador (CLT 511 §2º, 581 §2º); diferenciada = profissão com estatuto próprio (CLT 511 §3º).';
COMMENT ON COLUMN public.ponto_acordos.empresa_representada IS
  'A empresa (ou seu sindicato patronal) participou da negociação? Para categoria diferenciada, sem representação a norma não se aplica (Súmula 374 do TST) — vira aviso, não bloqueio.';
COMMENT ON COLUMN public.ponto_acordos.anexo_path IS
  'Caminho do documento no bucket privado jornada-documentos (pasta do tenant). Ler por URL assinada.';
COMMENT ON COLUMN public.ponto_acordos.cbos_categoria IS
  'CBOs (ou prefixos) da categoria; usados só para SUGERIR o vínculo de colaboradores (confirmação manual).';
COMMENT ON COLUMN public.ponto_acordos.cargos_categoria IS
  'Palavras do cargo da categoria; usadas só para SUGERIR o vínculo de colaboradores (confirmação manual).';

-- ── 2) Vínculo N:N instrumento x empresa ────────────────────────────────────
DO $tb$
BEGIN
  IF to_regclass('public.ponto_acordo_empresas') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_acordo_empresas ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' acordo_id uuid NOT NULL REFERENCES public.ponto_acordos(id) ON DELETE CASCADE,'
      || ' empresa_id uuid NOT NULL REFERENCES public.empresa_cadastro(id) ON DELETE CASCADE,'
      || ' created_at timestamptz NOT NULL DEFAULT now(),'
      || ' CONSTRAINT ponto_acordo_empresas_uq UNIQUE (acordo_id, empresa_id))';
  END IF;
  IF to_regclass('public.ponto_instrumento_colaborador') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_instrumento_colaborador ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' admissao_id uuid NOT NULL REFERENCES public.admissoes(id) ON DELETE CASCADE,'
      || ' instrumento_id uuid NOT NULL REFERENCES public.ponto_acordos(id) ON DELETE CASCADE,'
      || ' data_inicio date NOT NULL DEFAULT CURRENT_DATE,'
      || ' data_fim date,'
      || ' observacao text,'
      || ' criado_por uuid DEFAULT auth.uid(),'
      || ' created_at timestamptz NOT NULL DEFAULT now(),'
      || ' updated_at timestamptz NOT NULL DEFAULT now(),'
      || ' CONSTRAINT ponto_instr_colab_periodo_chk CHECK (data_fim IS NULL OR data_fim >= data_inicio))';
  END IF;
END $tb$;

CREATE INDEX IF NOT EXISTS idx_ponto_acordo_empresas_emp ON public.ponto_acordo_empresas (tenant_id, empresa_id);
CREATE INDEX IF NOT EXISTS idx_ponto_instr_colab_adm ON public.ponto_instrumento_colaborador (tenant_id, admissao_id, data_inicio);

COMMENT ON TABLE public.ponto_acordo_empresas IS
  'Empresas abrangidas por um instrumento (ponto_acordos). Sem linha aqui e sem ponto_acordos.empresa_id, o instrumento vale para todas as empresas do tenant.';
COMMENT ON TABLE public.ponto_instrumento_colaborador IS
  'Instrumento coletivo do colaborador (categoria diferenciada, base territorial etc.), com vigência. Sem vínculo, vale a CCT preponderante da empresa. Ver ponto_instrumento_do_colaborador.';

-- RLS: tenant + portão por perfil (mesma regra de ponto_acordos: leitura para
-- perfil amplo ou líder de subordinados; escrita pelo verbo do perfil).
DO $rls$
DECLARE
  v_tab text;
  v_mods text := quote_literal(ARRAY['ponto','colaboradores']) || '::text[]';
BEGIN
  FOREACH v_tab IN ARRAY ARRAY['ponto_acordo_empresas', 'ponto_instrumento_colaborador'] LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', v_tab || '_tenant', v_tab);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
                     || 'USING (tenant_id = public.get_user_tenant_id()) '
                     || 'WITH CHECK (tenant_id = public.get_user_tenant_id())', v_tab || '_tenant', v_tab);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_leitura_' || v_tab, v_tab);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING ('
                     || 'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC %s) '
                     || 'OR public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC %s))',
                     'perfil_restringe_leitura_' || v_tab, v_tab, v_mods, v_mods);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_ins', v_tab);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ('
                     || 'public.perfil_permite_modulo(tenant_id, VARIADIC %s) '
                     || 'AND public.perfil_escreve(tenant_id, %s, ARRAY[''criar'']::text[], NULL::text))',
                     'perfil_restringe_escrita_' || v_tab || '_ins', v_tab, v_mods, v_mods);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_upd', v_tab);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING ('
                     || 'public.perfil_permite_modulo(tenant_id, VARIADIC %s) '
                     || 'AND public.perfil_escreve(tenant_id, %s, ARRAY[''editar'',''aprovar'']::text[], NULL::text))',
                     'perfil_restringe_escrita_' || v_tab || '_upd', v_tab, v_mods, v_mods);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'perfil_restringe_escrita_' || v_tab || '_del', v_tab);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING ('
                     || 'public.perfil_permite_modulo(tenant_id, VARIADIC %s) '
                     || 'AND public.perfil_escreve(tenant_id, %s, ARRAY[''excluir'']::text[], NULL::text))',
                     'perfil_restringe_escrita_' || v_tab || '_del', v_tab, v_mods, v_mods);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou so com a politica de tenant: %', v_tab, SQLERRM;
    END;
  END LOOP;
END $rls$;

-- Cerca do QA (tabelas com tenant_id): rotina de teste nunca escreve fora do cercado.
DO $cerca$
DECLARE v_t text;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
    RETURN;
  END IF;
  FOREACH v_t IN ARRAY ARRAY['ponto_acordo_empresas', 'ponto_instrumento_colaborador'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'qa_guarda_cercado'
                      AND tgrelid = ('public.' || v_t)::regclass AND NOT tgisinternal) THEN
      EXECUTE format('CREATE TRIGGER qa_guarda_cercado BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
                     || 'FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()', v_t);
    END IF;
    IF to_regclass('public.qa_tabelas_protegidas') IS NOT NULL THEN
      INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
      SELECT v_t, 'Cerca generica: tabela tem tenant_id'
      WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x WHERE x.tabela = v_t);
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cerca do QA nao instalada nas tabelas de instrumento: %', SQLERRM;
END $cerca$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ponto_acordo_empresas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ponto_instrumento_colaborador TO authenticated;

-- Guardas dos vínculos: mesmo tenant dos dois lados e sem sobreposição de
-- vigência para o mesmo colaborador (um instrumento de cada vez).
CREATE OR REPLACE FUNCTION public.ponto_instr_vinculo_guarda()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF TG_TABLE_NAME = 'ponto_acordo_empresas' THEN
    IF NOT EXISTS (SELECT 1 FROM public.ponto_acordos WHERE id = NEW.acordo_id AND tenant_id = NEW.tenant_id)
       OR NOT EXISTS (SELECT 1 FROM public.empresa_cadastro WHERE id = NEW.empresa_id AND tenant_id = NEW.tenant_id) THEN
      RAISE EXCEPTION 'Instrumento e empresa precisam ser da mesma conta.' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ponto_acordos WHERE id = NEW.instrumento_id AND tenant_id = NEW.tenant_id)
     OR NOT EXISTS (SELECT 1 FROM public.admissoes WHERE id = NEW.admissao_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'Instrumento e colaborador precisam ser da mesma conta.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ponto_instrumento_colaborador v
    WHERE v.tenant_id = NEW.tenant_id
      AND v.admissao_id = NEW.admissao_id
      AND v.id <> NEW.id
      AND daterange(v.data_inicio, COALESCE(v.data_fim, 'infinity'::date), '[]')
          && daterange(NEW.data_inicio, COALESCE(NEW.data_fim, 'infinity'::date), '[]')
  ) THEN
    RAISE EXCEPTION 'Este colaborador já tem um instrumento vinculado nesse período. Encerre o vínculo anterior (data de fim) antes de criar outro.'
      USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ponto_acordo_empresas_guarda ON public.ponto_acordo_empresas;
CREATE TRIGGER trg_ponto_acordo_empresas_guarda
  BEFORE INSERT OR UPDATE ON public.ponto_acordo_empresas
  FOR EACH ROW EXECUTE FUNCTION public.ponto_instr_vinculo_guarda();
DROP TRIGGER IF EXISTS trg_ponto_instr_colab_guarda ON public.ponto_instrumento_colaborador;
CREATE TRIGGER trg_ponto_instr_colab_guarda
  BEFORE INSERT OR UPDATE ON public.ponto_instrumento_colaborador
  FOR EACH ROW EXECUTE FUNCTION public.ponto_instr_vinculo_guarda();

-- ── 3) Banco de horas ampliado (padrões = comportamento de hoje) ────────────
ALTER TABLE public.ponto_banco_horas_config
  ADD COLUMN IF NOT EXISTS modalidade text NOT NULL DEFAULT 'mensal',
  ADD COLUMN IF NOT EXISTS tipo_ciclo text NOT NULL DEFAULT 'fixo',
  ADD COLUMN IF NOT EXISTS meses_fechamento integer[] NOT NULL DEFAULT ARRAY[1,2,3,4,5,6,7,8,9,10,11,12],
  ADD COLUMN IF NOT EXISTS data_fim date,
  ADD COLUMN IF NOT EXISTS instrumento_id uuid REFERENCES public.ponto_acordos(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS negativo_fim_ciclo text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS negativo_rescisao_sem_justa_causa text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS negativo_rescisao_pedido_demissao text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS negativo_rescisao_justa_causa text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS negativo_rescisao_acordo_484a text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS negativo_rescisao_fim_contrato text NOT NULL DEFAULT 'zerar',
  ADD COLUMN IF NOT EXISTS teto_desconto_rescisao_uma_remuneracao boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS falta_injustificada_destino text NOT NULL DEFAULT 'folha',
  ADD COLUMN IF NOT EXISTS atraso_destino text NOT NULL DEFAULT 'banco',
  ADD COLUMN IF NOT EXISTS saida_antecipada_destino text NOT NULL DEFAULT 'banco',
  ADD COLUMN IF NOT EXISTS limite_saldo_negativo_min integer,
  ADD COLUMN IF NOT EXISTS negativo_acima_limite_acao text NOT NULL DEFAULT 'alertar',
  ADD COLUMN IF NOT EXISTS fator_credito_util numeric(4,2) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS fator_credito_domingo numeric(4,2) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS fator_credito_feriado numeric(4,2) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS fator_credito_noturno numeric(4,2) NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS teto_credito_diario_min integer NOT NULL DEFAULT 120,
  ADD COLUMN IF NOT EXISTS limite_saldo_acao text NOT NULL DEFAULT 'alertar',
  ADD COLUMN IF NOT EXISTS extrato_mensal boolean NOT NULL DEFAULT true;

DO $ck2$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ponto_bh_cfg_modalidade_chk',   'modalidade IN (''mensal'',''semestral'',''anual'')'),
      ('ponto_bh_cfg_tipo_ciclo_chk',   'tipo_ciclo IN (''fixo'',''admissao'')'),
      ('ponto_bh_cfg_neg_fim_chk',      'negativo_fim_ciclo IN (''zerar'',''descontar'',''transportar'')'),
      ('ponto_bh_cfg_neg_resc_chk',     'negativo_rescisao_sem_justa_causa IN (''zerar'',''descontar'') '
                                        || 'AND negativo_rescisao_pedido_demissao IN (''zerar'',''descontar'') '
                                        || 'AND negativo_rescisao_justa_causa IN (''zerar'',''descontar'') '
                                        || 'AND negativo_rescisao_acordo_484a IN (''zerar'',''descontar'') '
                                        || 'AND negativo_rescisao_fim_contrato IN (''zerar'',''descontar'')'),
      ('ponto_bh_cfg_destinos_chk',     'falta_injustificada_destino IN (''banco'',''folha'',''banco_se_houver_saldo'') '
                                        || 'AND atraso_destino IN (''banco'',''folha'',''banco_se_houver_saldo'') '
                                        || 'AND saida_antecipada_destino IN (''banco'',''folha'',''banco_se_houver_saldo'')'),
      ('ponto_bh_cfg_neg_limite_chk',   '(limite_saldo_negativo_min IS NULL OR limite_saldo_negativo_min >= 0) '
                                        || 'AND negativo_acima_limite_acao IN (''alertar'',''folha'')'),
      ('ponto_bh_cfg_fatores_chk',      'fator_credito_util BETWEEN 1 AND 3 AND fator_credito_domingo BETWEEN 1 AND 3 '
                                        || 'AND fator_credito_feriado BETWEEN 1 AND 3 AND fator_credito_noturno BETWEEN 1 AND 3'),
      -- Bloqueio legal (c): teto de crédito diário nunca acima de 2h (CLT art. 59, caput e §2º).
      ('ponto_bh_cfg_teto_credito_chk', 'teto_credito_diario_min BETWEEN 0 AND 120'),
      ('ponto_bh_cfg_limite_acao_chk',  'limite_saldo_acao IN (''alertar'',''reter_excedente'')'),
      ('ponto_bh_cfg_vigencia_chk',     'data_fim IS NULL OR data_inicio IS NULL OR data_fim >= data_inicio')
    ) AS t(nome, expr)
  LOOP
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = r.nome) THEN
        EXECUTE format('ALTER TABLE public.ponto_banco_horas_config ADD CONSTRAINT %I CHECK (%s)', r.nome, r.expr);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: restricao % nao aplicada: %', r.nome, SQLERRM;
    END;
  END LOOP;
END $ck2$;

COMMENT ON COLUMN public.ponto_banco_horas_config.modalidade IS
  'mensal (acordo tácito/escrito, CLT 59 §6º) | semestral (acordo individual escrito, §5º) | anual (só CCT/ACT, §2º). Fatia 1: cadastro; o cálculo usa a partir da Fatia 2.';
COMMENT ON COLUMN public.ponto_banco_horas_config.tipo_ciclo IS
  'fixo (meses_fechamento) | admissao (ciclo individual contado da admissão). Fatia 2.';
COMMENT ON COLUMN public.ponto_banco_horas_config.meses_fechamento IS
  'Meses (1-12) em que o ciclo fixo fecha. O intervalo entre fechamentos não pode passar do máximo da modalidade.';
COMMENT ON COLUMN public.ponto_banco_horas_config.negativo_fim_ciclo IS
  'zerar (sempre lícito) | descontar | transportar (estes dois exigem CCT/ACT: aviso, não bloqueio). Positivo no fim do ciclo é SEMPRE pago como hora extra — não existe opção de transportar positivo.';
COMMENT ON COLUMN public.ponto_banco_horas_config.teto_credito_diario_min IS
  'Teto de crédito no banco por dia (0-120). A Fatia 3 aplica no cálculo min(teto, 600 - jornada do dia) — exceção 12x36 (art. 59-A). Limita o crédito, nunca a batida.';
COMMENT ON COLUMN public.ponto_banco_horas_config.falta_injustificada_destino IS
  'banco | folha | banco_se_houver_saldo (debita só até zerar o saldo positivo; o resto vai para a folha). No banco, não descontar o dia nem o DSR da mesma falta (Lei 605/49 art. 6º). Ausência legal (CLT 473) e atestado NUNCA debitam — não há configuração para isso.';
COMMENT ON COLUMN public.ponto_banco_horas_config.limite_saldo_negativo_min IS
  'Teto do saldo negativo em minutos (NULL = sem limite). Acima dele: negativo_acima_limite_acao (alertar | folha).';
COMMENT ON COLUMN public.ponto_banco_horas_config.instrumento_id IS
  'Instrumento (ponto_acordos) a que esta regra se aplica. Fatia 1: guardado e IGNORADO pelo regime vigente (regra por convenção entra na Fatia 2).';

-- natureza do débito (Fatia 3 preenche; dispensa pela empresa nunca é descontada)
ALTER TABLE public.ponto_banco_horas_movimentacoes
  ADD COLUMN IF NOT EXISTS natureza_debito text;
DO $ck3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ponto_bh_mov_natureza_debito_chk') THEN
    ALTER TABLE public.ponto_banco_horas_movimentacoes
      ADD CONSTRAINT ponto_bh_mov_natureza_debito_chk
      CHECK (natureza_debito IS NULL OR natureza_debito IN ('ausencia_empregado', 'dispensa_empresa'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: restricao de natureza_debito nao aplicada: %', SQLERRM;
END $ck3$;
COMMENT ON COLUMN public.ponto_banco_horas_movimentacoes.natureza_debito IS
  'Origem do débito: ausencia_empregado (atraso, saída, falta do empregado) | dispensa_empresa (a empresa liberou mais cedo ou não deu trabalho: pode ser reposta, NUNCA descontada em folha — CLT art. 2º, risco do empregador). NULL = histórico anterior. Preenchida pelo cálculo a partir da Fatia 3.';

-- ponto_cct_config aponta para o instrumento novo quando importada
ALTER TABLE public.ponto_cct_config
  ADD COLUMN IF NOT EXISTS instrumento_id uuid REFERENCES public.ponto_acordos(id) ON DELETE SET NULL;

-- ── 4) Validação da configuração (bloqueios legais e coerência) ─────────────
CREATE OR REPLACE FUNCTION public.ponto_banco_config_valida()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_meses int[];
  v_max int;
  v_gap int := 0;
  i int;
BEGIN
  -- Bloqueio (a): saldo positivo no fim do prazo é pago como hora extra.
  -- Transportar (ou "liquidar só na rescisão") e zerar positivo não existem.
  -- Valores antigos já gravados ficam até a próxima edição dessa coluna.
  IF NEW.forma_pagamento_vencer IS NOT NULL
     AND NEW.forma_pagamento_vencer <> 'horas_extras'
     AND (TG_OP = 'INSERT' OR NEW.forma_pagamento_vencer IS DISTINCT FROM OLD.forma_pagamento_vencer) THEN
    RAISE EXCEPTION 'Saldo positivo no fim do prazo é sempre pago como hora extra; transportar ou zerar horas a favor do empregado não é permitido (CLT art. 59, §§2º e 5º).'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Coerência do ciclo fixo com o máximo legal da modalidade.
  IF NEW.tipo_ciclo = 'fixo' THEN
    v_meses := (SELECT array_agg(DISTINCT m ORDER BY m) FROM unnest(NEW.meses_fechamento) m);
    IF v_meses IS NULL OR cardinality(v_meses) = 0 THEN
      RAISE EXCEPTION 'Ciclo fixo precisa de pelo menos um mês de fechamento.' USING ERRCODE = 'check_violation';
    END IF;
    IF v_meses[1] < 1 OR v_meses[cardinality(v_meses)] > 12 THEN
      RAISE EXCEPTION 'Meses de fechamento devem ir de 1 a 12.' USING ERRCODE = 'check_violation';
    END IF;
    v_max := CASE NEW.modalidade WHEN 'mensal' THEN 1 WHEN 'semestral' THEN 6 ELSE 12 END;
    FOR i IN 1 .. cardinality(v_meses) - 1 LOOP
      v_gap := GREATEST(v_gap, v_meses[i + 1] - v_meses[i]);
    END LOOP;
    v_gap := GREATEST(v_gap, 12 - v_meses[cardinality(v_meses)] + v_meses[1]);
    IF v_gap > v_max THEN
      RAISE EXCEPTION 'Com esses meses de fechamento, um ciclo duraria % meses, acima do máximo do banco % (% meses — CLT art. 59).',
        v_gap, NEW.modalidade, v_max USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Instrumento e acordo precisam ser da mesma conta.
  IF NEW.instrumento_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ponto_acordos WHERE id = NEW.instrumento_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'O instrumento escolhido não é desta conta.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_ponto_banco_config_valida ON public.ponto_banco_horas_config;
CREATE TRIGGER trg_ponto_banco_config_valida
  BEFORE INSERT OR UPDATE ON public.ponto_banco_horas_config
  FOR EACH ROW EXECUTE FUNCTION public.ponto_banco_config_valida();

-- ── 5) Funções de leitura ───────────────────────────────────────────────────
-- O instrumento abrange a empresa? (empresa_id direto, vínculo N:N, ou sem
-- empresa nenhuma = todas as empresas do tenant)
CREATE OR REPLACE FUNCTION public.ponto_acordo_cobre_empresa(p_acordo_id uuid, p_empresa_id uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.id = p_acordo_id
      AND (
        (p_empresa_id IS NOT NULL AND ac.empresa_id = p_empresa_id)
        OR (p_empresa_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.ponto_acordo_empresas ae
              WHERE ae.acordo_id = ac.id AND ae.empresa_id = p_empresa_id))
        OR (ac.empresa_id IS NULL AND NOT EXISTS (
              SELECT 1 FROM public.ponto_acordo_empresas ae WHERE ae.acordo_id = ac.id))
      )
  )
$fn$;

CREATE OR REPLACE FUNCTION public.ponto_acordo_vigente_em(p_acordo_id uuid, p_data date)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.id = p_acordo_id
      AND COALESCE(ac.ativo, false)
      AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= p_data)
      AND (ac.vigencia_fim IS NULL OR ac.vigencia_fim >= p_data)
  )
$fn$;

-- Há CCT/ACT vigente para a empresa (NULL = qualquer uma do tenant)?
CREATE OR REPLACE FUNCTION public.ponto_tem_coletivo_vigente(p_tenant uuid, p_empresa_id uuid, p_data date)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id = p_tenant
      AND ac.tipo IN ('act', 'cct')
      AND public.ponto_acordo_vigente_em(ac.id, p_data)
      AND (p_empresa_id IS NULL OR public.ponto_acordo_cobre_empresa(ac.id, p_empresa_id))
  )
$fn$;

-- Precedência do instrumento do colaborador na data:
--   1) ACT da empresa (o ACT a que o colaborador está vinculado; senão o ACT
--      vigente da empresa que não seja de categoria diferenciada) — CLT art. 620;
--   2) instrumento vinculado ao colaborador (ex.: CCT da categoria diferenciada);
--   3) CCT preponderante da empresa (CLT 511 §2º, 581 §2º).
-- Devolve jsonb {instrumento_id, origem, tipo, nome, categoria, alerta_sumula_374}.
CREATE OR REPLACE FUNCTION public.ponto_instrumento_do_colaborador(
  p_tenant uuid, p_admissao_id uuid, p_data date DEFAULT CURRENT_DATE)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $fn$
DECLARE
  v_emp uuid;
  v_id uuid;
  v_origem text := 'nenhum';
BEGIN
  v_emp := (SELECT a.empresa_id FROM public.admissoes a
             WHERE a.id = p_admissao_id AND a.tenant_id = p_tenant LIMIT 1);

  -- 1a) ACT vinculado ao colaborador
  v_id := (SELECT ac.id
             FROM public.ponto_instrumento_colaborador v
             JOIN public.ponto_acordos ac ON ac.id = v.instrumento_id
            WHERE v.tenant_id = p_tenant AND v.admissao_id = p_admissao_id
              AND v.data_inicio <= p_data AND (v.data_fim IS NULL OR v.data_fim >= p_data)
              AND ac.tipo = 'act' AND public.ponto_acordo_vigente_em(ac.id, p_data)
            ORDER BY v.data_inicio DESC LIMIT 1);
  IF v_id IS NOT NULL THEN v_origem := 'act_vinculado'; END IF;

  -- 1b) ACT da empresa
  IF v_id IS NULL THEN
    v_id := (SELECT ac.id FROM public.ponto_acordos ac
              WHERE ac.tenant_id = p_tenant AND ac.tipo = 'act'
                AND COALESCE(ac.categoria, 'preponderante') <> 'diferenciada'
                AND public.ponto_acordo_vigente_em(ac.id, p_data)
                AND public.ponto_acordo_cobre_empresa(ac.id, v_emp)
              ORDER BY (ac.empresa_id IS NOT DISTINCT FROM v_emp) DESC,
                       ac.vigencia_inicio DESC NULLS LAST, ac.created_at DESC
              LIMIT 1);
    IF v_id IS NOT NULL THEN v_origem := 'act_empresa'; END IF;
  END IF;

  -- 2) instrumento vinculado ao colaborador
  IF v_id IS NULL THEN
    v_id := (SELECT ac.id
               FROM public.ponto_instrumento_colaborador v
               JOIN public.ponto_acordos ac ON ac.id = v.instrumento_id
              WHERE v.tenant_id = p_tenant AND v.admissao_id = p_admissao_id
                AND v.data_inicio <= p_data AND (v.data_fim IS NULL OR v.data_fim >= p_data)
                AND ac.tipo IN ('cct', 'act') AND public.ponto_acordo_vigente_em(ac.id, p_data)
              ORDER BY v.data_inicio DESC LIMIT 1);
    IF v_id IS NOT NULL THEN v_origem := 'vinculo_colaborador'; END IF;
  END IF;

  -- 3) CCT preponderante da empresa
  IF v_id IS NULL THEN
    v_id := (SELECT ac.id FROM public.ponto_acordos ac
              WHERE ac.tenant_id = p_tenant AND ac.tipo = 'cct'
                AND COALESCE(ac.categoria, 'preponderante') = 'preponderante'
                AND public.ponto_acordo_vigente_em(ac.id, p_data)
                AND public.ponto_acordo_cobre_empresa(ac.id, v_emp)
              ORDER BY (ac.empresa_id IS NOT DISTINCT FROM v_emp) DESC,
                       ac.vigencia_inicio DESC NULLS LAST, ac.created_at DESC
              LIMIT 1);
    IF v_id IS NOT NULL THEN v_origem := 'cct_preponderante'; END IF;
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'instrumento_id', v_id,
      'origem', v_origem,
      'tipo', ac.tipo,
      'nome', ac.titulo,
      'categoria', ac.categoria,
      'alerta_sumula_374', (ac.categoria = 'diferenciada' AND NOT COALESCE(ac.empresa_representada, true)))
    FROM (SELECT 1) x LEFT JOIN public.ponto_acordos ac ON ac.id = v_id
  );
END $fn$;

COMMENT ON FUNCTION public.ponto_instrumento_do_colaborador(uuid, uuid, date) IS
  'Instrumento coletivo do colaborador na data. Precedência: ACT da empresa (o vinculado ao colaborador, senão o da empresa não diferenciado) > instrumento vinculado ao colaborador > CCT preponderante da empresa. Fatia 1: só leitura, o cálculo passa a usar na Fatia 2. CLT 511, 570, 581, 620; Súm. 374 TST.';

-- Avisos ao vincular um colaborador a um instrumento
CREATE OR REPLACE FUNCTION public.ponto_instrumento_avisos_vinculo(
  p_tenant uuid, p_instrumento_id uuid, p_admissao_id uuid DEFAULT NULL)
RETURNS TABLE(codigo text, nivel text, texto text, base_legal text)
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $fn$
DECLARE
  v_ac jsonb;
  v_emp uuid;
BEGIN
  v_ac := (SELECT to_jsonb(a) FROM public.ponto_acordos a
            WHERE a.id = p_instrumento_id AND a.tenant_id = p_tenant);
  IF v_ac IS NULL THEN RETURN; END IF;

  IF v_ac->>'categoria' = 'diferenciada' AND NOT COALESCE((v_ac->>'empresa_representada')::boolean, true) THEN
    codigo := 'SUMULA_374'; nivel := 'atencao';
    texto := 'Esta convenção é de categoria diferenciada e a empresa não participou da negociação. '
          || 'Nesse caso, a Justiça entende que ela não obriga a empresa e vale a convenção da atividade principal. '
          || 'O vínculo é gravado, mas confira com o jurídico.';
    base_legal := 'Súmula 374 do TST; CLT art. 511, §3º';
    RETURN NEXT;
  END IF;

  IF NOT public.ponto_acordo_vigente_em(p_instrumento_id, CURRENT_DATE) THEN
    codigo := 'INSTRUMENTO_FORA_VIGENCIA'; nivel := 'atencao';
    texto := 'O instrumento está inativo ou fora da vigência hoje: enquanto isso, o colaborador segue a convenção da empresa.';
    base_legal := 'CLT art. 614, §3º';
    RETURN NEXT;
  END IF;

  IF v_ac->>'tipo' = 'individual' THEN
    codigo := 'INSTRUMENTO_INDIVIDUAL'; nivel := 'info';
    texto := 'Acordo individual não define a categoria do colaborador; o vínculo serve para convenções (CCT) e acordos coletivos (ACT).';
    base_legal := 'CLT arts. 611 e 620';
    RETURN NEXT;
  END IF;

  IF p_admissao_id IS NOT NULL THEN
    v_emp := (SELECT a.empresa_id FROM public.admissoes a WHERE a.id = p_admissao_id AND a.tenant_id = p_tenant);
    IF v_ac->>'categoria' = 'preponderante' AND NOT public.ponto_acordo_cobre_empresa(p_instrumento_id, v_emp) THEN
      codigo := 'INSTRUMENTO_OUTRA_EMPRESA'; nivel := 'atencao';
      texto := 'Esta convenção não está ligada à empresa do colaborador. Confira a base territorial e a empresa.';
      base_legal := 'CF art. 8º, II; CLT art. 581';
      RETURN NEXT;
    END IF;
  END IF;
END $fn$;

-- Restrições do colaborador ao banco de horas (aprendiz, menor, insalubre)
CREATE OR REPLACE FUNCTION public.ponto_banco_avisos_colaborador(
  p_tenant uuid, p_admissao_id uuid, p_data date DEFAULT CURRENT_DATE)
RETURNS TABLE(codigo text, nivel text, texto text, base_legal text)
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $fn$
DECLARE
  v_a jsonb;
  v_emp uuid;
  v_coletivo boolean;
  v_idade int;
BEGIN
  v_a := (SELECT to_jsonb(a) FROM public.admissoes a WHERE a.id = p_admissao_id AND a.tenant_id = p_tenant);
  IF v_a IS NULL THEN RETURN; END IF;
  v_emp := NULLIF(v_a->>'empresa_id', '')::uuid;
  v_coletivo := public.ponto_tem_coletivo_vigente(p_tenant, v_emp, p_data);

  IF COALESCE((v_a->>'contrato_aprendiz')::boolean, false) THEN
    codigo := 'APRENDIZ_SEM_BANCO'; nivel := 'bloqueio';
    texto := 'Aprendiz não pode ter banco de horas nem compensação de jornada. Mantenha-o fora do banco; '
          || 'o cálculo passará a excluí-lo automaticamente na próxima etapa.';
    base_legal := 'CLT art. 432';
    RETURN NEXT;
  END IF;

  IF NULLIF(v_a->>'data_nascimento', '') IS NOT NULL THEN
    v_idade := EXTRACT(YEAR FROM age(p_data, (v_a->>'data_nascimento')::date))::int;
    IF v_idade < 18 AND NOT v_coletivo THEN
      codigo := 'MENOR_SEM_COLETIVO'; nivel := 'atencao';
      texto := 'Menor de 18 anos só pode compensar horas se houver convenção ou acordo coletivo vigente. Cadastre a CCT/ACT ou mantenha-o fora do banco.';
      base_legal := 'CLT art. 413, I';
      RETURN NEXT;
    END IF;
  END IF;

  IF COALESCE((v_a->>'funcao_insalubre')::boolean, false) AND NOT v_coletivo THEN
    codigo := 'INSALUBRE_SEM_LICENCA'; nivel := 'atencao';
    texto := 'Atividade insalubre: prorrogar ou compensar jornada exige licença prévia do Ministério do Trabalho, '
          || 'salvo se a convenção/acordo coletivo autorizar ou se a escala for 12x36.';
    base_legal := 'CLT art. 60; art. 611-A, XIII; art. 59-A';
    RETURN NEXT;
  END IF;
END $fn$;

-- Sinal para o cálculo (Fatia 2): o colaborador não pode ter banco na data?
CREATE OR REPLACE FUNCTION public.ponto_banco_colaborador_bloqueado(p_tenant uuid, p_cpf text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.admissoes a
    WHERE a.tenant_id = p_tenant
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g') = regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g')
      AND a.status = 'concluido'
      AND COALESCE(a.contrato_aprendiz, false)
  )
$fn$;
COMMENT ON FUNCTION public.ponto_banco_colaborador_bloqueado(uuid, text) IS
  'true quando o vínculo ativo é de aprendiz (CLT art. 432: vedadas prorrogação e compensação). Fatia 1: só sinaliza (avisos e tela); o cálculo passa a respeitar na Fatia 2.';

-- Avisos da configuração do banco (sem bloqueio). Recebe a configuração como
-- jsonb para a tela avisar ENQUANTO o RH edita (antes de salvar).
CREATE OR REPLACE FUNCTION public.ponto_banco_config_avisos_previa(p_tenant uuid, p_config jsonb)
RETURNS TABLE(codigo text, nivel text, texto text, base_legal text)
LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $fn$
DECLARE
  v_emp uuid := NULLIF(p_config->>'empresa_id', '')::uuid;
  v_mod text := COALESCE(NULLIF(p_config->>'modalidade', ''), 'mensal');
  v_ref date := GREATEST(CURRENT_DATE, COALESCE(NULLIF(p_config->>'data_inicio', '')::date, CURRENT_DATE));
  v_prazo int := COALESCE(NULLIF(p_config->>'prazo_compensacao_dias', '')::int, 0);
  v_coletivo boolean;
  v_individual boolean;
  v_n int;
BEGIN
  IF COALESCE(p_config->>'tipo', '') = 'sem_banco' THEN RETURN; END IF;

  v_coletivo := public.ponto_tem_coletivo_vigente(p_tenant, v_emp, v_ref);
  v_individual := EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id = p_tenant AND ac.tipo = 'individual'
      AND public.ponto_acordo_vigente_em(ac.id, v_ref)
      AND (v_emp IS NULL OR public.ponto_acordo_cobre_empresa(ac.id, v_emp)));

  IF v_mod = 'anual' AND NOT v_coletivo THEN
    codigo := 'ANUAL_SEM_COLETIVO'; nivel := 'atencao';
    texto := 'Banco anual só vale com convenção ou acordo coletivo. Não há CCT/ACT vigente cadastrada para esta empresa; '
          || 'sem ela, a Justiça pode mandar pagar todas as horas como extras.';
    base_legal := 'CLT art. 59, §2º; art. 611-A, II';
    RETURN NEXT;
  END IF;

  IF v_mod = 'semestral' AND NOT v_individual AND NOT v_coletivo THEN
    codigo := 'SEMESTRAL_SEM_ACORDO'; nivel := 'atencao';
    texto := 'Banco semestral exige acordo individual ESCRITO assinado pelo colaborador (ou CCT/ACT). '
          || 'Cadastre o modelo do acordo em Convenções e acordos.';
    base_legal := 'CLT art. 59, §5º';
    RETURN NEXT;
  END IF;

  IF v_prazo > (CASE v_mod WHEN 'mensal' THEN 31 WHEN 'semestral' THEN 183 ELSE 366 END) THEN
    codigo := 'PRAZO_ACIMA_MODALIDADE'; nivel := 'atencao';
    texto := format('O prazo de compensação (%s dias) passa do máximo do banco %s. Revise a modalidade ou o prazo.', v_prazo, v_mod);
    base_legal := 'CLT art. 59, §§2º, 5º e 6º';
    RETURN NEXT;
  END IF;

  IF COALESCE(p_config->>'negativo_fim_ciclo', 'zerar') IN ('descontar', 'transportar') AND NOT v_coletivo THEN
    codigo := 'NEGATIVO_FIM_CICLO_SEM_COLETIVO'; nivel := 'atencao';
    texto := CASE p_config->>'negativo_fim_ciclo'
               WHEN 'descontar' THEN 'Descontar do salário as horas negativas no fim do ciclo'
               ELSE 'Levar as horas negativas para o próximo ciclo' END
          || ' só é seguro com previsão em convenção ou acordo coletivo vigente. Hoje não há CCT/ACT cadastrada.';
    base_legal := 'CLT art. 462; TST RR-116-23.2015.5.09.0513; STF Tema 1046';
    RETURN NEXT;
  END IF;

  IF COALESCE(p_config->>'negativo_rescisao_sem_justa_causa', 'zerar') = 'descontar' THEN
    codigo := 'RESCISAO_SEM_JUSTA_CAUSA_DESCONTO'; nivel := 'forte';
    texto := 'Na dispensa sem justa causa, quem decidiu encerrar o contrato foi a empresa: as horas que o colaborador '
          || 'ficou devendo não devem ser descontadas. O risco do negócio é do empregador.';
    base_legal := 'CLT art. 2º; art. 462';
    RETURN NEXT;
  END IF;

  IF COALESCE(p_config->>'negativo_rescisao_fim_contrato', 'zerar') = 'descontar' THEN
    codigo := 'RESCISAO_FIM_CONTRATO_DESCONTO'; nivel := 'forte';
    texto := 'No fim do contrato de experiência ou prazo determinado, descontar horas negativas transfere ao '
          || 'colaborador um risco que é da empresa.';
    base_legal := 'CLT art. 2º; art. 462';
    RETURN NEXT;
  END IF;

  IF (COALESCE(p_config->>'negativo_rescisao_pedido_demissao', 'zerar') = 'descontar'
      OR COALESCE(p_config->>'negativo_rescisao_justa_causa', 'zerar') = 'descontar')
     AND NOT v_coletivo THEN
    codigo := 'RESCISAO_DESCONTO_SEM_COLETIVO'; nivel := 'atencao';
    texto := 'Descontar horas negativas no pedido de demissão ou na justa causa só com previsão em CCT/ACT vigente, '
          || 'e limitado a uma remuneração.';
    base_legal := 'CLT art. 462; art. 477, §5º';
    RETURN NEXT;
  END IF;

  IF COALESCE(p_config->>'negativo_rescisao_acordo_484a', 'zerar') = 'descontar' THEN
    codigo := 'RESCISAO_484A_DESCONTO'; nivel := 'atencao';
    texto := 'No desligamento por acordo (art. 484-A) o desconto de horas negativas ainda não tem entendimento firme nos tribunais. Prefira zerar.';
    base_legal := 'CLT art. 484-A; art. 462';
    RETURN NEXT;
  END IF;

  IF NOT COALESCE(NULLIF(p_config->>'teto_desconto_rescisao_uma_remuneracao', '')::boolean, true) THEN
    codigo := 'TETO_RESCISAO_DESLIGADO'; nivel := 'atencao';
    texto := 'Na rescisão, os descontos somados não podem passar de uma remuneração do colaborador. Mantenha o teto ligado.';
    base_legal := 'CLT art. 477, §5º';
    RETURN NEXT;
  END IF;

  IF COALESCE(p_config->>'falta_injustificada_destino', 'folha') IN ('banco', 'banco_se_houver_saldo') THEN
    codigo := 'FALTA_NO_BANCO'; nivel := 'info';
    texto := 'Ao debitar a falta no banco, o sistema não desconta o dia nem o DSR dessa falta (não cobrar duas vezes). '
          || 'O acordo precisa prever a compensação de faltas.';
    base_legal := 'Lei 605/49 art. 6º; CLT art. 462';
    RETURN NEXT;
  END IF;

  IF COALESCE(NULLIF(p_config->>'permite_saldo_negativo', '')::boolean, false)
     AND NULLIF(p_config->>'limite_saldo_negativo_min', '') IS NULL THEN
    codigo := 'NEGATIVO_SEM_LIMITE'; nivel := 'atencao';
    texto := 'Saldo negativo grande pode acabar perdoado: horas que a empresa deixou de dar trabalho não podem ser descontadas. '
          || 'Defina um limite para o saldo negativo.';
    base_legal := 'CLT art. 2º';
    RETURN NEXT;
  END IF;

  IF NULLIF(p_config->>'instrumento_id', '') IS NOT NULL THEN
    codigo := 'REGRA_POR_INSTRUMENTO_EM_BREVE'; nivel := 'info';
    texto := 'Regra presa a uma convenção ainda não entra no cálculo: até a próxima etapa, quem vale para o colaborador são as outras regras ativas da empresa/escala.';
    base_legal := '';
    RETURN NEXT;
  END IF;

  -- Colaboradores com restrição ao banco no escopo desta regra
  v_n := (SELECT count(*) FROM public.admissoes a
           WHERE a.tenant_id = p_tenant AND a.status = 'concluido'
             AND (v_emp IS NULL OR a.empresa_id = v_emp)
             AND COALESCE(a.contrato_aprendiz, false));
  IF v_n > 0 THEN
    codigo := 'APRENDIZES_NO_ESCOPO'; nivel := 'bloqueio';
    texto := format('%s aprendiz(es) ativo(s) nesta empresa. Aprendiz não pode ter banco de horas: hoje o cálculo ainda os inclui; '
          || 'a próxima etapa vai excluí-los automaticamente. Até lá, confira o saldo deles.', v_n);
    base_legal := 'CLT art. 432';
    RETURN NEXT;
  END IF;

  IF NOT v_coletivo THEN
    v_n := (SELECT count(*) FROM public.admissoes a
             WHERE a.tenant_id = p_tenant AND a.status = 'concluido'
               AND (v_emp IS NULL OR a.empresa_id = v_emp)
               AND a.data_nascimento IS NOT NULL
               AND a.data_nascimento > (v_ref - INTERVAL '18 years')::date);
    IF v_n > 0 THEN
      codigo := 'MENORES_SEM_COLETIVO'; nivel := 'atencao';
      texto := format('%s colaborador(es) menor(es) de 18 anos: compensação só com CCT/ACT vigente.', v_n);
      base_legal := 'CLT art. 413, I';
      RETURN NEXT;
    END IF;
    v_n := (SELECT count(*) FROM public.admissoes a
             WHERE a.tenant_id = p_tenant AND a.status = 'concluido'
               AND (v_emp IS NULL OR a.empresa_id = v_emp)
               AND COALESCE(a.funcao_insalubre, false));
    IF v_n > 0 THEN
      codigo := 'INSALUBRES_SEM_COLETIVO'; nivel := 'atencao';
      texto := format('%s colaborador(es) em função insalubre: compensar jornada exige licença prévia do Ministério do Trabalho, '
            || 'salvo CCT/ACT que autorize ou escala 12x36.', v_n);
      base_legal := 'CLT art. 60; art. 611-A, XIII; art. 59-A';
      RETURN NEXT;
    END IF;
  END IF;
END $fn$;

COMMENT ON FUNCTION public.ponto_banco_config_avisos_previa(uuid, jsonb) IS
  'Avisos (sem bloqueio) da configuração do banco de horas, a partir do jsonb da configuração (tela avisa antes de salvar). Níveis: info | atencao | forte | bloqueio (este último só sinaliza; o cálculo respeita a partir da Fatia 2).';

CREATE OR REPLACE FUNCTION public.ponto_banco_config_avisos(p_tenant uuid, p_config_id uuid)
RETURNS TABLE(codigo text, nivel text, texto text, base_legal text)
LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  SELECT av.*
  FROM public.ponto_banco_horas_config c
  CROSS JOIN LATERAL public.ponto_banco_config_avisos_previa(p_tenant, to_jsonb(c)) av
  WHERE c.id = p_config_id AND c.tenant_id = p_tenant
$fn$;

-- Sugestão de colaboradores para um instrumento (por CBO ou palavra do cargo).
-- Só sugere: a confirmação é manual na tela.
CREATE OR REPLACE FUNCTION public.ponto_instrumento_sugestoes(p_tenant uuid, p_instrumento_id uuid)
RETURNS TABLE(admissao_id uuid, nome text, cargo text, cbo text, empresa_id uuid,
              motivo text, ja_vinculado boolean, aprendiz boolean)
LANGUAGE sql STABLE SET search_path TO 'public' AS $fn$
  WITH ins AS MATERIALIZED (
    SELECT ac.id,
           ARRAY(SELECT regexp_replace(x, '[^0-9]', '', 'g') FROM unnest(ac.cbos_categoria) x
                  WHERE regexp_replace(x, '[^0-9]', '', 'g') <> '') AS cbos,
           ARRAY(SELECT lower(btrim(x)) FROM unnest(ac.cargos_categoria) x WHERE btrim(x) <> '') AS cargos
    FROM public.ponto_acordos ac
    WHERE ac.id = p_instrumento_id AND ac.tenant_id = p_tenant
  )
  SELECT a.id, a.nome_completo, a.cargo, a.cbo, a.empresa_id,
         CASE WHEN EXISTS (SELECT 1 FROM unnest(ins.cbos) c
                            WHERE regexp_replace(COALESCE(a.cbo, ''), '[^0-9]', '', 'g') LIKE c || '%')
              THEN 'CBO ' || COALESCE(a.cbo, '')
              ELSE 'Cargo "' || COALESCE(a.cargo, '') || '"' END,
         EXISTS (SELECT 1 FROM public.ponto_instrumento_colaborador v
                  WHERE v.admissao_id = a.id AND v.instrumento_id = ins.id
                    AND (v.data_fim IS NULL OR v.data_fim >= CURRENT_DATE)),
         COALESCE(a.contrato_aprendiz, false)
  FROM ins
  JOIN public.admissoes a ON a.tenant_id = p_tenant AND a.status = 'concluido'
  WHERE (
          EXISTS (SELECT 1 FROM unnest(ins.cbos) c
                   WHERE regexp_replace(COALESCE(a.cbo, ''), '[^0-9]', '', 'g') LIKE c || '%')
       OR EXISTS (SELECT 1 FROM unnest(ins.cargos) k WHERE lower(COALESCE(a.cargo, '')) LIKE '%' || k || '%')
        )
  ORDER BY a.nome_completo
$fn$;

-- Trazer uma CCT da configuração antiga (ponto_cct_config) para o cadastro
-- novo. Cria o instrumento INATIVO: ativar é decisão do RH, porque um
-- instrumento coletivo ativo já conta para 12x36 e REP alternativo.
CREATE OR REPLACE FUNCTION public.ponto_importar_cct_legado(p_cct_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_c jsonb;
  v_id uuid := gen_random_uuid();
BEGIN
  v_c := (SELECT to_jsonb(c) FROM public.ponto_cct_config c WHERE c.id = p_cct_id);
  IF v_c IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_encontrada');
  END IF;
  IF NULLIF(v_c->>'instrumento_id', '') IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.ponto_acordos WHERE id = (v_c->>'instrumento_id')::uuid) THEN
    RETURN jsonb_build_object('ok', true, 'instrumento_id', v_c->>'instrumento_id', 'ja_importada', true);
  END IF;

  INSERT INTO public.ponto_acordos
    (id, tenant_id, empresa_id, tipo, titulo, vigencia_inicio, vigencia_fim, observacoes, ativo,
     sindicato_laboral, categoria, empresa_representada)
  VALUES
    (v_id, (v_c->>'tenant_id')::uuid, NULLIF(v_c->>'empresa_id', '')::uuid, 'cct',
     COALESCE(NULLIF(v_c->>'nome', ''), 'CCT importada'),
     NULLIF(v_c->>'vigencia_inicio', '')::date, NULLIF(v_c->>'vigencia_fim', '')::date,
     'Trazida da configuração antiga de CCT. Categoria informada lá: ' || COALESCE(NULLIF(v_c->>'categoria_profissional', ''), '—'),
     false, NULLIF(v_c->>'sindicato', ''), 'preponderante', true);

  UPDATE public.ponto_cct_config SET instrumento_id = v_id WHERE id = p_cct_id;
  RETURN jsonb_build_object('ok', true, 'instrumento_id', v_id, 'ja_importada', false);
END $fn$;

GRANT EXECUTE ON FUNCTION public.ponto_acordo_cobre_empresa(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_acordo_vigente_em(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_tem_coletivo_vigente(uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_instrumento_do_colaborador(uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_instrumento_avisos_vinculo(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_banco_avisos_colaborador(uuid, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_banco_colaborador_bloqueado(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_banco_config_avisos_previa(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_banco_config_avisos(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_instrumento_sugestoes(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ponto_importar_cct_legado(uuid) TO authenticated;

-- ── 6) Regime vigente: 'sem_banco' é sem banco; respeita data_fim ──────────
-- Única versão da função (20260819260000), sem remendos injetados: CREATE OR
-- REPLACE integral. Diferenças marcadas com [banco-f1].
CREATE OR REPLACE FUNCTION public.ponto_banco_regime_vigente(
  p_tenant_id      uuid,
  p_colaborador_cpf text,
  p_colaborador_id text,
  p_ref_data       date
)
RETURNS public.ponto_banco_horas_config
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf       text := regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g');
  v_escala_id uuid;
  v_empresa   uuid;
  v_cfg       public.ponto_banco_horas_config;
BEGIN
  -- Escala vigente do colaborador na data (para casar a config por escala).
  v_escala_id := (
    SELECT a.escala_id
    FROM public.ponto_escala_atribuicoes a
    WHERE a.tenant_id = p_tenant_id
      AND (regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
           OR a.colaborador_id::text = p_colaborador_id)
      AND COALESCE(a.ativa, true) = true
      AND (a.data_inicio IS NULL OR a.data_inicio <= p_ref_data)
      AND (a.data_fim IS NULL OR a.data_fim >= p_ref_data)
    ORDER BY a.data_inicio DESC NULLS LAST
    LIMIT 1);

  v_empresa := public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf);

  -- Regime vigente que cobre o vínculo: específico da escala > da empresa >
  -- do tenant. Se o regime exige acordo individual ou CCT/ACT, precisa do
  -- instrumento anexado (acordo_id) para valer.
  v_cfg := (
    SELECT c
    FROM public.ponto_banco_horas_config c
    WHERE c.tenant_id = p_tenant_id
      AND COALESCE(c.ativo, false) = true
      AND (c.data_inicio IS NULL OR c.data_inicio <= p_ref_data)
      AND (c.data_fim IS NULL OR c.data_fim >= p_ref_data)          -- [banco-f1] vigência
      AND c.instrumento_id IS NULL                                   -- [banco-f1] regra por instrumento: Fatia 2
      AND (c.escala_id IS NULL OR c.escala_id = v_escala_id)
      AND (c.empresa_id IS NULL OR c.empresa_id = v_empresa)
      AND (
        (COALESCE(c.exige_acordo_individual, false) = false
         AND COALESCE(c.exige_cct_act, false) = false)
        OR c.acordo_id IS NOT NULL
      )
    ORDER BY (c.escala_id IS NOT NULL) DESC,
             (c.empresa_id IS NOT NULL) DESC,
             c.data_inicio DESC NULLS LAST
    LIMIT 1);

  -- [banco-f1] A regra mais específica diz "sem banco": não há regime.
  -- Antes, uma config 'sem_banco' ativa contava como regime de banco.
  IF v_cfg.id IS NOT NULL AND v_cfg.tipo = 'sem_banco' THEN
    RETURN NULL;
  END IF;

  RETURN v_cfg;  -- linha com todos os campos NULL quando não há regime vigente
END;
$fn$;

COMMENT ON FUNCTION public.ponto_banco_regime_vigente(uuid, text, text, date) IS
  'Resolve o regime de banco de horas vigente do vinculo na data (config especifica da escala prevalece sobre a da empresa e a do tenant; exige acordo/CCT anexado quando o regime marca que o exige). Banco configuravel F1: a regra mais especifica do tipo sem_banco significa SEM regime; respeita data_fim; ignora regras presas a instrumento (Fatia 2). Retorna a linha de ponto_banco_horas_config, ou linha nula quando nao ha regime. CLT art. 59 §§2/5.';
