-- =========================================================
-- QA — HUB CONTÁBIL / Canal único do contador (PREM-0005, FASE 1)
--
-- Primeira verificação real do acesso externo por LINK do contador. Exercita,
-- no cercado, as RPCs SECURITY DEFINER criadas em
-- 20261026200623_hub_contador_link_publico.sql.
--
-- O QUE IMPORTA MAIS (nesta ordem):
--   1. ISOLAMENTO: o token do cercado A NUNCA enxerga nem toca dado do cercado B
--      (leitura — HUBCTD-020 — e escrita — HUBCTD-021). Usa os dois cercados da
--      homologação: '[QA] Cercado de Teste Automatizado' (qa-sandbox) e
--      '[QA] Cercado Vizinho (isolamento)' (qa-sandbox-2).
--   2. Filtragem: documento com visivel_contabilidade=false e comentário
--      eh_interno=true NÃO aparecem para o contador (HUBCTD-003/014/015).
--   3. Transições permitidas: só o conjunto liberado ao contador; nunca
--      cancelado/concluido (HUBCTD-005/013).
--   4. Validação/expiração do token (HUBCTD-010/011/012).
--   5. Lição ISOL-006: as RPCs revogam de PUBLIC; o resolver interno é fechado a
--      anon (HUBCTD-022).
--
-- Rotinas são somente leitura do ponto de vista do cliente real: tudo escreve
-- apenas nos cercados, sob a trava qa_bloqueia_fora_do_cercado (qa_modo_ligar).
-- =========================================================

-- ─────────────────────────────────────────────────────────
-- DOCUMENTAÇÃO (módulo já existente: documentos-governanca/hub-contabil)
-- ─────────────────────────────────────────────────────────
DO $seed$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'documentos-governanca/hub-contabil';
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Modulo hub-contabil nao encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, objetivo, resultado_esperado)
  VALUES
  -- FELIZ
  (v_mod,'HUBCTD-001','Validar o acesso do contador pelo token do link','feliz','alta','aprovado','api',
   'buscar_contador_acesso_por_token devolve empresa e contabilidade do link.','Acesso valido com os nomes.'),
  (v_mod,'HUBCTD-002','Contador lista os processos da sua contabilidade','feliz','alta','aprovado','api',
   'listar_hub_processos_contador traz os processos compartilhados do vinculo.','Processo compartilhado aparece.'),
  (v_mod,'HUBCTD-003','Contador abre um processo e ve doc visivel + comentario externo','feliz','alta','aprovado','api',
   'obter_hub_processo_contador devolve o dossie filtrado.','Documento visivel e comentario externo aparecem.'),
  (v_mod,'HUBCTD-004','Contador comenta no processo (bidirecional)','feliz','alta','aprovado','api',
   'comentar grava autor_perfil=contador, eh_interno=false e historico+ip.','Comentario e trilha gravados.'),
  (v_mod,'HUBCTD-005','Contador avanca status para um valor permitido','feliz','alta','aprovado','api',
   'mudar_status aceita em_analise.','Status muda para em_analise.'),
  (v_mod,'HUBCTD-006','Contador sobe documento de devolutiva (bidirecional)','feliz','alta','aprovado','api',
   'registrar_documento_contador grava origem=devolutiva_contabilidade, visivel.','Documento de devolutiva gravado.'),
  -- EXCECAO (token)
  (v_mod,'HUBCTD-010','Token inexistente e recusado','excecao','alta','aprovado','api',
   'Token que nao casa com nenhum link.','Erro de link invalido.'),
  (v_mod,'HUBCTD-011','Token expirado e recusado','excecao','alta','aprovado','api',
   'data_expiracao no passado invalida o link.','Erro de link expirado.'),
  (v_mod,'HUBCTD-012','Token de link inativo e recusado','excecao','alta','aprovado','api',
   'ativo=false invalida o link.','Erro de link invalido.'),
  -- NEGATIVO (regras)
  (v_mod,'HUBCTD-013','Contador NAO pode concluir nem cancelar','negativo','critica','aprovado','api',
   'mudar_status recusa concluido/cancelado.','Recusado; status inalterado.'),
  (v_mod,'HUBCTD-014','Comentario interno do RH e invisivel ao contador','negativo','critica','aprovado','api',
   'obter filtra eh_interno=false.','Comentario interno nao aparece.'),
  (v_mod,'HUBCTD-015','Documento nao-visivel e invisivel ao contador','negativo','critica','aprovado','api',
   'obter filtra visivel_contabilidade=true.','Documento oculto nao aparece.'),
  -- ISOLAMENTO (o mais importante)
  (v_mod,'HUBCTD-020','ISOLAMENTO leitura: token de A nao enxerga processo de B','negativo','critica','aprovado','api',
   'tenant derivado do token; A nunca ve B.','Processo de B invisivel ao token de A.'),
  (v_mod,'HUBCTD-021','ISOLAMENTO escrita: token de A nao toca processo de B','negativo','critica','aprovado','api',
   'comentar/mudar_status/registrar_documento recusam processo de outro tenant.','Nada gravado em B.'),
  -- ESTRUTURA / PERMISSAO
  (v_mod,'HUBCTD-022','Resolver interno do token fechado a anon (licao ISOL-006)','excecao','critica','aprovado','api',
   '_hub_contador_link_valido nao executavel por anon; RPCs publicas sim.','Resolver fechado; RPCs abertas a anon.'),
  (v_mod,'HUBCTD-023','Estrutura do canal do contador criada','feliz','media','aprovado','api',
   'Tabela, indice unico (tenant,contabilidade) e coluna visivel_contabilidade.','Estrutura presente.')
  ON CONFLICT (codigo) DO NOTHING;
END $seed$;

-- ─────────────────────────────────────────────────────────
-- SETUP do cenário (contabilidade + link + processo compartilhado)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.qa_hub_ctd_setup(p_tenant uuid, p_status text DEFAULT 'enviado_contabilidade')
RETURNS json LANGUAGE plpgsql AS $$
DECLARE v_contab uuid; v_token text; v_proc uuid;
BEGIN
  INSERT INTO public.hub_contabilidades (tenant_id, nome, email_principal)
  VALUES (p_tenant, '[QA] Contabilidade Canal ' || substr(gen_random_uuid()::text, 1, 8), 'qa@contabil.invalid')
  RETURNING id INTO v_contab;

  INSERT INTO public.hub_contador_links (tenant_id, contabilidade_id, rotulo)
  VALUES (p_tenant, v_contab, '[QA] Link Contador')
  RETURNING token INTO v_token;

  INSERT INTO public.hub_processos (tenant_id, contabilidade_id, tipo, status, titulo, competencia, colaborador_nome)
  VALUES (p_tenant, v_contab, 'admissao', p_status::public.hub_processo_status, '[QA] Processo Canal', '[QA]2026-10', '[QA] Colaborador')
  RETURNING id INTO v_proc;

  RETURN json_build_object('contabilidade_id', v_contab, 'token', v_token, 'processo_id', v_proc);
END $$;

-- ─────────────────────────────────────────────────────────
-- ROTINAS
-- ─────────────────────────────────────────────────────────

-- HUBCTD-001
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_out json;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Gerar link e validar acesso pelo token'; r.esperado:='valido=true com empresa e contabilidade';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_out := public.buscar_contador_acesso_por_token(v_s->>'token');
  IF COALESCE((v_out->>'valido')::boolean,false) AND (v_out->>'contabilidade_nome') IS NOT NULL THEN
    r.situacao:='passou'; r.obtido:='Acesso validado; contabilidade='||(v_out->>'contabilidade_nome');
  ELSE r.situacao:='falhou'; r.obtido:='Retorno inesperado: '||v_out::text; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-002
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_out json; v_n int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Listar processos pelo token'; r.esperado:='O processo compartilhado aparece';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_out := public.listar_hub_processos_contador(v_s->>'token');
  v_n := (SELECT count(*) FROM json_array_elements(v_out->'processos') e WHERE e->>'id' = v_s->>'processo_id');
  IF v_n = 1 THEN r.situacao:='passou'; r.obtido:='Processo compartilhado listado.';
  ELSE r.situacao:='falhou'; r.obtido:=format('Esperava 1 ocorrencia, achou %s.', v_n); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-003
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_out json; v_docs int; v_coms int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Processo com doc visivel + comentario externo, depois obter'; r.esperado:='Dossie traz doc e comentario';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  INSERT INTO public.hub_processo_documentos (tenant_id, processo_id, nome, arquivo_url, visivel_contabilidade)
  VALUES (v_t, v_proc, '[QA] Doc visivel', 'https://x.invalid/a.pdf', true);
  INSERT INTO public.hub_processo_comentarios (tenant_id, processo_id, autor_nome, autor_perfil, conteudo, eh_interno)
  VALUES (v_t, v_proc, '[QA] RH', 'rh', '[QA] comentario externo', false);
  v_out := public.obter_hub_processo_contador(v_s->>'token', v_proc);
  v_docs := (SELECT count(*) FROM json_array_elements(v_out->'documentos'));
  v_coms := (SELECT count(*) FROM json_array_elements(v_out->'comentarios'));
  IF (v_out->'processo') IS NOT NULL AND v_docs >= 1 AND v_coms >= 1 THEN
    r.situacao:='passou'; r.obtido:=format('Dossie ok: %s doc, %s comentario.', v_docs, v_coms);
  ELSE r.situacao:='falhou'; r.obtido:='Dossie incompleto: '||v_out::text; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-004
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_out json; v_c int; v_h int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Contador comenta no processo'; r.esperado:='Comentario externo + historico gravados';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  v_out := public.comentar_hub_processo_contador(v_s->>'token', v_proc, '[QA] duvida do contador');
  v_c := (SELECT count(*) FROM public.hub_processo_comentarios
          WHERE processo_id = v_proc AND autor_perfil='contador' AND eh_interno=false);
  v_h := (SELECT count(*) FROM public.hub_processo_historico
          WHERE processo_id = v_proc AND acao='comentario_contador' AND perfil='contador');
  IF COALESCE((v_out->>'success')::boolean,false) AND v_c=1 AND v_h=1 THEN
    r.situacao:='passou'; r.obtido:='Comentario e trilha do contador gravados.';
  ELSE r.situacao:='falhou'; r.obtido:=format('success=%s comentarios=%s historico=%s', v_out->>'success', v_c, v_h); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-005
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_out json; v_st text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Mudar status para em_analise'; r.esperado:='Status vira em_analise';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  v_out := public.mudar_status_hub_processo_contador(v_s->>'token', v_proc, 'em_analise');
  v_st := (SELECT status::text FROM public.hub_processos WHERE id=v_proc);
  IF COALESCE((v_out->>'success')::boolean,false) AND v_st='em_analise' THEN
    r.situacao:='passou'; r.obtido:='Status avancou para em_analise.';
  ELSE r.situacao:='falhou'; r.obtido:=format('success=%s status=%s', v_out->>'success', v_st); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-006
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_out json; v_d int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Contador sobe documento de devolutiva'; r.esperado:='Doc origem=devolutiva_contabilidade, visivel';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  v_out := public.registrar_documento_contador(v_s->>'token', v_proc, '[QA] Guia INSS', 'https://x.invalid/guia.pdf', 'guia.pdf', 'guia');
  v_d := (SELECT count(*) FROM public.hub_processo_documentos
          WHERE processo_id=v_proc AND origem='devolutiva_contabilidade' AND visivel_contabilidade=true);
  IF COALESCE((v_out->>'success')::boolean,false) AND v_d=1 THEN
    r.situacao:='passou'; r.obtido:='Documento de devolutiva gravado e visivel.';
  ELSE r.situacao:='falhou'; r.obtido:=format('success=%s docs_devolutiva=%s', v_out->>'success', v_d); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-010
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_out json;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Validar um token inexistente'; r.esperado:='Erro de link invalido';
  v_out := public.buscar_contador_acesso_por_token('token-que-nao-existe-'||substr(gen_random_uuid()::text,1,8));
  IF (v_out->>'error') IS NOT NULL THEN r.situacao:='passou'; r.obtido:='Recusado: '||(v_out->>'error');
  ELSE r.situacao:='falhou'; r.obtido:='ACEITOU token inexistente: '||v_out::text; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-011
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_contab uuid; v_token text; v_out json;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Link com data_expiracao no passado'; r.esperado:='Erro de link expirado';
  INSERT INTO public.hub_contabilidades (tenant_id, nome) VALUES (v_t, '[QA] Contab expirada '||substr(gen_random_uuid()::text,1,8)) RETURNING id INTO v_contab;
  INSERT INTO public.hub_contador_links (tenant_id, contabilidade_id, data_expiracao)
  VALUES (v_t, v_contab, now() - interval '1 day') RETURNING token INTO v_token;
  v_out := public.listar_hub_processos_contador(v_token);
  IF (v_out->>'error') IS NOT NULL THEN r.situacao:='passou'; r.obtido:='Recusado por expiracao.';
  ELSE r.situacao:='falhou'; r.obtido:='ACEITOU link expirado: '||v_out::text; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-012
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_contab uuid; v_token text; v_out json;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Link com ativo=false'; r.esperado:='Erro de link invalido';
  INSERT INTO public.hub_contabilidades (tenant_id, nome) VALUES (v_t, '[QA] Contab inativa '||substr(gen_random_uuid()::text,1,8)) RETURNING id INTO v_contab;
  INSERT INTO public.hub_contador_links (tenant_id, contabilidade_id, ativo)
  VALUES (v_t, v_contab, false) RETURNING token INTO v_token;
  v_out := public.buscar_contador_acesso_por_token(v_token);
  IF (v_out->>'error') IS NOT NULL THEN r.situacao:='passou'; r.obtido:='Recusado: link inativo.';
  ELSE r.situacao:='falhou'; r.obtido:='ACEITOU link inativo: '||v_out::text; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-013
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_o1 json; v_o2 json; v_st text;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Tentar concluir e cancelar pelo contador'; r.esperado:='Recusado; status inalterado';
  v_s := public.qa_hub_ctd_setup(v_t);  -- nasce enviado_contabilidade
  v_proc := (v_s->>'processo_id')::uuid;
  v_o1 := public.mudar_status_hub_processo_contador(v_s->>'token', v_proc, 'concluido');
  v_o2 := public.mudar_status_hub_processo_contador(v_s->>'token', v_proc, 'cancelado');
  v_st := (SELECT status::text FROM public.hub_processos WHERE id=v_proc);
  IF (v_o1->>'error') IS NOT NULL AND (v_o2->>'error') IS NOT NULL AND v_st='enviado_contabilidade' THEN
    r.situacao:='passou'; r.obtido:='Concluir e cancelar recusados; status segue enviado_contabilidade.';
  ELSE r.situacao:='falhou'; r.obtido:=format('o1=%s o2=%s status=%s', v_o1::text, v_o2::text, v_st); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-014
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_014()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_marca text; v_out json; v_vaza int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Comentario interno do RH + obter pelo contador'; r.esperado:='Interno nao aparece';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  v_marca := '[QA] INTERNO '||substr(gen_random_uuid()::text,1,8);
  INSERT INTO public.hub_processo_comentarios (tenant_id, processo_id, autor_nome, autor_perfil, conteudo, eh_interno)
  VALUES (v_t, v_proc, '[QA] RH', 'rh', v_marca, true);
  v_out := public.obter_hub_processo_contador(v_s->>'token', v_proc);
  v_vaza := (SELECT count(*) FROM json_array_elements(v_out->'comentarios') e WHERE e->>'conteudo' = v_marca);
  IF v_vaza=0 THEN r.situacao:='passou'; r.obtido:='Comentario interno nao aparece ao contador.';
  ELSE r.situacao:='falhou'; r.obtido:='VAZAMENTO: comentario interno visivel ao contador.'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-015
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_015()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id(); v_s json; v_proc uuid; v_marca text; v_out json; v_vaza int;
BEGIN
  PERFORM public.qa_modo_ligar();
  r.passo_ordem:=1; r.passo_acao:='Documento com visivel_contabilidade=false + obter'; r.esperado:='Documento oculto nao aparece';
  v_s := public.qa_hub_ctd_setup(v_t);
  v_proc := (v_s->>'processo_id')::uuid;
  v_marca := '[QA] OCULTO '||substr(gen_random_uuid()::text,1,8);
  INSERT INTO public.hub_processo_documentos (tenant_id, processo_id, nome, arquivo_url, visivel_contabilidade)
  VALUES (v_t, v_proc, v_marca, 'https://x.invalid/oculto.pdf', false);
  v_out := public.obter_hub_processo_contador(v_s->>'token', v_proc);
  v_vaza := (SELECT count(*) FROM json_array_elements(v_out->'documentos') e WHERE e->>'nome' = v_marca);
  IF v_vaza=0 THEN r.situacao:='passou'; r.obtido:='Documento nao-visivel nao aparece ao contador.';
  ELSE r.situacao:='falhou'; r.obtido:='VAZAMENTO: documento oculto visivel ao contador.'; END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-020 (ISOLAMENTO leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_020()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno;
  v_a uuid := public.qa_sandbox_tenant_id(); v_b uuid := public.qa_sandbox2_tenant_id();
  v_sa json; v_sb json; v_proca uuid; v_procb uuid; v_lista json; v_tem_a int; v_tem_b int; v_obter json;
BEGIN
  PERFORM public.qa_modo_ligar();
  IF v_b IS NULL THEN r.situacao:='erro'; r.obtido:='2o cercado (qa-sandbox-2) nao existe.'; RETURN r; END IF;
  r.passo_ordem:=1; r.passo_acao:='Montar cenario em A e em B'; r.esperado:='Token de A nao enxerga processo de B';
  v_sa := public.qa_hub_ctd_setup(v_a);
  v_sb := public.qa_hub_ctd_setup(v_b);
  v_proca := (v_sa->>'processo_id')::uuid;
  v_procb := (v_sb->>'processo_id')::uuid;
  r.passo_ordem:=2; r.passo_acao:='Listar com o token de A';
  v_lista := public.listar_hub_processos_contador(v_sa->>'token');
  v_tem_a := (SELECT count(*) FROM json_array_elements(v_lista->'processos') e WHERE e->>'id' = v_proca::text);
  v_tem_b := (SELECT count(*) FROM json_array_elements(v_lista->'processos') e WHERE e->>'id' = v_procb::text);
  r.passo_ordem:=3; r.passo_acao:='Tentar obter o processo de B com o token de A';
  v_obter := public.obter_hub_processo_contador(v_sa->>'token', v_procb);
  IF v_tem_a=1 AND v_tem_b=0 AND (v_obter->>'error') IS NOT NULL THEN
    r.situacao:='passou'; r.obtido:='Token de A ve so A; processo de B invisivel e inacessivel.';
  ELSE r.situacao:='falhou'; r.obtido:=format('VAZAMENTO: tem_a=%s tem_b=%s obter_b=%s', v_tem_a, v_tem_b, v_obter::text); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-021 (ISOLAMENTO escrita)
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_021()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno;
  v_a uuid := public.qa_sandbox_tenant_id(); v_b uuid := public.qa_sandbox2_tenant_id();
  v_sa json; v_sb json; v_procb uuid; v_oc json; v_os json; v_od json; v_coms int; v_stb text;
BEGIN
  PERFORM public.qa_modo_ligar();
  IF v_b IS NULL THEN r.situacao:='erro'; r.obtido:='2o cercado (qa-sandbox-2) nao existe.'; RETURN r; END IF;
  r.passo_ordem:=1; r.passo_acao:='Montar cenario em A e em B'; r.esperado:='Token de A nao grava nada em B';
  v_sa := public.qa_hub_ctd_setup(v_a);
  v_sb := public.qa_hub_ctd_setup(v_b);
  v_procb := (v_sb->>'processo_id')::uuid;
  r.passo_ordem:=2; r.passo_acao:='Tentar comentar/mudar status/subir doc em B usando o token de A';
  v_oc := public.comentar_hub_processo_contador(v_sa->>'token', v_procb, '[QA] invasao');
  v_os := public.mudar_status_hub_processo_contador(v_sa->>'token', v_procb, 'em_analise');
  v_od := public.registrar_documento_contador(v_sa->>'token', v_procb, '[QA] invasao', 'https://x.invalid/i.pdf');
  v_coms := (SELECT count(*) FROM public.hub_processo_comentarios WHERE processo_id=v_procb);
  v_stb := (SELECT status::text FROM public.hub_processos WHERE id=v_procb);
  IF (v_oc->>'error') IS NOT NULL AND (v_os->>'error') IS NOT NULL AND (v_od->>'error') IS NOT NULL
     AND v_coms=0 AND v_stb='enviado_contabilidade' THEN
    r.situacao:='passou'; r.obtido:='Todas as 3 escritas em B recusadas; B intacto.';
  ELSE r.situacao:='falhou'; r.obtido:=format('VAZAMENTO: oc=%s os=%s od=%s coms_b=%s status_b=%s',
        v_oc::text, v_os::text, v_od::text, v_coms, v_stb); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-022 (licao ISOL-006): resolver interno fechado a anon; RPCs abertas a anon
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_022()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_resolver_anon boolean; v_rpc_anon boolean;
BEGIN
  -- Somente leitura de catalogo de permissoes; nao escreve nada.
  r.passo_ordem:=1; r.passo_acao:='Auditar EXECUTE das funcoes para o papel anon'; r.esperado:='Resolver fechado; RPC publica aberta';
  v_resolver_anon := has_function_privilege('anon', 'public._hub_contador_link_valido(text)', 'EXECUTE');
  v_rpc_anon      := has_function_privilege('anon', 'public.buscar_contador_acesso_por_token(text)', 'EXECUTE');
  IF v_resolver_anon = false AND v_rpc_anon = true THEN
    r.situacao:='passou'; r.obtido:='anon NAO executa o resolver interno; executa a RPC publica (ISOL-006).';
  ELSE r.situacao:='falhou'; r.obtido:=format('resolver_anon=%s rpc_anon=%s', v_resolver_anon, v_rpc_anon); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- HUBCTD-023 (estrutura)
CREATE OR REPLACE FUNCTION public.qa_caso_hubctd_023()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_tab boolean; v_idx boolean; v_col boolean;
BEGIN
  r.passo_ordem:=1; r.passo_acao:='Conferir tabela, indice unico e coluna'; r.esperado:='Estrutura presente';
  v_tab := to_regclass('public.hub_contador_links') IS NOT NULL;
  v_idx := EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_hub_contador_links_tenant_contab');
  v_col := EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hub_processo_documentos' AND column_name='visivel_contabilidade');
  IF v_tab AND v_idx AND v_col THEN
    r.situacao:='passou'; r.obtido:='Tabela, indice unico (tenant,contabilidade) e coluna visivel_contabilidade presentes.';
  ELSE r.situacao:='falhou'; r.obtido:=format('tabela=%s indice=%s coluna=%s', v_tab, v_idx, v_col); END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao:='erro'; r.obtido:='Quebrou'; r.erro_tecnico:=SQLERRM; RETURN r; END $$;

-- ── Registrar ──
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('HUBCTD-001','qa_caso_hubctd_001'),('HUBCTD-002','qa_caso_hubctd_002'),('HUBCTD-003','qa_caso_hubctd_003'),
  ('HUBCTD-004','qa_caso_hubctd_004'),('HUBCTD-005','qa_caso_hubctd_005'),('HUBCTD-006','qa_caso_hubctd_006'),
  ('HUBCTD-010','qa_caso_hubctd_010'),('HUBCTD-011','qa_caso_hubctd_011'),('HUBCTD-012','qa_caso_hubctd_012'),
  ('HUBCTD-013','qa_caso_hubctd_013'),('HUBCTD-014','qa_caso_hubctd_014'),('HUBCTD-015','qa_caso_hubctd_015'),
  ('HUBCTD-020','qa_caso_hubctd_020'),('HUBCTD-021','qa_caso_hubctd_021'),('HUBCTD-022','qa_caso_hubctd_022'),
  ('HUBCTD-023','qa_caso_hubctd_023')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql=EXCLUDED.funcao_sql, ativo=true;

-- ── Rodar ──
DO $roda$ BEGIN PERFORM public.qa_rodar_bateria('manual', 'documentos-governanca/hub-contabil'); END $roda$;

-- ── Conferencia (so o ultimo SELECT aparece) ──
SELECT codigo, situacao::text, left(obtido, 70) AS resultado
FROM public.qa_resultados
WHERE execucao_id = (SELECT id FROM public.qa_execucoes ORDER BY iniciada_em DESC LIMIT 1)
  AND codigo LIKE 'HUBCTD-%'
ORDER BY (situacao='falhou') DESC, (situacao='erro') DESC, codigo;
