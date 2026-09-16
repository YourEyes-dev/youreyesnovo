-- ============================================================================
-- HOMOLOGACAO (AMBIENTE DE TESTE) — folga de meio periodo e trava do dia curto
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga NADA na base.
-- Os dois casos de QA montam dados ficticios e os DESFAZEM sozinhos: rodam
-- dentro de qa_executar_descartavel, que levanta um erro controlado (QA000) so
-- para dar rollback no fixture. Nada fica gravado.
--
-- ONDE COLAR
-- No SQL Editor do projeto de TESTE (bmehdgthciuvdbvutsdv). NAO e para producao.
--
-- O QUE CONFERE
--   1) PONTO-476 — a folga de meio periodo passa a ser registravel e o espelho
--      a chama de "Folga compensatoria" (nao mais "Diminui Banco Horas").
--   2) PONTO-477 — um dia muito abaixo da jornada, sem folga/abono/ajuste
--      declarado, vira PENDENCIA critica do fechamento (nao debita o banco em
--      silencio); declarada a folga, a pendencia some.
--   3) Estrutura — o limite configuravel existe, a folga aceita minutos e a
--      trava do fechamento foi de fato ampliada (e sem o antigo "j.minutos",
--      que numa base contaminada faria a lista de pendencias quebrar).
--
-- COMO LER: a coluna "veredito" tem de sair "OK" nas tres linhas.
-- ============================================================================

WITH r476 AS MATERIALIZED (
  SELECT * FROM public.qa_executar_descartavel('qa_caso_ponto_476')
),
r477 AS MATERIALIZED (
  SELECT * FROM public.qa_executar_descartavel('qa_caso_ponto_477')
),
fn_trava AS MATERIALIZED (
  SELECT to_regprocedure('public.ponto_fechamento_pendencias_criticas(uuid,uuid,text)') AS oid
),
def_trava AS MATERIALIZED (
  SELECT COALESCE((SELECT pg_get_functiondef(oid) FROM fn_trava WHERE oid IS NOT NULL), '') AS src
),
estrutura AS MATERIALIZED (
  SELECT
    EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'ponto_configuracao'
        AND column_name = 'dia_curto_bloqueia_fechamento_minutos'
    ) AS tem_config,
    to_regprocedure('public.ponto_registrar_folga_compensatoria(uuid,text,date,text,integer)')
      IS NOT NULL AS folga_aceita_minutos,
    (SELECT position('[dia-curto-sem-motivo]' IN src) > 0 FROM def_trava) AS trava_ampliada,
    (SELECT position('j.minutos' IN src) = 0 FROM def_trava)              AS sem_bug_j_minutos
)
SELECT 1 AS ordem,
       'PONTO-476 — folga de meio periodo registravel'::text AS o_que,
       (SELECT situacao::text FROM r476) AS resultado,
       CASE WHEN (SELECT situacao FROM r476) = 'passou'
            THEN 'OK' ELSE 'FALHOU — ' || COALESCE((SELECT obtido FROM r476), '(sem detalhe)') END AS veredito
UNION ALL
SELECT 2,
       'PONTO-477 — dia curto sem motivo vira pendencia (nao debita o banco)',
       (SELECT situacao::text FROM r477),
       CASE WHEN (SELECT situacao FROM r477) = 'passou'
            THEN 'OK' ELSE 'FALHOU — ' || COALESCE((SELECT obtido FROM r477), '(sem detalhe)') END
UNION ALL
SELECT 3,
       'Estrutura — limite, folga com minutos e trava ampliada',
       CASE WHEN (SELECT tem_config AND folga_aceita_minutos AND trava_ampliada AND sem_bug_j_minutos FROM estrutura)
            THEN 'ok' ELSE 'conferir' END,
       CASE
         WHEN (SELECT tem_config AND folga_aceita_minutos AND trava_ampliada AND sem_bug_j_minutos FROM estrutura)
           THEN 'OK — coluna do limite, folga parcial e trava (com jornada_min) presentes'
         ELSE 'CONFERIR: '
           || CASE WHEN (SELECT NOT tem_config FROM estrutura)            THEN 'falta a coluna dia_curto_bloqueia_fechamento_minutos; ' ELSE '' END
           || CASE WHEN (SELECT NOT folga_aceita_minutos FROM estrutura)  THEN 'a folga nao aceita minutos (versao antiga); ' ELSE '' END
           || CASE WHEN (SELECT NOT trava_ampliada FROM estrutura)        THEN 'a trava do dia curto nao foi inserida; ' ELSE '' END
           || CASE WHEN (SELECT NOT sem_bug_j_minutos FROM estrutura)     THEN 'a trava ainda tem o antigo j.minutos (quebra a lista de pendencias); ' ELSE '' END
       END
ORDER BY ordem;
