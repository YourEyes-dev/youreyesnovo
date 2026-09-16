-- =====================================================================
-- SCRIPT DE ENTREGA · PROGRAMA DE PARCEIROS · CONTRATO COM ASSINATURA
-- ELETRÔNICA COMPLETA (selfie, IP, dispositivo, localização, hash) e
-- texto no padrão ABNT com a qualificação das duas partes
--
-- Cole no SQL Editor do projeto. Roda em UMA transação; pode ser executado
-- mais de uma vez. Só cria/substitui funções, ajusta as exigências do
-- modelo 'parceria' na tela de Contratos e atualiza a redação da versão 2
-- do contrato (sem assinatura registrada em produção). Não altera nem
-- apaga assinaturas existentes.
--
-- Pré-requisitos: script_parceiros_politica_v2.sql e
-- script_youreyes_dados_fiscais.sql já aplicados.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Render ABNT: qualificação das partes + corpo + fecho e assinaturas
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_contrato_render_abnt(p_parceiro_id uuid, p_html text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_render_abnt$
DECLARE
  v_p    public.parceiros%ROWTYPE;
  v_ye   jsonb := public.youreyes_empresa_publica();
  v_v    public.parceiro_contratos_versoes%ROWTYPE;
  v_corpo text;
  v_css  text;
  v_titulo text;
  v_doc_rotulo text;
  v_cidade_ye text;
BEGIN
  IF p_parceiro_id IS NOT NULL THEN
    SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  v_corpo  := public.parceiro_contrato_render(p_parceiro_id, coalesce(p_html, v_v.html));
  v_titulo := coalesce(v_v.titulo, 'Contrato de Parceria Comercial');
  -- o corpo já traz o título como h2: evita repetir
  v_corpo := regexp_replace(v_corpo, '^\s*<h2>.*?</h2>\s*', '', 'i');
  -- ...e a linha "Versão N · vigente a partir de", que o cabeçalho ABNT já informa
  v_corpo := regexp_replace(v_corpo, '^\s*<p><strong>Versão \d+</strong>[^<]*</p>\s*', '', 'i');
  v_doc_rotulo := CASE WHEN v_p.tipo_pessoa = 'pf' THEN 'CPF' ELSE 'CNPJ' END;
  v_cidade_ye := nullif(concat_ws('/', v_ye->>'cidade', v_ye->>'uf'), '');

  -- CSS escopado (vale na tela pública, na Área do Parceiro, no SuperAdmin e na impressão)
  v_css := '<style>'
    || '.contrato-abnt{font-family:"Times New Roman",Times,"Liberation Serif",serif;font-size:12pt;line-height:1.5;color:#111;background:#fff;text-align:justify;text-justify:inter-word;hyphens:auto;-webkit-hyphens:auto;padding:3cm 2cm 2cm 3cm;max-width:21cm;margin:0 auto;box-sizing:border-box;}'
    || '.contrato-abnt *{color:#111;}'
    || '.contrato-abnt h1{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:center;margin:0 0 1.5em 0;letter-spacing:.02em;}'
    || '.contrato-abnt h2{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:left;margin:1.5em 0 .75em 0;}'
    || '.contrato-abnt h3{font-size:12pt;font-weight:bold;text-transform:uppercase;text-align:left;margin:1.5em 0 .75em 0;}'
    || '.contrato-abnt p{margin:0 0 .75em 0;text-indent:1.25cm;text-align:justify;}'
    || '.contrato-abnt p.sem-recuo,.contrato-abnt .partes p,.contrato-abnt .fecho p,.contrato-abnt .assinaturas p{text-indent:0;}'
    || '.contrato-abnt .partes{margin:0 0 1.5em 0;}'
    || '.contrato-abnt .partes table{width:100%;border-collapse:collapse;font-size:12pt;margin:.5em 0 1em 0;}'
    || '.contrato-abnt .partes th,.contrato-abnt .partes td{border:1px solid #333;padding:.25em .5em;text-align:left;vertical-align:top;}'
    || '.contrato-abnt .partes th{width:32%;font-weight:bold;background:#f2f2f2;}'
    || '.contrato-abnt .fecho{margin-top:2em;}'
    || '.contrato-abnt .assinaturas{display:flex;gap:2cm;justify-content:space-between;margin-top:3em;page-break-inside:avoid;}'
    || '.contrato-abnt .assinaturas > div{flex:1;text-align:center;border-top:1px solid #111;padding-top:.5em;}'
    || '.contrato-abnt .assinaturas small{display:block;font-size:10pt;line-height:1.3;}'
    || '.contrato-abnt .rodape{margin-top:2em;font-size:10pt;line-height:1.3;text-align:justify;border-top:1px solid #999;padding-top:.5em;}'
    || '.contrato-abnt em{font-style:italic;}'
    || '@media (max-width:640px){.contrato-abnt{padding:1.5cm 1cm 1cm 1.25cm;font-size:11pt;}.contrato-abnt .assinaturas{flex-direction:column;gap:2.5em;}}'
    || '@media print{@page{size:A4;margin:3cm 2cm 2cm 3cm;}.contrato-abnt{padding:0;max-width:none;}}'
    || '</style>';

  RETURN v_css
    || '<div class="contrato-abnt">'
    || '<h1>' || v_titulo || '</h1>'
    || '<p class="sem-recuo"><strong>Versão ' || coalesce(v_v.versao::text, '—') || '</strong>, publicada em '
    || coalesce(to_char(v_v.publicado_em, 'DD/MM/YYYY'), '—') || '. Instrumento particular gerado em ' || to_char(now(), 'DD/MM/YYYY') || '.</p>'
    || '<div class="partes"><h2>Qualificação das partes</h2>'
    || '<table><tbody>'
    || '<tr><th colspan="2">CONTRATADA (“YourEyes”)</th></tr>'
    || '<tr><th>Razão social</th><td>' || coalesce(v_ye->>'razao_social', 'YourEyes') || coalesce(' (' || nullif(v_ye->>'nome_fantasia','') || ')', '') || '</td></tr>'
    || '<tr><th>CNPJ</th><td>' || coalesce(nullif(v_ye->>'cnpj',''), '________________') || '</td></tr>'
    || '<tr><th>Endereço</th><td>' || coalesce(nullif(v_ye->>'endereco_completo',''), '________________') || '</td></tr>'
    || '<tr><th>E-mail</th><td>' || coalesce(nullif(v_ye->>'email_contato',''), '________________') || '</td></tr>'
    || '<tr><th>Representante legal</th><td>' || coalesce(nullif(v_ye->>'representante_nome',''), '________________') || coalesce(' — ' || nullif(v_ye->>'representante_cargo',''), '') || '</td></tr>'
    || '<tr><th colspan="2">PARCEIRO(A)</th></tr>'
    || '<tr><th>Nome / razão social</th><td>' || coalesce(v_p.nome, '________________') || '</td></tr>'
    || '<tr><th>' || v_doc_rotulo || '</th><td>' || coalesce(v_p.documento, '________________') || '</td></tr>'
    || '<tr><th>E-mail</th><td>' || coalesce(v_p.email, '________________') || '</td></tr>'
    || '<tr><th>Telefone</th><td>' || coalesce(v_p.telefone, '________________') || '</td></tr>'
    || '<tr><th>Cidade/UF</th><td>' || coalesce(nullif(concat_ws('/', v_p.cidade, v_p.uf), ''), '________________') || '</td></tr>'
    || '<tr><th>Código no programa</th><td>' || coalesce(v_p.codigo, '________________') || '</td></tr>'
    || '<tr><th>Perfil e trilha</th><td>' || coalesce(v_p.tipo_parceiro, '________') || ' — trilha ' || coalesce(initcap(v_p.trilha), '________') || '</td></tr>'
    || '</tbody></table></div>'
    || v_corpo
    || '<div class="fecho"><p>E, por estarem justas e contratadas, as partes firmam o presente instrumento em meio eletrônico, em uma única via digital, que produz os mesmos efeitos de documento físico assinado, na forma da Medida Provisória nº 2.200-2/2001, art. 10, § 2º, da Lei nº 14.063/2020 e do Código Civil, art. 107.</p>'
    || '<p>' || coalesce(v_cidade_ye, 'Brasil') || ', ' || to_char(now(), 'DD') || ' de '
    || (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'])[extract(month from now())::int]
    || ' de ' || to_char(now(), 'YYYY') || '.</p></div>'
    || '<div class="assinaturas">'
    || '<div><strong>' || coalesce(v_ye->>'razao_social', 'YourEyes') || '</strong><small>CNPJ ' || coalesce(nullif(v_ye->>'cnpj',''), '________________') || '</small><small>' || coalesce(nullif(v_ye->>'representante_nome',''), 'Representante legal') || '</small><small>CONTRATADA</small></div>'
    || '<div><strong>' || coalesce(v_p.nome, '________________') || '</strong><small>' || v_doc_rotulo || ' ' || coalesce(v_p.documento, '________________') || '</small><small>Assinatura eletrônica registrada com selfie, IP, dispositivo, localização e hash</small><small>PARCEIRO(A)</small></div>'
    || '</div>'
    || '<p class="rodape">Documento assinado eletronicamente. A autoria e a integridade são comprovadas pelo registro de assinatura da YourEyes: imagem da assinatura, fotografia (selfie) do signatário, endereço IP, identificação do dispositivo e navegador, coordenadas geográficas, data e hora e hash SHA-256 deste texto, guardados junto ao contrato e apresentados no relatório de assinatura.</p>'
    || '</div>';
END $parceiro_contrato_render_abnt$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_render_abnt(uuid, text) TO authenticated;

-- Texto público (quem visita /parceiros/contrato) já sai no padrão ABNT
CREATE OR REPLACE FUNCTION public.parceiro_contrato_publico()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_publico$
  SELECT jsonb_build_object('versao', v.versao, 'titulo', v.titulo, 'publicado_em', v.publicado_em,
    'html', public.parceiro_contrato_render_abnt(public.parceiro_meu_id(), v.html))
  FROM public.parceiro_contratos_versoes v WHERE v.vigente
$parceiro_contrato_publico$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_publico() TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) Modelo na tela de Contratos: um por versão vigente, exigindo CPF,
--    telefone, endereço, selfie e geolocalização
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_contrato_modelo_vigente()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_modelo_vigente$
DECLARE v_v public.parceiro_contratos_versoes%ROWTYPE; v_modelo uuid;
BEGIN
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_modelo FROM public.contratos_aceite
  WHERE categoria = 'parceria' AND versao = v_v.versao AND titulo = v_v.titulo
  ORDER BY created_at DESC LIMIT 1;
  IF v_modelo IS NULL THEN
    INSERT INTO public.contratos_aceite (titulo, categoria, descricao_publica, corpo_html,
      requer_cpf, requer_telefone, requer_endereco, requer_selfie, requer_geolocalizacao, validade_dias, versao, ativo)
    VALUES (v_v.titulo, 'parceria',
      'Contrato de Parceria Comercial do Programa de Parceiros. Gerado por parceiro com a qualificação das duas partes e assinado eletronicamente (assinatura, selfie, IP, dispositivo, localização e hash).',
      v_v.html, true, true, true, true, true, 30, v_v.versao, true)
    RETURNING id INTO v_modelo;
  ELSE
    UPDATE public.contratos_aceite SET ativo = true, requer_cpf = true, requer_telefone = true, requer_endereco = true,
      requer_selfie = true, requer_geolocalizacao = true, validade_dias = coalesce(validade_dias, 30), corpo_html = v_v.html
    WHERE id = v_modelo;
  END IF;
  RETURN v_modelo;
END $parceiro_contrato_modelo_vigente$;
REVOKE ALL ON FUNCTION public.parceiro_contrato_modelo_vigente() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) Iniciar assinatura: cria (ou reaproveita) o registro pendente com o
--    contrato gerado para o parceiro e devolve o token do link de assinar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_contrato_iniciar_assinatura_para(p_parceiro_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_iniciar_assinatura_para$
DECLARE v_p public.parceiros%ROWTYPE; v_v public.parceiro_contratos_versoes%ROWTYPE; v_modelo uuid; v_a public.contratos_assinaturas%ROWTYPE; v_html text;
BEGIN
  SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Parceiro não encontrado'; END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RAISE EXCEPTION 'Nenhuma versão vigente do contrato'; END IF;
  v_modelo := public.parceiro_contrato_modelo_vigente();

  -- já assinou esta versão?
  IF EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites WHERE parceiro_id = v_p.id AND versao = v_v.versao) THEN
    SELECT * INTO v_a FROM public.contratos_assinaturas WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'assinado' ORDER BY assinado_em DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', true, 'versao', v_v.versao, 'assinatura_id', v_a.id, 'assinado_em', v_a.assinado_em);
  END IF;

  -- pendente ainda válido? reaproveita (o texto é regenerado para refletir dados atualizados)
  SELECT * INTO v_a FROM public.contratos_assinaturas
  WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente' AND (expira_em IS NULL OR expira_em > now())
  ORDER BY created_at DESC LIMIT 1;
  v_html := public.parceiro_contrato_render_abnt(v_p.id, v_v.html);
  IF v_a.id IS NOT NULL THEN
    UPDATE public.contratos_assinaturas SET html_assinado = v_html,
      signatario_nome = coalesce(signatario_nome, v_p.nome), signatario_email = coalesce(signatario_email, v_p.email)
    WHERE id = v_a.id;
    RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
  END IF;

  UPDATE public.contratos_assinaturas SET status = 'expirado' WHERE parceiro_id = v_p.id AND contrato_id = v_modelo AND status = 'pendente';
  INSERT INTO public.contratos_assinaturas (contrato_id, parceiro_id, signatario_nome, signatario_email, signatario_telefone,
    signatario_cpf, signatario_cnpj, signatario_razao_social, html_assinado, link_enviado_para, expira_em, status, observacoes)
  VALUES (v_modelo, v_p.id, v_p.nome, v_p.email, v_p.telefone,
    CASE WHEN v_p.tipo_pessoa = 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.documento END,
    CASE WHEN v_p.tipo_pessoa <> 'pf' THEN v_p.nome END,
    v_html, v_p.email, now() + interval '30 days', 'pendente',
    'Contrato de Parceria gerado para o parceiro ' || v_p.codigo || ' · trilha ' || coalesce(v_p.trilha, '—') || ' · versão ' || v_v.versao || ' · aguardando assinatura eletrônica')
  RETURNING * INTO v_a;
  RETURN jsonb_build_object('ok', true, 'ja_assinado', false, 'token', v_a.token, 'assinatura_id', v_a.id, 'expira_em', v_a.expira_em, 'versao', v_v.versao);
END $parceiro_contrato_iniciar_assinatura_para$;
REVOKE ALL ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_iniciar_assinatura_para(uuid) TO service_role;

-- Versão para o próprio parceiro logado
CREATE OR REPLACE FUNCTION public.parceiro_contrato_iniciar_assinatura()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_iniciar_assinatura$
DECLARE v_pid uuid := public.parceiro_meu_id();
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  RETURN public.parceiro_contrato_iniciar_assinatura_para(v_pid);
END $parceiro_contrato_iniciar_assinatura$;
GRANT EXECUTE ON FUNCTION public.parceiro_contrato_iniciar_assinatura() TO authenticated;

-- O "aceite" do cadastro deixa de gravar assinatura: registra a intenção e
-- abre a assinatura pendente (mesma assinatura da função, para não quebrar chamadas)
CREATE OR REPLACE FUNCTION public.parceiro_aceitar_contrato(_user_agent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $parceiro_aceitar_contrato$
DECLARE v_pid uuid := public.parceiro_meu_id();
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  UPDATE public.parceiros SET aceite_termos_em = coalesce(aceite_termos_em, now()) WHERE id = v_pid;
  RETURN public.parceiro_contrato_iniciar_assinatura_para(v_pid) || jsonb_build_object('pendente_assinatura', true);
END $parceiro_aceitar_contrato$;

-- Cadastro autenticado (cliente / profissional do Marketplace virando parceiro)
-- devolve o token para a tela levar direto à assinatura eletrônica
CREATE OR REPLACE FUNCTION public.parceiro_cadastrar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_cadastrar$
DECLARE v_id uuid; v_uid uuid := auth.uid(); v_mp uuid; v_email text; v_contrato jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'É preciso estar autenticado'; END IF;
  IF public.parceiro_meu_id() IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'ja_existia', true, 'parceiro_id', public.parceiro_meu_id());
  END IF;
  IF coalesce(btrim(_dados->>'nome'),'') = '' THEN RAISE EXCEPTION 'Informe o nome'; END IF;
  IF coalesce((_dados->>'aceite_termos')::boolean, false) IS NOT TRUE THEN RAISE EXCEPTION 'É preciso aceitar o Contrato de Parceria'; END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  SELECT id INTO v_mp FROM public.marketplace_profissionais WHERE user_id = v_uid LIMIT 1;

  INSERT INTO public.parceiros
    (nome, tipo_pessoa, documento, tipo_parceiro, trilha, email, telefone, cidade, uf, cep,
     raio_atuacao_km, aceite_termos_em, marketplace_profissional_id, created_by)
  VALUES
    (_dados->>'nome', coalesce(_dados->>'tipo_pessoa','pj'), nullif(_dados->>'documento',''),
     coalesce(_dados->>'tipo_parceiro','indicador'),
     CASE WHEN _dados->>'trilha' IN ('indicador','representante','operador') THEN _dados->>'trilha' END,
     coalesce(nullif(_dados->>'email',''), v_email),
     nullif(_dados->>'telefone',''), nullif(_dados->>'cidade',''), nullif(upper(_dados->>'uf'),''),
     nullif(_dados->>'cep',''), coalesce((_dados->>'raio_atuacao_km')::int, 50), now(), v_mp, v_uid)
  RETURNING id INTO v_id;

  INSERT INTO public.parceiro_usuarios (parceiro_id, user_id, papel) VALUES (v_id, v_uid, 'dono');
  BEGIN
    v_contrato := public.parceiro_contrato_iniciar_assinatura_para(v_id);
  EXCEPTION WHEN OTHERS THEN v_contrato := jsonb_build_object('erro', SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'parceiro_id', v_id,
    'status', (SELECT status FROM public.parceiros WHERE id = v_id),
    'codigo', (SELECT codigo FROM public.parceiros WHERE id = v_id),
    'contrato', v_contrato);
END $parceiro_cadastrar$;

-- ---------------------------------------------------------------------
-- 4) Fluxo público de assinatura: mostra o texto gerado para o parceiro e,
--    ao assinar, fecha o aceite do programa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obter_contrato_publico(_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_assinatura public.contratos_assinaturas%ROWTYPE;
  v_contrato public.contratos_aceite%ROWTYPE;
  v_total_assinados INTEGER;
BEGIN
  SELECT * INTO v_assinatura FROM public.contratos_assinaturas WHERE token = _token;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro','token_invalido'); END IF;
  IF v_assinatura.status = 'assinado' THEN
    RETURN jsonb_build_object('erro','ja_assinado','assinado_em',v_assinatura.assinado_em, 'parceiro_id', v_assinatura.parceiro_id);
  END IF;
  IF v_assinatura.status = 'revogado' THEN RETURN jsonb_build_object('erro','revogado'); END IF;
  IF v_assinatura.expira_em IS NOT NULL AND v_assinatura.expira_em < now() THEN
    UPDATE public.contratos_assinaturas SET status='expirado' WHERE id = v_assinatura.id;
    RETURN jsonb_build_object('erro','expirado');
  END IF;

  SELECT * INTO v_contrato FROM public.contratos_aceite WHERE id = v_assinatura.contrato_id;
  IF NOT v_contrato.ativo THEN RETURN jsonb_build_object('erro','contrato_inativo'); END IF;

  IF v_contrato.limite_assinaturas IS NOT NULL THEN
    SELECT COUNT(*) INTO v_total_assinados FROM public.contratos_assinaturas
      WHERE contrato_id = v_contrato.id AND status='assinado';
    IF v_total_assinados >= v_contrato.limite_assinaturas THEN
      RETURN jsonb_build_object('erro','limite_atingido');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'titulo', v_contrato.titulo,
      'categoria', v_contrato.categoria,
      'descricao_publica', v_contrato.descricao_publica,
      -- contrato gerado por signatário (parceria) prevalece sobre o modelo genérico
      'corpo_html', coalesce(v_assinatura.html_assinado, v_contrato.corpo_html),
      'versao', v_contrato.versao,
      'requer_cpf', v_contrato.requer_cpf,
      'requer_rg', v_contrato.requer_rg,
      'requer_endereco', v_contrato.requer_endereco,
      'requer_telefone', v_contrato.requer_telefone,
      'requer_selfie', v_contrato.requer_selfie,
      'requer_geolocalizacao', v_contrato.requer_geolocalizacao,
      'requer_cnpj', v_contrato.requer_cnpj,
      'requer_razao_social', v_contrato.requer_razao_social,
      'requer_representante', v_contrato.requer_representante
    ),
    'assinatura', jsonb_build_object(
      'id', v_assinatura.id,
      'signatario_email', v_assinatura.signatario_email,
      'signatario_nome', v_assinatura.signatario_nome,
      'signatario_cpf', v_assinatura.signatario_cpf,
      'signatario_telefone', v_assinatura.signatario_telefone,
      'signatario_cnpj', v_assinatura.signatario_cnpj,
      'signatario_razao_social', v_assinatura.signatario_razao_social,
      'expira_em', v_assinatura.expira_em,
      'parceiro_id', v_assinatura.parceiro_id
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.registrar_assinatura_contrato(
    _token text,
    _nome text,
    _cpf text DEFAULT NULL::text,
    _email text DEFAULT NULL::text,
    _telefone text DEFAULT NULL::text,
    _rg text DEFAULT NULL::text,
    _endereco text DEFAULT NULL::text,
    _assinatura_imagem text DEFAULT NULL::text,
    _selfie_imagem text DEFAULT NULL::text,
    _ip text DEFAULT NULL::text,
    _user_agent text DEFAULT NULL::text,
    _geo_lat numeric DEFAULT NULL::numeric,
    _geo_lng numeric DEFAULT NULL::numeric,
    _hash text DEFAULT NULL::text,
    _cnpj text DEFAULT NULL::text,
    _razao_social text DEFAULT NULL::text,
    _representante text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_assinatura public.contratos_assinaturas%ROWTYPE; v_versao int; v_uid uuid; v_ip text := _ip;
BEGIN
  SELECT * INTO v_assinatura FROM public.contratos_assinaturas WHERE token = _token FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'erro','token_invalido'); END IF;
  IF v_assinatura.status = 'assinado' THEN RETURN jsonb_build_object('ok',false,'erro','ja_assinado'); END IF;
  IF v_assinatura.expira_em IS NOT NULL AND v_assinatura.expira_em < now() THEN
    UPDATE public.contratos_assinaturas SET status='expirado' WHERE id=v_assinatura.id;
    RETURN jsonb_build_object('ok',false,'erro','expirado');
  END IF;

  -- IP visto pelo servidor complementa o informado pelo navegador
  IF v_ip IS NULL THEN
    BEGIN
      v_ip := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
                       current_setting('request.headers', true)::json->>'cf-connecting-ip');
    EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;
  END IF;

  UPDATE public.contratos_assinaturas SET
    signatario_nome = _nome,
    signatario_cpf = _cpf,
    signatario_email = COALESCE(_email, signatario_email),
    signatario_telefone = _telefone,
    signatario_rg = _rg,
    signatario_endereco = _endereco,
    signatario_cnpj = _cnpj,
    signatario_razao_social = _razao_social,
    signatario_representante = _representante,
    assinatura_imagem = _assinatura_imagem,
    selfie_imagem = _selfie_imagem,
    ip_address = v_ip,
    user_agent = _user_agent,
    geo_lat = _geo_lat,
    geo_lng = _geo_lng,
    hash_documento = _hash,
    assinado_em = now(),
    status = 'assinado'
  WHERE id = v_assinatura.id;

  -- Contrato de Parceria: a assinatura fecha o aceite do programa
  IF v_assinatura.parceiro_id IS NOT NULL THEN
    SELECT c.versao INTO v_versao FROM public.contratos_aceite c WHERE c.id = v_assinatura.contrato_id;
    IF v_versao IS NOT NULL AND EXISTS (SELECT 1 FROM public.parceiro_contratos_versoes WHERE versao = v_versao) THEN
      SELECT user_id INTO v_uid FROM public.parceiro_usuarios WHERE parceiro_id = v_assinatura.parceiro_id ORDER BY (papel = 'dono') DESC, created_at LIMIT 1;
      INSERT INTO public.parceiro_contratos_aceites (parceiro_id, versao, user_id, ip, user_agent, hash_texto)
      VALUES (v_assinatura.parceiro_id, v_versao, coalesce(auth.uid(), v_uid), v_ip, left(_user_agent, 300),
              coalesce(_hash, encode(sha256(convert_to(coalesce(v_assinatura.html_assinado, ''), 'UTF8')), 'hex')))
      ON CONFLICT (parceiro_id, versao) DO NOTHING;
      UPDATE public.parceiros SET aceite_termos_em = coalesce(aceite_termos_em, now()),
        documento = coalesce(documento, nullif(_cpf, ''), nullif(_cnpj, '')),
        telefone = coalesce(telefone, nullif(_telefone, ''))
      WHERE id = v_assinatura.parceiro_id;
      UPDATE public.contratos_assinaturas SET observacoes = replace(coalesce(observacoes, ''), 'aguardando assinatura eletrônica', 'assinado eletronicamente (assinatura, selfie, IP, dispositivo, localização, hash)')
      WHERE id = v_assinatura.id;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok',true,'assinatura_id',v_assinatura.id, 'parceiro_id', v_assinatura.parceiro_id);
END;
$function$;

-- ---------------------------------------------------------------------
-- 5) Situação contratual do parceiro passa a informar o link pendente
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.parceiro_contrato_situacao(p_parceiro_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public
AS $parceiro_contrato_situacao$
  SELECT jsonb_build_object(
    'versao_vigente', (SELECT versao FROM public.parceiro_contratos_versoes WHERE vigente),
    'titulo_vigente', (SELECT titulo FROM public.parceiro_contratos_versoes WHERE vigente),
    'versao_aceita', (SELECT max(versao) FROM public.parceiro_contratos_aceites WHERE parceiro_id = p_parceiro_id),
    'aceito_em', (SELECT max(aceito_em) FROM public.parceiro_contratos_aceites WHERE parceiro_id = p_parceiro_id),
    'pendente', NOT EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites a
                            JOIN public.parceiro_contratos_versoes v ON v.versao = a.versao AND v.vigente
                            WHERE a.parceiro_id = p_parceiro_id),
    'assinatura_token', (SELECT s.token FROM public.contratos_assinaturas s
                         JOIN public.contratos_aceite c ON c.id = s.contrato_id AND c.categoria = 'parceria'
                         JOIN public.parceiro_contratos_versoes v ON v.versao = c.versao AND v.vigente
                         WHERE s.parceiro_id = p_parceiro_id AND s.status = 'pendente' AND (s.expira_em IS NULL OR s.expira_em > now())
                         ORDER BY s.created_at DESC LIMIT 1),
    'assinatura_id', (SELECT s.id FROM public.contratos_assinaturas s
                      JOIN public.contratos_aceite c ON c.id = s.contrato_id AND c.categoria = 'parceria'
                      JOIN public.parceiro_contratos_versoes v ON v.versao = c.versao AND v.vigente
                      WHERE s.parceiro_id = p_parceiro_id AND s.status = 'assinado'
                      ORDER BY s.assinado_em DESC LIMIT 1))
$parceiro_contrato_situacao$;

-- Publicar versão nova: o modelo novo já nasce exigindo as evidências
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
  PERFORM public.parceiro_contrato_modelo_vigente();
  RETURN v_versao;
END $superadmin_parceiro_contrato_publicar$;

-- Modelo vigente atualizado agora (flags de evidência), sem tocar assinaturas feitas
DO $modelo$
BEGIN
  PERFORM public.parceiro_contrato_modelo_vigente();
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'modelo vigente: %', SQLERRM;
END $modelo$;

-- Texto v2: a frase sobre a prova da contratação passa a descrever a assinatura
-- eletrônica completa (ainda não há assinatura em produção; hash recalculado)
UPDATE public.parceiro_contratos_versoes SET
  html = replace(replace(html,
    'O aceite eletrônico na Área do Parceiro, com registro de data, versão, usuário, endereço de rede e navegador, tem validade jurídica de assinatura (MP 2.200-2/2001, art. 10, § 2º; Lei 14.063/2020; Código Civil, art. 107).',
    'A assinatura eletrônica deste instrumento — assinatura manuscrita em tela, fotografia (selfie) do signatário, endereço de rede, dispositivo e navegador, coordenadas geográficas, data e hora e hash criptográfico do texto — tem validade jurídica de assinatura eletrônica avançada (Lei 14.063/2020, art. 4º, II; MP 2.200-2/2001, art. 10, § 2º; Código Civil, art. 107).'),
    '9.3. O aceite deste contrato é registrado com data, versão, usuário, endereço de rede e navegador como prova da contratação, e uma cópia assinada fica disponível para o Parceiro e para a YourEyes.',
    '9.3. A assinatura deste contrato é registrada com data, hora, versão, usuário, endereço de rede, dispositivo e navegador, coordenadas geográficas, imagem da assinatura, fotografia (selfie) do signatário e hash criptográfico do texto, como prova da contratação e da identidade do signatário (LGPD, art. 7º, V e II); a cópia assinada fica disponível para o Parceiro e para a YourEyes.')
WHERE versao = 2 AND html LIKE '%O aceite eletrônico na Área do Parceiro, com registro de data%';
UPDATE public.parceiro_contratos_versoes SET hash_texto = encode(sha256(convert_to(html, 'UTF8')), 'hex') WHERE versao = 2;
UPDATE public.contratos_aceite c SET corpo_html = v.html FROM public.parceiro_contratos_versoes v
WHERE c.categoria = 'parceria' AND c.versao = v.versao AND v.versao = 2 AND c.corpo_html <> v.html;

-- ---------------------------------------------------------------------
-- 6) QA — PGP-016 (api): assinatura eletrônica fecha o aceite
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros/programa-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;
  INSERT INTO public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  VALUES
  (v_mod, 'PGP-016', 'Contrato de Parceria: gerado com as duas partes (padrão ABNT) e aceito só após assinatura eletrônica com evidências',
   'feliz', 'alta', 'aprovado', 'api',
   'Lei 14.063/2020, art. 4º, II; MP 2.200-2/2001, art. 10, § 2º; Código Civil, art. 107; ABNT NBR 14724 (formatação)',
   'O clique de aceite no cadastro não basta. O contrato precisa ser gerado com a qualificação da YourEyes e do parceiro, formatado, e só conta como aceito quando a assinatura (imagem, selfie, IP, dispositivo, localização, hash) é registrada no mesmo fluxo dos contratos do SuperAdmin.',
   'Versão vigente do contrato publicada; dados fiscais da YourEyes preenchidos (ou traços).',
   '[{"ordem":1,"acao":"Iniciar a assinatura para um parceiro de QA","resultado_esperado":"Registro pendente em contratos_assinaturas com token, parceiro_id e html_assinado contendo o nome do parceiro, a razão social da YourEyes e o bloco ABNT; situação contratual pendente"},
     {"ordem":2,"acao":"Registrar a assinatura pelo token com selfie, IP, navegador, localização e hash","resultado_esperado":"Status assinado; parceiro_contratos_aceites ganha a versão; situação contratual deixa de ser pendente e aponta o id da assinatura"}]'::jsonb,
   'Contrato por parceiro, com as duas partes, no padrão ABNT; aceite fechado só pela assinatura eletrônica.',
   'A rotina cria e apaga o parceiro QA-PGP-CTR; nenhuma assinatura real é tocada.')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, objetivo = EXCLUDED.objetivo, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, base_legal = EXCLUDED.base_legal, observacoes = EXCLUDED.observacoes;
END $qa$;

CREATE OR REPLACE FUNCTION public.qa_caso_pgp_016()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_p uuid; v_ini jsonb; v_a public.contratos_assinaturas%ROWTYPE; v_sit jsonb; v_reg jsonb; v_ye text; v_v int;
BEGIN
  DELETE FROM public.parceiros WHERE codigo = 'QA-PGP-CTR';   -- sobra de execução avulsa
  SELECT versao INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v IS NULL THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: nenhuma versão vigente do contrato'; RETURN r; END IF;
  INSERT INTO public.parceiros (codigo, nome, tipo_pessoa, documento, email, telefone, cidade, uf, tipo_parceiro, trilha, status)
  VALUES ('QA-PGP-CTR', 'QA Contrato Parceiro', 'pf', '900.000.011-47', 'qa-ctr@exemplo.test', '46999990000', 'Pato Branco', 'PR', 'indicador', 'indicador', 'ativo') RETURNING id INTO v_p;

  r.passo_ordem := 1; r.passo_acao := 'Iniciar a assinatura para o parceiro de QA';
  r.esperado := 'Pendente com token, html com as duas partes e bloco ABNT; situação pendente';
  v_ini := public.parceiro_contrato_iniciar_assinatura_para(v_p);
  SELECT * INTO v_a FROM public.contratos_assinaturas WHERE token = v_ini->>'token';
  v_sit := public.parceiro_contrato_situacao(v_p);
  v_ye := coalesce(public.youreyes_empresa_publica()->>'razao_social', 'YourEyes');
  IF v_a.id IS NULL OR v_a.status <> 'pendente' OR v_a.parceiro_id <> v_p
     OR v_a.html_assinado NOT LIKE '%contrato-abnt%' OR v_a.html_assinado NOT LIKE '%QA Contrato Parceiro%'
     OR v_a.html_assinado NOT LIKE '%' || v_ye || '%' OR v_a.html_assinado NOT LIKE '%Qualificação das partes%'
     OR (v_sit->>'pendente')::boolean IS NOT TRUE OR v_sit->>'assinatura_token' IS DISTINCT FROM v_a.token THEN
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: status=%s, abnt=%s, parceiro_no_texto=%s, ye_no_texto=%s, pendente=%s, token_na_situacao=%s',
      v_a.status, v_a.html_assinado LIKE '%contrato-abnt%', v_a.html_assinado LIKE '%QA Contrato Parceiro%', v_a.html_assinado LIKE '%' || v_ye || '%', v_sit->>'pendente', v_sit->>'assinatura_token' = v_a.token);
    DELETE FROM public.parceiros WHERE id = v_p; RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Registrar a assinatura pelo token com evidências';
  r.esperado := 'Assinado; aceite da versão gravado; situação deixa de ser pendente';
  -- notação nomeada: existem duas sobrecargas (14 e 17 parâmetros); _cnpj só existe na completa
  v_reg := public.registrar_assinatura_contrato(_token => v_a.token, _nome => 'QA Contrato Parceiro', _cpf => '900.000.011-47',
    _email => 'qa-ctr@exemplo.test', _telefone => '46999990000', _endereco => 'Rua de Teste, 1 - Centro, Pato Branco/PR',
    _assinatura_imagem => 'data:image/png;base64,QA', _selfie_imagem => 'data:image/jpeg;base64,QA', _ip => '203.0.113.10',
    _user_agent => 'QA/1.0', _geo_lat => -26.2291, _geo_lng => -52.6706, _hash => repeat('a', 64), _cnpj => NULL);
  SELECT * INTO v_a FROM public.contratos_assinaturas WHERE id = v_a.id;
  v_sit := public.parceiro_contrato_situacao(v_p);
  IF (v_reg->>'ok')::boolean AND v_a.status = 'assinado' AND v_a.selfie_imagem IS NOT NULL AND v_a.geo_lat IS NOT NULL AND v_a.ip_address = '203.0.113.10'
     AND EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites WHERE parceiro_id = v_p AND versao = v_v)
     AND (v_sit->>'pendente')::boolean IS FALSE AND (v_sit->>'assinatura_id')::uuid = v_a.id THEN
    r.situacao := 'passou'; r.obtido := 'Contrato gerado com as duas partes em padrão ABNT; assinatura com evidências fechou o aceite da versão ' || v_v || '.';
  ELSE
    r.situacao := 'falhou';
    r.obtido := format('ACHADO: ok=%s, status=%s, aceite=%s, pendente=%s', v_reg->>'ok', v_a.status,
      EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites WHERE parceiro_id = v_p AND versao = v_v), v_sit->>'pendente');
  END IF;
  DELETE FROM public.parceiros WHERE id = v_p;   -- cascata apaga aceite; a assinatura fica sem parceiro
  DELETE FROM public.contratos_assinaturas WHERE id = v_a.id;
  RETURN r;
EXCEPTION WHEN OTHERS THEN r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES ('PGP-016', 'qa_caso_pgp_016')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ---------------------------------------------------------------------
-- CONFERÊNCIA (único resultado exibido pelo editor)
-- ---------------------------------------------------------------------
WITH f AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE p.proname = 'parceiro_contrato_render_abnt') AS render_abnt,
         count(*) FILTER (WHERE p.proname = 'parceiro_contrato_iniciar_assinatura') AS iniciar,
         count(*) FILTER (WHERE p.proname = 'parceiro_contrato_iniciar_assinatura_para') AS iniciar_para,
         count(*) FILTER (WHERE p.proname = 'parceiro_contrato_modelo_vigente') AS modelo,
         count(*) FILTER (WHERE p.proname = 'qa_caso_pgp_016') AS qa016
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
), m AS MATERIALIZED (
  SELECT count(*) AS modelos_parceria_ok
  FROM public.contratos_aceite c JOIN public.parceiro_contratos_versoes v ON v.versao = c.versao AND v.vigente
  WHERE c.categoria = 'parceria' AND c.ativo AND c.requer_cpf AND c.requer_selfie AND c.requer_geolocalizacao
), t AS MATERIALIZED (
  SELECT (public.parceiro_contrato_render_abnt(NULL) LIKE '%contrato-abnt%') AS render_abnt_ok,
         (SELECT html LIKE '%assinatura eletrônica avançada%' FROM public.parceiro_contratos_versoes WHERE versao = 2) AS texto_v2_ok
), q AS MATERIALIZED (
  SELECT r.situacao, r.erro_tecnico FROM public.qa_caso_pgp_016() r
)
SELECT
  CASE WHEN f.render_abnt = 1 AND f.iniciar = 1 AND f.iniciar_para = 1 AND f.modelo = 1 AND f.qa016 = 1
        AND m.modelos_parceria_ok >= 1 AND t.render_abnt_ok AND coalesce(t.texto_v2_ok, true) AND q.situacao = 'passou'
       THEN 'OK' ELSE 'REVISAR' END AS resultado,
  f.render_abnt, f.iniciar, f.iniciar_para, f.modelo, f.qa016,
  m.modelos_parceria_ok, t.render_abnt_ok, t.texto_v2_ok,
  q.situacao AS qa_pgp_016, q.erro_tecnico
FROM f, m, t, q;
