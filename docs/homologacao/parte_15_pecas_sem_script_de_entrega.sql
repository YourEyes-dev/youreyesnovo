-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE 15 de 16: Pecas que so existiam em migration
--
-- A bateria na homologacao mostrou que estas pecas nunca tiveram script de
-- entrega — existem no projeto desde sempre e nunca chegaram a producao: um
-- dia por data na apuracao, o adicional de feriado da RN23 com a folga
-- compensatoria, o motor agendado de vigilancias, a trava de imutabilidade
-- da marcacao e o prazo obrigatorio do link de marcacao.
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
--   * script_um_dia_por_data.sql
--   * script_ponto_rn23_feriado_adicional.sql
--   * script_ponto_vigilancias_diarias.sql
--   * script_ponto004_imutabilidade.sql
--   * script_ponto_links_prazo_obrigatorio.sql
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================



-- ############################################################
-- BLOCO: script_um_dia_por_data.sql
-- ############################################################

-- =====================================================================
-- Sábado aparecendo duas vezes na lista do Banco de Horas
--
-- Relato (Luiza e Adriana, 27/06): o mesmo sábado sai duas vezes —
-- uma com as marcações reais (07:50–12:00, 4h10, +4h10) e outra zerada
-- com o rótulo Equalização (0h00, −3h40).
--
-- Não é o dado: a varredura de ponto_diario não achou nenhuma data
-- repetida. Quem cria a segunda linha é a leitura.
--
-- ponto_saldo_dias_competencia percorre os dias e, no fim, ACRESCENTA
-- uma linha de equalização quando entende que o dia da equalização não
-- apareceu no laço. Quando essa linha cai num dia que já saiu, o dia
-- duplica — e o saldo do mês é debitado duas vezes, o que é pior que o
-- efeito visual: no caso da Adriana são 3h40 de débito que não existem.
--
-- Por que não corrigimos o ramo que emite a linha extra: a definição em
-- produção foi corrigida por remendo ao longo do tempo e não corresponde
-- a nenhum arquivo do repositório. Mexer no ramo errado quebraria o que
-- está certo sem resolver o que está errado.
--
-- A correção aqui é de outra ordem, e vale para qualquer ramo: a função
-- passa a garantir UM DIA POR DATA na saída. O corpo antigo continua
-- intacto, renomeado, e um invólucro agrupa o que ele devolve.
--
-- Dia que sai uma vez só — o caso normal — passa sem ser tocado: os
-- valores são exatamente os de antes. Só quando a mesma data aparece
-- duas vezes é que há junção, e ela segue o que a regra manda:
--   · dia protegido (atestado, férias, feriado) vence: saldo zero;
--   · senão, vale o que foi TRABALHADO na linha real e a MAIOR jornada
--     exigida entre as duas — no caso do sábado, a da equalização;
--   · o saldo é recalculado dessas duas, com a tolerância de 10 minutos
--     que a apuração já aplica.
-- =====================================================================

DO $renomeia$
BEGIN
  -- Guarda contra o cenario em que o involucro ja existe mas o corpo bruto
  -- sumiu (uma restauracao parcial, por exemplo): renomear o involucro faria
  -- dele o proprio "bruto" que ele chama, e a apuracao entraria em recursao
  -- infinita ("stack depth limit exceeded") na primeira competencia apurada.
  IF to_regprocedure('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)') IS NULL
     AND EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ponto_saldo_dias_competencia'
         AND position('ponto_saldo_dias_competencia_bruto' in p.prosrc) > 0
     ) THEN
    RAISE NOTICE 'ATENCAO: ponto_saldo_dias_competencia ja e o involucro, mas o corpo bruto nao existe nesta base. Nada foi renomeado (renomear criaria recursao infinita). Restaure ponto_saldo_dias_competencia_bruto antes de rodar este script.';
    RETURN;
  END IF;

  IF to_regprocedure('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)') IS NULL THEN
    ALTER FUNCTION public.ponto_saldo_dias_competencia(uuid, text, text)
      RENAME TO ponto_saldo_dias_competencia_bruto;
    RAISE NOTICE 'Corpo da apuração preservado como ponto_saldo_dias_competencia_bruto.';
  ELSE
    RAISE NOTICE 'ponto_saldo_dias_competencia_bruto já existe — nada a renomear.';
  END IF;
END $renomeia$;

COMMENT ON FUNCTION public.ponto_saldo_dias_competencia_bruto(uuid, text, text) IS
  'Apuração dia a dia, sem garantia de uma linha por data. Não chame direto: use ponto_saldo_dias_competencia.';

CREATE OR REPLACE FUNCTION public.ponto_saldo_dias_competencia(
  p_tenant_id uuid,
  p_colaborador_cpf text,
  p_competencia text
)
RETURNS TABLE(
  dia date,
  entrada time without time zone,
  saida time without time zone,
  trabalhado_min integer,
  jornada_min integer,
  saldo_min integer,
  protegido boolean,
  equalizacao boolean,
  excedente_retido_min integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bruto AS (
    SELECT * FROM public.ponto_saldo_dias_competencia_bruto(
      p_tenant_id, p_colaborador_cpf, p_competencia)
  ),
  agrupado AS (
    SELECT b.dia,
           count(*)                                      AS linhas,
           -- Entrada mais cedo e saída mais tarde entre as linhas do dia:
           -- a linha extra vem sem marcação, então na prática ficam as
           -- marcações reais.
           min(b.entrada)                                AS entrada,
           max(b.saida)                                  AS saida,
           max(b.trabalhado_min)                         AS trabalhado_min,
           max(b.jornada_min)                            AS jornada_min,
           max(b.saldo_min)                              AS saldo_unico,
           bool_or(b.protegido)                          AS protegido,
           bool_or(b.equalizacao)                        AS equalizacao,
           max(b.excedente_retido_min)                   AS excedente_retido_min
    FROM bruto b
    GROUP BY b.dia
  )
  SELECT a.dia,
         a.entrada,
         a.saida,
         a.trabalhado_min,
         -- Dia protegido não tem jornada a cobrar.
         CASE WHEN a.protegido AND a.linhas > 1 THEN 0 ELSE a.jornada_min END,
         CASE
           -- Dia que saiu uma vez só: nada muda, nem por arredondamento.
           WHEN a.linhas = 1 THEN a.saldo_unico
           -- Dia protegido não gera débito nem crédito.
           WHEN a.protegido THEN 0
           -- Tolerância de 10 minutos, a mesma da apuração.
           WHEN abs(a.trabalhado_min - a.jornada_min) <= 10 THEN 0
           ELSE a.trabalhado_min - a.jornada_min
         END,
         a.protegido,
         a.equalizacao,
         a.excedente_retido_min
  FROM agrupado a
  ORDER BY a.dia;
$$;

REVOKE EXECUTE ON FUNCTION public.ponto_saldo_dias_competencia(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_saldo_dias_competencia(uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.ponto_saldo_dias_competencia(uuid, text, text) IS
  'Apuração dia a dia da competência, garantindo uma linha por data. Junta linhas repetidas (o dia da equalização emitido em duplicidade) em vez de deixar o dia sair duas vezes e o saldo ser contado duas vezes.';


-- FERRAMENTA DE CONFERÊNCIA -------------------------------------------
-- Quem ainda teria dia repetido se a junção não existisse. Serve para
-- medir o tamanho do problema e, depois, para achar a causa com calma.
CREATE OR REPLACE FUNCTION public.ponto_dias_repetidos_na_apuracao(
  p_tenant_id uuid,
  p_competencia text
)
RETURNS TABLE(
  colaborador_cpf text,
  colaborador_nome text,
  dia date,
  linhas integer,
  saldo_somado_min integer,
  saldo_apos_juncao_min integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ini date := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim date := (to_date(p_competencia || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date;
  r RECORD;
BEGIN
  FOR r IN
    SELECT regexp_replace(pd.colaborador_cpf, '[^0-9]', '', 'g') AS cpf,
           max(pd.colaborador_nome) AS nome
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.data BETWEEN v_ini AND v_fim
      AND COALESCE(pd.colaborador_cpf, '') <> ''
    GROUP BY 1
  LOOP
    RETURN QUERY
    SELECT r.cpf, r.nome, b.dia, count(*)::int,
           sum(b.saldo_min)::int,
           (SELECT s.saldo_min
              FROM public.ponto_saldo_dias_competencia(p_tenant_id, r.cpf, p_competencia) s
             WHERE s.dia = b.dia)
    FROM public.ponto_saldo_dias_competencia_bruto(p_tenant_id, r.cpf, p_competencia) b
    GROUP BY b.dia
    HAVING count(*) > 1;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.ponto_dias_repetidos_na_apuracao(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ponto_dias_repetidos_na_apuracao(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.ponto_dias_repetidos_na_apuracao(uuid, text) IS
  'Dias que a apuração devolveria mais de uma vez, com o saldo antes e depois da junção. Mede quanto de débito indevido a duplicidade estava criando.';


-- =====================================================================
-- CONFERÊNCIA — rode junto
-- =====================================================================

-- 1) A correção está no lugar?
SELECT to_regprocedure('public.ponto_saldo_dias_competencia_bruto(uuid,text,text)') IS NOT NULL
         AS corpo_preservado,
       position('ponto_saldo_dias_competencia_bruto' in
         COALESCE(pg_get_functiondef(to_regprocedure(
           'public.ponto_saldo_dias_competencia(uuid,text,text)')), '')) > 0
         AS juncao_ativa;

-- 2) Quantos dias estavam saindo repetidos, e quanto de débito indevido
--    isso criava. Troque a competência se quiser olhar outro mês.
SELECT * FROM public.ponto_dias_repetidos_na_apuracao(
  (SELECT tenant_id FROM public.ponto_diario
    WHERE colaborador_nome ILIKE '%luiza%' LIMIT 1),
  '2026-06');

-- 3) O caso da Luiza no fim de junho, já corrigido: uma linha por dia.
SELECT s.*
FROM (SELECT tenant_id, regexp_replace(colaborador_cpf, '[^0-9]', '', 'g') AS cpf
        FROM public.ponto_diario WHERE colaborador_nome ILIKE '%luiza%' LIMIT 1) p,
     LATERAL public.ponto_saldo_dias_competencia(p.tenant_id, p.cpf, '2026-06') s
WHERE s.dia BETWEEN '2026-06-20' AND '2026-06-30'
ORDER BY s.dia;



-- ############################################################
-- BLOCO: script_ponto_rn23_feriado_adicional.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — RN23: feriado trabalhado com adicional de 100% (PONTO-131/320/321/322)
--
-- ACHADO DA BANCADA (bateria do Ponto na homologacao, 27/08/2026): quatro casos
-- reprovaram com a mesma causa —
--     function public.ponto_feriado_adicional_competencia(uuid, uuid, text)
--     does not exist
--
-- A RN23 (Lei 605/1949 art. 9; Sumula 146 do TST) nasceu em DUAS migrations e
-- NENHUM script de entrega. Migration so alcanca o ambiente de teste — entao o
-- adicional de feriado nunca existiu na producao. Na pratica: feriado
-- trabalhado sem folga compensatoria vem sendo tratado como jornada comum, sem
-- a dobra, EM SILENCIO. Nenhum erro aparece: a apuracao apenas nao encontra a
-- funcao e o dia segue como dia normal.
--
-- POR QUE ESTE PACOTE NAO E A COPIA DAS MIGRATIONS
-- A primeira montagem deste script concatenava as duas migrations de origem na
-- ordem cronologica. A conferencia em replica reprovou: a migration de 13/08
-- carrega uma versao de ponto_feriados_trabalhados ANTERIOR a que a Onda 5
-- (escala 12x36) instalou depois — copiar as migrations teria REGREDIDO o
-- 12x36 que ja esta na producao/homologacao (o caso PONTO-151 caiu na prova).
-- Por isso as funcoes aqui sao o estado ATUAL do projeto, com todas as
-- correcoes posteriores embutidas, e nao o texto das migrations.
--
-- O QUE ENTRA
--   1. feriado_folga_compensatoria — onde o RH registra que um feriado
--      trabalhado foi compensado com folga em outro dia (o que afasta a dobra).
--   2. feriado_excecao + ponto_escalas.comportamento_feriado — como cada
--      escala trata feriado.
--   3. A cadeia de apuracao completa, incluindo os auxiliares de resolucao de
--      empresa de que ela depende.
--
-- NAO altera saldo de banco de horas: o adicional de feriado e verba de folha,
-- nao credito de compensacao — soma-lo ao saldo pagaria duas vezes.
-- Idempotente; roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) AS DUAS TABELAS DA RN23 — DDL extraido do proprio projeto, nao redigido
--     a mao. (A primeira montagem deste pacote inventou as colunas de
--     feriado_excecao e a cadeia quebrou com "column colaborador_id does not
--     exist" na prova em replica.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.feriado_excecao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    colaborador_id uuid NOT NULL,
    data date,
    comportamento text NOT NULL,
    observacao text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

COMMENT ON TABLE public.feriado_excecao IS 'Exceções de comportamento no feriado, por colaborador. Com data: vale só para aquele feriado. Sem data: regra geral do colaborador. Tem precedência sobre a escala.';

CREATE TABLE IF NOT EXISTS public.feriado_folga_compensatoria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid DEFAULT public.current_user_tenant_id() NOT NULL,
    colaborador_id uuid NOT NULL,
    colaborador_cpf text NOT NULL,
    data_feriado date NOT NULL,
    data_folga date NOT NULL,
    observacao text,
    registrado_por uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_folga_compensatoria_ordem CHECK ((data_folga <> data_feriado))
);

COMMENT ON TABLE public.feriado_folga_compensatoria IS 'RN23 — folga concedida em troca de feriado trabalhado. A existência do registro afasta o pagamento em dobro (Lei 605/1949, art. 9º; Súmula 146 TST).';

-- Chaves e indices, um a um, sem abortar quando ja existirem.
DO $ddl$
BEGIN
  BEGIN
    ALTER TABLE ONLY public.feriado_excecao ADD CONSTRAINT feriado_excecao_pkey PRIMARY KEY (id);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'feriado_excecao_pkey: %', SQLERRM; END;
  BEGIN
    ALTER TABLE ONLY public.feriado_folga_compensatoria ADD CONSTRAINT feriado_folga_compensatoria_pkey PRIMARY KEY (id);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'feriado_folga_compensatoria_pkey: %', SQLERRM; END;
END $ddl$;

CREATE INDEX IF NOT EXISTS feriado_excecao_busca_idx
  ON public.feriado_excecao USING btree (tenant_id, colaborador_id, data);
CREATE INDEX IF NOT EXISTS idx_folga_compensatoria_periodo
  ON public.feriado_folga_compensatoria USING btree (tenant_id, data_feriado);
CREATE UNIQUE INDEX IF NOT EXISTS uq_folga_compensatoria_feriado
  ON public.feriado_folga_compensatoria USING btree (tenant_id, colaborador_cpf, data_feriado);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.feriado_excecao TO authenticated;
GRANT ALL ON public.feriado_excecao TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.feriado_folga_compensatoria TO authenticated;
GRANT ALL ON public.feriado_folga_compensatoria TO service_role;

ALTER TABLE public.feriado_excecao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feriado_folga_compensatoria ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant gerencia feriado_excecao" ON public.feriado_excecao;
CREATE POLICY "Tenant gerencia feriado_excecao" ON public.feriado_excecao TO authenticated
  USING ((tenant_id = public.current_user_tenant_id()))
  WITH CHECK ((tenant_id = public.current_user_tenant_id()));

DROP POLICY IF EXISTS "Tenant manage feriado_folga_compensatoria" ON public.feriado_folga_compensatoria;
CREATE POLICY "Tenant manage feriado_folga_compensatoria" ON public.feriado_folga_compensatoria TO authenticated
  USING ((tenant_id = public.current_user_tenant_id()))
  WITH CHECK ((tenant_id = public.current_user_tenant_id()));

-- ---------------------------------------------------------------------------
-- (2) COMO CADA ESCALA TRATA FERIADO
-- ---------------------------------------------------------------------------
ALTER TABLE public.ponto_escalas
  ADD COLUMN IF NOT EXISTS comportamento_feriado text;

COMMENT ON COLUMN public.ponto_escalas.comportamento_feriado IS
  'Como esta escala trata feriado (folga / trabalha / trabalha com adicional). Consultado por feriado_comportamento, que a exceção do colaborador sobrepõe.';

-- ---------------------------------------------------------------------------
-- (3) A CADEIA DE APURACAO — estado atual do projeto (com as correcoes
--     posteriores da Onda 4 e da Onda 5 ja embutidas).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.feriados_da_empresa(p_tenant_id uuid, p_empresa_id uuid, p_ini date, p_fim date)
 RETURNS TABLE(data date, nome text, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH loc AS (
    -- Subselects escalares: devolve sempre UMA linha, com NULL quando a
    -- empresa não existe. Um JOIN aqui zeraria também os nacionais.
    SELECT
      (SELECT ec.estado FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS uf,
      (SELECT ec.cidade FROM public.empresa_cadastro ec WHERE ec.id = p_empresa_id) AS cidade
  ),
  dias AS (
    SELECT g::date AS d FROM generate_series(p_ini, p_fim, interval '1 day') g
  ),
  candidatos AS (
    -- P0: tabela nomeada vinculada à filial
    SELECT d.d AS data, i.nome, 'tabela'::text AS origem, 0 AS prio
    FROM dias d
    JOIN public.feriado_tabela_empresas v ON v.empresa_id = p_empresa_id
    JOIN public.feriado_tabelas t
      ON t.id = v.tabela_id AND t.ativo = true AND t.tenant_id = p_tenant_id
     AND (t.ano IS NULL OR t.ano = EXTRACT(YEAR FROM d.d)::int)
    JOIN public.feriado_tabela_itens i
      ON i.tabela_id = t.id AND i.ativo = true AND i.tipo = 'feriado'
     AND (
       (i.recorrente = true
         AND i.dia = EXTRACT(DAY FROM d.d)::smallint
         AND i.mes = EXTRACT(MONTH FROM d.d)::smallint)
       OR (i.recorrente = false AND i.data = d.d)
     )
    WHERE p_empresa_id IS NOT NULL

    UNION ALL

    -- P1..P4: base public.feriados
    SELECT d.d, f.nome, f.abrangencia,
           CASE f.abrangencia
             WHEN 'filial' THEN 1 WHEN 'municipal' THEN 2
             WHEN 'estadual' THEN 3 ELSE 4 END
    FROM dias d
    CROSS JOIN loc
    JOIN public.feriados f
      ON COALESCE(f.ativo, true) = true AND f.tipo = 'feriado'
     AND (f.tenant_id IS NULL OR f.tenant_id = p_tenant_id)
     AND (
       (COALESCE(f.recorrente, false) = true
         AND f.dia = EXTRACT(DAY FROM d.d)::smallint
         AND f.mes = EXTRACT(MONTH FROM d.d)::smallint)
       OR (COALESCE(f.recorrente, false) = false AND f.data = d.d)
     )
     AND (
       f.abrangencia = 'nacional'
       OR (f.abrangencia = 'filial'
           AND p_empresa_id IS NOT NULL AND f.empresa_id = p_empresa_id)
       OR (f.abrangencia = 'estadual'
           AND loc.uf IS NOT NULL AND btrim(loc.uf) <> ''
           AND upper(btrim(f.uf)) = upper(btrim(loc.uf)))
       OR (f.abrangencia = 'municipal'
           AND loc.uf IS NOT NULL AND btrim(loc.uf) <> ''
           AND loc.cidade IS NOT NULL AND btrim(loc.cidade) <> ''
           AND upper(btrim(f.uf)) = upper(btrim(loc.uf))
           AND upper(btrim(f.municipio)) = upper(btrim(loc.cidade)))
     )
  )
  SELECT DISTINCT ON (c.data) c.data, c.nome, c.origem
  FROM candidatos c
  ORDER BY c.data, c.prio, c.nome;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_empresa_do_colaborador(p_colaborador_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT empresa_id FROM public.admissoes WHERE id = p_colaborador_id;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_empresa_do_cpf(p_tenant_id uuid, p_cpf text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT a.empresa_id
  FROM public.admissoes a
  WHERE a.tenant_id = p_tenant_id
    AND a.empresa_id IS NOT NULL
    AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
        = regexp_replace(COALESCE(p_cpf, ''), '[^0-9]', '', 'g')
  ORDER BY COALESCE(a.inativo, false), a.data_admissao DESC NULLS LAST
  LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.feriado_comportamento(p_tenant_id uuid, p_cpf text, p_colaborador_id uuid, p_data date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_comp TEXT;
BEGIN
  SELECT comportamento INTO v_comp FROM public.feriado_excecao
  WHERE tenant_id = p_tenant_id AND colaborador_id = p_colaborador_id AND data = p_data LIMIT 1;
  IF v_comp IS NOT NULL THEN RETURN v_comp; END IF;

  SELECT comportamento INTO v_comp FROM public.feriado_excecao
  WHERE tenant_id = p_tenant_id AND colaborador_id = p_colaborador_id AND data IS NULL LIMIT 1;
  IF v_comp IS NOT NULL THEN RETURN v_comp; END IF;

  SELECT e.comportamento_feriado INTO v_comp
  FROM public.ponto_escala_atribuicoes a
  JOIN public.ponto_escalas e ON e.id = a.escala_id
  WHERE a.tenant_id = p_tenant_id
    AND (a.colaborador_cpf = p_cpf OR a.colaborador_id = p_colaborador_id::text)
    AND COALESCE(a.ativa, true) = true
    AND a.data_inicio <= p_data AND (a.data_fim IS NULL OR a.data_fim >= p_data)
  ORDER BY a.data_inicio DESC LIMIT 1;

  RETURN COALESCE(v_comp, 'folga');
END;
$function$
;

CREATE OR REPLACE FUNCTION public.feriado_folga_compensatoria_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public.ponto_colaborador_id_por_cpf(p_tenant_id uuid, p_colaborador_cpf text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cid uuid;
BEGIN
  SELECT pd.colaborador_id INTO v_cid
  FROM public.ponto_diario pd
  WHERE pd.tenant_id = p_tenant_id AND pd.colaborador_cpf = p_colaborador_cpf
    AND pd.colaborador_id IS NOT NULL
  ORDER BY pd.data DESC LIMIT 1;

  IF v_cid IS NULL THEN
    SELECT pm.colaborador_id INTO v_cid
    FROM public.ponto_marcacoes pm
    WHERE pm.tenant_id = p_tenant_id AND pm.colaborador_cpf = p_colaborador_cpf
      AND pm.colaborador_id IS NOT NULL
    ORDER BY pm.created_at DESC LIMIT 1;
  END IF;

  RETURN v_cid;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_feriados_colaborador(p_tenant_id uuid, p_colaborador_id uuid, p_ini date, p_fim date)
 RETURNS TABLE(data date, nome text, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT h.data, h.nome, h.origem
  FROM public.feriados_da_empresa(
         p_tenant_id,
         public.ponto_empresa_do_colaborador(p_colaborador_id),
         p_ini, p_fim) h
  ORDER BY h.data;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_feriados_trabalhados(p_tenant_id uuid, p_colaborador_cpf text, p_ini date, p_fim date)
 RETURNS TABLE(data date, feriado_nome text, origem text, comportamento text, trabalhado_min integer, folga_compensatoria_em date, adicional_100_min integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cid uuid;
  v_emp uuid;
BEGIN
  v_cid := public.ponto_colaborador_id_por_cpf(p_tenant_id, p_colaborador_cpf);
  IF v_cid IS NULL THEN
    SELECT a.id INTO v_cid FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
    ORDER BY COALESCE(a.inativo, false), a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;
  IF v_cid IS NULL THEN RETURN; END IF;

  -- A empresa vem da admissão pelo CPF quando o id da linha de ponto não
  -- corresponde a uma admissão. Sem isso o feriado da unidade some.
  v_emp := COALESCE(public.ponto_empresa_do_colaborador(v_cid),
                    public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf));

  RETURN QUERY
  SELECT
    h.data,
    h.nome,
    h.origem,
    public.feriado_comportamento(p_tenant_id, p_colaborador_cpf, v_cid, h.data) AS comportamento,
    t.trab_min,
    fc.data_folga,
    CASE WHEN fc.data_folga IS NULL AND NOT COALESCE((SELECT c.eh_ciclo FROM public.ponto_apurar_ciclo_plantao_do_dia(p_tenant_id, p_colaborador_cpf, v_cid::text, h.data) c LIMIT 1), false) THEN t.trab_min ELSE 0 END AS adicional_100_min
  FROM public.feriados_da_empresa(p_tenant_id, v_emp, p_ini, p_fim) h
  JOIN LATERAL (
    SELECT COALESCE((EXTRACT(EPOCH FROM pd.horas_trabalhadas) / 60)::int, 0) AS trab_min
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.colaborador_cpf = p_colaborador_cpf
      AND pd.data = h.data
    LIMIT 1
  ) t ON t.trab_min > 0
  LEFT JOIN public.feriado_folga_compensatoria fc
    ON fc.tenant_id = p_tenant_id
   AND fc.colaborador_cpf = p_colaborador_cpf
   AND fc.data_feriado = h.data
  ORDER BY h.data;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_feriados_competencia(p_tenant_id uuid, p_colaborador_cpf text, p_competencia text)
 RETURNS TABLE(data date, feriado_nome text, origem text, trabalhado_min integer, folga_compensatoria_em date, adicional_100_min integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cid uuid;
  v_emp uuid;
  v_ini date;
  v_fim date;
BEGIN
  v_cid := public.ponto_colaborador_id_por_cpf(p_tenant_id, p_colaborador_cpf);
  IF v_cid IS NULL THEN
    SELECT a.id INTO v_cid FROM public.admissoes a
    WHERE a.tenant_id = p_tenant_id
      AND regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g')
          = regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g')
    ORDER BY COALESCE(a.inativo, false), a.data_admissao DESC NULLS LAST
    LIMIT 1;
  END IF;
  IF v_cid IS NULL THEN RETURN; END IF;

  v_emp := COALESCE(public.ponto_empresa_do_colaborador(v_cid),
                    public.ponto_empresa_do_cpf(p_tenant_id, p_colaborador_cpf));

  v_ini := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim := (v_ini + interval '1 month - 1 day')::date;

  RETURN QUERY
  SELECT
    h.data,
    h.nome,
    h.origem,
    COALESCE(t.trab_min, 0),
    fc.data_folga,
    CASE WHEN COALESCE(t.trab_min, 0) > 0 AND fc.data_folga IS NULL
         THEN t.trab_min ELSE 0 END
  FROM public.feriados_da_empresa(p_tenant_id, v_emp, v_ini, v_fim) h
  LEFT JOIN LATERAL (
    SELECT COALESCE((EXTRACT(EPOCH FROM pd.horas_trabalhadas) / 60)::int, 0) AS trab_min
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.colaborador_cpf = p_colaborador_cpf
      AND pd.data = h.data
    LIMIT 1
  ) t ON true
  LEFT JOIN public.feriado_folga_compensatoria fc
    ON fc.tenant_id = p_tenant_id
   AND fc.colaborador_cpf = p_colaborador_cpf
   AND fc.data_feriado = h.data
  ORDER BY h.data;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_feriado_adicional_competencia(p_tenant_id uuid, p_empresa_id uuid, p_competencia text)
 RETURNS TABLE(colaborador_cpf text, colaborador_nome text, qtd_feriados_trabalhados integer, minutos_trabalhados integer, minutos_adicional_100 integer, dias_compensados integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ini date;
  v_fim date;
BEGIN
  v_ini := to_date(p_competencia || '-01', 'YYYY-MM-DD');
  v_fim := (v_ini + interval '1 month - 1 day')::date;

  RETURN QUERY
  WITH colabs AS (
    SELECT DISTINCT pd.colaborador_cpf AS cpf,
           MAX(pd.colaborador_nome) AS nome
    FROM public.ponto_diario pd
    WHERE pd.tenant_id = p_tenant_id
      AND pd.data BETWEEN v_ini AND v_fim
      AND (p_empresa_id IS NULL OR pd.empresa_id = p_empresa_id)
    GROUP BY pd.colaborador_cpf
  ),
  apurado AS (
    SELECT c.cpf, c.nome, f.*
    FROM colabs c
    CROSS JOIN LATERAL public.ponto_feriados_trabalhados(p_tenant_id, c.cpf, v_ini, v_fim) f
  )
  SELECT
    a.cpf,
    a.nome,
    COUNT(*)::int,
    COALESCE(SUM(a.trabalhado_min), 0)::int,
    COALESCE(SUM(a.adicional_100_min), 0)::int,
    COUNT(*) FILTER (WHERE a.folga_compensatoria_em IS NOT NULL)::int
  FROM apurado a
  GROUP BY a.cpf, a.nome
  HAVING COUNT(*) > 0
  ORDER BY a.nome;
END;
$function$
;

DROP TRIGGER IF EXISTS trg_folga_compensatoria_touch ON public.feriado_folga_compensatoria;
CREATE TRIGGER trg_folga_compensatoria_touch
  BEFORE INSERT OR UPDATE ON public.feriado_folga_compensatoria
  FOR EACH ROW EXECUTE FUNCTION public.feriado_folga_compensatoria_touch();

REVOKE EXECUTE ON FUNCTION public.feriado_comportamento(uuid, text, uuid, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.feriado_comportamento(uuid, text, uuid, date) TO authenticated, service_role;

COMMENT ON TABLE public.feriado_folga_compensatoria IS
  'Registro da folga compensatoria de feriado trabalhado (art. 9, Lei 605/1949). Sua presenca afasta o adicional de 100% apurado por ponto_feriado_adicional_competencia. RN23.';
COMMENT ON FUNCTION public.ponto_feriado_adicional_competencia(uuid, uuid, text) IS
  'Minutos de feriado trabalhado com adicional de 100% por colaborador na competencia, descontando os feriados com folga compensatoria registrada. Verba de folha — nao entra no saldo de banco de horas. RN23 (Lei 605/1949 art. 9; Sumula 146 do TST).';

-- A tabela nova entra na trava do cercado de QA, quando o motor existir.
DO $cercas$
DECLARE v_n int;
BEGIN
  IF to_regprocedure('public.qa_instalar_cercas()') IS NULL THEN RETURN; END IF;
  SELECT count(*) INTO v_n FROM public.qa_instalar_cercas();
  RAISE NOTICE 'Cercas de QA conferidas: % tabela(s).', v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cercas nao puderam ser conferidas agora (%).', SQLERRM;
END $cercas$;

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | t | t | t | t | t | OK
--   rn23_apuracao   : ponto_feriado_adicional_competencia(uuid,uuid,text)
--   comportamento   : feriado_comportamento(uuid,text,uuid,date)
--   tabela_folga    : feriado_folga_compensatoria
--   tabela_excecao  : feriado_excecao
--   coluna_escala   : ponto_escalas.comportamento_feriado
--   cadeia_completa : as 4 funcoes de apoio da apuracao
--   preserva_12x36  : a distincao de plantao/12x36 continua em
--                     ponto_feriados_trabalhados (nao foi regredida)
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (to_regprocedure('public.ponto_feriado_adicional_competencia(uuid,uuid,text)') IS NOT NULL) AS rn23_apuracao,
    (to_regprocedure('public.feriado_comportamento(uuid,text,uuid,date)') IS NOT NULL) AS comportamento,
    (to_regclass('public.feriado_folga_compensatoria') IS NOT NULL) AS tabela_folga,
    (to_regclass('public.feriado_excecao') IS NOT NULL) AS tabela_excecao,
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'ponto_escalas'
               AND column_name = 'comportamento_feriado') AS coluna_escala,
    (SELECT count(DISTINCT p.proname) = 4 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('ponto_feriados_colaborador','ponto_colaborador_id_por_cpf',
                          'ponto_feriados_trabalhados','ponto_feriados_competencia')) AS cadeia_completa,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'ponto_feriados_trabalhados'
               AND (p.prosrc ILIKE '%12x36%' OR p.prosrc ILIKE '%plantao%'
                    OR p.prosrc ILIKE '%ciclo_horas%')) AS preserva_12x36
)
SELECT rn23_apuracao, comportamento, tabela_folga, tabela_excecao, coluna_escala,
       cadeia_completa, preserva_12x36,
       CASE WHEN rn23_apuracao AND comportamento AND tabela_folga AND tabela_excecao
                 AND coluna_escala AND cadeia_completa AND preserva_12x36
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;



-- ############################################################
-- BLOCO: script_ponto_vigilancias_diarias.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — Vigilancias do ponto: rotina diaria que faz as monitorias RODAREM
--
-- Colar INTEIRO no SQL Editor do projeto de PRODUCAO e executar uma vez.
--
-- CONTEXTO
--   As ondas 5, 7, 8, 9 e 10 criaram rotinas de vigilancia que geram alerta no
--   painel de Alertas CLT (vencimento e teto do banco de horas, controle de
--   fato que descaracteriza o art. 62, obrigatoriedade do controle por
--   estabelecimento, vigencia de instrumento coletivo, formalizacao de escala
--   12x36/revezamento e cobertura de turno). Nenhuma tem gatilho nem
--   agendamento: sao funcoes que alguem precisa chamar. Como nenhuma tela
--   chama, essas familias de alerta nunca foram emitidas.
--
-- O QUE ESTE SCRIPT FAZ
--   (1) Cria a rotina public.ponto_vigilancias_diarias(), que percorre os
--       tenants ativos e executa cada uma das OITO monitorias isolando erro
--       por tenant/rotina (uma falha nao impede as demais): banco de horas,
--       art. 62, obrigatoriedade por estabelecimento, vigencia de CCT,
--       formalizacao de escala, cobertura de turno, vencimento do certificado
--       digital e prazo de 48h do comprovante.
--   (2) Agenda essa rotina no pg_cron para rodar 1x por dia, as 03:37 UTC.
--
-- SEGURANCA DO DADO
--   Este script SO CRIA coisa nova (uma funcao e um agendamento). Nao altera
--   nem apaga nenhuma linha existente, entao nao ha copia de seguranca a
--   fazer. As rotinas chamadas apenas INSEREM alerta e todas ja se protegem
--   contra duplicidade, entao rodar todo dia nao repete alerta. Nenhuma delas
--   altera marcacao, apuracao, saldo ou espelho.
--
-- IDEMPOTENTE: rodar duas vezes nao quebra nem duplica (CREATE OR REPLACE e
-- reagendamento do mesmo job).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_vigilancias_diarias()
RETURNS TABLE(rotina text, alertas integer, tenants_com_erro integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $vig$
DECLARE
  t          RECORD;
  v_n        integer;
  v_banco    integer := 0;
  v_art62    integer := 0;  v_e_art62    integer := 0;
  v_estab    integer := 0;  v_e_estab    integer := 0;
  v_cct      integer := 0;  v_e_cct      integer := 0;
  v_escala   integer := 0;  v_e_escala   integer := 0;
  v_cobert   integer := 0;  v_e_cobert   integer := 0;
  v_cert     integer := 0;  v_e_cert     integer := 0;
  v_compr    integer := 0;  v_e_compr    integer := 0;
BEGIN
  -- (a) Banco de horas: vencimento e teto de acúmulo. É a única sem
  -- tenant_id no argumento — varre a base inteira de uma vez.
  BEGIN
    SELECT public.ponto_banco_alertas_monitorar() INTO v_n;
    v_banco := COALESCE(v_n, 0);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ponto_banco_alertas_monitorar falhou: %', SQLERRM;
    v_banco := -1;
  END;

  -- (b) Demais vigilâncias: por tenant ativo, isolando o erro de cada uma.
  FOR t IN SELECT id FROM public.tenants WHERE COALESCE(ativo, true) = true LOOP

    BEGIN
      SELECT public.ponto_detectar_descaracterizacao_art62(t.id) INTO v_n;
      v_art62 := v_art62 + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_art62 := v_e_art62 + 1;
      RAISE NOTICE 'descaracterizacao_art62 falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_estabelecimento_obrigatoriedade_monitorar(t.id) INTO v_n;
      v_estab := v_estab + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_estab := v_e_estab + 1;
      RAISE NOTICE 'estabelecimento_obrigatoriedade falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_cct_vigiar_vigencia(t.id) INTO v_n;
      v_cct := v_cct + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cct := v_e_cct + 1;
      RAISE NOTICE 'cct_vigiar_vigencia falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_escala_formalizacao_monitorar(t.id) INTO v_n;
      v_escala := v_escala + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_escala := v_e_escala + 1;
      RAISE NOTICE 'escala_formalizacao falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_escala_cobertura_monitorar(t.id) INTO v_n;
      v_cobert := v_cobert + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cobert := v_e_cobert + 1;
      RAISE NOTICE 'escala_cobertura falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_certificado_vigiar_vencimento(t.id) INTO v_n;
      v_cert := v_cert + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_cert := v_e_cert + 1;
      RAISE NOTICE 'certificado_vigiar_vencimento falhou no tenant %: %', t.id, SQLERRM;
    END;

    BEGIN
      SELECT public.ponto_comprovante_vigiar_48h(t.id) INTO v_n;
      v_compr := v_compr + COALESCE(v_n, 0);
    EXCEPTION WHEN OTHERS THEN
      v_e_compr := v_e_compr + 1;
      RAISE NOTICE 'comprovante_vigiar_48h falhou no tenant %: %', t.id, SQLERRM;
    END;

  END LOOP;

  RETURN QUERY
  SELECT * FROM (VALUES
    ('banco_horas_vencimento_e_teto', v_banco,  0),
    ('descaracterizacao_art62',       v_art62,  v_e_art62),
    ('estabelecimento_obrigatorio',   v_estab,  v_e_estab),
    ('cct_vigencia',                  v_cct,    v_e_cct),
    ('escala_formalizacao',           v_escala, v_e_escala),
    ('escala_cobertura_turno',        v_cobert, v_e_cobert),
    ('certificado_vencimento',        v_cert,   v_e_cert),
    ('comprovante_prazo_48h',         v_compr,  v_e_compr)
  ) AS x(rotina, alertas, tenants_com_erro);
END;
$vig$;

COMMENT ON FUNCTION public.ponto_vigilancias_diarias() IS
  'Executa as vigilancias do ponto (banco de horas, art. 62, obrigatoriedade por estabelecimento, vigencia de CCT, formalizacao de escala, cobertura de turno, vencimento do certificado digital e prazo de 48h do comprovante) em todos os tenants ativos, isolando erro por tenant/rotina. Somente insere alerta; nao altera marcacao, apuracao nem espelho. Agendada diariamente.';

REVOKE EXECUTE ON FUNCTION public.ponto_vigilancias_diarias() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ponto_vigilancias_diarias() TO authenticated;

-- Agendamento diário -------------------------------------------------------
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ponto-vigilancias-diarias')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias');
    PERFORM cron.schedule('ponto-vigilancias-diarias', '37 3 * * *',
      'SELECT public.ponto_vigilancias_diarias();');
    RAISE NOTICE 'Vigilancias do ponto agendadas (03:37 UTC, diariamente).';
  ELSE
    RAISE NOTICE 'pg_cron ausente — chame public.ponto_vigilancias_diarias() pela aplicacao.';
  END IF;
END $cron$;
-- ============================================================================
-- CONFERENCIA (o editor mostra so o ultimo resultado)
-- ============================================================================
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ponto_vigilancias_diarias') = 1
    AS rotina_criada,
  EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    AS pg_cron_presente,
  (SELECT count(*) FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias') = 1
    AS agendamento_ativo,
  (SELECT schedule FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias')
    AS horario_utc,
  (SELECT count(*) FROM public.tenants WHERE COALESCE(ativo, true) = true)
    AS tenants_que_serao_varridos,
  CASE
    WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'ponto_vigilancias_diarias') <> 1
      THEN 'FALHOU — a rotina nao foi criada; veja as mensagens acima'
    WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
      THEN 'ATENCAO — rotina criada, mas o pg_cron nao esta neste banco: nada sera agendado'
    WHEN (SELECT count(*) FROM cron.job WHERE jobname = 'ponto-vigilancias-diarias') = 1
      THEN 'OK'
    ELSE 'FALHOU — a rotina existe mas o agendamento nao foi criado'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto004_imutabilidade.sql
-- ############################################################

-- ============================================================================
-- SCRIPT DE ENTREGA — PONTO-004: marcação original imutável + remover backdoor
-- Cole no SQL Editor do banco de PRODUÇÃO (projeto diayjpsrcerycycyaxst)
-- SOMENTE após aprovar no ambiente de teste. Idempotente (pode rodar 2x).
--
-- Efeito:
--   (1) exclusão DIRETA de marcação de ponto (public.ponto_marcacoes) por papel
--       de gestão deixa de ser permitida — a correção passa a ser por acréscimo.
--       A exclusão de AJUSTES (public.ponto_ajustes) e da consolidação diária
--       (public.ponto_diario) continua funcionando como hoje, pelos mesmos papéis:
--       ajuste é o próprio acréscimo e ponto_diario é derivado/recalculável.
--   (2) remove o e-mail real hardcoded (backdoor de exclusão + dado pessoal real
--       no código, LGPD) de public.pode_excluir_registro_ponto.
--   (3) atualiza a nota de risco da rotina de QA PONTO-004 (se o motor de QA
--       estiver instalado neste banco).
--
-- NÃO cobre (decisão pendente, ver conversa): os RPC excluir_marcacao_ponto e
-- processar_ajuste_ponto (tipo "correcao") continuam apagando a marcação original
-- pelo flag de sessão app.allow_ponto_delete. É por eles que a tela do gestor
-- apaga hoje.
-- ============================================================================

SET LOCAL lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 1) Trigger de proteção contra exclusão da marcação original.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bloquear_delete_ponto()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;

  IF current_setting('app.allow_ponto_delete', true) = 'true' THEN
    RETURN OLD;
  END IF;

  -- Fora da marcação original, a regra de papéis continua valendo
  -- (ponto_ajustes = acréscimos; ponto_diario = consolidação derivada).
  IF TG_TABLE_NAME <> 'ponto_marcacoes'
     AND public.pode_excluir_registro_ponto(OLD.tenant_id) THEN
    RETURN OLD;
  END IF;

  INSERT INTO public.ponto_audit_log (
    tenant_id, tabela_origem, registro_id, acao, dados_anteriores, usuario_id
  ) VALUES (
    OLD.tenant_id, TG_TABLE_NAME, OLD.id, 'TENTATIVA_DELETE', to_jsonb(OLD), auth.uid()
  );

  IF TG_TABLE_NAME = 'ponto_marcacoes' THEN
    RAISE EXCEPTION 'Marcacao de ponto e imutavel: nao pode ser apagada (Sumula 338 / Portaria 671). Use correcao por acrescimo.';
  END IF;

  RAISE EXCEPTION 'Operação de exclusão não permitida para registros de ponto. Tentativa registrada.';
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) Remove o e-mail real hardcoded (backdoor + LGPD).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pode_excluir_registro_ponto(_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL OR _tenant_id IS NULL THEN
    RETURN false;
  END IF;
  IF public.has_minimum_role(auth.uid(), 'manager'::public.app_role)
     OR public.has_role(auth.uid(), 'superadmin'::public.app_role) THEN
    RETURN true;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = auth.uid() AND ub.tenant_id = _tenant_id
      AND ub.status::text = 'ativo'
      AND ub.tipo_usuario::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.usuario_vinculos uv
    JOIN public.usuarios_base ub ON ub.id = uv.usuario_id
    WHERE ub.auth_user_id = auth.uid() AND uv.tenant_id = _tenant_id
      AND uv.status::text = 'ativo'
      AND uv.tipo_vinculo::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) QA PONTO-004 — atualiza a nota de risco. Se o motor de QA não existir
--    neste banco, apenas avisa e segue (não aborta o script).
-- ---------------------------------------------------------------------------
DO $prodqa$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'qa_retorno'
  ) THEN
    RAISE NOTICE 'Motor de QA nao instalado neste banco: qa_caso_ponto_004 ignorado.';
    RETURN;
  END IF;

  EXECUTE $qa004$
  CREATE OR REPLACE FUNCTION public.qa_caso_ponto_004()
  RETURNS public.qa_retorno LANGUAGE plpgsql AS $body$
  DECLARE r public.qa_retorno; v_cpf text; v_id uuid;
          v_upd boolean := false; v_del boolean := false;
  BEGIN
    v_cpf := public.qa_ponto_admissao('QA Imutável', 5004);
    PERFORM public.qa_ponto_marca(v_cpf, 'QA Imutável', CURRENT_DATE - 1, TIME '08:00', 'entrada');
    SELECT id INTO v_id FROM public.ponto_marcacoes
    WHERE tenant_id = public.qa_sandbox_tenant_id() AND colaborador_cpf = v_cpf LIMIT 1;

    r.passo_ordem := 1;
    r.passo_acao := 'Tentar ALTERAR a hora da marcação original';
    r.esperado := 'Bloqueado pela imutabilidade';
    BEGIN
      UPDATE public.ponto_marcacoes SET hora_marcacao = TIME '07:00' WHERE id = v_id;
      v_upd := true;
    EXCEPTION WHEN OTHERS THEN v_upd := false; END;

    r.passo_ordem := 2;
    r.passo_acao := 'Tentar APAGAR a marcação original (sem privilégio de gestor)';
    r.esperado := 'Bloqueado';
    BEGIN
      DELETE FROM public.ponto_marcacoes WHERE id = v_id;
      v_del := NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes WHERE id = v_id);
    EXCEPTION WHEN OTHERS THEN v_del := false; END;

    IF NOT v_upd AND NOT v_del THEN
      r.situacao := 'passou';
      r.obtido := 'Alteração e exclusão da marcação original foram bloqueadas. A exclusão direta '
               || 'por papel de gestão foi fechada e o e-mail hardcoded de exceção foi removido. '
               || 'Risco remanescente (fora desta rotina): os RPC excluir_marcacao_ponto e '
               || 'processar_ajuste_ponto (tipo "correcao") ainda apagam a marcação original pelo '
               || 'flag de sessão app.allow_ponto_delete — correção por substituição, não por acréscimo.';
    ELSE
      r.situacao := 'falhou';
      r.obtido := format('A marcação original foi %s — registro que se altera não prova nada '
               || '(Súmula 338; Portaria 671 veda a alteração).',
               CASE WHEN v_upd AND v_del THEN 'ALTERADA E APAGADA'
                    WHEN v_upd THEN 'ALTERADA' ELSE 'APAGADA' END);
    END IF;
    RETURN r;
  EXCEPTION WHEN OTHERS THEN
    r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
  END $body$;
  $qa004$;

  RAISE NOTICE 'qa_caso_ponto_004 atualizado.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nao foi possivel atualizar qa_caso_ponto_004: %', SQLERRM;
END
$prodqa$;

-- ---------------------------------------------------------------------------
-- Conferência (o SQL Editor mostra só o último resultado).
-- Esperado: true | true | true | 3 | 'OK'
-- ---------------------------------------------------------------------------
SELECT
  position('cafefrossard' in pg_get_functiondef('public.pode_excluir_registro_ponto(uuid)'::regprocedure)) = 0
    AS email_hardcoded_removido,
  position('Marcacao de ponto e imutavel' in pg_get_functiondef('public.bloquear_delete_ponto()'::regprocedure)) > 0
    AS marcacao_original_blindada,
  position('ponto_ajustes' in pg_get_functiondef('public.pode_excluir_registro_ponto(uuid)'::regprocedure)) = 0
    AND position('pode_excluir_registro_ponto' in pg_get_functiondef('public.bloquear_delete_ponto()'::regprocedure)) > 0
    AS exclusao_de_ajustes_preservada,
  (SELECT count(*) FROM pg_trigger tg
     WHERE NOT tg.tgisinternal
       AND tg.tgfoid = 'public.bloquear_delete_ponto()'::regprocedure) AS triggers_de_protecao,
  CASE
    WHEN position('cafefrossard' in pg_get_functiondef('public.pode_excluir_registro_ponto(uuid)'::regprocedure)) > 0
      THEN 'ERRO: e-mail hardcoded ainda presente'
    WHEN position('Marcacao de ponto e imutavel' in pg_get_functiondef('public.bloquear_delete_ponto()'::regprocedure)) = 0
      THEN 'ERRO: trava de imutabilidade nao aplicada'
    WHEN (SELECT count(*) FROM pg_trigger tg
            WHERE NOT tg.tgisinternal
              AND tg.tgfoid = 'public.bloquear_delete_ponto()'::regprocedure) < 3
      THEN 'ATENCAO: menos de 3 triggers de protecao montados'
    ELSE 'OK'
  END AS erro_tecnico;



-- ############################################################
-- BLOCO: script_ponto_links_prazo_obrigatorio.sql
-- ############################################################

-- ============================================================================
-- ENTREGA — link de marcacao com prazo OBRIGATORIO (PONTO-251)
--
-- ACHADO DA BANCADA (bateria do Ponto na homologacao, 27/08/2026):
--     "De 248 link(s): data_expiracao aceita NULO no schema"
--
-- O link de marcacao e uma credencial distribuida por mensagem: o colaborador
-- recebe a URL e bate ponto por ela. Sem prazo obrigatorio no schema, nada
-- impede que um link nasca sem validade — e ai ele vira acesso PERMANENTE ao
-- ponto daquela pessoa, inclusive depois do desligamento. A protecao nao pode
-- depender de a consulta lembrar de filtrar por data: tem que estar na
-- estrutura.
--
-- Na producao a coluna existe e os 248 links atuais estao todos preenchidos —
-- a auditoria nao encontrou nenhum ativo sem prazo, nenhum vencido ainda
-- ativo, nenhum token curto e nenhuma colisao de token. Falta so a trava.
--
-- O QUE FAZ
--   1. Preenche qualquer link sem prazo (defensivo: hoje sao zero) com o
--      padrao da casa, 180 dias.
--   2. Torna data_expiracao obrigatoria no schema (DEFAULT + NOT NULL).
--   3. Traz as tres rotinas de manutencao que so existiam no ambiente de
--      teste: desativar vencidos, revogar links de desligados e renovar.
--      Sem elas o vencimento e so um campo — ninguem age sobre ele.
--
-- NAO altera o motor de saldo, o espelho nem o fechamento. NAO revoga nem
-- desativa nenhum link existente: apenas fecha a porta para os proximos e
-- entrega as ferramentas de manutencao. Idempotente; UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) Defensivo: nenhum link deve ficar para tras sem prazo. Um UPDATE so,
--     nao linha a linha — ha statement timeout.
UPDATE public.ponto_links
   SET data_expiracao = now() + interval '180 days'
 WHERE data_expiracao IS NULL;

-- (2) A trava entra na estrutura. Bloco proprio: se algo impedir, vira aviso
--     e a conferencia do fim mostra — em vez de abortar o arquivo inteiro.
DO $trava$
BEGIN
  ALTER TABLE public.ponto_links
    ALTER COLUMN data_expiracao SET DEFAULT (now() + '180 days'::interval);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'DEFAULT de data_expiracao nao pode ser ajustado: %', SQLERRM;
END $trava$;

DO $notnull$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ponto_links WHERE data_expiracao IS NULL) THEN
    RAISE NOTICE 'Ainda ha link sem prazo — NOT NULL nao aplicado. Ver a conferencia.';
  ELSE
    ALTER TABLE public.ponto_links ALTER COLUMN data_expiracao SET NOT NULL;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'NOT NULL de data_expiracao nao pode ser aplicado: %', SQLERRM;
END $notnull$;

-- (3) As rotinas de manutencao — estado atual do projeto.
CREATE OR REPLACE FUNCTION public.ponto_link_renovar(p_link_id uuid, p_dias integer DEFAULT 180)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link public.ponto_links;
  v_nova timestamptz;
BEGIN
  IF p_dias IS NULL OR p_dias < 1 OR p_dias > 365 THEN
    RAISE EXCEPTION 'Prazo inválido: informe entre 1 e 365 dias.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_link FROM public.ponto_links WHERE id = p_link_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link não encontrado.' USING ERRCODE = 'P0002';
  END IF;

  IF v_link.tenant_id IS DISTINCT FROM public.current_user_tenant_id() THEN
    RAISE EXCEPTION 'Sem permissão para renovar este link.' USING ERRCODE = '42501';
  END IF;

  v_nova := now() + make_interval(days => p_dias);

  UPDATE public.ponto_links
  SET data_expiracao = v_nova,
      ativo = true,
      updated_at = now()
  WHERE id = p_link_id;

  RETURN v_nova;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_links_desativar_vencidos()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int;
BEGIN
  UPDATE public.ponto_links
     SET ativo = false, updated_at = now()
   WHERE ativo = true
     AND data_expiracao <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ponto_links_revogar_desligados()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_qtd integer := 0;
BEGIN
  UPDATE public.ponto_links l
  SET ativo = false, updated_at = now()
  WHERE l.tipo <> 'compartilhado'
    AND l.ativo = true
    AND length(regexp_replace(COALESCE(l.colaborador_cpf, ''), '\D', '', 'g')) = 11
    AND NOT EXISTS (
      SELECT 1 FROM public.admissoes a
      WHERE a.tenant_id = l.tenant_id
        AND regexp_replace(COALESCE(a.cpf, ''), '\D', '', 'g') = regexp_replace(COALESCE(l.colaborador_cpf, ''), '\D', '', 'g')
        AND a.status = 'concluido'
        AND COALESCE(a.inativo, false) = false
        AND COALESCE(a.bate_ponto, true) = true
    );
  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  RETURN v_qtd;
END;
$function$
;


-- (4) O gatilho que ja preenche o prazo na gravacao — cinto alem da
--     suspensoria: mesmo um INSERT que esqueca a data nasce com prazo.
--     Tambem so existia em migration.
CREATE OR REPLACE FUNCTION public.ponto_links_validade_before()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.data_expiracao IS NULL THEN
      NEW.data_expiracao := now() + interval '180 days';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.token IS DISTINCT FROM OLD.token THEN
      NEW.data_expiracao := now() + interval '180 days';
    END IF;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$function$
;

DROP TRIGGER IF EXISTS trg_ponto_links_validade ON public.ponto_links;
CREATE TRIGGER trg_ponto_links_validade
  BEFORE INSERT OR UPDATE ON public.ponto_links
  FOR EACH ROW EXECUTE FUNCTION public.ponto_links_validade_before();

COMMENT ON COLUMN public.ponto_links.data_expiracao IS
  'Prazo do link de marcacao. Obrigatorio: link e credencial distribuida por mensagem e sem prazo vira acesso permanente ao ponto do colaborador. Padrao 180 dias. PONTO-251.';

-- ---------------------------------------------------------------------------
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: t | t | 0 | 0 | t | t | OK
--   prazo_obrigatorio : data_expiracao e NOT NULL no schema
--   tem_padrao        : a coluna tem DEFAULT (link novo ja nasce com prazo)
--   ativos_sem_prazo  : 0
--   vencidos_ativos   : quantos ativos ja passaram do prazo (informativo —
--                       nao reprova; e a fila de trabalho da rotina nova)
--   manutencao        : as 3 rotinas existem
--   gatilho           : trg_ponto_links_validade instalado
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (SELECT a.attnotnull FROM pg_attribute a
      WHERE a.attrelid = 'public.ponto_links'::regclass
        AND a.attname = 'data_expiracao') AS prazo_obrigatorio,
    EXISTS (SELECT 1 FROM pg_attrdef d
             JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
            WHERE d.adrelid = 'public.ponto_links'::regclass
              AND a.attname = 'data_expiracao') AS tem_padrao,
    (SELECT count(*) FROM public.ponto_links
      WHERE ativo IS TRUE AND data_expiracao IS NULL) AS ativos_sem_prazo,
    (SELECT count(*) FROM public.ponto_links
      WHERE ativo IS TRUE AND data_expiracao IS NOT NULL
        AND data_expiracao < now()) AS vencidos_ativos,
    (SELECT count(DISTINCT p.proname) = 3 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('ponto_links_desativar_vencidos',
                          'ponto_links_revogar_desligados',
                          'ponto_link_renovar')) AS manutencao,
    EXISTS (SELECT 1 FROM pg_trigger
             WHERE tgname = 'trg_ponto_links_validade'
               AND tgrelid = 'public.ponto_links'::regclass AND NOT tgisinternal) AS gatilho
)
SELECT prazo_obrigatorio, tem_padrao, ativos_sem_prazo, vencidos_ativos, manutencao, gatilho,
       CASE WHEN prazo_obrigatorio AND tem_padrao AND ativos_sem_prazo = 0 AND manutencao AND gatilho
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;


-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
    ('funcao', 'ponto_saldo_dias_competencia', NULL),
    ('funcao', 'ponto_dias_repetidos_na_apuracao', NULL),
    ('funcao', 'feriados_da_empresa', NULL),
    ('funcao', 'ponto_empresa_do_colaborador', NULL),
    ('funcao', 'ponto_empresa_do_cpf', NULL),
    ('funcao', 'feriado_comportamento', NULL),
    ('funcao', 'feriado_folga_compensatoria_touch', NULL),
    ('funcao', 'ponto_colaborador_id_por_cpf', NULL),
    ('funcao', 'ponto_feriados_colaborador', NULL),
    ('funcao', 'ponto_feriados_trabalhados', NULL),
    ('funcao', 'ponto_feriados_competencia', NULL),
    ('funcao', 'ponto_feriado_adicional_competencia', NULL),
    ('funcao', 'ponto_vigilancias_diarias', NULL),
    ('funcao', 'bloquear_delete_ponto', NULL),
    ('funcao', 'pode_excluir_registro_ponto', NULL),
    ('funcao', 'qa_caso_ponto_004', 'Tentar ALTERAR a hora da marcação original'),
    ('funcao', 'ponto_link_renovar', 'Prazo inválido: informe entre 1 e 365 dias.'),
    ('funcao', 'ponto_links_desativar_vencidos', NULL),
    ('funcao', 'ponto_links_revogar_desligados', ') = regexp_replace(COALESCE(l.colaborador_cpf, '),
    ('funcao', 'ponto_links_validade_before', NULL),
    ('tabela', 'feriado_excecao', NULL),
    ('tabela', 'feriado_folga_compensatoria', NULL),
    ('gatilho', 'trg_folga_compensatoria_touch', NULL),
    ('gatilho', 'trg_ponto_links_validade', NULL),
    ('indice', 'feriado_excecao_busca_idx', NULL),
    ('indice', 'idx_folga_compensatoria_periodo', NULL),
    ('indice', 'uq_folga_compensatoria_feriado', NULL),
    ('coluna', 'ponto_escalas.comportamento_feriado', NULL)
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
