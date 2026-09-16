-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 01 de 16: Travas legais de cadastro e marcacao
--
-- Recusa marcacao com data/hora futura, tolerancia acima do teto legal (5/10
-- min), intervalo de CCT abaixo do piso de 30 min e modo "registro por
-- excecao" sem acordo anexado.
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a 16, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
--   * script_ponto_onda0_travas_legais.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



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
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
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
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
