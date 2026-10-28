-- ============================================================================
-- ENTREGA — QA: casos DOCS-TELA-10, COLAB-TELA-10 e RECON-TELA-01/02/03
-- (colaborador desligado: pasta visível em Documentos, editar cadastro,
--  recontratar com novo vínculo e histórico de vínculos)
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO (já aplicado no
-- teste pela esteira). Só DOCUMENTA casos de teste; não altera comportamento nem
-- dado de cliente, não cria tabela nem função. UMA transação, idempotente
-- (ON CONFLICT atualiza). Pode rodar antes ou depois de publicar as telas.
-- ============================================================================

-- Documentos: a pasta de um colaborador DESLIGADO deve continuar visível na
-- árvore do módulo Documentos. O módulo é a evidência de todos que passaram pela
-- empresa (guarda legal: FGTS, eSocial, PCMSO por anos) — nunca pode ocultar pasta.
-- Antes, a árvore (useDocumentoPastas) validava a pasta contra a lista de ATIVOS
-- (RPC colaboradores_diretorio, que filtra status='concluido'), derrubando todo
-- desligado. Corrigido no front: o conjunto válido passa a incluir TODAS as
-- admissões da empresa (qualquer status), mantendo o filtro de empresa.
-- Documenta o caso e2e DOCS-TELA-10. Idempotente. Não cria tabela nem função.

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'documentos-governanca/documentos';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo documentos-governanca/documentos ausente; DOCS-TELA-10 não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DOCS-TELA-10',
   'Pasta de colaborador desligado continua visível na árvore de Documentos',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Guarda de documentos trabalhistas após o desligamento: FGTS (prescrição 5 anos, STF ARE 709212; guarda prática até 30 anos), PCMSO/ASO 20 anos (NR-7; 40 anos para expostos a cancerígenos), PPP 20 anos. LGPD art. 7º II e art. 16 I: retenção para cumprimento de obrigação legal.',
   'Garantir que o módulo Documentos nunca oculte a pasta de quem foi desligado — o módulo existe como evidência de TODOS que passaram pela empresa.',
   'Empresa com ao menos um colaborador desligado que possui pasta de documentos.',
   '[{"ordem":1,"acao":"Abrir o módulo Documentos","resultado_esperado":"Árvore de pastas carrega"},
     {"ordem":2,"acao":"Localizar a pasta do colaborador desligado","resultado_esperado":"A pasta do desligado aparece na árvore, com suas subpastas (Admissão, Vida Funcional, Saúde Ocupacional, Desligamento)"}]'::jsonb,
   'A pasta do colaborador desligado permanece na árvore (não é ocultada); só pastas de OUTRA empresa continuam barradas.',
   'Correção no front (useDocumentoPastas): conjunto de colaboradores válidos passa a incluir ativos + desligados da empresa. Ainda sem it() automatizado (depende de seed de desligado com pasta no staging).')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'DOCS-TELA-10 documentado (e2e).';
END
$doc$;

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

-- Recontratação (modelo PESSOA + N VÍNCULOS) e histórico de vínculos.
-- Recontratar quem foi desligado é um NOVO vínculo (novo contrato), nunca a
-- reativação do anterior: a CLT trata como novo contrato e o eSocial exige um
-- novo S-2200 com matrícula NOVA (a matrícula não é reutilizável); o S-2299 do
-- vínculo anterior fica intacto. O produto reaproveita os dados da PESSOA (CPF),
-- abre um novo vínculo e preserva o desligamento anterior, gerando o histórico
-- de períodos/funções para auditoria. Alertas de compliance: <90 dias de uma
-- dispensa sem justa causa (presunção de fraude FGTS/seguro-desemprego,
-- Portaria MTb 384/92 → risco de unicidade contratual) e seguro-desemprego.
-- Documenta os casos e2e RECON-TELA-01/02/03. Idempotente. Não cria tabela/função.

DO $doc$
DECLARE
  v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
   WHERE path = 'estrutura-organizacional/colaboradores';

  IF v_mod IS NULL THEN
    RAISE NOTICE 'Módulo estrutura-organizacional/colaboradores ausente; RECON-TELA-* não documentado.';
    RETURN;
  END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'RECON-TELA-01',
   'Recontratar gera um novo vínculo e preserva o desligamento anterior',
   'feliz', 'alta', 'aprovado', 'e2e',
   'CLT: recontratação é novo contrato (o anterior foi extinto pela rescisão; reativar só em reintegração). eSocial: novo S-2200 com matrícula NOVA; o S-2299 anterior permanece. Modelo pessoa + N vínculos.',
   'Garantir que recontratar reaproveite os dados da pessoa, crie um NOVO vínculo (nova admissão, status concluído) e NÃO altere o registro desligado anterior.',
   'Empresa com um colaborador desligado; usuário com permissão de cadastrar colaboradores.',
   '[{"ordem":1,"acao":"Colaboradores > Desligados > botão Recontratar","resultado_esperado":"Abre o cadastro em modo Recontratar, pré-preenchido com os dados da pessoa, data de admissão de hoje e matrícula em branco"},
     {"ordem":2,"acao":"Confirmar o novo cadastro","resultado_esperado":"Surge um NOVO colaborador ativo com o mesmo CPF; o registro anterior continua na aba Desligados (status inalterado)"}]'::jsonb,
   'A pessoa passa a ter dois vínculos (um desligado, um ativo); o desligamento anterior é preservado; a matrícula do novo vínculo é nova.',
   'Reaproveita o ColaboradorForm em modo novo (INSERT) com prop recontratarDe. Sem it() automatizado ainda (depende de seed no staging).'),
  (v_mod, 'RECON-TELA-02',
   'Alerta de recontratação em menos de 90 dias de dispensa sem justa causa',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Portaria MTb 384/92: recontratar em menos de 90 dias um empregado dispensado sem justa causa presume fraude ao FGTS/seguro-desemprego; risco de a Justiça reconhecer unicidade contratual. Seguro-desemprego é cancelado na recontratação.',
   'Avisar o RH, sem bloquear, quando a recontratação ocorre a menos de 90 dias do desligamento anterior sem justa causa (ou rescisão indireta/acordo mútuo).',
   'Colaborador desligado há menos de 90 dias, motivo dispensa sem justa causa.',
   '[{"ordem":1,"acao":"Recontratar esse colaborador","resultado_esperado":"O cadastro mostra um aviso âmbar sobre os 90 dias e o seguro-desemprego, sem impedir o cadastro"}]'::jsonb,
   'O aviso aparece (não bloqueia). Para pedido de demissão / justa causa, o aviso de 90 dias não aparece.',
   'Cálculo no ColaboradorForm (avisosRecontratacao) a partir de dataDesligamento e motivoDesligamento.'),
  (v_mod, 'RECON-TELA-03',
   'Histórico de vínculos lista todos os períodos da pessoa',
   'feliz', 'media', 'aprovado', 'e2e',
   'Auditoria e guarda de documentos trabalhistas: a empresa precisa comprovar os períodos de trabalho de cada pessoa (tempo de casa, funções).',
   'Mostrar, por pessoa (CPF), a linha do tempo dos vínculos: cargo, período (admissão → desligamento) e motivo de saída.',
   'Pessoa com um ou mais vínculos na empresa.',
   '[{"ordem":1,"acao":"Colaboradores > Desligados > botão Histórico de vínculos","resultado_esperado":"Abre a linha do tempo com cada vínculo (cargo, datas, status e motivo)"}]'::jsonb,
   'Todos os vínculos do mesmo CPF aparecem, do mais recente ao mais antigo, sem duplicar cadastro da pessoa.',
   'HistoricoVinculosDialog consulta admissoes por cpf (tenant/empresa). Sem it() automatizado ainda.')
  ON CONFLICT (codigo) DO UPDATE SET
     modulo_id = EXCLUDED.modulo_id, titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo,
     prioridade = EXCLUDED.prioridade, status = EXCLUDED.status, nivel = EXCLUDED.nivel,
     base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo,
     pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
     resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  RAISE NOTICE 'RECON-TELA-01/02/03 documentados (e2e).';
END
$doc$;


-- Conferência final (o editor mostra só este resultado):
SELECT
  (SELECT count(*) FROM public.qa_casos_teste
    WHERE codigo IN ('DOCS-TELA-10','COLAB-TELA-10','RECON-TELA-01','RECON-TELA-02','RECON-TELA-03')) AS casos_documentados_deve_ser_5,
  NULL::text AS erro_tecnico;

-- Para desfazer:
--   DELETE FROM public.qa_casos_teste
--    WHERE codigo IN ('DOCS-TELA-10','COLAB-TELA-10','RECON-TELA-01','RECON-TELA-02','RECON-TELA-03');
