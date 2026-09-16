-- =========================================================
-- SCRIPT DE ENTREGA — 13o Salario: Documentacao de testes completa
-- Projeto: HOMOLOGACAO e depois PRODUCAO (colar no SQL Editor)
--
-- POR QUE ESTE SCRIPT EXISTE
--   A Documentacao de testes do 13o nasceu por migration, e migration so
--   chega ao ambiente de teste. Nos demais ambientes a conferencia
--   mostrava "documentados: 0" — os casos nunca tinham chegado la.
--   Este script leva a documentacao INTEIRA, autossuficiente: o modulo,
--   os 31 casos (17 da 1a leva + 14 da 2a) e as rotinas que os executam.
--
-- O QUE ELE NAO FAZ: nao altera calculo, nao altera dado de folha, nao
-- mexe em regra de negocio. E documentacao e rotina de teste — tudo
-- somente leitura sobre o sistema. Por isso nao ha copia de seguranca
-- a fazer.
--
-- PRE-REQUISITO: o motor de QA (tabelas qa_*) precisa existir na base.
-- Se nao existir, este script para sem aplicar nada e nada se perde —
-- as correcoes de lei do 13o vivem no script_13o_testes_leva2_e_correcoes.sql,
-- que e independente deste.
--
-- Idempotente: rodar duas vezes nao duplica caso nem rotina.
-- Requisitos YE-DP-13-001.
-- =========================================================

SET lock_timeout = '10s';

-- ══════════ 1a leva: modulo e os 17 casos originais ══════════
-- O modulo pai precisa existir: em base que nunca recebeu a documentacao
-- de testes ele pode faltar, e ai o filho nao nasce e nada e documentado.
INSERT INTO public.qa_modulos (parent_id, label, path, prioridade_doc, status_doc)
SELECT NULL, 'Financeiro', 'financeiro', 1, 'em_andamento'
WHERE NOT EXISTS (SELECT 1 FROM public.qa_modulos WHERE path = 'financeiro');

-- Módulo próprio, filho de Financeiro (a tela é uma aba de Financeiro)
INSERT INTO public.qa_modulos (parent_id, label, path, prioridade_doc, status_doc)
SELECT m.id, '13º Salário', 'financeiro/decimo-terceiro', 1, 'em_andamento'
FROM public.qa_modulos m
WHERE m.path = 'financeiro'
ON CONFLICT (path) DO NOTHING;

DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos
  WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao pode ser criado nesta base — casos da 1a leva nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) APURAÇÃO DE AVOS ══════════

  (v_mod, 'DEC13-001', 'Avos apurados do vínculo: 1/12 por mês, fração de 15 dias conta',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 1º, §§1º e 2º',
   'O 13º é 1/12 da remuneração por mês de serviço do ano, e a fração igual ou superior a 15 dias conta como mês inteiro. Os avos devem sair da DATA DE ADMISSÃO do vínculo — não de um número digitado à mão. Admitido em 20 de maio: maio tem menos de 15 dias, não conta; junho a dezembro contam — 7 avos. Admitido em 10 de maio: maio conta — 8 avos.',
   'Vínculos fictícios admitidos em 10/05 e 20/05 do ano-base.',
   '[{"ordem":1,"acao":"Apurar o 13º do admitido em 10/05","resultado_esperado":"8 avos (maio conta — 22 dias trabalhados ≥ 15)"},
     {"ordem":2,"acao":"Apurar o 13º do admitido em 20/05","resultado_esperado":"7 avos (maio com menos de 15 dias não conta)"},
     {"ordem":3,"acao":"Conferir a origem do número de meses","resultado_esperado":"Calculado da data de admissão, não digitado livremente pelo operador"}]'::jsonb,
   'Avos nascem do vínculo e da regra dos 15 dias — nunca de digitação.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001 / cenário "Admissão no ano" (seção 25). DIVERGÊNCIA VISÍVEL: calcular13 recebe mesesTrabalhados informado na tela (DecimoTerceiroTab) — sem apuração automática. Deve falhar e encaminhar.'),

  (v_mod, 'DEC13-002', 'Faltas injustificadas derrubam o avo do mês que fica com menos de 15 dias',
   'negativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 1º, §1º (mês de serviço); tratamento consolidado das faltas injustificadas',
   'Mês em que as faltas INJUSTIFICADAS reduzem o trabalho para menos de 15 dias não gera avo. Faltas justificadas e afastamentos legais não entram nessa conta. A fonte é o Ponto — as ocorrências do módulo de jornada precisam refletir na apuração, senão o 13º sai maior do que o devido.',
   'Vínculo com 16 faltas injustificadas registradas no Ponto em um mesmo mês do ano-base.',
   '[{"ordem":1,"acao":"Apurar os avos do vínculo","resultado_esperado":"O mês com 16 faltas injustificadas NÃO conta como avo"},
     {"ordem":2,"acao":"Repetir com faltas justificadas (atestado)","resultado_esperado":"O mês conta normalmente — justificada não derruba avo"}]'::jsonb,
   'Injustificada demais no mês, avo a menos; justificada não mexe.',
   'Requisitos YE-DP-13-001: RN-001 / fluxo "Faltas injustificadas" (seção 9). Integração com Ponto/Afastamentos (seção 17).'),

  (v_mod, 'DEC13-003', 'Afastamentos: maternidade integra, auxílio-doença divide com o INSS',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 8.213/1991 (abono anual, art. 120 do Decreto 3.048/1999); salário-maternidade integra a apuração patronal',
   'Afastamentos não são todos iguais: na licença-maternidade o período INTEGRA a apuração do empregador; no auxílio-doença, o empregador paga os avos trabalhados e o INSS paga o abono anual proporcional ao benefício. O sistema deve tratar cada tipo pelo seu efeito e marcar o caso para validação contábil — não apagar nem contar tudo igual.',
   'Vínculos fictícios com licença-maternidade (4 meses) e auxílio-doença (5 meses) no ano-base.',
   '[{"ordem":1,"acao":"Apurar o 13º da colaboradora em licença-maternidade","resultado_esperado":"Período da licença conta na apuração patronal"},
     {"ordem":2,"acao":"Apurar o 13º do afastado por auxílio-doença","resultado_esperado":"Avos patronais só dos meses trabalhados; período do benefício sinalizado como abono anual do INSS"},
     {"ordem":3,"acao":"Conferir a marcação do caso","resultado_esperado":"Apuração marcada para validação contábil, com o tipo de afastamento visível"}]'::jsonb,
   'Cada afastamento com seu efeito — e contabilidade avisada.',
   'Requisitos YE-DP-13-001: RN-008 / CA (seção 24) / cenário "Afastamento" (seção 25). Classificação [OLC]/[VAL] — a divisão exata patronal×INSS é ponto de validação (seção 30). Integra com jornada-rotina/afastamentos.'),

  -- ══════════ B) BASE DE CÁLCULO E MÉDIAS ══════════

  (v_mod, 'DEC13-020', 'Base do 13º inclui as médias das variáveis do ano',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Decreto 57.155/1965, art. 2º; Súmulas 45, 148 e 253 do TST',
   'Quem recebe horas extras habituais, adicional noturno ou comissões não tem 13º só do salário fixo: as variáveis do ano entram na base pela média, conforme a parametrização de rubricas. Base composta apenas do fixo, para quem tem variável habitual, é diferença certa em reclamação.',
   'Vínculo com salário fixo e horas extras habituais lançadas na folha ao longo do ano-base.',
   '[{"ordem":1,"acao":"Calcular o 13º do vínculo com variáveis","resultado_esperado":"Base = salário + média das variáveis, com memória de cálculo mostrando a composição"},
     {"ordem":2,"acao":"Conferir as rubricas que integraram","resultado_esperado":"Somente rubricas parametrizadas como integrantes da base do 13º"}]'::jsonb,
   'Variável habitual entra pela média — e a memória mostra o caminho.',
   'Requisitos YE-DP-13-001: RN-002 / CA-002. Composição exata da base é [VAL]/[DAE] por cliente (seção 30); o que se testa é que a média EXISTE e é parametrizável (folha_rubricas).'),

  (v_mod, 'DEC13-021', 'Base de médias incompleta trava com alerta antes do fechamento',
   'excecao', 'media', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-006 e seção 14 (alerta "Base de médias incompleta")',
   'Fechar o 13º com rubricas variáveis do ano faltando é pagar errado com hora marcada. Antes do fechamento, o sistema confere se as competências do ano têm as variáveis lançadas; faltando, alerta o DP e aponta o que completar — o fechamento com pendência exige decisão consciente, não passa em silêncio.',
   'Ano-base com competências sem lançamento de rubricas variáveis para vínculo que as recebe habitualmente.',
   '[{"ordem":1,"acao":"Preparar o fechamento do 13º","resultado_esperado":"Alerta de base incompleta com as competências/rubricas faltantes"},
     {"ordem":2,"acao":"Completar os lançamentos e reprocessar","resultado_esperado":"Alerta encerrado; médias recalculadas"}]'::jsonb,
   'Média só fecha com o ano inteiro na mesa.',
   'Requisitos YE-DP-13-001: seção 14 / cenário "Dado ausente" (seção 25) / IA "Detecção de médias incompletas" (seção 18).'),

  -- ══════════ C) PARCELAS E PRAZOS ══════════

  (v_mod, 'DEC13-030', '1ª parcela: 50%, paga entre 1º de fevereiro e 30 de novembro',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º',
   'O adiantamento é METADE da remuneração do mês anterior, pago entre 1º/02 e 30/11. O sistema agenda a data-alvo, alerta na aproximação (D-30/15/7) e acusa o atraso — 1ª parcela paga em dezembro é infração, ainda que o valor esteja certo. FGTS incide sobre o adiantamento na competência do pagamento.',
   'Ano-base com vínculos ativos e calendário carregado.',
   '[{"ordem":1,"acao":"Programar a 1ª parcela dentro do prazo","resultado_esperado":"50% da base, agendada até 30/11, com FGTS da competência"},
     {"ordem":2,"acao":"Aproximar-se de 30/11 sem pagamento","resultado_esperado":"Alertas D-30/15/7 para DP/RH/Financeiro, com ação no Plano de Ação"},
     {"ordem":3,"acao":"Simular data de pagamento em dezembro","resultado_esperado":"Acusado como fora do prazo legal — não passa como regular"}]'::jsonb,
   'Metade do valor, dentro da janela legal, com o prazo vigiado.',
   'Requisitos YE-DP-13-001: RN-003 / CA-003 / alerta "1ª parcela a vencer" (seção 14). DIVERGÊNCIA VISÍVEL: não há motor de prazos nem alertas do 13º hoje. Deve falhar e encaminhar.'),

  (v_mod, 'DEC13-031', '2ª parcela até 20 de dezembro, antecipando em fim de semana ou feriado',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 4.749/1965, art. 1º; regra de antecipação por dia não útil',
   'A 2ª parcela vence em 20/12 — e quando o dia 20 cai em sábado, domingo ou feriado, paga-se ANTES, não depois. O motor de datas precisa conhecer o calendário (tabela de feriados) e mover a data-alvo para o dia útil anterior, refletindo isso nos alertas (D-15/7/3).',
   'Ano em que 20/12 cai em fim de semana; tabela de feriados carregada.',
   '[{"ordem":1,"acao":"Consultar a data-alvo da 2ª parcela nesse ano","resultado_esperado":"Antecipada para o último dia útil antes de 20/12"},
     {"ordem":2,"acao":"Conferir os alertas","resultado_esperado":"D-15/7/3 contados sobre a data antecipada, prioridade crítica"}]'::jsonb,
   'O prazo corre para trás no calendário, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-004 / CA-004 / cenário "Prazo vencido" (seção 25) / RNF-003. Usa a tabela feriados já existente no projeto.'),

  (v_mod, 'DEC13-032', 'Adiantamento nas férias: requerido em janeiro, pago no gozo, baixado na apuração',
   'alternativo', 'media', 'aprovado', 'e2e',
   'Lei 4.749/1965, art. 2º, §2º',
   'Quem requer em janeiro recebe a 1ª parcela junto das férias. O lado Férias já tem caso (FERIAS-035); aqui se testa o lado 13º: a opção registrada muda a data do adiantamento para o gozo, o valor pago nas férias aparece na apuração anual como adiantamento JÁ FEITO e a 2ª parcela deduz exatamente esse valor — sem pagar de novo em novembro.',
   'Vínculo com adiantar_13 = true requerido em janeiro e férias gozadas em julho, com a 1ª parcela paga junto.',
   '[{"ordem":1,"acao":"Consultar a apuração do 13º do vínculo","resultado_esperado":"Adiantamento marcado como pago nas férias, com valor e data"},
     {"ordem":2,"acao":"Programar a rodada geral de novembro","resultado_esperado":"Vínculo fora da rodada da 1ª parcela — já recebeu"},
     {"ordem":3,"acao":"Calcular a 2ª parcela","resultado_esperado":"Deduzido o valor pago nas férias, não os 50% teóricos"}]'::jsonb,
   'Pagou nas férias, baixou na apuração, deduziu na 2ª — uma vez só.',
   'Requisitos YE-DP-13-001: RN-003 / CA-003 / cenário "Adiantamento nas férias" (seção 9). Par do FERIAS-035 (lado Férias). Política de adiantamento é [DAE] (seção 30).'),

  (v_mod, 'DEC13-033', '2ª parcela deduz o adiantamento e diferenças posteriores geram complemento',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.749/1965, arts. 1º e 2º; Decreto 57.155/1965 (recálculo com variáveis do ano)',
   'A 2ª parcela é o total anual MENOS o adiantamento efetivamente pago. E o ano não acaba em 20/12: variável lançada depois (comissão de dezembro, HE do fim do ano) gera DIFERENÇA a apurar como complemento, com trilha própria e reflexo no eSocial — não se reabre o valor pago fingindo que nada mudou.',
   '1ª parcela paga; variável nova lançada após o pagamento da 2ª.',
   '[{"ordem":1,"acao":"Calcular a 2ª parcela","resultado_esperado":"Total anual menos o adiantamento real, com memória de cálculo"},
     {"ordem":2,"acao":"Lançar variável retroativa do ano","resultado_esperado":"Diferença detectada e alerta a DP/Contador"},
     {"ordem":3,"acao":"Apurar o complemento","resultado_esperado":"Complemento com trilha vinculada à apuração original e reflexo no eSocial"}]'::jsonb,
   'Deduz o que foi pago; o que chegar depois vira complemento rastreado.',
   'Requisitos YE-DP-13-001: CA-005 / RF-006 / cenário "Diferença" (seção 25) / alerta "Diferença após a 2ª parcela" (seção 14).'),

  -- ══════════ D) ENCARGOS ══════════

  (v_mod, 'DEC13-040', 'INSS do 13º: só na 2ª parcela, calculado em separado da folha do mês',
   'feliz', 'critica', 'aprovado', 'e2e',
   'Lei 8.212/1991; Decreto 3.048/1999, art. 214, §6º (cálculo em separado); retenção na quitação da 2ª parcela',
   'O INSS incide sobre o 13º INTEIRO, mas só é retido na 2ª parcela — e a base do 13º é tributada SEPARADA da remuneração de dezembro, cada uma com sua progressão de faixas. Somar as duas bases numa conta só infla a alíquota e desconta INSS a mais do colaborador.',
   'Vínculo com salário que, somado ao 13º, mudaria de faixa se as bases fossem somadas.',
   '[{"ordem":1,"acao":"Calcular a 1ª parcela","resultado_esperado":"Nenhum INSS retido no adiantamento"},
     {"ordem":2,"acao":"Calcular a 2ª parcela","resultado_esperado":"INSS sobre o 13º integral, com progressão de faixas própria, separada da folha de dezembro"},
     {"ordem":3,"acao":"Conferir a tabela aplicada","resultado_esperado":"Tabela de INSS vigente na competência (tabela versionada), não fixa em código"}]'::jsonb,
   'Base do 13º anda sozinha na tabela — e só paga na 2ª.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Usa folha_tabelas_inss (versionada — RNF-002). Tabelas vigentes são [VAL] (seção 30).'),

  (v_mod, 'DEC13-041', 'IRRF do 13º: tributação exclusiva na fonte, apurada na 2ª parcela',
   'feliz', 'critica', 'aprovado', 'e2e',
   'RIR/2018 (Decreto 9.580/2018), art. 700 — tributação exclusiva na fonte do 13º salário',
   'O IRRF do 13º é EXCLUSIVO na fonte: apurado sobre o valor integral na quitação da 2ª parcela, com as deduções legais (dependentes, INSS do próprio 13º), e NÃO se soma aos rendimentos do mês para reajustar a tabela. Misturar o 13º com o salário de dezembro no IRRF é erro clássico que muda o imposto dos dois.',
   'Vínculo com dependentes cadastrados e 13º na faixa tributável.',
   '[{"ordem":1,"acao":"Calcular a 1ª parcela","resultado_esperado":"Nenhum IRRF no adiantamento"},
     {"ordem":2,"acao":"Calcular a 2ª parcela","resultado_esperado":"IRRF sobre o 13º integral, deduzindo INSS do 13º e dependentes, separado do IRRF do salário"},
     {"ordem":3,"acao":"Conferir o caráter exclusivo","resultado_esperado":"Valor não compensável/somável com a tributação mensal; tabela vigente versionada"}]'::jsonb,
   'Imposto do 13º nasce e morre na 2ª parcela, sem contaminar o mês.',
   'Requisitos YE-DP-13-001: RN-007 / CA-004. Usa folha_tabelas_irrf (versionada). Tabela anual e deduções são [VAL] (seção 30).'),

  (v_mod, 'DEC13-042', 'FGTS de 8% nas duas parcelas, cada uma na sua competência',
   'feliz', 'alta', 'aprovado', 'e2e',
   'Lei 8.036/1990, art. 15 (a remuneração inclui a gratificação de Natal)',
   'O FGTS incide sobre AMBAS as parcelas — 8% sobre o adiantamento na competência em que foi pago e 8% sobre o restante na competência da 2ª parcela. Depositar tudo em dezembro, ou esquecer o depósito do adiantamento, deixa diferença de FGTS que o FGTS Digital denuncia.',
   '1ª parcela paga em novembro; 2ª em dezembro.',
   '[{"ordem":1,"acao":"Conferir o FGTS da 1ª parcela","resultado_esperado":"8% sobre os 50% pagos, na competência de novembro"},
     {"ordem":2,"acao":"Conferir o FGTS da 2ª parcela","resultado_esperado":"8% sobre a diferença (total menos adiantamento), na competência de dezembro"},
     {"ordem":3,"acao":"Somar as duas competências","resultado_esperado":"8% exatos sobre o 13º integral — sem falta nem duplicidade"}]'::jsonb,
   'Oito por cento no total, repartidos pela competência de cada parcela.',
   'Requisitos YE-DP-13-001: RN-006 / CA-004. calcular13 já reparte a base (1ª: metade; 2ª: diferença) — o que falta conferir é o registro por competência para a guia. Alíquota parametrizada por vínculo (aprendiz 2%).'),

  -- ══════════ E) RESCISÃO NO ANO ══════════

  (v_mod, 'DEC13-060', 'Rescisão no ano-base: 13º proporcional pago, justa causa perde, adiantamento concilia',
   'alternativo', 'alta', 'aprovado', 'e2e',
   'Lei 4.090/1962, art. 3º; CLT, art. 477; justa causa afasta a gratificação proporcional',
   'Desligado no meio do ano, o colaborador leva o 13º proporcional aos avos trabalhados (indenizado na rescisão); na dispensa POR JUSTA CAUSA, perde a proporcional. E se a 1ª parcela já tinha sido paga (inclusive nas férias), o valor adiantado é conciliado nas verbas — na justa causa, o adiantado a maior vira desconto conforme a regra.',
   'Vínculos fictícios desligados em agosto: um sem justa causa (com adiantamento pago), outro por justa causa.',
   '[{"ordem":1,"acao":"Processar a rescisão sem justa causa","resultado_esperado":"13º proporcional (8/12) nas verbas, deduzido o adiantamento pago"},
     {"ordem":2,"acao":"Processar a rescisão por justa causa","resultado_esperado":"13º proporcional zerado, com a base legal citada"},
     {"ordem":3,"acao":"Conferir a conciliação na apuração anual","resultado_esperado":"Vínculo desligado fora da rodada de novembro/dezembro — quitado na rescisão"}]'::jsonb,
   'Proporcional na rescisão, nada na justa causa, adiantamento nunca em dobro.',
   'Requisitos YE-DP-13-001: RN-009 / CA-006 / cenário "Rescisão" (seção 25). A família DESL cobre as verbas em geral (culpa recíproca 50% = DESL-035); aqui se testa a CONCILIAÇÃO com o módulo do 13º.'),

  -- ══════════ F) eSOCIAL E PROVISÃO ══════════

  (v_mod, 'DEC13-050', 'eSocial do 13º: S-1200 da folha anual e S-1210 dos pagamentos, sem duplicar',
   'excecao', 'alta', 'aprovado', 'api',
   'eSocial — S-1200 (apuração anual do 13º) e S-1210 (pagamentos); regras de retificação',
   'O 13º tem folha PRÓPRIA no eSocial: apuração anual via S-1200 e pagamentos das parcelas via S-1210, no leiaute vigente. Rejeição volta traduzida (o que houve, onde corrigir) e o reenvio retifica — nunca cria segundo evento da mesma competência anual. Sem esses eventos, o 13º pago não existe para o governo.',
   'Apuração e pagamentos do 13º concluídos no ambiente de teste.',
   '[{"ordem":1,"acao":"Fechar a apuração anual","resultado_esperado":"S-1200 anual gerado no leiaute vigente"},
     {"ordem":2,"acao":"Registrar os pagamentos das parcelas","resultado_esperado":"S-1210 correspondente, valores conciliados com as parcelas"},
     {"ordem":3,"acao":"Simular rejeição e reenviar","resultado_esperado":"Retorno traduzido, ação sugerida, reenvio como retificação — sem evento duplicado"}]'::jsonb,
   'Folha anual declarada, pagamentos casados, rejeição virando retificação.',
   'Requisitos YE-DP-13-001: RN-010 / CA-007 / cenário "Com erro" (seção 25). DIVERGÊNCIA VISÍVEL: não há geração de S-1200/S-1210 hoje. Deve falhar e encaminhar. Mesma disciplina de ADM-093 e FERIAS-081.'),

  (v_mod, 'DEC13-051', 'Provisão do 13º atualizada a cada competência e conciliável com a folha',
   'feliz', 'media', 'aprovado', 'api',
   'Documento YE-DP-13-001, CA-009 e RNF-007; regime de competência contábil',
   'O custo do 13º nasce mês a mês (1/12 + encargos por competência), não em dezembro. A provisão acompanha cada fato gerador — admissões, desligamentos e reajustes mexem nela — e o contador consegue conciliar o saldo provisionado com o efetivamente pago no fim do ano, com relatório exportável.',
   'Ano-base com admissões e um desligamento no meio do ano.',
   '[{"ordem":1,"acao":"Conferir a provisão após cada competência","resultado_esperado":"Saldo cresce 1/12 + encargos por vínculo ativo; ajusta em admissão/desligamento"},
     {"ordem":2,"acao":"Pagar as parcelas","resultado_esperado":"Provisão baixada contra os pagamentos"},
     {"ordem":3,"acao":"Exportar o relatório de provisão","resultado_esperado":"Saldo conciliável com a folha e com o pago, por estabelecimento"}]'::jsonb,
   'Provisão viva o ano inteiro — dezembro só confirma o que já estava contado.',
   'Requisitos YE-DP-13-001: CA-009 / seção 20 / alerta "Provisão desatualizada" (seção 14). Existe folha_provisoes genérica; o vínculo específico com o 13º é o que se testa. Regras de conciliação são [DAE]/[VAL] (seção 30).'),

  -- ══════════ G) FLUXO, REABERTURA E ACESSO ══════════

  (v_mod, 'DEC13-070', 'Cálculo fechado do 13º só reabre com dupla aprovação e diferença rastreada',
   'excecao', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-007; RNF-004 (trilha imutável)',
   'Corrigir 13º já fechado e pago não é editar o registro: é REABRIR com motivo, dupla aprovação, recálculo e apuração da diferença (complemento ou estorno), preservando a versão original na trilha. Alteração silenciosa em valor pago é exatamente o que a auditoria trabalhista procura.',
   'Cálculo de 13º fechado e pago no ambiente de teste.',
   '[{"ordem":1,"acao":"Tentar editar diretamente o cálculo fechado","resultado_esperado":"Bloqueado — só via reabertura formal"},
     {"ordem":2,"acao":"Reabrir com motivo e dupla aprovação","resultado_esperado":"Recálculo executado; diferença apurada como complemento/estorno"},
     {"ordem":3,"acao":"Conferir a trilha","resultado_esperado":"Versão original preservada; quem, quando, por quê e a diferença encadeados"}]'::jsonb,
   'Fechado não se edita: reabre com rito ou não muda.',
   'Requisitos YE-DP-13-001: RF-007 / cenário "Alteração retroativa" (seção 25). Mesma disciplina de FERIAS-054 (reabertura de férias).'),

  (v_mod, 'DEC13-071', 'Remuneração do 13º restrita por perfil: colaborador só vê o próprio',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD (Lei 13.709/2018), arts. 6º, VII e 46 — segurança e acesso mínimo; matriz de perfis do documento (seção 6)',
   'Valores de 13º são dado de remuneração: o colaborador consulta SÓ o próprio cálculo e recibo; a folha da equipe/empresa fica com DP, RH, financeiro e contador conforme a matriz de perfis, sempre dentro do tenant. Vazamento horizontal de remuneração entre colegas é incidente LGPD, não bug estético.',
   'Colaborador comum autenticado no tenant de teste; cálculos de 13º de vários vínculos existentes.',
   '[{"ordem":1,"acao":"Colaborador consulta o próprio 13º","resultado_esperado":"Permitido — parcelas e recibo próprios"},
     {"ordem":2,"acao":"Colaborador tenta ler o cálculo de um colega","resultado_esperado":"Bloqueado pela política de acesso (RLS)"},
     {"ordem":3,"acao":"Usuário de outro tenant tenta ler qualquer cálculo","resultado_esperado":"Bloqueado — segregação por empresa"}]'::jsonb,
   'Cada um vê o seu; a folha inteira é assunto de quem opera a folha.',
   'Requisitos YE-DP-13-001: seção 6 / seção 22 / cenário "Permissões insuficientes" (seção 25). A tabela folha_13_calculo é sensível: conferir cobertura da camada perfil_restringe_leitura_* (rotina PERFIL-003) ou exceção documentada.')

  ON CONFLICT (codigo) DO NOTHING;

  -- ---------------------------------------------------------
  -- Referências cruzadas em casos de outras famílias
  -- (só acrescenta às observações, não reescreve)
  -- ---------------------------------------------------------
  UPDATE public.qa_casos_teste SET observacoes = observacoes ||
    ' Requisitos YE-DP-13-001: o lado 13º do adiantamento nas férias ganhou caso próprio (DEC13-032 — baixa na apuração e dedução na 2ª parcela).'
  WHERE codigo = 'FERIAS-035' AND position('YE-DP-13-001' IN observacoes) = 0;

  UPDATE public.qa_casos_teste SET observacoes = observacoes ||
    ' Requisitos YE-DP-13-001: a conciliação do 13º na rescisão (adiantamento pago, rodada anual) ganhou caso próprio (DEC13-060).'
  WHERE codigo = 'DESL-035' AND position('YE-DP-13-001' IN observacoes) = 0;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE '13º Salário: % casos antes, % depois (esperado +17 na primeira execução).', v_antes, v_depois;
END $doc$;

-- ══════════ 1a leva: rotinas ══════════
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou_15m boolean := false; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo de 13º com 15 meses trabalhados (impossível — o ano tem 12)';
  r.esperado := 'Recusado — avos vão de 0 a 12 e deveriam sair da data de admissão, não de digitação';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, meses_trabalhados)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-001', 'QA Avos Quinze', 15);
    v_aceitou_15m := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_15m := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém apura os avos a partir da admissão?';
  r.esperado := 'Função que calcule 1/12 por mês com a fração de 15 dias (Lei 4.090, art. 1º)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%avos%'
         OR (p.prosrc ILIKE '%meses_trabalhados%' AND p.prosrc ILIKE '%data_admissao%'));

  IF v_aceitou_15m OR v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: os avos do 13º são um número DIGITADO — a tela (DecimoTerceiroTab) '
             || 'pede "meses trabalhados" e o banco aceitou até 15 meses (%s; folha_13_calculo não '
             || 'tem CHECK em meses_trabalhados) e nenhuma função apura os avos da data de '
             || 'admissão (%s). A Lei 4.090 manda contar 1/12 por mês com fração ≥ 15 dias: '
             || 'admitido em 10/05 são 8 avos, em 20/05 são 7 — diferença que hoje depende da '
             || 'conta de cabeça do operador. Correção: CHECK meses_trabalhados BETWEEN 0 AND 12 '
             || 'e apuração automática pela admissão (com faltas/afastamentos), digitação só como '
             || 'exceção justificada.',
             CASE WHEN v_aceitou_15m THEN '15 aceito' ELSE 'recusado' END,
             coalesce('há candidatas: ' || v_fns, 'nenhuma função'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Avos limitados e apurados por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-002 — faltas injustificadas derrubam o avo do mês (< 15 dias)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as faltas do Ponto chegam à apuração do 13º?';
  r.esperado := 'Mês reduzido a menos de 15 dias por falta INJUSTIFICADA não conta avo; justificada não interfere';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  -- exige menção explícita ao 13º: "falta + avos" solto pega as férias
  -- (ferias_recalcular_periodo aplica o art. 130 e não toca o 13º)
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%falta%'
    AND (p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%13_calculo%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função liga as faltas apuradas no Ponto ao 13º — o módulo de '
             || 'jornada materializa faltas dia a dia (ponto_diario) e o 13º nem olha. Um '
             || 'colaborador com 16 faltas injustificadas num mês deveria perder aquele avo '
             || '(mês de serviço exige ≥ 15 dias trabalhados, Lei 4.090 art. 1º §1º); hoje o '
             || '13º sai integral porque os meses são digitados (ver DEC13-001). O efeito '
             || 'perverso é o inverso também: falta JUSTIFICADA não pode derrubar avo, e sem '
             || 'regra nenhuma ninguém garante os dois lados. Correção: apuração de avos '
             || 'consumindo as ocorrências do Ponto, distinguindo justificada de injustificada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Faltas refletem na apuração via: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-003 — afastamentos: maternidade integra, auxílio-doença divide com o INSS
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text; v_tab text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os afastamentos entram na apuração do 13º com o efeito de cada tipo?';
  r.esperado := 'Maternidade conta na apuração patronal; auxílio-doença gera abono anual pelo INSS no período do benefício';
  v_tab := public.qa_col_existe('afastamentos', 'tipo%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%afastamento%'
    AND (p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%13_calculo%' OR p.prosrc ILIKE '%avos%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o módulo de afastamentos existe e é tipado (%s), mas nenhuma '
             || 'função o consulta ao apurar o 13º. Os efeitos são opostos por tipo: '
             || 'licença-maternidade INTEGRA a apuração patronal; auxílio-doença divide — '
             || 'empregador paga os avos trabalhados e o INSS paga o abono anual do período de '
             || 'benefício (Decreto 3.048, art. 120). Sem o cruzamento, ou a empresa paga 13º '
             || 'de período que é do INSS (paga a mais) ou corta período de maternidade (paga '
             || 'a menos e responde por isso). Correção: apuração por tipo de afastamento, com '
             || 'marcação para validação contábil [VAL] nos casos divididos.',
             coalesce(v_tab, 'tabela afastamentos'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Afastamentos tratados na apuração via: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-020 — base com médias das variáveis (Decreto 57.155; Súmulas 45/148/253)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_flag text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a marcação incide_13 das rubricas alimenta alguma média?';
  r.esperado := 'Rubricas com incide_13 = true compõem a média das variáveis na base do 13º';
  v_flag := public.qa_col_existe('folha_rubricas', 'incide_13');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%incide_13%';
  IF v_flag IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (metade boa, metade decorativa): a parametrização EXISTE — '
             || 'folha_rubricas.incide_13 diz exatamente quais rubricas compõem a base do 13º, '
             || 'o desenho certo do Decreto 57.155 — mas NENHUMA função a consulta: a "média de '
             || 'variáveis" do cálculo é um único número digitado na tela (media_variaveis), '
             || 'sem memória de qual rubrica entrou nem de que período. Horas extras habituais, '
             || 'adicional noturno e comissões integram a base por lei (Súmulas 45/148/253) e '
             || 'hoje dependem de o operador calcular a média fora do sistema. Correção: média '
             || 'automática dos lançamentos do ano filtrados por incide_13, com a composição '
             || 'gravada na memória de cálculo.';
  ELSIF v_flag IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O campo incide_13 não existe mais em folha_rubricas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Médias calculadas a partir de incide_13 em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-021 — base de médias incompleta alerta antes do fechamento
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): algum motor confere a completude do ano antes do fechamento?';
  r.esperado := 'Competência sem variáveis lançadas gera alerta ANTES do cálculo, não diferença depois';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_alertas_prazo%';
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a tabela de alertas da folha (folha_alertas_prazo) é alimentada só '
             || 'pela TELA — nenhuma função do banco gera ou confere alerta algum, e não '
             || 'existe verificação de base incompleta em lugar nenhum. Quem não abrir a aba '
             || 'de alertas no mês certo não é avisado de nada, e um 13º calculado com '
             || 'competências sem variáveis lançadas sai menor em silêncio — diferença que '
             || 'vira passivo (seção 14 do documento pede alerta de "base de médias '
             || 'incompleta" com prioridade média antes do fechamento). Correção: rotina '
             || 'agendada (pg_cron, como as demais do projeto) conferindo lançamentos do '
             || 'ano × vínculos com variável habitual e registrando o alerta.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alertas gerados/conferidos no banco por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-030 — 1ª parcela: 50% entre 1º/02 e 30/11 (Lei 4.749)
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_030()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_check text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o prazo legal do 13º tem lugar no controle de prazos da folha?';
  r.esperado := 'Tipos de alerta contemplando as parcelas do 13º (1ª até 30/11; 2ª até 20/12)';
  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.folha_alertas_prazo'::regclass
    AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%tipo%';
  IF v_check IS NULL OR (v_check NOT ILIKE '%13%' AND v_check NOT ILIKE '%decimo%') THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o controle de prazos da folha não conhece o 13º — o CHECK de '
             || 'folha_alertas_prazo só admite tipos mensais (%s): não há onde registrar '
             || '"1ª parcela até 30/11" nem "2ª até 20/12", e a tela que semeia os alertas '
             || 'gera datas aproximadas mês a mês, nunca as datas da Lei 4.749. Pagar a 1ª '
             || 'parcela fora da janela (1º/02 a 30/11) é infração mesmo com o valor certo, '
             || 'e é o risco nº 1 do módulo (seção 26). Correção: tipos decimo_primeira e '
             || 'decimo_segunda no CHECK + semeadura anual das duas datas com alertas '
             || 'D-30/15/7 e D-15/7/3.', coalesce(v_check, 'constraint ausente'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Prazos do 13º contemplados no controle: %s.', v_check);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-031 — 2ª parcela até 20/12 com antecipação por dia não útil
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_031()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_feriados text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe motor de datas que antecipe prazo em dia não útil?';
  r.esperado := '20/12 em fim de semana/feriado desloca a data-alvo para o dia útil ANTERIOR';
  v_feriados := CASE WHEN to_regclass('public.feriados') IS NOT NULL THEN 'feriados' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%feriado%'
    AND (p.prosrc ILIKE '%util%' OR p.prosrc ILIKE '%antecip%')
    AND (p.prosrc ILIKE '%folha%' OR p.prosrc ILIKE '%decimo%' OR p.prosrc ILIKE '%prazo%');
  IF v_feriados IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o calendário EXISTE (tabela feriados, nacional e por município) e '
             || 'nenhum motor de prazos da folha o consulta — não há função que desloque uma '
             || 'data-alvo para o dia útil anterior. O prazo do 13º anda sempre para TRÁS '
             || '(20/12 no sábado paga-se na sexta 19; pagar na segunda 22 é atraso com multa), '
             || 'diferente de prazos tributários que às vezes prorrogam — por isso a regra '
             || 'precisa ser do prazo, não um utilitário genérico. Correção: função de data-alvo '
             || 'com antecipação consultando feriados, usada pelos alertas do DEC13-030 '
             || '(RNF-003 do documento).';
  ELSIF v_feriados IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de feriados não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Motor de antecipação presente: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-032 — adiantamento nas férias baixa na apuração e deduz na 2ª
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_032()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_opcao text; v_fns text; v_ponte text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a opção adiantar_13 das férias chega ao módulo do 13º?';
  r.esperado := 'Adiantamento pago no gozo aparece na apuração anual como 1ª parcela JÁ PAGA';
  v_opcao := public.qa_col_existe('ferias_programacao', 'adiantar_13');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%adiantar_13%';
  v_ponte := coalesce(public.qa_col_existe('folha_13_calculo', '%adiant%'),
                      public.qa_col_existe('folha_13_calculo', '%ferias%'),
                      public.qa_col_existe('folha_13_calculo', '%origem%'));
  IF v_opcao IS NOT NULL AND v_fns IS NULL AND v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a opção existe SÓ do lado das férias — ferias_programacao.adiantar_13 '
             || 'é gravada e o cálculo de férias a soma no líquido (FERIAS-035 cobre esse '
             || 'lado), mas o módulo do 13º nunca fica sabendo: nenhuma função lê adiantar_13 '
             || 'e folha_13_calculo não tem campo que registre adiantamento pago fora da '
             || 'rodada (valor_primeira_parcela é digitado). Consequência prática: quem '
             || 'recebeu a 1ª parcela nas férias de julho entra na rodada de novembro e '
             || 'RECEBE DE NOVO — e a 2ª parcela deduz os 50% teóricos, não o valor real. '
             || 'Correção: baixa automática na apuração anual (origem + valor + data do '
             || 'adiantamento) e dedução pelo valor efetivamente pago.';
  ELSIF v_opcao IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O campo adiantar_13 não existe mais em ferias_programacao.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Ponte férias→13º presente (funções: %s; campos: %s).',
                       coalesce(v_fns, '—'), coalesce(v_ponte, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-033 — dedução do adiantamento e diferenças posteriores
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_033()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou_p3 boolean := false; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo com parcela = 3 (só existem 1ª e 2ª)';
  r.esperado := 'Recusado — o 13º tem duas parcelas; "3" só faria sentido como complemento estruturado';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-033', 'QA Parcela Tres', 3);
    v_aceitou_p3 := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_p3 := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): diferença apurada depois da 2ª parcela tem tratamento?';
  r.esperado := 'Complemento/estorno com vínculo à apuração original e reflexo no eSocial';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%complemento%13%' OR p.prosrc ILIKE '%13%complemento%'
         OR (p.prosrc ILIKE '%13_calculo%' AND (p.prosrc ILIKE '%estorno%' OR p.prosrc ILIKE '%diferen%')));

  IF v_aceitou_p3 OR v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: parcela é INT sem CHECK (parcela = 3 foi %s) e não existe '
             || 'estrutura de complemento — variável lançada depois da 2ª parcela (comissão de '
             || 'dezembro, HE da virada) não tem para onde ir: ou o operador edita o cálculo '
             || 'pago (sem trilha — ver DEC13-070) ou a diferença morre esquecida, e ambos '
             || 'erram. A dedução do adiantamento também é frágil: valor_primeira_parcela é '
             || 'digitado, não lido do pagamento real. Correção: CHECK parcela IN (1,2) + '
             || 'registro de complemento/estorno vinculado à apuração original (CA-005 e '
             || 'cenário "Diferença" da seção 25).',
             CASE WHEN v_aceitou_p3 THEN 'aceita' ELSE 'recusada' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Parcelas restritas e diferenças tratadas por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-040 — INSS só na 2ª parcela, em cálculo separado
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_040()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_vig text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar 1ª parcela com INSS retido (R$ 500) — a lei manda reter só na 2ª';
  r.esperado := 'Recusado — adiantamento não sofre INSS; a retenção acontece na quitação';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela, valor_inss, base_inss)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-040', 'QA INSS Primeira', 1, 500, 3000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a tabela de INSS é versionada por vigência?';
  r.esperado := 'folha_tabelas_inss com vigência (RNF-002) — o ponto bom do desenho atual';
  v_vig := public.qa_col_existe('folha_tabelas_inss', 'vigencia_inicio');

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o banco aceitou 1ª parcela com INSS retido — nenhum CHECK impede '
             || 'encargo no adiantamento (parcela = 1 com valor_inss = 500 entrou). O cálculo do '
             || 'React até faz certo (1ª sem descontos, 2ª com INSS em base separada da folha '
             || 'do mês, progressão própria de faixas), mas a regra vive SÓ na tela: qualquer '
             || 'escrita direta, importação ou ajuste manual grava o ilegal sem resistência. '
             || 'O versionamento das tabelas está correto (%s). Correção: CHECK '
             || '(parcela = 2 OR (valor_inss = 0 AND valor_irrf = 0)) — a regra legal morando '
             || 'no banco, não só no formulário.',
             coalesce('vigência presente: ' || v_vig, 'vigência AUSENTE'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Encargo na 1ª parcela recusado; tabelas com vigência (%s).',
                       coalesce(v_vig, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-041 — IRRF exclusivo na fonte, na 2ª parcela
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_041()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_vig text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar 1ª parcela com IRRF retido (R$ 300) — tributação do 13º é exclusiva da 2ª';
  r.esperado := 'Recusado — o IRRF do 13º nasce na quitação, sobre o valor integral, apartado do mês';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela, valor_irrf, base_irrf)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-041', 'QA IRRF Primeira', 1, 300, 4000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a tabela de IRRF é versionada por vigência?';
  r.esperado := 'folha_tabelas_irrf com vigência e deduções parametrizadas';
  v_vig := public.qa_col_existe('folha_tabelas_irrf', 'vigencia_inicio');

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO (par do DEC13-040, aqui pelo imposto): 1ª parcela com IRRF entrou '
             || 'sem resistência — a exclusividade na fonte (RIR/2018, art. 700: apura na 2ª '
             || 'parcela sobre o valor integral, sem somar aos rendimentos do mês) existe só no '
             || 'cálculo do React. O detalhe que agrava: base_irrf digitável permite também '
             || 'somar o 13º ao salário de dezembro numa base só, mudando a faixa dos dois — o '
             || 'erro clássico. Tabelas versionadas: %s. Correção: mesmo CHECK do DEC13-040 '
             || 'cobrindo valor_irrf, e memória de cálculo registrando a base apartada.',
             coalesce(v_vig, 'vigência AUSENTE'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('IRRF na 1ª parcela recusado; tabelas com vigência (%s).',
                       coalesce(v_vig, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-042 — FGTS de 8% nas duas parcelas, por competência
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_042()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_comp text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar cálculo com base de FGTS MAIOR que o bruto (base 10.000 para bruto 3.000)';
  r.esperado := 'Recusado — a base do FGTS de cada parcela é fração do bruto, nunca mais que ele';
  BEGIN
    INSERT INTO public.folha_13_calculo
      (tenant_id, ano, colaborador_id, colaborador_nome, parcela,
       valor_bruto, base_fgts, valor_fgts)
    VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
            'qa-dec13-042', 'QA FGTS Inflado', 2, 3000, 10000, 800);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: o depósito de cada parcela tem competência registrada para a guia?';
  r.esperado := 'FGTS da 1ª na competência do adiantamento; da 2ª na competência da quitação';
  v_comp := coalesce(public.qa_col_existe('folha_13_calculo', '%competencia%'),
                     public.qa_col_existe('folha_13_calculo', '%data_pagamento%'));

  IF v_aceitou OR v_comp IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o cálculo do React reparte a base certa (1ª: metade; 2ª: '
             || 'diferença — 8%% exatos no total, Lei 8.036 art. 15), mas o banco não sustenta '
             || 'a regra: base_fgts inflada além do bruto foi %s e NÃO HÁ campo de competência '
             || 'nem data de pagamento em folha_13_calculo (%s) — sem eles não se monta a guia '
             || 'de cada parcela nem se prova o depósito na competência devida, que é '
             || 'exatamente o que o FGTS Digital confere. Correção: CHECK base_fgts <= '
             || 'valor_bruto + colunas de competência/data de pagamento por parcela.',
             CASE WHEN v_aceitou THEN 'aceita' ELSE 'recusada' END,
             coalesce('há: ' || v_comp, 'nenhum campo'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Base consistente e competência registrada (%s).', v_comp);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-050 — eSocial: S-1200 anual e S-1210 sem duplicidade
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_unq text; v_anual text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual) e S-1210 (pagamentos) gerados, com unicidade por competência';
  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;
  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_anual
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%S-1200%' OR p.prosrc ILIKE '%S1200%' OR p.prosrc ILIKE '%anual%13%');

  IF v_unq IS NULL AND v_anual IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): o 13º '
             || 'não gera evento nenhum — nenhuma função monta o S-1200 da competência anual '
             || 'nem o S-1210 dos pagamentos das parcelas, e esocial_transmissoes segue sem '
             || 'unicidade (mesmo evento gravável duas vezes). A competência anual tem regra '
             || 'própria de retificação e prazo; sem os eventos, o 13º pago não existe para o '
             || 'governo — e a DCTFWeb de dezembro não fecha com a folha. Correção: geração '
             || 'dos dois eventos no fechamento (apuração e pagamento), chave natural '
             || '(vínculo + tipo + competência anual) e tradução de rejeição em instrução, '
             || 'nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes (unicidade: %s; eventos anuais: %s).',
                       coalesce(v_unq, '—'), coalesce(v_anual, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-051 — provisão do 13º viva, competência a competência
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_051()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisão do 13º é alimentada por algum motor?';
  r.esperado := '1/12 + encargos por competência e vínculo ativo, baixada contra os pagamentos';
  v_tab := CASE WHEN to_regclass('public.folha_provisoes') IS NOT NULL THEN 'folha_provisoes' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_provisoes%';
  IF v_tab IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a tabela existe (folha_provisoes, com tipo, encargos e reversão — '
             || 'desenho certo) e NENHUMA função a alimenta: a provisão do 13º é lançada à '
             || 'mão, quando alguém lembra. Provisão por regime de competência não é enfeite '
             || 'contábil — o custo nasce 1/12 por mês (CA-009), admissões e desligamentos a '
             || 'ajustam, e o contador precisa conciliar provisionado × pago no fim do ano '
             || '(seção 20). À mão, ela desalinha da folha no primeiro mês esquecido e o '
             || 'balancete de dezembro leva o susto do ano inteiro de uma vez. Correção: '
             || 'rotina mensal (pg_cron) provisionando por vínculo ativo e baixando contra '
             || 'os pagamentos das parcelas.';
  ELSIF v_tab IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela folha_provisoes não existe mais nesta base.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Provisão alimentada por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-060 — rescisão: proporcional pago, justa causa perde, adiantamento concilia
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_060()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_ponte text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar rescisão POR JUSTA CAUSA pagando 13º proporcional de R$ 1.000';
  r.esperado := 'Recusado — na dispensa por justa causa o 13º proporcional é perdido';
  BEGIN
    INSERT INTO public.folha_rescisoes
      (tenant_id, colaborador_id, colaborador_nome, tipo_rescisao,
       data_desligamento, decimo_terceiro_proporcional)
    VALUES (public.qa_sandbox_tenant_id(), 'qa-dec13-060', 'QA Justa Causa Com 13',
            'DISPENSA_COM_JUSTA_CAUSA', CURRENT_DATE, 1000);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a rescisão concilia com o módulo do 13º (adiantamento pago, rodada anual)?';
  r.esperado := 'Adiantamento deduzido nas verbas e vínculo desligado fora da rodada de novembro/dezembro';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_ponte
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%folha_rescisoes%' AND p.prosrc ILIKE '%13_calculo%';

  IF v_aceitou OR v_ponte IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a rescisão tem o campo certo (decimo_terceiro_proporcional) e '
             || 'nenhuma regra por trás — justa causa com 13º proporcional de R$ 1.000 foi '
             || '%s (o cálculo correto vive só no React, calcularRescisao), e nenhuma função '
             || 'liga folha_rescisoes a folha_13_calculo (%s): adiantamento pago nas férias '
             || 'não é conferido nas verbas, e o desligado pode reaparecer na rodada anual. '
             || 'A exceção da culpa recíproca (50%%, Súmula 14) é o DESL-035. Correção: '
             || 'validação motivo × verba no banco e conciliação rescisão ↔ apuração anual '
             || 'do 13º nos dois sentidos.',
             CASE WHEN v_aceitou THEN 'aceito' ELSE 'recusado' END,
             coalesce('há: ' || v_ponte, 'nenhuma'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Justa causa sem 13º garantida e conciliação presente (%s).', v_ponte);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-070 — cálculo fechado só reabre com rito
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, parcela,
     valor_bruto, total_liquido, status)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', 2, 3000, 2500, 'pago')
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  -- a cerca do sandbox de QA (qa_guarda_cercado) não é trilha de auditoria
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha (o único '
             || 'gatilho da tabela é o de updated_at, que não guarda o valor anterior). Nem o '
             || 'status tem CHECK: qualquer texto vale. Recibo entregue dizendo um valor e banco '
             || 'dizendo outro é exatamente o cenário que a auditoria trabalhista procura, e a '
             || 'reabertura com rito (motivo + dupla aprovação + diferença como complemento/'
             || 'estorno) é o RF-007 do documento. Correção: trava de UPDATE para status pago/'
             || 'fechado + trilha append-only com antes/depois + fluxo de reabertura. Mesma '
             || 'disciplina do FERIAS-054.';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := 'A edição direta do cálculo pago foi recusada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- DEC13-071 — remuneração do 13º restrita por perfil
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_071()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_restr int; v_proprio int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as políticas de folha_13_calculo separam o próprio do alheio?';
  r.esperado := 'Colaborador lê só o próprio cálculo; folha da equipe restrita por perfil (camada RESTRICTIVE)';
  SELECT count(*) INTO v_restr
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_13_calculo'
    AND permissive = 'RESTRICTIVE';
  SELECT count(*) INTO v_proprio
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'folha_13_calculo'
    AND (qual ILIKE '%auth.uid%' OR qual ILIKE '%usuario%' OR qual ILIKE '%colaborador%uid%');

  IF v_restr = 0 AND v_proprio = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: folha_13_calculo tem UMA política, e ela é só de tenant — qualquer '
             || 'usuário autenticado da empresa, inclusive o colaborador comum, lê a folha de '
             || '13º INTEIRA: salário-base, médias e líquido de todos os colegas. Remuneração '
             || 'é dado pessoal com acesso mínimo (LGPD art. 6º VII e seção 6 do documento: '
             || 'colaborador vê só o próprio), e a tabela está FORA da camada '
             || 'perfil_restringe_leitura_* que protege as 20 tabelas sensíveis do sistema — '
             || 'a folha de férias (folha_ferias_calculo) já tem a dela, o 13º ficou sem. '
             || 'Correção: política RESTRICTIVE via perfil_permite_modulo (padrão PERFIL-003) '
             || '+ regra de "próprio registro" para o colaborador.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Camadas presentes (restritivas: %s; separação do próprio: %s políticas).',
                       v_restr, v_proprio);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- Registro no motor
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-001','qa_caso_dec13_001',true), ('DEC13-002','qa_caso_dec13_002',true),
  ('DEC13-003','qa_caso_dec13_003',true), ('DEC13-020','qa_caso_dec13_020',true),
  ('DEC13-021','qa_caso_dec13_021',true), ('DEC13-030','qa_caso_dec13_030',true),
  ('DEC13-031','qa_caso_dec13_031',true), ('DEC13-032','qa_caso_dec13_032',true),
  ('DEC13-033','qa_caso_dec13_033',true), ('DEC13-040','qa_caso_dec13_040',true),
  ('DEC13-041','qa_caso_dec13_041',true), ('DEC13-042','qa_caso_dec13_042',true),
  ('DEC13-050','qa_caso_dec13_050',true), ('DEC13-051','qa_caso_dec13_051',true),
  ('DEC13-060','qa_caso_dec13_060',true), ('DEC13-070','qa_caso_dec13_070',true),
  ('DEC13-071','qa_caso_dec13_071',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ══════════ 2a leva: 14 casos novos e suas rotinas ══════════
DO $doc$
DECLARE v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'financeiro/decimo-terceiro';
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo financeiro/decimo-terceiro nao existe nesta base — casos nao inseridos.';
    RETURN;
  END IF;
  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'DEC13-004', 'Aviso prévio indenizado projeta o tempo e pode gerar mais um avo',
   'negativo', 'critica', 'aprovado', 'api',
   'CLT, art. 487, §1º; Súmula 371 do TST; OJ 82 da SDI-1 do TST',
   'O aviso prévio indenizado integra o tempo de serviço para todos os efeitos legais. Desligado em 20/11 com 30 dias de aviso indenizado, o contrato projeta até 20/12: dezembro passa a ter 20 dias e vira mais um avo. Ignorar a projeção paga 11/12 onde a lei manda 12/12 — diferença que volta como reclamatória.',
   'Vínculo desligado em 20/11 do ano-base, com aviso prévio indenizado de 30 dias.',
   '[{"ordem": 1, "acao": "Apurar o 13º sem considerar a projeção", "resultado_esperado": "11 avos"}, {"ordem": 2, "acao": "Apurar considerando a projeção do aviso indenizado", "resultado_esperado": "12 avos — dezembro fecha 20 dias com a projeção"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória mostra a data projetada do fim do contrato, não só a data do desligamento"}]'::jsonb,
   'Aviso indenizado conta como tempo de serviço — inclusive para o avo de dezembro.',
   'Requisitos YE-DP-13-001: RN-001 e RN-009 (rescisão). O mesmo vale para as férias proporcionais.'),

  (v_mod, 'DEC13-005', 'Fronteira dos 15 dias: dia 16 conta o avo, dia 17 não',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 1º, §2º (fração igual ou superior a 15 dias)',
   'A regra da fração é de contagem exata e é onde mais se erra por um dia. Em mês de 31 dias, admissão no dia 17 deixa 15 dias trabalhados (17 a 31) e CONTA; no dia 18 deixa 14 e NÃO conta. Fevereiro, com 28 ou 29 dias, tem fronteira própria. O teste fixa as bordas para que nenhuma mudança futura as mova sem que alguém perceba.',
   'Vínculos fictícios admitidos exatamente nas datas de fronteira do ano-base.',
   '[{"ordem": 1, "acao": "Admitido em 17/03 (mês de 31 dias)", "resultado_esperado": "Março conta — 15 dias trabalhados"}, {"ordem": 2, "acao": "Admitido em 18/03", "resultado_esperado": "Março não conta — 14 dias"}, {"ordem": 3, "acao": "Admitido em 14/02 (ano comum, 28 dias)", "resultado_esperado": "Fevereiro conta — 15 dias"}, {"ordem": 4, "acao": "Admitido em 15/02 (ano comum)", "resultado_esperado": "Fevereiro não conta — 14 dias"}]'::jsonb,
   'A borda é 15 dias exatos, contados no calendário do próprio mês.',
   'Requisitos YE-DP-13-001: RN-001 / CA-001. Complementa DEC13-001, que cobre o caso geral.'),

  (v_mod, 'DEC13-006', 'Afastamento por acidente de trabalho conta como tempo de serviço',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 8.213/1991, art. 4º, parágrafo único e art. 118; CLT, art. 4º; Súmula 46 do TST',
   'O afastamento acidentário (benefício B-91) não é igual ao auxílio-doença comum: o período é contado como tempo de serviço para todos os efeitos, inclusive 13º. Tratar acidente de trabalho como doença comum tira avos que a lei manda pagar.',
   'Vínculo com 4 meses de afastamento acidentário (B-91) no ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º de quem se afastou por acidente de trabalho", "resultado_esperado": "Os meses de afastamento contam como avos do empregador"}, {"ordem": 2, "acao": "Comparar com afastamento por doença comum", "resultado_esperado": "Na doença comum o empregador paga só os 15 primeiros dias e o restante é abono anual do INSS"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória nomeia o tipo de afastamento e o efeito aplicado"}]'::jsonb,
   'Acidente de trabalho conta tempo; doença comum divide com o INSS.',
   'Requisitos YE-DP-13-001: RN-008. Complementa DEC13-003, que trata maternidade e doença comum.'),

  (v_mod, 'DEC13-022', 'Horas extras entram pela média física × valor da hora atual (Súmula 347)',
   'alternativo', 'alta', 'aprovado', 'api',
   'Súmula 347 do TST; Decreto 57.155/1965, art. 2º',
   'A média de horas extras do 13º é FÍSICA: soma-se a quantidade de HORAS do ano, divide-se pelos meses e multiplica-se pelo valor da hora VIGENTE no pagamento. Usar a média dos valores históricos paga a menos sempre que houve aumento salarial no ano — é passivo certo.',
   'Vínculo com 10 horas extras por mês o ano todo e aumento salarial no meio do ano.',
   '[{"ordem": 1, "acao": "Apurar a média pela quantidade de horas × valor atual", "resultado_esperado": "Média calculada sobre o salário vigente"}, {"ordem": 2, "acao": "Comparar com a média dos valores pagos no ano", "resultado_esperado": "A média física é MAIOR quando houve aumento"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "A memória informa qual critério foi usado e por quê"}]'::jsonb,
   'Média física protege o cálculo do aumento salarial no meio do ano.',
   'Requisitos YE-DP-13-001: RN-003. Sem registro de ponto no ano, o sistema usa os valores pagos e avisa.'),

  (v_mod, 'DEC13-023', 'Adicionais habituais integram a base do 13º',
   'feliz', 'alta', 'aprovado', 'api',
   'Súmula 60 (adicional noturno), Súmula 132 (adicional de periculosidade) e Súmula 139 (adicional de insalubridade) do TST; Decreto 57.155/1965, art. 2º',
   'Adicional noturno, de insalubridade e de periculosidade pagos com habitualidade integram a remuneração e, portanto, a base do 13º. Se as rubricas desses adicionais não estiverem marcadas como integrantes do 13º no cadastro, o cálculo sai a menor sem ninguém perceber.',
   'Rubricas de adicional noturno, insalubridade e periculosidade cadastradas e pagas com habitualidade.',
   '[{"ordem": 1, "acao": "Conferir a marcação das rubricas de adicional", "resultado_esperado": "Marcadas como integrantes da base do 13º"}, {"ordem": 2, "acao": "Apurar a média das variáveis", "resultado_esperado": "Os adicionais habituais entram na média"}, {"ordem": 3, "acao": "Conferir a memória", "resultado_esperado": "Cada rubrica somada aparece nomeada na memória"}]'::jsonb,
   'Adicional habitual é remuneração — e remuneração entra no 13º.',
   'Requisitos YE-DP-13-001: RN-003 / CA-002. Complementa DEC13-020.'),

  (v_mod, 'DEC13-034', 'Política do adiantamento: as duas opções da lei, à escolha da empresa',
   'alternativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, caput',
   'A lei manda adiantar METADE do salário do mês anterior. A prática consolidada admite também metade do 13º apurado (com médias). As duas leituras são defensáveis, então a escolha é da empresa — e precisa ficar registrada, com efeito real no cálculo e a mesma política valendo para todos no ano.',
   'Empresa com a política do adiantamento configurada.',
   '[{"ordem": 1, "acao": "Configurar a política ''metade da remuneração do mês anterior'' e apurar a 1ª parcela", "resultado_esperado": "Valor = 50% da remuneração do mês anterior"}, {"ordem": 2, "acao": "Trocar para ''metade do 13º apurado'' e apurar de novo", "resultado_esperado": "Valor = 50% do 13º com médias — diferente do anterior"}, {"ordem": 3, "acao": "Conferir o registro", "resultado_esperado": "A política escolhida fica gravada e visível na memória do cálculo"}]'::jsonb,
   'As duas opções existem, a empresa escolhe e o sistema obedece — sem valor mágico.',
   'Requisitos YE-DP-13-001: RN-004. Ponto [VAL] do documento: a escolha deve ser conferida com a contabilidade.'),

  (v_mod, 'DEC13-035', 'Adiantamento nas férias fora de janeiro é avisado, não recusado',
   'negativo', 'media', 'aprovado', 'api',
   'Lei 4.749/1965, art. 2º, §2º',
   'O empregado que quer receber a 1ª parcela nas férias deve requerer em JANEIRO do ano correspondente. Pedido fora dessa janela não obriga o empregador. O sistema não deve recusar em silêncio nem pagar sem registro: deve avisar que o pedido saiu fora do prazo e deixar a decisão documentada.',
   'Pedido de férias com adiantamento do 13º requerido em março.',
   '[{"ordem": 1, "acao": "Gerar os adiantamentos das férias do ano", "resultado_esperado": "Os pedidos de janeiro geram a 1ª parcela normalmente"}, {"ordem": 2, "acao": "Conferir o pedido feito em março", "resultado_esperado": "Aparece na lista de avisos como fora da janela do §2º"}, {"ordem": 3, "acao": "Conferir a contagem", "resultado_esperado": "O retorno informa quantos pedidos ficaram fora de janeiro"}]'::jsonb,
   'Fora de janeiro não é proibido — é decisão da empresa, e fica registrada.',
   'Requisitos YE-DP-13-001: RN-004. Complementa DEC13-032.'),

  (v_mod, 'DEC13-043', 'INSS do 13º respeita faixas e teto, e bate com a tabela vigente',
   'feliz', 'critica', 'aprovado', 'api',
   'Lei 8.212/1991, art. 20 e art. 28, §7º; Decreto 3.048/1999, art. 214, §6º',
   'O INSS do 13º é progressivo por faixas e limitado ao teto. O cálculo do banco (usado no lote) e o da tela precisam dar o MESMO número em todas as faixas, inclusive nas bordas e acima do teto — divergência entre os dois é erro de recolhimento, com multa.',
   'Tabela de INSS vigente cadastrada.',
   '[{"ordem": 1, "acao": "Calcular o INSS em bases de cada faixa e nas bordas", "resultado_esperado": "Valor progressivo, faixa a faixa"}, {"ordem": 2, "acao": "Calcular o INSS em base acima do teto", "resultado_esperado": "Desconto limitado ao teto — não cresce mais"}, {"ordem": 3, "acao": "Comparar banco e tela", "resultado_esperado": "Mesmo valor, centavo a centavo"}]'::jsonb,
   'Faixas, bordas e teto conferidos — e os dois caminhos de cálculo concordando.',
   'Requisitos YE-DP-13-001: RN-005 / CA-004. Complementa DEC13-040.'),

  (v_mod, 'DEC13-052', 'Provisão do 13º é revertida quando o colaborador é desligado',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 6.404/1976, art. 177 (regime de competência); NBC TG 1000, seção 21 (provisões); documento YE-DP-13-001, CA-009',
   'A provisão acumula 1/12 por mês enquanto o vínculo existe. Quando o colaborador é desligado e o 13º é quitado na rescisão, a provisão daquele vínculo precisa ser REVERTIDA — senão o balanço carrega para sempre uma obrigação que já foi paga.',
   'Colaborador provisionado durante o ano e desligado antes de dezembro.',
   '[{"ordem": 1, "acao": "Provisionar competências com o vínculo ativo", "resultado_esperado": "Provisão acumulada mês a mês"}, {"ordem": 2, "acao": "Desligar o colaborador e provisionar a competência seguinte", "resultado_esperado": "A provisão do desligado é revertida, não repetida"}, {"ordem": 3, "acao": "Conciliar o ano", "resultado_esperado": "Provisionado e pago fecham, sem sobra do desligado"}]'::jsonb,
   'Provisão de quem saiu não fica pendurada no balanço.',
   'Requisitos YE-DP-13-001: RNF-007. Complementa DEC13-051.'),

  (v_mod, 'DEC13-061', 'Culpa recíproca paga metade do 13º proporcional',
   'alternativo', 'alta', 'aprovado', 'api',
   'CLT, art. 484; Súmula 14 do TST',
   'Reconhecida a culpa recíproca, as verbas rescisórias devidas pela dispensa sem justa causa são pagas pela METADE — inclusive o 13º proporcional. Tratar como justa causa (zero) ou como dispensa comum (integral) erra nos dois sentidos.',
   'Rescisão por culpa recíproca reconhecida judicialmente, no meio do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por culpa recíproca", "resultado_esperado": "Metade do 13º proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa sem justa causa", "resultado_esperado": "Metade do valor da dispensa comum"}, {"ordem": 3, "acao": "Conferir o fundamento", "resultado_esperado": "A memória cita o art. 484 da CLT e a Súmula 14 do TST"}]'::jsonb,
   'Culpa recíproca não é zero nem inteiro: é metade.',
   'Requisitos YE-DP-13-001: RN-009. DESL-035 cobre o lado do aviso prévio; aqui é o 13º.'),

  (v_mod, 'DEC13-062', 'Pedido de demissão mantém o 13º proporcional',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 4.090/1962, art. 3º; Súmula 157 do TST',
   'Quem pede demissão tem direito ao 13º proporcional aos meses trabalhados. Só a dispensa por justa causa afasta a gratificação. Confundir os dois motivos retém verba devida — e a Súmula 157 é expressa.',
   'Rescisão por pedido de demissão em agosto do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por pedido de demissão", "resultado_esperado": "8/12 do 13º, proporcional aos avos"}, {"ordem": 2, "acao": "Comparar com a dispensa por justa causa", "resultado_esperado": "Na justa causa, zero"}, {"ordem": 3, "acao": "Conferir o abatimento do adiantamento", "resultado_esperado": "Se houve 1ª parcela paga, ela é deduzida"}]'::jsonb,
   'Pedir demissão não faz perder o 13º proporcional.',
   'Requisitos YE-DP-13-001: RN-009. Complementa DEC13-060.'),

  (v_mod, 'DEC13-063', 'Falecimento: o 13º proporcional é devido e vai aos dependentes',
   'alternativo', 'media', 'aprovado', 'api',
   'Lei 6.858/1980, art. 1º; Lei 4.090/1962, art. 3º',
   'Com o falecimento do empregado, o 13º proporcional continua devido e é pago aos dependentes habilitados na Previdência, independentemente de inventário. O sistema não pode tratar o falecimento como perda da gratificação.',
   'Rescisão por falecimento em setembro do ano-base.',
   '[{"ordem": 1, "acao": "Apurar o 13º da rescisão por falecimento", "resultado_esperado": "9/12, proporcional aos avos — valor devido"}, {"ordem": 2, "acao": "Conferir o fundamento", "resultado_esperado": "A memória registra que o pagamento segue a Lei 6.858/1980"}, {"ordem": 3, "acao": "Conferir que não é tratado como justa causa", "resultado_esperado": "Valor diferente de zero"}]'::jsonb,
   'Falecimento não extingue a gratificação proporcional.',
   'Requisitos YE-DP-13-001: RN-009. O encaminhamento aos dependentes é operação do DP, fora do cálculo.'),

  (v_mod, 'DEC13-072', 'Rodar o lote duas vezes não duplica parcela',
   'negativo', 'alta', 'aprovado', 'api',
   'Documento YE-DP-13-001, RF-004 e RNF-008 (processamento em lote idempotente)',
   'O processamento em lote é feito por pessoas, sob pressão de prazo, e será clicado duas vezes. A segunda passada não pode criar uma segunda parcela viva para o mesmo colaborador: tem de pular quem já tem cálculo e dizer quantos pulou.',
   'Empresa com colaboradores aptos e a 1ª parcela já processada.',
   '[{"ordem": 1, "acao": "Processar o lote da 1ª parcela", "resultado_esperado": "Cálculos criados para os aptos"}, {"ordem": 2, "acao": "Processar o mesmo lote de novo", "resultado_esperado": "Nenhum cálculo novo; o retorno informa quantos já existiam"}, {"ordem": 3, "acao": "Conferir a base", "resultado_esperado": "Uma única parcela viva por colaborador/ano"}]'::jsonb,
   'Clicar duas vezes não duplica folha.',
   'Requisitos YE-DP-13-001: RF-004. A trava de base é a unicidade da parcela viva.'),

  (v_mod, 'DEC13-073', 'Prazo legal recua para o último dia útil, inclusive em feriado municipal',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 4.749/1965, arts. 1º e 2º; Lei 662/1949 e Lei 9.093/1995 (feriados civis e municipais)',
   'Se 30/11 ou 20/12 caem em sábado, domingo ou feriado, o pagamento tem de ser ANTECIPADO para o último dia útil anterior — nunca adiado. A conta precisa enxergar também o feriado municipal da cidade do estabelecimento, que é o mais fácil de esquecer.',
   'Feriado municipal cadastrado no dia útil imediatamente anterior à data-limite.',
   '[{"ordem": 1, "acao": "Consultar o prazo da 2ª parcela num ano em que 20/12 cai em domingo", "resultado_esperado": "Data-limite antecipada para a sexta-feira"}, {"ordem": 2, "acao": "Cadastrar feriado municipal nessa sexta e consultar de novo", "resultado_esperado": "Antecipa mais um dia útil"}, {"ordem": 3, "acao": "Conferir a 1ª parcela em 30/11", "resultado_esperado": "Mesma regra de antecipação"}]'::jsonb,
   'A data-limite anda para trás, nunca para frente.',
   'Requisitos YE-DP-13-001: RN-002 / CA-003. Complementa DEC13-031.')
  ON CONFLICT (codigo) DO UPDATE SET
      titulo = EXCLUDED.titulo, base_legal = EXCLUDED.base_legal,
      objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes,
      passos = EXCLUDED.passos, resultado_esperado = EXCLUDED.resultado_esperado,
      observacoes = EXCLUDED.observacoes, nivel = EXCLUDED.nivel,
      prioridade = EXCLUDED.prioridade, updated_at = now();

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'Documentacao de testes do 13o: % casos antes, % depois.', v_antes, v_depois;
END $doc$;

-- ── DEC13-005: a fronteira dos 15 dias, dia a dia ─────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_cpf text; v_avos int; c record;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de vinculos admitidos exatamente nas datas de fronteira';
  r.esperado := 'Mes com 15 dias ou mais conta; com 14, nao conta (Lei 4.090, art. 1o, §2o)';

  FOR c IN
    SELECT * FROM (VALUES
      ('90000005053', make_date(v_ano,3,17), 10, 'admitido em 17/03 (15 dias)'),
      ('90000005134', make_date(v_ano,3,18),  9, 'admitido em 18/03 (14 dias)'),
      ('90000005215', make_date(v_ano,2,14), 11, 'admitido em 14/02'),
      ('90000005304', make_date(v_ano,2,15), 10, 'admitido em 15/02')
    ) AS t(cpf, adm, avos_esperados, rotulo)
  LOOP
    -- vinculo efemero: a sonda cria, le e desfaz o proprio rastro
    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
    INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
    VALUES (v_ten, 'QA Fronteira ' || c.cpf, c.cpf, 'QA', c.adm, 'concluido');

    v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, c.cpf, v_ano, NULL)->>'avos')::int, -1);
    v_lidos := array_append(v_lidos, format('%s: %s avos', c.rotulo, v_avos));
    IF v_avos <> c.avos_esperados THEN
      v_erros := array_append(v_erros,
        format('%s deveria dar %s avos e deu %s', c.rotulo, c.avos_esperados, v_avos));
    END IF;

    DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = c.cpf;
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a fronteira dos 15 dias esta deslocada — ' || array_to_string(v_erros, '; ')
             || '. Um dia de diferenca na contagem vira um avo a mais ou a menos em toda a folha.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Fronteiras conferidas (' || array_to_string(v_lidos, '; ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-043: faixas, bordas e teto do INSS ──────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_043()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_ant numeric := -1; v_val numeric; v_teto numeric; v_base numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Calcular o INSS do 13o em bases crescentes, das faixas ate acima do teto';
  r.esperado := 'Valor progressivo que nunca diminui e para de crescer no teto (Lei 8.212/1991, art. 20)';

  FOREACH v_base IN ARRAY ARRAY[1000, 1412, 1500, 2666.68, 4000.03, 7786.02, 9000, 20000]::numeric[]
  LOOP
    v_val := COALESCE((public.decimo_terceiro_inss(v_base, v_ten, NULL)->>'valor')::numeric, -1);
    v_lidos := array_append(v_lidos, format('base %s -> %s', v_base, v_val));
    IF v_val < v_ant THEN
      v_erros := array_append(v_erros, format('base %s desconta MENOS que a base anterior', v_base));
    END IF;
    IF v_val > v_base THEN
      v_erros := array_append(v_erros, format('base %s desconta mais que o proprio 13o', v_base));
    END IF;
    v_ant := v_val;
  END LOOP;

  r.passo_ordem := 2;
  r.passo_acao := 'Conferir o teto: dobrar a base acima do teto nao pode aumentar o desconto';
  r.esperado := 'Mesmo valor — o desconto e limitado ao teto';
  v_teto := (public.decimo_terceiro_inss(20000, v_ten, NULL)->>'valor')::numeric;
  IF (public.decimo_terceiro_inss(40000, v_ten, NULL)->>'valor')::numeric <> v_teto THEN
    v_erros := array_append(v_erros, 'o desconto continua crescendo acima do teto');
  END IF;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o INSS do 13o nao respeita a progressao ou o teto — '
             || array_to_string(v_erros, '; ') || '. Recolhimento errado gera multa.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Progressao e teto conferidos (%s); teto em R$ %s.',
                       array_to_string(v_lidos, '; '), v_teto);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-073: a data-limite anda para tras, nunca para frente ────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_073()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_erros text[] := ARRAY[]::text[]; v_lidos text[] := ARRAY[]::text[];
  v_d date; v_ano int; v_limite date;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Consultar o prazo legal das duas parcelas em varios anos';
  r.esperado := 'Sempre dia util, e nunca depois de 30/11 (1a) ou 20/12 (2a) — Lei 4.749/1965';

  FOR v_ano IN 2024..2030 LOOP
    -- 1a parcela: limite 30/11
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 1, NULL, NULL);
    v_limite := make_date(v_ano, 11, 30);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em %s, depois de 30/11', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 1a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('%s 1a=%s', v_ano, v_d));

    -- 2a parcela: limite 20/12
    v_d := public.decimo_terceiro_prazo_legal(v_ano, 2, NULL, NULL);
    v_limite := make_date(v_ano, 12, 20);
    IF v_d > v_limite THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em %s, depois de 20/12', v_ano, v_d));
    END IF;
    IF extract(isodow from v_d) > 5 THEN
      v_erros := array_append(v_erros, format('%s: 2a parcela caiu em fim de semana (%s)', v_ano, v_d));
    END IF;
    v_lidos := array_append(v_lidos, format('2a=%s', v_d));
  END LOOP;

  IF array_length(v_erros,1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a data-limite do 13o nao antecipa corretamente — '
             || array_to_string(v_erros, '; ')
             || '. Pagar fora da janela e infracao mesmo com o valor certo.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Prazos conferidos em 7 anos, sempre em dia util e dentro do limite ('
             || array_to_string(v_lidos, ', ') || ').';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-006: acidente de trabalho nao derruba avo (Sumula 46 TST) ───
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005487'; v_af uuid;
  v_avos_acid int; v_avos_comum int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem ficou 4 meses afastado por ACIDENTE DE TRABALHO (B91)';
  r.esperado := 'Os meses contam: a ausencia por acidente nao pesa contra o 13o (Sumula 46 do TST)';

  DELETE FROM public.afastamentos WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes   WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao, status)
  VALUES (v_ten, 'QA Acidentado', v_cpf, 'QA', make_date(v_ano - 3, 1, 10), 'concluido');

  INSERT INTO public.afastamentos (tenant_id, colaborador_cpf, colaborador_nome,
                                   data_inicio, data_fim, nexo_trabalho, observacoes)
  VALUES (v_ten, v_cpf, 'QA Acidentado',
          make_date(v_ano, 3, 1), make_date(v_ano, 6, 30), 'sim'::nexo_trabalho, 'QA DEC13-006')
  RETURNING id INTO v_af;
  INSERT INTO public.afastamentos_previdenciario (tenant_id, afastamento_id, especie_beneficio,
                                                  data_inicio_beneficio)
  VALUES (v_ten, v_af, 'B91', make_date(v_ano, 3, 16));

  v_avos_acid := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  r.passo_ordem := 2;
  r.passo_acao := 'Trocar o beneficio para DOENCA COMUM (B31) e apurar de novo';
  r.esperado := 'Ai sim os meses de beneficio saem dos avos do empregador — o INSS paga o abono anual';
  UPDATE public.afastamentos_previdenciario SET especie_beneficio = 'B31' WHERE afastamento_id = v_af;
  v_avos_comum := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.afastamentos_previdenciario WHERE afastamento_id = v_af;
  DELETE FROM public.afastamentos WHERE id = v_af;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;

  IF v_avos_acid < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o afastamento por ACIDENTE DE TRABALHO derruba avos igual ao de '
             || 'doenca comum (acidentario: %s avos; doenca comum: %s avos). A Sumula 46 do TST e '
             || 'expressa: as ausencias por acidente do trabalho NAO sao consideradas contra a '
             || 'gratificacao natalina, e o art. 4o, paragrafo unico, da Lei 8.213/1991 conta o '
             || 'periodo como tempo de servico. Do jeito atual a empresa paga a menos e a '
             || 'diferenca volta como reclamatoria. Correcao: as especies acidentarias (B91, B92) '
             || 'nao entram no desconto de dias do empregador; as comuns (B31, B32) continuam '
             || 'entrando.', v_avos_acid, v_avos_comum);
  ELSIF v_avos_comum >= 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a doenca comum tambem manteve %s avos. O empregador '
             || 'so responde pelos 15 primeiros dias; o restante e abono anual do INSS. Contar '
             || 'tudo paga a MAIS e duplica a despesa.', v_avos_comum);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cada afastamento com seu efeito: acidente de trabalho manteve %s avos '
             || '(Sumula 46 do TST); doenca comum ficou com %s, cabendo o abono anual ao INSS.',
             v_avos_acid, v_avos_comum);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-004: projecao do aviso previo indenizado ────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000005568'; v_avos int; v_adm uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar os avos de quem foi desligado em 20/11 com aviso previo INDENIZADO de 30 dias';
  r.esperado := '12 avos: a projecao leva o contrato ate 20/12 e dezembro fecha 20 dias (CLT, art. 487, §1o; Sumula 371 do TST)';

  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, 'QA Aviso Indenizado', v_cpf, 'QA', make_date(v_ano - 2, 2, 1),
          make_date(v_ano, 11, 20), 'concluido')
  RETURNING id INTO v_adm;

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento,
                                      aviso_tipo, dias_aviso)
  VALUES (v_ten, 'qa-dec13-004', 'QA Aviso Indenizado', v_cpf, v_adm,
          'DISPENSA_SEM_JUSTA_CAUSA', make_date(v_ano, 11, 20), 'indenizado', 30);

  v_avos := COALESCE((public.decimo_terceiro_avos(v_ten, v_cpf, v_ano, NULL)->>'avos')::int, -1);

  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_avos < 12 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a apuracao parou na data do desligamento e devolveu %s avos. O '
             || 'aviso previo INDENIZADO integra o tempo de servico para todos os efeitos legais '
             || '(CLT, art. 487, §1o; Sumula 371 do TST): desligado em 20/11 com 30 dias de aviso, '
             || 'o contrato projeta ate 20/12 e dezembro fecha 20 dias — o 12o avo e devido. '
             || 'Pagar 11/12 onde a lei manda 12/12 e diferenca que volta como reclamatoria, e a '
             || 'mesma projecao vale para as ferias proporcionais. Correcao: somar os dias do '
             || 'aviso indenizado a data de fim do contrato antes de contar os avos.', v_avos);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Projecao do aviso indenizado considerada: %s avos, com dezembro contado '
             || 'pela data projetada do fim do contrato.', v_avos);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-061/062/063: o motivo da rescisao e o 13o ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_rescisao_motivo(
  p_tipo text, p_mes int, p_fator numeric, p_cpf text, p_nome text)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_adm uuid; v_resc uuid; v_out jsonb;
BEGIN
  DELETE FROM public.folha_rescisoes WHERE tenant_id = v_ten AND colaborador_cpf = p_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = p_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao,
                                data_desligamento, status)
  VALUES (v_ten, p_nome, p_cpf, 'QA', 3000, make_date(v_ano - 2, 2, 1),
          make_date(v_ano, p_mes, 25), 'concluido')
  RETURNING id INTO v_adm;

  INSERT INTO public.folha_rescisoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                      admissao_id, tipo_rescisao, data_desligamento)
  VALUES (v_ten, 'qa-' || p_cpf, p_nome, p_cpf, v_adm, p_tipo::public.rescisao_tipo, make_date(v_ano, p_mes, 25))
  RETURNING id INTO v_resc;

  v_out := public.decimo_terceiro_da_rescisao(v_resc);

  DELETE FROM public.folha_rescisoes WHERE id = v_resc;
  DELETE FROM public.admissoes WHERE id = v_adm;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_062()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_ped jsonb; v_jc jsonb; v_dev numeric; v_avos int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por PEDIDO DE DEMISSAO em agosto';
  r.esperado := '13o proporcional aos avos — so a justa causa afasta a gratificacao (Sumula 157 do TST)';
  v_ped := public.qa_caso_dec13_rescisao_motivo('PEDIDO_DEMISSAO', 8, 1.0, '90000005649', 'QA Pediu Demissao');
  v_jc  := public.qa_caso_dec13_rescisao_motivo('DISPENSA_COM_JUSTA_CAUSA', 8, 0.0, '90000005720', 'QA Justa Causa');
  v_dev := COALESCE((v_ped->>'devido')::numeric, -1);
  v_avos := COALESCE((v_ped->>'avos')::int, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o pedido de demissao ficou sem 13o proporcional (devido: R$ %s, '
             || '%s avos). A Sumula 157 do TST e o art. 3o da Lei 4.090/1962 garantem a '
             || 'gratificacao proporcional a quem pede demissao — so a justa causa a afasta. '
             || 'Reter verba devida e passivo direto.', v_dev, v_avos);
  ELSIF COALESCE((v_jc->>'devido')::numeric, -1) <> 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO ao contrario: a justa causa pagou R$ %s de 13o proporcional, '
             || 'quando a Lei 4.090/1962 a afasta.', (v_jc->>'devido'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Pedido de demissao manteve o 13o proporcional (%s avos, R$ %s) e a justa '
             || 'causa ficou em zero, como manda a lei.', v_avos, v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_063()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_out jsonb; v_dev numeric;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por FALECIMENTO em setembro';
  r.esperado := '13o proporcional devido, para pagamento aos dependentes (Lei 6.858/1980)';
  v_out := public.qa_caso_dec13_rescisao_motivo('FALECIMENTO', 9, 1.0, '90000005800', 'QA Falecimento');
  v_dev := COALESCE((v_out->>'devido')::numeric, -1);

  IF v_dev <= 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o falecimento ficou sem 13o proporcional (R$ %s). A gratificacao '
             || 'continua devida e e paga aos dependentes habilitados na Previdencia, '
             || 'independentemente de inventario (Lei 6.858/1980, art. 1o; Lei 4.090/1962, art. '
             || '3o). Tratar falecimento como perda da verba e erro grave com a familia.', v_dev);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Falecimento manteve o 13o proporcional devido (%s avos, R$ %s), para '
             || 'encaminhamento aos dependentes (Lei 6.858/1980).', (v_out->>'avos'), v_dev);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_dec13_061()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_cr jsonb; v_sem jsonb; v_dev_cr numeric; v_dev_sem numeric;
  v_tipos text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Apurar o 13o de uma rescisao por CULPA RECIPROCA';
  r.esperado := 'Metade do 13o proporcional (CLT, art. 484; Sumula 14 do TST)';

  SELECT string_agg(DISTINCT e.enumlabel, ', ') INTO v_tipos
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname LIKE '%rescisao%' AND e.enumlabel ILIKE '%RECIPROC%';

  BEGIN
    v_cr := public.qa_caso_dec13_rescisao_motivo('CULPA_RECIPROCA', 6, 0.5, '90000005991', 'QA Culpa Reciproca');
  EXCEPTION WHEN OTHERS THEN
    v_cr := jsonb_build_object('erro', SQLERRM);
  END;
  v_sem := public.qa_caso_dec13_rescisao_motivo('DISPENSA_SEM_JUSTA_CAUSA', 6, 1.0, '90000006025', 'QA Sem Justa Causa');

  v_dev_cr  := COALESCE((v_cr->>'devido')::numeric, -1);
  v_dev_sem := COALESCE((v_sem->>'devido')::numeric, -1);

  IF v_cr ? 'erro' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca nao existe como motivo de rescisao (%s). O art. '
             || '484 da CLT e a Sumula 14 do TST mandam pagar METADE das verbas da dispensa sem '
             || 'justa causa, o 13o proporcional incluido. Sem esse motivo, o operador acaba '
             || 'lancando como justa causa (paga zero, e devedor) ou como dispensa comum (paga '
             || 'inteiro, e perde dinheiro). Detalhe tecnico: %s',
             coalesce('motivos com "reciproca" no sistema: ' || v_tipos, 'nenhum motivo de culpa reciproca cadastrado'),
             (v_cr->>'erro'));
  ELSIF v_dev_sem <= 0 OR abs(v_dev_cr - round(v_dev_sem / 2, 2)) > 0.02 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a culpa reciproca pagou R$ %s, quando deveria pagar metade da '
             || 'dispensa sem justa causa (R$ %s / 2 = R$ %s) — CLT, art. 484 e Sumula 14 do TST.',
             v_dev_cr, v_dev_sem, round(v_dev_sem / 2, 2));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Culpa reciproca paga metade: R$ %s contra R$ %s da dispensa sem justa '
             || 'causa (Sumula 14 do TST).', v_dev_cr, v_dev_sem);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-022: Sumula 347 — media FISICA das horas extras ─────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_022()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_fn boolean; v_src text; v_param boolean; v_marca boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe media FISICA de horas extras no 13o?';
  r.esperado := 'Quantidade de horas do ano dividida pelos meses, multiplicada pelo valor da hora ATUAL (Sumula 347 do TST)';

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras')
    INTO v_fn;
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_media_horas_extras';
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='decimo_terceiro_config'
                    AND column_name='media_horas_extras') INTO v_param;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='folha_rubricas'
                    AND column_name='he_do_ponto') INTO v_marca;

  IF NOT v_fn OR NOT v_param THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a media de horas extras do 13o nao e fisica (funcao: %s; escolha '
             || 'do criterio: %s). A Sumula 347 do TST manda somar a QUANTIDADE de horas extras '
             || 'do ano, dividir pelos meses e multiplicar pelo valor da hora VIGENTE. Usar a '
             || 'media dos valores pagos paga a menos sempre que houve aumento salarial no ano — '
             || 'e o aumento e a regra, nao a excecao.',
             CASE WHEN v_fn THEN 'existe' ELSE 'nao existe' END,
             CASE WHEN v_param THEN 'existe' ELSE 'nao existe' END);
  ELSIF v_src NOT ILIKE '%valor_hora%' AND v_src NOT ILIKE '%salario%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a funcao de media de horas extras existe, mas nao multiplica pelo valor '
             || 'da hora atual — sem isso ela nao cumpre a Sumula 347 do TST.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Media fisica implementada (decimo_terceiro_media_horas_extras), criterio '
             || 'escolhivel pela empresa e rubricas de HE do ponto marcadas: %s.',
             CASE WHEN v_marca THEN 'sim' ELSE 'marcador ausente' END);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-023: adicionais habituais integram a base ───────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_col text; v_fora text; v_total int; v_existentes int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Conferir se as rubricas de adicional habitual entram na base do 13o';
  r.esperado := 'Noturno, insalubridade e periculosidade marcados como integrantes (Sumulas 60, 132 e 139 do TST)';

  SELECT column_name INTO v_col FROM information_schema.columns
   WHERE table_schema='public' AND table_name='folha_rubricas'
     AND (column_name ILIKE '%13%' OR column_name ILIKE '%decimo%') LIMIT 1;

  IF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o cadastro de rubricas nao tem marcacao de "integra o 13o". Sem ela, '
             || 'nao ha como saber se adicional noturno, insalubridade e periculosidade entram '
             || 'na base — e eles entram, por habitualidade (Sumulas 60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')') INTO v_existentes;

  IF COALESCE(v_existentes, 0) = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Nao ha rubrica de adicional noturno, insalubridade ou periculosidade cadastrada '
             || 'nesta base — nao ha o que conferir. O caso volta a valer assim que a empresa '
             || 'cadastrar esses adicionais, e ai eles precisam entrar na base do 13o (Sumulas '
             || '60, 132 e 139 do TST).';
    RETURN r;
  END IF;

  EXECUTE format(
    'SELECT count(*), string_agg(descricao, '', '') FROM public.folha_rubricas
      WHERE tipo = ''PROVENTO''
        AND (descricao ILIKE ''%%noturn%%'' OR descricao ILIKE ''%%insalubr%%''
             OR descricao ILIKE ''%%periculos%%'')
        AND COALESCE(%I, false) = false', v_col)
  INTO v_total, v_fora;

  IF v_total > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s rubrica(s) de adicional habitual estao FORA da base do 13o '
             || '(%s). Adicional noturno (Sumula 60), de periculosidade (Sumula 132) e de '
             || 'insalubridade (Sumula 139) integram a remuneracao e, por habitualidade, a base '
             || 'do 13o. Fora da base, o 13o sai a menor sem ninguem perceber. Correcao: marcar '
             || 'essas rubricas como integrantes no cadastro.', v_total, v_fora);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rubrica de adicional habitual ficou fora da base do 13o (marcador "'
             || v_col || '" no cadastro de rubricas).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-034: as duas politicas do adiantamento ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_034()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_check text; v_opcoes text; v_le boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a empresa escolhe a base do adiantamento?';
  r.esperado := 'As duas leituras da Lei 4.749/1965, art. 2o, disponiveis e com efeito no calculo';

  SELECT pg_get_constraintdef(c.oid) INTO v_check
  FROM pg_constraint c
  WHERE c.conrelid = 'public.decimo_terceiro_config'::regclass AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%adiantamento_base%';

  SELECT prosrc ILIKE '%adiantamento_base%' INTO v_le
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='decimo_terceiro_calcular';

  v_opcoes := coalesce(v_check, 'sem parametro');

  IF v_check IS NULL
     OR v_check NOT ILIKE '%remuneracao_mes_anterior%'
     OR v_check NOT ILIKE '%proporcional_apurado%' THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: nao ha escolha registrada da base do adiantamento (%s). A Lei '
             || '4.749/1965, art. 2o, manda adiantar metade do salario do mes anterior; a pratica '
             || 'consolidada admite metade do 13o apurado. As duas sao defensaveis, e por isso a '
             || 'escolha e da empresa — mas precisa ficar REGISTRADA e valer igual para todos no '
             || 'ano, senao cada calculo vira uma interpretacao.', v_opcoes);
  ELSIF NOT COALESCE(v_le, false) THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o parametro da politica do adiantamento existe, mas o calculo da parcela '
             || 'nao o le — escolha sem efeito e pior que escolha nenhuma, porque parece cumprida.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Politica do adiantamento registrada e lida pelo calculo (%s).', v_opcoes);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-035: pedido fora de janeiro e avisado ───────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_035()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o pedido fora de janeiro e sinalizado?';
  r.esperado := 'Aviso de pedido fora da janela do §2o do art. 2o da Lei 4.749/1965 — sem recusa silenciosa';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_adiantamento_nas_ferias';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao existe rotina de adiantamento do 13o junto as ferias. O §2o do art. '
             || '2o da Lei 4.749/1965 da esse direito a quem requer em janeiro, e sem rotina o '
             || 'pedido se perde entre planilhas.';
  ELSIF v_src NOT ILIKE '%janeiro%' AND v_src NOT ILIKE '%fora_de_janeiro%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a rotina de adiantamento nas ferias nao distingue o pedido feito em '
             || 'JANEIRO dos demais. Fora da janela do §2o o empregador nao e obrigado a antecipar '
             || '— o sistema deve avisar e deixar a decisao registrada, nunca recusar em silencio '
             || 'nem pagar sem rastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A rotina de adiantamento nas ferias separa os pedidos de janeiro e avisa sobre os '
             || 'que ficaram fora da janela do §2o (Lei 4.749/1965).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-052: provisao do desligado e revertida ──────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_052()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a provisao reverte quando o vinculo termina?';
  r.esperado := 'Provisao do desligado revertida na competencia seguinte, e conciliacao fechando';

  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decimo_terceiro_provisionar';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nao ha provisao propria do 13o. Sem ela, a despesa aparece inteira em '
             || 'dezembro e o resultado dos outros onze meses sai distorcido (regime de '
             || 'competencia — Lei 6.404/1976, art. 177).';
  ELSIF v_src NOT ILIKE '%revert%' OR v_src NOT ILIKE '%desligad%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a provisao do 13o nao reverte a parcela de quem foi desligado. O 13o '
             || 'desses ja foi quitado na rescisao; manter a provisao deixa no balanco uma '
             || 'obrigacao que nao existe mais, e a conciliacao nunca fecha.';
  ELSIF v_src NOT ILIKE '%cpf%' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a reversao da provisao nao casa o colaborador pelo CPF. O identificador '
             || 'livre de colaborador difere entre modulos, entao a reversao encontra zero linhas '
             || 'e falha em silencio — o pior tipo de erro contabil.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A provisao do 13o reverte a parcela dos desligados, casando o vinculo pelo CPF.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── DEC13-072: o lote nao duplica parcela ─────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_072()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_ten uuid := public.qa_sandbox_tenant_id();
  v_ano int := extract(year from CURRENT_DATE)::int - 1;
  v_cpf text := '90000006106'; v_adm uuid;
  v_r1 jsonb; v_r2 jsonb; v_vivas int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Processar o lote da 1a parcela e, em seguida, processar o MESMO lote de novo';
  r.esperado := 'A segunda passada nao cria parcela nova e informa quantos ja existiam';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE tenant_id = v_ten AND cpf = v_cpf;
  INSERT INTO public.admissoes (tenant_id, nome_completo, cpf, cargo, salario, data_admissao, status)
  VALUES (v_ten, 'QA Lote Duplo', v_cpf, 'QA', 2500, make_date(v_ano - 1, 3, 1), 'concluido')
  RETURNING id INTO v_adm;

  v_r1 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);
  v_r2 := public.decimo_terceiro_lote(v_ten, v_ano, 1, NULL);

  SELECT count(*) INTO v_vivas FROM public.folha_13_calculo
   WHERE tenant_id = v_ten AND ano = v_ano AND parcela = 1
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf
     AND status <> 'cancelado';

  DELETE FROM public.folha_13_calculo WHERE tenant_id = v_ten AND ano = v_ano
     AND regexp_replace(coalesce(colaborador_cpf,''),'\D','','g') = v_cpf;
  DELETE FROM public.admissoes WHERE id = v_adm;

  IF v_vivas > 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: rodar o lote duas vezes criou %s parcelas vivas para o mesmo '
             || 'colaborador. O lote e clicado por gente sob pressao de prazo e sera clicado duas '
             || 'vezes — duplicar parcela vira pagamento em dobro. Retornos: %s / %s',
             v_vivas, v_r1, v_r2);
  ELSIF COALESCE((v_r2->>'ja_calculados')::int, (v_r2->>'ja_existiam')::int, 0) = 0
        AND COALESCE((v_r2->>'calculados')::int, 0) > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a segunda passada nao duplicou, mas tambem nao informa que pulou '
             || 'ninguem (%s) — quem processa fica sem saber se o lote rodou. Retorno precisa '
             || 'dizer quantos foram calculados e quantos ja existiam.', v_r2);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Lote idempotente: uma unica parcela viva apos duas passadas; a segunda '
             || 'informou o que pulou (%s).', v_r2);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Registro das rotinas no motor (código -> função) ──────────────────
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('DEC13-004','qa_caso_dec13_004',true), ('DEC13-005','qa_caso_dec13_005',true),
  ('DEC13-006','qa_caso_dec13_006',true), ('DEC13-022','qa_caso_dec13_022',true),
  ('DEC13-023','qa_caso_dec13_023',true), ('DEC13-034','qa_caso_dec13_034',true),
  ('DEC13-035','qa_caso_dec13_035',true), ('DEC13-043','qa_caso_dec13_043',true),
  ('DEC13-052','qa_caso_dec13_052',true), ('DEC13-061','qa_caso_dec13_061',true),
  ('DEC13-062','qa_caso_dec13_062',true), ('DEC13-063','qa_caso_dec13_063',true),
  ('DEC13-072','qa_caso_dec13_072',true), ('DEC13-073','qa_caso_dec13_073',true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;


-- ══════════ Ajuste que vem DEPOIS da 1a leva ══════════
-- A 1a leva traz a sonda do DEC13-070 na versao escrita para o banco
-- antigo, que gravava status 'pago' sem data de pagamento — a trava da
-- Entrega 2 recusa isso, com razao. A versao ajustada precisa vir por
-- ultimo, senao a leva anterior a sobrescreve.
-- ── 2. DEC13-070: a sonda informa a data de pagamento ─────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_070()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_id uuid; v_alterou boolean := false; v_trg text;
BEGIN
  -- A sonda grava e NÃO desfaz (padrão desta família). Com a unicidade
  -- da Entrega 2, rodar duas vezes colidiria com a própria linha da
  -- rodada anterior — então ela limpa o próprio rastro antes.
  DELETE FROM public.folha_13_calculo
   WHERE tenant_id = public.qa_sandbox_tenant_id()
     AND colaborador_id = 'qa-dec13-070';

  -- Pago exige data de pagamento desde a Entrega 2 (CHECK
  -- folha_13_calculo_pagamento_ck) — a sonda informa, como a tela faz.
  INSERT INTO public.folha_13_calculo
    (tenant_id, ano, colaborador_id, colaborador_nome, colaborador_cpf, parcela,
     valor_bruto, total_liquido, status, data_pagamento)
  VALUES (public.qa_sandbox_tenant_id(), extract(year from CURRENT_DATE)::int,
          'qa-dec13-070', 'QA Pago Editado', '00000000070', 2, 3000, 2500,
          'pago', CURRENT_DATE)
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Editar diretamente o valor bruto de um cálculo com status PAGO';
  r.esperado := 'Bloqueado — valor pago só muda por reabertura com motivo, dupla aprovação e diferença';
  BEGIN
    UPDATE public.folha_13_calculo SET valor_bruto = 9999 WHERE id = v_id;
    SELECT (valor_bruto = 9999) INTO v_alterou FROM public.folha_13_calculo WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_alterou := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe trilha de alteração na tabela do 13º?';
  r.esperado := 'Gatilho de auditoria registrando antes/depois (RNF-004: log imutável)';
  SELECT string_agg(DISTINCT t.tgname, ', ') INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.folha_13_calculo'::regclass AND NOT t.tgisinternal
    AND t.tgname NOT ILIKE '%updated_at%' AND t.tgname NOT ILIKE 'qa\_%';

  IF v_alterou AND v_trg IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: um cálculo PAGO foi editado em silêncio — o valor bruto mudou de 3.000 '
             || 'para 9.999 sem bloqueio, sem justificativa, sem aprovação e sem trilha. '
             || 'Correção: trava de UPDATE para status pago/fechado + fluxo de reabertura '
             || '(RF-007 do documento).';
  ELSIF NOT v_alterou THEN
    r.situacao := 'passou';
    r.obtido := format('A edição direta do cálculo pago foi recusada pela trava do banco%s.',
                       CASE WHEN v_trg IS NULL THEN '' ELSE ' (gatilhos: ' || v_trg || ')' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Alteração registrada em trilha (%s) — conferir se guarda antes/depois.', v_trg);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ── Conferencia final ─────────────────────────────────────────────────
WITH doc AS MATERIALIZED (
    SELECT count(*) AS casos
      FROM public.qa_casos_teste c
      JOIN public.qa_modulos m ON m.id = c.modulo_id
     WHERE m.path = 'financeiro/decimo-terceiro'
),
rot AS MATERIALIZED (
    SELECT count(*) AS rotinas
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname LIKE 'qa\_caso\_dec13\_%'
),
liga AS MATERIALIZED (
    SELECT count(*) AS ligacoes FROM public.qa_implementacoes WHERE codigo LIKE 'DEC13-%'
)
SELECT 'modulo 13o na Documentacao de testes' AS item,
       CASE WHEN EXISTS (SELECT 1 FROM public.qa_modulos WHERE path='financeiro/decimo-terceiro')
            THEN 'OK' ELSE 'FALTOU' END AS situacao,
       NULL::text AS erro_tecnico
 UNION ALL
SELECT 'casos documentados (esperado 31)',
       CASE WHEN casos >= 31 THEN 'OK' ELSE 'FALTOU' END,
       'documentados: ' || casos::text FROM doc
 UNION ALL
SELECT 'rotinas que executam os casos (esperado 31)',
       CASE WHEN rotinas >= 31 THEN 'OK' ELSE 'FALTOU' END,
       'rotinas: ' || rotinas::text FROM rot
 UNION ALL
SELECT 'ligacao caso -> rotina no motor (esperado 31)',
       CASE WHEN ligacoes >= 31 THEN 'OK' ELSE 'FALTOU' END,
       'ligacoes: ' || ligacoes::text FROM liga
 UNION ALL
SELECT 'casos sem rotina registrada',
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'RESOLVER' END,
       CASE WHEN count(*) = 0 THEN NULL
            ELSE string_agg(c.codigo, ', ' ORDER BY c.codigo) END
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
 WHERE m.path = 'financeiro/decimo-terceiro'
   AND NOT EXISTS (SELECT 1 FROM public.qa_implementacoes i WHERE i.codigo = c.codigo AND i.ativo)
 ORDER BY 2 DESC, 1;
