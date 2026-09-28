# Manual do módulo — Controle de Ponto Eletrônico

> **Módulo-piloto** — escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md).
> Serve de roteiro para os vídeos comercial e tutorial e de referência de
> profundidade para os demais manuais.

- **Onde fica no menu:** seção **Jornada & Rotina → Ponto**.
- **Para quem é:** RH, Departamento Pessoal (DP) e Gestores.
- **Em uma frase:** registra, audita e fecha a jornada dos colaboradores CLT
  com selfie, geolocalização e cálculo automático, em conformidade com a
  **Portaria 671/2021 do MTP** (REP-C / REP-P).
- **Importante:** o ponto é **exclusivo de vínculos CLT**. PJ, pró-labore e
  prestadores de serviço (terceiros) não aparecem aqui de propósito.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Segurança jurídica contra ações trabalhistas.** Cada marcação guarda
  data/hora, **GPS**, **selfie** e um **hash** que prova que o registro não foi
  adulterado. Nada é apagado — correções ficam registradas por cima do original,
  com autor e motivo. Numa fiscalização ou processo, o histórico é a prova.
- **Conformidade com a Portaria 671/2021.** O sistema é um **REP-C** (registro
  por programa) e gera os arquivos oficiais **AFD/AEJ** exigidos pelo Ministério
  do Trabalho.
- **Fim da planilha e do cálculo manual.** Atraso, falta, hora extra, adicional
  noturno, intervalo e **banco de horas** são calculados sozinhos, comparando o
  que foi batido com a **escala** de cada pessoa.
- **Ponto de qualquer lugar.** Quem está em campo, obra ou home office bate
  ponto pelo próprio celular via **link REP-P**, com validação por código no
  WhatsApp — mesmo nível de auditoria do registro interno.
- **Fechamento que trava o mês.** Depois de conferido e fechado, o período não
  muda mais sem reabertura formal — os dados que vão para a folha ficam
  íntegros.
- **Alertas antes do problema.** Atrasos recorrentes, faltas sem justificativa e
  extras acima do limite viram alertas, que podem virar **Plano de Ação 5W2H**.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **REP-C** | Registro Eletrônico de Ponto por **Programa** — a marcação feita aqui no sistema, pelo navegador. |
| **REP-P** | A mesma marcação, mas feita **pelo celular do colaborador** via link externo (campo/home office). |
| **NSR** | Número Sequencial de Registro — o "número do comprovante" de cada batida. |
| **Espelho de ponto** | A visão do dia: quem bateu, a que horas, o total e o saldo. É o "extrato" da jornada. |
| **Escala** | O horário esperado de cada pessoa (ex.: 08:00–12:00 e 13:00–17:00, 5x2). É a régua para medir atraso/extra. |
| **Apuração** | O cálculo do saldo — banco de horas, extras, faltas — a partir do batido x escala. |
| **Ajuste** | Uma correção (inclusão, correção ou justificativa) que passa por aprovação. |
| **Banco de horas** | O saldo acumulado: horas a mais (crédito) e a menos (débito) a compensar. |
| **AFD / AEJ** | Arquivos oficiais da Portaria 671 (fiscais) que o sistema exporta. |
| **DSR** | Descanso Semanal Remunerado — o domingo (art. 67 da CLT). O sistema marca com um selo. |
| **Hash** | A "impressão digital" da marcação — garante que ela não foi alterada. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **A empresa precisa ter o controle de ponto ligado.** Isso é feito no
   cadastro da empresa, aba **Jornada e Turnos → "Utiliza controle de ponto"**.
   Sem isso, o módulo abre vazio com um aviso (é proposital — evita gerar falta
   indevida).
2. **Colaboradores CLT ativos cadastrados.**
3. **Pelo menos uma escala criada e atribuída** — sem escala, o sistema não sabe
   calcular atraso, falta ou hora extra.

> 📸 **PRINT 01 — Estado vazio (opcional, só para explicar o pré-requisito)**
> **Onde:** módulo Ponto com nenhuma empresa com ponto ligado.
> **O que precisa aparecer:** o cartão "Nenhuma empresa utiliza o Ponto ainda"
> com a instrução de ligar a opção na aba Jornada e Turnos.
> **Uso:** só no tutorial, para mostrar o ponto de partida. Pode ser pulado no
> comercial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Ponto**, o topo mostra o título **"Controle de Ponto Eletrônico"**,
o selo **"Portaria 671 MTP"** e dois botões: **Guia Rápido** e **Solicitar
Ajuste**. Se a empresa tiver mais de uma unidade com ponto, aparece o **seletor
de empresa**.

Abaixo ficam as **7 abas** do módulo:

| Aba | Para que serve |
|---|---|
| **Visão Geral** | Painel com indicadores do dia (presentes, atrasos, faltas, escore). |
| **Espelho** | O dia a dia da jornada: marcações, status e saldo por colaborador. |
| **Escalas** | Cadastro dos horários esperados (5x2, 6x1, 12x36, personalizada). |
| **Apuração** | Banco de horas, fechamento mensal e folha. |
| **Ajustes** | Solicitação e aprovação de correções (com contador de pendências). |
| **Compliance** | Alertas, REP-C (AFD/AEJ), certificado, pré-assinalação, dossiê. |
| **Configurações** | Tolerâncias, hora extra, feriados, acordos, CCT, links. |

> 📸 **PRINT 02 — Tela inicial do módulo**
> **Onde:** menu **Jornada & Rotina → Ponto**, aba **Visão Geral**.
> **O que precisa aparecer:** título, selo "Portaria 671 MTP", as 7 abas e os
> cartões de indicadores do dia.
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**; indicadores
> como "12 presentes, 2 atrasos, 1 falta".
> **Ação filmada:** panorâmica lenta da tela, mostrando as abas.

---

## 5. Passo a passo por fluxo

Os fluxos abaixo seguem a mesma ordem do **Guia Rápido** embutido no sistema
(botão "Guia Rápido" no topo) — vale abri-lo no vídeo tutorial como reforço.

### Fluxo 1 — Configurar o módulo

**Objetivo:** definir as regras que valem para todas as marcações.
**Benefício:** as regras da empresa (e da CCT) passam a ser aplicadas sozinhas.

1. Abra a aba **Configurações**.
2. Defina a **tolerância de atraso** (ex.: 10 minutos).
3. Configure os **percentuais de hora extra** (50% / 100%) e o **adicional
   noturno**.
4. Ative a **selfie obrigatória** e o **raio de geolocalização** (recomendado:
   **50 m**).
5. **Salve** — as regras passam a valer para as marcações novas.

> 📸 **PRINT 03 — Aba Configurações**
> **Onde:** Ponto → **Configurações**.
> **O que precisa aparecer:** campos de tolerância, hora extra, adicional
> noturno, selfie obrigatória e raio de geolocalização.
> **Dados fictícios na tela:** tolerância **10 min**; extra **50%/100%**;
> adicional noturno **20%**; raio **50 m**; selfie **ativada**.

> 💡 As regras vêm no padrão CLT, mas devem ser revisadas conforme a **CCT** da
> categoria. Anexe a convenção vigente na aba **CCT** (dentro de Configurações).

---

### Fluxo 2 — Cadastrar as escalas

**Objetivo:** dizer ao sistema o horário esperado de cada pessoa.
**Benefício:** sem escala não há como medir atraso, falta ou extra — este é o
alicerce de todo o cálculo.

1. Vá em **Escalas → Nova Escala**.
2. Preencha **nome**, **tipo** (5x2, 6x1, 12x36, personalizada) e a jornada
   semanal.
3. Adicione os **blocos diários** (ex.: **07:54–12:00** e **13:30–18:00**).
4. Configure **recorrências mensais** se houver (ex.: 1º sábado do mês,
   08:00–12:00).
5. **Atribua** a escala aos colaboradores, com **data de início**.

> 📸 **PRINT 04 — Lista de escalas**
> **Onde:** Ponto → **Escalas**.
> **O que precisa aparecer:** a lista com uma escala já criada.
> **Dados fictícios na tela:** escala **"Administrativo 5x2 — 08h às 17h"**,
> **20 colaboradores atribuídos**.

> 📸 **PRINT 05 — Cadastro de nova escala (blocos)**
> **Onde:** Escalas → **Nova Escala**.
> **O que precisa aparecer:** o formulário com os blocos de horário e o tipo.
> **Dados fictícios na tela:** nome **"Produção 6x1"**, blocos **07:00–11:00** e
> **12:00–16:00**, tipo **6x1**.

> 💡 Escala já atribuída **não pode ser excluída** (preserva o histórico) —
> nesse caso, **inative**. Só é possível excluir escala que nunca foi usada.

---

### Fluxo 3 — Registrar o ponto (REP-C, com selfie e GPS)

**Objetivo:** bater o ponto pelo sistema.
**Benefício:** cada batida nasce auditável — GPS, selfie e hash — gerando o
comprovante (NSR) que o colaborador pode baixar quando quiser.

1. Clique em **Registrar Ponto** no topo da página.
2. Selecione o **colaborador** — o sistema já sugere o **próximo tipo**
   (entrada → saída almoço → retorno → saída), pela alternância do dia.
3. **Permita a localização** quando o navegador pedir.
4. **Capture a selfie** (se a configuração exigir).
5. **Confirme** — o registro é gravado com timestamp, GPS e hash.

> 📸 **PRINT 06 — Modal "Registrar Ponto"**
> **Onde:** botão **Registrar Ponto** (topo).
> **O que precisa aparecer:** seletor de colaborador, o tipo sugerido, o mapa/
> endereço da geolocalização e a área de captura de selfie.
> **Dados fictícios na tela:** colaboradora **Camila Duarte** (900.000.003-37),
> tipo sugerido **"Entrada"**, endereço **"Av. Paulista, 1000 — São Paulo/SP"**,
> distância **12 m (dentro da cerca)**.
> **Ação filmada:** selecionar a Camila, capturar a selfie, clicar em Confirmar.

> 📸 **PRINT 07 — Comprovante da marcação (NSR)**
> **Onde:** após confirmar, ou em **Meus Comprovantes** (visão do colaborador).
> **O que precisa aparecer:** o comprovante com NSR, data/hora, tipo e hash.
> **Dados fictícios na tela:** NSR **000123**, **28/09/2026 08:02**, Entrada.

> 💡 Para quem está fora do escritório, use o **link REP-P** (Fluxo 8) — o
> colaborador bate pelo próprio celular.

---

### Fluxo 4 — Ler o espelho do dia

**Objetivo:** acompanhar a jornada dia a dia.
**Benefício:** numa tela o RH vê quem bateu, o total trabalhado, o status e o
saldo do dia — com selos automáticos (Atestado, Férias, Feriado, DSR).

1. Abra a aba **Espelho**.
2. Navegue pelos dias com **◀ / ▶** ou escolha a data no **calendário**; o botão
   **Hoje** volta para o dia atual.
3. Filtre por **status** (Regular, Atraso, Falta, Incompleto, Justificado),
   **departamento** ou busque por **nome/CPF**.
4. Cada linha mostra: **marcações do dia**, **nº de registros**, **total**,
   **status** e **saldo do dia**.

> 📸 **PRINT 08 — Espelho do dia**
> **Onde:** Ponto → **Espelho**.
> **O que precisa aparecer:** a navegação de data, os filtros e a tabela com
> várias linhas de colaboradores e selos de status diferentes.
> **Dados fictícios na tela:**
> - **Camila Duarte** — 08:02 / 12:00 / 13:01 / 17:03 — 4 registros — 7h58 —
>   **Regular** — saldo **−02min**.
> - **Diego Freitas** — 09:15 / … — **Atraso**.
> - **Eduarda Lima** — selo **Atestado** (violeta).
> - Linha de domingo mostrando o selo **DSR**.
> **Ação filmada:** clicar em ◀ para o dia anterior e aplicar o filtro "Atraso".

> 💡 O espelho mostra **exatamente o que a Apuração calcula** (mesma fonte de
> cálculo do banco de horas) — não há divergência entre as telas.

---

### Fluxo 5 — Solicitar e aprovar ajustes

**Objetivo:** corrigir esquecimentos e justificar ausências, sem apagar nada.
**Benefício:** correção com trilha de auditoria — o original permanece, o ajuste
entra por cima com responsável, data e motivo.

**Solicitar (colaborador ou RH):**
1. Clique em **Solicitar Ajuste** no topo.
2. Escolha o **tipo**: **Inclusão** (esqueceu de bater), **Correção** (hora
   errada) ou **Justificativa** (falta/abono).
3. Informe **data**, **marcação**, **hora solicitada** e **motivo**; anexe
   comprovantes se houver.

**Aprovar (gestor):**
4. Na aba **Ajustes**, veja os **pendentes** (o número no selo da aba mostra
   quantos dias aguardam).
5. **Aprove** ou **rejeite** — ao aprovar, o dia é **recalculado
   automaticamente**.

> 📸 **PRINT 09 — Modal "Solicitar Ajuste"**
> **Onde:** botão **Solicitar Ajuste** (topo).
> **O que precisa aparecer:** o seletor de tipo (Inclusão/Correção/
> Justificativa), data, marcação, hora e motivo.
> **Dados fictícios na tela:** colaboradora **Camila Duarte**, tipo
> **Inclusão**, data **26/09/2026**, marcação **Saída**, hora **17:00**, motivo
> **"Esqueci de registrar a saída"**.

> 📸 **PRINT 10 — Aba Ajustes com pendências**
> **Onde:** Ponto → **Ajustes**.
> **O que precisa aparecer:** o selo vermelho com o contador na aba e a lista de
> pendentes com os botões **Aprovar / Rejeitar**.
> **Dados fictícios na tela:** contador **3**; solicitação da Camila destacada.
> **Ação filmada:** clicar em **Aprovar** e mostrar o recálculo do dia.

> 💡 O sistema **nunca apaga** a marcação original — a rastreabilidade total é
> justamente o que protege a empresa numa auditoria.

---

### Fluxo 6 — Banco de horas

**Objetivo:** acompanhar crédito, débito e compensações.
**Benefício:** saldo calculado a cada marcação encerrada; alerta antes do
vencimento do prazo legal.

1. Abra **Apuração → Banco Horas**.
2. Veja o **saldo atual** por colaborador.
3. Filtre por **período, departamento ou status** (positivo/negativo).
4. Lance **compensações manuais** quando houver folga acordada.
5. **Exporte o extrato** individual para o colaborador.

> 📸 **PRINT 11 — Banco de horas**
> **Onde:** Ponto → **Apuração → Banco Horas**.
> **O que precisa aparecer:** a lista com saldos positivos e negativos e o
> filtro de período.
> **Dados fictícios na tela:** **Bruno Carvalho +06h30**, **Camila Duarte
> −01h15**, período **Setembro/2026**.

> 💡 O saldo respeita o limite legal (**6 meses** para acordo individual,
> **1 ano** para acordo coletivo) e avisa quando se aproxima do vencimento.

---

### Fluxo 7 — Fechamento mensal

**Objetivo:** travar o mês para integrar à folha.
**Benefício:** depois de fechado, nada muda sem reabertura formal — os dados da
folha ficam íntegros.

1. Abra **Apuração → Fechamento**.
2. Resolva as **pendências** sinalizadas (ajustes, faltas sem justificativa,
   marcações inconsistentes).
3. Confira o **resumo** de horas, extras e adicional noturno.
4. Clique em **Fechar período** — o sistema bloqueia edições.
5. Os dados ficam disponíveis na aba **Folha** para integração.

> 📸 **PRINT 12 — Fechamento mensal**
> **Onde:** Ponto → **Apuração → Fechamento**.
> **O que precisa aparecer:** a lista de pendências, o resumo do mês e o botão
> **Fechar período**.
> **Dados fictícios na tela:** competência **Setembro/2026**, **0 pendências**,
> total de extras **18h20**, botão **Fechar período** habilitado.

> 💡 Feche sempre na mesma data do mês (ex.: dia 25 → 25). Isso facilita
> auditoria e mantém o ritmo da folha.

---

### Fluxo 8 — Links externos (REP-P) para campo e home office

**Objetivo:** deixar o colaborador bater ponto pelo próprio celular.
**Benefício:** cobertura de quem está fora, com o mesmo nível de auditoria.

1. Abra **Configurações → Links**.
2. Gere um **link individual** ou por equipe.
3. Compartilhe por **WhatsApp, e-mail ou QR Code**.
4. O colaborador valida com um **código OTP enviado por WhatsApp**.
5. A marcação entra com **GPS, selfie e hash** — igual ao REP-C.

> 📸 **PRINT 13 — Geração de link REP-P**
> **Onde:** Ponto → **Configurações → Links**.
> **O que precisa aparecer:** o link/QR Code gerado e a validade configurável.
> **Dados fictícios na tela:** link para **Diego Freitas**, validade **8h**,
> QR Code visível.

> 📸 **PRINT 14 — Tela do celular (marcação externa)**
> **Onde:** o link REP-P aberto no navegador do celular.
> **O que precisa aparecer:** a tela de OTP e, depois, a confirmação da batida
> com selfie e mapa.
> **Dados fictícios na tela:** Diego Freitas, **"Home office — dentro do raio"**.
> **Ação filmada:** ótimo momento para gravar a tela real de um celular.

> 💡 Marcação fora do raio permitido é **bloqueada** e gera alerta automático.

---

### Fluxo 9 — Compliance: alertas, REP-C, CCT, folha e relatórios

**Objetivo:** fechar o ciclo legal e acompanhar sinais de risco.
**Benefício:** conformidade técnica pronta para fiscalização e prevenção de
problemas antes que virem passivo.

- **Alertas** (aba **Compliance → Alertas**): atrasos recorrentes, faltas não
  justificadas, extras acima do limite, intervalos não cumpridos, marcação fora
  do raio. Cada alerta pode virar um **Plano de Ação 5W2H**.
- **REP-C** (Compliance): guarda os arquivos **AFD/AEJ** da Portaria 671.
- **CCT** (Configurações): anexe a Convenção Coletiva vigente.
- **Folha** (Apuração): exporta os dados consolidados para o módulo Financeiro.
- **Relatórios**: espelhos de ponto, extratos e relatórios fiscais.

> 📸 **PRINT 15 — Aba Alertas**
> **Onde:** Ponto → **Compliance → Alertas**.
> **O que precisa aparecer:** a lista de alertas com prioridade e o botão
> **Criar Ação**.
> **Dados fictícios na tela:** alerta **"Atrasos recorrentes — Diego Freitas
> (3 no mês)"**, prioridade **Alta**.

> 📸 **PRINT 16 — Exportação AFD/AEJ (REP-C)**
> **Onde:** Ponto → **Compliance → REP-C**.
> **O que precisa aparecer:** os arquivos AFD/AEJ prontos para download.
> **Dados fictícios na tela:** competência **Setembro/2026**, botões de
> download AFD e AEJ.

> 💡 Exporte e arquive o **AFD** todo mês — em fiscalização do MTE, ele é o
> documento oficial.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, mostrando dor → solução → prova. Personas fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Controle de ponto ainda em planilha? Um erro e vira processo."* Abre com uma planilha bagunçada. | Imagem genérica de planilha |
| 8–20s | *"O YourEyes registra a jornada com selfie, GPS e comprovante à prova de fraude."* | **PRINT 06** (registrar) + **PRINT 07** (comprovante) |
| 20–35s | *"Atraso, falta, hora extra e banco de horas: calculados sozinhos."* | **PRINT 08** (espelho) + **PRINT 11** (banco de horas) |
| 35–50s | *"Time em campo? Bate ponto pelo celular, com validação no WhatsApp."* | **PRINT 14** (celular REP-P) |
| 50–65s | *"No fim do mês, feche e integre à folha. E tenha os arquivos da Portaria 671 prontos para o fiscal."* | **PRINT 12** (fechamento) + **PRINT 16** (AFD/AEJ) |
| 65–80s | *"YourEyes. Sua jornada, segura por lei."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 5–8 min)

Ordem de gravação = ordem lógica de uso. Narração em primeira pessoa
("vamos configurar…", "agora eu registro…").

1. **Abertura** — o que o módulo faz e para quem (**PRINT 02**).
2. **Configurar o módulo** — tolerância, extras, selfie, raio (**PRINT 03**).
3. **Criar e atribuir uma escala** (**PRINT 04, 05**).
4. **Registrar um ponto** com selfie e GPS (**PRINT 06, 07**).
5. **Ler o espelho do dia** e usar os filtros (**PRINT 08**).
6. **Solicitar e aprovar um ajuste** (**PRINT 09, 10**).
7. **Conferir o banco de horas** (**PRINT 11**).
8. **Fechar o mês** (**PRINT 12**).
9. **Gerar um link REP-P** e mostrar no celular (**PRINT 13, 14**).
10. **Tratar um alerta** e **exportar o AFD** (**PRINT 15, 16**).
11. **Encerramento** — lembrar do botão **Guia Rápido** dentro do sistema.

> 💡 Dica de gravação: abra o **Guia Rápido** (botão no topo) e siga os 9 passos
> dele — o roteiro do tutorial foi montado na mesma sequência.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado vazio (opcional, só tutorial)
- [ ] **PRINT 02** — Tela inicial / Visão Geral
- [ ] **PRINT 03** — Aba Configurações
- [ ] **PRINT 04** — Lista de escalas
- [ ] **PRINT 05** — Cadastro de nova escala
- [ ] **PRINT 06** — Modal Registrar Ponto (selfie + GPS)
- [ ] **PRINT 07** — Comprovante (NSR)
- [ ] **PRINT 08** — Espelho do dia (com filtros e selos)
- [ ] **PRINT 09** — Modal Solicitar Ajuste
- [ ] **PRINT 10** — Aba Ajustes com pendências
- [ ] **PRINT 11** — Banco de horas
- [ ] **PRINT 12** — Fechamento mensal
- [ ] **PRINT 13** — Geração de link REP-P
- [ ] **PRINT 14** — Tela do celular (marcação externa)
- [ ] **PRINT 15** — Aba Alertas
- [ ] **PRINT 16** — Exportação AFD/AEJ

---

## 9. Erros comuns / dúvidas frequentes

- **"O módulo abriu vazio."** A empresa não tem o ponto ligado. Ative em
  **cadastro da empresa → Jornada e Turnos → "Utiliza controle de ponto"**.
- **"O colaborador não aparece na lista."** Ponto é só **CLT**; confira o tipo
  de vínculo. Verifique também se está **ativo** e vinculado à empresa certa.
- **"O sistema não calcula atraso/extra."** Falta **escala atribuída** ao
  colaborador (Fluxo 2).
- **"A marcação foi bloqueada."** Provavelmente **fora do raio** de
  geolocalização configurado — confira o local ou o raio na aba Configurações.
- **"Preciso mudar algo depois do fechamento."** É necessário **reabrir o
  período** formalmente; sem isso, o mês fica travado (por segurança).

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra o arquivo `docs/manuais/ponto_controle-de-ponto-eletronico.md` (este
   arquivo) no projeto.
2. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos.
3. Aprovado o **formato**, eu replico o mesmo padrão para os demais módulos, nos
   lotes que você priorizar.
