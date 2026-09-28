-- ============================================================================
-- Correção — reconciliação de documentos de admissão (ADM-101/102/103)
--
-- Dois ajustes forward-only sobre as funções da migration 20260804150000:
--
-- 1) BUG do enum: documento_resolver_dono_e_pasta() e
--    reconciliar_documentos_colaborador() comparavam
--      COALESCE(ub.status, 'ativo') <> 'excluido'
--    mas 'excluido' NÃO é rótulo do enum usuario_status
--    (rascunho|pendente_convite|convite_enviado|aguardando_ativacao|ativo|
--     bloqueado|suspenso|inativo|arquivado). Em banco vazio o laço não itera e
--    passa; com dado real quebra ("invalid input value for enum usuario_status").
--    Correção: comparar ub.status::text (pegadinha documentada no CLAUDE.md).
--
-- 2) Auditorias ADM-101/102 refinadas: passam a medir só documento cujo dono JÁ
--    é colaborador (existe em usuarios_base pelo CPF). Documento de gente ainda
--    EM admissão legitimamente não tem dono/pasta — contá-lo como falha era um
--    falso-positivo da premissa. ADM-103 (só admissões concluídas) e ADM-108
--    (órfãos) ficam como estão.
--
-- Ao fim, um bloco DO reconcilia o passivo com a função corrigida (no-op em
-- banco vazio; nos ambientes com dado, resolve o que tem dono).
-- ============================================================================

-- ── 1) documento_resolver_dono_e_pasta — ::text no status ───────────────────
CREATE OR REPLACE FUNCTION public.documento_resolver_dono_e_pasta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_cpf text;
  v_nome text;
  v_emp uuid;
  v_sub text;
BEGIN
  v_cpf := NULLIF(regexp_replace(COALESCE(NEW.colaborador_cpf, ''), '[^0-9]', '', 'g'), '');

  IF NEW.colaborador_id IS NULL AND v_cpf IS NOT NULL THEN
    SELECT ub.id, ub.nome_completo
      INTO NEW.colaborador_id, v_nome
    FROM public.usuarios_base ub
    WHERE ub.tenant_id = NEW.tenant_id
      AND regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') = v_cpf
      AND COALESCE(ub.status::text, 'ativo') <> 'excluido'
    ORDER BY (ub.tipo_usuario = 'colaborador') DESC, ub.created_at
    LIMIT 1;
  END IF;

  IF NEW.pasta_id IS NULL AND NEW.colaborador_id IS NOT NULL THEN
    v_emp := NEW.empresa_id;
    v_sub := CASE WHEN NEW.observacoes = 'Documento da admissão' THEN 'Admissão' ELSE NULL END;

    NEW.pasta_id := public.documento_pasta_do_colaborador(
      NEW.tenant_id, NEW.colaborador_id, COALESCE(v_nome, NEW.colaborador_nome),
      v_cpf, v_emp, v_sub);
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2) reconciliar_documentos_colaborador — ::text no status ────────────────
CREATE OR REPLACE FUNCTION public.reconciliar_documentos_colaborador(
  p_tenant_id uuid DEFAULT NULL,
  p_colaborador_cpf text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r RECORD;
  v_pasta uuid;
  v_dono uuid;
  v_ajustados int := 0;
  v_sem_pessoa int := 0;
  v_cpf_filtro text := NULLIF(regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g'), '');
BEGIN
  FOR r IN
    SELECT d.id, d.tenant_id, d.empresa_id, d.colaborador_id, d.colaborador_nome,
           d.observacoes,
           regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf
    FROM public.documentos d
    WHERE (p_tenant_id IS NULL OR d.tenant_id = p_tenant_id)
      AND (d.colaborador_id IS NULL OR d.pasta_id IS NULL)
      AND COALESCE(d.colaborador_cpf, '') <> ''
      AND (v_cpf_filtro IS NULL
           OR regexp_replace(COALESCE(d.colaborador_cpf, ''), '[^0-9]', '', 'g') = v_cpf_filtro)
  LOOP
    v_dono := r.colaborador_id;

    IF v_dono IS NULL THEN
      SELECT ub.id INTO v_dono
      FROM public.usuarios_base ub
      WHERE ub.tenant_id = r.tenant_id
        AND regexp_replace(COALESCE(ub.cpf, ''), '[^0-9]', '', 'g') = r.cpf
        AND COALESCE(ub.status::text, 'ativo') <> 'excluido'
      ORDER BY (ub.tipo_usuario = 'colaborador') DESC, ub.created_at
      LIMIT 1;
    END IF;

    IF v_dono IS NULL THEN
      v_sem_pessoa := v_sem_pessoa + 1;
      CONTINUE;
    END IF;

    v_pasta := public.documento_pasta_do_colaborador(
      r.tenant_id, v_dono, r.colaborador_nome, r.cpf, r.empresa_id,
      CASE WHEN r.observacoes = 'Documento da admissão' THEN 'Admissão' ELSE NULL END
    );

    UPDATE public.documentos
       SET colaborador_id = v_dono,
           pasta_id       = COALESCE(pasta_id, v_pasta)
     WHERE id = r.id;

    v_ajustados := v_ajustados + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'documentos_reconciliados', v_ajustados,
    'documentos_sem_pessoa_ainda', v_sem_pessoa
  );
END;
$$;

-- ── 3) ADM-102 refinada ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_adm_102()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_total int; v_sem_dono int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): documentos de admissao de quem JA e colaborador, sem colaborador_id';
  r.esperado    := 'Zero — documento de pessoa ja registrada tem dono. (Em admissao em curso, sem dono e legitimo.)';

  SELECT count(*) INTO v_total FROM public.documentos
  WHERE observacoes = 'Documento da admissão';

  IF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Nenhum documento de admissao sincronizado nesta base — nada a auditar.';
    RETURN r;
  END IF;

  SELECT count(*) INTO v_sem_dono
  FROM public.documentos d
  WHERE d.observacoes = 'Documento da admissão'
    AND d.colaborador_id IS NULL
    AND EXISTS (
      SELECT 1 FROM public.usuarios_base ub
      WHERE ub.tenant_id = d.tenant_id
        AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g')
            = regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')
        AND COALESCE(d.colaborador_cpf,'') <> ''
        AND COALESCE(ub.status::text,'ativo') <> 'excluido');

  IF v_sem_dono = 0 THEN
    r.situacao := 'passou';
    r.obtido   := format('%s documento(s) de admissao; todos de quem ja e colaborador estao com dono.', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('%s documento(s) de pessoa JA registrada continuam SEM colaborador_id.', v_sem_dono);
    r.detalhe  := jsonb_build_object('sem_colaborador_id_resolvivel', v_sem_dono, 'total', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── 4) ADM-101 refinada ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_caso_adm_101()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno; v_total int; v_sem_pasta int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao  := 'AUDITORIA (somente leitura): documentos de quem JA e colaborador, sem pasta_id';
  r.esperado    := 'Zero — documento de pessoa ja registrada esta arquivado em pasta.';

  SELECT count(*) INTO v_total FROM public.documentos
  WHERE observacoes = 'Documento da admissão';

  IF v_total = 0 THEN
    r.situacao := 'nao_implementado';
    r.obtido   := 'Nenhum documento de admissao sincronizado nesta base — nada a auditar.';
    RETURN r;
  END IF;

  SELECT count(*) INTO v_sem_pasta
  FROM public.documentos d
  WHERE d.observacoes = 'Documento da admissão'
    AND d.pasta_id IS NULL
    AND (
      d.colaborador_id IS NOT NULL
      OR EXISTS (
        SELECT 1 FROM public.usuarios_base ub
        WHERE ub.tenant_id = d.tenant_id
          AND regexp_replace(COALESCE(ub.cpf,''),'[^0-9]','','g')
              = regexp_replace(COALESCE(d.colaborador_cpf,''),'[^0-9]','','g')
          AND COALESCE(d.colaborador_cpf,'') <> ''
          AND COALESCE(ub.status::text,'ativo') <> 'excluido'));

  IF v_sem_pasta = 0 THEN
    r.situacao := 'passou';
    r.obtido   := format('%s documento(s) de admissao; todos de quem ja e colaborador arquivados em pasta.', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('%s documento(s) de dono ja resolvivel continuam SEM pasta_id.', v_sem_pasta);
    r.detalhe  := jsonb_build_object('sem_pasta_resolvivel', v_sem_pasta, 'total', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── 5) Reconcilia o passivo com a função corrigida (no-op em banco vazio) ────
DO $reconc$
DECLARE v_res jsonb;
BEGIN
  v_res := public.reconciliar_documentos_colaborador(NULL, NULL);
  RAISE NOTICE 'Reconciliação (fix ::text): %', v_res::text;
END $reconc$;
