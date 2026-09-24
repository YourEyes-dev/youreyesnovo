-- ============================================================================
-- ENTREGA — fechamento: trava "dia curto sem motivo" (drift teste -> producao)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   O teste (fonte da verdade) passou a bloquear o fechamento da competencia
--   quando ha um dia MUITO abaixo da jornada SEM que ninguem tenha declarado o
--   motivo (folga? abono? falta?). Sao DUAS funcoes: uma DETECTA o dia curto
--   (ponto_fechamento_pendencias_criticas), a outra CONTA e bloqueia
--   (ponto_fechar_competencia_verificar). A producao ainda nao tem a trava.
--
--   Corpo copiado VERBATIM do teste (pg_get_functiondef). Envelope DO/EXECUTE
--   para o SQL Editor do Supabase nao confundir SELECT ... INTO com criacao de
--   tabela (injetor de RLS). As funcoes criadas sao byte a byte as do teste.
--
-- COMO RODAR: BLOCO 1, depois BLOCO 2, depois a conferencia (BLOCO 3) numa
--   consulta separada. Cada bloco de criacao volta "Success. No rows returned".
--
-- SEGURANCA: so substitui funcoes; nao altera nem apaga dado; idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── BLOCO 1: ponto_fechamento_pendencias_criticas ───────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_fechamento_pendencias_criticas(p_tenant_id uuid, p_empresa_id uuid, p_competencia text)
 RETURNS TABLE(tipo text, colaborador_cpf text, data_referencia date, descricao text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
BEGIN
  -- Ajustes de ponto PENDENTES de aprovação.
  RETURN QUERY
  SELECT 'ajuste_pendente'::text, a.colaborador_cpf, a.data_referencia,
         'Ajuste de ponto pendente de aprovacao'::text
  FROM public.ponto_ajustes a
  WHERE a.tenant_id = p_tenant_id
    AND a.status = 'pendente'
    AND a.data_referencia BETWEEN v_ini AND v_fim
    AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id);

  -- Dias INCOMPLETOS sem tratamento.
  RETURN QUERY
  SELECT 'dia_incompleto'::text, d.colaborador_cpf, d.data,
         format('Dia incompleto sem tratamento (status %s)', d.status)::text
  FROM public.ponto_diario d
  WHERE d.tenant_id = p_tenant_id
    AND d.data BETWEEN v_ini AND v_fim
    AND d.status IN ('incompleto', 'ajuste_pendente')
    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id);

  -- [dia-curto-sem-motivo] Dia que ficou MUITO abaixo da jornada sem que
  -- ninguem tenha dito por que. Nao e defeito de calculo: e a ausencia de
  -- uma DECLARACAO. Um dia curto pode ser folga compensatoria (debita o
  -- banco), ausencia justificada (nao debita nada) ou falta injustificada
  -- (desconta dia e DSR na folha) — tres efeitos diferentes, e so quem
  -- esteve la sabe qual foi. Sem a declaracao o sistema aplica um deles por
  -- omissao, e o espelho que o trabalhador assina nao explica o debito, o
  -- que fragiliza a prova do empregador (Sumula 338 do TST; Portaria MTP
  -- 671/2021, que exige as OCORRENCIAS no AEJ).
  -- O limite vive em ponto_configuracao.dia_curto_bloqueia_fechamento_minutos
  -- (padrao 60). Zero ou nulo desliga a trava.
  RETURN QUERY
  WITH limite AS (
    SELECT COALESCE(max(c.dia_curto_bloqueia_fechamento_minutos), 60) AS min
    FROM public.ponto_configuracao c
    WHERE c.tenant_id = p_tenant_id
  )
  SELECT 'dia_curto_sem_motivo'::text, d.colaborador_cpf, d.data,
         format('Dia %s min abaixo da jornada sem folga, abono ou ajuste declarado',
                (j.jornada_min - COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0)))::text
  FROM public.ponto_diario d
  CROSS JOIN limite l
  CROSS JOIN LATERAL public.ponto_jornada_do_dia(
    p_tenant_id,
    regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'),
    d.colaborador_id::text, d.data) j
  WHERE d.tenant_id = p_tenant_id
    AND d.data BETWEEN v_ini AND v_fim
    AND (p_empresa_id IS NULL OR d.empresa_id = p_empresa_id)
    AND COALESCE(l.min, 0) > 0
    AND COALESCE(j.jornada_min, 0) > 0
    AND COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0) > 0
    AND (j.jornada_min - COALESCE(floor(EXTRACT(EPOCH FROM d.horas_trabalhadas)/60)::int, 0)) >= l.min
    AND COALESCE(d.tipo_dia, 'util') NOT IN
        ('ferias', 'atestado', 'afastamento', 'feriado', 'folga_compensatoria')
    AND COALESCE(d.status, '') NOT IN ('justificado', 'incompleto', 'ajuste_pendente')
    AND NOT EXISTS (SELECT 1 FROM public.ponto_ajustes a2
                     WHERE a2.tenant_id = d.tenant_id
                       AND a2.data_referencia = d.data
                       AND regexp_replace(COALESCE(a2.colaborador_cpf, ''), '[^0-9]', '', 'g')
                         = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'));

  -- (387) Espelho SEM CIÊNCIA (Súmula 338).
  RETURN QUERY
  SELECT 'espelho_sem_ciencia'::text, e.colaborador_cpf, NULL::date,
         format('Espelho sem ciencia do colaborador (status %s, sem confirmacao/assinatura)', COALESCE(e.status,'-'))::text
  FROM public.ponto_espelhos e
  WHERE e.tenant_id = p_tenant_id
    AND e.competencia = p_competencia
    AND (p_empresa_id IS NULL OR e.empresa_id = p_empresa_id)
    AND COALESCE(e.status, '') NOT IN ('confirmado', 'assinado')
    AND e.data_confirmacao IS NULL
    AND COALESCE(e.assinatura_hash, '') = ''
    AND NULLIF(btrim(COALESCE(e.ressalva_texto, '')), '') IS NULL;
END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 2: ponto_fechar_competencia_verificar ─────────────────────────────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_fechar_competencia_verificar(p_tenant_id uuid, p_empresa_id uuid, p_competencia text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_n        int;
  v_ajustes  int;
  v_dias     int;
  v_espelhos int;
  v_curtos   int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE tipo = 'ajuste_pendente'),
         count(*) FILTER (WHERE tipo = 'dia_incompleto'),
         count(*) FILTER (WHERE tipo = 'dia_curto_sem_motivo'),
         count(*) FILTER (WHERE tipo = 'espelho_sem_ciencia')
    INTO v_n, v_ajustes, v_dias, v_curtos, v_espelhos
  FROM public.ponto_fechamento_pendencias_criticas(p_tenant_id, p_empresa_id, p_competencia);

  IF v_n > 0 THEN
    RAISE EXCEPTION 'Fechamento bloqueado na competencia %: % pendencia(s) critica(s) — % ajuste(s) pendente(s) de aprovacao, % dia(s) incompleto(s), % dia(s) curto(s) sem motivo declarado e % espelho(s) sem ciencia (status/confirmacao/assinatura). Trate antes de fechar.',
      p_competencia, v_n, v_ajustes, v_dias, v_curtos, v_espelhos
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN 0;
END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 3 (conferencia) — RODE SEPARADO. Esperado: 2 linhas, ambas OK ─────
--   WITH esperado(objeto, md5_teste) AS (
--     VALUES
--       ('ponto_fechamento_pendencias_criticas', '3d5790aec970bf2e9e60caef8759d6ae'),
--       ('ponto_fechar_competencia_verificar',   '43871b5a9a274c7f0e6ba01b58ea2c24')
--   )
--   SELECT e.objeto,
--          md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) AS md5_producao,
--          e.md5_teste,
--          CASE WHEN md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) = e.md5_teste
--               THEN 'OK' ELSE 'CONFERIR' END AS status
--   FROM esperado e
--   JOIN pg_proc p      ON p.proname = e.objeto
--   JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   ORDER BY e.objeto;
