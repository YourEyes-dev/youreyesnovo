-- ============================================================================
-- TESTE (HOMOLOGAÇÃO) — reativação pontual de colaborador desligado para
-- ajuste de ponto de dia anterior ao desligamento, e volta ao desligado.
-- Ensaia a MESMA lógica dos scripts de produção (backup da linha + UPDATE de
-- status/inativo com os gatilhos de admissoes desligados) numa admissão de
-- teste. Termina em ROLLBACK: nada fica gravado.
-- Prova: (1) a ida e a volta não criam nada em tabelas laterais (eSocial,
-- onboarding, contratos, planos, obrigações, escala, banco); (2) com o cadastro
-- reativado, a trava do ponto aceita a batida do dia anterior ao desligamento;
-- (3) depois da volta, a linha da admissão é idêntica à foto.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TEMP TABLE t_alvo AS
SELECT a.id, a.tenant_id, a.cpf
  FROM public.admissoes a
 WHERE a.status::text = 'concluido'
   AND COALESCE(a.cpf, '') <> ''
   AND a.data_admissao <= CURRENT_DATE - 30
   AND NOT EXISTS (SELECT 1 FROM public.admissoes o
                    WHERE o.tenant_id = a.tenant_id AND o.cpf = a.cpf AND o.id <> a.id)
 ORDER BY a.created_at
 LIMIT 1;

-- Desliga a admissão de teste pelo caminho NORMAL (gatilhos ligados), como no real.
UPDATE public.admissoes a
   SET status = 'desligado', data_desligamento = CURRENT_DATE - 2, motivo_desligamento = 'teste'
  FROM t_alvo t WHERE a.id = t.id;

-- Contagem das tabelas laterais que gatilhos de admissoes costumam tocar.
CREATE TEMP TABLE t_contagem (etapa text, tabela text, n bigint);
CREATE OR REPLACE FUNCTION pg_temp.contar(p_etapa text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE r record; v_n bigint; v_id text; v_cpf text; v_tenant uuid;
BEGIN
  SELECT id::text, cpf, tenant_id INTO v_id, v_cpf, v_tenant FROM t_alvo;
  FOR r IN SELECT unnest(ARRAY['esocial_transmissoes','onboarding_processos','trilha_atribuicoes',
                               'trilha_progresso','contratos_experiencia','plano_acoes','cultura_acoes',
                               'empresa_obrigacoes','ponto_escala_atribuicoes','ponto_banco_horas_movimentacoes',
                               'documentos','folha_itens','audit_logs']) AS t
  LOOP
    IF to_regclass('public.' || r.t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('SELECT count(*) FROM public.%I x WHERE to_jsonb(x)::text LIKE %L OR to_jsonb(x)::text LIKE %L',
                   r.t, '%' || v_id || '%', '%' || v_cpf || '%') INTO v_n;
    INSERT INTO t_contagem VALUES (p_etapa, r.t, v_n);
  END LOOP;
  INSERT INTO t_contagem
  SELECT p_etapa, 'empresa_cadastro(md5)', ('x' || substr(md5(string_agg(to_jsonb(e)::text, '' ORDER BY e.id)), 1, 15))::bit(60)::bigint
    FROM public.empresa_cadastro e WHERE e.tenant_id = v_tenant;
END $f$;

SELECT pg_temp.contar('0_desligado');

-- Controle: desligado, a trava do ponto recusa a batida do dia anterior (o defeito).
DO $c$
DECLARE v_t record;
BEGIN
  SELECT * INTO v_t FROM t_alvo;
  BEGIN
    INSERT INTO public.ponto_marcacoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                        data_marcacao, hora_marcacao, tipo_marcacao)
    VALUES (v_t.tenant_id, v_t.id, '[TESTE]', v_t.cpf, CURRENT_DATE - 3, '17:00', 'saida');
    RAISE NOTICE 'TESTE controle_desligado: batida ACEITA (inesperado)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TESTE controle_desligado: batida RECUSADA: %', SQLERRM;
  END;
END $c$;

-- ===== IDA (mesma lógica do script 1 de produção) =====
CREATE TEMP TABLE t_foto AS
SELECT now() AS fotografado_em, a.* FROM public.admissoes a JOIN t_alvo t ON t.id = a.id;

ALTER TABLE public.admissoes DISABLE TRIGGER USER;
UPDATE public.admissoes a SET status = 'concluido', inativo = false
  FROM t_alvo t WHERE a.id = t.id AND a.status::text = 'desligado';
ALTER TABLE public.admissoes ENABLE TRIGGER USER;

SELECT pg_temp.contar('1_reativado');

-- A trava do ponto aceita batida do dia anterior ao desligamento?
DO $b$
DECLARE v_t record;
BEGIN
  SELECT * INTO v_t FROM t_alvo;
  BEGIN
    INSERT INTO public.ponto_marcacoes (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
                                        data_marcacao, hora_marcacao, tipo_marcacao)
    VALUES (v_t.tenant_id, v_t.id, '[TESTE]', v_t.cpf, CURRENT_DATE - 3, '17:00', 'saida');
    RAISE NOTICE 'TESTE trava_ponto: batida do dia anterior ACEITA com o cadastro reativado';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TESTE trava_ponto: batida RECUSADA: %', SQLERRM;
  END;
END $b$;

-- ===== VOLTA (mesma lógica do script 2 de produção) =====
ALTER TABLE public.admissoes DISABLE TRIGGER USER;
UPDATE public.admissoes a SET status = b.status, inativo = b.inativo, updated_at = b.updated_at
  FROM t_foto b WHERE a.id = b.id;
ALTER TABLE public.admissoes ENABLE TRIGGER USER;

SELECT pg_temp.contar('2_desligado_de_novo');

DO $r$
DECLARE r record; v_igual boolean; v_desl int;
BEGIN
  FOR r IN
    SELECT c0.tabela, c0.n AS antes, c1.n AS reativado, c2.n AS depois
      FROM t_contagem c0
      JOIN t_contagem c1 ON c1.tabela = c0.tabela AND c1.etapa = '1_reativado'
      JOIN t_contagem c2 ON c2.tabela = c0.tabela AND c2.etapa = '2_desligado_de_novo'
     WHERE c0.etapa = '0_desligado'
  LOOP
    RAISE NOTICE 'TESTE lateral % : antes=% reativado=% depois=% -> %', r.tabela, r.antes, r.reativado, r.depois,
      CASE WHEN r.antes = r.reativado AND r.reativado = r.depois THEN 'OK' ELSE 'MUDOU' END;
  END LOOP;
  SELECT (to_jsonb(a) = (to_jsonb(b) - 'fotografado_em')) INTO v_igual
    FROM public.admissoes a JOIN t_foto b ON b.id = a.id;
  RAISE NOTICE 'TESTE admissao_igual_a_foto: %', v_igual;
  SELECT count(*) INTO v_desl FROM pg_trigger t
   WHERE t.tgrelid = 'public.admissoes'::regclass AND NOT t.tgisinternal AND t.tgenabled = 'D';
  RAISE NOTICE 'TESTE gatilhos_desligados_no_fim: %', v_desl;
END $r$;

ROLLBACK;
