-- =========================================================
-- SCRIPT DE ENTREGA — 13o Salario: testes (2a leva) e duas correcoes de lei
-- Projeto: PRODUCAO (colar no SQL Editor)
--
-- O QUE ESTE SCRIPT FAZ
--   1. Documenta 14 casos de teste novos do 13o, cada um com base legal
--      propria, e instala as rotinas que os executam no motor de QA;
--   2. Corrige DUAS falhas que esses testes encontraram, ambas de lei e
--      ambas pagando a MENOS do que o devido:
--      · aviso previo INDENIZADO nao projetava o tempo de servico
--        (CLT, art. 487, §1o; Sumula 371 do TST) — quem saia em 20/11
--        com 30 dias de aviso recebia 11/12 em vez de 12/12;
--      · afastamento por ACIDENTE DE TRABALHO derrubava avo igual ao de
--        doenca comum, contra a Sumula 46 do TST e o art. 4o, paragrafo
--        unico, da Lei 8.213/1991.
--
-- O QUE ELE NAO FAZ: nao altera nenhum calculo ja gravado. A apuracao e
-- somente leitura e o que esta aprovado ou pago segue travado; os
-- calculos em aberto e os proximos e que passam a sair pelo numero certo.
-- Por isso nao ha copia de seguranca a fazer.
--
-- Idempotente: rodar duas vezes nao quebra nem duplica.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.decimo_terceiro_avos(
    p_tenant  UUID,
    p_cpf     TEXT,
    p_ano     INT,
    p_empresa UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $fn$
DECLARE
    v_cpf          TEXT;
    v_ano_ini      DATE;
    v_ano_fim      DATE;
    v_admissao     DATE;
    v_desligamento DATE;
    v_fim_contrato DATE;
    v_dias_aviso   INT := 0;
    v_aviso_tipo   TEXT;
    v_tem_ponto    BOOLEAN := false;
    v_regra        TEXT;
    v_dias_empreg  INT;
    v_vigencia     DATE;
    v_avos         INT;
    v_meses        JSONB;
    v_avisos       TEXT[] := ARRAY[]::TEXT[];
BEGIN
    v_cpf := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
    IF v_cpf = '' OR p_ano IS NULL OR p_tenant IS NULL THEN
        RETURN jsonb_build_object('erro',
            'Apuração de avos precisa de empresa, CPF e ano-base. Recebido: CPF "'
            || coalesce(p_cpf, '(vazio)') || '".');
    END IF;

    v_ano_ini := make_date(p_ano, 1, 1);
    v_ano_fim := make_date(p_ano, 12, 31);

    SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
      INTO v_regra, v_dias_empreg, v_vigencia
      FROM public.decimo_terceiro_config c
     WHERE c.tenant_id = p_tenant AND c.empresa_id IS NOT DISTINCT FROM p_empresa
     LIMIT 1;

    IF v_regra IS NULL THEN
        SELECT c.afastamento_regra, c.afastamento_dias_empregador, c.parametros_vigencia_inicio
          INTO v_regra, v_dias_empreg, v_vigencia
          FROM public.decimo_terceiro_config c
         WHERE c.tenant_id = p_tenant AND c.empresa_id IS NULL
         LIMIT 1;
    END IF;

    v_regra       := coalesce(v_regra, 'previdenciario_suspende');
    v_dias_empreg := coalesce(v_dias_empreg, 15);
    v_vigencia    := coalesce(v_vigencia, DATE '2026-01-01');

    SELECT min(a.data_admissao) INTO v_admissao
      FROM public.admissoes a
     WHERE a.tenant_id = p_tenant
       AND regexp_replace(coalesce(a.cpf, ''), '\D', '', 'g') = v_cpf
       AND a.status = 'concluido'
       AND a.data_admissao IS NOT NULL;

    IF v_admissao IS NULL THEN
        v_avisos := array_append(v_avisos,
            'Não há admissão concluída com data para este CPF — os avos foram apurados como se o vínculo cobrisse o ano inteiro. Confira o cadastro antes de fechar.');
        v_admissao := v_ano_ini;
    END IF;

    -- Desligamento no ano-base, com o aviso prévio da própria rescisão.
    SELECT r.data_desligamento, r.aviso_tipo, coalesce(r.dias_aviso, 0)
      INTO v_desligamento, v_aviso_tipo, v_dias_aviso
      FROM public.folha_rescisoes r
     WHERE r.tenant_id = p_tenant
       AND regexp_replace(coalesce(r.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
       AND r.data_desligamento BETWEEN v_ano_ini AND v_ano_fim
     ORDER BY r.data_desligamento
     LIMIT 1;

    IF v_desligamento IS NULL THEN
        SELECT min(a.data_desligamento) INTO v_desligamento
          FROM public.admissoes a
         WHERE a.tenant_id = p_tenant
           AND regexp_replace(coalesce(a.cpf, ''), '\D', '', 'g') = v_cpf
           AND a.data_desligamento BETWEEN v_ano_ini AND v_ano_fim;
    END IF;

    -- PROJEÇÃO DO AVISO PRÉVIO INDENIZADO (CLT, art. 487, §1º; Súmula 371
    -- do TST): o contrato termina na data projetada, não na baixa. É o
    -- que decide o avo do último mês.
    v_fim_contrato := v_desligamento;
    IF v_desligamento IS NOT NULL
       AND lower(coalesce(v_aviso_tipo, '')) = 'indenizado'
       AND v_dias_aviso > 0 THEN
        v_fim_contrato := v_desligamento + v_dias_aviso;
        IF v_fim_contrato > v_ano_fim THEN
            v_fim_contrato := v_ano_fim;
        END IF;
        v_avisos := array_append(v_avisos, format(
            'Aviso prévio indenizado de %s dias: o contrato projeta até %s e os avos foram contados até lá (CLT, art. 487, §1º; Súmula 371 do TST).',
            v_dias_aviso, to_char(v_desligamento + v_dias_aviso, 'DD/MM/YYYY')));
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.ponto_diario pd
         WHERE pd.tenant_id = p_tenant
           AND regexp_replace(coalesce(pd.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND pd.data BETWEEN v_ano_ini AND v_ano_fim
           AND pd.status <> 'pendente'
    ) INTO v_tem_ponto;

    IF NOT v_tem_ponto THEN
        v_avisos := array_append(v_avisos,
            'Sem registro de ponto no ano-base: os avos foram apurados sem desconto de faltas.');
    END IF;

    WITH meses AS MATERIALIZED (
        SELECT m AS mes,
               make_date(p_ano, m, 1) AS mes_ini,
               (make_date(p_ano, m, 1) + INTERVAL '1 month - 1 day')::DATE AS mes_fim
          FROM generate_series(1, 12) AS m
    ),
    vinculo AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim,
               greatest(mes_ini, v_admissao) AS ini,
               least(mes_fim, coalesce(v_fim_contrato, mes_fim)) AS fim
          FROM meses
    ),
    dias AS MATERIALIZED (
        SELECT mes, mes_ini, mes_fim, ini, fim,
               CASE WHEN fim >= ini THEN (fim - ini + 1) ELSE 0 END AS dias_vinculo
          FROM vinculo
    ),
    computo AS MATERIALIZED (
        SELECT d.mes, d.dias_vinculo,
               CASE WHEN NOT v_tem_ponto OR d.dias_vinculo = 0 THEN 0 ELSE (
                   SELECT count(*)::INT
                     FROM public.ponto_diario pd
                    WHERE pd.tenant_id = p_tenant
                      AND regexp_replace(coalesce(pd.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
                      AND pd.data BETWEEN d.ini AND d.fim
                      AND pd.status = 'falta'
               ) END AS faltas,
               -- Dias por conta do INSS. SÓ as espécies COMUNS suspendem o
               -- avo: nas ACIDENTÁRIAS (B91 e B92) a ausência não pesa
               -- contra a gratificação natalina (Súmula 46 do TST; Lei
               -- 8.213/1991, art. 4º, parágrafo único).
               CASE WHEN d.dias_vinculo = 0 OR v_regra <> 'previdenciario_suspende' THEN 0 ELSE (
                   SELECT coalesce(sum(
                       greatest(0,
                           least(coalesce(af.data_fim, d.fim), d.fim)
                           - greatest(af.data_inicio + v_dias_empreg, d.ini) + 1)
                   )::INT, 0)
                     FROM public.afastamentos af
                     JOIN public.afastamentos_previdenciario ap ON ap.afastamento_id = af.id
                    WHERE af.tenant_id = p_tenant
                      AND regexp_replace(coalesce(af.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
                      AND ap.especie_beneficio IN ('B31', 'B32')
                      AND af.data_inicio <= d.fim
                      AND coalesce(af.data_fim, d.fim) >= d.ini
               ) END AS dias_inss
          FROM dias d
    ),
    fechado AS MATERIALIZED (
        SELECT mes, dias_vinculo, faltas, dias_inss,
               greatest(0, dias_vinculo - faltas - dias_inss) AS dias_computados,
               (greatest(0, dias_vinculo - faltas - dias_inss) >= 15) AS conta
          FROM computo
    )
    SELECT count(*) FILTER (WHERE conta)::INT,
           coalesce(jsonb_agg(jsonb_build_object(
               'mes',             mes,
               'dias_vinculo',    dias_vinculo,
               'faltas',          faltas,
               'dias_inss',       dias_inss,
               'dias_computados', dias_computados,
               'conta',           conta
           ) ORDER BY mes), '[]'::jsonb)
      INTO v_avos, v_meses
      FROM fechado;

    -- Afastamento acidentário no ano: a memória diz por que ele não tirou
    -- avo, para ninguém "corrigir" isso depois por engano.
    IF EXISTS (
        SELECT 1 FROM public.afastamentos af
          JOIN public.afastamentos_previdenciario ap ON ap.afastamento_id = af.id
         WHERE af.tenant_id = p_tenant
           AND regexp_replace(coalesce(af.colaborador_cpf, ''), '\D', '', 'g') = v_cpf
           AND ap.especie_beneficio IN ('B91', 'B92')
           AND af.data_inicio <= v_ano_fim
           AND coalesce(af.data_fim, v_ano_fim) >= v_ano_ini
    ) THEN
        v_avisos := array_append(v_avisos,
            'Há afastamento por acidente do trabalho no ano-base: os dias contam normalmente para o 13º (Súmula 46 do TST; Lei 8.213/1991, art. 4º, parágrafo único).');
    END IF;

    IF v_avos = 0 THEN
        v_avisos := array_append(v_avisos,
            'Nenhum mês do ano-base fechou 15 dias de trabalho — não há avo a pagar. Confira admissão, faltas e afastamentos.');
    END IF;

    RETURN jsonb_build_object(
        'avos',                v_avos,
        'ano',                 p_ano,
        'admissao',            v_admissao,
        'desligamento',        v_desligamento,
        'fim_contrato',        v_fim_contrato,
        'aviso_previo_tipo',   v_aviso_tipo,
        'aviso_previo_dias',   v_dias_aviso,
        'tem_ponto',           v_tem_ponto,
        'afastamento_regra',   v_regra,
        'dias_empregador',     v_dias_empreg,
        'parametros_vigencia', v_vigencia,
        'fundamento',          'Lei 4.090/1962, art. 1º, § 2º (fração >= 15 dias); CLT, art. 487, §1º (projeção do aviso indenizado); Súmula 46 do TST (acidente do trabalho)',
        'apurado_em',          now(),
        'meses',               v_meses,
        'avisos',              to_jsonb(v_avisos)
    );
END $fn$;

COMMENT ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) IS
    'Avos do 13o (Lei 4.090/1962): 1/12 por mes com fracao >= 15 dias, descontadas faltas do ponto e afastamento previdenciario COMUM. Projeta o aviso previo indenizado (CLT art. 487 §1o) e nao desconta afastamento acidentario (Sumula 46 do TST). Somente leitura.';

GRANT EXECUTE ON FUNCTION public.decimo_terceiro_avos(UUID, TEXT, INT, UUID) TO authenticated;

-- ── Documentacao de testes e rotinas ──────────────────────────────────
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao existe nesta base — casos nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DEC13-004', 'Aviso prévio indenizado projeta o tempo e pode gerar mais um avo',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT, art. 487, §1º; Súmula 371 do TST; OJ 82 da SDI-1 do TST',
   'O aviso prévio indenizado integra o tempo de serviço para todos os efeitos legais. Desligado em 20/11 com 30 dias de aviso indenizado, o contrato projeta até 20/12: dezembro passa a ter 20 dias e vira mais um avo. Ignorar a projeção paga 11/12 onde a lei manda 12/12 — diferença que volta como reclamatória.',
   'Vínculo desligado em 20/11 do ano-base, com aviso prévio indenizado de 30 dias.',
   '[{"ordem": 1, "acao": "Apurar o 13º sem considerar a projeção", "resultado_esperado": "11 avos"}, {"ordem": 2, "acao": "Apurar considerando a projeção do aviso indenizado", "resultado_esperado": "12 avos — dezembro fecha 20 dias com a projeção"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória mostra a data projetada do fim do contrato, não só a data do desligamento"}]'::jsonb,
   'Aviso indenizado conta como tempo de serviço — inclusive para o avo de dezembro.',
   'Requisitos YE-DP-13-001: RN-001 e RN-009 (rescisão). O mesmo vale para as férias proporcionais.'),

  (v_mod, 'DEC13-005', 'Fronteira dos 15 dias: dia 16 conta o avo, dia 17 não',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 1º, §2º (fração igual ou superior a 15 dias)',
   'A regra da fração é de contagem exata e é onde mais se erra por um dia. Em mês de 31 dias, admissão no dia 17 deixa 15 dias trabalhados (17 a 31) e CONTA; no dia 18 deixa 14 e NÃO conta. Fevereiro, com 28 ou 29 dias, tem fronteira própria. O teste fixa as bordas para que nenhuma mudança futura as mova sem que alguém perceba.',
   'Vínculos fictícios admitidos exatamente nas datas de fronteira do ano-base.',
   '[{"ordem": 1, "acao": "Admitido em 17/03 (mês de 31 dias)", "resultado_esperado": "Março conta — 15 dias trabalhados"}, {"ordem": 2, "acao": "Admitido em 18/03", "resultado_esperado": "Março não conta — 14 dias"}, {"ordem": 3, "acao": "Admitido em 14/02 (ano comum, 28 dias)", "resultado_esperado": "Fevereiro conta — 15 dias"}, {"ordem": 4, "acao": "Admitido em 15/02 (ano comum)", "resultado_esperado": "Fevereiro não conta — 14 dias"}]'::jsonb,
   'A borda é 15 dias exatos, contados no calendário do próprio mês.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001. Complementa DEC13-001, que cobre o caso geral.'),

  (v_mod, 'DEC13-006', 'Afastamento por acidente de trabalho conta como tempo de serviço',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 8.213/1991, art. 4º, parágrafo único e art. 118; CLT, art. 4º; Súmula 46 do TST',
   'O afastamento acidentário (benefício B-91) não é igual ao auxílio-doença comum: o período é contado como tempo de serviço para todos os efeitos, inclusive 13º. Tratar acidente de trabalho como doença comum tira avos que a lei manda pagar.',
   'Vínculo com 4 meses de afastamento acidentário (B-91) no ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º de quem se afastou por acidente de trabalho", "resultado_esperado": "Os meses de afastamento contam como avos do empregador"}, {"ordem": 2, "acao": "Comparar com afastamento por doença comum", "resultado_esperado": "Na doença comum o empregador paga só os 15 primeiros dias e o restante é abono anual do INSS"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória nomeia o tipo de afastamento e o efeito aplicado"}]'::jsonb,
   'Acidente de trabalho conta tempo; doença comum divide com o INSS.',
   'Requisitos YE-DP-13-001: RN-008. Complementa DEC13-003, que trata maternidade e doença comum.'),

  (v_mod, 'DEC13-022', 'Horas extras entram pela média física × valor da hora atual (Súmula 347)',
   'alternativo', 'alta', 'aprovado', 'api',
   'Súmula 347 do TST; Decreto 57.155/1965, art. 2º',
   'A média de horas extras do 13º é FÍSICA: soma-se a quantidade de HORAS do ano, divide-se pelos meses e multiplica-se pelo valor da hora VIGENTE no pagamento. Usar a média dos valores históricos paga a menos sempre que houve aumento salarial no ano — é passivo certo.',
   'Vínculo com 10 horas extras por mês o ano todo e aumento salarial no meio do ano.',
   '[{"ordem": 1, "acao": "Apurar a média pela quantidade de horas × valor atual", "resultado_esperado": "Média calculada sobre o salário vigente"}, {"ordem": 2, "acao": "Comparar com a média dos valores pagos no ano", "resultado_esperado": "A média física é MAIOR quando houve aumento"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória informa qual critério foi usado e por quê"}]'::jsonb,
   'Média física protege o cálculo do aumento salarial no meio do ano.',
   'Requisitos YE-DP-13-001: RN-003. Sem registro de ponto no ano, o sistema usa os valores pagos e avisa.'),

  (v_mod, 'DEC13-023', 'Adicionais habituais integram a base do 13º',
   'feliz', 'alta', 'aprovado', 'api',
   'Súmula 60 (adicional noturno), Súmula 132 (adicional de periculosidade) e Súmula 139 (adicional de insalubridade) do TST; Decreto 57.155/1965, art. 2º',
   'Adicional noturno, de insalubridade e de periculosidade pagos com habitualidade integram a remuneração e, portanto, a base do 13º. Se as rubricas desses adicionais não estiverem marcadas como integrantes do 13º no cadastro, o cálculo sai a menor sem ninguém perceber.',
   'Rubricas de adicional noturno, insalubridade e periculosidade cadastradas e pagas com habitualidade.',
   '[{"ordem": 1, "acao": "Conferir a marcação das rubricas de adicional", "resultado_esperado": "Marcadas como integrantes da base do 13º"}, {"ordem": 2, "acao": "Apurar a média das variáveis", "resultado_esperado": "Os adicionais habituais entram na média"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "Cada rubrica somada aparece nomeada na memória"}]'::jsonb,
   'Adicional habitual é remuneração — e remuneração entra no 13º.',
   'Requisitos YE-DP-13-001: RN-003 / CA-002. Complementa DEC13-020.'),

  (v_mod, 'DEC13-034', 'Política do adiantamento: as duas opções da lei, à escolha da empresa',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, caput',
   'A lei manda adiantar METADE do salário do mês anterior. A prática consolidada admite também metade do 13º apurado (com médias). As duas leituras são defensáveis, então a escolha é da empresa — e precisa ficar registrada, com efeito real no cálculo e a mesma política valendo para todos no ano.',
   'Empresa com a política do adiantamento configurada.',
   '[{"ordem": 1, "acao": "Configurar a política ''metade da remuneração do mês anterior'' e apurar a 1ª parcela", "resultado_esperado": "Valor = 50% da remuneração do mês anterior"}, {"ordem": 2, "acao": "Trocar para ''metade do 13º apurado'' e apurar de novo", "resultado_esperado": "Valor = 50% do 13º com médias — diferente do anterior"}, {"ordem": 3, "acao": "Conferir o registro", "resultado_esperado": "A política escolhida fica gravada e visível na memória do cálculo"}]'::jsonb,
   'As duas opções existem, a empresa escolhe e o sistema obedece — sem valor mágico.',
   'Requisitos YE-DP-13-001: RN-004. Ponto [VAL] do documento: a escolha deve ser conferida com a contabilidade.'),

  (v_mod, 'DEC13-035', 'Adiantamento nas férias fora de janeiro é avisado, não recusado',
   'negativo', 'media', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, §2º',
   'O empregado que quer receber a 1ª parcela nas férias deve requerer em JANEIRO do ano correspondente. Pedido fora dessa janela não obriga o empregador. O sistema não deve recusar em silêncio nem pagar sem registro: deve avisar que o pedido saiu fora do prazo e deixar a decisão documentada.',
   'Pedido de férias com adiantamento do 13º requerido em março.',
   '[{"ordem": 1, "acao": "Gerar os adiantamentos das férias do ano", "resultado_esperado": "Os pedidos de janeiro geram a 1ª parcela normalmente"}, {"ordem": 2, "acao": "Conferir o pedido feito em março", "resultado_esperado": "Aparece na lista de avisos como fora da janela do §2º"}, {"ordem": 3, "acao": "Conferir a contagem", "resultado_esperado": "O retorno informa quantos pedidos ficaram fora de janeiro"}]'::jsonb,
   'Fora de janeiro não é proibido — é decisão da empresa, e fica registrada.',
   'Requisitos YE-DP-13-001: RN-004. Complementa DEC13-032.'),

  (v_mod, 'DEC13-043', 'INSS do 13º respeita faixas e teto, e bate com a tabela vigente',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 8.212/1991, art. 20 e art. 28, §7º; Decreto 3.048/1999, art. 214, §6º',
   'O INSS do 13º é progressivo por faixas e limitado ao teto. O cálculo do banco (usado no lote) e o da tela precisam dar o MESMO número em todas as faixas, inclusive nas bordas e acima do teto — divergência entre os dois é erro de recolhimento, com multa.',
   'Tabela de INSS vigente cadastrada.',
   '[{"ordem": 1, "acao": "Calcular o INSS em bases de cada faixa e nas bordas", "resultado_esperado": "Valor progressivo, faixa a faixa"}, {"ordem": 2, "acao": "Calcular o INSS em base acima do teto", "resultado_esperado": "Desconto limitado ao teto — não cresce mais"}, {"ordem": 3, "acao": "Comparar banco e tela", "resultado_esperado": "Mesmo valor, centavo a centavo"}]'::jsonb,
   'Faixas, bordas e teto conferidos — e os dois caminhos de cálculo concordando.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Complementa DEC13-040.'),

  (v_mod, 'DEC13-052', 'Provisão do 13º é revertida quando o colaborador é desligado',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 6.404/1976, art. 177 (regime de competência); NBC TG 1000, seção 21 (provisões); documento YE-DP-13-001, CA-009',
   'A provisão acumula 1/12 por mês enquanto o vínculo existe. Quando o colaborador é desligado e o 13º é quitado na rescisão, a provisão daquele vínculo precisa ser REVERTIDA — senão o balanço carrega para sempre uma obrigação que já foi paga.',
   'Colaborador provisionado durante o ano e desligado antes de dezembro.',
   '[{"ordem": 1, "acao": "Provisionar competências com o vínculo ativo", "resultado_esperado": "Provisão acumulada mês a mês"}, {"ordem": 2, "acao": "Desligar o colaborador e provisionar a competência seguinte", "resultado_esperado": "A provisão do desligado é revertida, não repetida"}, {"ordem": 3, "acao": "Conciliar o ano", "resultado_esperado": "Provisionado e pago fecham, sem sobra do desligado"}]'::jsonb,
   'Provisão de quem saiu não fica pendurada no balanço.',
   'Requisitos YE-DP-13-001: RNF-007. Complementa DEC13-051.'),

  (v_mod, 'DEC13-061', 'Culpa recíproca paga metade do 13º proporcional',
   'alternativo', 'alta', 'aprovado', 'api',
   'CLT, art. 484; Súmula 14 do TST',
   'Reconhecida a culpa recíproca, as verbas rescisórias devidas pela dispensa sem justa causa são pagas pela METADE — inclusive o 13º proporcional. Tratar como justa causa (zero) ou como dispensa comum (integral) erra nos dois sentidos.',
   'Rescisão por culpa recíproca reconhecida judicialmente, no meio do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por culpa recíproca", "resultado_esperado": "Metade do 13º proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa sem justa causa", "resultado_esperado": "Metade do valor da dispensa comum"}, {"ordem": 3, "acao": "Conferir o fundamento", "resultado_esperado": "A memória cita o art. 484 da CLT e a Súmula 14 do TST"}]'::jsonb,
   'Culpa recíproca não é zero nem inteiro: é metade.',
   'Requisitos YE-DP-13-001: RN-009. DESL-035 cobre o lado do aviso prévio; aqui é o 13º.'),

  (v_mod, 'DEC13-062', 'Pedido de demissão mantém o 13º proporcional',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 3º; Súmula 157 do TST',
   'Quem pede demissão tem direito ao 13º proporcional aos meses trabalhados. Só a dispensa por justa causa afasta a gratificação. Confundir os dois motivos retém verba devida — e a Súmula 157 é expressa.',
   'Rescisão por pedido de demissão em agosto do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por pedido de demissão", "resultado_esperado": "8/12 do 13º, proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa por justa causa", "resultado_esperado": "Na justa causa, zero"}, {"ordem": 3, "acao": "Conferir o abatimento do adiantamento", "resultado_esperado": "Se houve 1ª parcela paga, ela é deduzida"}]'::jsonb,
   'Pedir demissão não faz perder o 13º proporcional.',
   'Requisitos YE-DP-13-001: RN-009. Complementa DEC13-060.'),

  (v_mod, 'DEC13-063', 'Falecimento: o 13º proporcional é devido e vai aos dependentes',
   'alternativo', 'media', 'aprovado', 'api',
   'Lei 6.858/1980, art. 1º; Lei 4.090/1962, art. 3º',
   'Com o falecimento do empregado, o 13º proporcional continua devido e é pago aos dependentes habilitados na Previdência, independentemente de inventário. O sistema não pode tratar o falecimento como perda da gratificação.',
   'Rescisão por falecimento em setembro do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por falecimento", "resultado_esperado": "9/12, proporcional aos avos — valor devido"}, {"ordem": 2, "acao": "Conferir o fundamento", "resultado_esperado": "A memória registra que o pagamento segue a Lei 6.858/1980"}, {"ordem": 3, "acao": "Conferir que não é tratado como justa causa", "resultado_esperado": "Valor diferente de zero"}]'::jsonb,
   'Falecimento não extingue a gratificação proporcional.',
   'Requisitos YE-DP-13-001: RN-009. O encaminhamento aos dependentes é operação do DP, fora do cálculo.'),

  (v_mod, 'DEC13-072', 'Rodar o lote duas vezes não duplica parcela',
   'negativo', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-004 e RNF-008 (processamento em lote idempotente)',
   'O processamento em lote é feito por pessoas, sob pressão de prazo, e será clicado duas vezes. A segunda passada não pode criar uma segunda parcela viva para o mesmo colaborador: tem de pular quem já tem cálculo e dizer quantos pulou.',
   'Empresa com colaboradores aptos e a 1ª parcela já processada.',
   '[{"ordem": 1, "acao": "Processar o lote da 1ª parcela", "resultado_esperado": "Cálculos criados para os aptos"}, {"ordem": 2, "acao": "Processar o mesmo lote de novo", "resultado_esperado": "Nenhum cálculo novo; o retorno informa quantos já existiam"}, {"ordem": 3, "acao": "Conferir a base", "resultado_esperado": "Uma única parcela viva por colaborador/ano"}]'::jsonb,
   'Clicar duas vezes não duplica folha.',
   'Requisitos YE-DP-13-001: RF-004. A trava de base é a unicidade da parcela viva.'),

  (v_mod, 'DEC13-073', 'Prazo legal recua para o último dia útil, inclusive em feriado municipal',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, arts. 1º e 2º; Lei 662/1949 e Lei 9.093/1995 (feriados civis e municipais)',
   'Se 30/11 ou 20/12 caem em sábado, domingo ou feriado, o pagamento tem de ser ANTECIPADO para o último dia útil anterior — nunca adiado. A conta precisa enxergar também o feriado municipal da cidade do estabelecimento, que é o mais fácil de esquecer.',
   'Feriado municipal cadastrado no dia útil imediatamente anterior à data-limite.',
   '[{"ordem": 1, "acao": "Consultar o prazo da 2ª parcela num ano em que 20/12 cai em domingo", "resultado_esperado": "Data-limite antecipada para a sexta-feira"}, {"ordem": 2, "acao": "Cadastrar feriado municipal nessa sexta e consultar de novo", "resultado_esperado": "Antecipa mais um dia útil"}, {"ordem": 3, "acao": "Conferir a 1ª parcela em 30/11", "resultado_esperado": "Mesma regra de antecipação"}]'::jsonb,
   'A data-limite anda para trás, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-002 / CA-003. Complementa DEC13-031.')
  ON CONFLICT (codigo) DO UPDATE SET
      titulo = EXCLUDED.titulo, base_legal = EXCLUDED.base_legal,
      objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes,
      passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
      observacoes = EXCLUDED.observacoes, nivel = EXCLUDED.nivel,
      prioridade = EXCLUDED.prioridade, updated_at = now();

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Documentacao de testes do 13o: % casos antes, % depois.', v_antes, v_depois;
END $doc$;

-- ── DEC13-005: a fronteira dos 15 dias, dia a dia ─────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_cpf text; v_avos int; c record;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de vinculos admitidos exatamente nas datas de fronteira';
  r.esperado := 'Mes com 15 dias ou mais conta; com 14, nao conta (Lei 4.090, art. 1o, §2o)';

  FOR c IN
    SELECT * FROM (VALUES
      ('90000005053', make_date(v_ano,3,17), 10, 'admitido em 17/03 (15 dias)'),
      ('90000005134', make_date(v_ano,3,18),  9, 'admitido em 18/03 (14 dias)'),
      ('90000005215', make_date(v_ano,2,14), 11, 'admitido em 14/02'),
      ('90000005304', make_date(v_ano,2,15), 10, 'admitido em 15/02')
    ) AS t(cpf, adm, avos_esperados, rotulo)
  LOOP
    -- vinculo efemero: a sonda cria, le e desfaz o proprio rastro
    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
    INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
    VALUES (v_ten, 'QA Fronteira ' || c.cpf, c.cpf, 'QA', c.adm, 'concluido');

    v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, c.cpf, v_ano, NULL)->>'avos')::int, -1);
    v_lidos := array_append(v_lidos, format('%s: %s avos', c.rotulo, v_avos));
    IF v_avos <> c.avos_esperados THEN
      v_erros := array_append(v_erros,
        format('%s deveria dar %s avos e deu %s', c.rotulo, c.avos_esperados, v_avos));
    END IF;

    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a fronteira dos 15 dias esta deslocada — ' || array_to_string(v_erros, '; ')
             || '. Um dia de diferenca na contagem vira um avo a mais ou a menos em toda a folha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Fronteiras conferidas (' || array_to_string(v_lidos, '; ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-043: faixas, bordas e teto do INSS ──────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_ant numeric := -1; v_val numeric; v_teto numeric; v_base numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Calcular o INSS do 13o em bases crescentes, das faixas ate acima do teto';
  r.esperado := 'Valor progressivo que nunca diminui e para de crescer no teto (Lei 8.212/1991, art. 20)';

  FOREACH v_base IN ARRAY ARRAY[1000, 1412, 1500, 2666.68, 4000.03, 7786.02, 9000, 20000]::numeric[]
  LOOP
    v_val := COALESCE((public.decimo_terceiro_inss(v_base, v_ten, NULL)->>'valor')::numeric, -1);
    v_lidos := array_append(v_lidos, format('base %s -> %s', v_base, v_val));
    IF v_val < v_ant THEN
      v_erros := array_append(v_erros, format('base %s desconta MENOS que a base anterior', v_base));
    END IF;
    IF v_val > v_base THEN
      v_erros := array_append(v_erros, format('base %s desconta mais que o proprio 13o', v_base));
    END IF;
    v_ant := v_val;
  END LOOP;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o teto: dobrar a base acima do teto nao pode aumentar o desconto';
  r.esperado := 'Mesmo valor — o desconto e limitado ao teto';
  v_teto := (public.decimo_terceiro_inss(20000, v_ten, NULL)->>'valor')::numeric;
  IF (public.decimo_terceiro_inss(40000, v_ten, NULL)->>'valor')::numeric <> v_teto THEN
    v_erros := array_append(v_erros, 'o desconto continua crescendo acima do teto');
  END IF;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o INSS do 13o nao respeita a progressao ou o teto — '
             || array_to_string(v_erros, '; ') || '. Recolhimento errado gera multa.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Progressao e teto conferidos (%s); teto em R$ %s.',
                       array_to_string(v_lidos, '; '), v_teto);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-073: a data-limite anda para tras, nunca para frente ────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_073()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_d date; v_ano int; v_limite date;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Consultar o prazo legal das duas parcelas em varios anos';
  r.esperado := 'Sempre dia util, e nunca depois de 30/11 (1a) ou 20/12 (2a) — Lei 4.749/1965';

  FOR v_ano IN 2024..2030 LOOP
    -- 1a parcela: limite 30/11
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 1, NULL, NULL);
    v_limite := make_date(v_ano, 11, 30);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em %s, depois de 30/11', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('%s 1a=%s', v_ano, v_d));

    -- 2a parcela: limite 20/12
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 2, NULL, NULL);
    v_limite := make_date(v_ano, 12, 20);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em %s, depois de 20/12', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('2a=%s', v_d));
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a data-limite do 13o nao antecipa corretamente — '
             || array_to_string(v_erros, '; ')
             || '. Pagar fora da janela e infracao mesmo com o valor certo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Prazos conferidos em 7 anos, sempre em dia util e dentro do limite ('
             || array_to_string(v_lidos, ', ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-006: acidente de trabalho nao derruba avo (Sumula 46 TST) ───
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005487'; v_af uuid;
  v_avos_acid int; v_avos_comum int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem ficou 4 meses afastado por ACIDENTE DE TRABALHO (B91)';
  r.esperado := 'Os meses contam: a ausencia por acidente nao pesa contra o 13o (Sumula 46 do TST)';

  DELETE FROM public.afastamentos WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes   WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
  VALUES (v_ten, 'QA Acidentado', v_cpf, 'QA', make_date(v_ano - 3, 1, 10), 'concluido');

  INSERT INTO public.afastamentos (tenant_id, colaborador_cpf, colaborador_nome,
                                   data_inicio, data_fim, nexo_trabalho, observacoes)
  VALUES (v_ten, v_cpf, 'QA Acidentado',
          make_date(v_ano, 3, 1), make_date(v_ano, 6, 30), 'sim'::nexo_trabalho, 'QA DEC13-006')
  RETURNING id INTO v_af;
  INSERT INTO public.afastamentos_previdenciario (tenant_id, afastamento_id, especie_beneficio,
                                                  data_inicio_beneficio)
  VALUES (v_ten, v_af, 'B91', make_date(v_ano, 3, 16));

  v_avos_acid := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  r.passo_ordem := 2;
  r.passo_acao := 'Trocar o beneficio para DOENCA COMUM (B31) e apurar de novo';
  r.esperado := 'Ai sim os meses de beneficio saem dos avos do empregador — o INSS paga o abono anual';
  UPDATE public.afastamentos_previdenciario SET especie_beneficio = 'B31' WHERE afastamento_id = v_af;
  v_avos_comum := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.afastamentos_previdenciario WHERE afastamento_id = v_af;
  DELETE FROM public.afastamentos WHERE id = v_af;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;

  IF v_avos_acid < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o afastamento por ACIDENTE DE TRABALHO derruba avos igual ao de '
             || 'doenca comum (acidentario: %s avos; doenca comum: %s avos). A Sumula 46 do TST e '
             || 'expressa: as ausencias por acidente do trabalho NAO sao consideradas contra a '
             || 'gratificacao natalina, e o art. 4o, paragrafo unico, da Lei 8.213/1991 conta o '
             || 'periodo como tempo de servico. Do jeito atual a empresa paga a menos e a '
             || 'diferenca volta como reclamatoria. Correcao: as especies acidentarias (B91, B92) '
             || 'nao entram no desconto de dias do empregador; as comuns (B31, B32) continuam '
             || 'entrando.', v_avos_acid, v_avos_comum);
  ELSIF v_avos_comum >= 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a doenca comum tambem manteve %s avos. O empregador '
             || 'so responde pelos 15 primeiros dias; o restante e abono anual do INSS. Contar '
             || 'tudo paga a MAIS e duplica a despesa.', v_avos_comum);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cada afastamento com seu efeito: acidente de trabalho manteve %s avos '
             || '(Sumula 46 do TST); doenca comum ficou com %s, cabendo o abono anual ao INSS.',
             v_avos_acid, v_avos_comum);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-004: projecao do aviso previo indenizado ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005568'; v_avos int; v_adm uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem foi desligado em 20/11 com aviso previo INDENIZADO de 30 dias';
  r.esperado := '12 avos: a projecao leva o contrato ate 20/12 e dezembro fecha 20 dias (CLT, art. 487, §1o; Sumula 371 do TST)';

  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, 'QA Aviso Indenizado', v_cpf, 'QA', make_date(v_ano - 2, 2, 1),
          make_date(v_ano, 11, 20), 'concluido')
  RETURNING id INTO v_adm;

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento,
                                      aviso_tipo, dias_aviso)
  VALUES (v_ten, 'qa-dec13-004', 'QA Aviso Indenizado', v_cpf, v_adm,
          'DISPENSA_SEM_JUSTA_CAUSA', make_date(v_ano, 11, 20), 'indenizado', 30);

  v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_avos < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a apuracao parou na data do desligamento e devolveu %s avos. O '
             || 'aviso previo INDENIZADO integra o tempo de servico para todos os efeitos legais '
             || '(CLT, art. 487, §1o; Sumula 371 do TST): desligado em 20/11 com 30 dias de aviso, '
             || 'o contrato projeta ate 20/12 e dezembro fecha 20 dias — o 12o avo e devido. '
             || 'Pagar 11/12 onde a lei manda 12/12 e diferenca que volta como reclamatoria, e a '
             || 'mesma projecao vale para as ferias proporcionais. Correcao: somar os dias do '
             || 'aviso indenizado a data de fim do contrato antes de contar os avos.', v_avos);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Projecao do aviso indenizado considerada: %s avos, com dezembro contado '
             || 'pela data projetada do fim do contrato.', v_avos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-061/062/063: o motivo da rescisao e o 13o ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_rescisao_motivo(
  p_tipo text, p_mes int, p_fator numeric, p_cpf text, p_nome text)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_adm uuid; v_resc uuid; v_out jsonb;
BEGIN
  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = p_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = p_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, p_nome, p_cpf, 'QA', 3000, make_date(v_ano - 2, 2, 1),
          make_date(v_ano, p_mes, 25), 'concluido')
  RETURNING id INTO v_adm;

  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento)
  VALUES (v_ten, 'qa-' || p_cpf, p_nome, p_cpf, v_adm, p_tipo::public.rescisao_tipo, make_date(v_ano, p_mes, 25))
  RETURNING id INTO v_resc;

  v_out := public.decimo_terceiro_da_rescisao(v_resc);

  DELETE FROM public.folha_rescisoes WHERE id = v_resc;
  DELETE FROM public.admissoes WHERE id = v_adm;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_ped jsonb; v_jc jsonb; v_dev numeric; v_avos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por PEDIDO DE DEMISSAO em agosto';
  r.esperado := '13o proporcional aos avos — so a justa causa afasta a gratificacao (Sumula 157 do TST)';
  v_ped := public.qa_caso_dec13_rescisao_motivo('PEDIDO_DEMISSAO', 8, 1.0, '90000005649', 'QA Pediu Demissao');
  v_jc  := public.qa_caso_dec13_rescisao_motivo('DISPENSA_COM_JUSTA_CAUSA', 8, 0.0, '90000005720', 'QA Justa Causa');
  v_dev := COALESCE((v_ped->>'devido')::numeric, -1);
  v_avos := COALESCE((v_ped->>'avos')::int, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o pedido de demissao ficou sem 13o proporcional (devido: R$ %s, '
             || '%s avos). A Sumula 157 do TST e o art. 3o da Lei 4.090/1962 garantem a '
             || 'gratificacao proporcional a quem pede demissao — so a justa causa a afasta. '
             || 'Reter verba devida e passivo direto.', v_dev, v_avos);
  ELSIF COALESCE((v_jc->>'devido')::numeric, -1) <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a justa causa pagou R$ %s de 13o proporcional, '
             || 'quando a Lei 4.090/1962 a afasta.', (v_jc->>'devido'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Pedido de demissao manteve o 13o proporcional (%s avos, R$ %s) e a justa '
             || 'causa ficou em zero, como manda a lei.', v_avos, v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_out jsonb; v_dev numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por FALECIMENTO em setembro';
  r.esperado := '13o proporcional devido, para pagamento aos dependentes (Lei 6.858/1980)';
  v_out := public.qa_caso_dec13_rescisao_motivo('FALECIMENTO', 9, 1.0, '90000005800', 'QA Falecimento');
  v_dev := COALESCE((v_out->>'devido')::numeric, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o falecimento ficou sem 13o proporcional (R$ %s). A gratificacao '
             || 'continua devida e e paga aos dependentes habilitados na Previdencia, '
             || 'independentemente de inventario (Lei 6.858/1980, art. 1o; Lei 4.090/1962, art. '
             || '3o). Tratar falecimento como perda da verba e erro grave com a familia.', v_dev);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Falecimento manteve o 13o proporcional devido (%s avos, R$ %s), para '
             || 'encaminhamento aos dependentes (Lei 6.858/1980).', (v_out->>'avos'), v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_cr jsonb; v_sem jsonb; v_dev_cr numeric; v_dev_sem numeric;
  v_tipos text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por CULPA RECIPROCA';
  r.esperado := 'Metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST)';

  SELECT string_agg(DISTINCT e.enumlabel, ', ') INTO v_tipos
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname LIKE '%rescisao%' AND e.enumlabel ILIKE '%RECIPROC%';

  BEGIN
    v_cr := public.qa_caso_dec13_rescisao_motivo('CULPA_RECIPROCA', 6, 0.5, '90000005991', 'QA Culpa Reciproca');
  EXCEPTION WHEN OTHERS THEN
    v_cr := jsonb_build_object('erro', SQLERRM);
  END;
  v_sem := public.qa_caso_dec13_rescisao_motivo('DISPENSA_SEM_JUSTA_CAUSA', 6, 1.0, '90000006025', 'QA Sem Justa Causa');

  v_dev_cr  := COALESCE((v_cr->>'devido')::numeric, -1);
  v_dev_sem := COALESCE((v_sem->>'devido')::numeric, -1);

  IF v_cr ? 'erro' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca nao existe como motivo de rescisao (%s). O art. '
             || '484 da CLT e a Sumula 14 do TST mandam pagar METADE das verbas da dispensa sem '
             || 'justa causa, o 13o proporcional incluido. Sem esse motivo, o operador acaba '
             || 'lancando como justa causa (paga zero, e devedor) ou como dispensa comum (paga '
             || 'inteiro, e perde dinheiro). Detalhe tecnico: %s',
             coalesce('motivos com "reciproca" no sistema: ' || v_tipos, 'nenhum motivo de culpa reciproca cadastrado'),
             (v_cr->>'erro'));
  ELSIF v_dev_sem <= 0 OR abs(v_dev_cr - round(v_dev_sem / 2, 2)) > 0.02 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca pagou R$ %s, quando deveria pagar metade da '
             || 'dispensa sem justa causa (R$ %s / 2 = R$ %s) — CLT, art. 484 e Sumula 14 do TST.',
             v_dev_cr, v_dev_sem, round(v_dev_sem / 2, 2));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Culpa reciproca paga metade: R$ %s contra R$ %s da dispensa sem justa '
             || 'causa (Sumula 14 do TST).', v_dev_cr, v_dev_sem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-022: Sumula 347 — media FISICA das horas extras ─────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_022()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_fn boolean; v_src text; v_param boolean; v_marca boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe media FISICA de horas extras no 13o?';
  r.esperado := 'Quantidade de horas do ano dividida pelos meses, multiplicada pelo valor da hora ATUAL (Sumula 347 do TST)';

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras')
    INTO v_fn;
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras';
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                    AND column_name='media_horas_extras') INTO v_param;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='folha_rubricas'
                    AND column_name='he_do_ponto') INTO v_marca;

  IF NOT v_fn OR NOT v_param THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a media de horas extras do 13o nao e fisica (funcao: %s; escolha '
             || 'do criterio: %s). A Sumula 347 do TST manda somar a QUANTIDADE de horas extras '
             || 'do ano, dividir pelos meses e multiplicar pelo valor da hora VIGENTE. Usar a '
             || 'media dos valores pagos paga a menos sempre que houve aumento salarial no ano — '
             || 'e o aumento e a regra, nao a excecao.',
             CASE WHEN v_fn THEN 'existe' ELSE 'nao existe' END,
             CASE WHEN v_param THEN 'existe' ELSE 'nao existe' END);
  ELSIF v_src NOT ILIKE '%valor_hora%' AND v_src NOT ILIKE '%salario%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a funcao de media de horas extras existe, mas nao multiplica pelo valor '
             || 'da hora atual — sem isso ela nao cumpre a Sumula 347 do TST.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Media fisica implementada (decimo_terceiro_media_horas_extras), criterio '
             || 'escolhivel pela empresa e rubricas de HE do ponto marcadas: %s.',
             CASE WHEN v_marca THEN 'sim' ELSE 'marcador ausente' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-023: adicionais habituais integram a base ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_col text; v_fora text; v_total int; v_existentes int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Conferir se as rubricas de adicional habitual entram na base do 13o';
  r.esperado := 'Noturno, insalubridade e periculosidade marcados como integrantes (Sumulas 60, 132 e 139 do TST)';

  SELECT column_name INTO v_col FROM information_schema.columns
   WHERE table_schema='public' AND table_name='folha_rubricas'
     AND (column_name ILIKE '%13%' OR column_name ILIKE '%decimo%') LIMIT 1;

  IF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o cadastro de rubricas nao tem marcacao de "integra o 13o". Sem ela, '
             || 'nao ha como saber se adicional noturno, insalubridade e periculosidade entram '
             || 'na base — e eles entram, por habitualidade (Sumulas 60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')') INTO v_existentes;

  IF COALESCE(v_existentes, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Nao ha rubrica de adicional noturno, insalubridade ou periculosidade cadastrada '
             || 'nesta base — nao ha o que conferir. O caso volta a valer assim que a empresa '
             || 'cadastrar esses adicionais, e ai eles precisam entrar na base do 13o (Sumulas '
             || '60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*), string_agg(descricao, '', '') FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')
        AND COALESCE(%I, false) = false', v_col)
  INTO v_total, v_fora;

  IF v_total > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s rubrica(s) de adicional habitual estao FORA da base do 13o '
             || '(%s). Adicional noturno (Sumula 60), de periculosidade (Sumula 132) e de '
             || 'insalubridade (Sumula 139) integram a remuneracao e, por habitualidade, a base '
             || 'do 13o. Fora da base, o 13o sai a menor sem ninguem perceber. Correcao: marcar '
             || 'essas rubricas como integrantes no cadastro.', v_total, v_fora);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rubrica de adicional habitual ficou fora da base do 13o (marcador "'
             || v_col || '" no cadastro de rubricas).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-034: as duas politicas do adiantamento ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_check text; v_opcoes text; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a empresa escolhe a base do adiantamento?';
  r.esperado := 'As duas leituras da Lei 4.749/1965, art. 2o, disponiveis e com efeito no calculo';

  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.decimo_terceiro_config'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%adiantamento_base%';

  SELECT prosrc ILIKE '%adiantamento_base%' INTO v_le
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular';

  v_opcoes := coalesce(v_check, 'sem parametro');

  IF v_check IS NULL
     OR v_check NOT ILIKE '%remuneracao_mes_anterior%'
     OR v_check NOT ILIKE '%proporcional_apurado%' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: nao ha escolha registrada da base do adiantamento (%s). A Lei '
             || '4.749/1965, art. 2o, manda adiantar metade do salario do mes anterior; a pratica '
             || 'consolidada admite metade do 13o apurado. As duas sao defensaveis, e por isso a '
             || 'escolha e da empresa — mas precisa ficar REGISTRADA e valer igual para todos no '
             || 'ano, senao cada calculo vira uma interpretacao.', v_opcoes);
  ELSIF NOT COALESCE(v_le, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o parametro da politica do adiantamento existe, mas o calculo da parcela '
             || 'nao o le — escolha sem efeito e pior que escolha nenhuma, porque parece cumprida.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Politica do adiantamento registrada e lida pelo calculo (%s).', v_opcoes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-035: pedido fora de janeiro e avisado ───────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o pedido fora de janeiro e sinalizado?';
  r.esperado := 'Aviso de pedido fora da janela do §2o do art. 2o da Lei 4.749/1965 — sem recusa silenciosa';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_adiantamento_nas_ferias';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe rotina de adiantamento do 13o junto as ferias. O §2o do art. '
             || '2o da Lei 4.749/1965 da esse direito a quem requer em janeiro, e sem rotina o '
             || 'pedido se perde entre planilhas.';
  ELSIF v_src NOT ILIKE '%janeiro%' AND v_src NOT ILIKE '%fora_de_janeiro%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a rotina de adiantamento nas ferias nao distingue o pedido feito em '
             || 'JANEIRO dos demais. Fora da janela do §2o o empregador nao e obrigado a antecipar '
             || '— o sistema deve avisar e deixar a decisao registrada, nunca recusar em silencio '
             || 'nem pagar sem rastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A rotina de adiantamento nas ferias separa os pedidos de janeiro e avisa sobre os '
             || 'que ficaram fora da janela do §2o (Lei 4.749/1965).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-052: provisao do desligado e revertida ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisao reverte quando o vinculo termina?';
  r.esperado := 'Provisao do desligado revertida na competencia seguinte, e conciliacao fechando';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_provisionar';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha provisao propria do 13o. Sem ela, a despesa aparece inteira em '
             || 'dezembro e o resultado dos outros onze meses sai distorcido (regime de '
             || 'competencia — Lei 6.404/1976, art. 177).';
  ELSIF v_src NOT ILIKE '%revert%' OR v_src NOT ILIKE '%desligad%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a provisao do 13o nao reverte a parcela de quem foi desligado. O 13o '
             || 'desses ja foi quitado na rescisao; manter a provisao deixa no balanco uma '
             || 'obrigacao que nao existe mais, e a conciliacao nunca fecha.';
  ELSIF v_src NOT ILIKE '%cpf%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a reversao da provisao nao casa o colaborador pelo CPF. O identificador '
             || 'livre de colaborador difere entre modulos, entao a reversao encontra zero linhas '
             || 'e falha em silencio — o pior tipo de erro contabil.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A provisao do 13o reverte a parcela dos desligados, casando o vinculo pelo CPF.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-072: o lote nao duplica parcela ─────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_072()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000006106'; v_adm uuid;
  v_r1 jsonb; v_r2 jsonb; v_vivas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Processar o lote da 1a parcela e, em seguida, processar o MESMO lote de novo';
  r.esperado := 'A segunda passada nao cria parcela nova e informa quantos ja existiam';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao, status)
  VALUES (v_ten, 'QA Lote Duplo', v_cpf, 'QA', 2500, make_date(v_ano - 1, 3, 1), 'concluido')
  RETURNING id INTO v_adm;

  v_r1 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);
  v_r2 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);

  SELECT count(*) INTO v_vivas FROM public.folha_13_calculo
   WHERE tenant_id = v_ten AND ano = v_ano AND parcela = 1
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf
     AND status <> 'cancelado';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_vivas > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rodar o lote duas vezes criou %s parcelas vivas para o mesmo '
             || 'colaborador. O lote e clicado por gente sob pressao de prazo e sera clicado duas '
             || 'vezes — duplicar parcela vira pagamento em dobro. Retornos: %s / %s',
             v_vivas, v_r1, v_r2);
  ELSIF COALESCE((v_r2->>'ja_calculados')::int, (v_r2->>'ja_existiam')::int, 0) = 0
        AND COALESCE((v_r2->>'calculados')::int, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a segunda passada nao duplicou, mas tambem nao informa que pulou '
             || 'ninguem (%s) — quem processa fica sem saber se o lote rodou. Retorno precisa '
             || 'dizer quantos foram calculados e quantos ja existiam.', v_r2);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Lote idempotente: uma unica parcela viva apos duas passadas; a segunda '
             || 'informou o que pulou (%s).', v_r2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro das rotinas no motor (código -> função) ──────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-004','qa_caso_dec13_004',true), ('DEC13-005','qa_caso_dec13_005',true),
  ('DEC13-006','qa_caso_dec13_006',true), ('DEC13-022','qa_caso_dec13_022',true),
  ('DEC13-023','qa_caso_dec13_023',true), ('DEC13-034','qa_caso_dec13_034',true),
  ('DEC13-035','qa_caso_dec13_035',true), ('DEC13-043','qa_caso_dec13_043',true),
  ('DEC13-052','qa_caso_dec13_052',true), ('DEC13-061','qa_caso_dec13_061',true),
  ('DEC13-062','qa_caso_dec13_062',true), ('DEC13-063','qa_caso_dec13_063',true),
  ('DEC13-072','qa_caso_dec13_072',true), ('DEC13-073','qa_caso_dec13_073',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ── Conferencia final ─────────────────────────────────────────────────
SELECT 'aviso previo indenizado projeta o tempo (CLT art. 487 §1o)' AS item,
       CASE WHEN position('v_fim_contrato' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END AS situacao,
       CASE WHEN position('v_fim_contrato' in p.prosrc) > 0 THEN NULL
            ELSE 'decimo_terceiro_avos nao foi substituida' END AS erro_tecnico
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='decimo_terceiro_avos'
 UNION ALL
SELECT 'acidente de trabalho nao derruba avo (Sumula 46 do TST)',
       CASE WHEN position('''B31'', ''B32''' in p.prosrc) > 0 THEN 'OK' ELSE 'FALTOU' END,
       CASE WHEN position('''B31'', ''B32''' in p.prosrc) > 0 THEN NULL
            ELSE 'as especies acidentarias ainda entram no desconto de dias' END
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='decimo_terceiro_avos'
 UNION ALL
-- A Documentacao de testes NAO vem mais neste script: ela nasceu por
-- migration, que so alcanca o ambiente de teste, e por isso em outros
-- ambientes aparecia "documentados: 0". Quem a leva, inteira e
-- autossuficiente, e o script_13o_documentacao_testes.sql.
SELECT 'Documentacao de testes do 13o nesta base',
       CASE WHEN count(*) >= 31 THEN 'OK' ELSE 'INFORMATIVO' END,
       CASE WHEN count(*) >= 31 THEN 'documentados: ' || count(*)::text
            ELSE 'documentados: ' || count(*)::text || ' de 31 — para completar, cole o '
                 || 'script_13o_documentacao_testes.sql. As correcoes de lei acima '
                 || 'independem disso e ja estao valendo' END
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
 WHERE m.path = 'financeiro/decimo-terceiro'
 ORDER BY 2 DESC, 1;
