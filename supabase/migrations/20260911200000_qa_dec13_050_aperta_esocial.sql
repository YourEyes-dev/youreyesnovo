-- =========================================================
-- QA DEC13-050 — aperta a sonda do eSocial do 13º
--
-- A sonda dava "passou" cedo demais: aceitava QUALQUER função cujo texto
-- contivesse "S-1200" ou "anual", e procurava a unicidade apenas entre
-- CONSTRAINTs — sem enxergar índice único parcial. Com isso o caso ficou
-- verde antes de existir qualquer geração de evento do 13º, que é
-- exatamente o achado que ele deveria acusar.
--
-- Agora ela cobra o que a Entrega 5 entrega, pelo nome: a validação
-- prévia, a montagem dos eventos e a anti-duplicidade por origem —
-- aceitando tanto constraint quanto índice único.
-- =========================================================
CREATE OR REPLACE FUNCTION public.qa_caso_dec13_050()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE
  r public.qa_retorno;
  v_unq       text;
  v_validar   boolean;
  v_gerar     boolean;
  v_anual     boolean;
  v_faltando  text[] := ARRAY[]::text[];
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folha anual do 13º tem eventos, validação prévia e anti-duplicidade?';
  r.esperado := 'S-1200 (apuração anual, indApuracao=2) e S-1210 (pagamentos), validação antes do envio e unicidade por origem';

  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;

  -- unicidade: vale constraint OU índice único (o índice parcial é o que
  -- permite refazer o evento depois de um erro ou cancelamento)
  SELECT string_agg(nome, ', ') INTO v_unq FROM (
    SELECT conname AS nome FROM pg_constraint
     WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u'
    UNION
    SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = 'public.esocial_transmissoes'::regclass
       AND i.indisunique AND NOT i.indisprimary
  ) u;

  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_validar')
    INTO v_validar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar')
    INTO v_gerar;
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'decimo_terceiro_esocial_gerar'
                    AND p.prosrc LIKE '%indApuracao>2<%')
    INTO v_anual;

  IF NOT v_validar THEN v_faltando := array_append(v_faltando, 'validação prévia do 13º (decimo_terceiro_esocial_validar)'); END IF;
  IF NOT v_gerar   THEN v_faltando := array_append(v_faltando, 'montagem dos eventos (decimo_terceiro_esocial_gerar)'); END IF;
  IF v_gerar AND NOT v_anual THEN v_faltando := array_append(v_faltando, 'apuração ANUAL no S-1200 (indApuracao = 2)'); END IF;
  IF v_unq IS NULL THEN v_faltando := array_append(v_faltando, 'anti-duplicidade em esocial_transmissoes'); END IF;

  IF array_length(v_faltando, 1) IS NOT NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (terceiro da série ADM-093/FERIAS-081, agora pela folha ANUAL): falta '
             || array_to_string(v_faltando, '; ') || '. A competência anual tem regra própria de '
             || 'retificação e prazo; sem os eventos, o 13º pago não existe para o governo — e a '
             || 'DCTFWeb de dezembro não fecha com a folha. Correção: geração dos dois eventos no '
             || 'fechamento (apuração e pagamento), chave natural (vínculo + tipo + competência '
             || 'anual) e tradução de rejeição em instrução, nunca reenvio às cegas.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes: validação prévia e montagem do S-1200 anual e do S-1210, com unicidade (%s).', v_unq);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
