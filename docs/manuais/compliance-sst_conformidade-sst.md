# Manual do módulo — Compliance SST

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e no mesmo tom e profundidade do módulo-piloto
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial e traz um marcador de
> print por tela que aparece na gravação.

- **Onde fica no menu:** seção **Saúde & Segurança → Compliance SST**
  (rota `/compliance-sst`).
- **Para quem é:** RH, Técnicos e Engenheiros de Segurança do Trabalho (SESMT),
  Medicina Ocupacional e Gestores responsáveis por conformidade.
- **Em uma frase:** importa os documentos legais de SST (**PGR, PCMSO, LTCAT** e
  outros), lê o conteúdo com **inteligência artificial**, aponta
  inconsistências e vencimentos, gera **planos de ação** e emite a **Ordem de
  Serviço (NR-1)** de cada colaborador.
- **Importante — o que o módulo NÃO é:** ele **não substitui** os profissionais
  legalmente habilitados **nem elabora** os documentos obrigatórios (PGR, PCMSO,
  LTCAT). Ele atua como **orquestrador da execução, auditor de coerência e
  gerador de inteligência preventiva** — esse aviso aparece fixo no topo da tela
  e deve ser respeitado na narração dos vídeos.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Fim da leitura manual de laudos.** Em vez de folhear um PGR de 80 páginas
  atrás de riscos e prazos, o RH **envia o PDF** e a IA extrai o inventário de
  riscos, a matriz de exames, os agentes nocivos e o plano de ação — sem
  digitação.
- **Nada vence sem aviso.** Cada documento importado entra num **calendário de
  vencimentos**. PGR, PCMSO e LTCAT têm validades diferentes; o sistema destaca
  o que está **vencido** e o que **vence em até 60 dias**, evitando lacunas de
  conformidade.
- **Achados viram ação.** A análise de IA aponta **inconsistências normativas**
  (por NR) e cada achado pode virar uma **ação 5W2H** no Plano de Ação, com
  origem rastreável até o documento que a gerou.
- **Ordem de Serviço automática (NR-1).** A OS individual, exigida pelo item
  1.4.1 "b" da NR-1 e pelo art. 157 da CLT, é **gerada a partir do PGR vigente**
  e enviada ao colaborador para **assinatura eletrônica**.
- **Coerência entre os documentos.** O sistema confronta o que está no PGR, no
  PCMSO e no LTCAT e sinaliza **divergências** — o tipo de lacuna que costuma
  virar passivo trabalhista e previdenciário.
- **Prova de diligência em fiscalização.** Documentos com histórico, ações com
  responsável e prazo, e OS assinadas formam a trilha que demonstra que a
  empresa cumpriu suas obrigações.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **PGR** | Programa de Gerenciamento de Riscos (NR-01) — o inventário de riscos da empresa e o plano de ação para tratá-los. |
| **PCMSO** | Programa de Controle Médico de Saúde Ocupacional (NR-07) — quais exames cada função faz e com que periodicidade. |
| **LTCAT** | Laudo Técnico das Condições Ambientais do Trabalho — avalia agentes nocivos para fins previdenciários (aposentadoria especial). |
| **Ordem de Serviço (OS)** | Documento individual, por colaborador, que informa os riscos do cargo e as medidas de proteção (NR-01 item 1.4.1 "b" / art. 157 CLT). |
| **Norma Regulamentadora (NR)** | As regras de SST do Ministério do Trabalho (NR-01, NR-07, NR-15, NR-16, NR-12…). |
| **5W2H** | Modelo de ação: *o quê, por quê, onde, quem, quando, como e quanto custa*. |
| **Achado** | Uma inconsistência ou pendência apontada pela análise de IA, com severidade **🔴 crítico**, **🟠 alerta técnico** ou **🟡 atenção**. |
| **Score de qualidade** | Nota (%) que a IA dá à completude dos dados extraídos de um documento. |
| **Vigência** | A data de validade do documento — base do calendário de vencimentos. |
| **eSocial (S-2210 / S-2220 / S-2240)** | Eventos de SST enviados ao governo (acidente, ASO/monitoramento e condições ambientais). |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **Empresa selecionada.** O módulo trabalha sempre no contexto da empresa
   ativa — confira que **Empresa Staging LTDA** está selecionada.
2. **Ter os documentos SST em arquivo** (PDF, DOCX ou DOC, até **50 MB**).
   O melhor resultado vem de **PDFs nativos** (texto selecionável); PDFs
   digitalizados (imagem) extraem com qualidade menor.
3. **Para a Ordem de Serviço:** é preciso ter um **PGR importado e com a análise
   de IA concluída**. Sem PGR válido para a empresa, a aba avisa e não gera OS.
4. **Para a OS:** colaboradores **ativos** cadastrados (o módulo puxa a lista de
   Admissões; desligados não aparecem).

> 📸 **PRINT 01 — Tela inicial do módulo**
> **Onde:** menu **Saúde & Segurança → Compliance SST** (abre na aba
> **Importação IA**).
> **O que precisa aparecer:** o título **"Compliance SST"** com o subtítulo
> "Governança, conformidade e inteligência legal…", o botão **Guia Rápido** no
> canto, o **aviso legal** em faixa âmbar (o módulo não substitui profissionais
> nem elabora PGR/PCMSO/LTCAT) e a **barra das 8 abas**.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**.
> **Ação filmada:** panorâmica lenta mostrando as abas e o aviso legal.

---

## 4. Mapa da tela (visão de 30 segundos)

No topo ficam o título **Compliance SST**, o botão **Guia Rápido** e uma faixa
**âmbar com o aviso legal**. Logo abaixo estão as **8 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Importação IA** | Envia o documento (PDF/DOCX) e a IA extrai os dados. É a aba de entrada. |
| **Documentos** | Lista tudo que foi importado, com status de vigência e as ações por documento. |
| **Ordem de Serviço** | Gera e envia a OS individual (NR-1) a partir do PGR vigente. |
| **Painel** | Indicadores + Calendário de Vencimentos. |
| **Alertas** | Achados de inconsistência da análise de IA, por severidade. |
| **Ações** | Ações identificadas nos documentos, prontas para ir ao Plano de Ação. |
| **eSocial** | Auditoria dos eventos SST no eSocial (**em breve**). |
| **Visão Psicossocial** | Resumo consolidado do módulo psicossocial. |

> 💡 A aba **Documentos** exibe um **contador** ao lado do nome com o total de
> documentos já importados — útil para mostrar volume no vídeo.

---

## 5. Passo a passo por fluxo

Os fluxos seguem a mesma ordem do **Guia Rápido** embutido (botão **Guia
Rápido** no topo) — vale abri-lo no tutorial como reforço.

> 📸 **PRINT 02 — Guia Rápido embutido**
> **Onde:** botão **Guia Rápido** (topo da página).
> **O que precisa aparecer:** o passo a passo lateral (O que é o módulo, Importe
> com IA, Revise e Consolide, Gerencie Documentos, Monitore o Painel, Acompanhe
> Alertas, Gerencie Ações, Documentos e Recursos), a barra de progresso e o
> botão para **baixar o Manual em PDF** na última etapa.
> **Ação filmada:** abrir o guia e avançar um ou dois passos com **Próximo**.

---

### Fluxo 1 — Importar um documento com IA

**Objetivo:** trazer um documento SST para dentro do sistema, com os dados já
estruturados.
**Benefício:** substitui a leitura e a digitação manual — a IA aplica regras de
extração específicas para cada tipo de documento.

O assistente tem **4 etapas** visíveis: **Upload + Tipo → Extração → Revisão →
Consolidação**.

1. Na aba **Importação IA**, clique em **Iniciar Importação**.
2. **Selecione o tipo** do documento (PGR, PCMSO, LTCAT, PPP, APR, NR-12, AEP,
   AET, Laudos, Avaliação Ambiental, Relatórios, Parecer Técnico ou Outros).
   Ao escolher, o sistema mostra **o que será importado** daquele tipo.
3. **Arraste ou selecione o arquivo** (PDF, DOCX ou DOC, até 50 MB) e clique em
   **Extrair Dados**.
4. Aguarde a **Extração**; depois **revise** os dados que a IA identificou
   (riscos, exames, agentes, responsáveis técnicos, datas) — você pode editar,
   adicionar ou remover itens.
5. **Consolide** para salvar tudo no sistema.

> 📸 **PRINT 03 — Upload + escolha do tipo**
> **Onde:** Importação IA → **Iniciar Importação**.
> **O que precisa aparecer:** o seletor **Tipo de Documento**, o quadro
> "O sistema irá importar…" e a área de arrastar arquivo.
> **Dados fictícios na tela:** tipo **PGR — Programa de Gerenciamento de
> Riscos**, arquivo **"PGR_Empresa_Staging_2026.pdf"** selecionado.
> **Ação filmada:** escolher **PGR**, soltar o arquivo e clicar em
> **Extrair Dados**.

> 📸 **PRINT 04 — Revisão dos dados extraídos**
> **Onde:** etapa **Revisão** do assistente.
> **O que precisa aparecer:** as seções extraídas (inventário de riscos, plano
> de ação, responsáveis técnicos) e as **marcas de confiança** (alta/média/
> baixa) da IA.
> **Dados fictícios na tela:** setor **Produção**, risco **"Ruído contínuo"**,
> responsável técnico **"Eng. de Segurança fictício — CREA-SP 000000"**.

> 📸 **PRINT 05 — Consolidação (sucesso)**
> **Onde:** etapa **Consolidação**.
> **O que precisa aparecer:** a mensagem **"Documento Importado com Sucesso!"**,
> o **Score de qualidade**, o resumo (riscos, ações, responsáveis, setores) e os
> **próximos passos recomendados**.
> **Dados fictícios na tela:** **PGR**, Score **82%**, **12 riscos**,
> **8 ações**, **4 setores**.

> 💡 A **classificação/seleção do tipo é decisiva**: ela orienta a IA a buscar
> os campos certos — **riscos** no PGR, **exames** no PCMSO, **agentes nocivos**
> no LTCAT. Escolher o tipo errado prejudica a extração.

---

### Fluxo 2 — Gerenciar documentos e vigências

**Objetivo:** ver tudo que foi importado e o estado de cada documento.
**Benefício:** um só lugar com o acervo SST, o status de vigência e o atalho
para revisar ou reanalisar cada documento.

1. Abra a aba **Documentos**.
2. **Busque** por tipo, arquivo, empresa emissora ou responsável.
3. Cada documento mostra: **tipo**, **status** (Vigente / Vence em Nd /
   Vencido), o selo **IA extraída** com o **score**, datas de emissão e
   vigência e um resumo (riscos / ações / responsáveis).
4. Nos botões da linha você pode **Revisar dados**, abrir a **Análise IA**
   narrativa (ícone de cérebro), **Baixar** o arquivo original ou **Excluir**.

> 📸 **PRINT 06 — Lista de documentos**
> **Onde:** Compliance SST → **Documentos**.
> **O que precisa aparecer:** a busca e alguns documentos com selos diferentes
> (um **Vigente**, um **Vence em 45d**, um **Vencido**) e o selo **IA extraída**
> com score.
> **Dados fictícios na tela:** **PGR** — Vigente — IA extraída **82%**;
> **PCMSO** — Vence em **45d**; **LTCAT** — **Vencido**.
> **Ação filmada:** digitar "PGR" na busca e passar o mouse pelos botões da
> linha.

> 💡 A exclusão pede **confirmação** e é definitiva. Para consultar o arquivo
> original, use **Baixar** — o sistema gera um link temporário do documento.

---

### Fluxo 3 — Análise de IA (Relatório de Conformidade)

**Objetivo:** auditar um documento e receber um parecer técnico legível.
**Benefício:** transforma o laudo em um relatório com riscos por categoria,
conformidade por NR, alertas e recomendações — exportável em PDF.

1. Na aba **Documentos**, clique no ícone de **cérebro** (Análise IA) da linha
   do documento.
2. Clique em **Iniciar Auditoria Técnica** — o relatório é escrito na tela em
   tempo real.
3. Ao terminar, clique em **Salvar Relatório** para guardá-lo no documento (é
   ele que alimenta as abas **Alertas** e **Ações**).
4. Use **Baixar PDF** para gerar o **Relatório de Conformidade SST** em arquivo.

> 📸 **PRINT 07 — Relatório de Conformidade SST**
> **Onde:** aba Documentos → ícone **Análise IA** → **Iniciar Auditoria
> Técnica**.
> **O que precisa aparecer:** o cabeçalho **"Relatório de Conformidade SST"** com
> os dados do documento e o texto do parecer (riscos por categoria, achados,
> recomendações) e os botões **Baixar PDF** e **Salvar Relatório**.
> **Dados fictícios na tela:** documento **PGR**, empresa **Empresa Staging
> LTDA**, data de hoje.
> **Ação filmada:** clicar em **Iniciar Auditoria Técnica** e mostrar o texto
> surgindo; ao fim, **Salvar Relatório**.

> 💡 **Salve o relatório.** É a análise salva que gera os **Alertas** e as
> **Ações** — sem salvar, essas abas continuam vazias para aquele documento.

---

### Fluxo 4 — Painel e Calendário de Vencimentos

**Objetivo:** ter a visão gerencial do compliance SST.
**Benefício:** em uma tela, quantos documentos estão vigentes ou vencidos, e o
que vence primeiro.

1. Abra a aba **Painel**.
2. Leia os **indicadores**: Documentos Vigentes, Documentos Vencidos, Análises
   IA Concluídas e Total de Documentos.
3. Consulte o **Calendário de Vencimentos**: os documentos ficam ordenados por
   validade, com bolinha **vermelha** (vencido), **âmbar** (vence em até 60
   dias) e **azul** (em dia).

> 📸 **PRINT 08 — Painel + Calendário de Vencimentos**
> **Onde:** Compliance SST → **Painel**.
> **O que precisa aparecer:** os quatro cartões de indicadores e o **Calendário
> de Vencimentos** com itens em cores diferentes.
> **Dados fictícios na tela:** **3 vigentes, 1 vencido, 2 análises concluídas,
> 4 no total**; no calendário, **LTCAT — Vencido**, **PCMSO — 45d**,
> **PGR — 210d**.

> 💡 Trate o Calendário de Vencimentos como rotina **semanal**: é a ferramenta
> de gestão proativa que evita a empresa ser pega com documento vencido.

---

### Fluxo 5 — Alertas: tratar achados e criar ações

**Objetivo:** revisar as inconsistências apontadas pela IA e transformá-las em
ação.
**Benefício:** as não-conformidades deixam de ficar escondidas no laudo e viram
tarefas com responsável e prazo.

1. Abra a aba **Alertas** (precisa de documentos com **análise salva**).
2. No topo, veja os totais: **Críticos**, **Alertas Técnicos** e **Achados
   Ativos**.
3. Expanda um documento para ler os achados, cada um com **severidade** e, quando
   houver, a **NR** relacionada.
4. Clique em **Criar ação** para gerar uma ação **5W2H** a partir do achado, ou
   em **✕** para **descartar** um achado irrelevante (dá para **restaurar**
   depois).

> 📸 **PRINT 09 — Aba Alertas**
> **Onde:** Compliance SST → **Alertas**.
> **O que precisa aparecer:** os cartões de contagem no topo, um documento
> expandido com achados **🔴 crítico** / **🟠 alerta** e o botão **Criar ação**.
> **Dados fictícios na tela:** documento **PGR**, achado crítico **"Ausência de
> medição de ruído — NR-15"**, **2 críticos / 3 alertas**.
> **Ação filmada:** expandir o PGR e clicar em **Criar ação** num achado
> crítico.

> 💡 Lacunas entre **PGR, PCMSO e LTCAT** são as mais perigosas — tratam-se de
> passivo em potencial. Priorize os achados **críticos**.

---

### Fluxo 6 — Ações: enviar para o Plano de Ação

**Objetivo:** aproveitar as ações que já estão escritas nos documentos.
**Benefício:** o sistema garimpa as frases que instruem uma ação (verbos no
infinitivo) e as leva ao Plano de Ação com a **origem** registrada.

1. Abra a aba **Ações**.
2. Expanda um documento e revise as ações identificadas (com **prazo** e
   **responsável** quando o texto traz).
3. Clique em **Importar** para enviar a ação ao **Plano de Ação** (origem
   "Compliance SST") ou em **Descartar** para tirá-la da lista.
4. Use **Plano de Ação** no rodapé para acompanhar tudo no módulo global.

> 📸 **PRINT 10 — Aba Ações**
> **Onde:** Compliance SST → **Ações**.
> **O que precisa aparecer:** o resumo (Docs com Ações / Ações Ativas), um
> documento expandido com ações e os botões **Importar** e **Descartar**.
> **Dados fictícios na tela:** ação **"Implementar programa de proteção
> auditiva no setor de Produção"**, origem **PGR**, prazo **90 dias**.
> **Ação filmada:** clicar em **Importar** e mostrar o aviso "Ação importada
> para o Plano de Ação".

> 💡 São listadas **apenas frases que instruem uma ação** (ex.: *implementar,
> reduzir, adequar*). Cabeçalhos e linhas de metadados são ignorados de
> propósito.

---

### Fluxo 7 — Ordem de Serviço (NR-1)

**Objetivo:** emitir a OS individual de cada colaborador e colher a assinatura.
**Benefício:** documento obrigatório gerado automaticamente do PGR vigente, sem
redigitar riscos por cargo.

1. Abra a aba **Ordem de Serviço**. Se não houver **PGR com análise concluída**,
   um aviso pede para importá-lo antes.
2. Preencha o **Responsável Técnico (SESMT)** — nome e registro profissional.
   Esses dados entram em todas as OS geradas (ficam salvos para a próxima vez).
3. Na lista de colaboradores ativos, veja o **status da OS** de cada um
   (Pendente, Rascunho, Aguardando, Vigente…).
4. Clique em **Gerar** — o sistema monta a OS a partir do PGR e abre a
   **pré-visualização**.
5. Escolha **Salvar como rascunho** ou **Salvar e enviar para assinatura** — no
   segundo caso o **link é copiado** para você enviar ao colaborador.

> 📸 **PRINT 11 — Ordem de Serviço: responsável e lista**
> **Onde:** Compliance SST → **Ordem de Serviço**.
> **O que precisa aparecer:** o cartão **Responsável Técnico (SESMT)** e a tabela
> de colaboradores com **Cargo/Setor**, **Status OS** e o botão **Gerar**.
> **Dados fictícios na tela:** responsável **"Eng. fictício — CREA-SP 000000"**;
> **Camila Duarte** (900.000.003-37) — Operadora de Produção — **Pendente**;
> **Diego Freitas** (900.000.004-18) — **Rascunho**.
> **Ação filmada:** preencher o responsável e clicar em **Gerar** na linha da
> Camila.

> 📸 **PRINT 12 — Pré-visualização e envio da OS**
> **Onde:** após **Gerar**, no modal de pré-visualização.
> **O que precisa aparecer:** o documento da OS com riscos do cargo e as medidas
> de proteção, e os botões **Salvar como rascunho** e **Salvar e enviar para
> assinatura**.
> **Dados fictícios na tela:** OS de **Camila Duarte**, cargo **Operadora de
> Produção**, riscos do setor de Produção.
> **Ação filmada:** clicar em **Salvar e enviar para assinatura** e mostrar o
> aviso "Link copiado!".

> 💡 Se o PGR mais recente estiver **vencido**, o sistema ainda deixa gerar a OS,
> mas exibe um aviso recomendando importar a versão atualizada.

---

### Fluxo 8 — eSocial e Visão Psicossocial

**Objetivo:** conhecer as duas abas complementares.
**Benefício:** deixa claro o roadmap (eSocial) e conecta o compliance à saúde
psicossocial.

- **eSocial:** a aba anuncia a **auditoria automática** dos eventos SST
  (S-2210, S-2220, S-2240) confrontados com os documentos legais. Hoje está como
  **"Em breve"** — não prometa a função como pronta nos vídeos.
- **Visão Psicossocial:** traz um **resumo consolidado** do módulo psicossocial
  dentro do compliance, para uma leitura conjunta de riscos.

> 📸 **PRINT 13 — Aba eSocial (em breve)**
> **Onde:** Compliance SST → **eSocial**.
> **O que precisa aparecer:** o cartão **"Auditoria eSocial — Eventos SST"** com
> a mensagem de que a função estará disponível em breve.
> **Uso:** opcional; serve para mostrar o roadmap.

> 📸 **PRINT 14 — Visão Psicossocial**
> **Onde:** Compliance SST → **Visão Psicossocial**.
> **O que precisa aparecer:** o resumo psicossocial consolidado exibido na aba.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Um PGR tem dezenas de páginas. Quem, de verdade, lê tudo antes do fiscal chegar?"* Abre com um laudo impresso grosso. | Imagem genérica de laudo |
| 8–22s | *"Com o YourEyes, você envia o documento e a IA lê por você: riscos, exames, agentes e prazos."* | **PRINT 03** (upload) + **PRINT 05** (consolidação) |
| 22–36s | *"Ela ainda audita a conformidade e aponta o que está fora da norma."* | **PRINT 07** (relatório) + **PRINT 09** (alertas) |
| 36–50s | *"Nada vence sem aviso — e cada falha vira uma ação com responsável e prazo."* | **PRINT 08** (calendário) + **PRINT 10** (ações) |
| 50–65s | *"E a Ordem de Serviço de cada colaborador? Gerada do PGR e enviada para assinar."* | **PRINT 11** + **PRINT 12** (OS) |
| 65–80s | *"YourEyes Compliance SST. Sua segurança do trabalho sob controle."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 6–9 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("agora eu importo…", "vamos revisar…").

1. **Abertura** — o que o módulo faz e o aviso legal (**PRINT 01**).
2. **Abrir o Guia Rápido** e mostrar o passo a passo embutido (**PRINT 02**).
3. **Importar um PGR** — tipo, upload, revisão e consolidação
   (**PRINT 03, 04, 05**).
4. **Gerenciar documentos** e ver vigências (**PRINT 06**).
5. **Rodar a Análise IA** e salvar o relatório (**PRINT 07**).
6. **Ler o Painel** e o Calendário de Vencimentos (**PRINT 08**).
7. **Tratar um alerta** e criar uma ação (**PRINT 09**).
8. **Importar ações** para o Plano de Ação (**PRINT 10**).
9. **Gerar e enviar uma Ordem de Serviço** (**PRINT 11, 12**).
10. **Mostrar eSocial (em breve) e Visão Psicossocial** (**PRINT 13, 14**).
11. **Encerramento** — lembrar do botão **Guia Rápido** e do **Manual em PDF**
    que ele oferece.

> 💡 Dica de gravação: siga a mesma sequência do **Guia Rápido** embutido — o
> roteiro foi montado na ordem dos passos dele.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Tela inicial (aviso legal + 8 abas)
- [ ] **PRINT 02** — Guia Rápido embutido
- [ ] **PRINT 03** — Upload + escolha do tipo
- [ ] **PRINT 04** — Revisão dos dados extraídos
- [ ] **PRINT 05** — Consolidação (sucesso + score)
- [ ] **PRINT 06** — Lista de documentos (vigências)
- [ ] **PRINT 07** — Relatório de Conformidade SST (Análise IA)
- [ ] **PRINT 08** — Painel + Calendário de Vencimentos
- [ ] **PRINT 09** — Aba Alertas (achados + Criar ação)
- [ ] **PRINT 10** — Aba Ações (Importar para o Plano)
- [ ] **PRINT 11** — Ordem de Serviço (responsável + lista)
- [ ] **PRINT 12** — Pré-visualização e envio da OS
- [ ] **PRINT 13** — Aba eSocial (em breve) — opcional
- [ ] **PRINT 14** — Visão Psicossocial

---

## 9. Erros comuns / dúvidas frequentes

- **"A aba Alertas (ou Ações) está vazia."** Falta a **Análise IA salva**. Vá em
  **Documentos**, abra a **Análise IA** do documento, rode e clique em **Salvar
  Relatório**.
- **"Não consigo gerar a Ordem de Serviço."** É preciso um **PGR importado e com
  análise concluída** para a empresa selecionada. Importe-o na aba **Importação
  IA** e aguarde a análise.
- **"O colaborador não aparece na lista da OS."** A lista traz apenas
  colaboradores **ativos** da empresa selecionada; desligados não entram.
- **"O arquivo não foi lido / deu erro na extração."** Pode ser um PDF pesado ou
  digitalizado. Envie um **PDF nativo** (texto selecionável) ou só as páginas do
  inventário de riscos e do plano de ação; o limite é **50 MB**.
- **"A extração veio incompleta."** Confira se o **tipo** selecionado bate com o
  documento — o tipo errado faz a IA procurar os campos errados.
- **"O módulo elabora o PGR/PCMSO para mim?"** **Não.** Ele importa, audita e
  organiza. A elaboração é de responsabilidade dos profissionais habilitados.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/compliance-sst_conformidade-sst.md` no projeto.
2. Confira, se quiser cruzar com a tela real, no **site de teste**
   (https://youreyes-dev.github.io/youreyesnovo/teste/) logado como **Marina
   Alves**, em **Saúde & Segurança → Compliance SST**: verifique que as 8 abas,
   o assistente de importação e a Ordem de Serviço correspondem aos fluxos e
   marcadores de print acima.
3. Aprovado o **formato e o conteúdo**, o mesmo padrão segue para os demais
   módulos, nos lotes que você priorizar.
