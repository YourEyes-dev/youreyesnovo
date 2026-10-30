-- HOMOLOGAÇÃO — somente leitura: estado da assinatura do espelho 2026-07 (Aline Toledo Quintana, CPF ficticio).
SELECT json_build_object(
  'solicitacoes', (SELECT json_agg(json_build_object('status', s.status, 'enviado_em', s.enviado_em,
        'respondido_em', s.respondido_em, 'assinado_sha', left(COALESCE(s.assinado_sha256,''),12),
        'documento_id', s.documento_id, 'trilha_id', s.trilha_id) ORDER BY s.created_at)
      FROM public.assinatura_solicitacoes s
      WHERE regexp_replace(s.colaborador_cpf,'[^0-9]','','g') = '90000005134' AND s.referencia = '2026-07'),
  'eventos', (SELECT json_agg(json_build_object('tipo', e.tipo, 'em', e.criado_em) ORDER BY e.criado_em)
      FROM public.assinatura_eventos e JOIN public.assinatura_solicitacoes s ON s.id = e.solicitacao_id
      WHERE regexp_replace(s.colaborador_cpf,'[^0-9]','','g') = '90000005134' AND s.referencia = '2026-07'),
  'espelho', (SELECT json_agg(json_build_object('status', p.status, 'ciencia_origem', p.ciencia_origem,
        'data_confirmacao', p.data_confirmacao, 'confirmado_por', p.confirmado_por, 'sol_id', p.assinatura_solicitacao_id))
      FROM public.ponto_espelhos p
      WHERE regexp_replace(p.colaborador_cpf,'[^0-9]','','g') = '90000005134' AND p.competencia = '2026-07')
) AS diag;
