-- ============================================================================
-- AGOSTO/2026 AINDA ESTA ABERTO? — a checagem antes de reconciliar
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA.
--
-- POR QUE ESTA CHECAGEM VEM PRIMEIRO
-- A correcao do minuto (PONTO-470) so alcanca dias JA GRAVADOS se a apuracao
-- diaria for refeita (reconsolidada). O fechamento e o espelho leem a hora
-- GRAVADA em ponto_diario — nao recalculam das marcacoes. Entao:
--   * se agosto ainda esta ABERTO, reconciliar e barato: reconsolida antes de
--     fechar, e os espelhos ja saem com o minuto certo. Sem reabrir nada, sem
--     recolher ciencia de novo;
--   * se agosto ja FECHOU em alguem, aquele grupo entra no caminho caro
--     (reabrir + reconsolidar + reemitir espelho + nova ciencia).
--
-- Esta consulta diz, empresa por empresa, em qual dos dois casos cada uma
-- esta. So depois de ler o resultado se decide o que reconciliar.
--
-- COMO LER
--   * fechamentos_fechados = 0 e espelhos_com_ciencia = 0  -> ABERTO, caminho barato
--   * qualquer um > 0                                      -> ha parte fechada, conferir
-- ============================================================================

WITH p AS MATERIALIZED (SELECT '2026-08'::text AS competencia),
fech AS MATERIALIZED (
  SELECT e.id AS empresa_id,
         COALESCE(e.nome_fantasia, e.razao_social) AS empresa,
         (SELECT count(*) FROM public.ponto_fechamentos f, p
           WHERE f.tenant_id = e.tenant_id
             AND f.competencia = p.competencia
             AND f.status = 'fechado'
             AND (f.empresa_id IS NULL OR f.empresa_id = e.id))       AS fechamentos_fechados,
         (SELECT count(*) FROM public.ponto_espelhos es, p
           WHERE es.tenant_id = e.tenant_id
             AND es.competencia = p.competencia
             AND es.empresa_id = e.id
             AND (COALESCE(es.status, '') IN ('confirmado', 'assinado')
                  OR es.data_confirmacao IS NOT NULL
                  OR COALESCE(es.assinatura_hash, '') <> ''))          AS espelhos_com_ciencia,
         (SELECT count(DISTINCT d.colaborador_cpf)
            FROM public.ponto_diario d, p
           WHERE d.tenant_id = e.tenant_id
             AND d.empresa_id = e.id
             AND to_char(d.data, 'YYYY-MM') = p.competencia
             AND EXISTS (SELECT 1 FROM public.ponto_marcacoes m
                          WHERE m.tenant_id = d.tenant_id
                            AND m.colaborador_cpf = d.colaborador_cpf
                            AND m.data_marcacao = d.data))              AS pessoas_batem_ponto
  FROM public.empresa_cadastro e
  WHERE COALESCE(e.usa_controle_ponto, false) = true
)
SELECT left(empresa, 32)                                              AS empresa,
       pessoas_batem_ponto                                            AS pessoas,
       fechamentos_fechados                                          AS fechados,
       espelhos_com_ciencia                                          AS espelhos_ok,
       CASE
         WHEN fechamentos_fechados = 0 AND espelhos_com_ciencia = 0
           THEN 'ABERTO — reconciliar antes de fechar (barato)'
         WHEN fechamentos_fechados > 0
           THEN 'FECHADO — precisa reabrir antes (caminho caro)'
         ELSE 'PARCIAL — ha espelho com ciencia, conferir'
       END                                                            AS situacao
FROM fech
WHERE pessoas_batem_ponto > 0
ORDER BY fechamentos_fechados DESC, espelhos_com_ciencia DESC, empresa;
