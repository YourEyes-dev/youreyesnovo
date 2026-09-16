-- =========================================================
-- QA — Programa de Parceiros (Onda 0): documentação dos casos.
--
-- Contexto: o Portal do Parceiro e a gestão de carteira nascem fora do
-- sistema (acesso pelo site), com uma identidade que pode ser também
-- profissional do Marketplace (família PARC, já documentada em
-- rede-parceiros). Para não colidir com PARC-*, esta família usa o
-- prefixo PGP (Programa de Parceiros) e vive no submódulo
-- rede-parceiros/programa-parceiros.
--
-- Regra da casa: documentação antes do teste. Casos 'api' ganham rotina
-- na migration de rotinas da mesma entrega quando a estrutura que testam
-- já existe (Onda 1); os demais ficam documentados e aparecem como
-- "nao_implementado" na bateria até a onda correspondente. Casos 'e2e'
-- só ganham it() no Cypress depois de documentados aqui.
--
-- Decisões do dono do produto (03/09/2026) refletidas nos casos:
--   * indicador é aprovado automaticamente; demais tipos, manualmente;
--   * implantador ganha pelo setup, com valor configurável por evento;
--   * lead da casa recebe sugestão de parceiro por proximidade;
--   * a aba Afiliados do Marketplace migra para este programa.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_pai uuid; v_mod uuid; v_antes int; v_depois int;
BEGIN
  SELECT id INTO v_pai FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_pai IS NULL THEN
    INSERT INTO public.qa_modulos (label, path, icone, ordem)
    VALUES ('Rede de Parceiros', 'rede-parceiros', '🤝', 90)
    RETURNING id INTO v_pai;
  END IF;

  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros/programa-parceiros';
  IF v_mod IS NULL THEN
    INSERT INTO public.qa_modulos (parent_id, label, path, icone, ordem)
    VALUES (v_pai, 'Programa de Parceiros', 'rede-parceiros/programa-parceiros', '🔗', 2)
    RETURNING id INTO v_mod;
  END IF;

  SELECT count(*) INTO v_antes FROM public.qa_casos_teste WHERE modulo_id = v_mod;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES

  -- ══════════ A) CADASTRO, APROVAÇÃO E IDENTIDADE (Onda 1) ══════════

  (v_mod, 'PGP-001', 'Indicador nasce ativo; representante, implantador, clínica e contabilidade nascem pendentes',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026): aprovação automática só para indicador',
   'O indicador só gera link e não fala em nome da casa: pode entrar sozinho. Quem representa, implanta ou atende o cliente precisa de aprovação humana antes de aparecer como parceiro ativo.',
   'Tabela parceiros com regra de status inicial por tipo.',
   '[{"ordem":1,"acao":"Cadastrar parceiro do tipo indicador sem informar status","resultado_esperado":"Status ativo e aprovacao = automatica"},
     {"ordem":2,"acao":"Cadastrar parceiro do tipo implantador sem informar status","resultado_esperado":"Status pendente e aprovacao = manual"}]'::jsonb,
   'Só o indicador entra sem aprovação.',
   'Sonda de escrita: insere dois parceiros sintéticos (código QA-*) e apaga ao final.'),

  (v_mod, 'PGP-002', 'Código do parceiro é único e o link principal nasce junto com o cadastro',
   'feliz', 'alta', 'aprovado', 'api',
   'Mockup do Portal do Parceiro (link principal ?ref=CODIGO)',
   'Todo parceiro tem um código único que vira o link principal de indicação. Sem o link automático, o parceiro aprovado fica sem o que compartilhar.',
   'Tabela parceiros e parceiro_links.',
   '[{"ordem":1,"acao":"Cadastrar parceiro com código QA-PGP-002","resultado_esperado":"Existe um parceiro_links com o mesmo código, campanha principal, ativo"},
     {"ordem":2,"acao":"Tentar cadastrar outro parceiro com o mesmo código","resultado_esperado":"Recusado por unicidade"}]'::jsonb,
   'Um código, um parceiro, um link principal automático.',
   NULL),

  (v_mod, 'PGP-003', 'Isolamento: parceiro só lê a própria carteira e comissões; leitura direta das tabelas não vaza',
   'negativo', 'critica', 'aprovado', 'api',
   'LGPD art. 46 (segurança) e política de acesso da casa (RLS em toda tabela com dado de terceiro)',
   'Carteira e comissão são dados comerciais de cada parceiro. A leitura precisa ser restrita ao próprio vínculo (parceiro_usuarios) e ao superadmin; nenhuma política pode abrir SELECT para qualquer autenticado.',
   'RLS ligada em parceiros, parceiro_usuarios, parceiro_links, parceiro_link_cliques e parceiro_comissoes.',
   '[{"ordem":1,"acao":"AUDITORIA: RLS ligada nas 5 tabelas","resultado_esperado":"relrowsecurity = true em todas"},
     {"ordem":2,"acao":"AUDITORIA: nenhuma política permissiva de SELECT com USING (true) para authenticated","resultado_esperado":"Só políticas que citam parceiro_usuarios ou is_superadmin"}]'::jsonb,
   'Sem RLS ou com política aberta = falha.',
   'Tabelas de parceiro não são por tenant: não entram em entitlement_gated_tables nem em perfil_permite_modulo. Se PERFIL-003 acusar, a exceção é documentada aqui.'),

  (v_mod, 'PGP-004', 'Origem do cliente fica no tenant e apagar o parceiro não apaga o cliente',
   'excecao', 'alta', 'aprovado', 'api',
   'Planejamento do Portal do Parceiro, seção 2.7 (FK ON DELETE SET NULL)',
   'O tenant guarda quem o originou (parceiro, link, data) e quem o implantou. Encerrar um parceiro não pode arrastar o cliente: as chaves apontam para o parceiro com SET NULL.',
   'Colunas parceiro_id, parceiro_link_id, originado_em e implantador_parceiro_id em tenants; parceiro_id e atribuicao em leads.',
   '[{"ordem":1,"acao":"AUDITORIA: colunas existem em tenants e leads","resultado_esperado":"Todas presentes"},
     {"ordem":2,"acao":"AUDITORIA: regra de exclusão das FKs tenants→parceiros e leads→parceiros","resultado_esperado":"SET NULL, nunca CASCADE"}]'::jsonb,
   'Cliente sobrevive ao parceiro.',
   NULL),

  (v_mod, 'PGP-005', 'Remuneração por evento (setup, go-live, renovação) é configurável, não fixa no código',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026): o implantador ganha pelo setup e o valor é configurável',
   'O ganho por evento vive em tabela editável pelo SuperAdmin (por trilha e tipo de parceiro), com valor fixo ou percentual da primeira mensalidade. Nenhuma função pode ter o valor do setup escrito à mão.',
   'Tabela parceiro_eventos_remuneracao semeada.',
   '[{"ordem":1,"acao":"AUDITORIA: tabela existe com evento setup_concluido para implantador","resultado_esperado":"Linha semeada, ativa"},
     {"ordem":2,"acao":"AUDITORIA: função de fechamento (quando existir) lê a tabela e não um literal","resultado_esperado":"Corpo referencia parceiro_eventos_remuneracao"}]'::jsonb,
   'Valor de setup editável na tela, lido pelo motor.',
   'Na Onda 1 só a tabela e a semente existem; a leitura pelo motor entra na Onda 3 e a sonda passa a exigir.'),

  (v_mod, 'PGP-006', 'Níveis por trilha: faixa de MRR e percentual vêm de tabela e o próximo nível é calculável',
   'feliz', 'media', 'aprovado', 'api',
   'Mockup (Trilha Operador · Nível Visão → Diamante, 25% → 30%)',
   'A barra "faltam R$ X para Diamante" depende de níveis ordenados por trilha com mrr_minimo e percentual. Sem tabela, a promoção vira código.',
   'parceiro_niveis semeada com a trilha operador.',
   '[{"ordem":1,"acao":"AUDITORIA: trilha operador tem ao menos 2 níveis ordenados com mrr_minimo crescente","resultado_esperado":"Visão (0) e Diamante (> 0)"}]'::jsonb,
   'Níveis em tabela, ordenados, com percentual.',
   NULL),

  -- ══════════ B) MOTOR (Ondas 3 e 4 — documentados, sem rotina ainda) ══════════

  (v_mod, 'PGP-010', 'Comissão zero em plano interno ou não público (tester)',
   'negativo', 'alta', 'aprovado', 'api',
   'plans.is_public = false não gera receita',
   'Tenant em plano interno aparece na carteira com aviso e comissão zero; o fechamento não pode gerar valor sobre plano de teste.',
   'Motor de fechamento (Onda 3).',
   '[{"ordem":1,"acao":"Fechar competência com tenant em plano tester vinculado a parceiro","resultado_esperado":"Comissão gerada com valor 0 e observação"}]'::jsonb,
   'Plano interno não remunera.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-011', 'Estágio da carteira derivado com precedência (Churn > Ativo > Go-live > Implantação > Contrato > Proposta > Lead)',
   'feliz', 'alta', 'aprovado', 'api',
   'Planejamento, seção 3 (tabela de estágio derivado)',
   'O estágio não é gravado: é calculado de subscriptions, contratos, onboarding e leads. A precedência precisa ser estável para o funil não mudar sozinho.',
   'Função parceiro_estagio_tenant (Onda 2).',
   '[{"ordem":1,"acao":"Tenant cancelado que também tem contrato assinado","resultado_esperado":"Churn"},
     {"ordem":2,"acao":"Tenant ativo há mais de 30 dias após go-live","resultado_esperado":"Ativo"},
     {"ordem":3,"acao":"Lead em negociação sem tenant","resultado_esperado":"Proposta"}]'::jsonb,
   'Um estágio por conta, pela precedência documentada.', 'Rotina na Onda 2.'),

  (v_mod, 'PGP-012', 'Fechamento de competência é idempotente e respeita 25/10',
   'excecao', 'critica', 'aprovado', 'api',
   'Mockup (fecha dia 25, paga até dia 10)',
   'Rodar o fechamento duas vezes na mesma competência não duplica comissão; o status segue previsto → fechado → pago/retido.',
   'Função parceiro_fechar_competencia (Onda 3).',
   '[{"ordem":1,"acao":"Fechar a mesma competência duas vezes","resultado_esperado":"Mesmo número de linhas, mesmos valores"}]'::jsonb,
   'Fechar duas vezes = fechar uma vez.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-013', 'Setup do implantador gera comissão por evento quando o onboarding do cliente conclui',
   'feliz', 'alta', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026)',
   'Quando o cliente atendido por um implantador conclui o onboarding, o fechamento gera uma comissão do tipo evento com o valor configurado em parceiro_eventos_remuneracao.',
   'Onda 3.',
   '[{"ordem":1,"acao":"Tenant com implantador_parceiro_id conclui onboarding","resultado_esperado":"Uma comissão tipo evento/setup_concluido, valor da tabela"}]'::jsonb,
   'Setup pago pela tabela, uma vez por cliente.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-014', 'Lead da casa recebe sugestão de parceiro por proximidade e a atribuição fica marcada como casa',
   'feliz', 'media', 'aprovado', 'api',
   'Decisão do dono do produto (03/09/2026); planejamento seção 3.1',
   'Lead sem link de origem recebe até 5 parceiros ativos sugeridos (mesma cidade → raio → UF). Ao encaminhar, leads.atribuicao = casa, distinto de link.',
   'Função parceiros_sugerir_para_lead (Onda 3).',
   '[{"ordem":1,"acao":"Sugerir para lead em cidade com parceiro ativo","resultado_esperado":"Parceiro da cidade em primeiro"},
     {"ordem":2,"acao":"Encaminhar lead ao parceiro","resultado_esperado":"atribuicao = casa"}]'::jsonb,
   'Proximidade ordena; atribuição registra a origem.', 'Rotina na Onda 3.'),

  (v_mod, 'PGP-015', 'Link ?ref= grava a origem no lead da landing, no checkout e no tenant provisionado',
   'feliz', 'alta', 'aprovado', 'api',
   'Planejamento, seção 2.6',
   'O código do link viaja da landing (ref_codigo) ao checkout (metadata) e ao webhook, que grava parceiro_id no tenant. Sem isso, a carteira do parceiro fica vazia.',
   'Onda 4.',
   '[{"ordem":1,"acao":"Inserir landing_lead com ref_codigo de link válido","resultado_esperado":"Lead atribuído ao parceiro do link"}]'::jsonb,
   'Origem preservada de ponta a ponta.', 'Rotina na Onda 4.'),

  -- ══════════ C) TELA (e2e) ══════════

  (v_mod, 'PGP-020', 'SuperAdmin: aba Parceiros lista, cadastra e mostra o status inicial pelo tipo',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'O SuperAdmin cadastra um parceiro pela aba Parceiros e vê o status correto (indicador ativo; implantador pendente).',
   'Login de superadmin no site de teste.',
   '[{"ordem":1,"acao":"Abrir /admin e clicar na aba Parceiros","resultado_esperado":"Lista de parceiros e botão Novo parceiro"},
     {"ordem":2,"acao":"Cadastrar parceiro tipo implantador","resultado_esperado":"Aparece na lista com selo Pendente"}]'::jsonb,
   'Cadastro pela tela reflete a regra de aprovação.', 'Cypress: cypress/e2e/parceiros-admin.cy.ts'),

  (v_mod, 'PGP-021', 'SuperAdmin: aprovar parceiro pendente e vincular uma empresa à carteira',
   'feliz', 'alta', 'aprovado', 'e2e',
   NULL,
   'Aprovar muda o selo para Ativo; vincular uma empresa faz o parceiro aparecer como origem no detalhe da empresa.',
   'Parceiro pendente existente.',
   '[{"ordem":1,"acao":"Clicar Aprovar no parceiro pendente","resultado_esperado":"Selo Ativo"},
     {"ordem":2,"acao":"Vincular empresa ao parceiro","resultado_esperado":"Empresa listada na carteira; detalhe da empresa mostra Parceiro de origem"}]'::jsonb,
   'Aprovação e vínculo visíveis nas duas telas.', 'Cypress: cypress/e2e/parceiros-admin.cy.ts'),

  (v_mod, 'PGP-030', 'Parceiro sem empresa loga pelo site e cai na Área do Parceiro, não no sistema',
   'feliz', 'critica', 'aprovado', 'e2e',
   'Planejamento, seção 2.4',
   'Usuário vinculado a um parceiro e sem profile de tenant entra em /parceiros/entrar e é levado a /parceiro; nunca vê o menu do sistema.',
   'Usuário-parceiro semeado no staging (Onda 2).',
   '[{"ordem":1,"acao":"Login em /parceiros/entrar","resultado_esperado":"Redireciona para /parceiro com cabeçalho do parceiro"}]'::jsonb,
   'Portal próprio, fora do sistema.', 'Onda 2.'),

  (v_mod, 'PGP-031', 'Portal: copiar o link de indicação',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL, 'O botão Copiar coloca o link completo (com o código do parceiro) na área de transferência e confirma.',
   'Parceiro ativo logado.',
   '[{"ordem":1,"acao":"Clicar Copiar","resultado_esperado":"Texto Copiado e link contém ?ref=CODIGO"}]'::jsonb,
   'Link copiado com o código.', 'Onda 2.'),

  (v_mod, 'PGP-032', 'Portal: carteira lista as empresas originadas com estágio e exporta CSV',
   'feliz', 'media', 'aprovado', 'e2e',
   NULL, 'A carteira mostra só as empresas do parceiro, com plano, MRR, estágio e comissão, e o botão Exportar gera CSV.',
   'Parceiro com ao menos uma empresa vinculada.',
   '[{"ordem":1,"acao":"Abrir /parceiro","resultado_esperado":"Tabela com as empresas do parceiro"},
     {"ordem":2,"acao":"Clicar Exportar","resultado_esperado":"CSV com as mesmas linhas"}]'::jsonb,
   'Só a própria carteira, exportável.', 'Onda 2.')

  ON CONFLICT (codigo) DO NOTHING;

  SELECT count(*) INTO v_depois FROM public.qa_casos_teste WHERE modulo_id = v_mod;
  RAISE NOTICE 'PGP: % casos antes, % depois.', v_antes, v_depois;
END $doc$;
