-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 04a: Psicossocial (campanhas, resultados, GHE, entrevistas, plano de acao)
--
-- PARA QUE SERVE
-- Preenche a tela /psicossocial da "Metalurgica Exemplo Ltda" (tenant demo da
-- parte 00) para a equipe comercial demonstrar o modulo com tudo preenchido.
-- Rodar DEPOIS da parte 00.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO (a trava abaixo recusa qualquer outro banco).
--
-- O QUE FAZ (tudo no tenant demo, nada fora dele)
--   1. catalogo dos 13 riscos psicossociais padrao e os 4 GHE (Producao,
--      Manutencao, Logistica, Administrativo) com os cargos de cada um;
--   2. 7 campanhas: 1o semestre (encerrada, 31 respostas), extraordinaria da
--      Manutencao (encerrada, 6), 2o semestre (encerrada, 41), pulso em
--      andamento (ativa, 12 respostas + link geral + 36 links individuais),
--      entrevistas guiadas (ativa, 13 convites), workshop coletivo
--      (encerrado, 2 sessoes) e uma campanha em rascunho;
--   3. respostas ANONIMAS ficticias (sem nome, sem CPF, sem ligacao com a
--      pessoa): so o GHE de quem respondeu, como a tela exige. Os indicadores
--      (IPS, IRP-S, IBO-S, IBD-S, IREC-S, ICOP-S e as 10 dimensoes) sao os
--      MESMOS que o calculo da tela produz (fixture gerada por
--      src/test/demoPsicossocialFixture.test.ts);
--   4. 8 entrevistas concluidas (6 individuais + 2 sessoes coletivas) com
--      analise dos 13 riscos e trechos anonimizados; 2 em andamento, 4
--      pendentes e 1 cancelada (links/tokens);
--   5. indice de confiabilidade, plano de acao PGR (5W2H) e os alertas /
--      acoes que o proprio sistema gera a partir das respostas.
--
-- GARANTIAS
--   - Idempotente: ids fixos (demo_id) e "so insere se nao existe"; rodar de
--     novo nao duplica nem muda nada.
--   - Nenhum dado real. Respostas sem nome/CPF; nomes dos convites de
--     entrevista sao os colaboradores ficticios da parte 00.
--   - Roda numa transacao so; sem tabela temporaria entre comandos; nao cria
--     tabela. Atualiza apenas linhas do tenant demo.
--
-- OBSERVACAO DE ESCALA (igual a semeadura TypeScript do repositorio): no SIPRO
-- o gatilho do banco grava em ips_score a media do IPS (escala de protecao),
-- mas a tela le o ips_score do SIPRO como IRP-S e mostra 100 - ips_score. Para
-- a demo mostrar o numero certo, no fim gravamos em ips_score a media do IRP-S.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) Trava de ambiente
-- ---------------------------------------------------------------------------
DO $trava$
DECLARE
  v_url text;
BEGIN
  v_url := (SELECT valor FROM public.app_config WHERE chave = 'supabase_url' LIMIT 1);
  IF v_url IS NULL
     OR (v_url NOT ILIKE '%fgsblefvdabgdouipigz%' AND v_url NOT ILIKE '%bmehdgthciuvdbvutsdv%') THEN
    RAISE EXCEPTION
      'RECUSADO: app_config.supabase_url (%) nao e a homologacao nem o teste. Os dados de demonstracao nunca entram em producao.',
      COALESCE(v_url, '(vazio)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = 'd3e00000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Rode antes a parte 00 (tenant demo nao encontrado).';
  END IF;
END $trava$;

-- ---------------------------------------------------------------------------
-- (1) Catalogo de riscos psicossociais padrao (13) — o painel "Riscos" e a
--     severidade dos fatores leem esta tabela
-- ---------------------------------------------------------------------------
INSERT INTO public.psicossocial_riscos (id, tenant_id, nome, descricao, padrao, ativo, severidade)
SELECT public.demo_id('psi_risco:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.nome, v.descricao, true, true, v.sev
FROM (VALUES
  (1,  'Assédio de qualquer natureza', 'Conduta abusiva, repetitiva ou única, que atente contra a dignidade ou integridade psíquica do trabalhador (moral, sexual ou organizacional).', 4),
  (2,  'Baixa clareza de papel/função', 'Falta de definição clara sobre responsabilidades, expectativas e limites do cargo.', 3),
  (3,  'Baixa demanda de trabalho (subcarga)', 'Trabalho monótono, repetitivo ou abaixo das capacidades do trabalhador, gerando tédio e desengajamento.', 2),
  (4,  'Baixa justiça organizacional', 'Percepção de injustiça nos processos, decisões e relações interpessoais dentro da organização.', 3),
  (5,  'Baixas recompensas e reconhecimento', 'Desequilíbrio entre esforço empregado e reconhecimento (financeiro, simbólico ou de carreira).', 3),
  (6,  'Baixo controle no trabalho / Falta de autonomia', 'Pouca participação nas decisões, ritmo, métodos ou organização do próprio trabalho.', 3),
  (7,  'Eventos violentos ou traumáticos', 'Exposição a violência física, verbal, assaltos, acidentes graves ou ameaças no ambiente de trabalho.', 5),
  (8,  'Excesso de demandas (sobrecarga)', 'Volume, ritmo ou complexidade de trabalho acima da capacidade do trabalhador.', 4),
  (9,  'Falta de suporte no trabalho', 'Ausência de apoio técnico, social ou emocional de colegas e superiores.', 3),
  (10, 'Má gestão de mudanças organizacionais', 'Mudanças impostas sem comunicação, participação ou suporte adequados.', 3),
  (11, 'Más relações no ambiente de trabalho', 'Conflitos interpessoais, falta de cooperação ou clima organizacional negativo.', 3),
  (12, 'Trabalho em condições de difícil comunicação', 'Barreiras físicas, tecnológicas ou organizacionais que dificultam a comunicação efetiva.', 2),
  (13, 'Trabalho remoto e isolado', 'Atividades realizadas de forma isolada, com pouco contato social e suporte.', 3)
) AS v(n, nome, descricao, sev)
WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_riscos r
                   WHERE r.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND lower(r.nome) = lower(v.nome));

-- ---------------------------------------------------------------------------
-- (2) Cargo x departamento (usado pela tela de GHE) e os 4 GHE com seus cargos
-- ---------------------------------------------------------------------------
INSERT INTO public.cargo_departamentos (id, tenant_id, cargo_id, departamento_id)
SELECT public.demo_id('psi_cargo_depto:' || c.id::text), c.tenant_id, c.id, c.departamento_id
FROM public.cargos c
WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND c.departamento_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.cargo_departamentos cd WHERE cd.cargo_id = c.id AND cd.departamento_id = c.departamento_id);

INSERT INTO public.psicossocial_ghe (id, tenant_id, empresa_id, codigo, nome, descricao, ativo)
SELECT public.demo_id('psi_ghe:' || v.cod), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.codigo, v.nome, v.descricao, true
FROM (VALUES
  ('P', 'DEMO-GHE-PROD',  'Produção',       'Operadores de usinagem, soldadores e montadores — turnos A e B.'),
  ('M', 'DEMO-GHE-MANUT', 'Manutenção',     'Mecânicos e eletricistas de manutenção — plantão e sobreaviso.'),
  ('L', 'DEMO-GHE-LOG',   'Logística',      'Operadores de empilhadeira e auxiliares de expedição.'),
  ('A', 'DEMO-GHE-ADM',   'Administrativo', 'Equipes de escritório: RH, financeiro, compras, qualidade e comercial.')
) AS v(cod, codigo, nome, descricao)
WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = public.demo_id('psi_ghe:' || v.cod));

INSERT INTO public.psicossocial_ghe_cargos (id, ghe_id, cargo_id, departamento_id, tenant_id)
SELECT public.demo_id('psi_ghe_cargo:' || v.cod || ':' || v.cargo), public.demo_id('psi_ghe:' || v.cod),
       public.demo_id('cargo:' || v.cargo), public.demo_id('depto:' || v.depto), 'd3e00000-0000-4000-8000-000000000001'
FROM (VALUES
  ('P', 'Operador de Usinagem CNC', 'Produção'), ('P', 'Soldador', 'Produção'),
  ('P', 'Montador de Estruturas Metálicas', 'Produção'), ('P', 'Líder de Produção', 'Produção'),
  ('M', 'Mecânico de Manutenção', 'Manutenção'), ('M', 'Eletricista de Manutenção', 'Manutenção'),
  ('M', 'Supervisor de Manutenção', 'Manutenção'),
  ('L', 'Operador de Empilhadeira', 'Logística'), ('L', 'Auxiliar de Logística', 'Logística'),
  ('L', 'Coordenador de Logística', 'Logística'),
  ('A', 'Analista Financeiro', 'Administrativo'), ('A', 'Analista da Qualidade', 'Administrativo'),
  ('A', 'Comprador', 'Administrativo'), ('A', 'Analista de RH', 'Recursos Humanos'),
  ('A', 'Técnico de Segurança do Trabalho', 'Recursos Humanos'), ('A', 'Vendedor Interno', 'Comercial')
) AS v(cod, cargo, depto)
WHERE EXISTS (SELECT 1 FROM public.psicossocial_ghe g WHERE g.id = public.demo_id('psi_ghe:' || v.cod))
  AND EXISTS (SELECT 1 FROM public.cargos c WHERE c.id = public.demo_id('cargo:' || v.cargo))
  AND NOT EXISTS (SELECT 1 FROM public.psicossocial_ghe_cargos x WHERE x.id = public.demo_id('psi_ghe_cargo:' || v.cod || ':' || v.cargo));

-- ---------------------------------------------------------------------------
-- (3) Campanhas. Datas relativas a hoje. A ordem de criacao (created_at) define
--     a ordem das listas: a mais recente aparece primeiro.
-- ---------------------------------------------------------------------------
INSERT INTO public.questionario_psicossocial_campanhas (
  id, tenant_id, empresa_id, nome, descricao, status, tipo, motivo_extraordinaria, evento_gatilho_tipo,
  campanha_anterior_id, periodicidade, instrumento, tipo_instrumento, escopo, escopo_valores, anonimo,
  permite_identificacao_voluntaria, mensagem_institucional, politica_uso_dados, data_inicio, data_fim,
  ghe_ids, situacoes_trabalho, blocos_dinamicos, criado_por, criado_por_nome, created_at, token_publico
)
SELECT public.demo_id('psi_camp:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.nome, v.descricao, v.status::public.campanha_psicossocial_status, v.tipo, v.motivo, v.evento,
       CASE WHEN v.ant IS NULL THEN NULL ELSE public.demo_id('psi_camp:' || v.ant) END,
       v.period, v.instr, v.tipo_instr, v.escopo,
       CASE WHEN v.escopo_val IS NULL THEN NULL ELSE string_to_array(v.escopo_val, '|') END,
       true, false,
       'Sua participação é anônima e voluntária. Os resultados são analisados apenas em grupo, nunca individualmente.',
       'As respostas são usadas exclusivamente para o Programa de Gerenciamento de Riscos (NR-01) e para ações de saúde e segurança. Nenhum resultado individual é divulgado.',
       CURRENT_DATE + v.ini, CURRENT_DATE + v.fim,
       ARRAY(SELECT public.demo_id('psi_ghe:' || g) FROM unnest(string_to_array(v.ghes, '|')) AS g),
       COALESCE((SELECT jsonb_agg(jsonb_build_object('setorId', c.departamento_id, 'setorNome', d.nome, 'funcaoId', c.id, 'funcaoNome', c.nome)
                                  ORDER BY d.nome, c.nome)
                   FROM public.cargos c JOIN public.departamentos d ON d.id = c.departamento_id
                  WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
                    AND (v.setores IS NULL OR d.nome = ANY (string_to_array(v.setores, '|')))), '[]'::jsonb),
       '[]'::jsonb,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       COALESCE((SELECT p.nome_completo FROM public.profiles p JOIN auth.users u ON u.id = p.user_id
                  WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Gestora de RH'),
       (CURRENT_DATE + v.ini - 7)::timestamptz + interval '12 hours',
       'demo' || substr(md5('psi_tok:' || v.n), 1, 20)
FROM (VALUES
  (1, 'Avaliação Psicossocial NR-1 — 1º semestre', 'Primeira avaliação de riscos psicossociais da Metalúrgica Exemplo, com o questionário SIPRO em toda a empresa.',
      'encerrada', 'regular', NULL, NULL, NULL, 'semestral', 'sipro', 'questionario', 'empresa', NULL, 'P|M|L|A', NULL, -210, -185),
  (2, 'Avaliação Extraordinária — Reestruturação da Manutenção', 'Aplicada após a mudança na escala de sobreaviso e na liderança da Manutenção.',
      'encerrada', 'extraordinaria', 'Mudança na escala de sobreaviso e na liderança da Manutenção', 'reestruturacao', 1, NULL, 'sipro', 'questionario', 'setor', 'Manutenção', 'M', 'Manutenção', -130, -115),
  (3, 'Avaliação Psicossocial NR-1 — 2º semestre', 'Reavaliação semestral após o plano de ação do 1º semestre.',
      'encerrada', 'regular', NULL, NULL, 1, 'semestral', 'sipro', 'questionario', 'empresa', NULL, 'P|M|L|A', NULL, -50, -25),
  (4, 'Pulso Psicossocial — Outubro', 'Pesquisa rápida de acompanhamento em andamento (link geral anônimo e links individuais).',
      'ativa', 'regular', NULL, NULL, 3, 'trimestral', 'sipro', 'questionario', 'empresa', NULL, 'P|M|L|A', NULL, -12, 18),
  (5, 'Entrevistas Guiadas NR-1 — Produção, Manutenção e Logística', 'Entrevistas individuais guiadas por IA (anônimas) para aprofundar os fatores críticos do questionário.',
      'ativa', 'regular', NULL, NULL, 3, NULL, 'copsoq', 'entrevista_guiada', 'empresa', NULL, 'P|M|L|A', NULL, -20, 25),
  (6, 'Workshop de Riscos Psicossociais — Chão de Fábrica', 'Entrevistas coletivas (workshops) com as equipes de Produção e Manutenção.',
      'encerrada', 'regular', NULL, NULL, 1, NULL, 'copsoq', 'entrevista_coletiva', 'empresa', NULL, 'P|M', NULL, -75, -60),
  (7, 'Avaliação Psicossocial — Filial Curitiba (planejada)', 'Campanha preparada para a Filial Curitiba; será aberta no próximo mês.',
      'rascunho', 'regular', NULL, NULL, NULL, 'semestral', 'sipro', 'questionario', 'unidade', 'Filial Curitiba', 'P|L', NULL, 20, 45)
) AS v(n, nome, descricao, status, tipo, motivo, evento, ant, period, instr, tipo_instr, escopo, escopo_val, ghes, setores, ini, fim)
WHERE NOT EXISTS (SELECT 1 FROM public.questionario_psicossocial_campanhas c WHERE c.id = public.demo_id('psi_camp:' || v.n));

-- ---------------------------------------------------------------------------
-- (4) Respostas ANONIMAS (sem nome, sem CPF, sem ligacao com a pessoa).
--     Formato de cada linha: [GHE, segundos, 35 respostas, IPS, classe, IRP-S,
--     IBO-S, IBD-S, IREC-S, ICOP-S, [10 medias por dimensao]]
--     O gatilho do banco recalcula a campanha a cada resposta.
-- ---------------------------------------------------------------------------
DO $respostas$
DECLARE
  v_atual jsonb := '[["P",898,"22221222111323333133323333322221211",64,"estavel",36,41,30,46,28,[50,44,25,31,25,33,25,33,50,31]],["P",875,"24333223222112122221122321211312232",38,"atencao",62,65,61,71,56,[75,63,50,69,50,67,42,67,75,56]],["P",672,"23331222112222132132222333322222111",55,"estavel",45,49,41,50,40,[69,44,33,56,31,50,33,33,50,31]],["P",500,"33333223332021122221221322221222222",38,"atencao",62,65,57,62,56,[75,63,67,75,50,58,50,50,58,50]],["P",765,"33333333222201121221112221111312222",33,"atencao",67,68,68,70,62,[75,75,50,75,56,75,50,75,75,50]],["P",980,"22222111211222333033223333333231111",66,"estavel",34,37,31,36,30,[50,31,33,44,19,42,25,25,33,25]],["P",680,"22322122111222323142233333333131222",63,"estavel",37,39,32,33,32,[56,44,25,44,25,42,25,25,25,44]],["P",862,"33232323322111122221121221221222222",38,"atencao",62,62,62,59,60,[69,63,58,75,50,67,58,58,58,50]],["P",678,"32232211222122233232112222222221112",50,"estavel",50,49,51,51,48,[63,38,50,56,31,67,50,50,50,31]],["P",562,"23333222213121123221112221232322222",42,"atencao",58,59,58,59,57,[69,56,50,69,44,75,50,50,58,50]],["P",945,"23331222111223232032332323332231122",59,"estavel",41,45,34,45,33,[69,44,25,44,25,33,42,25,42,38]],["P",490,"43333323222212222222112222321212223",39,"atencao",61,66,52,67,55,[81,69,50,56,50,67,50,42,67,56]],["P",939,"33433323223201023221112221221312232",33,"atencao",67,70,63,73,59,[81,69,58,81,44,75,50,58,75,56]],["P",748,"32231322121221122132222332222222122",52,"estavel",48,50,49,50,44,[63,50,33,63,38,50,33,50,50,44]],["P",936,"22232222212222223123222332233231122",56,"estavel",44,45,42,39,40,[56,50,42,50,38,42,33,42,33,38]],["P",970,"22221121221322223133323332333231111",64,"estavel",36,38,34,37,32,[50,31,42,44,31,33,25,33,33,25]],["M",915,"34332333332232312322223222320412332",37,"atencao",63,74,45,84,52,[81,69,67,38,63,50,42,42,92,63]],["M",768,"33342222222332222232222323331313333",45,"atencao",55,65,37,74,44,[81,50,50,38,44,50,42,25,75,75]],["M",843,"22232222211333333233223333342222213",60,"estavel",40,47,26,50,32,[56,50,33,25,31,42,25,17,50,50]],["M",827,"33332323332323322222112223221312332",40,"atencao",60,68,45,73,51,[75,63,67,31,50,67,50,42,75,63]],["M",703,"33232222223233333122323233321322211",52,"estavel",48,58,34,64,34,[69,50,58,31,31,42,33,33,67,38]],["M",981,"32232222132232233223233233331212222",53,"estavel",47,56,34,63,37,[63,50,50,44,38,33,33,25,67,50]],["M",775,"33333323323223222122112223231312222",40,"atencao",60,68,45,72,51,[75,69,67,44,44,67,50,33,75,50]],["M",444,"33332443223223222311222222221313232",36,"atencao",64,70,52,72,56,[75,81,58,44,63,58,50,50,75,63]],["L",752,"22222211112322333232324332222121111",63,"estavel",37,40,38,41,32,[50,38,33,38,31,42,17,50,42,25]],["L",686,"13231122221222223122232333223221111",58,"estavel",42,43,42,43,40,[56,38,42,50,38,42,33,42,42,25]],["L",509,"22111110111223333033343332234141110",75,"saudavel",25,24,31,17,23,[38,19,25,38,19,17,25,42,8,19]],["L",795,"22221122221112223132212222212221112",53,"estavel",47,45,54,47,46,[50,38,42,63,31,58,50,58,50,31]],["L",786,"21111012011233234132334343232231111",73,"estavel",27,29,28,36,23,[31,25,17,38,19,33,8,33,42,25]],["L",549,"12111000001233234132344443333131001",81,"saudavel",19,19,24,23,20,[31,6,8,38,19,25,0,25,25,13]],["L",489,"22211012110223233232323322223121111",66,"estavel",34,31,42,33,36,[44,25,17,44,31,42,33,50,33,25]],["L",969,"11111111111232334032224332323131111",72,"estavel",28,26,34,25,27,[25,25,25,38,13,50,17,42,25,25]],["A",933,"22121111110333334133344432234141001",77,"saudavel",23,24,25,17,17,[44,25,17,25,19,17,8,42,8,13]],["A",926,"22222122112322333222333343333121121",64,"estavel",36,40,30,36,33,[50,44,33,38,38,33,17,25,33,31]],["A",852,"22221211211232223132233232122222212",59,"estavel",41,42,44,48,36,[50,31,33,44,31,42,33,58,50,44]],["A",879,"22111122111222223133323332222120111",65,"estavel",35,35,41,37,33,[38,38,25,50,31,33,25,50,42,19]],["A",587,"12222122111333232133333332222231210",65,"estavel",35,37,35,39,28,[44,44,25,31,31,25,25,50,42,25]],["A",454,"22222122211222223123322232212121112",58,"estavel",42,42,47,42,39,[50,44,33,50,38,33,42,58,42,31]],["A",821,"12020111000333434043343433334131101",83,"saudavel",17,18,18,18,13,[31,19,0,19,6,17,17,25,17,19]],["A",854,"22222222121222232133333332222131121",61,"estavel",39,41,40,36,31,[50,50,33,50,31,25,25,50,33,31]],["A",998,"21211112011433433033324333233131110",75,"saudavel",25,27,24,26,21,[38,31,17,13,19,33,17,33,25,19]]]'::jsonb;
  v_ant jsonb := '[["P",956,"33322222221221132222223323222221211",50,"estavel",50,52,47,51,46,[69,50,42,63,44,50,33,42,50,31]],["P",930,"23322222222121122222212333331322221",47,"atencao",53,57,46,62,51,[63,50,50,69,50,58,33,25,67,44]],["P",520,"33322322211222233232213322321212212",50,"estavel",50,55,43,62,41,[69,56,33,50,31,58,33,42,67,44]],["P",922,"22232222212211123222223222232212211",50,"estavel",50,51,50,54,49,[56,50,42,69,44,50,42,42,58,38]],["P",653,"34432233233111021311112221222313332",30,"atencao",70,72,67,71,69,[88,63,67,81,69,75,50,58,67,69]],["P",452,"33433333323211112221112121222223223",33,"atencao",67,68,63,59,63,[81,75,67,69,56,75,58,58,50,63]],["P",935,"23331222222221123132223333322222222",52,"estavel",48,54,42,54,39,[69,44,50,63,31,50,25,33,50,50]],["P",962,"33333333222122122231111122222312322",36,"atencao",64,66,59,66,59,[75,75,50,63,44,75,67,50,67,56]],["P",864,"43442233223010111321011222120313232",26,"atencao",74,75,71,81,73,[94,63,58,88,69,83,58,58,83,63]],["P",800,"33222222112221222232222232232211122",51,"estavel",49,51,47,55,47,[63,50,33,56,44,50,42,42,58,38]],["P",839,"33343232222110121222012111211413222",31,"atencao",69,69,70,77,67,[81,63,50,81,56,75,67,67,83,56]],["P",914,"23332212122212122232222333232212122",50,"estavel",50,54,45,57,46,[69,44,42,63,44,50,33,33,58,44]],["M",492,"22233322221323332122122322231323223",49,"atencao",51,56,41,62,43,[56,63,42,31,38,58,42,42,67,63]],["M",680,"34332433332213222322112133320403332",32,"atencao",68,78,48,90,57,[81,75,67,50,56,67,50,33,100,69]],["M",590,"43343343222222222322222222221413333",34,"atencao",66,75,51,80,52,[88,81,50,50,56,50,50,50,83,75]],["M",932,"43433443232222211311122222121403343",27,"atencao",73,80,59,87,64,[88,88,58,50,75,67,50,58,92,81]],["M",836,"32332323222333332232233233431312222",51,"estavel",49,61,28,69,36,[69,63,50,25,38,42,33,17,75,50]],["M",856,"23232223122333232232223333342322223",54,"estavel",46,54,30,57,37,[63,56,42,31,38,50,25,17,58,56]],["L",934,"22332211211121232132232322213222212",54,"estavel",46,46,50,46,41,[63,38,33,63,31,42,42,58,42,44]],["L",755,"32222212322212122121122222121322221",45,"atencao",55,55,57,62,54,[56,44,58,63,44,67,50,58,67,44]],["L",563,"22231111112122232232233322212222111",58,"estavel",42,42,48,48,41,[56,25,33,56,38,42,33,58,50,31]],["L",1011,"11211111111223233132223332323130111",69,"estavel",31,27,39,26,34,[31,25,25,44,25,50,25,42,25,19]],["L",829,"22221222222222223122223331212221111",55,"estavel",45,46,50,48,40,[50,44,50,50,38,50,25,67,50,25]],["L",646,"22121111201232322133233432333221111",67,"estavel",33,34,33,39,33,[44,25,25,38,38,33,17,33,42,25]],["A",436,"22222322222322233132123221212232121",53,"estavel",47,48,50,44,40,[50,56,50,44,25,58,42,67,42,38]],["A",695,"32212122221222232133323332213122112",60,"estavel",40,43,43,38,33,[50,44,42,50,31,33,25,58,33,38]],["A",929,"11121211111243243133233343334131100",75,"saudavel",25,25,26,20,24,[31,31,25,31,19,33,17,25,17,13]],["A",853,"11121112001433243033343332233131011",76,"saudavel",24,24,27,24,18,[31,31,8,25,13,17,25,42,25,19]],["A",799,"33233223222312232121322222112132222",47,"atencao",53,54,53,44,45,[69,63,50,50,38,50,50,67,33,50]],["A",762,"22111111111224244122433443222131101",73,"estavel",27,30,30,32,21,[38,25,25,38,19,25,8,42,33,19]],["A",803,"22112122111233233133234342332120011",68,"estavel",32,35,29,37,26,[38,44,25,38,25,33,8,33,42,13]]]'::jsonb;
  v_keys text[] := ARRAY['sipro_dq1','sipro_dq2','sipro_dq3','sipro_dq4','sipro_dc1','sipro_dc2','sipro_dc3','sipro_dc4',
    'sipro_de1','sipro_de2','sipro_de3','sipro_ac1','sipro_ac2','sipro_ac3','sipro_ac4','sipro_cp1','sipro_cp2','sipro_cp3',
    'sipro_cp4','sipro_rj1','sipro_rj2','sipro_rj3','sipro_rs1','sipro_rs2','sipro_rs3','sipro_se1','sipro_se2','sipro_se3',
    'sipro_re1','sipro_re2','sipro_re3','sipro_sp1','sipro_sp2','sipro_sp3','sipro_sp4'];
  v_blocos text[] := ARRAY['Demandas Quantitativas e Ritmo','Demandas Cognitivas','Demandas Emocionais','Autonomia e Controle',
    'Clareza de Papéis','Reconhecimento e Justiça','Relacionamentos e Suporte','Sentido do Trabalho',
    'Recuperação e Equilíbrio','Sinais Precoces'];
  c record;
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      (public.demo_id('psi_camp:1'), 'ant', NULL::text, 1, 999),
      (public.demo_id('psi_camp:2'), 'ant', 'M', 1, 999),
      (public.demo_id('psi_camp:3'), 'atu', NULL::text, 1, 999),
      (public.demo_id('psi_camp:4'), 'atu', NULL::text, 5, 7)
    ) AS x(id, ds, ghe, rn_min, rn_max)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.questionario_psicossocial_campanhas k WHERE k.id = c.id) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM public.questionario_psicossocial_respostas r WHERE r.campanha_id = c.id) THEN CONTINUE; END IF;

    INSERT INTO public.questionario_psicossocial_respostas (
      id, tenant_id, campanha_id, respostas, indicadores, tempo_resposta_segundos, concluido_em, created_at,
      identificacao_voluntaria, ghe_id_snapshot, ghe_nome_snapshot, setor_snapshot, user_agent
    )
    WITH camp AS (
      SELECT k.data_inicio AS ini, LEAST(k.data_fim, CURRENT_DATE) AS fim FROM public.questionario_psicossocial_campanhas k WHERE k.id = c.id
    ), src AS (
      SELECT e.value AS v, e.ordinality AS ord
        FROM jsonb_array_elements(CASE WHEN c.ds = 'ant' THEN v_ant ELSE v_atual END) WITH ORDINALITY AS e(value, ordinality)
    ), rn AS (
      SELECT s.*, row_number() OVER (PARTITION BY s.v ->> 0 ORDER BY s.ord) AS rn FROM src s
    ), sel AS (
      SELECT r.*, row_number() OVER (ORDER BY r.rn, r.ord) AS i, count(*) OVER () AS n
        FROM rn r
       WHERE (c.ghe IS NULL OR r.v ->> 0 = c.ghe) AND r.rn BETWEEN c.rn_min AND c.rn_max
    )
    SELECT public.demo_id('psi_resp:' || c.id::text || ':' || sel.i), 'd3e00000-0000-4000-8000-000000000001', c.id,
           (SELECT jsonb_object_agg(v_keys[k], substr(sel.v ->> 2, k, 1)::int) FROM generate_series(1, 35) AS k),
           jsonb_build_object(
             'IPS', (sel.v ->> 3)::int, 'IPS_classificacao', sel.v ->> 4, 'IRP_S', (sel.v ->> 5)::int,
             'IBO_S', (sel.v ->> 6)::int, 'IBD_S', (sel.v ->> 7)::int, 'IREC_S', (sel.v ->> 8)::int, 'ICOP_S', (sel.v ->> 9)::int,
             'detalhes', (SELECT jsonb_agg(jsonb_build_object('bloco', v_blocos[k], 'media', (sel.v -> 10 ->> (k - 1))::int, 'nivel', 'moderado') ORDER BY k)
                            FROM generate_series(1, 10) AS k),
             'radar', (SELECT jsonb_agg(jsonb_build_object('subject', v_blocos[k], 'value', (sel.v -> 10 ->> (k - 1))::int, 'fullMark', 100) ORDER BY k)
                         FROM generate_series(1, 10) AS k)),
           (sel.v ->> 1)::int,
           (camp.ini::timestamp + ((camp.fim - camp.ini)::float8 * (sel.i - 0.5) / sel.n) * interval '1 day'
              + interval '8 hours' + ((sel.i * 53) % 540) * interval '1 minute')::timestamptz,
           (camp.ini::timestamp + ((camp.fim - camp.ini)::float8 * (sel.i - 0.5) / sel.n) * interval '1 day'
              + interval '8 hours' + ((sel.i * 53) % 540) * interval '1 minute')::timestamptz,
           false,
           public.demo_id('psi_ghe:' || (sel.v ->> 0)),
           CASE sel.v ->> 0 WHEN 'P' THEN 'Produção' WHEN 'M' THEN 'Manutenção' WHEN 'L' THEN 'Logística' ELSE 'Administrativo' END,
           CASE sel.v ->> 0 WHEN 'P' THEN 'Produção' WHEN 'M' THEN 'Manutenção' WHEN 'L' THEN 'Logística' ELSE 'Administrativo' END,
           'demo-homologacao'
      FROM sel CROSS JOIN camp;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Respostas psicossociais nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $respostas$;

-- Ajuste de escala do SIPRO (ver cabecalho): ips_score = media do IRP-S.
UPDATE public.questionario_psicossocial_campanhas c
   SET ips_score = m.irps
  FROM (SELECT r.campanha_id, round(avg((r.indicadores ->> 'IRP_S')::numeric)) AS irps
          FROM public.questionario_psicossocial_respostas r
         WHERE r.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
           AND r.campanha_id IN (SELECT public.demo_id('psi_camp:' || n) FROM generate_series(1, 4) AS n)
         GROUP BY r.campanha_id) m
 WHERE c.id = m.campanha_id AND c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
   AND c.ips_score IS DISTINCT FROM m.irps;

-- ---------------------------------------------------------------------------
-- (5) Links individuais da campanha em andamento (Gerenciar participantes):
--     36 colaboradores ativos recebem link; 12 ja responderam. A resposta fica
--     ANONIMA: nao ha ligacao entre o link e a resposta gravada.
-- ---------------------------------------------------------------------------
INSERT INTO public.psicossocial_participacoes (
  id, tenant_id, campanha_id, token, colaborador_id, colaborador_nome, colaborador_cpf, setor, cargo, unidade, turno,
  elegivel, respondido, respondido_em, enviado_via, enviado_em
)
SELECT public.demo_id('psi_part:' || a.id::text), a.tenant_id, public.demo_id('psi_camp:4'),
       upper(substr(md5('psi_part_tok:' || a.id::text), 1, 12)), a.id::text, a.nome_completo, a.cpf, a.departamento, a.cargo,
       COALESCE(a.filial, 'Matriz'),
       CASE WHEN a.jornada_trabalho ILIKE '%turno B%' THEN 'Turno B' ELSE 'Turno A' END,
       true, (a.rn <= 12),
       CASE WHEN a.rn <= 12 THEN (CURRENT_DATE - (a.rn % 9)::int)::timestamptz + interval '10 hours' END,
       (ARRAY['link','whatsapp','email','link'])[1 + (a.rn % 4)],
       (CURRENT_DATE - 11)::timestamptz + interval '9 hours'
FROM (SELECT x.*, row_number() OVER (ORDER BY md5(x.id::text)) AS rn
        FROM public.admissoes x
       WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.status::text = 'concluido') a
WHERE a.rn <= 36
  AND EXISTS (SELECT 1 FROM public.questionario_psicossocial_campanhas k WHERE k.id = public.demo_id('psi_camp:4'))
  AND NOT EXISTS (SELECT 1 FROM public.psicossocial_participacoes p WHERE p.id = public.demo_id('psi_part:' || a.id::text));

-- ---------------------------------------------------------------------------
-- (6) Entrevistas guiadas (campanha 5) e workshops (campanha 6).
--     Cada entrevista concluida traz a analise dos 13 riscos (probabilidade e
--     severidade de 1 a 5) e trechos ANONIMIZADOS — a tela soma por risco.
--     Formato da matriz: 13 pares "P,S" separados por ";" na ordem do catalogo.
-- ---------------------------------------------------------------------------
DO $entrevistas$
DECLARE
  e record;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      -- n, campanha, status, ghe, admissao (NULL = sessao coletiva), dias atras (inicio), matriz, grupo, previstos, resumo
      (1,  5, 'concluida',    'P', 3,  14, '1,1;3,2;1,1;2,2;3,3;5,3;1,1;4,4;1,1;1,1;3,3;2,3;1,1', NULL::text, NULL::int, 'Relato de ritmo intenso nas metas do turno e pouca margem para ajustar o método de trabalho. Boa relação com os colegas; reconhecimento percebido como insuficiente.'),
      (2,  5, 'concluida',    'P', 15, 12, '1,1;3,2;1,1;4,2;3,3;3,4;3,4;4,4;2,4;3,3;2,4;2,4;1,1', NULL, NULL, 'Sobrecarga em períodos de pico, pouca autonomia sobre pausas e dúvidas sobre critérios de promoção. Relatos pontuais de falta de apoio da liderança.'),
      (3,  5, 'concluida',    'P', 24, 9,  '1,1;1,1;1,1;3,2;4,4;4,3;1,4;5,5;2,3;2,4;3,3;2,4;1,1', NULL, NULL, 'Demandas elevadas e pressão por prazo na montagem, com reconhecimento abaixo do esforço. Sem indícios de assédio.'),
      (4,  5, 'concluida',    'M', 31, 11, '1,1;3,3;1,1;3,2;4,3;2,2;3,4;5,5;3,5;2,2;4,4;1,1;1,1', NULL, NULL, 'Sobreaviso frequente prejudica o descanso; acionamentos noturnos e pouca previsibilidade de folga. Preocupação com segurança em intervenções críticas.'),
      (5,  5, 'concluida',    'M', 37, 7,  '1,1;3,2;1,1;2,4;3,4;2,2;2,5;4,4;3,5;2,3;3,3;2,4;1,1', NULL, NULL, 'Carga alta nas corretivas, apoio técnico irregular e mudanças de escala comunicadas em cima da hora.'),
      (6,  5, 'concluida',    'L', 44, 5,  '1,1;1,1;2,2;2,4;3,4;2,4;3,3;3,3;3,2;2,2;2,4;1,1;1,1', NULL, NULL, 'Rotina estável, com momentos de monotonia na expedição e comunicação difícil entre turnos. Clima de equipe positivo.'),
      (7,  5, 'em_andamento', 'P', 8,  1,  NULL,     NULL, NULL, NULL),
      (8,  5, 'em_andamento', 'A', 53, 0,  NULL,     NULL, NULL, NULL),
      (9,  5, 'pendente',     'P', 5,  NULL, NULL,   NULL, NULL, NULL),
      (10, 5, 'pendente',     'P', 18, NULL, NULL,   NULL, NULL, NULL),
      (11, 5, 'pendente',     'M', 33, NULL, NULL,   NULL, NULL, NULL),
      (12, 5, 'pendente',     'L', 47, NULL, NULL,   NULL, NULL, NULL),
      (13, 5, 'cancelada',    'P', 26, NULL, NULL,   NULL, NULL, NULL),
      (14, 6, 'concluida',    'P', NULL, 66, '1,1;3,3;1,1;2,3;3,2;4,3;1,4;4,3;1,1;2,3;2,3;3,3;1,1', 'Turno B — Soldagem e Usinagem', 8, 'Grupo apontou ritmo de produção acima da capacidade nos fechamentos de mês, pouca voz na definição de metas e desejo de reconhecimento público pela qualidade.'),
      (15, 6, 'concluida',    'M', NULL, 63, '1,1;1,1;1,1;2,3;3,4;2,3;2,5;5,3;2,3;2,4;4,4;3,2;1,1', 'Equipe de Manutenção — sobreaviso', 6, 'Grupo destacou o sobreaviso como principal fator de desgaste, mudanças de escala sem consulta e boa cooperação entre mecânicos e eletricistas.')
    ) AS x(n, camp, status, ghe, adm, dias, matriz, grupo, previstos, resumo)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM public.questionario_psicossocial_campanhas k WHERE k.id = public.demo_id('psi_camp:' || e.camp)) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM public.psicossocial_entrevistas x WHERE x.id = public.demo_id('psi_ent:' || e.n)) THEN CONTINUE; END IF;

    INSERT INTO public.psicossocial_entrevistas (
      id, tenant_id, empresa_id, campanha_id, colaborador_id, colaborador_nome, ghe_id_snapshot, token, modalidade, status,
      consentimento_lgpd_em, iniciada_em, concluida_em, resumo_ia, fase_atual, riscos_cobertos, total_riscos,
      created_at, tipo_sessao, grupo_nome, participantes_previstos
    )
    WITH ri(idx, nome, pres, trecho) AS (VALUES
      (1,  'Assédio de qualquer natureza', 'O entrevistado descreveu situações de cobrança em tom elevado por parte de chefias intermediárias.', 'Às vezes a cobrança vem em voz alta na frente de todo mundo.'),
      (2,  'Baixa clareza de papel/função', 'Há dúvidas sobre quem decide prioridades quando duas áreas pedem ao mesmo tempo.', 'Cada hora um manda uma coisa; a gente não sabe qual vem primeiro.'),
      (3,  'Baixa demanda de trabalho (subcarga)', 'Há períodos de pouca atividade e tarefas repetitivas, com sensação de subaproveitamento.', 'Tem dia que a tarefa é a mesma o turno inteiro.'),
      (4,  'Baixa justiça organizacional', 'Percepção de critérios diferentes entre turnos para folgas, horas extras e promoções.', 'Parece que o critério muda de um turno para o outro.'),
      (5,  'Baixas recompensas e reconhecimento', 'O esforço em períodos de pico não é reconhecido de forma visível pela empresa.', 'Quando bate a meta ninguém fala nada, só quando dá problema.'),
      (6,  'Baixo controle no trabalho / Falta de autonomia', 'Pouca participação na definição de metas, ritmo e pausas.', 'A meta já vem pronta, a gente só executa.'),
      (7,  'Eventos violentos ou traumáticos', 'Lembrança de quase-acidente com máquina que gerou medo e insegurança na operação.', 'Depois daquele quase-acidente muita gente ficou com receio da máquina.'),
      (8,  'Excesso de demandas (sobrecarga)', 'Volume de trabalho e prazos acima da capacidade do time, principalmente em fechamentos e picos.', 'No fim do mês a gente corre o tempo todo e não dá pra parar nem pra respirar.'),
      (9,  'Falta de suporte no trabalho', 'Dificuldade de obter apoio técnico ou da liderança quando surgem imprevistos.', 'Quando dá problema a gente se vira sozinho, não tem para quem ligar.'),
      (10, 'Más relações no ambiente de trabalho', 'Atritos pontuais entre equipes e falta de cooperação em horários de troca de turno.', 'Na troca de turno às vezes um deixa o problema para o outro.'),
      (11, 'Má gestão de mudanças organizacionais', 'Mudanças de escala e de procedimento são comunicadas com pouca antecedência e sem ouvir a equipe.', 'Soubemos da mudança de escala na véspera.'),
      (12, 'Trabalho em condições de difícil comunicação', 'Ruído e distância entre postos dificultam a comunicação durante a operação.', 'Com o barulho da máquina a gente quase não consegue se falar.'),
      (13, 'Trabalho remoto e isolado', 'Atividades em locais afastados, com pouco contato durante o turno.', 'Fico longe da equipe quase o turno todo.')
    ), pares AS (
      SELECT r.idx, r.nome, r.pres, r.trecho,
             split_part(split_part(e.matriz, ';', r.idx::int), ',', 1)::int AS p,
             split_part(split_part(e.matriz, ';', r.idx::int), ',', 2)::int AS s
        FROM ri r WHERE e.matriz IS NOT NULL
    ), analise AS (
      SELECT jsonb_build_object('resumo_geral', e.resumo,
               'riscos', jsonb_agg(jsonb_build_object(
                 'risco_nome', nome, 'presente', (p * s >= 6), 'probabilidade', p, 'severidade', s,
                 'justificativa', CASE WHEN p * s >= 6 THEN pres ELSE 'Sem indícios na entrevista' END,
                 'trechos_anonimizados', CASE WHEN p * s >= 6 THEN jsonb_build_array(trecho) ELSE '[]'::jsonb END) ORDER BY idx)) AS j,
             count(*) FILTER (WHERE p * s >= 6)::int AS cobertos
        FROM pares
    )
    SELECT public.demo_id('psi_ent:' || e.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
           public.demo_id('psi_camp:' || e.camp),
           CASE WHEN e.adm IS NULL THEN NULL ELSE public.demo_id('admissao:' || e.adm) END,
           CASE WHEN e.adm IS NULL THEN NULL ELSE (SELECT a.nome_completo FROM public.admissoes a WHERE a.id = public.demo_id('admissao:' || e.adm)) END,
           public.demo_id('psi_ghe:' || e.ghe),
           md5('psi_ent_tok:' || e.n), 'texto', e.status,
           CASE WHEN e.status IN ('concluida', 'em_andamento') THEN (CURRENT_DATE - e.dias)::timestamptz + interval '9 hours' END,
           CASE WHEN e.status IN ('concluida', 'em_andamento') THEN (CURRENT_DATE - e.dias)::timestamptz + interval '9 hours 5 minutes' END,
           CASE WHEN e.status = 'concluida' THEN (CURRENT_DATE - e.dias)::timestamptz + interval '9 hours 48 minutes' END,
           CASE WHEN e.status = 'concluida' THEN (SELECT j FROM analise) END,
           CASE e.status WHEN 'concluida' THEN 3 WHEN 'em_andamento' THEN CASE WHEN e.n = 7 THEN 2 ELSE 1 END ELSE 0 END,
           CASE WHEN e.status = 'concluida' THEN (SELECT cobertos FROM analise) WHEN e.n = 7 THEN 5 WHEN e.n = 8 THEN 2 ELSE 0 END,
           13,
           (CURRENT_DATE - COALESCE(e.dias, 4))::timestamptz + interval '8 hours',
           CASE WHEN e.adm IS NULL THEN 'coletiva' ELSE 'individual' END, e.grupo, e.previstos;

    IF e.status = 'concluida' THEN
      INSERT INTO public.psicossocial_entrevistas_evidencias (
        id, entrevista_id, campanha_id, tenant_id, empresa_id, risco_catalogo_id, risco_nome, presente, probabilidade, severidade,
        nivel_risco, justificativa, trechos_anonimizados, created_at
      )
      SELECT public.demo_id('psi_evid:' || e.n || ':' || (r ->> 'risco_nome')), en.id, en.campanha_id, en.tenant_id, en.empresa_id,
             (SELECT pr.id FROM public.psicossocial_riscos pr WHERE pr.tenant_id = en.tenant_id AND pr.padrao = true
                 AND lower(pr.nome) = lower(r ->> 'risco_nome') LIMIT 1),
             r ->> 'risco_nome', (r ->> 'presente')::boolean, (r ->> 'probabilidade')::int, (r ->> 'severidade')::int,
             CASE WHEN (r ->> 'probabilidade')::int * (r ->> 'severidade')::int <= 4 THEN 'baixo'
                  WHEN (r ->> 'probabilidade')::int * (r ->> 'severidade')::int <= 9 THEN 'moderado'
                  WHEN (r ->> 'probabilidade')::int * (r ->> 'severidade')::int <= 16 THEN 'alto' ELSE 'critico' END,
             r ->> 'justificativa',
             ARRAY(SELECT jsonb_array_elements_text(r -> 'trechos_anonimizados')),
             en.concluida_em
        FROM public.psicossocial_entrevistas en
       CROSS JOIN LATERAL jsonb_array_elements(en.resumo_ia -> 'riscos') AS r
       WHERE en.id = public.demo_id('psi_ent:' || e.n)
         AND NOT EXISTS (SELECT 1 FROM public.psicossocial_entrevistas_evidencias x WHERE x.entrevista_id = en.id);
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Entrevistas psicossociais nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $entrevistas$;

-- ---------------------------------------------------------------------------
-- (7) Acoes no Plano de Acao geral ligadas ao Psicossocial (as que o sistema
--     cria ao tratar um alerta: "Intervencao Urgente" para critico e "Acao
--     Preventiva" para alto). Uma linha por vez: o codigo ACO-xxxxx e gerado
--     pelo banco a partir do maior ja existente.
-- ---------------------------------------------------------------------------
DO $acoes$
DECLARE
  a record;
  v_user uuid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1);
  v_nome text := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1) LIMIT 1), 'Gestora de RH');
BEGIN
  FOR a IN
    SELECT * FROM (VALUES
      (1, 2, 'Intervenção Urgente — Recuperação e Equilíbrio [Crítico]', 'Recuperação e Equilíbrio', 79, 'imediato', 'em_andamento', 60, 20, 'Supervisor de Manutenção',
         'Realizar diagnóstico aprofundado, envolver liderança e implementar intervenção imediata: rodízio de sobreaviso e folga compensatória após acionamento noturno.'),
      (2, 2, 'Intervenção Urgente — Demandas Quantitativas e Ritmo [Crítico]', 'Demandas Quantitativas e Ritmo', 74, 'imediato', 'atrasada', 35, -8, 'Supervisor de Manutenção',
         'Redistribuir as ordens de serviço corretivas entre os turnos e contratar apoio temporário nos picos.'),
      (3, 2, 'Intervenção Urgente — Demandas Cognitivas [Crítico]', 'Demandas Cognitivas', 71, 'imediato', 'pendente', 0, 15, 'Analista de RH',
         'Mapear as tarefas de maior complexidade e criar checklists e dupla técnica nas corretivas críticas.'),
      (4, 3, 'Ação Preventiva — Demandas Quantitativas e Ritmo [Alto]', 'Demandas Quantitativas e Ritmo', 57, 'urgente', 'em_andamento', 45, 30, 'Líder de Produção',
         'Monitorar a evolução, revisar o dimensionamento dos turnos e reavaliar em 60 dias conforme ISO 45003.'),
      (5, 3, 'Ação Preventiva — Autonomia e Controle [Alto]', 'Autonomia e Controle', 46, 'urgente', 'concluida', 100, -10, 'Líder de Produção',
         'Reunião de início de turno com participação dos operadores na definição do ritmo e das pausas.'),
      (6, 3, 'Ação Preventiva — Reconhecimento e Justiça [Alto]', 'Reconhecimento e Justiça', 45, 'urgente', 'pendente', 0, 40, 'Analista de RH',
         'Criar programa mensal de reconhecimento por segurança e qualidade, com indicação pelos pares.'),
      (7, 1, 'Ação Preventiva — Demandas Quantitativas e Ritmo [Alto]', 'Demandas Quantitativas e Ritmo', 69, 'urgente', 'concluida', 100, -120, 'Supervisor de Manutenção',
         'Implantar revezamento de tarefas e revisão das metas de produção do primeiro semestre.')
    ) AS x(n, camp, titulo, dimensao, risco, prioridade, status, progresso, prazo_dias, responsavel, como)
  LOOP
    IF EXISTS (SELECT 1 FROM public.plano_acoes p WHERE p.id = public.demo_id('psi_acao:' || a.n)) THEN CONTINUE; END IF;
    INSERT INTO public.plano_acoes (
      id, tenant_id, empresa_id, codigo, titulo, descricao, porque, onde, como, prazo, responsavel_nome, origem_modulo, origem_id,
      origem_descricao, gravidade, urgencia, tendencia, prioridade, status, progresso, data_inicio, data_conclusao,
      exige_evidencia, tipo, tempo_gasto_minutos, criado_por, criado_por_nome, created_at
    )
    SELECT public.demo_id('psi_acao:' || a.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002', '',
           a.titulo,
           'Risco psicossocial identificado na campanha "' || k.nome || '". Dimensão: ' || a.dimensao || '. Score de risco: ' || a.risco || '/100.',
           'Score de risco ' || a.risco || '/100 na dimensão ' || a.dimensao,
           CASE WHEN a.camp = 2 THEN 'Manutenção' ELSE 'Toda a organização' END,
           a.como,
           CURRENT_DATE + a.prazo_dias, a.responsavel, 'psicossocial', k.id,
           'Campanha: ' || k.nome || ' — Gerado automaticamente',
           CASE WHEN a.risco >= 70 THEN 5 ELSE 3 END, CASE WHEN a.prioridade = 'imediato' THEN 5 ELSE 3 END, 3,
           a.prioridade::public.acao_gut_prioridade, a.status::public.acao_status, a.progresso,
           CASE WHEN a.status = 'pendente' THEN NULL ELSE CURRENT_DATE + a.prazo_dias - 45 END,
           CASE WHEN a.status = 'concluida' THEN CURRENT_DATE + a.prazo_dias END,
           true, CASE WHEN a.prioridade = 'imediato' THEN 'corretiva' ELSE 'preventiva' END, 0, v_user, v_nome,
           k.data_fim::timestamptz + interval '1 day'
      FROM public.questionario_psicossocial_campanhas k
     WHERE k.id = public.demo_id('psi_camp:' || a.camp);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Acoes do plano (psicossocial) nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $acoes$;

-- Remove duplicatas geradas pelo gatilho de alertas, caso ele funcione neste ambiente
DELETE FROM public.plano_acoes p
 USING public.plano_acoes q
 WHERE p.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND q.tenant_id = p.tenant_id
   AND p.origem_modulo = 'psicossocial' AND q.origem_modulo = 'psicossocial'
   AND p.origem_descricao LIKE '%Gerado automaticamente' AND q.origem_descricao = p.origem_descricao
   AND p.titulo = q.titulo AND p.id > q.id
   AND p.id NOT IN (SELECT public.demo_id('psi_acao:' || n) FROM generate_series(1, 7) AS n);

-- ---------------------------------------------------------------------------
-- (8) Alertas psicossociais (painel "Alertas Psicossociais Ativos"): criticos e
--     elevados em aberto + historico ja tratado. score_risco = risco da
--     dimensao no SIPRO (maior = pior).
-- ---------------------------------------------------------------------------
INSERT INTO public.psicossocial_alertas (
  id, tenant_id, campanha_id, tipo, titulo, descricao, severidade, setor, metadados, resolvido, resolvido_em,
  dimensao_id, dimensao_nome, score_risco, score_ips, classificacao, acao_id, acao_criada_id, created_at
)
SELECT public.demo_id('psi_alerta:' || v.camp || ':' || v.dim), 'd3e00000-0000-4000-8000-000000000001', k.id,
       'risco_dimensao', v.dim || ' — risco ' || v.risco || '/100',
       'Dimensão "' || v.dim || '" acima do limite aceitável na campanha "' || k.nome || '".',
       CASE WHEN v.risco >= 70 THEN 'critica' ELSE 'media' END,
       CASE WHEN v.camp = 2 THEN 'Manutenção' ELSE NULL END,
       jsonb_build_object('origem', 'demo', 'campanha', k.nome),
       v.resolvido, CASE WHEN v.resolvido THEN k.data_fim::timestamptz + interval '20 days' END,
       v.dim, v.dim, v.risco, v.ips,
       CASE WHEN v.risco >= 70 THEN 'critico' ELSE 'elevado' END,
       CASE WHEN v.acao IS NULL THEN NULL ELSE public.demo_id('psi_acao:' || v.acao) END,
       CASE WHEN v.acao IS NULL THEN NULL ELSE public.demo_id('psi_acao:' || v.acao) END,
       k.data_fim::timestamptz + interval '1 day'
FROM (VALUES
  (2, 'Recuperação e Equilíbrio', 79, 41, false, 1), (2, 'Demandas Quantitativas e Ritmo', 74, 41, false, 2),
  (2, 'Demandas Cognitivas', 71, 41, false, 3), (2, 'Sinais Precoces', 66, 41, true, NULL),
  (2, 'Reconhecimento e Justiça', 56, 41, true, NULL), (2, 'Demandas Emocionais', 52, 41, true, NULL),
  (2, 'Clareza de Papéis', 50, 41, true, NULL),
  (3, 'Demandas Quantitativas e Ritmo', 57, 56, false, 4), (3, 'Recuperação e Equilíbrio', 48, 56, true, NULL),
  (4, 'Demandas Quantitativas e Ritmo', 52, 61, false, NULL)
) AS v(camp, dim, risco, ips, resolvido, acao)
JOIN public.questionario_psicossocial_campanhas k ON k.id = public.demo_id('psi_camp:' || v.camp)
WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_alertas a WHERE a.campanha_id = k.id AND a.dimensao_id = v.dim);

-- ---------------------------------------------------------------------------
-- (9) Indice de Confiabilidade (cruza o resultado com absenteismo, acidentes,
--     turnover, humor, denuncias e afastamentos)
-- ---------------------------------------------------------------------------
INSERT INTO public.psicossocial_indice_confiabilidade (
  id, campanha_id, tenant_id, score_absenteismo, score_acidentes, score_turnover, score_humor, score_denuncias, score_afastamentos,
  indice_confiabilidade, classificacao, periodo_inicio, periodo_fim, total_colaboradores, detalhes, calculado_em
)
SELECT public.demo_id('psi_conf:' || v.camp), k.id, 'd3e00000-0000-4000-8000-000000000001',
       v.s_abs, v.s_acid, v.s_turn, v.s_humor, v.s_den, v.s_afast, v.indice, v.classe,
       k.data_fim - 90, k.data_fim, 59,
       jsonb_build_object(
         'absenteismo', jsonb_build_object('total', v.t_abs, 'descricao', v.t_abs || ' atestados no trimestre, concentrados em Produção e Manutenção'),
         'acidentes', jsonb_build_object('total', 2, 'descricao', '2 ocorrências leves (sem afastamento) na Produção'),
         'turnover', jsonb_build_object('total', 3, 'descricao', '3 desligamentos no trimestre (5,1%)'),
         'humor', jsonb_build_object('total', v.t_humor, 'descricao', 'Humor médio neutro, com piora às segundas-feiras na Manutenção'),
         'denuncias', jsonb_build_object('total', 1, 'descricao', '1 relato na Ouvidoria sobre sobrecarga de plantão'),
         'afastamentos', jsonb_build_object('total', 3, 'descricao', '3 afastamentos acima de 15 dias (2 osteomusculares, 1 saúde mental)')),
       k.data_fim::timestamptz + interval '1 day 14 hours'
FROM (VALUES
  (1, 62, 78, 70, 58, 80, 55, 67, 'moderada', 35, 780),
  (3, 68, 80, 74, 62, 85, 58, 71, 'moderada', 41, 1180),
  (4, 72, 82, 76, 66, 85, 62, 74, 'moderada', 28, 640)
) AS v(camp, s_abs, s_acid, s_turn, s_humor, s_den, s_afast, indice, classe, t_abs, t_humor)
JOIN public.questionario_psicossocial_campanhas k ON k.id = public.demo_id('psi_camp:' || v.camp)
WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_indice_confiabilidade x WHERE x.id = public.demo_id('psi_conf:' || v.camp));

-- ---------------------------------------------------------------------------
-- (10) Plano de Acao PGR (5W2H) por GHE
-- ---------------------------------------------------------------------------
INSERT INTO public.psicossocial_plano_acao (
  id, tenant_id, empresa_id, campanha_ids, ghe_id, ghe_nome, fator_id, fator, nivel_gro, o_que, quem, onde, por_que,
  data_inicial, ate_quando, como, quanto, selecionada, origem, criado_por, created_at
)
SELECT public.demo_id('psi_pa:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       ARRAY[public.demo_id('psi_camp:1'), public.demo_id('psi_camp:3')],
       public.demo_id('psi_ghe:' || v.ghe), v.ghe_nome, v.fator, v.fator, v.nivel, v.o_que, v.quem, v.onde,
       'Fator "' || v.fator || '" apontado na avaliação psicossocial (NR-1, GRO).',
       CURRENT_DATE + v.ini, CURRENT_DATE + v.fim, v.como, v.quanto, v.selecionada, v.origem,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       (CURRENT_DATE + v.ini - 3)::timestamptz
FROM (VALUES
  (1, 'M', 'Manutenção', 'Excesso de demandas (sobrecarga)', 'alto', 'Redimensionar a escala de sobreaviso da manutenção', 'Supervisor de Manutenção',
      'Manutenção', 'Rodízio semanal com no máximo 1 sobreaviso por pessoa a cada 3 semanas e folga compensatória após acionamento noturno.', 'R$ 6.000 (horas de sobreaviso redistribuídas)', -25, 40, true, 'manual'),
  (2, 'M', 'Manutenção', 'Falta de suporte no trabalho', 'medio', 'Criar par técnico de apoio nas manutenções corretivas críticas', 'Supervisor de Manutenção',
      'Manutenção', 'Toda corretiva em equipamento crítico passa a ter dupla; registro no sistema de ordens de serviço.', 'Sem custo adicional', -10, 55, true, 'ia'),
  (3, 'P', 'Produção', 'Baixo controle no trabalho / Falta de autonomia', 'alto', 'Implantar reunião de início de turno com participação na definição do ritmo', 'Líder de Produção',
      'Produção', '10 minutos no início de cada turno para combinar metas do dia e pausas; operadores podem sinalizar gargalos.', 'R$ 1.500 (quadro de gestão à vista)', -30, 25, true, 'manual'),
  (4, 'P', 'Produção', 'Baixas recompensas e reconhecimento', 'medio', 'Programa mensal de reconhecimento por segurança e qualidade', 'Analista de RH',
      'Produção', 'Indicação pelos pares e lideranças; reconhecimento público no mural e no app.', 'R$ 800/mês', -15, 60, true, 'ia'),
  (5, 'P', 'Produção', 'Excesso de demandas (sobrecarga)', 'alto', 'Revisar o dimensionamento dos turnos no fechamento do mês', 'Líder de Produção',
      'Produção', 'Estudo de capacidade por célula e reforço temporário nos três últimos dias do mês.', 'R$ 4.200 (horas extras evitadas)', -20, -2, true, 'manual'),
  (6, 'L', 'Logística', 'Baixa demanda de trabalho (subcarga)', 'baixo', 'Rodízio de funções entre recebimento e expedição', 'Coordenador de Logística',
      'Logística', 'Rodízio quinzenal para reduzir monotonia, com treinamento cruzado registrado.', 'Sem custo adicional', -5, 90, false, 'manual'),
  (7, 'L', 'Logística', 'Trabalho em condições de difícil comunicação', 'medio', 'Rádios comunicadores na expedição e passagem de turno estruturada', 'Coordenador de Logística',
      'Logística', 'Compra de 8 rádios e roteiro de passagem de turno de 5 minutos.', 'R$ 2.400', -12, 30, true, 'ia'),
  (8, 'A', 'Administrativo', 'Baixa clareza de papel/função', 'baixo', 'Revisar descrições de função de Compras e Qualidade', 'Analista de RH',
      'Administrativo', 'Oficina de 2 horas com cada área e atualização do descritivo de cargos.', 'Sem custo adicional', -8, 45, false, 'manual')
) AS v(n, ghe, ghe_nome, fator, nivel, o_que, quem, onde, como, quanto, ini, fim, selecionada, origem)
WHERE NOT EXISTS (SELECT 1 FROM public.psicossocial_plano_acao x WHERE x.id = public.demo_id('psi_pa:' || v.n));

-- ---------------------------------------------------------------------------
-- Conferencia final (uma linha)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.psicossocial_ghe WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ghe,
  (SELECT count(*) FROM public.questionario_psicossocial_campanhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS campanhas,
  (SELECT count(*) FROM public.questionario_psicossocial_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS respostas,
  (SELECT count(*) FROM public.psicossocial_participacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS links_individuais,
  (SELECT count(*) FROM public.psicossocial_entrevistas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS entrevistas,
  (SELECT count(*) FROM public.psicossocial_entrevistas_evidencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS evidencias,
  (SELECT count(*) FROM public.psicossocial_alertas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS alertas,
  (SELECT count(*) FROM public.psicossocial_plano_acao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS plano_pgr,
  (SELECT count(*) FROM public.psicossocial_indice_confiabilidade WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS confiabilidade,
  CASE WHEN (SELECT count(*) FROM public.questionario_psicossocial_campanhas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 7
        AND (SELECT count(*) FROM public.questionario_psicossocial_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 90
        AND (SELECT count(*) FROM public.psicossocial_ghe WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') = 4
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
