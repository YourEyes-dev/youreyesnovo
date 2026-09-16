-- =====================================================================
-- PROGRAMA DE PARCEIROS · POLÍTICA v2 · SCRIPT DE ENTREGA
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK. Requer Ondas 1-3 e o
-- Contrato de Parceria (v1) aplicados.
--
-- O que faz: trilhas Indicador/Representante/Operador com matriz de níveis
-- Foco/Visão/Diamante pré-preenchida (6/8/10, 12/15/18, 20/25/30; setup
-- 20/25/30, 60/70/80, 100), tabela de configuração do programa (ciclo 24
-- meses, setup 30/40/30, retenção 90 dias, clawback, inadimplência, não
-- aliciamento 24 meses...), marcos do cliente (setup, mensalidades,
-- homologação), motor v2 e Contrato v2 gerado por parceiro na tela de
-- Contratos. ALTERA linhas de parceiro_niveis e parceiro_eventos_remuneracao:
-- por isso guarda backup_parceiro_niveis_20260904 e
-- backup_parceiro_eventos_20260904 antes (reversão comentada no rodapé da
-- migration). Idempotente.
-- Corresponde à migration 20260904160000_parceiros_politica_v2.sql.
-- =====================================================================

-- =====================================================================
-- PROGRAMA DE PARCEIROS · POLÍTICA v2 (documento "Programa de Parceiros
-- YourEyes", jul/2026, e apresentação aos parceiros)
--
-- O que muda em relação às Ondas 1-3:
--  * TRILHAS: Indicador, Representante e Operador (o "tipo" vira perfil:
--    clínica, contabilidade, consultoria...). A trilha define a matriz.
--  * NÍVEIS por trilha: Foco (até R$ 4 mil), Visão (4-12 mil), Diamante
--    (> 12 mil) — Indicador 6/8/10 %, Representante 12/15/18 %, Operador
--    20/25/30 %. Participação no setup: 20/25/30, 60/70/80, 100 %.
--  * BASE: valor efetivamente recebido do cliente (assinatura paga), líquido
--    de impostos sobre a venda (parâmetro), nunca o valor de tabela.
--  * CICLOS de 24 meses contados do go-live homologado, renovação
--    automática com bônus de 2×; compromisso limitado ao ciclo em curso.
--  * SETUP pago pelo cliente e repassado em 3 parcelas (30/40/30) contra
--    1ª mensalidade compensada, go-live homologado e 3ª mensalidade; bônus
--    de retenção 90 dias (+15 %); retenção de qualidade do Operador (20 %
--    dos 3 primeiros meses); clawback 50 % entre o 4º e o 12º mês.
--  * TODOS os parâmetros em tabela (parceiro_programa_config, parceiro_niveis,
--    parceiro_eventos_remuneracao) — pré-preenchidos, editáveis no SuperAdmin.
--  * CONTRATO v2 gerado por parceiro no aceite e salvo na tela de Contratos
--    do SuperAdmin (contratos_aceite / contratos_assinaturas).
--  * TITULARIDADE explícita: a carteira é da YourEyes; o parceiro tem o
--    registro de originação. Não aliciamento/não concorrência por 24 meses.
-- Guarda as linhas alteradas de parceiro_niveis em backup antes de mexer.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 0) Backup do que será alterado (níveis e eventos) — reversão no rodapé
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.backup_parceiro_niveis_20260904 AS SELECT * FROM public.parceiro_niveis;
CREATE TABLE IF NOT EXISTS public.backup_parceiro_eventos_20260904 AS SELECT * FROM public.parceiro_eventos_remuneracao;

-- ---------------------------------------------------------------------
-- 1) Configuração do programa (chave/valor, pré-preenchida, editável)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parceiro_programa_config (
  chave       text PRIMARY KEY,
  valor       text NOT NULL,
  tipo        text NOT NULL DEFAULT 'numero' CHECK (tipo IN ('numero','percentual','centavos','dias','meses','texto','booleano')),
  grupo       text NOT NULL,
  rotulo      text NOT NULL,
  descricao   text,
  ordem       int NOT NULL DEFAULT 0,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_por uuid
);
ALTER TABLE public.parceiro_programa_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS parceiro_programa_config_leitura ON public.parceiro_programa_config;
CREATE POLICY parceiro_programa_config_leitura ON public.parceiro_programa_config FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS parceiro_programa_config_superadmin ON public.parceiro_programa_config;
CREATE POLICY parceiro_programa_config_superadmin ON public.parceiro_programa_config FOR ALL TO authenticated
  USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));
GRANT SELECT ON public.parceiro_programa_config TO anon, authenticated;
GRANT ALL ON public.parceiro_programa_config TO service_role;

INSERT INTO public.parceiro_programa_config (chave, valor, tipo, grupo, rotulo, descricao, ordem) VALUES
 ('ciclo_meses',               '24',   'meses',      'ciclo',   'Duração do ciclo por cliente', 'Contado do go-live homologado. Renova automaticamente por igual período enquanto o parceiro estiver ativo.', 1),
 ('bonus_renovacao_mult',      '2',    'numero',     'ciclo',   'Bônus de renovação (× comissão mensal)', 'Pago a cada renovação de ciclo, com o parceiro ativo.', 2),
 ('nivel_protecao_meses',      '12',   'meses',      'niveis',  'Nível não cai por (meses)', 'Uma vez conquistado, o nível só é revisado na data-base anual.', 1),
 ('impostos_venda_pct',        '0',    'percentual', 'base',    'Impostos sobre a venda descontados da base (%)', 'A comissão incide sobre o valor recebido líquido de impostos e descontos. Defina o percentual com o contador.', 1),
 ('desconto_autonomia_pct',    '10',   'percentual', 'base',    'Desconto que o parceiro pode conceder sem aprovação (%)', 'Todo desconto reduz proporcionalmente a base de comissão do próprio parceiro.', 2),
 ('fechamento_dia',            '25',   'dias',       'pagamento','Dia do fechamento', NULL, 1),
 ('pagamento_dia',             '10',   'dias',       'pagamento','Pagamento até o dia', 'Do mês seguinte, mediante nota fiscal ou recibo.', 2),
 ('pagamento_minimo_cents',    '10000','centavos',   'pagamento','Valor mínimo para pagar no mês', 'Abaixo disso acumula para o mês seguinte.', 3),
 ('inadimplencia_dias',        '60',   'dias',       'pagamento','Atraso do cliente que suspende a comissão (dias)', 'A regularização libera os valores retidos. Não interrompe o ciclo.', 4),
 ('setup_parcela1_pct',        '30',   'percentual', 'setup',   'Setup: 1ª parcela (%) — 1ª mensalidade compensada', 'Nenhuma parcela é liberada antes da 1ª mensalidade compensada.', 1),
 ('setup_parcela2_pct',        '40',   'percentual', 'setup',   'Setup: 2ª parcela (%) — go-live homologado', NULL, 2),
 ('setup_parcela3_pct',        '30',   'percentual', 'setup',   'Setup: 3ª parcela (%) — 3ª mensalidade com a conta ativa', NULL, 3),
 ('setup_prazo_liberacao_dias','10',   'dias',       'setup',   'Prazo para liberar cada parcela após o marco (dias)', NULL, 4),
 ('bonus_retencao_90d_pct',    '15',   'percentual', 'bonus',   'Bônus de retenção 90 dias (% do setup)', 'Cliente ativo, adimplente e com uso no 90º dia após o go-live.', 1),
 ('fast_start_cents',          '200000','centavos',  'bonus',   'Fast Start (R$)', '3 empresas ativadas nos primeiros 90 dias de credenciamento.', 2),
 ('fast_start_ativacoes',      '3',    'numero',     'bonus',   'Fast Start: ativações necessárias', NULL, 3),
 ('fast_start_dias',           '90',   'dias',       'bonus',   'Fast Start: janela (dias)', NULL, 4),
 ('bonus_volume_pct',          '25',   'percentual', 'bonus',   'Bônus de volume (% sobre os setups do mês)', '3 ou mais ativações no mesmo mês. Incide sobre o total.', 5),
 ('bonus_volume_ativacoes',    '3',    'numero',     'bonus',   'Bônus de volume: ativações no mês', NULL, 6),
 ('bonus_velocidade_pct',      '20',   'percentual', 'bonus',   'Bônus de velocidade (% sobre o setup do cliente)', 'Go-live homologado em até N dias da assinatura.', 7),
 ('bonus_velocidade_dias',     '15',   'dias',       'bonus',   'Bônus de velocidade: prazo (dias)', NULL, 8),
 ('decimo_terceiro_churn_max_pct','8', 'percentual', 'bonus',   '13º da carteira: churn máximo no ano (%)', '1× a média mensal de comissão do ano. Lançado como ajuste no fechamento de dezembro.', 9),
 ('retencao_qualidade_pct',    '20',   'percentual', 'qualidade','Operador: retenção de qualidade (% da comissão)', 'Dos 3 primeiros meses de cada cliente novo; liberada após a 3ª mensalidade com a conta ativa.', 1),
 ('retencao_qualidade_meses',  '3',    'meses',      'qualidade','Operador: meses com retenção', NULL, 2),
 ('operador_setup_max_antes_golive_pct','50','percentual','qualidade','Operador: máximo do setup próprio faturável antes do go-live (%)', 'Cláusula de espelhamento no contrato do Operador com o cliente.', 3),
 ('golive_colaboradores_min_pct','80', 'percentual', 'qualidade','Go-live homologado: mínimo de colaboradores cadastrados (%)', 'Mais um ciclo operacional completo, usuários-chave treinados, termo de aceite assinado e nenhum chamado crítico há mais de 5 dias.', 4),
 ('clawback_pct',              '50',   'percentual', 'clawback','Clawback do setup (%)', 'Cancelamento entre o 4º e o 12º mês devolve este percentual do setup recebido. Falha comprovada do produto não gera devolução.', 1),
 ('clawback_mes_inicio',       '4',    'meses',      'clawback','Clawback: a partir do mês', NULL, 2),
 ('clawback_mes_fim',          '12',   'meses',      'clawback','Clawback: até o mês', NULL, 3),
 ('registro_oportunidade_dias','90',   'dias',       'atribuicao','Proteção do registro de oportunidade (dias)', 'Renovável com evidência de avanço. Prevalece o registro mais antigo.', 1),
 ('atribuicao_link_dias',      '90',   'dias',       'atribuicao','Janela de atribuição do link (dias)', 'Do primeiro clique ao cadastro/contratação.', 2),
 ('meta_atividade_semestre',   '1',    'numero',     'atribuicao','Ativações mínimas por semestre para seguir ativo', 'Mantém o status ativo e o direito à renovação automática dos ciclos.', 3),
 ('teto_exposicao_pct',        '30',   'percentual', 'governanca','Teto de exposição do canal (% do MRR do canal)', 'Acima disso a tabela é revista só para contratos novos.', 1),
 ('rescisao_aviso_dias',       '90',   'dias',       'governanca','Aviso prévio de rescisão (dias)', NULL, 2),
 ('nao_aliciamento_meses',     '24',   'meses',      'governanca','Não aliciamento / não concorrência após o término (meses)', NULL, 3),
 ('confidencialidade_anos',    '5',    'numero',     'governanca','Sigilo após o término (anos)', 'Segredos de negócio: enquanto mantiverem essa natureza.', 4),
 ('premio_liquidez_mult_max',  '6',    'numero',     'governanca','Prêmio de liquidez: múltiplo máximo da média mensal', 'A DECIDIR com o jurídico antes da 1ª assinatura, junto com o teto global.', 5),
 ('premio_liquidez_teto_pct',  '0',    'percentual', 'governanca','Prêmio de liquidez: teto global (% da transação)', '0 = ainda não definido; a cláusula do contrato remete a este parâmetro.', 6),
 ('premio_liquidez_permanencia_meses','12','meses',  'governanca','Prêmio de liquidez: permanência após o evento (meses)', NULL, 7),
 ('master_override_pct',       '5',    'percentual', 'master',  'Master Regional: override sobre o MRR líquido dos sub-parceiros (%)', 'Pago pela YourEyes, sem reduzir a comissão do sub-parceiro.', 1),
 ('master_diamante_meses_min', '6',    'meses',      'master',  'Master Regional: meses mínimos em Diamante', NULL, 2),
 ('master_churn_max_pct',      '8',    'percentual', 'master',  'Master Regional: churn máximo da carteira (%)', NULL, 3),
 ('diamante_comarketing_pct',  '3',    'percentual', 'niveis',  'Diamante: fundo de co-marketing (% do MRR gerado)', NULL, 2)
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.parceiro_cfg(p_chave text, p_default numeric DEFAULT 0)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public
AS $parceiro_cfg$
  SELECT coalesce((SELECT nullif(btrim(valor),'')::numeric FROM public.parceiro_programa_config WHERE chave = p_chave), p_default)
$parceiro_cfg$;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_config_salvar(_itens jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_parceiro_config_salvar$
DECLARE r jsonb; v_n int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(_itens,'[]'::jsonb)) LOOP
    UPDATE public.parceiro_programa_config SET valor = r->>'valor', atualizado_em = now(), atualizado_por = auth.uid()
    WHERE chave = r->>'chave';
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $superadmin_parceiro_config_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_config_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 2) Trilhas e matriz de níveis (valores do anexo, editáveis)
-- ---------------------------------------------------------------------
ALTER TABLE public.parceiro_niveis ADD COLUMN IF NOT EXISTS setup_participacao_pct numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE public.parceiro_niveis ADD COLUMN IF NOT EXISTS mrr_maximo_cents bigint;
ALTER TABLE public.parceiro_niveis ADD COLUMN IF NOT EXISTS beneficios text;

-- Operador: o antigo "Visão (ordem 1, R$ 0)" vira Foco; entram Visão e Diamante nas faixas do anexo.
UPDATE public.parceiro_niveis SET nome = 'Foco', ordem = 1, mrr_minimo_cents = 0, mrr_maximo_cents = 400000,
       percentual_link = 20, percentual_casa = 20, setup_participacao_pct = 100,
       beneficios = 'Percentual base. Certificação nível 1, ambiente de demonstração, kit comercial e gestor de canal compartilhado.'
WHERE trilha = 'operador' AND nome = 'Visão' AND ordem = 1 AND mrr_minimo_cents = 0
  AND NOT EXISTS (SELECT 1 FROM public.parceiro_niveis WHERE trilha = 'operador' AND nome = 'Foco');

INSERT INTO public.parceiro_niveis (trilha, nome, ordem, mrr_minimo_cents, mrr_maximo_cents, percentual_link, percentual_casa, setup_participacao_pct, bonus_renovacao_multiplicador, beneficios) VALUES
 ('indicador',    'Foco',     1,       0,  400000,  6,  6, 20, 2, 'Percentual base. Certificação nível 1, kit comercial e gestor de canal compartilhado.'),
 ('indicador',    'Visão',    2,  400100, 1200000,  8,  8, 25, 2, 'Certificação nível 2, prioridade em leads da sua região, co-branding e gestor de canal nomeado.'),
 ('indicador',    'Diamante', 3, 1200100,    NULL, 10, 10, 30, 2, 'Fundo de co-marketing (3% do MRR), convenção anual, assento no comitê de produto e condições especiais.'),
 ('representante','Foco',     1,       0,  400000, 12, 12, 60, 2, 'Percentual base. Certificação nível 1, ambiente de demonstração, kit comercial e gestor de canal compartilhado.'),
 ('representante','Visão',    2,  400100, 1200000, 15, 15, 70, 2, 'Certificação nível 2, prioridade em leads da sua região, co-branding e gestor de canal nomeado.'),
 ('representante','Diamante', 3, 1200100,    NULL, 18, 18, 80, 2, 'Fundo de co-marketing (3% do MRR), convenção anual, assento no comitê de produto, sub-parceiros e condições especiais.'),
 ('operador',     'Foco',     1,       0,  400000, 20, 20, 100, 2, 'Percentual base. Certificação nível 1, ambiente de demonstração, kit comercial e gestor de canal compartilhado.'),
 ('operador',     'Visão',    2,  400100, 1200000, 25, 25, 100, 2, 'Certificação nível 2, prioridade em leads da sua região, co-branding e gestor de canal nomeado.'),
 ('operador',     'Diamante', 3, 1200100,    NULL, 30, 30, 100, 2, 'Fundo de co-marketing (3% do MRR), convenção anual, assento no comitê de produto, sub-parceiros e condições especiais.')
ON CONFLICT (trilha, nome) DO UPDATE SET
  ordem = EXCLUDED.ordem, mrr_minimo_cents = EXCLUDED.mrr_minimo_cents, mrr_maximo_cents = EXCLUDED.mrr_maximo_cents,
  percentual_link = EXCLUDED.percentual_link, percentual_casa = EXCLUDED.percentual_casa,
  setup_participacao_pct = EXCLUDED.setup_participacao_pct, beneficios = EXCLUDED.beneficios;

-- Parceiros: trilha passa a ser uma das três; perfil (tipo) sugere a trilha.
CREATE OR REPLACE FUNCTION public.parceiro_trilha_padrao(p_tipo text)
RETURNS text LANGUAGE sql IMMUTABLE
AS $parceiro_trilha_padrao$
  SELECT CASE p_tipo WHEN 'indicador' THEN 'indicador' WHEN 'representante' THEN 'representante' ELSE 'operador' END
$parceiro_trilha_padrao$;

ALTER TABLE public.parceiros DROP CONSTRAINT IF EXISTS parceiros_trilha_check;
-- Sem default: o trigger deriva a trilha do perfil quando ela não vem informada.
ALTER TABLE public.parceiros ALTER COLUMN trilha DROP NOT NULL;
ALTER TABLE public.parceiros ALTER COLUMN trilha DROP DEFAULT;
UPDATE public.parceiros SET trilha = public.parceiro_trilha_padrao(tipo_parceiro)
WHERE trilha NOT IN ('indicador','representante','operador');
ALTER TABLE public.parceiros ADD CONSTRAINT parceiros_trilha_check CHECK (trilha IS NULL OR trilha IN ('indicador','representante','operador'));
ALTER TABLE public.parceiros
  ADD COLUMN IF NOT EXISTS nivel_conquistado_em date,
  ADD COLUMN IF NOT EXISTS certificacao_nivel int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS master_regional boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS master_parceiro_id uuid REFERENCES public.parceiros(id) ON DELETE SET NULL;
-- Nível inicial coerente com a trilha (quem estava com nível de outra trilha)
UPDATE public.parceiros p SET nivel_id = (SELECT n.id FROM public.parceiro_niveis n WHERE n.trilha = p.trilha AND n.ativo ORDER BY n.ordem LIMIT 1)
WHERE nivel_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.parceiro_niveis n WHERE n.id = p.nivel_id AND n.trilha = p.trilha);

-- Trigger de inserção: trilha pelo perfil quando não informada; nível da trilha.
CREATE OR REPLACE FUNCTION public.parceiros_antes_inserir()
RETURNS trigger LANGUAGE plpgsql SET search_path = public
AS $parceiros_antes_inserir$
BEGIN
  IF NEW.codigo IS NULL OR btrim(NEW.codigo) = '' THEN
    NEW.codigo := public.parceiro_gerar_codigo(NEW.nome);
  ELSE
    NEW.codigo := upper(regexp_replace(NEW.codigo, '[^A-Za-z0-9-]', '', 'g'));
  END IF;
  IF NEW.trilha IS NULL OR NEW.trilha NOT IN ('indicador','representante','operador') THEN
    NEW.trilha := public.parceiro_trilha_padrao(NEW.tipo_parceiro);
  END IF;
  -- Decisão 03/09/2026: indicador entra sozinho; os demais esperam aprovação.
  IF NEW.tipo_parceiro = 'indicador' AND NEW.trilha = 'indicador' THEN
    NEW.aprovacao := 'automatica';
    IF NEW.status = 'pendente' THEN NEW.status := 'ativo'; NEW.aprovado_em := now(); END IF;
  ELSE
    NEW.aprovacao := 'manual';
  END IF;
  IF NEW.nivel_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.parceiro_niveis n WHERE n.id = NEW.nivel_id AND n.trilha = NEW.trilha) THEN
    SELECT id INTO NEW.nivel_id FROM public.parceiro_niveis WHERE trilha = NEW.trilha AND ativo ORDER BY ordem LIMIT 1;
  END IF;
  NEW.nivel_conquistado_em := coalesce(NEW.nivel_conquistado_em, CURRENT_DATE);
  RETURN NEW;
END $parceiros_antes_inserir$;

-- Eventos por trilha: bônus (setup em parcelas fica na config). Re-semeia.
ALTER TABLE public.parceiro_eventos_remuneracao DROP CONSTRAINT IF EXISTS parceiro_eventos_remuneracao_evento_check;
ALTER TABLE public.parceiro_eventos_remuneracao ADD CONSTRAINT parceiro_eventos_remuneracao_evento_check
  CHECK (evento IN ('setup_concluido','go_live','renovacao','bonus_retencao_90d','fast_start','bonus_volume','bonus_velocidade','decimo_terceiro'));
ALTER TABLE public.parceiro_eventos_remuneracao DROP CONSTRAINT IF EXISTS parceiro_eventos_remuneracao_tipo_parceiro_check;
ALTER TABLE public.parceiro_eventos_remuneracao ADD COLUMN IF NOT EXISTS percentual_setup numeric(5,2) NOT NULL DEFAULT 0;
-- linhas antigas (por tipo) deixam de ser lidas pelo motor v2; ficam no backup
DELETE FROM public.parceiro_eventos_remuneracao WHERE tipo_parceiro NOT IN ('indicador','representante','operador');
INSERT INTO public.parceiro_eventos_remuneracao (trilha, tipo_parceiro, evento, valor_fixo_cents, percentual_primeira_mensalidade, percentual_setup, ativo)
SELECT t, t, e.evento, e.fixo, 0, e.pct, true
FROM unnest(ARRAY['indicador','representante','operador']) t
CROSS JOIN (VALUES ('bonus_retencao_90d', 0, 15.00), ('fast_start', 200000, 0), ('bonus_volume', 0, 25.00), ('bonus_velocidade', 0, 20.00)) AS e(evento, fixo, pct)
ON CONFLICT (trilha, tipo_parceiro, evento) DO NOTHING;

CREATE OR REPLACE FUNCTION public.superadmin_parceiro_eventos_salvar(_itens jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_parceiro_eventos_salvar$
DECLARE r jsonb; v_n int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(_itens,'[]'::jsonb)) LOOP
    INSERT INTO public.parceiro_eventos_remuneracao (trilha, tipo_parceiro, evento, valor_fixo_cents, percentual_primeira_mensalidade, percentual_setup, ativo)
    VALUES (coalesce(r->>'trilha','operador'), coalesce(r->>'tipo_parceiro', r->>'trilha', 'operador'), r->>'evento',
            coalesce((r->>'valor_fixo_cents')::bigint, 0), coalesce((r->>'percentual_primeira_mensalidade')::numeric, 0),
            coalesce((r->>'percentual_setup')::numeric, 0), coalesce((r->>'ativo')::boolean, true))
    ON CONFLICT (trilha, tipo_parceiro, evento) DO UPDATE SET
      valor_fixo_cents = EXCLUDED.valor_fixo_cents, percentual_primeira_mensalidade = EXCLUDED.percentual_primeira_mensalidade,
      percentual_setup = EXCLUDED.percentual_setup, ativo = EXCLUDED.ativo;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $superadmin_parceiro_eventos_salvar$;

-- Salvar níveis passa a aceitar participação no setup, teto da faixa e benefícios
CREATE OR REPLACE FUNCTION public.superadmin_parceiro_niveis_salvar(_itens jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_parceiro_niveis_salvar$
DECLARE r jsonb; v_n int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(_itens,'[]'::jsonb)) LOOP
    INSERT INTO public.parceiro_niveis
      (trilha, nome, ordem, mrr_minimo_cents, mrr_maximo_cents, percentual_link, percentual_casa, setup_participacao_pct, bonus_renovacao_multiplicador, beneficios, ativo)
    VALUES (coalesce(r->>'trilha','operador'), r->>'nome', coalesce((r->>'ordem')::int, 1),
            coalesce((r->>'mrr_minimo_cents')::bigint, 0), nullif(r->>'mrr_maximo_cents','')::bigint,
            coalesce((r->>'percentual_link')::numeric, 0), coalesce((r->>'percentual_casa')::numeric, (r->>'percentual_link')::numeric, 0),
            coalesce((r->>'setup_participacao_pct')::numeric, 0),
            coalesce((r->>'bonus_renovacao_multiplicador')::numeric, 2), nullif(r->>'beneficios',''), coalesce((r->>'ativo')::boolean, true))
    ON CONFLICT (trilha, nome) DO UPDATE SET
      ordem = EXCLUDED.ordem, mrr_minimo_cents = EXCLUDED.mrr_minimo_cents, mrr_maximo_cents = EXCLUDED.mrr_maximo_cents,
      percentual_link = EXCLUDED.percentual_link, percentual_casa = EXCLUDED.percentual_casa,
      setup_participacao_pct = EXCLUDED.setup_participacao_pct,
      bonus_renovacao_multiplicador = EXCLUDED.bonus_renovacao_multiplicador, beneficios = EXCLUDED.beneficios, ativo = EXCLUDED.ativo;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $superadmin_parceiro_niveis_salvar$;

-- ---------------------------------------------------------------------
-- 3) Marcos do cliente para o motor (setup, mensalidades, homologação)
-- ---------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS setup_valor_cents bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS primeira_mensalidade_compensada_em date,
  ADD COLUMN IF NOT EXISTS terceira_mensalidade_compensada_em date,
  ADD COLUMN IF NOT EXISTS go_live_homologado_em date,
  ADD COLUMN IF NOT EXISTS contrato_assinado_em date,
  ADD COLUMN IF NOT EXISTS cancelado_em date,
  ADD COLUMN IF NOT EXISTS desconto_pct numeric(5,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.superadmin_tenant_programa_salvar(_tenant_id uuid, _dados jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_tenant_programa_salvar$
DECLARE v_ciclo int := public.parceiro_cfg('ciclo_meses', 24)::int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.subscriptions (tenant_id, plan_id)
  SELECT _tenant_id, (SELECT id FROM public.plans WHERE code = 'tester')
  WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE tenant_id = _tenant_id);
  UPDATE public.subscriptions SET
    setup_valor_cents = coalesce((_dados->>'setup_valor_cents')::bigint, setup_valor_cents),
    desconto_pct = coalesce((_dados->>'desconto_pct')::numeric, desconto_pct),
    contrato_assinado_em = CASE WHEN _dados ? 'contrato_assinado_em' THEN nullif(_dados->>'contrato_assinado_em','')::date ELSE contrato_assinado_em END,
    primeira_mensalidade_compensada_em = CASE WHEN _dados ? 'primeira_mensalidade_compensada_em' THEN nullif(_dados->>'primeira_mensalidade_compensada_em','')::date ELSE primeira_mensalidade_compensada_em END,
    terceira_mensalidade_compensada_em = CASE WHEN _dados ? 'terceira_mensalidade_compensada_em' THEN nullif(_dados->>'terceira_mensalidade_compensada_em','')::date ELSE terceira_mensalidade_compensada_em END,
    go_live_homologado_em = CASE WHEN _dados ? 'go_live_homologado_em' THEN nullif(_dados->>'go_live_homologado_em','')::date ELSE go_live_homologado_em END,
    cancelado_em = CASE WHEN _dados ? 'cancelado_em' THEN nullif(_dados->>'cancelado_em','')::date ELSE cancelado_em END
  WHERE tenant_id = _tenant_id;
  -- Ciclo nasce no go-live homologado (política 5.2), se ainda não existir
  UPDATE public.subscriptions SET ciclo_meses = coalesce(ciclo_meses, v_ciclo),
    ciclo_inicio = coalesce(ciclo_inicio, go_live_homologado_em),
    ciclo_fim = coalesce(ciclo_fim, go_live_homologado_em + (coalesce(ciclo_meses, v_ciclo) || ' months')::interval)
  WHERE tenant_id = _tenant_id AND go_live_homologado_em IS NOT NULL;
END $superadmin_tenant_programa_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_tenant_programa_salvar(uuid, jsonb) TO authenticated;

-- Base de comissão: valor efetivamente recebido (assinatura paga) ou, na
-- falta, tabela com desconto concedido; sempre líquido de impostos (config).
CREATE OR REPLACE FUNCTION public.parceiro_base_tenant(p_tenant_id uuid)
RETURNS bigint LANGUAGE sql STABLE SET search_path = public
AS $parceiro_base_tenant$
  SELECT round(
    coalesce(
      (SELECT round(a.preco_mensal * 100)::bigint FROM public.assinaturas a
        WHERE a.tenant_id = p_tenant_id AND a.status IN ('approved','paid','authorized','active') ORDER BY a.approved_at DESC NULLS LAST LIMIT 1),
      round(public.parceiro_mrr_tenant(p_tenant_id) * (1 - coalesce((SELECT desconto_pct FROM public.subscriptions WHERE tenant_id = p_tenant_id), 0) / 100))::bigint
    ) * (1 - public.parceiro_cfg('impostos_venda_pct', 0) / 100))::bigint
$parceiro_base_tenant$;

CREATE OR REPLACE FUNCTION public.superadmin_tenant_programa(_tenant_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $superadmin_tenant_programa$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE (
    SELECT to_jsonb(s) - 'id' FROM (
      SELECT s.setup_valor_cents, s.desconto_pct, s.contrato_assinado_em, s.primeira_mensalidade_compensada_em,
             s.terceira_mensalidade_compensada_em, s.go_live_homologado_em, s.cancelado_em, s.ciclo_meses, s.ciclo_inicio, s.ciclo_fim,
             s.status, s.payment_confirmed, public.parceiro_estagio_tenant(_tenant_id) AS estagio, public.parceiro_mrr_tenant(_tenant_id) AS mrr_tabela_cents,
             public.parceiro_base_tenant(_tenant_id) AS base_cents
      FROM public.subscriptions s WHERE s.tenant_id = _tenant_id) s) END
$superadmin_tenant_programa$;

GRANT EXECUTE ON FUNCTION public.superadmin_tenant_programa(uuid) TO authenticated;

-- Estágio: go-live passa a ser a homologação registrada (ou onboarding concluído como proxy)
CREATE OR REPLACE FUNCTION public.parceiro_estagio_tenant(p_tenant_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path = public
AS $parceiro_estagio_tenant$
  SELECT public.parceiro_estagio_calc(
    true, t.ativo,
    (SELECT s.status FROM public.subscriptions s WHERE s.tenant_id = t.id),
    coalesce((SELECT s.contrato_assinado_em IS NOT NULL FROM public.subscriptions s WHERE s.tenant_id = t.id), false)
      OR EXISTS (SELECT 1 FROM public.programa_validador_clientes c JOIN public.programa_validador_contratos k ON k.cliente_id = c.id WHERE c.tenant_id = t.id AND k.status = 'assinado'),
    coalesce((SELECT s.go_live_homologado_em IS NOT NULL FROM public.subscriptions s WHERE s.tenant_id = t.id), false)
      OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.tenant_id = t.id AND p.onboarding_concluido),
    coalesce((SELECT s.go_live_homologado_em::timestamptz FROM public.subscriptions s WHERE s.tenant_id = t.id),
             (SELECT min(p.updated_at) FROM public.profiles p WHERE p.tenant_id = t.id AND p.onboarding_concluido)),
    NULL, false)
  FROM public.tenants t WHERE t.id = p_tenant_id
$parceiro_estagio_tenant$;

-- Tipos de comissão ampliados
ALTER TABLE public.parceiro_comissoes DROP CONSTRAINT IF EXISTS parceiro_comissoes_tipo_check;
ALTER TABLE public.parceiro_comissoes ADD CONSTRAINT parceiro_comissoes_tipo_check
  CHECK (tipo IN ('recorrente','bonus_renovacao','evento','ajuste','setup','retencao','clawback','override'));

-- ---------------------------------------------------------------------
-- 4) Motor v2
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_fechar_competencia(p_competencia date DEFAULT NULL, p_fechar boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_fechar_competencia$
DECLARE
  v_comp date := date_trunc('month', coalesce(p_competencia, CURRENT_DATE))::date;
  v_fim  date := (v_comp + interval '1 month' - interval '1 day')::date;
  v_p record; v_t record; v_ev record;
  v_nivel public.parceiro_niveis%ROWTYPE; v_prox public.parceiro_niveis%ROWTYPE;
  v_pct numeric; v_mrr_total bigint; v_base bigint; v_atrib text; v_val bigint; v_setup bigint;
  v_ret_pct numeric := public.parceiro_cfg('retencao_qualidade_pct', 20);
  v_ret_meses int := public.parceiro_cfg('retencao_qualidade_meses', 3)::int;
  v_ciclo int := public.parceiro_cfg('ciclo_meses', 24)::int;
  v_n_rec int := 0; v_n_setup int := 0; v_n_bonus int := 0; v_n_promo int := 0; v_n_parc int := 0; v_n_claw int := 0;
  v_ativacoes_mes int; v_golives_fast int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  FOR v_p IN SELECT * FROM public.parceiros WHERE status IN ('ativo','suspenso') LOOP
    v_n_parc := v_n_parc + 1;
    SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE id = v_p.nivel_id AND trilha = v_p.trilha;
    IF v_nivel.id IS NULL THEN SELECT * INTO v_nivel FROM public.parceiro_niveis WHERE trilha = v_p.trilha AND ativo ORDER BY ordem LIMIT 1; END IF;
    v_mrr_total := 0; v_ativacoes_mes := 0;

    FOR v_t IN
      SELECT t.id, t.nome, t.parceiro_id, t.implantador_parceiro_id, t.originado_em,
             public.parceiro_estagio_tenant(t.id) AS estagio,
             public.parceiro_mrr_tenant(t.id) AS mrr_cents,
             public.parceiro_base_tenant(t.id) AS base_cents,
             s.status AS sub_status, s.ciclo_inicio, s.ciclo_fim, s.setup_valor_cents, s.go_live_homologado_em,
             s.primeira_mensalidade_compensada_em, s.terceira_mensalidade_compensada_em, s.contrato_assinado_em, s.cancelado_em,
             (SELECT pl.is_public FROM public.plans pl WHERE pl.id = s.plan_id) AS plano_publico,
             (SELECT l.atribuicao FROM public.leads l WHERE l.tenant_convertido_id = t.id AND l.parceiro_id = v_p.id ORDER BY l.created_at LIMIT 1) AS atribuicao
      FROM public.tenants t LEFT JOIN public.subscriptions s ON s.tenant_id = t.id
      WHERE t.parceiro_id = v_p.id OR t.implantador_parceiro_id = v_p.id
    LOOP
      v_base := CASE WHEN coalesce(v_t.plano_publico, false) THEN v_t.base_cents ELSE 0 END;
      v_atrib := coalesce(v_t.atribuicao, 'link');
      v_pct := coalesce(v_p.percentual_comissao, CASE WHEN v_atrib = 'casa' THEN v_nivel.percentual_casa ELSE v_nivel.percentual_link END, 0);

      INSERT INTO public.parceiro_mrr_snapshots (parceiro_id, competencia, tenant_id, tenant_nome, estagio, mrr_cents, papel)
      VALUES (v_p.id, v_comp, v_t.id, v_t.nome, v_t.estagio, v_base,
              CASE WHEN v_t.parceiro_id = v_p.id AND v_t.implantador_parceiro_id = v_p.id THEN 'origem+implantacao'
                   WHEN v_t.parceiro_id = v_p.id THEN 'origem' ELSE 'implantacao' END)
      ON CONFLICT (parceiro_id, competencia, tenant_id) DO UPDATE SET estagio = EXCLUDED.estagio, mrr_cents = EXCLUDED.mrr_cents, tenant_nome = EXCLUDED.tenant_nome;

      -- só o ORIGINADOR recebe; conta só integra depois do go-live homologado
      IF v_t.parceiro_id <> v_p.id THEN CONTINUE; END IF;

      IF v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em <= v_fim
         AND v_t.sub_status IN ('active','past_due') AND v_base > 0 THEN
        v_mrr_total := v_mrr_total + v_base;
        v_val := round(v_base * v_pct / 100);
        -- Operador: retenção de qualidade nos primeiros meses
        IF v_p.trilha = 'operador' AND v_comp < (date_trunc('month', v_t.go_live_homologado_em) + (v_ret_meses || ' months')::interval)::date THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'retencao', 'retencao_qualidade', v_base, v_ret_pct, round(v_val * v_ret_pct / 100),
                  CASE WHEN v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN 'previsto' ELSE 'retido' END,
                  'Retenção de qualidade do Operador (' || v_ret_pct || '% dos ' || v_ret_meses || ' primeiros meses); liberada após a 3ª mensalidade com a conta ativa')
          ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE
            SET status = CASE WHEN public.parceiro_comissoes.status IN ('fechado','pago') THEN public.parceiro_comissoes.status
                              WHEN v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN 'previsto' ELSE 'retido' END,
                valor_cents = CASE WHEN public.parceiro_comissoes.status IN ('fechado','pago') THEN public.parceiro_comissoes.valor_cents ELSE EXCLUDED.valor_cents END;
          v_val := v_val - round(v_val * v_ret_pct / 100);
        END IF;
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', v_base, v_pct, v_val,
                CASE WHEN v_t.sub_status = 'past_due' THEN 'retido' ELSE 'previsto' END,
                CASE WHEN v_t.sub_status = 'past_due' THEN 'Cliente inadimplente — liberado com a regularização' END)
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE
          SET base_cents = EXCLUDED.base_cents, percentual = EXCLUDED.percentual, valor_cents = EXCLUDED.valor_cents, status = EXCLUDED.status, observacao = EXCLUDED.observacao
          WHERE public.parceiro_comissoes.status NOT IN ('fechado','pago');
        v_n_rec := v_n_rec + 1;
      ELSIF v_t.plano_publico IS FALSE AND v_t.sub_status IS NOT NULL THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'recorrente', 0, v_pct, 0, 'previsto', 'Plano interno ou não público: não gera comissão')
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO NOTHING;
      END IF;

      -- Liberação da retenção de qualidade quando a 3ª mensalidade compensa
      IF v_t.terceira_mensalidade_compensada_em IS NOT NULL THEN
        UPDATE public.parceiro_comissoes SET status = 'previsto', observacao = observacao || ' · liberada em ' || to_char(v_t.terceira_mensalidade_compensada_em,'DD/MM/YYYY')
        WHERE parceiro_id = v_p.id AND tenant_id = v_t.id AND tipo = 'retencao' AND status = 'retido';
      END IF;

      -- SETUP em 3 parcelas (participação da trilha/nível; Operador = fatura direto, não passa pela YE)
      v_setup := coalesce(v_t.setup_valor_cents, 0);
      IF v_setup > 0 AND v_nivel.setup_participacao_pct > 0 AND v_p.trilha <> 'operador' THEN
        IF v_t.primeira_mensalidade_compensada_em IS NOT NULL AND v_t.primeira_mensalidade_compensada_em <= v_fim
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela1') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela1', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela1_pct',30) / 100), 'previsto',
                  '1ª parcela do setup (' || public.parceiro_cfg('setup_parcela1_pct',30) || '%) — 1ª mensalidade compensada em ' || to_char(v_t.primeira_mensalidade_compensada_em,'DD/MM/YYYY'));
          v_n_setup := v_n_setup + 1;
        END IF;
        IF v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em <= v_fim AND v_t.primeira_mensalidade_compensada_em IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela2') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela2', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela2_pct',40) / 100), 'previsto',
                  '2ª parcela do setup (' || public.parceiro_cfg('setup_parcela2_pct',40) || '%) — go-live homologado em ' || to_char(v_t.go_live_homologado_em,'DD/MM/YYYY'));
          v_n_setup := v_n_setup + 1;
          -- Bônus de velocidade: go-live em até N dias da assinatura
          IF v_t.contrato_assinado_em IS NOT NULL AND v_t.go_live_homologado_em - v_t.contrato_assinado_em <= public.parceiro_cfg('bonus_velocidade_dias',15)::int THEN
            SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_velocidade' AND ativo;
            IF v_ev.id IS NOT NULL THEN
              INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
              VALUES (v_p.id, v_t.id, v_comp, 'evento', 'bonus_velocidade', v_setup, v_ev.percentual_setup,
                      v_ev.valor_fixo_cents + round(v_setup * v_nivel.setup_participacao_pct / 100 * v_ev.percentual_setup / 100), 'previsto',
                      'Bônus de velocidade: go-live em ' || (v_t.go_live_homologado_em - v_t.contrato_assinado_em) || ' dias')
              ON CONFLICT DO NOTHING;
              v_n_bonus := v_n_bonus + 1;
            END IF;
          END IF;
        END IF;
        IF v_t.terceira_mensalidade_compensada_em IS NOT NULL AND v_t.terceira_mensalidade_compensada_em <= v_fim AND v_t.sub_status = 'active'
           AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'setup' AND c.evento = 'setup_parcela3') THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'setup', 'setup_parcela3', v_setup, v_nivel.setup_participacao_pct,
                  round(v_setup * v_nivel.setup_participacao_pct / 100 * public.parceiro_cfg('setup_parcela3_pct',30) / 100), 'previsto',
                  '3ª parcela do setup (' || public.parceiro_cfg('setup_parcela3_pct',30) || '%) — 3ª mensalidade compensada com a conta ativa');
          v_n_setup := v_n_setup + 1;
        END IF;
      END IF;

      -- Bônus de retenção 90 dias (todas as trilhas; % do setup total do cliente)
      IF v_setup > 0 AND v_t.go_live_homologado_em IS NOT NULL AND v_t.go_live_homologado_em + 90 <= v_fim AND v_t.sub_status = 'active'
         AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.evento = 'bonus_retencao_90d') THEN
        SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_retencao_90d' AND ativo;
        IF v_ev.id IS NOT NULL THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'evento', 'bonus_retencao_90d', v_setup, v_ev.percentual_setup,
                  v_ev.valor_fixo_cents + round(v_setup * v_ev.percentual_setup / 100), 'previsto',
                  'Bônus de retenção: cliente ativo no 90º dia após o go-live (' || to_char(v_t.go_live_homologado_em + 90,'DD/MM/YYYY') || ')');
          v_n_bonus := v_n_bonus + 1;
        END IF;
      END IF;

      -- Ciclo: nasce no go-live; renovação automática com bônus 2×
      IF v_t.go_live_homologado_em IS NOT NULL AND v_t.ciclo_fim IS NULL THEN
        UPDATE public.subscriptions SET ciclo_meses = coalesce(ciclo_meses, v_ciclo), ciclo_inicio = v_t.go_live_homologado_em,
               ciclo_fim = v_t.go_live_homologado_em + (coalesce(ciclo_meses, v_ciclo) || ' months')::interval WHERE tenant_id = v_t.id;
      ELSIF v_t.ciclo_fim IS NOT NULL AND v_t.ciclo_fim BETWEEN v_comp AND v_fim AND v_t.sub_status = 'active' AND v_p.status = 'ativo' AND v_base > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, v_t.id, v_comp, 'bonus_renovacao', 'renovacao', v_base, v_pct,
                round(v_base * v_pct / 100 * coalesce(v_nivel.bonus_renovacao_multiplicador, public.parceiro_cfg('bonus_renovacao_mult',2))), 'previsto',
                'Renovação de ciclo em ' || to_char(v_t.ciclo_fim,'DD/MM/YYYY') || ' · novo ciclo de ' || v_ciclo || ' meses')
        ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO NOTHING;
        IF p_fechar THEN
          UPDATE public.subscriptions SET ciclo_inicio = ciclo_fim, ciclo_fim = ciclo_fim + (coalesce(ciclo_meses, v_ciclo) || ' months')::interval WHERE tenant_id = v_t.id;
        END IF;
        v_n_bonus := v_n_bonus + 1;
      END IF;

      -- Clawback: cancelamento entre o 4º e o 12º mês devolve % do setup recebido
      IF v_t.sub_status = 'canceled' AND v_t.go_live_homologado_em IS NOT NULL AND v_setup > 0
         AND (EXTRACT(year FROM age(coalesce(v_t.cancelado_em, v_fim), v_t.go_live_homologado_em)) * 12 + EXTRACT(month FROM age(coalesce(v_t.cancelado_em, v_fim), v_t.go_live_homologado_em)))
             BETWEEN public.parceiro_cfg('clawback_mes_inicio',4) AND public.parceiro_cfg('clawback_mes_fim',12)
         AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.tenant_id = v_t.id AND c.tipo = 'clawback') THEN
        SELECT coalesce(sum(valor_cents),0) INTO v_val FROM public.parceiro_comissoes WHERE parceiro_id = v_p.id AND tenant_id = v_t.id AND tipo = 'setup' AND status IN ('fechado','pago');
        IF v_val > 0 THEN
          INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
          VALUES (v_p.id, v_t.id, v_comp, 'clawback', 'clawback_setup', v_val, public.parceiro_cfg('clawback_pct',50),
                  -round(v_val * public.parceiro_cfg('clawback_pct',50) / 100), 'previsto',
                  'Clawback: cancelamento entre o 4º e o 12º mês devolve ' || public.parceiro_cfg('clawback_pct',50) || '% do setup recebido (não se aplica a falha comprovada do produto — ajuste manual)');
          v_n_claw := v_n_claw + 1;
        END IF;
      END IF;

      IF v_t.go_live_homologado_em BETWEEN v_comp AND v_fim THEN v_ativacoes_mes := v_ativacoes_mes + 1; END IF;
    END LOOP;

    -- Bônus de volume: N+ ativações no mês → % sobre os setups do mês
    IF v_ativacoes_mes >= public.parceiro_cfg('bonus_volume_ativacoes',3)::int THEN
      SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'bonus_volume' AND ativo;
      SELECT coalesce(sum(valor_cents),0) INTO v_val FROM public.parceiro_comissoes WHERE parceiro_id = v_p.id AND competencia = v_comp AND tipo = 'setup';
      IF v_ev.id IS NOT NULL AND v_val > 0 THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, NULL, v_comp, 'evento', 'bonus_volume', v_val, v_ev.percentual_setup, round(v_val * v_ev.percentual_setup / 100), 'previsto',
                'Bônus de volume: ' || v_ativacoes_mes || ' ativações no mês')
        ON CONFLICT DO NOTHING;
        v_n_bonus := v_n_bonus + 1;
      END IF;
    END IF;

    -- Fast Start: N ativações nos primeiros D dias de credenciamento (uma vez)
    SELECT count(*) INTO v_golives_fast FROM public.tenants t JOIN public.subscriptions s ON s.tenant_id = t.id
    WHERE t.parceiro_id = v_p.id AND s.go_live_homologado_em IS NOT NULL
      AND s.go_live_homologado_em <= v_p.parceiro_desde + public.parceiro_cfg('fast_start_dias',90)::int AND s.go_live_homologado_em <= v_fim;
    IF v_golives_fast >= public.parceiro_cfg('fast_start_ativacoes',3)::int
       AND NOT EXISTS (SELECT 1 FROM public.parceiro_comissoes c WHERE c.parceiro_id = v_p.id AND c.evento = 'fast_start') THEN
      SELECT * INTO v_ev FROM public.parceiro_eventos_remuneracao WHERE trilha = v_p.trilha AND evento = 'fast_start' AND ativo;
      IF v_ev.id IS NOT NULL THEN
        INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
        VALUES (v_p.id, NULL, v_comp, 'evento', 'fast_start', 0, 0, coalesce(nullif(v_ev.valor_fixo_cents,0), public.parceiro_cfg('fast_start_cents',200000)::bigint), 'previsto',
                'Fast Start: ' || v_golives_fast || ' empresas ativadas nos primeiros ' || public.parceiro_cfg('fast_start_dias',90) || ' dias');
        v_n_bonus := v_n_bonus + 1;
      END IF;
    END IF;

    -- Promoção imediata; nunca rebaixa (proteção de 12 meses / data-base anual)
    SELECT * INTO v_prox FROM public.parceiro_niveis
    WHERE trilha = v_p.trilha AND ativo AND ordem > coalesce(v_nivel.ordem, 0) AND mrr_minimo_cents <= v_mrr_total ORDER BY ordem DESC LIMIT 1;
    IF v_prox.id IS NOT NULL THEN
      UPDATE public.parceiros SET nivel_id = v_prox.id, nivel_conquistado_em = CURRENT_DATE WHERE id = v_p.id;
      v_n_promo := v_n_promo + 1;
    END IF;
  END LOOP;

  -- Override do Master Regional sobre o MRR líquido dos sub-parceiros
  FOR v_p IN SELECT m.* FROM public.parceiros m WHERE m.master_regional AND m.status = 'ativo' LOOP
    SELECT coalesce(sum(c.base_cents),0) INTO v_base FROM public.parceiro_comissoes c JOIN public.parceiros s ON s.id = c.parceiro_id
    WHERE s.master_parceiro_id = v_p.id AND c.competencia = v_comp AND c.tipo = 'recorrente';
    IF v_base > 0 THEN
      INSERT INTO public.parceiro_comissoes (parceiro_id, tenant_id, competencia, tipo, evento, base_cents, percentual, valor_cents, status, observacao)
      VALUES (v_p.id, NULL, v_comp, 'override', 'master_regional', v_base, public.parceiro_cfg('master_override_pct',5), round(v_base * public.parceiro_cfg('master_override_pct',5) / 100), 'previsto', 'Override Master Regional sobre os sub-parceiros')
      ON CONFLICT (parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,'')) DO UPDATE SET base_cents = EXCLUDED.base_cents, valor_cents = EXCLUDED.valor_cents
        WHERE public.parceiro_comissoes.status NOT IN ('fechado','pago');
    END IF;
  END LOOP;

  IF p_fechar THEN
    UPDATE public.parceiro_comissoes SET status = 'fechado', fechado_em = now() WHERE competencia = v_comp AND status = 'previsto';
  END IF;

  RETURN jsonb_build_object('competencia', to_char(v_comp,'YYYY-MM'), 'parceiros', v_n_parc, 'recorrentes', v_n_rec,
    'setup_parcelas', v_n_setup, 'bonus', v_n_bonus, 'clawbacks', v_n_claw, 'promocoes', v_n_promo, 'fechado', p_fechar,
    'compromisso_ciclo_cents', (SELECT coalesce(sum(c.valor_cents),0) FROM public.parceiro_comissoes c WHERE c.competencia = v_comp AND c.tipo = 'recorrente') * v_ciclo);
END $parceiro_fechar_competencia$;

-- Unique passa a cobrir tenant NULL (bônus por parceiro)
DROP INDEX IF EXISTS uq_parceiro_comissoes_recorrente;
CREATE UNIQUE INDEX IF NOT EXISTS uq_parceiro_comissoes_recorrente
  ON public.parceiro_comissoes(parceiro_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), competencia, tipo, coalesce(evento,''));

-- ---------------------------------------------------------------------
-- 5) Contrato v2 gerado por parceiro e salvo na tela de Contratos
-- ---------------------------------------------------------------------
ALTER TABLE public.contratos_assinaturas
  ADD COLUMN IF NOT EXISTS parceiro_id uuid REFERENCES public.parceiros(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS html_assinado text;

CREATE OR REPLACE FUNCTION public.parceiro_contrato_render(p_parceiro_id uuid, p_html text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_render$
DECLARE v_p public.parceiros%ROWTYPE; v_html text; v_n public.parceiro_niveis%ROWTYPE; v_matriz text; v_setup text;
BEGIN
  SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  v_html := coalesce(p_html, (SELECT html FROM public.parceiro_contratos_versoes WHERE vigente));
  SELECT string_agg(format('%s: %s%% (Foco) · %s%% (Visão) · %s%% (Diamante)', initcap(trilha), f, v, d), '; ' ORDER BY trilha) INTO v_matriz
  FROM (SELECT trilha, max(percentual_link) FILTER (WHERE ordem=1) f, max(percentual_link) FILTER (WHERE ordem=2) v, max(percentual_link) FILTER (WHERE ordem=3) d FROM public.parceiro_niveis WHERE ativo GROUP BY trilha) m;
  SELECT string_agg(format('%s: %s%% / %s%% / %s%%', initcap(trilha), f, v, d), '; ' ORDER BY trilha) INTO v_setup
  FROM (SELECT trilha, max(setup_participacao_pct) FILTER (WHERE ordem=1) f, max(setup_participacao_pct) FILTER (WHERE ordem=2) v, max(setup_participacao_pct) FILTER (WHERE ordem=3) d FROM public.parceiro_niveis WHERE ativo GROUP BY trilha) m;
  v_html := replace(v_html, '{{PARCEIRO_NOME}}', coalesce(v_p.nome, '________________'));
  v_html := replace(v_html, '{{PARCEIRO_DOCUMENTO}}', coalesce(v_p.documento, '________________'));
  v_html := replace(v_html, '{{PARCEIRO_TIPO_PESSOA}}', CASE v_p.tipo_pessoa WHEN 'pf' THEN 'pessoa física, CPF' ELSE 'pessoa jurídica, CNPJ' END);
  v_html := replace(v_html, '{{PARCEIRO_EMAIL}}', coalesce(v_p.email, '________________'));
  v_html := replace(v_html, '{{PARCEIRO_CIDADE_UF}}', coalesce(v_p.cidade || '/' || v_p.uf, '________________'));
  v_html := replace(v_html, '{{TRILHA}}', coalesce(initcap(v_p.trilha), '________'));
  v_html := replace(v_html, '{{PERFIL}}', coalesce(v_p.tipo_parceiro, '________'));
  v_html := replace(v_html, '{{DATA}}', to_char(now(), 'DD/MM/YYYY'));
  v_html := replace(v_html, '{{MATRIZ_COMISSAO}}', coalesce(v_matriz, ''));
  v_html := replace(v_html, '{{MATRIZ_SETUP}}', coalesce(v_setup, ''));
  v_html := replace(v_html, '{{CICLO_MESES}}', public.parceiro_cfg('ciclo_meses',24)::text);
  v_html := replace(v_html, '{{NAO_ALICIAMENTO_MESES}}', public.parceiro_cfg('nao_aliciamento_meses',24)::text);
  v_html := replace(v_html, '{{CONFIDENCIALIDADE_ANOS}}', public.parceiro_cfg('confidencialidade_anos',5)::text);
  v_html := replace(v_html, '{{RESCISAO_AVISO_DIAS}}', public.parceiro_cfg('rescisao_aviso_dias',90)::text);
  v_html := replace(v_html, '{{FECHAMENTO_DIA}}', public.parceiro_cfg('fechamento_dia',25)::text);
  v_html := replace(v_html, '{{PAGAMENTO_DIA}}', public.parceiro_cfg('pagamento_dia',10)::text);
  v_html := replace(v_html, '{{SETUP_PARCELAS}}', public.parceiro_cfg('setup_parcela1_pct',30)::text || '% / ' || public.parceiro_cfg('setup_parcela2_pct',40)::text || '% / ' || public.parceiro_cfg('setup_parcela3_pct',30)::text || '%');
  v_html := replace(v_html, '{{RETENCAO_90D_PCT}}', public.parceiro_cfg('bonus_retencao_90d_pct',15)::text);
  v_html := replace(v_html, '{{CLAWBACK_PCT}}', public.parceiro_cfg('clawback_pct',50)::text);
  v_html := replace(v_html, '{{RETENCAO_QUALIDADE_PCT}}', public.parceiro_cfg('retencao_qualidade_pct',20)::text);
  v_html := replace(v_html, '{{INADIMPLENCIA_DIAS}}', public.parceiro_cfg('inadimplencia_dias',60)::text);
  v_html := replace(v_html, '{{REGISTRO_OPORTUNIDADE_DIAS}}', public.parceiro_cfg('registro_oportunidade_dias',90)::text);
  v_html := replace(v_html, '{{DESCONTO_AUTONOMIA_PCT}}', public.parceiro_cfg('desconto_autonomia_pct',10)::text);
  v_html := replace(v_html, '{{PREMIO_LIQUIDEZ_MULT}}', public.parceiro_cfg('premio_liquidez_mult_max',6)::text);
  v_html := replace(v_html, '{{PREMIO_LIQUIDEZ_TETO}}', CASE WHEN public.parceiro_cfg('premio_liquidez_teto_pct',0) > 0 THEN public.parceiro_cfg('premio_liquidez_teto_pct',0)::text || '% do valor da transação' ELSE 'percentual a ser fixado em anexo antes do primeiro pagamento' END);
  v_html := replace(v_html, '{{META_ATIVIDADE}}', public.parceiro_cfg('meta_atividade_semestre',1)::text);
  RETURN v_html;
END $parceiro_contrato_render$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_render(uuid, text) TO authenticated;

-- Versão pública do texto (com placeholders genéricos) para quem ainda não é parceiro
CREATE OR REPLACE FUNCTION public.parceiro_contrato_publico()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_publico$
  SELECT jsonb_build_object('versao', v.versao, 'titulo', v.titulo, 'publicado_em', v.publicado_em,
    'html', public.parceiro_contrato_render(public.parceiro_meu_id(), v.html))
  FROM public.parceiro_contratos_versoes v WHERE v.vigente
$parceiro_contrato_publico$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_publico() TO anon, authenticated;

-- Aceite: registra em parceiro_contratos_aceites E gera o contrato assinado na tela de Contratos
CREATE OR REPLACE FUNCTION public.parceiro_aceitar_contrato(_user_agent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_aceitar_contrato$
DECLARE v_pid uuid := public.parceiro_meu_id(); v_v public.parceiro_contratos_versoes%ROWTYPE; v_ip text; v_p public.parceiros%ROWTYPE;
        v_modelo uuid; v_html text; v_hash text; v_ass uuid;
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RAISE EXCEPTION 'Nenhuma versão vigente do contrato'; END IF;
  SELECT * INTO v_p FROM public.parceiros WHERE id = v_pid;
  BEGIN
    v_ip := coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', current_setting('request.headers', true)::json->>'cf-connecting-ip');
  EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;

  v_html := public.parceiro_contrato_render(v_pid, v_v.html);
  v_hash := encode(sha256(convert_to(v_html, 'UTF8')), 'hex');

  INSERT INTO public.parceiro_contratos_aceites (parceiro_id, versao, user_id, ip, user_agent, hash_texto)
  VALUES (v_pid, v_v.versao, auth.uid(), v_ip, left(_user_agent, 300), v_hash)
  ON CONFLICT (parceiro_id, versao) DO NOTHING;
  UPDATE public.parceiros SET aceite_termos_em = coalesce(aceite_termos_em, now()) WHERE id = v_pid;

  -- Modelo na tela de Contratos (categoria parceria), um por versão vigente
  SELECT id INTO v_modelo FROM public.contratos_aceite WHERE categoria = 'parceria' AND titulo = v_v.titulo AND versao = v_v.versao LIMIT 1;
  IF v_modelo IS NULL THEN
    INSERT INTO public.contratos_aceite (titulo, categoria, descricao_publica, corpo_html, requer_cpf, requer_telefone, versao, ativo, created_by)
    VALUES (v_v.titulo, 'parceria', 'Contrato de Parceria Comercial do Programa de Parceiros. Aceite eletrônico realizado na Área do Parceiro; cada aceite gera um registro assinado com os dados do parceiro.', v_v.html, false, false, v_v.versao, true, auth.uid())
    RETURNING id INTO v_modelo;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contratos_assinaturas WHERE contrato_id = v_modelo AND parceiro_id = v_pid AND status = 'assinado') THEN
    INSERT INTO public.contratos_assinaturas (contrato_id, parceiro_id, signatario_nome, signatario_cpf, signatario_email, signatario_telefone,
      ip_address, user_agent, hash_documento, html_assinado, link_enviado_para, assinado_em, status, observacoes)
    VALUES (v_modelo, v_pid, v_p.nome, v_p.documento, v_p.email, v_p.telefone, v_ip, left(_user_agent,300), v_hash, v_html, v_p.email, now(), 'assinado',
      'Aceite eletrônico na Área do Parceiro (clickwrap) · parceiro ' || v_p.codigo || ' · trilha ' || v_p.trilha || ' · versão ' || v_v.versao)
    RETURNING id INTO v_ass;
  END IF;
  RETURN jsonb_build_object('ok', true, 'versao', v_v.versao, 'assinatura_id', v_ass);
END $parceiro_aceitar_contrato$;

-- Publicar versão nova também atualiza o modelo na tela de Contratos
CREATE OR REPLACE FUNCTION public.superadmin_parceiro_contrato_publicar(_titulo text, _html text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_parceiro_contrato_publicar$
DECLARE v_versao int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  UPDATE public.parceiro_contratos_versoes SET vigente = false WHERE vigente;
  SELECT coalesce(max(versao),0) + 1 INTO v_versao FROM public.parceiro_contratos_versoes;
  INSERT INTO public.parceiro_contratos_versoes (versao, titulo, html, hash_texto, vigente, publicado_por)
  VALUES (v_versao, _titulo, _html, encode(sha256(convert_to(_html, 'UTF8')), 'hex'), true, auth.uid());
  UPDATE public.contratos_aceite SET ativo = false WHERE categoria = 'parceria' AND titulo LIKE 'Contrato de Parceria Comercial%';
  INSERT INTO public.contratos_aceite (titulo, categoria, descricao_publica, corpo_html, requer_cpf, versao, ativo, created_by)
  VALUES (_titulo, 'parceria', 'Contrato de Parceria Comercial do Programa de Parceiros (aceite eletrônico na Área do Parceiro).', _html, false, v_versao, true, auth.uid());
  RETURN v_versao;
END $superadmin_parceiro_contrato_publicar$;

-- ---------------------------------------------------------------------
-- 6) Texto v2 do contrato (política jul/2026) — vira a versão vigente
-- ---------------------------------------------------------------------
DO $contrato$
DECLARE v_html text; v_ver int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.parceiro_contratos_versoes WHERE versao >= 2) THEN RETURN; END IF;
  v_html := $H$
<h2>Contrato de Parceria Comercial — Programa de Parceiros YourEyes</h2>
<p><strong>Versão 2</strong> · vigente a partir de {{DATA}}</p>
<p><strong>YOUREYES</strong>, plataforma de gestão de pessoas, departamento pessoal, saúde e segurança do trabalho e clima psicossocial ("YourEyes"), e <strong>{{PARCEIRO_NOME}}</strong>, {{PARCEIRO_TIPO_PESSOA}} {{PARCEIRO_DOCUMENTO}}, e-mail {{PARCEIRO_EMAIL}}, {{PARCEIRO_CIDADE_UF}} ("Parceiro"), perfil {{PERFIL}}, trilha <strong>{{TRILHA}}</strong>, celebram este contrato. O aceite eletrônico na Área do Parceiro, com registro de data, versão, usuário, endereço de rede e navegador, tem validade jurídica de assinatura (MP 2.200-2/2001, art. 10, § 2º; Lei 14.063/2020; Código Civil, art. 107).</p>

<h3>1. Objeto e natureza da relação</h3>
<p>1.1. O Parceiro passa a indicar, representar e/ou implantar e atender empresas clientes da plataforma YourEyes, conforme a trilha escolhida e aprovada, e recebe remuneração pelas contas que originar e pelos eventos que executar, nos termos deste contrato.</p>
<p>1.2. Trata-se de parceria comercial de intermediação e prestação de serviços entre partes autônomas. Não cria vínculo de emprego, sociedade, franquia, mandato, joint venture nem representação comercial com exclusividade de zona. O Parceiro atua por conta própria, com autonomia, sem subordinação e sem habitualidade pessoal exigida, e responde pelos seus próprios tributos, encargos e colaboradores.</p>
<p>1.3. A YourEyes fornece a plataforma, o suporte de segundo nível, a evolução do produto, a certificação, os materiais oficiais e a gestão do canal.</p>

<h3>2. Titularidade — os clientes são da YourEyes</h3>
<p>2.1. <strong>Os clientes, os contratos de assinatura, os dados e o relacionamento contratual pertencem exclusivamente à YourEyes.</strong> O Parceiro não tem, e não adquire por este contrato, qualquer direito atual ou futuro de propriedade, co-titularidade, posse, exclusividade, preferência de compra ou participação sobre a carteira de clientes, ainda que os tenha originado ou atendido.</p>
<p>2.2. O contrato de assinatura da plataforma é firmado diretamente entre a YourEyes e o cliente. O Parceiro não é parte, interveniente nem anuente. A mensalidade é sempre faturada pela YourEyes ao cliente; o Parceiro jamais fatura a assinatura, ainda que preste serviços próprios ao mesmo cliente.</p>
<p>2.3. A YourEyes é a controladora dos dados pessoais tratados na plataforma (LGPD, Lei 13.709/2018). Quando o Parceiro tratar dados por conta da YourEyes (implantação, suporte), atua como operador, nos limites das instruções recebidas, sendo vedado extrair, copiar, reter ou reutilizar a base para qualquer fim.</p>
<p>2.4. Não existe carteira vendável, cessível ou herdável pelo Parceiro. O que existe é direito de crédito sobre as comissões vincendas, nas condições do ciclo vigente (cláusula 5).</p>
<p>2.5. É vedada qualquer comunicação que apresente o Parceiro como fabricante, licenciante, proprietário ou operador da plataforma.</p>
<p>2.6. <strong>O que é do Parceiro e está protegido:</strong> (a) o <em>registro de originação</em> de cada conta no sistema de gestão do canal, que é o fato gerador da comissão; (b) enquanto o Parceiro estiver ativo e o ciclo vigente, a YourEyes não realiza venda direta na conta originada nem a redireciona a outro parceiro, e toda expansão dentro da conta (mais colaboradores, módulos, upgrade) remunera o originador; (c) na trilha Operador, o Parceiro é o ponto formal de atendimento reconhecido perante o cliente; (d) o Parceiro pode contratar com o cliente, em nome próprio, implantação, treinamento e consultoria — contrato dele, que não se confunde com a assinatura da plataforma.</p>

<h3>3. Trilhas, perfis e aprovação</h3>
<p>3.1. <strong>Indicador</strong>: apresenta o contato qualificado e faz a ponte de credibilidade; não negocia preço, não fecha, não implanta. A YourEyes conduz do primeiro contato ao go-live e sustenta o cliente. <strong>Representante</strong>: prospecta, apresenta, demonstra, negocia dentro da política de preço e fecha o contrato; não implanta nem presta suporte técnico. <strong>Operador</strong>: vende, implanta, treina, presta suporte de primeiro nível e acompanha o sucesso da conta.</p>
<p>3.2. O Parceiro escolhe a trilha ao entrar e pode migrar depois, mediante aprovação e certificação. A trilha Indicador tem adesão imediata; as demais dependem de aprovação da YourEyes, que pode solicitar documentos (CNPJ, registro profissional, referências) e recusar ou suspender o credenciamento sem obrigação de justificativa detalhada.</p>
<p>3.3. Certificação é obrigatória para vender; certificação de nível 2 é obrigatória para implantar na trilha Operador. Recertificação anual.</p>

<h3>4. Atribuição de clientes e registro de oportunidade</h3>
<p>4.1. Uma empresa é atribuída ao Parceiro quando (a) chega à YourEyes pelo link de indicação do Parceiro e conclui cadastro ou contratação dentro da janela de atribuição, ou (b) é vinculada ao Parceiro pela YourEyes (lead encaminhado pela casa, por localidade ou acordo), ou (c) tem registro de oportunidade válido em nome do Parceiro.</p>
<p>4.2. O registro de oportunidade protege a conta por {{REGISTRO_OPORTUNIDADE_DIAS}} dias, renováveis mediante evidência de avanço. Prevalece o registro mais antigo; sem registro, prevalece a evidência documental de primeiro contato. Cliente já existente na base da YourEyes, ou já em negociação pela equipe própria, não é atribuído.</p>
<p>4.3. Preferência territorial, quando houver, é condicionada a desempenho e revisável; não há exclusividade territorial permanente.</p>

<h3>5. Remuneração</h3>
<p>5.1. <strong>Comissão recorrente</strong>: percentual sobre a mensalidade efetivamente recebida do cliente, líquida de impostos sobre a venda e de descontos concedidos — nunca sobre valor apenas faturado. Percentuais por trilha e nível (Foco / Visão / Diamante): {{MATRIZ_COMISSAO}}. O nível é definido pelo MRR ativo sob atendimento do Parceiro (Foco até R$ 4.000; Visão de R$ 4.001 a R$ 12.000; Diamante acima de R$ 12.000). A promoção é imediata; o nível conquistado não cai por 12 meses e é revisado apenas na data-base anual. O nível é reconhecimento de desempenho, não medida de propriedade sobre clientes.</p>
<p>5.2. <strong>Ciclos de {{CICLO_MESES}} meses</strong>: a comissão de cada cliente é devida em ciclos de {{CICLO_MESES}} meses contados do go-live homologado daquele cliente, renovados automaticamente por períodos iguais, sem número máximo de renovações, enquanto forem atendidas as condições objetivas: Parceiro ativo (cláusula 7.5), certificação vigente e cliente na base. O relacionamento não se encerra por decurso de prazo. O compromisso da YourEyes, em qualquer data, limita-se ao que resta do ciclo em curso de cada cliente. A cada renovação, o Parceiro recebe bônus equivalente a duas comissões mensais daquele cliente.</p>
<p>5.3. <strong>Expansão</strong>: aumento de colaboradores, módulos adicionais e upgrade de plano geram comissão pelo mesmo percentual e são incorporados ao ciclo em curso, ainda que executados pelo time da YourEyes.</p>
<p>5.4. <strong>Setup (implantação)</strong>: é sempre pago pelo cliente. Nas trilhas Indicador e Representante, o Parceiro participa do setup recebido pela YourEyes nos percentuais por nível {{MATRIZ_SETUP}}, liberados em três parcelas ({{SETUP_PARCELAS}}) condicionadas, respectivamente, à compensação da primeira mensalidade, ao go-live homologado e à compensação da terceira mensalidade com a conta ativa. Nenhuma parcela é liberada antes da primeira mensalidade compensada. Na trilha Operador, o setup é serviço próprio do Parceiro, contratado e faturado por ele diretamente ao cliente, obrigando-se o Parceiro a não faturar mais de metade desse serviço antes do go-live homologado.</p>
<p>5.5. <strong>Bônus</strong> (valores vigentes na Área do Parceiro e na tabela do programa): retenção 90 dias ({{RETENCAO_90D_PCT}}% do setup, cliente ativo e adimplente no 90º dia após o go-live); Fast Start; volume; velocidade; 13º da carteira (churn abaixo do limite no ano). Bônus são liberalidades condicionadas e podem ser alterados para contratos novos, nunca para os ciclos em curso.</p>
<p>5.6. <strong>Go-live homologado</strong>: a homologação é feita pela YourEyes, inclusive quando a implantação foi executada pelo Parceiro, e exige ao menos 80% dos colaboradores cadastrados, um ciclo operacional completo no sistema, usuários-chave treinados com primeiro acesso, termo de aceite de implantação assinado pelo cliente e nenhum chamado crítico aberto há mais de 5 dias. Sem homologação a conta não integra o nível, não gera bônus e não libera parcelas.</p>
<p>5.7. <strong>Retenção de qualidade (Operador)</strong>: nos três primeiros meses de cada cliente novo, {{RETENCAO_QUALIDADE_PCT}}% da comissão recorrente fica retida e é liberada integralmente após a compensação da terceira mensalidade com a conta ativa.</p>
<p>5.8. <strong>Clawback</strong>: cancelamento do cliente entre o 4º e o 12º mês devolve {{CLAWBACK_PCT}}% do setup efetivamente recebido pelo Parceiro, por compensação nas comissões seguintes. Até o 3º mês não há devolução. Falha comprovada do produto não gera devolução em nenhum prazo.</p>
<p>5.9. <strong>Inadimplência</strong>: atraso do cliente superior a {{INADIMPLENCIA_DIAS}} dias suspende a comissão daquele contrato; a regularização libera os valores retidos. A suspensão não interrompe a contagem do ciclo.</p>
<p>5.10. <strong>Fechamento e pagamento</strong>: a competência fecha no dia {{FECHAMENTO_DIA}} e o pagamento ocorre até o dia {{PAGAMENTO_DIA}} do mês seguinte, por PIX na chave informada pelo Parceiro, mediante nota fiscal ou recibo, com extrato detalhado na Área do Parceiro. Tributos incidentes sobre a remuneração são de responsabilidade do Parceiro.</p>
<p>5.11. <strong>Desconto</strong>: o Parceiro pode conceder até {{DESCONTO_AUTONOMIA_PCT}}% de desconto sobre a tabela; acima disso precisa de aprovação. Todo desconto reduz proporcionalmente a base de cálculo da própria comissão.</p>
<p>5.12. <strong>Regra de transição</strong>: alterações de tabela, percentuais ou bônus valem exclusivamente para contas atribuídas após a mudança. Nenhuma comissão de ciclo em curso é reduzida.</p>

<h3>6. Obrigações do Parceiro</h3>
<p>6.1. Apresentar a YourEyes com veracidade, dentro da política de preço, sem promessas de funcionalidade, prazo ou preço fora do material oficial.</p>
<p>6.2. Não praticar spam, publicidade enganosa, compra de palavras-chave com a marca YourEyes, nem inserir o link de indicação em cadastros de terceiros sem o seu conhecimento.</p>
<p>6.3. Manter cadastro, contato, certificação e chave PIX atualizados. Cumprir a meta mínima de atividade ({{META_ATIVIDADE}} ativação por semestre) para manter o status ativo e a renovação automática dos ciclos.</p>
<p>6.4. Quando implantar ou atender: seguir o roteiro e os padrões da YourEyes, submeter cada conta à homologação e comunicar imediatamente qualquer incidente que envolva dados de clientes.</p>

<h3>7. Confidencialidade, segredos comerciais, não concorrência e não aliciamento</h3>
<p>7.1. São <strong>informações confidenciais e segredos de negócio</strong> da YourEyes (Lei 9.279/1996, art. 195, XI e XII): modelo de negócios, tabela de preços e descontos não públicos, estrutura de comissões e níveis, roteiros comerciais, materiais de implantação e certificação, metodologias, roadmap, métricas, relação de clientes, leads e prospects, e todo dado acessível pela Área do Parceiro ou pela plataforma.</p>
<p>7.2. O Parceiro usará essas informações exclusivamente para os fins deste contrato, não as divulgará a terceiros e as protegerá com o mesmo cuidado que dedica às próprias informações sigilosas, durante a vigência e por <strong>{{CONFIDENCIALIDADE_ANOS}} anos</strong> após o término; segredos de negócio, enquanto mantiverem essa natureza.</p>
<p>7.3. <strong>Não aliciamento</strong>: durante a vigência e por <strong>{{NAO_ALICIAMENTO_MESES}} meses</strong> após o término, o Parceiro não promoverá, direta ou indiretamente, a migração de clientes originados ou atendidos por este programa para plataforma concorrente, nem aliciará colaboradores, parceiros ou sub-parceiros da YourEyes.</p>
<p>7.4. <strong>Não concorrência</strong>: no mesmo prazo de {{NAO_ALICIAMENTO_MESES}} meses, o Parceiro não desenvolverá, comercializará nem representará plataforma de software concorrente (gestão integrada de RH, DP, ponto, saúde ocupacional e psicossocial) junto aos clientes atribuídos por este programa, nem se valerá de informações confidenciais, materiais, listas ou relacionamentos obtidos pela parceria para esse fim. A restrição é limitada no objeto e nos clientes indicados, não impede o Parceiro de exercer sua atividade principal (clínica, contabilidade, consultoria, engenharia) nem de atender os mesmos clientes com serviços próprios que não substituam a plataforma, e tem como contrapartida a manutenção das comissões dos ciclos em curso após a rescisão sem infração (cláusula 10.3).</p>
<p>7.5. A violação das cláusulas 7.1 a 7.4 ou da cláusula 2 sujeita o Parceiro à perda das comissões futuras, à devolução das comissões recebidas nos 12 meses anteriores à infração, a multa compensatória equivalente a 12 vezes a média mensal das comissões dos últimos 12 meses (mínimo de R$ 10.000,00) e à indenização por perdas e danos excedentes, sem prejuízo de tutela inibitória.</p>

<h3>8. Marca e propriedade intelectual</h3>
<p>8.1. Licença gratuita, não exclusiva e revogável para uso da marca e dos materiais oficiais na divulgação do programa, conforme o manual de marca. Vedado registrar domínios, perfis, marcas ou nomes empresariais que contenham "YourEyes"; co-branding só a partir do nível Visão, com aprovação prévia.</p>
<p>8.2. Toda propriedade intelectual da plataforma, dos materiais e das metodologias permanece da YourEyes. Sugestões incorporadas ao produto não geram remuneração adicional nem direito de coautoria.</p>

<h3>9. Proteção de dados</h3>
<p>9.1. Os dados cadastrais do Parceiro são tratados pela YourEyes para execução deste contrato, pagamento e obrigações legais, com base no art. 7º, V e II, da LGPD, e ficam disponíveis para consulta e correção na Área do Parceiro.</p>
<p>9.2. A Área do Parceiro exibe apenas dados da empresa cliente (nome, plano, estágio, valores, datas). Dados de pessoas físicas (colaboradores, saúde, psicossocial) não são compartilhados; acesso incidental obriga ao sigilo e à comunicação imediata.</p>
<p>9.3. O aceite deste contrato é registrado com data, versão, usuário, endereço de rede e navegador como prova da contratação, e uma cópia assinada fica disponível para o Parceiro e para a YourEyes.</p>

<h3>10. Vigência, suspensão e rescisão</h3>
<p>10.1. Vigência por prazo indeterminado a partir do aceite. Qualquer parte pode rescindir sem ônus com aviso prévio de {{RESCISAO_AVISO_DIAS}} dias.</p>
<p>10.2. A YourEyes pode suspender novas ativações do Parceiro em caso de índice de qualidade abaixo da meta por dois trimestres consecutivos, e suspender ou encerrar o credenciamento de imediato em caso de fraude, violação das cláusulas 2, 6, 7 ou 8, dano à imagem da marca ou inatividade além da meta mínima. A suspensão de ativações não afeta a carteira atendida nem as comissões em curso.</p>
<p>10.3. <strong>Rescisão sem infração</strong> (por qualquer parte): as comissões dos ciclos em curso continuam devidas até o término de cada ciclo, desde que o Parceiro cumpra as cláusulas 7.3 e 7.4. <strong>Rescisão por infração</strong> do Parceiro: cessam de imediato.</p>
<p>10.4. <strong>Cessão e mudança de controle</strong>: a YourEyes pode ceder este contrato a controladora, controlada, coligada ou adquirente, independentemente de anuência do Parceiro, mantidas as condições até o término dos ciclos em curso. O Parceiro não pode ceder este contrato sem anuência escrita.</p>

<h3>11. Prêmio de Liquidez</h3>
<p>11.1. Havendo mudança de controle societário da YourEyes, alienação substancial de ativos ou incorporação, os parceiros ativos, certificados e adimplentes na data do evento, com no mínimo 12 meses de programa, receberão bonificação contratual de até {{PREMIO_LIQUIDEZ_MULT}} vezes a média mensal das comissões recebidas nos 12 meses anteriores, limitada a um teto global de {{PREMIO_LIQUIDEZ_TETO}}, rateado proporcionalmente se o somatório o ultrapassar, paga em parcela única em até 30 dias do fechamento, condicionada à permanência por 12 meses após o evento (devolução proporcional em caso de saída).</p>
<p>11.2. A bonificação tem natureza de prêmio por desempenho: não é participação societária, não confere voto nem gera expectativa de sociedade. Enquanto o teto global não estiver fixado em anexo, a cláusula não gera direito exigível.</p>

<h3>12. Disposições gerais</h3>
<p>12.1. A YourEyes pode publicar nova versão deste contrato; ela é apresentada na Área do Parceiro e passa a valer para o Parceiro após o seu aceite. Enquanto não aceitar, aplica-se a versão anterior por até 60 dias, após o que novas ativações podem ser suspensas. Nenhuma versão nova reduz comissão de ciclo em curso.</p>
<p>12.2. Este contrato complementa os Termos de Uso e a Política de Privacidade da YourEyes e prevalece sobre eles no que se refere ao programa de parceiros. A nulidade de uma cláusula não afeta as demais.</p>
<p>12.3. Comunicações formais pelo e-mail cadastrado na Área do Parceiro e pelo e-mail contato@youreyes.com.br.</p>
<p>12.4. <strong>Solução de controvérsias</strong>: as partes buscarão solução amigável e, não a alcançando em 30 dias, submeterão a controvérsia a mediação. Persistindo, fica eleito o foro da comarca da sede da YourEyes, com renúncia a qualquer outro, ressalvada a faculdade de as partes, por termo específico, optarem por arbitragem nos termos da Lei 9.307/1996.</p>
<p><em>Nota de governança: o programa pode ser enquadrado, conforme a atuação concreta, na Lei 4.886/1965 (representação comercial). A YourEyes submeteu este modelo à revisão jurídica; as partes declaram que a relação pretendida é de parceria de intermediação autônoma, conforme descrito na cláusula 1.</em></p>
$H$;
  UPDATE public.parceiro_contratos_versoes SET vigente = false WHERE vigente;
  INSERT INTO public.parceiro_contratos_versoes (versao, titulo, html, hash_texto, vigente)
  VALUES (2, 'Contrato de Parceria Comercial — Programa de Parceiros YourEyes (v2)', v_html, encode(sha256(convert_to(v_html, 'UTF8')), 'hex'), true);
END $contrato$;

-- ---------------------------------------------------------------------
-- 7) Lista do SuperAdmin e portal: expõem trilha/nível/matriz
-- ---------------------------------------------------------------------
-- (superadmin_parceiros_list já devolve trilha, nivel_nome e contrato; nada a mudar)

-- ---------------------------------------------------------------------
-- 8) QA — PGP-013 passa a testar a parcela 2 do setup; PGP-005 a matriz
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_pgp_cenario(OUT o_parceiro uuid, OUT o_impl uuid, OUT o_tenant_pub uuid)
RETURNS record LANGUAGE plpgsql AS $$
DECLARE v_plano uuid; v_uid uuid := gen_random_uuid();
BEGIN
  PERFORM public.qa_modo_ligar();
  o_tenant_pub := public.qa_sandbox_tenant_id();
  IF o_tenant_pub IS NULL THEN RAISE EXCEPTION 'Cercado qa-sandbox não existe neste ambiente'; END IF;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-ORIG', 'QA Origem', 'representante', 'representante', 'ativo') RETURNING id INTO o_parceiro;
  INSERT INTO public.parceiros (codigo, nome, tipo_parceiro, trilha, status) VALUES ('QA-PGP-IMPL', 'QA Operador', 'implantador', 'operador', 'ativo') RETURNING id INTO o_impl;
  SELECT id INTO v_plano FROM public.plans WHERE code = 'performance';
  UPDATE public.tenants SET parceiro_id = o_parceiro, implantador_parceiro_id = o_impl, originado_em = now() - interval '90 days', ativo = true WHERE id = o_tenant_pub;
  INSERT INTO public.subscriptions (tenant_id, plan_id, status) VALUES (o_tenant_pub, v_plano, 'active')
  ON CONFLICT (tenant_id) DO UPDATE SET plan_id = EXCLUDED.plan_id, status = 'active';
  UPDATE public.subscriptions SET setup_valor_cents = 120000, contrato_assinado_em = CURRENT_DATE - 60,
    primeira_mensalidade_compensada_em = CURRENT_DATE - 50, go_live_homologado_em = CURRENT_DATE - 45,
    terceira_mensalidade_compensada_em = NULL, cancelado_em = NULL, ciclo_inicio = NULL, ciclo_fim = NULL, desconto_pct = 0
  WHERE tenant_id = o_tenant_pub;
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-pgp-' || left(v_uid::text,8) || '@exemplo.test');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, o_tenant_pub, 'QA Owner', true);
  DELETE FROM public.parceiro_comissoes WHERE tenant_id = o_tenant_pub;
  DELETE FROM public.parceiro_mrr_snapshots WHERE tenant_id = o_tenant_pub;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; c record; v_n int; v_p1 bigint; v_p2 bigint; v_esp1 bigint; v_esp2 bigint; v_part numeric; v_p3 int;
BEGIN
  SELECT * INTO c FROM public.qa_pgp_cenario();
  SELECT n.setup_participacao_pct INTO v_part FROM public.parceiros p JOIN public.parceiro_niveis n ON n.id = p.nivel_id WHERE p.id = c.o_parceiro;
  r.passo_ordem := 1; r.passo_acao := 'Fechar duas vezes: Representante nível Foco, setup R$ 1.200, 1ª mensalidade compensada e go-live homologado, 3ª ainda não';
  r.esperado := format('Parcela 1 = 1200 × %s%% × %s%%; parcela 2 = 1200 × %s%% × %s%%; sem parcela 3; sem duplicar', v_part, public.parceiro_cfg('setup_parcela1_pct',30), v_part, public.parceiro_cfg('setup_parcela2_pct',40));
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  PERFORM public.parceiro_fechar_competencia(CURRENT_DATE, false);
  SELECT count(*) INTO v_n FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND tipo = 'setup';
  SELECT valor_cents INTO v_p1 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela1';
  SELECT valor_cents INTO v_p2 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela2';
  SELECT count(*) INTO v_p3 FROM public.parceiro_comissoes WHERE parceiro_id = c.o_parceiro AND tenant_id = c.o_tenant_pub AND evento = 'setup_parcela3';
  v_esp1 := round(120000 * v_part / 100 * public.parceiro_cfg('setup_parcela1_pct',30) / 100);
  v_esp2 := round(120000 * v_part / 100 * public.parceiro_cfg('setup_parcela2_pct',40) / 100);
  IF v_n = 2 AND v_p1 = v_esp1 AND v_p2 = v_esp2 AND v_p3 = 0 THEN
    r.situacao := 'passou'; r.obtido := format('parcela 1 = %s, parcela 2 = %s centavos; parcela 3 aguardando a 3ª mensalidade; sem duplicidade.', v_p1, v_p2);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: %s linha(s) de setup; p1 = %s (esp. %s); p2 = %s (esp. %s); p3 = %s (esp. 0).', v_n, v_p1, v_esp1, v_p2, v_esp2, v_p3);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_trilhas int; v_cfg int; v_le boolean; v_lit boolean;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'AUDITORIA: matriz completa (3 trilhas × 3 níveis com percentual e participação no setup) e parâmetros de setup na config';
  r.esperado := '9 níveis ativos; setup_parcela1/2/3_pct e bonus_retencao_90d_pct configurados';
  SELECT count(*) INTO v_trilhas FROM public.parceiro_niveis WHERE ativo AND trilha IN ('indicador','representante','operador');
  SELECT count(*) INTO v_cfg FROM public.parceiro_programa_config WHERE chave IN ('setup_parcela1_pct','setup_parcela2_pct','setup_parcela3_pct','bonus_retencao_90d_pct','ciclo_meses');
  r.passo_ordem := 2; r.passo_acao := 'AUDITORIA: o motor lê a config e a matriz, não literais';
  r.esperado := 'parceiro_fechar_competencia referencia parceiro_cfg e setup_participacao_pct';
  SELECT (p.prosrc ILIKE '%parceiro_cfg(%' AND p.prosrc ILIKE '%setup_participacao_pct%' AND p.prosrc ILIKE '%parceiro_eventos_remuneracao%') INTO v_le
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'parceiro_fechar_competencia';
  IF v_trilhas >= 9 AND v_cfg = 5 AND coalesce(v_le, false) THEN
    r.situacao := 'passou'; r.obtido := format('%s níveis; %s/5 parâmetros de setup/ciclo; motor lê config, matriz e eventos.', v_trilhas, v_cfg);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: níveis = %s (esp. ≥ 9); config = %s/5; motor lê tabelas = %s.', v_trilhas, v_cfg, v_le);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- PGP-006: níveis por trilha (ajusta o texto do caso para as 3 trilhas)
UPDATE public.qa_casos_teste SET titulo = 'Níveis por trilha (Foco, Visão, Diamante): faixa de MRR, percentual e participação no setup vêm de tabela',
  resultado_esperado = 'Três trilhas com três níveis cada, faixas crescentes, percentuais 6/8/10, 12/15/18 e 20/25/30 pré-preenchidos e editáveis.'
WHERE codigo = 'PGP-006';
UPDATE public.qa_casos_teste SET titulo = 'Setup em três parcelas: liberação contra 1ª mensalidade, go-live homologado e 3ª mensalidade, sem duplicar',
  resultado_esperado = 'Parcelas de 30/40/30 (config) sobre a participação da trilha/nível; Operador fatura direto e não recebe parcela; rodar duas vezes não duplica.'
WHERE codigo = 'PGP-013';

-- Rodapé — reversão dos níveis/eventos, se preciso:
-- UPDATE public.parceiro_niveis n SET nome=b.nome, ordem=b.ordem, mrr_minimo_cents=b.mrr_minimo_cents, percentual_link=b.percentual_link, percentual_casa=b.percentual_casa
--   FROM public.backup_parceiro_niveis_20260904 b WHERE b.id = n.id;
-- DELETE FROM public.parceiro_niveis WHERE id NOT IN (SELECT id FROM public.backup_parceiro_niveis_20260904);
-- INSERT INTO public.parceiro_eventos_remuneracao SELECT * FROM public.backup_parceiro_eventos_20260904 ON CONFLICT DO NOTHING;

-- =====================================================================
-- CONFERÊNCIA FINAL (o editor mostra só este resultado)
-- =====================================================================
WITH n AS MATERIALIZED (SELECT count(*) AS niveis, count(DISTINCT trilha) AS trilhas FROM public.parceiro_niveis WHERE ativo AND trilha IN ('indicador','representante','operador')),
     c AS MATERIALIZED (SELECT count(*) AS n FROM public.parceiro_programa_config),
     v AS MATERIALIZED (SELECT max(versao) AS versao, bool_or(vigente) AS tem_vigente FROM public.parceiro_contratos_versoes),
     f AS MATERIALIZED (SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace WHERE ns.nspname='public' AND p.proname IN
        ('parceiro_cfg','superadmin_parceiro_config_salvar','parceiro_trilha_padrao','superadmin_tenant_programa_salvar','superadmin_tenant_programa','parceiro_base_tenant','parceiro_contrato_render','parceiro_contrato_publico')),
     col AS MATERIALIZED (SELECT count(*) AS n FROM information_schema.columns WHERE table_schema='public' AND table_name='subscriptions' AND column_name IN ('setup_valor_cents','primeira_mensalidade_compensada_em','terceira_mensalidade_compensada_em','go_live_homologado_em','contrato_assinado_em','cancelado_em','desconto_pct')),
     qa AS MATERIALIZED (SELECT (public.qa_caso_pgp_005()).situacao::text AS pgp005)
SELECT CASE WHEN n.niveis = 9 AND n.trilhas = 3 AND c.n >= 40 AND v.versao >= 2 AND v.tem_vigente AND f.n = 8 AND col.n = 7 AND qa.pgp005 = 'passou'
            THEN 'OK — Política v2 do Programa de Parceiros aplicada' ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
       n.niveis || ' níveis / ' || n.trilhas || ' trilhas' AS matriz, c.n AS parametros, 'v' || v.versao AS contrato, f.n || '/8' AS funcoes, col.n || '/7' AS marcos_cliente, qa.pgp005 AS qa_pgp_005, NULL::text AS erro_tecnico
FROM n, c, v, f, col, qa;
