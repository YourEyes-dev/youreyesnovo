-- =========================================================
-- Rubricas de adicional habitual — semeadura para AMBIENTE DE TESTE
--
-- POR QUE ESTE SCRIPT EXISTE
--   O caso DEC13-023 confere se adicional NOTURNO, de INSALUBRIDADE e de
--   PERICULOSIDADE entram na base do 13o — eles entram, por
--   habitualidade (Sumulas 60, 132 e 139 do TST). Em base sem essas
--   rubricas cadastradas o caso nao tem o que conferir e sai como "sem
--   dado". Este script cadastra as tres, ficticias, para o teste rodar
--   de verdade.
--
-- ONDE ELE RODA E ONDE NAO RODA
--   SO em homologacao e teste. Em PRODUCAO ele NAO FAZ NADA: rubrica de
--   producao e cadastro do cliente, com codigo, natureza contabil e
--   classificacao eSocial proprios — ninguem de fora inventa isso. A
--   trava e o proprio ref do projeto, lido de app_config. Se rodar na
--   producao por engano, sai um aviso e nada e criado.
--
--   Em producao o DEC13-023 continua saindo como "sem dado para
--   conferir" ate o cliente cadastrar seus adicionais — e ai ele passa a
--   valer sozinho, conferindo as rubricas REAIS. Isso e o certo.
--
-- Nao altera nenhuma rubrica existente: so cria o que faltar.
-- Idempotente.
-- =========================================================

SET lock_timeout = '10s';

DO $seed$
DECLARE
    v_url    TEXT;
    v_tenant UUID;
    v_criadas INT := 0;
    r RECORD;
BEGIN
    SELECT valor INTO v_url FROM public.app_config WHERE chave = 'supabase_url';

    IF coalesce(v_url, '') LIKE '%diayjpsrcerycycyaxst%' THEN
        RAISE NOTICE 'Este e o projeto de PRODUCAO: nenhuma rubrica ficticia foi criada (proposital).';
        RETURN;
    END IF;

    -- Todo tenant da base de teste. Criterio proposital: amarrar em
    -- "tenant com admissao concluida" ja deixou seed nenhum de fora numa
    -- base onde as admissoes apontavam para tenant inexistente.
    FOR v_tenant IN SELECT t.id FROM public.tenants t LOOP
        FOR r IN
            SELECT * FROM (VALUES
                ('AD_NOTURNO',  'Adicional Noturno',        'Sumula 60 do TST'),
                ('AD_INSALUB',  'Adicional de Insalubridade','Sumula 139 do TST'),
                ('AD_PERICUL',  'Adicional de Periculosidade','Sumula 132 do TST')
            ) AS t(codigo, descricao, base)
        LOOP
            IF NOT EXISTS (SELECT 1 FROM public.folha_rubricas fr
                            WHERE fr.tenant_id = v_tenant AND fr.codigo_interno = r.codigo) THEN
                INSERT INTO public.folha_rubricas (
                    tenant_id, codigo_interno, descricao, tipo, natureza,
                    incide_inss, incide_irrf, incide_fgts, incide_ferias,
                    incide_13, incide_rescisao, forma_calculo, ativa)
                VALUES (
                    v_tenant, r.codigo, r.descricao, 'PROVENTO', 'REMUNERATORIA',
                    true, true, true, true,
                    true,  -- integra a base do 13o: e o que o caso DEC13-023 confere
                    true, 'PERCENTUAL_SALARIO', true);
                v_criadas := v_criadas + 1;
            END IF;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Rubricas de adicional criadas: %.', v_criadas;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Semeadura das rubricas de adicional nao aplicada: %', SQLERRM;
END $seed$;

-- ── Conferencia ───────────────────────────────────────────────────────
SELECT 'rubricas de adicional habitual na base do 13o' AS item,
       CASE WHEN count(*) FILTER (WHERE incide_13) = count(*) AND count(*) > 0 THEN 'OK'
            WHEN count(*) = 0 THEN 'INFORMATIVO'
            ELSE 'RESOLVER' END AS situacao,
       CASE WHEN count(*) = 0
            THEN 'nenhuma rubrica de adicional nesta base — em producao isso e esperado, '
                 || 'e o caso DEC13-023 segue como "sem dado para conferir"'
            WHEN count(*) FILTER (WHERE incide_13) = count(*)
            THEN count(*)::text || ' rubrica(s) de adicional, todas integrando o 13o'
            ELSE (count(*) - count(*) FILTER (WHERE incide_13))::text
                 || ' rubrica(s) de adicional FORA da base do 13o — marque-as como integrantes '
                 || '(Sumulas 60, 132 e 139 do TST)' END AS erro_tecnico
  FROM public.folha_rubricas
 WHERE tipo = 'PROVENTO'
   AND (descricao ILIKE '%noturn%' OR descricao ILIKE '%insalubr%' OR descricao ILIKE '%periculos%');
