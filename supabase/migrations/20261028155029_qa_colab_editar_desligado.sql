-- Colaboradores: permitir EDITAR o cadastro de um colaborador desligado.
-- Antes, o botão de editar só existia na aba Ativos; a aba Desligados não tinha
-- ponto de entrada (não havia trava de status — só faltava o botão). Correções
-- de dado cadastral acontecem depois do desligamento (ajustar e-mail, cargo,
-- matrícula etc.), então o RH precisa editar quem já saiu. A edição reaproveita
-- o mesmo formulário dos ativos e NÃO altera o status (não reativa o desligado).
-- Documenta o caso e2e COLAB-TELA-10. Idempotente. Não cria tabela nem função.

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'estrutura-organizacional/colaboradores';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo estrutura-organizacional/colaboradores ausente; COLAB-TELA-10 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'COLAB-TELA-10',
   'Editar cadastro de colaborador desligado (aba Desligados)',
   'feliz', 'media', 'aprovado', 'e2e',
   'Correção de dados cadastrais de ex-empregado é rotina de DP (ex.: atualizar contato, matrícula eSocial, cargo histórico) e não pode depender de o colaborador estar ativo.',
   'Permitir que o RH edite o cadastro de quem já foi desligado, sem reativá-lo.',
   'Empresa com ao menos um colaborador desligado; usuário com permissão de editar colaboradores.',
   '[{"ordem":1,"acao":"Abrir Colaboradores > aba Desligados","resultado_esperado":"Lista de desligados com botão de editar (lápis) em cada linha"},
     {"ordem":2,"acao":"Clicar em editar, alterar um campo (ex.: e-mail) e salvar","resultado_esperado":"O dado é salvo e o colaborador PERMANECE desligado (status inalterado)"}]'::jsonb,
   'A edição salva os dados cadastrais e mantém o status ''desligado'' — não reativa o colaborador nem o move para a aba Ativos.',
   'Reaproveita o ColaboradorForm dos ativos; o payload de edição não inclui status. Ainda sem it() automatizado (depende de seed de desligado no staging).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'COLAB-TELA-10 documentado (e2e).';
END
$doc$;
