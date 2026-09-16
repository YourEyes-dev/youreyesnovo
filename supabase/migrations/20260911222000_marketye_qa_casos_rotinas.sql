-- =====================================================================
-- MARKETYE · QA: CASOS DOCUMENTADOS (MKY-*) E ROTINAS SOMENTE-LEITURA
--
-- A Documentação de testes é a fonte da verdade: cada regra sensível do
-- MarketYE vira um caso; os de nível 'api' ganham rotina qa_caso_mky_*()
-- (executadas por qa_rodar_bateria('manual','rede-parceiros'), sempre em
-- transação descartada); os de nível 'e2e' vivem no Cypress
-- (cypress/e2e/marketye.cy.ts) ligados pela ponte qa_cobertura_e2e.
--
-- O módulo de QA 'rede-parceiros' passa a se chamar MarketYE (o path fica,
-- porque está gravado nos casos PARC-* e nos filhos programa-parceiros).
-- Os casos PARC-001/002/004/024 ganham texto coerente com o comportamento
-- novo (cadastro nasce pendente; rejeição por moderação; avaliação só com
-- transação verificada).
--
-- Idempotente: casos com ON CONFLICT (codigo) DO UPDATE, rotinas com
-- CREATE OR REPLACE, ponte com ON CONFLICT DO NOTHING.
-- =====================================================================

SET lock_timeout = '10s';

UPDATE public.qa_modulos SET label = 'MarketYE', icone = '🏪' WHERE path = 'rede-parceiros' AND label <> 'MarketYE';

-- Trava do cercado do QA nas tabelas novas com tenant_id que as rotinas tocam.
-- marketplace_demanda_latente fica de fora de propósito: só guarda contadores
-- (empresa × categoria × UF × dia), sem dado pessoal, e a rotina MKY-005
-- precisa de cinco empresas distintas para provar a célula mínima.
DO $cerca$
DECLARE t text;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN RETURN; END IF;
  FOREACH t IN ARRAY ARRAY['marketplace_leads'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'qa_guarda_cercado' AND tgrelid = ('public.' || t)::regclass AND NOT tgisinternal) THEN
      EXECUTE format('CREATE TRIGGER qa_guarda_cercado BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()', t);
    END IF;
    INSERT INTO public.qa_tabelas_protegidas (tabela, motivo) VALUES (t, 'MarketYE: tabela tem tenant_id') ON CONFLICT (tabela) DO NOTHING;
  END LOOP;
END $cerca$;

-- ---------------------------------------------------------------------
-- 1) Casos documentados
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes) VALUES
  (v_mod, 'MKY-001', 'Cadastro do especialista nasce pendente, com consentimento versionado; cadastro direto pela tabela também nasce pendente',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 7º/8º (consentimento); RN-001, RN-012, RN-018, RN-021',
   'Todo cadastro — por função ou por INSERT direto — entra como pendente, sem selo, e registra as três versões de termos aceitas.',
   'Versões de termos em marketplace_config (chave termos_versoes).',
   '[{"ordem":1,"acao":"Cadastrar especialista pela função com CPF fictício válido e aceite dos termos","resultado_esperado":"status pendente, selo false, 3 consentimentos, linha de reputação criada"},
     {"ordem":2,"acao":"Repetir o cadastro com o mesmo CPF em outra conta","resultado_esperado":"recusado: CPF/CNPJ já possui cadastro"},
     {"ordem":3,"acao":"Como usuário autenticado, inserir direto na tabela com status ativo e selo true","resultado_esperado":"a guarda rebaixa para pendente e selo false"}]'::jsonb,
   'Ninguém entra na vitrine sem passar pela verificação; consentimento fica registrado por versão.',
   'A rotina cria contas fictícias (@sandbox.invalid) e apaga tudo; roda em transação descartada.'),
  (v_mod, 'MKY-002', 'Perfil global: pendente não aparece na busca; aprovado aparece para empresas distintas; rascunho de anúncio não aparece',
   'feliz', 'critica', 'aprovado', 'api', 'RN-002, RN-011, RN-013; CA-003',
   'A vitrine é global (cross-tenant) e só mostra especialista ativo com anúncio publicado.',
   'Cercado qa-sandbox e uma segunda empresa sintética.',
   '[{"ordem":1,"acao":"Especialista pendente com anúncio salvo (rascunho)","resultado_esperado":"busca por nome não encontra"},
     {"ordem":2,"acao":"Publicar antes da aprovação","resultado_esperado":"recusado: cadastro em verificação"},
     {"ordem":3,"acao":"Superadmin aprova; especialista publica","resultado_esperado":"busca encontra a partir de duas empresas diferentes, com selo e nível"}]'::jsonb,
   'Mesmo anúncio visível para qualquer empresa cliente; nada vaza antes da verificação.',
   'Simula claims de superadmin, do especialista e de usuários de duas empresas.'),
  (v_mod, 'MKY-003', 'Avaliação só com transação verificada (lead ganho), nos dois sentidos, com recálculo da reputação',
   'negativo', 'critica', 'aprovado', 'api', 'RN-004, RN-005, RN-022; CA-007; CDC art. 6º (informação)',
   'Sem lead ganho ou contratação concluída ninguém avalia; depois, cliente e especialista avaliam uma vez cada e a nota média é recalculada.',
   'Especialista ativo com anúncio publicado.',
   '[{"ordem":1,"acao":"Empresa abre lead; tenta avaliar","resultado_esperado":"recusado: avaliações ficam disponíveis após o atendimento"},
     {"ordem":2,"acao":"Especialista responde; empresa marca serviço combinado (ganho); avalia","resultado_esperado":"aceita; nota_media e total_avaliacoes do especialista atualizados"},
     {"ordem":3,"acao":"Empresa avalia de novo o mesmo lead","resultado_esperado":"recusado: já avaliado"},
     {"ordem":4,"acao":"Especialista avalia a empresa","resultado_esperado":"aceita na direção especialista→cliente"}]'::jsonb,
   'Avaliação atrelada a transação real, bidirecional, uma por lado.', NULL),
  (v_mod, 'MKY-004', 'Piso de nota rebaixa a visibilidade orgânica e o destaque pago não ultrapassa quem está abaixo do piso',
   'negativo', 'alta', 'aprovado', 'api', 'RN-006, RN-007; CA-005, CA-010; CDC arts. 36-38 (publicidade)',
   'Um especialista com destaque ativo mas nota abaixo do piso fica atrás do bem avaliado e não recebe o rótulo Patrocinado.',
   'Config piso_nota vigente.',
   '[{"ordem":1,"acao":"Dois especialistas na mesma categoria/UF: A com três notas 2 e destaque topo; B com três notas 5","resultado_esperado":"recalcular marca A abaixo do piso"},
     {"ordem":2,"acao":"Buscar pela categoria","resultado_esperado":"B vem antes de A; A sem patrocinado; A.abaixo_piso = true"}]'::jsonb,
   'Orgânico é meritocrático; pago é aditivo e nunca contorna o piso.', NULL),
  (v_mod, 'MKY-005', 'Vagas de demanda: célula abaixo do piso mínimo não aparece no agregado público',
   'negativo', 'alta', 'aprovado', 'api', 'LGPD (minimização/anonimização); RN-034; CA-021',
   'O agregado público só mostra uma célula categoria×UF quando pelo menos N empresas distintas buscaram sem oferta.',
   'Config demanda_latente.piso_celula = 5.',
   '[{"ordem":1,"acao":"Registrar 4 empresas distintas sem oferta para a mesma categoria/UF sintética","resultado_esperado":"a célula não aparece"},
     {"ordem":2,"acao":"Registrar a 5ª empresa","resultado_esperado":"a célula aparece com empresas = 5"}]'::jsonb,
   'Nenhuma contagem pequena que reidentifique uma empresa.', NULL),
  (v_mod, 'MKY-006', 'Contato mascarado nas mensagens até a empresa liberar; contato direto só sai pela função depois da liberação',
   'feliz', 'alta', 'aprovado', 'api', 'RN-020; LGPD (finalidade)',
   'Telefones, e-mails e links são ocultados nas mensagens enquanto o contato não for liberado; depois passam limpos e a função de contato devolve o e-mail.',
   'Lead aberto entre empresa e especialista.',
   '[{"ordem":1,"acao":"Empresa escreve mensagem com telefone e e-mail","resultado_esperado":"texto gravado com os trechos ocultos e sinal de saída marcado"},
     {"ordem":2,"acao":"Especialista pede o contato","resultado_esperado":"liberado = false"},
     {"ordem":3,"acao":"Empresa libera o contato e escreve de novo","resultado_esperado":"mensagem sem máscara; contato devolve o e-mail"}]'::jsonb,
   'Mascaramento proporcional: até o primeiro contato qualificado, sem penalização.', NULL),
  (v_mod, 'MKY-007', 'Léxico não-disciplinar no schema: nada se chama infração, punição, sanção ou demoção',
   'negativo', 'media', 'aprovado', 'api', 'CLT arts. 2º-3º (subordinação); RN-028; CA-018',
   'Auditoria de catálogo: tabelas, colunas, funções e valores de check do módulo não usam vocabulário disciplinar.',
   NULL,
   '[{"ordem":1,"acao":"Varrer information_schema e pg_proc pelos prefixos marketplace_ e marketye_","resultado_esperado":"nenhum nome com infrac, punic, sanc, democ ou penal"}]'::jsonb,
   'Ocorrência, reflexo na visibilidade e ajuste de nível são os únicos termos.', 'Somente leitura.'),
  (v_mod, 'MKY-008', 'Contestação por canal único: só uma pessoa (superadmin) decide, com trilha de evidência',
   'feliz', 'critica', 'aprovado', 'api', 'Marco Civil art. 19 (STF, Temas 987/533 — devido processo); LGPD art. 20; RN-032, RN-033; CA-020',
   'Cadastro rejeitado pode ser contestado; usuário comum não decide; superadmin defere e o cadastro volta a pendente com a trilha registrada.',
   NULL,
   '[{"ordem":1,"acao":"Superadmin rejeita o cadastro com motivo","resultado_esperado":"status bloqueado, moderacao_resultado rejeitado"},
     {"ordem":2,"acao":"Especialista contesta","resultado_esperado":"contestação aberta com trilha"},
     {"ordem":3,"acao":"Usuário de empresa tenta decidir","resultado_esperado":"acesso negado"},
     {"ordem":4,"acao":"Superadmin defere com resposta","resultado_esperado":"status pendente; trilha com dois eventos; resposta gravada"}]'::jsonb,
   'Human-in-the-loop obrigatório; a IA nunca fecha contestação.', NULL),
  (v_mod, 'MKY-009', 'Exclusão LGPD: perfil sai da vitrine e é anonimizado; leads e avaliações ficam pelo prazo legal',
   'feliz', 'alta', 'aprovado', 'api', 'LGPD arts. 16 e 18; RN-019; CA-014',
   'O titular exclui o próprio perfil: nome, e-mail, documento e foto anonimizados, anúncios removidos, transações retidas.',
   'Especialista com lead ganho e avaliação.',
   '[{"ordem":1,"acao":"Especialista chama a exclusão com a confirmação","resultado_esperado":"status bloqueado, excluido_em preenchido, PII anonimizada"},
     {"ordem":2,"acao":"Buscar pelo nome antigo","resultado_esperado":"nada encontrado"},
     {"ordem":3,"acao":"Conferir lead e avaliação","resultado_esperado":"continuam existindo, ligados ao id"}]'::jsonb,
   'Direito de exclusão atendido sem apagar a trilha transacional.', NULL),
  (v_mod, 'MKY-010', 'Ajuste de nível só depois de aviso e período de recuperação, e nunca bloqueia publicar',
   'alternativo', 'alta', 'aprovado', 'api', 'RN-010, RN-029; CA-009, CA-019; subordinação algorítmica (STF Temas 1291/1389 pendentes)',
   'Quem está em nível superior às métricas recebe aviso; só após o amortecedor o nível é ajustado; publicar continua permitido.',
   'Config niveis.amortecedor_dias = 14.',
   '[{"ordem":1,"acao":"Especialista prata sem métricas; recalcular","resultado_esperado":"continua prata, com aviso registrado"},
     {"ordem":2,"acao":"Envelhecer o aviso além do amortecedor; recalcular","resultado_esperado":"nível ajustado para novo"},
     {"ordem":3,"acao":"Publicar um anúncio","resultado_esperado":"publicado normalmente"}]'::jsonb,
   'Ajuste de nível é reflexo reputacional, não sanção.', NULL),
  (v_mod, 'MKY-011', 'Trilha de autonomia: definir e alterar preço gera eventos auditáveis',
   'feliz', 'media', 'aprovado', 'api', 'CLT arts. 2º-3º; RN-003, RN-031; CA-022',
   'Toda definição de preço/política do prestador fica registrada como evento com valor anterior e novo.',
   NULL,
   '[{"ordem":1,"acao":"Salvar anúncio com preço 300","resultado_esperado":"1 evento anuncio_preco_politica"},
     {"ordem":2,"acao":"Alterar para 350","resultado_esperado":"2º evento com anterior 300 e novo 350"}]'::jsonb,
   'Prova de que o preço é do prestador.', NULL),
  (v_mod, 'MKY-012', 'Leitura direta da tabela não expõe e-mail, telefone, CPF/CNPJ nem quem avaliou; admin de empresa não gerencia especialistas',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD (minimização); RN-020; incidente prévio de exposição (25)',
   'Auditoria de privilégios: o papel authenticated não tem SELECT nas colunas de contato do especialista nem no avaliador_id; a política antiga de admin por empresa não existe mais.',
   NULL,
   '[{"ordem":1,"acao":"Conferir column_privileges de authenticated em marketplace_profissionais e marketplace_avaliacoes","resultado_esperado":"sem email, telefone, cpf_cnpj, user_id, tenant_id, avaliador_id"},
     {"ordem":2,"acao":"Conferir pg_policies","resultado_esperado":"política Admins manage all professionals ausente; superadmin presente"}]'::jsonb,
   'Contato só pelo lead liberado; moderação só da casa.', 'Somente leitura.'),
  (v_mod, 'MKY-013', 'Guarda RN-021: status/selo não mudam por UPDATE direto de usuário autenticado; mudam pela função de moderação',
   'negativo', 'critica', 'aprovado', 'api', 'RN-021; CA-013; classe de vulnerabilidade da assinatura por anônimo',
   'Um UPDATE direto de status pelo próprio especialista é recusado; a função de moderação (superadmin) muda.',
   NULL,
   '[{"ordem":1,"acao":"Como o especialista (papel authenticated), UPDATE status = ativo","resultado_esperado":"recusado pela guarda"},
     {"ordem":2,"acao":"Superadmin aprova pela função","resultado_esperado":"status ativo, selo verificado"}]'::jsonb,
   'Escrita sensível só por função.', NULL),
  (v_mod, 'MKY-020', 'Cabeçalho: botão MarketYE abre a vitrine do marketplace de serviços', 'feliz', 'alta', 'aprovado', 'e2e', 'RN-002; 0.5 (nomenclatura)',
   'O botão global do cabeçalho passa a se chamar MarketYE e abre a vitrine com o título MarketYE e os filtros.',
   'Conta-robô logada no ambiente de teste.',
   '[{"ordem":1,"acao":"Entrar e localizar o botão MarketYE no cabeçalho","resultado_esperado":"botão existe com o texto MarketYE"},
     {"ordem":2,"acao":"Abrir /marketplace","resultado_esperado":"título MarketYE, campo de busca e filtros visíveis"}]'::jsonb,
   'Nada mais se chama Rede de Parceiros.', 'Cypress: cypress/e2e/marketye.cy.ts'),
  (v_mod, 'MKY-021', 'Vitrine: filtrar por categoria lista anúncios; busca sem oferta oferece alternativas em vez de vazio', 'feliz', 'alta', 'aprovado', 'e2e', 'RN-023; CA-004',
   'Com a categoria Segurança do Trabalho a vitrine lista o anúncio do especialista de teste; um termo inexistente mostra o aviso de oferta insuficiente com o botão de aviso.',
   'Fixture "Especialista Staging (QA)" com anúncio publicado (ilha de teste).',
   '[{"ordem":1,"acao":"Selecionar a categoria Segurança do Trabalho","resultado_esperado":"ao menos um card de anúncio"},
     {"ordem":2,"acao":"Buscar um termo sem oferta","resultado_esperado":"aviso de oferta insuficiente e opção Avise-me"}]'::jsonb,
   'Busca nunca devolve vazio seco.', 'Cypress: cypress/e2e/marketye.cy.ts'),
  (v_mod, 'MKY-022', 'Página pública MarketYE: proposta ao especialista, vagas de demanda e caminho para o cadastro', 'feliz', 'media', 'aprovado', 'e2e', 'RN-001; 6.3',
   'A página /marketye abre sem login, mostra a proposta de valor e leva ao formulário de cadastro.',
   NULL,
   '[{"ordem":1,"acao":"Abrir /marketye sem sessão","resultado_esperado":"título com MarketYE e botão de cadastro"},
     {"ordem":2,"acao":"Clicar em cadastrar","resultado_esperado":"formulário /marketye/cadastro com campos de nome, e-mail e CPF/CNPJ"}]'::jsonb,
   'Captação pública do lado da oferta.', 'Cypress: cypress/e2e/marketye.cy.ts')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  -- Casos antigos que descreviam o comportamento anterior.
  UPDATE public.qa_casos_teste SET
    titulo = 'Cadastrar-se como especialista (com documentos e selfie): nasce pendente até a verificação',
    resultado_esperado = 'Cadastro salvo como pendente, sem selo; aparece na fila de moderação do MarketYE.'
  WHERE codigo = 'PARC-001';
  UPDATE public.qa_casos_teste SET titulo = 'Perfil pendente não aparece no MarketYE antes da verificação' WHERE codigo = 'PARC-002';
  UPDATE public.qa_casos_teste SET
    titulo = 'Moderação: superadmin rejeita o cadastro com motivo (contestável pelo canal único)',
    resultado_esperado = 'Status bloqueado com moderacao_resultado = rejeitado e motivo gravado; o especialista pode contestar.'
  WHERE codigo = 'PARC-004';
  UPDATE public.qa_casos_teste SET
    titulo = 'Não permite avaliar sem transação verificada (contratação concluída ou lead ganho)',
    resultado_esperado = 'A função marketye_avaliar recusa; não existe mais inserção direta de avaliação.'
  WHERE codigo = 'PARC-024';
END $qa$;

-- ---------------------------------------------------------------------
-- 2) Apoio das rotinas: fixtures sintéticas (apagadas no fim; a bateria
--    ainda descarta a transação inteira)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_claims(p_uid uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- Cria conta + perfil de empresa (para get_user_tenant_id) num tenant.
CREATE OR REPLACE FUNCTION public.qa_mky_usuario_empresa(p_tenant uuid, p_marca text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, p_tenant, 'QA Empresa ' || p_marca, true);
  RETURN v_uid;
END $$;

CREATE OR REPLACE FUNCTION public.qa_mky_superadmin()
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.superadmins (user_id, email, nome, ativo) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid', 'QA Superadmin MKY', true);
  RETURN v_uid;
END $$;

-- Especialista fictício cadastrado pela função (pendente). CPF da faixa da casa.
CREATE OR REPLACE FUNCTION public.qa_mky_especialista(p_marca text, p_cpf text)
RETURNS TABLE (uid uuid, prof_id uuid) LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid(); v_res jsonb;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista ' || p_marca, 'email', 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', p_cpf, 'cidade', 'Cidade QA', 'estado', 'QA', 'modalidades', '["presencial","online"]'::jsonb, 'aceite_termos', true,
    'conselho', 'CREA', 'registro_profissional', 'QA-' || p_marca, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  RETURN QUERY SELECT v_uid, (v_res->>'id')::uuid;
END $$;

CREATE OR REPLACE FUNCTION public.qa_mky_limpar()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Dependentes sem ON DELETE CASCADE primeiro (auditoria e avaliações), depois o especialista (o resto cascateia).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_leads WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.marketplace_demanda_latente WHERE uf = 'QA';
  DELETE FROM public.marketplace_categorias WHERE slug LIKE 'qa-mky-%';
  DELETE FROM public.superadmins WHERE email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.profiles WHERE nome_completo LIKE 'QA Empresa %' AND user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.tenants WHERE slug LIKE 'qa-mky-%';
  DELETE FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid';
END $$;

-- ---------------------------------------------------------------------
-- 3) Rotinas
-- ---------------------------------------------------------------------
-- MKY-001 — cadastro nasce pendente; documento único; guarda no INSERT direto
CREATE OR REPLACE FUNCTION public.qa_caso_mky_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_status text; v_selo boolean; v_cons int; v_rep int; v_uid2 uuid := gen_random_uuid(); v_id2 uuid; v_claims text; v_dup text := 'ok';
        v_cercado uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar pela função com aceite'; r.esperado := 'pendente, sem selo, 3 consentimentos, reputação criada';
  SELECT * INTO e FROM public.qa_mky_especialista('001', '900.000.001-75');
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = e.prof_id;
  SELECT count(*) INTO v_rep FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_status <> 'pendente' OR v_selo OR v_cons <> 3 OR v_rep <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('ACHADO: status %s, selo %s, consentimentos %s, reputação %s', v_status, v_selo, v_cons, v_rep); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Repetir com o mesmo CPF em outra conta'; r.esperado := 'recusado';
  INSERT INTO auth.users (id, email) VALUES (v_uid2, 'qa-mky-dup-' || left(v_uid2::text, 8) || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid2, jsonb_build_object('nome_completo', 'QA Especialista Dup', 'email', 'qa-mky-dup@sandbox.invalid', 'cpf_cnpj', '90000000175', 'aceite_termos', true));
    v_dup := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM; END;
  IF v_dup NOT LIKE '%já possui cadastro%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: CPF repetido não foi recusado (' || v_dup || ')'; PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'INSERT direto como usuário autenticado com status ativo e selo'; r.esperado := 'guarda rebaixa para pendente/sem selo';
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM public.qa_mky_claims(v_uid2);
  -- A trava do cercado (qa_guarda_cercado) lê public.tenants com o papel de
  -- quem escreve; como 'authenticated' ela não enxerga o cercado (RLS) e
  -- bloquearia este INSERT mesmo com tenant_id do cercado. O modo de teste
  -- fica desligado só neste statement: a linha é do cercado e a bateria
  -- descarta a transação inteira de qualquer jeito.
  PERFORM set_config('app.qa_modo', 'off', true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.marketplace_profissionais (user_id, tenant_id, nome_completo, email, status, selo_verificado, nota_media)
    VALUES (v_uid2, v_cercado, 'QA Especialista Direto', 'qa-mky-direto-' || left(v_uid2::text, 8) || '@sandbox.invalid', 'ativo', true, 5) RETURNING id INTO v_id2;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); RAISE;
  END;
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = v_id2;
  IF v_status = 'pendente' AND NOT v_selo THEN
    r.situacao := 'passou'; r.obtido := 'Função e INSERT direto nascem pendentes e sem selo; CPF repetido recusado; consentimentos registrados.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: INSERT direto ficou %s / selo %s — a guarda não agiu.', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-002 — vitrine global: pendente não aparece; aprovado aparece para duas empresas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t1 uuid := public.qa_sandbox_tenant_id(); v_t2 uuid; v_u1 uuid; v_u2 uuid; v_claims text; v_an uuid; v_cat uuid;
        v_n1 int; v_n2 int; v_pub text := 'ok'; v_res jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  IF v_t1 IS NULL THEN r.situacao := 'erro'; r.obtido := 'Cercado qa-sandbox não existe'; RETURN r; END IF;
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO v_t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF v_t2 IS NULL THEN r.situacao := 'erro'; r.obtido := 'Segundo cercado (qa-sandbox-2) não existe'; RETURN r; END IF;
  v_u1 := public.qa_mky_usuario_empresa(v_t1, '002a'); v_u2 := public.qa_mky_usuario_empresa(v_t2, '002b'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('002', '900.000.002-56');
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  r.passo_ordem := 1; r.passo_acao := 'Anúncio salvo (rascunho) com o cadastro pendente'; r.esperado := 'busca não encontra';
  PERFORM public.qa_mky_claims(e.uid);
  v_res := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Laudo MKY-002 exclusivo', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  v_an := (v_res->>'id')::uuid;
  PERFORM public.qa_mky_claims(v_u1);
  v_n1 := (public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true))->>'total')::int;
  IF v_n1 <> 0 THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: anúncio de cadastro pendente apareceu na busca'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Publicar antes da aprovação'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims(e.uid);
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_pub := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_pub := SQLERRM; END;
  IF v_pub NOT LIKE '%verificação%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: publicou sem aprovação (' || v_pub || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Superadmin aprova; especialista publica; duas empresas buscam'; r.esperado := 'as duas encontram';
  PERFORM public.qa_mky_claims(v_sa);
  PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_anuncio_publicar(v_an);
  PERFORM public.qa_mky_claims(v_u1);
  v_n1 := (public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true))->>'total')::int;
  PERFORM public.qa_mky_claims(v_u2);
  v_res := public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true));
  v_n2 := (v_res->>'total')::int;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_n1 >= 1 AND v_n2 >= 1 AND (v_res->'resultados'->0->'profissional'->>'selo_verificado')::boolean THEN
    r.situacao := 'passou'; r.obtido := format('Pendente invisível; depois da aprovação, empresas distintas encontram o mesmo anúncio (%s/%s), com selo.', v_n1, v_n2);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: após aprovação, empresa 1 viu %s e empresa 2 viu %s.', v_n1, v_n2);
  END IF;
  r.detalhe := jsonb_build_object('primeiro', v_res->'resultados'->0->'fatores');
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-003 — avaliação só com lead ganho; bidirecional; recálculo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; v_msg text := 'ok';
        v_nota numeric; v_tot int; v_dup text := 'ok'; v_rev jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '003'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('003', '900.000.003-37');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-003', 'descricao', 'Serviço fictício de teste do MarketYE para avaliação verificada.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);

  r.passo_ordem := 1; r.passo_acao := 'Empresa abre lead e tenta avaliar'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Preciso de um orçamento para o serviço de teste.')->>'id')::uuid;
  BEGIN PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":5,"clareza":5,"aderencia_escopo":5,"profissionalismo":5}'::jsonb, NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT LIKE '%após o atendimento%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: avaliou sem transação (' || v_msg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Especialista responde; empresa marca ganho e avalia'; r.esperado := 'aceita e recalcula';
  PERFORM public.qa_mky_claims(e.uid); PERFORM public.marketye_lead_mensagem(v_lead, 'Posso atender na próxima semana.');
  PERFORM public.qa_mky_claims(v_u); PERFORM public.marketye_lead_status(v_lead, 'ganho');
  v_rev := public.marketye_avaliar('lead', v_lead, '{"pontualidade":4,"clareza":5,"aderencia_escopo":4,"profissionalismo":5}'::jsonb, 'Ótimo atendimento de teste.');
  SELECT nota_media, total_avaliacoes INTO v_nota, v_tot FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_tot <> 1 OR v_nota <> 4.5 THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: reputação não recalculou (nota %s, total %s)', v_nota, v_tot); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Empresa avalia de novo'; r.esperado := 'recusado';
  BEGIN PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":1}'::jsonb, NULL); v_dup := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM; END;
  IF v_dup NOT LIKE '%já foi avaliado%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: segunda avaliação passou (' || v_dup || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 4; r.passo_acao := 'Especialista avalia a empresa'; r.esperado := 'direção especialista_para_cliente';
  PERFORM public.qa_mky_claims(e.uid);
  v_rev := public.marketye_avaliar('lead', v_lead, '{"clareza_demanda":5,"pagamento_combinado":5}'::jsonb, NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_rev->>'direcao' = 'especialista_para_cliente' THEN
    r.situacao := 'passou'; r.obtido := 'Sem transação: recusa. Com lead ganho: cliente avalia uma vez (nota 4,5 recalculada) e o especialista avalia a empresa.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: avaliação reversa não gravou a direção correta.';
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-004 — piso de nota e destaque
CREATE OR REPLACE FUNCTION public.qa_caso_mky_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; ea record; eb record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_cat uuid; v_an_a uuid; v_an_b uuid;
        v_res jsonb; v_pos_a int; v_pos_b int; v_patro_a boolean; v_abaixo boolean; i int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '004'); v_sa := public.qa_mky_superadmin();
  INSERT INTO public.marketplace_categorias (nome, slug, ativo, ordem) VALUES ('QA Categoria MKY-004', 'qa-mky-004', true, 999) RETURNING id INTO v_cat;
  SELECT * INTO ea FROM public.qa_mky_especialista('004A', '900.000.004-18');
  SELECT * INTO eb FROM public.qa_mky_especialista('004B', '900.000.005-07');
  PERFORM public.qa_mky_claims(v_sa);
  PERFORM public.marketye_moderar_especialista(ea.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(eb.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(ea.uid);
  v_an_a := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anúncio A MKY-004', 'descricao', 'Anúncio fictício A da rotina de piso de nota do MarketYE.', 'categoria_id', v_cat, 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an_a);
  PERFORM public.qa_mky_claims(eb.uid);
  v_an_b := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anúncio B MKY-004', 'descricao', 'Anúncio fictício B da rotina de piso de nota do MarketYE.', 'categoria_id', v_cat, 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an_b);

  r.passo_ordem := 1; r.passo_acao := 'A: três notas 2 + destaque topo; B: três notas 5'; r.esperado := 'A abaixo do piso';
  FOR i IN 1..3 LOOP
    INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, direcao, nota_geral, criterios) VALUES (ea.prof_id, v_t, 'cliente_para_especialista', 2, '{}'::jsonb);
    INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, direcao, nota_geral, criterios) VALUES (eb.prof_id, v_t, 'cliente_para_especialista', 5, '{}'::jsonb);
  END LOOP;
  PERFORM public.marketye_recalcular_reputacao(ea.prof_id); PERFORM public.marketye_recalcular_reputacao(eb.prof_id);
  INSERT INTO public.marketplace_destaques (profissional_id, tipo, inicio, fim, ativo) VALUES (ea.prof_id, 'topo', CURRENT_DATE, CURRENT_DATE + 7, true);
  SELECT abaixo_piso INTO v_abaixo FROM public.marketplace_reputacao WHERE profissional_id = ea.prof_id;
  IF NOT COALESCE(v_abaixo, false) THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: nota 2 com 3 avaliações não marcou abaixo do piso'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Buscar pela categoria'; r.esperado := 'B antes de A; A sem patrocinado';
  PERFORM public.qa_mky_claims(v_u);
  v_res := public.marketye_buscar(jsonb_build_object('categoria_id', v_cat, 'ignorar_uf_padrao', true));
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT o - 1 INTO v_pos_a FROM jsonb_array_elements(v_res->'resultados') WITH ORDINALITY AS x(v, o) WHERE (x.v->>'servico_id')::uuid = v_an_a;
  SELECT o - 1 INTO v_pos_b FROM jsonb_array_elements(v_res->'resultados') WITH ORDINALITY AS x(v, o) WHERE (x.v->>'servico_id')::uuid = v_an_b;
  SELECT (x.v->>'patrocinado')::boolean INTO v_patro_a FROM jsonb_array_elements(v_res->'resultados') AS x(v) WHERE (x.v->>'servico_id')::uuid = v_an_a;
  IF v_pos_b < v_pos_a AND NOT v_patro_a THEN
    r.situacao := 'passou'; r.obtido := format('B (nota 5) na posição %s, A (nota 2, destaque) na %s e sem rótulo Patrocinado.', v_pos_b, v_pos_a);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: posições B=%s A=%s, patrocinado A=%s', v_pos_b, v_pos_a, v_patro_a);
  END IF;
  r.detalhe := jsonb_build_object('total', v_res->'total');
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-005 — célula mínima das vagas de demanda
CREATE OR REPLACE FUNCTION public.qa_caso_mky_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_cat uuid; v_t uuid; i int; v_n4 int; v_n5 int; v_piso int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_piso := COALESCE((public.marketye_config('demanda_latente')->>'piso_celula')::int, 5);
  INSERT INTO public.marketplace_categorias (nome, slug, ativo, ordem) VALUES ('QA Categoria MKY-005', 'qa-mky-005', true, 999) RETURNING id INTO v_cat;
  r.passo_ordem := 1; r.passo_acao := format('%s empresas distintas sem oferta na mesma célula', v_piso - 1); r.esperado := 'célula ausente';
  FOR i IN 1..(v_piso - 1) LOOP
    INSERT INTO public.tenants (nome, slug) VALUES ('QA Empresa ' || i || ' (MKY-005)', 'qa-mky-005-' || i) RETURNING id INTO v_t;
    INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, resultados) VALUES (v_t, v_cat, 'QA', 0);
  END LOOP;
  SELECT count(*) INTO v_n4 FROM jsonb_array_elements(public.marketye_vagas_demanda(30)) x WHERE x->>'categoria_slug' = 'qa-mky-005';
  r.passo_ordem := 2; r.passo_acao := 'Mais uma empresa'; r.esperado := format('célula com empresas = %s', v_piso);
  INSERT INTO public.tenants (nome, slug) VALUES ('QA Empresa extra (MKY-005)', 'qa-mky-005-x') RETURNING id INTO v_t;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, resultados) VALUES (v_t, v_cat, 'QA', 0);
  SELECT (x->>'empresas')::int INTO v_n5 FROM jsonb_array_elements(public.marketye_vagas_demanda(30)) x WHERE x->>'categoria_slug' = 'qa-mky-005';
  IF v_n4 = 0 AND v_n5 = v_piso THEN
    r.situacao := 'passou'; r.obtido := format('Com %s empresas a célula fica oculta; com %s aparece.', v_piso - 1, v_piso);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: com %s empresas apareceu %s célula(s); com %s, empresas = %s', v_piso - 1, v_n4, v_piso, v_n5);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-006 — mascaramento de contato
CREATE OR REPLACE FUNCTION public.qa_caso_mky_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; v_txt text; v_sinal boolean; v_c jsonb; v_txt2 text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '006'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('006', '900.000.006-80');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-006', 'descricao', 'Serviço fictício de teste do MarketYE para mascaramento de contato.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);

  r.passo_ordem := 1; r.passo_acao := 'Mensagem com telefone e e-mail'; r.esperado := 'trechos ocultos e sinal de saída';
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Me chama no (46) 99999-1234 ou contato@exemplo.test para combinar.')->>'id')::uuid;
  SELECT texto, sinal_saida INTO v_txt, v_sinal FROM public.marketplace_lead_mensagens WHERE lead_id = v_lead AND autor_tipo = 'cliente' ORDER BY created_at LIMIT 1;
  IF v_txt LIKE '%99999%' OR v_txt LIKE '%exemplo.test%' OR NOT v_sinal THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: contato não foi mascarado: ' || v_txt; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Especialista pede o contato'; r.esperado := 'liberado = false';
  PERFORM public.qa_mky_claims(e.uid);
  v_c := public.marketye_lead_contato(v_lead);
  IF (v_c->>'liberado')::boolean THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: contato saiu antes da liberação'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Empresa libera e escreve de novo'; r.esperado := 'sem máscara; contato devolve e-mail';
  PERFORM public.qa_mky_claims(v_u);
  PERFORM public.marketye_lead_liberar_contato(v_lead);
  PERFORM public.marketye_lead_mensagem(v_lead, 'Agora pode falar no (46) 99999-1234.');
  SELECT texto INTO v_txt2 FROM public.marketplace_lead_mensagens WHERE lead_id = v_lead AND autor_tipo = 'cliente' AND texto LIKE 'Agora pode falar%' LIMIT 1;
  PERFORM public.qa_mky_claims(e.uid);
  v_c := public.marketye_lead_contato(v_lead);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_txt2 LIKE '%99999-1234%' AND (v_c->>'liberado')::boolean AND v_c->>'email' LIKE 'qa-mky-006%' THEN
    r.situacao := 'passou'; r.obtido := 'Mascarado até a liberação; depois, texto limpo e contato disponível pela função.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: após liberação texto=%s liberado=%s email=%s', v_txt2, v_c->>'liberado', v_c->>'email');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-007 — léxico não-disciplinar (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_achados text[];
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Varrer nomes de tabelas, colunas e funções do módulo'; r.esperado := 'nenhum termo disciplinar';
  SELECT COALESCE(array_agg(DISTINCT nome), '{}') INTO v_achados FROM (
    SELECT table_name || '.' || column_name AS nome FROM information_schema.columns WHERE table_schema = 'public' AND (table_name LIKE 'marketplace\_%' OR table_name LIKE 'marketye\_%')
    UNION ALL SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND (table_name LIKE 'marketplace\_%' OR table_name LIKE 'marketye\_%')
    UNION ALL SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'marketye\_%'
  ) x WHERE nome ~* '(infrac|punic|sanc|democ|penal|castig)';
  IF COALESCE(array_length(v_achados, 1), 0) = 0 THEN
    r.situacao := 'passou'; r.obtido := 'Nenhum nome disciplinar no schema do MarketYE.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(v_achados, ', ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-008 — contestação com decisão humana
CREATE OR REPLACE FUNCTION public.qa_caso_mky_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_status text; v_mod text; v_ct uuid; v_neg text := 'ok'; v_trilha int; v_resp text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '008'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('008', '900.000.007-60');
  r.passo_ordem := 1; r.passo_acao := 'Superadmin rejeita com motivo'; r.esperado := 'bloqueado / rejeitado';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'rejeitado', 'Documento ilegível (teste).', false);
  SELECT status::text, moderacao_resultado INTO v_status, v_mod FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_status <> 'bloqueado' OR v_mod <> 'rejeitado' THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: rejeição deixou %s/%s', v_status, v_mod); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 2; r.passo_acao := 'Especialista contesta'; r.esperado := 'aberta';
  PERFORM public.qa_mky_claims(e.uid);
  v_ct := (public.marketye_contestar('rejeicao_cadastro', e.prof_id, 'O documento enviado é legível; anexo nova cópia.')->>'id')::uuid;
  r.passo_ordem := 3; r.passo_acao := 'Usuário de empresa tenta decidir'; r.esperado := 'acesso negado';
  PERFORM public.qa_mky_claims(v_u);
  BEGIN PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Tentativa indevida de decisão.'); v_neg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_neg := SQLERRM; END;
  IF v_neg NOT LIKE '%Acesso negado%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: usuário comum decidiu contestação (' || v_neg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 4; r.passo_acao := 'Superadmin defere'; r.esperado := 'pendente; trilha com 2 eventos';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Nova cópia conferida; cadastro volta à fila.');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text INTO v_status FROM public.marketplace_profissionais WHERE id = e.prof_id;
  SELECT jsonb_array_length(trilha), resposta INTO v_trilha, v_resp FROM public.marketplace_contestacoes WHERE id = v_ct;
  IF v_status = 'pendente' AND v_trilha = 2 AND v_resp IS NOT NULL THEN
    r.situacao := 'passou'; r.obtido := 'Rejeição contestada; só o superadmin decidiu; cadastro voltou a pendente com trilha de 2 eventos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: status %s, trilha %s eventos, resposta %s', v_status, v_trilha, v_resp);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-009 — exclusão LGPD
CREATE OR REPLACE FUNCTION public.qa_caso_mky_009()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; p record; v_n int; v_leads int; v_avals int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '009'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('009', '900.000.008-41');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-009 exclusivo', 'descricao', 'Serviço fictício de teste do MarketYE para exclusão LGPD.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Quero contratar o serviço de teste.')->>'id')::uuid;
  PERFORM public.marketye_lead_status(v_lead, 'ganho');
  PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":5}'::jsonb, NULL);

  r.passo_ordem := 1; r.passo_acao := 'Especialista exclui o perfil'; r.esperado := 'anonimizado e fora da vitrine';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = e.prof_id;
  PERFORM public.qa_mky_claims(v_u);
  v_n := (public.marketye_buscar(jsonb_build_object('q', 'QA Serviço MKY-009', 'ignorar_uf_padrao', true))->>'total')::int;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT count(*) INTO v_leads FROM public.marketplace_leads WHERE profissional_id = e.prof_id;
  SELECT count(*) INTO v_avals FROM public.marketplace_avaliacoes WHERE profissional_id = e.prof_id;
  IF p.excluido_em IS NOT NULL AND p.status::text = 'bloqueado' AND p.cpf_cnpj IS NULL AND p.nome_completo = 'Especialista removido' AND p.email LIKE 'removido+%' AND v_n = 0 AND v_leads = 1 AND v_avals = 1 THEN
    r.situacao := 'passou'; r.obtido := 'Perfil anonimizado e fora da busca; lead e avaliação retidos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: excluido_em %s, status %s, cpf %s, nome %s, busca %s, leads %s, avaliações %s', p.excluido_em, p.status, p.cpf_cnpj, p.nome_completo, v_n, v_leads, v_avals);
  END IF;
  -- A linha anonimizada não tem mais o marcador de e-mail: apaga pelo id (dependentes antes).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_leads WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_profissionais WHERE id = e.prof_id;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-010 — ajuste de nível com aviso e amortecedor; publicar continua livre
CREATE OR REPLACE FUNCTION public.qa_caso_mky_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_claims text; v_nivel text; v_aviso timestamptz; v_an uuid; v_st text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('010', '900.000.009-22');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  UPDATE public.marketplace_reputacao SET nivel = 'prata', nivel_aviso_em = NULL WHERE profissional_id = e.prof_id;

  r.passo_ordem := 1; r.passo_acao := 'Prata sem métricas; recalcular'; r.esperado := 'continua prata, com aviso';
  PERFORM public.marketye_recalcular_reputacao(e.prof_id);
  SELECT nivel, nivel_aviso_em INTO v_nivel, v_aviso FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_nivel <> 'prata' OR v_aviso IS NULL THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: ajustou sem aviso (nível %s, aviso %s)', v_nivel, v_aviso); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Aviso mais velho que o amortecedor; recalcular'; r.esperado := 'nível novo';
  UPDATE public.marketplace_reputacao SET nivel_aviso_em = now() - interval '40 days' WHERE profissional_id = e.prof_id;
  PERFORM public.marketye_recalcular_reputacao(e.prof_id);
  SELECT nivel INTO v_nivel FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_nivel <> 'novo' THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: após o amortecedor o nível ficou %s', v_nivel); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Publicar anúncio depois do ajuste'; r.esperado := 'publicado';
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-010', 'descricao', 'Serviço fictício de teste do MarketYE após ajuste de nível.', 'modalidade', 'online'))->>'id')::uuid;
  v_st := public.marketye_anuncio_publicar(v_an)->>'status';
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_st = 'publicado' THEN
    r.situacao := 'passou'; r.obtido := 'Aviso antes do ajuste; ajuste só após o amortecedor; publicar continuou permitido.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ajuste de nível impediu publicar (' || COALESCE(v_st, 'nulo') || ')';
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-011 — trilha de autonomia
CREATE OR REPLACE FUNCTION public.qa_caso_mky_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_claims text; v_an uuid; v_n1 int; v_n2 int; ev record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT * INTO e FROM public.qa_mky_especialista('011', '900.000.010-66');
  PERFORM public.qa_mky_claims(e.uid);
  r.passo_ordem := 1; r.passo_acao := 'Salvar anúncio com preço 300'; r.esperado := '1 evento';
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-011', 'descricao', 'Serviço fictício de teste do MarketYE para a trilha de autonomia.', 'modalidade', 'online', 'tipo_preco', 'visita', 'preco_referencia', 300))->>'id')::uuid;
  SELECT count(*) INTO v_n1 FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an;
  r.passo_ordem := 2; r.passo_acao := 'Alterar para 350'; r.esperado := '2º evento com anterior/novo';
  PERFORM public.marketye_anuncio_salvar(jsonb_build_object('id', v_an, 'nome', 'QA Serviço MKY-011', 'descricao', 'Serviço fictício de teste do MarketYE para a trilha de autonomia.', 'modalidade', 'online', 'tipo_preco', 'visita', 'preco_referencia', 350));
  SELECT count(*) INTO v_n2 FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an;
  SELECT * INTO ev FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an AND anterior IS NOT NULL LIMIT 1;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_n1 = 1 AND v_n2 = 2 AND (ev.anterior->>'preco_referencia')::numeric = 300 AND (ev.novo->>'preco_referencia')::numeric = 350 THEN
    r.situacao := 'passou'; r.obtido := 'Definição e alteração de preço registradas como eventos com anterior 300 e novo 350.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: eventos %s/%s, último anterior=%s novo=%s', v_n1, v_n2, ev.anterior->>'preco_referencia', ev.novo->>'preco_referencia');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-012 — privilégios de leitura (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_pii text[]; v_aval text[]; v_pol_antiga int; v_pol_sa int;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Conferir colunas legíveis por authenticated'; r.esperado := 'sem PII';
  SELECT COALESCE(array_agg(column_name::text), '{}') INTO v_pii FROM information_schema.column_privileges
   WHERE table_schema = 'public' AND table_name = 'marketplace_profissionais' AND grantee = 'authenticated' AND privilege_type = 'SELECT'
     AND column_name IN ('email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id');
  SELECT COALESCE(array_agg(column_name::text), '{}') INTO v_aval FROM information_schema.column_privileges
   WHERE table_schema = 'public' AND table_name = 'marketplace_avaliacoes' AND grantee = 'authenticated' AND privilege_type = 'SELECT' AND column_name IN ('avaliador_id', 'tenant_id');
  r.passo_ordem := 2; r.passo_acao := 'Conferir políticas'; r.esperado := 'sem admin por empresa; com superadmin';
  SELECT count(*) INTO v_pol_antiga FROM pg_policies WHERE tablename = 'marketplace_profissionais' AND policyname = 'Admins manage all professionals';
  SELECT count(*) INTO v_pol_sa FROM pg_policies WHERE tablename = 'marketplace_profissionais' AND policyname = 'marketplace_profissionais_superadmin';
  IF array_length(v_pii, 1) IS NULL AND array_length(v_aval, 1) IS NULL AND v_pol_antiga = 0 AND v_pol_sa = 1 THEN
    r.situacao := 'passou'; r.obtido := 'authenticated não lê e-mail/telefone/CPF/user_id nem avaliador_id; moderação só de superadmin.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: PII legível %s; avaliação %s; política antiga %s; superadmin %s', v_pii, v_aval, v_pol_antiga, v_pol_sa);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-013 — guarda RN-021
CREATE OR REPLACE FUNCTION public.qa_caso_mky_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_claims text; v_msg text := 'ok'; v_status text; v_selo boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('013', '900.000.011-47');
  r.passo_ordem := 1; r.passo_acao := 'UPDATE direto de status pelo próprio especialista (papel authenticated)'; r.esperado := 'recusado pela guarda';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- ver MKY-001: a trava do cercado não enxerga o cercado como authenticated
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.marketplace_profissionais SET status = 'ativo', selo_verificado = true WHERE id = e.prof_id;
    v_msg := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true);
  IF v_msg NOT LIKE '%só mudam por função%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: UPDATE direto passou (' || v_msg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin aprova pela função'; r.esperado := 'ativo com selo';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_status = 'ativo' AND v_selo THEN
    r.situacao := 'passou'; r.obtido := 'UPDATE direto recusado; a função de moderação ativou com selo.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: função deixou %s / selo %s', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ---------------------------------------------------------------------
-- 4) Registro das rotinas e ponte dos casos e2e
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MKY-001', 'qa_caso_mky_001'), ('MKY-002', 'qa_caso_mky_002'), ('MKY-003', 'qa_caso_mky_003'), ('MKY-004', 'qa_caso_mky_004'),
  ('MKY-005', 'qa_caso_mky_005'), ('MKY-006', 'qa_caso_mky_006'), ('MKY-007', 'qa_caso_mky_007'), ('MKY-008', 'qa_caso_mky_008'),
  ('MKY-009', 'qa_caso_mky_009'), ('MKY-010', 'qa_caso_mky_010'), ('MKY-011', 'qa_caso_mky_011'), ('MKY-012', 'qa_caso_mky_012'),
  ('MKY-013', 'qa_caso_mky_013')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste FROM (VALUES
  ('MKY-020', 'cypress/e2e/marketye.cy.ts', 'MKY-020: Cabeçalho: botão MarketYE abre a vitrine do marketplace de serviços'),
  ('MKY-021', 'cypress/e2e/marketye.cy.ts', 'MKY-021: Vitrine: filtrar por categoria lista anúncios; busca sem oferta oferece alternativas'),
  ('MKY-022', 'cypress/e2e/marketye.cy.ts', 'MKY-022: Página pública MarketYE: proposta ao especialista e caminho para o cadastro')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;
