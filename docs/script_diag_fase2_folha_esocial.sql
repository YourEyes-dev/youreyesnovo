-- ============================================================================
-- FASE 2 — DIAGNÓSTICO (SOMENTE LEITURA) — o débito errado já saiu para
-- folha ou eSocial? A reapuração é recálculo limpo ou correção formal?
-- Seguro em PRODUÇÃO: não altera nada. Cole no SQL Editor de PRODUÇÃO.
--
-- O que o mapa do sistema mostrou: um débito errado do banco só é "capturado"
-- rio abaixo em UM lugar persistido — o ESPELHO congelado no fechamento
-- (ponto_espelhos.total_debitos_minutos) — e se propaga para o Saldo Anterior
-- do mês seguinte. A folha (folha_lancamentos) NÃO puxa banco de horas, e
-- NENHUM evento eSocial carrega o débito. Este diagnóstico confirma isso caso a
-- caso e dá o veredito da reapuração.
--
-- Colunas:
--   foto_deb / foto_saldo   = ponto_banco_horas do mês (o que está gravado)
--   mes_fechado             = a competência está fechada (e não reaberta)?
--   espelho_status/_deb     = espelho congelado e o débito nele
--   espelho_assinado        = colaborador deu ciência (confirmado/ressalva)?
--   folha_exports           = nº de exportações de folha geradas no mês
--                             (não guardam o valor do débito — só provam que
--                              houve exportação)
--   folha_lanc_banco        = lançamentos de folha do CPF vindos do banco/ponto
--                             (ESPERADO 0 — não há ponte)
--   esocial_enviado         = eventos eSocial transmitidos do CPF no mês
--                             (ESPERADO: nada que carregue o débito)
--   prox_anterior           = Saldo Anterior do mês seguinte (mostra se o
--                             número errado já escorreu para frente)
--   VEREDITO                = RECALCULO LIMPO | REABRIR E REAPURAR |
--                             CORRECAO FORMAL, + alerta se houver folha/eSocial
-- ============================================================================

WITH alvo(cpf, quem) AS (
  VALUES ('07154201940','Leticia'), ('08594914989','Luciana'),
         ('11762645912','Luciani'), ('11289974950','Paulo'),
         ('06153113931','Adriana'), ('01416068198','Cleciane'),
         ('09332971900','Marina'),  ('07444157995','Fabieli')
),
comp(c) AS (VALUES ('2026-07'), ('2026-08'), ('2026-09'))
SELECT
  alvo.quem,
  comp.c AS competencia,
  b.debitos_minutos    AS foto_deb,
  b.saldo_atual_minutos AS foto_saldo,
  (fj.status = 'fechado' AND fj.reaberto_em IS NULL) AS mes_fechado,
  e.status              AS espelho_status,
  e.total_debitos_minutos AS espelho_deb,
  (e.status IN ('confirmado','ressalva') OR e.data_confirmacao IS NOT NULL) AS espelho_assinado,
  (SELECT count(*) FROM public.ponto_exportacoes_folha x
     WHERE x.tenant_id = b.tenant_id AND x.competencia = comp.c) AS folha_exports,
  (SELECT count(*) FROM public.folha_lancamentos fl
     JOIN public.folha_periodos fp ON fp.id = fl.periodo_id
     WHERE fl.tenant_id = b.tenant_id AND fp.competencia = comp.c
       AND regexp_replace(COALESCE(fl.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
       AND (COALESCE(fl.origem,'')            ILIKE '%banco%'
         OR COALESCE(fl.origem,'')            ILIKE '%ponto%'
         OR COALESCE(fl.rubrica_descricao,'') ILIKE '%banco%')) AS folha_lanc_banco,
  (SELECT string_agg(t.tipo_evento || ':' || t.status, ', ')
     FROM public.esocial_transmissoes t
     WHERE t.tenant_id = b.tenant_id AND t.competencia = comp.c
       AND regexp_replace(COALESCE(t.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
       AND t.status IN ('enviado','processado')) AS esocial_enviado,
  (SELECT b2.saldo_anterior_minutos FROM public.ponto_banco_horas b2
     WHERE b2.tenant_id = b.tenant_id
       AND regexp_replace(COALESCE(b2.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
       AND b2.competencia = to_char(to_date(comp.c||'-01','YYYY-MM-DD') + INTERVAL '1 month','YYYY-MM')
     LIMIT 1) AS prox_anterior,
  CASE
    WHEN fj.status = 'fechado' AND fj.reaberto_em IS NULL
         AND (e.status IN ('confirmado','ressalva') OR e.data_confirmacao IS NOT NULL)
      THEN 'CORRECAO FORMAL (mes fechado + espelho assinado)'
    WHEN fj.status = 'fechado' AND fj.reaberto_em IS NULL
      THEN 'REABRIR E REAPURAR (mes fechado, espelho sem ciencia)'
    ELSE 'RECALCULO LIMPO (mes aberto)'
  END
  || CASE WHEN (SELECT count(*) FROM public.folha_lancamentos fl
                  JOIN public.folha_periodos fp ON fp.id = fl.periodo_id
                  WHERE fl.tenant_id = b.tenant_id AND fp.competencia = comp.c
                    AND regexp_replace(COALESCE(fl.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
                    AND (COALESCE(fl.origem,'') ILIKE '%banco%'
                      OR COALESCE(fl.origem,'') ILIKE '%ponto%'
                      OR COALESCE(fl.rubrica_descricao,'') ILIKE '%banco%')) > 0
          THEN ' + ALERTA FOLHA' ELSE '' END
  || CASE WHEN (SELECT count(*) FROM public.esocial_transmissoes t
                  WHERE t.tenant_id = b.tenant_id AND t.competencia = comp.c
                    AND regexp_replace(COALESCE(t.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
                    AND t.status IN ('enviado','processado')) > 0
          THEN ' + ALERTA ESOCIAL' ELSE '' END
    AS veredito
FROM comp
CROSS JOIN alvo
LEFT JOIN public.ponto_banco_horas b
  ON regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
 AND b.competencia = comp.c
LEFT JOIN LATERAL (
  SELECT f.status, f.data_fechamento, f.reaberto_em
  FROM public.ponto_fechamentos f
  WHERE f.tenant_id = b.tenant_id AND f.competencia = comp.c
    AND (f.empresa_id = b.empresa_id OR b.empresa_id IS NULL)
  ORDER BY f.data_fechamento DESC NULLS LAST
  LIMIT 1
) fj ON true
LEFT JOIN public.ponto_espelhos e
  ON e.tenant_id = b.tenant_id
 AND regexp_replace(COALESCE(e.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
 AND e.competencia = comp.c
ORDER BY alvo.quem, comp.c;
