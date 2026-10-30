-- ============================================================================
-- SCRIPT DE ENTREGA — Ponto: Banco de horas configurável, FATIA 1 (cadastros)
-- Mesmo SQL para HOMOLOGAÇÃO e, depois de aprovado, PRODUÇÃO. Cole INTEIRO no
-- SQL Editor. Roda em UMA transação; idempotente (pode rodar duas vezes).
--
-- Equivale às migrations:
--   20261030223500_ponto_banco_configuravel_f1.sql
--   20261030223600_qa_ponto_banco_configuravel_f1.sql
--
-- O QUE MUDA
--   · Convenções e acordos: N instrumentos por conta (ponto_acordos ampliado),
--     empresas abrangidas (ponto_acordo_empresas), vínculo do colaborador
--     (ponto_instrumento_colaborador) e precedência por colaborador.
--   · ponto_banco_horas_config ganha modalidade/ciclo/fim de ciclo/rescisão/
--     débitos/fatores/limites/extrato — CADASTRO, o cálculo ainda não lê.
--   · Bloqueios legais (gatilho + CHECK) e avisos sem bloqueio.
--   · ÚNICA mudança de cálculo: ponto_banco_regime_vigente passa a tratar a
--     regra "sem_banco" como SEM banco e a respeitar a data de fim. Quem tinha
--     uma regra sem_banco ativa como a mais específica deixa de acumular banco
--     (a coluna configs_sem_banco_ativas da conferência mostra quantas são).
--
-- ANTES DE ALTERAR, guarda cópia de ponto_banco_horas_config e ponto_cct_config
-- no schema privado backup (backup.ponto_bh_config_20261030 e
-- backup.ponto_cct_config_20261030). Nenhuma linha existente é alterada aqui:
-- só ganham colunas novas com padrão. Para desfazer o regime vigente, recrie a
-- função a partir de 20260819260000_ponto_onda5_banco_instrumento_vigente.sql.
--
-- Tabelas criadas por EXECUTE e atribuição só por subconsulta escalar (o
-- auxiliar de RLS automático do editor não dispara). Termina com UM SELECT.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 0) Backup (schema privado backup) ──────────────────────────────────────
DO $bkp$
BEGIN
  IF to_regnamespace('backup') IS NULL THEN
    RAISE NOTICE 'ATENCAO: schema backup ausente; rode antes docs/script_backup_schema_privado.sql. Backup pulado.';
    RETURN;
  END IF;
  IF to_regclass('backup.ponto_bh_config_20261030') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_bh_config_20261030 AS SELECT * FROM public.ponto_banco_horas_config';
  END IF;
  IF to_regclass('backup.ponto_cct_config_20261030') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_cct_config_20261030 AS SELECT * FROM public.ponto_cct_config';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: backup nao gravado: %', SQLERRM;
END $bkp$;

-- ════════ PARTE 1: estrutura, funções e regime vigente ════════
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

-- ════════ PARTE 2: casos de teste do motor (PONTO-520..525) ════════
-- ============================================================================
-- QA — BANCO DE HORAS CONFIGURÁVEL, FATIA 1 (casos api)
--
--   PONTO-520  precedência do instrumento do colaborador (ACT > vínculo > CCT preponderante)
--   PONTO-521  vínculo ao instrumento: aviso da Súmula 374 e sem sobreposição de vigência
--   PONTO-522  avisos da configuração do banco (sem bloqueio) e sumiço com CCT/ACT vigente
--   PONTO-523  bloqueios legais da configuração + padrões que reproduzem o comportamento de hoje
--   PONTO-524  ponto_banco_regime_vigente: sem_banco é sem banco, respeita data_fim,
--              ignora regra presa a instrumento
--   PONTO-525  restrições do colaborador: aprendiz (bloqueio), menor e insalubre (aviso)
--
-- Rotinas no cercado (tenant sandbox), desfeitas pelo motor ao fim
-- (qa_executar_descartavel). Atribuição só por subconsulta escalar
-- (padrão do SQL Editor de produção). Idempotente.
-- ============================================================================


-- Ajudante: id da admissão do cercado pelo CPF-semente (cria se faltar).
CREATE OR REPLACE FUNCTION public.qa_bhf1_admissao(p_nome text, p_semente int, p_empresa uuid)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_cpf text;
BEGIN
  v_cpf := public.qa_ponto_admissao(p_nome, p_semente, p_empresa, DATE '2026-01-01');
  RETURN (SELECT a.id FROM public.admissoes a
           WHERE a.tenant_id = public.qa_sandbox_tenant_id() AND a.cpf = v_cpf
           ORDER BY (a.status = 'concluido') DESC, a.created_at DESC NULLS LAST LIMIT 1);
END $fn$;

-- Ajudante: instrumento no cercado.
CREATE OR REPLACE FUNCTION public.qa_bhf1_instrumento(
  p_tipo text, p_titulo text, p_empresa uuid, p_categoria text DEFAULT 'preponderante',
  p_representada boolean DEFAULT true, p_ini date DEFAULT NULL, p_fim date DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.ponto_acordos
    (id, tenant_id, empresa_id, tipo, titulo, vigencia_inicio, vigencia_fim, ativo, categoria, empresa_representada)
  VALUES (v_id, public.qa_sandbox_tenant_id(), p_empresa, p_tipo, p_titulo, p_ini, p_fim, true, p_categoria, p_representada);
  RETURN v_id;
END $fn$;

-- ── PONTO-520 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_520()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_adm uuid; v_cct uuid; v_dif uuid; v_act uuid;
  d date := DATE '2026-06-01';
  r0 jsonb; r1 jsonb; r2 jsonb; r3 jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Precedencia', '11222333052068');
  v_adm := public.qa_bhf1_admissao('[QA-BHF1] Colab Precedencia', 5201, v_emp);

  r.passo_ordem := 1;
  r.passo_acao := 'Resolver o instrumento sem nada cadastrado; depois com CCT preponderante, com CCT diferenciada vinculada e com ACT da empresa';
  r.esperado := 'nenhum -> cct_preponderante -> vinculo_colaborador (com alerta Súm. 374) -> act_empresa';

  r0 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_cct := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT principal', v_emp, 'preponderante', true, DATE '2026-01-01', DATE '2026-12-31');
  r1 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_dif := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT diferenciada', NULL, 'diferenciada', false, DATE '2026-01-01', NULL);
  INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
  VALUES (v_t, v_adm, v_dif, DATE '2026-01-01');
  r2 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);
  v_act := public.qa_bhf1_instrumento('act', '[QA-BHF1] ACT da empresa', v_emp, 'preponderante', true, DATE '2026-01-01', NULL);
  r3 := public.ponto_instrumento_do_colaborador(v_t, v_adm, d);

  IF r0->>'origem' <> 'nenhum' THEN
    r.situacao := 'falhou'; r.obtido := 'Sem instrumento devia vir nenhum e veio ' || r0::text;
  ELSIF r1->>'origem' <> 'cct_preponderante' OR (r1->>'instrumento_id')::uuid <> v_cct THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT da empresa devia vir cct_preponderante e veio ' || r1::text;
  ELSIF r2->>'origem' <> 'vinculo_colaborador' OR (r2->>'instrumento_id')::uuid <> v_dif
        OR NOT COALESCE((r2->>'alerta_sumula_374')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Com vínculo à diferenciada devia vir vinculo_colaborador com alerta 374 e veio ' || r2::text;
  ELSIF r3->>'origem' <> 'act_empresa' OR (r3->>'instrumento_id')::uuid <> v_act THEN
    r.situacao := 'falhou'; r.obtido := 'Com ACT da empresa devia prevalecer o ACT (CLT 620) e veio ' || r3::text;
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Precedência correta: nenhum, CCT preponderante, vínculo (com alerta Súm. 374), ACT da empresa.';
  END IF;
  r.detalhe := jsonb_build_object('r0', r0, 'r1', r1, 'r2', r2, 'r3', r3);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-521 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_521()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_adm uuid; v_dif uuid; v_ok uuid; v_venc uuid;
  v_av_dif text[]; v_av_ok text[]; v_av_venc text[];
  v_sobrepos_recusada boolean := false;
  v_sequencial_ok boolean := false;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Vinculo', '11222333052149');
  v_adm := public.qa_bhf1_admissao('[QA-BHF1] Colab Vinculo', 5211, v_emp);
  v_dif := public.qa_bhf1_instrumento('cct', '[QA-BHF1] Dif nao representada', NULL, 'diferenciada', false);
  v_ok  := public.qa_bhf1_instrumento('cct', '[QA-BHF1] Dif representada', NULL, 'diferenciada', true);
  v_venc := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT vencida', v_emp, 'preponderante', true, DATE '2024-01-01', DATE '2024-12-31');

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos ao vincular: diferenciada sem representação, diferenciada representada, instrumento vencido';
  r.esperado := 'SUMULA_374 só na não representada; INSTRUMENTO_FORA_VIGENCIA na vencida';
  v_av_dif := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_dif, v_adm));
  v_av_ok := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_ok, v_adm));
  v_av_venc := ARRAY(SELECT codigo FROM public.ponto_instrumento_avisos_vinculo(v_t, v_venc, v_adm));

  r.passo_ordem := 2;
  r.passo_acao := 'Vincular o colaborador e tentar um segundo vínculo no mesmo período; depois um vínculo sequencial';
  r.esperado := 'Sobreposição recusada; sequencial aceito';
  INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio, data_fim)
  VALUES (v_t, v_adm, v_dif, DATE '2026-01-01', DATE '2026-06-30');
  BEGIN
    INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
    VALUES (v_t, v_adm, v_ok, DATE '2026-03-01');
  EXCEPTION WHEN check_violation THEN v_sobrepos_recusada := true;
  END;
  BEGIN
    INSERT INTO public.ponto_instrumento_colaborador (tenant_id, admissao_id, instrumento_id, data_inicio)
    VALUES (v_t, v_adm, v_ok, DATE '2026-07-01');
    v_sequencial_ok := true;
  EXCEPTION WHEN OTHERS THEN v_sequencial_ok := false;
  END;

  IF NOT ('SUMULA_374' = ANY (v_av_dif)) THEN
    r.situacao := 'falhou'; r.obtido := 'Diferenciada sem representação não avisou a Súmula 374: ' || array_to_string(v_av_dif, ',');
  ELSIF 'SUMULA_374' = ANY (v_av_ok) THEN
    r.situacao := 'falhou'; r.obtido := 'Diferenciada representada avisou a Súmula 374 indevidamente';
  ELSIF NOT ('INSTRUMENTO_FORA_VIGENCIA' = ANY (v_av_venc)) THEN
    r.situacao := 'falhou'; r.obtido := 'Instrumento vencido não avisou: ' || array_to_string(v_av_venc, ',');
  ELSIF NOT v_sobrepos_recusada THEN
    r.situacao := 'falhou'; r.obtido := 'Dois vínculos no mesmo período foram aceitos';
  ELSIF NOT v_sequencial_ok THEN
    r.situacao := 'falhou'; r.obtido := 'Vínculo sequencial (sem sobreposição) foi recusado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Aviso da Súmula 374 só quando não representada; vencido avisado; sobreposição recusada; sequencial aceito.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-522 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_522()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid;
  v_anual jsonb; v_sem jsonb;
  a1 text[]; a2 text[]; a3 text[]; a4 text[];
  v_forte text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Avisos', '11222333052220');

  v_anual := jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp, 'modalidade', 'anual',
    'prazo_compensacao_dias', 365, 'negativo_fim_ciclo', 'descontar',
    'negativo_rescisao_sem_justa_causa', 'descontar', 'falta_injustificada_destino', 'banco',
    'permite_saldo_negativo', true);
  v_sem := jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp, 'modalidade', 'semestral',
    'prazo_compensacao_dias', 180, 'permite_saldo_negativo', true, 'limite_saldo_negativo_min', 600);

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos sem CCT/ACT vigente: banco anual com desconto do negativo e desconto na dispensa sem justa causa; banco semestral sem acordo';
  r.esperado := 'ANUAL_SEM_COLETIVO, NEGATIVO_FIM_CICLO_SEM_COLETIVO, RESCISAO_SEM_JUSTA_CAUSA_DESCONTO (forte), FALTA_NO_BANCO, NEGATIVO_SEM_LIMITE; SEMESTRAL_SEM_ACORDO';
  a1 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_anual));
  a2 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_sem));
  v_forte := (SELECT nivel FROM public.ponto_banco_config_avisos_previa(v_t, v_anual)
               WHERE codigo = 'RESCISAO_SEM_JUSTA_CAUSA_DESCONTO' LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Cadastrar uma CCT vigente para a empresa e reavaliar';
  r.esperado := 'Somem os avisos que dependem de CCT/ACT; o aviso forte da dispensa sem justa causa continua';
  PERFORM public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT vigente', v_emp);
  a3 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_anual));
  a4 := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t, v_sem));

  IF NOT (a1 @> ARRAY['ANUAL_SEM_COLETIVO','NEGATIVO_FIM_CICLO_SEM_COLETIVO','RESCISAO_SEM_JUSTA_CAUSA_DESCONTO','FALTA_NO_BANCO','NEGATIVO_SEM_LIMITE']) THEN
    r.situacao := 'falhou'; r.obtido := 'Sem CCT faltou aviso. Veio: ' || array_to_string(a1, ',');
  ELSIF v_forte IS DISTINCT FROM 'forte' THEN
    r.situacao := 'falhou'; r.obtido := 'Desconto na dispensa sem justa causa devia ser aviso forte e veio ' || COALESCE(v_forte, 'nulo');
  ELSIF NOT ('SEMESTRAL_SEM_ACORDO' = ANY (a2)) OR 'NEGATIVO_SEM_LIMITE' = ANY (a2) THEN
    r.situacao := 'falhou'; r.obtido := 'Semestral: esperado SEMESTRAL_SEM_ACORDO e sem NEGATIVO_SEM_LIMITE (há limite). Veio: ' || array_to_string(a2, ',');
  ELSIF a3 && ARRAY['ANUAL_SEM_COLETIVO','NEGATIVO_FIM_CICLO_SEM_COLETIVO'] OR 'SEMESTRAL_SEM_ACORDO' = ANY (a4) THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT vigente os avisos deviam sumir. Veio: ' || array_to_string(a3, ',') || ' | ' || array_to_string(a4, ',');
  ELSIF NOT ('RESCISAO_SEM_JUSTA_CAUSA_DESCONTO' = ANY (a3)) THEN
    r.situacao := 'falhou'; r.obtido := 'O aviso forte da dispensa sem justa causa não pode depender de CCT. Veio: ' || array_to_string(a3, ',');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Avisos corretos sem CCT; somem com CCT vigente; o aviso forte da rescisão permanece.';
  END IF;
  r.detalhe := jsonb_build_object('sem_cct_anual', a1, 'sem_cct_semestral', a2, 'com_cct_anual', a3, 'com_cct_semestral', a4);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-523 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_523()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_id uuid := gen_random_uuid();
  v_pos_bloq boolean := false; v_teto_bloq boolean := false;
  v_ciclo_bloq boolean := false; v_ciclo_ok boolean := false;
  v_cols_proibidas text; v_row jsonb; v_nat text;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  r.passo_ordem := 1;
  r.passo_acao := 'Gravar config com positivo zerado no vencimento, teto de crédito 121 min e semestral com fechamento só em dezembro';
  r.esperado := 'As três gravações recusadas; semestral com junho e dezembro aceito';
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, forma_pagamento_vencer, ativo)
    VALUES (v_t, 'individual', 'zerar', false);
  EXCEPTION WHEN check_violation THEN v_pos_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, teto_credito_diario_min, ativo)
    VALUES (v_t, 'individual', 121, false);
  EXCEPTION WHEN check_violation THEN v_teto_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, modalidade, meses_fechamento, ativo)
    VALUES (v_t, 'individual', 'semestral', ARRAY[12], false);
  EXCEPTION WHEN check_violation THEN v_ciclo_bloq := true;
  END;
  BEGIN
    INSERT INTO public.ponto_banco_horas_config (tenant_id, tipo, modalidade, meses_fechamento, ativo)
    VALUES (v_t, 'individual', 'semestral', ARRAY[6,12], false);
    v_ciclo_ok := true;
  EXCEPTION WHEN OTHERS THEN v_ciclo_ok := false;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar config mínima e conferir os padrões; procurar opção de debitar atestado/ausência legal; conferir natureza do débito';
  r.esperado := 'Padrões = hoje (mensal, fixo, 12 meses, teto 120, fatores 1, falta na folha, atraso no banco, negativo zerado, teto de rescisão ligado, extrato ligado); nenhuma coluna de atestado/ausência legal; natureza_debito aceita só ausencia_empregado/dispensa_empresa';
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, ativo) VALUES (v_id, v_t, 'individual', false);
  v_row := (SELECT to_jsonb(c) FROM public.ponto_banco_horas_config c WHERE c.id = v_id);
  v_cols_proibidas := (SELECT string_agg(column_name, ',') FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'ponto_banco_horas_config'
                          AND column_name ~ '(atestad|ausencia_legal|473|licenca)');
  v_nat := (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'ponto_bh_mov_natureza_debito_chk' LIMIT 1);

  IF NOT v_pos_bloq THEN
    r.situacao := 'falhou'; r.obtido := 'Aceitou zerar o saldo positivo no vencimento (devia pagar HE)';
  ELSIF NOT v_teto_bloq THEN
    r.situacao := 'falhou'; r.obtido := 'Aceitou teto de crédito diário acima de 120 min';
  ELSIF NOT v_ciclo_bloq OR NOT v_ciclo_ok THEN
    r.situacao := 'falhou'; r.obtido := format('Coerência do ciclo: dezembro só recusado=%s, junho+dezembro aceito=%s', v_ciclo_bloq, v_ciclo_ok);
  ELSIF v_row->>'modalidade' <> 'mensal' OR v_row->>'tipo_ciclo' <> 'fixo'
        OR jsonb_array_length(v_row->'meses_fechamento') <> 12
        OR (v_row->>'teto_credito_diario_min')::int <> 120
        OR (v_row->>'fator_credito_util')::numeric <> 1 OR (v_row->>'fator_credito_feriado')::numeric <> 1
        OR v_row->>'falta_injustificada_destino' <> 'folha' OR v_row->>'atraso_destino' <> 'banco'
        OR v_row->>'saida_antecipada_destino' <> 'banco' OR v_row->>'negativo_fim_ciclo' <> 'zerar'
        OR v_row->>'negativo_rescisao_sem_justa_causa' <> 'zerar'
        OR NOT (v_row->>'teto_desconto_rescisao_uma_remuneracao')::boolean
        OR NOT (v_row->>'extrato_mensal')::boolean
        OR v_row->>'limite_saldo_acao' <> 'alertar' THEN
    r.situacao := 'falhou'; r.obtido := 'Padrões diferentes do comportamento de hoje: ' || v_row::text;
  ELSIF v_cols_proibidas IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Existe configuração que permitiria debitar ausência legal/atestado: ' || v_cols_proibidas;
  ELSIF v_nat IS NULL OR position('dispensa_empresa' IN v_nat) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Movimentações sem a natureza do débito (ausencia_empregado x dispensa_empresa)';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Bloqueios legais ativos; padrões iguais aos de hoje; sem opção de debitar ausência legal; natureza do débito prevista.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-524 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_524()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_cpf text := public.qa_cpf(5241);
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid();
  v_d uuid := gen_random_uuid(); v_e uuid := gen_random_uuid();
  v_inst uuid;
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_banco_horas_config SET ativo = false WHERE tenant_id = v_t;

  r.passo_ordem := 1;
  r.passo_acao := 'Regra A (banco, desde 2025) e regra B (sem banco, desde 2026) no tenant';
  r.esperado := 'Em 06/2025 vale A; em 06/2026 não há regime (antes, B contava como banco)';
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_a, v_t, 'individual', DATE '2025-01-01', true);
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_b, v_t, 'sem_banco', DATE '2026-01-01', true);
  g1 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2025-06-01')).id;
  g2 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;

  r.passo_ordem := 2;
  r.passo_acao := 'Encerrar A em 31/03/2025 (data_fim)';
  r.esperado := 'Em 06/2025 não há regime';
  UPDATE public.ponto_banco_horas_config SET data_fim = DATE '2025-03-31' WHERE id = v_a;
  g3 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2025-06-01')).id;

  r.passo_ordem := 3;
  r.passo_acao := 'Regra D presa a instrumento (desde 03/2026) e regra E comum (desde 04/2026)';
  r.esperado := 'D é ignorada nesta fatia; em 06/2026 vale E';
  v_inst := public.qa_bhf1_instrumento('cct', '[QA-BHF1] CCT regra', NULL);
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, instrumento_id, ativo)
  VALUES (v_d, v_t, 'individual', DATE '2026-03-01', v_inst, true);
  g4 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;
  INSERT INTO public.ponto_banco_horas_config (id, tenant_id, tipo, data_inicio, ativo)
  VALUES (v_e, v_t, 'individual', DATE '2026-04-01', true);
  g5 := (public.ponto_banco_regime_vigente(v_t, v_cpf, NULL, DATE '2026-06-01')).id;

  IF g1 IS DISTINCT FROM v_a THEN
    r.situacao := 'falhou'; r.obtido := 'Em 06/2025 devia valer a regra A';
  ELSIF g2 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'ACHADO: a regra sem_banco ainda conta como regime de banco (id ' || g2 || ')';
  ELSIF g3 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Regra encerrada (data_fim) ainda vale depois do fim';
  ELSIF g4 IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'Regra presa a instrumento entrou no cálculo antes da Fatia 2';
  ELSIF g5 IS DISTINCT FROM v_e THEN
    r.situacao := 'falhou'; r.obtido := 'Em 06/2026 devia valer a regra E';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'sem_banco = sem regime; data_fim respeitada; regra por instrumento ignorada; demais regras como antes.';
  END IF;
  r.detalhe := jsonb_build_object('g1', g1, 'g2', g2, 'g3', g3, 'g4', g4, 'g5', g5);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-525 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_525()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid; v_emp uuid; v_apr uuid; v_men uuid; v_ins uuid;
  a_apr text[]; a_men text[]; a_ins text[]; a_cfg text[];
  v_nivel_apr text; v_bloq_apr boolean; v_bloq_ins boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  v_emp := public.qa_nova_empresa('[QA-BHF1] Empresa Restricoes', '11222333052300');
  v_apr := public.qa_bhf1_admissao('[QA-BHF1] Aprendiz', 5251, v_emp);
  v_men := public.qa_bhf1_admissao('[QA-BHF1] Menor', 5252, v_emp);
  v_ins := public.qa_bhf1_admissao('[QA-BHF1] Insalubre', 5253, v_emp);
  UPDATE public.admissoes SET contrato_aprendiz = true, data_nascimento = DATE '2006-01-01' WHERE id = v_apr;
  UPDATE public.admissoes SET data_nascimento = (CURRENT_DATE - INTERVAL '17 years')::date WHERE id = v_men;
  UPDATE public.admissoes SET funcao_insalubre = true, data_nascimento = DATE '1990-01-01' WHERE id = v_ins;

  r.passo_ordem := 1;
  r.passo_acao := 'Avisos de banco para aprendiz, menor e insalubre (sem CCT/ACT)';
  r.esperado := 'APRENDIZ_SEM_BANCO (bloqueio), MENOR_SEM_COLETIVO, INSALUBRE_SEM_LICENCA; aprendiz sinalizado para o cálculo; config da empresa avisa APRENDIZES_NO_ESCOPO';
  a_apr := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_apr));
  a_men := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_men));
  a_ins := ARRAY(SELECT codigo FROM public.ponto_banco_avisos_colaborador(v_t, v_ins));
  v_nivel_apr := (SELECT nivel FROM public.ponto_banco_avisos_colaborador(v_t, v_apr) WHERE codigo = 'APRENDIZ_SEM_BANCO' LIMIT 1);
  v_bloq_apr := public.ponto_banco_colaborador_bloqueado(v_t, public.qa_cpf(5251));
  v_bloq_ins := public.ponto_banco_colaborador_bloqueado(v_t, public.qa_cpf(5253));
  a_cfg := ARRAY(SELECT codigo FROM public.ponto_banco_config_avisos_previa(v_t,
             jsonb_build_object('tipo', 'individual', 'empresa_id', v_emp)));

  IF NOT ('APRENDIZ_SEM_BANCO' = ANY (a_apr)) OR v_nivel_apr IS DISTINCT FROM 'bloqueio' THEN
    r.situacao := 'falhou'; r.obtido := 'Aprendiz sem o bloqueio do art. 432: ' || array_to_string(a_apr, ',');
  ELSIF NOT ('MENOR_SEM_COLETIVO' = ANY (a_men)) THEN
    r.situacao := 'falhou'; r.obtido := 'Menor sem aviso do art. 413: ' || array_to_string(a_men, ',');
  ELSIF NOT ('INSALUBRE_SEM_LICENCA' = ANY (a_ins)) THEN
    r.situacao := 'falhou'; r.obtido := 'Insalubre sem aviso do art. 60: ' || array_to_string(a_ins, ',');
  ELSIF NOT v_bloq_apr OR v_bloq_ins THEN
    r.situacao := 'falhou'; r.obtido := format('Sinal para o cálculo: aprendiz=%s (esperado true), insalubre=%s (esperado false)', v_bloq_apr, v_bloq_ins);
  ELSIF NOT (a_cfg @> ARRAY['APRENDIZES_NO_ESCOPO','MENORES_SEM_COLETIVO','INSALUBRES_SEM_COLETIVO']) THEN
    r.situacao := 'falhou'; r.obtido := 'A configuração da empresa não avisou as restrições: ' || array_to_string(a_cfg, ',');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Aprendiz bloqueado (art. 432), menor (art. 413) e insalubre (art. 60) avisados, no colaborador e na configuração.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Documentação dos casos + implementações
DO $doc$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-520..525 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos PONTO-520..525 não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-520',
   'Convenção do colaborador: ACT da empresa > instrumento vinculado > CCT preponderante',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT arts. 511 §§2º e 3º, 570, 581 §2º e 620; Súmula 374 do TST',
   'Com várias convenções na mesma conta, cada colaborador precisa de UMA convenção resolvida por data. O ACT prevalece sobre a CCT; quem tem vínculo próprio (ex.: categoria diferenciada) segue o vínculo; os demais seguem a CCT da atividade principal da empresa.',
   'Cercado de QA; empresa e admissão de teste; instrumentos fictícios.',
   '[{"ordem":1,"acao":"Resolver sem instrumento","resultado_esperado":"origem nenhum"},
     {"ordem":2,"acao":"Cadastrar CCT preponderante da empresa","resultado_esperado":"origem cct_preponderante"},
     {"ordem":3,"acao":"Vincular o colaborador a uma CCT diferenciada sem representação","resultado_esperado":"origem vinculo_colaborador, alerta_sumula_374 = true"},
     {"ordem":4,"acao":"Cadastrar ACT da empresa","resultado_esperado":"origem act_empresa"}]'::jsonb,
   'ponto_instrumento_do_colaborador devolve a precedência correta em cada passo.',
   'Banco de horas configurável — Fatia 1 (30/10/2026). O cálculo passa a usar na Fatia 2.'),
  (v_mod, 'PONTO-521',
   'Vínculo do colaborador à convenção: aviso da Súmula 374 e um vínculo por período',
   'negativo', 'alta', 'aprovado', 'api',
   'Súmula 374 do TST; CLT art. 511 §3º; art. 614 §3º',
   'Vincular a uma CCT de categoria diferenciada em que a empresa não foi representada não obriga a empresa: o sistema avisa (não bloqueia). Dois vínculos no mesmo período deixariam a convenção ambígua: recusado.',
   'Cercado de QA; instrumentos diferenciada (com e sem representação) e um vencido.',
   '[{"ordem":1,"acao":"Avisos de vínculo para os três instrumentos","resultado_esperado":"SUMULA_374 só no não representado; INSTRUMENTO_FORA_VIGENCIA no vencido"},
     {"ordem":2,"acao":"Segundo vínculo sobreposto; depois sequencial","resultado_esperado":"Sobreposto recusado; sequencial aceito"}]'::jsonb,
   'Aviso correto e vigência sem sobreposição.',
   'ponto_instrumento_avisos_vinculo + gatilho trg_ponto_instr_colab_guarda.'),
  (v_mod, 'PONTO-522',
   'Avisos da configuração do banco sem CCT/ACT vigente, e que somem quando a convenção é cadastrada',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 §§2º e 5º; art. 611-A II; art. 462; art. 477 §5º; art. 2º; Lei 605/49 art. 6º',
   'Regra da fundadora (30/10): o que depende de CCT/ACT não bloqueia, avisa até a convenção ser cadastrada. Descontar o negativo na dispensa sem justa causa é aviso FORTE (risco do empregador) e não some com CCT.',
   'Cercado de QA; acordos do cercado desativados; empresa de teste.',
   '[{"ordem":1,"acao":"Avaliar banco anual com desconto do negativo, desconto na dispensa sem justa causa, falta no banco, negativo sem limite; e banco semestral","resultado_esperado":"ANUAL_SEM_COLETIVO, NEGATIVO_FIM_CICLO_SEM_COLETIVO, RESCISAO_SEM_JUSTA_CAUSA_DESCONTO (forte), FALTA_NO_BANCO, NEGATIVO_SEM_LIMITE; SEMESTRAL_SEM_ACORDO"},
     {"ordem":2,"acao":"Cadastrar CCT vigente e reavaliar","resultado_esperado":"Somem os avisos dependentes de CCT; o forte permanece"}]'::jsonb,
   'Avisos certos, sem bloquear a gravação.',
   'ponto_banco_config_avisos_previa (a tela chama enquanto o RH edita) e ponto_banco_config_avisos (config salva).'),
  (v_mod, 'PONTO-523',
   'Bloqueios legais da configuração do banco e padrões iguais ao comportamento atual',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 caput, §§2º e 5º; art. 473; Lei 605/49 art. 6º §1º; CLT art. 2º',
   'Só a lei proíbe em qualquer caso vira bloqueio: (a) não existe transportar/zerar saldo positivo (paga HE); (b) não existe opção de debitar ausência legal ou atestado; (c) teto de crédito diário entre 0 e 120 min. Ciclo fixo não pode passar do máximo da modalidade. Os campos novos nascem com o comportamento de hoje. A natureza do débito (ausência do empregado x dispensa pela empresa) fica prevista.',
   'Cercado de QA.',
   '[{"ordem":1,"acao":"Gravar positivo zerado, teto 121, semestral só em dezembro; semestral junho+dezembro","resultado_esperado":"Três recusas; o último aceito"},
     {"ordem":2,"acao":"Gravar config mínima e conferir padrões; procurar colunas de atestado/ausência legal; conferir natureza_debito","resultado_esperado":"Padrões de hoje; nenhuma coluna proibida; natureza_debito com ausencia_empregado/dispensa_empresa"}]'::jsonb,
   'Bloqueios ativos e padrões neutros.',
   'Gatilho trg_ponto_banco_config_valida + CHECKs ponto_bh_cfg_*. A Fatia 3 aplica no cálculo min(teto, 600 - jornada do dia), exceção 12x36 (art. 59-A); limita o crédito, nunca a batida.'),
  (v_mod, 'PONTO-524',
   'Regime de banco vigente: regra "sem banco" é sem banco e a data de fim é respeitada',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT art. 59 §§2º e 5º',
   'Antes, uma configuração do tipo sem_banco ativa contava como regime de banco (o excedente ia para o banco em vez da folha). Agora a regra mais específica sem_banco significa sem regime, a data de fim encerra a regra, e a regra presa a um instrumento só entra na Fatia 2.',
   'Cercado de QA; regras de banco do cercado desativadas.',
   '[{"ordem":1,"acao":"Regra A (banco, 2025) e B (sem banco, 2026)","resultado_esperado":"06/2025 = A; 06/2026 = sem regime"},
     {"ordem":2,"acao":"Encerrar A em 31/03/2025","resultado_esperado":"06/2025 = sem regime"},
     {"ordem":3,"acao":"Regra D presa a instrumento; regra E comum mais recente","resultado_esperado":"D ignorada; 06/2026 = E"}]'::jsonb,
   'ponto_banco_regime_vigente corrigido sem mudar o resto.',
   'Única mudança de cálculo da Fatia 1. Conferir quem é afetado: configs ativas tipo sem_banco (conferência do script).'),
  (v_mod, 'PONTO-525',
   'Restrições do colaborador ao banco: aprendiz bloqueado, menor e insalubre avisados',
   'negativo', 'alta', 'aprovado', 'api',
   'CLT art. 432; art. 413 I; art. 60; art. 611-A XIII; art. 59-A',
   'Aprendiz não pode ter prorrogação nem compensação (bloqueio sinalizado ao cálculo). Menor só compensa com CCT/ACT; atividade insalubre exige licença prévia salvo CCT/ACT ou 12x36 (avisos).',
   'Cercado de QA; três admissões fictícias (aprendiz, menor, insalubre); sem CCT/ACT.',
   '[{"ordem":1,"acao":"Avisos por colaborador, sinal para o cálculo e avisos da configuração da empresa","resultado_esperado":"APRENDIZ_SEM_BANCO (bloqueio), MENOR_SEM_COLETIVO, INSALUBRE_SEM_LICENCA; bloqueado só o aprendiz; APRENDIZES_NO_ESCOPO, MENORES_SEM_COLETIVO, INSALUBRES_SEM_COLETIVO"}]'::jsonb,
   'Restrições sinalizadas no colaborador e na configuração.',
   'Fatia 1 só sinaliza: o cálculo passa a excluir aprendiz na Fatia 2 (ponto_banco_colaborador_bloqueado).')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes, status = 'aprovado';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-520', 'qa_caso_ponto_520', true),
      ('PONTO-521', 'qa_caso_ponto_521', true),
      ('PONTO-522', 'qa_caso_ponto_522', true),
      ('PONTO-523', 'qa_caso_ponto_523', true),
      ('PONTO-524', 'qa_caso_ponto_524', true),
      ('PONTO-525', 'qa_caso_ponto_525', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-520..525 não registrada: %', SQLERRM;
END $doc$;

-- ── CONFERÊNCIA (único resultado que o editor mostra) ──────────────────────
-- Esperado: colunas_config_novas = 26, tabelas_novas = 2, funcoes_novas = 12,
-- gatilho_validacao = true, regime_corrigido = true, casos_qa = 6,
-- rotinas_qa = 6, backups = 2. configs_sem_banco_ativas = quantas regras
-- "sem banco" ativas existem (essas passam a valer como SEM banco).
-- A bateria NÃO roda aqui (segundo gesto):
--   SELECT public.qa_rodar_bateria('manual', 'jornada-rotina/ponto');
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ponto_banco_horas_config'
      AND column_name IN ('modalidade','tipo_ciclo','meses_fechamento','data_fim','instrumento_id',
        'negativo_fim_ciclo','negativo_rescisao_sem_justa_causa','negativo_rescisao_pedido_demissao',
        'negativo_rescisao_justa_causa','negativo_rescisao_acordo_484a','negativo_rescisao_fim_contrato',
        'teto_desconto_rescisao_uma_remuneracao','falta_injustificada_destino','atraso_destino',
        'saida_antecipada_destino','limite_saldo_negativo_min','negativo_acima_limite_acao',
        'fator_credito_util','fator_credito_domingo','fator_credito_feriado','fator_credito_noturno',
        'teto_credito_diario_min','limite_saldo_acao','extrato_mensal'))
  + (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'ponto_banco_horas_movimentacoes' AND column_name = 'natureza_debito')
  + (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'ponto_cct_config' AND column_name = 'instrumento_id') AS colunas_config_novas,
  (SELECT count(*) FROM pg_tables WHERE schemaname = 'public'
    AND tablename IN ('ponto_acordo_empresas','ponto_instrumento_colaborador') AND rowsecurity) AS tabelas_novas,
  (SELECT count(DISTINCT p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('ponto_instr_vinculo_guarda','ponto_banco_config_valida',
      'ponto_acordo_cobre_empresa','ponto_acordo_vigente_em','ponto_tem_coletivo_vigente',
      'ponto_instrumento_do_colaborador','ponto_instrumento_avisos_vinculo','ponto_banco_avisos_colaborador',
      'ponto_banco_colaborador_bloqueado','ponto_banco_config_avisos_previa','ponto_instrumento_sugestoes',
      'ponto_importar_cct_legado')) AS funcoes_novas,
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ponto_banco_config_valida' AND NOT tgisinternal) AS gatilho_validacao,
  position('[banco-f1]' IN pg_get_functiondef('public.ponto_banco_regime_vigente(uuid,text,text,date)'::regprocedure)) > 0 AS regime_corrigido,
  (SELECT count(*) FROM public.ponto_banco_horas_config WHERE tipo = 'sem_banco' AND COALESCE(ativo, false)) AS configs_sem_banco_ativas,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo IN ('PONTO-520','PONTO-521','PONTO-522','PONTO-523','PONTO-524','PONTO-525')) AS casos_qa,
  (SELECT count(*) FROM public.qa_implementacoes i
    WHERE i.codigo IN ('PONTO-520','PONTO-521','PONTO-522','PONTO-523','PONTO-524','PONTO-525')
      AND to_regprocedure('public.' || i.funcao_sql || '()') IS NOT NULL) AS rotinas_qa,
  (SELECT count(*) FROM pg_tables WHERE schemaname = 'backup'
    AND tablename IN ('ponto_bh_config_20261030','ponto_cct_config_20261030')) AS backups;
