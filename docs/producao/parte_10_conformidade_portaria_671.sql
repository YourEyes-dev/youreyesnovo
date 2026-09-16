-- ============================================================================
-- PRODUCAO — PONTO, PARTE 10 de 16
--
-- ANTES DE COLAR ESTA PARTE
--   * o RETRATO (passo_00_retrato_antes.sql) ja tem de ter sido tirado;
--   * as partes anteriores ja tem de ter sido aplicadas, nesta ordem, cada uma
--     com a conferencia terminando em OK.
--
-- ONDE COLAR
-- No SQL Editor do projeto de PRODUCAO. Execute o arquivo INTEIRO, uma vez.
-- Pode rodar de novo sem risco: e idempotente.
--
-- CONTEUDO
-- Identico ao que foi aplicado e conferido na homologacao, onde a bateria do
-- Ponto fechou em 133 passou / 1 falhou / 0 erro.
--
-- AO FINAL
-- Sai UMA conferencia com duas partes: as pecas que chegaram e o VOLUME —
-- quantas linhas das tabelas vivas do Ponto mudaram de quantidade. Nesta parte o esperado e ZERO.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (inicio) — a contagem de agora fica guardada para a
-- conferencia do fim comparar. Tabela propria, que nenhum sistema le.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_entrega_volume (
  parte          integer NOT NULL,
  tabela         text    NOT NULL,
  linhas_antes   bigint  NOT NULL,
  linhas_depois  bigint,
  marca_antes    text,
  marca_depois   text,
  medido_em      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parte, tabela)
);

-- Para a tabela criada por uma versao anterior desta fila continuar servindo.
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_antes  text;
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_depois text;

-- Tabela nova em public fica exposta pela API do Supabase. Esta nao tem dado
-- pessoal, mas tambem nao e da conta de ninguem: RLS ligada e sem politica.
ALTER TABLE public.ponto_entrega_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_entrega_volume FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_entrega_volume FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base.';
END $fechadura$;

DO $volume$
DECLARE
  t text;
  n bigint;
  m text;
BEGIN
  DELETE FROM public.ponto_entrega_volume WHERE parte = 10;
  FOREACH t IN ARRAY ARRAY['ponto_diario', 'ponto_marcacoes', 'ponto_espelhos', 'ponto_banco_horas', 'ponto_alertas', 'ponto_links', 'ponto_fechamentos', 'atestados']
  LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    m := NULL;
    -- A marca e a data da ultima alteracao registrada na tabela. Contagem
    -- pega linha criada ou apagada; a marca pega linha ALTERADA.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=t AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', t) INTO m;
    END IF;
    INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, marca_antes)
    VALUES (10, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda7_aej.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 7 (parte 2): AEJ — Arquivo Eletronico de Jornada (Portaria 671)
-- Alvos: ponto_arquivos_aej (nova) + ponto_gerar_aej, ponto_aej_extrair (novas)
-- PONTO-211
--
-- O AEJ e a saida OBRIGATORIA do "programa de tratamento" na Portaria 671 (ele
-- substituiu o AFDT/ACJEF da 1510/2009) e a peca que a fiscalizacao pede junto
-- com o AFD. Hoje nao existe em lugar nenhum do banco. Passa a existir a tabela
-- do arquivo arquivado, o gerador (a partir da apuracao fechada + contrato +
-- marcacoes TRATADAS, em registros tipados, assinado por hash) e a extracao para
-- download/fiscalizacao.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem as
-- marcacoes. So LE a apuracao e grava o arquivo. Aditivo e idempotente. Roda
-- inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
-- (1) Arquivo arquivado -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_arquivos_aej (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL,
  empresa_id          uuid,
  competencia         text NOT NULL,
  periodo_ini         date,
  periodo_fim         date,
  empregador_cnpj     text,
  empregador_nome     text,
  total_trabalhadores integer NOT NULL DEFAULT 0,
  total_marcacoes     integer NOT NULL DEFAULT 0,
  total_registros     integer NOT NULL DEFAULT 0,
  conteudo            text,
  conteudo_estruturado jsonb,
  hash_arquivo        text,
  arquivo_url         text,
  gerado_em           timestamptz NOT NULL DEFAULT now(),
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ponto_arquivos_aej_comp
  ON public.ponto_arquivos_aej (tenant_id, empresa_id, competencia);

COMMENT ON TABLE public.ponto_arquivos_aej IS
  'Arquivo Eletronico de Jornada (AEJ) gerado pelo programa de tratamento (Portaria MTP 671/2021): jornada tratada (contrato + marcacoes tratadas + apuracao) da competencia, arquivada, assinada por hash e vinculada ao empregador. Saida obrigatoria junto com o AFD.';

ALTER TABLE public.ponto_arquivos_aej ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_arquivos_aej'
         AND policyname='ponto_arquivos_aej_tenant') THEN
    CREATE POLICY ponto_arquivos_aej_tenant
      ON public.ponto_arquivos_aej
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- Trava do cercado do QA (isolamento de tenant) — PONTO-270.
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_arquivos_aej'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_arquivos_aej
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_arquivos_aej', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_arquivos_aej');

-- (2) Gerador do AEJ ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_gerar_aej(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_emp    RECORD;
  v_tipoid text;
  w        RECORD;
  mrec     RECORD;
  v_linhas text[] := ARRAY[]::text[];
  v_estr   jsonb  := '[]'::jsonb;
  v_marc   jsonb;
  v_n2 int := 0;   -- registros tipo 2 (contratos/trabalhadores)
  v_n3 int := 0;   -- registros tipo 3 (marcacoes tratadas)
  v_n4 int := 0;   -- registros tipo 4 (apuracoes)
  v_total int;
  v_conteudo text;
  v_hash text;
  v_id uuid;
BEGIN
  -- Empregador (cabeçalho, tipo 1). Identificador: 1=CNPJ; senão CEI/CAEPF.
  SELECT ec.razao_social, ec.cnpj, ec.cei, ec.caepf INTO v_emp
  FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id;

  v_tipoid := CASE
    WHEN v_emp.cnpj IS NOT NULL AND btrim(v_emp.cnpj) <> '' THEN '1'
    WHEN COALESCE(v_emp.caepf, '') <> '' THEN '3'
    WHEN COALESCE(v_emp.cei, '')   <> '' THEN '4'
    ELSE '9'
  END;

  v_linhas := array_append(v_linhas, format('1|%s|%s|%s|%s|%s|%s',
    v_tipoid,
    COALESCE(v_emp.cnpj, ''),
    COALESCE(NULLIF(v_emp.caepf,''), NULLIF(v_emp.cei,''), ''),
    COALESCE(v_emp.razao_social, ''),
    to_char(v_ini, 'YYYY-MM-DD'), to_char(v_fim, 'YYYY-MM-DD')));

  -- Trabalhadores com jornada no período: UNIAO da apuracao (espelhos) com as
  -- marcacoes tratadas do periodo. Contrato vem de admissoes (por CPF/empresa).
  FOR w IN
    WITH cpfs AS (
      SELECT DISTINCT regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') AS cpf_num,
             colaborador_cpf AS cpf_orig, colaborador_nome
      FROM public.ponto_espelhos
      WHERE tenant_id = p_tenant_id AND competencia = p_competencia
        AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
      UNION
      SELECT DISTINCT regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g'),
             colaborador_cpf, colaborador_nome
      FROM public.ponto_marcacoes
      WHERE tenant_id = p_tenant_id
        AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
        AND data_marcacao BETWEEN v_ini AND v_fim
        AND COALESCE(desconsiderada, false) = false
    )
    SELECT cpf_num,
           max(cpf_orig)      AS cpf_orig,
           max(colaborador_nome) AS nome
    FROM cpfs
    WHERE cpf_num <> ''
    GROUP BY cpf_num
    ORDER BY 1
  LOOP
    -- Contrato (tipo 2): admissoes por CPF (+ empresa quando informada).
    DECLARE
      v_adm RECORD;
      v_esp RECORD;
    BEGIN
      SELECT a.nome_completo, a.data_admissao, a.jornada_trabalho INTO v_adm
      FROM public.admissoes a
      WHERE regexp_replace(COALESCE(a.cpf,''),'[^0-9]','','g') = w.cpf_num
        AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id)
      ORDER BY a.data_admissao DESC NULLS LAST
      LIMIT 1;

      v_linhas := array_append(v_linhas, format('2|%s|%s|%s|%s',
        w.cpf_orig,
        COALESCE(v_adm.nome_completo, w.nome, ''),
        COALESCE(to_char(v_adm.data_admissao, 'YYYY-MM-DD'), ''),
        COALESCE(v_adm.jornada_trabalho, '')));
      v_n2 := v_n2 + 1;

      -- Marcacoes tratadas (tipo 3): originais, nao desconsideradas, ordenadas.
      v_marc := '[]'::jsonb;
      FOR mrec IN
        SELECT m.data_marcacao, m.hora_marcacao, m.tipo_marcacao,
               COALESCE(m.origem_marcacao, 'O') AS origem, m.nsr
        FROM public.ponto_marcacoes m
        WHERE m.tenant_id = p_tenant_id
          AND regexp_replace(COALESCE(m.colaborador_cpf,''),'[^0-9]','','g') = w.cpf_num
          AND (p_empresa_id IS NULL OR m.empresa_id = p_empresa_id)
          AND m.data_marcacao BETWEEN v_ini AND v_fim
          AND COALESCE(m.desconsiderada, false) = false
        ORDER BY m.data_marcacao, m.hora_marcacao
      LOOP
        v_linhas := array_append(v_linhas, format('3|%s|%s|%s|%s|%s|%s',
          w.cpf_orig,
          to_char(mrec.data_marcacao, 'YYYY-MM-DD'),
          to_char(mrec.hora_marcacao, 'HH24:MI'),
          COALESCE(mrec.tipo_marcacao, ''),
          mrec.origem,
          COALESCE(mrec.nsr::text, '')));
        v_n3 := v_n3 + 1;
        v_marc := v_marc || jsonb_build_object(
          'data', mrec.data_marcacao, 'hora', to_char(mrec.hora_marcacao,'HH24:MI'),
          'tipo', mrec.tipo_marcacao, 'origem', mrec.origem, 'nsr', mrec.nsr);
      END LOOP;

      -- Apuracao (tipo 4): totais tratados da competencia (ponto_espelhos).
      SELECT total_horas_normais_minutos, total_horas_extras_50_minutos,
             total_horas_extras_100_minutos, total_adicional_noturno_minutos,
             total_faltas, total_atrasos_minutos, total_dsr
        INTO v_esp
      FROM public.ponto_espelhos
      WHERE tenant_id = p_tenant_id AND competencia = p_competencia
        AND regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = w.cpf_num
        AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
      LIMIT 1;

      IF FOUND THEN
        v_linhas := array_append(v_linhas, format('4|%s|%s|%s|%s|%s|%s|%s|%s|%s',
          w.cpf_orig, p_competencia,
          COALESCE(v_esp.total_horas_normais_minutos, 0),
          COALESCE(v_esp.total_horas_extras_50_minutos, 0),
          COALESCE(v_esp.total_horas_extras_100_minutos, 0),
          COALESCE(v_esp.total_adicional_noturno_minutos, 0),
          COALESCE(v_esp.total_faltas, 0),
          COALESCE(v_esp.total_atrasos_minutos, 0),
          COALESCE(v_esp.total_dsr::text, '0')));
        v_n4 := v_n4 + 1;
      END IF;

      v_estr := v_estr || jsonb_build_object(
        'cpf', w.cpf_orig,
        'nome', COALESCE(v_adm.nome_completo, w.nome),
        'contrato', jsonb_build_object('data_admissao', v_adm.data_admissao,
                                       'jornada', v_adm.jornada_trabalho),
        'marcacoes_tratadas', v_marc);
    END;
  END LOOP;

  -- Trailer (tipo 9): contagens. total_registros inclui cabeçalho e trailer.
  v_total := array_length(v_linhas, 1) + 1;  -- +1: a própria linha 9
  v_linhas := array_append(v_linhas, format('9|%s|%s|%s|%s', v_n2, v_n3, v_n4, v_total));

  v_conteudo := array_to_string(v_linhas, E'\n');
  v_hash := encode(public.digest(v_conteudo, 'sha256'), 'hex');

  -- Idempotente: refaz o AEJ desta competência/empresa (marcador por match).
  DELETE FROM public.ponto_arquivos_aej
  WHERE tenant_id = p_tenant_id AND competencia = p_competencia
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id
         OR (p_empresa_id IS NULL AND empresa_id IS NULL));

  INSERT INTO public.ponto_arquivos_aej (
    tenant_id, empresa_id, competencia, periodo_ini, periodo_fim,
    empregador_cnpj, empregador_nome, total_trabalhadores, total_marcacoes,
    total_registros, conteudo, conteudo_estruturado, hash_arquivo, gerado_em
  ) VALUES (
    p_tenant_id, p_empresa_id, p_competencia, v_ini, v_fim,
    v_emp.cnpj, v_emp.razao_social, v_n2, v_n3,
    v_total, v_conteudo,
    jsonb_build_object(
      'norma', 'Portaria MTP 671/2021 — AEJ (Arquivo Eletronico de Jornada)',
      'empregador', jsonb_build_object('razao_social', v_emp.razao_social,
                                       'cnpj', v_emp.cnpj, 'cei', v_emp.cei, 'caepf', v_emp.caepf),
      'periodo', jsonb_build_object('inicio', v_ini, 'fim', v_fim),
      'trabalhadores', v_estr),
    v_hash, now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_gerar_aej(uuid, uuid, text) IS
  'Gera o AEJ (Arquivo Eletronico de Jornada, Portaria 671) da competencia a partir da apuracao fechada (ponto_espelhos) + contrato (admissoes) + marcacoes TRATADAS (ponto_marcacoes nao desconsideradas, com origem e NSR), em registros tipados (1 cabecalho, 2 contrato, 3 marcacao, 4 apuracao, 9 trailer), assinado por hash e arquivado. Idempotente. PONTO-211.';

-- (3) Extração do AEJ arquivado (download/fiscalização) -----------------------
CREATE OR REPLACE FUNCTION public.ponto_aej_extrair(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS TABLE(
  competencia      text,
  periodo_ini      date,
  periodo_fim      date,
  empregador_nome  text,
  total_trabalhadores integer,
  total_marcacoes  integer,
  total_registros  integer,
  conteudo         text,
  hash_arquivo     text,
  gerado_em        timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Devolve o AEJ arquivado da competencia/empresa (o mais recente). Portaria 671.
  SELECT a.competencia, a.periodo_ini, a.periodo_fim, a.empregador_nome,
         a.total_trabalhadores, a.total_marcacoes, a.total_registros,
         a.conteudo, a.hash_arquivo, a.gerado_em
  FROM public.ponto_arquivos_aej a
  WHERE a.tenant_id = p_tenant_id
    AND a.competencia = p_competencia
    AND (p_empresa_id IS NULL OR a.empresa_id = p_empresa_id
         OR (p_empresa_id IS NULL AND a.empresa_id IS NULL))
  ORDER BY a.gerado_em DESC
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.ponto_aej_extrair(uuid, uuid, text) IS
  'Devolve o AEJ arquivado (conteudo tratado + assinatura) da competencia/empresa, para download/fiscalizacao. Portaria 671. PONTO-211.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   arquivo_aej    : t  (ponto_arquivos_aej existe)
--   gerador_existe : t  (ponto_gerar_aej)
--   extracao_existe: t  (ponto_aej_extrair)
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_arquivos_aej') IS NOT NULL)                              AS arquivo_aej,
  (to_regprocedure('public.ponto_gerar_aej(uuid,uuid,text)') IS NOT NULL)             AS gerador_existe,
  (to_regprocedure('public.ponto_aej_extrair(uuid,uuid,text)') IS NOT NULL)           AS extracao_existe,
  CASE WHEN to_regclass('public.ponto_arquivos_aej') IS NOT NULL
        AND to_regprocedure('public.ponto_gerar_aej(uuid,uuid,text)') IS NOT NULL
        AND to_regprocedure('public.ponto_aej_extrair(uuid,uuid,text)') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda7_afd_importacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 7 (parte 3): importacao de AFD que CONFERE (Portaria 671)
-- Alvos: ponto_repc_importacoes (+colunas/constraint), ponto_marcacoes
--        (+nsr_origem/equipamento), ponto_afd_eventos_equipamento (nova),
--        ponto_afd_crc16 e ponto_afd_validar_importacao (novas)
-- PONTO-382 / PONTO-383 / PONTO-384 / PONTO-212
--
-- A importacao de AFD (Arquivo Fonte de Dados de REP de terceiro) so validava,
-- quando validava, na TELA. Importacao por API entrava sem conferencia: arquivo
-- corrompido, sequencia de NSR quebrada, reimportacao apos falha no meio, ou os
-- registros nao-marcacao (ajuste de relogio, evento sensivel) descartados.
--
-- Passa a existir a conferencia NO BANCO: CRC-16 por registro, cadeia SHA-256 do
-- trailer, verdito de assinatura e LACUNA de NSR (recusa o arquivo por inteiro),
-- com QUARENTENA do reprovado; a chave natural do registro de origem na marcacao
-- (nsr_origem + equipamento) para reimportacao idempotente; e a casa dos
-- registros nao-marcacao (tipo 4/6) na trilha do equipamento.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem grava
-- marcacao. Aditivo e idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
-- (383/382) Identidade e verdito do arquivo em ponto_repc_importacoes ---------
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS arquivo_hash      text;
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS crc_valido        boolean;
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS assinatura_valida boolean;
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS cadeia_valida     boolean;
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS quarentena        boolean NOT NULL DEFAULT false;
ALTER TABLE public.ponto_repc_importacoes ADD COLUMN IF NOT EXISTS relatorio         jsonb;

-- Unicidade do arquivo (hash) por tenant — a mesma remessa não entra duas vezes.
-- NULLs são distintos: linhas antigas (hash nulo) não conflitam.
DO $uk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.ponto_repc_importacoes'::regclass
                   AND conname='ponto_repc_importacoes_arquivo_uk') THEN
    ALTER TABLE public.ponto_repc_importacoes
      ADD CONSTRAINT ponto_repc_importacoes_arquivo_uk UNIQUE (tenant_id, arquivo_hash);
  END IF;
END $uk$;

-- (383) Chave natural do registro de origem na marcação: o NSR que veio NO AFD
-- e o equipamento que o emitiu. Distinto do nsr próprio (gerado na gravação).
ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS nsr_origem  bigint;
ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS equipamento text;

-- Reimportação idempotente pela chave natural (quando ambos presentes).
CREATE UNIQUE INDEX IF NOT EXISTS ponto_marcacoes_origem_afd_uk
  ON public.ponto_marcacoes (tenant_id, equipamento, nsr_origem)
  WHERE equipamento IS NOT NULL AND nsr_origem IS NOT NULL;

-- (384) Casa dos registros não-marcação do AFD (tipo 4 e tipo 6) --------------
CREATE TABLE IF NOT EXISTS public.ponto_afd_eventos_equipamento (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL,
  empresa_id            uuid,
  importacao_id         uuid,
  equipamento           text,
  nsr_origem            bigint,
  tipo_registro         text,          -- '4' (ajuste do relogio) | '6' (evento sensivel)
  data_hora             timestamptz,
  ajuste_relogio_de     timestamptz,   -- tipo 4: relogio ANTES do ajuste
  ajuste_relogio_para   timestamptz,   -- tipo 4: relogio DEPOIS do ajuste
  evento_sensivel_tipo  text,          -- tipo 6: natureza do evento
  evento_sensivel_descricao text,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ponto_afd_eventos_equip
  ON public.ponto_afd_eventos_equipamento (tenant_id, equipamento, data_hora);

COMMENT ON TABLE public.ponto_afd_eventos_equipamento IS
  'Registros nao-marcacao do AFD importado: ajuste do relogio do equipamento (tipo 4) e eventos sensiveis (tipo 6), visiveis na trilha de auditoria. Um relogio ajustado perto de uma marcacao suspeita e o que a fiscalizacao procura. PONTO-384.';

ALTER TABLE public.ponto_afd_eventos_equipamento ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_afd_eventos_equipamento'
         AND policyname='ponto_afd_eventos_equipamento_tenant') THEN
    CREATE POLICY ponto_afd_eventos_equipamento_tenant
      ON public.ponto_afd_eventos_equipamento
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_afd_eventos_equipamento'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_afd_eventos_equipamento
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_afd_eventos_equipamento', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_afd_eventos_equipamento');

-- (382) CRC-16/CCITT-FALSE de um registro -------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_afd_crc16(p_texto text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  v_bytes bytea := convert_to(COALESCE(p_texto, ''), 'LATIN1');
  v_crc   int := 65535;   -- 0xFFFF (init CCITT-FALSE)
  i int; j int; b int;
BEGIN
  FOR i IN 0 .. octet_length(v_bytes) - 1 LOOP
    b := get_byte(v_bytes, i);
    v_crc := (v_crc # (b << 8)) & 65535;
    FOR j IN 1..8 LOOP
      IF (v_crc & 32768) <> 0 THEN            -- 0x8000
        v_crc := ((v_crc << 1) # 4129) & 65535;  -- poly 0x1021
      ELSE
        v_crc := (v_crc << 1) & 65535;
      END IF;
    END LOOP;
  END LOOP;
  RETURN v_crc;
END;
$$;

COMMENT ON FUNCTION public.ponto_afd_crc16(text) IS
  'CRC-16/CCITT-FALSE (init 0xFFFF, poly 0x1021) de um registro do AFD, para conferir a integridade byte a byte na importacao. PONTO-382.';

-- (382/212) Conferência da importação: CRC, cadeia, LACUNA de NSR e quarentena -
CREATE OR REPLACE FUNCTION public.ponto_afd_validar_importacao(
  p_tenant_id       uuid,
  p_empresa_id      uuid,
  p_importacao_id   uuid,
  p_arquivo_hash    text,
  p_registros       jsonb,
  p_assinatura_valida boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  rec       jsonb;
  v_tipo    text;
  v_linha   text;
  v_crc_dec int;
  v_crc_ok  boolean := true;
  v_cadeia_ok boolean := true;
  v_lacuna  boolean := false;
  v_dupe    boolean := false;
  v_nsrs    bigint[] := ARRAY[]::bigint[];
  v_nsr     bigint;
  v_min bigint; v_max bigint; v_cnt int; v_distintos int;
  v_erros   jsonb := '[]'::jsonb;
  v_quarentena boolean;
  v_rejeitados int := 0;
  v_sha_calc text; v_sha_dec text;
  v_status  text;
  v_ja      int;
BEGIN
  -- Reimportação: se ESTE mesmo arquivo (hash) já entrou validado por outra
  -- importação do tenant, recusa como duplicado (nao reprocessa).
  SELECT count(*) INTO v_ja FROM public.ponto_repc_importacoes
  WHERE tenant_id = p_tenant_id AND arquivo_hash = p_arquivo_hash
    AND id <> p_importacao_id AND COALESCE(quarentena,false) = false
    AND COALESCE(status,'') = 'concluido';
  IF v_ja > 0 THEN
    v_dupe := true;
    v_erros := v_erros || jsonb_build_object('erro','arquivo_duplicado',
      'detalhe','Arquivo com o mesmo hash ja foi importado neste tenant.');
  END IF;

  -- Varre os registros: CRC por linha, coleta NSR de marcacao, cadeia do trailer.
  FOR rec IN SELECT * FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb))
  LOOP
    v_tipo := rec->>'tipo';
    v_linha := rec->>'linha';

    -- CRC-16 por registro (quando o arquivo declara o CRC da linha).
    IF (rec ? 'crc') AND v_linha IS NOT NULL THEN
      v_crc_dec := NULLIF(rec->>'crc','')::int;
      IF v_crc_dec IS DISTINCT FROM public.ponto_afd_crc16(v_linha) THEN
        v_crc_ok := false; v_rejeitados := v_rejeitados + 1;
        v_erros := v_erros || jsonb_build_object('erro','crc_invalido',
          'tipo', v_tipo, 'nsr', rec->>'nsr');
      END IF;
    END IF;

    IF v_tipo = '3' THEN                    -- marcacao: entra na sequencia de NSR
      v_nsr := NULLIF(rec->>'nsr','')::bigint;
      IF v_nsr IS NOT NULL THEN v_nsrs := array_append(v_nsrs, v_nsr); END IF;
    ELSIF v_tipo = '7' THEN                 -- trailer: cadeia SHA-256 do conteudo
      IF (rec ? 'sha256') AND (rec ? 'conteudo') THEN
        v_sha_calc := encode(public.digest(rec->>'conteudo', 'sha256'), 'hex');
        v_sha_dec  := lower(rec->>'sha256');
        IF v_sha_dec IS DISTINCT FROM v_sha_calc THEN
          v_cadeia_ok := false;
          v_erros := v_erros || jsonb_build_object('erro','cadeia_sha256_invalida');
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- LACUNA de NSR: a sequencia dos registros de marcacao tem que ser inteira,
  -- sem buraco e sem repeticao. Buraco = registro removido -> recusa o arquivo
  -- POR INTEIRO (Portaria 671). A sequencia de NSR e sequencial por definicao.
  v_cnt := COALESCE(array_length(v_nsrs, 1), 0);
  IF v_cnt > 0 THEN
    SELECT min(x), max(x), count(*), count(DISTINCT x)
      INTO v_min, v_max, v_cnt, v_distintos
    FROM unnest(v_nsrs) AS x;
    IF v_distintos <> v_cnt OR (v_max - v_min + 1) <> v_cnt THEN
      v_lacuna := true;
      v_erros := v_erros || jsonb_build_object('erro','lacuna_nsr',
        'detalhe', format('Sequencia de NSR quebrada: %s registros entre %s e %s (esperado %s).',
                          v_cnt, v_min, v_max, (v_max - v_min + 1)));
    END IF;
  END IF;

  -- Verdito: qualquer prova que falha manda o arquivo INTEIRO para a quarentena.
  -- O status segue o dominio existente (concluido/erro); o flag quarentena marca
  -- que o 'erro' e reprovacao de integridade probatoria (nao falha operacional).
  v_quarentena := v_dupe OR v_lacuna OR NOT v_crc_ok OR NOT v_cadeia_ok
               OR NOT COALESCE(p_assinatura_valida, true);
  v_status := CASE WHEN v_quarentena THEN 'erro' ELSE 'concluido' END;

  UPDATE public.ponto_repc_importacoes SET
    arquivo_hash      = p_arquivo_hash,
    crc_valido        = v_crc_ok,
    cadeia_valida     = v_cadeia_ok,
    assinatura_valida = COALESCE(p_assinatura_valida, true),
    quarentena        = v_quarentena,
    status            = v_status,
    registros_rejeitados = v_rejeitados,
    erros             = v_erros,
    relatorio         = jsonb_build_object(
                          'crc_valido', v_crc_ok, 'cadeia_valida', v_cadeia_ok,
                          'assinatura_valida', COALESCE(p_assinatura_valida, true),
                          'lacuna_nsr', v_lacuna, 'duplicado', v_dupe,
                          'quarentena', v_quarentena, 'erros', v_erros),
    updated_at        = now()
  WHERE id = p_importacao_id AND tenant_id = p_tenant_id;

  -- Arquivo aprovado: guarda os registros nao-marcacao (tipo 4/6) na trilha do
  -- equipamento. Arquivo em quarentena NAO deixa nada entrar.
  IF NOT v_quarentena THEN
    FOR rec IN SELECT * FROM jsonb_array_elements(COALESCE(p_registros, '[]'::jsonb))
    LOOP
      v_tipo := rec->>'tipo';
      IF v_tipo IN ('4', '6') THEN
        INSERT INTO public.ponto_afd_eventos_equipamento (
          tenant_id, empresa_id, importacao_id, equipamento, nsr_origem,
          tipo_registro, data_hora, ajuste_relogio_de, ajuste_relogio_para,
          evento_sensivel_tipo, evento_sensivel_descricao
        ) VALUES (
          p_tenant_id, p_empresa_id, p_importacao_id, rec->>'equipamento',
          NULLIF(rec->>'nsr','')::bigint, v_tipo,
          NULLIF(rec->>'data_hora','')::timestamptz,
          NULLIF(rec->>'ajuste_de','')::timestamptz,
          NULLIF(rec->>'ajuste_para','')::timestamptz,
          rec->>'evento', rec->>'evento_desc'
        );
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'status', v_status, 'quarentena', v_quarentena,
    'crc_valido', v_crc_ok, 'cadeia_valida', v_cadeia_ok,
    'lacuna_nsr', v_lacuna, 'duplicado', v_dupe,
    'registros_rejeitados', v_rejeitados, 'erros', v_erros);
END;
$$;

COMMENT ON FUNCTION public.ponto_afd_validar_importacao(uuid, uuid, uuid, text, jsonb, boolean) IS
  'Confere a integridade de um AFD importado NO BANCO: CRC-16 por registro, cadeia SHA-256 do trailer, verdito de assinatura e LACUNA na sequencia de NSR (recusa o arquivo por inteiro). Poe o arquivo reprovado em quarentena e so guarda os eventos do equipamento (tipo 4/6) quando aprovado. Idempotente pelo hash do arquivo. PONTO-382/212/384.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | OK
--   marcacao_origem : t (ponto_marcacoes.nsr_origem/equipamento)
--   arquivo_unico   : t (constraint de unicidade do arquivo)
--   eventos_equip   : t (tabela dos registros nao-marcacao tipo 4/6)
--   validador       : t (ponto_afd_validar_importacao)
--   crc16           : t (ponto_afd_crc16 confere: 123456789 -> 10673)
-- ---------------------------------------------------------------------------
SELECT
  (public.qa_col_existe('ponto_marcacoes','%nsr_origem%') IS NOT NULL
     AND public.qa_col_existe('ponto_marcacoes','%equipamento%') IS NOT NULL)      AS marcacao_origem,
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conrelid='public.ponto_repc_importacoes'::regclass AND contype='u') AS arquivo_unico,
  (to_regclass('public.ponto_afd_eventos_equipamento') IS NOT NULL)                AS eventos_equip,
  (to_regprocedure('public.ponto_afd_validar_importacao(uuid,uuid,uuid,text,jsonb,boolean)') IS NOT NULL) AS validador,
  (public.ponto_afd_crc16('123456789') = 10673)                                    AS crc16,
  CASE WHEN public.qa_col_existe('ponto_marcacoes','%nsr_origem%') IS NOT NULL
        AND public.qa_col_existe('ponto_marcacoes','%equipamento%') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid='public.ponto_repc_importacoes'::regclass AND contype='u')
        AND to_regclass('public.ponto_afd_eventos_equipamento') IS NOT NULL
        AND to_regprocedure('public.ponto_afd_validar_importacao(uuid,uuid,uuid,text,jsonb,boolean)') IS NOT NULL
        AND public.ponto_afd_crc16('123456789') = 10673
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda7_comprovantes.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 7 (parte 1): comprovante como DOCUMENTO (nao como booleano)
-- Alvos: ponto_comprovantes (nova) + ponto_gerar_comprovante,
--        ponto_comprovante_vigiar_48h, ponto_comprovantes_extrair (novas)
-- PONTO-380 / PONTO-381 / PONTO-359
--
-- Hoje o comprovante e so um boolean (ponto_marcacoes.comprovante_gerado). A
-- Portaria MTP 671/2021 (REP-P) trata o comprovante como o RECIBO LEGAL do
-- trabalhador: um artefato com identificacao do empregador e do trabalhador,
-- data/hora e NSR, arquivado e vinculado a marcacao, disponibilizado em ate 48h
-- e extraivel por periodo pelo proprio trabalhador. O NSR ja existe na marcacao;
-- falta o documento.
--
-- O QUE FAZ (aditivo)
--   (1) ponto_comprovantes: o documento — empregador (empresa_cadastro),
--       trabalhador, data/hora, NSR, conteudo minimo, hash de integridade e
--       vinculo a marcacao. Com a trava do cercado (PONTO-270) e RLS por tenant.
--   (2) ponto_gerar_comprovante(tenant, marcacao_id): emite o comprovante da
--       marcacao (idempotente — um por marcacao), atribuindo o NSR quando falta
--       e disponibilizando na hora. Portaria 671.
--   (3) ponto_comprovante_vigiar_48h(tenant, empresa): vigia o prazo de 48h —
--       marcacao sem comprovante perto de estourar (preventivo) ou estourada
--       (critico) vira alerta.
--   (4) ponto_comprovantes_extrair(tenant, cpf, ini, fim): extracao por periodo
--       restrita ao proprio CPF (direito do trabalhador).
--
-- GARANTIAS: nao altera o motor de saldo, o espelho nem o fechamento. So cria o
-- documento, a emissao, a vigilancia e a extracao. Aditivo e idempotente
-- (roda duas vezes sem quebrar nem duplicar). Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- Garantia defensiva (idempotente): as colunas de que a emissao depende ja
-- existem na marcacao desde a onda 1; IF NOT EXISTS torna a entrega autossuficiente.
ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS nsr bigint;
ALTER TABLE public.ponto_marcacoes ADD COLUMN IF NOT EXISTS comprovante_gerado boolean DEFAULT false;

-- (1) Documento ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_comprovantes (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL,
  empresa_id         uuid,
  marcacao_id        uuid,
  colaborador_cpf    text NOT NULL,
  colaborador_nome   text,
  empregador_cnpj    text,
  empregador_nome    text,
  nsr                bigint,
  data_hora_marcacao timestamptz,
  conteudo           jsonb NOT NULL,
  hash_comprovante   text,
  disponibilizado_em timestamptz,
  arquivo_url        text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_comprovantes_marcacao_uk UNIQUE (tenant_id, marcacao_id)
);

CREATE INDEX IF NOT EXISTS idx_ponto_comprovantes_colab
  ON public.ponto_comprovantes (tenant_id, colaborador_cpf, data_hora_marcacao);

COMMENT ON TABLE public.ponto_comprovantes IS
  'Comprovante de registro de ponto como DOCUMENTO (Portaria MTP 671/2021, REP-P): empregador, trabalhador, data/hora, NSR, conteudo minimo, hash e vinculo a marcacao. Recibo legal do trabalhador.';

ALTER TABLE public.ponto_comprovantes ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_comprovantes'
         AND policyname='ponto_comprovantes_tenant') THEN
    CREATE POLICY ponto_comprovantes_tenant
      ON public.ponto_comprovantes
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

-- Trava do cercado do QA (isolamento de tenant) — PONTO-270.
DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_comprovantes'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_comprovantes
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_comprovantes', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_comprovantes');

-- (2) Emissao do comprovante --------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_gerar_comprovante(
  p_tenant_id   uuid,
  p_marcacao_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  m        RECORD;
  v_nsr    bigint;
  v_ec     RECORD;
  v_ts     timestamptz;
  v_cont   jsonb;
  v_id     uuid;
BEGIN
  SELECT * INTO m FROM public.ponto_marcacoes
  WHERE id = p_marcacao_id AND tenant_id = p_tenant_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Idempotente: um comprovante por marcacao.
  SELECT id INTO v_id FROM public.ponto_comprovantes
  WHERE tenant_id = p_tenant_id AND marcacao_id = p_marcacao_id;
  IF FOUND THEN
    RETURN v_id;
  END IF;

  -- NSR: usa o da marcacao; se faltar, atribui o proximo do tenant e grava.
  v_nsr := m.nsr;
  IF v_nsr IS NULL THEN
    SELECT COALESCE(MAX(nsr), 0) + 1 INTO v_nsr
    FROM public.ponto_marcacoes WHERE tenant_id = p_tenant_id;
    UPDATE public.ponto_marcacoes SET nsr = v_nsr WHERE id = p_marcacao_id;
  END IF;

  -- Empregador (empresa_cadastro), quando houver vinculo.
  BEGIN
    SELECT ec.razao_social, ec.cnpj INTO v_ec
    FROM public.empresa_cadastro ec WHERE ec.id = m.empresa_id;
  EXCEPTION WHEN OTHERS THEN
    v_ec := NULL;
  END;

  v_ts := (m.data_marcacao + m.hora_marcacao);

  v_cont := jsonb_build_object(
    'norma', 'Portaria MTP 671/2021 — comprovante de registro de ponto (REP-P)',
    'empregador', jsonb_build_object('razao_social', v_ec.razao_social, 'cnpj', v_ec.cnpj),
    'trabalhador', jsonb_build_object('nome', m.colaborador_nome, 'cpf', m.colaborador_cpf),
    'marcacao', jsonb_build_object('data', m.data_marcacao, 'hora', m.hora_marcacao, 'nsr', v_nsr)
  );

  INSERT INTO public.ponto_comprovantes (
    tenant_id, empresa_id, marcacao_id, colaborador_cpf, colaborador_nome,
    empregador_cnpj, empregador_nome, nsr, data_hora_marcacao, conteudo,
    hash_comprovante, disponibilizado_em
  ) VALUES (
    p_tenant_id, m.empresa_id, p_marcacao_id, m.colaborador_cpf, m.colaborador_nome,
    v_ec.cnpj, v_ec.razao_social, v_nsr, v_ts, v_cont,
    encode(public.digest(v_cont::text, 'sha256'), 'hex'), now()
  )
  RETURNING id INTO v_id;

  UPDATE public.ponto_marcacoes SET comprovante_gerado = true WHERE id = p_marcacao_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_gerar_comprovante(uuid, uuid) IS
  'Emite o comprovante (documento) da marcacao: empregador, trabalhador, data/hora, NSR, conteudo minimo e hash. Idempotente (um por marcacao); atribui o NSR quando falta. Portaria 671. PONTO-380.';

-- (3) Vigilancia do prazo de 48h ---------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_comprovante_vigiar_48h(
  p_tenant_id  uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n   int := 0;
  v_ins int;
  r     RECORD;
  v_ts  timestamptz;
  v_prazo timestamptz;
  v_sev text;
  v_tit text;
BEGIN
  -- Marcacoes recentes SEM comprovante: o prazo legal de 48h para disponibilizar
  -- o comprovante (Portaria 671, REP-P) esta perto de estourar ou ja estourou.
  FOR r IN
    SELECT m.id, m.tenant_id, m.empresa_id, m.colaborador_cpf, m.colaborador_nome,
           m.data_marcacao, m.hora_marcacao
    FROM public.ponto_marcacoes m
    LEFT JOIN public.ponto_comprovantes c
      ON c.tenant_id = m.tenant_id AND c.marcacao_id = m.id
    WHERE m.tenant_id = p_tenant_id
      AND (p_empresa_id IS NULL OR m.empresa_id = p_empresa_id)
      AND c.id IS NULL
      AND m.data_marcacao >= (CURRENT_DATE - 5)
      AND (m.data_marcacao + m.hora_marcacao) <= now()
  LOOP
    v_ts := (r.data_marcacao + r.hora_marcacao);
    v_prazo := v_ts + INTERVAL '48 hours';

    IF now() > v_prazo THEN
      v_sev := 'critica'; v_tit := 'Comprovante de ponto fora do prazo de 48h (REP-P)';
    ELSIF v_prazo - now() <= INTERVAL '12 hours' THEN
      v_sev := 'alta';    v_tit := 'Comprovante de ponto perto do prazo de 48h (REP-P)';
    ELSE
      CONTINUE;  -- ainda dentro da folga: nao alerta
    END IF;

    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT r.tenant_id, r.empresa_id, NULL, r.colaborador_nome, r.colaborador_cpf,
           'comprovante_prazo_48h', v_sev, v_tit,
           format('Marcacao de %s %s sem comprovante disponibilizado; prazo de 48h ate %s '
               || '(Portaria 671/2021). Emitir/disponibilizar o comprovante ao trabalhador.',
               r.data_marcacao, to_char(r.hora_marcacao,'HH24:MI'), to_char(v_prazo,'DD/MM/YYYY HH24:MI')),
           r.data_marcacao
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = r.tenant_id
        AND a.colaborador_cpf = r.colaborador_cpf
        AND a.tipo = 'comprovante_prazo_48h'
        AND a.data_referencia = r.data_marcacao
    );
    GET DIAGNOSTICS v_ins = ROW_COUNT;
    v_n := v_n + v_ins;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_comprovante_vigiar_48h(uuid, uuid) IS
  'Vigia o prazo de 48 horas do comprovante (REP-P): marcacao sem comprovante perto de estourar (preventivo) ou estourada (critico) vira alerta. Idempotente por colaborador/dia. PONTO-381.';

-- (4) Extracao por periodo (restrita ao proprio CPF) -------------------------
CREATE OR REPLACE FUNCTION public.ponto_comprovantes_extrair(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_ini date,
  p_fim date
)
RETURNS TABLE(
  data_hora timestamptz,
  nsr       bigint,
  empregador text,
  conteudo  jsonb,
  hash_comprovante text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Extracao dos comprovantes do periodo, restrita ao proprio CPF (direito do
  -- trabalhador no REP-P; janela minima de 48h). Portaria 671.
  SELECT c.data_hora_marcacao, c.nsr, c.empregador_nome, c.conteudo, c.hash_comprovante
  FROM public.ponto_comprovantes c
  WHERE c.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g')
        = regexp_replace(COALESCE(p_colaborador_cpf,''), '[^0-9]', '', 'g')
    AND c.data_hora_marcacao::date BETWEEN p_ini AND p_fim
  ORDER BY c.data_hora_marcacao;
$$;

COMMENT ON FUNCTION public.ponto_comprovantes_extrair(uuid, text, date, date) IS
  'Extracao dos comprovantes de um periodo, restrita ao proprio CPF (direito do trabalhador, REP-P). Portaria 671. PONTO-359.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | OK
--   tabela_documento : t  (ponto_comprovantes existe)
--   marcacao_tem_nsr : t  (ponto_marcacoes.nsr — o comprovante se identifica)
--   emissao_existe   : t  (ponto_gerar_comprovante)
--   vigilancia_48h   : t  (ponto_comprovante_vigiar_48h)
--   extracao_existe  : t  (ponto_comprovantes_extrair)
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_comprovantes') IS NOT NULL)                                    AS tabela_documento,
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='nsr') AS marcacao_tem_nsr,
  (to_regprocedure('public.ponto_gerar_comprovante(uuid,uuid)') IS NOT NULL)                 AS emissao_existe,
  (to_regprocedure('public.ponto_comprovante_vigiar_48h(uuid,uuid)') IS NOT NULL)            AS vigilancia_48h,
  (to_regprocedure('public.ponto_comprovantes_extrair(uuid,text,date,date)') IS NOT NULL)    AS extracao_existe,
  CASE WHEN to_regclass('public.ponto_comprovantes') IS NOT NULL
        AND to_regprocedure('public.ponto_gerar_comprovante(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.ponto_comprovante_vigiar_48h(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.ponto_comprovantes_extrair(uuid,text,date,date)') IS NOT NULL
        AND EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='nsr')
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda7_certificado_digital.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 7 (parte 4): gestao do certificado digital (ICP-Brasil)
-- Alvos: ponto_certificados_digitais (nova) + ponto_certificado_vigente,
--        ponto_certificado_vigiar_vencimento (novas)
-- PONTO-360
--
-- Nao existia gestao de certificado digital — nem cadastro, nem vigencia, nem
-- alerta. Sem isso, AFD/AEJ nao tem COM QUE ser assinados (.p7s, ICP-Brasil,
-- Portaria 671), e um certificado vencido paralisaria a emissao assinada na hora
-- da auditoria. Passa a existir o cadastro do certificado por empresa (tipo,
-- titular, numero de serie, emissor, vigencia e antecedencia do alerta), a
-- consulta do certificado vigente hoje (o que assina o .p7s) e a vigilancia do
-- vencimento (alerta preventivo e critico).
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem a emissao
-- de AFD/AEJ. So cadastra e vigia. Sem chave privada no banco (so metadados de
-- vigencia). Aditivo e idempotente. Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
-- (1) Cadastro do certificado -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_certificados_digitais (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id               uuid NOT NULL,
  empresa_id              uuid,
  certificado_digital_tipo text NOT NULL DEFAULT 'A1',   -- 'A1' | 'A3'
  icp_brasil              boolean NOT NULL DEFAULT true,  -- cadeia ICP-Brasil
  titular_nome            text,
  titular_documento       text,                           -- CPF/CNPJ do titular
  numero_serie            text,
  emissor                 text,                           -- Autoridade Certificadora
  fingerprint             text,
  valido_de               date,
  valido_ate              date,
  alerta_antecedencia_dias integer NOT NULL DEFAULT 30,
  arquivo_url             text,                           -- referencia ao .pfx/.cer (nao a chave privada)
  ativo                   boolean NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_certificados_digitais_tipo_chk
    CHECK (certificado_digital_tipo IN ('A1', 'A3'))
);

CREATE INDEX IF NOT EXISTS idx_ponto_certificados_digitais_vig
  ON public.ponto_certificados_digitais (tenant_id, empresa_id, valido_ate);

COMMENT ON TABLE public.ponto_certificados_digitais IS
  'Cadastro do certificado de assinatura digital (ICP-Brasil) por empresa: tipo (A1/A3), titular, numero de serie, emissor, vigencia e antecedencia do alerta. Metadados de vigencia — a chave privada NAO fica no banco. Assina o .p7s do AFD/AEJ (Portaria 671). PONTO-360.';

ALTER TABLE public.ponto_certificados_digitais ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_certificados_digitais'
         AND policyname='ponto_certificados_digitais_tenant') THEN
    CREATE POLICY ponto_certificados_digitais_tenant
      ON public.ponto_certificados_digitais
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_certificados_digitais'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_certificados_digitais
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_certificados_digitais', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_certificados_digitais');

-- (2) Certificado vigente hoje (assina o .p7s do AFD/AEJ) --------------------
CREATE OR REPLACE FUNCTION public.ponto_certificado_vigente(
  p_tenant_id  uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS public.ponto_certificados_digitais
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- O certificado ICP-Brasil vigente HOJE que assina o .p7s do AFD/AEJ. Um
  -- certificado vencido nao volta aqui — a emissao assinada nao usa vencido.
  SELECT c.*
  FROM public.ponto_certificados_digitais c
  WHERE c.tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR c.empresa_id = p_empresa_id
         OR (p_empresa_id IS NULL AND c.empresa_id IS NULL))
    AND c.ativo = true
    AND (c.valido_de  IS NULL OR c.valido_de  <= CURRENT_DATE)
    AND (c.valido_ate IS NULL OR c.valido_ate >= CURRENT_DATE)
  ORDER BY c.valido_ate DESC NULLS LAST
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.ponto_certificado_vigente(uuid, uuid) IS
  'Devolve o certificado ICP-Brasil vigente hoje (o que assina o .p7s do AFD/AEJ). Certificado vencido nao e devolvido. PONTO-360.';

-- (3) Vigilância do vencimento -----------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_certificado_vigiar_vencimento(
  p_tenant_id  uuid,
  p_empresa_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_n int := 0;
  v_ins int;
  r RECORD;
  v_sev text;
  v_tit text;
BEGIN
  -- Certificados ICP-Brasil ativos perto de vencer (antecedencia parametrizada)
  -- ou ja vencidos. Certificado vencido paralisa a emissao assinada (.p7s) do
  -- AFD/AEJ exatamente na hora da auditoria do Auditor-Fiscal.
  FOR r IN
    SELECT c.id, c.tenant_id, c.empresa_id, c.titular_nome, c.numero_serie,
           c.valido_ate, c.alerta_antecedencia_dias
    FROM public.ponto_certificados_digitais c
    WHERE c.tenant_id = p_tenant_id
      AND (p_empresa_id IS NULL OR c.empresa_id = p_empresa_id)
      AND c.ativo = true
      AND c.valido_ate IS NOT NULL
      AND c.valido_ate <= (CURRENT_DATE + COALESCE(c.alerta_antecedencia_dias, 30))
  LOOP
    IF r.valido_ate < CURRENT_DATE THEN
      v_sev := 'critica';
      v_tit := 'Certificado digital VENCIDO (assinatura ICP-Brasil paralisada)';
    ELSE
      v_sev := 'alta';
      v_tit := 'Certificado digital perto de vencer (assinatura ICP-Brasil)';
    END IF;

    INSERT INTO public.ponto_alertas
      (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
       tipo, severidade, titulo, descricao, data_referencia)
    SELECT r.tenant_id, r.empresa_id, NULL, NULL, NULL,
           'certificado_digital_vencimento', v_sev, v_tit,
           format('Certificado %s (titular %s) vence em %s. Renovar antes do vencimento — '
               || 'certificado vencido impede assinar o .p7s do AFD/AEJ (Portaria 671).',
               COALESCE(r.numero_serie,'-'), COALESCE(r.titular_nome,'-'),
               to_char(r.valido_ate, 'DD/MM/YYYY')),
           r.valido_ate
    WHERE NOT EXISTS (
      SELECT 1 FROM public.ponto_alertas a
      WHERE a.tenant_id = r.tenant_id
        AND a.tipo = 'certificado_digital_vencimento'
        AND a.data_referencia = r.valido_ate
        AND COALESCE(a.empresa_id::text,'') = COALESCE(r.empresa_id::text,'')
        AND a.titulo = v_tit
    );
    GET DIAGNOSTICS v_ins = ROW_COUNT;
    v_n := v_n + v_ins;
  END LOOP;

  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.ponto_certificado_vigiar_vencimento(uuid, uuid) IS
  'Vigia o vencimento do certificado digital (ICP-Brasil): alerta preventivo com a antecedencia parametrizada e critico quando ja vencido (paralisa a emissao assinada do .p7s do AFD/AEJ). Idempotente por certificado/vencimento. PONTO-360.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   cadastro_cert  : t (ponto_certificados_digitais + coluna certificado_digital_tipo)
--   vigente_existe : t (ponto_certificado_vigente)
--   vigia_existe   : t (ponto_certificado_vigiar_vencimento)
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_certificados_digitais') IS NOT NULL
     AND public.qa_col_existe('ponto_certificados_digitais','%certificado_digital%') IS NOT NULL) AS cadastro_cert,
  (to_regprocedure('public.ponto_certificado_vigente(uuid,uuid)') IS NOT NULL)                     AS vigente_existe,
  (to_regprocedure('public.ponto_certificado_vigiar_vencimento(uuid,uuid)') IS NOT NULL)           AS vigia_existe,
  CASE WHEN to_regclass('public.ponto_certificados_digitais') IS NOT NULL
        AND public.qa_col_existe('ponto_certificados_digitais','%certificado_digital%') IS NOT NULL
        AND to_regprocedure('public.ponto_certificado_vigente(uuid,uuid)') IS NOT NULL
        AND to_regprocedure('public.ponto_certificado_vigiar_vencimento(uuid,uuid)') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_onda7_dossie_fiscalizacao.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — ONDA 7 (parte 5): dossie de fiscalizacao + arquivamento (fecha a onda 7)
-- Alvos: ponto_dossies_fiscalizacao (nova) + ponto_arquivar_documento,
--        ponto_gerar_dossie_fiscalizacao (novas)
-- PONTO-392 / PONTO-393
--
-- Faltavam as duas pontas do acervo probatorio: (392) um empacotador que reunisse
-- AFD, AEJ, comprovantes, espelhos e a trilha num pacote com indice e hashes; e
-- (393) o arquivamento automatico das pecas no modulo Documentos (com pasta,
-- metadados e vinculo), sem upload manual. As pecas nasceram nas partes 1-4;
-- esta parte as junta e as arquiva.
--
-- GARANTIAS: nao altera o motor de saldo, o espelho, o fechamento nem as pecas.
-- So LE as pecas, monta o pacote e registra a referencia. Aditivo e idempotente.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';
-- (1) O pacote ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_dossies_fiscalizacao (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL,
  empresa_id    uuid,
  competencia   text NOT NULL,
  periodo_ini   date,
  periodo_fim   date,
  total_pecas   integer NOT NULL DEFAULT 0,
  indice        jsonb,
  hash_pacote   text,
  documento_id  uuid,
  gerado_em     timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ponto_dossies_fiscalizacao_comp
  ON public.ponto_dossies_fiscalizacao (tenant_id, empresa_id, competencia);

COMMENT ON TABLE public.ponto_dossies_fiscalizacao IS
  'Dossie de fiscalizacao do ponto: pacote da competencia que reune as pecas (AEJ, comprovantes, espelhos, AFD importado) com indice, contagens e hashes de integridade. PONTO-392.';

ALTER TABLE public.ponto_dossies_fiscalizacao ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
  IF to_regprocedure('public.get_user_tenant_id()') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='ponto_dossies_fiscalizacao'
         AND policyname='ponto_dossies_fiscalizacao_tenant') THEN
    CREATE POLICY ponto_dossies_fiscalizacao_tenant
      ON public.ponto_dossies_fiscalizacao
      FOR ALL
      USING (tenant_id = public.get_user_tenant_id())
      WITH CHECK (tenant_id = public.get_user_tenant_id());
  END IF;
END $rls$;

DO $cerca$
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname = 'qa_guarda_cercado'
         AND tgrelid = 'public.ponto_dossies_fiscalizacao'::regclass
         AND NOT tgisinternal) THEN
    CREATE TRIGGER qa_guarda_cercado
      BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_dossies_fiscalizacao
      FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado();
  END IF;
END $cerca$;

INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
SELECT 'ponto_dossies_fiscalizacao', 'Cerca generica: tabela tem tenant_id'
WHERE to_regclass('public.qa_tabelas_protegidas') IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                  WHERE x.tabela = 'ponto_dossies_fiscalizacao');

-- (2) Arquivamento no módulo Documentos --------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_arquivar_documento(
  p_tenant_id       uuid,
  p_empresa_id      uuid,
  p_colaborador_id  uuid,
  p_colaborador_nome text,
  p_colaborador_cpf text,
  p_nome            text,
  p_tipo            text,
  p_storage_path    text,
  p_classificacao   text DEFAULT 'comum',
  p_pasta_id        uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id    uuid;
  v_no_storage boolean;
BEGIN
  -- Idempotente: uma referencia por caminho de arquivo no tenant.
  SELECT id INTO v_id FROM public.documentos
  WHERE tenant_id = p_tenant_id AND storage_path = p_storage_path
  LIMIT 1;
  IF FOUND THEN
    RETURN v_id;
  END IF;

  -- Confere se o objeto fisico ja esta no repositorio de arquivos
  -- (storage.objects); a referencia nasce mesmo antes do upload, marcada.
  v_no_storage := EXISTS (
    SELECT 1 FROM storage.objects o WHERE o.name = p_storage_path
  );

  INSERT INTO public.documentos (
    tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
    nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path,
    status, classificacao, pasta_id, criado_por_nome, versao, versao_atual, total_versoes,
    observacoes
  ) VALUES (
    p_tenant_id, p_empresa_id, p_colaborador_id,
    COALESCE(p_colaborador_nome, '(documento da empresa)'), p_colaborador_cpf,
    p_nome, p_nome, p_tipo, 0, 'application/octet-stream', p_storage_path,
    'valido', COALESCE(p_classificacao, 'comum'), p_pasta_id, 'Ponto (automatico)', '1', 1, 1,
    CASE WHEN v_no_storage THEN 'Arquivo presente em storage.objects.'
         ELSE 'Referencia registrada; arquivo fisico pendente em storage.objects.' END
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_arquivar_documento(uuid, uuid, uuid, text, text, text, text, text, text, uuid) IS
  'Arquiva a referencia de uma peca do ponto no modulo Documentos (public.documentos) com classificacao e vinculo (empresa/colaborador), conferindo o objeto em storage.objects. Idempotente por storage_path. Sem upload manual. PONTO-393.';

-- (3) Gerador do dossiê -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_gerar_dossie_fiscalizacao(
  p_tenant_id   uuid,
  p_empresa_id  uuid,
  p_competencia text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + INTERVAL '1 month - 1 day')::date;
  v_indice jsonb := '[]'::jsonb;
  v_total  int := 0;
  v_c int; v_h text;
  v_hash_pacote text;
  v_id uuid;
  v_doc uuid;
BEGIN
  -- Monta o dossie de fiscalizacao reunindo as pecas da competencia, cada uma
  -- com sua contagem e um hash representativo (verificacao de integridade).

  -- AEJ (Arquivo Eletronico de Jornada) — parte 2.
  SELECT count(*), max(hash_arquivo) INTO v_c, v_h
  FROM public.ponto_arquivos_aej
  WHERE tenant_id = p_tenant_id AND competencia = p_competencia
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id);
  v_indice := v_indice || jsonb_build_object('peca','aej','quantidade',v_c,'hash',v_h);
  v_total := v_total + COALESCE(v_c,0);

  -- Comprovantes de registro de ponto — parte 1.
  SELECT count(*), encode(public.digest(COALESCE(string_agg(hash_comprovante, ',' ORDER BY hash_comprovante),''),'sha256'),'hex')
    INTO v_c, v_h
  FROM public.ponto_comprovantes
  WHERE tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
    AND data_hora_marcacao::date BETWEEN v_ini AND v_fim;
  v_indice := v_indice || jsonb_build_object('peca','comprovantes','quantidade',v_c,'hash',v_h);
  v_total := v_total + COALESCE(v_c,0);

  -- Espelhos de ponto (apuracao fechada) — onda 6.
  SELECT count(*), encode(public.digest(COALESCE(string_agg(COALESCE(assinatura_hash,''), ',' ORDER BY colaborador_cpf),''),'sha256'),'hex')
    INTO v_c, v_h
  FROM public.ponto_espelhos
  WHERE tenant_id = p_tenant_id AND competencia = p_competencia
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id);
  v_indice := v_indice || jsonb_build_object('peca','espelhos','quantidade',v_c,'hash',v_h);
  v_total := v_total + COALESCE(v_c,0);

  -- AFD importado e conferido (nao em quarentena) — parte 3.
  SELECT count(*), encode(public.digest(COALESCE(string_agg(COALESCE(arquivo_hash,''), ',' ORDER BY arquivo_hash),''),'sha256'),'hex')
    INTO v_c, v_h
  FROM public.ponto_repc_importacoes
  WHERE tenant_id = p_tenant_id
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
    AND COALESCE(quarentena, false) = false;
  v_indice := v_indice || jsonb_build_object('peca','afd_importado','quantidade',v_c,'hash',v_h);
  v_total := v_total + COALESCE(v_c,0);

  -- Hash do pacote: integridade do indice inteiro (verificacao de assinaturas).
  v_hash_pacote := encode(public.digest(v_indice::text, 'sha256'), 'hex');

  -- Idempotente: refaz o dossie desta competencia/empresa.
  DELETE FROM public.ponto_dossies_fiscalizacao
  WHERE tenant_id = p_tenant_id AND competencia = p_competencia
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id
         OR (p_empresa_id IS NULL AND empresa_id IS NULL));

  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, empresa_id, competencia, periodo_ini, periodo_fim, total_pecas, indice, hash_pacote)
  VALUES
    (p_tenant_id, p_empresa_id, p_competencia, v_ini, v_fim, v_total, v_indice, v_hash_pacote)
  RETURNING id INTO v_id;

  -- Arquiva a referencia do dossie no modulo Documentos (sem upload manual).
  v_doc := public.ponto_arquivar_documento(
    p_tenant_id, p_empresa_id, NULL, NULL, NULL,
    format('Dossie de fiscalizacao %s.json', p_competencia),
    'dossie_fiscalizacao',
    format('ponto/dossie/%s/%s.json', COALESCE(p_empresa_id::text,'tenant'), p_competencia),
    'comum', NULL);

  UPDATE public.ponto_dossies_fiscalizacao SET documento_id = v_doc WHERE id = v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.ponto_gerar_dossie_fiscalizacao(uuid, uuid, text) IS
  'Monta o dossie de fiscalizacao da competencia reunindo AEJ, comprovantes, espelhos e AFD importado, com indice, contagens e hashes (verificacao de integridade), e arquiva a referencia no modulo Documentos. Idempotente. PONTO-392.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | OK
--   pacote_dossie  : t (ponto_dossies_fiscalizacao)
--   arquivar       : t (ponto_arquivar_documento — grava no modulo Documentos)
--   gerador_dossie : t (ponto_gerar_dossie_fiscalizacao)
-- ---------------------------------------------------------------------------
SELECT
  (to_regclass('public.ponto_dossies_fiscalizacao') IS NOT NULL)                                        AS pacote_dossie,
  (to_regprocedure('public.ponto_arquivar_documento(uuid,uuid,uuid,text,text,text,text,text,text,uuid)') IS NOT NULL) AS arquivar,
  (to_regprocedure('public.ponto_gerar_dossie_fiscalizacao(uuid,uuid,text)') IS NOT NULL)               AS gerador_dossie,
  CASE WHEN to_regclass('public.ponto_dossies_fiscalizacao') IS NOT NULL
        AND to_regprocedure('public.ponto_arquivar_documento(uuid,uuid,uuid,text,text,text,text,text,text,uuid)') IS NOT NULL
        AND to_regprocedure('public.ponto_gerar_dossie_fiscalizacao(uuid,uuid,text)') IS NOT NULL
       THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico;


-- ============================================================================

-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (fim) — a mesma contagem, agora depois da parte.
-- ---------------------------------------------------------------------
DO $volume2$
DECLARE
  v record;
  n bigint;
  m text;
BEGIN
  FOR v IN SELECT tabela FROM public.ponto_entrega_volume
            WHERE parte = 10 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 10 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_gerar_aej', 'Portaria MTP 671/2021 — AEJ (Arquivo Eletronico de Jornada)'),
    ('funcao', 'ponto_aej_extrair', NULL),
    ('funcao', 'ponto_afd_crc16', NULL),
    ('funcao', 'ponto_afd_validar_importacao', 'Arquivo com o mesmo hash ja foi importado neste tenant.'),
    ('funcao', 'ponto_gerar_comprovante', 'Portaria MTP 671/2021 — comprovante de registro de ponto (REP-P)'),
    ('funcao', 'ponto_comprovante_vigiar_48h', 'Comprovante de ponto fora do prazo de 48h (REP-P)'),
    ('funcao', 'ponto_comprovantes_extrair', NULL),
    ('funcao', 'ponto_certificado_vigente', NULL),
    ('funcao', 'ponto_certificado_vigiar_vencimento', 'Certificado digital VENCIDO (assinatura ICP-Brasil paralisada)'),
    ('funcao', 'ponto_arquivar_documento', 'Arquivo presente em storage.objects.'),
    ('funcao', 'ponto_gerar_dossie_fiscalizacao', ', COALESCE(p_empresa_id::text,'),
    ('tabela', 'ponto_arquivos_aej', NULL),
    ('tabela', 'ponto_afd_eventos_equipamento', NULL),
    ('tabela', 'ponto_comprovantes', NULL),
    ('tabela', 'ponto_certificados_digitais', NULL),
    ('tabela', 'ponto_dossies_fiscalizacao', NULL),
    ('indice', 'idx_ponto_arquivos_aej_comp', NULL),
    ('indice', 'ponto_marcacoes_origem_afd_uk', NULL),
    ('indice', 'idx_ponto_afd_eventos_equip', NULL),
    ('indice', 'idx_ponto_comprovantes_colab', NULL),
    ('indice', 'idx_ponto_certificados_digitais_vig', NULL),
    ('indice', 'idx_ponto_dossies_fiscalizacao_comp', NULL),
    ('coluna', 'ponto_repc_importacoes.arquivo_hash', NULL),
    ('coluna', 'ponto_repc_importacoes.crc_valido', NULL),
    ('coluna', 'ponto_repc_importacoes.assinatura_valida', NULL),
    ('coluna', 'ponto_repc_importacoes.cadeia_valida', NULL),
    ('coluna', 'ponto_repc_importacoes.quarentena', NULL),
    ('coluna', 'ponto_repc_importacoes.relatorio', NULL),
    ('coluna', 'ponto_marcacoes.nsr_origem', NULL),
    ('coluna', 'ponto_marcacoes.equipamento', NULL),
    ('coluna', 'ponto_marcacoes.nsr', NULL),
    ('coluna', 'ponto_marcacoes.comprovante_gerado', NULL)
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
), volume AS MATERIALIZED (
  SELECT v.tabela, v.linhas_antes AS antes, COALESCE(v.linhas_depois, v.linhas_antes) AS agora,
         v.marca_antes, v.marca_depois
  FROM public.ponto_entrega_volume v
  WHERE v.parte = 10
)
SELECT 'peca faltando'::text AS o_que, tipo || ' ' || nome AS detalhe, 'FALTOU'::text AS situacao
FROM estado WHERE NOT presente
UNION ALL
SELECT 'volume', tabela || ': ' || antes || ' para ' || agora || ' linha(s)',
       CASE WHEN agora = antes THEN 'sem alteracao' ELSE 'MUDOU ' || (agora - antes) || ' linha(s)' END
FROM volume WHERE agora <> antes
UNION ALL
SELECT 'volume', tabela || ': conteudo alterado (ultima alteracao passou de '
       || COALESCE(marca_antes, '-') || ' para ' || COALESCE(marca_depois, '-') || ')',
       'CONFERIR — ou e movimento normal de cliente durante a execucao'
FROM volume WHERE marca_antes IS DISTINCT FROM marca_depois
  AND tabela <> ''
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar; '
         || COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0)::text
         || ' linha(s) de dado vivo alteradas',
       CASE
         WHEN (SELECT count(*) FROM estado WHERE NOT presente) > 0 THEN 'CONFERIR — falta peca'
         WHEN false THEN 'OK'
         WHEN COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0) > 0
           THEN 'CONFERIR — esta parte nao deveria alterar dado vivo'
         ELSE 'OK'
       END
ORDER BY 1 DESC, 2;
