-- ============================================================================
-- ENTREGA — sábado de equalização não é contado como FALTA no espelho
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO (caso da Kailaine, sábado de equalização 19/09): a escala de
-- equalização mensal fecha a carga do mês num sábado. Quando esse sábado NÃO é
-- trabalhado, o motor já o trata como DÉBITO do banco (compensação de jornada,
-- CLT art. 59, §2º) — mas o espelho-resumo AINDA o contava como falta. Efeito
-- duplo: a mesma hora saía do banco E aparecia como ausência para a folha, com
-- risco de derrubar o DSR da semana. É o mesmo princípio do PONTO-421 (folga
-- compensatória não vira falta) e do PONTO-474 (não cobrar duas vezes).
--
-- CORREÇÃO ([falta-nao-conta-equalizacao]): o total de faltas do espelho passa
-- a excluir os dias de equalização. O DÉBITO no banco continua intacto — só
-- paramos de tipificar o dia como falta de folha. Vale também para o resumo por
-- empresa, que apenas delega para esta função (uma correção, duas telas).
--
-- SEGURANÇA: só redefine a função do espelho (não cria tabela, não escreve
-- dado). Idempotente (rodar 2x diz "ja aplicada"). Assim que aplicar, a tela
-- (que lê ao vivo) se corrige sozinha: o sábado de equalização deixa de contar
-- como falta e segue como débito no extrato do banco.
-- ============================================================================

DO $item$
DECLARE
  v_src text;
  v_novo text;
  v_alvo  text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0';
  v_troca text := 'WHERE NOT d.protegido AND d.jornada_min > 0 AND d.trabalhado_min = 0'
                 || ' AND NOT COALESCE(d.equalizacao, false) /* [falta-nao-conta-equalizacao] */';
BEGIN
  v_src := pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure);

  IF position('[falta-nao-conta-equalizacao]' IN v_src) > 0 THEN
    RAISE NOTICE 'ponto_espelho_resumo ja exclui equalizacao das faltas — nada a fazer.';
    RETURN;
  END IF;

  IF position(v_alvo IN v_src) = 0 THEN
    RAISE NOTICE 'ATENCAO: a ancora do filtro de faltas nao foi encontrada; NADA alterado.';
    RETURN;
  END IF;

  v_novo := replace(v_src, v_alvo, v_troca);
  EXECUTE v_novo;
  RAISE NOTICE 'ponto_espelho_resumo: sabado de equalizacao saiu das faltas (segue como debito).';
END $item$;

-- Conferência (o editor mostra só o último resultado): confirma a marca no corpo.
SELECT position('[falta-nao-conta-equalizacao]' IN
         pg_get_functiondef('public.ponto_espelho_resumo(uuid,text,text)'::regprocedure)) > 0
       AS espelho_equalizacao_ok;
