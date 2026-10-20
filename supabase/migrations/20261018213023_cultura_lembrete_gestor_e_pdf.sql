-- =========================================================
-- Cultura & Celebrações — lembrete ao gestor e calendário em PDF
--
-- Coluna cultura_config.lembrar_gestor (nasce DESLIGADA), rotina de QA
-- qa_caso_cult_090 ampliada e a documentação de testes (CULT-095, CULT-096).
-- Idempotente.
-- =========================================================

SET lock_timeout = '10s';

-- 1) Lembrete ao gestor: desligado por padrao (o RH liga na Configuracao)
ALTER TABLE public.cultura_config
  ADD COLUMN IF NOT EXISTS lembrar_gestor boolean NOT NULL DEFAULT false;

-- 2) QA (nivel api): passa a conferir tambem que o lembrete ao gestor nasce desligado
CREATE OR REPLACE FUNCTION public.qa_caso_cult_090()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_padrao_ok boolean;
  v_bissexto boolean;
  v_indice boolean;
  v_gestor_ok boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Conferir (somente leitura) os padrões seguros da automação de Cultura';
  r.esperado    := 'Automação e lembrete ao gestor nascem desligados, 29/02 cai em 28/02 em ano comum e há índice único de celebração';

  v_padrao_ok := (SELECT count(*) = 2 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name IN ('automacao_aniversario', 'automacao_tempo_casa')
                    AND column_default LIKE '%desligado%');
  v_gestor_ok := (SELECT count(*) = 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'cultura_config'
                    AND column_name = 'lembrar_gestor'
                    AND column_default LIKE '%false%');
  v_bissexto := (public.cultura_data_no_ano(2, 29, 2026) = DATE '2026-02-28'
                 AND public.cultura_data_no_ano(2, 29, 2028) = DATE '2028-02-29'
                 AND public.cultura_data_no_ano(3, 10, 2026) = DATE '2026-03-10');
  v_indice := EXISTS (SELECT 1 FROM pg_indexes
                      WHERE schemaname = 'public' AND indexname = 'cultura_acoes_chave_unica_uidx');

  IF v_padrao_ok AND v_gestor_ok AND v_bissexto AND v_indice THEN
    r.situacao := 'passou';
    r.obtido   := 'Padrões desligados, regra de 29/02 e índice único presentes.';
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('automação desligada=%s; lembrete gestor desligado=%s; 29/02=%s; índice único=%s',
                         v_padrao_ok, v_gestor_ok, v_bissexto, v_indice);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $fn$;

-- 3) Documentacao de testes
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'pessoas-cultura/cultura-celebracoes' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo pessoas-cultura/cultura-celebracoes não encontrado; nada a fazer.';
    RETURN;
  END IF;

  UPDATE public.qa_casos_teste SET
    objetivo = 'O RH precisa enxergar o mês e o ano: onde há concentração de datas e onde faltam rituais. O calendário mostra os mesmos itens da lista de próximas celebrações, mais ações, datas configuradas e rituais, com filtro por Pessoas, Datas e Rituais. Na visão Mês, o botão Baixar PDF gera o calendário do mês (CULT-096).'
  WHERE modulo_id = v_mod AND codigo = 'CULT-081';

  UPDATE public.qa_casos_teste SET
    objetivo = 'A automação e o lembrete ao gestor nascem desligados em todo cliente. O CULT-090 confere os padrões seguros: automação desligada, lembrete ao gestor desligado, 29/02 tratado e índice único de celebração.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-090';

  UPDATE public.qa_casos_teste SET
    objetivo = 'O RH escolhe, por tipo, se a rotina cria a ação pendente sozinha, o tom das mensagens, a meta de cobertura e se os gestores são lembrados no Mural. O botão Gerar ações agora mostra o efeito sem esperar a rotina das 6h.'
  WHERE modulo_id = v_mod AND codigo = 'CULT-091';

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'CULT-095', 'Lembrete ao gestor mostra só as celebrações do próprio time',
   'feliz', 'alta', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Com Lembrar os gestores ligado na Configuração, o gestor vê no Mural o card Seu time com as celebrações de quem ele gerencia dentro da janela de dias, e um toque abre a mensagem sugerida. O time vem do cadastro: gestor imediato com o nome do gestor, ou departamento em que ele é gestor (ou substituto com a substituição ativa). Ninguém é gestor de si mesmo e quem não tem time não vê o card. Quem pediu reconhecimento reservado aparece com o selo e não pode ser publicado.',
   'Lembrar os gestores ligado; colaborador com data na janela e gestor cadastrado.',
   '[{"ordem":1,"acao":"Entrar como gestor de um colaborador com aniversário próximo e abrir o Mural","resultado_esperado":"Card Seu time com o colaborador, o tipo e os dias que faltam"},
     {"ordem":2,"acao":"Clicar no ícone de mensagem","resultado_esperado":"Texto sugerido editável; publicar no Mural só para quem não é reservado"},
     {"ordem":3,"acao":"Entrar como outra pessoa sem time","resultado_esperado":"O card não aparece"}]'::jsonb,
   'O gestor é lembrado só do próprio time.',
   'Depende de dado semeado (gestor e colaborador com datas); sem it() de tela. Regras auxiliares cobertas por vitest. Desligado, o card não existe.'),

  (v_mod, 'CULT-096', 'Baixar o calendário do mês em PDF',
   'feliz', 'media', 'aprovado', 'e2e', 'LGPD art. 6º (dado pessoal)',
   'Na visão Mês do calendário, Baixar PDF gera um arquivo A4 paisagem com a grade do mês (até 3 itens por dia) e uma página de detalhamento com todos os itens e a situação das ações. Respeita o filtro ativo, mostra só dia e mês (nunca idade ou ano de nascimento) e deixa de fora quem pediu reconhecimento reservado, com aviso no rodapé, porque o papel circula.',
   'Usuário autenticado com acesso ao módulo.',
   '[{"ordem":1,"acao":"No calendário, na visão Mês, clicar em Baixar PDF","resultado_esperado":"Arquivo calendario-celebracoes-AAAA-MM.pdf com a grade e o detalhamento"},
     {"ordem":2,"acao":"Mudar o filtro (ex.: Rituais) e baixar de novo","resultado_esperado":"O PDF traz só o grupo filtrado, com o filtro no cabeçalho"},
     {"ordem":3,"acao":"Alternar para a visão Ano","resultado_esperado":"O botão Baixar PDF não aparece"}]'::jsonb,
   'O PDF do mês é gerado e respeita filtro e preferência reservada.',
   'O it() confere o botão; o conteúdo do PDF é coberto por vitest (semanas, células, rodapé, 2 páginas).')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste
FROM (VALUES
  ('CULT-096', 'cypress/e2e/cultura-celebracoes.cy.ts', 'mostra o botão de baixar o PDF do calendário')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
