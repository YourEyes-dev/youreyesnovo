-- ============================================================================
-- DETALHE DO BANCO DE HORAS — SUDOMED (somente leitura)
-- Colar no SQL Editor de PRODUÇÃO (projeto diayjpsrcerycycyaxst).
-- NÃO cria, NÃO altera e NÃO apaga nada. Mostra, por pessoa:
--   Bloco A — o SALDO mês a mês (para ver em que mês zerou);
--   Bloco B — as MOVIMENTAÇÕES manuais (as zeragens/ajustes feitos à mão, com data).
-- Escopo: as 4 empresas (inclui a filial 41085456000260).
-- ============================================================================
WITH emp AS MATERIALIZED (
  SELECT id, razao_social, cnpj
  FROM public.empresa_cadastro
  WHERE regexp_replace(COALESCE(cnpj,''),'[^0-9]','','g')
        IN ('26114701000145','31219374000126','41085456000189','41085456000260')
),
dados AS (
  -- Bloco A: saldo por competência (a evolução do saldo)
  SELECT e.razao_social AS empresa,
         COALESCE(b.colaborador_nome, b.colaborador_cpf) AS colaborador,
         'A. SALDO POR MÊS' AS bloco,
         b.competencia AS quando,
         'saldo anterior '
           ||(CASE WHEN COALESCE(b.saldo_anterior_minutos,0)<0 THEN '-' ELSE '' END)
           ||(abs(COALESCE(b.saldo_anterior_minutos,0))/60)||'h'||lpad((abs(COALESCE(b.saldo_anterior_minutos,0))%60)::text,2,'0')
         ||' · créditos +'||(COALESCE(b.creditos_minutos,0)/60)||'h'||lpad((COALESCE(b.creditos_minutos,0)%60)::text,2,'0')
         ||' · débitos -'||(COALESCE(b.debitos_minutos,0)/60)||'h'||lpad((COALESCE(b.debitos_minutos,0)%60)::text,2,'0')
         ||' · compensados '||(COALESCE(b.compensados_minutos,0)/60)||'h'||lpad((COALESCE(b.compensados_minutos,0)%60)::text,2,'0')
         ||' · >> SALDO ATUAL '
           ||(CASE WHEN COALESCE(b.saldo_atual_minutos,0)<0 THEN '-' ELSE '' END)
           ||(abs(COALESCE(b.saldo_atual_minutos,0))/60)||'h'||lpad((abs(COALESCE(b.saldo_atual_minutos,0))%60)::text,2,'0')
         ||' ('||COALESCE(b.saldo_atual_minutos,0)||' min · tipo '||COALESCE(b.tipo,'?')||')' AS detalhe
  FROM public.ponto_banco_horas b
  JOIN emp e ON e.id = b.empresa_id

  UNION ALL

  -- Bloco B: movimentações manuais (zeragens/ajustes à mão)
  SELECT e.razao_social AS empresa,
         COALESCE(b.colaborador_nome, mv.colaborador_cpf) AS colaborador,
         'B. MOVIMENTAÇÃO MANUAL' AS bloco,
         to_char(mv.data_referencia,'YYYY-MM-DD') AS quando,
         mv.tipo||' '
           ||(CASE WHEN COALESCE(mv.minutos,0)<0 THEN '-' ELSE '' END)
           ||(abs(COALESCE(mv.minutos,0))/60)||'h'||lpad((abs(COALESCE(mv.minutos,0))%60)::text,2,'0')
         ||' · '||COALESCE(mv.descricao,'(sem descrição)')
         ||' · origem '||COALESCE(mv.origem,'?') AS detalhe
  FROM public.ponto_banco_horas_movimentacoes mv
  JOIN public.ponto_banco_horas b ON b.id = mv.banco_horas_id
  JOIN emp e ON e.id = b.empresa_id
  WHERE COALESCE(mv.origem,'') <> 'apuracao'   -- só o que foi lançado à mão
)
SELECT empresa, colaborador, bloco, quando, detalhe
FROM dados
ORDER BY empresa, colaborador, bloco, quando;
