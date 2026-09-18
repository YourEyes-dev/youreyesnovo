-- ============================================================================
-- ENTREGA — regrava a jornada das escalas cujo intervalo e DECLARADO
--
-- Companheiro do pacote da jornada prevista (script_ponto_jornada_desconta_
-- pre_assinalacao.sql). Aquele corrige o MOTOR; este corrige o NUMERO GRAVADO
-- na escala, que o motor nao usa quando ha configuracao por dia, mas que vaza
-- para dois lugares que importam:
--
--   1. O AEJ (Arquivo Eletronico de Jornada, Portaria MTP 671/2021): o
--      registro Tipo 4 "Horarios contratuais" carrega a carga diaria. Uma
--      escala de 9h por dia declarada como 9h48 no arquivo legal e um erro
--      de conformidade, nao um detalhe de tela.
--   2. A base da cobertura por atestado e do teto diario (RN17), quando os
--      blocos previstos do dia nao estao disponiveis.
--
-- A CAUSA e a mesma do outro pacote: a tela somava a JANELA CRUA quando o
-- almoco nao era batido, ignorando o intervalo declarado por pre-assinalacao.
-- Escala de segunda a quinta das 08:00 as 18:00 e sexta das 08:00 as 17:00,
-- com 60 minutos declarados, ficou gravada como 588 minutos por dia (9h48) e
-- 49h por semana, quando o contratado sao 528 (9h) e 44h — o teto do art. 7,
-- XIII da Constituicao.
--
-- QUEM E TOCADO, e so isso: escalas que (a) tem configuracao por dia, (b) tem
-- uma declaracao de pre-assinalacao VIGENTE hoje, e (c) cujo numero gravado
-- realmente difere do que a conta correta devolve. Escala sem declaracao NAO
-- e tocada: ali a janela crua e mesmo a jornada, e mexer seria inventar um
-- intervalo que ninguem declarou.
--
-- A GUARDA DA VERSAO. A tabela tem um gatilho que arquiva os parametros
-- antigos quando a jornada muda, com vigencia ate ontem — e a apuracao de
-- datas passadas passa a ler esse arquivo. Isso existe para edicao de
-- verdade (a escala mudou a partir de tal dia). Aqui NAO houve mudanca de
-- contrato: o contrato sempre foi 9h, o sistema e que guardava a conta
-- errada. Arquivar "9h48 vigorou ate ontem" afirmaria sobre o passado uma
-- coisa que nunca foi verdade, e num arquivo que alimenta a apuracao. Por
-- isso o gatilho e suspenso durante a regravacao e religado no mesmo bloco.
-- Se algo falhar no meio, o tratador de erro desfaz tudo o que o bloco fez —
-- o gatilho volta ligado junto, e nenhuma escala fica alterada.
--
-- RESGATE. A producao nao tem Point-in-Time Recovery, entao as linhas sao
-- copiadas ANTES para backup_ponto_escalas_20260916 (copia integral da
-- tabela — ela e pequena e o resgate fica trivial). O comando que desfaz
-- esta no rodape deste arquivo. Rodar duas vezes nao duplica nem desfaz: a
-- copia so e criada se ainda nao existir, e o UPDATE so alcanca linhas cujo
-- valor gravado ainda diverge.
--
-- Idempotente. Roda inteiro em UMA transacao.
-- CLT art. 71, par. 2; Sumula 338, III do TST; Portaria MTP 671/2021.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Guarda as linhas antes de qualquer escrita.
--
-- Fica FORA do bloco abaixo de proposito, e por dois motivos. Primeiro: se o
-- bloco tropecar, o tratador de erro desfaz tudo o que aconteceu DENTRO dele —
-- inclusive a copia — e a conferencia do rodape, que se apoia nela, terminaria
-- num erro feio em vez de dizer o que houve. Segundo: aqui a copia existe
-- mesmo no ambiente que ainda nao tem a pre-assinalacao, e assim a conferencia
-- nunca precisa nomear aquela tabela.
CREATE TABLE IF NOT EXISTS public.backup_ponto_escalas_20260916 AS
  SELECT * FROM public.ponto_escalas;

DO $fix$
DECLARE
  v_afetadas    int := 0;
  v_tem_gatilho boolean;
BEGIN
  -- Zera o recado de erro: a conferencia do rodape le esta chave para saber se
  -- a regravacao passou ou tropecou. Sem isso, um tropeco viraria um "OK"
  -- silencioso — o pior desfecho possivel para um script que mexe em dado.
  PERFORM set_config('ponto.regrava_erro', '', false);

  IF to_regclass('public.ponto_pre_assinalacao') IS NULL THEN
    RAISE NOTICE 'PULADO — este ambiente ainda nao tem a tabela ponto_pre_assinalacao (pacote 18 da fila do Ponto, Onda 4 parte 3). Sem declaracoes nao ha o que regravar. Nenhuma linha foi tocada.';
    RETURN;
  END IF;

  -- (2) Suspende o arquivamento de versao: ver "A GUARDA DA VERSAO" no topo.
  --     Só mexe no gatilho se ele existir: ambiente que ainda nao recebeu o
  --     versionamento de escala (Onda 1) nao tem esse gatilho, e um ALTER
  --     TABLE cego derrubaria a regravacao inteira por um detalhe que, ali,
  --     nem se aplica — sem gatilho nao ha versao falsa a evitar.
  v_tem_gatilho := EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid = 'public.ponto_escalas'::regclass
       AND tgname  = 'trg_ponto_escala_arquiva_versao');

  IF v_tem_gatilho THEN
    EXECUTE 'ALTER TABLE public.ponto_escalas DISABLE TRIGGER trg_ponto_escala_arquiva_versao';
  END IF;

  -- (3) Regrava jornada diaria e semanal exatamente como a tela passa a
  --     calcular: a janela do dia menos o intervalo que couber (batido tem
  --     precedencia sobre declarado), mais a media semanal das compensacoes
  --     mensais no campo semanal.
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
             SUM(p.min_novo)::int  AS semanal_novo,
             SUM(p.min_velho)::int AS semanal_velho,
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

  -- (4) Religa o arquivamento de versao para as edicoes de verdade.
  IF v_tem_gatilho THEN
    EXECUTE 'ALTER TABLE public.ponto_escalas ENABLE TRIGGER trg_ponto_escala_arquiva_versao';
  END IF;

  IF v_afetadas = 0 THEN
    RAISE NOTICE 'Nada a regravar — nenhuma escala com declaracao vigente estava com a jornada inflada (ou ja foram todas corrigidas).';
  ELSE
    RAISE NOTICE 'Escalas regravadas: %.', v_afetadas;
  END IF;

EXCEPTION WHEN OTHERS THEN
  -- O tratador desfaz tudo o que este bloco fez, o gatilho de versao volta
  -- junto e nenhuma escala e alterada. O recado fica registrado para a
  -- conferencia do rodape nao anunciar um "OK" que nao houve.
  PERFORM set_config('ponto.regrava_erro', SQLERRM, false);
  RAISE NOTICE 'FALHOU a regravacao das escalas (nada foi alterado): %', SQLERRM;
END $fix$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado num ambiente em dia:   t | t | t | 1 (ou mais) | OK
-- Esperado num ambiente atrasado: f | t | t | 0            | PULADO ...
--
--   tem_declaracao  : o ambiente tem a tabela de pre-assinalacao. Em "f" o
--                     arquivo se recusou de proposito e NADA foi alterado.
--   backup_guardado : a copia de resgate existe (ver rodape para desfazer).
--   gatilho_religado: o arquivamento de versao voltou a valer. Tem de ser "t"
--                     — se ficasse desligado, edicoes de escala deixariam de
--                     congelar os parametros antigos e a apuracao de datas
--                     passadas passaria a usar os novos.
--   regravadas      : escalas cujo numero gravado mudou em relacao a copia.
--
-- Se a regravacao tropecar em algum dado, a transacao do bloco volta atras
-- sozinha (nenhuma escala alterada, gatilho religado) e a ultima coluna sai
-- comecando com FALHOU e o motivo tecnico — nunca um OK silencioso.
--
-- Esta conferencia nao nomeia a tabela de pre-assinalacao: le so o catalogo e
-- a copia de resgate, para tambem funcionar onde a fila do Ponto ainda nao
-- chegou. A conferencia detalhada, escala por escala, esta no roteiro.
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (to_regclass('public.ponto_pre_assinalacao') IS NOT NULL)         AS tem_declaracao,
    (to_regclass('public.backup_ponto_escalas_20260916') IS NOT NULL) AS backup_guardado,
    COALESCE((SELECT tgenabled = 'O' FROM pg_trigger
               WHERE tgrelid = 'public.ponto_escalas'::regclass
                 AND tgname  = 'trg_ponto_escala_arquiva_versao'), true) AS gatilho_religado,
    NULLIF(COALESCE(current_setting('ponto.regrava_erro', true), ''), '')  AS tropecou_com,
    (SELECT count(*)
       FROM public.ponto_escalas e
       JOIN public.backup_ponto_escalas_20260916 b ON b.id = e.id
      WHERE e.jornada_diaria_minutos  IS DISTINCT FROM b.jornada_diaria_minutos
         OR e.jornada_semanal_minutos IS DISTINCT FROM b.jornada_semanal_minutos) AS regravadas
)
SELECT tem_declaracao, backup_guardado, gatilho_religado, regravadas,
       CASE
         WHEN tropecou_com IS NOT NULL
           THEN 'FALHOU (nada foi alterado): ' || tropecou_com
         WHEN NOT tem_declaracao
           THEN 'PULADO — ambiente sem pre-assinalacao, nada foi alterado'
         WHEN NOT gatilho_religado
           THEN 'CONFERIR — o gatilho de versao ficou desligado'
         WHEN NOT backup_guardado
           THEN 'CONFERIR — a copia de resgate nao foi criada'
         ELSE 'OK'
       END AS erro_tecnico
FROM x;

-- ---------------------------------------------------------------------------
-- COMO DESFAZER (se for preciso). Devolve so as escalas tocadas, sem mexer
-- em nada que tenha sido alterado legitimamente depois:
--
--   UPDATE public.ponto_escalas e
--      SET jornada_diaria_minutos  = b.jornada_diaria_minutos,
--          jornada_semanal_minutos = b.jornada_semanal_minutos
--     FROM public.backup_ponto_escalas_20260916 b
--    WHERE e.id = b.id
--      AND (e.jornada_diaria_minutos  IS DISTINCT FROM b.jornada_diaria_minutos
--        OR e.jornada_semanal_minutos IS DISTINCT FROM b.jornada_semanal_minutos);
--
-- A copia pode ser apagada depois de algumas semanas de tranquilidade:
--   DROP TABLE public.backup_ponto_escalas_20260916;
-- ---------------------------------------------------------------------------
