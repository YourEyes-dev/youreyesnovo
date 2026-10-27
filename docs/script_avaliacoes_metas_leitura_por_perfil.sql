-- ============================================================================
-- ENTREGA — Avaliacoes e metas: leitura por perfil (DASH-PERFIL-01)
-- Cole no SQL Editor (TESTE/HOMOLOGACAO primeiro; depois PRODUCAO, so apos "aprovado").
-- UMA transacao, idempotente. Cria apenas politicas RESTRICTIVE de SELECT.
-- NAO altera dado, NAO cria tabela (por isso nao aciona o auto-RLS do editor nem
-- precisa de backup). Cada tabela e atomica: se uma falhar, so ela fica de fora.
--
-- O QUE FECHA: a Central de Pendencias e os blocos da tela inicial mostravam nome
-- do colaborador + avaliacoes/metas a qualquer membro da empresa (o filtro por
-- perfil daquelas telas e cosmetico; so a RLS protege). Passa a valer:
--   avaliacao_respostas  modulo 'avaliacoes' amplo OU o proprio avaliador (preserva
--                        a "Minha Caixa" de avaliacoes/360 de quem nao tem o modulo).
--   avaliacao_9box       modulo 'avaliacoes' amplo (calibracao de gestao).
--   metas                modulo 'avaliacoes'/'metas' amplo OU a propria meta
--                        individual (colaborador_id -> admissoes por CPF).
-- Superadmin/dono ficam acima; sem perfil vinculado vale o legado por papel/tipo;
-- com perfil, o escopo amplo do modulo libera (tudo em perfil_permite_modulo). As
-- telas /avaliacoes e /metas sao gated a esses modulos no front, entao quem chega
-- nelas passa. Nao ha VIEW sobre estas tabelas; a politica na base ja protege.
--
-- Rode ANTES, se quiser, a consulta_avaliacoes_metas_leitura.sql (so leitura).
-- Termina com UMA conferencia SELECT.
-- ============================================================================
SET lock_timeout = '10s';

DO $av$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('avaliacao_respostas',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes')
          OR avaliador_id = auth.uid()$p$),

      ('avaliacao_9box',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes')$p$),

      ('metas',
       $p$public.perfil_permite_modulo(tenant_id, 'avaliacoes', 'metas')
          OR (metas.colaborador_id IS NOT NULL
              AND public.cpf_do_usuario_logado() <> ''
              AND EXISTS (
                    SELECT 1 FROM public.admissoes a
                     WHERE a.id::text = metas.colaborador_id
                       AND a.tenant_id = metas.tenant_id
                       AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
                           = public.cpf_do_usuario_logado()))$p$)
    ) AS t(tabela, predicado)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Avaliacoes/Metas: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela);
      EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING (%s)',
                     'perfil_restringe_leitura_' || r.tabela, r.tabela, r.predicado);
      RAISE NOTICE 'Avaliacoes/Metas: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a camada de leitura por perfil: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $av$;

-- ── Conferencia final (o editor mostra so o ultimo resultado) ────────────────
-- Esperado: OK (RESTRICTIVE/SELECT) nas tres primeiras; afastamentos* ja vinham OK
-- (entrega de 23/10). Qualquer "FALTA" indica que a tabela ficou sem a camada.
SELECT t.tabela,
       CASE WHEN to_regclass('public.' || t.tabela) IS NULL THEN 'tabela ausente nesta base'
            WHEN p.policyname IS NULL THEN 'FALTA'
            ELSE 'OK (' || p.permissive || '/' || p.cmd || ')' END AS camada_perfil
FROM (VALUES ('avaliacao_respostas'), ('avaliacao_9box'), ('metas'),
             ('afastamentos'), ('afastamentos_pendencias')) AS t(tabela)
LEFT JOIN pg_policies p
  ON p.schemaname = 'public'
 AND p.tablename = t.tabela
 AND p.policyname = 'perfil_restringe_leitura_' || t.tabela
ORDER BY t.tabela;
