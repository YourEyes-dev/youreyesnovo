-- =========================================================
-- Central de Controle de Clientes — detalhe do incidente
--
-- A fila de incidentes mostra o resumo; para corrigir, a equipe precisa
-- abrir e ver: quais clientes sentiram, quando, em que tela, o que o
-- usuário estava fazendo e o detalhe técnico.
--
-- Tudo o que sai daqui já foi mascarado na ingestão — esta função não
-- desmascara nada. Leitura restrita a superadmin, como o resto da Central.
-- =========================================================

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
