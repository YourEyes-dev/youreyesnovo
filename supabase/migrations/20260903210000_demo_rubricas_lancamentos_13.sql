-- =========================================================
-- Dados de demonstração: rubricas e lançamentos variáveis para conferir
-- a média do 13º no ambiente de TESTE
--
-- POR QUE: na conferência da Entrega 1 do 13º (03/09/2026), a apuração
-- dos avos saiu certa em todos os colaboradores, mas a média das
-- variáveis saiu zero em todos, com o aviso "nenhuma rubrica está
-- marcada como integrante do 13º". O aviso estava certo: o tenant de
-- demonstração tem colaboradores e ponto, mas nunca teve cadastro de
-- rubricas nem folha lançada — então não há o que somar. Sem isso, a
-- metade "média" do cálculo não tem como ser conferida na tela.
--
-- O QUE FAZ: só no tenant de demonstração (a9b23784-...), e só se ele
-- existir e ainda não tiver rubricas, cria o cadastro padrão de
-- rubricas (o mesmo da folha, com hora extra, comissão e adicionais
-- marcados como integrantes do 13º) e lança hora extra fictícia nas
-- competências de 2026 de cada colaborador, a partir do mês em que foi
-- admitido.
--
-- ONDE RODA: apenas no TESTE. Migrations não são aplicadas na produção
-- (lá só entra script de entrega), e este arquivo NÃO faz parte do
-- script de entrega do 13º — de propósito. Nenhum dado real é tocado.
-- Todos os valores são fictícios.
-- =========================================================

SET lock_timeout = '10s';

DO $demo$
DECLARE
    v_tenant  UUID := 'a9b23784-5e5c-4f54-a71c-f1168e02771b';
    v_tem     BOOLEAN;
    v_rubricas INT;
    v_he      UUID;
    v_lanc    INT := 0;
BEGIN
    SELECT EXISTS (SELECT 1 FROM public.tenants WHERE id = v_tenant) INTO v_tem;
    IF NOT v_tem THEN
        RAISE NOTICE 'Tenant de demonstração não existe neste banco — nada a semear.';
        RETURN;
    END IF;

    -- 1) Cadastro de rubricas (o mesmo conjunto padrão da folha).
    INSERT INTO public.folha_rubricas
        (tenant_id, codigo_interno, descricao, tipo, natureza,
         incide_inss, incide_irrf, incide_fgts, incide_ferias, incide_13,
         incide_rescisao, prioridade_calculo, protegida, ativa)
    VALUES
        (v_tenant,'1000','Salário Base','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,1,true,true),
        (v_tenant,'1003','Hora Extra 50%','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,10,false,true),
        (v_tenant,'1004','Hora Extra 100%','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,11,false,true),
        (v_tenant,'1005','Comissão','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,15,false,true),
        (v_tenant,'1006','Adicional Noturno','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,20,false,true),
        (v_tenant,'1007','Adicional Periculosidade','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,25,false,true),
        (v_tenant,'1008','Adicional Insalubridade','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,26,false,true),
        (v_tenant,'1010','Vale Refeição','PROVENTO','INDENIZATORIA',false,false,false,false,false,false,50,false,true),
        (v_tenant,'1020','DSR s/ Comissões','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,30,false,true),
        (v_tenant,'9001','INSS','DESCONTO','OUTRA',false,false,false,false,false,false,100,true,true),
        (v_tenant,'9002','IRRF','DESCONTO','OUTRA',false,false,false,false,false,false,101,true,true)
    ON CONFLICT (tenant_id, codigo_interno) DO NOTHING;

    SELECT count(*) INTO v_rubricas
      FROM public.folha_rubricas
     WHERE tenant_id = v_tenant AND incide_13 AND ativa;
    RAISE NOTICE 'Rubricas integrantes do 13o no tenant de demonstracao: %', v_rubricas;

    -- 2) Competências de 2026.
    INSERT INTO public.folha_periodos (tenant_id, competencia, status)
    SELECT v_tenant, to_char(make_date(2026, m, 1), 'YYYY-MM'), 'fechado'
      FROM generate_series(1, 12) m
    ON CONFLICT (tenant_id, competencia) DO NOTHING;

    -- 3) Hora extra fictícia por competência, a partir do mês de admissão
    --    de cada colaborador. Valor determinístico (varia por CPF, entre
    --    R$ 200 e R$ 700) para a média não sair igual para todo mundo.
    SELECT id INTO v_he
      FROM public.folha_rubricas
     WHERE tenant_id = v_tenant AND codigo_interno = '1003'
     LIMIT 1;

    IF v_he IS NULL THEN
        RAISE NOTICE 'Rubrica de hora extra não encontrada — lançamentos não semeados.';
        RETURN;
    END IF;

    INSERT INTO public.folha_lancamentos
        (tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf,
         rubrica_id, rubrica_codigo, rubrica_descricao, tipo, referencia, valor, origem)
    SELECT v_tenant, pe.id, a.id::text, a.nome_completo, a.cpf,
           v_he, '1003', 'Hora Extra 50%', 'PROVENTO', 'demonstração',
           200 + (('x' || substr(md5(a.cpf), 1, 8))::bit(32)::bigint % 501),
           'seed_demo'
      FROM public.admissoes a
      JOIN public.folha_periodos pe
        ON pe.tenant_id = v_tenant
       AND pe.competencia BETWEEN to_char(greatest(a.data_admissao, DATE '2026-01-01'), 'YYYY-MM')
                              AND '2026-12'
     WHERE a.tenant_id = v_tenant
       AND a.status = 'concluido'
       AND a.data_admissao IS NOT NULL
       AND a.data_admissao <= DATE '2026-12-31'
       AND NOT EXISTS (
           SELECT 1 FROM public.folha_lancamentos l
            WHERE l.tenant_id = v_tenant
              AND l.periodo_id = pe.id
              AND l.colaborador_cpf = a.cpf
              AND l.rubrica_id = v_he
       );

    GET DIAGNOSTICS v_lanc = ROW_COUNT;
    RAISE NOTICE 'Lancamentos de hora extra semeados: %', v_lanc;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Seed de demonstracao do 13o ignorado neste ambiente: %', SQLERRM;
END $demo$;
