-- Script de entrega — Cultura & Celebrações: dia da profissão por cargo (IA sugere, pessoa aprova).
-- Cole no SQL Editor do projeto de PRODUÇÃO. Idempotente.
-- Cria UMA tabela nova (cultura_dias_profissao) com RLS por empresa, uma rotina de QA e casos de QA.
-- A tabela é criada por EXECUTE dentro de um bloco DO (o auxiliar de RLS automática do SQL Editor
-- injeta comandos no corpo das funções quando enxerga a criação de tabela escrita direto).
-- Antes de atualizar o texto do caso CULT-002, guarda a cópia dele.
-- Desfazer o texto: UPDATE public.qa_casos_teste q SET objetivo=b.objetivo
--   FROM backup_qa_cultura5_20261018 b WHERE b.id=q.id;
-- ORDEM DE ENTREGA: 1) este script  2) publicar a função ai-cultura-dia-profissao  3) publicar as telas.

SET lock_timeout = '10s';

DO $bk$
BEGIN
  IF to_regclass('public.backup_qa_cultura5_20261018') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.backup_qa_cultura5_20261018 AS SELECT * FROM public.qa_casos_teste WHERE codigo = ''CULT-002''';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'backup: %', SQLERRM;
END $bk$;

DO $tab$
BEGIN
  IF to_regclass('public.cultura_dias_profissao') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.cultura_dias_profissao (
      id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
      tenant_id uuid NOT NULL REFERENCES public.tenants(id),
      cargo_chave text NOT NULL,
      cargo_exemplo text NOT NULL,
      nome_data text,
      mes integer,
      dia integer,
      status text NOT NULL DEFAULT ''aprovado'',
      origem text NOT NULL DEFAULT ''ia'',
      confianca text,
      base text,
      criado_por uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT cultura_dias_profissao_status_chk CHECK (status IN (''aprovado'', ''rejeitado'')),
      CONSTRAINT cultura_dias_profissao_origem_chk CHECK (origem IN (''ia'', ''manual'')),
      CONSTRAINT cultura_dias_profissao_data_chk CHECK (
        status = ''rejeitado''
        OR (nome_data IS NOT NULL AND mes BETWEEN 1 AND 12 AND dia BETWEEN 1 AND 31)),
      CONSTRAINT cultura_dias_profissao_unico UNIQUE (tenant_id, cargo_chave)
    )';
  END IF;
END $tab$;

ALTER TABLE public.cultura_dias_profissao ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant isolation" ON public.cultura_dias_profissao;
CREATE POLICY "Tenant isolation" ON public.cultura_dias_profissao
  FOR ALL TO authenticated
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.cultura_dias_profissao TO authenticated;

-- QA (nivel api): estrutura e isolamento da tabela de decisoes
CREATE OR REPLACE FUNCTION public.qa_caso_cult_097()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_existe boolean;
  v_rls boolean;
  v_politica boolean;
  v_unico boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) a tabela de dias de profissão por cargo';
  r.esperado    := 'Tabela existe, com RLS ligado, política de isolamento por empresa e um registro por cargo';

  v_existe := (to_regclass('public.cultura_dias_profissao') IS NOT NULL);
  v_rls := COALESCE((SELECT c.relrowsecurity FROM pg_class c
                     WHERE c.oid = to_regclass('public.cultura_dias_profissao')), false);
  v_politica := EXISTS (SELECT 1 FROM pg_policies
                        WHERE schemaname = 'public' AND tablename = 'cultura_dias_profissao'
                          AND qual LIKE '%get_user_tenant_id%' AND with_check LIKE '%get_user_tenant_id%');
  v_unico := EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conname = 'cultura_dias_profissao_unico' AND contype = 'u');

  IF v_existe AND v_rls AND v_politica AND v_unico THEN
    r.situacao := 'passou';
    r.obtido   := 'Tabela com RLS, política por empresa e unicidade por cargo.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('tabela=%s; RLS=%s; política por empresa=%s; único por cargo=%s', v_existe, v_rls, v_politica, v_unico);
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
    objetivo = 'O card Próximas Celebrações puxa aniversários, tempo de casa e dia da profissão dos colaboradores ativos da empresa. Só entram os tipos ligados na Configuração e a janela de dias é a configurada (padrão 30 sem configuração salva). Tempo de casa mostra os anos da data celebrada, não do ano corrente. O dia da profissão vem das decisões da empresa (sugeridas pela IA e aprovadas, ou manuais) e, sem decisão, do catálogo padrão; cargo marcado como sem dia não é celebrado.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-002';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-097', 'Decisões de dia da profissão isoladas por empresa',
   'negativo', 'alta', 'aprovado', 'api', NULL,
   'As decisões sobre o dia da profissão de cada cargo são da empresa: não podem vazar para outra e cada cargo tem uma única decisão.',
   'Banco com a migration aplicada.',
   '[{"ordem":1,"acao":"Rodar a rotina qa_caso_cult_097 (somente leitura)","resultado_esperado":"Tabela com RLS ligado, política por empresa (leitura e escrita) e unicidade por cargo"}]'::jsonb,
   'A tabela de decisões está isolada por empresa.', 'Rotina qa_caso_cult_097().'),

  (v_mod, 'CULT-098', 'Aba Dias da Profissão com análise de cargos por IA',
   'feliz', 'media', 'aprovado', 'e2e', NULL,
   'Em Rituais e Reconhecimento há a aba Dias da Profissão, com o botão Analisar cargos com IA, o resumo de cargos (na empresa, cobertos pelo catálogo padrão, definidos, para analisar) e a lista do que a empresa já definiu.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"Abrir Rituais e Reconhecimento e a aba Dias da Profissão","resultado_esperado":"Resumo de cargos, botão Analisar cargos com IA e a lista Definidos pela empresa"}]'::jsonb,
   'A aba monta com o botão de análise por IA.', 'O it() confere só a montagem; a chamada à IA depende de chave e de cargos cadastrados.'),

  (v_mod, 'CULT-099', 'IA sugere o dia da profissão e uma pessoa aprova',
   'feliz', 'critica', 'aprovado', 'e2e', NULL,
   'A IA lê os nomes dos cargos (nunca dados de colaboradores) e sugere o dia comemorativo de cada profissão, com confiança e base. Nada vale sem aprovação: a pessoa confere nome, dia e mês e aprova ou descarta. Data impossível devolvida pela IA é descartada; cargo sem data garantida vai para Sem dia comemorativo conhecido; cargo descartado não é analisado de novo e deixa de ser celebrado, mesmo que o catálogo padrão casasse. Aprovado, o dia aparece em Próximas Celebrações e no calendário.',
   'Cargos cadastrados e chave da IA configurada na função.',
   '[{"ordem":1,"acao":"Clicar em Analisar cargos com IA","resultado_esperado":"Lista de sugestões com cargo, profissão, confiança, base e data editável"},
     {"ordem":2,"acao":"Corrigir uma data e aprovar","resultado_esperado":"Entra em Definidos pela empresa como IA aprovada"},
     {"ordem":3,"acao":"Descartar outra sugestão","resultado_esperado":"Entra como sem dia da profissão e não é sugerida de novo"},
     {"ordem":4,"acao":"Conferir o calendário no mês da data aprovada","resultado_esperado":"O dia da profissão aparece"}]'::jsonb,
   'Só entra no calendário o que uma pessoa aprovou.',
   'Depende de chamada real à IA: sem it() de tela. Validação da resposta e catálogo cobertos por vitest.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-098', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra a aba Dias da Profissão com a análise de cargos por IA')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;

SELECT 'tabela' AS item, count(*)::text AS valor FROM pg_tables WHERE schemaname = 'public' AND tablename = 'cultura_dias_profissao'
UNION ALL SELECT 'rls_ligado', count(*)::text FROM pg_class WHERE oid = to_regclass('public.cultura_dias_profissao') AND relrowsecurity
UNION ALL SELECT 'politicas', count(*)::text FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cultura_dias_profissao'
UNION ALL SELECT 'rotina_qa', count(*)::text FROM pg_proc WHERE proname = 'qa_caso_cult_097'
UNION ALL SELECT 'casos_qa', count(*)::text FROM public.qa_casos_teste WHERE codigo IN ('CULT-097','CULT-098','CULT-099');
