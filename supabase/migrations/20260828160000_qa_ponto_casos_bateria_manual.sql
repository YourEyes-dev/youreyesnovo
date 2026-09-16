-- =========================================================
-- QA PONTO — casos derivados do confronto com a "Bateria Legal do Ponto"
-- (roteiro manual de 113 casos em 13 famílias, A..M, para execução por
-- uma pessoa no ambiente de teste).
--
-- MÉTODO: os 113 casos do roteiro foram cruzados um a um com os 128 já
-- documentados (famílias PONTO e ESC). ~88% tinha caso equivalente. Este
-- arquivo documenta as 14 lacunas reais encontradas. Ficaram DE FORA,
-- deliberadamente:
--   - ~8 casos de cadastro puro (criar escala 5x2/6x1/noturna, atribuir
--     escala, configurar regime, cadastrar CCT/acordo): caminho feliz de
--     CRUD, matéria de tela;
--   - F7 (reflexo da HE no DSR), que tem dono no FOLHA-022.
--
-- LACUNAS DOCUMENTADAS AQUI (referência ao caso do roteiro):
--   D7 saída antecipada ................. PONTO-400
--   D6 extra sem truncamento ............ PONTO-401
--   F4 feriado não trabalhado ........... PONTO-402
--   B3 colaborador sem escala ........... PONTO-403
--   E8 batida real vence a declaração ... PONTO-410
--   H3 regime exige acordo .............. PONTO-420
--   H10 compensar com folga ............. PONTO-421
--   I2 ajuste sem justificativa ......... PONTO-430
--   K8 remontar dossiê não duplica ...... PONTO-431
--   L2 CCT vencida/a vencer ............. PONTO-440
--   L3 CCTs com vigências sobrepostas ... PONTO-441
--   M1 motor de vigilâncias completo .... PONTO-450
--   M2 vigilância não duplica alerta .... PONTO-451
--   C7 tentativas em série no link ...... PONTO-460
--
-- Rotinas na migration seguinte (mesma entrega).
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo jornada-rotina/ponto não encontrado.'; END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ APURAÇÃO DO DIA ══════════

  (v_mod, 'PONTO-400', 'Saída antecipada é identificada como tal, com os minutos',
   'alternativo', 'media', 'aprovado', 'api',
   'CLT art. 58 (duração da jornada) c/c art. 462 (desconto só do efetivamente devido)',
   'Sair antes do fim da jornada não é a mesma coisa que chegar atrasado, e o espelho precisa dizer qual foi: o dia recebe o selo de saída antecipada com os minutos, e o saldo fica negativo na diferença exata. Sem a distinção, o colaborador não sabe o que contestar e o gestor não sabe o que conversar — e o desconto vira número sem história.',
   'Colaborador com escala de jornada até 17h no ambiente de teste.',
   '[{"ordem":1,"acao":"Lançar saída às 16:00 num dia de jornada até 17:00","resultado_esperado":"Dia marcado como saída antecipada, com os minutos apurados"},
     {"ordem":2,"acao":"Conferir o saldo do dia","resultado_esperado":"Negativo exatamente na diferença — nem arredondado, nem tratado como falta"},
     {"ordem":3,"acao":"Comparar com um atraso equivalente","resultado_esperado":"Os dois aparecem com rótulos distintos no espelho"}]'::jsonb,
   'Sair cedo e chegar tarde são coisas diferentes — o espelho sabe qual foi.',
   'Roteiro manual "Bateria Legal do Ponto", caso D7. O atraso tem coluna própria (ponto_diario.atraso_minutos); a saída antecipada, não — a sonda confere.'),

  (v_mod, 'PONTO-401', 'Hora extra sai em minutos exatos, sem truncar nem arredondar',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT art. 59 (remuneração da hora suplementar); Súmula 449 do TST (minutos residuais não podem ser suprimidos)',
   'Depois da tolerância legal, cada minuto de excesso é devido: 2h37 de excedente aparecem como 2h37, não como 2h30 nem 3h. Arredondamento sistemático para baixo é supressão de hora extra em escala industrial (multiplicada por todo o quadro, todo mês); para cima, é custo criado sem fato gerador.',
   'Colaborador com jornada até 17h e tolerância padrão no ambiente de teste.',
   '[{"ordem":1,"acao":"Lançar saída às 19:37 (2h37 além da jornada)","resultado_esperado":"Excedente de 157 minutos apurado integralmente"},
     {"ordem":2,"acao":"Conferir o relatório de horas extras","resultado_esperado":"Mesmo valor em minutos exatos, sem arredondamento de fração"},
     {"ordem":3,"acao":"Repetir com excedente de 1 minuto além da tolerância","resultado_esperado":"O minuto aparece — não é engolido"}]'::jsonb,
   'Minuto trabalhado é minuto pago — sem régua enviesada para nenhum lado.',
   'Roteiro manual, caso D6. O adicional de 50% é o PONTO-090; aqui a cobrança é a PRECISÃO do excedente. Complementa PONTO-040/353 (tolerância e teto).'),

  (v_mod, 'PONTO-402', 'Feriado não trabalhado é dia neutro: sem falta e sem débito',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 605/1949, art. 1º (repouso em feriados civis e religiosos, sem prejuízo da remuneração)',
   'A contraprova do "dia útil sem marcação é falta": no feriado, a ausência de marcação é o esperado — o dia aparece identificado como feriado, sem falta, sem débito de jornada e sem afetar o DSR da semana. Feriado tratado como falta desconta salário e derruba o repouso de quem não devia nada.',
   'Feriado cadastrado na competência de teste, abrangendo a unidade do colaborador.',
   '[{"ordem":1,"acao":"Abrir o espelho do dia de feriado sem marcações","resultado_esperado":"Dia identificado como feriado, sem falta e sem débito"},
     {"ordem":2,"acao":"Conferir o DSR da semana","resultado_esperado":"Preservado — o feriado não é ausência injustificada"},
     {"ordem":3,"acao":"Conferir o total da competência","resultado_esperado":"Jornada prevista do mês desconta o feriado, sem saldo negativo artificial"}]'::jsonb,
   'No feriado, não bater ponto é o certo — e o sistema entende assim.',
   'Roteiro manual, caso F4. O oposto (dia útil sem marcação = falta) é o PONTO-023/290; o feriado TRABALHADO é o PONTO-320/321. ponto_diario tem tipo_dia e feriado_nome — a sonda confere o dia neutro.'),

  (v_mod, 'PONTO-403', 'Colaborador sem escala vigente: dia sem jornada prevista e pendência de cadastro',
   'alternativo', 'media', 'aprovado', 'api',
   'Portaria MTP 671/2021 (registro de jornada) c/c CLT art. 74',
   'Escala é pré-requisito da apuração: sem escala vigente, não há jornada prevista contra a qual medir saldo. O comportamento correto é contar o tempo trabalhado, NÃO inventar saldo (nem crédito, nem falta) e listar o colaborador nas pendências de cadastro — apurar contra uma jornada suposta de 8h é criar hora extra ou falta que ninguém deve.',
   'Colaborador batendo ponto sem atribuição de escala vigente no ambiente de teste.',
   '[{"ordem":1,"acao":"Registrar marcações de um colaborador sem escala atribuída","resultado_esperado":"Marcações aceitas normalmente"},
     {"ordem":2,"acao":"Abrir o espelho do dia","resultado_esperado":"Total trabalhado contado; sem jornada prevista e sem saldo apurado contra padrão suposto"},
     {"ordem":3,"acao":"Conferir as pendências","resultado_esperado":"Colaborador apontado como pendência de cadastro (escala ausente)"}]'::jsonb,
   'Sem escala não há régua — e régua inventada vira passivo.',
   'Roteiro manual, caso B3. Complementa PONTO-091 (jornada real da escala, não 8h fixas): aqui o caso é a AUSÊNCIA de escala.'),

  -- ══════════ INTERVALO ══════════

  (v_mod, 'PONTO-410', 'Batida real de intervalo vence a pré-assinalação declarada',
   'alternativo', 'alta', 'aprovado', 'api',
   'Súmula 338, III, do TST (a prova pré-constituída cede diante da marcação real); CLT art. 74, §2º',
   'Quando existe declaração de intervalo (pré-assinalação) E o colaborador bateu o almoço, prevalece o que foi BATIDO: o dia consta como intervalo marcado, sem o selo de pré-assinalado, e o cálculo usa o tempo real. A declaração é presunção; a marcação é fato — e presunção que vence fato é exatamente o que a súmula afasta em juízo.',
   'Escala com pré-assinalação de intervalo vigente no ambiente de teste.',
   '[{"ordem":1,"acao":"Lançar dia com almoço batido (08:00, 12:00, 13:00, 17:00)","resultado_esperado":"Intervalo consta como MARCADO, não como pré-assinalado"},
     {"ordem":2,"acao":"Conferir o cálculo do dia","resultado_esperado":"Usa o intervalo real batido, não o declarado na escala"},
     {"ordem":3,"acao":"Lançar outro dia só com entrada e saída","resultado_esperado":"Aí sim a pré-assinalação se aplica, com o selo correspondente"}]'::jsonb,
   'O que foi batido manda; o declarado só preenche o silêncio.',
   'Roteiro manual, caso E8. A pré-assinalação em si é o PONTO-064 e a supressão total é o PONTO-061; aqui a cobrança é a PRECEDÊNCIA. ponto_diario tem intervalo_origem — a sonda confere se ele reflete a batida real.'),

  -- ══════════ BANCO DE HORAS ══════════

  (v_mod, 'PONTO-420', 'Regime que exige acordo não credita banco enquanto o acordo não está anexado',
   'negativo', 'alta', 'aprovado', 'api',
   'CLT art. 59, §5º (banco de horas por acordo individual escrito) e §2º (por convenção ou acordo coletivo)',
   'A própria configuração do banco declara que exige acordo individual (ou CCT/ACT). Com a exigência ligada e nenhum acordo vinculado, o excedente NÃO pode ser creditado: crédito sem instrumento é compensação inválida — na reclamatória, todas as horas viram extras pagas com adicional, com o banco servindo apenas de prova contra a empresa.',
   'Configuração de banco com "exige acordo individual" ligada e sem acordo vinculado.',
   '[{"ordem":1,"acao":"Lançar um dia com excedente e apurar","resultado_esperado":"O banco não credita — a exigência declarada não está satisfeita"},
     {"ordem":2,"acao":"Conferir o destino do excedente","resultado_esperado":"Segue como hora extra a pagar, com a memória do porquê"},
     {"ordem":3,"acao":"Anexar o acordo e reapurar","resultado_esperado":"A partir daí o crédito ocorre normalmente"}]'::jsonb,
   'Banco sem acordo assinado não é banco — é hora extra represada.',
   'Roteiro manual, caso H3. O instrumento VIGENTE é o PONTO-170; aqui a cobrança é a coerência com a flag exige_acordo_individual/exige_cct_act da própria configuração (lida hoje por ponto_banco_regime_vigente).'),

  (v_mod, 'PONTO-421', 'Folga compensatória debita o saldo do banco e o dia não vira falta',
   'feliz', 'alta', 'aprovado', 'api',
   'CLT art. 59, §2º (compensação de horas mediante folga)',
   'Compensar é o propósito do banco: concedida a folga, o extrato mostra o DÉBITO contra o saldo positivo e o dia de folga NÃO vira falta nem gera desconto. Se o débito não acontece, a empresa paga duas vezes (dá a folga e mantém o saldo); se o dia vira falta, desconta de quem estava compensando — e ainda derruba o DSR da semana.',
   'Colaborador com saldo positivo de banco de horas no ambiente de teste.',
   '[{"ordem":1,"acao":"Lançar uma folga compensatória","resultado_esperado":"Dia identificado como folga compensatória, sem falta e sem desconto"},
     {"ordem":2,"acao":"Conferir o extrato do banco","resultado_esperado":"Débito correspondente às horas da folga, com o saldo atualizado"},
     {"ordem":3,"acao":"Conferir o DSR da semana","resultado_esperado":"Preservado — folga compensatória não é ausência injustificada"}]'::jsonb,
   'A folga que compensa precisa sair do saldo — e nunca virar falta.',
   'Roteiro manual, caso H10. A folga compensatória de FERIADO é o PONTO-321 (afasta a dobra); aqui é a compensação de saldo do banco. Complementa PONTO-171 (saldo vencido vira HE).'),

  -- ══════════ AJUSTES E DOSSIÊ ══════════

  (v_mod, 'PONTO-430', 'Ajuste de ponto sem justificativa é recusado',
   'negativo', 'alta', 'aprovado', 'api',
   'Portaria MTP 671/2021, art. 74 e ss. (alterações de marcação devem ser identificadas e motivadas); CLT art. 74',
   'Toda alteração de marcação precisa dizer POR QUÊ: pedido de ajuste com motivo vazio (ou apenas um caractere para enganar a validação) não pode ser enviado. Sem motivo registrado, a trilha de auditoria vira lista de mudanças sem história — e na fiscalização, marcação alterada sem justificativa é indício de manipulação do controle de jornada.',
   'Fluxo de solicitação de ajuste operante no ambiente de teste.',
   '[{"ordem":1,"acao":"Solicitar ajuste com justificativa vazia","resultado_esperado":"Recusado — a justificativa é obrigatória"},
     {"ordem":2,"acao":"Solicitar com justificativa mínima (um caractere)","resultado_esperado":"Recusado — motivo precisa ser inteligível, não formalidade"},
     {"ordem":3,"acao":"Solicitar com motivo real","resultado_esperado":"Aceito, com o motivo visível na trilha e para o aprovador"}]'::jsonb,
   'Mudar o ponto exige dizer por quê — em palavras, não em espaço em branco.',
   'Roteiro manual, caso I2. A alçada de aprovação é o PONTO-252 e a preservação da original é o PONTO-190/340; aqui é a obrigatoriedade do motivo (ponto_ajustes.motivo é NOT NULL — a sonda confere se string vazia/curta também é barrada).'),

  (v_mod, 'PONTO-431', 'Remontar o dossiê de fiscalização não cria um segundo dossiê',
   'negativo', 'media', 'aprovado', 'api',
   'Portaria MTP 671/2021 (documentação do controle de jornada apresentada à fiscalização)',
   'O dossiê da competência é peça única: mandar montar de novo (porque o primeiro saiu incompleto, ou por hábito) deve ATUALIZAR o dossiê existente, não empilhar cópias. Dois dossiês da mesma competência com conteúdos diferentes é o pior cenário na fiscalização — a empresa apresenta um e o auditor encontra o outro.',
   'Dossiê de fiscalização já montado para a competência no ambiente de teste.',
   '[{"ordem":1,"acao":"Montar o dossiê da competência","resultado_esperado":"Dossiê gerado com índice e hash do pacote"},
     {"ordem":2,"acao":"Mandar montar de novo","resultado_esperado":"Continua havendo UM dossiê da competência, com data e hash atualizados"},
     {"ordem":3,"acao":"Listar os dossiês","resultado_esperado":"Sem duplicata; histórico de versões preservado se houver"}]'::jsonb,
   'Um dossiê por competência — remontar atualiza, não multiplica.',
   'Roteiro manual, caso K8. A geração íntegra e assinada é o PONTO-392; aqui é a reentrância. ponto_dossies_fiscalizacao não tem UNIQUE por competência — a sonda confere.'),

  -- ══════════ INSTRUMENTO COLETIVO ══════════

  (v_mod, 'PONTO-440', 'Instrumento coletivo vencido ou a vencer é avisado antes de faltar parâmetro',
   'alternativo', 'alta', 'aprovado', 'api',
   'CF art. 7º, XXVI (reconhecimento das convenções e acordos coletivos); CLT art. 611-A e ss.',
   'A CCT vence e leva junto os parâmetros da apuração (percentuais de HE, adicional noturno, intervalo, banco). O sistema avisa com antecedência que o instrumento está para vencer — e com severidade maior quando já venceu, porque a competência seguinte fica sem parâmetro coletivo e passa a apurar pela regra geral sem ninguém decidir isso.',
   'Instrumento coletivo cadastrado com vigência terminando em poucos dias.',
   '[{"ordem":1,"acao":"Cadastrar CCT vencendo em 10 dias e rodar a vigilância","resultado_esperado":"Alerta de vencimento do instrumento coletivo, com prazo"},
     {"ordem":2,"acao":"Deixar a vigência terminar","resultado_esperado":"Alerta com severidade maior — a competência seguinte está descoberta"},
     {"ordem":3,"acao":"Registrar a renovação","resultado_esperado":"Alerta encerrado; nova vigência passa a reger a apuração"}]'::jsonb,
   'Convenção vencida é apuração sem régua — o aviso vem antes do vencimento.',
   'Roteiro manual, caso L2. O uso do instrumento vigente NA COMPETÊNCIA é o PONTO-386; aqui é o ciclo de vida do instrumento.'),

  (v_mod, 'PONTO-441', 'Dois instrumentos coletivos com vigências sobrepostas são acusados',
   'negativo', 'alta', 'aprovado', 'api',
   'CF art. 7º, XXVI; CLT art. 620 (prevalência entre instrumentos)',
   'Duas CCTs ativas do mesmo escopo cobrindo a mesma data deixam a apuração AMBÍGUA: qual percentual de hora extra vale? Qual intervalo? O sistema precisa acusar a sobreposição em vez de escolher em silêncio (pelo id, pela data de cadastro, pelo acaso do ORDER BY) — porque a escolha silenciosa só aparece quando o sindicato questiona a folha inteira.',
   'Dois instrumentos coletivos ativos do mesmo escopo com vigências que se cruzam.',
   '[{"ordem":1,"acao":"Cadastrar duas CCTs do mesmo escopo cobrindo a mesma data","resultado_esperado":"Sobreposição acusada — bloqueio ou alerta de alta severidade"},
     {"ordem":2,"acao":"Apurar uma competência na janela sobreposta","resultado_esperado":"Ambiguidade sinalizada; não escolhe em silêncio"},
     {"ordem":3,"acao":"Encerrar a vigência do instrumento anterior","resultado_esperado":"Alerta encerrado; apuração volta a ter um único instrumento"}]'::jsonb,
   'Dois instrumentos válidos ao mesmo tempo é um a menos — o sistema pergunta qual.',
   'Roteiro manual, caso L3. Complementa PONTO-386/440. Mesmo desenho do FER-003 (unidade em duas tabelas de feriados).'),

  -- ══════════ MOTOR DE VIGILÂNCIAS ══════════

  (v_mod, 'PONTO-450', 'O motor de vigilâncias diárias roda inteiro, agendado, sem erro',
   'feliz', 'critica', 'aprovado', 'api',
   'Portaria MTP 671/2021 e CLT art. 74 (controle efetivo da jornada) — a prevenção depende de a rotina rodar',
   'As vigilâncias do ponto (banco de horas, art. 62, porte do estabelecimento, instrumento coletivo, formalização de escala, cobertura de turno, certificado e prazo de 48h do comprovante) precisam rodar TODAS, de forma agendada e sem erro. Vigilância que existe mas não é chamada por nenhum agendamento é alerta que nunca chega — o painel fica limpo por omissão, não por conformidade.',
   'Ambiente de teste com dados que disparem ao menos uma vigilância.',
   '[{"ordem":1,"acao":"Conferir o agendamento diário da rotina","resultado_esperado":"Job ativo, com horário definido"},
     {"ordem":2,"acao":"Executar a rotina completa","resultado_esperado":"Todas as vigilâncias respondem, cada uma com o que encontrou — sem erro e sem faltar nenhuma"},
     {"ordem":3,"acao":"Conferir os alertas gerados","resultado_esperado":"Cada achado com tipo, severidade e vínculo ao colaborador/empresa"}]'::jsonb,
   'Vigilância que ninguém chama é alerta que nunca chega.',
   'Roteiro manual, caso M1 (que descreve uma rotina orquestradora com 8 vigilâncias, agendada). Hoje as vigilâncias existem SOLTAS (ponto_banco_alertas_monitorar, ponto_cct_vigiar_vigencia, ponto_certificado_vigiar_vencimento, ponto_comprovante_vigiar_48h, ponto_escala_formalizacao_monitorar, cobertura...) — a sonda confere a orquestração e o agendamento.'),

  (v_mod, 'PONTO-451', 'Vigilância rodada duas vezes não duplica o alerta',
   'negativo', 'alta', 'aprovado', 'api',
   'Boa prática de idempotência aplicada ao dever de vigilância (CLT art. 74; Portaria MTP 671/2021)',
   'A rotina roda de madrugada, e alguém pode rodá-la de novo à tarde para conferir. A segunda execução não pode duplicar alertas: o painel precisa mostrar UM alerta por ocorrência, senão o DP aprende a ignorar a lista (e o alerta que importa se perde no meio das cópias). É a mesma regra que a casa já aplica na materialização de faltas.',
   'Cenário que gere alerta (certificado a vencer, saldo perto do prazo) no ambiente de teste.',
   '[{"ordem":1,"acao":"Rodar a vigilância uma vez","resultado_esperado":"Alerta criado"},
     {"ordem":2,"acao":"Rodar de novo em seguida","resultado_esperado":"Nenhum alerta novo — a segunda execução não cria nada"},
     {"ordem":3,"acao":"Conferir o painel","resultado_esperado":"Um único alerta da ocorrência, com a data da primeira detecção"}]'::jsonb,
   'Rodar duas vezes não pode gerar dois avisos do mesmo problema.',
   'Roteiro manual, caso M2. Mesmo princípio do PONTO-292 (materializar duas vezes não duplica o dia) e do EPI/NF. ponto_alertas não tem UNIQUE de deduplicação — a sonda confere se as rotinas se protegem.'),

  -- ══════════ LINK DE MARCAÇÃO ══════════

  (v_mod, 'PONTO-460', 'Tentativas em série no link de marcação são contidas e registradas',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD arts. 46-48 (medidas de segurança e prevenção de acessos indevidos); Portaria MTP 671/2021 (integridade do registro)',
   'O link externo de marcação é porta aberta na internet: sem contenção, permite varrer CPFs até acertar um válido (e marcar ponto por outra pessoa). Após poucas tentativas frustradas, o link precisa bloquear temporariamente, orientar procurar o RH e registrar o evento na trilha — e liberar quem é legítimo assim que o bloqueio expira, sem exigir intervenção do DP.',
   'Link de marcação ativo no ambiente de teste.',
   '[{"ordem":1,"acao":"Informar cinco CPFs inválidos em sequência","resultado_esperado":"Bloqueio temporário anunciado, com orientação de procurar o RH"},
     {"ordem":2,"acao":"Conferir a trilha","resultado_esperado":"Tentativas frustradas e o bloqueio registrados"},
     {"ordem":3,"acao":"Passado o bloqueio, usar um CPF válido","resultado_esperado":"Marcação normal — quem é legítimo não fica preso"}]'::jsonb,
   'Porta na internet precisa de tranca que cansa quem tenta adivinhar.',
   'Roteiro manual, caso C7. Complementa PONTO-362 (enumeração de CPFs) e PONTO-251 (expiração/revogação). ponto_links tem tentativas_frustradas e bloqueado_ate — a sonda confere se são aplicados.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'PONTO (bateria manual): casos antes=%, depois=% (esperado +14 na primeira execução).', v_antes, v_depois;
END $doc$;

-- ── Referências cruzadas (sem duplicar cobertura) ──
DO $xref$
BEGIN
  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: o oposto (feriado não trabalhado como dia neutro) é o PONTO-402; a ausência de escala é o PONTO-403.'
  WHERE codigo IN ('PONTO-023','PONTO-290') AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: a precedência da batida real sobre a declaração é o PONTO-410.'
  WHERE codigo = 'PONTO-064' AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: a coerência com a flag de exigência de acordo da própria configuração é o PONTO-420; a compensação por folga é o PONTO-421.'
  WHERE codigo = 'PONTO-170' AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: o ciclo de vida do instrumento (vencimento e sobreposição) é o PONTO-440/441.'
  WHERE codigo = 'PONTO-386' AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: a reentrância (remontar não duplica) é o PONTO-431.'
  WHERE codigo = 'PONTO-392' AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: a contenção de tentativas em série no link é o PONTO-460.'
  WHERE codigo IN ('PONTO-251','PONTO-362') AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  UPDATE public.qa_casos_teste SET observacoes = coalesce(observacoes,'') ||
    ' | Bateria manual: a precisão do excedente em minutos exatos é o PONTO-401; a saída antecipada é o PONTO-400.'
  WHERE codigo = 'PONTO-090' AND position('Bateria manual' IN coalesce(observacoes,'')) = 0;

  RAISE NOTICE 'Referências cruzadas da bateria manual registradas.';
END $xref$;
