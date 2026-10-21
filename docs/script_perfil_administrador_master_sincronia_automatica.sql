-- ============================================================================
-- ENTREGA — Administrador Master (parte 4): sincronia automatica com o plano
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO (depois das partes 1 a 3).
-- ============================================================================

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


-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname = 'admin_master_sincronizar')              AS funcao_criada_esperado_1,
  (SELECT count(*) FROM cron.job WHERE jobname = 'admin-master-sincronizar')             AS agendada_esperado_1,
  (SELECT count(*) FROM public.admin_master_verbos_faltantes())                          AS verbos_faltando,
  (CASE WHEN has_function_privilege('authenticated', 'public.admin_master_sincronizar()', 'EXECUTE')
        THEN 'ATENCAO: aberta para usuarios' ELSE 'ok' END)                              AS erro_tecnico;

-- ── DESFAZER (so se precisar; rode em separado) ─────────────────────────────
--    SELECT cron.unschedule('admin-master-sincronizar');
--    -- as linhas acrescentadas pela rotina levam a marca na observacao:
--    DELETE FROM public.perfil_permissoes WHERE observacao = 'Sincronizado automaticamente (Administrador Master)';
