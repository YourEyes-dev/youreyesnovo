-- ============================================================================
-- ENTREGA — QA do EPI: caso EPI-049 (evidência em bucket privado) e sua rotina
--
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de TESTE depois do script
-- script_epi_evidencias_bucket_privado.sql. Só documenta o caso e cria a
-- rotina (auditoria somente leitura do catálogo); não altera comportamento nem
-- dado. UMA transação, idempotente, sem criar tabela.
-- ============================================================================

-- =========================================================
-- QA — EPI-049: foto do rosto e assinatura da entrega moram em bucket PRIVADO,
-- só da empresa dona, e não podem ser trocadas nem apagadas depois.
--
-- O defeito: o wizard gravava a foto (biometria, dado sensível, LGPD art. 11) e a
-- assinatura no bucket epi-signatures, público, com política de leitura aberta
-- (USING bucket_id = ...): qualquer pessoa com o link vê. Esse bucket é dividido
-- com PDI e Experiência, então não foi tornado privado; a evidência de EPI vai
-- para epi-evidencias.
--
-- A rotina é uma AUDITORIA do catálogo (bucket e políticas): o Supabase real
-- bloqueia DELETE direto em storage.objects, então criar e apagar arquivo de
-- teste não é possível. O comportamento (anônimo, outra empresa, mesma empresa)
-- foi conferido numa réplica na entrega desta correção.
--
-- Só documenta e liga o teste; não altera comportamento. Idempotente.
-- =========================================================

SET lock_timeout = '10s';

DO $doc$
DECLARE v_mod uuid;
BEGIN
  v_mod := (SELECT id FROM public.qa_modulos WHERE path = 'saude-ocupacional/epi');
  IF v_mod IS NULL THEN RAISE EXCEPTION 'Módulo saude-ocupacional/epi não encontrado.'; END IF;

  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'EPI-049',
   'Foto do rosto e assinatura da entrega ficam em bucket privado, só da empresa, sem troca nem exclusão',
   'negativo', 'alta', 'aprovado', 'api',
   'LGPD arts. 5º, II e 11 (dado biométrico é sensível) e 46 (medidas de segurança); EPI-041; Lei 14.063/2020 (integridade da evidência)',
   'A foto do colaborador na entrega é biometria. Em bucket público, qualquer pessoa com o link a vê. A evidência também não pode ser trocada ou apagada depois de gravada, ou deixa de provar a entrega.',
   'Ambiente com as migrations aplicadas.',
   '[{"ordem":1,"acao":"Conferir o bucket epi-evidencias","resultado_esperado":"Existe e NÃO é público"},
     {"ordem":2,"acao":"Conferir as políticas do bucket","resultado_esperado":"Leitura e gravação só para usuário autenticado da mesma empresa (pasta = empresa) e com acesso ao módulo EPI; nenhuma política para anônimo; nenhuma de UPDATE ou DELETE"}]'::jsonb,
   'Evidência de EPI em bucket privado, restrita à empresa e imutável.',
   'Guarda a correção C4 (opção A). As fichas antigas continuam no bucket público epi-signatures até a migração dos arquivos (job à parte, pela API de storage).')
  ON CONFLICT (codigo) DO UPDATE SET
    titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;
END $doc$;

CREATE OR REPLACE FUNCTION public.qa_caso_epi_049()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $fn$
DECLARE r public.qa_retorno; v_publico boolean; v_existe boolean;
        v_anon int; v_alteracao int; v_leitura_ok int; v_gravacao_ok int;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o bucket epi-evidencias existe e é privado?';
  r.esperado := 'Bucket existente e não público';
  v_existe := EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id = 'epi-evidencias');
  v_publico := COALESCE((SELECT b.public FROM storage.buckets b WHERE b.id = 'epi-evidencias'), false);

  IF NOT v_existe THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há bucket epi-evidencias. A foto do rosto e a assinatura da entrega seguem no bucket público epi-signatures (leitura aberta a qualquer pessoa com o link).';
    RETURN r;
  ELSIF v_publico THEN
    r.situacao := 'falhou';
    r.obtido := 'O bucket epi-evidencias está público: a foto do rosto fica acessível por link.';
    RETURN r;
  END IF;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA (somente leitura): quem lê, grava, altera e apaga no bucket?';
  r.esperado := 'Só autenticado da empresa com o módulo EPI lê e grava; ninguém altera nem apaga; anônimo nada';

  -- Políticas que citam o bucket, por comando (r SELECT, a INSERT, w UPDATE, d DELETE, * ALL).
  v_anon := (SELECT count(*) FROM pg_policy p
              WHERE p.polrelid = 'storage.objects'::regclass
                AND (pg_get_expr(p.polqual, p.polrelid) ILIKE '%epi-evidencias%'
                     OR pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%epi-evidencias%')
                AND (p.polroles = '{0}'::oid[]
                     OR EXISTS (SELECT 1 FROM pg_roles ro WHERE ro.oid = ANY (p.polroles) AND ro.rolname = 'anon')));
  v_alteracao := (SELECT count(*) FROM pg_policy p
                   WHERE p.polrelid = 'storage.objects'::regclass
                     AND p.polcmd IN ('w', 'd', '*')
                     AND (pg_get_expr(p.polqual, p.polrelid) ILIKE '%epi-evidencias%'
                          OR pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%epi-evidencias%'));
  v_leitura_ok := (SELECT count(*) FROM pg_policy p
                    WHERE p.polrelid = 'storage.objects'::regclass AND p.polcmd = 'r'
                      AND pg_get_expr(p.polqual, p.polrelid) ILIKE '%epi-evidencias%'
                      AND pg_get_expr(p.polqual, p.polrelid) ILIKE '%get_user_tenant_id%'
                      AND pg_get_expr(p.polqual, p.polrelid) ILIKE '%perfil_permite_modulo%');
  v_gravacao_ok := (SELECT count(*) FROM pg_policy p
                     WHERE p.polrelid = 'storage.objects'::regclass AND p.polcmd = 'a'
                       AND pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%epi-evidencias%'
                       AND pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%get_user_tenant_id%'
                       AND pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%perfil_permite_modulo%');

  IF v_anon > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('%s política(s) do bucket valem para anônimo/público; a evidência não pode ser aberta.', v_anon);
  ELSIF v_alteracao > 0 THEN
    r.situacao := 'falhou';
    r.obtido := format('%s política(s) permitem alterar ou apagar a evidência; a prova precisa ser imutável.', v_alteracao);
  ELSIF v_leitura_ok < 1 OR v_gravacao_ok < 1 THEN
    r.situacao := 'falhou';
    r.obtido := format('Falta restringir por empresa e por perfil: leitura correta=%s (esperado 1), gravação correta=%s (esperado 1).',
                       v_leitura_ok, v_gravacao_ok);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Bucket epi-evidencias privado; leitura e gravação só da empresa dona com acesso ao módulo EPI; sem política para anônimo; sem alteração nem exclusão.';
  END IF;
  r.detalhe := jsonb_build_object('politicas_anonimo', v_anon, 'politicas_alteracao', v_alteracao,
                                  'leitura_ok', v_leitura_ok, 'gravacao_ok', v_gravacao_ok);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('EPI-049', 'qa_caso_epi_049')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- Conferência final (o editor mostra só este resultado):
SELECT
  EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'EPI-049') AS caso_documentado,
  EXISTS (SELECT 1 FROM public.qa_implementacoes WHERE codigo = 'EPI-049'
           AND funcao_sql = 'qa_caso_epi_049') AS rotina_registrada,
  (SELECT count(*) FROM pg_proc WHERE proname = 'qa_caso_epi_049') AS funcao_criada,
  NULL::text AS erro_tecnico;

-- Para desfazer:
--   DELETE FROM public.qa_implementacoes WHERE codigo = 'EPI-049';
--   DROP FUNCTION IF EXISTS public.qa_caso_epi_049();
--   DELETE FROM public.qa_casos_teste WHERE codigo = 'EPI-049';
