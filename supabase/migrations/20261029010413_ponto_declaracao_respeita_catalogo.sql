-- ============================================================================
-- Ponto — declaração de comparecimento respeita a regra do catálogo
-- [declaracao-respeita-catalogo]  ·  Plano do Ponto, Fase 2 / F0b
-- ----------------------------------------------------------------------------
-- A consolidação (20261020162245) já decide certo: declaração só abona se o
-- catálogo da empresa disser "Abona" (ou "Configurável" e marcada). Mas quatro
-- pontos tratavam QUALQUER atestado como abono, desfazendo a regra:
--   1) gatilho legado trigger_justificar_ponto_atestado (atestado em DIAS):
--      roda depois da consolidação e marca o dia 'justificado';
--   2) saldo (ponto_saldo_dias_competencia_bruto): dia "protegido" por qualquer
--      atestado em dias;
--   3) saldo: dia "protegido" por qualquer atestado em horas sem marcação;
--   4) saldo: soma das horas de atestado reduz a jornada esperada.
-- Efeito: declaração configurada "Não abona" era abonada — em dias pelo
-- gatilho, em horas pelo saldo (o débito sumia).
--
-- Correção (aditiva, sem reescrever função remendada):
--   * função nova atestado_abona_no_ponto(tenant, subtipo, abona): regra única
--     — atestado comum abona; declaração segue o catálogo;
--   * gatilho legado passa a ignorar declarações (a consolidação decide);
--   * reinjeção no corpo VIGENTE do saldo: os três filtros de atestado ganham
--     a condição da regra. Âncoras contadas (dias = 1, horas = 2); se não
--     baterem, NADA muda (só aviso).
-- Dias já marcados 'justificado' no passado NÃO são revertidos (decisão de
-- dados do RH). Caso QA PONTO-DECL-01.
-- ============================================================================

-- 1) Regra única
CREATE OR REPLACE FUNCTION public.atestado_abona_no_ponto(
  p_tenant_id uuid, p_subtipo text, p_abona boolean
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH r AS (
    SELECT COALESCE((
      SELECT j.tipo_abono FROM public.ponto_justificativas j
      WHERE j.tenant_id = p_tenant_id AND j.codigo = 'DECLARACAO_COMPARECIMENTO'
      ORDER BY j.empresa_id NULLS LAST LIMIT 1), 'configuravel') AS regra
  )
  SELECT CASE
           WHEN COALESCE(p_subtipo, '') <> 'comparecimento' THEN true
           ELSE (SELECT regra = 'sim' OR (regra = 'configuravel' AND COALESCE(p_abona, false)) FROM r)
         END;
$function$;

COMMENT ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) IS
  'Regra única: atestado comum abona no ponto; declaração de comparecimento só abona '
  'se o catálogo (DECLARACAO_COMPARECIMENTO) disser Abona, ou Configurável e o documento '
  'estiver marcado para abonar. Usada pelo saldo diário. [declaracao-respeita-catalogo]';

REVOKE ALL ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.atestado_abona_no_ponto(uuid, text, boolean) TO authenticated;

-- 2) Gatilho legado ignora declarações (a consolidação aplica o catálogo)
DROP TRIGGER IF EXISTS trigger_justificar_ponto_atestado ON public.atestados;
CREATE TRIGGER trigger_justificar_ponto_atestado
  AFTER INSERT OR UPDATE ON public.atestados
  FOR EACH ROW
  WHEN (NEW.data_inicio_afastamento IS NOT NULL
        AND COALESCE(NEW.subtipo_assistencial::text, '') <> 'comparecimento')
  EXECUTE FUNCTION public.justificar_ponto_por_atestado();

-- 3) Reinjeção no saldo diário
DO $patch$
DECLARE
  v_src text;
  v_new text;
  v_dias text := 'AND COALESCE(a.unidade_afastamento, ''dias'') = ''dias''';
  v_horas text := 'AND COALESCE(a.unidade_afastamento, ''dias'') = ''horas''';
  v_cond text := ' AND public.atestado_abona_no_ponto(p_tenant_id, a.subtipo_assistencial::text, a.abona)';
  v_n_dias int;
  v_n_horas int;
BEGIN
  v_src := pg_get_functiondef('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)'::regprocedure);

  IF position('[declaracao-respeita-catalogo]' IN v_src) > 0 THEN
    RAISE NOTICE 'saldo: [declaracao-respeita-catalogo] ja aplicado; nada a fazer.';
    RETURN;
  END IF;

  v_n_dias  := (length(v_src) - length(replace(v_src, v_dias, ''))) / length(v_dias);
  v_n_horas := (length(v_src) - length(replace(v_src, v_horas, ''))) / length(v_horas);

  IF v_n_dias <> 1 OR v_n_horas <> 2 THEN
    RAISE NOTICE 'saldo: ancoras de [declaracao-respeita-catalogo] nao batem (dias=%, horas=%); nada alterado — revisar.', v_n_dias, v_n_horas;
    RETURN;
  END IF;

  v_new := replace(v_src, v_dias, v_dias || v_cond || ' /* [declaracao-respeita-catalogo] */');
  v_new := replace(v_new, v_horas, v_horas || v_cond);
  EXECUTE v_new;
  RAISE NOTICE 'saldo: [declaracao-respeita-catalogo] aplicado.';
END;
$patch$;

-- ---------------------------------------------------------------------
-- QA PONTO-DECL-01
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_decl_01()
RETURNS public.qa_retorno
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.qa_retorno;
  v_t uuid;
  v_d date := DATE '2026-08-11';   -- terça, sem feriado nacional
  v_comp text := '2026-08';
  v_cpf_decl text := public.qa_cpf(4911);
  v_cpf_med  text := public.qa_cpf(4912);
  v_cpf_dias text := public.qa_cpf(4913);
  v_saldo_decl int;
  v_saldo_med int;
  v_status_dias text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Declaração de 2h "não abona" × atestado médico de 2h × declaração de 1 dia "não abona"';
  r.esperado    := 'Declaração mantém o débito de 2h; atestado médico reduz a jornada (saldo 0); declaração em dias não justifica o dia';

  PERFORM public.qa_modo_ligar();
  v_t := public.qa_sandbox_tenant_id();

  -- Catálogo do cercado: declaração NÃO abona (a bateria desfaz ao fim)
  UPDATE public.ponto_justificativas SET tipo_abono = 'nao'
   WHERE tenant_id = v_t AND codigo = 'DECLARACAO_COMPARECIMENTO';
  IF NOT FOUND THEN
    INSERT INTO public.ponto_justificativas (tenant_id, nome, codigo, tipo_abono, sistema, ativo)
    VALUES (v_t, 'Declaração de comparecimento', 'DECLARACAO_COMPARECIMENTO', 'nao', true, true);
  END IF;

  PERFORM public.qa_ponto_escala_tol(v_cpf_decl, 'QA Decl Horas', 480, 10, v_d, v_d);
  PERFORM public.qa_ponto_dia_min(v_cpf_decl, 'QA Decl Horas', v_d, 360);
  PERFORM public.qa_ponto_escala_tol(v_cpf_med, 'QA Atestado Horas', 480, 10, v_d, v_d);
  PERFORM public.qa_ponto_dia_min(v_cpf_med, 'QA Atestado Horas', v_d, 360);
  PERFORM public.qa_ponto_dia_min(v_cpf_dias, 'QA Decl Dias', v_d, 0);

  INSERT INTO public.atestados
    (tenant_id, colaborador_nome, colaborador_cpf, tipo, subtipo_assistencial, data_emissao,
     profissional_nome, profissional_registro, unidade_afastamento, horas_afastamento,
     minutos_afastamento, data_inicio_afastamento, data_fim_afastamento, abona)
  VALUES
    (v_t, 'QA Decl Horas', v_cpf_decl, 'assistencial', 'comparecimento', v_d, 'QA', 'QA', 'horas', 2, 0, v_d, v_d, false),
    (v_t, 'QA Atestado Horas', v_cpf_med, 'assistencial', 'medico', v_d, 'QA', 'QA', 'horas', 2, 0, v_d, v_d, false),
    (v_t, 'QA Decl Dias', v_cpf_dias, 'assistencial', 'comparecimento', v_d, 'QA', 'QA', 'dias', NULL, NULL, v_d, v_d, false);

  v_saldo_decl := (SELECT s.saldo_min FROM public.ponto_saldo_dias_competencia(v_t, v_cpf_decl, v_comp) s WHERE s.dia = v_d);
  v_saldo_med  := (SELECT s.saldo_min FROM public.ponto_saldo_dias_competencia(v_t, v_cpf_med, v_comp) s WHERE s.dia = v_d);
  v_status_dias := (SELECT pd.status FROM public.ponto_diario pd
                     WHERE pd.tenant_id = v_t AND pd.colaborador_cpf = v_cpf_dias AND pd.data = v_d LIMIT 1);

  IF COALESCE(v_saldo_decl, 0) <= -110
     AND COALESCE(v_saldo_med, -999) BETWEEN -10 AND 10
     AND COALESCE(v_status_dias, '') <> 'justificado' THEN
    r.situacao := 'passou';
    r.obtido := format('Declaração não abona mantém o débito (%s min); atestado médico reduz a jornada (%s); '
             || 'declaração em dias não justifica o dia (status %s).', v_saldo_decl, v_saldo_med, coalesce(v_status_dias,'—'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: declaração "não abona" de 2h deixou saldo %s (esperado -120); atestado médico %s '
             || '(esperado 0); declaração em dias deixou o dia %s (esperado não justificado). '
             || 'A regra do catálogo não está sendo respeitada.',
             coalesce(v_saldo_decl::text,'nulo'), coalesce(v_saldo_med::text,'nulo'), coalesce(v_status_dias,'nulo'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$;

INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-DECL-01', m.id,
  'Declaração de comparecimento "não abona" mantém o débito (dias e horas)',
  'A declaração de comparecimento segue a regra do catálogo da empresa. Configurada como '
  || '"Não abona", o período não trabalhado continua como débito (banco ou folha) — tanto '
  || 'lançada em horas quanto em dias. Atestado médico continua abonando.',
  'negativo', 'api', 'critica', 'aprovado',
  'CLT art. 473 (hipóteses legais de abono); Lei 605/1949, art. 6º, §1º; Portaria MTP 671/2021, art. 74',
  jsonb_build_array(
    jsonb_build_object('ordem', 1, 'acao', 'Declaração de 2h, não abona, em dia trabalhado 6h de 8h',
                       'esperado', 'Saldo do dia -120'),
    jsonb_build_object('ordem', 2, 'acao', 'Atestado médico de 2h, mesmo cenário',
                       'esperado', 'Saldo do dia 0 (jornada reduzida)'),
    jsonb_build_object('ordem', 3, 'acao', 'Declaração de 1 dia, não abona',
                       'esperado', 'Dia não fica justificado')),
  'em_triagem',
  'Fase 2 do plano do Ponto (F0b), out/2026: gatilho legado e saldo abonavam qualquer atestado.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
VALUES ('PONTO-DECL-01', 'qa_caso_ponto_decl_01', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
