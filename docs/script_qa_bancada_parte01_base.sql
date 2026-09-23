-- ============================================================================
-- ENTREGA — BANCADA DE QA NA PRODUCAO — parte 1 de 15
-- Base — modulos e ferramentas do motor
--
-- POR QUE ESTA TRILHA EXISTE
-- A bancada de testes tem tres camadas: a ROTINA (uma funcao), o CASO
-- DOCUMENTADO (linha em qa_casos_teste) e a PONTE que liga uma a outra
-- (qa_implementacoes). Rotina e estrutura; caso e ponte sao dados. As tres
-- nasceram em migrations, que so alcancam o ambiente de teste — nunca a
-- producao. Resultado medido: a producao documenta 568 casos e executa 268,
-- enquanto o projeto documenta 822 e executa 565.
--
-- Esta trilha leva as tres camadas para a producao. A homologacao herda na
-- proxima copia (as tabelas do motor de QA sao copiadas de la na integra).
--
-- GARANTIAS
--   - Idempotente: rodar duas vezes nao duplica nem quebra.
--   - NAO altera nenhuma regra de negocio. So a bancada que as verifica.
--   - Modulo resolvido pelo CAMINHO, nao pelo identificador interno (os
--     identificadores diferem entre ambientes).
--   - A ponte so e criada quando a rotina existe de fato no destino.
--   - Cada rotina entra em bloco proprio: falha de uma vira NOTICE, nao
--     aborta o arquivo.
--   - O cercado (tenant isolado onde os testes rodam) JA existe na producao —
--     esta trilha nao mexe nele, nem em dado de cliente.
-- Roda inteiro em UMA transacao.
-- ============================================================================

SET lock_timeout = '10s';

-- (1) MODULOS — arvore inteira, resolvida pelo caminho.

WITH d(pai, label, path, icone, ordem, prioridade_doc, status_doc, motivo_bloqueio) AS (VALUES
    (NULL, 'Academia', 'academia', '📚', 10, 8, 'nao_iniciado', NULL),
    (NULL, 'Desenvolvimento & Performance', 'desenvolvimento-performance', '🎓', 4, 5, 'nao_iniciado', NULL),
    (NULL, 'Documentos & Governança', 'documentos-governanca', '📁', 7, 7, 'nao_iniciado', NULL),
    (NULL, 'Estrutura Organizacional', 'estrutura-organizacional', '🏢', 1, 3, 'nao_iniciado', NULL),
    (NULL, 'Financeiro', 'financeiro', '💰', 8, 7, 'nao_iniciado', NULL),
    (NULL, 'Infraestrutura & Auth', 'infraestrutura-auth', '🔧', 12, 2, 'nao_iniciado', NULL),
    (NULL, 'Jornada & Rotina', 'jornada-rotina', '⏰', 5, 1, 'em_andamento', NULL),
    (NULL, 'Pessoas & Cultura', 'pessoas-cultura', '👥', 3, 6, 'nao_iniciado', NULL),
    (NULL, 'Planejamento & Gestão', 'planejamento-gestao', '📊', 2, 8, 'nao_iniciado', NULL),
    (NULL, 'Rede de Parceiros', 'rede-parceiros', '🏪', 9, 8, 'nao_iniciado', NULL),
    (NULL, 'Saúde & Segurança', 'saude-seguranca', '🛡️', 6, 4, 'nao_iniciado', NULL),
    (NULL, 'Segurança de Acesso', 'seguranca-acesso', '🔐', 90, 99, 'nao_iniciado', NULL),
    (NULL, 'Sistema', 'sistema', '⚙️', 11, 8, 'nao_iniciado', NULL),
    ('desenvolvimento-performance', 'Aprendizado & Competências', 'desenvolvimento-performance/aprendizado-competencias', NULL, 1, 5, 'nao_iniciado', NULL),
    ('desenvolvimento-performance', 'Avaliações', 'desenvolvimento-performance/avaliacoes', NULL, 3, 5, 'nao_iniciado', NULL),
    ('desenvolvimento-performance', 'PDI', 'desenvolvimento-performance/pdi', NULL, 4, 5, 'nao_iniciado', NULL),
    ('desenvolvimento-performance', 'Trilhas', 'desenvolvimento-performance/trilhas', NULL, 2, 5, 'nao_iniciado', NULL),
    ('documentos-governanca', 'Documentos', 'documentos-governanca/documentos', NULL, 1, 7, 'nao_iniciado', NULL),
    ('documentos-governanca', 'Hub Contábil', 'documentos-governanca/hub-contabil', NULL, 2, 7, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Cargos', 'estrutura-organizacional/cargos', NULL, 4, 3, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Colaboradores', 'estrutura-organizacional/colaboradores', NULL, 5, 3, 'em_andamento', NULL),
    ('estrutura-organizacional', 'Departamentos', 'estrutura-organizacional/departamentos', NULL, 3, 3, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Empresa', 'estrutura-organizacional/empresa', NULL, 1, 3, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Estabelecimentos / Obras', 'estrutura-organizacional/estabelecimentos', NULL, 2, 3, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Organograma', 'estrutura-organizacional/organograma', NULL, 7, 3, 'nao_iniciado', NULL),
    ('estrutura-organizacional', 'Prestadores de Serviços', 'estrutura-organizacional/prestadores', NULL, 6, 3, 'nao_iniciado', NULL),
    ('financeiro', '13º Salário', 'financeiro/decimo-terceiro', NULL, 0, 1, 'em_andamento', NULL),
    ('financeiro', 'Folha de Pagamento', 'financeiro/folha-pagamento', NULL, 0, 1, 'em_andamento', NULL),
    ('infraestrutura-auth', 'Autenticação & Perfil', 'infraestrutura-auth/autenticacao', NULL, 1, 2, 'nao_iniciado', NULL),
    ('infraestrutura-auth', 'Edge Functions', 'infraestrutura-auth/edge-functions', NULL, 3, 2, 'nao_iniciado', NULL),
    ('infraestrutura-auth', 'Isolamento RLS', 'infraestrutura-auth/rls', NULL, 2, 2, 'nao_iniciado', NULL),
    ('jornada-rotina', 'Afastamentos', 'jornada-rotina/afastamentos', NULL, 4, 1, 'nao_iniciado', NULL),
    ('jornada-rotina', 'Análise de Jornada', 'jornada-rotina/analise-jornada', NULL, 2, 1, 'nao_iniciado', NULL),
    ('jornada-rotina', 'Benefícios', 'jornada-rotina/beneficios', NULL, 6, 1, 'nao_iniciado', NULL),
    ('jornada-rotina', 'Férias', 'jornada-rotina/ferias', NULL, 3, 1, 'documentado', NULL),
    ('jornada-rotina', 'Ponto', 'jornada-rotina/ponto', NULL, 1, 1, 'documentado', NULL),
    ('jornada-rotina', 'Saúde Ocupacional (ASO)', 'jornada-rotina/saude-ocupacional', NULL, 5, 1, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Meu Bem-Estar', 'pessoas-cultura/bem-estar', NULL, 5, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Contratos de Experiência', 'pessoas-cultura/contratos-experiencia', NULL, 2, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Cultura & Celebrações', 'pessoas-cultura/cultura-celebracoes', NULL, 3, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Feedback & Desenvolvimento', 'pessoas-cultura/feedback-desenvolvimento', NULL, 6, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Mural Interno', 'pessoas-cultura/mural-interno', NULL, 4, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Onboarding', 'pessoas-cultura/onboarding', NULL, 1, 6, 'nao_iniciado', NULL),
    ('pessoas-cultura', 'Ouvidoria', 'pessoas-cultura/ouvidoria', NULL, 7, 6, 'nao_iniciado', NULL),
    ('planejamento-gestao', 'Identidade Estratégica', 'planejamento-gestao/identidade-estrategica', NULL, 1, 8, 'nao_iniciado', NULL),
    ('planejamento-gestao', 'Metas', 'planejamento-gestao/metas', NULL, 3, 8, 'nao_iniciado', NULL),
    ('planejamento-gestao', 'Planejamento Estratégico', 'planejamento-gestao/planejamento-estrategico', NULL, 2, 8, 'nao_iniciado', NULL),
    ('planejamento-gestao', 'Plano de Ação', 'planejamento-gestao/plano-de-acao', NULL, 4, 8, 'nao_iniciado', NULL),
    (NULL, 'Admissao', 'rh-dp/admissao', NULL, 0, 99, 'nao_iniciado', NULL),
    (NULL, 'Atestados', 'saude-ocupacional/atestados', NULL, 0, 99, 'nao_iniciado', NULL),
    (NULL, 'EPI', 'saude-ocupacional/epi', NULL, 0, 99, 'nao_iniciado', NULL),
    ('saude-seguranca', 'Compliance SST', 'saude-seguranca/compliance-sst', NULL, 1, 4, 'nao_iniciado', NULL),
    ('saude-seguranca', 'EPIs', 'saude-seguranca/epis', NULL, 4, 4, 'nao_iniciado', NULL),
    ('saude-seguranca', 'Ergonomia', 'saude-seguranca/ergonomia', NULL, 3, 4, 'nao_iniciado', NULL),
    ('saude-seguranca', 'Incidentes & Acidentes', 'saude-seguranca/incidentes-acidentes', NULL, 5, 4, 'nao_iniciado', NULL),
    ('saude-seguranca', 'Psicossocial', 'saude-seguranca/psicossocial', '🧠', 2, 4, 'nao_iniciado', NULL),
    ('seguranca-acesso', 'Perfis de Acesso', 'seguranca-acesso/perfis', NULL, 0, 99, 'nao_iniciado', NULL),
    ('sistema', 'Configurações', 'sistema/configuracoes', NULL, 2, 8, 'nao_iniciado', NULL),
    ('sistema', 'Suporte', 'sistema/suporte', NULL, 1, 8, 'nao_iniciado', NULL),
    ('estrutura-organizacional/colaboradores', 'Admissao', 'estrutura-organizacional/colaboradores/admissao', NULL, 0, 1, 'em_andamento', NULL),
    ('estrutura-organizacional/colaboradores', 'Desligamento', 'estrutura-organizacional/colaboradores/desligamento', NULL, 0, 1, 'em_andamento', NULL),
    ('saude-seguranca/psicossocial', 'Campanhas', 'saude-seguranca/psicossocial/campanhas', NULL, 3, 4, 'nao_iniciado', NULL),
    ('saude-seguranca/psicossocial', 'GHE', 'saude-seguranca/psicossocial/ghe', NULL, 2, 4, 'nao_iniciado', NULL),
    ('saude-seguranca/psicossocial', 'Inventário PGR', 'saude-seguranca/psicossocial/inventario-pgr', NULL, 5, 4, 'nao_iniciado', NULL),
    ('saude-seguranca/psicossocial', 'Metodologia', 'saude-seguranca/psicossocial/metodologia', NULL, 6, 4, 'nao_iniciado', NULL),
    ('saude-seguranca/psicossocial', 'Resultados', 'saude-seguranca/psicossocial/resultados', NULL, 4, 4, 'nao_iniciado', NULL),
    ('saude-seguranca/psicossocial', 'Visão Geral', 'saude-seguranca/psicossocial/visao-geral', NULL, 1, 4, 'nao_iniciado', NULL)
)
INSERT INTO public.qa_modulos (label, path, icone, ordem, prioridade_doc, status_doc, motivo_bloqueio)
SELECT d.label::text, d.path::text, d.icone::text, d.ordem::integer,
       d.prioridade_doc::integer, d.status_doc::text::qa_status_doc, d.motivo_bloqueio::text
FROM d
ON CONFLICT (path) DO UPDATE SET label = EXCLUDED.label, icone = EXCLUDED.icone,
      ordem = EXCLUDED.ordem, prioridade_doc = EXCLUDED.prioridade_doc;

WITH d(pai, path) AS (VALUES
    ('desenvolvimento-performance', 'desenvolvimento-performance/aprendizado-competencias'),
    ('desenvolvimento-performance', 'desenvolvimento-performance/avaliacoes'),
    ('desenvolvimento-performance', 'desenvolvimento-performance/pdi'),
    ('desenvolvimento-performance', 'desenvolvimento-performance/trilhas'),
    ('documentos-governanca', 'documentos-governanca/documentos'),
    ('documentos-governanca', 'documentos-governanca/hub-contabil'),
    ('estrutura-organizacional', 'estrutura-organizacional/cargos'),
    ('estrutura-organizacional', 'estrutura-organizacional/colaboradores'),
    ('estrutura-organizacional', 'estrutura-organizacional/departamentos'),
    ('estrutura-organizacional', 'estrutura-organizacional/empresa'),
    ('estrutura-organizacional', 'estrutura-organizacional/estabelecimentos'),
    ('estrutura-organizacional', 'estrutura-organizacional/organograma'),
    ('estrutura-organizacional', 'estrutura-organizacional/prestadores'),
    ('financeiro', 'financeiro/decimo-terceiro'),
    ('financeiro', 'financeiro/folha-pagamento'),
    ('infraestrutura-auth', 'infraestrutura-auth/autenticacao'),
    ('infraestrutura-auth', 'infraestrutura-auth/edge-functions'),
    ('infraestrutura-auth', 'infraestrutura-auth/rls'),
    ('jornada-rotina', 'jornada-rotina/afastamentos'),
    ('jornada-rotina', 'jornada-rotina/analise-jornada'),
    ('jornada-rotina', 'jornada-rotina/beneficios'),
    ('jornada-rotina', 'jornada-rotina/ferias'),
    ('jornada-rotina', 'jornada-rotina/ponto'),
    ('jornada-rotina', 'jornada-rotina/saude-ocupacional'),
    ('pessoas-cultura', 'pessoas-cultura/bem-estar'),
    ('pessoas-cultura', 'pessoas-cultura/contratos-experiencia'),
    ('pessoas-cultura', 'pessoas-cultura/cultura-celebracoes'),
    ('pessoas-cultura', 'pessoas-cultura/feedback-desenvolvimento'),
    ('pessoas-cultura', 'pessoas-cultura/mural-interno'),
    ('pessoas-cultura', 'pessoas-cultura/onboarding'),
    ('pessoas-cultura', 'pessoas-cultura/ouvidoria'),
    ('planejamento-gestao', 'planejamento-gestao/identidade-estrategica'),
    ('planejamento-gestao', 'planejamento-gestao/metas'),
    ('planejamento-gestao', 'planejamento-gestao/planejamento-estrategico'),
    ('planejamento-gestao', 'planejamento-gestao/plano-de-acao'),
    ('saude-seguranca', 'saude-seguranca/compliance-sst'),
    ('saude-seguranca', 'saude-seguranca/epis'),
    ('saude-seguranca', 'saude-seguranca/ergonomia'),
    ('saude-seguranca', 'saude-seguranca/incidentes-acidentes'),
    ('saude-seguranca', 'saude-seguranca/psicossocial'),
    ('seguranca-acesso', 'seguranca-acesso/perfis'),
    ('sistema', 'sistema/configuracoes'),
    ('sistema', 'sistema/suporte'),
    ('estrutura-organizacional/colaboradores', 'estrutura-organizacional/colaboradores/admissao'),
    ('estrutura-organizacional/colaboradores', 'estrutura-organizacional/colaboradores/desligamento'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/campanhas'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/ghe'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/inventario-pgr'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/metodologia'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/resultados'),
    ('saude-seguranca/psicossocial', 'saude-seguranca/psicossocial/visao-geral')
)
UPDATE public.qa_modulos m SET parent_id = p.id
FROM d JOIN public.qa_modulos p ON p.path = d.pai::text
WHERE m.path = d.path::text AND m.parent_id IS DISTINCT FROM p.id;


-- (2) FERRAMENTAS DO MOTOR — helpers que as rotinas usam em tempo de
--     execucao (qa_cpf, qa_empresa, qa_ponto_dia, o cercado, o disparador
--     da bateria...). Sem elas, uma rotina cria normalmente mas falha ao rodar.

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_afast_legado(p_nome text, p_inicio date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  -- Nasce legítimo: prazo indeterminado pode existir sem data de término.
  v_id := public.qa_afast_novo(p_nome, p_inicio, NULL, true);

  -- Retira a marcação. A guarda de UPDATE só reage quando havia uma data
  -- de término e alguém tenta apagá-la; aqui nunca houve.
  UPDATE public.afastamentos
     SET prazo_indeterminado = false,
         status_geral_new    = 'registrado'
   WHERE id = v_id;

  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_afast_legado(p_nome text, p_inicio date)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_afast_legado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_afast_novo(p_nome text, p_inicio date, p_fim date, p_prazo_indeterminado boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, prazo_indeterminado)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(9101),
          p_inicio, p_fim, 'ativo', p_prazo_indeterminado)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_afast_novo(p_nome text, p_inicio date, p_fim date, p_prazo_indeterminado boolean)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_afast_novo nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_afast_tipado(p_nome text, p_semente integer, p_inicio date, p_fim date, p_tipo text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.afastamentos
    (tenant_id, colaborador_nome, colaborador_cpf, data_inicio, data_fim,
     status, tipo_principal_new)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, public.qa_cpf(p_semente),
          p_inicio, p_fim, 'ativo', p_tipo::public.afastamento_tipo_principal)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_afast_tipado(p_nome text, p_semente integer, p_inicio date, p_fim date, p_tipo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_afast_tipado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_ler_dias()
 RETURNS TABLE(dia_semana integer, dia_nome text, ligado boolean, hora integer, minuto integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.dia_semana,
         (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[d.dia_semana + 1],
         d.ligado, d.hora, d.minuto
  FROM public.qa_agendamento_e2e_dias d
  WHERE public.is_superadmin(auth.uid())
  ORDER BY d.dia_semana;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_e2e_ler_dias()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_e2e_ler_dias nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_proxima()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_char(min(prox), 'DD/MM (Dy) HH24:MI')
  FROM (
    SELECT
      date_trunc('day', v_now)
        + make_interval(days =>
            ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7
            + CASE
                WHEN ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7 = 0
                     AND make_time(d.hora, d.minuto, 0) <= v_now::time
                THEN 7 ELSE 0 END)
        + make_interval(hours => d.hora, mins => d.minuto) AS prox
    FROM public.qa_agendamento_e2e_dias d,
         (SELECT timezone('America/Sao_Paulo', now()) AS v_now) t
    WHERE d.ligado AND public.is_superadmin(auth.uid())
  ) x;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_e2e_proxima()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_e2e_proxima nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_e2e_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_dia NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Dia invalido: %.', p_dia;
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento_e2e_dias
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto
  WHERE dia_semana = p_dia;

  RETURN public.qa_cron_sincronizar_e2e();
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_e2e_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_e2e_salvar_dia nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_ler()
 RETURNS TABLE(ligado boolean, hora integer, minuto integer, modulo_path text, proxima_execucao text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
  SELECT a.ligado, a.hora, a.minuto, a.modulo_path,
         (SELECT to_char(
            (CURRENT_DATE + CASE WHEN make_time(a.hora,a.minuto,0) > CURRENT_TIME
                                 THEN 0 ELSE 1 END)::timestamp
            + make_interval(hours => a.hora, mins => a.minuto),
            'DD/MM HH24:MI')
          WHERE a.ligado)
  FROM public.qa_agendamento a
  WHERE a.id = 1 AND public.is_superadmin(auth.uid());
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_ler()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_ler nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_ler_dias()
 RETURNS TABLE(dia_semana integer, dia_nome text, ligado boolean, hora integer, minuto integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT d.dia_semana,
         (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[d.dia_semana + 1],
         d.ligado, d.hora, d.minuto
  FROM public.qa_agendamento_dias d
  WHERE public.is_superadmin(auth.uid())
  ORDER BY d.dia_semana;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_ler_dias()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_ler_dias nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_proxima()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_char(min(prox), 'DD/MM (Dy) HH24:MI')
  FROM (
    SELECT
      date_trunc('day', v_now)
        + make_interval(days =>
            ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7
            + CASE
                WHEN ((d.dia_semana - extract(dow from v_now)::int) + 7) % 7 = 0
                     AND make_time(d.hora, d.minuto, 0) <= v_now::time
                THEN 7 ELSE 0 END)
        + make_interval(hours => d.hora, mins => d.minuto) AS prox
    FROM public.qa_agendamento_dias d,
         (SELECT timezone('America/Sao_Paulo', now()) AS v_now) t
    WHERE d.ligado AND public.is_superadmin(auth.uid())
  ) x;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_proxima()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_proxima nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_salvar(p_ligado boolean, p_hora integer, p_minuto integer, p_modulo text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto,
      modulo_path = p_modulo, atualizado_em = now(),
      atualizado_por = (SELECT id FROM public.usuarios_base WHERE auth_user_id = auth.uid() LIMIT 1)
  WHERE id = 1;

  -- aplica no cron imediatamente
  RETURN public.qa_cron_sincronizar();
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_salvar(p_ligado boolean, p_hora integer, p_minuto integer, p_modulo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_salvar nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_agendamento_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;
  IF p_dia NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Dia invalido: %.', p_dia;
  END IF;
  IF p_hora NOT BETWEEN 0 AND 23 OR p_minuto NOT BETWEEN 0 AND 59 THEN
    RAISE EXCEPTION 'Horario invalido: %:%.', p_hora, p_minuto;
  END IF;

  UPDATE public.qa_agendamento_dias
  SET ligado = p_ligado, hora = p_hora, minuto = p_minuto
  WHERE dia_semana = p_dia;

  RETURN public.qa_cron_sincronizar();
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_agendamento_salvar_dia(p_dia integer, p_ligado boolean, p_hora integer, p_minuto integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_agendamento_salvar_dia nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_anexar_print_e2e(p_execucao_id uuid, p_spec text, p_teste text, p_evidencia_png text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_codigo text;
  v_n      int;
BEGIN
  IF p_evidencia_png IS NULL OR btrim(p_evidencia_png) = '' THEN
    RETURN false;
  END IF;

  -- O reporter conhece (spec, teste), não o código do caso — a ligação
  -- vive no banco. Resolve aqui, do mesmo jeito que a gravação faz.
  SELECT e.codigo INTO v_codigo
  FROM public.qa_cobertura_e2e e
  WHERE e.ativo AND e.spec = p_spec AND e.teste = p_teste;

  IF v_codigo IS NULL THEN
    RETURN false; -- teste sem caso documentado: não há linha para anexar
  END IF;

  UPDATE public.qa_resultados
  SET evidencia_png = p_evidencia_png
  WHERE execucao_id = p_execucao_id AND codigo = v_codigo;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_anexar_print_e2e(p_execucao_id uuid, p_spec text, p_teste text, p_evidencia_png text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_anexar_print_e2e nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_assert_sandbox(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_sandbox uuid;
BEGIN
  v_sandbox := public.qa_sandbox_tenant_id();

  IF v_sandbox IS NULL THEN
    RAISE EXCEPTION 'QA ABORTADO: o cercado de teste (slug qa-sandbox) nao existe.';
  END IF;

  IF p_tenant_id IS NULL OR p_tenant_id <> v_sandbox THEN
    RAISE EXCEPTION
      'QA ABORTADO: tentativa de escrever FORA do cercado. Alvo: %, permitido: %. Nenhuma alteracao foi feita.',
      COALESCE(p_tenant_id::text,'(nulo)'), v_sandbox;
  END IF;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_assert_sandbox(p_tenant_id uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_assert_sandbox nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_bloqueia_fora_do_cercado()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tenant  uuid;
  v_s1 uuid; v_s2 uuid;
BEGIN
  IF COALESCE(current_setting('app.qa_modo', true), 'off') <> 'on' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN v_tenant := (to_jsonb(OLD) ->> 'tenant_id')::uuid;
  ELSE v_tenant := (to_jsonb(NEW) ->> 'tenant_id')::uuid; END IF;

  v_s1 := public.qa_sandbox_tenant_id();
  SELECT id INTO v_s2 FROM public.tenants WHERE slug = 'qa-sandbox-2';

  IF v_tenant IS DISTINCT FROM v_s1 AND v_tenant IS DISTINCT FROM v_s2 THEN
    RAISE EXCEPTION
      'QA BLOQUEADO: modo de teste ligado. Operacao % em %.% tentou tocar o tenant %. Permitido apenas os cercados. Transacao abortada.',
      TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, COALESCE(v_tenant::text,'(nulo)');
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_bloqueia_fora_do_cercado()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_bloqueia_fora_do_cercado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_caso_detalhe(p_codigo text)
 RETURNS TABLE(campo text, conteudo text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'codigo',      ct.codigo             FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'titulo',     ct.titulo    FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'prioridade', ct.prioridade::text FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'nivel',      ct.nivel     FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'base_legal', COALESCE(ct.base_legal,'(regra de produto, sem base legal)')
                                              FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'objetivo',   COALESCE(ct.objetivo,'') FROM public.qa_casos_teste ct WHERE ct.codigo = p_codigo
  UNION ALL SELECT 'achado', COALESCE((
              SELECT r.obtido FROM public.qa_resultados r
              JOIN public.qa_execucoes e ON e.id = r.execucao_id
              WHERE r.codigo = p_codigo
              ORDER BY e.iniciada_em DESC LIMIT 1),
            '(sem execucao registrada)')
  ORDER BY 1;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_caso_detalhe(p_codigo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_caso_detalhe nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_cercas_faltando()
 RETURNS TABLE(tabela text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT col.table_name::text
  FROM information_schema.columns col
  JOIN information_schema.tables t
    ON t.table_schema = col.table_schema AND t.table_name = col.table_name
  WHERE col.table_schema = 'public'
    AND col.column_name  = 'tenant_id'
    AND t.table_type     = 'BASE TABLE'
    AND col.table_name NOT LIKE 'qa\_%'
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(col.table_name))::regclass
        AND NOT tg.tgisinternal)
  ORDER BY 1;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_cercas_faltando()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_cercas_faltando nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_col_existe(p_tabela text, p_col_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT string_agg(table_name || '.' || column_name, ', ')
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND (p_tabela IS NULL OR table_name = p_tabela)
    AND column_name ILIKE p_col_padrao;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_col_existe(p_tabela text, p_col_padrao text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_col_existe nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_coluna_existe(p_tabela text, p_coluna text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_tabela AND column_name = p_coluna);
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_coluna_existe(p_tabela text, p_coluna text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_coluna_existe nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_conferir_seguranca()
 RETURNS TABLE(item text, situacao text, detalhe text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sandbox uuid;
  v_sandbox2 uuid;
  v_modo boolean;
  v_protegidas int;
  v_escritas int;
  v_sem_trava text;
  v_vazamento int;
  v_rotinas int;
  v_casos int;
BEGIN
  -- ── 1. o cercado existe? ──
  v_sandbox  := public.qa_sandbox_tenant_id();
  v_sandbox2 := public.qa_sandbox2_tenant_id();

  IF v_sandbox IS NULL THEN
    RETURN QUERY SELECT
      'Cercado principal'::text, 'FALHA'::text,
      'O tenant de teste nao existe. Nenhuma bateria pode rodar com seguranca.'::text;
  ELSE
    RETURN QUERY SELECT
      'Cercado principal'::text, 'ok'::text,
      format('Existe (%s). Todos os dados de teste sao criados nele.', v_sandbox)::text;
  END IF;

  IF v_sandbox2 IS NULL THEN
    RETURN QUERY SELECT
      'Cercado secundario'::text, 'atencao'::text,
      'Nao existe. Os casos de isolamento entre clientes nao conseguem rodar.'::text;
  ELSE
    RETURN QUERY SELECT
      'Cercado secundario'::text, 'ok'::text,
      'Existe. Usado para provar que um cliente nao enxerga o outro.'::text;
  END IF;

  -- ── 2. o modo de teste esta desligado? ──
  BEGIN
    SELECT current_setting('qa.modo_teste', true) = 'on' INTO v_modo;
  EXCEPTION WHEN OTHERS THEN
    v_modo := false;
  END;

  IF COALESCE(v_modo, false) THEN
    RETURN QUERY SELECT
      'Modo de teste'::text, 'atencao'::text,
      'LIGADO nesta sessao. Fora de uma bateria em execucao, deveria estar desligado.'::text;
  ELSE
    RETURN QUERY SELECT
      'Modo de teste'::text, 'ok'::text,
      'Desligado, como esperado fora de uma bateria.'::text;
  END IF;

  -- ── 3. as tabelas escritas pelas rotinas tem trava? ──
  SELECT count(*) INTO v_protegidas
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE tg.tgname = 'qa_guarda_cercado' AND n.nspname = 'public' AND NOT tg.tgisinternal;

  -- tabelas do sistema que aparecem em INSERT/UPDATE/DELETE dentro de funcoes qa_*
  WITH corpo AS (
    SELECT p.proname, pg_get_functiondef(p.oid) AS def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE 'qa\_%'
  ),
  tocadas AS (
    SELECT DISTINCT lower((regexp_matches(
             def, '(?:INSERT INTO|UPDATE|DELETE FROM)\s+public\.(\w+)', 'gi'))[1]) AS tabela
    FROM corpo
  ),
  protegidas AS (
    SELECT c.relname AS tabela
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE tg.tgname = 'qa_guarda_cercado' AND n.nspname = 'public' AND NOT tg.tgisinternal
  )
  SELECT count(*), string_agg(t.tabela, ', ' ORDER BY t.tabela)
    INTO v_escritas, v_sem_trava
  FROM tocadas t
  WHERE t.tabela NOT LIKE 'qa\_%'
    AND t.tabela NOT IN (SELECT tabela FROM protegidas);

  IF COALESCE(v_escritas, 0) = 0 THEN
    RETURN QUERY SELECT
      'Travas do cercado'::text, 'ok'::text,
      format('%s tabelas protegidas. Toda tabela escrita pelas rotinas tem a trava.', v_protegidas)::text;
  ELSE
    RETURN QUERY SELECT
      'Travas do cercado'::text, 'FALHA'::text,
      format('%s tabela(s) escrita(s) por rotinas SEM trava: %s. Rode o SQL de instalacao da trava.',
             v_escritas, v_sem_trava)::text;
  END IF;

  -- ── 4. algum dado de teste vazou para fora do cercado? ──
  SELECT count(*) INTO v_vazamento
  FROM public.empresa_cadastro
  WHERE razao_social LIKE '[QA]%'
    AND tenant_id <> v_sandbox
    AND (v_sandbox2 IS NULL OR tenant_id <> v_sandbox2);

  IF v_vazamento = 0 THEN
    RETURN QUERY SELECT
      'Dados de teste fora do cercado'::text, 'ok'::text,
      'Nenhum registro marcado como [QA] existe fora do ambiente de teste.'::text;
  ELSE
    RETURN QUERY SELECT
      'Dados de teste fora do cercado'::text, 'FALHA'::text,
      format('%s registro(s) [QA] encontrado(s) em tenant de cliente. Investigar e remover.',
             v_vazamento)::text;
  END IF;

  -- ── 5. o inventario de casos e rotinas ──
  SELECT count(*) INTO v_casos   FROM public.qa_casos_teste;
  SELECT count(*) INTO v_rotinas FROM public.qa_implementacoes WHERE ativo;

  RETURN QUERY SELECT
    'Inventario'::text, 'ok'::text,
    format('%s casos documentados, %s com rotina executavel.', v_casos, v_rotinas)::text;

END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_conferir_seguranca()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_conferir_seguranca nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_cpf(p_semente integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_base text;
  v_d    int[];
  v_soma int;
  v_dv1  int;
  v_dv2  int;
  i      int;
BEGIN
  -- Base de 9 dígitos: prefixo 999 mantém a fixture reconhecível como teste.
  v_base := '999' || lpad((abs(p_semente) % 1000000)::text, 6, '0');

  SELECT array_agg(substring(v_base FROM g FOR 1)::int ORDER BY g)
    INTO v_d FROM generate_series(1, 9) g;

  -- 1º dígito: soma dos 9 primeiros por pesos de 10 a 2
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (11 - i); END LOOP;
  v_dv1 := 11 - (v_soma % 11);
  IF v_dv1 >= 10 THEN v_dv1 := 0; END IF;

  -- 2º dígito: soma dos 10 primeiros por pesos de 11 a 2
  v_soma := 0;
  FOR i IN 1..9 LOOP v_soma := v_soma + v_d[i] * (12 - i); END LOOP;
  v_soma := v_soma + v_dv1 * 2;
  v_dv2 := 11 - (v_soma % 11);
  IF v_dv2 >= 10 THEN v_dv2 := 0; END IF;

  RETURN v_base || v_dv1::text || v_dv2::text;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_cpf(p_semente integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_cpf nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_cpf_formatado(p_cpf text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT format('%s.%s.%s-%s',
                substr(p_cpf,1,3), substr(p_cpf,4,3), substr(p_cpf,7,3), substr(p_cpf,10,2))
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_cpf_formatado(p_cpf text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_cpf_formatado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_cron_sincronizar()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
DECLARE
  d record;
  v_utc timestamptz;
  v_hora_utc int;
  v_min_utc int;
  v_dow_utc int;
  v_ligados int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;

  PERFORM cron.unschedule(jobname)
  FROM cron.job
  WHERE jobname = 'qa-bateria-agendada' OR jobname LIKE 'qa-bateria-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_dias WHERE ligado ORDER BY dia_semana
  LOOP
    -- Converte o horario/dia escolhido (Brasil) para UTC, que e o que o cron usa.
    -- Ancoramos numa data qualquer que caia no dia da semana desejado.
    -- 2024-01-07 e um domingo (dow=0); somamos d.dia_semana para chegar no dia.
    v_utc := (
      (date '2024-01-07' + d.dia_semana)::timestamp
      + make_interval(hours => d.hora, mins => d.minuto)
    ) AT TIME ZONE 'America/Sao_Paulo';   -- interpreta como horario de SP -> vira timestamptz UTC

    v_hora_utc := extract(hour   from v_utc AT TIME ZONE 'UTC')::int;
    v_min_utc  := extract(minute from v_utc AT TIME ZONE 'UTC')::int;
    v_dow_utc  := extract(dow    from v_utc AT TIME ZONE 'UTC')::int;

    PERFORM cron.schedule(
      'qa-bateria-dia-' || d.dia_semana,
      format('%s %s * * %s', v_min_utc, v_hora_utc, v_dow_utc),
      $cmd$SELECT public.qa_rodar_agendada()$cmd$
    );
    v_ligados := v_ligados + 1;
  END LOOP;

  IF v_ligados = 0 THEN
    RETURN 'Nenhum dia agendado. O robo so roda manualmente.';
  END IF;
  RETURN format('%s dia(s) agendado(s), no seu horario (Brasilia).', v_ligados);
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_cron_sincronizar()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_cron_sincronizar nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_cron_sincronizar_e2e()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
DECLARE
  d record;
  v_utc timestamptz;
  v_ligados int := 0;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode configurar o agendamento.';
  END IF;

  PERFORM cron.unschedule(jobname)
  FROM cron.job
  WHERE jobname LIKE 'qa-e2e-dia-%';

  FOR d IN SELECT * FROM public.qa_agendamento_e2e_dias WHERE ligado ORDER BY dia_semana
  LOOP
    -- 2024-01-07 é um domingo (dow=0); somamos d.dia_semana p/ chegar no dia.
    v_utc := (
      (date '2024-01-07' + d.dia_semana)::timestamp
      + make_interval(hours => d.hora, mins => d.minuto)
    ) AT TIME ZONE 'America/Sao_Paulo';   -- horário de SP -> timestamptz (UTC)

    PERFORM cron.schedule(
      'qa-e2e-dia-' || d.dia_semana,
      format('%s %s * * %s',
             extract(minute from v_utc AT TIME ZONE 'UTC')::int,
             extract(hour   from v_utc AT TIME ZONE 'UTC')::int,
             extract(dow    from v_utc AT TIME ZONE 'UTC')::int),
      $cmd$SELECT public.qa_e2e_disparar_esteira()$cmd$
    );
    v_ligados := v_ligados + 1;
  END LOOP;

  IF v_ligados = 0 THEN
    RETURN 'Nenhum dia agendado. A suíte só roda quando você publica uma mudança.';
  END IF;
  RETURN format('%s dia(s) agendado(s), no seu horário (Brasília).', v_ligados);
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_cron_sincronizar_e2e()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_cron_sincronizar_e2e nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_dia_util_passado(p_atras integer DEFAULT 7)
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  SELECT d::date FROM generate_series(CURRENT_DATE - p_atras, CURRENT_DATE - 1, interval '1 day') d
  WHERE EXTRACT(ISODOW FROM d) BETWEEN 1 AND 5
  ORDER BY d LIMIT 1
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_dia_util_passado(p_atras integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_dia_util_passado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_disparar_bateria(p_modulo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE v_exec uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Apenas superadmin pode disparar a bateria de testes.';
  END IF;

  v_exec := public.qa_rodar_bateria('manual', p_modulo);

  UPDATE public.qa_execucoes
  SET disparada_por = (SELECT id FROM public.usuarios_base WHERE auth_user_id = auth.uid() LIMIT 1)
  WHERE id = v_exec;

  RETURN v_exec;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_disparar_bateria(p_modulo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_disparar_bateria nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_e2e_disparar_esteira()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token    text;
  v_repo     text;
  v_workflow text;
  v_ref      text;
BEGIN
  SELECT valor INTO v_token    FROM public.app_config WHERE chave = 'github_dispatch_token';
  SELECT valor INTO v_repo     FROM public.app_config WHERE chave = 'github_dispatch_repo';
  SELECT valor INTO v_workflow FROM public.app_config WHERE chave = 'github_dispatch_workflow';
  SELECT valor INTO v_ref      FROM public.app_config WHERE chave = 'github_dispatch_ref';

  -- Proteção de ambiente: sem token, não chama ninguém (avisa no log).
  IF v_token IS NULL OR btrim(v_token) = '' THEN
    RAISE NOTICE 'qa_e2e_disparar_esteira: app_config sem github_dispatch_token — nenhuma corrida disparada (proteção de ambiente).';
    RETURN;
  END IF;

  -- Padrões públicos (o repo/workflow já aparecem no código do painel e
  -- na esteira); só o token é segredo. Podem ser sobrescritos por app_config.
  v_repo     := COALESCE(NULLIF(btrim(v_repo),     ''), 'YourEyes-dev/youreyesnovo');
  v_workflow := COALESCE(NULLIF(btrim(v_workflow), ''), 'staging.yml');
  v_ref      := COALESCE(NULLIF(btrim(v_ref),      ''), 'main');

  PERFORM net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches',
                  v_repo, v_workflow),
    headers := jsonb_build_object(
      'Accept',               'application/vnd.github+json',
      'Authorization',        'Bearer ' || v_token,
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent',           'youreyes-qa-esteira',
      'Content-Type',         'application/json'
    ),
    body := jsonb_build_object('ref', v_ref)
  );

  RAISE NOTICE 'qa_e2e_disparar_esteira: pedido de corrida enviado à esteira (% / % @ %).',
    v_repo, v_workflow, v_ref;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_e2e_disparar_esteira()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_e2e_disparar_esteira nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_empresa(p_nome text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM public.empresa_cadastro
  WHERE tenant_id = public.qa_sandbox_tenant_id() AND nome_fantasia = p_nome
  LIMIT 1
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_empresa(p_nome text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_empresa nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_empresa_com_cota(p_nome text, p_cnpj text, p_total integer DEFAULT NULL::integer, p_pct numeric DEFAULT NULL::numeric, p_exigida integer DEFAULT NULL::integer, p_atual integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, cnpj, total_colaboradores,
     pcd_obrigatoria, pcd_percentual_exigido, pcd_quantidade_exigida, pcd_quantidade_atual)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, p_cnpj, COALESCE(p_total,0),
          COALESCE(p_total,0) >= 100, COALESCE(p_pct,0), COALESCE(p_exigida,0), COALESCE(p_atual,0))
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_empresa_com_cota(p_nome text, p_cnpj text, p_total integer, p_pct numeric, p_exigida integer, p_atual integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_empresa_com_cota nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_empresa_com_ponto(p_nome text, p_cnpj text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  v_id := public.qa_nova_empresa(p_nome, p_cnpj);
  UPDATE public.empresa_cadastro SET usa_controle_ponto = true WHERE id = v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_empresa_com_ponto(p_nome text, p_cnpj text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_empresa_com_ponto nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_executar_descartavel(p_funcao text)
 RETURNS qa_retorno
 LANGUAGE plpgsql
AS $function$
DECLARE
  r public.qa_retorno;
BEGIN
  -- A rotina nao precisa lembrar de nada. O funil liga.
  PERFORM public.qa_modo_ligar();
  -- E confere que ligou mesmo. Falha fechada.
  PERFORM public.qa_exigir_modo();

  BEGIN
    EXECUTE format('SELECT * FROM public.%I()', p_funcao) INTO r;
    RAISE EXCEPTION USING ERRCODE = 'QA000', MESSAGE = 'QA_DESCARTE';
  EXCEPTION
    WHEN SQLSTATE 'QA000' THEN
      NULL;  -- caminho normal: os dados de teste ja foram desfeitos
    WHEN OTHERS THEN
      r.situacao     := 'erro';
      r.obtido       := 'A rotina quebrou. Nenhum dado ficou na base.';
      r.erro_tecnico := SQLERRM || ' [' || SQLSTATE || ']';
  END;

  IF r.situacao IS NULL THEN
    r.situacao := 'erro';
    r.obtido   := 'A rotina nao devolveu veredito.';
  END IF;

  RETURN r;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_executar_descartavel(p_funcao text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_executar_descartavel nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_exigir_modo()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  IF COALESCE(current_setting('app.qa_modo', true), 'off') <> 'on' THEN
    RAISE EXCEPTION
      'QA ABORTADO: modo de teste desligado. A trava do cercado estaria inerte e a rotina poderia escrever em cliente real. Nada foi executado.';
  END IF;
  IF public.qa_sandbox_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'QA ABORTADO: o cercado nao existe.';
  END IF;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_exigir_modo()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_exigir_modo nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_feriado_da_unidade(p_empresa_id uuid, p_data date, p_nome text DEFAULT '[QA] Feriado de Teste'::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := public.qa_sandbox_tenant_id(); v_tab uuid;
BEGIN
  INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
  VALUES (v_t, p_nome || ' ' || p_data, 'SP', 'São Paulo', EXTRACT(YEAR FROM p_data)::int, true)
  RETURNING id INTO v_tab;
  INSERT INTO public.feriado_tabela_itens (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
  VALUES (v_t, v_tab, p_nome, p_data, false, 'feriado', true);
  INSERT INTO public.feriado_tabela_empresas (tenant_id, tabela_id, empresa_id)
  VALUES (v_t, v_tab, p_empresa_id);
  RETURN v_tab;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_feriado_da_unidade(p_empresa_id uuid, p_data date, p_nome text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_feriado_da_unidade nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ferias_periodo(p_cpf text, p_nome text, p_faltas integer DEFAULT 0, p_aquisitivo_fim date DEFAULT (CURRENT_DATE - 30))
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_direito int := public.ferias_dias_por_faltas_clt(p_faltas);
BEGIN
  INSERT INTO public.ferias_periodos_aquisitivos
    (tenant_id, colaborador_cpf, colaborador_nome, data_admissao,
     aquisitivo_inicio, aquisitivo_fim, faltas_carga, dias_gozados,
     fonte_faltas, dias_direito, dias_saldo, faltas_consideradas, status, origem)
  VALUES (public.qa_sandbox_tenant_id(), p_cpf, p_nome,
          p_aquisitivo_fim - interval '1 year',
          p_aquisitivo_fim - interval '1 year', p_aquisitivo_fim,
          p_faltas, 0, 'carga', v_direito, v_direito, p_faltas, 'ativo', 'sistema')
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ferias_periodo(p_cpf text, p_nome text, p_faltas integer, p_aquisitivo_fim date)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ferias_periodo nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_fixture_email(p_codigo text, p_n integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT 'qa.' || lower(replace(p_codigo, '-', '')) || '.' || p_n || '@sandbox.invalid'
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_fixture_email(p_codigo text, p_n integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_fixture_email nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_fixture_limpar(p_codigo text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_tenant uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_modo_ligar();
  -- usuario_vinculos tem ON DELETE CASCADE a partir de usuarios_base
  DELETE FROM public.usuarios_base
  WHERE tenant_id = v_tenant
    AND email_principal LIKE 'qa.' || lower(replace(p_codigo, '-', '')) || '.%@sandbox.invalid';
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_fixture_limpar(p_codigo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_fixture_limpar nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_fns_com(p_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT string_agg(p.proname, ', ')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname NOT LIKE 'qa\_%'
    AND p.prosrc ILIKE p_padrao;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_fns_com(p_padrao text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_fns_com nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_houve_vazamento()
 RETURNS boolean
 LANGUAGE sql
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.qa_verifica_vazamento() v
    WHERE v.veredito LIKE '>>>%'
  );
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_houve_vazamento()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_houve_vazamento nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_instalar_cercas()
 RETURNS TABLE(nome_tabela text, acao text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  c        record;
  v_tinha  boolean;
  v_novas  int := 0;
  v_ja     int := 0;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
    RAISE EXCEPTION 'qa_bloqueia_fora_do_cercado() nao existe — rode as migrations do cercado antes.';
  END IF;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'   -- as tabelas do proprio QA ficam de fora
    ORDER BY col.table_name
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger tg
      WHERE tg.tgname = 'qa_guarda_cercado'
        AND tg.tgrelid = ('public.' || quote_ident(c.table_name))::regclass
        AND NOT tg.tgisinternal
    ) INTO v_tinha;

    IF NOT v_tinha THEN
      EXECUTE format(
        'CREATE TRIGGER qa_guarda_cercado
           BEFORE INSERT OR UPDATE OR DELETE ON public.%I
           FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()',
        c.table_name);
      v_novas := v_novas + 1;
      nome_tabela := c.table_name; acao := 'trava instalada'; RETURN NEXT;
    ELSE
      v_ja := v_ja + 1;
    END IF;

    -- ON CONFLICT nomeando a coluna colidiria com o parametro de saida.
    INSERT INTO public.qa_tabelas_protegidas AS p (tabela, motivo)
    SELECT c.table_name, 'Cerca generica: tabela tem tenant_id'
    WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x
                      WHERE x.tabela = c.table_name);
  END LOOP;

  nome_tabela := format('%s tabela(s) ja protegida(s), %s nova(s)', v_ja, v_novas);
  acao        := 'resumo';
  RETURN NEXT;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_instalar_cercas()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_instalar_cercas nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_limpa_config_metas(p_tenant uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  DELETE FROM public.metas_configuracao WHERE tenant_id = p_tenant;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_limpa_config_metas(p_tenant uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_limpa_config_metas nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_limpa_identidade(p_tenant uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  DELETE FROM public.estrategia_cultura WHERE tenant_id = p_tenant;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_limpa_identidade(p_tenant uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_limpa_identidade nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_limpar_historico(p_dias integer DEFAULT 90)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_n int;
BEGIN
  WITH alvo AS (
    SELECT id FROM public.qa_execucoes
    WHERE iniciada_em < now() - make_interval(days => p_dias)
      AND falhou = 0 AND erro = 0        -- bateria que achou algo fica para sempre
  )
  DELETE FROM public.qa_execucoes e USING alvo a WHERE e.id = a.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;       -- qa_resultados cai por CASCADE
  RETURN v_n;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_limpar_historico(p_dias integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_limpar_historico nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_listar_baterias(p_limite integer DEFAULT 20)
 RETURNS TABLE(id uuid, iniciada_em timestamp with time zone, disparo text, modulo_path text, total integer, passou integer, falhou integer, nao_implementado integer, erro integer, duracao_ms integer, observacao text, disparada_por_nome text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT e.id, e.iniciada_em, e.disparo::text, e.modulo_path,
         e.total, e.passou, e.falhou, e.nao_implementado, e.erro,
         e.duracao_ms, e.observacao, u.nome_completo
  FROM public.qa_execucoes e
  LEFT JOIN public.usuarios_base u ON u.id = e.disparada_por
  WHERE public.is_superadmin(auth.uid())
  ORDER BY e.iniciada_em DESC
  LIMIT p_limite;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_listar_baterias(p_limite integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_listar_baterias nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_mobiliario_registrar()
 RETURNS TABLE(tabela text, esperado bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t uuid := public.qa_sandbox_tenant_id();
  c   record;
  v_n bigint;
BEGIN
  IF v_t IS NULL THEN
    RAISE EXCEPTION 'Cercado nao existe. Nao da para medir a linha de base.';
  END IF;

  -- WHERE true pelo mesmo motivo do detector: safeupdate nos papeis da API.
  DELETE FROM public.qa_mobiliario_fixo WHERE true;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
    ORDER BY col.table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = $1', c.table_name)
      INTO v_n USING v_t;

    IF v_n > 0 THEN
      INSERT INTO public.qa_mobiliario_fixo (tabela, esperado, motivo)
      VALUES (c.table_name, v_n, 'Medido com o cercado em repouso');
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT m.tabela, m.esperado FROM public.qa_mobiliario_fixo m ORDER BY m.tabela;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_mobiliario_registrar()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_mobiliario_registrar nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_modo_ligado()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$ SELECT COALESCE(current_setting('app.qa_modo', true), 'off') = 'on' $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_modo_ligado()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_modo_ligado nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_modo_ligar()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM set_config('app.qa_modo', 'on', true);  -- true = morre com a transação
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_modo_ligar()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_modo_ligar nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_modulos_testaveis()
 RETURNS TABLE(modulo_path text, label text, casos_executaveis bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.path, m.label, count(*)
  FROM public.qa_casos_teste c
  JOIN public.qa_modulos m ON m.id = c.modulo_id
  JOIN public.qa_implementacoes i ON i.codigo = c.codigo AND i.ativo
  WHERE c.status = 'aprovado'
    AND public.is_superadmin(auth.uid())
  GROUP BY m.path, m.label
  ORDER BY m.path;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_modulos_testaveis()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_modulos_testaveis nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_acao(p_titulo text, p_codigo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid; v_cod text;
BEGIN
  v_cod := COALESCE(p_codigo, 'QA-' || substr(gen_random_uuid()::text, 1, 8));
  INSERT INTO public.plano_acoes (tenant_id, codigo, titulo, origem_modulo)
  VALUES (public.qa_sandbox_tenant_id(), v_cod, p_titulo, 'manual') RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_acao(p_titulo text, p_codigo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_acao nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_competencia(p_comp text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.hub_competencias (tenant_id, competencia)
  VALUES (public.qa_sandbox_tenant_id(), p_comp) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_competencia(p_comp text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_competencia nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_condicao(p_nome text, p_insal boolean DEFAULT false, p_grau text DEFAULT NULL::text, p_val_insal numeric DEFAULT 0, p_peric boolean DEFAULT false, p_val_peric numeric DEFAULT 0, p_aplicado text DEFAULT NULL::text, p_val_aplicado numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.colaborador_condicoes_especiais
    (tenant_id, colaborador_id, colaborador_nome,
     insalubridade, insalubridade_grau, insalubridade_valor_calculado,
     periculosidade, periculosidade_valor_calculado,
     adicional_aplicado, adicional_valor_aplicado)
  VALUES (public.qa_sandbox_tenant_id(), '52998224725', p_nome,
          p_insal, p_grau, p_val_insal, p_peric, p_val_peric, p_aplicado, p_val_aplicado)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_condicao(p_nome text, p_insal boolean, p_grau text, p_val_insal numeric, p_peric boolean, p_val_peric numeric, p_aplicado text, p_val_aplicado numeric)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_condicao nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_empresa(p_razao text, p_cnpj text, p_ativo boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_cadastro (tenant_id, razao_social, nome_fantasia, cnpj, ativo)
  VALUES (public.qa_sandbox_tenant_id(), p_razao, p_razao, p_cnpj, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_empresa(p_razao text, p_cnpj text, p_ativo boolean)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_empresa nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_empresa_pf(p_razao text, p_cpf text, p_ativo boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_cadastro
    (tenant_id, razao_social, nome_fantasia, tipo_pessoa, cpf, ativo)
  VALUES (public.qa_sandbox_tenant_id(), p_razao, p_razao, 'pf', p_cpf, p_ativo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_empresa_pf(p_razao text, p_cpf text, p_ativo boolean)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_empresa_pf nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_meta(p_titulo text, p_ano integer DEFAULT 2026)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.metas (tenant_id, titulo, ano)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_ano) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_meta(p_titulo text, p_ano integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_meta nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_obrigacao(p_categoria text, p_titulo text, p_status text DEFAULT 'pendente'::text, p_criticidade text DEFAULT 'media'::text, p_subcategoria text DEFAULT NULL::text, p_acao uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.empresa_obrigacoes
    (tenant_id, categoria, subcategoria, titulo, status, criticidade, acao_gerada_id)
  VALUES (public.qa_sandbox_tenant_id(), p_categoria, p_subcategoria, p_titulo,
          p_status, p_criticidade, p_acao)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_obrigacao(p_categoria text, p_titulo text, p_status text, p_criticidade text, p_subcategoria text, p_acao uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_obrigacao nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_pasta(p_nome text, p_pai uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.documento_pastas (tenant_id, nome, pasta_pai_id)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, p_pai) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_pasta(p_nome text, p_pai uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_pasta nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_swot(p_titulo text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_swot (tenant_id, titulo)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_swot(p_titulo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_swot nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_nova_tabela_feriados(p_nome text, p_tenant uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_t uuid := COALESCE(p_tenant, public.qa_sandbox_tenant_id()); v_id uuid;
BEGIN
  INSERT INTO public.feriado_tabelas (tenant_id, nome, uf, municipio, ano, ativo)
  VALUES (v_t, p_nome, 'SP', 'São Paulo', 2026, true)
  RETURNING id INTO v_id;
  INSERT INTO public.feriado_tabela_itens (tenant_id, tabela_id, nome, data, recorrente, tipo, ativo)
  VALUES (v_t, v_id, '[QA] Aniversário da Cidade', DATE '2026-01-25', false, 'feriado', true);
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_nova_tabela_feriados(p_nome text, p_tenant uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_nova_tabela_feriados nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_doc_terceiro(p_terceiro uuid, p_tipo text, p_nome text, p_validade date DEFAULT NULL::date, p_trabalhador uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.terceiro_documentos
    (tenant_id, terceiro_id, trabalhador_id, tipo, nome, data_validade)
  VALUES (public.qa_sandbox_tenant_id(), p_terceiro, p_trabalhador, p_tipo, p_nome, p_validade)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_doc_terceiro(p_terceiro uuid, p_tipo text, p_nome text, p_validade date, p_trabalhador uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_doc_terceiro nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_documento(p_nome text, p_pasta uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.documentos
    (tenant_id, colaborador_nome, nome_arquivo, nome_original, tipo, tamanho, mime_type, storage_path, pasta_id)
  VALUES (public.qa_sandbox_tenant_id(), '[QA] Colaborador', p_nome, p_nome, 'pdf', 1024,
          'application/pdf', 'qa/'||p_nome, p_pasta) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_documento(p_nome text, p_pasta uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_documento nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_hub_processo(p_titulo text, p_tipo hub_processo_tipo DEFAULT 'admissao'::hub_processo_tipo)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.hub_processos (tenant_id, tipo, titulo)
  VALUES (public.qa_sandbox_tenant_id(), p_tipo, p_titulo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_hub_processo(p_titulo text, p_tipo hub_processo_tipo)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_hub_processo nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_no_org(p_titulo text, p_parent uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_organograma (tenant_id, titulo, parent_id)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_parent) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_no_org(p_titulo text, p_parent uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_no_org nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_oceano(p_titulo text, p_swot uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.estrategia_oceano_azul (tenant_id, titulo, swot_id)
  VALUES (public.qa_sandbox_tenant_id(), p_titulo, p_swot) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_oceano(p_titulo text, p_swot uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_oceano nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_novo_terceiro(p_razao text, p_cnpj text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.terceiros (tenant_id, razao_social, cnpj)
  VALUES (public.qa_sandbox_tenant_id(), p_razao, p_cnpj) RETURNING id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_novo_terceiro(p_razao text, p_cnpj text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_novo_terceiro nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_obrigacao_existe(p_empresa uuid, p_subcategoria text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE v_existe boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.empresa_obrigacoes
     WHERE tenant_id    = public.qa_sandbox_tenant_id()
       AND empresa_id   = p_empresa          -- <— o parametro passa a valer
       AND subcategoria = p_subcategoria
       AND origem       = 'cadastro_empresa'
  ) INTO v_existe;
  RETURN v_existe;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_obrigacao_existe(p_empresa uuid, p_subcategoria text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_obrigacao_existe nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_admissao(p_nome text, p_cpf_semente integer, p_empresa_id uuid DEFAULT NULL::uuid, p_data_admissao date DEFAULT (CURRENT_DATE - 60))
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_cpf text := public.qa_cpf(p_cpf_semente);
BEGIN
  INSERT INTO public.admissoes
    (tenant_id, nome_completo, cpf, email, cargo, status, data_admissao, empresa_id)
  VALUES (public.qa_sandbox_tenant_id(), p_nome, v_cpf,
          public.qa_fixture_email('PONTO-AGO', p_cpf_semente),
          'Operador', 'concluido', p_data_admissao, p_empresa_id);
  RETURN v_cpf;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_admissao(p_nome text, p_cpf_semente integer, p_empresa_id uuid, p_data_admissao date)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_admissao nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_dia(p_cpf text, p_nome text, p_data date, p_empresa_id uuid DEFAULT NULL::uuid, p_status text DEFAULT 'regular'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.ponto_diario
    (tenant_id, empresa_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data, entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status)
  VALUES (public.qa_sandbox_tenant_id(), p_empresa_id, gen_random_uuid(), p_nome, p_cpf,
          p_data, TIME '08:00', TIME '12:00', TIME '13:00', TIME '17:00',
          INTERVAL '8 hours', p_status);
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_dia(p_cpf text, p_nome text, p_data date, p_empresa_id uuid, p_status text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_dia nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_dia_horarios(p_cpf text, p_nome text, p_data date, p_entrada time without time zone, p_saida time without time zone, p_salm time without time zone DEFAULT NULL::time without time zone, p_ralm time without time zone DEFAULT NULL::time without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid := gen_random_uuid();
  v_min int;
BEGIN
  v_min := floor(EXTRACT(EPOCH FROM (p_saida - p_entrada))/60)::int;
  IF v_min < 0 THEN v_min := v_min + 1440; END IF;
  IF p_salm IS NOT NULL AND p_ralm IS NOT NULL THEN
    v_min := v_min - floor(EXTRACT(EPOCH FROM (p_ralm - p_salm))/60)::int;
  END IF;
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf, data,
     entrada, saida_almoco, retorno_almoco, saida, horas_trabalhadas, status)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_nome, p_cpf, p_data,
          p_entrada, p_salm, p_ralm, p_saida, make_interval(mins => v_min), 'regular')
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)) DO UPDATE
    SET entrada = EXCLUDED.entrada, saida = EXCLUDED.saida,
        saida_almoco = EXCLUDED.saida_almoco, retorno_almoco = EXCLUDED.retorno_almoco,
        horas_trabalhadas = EXCLUDED.horas_trabalhadas
  RETURNING colaborador_id INTO v_id;
  RETURN v_id;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_dia_horarios(p_cpf text, p_nome text, p_data date, p_entrada time without time zone, p_saida time without time zone, p_salm time without time zone, p_ralm time without time zone)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_dia_horarios nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_dia_min(p_cpf text, p_nome text, p_data date, p_minutos integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.ponto_diario
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data, entrada, saida, horas_trabalhadas, status)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), p_nome, p_cpf,
          p_data, TIME '08:00', TIME '08:00' + make_interval(mins => p_minutos),
          make_interval(mins => p_minutos), 'regular')
  ON CONFLICT (tenant_id, colaborador_cpf, data, COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)) DO UPDATE
    SET horas_trabalhadas = EXCLUDED.horas_trabalhadas,
        saida = EXCLUDED.saida;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_dia_min(p_cpf text, p_nome text, p_data date, p_minutos integer)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_dia_min nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_escala_tol(p_cpf text, p_nome text, p_jornada_min integer, p_tol_min integer, p_data_inicio date, p_data_fim date)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.ponto_escalas
    (tenant_id, nome, tipo, modalidade, jornada_diaria_minutos,
     jornada_semanal_minutos, intervalo_intrajornada_minutos,
     tolerancia_minutos, tolerancia_diaria_minutos,
     hora_entrada_padrao, hora_saida_padrao,
     equalizacao_mensal_ativa, carga_semanal_contratada_min, ativa)
  VALUES (public.qa_sandbox_tenant_id(), 'QA escala ' || p_cpf, 'fixa', 'fixa',
          p_jornada_min, p_jornada_min * 5, 60,
          LEAST(p_tol_min, 5), p_tol_min,
          TIME '08:00', TIME '17:00',
          false, p_jornada_min * 5, true)
  RETURNING id INTO v_id;

  INSERT INTO public.ponto_escala_atribuicoes
    (tenant_id, escala_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_inicio, data_fim, ativa)
  VALUES (public.qa_sandbox_tenant_id(), v_id, p_cpf, p_nome, p_cpf,
          p_data_inicio, p_data_fim, true);
  RETURN v_id;
END;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_escala_tol(p_cpf text, p_nome text, p_jornada_min integer, p_tol_min integer, p_data_inicio date, p_data_fim date)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_escala_tol nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_ponto_marca(p_cpf text, p_nome text, p_data date, p_hora time without time zone, p_tipo text, p_original boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.ponto_marcacoes
    (tenant_id, colaborador_id, colaborador_nome, colaborador_cpf,
     data_marcacao, hora_marcacao, tipo_marcacao,
     hash_marcacao, marcacao_original, origem_marcacao)
  VALUES (public.qa_sandbox_tenant_id(), gen_random_uuid(), p_nome, p_cpf,
          p_data, p_hora, p_tipo,
          'qa-seed', p_original, CASE WHEN p_original THEN 'O' ELSE 'A' END);
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_ponto_marca(p_cpf text, p_nome text, p_data date, p_hora time without time zone, p_tipo text, p_original boolean)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_ponto_marca nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_registrar_bateria_e2e(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_exec       uuid;
  v_item       jsonb;
  v_codigo     text;
  v_caso       uuid;
  v_situacao   public.qa_situacao;
  v_sem_caso   int := 0;
  v_gravados   int := 0;
  v_total      int;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload->'resultados') <> 'array' THEN
    RAISE EXCEPTION 'Payload invalido: esperava { "resultados": [...] }.';
  END IF;

  v_total := jsonb_array_length(p_payload->'resultados');

  INSERT INTO public.qa_execucoes (disparo, modulo_path, terminada_em)
  VALUES ('e2e', 'cypress', now())
  RETURNING id INTO v_exec;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'resultados')
  LOOP
    v_situacao := CASE lower(COALESCE(v_item->>'situacao', ''))
                    WHEN 'passou' THEN 'passou'
                    WHEN 'falhou' THEN 'falhou'
                    WHEN 'pulado' THEN 'nao_implementado'
                    ELSE 'erro'
                  END::public.qa_situacao;

    SELECT e.codigo INTO v_codigo
    FROM public.qa_cobertura_e2e e
    WHERE e.ativo
      AND e.spec  = v_item->>'spec'
      AND e.teste = v_item->>'teste';

    IF v_codigo IS NULL THEN
      v_sem_caso := v_sem_caso + 1;
      CONTINUE;
    END IF;

    SELECT c.id INTO v_caso FROM public.qa_casos_teste c WHERE c.codigo = v_codigo;

    INSERT INTO public.qa_resultados
      (execucao_id, caso_id, codigo, situacao, passo_acao, esperado, obtido,
       erro_tecnico, duracao_ms, evidencia_png)
    VALUES
      (v_exec, v_caso, v_codigo, v_situacao,
       v_item->>'teste',
       'Teste de tela em ' || COALESCE(v_item->>'spec', '(spec desconhecido)'),
       CASE v_situacao
         WHEN 'passou' THEN 'A tela se comportou como o caso descreve.'
         WHEN 'nao_implementado' THEN 'O teste existe mas nao rodou nesta corrida.'
         ELSE 'A tela fez diferente do que o caso descreve.'
       END,
       NULLIF(v_item->>'erro', ''),
       NULLIF(v_item->>'duracao_ms', '')::int,
       NULLIF(v_item->>'evidencia_png', ''))
    ON CONFLICT (execucao_id, codigo) DO NOTHING;

    v_gravados := v_gravados + 1;
    v_codigo := NULL;
  END LOOP;

  UPDATE public.qa_execucoes e SET
    total            = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec),
    passou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'passou'),
    falhou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'falhou'),
    nao_implementado = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'nao_implementado'),
    erro             = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao = 'erro'),
    observacao       = 'Corrida do Cypress (origem: '
                       || COALESCE(p_payload->>'origem', 'nao informada') || '). '
                       || v_total || ' teste(s) na suite, ' || v_gravados || ' ligado(s) a caso'
                       || CASE WHEN v_sem_caso > 0
                               THEN '. >>> ' || v_sem_caso || ' teste(s) de tela SEM caso documentado '
                                 || '(rodaram, mas nao aparecem no relatorio: falta linha em qa_cobertura_e2e).'
                               ELSE '. Todos os testes tem caso documentado.' END
  WHERE e.id = v_exec;

  RETURN v_exec;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_registrar_bateria_e2e(p_payload jsonb)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_registrar_bateria_e2e nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_relatorio_falhas(p_modulo text DEFAULT NULL::text)
 RETURNS TABLE(codigo text, prio text, disposicao text, situacao text, achado text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT r.codigo,
         left(ct.prioridade::text, 4),
         CASE ct.disposicao
           WHEN 'em_triagem'            THEN '>>> NOVO'
           WHEN 'bug_confirmado'        THEN 'bug'
           WHEN 'aguardando_construcao' THEN 'a construir'
           WHEN 'decisao_de_produto'    THEN 'decidido'
           WHEN 'fora_de_escopo'        THEN 'fora escopo'
           WHEN 'comportamento_correto' THEN 'caso errado'
           ELSE ct.disposicao END,
         left(r.situacao::text, 6),
         left(regexp_replace(COALESCE(r.obtido,''), '\s+', ' ', 'g'), 100)
  FROM public.qa_resultados r
  JOIN public.qa_casos_teste ct ON ct.codigo = r.codigo
  WHERE r.execucao_id = (
          SELECT e.id FROM public.qa_execucoes e
          WHERE p_modulo IS NULL OR e.modulo_path = p_modulo
          ORDER BY e.iniciada_em DESC LIMIT 1)
    AND r.situacao IN ('falhou','erro')
  ORDER BY (ct.disposicao <> 'em_triagem'),   -- o que ainda não foi triado vem primeiro
           CASE ct.prioridade WHEN 'critica' THEN 1 WHEN 'alta' THEN 2
                              WHEN 'media' THEN 3 ELSE 4 END,
           r.codigo;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_relatorio_falhas(p_modulo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_relatorio_falhas nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_resultados_da_bateria(p_execucao_id uuid)
 RETURNS TABLE(codigo text, situacao text, passo_ordem integer, passo_acao text, esperado text, obtido text, erro_tecnico text, duracao_ms integer, titulo text, objetivo text, pre_condicoes text, passos jsonb, resultado_esperado text, observacoes text, evidencia_png text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.codigo, r.situacao::text, r.passo_ordem, r.passo_acao,
         r.esperado, r.obtido, r.erro_tecnico, r.duracao_ms,
         c.titulo, c.objetivo, c.pre_condicoes,
         c.passos, c.resultado_esperado, c.observacoes,
         r.evidencia_png
  FROM public.qa_resultados r
  LEFT JOIN public.qa_casos_teste c ON c.codigo = r.codigo
  WHERE r.execucao_id = p_execucao_id
    AND public.is_superadmin(auth.uid())
  ORDER BY
    CASE r.situacao WHEN 'falhou' THEN 0 WHEN 'erro' THEN 1
                    WHEN 'passou' THEN 2 ELSE 3 END,
    r.codigo;
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_resultados_da_bateria(p_execucao_id uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_resultados_da_bateria nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_rodar_agendada()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_modulo text;
BEGIN
  SELECT modulo_path INTO v_modulo FROM public.qa_agendamento WHERE id = 1;
  -- disparo 'agendado', sem disparada_por (nao foi ninguem, foi o relogio)
  PERFORM public.qa_rodar_bateria('agendado', v_modulo);
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_rodar_agendada()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_rodar_agendada nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_rodar_bateria(p_disparo qa_disparo DEFAULT 'manual'::qa_disparo, p_modulo text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_exec uuid;
  v_t0   timestamptz := clock_timestamp();
  c      record;
  r      public.qa_retorno;
  v_ini  timestamptz;
  v_vaz  int;
  v_todos boolean := (p_modulo IS NULL OR btrim(p_modulo) = '');
BEGIN
  IF public.qa_sandbox_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'Cercado nao existe. Bateria abortada.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'qa_guarda_cercado' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'A trava do cercado nao esta instalada. Bateria abortada por seguranca.';
  END IF;

  PERFORM public.qa_modo_ligar();
  PERFORM public.qa_exigir_modo();

  INSERT INTO public.qa_execucoes (disparo, modulo_path)
  VALUES (p_disparo, CASE WHEN v_todos THEN 'todos' ELSE p_modulo END)
  RETURNING id INTO v_exec;

  FOR c IN
    SELECT ct.id AS caso_id, ct.codigo, ct.titulo, ct.nivel, i.funcao_sql
    FROM public.qa_casos_teste ct
    JOIN public.qa_modulos m ON m.id = ct.modulo_id
    LEFT JOIN public.qa_implementacoes i ON i.codigo = ct.codigo AND i.ativo
    WHERE ct.status = 'aprovado'
      AND (v_todos OR m.path = p_modulo)
    ORDER BY ct.codigo
  LOOP
    v_ini := clock_timestamp();

    IF c.funcao_sql IS NULL THEN
      INSERT INTO public.qa_resultados
        (execucao_id, caso_id, codigo, situacao, esperado, obtido, duracao_ms)
      VALUES (v_exec, c.caso_id, c.codigo, 'nao_implementado', c.titulo,
              CASE WHEN c.nivel = 'e2e'
                   THEN 'Caso de TELA (e2e). Nao roda no motor SQL por natureza — '
                     || 'depende de navegador, clique e latencia. A cobertura dele '
                     || 'vive no Cypress (pasta cypress/e2e). Este resultado nao e '
                     || 'divida do motor.'
                   ELSE 'Caso documentado e aprovado. Nenhuma rotina foi escrita para executa-lo.'
              END, 0);
    ELSE
      r := public.qa_executar_descartavel(c.funcao_sql);
      INSERT INTO public.qa_resultados
        (execucao_id, caso_id, codigo, situacao, passo_ordem, passo_acao,
         esperado, obtido, erro_tecnico, detalhe, duracao_ms)
      VALUES (v_exec, c.caso_id, c.codigo, r.situacao, r.passo_ordem, r.passo_acao,
              r.esperado, r.obtido, r.erro_tecnico, r.detalhe,
              extract(milliseconds from clock_timestamp() - v_ini)::int);
    END IF;
  END LOOP;

  SELECT count(*) INTO v_vaz FROM public.qa_verifica_vazamento()
  WHERE veredito NOT IN ('limpo','ok');

  UPDATE public.qa_execucoes e SET
    terminada_em     = now(),
    duracao_ms       = extract(milliseconds from clock_timestamp() - v_t0)::int,
    total            = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec),
    passou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='passou'),
    falhou           = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='falhou'),
    nao_implementado = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='nao_implementado'),
    erro             = (SELECT count(*) FROM public.qa_resultados WHERE execucao_id = v_exec AND situacao='erro'),
    observacao       = CASE WHEN v_vaz > 0
                            THEN '>>> VAZAMENTO: sobrou dado de teste no cercado.'
                            ELSE 'Cercado limpo ao final.' END
  WHERE e.id = v_exec;

  PERFORM public.qa_limpar_historico(90);
  RETURN v_exec;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_rodar_bateria(p_disparo qa_disparo, p_modulo text)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_rodar_bateria nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_sandbox2_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM public.tenants WHERE slug = 'qa-sandbox-2'
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_sandbox2_tenant_id()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_sandbox2_tenant_id nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_sandbox_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$ SELECT id FROM public.tenants WHERE slug = 'qa-sandbox' $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_sandbox_tenant_id()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_sandbox_tenant_id nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_um_usuario()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM auth.users ORDER BY created_at LIMIT 1
$function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_um_usuario()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_um_usuario nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_verifica_contaminacao(p_execucao_id uuid)
 RETURNS TABLE(tabela text, linhas_fora_do_cercado bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_ini timestamptz;
  v_fim timestamptz;
  v_sandbox uuid;
  t record;
  n bigint;
BEGIN
  SELECT iniciada_em, COALESCE(terminada_em, now())
    INTO v_ini, v_fim
  FROM public.qa_execucoes WHERE id = p_execucao_id;

  IF v_ini IS NULL THEN
    RAISE EXCEPTION 'Execucao % nao encontrada.', p_execucao_id;
  END IF;

  v_sandbox := public.qa_sandbox_tenant_id();

  FOR t IN SELECT qtp.tabela FROM public.qa_tabelas_protegidas qtp LOOP
    EXECUTE format(
      'SELECT count(*) FROM public.%I
        WHERE created_at >= $1 AND created_at <= $2 AND tenant_id IS DISTINCT FROM $3',
      t.tabela)
    INTO n USING v_ini, v_fim, v_sandbox;

    IF n > 0 THEN
      tabela := t.tabela;
      linhas_fora_do_cercado := n;
      RETURN NEXT;
    END IF;
  END LOOP;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_verifica_contaminacao(p_execucao_id uuid)';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_verifica_contaminacao nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;

DO $qa1$
DECLARE d text := $qadef$
CREATE OR REPLACE FUNCTION public.qa_verifica_vazamento()
 RETURNS TABLE(o_que text, encontrado bigint, esperado bigint, veredito text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_t         uuid := public.qa_sandbox_tenant_id();
  c           record;
  v_n         bigint;
  v_esperado  bigint;
  v_varridas  int := 0;
  v_problemas int := 0;
  v_pulos     int := 0;
  v_base      int;
BEGIN
  IF v_t IS NULL THEN
    RETURN QUERY SELECT 'cercado'::text, 0::bigint, 0::bigint,
      '>>> o cercado nao existe'::text;
    RETURN;
  END IF;

  SELECT count(*) INTO v_base FROM public.qa_mobiliario_fixo;
  IF v_base = 0 THEN
    RETURN QUERY SELECT 'linha de base'::text, 0::bigint, 0::bigint,
      '>>> sem linha de base — rode qa_mobiliario_registrar() com o cercado limpo'::text;
    RETURN;
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS qa_vaz_tmp
    (o_que text, encontrado bigint, esperado bigint, veredito text) ON COMMIT DROP;

  -- WHERE true: o safeupdate do Supabase recusa DELETE sem WHERE nos papeis
  -- da API. Apagar tudo aqui e intencional — a tabela e temporaria e serve
  -- so para acumular o resultado desta chamada.
  DELETE FROM qa_vaz_tmp WHERE true;

  FOR c IN
    SELECT col.table_name
    FROM information_schema.columns col
    JOIN information_schema.tables t
      ON t.table_schema = col.table_schema AND t.table_name = col.table_name
    WHERE col.table_schema = 'public'
      AND col.column_name  = 'tenant_id'
      AND t.table_type     = 'BASE TABLE'
      AND col.table_name NOT LIKE 'qa\_%'
    ORDER BY col.table_name
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I WHERE tenant_id = $1', c.table_name)
        INTO v_n USING v_t;
      v_varridas := v_varridas + 1;
    EXCEPTION WHEN OTHERS THEN
      v_pulos := v_pulos + 1;
      CONTINUE;
    END;

    SELECT m.esperado INTO v_esperado
    FROM public.qa_mobiliario_fixo m WHERE m.tabela = c.table_name;
    v_esperado := COALESCE(v_esperado, 0);

    IF v_n <> v_esperado THEN
      v_problemas := v_problemas + 1;
      INSERT INTO qa_vaz_tmp VALUES (
        c.table_name, v_n, v_esperado,
        CASE
          WHEN v_esperado = 0    THEN '>>> VAZOU'
          WHEN v_n > v_esperado  THEN '>>> SOBROU'
          ELSE                        '>>> FALTA'
        END);
    END IF;
  END LOOP;

  IF v_problemas = 0 THEN
    RETURN QUERY SELECT
      format('%s tabelas varridas%s', v_varridas,
             CASE WHEN v_pulos > 0
                  THEN format(', %s sem permissao de leitura', v_pulos)
                  ELSE '' END)::text,
      0::bigint, 0::bigint, 'limpo'::text;
  ELSE
    RETURN QUERY SELECT
      format('%s tabelas varridas, %s com problema', v_varridas, v_problemas)::text,
      v_problemas::bigint, 0::bigint, '>>> VAZOU'::text;
    RETURN QUERY SELECT * FROM qa_vaz_tmp ORDER BY 1;
  END IF;
END $function$
$qadef$;
BEGIN
  EXECUTE d;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    EXECUTE 'DROP FUNCTION IF EXISTS public.qa_verifica_vazamento()';
    EXECUTE d;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rotina qa_verifica_vazamento nao pode ser criada: %', SQLERRM;
  END;
END $qa1$;


-- ---------------------------------------------------------------------------
-- CONFERENCIA — Esperado: 67 | 79 | t | OK
-- ---------------------------------------------------------------------------
WITH x AS MATERIALIZED (
  SELECT
    (SELECT count(*) FROM public.qa_modulos) AS modulos,
    (SELECT count(DISTINCT p.proname) FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = ANY (ARRAY['qa_afast_legado', 'qa_afast_novo', 'qa_afast_tipado', 'qa_agendamento_e2e_ler_dias', 'qa_agendamento_e2e_proxima', 'qa_agendamento_e2e_salvar_dia', 'qa_agendamento_ler', 'qa_agendamento_ler_dias', 'qa_agendamento_proxima', 'qa_agendamento_salvar', 'qa_agendamento_salvar_dia', 'qa_anexar_print_e2e', 'qa_assert_sandbox', 'qa_bloqueia_fora_do_cercado', 'qa_caso_detalhe', 'qa_cercas_faltando', 'qa_col_existe', 'qa_coluna_existe', 'qa_conferir_seguranca', 'qa_cpf', 'qa_cpf_formatado', 'qa_cron_sincronizar', 'qa_cron_sincronizar_e2e', 'qa_dia_util_passado', 'qa_disparar_bateria', 'qa_e2e_disparar_esteira', 'qa_empresa', 'qa_empresa_com_cota', 'qa_empresa_com_ponto', 'qa_executar_descartavel', 'qa_exigir_modo', 'qa_feriado_da_unidade', 'qa_ferias_periodo', 'qa_fixture_email', 'qa_fixture_limpar', 'qa_fns_com', 'qa_houve_vazamento', 'qa_instalar_cercas', 'qa_limpa_config_metas', 'qa_limpa_identidade', 'qa_limpar_historico', 'qa_listar_baterias', 'qa_mobiliario_registrar', 'qa_modo_ligado', 'qa_modo_ligar', 'qa_modulos_testaveis', 'qa_nova_acao', 'qa_nova_competencia', 'qa_nova_condicao', 'qa_nova_empresa', 'qa_nova_empresa_pf', 'qa_nova_meta', 'qa_nova_obrigacao', 'qa_nova_pasta', 'qa_nova_swot', 'qa_nova_tabela_feriados', 'qa_novo_doc_terceiro', 'qa_novo_documento', 'qa_novo_hub_processo', 'qa_novo_no_org', 'qa_novo_oceano', 'qa_novo_terceiro', 'qa_obrigacao_existe', 'qa_ponto_admissao', 'qa_ponto_dia', 'qa_ponto_dia_horarios', 'qa_ponto_dia_min', 'qa_ponto_escala_tol', 'qa_ponto_marca', 'qa_registrar_bateria_e2e', 'qa_relatorio_falhas', 'qa_resultados_da_bateria', 'qa_rodar_agendada', 'qa_rodar_bateria', 'qa_sandbox2_tenant_id', 'qa_sandbox_tenant_id', 'qa_um_usuario', 'qa_verifica_contaminacao', 'qa_verifica_vazamento'])) AS ferramentas,
    (public.qa_sandbox_tenant_id() IS NOT NULL) AS cercado_existe
)
SELECT modulos, ferramentas, cercado_existe,
       CASE WHEN modulos >= 67 AND ferramentas >= 79 AND cercado_existe
            THEN 'OK' ELSE 'CONFERIR' END AS erro_tecnico
FROM x;
