-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 04b: Bem-Estar (/felicidade, humor diario) e Ouvidoria (/ouvidoria)
--
-- PARA QUE SERVE
-- Preenche, na "Metalurgica Exemplo Ltda" (tenant demo da parte 00), as telas:
--   * /felicidade ("Meu Bem-Estar no Trabalho"): radar dos 7 eixos, historico
--     semanal de respostas e momentos de gratidao do usuario da demonstracao;
--   * humor diario da equipe (check-in "Como voce esta hoje?"), que alimenta o
--     Painel, a Ergonomia inteligente e o Indice de Confiabilidade psicossocial;
--   * /ouvidoria: manifestacoes de todos os tipos e status (pendente, em
--     analise, respondido, arquivado), do app e do canal externo (link
--     publico com protocolo), anonimas e identificadas, com as acoes do Plano
--     de Acao ligadas (tratativas), link do canal externo e roteamento.
-- Rodar DEPOIS da parte 00 (e de preferencia depois da 04a).
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO (a trava abaixo recusa qualquer outro banco).
--
-- GARANTIAS
--   - Idempotente (ids fixos + "so insere se nao existe"); nao cria tabela;
--     so toca o tenant demo; nenhum dado real (CPFs 900.000.0XX, e-mails
--     @metalurgica-exemplo.demo).
--   - Humor diario: usa o id da admissao do colaborador como "user_id" (a
--     tabela nao tem chave estrangeira para usuarios) — a equipe demo nao tem
--     login individual. O usuario logado tem os dias anteriores preenchidos e
--     HOJE em branco, para o check-in aparecer ao vivo na demonstracao.
--   - O que e anonimo na Ouvidoria continua anonimo: sem autor, nome, e-mail,
--     CPF ou empresa. Nas identificadas, o autor e um colaborador ficticio.
-- ============================================================================

SET lock_timeout = '10s';

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
-- (1) Humor diario da equipe: ultimos 75 dias uteis (aprox. 55% de adesao por
--     dia; a Manutencao piora as segundas; a tendencia recente e de melhora).
--     Alguns colaboradores trocam o humor no meio da jornada (historico).
-- ---------------------------------------------------------------------------
WITH moods(lim, nome, emoji, idx) AS (VALUES
  (0, 'Bem', '😊', 0), (40, 'Animado', '😄', 1), (75, 'Motivado', '💪', 2), (115, 'Neutro', '😐', 3),
  (165, 'Cansado', '😴', 4), (200, 'Estressado', '😰', 5), (228, 'Ansioso', '😟', 6), (246, 'Desanimado', '😞', 7)
), pessoas AS (
  SELECT a.id AS uid, a.nome_completo AS nome, a.departamento
    FROM public.admissoes a
   WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status::text = 'concluido'
), dias AS (
  SELECT d::date AS dia FROM generate_series(CURRENT_DATE - 75, CURRENT_DATE, interval '1 day') AS d
   WHERE extract(isodow FROM d) <= 5
), base AS (
  SELECT p.*, d.dia,
         get_byte(decode(substr(md5(p.uid::text || d.dia::text), 1, 8), 'hex'), 0) AS r1,
         get_byte(decode(substr(md5(p.uid::text || d.dia::text), 1, 8), 'hex'), 1) AS r2,
         get_byte(decode(substr(md5(p.uid::text || d.dia::text), 1, 8), 'hex'), 2) AS r3,
         get_byte(decode(substr(md5(p.uid::text || d.dia::text), 1, 8), 'hex'), 3) AS r4,
         extract(isodow FROM d.dia)::int AS dow
    FROM pessoas p CROSS JOIN dias d
), calc AS (
  SELECT b.*,
         LEAST(255, GREATEST(0, (b.r2 * 0.78)::int
           + CASE WHEN b.dow = 1 AND b.departamento = 'Manutenção' THEN 55
                  WHEN b.departamento = 'Produção' THEN 12
                  WHEN b.departamento = 'Administrativo' THEN -10 ELSE 0 END
           + (CURRENT_DATE - b.dia) / 5)) AS score
    FROM base b
   WHERE b.r1 < CASE WHEN b.dia > CURRENT_DATE - 30 THEN 170 ELSE 140 END
), moods_calc AS (
  SELECT c.*,
         (SELECT m.idx FROM moods m WHERE m.lim <= c.score ORDER BY m.lim DESC LIMIT 1) AS idx_ini,
         CASE WHEN c.r3 < 14 THEN (c.r4 % 8) END AS idx_troca
    FROM calc c
), final AS (
  SELECT mc.*,
         CASE WHEN mc.idx_troca IS NOT NULL AND mc.idx_troca <> mc.idx_ini THEN mc.idx_troca END AS idx_novo
    FROM moods_calc mc
), ins AS (
  INSERT INTO public.humor_diario (id, tenant_id, user_id, user_nome, data, humor, emoji, micropergunta_tipo, micropergunta_resposta, created_at, updated_at)
  SELECT public.demo_id('humor:' || f.uid::text || ':' || f.dia::text), 'd3e00000-0000-4000-8000-000000000001', f.uid, f.nome, f.dia,
         (SELECT m.nome FROM moods m WHERE m.idx = COALESCE(f.idx_novo, f.idx_ini)),
         (SELECT m.emoji FROM moods m WHERE m.idx = COALESCE(f.idx_novo, f.idx_ini)),
         CASE WHEN f.r3 BETWEEN 14 AND 110 THEN (ARRAY['carga_trabalho','pausas','pressao','apoio_equipe','clareza_tarefas'])[1 + f.r4 % 5] END,
         CASE WHEN f.r3 BETWEEN 14 AND 110 THEN
           (CASE (f.r4 % 5)
              WHEN 0 THEN (ARRAY['leve','normal','pesado'])[1 + (CASE WHEN COALESCE(f.idx_novo, f.idx_ini) <= 2 THEN 0 WHEN COALESCE(f.idx_novo, f.idx_ini) <= 4 THEN 1 ELSE 2 END)]
              WHEN 1 THEN (ARRAY['sim','parcial','nao'])[1 + (CASE WHEN COALESCE(f.idx_novo, f.idx_ini) <= 2 THEN 0 WHEN COALESCE(f.idx_novo, f.idx_ini) <= 4 THEN 1 ELSE 2 END)]
              WHEN 2 THEN (ARRAY['nao','nao','sim'])[1 + (CASE WHEN COALESCE(f.idx_novo, f.idx_ini) <= 2 THEN 0 WHEN COALESCE(f.idx_novo, f.idx_ini) <= 4 THEN 1 ELSE 2 END)]
              WHEN 3 THEN (ARRAY['sim','parcial','nao'])[1 + (CASE WHEN COALESCE(f.idx_novo, f.idx_ini) <= 2 THEN 0 WHEN COALESCE(f.idx_novo, f.idx_ini) <= 4 THEN 1 ELSE 2 END)]
              ELSE (ARRAY['sim','parcial','nao'])[1 + (CASE WHEN COALESCE(f.idx_novo, f.idx_ini) <= 2 THEN 0 WHEN COALESCE(f.idx_novo, f.idx_ini) <= 4 THEN 1 ELSE 2 END)]
            END) END,
         f.dia::timestamp + interval '7 hours 20 minutes' + (f.r4 % 90) * interval '1 minute',
         f.dia::timestamp + interval '7 hours 20 minutes' + (f.r4 % 90) * interval '1 minute' + CASE WHEN f.idx_novo IS NOT NULL THEN interval '5 hours' ELSE interval '0' END
    FROM final f
  ON CONFLICT (tenant_id, user_id, data) DO NOTHING
  RETURNING id, user_id, data
)
INSERT INTO public.humor_historico (id, tenant_id, user_id, user_nome, humor_diario_id, humor_anterior, humor_novo, emoji_anterior, emoji_novo, motivo_mudanca, created_at)
SELECT public.demo_id('humor_h:' || t.passo || ':' || ins.id::text), 'd3e00000-0000-4000-8000-000000000001', f.uid, f.nome, ins.id,
       CASE WHEN t.passo = 1 THEN NULL ELSE (SELECT m.nome FROM moods m WHERE m.idx = f.idx_ini) END,
       (SELECT m.nome FROM moods m WHERE m.idx = CASE WHEN t.passo = 1 THEN f.idx_ini ELSE f.idx_novo END),
       CASE WHEN t.passo = 1 THEN NULL ELSE (SELECT m.emoji FROM moods m WHERE m.idx = f.idx_ini) END,
       (SELECT m.emoji FROM moods m WHERE m.idx = CASE WHEN t.passo = 1 THEN f.idx_ini ELSE f.idx_novo END),
       CASE WHEN t.passo = 2 THEN 'Check-in de meio de jornada' END,
       f.dia::timestamp + interval '7 hours 20 minutes' + (f.r4 % 90) * interval '1 minute' + CASE WHEN t.passo = 2 THEN interval '5 hours' ELSE interval '0' END
  FROM ins
  JOIN final f ON f.uid = ins.user_id AND f.dia = ins.data
  JOIN (VALUES (1), (2)) AS t(passo) ON (t.passo = 1 OR f.idx_novo IS NOT NULL);

-- Usuario logado da demonstracao: dias uteis anteriores (hoje fica em branco de proposito)
DO $humor_user$
DECLARE
  v_uid uuid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1);
  v_nome text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE NOTICE 'Login leirinuernberg@gmail.com nao existe neste ambiente: humor e bem-estar do usuario nao semeados.';
    RETURN;
  END IF;
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Gestora de RH');
  INSERT INTO public.humor_diario (id, tenant_id, user_id, user_nome, data, humor, emoji, micropergunta_tipo, micropergunta_resposta, created_at, updated_at)
  SELECT public.demo_id('humor:' || v_uid::text || ':' || d::date::text), 'd3e00000-0000-4000-8000-000000000001', v_uid, v_nome, d::date,
         (ARRAY['Bem','Animado','Motivado','Bem','Neutro','Cansado','Bem','Motivado'])[1 + (extract(day FROM d)::int % 8)],
         (ARRAY['😊','😄','💪','😊','😐','😴','😊','💪'])[1 + (extract(day FROM d)::int % 8)],
         CASE WHEN extract(day FROM d)::int % 3 = 0 THEN (ARRAY['carga_trabalho','pausas','apoio_equipe'])[1 + extract(day FROM d)::int % 3] END,
         CASE WHEN extract(day FROM d)::int % 3 = 0 THEN (ARRAY['normal','sim','sim'])[1 + extract(day FROM d)::int % 3] END,
         d::date::timestamp + interval '8 hours 5 minutes', d::date::timestamp + interval '8 hours 5 minutes'
    FROM generate_series(CURRENT_DATE - 21, CURRENT_DATE - 1, interval '1 day') AS d
   WHERE extract(isodow FROM d) <= 5
  ON CONFLICT (tenant_id, user_id, data) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Humor do usuario nao concluido: % (%)', SQLERRM, SQLSTATE;
END $humor_user$;

-- ---------------------------------------------------------------------------
-- (2) /felicidade — 7 eixos de bem-estar do usuario logado: 8 semanas de
--     respostas (tendencia de melhora), reflexoes e momentos de gratidao
-- ---------------------------------------------------------------------------
INSERT INTO public.bem_estar_config (id, tenant_id, eixo, pergunta_ativa, frequencia_pergunta, ativo)
SELECT public.demo_id('be_cfg:' || v.eixo), 'd3e00000-0000-4000-8000-000000000001', v.eixo, v.pergunta, 'semanal', true
FROM (VALUES
  ('autoconhecimento', 'Como você está se sentindo no trabalho esta semana?'),
  ('sentido', 'Seu trabalho fez sentido para você nesta semana?'),
  ('relacoes', 'Como foi a qualidade das suas relações com a equipe?'),
  ('autonomia', 'Você se sentiu reconhecido(a) e com espaço para decidir?'),
  ('autorrealizacao', 'Você sente que está evoluindo na sua função?'),
  ('atencao_plena', 'Seu ritmo de trabalho foi sustentável nesta semana?'),
  ('gratidao', 'Qual momento positivo aconteceu no trabalho esta semana?')
) AS v(eixo, pergunta)
WHERE NOT EXISTS (SELECT 1 FROM public.bem_estar_config c WHERE c.id = public.demo_id('be_cfg:' || v.eixo));

DO $bem_estar$
DECLARE
  v_uid uuid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1);
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;

  INSERT INTO public.bem_estar_respostas (id, tenant_id, user_id, eixo, tipo, valor_numerico, valor_texto, opcao_selecionada, anonimo, created_at)
  SELECT public.demo_id('be_resp:' || e.eixo || ':' || w.sem), 'd3e00000-0000-4000-8000-000000000001', v_uid, e.eixo, 'slider',
         LEAST(5, GREATEST(1, e.base + CASE WHEN w.sem >= 5 THEN e.tend ELSE 0 END + ((w.sem * e.passo) % 3) - 1)),
         NULL,
         CASE WHEN e.eixo = 'autoconhecimento' THEN (ARRAY['Tarefas','Pessoas','Ritmo','Falta de clareza','Algo pessoal','Pessoas','Tarefas','Ritmo'])[1 + w.sem] END,
         false,
         (CURRENT_DATE - (w.sem * 7 + e.deslocamento))::timestamptz + interval '16 hours'
    FROM (VALUES
      ('autoconhecimento', 3, 1, 2, 0), ('sentido', 4, 1, 3, 1), ('relacoes', 4, 1, 1, 2), ('autonomia', 3, 1, 2, 3),
      ('autorrealizacao', 3, 1, 3, 1), ('atencao_plena', 2, 1, 1, 2), ('gratidao', 4, 0, 2, 0)
    ) AS e(eixo, base, tend, passo, deslocamento)
    CROSS JOIN generate_series(0, 7) AS w(sem)
   WHERE NOT EXISTS (SELECT 1 FROM public.bem_estar_respostas r WHERE r.id = public.demo_id('be_resp:' || e.eixo || ':' || w.sem));

  INSERT INTO public.bem_estar_gratidao (id, tenant_id, user_id, conteudo, tipo, anonimo, created_at)
  SELECT public.demo_id('be_grat:' || g.n), 'd3e00000-0000-4000-8000-000000000001', v_uid, g.texto, 'momento_positivo', false,
         (CURRENT_DATE - g.dias)::timestamptz + interval '17 hours'
    FROM (VALUES
      (1, 3,  'A equipe da manutenção resolveu a parada da linha 2 em tempo recorde e ninguém se machucou.'),
      (2, 9,  'Recebi um elogio da diretoria pelo fechamento do programa de SST do trimestre.'),
      (3, 16, 'Almoço de aniversariantes do mês: foi bom ver o pessoal da fábrica e do escritório juntos.'),
      (4, 24, 'Um colaborador novo disse que se sentiu muito bem acolhido na integração.'),
      (5, 31, 'Fechamos o mês sem nenhum acidente com afastamento.'),
      (6, 40, 'O time de produção propôs uma melhoria no posto de solda e a gestão aprovou na hora.'),
      (7, 52, 'Consegui sair no horário na maior parte da semana e fiz caminhada no fim do dia.'),
      (8, 61, 'A equipe do RH me ajudou a organizar a campanha de vacinação sem estresse.')
    ) AS g(n, dias, texto)
   WHERE NOT EXISTS (SELECT 1 FROM public.bem_estar_gratidao x WHERE x.id = public.demo_id('be_grat:' || g.n));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Bem-estar do usuario nao concluido: % (%)', SQLERRM, SQLSTATE;
END $bem_estar$;

-- ---------------------------------------------------------------------------
-- (3) Ouvidoria — canal externo (link), roteamento e 32 manifestacoes
-- ---------------------------------------------------------------------------
INSERT INTO public.ouvidoria_links (id, tenant_id, token, ativo, data_expiracao, created_at)
SELECT public.demo_id('ouv_link:1'), 'd3e00000-0000-4000-8000-000000000001', md5('ouv_link_token:demo'), true, NULL, (CURRENT_DATE - 100)::timestamptz
WHERE NOT EXISTS (SELECT 1 FROM public.ouvidoria_links WHERE id = public.demo_id('ouv_link:1'))
  AND NOT EXISTS (SELECT 1 FROM public.ouvidoria_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001');

INSERT INTO public.ouvidoria_roteamento (id, tenant_id, tipo_manifestacao, departamento_responsavel, responsavel_id, responsavel_nome, ativo)
SELECT public.demo_id('ouv_rot:' || v.tipo), 'd3e00000-0000-4000-8000-000000000001', v.tipo, v.depto,
       (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1),
       COALESCE((SELECT p.nome_completo FROM public.profiles p JOIN auth.users u ON u.id = p.user_id
                  WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Gestora de RH'), true
FROM (VALUES ('denuncia', 'Recursos Humanos'), ('reclamacao', 'Recursos Humanos'), ('sugestao', 'Administrativo'),
             ('elogio', 'Recursos Humanos'), ('duvida', 'Recursos Humanos')) AS v(tipo, depto)
WHERE NOT EXISTS (SELECT 1 FROM public.ouvidoria_roteamento r
                   WHERE r.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND r.tipo_manifestacao = v.tipo);

INSERT INTO public.ouvidoria (
  id, tenant_id, tipo, assunto, mensagem, anonimo, autor_id, autor_nome, autor_email, autor_departamento, status, prioridade,
  resposta, respondido_por, respondido_por_nome, respondido_em, anexos, responsavel_id, responsavel_nome, departamento_destino,
  prazo_apuracao_ate, origem, empresa_id, autor_cpf, protocolo, created_at, updated_at
)
SELECT public.demo_id('ouv:' || v.n), 'd3e00000-0000-4000-8000-000000000001', v.tipo, v.assunto, v.mensagem, (v.adm IS NULL),
       CASE WHEN v.adm IS NULL THEN NULL ELSE public.demo_id('admissao:' || v.adm) END,
       a.nome_completo, a.email, a.cargo,
       v.status, v.prioridade, v.resposta,
       CASE WHEN v.resposta IS NOT NULL THEN u.uid END, CASE WHEN v.resposta IS NOT NULL THEN u.nome END,
       CASE WHEN v.resposta IS NOT NULL THEN (CURRENT_DATE - v.dias + v.resp_dias)::timestamptz + interval '15 hours' END,
       '[]'::jsonb, u.uid, u.nome, v.depto,
       CASE WHEN v.prazo IS NULL THEN NULL ELSE CURRENT_DATE + v.prazo END,
       v.origem, CASE WHEN v.adm IS NULL THEN NULL ELSE 'd3e00000-0000-4000-8000-000000000002'::uuid END,
       CASE WHEN v.origem = 'link_publico' AND v.adm IS NOT NULL THEN regexp_replace(a.cpf, '[^0-9]', '', 'g') END,
       CASE WHEN v.origem = 'link_publico' THEN 'OUV-' || to_char(CURRENT_DATE - v.dias, 'YYYYMMDD') || '-' || upper(substr(md5('ouv_prot:' || v.n), 1, 6)) END,
       (CURRENT_DATE - v.dias)::timestamptz + (8 + v.n % 9) * interval '1 hour' + (v.n * 7 % 60) * interval '1 minute',
       (CURRENT_DATE - v.dias + CASE WHEN v.resposta IS NOT NULL THEN v.resp_dias ELSE 0 END)::timestamptz + interval '16 hours'
FROM (VALUES
  (1,  'denuncia',   'Cobrança excessiva e gritos no turno B', 'Há semanas o encarregado do turno B levanta a voz com a equipe na frente de todos quando a meta não fecha. Alguns colegas estão com medo de falar.', NULL::int, 'em_analise', 'alta', 'app', 9, 'Recursos Humanos', NULL::text, 0, 10),
  (2,  'denuncia',   'Possível assédio moral por chefia imediata', 'Venho sofrendo humilhações e ameaças veladas de desligamento quando discordo das decisões da chefia. Peço sigilo absoluto.', NULL, 'pendente', 'urgente', 'link_publico', 2, 'Recursos Humanos', NULL, 0, 5),
  (3,  'denuncia',   'EPI vencido na área de solda', 'Os respiradores usados na solda estão com a validade do filtro vencida e não há reposição há dois meses.', 15, 'em_analise', 'alta', 'app', 14, 'Recursos Humanos', NULL, 0, -3),
  (4,  'denuncia',   'Piadas discriminatórias no refeitório', 'Um grupo de colegas faz piadas sobre origem e aparência de um colaborador novo todos os dias no almoço.', NULL, 'respondido', 'alta', 'link_publico', 40, 'Recursos Humanos', 'Obrigado pelo relato. O caso foi apurado com as pessoas envolvidas, houve advertência formal e o treinamento de respeito e diversidade foi aplicado a todos os turnos. Seguimos acompanhando.', 12, NULL),
  (5,  'denuncia',   'Horas extras não registradas na manutenção', 'Fomos acionados fora do horário duas vezes no mês e as horas não aparecem no banco de horas.', 33, 'respondido', 'normal', 'app', 55, 'Recursos Humanos', 'As horas foram conferidas com o registro de acionamentos e lançadas no banco de horas retroativamente. O fluxo de registro de sobreaviso foi revisado com a supervisão.', 9, NULL),
  (6,  'denuncia',   'Colega usando celular durante operação de máquina', 'Observei um operador mexendo no celular com a máquina em funcionamento no turno da noite.', NULL, 'arquivado', 'baixa', 'app', 90, 'Recursos Humanos', 'Sem elementos para apuração individual. O tema foi reforçado no diálogo de segurança e a regra de uso de celular na operação foi comunicada novamente.', 6, NULL),
  (7,  'denuncia',   'Suspeita de favorecimento em promoção', 'A última promoção da expedição ignorou critérios combinados e foi para alguém sem a avaliação de desempenho exigida.', NULL, 'pendente', 'alta', 'link_publico', 6, 'Recursos Humanos', NULL, 0, 8),
  (8,  'reclamacao', 'Ar-condicionado do escritório quebrado', 'O ar-condicionado da sala do administrativo está desligado há três semanas e a temperatura passa de 30 graus.', 53, 'em_analise', 'normal', 'app', 20, 'Administrativo', NULL, 0, 4),
  (9,  'reclamacao', 'Fila longa no refeitório no turno B', 'O horário de almoço do turno B coincide com o do administrativo e a fila consome quase todo o intervalo.', NULL, 'respondido', 'normal', 'app', 35, 'Recursos Humanos', 'O horário do administrativo foi deslocado em 20 minutos e foi aberto um segundo ponto de distribuição. Pedimos que informem se a fila melhorou.', 6, NULL),
  (10, 'reclamacao', 'Banheiro do galpão 2 sem manutenção', 'Duas descargas e a torneira do banheiro do galpão 2 não funcionam há dias.', NULL, 'pendente', 'normal', 'link_publico', 4, 'Recursos Humanos', NULL, 0, 6),
  (11, 'reclamacao', 'Atraso na entrega de uniformes', 'Os uniformes novos foram solicitados há dois meses e ainda não chegaram.', 22, 'respondido', 'normal', 'app', 48, 'Recursos Humanos', 'A reposição foi entregue na semana passada e o prazo do fornecedor foi renegociado para os próximos pedidos.', 15, NULL),
  (12, 'reclamacao', 'Escala de sobreaviso mudou sem aviso', 'A escala de sobreaviso da manutenção foi alterada na véspera, sem consulta à equipe.', 31, 'em_analise', 'alta', 'app', 8, 'Recursos Humanos', NULL, 0, 7),
  (13, 'reclamacao', 'Estacionamento sem iluminação', 'O fundo do estacionamento está escuro desde que as lâmpadas queimaram.', NULL, 'arquivado', 'baixa', 'app', 100, 'Recursos Humanos', 'Lâmpadas substituídas e ronda noturna reforçada. Manifestação encerrada.', 8, NULL),
  (14, 'reclamacao', 'Ruído excessivo na usinagem', 'Mesmo com protetor, o ruído da usinagem 3 está muito alto e causa dor de cabeça no fim do turno.', NULL, 'respondido', 'alta', 'app', 60, 'Recursos Humanos', 'A medição de ruído foi refeita, a máquina recebeu enclausuramento parcial e os protetores foram trocados por modelo de maior atenuação. A ação está registrada no Plano de Ação.', 21, NULL),
  (15, 'reclamacao', 'Falta de água no bebedouro do CD Itajaí', 'O bebedouro do centro de distribuição está sem água gelada há uma semana.', 44, 'respondido', 'normal', 'app', 28, 'Recursos Humanos', 'O reservatório foi substituído e o contrato de manutenção dos bebedouros foi revisado.', 5, NULL),
  (16, 'sugestao',   'Rodízio de funções na expedição', 'Sugiro fazer rodízio semanal entre recebimento e expedição para reduzir a monotonia e a sobrecarga nos ombros.', 46, 'respondido', 'baixa', 'app', 70, 'Administrativo', 'Ótima ideia. O rodízio quinzenal entrou como ação do plano psicossocial da Logística e já está em teste.', 10, NULL),
  (17, 'sugestao',   'Ginástica laboral antes do turno', 'Dez minutos de alongamento antes de iniciar o turno ajudariam a diminuir as dores nas costas e nos punhos.', NULL, 'em_analise', 'normal', 'app', 18, 'Administrativo', NULL, 0, NULL),
  (18, 'sugestao',   'Aplicativo para consultar holerite e banco de horas', 'Poderíamos consultar holerite, banco de horas e férias pelo celular, sem pedir ao RH.', 54, 'respondido', 'normal', 'app', 85, 'Administrativo', 'Já está disponível no portal do colaborador. Fizemos um comunicado e um tutorial em vídeo para todos os turnos.', 7, NULL),
  (19, 'sugestao',   'Mais armários no vestiário feminino', 'O número de armários não acompanhou as novas contratações e várias colegas guardam o material no chão.', 14, 'pendente', 'baixa', 'app', 3, 'Administrativo', NULL, 0, NULL),
  (20, 'sugestao',   'Quadro de reconhecimento da segurança', 'Um quadro mensal com os times sem acidentes e ideias de melhoria incentivaria todo mundo.', NULL, 'respondido', 'baixa', 'link_publico', 30, 'Administrativo', 'A sugestão foi aprovada e será incluída no ritual de reconhecimento mensal do módulo Cultura.', 8, NULL),
  (21, 'sugestao',   'Horário flexível para o administrativo', 'Sugiro entrada flexível entre 7h e 9h para o administrativo, mantendo as 8 horas diárias.', 55, 'arquivado', 'baixa', 'app', 110, 'Administrativo', 'Avaliado com a diretoria: neste momento a operação exige horário único. Será revisto na próxima convenção coletiva.', 14, NULL),
  (22, 'sugestao',   'Treinamento de primeiros socorros', 'Seria útil treinar mais brigadistas em primeiros socorros em cada turno.', NULL, 'em_analise', 'normal', 'link_publico', 11, 'Administrativo', NULL, 0, NULL),
  (23, 'elogio',     'Equipe da manutenção pelo atendimento rápido', 'Quero elogiar a equipe da manutenção que atendeu a parada da linha 2 de madrugada e resolveu em duas horas.', 17, 'respondido', 'baixa', 'app', 25, 'Recursos Humanos', 'Elogio repassado à supervisão e à equipe. Muito obrigado por registrar!', 2, NULL),
  (24, 'elogio',     'Novo líder do turno B escuta a equipe', 'Desde que o novo líder assumiu o turno B, a equipe se sente ouvida e o clima melhorou muito.', NULL, 'respondido', 'baixa', 'app', 33, 'Recursos Humanos', 'Agradecemos o retorno. O elogio foi compartilhado com a liderança.', 3, NULL),
  (25, 'elogio',     'Campanha de vacinação bem organizada', 'A campanha de vacinação foi muito bem organizada, sem filas e com explicação clara.', 56, 'respondido', 'baixa', 'app', 52, 'Recursos Humanos', 'Obrigado! Vamos repetir o formato na próxima campanha.', 2, NULL),
  (26, 'elogio',     'Refeitório com cardápio mais variado', 'O novo cardápio ficou ótimo, com mais opções de salada e fruta.', NULL, 'pendente', 'baixa', 'link_publico', 5, 'Recursos Humanos', NULL, 0, NULL),
  (27, 'duvida',     'Como funciona o banco de horas?', 'Qual é o prazo para compensar as horas do banco e como solicito a folga?', 47, 'respondido', 'normal', 'app', 15, 'Recursos Humanos', 'O banco de horas pode ser compensado em até 6 meses, com solicitação pelo portal ao gestor imediato. Detalhes na política de jornada.', 1, NULL),
  (28, 'duvida',     'Prazo para pedir antecipação do 13º', 'Até quando posso pedir a antecipação da primeira parcela do 13º salário?', NULL, 'respondido', 'baixa', 'link_publico', 40, 'Recursos Humanos', 'O pedido pode ser feito até o dia 30 de janeiro de cada ano, direto com o DP.', 1, NULL),
  (29, 'duvida',     'Dependentes no plano de saúde', 'Posso incluir meu filho de 22 anos que é estudante no plano de saúde da empresa?', 25, 'pendente', 'normal', 'app', 1, 'Recursos Humanos', NULL, 0, NULL),
  (30, 'duvida',     'Quem representa os trabalhadores na CIPA?', 'Gostaria de saber quem são os representantes eleitos dos trabalhadores na CIPA.', NULL, 'em_analise', 'baixa', 'app', 7, 'Recursos Humanos', NULL, 0, NULL),
  (31, 'reclamacao', 'Máquina de solda com defeito elétrico', 'A máquina de solda do posto 4 está dando choque leve ao tocar na carcaça. Já avisei o líder e nada foi feito.', 18, 'em_analise', 'urgente', 'app', 2, 'Manutenção', NULL, 0, 3),
  (32, 'denuncia',   'Retaliação após reclamação de segurança', 'Depois de reportar um risco na prensa, fui trocado de turno e perdi o adicional noturno.', NULL, 'em_analise', 'urgente', 'link_publico', 12, 'Recursos Humanos', NULL, 0, 2)
) AS v(n, tipo, assunto, mensagem, adm, status, prioridade, origem, dias, depto, resposta, resp_dias, prazo)
LEFT JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.adm)
CROSS JOIN (SELECT (SELECT x.id FROM auth.users x WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1) AS uid,
                   COALESCE((SELECT p.nome_completo FROM public.profiles p JOIN auth.users x ON x.id = p.user_id
                              WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Gestora de RH') AS nome) u
WHERE NOT EXISTS (SELECT 1 FROM public.ouvidoria o WHERE o.id = public.demo_id('ouv:' || v.n));

-- Anonimas nao carregam identidade nenhuma (garantia redundante, so nas linhas da demo)
UPDATE public.ouvidoria
   SET autor_id = NULL, autor_nome = NULL, autor_email = NULL, autor_departamento = NULL, autor_cpf = NULL, empresa_id = NULL
 WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND anonimo = true
   AND (autor_id IS NOT NULL OR autor_nome IS NOT NULL OR autor_email IS NOT NULL OR autor_departamento IS NOT NULL OR autor_cpf IS NOT NULL OR empresa_id IS NOT NULL);

-- Tratativas: acoes do Plano de Acao ligadas as manifestacoes (uma por vez: o codigo ACO-xxxxx sai do maior existente)
DO $ouv_acoes$
DECLARE
  a record;
  v_user uuid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1);
  v_nome text := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' LIMIT 1) LIMIT 1), 'Gestora de RH');
BEGIN
  FOR a IN
    SELECT * FROM (VALUES
      (1, 3,  'Substituir filtros vencidos dos respiradores e auditar validades dos EPIs da solda', 'em_andamento', 55, 5,  'imediato', 'corretiva', 'Técnico de Segurança do Trabalho', 'Levantar todos os respiradores e filtros, descartar os vencidos, repor estoque mínimo e criar controle mensal de validade.'),
      (2, 12, 'Definir regra de comunicação prévia para mudanças na escala de sobreaviso', 'pendente', 0, 14, 'urgente', 'preventiva', 'Supervisor de Manutenção', 'Aviso mínimo de 7 dias, consulta à equipe e registro da alteração no sistema de escalas.'),
      (3, 14, 'Enclausuramento parcial e protetores de maior atenuação na usinagem 3', 'concluida', 100, -25, 'urgente', 'corretiva', 'Supervisor de Manutenção', 'Instalar painel acústico, trocar protetores e refazer a dosimetria de ruído.'),
      (4, 4,  'Treinamento de respeito e diversidade para todos os turnos', 'concluida', 100, -30, 'urgente', 'preventiva', 'Analista de RH', 'Oficinas de 1 hora por turno, lista de presença e reforço do código de conduta.'),
      (5, 1,  'Treinamento de liderança para encarregados do turno B', 'em_andamento', 30, 20, 'urgente', 'preventiva', 'Analista de RH', 'Trilha de 3 encontros sobre feedback, cobrança de metas e comunicação respeitosa.'),
      (6, 31, 'Reparo elétrico urgente da máquina de solda do posto 4', 'em_andamento', 70, 1, 'imediato', 'corretiva', 'Supervisor de Manutenção', 'Bloquear o posto, revisar aterramento e isolação e liberar após laudo do eletricista.'),
      (7, 8,  'Reparar o ar-condicionado da sala do administrativo', 'pendente', 0, 9, 'medio', 'corretiva', 'Comprador', 'Solicitar três orçamentos de manutenção e agendar o reparo.')
    ) AS x(n, ouv, titulo, status, progresso, prazo_dias, prioridade, tipo, responsavel, como)
  LOOP
    IF EXISTS (SELECT 1 FROM public.plano_acoes p WHERE p.id = public.demo_id('ouv_acao:' || a.n)) THEN CONTINUE; END IF;
    INSERT INTO public.plano_acoes (
      id, tenant_id, empresa_id, codigo, titulo, descricao, porque, onde, como, prazo, responsavel_nome, origem_modulo, origem_id,
      origem_descricao, gravidade, urgencia, tendencia, prioridade, status, progresso, data_inicio, data_conclusao,
      exige_evidencia, tipo, tempo_gasto_minutos, criado_por, criado_por_nome, created_at
    )
    SELECT public.demo_id('ouv_acao:' || a.n), o.tenant_id, 'd3e00000-0000-4000-8000-000000000002', '', a.titulo,
           'Tratativa da manifestação da Ouvidoria: ' || o.assunto,
           'Manifestação recebida pela Ouvidoria (' || o.tipo || ')', 'Metalúrgica Exemplo', a.como,
           CURRENT_DATE + a.prazo_dias, a.responsavel, 'ouvidoria', o.id,
           (CASE o.tipo WHEN 'sugestao' THEN 'Sugestão' WHEN 'reclamacao' THEN 'Reclamação' WHEN 'denuncia' THEN 'Denúncia'
                        WHEN 'elogio' THEN 'Elogio' ELSE 'Dúvida' END) || ': ' || o.assunto,
           CASE WHEN a.prioridade = 'imediato' THEN 4 ELSE 3 END, CASE WHEN a.prioridade = 'imediato' THEN 5 ELSE 3 END, 3,
           a.prioridade::public.acao_gut_prioridade, a.status::public.acao_status, a.progresso,
           CASE WHEN a.status = 'pendente' THEN NULL ELSE LEAST(CURRENT_DATE, CURRENT_DATE + a.prazo_dias) - 10 END,
           CASE WHEN a.status = 'concluida' THEN CURRENT_DATE + a.prazo_dias END,
           false, a.tipo, 0, v_user, v_nome, o.created_at + interval '1 day'
      FROM public.ouvidoria o WHERE o.id = public.demo_id('ouv:' || a.ouv);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Acoes ligadas a Ouvidoria nao concluidas: % (%)', SQLERRM, SQLSTATE;
END $ouv_acoes$;

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.humor_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS humor_registros,
  (SELECT count(*) FROM public.humor_historico WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS humor_historico,
  (SELECT count(*) FROM public.bem_estar_respostas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS bem_estar_respostas,
  (SELECT count(*) FROM public.bem_estar_gratidao WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS gratidao,
  (SELECT count(*) FROM public.ouvidoria WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS manifestacoes,
  (SELECT count(DISTINCT status) FROM public.ouvidoria WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS status_distintos,
  (SELECT count(DISTINCT tipo) FROM public.ouvidoria WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS tipos_distintos,
  (SELECT count(*) FROM public.plano_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND origem_modulo = 'ouvidoria') AS tratativas,
  CASE WHEN (SELECT count(*) FROM public.ouvidoria WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 32
        AND (SELECT count(*) FROM public.humor_diario WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') > 500
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
