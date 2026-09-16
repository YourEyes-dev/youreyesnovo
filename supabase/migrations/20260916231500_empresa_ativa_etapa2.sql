-- =========================================================
-- Empresa ativa — ETAPA 2: a decisão passa a respeitar o contexto
--
-- A Etapa 1 (20260916230000) fez o banco SABER qual empresa está ativa. Esta
-- faz ele DECIDIR com isso. Fecha os achados VIN-005, VIN-006, CTX-003,
-- CTX-006 e LIB-002 do motor de QA.
--
-- O PROBLEMA, em uma frase: a decisão de acesso é
-- perfil_permite_modulo(tenant, módulos) — recebe o CLIENTE, não a empresa.
-- Um vínculo amplo em QUALQUER empresa do cliente valia em TODAS as outras.
-- Quem trabalha em três empresas do mesmo grupo enxergava as três ao mesmo
-- tempo, ainda que a tela mostrasse uma por vez.
--
-- A ALAVANCA: as 11 políticas RESTRICTIVE de perfil (perfil_restringe_leitura_*)
-- todas chamam perfil_permite_modulo. Tornar ESSA função ciente da empresa
-- corrige as 11 de uma vez, sem tocar em nenhuma política — que é justamente
-- o que torna esta mudança viável sem uma reescrita de risco.
--
-- COMO A VIRADA É SEGURA
--
-- Quando há empresa ativa registrada, a decisão passa a considerar só os
-- vínculos e as liberações DAQUELA empresa. Para quem usa a tela, isso já vale
-- de imediato — e é o conserto.
--
-- Quando NÃO há empresa registrada (sessão antiga, chamada interna, alguém que
-- ainda não abriu o seletor), o comportamento continua o de hoje. Essa
-- tolerância é proposital e temporária: derrubar quem não registrou seria
-- trocar um vazamento por gente sem acesso.
--
-- Quando a medição mostrar que todo mundo registra, a tolerância se fecha com
-- UM comando, sem nova migration:
--   INSERT INTO public.app_config (chave, valor) VALUES ('empresa_ativa_obrigatoria','true')
--   ON CONFLICT (chave) DO UPDATE SET valor = 'true';
-- e se algo der errado, o mesmo comando com 'false' devolve na hora. Ter o
-- botão de volta importa mais do que a virada em si.
--
-- O QUE NÃO MUDA, DE PROPÓSITO: superadmin, papel de gestão e tipo
-- administrador/gestor seguem valendo no cliente inteiro. Quem administra o
-- cliente administra as empresas dele; recortar isso é outra decisão de
-- produto, não um efeito colateral desta.
-- =========================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.empresa_ativa_obrigatoria()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    (SELECT lower(trim(valor)) = 'true' FROM public.app_config WHERE chave = 'empresa_ativa_obrigatoria'),
    false)
$fn$;

COMMENT ON FUNCTION public.empresa_ativa_obrigatoria() IS
  'Sessão sem empresa ativa registrada deve ser NEGADA? Começa em false (tolerante) e vira true quando a medição de adoção autorizar. Liga e desliga por app_config, sem migration.';

REVOKE EXECUTE ON FUNCTION public.empresa_ativa_obrigatoria() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.empresa_ativa_obrigatoria() TO authenticated, service_role;

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
  v_empresa uuid;
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

  IF v_status IS DISTINCT FROM 'ativo' THEN
    RETURN false;
  END IF;

  -- Quem administra o cliente administra as empresas dele: estes dois ramos
  -- seguem valendo no cliente inteiro, de propósito.
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

  -- O CONTEXTO. Nulo = a sessão ainda não registrou empresa nenhuma.
  v_empresa := public.empresa_ativa();

  IF v_empresa IS NULL AND public.empresa_ativa_obrigatoria() THEN
    RETURN false;
  END IF;

  -- Vínculo. O recorte por empresa é a correção: com contexto, só contam os
  -- vínculos DAQUELA empresa.
  --
  -- O vínculo sem empresa (empresa_id nulo) conta em qualquer contexto, e isso
  -- é seguro: quem nasce assim é o vínculo automático do perfil
  -- "Colaborador (padrão)", cujas permissões são TODAS de escopo
  -- proprio_usuario — ele nunca concede acesso amplo, então não reabre o
  -- vazamento que esta migration fecha.
  IF EXISTS (
    SELECT 1
    FROM public.usuarios_base ub
    JOIN public.usuario_perfil_vinculos v
      ON v.usuario_id = ub.id
     AND v.tenant_id = ub.tenant_id
     AND COALESCE(v.ativo, true) = true
     AND (v.expira_em IS NULL OR v.expira_em > now())
     AND (v_empresa IS NULL OR v.empresa_id IS NULL OR v.empresa_id = v_empresa)
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

  -- Liberação pontual: mesmo recorte. Uma liberação dada na Empresa A não
  -- pode valer quando a pessoa está na Empresa B — era o achado LIB-002.
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
     AND (v_empresa IS NULL OR pe.empresa_id IS NULL OR pe.empresa_id = v_empresa)
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perfil_permite_modulo(uuid, text[]) TO authenticated;

COMMENT ON FUNCTION public.perfil_permite_modulo(uuid, text[]) IS
  'Decisão de acesso do sistema. Exige cadastro ativo; respeita a EMPRESA ATIVA da sessão (vínculos e liberações da empresa em que a pessoa está, não a união de todas); soma liberações vigentes. Sem empresa registrada, tolera e decide como antes — até app_config.empresa_ativa_obrigatoria virar true. Superadmin, papel >= manager e tipo administrador/gestor valem no cliente inteiro, por desenho.';

-- ═════════════════════════════════════════════════════════
-- AS ROTINAS DE QA PASSAM A EXERCITAR O CONTEXTO
--
-- Até aqui elas perguntavam a decisão sem nunca dizer em qual empresa
-- estavam — porque não existia como dizer. Rodá-las sem mudança agora daria
-- verde pelo caminho TOLERANTE (sem empresa registrada, decide como antes),
-- que é justamente o que não queremos provar. Elas passam a registrar a
-- empresa ativa, como o seletor faz, e só então perguntar.
-- ═════════════════════════════════════════════════════════

-- A decisão do banco consulta a empresa ativa?
CREATE OR REPLACE FUNCTION public.qa_up_tem_empresa_ativa()
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ~* 'empresa_ativa'
  )
$fn$;

COMMENT ON FUNCTION public.qa_up_tem_empresa_ativa() IS
  'A decisão de acesso consulta a empresa ativa da sessão? Confere na função que decide, não em qualquer função com nome parecido — existir uma noção de contexto sem a decisão usá-la não vale nada.';

-- VIN-005 — o nível é POR VÍNCULO (premissa P1).
CREATE OR REPLACE FUNCTION public.qa_caso_vin_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_em_alfa boolean; v_em_beta boolean;
  v_tem_empresa boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-005');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário Admin na Alfa e Colaborador na Beta';
  r.esperado    := 'A ação exclusiva de Admin é PERMITIDA na Alfa e NEGADA na Beta';

  v_u  := public.qa_up_usuario('VIN-005', 1, '99900002393', 'ativo');
  v_pa := public.qa_up_perfil('VIN-005', 'Admin Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-005', 'Colab Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  v_tem_empresa := public.qa_up_tem_empresa_ativa();

  r.passo_ordem := 2;
  r.passo_acao  := 'Estando na Alfa, executar a ação de Admin';
  PERFORM public.qa_up_entrar(v_uid);
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Alfa'));
  v_em_alfa := public.perfil_permite_modulo(v_t, 'ponto');

  r.passo_ordem := 3;
  r.passo_acao  := 'Trocar para a Beta e tentar a MESMA ação';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Beta'));
  v_em_beta := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_tem_empresa AND v_em_alfa IS TRUE AND v_em_beta IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A mesma ação foi permitida na Alfa e negada na Beta: o nível acompanha o vínculo da empresa '
             || 'em que a pessoa está, não a união de todas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('O NÍVEL NÃO ACOMPANHOU O VÍNCULO: a decisão consulta a empresa ativa=%s; resposta na '
             || 'Alfa=%s, na Beta=%s (esperado permitido e negado). Se a decisão não recebe a empresa, basta '
             || 'um vínculo amplo em QUALQUER empresa do cliente para o acesso valer em TODAS.',
             v_tem_empresa, v_em_alfa, v_em_beta);
    r.detalhe := jsonb_build_object('decisao_ve_empresa', v_tem_empresa, 'alfa', v_em_alfa, 'beta', v_em_beta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- VIN-006 — permissão de uma empresa não vaza para a outra.
CREATE OR REPLACE FUNCTION public.qa_caso_vin_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_vaza boolean; v_na_alfa boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('VIN-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário com acesso amplo a documentos SÓ na Alfa e restrito na Beta';
  r.esperado    := 'No contexto da Beta, o acesso amplo concedido na Alfa NÃO vale';

  v_u  := public.qa_up_usuario('VIN-006', 1, '99900002474', 'ativo');
  v_pa := public.qa_up_perfil('VIN-006', 'Amplo Alfa', 'documentos', 'empresa_inteira');
  v_pb := public.qa_up_perfil('VIN-006', 'Restrito Beta', 'documentos', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  PERFORM public.qa_up_entrar(v_uid);

  r.passo_ordem := 2;
  r.passo_acao  := 'Controle: na Alfa, o acesso amplo vale';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Alfa'));
  v_na_alfa := public.perfil_permite_modulo(v_t, 'documentos');

  r.passo_ordem := 3;
  r.passo_acao  := 'Estando na Beta, pedir o acesso amplo que só a Alfa libera';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Beta'));
  v_vaza := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_na_alfa IS TRUE AND v_vaza IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'O acesso amplo concedido na Alfa valeu na Alfa e não valeu na Beta: a permissão não vaza '
             || 'entre vínculos.';
  ELSIF v_na_alfa IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'Controle inicial falhou: o acesso amplo não valeu nem na própria Alfa, onde foi concedido. '
             || 'Antes de acusar vazamento é preciso que o acesso legítimo funcione.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'PERMISSÃO VAZA ENTRE EMPRESAS: o acesso amplo a documentos foi concedido apenas no vínculo '
             || 'com a Alfa e valeu também na Beta. Em documentos moram atestados e dado de saúde '
             || '(LGPD art. 11).';
    r.detalhe := jsonb_build_object('usuario_id', v_u);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CTX-003 — o nível muda junto com o contexto, também no backend.
CREATE OR REPLACE FUNCTION public.qa_caso_ctx_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_em_alfa boolean; v_em_beta boolean; v_tem_ctx boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('CTX-003');

  r.passo_ordem := 1;
  r.passo_acao  := 'Admin na Alfa e Colaborador na Beta; executar a ação de admin em cada contexto';
  r.esperado    := 'Permitido no contexto da Alfa e negado no da Beta';

  v_u  := public.qa_up_usuario('CTX-003', 1, '99900002555', 'ativo');
  v_pa := public.qa_up_perfil('CTX-003', 'Admin Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('CTX-003', 'Colab Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  v_tem_ctx := public.qa_up_tem_empresa_ativa();

  r.passo_ordem := 2;
  r.passo_acao  := 'Selecionar a Alfa e pedir a decisão';
  PERFORM public.qa_up_entrar(v_uid);
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Alfa'));
  v_em_alfa := public.perfil_permite_modulo(v_t, 'ponto');

  r.passo_ordem := 3;
  r.passo_acao  := 'Trocar o seletor para a Beta e pedir a mesma decisão';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Beta'));
  v_em_beta := public.perfil_permite_modulo(v_t, 'ponto');
  PERFORM public.qa_up_sair();

  IF v_tem_ctx AND v_em_alfa IS TRUE AND v_em_beta IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A decisão acompanhou a empresa ativa: permitida na Alfa, negada na Beta. A troca de contexto '
             || 'muda o que a tela mostra E o que o banco entrega.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('A DECISÃO NÃO ACOMPANHOU O CONTEXTO: consulta a empresa ativa=%s; respondeu %s na Alfa '
             || 'e %s na Beta. A premissa P5 do documento (a sessão carrega a empresa ativa e o papel dela) '
             || 'não se sustenta.', v_tem_ctx, v_em_alfa, v_em_beta);
    r.detalhe := jsonb_build_object('decisao_ve_empresa', v_tem_ctx, 'alfa', v_em_alfa, 'beta', v_em_beta);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- CTX-006 — pertencer a B não basta enquanto o contexto for A.
CREATE OR REPLACE FUNCTION public.qa_caso_ctx_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_no_contexto_a boolean; v_apos_trocar boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('CTX-006');

  r.passo_ordem := 1;
  r.passo_acao  := 'Usuário vinculado a Alfa e Beta; só o vínculo da Beta libera o módulo';
  r.esperado    := 'Com contexto na Alfa, negado; depois de trocar para a Beta, permitido';

  v_u  := public.qa_up_usuario('CTX-006', 1, '99900002636', 'ativo');
  v_pa := public.qa_up_perfil('CTX-006', 'Alfa sem SST', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('CTX-006', 'Beta com SST', 'sst',   'empresa_inteira');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  r.passo_ordem := 2;
  r.passo_acao  := 'Com contexto na Alfa, alcançar o que só a Beta libera';
  PERFORM public.qa_up_entrar(v_uid);
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Alfa'));
  v_no_contexto_a := public.perfil_permite_modulo(v_t, 'sst');

  r.passo_ordem := 3;
  r.passo_acao  := 'Trocar o contexto para a Beta e tentar de novo';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Beta'));
  v_apos_trocar := public.perfil_permite_modulo(v_t, 'sst');
  PERFORM public.qa_up_sair();

  IF v_no_contexto_a IS FALSE AND v_apos_trocar IS TRUE THEN
    r.situacao := 'passou';
    r.obtido := 'Negado no contexto da Alfa e permitido depois de trocar para a Beta: pertencer não basta, '
             || 'é preciso estar.';
  ELSIF v_no_contexto_a IS TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'PERTENCER BASTA: o que só o vínculo da Beta libera foi alcançado com o contexto na Alfa. '
             || 'O acesso vale pela UNIÃO dos vínculos, não pela empresa em que a pessoa está — para quem '
             || 'tem vínculo com várias empresas do mesmo cliente, não existe fronteira entre elas.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'A TROCA DE CONTEXTO NÃO ABRIU O QUE DEVIA: depois de trocar para a Beta, o módulo que o '
             || 'vínculo dela libera continuou negado. Recortar por empresa não pode fechar o acesso legítimo.';
    r.detalhe := jsonb_build_object('no_contexto_alfa', v_no_contexto_a, 'apos_trocar', v_apos_trocar);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- LIB-002 — a liberação vale só na empresa em que foi concedida.
CREATE OR REPLACE FUNCTION public.qa_caso_lib_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_t uuid := public.qa_sandbox_tenant_id();
  v_u uuid; v_uid uuid; v_pa uuid; v_pb uuid; v_na_alfa boolean; v_na_beta boolean;
BEGIN
  PERFORM public.qa_fixture_limpar('LIB-002');

  r.passo_ordem := 1;
  r.passo_acao  := 'X vinculado a Alfa e Beta; liberação de documentos concedida SÓ na Alfa';
  r.esperado    := 'Vale na Alfa e é negada na Beta';

  v_u  := public.qa_up_usuario('LIB-002', 1, '99900002040', 'ativo');
  v_pa := public.qa_up_perfil('LIB-002', 'Alfa', 'ponto', 'empresa_inteira');
  v_pb := public.qa_up_perfil('LIB-002', 'Beta', 'ponto', 'proprio_usuario');
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Alfa'), v_pa);
  PERFORM public.qa_up_vincular(v_u, public.qa_empresa('[QA] Beta'), v_pb);
  SELECT auth_user_id INTO v_uid FROM public.usuarios_base WHERE id = v_u;

  INSERT INTO public.perfil_excecoes
    (tenant_id, usuario_id, empresa_id, tipo, modulo, acao, escopo, ativo, justificativa)
  VALUES (v_t, v_u, public.qa_empresa('[QA] Alfa'), 'adicional', 'documentos',
          'visualizar', 'empresa_inteira', true, 'Liberação só na Alfa — caso LIB-002.');

  r.passo_ordem := 2;
  r.passo_acao  := 'Controle: na Alfa, a liberação vale';
  PERFORM public.qa_up_entrar(v_uid);
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Alfa'));
  v_na_alfa := public.perfil_permite_modulo(v_t, 'documentos');

  r.passo_ordem := 3;
  r.passo_acao  := 'Na Beta, tentar usar o recurso liberado na Alfa';
  PERFORM public.definir_empresa_ativa(public.qa_empresa('[QA] Beta'));
  v_na_beta := public.perfil_permite_modulo(v_t, 'documentos');
  PERFORM public.qa_up_sair();

  IF v_na_alfa IS TRUE AND v_na_beta IS FALSE THEN
    r.situacao := 'passou';
    r.obtido := 'A liberação dada na Alfa valeu na Alfa e não valeu na Beta: ela não vaza entre vínculos.';
  ELSIF v_na_alfa IS NOT TRUE THEN
    r.situacao := 'falhou';
    r.obtido := 'Controle inicial falhou: a liberação não valeu nem na Alfa, onde foi concedida. Sem a '
             || 'concessão funcionando, o escopo por empresa não tem o que delimitar.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'LIBERAÇÃO VAZA ENTRE EMPRESAS: concedida apenas na Alfa, valeu também na Beta.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- O QUE CONTINUA DE FORA, E POR QUÊ
--
-- · PER-006 (verbos não separados). A coluna perfil_permissoes.acao guarda o
--   verbo, mas a camada restritiva de perfil é TODA "FOR SELECT": ela decide
--   quem LÊ, e não existe camada equivalente para escrita. Separar os verbos
--   de verdade significa CRIAR políticas restritivas de INSERT/UPDATE/DELETE
--   nas 11 tabelas sensíveis — uma superfície de enforcement nova, com risco
--   real de barrar gravação legítima. Não cabe de carona nesta entrega: é a
--   próxima, com medição própria.
--   E não adianta criar a função que recebe a ação sem ligar os chamadores a
--   ela: o caso de teste ficaria verde com o sistema idêntico.
--
-- · ISOL-005 (6 tabelas de faturamento com isolamento ligado e sem política)
--   e ISOL-007 (auditoria da leitura cross-tenant do superadmin) seguem como
--   estavam — o primeiro é de outro módulo, o segundo é projeto próprio.
-- ═════════════════════════════════════════════════════════
