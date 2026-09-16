-- ============================================================================
-- ENTREGA — correcoes apontadas pela bateria na homologacao (PONTO-191, 354)
--
-- Os dois ultimos casos do Ponto que nao passavam na homologacao. Nenhum dos
-- dois era defeito de comportamento — os dois eram defeito de ENTREGA e de
-- FERRAMENTA, e so apareceram porque a bancada passou a rodar contra a
-- estrutura real, com dado de cliente por perto.
--
-- (A) PONTO-191 — a verificacao da cadeia de hash EXISTE na producao e esta
--     correta (encadeada), mas o caso reprovava. Causa: a sonda procura uma
--     funcao cujo CORPO contenha "hash_marcacao" e "verific". No projeto a
--     palavra aparece num comentario DENTRO do corpo; no script de entrega da
--     Onda 2 o mesmo comentario ficou FORA do corpo (antes da abertura do
--     corpo),
--     e comentario fora do corpo nao chega ao prosrc. Script de entrega e
--     migration divergiram — a producao recebeu uma versao diferente da que o
--     projeto tem.
--     Correcao: instalar a versao ATUAL do projeto. E so a funcao de
--     verificacao, que apenas LE (devolve as quebras encontradas); nao toca em
--     hash gravado, nao altera marcacao, nao muda o gatilho de gravacao.
--
-- (B) PONTO-354 — o caso quebrava com
--       "QA BLOQUEADO: modo de teste ligado. Operacao UPDATE em
--        public.ponto_banco_horas tentou tocar o tenant 83f1b040-..."
--     Ou seja: a TRAVA DO CERCADO funcionou. O caso chama
--     converter_banco_horas_vencido(), que e global — varre TODOS os tenants.
--     Numa base sem dado de cliente (o ambiente de teste) isso nunca aparece;
--     numa base com dado de cliente (homologacao, producao) o teste tenta
--     tocar linha de terceiro e a trava aborta, como deve.
--     Consequencia: este caso era INEXECUTAVEL em qualquer base com dado real
--     — inclusive a producao, que e onde a bancada mais precisa rodar.
--     Correcao: a rotina ganha um parametro OPCIONAL de tenant. Sem
--     argumento, o comportamento e identico ao de hoje (todos os tenants);
--     com argumento, so aquele. O caso passa a escopar a conversao no cercado.
--
-- NOTA (nao e alteracao deste pacote, e observacao): converter_banco_horas_vencido
-- nao esta agendada em lugar nenhum — nem cron, nem tela, nem outra funcao. Na
-- pratica, saldo de banco de horas vencido nao esta sendo convertido sozinho na
-- producao. E decisao de produto, fora do escopo desta correcao.
--
-- Idempotente; nao altera o motor de saldo, o espelho nem o fechamento.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (A) PONTO-191 — versao atual da verificacao da cadeia (somente leitura)
-- ---------------------------------------------------------------------------
DO $guarda191$
BEGIN
  -- A verificacao da cadeia le a coluna nsr das marcacoes. Onde a NSR ainda
  -- nao existe (ambiente que nao recebeu a onda do AFD), a criacao falharia
  -- na validacao e — por rodar tudo em UMA transacao — derrubaria tambem a
  -- correcao (B). Entao ela so entra quando a coluna existe; do contrario o
  -- arquivo segue e avisa. Sem NSR nao ha o que encadear, mesmo.
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'ponto_marcacoes'
       AND column_name = 'nsr'
  ) THEN
    EXECUTE $def191$
CREATE OR REPLACE FUNCTION public.ponto_verificar_cadeia_hash(p_tenant_id uuid DEFAULT NULL::uuid, p_empresa_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(tenant_id uuid, empresa_id uuid, nsr bigint, marcacao_id uuid, tipo_quebra text, detalhe text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Verificacao da cadeia: recomputa cada hash_marcacao e confere o
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
  )
  SELECT tenant_id, empresa_id, nsr, id AS marcacao_id,
         CASE
           WHEN encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
                    || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
                <> hash_marcacao
             THEN 'hash_adulterado'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'cadeia_quebrada'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN 'nsr_faltante'
         END AS tipo_quebra,
         CASE
           WHEN encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
                    || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
                <> hash_marcacao
             THEN 'Hash gravado nao confere com o recomputado do conteudo (marcacao alterada).'
           WHEN hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash
             THEN 'Encadeamento rompido: o hash_anterior nao bate com o hash da marcacao anterior.'
           WHEN prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1
             THEN format('Salto de NSR (%s -> %s): pode haver marcacao removida.', prev_nsr, nsr)
         END AS detalhe
  FROM marcs
  WHERE encode(sha256((colaborador_cpf || data_marcacao::text || hora_marcacao::text
             || tipo_marcacao || ((created_at AT TIME ZONE 'UTC')::text || '+00') || COALESCE(hash_anterior,''))::bytea),'hex')
             <> hash_marcacao
     OR (hash_anterior IS NOT NULL AND prev_hash IS NOT NULL AND hash_anterior <> prev_hash)
     OR (prev_nsr IS NOT NULL AND nsr <> prev_nsr + 1)
  ORDER BY tenant_id, empresa_id NULLS FIRST, nsr;
$function$
$def191$;
    RAISE NOTICE 'PONTO-191: verificacao da cadeia de hash atualizada.';
  ELSE
    RAISE NOTICE 'PONTO-191 PULADO: este ambiente nao tem a coluna nsr em ponto_marcacoes — sem NSR nao ha cadeia a verificar. A correcao (B), do PONTO-354, foi aplicada normalmente.';
  END IF;
END $guarda191$;

-- ---------------------------------------------------------------------------
-- (B) PONTO-354 — conversao de saldo vencido com escopo opcional de tenant
--     A antiga sem argumento sai de cena para nao virar sobrecarga ambigua:
--     a nova, com parametro opcional, atende a chamada sem argumento igual.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.converter_banco_horas_vencido();

CREATE OR REPLACE FUNCTION public.converter_banco_horas_vencido(p_tenant uuid DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_banco RECORD;
BEGIN
  FOR v_banco IN
    SELECT * FROM public.ponto_banco_horas
    WHERE convertido_extras = FALSE
      AND prazo_compensacao IS NOT NULL
      AND prazo_compensacao < CURRENT_DATE
      AND saldo_atual_minutos > 0
      -- Sem argumento, o comportamento e o de sempre: todos os tenants.
      -- Com argumento, so aquele — e a bancada de QA consegue exercitar a
      -- conversao dentro do cercado, sem tentar tocar dado de cliente.
      AND (p_tenant IS NULL OR tenant_id = p_tenant)
  LOOP
    -- Mark as converted
    UPDATE public.ponto_banco_horas
    SET convertido_extras = TRUE,
        data_conversao = CURRENT_DATE,
        observacoes = COALESCE(observacoes, '') || ' [Convertido automaticamente em HE em ' || CURRENT_DATE::TEXT || '. Saldo: ' || v_banco.saldo_atual_minutos || ' min]'
    WHERE id = v_banco.id;

    -- Register conversion movement
    INSERT INTO public.ponto_banco_horas_movimentacoes (
      tenant_id, banco_horas_id, colaborador_cpf, data_referencia, tipo, minutos, descricao
    ) VALUES (
      v_banco.tenant_id, v_banco.id, v_banco.colaborador_cpf, CURRENT_DATE,
      'conversao_he', v_banco.saldo_atual_minutos,
      'Conversão automática: prazo de compensação vencido em ' || v_banco.prazo_compensacao::TEXT
    );
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.converter_banco_horas_vencido(uuid) IS
  'Converte em horas extras o saldo de banco de horas com prazo de compensacao vencido. Sem argumento: todos os tenants (comportamento historico). Com argumento: apenas aquele tenant — o que permite a bancada de QA exercitar a conversao dentro do cercado, sem tocar dado de cliente. PONTO-354.';

-- ---------------------------------------------------------------------------
-- (C) O caso de teste passa a escopar a conversao no cercado.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_354()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
  v_cpf text := public.qa_cpf(3541);
  v_apuracao_preenche boolean;
  v_convertido boolean;
  v_mov int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração do banco preenche o prazo de compensação?';
  r.esperado := 'apurar_banco_horas* deriva prazo_compensacao da configuração do regime (6m/12m)';

  SELECT bool_or(p.prosrc ILIKE '%prazo_compensacao%') INTO v_apuracao_preenche
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('apurar_banco_horas', 'apurar_banco_horas_colaborador');

  r.passo_ordem := 2;
  r.passo_acao := 'Semear saldo de 120 min com prazo vencido ontem e rodar a conversão automática';
  r.esperado := 'O saldo vencido vira hora extra: convertido_extras = true + movimentação de conversão';

  INSERT INTO public.ponto_banco_horas
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, tipo,
     competencia, saldo_anterior_minutos, creditos_minutos, debitos_minutos,
     compensados_minutos, saldo_atual_minutos, convertido_extras, prazo_compensacao)
  VALUES (public.qa_sandbox_tenant_id(), v_cpf, 'QA Vencimento Banco', v_cpf, 'mensal',
          to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'), 0, 120, 0, 0, 120,
          false, CURRENT_DATE - 1);

  PERFORM public.converter_banco_horas_vencido(public.qa_sandbox_tenant_id());

  SELECT b.convertido_extras,
         (SELECT count(*) FROM public.ponto_banco_horas_movimentacoes m
           WHERE m.banco_horas_id = b.id AND m.tipo = 'conversao_he')
    INTO v_convertido, v_mov
  FROM public.ponto_banco_horas b
  WHERE b.tenant_id = public.qa_sandbox_tenant_id() AND b.colaborador_cpf = v_cpf;

  IF NOT coalesce(v_convertido, false) OR coalesce(v_mov, 0) = 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('A conversão de saldo vencido não funcionou nem com o prazo semeado à mão '
             || '(convertido=%s, movimentações=%s). O saldo que passa do prazo legal precisa virar '
             || 'hora extra a pagar.', coalesce(v_convertido::text, 'NULL'), coalesce(v_mov, 0));
  ELSIF NOT coalesce(v_apuracao_preenche, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o mecanismo de conversão existe e funciona QUANDO o prazo está na linha '
             || '(o teste semeou o prazo à mão e o saldo foi convertido) — mas a APURAÇÃO nunca '
             || 'preenche prazo_compensacao. A configuração do regime até guarda '
             || 'prazo_compensacao_dias (ponto_banco_horas_config), só que nenhuma função de '
             || 'apuração a consulta. Resultado prático: nenhum saldo tem vencimento, a conversão '
             || 'automática nunca encontra o que converter, e saldos de banco individual passam '
             || 'dos 6 meses do art. 59, §5º (ou dos 12 meses do §2º) sem virar hora extra. '
             || 'Correção: ao apurar a competência, gravar prazo_compensacao = fim da competência '
             || '+ prazo_compensacao_dias do regime vigente.';
    r.detalhe := jsonb_build_object('conversao_funciona', true,
                                    'apuracao_preenche_prazo', false);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A apuração deriva o prazo do regime e a conversão de saldo vencido funciona.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $function$
;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
--
-- Esperado onde HA a coluna nsr:      t | t | t | t | OK
-- Esperado onde NAO HA a coluna nsr:  f | f | t | t | OK
--   (a parte 191 e pulada de proposito: sem NSR nao ha cadeia a verificar)
--
--   tem_nsr         : o ambiente tem ponto_marcacoes.nsr
--   p191_sonda_acha : a sonda do PONTO-191 encontra a funcao de verificacao
--   p191_encadeado  : a verificacao continua conferindo o hash anterior
--   p354_escopo     : converter_banco_horas_vencido(uuid) existe
--   p354_caso_escopa: o caso 354 chama a conversao com o cercado
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'ponto_marcacoes'
               AND column_name = 'nsr') AS tem_nsr,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
               AND p.prosrc ILIKE '%hash_marcacao%' AND p.prosrc ILIKE '%verific%') AS p191_sonda_acha,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_verificar_cadeia_hash'
               AND p.prosrc ILIKE '%anterior%') AS p191_encadeado,
    (to_regprocedure('public.converter_banco_horas_vencido(uuid)') IS NOT NULL) AS p354_escopo,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'qa_caso_ponto_354'
               AND p.prosrc ILIKE '%converter_banco_horas_vencido(public.qa_sandbox_tenant_id())%') AS p354_caso_escopa
)
SELECT p191_sonda_acha, p191_encadeado, p354_escopo, p354_caso_escopa,
       CASE
         -- Sem NSR, a parte 191 nao se aplica: o arquivo esta correto se a
         -- correcao do 354 entrou. O PONTO-191 seguira reprovando na bateria,
         -- e com razao: sem NSR nao ha numeracao sequencial a encadear.
         WHEN NOT tem_nsr AND p354_escopo AND p354_caso_escopa THEN 'OK'
         WHEN tem_nsr AND p191_sonda_acha AND p191_encadeado
              AND p354_escopo AND p354_caso_escopa THEN 'OK'
         ELSE 'CONFERIR'
       END AS erro_tecnico
FROM x;
