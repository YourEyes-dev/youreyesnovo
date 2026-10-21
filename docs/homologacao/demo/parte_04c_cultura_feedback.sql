-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 04c: Cultura & Celebracoes (/cultura-celebracoes, manual de cultura) e Feedback & Ocorrencias (/feedback-ocorrencias)
--
-- PARA QUE SERVE
-- Preenche, na "Metalurgica Exemplo Ltda" (tenant demo da parte 00):
--   * Cultura & Celebracoes: configuracao, marcos de tempo de casa, datas
--     comemorativas, dias da profissao decididos pela empresa, rituais de
--     reconhecimento (alguns vencendo hoje), preferencias dos colaboradores e
--     o historico de acoes de celebracao (aniversarios e tempo de casa dos
--     ultimos 12 meses, calculados a partir das datas reais dos colaboradores
--     ficticios; pendentes, atrasadas, concluidas e canceladas), alem das
--     proximas celebracoes ainda sem acao;
--   * Missao, visao, valores e manual de cultura (aba Cultura do modulo
--     Estrategia, "Manual de Cultura");
--   * Feedback & Ocorrencias: feedbacks (reconhecimento, alinhamento e
--     desenvolvimento), ocorrencias positivas, neutras e negativas,
--     advertencias com os links de assinatura em todos os status.
-- Rodar DEPOIS da parte 00.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO (a trava abaixo recusa qualquer outro banco).
--
-- GARANTIAS
--   - Idempotente (ids fixos + "so insere se nao existe"); nao cria tabela;
--     so toca o tenant demo; nenhum dado real (colaboradores e e-mails ficticios).
--   - Datas relativas a hoje: a lista de celebracoes se renova a cada dia em
--     que o script e rodado pela primeira vez (as acoes ja criadas ficam).
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
-- (1) Cultura — configuracao, marcos de tempo de casa e datas comemorativas
-- ---------------------------------------------------------------------------
INSERT INTO public.cultura_config (
  id, tenant_id, empresa_id, aniversario_ativo, tempo_casa_ativo, dia_profissao_ativo, dias_antecedencia_acao, presente_padrao,
  limite_valor_presente, folga_permitida, responsavel_padrao, automacao_aniversario, automacao_tempo_casa, tom_mensagem,
  meta_cobertura, lembrar_gestor
)
SELECT public.demo_id('cult_cfg:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       true, true, true, 30, true, 80, true, 'rh', 'aprovar', 'aprovar', 'leve', 90, true
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_config WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001');

INSERT INTO public.cultura_marcos (id, tenant_id, empresa_id, anos, tipo_celebracao, descricao, ativo)
SELECT public.demo_id('cult_marco:' || v.anos), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.anos, v.tipo, v.descricao, true
FROM (VALUES
  (1,  'certificado',    'Certificado de 1 ano de casa entregue pelo gestor na reunião de equipe.'),
  (3,  'mimo',           'Kit de brinde da empresa e cartão assinado pela diretoria.'),
  (5,  'reconhecimento', 'Reconhecimento público no mural e no encontro mensal da fábrica.'),
  (10, 'publico',        'Homenagem pública na confraternização anual, com placa comemorativa.'),
  (15, 'mimo',           'Vale-presente e folga de aniversário de casa.'),
  (20, 'publico',        'Homenagem especial da diretoria, com jantar para a família.')
) AS v(anos, tipo, descricao)
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_marcos m WHERE m.id = public.demo_id('cult_marco:' || v.anos));

INSERT INTO public.cultura_datas (id, tenant_id, empresa_id, titulo, descricao, tipo, recorrencia, mes, dia, data_especifica, ativo)
SELECT public.demo_id('cult_data:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.titulo, v.descricao, v.tipo, v.recorr, v.mes, v.dia,
       CASE WHEN v.dias_ate IS NULL THEN NULL ELSE CURRENT_DATE + v.dias_ate END, true
FROM (VALUES
  (1,  'Dia Internacional da Mulher', 'Homenagem às colaboradoras com café da manhã e palestra.', 'comemorativa', 'anual', 3, 8, NULL::int),
  (2,  'Dia do Trabalhador', 'Mensagem da diretoria e sorteio de brindes.', 'comemorativa', 'anual', 5, 1, NULL),
  (3,  'Dia do Meio Ambiente', 'Campanha de coleta seletiva e plantio de mudas na unidade.', 'campanha', 'anual', 6, 5, NULL),
  (4,  'Festa Junina da Fábrica', 'Confraternização com comidas típicas, organizada pelo comitê de cultura.', 'regional', 'anual', 6, 20, NULL),
  (5,  'Dia Nacional de Prevenção de Acidentes (SIPAT)', 'Abertura da Semana Interna de Prevenção de Acidentes do Trabalho.', 'campanha', 'anual', 7, 27, NULL),
  (6,  'Aniversário da Metalúrgica Exemplo', 'Comemoração do aniversário da empresa com todos os turnos.', 'interna', 'anual', 8, 15, NULL),
  (7,  'Setembro Amarelo', 'Campanha de valorização da vida e saúde mental, com rodas de conversa.', 'campanha', 'anual', 9, 1, NULL),
  (8,  'Outubro Rosa', 'Campanha de conscientização sobre o câncer de mama, com exames e palestra.', 'campanha', 'anual', 10, 1, NULL),
  (9,  'Novembro Azul', 'Campanha de saúde do homem, com orientação sobre exames preventivos.', 'campanha', 'anual', 11, 1, NULL),
  (10, 'Dia da Consciência Negra', 'Roda de conversa sobre diversidade e inclusão.', 'comemorativa', 'anual', 11, 20, NULL),
  (11, 'Natal e confraternização de fim de ano', 'Almoço de encerramento do ano com sorteios e homenagens de tempo de casa.', 'interna', 'anual', 12, 12, NULL),
  (12, 'Inauguração do novo refeitório', 'Evento de inauguração com a diretoria e todos os turnos.', 'interna', 'unica', NULL, NULL, 33)
) AS v(n, titulo, descricao, tipo, recorr, mes, dia, dias_ate)
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_datas d WHERE d.id = public.demo_id('cult_data:' || v.n));

-- Decisoes da empresa sobre o Dia da Profissao (IA aprovada, rejeitada ou manual)
INSERT INTO public.cultura_dias_profissao (id, tenant_id, cargo_chave, cargo_exemplo, nome_data, mes, dia, status, origem, confianca, base)
SELECT public.demo_id('cult_prof:' || v.chave), 'd3e00000-0000-4000-8000-000000000001', v.chave, v.cargo, v.nome_data, v.mes, v.dia,
       v.status, v.origem, v.confianca, v.base
FROM (VALUES
  ('operador de usinagem cnc', 'Operador de Usinagem CNC', 'Dia do Operador de Usinagem', 4, 22, 'aprovado', 'manual', NULL, 'Data definida pela própria empresa para homenagear a equipe da usinagem.'),
  ('analista da qualidade', 'Analista da Qualidade', 'Dia da Qualidade', 11, 14, 'aprovado', 'manual', NULL, 'Data definida pela empresa, alinhada ao mês da qualidade.'),
  ('comprador', 'Comprador', 'Dia do Comprador', 10, 20, 'aprovado', 'ia', 'media', 'Sugestão da IA aprovada pelo RH; data confirmada com a área de Compras.'),
  ('auxiliar de logistica', 'Auxiliar de Logística', NULL, NULL, NULL, 'rejeitado', 'ia', 'baixa', 'Sugestão da IA sem data oficial reconhecida; RH optou por não celebrar.')
) AS v(chave, cargo, nome_data, mes, dia, status, origem, confianca, base)
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_dias_profissao x WHERE x.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND x.cargo_chave = v.chave);

-- ---------------------------------------------------------------------------
-- (2) Rituais de reconhecimento (alguns vencem hoje ou estao atrasados) e
--     preferencias dos colaboradores
-- ---------------------------------------------------------------------------
INSERT INTO public.cultura_rituais (id, tenant_id, empresa_id, nome, descricao, frequencia, dia_semana, dia_mes, responsavel, responsavel_nome, ativo, ultima_execucao, proxima_execucao)
SELECT public.demo_id('cult_ritual:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.nome, v.descricao, v.freq, v.dsem, v.dmes, v.resp, v.resp_nome, v.ativo,
       CURRENT_DATE + v.ult, CASE WHEN v.prox IS NULL THEN NULL ELSE CURRENT_DATE + v.prox END
FROM (VALUES
  (1, 'Diálogo Diário de Segurança (DDS)', 'Conversa de 10 minutos no início de cada turno sobre um tema de segurança, com reconhecimento de boas práticas.', 'semanal', 1, NULL::int, 'lider', 'Líderes de turno', true, -7, 0),
  (2, 'Reconhecimento do Colaborador do Mês', 'Votação pelos pares e entrega de certificado na reunião mensal da fábrica.', 'mensal', NULL, 28, 'rh', 'Analista de RH', true, -20, 8),
  (3, 'Almoço de Aniversariantes do Mês', 'Almoço no refeitório com os aniversariantes de todos os turnos e a diretoria.', 'mensal', NULL, 15, 'cultura', 'Comitê de Cultura', true, -34, -4),
  (4, 'Café com a Diretoria', 'Encontro trimestral de 1 hora entre a diretoria e uma amostra de colaboradores de cada setor.', 'trimestral', NULL, NULL, 'rh', 'Gerente Administrativo', true, -60, 31),
  (5, 'Mural de Conquistas', 'Atualização quinzenal do mural com resultados, elogios e aniversariantes.', 'quinzenal', NULL, NULL, 'cultura', 'Comitê de Cultura', true, -12, 2),
  (6, 'Ginástica Laboral', 'Alongamento coletivo de 10 minutos, três vezes por semana, conduzido pela fisioterapeuta parceira.', 'semanal', 3, NULL, 'rh', 'Técnico de Segurança do Trabalho', false, -40, NULL)
) AS v(n, nome, descricao, freq, dsem, dmes, resp, resp_nome, ativo, ult, prox)
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_rituais r WHERE r.id = public.demo_id('cult_ritual:' || v.n));

INSERT INTO public.cultura_preferencias (id, tenant_id, colaborador_id, colaborador_nome, preferencia_aniversario, tipo_reconhecimento, observacoes)
SELECT public.demo_id('cult_pref:' || v.adm), a.tenant_id, a.id::text, a.nome_completo, v.pref, v.reconhecimento, v.obs
FROM (VALUES
  (3,  'experiencia', 'publico',   'Gosta de comemorar com a equipe no refeitório.'),
  (7,  'folga',       'reservado', 'Prefere não ser exposto(a) no mural; folga no dia do aniversário.'),
  (12, 'presente',    'tanto_faz', NULL),
  (15, 'experiencia', 'publico',   'Adora bolo de cenoura.'),
  (21, 'indiferente', 'reservado', 'Tímido(a); parabéns só por mensagem privada.'),
  (28, 'folga',       'publico',   NULL),
  (31, 'presente',    'tanto_faz', 'Torcedor(a) fanático(a) de futebol; vale-presente em loja de esportes.'),
  (40, 'experiencia', 'publico',   NULL),
  (46, 'presente',    'reservado', 'Prefere receber o presente em mãos, sem cerimônia.'),
  (53, 'folga',       'tanto_faz', 'Estuda à noite; prefere folga em vez de festa.'),
  (58, 'experiencia', 'publico',   NULL)
) AS v(adm, pref, reconhecimento, obs)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.adm)
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_preferencias p WHERE p.tenant_id = a.tenant_id AND p.colaborador_id = a.id::text);

-- ---------------------------------------------------------------------------
-- (3) Acoes de celebracao: aniversarios e tempo de casa dos ultimos 12 meses
--     (a tela identifica a pessoa pelo NOME: onde ha dois colaboradores com o
--     mesmo nome na parte 00, so o primeiro recebe a acao)
--     (calculados a partir das datas dos colaboradores). Concluidas, algumas
--     atrasadas, poucas canceladas; as dos proximos 10 dias ficam pendentes ou
--     em andamento; as de 11 a 45 dias ainda nao tem acao (aparecem em
--     "Proximas celebracoes" com o botao de criar).
-- ---------------------------------------------------------------------------
INSERT INTO public.cultura_acoes (
  id, tenant_id, empresa_id, tipo, titulo, descricao, colaborador_id, colaborador_nome, data_referencia, data_execucao,
  responsavel, responsavel_nome, status, observacoes, origem, chave_unica, publicado_em, created_at
)
SELECT DISTINCT ON (e.chave) public.demo_id('cult_acao:' || e.chave), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       e.tipo, e.titulo, NULL, e.id::text, e.nome, e.data,
       CASE WHEN e.status = 'concluida' THEN e.data + (e.h % 2) END,
       'rh', 'Analista de RH', e.status,
       CASE WHEN e.status = 'concluida' AND e.h % 4 = 0 THEN 'Bolo e cartão assinado pela equipe.'
            WHEN e.status = 'concluida' AND e.h % 4 = 1 THEN 'Parabéns no mural e na reunião do turno.'
            WHEN e.status = 'cancelada' THEN 'Colaborador de férias na data; celebração não realizada.' END,
       CASE WHEN e.h % 3 = 0 THEN 'automatica' ELSE 'manual' END,
       e.chave,
       CASE WHEN e.status = 'concluida' AND e.h % 3 <> 1 THEN e.data::timestamptz + interval '9 hours' END,
       LEAST(e.data - 7, CURRENT_DATE)::timestamptz + interval '8 hours'
FROM (
  SELECT x.*,
         CASE
           WHEN x.data < CURRENT_DATE - 3 AND x.data >= CURRENT_DATE - 40 AND x.h < 40 THEN 'pendente'
           WHEN x.data < CURRENT_DATE - 3 AND x.h < 8 THEN 'cancelada'
           WHEN x.data < CURRENT_DATE - 3 THEN 'concluida'
           WHEN x.h < 150 THEN 'pendente'
           ELSE 'em_andamento'
         END AS status
  FROM (
    SELECT p.id, p.nome_completo AS nome, ev.tipo, ev.data, ev.anos,
           ev.tipo || '|' || lower(trim(p.nome_completo)) || '|' || extract(year FROM ev.data)::int AS chave,
           CASE WHEN ev.tipo = 'aniversario' THEN 'Aniversário de ' || p.nome_completo
                ELSE ev.anos || CASE WHEN ev.anos > 1 THEN ' anos' ELSE ' ano' END || ' de empresa - ' || p.nome_completo END AS titulo,
           get_byte(decode(substr(md5(p.id::text || ev.tipo || ev.data::text), 1, 8), 'hex'), 0) AS h
      FROM (SELECT a.id, a.nome_completo, a.data_nascimento, a.data_admissao
              FROM public.admissoes a
             WHERE a.tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND a.status::text = 'concluido') p
      CROSS JOIN LATERAL (
        SELECT 'aniversario' AS tipo,
               (make_date(y, extract(month FROM p.data_nascimento)::int, 1)
                  + (LEAST(extract(day FROM p.data_nascimento)::int,
                           extract(day FROM (make_date(y, extract(month FROM p.data_nascimento)::int, 1) + interval '1 month' - interval '1 day'))::int) - 1)) AS data,
               NULL::int AS anos
          FROM generate_series(extract(year FROM CURRENT_DATE)::int - 1, extract(year FROM CURRENT_DATE)::int + 1) AS y
         WHERE p.data_nascimento IS NOT NULL
        UNION ALL
        SELECT 'tempo_casa',
               (make_date(y, extract(month FROM p.data_admissao)::int, 1)
                  + (LEAST(extract(day FROM p.data_admissao)::int,
                           extract(day FROM (make_date(y, extract(month FROM p.data_admissao)::int, 1) + interval '1 month' - interval '1 day'))::int) - 1)),
               y - extract(year FROM p.data_admissao)::int
          FROM generate_series(extract(year FROM CURRENT_DATE)::int - 1, extract(year FROM CURRENT_DATE)::int + 1) AS y
         WHERE p.data_admissao IS NOT NULL AND y - extract(year FROM p.data_admissao)::int >= 1
      ) ev
     WHERE ev.data BETWEEN CURRENT_DATE - 365 AND CURRENT_DATE + 10
  ) x
) e
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_acoes c WHERE c.id = public.demo_id('cult_acao:' || e.chave))
  AND NOT EXISTS (SELECT 1 FROM public.cultura_acoes c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
                    AND c.chave_unica = e.chave AND c.status <> 'cancelada')
ORDER BY e.chave, e.id;

-- Acoes manuais: dias da profissao, datas configuradas e rituais
INSERT INTO public.cultura_acoes (
  id, tenant_id, empresa_id, tipo, titulo, descricao, colaborador_id, colaborador_nome, data_referencia, data_execucao,
  responsavel, responsavel_nome, status, observacoes, cultura_data_id, origem, chave_unica, publicado_em, created_at
)
SELECT public.demo_id('cult_acao_m:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       v.tipo, v.titulo, v.descricao, NULL, NULL, v.data, CASE WHEN v.status = 'concluida' THEN v.data END,
       v.resp, v.resp_nome, v.status, v.obs,
       CASE WHEN v.cdata IS NULL THEN NULL ELSE public.demo_id('cult_data:' || v.cdata) END,
       'manual',
       CASE WHEN v.tipo = 'dia_profissao' THEN 'dia_profissao|' || lower(v.titulo) || '|' || extract(year FROM v.data)::int END,
       CASE WHEN v.status = 'concluida' AND v.tipo <> 'ritual' THEN v.data::timestamptz + interval '8 hours' END,
       (v.data - 10)::timestamptz + interval '8 hours'
FROM (
  SELECT n, tipo, titulo, descricao, status, resp, resp_nome, obs, cdata,
         CASE WHEN fix IS NOT NULL THEN CURRENT_DATE + fix
              ELSE (CASE WHEN make_date(extract(year FROM CURRENT_DATE)::int, mes, dia) > CURRENT_DATE
                         THEN make_date(extract(year FROM CURRENT_DATE)::int - 1, mes, dia)
                         ELSE make_date(extract(year FROM CURRENT_DATE)::int, mes, dia) END) END AS data
  FROM (VALUES
    (1,  'dia_profissao',   'Dia do Soldador', 'Homenagem à equipe de solda com café especial e brinde.', 'concluida', 'rh', 'Analista de RH', 'Entrega de brinde no início do turno.', NULL::int, 5, 29, NULL::int),
    (2,  'dia_profissao',   'Dia do Profissional de RH', 'Mensagem do time de Produção para a equipe de RH.', 'concluida', 'cultura', 'Comitê de Cultura', NULL, NULL, 6, 3, NULL),
    (3,  'dia_profissao',   'Dia do Eletricista', 'Café da manhã com a equipe de eletricistas e mensagem da diretoria.', 'pendente', 'rh', 'Analista de RH', 'Não realizado na data; reagendar com a supervisão.', NULL, 10, 17, NULL),
    (4,  'data_configurada','Dia Nacional de Prevenção de Acidentes (SIPAT)', 'Abertura da SIPAT com palestra e gincana de segurança.', 'concluida', 'rh', 'Técnico de Segurança do Trabalho', 'Participação de 92% dos colaboradores.', 5, 7, 27, NULL),
    (5,  'data_configurada','Aniversário da Metalúrgica Exemplo', 'Almoço comemorativo e homenagem de tempo de casa.', 'concluida', 'cultura', 'Comitê de Cultura', NULL, 6, 8, 15, NULL),
    (6,  'data_configurada','Setembro Amarelo', 'Rodas de conversa sobre saúde mental em todos os turnos.', 'concluida', 'rh', 'Analista de RH', 'Quatro rodas de conversa realizadas.', 7, 9, 1, NULL),
    (7,  'data_configurada','Outubro Rosa', 'Palestra, exames preventivos e laço rosa na entrada da fábrica.', 'em_andamento', 'rh', 'Analista de RH', 'Exames agendados para a próxima semana.', 8, 10, 1, NULL),
    (8,  'data_configurada','Novembro Azul', 'Palestra sobre saúde do homem e orientação sobre exames.', 'pendente', 'rh', 'Analista de RH', NULL, 9, NULL, NULL, 12),
    (9,  'data_configurada','Natal e confraternização de fim de ano', 'Definir local, cardápio e sorteios.', 'pendente', 'cultura', 'Comitê de Cultura', 'Orçamento em aprovação.', 11, NULL, NULL, 53),
    (10, 'ritual',          'Reconhecimento do Colaborador do Mês — setembro', 'Certificado entregue na reunião mensal.', 'concluida', 'rh', 'Analista de RH', NULL, NULL, 9, 28, NULL),
    (11, 'ritual',          'Reconhecimento do Colaborador do Mês — outubro', 'Votação aberta no mural.', 'pendente', 'rh', 'Analista de RH', NULL, NULL, NULL, NULL, 8)
  ) AS t(n, tipo, titulo, descricao, status, resp, resp_nome, obs, cdata, mes, dia, fix)
) v
WHERE NOT EXISTS (SELECT 1 FROM public.cultura_acoes c WHERE c.id = public.demo_id('cult_acao_m:' || v.n))
  AND (v.tipo <> 'dia_profissao' OR NOT EXISTS (
        SELECT 1 FROM public.cultura_acoes c WHERE c.tenant_id = 'd3e00000-0000-4000-8000-000000000001'
           AND c.chave_unica = 'dia_profissao|' || lower(v.titulo) || '|' || extract(year FROM v.data)::int AND c.status <> 'cancelada'));

-- ---------------------------------------------------------------------------
-- (4) Missao, visao, valores e manual de cultura (aba Cultura da Estrategia)
-- ---------------------------------------------------------------------------
INSERT INTO public.estrategia_cultura (
  id, tenant_id, empresa_id, missao, visao, valores, principios, comportamentos_esperados, comportamentos_nao_tolerados,
  criado_por_nome, proposito, carta_boas_vindas, tom_de_voz, codigo_conduta, dress_code, modelo_trabalho
)
SELECT public.demo_id('estr_cultura:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'Fabricar estruturas metálicas seguras e duráveis, cuidando das pessoas que as constroem.',
       'Ser a metalúrgica de referência do Sul do Brasil em segurança, qualidade e desenvolvimento de pessoas até 2030.',
       '["Segurança em primeiro lugar","Respeito às pessoas","Qualidade em cada detalhe","Compromisso com o cliente","Melhoria contínua","Honestidade e transparência"]'::jsonb,
       '["Nenhum resultado vale um acidente","Quem faz, sabe: o chão de fábrica é ouvido","Decisões com base em dados","Errar é aprender; esconder o erro não","Cada turno é uma só equipe"]'::jsonb,
       '["Usar os EPIs corretamente, sempre","Interromper a atividade quando houver risco","Dar e pedir feedback com respeito","Cumprir combinados e avisar quando não for possível","Compartilhar conhecimento com colegas novos","Zelar pelo patrimônio e pela organização do posto"]'::jsonb,
       '["Assédio moral ou sexual de qualquer natureza","Discriminação por origem, gênero, religião, orientação ou aparência","Burlar dispositivos de segurança","Esconder acidentes ou quase-acidentes","Uso de álcool ou drogas durante a jornada","Retaliação a quem faz uma denúncia"]'::jsonb,
       'Equipe de RH (demonstração)',
       'Construir estruturas que sustentam o trabalho e a vida de milhares de famílias, com segurança e orgulho.',
       'Seja bem-vindo(a) à Metalúrgica Exemplo! Aqui, cuidar de você vem antes de qualquer meta. Nos primeiros dias, seu líder e um colega de apoio vão te acompanhar, mostrar os postos, os EPIs e os canais para tirar dúvidas. Conte conosco.',
       'Direto, respeitoso e próximo. Falamos a língua do chão de fábrica, sem jargão desnecessário, e sempre explicamos o porquê das regras.',
       'Nosso Código de Conduta reúne as regras de convivência, segurança, uso de recursos e relacionamento com clientes e fornecedores. Dúvidas ou denúncias podem ser feitas a qualquer momento pela Ouvidoria, de forma identificada ou anônima.',
       'Uniforme completo e EPIs em áreas produtivas. No administrativo, traje casual (sem chinelos).',
       'Presencial na fábrica e nas filiais; administrativo com 1 dia de home office por semana, mediante combinado com o gestor.'
WHERE NOT EXISTS (SELECT 1 FROM public.estrategia_cultura WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND empresa_id = 'd3e00000-0000-4000-8000-000000000002');

INSERT INTO public.manuais_gerados (id, tenant_id, empresa_id, tipo, titulo, html, gerado_por_nome, created_at)
SELECT public.demo_id('manual_cultura:1'), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       'cultura', 'Manual de Cultura — Metalúrgica Exemplo',
       '<h1>Manual de Cultura</h1><h2>Metalúrgica Exemplo Ltda</h2>'
       || '<h3>Nossa missão</h3><p>Fabricar estruturas metálicas seguras e duráveis, cuidando das pessoas que as constroem.</p>'
       || '<h3>Nossa visão</h3><p>Ser a metalúrgica de referência do Sul do Brasil em segurança, qualidade e desenvolvimento de pessoas até 2030.</p>'
       || '<h3>Nossos valores</h3><ul><li>Segurança em primeiro lugar</li><li>Respeito às pessoas</li><li>Qualidade em cada detalhe</li><li>Compromisso com o cliente</li><li>Melhoria contínua</li><li>Honestidade e transparência</li></ul>'
       || '<h3>Como nos comportamos</h3><ul><li>Usamos os EPIs corretamente, sempre.</li><li>Interrompemos a atividade quando há risco.</li><li>Damos e pedimos feedback com respeito.</li><li>Compartilhamos conhecimento com os colegas novos.</li></ul>'
       || '<h3>O que não toleramos</h3><ul><li>Assédio moral ou sexual</li><li>Discriminação de qualquer natureza</li><li>Burlar dispositivos de segurança</li><li>Retaliação a quem faz uma denúncia</li></ul>'
       || '<p><em>Documento de demonstração gerado a partir da aba Cultura do módulo Estratégia.</em></p>',
       'Equipe de RH (demonstração)', now() - interval '20 days'
WHERE NOT EXISTS (SELECT 1 FROM public.manuais_gerados WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND tipo = 'cultura');

-- ---------------------------------------------------------------------------
-- (5) Feedback & Ocorrencias
-- ---------------------------------------------------------------------------
INSERT INTO public.feedbacks (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cargo, colaborador_departamento, colaborador_filial,
  categoria, descricao, descricao_ia, ia_utilizada, registrado_por, registrado_por_nome, enviado_email, created_at, updated_at
)
SELECT public.demo_id('fb:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.id::text, a.nome_completo, a.cargo, a.departamento, a.filial,
       v.categoria::public.feedback_categoria, v.descricao, v.descricao_ia, (v.descricao_ia IS NOT NULL),
       COALESCE(r.id, u.uid), COALESCE(r.nome_completo, u.nome), (v.n % 3 <> 0),
       (CURRENT_DATE - v.dias)::timestamptz + (9 + v.n % 7) * interval '1 hour', (CURRENT_DATE - v.dias)::timestamptz + (9 + v.n % 7) * interval '1 hour'
FROM (VALUES
  (1,  'reconhecimento',  3,  28, 3,  'Parabéns pela atenção na troca de ferramenta da CNC 4: você percebeu o desgaste antes de gerar refugo e evitou a parada da linha.', 'Parabéns pela sua atenção durante a troca de ferramenta da CNC 4. Ao perceber o desgaste a tempo, você evitou refugo e uma parada da linha. Obrigado por cuidar da qualidade e do resultado do time!'),
  (2,  'reconhecimento',  15, 28, 6,  'Ótimo trabalho na soldagem das estruturas do pedido da obra do cliente: zero retrabalho na inspeção.', NULL),
  (3,  'desenvolvimento', 22, 28, 9,  'Você tem boa habilidade na montagem. Para crescer, quero que se prepare para a leitura de desenhos técnicos. Vamos montar um plano de estudo e um curso curto.', 'Percebo seu bom desempenho na montagem e vejo potencial de crescimento. Para o próximo passo, sugiro que aprofunde a leitura de desenhos técnicos; vamos montar juntos um plano de estudo e um curso curto.'),
  (4,  'alinhamento',     9,  28, 12, 'Conversamos sobre os atrasos na troca de turno nas últimas duas semanas. Combinamos chegar 10 minutos antes para a passagem de turno.', NULL),
  (5,  'reconhecimento',  31, 40, 5,  'Atendimento rápido da parada da linha 2 de madrugada, com segurança e organização. Equipe reconhecida pela diretoria.', NULL),
  (6,  'desenvolvimento', 37, 40, 14, 'Quero que você assuma a manutenção preventiva das empilhadeiras. Vamos combinar um treinamento com o fornecedor e acompanhamento nas primeiras semanas.', NULL),
  (7,  'alinhamento',     33, 40, 17, 'Alinhamos a forma de registrar as ordens de serviço no sistema. Daqui para frente, toda intervenção deve ser registrada no mesmo dia.', 'Alinhamos a importância de registrar toda ordem de serviço no sistema no mesmo dia da intervenção, para termos histórico confiável dos equipamentos.'),
  (8,  'reconhecimento',  44, 52, 11, 'Excelente organização do estoque no inventário de fim de mês: divergência abaixo de 0,3%.', NULL),
  (9,  'alinhamento',     47, 52, 20, 'Conversamos sobre o uso correto do cinto de segurança na empilhadeira. O combinado: nenhuma exceção, nem em manobras curtas.', NULL),
  (10, 'desenvolvimento', 46, 52, 25, 'Você mostrou interesse em operar empilhadeira. Vamos inscrevê-lo(a) no treinamento NR-11 no próximo ciclo.', NULL),
  (11, 'reconhecimento',  53, 58, 7,  'Parabéns pelo fechamento financeiro do mês sem pendências. A conciliação ficou impecável.', NULL),
  (12, 'desenvolvimento', 55, 58, 30, 'Seu relatório de não conformidades ficou claro e objetivo. Vamos apresentá-lo na reunião de qualidade e ampliar o escopo para os fornecedores.', NULL),
  (13, 'alinhamento',     57, NULL, 36,'Alinhamento sobre prazos de cotação: acordamos pelo menos três propostas antes de qualquer compra acima de R$ 5 mil.', NULL),
  (14, 'reconhecimento',  58, NULL, 42,'Obrigado pela condução da campanha de vacinação: organização, comunicação e adesão acima do esperado.', 'Obrigado pela condução da campanha de vacinação. A organização, a comunicação clara e a adesão acima do esperado mostram o cuidado do RH com as pessoas.'),
  (15, 'desenvolvimento', 59, NULL, 48,'Plano de desenvolvimento: ampliar sua atuação em indicadores de RH (turnover, absenteísmo) e apresentar mensalmente à diretoria.', NULL),
  (16, 'reconhecimento',  1,  28, 55, 'Reconhecimento pela sugestão de melhoria no gabarito de fixação, que reduziu o tempo de setup em 12 minutos.', NULL),
  (17, 'alinhamento',     18, 28, 60, 'Conversamos sobre a pausa para descanso na solda: respeitar o intervalo é uma regra de saúde, não de produtividade.', NULL),
  (18, 'desenvolvimento', 36, 40, 66, 'Quero que você faça o curso de NR-10 para assumir intervenções em painéis de média tensão no próximo semestre.', NULL),
  (19, 'reconhecimento',  24, 28, 72, 'Parabéns pela receptividade com os novos colegas na montagem: o time elogiou sua paciência ao ensinar.', NULL),
  (20, 'alinhamento',     52, NULL, 80,'Alinhamos metas de expedição para o trimestre e a comunicação com a transportadora em atrasos.', NULL),
  (21, 'reconhecimento',  41, 52, 90, 'Ótimo trabalho na recepção do lote de chapas, com conferência cuidadosa e registro correto.', NULL),
  (22, 'desenvolvimento', 56, 58, 97, 'Vamos preparar você para auditorias internas da ISO 9001; indico o curso de auditor interno ainda neste ano.', NULL),
  (23, 'alinhamento',     30, 40, 105,'Reforço sobre o bloqueio e etiquetagem (LOTO) antes de qualquer intervenção. Nenhuma exceção.', NULL),
  (24, 'reconhecimento',  13, 28, 112,'Obrigado por assumir o turno extra durante a parada do colega, mantendo a entrega ao cliente.', NULL)
) AS v(n, categoria, adm, reg, dias, descricao, descricao_ia)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.adm)
LEFT JOIN public.admissoes r ON r.id = public.demo_id('admissao:' || v.reg)
CROSS JOIN (SELECT (SELECT x.id FROM auth.users x WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1) AS uid,
                   COALESCE((SELECT p.nome_completo FROM public.profiles p JOIN auth.users x ON x.id = p.user_id
                              WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Gestora de RH') AS nome) u
WHERE u.uid IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.feedbacks f WHERE f.id = public.demo_id('fb:' || v.n));

INSERT INTO public.ocorrencias (
  id, tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cargo, colaborador_departamento, colaborador_filial,
  tipo, descricao, is_advertencia, registrado_por, registrado_por_nome, data_ocorrencia, bloqueado, created_at, updated_at
)
SELECT public.demo_id('oc:' || v.n), 'd3e00000-0000-4000-8000-000000000001', 'd3e00000-0000-4000-8000-000000000002',
       a.id::text, a.nome_completo, a.cargo, a.departamento, a.filial,
       v.tipo::public.ocorrencia_tipo, v.descricao, v.adv, COALESCE(r.id, u.uid), COALESCE(r.nome_completo, u.nome),
       (CURRENT_DATE - v.dias)::timestamptz + (8 + v.n % 8) * interval '1 hour', v.adv,
       (CURRENT_DATE - v.dias)::timestamptz + (9 + v.n % 8) * interval '1 hour', (CURRENT_DATE - v.dias)::timestamptz + (9 + v.n % 8) * interval '1 hour'
FROM (VALUES
  (1,  'positiva', 3,  28, 4,   'Apontou vazamento de óleo na CNC 4 antes que gerasse acidente e isolou a área até a chegada da manutenção.', false),
  (2,  'positiva', 15, 28, 18,  'Sugestão de melhoria no posto de solda aprovada pela engenharia e implantada no turno B.', false),
  (3,  'positiva', 31, 40, 26,  'Atendeu chamado de emergência fora do horário e restabeleceu a linha 2 em duas horas.', false),
  (4,  'positiva', 44, 52, 33,  'Zero divergência de estoque no inventário trimestral do CD Itajaí.', false),
  (5,  'positiva', 58, NULL, 40,'Conduziu a integração dos três novos colaboradores de forma acolhedora e organizada.', false),
  (6,  'positiva', 22, 28, 61,  'Ajudou colega com mal-estar e acionou a brigada de emergência rapidamente.', false),
  (7,  'neutra',   9,  28, 12,  'Troca de turno solicitada e aprovada para consulta médica. Reposição das horas combinada.', false),
  (8,  'neutra',   37, 40, 30,  'Registro de dúvida sobre o procedimento de bloqueio e etiquetagem; orientação realizada.', false),
  (9,  'neutra',   47, 52, 48,  'Visita à filial Curitiba para alinhamento de processos de expedição.', false),
  (10, 'neutra',   54, NULL, 70,'Solicitou antecipação de férias; documentação encaminhada ao DP.', false),
  (11, 'negativa', 6,  28, 8,   'Atraso de 35 minutos sem aviso prévio ao líder, segundo atraso no mês.', false),
  (12, 'negativa', 18, 28, 15,  'Foi flagrado(a) sem protetor auricular na área de usinagem após orientação anterior.', true),
  (13, 'negativa', 26, 28, 24,  'Uso indevido de celular durante a operação do equipamento; foi orientado(a) e registrada a ocorrência.', false),
  (14, 'negativa', 33, 40, 35,  'Intervenção em painel sem bloqueio e etiquetagem (LOTO), mesmo após treinamento.', true),
  (15, 'negativa', 50, 52, 45,  'Faltou ao trabalho sem justificativa por dois dias consecutivos.', true),
  (16, 'negativa', 12, 28, 58,  'Discussão em tom elevado com colega durante o turno. As partes foram ouvidas e orientadas.', false),
  (17, 'negativa', 29, NULL, 77,'Descumprimento reiterado da regra de uso de uniforme completo no refeitório e na produção.', true),
  (18, 'negativa', 43, 52, 95,  'Manobra de empilhadeira acima da velocidade permitida no pátio, sem acidente.', true),
  (19, 'neutra',   55, NULL, 3, 'Reunião de acompanhamento sobre metas de qualidade do trimestre.', false),
  (20, 'positiva', 40, NULL, 2, 'Liderou a resposta ao quase-acidente na prensa, com investigação e plano de ação no mesmo dia.', false)
) AS v(n, tipo, adm, reg, dias, descricao, adv)
JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || v.adm)
LEFT JOIN public.admissoes r ON r.id = public.demo_id('admissao:' || v.reg)
CROSS JOIN (SELECT (SELECT x.id FROM auth.users x WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1) AS uid,
                   COALESCE((SELECT p.nome_completo FROM public.profiles p JOIN auth.users x ON x.id = p.user_id
                              WHERE lower(x.email) = 'leirinuernberg@gmail.com' LIMIT 1), 'Gestora de RH') AS nome) u
WHERE u.uid IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.ocorrencias o WHERE o.id = public.demo_id('oc:' || v.n));

-- Advertencias: links de ciencia e assinatura em todos os status
INSERT INTO public.advertencia_links (
  id, tenant_id, ocorrencia_id, token, destinatario_email, destinatario_nome, status, documento_url, documento_nome,
  enviado_em, formalizado_em, expira_em, created_at, updated_at
)
SELECT public.demo_id('adv:' || v.oc), o.tenant_id, o.id, md5('adv_token:' || v.oc), a.email, a.nome_completo, v.status::public.advertencia_status,
       CASE WHEN v.status = 'formalizada' THEN 'demo/advertencias/advertencia-' || v.oc || '.pdf' END,
       CASE WHEN v.status = 'formalizada' THEN 'Advertência assinada.pdf' END,
       CASE WHEN v.status <> 'pendente' THEN o.created_at + interval '1 day' END,
       CASE WHEN v.status = 'formalizada' THEN o.created_at + interval '2 days' END,
       o.created_at + interval '8 days', o.created_at, o.created_at + interval '2 days'
FROM (VALUES (12, 'formalizada'), (14, 'enviada'), (15, 'formalizada'), (17, 'pendente'), (18, 'arquivada')) AS v(oc, status)
JOIN public.ocorrencias o ON o.id = public.demo_id('oc:' || v.oc)
JOIN public.admissoes a ON a.id::text = o.colaborador_id
WHERE NOT EXISTS (SELECT 1 FROM public.advertencia_links l WHERE l.id = public.demo_id('adv:' || v.oc));

-- ---------------------------------------------------------------------------
-- Conferencia final
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.cultura_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS acoes_cultura,
  (SELECT count(DISTINCT status) FROM public.cultura_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS status_acoes,
  (SELECT count(*) FROM public.cultura_datas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS datas,
  (SELECT count(*) FROM public.cultura_rituais WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS rituais,
  (SELECT count(*) FROM public.cultura_marcos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS marcos,
  (SELECT count(*) FROM public.cultura_preferencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS preferencias,
  (SELECT count(*) FROM public.estrategia_cultura WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS cultura_estrategia,
  (SELECT count(*) FROM public.feedbacks WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS feedbacks,
  (SELECT count(*) FROM public.ocorrencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ocorrencias,
  (SELECT count(*) FROM public.advertencia_links WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS advertencias,
  CASE WHEN (SELECT count(*) FROM public.cultura_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 30
        AND (SELECT count(*) FROM public.feedbacks WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 24
        AND (SELECT count(*) FROM public.ocorrencias WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 20
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
