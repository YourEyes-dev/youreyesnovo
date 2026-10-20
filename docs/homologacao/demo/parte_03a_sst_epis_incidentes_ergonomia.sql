-- ============================================================================
-- HOMOLOGACAO — DEMONSTRACAO, PARTE 03a: EPIs, Incidentes e Acidentes, Ergonomia
--
-- PARA QUE SERVE
-- Preenche, para a "Metalurgica Exemplo Ltda" (100% ficticia, parte 00), as telas
--   /epis                  catalogo com CA, lotes, estoque por local e tamanho,
--                          entregas (ativas, devolvidas, extraviadas, vencidas em
--                          uso, aguardando assinatura), movimentacoes, alertas e
--                          matriz de protecao por cargo;
--   /incidentes-acidentes  quase-acidentes e acidentes (com e sem afastamento,
--                          CAT, causas, acoes vinculadas) para a lista, a analise,
--                          os indicadores, o preditivo, a cultura, o FAP e a piramide;
--   /ergonomia             itens da NR-17, inventario de riscos (GRO), analises por
--                          posto de trabalho, riscos, acoes e mapa de risco.
-- Tambem cria as acoes do plano de acao (origens sst, epi e ergonomia) que essas
-- telas e o painel PDCA de /documentos leem.
--
-- ONDE COLAR
-- SQL Editor do projeto de HOMOLOGACAO, DEPOIS da parte 00. O arquivo se RECUSA a
-- rodar fora da homologacao/teste (confere app_config.supabase_url). Nunca na producao.
--
-- GARANTIAS
--   - Nenhum dado real: nomes inventados, CPFs 900.000.0XX (via demo_cpf), marcas e
--     numeros de CA ficticios, diagnosticos (CID) genericos.
--   - So toca o tenant demo (d3e00000-...-0001). Nao altera nem apaga linha alguma
--     de outro tenant. Nenhum UPDATE/DELETE fora das linhas criadas aqui.
--   - Idempotente: ids fixos (demo_id) + "so insere se nao existe". Rodar de novo nao
--     duplica nada e nao recalcula o estoque de novo.
--   - Nao cria tabela. Roda numa transacao so; cada bloco tem rede de seguranca
--     (EXCEPTION WHEN OTHERS THEN RAISE NOTICE) para nao derrubar os demais.
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (0) Trava de ambiente (so homologacao/teste) + conferencia da base (parte 00)
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
    RAISE EXCEPTION 'RECUSADO: o tenant demo nao existe. Rode primeiro a parte 00 (parte_00_base_empresa_demo.sql).';
  END IF;
END $trava$;

-- ---------------------------------------------------------------------------
-- (1) EPIs — locais, categorias, catalogo (tipos), tamanhos, lotes e estoque por local
-- ---------------------------------------------------------------------------
DO $epi1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_tipos jsonb;
  v_lotes jsonb;
BEGIN
  -- Catalogo: k = chave, vm = vida util (meses), pt = troca (dias), ca = numero ficticio,
  -- cad = dias ate o vencimento do CA (negativo = ja vencido), tam = grade de tamanhos
  v_tipos := '[
   {"k":"cap","nome":"Capacete de Segurança Classe B","cat":"Proteção da Cabeça","vm":60,"pt":730,"dur":"duravel","un":"unidade","tam":null,"ca":"90101","cad":412,"marca":"Protecta","fab":"Protecta Indústria Ltda","emin":10,"custo":42.90},
   {"k":"oc","nome":"Óculos de Proteção Incolor Antirrisco","cat":"Proteção Visual","vm":24,"pt":365,"dur":"duravel","un":"unidade","tam":null,"ca":"90102","cad":300,"marca":"VisãoSeg","fab":"VisãoSeg Equipamentos","emin":20,"custo":9.50},
   {"k":"pl","nome":"Protetor Auricular Plug de Silicone","cat":"Proteção Auditiva","vm":12,"pt":180,"dur":"duravel","un":"par","tam":null,"ca":"90103","cad":48,"marca":"SomZero","fab":"SomZero Acústica","emin":60,"custo":2.80},
   {"k":"ab","nome":"Abafador de Ruído Tipo Concha","cat":"Proteção Auditiva","vm":24,"pt":730,"dur":"duravel","un":"unidade","tam":null,"ca":"90104","cad":21,"marca":"SomZero","fab":"SomZero Acústica","emin":8,"custo":38.00},
   {"k":"lr","nome":"Luva de Raspa de Couro Cano Curto","cat":"Proteção das Mãos","vm":6,"pt":90,"dur":"duravel","un":"par","tam":null,"ca":"90105","cad":520,"marca":"ForteGrip","fab":"ForteGrip Luvas","emin":40,"custo":14.90},
   {"k":"ln","nome":"Luva Nitrílica Anticorte Antiderrapante","cat":"Proteção das Mãos","vm":3,"pt":60,"dur":"descartavel","un":"par","tam":["P","M","G","GG"],"ca":"90106","cad":240,"marca":"ForteGrip","fab":"ForteGrip Luvas","emin":40,"custo":11.40},
   {"k":"bt","nome":"Botina de Segurança com Biqueira de Aço","cat":"Proteção dos Pés","vm":12,"pt":365,"dur":"duravel","un":"par","tam":["38","39","40","41","42","43","44"],"ca":"90107","cad":610,"marca":"PasseiSeg","fab":"PasseiSeg Calçados","emin":6,"custo":89.90},
   {"k":"pf","nome":"Respirador Descartável PFF2","cat":"Proteção Respiratória","vm":3,"pt":30,"dur":"descartavel","un":"unidade","tam":null,"ca":"90108","cad":-12,"marca":"AirPro","fab":"AirPro Respiratórios","emin":50,"custo":3.70},
   {"k":"rs","nome":"Respirador Semifacial com Filtro P2","cat":"Proteção Respiratória","vm":12,"pt":365,"dur":"duravel","un":"unidade","tam":["M","G"],"ca":"90109","cad":160,"marca":"AirPro","fab":"AirPro Respiratórios","emin":6,"custo":96.00},
   {"k":"ms","nome":"Máscara de Solda com Escurecimento Automático","cat":"Proteção Facial","vm":36,"pt":1095,"dur":"duravel","un":"unidade","tam":null,"ca":"90110","cad":690,"marca":"Arco Vivo","fab":"Arco Vivo Soldagem","emin":4,"custo":289.00},
   {"k":"av","nome":"Avental de Raspa para Soldador","cat":"Proteção do Tronco","vm":12,"pt":365,"dur":"duravel","un":"unidade","tam":null,"ca":"90111","cad":82,"marca":"ForteGrip","fab":"ForteGrip Luvas","emin":6,"custo":58.00},
   {"k":"pfa","nome":"Protetor Facial Incolor com Carneira","cat":"Proteção Facial","vm":24,"pt":730,"dur":"duravel","un":"unidade","tam":null,"ca":"90112","cad":365,"marca":"VisãoSeg","fab":"VisãoSeg Equipamentos","emin":8,"custo":27.50},
   {"k":"li","nome":"Luva Isolante de Borracha Classe 2 (NR-10)","cat":"Proteção contra Riscos Elétricos","vm":6,"pt":180,"dur":"duravel","un":"par","tam":["9","10","11"],"ca":"90113","cad":300,"marca":"VoltSeg","fab":"VoltSeg Isolantes","emin":4,"custo":210.00},
   {"k":"cp","nome":"Cinturão Paraquedista com Talabarte Duplo","cat":"Proteção contra Quedas","vm":24,"pt":730,"dur":"duravel","un":"unidade","tam":["M","G"],"ca":"90114","cad":430,"marca":"AltoSeguro","fab":"AltoSeguro Quedas","emin":3,"custo":240.00},
   {"k":"cr","nome":"Colete Refletivo de Sinalização","cat":"Sinalização e Visibilidade","vm":24,"pt":365,"dur":"duravel","un":"unidade","tam":["M","G","GG"],"ca":null,"cad":null,"marca":"Protecta","fab":"Protecta Indústria Ltda","emin":10,"custo":18.90}
  ]'::jsonb;

  -- Lotes: t = tipo, lval = dias ate o vencimento do lote (negativo = vencido),
  -- qpt = quantidade por tamanho (ou total, se nao ha grade), emin = minimo do lote
  v_lotes := '[
   {"k":"cap","t":"cap","lval":900,"qpt":14,"emin":10,"fab":200,"loc":"Prateleira A1"},
   {"k":"oc","t":"oc","lval":70,"qpt":40,"emin":20,"fab":150,"loc":"Prateleira A2"},
   {"k":"pl","t":"pl","lval":300,"qpt":150,"emin":60,"fab":90,"loc":"Gaveteiro B1"},
   {"k":"pl0","t":"pl","lval":-8,"qpt":12,"emin":5,"fab":420,"loc":"Quarentena (vencido)"},
   {"k":"ab","t":"ab","lval":900,"qpt":6,"emin":8,"fab":300,"loc":"Prateleira A3"},
   {"k":"lr","t":"lr","lval":600,"qpt":70,"emin":40,"fab":110,"loc":"Prateleira B2"},
   {"k":"ln","t":"ln","lval":24,"qpt":12,"emin":40,"fab":330,"loc":"Prateleira B3"},
   {"k":"bt","t":"bt","lval":800,"qpt":5,"emin":6,"fab":180,"loc":"Estante C1"},
   {"k":"pf","t":"pf","lval":200,"qpt":120,"emin":50,"fab":60,"loc":"Caixas D1"},
   {"k":"pf0","t":"pf","lval":-25,"qpt":18,"emin":5,"fab":480,"loc":"Quarentena (vencido)"},
   {"k":"rs","t":"rs","lval":500,"qpt":4,"emin":6,"fab":140,"loc":"Prateleira A4"},
   {"k":"ms","t":"ms","lval":1000,"qpt":4,"emin":4,"fab":260,"loc":"Prateleira A5"},
   {"k":"av","t":"av","lval":700,"qpt":7,"emin":6,"fab":120,"loc":"Prateleira B4"},
   {"k":"pfa","t":"pfa","lval":700,"qpt":9,"emin":8,"fab":100,"loc":"Prateleira A6"},
   {"k":"li","t":"li","lval":150,"qpt":1,"emin":4,"fab":130,"loc":"Armário elétrico (NR-10)"},
   {"k":"cp","t":"cp","lval":500,"qpt":0,"emin":3,"fab":300,"loc":"Armário de altura"},
   {"k":"cr","t":"cr","lval":900,"qpt":8,"emin":10,"fab":80,"loc":"Prateleira B5"}
  ]'::jsonb;

  -- Locais de estoque
  INSERT INTO public.epi_locais_estoque (id, tenant_id, nome, tipo, filial_id, responsavel_nome, observacoes, ativo)
  SELECT public.demo_id('epi_local:' || l.k), v_t, l.nome, l.tipo, l.filial, l.resp, l.obs, true
  FROM (VALUES
    ('central',  'Almoxarifado Central — Matriz', 'almoxarifado_central', NULL::uuid, 'Rafael Campos Lacerda', 'Recebimento de NF e distribuição para os setores.'),
    ('setorial', 'Almoxarifado Setorial — Produção', 'almoxarifado_setorial', NULL::uuid, 'Larissa Uchôa Ferraz', 'Estoque de giro rápido da usinagem e da solda.'),
    ('curitiba', 'Almoxarifado Filial Curitiba', 'almoxarifado_central', public.demo_id('filial:1'), 'Wagner Nogueira Paes', 'Atende a equipe de manutenção da filial.'),
    ('itajai',   'Estoque CD Itajaí', 'almoxarifado_setorial', public.demo_id('filial:2'), 'Márcio Leal Fontes', 'Centro de distribuição: colete, botina e luva.'),
    ('manut',    'Em Manutenção', 'almoxarifado_setorial', NULL::uuid, NULL, 'Itens enviados para higienização, ensaio dielétrico ou conserto.')
  ) AS l(k, nome, tipo, filial, resp, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_locais_estoque x WHERE x.id = public.demo_id('epi_local:' || l.k));

  INSERT INTO public.epi_config (tenant_id, usar_controle_estoque)
  SELECT v_t, true
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_config c WHERE c.tenant_id = v_t);

  -- Categorias (exigencia de CA) — so as que a empresa realmente usa
  INSERT INTO public.epi_categorias (id, tenant_id, nome, exige_ca)
  SELECT public.demo_id('epi_cat:' || c.nome), v_t, c.nome, c.exige
  FROM (VALUES
    ('Proteção da Cabeça', true), ('Proteção Visual', true), ('Proteção Auditiva', true),
    ('Proteção das Mãos', true), ('Proteção dos Pés', true), ('Proteção Respiratória', true),
    ('Proteção Facial', true), ('Proteção do Tronco', true), ('Proteção contra Quedas', true),
    ('Proteção contra Riscos Elétricos', true), ('Sinalização e Visibilidade', false)
  ) AS c(nome, exige)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_categorias x WHERE x.tenant_id = v_t AND x.nome = c.nome);

  -- Catalogo (tipos)
  INSERT INTO public.epi_tipos (
    id, tenant_id, nome, descricao, validade_meses, categoria, ca_numero, ca_validade, marca, fabricante,
    estoque_minimo, is_active, unidade_medida, tipo_durabilidade, controla_tamanho, periodicidade_troca_dias
  )
  SELECT public.demo_id('epi_tipo:' || s.k), v_t, s.nome,
         s.nome || ' — ' || s.marca, s.vm, s.cat, s.ca,
         CASE WHEN s.cad IS NULL THEN NULL ELSE CURRENT_DATE + s.cad END,
         s.marca, s.fab, s.emin, true, s.un, s.dur, COALESCE(jsonb_typeof(s.tam) = 'array', false), s.pt
  FROM jsonb_to_recordset(v_tipos) AS s(k text, nome text, cat text, vm int, pt int, dur text, un text, tam jsonb,
                                         ca text, cad int, marca text, fab text, emin int, custo numeric)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_tipos x WHERE x.id = public.demo_id('epi_tipo:' || s.k));

  -- Grade de tamanhos
  INSERT INTO public.epi_tamanhos (id, tenant_id, tipo_id, tamanho, ordem)
  SELECT public.demo_id('epi_tam:' || s.k || ':' || z.tam), v_t, public.demo_id('epi_tipo:' || s.k), z.tam, (z.ord - 1)::int
  FROM jsonb_to_recordset(v_tipos) AS s(k text, tam jsonb)
  CROSS JOIN LATERAL jsonb_array_elements_text(CASE WHEN jsonb_typeof(s.tam) = 'array' THEN s.tam ELSE '[]'::jsonb END) WITH ORDINALITY AS z(tam, ord)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_tamanhos x WHERE x.id = public.demo_id('epi_tam:' || s.k || ':' || z.tam));

  -- Lotes (tabela epis). O saldo definitivo e recalculado na secao 2, depois das entregas.
  INSERT INTO public.epis (
    id, tenant_id, empresa_id, tipo_id, codigo, ca, marca, modelo, data_fabricacao, data_validade,
    quantidade_estoque, quantidade_minima, custo_unitario, localizacao, status, local_estoque_id, observacoes
  )
  SELECT public.demo_id('epi:' || l.k), v_t, v_e, public.demo_id('epi_tipo:' || l.t),
         'EPI-' || upper(l.t) || '-' || CASE WHEN l.k = l.t THEN '001' ELSE '000' END,
         t.ca, t.marca, t.nome,
         CURRENT_DATE - l.fab, CURRENT_DATE + l.lval,
         l.qpt * COALESCE(CASE WHEN jsonb_typeof(t.tam) = 'array' THEN jsonb_array_length(t.tam) END, 1), l.emin, t.custo, l.loc,
         CASE WHEN l.lval < 0 THEN 'vencido' ELSE 'disponivel' END::public.epi_status,
         public.demo_id('epi_local:central'),
         CASE WHEN l.lval < 0 THEN 'Lote vencido segregado em quarentena, aguardando descarte.' ELSE NULL END
  FROM jsonb_to_recordset(v_lotes) AS l(k text, t text, lval int, qpt int, emin int, fab int, loc text)
  JOIN jsonb_to_recordset(v_tipos) AS t(k text, nome text, ca text, marca text, custo numeric, tam jsonb) ON t.k = l.t
  WHERE NOT EXISTS (SELECT 1 FROM public.epis x WHERE x.id = public.demo_id('epi:' || l.k));

  -- Estoque por local e tamanho (rateio: 50% central, 30% setorial, 10% Curitiba, 10% Itajai)
  INSERT INTO public.epi_estoque_local (id, tenant_id, epi_id, local_estoque_id, quantidade, quantidade_minima, tamanho)
  SELECT public.demo_id('epi_estoque:' || q.lk || ':' || q.loc || ':' || q.tam), v_t, public.demo_id('epi:' || q.lk),
         public.demo_id('epi_local:' || q.loc),
         CASE q.loc
           WHEN 'setorial' THEN (q.qt * 3) / 10
           WHEN 'curitiba' THEN q.qt / 10
           WHEN 'itajai'   THEN q.qt / 10
           ELSE q.qt - (q.qt * 3) / 10 - q.qt / 10 - q.qt / 10
         END,
         CASE q.loc WHEN 'central' THEN GREATEST(1, q.emin / GREATEST(q.ntam, 1)) ELSE 0 END,
         q.tam
  FROM (
    SELECT l.k AS lk, loc.loc, COALESCE(z.tam, '') AS tam, GREATEST(l.qpt + COALESCE((z.ord - 1)::int % 3, 1) - 1, 0) AS qt,
           l.emin, COALESCE(CASE WHEN jsonb_typeof(t.tam) = 'array' THEN jsonb_array_length(t.tam) END, 1) AS ntam
    FROM jsonb_to_recordset(v_lotes) AS l(k text, t text, qpt int, emin int)
    JOIN jsonb_to_recordset(v_tipos) AS t(k text, tam jsonb) ON t.k = l.t
    LEFT JOIN LATERAL jsonb_array_elements_text(CASE WHEN jsonb_typeof(t.tam) = 'array' THEN t.tam ELSE NULL END) WITH ORDINALITY AS z(tam, ord) ON true
    CROSS JOIN (VALUES ('central'), ('setorial'), ('curitiba'), ('itajai')) AS loc(loc)
    WHERE l.k NOT IN ('pl0', 'pf0') OR loc.loc = 'central'
  ) q
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_estoque_local x
                     WHERE x.id = public.demo_id('epi_estoque:' || q.lk || ':' || q.loc || ':' || q.tam));

  -- Itens que estao fora (ensaio dieletrico das luvas isoladoras)
  INSERT INTO public.epi_estoque_local (id, tenant_id, epi_id, local_estoque_id, quantidade, quantidade_minima, tamanho)
  SELECT public.demo_id('epi_estoque:li:manut:10'), v_t, public.demo_id('epi:li'), public.demo_id('epi_local:manut'), 1, 0, '10'
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_estoque_local x WHERE x.id = public.demo_id('epi_estoque:li:manut:10'));

  -- Ajuste fino: o estoque total do lote passa a ser a soma dos locais
  UPDATE public.epis e
     SET quantidade_estoque = COALESCE((SELECT sum(x.quantidade) FROM public.epi_estoque_local x WHERE x.epi_id = e.id), 0)
   WHERE e.tenant_id = v_t
     AND e.id IN (SELECT public.demo_id('epi:' || l.k) FROM jsonb_to_recordset(v_lotes) AS l(k text))
     AND NOT EXISTS (SELECT 1 FROM public.epi_entregas en WHERE en.epi_id = e.id);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EPI base (catalogo/estoque) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $epi1$;

-- ---------------------------------------------------------------------------
-- (2) EPIs — entregas (fichas), devolucoes, reservas e historico de movimentacoes
-- ---------------------------------------------------------------------------
DO $epi2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
  v_novas int := 0;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Folga temporaria de saldo nos lotes demo: os gatilhos de baixa/reserva rodam a cada
  -- entrega inserida; o saldo correto e refeito logo depois (so quando entram entregas novas).
  UPDATE public.epis SET quantidade_estoque = 99999
   WHERE tenant_id = v_t
     AND NOT EXISTS (SELECT 1 FROM public.epi_entregas en WHERE en.epi_id = epis.id)
     AND id IN (SELECT public.demo_id('epi:' || k) FROM unnest(ARRAY['cap','oc','pl','ab','lr','ln','bt','pf','rs','ms','av','pfa','li','cp','cr']) AS k);

  WITH grp AS (
    SELECT * FROM (VALUES
      (1, 12, ARRAY['cap','pl','ln','bt']),
      (13, 21, ARRAY['ms','av','lr','rs','bt','pf']),
      (22, 27, ARRAY['cap','oc','lr','bt','pfa']),
      (28, 29, ARRAY['cap','oc','pl','bt']),
      (30, 35, ARRAY['oc','ln','ab','bt']),
      (36, 39, ARRAY['cap','li','cp','bt']),
      (40, 40, ARRAY['cap','oc','bt']),
      (41, 45, ARRAY['cr','bt','pl']),
      (46, 51, ARRAY['lr','bt','cr']),
      (52, 52, ARRAY['cap','cr','bt']),
      (60, 61, ARRAY['cap','oc','pl'])
    ) AS g(lo, hi, kit)
  ),
  base AS (
    SELECT gs.n, k.epi, k.ord::int AS ord,
           a.id AS adm_id, a.nome_completo, a.cpf, a.cargo, a.departamento, a.data_admissao,
           (CURRENT_DATE - a.data_admissao) AS dias_casa
    FROM grp g
    CROSS JOIN LATERAL generate_series(g.lo, g.hi) AS gs(n)
    JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || gs.n) AND a.tenant_id = v_t
    CROSS JOIN LATERAL unnest(g.kit) WITH ORDINALITY AS k(epi, ord)
    WHERE a.status IN ('concluido', 'desligado')
  ),
  calc AS (
    SELECT b.*, t.validade_meses AS vm, t.nome AS epi_nome, t.controla_tamanho,
           CASE
             WHEN b.epi = 'pf' THEN 20 + ((b.n * 53 + b.ord * 29) % 40)
             WHEN (b.n + b.ord) % 6 = 0 AND t.validade_meses <= 12 THEN t.validade_meses * 30 + 8 + (b.n % 17)
             WHEN (b.n + b.ord) % 9 = 4 AND t.validade_meses <= 12 THEN t.validade_meses * 30 - (3 + (b.n % 10))
             ELSE 15 + ((b.n * 53 + b.ord * 29) % GREATEST(t.validade_meses * 30 - 20, 40))
           END AS dias_base
    FROM base b
    JOIN public.epi_tipos t ON t.id = public.demo_id('epi_tipo:' || b.epi)
  ),
  fim AS (
    SELECT c.*,
           (c.n + c.ord) % 7 = 3 AND c.dias_casa >= 150 AND NOT ((c.n * 7 + c.ord) % 41 = 0 AND c.epi <> 'pf') AS devolvido,
           (c.n, c.ord) IN ((17, 3), (44, 2)) AS extraviado,
           (c.n * 7 + c.ord) % 41 = 0 AND c.epi <> 'pf' AND NOT (c.n, c.ord) IN ((17, 3), (44, 2)) AS reserva
    FROM calc c
  ),
  fim2 AS (
    SELECT f.*,
           LEAST(
             CASE
               WHEN f.reserva THEN 1 + (f.n % 3)
               WHEN f.devolvido THEN 120 + ((f.n * 13 + f.ord * 7) % 150)
               ELSE LEAST(f.dias_base, 400)
             END,
             GREATEST(f.dias_casa, 1)) AS dias
    FROM fim f
  ),
  ent AS (
    SELECT f.*, (CURRENT_DATE - f.dias) AS dt
    FROM fim2 f
    WHERE f.dias >= CASE WHEN f.epi = 'pf' THEN 15 ELSE 0 END
  )
  INSERT INTO public.epi_entregas (
    id, tenant_id, empresa_id, epi_id, colaborador_nome, colaborador_cpf, colaborador_cargo, colaborador_departamento,
    quantidade, data_entrega, data_devolucao_prevista, data_devolucao_efetiva, motivo_entrega, entregue_por, entregue_por_nome,
    recebido_por_assinatura, observacoes, status, signed_at, ip_address, user_agent, liveness_detected,
    data_validade, employee_id, tamanho
  )
  SELECT public.demo_id('epi_entrega:' || e.n || ':' || e.ord), v_t, v_e, public.demo_id('epi:' || e.epi),
         e.nome_completo, e.cpf, e.cargo, e.departamento,
         1,
         (e.dt + TIME '07:30' + ((e.n % 9) * INTERVAL '35 minutes'))::timestamptz,
         (e.dt + (t.periodicidade_troca_dias)::int),
         CASE WHEN e.devolvido THEN (e.dt + (30 + (e.n % 40)) + TIME '16:10')::timestamptz END,
         CASE
           WHEN e.dias >= e.dias_casa - 5 THEN 'Admissão'
           WHEN e.dias > e.vm * 30 THEN 'Vencimento do EPI anterior'
           WHEN e.devolvido THEN 'Substituição por Desgaste'
           WHEN (e.n + e.ord) % 5 = 0 THEN 'Mudança de Função'
           WHEN (e.n + e.ord) % 11 = 0 THEN 'Substituição por Dano'
           ELSE 'Substituição por Desgaste'
         END,
         v_uid, v_nome,
         CASE WHEN e.reserva THEN NULL ELSE e.nome_completo END,
         CASE WHEN e.extraviado THEN 'Colaborador informou extravio no vestiário; reposição solicitada.'
              WHEN e.reserva THEN 'Reserva aguardando assinatura do colaborador (termo de recebimento).' END,
         CASE WHEN e.extraviado THEN 'extraviado' WHEN e.devolvido THEN 'devolvido' ELSE 'ativa' END::public.entrega_status,
         CASE WHEN e.reserva THEN NULL ELSE (e.dt + TIME '07:40' + ((e.n % 9) * INTERVAL '35 minutes'))::timestamptz END,
         CASE WHEN e.reserva THEN NULL ELSE '10.20.0.' || (10 + e.n)::text END,
         CASE WHEN e.reserva THEN NULL ELSE 'Tablet do almoxarifado (demonstração)' END,
         NOT e.reserva,
         (e.dt + (e.vm::text || ' months')::interval)::date,
         e.adm_id,
         CASE WHEN e.controla_tamanho THEN
           (SELECT z.tamanho FROM public.epi_tamanhos z WHERE z.tipo_id = t.id ORDER BY z.ordem
             OFFSET ((e.n + e.ord) % GREATEST((SELECT count(*) FROM public.epi_tamanhos z2 WHERE z2.tipo_id = t.id), 1)) LIMIT 1)
         END
  FROM ent e
  JOIN public.epi_tipos t ON t.id = public.demo_id('epi_tipo:' || e.epi)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_entregas x WHERE x.id = public.demo_id('epi_entrega:' || e.n || ':' || e.ord));
  GET DIAGNOSTICS v_novas = ROW_COUNT;

  IF v_novas > 0 THEN
    -- Historico de movimentacoes: entrada inicial + saidas (entregas) + devolucoes + eventos avulsos,
    -- com saldos anterior/atual consistentes. Saldo final = soma do estoque por local.
    INSERT INTO public.epi_movimentacoes (
      id, tenant_id, epi_id, tipo, quantidade, quantidade_anterior, quantidade_atual, motivo, documento_referencia,
      realizado_por, realizado_por_nome, created_at, local_estoque_id, subtipo, tamanho
    )
    WITH loc AS (
      SELECT * FROM (VALUES ('central'), ('setorial'), ('curitiba'), ('itajai')) AS x(k)
    ),
    extras AS (
      SELECT * FROM (VALUES
        ('oc',  'entrada', 'compra',        20, 75,  'Reposição de estoque (NF-e 004512)', 'central'),
        ('pl',  'entrada', 'compra',       100, 120, 'Reposição de estoque (NF-e 004390)', 'central'),
        ('ln',  'entrada', 'compra',        24, 55,  'Reposição de estoque (NF-e 004478)', 'central'),
        ('bt',  'entrada', 'doacao',         4, 90,  'Amostra doada pelo fornecedor para teste de conforto', 'central'),
        ('cap', 'ajuste',  'ajuste',         1, 40,  'Inventário rotativo: divergência de -1 unidade', 'central'),
        ('pf',  'descarte','dano',           6, 33,  'Caixa avariada no recebimento', 'central'),
        ('ab',  'saida',   'perda',          1, 60,  'Extravio durante manutenção do abafador', 'setorial'),
        ('cr',  'saida',   'transferencia',  6, 45,  'Transferência para o CD Itajaí', 'central'),
        ('cr',  'entrada', 'transferencia',  6, 45,  'Recebido da Matriz (transferência)', 'itajai'),
        ('bt',  'saida',   'transferencia',  5, 30,  'Transferência para a Filial Curitiba', 'central'),
        ('bt',  'entrada', 'transferencia',  5, 30,  'Recebido da Matriz (transferência)', 'curitiba')
      ) AS x(epi, tipo, subtipo, q, dias, motivo, loc)
    ),
    ev AS (
      SELECT en.epi_id, en.data_entrega AS ts, 'saida'::text AS tipo, en.quantidade AS q, (-en.quantidade) AS delta,
             'Entrega de EPI: ' || en.colaborador_nome AS motivo, 'ENT-' || substr(en.id::text, 1, 8) AS ref,
             CASE WHEN en.colaborador_departamento = 'Produção' THEN public.demo_id('epi_local:setorial') ELSE public.demo_id('epi_local:central') END AS local_id,
             'entrega'::text AS subtipo, en.tamanho, 1 AS ord
      FROM public.epi_entregas en
      WHERE en.tenant_id = v_t AND en.signed_at IS NOT NULL AND en.id IN (SELECT public.demo_id('epi_entrega:' || n || ':' || o) FROM generate_series(1, 64) n CROSS JOIN generate_series(1, 6) o)
      UNION ALL
      SELECT en.epi_id, en.data_devolucao_efetiva, 'entrada', en.quantidade, en.quantidade,
             'Devolução para estoque: ' || en.colaborador_nome, 'DEV-' || substr(en.id::text, 1, 8),
             public.demo_id('epi_local:central'), 'devolucao', en.tamanho, 2
      FROM public.epi_entregas en
      WHERE en.tenant_id = v_t AND en.status = 'devolvido' AND en.data_devolucao_efetiva IS NOT NULL
        AND en.id IN (SELECT public.demo_id('epi_entrega:' || n || ':' || o) FROM generate_series(1, 64) n CROSS JOIN generate_series(1, 6) o)
      UNION ALL
      SELECT public.demo_id('epi:' || x.epi), (CURRENT_DATE - x.dias) + TIME '10:15', x.tipo, x.q,
             CASE WHEN x.tipo = 'entrada' THEN x.q ELSE -x.q END,
             x.motivo, NULL, public.demo_id('epi_local:' || x.loc), x.subtipo, NULL, 3
      FROM extras x
    ),
    fin AS (
      SELECT e.id AS epi_id, COALESCE((SELECT sum(l.quantidade) FROM public.epi_estoque_local l WHERE l.epi_id = e.id), 0) AS final_qtd
      FROM public.epis e
      WHERE e.tenant_id = v_t AND e.id IN (SELECT public.demo_id('epi:' || k) FROM unnest(ARRAY['cap','oc','pl','pl0','ab','lr','ln','bt','pf','pf0','rs','ms','av','pfa','li','cp','cr']) AS k)
    ),
    ini AS (
      SELECT f.epi_id, f.final_qtd - COALESCE((SELECT sum(ev.delta) FROM ev WHERE ev.epi_id = f.epi_id), 0) AS qtd_inicial
      FROM fin f
    ),
    todos AS (
      SELECT i.epi_id, (CURRENT_DATE - 430) + TIME '09:00' AS ts, 'entrada'::text AS tipo, i.qtd_inicial AS q, i.qtd_inicial AS delta,
             'Estoque inicial (compra e inventário de implantação)' AS motivo, 'NF-e 003870'::text AS ref,
             public.demo_id('epi_local:central') AS local_id, 'inventario_inicial'::text AS subtipo, NULL::text AS tamanho, 0 AS ord
      FROM ini i WHERE i.qtd_inicial > 0
      UNION ALL
      SELECT ev.epi_id, ev.ts, ev.tipo, ev.q, ev.delta, ev.motivo, ev.ref, ev.local_id, ev.subtipo, ev.tamanho, ev.ord FROM ev
    ),
    seq AS (
      SELECT t.*,
             sum(t.delta) OVER (PARTITION BY t.epi_id ORDER BY t.ts, t.ord, t.motivo ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS saldo_apos,
             row_number() OVER (PARTITION BY t.epi_id ORDER BY t.ts, t.ord, t.motivo) AS rn
      FROM todos t
    )
    SELECT public.demo_id('epi_mov:' || s.epi_id::text || ':' || s.rn::text), v_t, s.epi_id, s.tipo, s.q,
           (s.saldo_apos - s.delta)::int, s.saldo_apos::int, s.motivo, s.ref, v_uid, v_nome, s.ts, s.local_id, s.subtipo, s.tamanho
    FROM seq s
    WHERE NOT EXISTS (SELECT 1 FROM public.epi_movimentacoes m WHERE m.id = public.demo_id('epi_mov:' || s.epi_id::text || ':' || s.rn::text));

  END IF;

  -- Saldo definitivo dos lotes: soma do estoque por local; reservas = entregas aguardando assinatura.
  -- Roda quando entraram entregas novas ou quando sobrou a folga temporaria (99999) de uma execucao interrompida.
  UPDATE public.epis e
     SET quantidade_estoque = COALESCE((SELECT sum(l.quantidade) FROM public.epi_estoque_local l WHERE l.epi_id = e.id), 0),
         quantidade_reservada = COALESCE((SELECT sum(en.quantidade) FROM public.epi_entregas en
                                           WHERE en.epi_id = e.id AND en.status = 'ativa' AND en.signed_at IS NULL), 0)
   WHERE e.tenant_id = v_t
     AND (v_novas > 0 OR e.quantidade_estoque = 99999)
     AND e.id IN (SELECT public.demo_id('epi:' || k) FROM unnest(ARRAY['cap','oc','pl','ab','lr','ln','bt','pf','rs','ms','av','pfa','li','cp','cr']) AS k);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EPI entregas/movimentacoes nao concluido: % (%)', SQLERRM, SQLSTATE;
END $epi2$;

-- ---------------------------------------------------------------------------
-- (3) EPIs — matriz de protecao (cargo x EPI) e condicoes especiais de trabalho (CET)
-- ---------------------------------------------------------------------------
DO $epi3$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
BEGIN
  INSERT INTO public.condicoes_especiais_trabalho (id, tenant_id, nome, descricao, norma_regulamentadora, icone, ativo)
  SELECT public.demo_id('cet:' || c.nome), v_t, c.nome, c.descricao, c.nr, c.icone, true
  FROM (VALUES
    ('Trabalho em Altura', 'Atividades acima de 2m do nível inferior', 'NR-35', 'mountain'),
    ('Espaço Confinado', 'Acesso a espaços com ventilação limitada', 'NR-33', 'box'),
    ('Eletricidade', 'Atividades em instalações elétricas e proximidades', 'NR-10', 'zap'),
    ('Agentes Químicos', 'Exposição a substâncias químicas nocivas', 'NR-15', 'flask-conical'),
    ('Ruído', 'Exposição a níveis elevados de ruído', 'NR-15', 'volume-2'),
    ('Trabalho Noturno', 'Jornada de trabalho no período noturno', 'NR-17', 'moon'),
    ('Calor', 'Exposição a fontes de calor intenso', 'NR-15', 'thermometer'),
    ('Radiação', 'Exposição a radiações ionizantes ou não-ionizantes', 'NR-15', 'radio'),
    ('Máquinas e Equipamentos', 'Operação de máquinas e equipamentos', 'NR-12', 'cog'),
    ('Trabalho com Inflamáveis', 'Manuseio de líquidos e combustíveis inflamáveis', 'NR-20', 'flame')
  ) AS c(nome, descricao, nr, icone)
  WHERE NOT EXISTS (SELECT 1 FROM public.condicoes_especiais_trabalho x WHERE x.tenant_id = v_t AND x.nome = c.nome);

  -- Cargo x EPI (obrigatorio / recomendado)
  INSERT INTO public.funcao_epis (id, tenant_id, cargo_id, epi_tipo_id, obrigatorio, justificativa)
  SELECT public.demo_id('funcao_epi:' || m.cargo || ':' || m.epi), v_t, public.demo_id('cargo:' || m.cargo),
         public.demo_id('epi_tipo:' || m.epi), m.obrig, m.just
  FROM (VALUES
    ('Operador de Usinagem CNC', 'cap', true, 'Risco de impacto e projeção (NR-6)'),
    ('Operador de Usinagem CNC', 'oc', true, 'Projeção de cavacos e fluido de corte'),
    ('Operador de Usinagem CNC', 'pl', true, 'Ruído contínuo acima de 85 dB(A)'),
    ('Operador de Usinagem CNC', 'ln', true, 'Manuseio de peças com rebarba'),
    ('Operador de Usinagem CNC', 'bt', true, 'Queda de peças e piso com cavaco'),
    ('Soldador', 'cap', true, 'Risco de impacto'),
    ('Soldador', 'ms', true, 'Radiação não ionizante e respingos'),
    ('Soldador', 'av', true, 'Respingos e escória'),
    ('Soldador', 'lr', true, 'Calor e respingos'),
    ('Soldador', 'rs', true, 'Fumos metálicos (LTCAT)'),
    ('Soldador', 'bt', true, 'Queda de peças e respingos'),
    ('Soldador', 'pl', true, 'Ruído do esmerilhamento'),
    ('Soldador', 'pf', false, 'Apoio em tarefas de curta duração'),
    ('Montador de Estruturas Metálicas', 'cap', true, 'Risco de impacto'),
    ('Montador de Estruturas Metálicas', 'oc', true, 'Projeção de partículas'),
    ('Montador de Estruturas Metálicas', 'lr', true, 'Manuseio de chapas e perfis'),
    ('Montador de Estruturas Metálicas', 'bt', true, 'Queda de peças'),
    ('Montador de Estruturas Metálicas', 'pfa', false, 'Esmerilhamento ocasional'),
    ('Líder de Produção', 'cap', true, 'Circulação em área fabril'),
    ('Líder de Produção', 'oc', true, 'Circulação em área fabril'),
    ('Líder de Produção', 'pl', true, 'Ruído da área fabril'),
    ('Líder de Produção', 'bt', true, 'Circulação em área fabril'),
    ('Mecânico de Manutenção', 'oc', true, 'Projeção de partículas e fluidos'),
    ('Mecânico de Manutenção', 'ln', true, 'Manuseio de peças e óleos'),
    ('Mecânico de Manutenção', 'bt', true, 'Queda de peças'),
    ('Mecânico de Manutenção', 'ab', true, 'Ruído de máquinas em manutenção'),
    ('Mecânico de Manutenção', 'cap', false, 'Trabalho sob equipamentos'),
    ('Eletricista de Manutenção', 'cap', true, 'Capacete classe B isolante (NR-10)'),
    ('Eletricista de Manutenção', 'li', true, 'Trabalho em instalações energizadas (NR-10)'),
    ('Eletricista de Manutenção', 'bt', true, 'Calçado sem partes metálicas expostas'),
    ('Eletricista de Manutenção', 'oc', true, 'Arco elétrico e projeção'),
    ('Eletricista de Manutenção', 'cp', true, 'Trabalho em altura em painéis e eletrocalhas (NR-35)'),
    ('Supervisor de Manutenção', 'cap', true, 'Circulação em área fabril'),
    ('Supervisor de Manutenção', 'oc', true, 'Circulação em área fabril'),
    ('Supervisor de Manutenção', 'bt', true, 'Circulação em área fabril'),
    ('Operador de Empilhadeira', 'cr', true, 'Sinalização de pessoas em área de tráfego'),
    ('Operador de Empilhadeira', 'bt', true, 'Queda de cargas'),
    ('Operador de Empilhadeira', 'pl', true, 'Ruído da operação'),
    ('Operador de Empilhadeira', 'cap', false, 'Doca de carregamento'),
    ('Auxiliar de Logística', 'lr', true, 'Movimentação manual de cargas'),
    ('Auxiliar de Logística', 'bt', true, 'Queda de cargas'),
    ('Auxiliar de Logística', 'cr', true, 'Área de tráfego de empilhadeiras'),
    ('Coordenador de Logística', 'cr', true, 'Área de tráfego de empilhadeiras'),
    ('Coordenador de Logística', 'bt', true, 'Área de expedição'),
    ('Técnico de Segurança do Trabalho', 'cap', true, 'Inspeções em campo'),
    ('Técnico de Segurança do Trabalho', 'oc', true, 'Inspeções em campo'),
    ('Técnico de Segurança do Trabalho', 'pl', true, 'Inspeções em campo'),
    ('Técnico de Segurança do Trabalho', 'bt', true, 'Inspeções em campo')
  ) AS m(cargo, epi, obrig, just)
  WHERE NOT EXISTS (SELECT 1 FROM public.funcao_epis x WHERE x.tenant_id = v_t
                     AND x.cargo_id = public.demo_id('cargo:' || m.cargo) AND x.epi_tipo_id = public.demo_id('epi_tipo:' || m.epi));

  -- Cargo x condicao especial
  INSERT INTO public.funcao_cets (id, tenant_id, cargo_id, cet_id, observacao)
  SELECT public.demo_id('funcao_cet:' || m.cargo || ':' || m.cet), v_t, public.demo_id('cargo:' || m.cargo),
         public.demo_id('cet:' || m.cet), m.obs
  FROM (VALUES
    ('Operador de Usinagem CNC', 'Ruído', 'Medição de ruído em dosimetria (LTCAT)'),
    ('Operador de Usinagem CNC', 'Máquinas e Equipamentos', 'NR-12: proteções fixas e intertravamentos'),
    ('Soldador', 'Radiação', 'Radiação não ionizante do arco elétrico'),
    ('Soldador', 'Agentes Químicos', 'Fumos metálicos'),
    ('Soldador', 'Ruído', 'Esmerilhamento e martelamento'),
    ('Soldador', 'Calor', 'Soldagem em estrutura'),
    ('Montador de Estruturas Metálicas', 'Trabalho em Altura', 'Montagem em plataformas acima de 2 m'),
    ('Montador de Estruturas Metálicas', 'Máquinas e Equipamentos', NULL),
    ('Mecânico de Manutenção', 'Máquinas e Equipamentos', 'Bloqueio e etiquetagem (LOTO)'),
    ('Mecânico de Manutenção', 'Trabalho com Inflamáveis', 'Óleos e solventes na oficina'),
    ('Eletricista de Manutenção', 'Eletricidade', 'Curso NR-10 e SEP em dia'),
    ('Eletricista de Manutenção', 'Trabalho em Altura', 'Eletrocalhas e painéis elevados'),
    ('Operador de Empilhadeira', 'Máquinas e Equipamentos', 'NR-11: habilitação e checklist diário')
  ) AS m(cargo, cet, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.funcao_cets x WHERE x.tenant_id = v_t
                     AND x.cargo_id = public.demo_id('cargo:' || m.cargo) AND x.cet_id = public.demo_id('cet:' || m.cet));

  -- EPI x condicao especial
  INSERT INTO public.epi_cets (id, tenant_id, epi_tipo_id, cet_id)
  SELECT public.demo_id('epi_cet:' || m.epi || ':' || m.cet), v_t, public.demo_id('epi_tipo:' || m.epi), public.demo_id('cet:' || m.cet)
  FROM (VALUES ('pl','Ruído'), ('ab','Ruído'), ('li','Eletricidade'), ('ms','Radiação'), ('rs','Agentes Químicos'),
               ('pf','Agentes Químicos'), ('cp','Trabalho em Altura'), ('lr','Calor'), ('av','Calor')) AS m(epi, cet)
  WHERE NOT EXISTS (SELECT 1 FROM public.epi_cets x WHERE x.tenant_id = v_t
                     AND x.epi_tipo_id = public.demo_id('epi_tipo:' || m.epi) AND x.cet_id = public.demo_id('cet:' || m.cet));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EPI matriz de protecao nao concluida: % (%)', SQLERRM, SQLSTATE;
END $epi3$;

-- ---------------------------------------------------------------------------
-- (4) Incidentes e acidentes — ocorrencias, desvios de seguranca, acoes do plano de acao
-- ---------------------------------------------------------------------------
DO $inc1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
  v_ev jsonb;
  v_ac jsonb;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Ocorrencias. d = dias atras; n = numero do colaborador (parte 00), null quando e uma condicao encontrada em inspecao.
  -- gp = potencial; gl = lesao; af = afastamento; at = atendimento; cn = numero da CAT; s = status; tl = tipo legal.
  v_ev := '[
   {"k":"a01","tipo":"acidente","d":12,"h":"14:20","un":"Metalúrgica Exemplo","st":"Produção","loc":"Usinagem CNC, torno 04","tu":"2º Turno","n":3,"cat":"Corte / laceração","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Operador sofreu corte no dedo indicador esquerdo ao retirar peça com rebarba da placa do torno sem luva anticorte. A limpeza do cavaco era feita com a mão.","ca":"Luva anticorte disponível mas não usada; ausência de gancho para retirada de cavaco; pressa para cumprir a meta da célula no fim do turno.","gp":"alta","gl":"leve","af":"sem_afastamento","at":"ambulatorial","cn":"2026.017.0001-3/01","ct":"inicial","s":"acoes_andamento","tl":"tipico","cid":"S61.0","nx":"confirmado","ag":"07.04 — Corte por objeto","da":0,"hp":3.5,"fe":["Ritmo de trabalho acelerado / pressa","Pressão excessiva por meta / produção"]},
   {"k":"a02","tipo":"acidente","d":45,"h":"09:50","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda, cabine 02","tu":"1º Turno","n":15,"cat":"Exposição a calor","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Queimadura de segundo grau no antebraço direito por respingo de solda durante soldagem de estrutura. O colaborador usava manga curta sob o avental.","ca":"Conjunto de proteção incompleto (sem manguito de raspa); avental curto para a atividade de soldagem fora de posição.","gp":"alta","gl":"moderada","af":"ate_15_dias","at":"ambulatorial","cn":"2026.017.0002-1/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"T22.2","nx":"confirmado","ag":"04.05 — Temperatura extrema","da":5,"hp":40,"fe":["Falha ou ausência de procedimento (POP, instruções)"]},
   {"k":"a03","tipo":"acidente","d":98,"h":"16:05","un":"Metalúrgica Exemplo","st":"Produção","loc":"Montagem, prensa hidráulica 02","tu":"2º Turno","n":24,"cat":"Esmagamento","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Esmagamento parcial da mão esquerda durante o posicionamento de peça na prensa hidráulica. O comando bimanual estava com uma das botoeiras travada por fita.","ca":"Dispositivo de segurança burlado para ganhar tempo; ausência de cortina de luz; manutenção do comando bimanual atrasada.","gp":"critica","gl":"grave","af":"mais_15_dias","at":"hospitalar","cn":"2026.017.0003-0/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"S67.8","nx":"confirmado","ag":"07.05 — Esmagamento / aprisionamento","da":32,"hp":256,"fe":["Pressão excessiva por meta / produção","Falha ou ausência de procedimento (POP, instruções)","Layout inadequado do posto"]},
   {"k":"a04","tipo":"acidente","d":150,"h":"07:40","un":"Metalúrgica Exemplo","st":"Logística","loc":"Expedição, doca 1","tu":"1º Turno","n":47,"cat":"Queda em mesmo nível","ori":"Ambiental (iluminação, temperatura, ruído, piso)","de":"Torção de tornozelo ao escorregar em piso com óleo hidráulico vazado de empilhadeira próxima à doca.","ca":"Vazamento sem sinalização e sem kit de absorção disponível; limpeza do piso fora da rotina.","gp":"media","gl":"moderada","af":"ate_15_dias","at":"ambulatorial","cn":"2026.017.0004-8/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"S93.4","nx":"confirmado","ag":"07.02 — Queda em mesmo nível","da":9,"hp":72,"fe":["Falha ou ausência de procedimento (POP, instruções)"]},
   {"k":"a05","tipo":"acidente","d":200,"h":"11:30","un":"Metalúrgica Exemplo","st":"Logística","loc":"Armazenagem, corredor B","tu":"1º Turno","n":48,"cat":"Condição insegura","ori":"Organizacional (pressão, falta de recurso, falta de pessoal)","de":"Colaborador relatou lombalgia aguda após movimentação manual repetida de caixas de 25 kg sem auxílio mecânico. Atendimento ambulatorial e afastamento por 21 dias.","ca":"Ausência de carrinho de apoio e de rodízio de tarefas; movimentação manual de cargas acima do recomendado.","gp":"media","gl":"moderada","af":"mais_15_dias","at":"ambulatorial","cn":"2026.017.0005-6/01","ct":"inicial","s":"concluido","tl":"doenca_ocupacional","cid":"M54.5","nx":"suspeito","ag":"06.02 — Levantamento e transporte manual","da":21,"hp":168,"fe":["Ritmo de trabalho acelerado / pressa","Layout inadequado do posto"]},
   {"k":"a06","tipo":"acidente","d":30,"h":"10:15","un":"Metalúrgica Exemplo","st":"Produção","loc":"Usinagem CNC, centro de usinagem 07","tu":"1º Turno","n":7,"cat":"Falha de EPI","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Projeção de cavaco no olho esquerdo durante troca de ferramenta. O óculos estava riscado e sem vedação lateral. Retirada do corpo estranho em atendimento ambulatorial.","ca":"Óculos fora de condição de uso; ausência de inspeção periódica dos EPIs na célula.","gp":"alta","gl":"leve","af":"sem_afastamento","at":"ambulatorial","cn":null,"ct":null,"s":"em_analise","tl":"tipico","cid":"S05.1","nx":"confirmado","ag":"07.03 — Choque contra objeto","da":0,"hp":2,"fe":[]},
   {"k":"a07","tipo":"acidente","d":70,"h":"15:25","un":"Filial Curitiba","st":"Manutenção","loc":"Sala elétrica, painel de comando","tu":"2º Turno","n":36,"cat":"Condição insegura","ori":"Comportamental","de":"Choque elétrico de baixa intensidade ao abrir painel de comando com circuito energizado durante diagnóstico de falha. Sem sequelas, avaliação ambulatorial.","ca":"Bloqueio e etiquetagem (LOTO) não aplicado integralmente; pressa na restauração da máquina parada.","gp":"critica","gl":"leve","af":"sem_afastamento","at":"ambulatorial","cn":"2026.041.0001-7/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"T75.4","nx":"confirmado","ag":"07.06 — Eletricidade","da":0,"hp":4,"fe":["Pressão excessiva por meta / produção"]},
   {"k":"a08","tipo":"acidente","d":120,"h":"13:10","un":"Centro de Distribuição Itajaí","st":"Logística","loc":"Corredor de estocagem 3","tu":"2º Turno","n":44,"cat":"Choque contra objeto","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Operador de empilhadeira sofreu entorse no punho ao ser atingido pelo volante em colisão leve com a estrutura de uma prateleira.","ca":"Corredor estreito para manobra; ausência de espelho convexo e de sinal sonoro de ré funcionando.","gp":"media","gl":"leve","af":"ate_15_dias","at":"ambulatorial","cn":"2026.083.0001-2/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"S63.5","nx":"confirmado","ag":"07.03 — Choque contra objeto","da":6,"hp":48,"fe":["Layout inadequado do posto"]},
   {"k":"a09","tipo":"acidente","d":5,"h":"06:35","un":"Metalúrgica Exemplo","st":"Produção","loc":"Via pública, acesso ao portão 1","tu":"1º Turno","n":23,"cat":"Condição insegura","ori":"Ambiental (iluminação, temperatura, ruído, piso)","de":"Acidente de trajeto: colaborador de motocicleta foi atingido por outro veículo no cruzamento próximo ao portão 1, a caminho do trabalho. Fratura do tornozelo, internação para cirurgia.","ca":"Cruzamento sem semáforo e com pouca iluminação no início do turno.","gp":"alta","gl":"grave","af":"mais_15_dias","at":"hospitalar","cn":"2026.017.0006-4/01","ct":"inicial","s":"em_aberto","tl":"trajeto","cid":"S82.6","nx":"confirmado","ag":"09.01 — Outros","da":18,"hp":144,"fe":[]},
   {"k":"a10","tipo":"acidente","d":260,"h":"08:55","un":"Metalúrgica Exemplo","st":"Produção","loc":"Montagem, bancada 5","tu":"1º Turno","n":25,"cat":"Corte / laceração","ori":"Comportamental","de":"Corte profundo no antebraço ao manusear chapa recém-cortada sem luva de raspa e sem manga de proteção. Sutura e afastamento de 11 dias.","ca":"Bordas vivas na chapa sem rebarbação prévia; luvas fora da bancada; pressa na montagem.","gp":"media","gl":"moderada","af":"ate_15_dias","at":"ambulatorial","cn":"2026.017.0007-2/01","ct":"inicial","s":"concluido","tl":"tipico","cid":"S51.8","nx":"confirmado","ag":"07.04 — Corte por objeto","da":11,"hp":88,"fe":["Ritmo de trabalho acelerado / pressa"]},
   {"k":"a11","tipo":"acidente","d":320,"h":"16:40","un":"Metalúrgica Exemplo","st":"Produção","loc":"Usinagem CNC, tornos","tu":"2º Turno","n":10,"cat":"Exposição a agente químico","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Dermatite de contato nas mãos associada ao fluido de corte, com troca do fluido e orientação sobre uso de luva nitrílica. Sem afastamento.","ca":"Fluido concentrado sem diluição padronizada; luva nitrílica não fornecida na célula na época.","gp":"baixa","gl":"leve","af":"sem_afastamento","at":"ambulatorial","cn":null,"ct":null,"s":"concluido","tl":"doenca_ocupacional","cid":"L24.9","nx":"confirmado","ag":"02.01 — Substâncias químicas","da":0,"hp":1,"fe":[]},
   {"k":"a12","tipo":"acidente","d":20,"h":"12:05","un":"Filial Curitiba","st":"Logística","loc":"Doca de recebimento","tu":"1º Turno","n":45,"cat":"Choque contra objeto","ori":"Comportamental","de":"Queda de peça de 8 kg sobre o pé durante descarga. A biqueira de aço evitou lesão grave; contusão leve atendida no ambulatório.","ca":"Peça apoiada de forma instável no pallet; botina com biqueira cumpriu a função de proteção.","gp":"alta","gl":"leve","af":"sem_afastamento","at":"ambulatorial","cn":null,"ct":null,"s":"em_analise","tl":"tipico","cid":"S90.3","nx":"confirmado","ag":"07.03 — Choque contra objeto","da":0,"hp":1.5,"fe":[]},
   {"k":"i01","tipo":"incidente","d":3,"h":"10:20","un":"Metalúrgica Exemplo","st":"Manutenção","loc":"Passarela de acesso às prensas","tu":"1º Turno","n":31,"cat":"Quase queda","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Mecânico quase caiu da passarela elevada porque o trecho final está sem corrimão após uma obra de adaptação.","ca":null,"gp":"alta","s":"em_aberto","fe":[]},
   {"k":"i02","tipo":"incidente","d":6,"h":"15:45","un":"Metalúrgica Exemplo","st":"Logística","loc":"Faixa de pedestres do pátio","tu":"2º Turno","n":42,"cat":"Choque contra objeto","ori":"Comportamental","de":"Empilhadeira passou a menos de um metro de um pedestre na faixa de segurança. O operador não percebeu a presença do colaborador.","ca":"Falta de espelho convexo na esquina e sinal sonoro baixo; pedestre atravessando falando ao celular.","gp":"critica","s":"em_analise","fe":["Falta de treinamento ou treinamento insuficiente"]},
   {"k":"i03","tipo":"incidente","d":9,"h":"08:10","un":"Metalúrgica Exemplo","st":"Produção","loc":"Usinagem CNC, corredor central","tu":"1º Turno","n":null,"cat":"Condição insegura","ori":"Ambiental (iluminação, temperatura, ruído, piso)","de":"Inspeção encontrou cavaco acumulado e piso com fluido de corte entre os tornos 03 e 04, com risco de escorregão.","ca":"Limpeza fora do fim de turno e ausência de bandeja coletora de fluido nas máquinas mais antigas.","gp":"media","s":"acoes_andamento","fe":[]},
   {"k":"i04","tipo":"incidente","d":15,"h":"14:00","un":"Filial Curitiba","st":"Manutenção","loc":"Quadro de comando principal","tu":"1º Turno","n":null,"cat":"Condição insegura","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Cabo energizado com isolamento danificado encontrado no quadro de comando durante inspeção de rotina (NR-10).","ca":"Fiação antiga sem substituição programada; roedores na canaleta.","gp":"critica","s":"concluido","fe":[]},
   {"k":"i05","tipo":"incidente","d":22,"h":"09:30","un":"Metalúrgica Exemplo","st":"Produção","loc":"Corte, guilhotina 01","tu":"1º Turno","n":null,"cat":"Falha de máquina / equipamento","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Intertravamento da proteção móvel da guilhotina foi encontrado desligado por um jumper improvisado.","ca":"Intertravamento falhava com frequência e a manutenção demorava; o jumper foi colocado para não parar a linha.","gp":"critica","s":"acoes_andamento","fe":["Pressão excessiva por meta / produção"]},
   {"k":"i06","tipo":"incidente","d":28,"h":"13:35","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda, esmerilhamento","tu":"2º Turno","n":18,"cat":"Ato inseguro","ori":"Comportamental","de":"Soldador esmerilhando sem protetor auricular em área acima de 85 dB(A), flagrado pelo técnico de segurança em ronda.","ca":"Protetor esquecido no armário; falta de lembrete visual na entrada da área.","gp":"media","s":"concluido","fe":["Ruído intenso"]},
   {"k":"i07","tipo":"incidente","d":40,"h":"17:10","un":"Metalúrgica Exemplo","st":"Logística","loc":"Doca de expedição","tu":"2º Turno","n":50,"cat":"Choque contra objeto","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Chapa de aço escorregou do pallet durante o carregamento e caiu a poucos centímetros de um auxiliar.","ca":"Pallet mal amarrado e ponte rolante com gancho sem trava de segurança.","gp":"critica","s":"concluido","fe":[]},
   {"k":"i08","tipo":"incidente","d":55,"h":"11:05","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda, cabine 03","tu":"1º Turno","n":20,"cat":"Exposição a agente químico","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Exaustão da cabine 03 desligada com soldador trabalhando por 40 minutos; fumos visíveis no ambiente.","ca":"Chave da exaustão sem identificação; motor com falha intermitente.","gp":"alta","s":"acoes_andamento","fe":[]},
   {"k":"i09","tipo":"incidente","d":75,"h":"10:00","un":"Metalúrgica Exemplo","st":"Produção","loc":"Corredor da montagem","tu":"1º Turno","n":null,"cat":"Condição insegura","ori":"Organizacional (pressão, falta de recurso, falta de pessoal)","de":"Extintor com inspeção vencida e acesso parcialmente bloqueado por pallet no corredor da montagem.","ca":"Responsável pela inspeção mensal de extintores em férias sem substituto designado.","gp":"media","s":"concluido","fe":[]},
   {"k":"i10","tipo":"incidente","d":90,"h":"08:45","un":"Metalúrgica Exemplo","st":"Manutenção","loc":"Oficina elétrica","tu":"1º Turno","n":37,"cat":"Falha de EPI","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Cinturão paraquedista com costura desgastada identificado na conferência pré-uso antes de subir em eletrocalha. Equipamento retirado de uso.","ca":"Vida útil do cinturão excedida; controle de inspeção periódica sem registro.","gp":"critica","s":"concluido","fe":[]},
   {"k":"i11","tipo":"incidente","d":110,"h":"16:20","un":"Metalúrgica Exemplo","st":"Produção","loc":"Montagem, prensa hidráulica 01","tu":"2º Turno","n":null,"cat":"Condição insegura","ori":"Técnica (máquina, ferramenta, EPI, layout)","de":"Vazamento de óleo hidráulico na mangueira da prensa 01 formando poça ao lado do posto de trabalho.","ca":"Mangueira com mais de 5 anos sem troca preventiva.","gp":"media","s":"concluido","fe":[]},
   {"k":"i12","tipo":"incidente","d":140,"h":"14:50","un":"Centro de Distribuição Itajaí","st":"Logística","loc":"Pátio de carga","tu":"2º Turno","n":44,"cat":"Ato inseguro","ori":"Comportamental","de":"Empilhadeira operando com carga acima da capacidade nominal, percebida pela inclinação do garfo. Operação interrompida pelo líder.","ca":"Etiqueta de capacidade ilegível; pressa para encerrar o carregamento antes do fim do turno.","gp":"alta","s":"concluido","fe":["Ritmo de trabalho acelerado / pressa"]},
   {"k":"i13","tipo":"incidente","d":180,"h":"09:15","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda, esmerilhamento","tu":"1º Turno","n":null,"cat":"Exposição a ruído","ori":"Ambiental (iluminação, temperatura, ruído, piso)","de":"Medição de rotina indicou ruído de 92 dB(A) no esmerilhamento, acima do limite de ação, com um colaborador sem dupla proteção.","ca":"Equipamentos antigos sem enclausuramento; protetor plug usado de forma incorreta.","gp":"media","s":"concluido","fe":["Ruído intenso"]},
   {"k":"i14","tipo":"incidente","d":230,"h":"15:30","un":"Metalúrgica Exemplo","st":"Logística","loc":"Saída de emergência do galpão 2","tu":"2º Turno","n":null,"cat":"Condição insegura","ori":"Organizacional (pressão, falta de recurso, falta de pessoal)","de":"Rota de fuga parcialmente bloqueada por pallets de matéria-prima durante recebimento de carga.","ca":"Pico de recebimento sem área de espera definida.","gp":"alta","s":"concluido","fe":[]},
   {"k":"i15","tipo":"incidente","d":300,"h":"10:40","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda, cabine 01","tu":"3º Turno","n":null,"cat":"Ato inseguro","ori":"Comportamental","de":"Respingos de solda atingiram colaborador vizinho sem lesão por ausência de biombo de proteção entre as cabines.","ca":"Biombo removido para limpeza e não reinstalado.","gp":"media","s":"concluido","fe":[]}
  ]'::jsonb;

  INSERT INTO public.eventos_sst (
    id, tenant_id, tipo, status, data_evento, hora_evento, unidade, setor, local_especifico, turno,
    colaborador_id, colaborador_nome, colaborador_funcao, colaborador_tempo_empresa, categoria_principal, origem_predominante,
    descricao, percepcao_causa, gravidade_potencial, gravidade_lesao, afastamento, obito, atendimento,
    cat_emitida, cat_numero, cat_data_emissao, cat_tipo, fatores_ergonomicos,
    tipo_acidente_legal, cid10, nexo_causal, agente_causador_esocial, dias_afastamento_total, horas_perdidas,
    criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('evento_sst:' || x.k), v_t, x.tipo::public.evento_sst_tipo, x.s::public.evento_sst_status,
         CURRENT_DATE - x.d, x.h::time, x.un, x.st, x.loc, x.tu,
         a.id::text, a.nome_completo, a.cargo,
         CASE WHEN a.id IS NULL THEN NULL ELSE
           (GREATEST(0, (((CURRENT_DATE - x.d) - a.data_admissao) / 30)) / 12)::text || ' anos e ' ||
           (GREATEST(0, (((CURRENT_DATE - x.d) - a.data_admissao) / 30)) % 12)::text || ' meses' END,
         x.cat, x.ori, x.de, x.ca, x.gp,
         x.gl::public.acidente_gravidade_lesao, x.af::public.acidente_afastamento, false, x.at::public.acidente_atendimento,
         (x.cn IS NOT NULL), x.cn, CASE WHEN x.cn IS NULL THEN NULL ELSE (CURRENT_DATE - x.d + 1) END, x.ct::public.cat_tipo,
         ARRAY(SELECT jsonb_array_elements_text(COALESCE(x.fe, '[]'::jsonb))),
         x.tl, x.cid, x.nx, x.ag, COALESCE(x.da, 0), COALESCE(x.hp, 0),
         v_uid::text, v_nome, (CURRENT_DATE - x.d) + TIME '18:00'
  FROM jsonb_to_recordset(v_ev) AS x(k text, tipo text, d int, h text, un text, st text, loc text, tu text, n int, cat text, ori text,
                                      de text, ca text, gp text, gl text, af text, at text, cn text, ct text, s text, tl text,
                                      cid text, nx text, ag text, da int, hp numeric, fe jsonb)
  LEFT JOIN public.admissoes a ON a.id = public.demo_id('admissao:' || x.n) AND a.tenant_id = v_t
  WHERE NOT EXISTS (SELECT 1 FROM public.eventos_sst e WHERE e.id = public.demo_id('evento_sst:' || x.k))
  ORDER BY x.d DESC, x.k;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Incidentes/acidentes (ocorrencias) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $inc1$;

DO $inc2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
  v_ac jsonb;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Acoes do plano de acao: ev = ocorrencia de origem (quando houver); pz = prazo em dias a partir de hoje;
  -- rn = numero do colaborador responsavel (0 = o usuario da demonstracao); ini/conc = dias atras.
  v_ac := '[
   {"k":"s01","ev":"a01","t":"Instalar gancho de remoção de cavaco nos tornos CNC","d":"Fornecer e fixar ganchos e escovas de remoção de cavaco em todos os tornos para eliminar a limpeza com a mão.","p":"Corte no dedo durante a limpeza de cavaco sem ferramenta adequada.","o":"Usinagem CNC","c":"Comprar 12 ganchos, fixar suporte magnético e treinar os operadores.","tp":"corretiva","pz":25,"s":"em_andamento","pg":60,"pr":"urgente","g":4,"u":4,"te":3,"or":"sst","rn":28,"cu":1800,"ini":10},
   {"k":"s02","ev":"a01","t":"Reforçar uso obrigatório de luva anticorte com auditoria semanal","d":"Diálogo de segurança em todos os turnos e checagem semanal do uso da luva anticorte na usinagem.","p":"Luva disponível, mas não usada no momento do acidente.","o":"Usinagem CNC","c":"DDS de 10 minutos por turno e planilha de auditoria comportamental.","tp":"preventiva","pz":-3,"s":"concluida","pg":100,"pr":"medio","g":3,"u":3,"te":3,"or":"sst","rn":0,"cu":0,"ini":12,"conc":3},
   {"k":"s03","ev":"a02","t":"Substituir aventais curtos por conjunto completo de raspa para soldagem","d":"Adquirir aventais longos e manguitos de raspa para todos os soldadores.","p":"Queimadura por respingo no antebraço com conjunto incompleto.","o":"Solda","c":"Cotação com três fornecedores, entrega e registro na ficha de EPI.","tp":"corretiva","pz":-30,"s":"concluida","pg":100,"pr":"urgente","g":4,"u":4,"te":3,"or":"sst","rn":29,"cu":2400,"ini":44,"conc":32},
   {"k":"s04","ev":"a03","t":"Instalar cortina de luz e comando bimanual na prensa hidráulica 02 (NR-12)","d":"Adequar a prensa com cortina de luz categoria 4, comando bimanual com anti-repetição e parada de emergência.","p":"Esmagamento da mão por dispositivo de segurança burlado.","o":"Montagem, prensa hidráulica 02","c":"Projeto de adequação por empresa especializada, instalação em parada programada e laudo de conformidade.","tp":"corretiva","pz":40,"s":"em_andamento","pg":40,"pr":"imediato","g":5,"u":4,"te":4,"or":"sst","rn":40,"cu":18500,"ini":90},
   {"k":"s05","ev":"a03","t":"Revisar APR da prensa e treinar operadores","d":"Revisar a Análise Preliminar de Risco da prensa e treinar todos os operadores no novo procedimento.","p":"Operação sem procedimento seguro atualizado.","o":"Montagem","c":"Revisão da APR, reunião com a equipe e registro de treinamento.","tp":"preventiva","pz":-60,"s":"concluida","pg":100,"pr":"urgente","g":4,"u":3,"te":3,"or":"sst","rn":0,"cu":0,"ini":95,"conc":62},
   {"k":"s06","ev":"a04","t":"Implantar rotina de limpeza de piso e kit de absorção de óleo","d":"Disponibilizar kits de absorção nas docas e rotina de inspeção de vazamentos das empilhadeiras.","p":"Queda por piso com óleo hidráulico.","o":"Expedição","c":"Kits em três pontos, checklist de vazamento no início do turno.","tp":"corretiva","pz":-120,"s":"concluida","pg":100,"pr":"medio","g":3,"u":3,"te":2,"or":"sst","rn":52,"cu":650,"ini":148,"conc":125},
   {"k":"s07","ev":"a05","t":"Adquirir carrinhos e auxílios mecânicos para movimentação de caixas","d":"Comprar carrinhos plataforma e mesa elevatória para reduzir a movimentação manual de caixas de 25 kg.","p":"Lombalgia por movimentação manual repetida de cargas.","o":"Armazenagem","c":"Levantar necessidades com a logística, cotar e implantar rodízio de tarefas.","tp":"preventiva","pz":-5,"s":"atrasada","pg":25,"pr":"urgente","g":4,"u":4,"te":4,"or":"sst","rn":52,"cu":7200,"ini":120},
   {"k":"s08","ev":"a06","t":"Substituir óculos por modelo com vedação lateral e criar inspeção mensal","d":"Trocar óculos riscados e incluir inspeção mensal de EPIs na célula de usinagem.","p":"Projeção de cavaco no olho com óculos danificado.","o":"Usinagem CNC","c":"Troca imediata, checklist mensal assinado pelo líder.","tp":"corretiva","pz":15,"s":"pendente","pg":0,"pr":"urgente","g":4,"u":4,"te":3,"or":"sst","rn":28,"cu":450},
   {"k":"s09","ev":"a07","t":"Revisar bloqueio e etiquetagem (LOTO) em painéis elétricos","d":"Revisar o procedimento LOTO, instalar kits de bloqueio nos painéis e reciclar a equipe elétrica na NR-10.","p":"Choque elétrico por painel energizado durante diagnóstico.","o":"Manutenção elétrica","c":"Kits de cadeado e etiqueta por painel, reciclagem e auditoria mensal.","tp":"corretiva","pz":20,"s":"em_andamento","pg":50,"pr":"imediato","g":5,"u":4,"te":3,"or":"sst","rn":40,"cu":3200,"ini":60},
   {"k":"s10","ev":"i01","t":"Instalar corrimão no trecho final da passarela de acesso às prensas","d":"Instalar corrimão e rodapé no trecho sem proteção da passarela.","p":"Quase queda de altura por falta de proteção coletiva.","o":"Passarela das prensas","c":"Serralheria interna fabrica e instala em duas semanas.","tp":"corretiva","pz":10,"s":"pendente","pg":0,"pr":"imediato","g":5,"u":5,"te":3,"or":"sst","rn":40,"cu":950},
   {"k":"s11","ev":"i02","t":"Sinalizar faixa de pedestres e instalar espelhos convexos e alarme de ré","d":"Pintura da faixa, espelhos nas esquinas do pátio e alarme de ré reforçado nas empilhadeiras.","p":"Quase atropelamento de pedestre por empilhadeira.","o":"Pátio logístico","c":"Compra dos espelhos, pintura e teste dos alarmes.","tp":"preventiva","pz":18,"s":"em_andamento","pg":35,"pr":"urgente","g":5,"u":4,"te":3,"or":"sst","rn":52,"cu":2100,"ini":5},
   {"k":"s12","ev":"i03","t":"Instalar bandejas coletoras e rotina de limpeza no fim do turno","d":"Instalar bandejas coletoras de fluido nos tornos antigos e rotina de limpeza ao final de cada turno.","p":"Piso com fluido e cavaco gerando risco de escorregão.","o":"Usinagem CNC","c":"Bandejas sob medida e checklist de limpeza assinado pelo líder.","tp":"corretiva","pz":-7,"s":"atrasada","pg":30,"pr":"medio","g":3,"u":3,"te":3,"or":"sst","rn":28,"cu":1300,"ini":8},
   {"k":"s13","ev":"i04","t":"Reorganizar a fiação do quadro de comando e isolar partes vivas","d":"Substituir cabos danificados, proteger a canaleta contra roedores e etiquetar circuitos.","p":"Cabo energizado com isolamento danificado.","o":"Filial Curitiba, quadro principal","c":"Parada programada de duas horas e termografia após a intervenção.","tp":"corretiva","pz":-10,"s":"concluida","pg":100,"pr":"imediato","g":5,"u":5,"te":3,"or":"sst","rn":36,"cu":2800,"ini":14,"conc":11},
   {"k":"s14","ev":"i05","t":"Substituir intertravamento da guilhotina e auditar as demais máquinas","d":"Trocar o intertravamento, remover o jumper e auditar proteções de todas as máquinas de corte e dobra.","p":"Proteção móvel com intertravamento burlado.","o":"Corte e dobra","c":"Substituição por peça original, auditoria NR-12 e treinamento de manutenção.","tp":"corretiva","pz":12,"s":"em_andamento","pg":55,"pr":"imediato","g":5,"u":4,"te":4,"or":"sst","rn":40,"cu":5400,"ini":18},
   {"k":"s15","ev":"i08","t":"Reparar exaustão da cabine de solda 03 e instalar indicador de funcionamento","d":"Trocar o motor da exaustão, identificar o comando e instalar sinalizador luminoso de funcionamento.","p":"Soldagem com exaustão desligada e fumos no ambiente.","o":"Solda, cabine 03","c":"Reparo do motor, sinalizador e inclusão em rota de inspeção semanal.","tp":"corretiva","pz":-12,"s":"atrasada","pg":20,"pr":"urgente","g":4,"u":4,"te":3,"or":"sst","rn":29,"cu":4100,"ini":50},
   {"k":"e01","ev":null,"t":"Renovar o CA do Respirador PFF2 (vencido) e cotar novo lote","d":"O CA do respirador descartável PFF2 venceu. Localizar o CA renovado do fabricante ou trocar de modelo antes da próxima entrega.","p":"Entregar EPI com CA vencido equivale a não entregar (NR-6).","o":"Almoxarifado Central","c":"Contato com fornecedor, atualização do cadastro do CA e segregação do estoque.","tp":"corretiva","pz":5,"s":"pendente","pg":0,"pr":"imediato","g":5,"u":5,"te":3,"or":"epi","rn":0,"cu":600},
   {"k":"e02","ev":null,"t":"Substituir abafadores de ruído com CA a vencer e abrir cotação","d":"O CA do abafador tipo concha vence em poucos dias e o estoque está abaixo do mínimo.","p":"Garantir proteção auditiva com CA vigente na usinagem e na solda.","o":"Almoxarifado Central","c":"Cotação, pedido de compra e troca dos itens antigos conforme a ficha.","tp":"preventiva","pz":14,"s":"em_andamento","pg":45,"pr":"urgente","g":4,"u":4,"te":3,"or":"epi","rn":52,"cu":1900},
   {"k":"e03","ev":null,"t":"Repor estoque do cinturão paraquedista (zerado)","d":"Estoque zerado de cinturão paraquedista; eletricistas e montadores dependem do item para trabalho em altura.","p":"Trabalho em altura exige cinturão com CA e inspeção prévia (NR-35).","o":"Almoxarifado Central","c":"Pedido de compra emergencial de 6 unidades e conferência de CA na entrada.","tp":"corretiva","pz":3,"s":"pendente","pg":0,"pr":"imediato","g":5,"u":5,"te":4,"or":"epi","rn":0,"cu":1440},
   {"k":"e04","ev":null,"t":"Descartar lotes vencidos de plug auricular e PFF2 mantidos em quarentena","d":"Dois lotes vencidos aguardam descarte em quarentena. Registrar saída, baixar o estoque e arquivar o termo de descarte.","p":"Item vencido fica segregado e fora do saldo entregável (NR-6).","o":"Almoxarifado Central","c":"Termo de descarte assinado pelo técnico de segurança e registro de movimentação.","tp":"corretiva","pz":7,"s":"pendente","pg":10,"pr":"medio","g":3,"u":3,"te":2,"or":"epi","rn":0,"cu":0},
   {"k":"e05","ev":null,"t":"Auditar fichas de EPI aguardando assinatura do colaborador","d":"Quatro entregas aguardam assinatura. Coletar o aceite e arquivar o recibo na ficha de EPI do colaborador.","p":"Sem assinatura a entrega não comprova o recebimento do EPI.","o":"Almoxarifado Setorial","c":"Ronda do almoxarifado nos três turnos para coletar as assinaturas.","tp":"preventiva","pz":6,"s":"em_andamento","pg":50,"pr":"medio","g":3,"u":3,"te":3,"or":"epi","rn":0,"cu":0},
   {"k":"e06","ev":null,"t":"Elaborar matriz de EPI para cargos administrativos e comerciais","d":"Cargos administrativos que visitam a fábrica não possuem matriz de EPI definida.","p":"Visitantes internos precisam de proteção mínima ao circular na área fabril.","o":"RH e SST","c":"Definir kit visitante (óculos, protetor auricular, colete) e cadastrar na matriz.","tp":"melhoria","pz":35,"s":"pendente","pg":0,"pr":"baixo","g":2,"u":2,"te":2,"or":"epi","rn":0,"cu":0},
   {"k":"e07","ev":null,"t":"Implantar inspeção trimestral dos cinturões e talabartes","d":"Inspeção formal trimestral com registro e identificação dos equipamentos aprovados.","p":"Cinturão com costura desgastada foi detectado por acaso.","o":"Manutenção elétrica","c":"Checklist de inspeção, etiqueta de aprovado e arquivo no sistema.","tp":"preventiva","pz":-40,"s":"concluida","pg":100,"pr":"urgente","g":4,"u":3,"te":3,"or":"epi","rn":40,"cu":0,"ini":85,"conc":42}
  ]'::jsonb;

  INSERT INTO public.plano_acoes (
    id, tenant_id, empresa_id, titulo, descricao, porque, onde, como, prazo, responsavel_id, responsavel_nome,
    custo_estimado, custo_real, origem_modulo, origem_id, origem_descricao, gravidade, urgencia, tendencia,
    prioridade, status, progresso, data_inicio, data_conclusao, tipo, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('plano_acao:' || x.k), v_t, v_e, x.t, x.d, x.p, x.o, x.c, CURRENT_DATE + x.pz,
         CASE WHEN COALESCE(x.rn, 0) = 0 THEN v_uid END,
         CASE WHEN COALESCE(x.rn, 0) = 0 THEN v_nome ELSE r.nome_completo END,
         x.cu, CASE WHEN x.s = 'concluida' THEN x.cu END,
         x.or, ev.id,
         CASE WHEN ev.id IS NULL THEN 'EPI → ' || x.t
              ELSE 'SST → ' || CASE WHEN ev.tipo = 'acidente' THEN 'Acidente ' ELSE 'Incidente ' END || ev.codigo END,
         x.g, x.u, x.te, x.pr::public.acao_gut_prioridade, x.s::public.acao_status, x.pg,
         CURRENT_DATE - COALESCE(x.ini, 7), CASE WHEN x.s = 'concluida' THEN CURRENT_DATE - COALESCE(x.conc, 1) END,
         x.tp, v_uid, v_nome, (CURRENT_DATE - COALESCE(x.ini, 7)) + TIME '09:00'
  FROM jsonb_to_recordset(v_ac) AS x(k text, ev text, t text, d text, p text, o text, c text, tp text, pz int, s text, pg int,
                                      pr text, g int, u int, te int, "or" text, rn int, cu numeric, ini int, conc int)
  LEFT JOIN public.eventos_sst ev ON ev.id = public.demo_id('evento_sst:' || x.ev)
  LEFT JOIN public.admissoes r ON r.id = public.demo_id('admissao:' || x.rn) AND r.tenant_id = v_t AND COALESCE(x.rn, 0) > 0
  WHERE NOT EXISTS (SELECT 1 FROM public.plano_acoes p WHERE p.id = public.demo_id('plano_acao:' || x.k))
  ORDER BY x.k;

  -- Vinculo ocorrencia <-> acao
  INSERT INTO public.evento_sst_acoes (id, tenant_id, evento_id, acao_id)
  SELECT public.demo_id('evento_acao:' || x.k), v_t, public.demo_id('evento_sst:' || x.ev), public.demo_id('plano_acao:' || x.k)
  FROM jsonb_to_recordset(v_ac) AS x(k text, ev text)
  WHERE x.ev IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.eventos_sst e WHERE e.id = public.demo_id('evento_sst:' || x.ev))
    AND EXISTS (SELECT 1 FROM public.plano_acoes p WHERE p.id = public.demo_id('plano_acao:' || x.k))
    AND NOT EXISTS (SELECT 1 FROM public.evento_sst_acoes l WHERE l.id = public.demo_id('evento_acao:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Acoes de SST/EPI (plano de acao) nao concluido: % (%)', SQLERRM, SQLSTATE;
END $inc2$;

DO $inc3$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_dv jsonb;
BEGIN
  -- Desvios de seguranca (base da piramide): d = dias atras
  v_dv := '[
   {"k":1,"tp":"condicao_insegura","cat":"Piso","pot":"medio","s":"resolvido","un":"Metalúrgica Exemplo","st":"Produção","loc":"Usinagem CNC","tu":"1º Turno","d":6,"de":"Fluido de corte escorrendo de bandeja trincada em torno antigo.","ca":"Bandeja trincada sem reposição.","ai":"Colocado absorvente e bandeja substituída.","rn":28},
   {"k":2,"tp":"ato_inseguro","cat":"EPI","pot":"medio","s":"em_tratamento","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda","tu":"2º Turno","d":4,"de":"Soldador sem avental completo em bancada de montagem.","ca":"Avental guardado no armário distante.","ai":"Orientação imediata e aviso ao líder.","rn":29},
   {"k":3,"tp":"condicao_insegura","cat":"Máquinas","pot":"alto","s":"aberto","un":"Metalúrgica Exemplo","st":"Produção","loc":"Corte e dobra","tu":"1º Turno","d":2,"de":"Protetor lateral da dobradeira sem um dos parafusos de fixação.","ca":"Parafuso perdido na última manutenção.","ai":"Máquina sinalizada e solicitada correção.","rn":0},
   {"k":4,"tp":"ato_inseguro","cat":"Empilhadeira","pot":"alto","s":"resolvido","un":"Metalúrgica Exemplo","st":"Logística","loc":"Pátio","tu":"2º Turno","d":10,"de":"Empilhadeira trafegando com garfos elevados em área de pedestres.","ca":"Pressa na movimentação.","ai":"Operador reorientado e reciclagem agendada.","rn":52},
   {"k":5,"tp":"condicao_insegura","cat":"Elétrica","pot":"alto","s":"em_tratamento","un":"Filial Curitiba","st":"Manutenção","loc":"Oficina","tu":"1º Turno","d":13,"de":"Extensão elétrica improvisada com emenda sem isolamento.","ca":"Falta de tomadas na bancada.","ai":"Extensão recolhida; tomadas solicitadas.","rn":36},
   {"k":6,"tp":"ato_inseguro","cat":"Ergonomia","pot":"baixo","s":"resolvido","un":"Metalúrgica Exemplo","st":"Logística","loc":"Armazenagem","tu":"1º Turno","d":17,"de":"Colaborador levantando caixa pesada sozinho com tronco flexionado.","ca":"Carrinho distante do posto.","ai":"Orientação sobre postura e uso do carrinho.","rn":48},
   {"k":7,"tp":"desvio_processo","cat":"Procedimento","pot":"medio","s":"aberto","un":"Metalúrgica Exemplo","st":"Manutenção","loc":"Oficina mecânica","tu":"1º Turno","d":8,"de":"Bloqueio e etiquetagem não registrado em intervenção de rotina.","ca":"Planilha LOTO na sala do supervisor, longe da oficina.","ai":"Reforço verbal com a equipe.","rn":40},
   {"k":8,"tp":"condicao_insegura","cat":"Incêndio","pot":"alto","s":"resolvido","un":"Metalúrgica Exemplo","st":"Produção","loc":"Montagem","tu":"1º Turno","d":24,"de":"Extintor sem sinalização de solo e com acesso parcial por caixas.","ca":"Reorganização do layout sem revisar a sinalização.","ai":"Acesso liberado e piso sinalizado.","rn":29},
   {"k":9,"tp":"ato_inseguro","cat":"Ruído","pot":"medio","s":"resolvido","un":"Metalúrgica Exemplo","st":"Produção","loc":"Solda","tu":"3º Turno","d":27,"de":"Dois colaboradores sem protetor auricular no esmerilhamento.","ca":"Protetores acabaram na prateleira do setor.","ai":"Reposição imediata no almoxarifado setorial.","rn":29},
   {"k":10,"tp":"condicao_insegura","cat":"Altura","pot":"critico","s":"em_tratamento","un":"Metalúrgica Exemplo","st":"Manutenção","loc":"Passarela das prensas","tu":"1º Turno","d":3,"de":"Trecho de passarela sem corrimão após adaptação de obra.","ca":"Obra concluída sem revisão de segurança.","ai":"Isolado com fita e correntes.","rn":40},
   {"k":11,"tp":"ato_inseguro","cat":"EPI","pot":"baixo","s":"resolvido","un":"Centro de Distribuição Itajaí","st":"Logística","loc":"Doca","tu":"2º Turno","d":31,"de":"Auxiliar sem colete refletivo na área de tráfego.","ca":"Colete molhado após lavagem.","ai":"Entregue colete reserva.","rn":52},
   {"k":12,"tp":"condicao_insegura","cat":"Iluminação","pot":"medio","s":"aberto","un":"Metalúrgica Exemplo","st":"Logística","loc":"Corredor C","tu":"2º Turno","d":1,"de":"Três luminárias queimadas no corredor C da armazenagem.","ca":"Lâmpadas sem reposição no almoxarifado de manutenção.","ai":"Ordem de serviço aberta.","rn":0},
   {"k":13,"tp":"desvio_processo","cat":"Permissão de trabalho","pot":"alto","s":"resolvido","un":"Metalúrgica Exemplo","st":"Manutenção","loc":"Telhado do galpão 1","tu":"1º Turno","d":35,"de":"Serviço no telhado iniciado antes da emissão completa da permissão de trabalho em altura.","ca":"Urgência de reparo de goteira.","ai":"Serviço parado até a liberação e orientação da equipe.","rn":40},
   {"k":14,"tp":"ato_inseguro","cat":"Máquinas","pot":"alto","s":"convertido_incidente","un":"Metalúrgica Exemplo","st":"Produção","loc":"Corte e dobra","tu":"1º Turno","d":22,"de":"Intertravamento da guilhotina anulado com jumper.","ca":"Falha frequente do sensor.","ai":"Máquina bloqueada.","rn":29},
   {"k":15,"tp":"condicao_insegura","cat":"Químico","pot":"medio","s":"cancelado","un":"Metalúrgica Exemplo","st":"Produção","loc":"Almoxarifado de insumos","tu":"1º Turno","d":45,"de":"Frasco sem rótulo identificado como água destilada na verificação; sem risco.","ca":"Reenvase sem etiqueta.","ai":"Frasco identificado.","rn":0},
   {"k":16,"tp":"ato_inseguro","cat":"Comportamento","pot":"baixo","s":"resolvido","un":"Metalúrgica Exemplo","st":"Administrativo","loc":"Escritório","tu":"1º Turno","d":50,"de":"Uso de celular ao descer a escada do mezanino.","ca":"Hábito de atender chamadas em movimento.","ai":"Orientação em DDS.","rn":0}
  ]'::jsonb;

  INSERT INTO public.desvios_seguranca (
    id, tenant_id, empresa_id, tipo_desvio, categoria, potencial_risco, status, unidade, setor, local_especifico, turno,
    data_desvio, hora_desvio, reportante_id, reportante_nome, reportante_anonimo, descricao, causa_provavel,
    acao_imediata, acao_imediata_responsavel, acao_imediata_prazo, criado_por_nome, created_at
  )
  SELECT public.demo_id('desvio:' || x.k), v_t, v_e, x.tp, x.cat, x.pot, x.s, x.un, x.st, x.loc, x.tu,
         CURRENT_DATE - x.d, (TIME '07:30' + (x.k * INTERVAL '37 minutes'))::time, r.id::text, r.nome_completo, false,
         x.de, x.ca, x.ai, COALESCE(g.nome_completo, 'Equipe de SST'), CURRENT_DATE - x.d + 7,
         COALESCE(r.nome_completo, 'Equipe de SST'), (CURRENT_DATE - x.d) + TIME '17:00'
  FROM jsonb_to_recordset(v_dv) AS x(k int, tp text, cat text, pot text, s text, un text, st text, loc text, tu text, d int, de text, ca text, ai text, rn int)
  LEFT JOIN public.admissoes r ON r.id = public.demo_id('admissao:' || (10 + x.k * 3)) AND r.tenant_id = v_t
  LEFT JOIN public.admissoes g ON g.id = public.demo_id('admissao:' || x.rn) AND g.tenant_id = v_t AND x.rn > 0
  WHERE NOT EXISTS (SELECT 1 FROM public.desvios_seguranca d WHERE d.id = public.demo_id('desvio:' || x.k))
  ORDER BY x.d DESC;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Desvios de seguranca nao concluido: % (%)', SQLERRM, SQLSTATE;
END $inc3$;

-- ---------------------------------------------------------------------------
-- (5) Ergonomia — itens da NR-17, analises por posto, riscos, acoes e inventario GRO
-- ---------------------------------------------------------------------------
DO $ergo1$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Itens da NR-17 (checklist de conformidade) com variedade de situacao
  INSERT INTO public.ergonomia_itens_nr17 (
    id, tenant_id, empresa_id, categoria, codigo, titulo, descricao, status, responsavel_id, responsavel_nome,
    data_avaliacao, proxima_reavaliacao, observacoes
  )
  SELECT public.demo_id('ergo_item:' || i.codigo), v_t, v_e, i.cat::public.ergonomia_categoria, i.codigo, i.titulo, i.descr,
         i.st::public.ergonomia_status, CASE WHEN i.resp = 'user' THEN v_uid END,
         CASE WHEN i.resp = 'user' THEN v_nome ELSE 'Equipe SESMT' END,
         CASE WHEN i.st = 'nao_aplicavel' THEN NULL ELSE (now() - (i.av || ' days')::interval) END,
         CASE WHEN i.st = 'nao_aplicavel' THEN NULL ELSE CURRENT_DATE + i.rv END, i.obs
  FROM (VALUES
    ('organizacao_trabalho', '17.1.1', 'Adaptação das condições de trabalho', 'As condições de trabalho devem ser adaptadas às características psicofisiológicas dos trabalhadores.', 'atendido', 'user', 40, 320, 'Avaliação realizada na revisão anual do PGR; evidências anexadas ao inventário.'),
    ('organizacao_trabalho', '17.6.1', 'Normas de produção e modo operatório', 'A organização do trabalho considera normas de produção, modo operatório, exigência de tempo e ritmo.', 'parcial', 'sesmt', 25, 60, 'Metas da usinagem revisadas; falta revisar o ritmo da linha de montagem.'),
    ('organizacao_trabalho', '17.6.2', 'Pausas para descanso', 'Atividades com sobrecarga muscular exigem pausas para descanso.', 'nao_atendido', 'sesmt', 18, -12, 'Linha de montagem sem pausas formais; proposta de pausas de 10 minutos em análise.'),
    ('organizacao_trabalho', '17.6.3', 'Retorno ao trabalho após afastamento', 'Retorno gradativo da exigência de produção após afastamentos iguais ou superiores a 15 dias.', 'atendido', 'user', 55, 250, 'Procedimento de retorno gradual aplicado nos dois últimos casos.'),
    ('mobiliario', '17.3.1', 'Postura adequada no posto de trabalho', 'Postos planejados ou adaptados para a posição sentada quando possível.', 'atendido', 'sesmt', 70, 200, 'Postos administrativos revisados.'),
    ('mobiliario', '17.3.2', 'Assentos nos postos de trabalho', 'Bancadas e mesas devem permitir boa postura, visualização e operação.', 'parcial', 'sesmt', 22, 45, 'Bancadas fixas da montagem acima da altura ideal em 4 de 6 postos.'),
    ('mobiliario', '17.3.3', 'Características do assento', 'Altura ajustável, borda frontal arredondada e encosto com suporte lombar.', 'atendido', 'sesmt', 70, 200, NULL),
    ('mobiliario', '17.3.4', 'Apoio para os pés', 'Suporte para os pés quando indicado pela análise ergonômica.', 'nao_aplicavel', 'sesmt', 0, 0, 'Sem indicação na AET atual.'),
    ('equipamentos', '17.4.1', 'Equipamentos adequados às características', 'Equipamentos adequados às características psicofisiológicas e à natureza do trabalho.', 'parcial', 'user', 30, 75, 'Ferramentas manuais da manutenção em substituição gradual.'),
    ('equipamentos', '17.4.2', 'Processamento eletrônico de dados', 'Suporte adequado para documentos nas atividades de digitação.', 'atendido', 'sesmt', 70, 220, NULL),
    ('equipamentos', '17.4.3', 'Requisitos de teclados', 'Terminais de vídeo com condições mínimas de mobilidade e superfície.', 'atendido', 'sesmt', 70, 220, NULL),
    ('condicoes_ambientais', '17.5.1', 'Condições ambientais confortáveis', 'Condições ambientais adequadas às características dos trabalhadores e da atividade.', 'parcial', 'sesmt', 35, 80, 'Calor na solda no verão; ventilação em estudo.'),
    ('condicoes_ambientais', '17.5.2', 'Níveis de ruído', 'Conforto acústico em locais com atividade intelectual e atenção constantes.', 'nao_atendido', 'sesmt', 35, -5, 'Escritório da qualidade próximo à usinagem com ruído acima do recomendado.'),
    ('condicoes_ambientais', '17.5.3', 'Iluminação adequada', 'Iluminação natural ou artificial apropriada à natureza da atividade.', 'atendido', 'sesmt', 90, 270, 'Luximetria dentro do previsto na NBR ISO/CIE 8995-1.'),
    ('condicoes_ambientais', '17.5.4', 'Temperatura efetiva', 'Temperatura entre 20 e 23 graus Celsius em ambientes de trabalho intelectual.', 'parcial', 'sesmt', 35, 80, 'Escritório climatizado; sala do almoxarifado sem climatização.'),
    ('levantamento_cargas', '17.2.1', 'Limite de peso por trabalhador', 'Transporte manual de cargas não pode comprometer a saúde ou a segurança.', 'parcial', 'user', 20, 40, 'Caixas de 25 kg na armazenagem; carrinhos em compra.'),
    ('levantamento_cargas', '17.2.2', 'Transporte manual regular', 'Peso máximo menor para mulheres e trabalhadores jovens designados ao transporte manual.', 'atendido', 'sesmt', 65, 280, NULL),
    ('levantamento_cargas', '17.2.3', 'Impulsão ou tração de cargas', 'Treinamento ou instruções satisfatórias para o transporte manual regular de cargas.', 'nao_atendido', 'sesmt', 20, 15, 'Treinamento de movimentação manual previsto para o próximo trimestre.'),
    ('levantamento_cargas', '17.2.4', 'Equipamentos mecânicos', 'Levantamento com equipamento mecânico de ação manual compatível com o esforço.', 'parcial', 'sesmt', 20, 40, 'Talhas instaladas na solda; faltam na expedição.'),
    ('aet', '17.1.2', 'Análise Ergonômica do Trabalho', 'O empregador deve realizar a análise ergonômica do trabalho.', 'parcial', 'user', 15, 90, 'AEP concluída para 12 postos; AET completa pendente para usinagem e solda.'),
    ('aet', '17.1.2.1', 'Avaliação de demandas físicas', 'A AET deve contemplar as demandas físicas do trabalho.', 'atendido', 'sesmt', 15, 200, NULL),
    ('aet', '17.1.2.2', 'Avaliação de demandas cognitivas', 'A AET também deve contemplar demandas cognitivas e organizacionais.', 'nao_atendido', 'sesmt', 15, 30, 'Depende do mapeamento psicossocial em andamento.')
  ) AS i(cat, codigo, titulo, descr, st, resp, av, rv, obs)
  WHERE NOT EXISTS (SELECT 1 FROM public.ergonomia_itens_nr17 x WHERE x.tenant_id = v_t AND x.codigo = i.codigo);

  -- Analises por posto de trabalho (AEP/AET): origem manual, checklist ou IA
  INSERT INTO public.ergonomia_analises (
    id, tenant_id, empresa_id, setor, cargo, atividade, unidade, num_trabalhadores, tipo_analise, data_analise, realizado_por,
    riscos_identificados, recomendacoes, lacunas_normativas, conformidade_estimada, resumo_geral, classificacao_risco,
    evidencias_urls, contexto_adicional, status
  )
  SELECT public.demo_id('ergo_analise:' || x.k), v_t, v_e, x.setor, x.cargo, x.ativ, 'Metalúrgica Exemplo', x.nt, x.tipo,
         now() - (x.d || ' days')::interval, x.por, x.riscos, x.rec, x.lac, x.conf, x.resumo, x.cls, '[]'::jsonb, x.ctx, 'ativo'
  FROM (VALUES
    ('01', 'Produção', 'Operador de Usinagem CNC', 'Operação de torno e centro de usinagem, setup e troca de ferramenta', 12, 'ia', 20, 'Equipe SESMT (com apoio da IA)',
      '[{"tipo":"Postura em pé prolongada","eixo":"fisico","severidade":"alto","descricao":"Permanência em pé por mais de 6 horas por turno sem apoio ou revezamento.","itemNR17":"17.3.1"},{"tipo":"Movimentos repetitivos de membros superiores","eixo":"fisico","severidade":"medio","descricao":"Troca frequente de ferramentas e carga de peças com flexão de punho.","itemNR17":"17.4.1"},{"tipo":"Ritmo e metas de produção","eixo":"organizacional","severidade":"medio","descricao":"Meta por célula com pouca margem de pausa entre ciclos.","itemNR17":"17.6.1"}]'::jsonb,
      '["Instalar tapetes antifadiga nos postos em pé","Alternar tarefas de setup e operação a cada 2 horas","Revisar metas considerando pausas","Disponibilizar banco semi-sentado nos tornos de ciclo longo"]'::jsonb,
      '["AET completa do posto ainda não realizada","Sem registro de pausas formais"]'::jsonb, 58,
      'Posto com demanda física moderada a alta por postura estática em pé e movimentos repetitivos. Ações simples reduzem a carga: tapetes antifadiga, revezamento e revisão das metas.', 'moderado', 'Visita de campo no 1º e 2º turno com cronoanálise de 3 ciclos.'),
    ('02', 'Produção', 'Soldador', 'Soldagem MIG/MAG em estruturas, esmerilhamento e acabamento', 9, 'manual', 12, 'Equipe SESMT',
      '[{"tipo":"Posturas forçadas na soldagem fora de posição","eixo":"fisico","severidade":"critico","descricao":"Tronco inclinado e pescoço em extensão por longos períodos em soldagem sobre cabeça.","itemNR17":"17.3.1"},{"tipo":"Vibração mão-braço no esmerilhamento","eixo":"fisico","severidade":"alto","descricao":"Uso prolongado de esmerilhadeira sem rodízio e sem luva antivibração.","itemNR17":"17.4.1"},{"tipo":"Calor e fumos","eixo":"fisico","severidade":"alto","descricao":"Cabine com ventilação irregular e pausas insuficientes em dias quentes.","itemNR17":"17.5.4"}]'::jsonb,
      '["Instalar posicionadores para peças e reduzir a soldagem sobre cabeça","Rodízio entre soldagem e esmerilhamento","Reparar a exaustão da cabine 03","Adotar pausas térmicas em dias de calor"]'::jsonb,
      '["Sem avaliação quantitativa de vibração","AET completa pendente"]'::jsonb, 38,
      'Posto crítico em ergonomia física. Posicionadores de peça e rodízio de tarefas têm o melhor retorno imediato.', 'alto', 'Análise conjunta com a CIPA e acompanhamento de 2 soldadores.'),
    ('03', 'Produção', 'Montador de Estruturas Metálicas', 'Montagem de estruturas em bancada e posicionamento manual de perfis', 6, 'checklist', 25, 'Equipe SESMT',
      '[{"tipo":"Levantamento manual de perfis","eixo":"fisico","severidade":"alto","descricao":"Perfis de até 22 kg levantados sem auxílio de talha em 4 dos 6 postos.","itemNR17":"17.2.1"},{"tipo":"Altura de bancada inadequada","eixo":"fisico","severidade":"alto","descricao":"Bancadas fixas 12 cm acima da altura ideal, exigindo elevação de ombros.","itemNR17":"17.3.2"},{"tipo":"Pausas insuficientes","eixo":"organizacional","severidade":"medio","descricao":"Ciclo contínuo sem pausa formal.","itemNR17":"17.6.2"}]'::jsonb,
      '["Instalar talhas e pórticos leves","Substituir bancadas por modelos de altura regulável","Implantar pausas de 10 minutos a cada 2 horas"]'::jsonb,
      '["Sem treinamento de levantamento manual","Altura das bancadas fora do previsto"]'::jsonb, 42,
      'Principal fonte de risco é o levantamento manual e a altura das bancadas. Ações de engenharia têm prioridade.', 'alto', 'Checklist aplicado com o líder do setor.'),
    ('04', 'Manutenção', 'Mecânico de Manutenção', 'Manutenção corretiva e preventiva de máquinas', 6, 'manual', 30, 'Equipe SESMT',
      '[{"tipo":"Posturas agachadas e de joelhos","eixo":"fisico","severidade":"medio","descricao":"Intervenções em partes baixas de máquinas com apoio inadequado.","itemNR17":"17.3.1"},{"tipo":"Ferramentas manuais inadequadas","eixo":"fisico","severidade":"medio","descricao":"Chaves e extratores desgastados exigem esforço extra.","itemNR17":"17.4.1"}]'::jsonb,
      '["Reposição programada de ferramentas","Disponibilizar carrinho de ferramentas e apoios para joelhos"]'::jsonb,
      '["Sem inventário de ferramentas críticas"]'::jsonb, 66,
      'Risco moderado, com melhorias simples de ferramentas e apoios.', 'moderado', 'Entrevista com 3 mecânicos.'),
    ('05', 'Manutenção', 'Eletricista de Manutenção', 'Manutenção elétrica em painéis e eletrocalhas', 4, 'checklist', 22, 'Equipe SESMT',
      '[{"tipo":"Trabalho com membros superiores elevados","eixo":"fisico","severidade":"medio","descricao":"Cabeamento em eletrocalhas altas exige elevação prolongada dos braços.","itemNR17":"17.3.1"}]'::jsonb,
      '["Plataforma elevatória para trabalhos em altura prolongados","Alternar tarefas de cabeamento"]'::jsonb,
      '[]'::jsonb, 72, 'Demanda física moderada concentrada nas tarefas de cabeamento em altura.', 'baixo', 'Checklist aplicado em obra de adequação.'),
    ('06', 'Logística', 'Operador de Empilhadeira', 'Movimentação de paletes e carregamento de caminhões', 5, 'ia', 15, 'Equipe SESMT (com apoio da IA)',
      '[{"tipo":"Vibração de corpo inteiro","eixo":"fisico","severidade":"medio","descricao":"Pisos irregulares no pátio transmitem vibração ao assento.","itemNR17":"17.5.1"},{"tipo":"Postura torcida de tronco","eixo":"fisico","severidade":"medio","descricao":"Giro de tronco constante nas manobras em marcha à ré.","itemNR17":"17.4.1"},{"tipo":"Atenção contínua e fadiga","eixo":"cognitivo","severidade":"medio","descricao":"Atenção constante em fluxo misto de pedestres e veículos.","itemNR17":"17.1.2.2"}]'::jsonb,
      '["Manutenção do piso do pátio","Câmera de ré nas empilhadeiras","Revezamento a cada 3 horas"]'::jsonb,
      '["Sem medição de vibração"]'::jsonb, 60, 'Posto com exigência cognitiva relevante e vibração moderada.', 'moderado', 'Observação de 2 turnos.'),
    ('07', 'Logística', 'Auxiliar de Logística', 'Separação e movimentação manual de caixas até 25 kg', 6, 'manual', 10, 'Equipe SESMT',
      '[{"tipo":"Levantamento e transporte manual de cargas","eixo":"fisico","severidade":"critico","descricao":"Caixas de 25 kg levantadas do chão até 1,6 m, mais de 40 vezes por hora.","itemNR17":"17.2.1"},{"tipo":"Ritmo acelerado","eixo":"organizacional","severidade":"alto","descricao":"Picos de expedição sem reforço de equipe.","itemNR17":"17.6.1"}]'::jsonb,
      '["Carrinhos e mesas elevatórias","Limitar o peso por caixa a 15 kg quando possível","Treinamento de levantamento manual","Rodízio entre separação e conferência"]'::jsonb,
      '["Treinamento NR-17 pendente","Sem análise biomecânica quantitativa"]'::jsonb, 30,
      'Posto de maior risco ergonômico da empresa; já houve afastamento por lombalgia. Ações de engenharia e treinamento são urgentes.', 'alto', 'Análise motivada pelo acidente por lombalgia.'),
    ('08', 'Administrativo', 'Analista Financeiro', 'Trabalho com computador, conciliações e relatórios', 2, 'checklist', 12, 'Equipe SESMT',
      '[{"tipo":"Postura sentada prolongada","eixo":"fisico","severidade":"baixo","descricao":"Mais de 6 horas sentado, com pausas irregulares.","itemNR17":"17.3.3"},{"tipo":"Monitor fora da altura dos olhos","eixo":"fisico","severidade":"baixo","descricao":"Monitor de notebook sem elevação.","itemNR17":"17.4.3"}]'::jsonb,
      '["Suporte para monitor e teclado externo","Pausas de alongamento a cada 50 minutos"]'::jsonb,
      '[]'::jsonb, 80, 'Postos adequados, com ajustes de monitor e pausas recomendados.', 'baixo', 'Checklist com a coordenação.'),
    ('09', 'Administrativo', 'Analista da Qualidade', 'Inspeção dimensional e laudos na sala da qualidade', 2, 'manual', 18, 'Equipe SESMT',
      '[{"tipo":"Ruído acima do recomendado para atividade intelectual","eixo":"fisico","severidade":"medio","descricao":"Sala próxima à usinagem com ruído de fundo elevado.","itemNR17":"17.5.2"},{"tipo":"Iluminação insuficiente em bancada de inspeção","eixo":"fisico","severidade":"baixo","descricao":"Pontos com menos de 500 lux na bancada de medição.","itemNR17":"17.5.3"}]'::jsonb,
      '["Tratamento acústico da sala","Luminária de bancada para inspeção"]'::jsonb,
      '["Sem medição de ruído no posto"]'::jsonb, 64, 'Conforto acústico é o ponto crítico.', 'moderado', 'Medição pontual com decibelímetro.'),
    ('10', 'Comercial', 'Vendedor Interno', 'Atendimento por telefone e sistema de pedidos', 3, 'checklist', 8, 'Equipe SESMT',
      '[{"tipo":"Uso contínuo de headset e monitor","eixo":"cognitivo","severidade":"baixo","descricao":"Carga cognitiva moderada no atendimento simultâneo de pedidos.","itemNR17":"17.1.2.2"}]'::jsonb,
      '["Pausas entre atendimentos","Revisão da escala em picos de pedidos"]'::jsonb,
      '[]'::jsonb, 84, 'Posto com baixo risco; atenção às pausas no pico de pedidos.', 'baixo', 'Checklist aplicado com a supervisão.'),
    ('11', 'Recursos Humanos', 'Analista de RH', 'Rotinas de departamento pessoal e recrutamento', 2, 'checklist', 6, 'Equipe SESMT',
      '[{"tipo":"Trabalho sentado prolongado","eixo":"fisico","severidade":"baixo","descricao":"Postura sentada sem alternância.","itemNR17":"17.3.3"}]'::jsonb,
      '["Mesa regulável em altura","Pausas ativas"]'::jsonb,
      '[]'::jsonb, 86, 'Posto adequado, com melhorias de conforto.', 'baixo', 'Checklist com a coordenação.'),
    ('12', 'Produção', 'Líder de Produção', 'Supervisão de célula, apoio à operação e registros', 2, 'ia', 3, 'Equipe SESMT (com apoio da IA)',
      '[{"tipo":"Sobrecarga cognitiva e interrupções","eixo":"cognitivo","severidade":"medio","descricao":"Interrupções constantes de operadores e da manutenção durante o turno.","itemNR17":"17.1.2.2"},{"tipo":"Deslocamentos longos em piso duro","eixo":"fisico","severidade":"baixo","descricao":"Caminhada acima de 9 mil passos por turno em piso de concreto.","itemNR17":"17.5.1"}]'::jsonb,
      '["Calçado com palmilha de conforto","Reunião curta de passagem de turno para reduzir interrupções"]'::jsonb,
      '[]'::jsonb, 74, 'Risco moderado, mais cognitivo que físico.', 'moderado', 'Observação de um turno completo.')
  ) AS x(k, setor, cargo, ativ, nt, tipo, d, por, riscos, rec, lac, conf, resumo, cls, ctx)
  WHERE NOT EXISTS (SELECT 1 FROM public.ergonomia_analises a WHERE a.id = public.demo_id('ergo_analise:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ergonomia (itens e analises) nao concluida: % (%)', SQLERRM, SQLSTATE;
END $ergo1$;

DO $ergo2$
DECLARE
  v_t constant uuid := 'd3e00000-0000-4000-8000-000000000001';
  v_e constant uuid := 'd3e00000-0000-4000-8000-000000000002';
  v_uid uuid;
  v_nome text;
BEGIN
  v_uid := (SELECT u.id FROM auth.users u WHERE lower(u.email) = 'leirinuernberg@gmail.com' ORDER BY u.created_at LIMIT 1);
  v_nome := COALESCE((SELECT p.nome_completo FROM public.profiles p WHERE p.user_id = v_uid LIMIT 1), 'Leiri Nuernberg');

  -- Acoes do plano de acao com origem ergonomia (alimentam o painel PDCA e o plano de acao)
  INSERT INTO public.plano_acoes (
    id, tenant_id, empresa_id, titulo, descricao, porque, onde, como, prazo, responsavel_id, responsavel_nome,
    custo_estimado, custo_real, origem_modulo, origem_descricao, gravidade, urgencia, tendencia, prioridade, status,
    progresso, data_inicio, data_conclusao, tipo, criado_por, criado_por_nome, created_at
  )
  SELECT public.demo_id('plano_acao:' || x.k), v_t, v_e, x.t, x.d, x.p, x.o, x.c, CURRENT_DATE + x.pz,
         v_uid, v_nome, x.cu, CASE WHEN x.s = 'concluida' THEN x.cu END, 'ergonomia',
         'Ergonomia → ' || x.o, x.g, x.u, x.te, x.pr::public.acao_gut_prioridade, x.s::public.acao_status, x.pg,
         CURRENT_DATE - x.ini, CASE WHEN x.s = 'concluida' THEN CURRENT_DATE - x.conc END, x.tp, v_uid, v_nome,
         (CURRENT_DATE - x.ini) + TIME '10:00'
  FROM (VALUES
    ('g01', 'Adquirir bancadas de altura regulável para a montagem', 'Substituir as seis bancadas fixas por bancadas com ajuste de altura.', 'Bancadas 12 cm acima da altura ideal (AEP do posto).', 'Montagem', 'Cotação, compra e instalação em parada programada.', 'corretiva', 30, 'em_andamento', 45, 'urgente', 4, 4, 3, 14400, 60, 0),
    ('g02', 'Implantar pausas programadas de 10 minutos na linha de montagem', 'Pausas a cada 2 horas, com alongamento orientado pelo SESMT.', 'Item 17.6.2 da NR-17 não atendido.', 'Montagem', 'Ajuste de escala com a produção e acompanhamento por 30 dias.', 'preventiva', -20, 'concluida', 100, 'medio', 3, 3, 3, 0, 55, 22),
    ('g03', 'Treinar equipe em levantamento manual seguro e uso de talhas', 'Treinamento prático de 4 horas para logística e montagem.', 'Item 17.2.3 não atendido e afastamento por lombalgia.', 'Logística e Montagem', 'Contratar instrutor, turmas por turno e registrar certificado.', 'preventiva', 35, 'pendente', 0, 'urgente', 4, 4, 4, 3800, 5, 0),
    ('g04', 'Realizar AET completa nos postos de usinagem e solda', 'Contratar ergonomista para AET detalhada, com biomecânica e vibração.', 'Item 17.1.2 da NR-17 parcialmente atendido.', 'Usinagem e Solda', 'Contrato com profissional habilitado e plano de visitas em dois turnos.', 'melhoria', 55, 'pendente', 0, 'medio', 3, 3, 3, 9800, 5, 0),
    ('g05', 'Instalar tapetes antifadiga nos postos em pé da usinagem', 'Tapetes antifadiga em oito tornos e centros de usinagem.', 'Postura em pé prolongada identificada na análise do posto.', 'Usinagem CNC', 'Compra de 8 tapetes e fixação com fita antiderrapante.', 'corretiva', -8, 'atrasada', 40, 'medio', 3, 3, 3, 2600, 35, 0),
    ('g06', 'Ajustar monitores e cadeiras do administrativo conforme a AEP', 'Suportes para monitor e revisão de cadeiras.', 'Postos administrativos com monitor abaixo da altura dos olhos.', 'Administrativo', 'Compra de suportes e orientação individual.', 'melhoria', -35, 'concluida', 100, 'baixo', 2, 2, 2, 1200, 60, 38)
  ) AS x(k, t, d, p, o, c, tp, pz, s, pg, pr, g, u, te, cu, ini, conc)
  WHERE NOT EXISTS (SELECT 1 FROM public.plano_acoes a WHERE a.id = public.demo_id('plano_acao:' || x.k));

  -- Riscos ergonomicos (cadastro classico)
  INSERT INTO public.ergonomia_riscos (
    id, tenant_id, empresa_id, item_nr17_id, eixo, titulo, descricao, fonte, impactos_potenciais, severidade, probabilidade,
    medidas_existentes, medidas_recomendadas, departamento, setor, ativo, cargo, unidade, analise_id
  )
  SELECT public.demo_id('ergo_risco:' || x.k), v_t, v_e, public.demo_id('ergo_item:' || x.item), x.eixo::public.ergonomia_eixo, x.t, x.d, x.f,
         ARRAY(SELECT jsonb_array_elements_text(x.imp)), x.sev::public.risco_severidade, x.prob::public.risco_severidade,
         ARRAY(SELECT jsonb_array_elements_text(x.me)), ARRAY(SELECT jsonb_array_elements_text(x.mr)),
         x.dep, x.dep, true, x.cargo, 'Metalúrgica Exemplo', public.demo_id('ergo_analise:' || x.an)
  FROM (VALUES
    ('r01', '17.2.1', 'fisico', 'Levantamento manual de caixas de 25 kg', 'Movimentação manual repetida de caixas na armazenagem.', 'Análise do posto e histórico de afastamento',
      '["Lombalgia","Hérnia de disco","Afastamento do trabalho"]'::jsonb, 'critico', 'alto', '["Orientação verbal sobre postura"]'::jsonb, '["Carrinhos e mesas elevatórias","Treinamento de levantamento manual","Rodízio de tarefas"]'::jsonb, 'Logística', 'Auxiliar de Logística', '07'),
    ('r02', '17.3.2', 'fisico', 'Bancada fixa em altura inadequada', 'Altura 12 cm acima do ideal na montagem.', 'AEP da montagem',
      '["Dor em ombros e cervical","Tendinite"]'::jsonb, 'alto', 'alto', '["Plataformas improvisadas para alguns postos"]'::jsonb, '["Bancadas de altura regulável"]'::jsonb, 'Produção', 'Montador de Estruturas Metálicas', '03'),
    ('r03', '17.6.2', 'organizacional', 'Ausência de pausas formais na linha', 'Ciclo contínuo sem pausa estruturada.', 'Entrevistas com operadores',
      '["Fadiga","LER/DORT","Erros operacionais"]'::jsonb, 'alto', 'medio', '[]'::jsonb, '["Pausas de 10 min a cada 2 h"]'::jsonb, 'Produção', 'Montador de Estruturas Metálicas', '03'),
    ('r04', '17.3.1', 'fisico', 'Soldagem sobre cabeça e fora de posição', 'Pescoço em extensão e ombros elevados em soldagem de estruturas.', 'Observação direta',
      '["Cervicalgia","Síndrome do ombro doloroso"]'::jsonb, 'critico', 'alto', '["Alternância informal de tarefas"]'::jsonb, '["Posicionadores de peça","Rodízio soldagem/esmerilhamento"]'::jsonb, 'Produção', 'Soldador', '02'),
    ('r05', '17.4.1', 'fisico', 'Vibração mão-braço no esmerilhamento', 'Uso prolongado de esmerilhadeira sem luva antivibração.', 'Observação e entrevista',
      '["Síndrome do túnel do carpo","Doença de Raynaud ocupacional"]'::jsonb, 'alto', 'medio', '["Rodízio ocasional"]'::jsonb, '["Luvas antivibração","Ferramentas com menor vibração","Avaliação quantitativa"]'::jsonb, 'Produção', 'Soldador', '02'),
    ('r06', '17.3.1', 'fisico', 'Postura em pé prolongada na usinagem', 'Mais de 6 horas em pé sem apoio.', 'Análise do posto',
      '["Dor lombar","Varizes","Fadiga em membros inferiores"]'::jsonb, 'alto', 'alto', '[]'::jsonb, '["Tapetes antifadiga","Banco semi-sentado","Revezamento de tarefas"]'::jsonb, 'Produção', 'Operador de Usinagem CNC', '01'),
    ('r07', '17.1.2.2', 'cognitivo', 'Atenção contínua em fluxo misto de empilhadeiras', 'Alta demanda de atenção em área com pedestres.', 'Observação de turnos',
      '["Fadiga mental","Risco de acidente"]'::jsonb, 'medio', 'medio', '["Sinal sonoro e faixa de pedestres"]'::jsonb, '["Câmera de ré","Revezamento a cada 3 horas"]'::jsonb, 'Logística', 'Operador de Empilhadeira', '06'),
    ('r08', '17.5.2', 'fisico', 'Ruído de fundo na sala da qualidade', 'Ruído de usinagem transmitido à sala de inspeção.', 'Decibelímetro',
      '["Estresse","Queda de concentração"]'::jsonb, 'medio', 'alto', '[]'::jsonb, '["Tratamento acústico da sala"]'::jsonb, 'Administrativo', 'Analista da Qualidade', '09'),
    ('r09', '17.6.1', 'organizacional', 'Metas de produção com pouca margem de pausa', 'Meta por célula ajustada sem considerar pausas.', 'Entrevistas',
      '["Pressão excessiva","Fadiga"]'::jsonb, 'medio', 'medio', '["Reunião semanal de produção"]'::jsonb, '["Revisão das metas com participação dos operadores"]'::jsonb, 'Produção', 'Operador de Usinagem CNC', '01'),
    ('r10', '17.4.1', 'fisico', 'Ferramentas manuais desgastadas na manutenção', 'Chaves e extratores com folga exigindo esforço extra.', 'Inspeção de ferramentas',
      '["Tendinite","Lesão por esforço"]'::jsonb, 'medio', 'medio', '["Troca de ferramentas quebradas"]'::jsonb, '["Reposição programada","Inventário de ferramentas críticas"]'::jsonb, 'Manutenção', 'Mecânico de Manutenção', '04')
  ) AS x(k, item, eixo, t, d, f, imp, sev, prob, me, mr, dep, cargo, an)
  WHERE NOT EXISTS (SELECT 1 FROM public.ergonomia_riscos r WHERE r.id = public.demo_id('ergo_risco:' || x.k));

  -- Acoes de ergonomia (aba Acoes)
  INSERT INTO public.ergonomia_acoes (
    id, tenant_id, empresa_id, risco_id, item_nr17_id, titulo, descricao, tipo, prioridade, status, responsavel_id, responsavel_nome,
    prazo, data_inicio, data_conclusao, evidencia_conclusao, custo_estimado, custo_real
  )
  SELECT public.demo_id('ergo_acao:' || x.k), v_t, v_e, public.demo_id('ergo_risco:' || x.r), public.demo_id('ergo_item:' || x.item),
         x.t, x.d, x.tp, x.pr::public.acao_prioridade, x.s::public.acao_status, v_uid, v_nome, CURRENT_DATE + x.pz,
         CURRENT_DATE - x.ini, CASE WHEN x.s = 'concluida' THEN CURRENT_DATE - x.conc END,
         CASE WHEN x.s = 'concluida' THEN x.ev END, x.cu, CASE WHEN x.s = 'concluida' THEN x.cu END
  FROM (VALUES
    ('a01', 'r01', '17.2.1', 'Comprar carrinhos plataforma e mesa elevatória', 'Reduzir o levantamento manual de caixas de 25 kg.', 'corretiva', 'urgente', 'atrasada', -5, 120, 0, NULL, 7200),
    ('a02', 'r01', '17.2.3', 'Treinamento de levantamento manual seguro', 'Turma prática com instrutor externo.', 'preventiva', 'alta', 'pendente', 35, 5, 0, NULL, 3800),
    ('a03', 'r02', '17.3.2', 'Bancadas de altura regulável para a montagem', 'Substituir seis bancadas fixas.', 'corretiva', 'alta', 'em_andamento', 30, 60, 0, NULL, 14400),
    ('a04', 'r03', '17.6.2', 'Implantar pausas de 10 minutos na linha de montagem', 'Escala de pausas com alongamento orientado.', 'preventiva', 'media', 'concluida', -20, 55, 22, 'Registro de pausas e ata de reunião com a produção arquivados no módulo de Documentos.', 0),
    ('a05', 'r04', '17.3.1', 'Adquirir posicionadores de peça para solda', 'Reduzir a soldagem sobre cabeça.', 'corretiva', 'urgente', 'em_andamento', 25, 40, 0, NULL, 16800),
    ('a06', 'r05', '17.4.1', 'Fornecer luvas antivibração e revisar esmerilhadeiras', 'Trocar equipamentos com maior vibração.', 'preventiva', 'alta', 'pendente', 20, 10, 0, NULL, 2100),
    ('a07', 'r06', '17.3.1', 'Instalar tapetes antifadiga nos tornos', 'Oito tapetes nos postos em pé.', 'corretiva', 'media', 'atrasada', -8, 35, 0, NULL, 2600),
    ('a08', 'r07', '17.1.2.2', 'Instalar câmeras de ré nas empilhadeiras', 'Reduzir carga cognitiva nas manobras.', 'melhoria', 'media', 'pendente', 45, 5, 0, NULL, 5200),
    ('a09', 'r08', '17.5.2', 'Tratamento acústico da sala da qualidade', 'Painéis absorventes e vedação da porta.', 'corretiva', 'baixa', 'pendente', 60, 5, 0, NULL, 3400),
    ('a10', 'r09', '17.6.1', 'Revisar metas da usinagem com os operadores', 'Reunião participativa para recalcular metas considerando pausas.', 'melhoria', 'media', 'em_andamento', 15, 25, 0, NULL, 0),
    ('a11', 'r10', '17.4.1', 'Repor ferramentas manuais críticas da manutenção', 'Lista de 30 ferramentas com reposição programada.', 'corretiva', 'baixa', 'concluida', -50, 100, 52, 'Notas fiscais e conferência de inventário anexadas.', 4100),
    ('a12', 'r06', '17.3.1', 'Disponibilizar bancos semi-sentados nos tornos de ciclo longo', 'Alternativa de apoio durante ciclos acima de 8 minutos.', 'melhoria', 'baixa', 'cancelada', -2, 45, 0, NULL, 1800)
  ) AS x(k, r, item, t, d, tp, pr, s, pz, ini, conc, ev, cu)
  WHERE NOT EXISTS (SELECT 1 FROM public.ergonomia_acoes a WHERE a.id = public.demo_id('ergo_acao:' || x.k));

  -- Inventario GRO (riscos fisicos/ergonomicos) — o nivel de risco e calculado pelo gatilho do banco
  INSERT INTO public.gro_riscos (
    id, tenant_id, empresa_id, subtipo, fonte, titulo, descricao, perigo_identificado, setor, cargo, atividade, unidade,
    trabalhadores_expostos, grupos_expostos, probabilidade, severidade, medidas_existentes, medidas_recomendadas,
    base_normativa, acao_id, status_gro, ativo, necessita_reavaliacao, reavaliacao_motivo, created_at
  )
  SELECT public.demo_id('gro:' || x.k), v_t, v_e, 'fisico', x.f, x.t, x.d, x.pe, x.st, x.cargo, x.ativ, 'Metalúrgica Exemplo',
         x.nt, ARRAY[x.cargo], x.pb, x.sv, ARRAY(SELECT jsonb_array_elements_text(x.me)), ARRAY(SELECT jsonb_array_elements_text(x.mr)),
         ARRAY['NR-01','NR-17'] || x.nr, CASE WHEN x.ac IS NULL THEN NULL ELSE public.demo_id('plano_acao:' || x.ac) END,
         x.sg, true, COALESCE(x.re, false), x.rm, now() - (x.dd || ' days')::interval
  FROM (VALUES
    ('01', 'aep', 'Levantamento manual de caixas de 25 kg', 'Movimentação manual repetida de caixas na armazenagem e expedição.', 'Esforço físico intenso e levantamento de carga', 'Logística', 'Auxiliar de Logística', 'Separação e carregamento manual', 6, 'alta', 'grave', '["Orientação verbal sobre postura"]'::jsonb, '["Carrinhos e mesas elevatórias","Treinamento de levantamento manual","Rodízio de tarefas"]'::jsonb, ARRAY['NR-17.2']::text[], 's07', 'avaliado', true, 'Acidente por lombalgia registrado após a última avaliação', 80),
    ('02', 'aep', 'Soldagem sobre cabeça e em posturas forçadas', 'Pescoço em extensão e ombros elevados em soldagem fora de posição.', 'Postura inadequada de trabalho', 'Produção', 'Soldador', 'Soldagem MIG/MAG de estruturas', 9, 'alta', 'grave', '["Alternância informal de tarefas"]'::jsonb, '["Posicionadores de peça","Rodízio soldagem e esmerilhamento"]'::jsonb, ARRAY['NR-17.3']::text[], 'g01', 'avaliado', false, NULL, 75),
    ('03', 'aep', 'Bancada fixa em altura inadequada', 'Bancadas 12 cm acima da altura ideal exigem elevação dos ombros.', 'Mobiliário inadequado', 'Produção', 'Montador de Estruturas Metálicas', 'Montagem em bancada', 6, 'alta', 'moderada', '[]'::jsonb, '["Bancadas de altura regulável"]'::jsonb, ARRAY['NR-17.3']::text[], 'g01', 'controlado', false, NULL, 70),
    ('04', 'observacao', 'Movimentos repetitivos de membros superiores', 'Troca de ferramenta e carga de peças com flexão repetida de punho.', 'Repetitividade', 'Produção', 'Operador de Usinagem CNC', 'Setup e operação de torno CNC', 12, 'moderada', 'grave', '["Revezamento ocasional entre máquinas"]'::jsonb, '["Alternar setup e operação a cada 2 horas","Ferramentas com pegada ergonômica"]'::jsonb, ARRAY['NR-17.4']::text[], NULL, 'avaliado', false, NULL, 65),
    ('05', 'observacao', 'Postura em pé prolongada na usinagem', 'Mais de seis horas em pé sem apoio nem tapete antifadiga.', 'Postura em pé prolongada', 'Produção', 'Operador de Usinagem CNC', 'Operação de máquinas', 12, 'alta', 'moderada', '[]'::jsonb, '["Tapetes antifadiga","Banco semi-sentado"]'::jsonb, ARRAY['NR-17.3']::text[], 'g05', 'identificado', true, 'Prazo da ação vencido sem execução', 60),
    ('06', 'manual', 'Ruído contínuo acima de 85 dB(A) no esmerilhamento', 'Níveis de ruído acima do limite de ação em esmerilhamento e martelamento.', 'Ruído contínuo', 'Produção', 'Soldador', 'Esmerilhamento e acabamento', 9, 'alta', 'moderada', '["Protetor auricular plug fornecido e registrado em ficha"]'::jsonb, '["Enclausuramento parcial","Abafador adicional em tarefas críticas"]'::jsonb, ARRAY['NR-15']::text[], NULL, 'monitorado', false, NULL, 120),
    ('07', 'manual', 'Vibração mão-braço', 'Uso prolongado de esmerilhadeira sem luva antivibração.', 'Vibração em mãos e braços', 'Produção', 'Soldador', 'Esmerilhamento', 9, 'moderada', 'grave', '["Rodízio ocasional"]'::jsonb, '["Luvas antivibração","Ferramentas com menor vibração"]'::jsonb, ARRAY['NR-09']::text[], NULL, 'identificado', false, NULL, 55),
    ('08', 'ia', 'Vibração de corpo inteiro em empilhadeiras', 'Pisos irregulares do pátio transmitem vibração ao assento.', 'Vibração de corpo inteiro', 'Logística', 'Operador de Empilhadeira', 'Movimentação de paletes', 5, 'moderada', 'moderada', '[]'::jsonb, '["Recuperação do piso","Assento com amortecimento"]'::jsonb, ARRAY['NR-09']::text[], NULL, 'avaliado', false, NULL, 50),
    ('09', 'aep', 'Postura sentada prolongada com mobiliário não ajustável', 'Cadeiras antigas sem regulagem de altura e apoio lombar.', 'Mobiliário inadequado', 'Administrativo', 'Analista Financeiro', 'Trabalho com computador', 2, 'alta', 'leve', '["Pausas informais"]'::jsonb, '["Substituição das cadeiras","Pausas de alongamento"]'::jsonb, ARRAY['NR-17.3']::text[], 'g06', 'monitorado', false, NULL, 100),
    ('10', 'aep', 'Monitor abaixo da altura dos olhos', 'Notebook sem suporte elevado.', 'Postura de pescoço', 'Comercial', 'Vendedor Interno', 'Atendimento por sistema', 3, 'baixa', 'leve', '[]'::jsonb, '["Suporte para monitor e teclado externo"]'::jsonb, ARRAY['NR-17.4']::text[], 'g06', 'revisado', false, NULL, 90),
    ('11', 'manual', 'Escala 6x2 com turnos alternados e fadiga', 'Alternância de turnos com recuperação insuficiente.', 'Organização do trabalho', 'Produção', 'Operador de Usinagem CNC', 'Operação em dois turnos', 12, 'moderada', 'moderada', '["Intervalo de 11 horas entre jornadas respeitado"]'::jsonb, '["Estudo de escala com participação dos trabalhadores"]'::jsonb, ARRAY['NR-17.6']::text[], NULL, 'avaliado', false, NULL, 45),
    ('12', 'observacao', 'Pausas insuficientes na linha de montagem', 'Ciclo contínuo sem pausa estruturada.', 'Organização do trabalho', 'Produção', 'Montador de Estruturas Metálicas', 'Montagem em linha', 6, 'alta', 'moderada', '[]'::jsonb, '["Pausas de 10 minutos a cada 2 horas"]'::jsonb, ARRAY['NR-17.6']::text[], 'g02', 'controlado', false, NULL, 40),
    ('13', 'manual', 'Ferramentas manuais desgastadas', 'Chaves e extratores com folga exigindo esforço extra.', 'Ferramentas inadequadas', 'Manutenção', 'Mecânico de Manutenção', 'Manutenção mecânica', 6, 'moderada', 'moderada', '["Troca de ferramentas quebradas"]'::jsonb, '["Reposição programada","Inventário de ferramentas críticas"]'::jsonb, ARRAY['NR-17.4']::text[], NULL, 'controlado', false, NULL, 60),
    ('14', 'ia', 'Iluminação insuficiente em corredores de armazenagem', 'Luminárias queimadas reduzem a iluminância no corredor C.', 'Iluminação inadequada', 'Logística', 'Auxiliar de Logística', 'Separação de pedidos', 6, 'moderada', 'leve', '[]'::jsonb, '["Reposição de luminárias","Rota de inspeção mensal"]'::jsonb, ARRAY['NR-17.5']::text[], NULL, 'identificado', false, NULL, 12),
    ('15', 'aep', 'Trabalho com membros superiores elevados em eletrocalhas', 'Cabeamento em eletrocalhas altas exige braços elevados por longos períodos.', 'Postura inadequada de trabalho', 'Manutenção', 'Eletricista de Manutenção', 'Cabeamento em altura', 4, 'baixa', 'moderada', '["Alternância de tarefas"]'::jsonb, '["Plataforma elevatória"]'::jsonb, ARRAY['NR-35']::text[], NULL, 'monitorado', false, NULL, 85),
    ('16', 'manual', 'Pressão por metas de produção', 'Metas por célula com margem reduzida para pausas e recuperação.', 'Organização do trabalho', 'Produção', 'Líder de Produção', 'Gestão de célula', 14, 'moderada', 'grave', '["Reunião semanal de produção"]'::jsonb, '["Revisão das metas com participação dos operadores"]'::jsonb, ARRAY['NR-17.6']::text[], NULL, 'avaliado', true, 'Mudança de metas anunciada para o próximo trimestre', 30)
  ) AS x(k, f, t, d, pe, st, cargo, ativ, nt, pb, sv, me, mr, nr, ac, sg, re, rm, dd)
  WHERE NOT EXISTS (SELECT 1 FROM public.gro_riscos g WHERE g.id = public.demo_id('gro:' || x.k));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Ergonomia (riscos, acoes e inventario GRO) nao concluida: % (%)', SQLERRM, SQLSTATE;
END $ergo2$;

-- ---------------------------------------------------------------------------
-- Conferencia final (uma linha)
-- ---------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM public.epi_tipos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epi_tipos,
  (SELECT count(*) FROM public.epis WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epi_lotes,
  (SELECT count(*) FROM public.epi_entregas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epi_entregas,
  (SELECT count(*) FROM public.epi_movimentacoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epi_movimentacoes,
  (SELECT count(*) FROM public.funcao_epis WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS epi_matriz,
  (SELECT count(*) FROM public.eventos_sst WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ocorrencias_sst,
  (SELECT count(*) FROM public.desvios_seguranca WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS desvios,
  (SELECT count(*) FROM public.plano_acoes WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001'
      AND origem_modulo IN ('sst', 'epi', 'ergonomia')) AS acoes_sst_epi_ergo,
  (SELECT count(*) FROM public.ergonomia_itens_nr17 WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ergo_itens,
  (SELECT count(*) FROM public.ergonomia_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') AS ergo_analises,
  (SELECT count(*) FROM public.gro_riscos WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001' AND subtipo = 'fisico') AS gro_riscos_fisicos,
  CASE WHEN (SELECT count(*) FROM public.epi_entregas WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 150
        AND (SELECT count(*) FROM public.eventos_sst WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 25
        AND (SELECT count(*) FROM public.ergonomia_analises WHERE tenant_id = 'd3e00000-0000-4000-8000-000000000001') >= 12
       THEN 'OK' ELSE 'CONFERIR' END AS situacao;
