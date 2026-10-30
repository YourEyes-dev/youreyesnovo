-- =====================================================================
-- SCRIPT DE ENTREGA — EC 141/2026, ENTREGA F1
-- Marcos legais (inativos) + escala "vale a partir de" + painel de impacto
--
-- O MESMO arquivo vai para a HOMOLOGAÇÃO e, depois do "aprovado", para a
-- PRODUÇÃO (SQL Editor). Roda inteiro em UMA transação; idempotente (pode
-- rodar 2 vezes); não altera nenhum dado de cliente (só cria tabelas, colunas
-- e funções). Mesmo assim guarda cópia de ponto_escalas e das versões no
-- schema privado backup antes de mexer.
--
-- Antes de rodar em produção: rode docs/consulta_ec141_impacto_SOMENTE_LEITURA.sql
-- e guarde o resultado.
--
-- Corresponde às migrations:
--   supabase/migrations/20261030231930_ponto_ec141_f1_marcos_vigencia.sql
--   supabase/migrations/20261030232630_qa_ponto_ec141_f1_casos.sql
--
-- NADA MUDA SOZINHO NUMA DATA: os marcos 42h e 40h entram INATIVOS. Só o
-- SuperAdmin ativa (SuperAdmin > Produtos > Marcos legais do ponto).
--
-- Reinjeções (marcador [ec141-f1], âncora contada = 1; se o corpo em
-- produção divergir, NADA é alterado naquela função e a conferência mostra
-- NAO APLICADA): formalização, equalização (escala e conta), saldo diário
-- (fallback), intervalo pela janela, débito por batida, batidas de dia
-- inteiro e troca de turno. Retroativo fica BLOQUEADO nesta entrega.
--
-- Desfazer: docs/script_ec141_f1_ROLLBACK.sql (devolve o comportamento de
-- antes; os backups ficam em backup.ponto_escalas_ec141f1_20261030 e
-- backup.ponto_escala_param_versoes_ec141f1_20261030).
-- A conferência final roda a bateria da entrega pelo motor de QA
-- (descartável: nada fica na base) e mostra cada caso.
-- =====================================================================

SET lock_timeout = '10s';

-- 0) Cópia de segurança (schema privado backup; nunca em public).
DO $bkp$
BEGIN
  IF to_regnamespace('backup') IS NULL THEN
    RAISE NOTICE 'Schema backup ausente: rode docs/script_backup_schema_privado.sql antes. Copia NAO feita.';
    RETURN;
  END IF;
  IF to_regclass('backup.ponto_escalas_ec141f1_20261030') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_escalas_ec141f1_20261030 AS SELECT * FROM public.ponto_escalas';
  END IF;
  IF to_regclass('backup.ponto_escala_param_versoes_ec141f1_20261030') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_escala_param_versoes_ec141f1_20261030 AS SELECT * FROM public.ponto_escala_param_versoes';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Copia de seguranca nao feita: %', SQLERRM;
END $bkp$;

-- ---------------------------------------------------------------------
-- PARTE A — estrutura, funções e reinjeções
-- ---------------------------------------------------------------------
-- =====================================================================
-- PONTO — EC 141/2026, ENTREGA F1: marcos legais + escala "vigente a partir de"
-- + painel de impacto (somente leitura). NADA MUDA SOZINHO NUMA DATA.
--
-- Decisão da fundadora (30/10/2026): a transição é MANUAL. A lei pode mudar ou
-- ser revogada, então os marcos 42h e 40h nascem INATIVOS. Só o SuperAdmin
-- YourEyes ativa (com data editável) e pode desativar. Enquanto nenhum marco
-- EC 141 estiver ativo, nenhum cálculo, aviso ou tela do cliente muda.
--
-- O QUE ENTRA
--   1) ponto_marcos_legais (global; tenant_id preenchido = exceção por conta)
--      + histórico + RPCs ponto_marco_ativar / desativar / definir_data /
--      remover_override + ponto_teto_legal(tenant, empresa, data) que só
--      considera marcos ATIVOS (exceção da conta vence o global).
--      Base: CF art. 7º XIII e XV (redação da EC 141/2026), art. 6º da EC.
--   2) ponto_escalas.parametros_vigentes_desde: a edição da escala pode valer
--      "a partir de" uma data. O gatilho de versão congela os valores antigos
--      até a véspera dessa data (antes: sempre até ontem). Na edição COM data
--      a versão guarda também compensacoes_mensais, carga_semanal_contratada_min,
--      equalizacao_mensal_ativa, tipo e jornada_semanal_minutos. A edição SEM
--      data segue byte a byte como antes (só os 7 campos da PONTO-153).
--      Os blocos diários (ponto_escala_periodos) de antes também ficam
--      copiados na versão: para dias anteriores à data, TUDO lê o antigo.
--      Regras: data anterior a hoje BLOQUEADA nesta entrega (os dias já
--      apurados precisariam ser reconsolidados — fica para a F2; a checagem
--      de justificativa e de competência fechada já está no gatilho); um
--      agendamento pendente por escala; numa alteração com data não podem
--      mudar campos não versionados (percentuais, feriado, noturno, ciclo).
--      RPCs: ponto_escala_cancelar_agendamento, ponto_escalas_cancelar_
--      agendamentos_lote (revogação da lei), ponto_escalas_agendamentos.
--   3) ponto_ec141_impacto(tenant, empresa, marco): prévia por empresa e
--      escala (colaboradores, carga, teto, 6x1 sem coletivo, agendamentos).
--      Para o cliente só aparece com marco EC 141 ativo; o SuperAdmin vê sempre.
--   4) ponto_escala_validar_teto(escala, data): AVISOS, nunca bloqueia nada
--      (nem a escala, nem a batida — Portaria MTP 671/2021).
--   5) Leitores que ignoravam a data passam a usar a versão do dia, por
--      reinjeção [ec141-f1] (registro _ponto_ec141_reinjecoes): formalização,
--      equalização (1º dia da competência) e equalização da conta, fallback de
--      jornada/tolerância do saldo, intervalo pela janela entre blocos, débito
--      por batida, batidas de dia inteiro e troca de turno. As telas leem por
--      ponto_escalas_na_data / ponto_escalas_periodos_na_data.
--
-- GARANTIAS
--   · Sem marco EC 141 ativo e sem agendamento, a apuração sai idêntica.
--   · Versões ANTIGAS (gravadas antes desta entrega) seguem lidas como antes:
--     os campos novos só sobrepõem quando a versão foi gravada com eles
--     (inclui_campos_ec141 = true).
--   · Reinjeções idempotentes, por marcador [ec141-f1], com âncora contada
--     (precisa aparecer exatamente 1 vez; senão só avisa e NÃO altera).
--   · Variáveis atribuídas só por subconsulta escalar e tabela criada por EXECUTE (o mesmo
--     corpo vai no script de entrega do SQL Editor).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) MARCOS LEGAIS
-- ---------------------------------------------------------------------
DO $tab_marcos$
BEGIN
  IF to_regclass('public.ponto_marcos_legais') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_marcos_legais ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' codigo text NOT NULL,'
      || ' nome text NOT NULL,'
      || ' vigencia_inicio date NOT NULL,'
      || ' teto_semanal_min integer NOT NULL CHECK (teto_semanal_min > 0),'
      || ' teto_diario_min integer NOT NULL CHECK (teto_diario_min > 0),'
      || ' repousos_semana integer NOT NULL CHECK (repousos_semana BETWEEN 1 AND 7),'
      || ' divisor_padrao integer NOT NULL CHECK (divisor_padrao > 0),'
      || ' fonte text,'
      || ' ativo boolean NOT NULL DEFAULT false,'
      || ' ativado_em timestamptz,'
      || ' ativado_por uuid,'
      || ' desativado_em timestamptz,'
      || ' desativado_por uuid,'
      || ' motivo text,'
      || ' tenant_id uuid REFERENCES public.tenants(id) ON DELETE CASCADE,'
      || ' criado_em timestamptz NOT NULL DEFAULT now(),'
      || ' atualizado_em timestamptz NOT NULL DEFAULT now()'
      || ')';
  END IF;
  IF to_regclass('public.ponto_marcos_legais_historico') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_marcos_legais_historico ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' marco_id uuid,'
      || ' codigo text NOT NULL,'
      || ' tenant_id uuid,'
      || ' acao text NOT NULL,'
      || ' antes jsonb,'
      || ' depois jsonb,'
      || ' motivo text,'
      || ' usuario_id uuid,'
      || ' usuario_email text,'
      || ' criado_em timestamptz NOT NULL DEFAULT now()'
      || ')';
  END IF;
END $tab_marcos$;

COMMENT ON TABLE public.ponto_marcos_legais IS
  'EC 141/2026 (F1) — marcos legais da duracao do trabalho (CF art. 7, XIII e XV). tenant_id NULL = regra global; preenchido = excecao da conta, que vence a global. Nascem INATIVOS (exceto a CF88 vigente): a ativacao e gesto manual do SuperAdmin, com data editavel e reversivel.';
COMMENT ON TABLE public.ponto_marcos_legais_historico IS
  'Auditoria das ativacoes, desativacoes e mudancas de data dos marcos legais (quem, quando, antes/depois, motivo).';

CREATE UNIQUE INDEX IF NOT EXISTS ponto_marcos_legais_global_uk
  ON public.ponto_marcos_legais (codigo) WHERE tenant_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ponto_marcos_legais_conta_uk
  ON public.ponto_marcos_legais (codigo, tenant_id) WHERE tenant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ponto_marcos_legais_hist_codigo
  ON public.ponto_marcos_legais_historico (codigo, criado_em DESC);

ALTER TABLE public.ponto_marcos_legais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ponto_marcos_legais_historico ENABLE ROW LEVEL SECURITY;

DO $pol_marcos$
BEGIN
  DROP POLICY IF EXISTS "ponto_marcos_legais_leitura" ON public.ponto_marcos_legais;
  CREATE POLICY "ponto_marcos_legais_leitura" ON public.ponto_marcos_legais
    FOR SELECT TO authenticated
    USING (tenant_id IS NULL OR tenant_id = public.get_user_tenant_id() OR public.is_superadmin(auth.uid()));
  DROP POLICY IF EXISTS "ponto_marcos_legais_escrita_superadmin" ON public.ponto_marcos_legais;
  CREATE POLICY "ponto_marcos_legais_escrita_superadmin" ON public.ponto_marcos_legais
    FOR ALL TO authenticated
    USING (public.is_superadmin(auth.uid()))
    WITH CHECK (public.is_superadmin(auth.uid()));
  DROP POLICY IF EXISTS "ponto_marcos_legais_hist_superadmin" ON public.ponto_marcos_legais_historico;
  CREATE POLICY "ponto_marcos_legais_hist_superadmin" ON public.ponto_marcos_legais_historico
    FOR SELECT TO authenticated
    USING (public.is_superadmin(auth.uid()));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politicas de ponto_marcos_legais nao aplicadas: %', SQLERRM;
END $pol_marcos$;

-- Carga dos marcos. Idempotente e SEM sobrescrever: rodar de novo não
-- desfaz uma ativação já feita pelo SuperAdmin.
DO $carga_marcos$
BEGIN
  INSERT INTO public.ponto_marcos_legais
    (codigo, nome, vigencia_inicio, teto_semanal_min, teto_diario_min, repousos_semana, divisor_padrao, fonte, ativo, motivo)
  SELECT v.codigo, v.nome, v.vigencia, v.semanal, v.diario, v.repousos, v.divisor, v.fonte, v.ativo, v.motivo
  FROM (VALUES
    ('CF88_44H', 'CF/88 — 44h semanais, 8h diárias, 1 repouso semanal', DATE '1988-10-05', 2640, 480, 1, 220,
     'CF art. 7º, XIII e XV (redação original); CLT art. 58 e 67', true,
     'Lei vigente na carga inicial (EC 141 F1).'),
    ('EC141_42H', 'EC 141/2026 — 42h semanais, 2 repousos (transição)', DATE '2026-12-15', 2520, 480, 2, 210,
     'EC 141/2026, art. 6º (42h 2 meses após a publicação, DOU 16/10/2026); CF art. 7º, XV; divisor 210 por inferência (Súmula 431 TST) — a confirmar', false,
     'Carga inicial inativa: a ativação é gesto manual do SuperAdmin.'),
    ('EC141_40H', 'EC 141/2026 — 40h semanais, 2 repousos', DATE '2027-12-15', 2400, 480, 2, 200,
     'EC 141/2026, art. 6º (40h 1 ano após a etapa de 42h); CF art. 7º, XIII e XV; Súmula 431 TST (divisor 200)', false,
     'Carga inicial inativa: a ativação é gesto manual do SuperAdmin.')
  ) AS v(codigo, nome, vigencia, semanal, diario, repousos, divisor, fonte, ativo, motivo)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.ponto_marcos_legais m WHERE m.codigo = v.codigo AND m.tenant_id IS NULL
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Carga dos marcos legais nao aplicada: %', SQLERRM;
END $carga_marcos$;

-- Papel de quem chama: interno (SQL Editor, service_role, motor de QA sem
-- usuário), superadmin, usuario (logado) ou anonimo.
CREATE OR REPLACE FUNCTION public._ponto_ec141_papel()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_claims jsonb;
  v_uid uuid;
BEGIN
  BEGIN
    v_claims := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_claims := NULL;
  END;
  v_uid := auth.uid();
  IF v_uid IS NOT NULL AND public.is_superadmin(v_uid) THEN
    RETURN 'superadmin';
  END IF;
  IF v_uid IS NOT NULL THEN
    RETURN 'usuario';
  END IF;
  IF COALESCE(v_claims->>'role', '') IN ('anon', 'authenticated') THEN
    RETURN 'anonimo';
  END IF;
  RETURN 'interno';
END $fn$;

-- Pode agir sobre dados do tenant? (interno, superadmin ou usuário da conta)
CREATE OR REPLACE FUNCTION public._ponto_ec141_pode_tenant(p_tenant uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_papel text := public._ponto_ec141_papel();
BEGIN
  IF v_papel IN ('interno', 'superadmin') THEN
    RETURN true;
  END IF;
  IF v_papel = 'usuario' AND p_tenant IS NOT NULL AND public.get_user_tenant_id() = p_tenant THEN
    RETURN true;
  END IF;
  RETURN false;
END $fn$;

-- Marcos resolvidos para a conta: a exceção da conta vence a global.
CREATE OR REPLACE FUNCTION public.ponto_marcos_resolvidos(p_tenant uuid)
RETURNS TABLE(codigo text, nome text, vigencia_inicio date, teto_semanal_min integer,
              teto_diario_min integer, repousos_semana integer, divisor_padrao integer,
              fonte text, ativo boolean, origem text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT DISTINCT ON (m.codigo)
         m.codigo, m.nome, m.vigencia_inicio, m.teto_semanal_min, m.teto_diario_min,
         m.repousos_semana, m.divisor_padrao, m.fonte, m.ativo,
         CASE WHEN m.tenant_id IS NULL THEN 'global' ELSE 'conta' END
  FROM public.ponto_marcos_legais m
  WHERE m.tenant_id IS NULL OR m.tenant_id = p_tenant
  ORDER BY m.codigo, (m.tenant_id IS NULL)
$fn$;

-- Teto legal na data: o marco ATIVO mais recente já em vigor. Marco inativo
-- é ignorado. Sem nenhum (não deveria acontecer), devolve a CF/88.
CREATE OR REPLACE FUNCTION public.ponto_teto_legal(p_tenant uuid, p_empresa uuid, p_data date)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    (SELECT jsonb_build_object(
              'codigo', r.codigo, 'nome', r.nome, 'vigencia_inicio', r.vigencia_inicio,
              'teto_semanal_min', r.teto_semanal_min, 'teto_diario_min', r.teto_diario_min,
              'repousos_semana', r.repousos_semana, 'divisor_padrao', r.divisor_padrao,
              'fonte', r.fonte, 'origem', r.origem,
              'data_referencia', COALESCE(p_data, CURRENT_DATE), 'empresa_id', p_empresa)
       FROM public.ponto_marcos_resolvidos(p_tenant) r
      WHERE r.ativo AND r.vigencia_inicio <= COALESCE(p_data, CURRENT_DATE)
      ORDER BY r.vigencia_inicio DESC, r.teto_semanal_min ASC
      LIMIT 1),
    jsonb_build_object(
      'codigo', 'CF88_44H', 'nome', 'CF/88 — 44h semanais, 8h diárias, 1 repouso semanal',
      'vigencia_inicio', DATE '1988-10-05', 'teto_semanal_min', 2640, 'teto_diario_min', 480,
      'repousos_semana', 1, 'divisor_padrao', 220, 'fonte', 'CF art. 7º, XIII e XV (redação original)',
      'origem', 'padrao', 'data_referencia', COALESCE(p_data, CURRENT_DATE), 'empresa_id', p_empresa)
  )
$fn$;

COMMENT ON FUNCTION public.ponto_teto_legal(uuid, uuid, date) IS
  'EC 141 F1 — teto legal (semanal, diario, repousos, divisor) na data, considerando SO marcos ativos; excecao da conta vence a global. Fallback: CF/88 44h.';

-- Próximo marco EC 141 ATIVO da conta (ou o último já em vigor).
CREATE OR REPLACE FUNCTION public.ponto_ec141_marco_alvo(p_tenant uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT to_jsonb(x) FROM (
    SELECT r.*
      FROM public.ponto_marcos_resolvidos(p_tenant) r
     WHERE r.ativo AND r.codigo LIKE 'EC141%'
     ORDER BY (r.vigencia_inicio > CURRENT_DATE) DESC,
              CASE WHEN r.vigencia_inicio > CURRENT_DATE THEN r.vigencia_inicio END ASC,
              r.vigencia_inicio DESC
     LIMIT 1
  ) x
$fn$;

-- Núcleo das alterações de marco (com histórico). Só SuperAdmin/interno.
CREATE OR REPLACE FUNCTION public._ponto_marco_gravar(
  p_acao text, p_codigo text, p_data date, p_motivo text, p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_papel  text := public._ponto_ec141_papel();
  v_uid    uuid := auth.uid();
  v_motivo text := NULLIF(btrim(COALESCE(p_motivo, '')), '');
  v_glob   public.ponto_marcos_legais;
  v_alvo   public.ponto_marcos_legais;
  v_antes  jsonb;
  v_depois jsonb;
  v_email  text;
BEGIN
  IF v_papel NOT IN ('interno', 'superadmin') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao',
      'mensagem', 'Somente o SuperAdmin YourEyes altera marcos legais.');
  END IF;
  IF p_acao NOT IN ('ativar', 'desativar', 'definir_data', 'remover_override') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'acao_invalida');
  END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio',
      'mensagem', 'Informe o motivo (ex.: publicação, revogação, adiamento, decisão judicial).');
  END IF;
  v_glob := (SELECT m FROM public.ponto_marcos_legais m WHERE m.codigo = p_codigo AND m.tenant_id IS NULL);
  IF v_glob.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'marco_inexistente');
  END IF;
  IF p_acao IN ('ativar', 'definir_data') AND p_data IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'data_obrigatoria');
  END IF;
  IF p_acao = 'desativar' AND p_codigo = 'CF88_44H' AND p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'marco_base',
      'mensagem', 'O marco base (CF/88 44h) não pode ser desativado.');
  END IF;
  IF p_acao = 'remover_override' AND p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'conta_obrigatoria');
  END IF;

  v_email := (SELECT u.email::text FROM auth.users u WHERE u.id = v_uid);

  IF p_tenant_id IS NULL THEN
    v_alvo := v_glob;
  ELSE
    v_alvo := (SELECT m FROM public.ponto_marcos_legais m WHERE m.codigo = p_codigo AND m.tenant_id = p_tenant_id);
    IF p_acao = 'remover_override' THEN
      IF v_alvo.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'sem_excecao');
      END IF;
      DELETE FROM public.ponto_marcos_legais WHERE id = v_alvo.id;
      INSERT INTO public.ponto_marcos_legais_historico
        (marco_id, codigo, tenant_id, acao, antes, depois, motivo, usuario_id, usuario_email)
      VALUES (v_alvo.id, p_codigo, p_tenant_id, p_acao, to_jsonb(v_alvo), NULL, v_motivo, v_uid, v_email);
      RETURN jsonb_build_object('ok', true, 'marco', NULL);
    END IF;
    IF v_alvo.id IS NULL THEN
      INSERT INTO public.ponto_marcos_legais
        (codigo, nome, vigencia_inicio, teto_semanal_min, teto_diario_min, repousos_semana,
         divisor_padrao, fonte, ativo, motivo, tenant_id)
      VALUES (v_glob.codigo, v_glob.nome, v_glob.vigencia_inicio, v_glob.teto_semanal_min,
              v_glob.teto_diario_min, v_glob.repousos_semana, v_glob.divisor_padrao,
              v_glob.fonte, v_glob.ativo, v_motivo, p_tenant_id);
      v_alvo := (SELECT m FROM public.ponto_marcos_legais m WHERE m.codigo = p_codigo AND m.tenant_id = p_tenant_id);
    END IF;
  END IF;

  v_antes := to_jsonb(v_alvo);

  UPDATE public.ponto_marcos_legais m SET
    ativo           = CASE p_acao WHEN 'ativar' THEN true WHEN 'desativar' THEN false ELSE m.ativo END,
    vigencia_inicio = CASE WHEN p_acao IN ('ativar', 'definir_data') THEN p_data ELSE m.vigencia_inicio END,
    ativado_em      = CASE WHEN p_acao = 'ativar' THEN now() ELSE m.ativado_em END,
    ativado_por     = CASE WHEN p_acao = 'ativar' THEN v_uid ELSE m.ativado_por END,
    desativado_em   = CASE WHEN p_acao = 'desativar' THEN now() WHEN p_acao = 'ativar' THEN NULL ELSE m.desativado_em END,
    desativado_por  = CASE WHEN p_acao = 'desativar' THEN v_uid WHEN p_acao = 'ativar' THEN NULL ELSE m.desativado_por END,
    motivo          = v_motivo,
    atualizado_em   = now()
  WHERE m.id = v_alvo.id;

  v_depois := (SELECT to_jsonb(m) FROM public.ponto_marcos_legais m WHERE m.id = v_alvo.id);

  INSERT INTO public.ponto_marcos_legais_historico
    (marco_id, codigo, tenant_id, acao, antes, depois, motivo, usuario_id, usuario_email)
  VALUES (v_alvo.id, p_codigo, p_tenant_id, p_acao, v_antes, v_depois, v_motivo, v_uid, v_email);

  RETURN jsonb_build_object('ok', true, 'marco', v_depois);
END $fn$;

CREATE OR REPLACE FUNCTION public.ponto_marco_ativar(
  p_codigo text, p_vigencia_inicio date, p_motivo text, p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._ponto_marco_gravar('ativar', p_codigo, p_vigencia_inicio, p_motivo, p_tenant_id)
$fn$;

CREATE OR REPLACE FUNCTION public.ponto_marco_desativar(
  p_codigo text, p_motivo text, p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._ponto_marco_gravar('desativar', p_codigo, NULL, p_motivo, p_tenant_id)
$fn$;

CREATE OR REPLACE FUNCTION public.ponto_marco_definir_data(
  p_codigo text, p_vigencia_inicio date, p_motivo text, p_tenant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._ponto_marco_gravar('definir_data', p_codigo, p_vigencia_inicio, p_motivo, p_tenant_id)
$fn$;

CREATE OR REPLACE FUNCTION public.ponto_marco_remover_excecao(
  p_codigo text, p_tenant_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public._ponto_marco_gravar('remover_override', p_codigo, NULL, p_motivo, p_tenant_id)
$fn$;

-- ---------------------------------------------------------------------
-- 2) ESCALA COM "VIGENTE A PARTIR DE"
-- ---------------------------------------------------------------------
ALTER TABLE public.ponto_escalas
  ADD COLUMN IF NOT EXISTS parametros_vigentes_desde date,
  ADD COLUMN IF NOT EXISTS parametros_vigencia_motivo text,
  ADD COLUMN IF NOT EXISTS parametros_marco_codigo text;

COMMENT ON COLUMN public.ponto_escalas.parametros_vigentes_desde IS
  'EC 141 F1 — data a partir da qual os parametros atuais da escala valem. Gravar uma data FUTURA agenda a mudanca (os valores antigos ficam congelados ate a vespera); data passada exige justificativa e competencia aberta.';
COMMENT ON COLUMN public.ponto_escalas.parametros_vigencia_motivo IS
  'EC 141 F1 — argumento transitorio da gravacao (justificativa da data). O gatilho consome e limpa.';
COMMENT ON COLUMN public.ponto_escalas.parametros_marco_codigo IS
  'EC 141 F1 — argumento transitorio: marco legal que motivou o agendamento (permite cancelar em lote se a lei mudar). O gatilho consome e limpa.';

ALTER TABLE public.ponto_escala_param_versoes
  ADD COLUMN IF NOT EXISTS compensacoes_mensais jsonb,
  ADD COLUMN IF NOT EXISTS carga_semanal_contratada_min integer,
  ADD COLUMN IF NOT EXISTS equalizacao_mensal_ativa boolean,
  ADD COLUMN IF NOT EXISTS tipo text,
  ADD COLUMN IF NOT EXISTS jornada_semanal_minutos integer,
  ADD COLUMN IF NOT EXISTS inclui_campos_ec141 boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS origem text,
  ADD COLUMN IF NOT EXISTS motivo text,
  ADD COLUMN IF NOT EXISTS marco_codigo text,
  ADD COLUMN IF NOT EXISTS criado_por uuid,
  ADD COLUMN IF NOT EXISTS vigentes_desde_anterior date,
  ADD COLUMN IF NOT EXISTS periodos jsonb,
  ADD COLUMN IF NOT EXISTS escala_anterior jsonb;

COMMENT ON COLUMN public.ponto_escala_param_versoes.periodos IS
  'EC 141 F1 — copia exata dos blocos diarios (ponto_escala_periodos) antes da alteracao com data: os dias anteriores a data continuam lendo os blocos antigos.';
COMMENT ON COLUMN public.ponto_escala_param_versoes.escala_anterior IS
  'EC 141 F1 — linha da escala antes da alteracao com data (para o cancelamento devolver o estado exato).';

COMMENT ON COLUMN public.ponto_escala_param_versoes.inclui_campos_ec141 IS
  'EC 141 F1 — true quando a versao veio de uma edicao COM data (agendamento ou retroativo) e por isso tambem sobrepoe compensacoes, carga contratada, equalizacao, tipo e jornada semanal. Versoes de edicao sem data (e as antigas) ficam false: a leitura delas segue identica a de antes.';

-- Auditoria do agendamento no log do ponto (sem dado pessoal).
CREATE OR REPLACE FUNCTION public._ponto_ec141_audit_escala(
  p_tenant uuid, p_escala uuid, p_antes jsonb, p_depois jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  INSERT INTO public.ponto_audit_log
    (tenant_id, tabela_origem, registro_id, acao, dados_anteriores, dados_novos, usuario_id, usuario_email)
  VALUES (p_tenant, 'ponto_escalas', p_escala, 'UPDATE', p_antes, p_depois, auth.uid(),
          (SELECT u.email::text FROM auth.users u WHERE u.id = auth.uid()));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Auditoria da escala nao registrada: %', SQLERRM;
END $fn$;

-- Gatilho de versão (substitui o da PONTO-153). Edição sem data continua
-- exatamente como antes: congela os valores antigos até ontem.
CREATE OR REPLACE FUNCTION public.ponto_escala_arquiva_versao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_inicio     date;
  v_desde      date;
  v_pend_fim   date;
  v_origem     text;
  v_motivo     text;
  v_marco      text;
  v_fechada    text;
  v_mudou7     boolean;
  v_mudou12    boolean;
  v_outros     boolean;
  v_explicito  boolean;
  v_ajuste     boolean;
  v_periodos   jsonb;
BEGIN
  -- Argumentos transitórios da gravação: consumidos aqui, nunca ficam na linha.
  v_motivo := NULLIF(btrim(COALESCE(NEW.parametros_vigencia_motivo, '')), '');
  v_marco  := NULLIF(btrim(COALESCE(NEW.parametros_marco_codigo, '')), '');
  NEW.parametros_vigencia_motivo := NULL;
  NEW.parametros_marco_codigo := NULL;

  -- Restauração feita pelo cancelamento de agendamento: não versiona.
  IF COALESCE(current_setting('ponto.ec141_restaurando', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  -- Os 7 parâmetros versionados desde a PONTO-153.
  v_mudou7 := (
        NEW.jornada_diaria_minutos         IS DISTINCT FROM OLD.jornada_diaria_minutos
     OR NEW.tolerancia_minutos             IS DISTINCT FROM OLD.tolerancia_minutos
     OR NEW.tolerancia_diaria_minutos      IS DISTINCT FROM OLD.tolerancia_diaria_minutos
     OR NEW.hora_entrada_padrao            IS DISTINCT FROM OLD.hora_entrada_padrao
     OR NEW.hora_saida_padrao              IS DISTINCT FROM OLD.hora_saida_padrao
     OR NEW.intervalo_intrajornada_minutos IS DISTINCT FROM OLD.intervalo_intrajornada_minutos
     OR NEW.dias_config                    IS DISTINCT FROM OLD.dias_config);
  -- + os 5 que só a alteração COM data versiona.
  v_mudou12 := v_mudou7
     OR NEW.compensacoes_mensais           IS DISTINCT FROM OLD.compensacoes_mensais
     OR NEW.carga_semanal_contratada_min   IS DISTINCT FROM OLD.carga_semanal_contratada_min
     OR NEW.equalizacao_mensal_ativa       IS DISTINCT FROM OLD.equalizacao_mensal_ativa
     OR NEW.tipo                           IS DISTINCT FROM OLD.tipo
     OR NEW.jornada_semanal_minutos        IS DISTINCT FROM OLD.jornada_semanal_minutos;
  -- Campos de cálculo que NÃO são versionados: numa alteração com data eles
  -- valeriam de imediato (antes da data), então não podem mudar junto.
  v_outros := (
        NEW.comportamento_feriado          IS DISTINCT FROM OLD.comportamento_feriado
     OR NEW.percentual_hora_extra_50       IS DISTINCT FROM OLD.percentual_hora_extra_50
     OR NEW.percentual_hora_extra_100      IS DISTINCT FROM OLD.percentual_hora_extra_100
     OR NEW.percentual_adicional_noturno   IS DISTINCT FROM OLD.percentual_adicional_noturno
     OR NEW.usa_hora_ficta_noturna         IS DISTINCT FROM OLD.usa_hora_ficta_noturna
     OR NEW.adicional_noturno_inicio       IS DISTINCT FROM OLD.adicional_noturno_inicio
     OR NEW.adicional_noturno_fim          IS DISTINCT FROM OLD.adicional_noturno_fim
     OR NEW.modalidade                     IS DISTINCT FROM OLD.modalidade
     OR NEW.ciclo_horas_trabalho           IS DISTINCT FROM OLD.ciclo_horas_trabalho
     OR NEW.ciclo_horas_descanso           IS DISTINCT FROM OLD.ciclo_horas_descanso
     OR NEW.ciclo_inicio_data              IS DISTINCT FROM OLD.ciclo_inicio_data
     OR NEW.ciclo_inicio_hora              IS DISTINCT FROM OLD.ciclo_inicio_hora
     OR NEW.janela_flexivel                IS DISTINCT FROM OLD.janela_flexivel
     OR NEW.regras_extras                  IS DISTINCT FROM OLD.regras_extras);

  -- Agendamento pendente desta escala (período antigo que termina hoje ou depois).
  v_pend_fim := (SELECT max(pv.vigencia_fim) FROM public.ponto_escala_param_versoes pv
                  WHERE pv.escala_id = OLD.id AND pv.vigencia_fim >= CURRENT_DATE);
  v_explicito := NEW.parametros_vigentes_desde IS NOT NULL
                 AND NEW.parametros_vigentes_desde IS DISTINCT FROM OLD.parametros_vigentes_desde;
  v_ajuste := NOT v_explicito AND v_pend_fim IS NOT NULL
              AND OLD.parametros_vigentes_desde = v_pend_fim + 1;

  IF (v_explicito OR v_ajuste) AND v_outros THEN
    RAISE EXCEPTION 'Numa alteração com data só mudam horários, jornada, tolerâncias, compensações e equalização. Percentuais, feriado, adicional noturno e ciclo valeriam antes da data: salve-os separadamente (sem data) ou depois que a data chegar.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT v_mudou12 THEN
    -- Sem mudança de parâmetro, a data de vigência não muda sozinha.
    NEW.parametros_vigentes_desde := OLD.parametros_vigentes_desde;
    RETURN NEW;
  END IF;

  IF v_explicito THEN
    v_desde := NEW.parametros_vigentes_desde;
  ELSIF v_ajuste THEN
    -- Ajuste dos valores JÁ agendados, para a mesma data: o período antigo
    -- (e os blocos antigos) continuam congelados como estavam.
    RETURN NEW;
  ELSE
    -- Edição sem data: EXATAMENTE como antes desta entrega. Só os 7 campos da
    -- PONTO-153 versionam; os outros 5 seguem valendo para trás como sempre.
    IF NOT v_mudou7 THEN
      NEW.parametros_vigentes_desde := OLD.parametros_vigentes_desde;
      RETURN NEW;
    END IF;
    v_desde := CURRENT_DATE;
  END IF;

  IF v_pend_fim IS NOT NULL THEN
    RAISE EXCEPTION 'Esta escala já tem uma alteração agendada para %. Cancele o agendamento antes de programar outra.',
      to_char(v_pend_fim + 1, 'DD/MM/YYYY')
      USING ERRCODE = 'P0001';
  END IF;

  -- Início do período antigo: logo após a última versão arquivada.
  v_inicio := (SELECT COALESCE(max(pv.vigencia_fim) + 1, DATE '1900-01-01')
                 FROM public.ponto_escala_param_versoes pv WHERE pv.escala_id = OLD.id);

  IF v_desde < CURRENT_DATE THEN
    IF v_motivo IS NULL THEN
      RAISE EXCEPTION 'Alteração com data anterior a hoje (%) exige justificativa.', to_char(v_desde, 'DD/MM/YYYY')
        USING ERRCODE = 'P0001';
    END IF;
    v_fechada := (SELECT min(f.competencia) FROM public.ponto_fechamentos f
                   WHERE f.tenant_id = NEW.tenant_id
                     AND f.status = 'fechado'
                     AND f.competencia BETWEEN to_char(v_desde, 'YYYY-MM') AND to_char(CURRENT_DATE, 'YYYY-MM')
                     AND (f.empresa_id IS NULL OR NEW.empresa_id IS NULL OR f.empresa_id = NEW.empresa_id));
    IF v_fechada IS NOT NULL THEN
      RAISE EXCEPTION 'A competência % já está fechada: a alteração não pode retroagir sobre ela. Escolha uma data em competência aberta.',
        v_fechada
        USING ERRCODE = 'P0001';
    END IF;
    -- Decisão de segurança (F1): os dias já apurados entre a data e ontem
    -- teriam de ser reconsolidados no ponto_diario. Enquanto essa
    -- reconsolidação não existir (EC 141 F2), o retroativo fica bloqueado.
    RAISE EXCEPTION 'Alteração com data anterior a hoje ainda não está disponível: os dias já apurados precisariam ser recalculados. Escolha hoje ou uma data futura.'
      USING ERRCODE = 'P0001';
  ELSIF v_desde > CURRENT_DATE THEN
    v_origem := 'agendamento';
  ELSE
    v_origem := 'edicao';
  END IF;

  -- Blocos diários de ANTES da alteração (a tela os regrava logo depois):
  -- a versão guarda a cópia exata para os dias anteriores à data.
  IF v_origem <> 'edicao' THEN
    v_periodos := COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.dia_semana, p.ordem_bloco)
                              FROM public.ponto_escala_periodos p WHERE p.escala_id = OLD.id), '[]'::jsonb);
  END IF;

  -- Se o intervalo não é válido (parâmetros vigoraram só a partir da data),
  -- não há período antigo a congelar.
  IF v_inicio <= v_desde - 1 THEN
    INSERT INTO public.ponto_escala_param_versoes
      (escala_id, tenant_id, vigencia_inicio, vigencia_fim,
       jornada_diaria_minutos, hora_entrada_padrao, hora_saida_padrao,
       intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
       dias_config, compensacoes_mensais, carga_semanal_contratada_min,
       equalizacao_mensal_ativa, tipo, jornada_semanal_minutos,
       inclui_campos_ec141, origem, motivo, marco_codigo, criado_por, vigentes_desde_anterior,
       periodos, escala_anterior)
    VALUES (OLD.id, OLD.tenant_id, v_inicio, v_desde - 1,
            OLD.jornada_diaria_minutos, OLD.hora_entrada_padrao, OLD.hora_saida_padrao,
            OLD.intervalo_intrajornada_minutos, OLD.tolerancia_minutos, OLD.tolerancia_diaria_minutos,
            OLD.dias_config, OLD.compensacoes_mensais, OLD.carga_semanal_contratada_min,
            OLD.equalizacao_mensal_ativa, OLD.tipo, OLD.jornada_semanal_minutos,
            (v_origem <> 'edicao'), v_origem, v_motivo, v_marco, auth.uid(), OLD.parametros_vigentes_desde,
            v_periodos, CASE WHEN v_origem <> 'edicao' THEN to_jsonb(OLD) END);
  END IF;

  NEW.parametros_vigentes_desde := v_desde;

  IF v_origem <> 'edicao' THEN
    PERFORM public._ponto_ec141_audit_escala(OLD.tenant_id, OLD.id,
      jsonb_build_object('jornada_diaria_minutos', OLD.jornada_diaria_minutos,
                         'jornada_semanal_minutos', OLD.jornada_semanal_minutos,
                         'tipo', OLD.tipo, 'dias_config', OLD.dias_config),
      jsonb_build_object('evento', 'ec141_' || v_origem, 'vigente_a_partir_de', v_desde,
                         'motivo', v_motivo, 'marco_codigo', v_marco,
                         'jornada_diaria_minutos', NEW.jornada_diaria_minutos,
                         'jornada_semanal_minutos', NEW.jornada_semanal_minutos,
                         'tipo', NEW.tipo, 'dias_config', NEW.dias_config));
  END IF;
  RETURN NEW;
END $fn$;

-- Garante o gatilho (já existe desde a PONTO-153; recriado só se faltar).
DO $trg$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'trg_ponto_escala_arquiva_versao'
                    AND t.tgrelid = 'public.ponto_escalas'::regclass AND NOT t.tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_ponto_escala_arquiva_versao BEFORE UPDATE ON public.ponto_escalas '
         || 'FOR EACH ROW EXECUTE FUNCTION public.ponto_escala_arquiva_versao()';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Gatilho de versao da escala nao conferido: %', SQLERRM;
END $trg$;

-- Overlay da versão do dia (substitui o da PONTO-153). Os campos novos só
-- sobrepõem em versões gravadas com eles — as antigas leem como sempre.
CREATE OR REPLACE FUNCTION public.ponto_escala_com_versao(esc public.ponto_escalas, p_data date)
RETURNS public.ponto_escalas
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v public.ponto_escala_param_versoes;
BEGIN
  IF esc.id IS NULL OR p_data IS NULL THEN
    RETURN esc;
  END IF;

  v := (SELECT pv FROM public.ponto_escala_param_versoes pv
         WHERE pv.escala_id = esc.id
           AND p_data BETWEEN pv.vigencia_inicio AND pv.vigencia_fim
         ORDER BY pv.vigencia_inicio DESC
         LIMIT 1);

  IF v.id IS NULL THEN
    RETURN esc;  -- nenhuma versão cobre a data: a escala viva é a vigente
  END IF;

  esc.jornada_diaria_minutos          := v.jornada_diaria_minutos;
  esc.tolerancia_minutos              := v.tolerancia_minutos;
  esc.tolerancia_diaria_minutos       := v.tolerancia_diaria_minutos;
  esc.hora_entrada_padrao             := v.hora_entrada_padrao;
  esc.hora_saida_padrao               := v.hora_saida_padrao;
  esc.intervalo_intrajornada_minutos  := v.intervalo_intrajornada_minutos;
  esc.dias_config                     := v.dias_config;
  IF COALESCE(v.inclui_campos_ec141, false) THEN
    esc.compensacoes_mensais          := v.compensacoes_mensais;
    esc.carga_semanal_contratada_min  := COALESCE(v.carga_semanal_contratada_min, esc.carga_semanal_contratada_min);
    esc.equalizacao_mensal_ativa      := COALESCE(v.equalizacao_mensal_ativa, esc.equalizacao_mensal_ativa);
    esc.tipo                          := COALESCE(v.tipo, esc.tipo);
    esc.jornada_semanal_minutos       := COALESCE(v.jornada_semanal_minutos, esc.jornada_semanal_minutos);
  END IF;
  RETURN esc;
END $fn$;

-- Escala vigente numa data (linha viva + versão do dia).
CREATE OR REPLACE FUNCTION public.ponto_escala_na_data(p_escala_id uuid, p_data date)
RETURNS public.ponto_escalas
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT public.ponto_escala_com_versao(e, COALESCE(p_data, CURRENT_DATE))
  FROM public.ponto_escalas e WHERE e.id = p_escala_id
$fn$;

-- Escala na data SÓ quando há alteração COM data cobrindo o dia; senão a
-- linha viva, exatamente como os leitores sempre leram. Sem SECURITY
-- DEFINER: chamada pela tela, respeita a RLS da conta.
CREATE OR REPLACE FUNCTION public.ponto_escala_na_data_agendada(p_escala_id uuid, p_data date)
RETURNS public.ponto_escalas
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM public.ponto_escala_param_versoes pv
                            WHERE pv.escala_id = e.id AND pv.inclui_campos_ec141
                              AND COALESCE(p_data, CURRENT_DATE) BETWEEN pv.vigencia_inicio AND pv.vigencia_fim)
              THEN public.ponto_escala_com_versao(e, COALESCE(p_data, CURRENT_DATE))
              ELSE e END
  FROM public.ponto_escalas e WHERE e.id = p_escala_id
$fn$;

-- Blocos diários da escala válidos na data: antes de uma alteração com data,
-- a cópia guardada na versão; senão, a tabela (como sempre).
CREATE OR REPLACE FUNCTION public.ponto_escala_periodos_na_data(p_escala_id uuid, p_data date)
RETURNS SETOF public.ponto_escala_periodos
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  WITH ver AS MATERIALIZED (
    SELECT pv.periodos FROM public.ponto_escala_param_versoes pv
     WHERE pv.escala_id = p_escala_id AND pv.inclui_campos_ec141 AND pv.periodos IS NOT NULL
       AND COALESCE(p_data, CURRENT_DATE) BETWEEN pv.vigencia_inicio AND pv.vigencia_fim
     ORDER BY pv.vigencia_inicio DESC LIMIT 1
  )
  SELECT x.* FROM ver CROSS JOIN LATERAL jsonb_populate_recordset(NULL::public.ponto_escala_periodos, ver.periodos) x
  UNION ALL
  SELECT p.* FROM public.ponto_escala_periodos p
   WHERE p.escala_id = p_escala_id AND NOT EXISTS (SELECT 1 FROM ver)
$fn$;

-- Para as telas: escalas e blocos do dia, já resolvidos pela data.
CREATE OR REPLACE FUNCTION public.ponto_escalas_na_data(p_data date, p_escala_ids uuid[] DEFAULT NULL, p_empresa_id uuid DEFAULT NULL)
RETURNS SETOF public.ponto_escalas
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT x.*
    FROM public.ponto_escalas e
    CROSS JOIN LATERAL public.ponto_escala_na_data_agendada(e.id, p_data) x
   WHERE (p_escala_ids IS NULL OR e.id = ANY (p_escala_ids))
     AND (p_empresa_id IS NULL OR e.empresa_id = p_empresa_id)
$fn$;

CREATE OR REPLACE FUNCTION public.ponto_escalas_periodos_na_data(p_escala_ids uuid[], p_data date)
RETURNS SETOF public.ponto_escala_periodos
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT b.*
    FROM unnest(p_escala_ids) AS u(escala_id)
    CROSS JOIN LATERAL public.ponto_escala_periodos_na_data(u.escala_id, p_data) b
   WHERE b.dia_semana = (ARRAY['domingo','segunda','terca','quarta','quinta','sexta','sabado'])[EXTRACT(DOW FROM p_data)::int + 1]
$fn$;

-- Carga semanal de uma escala (a mesma conta da tela de escalas).
CREATE OR REPLACE FUNCTION public.ponto_escala_carga_semanal(p_esc public.ponto_escalas, p_data date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_dias text[] := ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'];
  k      text;
  c      jsonb;
  v_min  int;
  v_sem  int := 0;
  v_n    int := 0;
  v_max  int := 0;
  v_decl int;
  v_comp int := 0;
BEGIN
  IF p_esc.id IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_esc.dias_config IS NULL OR jsonb_typeof(p_esc.dias_config) <> 'object' THEN
    RETURN jsonb_build_object(
      'carga_semanal_min', COALESCE(NULLIF(p_esc.jornada_semanal_minutos, 0), COALESCE(p_esc.jornada_diaria_minutos, 0) * 5),
      'dias_trabalhados', CASE p_esc.tipo WHEN '6x1' THEN 6 WHEN '5x2' THEN 5 ELSE NULL END,
      'maior_jornada_dia_min', p_esc.jornada_diaria_minutos,
      'compensacao_semanal_min', 0,
      'fonte', 'jornada_semanal');
  END IF;

  v_decl := (SELECT pa.intervalo_minutos FROM public.ponto_pre_assinalacao pa
              WHERE pa.escala_id = p_esc.id AND COALESCE(pa.ativa, true)
                AND pa.data_inicio <= COALESCE(p_data, CURRENT_DATE)
                AND (pa.data_fim IS NULL OR pa.data_fim >= COALESCE(p_data, CURRENT_DATE))
              ORDER BY pa.data_inicio DESC LIMIT 1);

  FOREACH k IN ARRAY v_dias LOOP
    c := p_esc.dias_config -> k;
    CONTINUE WHEN c IS NULL OR jsonb_typeof(c) <> 'object';
    BEGIN
      CONTINUE WHEN NOT COALESCE((c->>'trabalha')::boolean, false);
      IF COALESCE((c->>'tem_almoco')::boolean, false)
         AND NULLIF(c->>'inicio_almoco', '') IS NOT NULL AND NULLIF(c->>'fim_almoco', '') IS NOT NULL THEN
        v_min := (EXTRACT(EPOCH FROM ((c->>'saida')::time - (c->>'entrada')::time))::int / 60)
               - (EXTRACT(EPOCH FROM ((c->>'fim_almoco')::time - (c->>'inicio_almoco')::time))::int / 60);
      ELSE
        v_min := (EXTRACT(EPOCH FROM ((c->>'saida')::time - (c->>'entrada')::time))::int / 60)
               - COALESCE(NULLIF(c->>'intervalo', '')::int, v_decl, 0);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_min := 0;
    END;
    v_min := GREATEST(COALESCE(v_min, 0), 0);
    IF v_min > 0 THEN
      v_sem := v_sem + v_min;
      v_n := v_n + 1;
      v_max := GREATEST(v_max, v_min);
    END IF;
  END LOOP;

  IF p_esc.compensacoes_mensais IS NOT NULL AND jsonb_typeof(p_esc.compensacoes_mensais) = 'array' THEN
    BEGIN
      v_comp := COALESCE(round((SELECT sum(GREATEST(0,
                  EXTRACT(EPOCH FROM ((x->>'saida')::time - (x->>'entrada')::time))::int / 60
                  - COALESCE(NULLIF(x->>'intervalo', '')::int, 0)))
                FROM jsonb_array_elements(p_esc.compensacoes_mensais) x)::numeric / 4.345)::int, 0);
    EXCEPTION WHEN OTHERS THEN
      v_comp := 0;
    END;
  END IF;

  RETURN jsonb_build_object(
    'carga_semanal_min', v_sem + v_comp,
    'carga_base_min', v_sem,
    'compensacao_semanal_min', v_comp,
    'dias_trabalhados', v_n,
    'maior_jornada_dia_min', v_max,
    'fonte', 'dias_config');
END $fn$;

-- Há instrumento coletivo (CCT/ACT) vigente para a conta/empresa na data?
-- Usa a função da Parte 1 (ponto_tem_coletivo_vigente) quando existe.
CREATE OR REPLACE FUNCTION public._ponto_ec141_coletivo(p_tenant uuid, p_empresa uuid, p_data date)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF to_regprocedure('public.ponto_tem_coletivo_vigente(uuid,uuid,date)') IS NOT NULL THEN
    RETURN public.ponto_tem_coletivo_vigente(p_tenant, p_empresa, COALESCE(p_data, CURRENT_DATE));
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id = p_tenant
      AND COALESCE(ac.ativo, false)
      AND ac.tipo IN ('act', 'cct')
      AND (ac.vigencia_inicio IS NULL OR ac.vigencia_inicio <= COALESCE(p_data, CURRENT_DATE))
      AND (ac.vigencia_fim IS NULL OR ac.vigencia_fim >= COALESCE(p_data, CURRENT_DATE))
      AND (p_empresa IS NULL OR ac.empresa_id IS NULL OR ac.empresa_id = p_empresa));
END $fn$;

-- Refaz os blocos diários da escala a partir do dias_config (mesma regra da tela).
CREATE OR REPLACE FUNCTION public._ponto_ec141_sincronizar_periodos(p_escala_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_esc public.ponto_escalas;
  k text;
  c jsonb;
BEGIN
  v_esc := (SELECT e FROM public.ponto_escalas e WHERE e.id = p_escala_id);
  IF v_esc.id IS NULL OR v_esc.dias_config IS NULL OR jsonb_typeof(v_esc.dias_config) <> 'object' THEN
    RETURN;
  END IF;
  DELETE FROM public.ponto_escala_periodos WHERE escala_id = p_escala_id;
  FOREACH k IN ARRAY ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'] LOOP
    c := v_esc.dias_config -> k;
    CONTINUE WHEN c IS NULL OR NOT COALESCE((c->>'trabalha')::boolean, false);
    CONTINUE WHEN NULLIF(c->>'entrada', '') IS NULL OR NULLIF(c->>'saida', '') IS NULL;
    IF COALESCE((c->>'tem_almoco')::boolean, false)
       AND NULLIF(c->>'inicio_almoco', '') IS NOT NULL AND NULLIF(c->>'fim_almoco', '') IS NOT NULL THEN
      INSERT INTO public.ponto_escala_periodos (tenant_id, escala_id, dia_semana, ordem_bloco, hora_inicio, hora_fim)
      VALUES (v_esc.tenant_id, p_escala_id, k, 1, (c->>'entrada')::time, (c->>'inicio_almoco')::time),
             (v_esc.tenant_id, p_escala_id, k, 2, (c->>'fim_almoco')::time, (c->>'saida')::time);
    ELSE
      INSERT INTO public.ponto_escala_periodos (tenant_id, escala_id, dia_semana, ordem_bloco, hora_inicio, hora_fim)
      VALUES (v_esc.tenant_id, p_escala_id, k, 1, (c->>'entrada')::time, (c->>'saida')::time);
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Blocos da escala nao sincronizados: %', SQLERRM;
END $fn$;

-- Cancela o agendamento pendente da escala (só antes da data): restaura os
-- valores antigos e apaga o período congelado que encerrava na véspera.
CREATE OR REPLACE FUNCTION public.ponto_escala_cancelar_agendamento(p_escala_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_esc public.ponto_escalas;
  v_ver public.ponto_escala_param_versoes;
BEGIN
  v_esc := (SELECT e FROM public.ponto_escalas e WHERE e.id = p_escala_id);
  IF v_esc.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'escala_nao_encontrada');
  END IF;
  IF NOT public._ponto_ec141_pode_tenant(v_esc.tenant_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;

  v_ver := (SELECT pv FROM public.ponto_escala_param_versoes pv
             WHERE pv.escala_id = p_escala_id AND pv.vigencia_fim >= CURRENT_DATE
             ORDER BY pv.vigencia_fim DESC LIMIT 1);
  IF v_ver.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_agendamento',
      'mensagem', 'Não há alteração agendada para esta escala (ou a data já chegou).');
  END IF;

  PERFORM set_config('ponto.ec141_restaurando', 'on', true);
  UPDATE public.ponto_escalas e SET
    jornada_diaria_minutos         = COALESCE(v_ver.jornada_diaria_minutos, e.jornada_diaria_minutos),
    hora_entrada_padrao            = v_ver.hora_entrada_padrao,
    hora_saida_padrao              = v_ver.hora_saida_padrao,
    intervalo_intrajornada_minutos = COALESCE(v_ver.intervalo_intrajornada_minutos, e.intervalo_intrajornada_minutos),
    tolerancia_minutos             = COALESCE(v_ver.tolerancia_minutos, e.tolerancia_minutos),
    tolerancia_diaria_minutos      = COALESCE(v_ver.tolerancia_diaria_minutos, e.tolerancia_diaria_minutos),
    dias_config                    = v_ver.dias_config,
    compensacoes_mensais           = CASE WHEN v_ver.inclui_campos_ec141 THEN v_ver.compensacoes_mensais ELSE e.compensacoes_mensais END,
    carga_semanal_contratada_min   = COALESCE(v_ver.carga_semanal_contratada_min, e.carga_semanal_contratada_min),
    equalizacao_mensal_ativa       = COALESCE(v_ver.equalizacao_mensal_ativa, e.equalizacao_mensal_ativa),
    tipo                           = COALESCE(v_ver.tipo, e.tipo),
    jornada_semanal_minutos        = COALESCE(v_ver.jornada_semanal_minutos, e.jornada_semanal_minutos),
    sabado_util                    = CASE WHEN v_ver.escala_anterior ? 'sabado_util'
                                          THEN (v_ver.escala_anterior->>'sabado_util')::boolean ELSE e.sabado_util END,
    domingo_util                   = CASE WHEN v_ver.escala_anterior ? 'domingo_util'
                                          THEN (v_ver.escala_anterior->>'domingo_util')::boolean ELSE e.domingo_util END,
    parametros_vigentes_desde      = v_ver.vigentes_desde_anterior
  WHERE e.id = p_escala_id;
  PERFORM set_config('ponto.ec141_restaurando', 'off', true);

  DELETE FROM public.ponto_escala_param_versoes WHERE id = v_ver.id;
  -- Blocos diários: devolve a cópia exata de antes do agendamento.
  IF v_ver.periodos IS NOT NULL THEN
    DELETE FROM public.ponto_escala_periodos WHERE escala_id = p_escala_id;
    INSERT INTO public.ponto_escala_periodos
    SELECT x.* FROM jsonb_populate_recordset(NULL::public.ponto_escala_periodos, v_ver.periodos) x;
  ELSE
    PERFORM public._ponto_ec141_sincronizar_periodos(p_escala_id);
  END IF;

  PERFORM public._ponto_ec141_audit_escala(v_esc.tenant_id, p_escala_id,
    jsonb_build_object('agendado_para', v_ver.vigencia_fim + 1, 'marco_codigo', v_ver.marco_codigo,
                       'jornada_semanal_minutos', v_esc.jornada_semanal_minutos),
    jsonb_build_object('evento', 'ec141_agendamento_cancelado',
                       'jornada_semanal_minutos', v_ver.jornada_semanal_minutos));

  RETURN jsonb_build_object('ok', true, 'escala_id', p_escala_id,
    'data_cancelada', v_ver.vigencia_fim + 1, 'marco_codigo', v_ver.marco_codigo);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('ponto.ec141_restaurando', 'off', true);
  RETURN jsonb_build_object('ok', false, 'erro', 'falha', 'mensagem', SQLERRM);
END $fn$;

-- Cancelamento em lote (revogação ou adiamento da lei). p_tenant NULL = todas
-- as contas (só SuperAdmin/interno). p_marco_codigo NULL = todos os pendentes
-- da conta.
CREATE OR REPLACE FUNCTION public.ponto_escalas_cancelar_agendamentos_lote(p_tenant uuid, p_marco_codigo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_papel text := public._ponto_ec141_papel();
  r record;
  v_res jsonb;
  v_ok int := 0;
  v_falhas jsonb := '[]'::jsonb;
BEGIN
  IF p_tenant IS NULL AND v_papel NOT IN ('interno', 'superadmin') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF p_tenant IS NOT NULL AND NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;

  FOR r IN
    SELECT DISTINCT pv.escala_id
      FROM public.ponto_escala_param_versoes pv
      JOIN public.ponto_escalas e ON e.id = pv.escala_id
     WHERE pv.vigencia_fim >= CURRENT_DATE
       AND (p_tenant IS NULL OR e.tenant_id = p_tenant)
       AND (p_marco_codigo IS NULL OR pv.marco_codigo = p_marco_codigo)
  LOOP
    v_res := public.ponto_escala_cancelar_agendamento(r.escala_id);
    IF COALESCE((v_res->>'ok')::boolean, false) THEN
      v_ok := v_ok + 1;
    ELSE
      v_falhas := v_falhas || jsonb_build_array(jsonb_build_object('escala_id', r.escala_id, 'erro', v_res->>'erro'));
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'canceladas', v_ok, 'falhas', v_falhas);
END $fn$;

-- Agendamentos pendentes da conta, com os valores de hoje e os futuros.
CREATE OR REPLACE FUNCTION public.ponto_escalas_agendamentos(p_tenant uuid)
RETURNS TABLE(escala_id uuid, escala_nome text, vigente_a_partir_de date, motivo text, marco_codigo text,
              agendado_em timestamptz, atual_jornada_diaria_min integer, atual_carga_semanal_min integer,
              nova_jornada_diaria_min integer, nova_carga_semanal_min integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT e.id, e.nome, pv.vigencia_fim + 1, pv.motivo, pv.marco_codigo, pv.arquivada_em,
         (hh.h).jornada_diaria_minutos,
         (public.ponto_escala_carga_semanal(hh.h, CURRENT_DATE)->>'carga_semanal_min')::int,
         e.jornada_diaria_minutos,
         (public.ponto_escala_carga_semanal(e, pv.vigencia_fim + 1)->>'carga_semanal_min')::int
    FROM public.ponto_escalas e
    JOIN public.ponto_escala_param_versoes pv ON pv.escala_id = e.id AND pv.vigencia_fim >= CURRENT_DATE
    CROSS JOIN LATERAL (SELECT public.ponto_escala_com_versao(e, CURRENT_DATE) AS h) hh
   WHERE e.tenant_id = p_tenant
   ORDER BY e.nome;
END $fn$;

-- ---------------------------------------------------------------------
-- 4) VALIDAÇÃO (AVISOS, nunca bloqueia)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_escala_validar_teto(p_escala_id uuid, p_data date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_data   date := COALESCE(p_data, CURRENT_DATE);
  v_esc    public.ponto_escalas;
  v_teto   jsonb;
  v_carga  jsonb;
  v_sem    int;
  v_dias   int;
  v_maior  int;
  v_rep    int;
  v_col    boolean;
  v_avisos jsonb := '[]'::jsonb;
  v_prox   jsonb;
BEGIN
  v_esc := public.ponto_escala_na_data(p_escala_id, v_data);
  IF v_esc.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'escala_nao_encontrada');
  END IF;
  IF NOT public._ponto_ec141_pode_tenant(v_esc.tenant_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;

  v_teto  := public.ponto_teto_legal(v_esc.tenant_id, v_esc.empresa_id, v_data);
  v_carga := public.ponto_escala_carga_semanal(v_esc, v_data);
  v_sem   := (v_carga->>'carga_semanal_min')::int;
  v_dias  := (v_carga->>'dias_trabalhados')::int;
  v_maior := (v_carga->>'maior_jornada_dia_min')::int;
  v_rep   := CASE WHEN v_dias IS NULL THEN NULL ELSE 7 - v_dias END;
  v_col   := public._ponto_ec141_coletivo(v_esc.tenant_id, v_esc.empresa_id, v_data);

  -- Escala de ciclo (12x36 etc.) tem regime próprio (CLT art. 59-A): sem aviso de teto semanal aqui.
  IF COALESCE(v_esc.tipo, '') <> '12x36' AND COALESCE(v_esc.modalidade, '') <> 'movel' THEN
    IF v_sem IS NOT NULL AND v_sem > (v_teto->>'teto_semanal_min')::int THEN
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', 'acima_teto_semanal', 'nivel', 'alerta',
        'mensagem', format('Carga de %sh%s por semana acima do teto de %sh (%s).',
                    v_sem / 60, lpad((v_sem % 60)::text, 2, '0'),
                    (v_teto->>'teto_semanal_min')::int / 60, v_teto->>'nome')));
    END IF;
    IF v_maior IS NOT NULL AND v_maior > (v_teto->>'teto_diario_min')::int THEN
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', 'acima_teto_diario', 'nivel', 'info',
        'mensagem', format('Há dia com %sh%s, acima de %sh diárias. Só vale com compensação formalizada%s.',
                    v_maior / 60, lpad((v_maior % 60)::text, 2, '0'),
                    (v_teto->>'teto_diario_min')::int / 60,
                    CASE WHEN v_col THEN ' (há instrumento coletivo vigente)' ELSE ' (acordo ou instrumento coletivo)' END)));
    END IF;
    IF v_rep IS NOT NULL AND v_rep < (v_teto->>'repousos_semana')::int THEN
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', CASE WHEN v_col THEN 'repouso_por_coletivo' ELSE 'repousos_insuficientes' END,
        'nivel', CASE WHEN v_col THEN 'info' ELSE 'alerta' END,
        'mensagem', CASE WHEN v_col
          THEN format('A escala tem %s repouso(s) na semana; a regra é %s. Há instrumento coletivo vigente: confira se ele prevê a média de repousos no mês (CF art. 7º, §2º).', v_rep, v_teto->>'repousos_semana')
          ELSE format('A escala tem %s repouso(s) na semana; a regra é %s e não há instrumento coletivo vigente (CF art. 7º, XV).', v_rep, v_teto->>'repousos_semana') END));
    END IF;
  END IF;

  -- Marco futuro já ativado: avisa com antecedência (sem bloquear).
  v_prox := public.ponto_ec141_marco_alvo(v_esc.tenant_id);
  IF v_prox IS NOT NULL AND (v_prox->>'vigencia_inicio')::date > v_data
     AND v_sem IS NOT NULL AND v_sem > (v_prox->>'teto_semanal_min')::int
     AND COALESCE(v_esc.tipo, '') <> '12x36' THEN
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
      'codigo', 'marco_futuro', 'nivel', 'aviso',
      'mensagem', format('A partir de %s o teto passa a %sh semanais (%s). Esta escala tem %sh%s.',
                  to_char((v_prox->>'vigencia_inicio')::date, 'DD/MM/YYYY'),
                  (v_prox->>'teto_semanal_min')::int / 60, v_prox->>'nome',
                  v_sem / 60, lpad((v_sem % 60)::text, 2, '0'))));
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'escala_id', p_escala_id, 'data', v_data, 'teto', v_teto,
    'carga_semanal_min', v_sem, 'dias_trabalhados', v_dias, 'repousos', v_rep,
    'maior_jornada_dia_min', v_maior, 'coletivo_vigente', v_col,
    'bloqueia', false, 'avisos', v_avisos);
END $fn$;

COMMENT ON FUNCTION public.ponto_escala_validar_teto(uuid, date) IS
  'EC 141 F1 — avisos da escala contra o teto legal ATIVO na data (semanal, diario, repousos) e contra o proximo marco ativado. Nunca bloqueia a escala nem a batida (Portaria MTP 671/2021).';

-- ---------------------------------------------------------------------
-- 3) PAINEL DE IMPACTO (somente leitura)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ec141_impacto(p_tenant uuid, p_empresa uuid DEFAULT NULL, p_marco_codigo text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_papel  text := public._ponto_ec141_papel();
  v_marco  jsonb;
  v_data   date;
  v_teto   int;
  v_linhas jsonb;
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN jsonb_build_object('ok', false, 'visivel', false, 'erro', 'sem_permissao');
  END IF;

  IF v_papel IN ('interno', 'superadmin') AND p_marco_codigo IS NOT NULL THEN
    v_marco := (SELECT to_jsonb(r) FROM public.ponto_marcos_resolvidos(p_tenant) r WHERE r.codigo = p_marco_codigo);
  ELSE
    v_marco := public.ponto_ec141_marco_alvo(p_tenant);
  END IF;

  -- Para o cliente, nada aparece enquanto nenhum marco EC 141 estiver ativo.
  IF v_marco IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'visivel', false, 'previa', v_papel IN ('interno', 'superadmin'),
      'mensagem', 'Nenhum marco da EC 141 ativo para esta conta.');
  END IF;

  v_data := (v_marco->>'vigencia_inicio')::date;
  v_teto := (v_marco->>'teto_semanal_min')::int;

  v_linhas := (
  WITH esc AS MATERIALIZED (
    SELECT e.id, e.nome, e.tenant_id, e.empresa_id, e.tipo, e.modalidade,
           public.ponto_escala_com_versao(e, CURRENT_DATE) AS hoje
      FROM public.ponto_escalas e
     WHERE e.tenant_id = p_tenant
       AND COALESCE(e.ativa, true)
       AND (p_empresa IS NULL OR e.empresa_id = p_empresa)
  ),
  calc AS MATERIALIZED (
    SELECT s.*, public.ponto_escala_carga_semanal(s.hoje, CURRENT_DATE) AS carga,
           (SELECT count(DISTINCT COALESCE(NULLIF(regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''), a.colaborador_id))
              FROM public.ponto_escala_atribuicoes a
             WHERE a.escala_id = s.id AND COALESCE(a.ativa, true)
               AND (a.data_fim IS NULL OR a.data_fim >= CURRENT_DATE)) AS colaboradores,
           (SELECT jsonb_build_object('vigente_a_partir_de', pv.vigencia_fim + 1, 'marco_codigo', pv.marco_codigo)
              FROM public.ponto_escala_param_versoes pv
             WHERE pv.escala_id = s.id AND pv.vigencia_fim >= CURRENT_DATE
             ORDER BY pv.vigencia_fim DESC LIMIT 1) AS agendamento,
           public._ponto_ec141_coletivo(s.tenant_id, s.empresa_id, v_data) AS coletivo
      FROM esc s
  ),
  lin AS (
    SELECT c.*,
           (c.carga->>'carga_semanal_min')::int AS carga_min,
           (c.carga->>'dias_trabalhados')::int AS dias_trab,
           COALESCE(ec.nome_fantasia, ec.razao_social, 'Sem empresa definida') AS empresa_nome
      FROM calc c
      LEFT JOIN public.empresa_cadastro ec ON ec.id = c.empresa_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'empresa_id', l.empresa_id, 'empresa_nome', l.empresa_nome,
           'escala_id', l.id, 'escala_nome', l.nome, 'tipo', l.tipo,
           'colaboradores', l.colaboradores,
           'carga_semanal_atual_min', l.carga_min,
           'dias_trabalhados', l.dias_trab,
           'teto_semanal_min', v_teto,
           'acima_do_teto', (COALESCE(l.tipo, '') <> '12x36' AND COALESCE(l.modalidade, '') <> 'movel' AND l.carga_min > v_teto),
           'seis_dias', COALESCE(l.dias_trab, 0) >= 6,
           'coletivo_vigente', l.coletivo,
           'seis_dias_sem_coletivo', (COALESCE(l.dias_trab, 0) >= 6 AND NOT l.coletivo),
           'agendamento', CASE WHEN l.agendamento IS NULL THEN NULL
                               ELSE l.agendamento || jsonb_build_object('nova_carga_semanal_min',
                                    (public.ponto_escala_carga_semanal(
                                       (SELECT x FROM public.ponto_escalas x WHERE x.id = l.id),
                                       (l.agendamento->>'vigente_a_partir_de')::date)->>'carga_semanal_min')::int) END)
         ORDER BY l.empresa_nome, l.nome), '[]'::jsonb)
    FROM lin l);

  RETURN jsonb_build_object(
    'ok', true, 'visivel', true, 'previa', v_papel IN ('interno', 'superadmin'),
    'marco', v_marco,
    'linhas', v_linhas,
    'totais', jsonb_build_object(
      'escalas', jsonb_array_length(v_linhas),
      'escalas_acima_teto', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE (x->>'acima_do_teto')::boolean),
      'colaboradores_acima_teto', (SELECT COALESCE(sum((x->>'colaboradores')::int), 0) FROM jsonb_array_elements(v_linhas) x WHERE (x->>'acima_do_teto')::boolean),
      'escalas_6dias_sem_coletivo', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE (x->>'seis_dias_sem_coletivo')::boolean),
      'colaboradores_6dias_sem_coletivo', (SELECT COALESCE(sum((x->>'colaboradores')::int), 0) FROM jsonb_array_elements(v_linhas) x WHERE (x->>'seis_dias_sem_coletivo')::boolean),
      'escalas_com_agendamento', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->'agendamento' <> 'null'::jsonb)));
END $fn$;

COMMENT ON FUNCTION public.ponto_ec141_impacto(uuid, uuid, text) IS
  'EC 141 F1 — impacto (somente leitura) por empresa e escala: colaboradores, carga atual, teto do marco, 6 dias sem coletivo, agendamentos. Cliente so ve com marco EC 141 ativo; SuperAdmin ve a previa de qualquer marco.';

-- ---------------------------------------------------------------------
-- 5) LEITORES QUE IGNORAVAM A DATA
-- ---------------------------------------------------------------------
-- (a) Formalização com empresa + data (ESC-001/ESC-031), na versão do dia.
CREATE OR REPLACE FUNCTION public.ponto_escala_formalizacao_status_em(p_escala_id uuid, p_data date)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_data date := COALESCE(p_data, CURRENT_DATE);
  e      public.ponto_escalas;
  v_col  boolean;
BEGIN
  e := public.ponto_escala_na_data(p_escala_id, v_data);
  IF e.id IS NULL THEN
    RETURN 'nao_se_aplica';
  END IF;
  IF NOT public._ponto_ec141_pode_tenant(e.tenant_id) THEN
    RETURN 'nao_se_aplica';
  END IF;

  v_col := public._ponto_ec141_coletivo(e.tenant_id, e.empresa_id, v_data);

  -- 12x36 (art. 59-A): acordo individual ESCRITO, ACT ou CCT.
  IF COALESCE(e.tipo, '') = '12x36' THEN
    IF btrim(COALESCE(e.acordo_individual_url, '')) <> ''
       OR btrim(COALESCE(e.cct_act_url, '')) <> ''
       OR v_col THEN
      RETURN 'regular';
    END IF;
    RETURN 'pendente';
  END IF;

  -- Revezamento (CF art. 7º, XIV): 6h; acima disso só com COLETIVO.
  IF COALESCE(e.modalidade, '') = 'revezamento' THEN
    IF COALESCE(e.jornada_diaria_minutos, 0) <= 360 THEN
      RETURN 'regular';
    END IF;
    IF btrim(COALESCE(e.cct_act_url, '')) <> '' OR v_col THEN
      RETURN 'regular';
    END IF;
    RETURN 'pendente';
  END IF;

  RETURN 'nao_se_aplica';
END $fn$;

COMMENT ON FUNCTION public.ponto_escala_formalizacao_status_em(uuid, date) IS
  'Formalizacao da escala (ESC-001/ESC-031) na DATA: le a versao da escala vigente no dia e o instrumento coletivo vigente da conta/empresa naquela data. Devolve regular | pendente | nao_se_aplica.';

-- (b) Reinjeções [ec141-f1]: leitores que liam a escala/blocos VIVOS sem
--     olhar a data passam a ler a versão do dia (só quando há alteração com
--     data cobrindo o dia — sem agendamento, leem exatamente o mesmo).
--     Registro único dos pares (âncora, texto novo): o mesmo registro serve
--     para aplicar (migration/script) e para desfazer (rollback). Cada âncora
--     precisa aparecer exatamente 1 vez; senão a função NÃO é alterada.
CREATE OR REPLACE FUNCTION public._ponto_ec141_reinjecoes()
RETURNS TABLE(fn text, pares jsonb)
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  VALUES
  -- Formalização sem data delega à versão com empresa + data (hoje).
  ('public.ponto_escala_formalizacao_status(uuid)', jsonb_build_array(jsonb_build_array(
     E'    RETURN ''nao_se_aplica'';\n  END IF;\n\n  -- Coletivo (act/cct) vigente para o tenant.',
     E'    RETURN ''nao_se_aplica'';\n  END IF;\n\n  -- [ec141-f1] versao do dia + instrumento coletivo da empresa na data (ver ponto_escala_formalizacao_status_em)\n  RETURN public.ponto_escala_formalizacao_status_em(p_escala_id, CURRENT_DATE);\n\n  -- Coletivo (act/cct) vigente para o tenant.'))),
  -- Equalização: parâmetros vigentes no PRIMEIRO dia da competência (o mês
  -- que contém a data agendada segue inteiro com os valores antigos; o rateio
  -- por dia é a entrega A7).
  ('public.ponto_equalizacao_competencia(uuid,uuid,text)', jsonb_build_array(jsonb_build_array(
     'v_contratada := v_esc.contratada;',
     E'v_contratada := v_esc.contratada;\n\n  -- [ec141-f1] parametros vigentes no primeiro dia da competencia, so quando ha alteracao com data.\n'
     || E'  DECLARE v_ec141_ver public.ponto_escalas;\n'
     || E'  BEGIN\n'
     || E'    IF EXISTS (SELECT 1 FROM public.ponto_escala_param_versoes pv\n'
     || E'                WHERE pv.escala_id = v_esc.id AND v_ini BETWEEN pv.vigencia_inicio AND pv.vigencia_fim\n'
     || E'                  AND pv.inclui_campos_ec141) THEN\n'
     || E'      v_ec141_ver := public.ponto_escala_na_data(v_esc.id, v_ini);\n'
     || E'      v_esc.dias_config := v_ec141_ver.dias_config;\n'
     || E'      v_esc.jornada_diaria_minutos := v_ec141_ver.jornada_diaria_minutos;\n'
     || E'      v_esc.ativa := COALESCE(v_ec141_ver.equalizacao_mensal_ativa, false);\n'
     || E'      v_contratada := COALESCE(v_ec141_ver.carga_semanal_contratada_min, 2640);\n'
     || E'    END IF;\n'
     || E'  END;'))),
  -- Equalização da conta (lista de escalas com equalização ligada).
  ('public.ponto_equalizacao_competencia_tenant(uuid,text,uuid)', jsonb_build_array(jsonb_build_array(
     'AND COALESCE(e.equalizacao_mensal_ativa, false) = true',
     'AND COALESCE((public.ponto_escala_na_data_agendada(e.id, v_ini)).equalizacao_mensal_ativa, false) = true /* [ec141-f1] */'))),
  -- Saldo diário: fallback de jornada e de tolerância pela versão do dia.
  ('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)', jsonb_build_array(
     jsonb_build_array('v_esperado := COALESCE(v_fb_jornada, 0);',
       'v_esperado := COALESCE((public.ponto_escala_na_data_agendada(v_fb_escala_id, r.data)).jornada_diaria_minutos, v_fb_jornada, 0); /* [ec141-f1] */'),
     jsonb_build_array('ELSE COALESCE(v_fb_tol, 0) END;',
       'ELSE COALESCE((public.ponto_escala_na_data_agendada(v_fb_escala_id, r.data)).tolerancia_diaria_minutos, v_fb_tol, 0) END; /* [ec141-f1] */'))),
  -- Intervalo pela janela entre blocos: blocos do dia.
  ('public.ponto_intervalo_janela_do_dia(uuid,text,text,date)', jsonb_build_array(
     jsonb_build_array('FROM public.ponto_escala_periodos p1',
       'FROM public.ponto_escala_periodos_na_data(v_escala.id, p_data) p1 /* [ec141-f1] */'),
     jsonb_build_array('JOIN public.ponto_escala_periodos p2',
       'JOIN public.ponto_escala_periodos_na_data(v_escala.id, p_data) p2'))),
  -- Débito por batida: blocos e tolerância do dia.
  ('public.ponto_debito_batida_do_dia(uuid,text,date,time without time zone,time without time zone)', jsonb_build_array(
     jsonb_build_array(E'FROM public.ponto_escala_periodos\n',
       E'FROM public.ponto_escala_periodos_na_data(v_escala_id, p_data) /* [ec141-f1] */\n'),
     jsonb_build_array('FROM public.ponto_escalas e WHERE e.id = v_escala_id;',
       'FROM public.ponto_escala_na_data_agendada(v_escala_id, p_data) e WHERE e.id = v_escala_id;'))),
  -- Batidas geradas para dia inteiro abonado: horários do dia.
  ('public._ponto_gera_batidas_dia_inteiro(uuid,uuid,text,text,date,uuid,uuid)', jsonb_build_array(jsonb_build_array(
     'JOIN public.ponto_escalas e ON e.id = a.escala_id',
     'JOIN LATERAL public.ponto_escala_na_data_agendada(a.escala_id, p_data) e ON e.id = a.escala_id /* [ec141-f1] */'))),
  -- Troca de turno: horários das duas escalas na data da troca.
  ('public.ponto_troca_turno_solicitar(uuid,uuid,uuid,date,date,uuid,text,text)', jsonb_build_array(
     jsonb_build_array('FROM public.ponto_escalas WHERE id = a.escala_id;',
       'FROM public.ponto_escala_na_data_agendada(a.escala_id, p_data_troca) WHERE id = a.escala_id; /* [ec141-f1] */'),
     jsonb_build_array('FROM public.ponto_escalas WHERE id = b.escala_id;',
       'FROM public.ponto_escala_na_data_agendada(b.escala_id, p_data_troca) WHERE id = b.escala_id;')))
$fn$;

-- Aplica (ou desfaz) os pares de uma função. Devolve a situação.
CREATE OR REPLACE FUNCTION public._ponto_ec141_reinjetar(p_fn text, p_pares jsonb, p_desfazer boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_def  text;
  v_par  jsonb;
  v_de   text;
  v_para text;
  v_n    int;
BEGIN
  IF to_regprocedure(p_fn) IS NULL THEN
    RETURN 'ausente';
  END IF;
  v_def := pg_get_functiondef(to_regprocedure(p_fn));
  IF NOT p_desfazer AND position('[ec141-f1]' IN v_def) > 0 THEN
    RETURN 'ja_aplicada';
  END IF;
  IF p_desfazer AND position('[ec141-f1]' IN v_def) = 0 THEN
    RETURN 'nada_a_desfazer';
  END IF;
  FOR v_par IN SELECT x FROM jsonb_array_elements(p_pares) x LOOP
    v_de   := CASE WHEN p_desfazer THEN v_par->>1 ELSE v_par->>0 END;
    v_para := CASE WHEN p_desfazer THEN v_par->>0 ELSE v_par->>1 END;
    v_n := (length(v_def) - length(replace(v_def, v_de, ''))) / length(v_de);
    IF v_n <> 1 THEN
      RETURN format('NAO aplicada: ancora encontrada %s vez(es) (corpo divergente)', v_n);
    END IF;
    v_def := replace(v_def, v_de, v_para);
  END LOOP;
  EXECUTE v_def;
  RETURN CASE WHEN p_desfazer THEN 'desfeita' ELSE 'aplicada' END;
EXCEPTION WHEN OTHERS THEN
  RETURN 'NAO aplicada: ' || SQLERRM;
END $fn$;

DO $reinj$
DECLARE
  r record;
  v text;
BEGIN
  FOR r IN SELECT * FROM public._ponto_ec141_reinjecoes() LOOP
    v := public._ponto_ec141_reinjetar(r.fn, r.pares, false);
    RAISE NOTICE '[ec141-f1] %: %', r.fn, v;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[ec141-f1] reinjecoes interrompidas: %', SQLERRM;
END $reinj$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
DO $grants$
BEGIN
  REVOKE ALL ON FUNCTION public._ponto_marco_gravar(text, text, date, text, uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_marco_ativar(text, date, text, uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_marco_desativar(text, text, uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_marco_definir_data(text, date, text, uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_marco_remover_excecao(text, uuid, text) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_escala_cancelar_agendamento(uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_escalas_cancelar_agendamentos_lote(uuid, text) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public._ponto_ec141_sincronizar_periodos(uuid) FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public._ponto_ec141_audit_escala(uuid, uuid, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.ponto_marco_ativar(text, date, text, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_marco_desativar(text, text, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_marco_definir_data(text, date, text, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_marco_remover_excecao(text, uuid, text) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public._ponto_marco_gravar(text, text, date, text, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_cancelar_agendamento(uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escalas_cancelar_agendamentos_lote(uuid, text) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_teto_legal(uuid, uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_marcos_resolvidos(uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_marco_alvo(uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escalas_agendamentos(uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_validar_teto(uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_impacto(uuid, uuid, text) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_formalizacao_status_em(uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_na_data(uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_na_data_agendada(uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_periodos_na_data(uuid, date) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escalas_na_data(date, uuid[], uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escalas_periodos_na_data(uuid[], date) TO authenticated, service_role;
  REVOKE ALL ON FUNCTION public._ponto_ec141_reinjetar(text, jsonb, boolean) FROM PUBLIC, anon, authenticated;
  GRANT SELECT ON public.ponto_marcos_legais TO authenticated;
  GRANT SELECT ON public.ponto_marcos_legais_historico TO authenticated;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Permissoes EC 141 F1 nao aplicadas: %', SQLERRM;
END $grants$;

-- Tabelas novas com tenant_id recebem a cerca do QA (PONTO-270 vigia).
DO $cercas$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'qa_instalar_cercas';
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM * FROM public.qa_instalar_cercas();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel instalar as cercas: %', SQLERRM;
END $cercas$;

-- ---------------------------------------------------------------------
-- PARTE B — casos de teste do motor (qa_*) e documentação
-- ---------------------------------------------------------------------
-- ============================================================================
-- QA — EC 141/2026, ENTREGA F1 (marcos legais + escala "vigente a partir de")
--
--   PONTO-EC141-001  com os marcos EC 141 inativos, jornada e saldo de uma semana
--                    5x2 8h48 saem idênticos (nada muda sozinho)
--   PONTO-EC141-002  agendamento 8h48 -> 8h24 em D: D-1 com 8h48 = 0; D com
--                    8h48 = +24; D+1 com 8h24 = 0
--   PONTO-EC141-003  cancelar o agendamento restaura a escala e a jornada de D
--   PONTO-EC141-004  retroativo: sem justificativa recusado; sobre competência
--                    fechada recusado; em competência aberta também recusado nesta
--                    entrega (falta a reconsolidação do ponto_diario — F2)
--   PONTO-EC141-005  ponto_teto_legal ignora marco inativo e respeita ativação,
--                    mudança de data, desativação e exceção por conta; só o
--                    SuperAdmin altera marco
--   PONTO-EC141-006  painel de impacto conta a 6x1 sem instrumento coletivo e
--                    some para o cliente sem marco ativo
--   PONTO-EC141-007  batida em escala acima do teto continua aceita (nunca
--                    bloquear a batida — Portaria MTP 671/2021)
--   PONTO-EC141-008  com um agendamento para D, TUDO dos dias < D fica idêntico
--                    (saldo, jornada, horários e blocos, intervalo, débito,
--                    equalização, espelho) e cancelar devolve o estado exato
--
-- As rotinas chamam as MESMAS funções da tela (UPDATE da escala pelo gatilho,
-- ponto_escala_cancelar_agendamento, ponto_marco_*, ponto_teto_legal,
-- ponto_ec141_impacto, ponto_saldo_dias_competencia). Rodam no cercado e são
-- desfeitas pelo motor (qa_executar_descartavel). Os marcos são alterados só
-- como EXCEÇÃO DA CONTA do cercado: a regra global nunca é tocada pelo teste.
-- Variáveis só por subconsulta escalar (padrão do SQL Editor de produção). Idempotente.
-- ============================================================================


-- Ajudante: escala por dia no cercado (entrada 08:00, almoço 12:00-13:00),
-- tolerâncias zeradas, atribuída ao CPF fictício desde p_inicio.
CREATE OR REPLACE FUNCTION public.qa_ec141_escala(
  p_cpf text, p_jornada_min integer, p_dias text[], p_inicio date)
RETURNS uuid LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_id    uuid := gen_random_uuid();
  v_cfg   jsonb := '{}'::jsonb;
  v_saida text;
  k       text;
BEGIN
  v_saida := to_char(TIME '08:00' + make_interval(mins => p_jornada_min + 60), 'HH24:MI');
  FOREACH k IN ARRAY ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'] LOOP
    v_cfg := v_cfg || jsonb_build_object(k, jsonb_build_object(
      'trabalha', k = ANY (p_dias), 'tem_almoco', true, 'entrada', '08:00',
      'inicio_almoco', '12:00', 'fim_almoco', '13:00', 'saida', v_saida));
  END LOOP;
  INSERT INTO public.ponto_escalas
    (id, tenant_id, nome, tipo, modalidade, jornada_diaria_minutos, jornada_semanal_minutos,
     intervalo_intrajornada_minutos, tolerancia_minutos, tolerancia_diaria_minutos,
     hora_entrada_padrao, hora_saida_padrao, equalizacao_mensal_ativa, carga_semanal_contratada_min,
     ativa, dias_config)
  VALUES (v_id, public.qa_sandbox_tenant_id(), '[QA-EC141] Escala ' || p_cpf,
          CASE cardinality(p_dias) WHEN 6 THEN '6x1' ELSE '5x2' END, 'fixa',
          p_jornada_min, p_jornada_min * cardinality(p_dias), 60, 0, 0,
          TIME '08:00', v_saida::time, false, 2640, true, v_cfg);
  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, ativa)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_cpf, '[QA-EC141] Colaborador', p_cpf, p_inicio, true);
  -- Blocos diários, como a tela grava ao criar.
  PERFORM public._ponto_ec141_sincronizar_periodos(v_id);
  RETURN v_id;
END $fn$;

-- Ajudante: o MESMO gesto da tela de escalas — salvar novos horários (saída
-- do dia) com "vale a partir de" e, se for o caso, justificativa e marco.
CREATE OR REPLACE FUNCTION public.qa_ec141_salvar_escala(
  p_escala uuid, p_jornada_min integer, p_desde date, p_motivo text DEFAULT NULL, p_marco text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_saida text := to_char(TIME '08:00' + make_interval(mins => p_jornada_min + 60), 'HH24:MI');
BEGIN
  UPDATE public.ponto_escalas e
     SET dias_config = (SELECT jsonb_object_agg(x.k, x.v || CASE WHEN COALESCE((x.v->>'trabalha')::boolean, false)
                                                                  THEN jsonb_build_object('saida', v_saida)
                                                                  ELSE '{}'::jsonb END)
                          FROM jsonb_each(e.dias_config) x(k, v)),
         jornada_diaria_minutos = p_jornada_min,
         jornada_semanal_minutos = p_jornada_min * 5,
         hora_saida_padrao = v_saida::time,
         parametros_vigentes_desde = p_desde,
         parametros_vigencia_motivo = p_motivo,
         parametros_marco_codigo = p_marco
   WHERE e.id = p_escala;
  -- A tela regrava os blocos diários logo depois de salvar.
  PERFORM public._ponto_ec141_sincronizar_periodos(p_escala);
END $fn$;

-- Ajudante: saldo e jornada de um dia pela mesma função da tela.
CREATE OR REPLACE FUNCTION public.qa_ec141_dia(p_cpf text, p_dia date)
RETURNS jsonb LANGUAGE sql SET search_path TO 'public' AS $fn$
  SELECT jsonb_build_object('jornada', s.jornada_min, 'trabalhado', s.trabalhado_min, 'saldo', s.saldo_min)
    FROM public.ponto_saldo_dias_competencia(public.qa_sandbox_tenant_id(), p_cpf, to_char(p_dia, 'YYYY-MM')) s
   WHERE s.dia = p_dia
   LIMIT 1
$fn$;

-- ── PONTO-EC141-001 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_001()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_cpf   text := public.qa_cpf(6141);
  v_seg   date := DATE '2026-08-10';   -- semana sem feriado nacional
  v_trab  int[] := ARRAY[528, 540, 500, 528, 600];
  v_esc   uuid;
  v_dia   jsonb;
  v_falha text := NULL;
  v_ver   int;
  v_teto  jsonb;
  i       int;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- Marcos EC 141 inativos para a conta do cercado (exceção da conta),
  -- seja qual for o estado global.
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] marcos inativos', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] marcos inativos', v_t);

  r.passo_ordem := 1;
  r.passo_acao := 'Escala 5x2 de 8h48 sem nenhuma alteração; batidas de 8h48, 9h00, 8h20, 8h48 e 10h00 na semana de 10/08/2026';
  r.esperado := 'Jornada 528 nos 5 dias, 0 no fim de semana; saldo = trabalhado - 528 (0, +12, -28, 0, +72); nenhuma versão; teto CF/88 44h';
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  FOR i IN 1..5 LOOP
    PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_seg + (i - 1), v_trab[i] + 60);
  END LOOP;

  FOR i IN 1..5 LOOP
    v_dia := public.qa_ec141_dia(v_cpf, v_seg + (i - 1));
    IF (v_dia->>'jornada')::int IS DISTINCT FROM 528
       OR (v_dia->>'trabalhado')::int IS DISTINCT FROM v_trab[i]
       OR (v_dia->>'saldo')::int IS DISTINCT FROM v_trab[i] - 528 THEN
      v_falha := COALESCE(v_falha || '; ', '') || format('%s: %s', to_char(v_seg + (i - 1), 'DD/MM'), COALESCE(v_dia::text, 'sem linha'));
    END IF;
  END LOOP;
  v_dia := public.qa_ec141_dia(v_cpf, v_seg + 5);
  IF COALESCE((v_dia->>'jornada')::int, 0) <> 0 OR COALESCE((v_dia->>'saldo')::int, 0) <> 0 THEN
    v_falha := COALESCE(v_falha || '; ', '') || 'sábado: ' || v_dia::text;
  END IF;

  v_ver := (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE escala_id = v_esc);
  v_teto := public.ponto_teto_legal(v_t, NULL, DATE '2028-06-01');

  IF v_falha IS NOT NULL THEN
    r.situacao := 'falhou'; r.obtido := 'A apuração mudou sem nenhum marco ativo: ' || v_falha;
  ELSIF v_ver <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Surgiram %s versão(ões) sem edição da escala', v_ver);
  ELSIF COALESCE(v_teto->>'codigo', '') <> 'CF88_44H' OR (v_teto->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Com os marcos EC 141 inativos o teto deveria seguir 44h: ' || COALESCE(v_teto::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Semana 5x2 8h48 apurada igual (528 por dia; saldos 0, +12, -28, 0, +72); teto 44h com os marcos inativos.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-002 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_002()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_cpf  text := public.qa_cpf(6142);
  v_d    date;
  v_esc  uuid;
  v_ant  jsonb; v_dia jsonb; v_dep jsonb;
  v_ver  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- D = terça-feira daqui a pelo menos duas semanas (D-1 segunda, D+1 quarta).
  v_d := CURRENT_DATE + 14 + ((2 - EXTRACT(ISODOW FROM CURRENT_DATE + 14)::int + 7) % 7);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := format('Na tela de escalas, salvar 8h24 (17:24) com "vale a partir de" %s, marcado para EC141_42H', to_char(v_d, 'DD/MM/YYYY'));
  r.esperado := 'Versão com os valores antigos até a véspera; escala viva com 8h24 e vigente desde D';
  PERFORM public.qa_ec141_salvar_escala(v_esc, 504, v_d, NULL, 'EC141_42H');
  v_ver := (SELECT jsonb_build_object('fim', pv.vigencia_fim, 'origem', pv.origem, 'marco', pv.marco_codigo,
                                      'semanal', pv.jornada_semanal_minutos)
              FROM public.ponto_escala_param_versoes pv WHERE pv.escala_id = v_esc LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Batidas: D-1 com 8h48; D com 8h48; D+1 com 8h24';
  r.esperado := 'D-1: jornada 528, saldo 0; D: jornada 504, saldo +24; D+1: jornada 504, saldo 0';
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d - 1, 528 + 60);
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d,     528 + 60);
  PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', v_d + 1, 504 + 60);
  v_ant := public.qa_ec141_dia(v_cpf, v_d - 1);
  v_dia := public.qa_ec141_dia(v_cpf, v_d);
  v_dep := public.qa_ec141_dia(v_cpf, v_d + 1);

  IF v_ver IS NULL OR (v_ver->>'fim')::date <> v_d - 1 OR v_ver->>'origem' <> 'agendamento'
     OR COALESCE(v_ver->>'marco', '') <> 'EC141_42H' OR (v_ver->>'semanal')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'A versão congelada não ficou até a véspera de D: ' || COALESCE(v_ver::text, 'nenhuma');
  ELSIF (v_ant->>'jornada')::int IS DISTINCT FROM 528 OR (v_ant->>'saldo')::int IS DISTINCT FROM 0 THEN
    r.situacao := 'falhou'; r.obtido := 'D-1 devia ser 528/0 e veio ' || COALESCE(v_ant::text, 'sem linha');
  ELSIF (v_dia->>'jornada')::int IS DISTINCT FROM 504 OR (v_dia->>'saldo')::int IS DISTINCT FROM 24 THEN
    r.situacao := 'falhou'; r.obtido := 'D devia ser 504/+24 e veio ' || COALESCE(v_dia::text, 'sem linha');
  ELSIF (v_dep->>'jornada')::int IS DISTINCT FROM 504 OR (v_dep->>'saldo')::int IS DISTINCT FROM 0 THEN
    r.situacao := 'falhou'; r.obtido := 'D+1 devia ser 504/0 e veio ' || COALESCE(v_dep::text, 'sem linha');
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Agendado para %s: véspera 528/0, dia D 504/+24, dia seguinte 504/0.', to_char(v_d, 'DD/MM/YYYY'));
  END IF;
  r.detalhe := jsonb_build_object('versao', v_ver, 'd_menos_1', v_ant, 'd', v_dia, 'd_mais_1', v_dep);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-003 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_003()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r       public.qa_retorno;
  v_t     uuid := public.qa_sandbox_tenant_id();
  v_cpf   text := public.qa_cpf(6143);
  v_d     date := CURRENT_DATE + 10;
  v_esc   uuid;
  v_seg   boolean := false;
  v_res   jsonb;
  v_row   jsonb;
  v_jd    int;
  v_vers  int;
  v_lista int;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  PERFORM public.qa_ec141_salvar_escala(v_esc, 504, v_d, NULL, 'EC141_42H');
  v_lista := (SELECT count(*) FROM public.ponto_escalas_agendamentos(v_t) a WHERE a.escala_id = v_esc);

  r.passo_ordem := 1;
  r.passo_acao := 'Com agendamento pendente, tentar programar outra data';
  r.esperado := 'Recusado: um agendamento pendente por escala';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc, 480, v_d + 7, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_seg := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Cancelar o agendamento (ponto_escala_cancelar_agendamento)';
  r.esperado := 'Escala volta a 8h48 (17:48), sem versão pendente; jornada de D volta a 528';
  v_res := public.ponto_escala_cancelar_agendamento(v_esc);
  v_row := (SELECT jsonb_build_object('jd', e.jornada_diaria_minutos, 'js', e.jornada_semanal_minutos,
                                      'saida', e.dias_config->'segunda'->>'saida', 'desde', e.parametros_vigentes_desde)
              FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_vers := (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE escala_id = v_esc);
  v_jd := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf, v_cpf, v_d) j LIMIT 1);

  IF v_lista <> 1 THEN
    r.situacao := 'falhou'; r.obtido := 'O agendamento não apareceu na lista de agendamentos da conta';
  ELSIF NOT v_seg THEN
    r.situacao := 'falhou'; r.obtido := 'Um segundo agendamento foi aceito com outro pendente';
  ELSIF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'O cancelamento foi recusado: ' || COALESCE(v_res::text, 'nulo');
  ELSIF (v_row->>'jd')::int <> 528 OR (v_row->>'js')::int <> 2640 OR v_row->>'saida' <> '17:48' THEN
    r.situacao := 'falhou'; r.obtido := 'A escala não voltou aos valores antigos: ' || v_row::text;
  ELSIF v_vers <> 0 THEN
    r.situacao := 'falhou'; r.obtido := format('Sobrou %s versão(ões) depois do cancelamento', v_vers);
  ELSIF v_jd IS DISTINCT FROM 528 THEN
    r.situacao := 'falhou'; r.obtido := format('A jornada de D devia voltar a 528 e veio %s', COALESCE(v_jd::text, 'nula'));
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Segundo agendamento recusado; cancelamento restaurou 8h48 (17:48), sem versão pendente; D voltou a 528.';
  END IF;
  r.detalhe := jsonb_build_object('cancelamento', v_res, 'escala', v_row);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-004 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_004()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r          public.qa_retorno;
  v_t        uuid := public.qa_sandbox_tenant_id();
  v_cpf1     text := public.qa_cpf(6144);
  v_cpf2     text := public.qa_cpf(6145);
  v_esc1     uuid;
  v_esc2     uuid;
  v_mes_ant  date := date_trunc('month', CURRENT_DATE - INTERVAL '1 month')::date;
  v_sem_mot  boolean := false;
  v_fechada  boolean := false;
  v_msg      text;
  v_msg2     text;
  v_aberta   boolean := false;
  v_jd_ant   int;
BEGIN
  PERFORM public.qa_modo_ligar();
  DELETE FROM public.ponto_fechamentos WHERE tenant_id = v_t;
  v_esc1 := public.qa_ec141_escala(v_cpf1, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_esc2 := public.qa_ec141_escala(v_cpf2, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Salvar a escala valendo desde ontem, SEM justificativa';
  r.esperado := 'Recusado (data anterior a hoje exige justificativa)';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc1, 504, CURRENT_DATE - 1, NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_sem_mot := true;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'Salvar valendo desde ontem COM justificativa (competência aberta)';
  r.esperado := 'Recusado nesta entrega (dias já apurados exigiriam reconsolidação); a escala não muda';
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc1, 504, CURRENT_DATE - 1, '[QA] correção de cadastro', NULL);
    v_aberta := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg2 := SQLERRM;
  END;
  v_jd_ant := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf1, v_cpf1, CURRENT_DATE - 1) j LIMIT 1);

  r.passo_ordem := 3;
  r.passo_acao := 'Fechar a competência do mês passado e salvar outra escala valendo desde o dia 1º dele, com justificativa';
  r.esperado := 'Recusado: a alteração não retroage sobre competência fechada';
  INSERT INTO public.ponto_fechamentos (tenant_id, empresa_id, competencia, status, data_fechamento)
  VALUES (v_t, NULL, to_char(v_mes_ant, 'YYYY-MM'), 'fechado', now());
  BEGIN
    PERFORM public.qa_ec141_salvar_escala(v_esc2, 504, v_mes_ant, '[QA] tentativa sobre mês fechado', NULL);
  EXCEPTION WHEN OTHERS THEN
    v_fechada := position('fechada' IN SQLERRM) > 0;
    v_msg := SQLERRM;
  END;

  IF NOT v_sem_mot THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo sem justificativa foi aceito';
  ELSIF v_aberta OR position('ainda não está disponível' IN COALESCE(v_msg2, '')) = 0 THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo em competência aberta devia ser bloqueado nesta entrega: ' || COALESCE(v_msg2, 'aceito');
  ELSIF v_jd_ant IS DISTINCT FROM 528 THEN
    r.situacao := 'falhou'; r.obtido := format('Ontem devia manter 528 e veio %s', COALESCE(v_jd_ant::text, 'nulo'));
  ELSIF NOT v_fechada THEN
    r.situacao := 'falhou'; r.obtido := 'Retroativo sobre competência fechada não foi recusado como tal: ' || COALESCE(v_msg, 'aceito');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem justificativa: recusado. Com justificativa em mês aberto: bloqueado (falta reconsolidação; F2), ontem segue 528. Sobre mês fechado: recusado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-005 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_005()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r        public.qa_retorno;
  v_claims text := current_setting('request.jwt.claims', true);
  v_t      uuid := public.qa_sandbox_tenant_id();
  v_outra  uuid := gen_random_uuid();
  v_d      date := CURRENT_DATE + 30;
  t0 jsonb; t1 jsonb; t2 jsonb; t3 jsonb; t4 jsonb; t5 jsonb; t_outra jsonb; t_glob jsonb;
  v_user   uuid;
  v_negado jsonb;
  v_hist   int;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] estado inicial', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] estado inicial', v_t);

  r.passo_ordem := 1;
  r.passo_acao := 'Teto na data com os marcos EC 141 INATIVOS na conta';
  r.esperado := 'CF/88: 2640 min (44h), 1 repouso';
  t0 := public.ponto_teto_legal(v_t, NULL, v_d + 400);

  r.passo_ordem := 2;
  r.passo_acao := format('SuperAdmin ativa EC141_42H para a conta a partir de %s', to_char(v_d, 'DD/MM/YYYY'));
  r.esperado := 'Na véspera segue 44h; na data passa a 42h (2520), 2 repousos, divisor 210';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] ativação', v_t);
  t1 := public.ponto_teto_legal(v_t, NULL, v_d - 1);
  t2 := public.ponto_teto_legal(v_t, NULL, v_d);

  r.passo_ordem := 3;
  r.passo_acao := 'Adiar a data em 10 dias (ponto_marco_definir_data)';
  r.esperado := 'Na data antiga volta a 44h';
  PERFORM public.ponto_marco_definir_data('EC141_42H', v_d + 10, '[QA] adiamento', v_t);
  t3 := public.ponto_teto_legal(v_t, NULL, v_d);

  r.passo_ordem := 4;
  r.passo_acao := 'Desativar (revogação)';
  r.esperado := 'Mesmo depois da data, volta a 44h';
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] revogação', v_t);
  t4 := public.ponto_teto_legal(v_t, NULL, v_d + 20);

  r.passo_ordem := 5;
  r.passo_acao := 'Reativar só para a conta do cercado e comparar com outra conta';
  r.esperado := 'A exceção da conta vale só para ela; a outra conta segue a regra global';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] reativação', v_t);
  t5 := public.ponto_teto_legal(v_t, NULL, v_d);
  t_outra := public.ponto_teto_legal(v_outra, NULL, v_d);
  t_glob := public.ponto_teto_legal(NULL, NULL, v_d);   -- só a regra global
  v_hist := (SELECT count(*) FROM public.ponto_marcos_legais_historico h WHERE h.tenant_id = v_t AND h.codigo = 'EC141_42H');

  r.passo_ordem := 6;
  r.passo_acao := 'Usuário comum (não SuperAdmin) tenta ativar um marco';
  r.esperado := 'Recusado (sem_permissao)';
  v_user := public.qa_mky_usuario_empresa(v_t, 'ec141');
  PERFORM public.qa_mky_claims(v_user);
  v_negado := public.ponto_marco_ativar('EC141_40H', v_d, '[QA] tentativa indevida', v_t);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF (t0->>'teto_semanal_min')::int <> 2640 OR t0->>'codigo' <> 'CF88_44H' THEN
    r.situacao := 'falhou'; r.obtido := 'Marco inativo foi considerado: ' || t0::text;
  ELSIF (t1->>'teto_semanal_min')::int <> 2640 OR (t2->>'teto_semanal_min')::int <> 2520
        OR (t2->>'repousos_semana')::int <> 2 OR (t2->>'divisor_padrao')::int <> 210 OR t2->>'origem' <> 'conta' THEN
    r.situacao := 'falhou'; r.obtido := format('Ativação não respeitou a data: véspera %s, data %s', t1::text, t2::text);
  ELSIF (t3->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Adiamento não foi respeitado: ' || t3::text;
  ELSIF (t4->>'teto_semanal_min')::int <> 2640 THEN
    r.situacao := 'falhou'; r.obtido := 'Desativação não foi respeitada: ' || t4::text;
  ELSIF (t5->>'teto_semanal_min')::int <> 2520
        OR t_outra->>'origem' = 'conta'
        OR (t_outra->>'teto_semanal_min')::int <> (t_glob->>'teto_semanal_min')::int THEN
    r.situacao := 'falhou'; r.obtido := format('Exceção por conta vazou ou não valeu: conta %s, outra %s', t5::text, t_outra::text);
  ELSIF v_hist < 5 THEN
    r.situacao := 'falhou'; r.obtido := format('Histórico com %s registro(s); esperado ao menos 5', v_hist);
  ELSIF COALESCE(v_negado->>'erro', '') <> 'sem_permissao' THEN
    r.situacao := 'falhou'; r.obtido := 'Usuário comum conseguiu alterar marco: ' || COALESCE(v_negado::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Inativo ignorado; ativação, adiamento, desativação e reativação respeitados; exceção vale só para a conta; histórico gravado; usuário comum barrado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-006 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_006()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r         public.qa_retorno;
  v_claims  text := current_setting('request.jwt.claims', true);
  v_t       uuid := public.qa_sandbox_tenant_id();
  v_cpf     text := public.qa_cpf(6146);
  v_d       date := CURRENT_DATE + 45;
  v_esc     uuid;
  v_user    uuid;
  v_cli_off jsonb;
  v_imp     jsonb;
  v_lin     jsonb;
  v_lin_col jsonb;
  v_cli_on  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.ponto_acordos SET ativo = false WHERE tenant_id = v_t;
  PERFORM public.ponto_marco_desativar('EC141_42H', '[QA] estado inicial', v_t);
  PERFORM public.ponto_marco_desativar('EC141_40H', '[QA] estado inicial', v_t);
  -- 6x1 de 7h20 (44h), sem instrumento coletivo.
  v_esc := public.qa_ec141_escala(v_cpf, 440, ARRAY['segunda','terca','quarta','quinta','sexta','sabado'], DATE '2026-01-01');

  r.passo_ordem := 1;
  r.passo_acao := 'Usuário da conta abre o painel de impacto sem marco EC 141 ativo';
  r.esperado := 'Nada aparece (visivel = false)';
  v_user := public.qa_mky_usuario_empresa(v_t, 'ec141-imp');
  PERFORM public.qa_mky_claims(v_user);
  v_cli_off := public.ponto_ec141_impacto(v_t, NULL, NULL);
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 2;
  r.passo_acao := 'SuperAdmin ativa EC141_42H para a conta e consulta o impacto';
  r.esperado := 'A 6x1 aparece com 1 colaborador, 44h acima do teto de 42h e "6 dias sem coletivo"';
  PERFORM public.ponto_marco_ativar('EC141_42H', v_d, '[QA] impacto', v_t);
  v_imp := public.ponto_ec141_impacto(v_t, NULL, NULL);
  v_lin := (SELECT x FROM jsonb_array_elements(v_imp->'linhas') x WHERE x->>'escala_id' = v_esc::text LIMIT 1);
  PERFORM public.qa_mky_claims(v_user);
  v_cli_on := public.ponto_ec141_impacto(v_t, NULL, NULL);
  PERFORM set_config('request.jwt.claims', '', true);

  r.passo_ordem := 3;
  r.passo_acao := 'Cadastrar uma CCT vigente na data e consultar de novo';
  r.esperado := 'A mesma 6x1 deixa de contar como "sem coletivo"';
  INSERT INTO public.ponto_acordos (tenant_id, tipo, titulo, ativo, vigencia_inicio, vigencia_fim)
  VALUES (v_t, 'cct', '[QA-EC141] CCT vigente', true, CURRENT_DATE - 30, v_d + 365);
  v_lin_col := (SELECT x FROM jsonb_array_elements(public.ponto_ec141_impacto(v_t, NULL, NULL)->'linhas') x
                 WHERE x->>'escala_id' = v_esc::text LIMIT 1);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);

  IF COALESCE((v_cli_off->>'visivel')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'Sem marco ativo o cliente viu o painel: ' || COALESCE(v_cli_off::text, 'nulo');
  ELSIF v_lin IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'A escala 6x1 não apareceu no impacto: ' || COALESCE(v_imp::text, 'nulo');
  ELSIF (v_lin->>'colaboradores')::int <> 1 OR (v_lin->>'carga_semanal_atual_min')::int <> 2640
        OR NOT (v_lin->>'acima_do_teto')::boolean OR NOT (v_lin->>'seis_dias_sem_coletivo')::boolean THEN
    r.situacao := 'falhou'; r.obtido := 'Linha da 6x1 incorreta: ' || v_lin::text;
  ELSIF NOT COALESCE((v_cli_on->>'visivel')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Com marco ativo o cliente não viu o painel: ' || COALESCE(v_cli_on::text, 'nulo');
  ELSIF v_lin_col IS NULL OR (v_lin_col->>'seis_dias_sem_coletivo')::boolean THEN
    r.situacao := 'falhou'; r.obtido := 'Com CCT vigente a 6x1 seguiu como "sem coletivo": ' || COALESCE(v_lin_col::text, 'nulo');
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Sem marco ativo o cliente não vê nada; com 42h ativo a 6x1 aparece (1 colaborador, 44h, sem coletivo); com CCT vigente deixa de contar.';
  END IF;
  r.detalhe := jsonb_build_object('linha', v_lin, 'totais', v_imp->'totais');
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  BEGIN PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); EXCEPTION WHEN OTHERS THEN NULL; END;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ── PONTO-EC141-007 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_007()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6147);
  v_dia  date := CURRENT_DATE - 1;
  v_esc  uuid;
  v_aceita boolean := false;
  v_msg  text;
  v_n    int;
  v_val  jsonb;
  v_sal  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  -- 42h já em vigor para a conta; escala de 44h (acima do teto).
  PERFORM public.ponto_marco_ativar('EC141_42H', CURRENT_DATE - 30, '[QA] teto em vigor', v_t);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_val := public.ponto_escala_validar_teto(v_esc, v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Colaborador bate entrada e saída numa escala acima do teto legal ativo';
  r.esperado := 'As batidas são gravadas e apuradas; a validação só AVISA (bloqueia = false)';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '08:00', 'entrada');
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '17:48', 'saida');
    PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);
    v_aceita := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  v_n := (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf AND m.data_marcacao = v_dia);
  v_sal := public.qa_ec141_dia(v_cpf, v_dia);

  IF NOT v_aceita OR v_n <> 2 THEN
    r.situacao := 'falhou'; r.obtido := format('Batida recusada em escala acima do teto (%s marcação(ões)): %s', v_n, COALESCE(v_msg, ''));
  ELSIF COALESCE((v_val->>'bloqueia')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'A validação do teto passou a bloquear: ' || COALESCE(v_val::text, 'nulo');
  ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_val->'avisos') a WHERE a->>'codigo' = 'acima_teto_semanal') THEN
    r.situacao := 'falhou'; r.obtido := 'A escala de 44h com teto de 42h não gerou o aviso: ' || COALESCE(v_val::text, 'nulo');
  ELSIF v_sal IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O dia batido não foi apurado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Batidas gravadas e apuradas; o teto de 42h gerou só o aviso (sem bloqueio).';
  END IF;
  r.detalhe := jsonb_build_object('validacao', v_val, 'dia', v_sal);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Ajudante: "fotografia" de tudo o que a apuração e as telas leem da escala
-- num intervalo de dias (por dia) e em competências (por mês).
CREATE OR REPLACE FUNCTION public.qa_ec141_foto(
  p_cpf text, p_escala uuid, p_de date, p_ate date, p_comps text[], p_comps_espelho text[])
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  RETURN jsonb_build_object(
    'saldo', (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.dia)
                FROM (SELECT DISTINCT to_char(g::date, 'YYYY-MM') AS c
                        FROM generate_series(p_de, p_ate, INTERVAL '1 day') g) cc
                CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(v_t, p_cpf, cc.c) s
               WHERE s.dia BETWEEN p_de AND p_ate),
    'dias', (SELECT jsonb_agg(jsonb_build_object(
                'd', g::date,
                'jornada', (SELECT to_jsonb(j) FROM public.ponto_jornada_do_dia(v_t, p_cpf, p_cpf, g::date) j LIMIT 1),
                'escala', (SELECT to_jsonb(e) FROM public.ponto_escala_do_dia(v_t, p_cpf, p_cpf, g::date) e LIMIT 1),
                'intervalo', (SELECT to_jsonb(i) FROM public.ponto_intervalo_janela_do_dia(v_t, p_cpf, p_cpf, g::date) i LIMIT 1),
                'debito', public.ponto_debito_batida_do_dia(v_t, p_cpf, g::date, TIME '08:20', TIME '16:30'),
                'blocos', (SELECT jsonb_agg(jsonb_build_object('b', b.ordem_bloco, 'i', b.hora_inicio, 'f', b.hora_fim) ORDER BY b.ordem_bloco)
                             FROM public.ponto_escalas_periodos_na_data(ARRAY[p_escala], g::date) b),
                'tela', (SELECT jsonb_build_object('jd', x.jornada_diaria_minutos, 'ent', x.hora_entrada_padrao, 'sai', x.hora_saida_padrao)
                           FROM public.ponto_escalas_na_data(g::date, ARRAY[p_escala]) x))
              ORDER BY g)
               FROM generate_series(p_de, p_ate, INTERVAL '1 day') g),
    'meses', (SELECT jsonb_agg(jsonb_build_object(
                'c', c,
                'equalizacao', public.ponto_equalizacao_competencia(v_t, p_escala, c) - 'gerado_em',
                'equalizacao_conta', (SELECT jsonb_agg(jsonb_build_object('t', q.total_equalizacao_min, 'd', q.dias_uteis_efetivos))
                     FROM public.ponto_equalizacao_competencia_tenant(v_t, c, NULL) q WHERE q.escala_id = p_escala),
                'espelho', CASE WHEN c = ANY (p_comps_espelho)
                                THEN (SELECT to_jsonb(er) FROM public.ponto_espelho_resumo(v_t, p_cpf, c) er LIMIT 1) END)
              ORDER BY c)
               FROM unnest(p_comps) c));
END $fn$;

-- ── PONTO-EC141-008 ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_008()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r        public.qa_retorno;
  v_t      uuid := public.qa_sandbox_tenant_id();
  v_cpf    text := public.qa_cpf(6148);
  v_mes    date := date_trunc('month', CURRENT_DATE + 45)::date;   -- mês que contém D
  v_d      date;
  v_ant    date;
  v_comps  text[];
  v_esc    uuid;
  g        date;
  v_antes_menor  jsonb; v_depois_menor jsonb;
  v_antes_tudo   jsonb; v_cancel_tudo  jsonb;
  v_row0   jsonb; v_row2 jsonb;
  v_per0   jsonb; v_per2 jsonb;
  v_jd_d   int;
  v_res    jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  v_d   := v_mes + 14;                                   -- dia 15
  v_ant := (v_mes - INTERVAL '1 month')::date;           -- mês inteiro antes de D
  v_comps := ARRAY[to_char(v_ant, 'YYYY-MM'), to_char(v_mes, 'YYYY-MM')];

  -- Escala 5x2 8h (40h) com equalização mensal ligada (contratada 44h).
  v_esc := public.qa_ec141_escala(v_cpf, 480, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  UPDATE public.ponto_escalas SET equalizacao_mensal_ativa = true, carga_semanal_contratada_min = 2640 WHERE id = v_esc;
  -- Batidas: dias úteis variando em torno de 8h; o 1º sábado de cada mês trabalhado.
  FOR g IN SELECT x::date FROM generate_series(v_ant, v_d + 10, INTERVAL '1 day') x LOOP
    IF EXTRACT(ISODOW FROM g) BETWEEN 1 AND 5 THEN
      PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', g, 540 + ((EXTRACT(DAY FROM g)::int * 7) % 25) - 12);
    ELSIF EXTRACT(ISODOW FROM g) = 6 AND EXTRACT(DAY FROM g) <= 7 THEN
      PERFORM public.qa_ponto_dia_min(v_cpf, '[QA-EC141] Colaborador', g, 300);
    END IF;
  END LOOP;

  r.passo_ordem := 1;
  r.passo_acao := 'Fotografar tudo dos dias e meses antes de D; agendar para D (dia 15 do mês) 7h/dia, tolerâncias novas, equalização desligada e contratada 40h; a tela regrava os blocos';
  r.esperado := 'A fotografia dos dias < D (saldo, jornada, horários, blocos, intervalo, débito, equalização, espelho do mês anterior) fica idêntica; D já usa 7h';
  -- Espelho: o mês anterior (inteiro antes de D) na comparação "antes de D";
  -- os dois meses na comparação do cancelamento.
  v_antes_menor := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d - 1, v_comps, v_comps[1:1]);
  v_antes_tudo  := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d + 10, v_comps, v_comps);
  v_row0 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_per0 := (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.ponto_escala_periodos p WHERE p.escala_id = v_esc);

  UPDATE public.ponto_escalas e
     SET dias_config = (SELECT jsonb_object_agg(x.k, x.v || CASE WHEN COALESCE((x.v->>'trabalha')::boolean, false)
                                                                  THEN jsonb_build_object('saida', '16:00') ELSE '{}'::jsonb END)
                          FROM jsonb_each(e.dias_config) x(k, v)),
         jornada_diaria_minutos = 420, jornada_semanal_minutos = 2100, hora_saida_padrao = TIME '16:00',
         tolerancia_minutos = 3, tolerancia_diaria_minutos = 7,
         equalizacao_mensal_ativa = false, carga_semanal_contratada_min = 2400,
         parametros_vigentes_desde = v_d, parametros_marco_codigo = 'EC141_40H'
   WHERE e.id = v_esc;
  PERFORM public._ponto_ec141_sincronizar_periodos(v_esc);
  v_depois_menor := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d - 1, v_comps, v_comps[1:1]);
  v_jd_d := (SELECT j.jornada_min FROM public.ponto_jornada_do_dia(v_t, v_cpf, v_cpf, v_d) j LIMIT 1);

  r.passo_ordem := 2;
  r.passo_acao := 'Cancelar o agendamento';
  r.esperado := 'Escala, blocos e a fotografia de TODOS os dias (antes e depois de D) voltam exatamente ao estado anterior';
  v_res := public.ponto_escala_cancelar_agendamento(v_esc);
  v_cancel_tudo := public.qa_ec141_foto(v_cpf, v_esc, v_ant, v_d + 10, v_comps, v_comps);
  v_row2 := (SELECT to_jsonb(e) - 'updated_at' FROM public.ponto_escalas e WHERE e.id = v_esc);
  v_per2 := (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.ponto_escala_periodos p WHERE p.escala_id = v_esc);

  IF v_antes_menor IS DISTINCT FROM v_depois_menor THEN
    r.situacao := 'falhou';
    r.obtido := 'O agendamento mudou algo ANTES da data D: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_antes_menor) k
                    WHERE v_antes_menor->k IS DISTINCT FROM v_depois_menor->k), '?');
    r.detalhe := jsonb_build_object('antes', v_antes_menor, 'depois', v_depois_menor);
  ELSIF v_jd_d IS DISTINCT FROM 420 THEN
    r.situacao := 'falhou'; r.obtido := format('Em D a jornada devia ser 420 e veio %s', COALESCE(v_jd_d::text, 'nula'));
  ELSIF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    r.situacao := 'falhou'; r.obtido := 'Cancelamento recusado: ' || COALESCE(v_res::text, 'nulo');
  ELSIF v_row0 IS DISTINCT FROM v_row2 THEN
    r.situacao := 'falhou'; r.obtido := 'A escala não voltou ao estado exato: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_row0) k WHERE v_row0->k IS DISTINCT FROM v_row2->k), '?');
  ELSIF v_per0 IS DISTINCT FROM v_per2 THEN
    r.situacao := 'falhou'; r.obtido := 'Os blocos diários não voltaram ao estado exato';
  ELSIF v_antes_tudo IS DISTINCT FROM v_cancel_tudo THEN
    r.situacao := 'falhou';
    r.obtido := 'Depois de cancelar a apuração não voltou ao estado anterior: '
      || COALESCE((SELECT string_agg(k, ', ') FROM jsonb_object_keys(v_antes_tudo) k
                    WHERE v_antes_tudo->k IS DISTINCT FROM v_cancel_tudo->k), '?');
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Agendado para %s: dias e meses anteriores idênticos (saldo, jornada, horários, blocos, intervalo, débito, equalização, espelho); D com 7h; cancelar devolveu escala, blocos e apuração exatos.', to_char(v_d, 'DD/MM/YYYY'));
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
    RAISE NOTICE 'Motor de QA ausente; casos PONTO-EC141 não documentados.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; casos PONTO-EC141 não documentados.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-EC141-001',
   'EC 141: com os marcos 42h/40h inativos, a apuração de uma semana 5x2 8h48 não muda',
   'alternativo', 'critica', 'aprovado', 'api',
   'CF art. 7º, XIII (redação original, 44h); EC 141/2026, art. 6º (transição só por ativação manual)',
   'A entrega F1 cria os marcos legais e a escala com "vigente a partir de" desligados. Nada pode mudar sozinho numa data: sem marco ativo e sem agendamento, jornada e saldo saem exatamente como antes.',
   'Cercado de QA; marcos EC141_42H e EC141_40H inativos para a conta (exceção da conta).',
   '[{"ordem":1,"acao":"Escala 5x2 8h48 sem edição; batidas de 8h48, 9h, 8h20, 8h48 e 10h na semana de 10/08/2026","resultado_esperado":"Jornada 528 por dia útil; saldos 0, +12, -28, 0, +72; sábado 0; nenhuma versão; teto 44h"}]'::jsonb,
   'Apuração idêntica e teto CF/88 enquanto nenhum marco EC 141 estiver ativo.',
   'Fotografia mínima da F1 (Plano Mestre, princípio 1). Semana fixa para não depender de feriado.'),
  (v_mod, 'PONTO-EC141-002',
   'Escala com "vale a partir de": a nova jornada só vale da data em diante',
   'feliz', 'critica', 'aprovado', 'api',
   'EC 141/2026, art. 6º e 7º; CLT art. 58 e 59; CLT art. 468 (alteração só para frente)',
   'A HE é diária (trabalhado - jornada do dia). Ao agendar 8h48 -> 8h24 para a data D, a véspera continua com 8h48 e o dia D em diante passa a 8h24. Antes desta entrega o gatilho de versão só sabia congelar até ontem.',
   'Cercado de QA; escala 5x2 8h48 atribuída.',
   '[{"ordem":1,"acao":"Salvar 8h24 com \"vale a partir de\" D (terça futura), marco EC141_42H","resultado_esperado":"Versão antiga até D-1 (origem agendamento, marco gravado)"},
     {"ordem":2,"acao":"D-1 com 8h48; D com 8h48; D+1 com 8h24","resultado_esperado":"D-1: 528/0; D: 504/+24; D+1: 504/0"}]'::jsonb,
   'Corte exato na data agendada, sem tocar o passado.',
   'Mesmo gesto da tela (UPDATE da escala com parametros_vigentes_desde); saldo pela ponto_saldo_dias_competencia.'),
  (v_mod, 'PONTO-EC141-003',
   'Cancelar o agendamento da escala restaura os valores antigos (e só um agendamento por escala)',
   'feliz', 'alta', 'aprovado', 'api',
   'EC 141/2026 (lei pode ser revogada/adiada antes da data); CLT art. 468',
   'Se a lei mudar antes da data, o RH (ou o lote do SuperAdmin) cancela o agendamento e a escala volta a ser o que era, sem resíduo de versão.',
   'Cercado de QA; escala 5x2 8h48 com 8h24 agendada para daqui a 10 dias.',
   '[{"ordem":1,"acao":"Tentar agendar outra data com um pendente","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"ponto_escala_cancelar_agendamento","resultado_esperado":"Escala volta a 8h48 (17:48), nenhuma versão pendente; jornada de D = 528"}]'::jsonb,
   'Cancelamento devolve a escala ao estado anterior.',
   'O lote (ponto_escalas_cancelar_agendamentos_lote) chama a mesma função por escala.'),
  (v_mod, 'PONTO-EC141-004',
   'Alteração retroativa da escala: exige justificativa, nunca atinge competência fechada e, nesta entrega, fica bloqueada',
   'negativo', 'critica', 'aprovado', 'api',
   'Plano Mestre do Ponto, princípio 3 (meses fechados são intocáveis); Súmula 338 do TST',
   'Uma data anterior a hoje reescreve dias já apurados. Exige justificativa e nunca atinge competência fechada; como os dias já consolidados no ponto_diario precisariam ser recalculados e essa reconsolidação ainda não existe, a F1 bloqueia o retroativo (liberação prevista na F2).',
   'Cercado de QA; duas escalas 5x2 8h48; fechamento do mês passado criado no passo 3.',
   '[{"ordem":1,"acao":"Valer desde ontem, sem justificativa","resultado_esperado":"Recusado"},
     {"ordem":2,"acao":"Valer desde ontem, com justificativa","resultado_esperado":"Bloqueado nesta entrega; ontem segue 528"},
     {"ordem":3,"acao":"Fechar o mês passado e valer desde o dia 1º dele","resultado_esperado":"Recusado (competência fechada)"}]'::jsonb,
   'Retroativo controlado; mês fechado protegido.',
   'Gatilho ponto_escala_arquiva_versao.'),
  (v_mod, 'PONTO-EC141-005',
   'Teto legal: marco inativo é ignorado; ativação, data, desativação e exceção por conta são respeitadas; só o SuperAdmin altera',
   'feliz', 'critica', 'aprovado', 'api',
   'CF art. 7º, XIII e XV (redação da EC 141/2026); EC 141/2026, art. 6º',
   'Decisão da fundadora (30/10/2026): a transição é manual. ponto_teto_legal só considera marcos ATIVOS, a exceção da conta vence a regra global, e toda alteração fica no histórico.',
   'Cercado de QA; marcos alterados apenas como exceção da conta do cercado.',
   '[{"ordem":1,"acao":"Teto com os marcos inativos","resultado_esperado":"44h"},
     {"ordem":2,"acao":"Ativar 42h em D","resultado_esperado":"D-1: 44h; D: 42h, 2 repousos, divisor 210"},
     {"ordem":3,"acao":"Adiar 10 dias","resultado_esperado":"D: 44h"},
     {"ordem":4,"acao":"Desativar","resultado_esperado":"44h mesmo após a data"},
     {"ordem":5,"acao":"Reativar só na conta; comparar com outra conta","resultado_esperado":"Só a conta muda"},
     {"ordem":6,"acao":"Usuário comum tenta ativar","resultado_esperado":"sem_permissao"}]'::jsonb,
   'Teto obedece só ao gesto do SuperAdmin.',
   'Histórico em ponto_marcos_legais_historico.'),
  (v_mod, 'PONTO-EC141-006',
   'Painel de impacto da EC 141 conta a 6x1 sem instrumento coletivo e fica oculto ao cliente sem marco ativo',
   'feliz', 'alta', 'aprovado', 'api',
   'CF art. 7º, XV e §2º (redação da EC 141/2026): 2 repousos, ou média mensal só por CCT/ACT',
   'O painel é somente leitura. Para o cliente só aparece com marco EC 141 ativo; mostra por empresa e escala os colaboradores, a carga atual contra o teto e a 6x1 sem coletivo.',
   'Cercado de QA; escala 6x1 7h20 (44h) com 1 colaborador; sem coletivo.',
   '[{"ordem":1,"acao":"Cliente abre o painel sem marco ativo","resultado_esperado":"visivel = false"},
     {"ordem":2,"acao":"Ativar 42h e consultar","resultado_esperado":"6x1 com 1 colaborador, 44h acima do teto, 6 dias sem coletivo; cliente passa a ver"},
     {"ordem":3,"acao":"Cadastrar CCT vigente e consultar","resultado_esperado":"Deixa de contar como sem coletivo"}]'::jsonb,
   'Impacto correto e oculto enquanto a lei não for ativada.',
   'ponto_ec141_impacto; coletivo por ponto_tem_coletivo_vigente (Parte 1) quando existe.'),
  (v_mod, 'PONTO-EC141-007',
   'Batida em escala acima do teto legal continua aceita (o teto só gera aviso)',
   'negativo', 'critica', 'aprovado', 'api',
   'Portaria MTP 671/2021 (o registro não pode ser impedido); Plano Mestre do Ponto, princípio 2',
   'Mesmo com o teto de 42h em vigor, a batida de quem está numa escala de 44h é gravada e apurada. A validação do teto devolve avisos e nunca bloqueia.',
   'Cercado de QA; EC141_42H ativo para a conta desde 30 dias atrás; escala 5x2 8h48.',
   '[{"ordem":1,"acao":"Bater entrada e saída ontem e consolidar o dia","resultado_esperado":"2 marcações gravadas; dia apurado; validação com aviso acima_teto_semanal e bloqueia = false"}]'::jsonb,
   'Nunca bloquear a batida.',
   'ponto_escala_validar_teto é a função usada como aviso na tela de escalas.'),
  (v_mod, 'PONTO-EC141-008',
   'Com uma alteração agendada para D, nada dos dias anteriores a D muda; cancelar devolve o estado exato',
   'alternativo', 'critica', 'aprovado', 'api',
   'CLT art. 468 (alteração só para frente); Plano Mestre do Ponto, princípios 1 e 4',
   'Critério "nada muda antes da data D": saldo, jornada do dia, horários esperados e blocos diários, intervalo, débito por batida, equalização (da escala e da conta) e espelho seguem idênticos para os dias e meses anteriores a D. O cancelamento restaura escala, blocos e apuração exatamente.',
   'Cercado de QA; escala 5x2 8h com equalização (contratada 44h); batidas do mês anterior a D até D+10.',
   '[{"ordem":1,"acao":"Fotografar; agendar 7h/dia, tolerâncias, equalização desligada e contratada 40h para D (dia 15); a tela regrava os blocos","resultado_esperado":"Fotografia dos dias < D idêntica; D com jornada 420"},
     {"ordem":2,"acao":"Cancelar o agendamento","resultado_esperado":"Escala, blocos e fotografia de todos os dias iguais ao estado anterior"}]'::jsonb,
   'Nada muda antes de D; cancelamento exato.',
   'Leitores cobertos por reinjeção [ec141-f1] e pelas funções ponto_escala_na_data_agendada / ponto_escala_periodos_na_data.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo,
    passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
    base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes,
    pre_condicoes = EXCLUDED.pre_condicoes, status = 'aprovado';

  -- PONTO-153 continua valendo; a descrição ganha o "vale a partir de".
  UPDATE public.qa_casos_teste
     SET observacoes = COALESCE(observacoes, '') ||
         CASE WHEN position('EC 141 F1' IN COALESCE(observacoes, '')) > 0 THEN ''
              ELSE ' EC 141 F1 (30/10/2026): a edição pode valer "a partir de" uma data (versão congelada até a véspera); sem data, segue congelando até ontem. Na edição com data a versão guarda também compensações, carga contratada, equalização, tipo e jornada semanal (ver PONTO-EC141-002/003/004).' END
   WHERE codigo = 'PONTO-153';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PONTO-EC141-001', 'qa_caso_ponto_ec141_001', true),
      ('PONTO-EC141-002', 'qa_caso_ponto_ec141_002', true),
      ('PONTO-EC141-003', 'qa_caso_ponto_ec141_003', true),
      ('PONTO-EC141-004', 'qa_caso_ponto_ec141_004', true),
      ('PONTO-EC141-005', 'qa_caso_ponto_ec141_005', true),
      ('PONTO-EC141-006', 'qa_caso_ponto_ec141_006', true),
      ('PONTO-EC141-007', 'qa_caso_ponto_ec141_007', true),
      ('PONTO-EC141-008', 'qa_caso_ponto_ec141_008', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentação PONTO-EC141 não registrada: %', SQLERRM;
END $doc$;

-- Resumo da bateria da entrega (usado na conferência do script de entrega).
-- Roda os casos pelo motor (descartável: nada fica na base) e devolve
-- "codigo:situacao | ...". Sem motor, devolve o aviso em vez de quebrar.
CREATE OR REPLACE FUNCTION public.qa_ponto_ec141_f1_resumo()
RETURNS text LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  v_out  text := '';
  v_cod  text;
  v_fn   text;
  v_sit  text;
BEGIN
  IF to_regprocedure('public.qa_executar_descartavel(text)') IS NULL THEN
    RETURN 'motor de QA ausente';
  END IF;
  FOR v_cod, v_fn IN
    SELECT x.cod, x.fn FROM (VALUES
      ('PONTO-EC141-001', 'qa_caso_ponto_ec141_001'), ('PONTO-EC141-002', 'qa_caso_ponto_ec141_002'),
      ('PONTO-EC141-003', 'qa_caso_ponto_ec141_003'), ('PONTO-EC141-004', 'qa_caso_ponto_ec141_004'),
      ('PONTO-EC141-005', 'qa_caso_ponto_ec141_005'), ('PONTO-EC141-006', 'qa_caso_ponto_ec141_006'),
      ('PONTO-EC141-007', 'qa_caso_ponto_ec141_007'), ('PONTO-EC141-008', 'qa_caso_ponto_ec141_008'),
      ('PONTO-153', 'qa_caso_ponto_153'),
      ('PONTO-478', 'qa_caso_ponto_478')) AS x(cod, fn)
  LOOP
    IF to_regprocedure('public.' || v_fn || '()') IS NULL THEN
      v_sit := 'ausente';
    ELSE
      BEGIN
        v_sit := (SELECT (public.qa_executar_descartavel(v_fn)).situacao::text);
      EXCEPTION WHEN OTHERS THEN
        v_sit := 'erro: ' || SQLERRM;
      END;
    END IF;
    v_out := v_out || CASE WHEN v_out = '' THEN '' ELSE ' | ' END || v_cod || ':' || COALESCE(v_sit, 'nulo');
  END LOOP;
  RETURN v_out;
END $fn$;

-- =====================================================================
-- CONFERÊNCIA FINAL (um SELECT)
-- =====================================================================
SELECT
  (SELECT string_agg(m.codigo || '=' || CASE WHEN m.ativo THEN 'ATIVO' ELSE 'inativo' END || ' desde ' || to_char(m.vigencia_inicio, 'DD/MM/YYYY'), ' | ' ORDER BY m.vigencia_inicio)
     FROM public.ponto_marcos_legais m WHERE m.tenant_id IS NULL) AS marcos_e_status,
  (SELECT count(*) FROM public.ponto_marcos_legais m WHERE m.tenant_id IS NOT NULL) AS excecoes_de_conta,
  public.ponto_teto_legal(NULL, NULL, CURRENT_DATE)->>'codigo' AS teto_hoje_deve_ser_cf88,
  (SELECT bool_and(to_regprocedure(r.fn) IS NOT NULL AND position('[ec141-f1]' IN pg_get_functiondef(to_regprocedure(r.fn))) > 0)
     FROM public._ponto_ec141_reinjecoes() r) AS reinjecoes_todas_aplicadas,
  (SELECT string_agg(split_part(replace(r.fn, 'public.', ''), '(', 1) || '=' ||
            CASE WHEN to_regprocedure(r.fn) IS NULL THEN 'AUSENTE'
                 WHEN position('[ec141-f1]' IN pg_get_functiondef(to_regprocedure(r.fn))) > 0 THEN 'aplicada'
                 ELSE 'NAO APLICADA (corpo divergente)' END, ' | ')
     FROM public._ponto_ec141_reinjecoes() r) AS reinjecoes,
  (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = 'public' AND c.table_name = 'ponto_escalas'
      AND c.column_name IN ('parametros_vigentes_desde', 'parametros_vigencia_motivo', 'parametros_marco_codigo')) = 3 AS colunas_escala_ok,
  (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = 'public' AND c.table_name = 'ponto_escala_param_versoes'
      AND c.column_name IN ('compensacoes_mensais', 'carga_semanal_contratada_min', 'equalizacao_mensal_ativa', 'tipo',
                            'jornada_semanal_minutos', 'inclui_campos_ec141', 'origem', 'motivo', 'marco_codigo',
                            'criado_por', 'vigentes_desde_anterior', 'periodos', 'escala_anterior')) = 13 AS colunas_versao_ok,
  (position('parametros_vigentes_desde' IN pg_get_functiondef('public.ponto_escala_arquiva_versao()'::regprocedure)) > 0
     AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'trg_ponto_escala_arquiva_versao'
                    AND t.tgrelid = 'public.ponto_escalas'::regclass AND t.tgenabled <> 'D')) AS gatilho_atualizado_e_ligado,
  position('inclui_campos_ec141' IN pg_get_functiondef('public.ponto_escala_com_versao(public.ponto_escalas,date)'::regprocedure)) > 0 AS overlay_atualizado,
  (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN (
      'ponto_teto_legal', 'ponto_marco_ativar', 'ponto_marco_desativar', 'ponto_marco_definir_data', 'ponto_marco_remover_excecao',
      'ponto_escala_cancelar_agendamento', 'ponto_escalas_cancelar_agendamentos_lote', 'ponto_escalas_agendamentos',
      'ponto_escala_validar_teto', 'ponto_ec141_impacto', 'ponto_escala_formalizacao_status_em', 'ponto_escala_carga_semanal',
      'ponto_escala_na_data_agendada', 'ponto_escala_periodos_na_data', 'ponto_escalas_na_data', 'ponto_escalas_periodos_na_data')) AS funcoes_novas_de_16,
  (SELECT count(*) FROM public.ponto_escala_param_versoes WHERE vigencia_fim >= CURRENT_DATE) AS agendamentos_pendentes,
  (to_regclass('backup.ponto_escalas_ec141f1_20261030') IS NOT NULL
     AND to_regclass('backup.ponto_escala_param_versoes_ec141f1_20261030') IS NOT NULL) AS backup_ok,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo LIKE 'PONTO-EC141-%') AS casos_documentados_de_8,
  public.qa_ponto_ec141_f1_resumo() AS bateria;
