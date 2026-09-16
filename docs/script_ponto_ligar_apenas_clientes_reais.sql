-- ============================================================================
-- PONTO — ligar o controle de ponto SOMENTE nas empresas que o usam
--
-- O QUE ESTE ARQUIVO RESOLVE
-- O levantamento na producao (01/09) mostrou 88 colaboradores marcando ponto
-- num universo de 11.674, e 99.251 faltas acumuladas no ano por 11.586 pessoas
-- que nunca bateram. A tarefa diaria ponto_materializar_faltas cria o dia como
-- falta para todo colaborador de empresa que esteja marcada como usuaria do
-- controle de ponto — e praticamente toda a base esta assim.
--
-- Isso importa porque o DSR (desconto do repouso por falta injustificada, Lei
-- 605/49 art. 6) ja existe na producao: no dia em que a folha for exportada,
-- cada uma dessas faltas vira desconto no contracheque de quem nunca deveria
-- ter marcado ponto.
--
-- NAO E DEFEITO DE CODIGO. A chave certa ja existe no sistema
-- (empresa_cadastro.usa_controle_ponto, lida por ponto_empresas_em_regime).
-- O que este arquivo faz e AJUSTAR A CONFIGURACAO: desliga a chave em todas as
-- empresas e a religa apenas nos clientes que de fato usam o modulo, conforme
-- definido pelo dono do produto em 01/09/2026:
--
--   * Barros & Nuernberg
--   * Nuernberg & Barros
--   * Avana Engenharia
--   * Sudoclin
--   * Clinica Medica Ambulatorial Magalhaes Lopes
--   * Voe Midia  (acrescentada em 01/09/2026, na conferencia do resultado)
--
-- REDE DE SEGURANCA JA EXISTENTE
-- A apuracao tambem alcanca, independentemente desta chave, qualquer CPF com
-- marcacao nos ultimos 365 dias (ponto_cpfs_em_regime). Ou seja: se o nome de
-- alguma empresa nao casar com a lista acima, quem realmente bate ponto
-- continua sendo apurado normalmente. O desligamento nao cega ninguem que use
-- o modulo de verdade.
--
-- O QUE ESTE ARQUIVO NAO FAZ
-- Nao apaga as 99.251 faltas ja criadas. Elas param de crescer a partir da
-- proxima madrugada, mas a limpeza do passado e uma decisao separada, com
-- copia de seguranca propria.
--
-- ALTERA DADO EXISTENTE: guarda antes as linhas afetadas em
-- backup_usa_controle_ponto_AAAAMMDD. O comando que desfaz esta no fim.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Copia de seguranca das empresas que serao tocadas
-- ---------------------------------------------------------------------
DO $copia$
DECLARE v_nome text := 'backup_usa_controle_ponto_' || to_char(CURRENT_DATE, 'YYYYMMDD');
BEGIN
  IF to_regclass('public.' || v_nome) IS NOT NULL THEN
    RAISE NOTICE 'A copia % ja existe — mantida como estava.', v_nome;
    RETURN;
  END IF;
  EXECUTE format(
    'CREATE TABLE public.%I AS
       SELECT id, tenant_id, razao_social, cnpj, usa_controle_ponto
       FROM public.empresa_cadastro', v_nome);
  RAISE NOTICE 'Copia de seguranca criada: %', v_nome;
END $copia$;

-- ---------------------------------------------------------------------
-- 2) Desliga o controle de ponto em todas as empresas que NAO estao na
--    lista dos clientes que usam o modulo
-- ---------------------------------------------------------------------
UPDATE public.empresa_cadastro e
   SET usa_controle_ponto = false
 WHERE COALESCE(e.usa_controle_ponto, false) IS TRUE
   AND NOT (
     e.razao_social ILIKE '%BARROS%NUERNBERG%' OR
     e.razao_social ILIKE '%NUERNBERG%BARROS%' OR
     e.razao_social ILIKE '%AVANA%ENGENHARIA%' OR
     e.razao_social ILIKE '%SUDOCLIN%'          OR
     e.razao_social ILIKE '%MAGALHAES%LOPES%'   OR
     e.razao_social ILIKE '%VOE%MIDIA%'         OR
     e.razao_social ILIKE '%VOE%MÍDIA%'
   );

-- ---------------------------------------------------------------------
-- 3) Garante o controle LIGADO nos clientes que usam o modulo
-- ---------------------------------------------------------------------
UPDATE public.empresa_cadastro e
   SET usa_controle_ponto = true
 WHERE COALESCE(e.usa_controle_ponto, false) IS NOT TRUE
   AND (
     e.razao_social ILIKE '%BARROS%NUERNBERG%' OR
     e.razao_social ILIKE '%NUERNBERG%BARROS%' OR
     e.razao_social ILIKE '%AVANA%ENGENHARIA%' OR
     e.razao_social ILIKE '%SUDOCLIN%'          OR
     e.razao_social ILIKE '%MAGALHAES%LOPES%'   OR
     e.razao_social ILIKE '%VOE%MIDIA%'         OR
     e.razao_social ILIKE '%VOE%MÍDIA%'
   );

-- ============================================================================
-- CONFERENCIA
-- Primeiro as empresas que ficaram COM controle de ponto (confira uma a uma:
-- so podem estar aqui as que usam o modulo). Depois o resumo.
-- ============================================================================
WITH ligadas AS MATERIALIZED (
  SELECT e.razao_social, e.cnpj, e.ativo
  FROM public.empresa_cadastro e
  WHERE e.usa_controle_ponto IS TRUE
),
numeros AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE usa_controle_ponto IS TRUE)  AS ligadas,
         count(*) FILTER (WHERE COALESCE(usa_controle_ponto, false) IS NOT TRUE) AS desligadas,
         count(*)                                            AS total
  FROM public.empresa_cadastro
),
cpfs AS MATERIALIZED (
  SELECT count(DISTINCT regexp_replace(m.colaborador_cpf, '[^0-9]', '', 'g')) AS n
  FROM public.ponto_marcacoes m
  WHERE m.data_marcacao >= CURRENT_DATE - 365
)
SELECT 1 AS ordem,
       left(l.razao_social, 45)                    AS empresa,
       COALESCE(l.cnpj, '-')                       AS cnpj,
       CASE WHEN l.ativo THEN 'ativa' ELSE 'inativa' END AS situacao_cadastro,
       'CONTINUA com controle de ponto'::text      AS controle
FROM ligadas l
UNION ALL
SELECT 0,
       'RESUMO',
       (SELECT ligadas::text || ' de ' || total::text FROM numeros) || ' empresa(s) com ponto',
       (SELECT desligadas::text FROM numeros) || ' desligada(s)',
       'Alem dessas, a apuracao segue alcancando ' || (SELECT n::text FROM cpfs)
         || ' CPF(s) com marcacao nos ultimos 365 dias, independentemente da chave — '
         || 'quem bate ponto de verdade nao fica sem apuracao.'
ORDER BY ordem, empresa;

-- ---------------------------------------------------------------------
-- PARA DESFAZER (troque AAAAMMDD pela data de hoje):
--   UPDATE public.empresa_cadastro e
--      SET usa_controle_ponto = b.usa_controle_ponto
--     FROM backup_usa_controle_ponto_AAAAMMDD b
--    WHERE b.id = e.id;
-- ---------------------------------------------------------------------
