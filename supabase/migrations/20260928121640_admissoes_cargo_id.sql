-- ============================================================================
-- O2-A: vínculo canônico colaborador -> cargo em admissoes.cargo_id
--
-- Contexto: o colaborador (admissoes) guarda o cargo como TEXTO livre
-- (admissoes.cargo). O envio de manual para assinatura casa colaborador x cargo
-- por comparação de string do nome — qualquer divergência de grafia/acentuação
-- faz o colaborador sumir da lista. Esta coluna cria a chave canônica para a
-- tela filtrar por id (com fallback ao texto) e para o match do Mapa (Onda 3).
--
-- Aditivo/idempotente: adiciona a coluna, o índice e faz backfill apenas dos
-- casos INEQUÍVOCOS (exatamente 1 cargo com o mesmo nome no tenant/empresa).
-- Ambíguos e sem correspondência ficam NULL (corrigíveis na tela do colaborador).
-- Só preenche uma coluna NOVA — não altera dado existente; reversão: SET NULL.
-- ============================================================================

SET lock_timeout = '10s';

ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS cargo_id uuid REFERENCES public.cargos(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_admissoes_cargo_id ON public.admissoes (cargo_id);

-- Backfill: resolve cargo_id pelo nome (case-insensitive, sem espaços nas pontas),
-- escopado por tenant e compatível com a empresa. Só atribui quando há
-- EXATAMENTE UM cargo correspondente (evita escolher arbitrariamente em duplicidade).
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
