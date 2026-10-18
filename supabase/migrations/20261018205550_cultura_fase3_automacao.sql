-- =========================================================
-- Cultura & Celebrações — Fase 3: automação segura, mensagem sugerida e alertas
--
-- Colunas novas (cultura_config e cultura_acoes), índice único por celebração,
-- rotina diária cultura_automacao_rodar (só cria ação PENDENTE; nunca conclui,
-- publica ou concede nada), RPC cultura_automacao_minha_empresa (botão Gerar
-- agora), agendamento às 06:00 de Brasília e a documentação de QA da fase.
-- Tudo nasce desligado: nenhum tenant é afetado até ligar a automação.
-- Idempotente.
-- =========================================================

SET lock_timeout = '10s';

-- 1) Colunas novas (idempotente). Sem tabela nova.
ALTER TABLE public.cultura_config
  ADD COLUMN IF NOT EXISTS automacao_aniversario text NOT NULL DEFAULT 'desligado',
  ADD COLUMN IF NOT EXISTS automacao_tempo_casa text NOT NULL DEFAULT 'desligado',
  ADD COLUMN IF NOT EXISTS tom_mensagem text NOT NULL DEFAULT 'leve',
  ADD COLUMN IF NOT EXISTS meta_cobertura integer NOT NULL DEFAULT 95;

ALTER TABLE public.cultura_acoes
  ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS chave_unica text,
  ADD COLUMN IF NOT EXISTS publicado_em timestamptz;

DO $chk$
BEGIN
  ALTER TABLE public.cultura_config
    ADD CONSTRAINT cultura_config_automacao_chk CHECK (
      automacao_aniversario IN ('desligado', 'aprovar')
      AND automacao_tempo_casa IN ('desligado', 'aprovar')
      AND tom_mensagem IN ('formal', 'leve')
      AND meta_cobertura BETWEEN 1 AND 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $chk$;

-- Uma celebracao (pessoa + tipo + ano) gera no maximo uma acao ativa.
-- Linhas antigas ficam com chave_unica nula e nao entram no indice.
CREATE UNIQUE INDEX IF NOT EXISTS cultura_acoes_chave_unica_uidx
  ON public.cultura_acoes (tenant_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), chave_unica)
  WHERE chave_unica IS NOT NULL AND status <> 'cancelada';

-- 2) Data de uma comemoracao anual num ano; 29/02 cai em 28/02 nos anos nao bissextos.
CREATE OR REPLACE FUNCTION public.cultura_data_no_ano(p_mes int, p_dia int, p_ano int)
RETURNS date LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
           WHEN p_mes = 2 AND p_dia = 29
                AND NOT (p_ano % 4 = 0 AND (p_ano % 100 <> 0 OR p_ano % 400 = 0))
             THEN make_date(p_ano, 2, 28)
           ELSE make_date(p_ano, p_mes, p_dia)
         END
$fn$;

-- 3) Rotina diaria: cria como PENDENTE (nunca conclui, nunca publica) as acoes das
-- celebracoes que cairem na janela de dias da Configuracao, so para os tenants que
-- ligaram a automacao. Preferencia de reconhecimento nao impede criar a acao interna:
-- ela so impede publicar, e publicar e sempre gesto humano.
CREATE OR REPLACE FUNCTION public.cultura_automacao_rodar(p_tenant uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_total integer := 0;
  v_n integer;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  c record;
BEGIN
  FOR c IN
    SELECT tenant_id,
           dias_antecedencia_acao AS dias,
           (aniversario_ativo AND automacao_aniversario = 'aprovar') AS faz_aniv,
           (tempo_casa_ativo AND automacao_tempo_casa = 'aprovar') AS faz_tempo
    FROM public.cultura_config
    WHERE p_tenant IS NULL OR tenant_id = p_tenant
  LOOP
    CONTINUE WHEN NOT (c.faz_aniv OR c.faz_tempo);
    BEGIN
      WITH pessoas AS MATERIALIZED (
        SELECT a.tenant_id, a.empresa_id, a.id::text AS pessoa_id, a.nome_completo,
               a.data_nascimento, a.data_admissao
        FROM public.admissoes a
        WHERE a.tenant_id = c.tenant_id
          AND a.status = 'concluido'
          AND a.empresa_id IS NOT NULL
      ),
      anos AS MATERIALIZED (
        SELECT y FROM generate_series(extract(year FROM v_hoje)::int, extract(year FROM v_hoje)::int + 1) AS y
      ),
      ocorrencias AS MATERIALIZED (
        SELECT p.tenant_id, p.empresa_id, p.pessoa_id, p.nome_completo,
               'aniversario'::text AS tipo,
               public.cultura_data_no_ano(extract(month FROM p.data_nascimento)::int,
                                          extract(day FROM p.data_nascimento)::int, an.y) AS data,
               NULL::int AS anos_casa
        FROM pessoas p CROSS JOIN anos an
        WHERE c.faz_aniv AND p.data_nascimento IS NOT NULL
        UNION ALL
        SELECT p.tenant_id, p.empresa_id, p.pessoa_id, p.nome_completo,
               'tempo_casa'::text,
               public.cultura_data_no_ano(extract(month FROM p.data_admissao)::int,
                                          extract(day FROM p.data_admissao)::int, an.y),
               an.y - extract(year FROM p.data_admissao)::int
        FROM pessoas p CROSS JOIN anos an
        WHERE c.faz_tempo AND p.data_admissao IS NOT NULL
          AND an.y - extract(year FROM p.data_admissao)::int >= 1
      )
      INSERT INTO public.cultura_acoes
        (tenant_id, empresa_id, tipo, titulo, colaborador_id, colaborador_nome,
         data_referencia, status, origem, chave_unica)
      SELECT o.tenant_id, o.empresa_id, o.tipo,
             CASE WHEN o.tipo = 'aniversario' THEN 'Aniversário de ' || o.nome_completo
                  ELSE o.anos_casa || ' ano' || CASE WHEN o.anos_casa > 1 THEN 's' ELSE '' END
                       || ' de empresa - ' || o.nome_completo END,
             o.pessoa_id, o.nome_completo, o.data, 'pendente', 'automatica',
             o.tipo || '|' || lower(btrim(o.nome_completo)) || '|' || extract(year FROM o.data)::int
      FROM ocorrencias o
      WHERE o.data BETWEEN v_hoje AND v_hoje + c.dias
        AND NOT EXISTS (
          SELECT 1 FROM public.cultura_acoes x
          WHERE x.tenant_id = o.tenant_id
            AND x.tipo = o.tipo
            AND lower(btrim(x.colaborador_nome)) = lower(btrim(o.nome_completo))
            AND extract(year FROM x.data_referencia) = extract(year FROM o.data)
            AND x.status <> 'cancelada')
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'cultura_automacao_rodar: tenant % ignorado (%)', c.tenant_id, SQLERRM;
    END;
  END LOOP;
  RETURN v_total;
END $fn$;

-- Chamada pela tela (botao Gerar agora): so para o tenant de quem chama e so gestor para cima.
CREATE OR REPLACE FUNCTION public.cultura_automacao_minha_empresa()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_uid IS NULL OR v_tenant IS NULL OR NOT public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RAISE EXCEPTION 'Sem permissão para gerar as ações de cultura.';
  END IF;
  RETURN public.cultura_automacao_rodar(v_tenant);
END $fn$;

REVOKE ALL ON FUNCTION public.cultura_automacao_rodar(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cultura_automacao_minha_empresa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cultura_automacao_minha_empresa() TO authenticated;

-- 4) Todo dia as 09:00 UTC (06:00 em Brasilia). Sem tenant que ligou a automacao, nao faz nada.
DO $cron$
BEGIN
  PERFORM cron.unschedule('cultura-automacao-diaria');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $cron$;

DO $cron$
BEGIN
  PERFORM cron.schedule('cultura-automacao-diaria', '0 9 * * *', $job$SELECT public.cultura_automacao_rodar()$job$);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento diário não pôde ser criado (%). A rotina continua chamável à mão.', SQLERRM;
END $cron$;

-- 5) QA (nivel api): base da automacao
CREATE OR REPLACE FUNCTION public.qa_caso_cult_090()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_padrao_ok boolean;
  v_bissexto boolean;
  v_indice boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) os padrões seguros da automação de Cultura';
  r.esperado    := 'Automação nasce desligada, 29/02 cai em 28/02 em ano comum e há índice único de celebração';

  v_padrao_ok := (SELECT count(*) = 2 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name IN ('automacao_aniversario', 'automacao_tempo_casa')
                    AND column_default LIKE '%desligado%');
  v_bissexto := (public.cultura_data_no_ano(2, 29, 2026) = DATE '2026-02-28'
                 AND public.cultura_data_no_ano(2, 29, 2028) = DATE '2028-02-29'
                 AND public.cultura_data_no_ano(3, 10, 2026) = DATE '2026-03-10');
  v_indice := EXISTS (SELECT 1 FROM pg_indexes
                      WHERE schemaname = 'public' AND indexname = 'cultura_acoes_chave_unica_uidx');

  IF v_padrao_ok AND v_bissexto AND v_indice THEN
    r.situacao := 'passou';
    r.obtido   := 'Padrão desligado, regra de 29/02 e índice único presentes.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('padrão desligado=%s; 29/02=%s; índice único=%s', v_padrao_ok, v_bissexto, v_indice);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste SET
    objetivo = 'A configuração governa a detecção e a automação: interruptores de aniversário, tempo de casa e dia da profissão, dias de antecedência, meta de cobertura, tom das mensagens sugeridas e, por tipo, se a rotina diária cria a ação pendente sozinha (padrão desligada).',
    resultado_esperado = 'A configuração persiste e muda o que a tela de Cultura, o Mural e a rotina diária fazem.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-050';

  UPDATE public.qa_casos_teste SET
    objetivo = 'A pergunta do RH é o que fazer agora. O painel Hoje lista as celebrações de hoje, as ações atrasadas e os rituais vencidos, cada um com ação de um toque. Em cada celebração de pessoa há o botão de sugerir mensagem, aberto no CULT-093. Ações criadas pela rotina diária trazem o selo Automática.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-080';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-090', 'Base da automação: padrão desligado, 29/02 e trava de duplicidade',
   'negativo', 'alta', 'aprovado', 'api', NULL,
   'A automação cria ações sozinha, então precisa nascer desligada (ninguém é afetado sem decidir), tratar 29/02 e ter o índice único que impede duas ações para a mesma celebração.',
   'Banco com as migrations da Fase 3 aplicadas.',
   '[{"ordem":1,"acao":"Rodar a rotina qa_caso_cult_090 (somente leitura)","resultado_esperado":"Padrão desligado nas duas colunas, 29/02 vira 28/02 em ano comum e o índice cultura_acoes_chave_unica_uidx existe"}]'::jsonb,
   'Os padrões seguros da automação estão presentes.', 'Rotina qa_caso_cult_090().'),

  (v_mod, 'CULT-091', 'Configurar a automação e gerar as ações agora',
   'feliz', 'alta', 'aprovado', 'e2e', NULL,
   'O RH escolhe, por tipo, se a rotina cria a ação pendente sozinha, o tom das mensagens e a meta de cobertura. O botão Gerar ações agora mostra o efeito sem esperar a rotina das 6h.',
   'Sub-aba Configuração, em Rituais e Reconhecimento. Usuário gestor ou acima.',
   '[{"ordem":1,"acao":"Em Automação, ligar Criar ação pendente sozinha para Aniversário","resultado_esperado":"Configuração salva"},
     {"ordem":2,"acao":"Clicar em Gerar ações agora","resultado_esperado":"Aviso com quantas ações foram criadas; elas aparecem com o selo Automática"},
     {"ordem":3,"acao":"Clicar de novo","resultado_esperado":"Nada novo para criar agora"}]'::jsonb,
   'A automação é configurável e gera as ações pendentes sem duplicar.',
   'Só aparece o it() da montagem; o efeito depende de colaboradores com data na janela.'),

  (v_mod, 'CULT-092', 'Rotina diária cria só ações pendentes, sem duplicar e sem expor ninguém',
   'negativo', 'critica', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'A rotina nunca conclui, nunca publica no Mural e nunca concede presente ou folga. Cria no máximo uma ação por pessoa, tipo e ano, mesmo que já exista uma ação manual do ano; ignora admissão não concluída, sem empresa, fora da janela, aniversário de quem tem menos de 1 ano de casa e tenant com a automação desligada.',
   'Colaboradores com datas dentro e fora da janela; um deles com ação manual do ano.',
   '[{"ordem":1,"acao":"Gerar ações agora","resultado_esperado":"Só as celebrações elegíveis ganham ação pendente com selo Automática"},
     {"ordem":2,"acao":"Gerar de novo","resultado_esperado":"Nenhuma ação nova"}]'::jsonb,
   'Criação automática segura e sem duplicidade.',
   'Verificada em réplica local do banco no desenvolvimento (8 cenários). Depende de dado semeado: sem it() de tela.'),

  (v_mod, 'CULT-093', 'Mensagem sugerida pela Íris, editável, sem idade',
   'feliz', 'media', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'No painel Hoje, o ícone de mensagem abre um texto sugerido no tom configurado (leve ou formal). O texto nunca traz idade nem ano de nascimento, pode ser editado, trocado por outra sugestão, copiado ou publicado no Mural pelo usuário. Quem pediu reconhecimento reservado não pode ser publicado.',
   'Uma celebração de hoje.',
   '[{"ordem":1,"acao":"Clicar no ícone de mensagem de uma celebração","resultado_esperado":"Texto sugerido editável"},
     {"ordem":2,"acao":"Clicar em Publicar no Mural","resultado_esperado":"Post publicado e a ação mostra Publicada no Mural"},
     {"ordem":3,"acao":"Repetir para um colaborador reservado","resultado_esperado":"Publicar fica desabilitado, com aviso"}]'::jsonb,
   'A sugestão é só ponto de partida e a preferência é respeitada.',
   'Depende de dado semeado: sem it() de tela; texto e alertas cobertos por vitest.'),

  (v_mod, 'CULT-094', 'Alertas levam ao Plano de Ação',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Medir sem agir não muda nada. Ações atrasadas e cobertura abaixo da meta aparecem em Alertas; cada alerta abre a sugestão de ação do Plano de Ação. Sem alerta, a tela diz que está tudo em dia.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Conferir o card Alertas","resultado_esperado":"Lista os alertas, ou informa que não há nenhum"},
     {"ordem":2,"acao":"Clicar em Criar ação no Plano de Ação","resultado_esperado":"Abre a sugestão de ações com origem Cultura"}]'::jsonb,
   'O alerta fecha o ciclo medir e agir.', NULL)
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-091', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra as opções de automação na Configuração'),
  ('CULT-094', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o painel de alertas')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
