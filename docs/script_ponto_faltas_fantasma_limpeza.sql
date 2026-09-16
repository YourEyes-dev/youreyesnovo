-- ============================================================================
-- FALTAS FANTASMA — a limpeza
--
-- APAGA DADO. Leia antes de colar.
--
-- O QUE APAGA
-- Exatamente o conjunto que o levantamento
-- (script_ponto_faltas_fantasma_levantamento.sql) classificou como ALVO, com os
-- mesmos filtros, palavra por palavra:
--   1. so dias com situacao FALTA;
--   2. so colaboradores que NUNCA bateram ponto;
--   3. so empresas com o controle de ponto DESLIGADO;
--   4. FORA competencias ja fechadas;
--   5. FORA dias com espelho emitido ou ajuste registrado;
--   6. FORA dias sem empresa no registro ou de empresa que nao esta no cadastro.
-- Na producao, em 01/09/2026, esse conjunto era de 98.071 dias, de 11.279
-- colaboradores, em 996 empresas — contra 100.690 dias de falta na base.
--
-- POR QUE APAGAR
-- Sao dias que o sistema criou sozinho para gente que nunca deveria estar no
-- modulo de ponto. Enquanto existirem, cada um deles vira desconto de repouso
-- (DSR, Lei 605/49 art. 6) na primeira exportacao de folha.
--
-- COMO O DADO E PRESERVADO — TRES CAMADAS
--   * a copia backup_faltas_fantasma_AAAAMMDD guarda a LINHA INTEIRA de cada
--     dia apagado, e o comando que devolve tudo esta no fim deste arquivo;
--   * a exclusao passa pela trilha de auditoria do proprio sistema
--     (ponto_audit_log), que e o registro formal de quem apagou o que;
--   * a lista do que apagar sai DA PROPRIA COPIA — copia e exclusao nao tem
--     como divergir.
--
-- A TRAVA DE EXCLUSAO DO PONTO
-- Apagar linha de ponto e bloqueado por gatilho, de proposito. Este arquivo usa
-- o caminho controlado que o proprio sistema oferece (app.allow_ponto_delete),
-- que vale so dentro desta transacao e morre no fim dela.
--
-- SE DER TEMPO ESGOTADO
-- Sao muitas linhas. Se o editor interromper por tempo, NADA foi apagado — o
-- arquivo roda em uma transacao so. Nesse caso me avise que eu divido a limpeza
-- por competencia.
--
-- Idempotente: rodar de novo nao apaga mais nada e mantem a copia do dia.
-- ============================================================================

SET lock_timeout = '10s';
SET statement_timeout = '600s';

-- ---------------------------------------------------------------------
-- 1) COPIA DE SEGURANCA — a linha inteira de cada dia que sera apagado
-- ---------------------------------------------------------------------
DO $copia$
DECLARE v_nome text := 'backup_faltas_fantasma_' || to_char(CURRENT_DATE, 'YYYYMMDD');
        n bigint;
BEGIN
  IF to_regclass('public.' || v_nome) IS NOT NULL THEN
    EXECUTE format('SELECT count(*) FROM public.%I', v_nome) INTO n;
    RAISE NOTICE 'A copia % ja existe com % linha(s) — mantida como esta.', v_nome, n;
    RETURN;
  END IF;

  EXECUTE format($sql$
    CREATE TABLE public.%I AS
    SELECT d.*
    FROM public.ponto_diario d
    JOIN public.empresa_cadastro e ON e.id = d.empresa_id
    WHERE d.status = 'falta'
      AND COALESCE(e.usa_controle_ponto, false) = false
      AND NOT EXISTS (
            SELECT 1 FROM public.ponto_marcacoes m
             WHERE m.tenant_id = d.tenant_id
               AND regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'))
      AND NOT EXISTS (
            SELECT 1 FROM public.ponto_fechamentos fe
             WHERE fe.tenant_id = d.tenant_id
               AND fe.competencia = to_char(d.data, 'YYYY-MM')
               AND fe.status = 'fechado'
               AND (fe.empresa_id IS NULL OR fe.empresa_id = d.empresa_id))
      AND NOT EXISTS (
            SELECT 1 FROM public.ponto_espelhos es
             WHERE es.tenant_id = d.tenant_id
               AND es.competencia = to_char(d.data, 'YYYY-MM')
               AND regexp_replace(COALESCE(es.colaborador_cpf, ''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'))
      AND NOT EXISTS (
            SELECT 1 FROM public.ponto_ajustes aj
             WHERE aj.tenant_id = d.tenant_id
               AND aj.data_referencia = d.data
               AND regexp_replace(COALESCE(aj.colaborador_cpf, ''), '[^0-9]', '', 'g')
                 = regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g'))
  $sql$, v_nome);

  EXECUTE format('SELECT count(*) FROM public.%I', v_nome) INTO n;
  RAISE NOTICE 'Copia de seguranca criada: % com % linha(s).', v_nome, n;
END $copia$;

-- ---------------------------------------------------------------------
-- 2) EXCLUSAO — a lista sai da propria copia
-- ---------------------------------------------------------------------
DO $apaga$
DECLARE v_nome text := 'backup_faltas_fantasma_' || to_char(CURRENT_DATE, 'YYYYMMDD');
        n bigint;
BEGIN
  -- Caminho controlado de exclusao que o proprio sistema oferece. Fica ligado
  -- DENTRO deste bloco e morre com a transacao — por isso e ligado aqui, e nao
  -- num comando solto la em cima: assim vale qualquer que seja o editor.
  PERFORM set_config('app.allow_ponto_delete', 'true', true);

  EXECUTE format(
    'DELETE FROM public.ponto_diario d
      WHERE d.id IN (SELECT b.id FROM public.%I b)', v_nome);
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE '% dia(s) de falta fantasma removido(s).', n;
END $apaga$;

-- ============================================================================
-- CONFERENCIA
-- ============================================================================
WITH nome AS MATERIALIZED (
  SELECT 'backup_faltas_fantasma_' || to_char(CURRENT_DATE, 'YYYYMMDD') AS t
),
copia AS MATERIALIZED (
  -- A copia tem nome com a data, entao a contagem dela e feita por consulta
  -- montada na hora. Ela sempre existe aqui: foi criada acima nesta mesma
  -- transacao.
  SELECT (xpath('/row/c/text()',
           query_to_xml('SELECT count(*) AS c FROM public.' || quote_ident(n.t),
                        false, true, '')))[1]::text::bigint AS n
  FROM nome n
),
agora AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE d.status = 'falta') AS faltas
  FROM public.ponto_diario d
),
sobrou AS MATERIALIZED (
  SELECT count(*) AS n
  FROM public.ponto_diario d
  JOIN public.empresa_cadastro e ON e.id = d.empresa_id
  WHERE d.status = 'falta'
    AND COALESCE(e.usa_controle_ponto, false) = false
    AND NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m
                     WHERE m.tenant_id = d.tenant_id
                       AND regexp_replace(COALESCE(m.colaborador_cpf,''), '[^0-9]', '', 'g')
                         = regexp_replace(COALESCE(d.colaborador_cpf,''), '[^0-9]', '', 'g'))
    AND NOT EXISTS (SELECT 1 FROM public.ponto_fechamentos fe
                     WHERE fe.tenant_id = d.tenant_id
                       AND fe.competencia = to_char(d.data, 'YYYY-MM')
                       AND fe.status = 'fechado'
                       AND (fe.empresa_id IS NULL OR fe.empresa_id = d.empresa_id))
    AND NOT EXISTS (SELECT 1 FROM public.ponto_espelhos es
                     WHERE es.tenant_id = d.tenant_id
                       AND es.competencia = to_char(d.data, 'YYYY-MM')
                       AND regexp_replace(COALESCE(es.colaborador_cpf,''), '[^0-9]', '', 'g')
                         = regexp_replace(COALESCE(d.colaborador_cpf,''), '[^0-9]', '', 'g'))
    AND NOT EXISTS (SELECT 1 FROM public.ponto_ajustes aj
                     WHERE aj.tenant_id = d.tenant_id
                       AND aj.data_referencia = d.data
                       AND regexp_replace(COALESCE(aj.colaborador_cpf,''), '[^0-9]', '', 'g')
                         = regexp_replace(COALESCE(d.colaborador_cpf,''), '[^0-9]', '', 'g'))
)
SELECT 'dias apagados (na copia)'::text AS o_que,
       (SELECT n::text FROM copia)                                   AS detalhe,
       'guardados linha a linha em ' || (SELECT t FROM nome)          AS situacao
UNION ALL
SELECT 'faltas que restam na base', (SELECT faltas::text FROM agora),
       'sao as preservadas pelos filtros'
UNION ALL
SELECT 'alvo remanescente', (SELECT n::text FROM sobrou),
       CASE WHEN (SELECT n FROM sobrou) = 0
            THEN 'OK — nao sobrou nenhuma falta fantasma'
            ELSE 'CONFERIR — ainda ha alvo na base' END;

-- ---------------------------------------------------------------------
-- PARA DESFAZER (troque AAAAMMDD pela data de hoje):
--   SELECT set_config('app.allow_ponto_delete', 'true', true);
--   INSERT INTO public.ponto_diario
--   SELECT * FROM backup_faltas_fantasma_AAAAMMDD
--   ON CONFLICT DO NOTHING;
-- ---------------------------------------------------------------------
