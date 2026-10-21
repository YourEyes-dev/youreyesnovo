-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 03b: Compliance SST, Terceiros e Documentos
--
-- PARA QUE SERVE
-- Preenche, para a "Metalurgica Exemplo Ltda" (100% ficticia, parte 00), as telas
--   /compliance-sst  documentos SST (PGR atual e anterior, PCMSO, LTCAT, AET, AEP,
--                    laudos, APR, dosimetria) com a analise ja gravada (revisao dos
--                    dados, relatorio de conformidade, alertas e acoes), calendario
--                    de vencimentos e Ordens de Servico da NR-1 por colaborador;
--   /terceiros       empresas terceiras, trabalhadores, documentos e treinamentos
--                    (validos, a vencer, vencidos e pendentes), permissoes de
--                    trabalho, vencimentos e trilhas de integracao com link publico;
--   /documentos      arvore de pastas da empresa, documentos com vencimentos,
--                    mapa de conformidade, radar de governanca, painel PDCA,
--                    notificacoes de vencimento e historico de auditoria.
-- Tambem grava as acoes do plano de acao de origem compliance_sst.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, DEPOIS da parte 00 (e de preferencia depois
-- da parte 03a, que traz os acidentes e as acoes que o painel PDCA tambem le).
-- O arquivo se RECUSA a rodar fora da homologacao/teste (confere app_config.supabase_url).
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, CPFs 900.000.0XX (via demo_cpf), CNPJs e
--     registros profissionais ficticios, arquivos so com caminho de mentira (demo/...).
--   - So toca o tenant demo (d3e00000-...-0001). Nenhum UPDATE/DELETE em linha de outro tenant.
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe". Rodar de novo nao duplica.
--     Pastas que ja existam com o mesmo nome e a mesma pasta-pai sao reaproveitadas.
--   - Nao cria tabela. Roda numa transacao so; cada bloco tem rede de seguranca
--     (EXCEPTION WHEN OTHERS THEN RAISE NOTICE) para nao derrubar os demais.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) Trava de ambiente (so homologacao/teste) + conferencia da base (parte 00)
-- ---------------------------------------------------------------------------
DO $trava$
DECLARE
  v_url text;
BEGIN
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url' LIMIT 1);
  IF v_url IS NULL
     OR (v_url NOT ILIKE '%fgsblefvdabgdouipigz%' AND v_url NOT ILIKE '%bmehdgthciuvdbvutsdv%') THEN
    RAISE EXCEPTION
      'RECUSADO: app_config.supabase_url (%) nao e a homologacao nem o teste. Os dados de demonstracao nunca entram em producao.',
      COALESCE(v_url, '(vazio)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'RECUSADO: o tenant demo nao existe. Rode primeiro a parte 00 (parte_00_base_empresa_demo.sql).';
  END IF;
END $trava$;

-- ---------------------------------------------------------------------------
-- (1) Compliance SST — documentos legais com a analise ja gravada
-- ---------------------------------------------------------------------------
DO $sst1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- e = dias de emissao atras; v = dias ate o vencimento (negativo = vencido); ia = dados extraidos; md = relatorio narrativo
  INSERT INTO public.sst_documentos (
    id, tenant_id, empresa_id, tipo, arquivo_url, arquivo_nome, arquivo_tamanho, data_emissao, data_vigencia,
    profissional_responsavel, empresa_emissora, unidade, cnpj_relacionado, status, analise_ia, analise_ia_status,
    analise_ia_confianca, criado_por, criado_por_nome, observacoes, created_at
  )
  SELECT public.demo_id('sst_doc:' || x.k), v_t, v_e, x.tipo, 'demo/sst/' || x.arq, x.arq, x.tam, CURRENT_DATE - x.e, CURRENT_DATE + x.v,
         x.prof, 'Prevenir Consultoria em SST Ltda (demonstração)', 'Metalúrgica Exemplo', '98.765.432/0001-02',
         CASE WHEN x.v < 0 THEN 'vencido' ELSE 'vigente' END,
         CASE WHEN x.ia IS NULL THEN NULL
              ELSE x.ia || jsonb_build_object('resultado', x.md, 'data', (now() - ((x.e - 2) || ' days')::interval)) END,
         CASE WHEN x.ia IS NULL THEN 'pendente' ELSE 'concluida' END,
         x.conf, v_uid, v_nome, x.obs, (CURRENT_DATE - x.e) + TIME '11:00'
  FROM (VALUES
    ('pgr_atual', 'PGR', 'PGR_2026_Metalurgica_Exemplo.pdf', 4820000, 200, 165, 'Carlos Eduardo Menezes Prado (Eng. de Segurança, CREA-SC 100001-0)', 0.93::numeric,
      'PGR vigente, revisão anual.',
      '{"tipo_documento":"PGR","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"cnpj":{"valor":"98.765.432/0001-02","confianca":"alta"},"data_emissao":{"valor":"emissão há cerca de 200 dias","confianca":"alta"},"vigencia":{"valor":"12 meses","confianca":"alta"},"grau_de_risco":{"valor":"3","confianca":"alta"},"metodologia":{"valor":"Matriz de risco 5x5 (probabilidade x severidade)","confianca":"media"}},"estrutura_organizacional":{"unidades":[{"nome":"Matriz Joinville","endereco":"Rua das Indústrias, 1000, Distrito Industrial"},{"nome":"Filial Curitiba","endereco":"Av. das Araucárias, 500"},{"nome":"Centro de Distribuição Itajaí","endereco":"Rod. BR-101, km 110"}],"setores":["Usinagem CNC","Solda","Montagem","Manutenção","Expedição","Administrativo"],"departamentos":["Produção","Manutenção","Logística","Administrativo","Recursos Humanos","Comercial"]},"funcoes_atividades":[{"cargo":"Operador de Usinagem CNC","setor":"Produção","atividades":["Preparar e operar tornos e centros de usinagem","Trocar ferramentas e medir peças","Remover cavacos e abastecer fluido de corte"]},{"cargo":"Soldador","setor":"Produção","atividades":["Soldar estruturas pelos processos MIG/MAG","Esmerilhar e acabar cordões de solda","Posicionar peças com ponte rolante"]},{"cargo":"Eletricista de Manutenção","setor":"Manutenção","atividades":["Manter painéis e circuitos de comando","Executar manutenção em instalações energizadas conforme NR-10","Trabalhar em altura em eletrocalhas"]},{"cargo":"Operador de Empilhadeira","setor":"Logística","atividades":["Movimentar paletes e bobinas","Carregar e descarregar caminhões","Inspecionar a empilhadeira no início do turno"]}],"inventario_riscos":[{"risco":"Ruído contínuo acima de 85 dB(A)","tipo_risco":"Físico","setor":"Produção","funcao":"Operador de Usinagem CNC","fonte_geradora":"Tornos e centros de usinagem","intensidade":"87 a 92 dB(A)","danos":"Perda auditiva induzida por ruído","metodologia":"Dosimetria","controles_existentes":["Protetor auricular plug","Treinamento de conservação auditiva"],"confianca":"alta"},{"risco":"Fumos metálicos","tipo_risco":"Químico","setor":"Produção","funcao":"Soldador","fonte_geradora":"Soldagem MIG/MAG","intensidade":"Acima do nível de ação para manganês","danos":"Doenças respiratórias, febre dos fumos metálicos","metodologia":"Amostragem pessoal","controles_existentes":["Exaustão localizada","Respirador semifacial com filtro P2"],"confianca":"alta"},{"risco":"Choque elétrico","tipo_risco":"Acidente","setor":"Manutenção","funcao":"Eletricista de Manutenção","fonte_geradora":"Painéis e circuitos energizados","intensidade":"Baixa tensão (até 440 V)","danos":"Queimaduras e fibrilação ventricular","metodologia":"Qualitativa","controles_existentes":["Bloqueio e etiquetagem","Luvas isolantes classe 2","Treinamento NR-10"],"confianca":"alta"},{"risco":"Esmagamento por prensa","tipo_risco":"Acidente","setor":"Produção","funcao":"Montador de Estruturas Metálicas","fonte_geradora":"Prensa hidráulica","intensidade":"Alta","danos":"Amputação e esmagamento","metodologia":"APR","controles_existentes":["Comando bimanual","Treinamento"],"confianca":"media"},{"risco":"Atropelamento por empilhadeira","tipo_risco":"Acidente","setor":"Logística","funcao":"Operador de Empilhadeira","fonte_geradora":"Tráfego no pátio","intensidade":"Média","danos":"Politraumatismo","metodologia":"Qualitativa","controles_existentes":["Faixa de pedestres","Alarme de ré"],"confianca":"media"},{"risco":"Levantamento manual de cargas","tipo_risco":"Ergonômico","setor":"Logística","funcao":"Auxiliar de Logística","fonte_geradora":"Caixas de 25 kg","intensidade":"Acima do recomendado","danos":"Lombalgia e hérnia de disco","metodologia":"AEP","controles_existentes":["Orientação de postura"],"confianca":"media"}],"plano_acao":[{"what":"Adequar as prensas e a guilhotina à NR-12 com laudo de conformidade","why":"Risco de esmagamento e proteções móveis burladas","where":"Montagem e corte","who":"Supervisor de Manutenção","when":"60 dias","how":"Projeto de adequação, instalação em parada programada e laudo","how_much":"R$ 24.000","prioridade":"alta","setor":"Produção","trecho_origem":"Capítulo 7, medidas de prevenção"},{"what":"Incluir o risco psicossocial no inventário conforme NR-1","why":"Exigência do item 1.5.3.1.4 da NR-1","where":"Toda a empresa","who":"SESMT e RH","when":"90 dias","how":"Aplicar instrumento validado e consolidar no inventário","how_much":"R$ 6.000","prioridade":"alta","setor":"Todos","trecho_origem":"Capítulo 5, inventário"},{"what":"Realizar avaliação quantitativa de fumos metálicos na solda","why":"Última avaliação com mais de 12 meses","where":"Solda","who":"Higienista contratado","when":"45 dias","how":"Amostragem pessoal por turno","how_much":"R$ 4.500","prioridade":"media","setor":"Produção","trecho_origem":"Capítulo 6, avaliação de agentes"},{"what":"Implantar plano de trabalho em altura para manutenção de telhado e eletrocalhas","why":"NR-35 sem procedimento documentado","where":"Manutenção","who":"Supervisor de Manutenção","when":"30 dias","how":"Permissão de trabalho, linhas de vida e checklist de EPI","how_much":"R$ 9.800","prioridade":"alta","setor":"Manutenção","trecho_origem":"Capítulo 7"},{"what":"Antecipar a revisão do PGR para incluir a nova célula de solda","why":"Mudança de processo","where":"Produção","who":"Eng. de Segurança","when":"120 dias","how":"Revisão do inventário e consulta à CIPA","how_much":"R$ 3.200","prioridade":"baixa","setor":"Produção","trecho_origem":"Capítulo 9, revisão"}],"responsaveis_tecnicos":[{"nome":"Carlos Eduardo Menezes Prado","formacao":"Engenheiro de Segurança do Trabalho","conselho":"CREA-SC","registro":"CREA-SC 100001-0","funcao_no_doc":"Responsável pela elaboração"},{"nome":"Rodrigo Pires Vasconcelos","formacao":"Técnico de Segurança do Trabalho","conselho":"MTE","registro":"MTE-SC 0001","funcao_no_doc":"Apoio técnico"}],"pendencias":[{"campo":"Riscos psicossociais","motivo":"Não há dimensões psicossociais no inventário","severidade":"media"},{"campo":"Assinatura da diretoria","motivo":"Página de aprovação sem assinatura digital","severidade":"baixa"}],"score_qualidade":{"geral":84,"dados_gerais":92,"inventario":82,"plano_acao":78,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: PGR 2026\n\n**Documento:** PGR da Metalúrgica Exemplo Ltda. Auditoria com base nas NR-1, NR-9, NR-12, NR-17 e NR-35.\n\n## Panorama do inventário\nForam identificados 6 grupos de riscos relevantes distribuídos em Produção, Manutenção e Logística, com 5 ações no plano.\n\n## 🔴 Alertas Críticos\n- Máquinas de corte e dobra sem comprovação de adequação à NR-12 (intertravamentos e paradas de emergência) em três equipamentos.\n- Ausência de procedimento documentado de trabalho em altura (NR-35) para a manutenção de telhado e eletrocalhas.\n\n## 🟠 Alertas Técnicos\n- Inventário não contempla o risco psicossocial exigido pelo item 1.5.3.1.4 da NR-1.\n- Ruído acima do limite de ação (NR-15, Anexo 1) no esmerilhamento, sem dobra de proteção documentada.\n- Fumos metálicos da soldagem sem avaliação quantitativa nos últimos 12 meses (NR-9).\n\n## 🟡 Pontos de Atenção\n- Revisão anual prevista para o próximo trimestre; antecipar para absorver a nova célula de solda.\n- Eventos S-2240 do eSocial devem refletir o inventário atualizado após a revisão.\n\n## Plano de Ação Recomendado\n1. Adequar as prensas e a guilhotina à NR-12 com laudo de conformidade em até 60 dias. Responsável: Supervisor de Manutenção.\n2. Incluir o risco psicossocial no inventário conforme a NR-1. Prazo: 90 dias.\n3. Realizar avaliação quantitativa de fumos metálicos na solda. Prazo: 45 dias.\n4. Implantar plano de trabalho em altura com permissão de trabalho e linhas de vida. Prazo: 30 dias.\n5. Antecipar a revisão do PGR para incluir a nova célula de solda. Prazo: 120 dias.\n'),
    ('pgr_anterior', 'PGR', 'PGR_2025_Metalurgica_Exemplo.pdf', 4310000, 580, -215, 'Carlos Eduardo Menezes Prado (Eng. de Segurança, CREA-SC 100001-0)', 0.9::numeric,
      'Versão anterior substituída pela revisão de 2026.',
      '{"tipo_documento":"PGR","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"vigencia":{"valor":"12 meses","confianca":"alta"}},"inventario_riscos":[{"risco":"Ruído contínuo acima de 85 dB(A)","tipo_risco":"Físico","setor":"Produção","confianca":"alta"},{"risco":"Choque elétrico","tipo_risco":"Acidente","setor":"Manutenção","confianca":"alta"},{"risco":"Fumos metálicos","tipo_risco":"Químico","setor":"Produção","confianca":"media"}],"plano_acao":[{"what":"Substituir intertravamentos de máquinas antigas","prioridade":"alta","setor":"Produção","prazo":"180 dias"}],"responsaveis_tecnicos":[{"nome":"Carlos Eduardo Menezes Prado","formacao":"Engenheiro de Segurança do Trabalho","conselho":"CREA-SC","registro":"CREA-SC 100001-0"}],"pendencias":[],"score_qualidade":{"geral":71,"dados_gerais":80,"inventario":68,"plano_acao":60,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: PGR 2025\n\n**Documento:** versão anterior do PGR, com vigência encerrada.\n\n## 🔴 Alertas Críticos\n- Documento com vigência expirada: não cobre mais a operação atual e foi substituído pela revisão de 2026.\n\n## 🟡 Pontos de Atenção\n- Ordens de Serviço baseadas nesta versão precisam ser reemitidas a partir do PGR vigente.\n'),
    ('pcmso', 'PCMSO', 'PCMSO_2026_Metalurgica_Exemplo.pdf', 2980000, 170, 195, 'Dra. Helena Monteiro Alcântara (Médica do Trabalho, CRM-SC 00001)', 0.91::numeric,
      'PCMSO vigente, coordenação médica terceirizada.',
      '{"tipo_documento":"PCMSO","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"medico_coordenador":{"valor":"Dra. Helena Monteiro Alcântara","confianca":"alta"},"vigencia":{"valor":"12 meses","confianca":"alta"}},"matriz_exames":[{"cargo":"Operador de Usinagem CNC","exames":["Clínico","Audiometria"],"periodicidade":"12 meses"},{"cargo":"Soldador","exames":["Clínico","Audiometria","Espirometria"],"periodicidade":"12 meses"},{"cargo":"Eletricista de Manutenção","exames":["Clínico","Eletrocardiograma"],"periodicidade":"12 meses"},{"cargo":"Operador de Empilhadeira","exames":["Clínico","Acuidade visual"],"periodicidade":"12 meses"}],"inventario_riscos":[{"risco":"Ruído contínuo","tipo_risco":"Físico","setor":"Produção","confianca":"alta"},{"risco":"Fumos metálicos","tipo_risco":"Químico","setor":"Produção","confianca":"alta"}],"plano_acao":[{"what":"Realizar os exames periódicos em atraso de soldadores e operadores","prioridade":"alta","setor":"Produção","prazo":"30 dias"},{"what":"Incluir avaliação de saúde mental no exame periódico conforme PGR","prioridade":"media","setor":"Todos","prazo":"90 dias"}],"responsaveis_tecnicos":[{"nome":"Helena Monteiro Alcântara","formacao":"Médica do Trabalho","conselho":"CRM-SC","registro":"CRM-SC 00001","funcao_no_doc":"Coordenadora do PCMSO"}],"pendencias":[{"campo":"Relatório anual","motivo":"Relatório analítico do ano anterior não localizado","severidade":"media"}],"score_qualidade":{"geral":82,"dados_gerais":90,"inventario":78,"plano_acao":74,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: PCMSO 2026\n\n**Documento:** PCMSO coordenado por médica do trabalho, alinhado ao PGR vigente.\n\n## 🟠 Alertas Técnicos\n- Matriz de exames cobre os cargos com insalubridade, mas não prevê avaliação de saúde mental exigida pela revisão da NR-1.\n- Relatório analítico anual do PCMSO anterior não foi localizado no arquivo da empresa.\n\n## 🟡 Pontos de Atenção\n- Exames periódicos de parte dos soldadores e operadores estão próximos do vencimento.\n- Alinhar o evento S-2220 do eSocial com a matriz de exames atualizada.\n\n## Plano de Ação Recomendado\n1. Realizar os exames periódicos em atraso de soldadores e operadores em até 30 dias.\n2. Incluir avaliação de saúde mental no exame periódico conforme o PGR. Prazo: 90 dias.\n'),
    ('ltcat', 'LTCAT', 'LTCAT_2026_Metalurgica_Exemplo.pdf', 3560000, 150, 340, 'Carlos Eduardo Menezes Prado (Eng. de Segurança, CREA-SC 100001-0)', 0.88::numeric,
      'LTCAT base do PPP e da aposentadoria especial.',
      '{"tipo_documento":"LTCAT","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"vigencia":{"valor":"Até alteração do ambiente","confianca":"media"}},"inventario_riscos":[{"risco":"Ruído 92 dB(A)","tipo_risco":"Físico","setor":"Produção","funcao":"Soldador","intensidade":"92 dB(A)","metodologia":"NHO-01","confianca":"alta"},{"risco":"Manganês em fumos de solda","tipo_risco":"Químico","setor":"Produção","funcao":"Soldador","intensidade":"0,12 mg/m3","metodologia":"NHO-08","confianca":"media"},{"risco":"Óleos e graxas minerais","tipo_risco":"Químico","setor":"Manutenção","funcao":"Mecânico de Manutenção","metodologia":"Qualitativa","confianca":"media"}],"plano_acao":[{"what":"Reavaliar o ruído do esmerilhamento após o enclausuramento parcial","prioridade":"media","setor":"Produção","prazo":"180 dias"}],"responsaveis_tecnicos":[{"nome":"Carlos Eduardo Menezes Prado","formacao":"Engenheiro de Segurança do Trabalho","conselho":"CREA-SC","registro":"CREA-SC 100001-0"}],"pendencias":[{"campo":"Agentes químicos","motivo":"Faltam laudos de amostragem de 2 dos 3 agentes","severidade":"media"}],"score_qualidade":{"geral":78,"dados_gerais":85,"inventario":75,"plano_acao":65,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: LTCAT 2026\n\n**Documento:** LTCAT com caracterização de agentes nocivos por função.\n\n## 🟠 Alertas Técnicos\n- Exposição ao manganês sem laudo de amostragem anexado no caso dos soldadores.\n- Metodologia do agente óleos e graxas minerais apenas qualitativa, sem registro de tempo de exposição.\n\n## 🟡 Pontos de Atenção\n- Os eventos S-2240 devem ser conferidos com os agentes e as intensidades do LTCAT.\n- Reavaliar o ruído do esmerilhamento após as melhorias previstas no PGR.\n\n## Plano de Ação Recomendado\n1. Reavaliar o ruído do esmerilhamento após o enclausuramento parcial em até 180 dias.\n'),
    ('aet', 'AET', 'AET_Montagem_e_Logistica_2026.pdf', 2210000, 90, 275, 'Dra. Bruna Albuquerque Seixas (Ergonomista, CREFITO-10 000001-F)', 0.86::numeric,
      'AET dos postos da montagem e da logística.',
      '{"tipo_documento":"AET","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"postos":{"valor":"Montagem e Logística","confianca":"alta"}},"fatores_ergonomicos":[{"fator":"Levantamento manual de cargas","setor":"Logística","nivel":"alto"},{"fator":"Altura de bancada inadequada","setor":"Montagem","nivel":"alto"},{"fator":"Pausas insuficientes","setor":"Montagem","nivel":"medio"}],"inventario_riscos":[{"risco":"Levantamento manual de caixas de 25 kg","tipo_risco":"Ergonômico","setor":"Logística","funcao":"Auxiliar de Logística","confianca":"alta"}],"plano_acao":[{"what":"Adquirir bancadas de altura regulável para a montagem","prioridade":"alta","setor":"Montagem","prazo":"90 dias"},{"what":"Fornecer carrinhos e auxílios mecânicos na armazenagem","prioridade":"alta","setor":"Logística","prazo":"60 dias"}],"responsaveis_tecnicos":[{"nome":"Bruna Albuquerque Seixas","formacao":"Fisioterapeuta ergonomista","conselho":"CREFITO","registro":"CREFITO-10 000001-F"}],"pendencias":[],"score_qualidade":{"geral":80,"dados_gerais":88,"inventario":76,"plano_acao":72,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: AET\n\n**Documento:** AET dos postos de montagem e logística (NR-17).\n\n## 🟠 Alertas Técnicos\n- Levantamento manual de caixas de 25 kg acima do recomendado para o posto de auxiliar de logística (item 17.2 da NR-17).\n- Bancadas fixas acima da altura ideal em quatro dos seis postos da montagem.\n\n## 🟡 Pontos de Atenção\n- Estender a AET aos postos de usinagem e solda no próximo ciclo.\n\n## Plano de Ação Recomendado\n1. Adquirir bancadas de altura regulável para a montagem em até 90 dias.\n2. Fornecer carrinhos e auxílios mecânicos na armazenagem em até 60 dias.\n'),
    ('aep', 'AEP', 'AEP_Administrativo_2026.pdf', 1250000, 335, 30, 'Dra. Bruna Albuquerque Seixas (Ergonomista, CREFITO-10 000001-F)', 0.84::numeric,
      'AEP dos postos administrativos; vence em breve.',
      '{"tipo_documento":"AEP","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"postos":{"valor":"Administrativo, RH e Comercial","confianca":"alta"}},"inventario_riscos":[{"risco":"Postura sentada prolongada","tipo_risco":"Ergonômico","setor":"Administrativo","confianca":"alta"},{"risco":"Monitor abaixo da altura dos olhos","tipo_risco":"Ergonômico","setor":"Comercial","confianca":"alta"}],"plano_acao":[{"what":"Fornecer suportes de monitor e teclado externo","prioridade":"baixa","setor":"Administrativo","prazo":"60 dias"}],"responsaveis_tecnicos":[{"nome":"Bruna Albuquerque Seixas","formacao":"Fisioterapeuta ergonomista","conselho":"CREFITO","registro":"CREFITO-10 000001-F"}],"pendencias":[],"score_qualidade":{"geral":88,"dados_gerais":92,"inventario":85,"plano_acao":80,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: AEP Administrativo\n\n**Documento:** AEP dos postos de escritório.\n\n## 🟡 Pontos de Atenção\n- A avaliação vence em 30 dias; programar a reavaliação dos postos administrativos.\n- Monitores abaixo da altura dos olhos em parte dos postos comerciais.\n\n## Plano de Ação Recomendado\n1. Fornecer suportes de monitor e teclado externo em até 60 dias.\n'),
    ('ins', 'LAUDO_INSALUBRIDADE', 'Laudo_Insalubridade_2026.pdf', 1840000, 120, 245, 'Carlos Eduardo Menezes Prado (Eng. de Segurança, CREA-SC 100001-0)', 0.87::numeric,
      'Laudo de insalubridade: ruído e agentes químicos.',
      '{"tipo_documento":"LAUDO_INSALUBRIDADE","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"}},"inventario_riscos":[{"risco":"Ruído contínuo acima de 85 dB(A)","tipo_risco":"Físico","setor":"Produção","funcao":"Operador de Usinagem CNC","intensidade":"Grau médio (20%)","metodologia":"NR-15 Anexo 1","confianca":"alta"},{"risco":"Fumos metálicos e radiação não ionizante","tipo_risco":"Químico","setor":"Produção","funcao":"Soldador","intensidade":"Grau médio (20%)","metodologia":"NR-15","confianca":"media"}],"plano_acao":[],"responsaveis_tecnicos":[{"nome":"Carlos Eduardo Menezes Prado","formacao":"Engenheiro de Segurança do Trabalho","conselho":"CREA-SC","registro":"CREA-SC 100001-0"}],"pendencias":[],"score_qualidade":{"geral":85,"dados_gerais":88,"inventario":84,"plano_acao":70,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: Laudo de Insalubridade\n\n**Documento:** caracterização de insalubridade por função, base para o adicional.\n\n## 🟡 Pontos de Atenção\n- O adicional de insalubridade deve ser conferido na folha para os cargos de operador de usinagem e soldador.\n- Revisar o laudo quando o enclausuramento do esmerilhamento for concluído.\n'),
    ('per', 'LAUDO_PERICULOSIDADE', 'Laudo_Periculosidade_Eletricidade_2025.pdf', 1520000, 420, -20, 'Carlos Eduardo Menezes Prado (Eng. de Segurança, CREA-SC 100001-0)', 0.85::numeric,
      'Laudo de periculosidade (eletricidade) com revisão vencida.',
      '{"tipo_documento":"LAUDO_PERICULOSIDADE","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"}},"inventario_riscos":[{"risco":"Exposição a sistema elétrico de potência","tipo_risco":"Acidente","setor":"Manutenção","funcao":"Eletricista de Manutenção","intensidade":"Periculosidade (30%)","metodologia":"NR-16 Anexo 4","confianca":"alta"}],"plano_acao":[{"what":"Renovar o laudo de periculosidade do setor elétrico","prioridade":"alta","setor":"Manutenção","prazo":"15 dias"}],"responsaveis_tecnicos":[{"nome":"Carlos Eduardo Menezes Prado","formacao":"Engenheiro de Segurança do Trabalho","conselho":"CREA-SC","registro":"CREA-SC 100001-0"}],"pendencias":[{"campo":"Vigência","motivo":"Laudo com revisão anual vencida","severidade":"critica"}],"score_qualidade":{"geral":66,"dados_gerais":75,"inventario":70,"plano_acao":50,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: Laudo de Periculosidade\n\n**Documento:** laudo de periculosidade por eletricidade para a equipe de manutenção elétrica.\n\n## 🔴 Alertas Críticos\n- Laudo com revisão vencida há 20 dias: o enquadramento dos eletricistas não está respaldado por documento vigente (NR-16).\n\n## 🟡 Pontos de Atenção\n- Conferir o pagamento do adicional de periculosidade dos quatro eletricistas durante a renovação.\n\n## Plano de Ação Recomendado\n1. Renovar o laudo de periculosidade do setor elétrico em até 15 dias.\n'),
    ('apr', 'APR', 'APR_Manutencao_de_Prensas_2026.pdf', 980000, 320, 45, 'Rodrigo Pires Vasconcelos (Técnico de Segurança, MTE-SC 0001)', 0.82::numeric,
      'APR da manutenção de prensas; revisão em 45 dias.',
      '{"tipo_documento":"APR","dados_gerais":{"empresa":{"valor":"Metalúrgica Exemplo Ltda","confianca":"alta"},"atividade":{"valor":"Manutenção de prensas hidráulicas","confianca":"alta"}},"inventario_riscos":[{"risco":"Partida inesperada da prensa","tipo_risco":"Acidente","setor":"Manutenção","funcao":"Mecânico de Manutenção","controles_existentes":["Bloqueio e etiquetagem","Calço de segurança"],"confianca":"alta"},{"risco":"Vazamento de óleo hidráulico pressurizado","tipo_risco":"Acidente","setor":"Manutenção","funcao":"Mecânico de Manutenção","controles_existentes":["Despressurização antes da intervenção"],"confianca":"media"}],"plano_acao":[{"what":"Revisar a APR após a adequação da prensa 02 à NR-12","prioridade":"media","setor":"Manutenção","prazo":"45 dias"}],"responsaveis_tecnicos":[{"nome":"Rodrigo Pires Vasconcelos","formacao":"Técnico de Segurança do Trabalho","conselho":"MTE","registro":"MTE-SC 0001"}],"pendencias":[],"score_qualidade":{"geral":81,"dados_gerais":85,"inventario":80,"plano_acao":70,"responsaveis":100}}',
      E'# Relatório de Conformidade SST: APR da manutenção de prensas\n\n**Documento:** análise preliminar de risco para intervenções em prensas.\n\n## 🟡 Pontos de Atenção\n- A APR deve ser revisada após a instalação da cortina de luz na prensa 02.\n- Registrar na APR a verificação do calço de segurança antes de cada intervenção.\n\n## Plano de Ação Recomendado\n1. Revisar a APR após a adequação da prensa 02 à NR-12 em até 45 dias.\n'),
    ('dosimetria', 'OUTROS', 'Dosimetria_de_Ruido_2026.pdf', 1130000, 60, 305, 'Rodrigo Pires Vasconcelos (Técnico de Segurança, MTE-SC 0001)', NULL::numeric,
      'Relatório de dosimetria de ruído aguardando análise.', NULL::jsonb, NULL::text),
    ('ppra', 'PPRA', 'PPRA_2023_Legado.pdf', 2650000, 1100, -735, 'Consultoria anterior (demonstração)', NULL::numeric,
      'Programa legado substituído pelo PGR; guardado para histórico.', NULL::jsonb, NULL::text)
  ) AS x(k, tipo, arq, tam, e, v, prof, conf, obs, ia, md)
  WHERE NOT EXISTS (SELECT 1 FROM public.sst_documentos s WHERE s.id = public.demo_id('sst_doc:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Compliance SST (documentos) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $sst1$;

-- ---------------------------------------------------------------------------
-- (2) Compliance SST — Ordens de Servico (NR-1) por colaborador e acoes de conformidade
-- ---------------------------------------------------------------------------
DO $sst2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Colaboradores sem OS (pendentes): os 3 contratados ha poucos dias (57 a 59), alguns administrativos e comerciais
  INSERT INTO public.ordens_servico (
    id, tenant_id, empresa_id, colaborador_id, cargo_id, cargo_nome, setor_nome, numero_sequencial, ano, pgr_id,
    conteudo_html, conteudo_json, data_emissao, data_vigencia, status, assinada_em, assinatura_geo, assinatura_ip, assinatura_hash,
    responsavel_emissao_id, responsavel_emissao_nome, responsavel_tecnico_nome, responsavel_tecnico_registro,
    motivo_reemissao, versao, criado_por, created_at
  )
  SELECT public.demo_id('ordem_servico:' || o.n), v_t, v_e, a.id, a.cargo_id, a.cargo, a.departamento, 0,
         EXTRACT(YEAR FROM (CURRENT_DATE - o.emissao))::int,
         CASE WHEN o.st IN ('desatualizada', 'vencida') THEN public.demo_id('sst_doc:pgr_anterior') ELSE public.demo_id('sst_doc:pgr_atual') END,
         '<h2>ORDEM DE SERVIÇO DE SEGURANÇA E SAÚDE NO TRABALHO</h2>'
           || '<p><strong>Empresa:</strong> Metalúrgica Exemplo Ltda, CNPJ 98.765.432/0001-02.</p>'
           || '<p><strong>Colaborador:</strong> ' || a.nome_completo || ' &middot; <strong>Cargo:</strong> ' || a.cargo || ' &middot; <strong>Setor:</strong> ' || a.departamento || '</p>'
           || '<h3>1. Riscos ocupacionais da função (PGR)</h3><ul>' || r.riscos || '</ul>'
           || '<h3>2. Medidas de controle e EPI</h3><ul>' || r.medidas || '</ul>'
           || '<h3>3. Obrigações do trabalhador</h3><ul><li>Cumprir as normas de segurança e usar corretamente os EPI fornecidos.</li><li>Comunicar ao superior qualquer condição de risco.</li><li>Participar dos treinamentos e dos exames médicos.</li></ul>'
           || '<h3>4. Proibições</h3><ul><li>Operar máquinas sem treinamento ou com proteções removidas.</li><li>Recusar o uso de EPI obrigatório.</li></ul>'
           || '<h3>5. Penalidades</h3><p>O descumprimento sujeita o trabalhador às medidas disciplinares previstas em lei (art. 158 da CLT).</p>'
           || '<p><em>Documento emitido com base no PGR vigente. Demonstração.</em></p>',
         jsonb_build_object('colaborador', a.nome_completo, 'cargo', a.cargo, 'setor', a.departamento, 'versao_pgr', CASE WHEN o.st IN ('desatualizada', 'vencida') THEN '2025' ELSE '2026' END),
         CURRENT_DATE - o.emissao, CURRENT_DATE - o.emissao + 365,
         o.st,
         CASE WHEN o.st IN ('assinada', 'desatualizada', 'vencida') THEN (CURRENT_DATE - o.emissao + (o.n % 4)) + TIME '08:50' END,
         CASE WHEN o.st IN ('assinada', 'desatualizada', 'vencida') THEN jsonb_build_object('lat', -26.30, 'lng', -48.84, 'precisao_m', 25) END,
         CASE WHEN o.st IN ('assinada', 'desatualizada', 'vencida') THEN '10.20.1.' || (10 + o.n)::text END,
         CASE WHEN o.st IN ('assinada', 'desatualizada', 'vencida') THEN md5('demo-os-' || o.n::text) END,
         v_uid, v_nome, 'Carlos Eduardo Menezes Prado', 'CREA-SC 100001-0',
         CASE WHEN o.st = 'cancelada' THEN 'Emitida com cargo errado; cancelada e reemitida' END,
         1, v_uid, (CURRENT_DATE - o.emissao) + TIME '09:00'
  FROM (
    SELECT n,
           CASE
             WHEN n = 20 THEN 'cancelada'
             WHEN n % 10 IN (1, 2, 3, 4, 5, 6) THEN 'assinada'
             WHEN n % 10 = 7 THEN 'aguardando_assinatura'
             WHEN n % 10 = 8 THEN 'desatualizada'
             WHEN n % 10 = 9 THEN 'vencida'
             ELSE 'rascunho'
           END AS st,
           CASE
             WHEN n % 10 = 8 THEN 330 + (n % 20)
             WHEN n % 10 = 9 THEN 400 + (n % 25)
             WHEN n % 10 = 7 THEN 3 + (n % 5)
             WHEN n % 10 = 0 THEN 1 + (n % 3)
             ELSE 20 + ((n * 17) % 160)
           END AS emissao
    FROM generate_series(1, 59) AS n
    WHERE n NOT IN (4, 11, 26, 33, 38, 47, 53, 56, 57, 58, 59)
  ) o
  JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || o.n) AND a.tenant_id = v_t
  JOIN (VALUES
    ('Operador de Usinagem CNC', '<li>Ruído contínuo acima de 85 dB(A)</li><li>Projeção de cavacos e fluido de corte</li><li>Esmagamento e corte em máquinas</li><li>Postura em pé prolongada</li>', '<li>Protetor auricular, óculos e luva anticorte</li><li>Proteções fixas e intertravadas (NR-12)</li><li>Rodízio de tarefas</li>'),
    ('Soldador', '<li>Fumos metálicos e radiação não ionizante</li><li>Respingos e calor</li><li>Ruído do esmerilhamento</li><li>Posturas forçadas</li>', '<li>Máscara de solda, avental, luva de raspa e respirador P2</li><li>Exaustão localizada</li><li>Pausas térmicas</li>'),
    ('Montador de Estruturas Metálicas', '<li>Levantamento manual de perfis</li><li>Esmagamento em prensa</li><li>Queda de materiais</li>', '<li>Capacete, luva, botina e óculos</li><li>Talhas e auxílios mecânicos</li><li>Comando bimanual na prensa</li>'),
    ('Líder de Produção', '<li>Circulação em área fabril (ruído, tráfego de empilhadeiras)</li><li>Sobrecarga cognitiva</li>', '<li>Capacete, óculos, protetor auricular e botina na área fabril</li><li>Faixas de pedestres</li>'),
    ('Mecânico de Manutenção', '<li>Partida inesperada de máquinas</li><li>Óleos e graxas minerais</li><li>Ruído</li>', '<li>Bloqueio e etiquetagem (LOTO)</li><li>Luva nitrílica, óculos, abafador e botina</li>'),
    ('Eletricista de Manutenção', '<li>Choque elétrico e arco elétrico</li><li>Trabalho em altura</li>', '<li>Procedimentos NR-10 e bloqueio e etiquetagem</li><li>Luva isolante, capacete classe B e cinturão (NR-35)</li>'),
    ('Supervisor de Manutenção', '<li>Circulação em área fabril</li><li>Exposição eventual a risco elétrico</li>', '<li>EPI de circulação (capacete, óculos, botina)</li><li>Autorizações de trabalho</li>'),
    ('Operador de Empilhadeira', '<li>Atropelamento e colisão</li><li>Vibração de corpo inteiro</li><li>Postura torcida</li>', '<li>Habilitação NR-11 e checklist diário</li><li>Colete refletivo e botina</li>'),
    ('Auxiliar de Logística', '<li>Levantamento manual de cargas</li><li>Atropelamento no pátio</li>', '<li>Auxílios mecânicos e rodízio</li><li>Luva, botina e colete refletivo</li>'),
    ('Coordenador de Logística', '<li>Circulação em pátio e docas</li><li>Pressão por prazos</li>', '<li>Colete refletivo e botina</li><li>Faixas de pedestres</li>'),
    ('Analista Financeiro', '<li>Postura sentada prolongada</li><li>Uso de computador</li>', '<li>Mobiliário ajustável e pausas de alongamento</li>'),
    ('Analista da Qualidade', '<li>Ruído de fundo da usinagem</li><li>Iluminação da bancada de inspeção</li>', '<li>Protetor auricular ao circular na fábrica</li><li>Luminária de bancada</li>'),
    ('Comprador', '<li>Postura sentada prolongada</li>', '<li>Mobiliário ajustável e pausas</li>'),
    ('Analista de RH', '<li>Postura sentada prolongada</li><li>Carga mental</li>', '<li>Mobiliário ajustável e pausas</li>'),
    ('Técnico de Segurança do Trabalho', '<li>Exposição a diversos agentes durante inspeções</li>', '<li>EPI conforme a área inspecionada</li>'),
    ('Vendedor Interno', '<li>Uso contínuo de computador e headset</li>', '<li>Pausas entre atendimentos e monitor na altura dos olhos</li>')
  ) AS r(cargo, riscos, medidas) ON r.cargo = a.cargo
  WHERE NOT EXISTS (SELECT 1 FROM public.ordens_servico x WHERE x.id = public.demo_id('ordem_servico:' || o.n))
  ORDER BY (CURRENT_DATE - o.emissao) DESC, o.n;

  -- Acoes do plano de acao com origem compliance_sst
  INSERT INTO public.plano_acoes (
    id, tenant_id, empresa_id, titulo, descricao, porque, onde, como, prazo, responsavel_id, responsavel_nome,
    custo_estimado, custo_real, origem_modulo, origem_descricao, gravidade, urgencia, tendencia, prioridade, status,
    progresso, data_inicio, data_conclusao, tipo, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('plano_acao:' || x.k), v_t, v_e, x.t, x.d, x.p, x.o, x.c, CURRENT_DATE + x.pz, v_uid, v_nome,
         x.cu, CASE WHEN x.s = 'concluida' THEN x.cu END, 'compliance_sst', x.od, x.g, x.u, x.te,
         x.pr::public.acao_gut_prioridade, x.s::public.acao_status, x.pg, CURRENT_DATE - x.ini,
         CASE WHEN x.s = 'concluida' THEN CURRENT_DATE - x.conc END, x.tp, v_uid, v_nome, (CURRENT_DATE - x.ini) + TIME '11:00'
  FROM (VALUES
    ('c01', 'Adequar as prensas e a guilhotina à NR-12 com laudo de conformidade', 'Projeto de adequação, instalação em parada programada e laudo técnico.', 'Alerta crítico do PGR: proteções móveis burladas e comando bimanual deficiente.', 'Montagem e corte', 'Contratar empresa especializada e acompanhar com a manutenção.', 60, 'em_andamento', 40, 'imediato', 5, 4, 4, 24000, 'Revisão pós-importação: PGR_2026_Metalurgica_Exemplo.pdf', 'corretiva', 80, 0),
    ('c02', 'Incluir o risco psicossocial no inventário do PGR (NR-1)', 'Aplicar instrumento validado e consolidar no inventário de riscos.', 'Exigência do item 1.5.3.1.4 da NR-1.', 'Toda a empresa', 'Plano de aplicação com RH, SESMT e CIPA.', 90, 'pendente', 0, 'urgente', 4, 4, 4, 6000, 'Revisão pós-importação: PGR_2026_Metalurgica_Exemplo.pdf', 'preventiva', 30, 0),
    ('c03', 'Renovar o laudo de periculosidade do setor elétrico', 'Contratar a revisão do laudo de periculosidade por eletricidade.', 'Laudo com revisão vencida há 20 dias.', 'Manutenção elétrica', 'Solicitar proposta ao engenheiro responsável e agendar visita técnica.', 7, 'pendente', 10, 'imediato', 4, 5, 3, 2200, 'Revisão pós-importação: Laudo_Periculosidade_Eletricidade_2025.pdf', 'corretiva', 20, 0),
    ('c04', 'Realizar os exames periódicos em atraso de soldadores e operadores', 'Agendar os exames periódicos pendentes conforme a matriz do PCMSO.', 'Exames próximos do vencimento ou vencidos.', 'Saúde ocupacional', 'Convocar os colaboradores e acompanhar a clínica credenciada.', 25, 'em_andamento', 60, 'urgente', 4, 4, 3, 5400, 'Revisão pós-importação: PCMSO_2026_Metalurgica_Exemplo.pdf', 'corretiva', 45, 0),
    ('c05', 'Reemitir as Ordens de Serviço desatualizadas após a revisão do PGR', 'Gerar nova OS para os colaboradores cuja OS foi baseada no PGR anterior.', 'OS desatualizadas após a publicação do PGR 2026.', 'Todas as áreas', 'Gerar, enviar para assinatura e acompanhar o aceite.', 20, 'em_andamento', 70, 'urgente', 3, 4, 3, 0, 'Compliance SST: Ordens de Serviço', 'corretiva', 15, 0),
    ('c06', 'Revisar a APR de manutenção de prensas', 'Atualizar a APR após a instalação da cortina de luz.', 'A APR vence em 45 dias e a prensa 02 será adequada.', 'Manutenção', 'Revisão em conjunto com os mecânicos e a CIPA.', 45, 'pendente', 0, 'medio', 3, 3, 3, 0, 'Revisão pós-importação: APR_Manutencao_de_Prensas_2026.pdf', 'preventiva', 10, 0),
    ('c07', 'Atualizar o LTCAT após a reavaliação do ruído do esmerilhamento', 'Reavaliar o ruído após o enclausuramento parcial e atualizar o LTCAT.', 'Evidência de ruído acima do nível de ação.', 'Solda', 'Dosimetria e emissão de adendo ao LTCAT.', -25, 'concluida', 100, 'medio', 3, 3, 2, 1800, 'Revisão pós-importação: LTCAT_2026_Metalurgica_Exemplo.pdf', 'preventiva', 70, 28)
  ) AS x(k, t, d, p, o, c, pz, s, pg, pr, g, u, te, cu, od, tp, ini, conc)
  WHERE NOT EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('plano_acao:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Compliance SST (OS e acoes) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $sst2$;

-- ---------------------------------------------------------------------------
-- (3) Terceiros — empresas, trabalhadores, documentos e treinamentos
--     (o status de liberado, restrito ou bloqueado e recalculado pelos gatilhos do banco)
-- ---------------------------------------------------------------------------
DO $terc1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Empresas terceiras (CNPJs ficticios)
  INSERT INTO public.terceiros (
    id, tenant_id, empresa_id, razao_social, nome_fantasia, cnpj, atividade_principal, cnae, responsavel_nome, responsavel_cargo,
    email, telefone, tipo_servico, unidades, setores, tipo_acesso, contrato_inicio, contrato_fim, atividade_risco, observacoes
  )
  SELECT public.demo_id('terceiro:' || x.k), v_t, v_e, x.rs, x.nf, x.cnpj, x.ativ, x.cnae, x.resp, x.cargo,
         x.mail, x.tel, x.srv, ARRAY['Metalúrgica Exemplo'], x.setores, x.acesso::public.terceiro_acesso,
         CURRENT_DATE - x.ci, CURRENT_DATE + x.cf, x.risco, x.obs
  FROM (VALUES
    (1, 'Elevar Manutenção de Empilhadeiras Ltda', 'Elevar Empilhadeiras', '11222333000181', 'Manutenção de empilhadeiras e equipamentos de movimentação', '3314-7/10', 'Rubens Aguiar Teles', 'Gerente de contratos', 'contratos@elevar-empilhadeiras.demo', '(47) 3300-1101', ARRAY['Manutenção','Mecânica'], ARRAY['Logística'], 'recorrente', 420, 310, true, 'Atende as 8 empilhadeiras da matriz e do CD Itajaí.'),
    (2, 'Voltaje Instalações Elétricas Ltda', 'Voltaje Elétrica', '22333444000172', 'Instalação e manutenção de sistemas elétricos industriais', '4321-5/00', 'Silvana Prado Meireles', 'Engenheira responsável', 'projetos@voltaje.demo', '(47) 3300-2202', ARRAY['Elétrica','Manutenção'], ARRAY['Manutenção','Produção'], 'recorrente', 300, 200, true, 'Equipe com curso NR-10 e SEP; acessa subestação mediante permissão de trabalho.'),
    (3, 'Brilho Limpeza Industrial Ltda', 'Brilho Limpeza', '33444555000163', 'Limpeza e conservação industrial', '8121-4/00', 'Dolores Santana', 'Sócia administradora', 'adm@brilholimpeza.demo', '(47) 3300-3303', ARRAY['Limpeza técnica'], ARRAY['Produção','Administrativo'], 'continuo', 700, 390, false, 'Contrato contínuo com 4 colaboradores no local.'),
    (4, 'ColorTec Pintura Industrial Ltda', 'ColorTec', '44555666000154', 'Pintura industrial e tratamento de superfícies', '4330-4/04', 'Nilton Barroso', 'Diretor técnico', 'comercial@colortec.demo', '(47) 3300-4404', ARRAY['Pintura'], ARRAY['Produção'], 'eventual', 180, 90, true, 'Serviços de pintura de estruturas e pontes rolantes em paradas programadas.'),
    (5, 'Vigia Segurança Patrimonial Ltda', 'Vigia Patrimonial', '55666777000145', 'Vigilância e segurança patrimonial', '8011-1/01', 'Coronel Heitor Valadares (reserva)', 'Diretor operacional', 'operacao@vigia.demo', '(47) 3300-5505', ARRAY['Segurança'], ARRAY['Portaria'], 'continuo', 900, 480, false, 'Portaria 24 horas, três postos.'),
    (6, 'RotaSul Transportes Ltda', 'RotaSul', '66777888000136', 'Transporte rodoviário de cargas', '4930-2/02', 'Edilene Moraes', 'Coordenadora de frota', 'frota@rotasul.demo', '(47) 3300-6606', ARRAY['Outros'], ARRAY['Expedição'], 'recorrente', 500, 260, false, 'Transporte de produtos acabados para clientes do Sul.'),
    (7, 'MetroCal Metrologia e Calibração Ltda', 'MetroCal', '77888999000127', 'Calibração de instrumentos de medição', '7120-1/00', 'Dr. Artur Fontoura', 'Responsável técnico', 'laboratorio@metrocal.demo', '(47) 3300-7707', ARRAY['Outros'], ARRAY['Qualidade'], 'recorrente', 340, 28, false, 'Contrato próximo do fim; renovação em negociação.'),
    (8, 'TecnoNet Informática Ltda', 'TecnoNet', '88999000000118', 'Suporte e infraestrutura de TI', '6209-1/00', 'Lívia Soares', 'Coordenadora de suporte', 'suporte@tecnonet.demo', '(47) 3300-8808', ARRAY['TI'], ARRAY['Administrativo'], 'eventual', 200, 165, false, 'Atendimento sob demanda.'),
    (9, 'Altus Montagens e Andaimes Ltda', 'Altus Andaimes', '99000111000109', 'Montagem de andaimes e estruturas temporárias', '4399-1/01', 'Ademir Cordeiro', 'Sócio e responsável técnico', 'obras@altus.demo', '(47) 3300-9909', ARRAY['Obras','Manutenção'], ARRAY['Produção','Manutenção'], 'eventual', 150, 215, true, 'Atua em trabalhos em altura no telhado e na ponte rolante.'),
    (10, 'SafeMed Consultoria em SST Ltda', 'SafeMed SST', '10111222000191', 'Consultoria em saúde e segurança do trabalho', '7119-7/04', 'Dra. Patrícia Vilar', 'Sócia e consultora', 'atendimento@safemed.demo', '(47) 3300-1010', ARRAY['Segurança'], ARRAY['Produção','Administrativo'], 'recorrente', 260, 105, false, 'Elabora PGR, PCMSO e treinamentos NR da empresa.')
  ) AS x(k, rs, nf, cnpj, ativ, cnae, resp, cargo, mail, tel, srv, setores, acesso, ci, cf, risco, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiros z WHERE z.id = public.demo_id('terceiro:' || x.k));

  -- Trabalhadores (CPFs ficticios da faixa 900.000.1XX)
  INSERT INTO public.terceiro_trabalhadores (
    id, tenant_id, terceiro_id, nome, cpf, funcao, atividades, unidade, setor, atividades_risco, ativo
  )
  SELECT public.demo_id('terc_trab:' || w.k), v_t, public.demo_id('terceiro:' || w.t), w.nome, public.demo_cpf(100 + w.k), w.funcao,
         ARRAY[w.funcao], 'Metalúrgica Exemplo', w.setor, w.riscos, true
  FROM (VALUES
    (1, 1, 'Anderson Moreira Caldas', 'Mecânico de empilhadeiras', 'Logística', ARRAY['Máquinas e Equipamentos']),
    (2, 1, 'Jefferson Rocha Ribeiro', 'Auxiliar mecânico', 'Logística', ARRAY['Máquinas e Equipamentos']),
    (3, 1, 'Cleber Antunes Dutra', 'Mecânico de empilhadeiras', 'Logística', ARRAY['Máquinas e Equipamentos']),
    (4, 1, 'Marcelo Tavares Guedes', 'Eletricista automotivo', 'Logística', ARRAY['Eletricidade']),
    (5, 2, 'Rogério Batista Salles', 'Eletricista de manutenção', 'Manutenção', ARRAY['Eletricidade','Trabalho em Altura']),
    (6, 2, 'Edson Cavalcanti Lima', 'Eletricista de manutenção', 'Manutenção', ARRAY['Eletricidade']),
    (7, 2, 'Valdir Nogueira Prado', 'Encarregado elétrico', 'Manutenção', ARRAY['Eletricidade','Trabalho em Altura']),
    (8, 2, 'Fábio Henrique Soares', 'Ajudante de eletricista', 'Manutenção', ARRAY['Eletricidade']),
    (9, 3, 'Luzia Aparecida Matos', 'Auxiliar de limpeza industrial', 'Produção', ARRAY[]::text[]),
    (10, 3, 'Marta Cristina Pinto', 'Auxiliar de limpeza industrial', 'Administrativo', ARRAY[]::text[]),
    (11, 3, 'Josefa Ramos Duarte', 'Auxiliar de limpeza industrial', 'Produção', ARRAY[]::text[]),
    (12, 3, 'Sandra Regina Teles', 'Encarregada de limpeza', 'Produção', ARRAY[]::text[]),
    (13, 4, 'Osvaldo Pereira Brandão', 'Pintor industrial', 'Produção', ARRAY['Trabalho em Altura','Espaço Confinado']),
    (14, 4, 'Jair Fernandes Costa', 'Pintor industrial', 'Produção', ARRAY['Trabalho em Altura']),
    (15, 4, 'Mauro Lúcio Andrade', 'Ajudante de pintura', 'Produção', ARRAY['Trabalho em Altura']),
    (16, 5, 'Cláudio Ribeiro Mendes', 'Vigilante', 'Portaria', ARRAY[]::text[]),
    (17, 5, 'Nelson Batista Freitas', 'Vigilante', 'Portaria', ARRAY[]::text[]),
    (18, 5, 'Ivan Duarte Luz', 'Vigilante', 'Portaria', ARRAY[]::text[]),
    (19, 6, 'Gilmar Souza Bastos', 'Motorista', 'Expedição', ARRAY[]::text[]),
    (20, 6, 'Ronaldo Pires Neves', 'Motorista', 'Expedição', ARRAY[]::text[]),
    (21, 7, 'Patrícia Lemos Cardoso', 'Metrologista', 'Qualidade', ARRAY[]::text[]),
    (22, 7, 'Tiago Moura Barbosa', 'Técnico de calibração', 'Qualidade', ARRAY[]::text[]),
    (23, 8, 'Eduardo Lacerda Rios', 'Técnico de informática', 'Administrativo', ARRAY[]::text[]),
    (24, 9, 'Wilson Gomes Pacheco', 'Montador de andaimes', 'Produção', ARRAY['Trabalho em Altura']),
    (25, 9, 'Reinaldo Dias Furtado', 'Montador de andaimes', 'Produção', ARRAY['Trabalho em Altura']),
    (26, 9, 'Alan Ferraz Medeiros', 'Montador de andaimes', 'Produção', ARRAY['Trabalho em Altura']),
    (27, 9, 'Sérgio Vilela Campos', 'Encarregado de montagem', 'Produção', ARRAY['Trabalho em Altura','Trabalho a Quente']),
    (28, 10, 'Camila Rezende Tosta', 'Consultora de SST', 'Administrativo', ARRAY[]::text[]),
    (29, 10, 'Bruno Cunha Garrido', 'Técnico de segurança', 'Produção', ARRAY[]::text[])
  ) AS w(k, t, nome, funcao, setor, riscos)
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiro_trabalhadores z WHERE z.id = public.demo_id('terc_trab:' || w.k));

  -- Documentos da empresa terceira (contrato, PGR, PCMSO, seguro, registro). perfil define os vencimentos.
  INSERT INTO public.terceiro_documentos (
    id, tenant_id, terceiro_id, trabalhador_id, tipo, nome, arquivo_url, arquivo_nome, arquivo_tamanho, data_emissao, data_validade,
    observacoes, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('terc_doc:e:' || p.k || ':' || d.tipo), v_t, public.demo_id('terceiro:' || p.k), NULL, d.tipo,
         d.tipo || ' - ' || p.nf,
         CASE WHEN d.tipo = 'PCMSO' AND p.perfil = 'pend_pcmso' THEN NULL
              ELSE 'demo/terceiros/' || p.k::text || '/' || lower(replace(d.tipo, '/', '-')) || '.pdf' END,
         CASE WHEN d.tipo = 'PCMSO' AND p.perfil = 'pend_pcmso' THEN NULL
              ELSE lower(replace(d.tipo, '/', '-')) || '_' || p.k::text || '.pdf' END,
         CASE WHEN d.tipo = 'PCMSO' AND p.perfil = 'pend_pcmso' THEN NULL ELSE 380000 + p.k * 17000 END,
         CURRENT_DATE - 160,
         CASE
           WHEN d.tipo = 'Contrato' THEN CURRENT_DATE + p.cf
           WHEN d.tipo = 'PGR' AND p.perfil = 'bloq_pgr' THEN CURRENT_DATE - 40
           WHEN d.tipo = 'PCMSO' AND p.perfil = 'pend_pcmso' THEN NULL
           WHEN d.tipo = 'Seguro' AND p.perfil = 'seg_a_vencer' THEN CURRENT_DATE + 25
           WHEN d.tipo = 'Seguro' AND p.perfil = 'seg_vencido' THEN CURRENT_DATE - 10
           WHEN d.tipo = 'Certificado/Registro Legal' THEN CURRENT_DATE + 400
           ELSE CURRENT_DATE + 200 + p.k * 7
         END,
         CASE WHEN d.tipo = 'PCMSO' AND p.perfil = 'pend_pcmso' THEN 'Documento solicitado ao prestador e ainda não entregue.' END,
         v_uid, v_nome, now() - ((100 + p.k) || ' days')::interval
  FROM (VALUES
    (1, 'Elevar Empilhadeiras', 'ok', 310), (2, 'Voltaje Elétrica', 'seg_a_vencer', 200), (3, 'Brilho Limpeza', 'pend_pcmso', 390),
    (4, 'ColorTec', 'bloq_pgr', 90), (5, 'Vigia Patrimonial', 'ok', 480), (6, 'RotaSul', 'ok', 260), (7, 'MetroCal', 'ok', 28),
    (8, 'TecnoNet', 'ok', 165), (9, 'Altus Andaimes', 'seg_vencido', 215), (10, 'SafeMed SST', 'ok', 105)
  ) AS p(k, nf, perfil, cf)
  CROSS JOIN (VALUES ('Contrato'), ('PGR'), ('PCMSO'), ('Seguro'), ('Certificado/Registro Legal')) AS d(tipo)
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiro_documentos z WHERE z.id = public.demo_id('terc_doc:e:' || p.k || ':' || d.tipo));

  -- Documentos dos trabalhadores: ASO e Ficha de EPI (perfil define os vencimentos)
  INSERT INTO public.terceiro_documentos (
    id, tenant_id, terceiro_id, trabalhador_id, tipo, nome, arquivo_url, arquivo_nome, arquivo_tamanho, data_emissao, data_validade,
    observacoes, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('terc_doc:t:' || w.k || ':' || d.tipo), v_t, public.demo_id('terceiro:' || w.t), public.demo_id('terc_trab:' || w.k),
         d.tipo, d.tipo || ' - ' || w.nome,
         CASE WHEN d.tipo = 'ASO' AND w.perfil = 'pend' THEN NULL ELSE 'demo/terceiros/' || w.t::text || '/trab' || w.k::text || '_' || lower(replace(d.tipo, ' ', '-')) || '.pdf' END,
         CASE WHEN d.tipo = 'ASO' AND w.perfil = 'pend' THEN NULL ELSE lower(replace(d.tipo, ' ', '-')) || '_' || w.k::text || '.pdf' END,
         CASE WHEN d.tipo = 'ASO' AND w.perfil = 'pend' THEN NULL ELSE 150000 + w.k * 4000 END,
         CURRENT_DATE - 120,
         CASE
           WHEN d.tipo = 'ASO' AND w.perfil = 'ok' THEN CURRENT_DATE + 180 + (w.k % 5) * 12
           WHEN d.tipo = 'ASO' AND w.perfil = 'venc' THEN CURRENT_DATE + 18 + (w.k % 4)
           WHEN d.tipo = 'ASO' AND w.perfil = 'bloq' THEN CURRENT_DATE - 12
           WHEN d.tipo = 'ASO' AND w.perfil = 'pend' THEN NULL
           WHEN d.tipo = 'ASO' THEN CURRENT_DATE + 150
           ELSE CURRENT_DATE + 250
         END,
         CASE WHEN d.tipo = 'ASO' AND w.perfil = 'pend' THEN 'ASO aguardando envio pela empresa terceira.' END,
         v_uid, v_nome, now() - ((90 + w.k) || ' days')::interval
  FROM (VALUES
    (1, 1, 'Anderson Moreira Caldas', 'ok'), (2, 1, 'Jefferson Rocha Ribeiro', 'venc'), (3, 1, 'Cleber Antunes Dutra', 'ok'), (4, 1, 'Marcelo Tavares Guedes', 'ok'),
    (5, 2, 'Rogério Batista Salles', 'ok'), (6, 2, 'Edson Cavalcanti Lima', 'venc'), (7, 2, 'Valdir Nogueira Prado', 'ok'), (8, 2, 'Fábio Henrique Soares', 'pend'),
    (9, 3, 'Luzia Aparecida Matos', 'ok'), (10, 3, 'Marta Cristina Pinto', 'ok'), (11, 3, 'Josefa Ramos Duarte', 'venc'), (12, 3, 'Sandra Regina Teles', 'ok'),
    (13, 4, 'Osvaldo Pereira Brandão', 'ok'), (14, 4, 'Jair Fernandes Costa', 'ok'), (15, 4, 'Mauro Lúcio Andrade', 'ok'),
    (16, 5, 'Cláudio Ribeiro Mendes', 'ok'), (17, 5, 'Nelson Batista Freitas', 'ok'), (18, 5, 'Ivan Duarte Luz', 'venc'),
    (19, 6, 'Gilmar Souza Bastos', 'ok'), (20, 6, 'Ronaldo Pires Neves', 'ok'), (21, 7, 'Patrícia Lemos Cardoso', 'ok'), (22, 7, 'Tiago Moura Barbosa', 'ok'),
    (23, 8, 'Eduardo Lacerda Rios', 'ok'), (24, 9, 'Wilson Gomes Pacheco', 'bloq'), (25, 9, 'Reinaldo Dias Furtado', 'ok'), (26, 9, 'Alan Ferraz Medeiros', 'ok'),
    (27, 9, 'Sérgio Vilela Campos', 'venc'), (28, 10, 'Camila Rezende Tosta', 'ok'), (29, 10, 'Bruno Cunha Garrido', 'ok')
  ) AS w(k, t, nome, perfil)
  CROSS JOIN (VALUES ('ASO'), ('Ficha de EPI')) AS d(tipo)
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiro_documentos z WHERE z.id = public.demo_id('terc_doc:t:' || w.k || ':' || d.tipo));

  -- Treinamentos: NR especifica da funcao, NR-06 e integracao em SST
  INSERT INTO public.terceiro_treinamentos (
    id, tenant_id, terceiro_id, trabalhador_id, tipo, descricao, data_realizacao, carga_horaria, data_validade,
    certificado_url, certificado_nome, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('terc_trein:' || w.k || ':' || n.tipo), v_t, public.demo_id('terceiro:' || w.t), public.demo_id('terc_trab:' || w.k), n.tipo,
         n.descr, CURRENT_DATE - 200 + (w.k % 9), n.ch,
         CASE
           WHEN n.tipo = 'Integração SST' THEN CURRENT_DATE + 330
           WHEN w.perfil = 'venc' AND n.tipo LIKE 'NR-%' THEN CURRENT_DATE + 27 + (w.k % 3)
           WHEN w.perfil = 'bloq2' AND n.tipo LIKE 'NR-3%' THEN CURRENT_DATE - 30
           ELSE CURRENT_DATE + 300 + (w.k % 6) * 14
         END,
         'demo/terceiros/' || w.t::text || '/trein' || w.k::text || '_' || lower(replace(n.tipo, ' ', '-')) || '.pdf',
         'certificado_' || lower(replace(n.tipo, ' ', '-')) || '_' || w.k::text || '.pdf',
         v_uid, v_nome, now() - ((80 + w.k) || ' days')::interval
  FROM (VALUES
    (1, 1, 'ok'), (2, 1, 'venc'), (3, 1, 'ok'), (4, 1, 'ok'), (5, 2, 'ok'), (6, 2, 'venc'), (7, 2, 'ok'), (8, 2, 'ok'),
    (9, 3, 'ok'), (10, 3, 'ok'), (11, 3, 'ok'), (12, 3, 'ok'), (13, 4, 'bloq2'), (14, 4, 'ok'), (15, 4, 'ok'),
    (16, 5, 'ok'), (17, 5, 'ok'), (18, 5, 'ok'), (19, 6, 'ok'), (20, 6, 'ok'), (21, 7, 'ok'), (22, 7, 'ok'), (23, 8, 'ok'),
    (24, 9, 'ok'), (25, 9, 'ok'), (26, 9, 'ok'), (27, 9, 'venc'), (28, 10, 'ok'), (29, 10, 'ok')
  ) AS w(k, t, perfil)
  JOIN (VALUES
    (1, 'NR-12', 'Segurança em máquinas e equipamentos', 8), (2, 'NR-10', 'Segurança em instalações elétricas', 40),
    (2, 'NR-35', 'Trabalho em altura', 8), (4, 'NR-35', 'Trabalho em altura', 8), (4, 'NR-33', 'Espaço confinado', 16),
    (9, 'NR-35', 'Trabalho em altura', 8), (9, 'NR-18', 'Condições de trabalho na construção', 6),
    (1, 'NR-06 (EPI)', 'Uso e conservação de EPI', 4), (2, 'NR-06 (EPI)', 'Uso e conservação de EPI', 4),
    (3, 'NR-06 (EPI)', 'Uso e conservação de EPI', 4), (4, 'NR-06 (EPI)', 'Uso e conservação de EPI', 4), (9, 'NR-06 (EPI)', 'Uso e conservação de EPI', 4),
    (1, 'Integração SST', 'Integração de segurança para terceiros', 4), (2, 'Integração SST', 'Integração de segurança para terceiros', 4),
    (3, 'Integração SST', 'Integração de segurança para terceiros', 4), (4, 'Integração SST', 'Integração de segurança para terceiros', 4),
    (5, 'Integração SST', 'Integração de segurança para terceiros', 4), (6, 'Integração SST', 'Integração de segurança para terceiros', 4),
    (7, 'Integração SST', 'Integração de segurança para terceiros', 4), (8, 'Integração SST', 'Integração de segurança para terceiros', 4),
    (9, 'Integração SST', 'Integração de segurança para terceiros', 4), (10, 'Integração SST', 'Integração de segurança para terceiros', 4)
  ) AS n(t, tipo, descr, ch) ON n.t = w.t
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiro_treinamentos z WHERE z.id = public.demo_id('terc_trein:' || w.k || ':' || n.tipo));

  -- Historico (auditoria) das empresas terceiras
  INSERT INTO public.terceiro_audit_log (id, tenant_id, entidade_tipo, entidade_id, acao, descricao, dados_novos, usuario_id, usuario_nome, created_at)
  SELECT public.demo_id('terc_audit:' || x.k), v_t, 'terceiro', public.demo_id('terceiro:' || x.t), x.acao, x.descr,
         jsonb_build_object('terceiro', x.t), v_uid, v_nome, now() - (x.d || ' days')::interval
  FROM (VALUES
    (1, 1, 'criado', 'Terceiro "Elevar Empilhadeiras" cadastrado', 420), (2, 2, 'criado', 'Terceiro "Voltaje Elétrica" cadastrado', 300),
    (3, 4, 'status_alterado', 'Status alterado para bloqueado: PGR vencido', 40), (4, 9, 'status_alterado', 'Status alterado para bloqueado: seguro vencido', 10),
    (5, 7, 'atualizado', 'Contrato com vigência próxima do fim; renovação em negociação', 20), (6, 3, 'documento_pendente', 'PCMSO solicitado ao prestador', 15),
    (7, 2, 'status_alterado', 'Status alterado para restrito: seguro a vencer', 6), (8, 10, 'criado', 'Terceiro "SafeMed SST" cadastrado', 260)
  ) AS x(k, t, acao, descr, d)
  WHERE NOT EXISTS (SELECT 1 FROM public.terceiro_audit_log z WHERE z.id = public.demo_id('terc_audit:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Terceiros (empresas, trabalhadores, documentos) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $terc1$;

-- ---------------------------------------------------------------------------
-- (4) Terceiros — permissoes de trabalho e trilhas de integracao (com link publico)
-- ---------------------------------------------------------------------------
DO $terc2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Permissoes de trabalho (o codigo PT-xxxxx e gerado pelo banco, em ordem de data)
  INSERT INTO public.permissoes_trabalho (
    id, tenant_id, empresa_id, terceiro_id, data_inicio, data_fim, local, atividade, descricao, atividades_risco, status, motivo_bloqueio,
    criado_por, criado_por_nome, liberado_por, liberado_por_nome, liberado_em, encerrado_por, encerrado_por_nome, encerrado_em, observacoes, created_at
  )
  SELECT public.demo_id('pt:' || x.k), v_t, v_e, public.demo_id('terceiro:' || x.t), CURRENT_DATE + x.di, CURRENT_DATE + x.df, x.loc, x.ativ, x.descr,
         x.risco, x.st::public.pt_status, x.mot, v_uid, v_nome,
         CASE WHEN x.st IN ('liberada', 'encerrada') THEN v_uid END, CASE WHEN x.st IN ('liberada', 'encerrada') THEN v_nome END,
         CASE WHEN x.st IN ('liberada', 'encerrada') THEN (CURRENT_DATE + x.di) + TIME '07:15' END,
         CASE WHEN x.st = 'encerrada' THEN v_uid END, CASE WHEN x.st = 'encerrada' THEN v_nome END,
         CASE WHEN x.st = 'encerrada' THEN (CURRENT_DATE + x.df) + TIME '17:30' END,
         x.obs, (CURRENT_DATE + x.di - 3) + TIME '14:00'
  FROM (VALUES
    (1, 9, -62, -58, 'Galpão 1, cobertura', 'Montagem de andaime para troca de telhas', 'Montagem de andaime fachadeiro e troca de telhas translúcidas.', ARRAY['Trabalho em Altura'], 'encerrada', NULL, 'Concluída sem ocorrências; andaime desmontado e área liberada.'),
    (2, 2, -21, -19, 'Usinagem CNC', 'Instalação de novos pontos de tomada', 'Passagem de eletrodutos e instalação de tomadas industriais.', ARRAY['Eletricidade'], 'encerrada', NULL, NULL),
    (3, 4, -30, -28, 'Galpão 2', 'Pintura de tubulações', 'Pintura de tubulações de ar comprimido.', ARRAY['Trabalho em Altura'], 'cancelada', NULL, 'Cancelada por chuva e reprogramada pelo prestador.'),
    (4, 1, -1, 1, 'Oficina de manutenção', 'Revisão das empilhadeiras 1 a 4', 'Revisão preventiva de 250 horas com troca de fluido hidráulico.', ARRAY['Máquinas e Equipamentos'], 'liberada', NULL, 'Trabalho acompanhado pelo supervisor de manutenção.'),
    (5, 2, 0, 1, 'Subestação 1', 'Troca do disjuntor geral e inspeção do quadro', 'Intervenção no quadro geral com desligamento programado.', ARRAY['Eletricidade'], 'liberada', NULL, 'Bloqueio e etiquetagem aplicado pela equipe de manutenção.'),
    (6, 9, 2, 4, 'Galpão 1, ponte rolante', 'Montagem de andaime para manutenção da ponte rolante', 'Andaime para acesso aos trilhos da ponte rolante.', ARRAY['Trabalho em Altura'], 'bloqueada', 'Trabalhador com ASO vencido e treinamento de altura a vencer: substituir ou regularizar antes da liberação.', NULL),
    (7, 4, 3, 5, 'Galpão 2', 'Pintura da estrutura da ponte rolante', 'Pintura epóxi da estrutura metálica com plataforma elevatória.', ARRAY['Trabalho em Altura', 'Espaço Confinado'], 'rascunho', NULL, 'Aguardando renovação do PGR do prestador.'),
    (8, 1, 6, 6, 'CD Itajaí', 'Troca de pneus das empilhadeiras', 'Troca dos pneus maciços de duas empilhadeiras.', ARRAY['Máquinas e Equipamentos'], 'rascunho', NULL, NULL)
  ) AS x(k, t, di, df, loc, ativ, descr, risco, st, mot, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.permissoes_trabalho z WHERE z.id = public.demo_id('pt:' || x.k))
  ORDER BY x.di, x.k;

  -- Trabalhadores de cada permissao com a verificacao de documentos, treinamentos e ASO
  INSERT INTO public.permissao_trabalhadores (id, permissao_id, trabalhador_id, tenant_id, docs_ok, treins_ok, aso_ok, apto, motivo_bloqueio)
  SELECT public.demo_id('pt_trab:' || l.pt || ':' || l.w), public.demo_id('pt:' || l.pt), public.demo_id('terc_trab:' || l.w), v_t,
         c.docs_ok, c.treins_ok, c.aso_ok, (c.docs_ok AND c.treins_ok AND c.aso_ok),
         CASE WHEN NOT c.aso_ok THEN 'ASO vencido ou pendente' WHEN NOT c.docs_ok THEN 'Documento vencido' WHEN NOT c.treins_ok THEN 'Treinamento vencido' END
  FROM (VALUES
    (1, 24), (1, 25), (1, 26), (2, 5), (2, 6), (3, 13), (3, 14), (4, 1), (4, 2), (4, 3), (5, 5), (5, 7), (5, 6),
    (6, 24), (6, 25), (6, 27), (7, 13), (7, 14), (7, 15), (8, 1), (8, 3)
  ) AS l(pt, w)
  CROSS JOIN LATERAL (
    SELECT NOT EXISTS (SELECT 1 FROM public.terceiro_documentos d WHERE d.trabalhador_id = public.demo_id('terc_trab:' || l.w) AND d.status = 'vencido') AS docs_ok,
           NOT EXISTS (SELECT 1 FROM public.terceiro_treinamentos tr WHERE tr.trabalhador_id = public.demo_id('terc_trab:' || l.w) AND tr.status = 'vencido') AS treins_ok,
           NOT EXISTS (SELECT 1 FROM public.terceiro_documentos d WHERE d.trabalhador_id = public.demo_id('terc_trab:' || l.w) AND d.tipo = 'ASO' AND d.status IN ('vencido', 'pendente')) AS aso_ok
  ) c
  WHERE EXISTS (SELECT 1 FROM public.permissoes_trabalho p WHERE p.id = public.demo_id('pt:' || l.pt))
    AND EXISTS (SELECT 1 FROM public.terceiro_trabalhadores w WHERE w.id = public.demo_id('terc_trab:' || l.w))
    AND NOT EXISTS (SELECT 1 FROM public.permissao_trabalhadores z WHERE z.id = public.demo_id('pt_trab:' || l.pt || ':' || l.w));

  -- Trilhas de integracao para terceiros (link publico)
  INSERT INTO public.trilhas (
    id, tenant_id, empresa_id, nome, descricao, objetivo, tipo, prioridade, visibilidade, status, pontuacao_minima, prazo_dias,
    publico_terceiros, token_publico, criado_por_nome
  )
  SELECT public.demo_id('trilha:' || x.k), v_t, v_e, x.nome, x.descr, x.obj, 'tecnica'::public.trilha_tipo, 'obrigatoria'::public.trilha_prioridade,
         'publica'::public.trilha_visibilidade, 'ativa'::public.trilha_status, 70, x.prazo, true, x.tok, v_nome
  FROM (VALUES
    ('terc_integ', 'Integração de Segurança para Prestadores de Serviço', 'Regras de segurança da Metalúrgica Exemplo para quem presta serviço nas dependências da empresa.', 'Garantir que todo prestador conheça os riscos, as regras de acesso e as rotas de emergência antes de iniciar o serviço.', 7, 'demo-integracao-terceiros-2026'),
    ('terc_altura', 'Trabalho em Altura para Prestadores (reciclagem)', 'Revisão dos requisitos da NR-35 para prestadores que atuam em telhados, andaimes e pontes rolantes.', 'Reciclar conceitos de trabalho em altura e a permissão de trabalho da empresa.', 15, 'demo-altura-terceiros-2026')
  ) AS x(k, nome, descr, obj, prazo, tok)
  WHERE NOT EXISTS (SELECT 1 FROM public.trilhas z WHERE z.id = public.demo_id('trilha:' || x.k));

  INSERT INTO public.trilha_modulos (
    id, tenant_id, trilha_id, titulo, descricao, objetivo, tipo, conteudo_texto, tempo_estimado_min, pontuacao, ordem, ordem_tipo, evidencia_obrigatoria, ativo
  )
  SELECT public.demo_id('trilha_mod:' || x.tr || ':' || x.o), v_t, public.demo_id('trilha:' || x.tr), x.t, x.d, x.ob, x.tp::public.trilha_modulo_tipo, x.txt,
         x.min, x.pts, x.o, 'sequencial'::public.trilha_modulo_ordem_tipo, false, true
  FROM (VALUES
    ('terc_integ', 1, 'Apresentação da empresa e regras de acesso', 'Visão geral da operação, portaria, crachá e circulação.', 'Conhecer as regras de acesso.', 'conteudo_interno', 'A Metalúrgica Exemplo opera usinagem, solda e montagem em dois turnos. Todo prestador deve se identificar na portaria, usar crachá visível, circular apenas pelas rotas sinalizadas e obedecer à sinalização de tráfego de empilhadeiras. Nunca opere máquinas da empresa sem autorização.', 10, 10),
    ('terc_integ', 2, 'Riscos da área fabril e EPI obrigatório', 'Ruído, partículas, cargas suspensas e tráfego de empilhadeiras.', 'Identificar os riscos e os EPI mínimos.', 'conteudo_interno', 'Na área fabril o uso de capacete, óculos de proteção, protetor auricular, calçado de segurança e colete é obrigatório. Respeite as áreas isoladas e a sinalização. Em caso de dúvida, procure o responsável pelo contrato.', 15, 15),
    ('terc_integ', 3, 'Permissão de trabalho e atividades de risco', 'Quando a PT é obrigatória e quem libera.', 'Entender a permissão de trabalho.', 'conteudo_interno', 'Trabalhos em altura, com eletricidade, a quente ou em espaço confinado exigem Permissão de Trabalho emitida pela empresa antes do início. A permissão só é liberada com documentos, ASO e treinamentos em dia.', 15, 15),
    ('terc_integ', 4, 'Emergências, rotas de fuga e primeiros socorros', 'Alarmes, pontos de encontro e acionamento da brigada.', 'Saber como agir em emergências.', 'checklist', 'Confirme: conheço o ponto de encontro; sei acionar a brigada pelo ramal 190; sei onde ficam extintores e chuveiros de emergência.', 10, 20),
    ('terc_integ', 5, 'Avaliação final de integração', 'Questões rápidas sobre as regras da empresa.', 'Comprovar o entendimento.', 'quiz', 'Questionário de 10 perguntas sobre acesso, EPI, permissão de trabalho e emergências.', 10, 40),
    ('terc_altura', 1, 'Requisitos da NR-35 e análise de risco', 'Capacitação, ASO, sistemas de ancoragem e análise de risco.', 'Rever os requisitos legais.', 'conteudo_interno', 'O trabalho em altura exige capacitação válida, ASO com aptidão específica, análise de risco e sistemas de ancoragem inspecionados. Inspecione o cinturão e o talabarte antes de cada uso.', 15, 30),
    ('terc_altura', 2, 'Permissão de trabalho em altura da empresa', 'Como solicitar e quem libera.', 'Seguir o fluxo da empresa.', 'conteudo_interno', 'Solicite a permissão com antecedência, apresente certificados e ASO e aguarde a liberação do responsável de SST. Nunca inicie o serviço sem a permissão liberada.', 10, 30),
    ('terc_altura', 3, 'Avaliação de trabalho em altura', 'Perguntas sobre ancoragem, resgate e permissão.', 'Comprovar o entendimento.', 'quiz', 'Questionário de 8 perguntas sobre NR-35 e a permissão de trabalho da empresa.', 10, 40)
  ) AS x(tr, o, t, d, ob, tp, txt, min, pts)
  WHERE EXISTS (SELECT 1 FROM public.trilhas z WHERE z.id = public.demo_id('trilha:' || x.tr))
    AND NOT EXISTS (SELECT 1 FROM public.trilha_modulos z WHERE z.id = public.demo_id('trilha_mod:' || x.tr || ':' || x.o));

  -- Progresso dos prestadores na trilha de integracao: 5 modulos; k = trabalhador, q = modulos concluidos
  INSERT INTO public.trilha_terceiro_progresso (
    id, tenant_id, trilha_id, modulo_id, terceiro_nome, terceiro_cpf, terceiro_empresa, status, nota, evidencia_texto, data_inicio, data_conclusao, pontos_obtidos
  )
  SELECT public.demo_id('trilha_prog:' || p.k || ':' || m.o), v_t, public.demo_id('trilha:terc_integ'), public.demo_id('trilha_mod:terc_integ:' || m.o),
         w.nome, w.cpf, t.razao_social,
         CASE WHEN m.o <= p.q THEN 'concluido' ELSE 'em_andamento' END,
         CASE WHEN m.o = 5 AND m.o <= p.q THEN 80 + (p.k % 3) * 5 END,
         CASE WHEN m.o = 4 AND m.o <= p.q THEN 'Checklist confirmado' END,
         now() - ((14 - m.o) || ' days')::interval,
         CASE WHEN m.o <= p.q THEN now() - ((13 - m.o) || ' days')::interval END,
         CASE WHEN m.o <= p.q THEN (ARRAY[10, 15, 15, 20, 40])[m.o] ELSE 0 END
  FROM (VALUES (1, 5), (2, 5), (3, 5), (5, 5), (6, 4), (7, 5), (9, 5), (10, 3), (11, 5), (13, 5), (14, 2), (16, 5), (17, 5), (24, 5), (25, 5), (26, 1)) AS p(k, q)
  JOIN public.terceiro_trabalhadores w ON w.id = public.demo_id('terc_trab:' || p.k)
  JOIN public.terceiros t ON t.id = w.terceiro_id
  CROSS JOIN generate_series(1, 5) AS m(o)
  WHERE m.o <= LEAST(p.q + 1, 5)
    AND EXISTS (SELECT 1 FROM public.trilha_modulos z WHERE z.id = public.demo_id('trilha_mod:terc_integ:' || m.o))
    AND NOT EXISTS (SELECT 1 FROM public.trilha_terceiro_progresso z WHERE z.id = public.demo_id('trilha_prog:' || p.k || ':' || m.o));

  -- Integracao SST concluida pela trilha fica ligada ao treinamento do prestador
  UPDATE public.terceiro_treinamentos tr
     SET trilha_id = public.demo_id('trilha:terc_integ')
   WHERE tr.tenant_id = v_t AND tr.tipo = 'Integração SST' AND tr.trilha_id IS NULL
     AND tr.trabalhador_id IN (SELECT public.demo_id('terc_trab:' || k) FROM unnest(ARRAY[1, 2, 3, 5, 6, 7, 9, 11, 13, 16, 17, 24, 25]) AS k)
     AND EXISTS (SELECT 1 FROM public.trilhas z WHERE z.id = public.demo_id('trilha:terc_integ'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Terceiros (permissoes e trilhas) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $terc2$;

-- ---------------------------------------------------------------------------
-- (5) Documentos — arvore de pastas da empresa (reaproveita pastas que ja existam)
-- ---------------------------------------------------------------------------
DO $doc1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
  v_map jsonb := '{}'::jsonb;
  v_pai uuid;
  v_id uuid;
  v_gp uuid;
  v_inv uuid;
  r record;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Estrutura padrao do sistema + categorias extras usadas pelo mapa de conformidade e pelo radar de governanca
  FOR r IN
    SELECT f.path, f.tipo, f.icone, f.ordem
    FROM (VALUES
      ('Governança e Administração', 'root', 'Scale', 0),
      ('Governança e Administração > Contrato Social e Estatuto', 'categoria', 'Building2', 0),
      ('Governança e Administração > Políticas e Diretrizes', 'categoria', 'Target', 1),
      ('Governança e Administração > Licenças e Autorizações', 'categoria', 'FileCheck', 2),
      ('Governança e Administração > Certidões', 'categoria', 'Award', 3),
      ('Governança e Administração > Registros em Conselhos', 'categoria', 'Shield', 4),
      ('Governança e Administração > Estrutura Organizacional', 'categoria', NULL, 5),
      ('Governança e Administração > Direcionamento Estratégico', 'categoria', NULL, 6),
      ('Sistema de Gestão', 'root', 'BookOpen', 1),
      ('Sistema de Gestão > Procedimentos e Instruções de Trabalho', 'categoria', 'FileText', 0),
      ('Sistema de Gestão > Registros da Qualidade', 'categoria', 'CheckSquare', 1),
      ('Gestão de Riscos', 'root', 'AlertTriangle', 2),
      ('Gestão de Riscos > Inventário de Riscos', 'categoria', 'List', 0),
      ('Gestão de Riscos > Análise de Riscos (APR / HAZOP)', 'categoria', 'Search', 1),
      ('Gestão de Riscos > Planos de Emergência', 'categoria', 'ShieldAlert', 2),
      ('Gestão de Riscos > Matriz de Riscos', 'categoria', NULL, 3),
      ('SST', 'root', 'Shield', 3),
      ('SST > Programas Legais', 'categoria', 'FileCheck', 0),
      ('SST > Programas Legais > PGR', 'custom', NULL, 0),
      ('SST > Programas Legais > PCMSO', 'custom', NULL, 1),
      ('SST > Programas Legais > LTCAT', 'custom', NULL, 2),
      ('SST > Programas Legais > AET — Análise Ergonômica do Trabalho', 'custom', NULL, 3),
      ('SST > Programas Legais > AEP — Avaliação Ergonômica Preliminar', 'custom', NULL, 4),
      ('SST > Programas Legais > Laudos de Insalubridade', 'custom', NULL, 5),
      ('SST > Programas Legais > Laudos de Periculosidade', 'custom', NULL, 6),
      ('SST > Treinamentos', 'categoria', 'GraduationCap', 1),
      ('SST > Treinamentos > NR-01 — Disposições Gerais e Gerenciamento de Riscos', 'custom', NULL, 0),
      ('SST > Treinamentos > NR-05 — CIPA', 'custom', NULL, 1),
      ('SST > Treinamentos > NR-06 — EPIs', 'custom', NULL, 2),
      ('SST > Treinamentos > NR-10 — Instalações Elétricas', 'custom', NULL, 3),
      ('SST > Treinamentos > NR-11 — Transporte de Cargas', 'custom', NULL, 4),
      ('SST > Treinamentos > NR-12 — Máquinas e Equipamentos', 'custom', NULL, 5),
      ('SST > Treinamentos > NR-35 — Trabalho em Altura', 'custom', NULL, 6),
      ('SST > Registros e Evidências', 'categoria', 'ClipboardList', 2),
      ('SST > Registros e Evidências > CAT — Comunicação de Acidente', 'custom', NULL, 0),
      ('SST > Registros e Evidências > Inspeções de Segurança', 'custom', NULL, 1),
      ('SST > Registros e Evidências > Permissões de Trabalho', 'custom', NULL, 2),
      ('Cultura Organizacional', 'root', 'Heart', 4),
      ('Cultura Organizacional > Manual de Cultura', 'categoria', 'FileText', 0),
      ('Cultura Organizacional > Documentos da Cultura', 'categoria', 'FileCheck', 1),
      ('Gestão de Pessoas', 'root', 'Users', 5),
      ('Investigação de Incidentes', 'root', 'SearchX', 6),
      ('Investigação de Incidentes > Acidentes de Trabalho', 'categoria', NULL, 0),
      ('Investigação de Incidentes > Quase Acidentes', 'categoria', NULL, 1),
      ('Investigação de Incidentes > Não Conformidades', 'categoria', NULL, 2),
      ('Auditorias e Melhoria Contínua', 'root', 'CheckSquare', 7),
      ('Auditorias e Melhoria Contínua > Auditorias Internas', 'categoria', 'ClipboardCheck', 0),
      ('Auditorias e Melhoria Contínua > Auditorias Externas e Certificações', 'categoria', 'Award', 1),
      ('Auditorias e Melhoria Contínua > Ações Corretivas e Preventivas', 'categoria', 'RefreshCw', 2),
      ('Processos Organizacionais', 'root', 'FileText', 8),
      ('Processos Organizacionais > Mapeamento de Processos', 'categoria', NULL, 0),
      ('Processos Organizacionais > Procedimentos Operacionais', 'categoria', NULL, 1),
      ('Processos Organizacionais > Gestão da Qualidade', 'categoria', NULL, 2),
      ('Gestão Ambiental', 'root', 'Shield', 9),
      ('Gestão Ambiental > Licenciamento Ambiental', 'categoria', NULL, 0),
      ('Gestão Ambiental > Planos Ambientais', 'categoria', NULL, 1)
    ) AS f(path, tipo, icone, ordem)
  LOOP
    v_pai := NULL;
    IF position(' > ' IN r.path) > 0 THEN
      v_pai := (v_map ->> regexp_replace(r.path, ' > [^>]*$', ''))::uuid;
    END IF;
    v_id := (SELECT p.id FROM public.documento_pastas p
              WHERE p.tenant_id = v_t AND p.empresa_id = v_e AND p.nome = regexp_replace(r.path, '^.* > ', '')
                AND p.pasta_pai_id IS NOT DISTINCT FROM v_pai
              ORDER BY p.created_at LIMIT 1);
    IF v_id IS NULL THEN
      v_id := public.demo_id('pasta:' || r.path);
      INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, icone, criado_por, criado_por_nome)
      VALUES (v_id, v_t, v_e, regexp_replace(r.path, '^.* > ', ''), r.tipo, v_pai, r.ordem, r.icone, v_uid, v_nome)
      ON CONFLICT (id) DO NOTHING;
    END IF;
    v_map := v_map || jsonb_build_object(r.path, v_id);
  END LOOP;

  v_gp := (v_map ->> 'Gestão de Pessoas')::uuid;
  v_inv := (v_map ->> 'Investigação de Incidentes')::uuid;

  -- Pasta de cada colaborador ativo (sob Gestao de Pessoas), como o sistema faria ao sincronizar
  INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, colaborador_id, colaborador_cpf, colaborador_nome, ordem, icone, criado_por, criado_por_nome)
  SELECT public.demo_id('pasta_colab:' || a.id::text), v_t, v_e, a.nome_completo, 'colaborador', v_gp, a.id, a.cpf, a.nome_completo, 0, 'User', v_uid, v_nome
  FROM public.admissoes a
  WHERE a.tenant_id = v_t AND a.status = 'concluido' AND COALESCE(a.inativo, false) = false AND v_gp IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.documento_pastas p WHERE p.tenant_id = v_t AND p.colaborador_id = a.id AND p.tipo = 'colaborador');

  INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem)
  SELECT public.demo_id('pasta_colab_sub:' || p.id::text || ':' || s.nome), v_t, v_e, s.nome, 'categoria', p.id, s.ordem
  FROM public.documento_pastas p
  CROSS JOIN (VALUES ('Admissão', 0), ('Vida Funcional', 1), ('Saúde Ocupacional', 2), ('Desligamento', 3)) AS s(nome, ordem)
  WHERE p.tenant_id = v_t AND p.tipo = 'colaborador' AND p.colaborador_id IN (SELECT a.id FROM public.admissoes a WHERE a.tenant_id = v_t)
    AND NOT EXISTS (SELECT 1 FROM public.documento_pastas z WHERE z.tenant_id = v_t AND z.pasta_pai_id = p.id AND z.nome = s.nome);

  -- Pastas de investigacao de cada acidente (criadas pelo sistema ao registrar o evento)
  INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, criado_por, criado_por_nome)
  SELECT public.demo_id('pasta_evt:' || e.id::text), v_t, v_e,
         'Acidente ' || e.codigo || ' — ' || to_char(e.data_evento, 'DD/MM/YYYY'), 'custom', v_inv, 999, v_uid, v_nome
  FROM public.eventos_sst e
  WHERE e.tenant_id = v_t AND e.tipo = 'acidente' AND v_inv IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.documento_pastas z WHERE z.tenant_id = v_t AND z.pasta_pai_id = v_inv
                     AND z.nome = 'Acidente ' || e.codigo || ' — ' || to_char(e.data_evento, 'DD/MM/YYYY'));

  INSERT INTO public.documento_pastas (id, tenant_id, empresa_id, nome, tipo, pasta_pai_id, ordem, criado_por, criado_por_nome)
  SELECT public.demo_id('pasta_evt_sub:' || p.id::text || ':' || s.nome), v_t, v_e, s.nome, 'custom', p.id, s.ordem, v_uid, v_nome
  FROM public.documento_pastas p
  CROSS JOIN (VALUES ('Relato do Ocorrido', 0), ('Análise de Causa Raiz', 1), ('Plano de Ação', 2), ('Evidências e Fotos', 3), ('CAT', 4)) AS s(nome, ordem)
  WHERE p.tenant_id = v_t AND p.pasta_pai_id = v_inv AND p.nome LIKE 'Acidente EVT-%'
    AND NOT EXISTS (SELECT 1 FROM public.documento_pastas z WHERE z.tenant_id = v_t AND z.pasta_pai_id = p.id AND z.nome = s.nome);

  -- Documentos da empresa (pasta, arquivo, tipo, tamanho em KB, vencimento em dias, classificacao)
  INSERT INTO public.documentos (
    id, tenant_id, empresa_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
    observacoes, criado_por, criado_por_nome, pasta_id, classificacao, created_at
  )
  SELECT public.demo_id('doc_emp:' || d.pasta || ':' || d.arq), v_t, v_e, 'Empresa', 'demo/documentos/' || md5(d.arq) || '.pdf', d.arq, d.tipo, d.kb * 1024,
         CASE WHEN d.arq LIKE '%.xlsx' THEN 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ELSE 'application/pdf' END,
         'demo/documentos/' || md5(d.arq) || '.pdf',
         CASE WHEN d.venc IS NULL THEN NULL ELSE CURRENT_DATE + d.venc END,
         d.obs, v_uid, v_nome, (v_map ->> d.pasta)::uuid, 'comum', now() - ((10 + (length(d.arq) * 7) % 300) || ' days')::interval
  FROM (VALUES
    ('Governança e Administração > Estrutura Organizacional', 'Contrato Social - Metalúrgica Exemplo.pdf', 'Contrato', 920, NULL::int, 'Contrato social consolidado.'),
    ('Governança e Administração > Estrutura Organizacional', 'Alterações Contratuais 2025.pdf', 'Contrato', 410, NULL, NULL),
    ('Governança e Administração > Estrutura Organizacional', 'Organograma 2026.pdf', 'Outros', 260, NULL, NULL),
    ('Governança e Administração > Estrutura Organizacional', 'Estrutura de Cargos e Salários 2026.pdf', 'Outros', 540, NULL, NULL),
    ('Governança e Administração > Direcionamento Estratégico', 'Missão, Visão e Valores.pdf', 'Outros', 180, NULL, NULL),
    ('Governança e Administração > Direcionamento Estratégico', 'Política da Qualidade.pdf', 'Outros', 220, NULL, NULL),
    ('Governança e Administração > Direcionamento Estratégico', 'Política de SST.pdf', 'Outros', 205, NULL, 'Assinada pela diretoria.'),
    ('Governança e Administração > Políticas e Diretrizes', 'Política de Segurança da Informação.pdf', 'Outros', 330, NULL, NULL),
    ('Governança e Administração > Licenças e Autorizações', 'Alvará de Funcionamento 2026.pdf', 'Certificado', 300, 200, NULL),
    ('Governança e Administração > Licenças e Autorizações', 'Licença Corpo de Bombeiros (AVCB).pdf', 'Certificado', 450, 45, 'Renovação do AVCB em andamento.'),
    ('Governança e Administração > Certidões', 'Certidão Federal - Débitos e Dívida Ativa.pdf', 'Certificado', 120, 85, NULL),
    ('Governança e Administração > Certidões', 'Certidão Estadual.pdf', 'Certificado', 110, 120, NULL),
    ('Governança e Administração > Certidões', 'Certidão Municipal.pdf', 'Certificado', 95, -12, 'Vencida, solicitar nova certidão.'),
    ('Governança e Administração > Certidões', 'Certidão FGTS (CRF).pdf', 'Certificado', 90, 18, NULL),
    ('Governança e Administração > Certidões', 'Certidão INSS.pdf', 'Certificado', 105, 140, NULL),
    ('Governança e Administração > Certidões', 'Certidão Trabalhista (CNDT).pdf', 'Certificado', 98, 90, NULL),
    ('Governança e Administração > Registros em Conselhos', 'Registro no CREA da empresa.pdf', 'Certificado', 140, 320, NULL),
    ('Sistema de Gestão > Procedimentos e Instruções de Trabalho', 'POP-001 Operação de Torno CNC.pdf', 'Outros', 380, NULL, NULL),
    ('Sistema de Gestão > Procedimentos e Instruções de Trabalho', 'POP-007 Soldagem MIG-MAG.pdf', 'Outros', 410, NULL, NULL),
    ('Sistema de Gestão > Registros da Qualidade', 'Relatório de Inspeção Final - setembro 2026.pdf', 'Outros', 700, NULL, NULL),
    ('Processos Organizacionais > Mapeamento de Processos', 'Fluxogramas de Produção.pdf', 'Outros', 520, NULL, NULL),
    ('Processos Organizacionais > Mapeamento de Processos', 'Cadeia de Valor.pdf', 'Outros', 240, NULL, NULL),
    ('Processos Organizacionais > Procedimentos Operacionais', 'POPs Usinagem e Solda - consolidado.pdf', 'Outros', 1300, NULL, NULL),
    ('Processos Organizacionais > Procedimentos Operacionais', 'Instruções de Trabalho IT-001 a IT-020.pdf', 'Outros', 980, NULL, NULL),
    ('Processos Organizacionais > Gestão da Qualidade', 'Procedimentos de Qualidade PQ-01 a PQ-08.pdf', 'Outros', 860, NULL, NULL),
    ('Processos Organizacionais > Gestão da Qualidade', 'Indicadores de Desempenho 2026.xlsx', 'Outros', 160, NULL, NULL),
    ('Gestão de Riscos > Inventário de Riscos', 'Riscos Operacionais - inventário da produção.pdf', 'Outros', 640, NULL, NULL),
    ('Gestão de Riscos > Inventário de Riscos', 'Riscos de SST - inventário do PGR.pdf', 'Outros', 720, NULL, NULL),
    ('Gestão de Riscos > Matriz de Riscos', 'Classificação de Risco - matriz 5x5.pdf', 'Outros', 190, NULL, NULL),
    ('Gestão de Riscos > Matriz de Riscos', 'Probabilidade e escalas de avaliação.pdf', 'Outros', 150, NULL, NULL),
    ('Gestão de Riscos > Planos de Emergência', 'Plano de Atendimento a Emergências (PAE).pdf', 'Outros', 1100, 240, 'Revisão anual com a brigada.'),
    ('SST > Treinamentos > NR-01 — Disposições Gerais e Gerenciamento de Riscos', 'NR-01 — Disposições Gerais - lista de presença 2026.pdf', 'Treinamento NR', 210, NULL, NULL),
    ('SST > Treinamentos > NR-05 — CIPA', 'NR-05 — CIPA - ata de posse e certificados.pdf', 'Treinamento NR', 340, 210, NULL),
    ('SST > Treinamentos > NR-06 — EPIs', 'NR-06 — EPIs - treinamento de uso e conservação 2026.pdf', 'Treinamento NR', 290, NULL, NULL),
    ('SST > Treinamentos > NR-10 — Instalações Elétricas', 'NR-10 - certificados da equipe elétrica.pdf', 'Treinamento NR', 810, 60, 'Reciclagem agendada para os próximos dois meses.'),
    ('SST > Treinamentos > NR-11 — Transporte de Cargas', 'NR-11 - habilitação dos operadores de empilhadeira.pdf', 'Treinamento NR', 560, 150, NULL),
    ('SST > Treinamentos > NR-12 — Máquinas e Equipamentos', 'NR-12 - treinamento dos operadores de prensa.pdf', 'Treinamento NR', 430, 280, NULL),
    ('SST > Treinamentos > NR-35 — Trabalho em Altura', 'NR-35 - certificados trabalho em altura.pdf', 'Treinamento NR', 470, 35, NULL),
    ('SST > Registros e Evidências', 'Investigação de Acidentes - relatório consolidado 2026.pdf', 'Outros', 1500, NULL, NULL),
    ('SST > Registros e Evidências > Inspeções de Segurança', 'Inspeção de Segurança - outubro 2026.pdf', 'Outros', 620, NULL, NULL),
    ('SST > Registros e Evidências > Inspeções de Segurança', 'APR — Análise Preliminar de Risco - Prensa 02.pdf', 'Outros', 390, 100, NULL),
    ('SST > Registros e Evidências > Permissões de Trabalho', 'Permissões de Trabalho - registro mensal setembro.pdf', 'Outros', 270, NULL, NULL),
    ('Cultura Organizacional > Manual de Cultura', 'Manual de Cultura Metalúrgica Exemplo.pdf', 'Outros', 1900, NULL, NULL),
    ('Cultura Organizacional > Documentos da Cultura', 'Código de Conduta (rascunho).pdf', 'Outros', 330, NULL, 'Em revisão pelo jurídico.'),
    ('Auditorias e Melhoria Contínua > Auditorias Internas', 'Relatórios - auditoria interna ISO 9001 2026.pdf', 'Outros', 1250, NULL, NULL),
    ('Auditorias e Melhoria Contínua > Auditorias Internas', 'Checklists de auditoria interna.pdf', 'Outros', 180, NULL, NULL),
    ('Auditorias e Melhoria Contínua > Auditorias Externas e Certificações', 'Certificado ISO 9001 - Metalúrgica Exemplo.pdf', 'Certificado', 380, 130, 'Auditoria de manutenção em fevereiro.'),
    ('Auditorias e Melhoria Contínua > Ações Corretivas e Preventivas', 'Relatório de Ações Corretivas - 3º trimestre.pdf', 'Outros', 540, NULL, NULL),
    ('Gestão Ambiental > Licenciamento Ambiental', 'Licença de Operação 2025.pdf', 'Certificado', 480, 150, NULL),
    ('Gestão Ambiental > Licenciamento Ambiental', 'Licença de Instalação - galpão 2.pdf', 'Certificado', 420, NULL, NULL),
    ('Gestão Ambiental > Planos Ambientais', 'PGRS — Plano de Gerenciamento de Resíduos 2026.pdf', 'Outros', 760, 330, NULL)
  ) AS d(pasta, arq, tipo, kb, venc, obs)
  WHERE (v_map ->> d.pasta) IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.documentos z WHERE z.id = public.demo_id('doc_emp:' || d.pasta || ':' || d.arq));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentos (pastas e documentos da empresa) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $doc1$;

-- ---------------------------------------------------------------------------
-- (6) Documentos — documentos SST espelhados, investigacao dos acidentes, documentos dos colaboradores e historico
-- ---------------------------------------------------------------------------
DO $doc2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Documentos SST: o sistema grava uma copia em Documentos (tipo SST - ...) na pasta do programa
  INSERT INTO public.documentos (
    id, tenant_id, empresa_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
    observacoes, criado_por, criado_por_nome, pasta_id, classificacao, created_at
  )
  SELECT public.demo_id('doc_sst:' || s.id::text), v_t, v_e, 'Empresa', s.arquivo_url, s.arquivo_nome, 'SST - ' || s.tipo, COALESCE(s.arquivo_tamanho, 900000)::int,
         'application/pdf', s.arquivo_url, s.data_vigencia, 'Documento SST: ' || s.tipo, v_uid, v_nome, pf.id, 'comum', s.created_at
  FROM public.sst_documentos s
  JOIN LATERAL (
    SELECT p.id
    FROM public.documento_pastas p
    LEFT JOIN public.documento_pastas pai ON pai.id = p.pasta_pai_id
    WHERE p.tenant_id = v_t AND p.empresa_id = v_e
      AND p.nome = CASE s.tipo
            WHEN 'PGR' THEN 'PGR' WHEN 'PCMSO' THEN 'PCMSO' WHEN 'LTCAT' THEN 'LTCAT'
            WHEN 'AET' THEN 'AET — Análise Ergonômica do Trabalho' WHEN 'AEP' THEN 'AEP — Avaliação Ergonômica Preliminar'
            WHEN 'LAUDO_INSALUBRIDADE' THEN 'Laudos de Insalubridade' WHEN 'LAUDO_PERICULOSIDADE' THEN 'Laudos de Periculosidade'
            WHEN 'APR' THEN 'Análise de Riscos (APR / HAZOP)' WHEN 'PPRA' THEN 'Programas Legais' ELSE 'Registros e Evidências' END
      AND (pai.nome IS NULL OR pai.nome IN ('Programas Legais', 'Gestão de Riscos', 'SST'))
    ORDER BY p.created_at LIMIT 1
  ) pf ON true
  WHERE s.tenant_id = v_t AND s.id IN (SELECT public.demo_id('sst_doc:' || k) FROM unnest(ARRAY['pgr_atual','pgr_anterior','pcmso','ltcat','aet','aep','ins','per','apr','dosimetria','ppra']) AS k)
    AND NOT EXISTS (SELECT 1 FROM public.documentos z WHERE z.id = public.demo_id('doc_sst:' || s.id::text));

  -- Comunicacoes de acidente (CAT) na pasta de registros e, em cada acidente, relato, causa raiz e CAT na pasta de investigacao
  INSERT INTO public.documentos (
    id, tenant_id, empresa_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
    observacoes, criado_por, criado_por_nome, pasta_id, classificacao, created_at
  )
  SELECT public.demo_id('doc_cat:' || e.id::text), v_t, v_e, 'Empresa', 'demo/documentos/cat_' || e.codigo || '.pdf',
         'CAT — Comunicação de Acidente ' || e.cat_numero || '.pdf', 'Outros', 260000, 'application/pdf', 'demo/documentos/cat_' || e.codigo || '.pdf', NULL,
         'CAT do evento ' || e.codigo, v_uid, v_nome, pf.id, 'sensivel_saude', e.created_at + interval '1 day'
  FROM public.eventos_sst e
  JOIN LATERAL (SELECT p.id FROM public.documento_pastas p
                 WHERE p.tenant_id = v_t AND p.nome = 'CAT — Comunicação de Acidente' ORDER BY p.created_at LIMIT 1) pf ON true
  WHERE e.tenant_id = v_t AND e.tipo = 'acidente' AND e.cat_emitida AND e.cat_numero IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.documentos z WHERE z.id = public.demo_id('doc_cat:' || e.id::text));

  INSERT INTO public.documentos (
    id, tenant_id, empresa_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, data_validade,
    observacoes, criado_por, criado_por_nome, pasta_id, classificacao, created_at
  )
  SELECT public.demo_id('doc_evt:' || e.id::text || ':' || s.sub), v_t, v_e, 'Empresa', 'demo/documentos/' || e.codigo || '_' || s.k || '.pdf',
         s.sub || ' ' || e.codigo || '.pdf', 'Outros', 180000 + s.ord * 50000, 'application/pdf', 'demo/documentos/' || e.codigo || '_' || s.k || '.pdf', NULL,
         'Documento da investigação do evento ' || e.codigo, v_uid, v_nome, sp.id, 'sensivel_saude', e.created_at + (s.ord || ' days')::interval
  FROM public.eventos_sst e
  JOIN public.documento_pastas pe ON pe.tenant_id = v_t AND pe.pasta_pai_id IS NOT NULL
        AND pe.nome = 'Acidente ' || e.codigo || ' — ' || to_char(e.data_evento, 'DD/MM/YYYY')
  CROSS JOIN (VALUES ('Relato do Ocorrido', 'relato', 1, 'todos'), ('Análise de Causa Raiz', 'causa', 2, 'investigado'),
                     ('Plano de Ação', 'plano', 3, 'acoes'), ('CAT', 'cat', 4, 'cat')) AS s(sub, k, ord, quando)
  JOIN public.documento_pastas sp ON sp.pasta_pai_id = pe.id AND sp.nome = s.sub
  WHERE e.tenant_id = v_t AND e.tipo = 'acidente'
    AND (s.quando = 'todos'
         OR (s.quando = 'investigado' AND e.status IN ('em_analise', 'acoes_andamento', 'concluido'))
         OR (s.quando = 'acoes' AND e.status IN ('acoes_andamento', 'concluido'))
         OR (s.quando = 'cat' AND e.cat_emitida))
    AND NOT EXISTS (SELECT 1 FROM public.documentos z WHERE z.id = public.demo_id('doc_evt:' || e.id::text || ':' || s.sub));

  -- Documentos dos colaboradores: ASO periodico, contrato de trabalho e ficha de EPI nas subpastas de cada pasta pessoal
  INSERT INTO public.documentos (
    id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf, nome_arquivo, nome_original, tipo, tamanho, mime_type,
    storage_path, data_validade, observacoes, criado_por, criado_por_nome, pasta_id, classificacao, created_at
  )
  SELECT public.demo_id('doc_colab:' || a.id::text || ':' || d.tipo), v_t, v_e, a.id, a.nome_completo, a.cpf,
         'demo/documentos/' || md5(a.id::text || d.tipo) || '.pdf', d.arq || ' - ' || a.nome_completo || '.pdf', d.tipo, d.kb * 1024, 'application/pdf',
         'demo/documentos/' || md5(a.id::text || d.tipo) || '.pdf',
         CASE d.tipo WHEN 'ASO' THEN CURRENT_DATE - 25 + ((a.n * 13) % 420)
                     WHEN 'Recibo de EPI' THEN CURRENT_DATE + 120 + ((a.n * 7) % 200) END,
         d.obs, v_uid, v_nome, sp.id, d.classif, now() - ((20 + (a.n * 11) % 330) || ' days')::interval
  FROM (
    SELECT x.n, ad.id, ad.nome_completo, ad.cpf
    FROM generate_series(1, 59) AS x(n)
    JOIN public.admissoes ad ON ad.id = public.demo_id('admissao:' || x.n) AND ad.tenant_id = v_t AND ad.status = 'concluido'
  ) a
  JOIN (VALUES
    ('ASO', 'ASO Periódico 2026', 'Saúde Ocupacional', 180, 'sensivel_saude', 'Apto para a função, sem restrições.'),
    ('Contrato', 'Contrato de Trabalho', 'Admissão', 310, 'pessoal', NULL),
    ('Recibo de EPI', 'Ficha de EPI', 'Saúde Ocupacional', 140, 'comum', 'Ficha atualizada com as entregas do módulo de EPIs.')
  ) AS d(tipo, arq, sub, kb, classif, obs) ON (d.tipo <> 'ASO' OR a.n % 7 <> 0) AND (d.tipo <> 'Recibo de EPI' OR a.n <= 52)
  JOIN public.documento_pastas pc ON pc.tenant_id = v_t AND pc.tipo = 'colaborador' AND pc.colaborador_id = a.id
  JOIN public.documento_pastas sp ON sp.pasta_pai_id = pc.id AND sp.nome = d.sub
  WHERE NOT EXISTS (SELECT 1 FROM public.documentos z WHERE z.id = public.demo_id('doc_colab:' || a.id::text || ':' || d.tipo));

  -- Historico de auditoria: envios, movimentacoes, renomeacoes, exclusao e restauracao
  INSERT INTO public.documento_audit_log (
    id, tenant_id, documento_id, documento_nome, acao, pasta_origem_id, pasta_origem_nome, pasta_destino_id, pasta_destino_nome,
    dados_anteriores, dados_novos, usuario_id, usuario_nome, ip_address, created_at
  )
  SELECT public.demo_id('doc_audit:' || q.id::text), v_t, q.id, q.nome_original,
         CASE WHEN q.rn <= 18 THEN 'upload' WHEN q.rn <= 21 THEN 'move' WHEN q.rn <= 23 THEN 'rename' WHEN q.rn = 24 THEN 'delete' ELSE 'restore' END,
         CASE WHEN q.rn BETWEEN 19 AND 21 THEN public.demo_id('pasta:Governança e Administração') END,
         CASE WHEN q.rn BETWEEN 19 AND 21 THEN 'Governança e Administração' END,
         CASE WHEN q.rn BETWEEN 19 AND 21 THEN q.pasta_id END,
         CASE WHEN q.rn BETWEEN 19 AND 21 THEN (SELECT p.nome FROM public.documento_pastas p WHERE p.id = q.pasta_id) END,
         CASE WHEN q.rn BETWEEN 22 AND 23 THEN jsonb_build_object('nome', 'Rascunho - ' || q.nome_original) END,
         CASE WHEN q.rn BETWEEN 22 AND 23 THEN jsonb_build_object('nome', q.nome_original) END,
         v_uid, v_nome, '10.20.2.' || (10 + q.rn)::text, now() - ((q.rn * 4) || ' days')::interval
  FROM (
    SELECT d.id, d.nome_original, d.pasta_id, row_number() OVER (ORDER BY d.created_at DESC, d.id) AS rn
    FROM public.documentos d
    WHERE d.tenant_id = v_t AND d.colaborador_nome = 'Empresa'
  ) q
  WHERE q.rn <= 25
    AND NOT EXISTS (SELECT 1 FROM public.documento_audit_log z WHERE z.id = public.demo_id('doc_audit:' || q.id::text));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentos (SST, investigacao, colaboradores e historico) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $doc2$;

-- ---------------------------------------------------------------------------
-- Conferencia final (uma linha)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.sst_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS sst_documentos,
  (SELECT count(*) FROM public.ordens_servico WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ordens_servico,
  (SELECT count(*) FROM public.plano_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND origem_modulo = 'compliance_sst') AS acoes_compliance,
  (SELECT count(*) FROM public.terceiros WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS terceiros,
  (SELECT count(*) FROM public.terceiro_trabalhadores WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS terceiros_trabalhadores,
  (SELECT count(*) FROM public.terceiro_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS terceiros_documentos,
  (SELECT count(*) FROM public.terceiro_treinamentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS terceiros_treinamentos,
  (SELECT count(*) FROM public.permissoes_trabalho WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS permissoes_trabalho,
  (SELECT count(*) FROM public.trilhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND publico_terceiros) AS trilhas_terceiros,
  (SELECT count(*) FROM public.documento_pastas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS pastas,
  (SELECT count(*) FROM public.documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS documentos,
  (SELECT count(*) FROM public.documento_audit_log WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS historico_documentos,
  CASE WHEN (SELECT count(*) FROM public.sst_documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 11
        AND (SELECT count(*) FROM public.ordens_servico WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 40
        AND (SELECT count(*) FROM public.terceiros WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 10
        AND (SELECT count(*) FROM public.documentos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 100
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
