# 📘 YourEyes — Manual Completo do Sistema
## Plataforma de Governança do Trabalho Humano com Inteligência Artificial

---

## 🏛️ VISÃO GERAL

O **YourEyes** é uma plataforma SaaS de **Governança do Trabalho Humano** que unifica, em um só ambiente, a gestão de pessoas, segurança e saúde do trabalho (SST), ergonomia, compliance, cultura organizacional e desenvolvimento humano — tudo potencializado por **Inteligência Artificial**.

A plataforma opera sob o princípio: **"Ação é evidência, e evidência é proteção."** Cada diagnóstico, indicador ou risco identificado resulta em uma ação estruturada, rastreável e auditável.

### Arquitetura de 4 Pilares Estratégicos

| Pilar | Descrição |
|-------|-----------|
| 🏗️ **Organização do Trabalho** | Estruturação de cargos, funções, atividades, competências e procedimentos |
| ⚙️ **Condições de Execução** | EPIs, ergonomia, SST, conformidade regulatória e ambiente de trabalho |
| 💚 **Experiência Humana** | Bem-estar, humor, cultura, celebrações, ouvidoria e feedback |
| 📊 **Governança e Impacto** | Plano de Ação, auditorias, indicadores, compliance e rastreabilidade |

---

## 🔐 ACESSO E AUTENTICAÇÃO

### Login e Registro
- Acesso via **e-mail e senha** com recuperação de senha integrada
- **Multi-tenant**: cada organização possui seu espaço isolado
- **Controle de acesso por perfis** (RBAC): Proprietário, Admin, Gestor, Colaborador
- **Painel Super Admin** para administração geral da plataforma (rota `/admin`), com menu lateral agrupado por área: **Painel** (Visão geral, Situação das empresas), **Clientes** (Empresas, Usuários, Contratos e termos), **Comercial e marketing** (Leads CRM, Leads da landing, Preços e add-ons, Programa de Parceiros, Blog), **Produtos** (Psicossocial, MarketYE), **A YourEyes** (Dados da YourEyes) e **Qualidade e suporte** (QA e testes, Central de Controle de Clientes, Manual do sistema)

### Onboarding Guiado
Ao criar uma conta, o usuário é conduzido por um **fluxo de onboarding** que configura o tenant inicial: dados da empresa, estrutura organizacional e preferências do sistema.

---

## 🏢 MÓDULO: EMPRESA

**Rota:** `/empresa`

O módulo de Empresa centraliza toda a gestão de unidades organizacionais do tenant.

### Funcionalidades:
- **Cadastro condicional** por tipo de empregador:
  - **Pessoa Jurídica**: CNPJ com busca automática via API (preenchimento inteligente)
  - **Pessoa Física**: CPF obrigatório, campos CEI e CAEPF com máscaras específicas
- **Hierarquia fiscal em 4 níveis**:
  1. **Grupo Econômico** — controle de diferentes CNPJs sob mesma gestão
  2. **Matriz** — CNPJ raiz único
  3. **Filial** — compartilha CNPJ raiz com variação de sufixo
  4. **Estabelecimento / Obra** — locais físicos sem CNPJ próprio
- Filiais herdam automaticamente o Grupo Econômico da Matriz
- Criação de filiais inline (sem sair da tela)
- Filtros avançados por grupo, status (ativo/inativo)
- Exportação de dados para Excel
- Integração de obrigações ao **Plano de Ação Global**

### 🔄 Seletor Global de Empresa (Cabeçalho)
O ícone 🏢 no cabeçalho permite alternar entre empresas ou visualizar dados consolidados ("Todas as empresas"). Esta seleção filtra **todo o sistema** automaticamente, garantindo isolamento de dados por empresa.

**Travas de segurança:**
- Importação de planilhas é **bloqueada** quando "Todas as empresas" está selecionado
- Formulários de cadastro exibem um **banner visual** destacando a empresa de destino
- Campos de localidade são filtrados dinamicamente por empresa ativa

---

## 👥 MÓDULO: COLABORADORES

**Rota:** `/colaboradores`

Hub unificado para gestão do ciclo de vida completo do colaborador.

### Abas Principais:
1. **Ativos** — colaboradores em exercício
2. **Admissões** — processos de admissão em andamento
3. **Desligados** — histórico de desligamentos

### Funcionalidades:

#### Cadastro de Colaboradores
- Formulário completo com dados pessoais, profissionais e contratuais
- Campo **Estabelecimento / Obra** filtrado pela empresa ativa
- Campos de **Centro de Custo** e **Gestor Imediato**
- **Banner inteligente** alertando sobre a empresa selecionada
- Vinculação automática com `empresa_id` da empresa ativa

#### Importação em Massa via Planilha
- Upload de arquivos **.xlsx, .xls, .csv** (até 5MB)
- Mapeamento automático de colunas
- Pré-validação de dados antes da importação
- **Bloqueio automático** se nenhuma empresa estiver selecionada

#### Admissão Digital
- Workflow completo em etapas configuráveis
- Gestão de documentos obrigatórios com status individual
- Histórico de ações com trilha de auditoria
- **Exame Admissional**: clínica, médico, CRM, resultado e validade
- Dados bancários completos (banco, agência, conta, PIX)

#### Desligamento (Compliance CLT)
- Cálculo automático de aviso prévio conforme **Lei 12.506/2011**
  - 30 dias base + 3 dias por ano trabalhado (máximo 90 dias)
- Campo "aviso prévio cumprido" condicional (apenas quando tipo = Trabalhado)
- Upload obrigatório do **ASO Demissional**
- Arquivo automático no prontuário digital
- **Cancelamento automático** de ações culturais futuras

---

## 💰 MÓDULO: FINANCEIRO

**Rota:** `/financeiro` e `/financeiro/beneficios`

### Funcionalidades:
- **Dashboard financeiro** com visão consolidada
- Gestão de **Benefícios por tipo** (categorias, valores, regras)
- Atribuição de benefícios por colaborador com histórico
- Regras por cargo, unidade e vínculo
- Integração com módulo de férias para lançamentos automáticos
- Identificação de férias via tags nas observações

---

## 🏖️ MÓDULO: FÉRIAS

**Rota:** `/ferias`

Automatiza a conformidade CLT na gestão de férias.

### Funcionalidades:
- **Validação automática** de períodos aquisitivos e concessivos
- Regras de **fracionamento** conforme legislação
- **Monitoramento de vencimentos** (Art. 134 CLT):
  - Alertas visuais de 90, 60 e 30 dias
  - Cálculo de risco trabalhista (Art. 137 CLT)
- Fluxo de gestão sequencial:
  1. ✅ **Aprovação** (com alerta de sobreposição de setor)
  2. 📄 **Geração de Aviso e Recibo** (PDF)
  3. 💳 **Registro Financeiro** (vencimento 2 dias úteis antes do início)
  4. ✍️ **Link de Assinatura Digital** (pad de assinatura no frontend)
- **🤖 INR™ (Indicador de Necessidade de Recuperação)**:
  - IA sugere férias preventivas baseadas em humor, burnout e sobrecarga de tarefas
- Automação cultural: mensagens pré-férias e check-ins no retorno
- Rota pública para assinatura: `/ferias-assinatura/:token`

---

## 📋 MÓDULO: AVALIAÇÕES DE DESEMPENHO

**Rota:** `/avaliacoes`

### Estrutura em 4 Blocos:
1. **Entrega e Qualidade** (Performance)
2. **Competências** (Função e Comportamento)
3. **Evolução e Aprendizado** (Desenvolvimento)
4. **Contexto de Trabalho** (Ergonomia e Risco Humano)

### Funcionalidades:
- Ciclos configuráveis: **90°, 180° ou 360°**
- Templates customizáveis com escalas e categorias
- Pesos ajustáveis por dimensão
- **Justificativa obrigatória** para notas extremas
- Matriz **9-Box** (Desempenho × Potencial)
- Feedbacks estruturados por critério

### 🤖 Inteligência Artificial:
- **Assistente IA gera rascunhos** automáticos de avaliação
- Integra evidências do período: metas, feedbacks, ocorrências, treinamentos
- Radar de risco humano integrado

---

## 🩺 MÓDULO: ATESTADOS E SAÚDE OCUPACIONAL

**Rota:** `/atestados`

### Funcionalidades:
- Cadastro detalhado de atestados (assistenciais e ocupacionais)
- Tipos: Admissional, Periódico, Retorno, Mudança de Função, Demissional
- Registro de CID com autorização explícita
- Classificação por **Grupo Clínico**
- Nexo com trabalho (Nexo Ocupacional)
- Upload de documentos digitalizados
- Restrições e observações ocupacionais

### 🤖 Inteligência Artificial:
- **Extração automática de dados via GPT-4o**
- Upload de foto/scan do atestado → campos preenchidos automaticamente
- Reconhece: nome, CRM, CID, datas, dias de afastamento

### Afastamentos
- Gestão completa do ciclo de afastamento
- Alertas automáticos de 15 e 30 dias
- Vinculação com benefícios INSS (espécies B91, B31, etc.)
- Estabilidade provisória com data de fim calculada
- ASO de retorno pendente

### Alertas de Saúde
- Sistema de alertas automáticos por colaborador
- Priorização e resolução rastreável

---

## 🔒 MÓDULO: COMPLIANCE SST

**Rota:** `/compliance-sst`

### 🤖 Inteligência Artificial (GPT-4o):
- **Auditor IA** que analisa a coerência normativa entre:
  - **PGR** (Programa de Gerenciamento de Riscos)
  - **PCMSO** (Programa de Controle Médico)
  - **LTCAT** (Laudo Técnico de Condições Ambientais)
- Identificação de riscos, omissões e **passivos jurídicos**
- Critérios técnicos: **LINACH, Tema 555 do STF**
- Monitoramento de eventos **eSocial** (S-2210, S-2220, S-2240)
- Integração de diagnósticos ao **Plano de Ação Global**
- Proteção jurídica sem substituir o mérito profissional

---

## 🦺 MÓDULO: EPIs — EQUIPAMENTOS DE PROTEÇÃO INDIVIDUAL

**Rota:** `/epis`

### Catálogo Inteligente:
- Estrutura hierárquica: **Categorias → Tipos → Itens**
- Campo de nome do EPI em texto aberto
- Grid para visualização e edição de categorias

### Controle de Estoque:
- Saldo particionado por **empresa** e **local** (Estabelecimento/Obra → Almoxarifado)
- Movimentações rastreáveis:
  - **Entradas**: manual ou via importação de NF XML
  - **Saídas**: venda, descarte, perda, dano, vencimento
  - **Transferências internas** com lógica dual (decrementa origem / incrementa destino)
- Alertas para itens abaixo do nível mínimo
- Dashboard de distribuição em tempo real

### Entregas e Devoluções:
- **Fluxo de entrega em 4 etapas**:
  1. Seleção do EPI
  2. Prova de vida (foto)
  3. Assinatura digital
  4. Geração de recibo PDF (arquivado automaticamente no prontuário)
- Devoluções com encaminhamento para manutenção ou descarte

### Conformidade:
- **Matriz de Proteção**: EPIs obrigatórios por função e Condições Especiais
- Monitoramento de validade do **Certificado de Aprovação (CA)**: alertas 30/90 dias
- **Ciclo de Vida Inteligente**: sugestão de substituição baseada em vida útil estimada

### 🤖 Inteligência Artificial:
- **Importação de NF XML** com IA (`ai-nf-match`): vínculo automático com catálogo
- **Auditoria Inteligente** (GPT-4o):
  - Auditoria automatizada de entregas e estoque
  - Identificação de riscos de conformidade (NR-6/NR-9)
  - Relatórios PDF com cabeçalho corporativo
  - **Sugestão de ações corretivas 5W2H** em lote no Plano de Ação

### RBAC específico:
Hierarquia de acesso: Usuário → Gestor → Admin → Proprietário

---

## 🧠 MÓDULO: ERGONOMIA INTELIGENTE

**Rota:** `/ergonomia`

### Funcionalidades:
- **AEP (Análise Ergonômica Preliminar)** assistida por IA
- Conformidade **NR-17** automatizada
- Monitoramento psicossocial integrado

### 🤖 Inteligência Artificial:
- **Análise de vídeo**: extração estratégica de quadros para avaliação ergonômica
- **Radares Preditivos**:
  - **Burnout** — risco de esgotamento
  - **Boreout** — risco de tédio/subaproveitamento
  - **IRP-S** — Indicador de Risco Psicossocial
- Recomendações geradas pela IA são convertidas em **ações 5W2H** no Plano de Ação
- Preenchimento automático de justificativas técnicas (riscos físicos e cognitivos)
- Criação de ações preventivas a partir de fatores qualitativos (humor, ritmo, carga mental)

---

## 📊 MÓDULO: QUESTIONÁRIO PSICOSSOCIAL

**Rota:** `/questionario/:token` (pública)

### Funcionalidades:
- Escala de 0 a 4
- **Modelo híbrido**: anônimo por padrão, identificação voluntária
- Temas das perguntas **ocultos** para respondentes (evita viés)
- Ciclos regulares: mensal, trimestral, semestral, anual
- **Reaplicações extraordinárias** por gatilho:
  - Acidente, denúncia, reestruturação, conflito, sugestão de IA, solicitação do colaborador

### Indicadores Automáticos:
| Indicador | Descrição |
|-----------|-----------|
| **IRP-S** | Índice de Risco Psicossocial |
| **IBO-S** | Índice de Burnout |
| **IBD-S** | Índice de Boreout |
| **IREC-S** | Índice de Reconhecimento |
| **ICOP-S** | Índice de Cooperação |
| **INOT-S** | Índice de Notificação |

- **Imutabilidade e comparabilidade** histórica garantidas

---

## 📝 MÓDULO: FEEDBACK E OCORRÊNCIAS

**Rota:** `/feedback-ocorrencias`

### Feedbacks Estruturados:
- Categorização por tipo: **Positivo, Neutro, Negativo**
- Foco: **Reconhecimento, Alinhamento, Desenvolvimento**

### 🤖 Inteligência Artificial (GPT-4o-mini):
- **Transforma notas brutas em redações profissionais**
- Sugestões de tom e estrutura

### Ocorrências Disciplinares:
- Emissão de **advertências formais**
- **Links externos seguros** para formalização sem login
- Upload de documentos assinados por partes interessadas
- Trilha de auditoria completa

---

## 📚 MÓDULO: APRENDIZADO E PAPÉIS

**Rota:** `/aprendizado-papeis`

### Funcionalidades:
- **Gestão de Atividades** por função
- **Matriz de Responsabilidade** por atividade (ferramentas, interfaces, consequências de erro)
- **Mapeamento de Competências**: Técnicas, Comportamentais, Cognitivas
- **Vinculação de EPIs** a funções
- Dashboards de complexidade e lacunas
- Abas organizadas: Atividades, Competências, EPIs & Treinamento

### 🤖 Inteligência Artificial:
- **Importação via áudio** (`ai-audio-atividades`): fale sobre as atividades da função e a IA estrutura automaticamente
- Transcrição via **Whisper (OpenAI)**
- **POP Inteligente** (`ai-pop-generator`):
  - Geração automática de Procedimentos Operacionais Padrão
  - Herda dados da matriz de responsabilidade
  - Status: Rascunho → Em revisão → Publicado → Desatualizado
  - Versionamento via snapshots
  - Editor híbrido com botões IA: Detalhar, Simplificar, Pontos de Atenção, Checklist
  - **Visual Diff** para comparação de versões
  - Exportação PDF
  - Marcação automática como "Desatualizado" se a atividade mudar
- **Geração de Manuais Profissionais** (`ai-manual-funcao`):
  - Documento HTML/PDF consolidando: POPs, trilhas, responsabilidades, EPIs, competências
  - Manual individual por função ou **Manual Global** de todas as funções

---

## 🎓 MÓDULO: TRILHAS DE APRENDIZAGEM

**Rota:** `/trilhas`

### Funcionalidades:
- **11 tipos de conteúdo** suportados
- **Gamificação**: medalhas e ranking
- Trilhas personalizadas por função/cargo
- **Acesso para terceiros** via links públicos (NRs e integração)
- Rota pública: `/trilha-terceiro/:token`
- Cancelamento automático de tarefas pendentes em desligamentos
- Reavaliação de conteúdos em mudanças de cargo
- Botão "Nova Trilha" disponível globalmente no cabeçalho

---

## 🎯 MÓDULO: PDI — PLANO DE DESENVOLVIMENTO INDIVIDUAL

**Rota:** `/pdi`

### Funcionalidades:
- Metas **SMART** com acompanhamento
- **Vínculo bidirecional** com o Plano de Ação Global
- Progresso e status dinâmicos

### 🤖 Inteligência Artificial:
- **Geração de metas SMART** via IA (`ai-pdi-smart`)
- **Geração de documento profissional** (`ai-pdi-documento`) em HTML/PDF
- Arquivo automático no prontuário do colaborador
- **Formalização via WhatsApp**: link de assinatura → Edge Function injeta selo de auditoria (timestamp + assinatura) → arquivo renomeado como "(Assinado)"
- Rota pública: `/pdi-assinatura/:token`

---

## 📋 MÓDULO: PLANO DE AÇÃO GLOBAL

**Rota:** `/plano-acao`

O coração da governança. **Tudo no sistema converge para cá.**

### Funcionalidades:
- Metodologia **5W2H** (O quê, Por quê, Onde, Quando, Quem, Como, Quanto)
- **Matriz GUT** para priorização (Gravidade × Urgência × Tendência)
- Subtarefas com progresso incremental
- Conclusão direta (100%) mesmo sem subtarefas
- **Rastreabilidade de origem** com badges/emojis (AEP, Auditoria EPI, Oceano Azul, etc.)
- Filtros por período e busca por responsável
- Cards de estatísticas clicáveis (filtram por status)
- Aba de **ações críticas** (itens atrasados)
- Detalhe individual por ação: `/plano-acao/:id`

### 🤖 Inteligência Artificial (`ai-plano-acao`):
- **Assistente IA** para geração e refinamento de ações
- Sugestões contextuais com base no diagnóstico de origem

### Políticas de Acesso:
- Todos os perfis (incluindo Colaborador) podem criar seus próprios planos
- Permite autogestão e integração com PDI

---

## 🏛️ MÓDULO: ESTRATÉGIA E GOVERNANÇA

**Rota:** `/estrategia`

### Cultura Organizacional:
- Definição de **Missão, Visão, Valores, Princípios e Comportamentos**

### 🤖 Inteligência Artificial:
- **Assistente IA** (`ai-cultura-sugestao`): sugestões coerentes e profissionais
- **Manual de Cultura** (`ai-cultura-manual`): documento HTML/PDF com layout premium, CSS inline, pronto para impressão

### Análise SWOT:
- Forças, Fraquezas, Oportunidades, Ameaças
- Integração com Oceano Azul

### Matriz Oceano Azul:
- Estratégias de inovação: **Eliminar, Reduzir, Elevar, Criar**

### 🤖 Inteligência Artificial (`ai-oceano-azul` — GPT-4o):
- Integra diagnósticos SWOT em estratégias de inovação
- **Criação em lote de ações 5W2H** no Plano de Ação Global
- Sugestões contextuais com prioridades GUT automáticas

### Organograma Visual:
- Gestão interativa da hierarquia funcional

---

## 🎉 MÓDULO: CULTURA E CELEBRAÇÕES

**Rota:** `/cultura-celebracoes`

### Funcionalidades:
- Mapeamento automático do **Dia da Profissão** para +40 funções
- Coleta de preferências de reconhecimento no onboarding
- **Gatilhos automáticos** de banco de dados:
  - Cancelamento de ações culturais em desligamento
  - Reavaliação em mudança de cargo
- Felicitações automáticas (aniversários, tempo de casa)

### 🤖 Inteligência Artificial (`ai-felicitacao`):
- Geração de mensagens personalizadas para celebrações

---

## 💚 MÓDULO: BEM-ESTAR (GESTÃO DA FELICIDADE)

**Rota:** `/felicidade`

**Filosofia**: "Espelho guiado" — espaço de autopercepção segura, **nunca para punição ou cobrança**.

### 7 Eixos:
1. 🪞 **Autoconhecimento** — histórico de humor dos últimos 14 dias
2. 🧭 **Sentido & Propósito** — conexão da função com objetivos da empresa
3. 🤝 **Relações** — qualidade das interações
4. 🔑 **Autonomia** — liberdade de atuação
5. ⭐ **Autorrealização** — crescimento pessoal
6. 🧘 **Atenção Plena** — mindfulness no trabalho
7. 🙏 **Gratidão** — registro de agradecimentos

### Privacidade Absoluta:
- Gestores veem apenas **tendências agregadas** e alertas por eixo
- **Nenhuma identificação individual** é exposta
- Régua de 1 a 5 alimenta o **radar visual** de bem-estar

### Humor Diário:
- **Popup obrigatório** ao acessar o sistema (se não registrou hoje)
- Registro rápido do estado emocional
- Histórico para autoconhecimento

---

## 📢 MÓDULO: OUVIDORIA

**Rota:** `/ouvidoria`

### Funcionalidades:
- Submissões **anônimas ou identificadas**
- Tipos: **Denúncia, Elogio, Sugestão, Reclamação**
- Suporte a múltiplos anexos (10MB cada)
- Fluxo de resposta direta
- Roteamento configurável por departamento

### 🤖 Inteligência Artificial:
- **Análise de sentimento** (`ai-ouvidoria` — GPT-4o): positivo, neutro, negativo, urgente
- Classificação automática e subcategorias
- Priorização inteligente
- Identificação de riscos
- **Sugestão de planos de ação 5W2H** (`ai-ouvidoria-acoes`) baseados nas manifestações

### Segurança:
- RLS garante que identidades anônimas permaneçam protegidas
- Rastreabilidade total das ações corretivas

---

## 🏗️ MÓDULO: TERCEIROS

**Rota:** `/terceiros`

### Estrutura em 3 Camadas:
1. **Empresa** (Terceiro)
2. **Trabalhadores** vinculados
3. **Documentos e Treinamentos**

### Status Operacional Dinâmico:
- **Liberado** ✅ | **Restrito** ⚠️ | **Bloqueado** 🚫
- Triggers automáticos que validam expiração de:
  - ASO, PGR, PCMSO
  - Certificados de treinamento (NR-10, NR-35, etc.)

### Painel de Vencimentos:
- Visão centralizada de documentos vencendo em 60/30 dias
- Log de auditoria para versionamento de arquivos

### Permissão de Trabalho (PT) Digital:
- Validação automática da conformidade dos trabalhadores antes da liberação

---

## 🚨 MÓDULO: INCIDENTES E ACIDENTES

**Rota:** `/incidentes-acidentes`

- Registro e acompanhamento de incidentes e acidentes de trabalho
- Integração com módulos de SST e Plano de Ação

---

## 📁 MÓDULO: GESTÃO DOCUMENTAL

**Rota:** `/documentos`

### Duas Estruturas:
1. **Prontuários (Colaboradores)**:
   - Hierarquia: Empresa → Estabelecimento/Obra → Colaborador → Ano
2. **Processos**:
   - Hierarquia: Documentos de Processos → [Função]
   - Armazena POPs gerados pelo módulo Aprendizado

### Funcionalidades:
- Sincronização automática de pastas
- Metadados vinculados (pop_id, colaborador_id)
- Índices únicos para evitar duplicidade

---

## 🧾 MÓDULO: HUB CONTÁBIL INTELIGENTE

**Rota:** `/hub-contabil`

### Abas Estratégicas:
1. 📊 **Dashboard** — visão geral
2. 📅 **Competências** — abertura mensal automatizada (pg_cron)
3. 📄 **Documentos** — envio e controle
4. 📋 **Guias** — impostos e obrigações
5. 🔍 **Conferência Cruzada** — validação automática de valores (guias × folha)
6. 📜 **Certidões/CNDs** — monitoramento de validade
7. 📚 **Histórico** — trilha de auditoria
8. 📆 **Calendário** — prazos recorrentes de impostos

### Funcionalidades:
- **Roteamento inteligente** de documentos:
  - Holerites → Dossiê do Colaborador
  - GRRF → Rescisão Específica
  - Recibos de Férias → Período Aquisitivo
- Integração automática com eventos operacionais (admissões, férias, rescisões)
- **Checklist que bloqueia envio** ao contador se houver pendências
- Monitoramento automático de validade de CNDs

---

## 🌐 MÓDULO: REDE DE PARCEIROS (MARKETPLACE)

**Rota:** `/marketplace`

### Cadastro de Profissionais:
- Documentos obrigatórios: RG, CPF/CNPJ, Registro no Conselho, Diplomas
- Selfie de verificação + foto de perfil
- **Atestado de Capacidade Técnica** (opcional, mas prioriza no ranking)

### Governança:
- **Bloqueio automático** de profissionais com registros vencidos
- **Auditoria** que impede oferta de serviços fora do escopo legal do conselho

---

## ⏰ MÓDULO: PONTO

**Rota:** `/ponto`

- Gestão de registros de ponto
- Filtrado por empresa ativa

---

## 📰 MÓDULO: FEED

**Rota:** `/feed`

- Feed de comunicação interna

---

## ⚙️ CONFIGURAÇÕES

**Rota:** `/configuracoes`

- Configurações do sistema e preferências do tenant

---

## 💬 ASSISTENTE VIRTUAL SST (Chat IA)

Widget flutuante disponível em todas as telas.

### 🤖 Inteligência Artificial (GPT-4o):
- Especialista em **segurança do trabalho, ergonomia e saúde ocupacional**
- Conhecimento sobre todas as NRs, AET/AEP, EPIs, PCMSO, PGR, LTCAT
- Respostas em português com citação de normas
- Streaming em tempo real
- Perguntas sugeridas para facilitar o uso
- Suporte a **Markdown** nas respostas

---

## 🤖 MAPA COMPLETO DE INTELIGÊNCIA ARTIFICIAL

O YourEyes utiliza a **API da OpenAI** com 26 Edge Functions de IA:

| Função | Modelo | Descrição |
|--------|--------|-----------|
| `ai-chat` | GPT-4o | Assistente virtual SST |
| `ai-sst-analise` | GPT-4o | Auditoria de compliance SST |
| `ai-audio-atividades` | Whisper + GPT-4o | Importação de atividades via áudio |
| `ai-ouvidoria` | GPT-4o | Análise de sentimento da ouvidoria |
| `ai-ouvidoria-acoes` | GPT-4o | Ações 5W2H para ouvidoria |
| `ai-oceano-azul` | GPT-4o | Estratégia Oceano Azul |
| `ai-feedback` | GPT-4o-mini | Redação profissional de feedbacks |
| `ai-plano-acao` | GPT-4o | Assistente do Plano de Ação |
| `ai-pdi-smart` | GPT-4o | Geração de metas SMART |
| `ai-pdi-documento` | GPT-4o | Documento PDF do PDI |
| `ai-pop-generator` | GPT-4o | POPs inteligentes |
| `ai-manual-funcao` | GPT-4o | Manuais profissionais de função |
| `ai-cultura-sugestao` | GPT-4o | Sugestões de cultura organizacional |
| `ai-cultura-manual` | GPT-4o | Manual de Cultura em PDF |
| `ai-epi-fiscal` | GPT-4o | Auditoria inteligente de EPIs |
| `ai-nf-match` | Edge Function | Vínculo de NF XML com catálogo |
| `ai-felicitacao` | GPT-4o-mini | Mensagens de celebração |
| `extract-atestado` | GPT-4o | Extração de dados de atestados |
| `analyze-ergonomia` | GPT-4o | Análise ergonômica via vídeo |

---

## 📐 CADASTROS BASE

### Departamentos (`/cadastros/departamentos`)
- Gestão de departamentos por tenant

### Cargos (`/cadastros/cargos`)
- Cadastro com nível (operacional, tático, estratégico)
- Vinculação a departamentos
- Exames obrigatórios e periodicidade
- Faixa salarial

### Filiais / Estabelecimentos (`/cadastros/filiais`)
- Gestão de locais físicos vinculados a empresas

---

## 🔒 SEGURANÇA E GOVERNANÇA

### Auditoria (Audit Logs)
- Registro automático de todas as ações do sistema
- Usuário, módulo, ação, target, metadados, IP e timestamp
- Rastreabilidade total

### Multi-Tenant
- Isolamento completo de dados por tenant
- RLS (Row Level Security) em todas as tabelas

### RBAC (Role-Based Access Control)
- Perfis: Proprietário, Admin, Gestor, Colaborador
- Permissões granulares por módulo

---

## 🏗️ ARQUITETURA TÉCNICA

| Componente | Tecnologia |
|------------|-----------|
| Frontend | React + TypeScript + Vite |
| Estilização | Tailwind CSS + shadcn/ui |
| Animações | Framer Motion |
| Ícones | Lucide React |
| Estado | React Query (TanStack) |
| Backend | Supabase (Auth, DB, Storage, Edge Functions) |
| IA | OpenAI (GPT-4o, GPT-4o-mini, Whisper) |
| PDFs | jsPDF + html2canvas |
| Planilhas | xlsx |
| Gráficos | Recharts |
| Upload | React Dropzone |
| Assinaturas | React Signature Canvas |

---

---

# 🎤 PITCH DE VENDAS — YourEyes

---

## O PROBLEMA

> **Empresas brasileiras perdem milhões por ano com:**
> - Multas trabalhistas por não conformidade com NRs
> - Passivos jurídicos por falta de evidências e rastreabilidade
> - Afastamentos evitáveis por problemas ergonômicos e psicossociais
> - Retrabalho em processos manuais (planilhas, papel, WhatsApp)
> - Desconexão entre RH, SST, Financeiro e Contabilidade
> - Burnout, turnover e perda de talentos por falta de gestão humana

---

## A SOLUÇÃO: YourEyes

### Uma plataforma que une **Governança, Compliance e Cuidado Humano** — potencializada por **Inteligência Artificial**.

O YourEyes não é apenas mais um software de RH.  
É a **primeira plataforma brasileira de Governança do Trabalho Humano**.

Unificamos **mais de 20 módulos** em uma única ferramenta que transforma cada diagnóstico em ação, cada ação em evidência, e cada evidência em proteção jurídica.

---

## DIFERENCIAIS EXCLUSIVOS

### 🤖 26 Funções de Inteligência Artificial
- **Não é IA genérica.** São assistentes especializados em SST, ergonomia, cultura, compliance e desenvolvimento humano.
- De **extrair automaticamente dados de um atestado médico** a **gerar um Manual de Cultura Organizacional** em PDF — tudo com IA.

### 📋 Plano de Ação Global (5W2H + GUT)
- **Todo módulo converge para ações.** Ergonomia detectou risco? Ação criada. Auditoria de EPI encontrou falha? Ação sugerida. Ouvidoria recebeu denúncia? Ação gerada pela IA.
- **Nenhum achado fica sem resposta.**

### 🧠 Ergonomia Preditiva
- **Radares de Burnout e Boreout** baseados em humor diário, carga e questionários psicossociais
- **INR™ — Indicador de Necessidade de Recuperação**: a IA sugere férias preventivas antes do colapso

### 🏢 Multi-Empresa Inteligente
- Gerencie **Grupos Econômicos, Matrizes, Filiais e Obras** — tudo com isolamento de dados e alternância em um clique
- Travas de segurança impedem cadastros na empresa errada

### 📄 Formalização Digital Completa
- **PDIs, férias, advertências** — tudo assinado digitalmente via links seguros (WhatsApp)
- Selos de auditoria automáticos com timestamp

### 🔒 Compliance CLT + SST Automatizado
- Aviso prévio calculado automaticamente (Lei 12.506)
- Vencimentos de férias com risco trabalhista (Arts. 134 e 137 CLT)
- Auditor IA que cruza PGR × PCMSO × LTCAT e identifica passivos

### 💚 Gestão da Felicidade (Inédito)
- 7 eixos de bem-estar com **privacidade absoluta**
- A ferramenta nunca é para punição — é um espelho para o colaborador crescer
- Questionários psicossociais com **6 indicadores automáticos**

---

## PARA QUEM É?

| Perfil | Benefício Principal |
|--------|---------------------|
| **Empresas de médio e grande porte** | Governança completa com rastreabilidade |
| **Consultorias de SST** | Atendimento multi-cliente com IA |
| **Departamentos de RH** | Automação do ciclo de vida do colaborador |
| **Técnicos de Segurança** | Compliance NR-17, EPIs e ergonomia com IA |
| **Gestores** | Indicadores preditivos e ações preventivas |
| **Diretores/C-Level** | Proteção jurídica e redução de passivos |

---

## RESULTADOS ESPERADOS

- ⏱️ **Redução de 70%** no tempo de processos manuais (admissão, EPIs, atestados)
- 📉 **Redução de passivos trabalhistas** com evidências digitais rastreáveis
- 🧠 **Prevenção de afastamentos** com indicadores preditivos (burnout, ergonomia)
- 📋 **100% de conformidade** com NRs e obrigações eSocial
- 💰 **ROI em 3 meses** pela eliminação de retrabalho e multas
- 🤝 **Melhoria do clima organizacional** com gestão humanizada

---

## CHAMADA FINAL

> ### "O YourEyes não gerencia pessoas. Ele **governa o trabalho humano.**"
>
> Cada ação é evidência.  
> Cada evidência é proteção.  
> Cada proteção é valor.
>
> **Sua empresa está protegida?**

---

*YourEyes — Plataforma de Governança do Trabalho Humano com Inteligência Artificial*

© 2026 — Todos os direitos reservados.
