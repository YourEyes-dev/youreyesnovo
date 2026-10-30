-- ============================================================================
-- ASSINATURA DE DOCUMENTOS (genérico) — Fatia 1, parte 1: tabelas e bucket
-- Primeiro uso: Espelho de Ponto (contexto 'ponto_espelho').
--
--   assinatura_lotes         um envio em lote (o modelo já nasce pronto; a tela
--                            de lote é a Fatia 2)
--   assinatura_solicitacoes  uma linha por signatário e documento: cópia do
--                            signatário no envio, hash do PDF congelado, hash do
--                            token (nunca o token), status, autenticação,
--                            tentativas e lembretes
--   assinatura_eventos       trilha só de inserção (aberto, cpf, otp, consentimento,
--                            prova de vida, assinado, lembrete, expirado...)
--   assinatura_otps          códigos de uso único (só o hash), sem acesso pela API
--
-- Leitura: só a própria empresa, mais a camada de perfil (módulos ponto e
-- colaboradores, mesmo portão do Ponto). Escrita: só funções do servidor
-- (SECURITY DEFINER) e funções de borda com a chave de serviço. Nada para anônimo.
--
-- Bucket privado 'assinaturas-documentos' ({tenant}/{contexto}/{solicitacao}/
-- original.pdf | assinado.pdf): sem regra de alterar nem apagar; quem grava é a
-- função de borda. A cópia navegável do assinado vai para Documentos.
--
-- ponto_espelhos.assinatura_solicitacao_id: a solicitação que deu a ciência.
--
-- Tabelas criadas por EXECUTE (o mesmo texto vai no script de entrega, que não
-- pode ter a sequência de criar tabela por extenso). Idempotente.
-- ============================================================================

SET lock_timeout = '10s';

-- ── Tabelas ────────────────────────────────────────────────────────────────
DO $tab$
BEGIN
  IF to_regclass('public.assinatura_lotes') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinatura_lotes ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' empresa_id uuid,'
      || ' contexto text NOT NULL,'
      || ' referencia text,'
      || ' filtros jsonb NOT NULL DEFAULT ''{}''::jsonb,'
      || ' status text NOT NULL DEFAULT ''preparando'''
      || '   CHECK (status IN (''preparando'',''gerando'',''enviando'',''concluido'',''concluido_com_falhas'',''cancelado'')),'
      || ' total int NOT NULL DEFAULT 0,'
      || ' gerados int NOT NULL DEFAULT 0,'
      || ' enviados int NOT NULL DEFAULT 0,'
      || ' falhas int NOT NULL DEFAULT 0,'
      || ' criado_por uuid,'
      || ' criado_por_nome text,'
      || ' created_at timestamptz NOT NULL DEFAULT now(),'
      || ' concluido_em timestamptz)';
  END IF;

  IF to_regclass('public.assinatura_solicitacoes') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinatura_solicitacoes ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' empresa_id uuid,'
      || ' lote_id uuid REFERENCES public.assinatura_lotes(id) ON DELETE SET NULL,'
      || ' contexto text NOT NULL,'
      || ' documento_ref_tabela text,'
      || ' documento_ref_id uuid,'
      || ' referencia text,'
      || ' colaborador_id text,'
      || ' colaborador_cpf text NOT NULL,'
      || ' colaborador_nome text,'
      || ' email text,'
      || ' celular text,'
      || ' status text NOT NULL DEFAULT ''preparando'''
      || '   CHECK (status IN (''preparando'',''na_fila'',''enviado'',''visualizado'',''assinado'',''assinado_com_ressalva'',''contestado'',''expirado'',''cancelado'',''falha'')),'
      || ' token_hash text UNIQUE,'
      || ' token_gerado_em timestamptz,'
      || ' link_base text,'
      || ' expira_em timestamptz,'
      || ' original_path text,'
      || ' original_sha256 text CHECK (original_sha256 IS NULL OR original_sha256 ~ ''^[0-9a-f]{64}$''),'
      || ' original_bytes int,'
      || ' dados_snapshot jsonb,'
      || ' dados_sha256 text,'
      || ' assinado_path text,'
      || ' assinado_sha256 text,'
      || ' documento_id uuid,'
      || ' trilha_id uuid,'
      || ' consentimento_id uuid,'
      || ' autenticacao jsonb NOT NULL DEFAULT ''{}''::jsonb,'
      || ' decisao_texto text,'
      || ' respondido_em timestamptz,'
      || ' visualizado_em timestamptz,'
      || ' enviado_por uuid,'
      || ' enviado_por_nome text,'
      || ' enviado_em timestamptz,'
      || ' canais text[] NOT NULL DEFAULT ARRAY[]::text[],'
      || ' envio_tentativas int NOT NULL DEFAULT 0,'
      || ' envio_proxima_em timestamptz,'
      || ' envio_erro text,'
      || ' lembretes_enviados int NOT NULL DEFAULT 0,'
      || ' proximo_lembrete_em timestamptz,'
      || ' tentativas_cpf int NOT NULL DEFAULT 0,'
      || ' tentativas_otp int NOT NULL DEFAULT 0,'
      || ' bloqueado_ate timestamptz,'
      || ' cancelado_motivo text,'
      || ' cancelado_em timestamptz,'
      || ' created_at timestamptz NOT NULL DEFAULT now(),'
      || ' updated_at timestamptz NOT NULL DEFAULT now())';
  END IF;

  IF to_regclass('public.assinatura_eventos') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinatura_eventos ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' solicitacao_id uuid NOT NULL REFERENCES public.assinatura_solicitacoes(id),'
      || ' tipo text NOT NULL,'
      || ' ator text NOT NULL DEFAULT ''sistema'' CHECK (ator IN (''rh'',''colaborador'',''sistema'')),'
      || ' ator_id uuid,'
      || ' ip text,'
      || ' user_agent text,'
      || ' dados jsonb NOT NULL DEFAULT ''{}''::jsonb,'
      || ' criado_em timestamptz NOT NULL DEFAULT now())';
  END IF;

  IF to_regclass('public.assinatura_otps') IS NULL THEN
    EXECUTE 'CREATE ' || 'TABLE public.assinatura_otps ('
      || ' id uuid PRIMARY KEY DEFAULT gen_random_uuid(),'
      || ' tenant_id uuid NOT NULL,'
      || ' solicitacao_id uuid NOT NULL REFERENCES public.assinatura_solicitacoes(id),'
      || ' codigo_hash text NOT NULL,'
      || ' canal text NOT NULL DEFAULT ''email'','
      || ' destino_mascarado text,'
      || ' expira_em timestamptz NOT NULL,'
      || ' tentativas int NOT NULL DEFAULT 0,'
      || ' usado_em timestamptz,'
      || ' criado_em timestamptz NOT NULL DEFAULT now())';
  END IF;
END $tab$;

COMMENT ON TABLE public.assinatura_solicitacoes IS
  'Assinatura eletronica de documentos (generico; 1o uso: espelho de ponto). Uma linha por signatario e documento: copia do signatario no envio, hash do PDF congelado, hash do token (nunca o token), status, autenticacao (CPF/OTP/prova de vida), tentativas e lembretes. Escrita so pelo servidor.';
COMMENT ON TABLE public.assinatura_eventos IS
  'Trilha so de insercao da assinatura eletronica (aberto, cpf, otp, consentimento, prova de vida, assinado, ressalva, contestado, lembrete, expirado, cancelado). Nao aceita alteracao nem exclusao.';
COMMENT ON TABLE public.assinatura_otps IS
  'Codigos de uso unico da assinatura (so o hash). Sem acesso pela API: so o servidor.';
COMMENT ON TABLE public.assinatura_lotes IS
  'Envio em lote de documentos para assinatura (modelo pronto; tela na Fatia 2).';

-- ── Índices ────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_assinatura_solicitacao_ativa
  ON public.assinatura_solicitacoes (contexto, documento_ref_id)
  WHERE status IN ('preparando', 'na_fila', 'enviado', 'visualizado');
CREATE INDEX IF NOT EXISTS idx_assinatura_solicitacoes_ref
  ON public.assinatura_solicitacoes (tenant_id, contexto, referencia);
CREATE INDEX IF NOT EXISTS idx_assinatura_solicitacoes_cpf
  ON public.assinatura_solicitacoes (tenant_id, colaborador_cpf);
CREATE INDEX IF NOT EXISTS idx_assinatura_solicitacoes_lembrete
  ON public.assinatura_solicitacoes (proximo_lembrete_em)
  WHERE status IN ('enviado', 'visualizado');
CREATE INDEX IF NOT EXISTS idx_assinatura_eventos_solicitacao
  ON public.assinatura_eventos (solicitacao_id, criado_em);
CREATE INDEX IF NOT EXISTS idx_assinatura_otps_solicitacao
  ON public.assinatura_otps (solicitacao_id, criado_em DESC);

-- ── Coluna no espelho ──────────────────────────────────────────────────────
ALTER TABLE public.ponto_espelhos
  ADD COLUMN IF NOT EXISTS assinatura_solicitacao_id uuid;

-- ── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.assinatura_lotes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assinatura_solicitacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assinatura_eventos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assinatura_otps         ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.assinatura_lotes, public.assinatura_solicitacoes,
              public.assinatura_eventos, public.assinatura_otps FROM anon;
REVOKE ALL ON public.assinatura_otps FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.assinatura_lotes, public.assinatura_solicitacoes,
              public.assinatura_eventos FROM authenticated;
GRANT SELECT ON public.assinatura_lotes, public.assinatura_solicitacoes,
              public.assinatura_eventos TO authenticated;

DO $rls$
BEGIN
  -- Leitura pela empresa (permissiva) ...
  DROP POLICY IF EXISTS assinatura_lotes_leitura_tenant ON public.assinatura_lotes;
  CREATE POLICY assinatura_lotes_leitura_tenant ON public.assinatura_lotes
    FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());

  DROP POLICY IF EXISTS assinatura_solicitacoes_leitura_tenant ON public.assinatura_solicitacoes;
  CREATE POLICY assinatura_solicitacoes_leitura_tenant ON public.assinatura_solicitacoes
    FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());

  DROP POLICY IF EXISTS assinatura_eventos_leitura_tenant ON public.assinatura_eventos;
  CREATE POLICY assinatura_eventos_leitura_tenant ON public.assinatura_eventos
    FOR SELECT TO authenticated USING (tenant_id = public.get_user_tenant_id());

  -- ... e a camada de perfil (restritiva): mesmo portão do Ponto.
  DROP POLICY IF EXISTS perfil_restringe_leitura_assinatura_lotes ON public.assinatura_lotes;
  CREATE POLICY perfil_restringe_leitura_assinatura_lotes ON public.assinatura_lotes
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (public.perfil_permite_modulo(tenant_id, VARIADIC ARRAY['ponto', 'colaboradores']));

  DROP POLICY IF EXISTS perfil_restringe_leitura_assinatura_solicitacoes ON public.assinatura_solicitacoes;
  CREATE POLICY perfil_restringe_leitura_assinatura_solicitacoes ON public.assinatura_solicitacoes
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (
      public.perfil_amplo_sem_subordinados(tenant_id, VARIADIC ARRAY['ponto', 'colaboradores'])
      OR regexp_replace(COALESCE(colaborador_cpf, ''), '[^0-9]', '', 'g') = public.cpf_do_usuario_logado()
      OR (public.perfil_tem_escopo_subordinados(tenant_id, VARIADIC ARRAY['ponto', 'colaboradores'])
          AND public.ye_cpf_eh_subordinado_direto(tenant_id, colaborador_cpf)));

  -- Códigos de uso único: ninguém lê pela API (só o servidor, que ignora a RLS).
  -- Política explícita de negação para a varredura de isolamento (ISOL-005)
  -- não confundir "sem política" com esquecimento.
  DROP POLICY IF EXISTS assinatura_otps_sem_acesso_pela_api ON public.assinatura_otps;
  CREATE POLICY assinatura_otps_sem_acesso_pela_api ON public.assinatura_otps
    FOR SELECT TO authenticated USING (false);

  -- O evento herda a visibilidade da solicitação (a subconsulta passa pela RLS dela).
  DROP POLICY IF EXISTS perfil_restringe_leitura_assinatura_eventos ON public.assinatura_eventos;
  CREATE POLICY perfil_restringe_leitura_assinatura_eventos ON public.assinatura_eventos
    AS RESTRICTIVE FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.assinatura_solicitacoes s WHERE s.id = solicitacao_id));
END $rls$;

-- ── Trilha imutável ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assinatura_eventos_imutavel()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  RAISE EXCEPTION 'A trilha da assinatura (assinatura_eventos) não aceita alteração nem exclusão.'
    USING ERRCODE = 'insufficient_privilege';
END;
$fn$;

DROP TRIGGER IF EXISTS trg_assinatura_eventos_imutavel ON public.assinatura_eventos;
CREATE TRIGGER trg_assinatura_eventos_imutavel
  BEFORE UPDATE OR DELETE ON public.assinatura_eventos
  FOR EACH ROW EXECUTE FUNCTION public.assinatura_eventos_imutavel();

-- updated_at da solicitação
DROP TRIGGER IF EXISTS trg_assinatura_solicitacoes_updated_at ON public.assinatura_solicitacoes;
CREATE TRIGGER trg_assinatura_solicitacoes_updated_at
  BEFORE UPDATE ON public.assinatura_solicitacoes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ── Cerca do QA (tabelas com tenant_id) ────────────────────────────────────
DO $cerca$
DECLARE v_t text;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN
    RETURN;
  END IF;
  FOREACH v_t IN ARRAY ARRAY['assinatura_lotes', 'assinatura_solicitacoes', 'assinatura_eventos', 'assinatura_otps'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgname = 'qa_guarda_cercado'
                      AND tgrelid = ('public.' || v_t)::regclass AND NOT tgisinternal) THEN
      EXECUTE format('CREATE TRIGGER qa_guarda_cercado BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
                     || 'FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()', v_t);
    END IF;
    IF to_regclass('public.qa_tabelas_protegidas') IS NOT NULL THEN
      INSERT INTO public.qa_tabelas_protegidas (tabela, motivo)
      SELECT v_t, 'Cerca generica: tabela tem tenant_id'
      WHERE NOT EXISTS (SELECT 1 FROM public.qa_tabelas_protegidas x WHERE x.tabela = v_t);
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cerca do QA nao instalada nas tabelas de assinatura: %', SQLERRM;
END $cerca$;

-- ── Bucket privado dos PDFs (original congelado e assinado) ────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('assinaturas-documentos', 'assinaturas-documentos', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- Só leitura, só a própria empresa e só quem tem Ponto/Colaboradores em escopo
-- amplo. Sem regra de gravar, alterar ou apagar: quem grava é a função de borda.
DROP POLICY IF EXISTS "assinaturas_documentos_leitura_da_empresa" ON storage.objects;
CREATE POLICY "assinaturas_documentos_leitura_da_empresa"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'assinaturas-documentos'
    AND (storage.foldername(name))[1] = public.get_user_tenant_id()::text
    AND public.perfil_permite_modulo(public.get_user_tenant_id(), VARIADIC ARRAY['ponto', 'colaboradores'])
  );
