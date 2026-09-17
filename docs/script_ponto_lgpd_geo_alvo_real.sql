-- SOMENTE LEITURA — o alvo REAL da primeira passada, pelo prazo de cada cliente.
-- A medicao anterior simulou 180 dias para todo mundo. A rotina nao faz isso:
-- ela le o prazo configurado de CADA cliente. Onde alguem ja tiver configurado
-- um prazo mais curto, o alcance e maior do que aquela simulacao mostrou.
SELECT
  COALESCE(substring((SELECT valor FROM public.app_config WHERE chave = 'supabase_url')
                     FROM 'https?://([a-z0-9]+)\.'), '(sem supabase_url)')  AS projeto,
  count(*)                                              AS clientes_configurados,
  count(*) FILTER (WHERE rc.ativo)                      AS ativos,
  min(rc.geolocalizacao_dias)                           AS menor_prazo,
  max(rc.geolocalizacao_dias)                           AS maior_prazo,
  COALESCE(sum(CASE WHEN rc.ativo THEN (
    SELECT count(*) FROM public.ponto_marcacoes m
     WHERE m.tenant_id = rc.tenant_id
       AND m.data_marcacao < CURRENT_DATE - rc.geolocalizacao_dias
       AND (m.latitude IS NOT NULL OR m.longitude IS NOT NULL
            OR m.endereco_geolocalizacao IS NOT NULL)) ELSE 0 END), 0)
                                                        AS alvo_real_1a_passada,
  CASE WHEN min(rc.geolocalizacao_dias) < 180
       THEN 'ATENCAO — ha cliente com prazo menor que 180 dias; o alcance real e maior que a simulacao'
       ELSE 'OK' END                                    AS erro_tecnico
FROM public.ponto_retencao_config rc;
