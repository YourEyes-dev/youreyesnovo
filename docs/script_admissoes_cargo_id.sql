-- ============================================================================
-- ENTREGA: admissoes.cargo_id — vínculo canônico colaborador -> cargo (O2-A)
-- Equivalente à migration 20260928121640_admissoes_cargo_id.sql
-- Cole INTEIRO no SQL Editor de PRODUÇÃO. Idempotente.
--
-- Por que: o envio de manual para assinatura casa colaborador x cargo por
-- texto do nome do cargo; qualquer divergência de grafia esconde o colaborador.
-- Esta coluna cria a chave canônica; a tela passa a filtrar por id (com fallback
-- ao texto). manual_funcao_assinaturas JA persiste cargo_id — o ajuste é só na
-- SELECAO. Também habilita o match do Mapa (Onda 3) via CPF -> cargo_id.
--
-- Só CRIA coluna nova e a preenche — NAO altera dado existente (o texto em
-- admissoes.cargo fica intacto). Por isso dispensa tabela de backup; a reversão
-- é o UPDATE ... SET cargo_id = NULL no rodapé. Não cria TABELA nova, então não
-- aciona o auxiliar de RLS do editor.
-- ============================================================================

SET lock_timeout = '10s';

-- 1) Coluna canônica + índice (aditivos, idempotentes).
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS cargo_id uuid REFERENCES public.cargos(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_admissoes_cargo_id ON public.admissoes (cargo_id);

-- 2) Backfill: resolve pelo nome (case-insensitive, sem espaços nas pontas),
--    escopado por tenant e compatível com a empresa. Só atribui quando há
--    EXATAMENTE UM cargo correspondente (ambíguos ficam NULL).
UPDATE public.admissoes a
   SET cargo_id = (
     SELECT c.id
       FROM public.cargos c
      WHERE c.tenant_id = a.tenant_id
        AND lower(btrim(c.nome)) = lower(btrim(a.cargo))
        AND (c.empresa_id IS NULL OR a.empresa_id IS NULL OR c.empresa_id = a.empresa_id)
      LIMIT 1
   )
 WHERE a.cargo_id IS NULL
   AND a.cargo IS NOT NULL
   AND btrim(a.cargo) <> ''
   AND (
     SELECT count(*)
       FROM public.cargos c
      WHERE c.tenant_id = a.tenant_id
        AND lower(btrim(c.nome)) = lower(btrim(a.cargo))
        AND (c.empresa_id IS NULL OR a.empresa_id IS NULL OR c.empresa_id = a.empresa_id)
   ) = 1;

-- 3) Conferência (único resultado) + relatório de não-resolvidos.
--    pendentes_ambiguos: mesmo nome em 2+ cargos do escopo (resolver na tela).
--    pendentes_sem_match: nome não bate com nenhum cargo (corrigir grafia/cadastro).
WITH pend AS MATERIALIZED (
  SELECT a.id,
    (SELECT count(*)
       FROM public.cargos c
      WHERE c.tenant_id = a.tenant_id
        AND lower(btrim(c.nome)) = lower(btrim(a.cargo))
        AND (c.empresa_id IS NULL OR a.empresa_id IS NULL OR c.empresa_id = a.empresa_id)) AS n_match
    FROM public.admissoes a
   WHERE a.cargo_id IS NULL AND a.cargo IS NOT NULL AND btrim(a.cargo) <> ''
)
SELECT
  (SELECT count(*) FROM public.admissoes)                          AS total_admissoes,
  (SELECT count(*) FROM public.admissoes WHERE cargo_id IS NOT NULL) AS resolvidos,
  (SELECT count(*) FROM pend)                                       AS pendentes,
  (SELECT count(*) FROM pend WHERE n_match > 1)                     AS pendentes_ambiguos,
  (SELECT count(*) FROM pend WHERE n_match = 0)                     AS pendentes_sem_match;

-- Desfazer (se algum dia precisar): a coluna é nova, então basta zerá-la.
--   UPDATE public.admissoes SET cargo_id = NULL;
-- (e, se quiser remover de vez a estrutura:)
--   DROP INDEX IF EXISTS public.idx_admissoes_cargo_id;
--   ALTER TABLE public.admissoes DROP COLUMN IF EXISTS cargo_id;
