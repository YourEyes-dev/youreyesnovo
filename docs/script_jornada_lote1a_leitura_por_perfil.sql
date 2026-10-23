-- ============================================================================
-- ENTREGA — Jornada LOTE 1a: leitura por pessoa nas tabelas de ponto/jornada
--
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). UMA transacao, idempotente.
-- So politicas de leitura (RESTRICTIVE): nenhum dado e alterado e nenhuma tabela e criada
-- (o auxiliar de RLS automatico do editor nao entra). Cada tabela e atomica: se uma falhar, so ela
-- fica de fora e o aviso diz qual. Termina com UMA conferencia SELECT.
--
-- Efeito esperado: colaborador comum passa a ler so a PROPRIA jornada (pelo CPF); quem tem Ponto/
-- Colaboradores em escopo amplo (ou, em Analise de Jornada, o modulo analise_jornada) segue vendo tudo;
-- lider com escopo "subordinados diretos" ve a propria e a dos subordinados; sem perfil vinculado o
-- papel de gestao segue vendo tudo (legado). Rode ANTES a consulta de impacto e a bateria do Ponto depois.
-- Para DESFAZER uma tabela:  DROP POLICY perfil_restringe_leitura_<tabela> ON public.<tabela>;
-- ============================================================================

SET lock_timeout = '10s';

DO $jor$
DECLARE
  r record;
  c_cpf CONSTANT text := $c$regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g')$c$;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ponto_semanal',                  ARRAY['ponto','colaboradores']),
      ('ponto_banco_horas',              ARRAY['ponto','colaboradores']),
      ('ponto_banco_horas_movimentacoes',ARRAY['ponto','colaboradores']),
      ('ponto_ajustes',                  ARRAY['ponto','colaboradores']),
      ('ponto_links',                    ARRAY['ponto','colaboradores']),
      ('ponto_acesso_sensivel_log',      ARRAY['ponto','colaboradores']),
      ('ponto_equalizacao_mensal',       ARRAY['ponto','colaboradores']),
      ('ponto_comprovantes',             ARRAY['ponto','colaboradores']),
      ('ponto_memoria_calculo',          ARRAY['ponto','colaboradores']),
      ('ponto_compensacao_falta',        ARRAY['ponto','colaboradores']),
      ('ponto_pre_assinalacao',          ARRAY['ponto','colaboradores']),
      ('jornada_alertas',                ARRAY['analise_jornada','ponto','colaboradores']),
      ('jornada_analises',               ARRAY['analise_jornada','ponto','colaboradores'])
    ) AS t(tabela, modulos)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Jornada 1a: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'colaborador_cpf')
         OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem colaborador_cpf/tenant_id; ficou SEM a trava.', r.tabela;
        CONTINUE;
      END IF;

      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS perfil_restringe_leitura_%1$s ON public.%1$I', r.tabela);
      EXECUTE format(
        'CREATE POLICY perfil_restringe_leitura_%1$s ON public.%1$I AS RESTRICTIVE FOR SELECT TO authenticated '
        || 'USING (public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC %2$L::text[]) '
        || 'OR %3$s = public.cpf_do_usuario_logado() '
        || 'OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC %2$L::text[]) '
        || 'AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)))',
        r.tabela, r.modulos, c_cpf);
      RAISE NOTICE 'Jornada 1a: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de leitura: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $jor$;

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND permissive='RESTRICTIVE'
     AND policyname = 'perfil_restringe_leitura_' || tablename
     AND tablename IN ('ponto_semanal','ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_ajustes','ponto_links',
                       'ponto_acesso_sensivel_log','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
                       'ponto_compensacao_falta','ponto_pre_assinalacao','jornada_alertas','jornada_analises'))  AS tabelas_com_a_trava,
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND c.relname IN ('ponto_semanal','ponto_banco_horas','ponto_banco_horas_movimentacoes','ponto_ajustes','ponto_links',
                       'ponto_acesso_sensivel_log','ponto_equalizacao_mensal','ponto_comprovantes','ponto_memoria_calculo',
                       'ponto_compensacao_falta','ponto_pre_assinalacao','jornada_alertas','jornada_analises'))  AS tabelas_do_lote_que_existem;
-- Os dois numeros devem ser IGUAIS. Depois, rode a bateria do Ponto:
--   SELECT public.qa_rodar_bateria('manual', 'jornada-rotina/ponto');
--
-- Resumo da ULTIMA bateria do Ponto (rode depois da linha acima; "falhou" e "erro" precisam ser iguais ao de antes):
--   SELECT total, passou, falhou, erro, nao_implementado FROM public.qa_execucoes
--    WHERE modulo_path = 'jornada-rotina/ponto' ORDER BY iniciada_em DESC NULLS LAST LIMIT 1;
