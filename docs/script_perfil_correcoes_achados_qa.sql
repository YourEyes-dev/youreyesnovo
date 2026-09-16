-- =========================================================
-- SCRIPT DE ENTREGA — Correções dos achados do motor de QA
-- (módulo Usuários, Níveis de Acesso, Liberações e Permissões)
--
-- Onde colar: SQL Editor do projeto (homologação primeiro; produção só
-- depois do aceite). Roda o arquivo INTEIRO de uma vez.
--
-- LEIA ANTES DE APLICAR EM PRODUÇÃO — este script MUDA PERMISSÃO EFETIVA:
--   · quem não é administrador deixa de conseguir mexer em vínculo de perfil
--     e em liberação (hoje qualquer usuário interno consegue);
--   · usuário com status inativo, bloqueado, suspenso ou arquivado deixa de
--     ter acesso (hoje continua entrando enquanto o vínculo existir);
--   · liberações pontuais já gravadas PASSAM A VALER (hoje são ignoradas) —
--     a conferência no fim mostra quantas são; olhe esse número antes;
--   · 42 rotinas deixam de ser executáveis por quem não fez login. Usuário
--     logado não é afetado. A lista de exceções públicas por desenho está no
--     bloco 8, com o motivo de cada uma e o comando para desfazer item a item.
--
-- Não apaga nem altera dado de cliente: mexe em políticas, funções, índices e
-- permissões. Por isso não há cópia de segurança aqui. Para voltar atrás,
-- cada bloco diz o que recriar.
--
-- Origem: bateria do motor de QA de 20260916180000, que reprovou 23 casos.
--
-- Origem: bateria de 20260916180000, que reprovou 23 casos. Esta migration
-- corrige as causas que dá para corrigir com segurança e SEM tirar acesso de
-- quem legitimamente já o tem. O que ficou de fora está listado no fim, com
-- o motivo — nenhum achado foi esquecido em silêncio.
--
-- ORDEM DE GRAVIDADE (é também a ordem dos blocos):
--   1. Qualquer usuário interno alterava vínculos de perfil — inclusive o
--      próprio. Escalada de privilégio direta. (PRIV-001, NAC-006)
--   2. A decisão de acesso ignorava o status do usuário: desativado,
--      bloqueado e suspenso continuavam entrando. (USR-005, USR-006, SES-003)
--   3. A liberação pontual era gravada e nunca lida. (LIB-001, LIB-003, LIB-004)
--   4. Vínculo duplicado na mesma empresa. (VIN-008)
--   5. Exclusão de usuário deixava vínculo órfão. (USR-008)
--   6. E-mail sem validação de formato no banco. (USR-004)
--   7. Tabelas de cópia de segurança com dado real e sem isolamento. (ISOL-005)
--   8. Rotinas sensíveis executáveis sem login. (ISOL-006)
--
-- Idempotente. Não apaga nem altera dado de cliente: mexe em políticas,
-- funções, índices e permissões. O único bloco que poderia esbarrar em dado
-- existente (o índice de unicidade) avisa e segue, em vez de quebrar.
-- =========================================================

SET lock_timeout = '10s';

-- ═════════════════════════════════════════════════════════
-- 1) ESCALADA DE PRIVILÉGIO — quem pode mexer em vínculo de perfil
--
-- Como estava: as políticas de INSERT/UPDATE/DELETE em
-- usuario_perfil_vinculos exigiam apenas tenant_id = o meu E
-- user_has_empresa_vinculo(empresa_id). Essa segunda função devolve TRUE
-- para todo mundo que não seja de um punhado de tipos externos (clínica,
-- consultor, prestador, auditor, suporte). Na prática: QUALQUER usuário
-- interno do cliente podia trocar o perfil de qualquer pessoa — inclusive o
-- seu — por um perfil de escopo máximo. Nenhuma das políticas tinha cláusula
-- de verificação, então também dava para mover o vínculo para outro cliente.
--
-- Como fica: escrever em vínculo passa a exigir ser administrador. O
-- critério é o MESMO que o sistema já usa para decidir quem administra
-- (perfil_permite_modulo): superadmin, papel de gestão para cima, ou
-- tipo_usuario administrador/gestor. Isso é de propósito: usar a definição
-- que já existe não tira o acesso de ninguém que hoje administra de fato, e
-- fecha a porta para o colaborador comum, que é o caso da escalada.
--
-- Estreitar mais do que isso (por exemplo, exigir também que não seja
-- 'gestor') é decisão de produto, não de QA — e está anotada no fim.
-- ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.pode_gerir_acesso(p_tenant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_tenant_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_superadmin(v_uid)
     OR public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
      AND ub.tipo_usuario::text IN ('administrador', 'gestor')
      AND ub.status::text NOT IN ('inativo', 'bloqueado', 'suspenso', 'arquivado')
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.pode_gerir_acesso(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pode_gerir_acesso(uuid) TO authenticated;

COMMENT ON FUNCTION public.pode_gerir_acesso(uuid) IS
  'Quem pode CONCEDER acesso (mexer em vínculo de perfil e em liberação). Mesmo critério que o sistema já usa para reconhecer um administrador. Criada para fechar a escalada de privilégio achada em PRIV-001.';

DROP POLICY IF EXISTS insert_usuario_perfil_vinculos_vinculo ON public.usuario_perfil_vinculos;
DROP POLICY IF EXISTS update_usuario_perfil_vinculos_vinculo ON public.usuario_perfil_vinculos;
DROP POLICY IF EXISTS delete_usuario_perfil_vinculos_vinculo ON public.usuario_perfil_vinculos;

CREATE POLICY insert_usuario_perfil_vinculos_vinculo
  ON public.usuario_perfil_vinculos FOR INSERT
  WITH CHECK (tenant_id = public.get_user_tenant_id()
              AND public.user_has_empresa_vinculo(empresa_id)
              AND public.pode_gerir_acesso(tenant_id));

-- A cláusula de verificação no UPDATE é o que impede empurrar o vínculo para
-- outro cliente: sem ela, a linha sai do alcance de quem a criou.
CREATE POLICY update_usuario_perfil_vinculos_vinculo
  ON public.usuario_perfil_vinculos FOR UPDATE
  USING (tenant_id = public.get_user_tenant_id()
         AND public.user_has_empresa_vinculo(empresa_id)
         AND public.pode_gerir_acesso(tenant_id))
  WITH CHECK (tenant_id = public.get_user_tenant_id()
              AND public.pode_gerir_acesso(tenant_id));

CREATE POLICY delete_usuario_perfil_vinculos_vinculo
  ON public.usuario_perfil_vinculos FOR DELETE
  USING (tenant_id = public.get_user_tenant_id()
         AND public.user_has_empresa_vinculo(empresa_id)
         AND public.pode_gerir_acesso(tenant_id));

-- A MESMA FALHA EXISTIA NA LIBERAÇÃO (perfil_excecoes), e ela é a porta dos
-- fundos da mesma escalada: quem não consegue trocar o próprio perfil, mas
-- consegue conceder a si mesmo uma exceção, chega ao mesmo lugar.
--
-- ARMADILHA QUE ME PEGOU AQUI, e que fica registrada porque vai pegar de novo:
-- política PERMISSIVA se soma às outras com OU. Criar uma política restrita AO
-- LADO da frouxa não restringe nada — as duas valem, e basta a frouxa aprovar.
-- Para apertar de verdade é preciso SUBSTITUIR a frouxa, que é o que este
-- bloco faz. (A primeira versão desta correção só acrescentava, e o caso
-- LIB-005 continuou reprovando — foi o motor de QA que apontou.)
DO $pol$
BEGIN
  IF to_regclass('public.perfil_excecoes') IS NULL THEN
    RAISE NOTICE 'perfil_excecoes não existe neste ambiente; bloco ignorado.';
    RETURN;
  END IF;

  EXECUTE 'DROP POLICY IF EXISTS insert_perfil_excecoes_gestao ON public.perfil_excecoes';
  EXECUTE 'DROP POLICY IF EXISTS insert_perfil_excecoes_vinculo ON public.perfil_excecoes';
  EXECUTE 'DROP POLICY IF EXISTS update_perfil_excecoes_vinculo ON public.perfil_excecoes';
  EXECUTE 'DROP POLICY IF EXISTS delete_perfil_excecoes_vinculo ON public.perfil_excecoes';

  EXECUTE 'CREATE POLICY insert_perfil_excecoes_vinculo ON public.perfil_excecoes FOR INSERT
           WITH CHECK (tenant_id = public.get_user_tenant_id()
                       AND public.user_has_empresa_vinculo(empresa_id)
                       AND public.pode_gerir_acesso(tenant_id))';

  EXECUTE 'CREATE POLICY update_perfil_excecoes_vinculo ON public.perfil_excecoes FOR UPDATE
           USING (tenant_id = public.get_user_tenant_id()
                  AND public.user_has_empresa_vinculo(empresa_id)
                  AND public.pode_gerir_acesso(tenant_id))
           WITH CHECK (tenant_id = public.get_user_tenant_id()
                       AND public.pode_gerir_acesso(tenant_id))';

  EXECUTE 'CREATE POLICY delete_perfil_excecoes_vinculo ON public.perfil_excecoes FOR DELETE
           USING (tenant_id = public.get_user_tenant_id()
                  AND public.user_has_empresa_vinculo(empresa_id)
                  AND public.pode_gerir_acesso(tenant_id))';

  RAISE NOTICE 'LIB-005: escrita em perfil_excecoes passa a exigir administração.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Políticas de perfil_excecoes não aplicadas: %', SQLERRM;
END $pol$;

-- ═════════════════════════════════════════════════════════
-- 2 e 3) A DECISÃO DE ACESSO — status do usuário e liberação pontual
--
-- Duas correções na mesma função, porque é ela que decide tudo.
--
-- (2) STATUS — como estava: perfil_permite_modulo só olhava o status no ramo
-- de administrador/gestor. No ramo do perfil (o de todo mundo) não olhava.
-- Resultado: desativar, bloquear ou suspender alguém não fechava porta
-- nenhuma enquanto o vínculo existisse. Quem foi desligado continuava
-- trabalhando no sistema.
--
-- Como fica: os status TERMINAIS (inativo, bloqueado, suspenso, arquivado)
-- passam a negar acesso em qualquer ramo.
--
-- Por que NÃO exigir status = 'ativo', que seria o mais rigoroso: não existe
-- no banco nenhuma rotina que carimbe 'ativo' na aceitação do convite — o
-- caminho passa pela tela. Exigir 'ativo' hoje derrubaria gente que está
-- legitimamente dentro do sistema com status de pré-ativação. Fechar os
-- status terminais resolve o caso real (desligado continuar entrando) sem
-- esse risco. Por isso USR-001 (convidado que ainda não ativou) segue
-- vermelho de propósito — está anotado no fim.
--
-- (3) LIBERAÇÃO — como estava: perfil_excecoes era gravada pela tela e
-- NENHUMA função do banco a lia. A pessoa que liberava um recurso acreditava
-- ter liberado; no banco, nada mudava.
--
-- Como fica: a decisão passa a somar as liberações ATIVAS e DENTRO DA
-- VIGÊNCIA, do tipo 'adicional'. É aditivo: ninguém perde acesso por isso.
--
-- ATENÇÃO AO APLICAR EM PRODUÇÃO: se já existirem liberações gravadas lá,
-- elas passam a VALER a partir deste script. É o comportamento que a tela
-- sempre prometeu, mas é uma mudança real de permissão efetiva. A conferência
-- no fim deste arquivo mostra quantas liberações existem e a quem — confira
-- ANTES de aplicar em produção.
-- ═════════════════════════════════════════════════════════

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

  -- Superadmin atravessa por desenho, e só ele.
  IF public.is_superadmin(v_uid) THEN
    RETURN true;
  END IF;

  -- Status terminal fecha a porta antes de qualquer outra consideração:
  -- desligado, bloqueado ou suspenso não entra, tenha o vínculo que tiver.
  SELECT ub.status::text INTO v_status
  FROM public.usuarios_base ub
  WHERE ub.auth_user_id = v_uid AND ub.tenant_id = p_tenant_id
  LIMIT 1;

  IF v_status IN ('inativo', 'bloqueado', 'suspenso', 'arquivado') THEN
    RETURN false;
  END IF;

  IF public.has_minimum_role(v_uid, 'manager'::public.app_role) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.usuarios_base ub
    WHERE ub.auth_user_id = v_uid
      AND ub.tenant_id = p_tenant_id
      AND ub.status::text = 'ativo'
      AND ub.tipo_usuario::text IN ('administrador', 'gestor')
  ) THEN
    RETURN true;
  END IF;

  -- Perfil vinculado com permissão AMPLA no módulo.
  -- escopo é enum: a comparação é feita como texto.
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

  -- Liberação pontual: soma ao perfil, nunca subtrai. Só conta a que está
  -- ativa e dentro da vigência — é aqui que expira_em passa a valer.
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
  'O perfil de acesso do usuário logado permite acesso amplo a algum destes módulos? Nega para status terminal (inativo/bloqueado/suspenso/arquivado) e soma as liberações pontuais ativas e dentro da vigência (perfil_excecoes, tipo adicional). Superadmin, papel >= manager e tipo administrador/gestor têm acesso amplo por padrão.';

-- ═════════════════════════════════════════════════════════
-- 4) VÍNCULO DUPLICADO NA MESMA EMPRESA (VIN-008)
--
-- Como estava: nada impedia o mesmo usuário de ter dois vínculos ativos na
-- MESMA empresa, cada um com um perfil. Com dois níveis valendo ao mesmo
-- tempo, a decisão aplica a união deles — ou seja, sempre o mais permissivo.
-- Rebaixar alguém deixa de funcionar se o vínculo antigo continuar lá.
--
-- O índice é parcial (só vínculos ativos) porque desvincular, no sistema, é
-- marcar ativo = false: o histórico fica, e um vínculo encerrado não pode
-- bloquear um novo. empresa_id entra com COALESCE porque o vínculo de perfil
-- padrão nasce sem empresa, e dois desses também não podem coexistir.
--
-- Se já houver duplicados na base, a criação do índice falha. Nesse caso
-- AVISAMOS com a contagem e seguimos: apagar ou desativar vínculo é mexer em
-- permissão de gente real e isso é decisão humana, não de migration.
-- ═════════════════════════════════════════════════════════
DO $uniq$
DECLARE v_dups int;
BEGIN
  SELECT count(*) INTO v_dups FROM (
    SELECT usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)
    FROM public.usuario_perfil_vinculos
    WHERE COALESCE(ativo, true)
    GROUP BY 1, 2 HAVING count(*) > 1
  ) d;

  IF v_dups > 0 THEN
    RAISE NOTICE 'VIN-008 NAO CORRIGIDO: existem % par(es) usuario+empresa com mais de um vinculo ativo. O indice de unicidade nao foi criado. Resolva os duplicados (decidindo qual perfil vale) e rode de novo.', v_dups;
  ELSE
    CREATE UNIQUE INDEX IF NOT EXISTS usuario_perfil_vinculos_ativo_uidx
      ON public.usuario_perfil_vinculos
         (usuario_id, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid))
      WHERE COALESCE(ativo, true);
    RAISE NOTICE 'VIN-008 corrigido: indice de unicidade criado.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'VIN-008: indice de unicidade nao criado: %', SQLERRM;
END $uniq$;

-- ═════════════════════════════════════════════════════════
-- 5) VÍNCULO ÓRFÃO APÓS EXCLUIR USUÁRIO (USR-008)
--
-- Como estava: usuario_perfil_vinculos.usuario_id não tinha chave
-- estrangeira. Excluir um cadastro deixava a permissão pendurada em ninguém.
--
-- A chave entra como NÃO VALIDADA de propósito: assim ela já vale para tudo
-- que acontecer daqui pra frente (inclusive a cascata) sem varrer a tabela
-- inteira nem travar se houver órfão antigo. A validação do passado é
-- tentada em seguida, e se houver órfão ela apenas avisa — limpar órfão é
-- apagar dado, e isso é decisão humana.
-- ═════════════════════════════════════════════════════════
DO $fk$
DECLARE v_orfaos int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'usuario_perfil_vinculos_usuario_id_fkey'
      AND conrelid = 'public.usuario_perfil_vinculos'::regclass
  ) THEN
    ALTER TABLE public.usuario_perfil_vinculos
      ADD CONSTRAINT usuario_perfil_vinculos_usuario_id_fkey
      FOREIGN KEY (usuario_id) REFERENCES public.usuarios_base(id) ON DELETE CASCADE
      NOT VALID;
    RAISE NOTICE 'USR-008: chave estrangeira criada (nao validada).';
  END IF;

  SELECT count(*) INTO v_orfaos
  FROM public.usuario_perfil_vinculos v
  WHERE NOT EXISTS (SELECT 1 FROM public.usuarios_base u WHERE u.id = v.usuario_id);

  IF v_orfaos = 0 THEN
    ALTER TABLE public.usuario_perfil_vinculos
      VALIDATE CONSTRAINT usuario_perfil_vinculos_usuario_id_fkey;
    RAISE NOTICE 'USR-008 corrigido: chave estrangeira validada.';
  ELSE
    RAISE NOTICE 'USR-008 parcial: chave criada e valendo para os novos, mas ha % vinculo(s) orfao(s) antigo(s). Decida o que fazer com eles e depois rode VALIDATE CONSTRAINT.', v_orfaos;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'USR-008: chave estrangeira nao aplicada: %', SQLERRM;
END $fk$;

-- ═════════════════════════════════════════════════════════
-- 6) E-MAIL SEM VALIDAÇÃO DE FORMATO (USR-004)
--
-- Como estava: o banco aceitava qualquer texto como e-mail principal. A
-- validação existia só na tela — e qualquer via que não passe por ela
-- (importação, rotina, chamada direta) criava usuário cujo convite nunca
-- chega a lugar nenhum.
--
-- Entra como NÃO VALIDADA: vale para todo cadastro novo e para toda alteração
-- daqui em diante, sem quebrar se houver e-mail torto antigo na base. A
-- checagem do passado é tentada em seguida e, se houver registro fora do
-- padrão, apenas avisa — corrigir e-mail de cliente é decisão humana.
-- ═════════════════════════════════════════════════════════
DO $mail$
DECLARE v_tortos int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'usuarios_base_email_formato_chk'
      AND conrelid = 'public.usuarios_base'::regclass
  ) THEN
    ALTER TABLE public.usuarios_base
      ADD CONSTRAINT usuarios_base_email_formato_chk
      CHECK (email_principal IS NULL
             OR trim(email_principal) = ''
             OR email_principal ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$')
      NOT VALID;
    RAISE NOTICE 'USR-004: regra de formato de e-mail criada (nao validada).';
  END IF;

  SELECT count(*) INTO v_tortos FROM public.usuarios_base
  WHERE email_principal IS NOT NULL AND trim(email_principal) <> ''
    AND email_principal !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$';

  IF v_tortos = 0 THEN
    ALTER TABLE public.usuarios_base VALIDATE CONSTRAINT usuarios_base_email_formato_chk;
    RAISE NOTICE 'USR-004 corrigido: regra de formato validada.';
  ELSE
    RAISE NOTICE 'USR-004 parcial: regra valendo para os novos, mas ha % e-mail(is) fora do padrao na base. Corrija-os e depois rode VALIDATE CONSTRAINT.', v_tortos;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'USR-004: regra de formato nao aplicada: %', SQLERRM;
END $mail$;

-- ═════════════════════════════════════════════════════════
-- 7) TABELAS DE CÓPIA DE SEGURANÇA SEM ISOLAMENTO (ISOL-005)
--
-- Como estava: as tabelas backup_* que os scripts de entrega criam antes de
-- alterar dado guardam linhas REAIS de cliente (com tenant_id) e nascem sem
-- isolamento nenhum. A cópia que protege contra o script errado virava, ela
-- mesma, uma cópia desprotegida do dado que salvou.
--
-- Como fica: isolamento ligado e uma política de superadmin. Elas não são
-- lidas pelo sistema — existem para o resgate manual —, então fechar para o
-- superadmin não tira função de ninguém, e tira essas cópias do alcance de
-- qualquer usuário de cliente.
--
-- Vale para as que existem hoje. Toda cópia nova nasce igualmente aberta: o
-- lugar de resolver isso de vez é o padrão dos scripts de entrega, anotado
-- no fim deste arquivo.
-- ═════════════════════════════════════════════════════════
DO $bkp$
DECLARE c record; v_n int := 0;
BEGIN
  FOR c IN
    SELECT col.table_name AS tabela
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    JOIN pg_class cl ON cl.oid = ('public.' || quote_ident(col.table_name))::regclass
    WHERE col.table_schema = 'public' AND col.column_name = 'tenant_id'
      AND t.table_type = 'BASE TABLE'
      AND col.table_name LIKE 'backup\_%'
      AND cl.relrowsecurity = false
    ORDER BY col.table_name
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', c.tabela);
      -- Nome fixo: política só precisa ser única DENTRO da tabela. Compor o
      -- nome com a tabela truncada arriscava colidir entre duas cópias de
      -- nomes parecidos — e a colisão deixaria a tabela com isolamento ligado
      -- e SEM política, que é o outro defeito que ISOL-005 acusa.
      EXECUTE format(
        'CREATE POLICY somente_superadmin ON public.%I FOR ALL USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()))',
        c.tabela);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-005: % nao protegida: %', c.tabela, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-005: % tabela(s) de copia de seguranca fechadas ao superadmin.', v_n;
END $bkp$;

-- ═════════════════════════════════════════════════════════
-- 8) ROTINAS SENSÍVEIS EXECUTÁVEIS SEM LOGIN (ISOL-006)
--
-- Como estava: 58 rotinas que tocam dado de cliente podiam ser chamadas por
-- quem não fez login — entre elas superadmin_list_all_empresas,
-- superadmin_list_tenant_users, ler_cid_clinico (dado de saúde, LGPD art. 11)
-- e admissao_expurgar_reprovadas, que apaga.
--
-- Como fica: tira-se a permissão do papel anônimo. Tirar do ANÔNIMO não
-- afeta usuário logado — quem entrou no sistema usa outro papel.
--
-- ATENÇÃO A UMA ARMADILHA QUE CUSTOU UMA RODADA AQUI: no PostgreSQL, toda
-- função nasce com EXECUTE concedido a PUBLIC. "REVOKE ... FROM anon" não
-- tira nada quando a permissão vem por PUBLIC — o comando passa sem erro e a
-- rotina continua aberta. É preciso revogar de PUBLIC (e de anon) e então
-- devolver explicitamente a quem deve ter: o usuário logado e o papel de
-- serviço que as edge functions usam.
--
-- A lista de exceções abaixo é o cuidado que impede este bloco de derrubar
-- o que é público POR DESENHO. Ela é uma lista de PERMITIDOS, não de
-- proibidos: rotina nova nasce fechada ao anônimo, que é o lado seguro do
-- erro. Cada exceção tem motivo:
--   · *_by_token ......... admissão pelo link que o candidato recebe; ele não
--                          tem login, é esse o fluxo;
--   · parceiro_* ......... portal do parceiro, de acesso público;
--   · validar_cpf_colaborador_campanha .. formulário público de campanha;
--   · helpers de identidade .. get_user_tenant_id, current_user_tenant_id,
--                          user_tenant_ids, has_tenant_access,
--                          user_has_empresa_vinculo, get_current_user_tipo e
--                          user_can_access_storage_object são chamados DE
--                          DENTRO das próprias políticas de isolamento. A
--                          política roda com o papel de quem consulta: tirar
--                          a permissão do anônimo faria QUEBRAR toda consulta
--                          anônima legítima, em vez de protegê-la.
--
-- Para desfazer um item, se algum fluxo público inesperado depender dele:
--   GRANT EXECUTE ON FUNCTION public.<rotina>(<tipos>) TO anon;
-- ═════════════════════════════════════════════════════════
DO $anon$
DECLARE
  c record; v_n int := 0; v_lista text := '';
  v_permitidos CONSTANT text[] := ARRAY[
    'get_admissao_by_token', 'get_admissao_documentos_by_token',
    'update_admissao_documento_by_token', 'update_admissao_foto_by_token',
    'finalizar_admissao_by_token', 'ensure_admissao_documentos_by_token',
    'parceiro_meu_portal', 'parceiro_estagio_tenant',
    'validar_cpf_colaborador_campanha',
    'get_user_tenant_id', 'current_user_tenant_id', 'user_tenant_ids',
    'has_tenant_access', 'user_has_empresa_vinculo', 'get_current_user_tipo',
    'user_can_access_storage_object'
  ];
BEGIN
  FOR c IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND NOT (p.proname = ANY (v_permitidos))
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
    ORDER BY p.proname
  LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon', c.proname, c.args);
      -- Devolve a quem deve ter: sem isto, revogar de PUBLIC fecharia também
      -- para o usuário logado e para as edge functions.
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role', c.proname, c.args);
      v_n := v_n + 1;
      v_lista := v_lista || CASE WHEN v_lista = '' THEN '' ELSE ', ' END || c.proname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ISOL-006: nao foi possivel fechar %: %', c.proname, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'ISOL-006: % rotina(s) fechadas ao anonimo: %', v_n, v_lista;
END $anon$;


-- ═════════════════════════════════════════════════════════
-- 9) A ROTINA DE QA ISOL-006 PASSA A RECONHECER O QUE É PÚBLICO POR DESENHO
--
-- Com o bloco 8 aplicado, sobram abertas ao anônimo só as rotinas que PRECISAM
-- estar: a admissão pelo link do candidato, o portal do parceiro, o formulário
-- público de campanha e os helpers que as próprias políticas de isolamento
-- chamam. A rotina de QA não sabia disso e continuaria acusando — um vermelho
-- que nunca fecharia e que, de tanto aparecer, deixaria de ser lido.
--
-- A lista de exceções mora DENTRO da rotina de propósito: assim toda exceção
-- fica visível para quem abre o caso, com o motivo ao lado, e rotina nova NÃO
-- entra sozinha — ela aparece como achado até alguém decidir, por escrito, que
-- é pública. É a mesma disciplina de PERFIL-003.
--
-- Por que aqui e não editando a migration de 20260916180000: aquela já foi
-- aplicada, e o CLI indexa migration pelo carimbo — editar o arquivo depois
-- não reaplica nada. Correção de função vem sempre sob carimbo novo.
-- ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.qa_caso_isol_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE
  r public.qa_retorno;
  v_anon int; v_lista text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): quem pode executar as rotinas que tocam dado de cliente';
  r.esperado    := 'Nenhuma rotina sensível executável por usuário ANÔNIMO';

  SELECT count(*), string_agg(x.proname, ', ' ORDER BY x.proname)
  INTO v_anon, v_lista
  FROM (
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname NOT LIKE 'qa\_%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      -- sensível = o corpo menciona alguma tabela que guarda dado de cliente
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfis_acesso|perfil_permissoes|perfil_excecoes|usuario_perfil_vinculos|profiles|admissoes|atestados)'
      -- EXCEÇÕES DOCUMENTADAS: rotinas que são públicas POR DESENHO. A lista
      -- mora aqui, dentro da própria rotina de QA, de propósito: assim toda
      -- exceção é visível para quem lê o caso, e rotina nova NÃO entra sozinha
      -- — ela aparece como achado até alguém decidir, por escrito, que é
      -- pública. É a mesma disciplina que PERFIL-003 usa.
      AND p.proname NOT IN (
        -- admissão pelo link que o candidato recebe: ele não tem login, é o fluxo
        'get_admissao_by_token', 'get_admissao_documentos_by_token',
        'update_admissao_documento_by_token', 'update_admissao_foto_by_token',
        'finalizar_admissao_by_token', 'ensure_admissao_documentos_by_token',
        -- portal do parceiro e formulário público de campanha
        'parceiro_meu_portal', 'parceiro_estagio_tenant', 'validar_cpf_colaborador_campanha',
        -- helpers chamados DE DENTRO das políticas de isolamento: a política roda
        -- com o papel de quem consulta, então fechá-los ao anônimo quebraria a
        -- consulta anônima legítima em vez de protegê-la
        'get_user_tenant_id', 'current_user_tenant_id', 'user_tenant_ids',
        'has_tenant_access', 'user_has_empresa_vinculo', 'get_current_user_tipo',
        'user_can_access_storage_object'
      )
  ) x;

  IF v_anon = 0 THEN
    r.situacao := 'passou';
    r.obtido := 'Nenhuma rotina que toca dado de cliente está aberta ao usuário anônimo, fora as que são '
             || 'públicas por desenho (admissão por link, portal do parceiro, formulário de campanha e os '
             || 'helpers que as próprias políticas chamam) — essas estão listadas e justificadas no corpo '
             || 'desta rotina.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ROTINA SENSÍVEL ABERTA AO ANÔNIMO: %s rotina(s) que tocam dado de cliente podem ser '
             || 'executadas sem nenhum login: %s. Já houve precedente disso neste produto em outro módulo. '
             || 'Rotina aberta ao anônimo não é protegida por política de linha: ela roda antes.', v_anon, v_lista);
    r.detalhe := jsonb_build_object('quantidade', v_anon, 'rotinas', v_lista);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- ═════════════════════════════════════════════════════════
-- O QUE NÃO FOI CORRIGIDO AQUI, E POR QUÊ
--
-- Nenhum destes é esquecimento. Cada um exige uma decisão que não é de QA,
-- ou um trabalho que não cabe numa migration de correção.
--
-- · VIN-005, VIN-006, CTX-003, CTX-006 — O NÍVEL NÃO É POR EMPRESA.
--   A decisão é perfil_permite_modulo(tenant, módulos): recebe o cliente, não
--   a empresa. Corrigir exige três coisas juntas: a sessão passar a carregar
--   a empresa ativa, a decisão passar a recebê-la, e as políticas restritivas
--   das 11 tabelas sensíveis (mais as telas) passarem a informá-la. É mudança
--   de arquitetura do controle de acesso, com risco real de tirar acesso de
--   quem trabalha em várias empresas do mesmo cliente. Precisa de decisão do
--   dono do produto e de uma entrega própria, medida antes e depois.
--
-- · PER-006 — VERBOS NÃO SEPARADOS. A coluna perfil_permissoes.acao guarda o
--   verbo, mas a decisão não o recebe. Criar agora uma função que separa o
--   verbo SEM ligar os chamadores a ela deixaria o caso de teste verde com o
--   sistema idêntico — conforto sem prova, que é pior do que o vermelho
--   honesto. Ligar os chamadores é a mesma entrega do item acima.
--
-- · USR-001 — CONVIDADO QUE AINDA NÃO ATIVOU. Só se fecha exigindo
--   status = 'ativo', e hoje nenhuma rotina do banco carimba 'ativo' na
--   aceitação do convite. Exigir isso agora derrubaria quem está legitimamente
--   dentro com status de pré-ativação. O caminho certo é primeiro garantir o
--   carimbo na ativação e só então fechar — nesta ordem, não na inversa.
--
-- · ISOL-007 — LEITURA DO SUPERADMIN NÃO É AUDITADA. Mudanças de perfil já
--   deixam rastro; a travessia de leitura entre clientes, não. Registrar
--   leitura exige desenhar onde e como (por rotina? por política? com que
--   retenção, já que é dado sensível?) — é projeto, não ajuste.
--
-- · ISOL-008 — 9 ROTINAS COM PRIVILÉGIO DO DONO SEM FILTRO DE CLIENTE.
--   Cada uma precisa ser lida individualmente para saber se o filtro está
--   ausente ou se vem por outro caminho. Corrigir no atacado é como o motor
--   de QA erraria: mexer no que não entendeu.
--
-- · ROTINA NOVA CONTINUA NASCENDO ABERTA AO ANÔNIMO. Este arquivo fecha as
--   que existem hoje. Fechar o PADRÃO (ALTER DEFAULT PRIVILEGES) resolveria de
--   vez, mas passaria a exigir que toda função nova conceda permissão
--   explicitamente — e uma que esquecesse quebraria para o usuário logado, em
--   produção, sem aviso. Não é mudança para entrar de carona numa correção:
--   merece ser combinada com quem escreve migrations aqui.
--
-- · O PADRÃO DAS CÓPIAS DE SEGURANÇA. Este arquivo fecha as 10 tabelas
--   backup_* que existem hoje; a próxima nasce aberta de novo. O lugar de
--   resolver de vez é a regra dos scripts de entrega em CLAUDE.md, para que
--   toda cópia já nasça com isolamento — mudança de processo, não de banco.
-- ═════════════════════════════════════════════════════════

-- =========================================================
-- CONFERÊNCIA
-- Esperado depois desta migration: escalada fechada (o primeiro número tem
-- que ser 3), status terminal negando, liberação sendo lida, e zero tabela
-- sensível exposta.
-- IMPORTANTE: liberacoes_que_passam_a_valer mostra quantas liberações já
-- gravadas passam a conceder acesso de verdade a partir de agora. Confira
-- esse número ANTES de aplicar em produção.
-- =========================================================
WITH pol AS MATERIALIZED (
  SELECT count(*) AS n FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'usuario_perfil_vinculos'
    AND cmd IN ('INSERT','UPDATE','DELETE')
    AND COALESCE(qual, '') || COALESCE(with_check, '') ILIKE '%pode_gerir_acesso%'
),
expostas AS MATERIALIZED (
  SELECT count(*) AS n
  FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  JOIN pg_class cl ON cl.oid = ('public.' || quote_ident(c.table_name))::regclass
  WHERE c.table_schema = 'public' AND c.column_name = 'tenant_id'
    AND t.table_type = 'BASE TABLE' AND c.table_name NOT LIKE 'qa\_%'
    AND cl.relrowsecurity = false
)
SELECT
  (SELECT n FROM pol)                                                     AS politicas_de_vinculo_protegidas,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ILIKE '%perfil_excecoes%')            AS decisao_le_liberacoes,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'perfil_permite_modulo'
      AND pg_get_functiondef(p.oid) ILIKE '%bloqueado%')                  AS decisao_nega_status_terminal,
  (SELECT n FROM expostas)                                                AS tabelas_sensiveis_expostas,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname NOT LIKE 'qa\_%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      -- fora da conta os helpers que as próprias políticas chamam: eles
      -- PRECISAM continuar acessíveis ao anônimo, senão a consulta anônima
      -- legítima quebra em vez de ser protegida.
      AND p.proname NOT IN ('get_user_tenant_id','current_user_tenant_id','user_tenant_ids',
                            'has_tenant_access','user_has_empresa_vinculo','get_current_user_tipo',
                            'user_can_access_storage_object')
      AND pg_get_functiondef(p.oid) ~* '(usuarios_base|perfil_excecoes|usuario_perfil_vinculos|atestados)')
                                                                          AS rotinas_sensiveis_no_anonimo,
  (SELECT count(*) FROM public.perfil_excecoes
    WHERE COALESCE(ativo, true) AND COALESCE(tipo, 'adicional') = 'adicional'
      AND (expira_em IS NULL OR expira_em > now()))                       AS liberacoes_que_passam_a_valer;
