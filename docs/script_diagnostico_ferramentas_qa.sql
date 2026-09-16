-- ============================================================================
-- DIAGNOSTICO — ferramentas do motor de QA ausentes no ambiente
--
-- POR QUE EXISTE
-- A parte 1 da trilha da bancada cria as 79 ferramentas do motor (helpers
-- usados pelas rotinas: cercado, CPF ficticio, fixtures, executor). Cada uma
-- entra em bloco proprio: se uma falhar, vira aviso e o arquivo segue. A
-- conferencia da parte 1 conta quantas existem no fim — quando o numero vem
-- abaixo de 79, este diagnostico diz QUAIS faltaram, para reaplicar so elas.
--
-- COMO USAR
-- Cole no SQL Editor do MESMO ambiente onde a parte 1 rodou. Se a lista vier
-- vazia, esta tudo no lugar. Se vier com nomes, procure cada um na parte 1 do
-- arquivo docs/script_qa_bancada_parte01_base.sql e rode o bloco DO
-- correspondente sozinho — o erro aparece na mensagem, sem o aviso se perder
-- no meio da corrida inteira.
--
-- AUSENCIAS ESPERADAS FORA DO AMBIENTE DE TESTE
-- Duas ferramentas so existem onde roda a suite de tela (Cypress), porque
-- leem a grade de horarios do agendamento dela (tabela
-- qa_agendamento_e2e_dias, criada pela mudanca 20260814120000, que a
-- producao e a homologacao nao receberam):
--
--   qa_agendamento_e2e_ler_dias
--   qa_agendamento_e2e_proxima
--
-- Se a lista trouxer SO esses dois nomes, esta certo: elas nao participam de
-- nenhuma bateria do motor e a bancada funciona inteira sem elas. Ter a grade
-- fora do ambiente de teste seria pior — outro ambiente poderia disparar a
-- suite de tela do teste. A conferencia da parte 1 fecha em 77 de 79 nesse
-- caso, e isso e o esperado.
--
-- Somente leitura: nao cria, nao altera e nao apaga nada.
-- ============================================================================

-- Quais ferramentas do motor de QA nao existem neste ambiente
WITH esperadas(nome) AS MATERIALIZED (
  SELECT unnest(ARRAY[
    'qa_afast_legado',
    'qa_afast_novo',
    'qa_afast_tipado',
    'qa_agendamento_e2e_ler_dias',
    'qa_agendamento_e2e_proxima',
    'qa_agendamento_e2e_salvar_dia',
    'qa_agendamento_ler',
    'qa_agendamento_ler_dias',
    'qa_agendamento_proxima',
    'qa_agendamento_salvar',
    'qa_agendamento_salvar_dia',
    'qa_anexar_print_e2e',
    'qa_assert_sandbox',
    'qa_bloqueia_fora_do_cercado',
    'qa_caso_detalhe',
    'qa_cercas_faltando',
    'qa_col_existe',
    'qa_coluna_existe',
    'qa_conferir_seguranca',
    'qa_cpf',
    'qa_cpf_formatado',
    'qa_cron_sincronizar',
    'qa_cron_sincronizar_e2e',
    'qa_dia_util_passado',
    'qa_disparar_bateria',
    'qa_e2e_disparar_esteira',
    'qa_empresa',
    'qa_empresa_com_cota',
    'qa_empresa_com_ponto',
    'qa_executar_descartavel',
    'qa_exigir_modo',
    'qa_feriado_da_unidade',
    'qa_ferias_periodo',
    'qa_fixture_email',
    'qa_fixture_limpar',
    'qa_fns_com',
    'qa_houve_vazamento',
    'qa_instalar_cercas',
    'qa_limpa_config_metas',
    'qa_limpa_identidade',
    'qa_limpar_historico',
    'qa_listar_baterias',
    'qa_mobiliario_registrar',
    'qa_modo_ligado',
    'qa_modo_ligar',
    'qa_modulos_testaveis',
    'qa_nova_acao',
    'qa_nova_competencia',
    'qa_nova_condicao',
    'qa_nova_empresa',
    'qa_nova_empresa_pf',
    'qa_nova_meta',
    'qa_nova_obrigacao',
    'qa_nova_pasta',
    'qa_nova_swot',
    'qa_nova_tabela_feriados',
    'qa_novo_doc_terceiro',
    'qa_novo_documento',
    'qa_novo_hub_processo',
    'qa_novo_no_org',
    'qa_novo_oceano',
    'qa_novo_terceiro',
    'qa_obrigacao_existe',
    'qa_ponto_admissao',
    'qa_ponto_dia',
    'qa_ponto_dia_horarios',
    'qa_ponto_dia_min',
    'qa_ponto_escala_tol',
    'qa_ponto_marca',
    'qa_registrar_bateria_e2e',
    'qa_relatorio_falhas',
    'qa_resultados_da_bateria',
    'qa_rodar_agendada',
    'qa_rodar_bateria',
    'qa_sandbox2_tenant_id',
    'qa_sandbox_tenant_id',
    'qa_um_usuario',
    'qa_verifica_contaminacao',
    'qa_verifica_vazamento'
  ])
)
SELECT e.nome AS ferramenta_ausente
FROM esperadas e
WHERE to_regprocedure('public.' || e.nome || '()') IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = e.nome
  )
ORDER BY 1;
