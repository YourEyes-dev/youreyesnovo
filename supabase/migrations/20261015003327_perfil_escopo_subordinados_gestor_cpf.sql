-- ============================================================================
-- Escopo "subordinados diretos" — ancora a hierarquia no CPF do gestor
--
-- A fundação anterior guardava o chefe como PONTEIRO para a ficha de colaborador
-- (admissoes.gestor_admissao_id). Problema real: há gestor que NÃO tem ficha de
-- colaborador — um pró-labore ou o próprio dono, que existe só como usuário do
-- sistema (usuarios_base). Esse não tinha ficha para onde apontar.
--
-- Correção: o vínculo passa a ser o CPF do gestor (admissoes.gestor_cpf). O CPF
-- é a única identidade que colaborador, pró-labore e usuário do sistema
-- compartilham, e é por CPF que a camada de perfil já identifica "quem sou eu"
-- (cpf_do_usuario_logado). Assim qualquer gestor com CPF resolve seus
-- subordinados, tenha ou não ficha de colaborador.
--
-- Esta migration roda DEPOIS da fundação (que já criou gestor_admissao_id no
-- staging): migra o dado para gestor_cpf e remove a coluna antiga.
-- ============================================================================

SET lock_timeout = '10s';

-- ── 1. Nova âncora: CPF do gestor (dígitos) ─────────────────────────────────
ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS gestor_cpf text;

CREATE INDEX IF NOT EXISTS idx_admissoes_gestor_cpf
  ON public.admissoes(gestor_cpf);

-- ── 2. Backfill do gestor_cpf ───────────────────────────────────────────────
DO $backfill$
BEGIN
  -- (a) a partir do ponteiro antigo gestor_admissao_id, se existir e preenchido
  BEGIN
    UPDATE public.admissoes a
       SET gestor_cpf = regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g')
      FROM public.admissoes g
     WHERE a.gestor_admissao_id = g.id
       AND a.gestor_admissao_id IS NOT NULL
       AND (a.gestor_cpf IS NULL OR a.gestor_cpf = '')
       AND regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g') <> '';
  EXCEPTION WHEN undefined_column THEN
    RAISE NOTICE 'Coluna gestor_admissao_id ausente; backfill (a) pulado.';
  END;

  -- (b) a partir do texto livre gestor_imediato (nome único no tenant)
  UPDATE public.admissoes a
     SET gestor_cpf = g.cpf_norm
    FROM (
      SELECT tenant_id, lower(btrim(nome_completo)) AS nome_norm,
             min(regexp_replace(COALESCE(cpf, ''), '[^0-9]', '', 'g')) AS cpf_norm,
             count(*) AS n
        FROM public.admissoes
       GROUP BY tenant_id, lower(btrim(nome_completo))
      HAVING count(*) = 1
    ) g
   WHERE (a.gestor_cpf IS NULL OR a.gestor_cpf = '')
     AND a.gestor_imediato IS NOT NULL
     AND btrim(a.gestor_imediato) <> ''
     AND a.tenant_id = g.tenant_id
     AND lower(btrim(a.gestor_imediato)) = g.nome_norm
     AND g.cpf_norm <> ''
     AND g.cpf_norm <> regexp_replace(COALESCE(a.cpf, ''), '[^0-9]', '', 'g');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Backfill de gestor_cpf pulado: %', SQLERRM;
END $backfill$;

-- ── 3. Motor: subordinados resolvidos pelo CPF do gestor ────────────────────
-- Direto: o subordinado aponta para mim pelo gestor_cpf.
-- Apoio:  colaboradores de departamento cujo gestor (ficha) tem o meu CPF.
-- "Quem sou eu" = cpf_do_usuario_logado() — funciona para colaborador,
-- pró-labore E usuário do sistema sem ficha.
CREATE OR REPLACE FUNCTION public.ye_cpfs_subordinados_diretos(p_tenant_id uuid)
RETURNS text[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_cpf text := public.cpf_do_usuario_logado();
  v_res text[];
BEGIN
  IF p_tenant_id IS NULL OR v_cpf IS NULL OR v_cpf = '' THEN
    RETURN ARRAY[]::text[];
  END IF;

  SELECT COALESCE(array_agg(DISTINCT cpf_norm), ARRAY[]::text[])
    INTO v_res
    FROM (
      -- vínculo direto pelo CPF do gestor
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g') AS cpf_norm
        FROM public.admissoes s
       WHERE s.tenant_id = p_tenant_id
         AND regexp_replace(COALESCE(s.gestor_cpf, ''), '[^0-9]', '', 'g') = v_cpf
      UNION
      -- apoio: colaboradores de departamento que eu chefio (gestor = minha ficha)
      SELECT regexp_replace(COALESCE(s.cpf, ''), '[^0-9]', '', 'g')
        FROM public.admissoes s
        JOIN public.departamentos d
          ON d.id = s.departamento_id
         AND d.tenant_id = p_tenant_id
        JOIN public.admissoes g
          ON g.id = d.gestor_admissao_id
         AND g.tenant_id = p_tenant_id
         AND regexp_replace(COALESCE(g.cpf, ''), '[^0-9]', '', 'g') = v_cpf
       WHERE s.tenant_id = p_tenant_id
    ) q
   WHERE cpf_norm <> '' AND cpf_norm <> v_cpf;

  RETURN v_res;
END;
$fn$;

-- ── 4. Remove a âncora antiga (ponteiro para ficha), agora substituída ──────
DROP INDEX IF EXISTS public.idx_admissoes_gestor_admissao;
ALTER TABLE public.admissoes DROP COLUMN IF EXISTS gestor_admissao_id;
