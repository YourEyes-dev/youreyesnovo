-- =====================================================================
-- ROLLBACK da entrega EC 141 F2a (validação ao salvar + assistente de
-- migração + aditivo + cancelamento em lote)
--
-- Só use se a entrega precisar ser desfeita. Roda inteiro em UMA transação,
-- é idempotente e devolve o COMPORTAMENTO de antes (o da F1):
--   1) cancela as migrações ainda ANTES da data (escalas, blocos e
--      atribuições voltam exatamente ao que eram; aditivos não assinados ficam
--      cancelados). Migração cuja data já chegou NÃO é desfeita (alteraria
--      dias já apurados): continua valendo como escala comum;
--   2) guarda cópia das 3 tabelas novas no schema privado backup;
--   3) remove o gatilho de validação ao salvar e as funções da F2a;
--   4) remove os casos PONTO-EC141-009..018 e devolve a rotina do
--      PONTO-EC141-007 ao corpo da F1.
-- As 3 tabelas novas ficam (inertes) com o histórico de auditoria. Nada de
-- dado de cliente é apagado. Conferência final em um SELECT.
-- =====================================================================

SET lock_timeout = '10s';

-- 1) Migrações antes da data: desfaz pelo próprio cancelamento.
DO $rb_mig$
DECLARE
  r record;
  v jsonb;
BEGIN
  IF to_regprocedure('public.ponto_ec141_migracao_cancelar(uuid,uuid,text,text,uuid)') IS NULL
     OR to_regclass('public.ponto_ec141_migracoes') IS NULL THEN
    RETURN;
  END IF;
  FOR r IN SELECT DISTINCT m.tenant_id FROM public.ponto_ec141_migracoes m
            WHERE m.status = 'aplicada' AND m.vigencia_inicio > CURRENT_DATE LOOP
    v := public.ponto_ec141_migracao_cancelar(r.tenant_id, NULL, NULL, 'Rollback da entrega EC 141 F2a', NULL);
    RAISE NOTICE 'Rollback EC141 F2a: conta %: %', r.tenant_id, v;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F2a: migracoes nao canceladas: %', SQLERRM;
END $rb_mig$;

-- 2) Cópia das tabelas novas (schema privado backup).
DO $rb_bkp$
BEGIN
  IF to_regnamespace('backup') IS NULL THEN
    RAISE NOTICE 'Schema backup ausente: copia NAO feita.';
    RETURN;
  END IF;
  IF to_regclass('public.ponto_ec141_migracoes') IS NOT NULL AND to_regclass('backup.ponto_ec141_migracoes_rb_20261031') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_ec141_migracoes_rb_20261031 AS SELECT * FROM public.ponto_ec141_migracoes';
  END IF;
  IF to_regclass('public.ponto_ec141_migracao_itens') IS NOT NULL AND to_regclass('backup.ponto_ec141_migracao_itens_rb_20261031') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_ec141_migracao_itens_rb_20261031 AS SELECT * FROM public.ponto_ec141_migracao_itens';
  END IF;
  IF to_regclass('public.ponto_ec141_aditivos') IS NOT NULL AND to_regclass('backup.ponto_ec141_aditivos_rb_20261031') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE backup.ponto_ec141_aditivos_rb_20261031 AS SELECT * FROM public.ponto_ec141_aditivos';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F2a: copia nao feita: %', SQLERRM;
END $rb_bkp$;

-- 3) Gatilho e funções da F2a.
DO $rb_fn$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_ponto_escala_zz_ec141_valida ON public.ponto_escalas';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_escala_ec141_valida_salvar()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_escala_ec141_validar_salvar(uuid, jsonb, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_escala_ec141_checar(public.ponto_escalas, public.ponto_escalas, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_migracao_aplicar(uuid, uuid, text, jsonb, boolean, uuid[])';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_migracao_cancelar(uuid, uuid, text, text, uuid)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_migracao_previa(uuid, uuid, text, jsonb, uuid[])';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_migracoes_lista(uuid, uuid)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_aditivos_lista(uuid, uuid, boolean)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_aditivo_documento(uuid)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_aditivo_render(jsonb)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.ponto_ec141_aditivo_modelo()';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_definir_modos(uuid, date, jsonb)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_fechar_orfaos(uuid)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_item_vivo(text, uuid, text)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_destino_min(text)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_coletivo_colaborador(uuid, uuid, uuid, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_colaboradores(uuid, uuid, date, uuid[])';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_proposta(public.ponto_escalas, integer, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_descrever_jornada(jsonb)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_tem_marco_ativo(uuid)';
    EXECUTE 'DROP FUNCTION IF EXISTS public._ponto_ec141_horas(integer)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_ec141_f2a_resumo()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_009()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_010()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_011()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_012()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_013()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_014()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_015()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_016()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_017()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_ec141_018()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_linha(jsonb, text)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_jornada(text, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_estado()';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_ativar(text, date)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_coletivo(boolean)';
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ec141_atribuir(uuid, text, date)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F2a: funcoes nao removidas: %', SQLERRM;
END $rb_fn$;

-- 4) Casos de teste da F2a fora do motor; PONTO-EC141-007 volta ao corpo da F1.
DO $rb_qa$
BEGIN
  IF to_regclass('public.qa_implementacoes') IS NOT NULL THEN
    DELETE FROM public.qa_implementacoes
     WHERE codigo IN ('PONTO-EC141-009','PONTO-EC141-010','PONTO-EC141-011','PONTO-EC141-012','PONTO-EC141-013',
                      'PONTO-EC141-014','PONTO-EC141-015','PONTO-EC141-016','PONTO-EC141-017','PONTO-EC141-018');
  END IF;
  IF to_regclass('public.qa_casos_teste') IS NOT NULL THEN
    DELETE FROM public.qa_casos_teste
     WHERE codigo IN ('PONTO-EC141-009','PONTO-EC141-010','PONTO-EC141-011','PONTO-EC141-012','PONTO-EC141-013',
                      'PONTO-EC141-014','PONTO-EC141-015','PONTO-EC141-016','PONTO-EC141-017','PONTO-EC141-018');
    UPDATE public.qa_casos_teste
       SET observacoes = regexp_replace(observacoes, ' EC 141 F2a \(31/10/2026\):.*$', '')
     WHERE codigo = 'PONTO-EC141-007' AND position('EC 141 F2a' IN COALESCE(observacoes, '')) > 0;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Rollback EC141 F2a: casos nao removidos: %', SQLERRM;
END $rb_qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_ponto_ec141_007()
RETURNS public.qa_retorno LANGUAGE plpgsql SET search_path TO 'public' AS $fn$
DECLARE
  r      public.qa_retorno;
  v_t    uuid := public.qa_sandbox_tenant_id();
  v_cpf  text := public.qa_cpf(6147);
  v_dia  date := CURRENT_DATE - 1;
  v_esc  uuid;
  v_aceita boolean := false;
  v_msg  text;
  v_n    int;
  v_val  jsonb;
  v_sal  jsonb;
BEGIN
  PERFORM public.qa_modo_ligar();
  PERFORM set_config('request.jwt.claims', '', true);
  -- 42h já em vigor para a conta; escala de 44h (acima do teto).
  PERFORM public.ponto_marco_ativar('EC141_42H', CURRENT_DATE - 30, '[QA] teto em vigor', v_t);
  v_esc := public.qa_ec141_escala(v_cpf, 528, ARRAY['segunda','terca','quarta','quinta','sexta'], DATE '2026-01-01');
  v_val := public.ponto_escala_validar_teto(v_esc, v_dia);

  r.passo_ordem := 1;
  r.passo_acao := 'Colaborador bate entrada e saída numa escala acima do teto legal ativo';
  r.esperado := 'As batidas são gravadas e apuradas; a validação só AVISA (bloqueia = false)';
  BEGIN
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '08:00', 'entrada');
    PERFORM public.qa_ponto_marca(v_cpf, '[QA-EC141] Colaborador', v_dia, TIME '17:48', 'saida');
    PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);
    v_aceita := true;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  v_n := (SELECT count(*) FROM public.ponto_marcacoes m
           WHERE m.tenant_id = v_t AND m.colaborador_cpf = v_cpf AND m.data_marcacao = v_dia);
  v_sal := public.qa_ec141_dia(v_cpf, v_dia);

  IF NOT v_aceita OR v_n <> 2 THEN
    r.situacao := 'falhou'; r.obtido := format('Batida recusada em escala acima do teto (%s marcação(ões)): %s', v_n, COALESCE(v_msg, ''));
  ELSIF COALESCE((v_val->>'bloqueia')::boolean, true) THEN
    r.situacao := 'falhou'; r.obtido := 'A validação do teto passou a bloquear: ' || COALESCE(v_val::text, 'nulo');
  ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_val->'avisos') a WHERE a->>'codigo' = 'acima_teto_semanal') THEN
    r.situacao := 'falhou'; r.obtido := 'A escala de 44h com teto de 42h não gerou o aviso: ' || COALESCE(v_val::text, 'nulo');
  ELSIF v_sal IS NULL THEN
    r.situacao := 'falhou'; r.obtido := 'O dia batido não foi apurado';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Batidas gravadas e apuradas; o teto de 42h gerou só o aviso (sem bloqueio).';
  END IF;
  r.detalhe := jsonb_build_object('validacao', v_val, 'dia', v_sal);
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $fn$;

-- Conferência (um SELECT).
SELECT
  NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'trg_ponto_escala_zz_ec141_valida'
                 AND t.tgrelid = 'public.ponto_escalas'::regclass) AS gatilho_validacao_removido,
  (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN (
      'ponto_escala_ec141_checar', 'ponto_escala_ec141_validar_salvar', 'ponto_escala_ec141_valida_salvar',
      'ponto_ec141_migracao_previa', 'ponto_ec141_migracao_aplicar', 'ponto_ec141_migracao_cancelar')) AS funcoes_f2a_restantes_deve_ser_0,
  (SELECT count(*) FROM public.ponto_ec141_migracoes WHERE status = 'aplicada' AND vigencia_inicio > CURRENT_DATE) AS migracoes_antes_da_data_deve_ser_0,
  (SELECT count(*) FROM public.qa_casos_teste WHERE codigo LIKE 'PONTO-EC141-%') AS casos_ec141_deve_ser_8,
  position('F2a' IN pg_get_functiondef('public.qa_caso_ponto_ec141_007()'::regprocedure)) = 0 AS caso_007_restaurado,
  EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'trg_ponto_escala_arquiva_versao'
             AND t.tgrelid = 'public.ponto_escalas'::regclass AND t.tgenabled <> 'D') AS gatilho_versao_f1_ligado;
