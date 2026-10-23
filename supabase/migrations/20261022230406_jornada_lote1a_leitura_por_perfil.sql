-- ============================================================================
-- JORNADA — LOTE 1a: leitura por pessoa nas tabelas de ponto/jornada (LGPD arts. 6 e 46)
--
-- Levantamento de 10/2026 (consulta C): 13 tabelas de jornada tinham CPF do colaborador e eram
-- legiveis por QUALQUER membro da empresa (so o tenant). Provado em teste: um usuario so com
-- Documentos leu o cadastro e as admissoes inteiras. Aqui as tabelas de jornada ganham o MESMO
-- portao ja usado em ponto_marcacoes e ponto_espelhos desde a PONTO-396 / subordinados diretos:
--
--   perfil com Ponto/Colaboradores em escopo AMPLO   ->  ve todas
--   a linha e do proprio usuario (pelo CPF)          ->  ve a sua
--   perfil com escopo SUBORDINADOS e a linha e de um
--   subordinado direto                               ->  ve a do subordinado
--   sem perfil vinculado: papel de gestao ve tudo (legado, como em ponto_marcacoes)
--
-- Tabelas: ponto_semanal, ponto_banco_horas, ponto_banco_horas_movimentacoes, ponto_ajustes,
--   ponto_links, ponto_acesso_sensivel_log, ponto_equalizacao_mensal, ponto_comprovantes,
--   ponto_memoria_calculo, ponto_compensacao_falta, ponto_pre_assinalacao (modulos ponto e
--   colaboradores) e jornada_alertas, jornada_analises (acrescenta analise_jornada).
--
-- FICA DE FORA (lote 1b, exige revisar funcoes que rodam com o direito de quem chama):
--   ponto_alertas, ponto_escala_atribuicoes, ponto_troca_turno, ponto_acordos e ponto_lotacao_historico.
-- FICA DE FORA DE PROPOSITO: ponto_diario (leitura agregada por outros modulos, PONTO-396).
--
-- Conferido: nenhuma funcao do sistema SEM security definer le estas 13 tabelas (so rotinas de QA,
-- que rodam como o dono do banco); as funcoes de borda e a batida por link usam a chave de servico ou
-- funcoes security definer. Nenhuma politica de escrita e alterada; nenhum dado e alterado.
-- Atomico por tabela: se uma falhar, so ela fica de fora e o aviso diz qual.
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
