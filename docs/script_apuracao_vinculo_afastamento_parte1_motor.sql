-- ============================================================================
-- ENTREGA PARTE 1/2 — MOTOR da apuração respeita vínculo e afastamento
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- O QUE FAZ (só MECANISMO — NÃO altera nenhum dado, não reapura nada):
--   A) [vinculo-corte]  a apuração deixa de gerar dia "sintético" (débito de
--      jornada inteira, sem marcação) fora do vínculo: nada antes da admissão
--      nem depois do desligamento (mantendo o dia da admissão e o do
--      desligamento — cobre o aviso prévio trabalhado). Filtra por VÍNCULO
--      (dois contratos somam janelas); sem admissão efetivada, não muda nada.
--   B) [afast-protege]  dia dentro do período de um afastamento (por intervalo
--      de datas: ativo/encerrado/benefício) fica protegido (saldo 0), sem
--      depender de linha no espelho. Fronteira (início/fim) COM marcação apura
--      normal. O tipo do afastamento segue disponível para a folha.
--   C) gatilho que fecha a atribuição de escala no desligamento (para os
--      PRÓXIMOS desligamentos). O fechamento retroativo dos já-desligados vai
--      na PARTE 2 (que guarda as linhas antes de alterar).
--
-- SEGURANÇA: só redefine funções e cria um gatilho. Não cria tabela, não
-- escreve dado. Idempotente (rodar de novo diz "nada a fazer"). A reapuração
-- auditável dos meses fechados é etapa à parte.
-- ============================================================================

-- A + B) Motor: corte por vínculo + proteção por afastamento
DO $item$
DECLARE
  v_nome text;
  v_src  text;
  v_novo text;
  v_achou boolean := false;
  v_ja_alvo text;
  v_ja_troca text;
  v_prot_alvo text;
  v_prot_troca text;
BEGIN
  v_ja_alvo := E'    v_ja_emitiu := v_ja_emitiu || r.data;';

  v_ja_troca := v_ja_alvo || E'\n'
    || E'\n'
    || E'    -- [vinculo-corte] So apura dias dentro de um vinculo de emprego real.\n'
    || E'    -- Se o CPF tem admissao efetivada (concluido/desligado) e NENHUMA cobre\n'
    || E'    -- este dia pelo intervalo [data_admissao, COALESCE(data_desligamento,\n'
    || E'    -- ''infinity'')], o dia esta fora de contrato (antes de admitir, ou depois\n'
    || E'    -- de desligar, incluindo aviso previo trabalhado) e nao gera saldo. Mantem\n'
    || E'    -- o dia da admissao e o do desligamento (corte estritamente APOS). Filtra\n'
    || E'    -- por VINCULO, nao por pessoa: dois vinculos = uniao das janelas; sem\n'
    || E'    -- nenhuma admissao efetivada, nao corta nada (preserva o anterior).\n'
    || E'    IF EXISTS (\n'
    || E'      SELECT 1 FROM public.admissoes adm\n'
    || E'      WHERE adm.tenant_id = p_tenant_id\n'
    || E'        AND regexp_replace(COALESCE(adm.cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'        AND adm.data_admissao IS NOT NULL\n'
    || E'        AND adm.status::text IN (''concluido'', ''desligado'')\n'
    || E'    ) AND NOT EXISTS (\n'
    || E'      SELECT 1 FROM public.admissoes adm\n'
    || E'      WHERE adm.tenant_id = p_tenant_id\n'
    || E'        AND regexp_replace(COALESCE(adm.cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'        AND adm.data_admissao IS NOT NULL\n'
    || E'        AND adm.status::text IN (''concluido'', ''desligado'')\n'
    || E'        AND adm.data_admissao <= r.data\n'
    || E'        AND COALESCE(adm.data_desligamento, ''infinity''::date) >= r.data\n'
    || E'    ) THEN\n'
    || E'      CONTINUE;\n'
    || E'    END IF;';

  v_prot_alvo := E'    v_prot_credito := v_protegido';

  v_prot_troca :=
       E'    -- [afast-protege] Dia dentro do periodo de um afastamento (por intervalo\n'
    || E'    -- de datas, nao por status): protege o dia para nao virar debito enquanto\n'
    || E'    -- o colaborador esta afastado. Vale para qualquer afastamento registrado\n'
    || E'    -- (ativo, encerrado, beneficio_inss) — o proprio registro delimita o\n'
    || E'    -- periodo por data_inicio/data_fim; data_fim nula protege de data_inicio em\n'
    || E'    -- diante. EXCECAO (art. 60 CLT / operacao): dia de FRONTEIRA (= data_inicio\n'
    || E'    -- ou = data_fim) COM marcacao apura normal — meio periodo trabalha, meio\n'
    || E'    -- afasta. O tipo do afastamento segue disponivel para a folha (esta funcao\n'
    || E'    -- nao apaga nada; so deixa de debitar).\n'
    || E'    -- v_protegido pode vir NULL (dia sintetico: r.status NULL => a\n'
    || E'    -- expressao acima resolve NULL), por isso o COALESCE.\n'
    || E'    IF NOT COALESCE(v_protegido, false) THEN\n'
    || E'      v_protegido := EXISTS (\n'
    || E'        SELECT 1 FROM public.afastamentos af\n'
    || E'        WHERE af.tenant_id = p_tenant_id\n'
    || E'          AND regexp_replace(COALESCE(af.colaborador_cpf, ''''), ''[^0-9]'', '''', ''g'') = v_cpf\n'
    || E'          AND af.data_inicio IS NOT NULL\n'
    || E'          AND af.data_inicio <= r.data\n'
    || E'          AND COALESCE(af.data_fim, ''infinity''::date) >= r.data\n'
    || E'          AND NOT (\n'
    || E'            (r.data = af.data_inicio OR (af.data_fim IS NOT NULL AND r.data = af.data_fim))\n'
    || E'            AND (\n'
    || E'              r.entrada IS NOT NULL OR r.saida IS NOT NULL\n'
    || E'              OR COALESCE(floor(EXTRACT(EPOCH FROM r.horas_trabalhadas)/60)::int, 0) > 0\n'
    || E'            )\n'
    || E'          )\n'
    || E'      );\n'
    || E'    END IF;\n'
    || E'\n'
    || v_prot_alvo;

  FOREACH v_nome IN ARRAY ARRAY['ponto_saldo_dias_competencia_bruto',
                                'ponto_saldo_dias_competencia'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_nome
      AND pg_get_function_identity_arguments(p.oid)
          = 'p_tenant_id uuid, p_colaborador_cpf text, p_competencia text'
    LIMIT 1;

    IF v_src IS NULL OR position('v_tol_bat' IN v_src) = 0 THEN
      CONTINUE;
    END IF;

    IF position('[vinculo-corte]' IN v_src) > 0
       AND position('[afast-protege]' IN v_src) > 0 THEN
      RAISE NOTICE '% ja corta fora do vinculo e protege dia de afastamento — nada a fazer.', v_nome;
      v_achou := true;
      CONTINUE;
    END IF;

    IF position(v_ja_alvo IN v_src) = 0 OR position(v_prot_alvo IN v_src) = 0 THEN
      RAISE NOTICE 'ATENCAO: em % as ancoras esperadas nao foram encontradas. Corpo divergente; NADA alterado.', v_nome;
      CONTINUE;
    END IF;

    v_novo := replace(v_src, v_ja_alvo, v_ja_troca);
    v_novo := replace(v_novo, v_prot_alvo, v_prot_troca);
    EXECUTE v_novo;
    v_achou := true;
    RAISE NOTICE 'Em %: dia fora do vinculo nao debita e dia de afastamento fica protegido.', v_nome;
  END LOOP;

  IF NOT v_achou THEN
    RAISE NOTICE 'A apuracao de saldo nao foi encontrada nesta base — nada a corrigir.';
  END IF;
END $item$;

-- C) Gatilho: fecha a atribuicao de escala nos PROXIMOS desligamentos
CREATE OR REPLACE FUNCTION public.admissao_fecha_escala_desligamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cpf text := regexp_replace(COALESCE(NEW.cpf, ''), '[^0-9]', '', 'g');
BEGIN
  IF NEW.data_desligamento IS NOT NULL AND v_cpf <> '' THEN
    UPDATE public.ponto_escala_atribuicoes
       SET data_fim = NEW.data_desligamento
     WHERE tenant_id = NEW.tenant_id
       AND regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf
       AND data_inicio <= NEW.data_desligamento
       AND (data_fim IS NULL OR data_fim > NEW.data_desligamento);
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_admissao_fecha_escala_desligamento ON public.admissoes;
CREATE TRIGGER trg_admissao_fecha_escala_desligamento
AFTER UPDATE OF data_desligamento, status ON public.admissoes
FOR EACH ROW EXECUTE FUNCTION public.admissao_fecha_escala_desligamento();

-- Conferencia (o editor mostra so o ultimo resultado): confirma que as duas
-- marcas do motor estao no corpo e que o gatilho existe.
SELECT
  (SELECT bool_and(position('[vinculo-corte]' IN pg_get_functiondef(p.oid)) > 0
                   AND position('[afast-protege]' IN pg_get_functiondef(p.oid)) > 0)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia_bruto'
  ) AS motor_ok,
  EXISTS (SELECT 1 FROM pg_trigger
           WHERE tgname = 'trg_admissao_fecha_escala_desligamento') AS gatilho_ok;
