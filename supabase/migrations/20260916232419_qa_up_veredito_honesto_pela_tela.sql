-- ============================================================================
-- QA Usuários & Permissões — a bateria pela TELA estava mentindo por omissão.
--
-- Achado na corrida real do staging (16/09/2026, 16:39): 38 passou, 3 falhou,
-- 2 erro, 16 sem rotina. Na réplica local a MESMA bateria dá 48 verdes. A
-- diferença não é do produto: é da PORTA por onde a bateria entra.
--
-- Doze casos deste módulo só provam alguma coisa se a rotina calçar os sapatos
-- de um usuário comum (SET LOCAL ROLE authenticated). Sem isso a leitura corre
-- com o papel dono do banco, para quem o isolamento não vale — e o verde sairia
-- sem prova nenhuma. Acontece que o PostgreSQL PROÍBE trocar de papel dentro de
-- uma função com privilégio do dono, e o botão da tela entra exatamente por uma
-- dessas: qa_disparar_bateria precisa do privilégio para conferir o superadmin e
-- para o motor ter direito de escrever. Logo, por aquela porta, esses doze casos
-- NUNCA terão veredito. Pelo SQL Editor, que chama qa_rodar_bateria direto, eles
-- têm.
--
-- Duas coisas estavam erradas nisso, e é o que esta migration corrige:
--
-- 1) LIB-005 e NAC-006 QUEBRAVAM em vez de se declararem sem veredito. As duas
--    tinham um RESET ROLE solto, fora do bloco protegido: o guarda via que não
--    dava para trocar de papel, pulava a troca — e o RESET ROLE seguinte
--    estourava assim mesmo ("cannot set parameter role within security-definer
--    function"), levando junto o tratador de erro, que repetia o mesmo comando.
--    Pior que o erro: se o RESET ROLE não tivesse estourado, as duas teriam
--    feito a escrita indevida com o papel DONO DO BANCO — que a faz passar — e
--    reportado VERMELHO acusando escalada de privilégio que não existe. O erro
--    escondeu um falso vermelho. Agora as duas param antes de escrever, como as
--    outras dez já faziam.
--
-- 2) A mensagem das outras dez dizia "este ambiente não deixa", o que joga a
--    culpa no ambiente e não diz o que fazer. Passa a ser uma só mensagem, em
--    um lugar só, que nomeia a causa (a porta com privilégio do dono) e entrega
--    o comando para obter o veredito completo.
--
-- Não muda nada do produto: só rotinas de QA e o texto que elas devolvem.
-- ============================================================================

-- ─────────────────────────────────────────────────────────
-- A explicação, em um lugar só.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_up_motivo_sem_papel()
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 'SEM VEREDITO POR ESTA PORTA (não é falha do produto). Este caso só prova '
      || 'alguma coisa se a rotina calçar os sapatos de um usuário comum: lida com o papel '
      || 'dono do banco, a leitura ignora o isolamento e o verde não valeria nada. O banco '
      || 'proíbe trocar de papel dentro de uma função com privilégio do dono, e o botão da '
      || 'tela entra por uma delas (qa_disparar_bateria, que precisa do privilégio para '
      || 'conferir o superadmin). Para obter o veredito deste caso, rode a bateria pelo SQL '
      || 'Editor, que chama o motor direto: '
      || 'select public.qa_rodar_bateria(''manual'', ''infraestrutura-auth/usuarios-permissoes'');';
$fn$;

COMMENT ON FUNCTION public.qa_up_motivo_sem_papel() IS
  'QA Usuários & Permissões: por que um caso fica sem veredito quando a bateria roda pela tela, e como obter o veredito.';

-- ─────────────────────────────────────────────────────────
-- Voltar ao papel de origem SEM risco de estourar.
--
-- Era isto que faltava: um RESET ROLE solto estoura quando a bateria roda por
-- dentro de uma função com privilégio do dono — inclusive dentro do tratador de
-- erro, onde derruba a rotina inteira e troca o veredito por uma mensagem crua
-- do PostgreSQL. Voltar o papel é higiene, nunca deve ser o motivo de uma
-- rotina morrer.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_up_voltar_papel()
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  BEGIN
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $fn$;

COMMENT ON FUNCTION public.qa_up_voltar_papel() IS
  'QA Usuários & Permissões: devolve o papel de origem sem nunca derrubar a rotina que chamou.';

-- ─────────────────────────────────────────────────────────
-- LIB-005 — liberação não eleva ninguém acima do teto de quem concede.
--
-- Muda só o começo e o fim: para antes de escrever quando não dá para virar
-- usuário comum, e volta o papel sem risco de estourar no caminho.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_lib_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_admin uuid; v_uid uuid; v_alvo uuid; v_p uuid; v_criou boolean := false; v_motivo text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Admin de empresa SEM a capacidade tenta liberá-la para outro usuário';
  r.esperado    := 'Negado — ninguém concede o que não tem';

  -- Para ANTES de escrever. Com o papel dono do banco a inserção indevida
  -- passaria, e a rotina reportaria escalada de privilégio onde não há.
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  PERFORM public.qa_fixture_limpar('LIB-005');

  v_admin := public.qa_up_usuario('LIB-005', 1, '99900002393', 'ativo');
  v_alvo  := public.qa_up_usuario('LIB-005', 2, '99900002474', 'ativo');
  v_p     := public.qa_up_perfil('LIB-005', 'So Ponto', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_admin, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_admin;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conceder ao alvo uma liberação de módulo que o concedente não possui';
  PERFORM public.qa_up_entrar(v_uid);
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.perfil_excecoes
      (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
    VALUES (v_t, v_alvo, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
            'administrar', 'grupo_economico', true, 'Tentativa de conceder acima do teto — caso LIB-005.');
    v_criou := true;
  EXCEPTION WHEN OTHERS THEN
    v_criou  := false;
    v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  PERFORM public.qa_up_voltar_papel();
  PERFORM public.qa_up_sair();

  IF NOT v_criou THEN
    r.situacao := 'passou';
    r.obtido := format('A liberação acima do teto do concedente foi recusada. Motivo: %s.',
                       COALESCE(v_motivo, '(a inserção não afetou nada)'));
    r.detalhe := jsonb_build_object('motivo', v_motivo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO ACIMA DO TETO ACEITA: um usuário cujo perfil só alcança o módulo Ponto concedeu a '
             || 'outro uma liberação de escopo de grupo econômico com ação administrar em Documentos. '
             || 'A liberação vira a porta dos fundos da escalada de privilégio.';
    r.detalhe := jsonb_build_object('usuario_alvo', v_alvo);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_voltar_papel();
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ─────────────────────────────────────────────────────────
-- NAC-006 — ninguém atribui perfil acima do próprio teto. Mesma correção.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_nac_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_p_super uuid; v_criou boolean := false;
  v_tem_trava boolean; v_motivo text; v_p_dele uuid;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA: existe trava que impeça conceder acima do próprio teto?';
  r.esperado    := 'Uma trava no banco recusa a atribuição de perfil de escopo superior ao de quem concede';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  PERFORM public.qa_fixture_limpar('NAC-006');

  -- A trava seria um gatilho ou política em usuario_perfil_vinculos que
  -- compare o teto de quem concede com o do perfil concedido.
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger tg
    JOIN pg_proc p ON p.oid = tg.tgfoid
    WHERE tg.tgrelid = 'public.usuario_perfil_vinculos'::regclass
      AND NOT tg.tgisinternal
      AND tg.tgname NOT LIKE 'qa\_%'
      AND pg_get_functiondef(p.oid) ~* '(teto|hierarqui|has_minimum_role|superadmin|nivel_risco)'
  ) INTO v_tem_trava;

  r.passo_ordem := 2;
  r.passo_acao  := 'Um usuário comum tenta atribuir a si mesmo um perfil de escopo máximo';
  v_u    := public.qa_up_usuario('NAC-006', 1, '99900001150', 'ativo');
  v_alvo := public.qa_up_usuario('NAC-006', 2, '99900001230', 'ativo');
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;
  v_p_super := public.qa_up_perfil('NAC-006', 'Escopo Maximo', 'ponto', 'grupo_economico', 'administrar');

  -- O concedente precisa ser um administrador de empresa DE VERDADE, com
  -- vínculo na empresa. Sem vínculo, as políticas o barrariam por não
  -- pertencer à empresa, e o verde mediria a falta da fixture, não o teto.
  v_p_dele := public.qa_up_perfil('NAC-006', 'Admin de empresa', 'ponto', 'empresa_inteira', 'administrar');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p_dele);

  PERFORM public.qa_up_entrar(v_uid);
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.usuario_perfil_vinculos
      (tenant_id, usuario_id, empresa_id, perfil_id, ativo)
    VALUES (public.qa_sandbox_tenant_id(), v_alvo, public.qa_empresa('[QA] Alfa'), v_p_super, true);
    v_criou := true;
  EXCEPTION WHEN OTHERS THEN
    v_criou  := false;
    v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  PERFORM public.qa_up_voltar_papel();
  PERFORM public.qa_up_sair();

  IF NOT v_criou THEN
    r.situacao := 'passou';
    -- Importante dizer POR QUE barrou: uma recusa vinda do isolamento é uma
    -- defesa real, mas não é a mesma coisa que uma trava de hierarquia. Sem
    -- essa distinção o verde esconderia a lacuna.
    r.obtido := format('A concessão acima do próprio teto foi recusada. Motivo da recusa: %s. '
             || 'Trava de hierarquia específica encontrada no banco: %s — quando ela é "false", quem barrou '
             || 'foi a camada de isolamento, e não uma regra de teto: a defesa existe, mas por outro caminho.',
             COALESCE(v_motivo, '(a inserção simplesmente não afetou nada)'), v_tem_trava);
    r.detalhe := jsonb_build_object('trava_de_hierarquia', v_tem_trava, 'motivo', v_motivo);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('CONCESSÃO ACIMA DO TETO ACEITA: um usuário comum atribuiu a outro um perfil de escopo '
             || 'máximo (grupo_economico, ação administrar) sem possuir nada parecido. '
             || 'Trava de hierarquia encontrada no banco: %s. Sem teto, o caminho até o poder total é '
             || 'de dois passos: crio o perfil, atribuo a mim.', v_tem_trava);
    r.detalhe := jsonb_build_object('trava_no_banco', v_tem_trava);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM public.qa_up_voltar_papel();
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ─────────────────────────────────────────────────────────
-- As outras dez: só a mensagem muda, o teste é o mesmo.
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_nac_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_outro uuid; v_u uuid; v_uid uuid; v_p uuid; v_viu int; v_alterou int;
BEGIN
  PERFORM public.qa_fixture_limpar('NAC-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Perfil personalizado criado no cercado; olhar com os olhos de outro cliente';
  r.esperado    := 'O perfil do cercado não aparece nem pode ser alterado por usuário de outro cliente';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente, então não há "outro lado" para '
             || 'provar o isolamento. Em ambiente com mais de um cliente esta rotina roda de verdade.';
    RETURN r;
  END IF;

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_u := public.qa_up_usuario('NAC-005', 1, '99900001079', 'ativo');
  v_p := public.qa_up_perfil('NAC-005', 'So do cercado', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Como usuário do cercado, listar perfis do OUTRO cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_viu FROM public.perfis_acesso WHERE tenant_id = v_outro;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  r.passo_ordem := 3;
  r.passo_acao  := 'Como usuário do cercado, tentar ALTERAR perfil do outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.perfis_acesso SET descricao = '[QA-NAC-005] invasao' WHERE tenant_id = v_outro;
    GET DIAGNOSTICS v_alterou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN
    v_alterou := 0;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_viu = 0 AND v_alterou = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Os perfis do outro cliente não apareceram nem puderam ser alterados: a configuração de acesso '
             || 'de cada cliente fica dentro da casa dele.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('PERFIS VAZAM ENTRE CLIENTES: um usuário do cercado enxergou %s perfil(is) e alterou %s '
             || 'do outro cliente. Vazar perfil é vazar a própria estrutura de acesso de quem contratou.', v_viu, v_alterou);
    r.detalhe := jsonb_build_object('outro_tenant', v_outro, 'viu', v_viu, 'alterou', v_alterou);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_isol_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_uid uuid; v_proprias int; v_alheias int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, consultar uma tabela sensível';
  r.esperado    := 'Só linhas do próprio cliente — e pelo menos uma, senão não se provou leitura nenhuma';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-001', '99900001230');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar neste ambiente a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Contar o que o usuário enxerga, dentro e fora do próprio cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) FILTER (WHERE tenant_id = v_t),
         count(*) FILTER (WHERE tenant_id <> v_t)
  INTO v_proprias, v_alheias
  FROM public.usuarios_base;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_proprias > 0 AND v_alheias = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('O usuário enxergou %s linha(s) do próprio cliente e nenhuma de outro.', v_proprias);
  ELSIF v_proprias = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'O usuário não enxergou NADA, nem do próprio cliente. O isolamento não pode ser tão fechado '
             || 'que o dono do dado fique de fora: tabela com política que nega tudo é tão defeituosa quanto '
             || 'tabela sem política — e alguém vai "consertar" desligando o isolamento.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO: o usuário enxergou %s linha(s) de OUTRO cliente.', v_alheias);
    r.detalhe := jsonb_build_object('proprias', v_proprias, 'alheias', v_alheias);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_isol_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_alvo uuid; v_por_busca int; v_por_id int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, procurar linhas de OUTRO cliente — por busca e pelo id exato';
  r.esperado    := 'Zero linhas nos dois caminhos';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente: sem o outro lado, o lado negativo '
             || 'do isolamento não tem o que provar.';
    RETURN r;
  END IF;

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-002', '99900001311');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id INTO v_alvo FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Buscar por cliente e depois pelo id exato de uma linha dele';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_por_busca FROM public.usuarios_base WHERE tenant_id = v_outro;
  SELECT count(*) INTO v_por_id    FROM public.usuarios_base WHERE id = v_alvo;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_por_busca = 0 AND v_por_id = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma linha do outro cliente foi alcançada, nem por busca nem pelo id exato.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('VAZAMENTO ENTRE CLIENTES: por busca %s linha(s), pelo id exato %s. É o risco '
             || 'existencial do produto — dado pessoal de um cliente na mão de outro (LGPD art. 46).',
             v_por_busca, v_por_id);
    r.detalhe := jsonb_build_object('outro_tenant', v_outro, 'por_busca', v_por_busca, 'por_id', v_por_id);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_isol_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_alvo uuid; v_alterou int := 0; v_apagou int := 0; v_intacta boolean;
  v_nome_antes text; v_nome_depois text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, tentar ALTERAR e EXCLUIR linha de outro cliente';
  r.esperado    := 'Zero linhas afetadas nos dois verbos, e a linha alheia intacta';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-003', '99900001400');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id, nome_completo INTO v_alvo, v_nome_antes
  FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar alterar e excluir a linha alheia';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.usuarios_base SET nome_completo = '[QA-ISOL-003] invadido' WHERE id = v_alvo;
    GET DIAGNOSTICS v_alterou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_alterou := 0;
  END;
  BEGIN
    DELETE FROM public.usuarios_base WHERE id = v_alvo;
    GET DIAGNOSTICS v_apagou = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN v_apagou := 0;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT nome_completo INTO v_nome_depois FROM public.usuarios_base WHERE id = v_alvo;
  v_intacta := (v_nome_depois IS NOT DISTINCT FROM v_nome_antes);

  IF v_alterou = 0 AND v_apagou = 0 AND v_intacta THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma escrita cruzou a fronteira: zero linhas alteradas, zero excluídas, linha alheia intacta.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ESCRITA CRUZOU A FRONTEIRA: %s linha(s) alterada(s) e %s excluída(s) em outro cliente; '
             || 'linha intacta=%s. É o erro clássico da política que cobre a leitura e esquece a escrita.',
             v_alterou, v_apagou, v_intacta);
    r.detalhe := jsonb_build_object('alterou', v_alterou, 'apagou', v_apagou);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_isol_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_plantou boolean := false; v_motivo text; v_n int;
  v_com_check int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Como usuário do cercado, inserir uma linha DECLARANDO outro cliente';
  r.esperado    := 'Rejeitado pela verificação da política; nenhuma linha nova no outro cliente';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('ISOL-004', '99900001583');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Tentar plantar a linha no outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.usuarios_base
      (tenant_id, nome_completo, email_principal, cpf, tipo_usuario, status, auth_user_id)
    VALUES (v_outro, '[QA-ISOL-004] Plantado', 'qa.isol004.plantado@sandbox.invalid',
            '99900001664', 'colaborador', 'ativo', gen_random_uuid());
    v_plantou := true;
  EXCEPTION WHEN OTHERS THEN
    v_plantou := false;
    v_motivo  := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT count(*) INTO v_n FROM public.usuarios_base
  WHERE tenant_id = v_outro AND nome_completo = '[QA-ISOL-004] Plantado';

  -- Quantas políticas de inserção prendem o cliente na verificação? É a
  -- prova estrutural que sustenta o resultado observado.
  SELECT count(*) INTO v_com_check FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'usuarios_base'
    AND cmd IN ('INSERT','ALL') AND COALESCE(with_check, '') ILIKE '%tenant%';

  -- A trava do cercado é um gatilho BEFORE: ela roda ANTES da verificação da
  -- política. Quando é ela quem recusa, o sistema nem chegou a ser consultado,
  -- e dar "passou" aqui seria creditar ao produto uma defesa que foi do QA.
  -- Nesse caso o veredito passa a se apoiar na prova estrutural: as políticas
  -- de inserção prendem o cliente na verificação?
  IF NOT v_plantou AND v_n = 0 AND COALESCE(v_motivo, '') ILIKE '%QA BLOQUEADO%' THEN
    IF v_com_check > 0 THEN
      r.situacao := 'passou';
      r.obtido := format('Nada foi plantado no outro cliente. Ressalva honesta sobre a evidência: quem recusou '
               || 'primeiro foi a trava do cercado de QA (gatilho BEFORE, que roda antes da verificação da '
               || 'política), então a recusa do sistema não pôde ser observada em ação. O veredito se apoia '
               || 'na prova estrutural: %s política(s) de inserção em usuarios_base prendem o cliente na '
               || 'cláusula de verificação, que é o que impede plantar linha em cliente alheio.', v_com_check);
    ELSE
      r.situacao := 'falhou';
      r.obtido := 'NÃO HÁ VERIFICAÇÃO DE CLIENTE NA INSERÇÃO: nenhuma política de inserção em usuarios_base '
               || 'prende o tenant_id na cláusula de verificação. Nada foi plantado nesta rodada apenas '
               || 'porque a trava do cercado de QA recusou antes — fora do QA, essa trava não existe.';
      r.detalhe := jsonb_build_object('politicas_com_check', v_com_check, 'motivo', v_motivo);
    END IF;
  ELSIF NOT v_plantou AND v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('A inserção com cliente alheio foi rejeitada pelo próprio sistema e nada foi plantado. '
             || 'Motivo: %s. Políticas de inserção que prendem o cliente na verificação: %s.',
             COALESCE(v_motivo, '(sem erro, mas nada gravado)'), v_com_check);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('LINHA PLANTADA EM OUTRO CLIENTE: inserção aceita=%s, linhas encontradas=%s. '
             || 'Políticas de inserção prendendo o cliente: %s. Sem essa verificação dá para semear dado '
             || 'dentro do cliente errado — e ele aparece lá como se fosse legítimo.',
             v_plantou, v_n, v_com_check);
    r.detalhe := jsonb_build_object('plantou', v_plantou, 'linhas', v_n, 'politicas_com_check', v_com_check);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_priv_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_restrito uuid; v_amplo uuid; v_promoveu int := 0; v_virou_admin boolean := false;
  v_perfil_final uuid; v_motivo text;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Colaborador tenta trocar o próprio perfil por um amplo e virar admin do sistema';
  r.esperado    := 'Negado nos dois caminhos; o nível dele não muda';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_u       := public.qa_up_usuario('PRIV-001', 1, '99900001745', 'ativo');
  v_restrito:= public.qa_up_perfil('PRIV-001', 'Colaborador', 'ponto', 'proprio_usuario');
  v_amplo   := public.qa_up_perfil('PRIV-001', 'Admin', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_restrito);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Auto-promoção: trocar o perfil do próprio vínculo pelo amplo';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.usuario_perfil_vinculos SET perfil_id = v_amplo WHERE usuario_id = v_u;
    GET DIAGNOSTICS v_promoveu = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_promoveu := 0; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  r.passo_ordem := 3;
  r.passo_acao  := 'Auto-promoção pelo outro caminho: conceder a si mesmo papel de administrador';
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_uid, 'admin');
    v_virou_admin := true;
  EXCEPTION WHEN OTHERS THEN
    v_virou_admin := false;
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT perfil_id INTO v_perfil_final FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF v_promoveu = 0 AND NOT v_virou_admin AND v_perfil_final = v_restrito THEN
    r.situacao := 'passou';
    r.obtido := format('A auto-promoção foi negada nos dois caminhos e o nível ficou como estava. Motivo: %s.',
                       COALESCE(v_motivo, '(nenhuma linha afetada)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('AUTO-PROMOÇÃO POSSÍVEL: o usuário alterou o próprio vínculo em %s linha(s) e/ou '
             || 'concedeu a si mesmo papel de administrador (%s). É a escalada mais direta que existe: '
             || 'quem entra como colaborador sai como administrador sem passar por ninguém.',
             v_promoveu, v_virou_admin);
    r.detalhe := jsonb_build_object('linhas_alteradas', v_promoveu, 'virou_admin', v_virou_admin);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_priv_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_alvo_uid uuid; v_p uuid; v_concedeu boolean := false; v_motivo text;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário sem poder de sistema tenta conceder a outro um papel acima do seu';
  r.esperado    := 'Negado — ninguém concede acima do próprio teto';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_u    := public.qa_up_usuario('PRIV-002', 1, '99900001826', 'ativo');
  v_alvo := public.qa_up_usuario('PRIV-002', 2, '99900001907', 'ativo');
  v_p    := public.qa_up_perfil('PRIV-002', 'Comum', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid      FROM public.usuarios_base WHERE id = v_u;
  SELECT auth_user_id INTO v_alvo_uid FROM public.usuarios_base WHERE id = v_alvo;

  r.passo_ordem := 2;
  r.passo_acao  := 'Conceder ao alvo um papel de sistema que o concedente não possui';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_alvo_uid, 'owner');
    v_concedeu := true;
  EXCEPTION WHEN OTHERS THEN
    v_concedeu := false; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF NOT v_concedeu THEN
    r.situacao := 'passou';
    r.obtido := format('A concessão acima do teto foi recusada. Motivo: %s.', COALESCE(v_motivo, '(nada gravado)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'CONCESSÃO ACIMA DO TETO ACEITA: um usuário comum concedeu a outro o papel de dono do '
             || 'sistema. Com isso, dois usuários comuns combinados chegam ao poder total em um passo cada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_priv_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_empresas int; v_perfis int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Usar a credencial de um cliente para alcançar recursos de outro';
  r.esperado    := 'Negado: a credencial não abre nada fora do cliente dela';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('PRIV-004', '99900002121');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Com essa credencial, alcançar empresas e perfis do outro cliente';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_empresas FROM public.empresa_cadastro WHERE tenant_id = v_outro;
  SELECT count(*) INTO v_perfis   FROM public.perfis_acesso    WHERE tenant_id = v_outro;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_empresas = 0 AND v_perfis = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'A credencial não abriu nada do outro cliente: nem empresas, nem perfis.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('CREDENCIAL ATRAVESSA A FRONTEIRA: alcançou %s empresa(s) e %s perfil(is) de outro '
             || 'cliente.', v_empresas, v_perfis);
    r.detalhe := jsonb_build_object('empresas', v_empresas, 'perfis', v_perfis);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_priv_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_outro uuid; v_uid uuid; v_id_alheio uuid; v_viu int; v_nome text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'Trocar o id do recurso por um id VÁLIDO e EXISTENTE de outro cliente';
  r.esperado    := 'Negado mesmo com o id certo, e sem revelar que o registro existe';

  v_outro := public.qa_up_outro_tenant();
  IF v_outro IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não existe um segundo cliente com dados neste ambiente.';
    RETURN r;
  END IF;
  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_uid := public.qa_up_usuario_isolado('PRIV-005', '99900002202');
  IF v_uid IS NULL THEN
    r.situacao := 'nao_implementado';
    r.obtido := 'Não foi possível montar a identidade que o isolamento consulta (profiles).';
    RETURN r;
  END IF;

  SELECT id INTO v_id_alheio FROM public.usuarios_base WHERE tenant_id = v_outro LIMIT 1;

  r.passo_ordem := 2;
  r.passo_acao  := 'Buscar exatamente por esse id';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_viu FROM public.usuarios_base WHERE id = v_id_alheio;
  SELECT nome_completo INTO v_nome FROM public.usuarios_base WHERE id = v_id_alheio;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  IF v_viu = 0 AND v_nome IS NULL THEN
    r.situacao := 'passou';
    r.obtido := 'O id válido de outro cliente não devolveu nada e nenhum dado dele foi revelado. '
             || 'O id ser um identificador aleatório dificulta adivinhar, mas quem prova o caso é a negação.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACESSO POR ID ALHEIO: a busca pelo id de outro cliente devolveu %s linha(s) e o nome '
             || '"%s". Trocar um identificador na chamada é a forma mais barata de vazamento que existe.',
             v_viu, COALESCE(v_nome, '(vazio)'));
    r.detalhe := jsonb_build_object('linhas', v_viu);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION public.qa_caso_priv_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_u uuid; v_uid uuid; v_alvo uuid; v_alvo_uid uuid; v_p uuid;
  v_virou boolean := false; v_motivo text; v_n int;
BEGIN
  PERFORM public.qa_fixture_limpar('PRIV-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Pelas vias normais de administração de empresa, tentar criar um superadmin';
  r.esperado    := 'Negado — só o fluxo controlado cria superadmin';

  IF NOT public.qa_up_pode_virar_usuario() THEN
    r.situacao := 'nao_implementado';
    r.obtido := public.qa_up_motivo_sem_papel();
    RETURN r;
  END IF;

  v_u    := public.qa_up_usuario('PRIV-006', 1, '99900002393', 'ativo');
  v_alvo := public.qa_up_usuario('PRIV-006', 2, '99900002474', 'ativo');
  v_p    := public.qa_up_perfil('PRIV-006', 'Admin de empresa', 'ponto', 'empresa_inteira', 'administrar');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_p);
  SELECT auth_user_id INTO v_uid      FROM public.usuarios_base WHERE id = v_u;
  SELECT auth_user_id INTO v_alvo_uid FROM public.usuarios_base WHERE id = v_alvo;

  r.passo_ordem := 2;
  r.passo_acao  := 'Atribuir o papel de superadmin';
  PERFORM public.qa_up_entrar(v_uid);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES (v_alvo_uid, 'superadmin');
    v_virou := true;
  EXCEPTION WHEN OTHERS THEN
    v_virou := false; v_motivo := SQLERRM || ' [' || SQLSTATE || ']';
  END;
  RESET ROLE;
  PERFORM public.qa_up_sair();

  SELECT count(*) INTO v_n FROM public.user_roles
  WHERE user_id = v_alvo_uid AND role = 'superadmin';

  IF NOT v_virou AND v_n = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('O papel de superadmin não foi concedido pelas vias normais. Motivo: %s.',
                       COALESCE(v_motivo, '(nada gravado)'));
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('SUPERADMIN CRIADO FORA DO FLUXO CONTROLADO: concessão aceita=%s, papéis encontrados=%s. '
             || 'Superadmin é o maior poder do produto e atravessa o isolamento por desenho: se um admin de '
             || 'empresa cria um, o isolamento de 1.100 clientes deixa de valer.', v_virou, v_n);
    r.detalhe := jsonb_build_object('virou', v_virou, 'papeis', v_n);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;
