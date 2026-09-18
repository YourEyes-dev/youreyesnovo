-- ============================================================================
-- QA — LOTE 3 (ADM): entregar 17 rotinas de caso de Admissao a producao.
-- Funcoes qa_caso_adm_* do dev que nao chegaram a producao (drift). Aditivo
-- (CREATE OR REPLACE) + vinculo. Read-only por natureza. Conferencia agrupa.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.qa_caso_adm_020()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cpf text := public.qa_cpf(7020);
        v_aceitou_100 boolean := false; v_aceitou_105 boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar contrato de experiência com primeiro período de 100 dias';
  r.esperado := 'Recusado — o art. 445, parágrafo único, limita a 90 dias somados';
  BEGIN
    INSERT INTO public.contratos_experiencia
      (tenant_id, colaborador_nome, colaborador_cpf, data_admissao,
       duracao_primeiro_periodo, data_fim_primeiro_periodo, status)
    VALUES (public.qa_sandbox_tenant_id(), 'QA Experiência 100', v_cpf,
            CURRENT_DATE, 100, CURRENT_DATE + 99, 'ativo');
    v_aceitou_100 := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_100 := false; END;

  r.passo_ordem := 2;
  r.passo_acao := 'Gravar experiência de 60 dias prorrogada por mais 45 (105 no total)';
  r.esperado := 'Recusado — a soma período + prorrogação também respeita o teto de 90';
  BEGIN
    INSERT INTO public.contratos_experiencia
      (tenant_id, colaborador_nome, colaborador_cpf, data_admissao,
       duracao_primeiro_periodo, data_fim_primeiro_periodo,
       prorrogado, duracao_prorrogacao, data_inicio_prorrogacao, data_fim_prorrogacao, status)
    VALUES (public.qa_sandbox_tenant_id(), 'QA Experiência 105', public.qa_cpf(7021),
            CURRENT_DATE, 60, CURRENT_DATE + 59,
            true, 45, CURRENT_DATE + 60, CURRENT_DATE + 104, 'prorrogado');
    v_aceitou_105 := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou_105 := false; END;

  IF v_aceitou_100 OR v_aceitou_105 THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: o banco aceitou experiência fora do teto legal (100 dias '
             || 'diretos: %s; 60+45=105 com prorrogação: %s) — contratos_experiencia não tem '
             || 'NENHUM CHECK sobre as durações. Experiência acima de 90 dias descaracteriza '
             || 'o prazo: o contrato vira indeterminado por força de lei, com as verbas da '
             || 'conversão. O ponto estrutural bom: "prorrogado" é boolean — a SEGUNDA '
             || 'prorrogação não tem onde existir (art. 451 atendido por desenho). Correção: '
             || 'CHECK duracao_primeiro_periodo BETWEEN 1 AND 90 e '
             || 'CHECK (coalesce(duracao_primeiro_periodo,0) + coalesce(duracao_prorrogacao,0)) <= 90.',
             CASE WHEN v_aceitou_100 THEN 'aceito' ELSE 'recusado' END,
             CASE WHEN v_aceitou_105 THEN 'aceito' ELSE 'recusado' END);
  ELSE
    r.situacao := 'passou';
    r.obtido := 'Os dois contratos acima de 90 dias foram recusados; a prorrogação única já é '
             || 'estrutural (campo booleano).';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_021()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_col text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o contrato por prazo determinado tem data de término controlada?';
  r.esperado := 'Campo de fim do contrato + validação do teto de 2 anos e da prorrogação única';
  v_col := coalesce(public.qa_col_existe('admissoes', '%fim_contrato%'),
                    public.qa_col_existe('admissoes', '%data_fim%'),
                    public.qa_col_existe('admissoes', '%prazo_determinado%'));
  -- funções que tratem o TETO/prorrogação do determinado (não basta a palavra
  -- "determinado", que aparece em textos como CLT_PRAZO_INDETERMINADO)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%determinado%' AND p.prosrc ILIKE '%prorrog%'
    AND p.proname NOT ILIKE '%afastamento%';
  IF v_col IS NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a modalidade "prazo determinado" não tem onde viver — admissoes.tipo_contrato '
             || 'é texto livre e não existe campo de data de término nem função que valide o teto '
             || 'de 2 anos e a prorrogação única do art. 451 (só a EXPERIÊNCIA tem tabela própria, '
             || 'contratos_experiencia). Um determinado de 30 meses entra sem resistência e, '
             || 'vencido o prazo sem controle, o contrato segue como se indeterminado fosse — '
             || 'sem alerta de término, sem termo. Correção: estruturar prazo determinado como a '
             || 'experiência (fim, prorrogação única, alertas de vencimento).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Controle presente (campo: %s; funções: %s).',
                       coalesce(v_col, '—'), coalesce(v_fns, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_022()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a modalidade intermitente tem estrutura própria?';
  r.esperado := 'Valor da hora (≥ mínimo e ≥ pares da função) e cláusulas de convocação/aceite';
  v_est := coalesce(public.qa_col_existe(NULL, '%intermitente%'),
                    public.qa_col_existe(NULL, '%valor_hora%'),
                    public.qa_fns_com('%intermitente%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o contrato intermitente não existe no banco — nenhuma coluna ou função '
             || 'trata a modalidade. O art. 452-A exige contrato ESCRITO com o valor da hora '
             || '(nunca inferior ao mínimo horário nem ao dos demais na mesma função) e o rito '
             || 'de convocação com 3 dias de antecedência. Se a empresa admitir um intermitente '
             || 'hoje, ele entra como texto livre em tipo_contrato, sem as cláusulas que '
             || 'sustentam a modalidade — e sem elas o vínculo tende à forma comum. Correção: '
             || 'estrutura mínima (valor_hora + modelo de contrato próprio) antes de ofertar a '
             || 'modalidade. Cláusulas finais são [VAL] jurídico (seção 30 do documento).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Estrutura presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_030()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar admissão de candidato com 15 anos em contrato comum (não aprendiz)';
  r.esperado := 'Recusado — menor de 16 só entra na condição de aprendiz (a partir dos 14)';
  BEGIN
    INSERT INTO public.admissoes
      (tenant_id, nome_completo, cpf, cargo, data_nascimento, data_admissao, tipo_contrato)
    VALUES (public.qa_sandbox_tenant_id(), 'QA Menor Quinze', public.qa_cpf(7030),
            'Auxiliar', CURRENT_DATE - interval '15 years', CURRENT_DATE + 10,
            'CLT_PRAZO_INDETERMINADO');
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;

  IF v_aceitou THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o banco aceitou admissão COMUM de um candidato de 15 anos — nada '
             || 'valida a idade na data de início contra a modalidade. A CF (art. 7º, XXXIII) '
             || 'proíbe qualquer trabalho antes dos 16, salvo aprendiz a partir dos 14: essa '
             || 'admissão é nula e expõe a empresa a autuação imediata. Correção: validação '
             || 'idade × modalidade na gravação (16+ para contrato comum; 14-15 somente '
             || 'aprendiz, com a documentação do programa), bloqueando na fonte, não na tela.';
  ELSE
    r.situacao := 'passou';
    r.obtido := 'A admissão comum do menor de 16 foi recusada na gravação.';
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_031()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguém cruza a idade do admitido com riscos da função e turno?';
  r.esperado := 'Menor de 18 barrado em jornada noturna e em função insalubre/perigosa (CLT arts. 404/405)';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_fns
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%data_nascimento%'
    AND (p.prosrc ILIKE '%noturn%' OR p.prosrc ILIKE '%insalubr%' OR p.prosrc ILIKE '%perigos%');
  IF v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: nenhuma função cruza data_nascimento com risco da função ou turno — '
             || 'um colaborador de 17 anos pode ser alocado em escala noturna ou em função '
             || 'insalubre/perigosa sem nenhum aviso. A vedação é absoluta (CF art. 7º XXXIII; '
             || 'CLT arts. 404/405): não há adicional que a compense, e o SST já cadastra os '
             || 'riscos por função — falta só o cruzamento na admissão e na troca de '
             || 'função/escala. Correção: trava idade × (risco da função, período da escala) '
             || 'nos dois momentos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cruzamento presente em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_040()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_cols text; v_fns text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): os campos de cota de aprendiz são calculados por alguém?';
  r.esperado := 'Base × 5%..15% por estabelecimento, com o realizado atualizado pelas admissões';
  v_cols := public.qa_col_existe('empresa_cadastro', 'aprendiz%');
  v_fns := public.qa_fns_com('%aprendiz%');
  IF v_cols IS NOT NULL AND v_fns IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: os campos existem (%s) e NENHUMA função os calcula ou atualiza '
             || '— são decorativos, preenchidos à mão. Compare com a cota de PcD, que tem o '
             || 'gatilho recalcular_cota_pcd: a de aprendiz (art. 429, 5%% a 15%% das funções '
             || 'que demandam formação) ficou sem motor. E a admissão não marca ninguém como '
             || 'aprendiz (tipo_contrato é texto livre), então o "realizado" não tem fonte. '
             || 'Correção: espelhar o desenho da cota de PcD — cálculo por faixa no gatilho e '
             || 'realizado derivado das admissões de aprendiz ativas.', v_cols);
  ELSIF v_cols IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'Os campos de cota de aprendiz não existem mais em empresa_cadastro.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Cota de aprendiz calculada em: %s.', v_fns);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_041()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_emp uuid; v_pct numeric; v_pct2 numeric; v_col text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar estabelecimento com 120 ativos e cota obrigatória; depois crescer para 600';
  r.esperado := 'Percentual recalculado por faixa: 2% (100-200) e 4% (501-1000)';
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, pcd_obrigatoria, total_colaboradores)
  VALUES (public.qa_sandbox_tenant_id(), 'QA Cota PcD LTDA', true, 120)
  RETURNING id INTO v_emp;
  SELECT pcd_percentual_exigido INTO v_pct FROM public.empresa_cadastro WHERE id = v_emp;

  UPDATE public.empresa_cadastro SET total_colaboradores = 600 WHERE id = v_emp;
  SELECT pcd_percentual_exigido INTO v_pct2 FROM public.empresa_cadastro WHERE id = v_emp;

  r.passo_ordem := 2;
  r.passo_acao := 'AUDITORIA: a admissão marca quem é PcD/reabilitado para alimentar o realizado?';
  r.esperado := 'Campo de enquadramento PcD no cadastro do colaborador';
  v_col := coalesce(public.qa_col_existe('admissoes', '%pcd%'),
                    public.qa_col_existe('admissoes', '%deficien%'),
                    public.qa_col_existe('admissoes', '%reabilitad%'));

  IF v_pct = 2 AND v_pct2 = 4 AND v_col IS NOT NULL THEN
    r.situacao := 'passou';
    r.obtido := 'Faixas recalculadas no gatilho e enquadramento PcD presente na admissão.';
  ELSIF v_pct = 2 AND v_pct2 = 4 THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (metade boa, metade faltando): o gatilho recalcular_cota_pcd FUNCIONA — '
             || '120 ativos deram 2% e 600 deram 4%, faixas certas da Lei 8.213. Mas a admissão '
             || 'NÃO PERGUNTA se o admitido é PcD ou reabilitado (nenhum campo em admissoes): o '
             || '"realizado" (pcd_quantidade_atual) é digitado à mão e ninguém sabe QUEM compõe '
             || 'a cota — na fiscalização, a empresa precisa provar nominalmente. Correção: '
             || 'enquadramento PcD/reabilitado na admissão (dado sensível, acesso restrito) '
             || 'alimentando o realizado automaticamente.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('Faixas erradas no recálculo: 120 ativos → %s%% (esperado 2), 600 → %s%% '
             || '(esperado 4). A tabela do art. 93 é 2/3/4/5%% por faixa de efetivo.',
             coalesce(v_pct::text, 'NULL'), coalesce(v_pct2::text, 'NULL'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_050()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a admissão colhe a opção de vale-transporte?';
  r.esperado := 'Opção com trajeto/linhas ou renúncia formal arquivada — nunca presunção';
  v_est := coalesce(public.qa_col_existe(NULL, '%vale_transporte%'),
                    public.qa_col_existe(NULL, '%vale\_%'),
                    public.qa_fns_com('%vale_transporte%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o vale-transporte não existe na admissão — nenhum campo registra a '
             || 'opção (trajeto, linhas) nem a renúncia. A Lei 7.418 condiciona o benefício à '
             || 'opção do empregado; sem o registro, ou se desconta de quem renunciou (desconto '
             || 'indevido) ou não se tem prova da renúncia de quem depois o reclama. O checklist '
             || 'de documentos até menciona comprovantes, mas opção/renúncia é DECLARAÇÃO, não '
             || 'anexo. Correção: etapa de benefícios na coleta com opção estruturada e termo de '
             || 'renúncia gerado e arquivado (seção 16 do documento).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Opção de VT presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_051()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_piso text; v_confere text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o salário da admissão é conferido contra o piso da CCT?';
  r.esperado := 'Piso cadastrado (folha_cct) consultado na abertura; abaixo dele, bloqueio ou justificativa';
  v_piso := public.qa_col_existe('folha_cct', 'piso_salarial');
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_confere
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE '%piso_salarial%';
  IF v_piso IS NOT NULL AND v_confere IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o piso EXISTE no cadastro da CCT (folha_cct.piso_salarial) e NINGUÉM o '
             || 'consulta — a admissão grava qualquer salário sem olhar o instrumento coletivo '
             || 'da categoria. Salário abaixo do piso é diferença salarial devida desde o '
             || 'primeiro dia, com reflexos em tudo. E não há comparação com os pares da mesma '
             || 'função (igualdade salarial, Lei 14.611/2023 [VAL]). Correção: conferência '
             || 'salário × piso vigente na abertura (bloqueio ou justificativa formal) e alerta '
             || 'de coerência com a mediana da função.';
  ELSIF v_piso IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'O campo de piso salarial não existe mais no cadastro de CCT.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Piso conferido em: %s.', v_confere);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_052()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_param text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o checklist de documentos da admissão é parametrizável?';
  r.esperado := 'Exigência extra da CCT/cargo cadastrada como parâmetro entra no checklist sem mexer em código';
  SELECT string_agg(table_name, ', ') INTO v_param
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND (table_name ILIKE '%admissao%config%' OR table_name ILIKE '%checklist%admissao%'
         OR table_name ILIKE '%documento%exigid%' OR table_name ILIKE '%admissao%template%');
  IF v_param IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: não existe tabela que parametrize o checklist da admissão — a lista de '
             || 'documentos obrigatórios vive fixa no código (ensure_admissao_documentos_by_token '
             || 'e a tela). Convenção que exija documento adicional, ou cargo que dispense um '
             || 'item, obriga alteração de código a cada cliente — e a exigência da CCT [RCC] '
             || 'passa batida até alguém lembrar. Correção: checklist como parâmetro por '
             || 'empresa/categoria/vigência (mesmo desenho de empresa_experiencia_config), '
             || 'consumido pela geração dos itens em admissao_documentos.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Checklist parametrizável em: %s.', v_param);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_070()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_gate text; v_fin text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): alguma função condiciona a conclusão à assinatura do contrato?';
  r.esperado := 'Sem contrato/termos assinados (candidato e empresa), a admissão não conclui';
  -- o gate precisa viver no caminho da conclusão: gatilho da própria tabela
  -- admissoes ou a função de finalização conferindo assinatura (buscar por
  -- "admiss%+assinatura" solto pega funções de exclusão/experiência)
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_gate
  FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE t.tgrelid = 'public.admissoes'::regclass AND NOT t.tgisinternal
    AND p.prosrc ILIKE '%assin%';
  SELECT left(p.prosrc, 1) INTO v_fin
  FROM pg_proc p WHERE p.proname = 'finalizar_admissao_by_token'
    AND p.prosrc ILIKE '%assin%';
  IF v_gate IS NULL AND v_fin IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a conclusão da admissão não confere assinatura nenhuma — '
             || 'finalizar_admissao_by_token só troca o status, e nenhuma outra função liga '
             || 'admissão a assinatura. A infraestrutura de assinatura EXISTE no sistema (o '
             || 'termo de experiência usa experiencia_assinatura_links, com trilha), mas o '
             || 'CONTRATO da admissão não passa por ela: a admissão conclui com contrato em '
             || 'rascunho, e o arquivamento (ADM-100..) recebe documento sem assinatura. Sem o '
             || 'contrato assinado, a empresa não prova o pactuado (arts. 29/442). Correção: '
             || 'estender o fluxo de assinatura da experiência ao contrato/termos da admissão '
             || 'e condicionar a transição de status à ciência das duas partes.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Conclusão condicionada à assinatura em: %s.',
                       coalesce(v_gate, 'finalizar_admissao_by_token'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_071()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_aceitou boolean := false; v_just text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'Gravar admissão com início 30 dias no PASSADO, sem nenhuma justificativa';
  r.esperado := 'Exceção com rito: justificativa obrigatória em trilha + alerta de eSocial fora do prazo';
  BEGIN
    INSERT INTO public.admissoes
      (tenant_id, nome_completo, cpf, cargo, data_admissao)
    VALUES (public.qa_sandbox_tenant_id(), 'QA Retroativa', public.qa_cpf(7071),
            'Analista', CURRENT_DATE - 30);
    v_aceitou := true;
  EXCEPTION WHEN check_violation OR raise_exception THEN v_aceitou := false; END;
  v_just := public.qa_col_existe('admissoes', '%justificativa%');

  IF v_aceitou AND v_just IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a admissão retroativa entrou CALADA — sem justificativa (a coluna nem '
             || 'existe), sem marcação de exceção, sem alerta. Início no passado significa, por '
             || 'definição, S-2200 fora do prazo (era devido até o dia anterior ao início) e '
             || 'possível período trabalhado sem registro — multa do art. 47 da CLT. O sistema '
             || 'pode aceitar o fato consumado, mas nunca em silêncio. Correção: justificativa '
             || 'obrigatória em trilha para data_admissao < hoje na criação + alerta crítico de '
             || 'atraso com ação no Plano de Ação.';
  ELSIF NOT v_aceitou THEN
    r.situacao := 'passou';
    r.obtido := 'A retroativa sem justificativa foi recusada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Retroativa aceita com campo de justificativa disponível (%s) — conferir '
                       || 'na tela a obrigatoriedade.', v_just);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_072()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_id uuid; v_status text;
BEGIN
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, cargo, data_admissao,
     exame_admissional_data, exame_admissional_resultado)
  VALUES (public.qa_sandbox_tenant_id(), 'QA Inapto Concluído', public.qa_cpf(7072),
          'Operador', CURRENT_DATE + 5, CURRENT_DATE - 1, 'inapto')
  RETURNING id INTO v_id;

  r.passo_ordem := 1;
  r.passo_acao := 'Concluir a admissão com ASO INAPTO registrado (e sem eSocial aceito)';
  r.esperado := 'Bloqueado — as pré-condições do CA-008 são cadastro completo, ASO apto e eSocial aceito';
  BEGIN
    UPDATE public.admissoes SET status = 'concluido' WHERE id = v_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN
    r.situacao := 'passou';
    r.obtido := 'A conclusão com ASO inapto foi recusada.';
    RETURN r;
  END;
  SELECT status::text INTO v_status FROM public.admissoes WHERE id = v_id;

  IF v_status = 'concluido' THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a admissão CONCLUIU com ASO inapto e sem evento de eSocial — o gatilho '
             || 'de onboarding (auto_criar_onboarding_admissao) olha SÓ a mudança de status, '
             || 'nenhuma pré-condição. Concluída, a cadeia inteira dispara (onboarding, ponto, '
             || 'contrato de experiência) para alguém que a NR-7 proíbe de começar a trabalhar '
             || 'naquela função — e cujo vínculo não existe para o governo. Correção: transição '
             || 'para concluído condicionada a ASO apto (já há campos estruturados para isso) e, '
             || 'quando o eSocial nascer (ADM-090), ao evento aceito.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('A conclusão foi retida (status ficou "%s").', v_status);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_073()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): dados de candidato não admitido têm prazo de retenção?';
  r.esperado := 'Política de retenção + descarte/anonimização para admissões encerradas sem contratação';
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_est
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND (p.prosrc ILIKE '%admiss%' AND (p.prosrc ILIKE '%retencao%' OR p.prosrc ILIKE '%expurg%'
         OR p.prosrc ILIKE '%anonimiz%' OR p.prosrc ILIKE '%descart%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o descarte existe no PONTO (ponto_expurgar_registros, com config de '
             || 'anos) e no catálogo do Hub (prazo_retencao_anos), mas NÃO na admissão — '
             || 'candidato reprovado ou desistente fica com CPF, documentos e até resultado de '
             || 'ASO guardados para sempre, sem base legal que o sustente (a base era a '
             || 'execução do contrato QUE NÃO HOUVE). Dado sensível de quem nunca foi '
             || 'colaborador é o pior passivo de LGPD do módulo. Correção: replicar o desenho '
             || 'do Ponto — config de prazo por tenant + rotina de expurgo/anonimização para '
             || 'admissões em reprovado/cancelado, preservando trilha sem conteúdo pessoal. '
             || 'Prazo é [VAL] jurídico (seção 30).';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Retenção/descarte da admissão presente em: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_092()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): existe consulta/registro de qualificação cadastral?';
  r.esperado := 'CPF × nome × nascimento validados contra a base do governo ANTES do S-2200';
  v_est := coalesce(public.qa_fns_com('%qualifica%'), public.qa_col_existe(NULL, '%qualificacao%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: a qualificação cadastral não existe no módulo — nenhuma função ou '
             || 'campo registra a validação de CPF/nome/nascimento contra as bases do governo. '
             || 'É a causa nº 1 de rejeição do S-2200: divergência conhecida e não tratada em '
             || 'casa vira rejeição anunciada no dia do envio (a véspera do início, sem folga '
             || 'para corrigir). Encadeado ao ADM-090: quando a transmissão nascer, a '
             || 'qualificação precisa nascer ANTES dela no fluxo — na validação da admissão, '
             || 'com o campo divergente apontado em linguagem simples e o envio retido até '
             || 'corrigir.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Qualificação cadastral presente: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_093()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_unq text; v_trad text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): a transmissão tem anti-duplicidade e tradução de rejeição?';
  r.esperado := 'Reenvio corrigido substitui/retifica (nunca duplica o vínculo) e a rejeição vira instrução';
  IF to_regclass('public.esocial_transmissoes') IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'A tabela de transmissões do eSocial não existe nesta base.';
    RETURN r;
  END IF;
  SELECT string_agg(conname, ', ') INTO v_unq
  FROM pg_constraint WHERE conrelid = 'public.esocial_transmissoes'::regclass AND contype = 'u';
  v_trad := coalesce(public.qa_fns_com('%rejeic%esocial%'), public.qa_fns_com('%esocial%rejei%'));

  IF v_unq IS NULL AND v_trad IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO (par do FERIAS-081, aqui pelo S-2200): esocial_transmissoes não tem '
             || 'unicidade — o mesmo evento de admissão pode ser gravado e enviado duas vezes — '
             || 'e nenhuma função interpreta rejeições: o retorno técnico chega cru e o reenvio '
             || 'fica por conta do operador. S-2200 duplicado é vínculo duplicado no governo, '
             || 'passivo criado pela própria correção. Correção: chave natural do evento '
             || '(vínculo + tipo + competência) + rotina que traduz a rejeição em instrução e '
             || 'conduz retificação, nunca clone. Vale para a admissão herdar pronta quando o '
             || 'ADM-090 for construído.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('Proteções presentes (unicidade: %s; tradução: %s).',
                       coalesce(v_unq, '—'), coalesce(v_trad, '—'));
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

CREATE OR REPLACE FUNCTION public.qa_caso_adm_107()
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE r public.qa_retorno; v_est text;
BEGIN
  r.passo_ordem := 1;
  r.passo_acao := 'AUDITORIA (somente leitura): o ASO admissional existe como entidade de saúde própria?';
  r.esperado := 'Regime próprio de acesso, retenção e sigilo (NR-07/LGPD art. 11) — não anexo comum';
  v_est := coalesce(public.qa_col_existe(NULL, '%aso_admissional%'),
                    public.qa_fns_com('%aso%admissional%'));
  IF v_est IS NULL THEN
    r.situacao := 'falhou';
    r.obtido := 'ACHADO: o ASO admissional não existe como entidade — o único ASO do sistema é '
             || 'o de RETORNO de afastamento (afastamentos.aso_retorno_*). Na admissão, o ASO '
             || 'entraria como anexo genérico, com o mesmo tratamento de um comprovante de '
             || 'residência — mas é dado de SAÚDE: sigilo médico (NR-07), acesso restrito, '
             || 'retenção de 20 anos e LGPD art. 11. Correção: categoria própria de documento '
             || 'de saúde na admissão, com política de acesso restritiva e retenção '
             || 'diferenciada.';
  ELSE
    r.situacao := 'passou';
    r.obtido := format('ASO admissional estruturado: %s.', v_est);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $function$

;

INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo) VALUES
  ('ADM-020','qa_caso_adm_020', true),
  ('ADM-021','qa_caso_adm_021', true),
  ('ADM-022','qa_caso_adm_022', true),
  ('ADM-030','qa_caso_adm_030', true),
  ('ADM-031','qa_caso_adm_031', true),
  ('ADM-040','qa_caso_adm_040', true),
  ('ADM-041','qa_caso_adm_041', true),
  ('ADM-050','qa_caso_adm_050', true),
  ('ADM-051','qa_caso_adm_051', true),
  ('ADM-052','qa_caso_adm_052', true),
  ('ADM-070','qa_caso_adm_070', true),
  ('ADM-071','qa_caso_adm_071', true),
  ('ADM-072','qa_caso_adm_072', true),
  ('ADM-073','qa_caso_adm_073', true),
  ('ADM-092','qa_caso_adm_092', true),
  ('ADM-093','qa_caso_adm_093', true),
  ('ADM-107','qa_caso_adm_107', true)
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

WITH alvo(codigo) AS (SELECT codigo FROM public.qa_implementacoes WHERE codigo LIKE 'ADM-%' AND ativo)
SELECT (public.qa_executar_descartavel(i.funcao_sql)).situacao::text AS situacao, count(*) AS qtd
FROM alvo a JOIN public.qa_implementacoes i ON i.codigo=a.codigo GROUP BY 1 ORDER BY 2 DESC;
