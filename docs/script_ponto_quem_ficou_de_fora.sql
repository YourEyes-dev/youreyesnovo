-- ============================================================================
-- PONTO — alguma empresa que USA o modulo ficou de fora da lista?
--
-- POR QUE ESTE ARQUIVO
-- A lista de empresas com controle de ponto ligado foi montada a partir do que
-- o dono do produto lembrava. Esta consulta confere essa lista contra o UNICO
-- juiz confiavel: a marcacao de ponto. Quem bateu ponto alguma vez usou o
-- modulo — nao ha como discutir com isso.
--
-- O QUE ELE MOSTRA
-- Toda empresa que tem ao menos uma marcacao na historia da base, com:
--   * quantos CPFs distintos bateram e quantas marcacoes ao todo;
--   * a data da primeira e da ultima marcacao;
--   * se a chave do controle de ponto esta ligada ou desligada.
--
-- COMO LER
-- A coluna VEREDITO e a que importa. Empresa com marcacao RECENTE e chave
-- DESLIGADA e a que pode ter ficado de fora — traga o nome dela para mim e eu
-- acrescento a lista. Empresa com marcacao antiga e chave desligada em geral e
-- teste antigo ou cliente que parou de usar, e nao exige acao.
--
-- LEMBRETE DA REDE DE SEGURANCA
-- Mesmo desligada, a apuracao alcanca qualquer CPF com marcacao nos ultimos
-- 365 dias. Entao uma empresa esquecida aqui NAO fica sem apuracao enquanto o
-- pessoal dela continuar batendo — a chave decide apenas se o sistema cria
-- FALTA para quem nao bate.
--
-- SOMENTE LEITURA. Nao cria, nao altera e nao apaga nada. Nao mostra nome nem
-- CPF de pessoa alguma: so contagens por empresa.
-- ============================================================================

WITH marcacoes AS MATERIALIZED (
  SELECT m.tenant_id,
         regexp_replace(COALESCE(m.colaborador_cpf, ''), '[^0-9]', '', 'g') AS cpf,
         m.data_marcacao
  FROM public.ponto_marcacoes m
  WHERE COALESCE(m.colaborador_cpf, '') <> ''
),
-- A marcacao nao guarda a empresa; a ligacao vem pela admissao do CPF.
por_empresa AS MATERIALIZED (
  SELECT a.empresa_id,
         count(DISTINCT k.cpf)              AS pessoas,
         count(*)                           AS marcacoes,
         min(k.data_marcacao)               AS primeira,
         max(k.data_marcacao)               AS ultima
  FROM marcacoes k
  JOIN public.admissoes a
    ON a.tenant_id = k.tenant_id
   AND regexp_replace(a.cpf, '[^0-9]', '', 'g') = k.cpf
  GROUP BY a.empresa_id
)
SELECT CASE
         WHEN e.razao_social IS NOT NULL THEN left(e.razao_social, 45)
         WHEN p.empresa_id IS NULL       THEN '(admissao sem empresa vinculada)'
         ELSE '(empresa nao encontrada no cadastro: ' || left(p.empresa_id::text, 8) || ')'
       END                                                      AS empresa,
       COALESCE(e.cnpj, '-')                                    AS cnpj,
       p.pessoas                                                AS pessoas_que_bateram,
       p.marcacoes,
       to_char(p.primeira, 'DD/MM/YYYY')                        AS primeira_marcacao,
       to_char(p.ultima,   'DD/MM/YYYY')                        AS ultima_marcacao,
       CASE WHEN e.usa_controle_ponto IS TRUE THEN 'ligada' ELSE 'DESLIGADA' END AS chave,
       CASE
         WHEN e.usa_controle_ponto IS TRUE
           THEN 'OK — usa o modulo e esta na lista'
         WHEN p.ultima >= CURRENT_DATE - 90
           THEN 'ATENCAO: bateu ponto nos ultimos 90 dias e esta DESLIGADA. Provavel esquecimento na lista.'
         WHEN p.ultima >= CURRENT_DATE - 365
           THEN 'CONFERIR: bateu ponto no ultimo ano e esta desligada. Cliente que parou de usar, ou esquecimento.'
         ELSE 'Sem uso recente — provavelmente teste antigo ou cliente que abandonou o modulo.'
       END                                                      AS veredito
FROM por_empresa p
LEFT JOIN public.empresa_cadastro e ON e.id = p.empresa_id
ORDER BY (e.usa_controle_ponto IS TRUE), p.ultima DESC NULLS LAST, p.marcacoes DESC;
