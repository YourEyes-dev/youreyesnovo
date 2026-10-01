-- ============================================================================
-- ENTREGA — atalho de ajuste sinaliza intervalo pré-assinalado
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
--
-- ACHADO: no campo de ajuste da folha, as empresas que usam "Intervalo
-- Pré-Assinalado" viam 4 campos (2 Entradas + 2 Saídas). Nessa configuração a
-- jornada é de DUAS batidas (Entrada/Saída) — o intervalo é declarado, não
-- batido (TST Súmula 338, III · Portaria MTP 671/2021). A folha deve mostrar
-- só 1 par.
--
-- CORREÇÃO: a tela "dentro do sistema" já detecta a declaração (lê a config por
-- RLS). O ATALHO (link público) usa RPC pública sem login e não lê a config
-- direto; então a própria RPC passa a devolver a flag `pre_assinalado`,
-- calculada pelo resolver canônico public.ponto_pre_assinalacao_do_dia
-- (colaborador vence escala; vigência no dia). As duas telas então limitam a
-- folha a 1 par e preservam no registro eventuais batidas de almoço (a marcação
-- é imutável — Súmula 338).
--
-- SEGURANÇA: só substitui FUNÇÃO (não cria tabela, não altera/apaga dado).
-- Idempotente. O patch é CIRÚRGICO: parte da função que já existe no ambiente e
-- apenas INJETA a chave `pre_assinalado` no retorno — preserva qualquer outra
-- diferença local. Se a âncora não bater, apenas AVISA e segue (nunca aborta).
-- Termina com conferência.
-- ============================================================================


-- ---------------------------------------------------------------------
-- A) externo.listar_ponto_externo(text, integer) — link individual
--    v_cpf e v_link já existem no escopo do RETURN; injeta a flag.
-- ---------------------------------------------------------------------
DO $patchA$
DECLARE
  v_oid oid := to_regprocedure('externo.listar_ponto_externo(text, integer)');
  v_src text;
  v_new text;
BEGIN
  IF v_oid IS NULL THEN
    RAISE NOTICE '[A] externo.listar_ponto_externo(text,integer) nao existe — pulado.';
    RETURN;
  END IF;
  v_src := pg_get_functiondef(v_oid);
  IF position('''pre_assinalado''' IN v_src) > 0 THEN
    RAISE NOTICE '[A] ja tem pre_assinalado — nada a fazer.';
    RETURN;
  END IF;
  IF position('''success'', true,' IN v_src) = 0 THEN
    RAISE NOTICE '[A] ancora "success, true," nao encontrada — pulado (confira manualmente).';
    RETURN;
  END IF;
  v_new := replace(
    v_src,
    '''success'', true,',
    '''success'', true,' || E'\n    ''pre_assinalado'', EXISTS (SELECT 1 FROM public.ponto_pre_assinalacao_do_dia(v_link.tenant_id, v_cpf, v_link.colaborador_id::text, CURRENT_DATE) WHERE aplica),'
  );
  EXECUTE v_new;
  RAISE NOTICE '[A] externo.listar_ponto_externo atualizada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[A] falhou: %', SQLERRM;
END $patchA$;


-- ---------------------------------------------------------------------
-- B) externo.listar_ponto_externo_cpf(text, text, integer) — link compartilhado
--    v_cpf e v_colab já existem no escopo do RETURN; injeta a flag.
-- ---------------------------------------------------------------------
DO $patchB$
DECLARE
  v_oid oid := to_regprocedure('externo.listar_ponto_externo_cpf(text, text, integer)');
  v_src text;
  v_new text;
BEGIN
  IF v_oid IS NULL THEN
    RAISE NOTICE '[B] externo.listar_ponto_externo_cpf(text,text,integer) nao existe — pulado.';
    RETURN;
  END IF;
  v_src := pg_get_functiondef(v_oid);
  IF position('''pre_assinalado''' IN v_src) > 0 THEN
    RAISE NOTICE '[B] ja tem pre_assinalado — nada a fazer.';
    RETURN;
  END IF;
  IF position('''success'', true,' IN v_src) = 0 THEN
    RAISE NOTICE '[B] ancora "success, true," nao encontrada — pulado (confira manualmente).';
    RETURN;
  END IF;
  v_new := replace(
    v_src,
    '''success'', true,',
    '''success'', true,' || E'\n    ''pre_assinalado'', EXISTS (SELECT 1 FROM public.ponto_pre_assinalacao_do_dia(v_link.tenant_id, v_cpf, v_colab.colaborador_id::text, CURRENT_DATE) WHERE aplica),'
  );
  EXECUTE v_new;
  RAISE NOTICE '[B] externo.listar_ponto_externo_cpf atualizada.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[B] falhou: %', SQLERRM;
END $patchB$;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA (o editor mostra só o último resultado): as duas funções
-- devem conter a chave pre_assinalado agora.
-- ---------------------------------------------------------------------
SELECT
  (to_regprocedure('externo.listar_ponto_externo(text, integer)') IS NOT NULL)        AS existe_individual,
  (to_regprocedure('externo.listar_ponto_externo_cpf(text, text, integer)') IS NOT NULL) AS existe_compartilhado,
  (position('''pre_assinalado''' IN pg_get_functiondef(to_regprocedure('externo.listar_ponto_externo(text, integer)'))) > 0)            AS individual_tem_flag,
  (position('''pre_assinalado''' IN pg_get_functiondef(to_regprocedure('externo.listar_ponto_externo_cpf(text, text, integer)'))) > 0) AS compartilhado_tem_flag;
