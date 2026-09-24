-- ============================================================================
-- ENTREGA — cadeia de hash das marcacoes: fixar o instante em UTC (teste->prod)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   A cadeia de hash e a prova de que nenhuma marcacao de ponto foi adulterada:
--   cada marcacao guarda um hash do seu conteudo, e uma rotina reconfere isso.
--   O conteudo inclui o INSTANTE do registro (created_at). Como created_at e
--   timestamptz, o texto dele depende do FUSO da sessao: o MESMO instante vira
--   '...12:00:00+00' sob UTC e '...09:00:00-03' sob America/Sao_Paulo — dois
--   textos, dois hashes. Hoje tudo roda em UTC e funciona; se o fuso do banco
--   mudasse, TODAS as marcacoes passariam a "nao conferir" e o monitor de
--   integridade dispararia alarme de adulteracao para todo mundo, todo dia —
--   alarme falso justamente na ferramenta que existe para achar adulteracao.
--
--   O teste (fonte da verdade) ja corrigiu, fixando o instante em UTC:
--   ((created_at AT TIME ZONE 'UTC')::text || '+00'). Sob UTC essa forma e
--   BYTE-IDENTICA a created_at::text, entao NENHUM hash ja gravado e invalidado
--   e NADA e reprocessado — so deixa de depender de quem executa. A producao
--   ainda tem a versao antiga (dependente do fuso). Este script alinha as DUAS
--   pecas do par, exatamente como no teste:
--     1. gerar_hash_marcacao()          — GRAVA o hash (gatilho de insert);
--     2. ponto_verificar_cadeia_hash()  — RECONFERE a cadeia (leitura).
--
--   Corpo copiado VERBATIM da migration 20260826120000 (a mesma que o teste
--   aplicou). Cada funcao vai num bloco DO/EXECUTE proprio porque gerar tem
--   SELECT ... INTO, que o SQL Editor do Supabase confunde com criacao de
--   tabela (injetor de RLS). Rode BLOCO 1, depois BLOCO 2, depois a conferencia.
--
-- SEGURANCA: so substitui duas funcoes; retrocompativel (nao invalida hash,
--   nao reprocessa nada); nao altera nem apaga dado; idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── BLOCO 1: gerar_hash_marcacao (grava o hash, com o instante em UTC) ───────
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.gerar_hash_marcacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_sentinela uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  -- Encadeia com o hash da marcação anterior (NSR imediatamente menor no mesmo
  -- balde tenant/estabelecimento). Nunca deixa a leitura derrubar o insert.
  IF NEW.nsr IS NOT NULL AND NEW.tenant_id IS NOT NULL THEN
    BEGIN
      SELECT m.hash_marcacao
        INTO NEW.hash_anterior
      FROM public.ponto_marcacoes m
      WHERE m.tenant_id = NEW.tenant_id
        AND COALESCE(m.empresa_id, v_sentinela) = COALESCE(NEW.empresa_id, v_sentinela)
        AND m.nsr = NEW.nsr - 1
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      NEW.hash_anterior := NULL;
    END;
  END IF;

  -- Instante fixado em UTC: mesmo texto qualquer que seja o fuso da sessao.
  NEW.hash_marcacao := encode(
    sha256(
      (NEW.colaborador_cpf || NEW.data_marcacao::text || NEW.hora_marcacao::text
       || NEW.tipo_marcacao || ((NEW.created_at AT TIME ZONE 'UTC')::text || '+00')
       || COALESCE(NEW.hash_anterior, ''))::bytea
    ),
    'hex'
  );
  RETURN NEW;
END;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 2: ponto_verificar_cadeia_hash (reconfere, com o instante em UTC) ──
DO $ptdo$
BEGIN
  EXECUTE $ptsql$
CREATE OR REPLACE FUNCTION public.ponto_verificar_cadeia_hash(
  p_tenant_id uuid DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS TABLE(
  tenant_id uuid,
  empresa_id uuid,
  nsr bigint,
  marcacao_id uuid,
  tipo_quebra text,
  detalhe text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  -- Verificacao da cadeia: recomputa cada hash_marcacao (com o instante fixado
  -- em UTC, para nao depender do fuso de quem executa) e confere o
  -- encadeamento pelo hash_anterior e a continuidade da NSR.
  WITH marcs AS (
    SELECT m.id, m.tenant_id, m.empresa_id, m.nsr,
           m.hash_marcacao, m.hash_anterior,
           m.colaborador_cpf, m.data_marcacao, m.hora_marcacao,
           m.tipo_marcacao, m.created_at,
           lag(m.hash_marcacao) OVER w AS prev_hash,
           lag(m.nsr)           OVER w AS prev_nsr
    FROM public.ponto_marcacoes m
    WHERE m.hash_marcacao IS NOT NULL
      AND m.nsr IS NOT NULL
      AND (p_tenant_id  IS NULL OR m.tenant_id  = p_tenant_id)
      AND (p_empresa_id IS NULL OR m.empresa_id = p_empresa_id)
    WINDOW w AS (
      PARTITION BY m.tenant_id, COALESCE(m.empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
      ORDER BY m.nsr
    )
  ),
  calc AS (
    SELECT c.*,
           encode(sha256((c.colaborador_cpf || c.data_marcacao::text || c.hora_marcacao::text
                  || c.tipo_marcacao || ((c.created_at AT TIME ZONE 'UTC')::text || '+00')
                  || COALESCE(c.hash_anterior,''))::bytea),'hex') AS hash_recomputado
    FROM marcs c
  )
  SELECT tenant_id, empresa_id, nsr, id AS marcacao_id,
         CASE
           WHEN hash_recomputado <> hash_marcacao
             THEN 'hash_adulterado'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'cadeia_quebrada'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN 'nsr_faltante'
         END AS tipo_quebra,
         CASE
           WHEN hash_recomputado <> hash_marcacao
             THEN 'Hash gravado nao confere com o recomputado do conteudo (marcacao alterada).'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'Encadeamento rompido: o hash_anterior nao bate com o hash da marcacao anterior.'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN format('Salto de NSR (%s -> %s): pode haver marcacao removida.', prev_nsr, nsr)
         END AS detalhe
  FROM calc
  WHERE hash_recomputado <> hash_marcacao
     OR (hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash)
     OR (prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1)
  ORDER BY tenant_id, empresa_id NULLS FIRST, nsr;
$fn$;
  $ptsql$;
END
$ptdo$;

-- ── BLOCO 3 (conferencia) — RODE SEPARADO. Esperado: 2 linhas, ambas OK ─────
-- md5_normalizado do TESTE (confirmado no cruzamento teste=homologacao):
--   gerar_hash_marcacao          -> 07b70172fd02a3f67933c3c4d558bcf1
--   ponto_verificar_cadeia_hash  -> a17e6d5809a62d8d2dbbe94787ee8d51
--   WITH esperado(objeto, md5_teste) AS (
--     VALUES
--       ('gerar_hash_marcacao',         '07b70172fd02a3f67933c3c4d558bcf1'),
--       ('ponto_verificar_cadeia_hash', 'a17e6d5809a62d8d2dbbe94787ee8d51')
--   )
--   SELECT e.objeto,
--          l.lanname                                                        AS linguagem,
--          md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))  AS md5_producao,
--          (pg_get_functiondef(p.oid) LIKE '%AT TIME ZONE ''UTC''%')        AS tem_utc,
--          CASE WHEN md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) = e.md5_teste
--               THEN 'OK' ELSE 'CONFERIR' END                               AS status
--   FROM esperado e
--   JOIN pg_proc p      ON p.proname = e.objeto
--   JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   JOIN pg_language  l ON l.oid = p.prolang
--   ORDER BY e.objeto;
