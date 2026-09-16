-- =========================================================
-- Dois colaboradores de demonstração para os casos de AVOS do 13º
--
-- POR QUE: a remoção das admissões órfãs (20260903250000) tira do
-- ambiente de teste os únicos colaboradores admitidos no meio do ano.
-- Sobram só os admitidos em 2024, todos com 12/12 avos — e aí os dois
-- casos que são o coração da Entrega 1 deixam de ser conferíveis na
-- tela:
--   · proporcionalidade (Lei 4.090: 1/12 por mês, fração >= 15 dias);
--   · falta injustificada que derruba o mês abaixo de 15 dias.
-- Tirar a cobertura de teste junto com o lixo seria um estrago meu.
--
-- O QUE FAZ, em toda empresa que já tem colaborador (nunca criando
-- empresa nova):
--   1) "QA 13o Admitido em Maio" — admissão em 06/05/2026, deve apurar
--      8 avos (maio entra com 26 dias, acima dos 15);
--   2) "QA 13o Faltoso" — admitido em 2024, com 20 faltas
--      injustificadas em março de 2026, deve apurar 11 avos;
--   3) lança hora extra fictícia para quem ainda não tem lançamento,
--      para a média também aparecer nesses dois.
--
-- CPFs fictícios da faixa 900.000.0XX com dígito verificador válido,
-- como manda a casa. Nenhum dado real.
--
-- ONDE RODA: só fora da produção — migrations não chegam lá e o arquivo
-- se recusa a rodar se app_config apontar para a produção. Não entra em
-- script de entrega nenhum.
-- =========================================================

SET lock_timeout = '10s';

DO $casos$
DECLARE
    v_url    TEXT;
    v_t      RECORD;
    v_he     UUID;
    v_maio   UUID;
    v_falt   UUID;
    v_n      INT;
    v_lanc   INT := 0;
BEGIN
    SELECT valor INTO v_url FROM public.app_config WHERE chave = 'supabase_url';
    IF v_url IS NOT NULL AND v_url LIKE '%diayjpsrcerycycyaxst%' THEN
        RAISE WARNING 'Casos de demonstração do 13º RECUSADOS: este banco é o de produção.';
        RETURN;
    END IF;

    FOR v_t IN
        SELECT t.id, t.nome
          FROM public.tenants t
         WHERE EXISTS (SELECT 1 FROM public.admissoes a
                        WHERE a.tenant_id = t.id AND a.status = 'concluido')
    LOOP
        BEGIN
            -- 1) Admitido no meio do ano → 8 avos.
            INSERT INTO public.admissoes
                (tenant_id, status, nome_completo, cpf, email, cargo, data_admissao, salario)
            SELECT v_t.id, 'concluido', 'QA 13o Admitido em Maio', '90000002119',
                   'qa13.maio@teste.local', 'Analista de Testes', DATE '2026-05-06', 4000
             WHERE NOT EXISTS (
                   SELECT 1 FROM public.admissoes a
                    WHERE a.tenant_id = v_t.id AND a.cpf = '90000002119');

            -- 2) Faltoso → março cai, 11 avos.
            INSERT INTO public.admissoes
                (tenant_id, status, nome_completo, cpf, email, cargo, data_admissao, salario)
            SELECT v_t.id, 'concluido', 'QA 13o Faltoso', '90000002208',
                   'qa13.faltoso@teste.local', 'Analista de Testes', DATE '2024-02-01', 3500
             WHERE NOT EXISTS (
                   SELECT 1 FROM public.admissoes a
                    WHERE a.tenant_id = v_t.id AND a.cpf = '90000002208');

            SELECT id INTO v_maio FROM public.admissoes
             WHERE tenant_id = v_t.id AND cpf = '90000002119' LIMIT 1;
            SELECT id INTO v_falt FROM public.admissoes
             WHERE tenant_id = v_t.id AND cpf = '90000002208' LIMIT 1;

            -- Ponto do faltoso: 20 faltas em março, resto regular. Sem o
            -- ponto do ano inteiro a apuração não desconta falta nenhuma
            -- (ela exige cobertura para poder descontar).
            INSERT INTO public.ponto_diario
                (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data, status)
            SELECT v_t.id, v_falt, 'QA 13o Faltoso', '90000002208', d::date,
                   CASE WHEN d::date BETWEEN DATE '2026-03-05' AND DATE '2026-03-24'
                        THEN 'falta' ELSE 'regular' END
              FROM generate_series(DATE '2026-01-01', DATE '2026-12-31', INTERVAL '1 day') d
             WHERE v_falt IS NOT NULL
               -- Sem ON CONFLICT: a chave única do ponto inclui uma
               -- expressão sobre empresa_id, e ON CONFLICT não casa com ela.
               AND NOT EXISTS (
                   SELECT 1 FROM public.ponto_diario p
                    WHERE p.tenant_id = v_t.id
                      AND p.colaborador_cpf = '90000002208'
                      AND p.data = d::date);

            -- 3) Hora extra para quem ainda não tem lançamento nenhum.
            SELECT id INTO v_he FROM public.folha_rubricas
             WHERE tenant_id = v_t.id AND codigo_interno = '1003' AND ativa LIMIT 1;

            IF v_he IS NOT NULL THEN
                INSERT INTO public.folha_lancamentos
                    (tenant_id, periodo_id, colaborador_id, colaborador_nome, colaborador_cpf,
                     rubrica_id, rubrica_codigo, rubrica_descricao, tipo, referencia, valor, origem)
                SELECT v_t.id, pe.id, a.id::text, a.nome_completo, a.cpf,
                       v_he, '1003', 'Hora Extra 50%', 'PROVENTO', 'demonstração',
                       200 + (('x' || substr(md5(a.cpf), 1, 8))::bit(32)::bigint % 501),
                       'seed_demo'
                  FROM public.admissoes a
                  JOIN public.folha_periodos pe
                    ON pe.tenant_id = v_t.id
                   AND pe.competencia BETWEEN to_char(greatest(a.data_admissao, DATE '2026-01-01'), 'YYYY-MM')
                                          AND '2026-12'
                 WHERE a.tenant_id = v_t.id
                   AND a.status = 'concluido'
                   AND a.data_admissao IS NOT NULL
                   AND a.data_admissao <= DATE '2026-12-31'
                   AND NOT EXISTS (
                       SELECT 1 FROM public.folha_lancamentos l
                        WHERE l.tenant_id = v_t.id
                          AND l.colaborador_cpf = a.cpf
                          AND l.rubrica_id = v_he
                          AND l.periodo_id = pe.id);
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_lanc := v_lanc + v_n;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Empresa % (%): casos de demonstração do 13º falharam — %',
                v_t.nome, v_t.id, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Casos de avos do 13º prontos; % lancamento(s) de hora extra completado(s).', v_lanc;
END $casos$;
