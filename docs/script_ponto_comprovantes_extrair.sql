-- ============================================================================
-- ENTREGA — ponto_comprovantes_extrair: trava de acesso LGPD (drift teste->prod)
--
-- O QUE ESTE SCRIPT FAZ (e por que):
--   O comprovante de ponto (REP-P) e dado pessoal do trabalhador. Na producao
--   a funcao e SQL puro e devolve o comprovante de QUALQUER CPF para quem a
--   chamar. O teste (fonte da verdade) ja restringiu: so o PROPRIO dono do CPF
--   ou um perfil de RH/gestao (has_minimum_role 'manager') extrai; qualquer
--   outro usuario autenticado recebe VAZIO — nem o dado nem a confirmacao de
--   que ele existe (LGPD arts. 11 e 46).
--
--   Sem sessao (auth.uid() nulo — SQL Editor, cron, outra funcao do banco) a
--   extracao continua liberada, para nao travar rotinas internas e a
--   fiscalizacao. So muda a assinatura interna para plpgsql; a assinatura
--   externa (parametros e colunas devolvidas) e a MESMA.
--
-- SEGURANCA: so substitui a funcao; nao altera nem apaga dado; idempotente.
--   A conferencia final compara o corpo normalizado com o hash do teste (OK).
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.ponto_comprovantes_extrair(p_tenant_id uuid, p_colaborador_cpf text, p_ini date, p_fim date)
 RETURNS TABLE(data_hora timestamp with time zone, nsr bigint, empregador text, conteudo jsonb, hash_comprovante text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid       uuid;
  v_cpf_alvo  text := regexp_replace(COALESCE(p_colaborador_cpf,''), '[^0-9]', '', 'g');
  v_cpf_dono  text;
  v_pode      boolean := false;
BEGIN
  BEGIN v_uid := auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;

  IF v_uid IS NULL THEN
    -- Sem sessão: rotina do banco / SQL Editor. Não há usuário a restringir.
    v_pode := true;
  ELSE
    -- O próprio dono do CPF.
    BEGIN
      SELECT regexp_replace(COALESCE(ub.cpf,''), '[^0-9]', '', 'g')
        INTO v_cpf_dono
      FROM public.usuarios_base ub
      WHERE ub.auth_user_id = v_uid
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_cpf_dono := NULL; END;

    IF v_cpf_dono IS NOT NULL AND v_cpf_dono <> '' AND v_cpf_dono = v_cpf_alvo THEN
      v_pode := true;
    END IF;

    -- RH e gestão: precisam extrair o de terceiros (conferência, fiscalização).
    IF NOT v_pode AND to_regprocedure('public.has_minimum_role(uuid, app_role)') IS NOT NULL THEN
      BEGIN
        v_pode := public.has_minimum_role(v_uid, 'manager'::app_role);
      EXCEPTION WHEN OTHERS THEN v_pode := false; END;
    END IF;
  END IF;

  IF NOT v_pode THEN
    RETURN;  -- vazio: nem dado de terceiro, nem confirmação de que ele existe
  END IF;

  RETURN QUERY
  SELECT c.data_hora_marcacao, c.nsr, c.empregador_nome, c.conteudo, c.hash_comprovante
  FROM public.ponto_comprovantes c
  WHERE c.tenant_id = p_tenant_id
    AND regexp_replace(COALESCE(c.colaborador_cpf,''), '[^0-9]', '', 'g') = v_cpf_alvo
    AND c.data_hora_marcacao::date BETWEEN p_ini AND p_fim
  ORDER BY c.data_hora_marcacao;
END;
$fn$;

-- ── Conferencia (o editor mostra so o ultimo resultado) ─────────────────────
-- Esperado: 1 linha, linguagem = plpgsql, status = OK.
SELECT
  l.lanname                                                        AS linguagem,
  md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))  AS md5_producao,
  'b61d28bbdabbe579e74bc758e4cb78a0'                               AS md5_teste,
  CASE WHEN md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))
            = 'b61d28bbdabbe579e74bc758e4cb78a0'
       THEN 'OK' ELSE 'CONFERIR' END                               AS status
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
JOIN pg_language  l ON l.oid = p.prolang
WHERE p.proname = 'ponto_comprovantes_extrair';
