-- ============================================================================
-- ENTREGA — ADM-101/102/103 · reconciliação de documentos de admissão
--            PARTE 1/2: OBJETOS (funções, gatilhos, auditorias) — HOMOLOGAÇÃO
--
-- Cole no SQL Editor da HOMOLOGAÇÃO; depois de conferido, o MESMO na PRODUÇÃO.
-- Esta parte NÃO toca em dado — só cria/atualiza funções, gatilhos e as rotinas
-- de auditoria. O reparo retroativo (que mexe em documento real) é a PARTE 2.
--
-- Cobre:
--   ADM-101/102 · gatilho que resolve dono+pasta na escrita do documento, e a
--                 função de pasta do colaborador (cria a árvore se faltar).
--   ADM-103     · gatilho que reconcilia os documentos quando a admissão conclui.
--   + refinação das auditorias ADM-101/102 para medirem a coisa certa: só contam
--     documento cujo dono JÁ É colaborador (documento de gente ainda EM admissão
--     legitimamente não tem dono — deixar de acusá-lo não afrouxa nada, corrige a
--     premissa da própria auditoria). ADM-108 já está verde e não entra aqui.
--
-- CORREÇÃO DE BUG (importante): as funções da migration comparavam
--   COALESCE(ub.status,'ativo') <> 'excluido' — mas 'excluido' NÃO é rótulo do
--   enum usuario_status. Em banco vazio o laço não itera e passa; com dado real
--   (homologação/produção) quebra. Aqui vai com ub.status::text (compara como
--   texto — pegadinha documentada no CLAUDE.md).
--
-- SEGURANÇA: só CREATE FUNCTION/TRIGGER — não cria tabela (auto-RLS não liga),
--   não apaga/altera dado. Dois gatilhos em DUAS tabelas (documentos e admissoes):
--   se aparecer "deadlock detected", rode de novo (idempotente). lock_timeout curto.
--
-- Origem: migrations 20260804150000 (com o fix ::text) e 20260801140000
--   (auditorias, refinadas). Ao fim, conferência.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Pasta do colaborador (cria a árvore Gestão de Pessoas → pessoa → subpastas) ─
CREATE OR REPLACE FUNCTION public.documento_pasta_do_colaborador(
  p_tenant_id uuid,
  p_colaborador_id uuid,
  p_colaborador_nome text,
  p_colaborador_cpf text DEFAULT NULL,
  p_empresa_id uuid DEFAULT NULL,
  p_subpasta text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_raiz uuid;
  v_pasta uuid;
  v_sub uuid;
  v_nome text := COALESCE(NULLIF(btrim(p_colaborador_nome), ''), 'Colaborador');
  v_padrao text[] := ARRAY['Admissão', 'Vida Funcional', 'Saúde Ocupacional', 'Desligamento'];
  v_item text;
  v_i int := 0;
BEGIN
  IF p_tenant_id IS NULL OR p_colaborador_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_pasta
  FROM public.documento_pastas
  WHERE tenant_id = p_tenant_id
    AND colaborador_id = p_colaborador_id
    AND tipo = 'colaborador'
    AND empresa_id IS NOT DISTINCT FROM p_empresa_id
  LIMIT 1;

  IF v_pasta IS NULL THEN
    SELECT id INTO v_raiz
    FROM public.documento_pastas
    WHERE tenant_id = p_tenant_id
      AND nome = 'Gestão de Pessoas'
      AND empresa_id IS NOT DISTINCT FROM p_empresa_id
    LIMIT 1;

    IF v_raiz IS NULL THEN
      INSERT INTO public.documento_pastas (tenant_id, nome, tipo, ordem, icone, empresa_id)
      VALUES (p_tenant_id, 'Gestão de Pessoas', 'root', 5, 'Users', p_empresa_id)
      RETURNING id INTO v_raiz;
    END IF;

    INSERT INTO public.documento_pastas (
      tenant_id, nome, tipo, pasta_pai_id, colaborador_id, colaborador_cpf,
      colaborador_nome, ordem, icone, empresa_id
    ) VALUES (
      p_tenant_id, v_nome, 'colaborador', v_raiz, p_colaborador_id,
      NULLIF(regexp_replace(COALESCE(p_colaborador_cpf, ''), '[^0-9]', '', 'g'), ''),
      v_nome, 0, 'User', p_empresa_id
    )
    RETURNING id INTO v_pasta;
  END IF;

  FOREACH v_item IN ARRAY v_padrao LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.documento_pastas
      WHERE tenant_id = p_tenant_id AND pasta_pai_id = v_pasta AND nome = v_item
    ) THEN
      INSERT INTO public.documento_pastas (tenant_id, nome, tipo, pasta_pai_id, ordem, empresa_id)
      VALUES (p_tenant_id, v_item, 'categoria', v_pasta, v_i, p_empresa_id);
    END IF;
    v_i := v_i + 1;
  END LOOP;

  IF p_subpasta IS NULL THEN
    RETURN v_pasta;
  END IF;

  SELECT id INTO v_sub
  FROM public.documento_pastas
  WHERE tenant_id = p_tenant_id AND pasta_pai_id = v_pasta AND nome = p_subpasta
  LIMIT 1;

  RETURN COALESCE(v_sub, v_pasta);
END;
$$;

-- ── Na escrita: resolve dono e pasta (::text no status — fix do bug) ─────────
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
      NEW.tenant_id,
      NEW.colaborador_id,
      COALESCE(v_nome, NEW.colaborador_nome),
      v_cpf,
      v_emp,
      v_sub
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documento_resolver_dono_e_pasta ON public.documentos;
CREATE TRIGGER trg_documento_resolver_dono_e_pasta
  BEFORE INSERT OR UPDATE OF colaborador_cpf, colaborador_id, pasta_id ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.documento_resolver_dono_e_pasta();

-- ── Reconciliação retroativa (::text no status — fix do bug) ─────────────────
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

-- ── Gatilho na conclusão da admissão (fecha o ciclo — ADM-103) ───────────────
CREATE OR REPLACE FUNCTION public.admissao_reconciliar_documentos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'concluido'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'concluido')
     AND COALESCE(NEW.cpf, '') <> '' THEN
    PERFORM public.reconciliar_documentos_colaborador(NEW.tenant_id, NEW.cpf);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admissao_reconciliar_documentos ON public.admissoes;
CREATE TRIGGER trg_admissao_reconciliar_documentos
  AFTER INSERT OR UPDATE OF status ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_reconciliar_documentos();

REVOKE EXECUTE ON FUNCTION public.reconciliar_documentos_colaborador(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconciliar_documentos_colaborador(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.documento_pasta_do_colaborador(uuid, uuid, text, text, uuid, text) TO authenticated;

-- ── Auditoria ADM-102 refinada: só conta doc cujo dono JÁ É resolvível ───────
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
    r.obtido   := format('%s documento(s) de admissao; todos de quem ja e colaborador estao com '
               || 'dono identificado (documento de admissao em curso, sem dono, e legitimo).', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('%s documento(s) de admissao de pessoa JA registrada como colaborador '
               || 'continuam SEM colaborador_id — deveriam ter sido reconciliados. Rode '
               || 'reconciliar_documentos_colaborador(); daqui pra frente o gatilho resolve na escrita.',
               v_sem_dono);
    r.detalhe  := jsonb_build_object('sem_colaborador_id_resolvivel', v_sem_dono, 'total', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;

-- ── Auditoria ADM-101 refinada: só conta doc de dono resolvível sem pasta ────
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
    r.obtido   := format('%s documento(s) de admissao; todos de quem ja e colaborador estao '
               || 'arquivados em pasta (documento de admissao em curso e legitimo ficar sem pasta).', v_total);
  ELSE
    r.situacao := 'falhou';
    r.obtido   := format('%s documento(s) de dono ja resolvivel continuam SEM pasta_id. Rode '
               || 'reconciliar_documentos_colaborador(); daqui pra frente o gatilho arquiva na escrita.',
               v_sem_pasta);
    r.detalhe  := jsonb_build_object('sem_pasta_resolvivel', v_sem_pasta, 'total', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM;
  RETURN r;
END $$;


-- ════════════════════ CONFERÊNCIA (única — esperado tudo 'ok') ════════════════
WITH alvo(item, presente) AS (
  VALUES
    ('ADM · função pasta do colaborador',
       (to_regprocedure('public.documento_pasta_do_colaborador(uuid,uuid,text,text,uuid,text)') IS NOT NULL)),
    ('ADM-101/102 · resolver dono+pasta na escrita (função)',
       (to_regprocedure('public.documento_resolver_dono_e_pasta()') IS NOT NULL)),
    ('ADM-101/102 · gatilho na escrita (documentos)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_documento_resolver_dono_e_pasta' AND NOT tgisinternal)),
    ('ADM · reconciliação retroativa (função, com fix ::text)',
       (to_regprocedure('public.reconciliar_documentos_colaborador(uuid,text)') IS NOT NULL)),
    ('ADM-103 · reconciliar na conclusão (função)',
       (to_regprocedure('public.admissao_reconciliar_documentos()') IS NOT NULL)),
    ('ADM-103 · gatilho na conclusão (admissoes)',
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_admissao_reconciliar_documentos' AND NOT tgisinternal)),
    ('ADM-101 · auditoria refinada (sem min/excluido cru)',
       (pg_get_functiondef('public.qa_caso_adm_101()'::regprocedure) ~* 'ja e colaborador')),
    ('ADM-102 · auditoria refinada',
       (pg_get_functiondef('public.qa_caso_adm_102()'::regprocedure) ~* 'ja e colaborador'))
)
SELECT item, CASE WHEN presente THEN 'ok' ELSE 'FALTOU' END AS situacao FROM alvo ORDER BY item;
