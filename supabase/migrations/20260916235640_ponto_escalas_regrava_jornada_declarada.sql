-- Regrava a jornada das escalas cujo intervalo e DECLARADO por pre-assinalacao.
--
-- Companheira de 20260916234512 (aquela corrige o MOTOR; esta corrige o NUMERO
-- GRAVADO na escala). O motor nao usa esse numero quando ha configuracao por
-- dia, mas ele vaza para dois lugares que importam:
--   1. o AEJ (Portaria MTP 671/2021), registro Tipo 4 "Horarios contratuais",
--      que carrega a carga diaria — declarar 9h48 onde o contrato e 9h e erro
--      de conformidade, nao detalhe de tela;
--   2. a base da cobertura por atestado e do teto diario (RN17), quando os
--      blocos previstos do dia nao estao disponiveis.
--
-- A causa e a mesma: a tela somava a JANELA CRUA quando o almoco nao era
-- batido, ignorando o intervalo declarado. Escala de segunda a quinta das
-- 08:00 as 18:00 e sexta das 08:00 as 17:00, com 60 minutos declarados, ficou
-- gravada como 588 min/dia e 49h/semana, quando o contratado sao 528 (9h) e
-- 44h — o teto do art. 7, XIII da Constituicao.
--
-- So e tocada a escala que (a) tem configuracao por dia, (b) tem declaracao
-- VIGENTE hoje e (c) cujo numero gravado difere da conta correta. Escala sem
-- declaracao NAO e tocada: ali a janela crua e mesmo a jornada.
--
-- O gatilho que arquiva versao de parametros e suspenso durante a regravacao:
-- isto nao e mudanca de contrato (o contrato sempre foi 9h), entao arquivar
-- "9h48 vigorou ate ontem" afirmaria sobre o passado algo que nunca foi
-- verdade — num arquivo que alimenta a apuracao de datas passadas.
--
-- Em banco novo nao ha escala nenhuma e nada acontece. Idempotente.
-- CLT art. 71, par. 2; Sumula 338, III do TST; Portaria MTP 671/2021.
--
-- A copia de resgate NAO e criada aqui de proposito: ela existe no script de
-- entrega, para a producao, que nao tem Point-in-Time Recovery. Migration roda
-- em banco descartavel e e reaplicada do zero.

DO $regrava$
DECLARE
  v_afetadas int := 0;
BEGIN
  IF to_regclass('public.ponto_pre_assinalacao') IS NULL
     OR to_regclass('public.ponto_escalas') IS NULL THEN
    RAISE NOTICE 'ponto: regravacao de jornada pulada (tabelas ainda nao existem).';
    RETURN;
  END IF;

  EXECUTE 'ALTER TABLE public.ponto_escalas DISABLE TRIGGER trg_ponto_escala_arquiva_versao';

  EXECUTE $sql$
    WITH declaracao AS MATERIALIZED (
      SELECT DISTINCT ON (pa.escala_id) pa.escala_id, pa.intervalo_minutos
        FROM public.ponto_pre_assinalacao pa
       WHERE pa.escala_id IS NOT NULL
         AND COALESCE(pa.ativa, true) = true
         AND pa.data_inicio <= CURRENT_DATE
         AND (pa.data_fim IS NULL OR pa.data_fim >= CURRENT_DATE)
       ORDER BY pa.escala_id, pa.data_inicio DESC
    ),
    por_dia AS MATERIALIZED (
      SELECT e.id,
             CASE
               WHEN NOT COALESCE((cfg->>'trabalha')::boolean, false) THEN 0
               WHEN COALESCE((cfg->>'tem_almoco')::boolean, false) THEN GREATEST(0,
                    EXTRACT(EPOCH FROM ((cfg->>'inicio_almoco')::time - (cfg->>'entrada')::time))::int/60
                  + EXTRACT(EPOCH FROM ((cfg->>'saida')::time - (cfg->>'fim_almoco')::time))::int/60)
               ELSE GREATEST(0,
                    EXTRACT(EPOCH FROM ((cfg->>'saida')::time - (cfg->>'entrada')::time))::int/60
                    - GREATEST(0, d.intervalo_minutos))
             END AS min_novo,
             CASE
               WHEN NOT COALESCE((cfg->>'trabalha')::boolean, false) THEN 0
               WHEN COALESCE((cfg->>'tem_almoco')::boolean, false) THEN GREATEST(0,
                    EXTRACT(EPOCH FROM ((cfg->>'inicio_almoco')::time - (cfg->>'entrada')::time))::int/60
                  + EXTRACT(EPOCH FROM ((cfg->>'saida')::time - (cfg->>'fim_almoco')::time))::int/60)
               ELSE GREATEST(0,
                    EXTRACT(EPOCH FROM ((cfg->>'saida')::time - (cfg->>'entrada')::time))::int/60)
             END AS min_velho
        FROM public.ponto_escalas e
        JOIN declaracao d ON d.escala_id = e.id
        CROSS JOIN LATERAL (VALUES ('segunda'),('terca'),('quarta'),('quinta'),
                                   ('sexta'),('sabado'),('domingo')) AS k(dia)
        CROSS JOIN LATERAL (SELECT e.dias_config -> k.dia) AS j(cfg)
       WHERE jsonb_typeof(e.dias_config) = 'object'
    ),
    compensacao AS MATERIALIZED (
      SELECT e.id,
             ROUND(SUM(GREATEST(0,
               EXTRACT(EPOCH FROM ((c->>'saida')::time - (c->>'entrada')::time))::int/60
               - COALESCE(NULLIF(c->>'intervalo','')::int, 0)))::numeric / 4.345)::int AS comp_min
        FROM public.ponto_escalas e
        CROSS JOIN LATERAL jsonb_array_elements(
          CASE WHEN jsonb_typeof(e.compensacoes_mensais) = 'array'
               THEN e.compensacoes_mensais ELSE '[]'::jsonb END) AS a(c)
       GROUP BY e.id
    ),
    alvo AS MATERIALIZED (
      SELECT p.id,
             SUM(p.min_novo)::int AS semanal_novo,
             COUNT(*) FILTER (WHERE p.min_novo > 0) AS dias_trab
        FROM por_dia p
       GROUP BY p.id
      HAVING SUM(p.min_velho) > SUM(p.min_novo)
         AND COUNT(*) FILTER (WHERE p.min_novo > 0) > 0
    ),
    calculado AS MATERIALIZED (
      SELECT a.id,
             ROUND(a.semanal_novo::numeric / a.dias_trab)::int AS diaria_nova,
             (a.semanal_novo + COALESCE(cp.comp_min, 0))::int  AS semanal_nova
        FROM alvo a
        LEFT JOIN compensacao cp ON cp.id = a.id
    )
    UPDATE public.ponto_escalas e
       SET jornada_diaria_minutos  = c.diaria_nova,
           jornada_semanal_minutos = c.semanal_nova
      FROM calculado c
     WHERE e.id = c.id
       AND (e.jornada_diaria_minutos  IS DISTINCT FROM c.diaria_nova
         OR e.jornada_semanal_minutos IS DISTINCT FROM c.semanal_nova)
  $sql$;

  GET DIAGNOSTICS v_afetadas = ROW_COUNT;

  EXECUTE 'ALTER TABLE public.ponto_escalas ENABLE TRIGGER trg_ponto_escala_arquiva_versao';

  RAISE NOTICE 'ponto: escalas com jornada regravada pelo intervalo declarado: %.', v_afetadas;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ponto: regravacao de jornada nao aplicada (nada foi alterado): %', SQLERRM;
END $regrava$;
