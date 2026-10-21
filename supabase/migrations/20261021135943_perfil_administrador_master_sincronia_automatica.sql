-- Administrador Master (parte 4): sincronia automatica com o plano.
--
-- Decisao do dono do produto (21/10/2026): o Administrador Master ve e movimenta tudo da empresa nos
-- modulos que o plano libera. As partes 1 a 3 acertaram o que ja existia; esta parte faz o acerto
-- se repetir sozinho para perfil novo, modulo novo e plano que cresce.
--
-- admin_master_sincronizar(): acrescenta, para cada Administrador Master em uso, os verbos que NAO
-- tem NENHUMA linha (ativa ou desligada) nos modulos que o plano libera. Diferente da parte 3, NAO
-- religa verbo desligado: se alguem desligou de proposito pela tela de perfis, a sincronia respeita.
-- Roda de hora em hora (pg_cron) e pode ser chamada a mao. So le o plano e so grava em
-- perfil_permissoes; cliente sem assinatura viva fica de fora (regra de admin_master_modulos_plano).
-- Idempotente.

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.admin_master_sincronizar()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $ams$
DECLARE
  v_marca text := 'Sincronizado automaticamente (Administrador Master)';
  v_novos int := 0;
BEGIN
  IF to_regprocedure('public.admin_master_modulos_plano()') IS NULL THEN
    RAISE NOTICE 'admin_master_modulos_plano ausente; nada sincronizado';
    RETURN 0;
  END IF;

  INSERT INTO public.perfil_permissoes
    (perfil_id, tenant_id, modulo, acao, escopo, ativo, is_sensivel, observacao)
  SELECT p.perfil_id, p.tenant_id, p.modulo, v.acao::public.perfil_acao,
         'empresa_inteira'::public.perfil_escopo_tipo, true,
         (v.acao IN ('administrar', 'acessar_sensivel', 'ver_individual')), v_marca
    FROM public.admin_master_modulos_plano() p
   CROSS JOIN (VALUES ('visualizar'), ('criar'), ('editar'), ('excluir'), ('inativar'),
                      ('exportar'), ('importar'), ('aprovar'), ('assinar'), ('compartilhar'),
                      ('parametrizar'), ('administrar'), ('acessar_sensivel'),
                      ('acessar_anonimizado'), ('ver_indicadores'), ('ver_individual')) AS v(acao)
   WHERE NOT EXISTS (SELECT 1 FROM public.perfil_permissoes x
                      WHERE x.perfil_id = p.perfil_id AND x.modulo = p.modulo
                        AND x.acao::text = v.acao);
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  IF v_novos > 0 THEN
    INSERT INTO public.perfil_audit_log
      (tenant_id, perfil_id, acao, descricao, dados_novos, realizado_por_nome)
    SELECT pp.tenant_id, pp.perfil_id, 'alteracao',
           'Permissoes do Administrador Master sincronizadas com o plano (rotina automatica)',
           jsonb_build_object('linhas', count(*), 'modulos', jsonb_agg(DISTINCT pp.modulo)),
           'Sistema (sincronia automatica)'
      FROM public.perfil_permissoes pp
     WHERE pp.observacao = v_marca AND pp.created_at = now()
     GROUP BY pp.tenant_id, pp.perfil_id;
  END IF;

  RETURN v_novos;
END
$ams$;

REVOKE ALL ON FUNCTION public.admin_master_sincronizar() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_master_sincronizar() TO service_role;

-- Agenda: de hora em hora, no minuto 17 (fora do topo da hora).
DO $cron$
BEGIN
  PERFORM cron.unschedule('admin-master-sincronizar');
EXCEPTION WHEN OTHERS THEN
  NULL;  -- nao existia ainda; seguir
END $cron$;

DO $cron$
BEGIN
  PERFORM cron.schedule(
    'admin-master-sincronizar',
    '17 * * * *',
    $job$SELECT public.admin_master_sincronizar()$job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Agendamento nao pôde ser criado (%). A rotina continua chamavel a mao.', SQLERRM;
END $cron$;

-- QA — PERFIL-020 (nivel api, somente leitura): a sincronia existe, e segura e esta agendada.
CREATE OR REPLACE FUNCTION public.qa_caso_perfil_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_falhas text[] := ARRAY[]::text[];
  v_oid oid;
  v_def text;
  v_agendada boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): admin_master_sincronizar existe, nao religa verbo desligado e esta agendada';
  r.esperado    := 'Funcao SECURITY DEFINER fechada para a API, sem UPDATE, e agendada no pg_cron';

  v_oid := to_regprocedure('public.admin_master_sincronizar()');
  IF v_oid IS NULL THEN
    v_falhas := v_falhas || 'funcao admin_master_sincronizar ausente'::text;
  ELSE
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_oid) THEN
      v_falhas := v_falhas || 'nao e SECURITY DEFINER'::text;
    END IF;
    IF has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
      v_falhas := v_falhas || 'executavel por usuario autenticado (deveria ser so service_role)'::text;
    END IF;
    v_def := pg_get_functiondef(v_oid);
    IF position('UPDATE' IN upper(v_def)) > 0 THEN
      v_falhas := v_falhas || 'a sincronia passou a ter UPDATE (nao deve religar verbo desligado de proposito)'::text;
    END IF;
  END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = ''admin-master-sincronizar'')'
       INTO v_agendada;
    IF NOT v_agendada THEN
      v_falhas := v_falhas || 'sem o agendamento admin-master-sincronizar no pg_cron'::text;
    END IF;
  END IF;

  IF COALESCE(array_length(v_falhas, 1), 0) = 0 THEN
    r.situacao := 'passou';
    r.obtido   := 'Sincronia do Administrador Master presente, fechada para a API, sem religar desligados'
               || CASE WHEN to_regclass('cron.job') IS NULL THEN ' (pg_cron ausente nesta base; agenda nao conferida).'
                       ELSE ' e agendada.' END;
  ELSE
    r.situacao := 'falhou';
    r.obtido   := array_to_string(v_falhas, '; ');
    r.detalhe  := jsonb_build_object('falhas', to_jsonb(v_falhas));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

DO $amq4$
DECLARE v_mod uuid;
BEGIN
  IF to_regclass('public.qa_casos_teste') IS NULL OR to_regclass('public.qa_modulos') IS NULL THEN
    RAISE NOTICE 'Motor de QA ausente nesta base; PERFIL-020 nao documentado.';
    RETURN;
  END IF;
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'seguranca-acesso/perfis' LIMIT 1);
  IF v_mod IS NULL THEN
    RAISE NOTICE 'Modulo seguranca-acesso/perfis ausente; PERFIL-020 nao documentado.';
    RETURN;
  END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado)
  VALUES
  (v_mod, 'PERFIL-020', 'Sincronia automatica do Administrador Master com o plano esta presente e agendada',
   'feliz', 'alta', 'aprovado', 'api',
   'LGPD, art. 46 (acesso conforme a funcao)',
   'Perfil novo, modulo novo e plano que cresce nao podem deixar o Administrador Master sem acesso. A rotina admin_master_sincronizar acrescenta o que falta de hora em hora, sem religar verbo desligado de proposito, e so o service_role a executa. Os casos PERFIL-018 e PERFIL-019 acusam o que a sincronia nao cobre (por exemplo verbo desligado a mao).',
   'Entrega da sincronia automatica aplicada.',
   '[{"ordem":1,"acao":"Conferir a funcao, o fechamento para a API, a ausencia de UPDATE e o agendamento no pg_cron","resultado_esperado":"Tudo presente"}]',
   'Sincronia do Administrador Master presente, segura e agendada.')
  ON CONFLICT (codigo) DO NOTHING;

  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
    VALUES ('PERFIL-020', 'qa_caso_perfil_020', true)
    ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Documentacao PERFIL-020 nao registrada: %', SQLERRM;
END $amq4$;
