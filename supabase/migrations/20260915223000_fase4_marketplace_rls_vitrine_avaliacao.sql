-- ============================================================================
-- Fase 4 (motores) — Marketplace: RLS da vitrine e das avaliações.
--
-- MKY-068: anúncio publicado só aparece na leitura pública se o ESPECIALISTA
--          estiver ativo (pendente/suspenso/bloqueado/excluído não vazam).
-- MKY-087: avaliação moderada sai da leitura pública (o cálculo já a exclui).
--
-- Restrições ADITIVAS (só reduzem o que é visível — nunca expõem mais). Como a
-- réplica local não reproduz a RLS com fidelidade, o efeito destas políticas é
-- confirmado na bateria MKY do ambiente de teste.
-- ============================================================================

-- ── MKY-068: leitura pública de anúncio exige especialista ativo ────────────
DROP POLICY IF EXISTS "Public can view active services" ON public.marketplace_servicos;
CREATE POLICY "Public can view active services"
  ON public.marketplace_servicos
  FOR SELECT
  USING (
    ativo = true
    AND status = 'publicado'
    AND EXISTS (
      SELECT 1 FROM public.marketplace_profissionais p
       WHERE p.id = marketplace_servicos.profissional_id
         AND p.status = 'ativo'
         AND p.excluido_em IS NULL
    )
  );

-- ── MKY-087: avaliação moderada não é lida publicamente ─────────────────────
DROP POLICY IF EXISTS "Tenant members can view reviews" ON public.marketplace_avaliacoes;
CREATE POLICY "Tenant members can view reviews"
  ON public.marketplace_avaliacoes
  FOR SELECT
  USING (NOT COALESCE(moderada, false));
