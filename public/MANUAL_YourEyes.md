# 📘 YourEyes — Manual do Usuário

## Guia prático de uso da plataforma, módulo por módulo

> **Como este manual está organizado**
> Cada módulo segue a mesma estrutura, pensada para você usar no dia a dia:
> **O que é · Para que serve · Como utilizar (passo a passo) · Onde essa ação impacta · Benefícios.**
> O passo a passo mostra como **incluir**, **alterar** e concluir as principais ações; "Onde essa ação impacta" indica o que muda em outras telas quando você faz aquilo.

> **Antes de começar — leia isto uma vez**
> - **Seletor de empresa (🏢 no topo):** quase tudo no sistema é filtrado pela empresa selecionada. Antes de cadastrar ou importar qualquer coisa, confirme no cabeçalho **qual empresa está ativa**. Com "Todas as empresas" selecionado, cadastros e importações ficam bloqueados de propósito.
> - **Salvar:** ações de cadastro só valem depois de clicar em **Salvar/Confirmar**. Formulários mostram um aviso da empresa de destino para evitar cadastro no lugar errado.
> - **Perfis de acesso:** você vê e edita apenas o que seu perfil permite (Proprietário, Admin, Gestor ou Colaborador). Se um botão não aparece, provavelmente é permissão.

---

## 🏛️ VISÃO GERAL

O **YourEyes** é uma plataforma que reúne, em um só lugar, a gestão de pessoas, a segurança e saúde do trabalho (SST), a ergonomia, o compliance, a cultura e o desenvolvimento humano — com apoio de **Inteligência Artificial**.

O princípio que guia o sistema é simples: **cada diagnóstico vira uma ação, e cada ação fica registrada e rastreável.** Por isso muitos módulos terminam gerando tarefas no **Plano de Ação**.

### Os 4 pilares

| Pilar | O que abrange |
|-------|---------------|
| 🏗️ **Organização do Trabalho** | Cargos, funções, atividades, competências e procedimentos |
| ⚙️ **Condições de Execução** | EPIs, ergonomia, SST, conformidade e jornada |
| 💚 **Experiência Humana** | Bem-estar, cultura, celebrações, ouvidoria e feedback |
| 📊 **Governança e Impacto** | Plano de Ação, indicadores, compliance e rastreabilidade |

---

## 🔐 ACESSO, PERFIS E PRIMEIRO USO

**O que é.** A entrada no sistema e a forma como cada pessoa enxerga apenas o que lhe compete.

**Para que serve.** Manter os dados de cada empresa isolados e dar a cada perfil o acesso certo.

**Como utilizar (passo a passo).**
1. Acesse com **e-mail e senha**. Esqueceu a senha? Use **"Esqueci minha senha"** para receber o link de redefinição.
2. No primeiro acesso, siga o **onboarding guiado**: ele configura os dados da empresa, a estrutura inicial e as preferências.
3. No topo, use o **seletor de empresa (🏢)** para escolher em qual empresa você vai trabalhar.
4. Para ajustar seus dados, abra **Meu Perfil**.
5. (Administração) Novos usuários e permissões são criados no módulo **Usuários**.

**Onde essa ação impacta.**
- A empresa selecionada filtra **todo o sistema** (colaboradores, ponto, EPIs, relatórios).
- O perfil define quais módulos você abre e o que pode editar.

**Benefícios.** Segurança e privacidade dos dados desde o primeiro acesso, sem risco de misturar informação entre empresas.

---

# 🏗️ FUNDAÇÃO ORGANIZACIONAL

*Onde a empresa é estruturada: unidades, cargos, pessoas e vínculos.*

---

## 🏢 MÓDULO: EMPRESA

**Rota:** `/empresa`

**O que é.** O cadastro das unidades organizacionais (grupo, matriz, filiais e obras).

**Para que serve.** Representar a estrutura real da empresa para que todos os outros módulos saibam "onde" cada coisa acontece.

**Como utilizar (passo a passo).**
1. Abra **Empresa** no menu.
2. Para **incluir**, clique em **Nova Empresa**.
3. Escolha o tipo de empregador:
   - **Pessoa Jurídica:** digite o **CNPJ** — os dados são preenchidos automaticamente.
   - **Pessoa Física:** informe o **CPF** (com os campos CEI/CAEPF quando aplicável).
4. Defina a posição na hierarquia: **Grupo Econômico → Matriz → Filial → Estabelecimento/Obra**. Filiais herdam o grupo da matriz.
5. Clique em **Salvar**.
6. Para **alterar**, clique sobre a empresa na lista e edite os campos; para criar uma filial rapidamente, use a criação **inline** sem sair da tela.
7. Use os **filtros** (grupo, status) e **Exportar para Excel** quando precisar da lista.

**Onde essa ação impacta.**
- A empresa passa a aparecer no **seletor 🏢** do topo e a filtrar todo o sistema.
- Estabelecimentos/Obras ficam disponíveis para vincular colaboradores, ponto, EPIs e prontuários.
- Obrigações da empresa podem virar itens no **Plano de Ação**.

**Benefícios.** Um cadastro único que respeita a realidade fiscal brasileira e evita cadastro na empresa errada.

---

## 📐 MÓDULO: CADASTROS BASE (Cargos, Departamentos, Filiais)

**Rotas:** `/cadastros/cargos` · `/cadastros/departamentos` · `/cadastros/filiais`

**O que é.** As tabelas básicas que dão nome e forma à estrutura (cargos, áreas e locais).

**Para que serve.** Padronizar cargos, departamentos e unidades para que avaliações, exames e EPIs falem a mesma língua.

**Como utilizar (passo a passo).**
1. Abra o cadastro desejado no menu **Cadastros**.
2. Para **incluir**, clique no botão de novo registro e preencha:
   - **Cargo:** nome, nível (operacional/tático/estratégico), departamento, **exames obrigatórios e periodicidade** e faixa salarial.
   - **Departamento:** nome e área.
   - **Filial/Estabelecimento:** nome e vínculo com a empresa.
3. Clique em **Salvar**.
4. Para **alterar**, clique no item na lista, ajuste e salve.

**Onde essa ação impacta.**
- Cargos alimentam **exames ocupacionais** (Saúde Ocupacional), **matriz de EPIs** e **avaliações**.
- Departamentos e filiais aparecem como filtros e destinos em vários módulos.

**Benefícios.** Consistência em todo o sistema: cadastrar uma vez, usar em todos os módulos.

---

## 👥 MÓDULO: COLABORADORES

**Rota:** `/colaboradores`

**O que é.** O cadastro e o histórico completo de cada colaborador, do início ao desligamento.

**Para que serve.** Centralizar tudo sobre cada pessoa, com conformidade trabalhista nos momentos críticos.

**Como utilizar (passo a passo).**
1. Confirme a **empresa ativa** no topo.
2. Abra **Colaboradores**. Use as abas **Ativos**, **Admissões** e **Desligados**.
3. Para **incluir um colaborador**, clique em **Novo Colaborador** e preencha dados pessoais, profissionais e contratuais (Estabelecimento/Obra, Centro de Custo, Gestor Imediato). Salve.
4. Para **incluir vários de uma vez**, use **Importar planilha** (.xlsx/.xls/.csv), confira o mapeamento de colunas e confirme.
5. Para **alterar**, clique no colaborador e edite os dados.
6. Para **desligar**, abra o colaborador → **Desligar**: o sistema calcula o **aviso prévio** (Lei 12.506/2011), pede o **ASO Demissional** e conclui o processo.

**Onde essa ação impacta.**
- O colaborador passa a aparecer em ponto, férias, EPIs, avaliações, trilhas, etc.
- No desligamento, ações culturais futuras são canceladas e os documentos vão para o **prontuário** (Gestão Documental).
- A importação é **bloqueada** se nenhuma empresa estiver selecionada.

**Benefícios.** Menos erro manual e conformidade trabalhista garantida nos pontos sensíveis.

---

## 🧾 MÓDULO: ADMISSÃO DIGITAL

**Rota:** `/admissao`

**O que é.** O processo de admissão conduzido de ponta a ponta dentro da plataforma.

**Para que serve.** Substituir papéis e planilhas por um fluxo digital, guiado e rastreável.

**Como utilizar (passo a passo).**
1. Abra **Admissão** e clique em **Nova Admissão**.
2. Preencha os dados do candidato e avance pelas **etapas do workflow**.
3. Anexe os **documentos obrigatórios** (cada um com seu status) e registre o **Exame Admissional** (clínica, médico, CRM, resultado, validade).
4. Informe os **dados bancários** (banco, agência, conta, PIX).
5. Se quiser que o próprio candidato preencha, envie o **link seguro de cadastro**.
6. Para **alterar**, reabra a admissão e ajuste as etapas/documentos. Ao concluir, o colaborador passa a ativo.

**Onde essa ação impacta.**
- Ao concluir, gera o registro em **Colaboradores** e organiza os documentos no **prontuário**.
- Alimenta os dados necessários para o **eSocial**.

**Benefícios.** Admissões mais rápidas, sem documento perdido.

---

## 📄 MÓDULO: CONTRATOS DE EXPERIÊNCIA

**Rota:** `/contratos-experiencia`

**O que é.** O controle do período de experiência dos novos colaboradores.

**Para que serve.** Nunca perder o prazo de um contrato de experiência (e evitar a efetivação automática por esquecimento).

**Como utilizar (passo a passo).**
1. Abra **Contratos de Experiência** — a lista mostra quem está em **1º Período**, **2º Período**, **Efetivado** ou **Encerrado**, com os que vencem em **30/15/7 dias** destacados.
2. Para **prorrogar**, abra o contrato e clique em **Prorrogar** (o sistema valida os limites legais).
3. Para **efetivar**, clique em **Efetivar**.
4. Para **encerrar**, clique em **Encerrar** antes do vencimento.

**Onde essa ação impacta.**
- A situação do colaborador é atualizada; deixar vencer sem ação vira **prazo indeterminado** automaticamente.

**Benefícios.** Decisão de efetivação na hora certa, com respaldo legal.

---

## 👤 MÓDULO: USUÁRIOS E PERFIS DE ACESSO

**Rotas:** `/usuarios` · `/meu-perfil`

**O que é.** A gestão de quem entra no sistema e do que cada um pode fazer.

**Para que serve.** Dar a cada pessoa exatamente o acesso necessário.

**Como utilizar (passo a passo).**
1. Abra **Usuários** (perfis Admin/Proprietário).
2. Para **incluir**, clique em **Novo Usuário**, informe e-mail e dados, vincule à(s) empresa(s) e escolha o **perfil de acesso**. Salve.
3. Para **alterar**, clique no usuário e ajuste perfil/vínculos/status.
4. Cada pessoa gerencia os próprios dados em **Meu Perfil**.

**Onde essa ação impacta.**
- O perfil define quais módulos o usuário abre e o que pode editar (por empresa e por escopo).

**Benefícios.** Governança de acesso clara e aderente à LGPD.

---

# ⏱️ JORNADA, FÉRIAS E FINANCEIRO

---

## ⏰ MÓDULO: PONTO ELETRÔNICO

**Rota:** `/ponto` (e `/ponto-externo` para marcação em campo)

**O que é.** O registro e a apuração da jornada, da batida à folha, em conformidade com a legislação de ponto.

**Para que serve.** Garantir jornada **confiável, imutável e fiscalizável**, com cálculo correto de horas, adicionais e banco de horas.

**Como utilizar (passo a passo).**
1. Abra **Ponto** e selecione a **competência** (mês) e a empresa.
2. Acompanhe as **marcações** dos colaboradores; uma batida **nunca é apagada** — quando necessário, é apenas **desconsiderada** com o motivo registrado.
3. Para **ajustar/justificar**, abra o dia do colaborador e registre a justificativa/ajuste (fica na trilha de auditoria).
4. Confira o **cálculo** da jornada (horas extras, adicional noturno, DSR, escalas como 12×36) e trate as **pendências**.
5. Para **fechar a competência**, use **Fechar/Gerar espelhos** — o sistema bloqueia o fechamento se houver pendência crítica ou espelho sem ciência do colaborador.
6. Gere a **folha** e os **arquivos legais** (comprovantes e AEJ) quando necessário.

**Onde essa ação impacta.**
- Alimenta a **Análise de Jornada**, o **banco de horas** e a **folha**.
- Pendências de ponto aparecem no módulo **Pendências**.

**Benefícios.** Tranquilidade em fiscalização e cálculo justo para empresa e colaborador.

---

## 📊 MÓDULO: ANÁLISE DE CARGA DE TRABALHO & JORNADA

**Rota:** `/analise-jornada`

**O que é.** A leitura analítica da jornada — o que os números do ponto revelam sobre sobrecarga e risco.

**Para que serve.** Identificar excesso de horas e riscos **antes** que virem afastamento.

**Como utilizar (passo a passo).**
1. Abra **Análise de Jornada**.
2. Na aba **Importação**, carregue os dados de jornada quando necessário.
3. Use **Dashboard**, **Individual** e **Coletiva** para analisar por pessoa e por grupo.
4. Verifique a aba **Conformidade** (limites legais) e os **Alertas** de risco.
5. Gere **Relatórios** e **Documentos** para evidência.

**Onde essa ação impacta.**
- Os alertas podem embasar ações preventivas no **Plano de Ação** e conversas de gestão.

**Benefícios.** Prevenção de burnout e base concreta para redimensionar equipes.

---

## 🏖️ MÓDULO: FÉRIAS

**Rota:** `/ferias`

**O que é.** A gestão completa de férias, com conformidade CLT automática.

**Para que serve.** Evitar o vencimento de férias e conduzir todo o fluxo sem sair da plataforma.

**Como utilizar (passo a passo).**
1. Abra **Férias** — a lista mostra os **vencimentos** com alertas de 90/60/30 dias.
2. Para **incluir**, clique em **Nova Férias/Programar**, escolha o colaborador e o período (o sistema valida período aquisitivo, concessivo e fracionamento).
3. **Aprove** a solicitação (há alerta se houver sobreposição no mesmo setor).
4. Gere o **Aviso e o Recibo** (PDF).
5. Confirme o **registro financeiro** (vencimento 2 dias úteis antes do início).
6. Envie o **link de assinatura digital** para o colaborador assinar.

**Onde essa ação impacta.**
- Gera lançamento no **Financeiro** e documentos no **prontuário**.
- Dispara mensagens culturais (pré-férias e retorno).
- A IA (**INR™**) pode **sugerir férias preventivas** com base em humor, burnout e sobrecarga.

**Benefícios.** Zero férias vencidas e conformidade documentada.

---

## 💰 MÓDULO: FINANCEIRO E BENEFÍCIOS

**Rotas:** `/financeiro` · `/financeiro/beneficios`

**O que é.** A visão financeira ligada às pessoas: benefícios e lançamentos.

**Para que serve.** Dar visão consolidada dos custos de pessoal e automatizar lançamentos recorrentes.

**Como utilizar (passo a passo).**
1. Abra **Financeiro** para ver o **dashboard** consolidado.
2. Em **Benefícios**, para **incluir** um tipo, clique em novo, defina categoria, valor e regras (por cargo, unidade, vínculo). Salve.
3. Para **atribuir** um benefício a um colaborador, abra o colaborador no módulo e registre a atribuição (fica com histórico).
4. Para **alterar**, edite o tipo de benefício ou a atribuição.

**Onde essa ação impacta.**
- Integra com **Férias** (lançamentos automáticos) e compõe os custos de pessoal.

**Benefícios.** Menos planilhas e custos sob controle.

---

## 🧾 MÓDULO: HUB CONTÁBIL INTELIGENTE

**Rota:** `/hub-contabil`

**O que é.** A ponte organizada entre a empresa e a contabilidade.

**Para que serve.** Acabar com o caos do envio de documentos ao contador e manter impostos, guias e certidões em dia.

**Como utilizar (passo a passo).**
1. Abra **Hub Contábil** e navegue pelas abas: **Dashboard, Competências, Documentos, Guias, Conferência Cruzada, Certidões/CNDs, Histórico, Calendário**.
2. A cada mês, a **Competência** é aberta automaticamente. Em **Documentos**, faça o **upload** dos arquivos.
3. Use a **Conferência Cruzada** para validar valores (guias × folha).
4. Antes de enviar ao contador, resolva o **checklist** — ele **bloqueia o envio** se houver pendências.
5. Acompanhe validade de **CNDs** e prazos no **Calendário**.

**Onde essa ação impacta.**
- Documentos são **roteados automaticamente** (ex.: holerite → prontuário do colaborador; recibo de férias → período aquisitivo).
- Integra com admissões, férias e rescisões.

**Benefícios.** Contabilidade sem retrabalho e riscos fiscais monitorados.

---

# 🩺 SAÚDE, SEGURANÇA E COMPLIANCE (SST)

---

## 🩺 MÓDULO: ATESTADOS E AFASTAMENTOS

**Rota:** `/atestados`

**O que é.** O registro de atestados médicos e a gestão do ciclo de afastamento.

**Para que serve.** Controlar afastamentos com precisão e respeitar a privacidade de dados de saúde (LGPD).

**Como utilizar (passo a passo).**
1. Abra **Atestados** e clique em **Novo Atestado**.
2. **Deixe a IA preencher:** suba a **foto/scan** do atestado — o sistema reconhece nome, CRM, CID, datas e dias de afastamento.
3. Confira e complete: tipo, **CID** (apenas com autorização), grupo clínico e nexo ocupacional. Salve.
4. Para **afastamentos**, acompanhe o ciclo com **alertas de 15 e 30 dias**, vínculo com INSS (B91, B31…) e controle de **ASO de retorno** pendente.
5. Para **alterar**, reabra o registro e ajuste.

**Onde essa ação impacta.**
- Alimenta **Saúde Ocupacional**, alertas de saúde e (quando há acidente) o módulo de **Incidentes**.
- Documentos vão para o **prontuário**.

**Benefícios.** Menos digitação, mais precisão e controle fino de prazos.

---

## 🩺 MÓDULO: SAÚDE OCUPACIONAL (ASO)

**Rota:** `/saude-ocupacional`

**O que é.** O controle dos **Atestados de Saúde Ocupacional (ASO)** e da periodicidade dos exames.

**Para que serve.** Garantir que ninguém esteja com exame ocupacional vencido (exigência do PCMSO).

**Como utilizar (passo a passo).**
1. Abra **Saúde Ocupacional** — a lista traz os ASOs por tipo (Admissional, Periódico, Retorno, Mudança de Função, Demissional) e os **próximos vencimentos**.
2. Para **incluir**, clique em novo ASO, informe colaborador, tipo, data de emissão e resultado. Salve.
3. Use a **busca** por colaborador, profissional ou CID e priorize os que estão a vencer.

**Onde essa ação impacta.**
- Mantém a **aptidão** dos colaboradores em dia e alimenta a conformidade do PCMSO.

**Benefícios.** Nenhum exame vencido passa despercebido.

---

## 🔒 MÓDULO: COMPLIANCE SST

**Rota:** `/compliance-sst`

**O que é.** O auditor de conformidade em SST, assistido por IA.

**Para que serve.** Descobrir incoerências entre os documentos legais (PGR, PCMSO, LTCAT) antes da fiscalização.

**Como utilizar (passo a passo).**
1. Abra **Compliance SST**.
2. Suba/verifique os documentos **PGR, PCMSO e LTCAT**.
3. Rode a **análise por IA** — ela aponta riscos, omissões e possíveis **passivos jurídicos**, com critérios técnicos.
4. Acompanhe o monitoramento de eventos **eSocial** (S-2210, S-2220, S-2240).
5. Transforme cada achado em **ação** com um clique.

**Onde essa ação impacta.**
- Os diagnósticos viram itens no **Plano de Ação Global**.

**Benefícios.** Proteção jurídica proativa, sem substituir o profissional.

---

## 🦺 MÓDULO: EPIs

**Rota:** `/epis`

**O que é.** A gestão de EPIs: catálogo, estoque, entregas, conformidade e auditoria.

**Para que serve.** Provar que o EPI certo foi entregue à pessoa certa, com CA válido.

**Como utilizar (passo a passo).**
1. Abra **EPIs**. Monte o **catálogo** (Categorias → Tipos → Itens).
2. Para **dar entrada em estoque**, use entrada manual **ou** importe a **NF (XML)** — a IA vincula os itens ao catálogo.
3. Para **entregar um EPI**, use o fluxo em 4 etapas: **selecionar EPI → foto (prova de vida) → assinatura digital → recibo em PDF** (arquivado no prontuário).
4. Registre **devoluções** (manutenção ou descarte) quando houver.
5. Configure a **Matriz de Proteção** (EPIs obrigatórios por função) e acompanhe a validade do **CA** (alertas 30/90 dias).
6. Rode a **Auditoria Inteligente** para revisar conformidade e gerar ações.

**Onde essa ação impacta.**
- Baixa/entrada no **estoque** por empresa e local; recibo no **prontuário**.
- A auditoria gera **ações 5W2H** no **Plano de Ação**.

**Benefícios.** Estoque sob controle e entregas com prova jurídica.

---

## 🧠 MÓDULO: ERGONOMIA INTELIGENTE

**Rota:** `/ergonomia`

**O que é.** A análise ergonômica (NR-17) assistida por IA, com radares de risco humano.

**Para que serve.** Antecipar esgotamento e propor intervenções concretas.

**Como utilizar (passo a passo).**
1. Abra **Ergonomia** e inicie uma **AEP (Análise Ergonômica Preliminar)**.
2. Para a análise por vídeo, **envie o vídeo do posto** — a IA extrai os quadros para avaliação.
3. Preencha/valide os fatores de risco; a IA ajuda com as justificativas técnicas.
4. Acompanhe os **radares** de **Burnout**, **Boreout** e **IRP-S**.
5. Converta as recomendações em **ações** com um clique.

**Onde essa ação impacta.**
- As recomendações viram **ações 5W2H** no **Plano de Ação**.
- Cruza com **Incidentes** e **Psicossocial** (fatores recorrentes geram alertas).

**Benefícios.** Prevenção de afastamentos e laudos mais rápidos.

---

## 🚨 MÓDULO: INCIDENTES E ACIDENTES

**Rota:** `/incidentes-acidentes`

**O que é.** A central de registro, investigação e prevenção de eventos de segurança.

**Para que serve.** Cumprir a lei (CAT, eSocial, NR-01) e aprender com os eventos menores antes que virem acidentes graves.

**Como utilizar (passo a passo).**
1. Abra **Incidentes e Acidentes**.
2. Para registrar um **desvio** (condição/ato inseguro observado), clique em **Registrar Desvio** e informe tipo, local, categoria e potencial de risco.
3. Para registrar um evento, clique em **Registrar Evento** e escolha **Incidente** ou **Acidente**; preencha data, local, turno, envolvidos, categoria e descrição.
4. Se for **Acidente**, preencha gravidade, afastamento, atendimento e a **CAT** (número, data, PDF) — atenção ao prazo legal (1º dia útil).
5. Marque os **fatores ergonômicos/psicossociais** que contribuíram.
6. Conduza a **investigação** (a pasta de documentos é criada automaticamente para acidentes graves) e crie uma **Ação Vinculada**.
7. Atualize o **status** (Em Aberto → Em Análise → Ações em Andamento → Concluído) e acompanhe o **Dashboard** e o **Simulador FAP/RAT**.

**Onde essa ação impacta.**
- Cria pasta em **Documentos**, ações no **Plano de Ação** e evidências para **GRO/PGR**.
- Fatores repetidos disparam alertas em **Ergonomia** e **Psicossocial**.

**Benefícios.** Cultura de segurança madura, CAT no prazo e defesa robusta em fiscalização.

---

## 📊 MÓDULO: QUESTIONÁRIO PSICOSSOCIAL

**Rota:** `/psicossocial` (respostas em link público `/questionario/:token`)

**O que é.** A avaliação de riscos psicossociais (exigência da NR-01), com indicadores automáticos.

**Para que serve.** Medir o clima psicológico do trabalho de forma segura e anônima.

**Como utilizar (passo a passo).**
1. Abra **Psicossocial** e crie uma **Campanha** (defina público e periodicidade — mensal a anual).
2. **Envie o link** aos colaboradores (respostas anônimas por padrão; identificação é voluntária).
3. Acompanhe as respostas e, ao fechar, veja os **indicadores** automáticos: IRP-S, IBO-S, IBD-S, IREC-S, ICOP-S, INOT-S.
4. Se necessário, faça uma **reaplicação extraordinária** (após acidente, denúncia, reestruturação, etc.).

**Onde essa ação impacta.**
- Alimenta o **PGR psicossocial** e cruza com **Ergonomia** e **Incidentes**.
- Resultados são **imutáveis** para permitir comparação histórica.

**Benefícios.** Conformidade com a NR-01 e diagnóstico honesto do ambiente, com privacidade.

---

## 🏗️ MÓDULO: TERCEIROS

**Rota:** `/terceiros`

**O que é.** A gestão de empresas terceiras, seus trabalhadores e a documentação que libera (ou barra) o acesso.

**Para que serve.** Garantir que ninguém entre para trabalhar com documento vencido.

**Como utilizar (passo a passo).**
1. Abra **Terceiros** e **cadastre a empresa terceira**.
2. Vincule os **trabalhadores** a essa empresa.
3. Anexe **documentos e treinamentos** (ASO, PGR, PCMSO, NR-10, NR-35…) com suas validades.
4. Acompanhe o **status** de cada trabalhador: **Liberado ✅ / Restrito ⚠️ / Bloqueado 🚫** (atualizado automaticamente pela validade dos documentos).
5. Use o **Painel de Vencimentos** (60/30 dias) e emita a **Permissão de Trabalho (PT)** antes de liberar.

**Onde essa ação impacta.**
- Documento vencido muda o status para **Bloqueado** automaticamente, impedindo a liberação.

**Benefícios.** Menos risco de responsabilidade solidária e portaria segura.

---

# 🎯 DESENVOLVIMENTO E DESEMPENHO

---

## 📋 MÓDULO: AVALIAÇÕES DE DESEMPENHO

**Rota:** `/avaliacoes`

**O que é.** O sistema de avaliação estruturado em quatro dimensões, com apoio de IA.

**Para que serve.** Avaliar com justiça e consistência, ligando desempenho a competências e desenvolvimento.

**Como utilizar (passo a passo).**
1. Abra **Avaliações** e crie um **ciclo** (90°, 180° ou 360°), escolhendo o template e os pesos por dimensão.
2. Para cada colaborador, preencha os quatro blocos: **Entrega e Qualidade, Competências, Evolução e Aprendizado, Contexto de Trabalho**.
3. Use o **rascunho por IA** — ela reúne metas, feedbacks, ocorrências e treinamentos do período.
4. Ajuste as notas (**justificativa obrigatória** para notas extremas) e finalize.
5. Consulte a **matriz 9-Box** (Desempenho × Potencial).

**Onde essa ação impacta.**
- Resultados apoiam **PDI**, sucessão e decisões de desenvolvimento.

**Benefícios.** Avaliações mais justas, rápidas e baseadas em evidência.

---

## 🎯 MÓDULO: METAS

**Rota:** `/metas`

**O que é.** A gestão de metas em cascata, do estratégico ao individual.

**Para que serve.** Conectar a estratégia da empresa ao dia a dia de cada pessoa.

**Como utilizar (passo a passo).**
1. Abra **Metas** e escolha o nível: **Estratégica → Unidade → Setor → Individual**.
2. Para **incluir**, clique em **Nova Meta**, defina descrição, responsável, indicador e prazo (a IA ajuda a formular). Salve.
3. Para **desdobrar**, abra uma meta superior e use **Desdobrar** para criar metas dos níveis abaixo.
4. Faça **check-ins** periódicos e anexe **evidências** para atualizar o progresso.
5. Acompanhe o **Dashboard** por nível.

**Onde essa ação impacta.**
- Metas individuais aparecem para o colaborador e podem entrar nas **Avaliações**.

**Benefícios.** Alinhamento estratégico real e acompanhamento contínuo.

---

## 🎯 MÓDULO: PDI — PLANO DE DESENVOLVIMENTO INDIVIDUAL

**Rota:** `/pdi`

**O que é.** O plano de desenvolvimento de cada colaborador, com metas SMART.

**Para que serve.** Estruturar o crescimento das pessoas e registrar o compromisso.

**Como utilizar (passo a passo).**
1. Abra **PDI** e selecione o colaborador.
2. Para **incluir uma meta**, clique em nova meta — use a **geração SMART por IA** e ajuste. Salve.
3. Gere o **documento do PDI** (PDF) e envie o **link de assinatura** (WhatsApp) para o colaborador assinar.
4. Atualize o **progresso** ao longo do tempo.

**Onde essa ação impacta.**
- Vincula-se ao **Plano de Ação**; o documento assinado vai para o **prontuário**.

**Benefícios.** Desenvolvimento estruturado e formalizado sem burocracia.

---

## 📚 MÓDULO: APRENDIZADO E PAPÉIS

**Rota:** `/aprendizado-papeis`

**O que é.** A engenharia do trabalho: o que cada função faz, com quais competências, ferramentas, EPIs e procedimentos.

**Para que serve.** Registrar o conhecimento operacional em POPs e manuais de função.

**Como utilizar (passo a passo).**
1. Abra **Aprendizado e Papéis** e selecione a **função**.
2. Cadastre as **atividades** (ou use a **importação por áudio**: fale as atividades e a IA estrutura).
3. Preencha a **matriz de responsabilidade** e o **mapa de competências**; vincule os **EPIs** da função.
4. Gere um **POP** com IA (botões Detalhar/Simplificar/Checklist), revise e **publique**.
5. Gere o **Manual de Função** (PDF) e, se quiser, envie para **assinatura** do colaborador.

**Onde essa ação impacta.**
- POPs são arquivados em **Documentos (Processos)**; se a atividade mudar, o POP é marcado como **"Desatualizado"**.
- EPIs da função alimentam a **Matriz de Proteção** do módulo de EPIs.

**Benefícios.** Conhecimento retido na empresa e onboarding mais rápido.

---

## 🎓 MÓDULO: TRILHAS DE APRENDIZAGEM

**Rota:** `/trilhas`

**O que é.** As trilhas de capacitação por função/cargo, com gamificação.

**Para que serve.** Garantir a formação certa para cada papel — inclusive para terceiros.

**Como utilizar (passo a passo).**
1. Abra **Trilhas** (ou use **Nova Trilha** no cabeçalho).
2. Para **incluir**, defina o público (função/cargo), adicione conteúdos (11 tipos suportados) e publique.
3. Acompanhe o progresso, medalhas e ranking.
4. Para **terceiros**, gere o **link público** de acesso à trilha.

**Onde essa ação impacta.**
- Em desligamento, tarefas pendentes são canceladas; em mudança de cargo, conteúdos são reavaliados.
- Serve de **evidência de treinamento** para compliance.

**Benefícios.** Capacitação alinhada ao papel e engajamento pela gamificação.

---

## 🎓 MÓDULO: ACADEMIA (UNIVERSIDADE CORPORATIVA)

**Rota:** `/academia`

**O que é.** O ambiente de e-learning da empresa: cursos, aulas, pontos e conquistas.

**Para que serve.** Oferecer aprendizado contínuo, com catálogo, progresso e gamificação.

**Como utilizar (passo a passo).**
1. Abra **Academia** e navegue pelo **catálogo** (por categoria e nível), **Meus cursos**, **Favoritos** e destaques.
2. Para **fazer um curso**, abra o treinamento e assista às **aulas** — o progresso é salvo e você ganha **XP** e **badges**.
3. (Admin) Para **criar um treinamento**, use a área administrativa: monte as aulas e mude o status de **rascunho** para **publicado**.

**Onde essa ação impacta.**
- Cursos publicados ficam visíveis no catálogo; o progresso conta para XP e conquistas.

**Benefícios.** Cultura de aprendizado e engajamento.

---

# 💚 CULTURA, EXPERIÊNCIA E ESCUTA

---

## 💚 MÓDULO: BEM-ESTAR (GESTÃO DA FELICIDADE)

**Rota:** `/felicidade`

**O que é.** Um espaço de autopercepção do colaborador, guiado por sete eixos.

**Para que serve.** Um **"espelho guiado"** — autopercepção segura, **nunca para punição**.

**Como utilizar (passo a passo).**
1. Ao entrar no sistema, registre seu **humor do dia** no popup rápido (se ainda não registrou).
2. Abra **Bem-Estar** e explore os **sete eixos** (Autoconhecimento, Sentido & Propósito, Relações, Autonomia, Autorrealização, Atenção Plena, Gratidão).
3. Registre percepções na régua de 1 a 5.
4. (Gestores) Consulte apenas as **tendências agregadas** e alertas por eixo — **sem identificação individual**.

**Onde essa ação impacta.**
- Alimenta o radar de bem-estar e sinais que apoiam **Ergonomia** e **férias preventivas** (sem expor ninguém).

**Benefícios.** Sinais precoces de mal-estar coletivo, com privacidade absoluta.

---

## 🎉 MÓDULO: CULTURA E CELEBRAÇÕES

**Rota:** `/cultura-celebracoes`

**O que é.** A automação do reconhecimento e das datas importantes.

**Para que serve.** Fazer com que aniversários, tempo de casa e o Dia da Profissão nunca passem em branco.

**Como utilizar (passo a passo).**
1. Abra **Cultura e Celebrações** para ver as **próximas datas** e ações.
2. As **preferências de reconhecimento** de cada pessoa são coletadas no onboarding — ajuste quando necessário.
3. Para uma mensagem, use a **geração por IA** para personalizar o texto.

**Onde essa ação impacta.**
- Em desligamento, ações culturais futuras são canceladas; em mudança de cargo, são reavaliadas.

**Benefícios.** Reconhecimento consistente e clima positivo.

---

## 🏛️ MÓDULO: ESTRATÉGIA E GOVERNANÇA

**Rota:** `/estrategia`

**O que é.** A camada estratégica: cultura organizacional, análises e organograma.

**Para que serve.** Traduzir a identidade e a estratégia da empresa em documentos vivos e em ações.

**Como utilizar (passo a passo).**
1. Abra **Estratégia**. Em **Cultura**, defina Missão, Visão, Valores, Princípios e Comportamentos (a IA sugere textos) e gere o **Manual de Cultura** (PDF).
2. Preencha a **Análise SWOT**.
3. Na **Matriz Oceano Azul**, use a IA para transformar a SWOT em iniciativas (**Eliminar, Reduzir, Elevar, Criar**) e **criar ações em lote** no Plano de Ação.
4. Monte o **Organograma** visual.

**Onde essa ação impacta.**
- As iniciativas viram **ações 5W2H** (com prioridade GUT) no **Plano de Ação**.

**Benefícios.** Estratégia que sai do papel e vira ação priorizada.

---

## 📝 MÓDULO: FEEDBACK E OCORRÊNCIAS

**Rota:** `/feedback-ocorrencias`

**O que é.** O registro de feedbacks estruturados e de ocorrências disciplinares.

**Para que serve.** Reconhecer, alinhar e desenvolver — e formalizar ocorrências com respaldo.

**Como utilizar (passo a passo).**
1. Abra **Feedback e Ocorrências**.
2. Para um **feedback**, clique em novo, escolha o colaborador, o tipo (Positivo/Neutro/Negativo) e o foco; escreva uma nota rápida e use a **IA para transformar em texto profissional**. Salve.
3. Para uma **ocorrência/advertência**, registre o fato, anexe documentos e, se preciso, envie o **link externo seguro** para formalização (sem login).

**Onde essa ação impacta.**
- Feedbacks e ocorrências entram no histórico do colaborador e apoiam as **Avaliações**.

**Benefícios.** Feedback de qualidade sem esforço de redação e ocorrências com segurança jurídica.

---

## 📢 MÓDULO: OUVIDORIA

**Rota:** `/ouvidoria`

**O que é.** O canal de escuta formal — denúncias, elogios, sugestões e reclamações — com análise por IA.

**Para que serve.** Cumprir o canal de denúncias, proteger o denunciante e transformar manifestações em ações.

**Como utilizar (passo a passo).**
1. Abra **Ouvidoria**. Para **registrar** uma manifestação, escolha o tipo (Denúncia/Elogio/Sugestão/Reclamação), escreva e anexe arquivos (pode ser **anônima**).
2. (Gestão) Acompanhe a triagem: a IA faz **análise de sentimento**, classifica e prioriza.
3. **Responda** a manifestação e, quando couber, gere um **plano de ação** (a IA sugere ações 5W2H).

**Onde essa ação impacta.**
- Identidades anônimas ficam protegidas; ações corretivas vão para o **Plano de Ação** com rastreabilidade.

**Benefícios.** Confiança para reportar e resolução rastreável.

---

## 📰 MÓDULO: FEED (MURAL INTERNO)

**Rota:** `/feed`

**O que é.** O mural de comunicação interna da empresa.

**Para que serve.** Centralizar comunicados e avisos onde a equipe já trabalha.

**Como utilizar (passo a passo).**
1. Abra **Feed** para ler os comunicados.
2. (Perfis autorizados) Para **publicar**, clique em novo comunicado, escreva e publique.

**Onde essa ação impacta.**
- O comunicado fica visível para a equipe conforme a empresa ativa.

**Benefícios.** Comunicação alinhada e menos ruído em grupos de mensagens.

---

# 📊 GOVERNANÇA E OPERAÇÃO

---

## 📋 MÓDULO: PLANO DE AÇÃO GLOBAL

**Rota:** `/plano-acao`

**O que é.** O centro da governança: onde os achados de todos os módulos viram ações.

**Para que serve.** Garantir que **nenhum diagnóstico fique sem resposta** — cada ação com dono, prazo e evidência.

**Como utilizar (passo a passo).**
1. Abra **Plano de Ação**.
2. Para **incluir**, clique em **Nova Ação** e preencha o **5W2H** (O quê, Por quê, Onde, Quando, Quem, Como, Quanto). Defina a prioridade pela **matriz GUT**. Salve.
3. Use a **IA** para gerar/refinar a ação a partir do diagnóstico de origem.
4. Adicione **subtarefas** e atualize o progresso (ou conclua direto em 100%).
5. Acompanhe pelos **cards de estatística** e pela aba de **ações críticas** (atrasadas). Abra uma ação para ver o detalhe.

**Onde essa ação impacta.**
- Recebe ações vindas de Ergonomia, EPIs, Ouvidoria, Compliance, Incidentes, Estratégia e PDI.
- É a evidência central de que o diagnóstico virou execução.

**Benefícios.** Visibilidade total e priorização inteligente.

---

## 📁 MÓDULO: GESTÃO DOCUMENTAL

**Rota:** `/documentos`

**O que é.** O repositório organizado de documentos da empresa e dos colaboradores.

**Para que serve.** Ter cada documento no lugar certo, encontrável e vinculado ao seu contexto.

**Como utilizar (passo a passo).**
1. Abra **Documentos**. Há duas estruturas: **Prontuários** (por colaborador) e **Processos** (por função).
2. Navegue pela árvore **Empresa → Estabelecimento/Obra → Colaborador → Ano**.
3. Para **incluir**, entre na pasta e faça o **upload**; para **substituir**, envie a nova versão (fica no log de auditoria).

**Onde essa ação impacta.**
- Muitos documentos chegam **automaticamente** (recibos de EPI/férias, POPs, pastas de investigação de acidentes).

**Benefícios.** Documentação sempre organizada e pronta para auditoria.

---

## ✅ MÓDULO: PENDÊNCIAS

**Rota:** `/pendencias`

**O que é.** O painel único do que exige atenção — para cada perfil.

**Para que serve.** Ver, em um só lugar e por prioridade, o que precisa ser feito agora.

**Como utilizar (passo a passo).**
1. Abra **Pendências**.
2. Filtre pela aba do seu papel: **Todos, Gestor, RH, Colaborador**.
3. Clique em cada pendência (férias, documentos, ajustes de ponto, avaliações, desligamentos, afastamentos, alertas de saúde) para ir direto à tela onde ela é resolvida.

**Onde essa ação impacta.**
- Resolver a pendência atualiza o módulo de origem e some da lista.

**Benefícios.** Nada cai no esquecimento; o time trabalha por prioridade.

---

## 💬 ASSISTENTE VIRTUAL SST (CHAT IA)

**Onde:** botão flutuante em todas as telas.

**O que é.** Um especialista em SST disponível a qualquer momento.

**Para que serve.** Tirar dúvidas técnicas de segurança, ergonomia e saúde ocupacional na hora.

**Como utilizar (passo a passo).**
1. Clique no **botão do chat** (canto da tela).
2. Digite sua dúvida (ou use uma das **perguntas sugeridas**).
3. Leia a resposta — em português e **com citação das normas** (NRs, PGR, PCMSO, LTCAT…).

**Benefícios.** Conhecimento técnico acessível a todos, com decisões mais seguras.

---

## ⚙️ CONFIGURAÇÕES, MEU PLANO E SUPORTE

**Rotas:** `/configuracoes` · `/meu-plano` · `/suporte` · `/meu-perfil`

**O que é.** Os módulos de operação da conta.

**Como utilizar (passo a passo).**
1. **Configurações:** ajuste preferências do sistema e da empresa.
2. **Meu Plano:** consulte as informações da assinatura e os recursos contratados.
3. **Suporte:** abra a Central de Suporte para pedir ajuda dentro da plataforma.
4. **Meu Perfil:** atualize seus dados e preferências.

**Benefícios.** Autonomia para gerir a conta e ajuda sempre à mão.

---

# 🌐 ECOSSISTEMA YOUREYES

---

## 🌐 MARKETYE — REDE DE ESPECIALISTAS

**Rotas:** `/marketye` e portal do especialista

**O que é.** O marketplace que conecta empresas a profissionais e especialistas de SST, saúde e gestão de pessoas.

**Para que serve.** Encontrar e contratar o especialista certo com segurança.

**Como utilizar (passo a passo).**
1. Abra **MarketYE** e **busque** por especialistas.
2. (Especialista) Para se cadastrar, use o **cadastro de especialista**: envie documentos (RG, CPF/CNPJ, registro no conselho, diplomas), selfie de verificação e, se tiver, o **Atestado de Capacidade Técnica** (prioriza no ranking).
3. Gerencie o perfil e as oportunidades no **portal do especialista**.

**Onde essa ação impacta.**
- Profissionais com registro vencido são **bloqueados** automaticamente; a oferta fora do escopo do conselho é impedida.

**Benefícios.** Contratação segura e verificada.

---

## 🤝 PROGRAMA DE PARCEIROS

**Rotas:** `/parceiros` e portal do parceiro

**O que é.** O canal para parceiros que indicam e revendem o YourEyes.

**Para que serve.** Ampliar o alcance da plataforma por meio de uma rede de parceiros.

**Como utilizar (passo a passo).**
1. Acesse **Parceiros** e faça o **cadastro de parceiro**.
2. Assine o **contrato de parceria**.
3. Acompanhe sua atuação e seu perfil no **portal do parceiro**.

**Benefícios.** Crescimento por rede, com relação formalizada e espaço próprio.

---

# 🔒 SEGURANÇA E PRIVACIDADE (o que você precisa saber)

O YourEyes trata dados sensíveis (saúde, ergonomia, psicossocial) e foi construído com a **LGPD** no centro.

- **Cada empresa em seu espaço:** os dados de uma empresa nunca se misturam com os de outra.
- **Acesso por perfil:** você só vê e edita o que seu perfil permite.
- **Dados de saúde protegidos:** o **CID** só é registrado com autorização; o **Bem-Estar** nunca expõe respostas individuais aos gestores.
- **Trilha de auditoria:** o sistema registra quem fez o quê e quando.
- **Assinaturas digitais** com selo de data/hora em férias, PDI, EPIs, documentos e contratos.

**Boa prática:** confira sempre a **empresa ativa** antes de cadastrar, e nunca compartilhe seu acesso.

---

*YourEyes — Manual do Usuário.*
