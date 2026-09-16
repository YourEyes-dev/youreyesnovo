-- =========================================================
-- Remove as admissões órfãs do ambiente de teste
--
-- DECISÃO DO DONO DO PRODUTO (03/09/2026): remover.
--
-- O QUE SÃO: 10 admissões apontando para o tenant
-- a9b23784-5e5c-4f54-a71c-f1168e02771b, que NÃO EXISTE na tabela de
-- empresas. Entraram pela migration 20260504020722, que faz
-- SET session_replication_role = 'replica' — desligando a checagem de
-- chave estrangeira —, insere os registros e religa. Nenhuma migration
-- cria essa empresa. Resultado: desde 04/05 existem colaboradores de
-- uma empresa que nunca existiu, e que por isso não podem receber folha
-- (folha_rubricas, folha_periodos e folha_lancamentos exigem empresa).
--
-- ESCOPO: só as ADMISSÕES órfãs e os registros que dependem delas.
-- A base de Ponto do mesmo tenant fantasma (ponto_diario, ponto_marcacoes
-- e afins, cerca de 1.400 linhas) NÃO é tocada aqui: não foi o que se
-- pediu, é de outro módulo e pode estar servindo a testes do Ponto.
-- Fica registrada no aviso final, com a consulta para quem decidir depois.
--
-- RESGUARDO: antes de apagar, as linhas são copiadas para tabelas
-- backup_*_20260903. O comando que desfaz está no comentário do fim.
--
-- ONDE RODA: só fora da produção. Migrations não chegam à produção e,
-- além disso, este arquivo se recusa a rodar se app_config apontar para
-- lá. NÃO faz parte de nenhum script de entrega.
-- =========================================================

SET lock_timeout = '10s';

DO $orfas$
DECLARE
    v_url   TEXT;
    v_qtd   INT;
    v_ponto INT;
BEGIN
    SELECT valor INTO v_url FROM public.app_config WHERE chave = 'supabase_url';
    IF v_url IS NOT NULL AND v_url LIKE '%diayjpsrcerycycyaxst%' THEN
        RAISE WARNING 'Remoção de admissões órfãs RECUSADA: este banco é o de produção.';
        RETURN;
    END IF;

    -- Quem são (nenhuma linha = nada a fazer, e o arquivo é idempotente).
    CREATE TEMP TABLE IF NOT EXISTS _orfas ON COMMIT DROP AS
    SELECT a.id
      FROM public.admissoes a
     WHERE NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id = a.tenant_id);

    SELECT count(*) INTO v_qtd FROM _orfas;
    IF v_qtd = 0 THEN
        RAISE NOTICE 'Não há admissões órfãs neste banco — nada a remover.';
        RETURN;
    END IF;

    RAISE NOTICE 'Admissões órfãs encontradas: %. Copiando antes de apagar.', v_qtd;

    -- ── Resguardo: copia tudo que será apagado ───────────────────────
    CREATE TABLE IF NOT EXISTS public.backup_admissoes_orfas_20260903 AS
    SELECT a.* FROM public.admissoes a WHERE a.id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_admissao_documentos_orfas_20260903 AS
    SELECT d.* FROM public.admissao_documentos d WHERE d.admissao_id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_admissao_workflow_orfas_20260903 AS
    SELECT w.* FROM public.admissao_workflow w WHERE w.admissao_id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_admissao_historico_orfas_20260903 AS
    SELECT h.* FROM public.admissao_historico h WHERE h.admissao_id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_desligamento_eventos_orfas_20260903 AS
    SELECT e.* FROM public.desligamento_eventos e WHERE e.admissao_id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_onboarding_processos_orfas_20260903 AS
    SELECT o.* FROM public.onboarding_processos o WHERE o.admissao_id IN (SELECT id FROM _orfas);

    CREATE TABLE IF NOT EXISTS public.backup_contratos_experiencia_orfas_20260903 AS
    SELECT c.* FROM public.contratos_experiencia c WHERE c.admissao_id IN (SELECT id FROM _orfas);

    -- ── Dependentes que NÃO caem sozinhos (chave sem CASCADE) ────────
    -- Sem apagar estes primeiro, o DELETE das admissões seria recusado.
    DELETE FROM public.onboarding_processos WHERE admissao_id IN (SELECT id FROM _orfas);
    DELETE FROM public.contratos_experiencia WHERE admissao_id IN (SELECT id FROM _orfas);

    -- Referências que apenas ficariam nulas: zeradas de forma explícita,
    -- para o efeito ficar no registro em vez de acontecer por baixo.
    UPDATE public.departamentos SET gestor_admissao_id = NULL
     WHERE gestor_admissao_id IN (SELECT id FROM _orfas);
    UPDATE public.departamentos SET gestor_substituto_admissao_id = NULL
     WHERE gestor_substituto_admissao_id IN (SELECT id FROM _orfas);
    UPDATE public.estrategia_organograma SET colaborador_id = NULL
     WHERE colaborador_id IN (SELECT id FROM _orfas);

    -- ── A remoção (documentos, workflow, histórico e eventos de
    --    desligamento caem em cascata, já copiados acima) ────────────
    DELETE FROM public.admissoes WHERE id IN (SELECT id FROM _orfas);
    GET DIAGNOSTICS v_qtd = ROW_COUNT;
    RAISE NOTICE 'Admissões órfãs removidas: %.', v_qtd;

    -- ── O que sobrou do mesmo tenant fantasma ────────────────────────
    SELECT count(*) INTO v_ponto
      FROM public.ponto_diario p
     WHERE NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id = p.tenant_id);

    IF v_ponto > 0 THEN
        RAISE NOTICE 'Continua existindo base de Ponto sob empresa inexistente (% dia(s) em ponto_diario, e tabelas ponto_* irmãs). Não foi tocada de propósito — decisão separada.', v_ponto;
    END IF;
END $orfas$;

-- ── Como desfazer, se preciso ────────────────────────────────────────
-- Restaura na ordem: admissões primeiro, dependentes depois.
--
--   INSERT INTO public.admissoes
--   SELECT * FROM public.backup_admissoes_orfas_20260903
--   ON CONFLICT (id) DO NOTHING;
--
--   INSERT INTO public.admissao_documentos
--   SELECT * FROM public.backup_admissao_documentos_orfas_20260903
--   ON CONFLICT (id) DO NOTHING;
--
--   (idem para backup_admissao_workflow_..., backup_admissao_historico_...,
--    backup_desligamento_eventos_..., backup_onboarding_processos_... e
--    backup_contratos_experiencia_...)
--
-- Atenção: as admissões só voltam se a empresa a9b23784-... existir, ou
-- com a checagem de chave estrangeira desligada — que foi o que criou o
-- problema. O certo, se um dia forem necessárias, é criar a empresa antes.
