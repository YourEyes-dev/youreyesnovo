-- =====================================================================
-- PROGRAMA DE PARCEIROS · CONTRATO DE PARCERIA · SCRIPT DE ENTREGA
-- Cole no SQL Editor de cada ambiente (Teste → Homologação → Produção),
-- avançando só depois que o anterior devolver OK. Requer as Ondas 1 e 2.
--
-- O que faz: versões do Contrato de Parceria com aceite eletrônico
-- registrado (versão, hash, data, usuário, IP, navegador), amarrado ao
-- cadastro; situação contratual no portal e no SuperAdmin; texto v1 da
-- Política de Parceiros. Só cria/insere. Idempotente.
-- Corresponde à migration 20260904140000_parceiros_contrato.sql.
-- =====================================================================

-- =====================================================================
-- PROGRAMA DE PARCEIROS · CONTRATO DE PARCERIA (aceite eletrônico)
--
-- Onde o contrato se amarra: no CADASTRO. Ninguém vira parceiro sem aceitar
-- a versão vigente do Contrato de Parceria (clickwrap com registro de
-- versão, hash do texto, data, usuário, IP e navegador). Quando a casa
-- publica uma versão nova, o portal exibe o aviso e o parceiro precisa
-- aceitar de novo; até lá o link continua funcionando, mas a pendência fica
-- visível para ele e para o SuperAdmin.
--
-- O texto vive em tabela (parceiro_contratos_versoes), não no código, para a
-- casa revisar com o jurídico sem nova publicação de tela. A versão 1 abaixo
-- consolida a Política de Parceiros: papéis, remuneração (níveis, base,
-- fechamento 25 / pagamento 10, bônus, setup), atribuição, confidencialidade,
-- segredos comerciais, não concorrência e não aliciamento, marca, LGPD,
-- vigência e rescisão. Revisão jurídica recomendada antes da produção.
-- Só cria/insere. Idempotente.
-- =====================================================================

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.parceiro_contratos_versoes (
  versao        int PRIMARY KEY,
  titulo        text NOT NULL,
  html          text NOT NULL,
  hash_texto    text NOT NULL,
  vigente       boolean NOT NULL DEFAULT false,
  publicado_em  timestamptz NOT NULL DEFAULT now(),
  publicado_por uuid
);
COMMENT ON TABLE public.parceiro_contratos_versoes IS
  'Versões do Contrato de Parceria (Política de Parceiros). Uma vigente por vez.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_parceiro_contrato_vigente
  ON public.parceiro_contratos_versoes (vigente) WHERE vigente;

CREATE TABLE IF NOT EXISTS public.parceiro_contratos_aceites (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parceiro_id  uuid NOT NULL REFERENCES public.parceiros(id) ON DELETE CASCADE,
  versao       int  NOT NULL REFERENCES public.parceiro_contratos_versoes(versao),
  user_id      uuid,
  aceito_em    timestamptz NOT NULL DEFAULT now(),
  ip           text,
  user_agent   text,
  hash_texto   text NOT NULL,
  UNIQUE (parceiro_id, versao)
);
COMMENT ON TABLE public.parceiro_contratos_aceites IS
  'Aceite eletrônico do Contrato de Parceria: quem, quando, de onde, qual versão e qual texto (hash).';

ALTER TABLE public.parceiro_contratos_versoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parceiro_contratos_aceites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parceiro_contratos_versoes_leitura ON public.parceiro_contratos_versoes;
CREATE POLICY parceiro_contratos_versoes_leitura ON public.parceiro_contratos_versoes
  FOR SELECT TO anon, authenticated USING (true);   -- texto público, como os Termos de Uso
DROP POLICY IF EXISTS parceiro_contratos_versoes_superadmin ON public.parceiro_contratos_versoes;
CREATE POLICY parceiro_contratos_versoes_superadmin ON public.parceiro_contratos_versoes
  FOR ALL TO authenticated USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS parceiro_contratos_aceites_proprio ON public.parceiro_contratos_aceites;
CREATE POLICY parceiro_contratos_aceites_proprio ON public.parceiro_contratos_aceites
  FOR SELECT TO authenticated
  USING (parceiro_id = public.parceiro_meu_id() OR public.is_superadmin(auth.uid()));

GRANT SELECT ON public.parceiro_contratos_versoes TO anon, authenticated;
GRANT SELECT ON public.parceiro_contratos_aceites TO authenticated;
GRANT ALL ON public.parceiro_contratos_versoes, public.parceiro_contratos_aceites TO service_role;

-- Registra o aceite do parceiro logado na versão vigente (idempotente por versão).
CREATE OR REPLACE FUNCTION public.parceiro_aceitar_contrato(_user_agent text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_aceitar_contrato$
DECLARE v_pid uuid := public.parceiro_meu_id(); v_v public.parceiro_contratos_versoes%ROWTYPE; v_ip text;
BEGIN
  IF v_pid IS NULL THEN RAISE EXCEPTION 'Sem vínculo com parceiro'; END IF;
  SELECT * INTO v_v FROM public.parceiro_contratos_versoes WHERE vigente;
  IF v_v.versao IS NULL THEN RAISE EXCEPTION 'Nenhuma versão vigente do contrato'; END IF;
  BEGIN
    v_ip := coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for',
                     current_setting('request.headers', true)::json->>'cf-connecting-ip');
  EXCEPTION WHEN OTHERS THEN v_ip := NULL; END;
  INSERT INTO public.parceiro_contratos_aceites (parceiro_id, versao, user_id, ip, user_agent, hash_texto)
  VALUES (v_pid, v_v.versao, auth.uid(), v_ip, left(_user_agent, 300), v_v.hash_texto)
  ON CONFLICT (parceiro_id, versao) DO NOTHING;
  UPDATE public.parceiros SET aceite_termos_em = coalesce(aceite_termos_em, now()) WHERE id = v_pid;
  RETURN jsonb_build_object('ok', true, 'versao', v_v.versao);
END $parceiro_aceitar_contrato$;
GRANT EXECUTE ON FUNCTION public.parceiro_aceitar_contrato(text) TO authenticated;

-- Situação contratual de um parceiro (usada pelo portal e pelo SuperAdmin)
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
                            WHERE a.parceiro_id = p_parceiro_id))
$parceiro_contrato_situacao$;

-- Cadastro autenticado passa a registrar o aceite do contrato junto
CREATE OR REPLACE FUNCTION public.parceiro_cadastrar(_dados jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $parceiro_cadastrar$
DECLARE v_id uuid; v_uid uuid := auth.uid(); v_mp uuid; v_email text;
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
    (nome, tipo_pessoa, documento, tipo_parceiro, email, telefone, cidade, uf, cep,
     raio_atuacao_km, aceite_termos_em, marketplace_profissional_id, created_by)
  VALUES
    (_dados->>'nome', coalesce(_dados->>'tipo_pessoa','pj'), nullif(_dados->>'documento',''),
     coalesce(_dados->>'tipo_parceiro','indicador'), coalesce(nullif(_dados->>'email',''), v_email),
     nullif(_dados->>'telefone',''), nullif(_dados->>'cidade',''), nullif(upper(_dados->>'uf'),''),
     nullif(_dados->>'cep',''), coalesce((_dados->>'raio_atuacao_km')::int, 50), now(), v_mp, v_uid)
  RETURNING id INTO v_id;

  INSERT INTO public.parceiro_usuarios (parceiro_id, user_id, papel) VALUES (v_id, v_uid, 'dono');
  PERFORM public.parceiro_aceitar_contrato(_dados->>'user_agent');
  RETURN jsonb_build_object('ok', true, 'parceiro_id', v_id,
    'status', (SELECT status FROM public.parceiros WHERE id = v_id),
    'codigo', (SELECT codigo FROM public.parceiros WHERE id = v_id));
END $parceiro_cadastrar$;

-- Lista do SuperAdmin ganha a situação contratual
CREATE OR REPLACE FUNCTION public.superadmin_parceiros_list()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiros_list$
DECLARE result jsonb;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT jsonb_agg(row_to_json(x) ORDER BY x.status = 'pendente' DESC, x.created_at DESC) INTO result
  FROM (
    SELECT p.id, p.codigo, p.nome, p.tipo_pessoa, p.documento, p.tipo_parceiro, p.email, p.telefone,
           p.cidade, p.uf, p.cep, p.raio_atuacao_km, p.trilha, p.nivel_id, n.nome AS nivel_nome,
           p.percentual_comissao, p.status, p.aprovacao, p.aprovado_em, p.motivo_recusa,
           p.parceiro_desde, p.pix_chave, p.marketplace_profissional_id, p.observacoes, p.created_at,
           (SELECT count(*) FROM public.tenants t WHERE t.parceiro_id = p.id)            AS total_clientes,
           (SELECT count(*) FROM public.tenants t WHERE t.implantador_parceiro_id = p.id) AS total_implantacoes,
           (SELECT count(*) FROM public.leads l WHERE l.parceiro_id = p.id AND l.deleted_at IS NULL) AS total_leads,
           (SELECT count(*) FROM public.parceiro_links k WHERE k.parceiro_id = p.id AND k.ativo) AS total_links,
           (SELECT string_agg(u.email, ', ') FROM public.parceiro_usuarios pu
              JOIN auth.users u ON u.id = pu.user_id WHERE pu.parceiro_id = p.id) AS usuarios,
           public.parceiro_contrato_situacao(p.id) AS contrato
    FROM public.parceiros p
    LEFT JOIN public.parceiro_niveis n ON n.id = p.nivel_id
  ) x;
  RETURN coalesce(result, '[]'::jsonb);
END $superadmin_parceiros_list$;

-- Portal: acrescenta a situação contratual ao que já devolve
CREATE OR REPLACE FUNCTION public.parceiro_meu_portal_com_contrato()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $parceiro_meu_portal_com_contrato$
  SELECT CASE WHEN public.parceiro_meu_id() IS NULL THEN NULL
         ELSE public.parceiro_meu_portal() || jsonb_build_object('contrato', public.parceiro_contrato_situacao(public.parceiro_meu_id())) END
$parceiro_meu_portal_com_contrato$;
GRANT EXECUTE ON FUNCTION public.parceiro_meu_portal_com_contrato() TO authenticated;

-- Publicar nova versão (SuperAdmin): a anterior deixa de ser vigente
CREATE OR REPLACE FUNCTION public.superadmin_parceiro_contrato_publicar(_titulo text, _html text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $superadmin_parceiro_contrato_publicar$
DECLARE v_versao int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  UPDATE public.parceiro_contratos_versoes SET vigente = false WHERE vigente;
  SELECT coalesce(max(versao),0) + 1 INTO v_versao FROM public.parceiro_contratos_versoes;
  INSERT INTO public.parceiro_contratos_versoes (versao, titulo, html, hash_texto, vigente, publicado_por)
  VALUES (v_versao, _titulo, _html, encode(sha256(convert_to(_html, 'UTF8')), 'hex'), true, auth.uid());
  RETURN v_versao;
END $superadmin_parceiro_contrato_publicar$;
GRANT EXECUTE ON FUNCTION public.superadmin_parceiro_contrato_publicar(text, text) TO authenticated;

-- ---------------------------------------------------------------------
-- Versão 1 do Contrato de Parceria (Política de Parceiros consolidada)
-- ---------------------------------------------------------------------
DO $contrato$
DECLARE v_html text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.parceiro_contratos_versoes) THEN RETURN; END IF;
  v_html := $H$
<h2>Contrato de Parceria Comercial — Programa de Parceiros YourEyes</h2>
<p><strong>Versão 1</strong> · vigente a partir de 03/09/2026</p>
<p>Este contrato regula a relação entre a <strong>YourEyes</strong> (plataforma de maturidade organizacional: RH, DP, SST e psicossocial) e a pessoa física ou jurídica que adere ao Programa de Parceiros (<strong>Parceiro</strong>), nas modalidades Indicador, Representante, Implantador, Clínica de SST e Contabilidade. O aceite eletrônico no cadastro, com registro de data, versão, usuário e endereço de rede, tem valor de assinatura (Lei 14.063/2020 e MP 2.200-2/2001).</p>

<h3>1. Objeto</h3>
<p>1.1. O Parceiro passa a indicar, representar, implantar ou atender empresas clientes da YourEyes, conforme a modalidade escolhida e aprovada, e recebe remuneração pelas contas que originar ou pelos eventos que executar, nos termos deste contrato.</p>
<p>1.2. A parceria não cria vínculo de emprego, sociedade, franquia, mandato ou representação comercial com exclusividade. O Parceiro atua por conta própria, com autonomia e sem subordinação.</p>

<h3>2. Modalidades e aprovação</h3>
<p>2.1. <strong>Indicador</strong>: divulga o link de indicação; adesão imediata. <strong>Representante</strong>: apresenta a plataforma, conduz proposta e acompanha até o contrato. <strong>Implantador</strong>: executa a implantação (setup) do cliente. <strong>Clínica de SST</strong> e <strong>Contabilidade</strong>: atendem clientes na sua região e indicam novas empresas.</p>
<p>2.2. As modalidades Representante, Implantador, Clínica e Contabilidade dependem de aprovação da YourEyes, que pode solicitar documentos (CNPJ, registro profissional, referências) e recusar ou suspender sem necessidade de justificativa detalhada.</p>

<h3>3. Atribuição de clientes</h3>
<p>3.1. Uma empresa é atribuída ao Parceiro quando (a) acessa a YourEyes pelo link de indicação do Parceiro e conclui o cadastro ou a contratação em até 90 dias do primeiro clique, ou (b) é vinculada ao Parceiro pela YourEyes (lead encaminhado pela casa, por proximidade ou acordo).</p>
<p>3.2. Vale o primeiro registro de origem. Cliente já existente na base da YourEyes, ou já em negociação pela equipe própria, não é atribuído ao Parceiro.</p>
<p>3.3. A YourEyes pode indicar ao Parceiro, por localidade, leads que chegam sem origem; a atribuição pela casa pode ter percentual próprio, conforme a tabela de níveis.</p>

<h3>4. Remuneração</h3>
<p>4.1. <strong>Comissão recorrente</strong>: percentual da mensalidade de tabela do plano público do cliente atribuído (mais módulos e vidas adicionais contratados), devida a cada mês em que a assinatura do cliente estiver ativa e paga.</p>
<p>4.2. <strong>Níveis</strong>: o percentual depende do nível do Parceiro na sua trilha, medido pelo MRR sob atendimento (soma das mensalidades de tabela dos clientes ativos originados). Níveis, faixas e percentuais vigentes constam na Área do Parceiro e podem ser revisados pela YourEyes com aviso de 30 dias, sem efeito retroativo.</p>
<p>4.3. <strong>Eventos</strong>: o Implantador recebe, uma única vez por cliente, o valor de setup configurado na tabela de remuneração por evento quando o cliente conclui a implantação (onboarding). Renovações de ciclo contratual rendem bônus, conforme multiplicador do nível.</p>
<p>4.4. <strong>Base</strong>: preço de tabela vigente na data do fechamento. Descontos promocionais, planos internos, planos de teste e períodos de inadimplência não geram comissão; comissão de cliente inadimplente fica retida e é liberada com a regularização.</p>
<p>4.5. <strong>Fechamento e pagamento</strong>: a competência fecha no dia 25 de cada mês e o pagamento ocorre até o dia 10 do mês seguinte, por PIX na chave informada pelo Parceiro, mediante emissão do documento fiscal cabível (nota fiscal ou recibo, conforme a natureza do Parceiro). Valores abaixo de R$ 100,00 acumulam para o mês seguinte.</p>
<p>4.6. Tributos incidentes sobre a remuneração são de responsabilidade do Parceiro.</p>

<h3>5. Obrigações do Parceiro</h3>
<p>5.1. Apresentar a YourEyes com veracidade, sem promessas de funcionalidade, prazo ou preço que não constem do material oficial.</p>
<p>5.2. Não praticar spam, publicidade enganosa, compra de palavras-chave com a marca YourEyes, nem inserir o link de indicação em cadastros feitos por terceiros sem o seu conhecimento.</p>
<p>5.3. Manter cadastro, dados de contato e chave PIX atualizados na Área do Parceiro.</p>
<p>5.4. Quando Implantador, Clínica ou Contabilidade: prestar o serviço com diligência, dentro dos padrões orientados pela YourEyes, e comunicar imediatamente qualquer incidente que envolva dados de clientes.</p>

<h3>6. Confidencialidade e segredos comerciais</h3>
<p>6.1. São <strong>informações confidenciais</strong> da YourEyes, entre outras: tabela de preços e descontos não públicos, estrutura de comissões e níveis, roteiros comerciais, materiais de implantação, metodologias, roadmap de produto, métricas de clientes, relação de clientes e leads, e todo dado a que o Parceiro tenha acesso pela Área do Parceiro ou pela plataforma.</p>
<p>6.2. O Parceiro compromete-se a usar essas informações exclusivamente para os fins deste contrato, a não as divulgar a terceiros e a protegê-las com o mesmo cuidado que dedica às suas próprias informações sigilosas. A obrigação vigora durante a parceria e por <strong>5 (cinco) anos</strong> após o seu término; para segredos de negócio (Lei 9.279/1996, art. 195), enquanto mantiverem essa natureza.</p>
<p>6.3. Dados de pessoas físicas (colaboradores de clientes, informações de saúde e psicossociais) <strong>não são compartilhados</strong> com o Parceiro; a Área do Parceiro exibe apenas dados da empresa cliente (nome, plano, estágio, valores). Qualquer acesso incidental a dado pessoal obriga o Parceiro ao sigilo e à comunicação imediata à YourEyes (LGPD, Lei 13.709/2018).</p>

<h3>7. Não concorrência e não aliciamento</h3>
<p>7.1. Durante a vigência e por <strong>12 (doze) meses</strong> após o término, o Parceiro não desenvolverá, comercializará nem representará plataforma de software concorrente da YourEyes (gestão integrada de RH, DP, ponto, saúde ocupacional e psicossocial) valendo-se de informações confidenciais, materiais, listas de clientes ou relacionamentos obtidos por meio desta parceria.</p>
<p>7.2. No mesmo período, o Parceiro não aliciará clientes atribuídos por este programa para migrar a plataforma concorrente, nem aliciará colaboradores ou outros parceiros da YourEyes.</p>
<p>7.3. Esta cláusula não impede o Parceiro de exercer sua atividade principal (clínica, contabilidade, consultoria) nem de atender os mesmos clientes com serviços próprios que não substituam a plataforma.</p>
<p>7.4. A violação das cláusulas 6 e 7 sujeita o Parceiro à perda das comissões futuras, à devolução das comissões recebidas nos 12 meses anteriores à infração e a indenização pelas perdas comprovadas, sem prejuízo das medidas judiciais cabíveis.</p>

<h3>8. Marca, materiais e propriedade intelectual</h3>
<p>8.1. A YourEyes concede ao Parceiro licença gratuita, não exclusiva e revogável para usar a marca e os materiais oficiais exclusivamente na divulgação do programa, conforme o manual de marca disponibilizado. É vedado registrar domínios, perfis ou marcas que contenham "YourEyes".</p>
<p>8.2. Toda propriedade intelectual da plataforma, dos materiais e das metodologias permanece da YourEyes. Sugestões do Parceiro incorporadas ao produto não geram direito a remuneração adicional.</p>

<h3>9. Proteção de dados</h3>
<p>9.1. Cada parte é controladora dos dados pessoais que trata por conta própria. Os dados cadastrais do Parceiro são tratados pela YourEyes para execução deste contrato, pagamento e obrigações legais, e ficam disponíveis para consulta e correção na Área do Parceiro.</p>
<p>9.2. A YourEyes registra o aceite deste contrato com data, versão, usuário, endereço de rede e navegador, como prova da contratação.</p>

<h3>10. Vigência, suspensão e rescisão</h3>
<p>10.1. Vigência por prazo indeterminado, a partir do aceite. Qualquer parte pode rescindir sem ônus com aviso de 30 dias.</p>
<p>10.2. A YourEyes pode suspender ou encerrar o Parceiro de imediato em caso de fraude, violação das cláusulas 5 a 8, dano à imagem da marca ou inatividade superior a 12 meses.</p>
<p>10.3. Na rescisão sem infração, as comissões recorrentes dos clientes já atribuídos continuam devidas por <strong>6 (seis) meses</strong> após o término, ou até o fim do ciclo contratual vigente do cliente, o que ocorrer primeiro. Na rescisão por infração, cessam de imediato.</p>

<h3>11. Disposições gerais</h3>
<p>11.1. A YourEyes pode publicar nova versão deste contrato; a versão nova é apresentada na Área do Parceiro e passa a valer para o Parceiro após o seu aceite. Enquanto não aceitar, aplica-se a versão anterior por até 60 dias, após o que a parceria pode ser suspensa.</p>
<p>11.2. Este contrato complementa os Termos de Uso e a Política de Privacidade da YourEyes. Em caso de conflito sobre o programa de parceiros, prevalece este contrato.</p>
<p>11.3. Fica eleito o foro da comarca da sede da YourEyes, com renúncia a qualquer outro, para dirimir controvérsias, admitida a mediação prévia.</p>
$H$;
  INSERT INTO public.parceiro_contratos_versoes (versao, titulo, html, hash_texto, vigente)
  VALUES (1, 'Contrato de Parceria Comercial — Programa de Parceiros YourEyes (v1)', v_html,
          encode(sha256(convert_to(v_html, 'UTF8')), 'hex'), true);
END $contrato$;

-- Parceiros já cadastrados antes do contrato existir: registra o aceite dos
-- Termos feito no cadastro como aceite da v1 (aceite_termos_em) para não
-- bloquear ninguém; quem não tinha aceite fica pendente e vê o aviso.
INSERT INTO public.parceiro_contratos_aceites (parceiro_id, versao, user_id, aceito_em, hash_texto)
SELECT p.id, 1, (SELECT user_id FROM public.parceiro_usuarios pu WHERE pu.parceiro_id = p.id LIMIT 1),
       p.aceite_termos_em, (SELECT hash_texto FROM public.parceiro_contratos_versoes WHERE versao = 1)
FROM public.parceiros p
WHERE p.aceite_termos_em IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.parceiro_contratos_aceites a WHERE a.parceiro_id = p.id AND a.versao = 1)
ON CONFLICT DO NOTHING;

-- =====================================================================
-- CONFERÊNCIA FINAL (o editor mostra só este resultado)
-- =====================================================================
WITH v AS MATERIALIZED (SELECT count(*) AS n, bool_or(vigente) AS tem_vigente FROM public.parceiro_contratos_versoes),
     f AS MATERIALIZED (SELECT count(*) AS n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
                        WHERE ns.nspname = 'public' AND p.proname IN ('parceiro_aceitar_contrato','parceiro_contrato_situacao',
                              'parceiro_meu_portal_com_contrato','superadmin_parceiro_contrato_publicar')),
     a AS MATERIALIZED (SELECT count(*) AS aceites,
                               (SELECT count(*) FROM public.parceiros p WHERE (public.parceiro_contrato_situacao(p.id)->>'pendente')::boolean) AS pendentes
                        FROM public.parceiro_contratos_aceites)
SELECT CASE WHEN v.n >= 1 AND v.tem_vigente AND f.n = 4 THEN 'OK — Contrato de Parceria aplicado' ELSE 'ATENÇÃO — confira as colunas ao lado' END AS resultado,
       v.n AS versoes, v.tem_vigente, f.n || '/4' AS funcoes, a.aceites, a.pendentes AS parceiros_com_aceite_pendente, NULL::text AS erro_tecnico
FROM v, f, a;
