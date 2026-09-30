-- ============================================================================
-- ENTREGA — listas do mês do Ponto respeitam o vínculo (desligado só até a data)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO: Apuração/Fechamento e a nova Compensação de Faltas traziam
-- colaboradores DESLIGADOS mesmo em meses após a data de desligamento; e a
-- Compensação de Faltas ainda trazia sábado/domingo (dia sem jornada).
--
-- CORREÇÃO:
--   A. ponto_vinculo_cobre_periodo — regra única de vínculo (reusável).
--   B. consolidar_ponto_dia_todos — para de materializar 'falta' após o desligamento.
--   C. ponto_espelho_resumo_empresa (Fechamento) — filtra por vínculo.
--   D. ponto_banco_horas_oficial (Banco) — filtra por vínculo.
--   E. ponto_faltas_do_mes — fonte da Compensação de Faltas, validando escala
--      (só dia com jornada prevista) e vínculo.
--
-- SEGURANÇA: só cria/substitui FUNÇÃO (não cria tabela, não altera/apaga dado).
-- Idempotente (CREATE OR REPLACE; os patches C/D só aplicam se ainda não
-- estiverem aplicados). Termina com conferência.
-- ============================================================================


-- ---------------------------------------------------------------------
-- A) Regra única de vínculo ativo num período
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_vinculo_cobre_periodo(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_ini date,
  p_fim date
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  -- true quando: (a) o CPF não tem admissão efetivada registrada (não filtramos
  -- quem não tem cadastro — salvaguarda do [vinculo-corte]); ou (b) existe uma
  -- admissão efetivada cujo intervalo [data_admissao, data_desligamento|infinito]
  -- cruza [p_ini, p_fim].
  SELECT
    NOT EXISTS (
      SELECT 1 FROM public.admissoes a
      WHERE a.tenant_id = p_tenant_id
        AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
            = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
        AND a.status::text IN ('concluido','desligado')
    )
    OR EXISTS (
      SELECT 1 FROM public.admissoes a
      WHERE a.tenant_id = p_tenant_id
        AND regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g')
            = regexp_replace(COALESCE(p_colaborador_cpf,''),'[^0-9]','','g')
        AND a.status::text IN ('concluido','desligado')
        AND COALESCE(a.data_admissao, '-infinity'::date) <= p_fim
        AND COALESCE(a.data_desligamento, 'infinity'::date) >= p_ini
    );
$function$;

COMMENT ON FUNCTION public.ponto_vinculo_cobre_periodo(uuid, text, date, date) IS
  'true se o vínculo do colaborador cobre algum dia de [ini,fim] (admissao efetivada; desligado conta até a data_desligamento). Sem admissão efetivada registrada, retorna true (não filtra). Regra única das listas mensais do Ponto.';

-- ---------------------------------------------------------------------
-- B) Materialização para de gerar 'falta' após o desligamento
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consolidar_ponto_dia_todos(p_tenant_id UUID, p_data DATE)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $todos$
DECLARE
  v_colab RECORD;
  v_n INT := 0;
BEGIN
  FOR v_colab IN
    SELECT DISTINCT regexp_replace(a.cpf, '[^0-9]', '', 'g') AS cpf
    FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id AND a.cpf IS NOT NULL
      AND COALESCE(a.inativo, false) = false
      AND COALESCE(a.bate_ponto, true) = true
      AND a.data_admissao <= p_data
      -- [lista-respeita-vinculo] Não materializar dia após o desligamento
      -- (mantém o próprio dia do desligamento, como o [vinculo-corte]).
      AND (a.data_desligamento IS NULL OR a.data_desligamento >= p_data)
      AND (
        a.empresa_id IN (SELECT r.empresa_id FROM public.ponto_empresas_em_regime(p_tenant_id) r)
        OR regexp_replace(a.cpf, '[^0-9]', '', 'g')
           IN (SELECT c.cpf FROM public.ponto_cpfs_em_regime(p_tenant_id, p_data) c)
      )
  LOOP
    PERFORM public.consolidar_ponto_diario_manual(p_tenant_id, v_colab.cpf, p_data);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$todos$;

-- ---------------------------------------------------------------------
-- C) Fechamento: ponto_espelho_resumo_empresa filtra por vínculo (patch)
-- ---------------------------------------------------------------------
DO $patchC$
DECLARE
  v_src text; v_novo text;
  v_alvo text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'';
  v_troca text := E'      AND COALESCE(pd.colaborador_cpf, \'\') <> \'\'\n'
    || E'      -- [lista-respeita-vinculo] não traz desligado após a data\n'
    || E'      AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(pd.colaborador_cpf, \'[^0-9]\', \'\', \'g\'), v_ini, v_fim)';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo_empresa(uuid,uuid,text)'::regprocedure);
  IF position('[lista-respeita-vinculo]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo_empresa ja filtra por vinculo — nada a fazer.'; RETURN;
  END IF;
  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora do loop de cpf em ponto_espelho_resumo_empresa nao encontrada; NADA alterado.'; RETURN;
  END IF;
  v_novo := replace(v_src, v_alvo, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_espelho_resumo_empresa: lista do mes passa a respeitar o vinculo.';
END;
$patchC$;

-- ---------------------------------------------------------------------
-- D) Banco: ponto_banco_horas_oficial filtra por vínculo (patch, 2 ramos)
-- ---------------------------------------------------------------------
DO $patchD$
DECLARE
  v_src text; v_novo text; v_ok boolean := true;
  v_alvo_b text := E'      AND (v_so_cpf IS NULL\n           OR regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)';
  v_troca_b text := E'      AND (v_so_cpf IS NULL\n           OR regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)\n'
    || E'      AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(COALESCE(b.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\'), v_ini, v_fim) /* [lista-respeita-vinculo] */';
  v_alvo_d text := E'        AND (v_so_cpf IS NULL\n             OR regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)';
  v_troca_d text := E'        AND (v_so_cpf IS NULL\n             OR regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\') = v_so_cpf)\n'
    || E'        AND public.ponto_vinculo_cobre_periodo(p_tenant_id, regexp_replace(COALESCE(pd.colaborador_cpf, \'\'), \'[^0-9]\', \'\', \'g\'), v_ini, v_fim) /* [lista-respeita-vinculo] */';
BEGIN
  v_src := pg_get_functiondef('public.ponto_banco_horas_oficial(uuid,text,uuid,text)'::regprocedure);
  IF position('[lista-respeita-vinculo]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_banco_horas_oficial ja filtra por vinculo — nada a fazer.'; RETURN;
  END IF;
  IF position(v_alvo_b IN v_src) = 0 OR position(v_alvo_d IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: ancora(s) em ponto_banco_horas_oficial nao encontrada(s); NADA alterado.'; RETURN;
  END IF;
  v_novo := replace(v_src, v_alvo_b, v_troca_b);
  v_novo := replace(v_novo, v_alvo_d, v_troca_d);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_banco_horas_oficial: lista do mes passa a respeitar o vinculo.';
END;
$patchD$;

-- ---------------------------------------------------------------------
-- E) Fonte da Compensação de Faltas: valida escala (jornada>0) e vínculo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_faltas_do_mes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_competencia text
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  colaborador_id uuid,
  data date,
  jornada_min integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH janela AS (
    SELECT to_date(p_competencia || '-01','YYYY-MM-DD') AS ini,
           (to_date(p_competencia || '-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date AS fim
  )
  SELECT
    regexp_replace(pd.colaborador_cpf,'[^0-9]','','g') AS colaborador_cpf,
    pd.colaborador_nome,
    pd.colaborador_id,
    pd.data,
    j.jornada_min
  FROM janela w
  JOIN public.ponto_diario pd
    ON pd.tenant_id = p_tenant_id
   AND pd.data BETWEEN w.ini AND w.fim
   AND pd.status = 'falta'
   AND COALESCE(pd.colaborador_cpf,'') <> ''
   AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id)
  CROSS JOIN LATERAL public.ponto_jornada_do_dia(
    p_tenant_id,
    regexp_replace(pd.colaborador_cpf,'[^0-9]','','g'),
    pd.colaborador_id::text,
    pd.data) j
  WHERE COALESCE(j.jornada_min,0) > 0                       -- valida a escala (sem fim de semana)
    AND public.ponto_vinculo_cobre_periodo(                 -- não traz desligado após a data
          p_tenant_id,
          regexp_replace(pd.colaborador_cpf,'[^0-9]','','g'),
          pd.data, pd.data)
  ORDER BY pd.data DESC, pd.colaborador_nome;
$function$;

COMMENT ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) IS
  'Faltas reais do mês para a tela de Compensação de Faltas: só dias com jornada prevista (valida a escala — sem sábado/domingo neutro) e dentro do vínculo (desligado só até a data_desligamento).';

REVOKE ALL ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ponto_faltas_do_mes(uuid, uuid, text) TO authenticated;

-- Conferência (o editor mostra só o último resultado): tudo no lugar? (espera t)
SELECT
  to_regprocedure('public.ponto_vinculo_cobre_periodo(uuid,text,date,date)') IS NOT NULL AS regra_vinculo_ok,
  to_regprocedure('public.ponto_faltas_do_mes(uuid,uuid,text)') IS NOT NULL AS faltas_do_mes_ok,
  position('[lista-respeita-vinculo]' IN pg_get_functiondef('public.ponto_espelho_resumo_empresa(uuid,uuid,text)'::regprocedure)) > 0 AS fechamento_ok,
  position('[lista-respeita-vinculo]' IN pg_get_functiondef('public.ponto_banco_horas_oficial(uuid,text,uuid,text)'::regprocedure)) > 0 AS banco_ok,
  position('[lista-respeita-vinculo]' IN pg_get_functiondef('public.consolidar_ponto_dia_todos(uuid,date)'::regprocedure)) > 0 AS materializacao_ok;
