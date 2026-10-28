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
