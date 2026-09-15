-- ============================================================================
-- Fase 4 — ADM-070: conclusão da admissão condicionada à assinatura do contrato.
--
-- A infraestrutura de assinatura já existe (contratos_assinaturas). Aqui a
-- finalização da admissão pelo candidato (finalizar_admissao_by_token, o caminho
-- da tela de onboarding) passa a exigir que não haja contrato PENDENTE de
-- assinatura para o CPF: contrato aguardando assinatura trava o avanço até a
-- ciência das partes (arts. 29/442). Não bloqueia quando não há assinatura
-- pendente (fluxo atual segue), então não quebra o onboarding em produção.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.finalizar_admissao_by_token(_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_cpf text;
BEGIN
  SELECT cpf INTO v_cpf FROM public.admissoes WHERE onboarding_token = _token;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token inválido' USING ERRCODE = '42501';
  END IF;

  -- Gate de assinatura: contrato pendente de assinatura (link enviado, ainda
  -- sem assinado_em e dentro do prazo) trava a conclusão até a assinatura.
  IF EXISTS (
    SELECT 1 FROM public.contratos_assinaturas ca
     WHERE regexp_replace(COALESCE(ca.signatario_cpf, ''), '[^0-9]', '', 'g')
         = regexp_replace(COALESCE(v_cpf, ''), '[^0-9]', '', 'g')
       AND ca.assinado_em IS NULL
       AND ca.link_enviado_em IS NOT NULL
       AND (ca.expira_em IS NULL OR ca.expira_em > now())
  ) THEN
    RAISE EXCEPTION 'Contrato pendente de assinatura: conclua a assinatura do contrato antes de finalizar a admissão.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.admissoes
     SET onboarding_status = 'em_analise',
         status = 'em_analise',
         updated_at = now()
   WHERE onboarding_token = _token;
END;
$$;

COMMENT ON FUNCTION public.finalizar_admissao_by_token(uuid) IS
  'ADM-070: finalizacao do onboarding condicionada a assinatura do contrato (contratos_assinaturas sem pendencia).';
