# MarketYE — entrega da fundação (MVP conexão/lead)

Módulo que substitui a antiga "Rede de Parceiros" (`/marketplace`) pelo
**MarketYE**, o marketplace de serviços do YourEyes, seguindo o Documento de
Requisitos v2.0 (11/09/2026). Esta página resume o que entrou, o que ficou de
fora de propósito e como conferir no ambiente de teste.

## O que entrou

**Nomenclatura (0.5).** Botão do cabeçalho, menu, busca global, perfis de
acesso e painel de QA passam a dizer **MarketYE**. "Parceiros" fica só para o
Programa de Parceiros (canal de vendas).

**Banco (migrations 20260911220000 / 221000 / 222000 / 224000 / 230000 / 20260912002000 / 030000 / 040000; script de entrega
`docs/script_marketye_fundacao.sql`).**

| Requisito | Como ficou |
|---|---|
| Especialista global, sem tenant (RN-001/002) | `marketplace_profissionais` continua a tabela; `tenant_id` vira só "empresa de origem do cadastro". Novo cadastro nasce `pendente`. |
| Escrita sensível só por função (RN-021 / CA-013) | Guardas por trigger: status, selo, reputação, documento e consentimento não mudam por UPDATE direto; anúncio só publica por `marketye_anuncio_publicar`. |
| Contato mascarado (RN-020) | Leitura direta de e-mail/telefone/CPF pelo papel `authenticated` retirada; mensagens do lead mascaram telefone/e-mail/link até a empresa liberar; contato sai por `marketye_lead_contato`. |
| Leads (RF-012) | `marketplace_leads` + `marketplace_lead_mensagens`; funções abrir/mensagem/liberar/status; recusar não pesa (RN-030). |
| Avaliação verificada e bidirecional (RN-004/022) | `marketye_avaliar('lead' ou 'contratacao', ...)` só com lead ganho ou contratação concluída, dentro da janela; 1 por lado; direito de resposta; limite por par (anti-gaming). |
| Reputação em dois eixos (RN-005) | `marketplace_reputacao`: saúde recente (90 d) + nível (novo → bronze → prata → ouro → top) com requisitos simultâneos, aviso e amortecedor antes do ajuste (RN-009/010/029). |
| Relevância personalizada (RF-008) | `marketye_buscar(jsonb)`: fit por obrigação legal × reputação × saúde × proximidade × exploração (boost de novato) × preço × destaque, com pesos em `marketplace_config`; piso de nota rebaixa e o destaque não passa por cima (RN-006/007). |
| Busca nunca vazia (RN-023) | Relaxamento progressivo (raio → cidade → modalidade → UF → nota) e categorias adjacentes; busca rala vira demanda latente. |
| Vagas de demanda (6.3 / RN-034) | `marketye_vagas_demanda()` só devolve células com ≥ 5 empresas distintas. |
| Parametrização versionada (RN-016) | `marketplace_config` (pesos, piso, níveis, proteção ao novato, célula mínima, mascaramento, janela de avaliação, versões dos termos, localização, destaque). |
| LGPD do não-usuário (RN-018/019) | `marketplace_consentimentos` por versão; exportação e exclusão (anonimiza e retém transações). |
| Devido processo (RN-032/033) | `marketplace_contestacoes`: canal único; só superadmin decide, com trilha; relatório de transparência. |
| Trilha de autonomia (RN-031) | `marketplace_autonomia_eventos` por trigger em preço/política/horário. |
| Léxico (RN-028) | Ocorrência, reflexo na visibilidade, ajuste de nível. Auditado pela rotina MKY-007. |
| Taxonomia (7.1) | Categorias com slug, árvore, aliases, obrigação legal, exige registro, jurisdição. 20 subcategorias do beachhead SST/RH. |
| Áreas abertas a todo tipo de prestador (decisão 11/09) | Raízes genéricas **Manutenção e instalações**, **Palestras e eventos**, **Consultoria e gestão**, **Saúde e bem-estar** e **Outros serviços**, com sinônimos para a busca em linguagem natural. Nas telas só aparecem as **áreas gerais** (as subáreas continuam no banco, para o encaixe com as obrigações legais e para a IA); a área é sugestão, nunca obrigação. |
| Busca não quebra ao relaxar filtros (regressão 12/09) | `marketye_buscar` falhava com "malformed array literal" ao anotar a etapa relaxada (lista || 'uf' lido pelo banco como duas listas); acontecia sempre que a empresa tinha estado cadastrado e a busca achava menos de 3 anúncios. Corrigido com `array_append` (migration 20260912002000); caso MKY-015 força as cinco etapas. |
| Portal abre depois do cadastro mínimo (regressão 11/09) | `marketye_meu_portal` quebrava quando o cadastro não tinha especialidades (nulo medido como lista) e a tela ficava no círculo de carregamento. Função corrigida (migration 230000), tela com "Tentar de novo" e caso MKY-014 cobrindo. |
| Localização (0.3) | `pais`/`moeda`/`jurisdicao` em especialista, anúncio, categorias e config. Nada de Brasil fixado em código; i18n ainda não. |

**Telas.**

- `/marketplace` — vitrine MarketYE (busca em linguagem natural com IA, filtros, ordenação por relevância, cards com selo "dados verificados", nível, saúde recente, Patrocinado rotulado, busca vazia com Avise-me); Minhas conversas (chat com mascaramento, liberar contato, serviço combinado, avaliar, Analisar com IA, Criar ação no Plano de Ação, arquivar proposta no módulo Documentos); Serviços contratados e Pacotes (legado). O superadmin vê a vitrine como uma empresa cliente; nada de administração aqui.
- **Super Admin → Produtos → MarketYE** (`/admin/marketye`; o endereço antigo `/admin?aba=marketye` redireciona para cá) — administração da casa: **Aprovar cadastros**, **Denúncias**, **Pedidos de revisão**, **Destaques**, **Ajustes** (a antiga "Parâmetros": controles deslizantes com nome em linguagem comum e botão *Sugerir com IA*, que devolve os pesos a partir de um objetivo escrito em uma frase) e **Oferta e procura** (a antiga "Liquidez").
- `/marketye` — página pública de captação com "vagas de demanda" anonimizadas.
- `/marketye/cadastro` — cadastro sem acesso ao sistema (Edge Function `marketye-cadastro`) ou com conta existente (papéis sobrepostos com o Programa de Parceiros). Formulário curto e sem jargão: nome, CPF/CNPJ, **"O que você faz para empresas?"** em texto livre (vira a apresentação), área opcional, registro profissional opcional em texto livre, cidade, telefone, como atende, e-mail e senha.
- `/marketye/entrar` e `/marketye/portal` — portal restrito do especialista. Abre na aba **Meu caminho**: seis passos em sequência (conte o que faz → aprovação dos dados → cadastre o primeiro serviço → publique → responda às empresas → combine, faça o serviço e avalie), cada um com o botão que leva à ação e marcado como feito conforme avança. Demais abas: Meus serviços (anúncio montado pela IA a partir de uma frase, com "Mais opções" escondendo o resto), Conversas (resposta escrita com a IA), Minha reputação, Meu perfil (apresentação escrita com a IA), Cupons e Minha conta (termos, pedir revisão de uma decisão, baixar/apagar dados).
- `EncontrarEspecialistaLink` — componente para alertas: leva à vitrine já filtrada pela obrigação (`/marketplace?obrigacao=NR-1&origem=...`).

**Linguagem.** Nenhuma tela do módulo usa termo técnico (lead, moderação,
parâmetros, contestação, liquidez, sanção, pipeline): virou "conversa",
"aprovar cadastros", "ajustes", "pedido de revisão", "oferta e procura",
"ocorrência". A IA (`ai-marketye`) atende qualquer serviço prestado a empresas,
não só SST/RH.

**Mobiliário do ambiente de teste.** O "Especialista Staging (QA)" (2 anúncios
publicados) é semeado ou reparado a cada corrida da esteira pela função
`marketye_semear_ilha_teste()` (migrations 20260912000100 e 20260912001000), chamada
pelo passo que semeia a conta-robô (esse passo só roda com o segredo
`QA_E2E_TOKEN` configurado no repositório; sem ele, a esteira pula a semeadura e a
guarda de cobertura). A função escolhe o primeiro CPF fictício livre da faixa da casa
e informa o resultado. Para ver o diagnóstico no SQL Editor do projeto de teste:
`SELECT public.marketye_semear_ilha_teste();`. A vitrine passou a mostrar o erro
da busca ("Não conseguimos buscar agora" + Tentar de novo) em vez de "sem
resultados". A migration 20260911223000 (semente silenciosa) fica como estava.

**Pacote de QA (12/09).** `docs/QA_MARKETYE.md` traz a auditoria do requisito,
a análise de risco, os defeitos encontrados, a matriz CA × caso e a recomendação
go/no-go do agente de QA. Os casos MKY-030 a MKY-161 (13 famílias) estão na
Documentação de Testes (migration 20260912020000; script
`docs/script_marketye_qa_documentacao.sql`) e ganham rotinas e testes de tela nas
ondas seguintes — até lá o motor mostra "não implementado", nunca "passou".

**Segurança (12/09, rotinas MKY-110..116).** A família de segurança ganhou rotina (migration
20260912030000) e, na primeira execução, achou e corrigiu: D-05 (funções executáveis por
visitante), D-15 (aviso de nível legível por qualquer usuário), D-16 (visitante com SELECT
em avaliações) e **D-17: 13 políticas (5 no Storage) liam `user_id` do especialista, coluna
fechada desde a fundação, e quebravam qualquer leitura direta de anúncios/pacotes/contratações
e o upload de foto/documento do especialista com "permission denied"**. Reescritas com
`marketye_meu_id()`.

**Motor (banco) — rotinas para os casos documentados (12/09, migration 20260912040000).**
Os 58 casos `api` restantes que o motor consegue executar (famílias cadastro, moderação,
anúncio, busca, conversa, avaliação/reputação, LGPD, ajustes e integrações) ganharam rotina
`qa_caso_mky_*`; com as 22 anteriores, o módulo tem **80 rotinas** registradas em
`qa_implementacoes`. Elas rodam em **Super Admin → QA e Testes → Executar testes → Motor
(banco)**, módulo MarketYE, em cerca de 3 segundos. As rotinas são honestas: onde o produto
contraria o caso documentado elas **falham** e o texto começa com "ACHADO". Na primeira execução
foram 64 passou / **16 falhou** / 0 erro; os 16 casos que falham têm a disposição registrada na
Documentação de Testes (`bug_confirmado` ou `aguardando_construcao`, com o motivo), e a
conferência do script de entrega só reprova falha inesperada (caso ainda `em_triagem`). O mais
grave dos achados: **D-18 — qualquer especialista logado consegue liberar o contato e mudar o
status de uma conversa de que não faz parte** (`marketye_lead_liberar_contato` e
`marketye_lead_status` não recusam papel nulo). Lista completa e severidades em
`docs/QA_MARKETYE.md`, seção 8 (D-06, D-11 e D-18 a D-31). Nada do produto foi alterado nesta
entrega: só rotinas de teste, registro, ajustes de texto de caso e disposições. O script de
entrega `docs/script_marketye_fundacao.sql` passou a ser autossuficiente: além das rotinas, incorpora
o conteúdo de `script_marketye_anexos_fotos.sql` e `script_marketye_qa_documentacao.sql` (todos
idempotentes), e a conferência final roda as 80 rotinas — só reprova erro de rotina ou falha em caso
ainda `em_triagem`; os achados conhecidos saem na coluna `achados_conhecidos`.

**QA.** Casos MKY-001 a MKY-015, MKY-031 a MKY-124 (api, 80 com rotina) e MKY-110 a MKY-116 e MKY-020 a MKY-022 (e2e,
`cypress/e2e/marketye.cy.ts`); módulo `rede-parceiros` renomeado para MarketYE
na Documentação de testes. Casos PARC-001/002/004/024 atualizados.

## Correções de 12/09/2026 (achadas no ambiente de teste)

| Sintoma | Causa | Correção |
|---|---|---|
| Cadastro de especialista pelo formulário da vitrine dava erro, mas o cadastro aparecia depois; os anexos não ficavam gravados | O perfil era criado pela função do sistema e, em seguida, o envio dos documentos era recusado pelo Storage: a política do bucket `marketplace-docs` exige que a primeira pasta do caminho seja o **id do especialista**, e a tela mandava o id do usuário. O registro na tabela também não conferia erro. | Caminho corrigido (`<especialista>/<categoria>/<arquivo>`, em `src/lib/marketyeAnexos.ts`), erro de registro tratado, e a segunda tentativa **reaproveita o cadastro** que já existia (envia só os anexos, sem duplicar). `arquivo_url` passa a guardar o caminho no bucket. |
| Documentos não abriam na aprovação de cadastros | O bucket é privado e a URL "pública" guardada não abre; o superadmin também não tinha política de leitura | Painel de moderação abre cada documento por **link assinado** (2 min); migration `20260912013000` (script `docs/script_marketye_anexos_fotos.sql`) dá leitura ao superadmin e cria o bucket público `marketplace-fotos` para a foto de perfil. A mesma migration **retira** a leitura que qualquer admin de empresa cliente tinha sobre os documentos pessoais de todos os especialistas. |
| Mensagem enviada pela empresa não aparecia na tela do prestador | A lista de conversas do portal (e a da empresa) só era consultada uma vez e não recarregava ao voltar à aba | Listas reconsultadas a cada 30 s e ao voltar à aba; botão **Atualizar** na aba Conversas do portal. |
| "OPENAI_API_KEY não configurada" ao montar o anúncio com IA | Segredo de projeto não copiado para o projeto de teste (ver `docs/AMBIENTES.md`, "Recadastrar os secrets") | A função responde com mensagem em linguagem clara (e código 503) dizendo o que falta e que dá para preencher à mão. O segredo precisa ser cadastrado em *Project Settings → Edge Functions → Secrets* do projeto de teste. |
| Botão MarketYE do cabeçalho pouco visível | — | Botão na cor laranja da paleta (`--brand-orange`). |

## O que NÃO entrou (de propósito)

- **Pagamento intra-plataforma, split, escrow, take rate, NF da taxa** —
  GATE jurídico pré-build (seção 14). Nenhuma linha de código.
- **Cobrança do destaque pago** — só o registro do período e o reflexo no
  ranking; o dinheiro fica para a onda com meio de pagamento.
- **Verificação por OCR / antecedentes** — a moderação continua humana com
  os documentos enviados.
- **Notificações por e-mail/WhatsApp de lead** — o portal mostra "aguardando
  sua resposta"; disparo automático é onda seguinte.
- **i18n / moeda estrangeira ativa** — só o modelo de dados está preparado.
- **Redação final dos instrumentos (3.4)** e **prazos de retenção** —
  exigem advogado; as versões vigentes são placeholders (`2026-09-v1`).

## Como conferir no ambiente de teste

1. Site de teste: https://ustudy123.github.io/youreyesnovo/teste/
2. Logado como empresa: botão **MarketYE** no cabeçalho → vitrine; filtre
   "Segurança do Trabalho" (aparece "Especialista Staging (QA)"); busque
   "xyz" (aviso de oferta insuficiente + Avise-me); abra uma conversa.
3. Sem login: `/marketye` (página pública) → "Quero me cadastrar".
4. Superadmin: botão **Super Admin** → aba **MarketYE** → Aprovar cadastros,
   Pedidos de revisão, Ajustes (mova um controle e salve; clique em *Sugerir
   com IA* com um objetivo como "quero dar mais chance a quem está
   começando") e Oferta e procura.
5. Como especialista (`/marketye/entrar` com a conta do Especialista Staging):
   aba **Meu caminho** — siga os seis passos; em Meus serviços, escreva uma
   frase e clique em *Montar anúncio*.
6. Superadmin: **QA e Testes → Executar testes → Motor (banco)** → escolha o módulo
   **MarketYE** e clique em Executar. Esperado: 64 passou, 16 falhou (cada "falhou" abre com o
   texto "ACHADO: ..." e o caso correspondente mostra a disposição na Documentação de Testes),
   0 erro, 45 não implementados (casos de tela, IA e aguardando construção).
7. SQL Editor do projeto de TESTE: `SELECT * FROM public.qa_rodar_bateria('manual','rede-parceiros');`
   e depois `SELECT codigo, situacao, left(obtido, 200) FROM public.qa_resultados WHERE execucao_id = '<id devolvido>' ORDER BY codigo;`
   (ou a conferência final do `docs/script_marketye_fundacao.sql`, que roda as 80 rotinas e
   mostra `qa_mky`, `achados_conhecidos` e `falhas_inesperadas`).

A produção segue intacta: nada aqui toca o projeto de produção.
