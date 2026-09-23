# 📘 YourEyes — Manual do Sistema

## Plataforma de Governança do Trabalho Humano com Inteligência Artificial

> **Como usar este manual**
> Cada módulo abaixo segue a mesma estrutura, pensada tanto para o **usuário final** (RH, gestores, técnicos de SST) quanto para **ferramentas de IA que produzem vídeos e conteúdo institucional**:
> **O que é · Para que serve · Como funciona · Inteligência Artificial · Benefícios · 🎬 Gancho para vídeo.**
> Onde aparece 🎬, está uma frase-síntese pronta para virar narração ou legenda.

---

## 🏛️ VISÃO GERAL

O **YourEyes** é uma plataforma **SaaS de Governança do Trabalho Humano** que reúne, em um só ambiente, a gestão de pessoas, a segurança e saúde do trabalho (SST), a ergonomia, o compliance, a cultura organizacional e o desenvolvimento humano — tudo potencializado por **Inteligência Artificial**.

A plataforma opera sob um princípio simples e poderoso: **"Ação é evidência, e evidência é proteção."** Cada diagnóstico, indicador ou risco identificado no sistema se transforma em uma **ação estruturada, rastreável e auditável**. Nada fica só no diagnóstico.

### Os 4 pilares estratégicos

| Pilar | O que abrange |
|-------|---------------|
| 🏗️ **Organização do Trabalho** | Cargos, funções, atividades, competências, procedimentos e responsabilidades |
| ⚙️ **Condições de Execução** | EPIs, ergonomia, SST, conformidade regulatória, ambiente e jornada de trabalho |
| 💚 **Experiência Humana** | Bem-estar, humor, cultura, celebrações, ouvidoria, feedback e escuta ativa |
| 📊 **Governança e Impacto** | Plano de Ação, auditorias, indicadores, compliance e rastreabilidade total |

### O que torna o YourEyes diferente

- **Tudo conectado:** o que a ergonomia detecta vira ação; o que a auditoria de EPI encontra vira ação; o que a ouvidoria recebe vira ação. Nenhum achado fica sem resposta.
- **IA especializada, não genérica:** os assistentes de IA entendem de SST, ergonomia, cultura, compliance e desenvolvimento humano — e falam a língua das normas brasileiras.
- **Prova jurídica embutida:** assinaturas digitais, selos de auditoria, versionamento e trilhas completas transformam a operação do dia a dia em evidência de conformidade.

🎬 **Gancho para vídeo:** *"O YourEyes não gerencia pessoas. Ele governa o trabalho humano — transformando cada diagnóstico em ação, cada ação em evidência, e cada evidência em proteção."*

---

## 🔐 ACESSO, PERFIS E ONBOARDING

**O que é.** A porta de entrada segura da plataforma e a forma como cada pessoa enxerga apenas o que lhe compete.

**Para que serve.** Garantir que uma empresa nunca veja os dados de outra, que cada perfil tenha o acesso certo e que a chegada de um novo cliente seja simples e guiada.

**Como funciona.**
- Acesso por **e-mail e senha**, com recuperação de senha integrada.
- Arquitetura **multi-tenant**: cada organização tem seu espaço isolado, sem cruzamento de dados.
- **Controle de acesso por perfis (RBAC):** Proprietário, Admin, Gestor e Colaborador — cada um com permissões próprias por módulo.
- **Camada de permissão por perfil:** além do papel, o sistema controla quais módulos cada perfil pode ler e escrever, com regras de escopo (empresa inteira, apenas o próprio usuário, etc.).
- **Onboarding guiado:** ao criar a conta, o usuário é conduzido por um fluxo que configura a empresa inicial, a estrutura organizacional e as preferências do sistema.
- **Painel Super Admin** (rota `/admin`): administração geral da plataforma, com menu organizado por área — Painel (visão geral e situação das empresas), Clientes (empresas, usuários, contratos e termos), Comercial e Marketing (CRM de leads, preços e add-ons, Programa de Parceiros, Blog), Produtos (Psicossocial, MarketYE), A YourEyes e Qualidade e Suporte (QA, Central de Controle de Clientes, Manual do Sistema).

**Benefícios.** Segurança de dados por padrão, conformidade com a LGPD desde o primeiro acesso e uma experiência de entrada sem atrito para novos clientes.

🎬 **Gancho para vídeo:** *"Cada empresa no seu próprio espaço, cada pessoa com o acesso certo — segurança e privacidade desde o primeiro login."*

---

# 🏗️ FUNDAÇÃO ORGANIZACIONAL

*Onde a empresa é estruturada: unidades, cargos, pessoas e vínculos.*

---

## 🏢 MÓDULO: EMPRESA

**Rota:** `/empresa`

**O que é.** O módulo que centraliza toda a estrutura de unidades organizacionais do cliente.

**Para que serve.** Representar fielmente a realidade fiscal e física da empresa — de um grupo econômico inteiro a uma obra específica — para que todos os outros módulos saibam exatamente "onde" cada coisa acontece.

**Como funciona.**
- **Cadastro condicional por tipo de empregador:**
  - **Pessoa Jurídica:** CNPJ com busca automática (preenchimento inteligente dos dados).
  - **Pessoa Física:** CPF obrigatório, com campos CEI e CAEPF e máscaras específicas.
- **Hierarquia fiscal em 4 níveis:**
  1. **Grupo Econômico** — diferentes CNPJs sob a mesma gestão.
  2. **Matriz** — o CNPJ raiz.
  3. **Filial** — compartilha o CNPJ raiz com variação de sufixo.
  4. **Estabelecimento / Obra** — locais físicos, mesmo sem CNPJ próprio.
- Filiais **herdam automaticamente** o Grupo Econômico da Matriz.
- Criação de filiais **sem sair da tela** (inline).
- Filtros por grupo e status, e **exportação para Excel**.
- **Seletor Global de Empresa** (ícone 🏢 no cabeçalho): alterna entre empresas ou mostra a visão consolidada ("Todas as empresas"). Essa escolha **filtra o sistema inteiro** automaticamente.
- **Travas de segurança:** importação de planilhas é bloqueada quando "Todas as empresas" está selecionado; os formulários mostram um **banner destacando a empresa de destino**; campos de localidade são filtrados pela empresa ativa.

**Benefícios.** Um único cadastro que respeita a complexidade fiscal brasileira, isolamento de dados por empresa e o fim do risco de cadastrar informação na empresa errada.

🎬 **Gancho para vídeo:** *"Grupos, matrizes, filiais e obras — toda a estrutura da empresa em um só lugar, e um clique para alternar entre elas."*

---

## 📐 MÓDULO: CADASTROS BASE

**Rotas:** `/cadastros/cargos` · `/cadastros/departamentos` · `/cadastros/filiais`

**O que é.** As tabelas fundamentais que dão nome e forma à estrutura da empresa.

**Para que serve.** Padronizar cargos, departamentos e locais para que avaliações, exames, EPIs e relatórios falem sempre a mesma língua.

**Como funciona.**
- **Cargos:** nível (operacional, tático, estratégico), vínculo com departamento, **exames obrigatórios e periodicidade**, e faixa salarial.
- **Departamentos:** organização por área dentro de cada empresa.
- **Filiais / Estabelecimentos:** locais físicos vinculados às empresas, base para ponto, EPIs e prontuários.

**Benefícios.** Consistência em todo o sistema e menos retrabalho — cadastrar uma vez, usar em todos os módulos.

🎬 **Gancho para vídeo:** *"Cargos, departamentos e unidades bem definidos são a base de tudo — e o YourEyes começa por aí."*

---

## 👥 MÓDULO: COLABORADORES

**Rota:** `/colaboradores`

**O que é.** O hub unificado do ciclo de vida completo do colaborador — da admissão ao desligamento.

**Para que serve.** Reunir em um só lugar tudo sobre cada pessoa, com conformidade trabalhista automática nos momentos mais sensíveis (admissão e desligamento).

**Como funciona.**
- **Três abas principais:** Ativos, Admissões (em andamento) e Desligados (histórico).
- **Cadastro completo:** dados pessoais, profissionais e contratuais, com Estabelecimento/Obra, Centro de Custo e Gestor Imediato, sempre vinculados à empresa ativa (com banner de alerta).
- **Importação em massa por planilha** (.xlsx, .xls, .csv até 5MB), com mapeamento automático de colunas e pré-validação — bloqueada se nenhuma empresa estiver selecionada.
- **Desligamento com compliance CLT:** cálculo automático do **aviso prévio** (Lei 12.506/2011 — 30 dias + 3 por ano trabalhado, até 90), upload obrigatório do **ASO Demissional**, arquivo automático no prontuário e cancelamento automático de ações culturais futuras.

**Benefícios.** Menos erro humano, conformidade trabalhista garantida nos pontos críticos e um histórico organizado e auditável de cada colaborador.

🎬 **Gancho para vídeo:** *"Do primeiro dia ao último, o ciclo de vida do colaborador organizado, automatizado e em conformidade com a CLT."*

---

## 🧾 MÓDULO: ADMISSÃO DIGITAL

**Rota:** `/admissao`

**O que é.** O processo de admissão conduzido de ponta a ponta dentro da plataforma.

**Para que serve.** Substituir o vaivém de papéis, e-mails e planilhas por um fluxo digital, guiado e rastreável.

**Como funciona.**
- **Workflow em etapas configuráveis**, com status por etapa e responsáveis.
- **Gestão de documentos obrigatórios**, com status individual e upload direto.
- **Exame Admissional** registrado: clínica, médico, CRM, resultado e validade.
- **Dados bancários completos** (banco, agência, conta, PIX).
- **Histórico com trilha de auditoria** de cada ação do processo.
- Links seguros para o candidato completar o próprio cadastro sem precisar de login no sistema.

**Benefícios.** Admissões mais rápidas, sem documento perdido, com tudo pronto para o prontuário digital e para o eSocial.

🎬 **Gancho para vídeo:** *"Admissão sem papel: cada documento, cada exame e cada assinatura no lugar certo, do convite ao primeiro dia."*

---

## 📄 MÓDULO: CONTRATOS DE EXPERIÊNCIA

**Rota:** `/contratos-experiencia`

**O que é.** O controle do período de experiência dos novos colaboradores.

**Para que serve.** Nunca mais perder o prazo de um contrato de experiência — e evitar a efetivação automática indesejada por esquecimento.

**Como funciona.**
- Acompanha o ciclo completo: **1º Período → 2º Período → Efetivado / Encerrado**, com o estado "Vencido (virou prazo indeterminado)" sinalizado quando o prazo passa.
- **Validação de prorrogação** conforme as regras legais (duração total e limites de período).
- **Alertas de vencimento** em 30, 15 e 7 dias.
- Ações diretas: **prorrogar, efetivar ou encerrar** com poucos cliques.

**Benefícios.** Decisões de efetivação tomadas no momento certo, com respaldo legal e sem risco de efetivação por omissão.

🎬 **Gancho para vídeo:** *"O relógio do contrato de experiência corre por você — alertas na hora certa para decidir sobre cada efetivação."*

---

## 👤 MÓDULO: USUÁRIOS E PERFIS DE ACESSO

**Rotas:** `/usuarios` · `/meu-perfil`

**O que é.** A gestão de quem entra no sistema e do que cada um pode fazer.

**Para que serve.** Dar a cada gestor, RH e colaborador exatamente o acesso que precisa — nem mais, nem menos.

**Como funciona.**
- Cadastro e gestão de usuários, com vínculo a empresa(s) e perfis.
- **Perfis de acesso** com permissões por módulo e escopo (empresa inteira, próprio usuário, etc.).
- **Meu Perfil:** cada pessoa gerencia seus próprios dados e preferências.
- Mapeamento entre tipos de usuário e papéis de acesso, com filtros por status, tipo e empresa.

**Benefícios.** Governança de acesso clara, aderente à LGPD, e autonomia para o colaborador cuidar do próprio cadastro.

🎬 **Gancho para vídeo:** *"Cada pessoa vê o que precisa ver — controle de acesso granular, do proprietário ao colaborador."*

---

# ⏱️ JORNADA, FÉRIAS E FINANCEIRO

*O tempo trabalhado, o descanso devido e o dinheiro que decorre disso.*

---

## ⏰ MÓDULO: PONTO ELETRÔNICO

**Rota:** `/ponto` (e `/ponto-externo` para marcação em campo)

**O que é.** O registro e a apuração da jornada de trabalho, do batimento à folha, em conformidade com a legislação de ponto eletrônico.

**Para que serve.** Garantir que a jornada seja registrada de forma **confiável, imutável e fiscalizável**, e que o cálculo de horas, adicionais e banco de horas seja correto e defensável.

**Como funciona.**
- **A batida é prova:** uma marcação **nunca é apagada** — quando necessário, é apenas *desconsiderada*, com registro do motivo. Cada batida recebe **numeração sequencial (NSR)** e entra em uma **cadeia de hash encadeado**, o que torna a manipulação detectável.
- **Origem e relógio confiáveis:** o sistema registra de onde veio a batida e valida o horário, sinalizando marcações suspeitas ("ponto britânico").
- **Cálculo da jornada:** tolerância cumulativa, horas extras sem truncamento, **adicional noturno** (inclusive prorrogado), turno da virada, domingos e feriados em dobro, DSR e repouso de 24h, e escalas especiais como **12×36 por ciclo**.
- **Intervalos:** faixas de intervalo, supressão de intervalo (adicional de 50%) e pré-assinalação formal.
- **Banco de horas:** só com instrumento coletivo vigente, com **prazo de vencimento por crédito**, alertas de vencimento e teto, limite de 10h/dia e **liquidação do saldo na rescisão**.
- **Fechamento e folha:** geração transacional dos **espelhos de ponto**, bloqueio do fechamento em caso de pendência crítica ou espelho sem ciência do colaborador, reabertura formal de competência e **pacote da folha** com as naturezas corretas.
- **Arquivos legais:** comprovante de marcação como documento oficial e **AEJ (Arquivo Eletrônico de Jornada)** para a fiscalização.

**Benefícios.** Tranquilidade em auditoria e fiscalização, cálculo justo para empresa e colaborador, e prova robusta contra passivos trabalhistas.

🎬 **Gancho para vídeo:** *"Cada batida é uma prova imutável. Do registro ao espelho de ponto, uma jornada confiável e pronta para a fiscalização."*

---

## 📊 MÓDULO: ANÁLISE DE CARGA DE TRABALHO & JORNADA

**Rota:** `/analise-jornada`

**O que é.** A leitura analítica e preventiva da jornada — o que os números do ponto revelam sobre saúde, risco e conformidade.

**Para que serve.** Transformar dados de jornada em inteligência: identificar sobrecarga, excesso de horas extras e riscos organizacionais **antes** que virem afastamento ou passivo.

**Como funciona.** Organizado em painéis:
- **Dashboard** com a visão geral da carga de trabalho.
- **Importação** de dados de jornada.
- **Individual** e **Coletiva:** análise por pessoa e por grupo/setor.
- **Conformidade:** verificação de limites legais de jornada e descanso.
- **Alertas:** sinalizações automáticas de risco.
- **Documentos** e **Relatórios** para evidência e apresentação.

**Benefícios.** Prevenção de burnout e afastamentos, base concreta para redimensionar equipes e evidência de que a empresa monitora a saúde da jornada.

🎬 **Gancho para vídeo:** *"Horas demais são um alerta, não só um custo. A Análise de Jornada mostra onde a sobrecarga vira risco — antes do afastamento."*

---

## 🏖️ MÓDULO: FÉRIAS

**Rota:** `/ferias`

**O que é.** A gestão completa de férias, com conformidade CLT automática.

**Para que serve.** Evitar o vencimento de férias (e o risco de pagamento em dobro) e conduzir todo o fluxo — aprovação, aviso, recibo, financeiro e assinatura — sem sair da plataforma.

**Como funciona.**
- **Validação automática** de períodos aquisitivos e concessivos e das regras de **fracionamento**.
- **Monitoramento de vencimentos (Art. 134 CLT):** alertas visuais de 90, 60 e 30 dias e cálculo do risco trabalhista (Art. 137 CLT).
- **Fluxo sequencial de gestão:**
  1. ✅ **Aprovação**, com alerta de sobreposição de férias no mesmo setor.
  2. 📄 **Geração de Aviso e Recibo** em PDF.
  3. 💳 **Registro Financeiro**, com vencimento 2 dias úteis antes do início.
  4. ✍️ **Assinatura digital** via link seguro (`/ferias-assinatura/:token`).
- **Automação cultural:** mensagens pré-férias e check-in no retorno.

**Inteligência Artificial.** **INR™ — Indicador de Necessidade de Recuperação:** a IA sugere **férias preventivas** cruzando humor, sinais de burnout e sobrecarga de tarefas.

**Benefícios.** Zero férias vencidas, conformidade CLT documentada e um cuidado genuíno com a recuperação do colaborador.

🎬 **Gancho para vídeo:** *"Férias sem susto: a plataforma avisa antes de vencer, e a IA sugere descanso antes do esgotamento."*

---

## 💰 MÓDULO: FINANCEIRO E BENEFÍCIOS

**Rotas:** `/financeiro` · `/financeiro/beneficios`

**O que é.** A visão financeira ligada às pessoas: benefícios, lançamentos e integrações com férias e folha.

**Para que serve.** Dar ao RH e ao financeiro uma visão consolidada dos custos de pessoal e automatizar lançamentos recorrentes.

**Como funciona.**
- **Dashboard financeiro** com visão consolidada.
- **Gestão de benefícios por tipo:** categorias, valores e regras por cargo, unidade e vínculo.
- **Atribuição de benefícios por colaborador**, com histórico.
- **Integração com férias** para lançamentos automáticos.

**Benefícios.** Menos planilhas, custos de pessoal sob controle e integração natural com os demais módulos.

🎬 **Gancho para vídeo:** *"Benefícios, férias e folha conversando entre si — a gestão financeira de pessoas em uma visão só."*

---

## 🧾 MÓDULO: HUB CONTÁBIL INTELIGENTE

**Rota:** `/hub-contabil`

**O que é.** A ponte organizada entre a empresa e a contabilidade, com roteamento inteligente de documentos e conferências automáticas.

**Para que serve.** Acabar com o caos do envio de documentos para o contador e garantir que impostos, guias e certidões estejam sempre em dia.

**Como funciona.** Abas estratégicas:
- 📊 **Dashboard** — visão geral.
- 📅 **Competências** — abertura mensal automatizada.
- 📄 **Documentos** — envio e controle.
- 📋 **Guias** — impostos e obrigações.
- 🔍 **Conferência Cruzada** — validação automática de valores (guias × folha).
- 📜 **Certidões / CNDs** — monitoramento de validade.
- 📚 **Histórico** — trilha de auditoria.
- 📆 **Calendário** — prazos recorrentes de impostos.

E ainda: **roteamento inteligente** (holerites → dossiê do colaborador; GRRF → rescisão; recibos de férias → período aquisitivo), integração com eventos operacionais e **checklist que bloqueia o envio** ao contador se houver pendências.

**Benefícios.** Contabilidade sem retrabalho, riscos fiscais monitorados e documentos sempre no lugar certo.

🎬 **Gancho para vídeo:** *"Do holerite à CND, cada documento contábil no destino certo — e um checklist que não deixa nada passar."*

---

# 🩺 SAÚDE, SEGURANÇA E COMPLIANCE (SST)

*O coração técnico do YourEyes: proteger pessoas e blindar a empresa juridicamente.*

---

## 🩺 MÓDULO: ATESTADOS E AFASTAMENTOS

**Rota:** `/atestados`

**O que é.** O registro e a gestão de atestados médicos e do ciclo de afastamento.

**Para que serve.** Controlar afastamentos com precisão, respeitar a privacidade de dados de saúde (LGPD) e reduzir o trabalho manual de digitação.

**Como funciona.**
- Cadastro detalhado de atestados (assistenciais e ocupacionais), por tipo, com registro de **CID mediante autorização explícita**, classificação por **grupo clínico** e nexo ocupacional.
- **Afastamentos:** ciclo completo, com **alertas de 15 e 30 dias**, vínculo com benefícios do INSS (B91, B31, etc.), estabilidade provisória com data de fim calculada e controle de ASO de retorno pendente.
- **Alertas de saúde** automáticos por colaborador, com priorização e resolução rastreável.

**Inteligência Artificial.** **Extração automática de dados:** basta subir a foto/scan do atestado e a IA preenche nome, CRM, CID, datas e dias de afastamento.

**Benefícios.** Menos digitação, mais precisão, e controle fino de afastamentos e estabilidades — com privacidade preservada.

🎬 **Gancho para vídeo:** *"Fotografe o atestado e pronto: a IA lê, preenche e organiza — e o sistema cuida dos prazos de afastamento por você."*

---

## 🩺 MÓDULO: SAÚDE OCUPACIONAL (ASO)

**Rota:** `/saude-ocupacional`

**O que é.** O controle específico dos **Atestados de Saúde Ocupacional (ASO)** e da periodicidade dos exames.

**Para que serve.** Garantir que nenhum colaborador esteja com exame ocupacional vencido — requisito central do PCMSO e da fiscalização.

**Como funciona.**
- Consolida os ASOs por tipo: **Admissional, Periódico, Retorno ao Trabalho, Mudança de Função e Demissional**.
- Calcula o **próximo vencimento** de cada exame (ex.: periodicidade anual).
- Busca por colaborador, profissional ou CID e sinaliza os exames a vencer.

**Benefícios.** Conformidade com o PCMSO, aptidão dos colaboradores sempre em dia e evidência organizada para auditoria.

🎬 **Gancho para vídeo:** *"Nenhum exame ocupacional vencido passa despercebido — a saúde da equipe e a conformidade do PCMSO sob controle."*

---

## 🔒 MÓDULO: COMPLIANCE SST

**Rota:** `/compliance-sst`

**O que é.** O auditor de conformidade em saúde e segurança do trabalho, assistido por IA.

**Para que serve.** Descobrir incoerências e omissões entre os documentos legais de SST antes que a fiscalização (ou a Justiça) o faça.

**Como funciona.**
- **Auditor de IA** que analisa a coerência normativa entre **PGR** (Programa de Gerenciamento de Riscos), **PCMSO** (Programa de Controle Médico) e **LTCAT** (Laudo Técnico de Condições Ambientais).
- Identifica riscos, omissões e **passivos jurídicos**, com critérios técnicos (ex.: LINACH, Tema 555 do STF).
- Monitora eventos do **eSocial** (S-2210, S-2220, S-2240).
- Integra os diagnósticos diretamente ao **Plano de Ação Global**.

**Benefícios.** Proteção jurídica proativa, sem substituir o profissional — a IA aponta, o especialista decide.

🎬 **Gancho para vídeo:** *"PGR, PCMSO e LTCAT dizem a mesma coisa? A IA do YourEyes cruza os documentos e revela o passivo antes da fiscalização."*

---

## 🦺 MÓDULO: EPIs — EQUIPAMENTOS DE PROTEÇÃO INDIVIDUAL

**Rota:** `/epis`

**O que é.** A gestão completa de EPIs: catálogo, estoque, entregas, conformidade e auditoria.

**Para que serve.** Provar que o EPI certo foi entregue à pessoa certa, no momento certo, com o CA válido — a base da defesa em NR-6 e da segurança real.

**Como funciona.**
- **Catálogo inteligente:** Categorias → Tipos → Itens.
- **Controle de estoque** por empresa e local (Estabelecimento/Obra → Almoxarifado), com entradas (manuais ou por **importação de NF XML**), saídas (venda, descarte, perda, dano, vencimento) e **transferências internas**.
- **Entrega em 4 etapas:** seleção do EPI → prova de vida (foto) → assinatura digital → **recibo em PDF** arquivado automaticamente no prontuário. Devoluções encaminham para manutenção ou descarte.
- **Conformidade:** **Matriz de Proteção** (EPIs obrigatórios por função), monitoramento de validade do **Certificado de Aprovação (CA)** (alertas 30/90 dias) e **ciclo de vida** com sugestão de substituição por vida útil.

**Inteligência Artificial.** Vínculo automático de **NF XML** ao catálogo e **auditoria inteligente** que aponta riscos de conformidade (NR-6/NR-9), gera relatórios em PDF e sugere **ações corretivas 5W2H em lote** no Plano de Ação.

**Benefícios.** Estoque sob controle, entregas com prova jurídica e auditoria de conformidade que vira ação — não só relatório.

🎬 **Gancho para vídeo:** *"Do XML da nota à assinatura do recibo: cada EPI rastreado, cada entrega comprovada, cada risco virando ação."*

---

## 🧠 MÓDULO: ERGONOMIA INTELIGENTE

**Rota:** `/ergonomia`

**O que é.** A análise ergonômica (NR-17) assistida por IA, com radares preditivos de risco humano.

**Para que serve.** Sair da ergonomia reativa (laudo na gaveta) para a **ergonomia preditiva**, que antecipa esgotamento e propõe intervenções concretas.

**Como funciona.**
- **AEP (Análise Ergonômica Preliminar)** assistida por IA e conformidade **NR-17** automatizada.
- **Análise de vídeo:** a IA extrai os quadros estratégicos do vídeo do posto de trabalho para a avaliação.
- **Radares preditivos:** **Burnout** (esgotamento), **Boreout** (tédio/subaproveitamento) e **IRP-S** (Indicador de Risco Psicossocial).
- Recomendações da IA viram **ações 5W2H** no Plano de Ação, e fatores qualitativos (humor, ritmo, carga mental) geram ações preventivas.

**Benefícios.** Prevenção de afastamentos musculoesqueléticos e psicossociais, laudos mais rápidos e evidência técnica para intervenções.

🎬 **Gancho para vídeo:** *"A ergonomia que enxerga o futuro: radares de burnout e boreout que transformam risco em ação preventiva."*

---

## 🚨 MÓDULO: INCIDENTES E ACIDENTES

**Rota:** `/incidentes-acidentes`

**O que é.** A central de registro, investigação e prevenção de eventos de segurança — de quase-acidentes a acidentes graves.

**Para que serve.** Cumprir a Lei 8.213/91 (CAT), o eSocial (S-2210/S-2220), a NR-01 (GRO/PGR) e a ISO 45001, e — acima de tudo — **aprender com os eventos menores antes que virem acidentes graves** (lógica da Pirâmide de Bird).

**Como funciona.**
- **Cartões de Desvio:** micro-registros de condições/atos inseguros captados **antes** do incidente — a base preventiva da pirâmide.
- **Registro do evento:** classificação clara entre **Incidente** e **Acidente**, com código automático (INC/ACD/DEV), data, local, turno, envolvidos, categoria e origem.
- **Campos de acidente:** gravidade, afastamento, atendimento, óbito e **CAT** (número, data, tipo e PDF anexo), com alerta de prazo legal (1º dia útil).
- **Fatores ergonômicos e psicossociais:** cada evento alimenta o GRO e cruza com a ergonomia e o psicossocial, gerando alertas de **padrão recorrente**.
- **Pasta de investigação automática** em Documentos (5 subpastas padrão) para acidentes graves.
- **Plano de ação vinculado**, ciclo de status (Em Aberto → Em Análise → Ações em Andamento → Concluído) e **dashboard** de KPIs de SST.
- **Simulador FAP/RAT:** projeta o impacto financeiro dos acidentes na folha e simula cenários de prevenção.
- **Análise preditiva:** score de risco por setor/turno e taxa de conversão Desvio → Incidente → Acidente.

**Benefícios.** Cultura de segurança madura, CAT no prazo, defesa robusta em fiscalização e um argumento financeiro concreto (FAP/RAT) para investir em prevenção.

🎬 **Gancho para vídeo:** *"Cada quase-acidente registrado é um acidente evitado. Da base da pirâmide ao FAP, a segurança que protege pessoas e o caixa da empresa."*

---

## 📊 MÓDULO: QUESTIONÁRIO PSICOSSOCIAL

**Rota (pública):** `/questionario/:token`

**O que é.** A avaliação de riscos psicossociais, exigência da NR-01 atualizada, com indicadores automáticos e comparáveis no tempo.

**Para que serve.** Medir o clima psicológico do trabalho de forma segura e anônima, e transformar a percepção das pessoas em indicadores acionáveis.

**Como funciona.**
- Escala de 0 a 4, **modelo híbrido** (anônimo por padrão, identificação voluntária), com os temas das perguntas **ocultos** para evitar viés.
- Ciclos regulares (mensal a anual) e **reaplicações extraordinárias** por gatilho (acidente, denúncia, reestruturação, conflito, sugestão da IA ou pedido do colaborador).
- **Indicadores automáticos:** IRP-S (risco psicossocial), IBO-S (burnout), IBD-S (boreout), IREC-S (reconhecimento), ICOP-S (cooperação) e INOT-S (notificação).
- **Imutabilidade e comparabilidade histórica** garantidas.

**Benefícios.** Conformidade com a NR-01, diagnóstico honesto do ambiente e base para o PGR psicossocial — tudo com privacidade.

🎬 **Gancho para vídeo:** *"O que a equipe sente vira indicador. Anônimo, comparável e pronto para o PGR psicossocial da NR-01."*

---

## 🏗️ MÓDULO: TERCEIROS

**Rota:** `/terceiros`

**O que é.** A gestão de empresas terceiras, seus trabalhadores e a conformidade documental que libera (ou barra) o acesso ao trabalho.

**Para que serve.** Garantir que ninguém entre para trabalhar com documento vencido — protegendo a empresa da responsabilidade solidária.

**Como funciona.**
- **Três camadas:** Empresa terceira → Trabalhadores vinculados → Documentos e treinamentos.
- **Status operacional dinâmico:** Liberado ✅ · Restrito ⚠️ · Bloqueado 🚫, com validação automática de ASO, PGR, PCMSO e certificados (NR-10, NR-35, etc.).
- **Painel de vencimentos** (60/30 dias) e **log de auditoria** de versões de arquivos.
- **Permissão de Trabalho (PT) digital**, que valida a conformidade antes da liberação.

**Benefícios.** Redução do risco de responsabilidade solidária, portaria segura e documentação de terceiros sempre auditável.

🎬 **Gancho para vídeo:** *"Documento vencido, acesso bloqueado — automaticamente. A gestão de terceiros que protege a empresa da responsabilidade solidária."*

---

# 🎯 DESENVOLVIMENTO E DESEMPENHO

*Fazer as pessoas crescerem — e provar que a empresa investe nisso.*

---

## 📋 MÓDULO: AVALIAÇÕES DE DESEMPENHO

**Rota:** `/avaliacoes`

**O que é.** O sistema de avaliação de desempenho estruturado em quatro dimensões, com apoio de IA.

**Para que serve.** Avaliar com justiça e consistência, ligando desempenho a competências, desenvolvimento e contexto de trabalho.

**Como funciona.**
- **Quatro blocos:** Entrega e Qualidade (performance), Competências (função e comportamento), Evolução e Aprendizado, e Contexto de Trabalho (ergonomia e risco humano).
- **Ciclos configuráveis:** 90°, 180° ou 360°.
- Templates customizáveis, pesos por dimensão, **justificativa obrigatória** para notas extremas e **matriz 9-Box** (Desempenho × Potencial).

**Inteligência Artificial.** A IA gera **rascunhos de avaliação** integrando as evidências reais do período: metas, feedbacks, ocorrências e treinamentos — com radar de risco humano.

**Benefícios.** Avaliações mais justas e rápidas, baseadas em evidência, e uma leitura estratégica de talento com o 9-Box.

🎬 **Gancho para vídeo:** *"Avaliar com evidência, não com achismo: a IA reúne metas, feedbacks e treinamentos e prepara a avaliação para você revisar."*

---

## 🎯 MÓDULO: METAS

**Rota:** `/metas`

**O que é.** A gestão de metas e objetivos em cascata, do estratégico ao individual.

**Para que serve.** Conectar a estratégia da empresa ao dia a dia de cada pessoa, tornando visível como cada meta individual contribui para o todo.

**Como funciona.**
- **Quatro níveis com desdobramento (cascata):** **Estratégica → Unidade → Setor → Individual**. Uma meta superior se desdobra em metas dos níveis abaixo.
- **Acompanhamento vivo:** check-ins periódicos, registro de evidências e workflow de status.
- **Configuração de indicadores** e um **guia** embutido de boas práticas.
- **Dashboard** com o progresso por nível.

**Inteligência Artificial.** Assistente de IA para formular e refinar metas.

**Benefícios.** Alinhamento estratégico real, transparência sobre o que importa e acompanhamento contínuo — não apenas no fim do ciclo.

🎬 **Gancho para vídeo:** *"Da estratégia da diretoria à meta de cada pessoa: objetivos que se desdobram e se conectam, com acompanhamento vivo."*

---

## 🎯 MÓDULO: PDI — PLANO DE DESENVOLVIMENTO INDIVIDUAL

**Rota:** `/pdi`

**O que é.** O plano de desenvolvimento de cada colaborador, com metas SMART e formalização digital.

**Para que serve.** Estruturar o crescimento das pessoas e registrar formalmente o compromisso de desenvolvimento.

**Como funciona.**
- **Metas SMART** com acompanhamento de progresso e status.
- **Vínculo bidirecional** com o Plano de Ação Global.

**Inteligência Artificial.** Geração de **metas SMART** e de um **documento profissional em PDF**, arquivado no prontuário. **Formalização via link seguro (WhatsApp):** a assinatura recebe um selo de auditoria (timestamp + assinatura) e o arquivo é renomeado como "(Assinado)". Rota pública: `/pdi-assinatura/:token`.

**Benefícios.** Desenvolvimento estruturado, evidência de investimento nas pessoas e formalização sem burocracia.

🎬 **Gancho para vídeo:** *"O crescimento de cada pessoa, planejado com a IA e assinado pelo celular — desenvolvimento com compromisso documentado."*

---

## 📚 MÓDULO: APRENDIZADO E PAPÉIS

**Rota:** `/aprendizado-papeis`

**O que é.** A engenharia do trabalho: o que cada função faz, com quais competências, ferramentas, EPIs e procedimentos.

**Para que serve.** Documentar o conhecimento operacional da empresa — normalmente na cabeça das pessoas — em POPs e manuais de função profissionais.

**Como funciona.**
- **Gestão de atividades por função** e **matriz de responsabilidade** (ferramentas, interfaces, consequências de erro).
- **Mapeamento de competências** (técnicas, comportamentais, cognitivas) e **vínculo de EPIs** à função.
- Dashboards de complexidade e lacunas.

**Inteligência Artificial.**
- **Importação por áudio:** fale sobre as atividades da função e a IA as estrutura (transcrição automática).
- **POP Inteligente:** gera Procedimentos Operacionais Padrão herdando a matriz de responsabilidade, com versionamento, **visual diff**, botões de IA (Detalhar, Simplificar, Pontos de Atenção, Checklist) e marcação automática como "Desatualizado" quando a atividade muda.
- **Manuais profissionais de função** (individual ou global) em PDF, consolidando POPs, trilhas, responsabilidades, EPIs e competências — com fluxo de **assinatura** do colaborador.

**Benefícios.** Conhecimento retido na empresa, onboarding mais rápido e base sólida para treinamento e auditoria.

🎬 **Gancho para vídeo:** *"Descreva a função falando, e a IA escreve o POP. O conhecimento da operação vira manual profissional — e não vai embora com quem sai."*

---

## 🎓 MÓDULO: TRILHAS DE APRENDIZAGEM

**Rota:** `/trilhas`

**O que é.** As trilhas de capacitação direcionadas por função e cargo, com gamificação.

**Para que serve.** Garantir que cada pessoa (e cada terceiro) receba a formação certa para o seu papel — incluindo integração e NRs.

**Como funciona.**
- **11 tipos de conteúdo**, trilhas personalizadas por função/cargo e **gamificação** (medalhas e ranking).
- **Acesso para terceiros** via links públicos (`/trilha-terceiro/:token`).
- Cancelamento automático de tarefas pendentes em desligamentos e reavaliação de conteúdos em mudança de cargo.

**Benefícios.** Capacitação alinhada ao papel, engajamento pela gamificação e evidência de treinamento para compliance.

🎬 **Gancho para vídeo:** *"A formação certa para cada função — inclusive para terceiros — com trilhas, medalhas e ranking."*

---

## 🎓 MÓDULO: ACADEMIA (UNIVERSIDADE CORPORATIVA)

**Rota:** `/academia`

**O que é.** O ambiente de e-learning da empresa: uma universidade corporativa completa, com cursos, aulas, XP e conquistas.

**Para que serve.** Oferecer uma experiência de aprendizado rica e contínua, com catálogo de treinamentos, progresso e gamificação.

**Como funciona.**
- **Catálogo de treinamentos** por categoria e nível, com destaques, favoritos, "Meus cursos" e recentes.
- **Aulas** com acompanhamento de progresso.
- **Gamificação:** pontos de experiência (**XP**) e **badges** (conquistas).
- **Área administrativa** para criar e publicar treinamentos (rascunho → publicado).

**Benefícios.** Cultura de aprendizado, retenção de talentos e uma vitrine de desenvolvimento que engaja pela gamificação.

🎬 **Gancho para vídeo:** *"Uma universidade corporativa dentro da empresa: cursos, conquistas e evolução — aprender vira jogo."*

---

# 💚 CULTURA, EXPERIÊNCIA E ESCUTA

*O lado humano da governança: sentir, reconhecer, comunicar e cuidar.*

---

## 💚 MÓDULO: BEM-ESTAR (GESTÃO DA FELICIDADE)

**Rota:** `/felicidade`

**O que é.** Um espaço de autopercepção do colaborador, guiado por sete eixos de bem-estar.

**Filosofia.** Um **"espelho guiado"** — espaço de autopercepção segura, **nunca para punição ou cobrança**.

**Como funciona.**
- **Sete eixos:** Autoconhecimento (humor dos últimos 14 dias), Sentido & Propósito, Relações, Autonomia, Autorrealização, Atenção Plena e Gratidão.
- **Humor diário:** popup ao acessar o sistema (se ainda não registrou no dia), rápido e opcional em conteúdo.
- **Privacidade absoluta:** gestores veem apenas **tendências agregadas** e alertas por eixo — **nunca a identificação individual**. A régua de 1 a 5 alimenta um **radar visual** de bem-estar.

**Benefícios.** Sinais precoces de mal-estar coletivo, cuidado real com as pessoas e dados de bem-estar que alimentam ergonomia e férias preventivas — sem expor ninguém.

🎬 **Gancho para vídeo:** *"Um espelho, não um holofote: bem-estar com privacidade absoluta, onde o colaborador se conhece e a empresa cuida do coletivo."*

---

## 🎉 MÓDULO: CULTURA E CELEBRAÇÕES

**Rota:** `/cultura-celebracoes`

**O que é.** A automação do reconhecimento e das datas que importam para cada pessoa.

**Para que serve.** Fazer com que aniversários, tempo de casa e o Dia da Profissão nunca passem em branco — com o tom certo para cada um.

**Como funciona.**
- Mapeamento automático do **Dia da Profissão** para mais de 40 funções.
- Coleta de **preferências de reconhecimento** no onboarding.
- **Gatilhos automáticos:** cancelamento de ações culturais em desligamento e reavaliação em mudança de cargo.
- **Felicitações automáticas** (aniversários, tempo de casa).

**Inteligência Artificial.** Geração de **mensagens personalizadas** de celebração.

**Benefícios.** Reconhecimento consistente, clima positivo e pertencimento — no automático, mas com personalização.

🎬 **Gancho para vídeo:** *"Nenhuma data importante esquecida: reconhecimento automático e personalizado, do aniversário ao Dia da Profissão."*

---

## 🏛️ MÓDULO: ESTRATÉGIA E GOVERNANÇA

**Rota:** `/estrategia`

**O que é.** A camada estratégica: cultura organizacional, análises e organograma, com IA.

**Para que serve.** Traduzir a identidade e a estratégia da empresa em documentos vivos e em ações concretas.

**Como funciona.**
- **Cultura organizacional:** Missão, Visão, Valores, Princípios e Comportamentos, com **assistente de IA** e geração de um **Manual de Cultura** em PDF de layout premium.
- **Análise SWOT** (Forças, Fraquezas, Oportunidades, Ameaças), integrada ao Oceano Azul.
- **Matriz Oceano Azul** (Eliminar, Reduzir, Elevar, Criar), com IA que integra o SWOT e cria **ações 5W2H em lote** no Plano de Ação, já com prioridades GUT.
- **Organograma visual** interativo.

**Benefícios.** Estratégia que sai do papel e vira ação priorizada, com identidade cultural documentada e comunicável.

🎬 **Gancho para vídeo:** *"Da missão ao organograma, da SWOT ao Oceano Azul: a estratégia da empresa vira ação priorizada — com a IA no comando do detalhamento."*

---

## 📝 MÓDULO: FEEDBACK E OCORRÊNCIAS

**Rota:** `/feedback-ocorrencias`

**O que é.** O registro de feedbacks estruturados e de ocorrências disciplinares formais.

**Para que serve.** Dar aos gestores uma ferramenta para reconhecer, alinhar e desenvolver — e para formalizar ocorrências com respaldo.

**Como funciona.**
- **Feedbacks estruturados** por tipo (Positivo, Neutro, Negativo) e foco (Reconhecimento, Alinhamento, Desenvolvimento).
- **Ocorrências disciplinares:** advertências formais, **links externos seguros** para formalização sem login, upload de documentos assinados e trilha de auditoria.

**Inteligência Artificial.** Transforma anotações brutas em **redações profissionais**, com sugestão de tom e estrutura.

**Benefícios.** Feedback de qualidade sem esforço de redação e ocorrências formalizadas com segurança jurídica.

🎬 **Gancho para vídeo:** *"Anote a ideia; a IA escreve o feedback profissional. E cada ocorrência formalizada com trilha e assinatura."*

---

## 📢 MÓDULO: OUVIDORIA

**Rota:** `/ouvidoria`

**O que é.** O canal de escuta formal da empresa — denúncias, elogios, sugestões e reclamações — com análise por IA.

**Para que serve.** Cumprir requisitos de canal de denúncias, proteger o denunciante e transformar manifestações em ações corretivas.

**Como funciona.**
- Submissões **anônimas ou identificadas**, por tipo (Denúncia, Elogio, Sugestão, Reclamação), com múltiplos anexos e roteamento por departamento.
- **RLS** protege as identidades anônimas; rastreabilidade total das ações corretivas.

**Inteligência Artificial.** **Análise de sentimento** (positivo, neutro, negativo, urgente), classificação e subcategorias automáticas, priorização, identificação de riscos e **sugestão de planos de ação 5W2H**.

**Benefícios.** Confiança para reportar, triagem inteligente do que é urgente e resolução rastreável — do relato à ação.

🎬 **Gancho para vídeo:** *"Um canal seguro para falar, uma IA que entende a urgência, e cada manifestação virando ação corretiva rastreável."*

---

## 📰 MÓDULO: FEED (MURAL INTERNO)

**Rota:** `/feed`

**O que é.** O mural de comunicação interna da empresa.

**Para que serve.** Centralizar comunicados, avisos e novidades em um canal único, dentro da própria plataforma que a equipe já usa.

**Como funciona.** Publicação e leitura de comunicados internos, visíveis à equipe conforme a empresa ativa.

**Benefícios.** Comunicação alinhada, menos ruído em grupos de mensagens e informação no mesmo lugar do trabalho.

🎬 **Gancho para vídeo:** *"O recado certo, para as pessoas certas, no lugar onde o trabalho já acontece."*

---

# 📊 GOVERNANÇA E OPERAÇÃO

*O que amarra tudo: ação, documento, pendência e suporte.*

---

## 📋 MÓDULO: PLANO DE AÇÃO GLOBAL

**Rota:** `/plano-acao` (detalhe em `/plano-acao/:id`)

**O que é.** O coração da governança do YourEyes. **Todos os módulos convergem para cá.**

**Para que serve.** Garantir que **nenhum achado fique sem resposta** — cada risco, diagnóstico ou sugestão vira uma ação com dono, prazo e evidência.

**Como funciona.**
- Metodologia **5W2H** (O quê, Por quê, Onde, Quando, Quem, Como, Quanto).
- **Matriz GUT** para priorização (Gravidade × Urgência × Tendência).
- Subtarefas com progresso incremental ou conclusão direta.
- **Rastreabilidade de origem** com selos/emojis (AEP, Auditoria de EPI, Oceano Azul, Ouvidoria, etc.).
- Cards de estatística clicáveis, aba de **ações críticas** (atrasadas) e filtros por período e responsável.
- **Autogestão:** qualquer perfil pode criar seus próprios planos, integrando-se ao PDI.

**Inteligência Artificial.** Assistente que **gera e refina ações** com base no diagnóstico de origem.

**Benefícios.** Governança de verdade: visibilidade total, priorização inteligente e a certeza de que o diagnóstico virou execução.

🎬 **Gancho para vídeo:** *"Todo diagnóstico termina aqui — em uma ação com dono, prazo e evidência. É onde a governança acontece."*

---

## 📁 MÓDULO: GESTÃO DOCUMENTAL

**Rota:** `/documentos`

**O que é.** O repositório organizado e automático de documentos da empresa e dos colaboradores.

**Para que serve.** Ter cada documento no lugar certo, encontrável e vinculado ao seu contexto — sem pastas soltas e duplicadas.

**Como funciona.**
- **Prontuários (colaboradores):** hierarquia Empresa → Estabelecimento/Obra → Colaborador → Ano.
- **Processos:** documentos por função (ex.: POPs gerados pelo módulo Aprendizado).
- **Sincronização automática** de pastas, metadados vinculados (ex.: pop_id, colaborador_id) e índices que evitam duplicidade.

**Benefícios.** Documentação sempre organizada, auditável e alimentada automaticamente pelos outros módulos.

🎬 **Gancho para vídeo:** *"Cada recibo, ASO e POP no lugar certo — organizado automaticamente, pronto para a auditoria."*

---

## ✅ MÓDULO: PENDÊNCIAS

**Rota:** `/pendencias`

**O que é.** O painel único que reúne tudo o que exige atenção — para cada perfil.

**Para que serve.** Substituir a caça a pendências espalhadas por um só lugar que diz, por prioridade, o que precisa ser feito agora.

**Como funciona.**
- Consolida pendências de **férias, documentos, ajustes de ponto, avaliações, desligamentos, afastamentos e alertas de saúde**.
- Organizado por papel: **Todos, Gestor, RH e Colaborador**, com **níveis de prioridade** (alta, média, baixa) e busca.

**Benefícios.** Nada cai no esquecimento, o time trabalha por prioridade e cada perfil vê exatamente as suas tarefas.

🎬 **Gancho para vídeo:** *"Uma lista, todas as pendências, por prioridade e por papel — o que fazer agora, num só lugar."*

---

## 💬 ASSISTENTE VIRTUAL SST (CHAT IA)

**Onde:** widget flutuante em todas as telas.

**O que é.** Um especialista em SST disponível a qualquer momento, dentro do sistema.

**Para que serve.** Tirar dúvidas técnicas de segurança, ergonomia e saúde ocupacional na hora, com base nas normas brasileiras.

**Como funciona.** Conhecimento sobre NRs, AET/AEP, EPIs, PCMSO, PGR e LTCAT; respostas em português com **citação de normas**, em tempo real (streaming), com perguntas sugeridas e formatação clara.

**Benefícios.** Conhecimento técnico acessível a todos, decisões mais seguras e menos dependência de consulta externa para dúvidas rotineiras.

🎬 **Gancho para vídeo:** *"Um especialista em segurança do trabalho a um clique, em qualquer tela — com resposta na norma certa."*

---

## ⚙️ CONFIGURAÇÕES, MEU PLANO E SUPORTE

**Rotas:** `/configuracoes` · `/meu-plano` · `/suporte` · `/meu-perfil`

**O que é.** Os módulos de operação da conta: preferências, informações do plano, canal de suporte e dados pessoais.

**Como funciona.**
- **Configurações:** preferências do sistema e do tenant.
- **Meu Plano:** informações da assinatura e dos recursos contratados pela empresa.
- **Central de Suporte:** canal de atendimento e ajuda dentro da plataforma.
- **Meu Perfil:** dados e preferências de cada usuário.

**Benefícios.** Autonomia para o cliente gerir a própria conta e um canal de ajuda sempre à mão.

🎬 **Gancho para vídeo:** *"Sua conta, seu plano e o suporte — tudo à mão, sem sair da plataforma."*

---

# 🌐 ECOSSISTEMA YOUREYES

*Além das paredes da empresa: especialistas e parceiros.*

---

## 🌐 MARKETYE — REDE DE ESPECIALISTAS

**Rotas:** `/marketye` (público) · portal do especialista · cadastro de especialista

**O que é.** O marketplace que conecta empresas a profissionais e especialistas de SST, saúde e gestão de pessoas — com governança embutida.

**Para que serve.** Permitir que a empresa encontre e contrate o especialista certo com segurança, e que profissionais qualificados ofereçam seus serviços dentro de um ambiente confiável.

**Como funciona.**
- **Cadastro de profissionais** com documentos obrigatórios (RG, CPF/CNPJ, registro no conselho, diplomas), selfie de verificação e foto de perfil; **Atestado de Capacidade Técnica** opcional que prioriza no ranking.
- **Portal do especialista** para gestão do próprio perfil e das oportunidades.
- **Governança:** bloqueio automático de profissionais com registros vencidos e auditoria que impede a oferta de serviços fora do escopo legal do conselho.

**Benefícios.** Contratação segura e verificada, ampliação da rede de atendimento e confiança para ambos os lados.

🎬 **Gancho para vídeo:** *"A empresa certa e o especialista certo se encontram — com registro verificado e governança que protege os dois lados."*

---

## 🤝 PROGRAMA DE PARCEIROS

**Rotas:** `/parceiros` (público) · portal do parceiro · cadastro e contrato de parceria

**O que é.** O canal para parceiros que indicam e revendem o YourEyes.

**Para que serve.** Ampliar o alcance da plataforma por meio de uma rede de parceiros, com cadastro, contrato e portal próprios.

**Como funciona.** Cadastro do parceiro, **contrato de parceria** e um **portal do parceiro** para acompanhar a sua atuação e o seu perfil.

**Benefícios.** Crescimento por rede, relação formalizada e um espaço dedicado para o parceiro.

🎬 **Gancho para vídeo:** *"Cresça com a gente: um programa de parceiros com cadastro, contrato e portal próprios."*

---

# 🤖 INTELIGÊNCIA ARTIFICIAL — VISÃO GERAL

A IA do YourEyes **não é genérica**: são assistentes especializados, embutidos em cada módulo, que entendem de SST, ergonomia, cultura, compliance e desenvolvimento humano — e falam a língua das normas brasileiras.

| Onde atua | O que a IA faz |
|-----------|----------------|
| **Atestados** | Lê a foto do atestado e preenche os dados automaticamente |
| **Compliance SST** | Cruza PGR × PCMSO × LTCAT e aponta passivos e omissões |
| **EPIs** | Vincula NF XML ao catálogo e audita a conformidade (NR-6/NR-9) |
| **Ergonomia** | Analisa vídeo do posto e projeta radares de burnout e boreout |
| **Incidentes** | Score preditivo de risco e simulação de impacto no FAP/RAT |
| **Ouvidoria** | Análise de sentimento e sugestão de ações corretivas |
| **Estratégia** | Traduz SWOT em ações Oceano Azul (5W2H + GUT) |
| **Feedback** | Transforma anotações em redações profissionais |
| **Avaliações** | Gera rascunhos com base em evidências reais do período |
| **Aprendizado** | Cria POPs por áudio e manuais de função completos |
| **PDI / Metas** | Gera metas SMART e refina objetivos |
| **Cultura** | Gera Manual de Cultura e mensagens de celebração |
| **Férias** | INR™: sugere descanso preventivo antes do esgotamento |
| **Assistente SST** | Responde dúvidas técnicas citando as NRs |

**O fio condutor da IA:** ela não apenas informa — ela **converte diagnóstico em ação** dentro do Plano de Ação Global. Da detecção à execução, com o profissional sempre no controle da decisão.

🎬 **Gancho para vídeo:** *"Uma IA que entende de norma, de gente e de risco — e que transforma cada diagnóstico em ação."*

---

# 🔒 SEGURANÇA, PRIVACIDADE E GOVERNANÇA DE DADOS

O YourEyes lida com dados sensíveis (saúde, ergonomia, psicossocial) e foi construído com a **LGPD** no centro.

- **Multi-tenant com isolamento total:** cada empresa em seu espaço, sem cruzamento de dados.
- **RLS (Row Level Security)** em todas as tabelas, garantindo o isolamento na camada do banco.
- **RBAC + permissões por perfil:** acesso por papel e por escopo, módulo a módulo.
- **Dados de saúde protegidos** (LGPD art. 11): CID só com autorização explícita; bem-estar sem identificação individual.
- **Trilha de auditoria** completa: usuário, módulo, ação, alvo, metadados, IP e data/hora — rastreabilidade total.
- **Assinaturas digitais com selo de auditoria** (timestamp) em férias, PDI, EPIs, documentos e contratos.

🎬 **Gancho para vídeo:** *"Dados sensíveis exigem cuidado sério: isolamento por empresa, privacidade por padrão e rastreabilidade em cada clique."*

---

---

# 🎤 INSTITUCIONAL — POSICIONAMENTO YOUREYES

*Bloco para conteúdo institucional e de vendas. Números de plano e preço não constam aqui e devem ser fornecidos oficialmente pela empresa antes de qualquer uso comercial.*

---

## O PROBLEMA

As empresas brasileiras convivem com dores caras e crônicas:
- Multas e passivos trabalhistas por não conformidade com as NRs e a CLT.
- Falta de evidências e rastreabilidade quando a fiscalização ou a Justiça chega.
- Afastamentos evitáveis por problemas ergonômicos e psicossociais.
- Retrabalho em processos manuais — planilhas, papel e mensagens soltas.
- Desconexão entre RH, SST, Financeiro e Contabilidade.
- Burnout, turnover e perda de talentos por falta de gestão humana.

🎬 **Gancho para vídeo:** *"O problema não é falta de esforço. É falta de conexão, de evidência e de ação."*

---

## A SOLUÇÃO: YOUREYES

Uma plataforma que une **Governança, Compliance e Cuidado Humano** — potencializada por **Inteligência Artificial**.

O YourEyes não é apenas mais um software de RH. É uma plataforma de **Governança do Trabalho Humano**, que unifica dezenas de módulos e transforma **cada diagnóstico em ação, cada ação em evidência, e cada evidência em proteção**.

🎬 **Gancho para vídeo:** *"Não é RH. Não é só SST. É a governança completa do trabalho humano, em uma só plataforma."*

---

## DIFERENCIAIS EXCLUSIVOS

- **🤖 IA especializada em cada módulo** — de extrair dados de um atestado a gerar um Manual de Cultura, tudo com IA que entende do assunto.
- **📋 Plano de Ação Global (5W2H + GUT)** — todo módulo converge para ações; nenhum achado fica sem resposta.
- **🧠 Ergonomia e saúde preditivas** — radares de burnout e boreout e o INR™, que sugere descanso antes do colapso.
- **🏢 Multi-empresa inteligente** — grupos, matrizes, filiais e obras, com isolamento de dados e alternância em um clique.
- **📄 Formalização digital completa** — PDIs, férias, advertências, EPIs e contratos assinados por link seguro, com selo de auditoria.
- **🔒 Compliance CLT + SST automatizado** — aviso prévio, vencimentos de férias, ponto imutável e auditoria PGR × PCMSO × LTCAT.
- **💚 Gestão da Felicidade** — sete eixos de bem-estar com privacidade absoluta; a ferramenta é espelho, nunca holofote.

🎬 **Gancho para vídeo:** *"Enquanto os outros registram o passado, o YourEyes previne o futuro — e transforma tudo em ação."*

---

## PARA QUEM É?

| Perfil | Benefício principal |
|--------|---------------------|
| **Empresas de médio e grande porte** | Governança completa com rastreabilidade |
| **Consultorias de SST** | Atendimento multi-cliente com IA |
| **Departamentos de RH** | Automação do ciclo de vida do colaborador |
| **Técnicos e Engenheiros de Segurança** | Compliance NR-17, EPIs e ergonomia com IA |
| **Gestores** | Indicadores preditivos e ações preventivas |
| **Diretores / C-Level** | Proteção jurídica e redução de passivos |

🎬 **Gancho para vídeo:** *"Do técnico de segurança ao C-level: cada perfil encontra no YourEyes a resposta que procura."*

---

## RESULTADOS ESPERADOS

- ⏱️ **Menos tempo** em processos manuais (admissão, EPIs, atestados).
- 📉 **Redução de passivos trabalhistas** com evidências digitais rastreáveis.
- 🧠 **Prevenção de afastamentos** com indicadores preditivos.
- 📋 **Conformidade** com NRs e obrigações do eSocial.
- 💰 **Eliminação de retrabalho e multas**.
- 🤝 **Melhoria do clima organizacional** com gestão humanizada.

> *Os percentuais e projeções de ROI devem ser confirmados com dados oficiais da empresa antes de uso em peças comerciais.*

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

*YourEyes — Plataforma de Governança do Trabalho Humano com Inteligência Artificial.*
