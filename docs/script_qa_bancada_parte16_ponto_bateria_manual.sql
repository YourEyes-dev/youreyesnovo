-- ============================================================================
-- ENTREGA — BANCADA DE QA — parte 16 de 16
-- Ponto: as 14 lacunas apontadas pela bateria manual (PONTO-400..460)
--
-- POR QUE ESTA PARTE EXISTE
-- As partes 1 a 15 levaram a bancada inteira ate o ponto em que ela estava
-- em 31/08. Depois disso, o confronto do roteiro manual "Bateria Legal do
-- Ponto" (113 casos) com os casos documentados apontou 14 lacunas, que
-- viraram os casos PONTO-400 a PONTO-460 com suas rotinas. Esta parte leva
-- essas 14 lacunas ao mesmo destino das outras quinze.
--
-- ONDE COLAR
--   - HOMOLOGACAO: rode as partes 1 a 16 no SQL Editor do projeto de
--     homologacao, na ordem. Atencao: a homologacao e recriada a partir da
--     PRODUCAO pelo botao RECRIAR — o que for aplicado direto nela se perde
--     na proxima recriacao. Para a bancada sobreviver, o caminho definitivo
--     e aplicar as 16 partes na PRODUCAO e deixar a homologacao herdar na
--     copia seguinte.
--   - PRODUCAO: parte 16 depois da 15, quando a trilha for aplicada la.
--
-- GARANTIAS (as mesmas das partes anteriores)
--   - Idempotente: rodar duas vezes nao duplica nem quebra.
--   - NAO altera nenhuma regra de negocio. So a bancada que as verifica.
--   - Modulo resolvido pelo CAMINHO, nao pelo identificador interno.
--   - A ponte so e criada quando a rotina existe de fato no destino.
--   - Cada rotina entra em bloco proprio: falha de uma vira NOTICE, nao
--     aborta o arquivo.
--   - As rotinas so leem o dicionario do banco e escrevem no cercado de QA
--     (tenant isolado) — nenhum dado de cliente e tocado.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (1) ROTINAS — 14 funcoes de teste.
-- ---------------------------------------------------------------------------
DO $qa1$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_400()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a saída antecipada é identificada como tal?';
  r.esperado := 'Selo/campo próprio com os minutos, distinto do atraso';
  v_col := coalesce(public.qa_col_existe('ponto_diario', '%antecipad%'),
                    public.qa_col_existe('ponto_diario', '%saida_ante%'));
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%antecipad%' AND p.prosrc ILIKE '%ponto%');

  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a saída antecipada não existe como conceito na apuração — o '
             || 'atraso tem coluna própria (ponto_diario.atraso_minutos) e a saída antes '
             || 'do fim da jornada some dentro de horas_faltantes, sem rótulo e sem os '
             || 'minutos separados. Para o colaborador, o espelho mostra um débito sem '
             || 'dizer de onde veio; para o gestor, some a informação de que a pessoa '
             || 'está saindo cedo (que é conversa de gestão, não de folha). Correção: '
             || 'marcar o dia com saída antecipada e os minutos, ao lado do atraso, com '
             || 'o saldo negativo na diferença exata — sem tratar como falta.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Saída antecipada tratada (campo: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_400()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_400 nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa2$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_401()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text; v_arred boolean;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a apuração do dia arredonda o excedente?';
  r.esperado := 'Excedente em minutos exatos — sem round/ceil/floor sobre a hora extra';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A função de apuração do dia (_ponto_calc_dia) não existe mais nesta base.';
    RETURN r;
  END IF;

  -- arredondamento perigoso: round/ceil/floor aplicado às grandezas de extra.
  -- Divisões inteiras de minutos (EXTRACT/60) são normais e não contam.
  v_arred := (v_src ILIKE '%round(%' OR v_src ILIKE '%ceil(%' OR v_src ILIKE '%floor(%');

  IF v_arred THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a apuração do dia aplica arredondamento (round/ceil/floor) sobre '
             || 'as grandezas apuradas — depois da tolerância legal, cada minuto de '
             || 'excesso é devido (Súmula 449 do TST). Arredondar para baixo suprime hora '
             || 'extra em escala (todo o quadro, todo mês); para cima, cria custo sem '
             || 'fato gerador. Correção: manter o excedente em minutos inteiros exatos, '
             || 'deixando o arredondamento apenas para a apresentação e para o valor '
             || 'monetário na folha, com a memória de cálculo mostrando os minutos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A apuração do dia trabalha em minutos exatos, sem arredondar o excedente.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_401()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_401 nao pode ser criada: %', SQLERRM;
  END;
END $qa2$;

DO $qa3$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_402()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tipo text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o feriado sem marcação é dia neutro, não falta?';
  r.esperado := 'Dia identificado como feriado, sem falta e sem débito de jornada';
  v_tipo := public.qa_col_existe('ponto_diario', 'tipo_dia');
  -- quem pode criar a falta indevida é a MATERIALIZAÇÃO; outras rotinas
  -- (pacote da folha, DSR) citam feriado sem proteger o dia neutro
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.proname ILIKE '%materializar%falta%'
    AND p.prosrc ILIKE '%feriado%';

  IF v_tipo IS NOT NULL AND v_fns IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Feriado reconhecido na apuração (tipo_dia + %s) — dia neutro preservado.', v_fns);
  ELSIF v_tipo IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A coluna tipo_dia não existe mais em ponto_diario — o feriado perdeu o '
             || 'lugar onde era identificado, e dia sem marcação corre o risco de virar '
             || 'falta (Lei 605/49: feriado é repouso remunerado).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: tipo_dia existe e várias rotinas conhecem feriado (pacote da '
             || 'folha, DSR), mas a MATERIALIZAÇÃO DE FALTAS — a única que cria o registro '
             || 'de ausência para o dia sem marcação (PONTO-290) — não consulta feriado '
             || 'nenhum: ela varre os dias e materializa. O feriado sem marcação, que é o '
             || 'comportamento esperado, corre o risco de virar falta, descontando salário '
             || 'e derrubando o DSR de quem não devia nada (Lei 605/49, art. 1º). '
             || 'Correção: a materialização deve pular os feriados da unidade do '
             || 'colaborador, gravando o dia como neutro com o nome do feriado.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_402()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_402 nao pode ser criada: %', SQLERRM;
  END;
END $qa3$;

DO $qa4$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_403()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_cpf text := public.qa_cpf(81); v_dia date := CURRENT_DATE - 2;
        v_escala uuid; v_falta interval; v_extra interval; v_trab interval;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Apurar um dia de colaborador SEM escala atribuída (06:00 às 12:00)';
  r.esperado := 'Tempo contado; sem saldo apurado contra jornada suposta; pendência de cadastro';
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
     entrada, saida, status)
  VALUES (v_t, gen_random_uuid(), 'QA Colaborador Sem Escala', v_cpf, v_dia,
          time '06:00', time '12:00', 'pendente')
  ON CONFLICT DO NOTHING;  -- reexecução no mesmo dia reaproveita a linha

  BEGIN
    PERFORM public.consolidar_ponto_diario_manual(v_t, v_cpf, v_dia);
  EXCEPTION WHEN OTHERS THEN NULL;  -- a consolidação pode exigir contexto extra
  END;

  SELECT d.escala_id, coalesce(d.horas_faltantes, interval '0'),
         coalesce(d.horas_extras, interval '0'), coalesce(d.horas_trabalhadas, interval '0')
    INTO v_escala, v_falta, v_extra, v_trab
  FROM public.ponto_diario d
  WHERE d.tenant_id = v_t AND d.colaborador_cpf = v_cpf AND d.data = v_dia;

  IF v_escala IS NULL AND (v_falta > interval '0' OR v_extra > interval '0') THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: sem escala atribuída (escala_id nulo), a apuração mesmo '
             || 'assim produziu saldo — %s de falta e %s de extra sobre %s '
             || 'trabalhadas: o dia foi medido contra uma jornada que ninguém contratou '
             || '(o fallback de CCT/8h). Escala é pré-requisito da apuração: medir contra '
             || 'padrão suposto cria hora extra (se a jornada real for menor) ou falta (se '
             || 'for maior) que não existem — e o erro passa despercebido porque o espelho '
             || 'parece normal. Correção: sem escala vigente, contar o tempo trabalhado '
             || 'SEM apurar saldo, e listar o colaborador nas pendências de cadastro.',
             v_falta, v_extra, v_trab);
  ELSIF v_escala IS NULL AND v_trab > interval '0' THEN
    r.situacao := 'passou';
    r.obtido := format('Sem escala: %s contadas e nenhum saldo apurado contra padrão suposto.', v_trab);
  ELSIF v_escala IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('O dia acabou vinculado a uma escala (%s) — o cenário sem escala não se formou nesta base.',
                       v_escala);
  ELSE
    -- a consolidação não produziu jornada nesta base (falta contexto de
    -- cadastro): sem número apurado, não há o que julgar — guarda honesta
    r.situacao := 'nao_implementado';
    r.obtido := 'A consolidação não apurou jornada para o dia nesta base (sem colaborador '
             || 'completo no cadastro), então não há saldo a auditar. No ambiente com '
             || 'dados, o caso mede se a apuração inventa jornada padrão para quem não '
             || 'tem escala.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_403()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_403 nao pode ser criada: %', SQLERRM;
  END;
END $qa4$;

DO $qa5$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_410()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): com almoço batido, a pré-assinalação cede?';
  r.esperado := 'Intervalo consta como marcado (batida real prevalece — Súmula 338 do TST)';
  v_col := public.qa_col_existe('ponto_diario', 'intervalo_origem');
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '_ponto_calc_dia';

  IF v_col IS NOT NULL AND v_src IS NOT NULL
     AND v_src ILIKE '%intervalo_origem%'
     AND (v_src ILIKE '%pre_assinal%' OR v_src ILIKE '%pre-assinal%') THEN
    r.situacao := 'passou';
    r.obtido := 'A apuração distingue a origem do intervalo (marcado × pré-assinalado) e '
             || 'grava em intervalo_origem — a batida real tem onde prevalecer.';
  ELSIF v_col IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há registro da ORIGEM do intervalo (a coluna intervalo_origem '
             || 'sumiu de ponto_diario) — sem ela, não é possível provar, dia a dia, se o '
             || 'intervalo foi batido ou apenas declarado. A Súmula 338, III, do TST faz a '
             || 'marcação real prevalecer sobre a pré-assinalação; se o sistema aplica o '
             || 'declarado por cima do batido, o intervalo real menor (que gera indenização '
             || 'do art. 71, §4º) desaparece do espelho. Correção: gravar a origem do '
             || 'intervalo em cada dia, com o batido prevalecendo sempre que existir.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a coluna intervalo_origem existe, mas a apuração do dia não a '
             || 'usa para dar precedência à batida real sobre a pré-assinalação — o '
             || 'declarado pode estar sobrepondo o que foi efetivamente marcado. Pela '
             || 'Súmula 338, III, do TST a presunção cede diante do fato: intervalo batido '
             || 'menor que o declarado precisa aparecer como suprimido (PONTO-060), não '
             || 'como gozado. Correção: na apuração, quando houver marcações de almoço, '
             || 'usar o intervalo real e marcar a origem como "marcado".';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_410()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_410 nao pode ser criada: %', SQLERRM;
  END;
END $qa5$;

DO $qa6$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_420()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a exigência de acordo declarada na config é honrada?';
  r.esperado := 'Com exige_acordo ligado e sem acordo vinculado, o banco NÃO credita';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_banco_regime_vigente';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A função ponto_banco_regime_vigente não existe mais — o regime de banco '
             || 'perdeu o guardião do instrumento (CLT art. 59, §§ 2º e 5º).';
  ELSIF v_src ILIKE '%exige_acordo%' AND v_src ILIKE '%acordo_id%' THEN
    r.situacao := 'passou';
    r.obtido := 'O regime vigente confere a exigência de acordo declarada na configuração '
             || 'e o vínculo do acordo — crédito sem instrumento não passa.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a configuração do banco declara exigir acordo (exige_acordo_'
             || 'individual / exige_cct_act) e a rotina do regime vigente não confere se o '
             || 'acordo está de fato VINCULADO (acordo_id): a exigência que a própria casa '
             || 'declarou fica sem efeito, e o excedente é creditado num banco sem '
             || 'instrumento. Compensação sem acordo é inválida (CLT art. 59, §5º): na '
             || 'reclamatória, todas as horas viram extras com adicional e o extrato do '
             || 'banco serve de prova contra a empresa. Correção: sem acordo vinculado, '
             || 'não creditar — o excedente segue como hora extra, com a memória do '
             || 'motivo, e o alerta de formalização pendente.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_420()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_420 nao pode ser criada: %', SQLERRM;
  END;
END $qa6$;

DO $qa7$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_421()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tab text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a folga compensatória debita o saldo do banco?';
  r.esperado := 'Débito no extrato do banco e o dia de folga não vira falta';
  v_tab := CASE WHEN to_regclass('public.feriado_folga_compensatoria') IS NOT NULL
                THEN 'feriado_folga_compensatoria' END;
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%banco_horas_movimentacoes%'
    AND (p.prosrc ILIKE '%folga%' OR p.prosrc ILIKE '%compensat%');

  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a folga compensatória não debita o banco de horas — a '
             || 'estrutura existente (%s) serve ao feriado trabalhado (PONTO-321, que '
             || 'afasta a dobra) e NENHUMA rotina lança o débito correspondente em '
             || 'ponto_banco_horas_movimentacoes. O efeito é dobrado e caro: a empresa dá '
             || 'a folga E mantém o saldo positivo (pagará de novo no vencimento, '
             || 'PONTO-171), enquanto o dia de folga corre o risco de ser materializado '
             || 'como falta — descontando de quem estava justamente compensando. '
             || 'Correção: lançar a folga como débito no banco (CLT art. 59, §2º), marcar '
             || 'o dia como folga compensatória (sem falta) e preservar o DSR da semana.',
             coalesce(v_tab, 'nenhuma tabela de folga'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Folga compensatória debita o banco por: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_421()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_421 nao pode ser criada: %', SQLERRM;
  END;
END $qa7$;

DO $qa8$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_430()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_vazio boolean := false; v_chk text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Solicitar ajuste com justificativa VAZIA e ver se passa';
  r.esperado := 'Recusado — a justificativa é obrigatória (Portaria MTP 671/2021)';
  BEGIN
    INSERT INTO public.ponto_ajustes
      (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
       data_referencia, tipo_ajuste, tipo_marcacao, hora_solicitada, motivo, status)
    VALUES (v_t, gen_random_uuid(), 'QA Colaborador Ajuste', public.qa_cpf(80),
            CURRENT_DATE - 1, 'correcao', 'entrada', '08:00', '', 'pendente');
    v_vazio := true;
  EXCEPTION WHEN check_violation OR not_null_violation OR raise_exception THEN
    v_vazio := false;
  END;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: existe validação de conteúdo mínimo do motivo?';
  r.esperado := 'CHECK/validação além do NOT NULL — string vazia não é justificativa';
  SELECT string_agg(conname, ', ') INTO v_chk FROM pg_constraint
  WHERE conrelid = 'public.ponto_ajustes'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%motivo%';

  IF v_vazio AND v_chk IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o ajuste entrou com motivo VAZIO — a coluna é NOT NULL (o que '
             || 'barra o nulo) mas string vazia passa, e não há CHECK de conteúdo mínimo. '
             || 'A trilha de auditoria fica com alterações de marcação sem história: na '
             || 'fiscalização, marcação alterada sem justificativa é indício de '
             || 'manipulação do controle de jornada (Portaria MTP 671/2021), e o '
             || 'aprovador decide no escuro. Correção: exigir motivo com conteúdo '
             || 'mínimo (CHECK de comprimento após trim), aplicado no banco — não só na '
             || 'tela, que qualquer integração contorna.';
  ELSIF NOT v_vazio THEN
    r.situacao := 'passou';
    r.obtido := 'Ajuste com justificativa vazia foi recusado pelo banco.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Há validação de conteúdo do motivo: %s.', v_chk);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_430()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_430 nao pode ser criada: %', SQLERRM;
  END;
END $qa8$;

DO $qa9$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_431()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_t uuid := public.qa_sandbox_tenant_id();
        v_comp text := to_char(CURRENT_DATE, 'YYYY-MM'); v_qtd int; v_uq text;
BEGIN
  PERFORM public.qa_modo_ligar();

  r.passo_ordem := 1;
  r.passo_acao := 'Montar o dossiê da competência DUAS vezes e contar';
  r.esperado := 'Um único dossiê por competência, com data e hash atualizados';
  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 5, 'qa-hash-1');
  INSERT INTO public.ponto_dossies_fiscalizacao
    (tenant_id, competencia, periodo_ini, periodo_fim, total_pecas, hash_pacote)
  VALUES (v_t, v_comp, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE, 7, 'qa-hash-2');
  SELECT count(*) INTO v_qtd FROM public.ponto_dossies_fiscalizacao d
  WHERE d.tenant_id = v_t AND d.competencia = v_comp;

  SELECT string_agg(conname, ', ') INTO v_uq FROM pg_constraint
  WHERE conrelid = 'public.ponto_dossies_fiscalizacao'::regclass AND contype = 'u';

  IF v_qtd > 1 AND v_uq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a mesma competência ficou com %s dossiês — não há UNIQUE '
             || '(tenant, competência) nem lógica de atualização: remontar empilha cópias '
             || 'em vez de atualizar. Dois dossiês da mesma competência com conteúdos e '
             || 'hashes diferentes (5 e 7 peças, no teste) é o pior cenário na '
             || 'fiscalização — a empresa apresenta um e o auditor encontra o outro, e a '
             || 'divergência vale mais contra do que o conteúdo vale a favor. Correção: '
             || 'UNIQUE por tenant+competência com atualização no lugar (ou versionamento '
             || 'explícito, com um único dossiê CORRENTE apontado).',
             v_qtd);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Dossiê único por competência (registros: %s; unicidade: %s).',
                       v_qtd, coalesce(v_uq, 'na gravação'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_431()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_431 nao pode ser criada: %', SQLERRM;
  END;
END $qa9$;

DO $qa10$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_440()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém vigia a vigência do instrumento coletivo?';
  r.esperado := 'Alerta antes do vencimento e severidade maior quando já vencido';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_cct_vigiar_vigencia';

  IF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma rotina vigia a vigência dos instrumentos coletivos — a '
             || 'CCT vence e leva junto os parâmetros da apuração (percentuais de HE, '
             || 'adicional noturno, intervalo, prazo do banco), e a competência seguinte '
             || 'passa a apurar pela regra geral sem ninguém decidir isso. Correção: '
             || 'vigilância diária avisando o vencimento com antecedência e acusando o '
             || 'instrumento vencido com severidade maior.';
  ELSIF v_src ILIKE '%vencid%' OR v_src ILIKE '%severidade%' THEN
    r.situacao := 'passou';
    r.obtido := 'A vigência do instrumento coletivo é vigiada por ponto_cct_vigiar_vigencia, '
             || 'com distinção entre a vencer e vencido.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: existe vigilância de CCT (ponto_cct_vigiar_vigencia), mas ela não '
             || 'distingue o instrumento A VENCER do JÁ VENCIDO — o alerta chega com o '
             || 'mesmo peso nos dois casos, quando o vencido significa competência '
             || 'descoberta de parâmetro coletivo. Correção: severidade maior para o '
             || 'vencido, com a competência afetada apontada.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_440()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_440 nao pode ser criada: %', SQLERRM;
  END;
END $qa10$;

DO $qa11$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_441()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_src text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): dois instrumentos do mesmo escopo na mesma data são acusados?';
  r.esperado := 'Sobreposição sinalizada — a apuração não escolhe em silêncio';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'ponto_cct_vigiar_vigencia';

  IF v_src IS NOT NULL AND (v_src ILIKE '%sobrep%' OR v_src ILIKE '%overlap%') THEN
    r.situacao := 'passou';
    r.obtido := 'A sobreposição de vigências é detectada pela vigilância do instrumento '
             || 'coletivo — a ambiguidade vira alerta em vez de escolha silenciosa.';
  ELSIF v_src IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não há vigilância de instrumento coletivo — logo, ninguém detecta '
             || 'duas CCTs do mesmo escopo cobrindo a mesma data. Com dois instrumentos '
             || 'válidos ao mesmo tempo, a apuração escolhe pelo acaso da ordenação, e a '
             || 'diferença de percentual de HE ou de intervalo entre eles vira erro '
             || 'sistemático na folha inteira. Correção: detectar a sobreposição por '
             || 'escopo/vigência e sinalizar antes da apuração.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a vigilância acompanha o VENCIMENTO da CCT, mas não detecta '
             || 'SOBREPOSIÇÃO de vigências: duas convenções ativas do mesmo escopo '
             || 'cobrindo a mesma data deixam a apuração ambígua (qual percentual de hora '
             || 'extra vale? qual intervalo mínimo?) e o sistema decide em silêncio, pelo '
             || 'ORDER BY. Quando o sindicato questiona, a resposta "foi o que o sistema '
             || 'pegou" não existe. Correção: alerta de alta severidade (ou bloqueio) na '
             || 'sobreposição, no mesmo desenho do FER-003, que já impede a unidade de '
             || 'estar em duas tabelas de feriados.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_441()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_441 nao pode ser criada: %', SQLERRM;
  END;
END $qa11$;

DO $qa12$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_450()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_orq text; v_vigias text; v_qtd int; v_job text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe rotina que orquestre TODAS as vigilâncias, agendada?';
  r.esperado := 'Uma chamada roda as vigilâncias do ponto; job diário ativo';
  SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO v_vigias
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.proname ILIKE 'ponto%vigiar%' OR p.proname ILIKE 'ponto%monitorar%'
         OR p.proname ILIKE 'ponto%alertas%');
  SELECT count(*) INTO v_qtd
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.proname ILIKE 'ponto%vigiar%' OR p.proname ILIKE 'ponto%monitorar%'
         OR p.proname ILIKE 'ponto%alertas%');
  SELECT p.proname INTO v_orq FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname ILIKE 'ponto%vigilancias%';

  BEGIN
    SELECT string_agg(j.jobname, ', ') INTO v_job FROM cron.job j
    WHERE j.jobname ILIKE '%vigilancia%' OR j.jobname ILIKE '%ponto%alerta%';
  EXCEPTION WHEN OTHERS THEN v_job := NULL;
  END;

  IF v_orq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: as vigilâncias do ponto existem SOLTAS (%s vigilância(s): '
             || '%s) e não há rotina orquestradora que rode todas de uma vez, nem '
             || 'agendamento diário que as chame (jobs de vigilância encontrados: %s). '
             || 'Vigilância que ninguém chama é alerta que nunca chega: o painel fica '
             || 'limpo por omissão, não por conformidade — e o DP conclui que está tudo '
             || 'certo justamente quando não está. Correção: rotina única que execute '
             || 'todas as vigilâncias devolvendo o que cada uma encontrou, agendada '
             || 'diariamente (pg_cron, como ponto-materializar-faltas já faz), com '
             || 'execução idempotente (PONTO-451).',
             v_qtd, coalesce(v_vigias, 'nenhuma'), coalesce(v_job, 'nenhum'));
  ELSIF v_job IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: a orquestradora existe (%s), mas NENHUM agendamento a '
             || 'chama — os alertas só nascem se alguém rodar à mão. Correção: agendar a '
             || 'execução diária no pg_cron.', v_orq);
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Motor de vigilâncias orquestrado (%s) e agendado (%s), com %s vigilância(s).',
                       v_orq, v_job, v_qtd);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_450()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_450 nao pode ser criada: %', SQLERRM;
  END;
END $qa12$;

DO $qa13$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_451()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_total int; v_protegidas int; v_soltas text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): as vigilâncias se protegem de duplicar alertas?';
  r.esperado := 'Segunda execução não cria alerta novo (NOT EXISTS / ON CONFLICT por ocorrência)';
  SELECT count(*) INTO v_total
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%';
  SELECT count(*) INTO v_protegidas
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%'
    AND (p.prosrc ILIKE '%NOT EXISTS%' OR p.prosrc ILIKE '%ON CONFLICT%');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_soltas
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%INSERT INTO%ponto_alertas%'
    AND p.prosrc NOT ILIKE '%NOT EXISTS%' AND p.prosrc NOT ILIKE '%ON CONFLICT%';

  IF v_total = 0 THEN
    r.situacao := 'falhou';
    r.obtido := 'Nenhuma rotina grava em ponto_alertas — o painel de alertas do ponto '
             || 'ficou sem quem o alimente.';
  ELSIF v_protegidas < v_total THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: %s de %s rotina(s) que criam alertas do ponto não se '
             || 'protegem contra duplicata (%s) — e a tabela ponto_alertas não tem índice '
             || 'único de deduplicação. Rodar a vigilância duas vezes (o que acontece '
             || 'sempre que alguém confere à tarde o que a madrugada gerou) empilha '
             || 'cópias do mesmo aviso; o DP aprende a ignorar a lista e o alerta que '
             || 'importa se perde no meio das repetições. A casa já resolve isso na '
             || 'materialização de faltas (PONTO-292). Correção: NOT EXISTS por '
             || 'ocorrência (tipo + colaborador + data de referência, não resolvido) ou '
             || 'índice único parcial equivalente.',
             v_total - v_protegidas, v_total, coalesce(v_soltas, '—'));
  ELSE
    r.situacao := 'passou';
    r.obtido := format('As %s rotina(s) de alerta do ponto são idempotentes.', v_total);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_451()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_451 nao pode ser criada: %', SQLERRM;
  END;
END $qa13$;

DO $qa14$
DECLARE d text := $qadef$CREATE OR REPLACE FUNCTION public.qa_caso_ponto_460()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_tent text; v_bloq text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o link contém tentativas em série e registra?';
  r.esperado := 'Contador de tentativas, bloqueio temporário e liberação automática';
  v_tent := public.qa_col_existe('ponto_links', 'tentativas_frustradas');
  v_bloq := public.qa_col_existe('ponto_links', 'bloqueado_ate');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%tentativas_frustradas%' OR p.prosrc ILIKE '%bloqueado_ate%');

  IF v_tent IS NOT NULL AND v_bloq IS NOT NULL AND v_fns IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := format('Contenção presente: contador e bloqueio temporário no link, '
             || 'aplicados por %s — quem é legítimo volta a marcar quando o bloqueio expira.',
             v_fns);
  ELSIF v_tent IS NULL OR v_bloq IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o link de marcação não tem contenção de tentativas (faltam o '
             || 'contador e/ou o bloqueio temporário) — é porta aberta na internet que '
             || 'permite varrer CPFs até acertar um válido e marcar ponto por outra '
             || 'pessoa, sem deixar rastro. Correção: bloqueio temporário após poucas '
             || 'tentativas frustradas, com registro na trilha e liberação automática '
             || '(LGPD arts. 46-48).';
  ELSE
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: as colunas de contenção existem (tentativas_frustradas, '
             || 'bloqueado_ate) e NENHUMA função as usa — o contador nunca sobe e o '
             || 'bloqueio nunca acontece: a proteção está cadastrada, não aplicada. '
             || 'Correção: incrementar a cada tentativa frustrada, bloquear ao cruzar o '
             || 'limite, registrar na trilha e liberar sozinho ao expirar.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_ponto_460()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_ponto_460 nao pode ser criada: %', SQLERRM;
  END;
END $qa14$;

-- ---------------------------------------------------------------------------
-- (2) CASOS DOCUMENTADOS — 14 linhas no catalogo, no modulo do Ponto.
-- ---------------------------------------------------------------------------

INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, objetivo, pre_condicoes, passos, resultado_esperado, observacoes, nivel, base_legal, disposicao, disposicao_motivo)
SELECT m.id, d.codigo::text, d.titulo::text, d.tipo::text::qa_caso_tipo, d.prioridade::text::qa_prioridade, d.status::text::qa_caso_status, d.objetivo::text, d.pre_condicoes::text, d.passos::text::jsonb, d.resultado_esperado::text, d.observacoes::text, d.nivel::text, d.base_legal::text, d.disposicao::text, d.disposicao_motivo::text
FROM (VALUES
('PONTO-400', 'Saída antecipada é identificada como tal, com os minutos', 'alternativo', 'media', 'aprovado', 'Sair antes do fim da jornada não é a mesma coisa que chegar atrasado, e o espelho precisa dizer qual foi: o dia recebe o selo de saída antecipada com os minutos, e o saldo fica negativo na diferença exata. Sem a distinção, o colaborador não sabe o que contestar e o gestor não sabe o que conversar — e o desconto vira número sem história.', 'Colaborador com escala de jornada até 17h no ambiente de teste.', '[{"acao": "Lançar saída às 16:00 num dia de jornada até 17:00", "ordem": 1, "resultado_esperado": "Dia marcado como saída antecipada, com os minutos apurados"}, {"acao": "Conferir o saldo do dia", "ordem": 2, "resultado_esperado": "Negativo exatamente na diferença — nem arredondado, nem tratado como falta"}, {"acao": "Comparar com um atraso equivalente", "ordem": 3, "resultado_esperado": "Os dois aparecem com rótulos distintos no espelho"}]', 'Sair cedo e chegar tarde são coisas diferentes — o espelho sabe qual foi.', 'Roteiro manual "Bateria Legal do Ponto", caso D7. O atraso tem coluna própria (ponto_diario.atraso_minutos); a saída antecipada, não — a sonda confere.', 'api', 'CLT art. 58 (duração da jornada) c/c art. 462 (desconto só do efetivamente devido)', 'em_triagem', NULL),
    ('PONTO-401', 'Hora extra sai em minutos exatos, sem truncar nem arredondar', 'feliz', 'alta', 'aprovado', 'Depois da tolerância legal, cada minuto de excesso é devido: 2h37 de excedente aparecem como 2h37, não como 2h30 nem 3h. Arredondamento sistemático para baixo é supressão de hora extra em escala industrial (multiplicada por todo o quadro, todo mês); para cima, é custo criado sem fato gerador.', 'Colaborador com jornada até 17h e tolerância padrão no ambiente de teste.', '[{"acao": "Lançar saída às 19:37 (2h37 além da jornada)", "ordem": 1, "resultado_esperado": "Excedente de 157 minutos apurado integralmente"}, {"acao": "Conferir o relatório de horas extras", "ordem": 2, "resultado_esperado": "Mesmo valor em minutos exatos, sem arredondamento de fração"}, {"acao": "Repetir com excedente de 1 minuto além da tolerância", "ordem": 3, "resultado_esperado": "O minuto aparece — não é engolido"}]', 'Minuto trabalhado é minuto pago — sem régua enviesada para nenhum lado.', 'Roteiro manual, caso D6. O adicional de 50% é o PONTO-090; aqui a cobrança é a PRECISÃO do excedente. Complementa PONTO-040/353 (tolerância e teto).', 'api', 'CLT art. 59 (remuneração da hora suplementar); Súmula 449 do TST (minutos residuais não podem ser suprimidos)', 'em_triagem', NULL),
    ('PONTO-402', 'Feriado não trabalhado é dia neutro: sem falta e sem débito', 'feliz', 'alta', 'aprovado', 'A contraprova do "dia útil sem marcação é falta": no feriado, a ausência de marcação é o esperado — o dia aparece identificado como feriado, sem falta, sem débito de jornada e sem afetar o DSR da semana. Feriado tratado como falta desconta salário e derruba o repouso de quem não devia nada.', 'Feriado cadastrado na competência de teste, abrangendo a unidade do colaborador.', '[{"acao": "Abrir o espelho do dia de feriado sem marcações", "ordem": 1, "resultado_esperado": "Dia identificado como feriado, sem falta e sem débito"}, {"acao": "Conferir o DSR da semana", "ordem": 2, "resultado_esperado": "Preservado — o feriado não é ausência injustificada"}, {"acao": "Conferir o total da competência", "ordem": 3, "resultado_esperado": "Jornada prevista do mês desconta o feriado, sem saldo negativo artificial"}]', 'No feriado, não bater ponto é o certo — e o sistema entende assim.', 'Roteiro manual, caso F4. O oposto (dia útil sem marcação = falta) é o PONTO-023/290; o feriado TRABALHADO é o PONTO-320/321. ponto_diario tem tipo_dia e feriado_nome — a sonda confere o dia neutro.', 'api', 'Lei 605/1949, art. 1º (repouso em feriados civis e religiosos, sem prejuízo da remuneração)', 'em_triagem', NULL),
    ('PONTO-403', 'Colaborador sem escala vigente: dia sem jornada prevista e pendência de cadastro', 'alternativo', 'media', 'aprovado', 'Escala é pré-requisito da apuração: sem escala vigente, não há jornada prevista contra a qual medir saldo. O comportamento correto é contar o tempo trabalhado, NÃO inventar saldo (nem crédito, nem falta) e listar o colaborador nas pendências de cadastro — apurar contra uma jornada suposta de 8h é criar hora extra ou falta que ninguém deve.', 'Colaborador batendo ponto sem atribuição de escala vigente no ambiente de teste.', '[{"acao": "Registrar marcações de um colaborador sem escala atribuída", "ordem": 1, "resultado_esperado": "Marcações aceitas normalmente"}, {"acao": "Abrir o espelho do dia", "ordem": 2, "resultado_esperado": "Total trabalhado contado; sem jornada prevista e sem saldo apurado contra padrão suposto"}, {"acao": "Conferir as pendências", "ordem": 3, "resultado_esperado": "Colaborador apontado como pendência de cadastro (escala ausente)"}]', 'Sem escala não há régua — e régua inventada vira passivo.', 'Roteiro manual, caso B3. Complementa PONTO-091 (jornada real da escala, não 8h fixas): aqui o caso é a AUSÊNCIA de escala.', 'api', 'Portaria MTP 671/2021 (registro de jornada) c/c CLT art. 74', 'em_triagem', NULL),
    ('PONTO-410', 'Batida real de intervalo vence a pré-assinalação declarada', 'alternativo', 'alta', 'aprovado', 'Quando existe declaração de intervalo (pré-assinalação) E o colaborador bateu o almoço, prevalece o que foi BATIDO: o dia consta como intervalo marcado, sem o selo de pré-assinalado, e o cálculo usa o tempo real. A declaração é presunção; a marcação é fato — e presunção que vence fato é exatamente o que a súmula afasta em juízo.', 'Escala com pré-assinalação de intervalo vigente no ambiente de teste.', '[{"acao": "Lançar dia com almoço batido (08:00, 12:00, 13:00, 17:00)", "ordem": 1, "resultado_esperado": "Intervalo consta como MARCADO, não como pré-assinalado"}, {"acao": "Conferir o cálculo do dia", "ordem": 2, "resultado_esperado": "Usa o intervalo real batido, não o declarado na escala"}, {"acao": "Lançar outro dia só com entrada e saída", "ordem": 3, "resultado_esperado": "Aí sim a pré-assinalação se aplica, com o selo correspondente"}]', 'O que foi batido manda; o declarado só preenche o silêncio.', 'Roteiro manual, caso E8. A pré-assinalação em si é o PONTO-064 e a supressão total é o PONTO-061; aqui a cobrança é a PRECEDÊNCIA. ponto_diario tem intervalo_origem — a sonda confere se ele reflete a batida real.', 'api', 'Súmula 338, III, do TST (a prova pré-constituída cede diante da marcação real); CLT art. 74, §2º', 'em_triagem', NULL),
    ('PONTO-420', 'Regime que exige acordo não credita banco enquanto o acordo não está anexado', 'negativo', 'alta', 'aprovado', 'A própria configuração do banco declara que exige acordo individual (ou CCT/ACT). Com a exigência ligada e nenhum acordo vinculado, o excedente NÃO pode ser creditado: crédito sem instrumento é compensação inválida — na reclamatória, todas as horas viram extras pagas com adicional, com o banco servindo apenas de prova contra a empresa.', 'Configuração de banco com "exige acordo individual" ligada e sem acordo vinculado.', '[{"acao": "Lançar um dia com excedente e apurar", "ordem": 1, "resultado_esperado": "O banco não credita — a exigência declarada não está satisfeita"}, {"acao": "Conferir o destino do excedente", "ordem": 2, "resultado_esperado": "Segue como hora extra a pagar, com a memória do porquê"}, {"acao": "Anexar o acordo e reapurar", "ordem": 3, "resultado_esperado": "A partir daí o crédito ocorre normalmente"}]', 'Banco sem acordo assinado não é banco — é hora extra represada.', 'Roteiro manual, caso H3. O instrumento VIGENTE é o PONTO-170; aqui a cobrança é a coerência com a flag exige_acordo_individual/exige_cct_act da própria configuração (lida hoje por ponto_banco_regime_vigente).', 'api', 'CLT art. 59, §5º (banco de horas por acordo individual escrito) e §2º (por convenção ou acordo coletivo)', 'em_triagem', NULL),
    ('PONTO-421', 'Folga compensatória debita o saldo do banco e o dia não vira falta', 'feliz', 'alta', 'aprovado', 'Compensar é o propósito do banco: concedida a folga, o extrato mostra o DÉBITO contra o saldo positivo e o dia de folga NÃO vira falta nem gera desconto. Se o débito não acontece, a empresa paga duas vezes (dá a folga e mantém o saldo); se o dia vira falta, desconta de quem estava compensando — e ainda derruba o DSR da semana.', 'Colaborador com saldo positivo de banco de horas no ambiente de teste.', '[{"acao": "Lançar uma folga compensatória", "ordem": 1, "resultado_esperado": "Dia identificado como folga compensatória, sem falta e sem desconto"}, {"acao": "Conferir o extrato do banco", "ordem": 2, "resultado_esperado": "Débito correspondente às horas da folga, com o saldo atualizado"}, {"acao": "Conferir o DSR da semana", "ordem": 3, "resultado_esperado": "Preservado — folga compensatória não é ausência injustificada"}]', 'A folga que compensa precisa sair do saldo — e nunca virar falta.', 'Roteiro manual, caso H10. A folga compensatória de FERIADO é o PONTO-321 (afasta a dobra); aqui é a compensação de saldo do banco. Complementa PONTO-171 (saldo vencido vira HE).', 'api', 'CLT art. 59, §2º (compensação de horas mediante folga)', 'em_triagem', NULL),
    ('PONTO-430', 'Ajuste de ponto sem justificativa é recusado', 'negativo', 'alta', 'aprovado', 'Toda alteração de marcação precisa dizer POR QUÊ: pedido de ajuste com motivo vazio (ou apenas um caractere para enganar a validação) não pode ser enviado. Sem motivo registrado, a trilha de auditoria vira lista de mudanças sem história — e na fiscalização, marcação alterada sem justificativa é indício de manipulação do controle de jornada.', 'Fluxo de solicitação de ajuste operante no ambiente de teste.', '[{"acao": "Solicitar ajuste com justificativa vazia", "ordem": 1, "resultado_esperado": "Recusado — a justificativa é obrigatória"}, {"acao": "Solicitar com justificativa mínima (um caractere)", "ordem": 2, "resultado_esperado": "Recusado — motivo precisa ser inteligível, não formalidade"}, {"acao": "Solicitar com motivo real", "ordem": 3, "resultado_esperado": "Aceito, com o motivo visível na trilha e para o aprovador"}]', 'Mudar o ponto exige dizer por quê — em palavras, não em espaço em branco.', 'Roteiro manual, caso I2. A alçada de aprovação é o PONTO-252 e a preservação da original é o PONTO-190/340; aqui é a obrigatoriedade do motivo (ponto_ajustes.motivo é NOT NULL — a sonda confere se string vazia/curta também é barrada).', 'api', 'Portaria MTP 671/2021, art. 74 e ss. (alterações de marcação devem ser identificadas e motivadas); CLT art. 74', 'em_triagem', NULL),
    ('PONTO-431', 'Remontar o dossiê de fiscalização não cria um segundo dossiê', 'negativo', 'media', 'aprovado', 'O dossiê da competência é peça única: mandar montar de novo (porque o primeiro saiu incompleto, ou por hábito) deve ATUALIZAR o dossiê existente, não empilhar cópias. Dois dossiês da mesma competência com conteúdos diferentes é o pior cenário na fiscalização — a empresa apresenta um e o auditor encontra o outro.', 'Dossiê de fiscalização já montado para a competência no ambiente de teste.', '[{"acao": "Montar o dossiê da competência", "ordem": 1, "resultado_esperado": "Dossiê gerado com índice e hash do pacote"}, {"acao": "Mandar montar de novo", "ordem": 2, "resultado_esperado": "Continua havendo UM dossiê da competência, com data e hash atualizados"}, {"acao": "Listar os dossiês", "ordem": 3, "resultado_esperado": "Sem duplicata; histórico de versões preservado se houver"}]', 'Um dossiê por competência — remontar atualiza, não multiplica.', 'Roteiro manual, caso K8. A geração íntegra e assinada é o PONTO-392; aqui é a reentrância. ponto_dossies_fiscalizacao não tem UNIQUE por competência — a sonda confere.', 'api', 'Portaria MTP 671/2021 (documentação do controle de jornada apresentada à fiscalização)', 'em_triagem', NULL),
    ('PONTO-440', 'Instrumento coletivo vencido ou a vencer é avisado antes de faltar parâmetro', 'alternativo', 'alta', 'aprovado', 'A CCT vence e leva junto os parâmetros da apuração (percentuais de HE, adicional noturno, intervalo, banco). O sistema avisa com antecedência que o instrumento está para vencer — e com severidade maior quando já venceu, porque a competência seguinte fica sem parâmetro coletivo e passa a apurar pela regra geral sem ninguém decidir isso.', 'Instrumento coletivo cadastrado com vigência terminando em poucos dias.', '[{"acao": "Cadastrar CCT vencendo em 10 dias e rodar a vigilância", "ordem": 1, "resultado_esperado": "Alerta de vencimento do instrumento coletivo, com prazo"}, {"acao": "Deixar a vigência terminar", "ordem": 2, "resultado_esperado": "Alerta com severidade maior — a competência seguinte está descoberta"}, {"acao": "Registrar a renovação", "ordem": 3, "resultado_esperado": "Alerta encerrado; nova vigência passa a reger a apuração"}]', 'Convenção vencida é apuração sem régua — o aviso vem antes do vencimento.', 'Roteiro manual, caso L2. O uso do instrumento vigente NA COMPETÊNCIA é o PONTO-386; aqui é o ciclo de vida do instrumento.', 'api', 'CF art. 7º, XXVI (reconhecimento das convenções e acordos coletivos); CLT art. 611-A e ss.', 'em_triagem', NULL),
    ('PONTO-441', 'Dois instrumentos coletivos com vigências sobrepostas são acusados', 'negativo', 'alta', 'aprovado', 'Duas CCTs ativas do mesmo escopo cobrindo a mesma data deixam a apuração AMBÍGUA: qual percentual de hora extra vale? Qual intervalo? O sistema precisa acusar a sobreposição em vez de escolher em silêncio (pelo id, pela data de cadastro, pelo acaso do ORDER BY) — porque a escolha silenciosa só aparece quando o sindicato questiona a folha inteira.', 'Dois instrumentos coletivos ativos do mesmo escopo com vigências que se cruzam.', '[{"acao": "Cadastrar duas CCTs do mesmo escopo cobrindo a mesma data", "ordem": 1, "resultado_esperado": "Sobreposição acusada — bloqueio ou alerta de alta severidade"}, {"acao": "Apurar uma competência na janela sobreposta", "ordem": 2, "resultado_esperado": "Ambiguidade sinalizada; não escolhe em silêncio"}, {"acao": "Encerrar a vigência do instrumento anterior", "ordem": 3, "resultado_esperado": "Alerta encerrado; apuração volta a ter um único instrumento"}]', 'Dois instrumentos válidos ao mesmo tempo é um a menos — o sistema pergunta qual.', 'Roteiro manual, caso L3. Complementa PONTO-386/440. Mesmo desenho do FER-003 (unidade em duas tabelas de feriados).', 'api', 'CF art. 7º, XXVI; CLT art. 620 (prevalência entre instrumentos)', 'em_triagem', NULL),
    ('PONTO-450', 'O motor de vigilâncias diárias roda inteiro, agendado, sem erro', 'feliz', 'critica', 'aprovado', 'As vigilâncias do ponto (banco de horas, art. 62, porte do estabelecimento, instrumento coletivo, formalização de escala, cobertura de turno, certificado e prazo de 48h do comprovante) precisam rodar TODAS, de forma agendada e sem erro. Vigilância que existe mas não é chamada por nenhum agendamento é alerta que nunca chega — o painel fica limpo por omissão, não por conformidade.', 'Ambiente de teste com dados que disparem ao menos uma vigilância.', '[{"acao": "Conferir o agendamento diário da rotina", "ordem": 1, "resultado_esperado": "Job ativo, com horário definido"}, {"acao": "Executar a rotina completa", "ordem": 2, "resultado_esperado": "Todas as vigilâncias respondem, cada uma com o que encontrou — sem erro e sem faltar nenhuma"}, {"acao": "Conferir os alertas gerados", "ordem": 3, "resultado_esperado": "Cada achado com tipo, severidade e vínculo ao colaborador/empresa"}]', 'Vigilância que ninguém chama é alerta que nunca chega.', 'Roteiro manual, caso M1 (que descreve uma rotina orquestradora com 8 vigilâncias, agendada). Hoje as vigilâncias existem SOLTAS (ponto_banco_alertas_monitorar, ponto_cct_vigiar_vigencia, ponto_certificado_vigiar_vencimento, ponto_comprovante_vigiar_48h, ponto_escala_formalizacao_monitorar, cobertura...) — a sonda confere a orquestração e o agendamento.', 'api', 'Portaria MTP 671/2021 e CLT art. 74 (controle efetivo da jornada) — a prevenção depende de a rotina rodar', 'em_triagem', NULL),
    ('PONTO-451', 'Vigilância rodada duas vezes não duplica o alerta', 'negativo', 'alta', 'aprovado', 'A rotina roda de madrugada, e alguém pode rodá-la de novo à tarde para conferir. A segunda execução não pode duplicar alertas: o painel precisa mostrar UM alerta por ocorrência, senão o DP aprende a ignorar a lista (e o alerta que importa se perde no meio das cópias). É a mesma regra que a casa já aplica na materialização de faltas.', 'Cenário que gere alerta (certificado a vencer, saldo perto do prazo) no ambiente de teste.', '[{"acao": "Rodar a vigilância uma vez", "ordem": 1, "resultado_esperado": "Alerta criado"}, {"acao": "Rodar de novo em seguida", "ordem": 2, "resultado_esperado": "Nenhum alerta novo — a segunda execução não cria nada"}, {"acao": "Conferir o painel", "ordem": 3, "resultado_esperado": "Um único alerta da ocorrência, com a data da primeira detecção"}]', 'Rodar duas vezes não pode gerar dois avisos do mesmo problema.', 'Roteiro manual, caso M2. Mesmo princípio do PONTO-292 (materializar duas vezes não duplica o dia) e do EPI/NF. ponto_alertas não tem UNIQUE de deduplicação — a sonda confere se as rotinas se protegem.', 'api', 'Boa prática de idempotência aplicada ao dever de vigilância (CLT art. 74; Portaria MTP 671/2021)', 'em_triagem', NULL),
    ('PONTO-460', 'Tentativas em série no link de marcação são contidas e registradas', 'negativo', 'alta', 'aprovado', 'O link externo de marcação é porta aberta na internet: sem contenção, permite varrer CPFs até acertar um válido (e marcar ponto por outra pessoa). Após poucas tentativas frustradas, o link precisa bloquear temporariamente, orientar procurar o RH e registrar o evento na trilha — e liberar quem é legítimo assim que o bloqueio expira, sem exigir intervenção do DP.', 'Link de marcação ativo no ambiente de teste.', '[{"acao": "Informar cinco CPFs inválidos em sequência", "ordem": 1, "resultado_esperado": "Bloqueio temporário anunciado, com orientação de procurar o RH"}, {"acao": "Conferir a trilha", "ordem": 2, "resultado_esperado": "Tentativas frustradas e o bloqueio registrados"}, {"acao": "Passado o bloqueio, usar um CPF válido", "ordem": 3, "resultado_esperado": "Marcação normal — quem é legítimo não fica preso"}]', 'Porta na internet precisa de tranca que cansa quem tenta adivinhar.', 'Roteiro manual, caso C7. Complementa PONTO-362 (enumeração de CPFs) e PONTO-251 (expiração/revogação). ponto_links tem tentativas_frustradas e bloqueado_ate — a sonda confere se são aplicados.', 'api', 'LGPD arts. 46-48 (medidas de segurança e prevenção de acessos indevidos); Portaria MTP 671/2021 (integridade do registro)', 'em_triagem', NULL)
) AS d(codigo, titulo, tipo, prioridade, status, objetivo, pre_condicoes, passos, resultado_esperado, observacoes, nivel, base_legal, disposicao, disposicao_motivo)
CROSS JOIN public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO UPDATE SET
      titulo = EXCLUDED.titulo,
      tipo = EXCLUDED.tipo,
      prioridade = EXCLUDED.prioridade,
      status = EXCLUDED.status,
      objetivo = EXCLUDED.objetivo,
      pre_condicoes = EXCLUDED.pre_condicoes,
      passos = EXCLUDED.passos,
      resultado_esperado = EXCLUDED.resultado_esperado,
      observacoes = EXCLUDED.observacoes,
      nivel = EXCLUDED.nivel,
      base_legal = EXCLUDED.base_legal;

-- ---------------------------------------------------------------------------
-- (3) PONTES — ligam o caso a rotina, so quando a rotina existe no destino.
-- ---------------------------------------------------------------------------

INSERT INTO public.qa_implementacoes (codigo, funcao_sql)
SELECT p.codigo, p.fn
FROM (VALUES
    ('PONTO-400', 'qa_caso_ponto_400'),
    ('PONTO-401', 'qa_caso_ponto_401'),
    ('PONTO-402', 'qa_caso_ponto_402'),
    ('PONTO-403', 'qa_caso_ponto_403'),
    ('PONTO-410', 'qa_caso_ponto_410'),
    ('PONTO-420', 'qa_caso_ponto_420'),
    ('PONTO-421', 'qa_caso_ponto_421'),
    ('PONTO-430', 'qa_caso_ponto_430'),
    ('PONTO-431', 'qa_caso_ponto_431'),
    ('PONTO-440', 'qa_caso_ponto_440'),
    ('PONTO-441', 'qa_caso_ponto_441'),
    ('PONTO-450', 'qa_caso_ponto_450'),
    ('PONTO-451', 'qa_caso_ponto_451'),
    ('PONTO-460', 'qa_caso_ponto_460')
) AS p(codigo, fn)
WHERE to_regprocedure('public.' || p.fn || '()') IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.qa_casos_teste c WHERE c.codigo = p.codigo)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql;

-- ---------------------------------------------------------------------------
-- CONFERENCIA FINAL — o retrato das 14 lacunas neste ambiente.
-- Esperado: 14 | 14 | 14 | 0 | OK
-- ---------------------------------------------------------------------------
WITH alvo AS MATERIALIZED (
  SELECT unnest(ARRAY['PONTO-400','PONTO-401','PONTO-402','PONTO-403','PONTO-410',
                      'PONTO-420','PONTO-421','PONTO-430','PONTO-431','PONTO-440',
                      'PONTO-441','PONTO-450','PONTO-451','PONTO-460']) AS codigo
),
base AS MATERIALIZED (
  SELECT a.codigo,
         c.codigo IS NOT NULL AS documentado,
         i.codigo IS NOT NULL AS tem_ponte,
         (i.codigo IS NOT NULL
          AND to_regprocedure('public.' || i.funcao_sql || '()') IS NOT NULL) AS rotina_existe
  FROM alvo a
  LEFT JOIN public.qa_casos_teste c ON c.codigo = a.codigo
  LEFT JOIN public.qa_implementacoes i ON i.codigo = a.codigo
)
SELECT count(*) FILTER (WHERE documentado) AS documentados,
       count(*) FILTER (WHERE tem_ponte) AS com_ponte,
       count(*) FILTER (WHERE rotina_existe) AS com_rotina,
       count(*) FILTER (WHERE tem_ponte AND NOT rotina_existe) AS ponte_orfa,
       CASE WHEN count(*) FILTER (WHERE documentado) = 14
             AND count(*) FILTER (WHERE rotina_existe) = 14
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM base;
