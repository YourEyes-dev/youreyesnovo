-- ============================================================================
-- PGP-014 (raiz) — a sugestão de parceiros ordenava DEPOIS do LIMIT.
--
-- `parceiros_sugerir_para_lead` montava a lista assim:
--     SELECT ... FROM parceiros WHERE ... LIMIT 5   -- sem ORDER BY!
-- e só então ordenava esses 5 por prioridade dentro do jsonb_agg. Com poucos
-- parceiros (réplica local) os 5 cabiam e o de "mesma cidade" aparecia; com
-- muitos parceiros (produção/staging real), o LIMIT 5 recortava um conjunto
-- ARBITRÁRIO — o parceiro certo (mesma cidade) podia ficar de fora e um de
-- "mesmo estado" surgia em 1º. Foi exatamente o que o PGP-014 flagrou no
-- staging (1º = "Clínica Staging SST", motivo "Mesmo estado").
--
-- Correção: ordenar por prioridade (mesma cidade > mesmo estado > distância,
-- e, dentro da faixa, nível melhor) ANTES do LIMIT, para o corte pegar os 5
-- MELHORES, não 5 quaisquer. Regra de negócio de fato: a sugestão sempre
-- devolve os parceiros mais próximos primeiro, mesmo com a base cheia.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.parceiros_sugerir_para_lead(_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_l record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT cidade, uf INTO v_l FROM public.leads WHERE id = _lead_id;
  RETURN coalesce((SELECT jsonb_agg(x ORDER BY ord_prioridade, ord_nome) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'nome', p.nome, 'tipo_parceiro', p.tipo_parceiro, 'cidade', p.cidade, 'uf', p.uf,
      'nivel', n.nome, 'clientes', (SELECT count(*) FROM public.tenants t WHERE t.parceiro_id = p.id),
      'motivo', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN 'Mesma cidade'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN 'Mesmo estado'
        ELSE 'Atende à distância' END,
      'prioridade', CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN '1'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN '2' ELSE '3' END
        || lpad((9 - coalesce(n.ordem, 0))::text, 2, '0')
    ) AS x,
    -- Mesma chave de prioridade, agora usada para ORDENAR ANTES DO LIMIT:
    (CASE
        WHEN v_l.cidade IS NOT NULL AND lower(unaccent_safe(p.cidade)) = lower(unaccent_safe(v_l.cidade)) AND upper(p.uf) = upper(v_l.uf) THEN '1'
        WHEN v_l.uf IS NOT NULL AND upper(p.uf) = upper(v_l.uf) THEN '2' ELSE '3' END
        || lpad((9 - coalesce(n.ordem, 0))::text, 2, '0')) AS ord_prioridade,
    p.nome AS ord_nome
    FROM public.parceiros p LEFT JOIN public.parceiro_niveis n ON n.id = p.nivel_id
    WHERE p.status = 'ativo' AND p.tipo_parceiro IN ('representante','implantador','clinica','contabilidade','indicador')
    ORDER BY ord_prioridade, ord_nome
    LIMIT 5) q), '[]'::jsonb);
END $fn$;
