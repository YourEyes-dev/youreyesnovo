-- =====================================================================
-- PONTO — EC 141/2026, ENTREGA F2a: validação ao salvar + assistente
-- "Migrar para 42h/40h" + aditivo individual (assinatura eletrônica) +
-- cancelamento em lote da migração.
--
-- Decisões da fundadora (invioláveis):
--   · Transição MANUAL: tudo aqui só age com marco EC 141 ATIVO (gesto do
--     SuperAdmin). Sem marco ativo, nada muda (nem cálculo, nem tela, nem
--     o salvar da escala — continua só o aviso da F1).
--   · Destino 42h ou 40h direto, por empresa, com exceção por colaborador.
--     Sem CCT/ACT vigente para o colaborador (ponto_instrumento_do_colaborador)
--     o assistente RECOMENDA 40h (5 x 8h) e só libera 8h24/dia (42h em 5 dias)
--     com confirmação explícita (aviso forte — EC 141/2026, art. 7º remete à
--     negociação coletiva a jornada diária acima de 8h na transição).
--   · Só proibição legal bloqueia, e só ao SALVAR a escala. Nunca a batida
--     (Portaria MTP 671/2021).
--   · Sem redução salarial (EC 141/2026, art. 2º; CLT art. 468) — o aditivo diz.
--
-- O QUE ENTRA
--   1) ponto_escala_ec141_checar / ponto_escala_ec141_validar_salvar e o
--      gatilho trg_ponto_escala_zz_ec141_valida (BEFORE INSERT OR UPDATE,
--      roda depois do gatilho de versão da F1): com marco EC 141 ativo e em
--      vigor na data em que a escala passa a valer, BLOQUEIA
--        (a) carga semanal acima do teto (CF art. 7º, XIII, red. EC 141);
--        (b) 6 dias de trabalho sem instrumento coletivo vigente
--            (CF art. 7º, XV e §2º, red. EC 141).
--      O resto é aviso. Edição que não mexe na carga nem nos dias (ex.:
--      tolerância de uma escala ainda não migrada) não bloqueia.
--   2) Assistente: ponto_ec141_migracao_previa / _aplicar. Grava pelo
--      MESMO mecanismo da F1 ("vale a partir de" = data do marco): quando
--      todos os colaboradores da escala vão para o mesmo destino, agenda a
--      própria escala; senão cria a escala "<nome> — 40h (EC 141)" e troca a
--      atribuição a partir da data (a anterior termina na véspera). Nunca
--      altera dias anteriores à data. Idempotente (índice único por
--      colaborador + marco). Auditoria em ponto_ec141_migracoes.
--   3) Aditivo individual por colaborador migrado (ponto_ec141_aditivos),
--      texto por modelo com variáveis; o envio usa o fluxo de assinatura
--      eletrônica existente (assinatura_solicitacoes, contexto
--      'ponto_ec141_aditivo', função de borda assinatura-solicitar).
--   4) ponto_ec141_migracao_cancelar: desfaz a migração da empresa (antes da
--      data), restaurando o estado exato; aditivos pendentes cancelados.
--
-- GARANTIAS
--   · Sem marco EC 141 ativo para a conta, o gatilho sai na primeira linha.
--   · Variáveis só por subconsulta escalar; tabelas por EXECUTE (o mesmo corpo
--     vai no script de entrega do SQL Editor).
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 0) TABELAS
-- ---------------------------------------------------------------------
DO $tab_f2$
BEGIN
  IF to_regclass('public.ponto_ec141_migracoes') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_ec141_migracoes ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,'
      || ' empresa_id uuid,'
      || ' marco_codigo text NOT NULL,'
      || ' vigencia_inicio date NOT NULL,'
      || ' destino_padrao text NOT NULL,'
      || ' excecoes jsonb NOT NULL DEFAULT ''{}''::jsonb,'
      || ' confirmou_8h24 boolean NOT NULL DEFAULT false,'
      || ' status text NOT NULL DEFAULT ''aplicada'','
      || ' resumo jsonb,'
      || ' acionado_por uuid,'
      || ' acionado_por_email text,'
      || ' acionado_em timestamptz NOT NULL DEFAULT now(),'
      || ' cancelado_por uuid,'
      || ' cancelado_por_email text,'
      || ' cancelado_em timestamptz,'
      || ' cancelado_motivo text'
      || ')';
  END IF;
  IF to_regclass('public.ponto_ec141_migracao_itens') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_ec141_migracao_itens ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' migracao_id uuid NOT NULL REFERENCES public.ponto_ec141_migracoes(id) ON DELETE CASCADE,'
      || ' tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,'
      || ' empresa_id uuid,'
      || ' marco_codigo text NOT NULL,'
      || ' colaborador_chave text NOT NULL,'
      || ' colaborador_id text,'
      || ' colaborador_cpf text,'
      || ' colaborador_nome text,'
      || ' escala_origem_id uuid,'
      || ' escala_destino_id uuid,'
      || ' modo text NOT NULL,'
      || ' destino text NOT NULL,'
      || ' atribuicao_anterior jsonb,'
      || ' atribuicao_nova_id uuid,'
      || ' carga_antes_min integer,'
      || ' carga_depois_min integer,'
      || ' tem_coletivo boolean,'
      || ' avisos jsonb,'
      || ' status text NOT NULL DEFAULT ''ativo'','
      || ' criado_em timestamptz NOT NULL DEFAULT now()'
      || ')';
  END IF;
  IF to_regclass('public.ponto_ec141_aditivos') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.ponto_ec141_aditivos ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,'
      || ' empresa_id uuid,'
      || ' migracao_id uuid REFERENCES public.ponto_ec141_migracoes(id) ON DELETE CASCADE,'
      || ' item_id uuid REFERENCES public.ponto_ec141_migracao_itens(id) ON DELETE CASCADE,'
      || ' colaborador_id text,'
      || ' colaborador_cpf text,'
      || ' colaborador_nome text,'
      || ' vigencia_inicio date NOT NULL,'
      || ' modelo_versao text NOT NULL,'
      || ' variaveis jsonb NOT NULL,'
      || ' texto text NOT NULL,'
      || ' status text NOT NULL DEFAULT ''pendente_envio'','
      || ' solicitacao_id uuid,'
      || ' criado_em timestamptz NOT NULL DEFAULT now(),'
      || ' atualizado_em timestamptz NOT NULL DEFAULT now()'
      || ')';
  END IF;
END $tab_f2$;

COMMENT ON TABLE public.ponto_ec141_migracoes IS
  'EC 141 F2a — auditoria de cada acionamento do assistente "Migrar para 42h/40h" (quem, quando, empresa, marco, destino, exceções) e do cancelamento.';
COMMENT ON TABLE public.ponto_ec141_migracao_itens IS
  'EC 141 F2a — um registro por colaborador migrado: escala de origem/destino, modo (escala agendada ou escala nova), atribuição anterior (para restaurar). Único ativo por colaborador + marco (idempotência).';
COMMENT ON TABLE public.ponto_ec141_aditivos IS
  'EC 141 F2a — aditivo individual de alteração de horário (modelo com variáveis; EC 141/2026 art. 2º, CLT art. 468). O envio para assinatura usa assinatura_solicitacoes (contexto ponto_ec141_aditivo).';

CREATE UNIQUE INDEX IF NOT EXISTS ponto_ec141_migracao_itens_ativo_uk
  ON public.ponto_ec141_migracao_itens (tenant_id, marco_codigo, colaborador_chave) WHERE status = 'ativo';
CREATE INDEX IF NOT EXISTS ponto_ec141_migracao_itens_mig
  ON public.ponto_ec141_migracao_itens (migracao_id);
CREATE INDEX IF NOT EXISTS ponto_ec141_migracoes_tenant
  ON public.ponto_ec141_migracoes (tenant_id, acionado_em DESC);
CREATE INDEX IF NOT EXISTS ponto_ec141_aditivos_tenant
  ON public.ponto_ec141_aditivos (tenant_id, status);

ALTER TABLE public.ponto_ec141_migracoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ponto_ec141_migracao_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ponto_ec141_aditivos ENABLE ROW LEVEL SECURITY;

-- Leitura: conta do usuário com acesso a Ponto/Colaboradores, ou SuperAdmin.
-- Escrita: só pelas funções abaixo (SECURITY DEFINER) e pela função de borda.
DO $pol_f2$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ponto_ec141_migracoes', 'ponto_ec141_migracao_itens', 'ponto_ec141_aditivos'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_leitura', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING ('
                || '(tenant_id = public.get_user_tenant_id() AND public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY[''ponto'', ''colaboradores'']))'
                || ' OR public.is_superadmin(auth.uid()))', t || '_leitura', t);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politicas EC 141 F2a nao aplicadas: %', SQLERRM;
END $pol_f2$;

-- ---------------------------------------------------------------------
-- 1) VALIDAÇÃO AO SALVAR
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ponto_ec141_horas(p_min integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT CASE WHEN p_min IS NULL THEN '-'
              WHEN p_min % 60 = 0 THEN (p_min / 60)::text || 'h'
              ELSE (p_min / 60)::text || 'h' || lpad((p_min % 60)::text, 2, '0') END
$fn$;

-- Tem marco EC 141 ATIVO para a conta? (saída rápida do gatilho)
CREATE OR REPLACE FUNCTION public._ponto_ec141_tem_marco_ativo(p_tenant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.ponto_marcos_resolvidos(p_tenant) r
                  WHERE r.ativo AND r.codigo LIKE 'EC141%')
$fn$;

-- Confere a escala NOVA (como ficará) contra o teto EC 141 em vigor na data
-- em que ela passa a valer. Devolve {aplica, bloqueia, erros[], avisos[]}.
-- p_antigo NULL = escala nova (INSERT).
CREATE OR REPLACE FUNCTION public.ponto_escala_ec141_checar(
  p_novo public.ponto_escalas, p_antigo public.ponto_escalas, p_desde date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_desde  date := GREATEST(COALESCE(p_desde, CURRENT_DATE), CURRENT_DATE);
  v_teto   jsonb;
  v_carga  jsonb;
  v_carga0 jsonb;
  v_sem    int;
  v_dias   int;
  v_maior  int;
  v_sem0   int;
  v_dias0  int;
  v_tsem   int;
  v_trep   int;
  v_col    boolean;
  v_mudou  boolean;
  v_erros  jsonb := '[]'::jsonb;
  v_avisos jsonb := '[]'::jsonb;
BEGIN
  IF p_novo.tenant_id IS NULL THEN
    RETURN jsonb_build_object('aplica', false, 'bloqueia', false, 'erros', '[]'::jsonb, 'avisos', '[]'::jsonb);
  END IF;
  v_teto := public.ponto_teto_legal(p_novo.tenant_id, p_novo.empresa_id, v_desde);
  -- Só com um marco da EC 141 ATIVO e já em vigor na data da escala.
  IF COALESCE(v_teto->>'codigo', '') NOT LIKE 'EC141%'
     OR COALESCE(p_novo.tipo, '') = '12x36' OR COALESCE(p_novo.modalidade, '') = 'movel' THEN
    RETURN jsonb_build_object('aplica', false, 'bloqueia', false, 'erros', '[]'::jsonb, 'avisos', '[]'::jsonb,
                              'teto', v_teto, 'desde', v_desde);
  END IF;

  v_tsem  := (v_teto->>'teto_semanal_min')::int;
  v_trep  := (v_teto->>'repousos_semana')::int;
  v_carga := public.ponto_escala_carga_semanal(p_novo, v_desde);
  v_sem   := (v_carga->>'carga_semanal_min')::int;
  v_dias  := (v_carga->>'dias_trabalhados')::int;
  v_maior := (v_carga->>'maior_jornada_dia_min')::int;
  v_col   := public._ponto_ec141_coletivo(p_novo.tenant_id, p_novo.empresa_id, v_desde);

  IF p_antigo.id IS NULL THEN
    v_mudou := true;
  ELSE
    v_carga0 := public.ponto_escala_carga_semanal(p_antigo, v_desde);
    v_sem0   := (v_carga0->>'carga_semanal_min')::int;
    v_dias0  := (v_carga0->>'dias_trabalhados')::int;
    v_mudou  := v_sem IS DISTINCT FROM v_sem0 OR v_dias IS DISTINCT FROM v_dias0
             OR p_novo.dias_config IS DISTINCT FROM p_antigo.dias_config
             OR p_novo.compensacoes_mensais IS DISTINCT FROM p_antigo.compensacoes_mensais;
  END IF;

  IF v_sem IS NOT NULL AND v_sem > v_tsem THEN
    IF v_mudou THEN
      v_erros := v_erros || jsonb_build_array(jsonb_build_object(
        'codigo', 'acima_teto_semanal', 'base_legal', 'CF art. 7º, XIII (redação da EC 141/2026)',
        'mensagem', format('Não é possível salvar: a carga semanal fica em %s, acima do limite de %s por semana que vale a partir de %s (CF art. 7º, XIII, na redação da EC 141/2026). Reduza a jornada para até %s por semana. As batidas dos colaboradores continuam sendo registradas normalmente.',
                    public._ponto_ec141_horas(v_sem), public._ponto_ec141_horas(v_tsem),
                    to_char((v_teto->>'vigencia_inicio')::date, 'DD/MM/YYYY'), public._ponto_ec141_horas(v_tsem))));
    ELSE
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', 'acima_teto_semanal_existente', 'nivel', 'alerta',
        'mensagem', format('A escala segue com %s por semana, acima do limite de %s (CF art. 7º, XIII, na redação da EC 141/2026). Use o assistente "Migrar para 42h/40h" ou ajuste a jornada.',
                    public._ponto_ec141_horas(v_sem), public._ponto_ec141_horas(v_tsem))));
    END IF;
  END IF;

  IF v_dias IS NOT NULL AND 7 - v_dias < v_trep THEN
    IF NOT v_col AND v_mudou THEN
      v_erros := v_erros || jsonb_build_array(jsonb_build_object(
        'codigo', 'repousos_sem_coletivo', 'base_legal', 'CF art. 7º, XV e §2º (redação da EC 141/2026)',
        'mensagem', format('Não é possível salvar: a escala tem %s dia(s) de trabalho por semana e, a partir de %s, são obrigatórios %s repousos semanais (CF art. 7º, XV, na redação da EC 141/2026). Seis dias de trabalho só com convenção ou acordo coletivo vigente que preveja a média de repousos no mês (CF art. 7º, §2º). Cadastre o instrumento em Compliance > Acordos ou reduza para %s dias.',
                    v_dias, to_char((v_teto->>'vigencia_inicio')::date, 'DD/MM/YYYY'), v_trep, 7 - v_trep)));
    ELSIF v_col THEN
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', 'repousos_por_coletivo', 'nivel', 'info',
        'mensagem', format('%s dia(s) de trabalho por semana: há instrumento coletivo vigente; confira se ele prevê a média de %s repousos no mês (CF art. 7º, §2º, na redação da EC 141/2026).', v_dias, v_trep)));
    ELSE
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
        'codigo', 'repousos_insuficientes_existente', 'nivel', 'alerta',
        'mensagem', format('A escala segue com %s dia(s) de trabalho por semana sem instrumento coletivo vigente; a regra é %s repousos (CF art. 7º, XV, na redação da EC 141/2026).', v_dias, v_trep)));
    END IF;
  END IF;

  IF v_maior IS NOT NULL AND v_maior > (v_teto->>'teto_diario_min')::int THEN
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object(
      'codigo', CASE WHEN v_col THEN 'acima_8h_com_coletivo' ELSE 'acima_8h_sem_coletivo' END,
      'nivel', CASE WHEN v_col THEN 'info' ELSE 'forte' END,
      'mensagem', CASE WHEN v_col
        THEN format('Há dia com %s, acima de 8h: confira se o instrumento coletivo vigente autoriza essa jornada na transição (EC 141/2026, art. 7º).', public._ponto_ec141_horas(v_maior))
        ELSE format('Atenção: há dia com %s, acima de 8h, sem convenção ou acordo coletivo vigente. Na transição, jornada diária acima de 8 horas depende de negociação coletiva (EC 141/2026, art. 7º). Recomendado: 5 dias de 8h (40h).', public._ponto_ec141_horas(v_maior)) END));
  END IF;

  RETURN jsonb_build_object('aplica', true, 'bloqueia', jsonb_array_length(v_erros) > 0,
    'erros', v_erros, 'avisos', v_avisos, 'teto', v_teto, 'desde', v_desde,
    'carga_semanal_min', v_sem, 'dias_trabalhados', v_dias, 'maior_jornada_dia_min', v_maior,
    'coletivo_vigente', v_col);
END $fn$;

COMMENT ON FUNCTION public.ponto_escala_ec141_checar(public.ponto_escalas, public.ponto_escalas, date) IS
  'EC 141 F2a — confere a escala (como ficará) contra o teto EC 141 ATIVO e em vigor na data em que ela passa a valer. Bloqueia só carga semanal acima do teto e 6 dias sem coletivo (quando a gravação mexe na carga/dias); o resto é aviso. Nunca bloqueia a batida.';

-- Para a tela: confere antes de salvar (mesma regra do gatilho).
CREATE OR REPLACE FUNCTION public.ponto_escala_ec141_validar_salvar(
  p_escala_id uuid, p_dados jsonb, p_desde date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_antigo public.ponto_escalas;
  v_novo   public.ponto_escalas;
  v_tenant uuid;
BEGIN
  IF p_escala_id IS NOT NULL THEN
    v_antigo := (SELECT e FROM public.ponto_escalas e WHERE e.id = p_escala_id);
    IF v_antigo.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'escala_nao_encontrada');
    END IF;
    v_tenant := v_antigo.tenant_id;
    v_novo := jsonb_populate_record(v_antigo, COALESCE(p_dados, '{}'::jsonb) - 'id' - 'tenant_id');
  ELSE
    v_tenant := COALESCE(NULLIF(p_dados->>'tenant_id', '')::uuid, public.get_user_tenant_id());
    v_novo := jsonb_populate_record(NULL::public.ponto_escalas,
                COALESCE(p_dados, '{}'::jsonb) || jsonb_build_object('tenant_id', v_tenant));
  END IF;
  IF NOT public._ponto_ec141_pode_tenant(v_tenant) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF NOT public._ponto_ec141_tem_marco_ativo(v_tenant) THEN
    RETURN jsonb_build_object('ok', true, 'aplica', false, 'bloqueia', false, 'erros', '[]'::jsonb, 'avisos', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('ok', true) || public.ponto_escala_ec141_checar(v_novo, v_antigo, p_desde);
END $fn$;

-- Gatilho: roda DEPOIS do gatilho de versão da F1 (ordem alfabética:
-- trg_ponto_escala_arquiva_versao < trg_ponto_escala_zz_ec141_valida), então
-- já enxerga a data final de vigência gravada por ele.
CREATE OR REPLACE FUNCTION public.ponto_escala_ec141_valida_salvar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  v_res jsonb;
BEGIN
  -- Restauração do cancelamento (F1): sempre passa.
  IF COALESCE(current_setting('ponto.ec141_restaurando', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NOT (
        NEW.jornada_diaria_minutos         IS DISTINCT FROM OLD.jornada_diaria_minutos
     OR NEW.tolerancia_minutos             IS DISTINCT FROM OLD.tolerancia_minutos
     OR NEW.tolerancia_diaria_minutos      IS DISTINCT FROM OLD.tolerancia_diaria_minutos
     OR NEW.hora_entrada_padrao            IS DISTINCT FROM OLD.hora_entrada_padrao
     OR NEW.hora_saida_padrao              IS DISTINCT FROM OLD.hora_saida_padrao
     OR NEW.intervalo_intrajornada_minutos IS DISTINCT FROM OLD.intervalo_intrajornada_minutos
     OR NEW.dias_config                    IS DISTINCT FROM OLD.dias_config
     OR NEW.compensacoes_mensais           IS DISTINCT FROM OLD.compensacoes_mensais
     OR NEW.carga_semanal_contratada_min   IS DISTINCT FROM OLD.carga_semanal_contratada_min
     OR NEW.equalizacao_mensal_ativa       IS DISTINCT FROM OLD.equalizacao_mensal_ativa
     OR NEW.tipo                           IS DISTINCT FROM OLD.tipo
     OR NEW.jornada_semanal_minutos        IS DISTINCT FROM OLD.jornada_semanal_minutos
     OR NEW.modalidade                     IS DISTINCT FROM OLD.modalidade) THEN
    RETURN NEW;
  END IF;
  -- Marcos inativos: comportamento idêntico ao de antes desta entrega.
  IF NOT public._ponto_ec141_tem_marco_ativo(NEW.tenant_id) THEN
    RETURN NEW;
  END IF;
  v_res := public.ponto_escala_ec141_checar(NEW, CASE WHEN TG_OP = 'UPDATE' THEN OLD END,
                                            NEW.parametros_vigentes_desde);
  IF COALESCE((v_res->>'bloqueia')::boolean, false) THEN
    RAISE EXCEPTION '%', (SELECT string_agg(x->>'mensagem', ' ') FROM jsonb_array_elements(v_res->'erros') x)
      USING ERRCODE = 'P0001', HINT = 'ec141_bloqueio';
  END IF;
  RETURN NEW;
END $fn$;

DO $trg_f2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'trg_ponto_escala_zz_ec141_valida'
                    AND t.tgrelid = 'public.ponto_escalas'::regclass AND NOT t.tgisinternal) THEN
    EXECUTE 'CREATE TRIGGER trg_ponto_escala_zz_ec141_valida BEFORE INSERT OR UPDATE ON public.ponto_escalas '
         || 'FOR EACH ROW EXECUTE FUNCTION public.ponto_escala_ec141_valida_salvar()';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Gatilho de validacao EC 141 nao criado: %', SQLERRM;
END $trg_f2$;

-- ---------------------------------------------------------------------
-- 2) ASSISTENTE "MIGRAR PARA 42h/40h"
-- ---------------------------------------------------------------------
-- Descrição legível da jornada ("Seg, Ter, Qua, Qui e Sex: 08:00 às 12:00 e
-- 13:00 às 17:24"), agrupando dias com o mesmo horário.
CREATE OR REPLACE FUNCTION public._ponto_ec141_descrever_jornada(p_dc jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_dias text[] := ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'];
  v_lbl  text[] := ARRAY['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'];
  v_hor  text[] := ARRAY[]::text[];
  v_grp  text[] := ARRAY[]::text[];
  v_gdia text[] := ARRAY[]::text[];
  c jsonb;
  h text;
  i int;
  j int;
  v_out text := '';
  v_n int;
BEGIN
  IF p_dc IS NULL OR jsonb_typeof(p_dc) <> 'object' THEN
    RETURN 'jornada conforme a escala cadastrada';
  END IF;
  FOR i IN 1..7 LOOP
    c := p_dc -> v_dias[i];
    IF c IS NULL OR NOT COALESCE((c->>'trabalha')::boolean, false) THEN
      CONTINUE;
    END IF;
    IF COALESCE((c->>'tem_almoco')::boolean, false) AND NULLIF(c->>'inicio_almoco', '') IS NOT NULL
       AND NULLIF(c->>'fim_almoco', '') IS NOT NULL THEN
      h := format('%s às %s e %s às %s', left(c->>'entrada', 5), left(c->>'inicio_almoco', 5),
                  left(c->>'fim_almoco', 5), left(c->>'saida', 5));
    ELSE
      h := format('%s às %s', left(c->>'entrada', 5), left(c->>'saida', 5));
    END IF;
    j := array_position(v_grp, h);
    IF j IS NULL THEN
      v_grp := v_grp || h;
      v_gdia := v_gdia || v_lbl[i];
    ELSE
      v_gdia[j] := v_gdia[j] || ',' || v_lbl[i];
    END IF;
  END LOOP;
  IF cardinality(v_grp) = 0 THEN
    RETURN 'sem dias de trabalho';
  END IF;
  FOR j IN 1..cardinality(v_grp) LOOP
    v_hor := string_to_array(v_gdia[j], ',');
    v_n := cardinality(v_hor);
    v_out := v_out || CASE WHEN v_out = '' THEN '' ELSE '; ' END
          || CASE WHEN v_n = 1 THEN v_hor[1]
                  ELSE array_to_string(v_hor[1:v_n - 1], ', ') || ' e ' || v_hor[v_n] END
          || ': ' || v_grp[j];
  END LOOP;
  RETURN v_out;
END $fn$;

-- Proposta para uma escala e um destino (minutos semanais):
--   · 6 ou 7 dias de trabalho: sai o domingo, depois o sábado, até 5 dias
--     (2 repousos — CF art. 7º, XV, red. EC 141);
--   · a carga alvo (o menor entre o destino e a carga atual sem as
--     compensações) é dividida igualmente entre os dias que ficam;
--   · cada dia mantém entrada e almoço; muda só a saída.
-- Devolve {status: migrar | ja_conforme | fora_do_assistente, escala (campos novos), ...}.
CREATE OR REPLACE FUNCTION public._ponto_ec141_proposta(
  p_esc public.ponto_escalas, p_destino_min integer, p_data date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ordem   text[] := ARRAY['segunda','terca','quarta','quinta','sexta','sabado','domingo'];
  v_lbl     jsonb := '{"segunda":"segunda","terca":"terça","quarta":"quarta","quinta":"quinta","sexta":"sexta","sabado":"sábado","domingo":"domingo"}'::jsonb;
  v_carga   jsonb;
  v_sem     int;
  v_base    int;
  v_dias    int;
  v_trab    text[] := ARRAY[]::text[];
  v_sai     text[] := ARRAY[]::text[];
  v_alvo    int;
  v_por     int;
  v_resto   int;
  v_dc      jsonb;
  c         jsonb;
  k         text;
  i         int;
  v_ent     int;
  v_alm     int;
  v_min     int;
  v_novo    public.ponto_escalas;
  v_carga2  jsonb;
  v_avisos  jsonb := '[]'::jsonb;
  v_tipo    text;
  v_prim    jsonb;
BEGIN
  IF COALESCE(p_esc.tipo, '') = '12x36' OR COALESCE(p_esc.modalidade, '') IN ('movel', 'revezamento')
     OR p_esc.dias_config IS NULL OR jsonb_typeof(p_esc.dias_config) <> 'object' THEN
    RETURN jsonb_build_object('status', 'fora_do_assistente',
      'avisos', jsonb_build_array(jsonb_build_object('nivel', 'alerta', 'codigo', 'regime_proprio',
        'mensagem', 'Escala de ciclo, móvel ou de revezamento: tem regime próprio (CLT art. 59-A; CF art. 7º, XIV). Ajuste manualmente na edição da escala.')));
  END IF;

  v_carga := public.ponto_escala_carga_semanal(p_esc, p_data);
  v_sem   := (v_carga->>'carga_semanal_min')::int;
  v_base  := COALESCE((v_carga->>'carga_base_min')::int, v_sem);
  v_dias  := (v_carga->>'dias_trabalhados')::int;

  FOREACH k IN ARRAY v_ordem LOOP
    c := p_esc.dias_config -> k;
    IF c IS NOT NULL AND COALESCE((c->>'trabalha')::boolean, false)
       AND NULLIF(c->>'entrada', '') IS NOT NULL AND NULLIF(c->>'saida', '') IS NOT NULL THEN
      v_trab := v_trab || k;
    END IF;
  END LOOP;

  IF COALESCE(v_sem, 0) <= p_destino_min AND cardinality(v_trab) <= 5 THEN
    RETURN jsonb_build_object('status', 'ja_conforme', 'carga_antes_min', v_sem, 'carga_depois_min', v_sem,
      'dias_antes', v_dias, 'dias_depois', v_dias, 'avisos', '[]'::jsonb,
      'jornada_atual', public._ponto_ec141_descrever_jornada(p_esc.dias_config),
      'jornada_nova', public._ponto_ec141_descrever_jornada(p_esc.dias_config));
  END IF;
  IF cardinality(v_trab) = 0 THEN
    RETURN jsonb_build_object('status', 'fora_do_assistente', 'avisos', jsonb_build_array(jsonb_build_object(
      'nivel', 'alerta', 'codigo', 'sem_dias', 'mensagem', 'A escala não tem dias de trabalho com horário: ajuste manualmente.')));
  END IF;

  -- Até 5 dias: sai o domingo, depois o sábado, depois os últimos.
  WHILE cardinality(v_trab) > 5 LOOP
    IF 'domingo' = ANY (v_trab) THEN
      v_trab := array_remove(v_trab, 'domingo'); v_sai := array_append(v_sai, 'domingo'::text);
    ELSIF 'sabado' = ANY (v_trab) THEN
      v_trab := array_remove(v_trab, 'sabado'); v_sai := array_append(v_sai, 'sabado'::text);
    ELSE
      v_sai := v_sai || v_trab[cardinality(v_trab)];
      v_trab := v_trab[1:cardinality(v_trab) - 1];
    END IF;
  END LOOP;

  v_alvo  := LEAST(p_destino_min, v_base);
  v_por   := v_alvo / cardinality(v_trab);
  v_resto := v_alvo - v_por * cardinality(v_trab);
  v_dc    := p_esc.dias_config;

  FOREACH k IN ARRAY v_sai LOOP
    v_dc := jsonb_set(v_dc, ARRAY[k], (v_dc -> k) || jsonb_build_object('trabalha', false));
  END LOOP;
  FOR i IN 1..cardinality(v_trab) LOOP
    k := v_trab[i];
    c := v_dc -> k;
    v_min := v_por + CASE WHEN i <= v_resto THEN 1 ELSE 0 END;
    v_ent := (EXTRACT(EPOCH FROM (c->>'entrada')::time)::int / 60);
    IF COALESCE((c->>'tem_almoco')::boolean, false) AND NULLIF(c->>'inicio_almoco', '') IS NOT NULL
       AND NULLIF(c->>'fim_almoco', '') IS NOT NULL THEN
      v_alm := (EXTRACT(EPOCH FROM ((c->>'fim_almoco')::time - (c->>'inicio_almoco')::time))::int / 60);
    ELSE
      v_alm := COALESCE(NULLIF(c->>'intervalo', '')::int, 0);
    END IF;
    IF v_ent + v_alm + v_min >= 1440 THEN
      RETURN jsonb_build_object('status', 'fora_do_assistente', 'avisos', jsonb_build_array(jsonb_build_object(
        'nivel', 'alerta', 'codigo', 'vira_o_dia', 'mensagem', 'A jornada atravessa a meia-noite: ajuste manualmente na edição da escala.')));
    END IF;
    v_dc := jsonb_set(v_dc, ARRAY[k], c || jsonb_build_object(
      'saida', to_char(make_time(0, 0, 0) + make_interval(mins => v_ent + v_alm + v_min), 'HH24:MI')));
  END LOOP;

  -- Tipo, como a tela deriva.
  v_tipo := CASE
    WHEN cardinality(v_trab) = 5 AND 'segunda' = ANY (v_trab) AND NOT ('sabado' = ANY (v_trab)) AND NOT ('domingo' = ANY (v_trab)) THEN '5x2'
    WHEN cardinality(v_trab) = 6 AND 'segunda' = ANY (v_trab) AND 'sabado' = ANY (v_trab) AND NOT ('domingo' = ANY (v_trab)) THEN '6x1'
    ELSE 'personalizada' END;
  v_prim := v_dc -> v_trab[1];

  v_novo := p_esc;
  v_novo.dias_config := v_dc;
  v_novo.compensacoes_mensais := '[]'::jsonb;
  v_carga2 := public.ponto_escala_carga_semanal(v_novo, p_data);

  IF cardinality(v_sai) > 0 THEN
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'info', 'codigo', 'dia_sai',
      'mensagem', format('%s %s de ser dia de trabalho: 2 repousos semanais (CF art. 7º, XV, na redação da EC 141/2026).',
                  initcap((SELECT string_agg(v_lbl->>x, ' e ') FROM unnest(v_sai) x)),
                  CASE WHEN cardinality(v_sai) = 1 THEN 'deixa' ELSE 'deixam' END)));
  END IF;
  IF p_esc.compensacoes_mensais IS NOT NULL AND jsonb_typeof(p_esc.compensacoes_mensais) = 'array'
     AND jsonb_array_length(p_esc.compensacoes_mensais) > 0 THEN
    v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'alerta', 'codigo', 'compensacoes',
      'mensagem', 'As compensações mensais desta escala não entram na nova jornada: revise-as depois, se ainda fizerem sentido.'));
  END IF;

  RETURN jsonb_build_object(
    'status', 'migrar',
    'carga_antes_min', v_sem,
    'carga_depois_min', (v_carga2->>'carga_semanal_min')::int,
    'dias_antes', v_dias,
    'dias_depois', (v_carga2->>'dias_trabalhados')::int,
    'maior_dia_depois_min', (v_carga2->>'maior_jornada_dia_min')::int,
    'jornada_atual', public._ponto_ec141_descrever_jornada(p_esc.dias_config),
    'jornada_nova', public._ponto_ec141_descrever_jornada(v_dc),
    'avisos', v_avisos,
    'escala', jsonb_build_object(
      'dias_config', v_dc,
      'compensacoes_mensais', '[]'::jsonb,
      'jornada_diaria_minutos', (v_carga2->>'maior_jornada_dia_min')::int,
      'jornada_semanal_minutos', (v_carga2->>'carga_semanal_min')::int,
      'carga_semanal_contratada_min', LEAST(COALESCE(p_esc.carga_semanal_contratada_min, p_destino_min), p_destino_min),
      'tipo', v_tipo,
      'hora_entrada_padrao', left(v_prim->>'entrada', 5),
      'hora_saida_padrao', left(v_prim->>'saida', 5),
      'sabado_util', 'sabado' = ANY (v_trab),
      'domingo_util', 'domingo' = ANY (v_trab)));
END $fn$;

-- Colaboradores com escala na data (uma atribuição por colaborador: a de
-- início mais recente que cobre a data), com a admissão e a empresa.
CREATE OR REPLACE FUNCTION public._ponto_ec141_colaboradores(
  p_tenant uuid, p_empresa uuid, p_data date, p_escala_ids uuid[] DEFAULT NULL)
RETURNS TABLE(chave text, colaborador_id text, colaborador_cpf text, colaborador_nome text,
              admissao_id uuid, empresa_id uuid, escala_id uuid, atribuicao_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  WITH atr AS MATERIALIZED (
    SELECT DISTINCT ON (COALESCE(NULLIF(regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''), a.colaborador_id))
           COALESCE(NULLIF(regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''), a.colaborador_id) AS chave,
           a.colaborador_id, regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
           a.colaborador_nome, a.escala_id, a.id AS atribuicao_id, e.empresa_id AS esc_empresa
      FROM public.ponto_escala_atribuicoes a
      JOIN public.ponto_escalas e ON e.id = a.escala_id
     WHERE a.tenant_id = p_tenant
       AND COALESCE(a.ativa, true)
       AND a.data_inicio <= p_data
       AND (a.data_fim IS NULL OR a.data_fim >= p_data)
     ORDER BY COALESCE(NULLIF(regexp_replace(COALESCE(a.colaborador_cpf, ''), '[^0-9]', '', 'g'), ''), a.colaborador_id),
              a.data_inicio DESC, a.created_at DESC
  ),
  com_adm AS (
    SELECT t.*,
           (SELECT ad.id FROM public.admissoes ad
             WHERE ad.tenant_id = p_tenant
               AND (ad.id::text = t.colaborador_id
                    OR (t.cpf <> '' AND regexp_replace(COALESCE(ad.cpf, ''), '[^0-9]', '', 'g') = t.cpf))
             ORDER BY (ad.status::text = 'concluido') DESC, ad.created_at DESC
             LIMIT 1) AS adm
      FROM atr t
  )
  SELECT c.chave, c.colaborador_id, NULLIF(c.cpf, ''), c.colaborador_nome, c.adm,
         COALESCE((SELECT ad.empresa_id FROM public.admissoes ad WHERE ad.id = c.adm), c.esc_empresa),
         c.escala_id, c.atribuicao_id
    FROM com_adm c
   WHERE (p_escala_ids IS NULL OR c.escala_id = ANY (p_escala_ids))
     AND (p_empresa IS NULL
          OR COALESCE((SELECT ad.empresa_id FROM public.admissoes ad WHERE ad.id = c.adm), c.esc_empresa) = p_empresa)
$fn$;

-- Instrumento coletivo do colaborador na data (Parte 1 quando há admissão;
-- senão o da conta/empresa da escala).
CREATE OR REPLACE FUNCTION public._ponto_ec141_coletivo_colaborador(
  p_tenant uuid, p_admissao uuid, p_empresa uuid, p_data date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v jsonb;
BEGIN
  IF p_admissao IS NOT NULL AND to_regprocedure('public.ponto_instrumento_do_colaborador(uuid,uuid,date)') IS NOT NULL THEN
    v := public.ponto_instrumento_do_colaborador(p_tenant, p_admissao, p_data);
    RETURN jsonb_build_object('tem', (v->>'instrumento_id') IS NOT NULL, 'nome', v->>'nome', 'origem', v->>'origem');
  END IF;
  RETURN jsonb_build_object('tem', public._ponto_ec141_coletivo(p_tenant, p_empresa, p_data), 'nome', NULL, 'origem', 'conta');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('tem', public._ponto_ec141_coletivo(p_tenant, p_empresa, p_data), 'nome', NULL, 'origem', 'conta');
END $fn$;

-- Marco alvo do assistente + destinos permitidos.
CREATE OR REPLACE FUNCTION public._ponto_ec141_destino_min(p_destino text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT CASE p_destino WHEN '42' THEN 2520 WHEN '40' THEN 2400 END
$fn$;

-- Item "modo escala" cujo agendamento foi cancelado por fora do assistente
-- (botão de cancelar da escala ou o lote da F1): deixa de contar como migrado.
CREATE OR REPLACE FUNCTION public._ponto_ec141_item_vivo(p_modo text, p_escala uuid, p_marco text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT p_modo <> 'escala'
      OR EXISTS (SELECT 1 FROM public.ponto_escala_param_versoes pv
                  WHERE pv.escala_id = p_escala AND pv.marco_codigo = p_marco)
$fn$;

-- Fecha os itens órfãos (e os aditivos deles) antes de gravar ou cancelar.
CREATE OR REPLACE FUNCTION public._ponto_ec141_fechar_orfaos(p_tenant uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_n int;
BEGIN
  WITH orf AS MATERIALIZED (
    SELECT i.id FROM public.ponto_ec141_migracao_itens i
     WHERE i.tenant_id = p_tenant AND i.status = 'ativo'
       AND NOT public._ponto_ec141_item_vivo(i.modo, i.escala_origem_id, i.marco_codigo)
  ), ad AS (
    UPDATE public.ponto_ec141_aditivos a SET status = 'cancelado', atualizado_em = now()
      FROM orf WHERE a.item_id = orf.id AND a.status <> 'cancelado' AND a.solicitacao_id IS NULL
    RETURNING a.id
  )
  UPDATE public.ponto_ec141_migracao_itens i SET status = 'cancelado'
    FROM orf WHERE i.id = orf.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $fn$;

-- Prévia por colaborador (somente leitura). p_excecoes = {chave: '42'|'40'|'manter'}.
CREATE OR REPLACE FUNCTION public.ponto_ec141_migracao_previa(
  p_tenant uuid, p_empresa uuid, p_destino text,
  p_excecoes jsonb DEFAULT '{}'::jsonb, p_escala_ids uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_marco  jsonb;
  v_d      date;
  v_teto   int;
  v_linhas jsonb := '[]'::jsonb;
  r        record;
  v_esc    public.ponto_escalas;
  v_dest   text;
  v_prop   jsonb;
  v_col    jsonb;
  v_status text;
  v_avisos jsonb;
  v_pend   jsonb;
  v_rec    text;
  v_conf   boolean;
  v_exc    jsonb := COALESCE(p_excecoes, '{}'::jsonb);
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  v_marco := public.ponto_ec141_marco_alvo(p_tenant);
  IF v_marco IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'visivel', false,
      'mensagem', 'Nenhum marco da EC 141 ativo para esta conta: o assistente só aparece depois que a lei for ativada.');
  END IF;
  v_d := (v_marco->>'vigencia_inicio')::date;
  v_teto := (v_marco->>'teto_semanal_min')::int;
  IF public._ponto_ec141_destino_min(p_destino) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'destino_invalido', 'mensagem', 'Escolha 42h ou 40h.');
  END IF;

  FOR r IN SELECT * FROM public._ponto_ec141_colaboradores(p_tenant, p_empresa, v_d, p_escala_ids) c
            ORDER BY c.colaborador_nome, c.chave LOOP
    v_esc  := (SELECT e FROM public.ponto_escalas e WHERE e.id = r.escala_id);
    v_dest := COALESCE(NULLIF(v_exc->>r.chave, ''), p_destino);
    v_col  := public._ponto_ec141_coletivo_colaborador(p_tenant, r.admissao_id, r.empresa_id, v_d);
    v_rec  := CASE WHEN COALESCE((v_col->>'tem')::boolean, false) THEN p_destino ELSE '40' END;
    v_avisos := '[]'::jsonb;
    v_prop := NULL;
    v_conf := false;
    v_pend := (SELECT jsonb_build_object('data', pv.vigencia_fim + 1, 'marco', pv.marco_codigo)
                 FROM public.ponto_escala_param_versoes pv
                WHERE pv.escala_id = r.escala_id AND pv.vigencia_fim >= CURRENT_DATE
                ORDER BY pv.vigencia_fim DESC LIMIT 1);

    IF v_dest = 'manter' THEN
      v_status := 'nao_migrar';
    ELSIF public._ponto_ec141_destino_min(v_dest) IS NULL THEN
      v_status := 'nao_migrar';
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'alerta', 'codigo', 'destino_invalido',
        'mensagem', 'Destino inválido para este colaborador.'));
    ELSIF EXISTS (SELECT 1 FROM public.ponto_ec141_migracao_itens i
                   WHERE i.tenant_id = p_tenant AND i.marco_codigo = v_marco->>'codigo'
                     AND i.colaborador_chave = r.chave AND i.status = 'ativo'
                     AND public._ponto_ec141_item_vivo(i.modo, i.escala_origem_id, i.marco_codigo)) THEN
      v_status := 'ja_migrado';
    ELSIF v_pend IS NOT NULL AND v_pend->>'marco' IS NOT DISTINCT FROM v_marco->>'codigo' THEN
      v_status := 'ja_migrado';
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'info', 'codigo', 'agendada_manual',
        'mensagem', format('A escala já tem a alteração para a lei agendada para %s.', to_char((v_pend->>'data')::date, 'DD/MM/YYYY'))));
    ELSIF v_pend IS NOT NULL THEN
      v_status := 'conflito';
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'alerta', 'codigo', 'agendamento_existente',
        'mensagem', format('A escala já tem outra alteração agendada para %s. Cancele-a na lista de escalas antes de migrar.', to_char((v_pend->>'data')::date, 'DD/MM/YYYY'))));
    ELSIF public._ponto_ec141_destino_min(v_dest) > v_teto THEN
      v_status := 'nao_migrar';
      v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'alerta', 'codigo', 'destino_acima_teto',
        'mensagem', format('O limite ativo é %s: o destino %sh não é permitido.', public._ponto_ec141_horas(v_teto), v_dest)));
    ELSE
      v_prop := public._ponto_ec141_proposta(v_esc, public._ponto_ec141_destino_min(v_dest), v_d);
      v_status := v_prop->>'status';
      v_avisos := v_avisos || COALESCE(v_prop->'avisos', '[]'::jsonb);
      IF v_status = 'migrar' AND COALESCE((v_prop->>'maior_dia_depois_min')::int, 0) > 480 THEN
        IF COALESCE((v_col->>'tem')::boolean, false) THEN
          v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'info', 'codigo', 'acima_8h_com_coletivo',
            'mensagem', format('Jornada de %s por dia: confira se o instrumento coletivo%s autoriza essa jornada na transição (EC 141/2026, art. 7º).',
                        public._ponto_ec141_horas((v_prop->>'maior_dia_depois_min')::int),
                        COALESCE(' (' || (v_col->>'nome') || ')', ''))));
        ELSE
          v_conf := true;
          v_avisos := v_avisos || jsonb_build_array(jsonb_build_object('nivel', 'forte', 'codigo', 'acima_8h_sem_coletivo',
            'mensagem', format('Atenção: jornada de %s por dia sem convenção ou acordo coletivo vigente para este colaborador. Na transição, jornada diária acima de 8 horas depende de negociação coletiva (EC 141/2026, art. 7º). Recomendado: 40h (5 dias de 8h). Só é gravado com a sua confirmação.',
                        public._ponto_ec141_horas((v_prop->>'maior_dia_depois_min')::int))));
        END IF;
      END IF;
    END IF;

    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
      'chave', r.chave, 'colaborador_id', r.colaborador_id, 'colaborador_nome', r.colaborador_nome,
      'colaborador_cpf', r.colaborador_cpf, 'admissao_id', r.admissao_id, 'empresa_id', r.empresa_id,
      'atribuicao_id', r.atribuicao_id,
      'escala_id', r.escala_id, 'escala_nome', v_esc.nome, 'escala_tipo', v_esc.tipo,
      'destino', v_dest, 'recomendacao', v_rec,
      'tem_coletivo', COALESCE((v_col->>'tem')::boolean, false), 'instrumento_nome', v_col->>'nome',
      'status', v_status,
      'requer_confirmacao_8h24', v_conf,
      'jornada_atual', COALESCE(v_prop->>'jornada_atual', public._ponto_ec141_descrever_jornada(v_esc.dias_config)),
      'jornada_nova', v_prop->>'jornada_nova',
      'carga_antes_min', COALESCE((v_prop->>'carga_antes_min')::int,
                                  (public.ponto_escala_carga_semanal(v_esc, v_d)->>'carga_semanal_min')::int),
      'carga_depois_min', (v_prop->>'carga_depois_min')::int,
      'maior_dia_depois_min', (v_prop->>'maior_dia_depois_min')::int,
      'proposta', v_prop->'escala',
      'avisos', v_avisos));
  END LOOP;

  v_linhas := public._ponto_ec141_definir_modos(p_tenant, v_d, v_linhas);

  RETURN jsonb_build_object(
    'ok', true, 'visivel', true, 'marco', v_marco, 'vigencia_inicio', v_d,
    'pode_aplicar', v_d > CURRENT_DATE,
    'mensagem', CASE WHEN v_d <= CURRENT_DATE THEN
      'A data da lei já chegou: a migração só pode ser gravada antes da data (alteração retroativa ainda não está disponível).' END,
    'destino_padrao', p_destino,
    'linhas', v_linhas,
    'totais', jsonb_build_object(
      'colaboradores', jsonb_array_length(v_linhas),
      'migrar', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->>'status' = 'migrar'),
      'requer_confirmacao', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->>'status' = 'migrar' AND (x->>'requer_confirmacao_8h24')::boolean),
      'ja_conforme', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->>'status' = 'ja_conforme'),
      'ja_migrado', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->>'status' = 'ja_migrado'),
      'fora_do_assistente', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE x->>'status' IN ('fora_do_assistente', 'conflito')),
      'sem_coletivo', (SELECT count(*) FROM jsonb_array_elements(v_linhas) x WHERE NOT (x->>'tem_coletivo')::boolean)));
END $fn$;

-- Define o modo de gravação de cada linha "migrar":
--   'escala'      todos os colaboradores da escala na data vão para o mesmo
--                 destino -> agenda a própria escala (mecanismo da F1);
--   'nova_escala' destinos diferentes (ou parte fica) -> escala nova para o
--                 grupo, a partir da data.
CREATE OR REPLACE FUNCTION public._ponto_ec141_definir_modos(p_tenant uuid, p_data date, p_linhas jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  WITH l AS MATERIALIZED (
    SELECT x, ord FROM jsonb_array_elements(COALESCE(p_linhas, '[]'::jsonb)) WITH ORDINALITY AS t(x, ord)
  ),
  grp AS MATERIALIZED (
    SELECT (x->>'escala_id')::uuid AS escala_id,
           count(DISTINCT x->>'destino') AS destinos,
           count(*) AS n
      FROM l WHERE x->>'status' = 'migrar'
     GROUP BY 1
  ),
  tot AS MATERIALIZED (
    SELECT g.escala_id,
           (SELECT count(*) FROM public._ponto_ec141_colaboradores(p_tenant, NULL, p_data, ARRAY[g.escala_id])) AS total
      FROM grp g
  )
  SELECT COALESCE(jsonb_agg(
           CASE WHEN l.x->>'status' <> 'migrar' THEN l.x
                ELSE l.x || jsonb_build_object('modo',
                       CASE WHEN g.destinos = 1 AND g.n = t.total THEN 'escala' ELSE 'nova_escala' END)
           END ORDER BY l.ord), '[]'::jsonb)
    FROM l
    LEFT JOIN grp g ON g.escala_id = (l.x->>'escala_id')::uuid
    LEFT JOIN tot t ON t.escala_id = g.escala_id
$fn$;

-- ---------------------------------------------------------------------
-- 3) ADITIVO INDIVIDUAL (modelo com variáveis)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ec141_aditivo_modelo()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  SELECT jsonb_build_object(
    'versao', 'ec141-aditivo-v1-2026-10-31',
    'titulo', 'TERMO ADITIVO AO CONTRATO DE TRABALHO — ALTERAÇÃO DE HORÁRIO (EC 141/2026)',
    'texto',
       'EMPREGADOR: {{empresa_nome}}, CNPJ {{empresa_cnpj}}.' || E'\n'
    || 'EMPREGADO(A): {{colaborador_nome}}, CPF {{colaborador_cpf}}.' || E'\n\n'
    || 'Cláusula 1ª — Em cumprimento à Emenda Constitucional nº 141/2026, que reduz a duração normal do trabalho para {{teto_semanal}} semanais, a jornada do(a) EMPREGADO(A) passa a ser, a partir de {{vigencia_inicio}}:' || E'\n'
    || '  Antes: {{jornada_anterior}} ({{carga_anterior}} por semana).' || E'\n'
    || '  A partir de {{vigencia_inicio}}: {{jornada_nova}} ({{carga_nova}} por semana).' || E'\n\n'
    || 'Cláusula 2ª — A redução da jornada não acarreta redução do salário: fica mantido o salário mensal atualmente pago (EC 141/2026, art. 2º; CLT, art. 468).' || E'\n\n'
    || 'Cláusula 3ª — Os dias anteriores a {{vigencia_inicio}} não são alterados por este aditivo.' || E'\n\n'
    || 'Cláusula 4ª — {{clausula_jornada_diaria}}' || E'\n\n'
    || 'Cláusula 5ª — Permanecem inalteradas as demais cláusulas do contrato de trabalho.',
    'variaveis', jsonb_build_array('empresa_nome', 'empresa_cnpj', 'colaborador_nome', 'colaborador_cpf',
                                   'teto_semanal', 'vigencia_inicio', 'jornada_anterior', 'carga_anterior',
                                   'jornada_nova', 'carga_nova', 'clausula_jornada_diaria'))
$fn$;

COMMENT ON FUNCTION public.ponto_ec141_aditivo_modelo() IS
  'EC 141 F2a — modelo do aditivo individual de alteração de horário. Sem dado pessoal fixo: só variáveis {{...}}. Cita EC 141/2026 art. 2º e CLT art. 468 (sem redução salarial). A redação deve passar pela revisão jurídica.';

CREATE OR REPLACE FUNCTION public._ponto_ec141_aditivo_render(p_vars jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_txt text := public.ponto_ec141_aditivo_modelo()->>'texto';
  r record;
BEGIN
  FOR r IN SELECT * FROM jsonb_each_text(COALESCE(p_vars, '{}'::jsonb)) LOOP
    v_txt := replace(v_txt, '{{' || r.key || '}}', COALESCE(r.value, ''));
  END LOOP;
  RETURN v_txt;
END $fn$;

-- ---------------------------------------------------------------------
-- 2b) APLICAR
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ec141_migracao_aplicar(
  p_tenant uuid, p_empresa uuid, p_destino text,
  p_excecoes jsonb DEFAULT '{}'::jsonb, p_confirmar_8h24 boolean DEFAULT false,
  p_escala_ids uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_prev    jsonb;
  v_marco   text;
  v_d       date;
  v_linhas  jsonb;
  v_mig     uuid;
  v_uid     uuid := auth.uid();
  v_email   text;
  g         record;
  l         jsonb;
  v_esc     public.ponto_escalas;
  v_nova    uuid;
  v_row     public.ponto_escalas;
  v_atr     public.ponto_escala_atribuicoes;
  v_atr_n   uuid;
  v_item    uuid;
  v_emp     public.empresa_cadastro;
  v_vars    jsonb;
  v_n       int := 0;
  v_n_esc   int := 0;
  v_n_nova  int := 0;
  v_pulados int := 0;
  v_adit    int := 0;
BEGIN
  v_prev := public.ponto_ec141_migracao_previa(p_tenant, p_empresa, p_destino, p_excecoes, p_escala_ids);
  IF NOT COALESCE((v_prev->>'ok')::boolean, false) THEN
    RETURN v_prev;
  END IF;
  IF NOT COALESCE((v_prev->>'visivel')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_marco_ativo', 'mensagem', v_prev->>'mensagem');
  END IF;
  IF NOT COALESCE((v_prev->>'pode_aplicar')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'data_ja_chegou', 'mensagem', v_prev->>'mensagem');
  END IF;
  v_marco := v_prev->'marco'->>'codigo';
  v_d     := (v_prev->>'vigencia_inicio')::date;

  -- Só o que será gravado: "migrar" e, se 8h24 sem coletivo, com confirmação.
  v_linhas := (SELECT COALESCE(jsonb_agg(x - 'modo'), '[]'::jsonb) FROM jsonb_array_elements(v_prev->'linhas') x
                WHERE x->>'status' = 'migrar'
                  AND (NOT (x->>'requer_confirmacao_8h24')::boolean OR COALESCE(p_confirmar_8h24, false)));
  v_pulados := (SELECT count(*) FROM jsonb_array_elements(v_prev->'linhas') x
                 WHERE x->>'status' = 'migrar' AND (x->>'requer_confirmacao_8h24')::boolean
                   AND NOT COALESCE(p_confirmar_8h24, false));
  IF jsonb_array_length(v_linhas) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'migracao_id', NULL, 'migrados', 0, 'aguardando_confirmacao', v_pulados,
      'mensagem', CASE WHEN v_pulados > 0 THEN 'Nada gravado: os colaboradores restantes precisam da confirmação da jornada de 8h24.'
                       ELSE 'Nada a migrar: todos já estão migrados, dentro do limite ou fora do assistente.' END);
  END IF;
  v_linhas := public._ponto_ec141_definir_modos(p_tenant, v_d, v_linhas);

  BEGIN
    PERFORM public._ponto_ec141_fechar_orfaos(p_tenant);
    v_email := (SELECT u.email::text FROM auth.users u WHERE u.id = v_uid);
    v_mig := gen_random_uuid();
    INSERT INTO public.ponto_ec141_migracoes
      (id, tenant_id, empresa_id, marco_codigo, vigencia_inicio, destino_padrao, excecoes, confirmou_8h24,
       acionado_por, acionado_por_email)
    VALUES (v_mig, p_tenant, p_empresa, v_marco, v_d, p_destino, COALESCE(p_excecoes, '{}'::jsonb),
            COALESCE(p_confirmar_8h24, false), v_uid, v_email);

    FOR g IN
      SELECT (x->>'escala_id')::uuid AS escala_id, x->>'destino' AS destino, x->>'modo' AS modo,
             jsonb_agg(x) AS itens
        FROM jsonb_array_elements(v_linhas) x
       GROUP BY 1, 2, 3
       ORDER BY 1, 2
    LOOP
      v_esc := (SELECT e FROM public.ponto_escalas e WHERE e.id = g.escala_id);
      l := g.itens->0;
      IF g.modo = 'escala' THEN
        -- Mecanismo da F1: a própria escala com "vale a partir de" = data do marco.
        UPDATE public.ponto_escalas e SET
          dias_config                  = (l->'proposta'->'dias_config'),
          compensacoes_mensais         = (l->'proposta'->'compensacoes_mensais'),
          jornada_diaria_minutos       = (l->'proposta'->>'jornada_diaria_minutos')::int,
          jornada_semanal_minutos      = (l->'proposta'->>'jornada_semanal_minutos')::int,
          carga_semanal_contratada_min = (l->'proposta'->>'carga_semanal_contratada_min')::int,
          tipo                         = l->'proposta'->>'tipo',
          hora_entrada_padrao          = (l->'proposta'->>'hora_entrada_padrao')::time,
          hora_saida_padrao            = (l->'proposta'->>'hora_saida_padrao')::time,
          sabado_util                  = (l->'proposta'->>'sabado_util')::boolean,
          domingo_util                 = (l->'proposta'->>'domingo_util')::boolean,
          parametros_vigentes_desde    = v_d,
          parametros_vigencia_motivo   = 'Migração EC 141 (assistente)',
          parametros_marco_codigo      = v_marco
        WHERE e.id = g.escala_id;
        PERFORM public._ponto_ec141_sincronizar_periodos(g.escala_id);
        v_nova := g.escala_id;
        v_n_esc := v_n_esc + 1;
      ELSE
        -- Escala nova para o grupo (reaproveita a de uma migração anterior).
        v_nova := (SELECT i.escala_destino_id FROM public.ponto_ec141_migracao_itens i
                    WHERE i.tenant_id = p_tenant AND i.marco_codigo = v_marco AND i.status = 'ativo'
                      AND i.modo = 'nova_escala' AND i.escala_origem_id = g.escala_id AND i.destino = g.destino
                    LIMIT 1);
        IF v_nova IS NULL THEN
          v_nova := gen_random_uuid();
          v_row := jsonb_populate_record(NULL::public.ponto_escalas,
                     to_jsonb(v_esc) || (l->'proposta') || jsonb_build_object(
                       'id', v_nova,
                       'nome', left(v_esc.nome, 180) || ' — ' || g.destino || 'h (EC 141)',
                       'created_at', now(), 'updated_at', now(),
                       'parametros_vigentes_desde', v_d,
                       'parametros_vigencia_motivo', NULL, 'parametros_marco_codigo', NULL,
                       'observacoes', 'Criada pelo assistente da EC 141 em ' || to_char(now(), 'DD/MM/YYYY')
                                      || ' a partir da escala "' || v_esc.nome || '"; vale a partir de '
                                      || to_char(v_d, 'DD/MM/YYYY') || '.'));
          INSERT INTO public.ponto_escalas SELECT (v_row).*;
          PERFORM public._ponto_ec141_sincronizar_periodos(v_nova);
          v_n_nova := v_n_nova + 1;
        END IF;
      END IF;

      FOR l IN SELECT x FROM jsonb_array_elements(g.itens) x LOOP
        v_atr := (SELECT a FROM public.ponto_escala_atribuicoes a WHERE a.id = (l->>'atribuicao_id')::uuid);
        v_atr_n := NULL;
        v_item := gen_random_uuid();
        IF g.modo = 'nova_escala' THEN
          -- A atribuição atual termina na véspera; a nova começa na data.
          UPDATE public.ponto_escala_atribuicoes SET data_fim = v_d - 1 WHERE id = v_atr.id;
          v_atr_n := gen_random_uuid();
          INSERT INTO public.ponto_escala_atribuicoes
            (id, tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf, data_inicio, ativa)
          VALUES (v_atr_n, p_tenant, v_nova, v_atr.colaborador_id, v_atr.colaborador_nome, v_atr.colaborador_cpf, v_d, true);
        END IF;

        INSERT INTO public.ponto_ec141_migracao_itens
          (id, migracao_id, tenant_id, empresa_id, marco_codigo, colaborador_chave, colaborador_id, colaborador_cpf,
           colaborador_nome, escala_origem_id, escala_destino_id, modo, destino, atribuicao_anterior,
           atribuicao_nova_id, carga_antes_min, carga_depois_min, tem_coletivo, avisos)
        VALUES (v_item, v_mig, p_tenant, NULLIF(l->>'empresa_id', '')::uuid, v_marco, l->>'chave', l->>'colaborador_id',
                l->>'colaborador_cpf', l->>'colaborador_nome', g.escala_id, v_nova, g.modo, g.destino,
                to_jsonb(v_atr), v_atr_n, (l->>'carga_antes_min')::int, (l->>'carga_depois_min')::int,
                (l->>'tem_coletivo')::boolean, l->'avisos');

        -- Aditivo individual (texto pelo modelo, variáveis da conta).
        v_emp := (SELECT ec FROM public.empresa_cadastro ec WHERE ec.id = NULLIF(l->>'empresa_id', '')::uuid);
        v_vars := jsonb_build_object(
          'empresa_nome', COALESCE(v_emp.razao_social, v_emp.nome_fantasia, '________________'),
          'empresa_cnpj', COALESCE(v_emp.cnpj, '________________'),
          'colaborador_nome', COALESCE(l->>'colaborador_nome', '________________'),
          'colaborador_cpf', CASE WHEN length(COALESCE(l->>'colaborador_cpf', '')) = 11
                                  THEN regexp_replace(l->>'colaborador_cpf', '^(\d{3})(\d{3})(\d{3})(\d{2})$', '\1.\2.\3-\4')
                                  ELSE COALESCE(l->>'colaborador_cpf', '________________') END,
          'teto_semanal', public._ponto_ec141_horas((v_prev->'marco'->>'teto_semanal_min')::int),
          'vigencia_inicio', to_char(v_d, 'DD/MM/YYYY'),
          'jornada_anterior', l->>'jornada_atual',
          'carga_anterior', public._ponto_ec141_horas((l->>'carga_antes_min')::int),
          'jornada_nova', l->>'jornada_nova',
          'carga_nova', public._ponto_ec141_horas((l->>'carga_depois_min')::int),
          'clausula_jornada_diaria', CASE
            WHEN COALESCE((l->>'maior_dia_depois_min')::int, 0) <= 480
              THEN 'A jornada diária não excede 8 (oito) horas.'
            WHEN (l->>'tem_coletivo')::boolean
              THEN 'A jornada diária superior a 8 (oito) horas observa o instrumento coletivo vigente'
                   || COALESCE(' (' || (l->>'instrumento_nome') || ')', '') || ' (EC 141/2026, art. 7º).'
            ELSE 'A jornada diária superior a 8 (oito) horas, durante a transição, observa o que for ajustado em negociação coletiva (EC 141/2026, art. 7º).' END);
        INSERT INTO public.ponto_ec141_aditivos
          (tenant_id, empresa_id, migracao_id, item_id, colaborador_id, colaborador_cpf, colaborador_nome,
           vigencia_inicio, modelo_versao, variaveis, texto)
        VALUES (p_tenant, NULLIF(l->>'empresa_id', '')::uuid, v_mig, v_item, l->>'colaborador_id',
                l->>'colaborador_cpf', l->>'colaborador_nome', v_d,
                public.ponto_ec141_aditivo_modelo()->>'versao', v_vars, public._ponto_ec141_aditivo_render(v_vars));
        v_adit := v_adit + 1;
        v_n := v_n + 1;
      END LOOP;
    END LOOP;

    UPDATE public.ponto_ec141_migracoes SET resumo = jsonb_build_object(
      'migrados', v_n, 'escalas_agendadas', v_n_esc, 'escalas_novas', v_n_nova,
      'aditivos', v_adit, 'aguardando_confirmacao', v_pulados)
     WHERE id = v_mig;
  EXCEPTION WHEN OTHERS THEN
    -- Tudo ou nada: o bloco desfaz o que gravou.
    RETURN jsonb_build_object('ok', false, 'erro', 'falha', 'mensagem', SQLERRM);
  END;

  RETURN jsonb_build_object('ok', true, 'migracao_id', v_mig, 'migrados', v_n,
    'escalas_agendadas', v_n_esc, 'escalas_novas', v_n_nova, 'aditivos', v_adit,
    'aguardando_confirmacao', v_pulados, 'vigencia_inicio', v_d, 'marco_codigo', v_marco);
END $fn$;

COMMENT ON FUNCTION public.ponto_ec141_migracao_aplicar(uuid, uuid, text, jsonb, boolean, uuid[]) IS
  'EC 141 F2a — grava a migração (tudo ou nada) com "vale a partir de" = data do marco ativo; nunca altera dias anteriores. Idempotente: colaborador já migrado para o marco é pulado. Gera o aditivo individual e o registro de auditoria.';

-- ---------------------------------------------------------------------
-- 4) CANCELAR A MIGRAÇÃO (lei revogada/adiada) — restaura o estado exato
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ec141_migracao_cancelar(
  p_tenant uuid, p_empresa uuid DEFAULT NULL, p_marco_codigo text DEFAULT NULL,
  p_motivo text DEFAULT NULL, p_migracao_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_motivo text := NULLIF(btrim(COALESCE(p_motivo, '')), '');
  v_uid    uuid := auth.uid();
  v_email  text;
  m        record;
  i        record;
  a        record;
  v_res    jsonb;
  v_migs   int := 0;
  v_itens  int := 0;
  v_rc     int;
  v_adit   int := 0;
  v_falhas jsonb := '[]'::jsonb;
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio',
      'mensagem', 'Informe o motivo (ex.: lei revogada, adiamento, decisão judicial).');
  END IF;
  v_email := (SELECT u.email::text FROM auth.users u WHERE u.id = v_uid);
  PERFORM public._ponto_ec141_fechar_orfaos(p_tenant);

  FOR m IN SELECT * FROM public.ponto_ec141_migracoes x
            WHERE x.tenant_id = p_tenant AND x.status = 'aplicada'
              AND (p_migracao_id IS NULL OR x.id = p_migracao_id)
              AND (p_empresa IS NULL OR x.empresa_id IS NOT DISTINCT FROM p_empresa)
              AND (p_marco_codigo IS NULL OR x.marco_codigo = p_marco_codigo)
            ORDER BY x.acionado_em DESC
  LOOP
    IF m.vigencia_inicio <= CURRENT_DATE THEN
      v_falhas := v_falhas || jsonb_build_array(jsonb_build_object('migracao_id', m.id, 'erro', 'data_ja_chegou',
        'mensagem', format('A migração vale desde %s: depois da data, o cancelamento alteraria dias já apurados.', to_char(m.vigencia_inicio, 'DD/MM/YYYY'))));
      CONTINUE;
    END IF;
    BEGIN
      -- (a) escalas agendadas: o cancelamento da F1 devolve o estado exato.
      FOR a IN SELECT DISTINCT it.escala_origem_id FROM public.ponto_ec141_migracao_itens it
                WHERE it.migracao_id = m.id AND it.status = 'ativo' AND it.modo = 'escala' LOOP
        IF EXISTS (SELECT 1 FROM public.ponto_escala_param_versoes pv
                    WHERE pv.escala_id = a.escala_origem_id AND pv.vigencia_fim >= CURRENT_DATE
                      AND pv.marco_codigo = m.marco_codigo) THEN
          v_res := public.ponto_escala_cancelar_agendamento(a.escala_origem_id);
          IF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
            RAISE EXCEPTION 'Agendamento da escala % nao cancelado: %', a.escala_origem_id, COALESCE(v_res->>'mensagem', v_res->>'erro');
          END IF;
        END IF;
      END LOOP;
      -- (b) escalas novas: devolve a atribuição anterior como era e apaga a nova.
      FOR i IN SELECT * FROM public.ponto_ec141_migracao_itens it
                WHERE it.migracao_id = m.id AND it.status = 'ativo' AND it.modo = 'nova_escala' LOOP
        DELETE FROM public.ponto_escala_atribuicoes WHERE id = i.atribuicao_nova_id;
        UPDATE public.ponto_escala_atribuicoes x SET
          data_fim = NULLIF(i.atribuicao_anterior->>'data_fim', '')::date,
          ativa    = (i.atribuicao_anterior->>'ativa')::boolean
         WHERE x.id = (i.atribuicao_anterior->>'id')::uuid;
      END LOOP;
      FOR a IN SELECT DISTINCT it.escala_destino_id FROM public.ponto_ec141_migracao_itens it
                WHERE it.migracao_id = m.id AND it.status = 'ativo' AND it.modo = 'nova_escala' LOOP
        IF NOT EXISTS (SELECT 1 FROM public.ponto_escala_atribuicoes x WHERE x.escala_id = a.escala_destino_id)
           AND NOT EXISTS (SELECT 1 FROM public.ponto_ec141_migracao_itens o
                            WHERE o.escala_destino_id = a.escala_destino_id AND o.status = 'ativo' AND o.migracao_id <> m.id) THEN
          DELETE FROM public.ponto_escala_periodos WHERE escala_id = a.escala_destino_id;
          DELETE FROM public.ponto_escalas WHERE id = a.escala_destino_id;
        END IF;
      END LOOP;
      -- (c) aditivos: os não assinados ficam cancelados (e a solicitação também).
      FOR a IN SELECT ad.id, ad.solicitacao_id FROM public.ponto_ec141_aditivos ad
                WHERE ad.migracao_id = m.id AND ad.status <> 'cancelado' LOOP
        IF a.solicitacao_id IS NOT NULL THEN
          PERFORM public.assinatura_cancelar(a.solicitacao_id, 'migracao_ec141_cancelada');
        END IF;
        UPDATE public.ponto_ec141_aditivos SET status = 'cancelado', atualizado_em = now() WHERE id = a.id;
        v_adit := v_adit + 1;
      END LOOP;
      UPDATE public.ponto_ec141_migracao_itens SET status = 'cancelado' WHERE migracao_id = m.id AND status = 'ativo';
      GET DIAGNOSTICS v_rc = ROW_COUNT;
      v_itens := v_itens + v_rc;
      UPDATE public.ponto_ec141_migracoes SET status = 'cancelada', cancelado_por = v_uid,
             cancelado_por_email = v_email, cancelado_em = now(), cancelado_motivo = v_motivo
       WHERE id = m.id;
      v_migs := v_migs + 1;
    EXCEPTION WHEN OTHERS THEN
      v_falhas := v_falhas || jsonb_build_array(jsonb_build_object('migracao_id', m.id, 'erro', 'falha', 'mensagem', SQLERRM));
    END;
  END LOOP;

  RETURN jsonb_build_object('ok', jsonb_array_length(v_falhas) = 0, 'migracoes_canceladas', v_migs,
    'colaboradores_restaurados', v_itens, 'aditivos_cancelados', v_adit, 'falhas', v_falhas);
END $fn$;

COMMENT ON FUNCTION public.ponto_ec141_migracao_cancelar(uuid, uuid, text, text, uuid) IS
  'EC 141 F2a — cancela a(s) migração(ões) da conta/empresa antes da data: escalas agendadas voltam pelo cancelamento da F1, atribuições voltam como eram, escalas novas são apagadas, aditivos não assinados ficam cancelados. Registra quem cancelou e o motivo.';

-- ---------------------------------------------------------------------
-- 5) LEITURAS PARA A TELA
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ec141_migracoes_lista(p_tenant uuid, p_empresa uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id', m.id, 'empresa_id', m.empresa_id, 'marco_codigo', m.marco_codigo,
             'vigencia_inicio', m.vigencia_inicio, 'destino_padrao', m.destino_padrao,
             'status', m.status, 'resumo', m.resumo, 'confirmou_8h24', m.confirmou_8h24,
             'acionado_por_email', m.acionado_por_email, 'acionado_em', m.acionado_em,
             'cancelado_por_email', m.cancelado_por_email, 'cancelado_em', m.cancelado_em,
             'cancelado_motivo', m.cancelado_motivo,
             'pode_cancelar', m.status = 'aplicada' AND m.vigencia_inicio > CURRENT_DATE)
           ORDER BY m.acionado_em DESC)
      FROM public.ponto_ec141_migracoes m
     WHERE m.tenant_id = p_tenant
       AND (p_empresa IS NULL OR m.empresa_id IS NULL OR m.empresa_id = p_empresa)), '[]'::jsonb);
END $fn$;

-- Aditivos com a situação da assinatura (a do fluxo de assinatura vence).
CREATE OR REPLACE FUNCTION public.ponto_ec141_aditivos_lista(
  p_tenant uuid, p_empresa uuid DEFAULT NULL, p_so_pendentes boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public._ponto_ec141_pode_tenant(p_tenant) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN COALESCE((
    WITH ad AS MATERIALIZED (
      SELECT a.*, s.status AS assinatura_status, s.respondido_em,
             CASE WHEN a.status = 'cancelado' THEN 'cancelado'
                  WHEN it.status = 'cancelado' AND s.id IS NULL THEN 'cancelado'
                  WHEN it.id IS NOT NULL AND s.id IS NULL
                       AND NOT public._ponto_ec141_item_vivo(it.modo, it.escala_origem_id, it.marco_codigo) THEN 'cancelado'
                  WHEN s.status IN ('assinado', 'assinado_com_ressalva') THEN 'assinado'
                  WHEN s.status = 'contestado' THEN 'contestado'
                  WHEN s.status IN ('enviado', 'visualizado', 'na_fila', 'preparando') THEN 'aguardando_assinatura'
                  ELSE 'pendente_envio' END AS situacao
        FROM public.ponto_ec141_aditivos a
        LEFT JOIN public.assinatura_solicitacoes s ON s.id = a.solicitacao_id
        LEFT JOIN public.ponto_ec141_migracao_itens it ON it.id = a.item_id
       WHERE a.tenant_id = p_tenant
         AND (p_empresa IS NULL OR a.empresa_id IS NULL OR a.empresa_id = p_empresa)
    )
    SELECT jsonb_agg(jsonb_build_object(
             'id', ad.id, 'migracao_id', ad.migracao_id, 'colaborador_nome', ad.colaborador_nome,
             'colaborador_cpf', ad.colaborador_cpf, 'colaborador_id', ad.colaborador_id,
             'empresa_id', ad.empresa_id, 'vigencia_inicio', ad.vigencia_inicio,
             'situacao', ad.situacao, 'assinatura_status', ad.assinatura_status,
             'solicitacao_id', ad.solicitacao_id, 'respondido_em', ad.respondido_em,
             'criado_em', ad.criado_em)
           ORDER BY ad.colaborador_nome)
      FROM ad
     WHERE NOT COALESCE(p_so_pendentes, false) OR ad.situacao NOT IN ('assinado', 'cancelado')), '[]'::jsonb);
END $fn$;

-- Texto do aditivo para gerar o PDF (a tela monta o PDF e o envia pela
-- função de borda assinatura-solicitar, que guarda o PDF e o hash).
CREATE OR REPLACE FUNCTION public.ponto_ec141_aditivo_documento(p_aditivo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v public.ponto_ec141_aditivos;
BEGIN
  v := (SELECT a FROM public.ponto_ec141_aditivos a WHERE a.id = p_aditivo_id);
  IF v.id IS NULL OR NOT public._ponto_ec141_pode_tenant(v.tenant_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_encontrado');
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v.id, 'titulo', public.ponto_ec141_aditivo_modelo()->>'titulo',
    'texto', v.texto, 'variaveis', v.variaveis, 'modelo_versao', v.modelo_versao, 'status', v.status,
    'colaborador_nome', v.colaborador_nome, 'vigencia_inicio', v.vigencia_inicio);
END $fn$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
DO $grants_f2$
BEGIN
  REVOKE ALL ON FUNCTION public.ponto_ec141_migracao_aplicar(uuid, uuid, text, jsonb, boolean, uuid[]) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_ec141_migracao_cancelar(uuid, uuid, text, text, uuid) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public.ponto_ec141_migracao_previa(uuid, uuid, text, jsonb, uuid[]) FROM PUBLIC, anon;
  REVOKE ALL ON FUNCTION public._ponto_ec141_colaboradores(uuid, uuid, date, uuid[]) FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public._ponto_ec141_proposta(public.ponto_escalas, integer, date) FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public._ponto_ec141_definir_modos(uuid, date, jsonb) FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public._ponto_ec141_coletivo_colaborador(uuid, uuid, uuid, date) FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public._ponto_ec141_fechar_orfaos(uuid) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_migracao_previa(uuid, uuid, text, jsonb, uuid[]) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_migracao_aplicar(uuid, uuid, text, jsonb, boolean, uuid[]) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_migracao_cancelar(uuid, uuid, text, text, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_migracoes_lista(uuid, uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_aditivos_lista(uuid, uuid, boolean) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_aditivo_documento(uuid) TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_ec141_aditivo_modelo() TO authenticated, service_role;
  GRANT EXECUTE ON FUNCTION public.ponto_escala_ec141_validar_salvar(uuid, jsonb, date) TO authenticated, service_role;
  GRANT SELECT ON public.ponto_ec141_migracoes, public.ponto_ec141_migracao_itens, public.ponto_ec141_aditivos TO authenticated;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Permissoes EC 141 F2a nao aplicadas: %', SQLERRM;
END $grants_f2$;

-- Tabelas novas com tenant_id recebem a cerca do QA (PONTO-270 vigia).
DO $cercas_f2$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'qa_instalar_cercas';
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM * FROM public.qa_instalar_cercas();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel instalar as cercas: %', SQLERRM;
END $cercas_f2$;
