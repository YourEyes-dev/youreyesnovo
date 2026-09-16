-- ============================================================================
-- PRODUCAO — PONTO, PARTE 03 de 16
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
  DELETE FROM public.ponto_entrega_volume WHERE parte = 3;
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
    VALUES (3, t, n, m);
  END LOOP;
END $volume$;

-- ############################################################
-- BLOCO: script_ponto_onda1_nsr_e_lotacao.sql
-- ############################################################

-- ============================================================================
-- SCRIPT DE ENTREGA — PONTO, ONDA 1 (parte 1): NSR e histórico de lotação
-- Cole no SQL Editor do banco de PRODUÇÃO (projeto diayjpsrcerycycyaxst)
-- SOMENTE após aprovar no ambiente de teste. Idempotente (pode rodar 2x).
--
-- O QUE ESTE SCRIPT FAZ
--   PONTO-210  NSR — numeração sequencial da marcação, contínua e imutável
--   PONTO-395  histórico de lotação por estabelecimento, com vigência
--
-- O QUE ESTE SCRIPT NÃO FAZ
--   Não altera nenhum cálculo de jornada. São estruturas novas ao lado do
--   que já existe; nenhuma função de apuração passa a lê-las agora. Saldo,
--   espelho e banco de horas saem daqui idênticos.
--
-- DEPOIS DELE
--   As marcações NOVAS já nascem com NSR. As ANTIGAS ficam sem, até rodar
--   docs/script_ponto210_backfill_nsr.sql — que é separado de propósito:
--   cada alteração em ponto_marcacoes grava uma linha de auditoria com o
--   JSON inteiro, e fazer isso na tabela toda de uma vez inflaria a trilha
--   sem ninguém acompanhando. A conferência final diz quantas faltam.
-- ============================================================================

SET LOCAL lock_timeout = '10s';

-- =====================================================================
-- PONTO-210 — NSR (Número Sequencial de Registro)
-- =====================================================================
-- Portaria MTP 671/2021: é a numeração que demonstra que nenhum registro
-- foi removido. Sem ela o AFD improvisa números na exportação e não prova
-- nada.
--
-- ESCOPO DA SEQUÊNCIA: por (tenant, empresa). O AFD é gerado por
-- estabelecimento, então a sequência precisa ser contínua dentro de cada
-- arquivo. Marcação sem empresa cai num balde próprio do tenant.
--
-- POR QUE UMA TABELA DE CONTROLE E NÃO UMA SEQUENCE: sequence do Postgres
-- não devolve o número quando a transação desfaz — deixaria buracos, que é
-- exatamente o que o NSR existe para provar que não há. Com contador em
-- tabela, o desfazimento devolve o número junto.

ALTER TABLE public.ponto_marcacoes
  ADD COLUMN IF NOT EXISTS nsr bigint;

COMMENT ON COLUMN public.ponto_marcacoes.nsr IS
  'Portaria MTP 671/2021 — Numero Sequencial de Registro, continuo por (tenant, empresa) e imutavel. Nulo apenas em marcacoes anteriores a esta funcionalidade, ate rodar o preenchimento historico.';

CREATE TABLE IF NOT EXISTS public.ponto_nsr_controle (
  tenant_id   uuid        NOT NULL,
  empresa_id  uuid        NOT NULL,  -- sentinela zerada quando nao ha empresa
  ultimo_nsr  bigint      NOT NULL DEFAULT 0,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_nsr_controle_pk PRIMARY KEY (tenant_id, empresa_id)
);

COMMENT ON TABLE public.ponto_nsr_controle IS
  'Contador do NSR por (tenant, empresa). Sentinela 00000000-0000-0000-0000-000000000000 representa marcacao sem estabelecimento definido.';

ALTER TABLE public.ponto_nsr_controle ENABLE ROW LEVEL SECURITY;

DO $pol_nsr$
BEGIN
  DROP POLICY IF EXISTS "Tenant gerencia ponto_nsr_controle" ON public.ponto_nsr_controle;
  CREATE POLICY "Tenant gerencia ponto_nsr_controle"
    ON public.ponto_nsr_controle FOR ALL
    USING (tenant_id = public.current_user_tenant_id())
    WITH CHECK (tenant_id = public.current_user_tenant_id());
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politica de ponto_nsr_controle nao aplicada: %', SQLERRM;
END $pol_nsr$;

-- Entrega o próximo NSR do balde, travando a linha do contador. Duas
-- marcações simultâneas do mesmo estabelecimento entram em fila aqui —
-- é o preço de não ter buraco, e o volume por empregador comporta.
CREATE OR REPLACE FUNCTION public.ponto_proximo_nsr(p_tenant_id uuid, p_empresa_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_empresa uuid := COALESCE(p_empresa_id, '00000000-0000-0000-0000-000000000000'::uuid);
  v_nsr bigint;
BEGIN
  INSERT INTO public.ponto_nsr_controle (tenant_id, empresa_id, ultimo_nsr, updated_at)
  VALUES (p_tenant_id, v_empresa, 1, now())
  ON CONFLICT (tenant_id, empresa_id) DO UPDATE
    SET ultimo_nsr = public.ponto_nsr_controle.ultimo_nsr + 1,
        updated_at = now()
  RETURNING ultimo_nsr INTO v_nsr;

  RETURN v_nsr;
END;
$$;

CREATE OR REPLACE FUNCTION public.ponto_atribuir_nsr()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- O preenchimento histórico informa o NSR explicitamente; a marcação
  -- nova nunca informa, e recebe o próximo do balde.
  IF NEW.nsr IS NULL AND NEW.tenant_id IS NOT NULL THEN
    NEW.nsr := public.ponto_proximo_nsr(NEW.tenant_id, NEW.empresa_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_atribuir_nsr ON public.ponto_marcacoes;
CREATE TRIGGER trg_ponto_atribuir_nsr
BEFORE INSERT ON public.ponto_marcacoes
FOR EACH ROW
EXECUTE FUNCTION public.ponto_atribuir_nsr();

-- Um NSR nunca se repete dentro do balde.
CREATE UNIQUE INDEX IF NOT EXISTS ponto_marcacoes_nsr_unico
  ON public.ponto_marcacoes (tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), nsr)
  WHERE nsr IS NOT NULL;

-- ---------------------------------------------------------------------
-- NSR é imutável — inclusive na retificação
-- ---------------------------------------------------------------------
-- A retificação oficial pode corrigir a hora (com justificativa), mas o
-- número do registro é o que amarra a marcação ao arquivo-fonte: mudá-lo
-- desfaz a prova. Por isso a trava vem ANTES da liberação da retificação.
-- Atribuir NSR a marcação que ainda não tinha (nulo -> número) continua
-- permitido: é o preenchimento histórico.
CREATE OR REPLACE FUNCTION public.ponto_bloquear_update_marcacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_reordena boolean := coalesce(current_setting('app.ponto_reordena', true), 'off') = 'on';
BEGIN
  IF OLD.nsr IS NOT NULL AND NEW.nsr IS DISTINCT FROM OLD.nsr THEN
    RAISE EXCEPTION 'NSR da marcacao e imutavel (Portaria MTP 671/2021): e o numero que amarra o registro ao arquivo-fonte.'
      USING ERRCODE = '42501';
  END IF;

  -- Retificação oficial (com justificativa registrada): passa direto.
  IF coalesce(current_setting('app.ponto_retificacao', true), 'off') = 'on' THEN
    RETURN NEW;
  END IF;

  -- Reordenação automática de rótulos: libera SOMENTE tipo_marcacao.
  IF v_reordena
     AND NEW.hora_marcacao       IS NOT DISTINCT FROM OLD.hora_marcacao
     AND NEW.data_marcacao       IS NOT DISTINCT FROM OLD.data_marcacao
     AND NEW.colaborador_cpf     IS NOT DISTINCT FROM OLD.colaborador_cpf
     AND NEW.colaborador_id      IS NOT DISTINCT FROM OLD.colaborador_id
     AND NEW.marcacao_original   IS NOT DISTINCT FROM OLD.marcacao_original
  THEN
    RETURN NEW;
  END IF;

  IF NEW.hora_marcacao IS DISTINCT FROM OLD.hora_marcacao
     OR NEW.data_marcacao IS DISTINCT FROM OLD.data_marcacao
     OR NEW.tipo_marcacao IS DISTINCT FROM OLD.tipo_marcacao
     OR NEW.colaborador_cpf IS DISTINCT FROM OLD.colaborador_cpf
     OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id
     OR NEW.marcacao_original IS DISTINCT FROM OLD.marcacao_original
  THEN
    RAISE EXCEPTION 'Marcação original é imutável (Portaria MTP 671/2021). Use a retificação com justificativa.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================================
-- PONTO-395 — Histórico de lotação por estabelecimento
-- =====================================================================
-- Hoje a empresa do colaborador é atributo solto em cada linha, sem
-- vigência. Numa transferência real, nada garante origem encerrada e
-- destino iniciado na data certa — e o AFD de cada estabelecimento sai
-- misturado.

CREATE TABLE IF NOT EXISTS public.ponto_lotacao_historico (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                   uuid NOT NULL,
  colaborador_cpf             text NOT NULL,
  colaborador_id              uuid,
  colaborador_nome            text,
  empresa_id                  uuid NOT NULL,
  data_inicio                 date NOT NULL,
  data_fim                    date,
  motivo                      text NOT NULL DEFAULT 'admissao',
  transferencia_de_empresa_id uuid,
  observacao                  text,
  created_by                  uuid,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ponto_lotacao_periodo_valido CHECK (data_fim IS NULL OR data_fim >= data_inicio),
  CONSTRAINT ponto_lotacao_motivo_chk CHECK (motivo IN ('admissao', 'transferencia', 'ajuste'))
);

COMMENT ON TABLE public.ponto_lotacao_historico IS
  'Onde cada colaborador estava lotado em cada periodo. Consultado pela apuracao e pelos arquivos legais para que o AFD de cada estabelecimento saia sem mistura.';
COMMENT ON COLUMN public.ponto_lotacao_historico.transferencia_de_empresa_id IS
  'Estabelecimento de origem, preenchido quando o periodo nasce de uma transferencia. Nulo na lotacao inicial.';

CREATE INDEX IF NOT EXISTS ponto_lotacao_historico_busca
  ON public.ponto_lotacao_historico (tenant_id, colaborador_cpf, data_inicio DESC);

-- Períodos do mesmo CPF não se sobrepõem: uma pessoa está lotada num
-- estabelecimento por vez. Sem isso, "onde ele estava no dia 10" tem duas
-- respostas e o arquivo sai duplicado.
CREATE OR REPLACE FUNCTION public.ponto_lotacao_sem_sobreposicao()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_conflito record;
BEGIN
  NEW.colaborador_cpf := regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g');
  NEW.updated_at := now();

  SELECT l.data_inicio, l.data_fim INTO v_conflito
  FROM public.ponto_lotacao_historico l
  WHERE l.tenant_id = NEW.tenant_id
    AND l.colaborador_cpf = NEW.colaborador_cpf
    AND l.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND daterange(l.data_inicio, l.data_fim, '[]')
        && daterange(NEW.data_inicio, NEW.data_fim, '[]')
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION
      'Lotacao sobreposta para o CPF %: ja existe periodo de % a %. Encerre o periodo anterior antes de abrir o novo.',
      NEW.colaborador_cpf, v_conflito.data_inicio, COALESCE(v_conflito.data_fim::text, 'aberto');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ponto_lotacao_sem_sobreposicao ON public.ponto_lotacao_historico;
CREATE TRIGGER trg_ponto_lotacao_sem_sobreposicao
BEFORE INSERT OR UPDATE ON public.ponto_lotacao_historico
FOR EACH ROW
EXECUTE FUNCTION public.ponto_lotacao_sem_sobreposicao();

-- Onde a pessoa estava lotada numa data. É esta função que a apuração e
-- os arquivos passam a consultar nas ondas seguintes.
CREATE OR REPLACE FUNCTION public.ponto_lotacao_do_dia(
  p_tenant_id uuid, p_cpf text, p_data date
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.empresa_id
  FROM public.ponto_lotacao_historico l
  WHERE l.tenant_id = p_tenant_id
    AND l.colaborador_cpf = regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g')
    AND l.data_inicio <= p_data
    AND (l.data_fim IS NULL OR l.data_fim >= p_data)
  ORDER BY l.data_inicio DESC
  LIMIT 1;
$$;

-- Registra uma transferência: encerra o período vigente na véspera e abre
-- o novo, guardando de onde veio.
CREATE OR REPLACE FUNCTION public.ponto_transferir_lotacao(
  p_tenant_id uuid, p_cpf text, p_empresa_destino uuid,
  p_data_inicio date, p_observacao text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf text := regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g');
  v_origem uuid;
  v_nome text;
  v_colab uuid;
  v_novo uuid;
BEGIN
  IF p_empresa_destino IS NULL OR p_data_inicio IS NULL THEN
    RAISE EXCEPTION 'Transferencia exige estabelecimento de destino e data de inicio.';
  END IF;

  SELECT l.empresa_id, l.colaborador_nome, l.colaborador_id
    INTO v_origem, v_nome, v_colab
  FROM public.ponto_lotacao_historico l
  WHERE l.tenant_id = p_tenant_id
    AND l.colaborador_cpf = v_cpf
    AND l.data_inicio < p_data_inicio
    AND (l.data_fim IS NULL OR l.data_fim >= p_data_inicio)
  ORDER BY l.data_inicio DESC
  LIMIT 1;

  IF v_origem IS NOT NULL THEN
    UPDATE public.ponto_lotacao_historico
       SET data_fim = p_data_inicio - 1
     WHERE tenant_id = p_tenant_id
       AND colaborador_cpf = v_cpf
       AND data_inicio < p_data_inicio
       AND (data_fim IS NULL OR data_fim >= p_data_inicio);
  END IF;

  INSERT INTO public.ponto_lotacao_historico
    (tenant_id, colaborador_cpf, colaborador_id, colaborador_nome, empresa_id,
     data_inicio, motivo, transferencia_de_empresa_id, observacao, created_by)
  VALUES (p_tenant_id, v_cpf, v_colab, v_nome, p_empresa_destino,
          p_data_inicio,
          CASE WHEN v_origem IS NULL THEN 'admissao' ELSE 'transferencia' END,
          v_origem, p_observacao, auth.uid())
  RETURNING id INTO v_novo;

  RETURN v_novo;
END;
$$;

ALTER TABLE public.ponto_lotacao_historico ENABLE ROW LEVEL SECURITY;

DO $pol_lot$
BEGIN
  DROP POLICY IF EXISTS "Tenant gerencia ponto_lotacao_historico" ON public.ponto_lotacao_historico;
  CREATE POLICY "Tenant gerencia ponto_lotacao_historico"
    ON public.ponto_lotacao_historico FOR ALL
    USING (tenant_id = public.current_user_tenant_id())
    WITH CHECK (tenant_id = public.current_user_tenant_id());
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Politica de ponto_lotacao_historico nao aplicada: %', SQLERRM;
END $pol_lot$;

-- Semeia a lotação inicial a partir das admissões concluídas que já têm
-- estabelecimento. Em banco novo não encontra nada e segue; em produção
-- roda igual. Só cria o que falta — rodar duas vezes não duplica.
DO $prodseed$
BEGIN
  INSERT INTO public.ponto_lotacao_historico
    (tenant_id, colaborador_cpf, colaborador_nome, empresa_id, data_inicio, motivo, observacao)
  SELECT a.tenant_id,
         regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g'),
         a.nome_completo,
         a.empresa_id,
         COALESCE(a.data_admissao, CURRENT_DATE),
         'admissao',
         'Lotacao inicial semeada a partir da admissao'
  FROM public.admissoes a
  WHERE a.empresa_id IS NOT NULL
    AND a.tenant_id IS NOT NULL
    AND COALESCE(a.cpf, '') <> ''
    AND a.status::text = 'concluido'
    AND NOT EXISTS (
      SELECT 1 FROM public.ponto_lotacao_historico l
      WHERE l.tenant_id = a.tenant_id
        AND l.colaborador_cpf = regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
    );
  RAISE NOTICE 'Lotacao inicial semeada.';
EXCEPTION WHEN foreign_key_violation OR not_null_violation OR raise_exception THEN
  RAISE NOTICE 'Semeadura da lotacao inicial pulada: %', SQLERRM;
END $prodseed$;

-- Tabela nova de ponto precisa da trava do cercado (PONTO-270 vigia isso).
DO $cercas$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'qa_instalar_cercas';
  IF NOT FOUND THEN
    RAISE NOTICE 'Motor de QA nao instalado: cercas ignoradas.';
    RETURN;
  END IF;
  PERFORM * FROM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas reinstaladas (tabelas novas incluidas).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel instalar as cercas: %', SQLERRM;
END $cercas$;

-- =====================================================================
-- RÉGUA: as duas rotinas passam a testar COMPORTAMENTO
-- =====================================================================
-- Como estavam, PONTO-210 e PONTO-395 só perguntavam se existia coluna
-- com certo nome. Passariam com uma coluna vazia e um nome bem escolhido.
-- Agora exercitam o que a estrutura promete.

DO $qa210$
BEGIN
  IF to_regclass('public.qa_retorno') IS NULL THEN
    RAISE NOTICE 'Motor de QA nao instalado: qa_caso_ponto_210 ignorado.';
    RETURN;
  END IF;

  EXECUTE $body210$
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_210()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_cpf text; v_t uuid := public.qa_sandbox_tenant_id();
  v_n1 bigint; v_n2 bigint;
  v_mudou boolean := false;
  v_unico boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar duas marcacoes e conferir se o NSR nasce sozinho e continua a serie';
  r.esperado := 'NSR atribuido na gravacao, sequencial, sem buraco';

  v_cpf := public.qa_ponto_admissao('QA NSR', 2101);
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '08:00', 'entrada');
  PERFORM public.qa_ponto_marca(v_cpf, 'QA NSR', CURRENT_DATE - 2, TIME '12:00', 'saida');

  SELECT min(nsr), max(nsr) INTO v_n1, v_n2
  FROM public.ponto_marcacoes
  WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;

  r.passo_ordem := 2;
  r.passo_acao := 'Tentar ALTERAR o NSR de uma marcacao ja gravada';
  r.esperado := 'Recusado — o numero amarra o registro ao arquivo-fonte';
  BEGIN
    UPDATE public.ponto_marcacoes SET nsr = nsr + 1000
    WHERE tenant_id = v_t AND colaborador_cpf = v_cpf;
    v_mudou := true;
  EXCEPTION WHEN OTHERS THEN v_mudou := false; END;

  r.passo_ordem := 3;
  r.passo_acao := 'Conferir que o NSR nao se repete dentro do estabelecimento';
  r.esperado := 'Indice unico por (tenant, empresa, nsr)';
  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'ponto_marcacoes'
      AND indexname = 'ponto_marcacoes_nsr_unico'
  ) INTO v_unico;

  IF v_n1 IS NOT NULL AND v_n2 = v_n1 + 1 AND NOT v_mudou AND v_unico THEN
    r.situacao := 'passou';
    r.obtido := format('NSR atribuido na gravacao (%s e %s, sem buraco), imutavel depois de '
             || 'gravado e unico por estabelecimento. Marcacoes anteriores a esta '
             || 'funcionalidade ficam sem NSR ate rodar o preenchimento historico.', v_n1, v_n2);
  ELSIF v_n1 IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a marcacao foi gravada SEM NSR. Sem numeracao sequencial de registro, '
             || 'o AFD improvisa numeros na exportacao e nada demonstra que nenhum registro foi '
             || 'removido. E o requisito central do arquivo-fonte da Portaria 671.';
  ELSIF v_n2 <> v_n1 + 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a serie do NSR tem buraco (%s depois de %s). Buraco na sequencia '
             || 'e exatamente o que a fiscalizacao le como registro removido.', v_n2, v_n1);
  ELSIF v_mudou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o NSR de uma marcacao ja gravada pode ser ALTERADO. Numero que muda nao '
             || 'amarra nada — o vinculo entre a marcacao e o arquivo-fonte deixa de provar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: falta o indice que impede NSR repetido dentro do estabelecimento.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
  $body210$;

  RAISE NOTICE 'qa_caso_ponto_210 passou a testar comportamento.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel atualizar qa_caso_ponto_210: %', SQLERRM;
END $qa210$;

DO $qa395$
BEGIN
  IF to_regclass('public.qa_retorno') IS NULL THEN
    RAISE NOTICE 'Motor de QA nao instalado: qa_caso_ponto_395 ignorado.';
    RETURN;
  END IF;

  EXECUTE $body395$
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_395()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_cpf text := public.qa_cpf(3951);
  v_ea uuid; v_eb uuid;
  v_corte date := CURRENT_DATE - 30;
  v_antes uuid; v_depois uuid;
  v_sobrepos boolean := false;
  v_encerrou boolean := false;
BEGIN
  IF to_regclass('public.ponto_lotacao_historico') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe historico de lotacao — a empresa do colaborador e um '
             || 'atributo solto em cada linha, sem vigencia nem data de corte. Numa '
             || 'transferencia real o AFD de cada estabelecimento sai misturado.';
    RETURN r;
  END IF;

  v_ea := public.qa_nova_empresa('QA Lotacao Origem ' || v_cpf, '11.222.333/0001-81', true);
  v_eb := public.qa_nova_empresa('QA Lotacao Destino ' || v_cpf, '11.444.777/0001-61', true);

  r.passo_ordem := 1;
  r.passo_acao := 'Transferir o colaborador e conferir se a origem foi encerrada na vespera';
  r.esperado := 'Periodo de origem fechado no dia anterior; destino aberto na data do corte';

  INSERT INTO public.ponto_lotacao_historico
    (tenant_id, colaborador_cpf, colaborador_nome, empresa_id, data_inicio, motivo)
  VALUES (v_t, v_cpf, 'QA Lotacao', v_ea, CURRENT_DATE - 120, 'admissao');

  PERFORM public.ponto_transferir_lotacao(v_t, v_cpf, v_eb, v_corte, 'QA: transferencia');

  SELECT EXISTS (
    SELECT 1 FROM public.ponto_lotacao_historico
    WHERE tenant_id = v_t AND colaborador_cpf = v_cpf
      AND empresa_id = v_ea AND data_fim = v_corte - 1
  ) INTO v_encerrou;

  r.passo_ordem := 2;
  r.passo_acao := 'Perguntar onde o colaborador estava antes e depois do corte';
  r.esperado := 'Antes do corte responde a origem; depois responde o destino';
  v_antes  := public.ponto_lotacao_do_dia(v_t, v_cpf, v_corte - 10);
  v_depois := public.ponto_lotacao_do_dia(v_t, v_cpf, v_corte + 10);

  r.passo_ordem := 3;
  r.passo_acao := 'Tentar abrir um periodo que se sobrepoe a outro';
  r.esperado := 'Recusado — uma pessoa esta lotada num estabelecimento por vez';
  BEGIN
    INSERT INTO public.ponto_lotacao_historico
      (tenant_id, colaborador_cpf, colaborador_nome, empresa_id, data_inicio, data_fim, motivo)
    VALUES (v_t, v_cpf, 'QA Lotacao', v_ea, v_corte + 1, v_corte + 5, 'ajuste');
    v_sobrepos := true;
  EXCEPTION WHEN OTHERS THEN v_sobrepos := false; END;

  IF v_encerrou AND v_antes = v_ea AND v_depois = v_eb AND NOT v_sobrepos THEN
    r.situacao := 'passou';
    r.obtido := 'Transferencia encerrou a origem na vespera e abriu o destino na data do corte. '
             || 'A consulta por data responde o estabelecimento certo de cada lado, e periodo '
             || 'sobreposto foi recusado — o AFD de cada estabelecimento sai sem mistura.';
  ELSIF NOT v_encerrou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a transferencia nao encerrou o periodo de origem na vespera. Sem data '
             || 'de corte, os dois estabelecimentos reivindicam o mesmo dia.';
  ELSIF v_antes IS DISTINCT FROM v_ea OR v_depois IS DISTINCT FROM v_eb THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a consulta de lotacao por data devolveu o estabelecimento errado — '
             || 'a apuracao e os arquivos leriam a lotacao trocada.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco ACEITOU periodos de lotacao sobrepostos. "Onde ele estava no '
             || 'dia 10" passa a ter duas respostas e o arquivo sai duplicado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
  $body395$;

  RAISE NOTICE 'qa_caso_ponto_395 passou a testar comportamento.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel atualizar qa_caso_ponto_395: %', SQLERRM;
END $qa395$;

-- =====================================================================
-- RÉGUA: dois casos que passariam de graça com a chegada do NSR
-- =====================================================================
-- PONTO-380 e PONTO-383 reprovavam apenas quando NENHUMA das condições
-- existia ("se não tem tabela E não tem NSR"). Bastou o NSR aparecer para
-- os dois virarem "passou" — com a própria evidência mostrando que a peça
-- principal continua faltando ("tabela: f", "unicidade: —").
--
-- Passam a exigir as duas condições. Sem isto, esta onda pareceria fechar
-- dois casos em que não encostou, que é o pior tipo de erro num placar.

DO $qa380$
BEGIN
  IF to_regclass('public.qa_retorno') IS NULL THEN RETURN; END IF;
  EXECUTE $body380$
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_380()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_tab boolean; v_nsr text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o comprovante existe como documento com conteudo minimo?';
  r.esperado := 'Comprovante com empregador, trabalhador, data/hora e NSR, vinculado a marcacao';

  v_tab := to_regclass('public.ponto_comprovantes') IS NOT NULL;
  v_nsr := public.qa_col_existe('ponto_marcacoes', '%nsr%');

  IF v_tab AND v_nsr IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Comprovante existe como documento (ponto_comprovantes) e a marcacao '
             || 'carrega o NSR que o identifica (%s).', v_nsr);
  ELSIF NOT v_tab AND v_nsr IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o comprovante hoje e so um boolean (ponto_marcacoes.comprovante_gerado) '
             || '— nao existe o documento em si, e a marcacao tambem nao tem NSR. O comprovante '
             || 'e o recibo legal do trabalhador na Portaria 671.';
  ELSIF NOT v_tab THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO PARCIAL: o NSR ja existe na marcacao, mas o comprovante continua sendo '
             || 'apenas um boolean — nao existe a tabela do documento com identificacao do '
             || 'empregador, do trabalhador, data/hora e NSR. Metade do requisito nao e o '
             || 'requisito: sem o artefato, nao ha o que entregar ao trabalhador.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO PARCIAL: a tabela de comprovantes existe, mas a marcacao nao carrega NSR '
             || '— o comprovante nao consegue identificar a qual registro se refere.';
  END IF;
  r.detalhe := jsonb_build_object('tabela_comprovantes', v_tab, 'coluna_nsr', v_nsr);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
  $body380$;
  RAISE NOTICE 'qa_caso_ponto_380 corrigido (exigia uma condicao, agora exige as duas).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel corrigir qa_caso_ponto_380: %', SQLERRM;
END $qa380$;

DO $qa383$
BEGIN
  IF to_regclass('public.qa_retorno') IS NULL THEN RETURN; END IF;
  EXECUTE $body383$
CREATE OR REPLACE FUNCTION public.qa_caso_ponto_383()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_unq text; v_nsr_origem text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): reimportar o mesmo AFD duplicaria marcacoes?';
  r.esperado := 'Unicidade do arquivo importado E chave natural do registro de origem (equipamento + NSR do AFD)';

  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint
  WHERE conrelid = 'public.ponto_repc_importacoes'::regclass AND contype = 'u';

  -- O NSR proprio (ponto_marcacoes.nsr) e gerado pelo YourEyes na gravacao:
  -- nao serve para deduplicar arquivo de terceiro. A chave natural do AFD
  -- importado e o NSR DE ORIGEM somado ao equipamento que o emitiu.
  v_nsr_origem := coalesce(public.qa_col_existe('ponto_marcacoes', '%nsr_origem%'),
                           public.qa_col_existe('ponto_marcacoes', '%nsr_afd%'),
                           public.qa_col_existe('ponto_marcacoes', '%equipamento%'));

  IF v_unq IS NOT NULL AND v_nsr_origem IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Reprocessamento idempotente: unicidade do arquivo (%s) e chave natural do '
             || 'registro de origem (%s).', v_unq, v_nsr_origem);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: nao ha trava de reimportacao. Unicidade do arquivo em '
             || 'ponto_repc_importacoes: %s. Chave do registro de origem na marcacao: %s. '
             || 'Atencao: o NSR proprio da marcacao, criado nesta onda, e gerado pelo YourEyes na '
             || 'gravacao e NAO serve para deduplicar AFD de terceiro — para isso e preciso '
             || 'guardar o NSR que veio no arquivo e o equipamento que o emitiu. Repetir um upload '
             || 'apos falha no meio duplica batidas e suja a apuracao.',
             coalesce(v_unq, 'nenhuma'), coalesce(v_nsr_origem, 'nenhuma'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
  $body383$;
  RAISE NOTICE 'qa_caso_ponto_383 corrigido (exigia uma condicao, agora exige as duas).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel corrigir qa_caso_ponto_383: %', SQLERRM;
END $qa383$;

-- ============================================================================
-- CONFERÊNCIA — o SQL Editor mostra apenas o último resultado.
-- Esperado: t | t | t | t | t | t | OK
-- "marcacoes_sem_nsr" dimensiona o preenchimento histórico que vem depois.
-- ============================================================================
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='nsr') = 1
                                                                    AS coluna_nsr,

  (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
    AND tgname='trg_ponto_atribuir_nsr') = 1                        AS gatilho_atribui_nsr,

  (SELECT count(*) FROM pg_indexes
    WHERE schemaname='public' AND indexname='ponto_marcacoes_nsr_unico') = 1
                                                                    AS nsr_nao_repete,

  to_regclass('public.ponto_lotacao_historico') IS NOT NULL          AS tabela_lotacao,

  (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
    AND tgname='trg_ponto_lotacao_sem_sobreposicao') = 1             AS lotacao_sem_sobreposicao,

  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('ponto_lotacao_do_dia','ponto_transferir_lotacao')) = 2
                                                                    AS funcoes_de_lotacao,

  (SELECT count(*) FROM public.ponto_marcacoes
    WHERE nsr IS NULL AND tenant_id IS NOT NULL)                    AS marcacoes_sem_nsr,

  (SELECT count(*) FROM public.ponto_lotacao_historico)             AS periodos_de_lotacao,

  CASE
    WHEN (SELECT count(*) FROM information_schema.columns
           WHERE table_schema='public' AND table_name='ponto_marcacoes' AND column_name='nsr') = 0
      THEN 'ERRO: a coluna do NSR nao foi criada'
    WHEN (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgname='trg_ponto_atribuir_nsr') = 0
      THEN 'ERRO: o gatilho que atribui o NSR nao foi criado — marcacao nova nasceria sem numero'
    WHEN to_regclass('public.ponto_lotacao_historico') IS NULL
      THEN 'ERRO: a tabela de lotacao nao foi criada'
    ELSE 'OK'
  END                                                               AS erro_tecnico;


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
            WHERE parte = 3 AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = 3 AND tabela = v.tabela;
  END LOOP;
END $volume2$;

-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_proximo_nsr', NULL),
    ('funcao', 'ponto_atribuir_nsr', NULL),
    ('funcao', 'ponto_bloquear_update_marcacao', NULL),
    ('funcao', 'ponto_lotacao_sem_sobreposicao', NULL),
    ('funcao', 'ponto_lotacao_do_dia', NULL),
    ('funcao', 'ponto_transferir_lotacao', 'Transferencia exige estabelecimento de destino e data de inicio.'),
    ('funcao', 'qa_caso_ponto_210', 'NSR atribuido na gravacao, sequencial, sem buraco'),
    ('funcao', 'qa_caso_ponto_395', 'atributo solto em cada linha, sem vigencia nem data de corte. Numa '),
    ('funcao', 'qa_caso_ponto_380', 'Comprovante existe como documento (ponto_comprovantes) e a marcacao '),
    ('funcao', 'qa_caso_ponto_383', 'ACHADO: nao ha trava de reimportacao. Unicidade do arquivo em '),
    ('tabela', 'ponto_nsr_controle', NULL),
    ('tabela', 'ponto_lotacao_historico', NULL),
    ('gatilho', 'trg_ponto_atribuir_nsr', NULL),
    ('gatilho', 'trg_ponto_lotacao_sem_sobreposicao', NULL),
    ('indice', 'ponto_marcacoes_nsr_unico', NULL),
    ('indice', 'ponto_lotacao_historico_busca', NULL),
    ('coluna', 'ponto_marcacoes.nsr', NULL)
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
  WHERE v.parte = 3
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
