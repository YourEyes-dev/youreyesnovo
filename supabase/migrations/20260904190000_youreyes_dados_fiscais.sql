-- =====================================================================
-- DADOS FISCAIS/CONTÁBEIS DA YOUREYES (um único registro)
--
-- Razão social, CNPJ, endereço, contato, representante legal e foro, usados
-- nos contratos (Programa de Parceiros e futuros) e em documentos emitidos
-- pela casa. Editável só pelo SuperAdmin; a leitura pública devolve apenas o
-- que vai em contrato (sem CPF do representante). Só cria. Idempotente.
-- =====================================================================
SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.youreyes_empresa (
  id                    int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  razao_social          text NOT NULL DEFAULT 'YourEyes',
  nome_fantasia         text NOT NULL DEFAULT 'YourEyes',
  cnpj                  text,
  inscricao_estadual    text,
  inscricao_municipal   text,
  endereco              text,
  numero                text,
  complemento           text,
  bairro                text,
  cidade                text,
  uf                    text,
  cep                   text,
  email_contato         text NOT NULL DEFAULT 'contato@youreyes.com.br',
  email_financeiro      text,
  telefone              text,
  site                  text NOT NULL DEFAULT 'https://youreyes.com.br',
  representante_nome    text,
  representante_cargo   text,
  representante_cpf     text,          -- sensível: nunca sai na leitura pública
  foro_comarca          text,
  regime_tributario     text,
  observacoes           text,
  atualizado_em         timestamptz NOT NULL DEFAULT now(),
  atualizado_por        uuid
);
COMMENT ON TABLE public.youreyes_empresa IS 'Dados fiscais/contábeis da própria YourEyes (registro único), usados em contratos e documentos.';
ALTER TABLE public.youreyes_empresa ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS youreyes_empresa_superadmin ON public.youreyes_empresa;
CREATE POLICY youreyes_empresa_superadmin ON public.youreyes_empresa FOR ALL TO authenticated
  USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));
GRANT SELECT, INSERT, UPDATE ON public.youreyes_empresa TO authenticated;
GRANT ALL ON public.youreyes_empresa TO service_role;
INSERT INTO public.youreyes_empresa (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.superadmin_youreyes_empresa_salvar(_dados jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $superadmin_youreyes_empresa_salvar$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.youreyes_empresa (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
  UPDATE public.youreyes_empresa SET
    razao_social = coalesce(nullif(_dados->>'razao_social',''), razao_social),
    nome_fantasia = coalesce(nullif(_dados->>'nome_fantasia',''), nome_fantasia),
    cnpj = nullif(_dados->>'cnpj',''), inscricao_estadual = nullif(_dados->>'inscricao_estadual',''),
    inscricao_municipal = nullif(_dados->>'inscricao_municipal',''),
    endereco = nullif(_dados->>'endereco',''), numero = nullif(_dados->>'numero',''), complemento = nullif(_dados->>'complemento',''),
    bairro = nullif(_dados->>'bairro',''), cidade = nullif(_dados->>'cidade',''), uf = nullif(upper(_dados->>'uf'),''), cep = nullif(_dados->>'cep',''),
    email_contato = coalesce(nullif(_dados->>'email_contato',''), email_contato), email_financeiro = nullif(_dados->>'email_financeiro',''),
    telefone = nullif(_dados->>'telefone',''), site = coalesce(nullif(_dados->>'site',''), site),
    representante_nome = nullif(_dados->>'representante_nome',''), representante_cargo = nullif(_dados->>'representante_cargo',''),
    representante_cpf = nullif(_dados->>'representante_cpf',''), foro_comarca = nullif(_dados->>'foro_comarca',''),
    regime_tributario = nullif(_dados->>'regime_tributario',''), observacoes = nullif(_dados->>'observacoes',''),
    atualizado_em = now(), atualizado_por = auth.uid()
  WHERE id = 1;
END $superadmin_youreyes_empresa_salvar$;
GRANT EXECUTE ON FUNCTION public.superadmin_youreyes_empresa_salvar(jsonb) TO authenticated;

-- Leitura pública: só o que vai em contrato/documento (sem CPF, sem observações)
CREATE OR REPLACE FUNCTION public.youreyes_empresa_publica()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $youreyes_empresa_publica$
  SELECT jsonb_build_object(
    'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia, 'cnpj', e.cnpj,
    'endereco_completo', concat_ws(', ', nullif(concat_ws(' ', e.endereco, e.numero), ''), e.complemento, e.bairro,
                                   nullif(concat_ws('/', e.cidade, e.uf), ''), CASE WHEN e.cep IS NOT NULL THEN 'CEP ' || e.cep END),
    'cidade', e.cidade, 'uf', e.uf, 'email_contato', e.email_contato, 'telefone', e.telefone, 'site', e.site,
    'representante_nome', e.representante_nome, 'representante_cargo', e.representante_cargo,
    'foro_comarca', coalesce(e.foro_comarca, nullif(concat_ws('/', e.cidade, e.uf), '')))
  FROM public.youreyes_empresa e WHERE e.id = 1
$youreyes_empresa_publica$;
GRANT EXECUTE ON FUNCTION public.youreyes_empresa_publica() TO anon, authenticated;

-- Contrato: placeholders da casa
CREATE OR REPLACE FUNCTION public.parceiro_contrato_render(p_parceiro_id uuid, p_html text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $parceiro_contrato_render$
DECLARE v_p public.parceiros%ROWTYPE; v_html text; v_matriz text; v_setup text; v_ye jsonb := public.youreyes_empresa_publica();
BEGIN
  SELECT * INTO v_p FROM public.parceiros WHERE id = p_parceiro_id;
  v_html := coalesce(p_html, (SELECT html FROM public.parceiro_contratos_versoes WHERE vigente));
  SELECT string_agg(format('%s: %s%% (Foco) · %s%% (Visão) · %s%% (Diamante)', initcap(trilha), f, v, d), '; ' ORDER BY trilha) INTO v_matriz
  FROM (SELECT trilha, max(percentual_link) FILTER (WHERE ordem=1) f, max(percentual_link) FILTER (WHERE ordem=2) v, max(percentual_link) FILTER (WHERE ordem=3) d FROM public.parceiro_niveis WHERE ativo GROUP BY trilha) m;
  SELECT string_agg(format('%s: %s%% / %s%% / %s%%', initcap(trilha), f, v, d), '; ' ORDER BY trilha) INTO v_setup
  FROM (SELECT trilha, max(setup_participacao_pct) FILTER (WHERE ordem=1) f, max(setup_participacao_pct) FILTER (WHERE ordem=2) v, max(setup_participacao_pct) FILTER (WHERE ordem=3) d FROM public.parceiro_niveis WHERE ativo GROUP BY trilha) m;
  v_html := replace(v_html, '{{YE_RAZAO_SOCIAL}}', coalesce(v_ye->>'razao_social', 'YourEyes'));
  v_html := replace(v_html, '{{YE_CNPJ}}', coalesce(v_ye->>'cnpj', '________________'));
  v_html := replace(v_html, '{{YE_ENDERECO}}', coalesce(nullif(v_ye->>'endereco_completo',''), '________________'));
  v_html := replace(v_html, '{{YE_EMAIL}}', coalesce(v_ye->>'email_contato', 'contato@youreyes.com.br'));
  v_html := replace(v_html, '{{YE_FORO}}', coalesce(nullif(v_ye->>'foro_comarca',''), 'sede da YourEyes'));
  v_html := replace(v_html, '{{YE_REPRESENTANTE}}', CASE WHEN v_ye->>'representante_nome' IS NOT NULL THEN ', representada por ' || (v_ye->>'representante_nome') || coalesce(' (' || (v_ye->>'representante_cargo') || ')', '') ELSE '' END);
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

-- Texto v2 passa a identificar a YourEyes pelos dados fiscais (nenhum aceite em produção ainda)
UPDATE public.parceiro_contratos_versoes SET
  html = replace(replace(replace(html,
    '<p><strong>YOUREYES</strong>, plataforma de gestão de pessoas, departamento pessoal, saúde e segurança do trabalho e clima psicossocial ("YourEyes"), e ',
    '<p><strong>{{YE_RAZAO_SOCIAL}}</strong>, CNPJ {{YE_CNPJ}}, com sede em {{YE_ENDERECO}}{{YE_REPRESENTANTE}}, mantenedora da plataforma YourEyes de gestão de pessoas, departamento pessoal, saúde e segurança do trabalho e clima psicossocial ("YourEyes"), e '),
    'Comunicações formais pelo e-mail cadastrado na Área do Parceiro e pelo e-mail contato@youreyes.com.br.',
    'Comunicações formais pelo e-mail cadastrado na Área do Parceiro e pelo e-mail {{YE_EMAIL}}.'),
    'fica eleito o foro da comarca da sede da YourEyes, com renúncia a qualquer outro',
    'fica eleito o foro da comarca de {{YE_FORO}}, com renúncia a qualquer outro')
WHERE versao = 2 AND html NOT LIKE '%{{YE_RAZAO_SOCIAL}}%';
UPDATE public.parceiro_contratos_versoes SET hash_texto = encode(sha256(convert_to(html, 'UTF8')), 'hex') WHERE versao = 2;
UPDATE public.contratos_aceite c SET corpo_html = v.html FROM public.parceiro_contratos_versoes v
WHERE c.categoria = 'parceria' AND c.versao = v.versao AND v.versao = 2;
