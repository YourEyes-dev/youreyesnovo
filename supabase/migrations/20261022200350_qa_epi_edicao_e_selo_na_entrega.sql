-- =========================================================
-- QA — EPI: dois testes que nascem VERMELHOS de propósito (prova de bug).
--
-- 1) TELA-EPI-049 (e2e) — "Editar EPI altera o item existente e não cria outro".
--    O formulário de EPI (EpiForm) recebe a propriedade onSubmit mas nunca a
--    chama: o botão "Salvar Alterações" cai no mesmo caminho do cadastro
--    (onCreateTipo) e cria um tipo e um item NOVOS, com movimentação falsa de
--    "Cadastro inicial", sem tocar no original. Nenhum teste existente editava.
--    Spec: cypress/e2e/epi.cy.ts (CT-49).
--
-- 2) EPI-045 (api) — "A entrega assinada no ato do registro nasce lacrada".
--    O wizard grava a entrega JÁ assinada (INSERT com signed_at), mas o selo de
--    integridade (assinatura_hash) e o arquivamento da ficha em Documentos são
--    gatilhos de UPDATE OF signed_at com OLD.signed_at IS NULL: no INSERT nunca
--    disparam. O EPI-042 só conferia que a COLUNA de hash existia e passava.
--    Esta rotina reproduz o caminho do wizard e exige o valor preenchido.
--
-- Esta migration só documenta e liga testes; não altera comportamento do sistema.
-- Idempotente. Carimbo gerado com date -u.
-- =========================================================

SET lock_timeout = '10s';

-- 1) Casos documentados
DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi');
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-ocupacional/epi não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'TELA-EPI-049',
   'CT-49: Editar EPI altera o item existente e não cria outro',
   'feliz', 'alta', 'aprovado', 'e2e',
   'NR-6 (controle do EPI fornecido) — o cadastro é a base da ficha de entrega',
   'Corrigir um dado do EPI (nome, marca, mínimo) precisa alterar o item que já existe. Se a edição cria outro item, o estoque se duplica, o histórico ganha uma entrada falsa e o original segue errado.',
   'Usuário com permissão de editar EPI; um EPI cadastrado na própria corrida do teste.',
   '[{"ordem":1,"acao":"Cadastrar um EPI com nome único","resultado_esperado":"Aparece na aba Estoque, uma única linha"},
     {"ordem":2,"acao":"No menu da linha, abrir Editar, trocar o nome e clicar em Salvar Alterações","resultado_esperado":"Diálogo fecha"},
     {"ordem":3,"acao":"Buscar na lista pelo nome novo e pelo nome antigo","resultado_esperado":"O nome novo aparece em UMA linha; o nome antigo não existe mais"}]'::jsonb,
   'A edição troca o nome do item existente; continua havendo uma única linha para aquele CA.',
   'Prova de bug C9: EpiForm nunca chama onSubmit; a edição cria tipo e item novos. Este teste DEVE FALHAR até a correção.'),

  (v_mod, 'EPI-045',
   'A entrega assinada no ato do registro nasce lacrada (hash) e arquivada em Documentos',
   'negativo', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º, II (detectar modificação posterior); MP 2.200-2/2001, art. 10, §2º; STJ REsp 2.159.442/PR',
   'O wizard de entrega grava a ficha já assinada (INSERT com signed_at). Se o selo de integridade e o arquivamento só existem para UPDATE, a ficha mais comum nasce sem hash e fora do módulo Documentos: a assinatura vira imagem sem prova de integridade. A coluna existir não basta; o valor precisa estar preenchido.',
   'Sandbox QA com um EPI em estoque.',
   '[{"ordem":1,"acao":"Registrar a entrega JÁ assinada, no mesmo INSERT (como o wizard faz)","resultado_esperado":"Entrega gravada com signed_at e assinatura_url"},
     {"ordem":2,"acao":"Conferir assinatura_hash","resultado_esperado":"Hash preenchido no ato"},
     {"ordem":3,"acao":"Conferir o módulo Documentos","resultado_esperado":"Ficha de EPI arquivada (tipo ficha_epi) apontando para a assinatura"}]'::jsonb,
   'Toda entrega assinada, entre por INSERT ou por UPDATE, sai com hash e ficha arquivada.',
   'Prova de bug C2/C3. Complementa o EPI-042, que só conferia a existência da coluna de hash. Esta rotina DEVE FALHAR até a correção.')
  ON CONFLICT (codigo) DO NOTHING;
END $doc$;

-- 2) Rotina do EPI-045 (caminho do wizard: INSERT já assinado)
CREATE OR REPLACE FUNCTION public.qa_caso_epi_045()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_tipo uuid; v_epi uuid; v_id uuid; v_hash text; v_docs int;
        v_path text := 'qa/assinatura-epi-045.png';
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Registrar a entrega JÁ assinada, no mesmo INSERT (caminho real do wizard)';
  r.esperado := 'Ficha lacrada com hash e arquivada em Documentos no ato da assinatura';
  INSERT INTO public.epi_tipos (tenant_id, nome, ca_numero, ca_validade, is_active)
  VALUES (v_t, 'QA — Luva selo', '99045', CURRENT_DATE + 365, true)
  RETURNING id INTO v_tipo;
  INSERT INTO public.epis (tenant_id, tipo_id, codigo, quantidade_estoque, data_validade)
  VALUES (v_t, v_tipo, 'QA-EPI-045', 10, CURRENT_DATE + 365)
  RETURNING id INTO v_epi;

  INSERT INTO public.epi_entregas
    (tenant_id, epi_id, colaborador_nome, colaborador_cpf, quantidade, data_entrega,
     assinatura_url, signed_at, user_agent)
  VALUES (v_t, v_epi, 'QA Colaborador Quarenta e Cinco', public.qa_cpf(45), 1, CURRENT_DATE,
          v_path, now(), 'qa-epi-045')
  RETURNING id INTO v_id;

  v_hash := (SELECT e.assinatura_hash FROM public.epi_entregas e WHERE e.id = v_id);
  v_docs := (SELECT count(*) FROM public.documentos d
              WHERE d.tenant_id = v_t AND d.tipo = 'ficha_epi' AND d.storage_path = v_path);

  IF COALESCE(v_hash, '') = '' AND v_docs = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a entrega assinada no INSERT (o caminho do wizard) nasceu SEM hash de '
             || 'integridade e SEM ficha em Documentos. Os gatilhos trg_epi_entrega_sela_integridade '
             || 'e trg_epi_entrega_arquivar_documento são de UPDATE OF signed_at com '
             || 'OLD.signed_at IS NULL e nunca disparam no INSERT. Correção: cobrir também o '
             || 'INSERT (BEFORE INSERT OR UPDATE) com a mesma regra, sem tocar nos blocos '
             || 'injetados de outras funções.';
  ELSIF COALESCE(v_hash, '') = '' THEN
    r.situacao := 'falhou';
    r.obtido := 'A ficha foi arquivada em Documentos, mas a entrega assinada no INSERT ficou sem hash de integridade.';
  ELSIF v_docs = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'O hash foi gravado, mas a ficha assinada no INSERT não foi arquivada em Documentos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Entrega assinada no INSERT nasceu lacrada (hash %s...) e arquivada em Documentos.',
                       left(v_hash, 12));
  END IF;
  r.detalhe := jsonb_build_object('entrega_id', v_id, 'hash_preenchido', COALESCE(v_hash, '') <> '',
                                  'fichas_em_documentos', v_docs);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('EPI-045', 'qa_caso_epi_045')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- 3) Ponte caso -> it() (título EXATO do it() em epi.cy.ts)
DELETE FROM public.qa_cobertura_e2e WHERE codigo = 'TELA-EPI-049';
INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
VALUES ('TELA-EPI-049', 'cypress/e2e/epi.cy.ts',
        'CT-49: Editar EPI altera o item existente e não cria outro');
