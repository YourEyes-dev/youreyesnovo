# Manual do Ponto — YourEyes

**Módulo de Controle de Jornada · referência de conformidade**
Base legal: CLT · Portaria MTP 671/2021 · TST (Súmulas) · LGPD · Lei 605/49 · Lei 5.889/73
Atualizado em 20/08/2026.

> Guia visual navegável (mesma matéria, para leitura/compartilhamento): publicado como
> Artifact na sessão. Este arquivo é a cópia versionada no projeto.

---

## 00 · Como o ponto mudou

O módulo Ponto deixou de ser um sistema que apenas **anota horários** e passou a ser um
sistema que **sustenta a jornada perante a lei** — do momento da batida até o valor que vai
para a folha e até o dossiê que se entrega numa fiscalização.

A revisão foi feita em **ondas**, cada uma cobrindo um risco jurídico de uma vez, sempre com
o mesmo método: a mudança nasce no **ambiente de teste**, é validada por uma pessoa e conferida
por uma bateria automática de casos legais — e só depois entra na fila de produção. Foram
**10 ondas** (0 a 9) mais duas correções, somando **45 entregas**.

Resultado atual da bateria de conformidade (120 casos): **113 aprovados · 1 vermelho
(rural, parado de propósito) · 6 de tela**.

### A regra de ouro dos ambientes

Nada é aplicado na **produção** automaticamente. O ambiente de teste recebe tudo pela esteira;
a produção só muda por **dois gestos manuais seus**: colar um script no banco real, ou clicar
em Publicar no aplicativo. Enquanto você não faz esses gestos, **a produção segue exatamente
como está**. Este manual descreve o comportamento **já validado no teste**.

---

## 01 · Como ler este guia

Cada regra mostra **o que mudou** e **como o sistema se comporta agora**, com o dispositivo
legal ao lado. Uma etiqueta indica o estágio:

- **Banco pronto** — a regra já funciona no coração do sistema (o banco). Vale mesmo antes de
  mexer em qualquer tela.
- **Depende de tela** — o banco já faz o trabalho; falta o botão/visualização no aplicativo,
  que entra por **Publicar no Lovable**.
- **Parado por decisão** — construído até certo ponto e deixado em espera de propósito (o rural).

Códigos como `PONTO-191` são os casos da bateria de conformidade — a régua que prova cada regra.

---

## 02 · Mapa das ondas

| Onda | Frente | Em uma linha |
|---|---|---|
| **0** | Travas legais de risco aberto | Leitura só do próprio ponto (LGPD), batida no futuro recusada, cadastros fora do piso legal barrados. |
| **1** | Identidade da marcação | NSR (numeração imutável, Portaria 671), vínculo/empresa na chave, versionamento de parâmetros e memória de cálculo. |
| **2** | Registro imutável de verdade | Cadeia de hash, relógio confiável, ponto "britânico", reabertura formal, e desconsiderar em vez de apagar. |
| **3** | Cálculo (onde está o dinheiro) | Tolerância cumulativa, jornada da escala, HE sem truncar, adicional noturno prorrogado, turno da virada. |
| **4** | Intervalo, descanso e DSR | Faixas de intervalo, supressão indenizatória, pré-assinalação, domingo em dobro, repouso semanal de 24h. |
| **5** | Banco de horas e escalas | Banco só com instrumento vigente, prazo, alertas, limite de 10h/dia, liquidação na rescisão, escala 12×36. |
| **6** | Fechamento e folha | Geração transacional, pendência e ciência bloqueiam o fechamento, pacote da folha com naturezas, fila com reenvio. |
| **7** | Arquivos legais e prova | Comprovante como documento, AEJ, importação de AFD que confere, certificado digital, dossiê de fiscalização. |
| **8** | Enquadramento e prevenção | Art. 62 e teletrabalho, descaracterização, obrigatoriedade por estabelecimento, REP-A, LGPD, Plano de Ação com IA. |
| **9** | Instrumento coletivo vigente | Apuração usa a CCT/ACT vigente na competência; vigilância de vencimento e sobreposição. |

Correções pós-bateria: **competência fechada bloqueia até a gestão** (PONTO-193) e a própria
**vigilância de vigência de CCT** (Onda 9, PONTO-386).

---

## A · A marcação e sua prova (ondas 0, 1, 2)

O primeiro dever de um ponto é ser **prova**. Se a batida pode ser apagada, editada ou
fabricada em série, o espelho não vale nada perante a Justiça.

### A batida nunca é apagada — é desconsiderada `PONTO-004`
**Antes:** a gestão podia excluir a marcação original; havia um e-mail real fixo no código como
exceção. **Agora:** a batida original **permanece sempre** no acervo e na cadeia de prova.
Corrigir é por **acréscimo** — a marcação é **desconsiderada** (com motivo e responsável) e sai
do cálculo, mas continua registrada. Apagar deixou de ser possível.
*Base:* Portaria 671 (veda apagar) · CLT art. 74 · TST Súmula 338. — **Banco pronto** (rótulo do
botão "Desconsiderar" por tela).

### NSR — numeração sequencial e imutável
Toda marcação nasce com um **NSR** (número que não se repete nem se reusa; as antigas foram
preenchidas em lotes). É a base de comprovante, cadeia de hash e AEJ.
*Base:* Portaria 671. — **Banco pronto**.

### Cadeia de hash encadeado `PONTO-191`
O hash de cada marcação **incorpora o da anterior**. Remover ou alterar uma linha **quebra a
cadeia**, e uma rotina detecta e alerta o RH — transforma o registro em prova (registro tipo 7
do AFD). As marcações já gravadas continuam válidas, sem quebra falsa.
*Base:* Portaria 671. — **Banco pronto**.

### Relógio confiável e origem da batida `378 · 379`
A marcação registra se nasceu **on-line ou off-line** e quando sincronizou (a hora da batida
segue oficial). Uma rotina compara o relógio do servidor com a **Hora Legal Brasileira**
(Observatório Nacional) e alerta se o desvio passar da tolerância.
*Base:* REP-P / Portaria 671. — **Banco pronto**.

### Ponto "britânico" detectado `PONTO-377`
O sistema mede a variação dos horários ao longo dos dias. Horários **idênticos por muitos dias**
são sinalizados ao RH — a Súmula 338, III do TST os considera **inválidos como prova**.
*Base:* TST Súmula 338, III. — **Banco pronto**.

### Leitura restrita, futuro recusado, cadastro no piso `Onda 0`
Colaborador comum lê **só o próprio ponto** (LGPD); marcação no **futuro é recusada**; o cadastro
barra tolerância acima do teto, CCT abaixo do piso de intervalo e "registro por exceção" sem
acordo. — **Banco pronto**.

> **Dois comportamentos que já estão certos — e são de tela.**
> **Não restringe horário de marcação** `PONTO-002`: nenhuma batida é recusada por estar "fora do
> horário" — a lei veda impedir a marcação. **Cerca virtual sinaliza, nunca bloqueia** `PONTO-006`:
> a localização qualifica a batida, jamais impede. Ambos já se comportam assim; falta o teste de
> tela e, na cerca, o aviso visível ao trabalhador.

---

## B · O cálculo da jornada (onda 3 + partes das 4/5)

É onde o ponto vira dinheiro. Todas as regras foram provadas com **regressão zero**.

### Tolerância cumulativa `041 · 042`
Os dois tetos do art. 58, §1º valem **juntos** — até **5 min por marcação** e **10 min no dia**.
Estourou qualquer um, conta-se **todo** o tempo que excede a jornada. Corrigiu-se o encaixe que
era o dobro do legal. *Base:* CLT art. 58, §1º · TST Súmula 366. — **Banco pronto**.

### Jornada da escala + HE sem truncar `091 · 092`
A jornada esperada vem da **escala do vínculo** (não mais 8h fixas), então a HE de quem tem
jornada menor deixa de sumir. A hora extra **não é mais cortada em 2h**: apura-se todo o tempo
além da jornada e o excesso **vira alerta** ao RH. *Base:* CLT art. 58/59 · CF art. 7º, XIII. —
**Banco pronto**.

### Adicional noturno prorrogado `PONTO-112`
Jornada cumprida toda no período noturno e **prorrogada além das 5h** mantém o adicional noturno
nas horas prorrogadas, em vez de cessar às 05:00. *Base:* TST Súmula 60, II. — **Banco pronto**.

### Turno da virada `PONTO-022`
A jornada que cruza a meia-noite pertence **inteira ao dia em que começou** — sem "falta fictícia"
no dia seguinte. Nenhum horário é alterado; muda só a ordem de leitura (cíclica).
*Base:* CLT art. 73. — **Banco pronto**.

### Domingo trabalhado em dobro `PONTO-130`
Domingo de **repouso** trabalhado sem folga compensatória é pago **em dobro por inteiro** — a
jornada normal inclusive —, não só o excedente. Domingo previsto na escala (6×1) não dobra.
*Base:* Lei 605/49, art. 9º · TST Súmula 146. — **Banco pronto**.

### DSR e repouso de 24h `132 · 133`
O repouso semanal entra no cálculo: **reflexo das HE** sobre o DSR (Súmula 172), **perda do DSR**
por falta injustificada, e detecção de **7 dias seguidos** sem 24h de descanso (art. 67), com
alerta. *Base:* Lei 605/49 · CLT art. 67 · Súmula 172. — **Banco pronto** (espelho/folha por tela).

### Escala 12×36 por ciclo `150 · 151`
O plantonista 12×36 é apurado **por ciclo**: plantão sem "extra" fictícia, folga **sem falta**,
feriado trabalhado **sem dobra indevida** (a 12×36 já compensa por lei). Só muda para quem é
12×36. *Base:* CLT art. 59-A. — **Banco pronto**.

> **Honestidade sobre o cálculo.** As funções desta onda deixam o resultado **correto para quando
> o fluxo de apuração as consumir**. Algumas ainda não são chamadas pelo fluxo vivo — corrigi-las
> agora garante que, ao ligar, o número já sai certo. Ligar cada cálculo ao espelho e à folha é
> trabalho de tela, item a item.

---

## C · Intervalos (onda 4, partes 1–3)

### Faixas de intervalo `PONTO-062`
O mínimo de intervalo segue a **faixa de jornada**: até 4h nenhum; 4–6h 15 min; acima de 6h
60 min. Base que evita cobrar "supressão" fictícia de jornada curta. *Base:* CLT art. 71. —
**Banco pronto**.

### Supressão de intervalo (50%) `060 · 061`
Pausa menor que a devida gera **indenização de 50% sobre os minutos suprimidos**, de natureza
**indenizatória** (sem reflexos). A supressão **total** deixa de passar invisível, com alerta.
*Base:* CLT art. 71, §4º (pós-2017). — **Banco pronto**.

### Pré-assinalação formal do intervalo `PONTO-064`
A jornada de **duas batidas** (sem marcar o almoço) só vale com o intervalo **pré-assinalado** —
declaração formal por escala ou colaborador, com vigência e lastro (CCT/acordo). O espelho mostra
de onde veio o intervalo. **Batida real sempre vence o declarado**; sem declaração, nada muda.
*Base:* TST Súmula 338, III · Portaria 671. — **Banco pronto** (cadastro/espelho por tela).

---

## D · Banco de horas (onda 5, partes 1–5)

### Só com instrumento vigente `170 · 354`
O banco só **credita/debita** quando há regime de compensação **vigente** para o vínculo (com
acordo/CCT quando exigido). Sem regime, o excedente **segue apurado no dia e vai para a folha** —
não some. *Base:* CLT art. 59, §§2º e 5º. — **Banco pronto**.

### Prazo de vencimento em cada crédito `PONTO-171`
Cada saldo nasce com **prazo de compensação** (6 meses no acordo individual, até 12 no coletivo).
Passou do prazo, vira **hora extra a pagar**. *Base:* CLT art. 59, §§5º/6º. — **Banco pronto**.

### Alertas de vencimento e teto `355 · 356`
O sistema avisa **antes** de o saldo vencer (com ação sugerida) e sinaliza quando o acúmulo passa
do **teto** configurado. *Base:* CLT art. 59, §5º. — **Banco pronto**.

### Limite de 10h/dia no regime `PONTO-172`
Em regime de compensação, o dia acima de **10 horas** é sinalizado como irregular — limite do
regime, independente do teto de 2h extras. *Base:* CLT art. 59, §2º. — **Banco pronto**.

### Liquidação do saldo na rescisão `PONTO-173`
O desligamento **conversa com o banco de horas**: o saldo positivo não compensado é apurado e
registrado para pagamento sobre a remuneração da rescisão. Um gatilho no desligamento dispara a
liquidação, sem nunca quebrar o desligamento. *Base:* CLT art. 59, §3º. — **Banco pronto**
(valor na folha de rescisão por tela).

---

## E · Fechamento e folha (ondas 6, 2, correções)

Fechar a competência congela a prova e libera o dinheiro. Passou a ter porteiros.

### Geração transacional dos espelhos `PONTO-194`
Os espelhos nascem numa **operação única (tudo-ou-nada)** — nunca mais metade com documento e
metade sem. Regenerar **preserva a ciência já dada**. *Base:* TST Súmula 338. — **Banco pronto**.

### Pendência crítica bloqueia o fechamento `PONTO-388`
Com ajuste pendente ou dia incompleto sem tratamento, o fechamento **é abortado** com a lista das
pendências. *Base:* CLT art. 74, §2º. — **Banco pronto** (lista no botão por tela).

### Espelho sem ciência bloqueia `PONTO-387`
O fechamento também barra **espelho sem ciência**. Espelho com **ressalva formal** não bloqueia.
*Base:* TST Súmula 338. — **Banco pronto**.

### Reabertura formal de competência `PONTO-358`
O erro descoberto após o fechamento tem saída **formal**: reabrir **exige motivo**, confere
alçada, **arquiva a versão** do espelho recebida pelo colaborador e registra a trilha. O
re-fechamento gera a próxima versão. *Base:* CLT art. 74. — **Banco pronto**.

### Competência fechada bloqueia até a gestão `PONTO-193`
**Correção:** rodando a bateria no teste com um usuário de gestão, descobriu-se uma "válvula" —
a gestão inseria marcação numa competência **já fechada** sem reabrir. **Agora:** competência
fechada **bloqueia todo mundo**, gestão inclusive. O único caminho é a **reabertura formal**.
*Base:* Portaria 671 · TST Súmula 338. — **Banco pronto**.

### Pacote da folha com naturezas corretas, e fila com reenvio `361 · 398`
A exportação para a folha é montada a partir da **apuração fechada**, com **naturezas separadas**:
**vencimento** (HE 50%/100%, adicional noturno, reflexo do DSR), **desconto** (faltas, atrasos,
perda de DSR) e **indenizatória** (supressão de intervalo, que **não é hora extra**). A fila tem
estados e **reenvio idempotente** — sem duplicar nem perder. *Base:* CLT art. 71, §4º. —
**Banco pronto** (geração do arquivo/envio por tela).

---

## F · Arquivos legais e fiscalização (onda 7)

### Comprovante como documento `380 · 381 · 359`
O comprovante virou o **recibo legal do trabalhador**: empregador, trabalhador, data/hora, **NSR**
e hash de integridade, arquivado, disponível em até 48h e **extraível por período pelo próprio
trabalhador** (restrito ao próprio CPF). Uma vigilância avisa quando o prazo de 48h está por
estourar. *Base:* Portaria 671 · REP-P. — **Banco pronto** (baixar/extrair na tela do trabalhador).

### AEJ — Arquivo Eletrônico de Jornada `PONTO-211`
Existe o AEJ, saída obrigatória do "programa de tratamento", pedida junto com o AFD. Gerado **a
partir da apuração fechada** em registros tipados, assinado por hash e arquivado, com extração
para download/fiscalização. *Base:* Portaria 671. — **Banco pronto**.

### Importação de AFD que confere `382·383·384·212`
A importação **confere no banco**: dígito verificador (CRC-16) de cada registro, cadeia SHA-256,
assinatura e **lacuna na sequência de NSR**. Arquivo com buraco é **recusado por inteiro** e vai
para quarentena; a mesma remessa não entra duas vezes. *Base:* Portaria 671 · AFD. —
**Banco pronto**.

### Gestão do certificado digital `PONTO-360`
Cadastro de certificado **ICP-Brasil** por empresa (só metadados de vigência — a chave privada
não fica no banco), escolha do **vigente** que assina o `.p7s`, e alerta **antes** de vencer.
Um certificado vencido não paralisa a emissão na hora da auditoria. *Base:* Portaria 671 ·
ICP-Brasil. — **Banco pronto**.

### Dossiê de fiscalização `392 · 393`
Um **empacotador** reúne AFD, AEJ, comprovantes, espelhos e trilha num pacote com **índice e
verificação de hashes**, e o **arquiva no módulo Documentos** (pasta, classificação, vínculo) —
sem caçar peça por peça diante do Auditor-Fiscal. *Base:* Portaria 671. — **Banco pronto**.

---

## G · Quem bate ponto (onda 8, partes 1–4; onda 9)

### Enquadramento do art. 62 e teletrabalho `373 · 374`
O vínculo tem enquadramento do **art. 62** (gestor, trabalho externo) e a modalidade de
**teletrabalho**. A dispensa só vale com inciso **e** modalidade que não seja teletrabalho por
**jornada** — só o teletrabalho por **produção/tarefa** dispensa. Quem é dispensado deixa de gerar
falta. *Base:* CLT art. 62 · Lei 14.442/2022. — **Banco pronto** (campos na ficha por tela).

### Controle de fato descaracteriza a dispensa `PONTO-375`
Um dispensado que, na prática, **acumula marcações reais** gera **alerta crítico** para
RH/Jurídico — é o que descaracteriza a dispensa e faz voltar as horas extras do período.
*Base:* CLT art. 62. — **Banco pronto**.

### Obrigatoriedade por estabelecimento `PONTO-370`
O controle é obrigatório acima de **20 trabalhadores por estabelecimento** (não pela empresa
inteira). O sistema conta por estabelecimento e **alerta** o obrigado que ainda não usa controle.
*Base:* CLT art. 74, §2º · Lei 13.874/2019. — **Banco pronto**.

### Sistema alternativo (REP-A) só com coletivo `PONTO-213`
Ativar o registro por **link/app (REP-A)** exige **autorização em convenção ou acordo coletivo** —
anexo do instrumento ou acordo coletivo vigente. Acordo individual não autoriza; sem lastro, a
ativação é recusada. *Base:* Portaria 671 · CLT art. 74, §4º. — **Banco pronto** (pedido do
documento por tela).

### Instrumento coletivo vigente na competência `PONTO-386`
A apuração usa o instrumento coletivo (CCT/ACT) **vigente na data apurada** — reapurar um mês
antigo aplica a convenção da época. Uma **vigilância** alerta instrumento a vencer, vencido, ou
duas vigências **sobrepostas** no mesmo escopo. *Base:* CF art. 7º, XXVI. — **Banco pronto**.

---

## H · Privacidade e prevenção (onda 8, partes 5–6)

### Trilha de acesso a dado sensível `PONTO-397`
**Ver** a selfie ou a geolocalização de uma marcação e **exportar** relatórios (AFD/AEJ) deixam
**rastro num log imutável** (append-only — recusa alteração e exclusão), com quem viu, escopo e
destinatário. *Base:* LGPD arts. 11 e 46. — **Banco pronto** (registro no clique por tela).

### Contenção de enumeração de CPF `PONTO-362`
O link compartilhado conta tentativas com CPFs diferentes e **bloqueia temporariamente** ao
estourar o limite, registrando o evento. Um acesso bem-sucedido zera o contador.
*Base:* LGPD arts. 46-49. — **Banco pronto**.

### Plano de Ação: alerta vira ação, com eficácia — a IA sugere, o humano decide `389·390·391`
O alerta do ponto (lacuna, HE habitual, banco a vencer, integridade, descaracterização…) **vira
ação 5W2H** no Plano de Ação, com origem navegável. Concluir a ação **valida a eficácia**: se a
ocorrência persiste, não há baixa cega — gera alerta de eficácia. A **IA analisa e sugere**
causa/impacto/ação, mas só avança por **decisão humana registrada**. Nada automatizado afeta
direito do trabalhador. *Base:* LGPD art. 20 · 5W2H/GUT. — **Banco pronto** (botões por tela).

---

## 03 · Situação da qualidade (bateria de 120 casos)

Placar atual no ambiente de teste: **113 aprovados · 1 vermelho · 6 de tela**. Os "de tela" são
verificados no navegador, não no motor de banco — por isso aparecem como "sem rotina" na bateria
de banco, **por desenho**.

| Caso de tela | Como está hoje | Falta |
|---|---|---|
| `PONTO-002` Não restringe horário | Comportamento correto | Só o teste de tela automatizado. |
| `PONTO-005` Comprovante após a batida | Banco pronto | Botão de baixar o comprovante na tela do trabalhador. |
| `PONTO-006` Cerca sinaliza, não bloqueia | Banco pronto | O aviso "fora da área" ao trabalhador. |
| `PONTO-195` Ciência do espelho com ressalva | Banco pronto | A tela de ciência e ressalva. |
| `PONTO-254` Selfie é dado comum | Decisão de produto | Decidir classificação/aviso (hoje já é foto comum). |
| `PONTO-363` Aviso de tratamento na tela | Decisão de produto | Definir e construir o aviso LGPD na tela. |

O único vermelho é o **PONTO-113 (rural)**, abaixo.

---

## 04 · O que ainda depende de tela (Publicar no Lovable)

Muita regra já está pronta no banco, faltando o botão/visualização no app:

- **Baixar/extrair o comprovante** na tela do trabalhador `005`.
- **Aviso da cerca virtual** ("fora da área", sem bloquear) `006`.
- **Ciência do espelho com ressalva** pelo colaborador `195`.
- **Aviso de tratamento de dados (LGPD)** na tela de marcação `363` (após decisão).
- **Rótulo "Desconsiderar"** (com motivo) no lugar de "Excluir" `004`.
- **Campos de enquadramento** (art. 62, teletrabalho, futuramente rural) na ficha.
- **Lista de pendências** no botão de fechar; **DSR** e **pré-assinalação** no espelho;
  **geração/envio do arquivo da folha**; **botões de AEJ, dossiê, certificado**;
  **registro de acesso** no clique; **ação/IA** do Plano de Ação.

Regra da casa: **todo teste de tela nasce de um caso documentado**. Esses itens já estão
documentados — viram teste de tela automatizado quando cada tela for construída.

---

## 05 · O rural (parado por decisão) — `PONTO-113`

O único vermelho da bateria. Não foi implementado **de propósito**: só compensa quando houver
cliente do agronegócio. Enquanto nenhum vínculo for marcado como rural, **todo o cálculo continua
urbano como hoje** — risco zero para quem não é do agro.

O regime rural (Lei 5.889/73) muda **três eixos ao mesmo tempo**:

| Eixo | Urbano (hoje) | Rural |
|---|---|---|
| Janela noturna | 22h–5h | Lavoura 21h–5h · Pecuária 20h–4h |
| Adicional noturno | 20% | 25% |
| Hora noturna | ficta (52min30s) | cheia (60 min), sem ficta |

Fazer funcionar exige: um **campo de regime** no vínculo, a **apuração** aplicando os três eixos
quando rural (o motor já sabe parametrizar janela/percentual/ficta), um caso de prova, e um campo
de tela para o RH marcar quem é rural. *Base:* Lei 5.889/1973, art. 7º.

---

## 06 · Base legal (o que a lei pede → o que o sistema faz)

| Dispositivo | O que o sistema faz agora |
|---|---|
| CLT art. 58, §1º · Súmula 366 | Tolerância cumulativa (5 min/marcação e 10 min/dia); estouro conta o total. |
| CLT art. 59 e §§ | HE sem truncar; banco só com regime vigente, prazo, limite de 10h/dia, liquidação na rescisão. |
| CLT art. 59-A | Escala 12×36 por ciclo, sem extra/falta fictícias e sem dobra de feriado. |
| CLT art. 62 · Lei 14.442/22 | Enquadramento e dispensa; teletrabalho por jornada segue controlado; controle de fato descaracteriza. |
| CLT art. 67 · Lei 605/49 | Repouso de 24h vigiado; DSR com reflexo de HE e perda por falta; domingo em dobro. |
| CLT art. 71 | Faixas de intervalo; supressão indenizatória de 50%; pré-assinalação formal. |
| CLT art. 73 · Súmula 60 | Turno da virada no dia de início; adicional noturno prorrogado. |
| CLT art. 74, §§2º/4º · Lei 13.874/19 | Obrigatoriedade por estabelecimento (>20); REP-A só com coletivo; não se apaga marcação. |
| CF art. 7º, XIII e XXVI | Jornada da escala respeitada; instrumento coletivo vigente na competência. |
| TST Súmula 338 | Ponto "britânico" inválido; espelho com ciência; geração íntegra dos espelhos. |
| Portaria MTP 671/2021 | NSR, comprovante REP-P, AEJ, AFD que confere, certificado ICP-Brasil, dossiê, relógio legal. |
| LGPD (arts. 5, 6, 9, 11, 18, 20, 46-49) | Leitura restrita ao próprio ponto; trilha de acesso; contenção de enumeração; IA sugere, humano decide. |
| Lei 5.889/73 (rural) | *Condicional* — escopo medido, parado até haver cliente do agro. |

---

## 07 · Como conferir e o que vem a seguir

Tudo o que este manual descreve está **validado no ambiente de teste**. Para ver o placar
**113 · 1 · 6** com os próprios olhos:

- Site de teste: https://youreyes-dev.github.io/youreyesnovo/teste/
- Menu **Administração → QA → Runner** → bateria **Ponto**.

**Produção.** Nada foi aplicado na produção. As entregas estão na fila do roteiro
(`docs/ROTEIRO_PRODUCAO_PONTO.md`), na ordem certa. Quando aprovado, cada pacote é colado no banco
real por um gesto seu, e as telas entram por Publicar no aplicativo. Até lá, a produção segue
exatamente como está.

**Próximos passos possíveis:**
1. Aprovar a implantação em produção, na ordem do roteiro;
2. Construir as telas pendentes (comprovante, ciência, cerca, aviso LGPD…);
3. Decidir a triagem dos casos `254` e `363`;
4. Retomar o rural quando entrar um cliente do agro.
