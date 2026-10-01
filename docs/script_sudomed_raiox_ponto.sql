-- ============================================================================
-- RAIO-X DO PONTO — SUDOMED (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO cria, NÃO altera e NÃO apaga nada. Só lê e resume o estado atual.
--
-- Escopo: as 3 empresas (CNPJs) abaixo. Um único resultado, por seções.
-- Se uma seção NÃO aparecer no resultado, é porque está vazia (ex.: nenhum
-- acordo/CCT/regime cadastrado — que é justamente o que falta configurar).
-- ============================================================================
WITH emp AS MATERIALIZED (
  SELECT id, tenant_id, razao_social, cnpj,
         COALESCE(usa_controle_ponto,false) AS ponto_on
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189')
),
tn AS MATERIALIZED (SELECT DISTINCT tenant_id FROM emp),
linhas AS (
  -- 1. Empresas encontradas
  SELECT 1 AS ord, '1. EMPRESAS' AS secao,
         e.razao_social AS item,
         'CNPJ '||e.cnpj||' · ponto '||CASE WHEN e.ponto_on THEN 'ATIVO' ELSE 'inativo' END AS detalhe
  FROM emp e

  -- 2. Colaboradores ativos por empresa
  UNION ALL
  SELECT 2, '2. COLABORADORES ATIVOS', e.razao_social,
         count(a.*)::text||' ativos (admissão concluída, não desligados)'
  FROM emp e
  LEFT JOIN public.admissoes a
    ON a.empresa_id = e.id AND a.status = 'concluido'
   AND COALESCE(a.inativo,false) = false AND a.data_desligamento IS NULL
  GROUP BY e.razao_social

  -- 3. Escalas cadastradas (tenant + empresas do grupo, ou tenant-wide)
  UNION ALL
  SELECT 3, '3. ESCALAS CADASTRADAS', es.nome,
         'diária '||COALESCE(es.jornada_diaria_minutos,0)||'min'
       ||' · semanal '||COALESCE(es.jornada_semanal_minutos,0)||'min'
       ||' · mensal '||COALESCE(es.jornada_mensal_minutos,0)||'min'
       ||' · sábado '||CASE WHEN COALESCE(es.sabado_util,false) THEN 'ÚTIL' ELSE 'folga' END
       ||' · domingo '||CASE WHEN COALESCE(es.domingo_util,false) THEN 'útil' ELSE 'folga' END
       ||' · equalização mensal '||CASE WHEN COALESCE(es.equalizacao_mensal_ativa,false) THEN 'LIGADA' ELSE 'desligada' END
       ||' · pessoas: '||(SELECT count(*) FROM public.ponto_escala_atribuicoes at
                           WHERE at.escala_id = es.id AND COALESCE(at.ativa,true))
  FROM public.ponto_escalas es
  WHERE es.tenant_id IN (SELECT tenant_id FROM tn)
    AND COALESCE(es.ativa,true)
    AND (es.empresa_id IN (SELECT id FROM emp) OR es.empresa_id IS NULL)

  -- 4. Acordos (individual/act/cct)
  UNION ALL
  SELECT 4, '4. ACORDOS', COALESCE(ac.titulo,'(sem título)'),
         'tipo '||ac.tipo
       ||CASE WHEN ac.colaborador_cpf IS NOT NULL THEN ' · INDIVIDUAL cpf '||ac.colaborador_cpf ELSE ' · empresa toda' END
       ||' · vigência '||COALESCE(ac.vigencia_inicio::text,'?')||' → '||COALESCE(ac.vigencia_fim::text,'sem fim')
       ||' · '||CASE WHEN COALESCE(ac.ativo,false) THEN 'ATIVO' ELSE 'inativo' END
       ||' · permite compensar falta: '||COALESCE(ac.permite_compensacao_falta::text,'não')
  FROM public.ponto_acordos ac
  WHERE ac.tenant_id IN (SELECT tenant_id FROM tn)
    AND (ac.empresa_id IN (SELECT id FROM emp) OR ac.empresa_id IS NULL)
  UNION ALL
  SELECT 4, '4. ACORDOS', '(nenhum acordo cadastrado)', 'é um dos itens a configurar'
  WHERE NOT EXISTS (SELECT 1 FROM public.ponto_acordos ac
    WHERE ac.tenant_id IN (SELECT tenant_id FROM tn)
      AND (ac.empresa_id IN (SELECT id FROM emp) OR ac.empresa_id IS NULL))

  -- 5. Regime de banco de horas
  UNION ALL
  SELECT 5, '5. REGIME DE BANCO DE HORAS', 'config '||left(bc.id::text,8),
         'tipo '||bc.tipo
       ||' · prazo compensação '||COALESCE(bc.prazo_compensacao_dias::text,'?')||' dias'
       ||' · exige acordo individual: '||COALESCE(bc.exige_acordo_individual::text,'?')
       ||' · exige CCT/ACT: '||COALESCE(bc.exige_cct_act::text,'?')
       ||' · homologação RH acima de: '||COALESCE(bc.homologacao_rh_acima_min::text,'—')||'min'
       ||' · '||CASE WHEN COALESCE(bc.ativo,false) THEN 'ATIVO' ELSE 'inativo' END
  FROM public.ponto_banco_horas_config bc
  WHERE bc.tenant_id IN (SELECT tenant_id FROM tn)
    AND (bc.empresa_id IN (SELECT id FROM emp) OR bc.empresa_id IS NULL)
  UNION ALL
  SELECT 5, '5. REGIME DE BANCO DE HORAS', '(nenhum regime cadastrado)', 'é um dos itens a configurar'
  WHERE NOT EXISTS (SELECT 1 FROM public.ponto_banco_horas_config bc
    WHERE bc.tenant_id IN (SELECT tenant_id FROM tn)
      AND (bc.empresa_id IN (SELECT id FROM emp) OR bc.empresa_id IS NULL))

  -- 6. Convenção coletiva (CCT)
  UNION ALL
  SELECT 6, '6. CONVENÇÃO (CCT)', COALESCE(c.nome, c.sindicato, '(sem nome)'),
         'banco permitido: '||COALESCE(c.banco_horas_permitido::text,'?')
       ||' · prazo '||COALESCE(c.banco_horas_prazo_compensacao_meses::text,'?')||' meses'
       ||' · vigência '||COALESCE(c.vigencia_inicio::text,'?')||' → '||COALESCE(c.vigencia_fim::text,'?')
       ||' · '||CASE WHEN COALESCE(c.ativo,false) THEN 'ATIVA' ELSE 'inativa' END
  FROM public.ponto_cct_config c
  WHERE c.tenant_id IN (SELECT tenant_id FROM tn)
    AND (c.empresa_id IN (SELECT id FROM emp) OR c.empresa_id IS NULL)
  UNION ALL
  SELECT 6, '6. CONVENÇÃO (CCT)', '(nenhuma CCT cadastrada)', 'é um dos itens a configurar'
  WHERE NOT EXISTS (SELECT 1 FROM public.ponto_cct_config c
    WHERE c.tenant_id IN (SELECT tenant_id FROM tn)
      AND (c.empresa_id IN (SELECT id FROM emp) OR c.empresa_id IS NULL))

  -- 7. Pré-assinalação de intervalo (se usarem jornada de 2 batidas)
  UNION ALL
  SELECT 7, '7. PRÉ-ASSINALAÇÃO', COALESCE(pa.colaborador_cpf,'(por escala)'),
         'intervalo '||COALESCE(pa.intervalo_minutos::text,'?')||'min'
       ||' · '||COALESCE(pa.intervalo_inicio::text,'?')||'–'||COALESCE(pa.intervalo_fim::text,'?')
       ||' · vigência '||COALESCE(pa.data_inicio::text,'?')||' → '||COALESCE(pa.data_fim::text,'sem fim')
       ||' · '||CASE WHEN COALESCE(pa.ativa,false) THEN 'ATIVA' ELSE 'inativa' END
  FROM public.ponto_pre_assinalacao pa
  WHERE pa.tenant_id IN (SELECT tenant_id FROM tn)

  -- 8. Fechamentos já feitos
  UNION ALL
  SELECT 8, '8. FECHAMENTOS FEITOS', f.competencia,
         'status '||f.status||' · em '||COALESCE(f.data_fechamento::text,'?')
       ||' · '||COALESCE(f.total_colaboradores::text,'?')||' colaboradores'
  FROM public.ponto_fechamentos f
  WHERE f.empresa_id IN (SELECT id FROM emp)

  -- 9. Zeragens / equalizações já lançadas (as "horas zeradas")
  UNION ALL
  SELECT 9, '9. ZERAGENS (equalização mensal)',
         eq.competencia||' · '||COALESCE(eq.colaborador_nome, eq.colaborador_cpf),
         COALESCE(eq.total_equalizacao_min::text,'?')||'min · origem '||COALESCE(eq.origem,'?')
       ||' · em '||COALESCE(eq.data_equalizacao::text,'?')
  FROM public.ponto_equalizacao_mensal eq
  WHERE eq.empresa_id IN (SELECT id FROM emp)
)
SELECT secao, item, detalhe
FROM linhas
ORDER BY ord, item;
