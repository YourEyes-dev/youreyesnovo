-- =========================================================
-- Achados do motor de QA — USR-001 e ISOL-008
--
-- Continuação de 20260916210000. Dois achados que eu havia deixado de fora
-- por dependerem de entendimento que agora existe:
--
--   USR-001 — convidado que ainda não ativou obtinha acesso. Eu não fechei
--   antes porque exigir status = 'ativo' derrubaria quem está legitimamente
--   dentro: nenhuma rotina do banco garantia o carimbo. Este arquivo cria a
--   garantia PRIMEIRO e só então fecha a porta — nesta ordem, não na inversa.
--
--   ISOL-008 — 9 rotinas com privilégio do dono que tocam dado de cliente sem
--   amarrar cliente nem usuário. Lidas UMA A UMA, como prometido. Sete são
--   legítimas por motivos diferentes e viram exceção documentada; duas são
--   vazamento de verdade e são corrigidas.
-- =========================================================

SET lock_timeout = '10s';

-- ═════════════════════════════════════════════════════════
-- 1) USR-001 — primeiro o carimbo, depois a trava
--
-- A INVARIANTE QUE O PRODUTO JÁ TEM, e que não estava escrita no banco:
-- ninguém entra sem auth_user_id. Quando o administrador provisiona o acesso,
-- a tela grava auth_user_id, status 'ativo' e convite_aceito_em na mesma
-- operação. Ou seja: ter conta e estar ativo nascem juntos — mas só pela tela.
-- Qualquer outro caminho (importação, rotina, correção manual) podia ligar a
-- conta e deixar o status para trás, e era essa fresta que USR-001 media.
--
-- O gatilho torna a invariante do banco: ligou a conta, está ativo. Ele só
-- promove quem está em status de PRÉ-ativação; nunca ressuscita alguém que
-- foi desligado, bloqueado ou suspenso — isso seria reabrir a porta que o
-- arquivo anterior fechou.
-- ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.usuario_ativa_ao_ligar_conta()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.auth_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.auth_user_id IS NULL)
     AND NEW.status::text IN ('rascunho', 'pendente_convite', 'convite_enviado', 'aguardando_ativacao')
  THEN
    NEW.status := 'ativo';
    NEW.convite_aceito_em := COALESCE(NEW.convite_aceito_em, now());
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.usuario_ativa_ao_ligar_conta() IS
  'Carimba ativo quando a conta de acesso é ligada ao cadastro. Só promove quem está em pré-ativação: desligado, bloqueado e suspenso continuam como estão.';

DROP TRIGGER IF EXISTS trg_usuario_ativa_ao_ligar_conta ON public.usuarios_base;
CREATE TRIGGER trg_usuario_ativa_ao_ligar_conta
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.usuarios_base
  FOR EACH ROW EXECUTE FUNCTION public.usuario_ativa_ao_ligar_conta();

-- Reparo do passado: quem JÁ tem conta ligada e ficou com status de
-- pré-ativação. Sem isto, fechar a porta derrubaria exatamente essas pessoas.
-- Guarda as linhas antes, como manda a regra da casa para script que altera
-- dado existente — mesmo sendo uma correção de estado inconsistente.
DO $reparo$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.usuarios_base
  WHERE auth_user_id IS NOT NULL
    AND status::text IN ('rascunho', 'pendente_convite', 'convite_enviado', 'aguardando_ativacao');

  -- A cópia nasce SEMPRE, mesmo vazia. Criá-la só quando há o que reparar
  -- deixaria a conferência final do script de entrega apontando para uma
  -- tabela inexistente — e, como o SQL Editor roda tudo em UMA transação,
  -- esse erro na última linha desfaria o arquivo inteiro. (Foi o que
  -- aconteceu ao testar; a cópia vazia é o preço de a conferência ser
  -- sempre válida.)
  CREATE TABLE IF NOT EXISTS public.backup_usuarios_status_ativacao_20260916 AS
  SELECT * FROM public.usuarios_base
  WHERE auth_user_id IS NOT NULL
    AND status::text IN ('rascunho', 'pendente_convite', 'convite_enviado', 'aguardando_ativacao');

  -- A cópia guarda linha de cliente: nasce protegida, ao contrário das
  -- outras backup_* que o ISOL-005 acusou.
  EXECUTE 'ALTER TABLE public.backup_usuarios_status_ativacao_20260916 ENABLE ROW LEVEL SECURITY';
  BEGIN
    EXECUTE 'CREATE POLICY somente_superadmin ON public.backup_usuarios_status_ativacao_20260916
             FOR ALL USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))';
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  IF v_n = 0 THEN
    RAISE NOTICE 'USR-001: nenhum cadastro com conta ligada e status de pre-ativacao. Nada a reparar.';
  ELSE
    UPDATE public.usuarios_base u
    SET status = 'ativo',
        convite_aceito_em = COALESCE(u.convite_aceito_em, now())
    FROM public.backup_usuarios_status_ativacao_20260916 b
    WHERE u.id = b.id;

    RAISE NOTICE 'USR-001: % cadastro(s) com conta ligada carimbados como ativo. Copia em backup_usuarios_status_ativacao_20260916.', v_n;
    -- Para desfazer:
    --   UPDATE public.usuarios_base u SET status = b.status, convite_aceito_em = b.convite_aceito_em
    --   FROM public.backup_usuarios_status_ativacao_20260916 b WHERE u.id = b.id;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'USR-001: reparo nao aplicado: %', SQLERRM;
END $reparo$;

-- Agora sim a trava: com o carimbo garantido, os status de PRÉ-ativação podem
-- negar sem derrubar ninguém — quem consegue entrar tem conta ligada, e quem
-- tem conta ligada está 'ativo'.
CREATE OR REPLACE FUNCTION public.perfil_permite_modulo(
  p_tenant_id uuid,
  VARIADIC p_modulos text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  SELECT ub.status::text INTO v_status
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  LIMIT 1;

  -- Só 'ativo' abre porta. Terminal (desligado, bloqueado, suspenso,
  -- arquivado) nega, e pré-ativação também — a partir do gatilho desta
  -- migration, ninguém com conta ligada fica em pré-ativação.
  -- Cadastro inexistente no cliente (v_status nulo) também nega: é o caso de
  -- quem tem conta de autenticação mas nenhum vínculo com este cliente.
  IF v_status IS DISTINCT FROM 'ativo' THEN
    RETURN false;
  END IF;

  IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
      AND ub.tipo_usuario::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
    JOIN public.perfis_acesso pa
      ON pa.id = v.perfil_id
     AND COALESCE(pa.ativo, true) = true
     AND (pa.expira_em IS NULL OR pa.expira_em > now())
    JOIN public.perfil_permissoes pp
      ON pp.perfil_id = v.perfil_id
     AND COALESCE(pp.ativo, true) = true
     AND pp.modulo = ANY (p_modulos)
     AND COALESCE(pp.escopo::text, '') <> 'proprio_usuario'
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  ) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.perfil_excecoes pe
      ON pe.usuario_id = ub.id
     AND pe.tenant_id = ub.tenant_id
     AND COALESCE(pe.ativo, true) = true
     AND COALESCE(pe.tipo, 'adicional') = 'adicional'
     AND (pe.expira_em IS NULL OR pe.expira_em > now())
     AND pe.modulo = ANY (p_modulos)
     AND COALESCE(pe.escopo::text, '') <> 'proprio_usuario'
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) TO authenticated;

COMMENT ON FUNCTION public.perfil_permite_modulo(uuid, text[]) IS
  'O perfil de acesso do usuário logado permite acesso amplo a algum destes módulos? Exige cadastro ativo no cliente (pré-ativação e status terminal negam) e soma as liberações pontuais vigentes. Superadmin atravessa por desenho.';

-- ═════════════════════════════════════════════════════════
-- 2) ISOL-008 — as 9 rotinas privilegiadas, lidas uma a uma
--
-- SETE SÃO LEGÍTIMAS, por três motivos diferentes:
--
--   · get_admissao_by_token, get_admissao_documentos_by_token,
--     update_admissao_documento_by_token, update_admissao_foto_by_token e
--     finalizar_admissao_by_token — o fluxo da admissão pelo link que o
--     candidato recebe. Elas NÃO têm filtro de cliente porque a autorização
--     delas É O TOKEN: um segredo que só quem recebeu o link possui. Pedir
--     filtro de cliente aqui seria pedir login de quem, por desenho, ainda
--     não tem. O que importa nelas é o token ser imprevisível e expirar —
--     outra conversa, não esta.
--   · sync_admissao_contrato_experiencia — é função de GATILHO em
--     contratos_experiencia. Gatilho roda na linha que está sendo gravada, e
--     essa linha já passou pela política da tabela. Filtro de cliente ali
--     seria redundante.
--   · gerar_login_youreyes — monta um nome de login e confere se já existe.
--     A varredura sem filtro é o PONTO: login é único no sistema inteiro, não
--     por cliente. Ela não devolve dado de cliente nenhum, só o texto do login.
--
-- DUAS SÃO VAZAMENTO DE VERDADE e são corrigidas abaixo. As duas recebem um
-- id e respondem sobre ele sem perguntar de quem é. Hoje só não são um
-- problema maior porque o id é aleatório e difícil de adivinhar — e "id
-- difícil de adivinhar" não é autorização, é obscuridade. É exatamente o que
-- o caso PRIV-005 diz.
--
-- A CORREÇÃO PRESERVA O USO INTERNO: quando não há usuário logado (rotina de
-- madrugada, gatilho, chamada de dentro de outra função privilegiada), elas
-- seguem respondendo como hoje. O filtro vale para quem chega com identidade,
-- que é quem poderia abusar.
-- ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ponto_empresa_do_colaborador(p_colaborador_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT a.empresa_id
  FROM public.admissoes a
  WHERE a.id = p_colaborador_id
    AND (
      -- sem usuário logado: contexto interno (cron, gatilho, outra função)
      auth.uid() IS NULL
      OR public.is_superadmin(auth.uid())
      OR a.tenant_id = public.get_user_tenant_id()
    );
$fn$;

COMMENT ON FUNCTION public.ponto_empresa_do_colaborador(uuid) IS
  'Empresa do colaborador. Para quem chega com identidade, só responde sobre colaborador do próprio cliente (ISOL-008); em contexto interno segue respondendo como antes.';

CREATE OR REPLACE FUNCTION public.colaborador_tem_vinculos(_admissao_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_total int := 0;
  v_detalhes jsonb := '{}'::jsonb;
  v_count int;
BEGIN
  -- Antes de contar o que quer que seja: este colaborador é de quem pergunta?
  -- Sem esta porteira, a função respondia sobre QUALQUER id — e as contagens
  -- contam história: dizer que um id tem 3 atestados já é dado de saúde.
  IF auth.uid() IS NOT NULL
     AND NOT public.is_superadmin(auth.uid())
     AND NOT EXISTS (
       SELECT 1 FROM public.admissoes a
       WHERE a.id = _admissao_id AND a.tenant_id = public.get_user_tenant_id()
     )
  THEN
    RETURN jsonb_build_object('total', 0, 'detalhes', '{}'::jsonb, 'fora_do_alcance', true);
  END IF;

  SELECT count(*) INTO v_count FROM public.ponto_marcacoes WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('ponto_marcacoes', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.ponto_diario WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('ponto_diario', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.ferias_solicitacoes WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('ferias', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.atestados WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('atestados', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.afastamentos WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('afastamentos', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.ordens_servico WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('ordens_servico', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.ponto_ajustes WHERE colaborador_id = _admissao_id;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('ponto_ajustes', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.folha_itens WHERE colaborador_id = _admissao_id::text;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('folha', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.eventos_sst WHERE colaborador_id = _admissao_id::text;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('eventos_sst', v_count); END IF;
  SELECT count(*) INTO v_count FROM public.pdis WHERE colaborador_id = _admissao_id::text;
  IF v_count > 0 THEN v_total := v_total + v_count; v_detalhes := v_detalhes || jsonb_build_object('pdis', v_count); END IF;

  RETURN jsonb_build_object('total', v_total, 'detalhes', v_detalhes);
END;
$fn$;

COMMENT ON FUNCTION public.colaborador_tem_vinculos(uuid) IS
  'Conta os registros ligados ao colaborador. Para quem chega com identidade, só responde sobre colaborador do próprio cliente (ISOL-008); em contexto interno segue como antes.';

-- ═════════════════════════════════════════════════════════
-- 3) A ROTINA DE QA ISOL-008 PASSA A RECONHECER AS EXCEÇÕES DOCUMENTADAS
--
-- Com as duas corrigidas acima, sobram sete rotinas que a varredura acusa e
-- que, lidas de perto, são legítimas — pelos motivos que ficam escritos dentro
-- da própria rotina de QA, ao lado de cada nome. Sem isso o caso ficaria
-- vermelho para sempre; e vermelho que nunca fecha é vermelho que ninguém lê.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.qa_caso_isol_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_total int; v_sem_filtro int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): rotinas que rodam com privilégio do dono';
  r.esperado    := 'Todas reaplicam o filtro de cliente por dentro — privilégio do dono ignora a política';

  SELECT count(*) INTO v_total
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosecdef
    AND p.proname NOT LIKE 'qa\_%';

  SELECT count(*), string_agg(x.proname, ', ' ORDER BY x.proname)
  INTO v_sem_filtro, v_lista
  FROM (
    SELECT p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosecdef
      AND p.proname NOT LIKE 'qa\_%'
      -- ALCANCE, antes de qualquer outra coisa: a premissa deste caso é que um
      -- usuário de cliente CHAME a rotina e receba dado alheio. Se nem o
      -- usuário logado nem o anônimo conseguem executá-la, essa premissa não
      -- existe — quem alcança é só o papel de serviço, que já trabalha com
      -- privilégio total por desenho. Sem este recorte o caso acusaria toda
      -- rotina administrativa e interna, e um caso que acusa tudo não informa
      -- nada. (Descoberto quando o detector acusou empresa_ativa_adocao, uma
      -- medição fechada ao papel de serviço.)
      AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
           OR has_function_privilege('anon', p.oid, 'EXECUTE'))
      -- toca tabela de dado de cliente...
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|admissoes|atestados|perfil_excecoes|usuario_perfil_vinculos|profiles)'
      -- ...e em nenhum lugar do corpo amarra o cliente ou o usuário logado
      AND pg_get_functiondef(p.oid) !~* '(tenant_id|auth\.uid\(\)|get_user_tenant_id|is_superadmin|has_minimum_role)'
      -- EXCEÇÕES DOCUMENTADAS: rotinas cuja autorização vem por OUTRO caminho,
      -- lidas uma a uma em 16/09/2026. A lista mora aqui para ficar à vista de
      -- quem abre o caso; rotina nova NÃO entra sozinha — aparece como achado
      -- até alguém decidir, por escrito, que tem justificativa.
      AND p.proname NOT IN (
        -- Admissão pelo link do candidato: a autorização É O TOKEN, um segredo
        -- que só quem recebeu o link tem. Exigir filtro de cliente seria exigir
        -- login de quem, por desenho, ainda não tem. (O que importa nelas é o
        -- token ser imprevisível e expirar — outra conversa, não esta.)
        'get_admissao_by_token', 'get_admissao_documentos_by_token',
        'update_admissao_documento_by_token', 'update_admissao_foto_by_token',
        'finalizar_admissao_by_token',
        -- Função de GATILHO: roda na linha que está sendo gravada, e essa linha
        -- já passou pela política da tabela. Filtro ali seria redundante.
        'sync_admissao_contrato_experiencia',
        -- Monta um nome de login e confere se já existe. A varredura sem filtro
        -- é o ponto: login é único no sistema inteiro, não por cliente. Não
        -- devolve dado de cliente nenhum, só o texto do login.
        'gerar_login_youreyes'
      )
  ) x;

  IF v_sem_filtro = 0 THEN
    r.situacao := 'passou';
    r.obtido := format('Todas as %s rotinas com privilégio do dono que tocam dado de cliente amarram o cliente '
             || 'ou o usuário logado por dentro, fora as exceções documentadas no corpo desta rotina '
             || '(admissão por token, função de gatilho e o gerador de login) — cada uma com o motivo ao lado.', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('TÚNEL ENTRE CLIENTES: de %s rotinas com privilégio do dono, %s tocam dado de cliente '
             || 'sem amarrar o cliente nem o usuário logado em lugar nenhum do corpo: %s. Rotina assim roda '
             || 'com o privilégio de quem a criou e passa por cima da política de linha — ela é a porta que '
             || 'contorna todo o isolamento.', v_total, v_sem_filtro, v_lista);
    r.detalhe := jsonb_build_object('total_definer', v_total, 'sem_filtro', v_sem_filtro, 'rotinas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- 4) O CASO USR-001 PASSA A MEDIR O QUE AGORA IMPORTA
--
-- A rotina antiga montava um convidado com conta de acesso já ligada e status
-- pendente_convite — uma combinação que, a partir do gatilho criado acima, não
-- existe mais. Ela testava o mundo velho.
--
-- O caso continua o mesmo ("convite não é acesso"), mas a prova muda de forma,
-- porque a garantia mudou. Agora ela mede as DUAS metades:
--   1. a invariante: convite pendente não tem conta ligada — e se alguém ligar
--      a conta, o status é carimbado ativo na hora (não fica pendente);
--   2. a trava: um cadastro que esteja em status de pré-ativação é negado pela
--      decisão de acesso, ainda que carregue identidade.
-- Uma sem a outra não prova nada: a trava sozinha derrubaria gente de verdade,
-- e a invariante sozinha não impede o acesso de um estado inconsistente antigo.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.qa_caso_usr_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_perfil uuid; v_n int;
  v_status_convite text; v_conta_ligada boolean;
  v_status_apos_ligar text; v_acesso boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('USR-001');

  r.passo_ordem := 1;
  r.passo_acao  := 'Convidar usuário com vínculo à Empresa Alfa, sem conta de acesso ainda';
  r.esperado    := 'Convite pendente não tem conta ligada; ligar a conta carimba ativo; e status de pré-ativação é negado';

  v_u := public.qa_up_usuario('USR-001', 1, '99900001079', 'pendente_convite');
  v_perfil := public.qa_up_perfil('USR-001', 'Colaborador', 'ponto', 'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_perfil);

  -- A fixture cria o usuário já com conta (ela precisa dela para simular
  -- login). Aqui se desfaz isso, que é o estado real de um convite pendente.
  UPDATE public.usuarios_base
  SET auth_user_id = NULL, status = 'pendente_convite'
  WHERE id = v_u;

  SELECT status::text, auth_user_id IS NOT NULL INTO v_status_convite, v_conta_ligada
  FROM public.usuarios_base WHERE id = v_u;

  SELECT count(*) INTO v_n FROM public.usuario_perfil_vinculos WHERE usuario_id = v_u;

  IF v_conta_ligada OR v_status_convite <> 'pendente_convite' OR v_n <> 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('Ponto de partida errado: conta ligada=%s, status=%s, vínculos=%s (esperado sem conta, '
             || 'pendente_convite e 1 vínculo).', v_conta_ligada, v_status_convite, v_n);
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao  := 'Ligar a conta de acesso ao cadastro, como faz a ativação';
  v_uid := gen_random_uuid();
  UPDATE public.usuarios_base SET auth_user_id = v_uid WHERE id = v_u;
  SELECT status::text INTO v_status_apos_ligar FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 3;
  r.passo_acao  := 'Forçar o cadastro de volta a um status de pré-ativação e pedir a decisão de acesso';
  -- Simula o estado inconsistente que existia antes (conta ligada, status para
  -- trás) para provar que, mesmo assim, a porta está fechada.
  UPDATE public.usuarios_base SET status = 'convite_enviado' WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);
  v_acesso := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_status_apos_ligar = 'ativo' AND v_acesso IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'Convite não concede acesso: enquanto pendente não há conta ligada; ligar a conta carimba '
             || 'ativo na hora; e um cadastro em pré-ativação é negado pela decisão. Convite é promessa de '
             || 'acesso, não acesso.';
  ELSIF v_status_apos_ligar <> 'ativo' THEN
    r.situacao := 'falhou';
    r.obtido := format('A ATIVAÇÃO NÃO CARIMBA: a conta de acesso foi ligada ao cadastro e o status ficou '
             || '"%s" em vez de ativo. Sem esse carimbo confiável, fechar a porta para pré-ativação '
             || 'derrubaria gente que está legitimamente dentro.', v_status_apos_ligar);
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACESSO EM PRÉ-ATIVAÇÃO: um cadastro com status de convite obteve acesso amplo ao módulo. '
             || 'Quem foi convidado e nunca ativou já entra.';
    r.detalhe := jsonb_build_object('usuario_id', v_u, 'status_apos_ligar', v_status_apos_ligar);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- 5) EMPRESA ATIVA — ETAPA 1: o banco passa a SABER, sem ainda DECIDIR
--
-- O problema que isto começa a resolver (VIN-005, VIN-006, CTX-003, CTX-006,
-- LIB-002): o produto mostra UMA empresa por vez, escolhida no seletor do topo
-- — mas essa escolha vive só no navegador. O banco nunca fica sabendo, e por
-- isso a decisão de acesso é por CLIENTE: um vínculo amplo em qualquer empresa
-- vale em todas as outras do mesmo cliente.
--
-- Esta etapa cria o caminho e NÃO MUDA COMPORTAMENTO NENHUM. Nada consulta
-- empresa_ativa() para decidir acesso ainda. Ela existe para:
--   1. o seletor passar a registrar a escolha;
--   2. medirmos quantas sessões já registram, antes de apertar.
-- A virada (Etapa 2) só acontece com essa medição na mão. Inverter a ordem
-- seria trocar um vazamento por gente sem acesso, que é pior.
--
-- POR QUE GRAVAR NO BANCO e não mandar em cabeçalho ou no token:
--   · cabeçalho exigiria alterar src/integrations/supabase/client.ts, que é
--     arquivo gerado ("do not edit directly") e seria sobrescrito;
--   · token exigiria renovar a sessão a cada troca de empresa;
--   · gravando, quem confere o direito é o banco — e é ele que precisa saber.
-- Consequência aceita (decisão do dono do produto, 16/09/2026): a escolha é
-- por USUÁRIO, não por aba. Duas abas do mesmo usuário mostram a mesma
-- empresa, o que combina com um seletor global que mostra uma por vez.
-- ═════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.usuario_empresa_ativa (
  user_id       uuid PRIMARY KEY,
  tenant_id     uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id    uuid NOT NULL REFERENCES public.empresa_cadastro(id) ON DELETE CASCADE,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.usuario_empresa_ativa IS
  'Qual empresa cada usuário tem ativa no seletor do topo. É como o banco fica sabendo do contexto que hoje só existe no navegador.';

CREATE INDEX IF NOT EXISTS idx_usuario_empresa_ativa_tenant
  ON public.usuario_empresa_ativa(tenant_id);

ALTER TABLE public.usuario_empresa_ativa ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS usuario_empresa_ativa_propria ON public.usuario_empresa_ativa;
CREATE POLICY usuario_empresa_ativa_propria
  ON public.usuario_empresa_ativa FOR ALL
  USING (user_id = auth.uid() OR public.is_superadmin(auth.uid()))
  WITH CHECK (user_id = auth.uid());

-- Registrar a escolha é um GESTO CONFERIDO, não um dado que o cliente manda.
-- Quem diz qual empresa é o navegador; quem diz se pode é o banco. Por isso a
-- gravação passa por aqui e não por um UPDATE direto da tela.
CREATE OR REPLACE FUNCTION public.definir_empresa_ativa(p_empresa_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_tenant uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sem usuário autenticado.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Limpar a escolha é legítimo (sair do contexto).
  IF p_empresa_id IS NULL THEN
    DELETE FROM public.usuario_empresa_ativa WHERE user_id = v_uid;
    RETURN NULL;
  END IF;

  SELECT e.tenant_id INTO v_tenant
  FROM public.empresa_cadastro e WHERE e.id = p_empresa_id;

  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'Empresa não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  -- A porteira: a empresa tem de ser do meu cliente E eu tenho de poder
  -- alcançá-la. O critério de alcance é o MESMO que o sistema já usa
  -- (user_has_empresa_vinculo) — usar a regra que já existe evita inventar
  -- uma segunda definição de "minhas empresas" que divergiria da tela.
  IF NOT public.is_superadmin(v_uid) THEN
    IF v_tenant IS DISTINCT FROM public.get_user_tenant_id() THEN
      RAISE EXCEPTION 'Empresa de outro cliente.' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT public.user_has_empresa_vinculo(p_empresa_id) THEN
      RAISE EXCEPTION 'Sem vínculo com esta empresa.' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  INSERT INTO public.usuario_empresa_ativa (user_id, tenant_id, empresa_id, atualizado_em)
  VALUES (v_uid, v_tenant, p_empresa_id, now())
  ON CONFLICT (user_id) DO UPDATE
    SET empresa_id = EXCLUDED.empresa_id,
        tenant_id  = EXCLUDED.tenant_id,
        atualizado_em = now();

  RETURN p_empresa_id;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.definir_empresa_ativa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.definir_empresa_ativa(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.definir_empresa_ativa(uuid) IS
  'Registra a empresa ativa do usuário, conferindo antes se ele pode alcançá-la. O navegador diz QUAL; o banco diz SE pode.';

-- A leitura que a Etapa 2 vai usar. Hoje ninguém decide com ela.
CREATE OR REPLACE FUNCTION public.empresa_ativa()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT empresa_id FROM public.usuario_empresa_ativa WHERE user_id = auth.uid()
$fn$;

REVOKE EXECUTE ON FUNCTION public.empresa_ativa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.empresa_ativa() TO authenticated, service_role;

COMMENT ON FUNCTION public.empresa_ativa() IS
  'Empresa ativa do usuário logado, ou nulo se ele ainda não registrou nenhuma. Nulo NÃO significa "sem acesso": na Etapa 1 a decisão de acesso ainda não consulta esta função.';

-- A medição que decide quando virar a chave. Só o superadmin lê.
CREATE OR REPLACE FUNCTION public.empresa_ativa_adocao()
RETURNS TABLE (usuarios_com_conta bigint, com_empresa_registrada bigint, registrada_ultimas_24h bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT
    (SELECT count(*) FROM public.usuarios_base
      WHERE auth_user_id IS NOT NULL AND status::text = 'ativo'),
    (SELECT count(*) FROM public.usuario_empresa_ativa),
    (SELECT count(*) FROM public.usuario_empresa_ativa WHERE atualizado_em > now() - interval '24 hours')
$fn$;

REVOKE EXECUTE ON FUNCTION public.empresa_ativa_adocao() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.empresa_ativa_adocao() TO service_role;

COMMENT ON FUNCTION public.empresa_ativa_adocao() IS
  'Quantos usuários ativos existem e quantos já registraram a empresa ativa. É a medição que autoriza a Etapa 2 — virar a chave antes dela trocaria vazamento por gente sem acesso.';
