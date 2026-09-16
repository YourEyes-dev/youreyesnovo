-- =========================================================
-- Folha de demonstração do 13º — semeadura por CRITÉRIO, não por
-- identificador escrito à mão
--
-- POR QUE (conferência de 03/09/2026): a semeadura anterior
-- (20260903210000) mirava o tenant a9b23784-... , tirado da migration
-- que criou aqueles colaboradores. Ela rodou na esteira, não encontrou
-- esse tenant e saiu sem fazer nada — em silêncio, porque eu a tinha
-- envolvido num EXCEPTION WHEN OTHERS. Três erros meus de uma vez:
--   1) prender a semeadura a um identificador fixo;
--   2) engolir a falha em vez de reclamar alto;
--   3) não conferir, antes, ONDE os colaboradores do teste estavam.
--
-- O QUE O DIAGNÓSTICO MOSTROU:
--   tenant 11111111-...  "Empresa Staging LTDA"  20 colaboradores, 0 rubricas
--   tenant a9b23784-...  (SEM linha em tenants)  10 colaboradores, 0 rubricas
--
-- O segundo é órfão: tem admissões, mas nenhuma linha na tabela de
-- empresas. Como folha_rubricas, folha_periodos e folha_lancamentos
-- exigem uma empresa existente (chave estrangeira), esse conjunto NÃO
-- PODE receber folha — nem por esta semeadura nem pela tela. Ele é
-- avisado aqui e fica para o dono do produto decidir (criar a empresa
-- que falta ou remover as admissões órfãs); ressuscitar a empresa por
-- conta própria seria decisão que não me cabe.
--
-- O QUE FAZ AGORA: semeia TODO tenant que (a) existe de fato na tabela
-- de empresas, (b) tem admissão concluída e (c) não tem nenhuma rubrica
-- cadastrada — com o catálogo padrão de rubricas e hora extra fictícia
-- nas competências de 2026, a partir do mês de admissão de cada um.
--
-- ONDE RODA: só fora da produção. Migrations não são aplicadas na
-- produção (lá só entra script de entrega) e, além disso, este arquivo
-- se recusa a rodar se app_config apontar para o projeto de produção.
-- NÃO faz parte do script de entrega do 13º, de propósito.
-- Todos os valores são fictícios; nenhum dado real é tocado.
-- =========================================================

SET lock_timeout = '10s';

DO $demo$
DECLARE
    v_url        TEXT;
    v_tenant     RECORD;
    v_he         UUID;
    v_lanc       INT;
    v_total      INT := 0;
    v_empresas   INT := 0;
    v_orfaos     TEXT;
BEGIN
    -- ── Trava de ambiente ────────────────────────────────────────────
    SELECT valor INTO v_url FROM public.app_config WHERE chave = 'supabase_url';
    IF v_url IS NOT NULL AND v_url LIKE '%diayjpsrcerycycyaxst%' THEN
        RAISE WARNING 'Semeadura de demonstração do 13º RECUSADA: este banco é o de produção.';
        RETURN;
    END IF;

    -- ── Admissões órfãs: avisa, não conserta ─────────────────────────
    SELECT string_agg(DISTINCT a.tenant_id::text, ', ')
      INTO v_orfaos
      FROM public.admissoes a
     WHERE a.status = 'concluido'
       AND NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id = a.tenant_id);

    IF v_orfaos IS NOT NULL THEN
        RAISE WARNING 'Há admissões apontando para empresa inexistente (tenant %). Esse conjunto não pode receber folha — as tabelas de folha exigem empresa existente. Decisão do dono do produto: criar a empresa que falta ou remover as admissões órfãs.', v_orfaos;
    END IF;

    -- ── Semeadura, empresa a empresa ─────────────────────────────────
    FOR v_tenant IN
        SELECT t.id, t.nome
          FROM public.tenants t
         WHERE EXISTS (
                   SELECT 1 FROM public.admissoes a
                    WHERE a.tenant_id = t.id
                      AND a.status = 'concluido'
                      AND a.data_admissao IS NOT NULL)
           AND NOT EXISTS (
                   SELECT 1 FROM public.folha_rubricas r
                    WHERE r.tenant_id = t.id)
    LOOP
        BEGIN
            v_empresas := v_empresas + 1;

            INSERT INTO public.folha_rubricas
                (tenant_id, codigo_interno, descricao, tipo, natureza,
                 incide_inss, incide_irrf, incide_fgts, incide_ferias, incide_13,
                 incide_rescisao, prioridade_calculo, protegida, ativa)
            VALUES
                (v_tenant.id,'1000','Salário Base','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,1,true,true),
                (v_tenant.id,'1003','Hora Extra 50%','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,10,false,true),
                (v_tenant.id,'1004','Hora Extra 100%','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,11,false,true),
                (v_tenant.id,'1005','Comissão','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,15,false,true),
                (v_tenant.id,'1006','Adicional Noturno','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,20,false,true),
                (v_tenant.id,'1007','Adicional Periculosidade','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,25,false,true),
                (v_tenant.id,'1008','Adicional Insalubridade','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,26,false,true),
                (v_tenant.id,'1010','Vale Refeição','PROVENTO','INDENIZATORIA',false,false,false,false,false,false,50,false,true),
                (v_tenant.id,'1020','DSR s/ Comissões','PROVENTO','REMUNERATORIA',true,true,true,true,true,true,30,false,true),
                (v_tenant.id,'9001','INSS','DESCONTO','OUTRA',false,false,false,false,false,false,100,true,true),
                (v_tenant.id,'9002','IRRF','DESCONTO','OUTRA',false,false,false,false,false,false,101,true,true)
            ON CONFLICT (tenant_id, codigo_interno) DO NOTHING;

            INSERT INTO public.folha_periodos (tenant_id, competencia, status)
            SELECT v_tenant.id, to_char(make_date(2026, m, 1), 'YYYY-MM'), 'fechado'
              FROM generate_series(1, 12) m
            ON CONFLICT (tenant_id, competencia) DO NOTHING;

            SELECT id INTO v_he
              FROM public.folha_rubricas
             WHERE tenant_id = v_tenant.id AND codigo_interno = '1003'
             LIMIT 1;

            IF v_he IS NULL THEN
                RAISE WARNING 'Empresa % (%): rubrica de hora extra não criada — lançamentos não semeados.',
                    v_tenant.nome, v_tenant.id;
                CONTINUE;
            END IF;

            -- Hora extra fictícia por competência, do mês de admissão em
            -- diante. Valor determinístico por CPF (R$ 200 a R$ 700) para a
            -- média não sair igual para todo mundo.
            INSERT INTO public.folha_lancamentos
                (tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf,
                 rubrica_id, rubrica_codigo, rubrica_descricao, tipo, referencia, valor, origem)
            SELECT v_tenant.id, pe.id, a.id::text, a.nome_completo, a.cpf,
                   v_he, '1003', 'Hora Extra 50%', 'PROVENTO', 'demonstração',
                   200 + (('x' || substr(md5(a.cpf), 1, 8))::bit(32)::bigint % 501),
                   'seed_demo'
              FROM public.admissoes a
              JOIN public.folha_periodos pe
                ON pe.tenant_id = v_tenant.id
               AND pe.competencia BETWEEN to_char(greatest(a.data_admissao, DATE '2026-01-01'), 'YYYY-MM')
                                      AND '2026-12'
             WHERE a.tenant_id = v_tenant.id
               AND a.status = 'concluido'
               AND a.data_admissao IS NOT NULL
               AND a.data_admissao <= DATE '2026-12-31'
               AND NOT EXISTS (
                   SELECT 1 FROM public.folha_lancamentos l
                    WHERE l.tenant_id = v_tenant.id
                      AND l.periodo_id = pe.id
                      AND l.colaborador_cpf = a.cpf
                      AND l.rubrica_id = v_he);

            GET DIAGNOSTICS v_lanc = ROW_COUNT;
            v_total := v_total + v_lanc;
            RAISE NOTICE 'Empresa % (%): % lancamento(s) de hora extra semeado(s).',
                v_tenant.nome, v_tenant.id, v_lanc;

        EXCEPTION WHEN OTHERS THEN
            -- Uma empresa problemática não derruba a esteira, mas RECLAMA:
            -- warning aparece no log, ao contrário do silêncio de antes.
            RAISE WARNING 'Empresa % (%): semeadura falhou — %',
                v_tenant.nome, v_tenant.id, SQLERRM;
        END;
    END LOOP;

    IF v_empresas = 0 THEN
        -- Nada a fazer é o estado NORMAL depois da primeira execução: toda
        -- empresa já tem rubricas. Só vira aviso quando não há empresa com
        -- colaborador alguma — aí sim há algo errado com os dados de teste.
        IF EXISTS (SELECT 1 FROM public.tenants t
                    JOIN public.admissoes a ON a.tenant_id = t.id
                   WHERE a.status = 'concluido') THEN
            RAISE NOTICE 'Folha de demonstração: nada a semear — as empresas com colaborador já têm rubricas cadastradas.';
        ELSE
            RAISE WARNING 'Folha de demonstração: nenhuma empresa com colaborador admitido neste banco — não há o que semear. Confira os dados de teste.';
        END IF;
    ELSE
        RAISE NOTICE 'Folha de demonstração: % empresa(s) semeada(s), % lancamento(s) no total.',
            v_empresas, v_total;
    END IF;
END $demo$;
