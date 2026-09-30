-- ============================================================================
-- DIAGNÓSTICO (SOMENTE LEITURA) — por que os saldos zerados em agosto voltaram
-- Seguro em PRODUÇÃO: não altera nada. Cole no SQL Editor de PRODUÇÃO.
--
-- Para cada colaborador da lista, mostra 2026-07, 2026-08 e 2026-09:
--   · foto_*        = ponto_banco_horas (o que a tela mostra na linha)
--   · oficial_saldo = ponto_banco_horas_oficial (cálculo ao vivo)
--   · fechado       = a competência está fechada? (ponto_fechamentos)
--   · movimentos    = lançamentos do mês, com ORIGEM — aqui se vê se o
--                     lançamento MANUAL de zeragem sobreviveu ou se uma nova
--                     "apuracao" reescreveu por cima
--   · diario_bruto  = soma do saldo diário ao vivo do mês (o motor)
--   · vinculo       = status da admissão / data de desligamento
--   · afast_no_mes  = há afastamento cobrindo dias do mês? (Fabieli etc.)
--
-- Leitura rápida:
--   - Se em 2026-08 o saldo_atual voltou a != 0 e os movimentos NÃO têm mais o
--     lançamento manual de zeragem => alguém reapurou agosto e o motor (ainda
--     COM o bug em produção) reescreveu.
--   - Se em 2026-09 o saldo_anterior != 0 => setembro puxou o fechamento de
--     agosto que voltou a != 0 (efeito dominó do item acima).
--   - Se aparecer débito em quem está afastado (afast_no_mes = sim) => é o bug
--     que a Fase 1 corrige (dias de afastamento viram débito).
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
  b.saldo_anterior_minutos AS foto_anterior,
  b.creditos_minutos       AS foto_cred,
  b.debitos_minutos        AS foto_deb,
  b.compensados_minutos    AS foto_comp,
  b.saldo_atual_minutos    AS foto_saldo,
  o.saldo_atual_min        AS oficial_saldo,
  EXISTS (SELECT 1 FROM public.ponto_fechamentos f
           WHERE f.tenant_id = b.tenant_id AND f.competencia = comp.c
             AND (f.empresa_id = b.empresa_id OR b.empresa_id IS NULL)) AS fechado,
  (SELECT string_agg(m.tipo || ' ' || m.minutos || 'min (' || COALESCE(m.origem,'?') || ')',
                     '  |  ' ORDER BY m.data_referencia, m.id)
     FROM public.ponto_banco_horas_movimentacoes m
     WHERE m.banco_horas_id = b.id) AS movimentos,
  COALESCE((SELECT SUM(s.saldo_min)
              FROM public.ponto_saldo_dias_competencia(b.tenant_id, b.colaborador_cpf, comp.c) s), 0)
    AS diario_bruto,
  (SELECT a.status::text || COALESCE(' / desl ' || a.data_desligamento::text, '')
     FROM public.admissoes a
     WHERE regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g') = alvo.cpf
       AND (a.empresa_id = b.empresa_id OR b.empresa_id IS NULL)
     ORDER BY a.data_admissao DESC NULLS LAST LIMIT 1) AS vinculo,
  EXISTS (SELECT 1 FROM public.afastamentos af
           WHERE regexp_replace(COALESCE(af.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
             AND af.data_inicio <= (to_date(comp.c||'-01','YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date
             AND COALESCE(af.data_fim,'infinity'::date) >= to_date(comp.c||'-01','YYYY-MM-DD')) AS afast_no_mes
FROM comp
CROSS JOIN alvo
LEFT JOIN public.ponto_banco_horas b
  ON regexp_replace(COALESCE(b.colaborador_cpf,''),'[^0-9]','','g') = alvo.cpf
 AND b.competencia = comp.c
LEFT JOIN LATERAL public.ponto_banco_horas_oficial(
  b.tenant_id, comp.c, b.empresa_id, b.colaborador_cpf) o ON true
ORDER BY alvo.quem, comp.c;
