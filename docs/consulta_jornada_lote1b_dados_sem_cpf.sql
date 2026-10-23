-- SOMENTE LEITURA — linhas SEM CPF nas tabelas do lote 1b (nao conseguem ser ligadas a uma pessoa).
-- Depois da trava, linha sem CPF so e vista por perfil amplo (nem o proprio colaborador a ve).
-- Alerta sem CPF e normal (alertas da empresa: certificado, CCT, REP). Atribuicao de escala ou lotacao sem CPF
-- e problema de cadastro: o colaborador nao enxerga a propria escala. Nao mostra nome nem CPF.
SELECT 'ponto_alertas' AS tabela, count(*) FILTER (WHERE regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = '') AS sem_cpf, count(*) AS total FROM public.ponto_alertas
UNION ALL
SELECT 'ponto_escala_atribuicoes', count(*) FILTER (WHERE regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = ''), count(*) FROM public.ponto_escala_atribuicoes
UNION ALL
SELECT 'ponto_lotacao_historico', count(*) FILTER (WHERE regexp_replace(COALESCE(colaborador_cpf,''),'[^0-9]','','g') = ''), count(*) FROM public.ponto_lotacao_historico
UNION ALL
SELECT 'ponto_troca_turno', count(*) FILTER (WHERE regexp_replace(COALESCE(colaborador_a_cpf,''),'[^0-9]','','g') = '' OR regexp_replace(COALESCE(colaborador_b_cpf,''),'[^0-9]','','g') = ''), count(*) FROM public.ponto_troca_turno
ORDER BY 1;
