-- ============================================================================
-- Ponto — Apuração › Comp. Faltas: visibilidade das AUSÊNCIAS PARCIAIS do mês
-- ----------------------------------------------------------------------------
-- CONTEXTO
-- A aba "Comp. Faltas" lista hoje só as FALTAS de dia inteiro (fonte
-- public.ponto_faltas_do_mes). Falta a contrapartida: as AUSÊNCIAS PARCIAIS —
-- dias TRABALHADOS com déficit de minutos (atraso / saída antecipada). Quem tem
-- regime de banco de horas vigente já teve esse déficit debitado AUTOMATICAMENTE
-- no banco (apurar_banco_horas_colaborador); quem não tem, o déficit vai para a
-- folha (CLT art. 59, §§2º/5º). Esta migration só ADICIONA VISIBILIDADE
-- (read-only): não cria compensação, não escreve nada em runtime.
--
-- O QUE FAZ (aditivo, uma função NOVA)
--   public.ponto_ausencias_parciais_do_mes(tenant, empresa, competencia) —
--   lista, por colaborador/dia, as ausências parciais do mês, com os minutos
--   devedores e se foram para o banco ou para a folha.
--
-- DE ONDE VÊM OS NÚMEROS (reúso — nada é recalculado à mão)
--   · déficit diário (já com tolerância de marcação): a função pega o saldo
--     diário de public.ponto_saldo_dias_competencia e filtra os dias com saldo
--     NEGATIVO; NÃO reconstrói a fórmula de tolerância/déficit.
--   · escala e vínculo: mesma validação de public.ponto_faltas_do_mes —
--     ponto_jornada_do_dia (só dia com jornada prevista) e
--     ponto_vinculo_cobre_periodo (não traz desligado após a data), além do
--     filtro (p_empresa_id IS NULL OR empresa_id = p_empresa_id).
--   · foi pro banco? a MESMA checagem que o banco oficial usa para decidir se o
--     déficit vira saldo: public.ponto_banco_regime_vigente(...).id IS NOT NULL,
--     avaliada no FIM da competência (v_fim) — exatamente como
--     apurar_banco_horas_colaborador e ponto_banco_horas_oficial fazem, para que
--     no_banco concorde com o que o dinheiro de fato fez.
--
-- NOTA DE PROJETO — status do dia
--   ponto_saldo_dias_competencia NÃO retorna o status do dia (seu RETURNS é
--   dia/entrada/saida/trabalhado_min/jornada_min/saldo_min/protegido/
--   equalizacao/excedente_retido_min). Por isso o status vem de ponto_diario
--   (coluna status), lido pelo mesmo dia. O filtro exclui dia cheio ('falta',
--   que já aparece em ponto_faltas_do_mes), 'justificado' e 'incompleto'
--   (marcação pendente, sem déficit confiável), e também protegido=true
--   (férias/atestado/afastamento/feriado) e equalizacao=true (débito de
--   equalização mensal, que não é atraso/saída antecipada de um dia).
-- ============================================================================

-- ---------------------------------------------------------------------
-- 1) A fonte read-only da listagem de ausências parciais
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_ausencias_parciais_do_mes(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_competencia text
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  colaborador_id uuid,
  data date,
  minutos_deficit integer,
  no_banco boolean,
  status_dia text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH janela AS (
    SELECT to_date(p_competencia || '-01','YYYY-MM-DD') AS ini,
           (to_date(p_competencia || '-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date AS fim
  ),
  colabs AS (
    -- Um CPF (só dígitos) por colaborador com ao menos um dia no mês, dentro
    -- da empresa pedida. É sobre este conjunto que o saldo diário é somado.
    SELECT DISTINCT regexp_replace(pd.colaborador_cpf,'[^0-9]','','g') AS cpf_num
    FROM janela w
    JOIN public.ponto_diario pd
      ON pd.tenant_id = p_tenant_id
     AND pd.data BETWEEN w.ini AND w.fim
     AND COALESCE(pd.colaborador_cpf,'') <> ''
     AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id)
  )
  SELECT
    c.cpf_num AS colaborador_cpf,
    pdd.colaborador_nome,
    pdd.colaborador_id,
    s.dia AS data,
    (-s.saldo_min)::integer AS minutos_deficit,                 -- valor POSITIVO devedor
    (public.ponto_banco_regime_vigente(                         -- a MESMA checagem do banco oficial
        p_tenant_id, c.cpf_num, pdd.colaborador_id::text, w.fim)).id IS NOT NULL AS no_banco,
    pdd.status AS status_dia
  FROM janela w
  CROSS JOIN colabs c
  -- Saldo diário canônico (com tolerância de marcação). NÃO reconstruir a fórmula.
  CROSS JOIN LATERAL public.ponto_saldo_dias_competencia(p_tenant_id, c.cpf_num, p_competencia) s
  -- O dia real no ponto_diario (status, nome, id). O INNER LATERAL garante que
  -- só entram dias com registro de ponto (exclui dias-fantasma de vínculo/
  -- equalização que o saldo gera sem linha em ponto_diario).
  CROSS JOIN LATERAL (
    SELECT pd2.colaborador_nome, pd2.colaborador_id, pd2.status, pd2.empresa_id
    FROM public.ponto_diario pd2
    WHERE pd2.tenant_id = p_tenant_id
      AND regexp_replace(pd2.colaborador_cpf,'[^0-9]','','g') = c.cpf_num
      AND pd2.data = s.dia
    ORDER BY COALESCE(floor(EXTRACT(EPOCH FROM pd2.horas_trabalhadas)/60)::int,0) DESC,
             pd2.updated_at DESC NULLS LAST
    LIMIT 1
  ) pdd
  -- Valida a escala: só dia com jornada prevista (sem sábado/domingo neutro).
  CROSS JOIN LATERAL public.ponto_jornada_do_dia(
    p_tenant_id, c.cpf_num, pdd.colaborador_id::text, s.dia) j
  WHERE s.saldo_min < 0                                         -- há déficit de minutos no dia
    AND COALESCE(s.protegido,false) = false                     -- não é férias/atestado/afastamento/feriado/justificado
    AND COALESCE(s.equalizacao,false) = false                   -- não é o débito de equalização mensal
    AND COALESCE(pdd.status,'') NOT IN ('falta','justificado','incompleto')  -- dia TRABALHADO (exclui dia cheio)
    AND (p_empresa_id IS NULL OR pdd.empresa_id = p_empresa_id)
    AND COALESCE(j.jornada_min,0) > 0                           -- valida a escala
    AND public.ponto_vinculo_cobre_periodo(                     -- não traz desligado após a data
          p_tenant_id, c.cpf_num, s.dia, s.dia)
  ORDER BY s.dia DESC, pdd.colaborador_nome;
$function$;

COMMENT ON FUNCTION public.ponto_ausencias_parciais_do_mes(uuid, uuid, text) IS
  'Somente leitura (visibilidade da aba Comp. Faltas): ausencias PARCIAIS do mes (dias TRABALHADOS com deficit, atraso/saida antecipada), por colaborador/dia. minutos_deficit = valor positivo devedor. no_banco = true quando ha regime de banco vigente (o deficit foi debitado automaticamente no banco); false = foi para a folha (CLT art. 59). Reusa ponto_saldo_dias_competencia (deficit com tolerancia), ponto_jornada_do_dia + ponto_vinculo_cobre_periodo (escala/vinculo, iguais a ponto_faltas_do_mes) e ponto_banco_regime_vigente (a mesma checagem do banco oficial). Exclui dia cheio (falta), justificado, incompleto, protegido e o dia de equalizacao.';

REVOKE ALL ON FUNCTION public.ponto_ausencias_parciais_do_mes(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ponto_ausencias_parciais_do_mes(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 2) QA PONTO-TELA-20 — a lista mostra as ausências parciais já debitadas
--    no banco (documentação e2e; sem it() automatizado, depende de seed)
-- ---------------------------------------------------------------------
DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo jornada-rotina/ponto ausente; PONTO-TELA-20 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PONTO-TELA-20',
   'Comp. Faltas lista as ausências parciais do mês já debitadas no banco',
   'feliz', 'media', 'aprovado', 'e2e',
   'CLT art. 59, §2º (banco de horas): o déficit parcial de um dia trabalhado (atraso/saída '
   || 'antecipada) com regime de compensação vigente é debitado no banco; sem regime vigente vai '
   || 'para a folha (art. 59, §§2º/5º). Débito parcial NÃO é falta de dia inteiro, logo não perde '
   || 'o DSR (Lei 605/49): é só visibilidade do que já foi apurado, não cria compensação nova.',
   'Mostrar, na aba Ponto › Apuração › Comp. Faltas, uma listagem read-only das ausências '
   || 'PARCIAIS do mês (dias trabalhados com déficit de minutos), com quantos minutos foram '
   || 'debitados automaticamente no banco, separando o que foi para o banco (regime vigente) do '
   || 'que foi para a folha. É só visibilidade: não escreve nada e não cria compensação.',
   'Competência com um colaborador que, num dia útil da escala, trabalhou menos que a jornada '
   || '(atraso ou saída antecipada), além da tolerância; regime de banco de horas vigente para '
   || 'esse vínculo.',
   '[{"ordem":1,"acao":"Abrir Ponto > Apuração > Comp. Faltas na competência do déficit parcial","resultado_esperado":"Além das faltas de dia inteiro, aparece a seção de ausências parciais com o dia, os minutos devedores e a marca de que foi para o banco"},
     {"ordem":2,"acao":"Conferir um colaborador SEM regime de banco vigente no mesmo mês","resultado_esperado":"A ausência parcial dele aparece marcada como folha (no_banco = falso), porque sem regime o déficit é devido em dinheiro"},
     {"ordem":3,"acao":"Conferir uma falta de dia inteiro e um dia justificado","resultado_esperado":"Nenhum dos dois entra na listagem de parciais (dia cheio já está na lista de faltas; justificado e protegido não geram déficit)"}]'::jsonb,
   'A listagem traz só dias trabalhados com déficit (atraso/saída antecipada), com minutos_deficit '
   || 'positivo e no_banco indicando banco x folha; dia cheio (falta), justificado, incompleto, '
   || 'protegido e o dia de equalização ficam de fora; respeita escala e vínculo (não traz '
   || 'desligado após a data).',
   'Fonte: public.ponto_ausencias_parciais_do_mes(tenant, empresa, competencia). Read-only, reúsa '
   || 'ponto_saldo_dias_competencia (déficit), ponto_jornada_do_dia + ponto_vinculo_cobre_periodo '
   || '(escala/vínculo) e ponto_banco_regime_vigente (banco x folha). Sem it() automatizado ainda '
   || '(depende de seed no staging).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'PONTO-TELA-20 documentado (e2e): ausências parciais do mês na Comp. Faltas.';
END
$doc$;

DO $fim$
BEGIN
  RAISE NOTICE 'ponto_ausencias_parciais_do_mes criada (read-only): visibilidade das ausencias parciais ja debitadas no banco.';
END
$fim$;
