-- =====================================================================
-- SCRIPT DE ENTREGA · CENTRAL DE CONTROLE DE CLIENTES
-- Detalhe do incidente (para a triagem do erro)
--
-- Cole no SQL Editor do projeto. Roda em UMA transacao e pode ser
-- executado mais de uma vez sem efeito diferente.
--
-- O QUE FAZ: cria a funcao central_incidente_detalhe, que devolve, para
-- um incidente, os clientes atingidos e os ultimos eventos (empresa,
-- tela, acao, trilha do usuario e detalhe tecnico). So CRIA funcao nova;
-- nao altera nem apaga dado — nao ha copia de seguranca a fazer.
--
-- Nada e desmascarado aqui: o texto ja entrou no banco sem CPF, e-mail,
-- telefone nem segredo. Leitura restrita a superadmin.
--
-- Depende do script_central_captura_erros.sql (tabelas de evento).
-- Conteudo igual ao da migration 20260917000500_central_detalhe_incidente.sql.
-- =====================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.central_incidente_detalhe(
  p_fingerprint text,
  p_limite int DEFAULT 20
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $det$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN '{}'::jsonb ELSE
    jsonb_build_object(
      'incidente', (
        SELECT to_jsonb(i) FROM public.evento_incidente i WHERE i.fingerprint = p_fingerprint
      ),
      'clientes', COALESCE((
        SELECT jsonb_agg(c ORDER BY c->>'ocorrencias' DESC)
        FROM (
          SELECT jsonb_build_object(
                   'tenant_id', e.tenant_id,
                   'nome', COALESCE(t.nome, 'Sem empresa vinculada'),
                   'ocorrencias', count(*),
                   'ultimo', max(e.recebido_em)
                 ) AS c
          FROM public.evento_erro e
          LEFT JOIN public.tenants t ON t.id = e.tenant_id
          WHERE e.fingerprint = p_fingerprint
          GROUP BY e.tenant_id, t.nome
        ) s
      ), '[]'::jsonb),
      'eventos', COALESCE((
        SELECT jsonb_agg(ev ORDER BY ev->>'ocorrido_em' DESC)
        FROM (
          SELECT jsonb_build_object(
                   'id', e.id,
                   'empresa', COALESCE(t.nome, 'Sem empresa vinculada'),
                   'ambiente', e.ambiente,
                   'origem', e.origem,
                   'usuario_pseudo', e.usuario_pseudo,
                   'modulo', e.modulo,
                   'rota', e.rota,
                   'acao', e.acao,
                   'mensagem', e.mensagem,
                   'stack', e.stack,
                   'breadcrumbs', e.breadcrumbs,
                   'versao_app', e.versao_app,
                   'navegador_os', e.navegador_os,
                   'ocorrido_em', e.ocorrido_em
                 ) AS ev
          FROM public.evento_erro e
          LEFT JOIN public.tenants t ON t.id = e.tenant_id
          WHERE e.fingerprint = p_fingerprint
          ORDER BY e.recebido_em DESC
          LIMIT GREATEST(1, LEAST(COALESCE(p_limite, 20), 100))
        ) s
      ), '[]'::jsonb)
    )
  END
$det$;

REVOKE ALL ON FUNCTION public.central_incidente_detalhe(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.central_incidente_detalhe(text, int) TO authenticated;

COMMENT ON FUNCTION public.central_incidente_detalhe(text, int) IS
  'Detalhe de um incidente para a triagem: clientes atingidos e últimos eventos, já mascarados. Só superadmin.';

-- === CONFERENCIA (unico resultado que o editor mostra) ===
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'central_incidente_detalhe')      AS funcao_criada_esperado_1,
  (SELECT count(*) FROM information_schema.role_routine_grants
    WHERE routine_schema = 'public' AND routine_name = 'central_incidente_detalhe'
      AND grantee = 'anon')                                                       AS acesso_anonimo_deve_ser_zero,
  (SELECT count(*) FROM public.evento_incidente)                                  AS incidentes_hoje,
  'OK — detalhe do incidente disponivel na Central'                               AS resultado;
