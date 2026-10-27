-- ============================================================================
-- JORNADA — LOTE 1b: leitura por perfil em alertas, escala, troca de turno, acordos e lotacao
--
-- Continuacao do lote 1a. Estas 5 tabelas ficaram de fora porque funcoes que rodam com o direito de
-- quem chama (troca de turno, atestado, monitores) leem ou gravam nelas. Conferido uma a uma:
--   - troca de turno solicitar/aprovar/recusar/efetivar: leem as atribuicoes e a troca. Com a trava, quem
--     nao enxerga a atribuicao recebe o erro "atribuicao nao encontrada" ANTES de gravar qualquer coisa
--     (falha segura, nunca troca pela metade: a efetivacao le as duas atribuicoes antes de alterar).
--   - gatilhos de atestado (sobreposicao e encaminhamento ao INSS): so INSEREM alerta; INSERT nao passa
--     pela trava de leitura. A checagem de duplicata ja trata o conflito do indice unico num bloco proprio.
--   - monitores diarios do Ponto: rodam pelo agendador (dono do banco) ou com security definer.
--   - nenhuma politica, visao ou funcao de outra tabela le estas 5 tabelas.
--
-- Regra (igual ao lote 1a): perfil com Ponto/Colaboradores em escopo AMPLO ve todas; a linha do proprio
-- usuario (CPF) e visivel; lider com escopo de subordinados ve a dele e a dos subordinados diretos;
-- sem perfil vinculado vale o legado por papel. Particularidades:
--   ponto_alertas        alertas sem CPF (da empresa: certificado, CCT, REP...) so o perfil amplo ve; o perfil
--                        amplo de Ergonomia continua vendo os 3 tipos de jornada que o painel da Ergonomia conta
--                        (excesso de jornada, intervalo suprimido, interjornada insuficiente).
--   ponto_troca_turno    vale o CPF de qualquer das duas pessoas da troca.
--   ponto_acordos        nao tem CPF (acordos e convencoes da empresa): perfil amplo ou lider de subordinados.
--
-- NAO muda politica de escrita nem dado. Lacuna conhecida e adiada para o lote de escrita: o INSERT destas
-- tabelas ainda e liberado a qualquer membro da empresa (so a leitura e fechada aqui).
-- Atomico por tabela: se uma falhar, so ela fica de fora e o aviso diz qual.
-- ============================================================================

SET lock_timeout = '10s';

DO $jor$
DECLARE
  r record;
  v_mods text;
  v_using text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ponto_alertas', 'padrao'),
      ('ponto_escala_atribuicoes', 'padrao'),
      ('ponto_lotacao_historico', 'padrao'),
      ('ponto_troca_turno',        'troca'),
      ('ponto_acordos',            'sem_cpf')
    ) AS t(tabela, modo)
  LOOP
    BEGIN
      IF to_regclass('public.' || r.tabela) IS NULL THEN
        RAISE NOTICE 'Jornada 1b: tabela % nao existe nesta base; pulada.', r.tabela;
        CONTINUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'tenant_id') THEN
        RAISE NOTICE 'ATENCAO: % sem tenant_id; ficou SEM a trava.', r.tabela;
        CONTINUE;
      END IF;

      v_mods := quote_literal(ARRAY['ponto','colaboradores']) || '::text[]';

      IF r.modo = 'troca' THEN
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR regexp_replace(COALESCE(colaborador_a_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR regexp_replace(COALESCE(colaborador_b_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'AND (public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_a_cpf) '
          || 'OR public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_b_cpf)))';
      ELSIF r.modo = 'sem_cpf' THEN
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ')';
      ELSE
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = r.tabela AND column_name = 'colaborador_cpf') THEN
          RAISE NOTICE 'ATENCAO: % sem colaborador_cpf; ficou SEM a trava.', r.tabela;
          CONTINUE;
        END IF;
        v_using :=
             'public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'OR regexp_replace(COALESCE(colaborador_cpf,''''),''[^0-9]'','''',''g'') = public.cpf_do_usuario_logado() '
          || 'OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ' || v_mods || ') '
          || 'AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf))';
        IF r.tabela = 'ponto_alertas' THEN
          v_using := v_using
            || ' OR (tipo IN (''excesso_jornada'',''intervalo_suprimido'',''interjornada_insuficiente'') '
            || 'AND public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY[''ergonomia'']::text[]))';
        END IF;
      END IF;

      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tabela);
      EXECUTE format('DROP POLICY IF EXISTS perfil_restringe_leitura_%1$s ON public.%1$I', r.tabela);
      EXECUTE format('CREATE POLICY perfil_restringe_leitura_%1$s ON public.%1$I AS RESTRICTIVE FOR SELECT TO authenticated USING (%2$s)',
                     r.tabela, v_using);
      RAISE NOTICE 'Jornada 1b: leitura por perfil aplicada em %.', r.tabela;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ATENCAO: % ficou SEM a trava de leitura: %', r.tabela, SQLERRM;
    END;
  END LOOP;
END $jor$;
