-- ============================================================================
-- Mapa Comportamental — Fundação (Fatia 1 do MVP)
--
-- Novo módulo do bloco Desenvolvimento & Performance (DHO): instrumento de
-- AUTOPERCEPÇÃO comportamental de 28 itens que produz uma assinatura
-- (Arquétipo + Motor de Decisão + Modo de Contexto). Base: documento
-- "YE - Mapa Comportamental" (Anexo A/A.8 = itens e algoritmo).
--
-- Esta fatia cria a fundação da aba "Meu Mapa": o colaborador responde e vê o
-- próprio resultado na hora. Campanhas, Guia do Líder e Aderência vêm nas
-- fatias seguintes.
--
-- Decisões travadas com o dono do produto (padrões seguros do documento):
--  - Instrumento de autopercepção/desenvolvimento; NÃO é psicodiagnóstico (P1).
--  - Cálculo DETERMINÍSTICO e AUDITÁVEL (RN-013): a apuração é uma função pura
--    versionada (src/data/instrumentos/mapaComportamental.ts) e as respostas
--    cruas ficam guardadas para recálculo/auditoria.
--  - RN-002: o titular vê o próprio mapa; nesta fatia a leitura de linha é
--    restrita ao titular (gestor/RH só via agregados com supressão por baixo N).
--  - RN-009 (trava de arquitetura): NENHUMA troca com Psicossocial, Bem-Estar,
--    Atestados ou Saúde Ocupacional — este módulo não referencia essas tabelas.
--  - Nenhum dado de saúde/CID/humor é armazenado aqui.
-- ============================================================================

SET lock_timeout = '10s';

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Instrumento versionado (RF-016). Guarda a metainformação da versão; o
--    conteúdo dos itens e o algoritmo vivem no código, referenciados por
--    algoritmo_versao (versionados no git).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_instrumentos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  versao           int  NOT NULL UNIQUE,
  algoritmo_versao text NOT NULL,
  titulo           text NOT NULL DEFAULT 'Mapa Comportamental',
  total_itens      int  NOT NULL DEFAULT 28,
  definicao        jsonb NOT NULL DEFAULT '{}'::jsonb,
  vigente          boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.mapa_comportamental_instrumentos (versao, algoritmo_versao, total_itens, vigente, definicao)
VALUES (
  1, 'v1', 28, true,
  jsonb_build_object(
    'versao', 1,
    'algoritmo_versao', 'v1',
    'total_itens', 28,
    'limiar_perfil_misto', 2,
    'tempo_minimo_segundos', 60,
    'eixos', jsonb_build_object(
      'foco',  'A=Pessoas / B=Tarefas',
      'ritmo', 'A=Acelerado / B=Ponderado',
      'modo',  'A=Constante / B=Cadenciado',
      'motor', '1=Racional / 2=Relacional / 3=Pragmatico'
    ),
    'pares_controle', jsonb_build_array(
      jsonb_build_array(1,25), jsonb_build_array(7,26),
      jsonb_build_array(13,27), jsonb_build_array(19,28)
    ),
    'fonte', 'src/data/instrumentos/mapaComportamental.ts'
  )
)
ON CONFLICT (versao) DO NOTHING;

-- ────────────────────────────────────────────────────────────────────────────
-- 2) Respostas + resultado apurado. Uma linha por aplicação (rascunho ou
--    concluído). A identidade é carimbada no servidor (trigger), nunca confiada
--    ao cliente.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_respostas (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id           uuid,
  auth_user_id         uuid NOT NULL,
  usuario_id           uuid,
  colaborador_nome     text,
  colaborador_cpf      text,
  campanha_id          uuid,              -- Fatia 2 (campanhas)
  instrumento_versao   int  NOT NULL DEFAULT 1,
  algoritmo_versao     text NOT NULL DEFAULT 'v1',
  status               text NOT NULL DEFAULT 'rascunho',
  respostas            jsonb NOT NULL DEFAULT '{}'::jsonb,
  resultado            jsonb,
  arquetipo            text,
  indice_consistencia  int,
  confiabilidade       text,
  aviso_versao         text,
  aviso_aceite_em      timestamptz,
  tempo_total_segundos int,
  tempo_por_item       jsonb,
  concluido_em         timestamptz,
  vence_em             date,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mapa_comp_status_chk CHECK (status IN ('rascunho','concluido')),
  CONSTRAINT mapa_comp_confiab_chk CHECK (confiabilidade IS NULL OR confiabilidade IN ('alta','baixa'))
);

CREATE INDEX IF NOT EXISTS idx_mapa_comp_resp_tenant_user
  ON public.mapa_comportamental_respostas(tenant_id, auth_user_id);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_resp_tenant_status
  ON public.mapa_comportamental_respostas(tenant_id, status);
-- No máximo um rascunho de autoaplicação (sem campanha) por usuário.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mapa_comp_rascunho_autoaplicacao
  ON public.mapa_comportamental_respostas(tenant_id, auth_user_id)
  WHERE status = 'rascunho' AND campanha_id IS NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) Log de acesso a mapa de terceiro (RF-013). Consultável pelo titular. Ainda
--    não exercido nesta fatia (não há visão de terceiros), mas já criado.
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mapa_comportamental_acessos (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  mapa_id           uuid NOT NULL REFERENCES public.mapa_comportamental_respostas(id) ON DELETE CASCADE,
  acessado_por      uuid NOT NULL,
  acessado_por_nome text,
  acessado_em       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mapa_comp_acessos_mapa
  ON public.mapa_comportamental_acessos(mapa_id);

-- ────────────────────────────────────────────────────────────────────────────
-- 4) Trigger de identidade: carimba tenant/usuário/nome/cpf a partir do usuário
--    autenticado, ignorando o que o cliente enviar. Evita mapa em nome de
--    outra pessoa.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_carimbar_identidade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_ub  record;
BEGIN
  NEW.auth_user_id := v_uid;
  NEW.tenant_id := COALESCE(public.get_user_tenant_id(), NEW.tenant_id);

  SELECT ub.id, ub.nome_completo,
         regexp_replace(COALESCE(ub.cpf,''), '[^0-9]', '', 'g') AS cpf_num
    INTO v_ub
    FROM public.usuarios_base ub
   WHERE ub.auth_user_id = v_uid
   LIMIT 1;

  IF FOUND THEN
    NEW.usuario_id       := v_ub.id;
    NEW.colaborador_nome := v_ub.nome_completo;
    NEW.colaborador_cpf  := NULLIF(v_ub.cpf_num, '');
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_mapa_comp_carimbar_identidade ON public.mapa_comportamental_respostas;
CREATE TRIGGER trg_mapa_comp_carimbar_identidade
  BEFORE INSERT ON public.mapa_comportamental_respostas
  FOR EACH ROW EXECUTE FUNCTION public.mapa_comportamental_carimbar_identidade();

DROP TRIGGER IF EXISTS trg_mapa_comp_updated_at ON public.mapa_comportamental_respostas;
CREATE TRIGGER trg_mapa_comp_updated_at
  BEFORE UPDATE ON public.mapa_comportamental_respostas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ────────────────────────────────────────────────────────────────────────────
-- 5) RLS
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.mapa_comportamental_instrumentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mapa_comportamental_respostas    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mapa_comportamental_acessos      ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  -- Instrumento: leitura livre para autenticados (dado de referência, sem tenant).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_instrumentos' AND policyname='mapa_comp_instr_select') THEN
    CREATE POLICY mapa_comp_instr_select ON public.mapa_comportamental_instrumentos
      FOR SELECT TO authenticated USING (true);
  END IF;

  -- Respostas: o titular vê/insere/atualiza apenas o próprio mapa.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_respostas' AND policyname='mapa_comp_resp_select_titular') THEN
    CREATE POLICY mapa_comp_resp_select_titular ON public.mapa_comportamental_respostas
      FOR SELECT TO authenticated
      USING (auth_user_id = auth.uid() OR public.is_superadmin(auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_respostas' AND policyname='mapa_comp_resp_insert_titular') THEN
    CREATE POLICY mapa_comp_resp_insert_titular ON public.mapa_comportamental_respostas
      FOR INSERT TO authenticated
      WITH CHECK (auth_user_id = auth.uid() AND tenant_id = public.get_user_tenant_id());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_respostas' AND policyname='mapa_comp_resp_update_titular') THEN
    CREATE POLICY mapa_comp_resp_update_titular ON public.mapa_comportamental_respostas
      FOR UPDATE TO authenticated
      USING (auth_user_id = auth.uid())
      WITH CHECK (auth_user_id = auth.uid());
  END IF;

  -- RESTRICTIVE (PERFIL-003): tabela com dado pessoal só é lida pelo titular,
  -- por quem o perfil permite o módulo, ou superadmin. AND-combina com a
  -- permissiva acima (nesta fatia, portanto, efetivamente = titular).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_respostas' AND policyname='perfil_restringe_leitura_mapa_comportamental_respostas') THEN
    CREATE POLICY perfil_restringe_leitura_mapa_comportamental_respostas
      ON public.mapa_comportamental_respostas
      AS RESTRICTIVE FOR SELECT TO authenticated
      USING (
        auth_user_id = auth.uid()
        OR public.is_superadmin(auth.uid())
        OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
      );
  END IF;

  -- Acessos: o titular do mapa vê o log dos próprios; RH/perfil também. Insere
  -- quem está registrando o próprio acesso.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_acessos' AND policyname='mapa_comp_acessos_select') THEN
    CREATE POLICY mapa_comp_acessos_select ON public.mapa_comportamental_acessos
      FOR SELECT TO authenticated
      USING (
        public.is_superadmin(auth.uid())
        OR public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['mapa_comportamental'::text])
        OR EXISTS (
          SELECT 1 FROM public.mapa_comportamental_respostas r
          WHERE r.id = mapa_id AND r.auth_user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='mapa_comportamental_acessos' AND policyname='mapa_comp_acessos_insert') THEN
    CREATE POLICY mapa_comp_acessos_insert ON public.mapa_comportamental_acessos
      FOR INSERT TO authenticated
      WITH CHECK (acessado_por = auth.uid() AND tenant_id = public.get_user_tenant_id());
  END IF;
END $pol$;

-- ────────────────────────────────────────────────────────────────────────────
-- 6) Painel agregado (RH/gestor) com supressão por baixo N (RN-011). Só entrega
--    números a quem o perfil permite o módulo; baixa confiabilidade não alimenta
--    indicadores (RN-005).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mapa_comportamental_painel(p_empresa_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tenant uuid := public.get_user_tenant_id();
  v_min    int  := 5;
  v_total  int;
  v_validos int;
  v_baixa  int;
  v_cons   numeric;
  v_dist   jsonb;
BEGIN
  IF v_tenant IS NULL
     OR NOT public.perfil_permite_modulo(v_tenant, VARIADIC ARRAY['mapa_comportamental'::text]) THEN
    RETURN jsonb_build_object('suprimido', true, 'total_concluidos', 0, 'minimo_respondentes', v_min);
  END IF;

  SELECT
    count(*) FILTER (WHERE status = 'concluido'),
    count(*) FILTER (WHERE status = 'concluido' AND confiabilidade = 'alta'),
    count(*) FILTER (WHERE status = 'concluido' AND confiabilidade = 'baixa')
  INTO v_total, v_validos, v_baixa
  FROM public.mapa_comportamental_respostas
  WHERE tenant_id = v_tenant
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id);

  IF v_validos < v_min THEN
    RETURN jsonb_build_object(
      'suprimido', true,
      'total_concluidos', v_total,
      'minimo_respondentes', v_min,
      'confiabilidade_baixa', v_baixa
    );
  END IF;

  SELECT round(avg(indice_consistencia)::numeric, 2)
    INTO v_cons
  FROM public.mapa_comportamental_respostas
  WHERE tenant_id = v_tenant AND status = 'concluido' AND confiabilidade = 'alta'
    AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id);

  SELECT COALESCE(jsonb_object_agg(arq, qt), '{}'::jsonb)
    INTO v_dist
  FROM (
    SELECT COALESCE(arquetipo, 'indefinido') AS arq, count(*) AS qt
    FROM public.mapa_comportamental_respostas
    WHERE tenant_id = v_tenant AND status = 'concluido' AND confiabilidade = 'alta'
      AND (p_empresa_id IS NULL OR empresa_id = p_empresa_id)
    GROUP BY 1
  ) d;

  RETURN jsonb_build_object(
    'suprimido', false,
    'total_concluidos', v_total,
    'minimo_respondentes', v_min,
    'distribuicao_arquetipos', v_dist,
    'consistencia_media', v_cons,
    'confiabilidade_baixa', v_baixa
  );
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.mapa_comportamental_painel(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mapa_comportamental_painel(uuid) TO authenticated;
