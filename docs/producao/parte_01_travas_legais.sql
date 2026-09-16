-- ============================================================================
-- PRODUCAO — PONTO, PARTE 01 de 16
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
  DELETE FROM public.ponto_entrega_volume WHERE parte = 1;
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
    VALUES (1, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda0_travas_legais.sql
-- ############################################################

-- ============================================================================
-- SCRIPT DE ENTREGA — PONTO, ONDA 0: travas legais de risco aberto
-- Cole no SQL Editor do banco de PRODUÇÃO (projeto diayjpsrcerycycyaxst)
-- SOMENTE após aprovar no ambiente de teste. Idempotente (pode rodar 2x).
--
-- O QUE ESTE SCRIPT FAZ
--   PONTO-396  colaborador comum passa a ler apenas o próprio ponto (LGPD)
--   PONTO-376  marcação com data/hora no futuro é recusada
--   PONTO-043  tolerância acima do teto legal é recusada no cadastro
--   PONTO-063  CCT com intervalo abaixo de 30 min é recusada
--   PONTO-372  modo "por exceção" exige o acordo anexado
--   PONTO-270  instala a trava do cercado na tabela que ficou de fora
--
-- O QUE ESTE SCRIPT NÃO FAZ
--   Não altera nenhum cálculo de jornada. Saldo, espelho, banco de horas e
--   apuração saem daqui idênticos. Todas as mudanças são de ACESSO (quem lê
--   o quê) ou de VALIDAÇÃO DE CADASTRO (o que pode ser gravado dali em diante).
--
-- REGISTROS LEGADOS
--   As validações valem para o que for criado ou efetivamente alterado. Um
--   cadastro antigo fora da faixa continua editável nos demais campos — só
--   não pode ser regravado fora da faixa. A conferência final lista quantos
--   existem, para correção manual.
-- ============================================================================

SET LOCAL lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- PONTO-396 — Colaborador comum lê apenas o próprio ponto
-- LGPD arts. 6º e 46. Vale para as duas tabelas com dado sensível nominal:
-- as batidas (com geolocalização e selfie) e os espelhos. NÃO alcança
-- ponto_diario, que é lida de forma agregada por telas de outros módulos
-- (contraprova do psicossocial, Hub Contábil) — restringi-la faria esses
-- indicadores somarem só os dias do próprio leitor, errando em silêncio.
-- Mesmo portão já usado em 20 tabelas sensíveis
-- (saúde, férias, psicossocial): perfil_permite_modulo libera superadmin,
-- papel de gestão para cima, tipo administrador/gestor e perfil de escopo
-- amplo. Quem não passa cai no próprio CPF.
-- ---------------------------------------------------------------------------
DO $ponto396$
DECLARE
  v_tabela text;
BEGIN
  FOREACH v_tabela IN ARRAY ARRAY['ponto_marcacoes', 'ponto_espelhos'] LOOP
    BEGIN
      IF to_regclass('public.' || v_tabela) IS NULL THEN
        RAISE NOTICE 'Tabela % nao existe: politica ignorada.', v_tabela;
        CONTINUE;
      END IF;

      EXECUTE format(
        'DROP POLICY IF EXISTS perfil_restringe_leitura_%1$s ON public.%1$I', v_tabela);

      EXECUTE format($pol$
        CREATE POLICY perfil_restringe_leitura_%1$s
        ON public.%1$I
        AS RESTRICTIVE
        FOR SELECT
        TO authenticated
        USING (
          public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ponto', 'colaboradores'])
          OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g')
             = public.cpf_do_usuario_logado()
        )
      $pol$, v_tabela);

      RAISE NOTICE 'Politica de leitura aplicada em %.', v_tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'PONTO-396 falhou em %: %', v_tabela, SQLERRM;
    END;
  END LOOP;
END $ponto396$;

-- ---------------------------------------------------------------------------
-- PONTO-376 — Marcação no futuro é recusada
-- Portaria MTP 671/2021: o registro reflete fielmente o momento da marcação.
-- Só a marcação ORIGINAL passa pela trava — ajuste e abono aprovados por
-- gestor são atos administrativos e podem referir-se a dia planejado.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_bloquear_marcacao_futura()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_agora   timestamp := timezone('America/Sao_Paulo', now());
  v_marcada timestamp;
  v_folga   interval := interval '5 minutes';
BEGIN
  IF COALESCE(NEW.marcacao_original, true) IS NOT TRUE THEN
    RETURN NEW;
  END IF;
  IF NEW.data_marcacao IS NULL OR NEW.hora_marcacao IS NULL THEN
    RETURN NEW;
  END IF;

  v_marcada := NEW.data_marcacao + NEW.hora_marcacao;

  IF v_marcada > v_agora + v_folga THEN
    RAISE EXCEPTION
      'Marcacao de ponto no futuro nao e aceita: informada %, agora %. Confira o relogio do dispositivo.',
      to_char(v_marcada, 'DD/MM/YYYY HH24:MI'),
      to_char(v_agora,  'DD/MM/YYYY HH24:MI');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_bloquear_marcacao_futura ON public.ponto_marcacoes;
CREATE TRIGGER trg_ponto_bloquear_marcacao_futura
BEFORE INSERT ON public.ponto_marcacoes
FOR EACH ROW
EXECUTE FUNCTION public.ponto_bloquear_marcacao_futura();

-- ---------------------------------------------------------------------------
-- PONTO-043 — Tolerância acima do teto legal é recusada
-- CLT art. 58, §1º (5 por marcação, 10 no dia); Súmula 449 do TST veda
-- ampliar inclusive por norma coletiva. Reduzir é permitido, zero inclusive.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_validar_tolerancia_escala()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.tolerancia_minutos IS DISTINCT FROM OLD.tolerancia_minutos THEN
    IF NEW.tolerancia_minutos IS NOT NULL
       AND (NEW.tolerancia_minutos < 0 OR NEW.tolerancia_minutos > 5) THEN
      RAISE EXCEPTION
        'Tolerancia por marcacao deve ficar entre 0 e 5 minutos (CLT art. 58, §1º; Sumula 449 do TST veda ampliar, inclusive por norma coletiva). Valor recusado: %.',
        NEW.tolerancia_minutos;
    END IF;
  END IF;

  IF TG_OP = 'INSERT'
     OR NEW.tolerancia_diaria_minutos IS DISTINCT FROM OLD.tolerancia_diaria_minutos THEN
    IF NEW.tolerancia_diaria_minutos IS NOT NULL
       AND (NEW.tolerancia_diaria_minutos < 0 OR NEW.tolerancia_diaria_minutos > 10) THEN
      RAISE EXCEPTION
        'Tolerancia diaria deve ficar entre 0 e 10 minutos (CLT art. 58, §1º; Sumula 449 do TST). Valor recusado: %.',
        NEW.tolerancia_diaria_minutos;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_validar_tolerancia_escala ON public.ponto_escalas;
CREATE TRIGGER trg_ponto_validar_tolerancia_escala
BEFORE INSERT OR UPDATE ON public.ponto_escalas
FOR EACH ROW
EXECUTE FUNCTION public.ponto_validar_tolerancia_escala();

-- ---------------------------------------------------------------------------
-- PONTO-063 — CCT não pode furar o piso de 30 minutos (CLT art. 611-A, III)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_validar_intervalo_cct()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.intervalo_minimo_min IS DISTINCT FROM OLD.intervalo_minimo_min THEN
    IF NEW.intervalo_minimo_min IS NOT NULL AND NEW.intervalo_minimo_min < 30 THEN
      RAISE EXCEPTION
        'Intervalo minimo por norma coletiva nao pode ficar abaixo de 30 minutos (CLT art. 611-A, III). Valor recusado: %.',
        NEW.intervalo_minimo_min;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_validar_intervalo_cct ON public.ponto_cct_config;
CREATE TRIGGER trg_ponto_validar_intervalo_cct
BEFORE INSERT OR UPDATE ON public.ponto_cct_config
FOR EACH ROW
EXECUTE FUNCTION public.ponto_validar_intervalo_cct();

-- ---------------------------------------------------------------------------
-- PONTO-372 — Registro por exceção exige o acordo anexado (CLT art. 74, §4º)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ponto_validar_acordo_excecao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.modo_apuracao IS DISTINCT FROM OLD.modo_apuracao
     OR NEW.ponto_excecao_acordo_url IS DISTINCT FROM OLD.ponto_excecao_acordo_url THEN
    IF COALESCE(NEW.modo_apuracao, '') = 'por_excecao'
       AND btrim(COALESCE(NEW.ponto_excecao_acordo_url, '')) = '' THEN
      RAISE EXCEPTION
        'Registro por excecao exige o acordo anexado (CLT art. 74, §4º): preencha o documento autorizador antes de ativar o modo.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_validar_acordo_excecao ON public.ponto_configuracao;
CREATE TRIGGER trg_ponto_validar_acordo_excecao
BEFORE INSERT OR UPDATE ON public.ponto_configuracao
FOR EACH ROW
EXECUTE FUNCTION public.ponto_validar_acordo_excecao();

-- ---------------------------------------------------------------------------
-- PONTO-270 — Trava do cercado na tabela que ficou de fora
-- ---------------------------------------------------------------------------
DO $ponto270$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'qa_instalar_cercas';
  IF NOT FOUND THEN
    RAISE NOTICE 'Motor de QA nao instalado nesta base: cercas ignoradas.';
    RETURN;
  END IF;
  PERFORM * FROM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas do cercado de teste reinstaladas.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel instalar as cercas: %', SQLERRM;
END $ponto270$;

-- ============================================================================
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: 2 políticas, 4 gatilhos, situacao = 'OK'.
-- As três últimas colunas devem idealmente ser 0. Se vierem acima de zero,
-- são cadastros ANTIGOS fora da faixa legal: continuam funcionando, mas
-- produzem apuração irregular e precisam de correção manual na tela.
-- ============================================================================
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname IN ('perfil_restringe_leitura_ponto_marcacoes',
                         'perfil_restringe_leitura_ponto_espelhos'))              AS politicas_de_leitura,

  (SELECT count(*) FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname IN ('trg_ponto_bloquear_marcacao_futura',
                     'trg_ponto_validar_tolerancia_escala',
                     'trg_ponto_validar_intervalo_cct',
                     'trg_ponto_validar_acordo_excecao'))                         AS gatilhos_de_validacao,

  (SELECT count(*) FROM public.ponto_escalas
    WHERE COALESCE(tolerancia_minutos, 0) > 5
       OR COALESCE(tolerancia_diaria_minutos, 0) > 10)                            AS escalas_legadas_fora_da_faixa,

  (SELECT count(*) FROM public.ponto_cct_config
    WHERE intervalo_minimo_min IS NOT NULL AND intervalo_minimo_min < 30)         AS ccts_legadas_abaixo_do_piso,

  (SELECT count(*) FROM public.ponto_configuracao
    WHERE modo_apuracao = 'por_excecao'
      AND btrim(COALESCE(ponto_excecao_acordo_url, '')) = '')                     AS excecoes_legadas_sem_acordo,

  CASE
    WHEN (SELECT count(*) FROM pg_policies
           WHERE schemaname = 'public'
             AND policyname IN ('perfil_restringe_leitura_ponto_marcacoes',
                                'perfil_restringe_leitura_ponto_espelhos')) < 2
      THEN 'ERRO: faltou politica de leitura — a exposicao de dados segue aberta'
    WHEN (SELECT count(*) FROM pg_trigger
           WHERE NOT tgisinternal
             AND tgname IN ('trg_ponto_bloquear_marcacao_futura',
                            'trg_ponto_validar_tolerancia_escala',
                            'trg_ponto_validar_intervalo_cct',
                            'trg_ponto_validar_acordo_excecao')) < 4
      THEN 'ERRO: faltou gatilho de validacao'
    ELSE 'OK'
  END                                                                             AS erro_tecnico;


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
            WHERE parte = 1 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 1 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_bloquear_marcacao_futura', NULL),
    ('funcao', 'ponto_validar_tolerancia_escala', NULL),
    ('funcao', 'ponto_validar_intervalo_cct', NULL),
    ('funcao', 'ponto_validar_acordo_excecao', NULL),
    ('gatilho', 'trg_ponto_bloquear_marcacao_futura', NULL),
    ('gatilho', 'trg_ponto_validar_tolerancia_escala', NULL),
    ('gatilho', 'trg_ponto_validar_intervalo_cct', NULL),
    ('gatilho', 'trg_ponto_validar_acordo_excecao', NULL)
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
  WHERE v.parte = 1
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
