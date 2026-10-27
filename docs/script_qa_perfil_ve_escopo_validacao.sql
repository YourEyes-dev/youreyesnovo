-- ============================================================================
-- QA COMPORTAMENTAL — porteiro de leitura por escopo (public.perfil_ve_cpf)
-- Prova que a leitura respeita o ESCOPO do perfil de acesso (perfil_permissoes):
--   PERFIL-050 proprio_usuario -> vê o próprio, NÃO vê outro
--   PERFIL-051 empresa_inteira -> vê outro colaborador
--   PERFIL-052 sem o módulo    -> não vê nem o próprio (porta do módulo fechada)
--   PERFIL-053 escopo não-mapeado (unidade) -> fail-closed = só o próprio
--   PERFIL-054 subordinados_diretos -> vê subordinado, NÃO vê não-subordinado
--   PERFIL-055 setor (= departamento) -> vê mesmo depto, NÃO vê outro depto
-- Usa o DSL de QA (qa_up_usuario/perfil/vincular/entrar/sair). Dados de teste
-- no tenant sandbox, desfeitos pelo descarte do motor. Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- Helper: monta o qa_retorno a partir de uma asserção booleana.
CREATE OR REPLACE FUNCTION public.qa_esc_resultado(
  p_esperado text, p_ok boolean, p_obtido text
) RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Aferir public.perfil_ve_cpf sob um usuário logado com escopo definido';
  r.esperado    := p_esperado;
  r.obtido      := p_obtido;
  r.situacao    := CASE WHEN p_ok THEN 'passou'::public.qa_situacao ELSE 'falhou'::public.qa_situacao END;
  RETURN r;
END $fn$;

-- Cria uma admissao mínima no sandbox (p/ subordinados/setor).
CREATE OR REPLACE FUNCTION public.qa_esc_admissao(
  p_cpf text, p_nome text, p_gestor_cpf text, p_departamento text
) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_t uuid := public.qa_sandbox_tenant_id();
BEGIN
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, departamento, gestor_cpf)
  VALUES (v_t, p_nome, p_cpf,
          lower(replace(p_nome,' ','.')) || '@qa.local', 'Analista',
          p_departamento, p_gestor_cpf);
END $fn$;

-- ── PERFIL-050: proprio_usuario vê só o próprio ──────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid();
  v_a uuid; v_b uuid; v_perf uuid;
  v_ve_a boolean; v_ve_b boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('PERFIL-050', 1, '11111111111', 'ativo', v_uidA);
  v_b := public.qa_up_usuario('PERFIL-050', 2, '22222222222', 'ativo', gen_random_uuid());
  v_perf := public.qa_up_perfil('PERFIL-050', 'Próprio Metas', 'metas', 'proprio_usuario', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_a := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '11111111111', 'metas');
  v_ve_b := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '22222222222', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'escopo proprio_usuario: vê o próprio (true) e NÃO vê outro (false)',
    (v_ve_a IS TRUE AND v_ve_b IS FALSE),
    format('vê_próprio=%s  vê_outro=%s', v_ve_a, v_ve_b));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── PERFIL-051: empresa_inteira vê outro colaborador ─────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_051()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid(); v_a uuid; v_perf uuid; v_ve_b boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('PERFIL-051', 1, '11111111111', 'ativo', v_uidA);
  PERFORM public.qa_up_usuario('PERFIL-051', 2, '22222222222', 'ativo', gen_random_uuid());
  v_perf := public.qa_up_perfil('PERFIL-051', 'Empresa Metas', 'metas', 'empresa_inteira', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_b := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '22222222222', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'escopo empresa_inteira: vê outro colaborador (true)',
    (v_ve_b IS TRUE),
    format('vê_outro=%s', v_ve_b));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── PERFIL-052: sem o módulo não vê nem o próprio ────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid(); v_a uuid; v_perf uuid; v_ve_a boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('PERFIL-052', 1, '11111111111', 'ativo', v_uidA);
  -- perfil amplo, mas em OUTRO módulo (ferias), não em metas
  v_perf := public.qa_up_perfil('PERFIL-052', 'Ferias Ampla', 'ferias', 'empresa_inteira', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_a := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '11111111111', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'sem o módulo metas: não vê nem o próprio (false)',
    (v_ve_a IS FALSE),
    format('vê_próprio_em_metas=%s', v_ve_a));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── PERFIL-053: escopo não-mapeado (unidade) = fail-closed ao próprio ────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_053()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid(); v_a uuid; v_perf uuid;
  v_ve_a boolean; v_ve_b boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('PERFIL-053', 1, '11111111111', 'ativo', v_uidA);
  PERFORM public.qa_up_usuario('PERFIL-053', 2, '22222222222', 'ativo', gen_random_uuid());
  v_perf := public.qa_up_perfil('PERFIL-053', 'Unidade Metas', 'metas', 'unidade', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_a := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '11111111111', 'metas');
  v_ve_b := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '22222222222', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'escopo não-mapeado (unidade) = fail-closed: vê o próprio, NÃO vê outro',
    (v_ve_a IS TRUE AND v_ve_b IS FALSE),
    format('vê_próprio=%s  vê_outro=%s', v_ve_a, v_ve_b));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── PERFIL-054: subordinados_diretos vê subordinado, não vê não-subordinado ──
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_054()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid(); v_a uuid; v_perf uuid;
  v_ve_sub boolean; v_ve_nao boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  -- A é o gestor logado
  v_a := public.qa_up_usuario('PERFIL-054', 1, '11111111111', 'ativo', v_uidA);
  -- admissões: B subordinado de A (gestor_cpf=A); C não-subordinado
  PERFORM public.qa_esc_admissao('11111111111', 'Gestor A', NULL, 'RH');
  PERFORM public.qa_esc_admissao('22222222222', 'Subordinado B', '11111111111', 'RH');
  PERFORM public.qa_esc_admissao('33333333333', 'Outro C', '99999999999', 'RH');
  v_perf := public.qa_up_perfil('PERFIL-054', 'Subord Metas', 'metas', 'subordinados_diretos', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_sub := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '22222222222', 'metas');
  v_ve_nao := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '33333333333', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'escopo subordinados_diretos: vê subordinado (true), NÃO vê não-subordinado (false)',
    (v_ve_sub IS TRUE AND v_ve_nao IS FALSE),
    format('vê_subordinado=%s  vê_não_subordinado=%s', v_ve_sub, v_ve_nao));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── PERFIL-055: setor (= departamento) vê mesmo depto, não vê outro ──────────
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_055()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  v_uidA uuid := gen_random_uuid(); v_a uuid; v_perf uuid;
  v_ve_mesmo boolean; v_ve_outro boolean;
BEGIN
  PERFORM public.qa_modo_ligar();
  v_a := public.qa_up_usuario('PERFIL-055', 1, '11111111111', 'ativo', v_uidA);
  PERFORM public.qa_esc_admissao('11111111111', 'Pessoa A', NULL, 'RH');
  PERFORM public.qa_esc_admissao('22222222222', 'Pessoa B', NULL, 'RH');  -- mesmo depto
  PERFORM public.qa_esc_admissao('33333333333', 'Pessoa C', NULL, 'TI');  -- outro depto
  v_perf := public.qa_up_perfil('PERFIL-055', 'Setor Metas', 'metas', 'setor', 'visualizar');
  PERFORM public.qa_up_vincular(v_a, NULL, v_perf);

  PERFORM public.qa_up_entrar(v_uidA);
  v_ve_mesmo := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '22222222222', 'metas');
  v_ve_outro := public.perfil_ve_cpf(public.qa_sandbox_tenant_id(), '33333333333', 'metas');
  PERFORM public.qa_up_sair();

  RETURN public.qa_esc_resultado(
    'escopo setor (=departamento): vê mesmo depto (true), NÃO vê outro depto (false)',
    (v_ve_mesmo IS TRUE AND v_ve_outro IS FALSE),
    format('vê_mesmo_depto=%s  vê_outro_depto=%s', v_ve_mesmo, v_ve_outro));
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_sair();
  RETURN public.qa_esc_resultado('sem erro', false, 'quebrou: ' || SQLERRM);
END $fn$;

-- ── Registro dos casos + implementações ──────────────────────────────────────
DO $reg$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'QA perfil_ve_cpf: harness ausente, pulando registro.'; RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    v_mod := (SELECT id FROM public.qa_modulos ORDER BY ordem NULLS LAST LIMIT 1);
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo)
  VALUES
    (v_mod, 'PERFIL-050', 'Leitura por escopo: proprio_usuario vê só o próprio', 'negativo', 'alta', 'aprovado', 'api',
     'Perfil com escopo proprio_usuario em metas vê o próprio e não vê outro colaborador.'),
    (v_mod, 'PERFIL-051', 'Leitura por escopo: empresa_inteira vê outro', 'feliz', 'alta', 'aprovado', 'api',
     'Perfil empresa_inteira em metas vê outro colaborador.'),
    (v_mod, 'PERFIL-052', 'Leitura por escopo: sem o módulo não vê nem o próprio', 'negativo', 'alta', 'aprovado', 'api',
     'Perfil sem o módulo metas não vê nem o próprio registro.'),
    (v_mod, 'PERFIL-053', 'Leitura por escopo: não-mapeado = fail-closed ao próprio', 'negativo', 'alta', 'aprovado', 'api',
     'Escopo não mapeado (unidade) cai no próprio apenas.'),
    (v_mod, 'PERFIL-054', 'Leitura por escopo: subordinados_diretos', 'negativo', 'alta', 'aprovado', 'api',
     'Vê subordinado direto e não vê não-subordinado.'),
    (v_mod, 'PERFIL-055', 'Leitura por escopo: setor (=departamento)', 'negativo', 'alta', 'aprovado', 'api',
     'Vê mesmo departamento e não vê outro.')
  ON CONFLICT (codigo) DO UPDATE SET
    modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo,
    objetivo = EXCLUDED.objetivo, status = 'aprovado';

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
      ('PERFIL-050', 'qa_caso_perfil_050', true),
      ('PERFIL-051', 'qa_caso_perfil_051', true),
      ('PERFIL-052', 'qa_caso_perfil_052', true),
      ('PERFIL-053', 'qa_caso_perfil_053', true),
      ('PERFIL-054', 'qa_caso_perfil_054', true),
      ('PERFIL-055', 'qa_caso_perfil_055', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
END
$reg$;

-- ── RUNNER DE VALIDAÇÃO (temporário; removido na versão migration) ───────────
-- Executa cada caso e imprime situacao|obtido, com ROLLBACK por caso para não
-- sujar o sandbox (BEGIN/EXCEPTION desfaz os writes do caso).
DO $run$
DECLARE c text; res public.qa_retorno;
BEGIN
  FOREACH c IN ARRAY ARRAY['qa_caso_perfil_050','qa_caso_perfil_051','qa_caso_perfil_052',
                           'qa_caso_perfil_053','qa_caso_perfil_054','qa_caso_perfil_055'] LOOP
    BEGIN
      EXECUTE format('SELECT * FROM public.%I()', c) INTO res;
      RAISE EXCEPTION 'ROLLBACK_ME:% | %', res.situacao, COALESCE(res.obtido,'');
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'ROLLBACK_ME:%' THEN
        RAISE NOTICE 'VALIDACAO % -> %', c, substring(SQLERRM from 'ROLLBACK_ME:(.*)');
      ELSE
        RAISE NOTICE 'VALIDACAO % -> ERRO_INESPERADO: %', c, SQLERRM;
      END IF;
    END;
  END LOOP;
END
$run$;
