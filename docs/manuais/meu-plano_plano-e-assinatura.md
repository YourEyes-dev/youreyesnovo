# Manual do módulo — Meu Plano (Plano e Assinatura)

> Escrito no padrão de [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
> e na profundidade do piloto aprovado
> [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
> Serve de roteiro para os vídeos comercial e tutorial.

- **Onde fica no menu:** seção **Sistema → Meu Plano** (rota `/meu-plano`).
- **Para quem é:** gestores, responsável de RH e quem cuida do
  administrativo/financeiro da empresa — quem decide contratar módulos, vidas
  extras ou análises.
- **Em uma frase:** mostra, em uma tela só, **qual plano a empresa contratou**,
  **quanto está pagando por mês**, **quanto do limite já está sendo usado**
  (colaboradores e análises) e **o que dá para contratar na hora**, sem abrir
  chamado.
- **Importante:** esta tela **não emite boleto nem cobra no cartão**. As
  contratações feitas aqui têm **efeito imediato** no sistema (liberam o módulo
  ou elevam o limite) e **ajustam o valor mensal**; a **cobrança em si é
  conciliada pelo financeiro** depois. Para **trocar de plano** (subir de
  Starter para Performance, por exemplo), a tela orienta a **falar com o
  suporte** — isso não é feito por autosserviço.

---

## 1. Por que este módulo existe (benefícios)

Estes são os argumentos que sustentam o **vídeo comercial**:

- **Transparência total da assinatura.** O cliente vê o plano, o valor mensal
  detalhado (base do plano + add-ons) e tudo o que está incluído — sem depender
  do comercial para saber o que contratou.
- **Autosserviço na hora.** Precisa de mais um módulo ou de mais vidas para
  cadastrar colaboradores? Contrata ali mesmo, com **efeito imediato**. Sem
  e-mail, sem esperar aprovação.
- **Nunca ser pego de surpresa pelo limite.** A barra de **uso de vidas** e a de
  **análises** mudam de cor (verde → âmbar → vermelho) e avisam **antes** de
  travar o cadastro de gente nova.
- **Custo sob controle.** Cada add-on contratado aparece com preço unitário e
  total; dá para **cancelar** o que não usa mais e ver o valor mensal recalcular.
- **Crescimento sem fricção.** À medida que a empresa contrata mais gente, o
  próprio gestor eleva o teto de vidas — o sistema acompanha o crescimento em vez
  de atrapalhá-lo.

---

## 2. Conceitos-chave (glossário para a narração)

| Termo | O que é, em linguagem simples |
|---|---|
| **Plano** | O pacote contratado pela empresa (ex.: Starter, Essential, Performance, Governança, Enterprise). Define quais módulos vêm inclusos e o teto de vidas. |
| **Valor mensal** | Quanto a empresa paga por mês: a **base do plano** somada aos **add-ons** contratados. |
| **Vidas** | Cada **colaborador ativo** cadastrado. O plano dá um teto de vidas; passou do teto, é preciso contratar **vidas extras**. |
| **Vidas extras** | Add-on **mensal** que eleva o teto de vidas acima do incluído no plano (preço por vida/mês). |
| **Módulo incluído** | Recurso que já veio no plano — aparece com um **check verde**. |
| **Módulo avulso (add-on de módulo)** | Recurso fora do plano que a empresa contrata **à parte**, com **mensalidade própria** — aparece com **cadeado** e botão de contratar. |
| **Mapas comportamentais** | Análises de perfil comportamental de pessoas. O plano dá uma **cota** de análises. |
| **Cota / análise** | Cada **pessoa mapeada** consome **uma análise** da cota. Refazer o mapa da mesma pessoa **não** consome de novo. |
| **Recarga de análises** | Compra **avulsa** (unitária, por pessoa) que **soma ao saldo** e **não** entra no valor mensal. |
| **Add-on** | Nome genérico de qualquer contratação extra (módulo avulso, vidas extras ou recarga de análises). |
| **Sob consulta** | Quando o plano não tem preço público cadastrado — a tela orienta a falar com o suporte. |

---

## 3. Pré-requisitos (antes de gravar / operar)

1. **A empresa precisa ter um plano vinculado.** Sem plano, a tela mostra um
   aviso "Ainda não há um plano definido para esta empresa. Fale com o suporte"
   (é proposital — não há o que exibir).
2. **Usuário logado com acesso à empresa.** A tela lê o plano da **própria
   empresa** do usuário (não é preciso escolher empresa).
3. Para ver o cartão de **Mapas comportamentais**, o módulo **Mapa
   Comportamental** precisa estar **incluído** no plano (ou ter sido contratado
   como avulso). Se não estiver, o cartão simplesmente não aparece — e a
   contratação do módulo fica na lista de módulos, mais abaixo.

> 📸 **PRINT 01 — Estado sem plano / carregando (opcional, só tutorial)**
> **Onde:** módulo **Meu Plano** de uma empresa sem plano vinculado (ou durante
> o carregamento).
> **O que precisa aparecer:** o cartão "Ainda não há um plano definido para esta
> empresa. Fale com o suporte" (ou os retângulos cinza de carregamento).
> **Uso:** só no tutorial, para explicar o pré-requisito. Pode ser pulado no
> comercial.

---

## 4. Mapa da tela (visão de 30 segundos)

Ao abrir **Meu Plano**, o topo mostra uma **seta de voltar**, o título **"Meu
Plano"** e a linha **"Plano, uso, módulos e contratações da sua empresa"**. Não
há abas: a tela é uma **coluna de cartões**, de cima para baixo:

| Cartão | Para que serve |
|---|---|
| **Plano atual** | Nome do plano contratado (e o selo "Plano interno", quando for o caso). |
| **Valor mensal** | O total por mês, detalhado em base do plano + add-ons. |
| **Contratações ativas** | Lista dos add-ons já contratados, com opção de **cancelar** (só aparece se houver algum). |
| **Colaboradores (vidas)** | Uso × teto de vidas, com barra colorida e a opção **Adicionar vidas extras**. |
| **Mapas comportamentais** | Uso × cota de análises, com a opção **Comprar mais análises** (só aparece se o módulo estiver incluído). |
| **Módulos do seu plano** | Lista dos **incluídos** (check verde) e dos **disponíveis para contratar** (cadeado). |

Ao final, um rodapé lembra: *"Módulos e vidas extras podem ser contratados
aqui, na hora. Para mudar de plano, fale com o suporte."*

> 📸 **PRINT 02 — Tela inicial do módulo**
> **Onde:** menu **Sistema → Meu Plano**.
> **O que precisa aparecer:** o título "Meu Plano", a linha de subtítulo e a
> sequência de cartões (Plano atual, Valor mensal, Colaboradores, Módulos).
> **Dados fictícios na tela:** empresa **Empresa Staging LTDA**, plano
> **Performance**, valor **R$ 1.468,00 / mês**, **178 de 210 vidas**.
> **Ação filmada:** rolagem lenta de cima para baixo, mostrando todos os cartões.

---

## 5. Passo a passo por fluxo

A tela não tem um "assistente" passo a passo embutido — ela é **direta**, cada
cartão resolve uma coisa. Os fluxos abaixo seguem a ordem em que os cartões
aparecem na página.

### Fluxo 1 — Entender o plano e o valor mensal

**Objetivo:** saber o que a empresa contratou e quanto paga.
**Benefício:** transparência — o cliente enxerga plano e conta sem depender do
comercial.

1. Abra **Sistema → Meu Plano**.
2. No cartão **Plano atual**, leia o nome do plano. Se for um plano de uso
   interno da casa, aparece o selo **"Plano interno"**.
3. No cartão **Valor mensal**, veja o **total por mês** e o detalhamento:
   **Plano** (valor-base) e, quando houver, **Add-ons contratados**.
4. Se o plano estiver **sob consulta** (sem preço público), o cartão mostra
   "Valor do plano **sob consulta**. Fale com o suporte para conhecer os
   valores." — nesse caso não há total a exibir.

> 📸 **PRINT 03 — Cartão "Plano atual"**
> **Onde:** Meu Plano, primeiro cartão.
> **O que precisa aparecer:** o nome do plano em destaque e o ícone de brilho.
> **Dados fictícios na tela:** plano **Performance**.

> 📸 **PRINT 04 — Cartão "Valor mensal" (detalhado)**
> **Onde:** Meu Plano, segundo cartão.
> **O que precisa aparecer:** o total em destaque (R$ … / mês) e as linhas de
> detalhamento (Plano + Add-ons contratados), além do aviso de que os add-ons
> ajustam o valor e a cobrança é conciliada pelo financeiro.
> **Dados fictícios na tela:** total **R$ 1.468,00 / mês**; **Plano
> (Performance) R$ 1.290,00**; **Add-ons contratados R$ 178,00**.

> 💡 Esta tela **não cobra automaticamente**. O que muda aqui é o **valor
> mensal** e a **liberação do recurso**; o **financeiro concilia** a cobrança.

---

### Fluxo 2 — Acompanhar o uso de vidas (colaboradores)

**Objetivo:** saber quantos colaboradores ativos cabem no plano e quanto já foi
usado.
**Benefício:** enxergar o limite **antes** de tentar cadastrar alguém e travar.

1. Vá até o cartão **Colaboradores (vidas)**.
2. Leia **"X de Y vidas"** e o **percentual** ao lado. A barra é **verde** até
   79%, **âmbar** de 80% a 99% e **vermelha** ao atingir 100%.
3. Ao chegar perto (≥ 80%) ou no limite (100%), aparece uma **faixa de aviso**
   sugerindo adicionar vidas extras (ver Fluxo 3).
4. Se o plano tiver **vidas ilimitadas**, o cartão mostra apenas o número de
   **colaboradores ativos · limite ilimitado** — sem barra.

> 📸 **PRINT 05 — Cartão "Colaboradores (vidas)" com barra e aviso**
> **Onde:** Meu Plano, cartão de vidas.
> **O que precisa aparecer:** o número "X de Y vidas", o percentual, a barra
> colorida e, de preferência, a faixa de aviso âmbar de "chegando ao limite".
> **Dados fictícios na tela:** **178 de 210 vidas**, **85%**, barra **âmbar**,
> aviso *"Você está usando 85% do limite de vidas. Você pode adicionar vidas
> extras abaixo."*

> 💡 "Vida" é **colaborador ativo** — na plataforma, admissão com status
> **concluído**. Desligamentos deixam de contar; novas admissões passam a contar.

---

### Fluxo 3 — Adicionar vidas extras (autosserviço)

**Objetivo:** elevar o teto de vidas sem trocar de plano.
**Benefício:** cadastrar mais gente **na hora**, quando a empresa cresce.

1. Ainda no cartão **Colaboradores (vidas)**, encontre o bloco **"Adicionar
   vidas extras"** (aparece quando há preço cadastrado). Ele mostra o preço
   **por vida / mês**.
2. Se já houver vidas extras contratadas, o bloco avisa quantas — e lembra que
   **uma nova contratação substitui a atual** (o número informado é o **total**
   de vidas extras, não um acréscimo).
3. Digite a **quantidade** desejada (1 ou mais) e clique em **Contratar**.
4. O sistema confirma com "Contratação registrada. O valor mensal foi
   atualizado." — o teto sobe **na hora** e o **Valor mensal** é recalculado.

> 📸 **PRINT 06 — Adicionar vidas extras**
> **Onde:** cartão de vidas → bloco "Adicionar vidas extras".
> **O que precisa aparecer:** o preço por vida/mês, o campo de quantidade e o
> botão **Contratar**; se possível, a linha verde "Você já tem N vida(s)
> extra(s) contratada(s)".
> **Dados fictícios na tela:** **R$ 12,90 por vida / mês**; campo com **10**;
> aviso "Você já tem 10 vida(s) extra(s) contratada(s)".
> **Ação filmada:** digitar a quantidade e clicar em **Contratar**, mostrando o
> aviso de sucesso e o Valor mensal atualizando.

> 💡 A quantidade é o **total** de vidas extras. Se você tem 10 e quer 15, digite
> **15** (não 5) — a nova contratação **substitui** a anterior.

---

### Fluxo 4 — Acompanhar a cota de mapas comportamentais

**Objetivo:** saber quantas análises de perfil ainda cabem.
**Benefício:** planejar mapeamentos sem esbarrar na cota no meio do processo.

1. Vá ao cartão **Mapas comportamentais** (só aparece se o módulo estiver
   incluído ou contratado).
2. Leia **"X de Y análises"** e o percentual — mesma lógica de cores da barra de
   vidas (verde / âmbar / vermelho).
3. Leia a explicação: **cada pessoa mapeada consome uma análise**;
   **rotatividade e novas contratações consomem novas análises**; **refazer o
   mapa da mesma pessoa não consome**.
4. Se a cota for **ilimitada**, o cartão mostra só o número de **pessoas
   mapeadas · análises ilimitadas**.

> 📸 **PRINT 07 — Cartão "Mapas comportamentais"**
> **Onde:** Meu Plano, cartão de mapas.
> **O que precisa aparecer:** o número "X de Y análises", o percentual, a barra e
> o texto explicando o consumo por pessoa.
> **Dados fictícios na tela:** **118 de 200 análises**, **59%**, barra
> **verde**.

> 💡 A cota de análises **espelha o tamanho do plano** (o mesmo porte do teto de
> vidas). É um **saldo acumulado** — cresce quando você recarrega, e o consumo é
> por pessoa mapeada.

---

### Fluxo 5 — Comprar mais análises (recarga avulsa)

**Objetivo:** ganhar mais análises sem mexer no valor mensal.
**Benefício:** recarga pontual, unitária por pessoa, que **soma ao saldo**.

1. No cartão **Mapas comportamentais**, encontre o bloco **"Comprar mais
   análises"** (aparece quando há preço cadastrado). Ele mostra o preço **por
   análise (pessoa)**.
2. Note o aviso: é **compra avulsa** — **soma ao saldo** e **não altera o valor
   mensal** (diferente das vidas extras, que são mensais).
3. Digite a **quantidade** (1 ou mais) e clique em **Comprar**.
4. O saldo de análises aumenta na hora.

> 📸 **PRINT 08 — Comprar mais análises**
> **Onde:** cartão de mapas → bloco "Comprar mais análises".
> **O que precisa aparecer:** o preço por análise, o texto "Compra avulsa — soma
> ao seu saldo e não altera o valor mensal", o campo de quantidade e o botão
> **Comprar**.
> **Dados fictícios na tela:** **R$ 9,90 por análise (pessoa)**; campo com **50**.
> **Ação filmada:** digitar a quantidade e clicar em **Comprar**.

> 💡 Diferença que vale explicar no vídeo: **vidas extras = mensal** (entra no
> valor do mês); **recarga de análises = avulsa** (saldo que não mexe na
> mensalidade).

---

### Fluxo 6 — Ver os módulos e contratar um módulo avulso

**Objetivo:** enxergar o que está incluído e o que dá para contratar à parte.
**Benefício:** liberar um recurso **na hora**, sem trocar de plano.

1. Role até o cartão **Módulos do seu plano**.
2. Em **Incluídos**, os módulos do plano aparecem com **check verde**.
3. Em **Disponíveis para contratar**, os módulos fora do plano aparecem com
   **cadeado**. Cada um mostra **uma** de duas coisas:
   - um botão **"Contratar (R$ …/mês)"**, quando o módulo pode ser contratado
     avulso; ou
   - um selo com o **nome do plano** onde ele passa a existir (ex.: "Governança"),
     quando não é vendido avulso — nesse caso, o caminho é **mudar de plano com o
     suporte**.
4. Ao clicar em **Contratar**, o módulo é **liberado imediatamente** e o **Valor
   mensal** é recalculado (aviso "Contratação registrada. O valor mensal foi
   atualizado.").

> 📸 **PRINT 09 — Cartão "Módulos do seu plano"**
> **Onde:** Meu Plano, cartão de módulos.
> **O que precisa aparecer:** a lista de **Incluídos (N)** com checks verdes e a
> de **Disponíveis para contratar (N)** com cadeados, misturando um botão
> "Contratar (R$ …/mês)" e um selo de plano.
> **Dados fictícios na tela:** Incluídos: **Estrutura, Ponto, Psicossocial,
> Benefícios, Metas, Mapa Comportamental**. Disponíveis: **KPIs Estratégicos —
> Contratar (R$ 39,00/mês)** e **Identidade Estratégica — selo "Governança"**.

> 📸 **PRINT 10 — Contratar um módulo (confirmação)**
> **Onde:** cartão de módulos, ao clicar em **Contratar** em um módulo com preço.
> **O que precisa aparecer:** o aviso de sucesso "Contratação registrada. O valor
> mensal foi atualizado." e o módulo migrando para **Incluídos**.
> **Dados fictícios na tela:** módulo **KPIs Estratégicos** recém-contratado.
> **Ação filmada:** clicar em **Contratar** e mostrar o Valor mensal subindo.

> 💡 O cadeado nos módulos é **convite comercial**, não é o único bloqueio de
> dados — mas contratar aqui **libera o recurso de verdade** na hora.

---

### Fluxo 7 — Gerenciar as contratações ativas (cancelar)

**Objetivo:** revisar e cancelar add-ons que não são mais necessários.
**Benefício:** custo sob controle — cancela o que não usa e vê o valor cair.

1. Vá ao cartão **Contratações ativas** (só aparece se houver algum add-on).
2. Cada linha mostra o add-on e o preço:
   - **vidas extras:** "N vida(s) extra(s)" com o cálculo (unitário × quantidade);
   - **módulo avulso:** o nome do módulo e a mensalidade.
3. Para remover, clique em **Cancelar** na linha desejada.
4. O sistema confirma "Add-on cancelado." — o efeito é desfeito e o **Valor
   mensal** recalcula.

> 📸 **PRINT 11 — Cartão "Contratações ativas"**
> **Onde:** Meu Plano, cartão de contratações (quando há add-ons).
> **O que precisa aparecer:** a lista de add-ons com preços e o botão
> **Cancelar** em cada linha.
> **Dados fictícios na tela:** **10 vida(s) extra(s)** — R$ 12,90 × 10 = R$
> 129,00 / mês; **Planejamento Estratégico** — R$ 49,00 / mês.

> 📸 **PRINT 12 — Cancelar um add-on (confirmação)**
> **Onde:** cartão de contratações, ao clicar em **Cancelar**.
> **O que precisa aparecer:** o aviso "Add-on cancelado." e a lista atualizada.
> **Dados fictícios na tela:** cancelamento do add-on **Planejamento
> Estratégico**.
> **Ação filmada:** clicar em **Cancelar** e mostrar o Valor mensal recalculando.

> 💡 Cancelar **módulo avulso** volta o recurso ao estado bloqueado; cancelar
> **vidas extras** volta o teto ao incluído no plano. Confira o uso atual antes,
> para não ficar acima do limite.

---

## 6. Roteiro sugerido — vídeo COMERCIAL (60–90s)

**Tom:** direto, dor → solução → prova. Personas e empresa fictícias.

| Tempo | Cena / narração | Print / captura |
|---|---|---|
| 0–8s | *"Quanto sua empresa paga de RH por mês? E o que exatamente está incluído?"* Abre com dúvida/planilha de custos. | Imagem genérica |
| 8–22s | *"No YourEyes, seu plano é uma tela só: valor detalhado, módulos incluídos e o que dá para contratar."* | **PRINT 02** (visão geral) + **PRINT 04** (valor mensal) |
| 22–38s | *"Cresceu a equipe? Você mesmo adiciona vidas — na hora, sem chamado."* | **PRINT 05** (uso de vidas) + **PRINT 06** (adicionar vidas) |
| 38–52s | *"Precisa de um módulo novo? Um clique libera e o valor se ajusta."* | **PRINT 09** (módulos) + **PRINT 10** (contratar) |
| 52–65s | *"E o que não usa mais, você cancela — custo sempre sob controle."* | **PRINT 11** (contratações ativas) |
| 65–80s | *"YourEyes. Seu plano, na palma da sua mão."* Logo. | Tela final |

---

## 7. Roteiro sugerido — vídeo TUTORIAL (operação real, 4–6 min)

Ordem de gravação = ordem dos cartões na tela. Narração em primeira pessoa
("agora eu confiro…", "vou contratar…").

1. **Abertura** — o que a tela mostra e para quem serve (**PRINT 02**).
2. **Ler o plano atual** e o **valor mensal** detalhado (**PRINT 03, 04**).
3. **Acompanhar o uso de vidas** e entender as cores da barra (**PRINT 05**).
4. **Adicionar vidas extras** e ver o valor recalcular (**PRINT 06**).
5. **Conferir a cota de mapas comportamentais** (**PRINT 07**).
6. **Comprar mais análises** (recarga avulsa) (**PRINT 08**).
7. **Ver os módulos** incluídos × disponíveis e **contratar um módulo**
   (**PRINT 09, 10**).
8. **Revisar as contratações ativas** e **cancelar** um add-on (**PRINT 11, 12**).
9. **Encerramento** — lembrar que **trocar de plano é com o suporte** (rodapé da
   tela) e que a **cobrança é conciliada pelo financeiro**.

> 💡 Dica de gravação: prepare a empresa de teste com pelo menos **uma
> contratação ativa** e o uso de vidas **perto do limite** (≥ 80%) — assim os
> cartões de "Contratações ativas" e a faixa de aviso âmbar aparecem no vídeo.

---

## 8. Checklist de prints (conferir na captura)

Ambiente de captura: **site de teste**
(https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

- [ ] **PRINT 01** — Estado sem plano / carregando (opcional, só tutorial)
- [ ] **PRINT 02** — Tela inicial (visão geral dos cartões)
- [ ] **PRINT 03** — Cartão Plano atual
- [ ] **PRINT 04** — Cartão Valor mensal (detalhado)
- [ ] **PRINT 05** — Cartão Colaboradores (vidas) com barra e aviso
- [ ] **PRINT 06** — Adicionar vidas extras
- [ ] **PRINT 07** — Cartão Mapas comportamentais
- [ ] **PRINT 08** — Comprar mais análises
- [ ] **PRINT 09** — Cartão Módulos (incluídos × disponíveis)
- [ ] **PRINT 10** — Contratar um módulo (confirmação)
- [ ] **PRINT 11** — Cartão Contratações ativas
- [ ] **PRINT 12** — Cancelar um add-on (confirmação)

---

## 9. Erros comuns / dúvidas frequentes

- **"A tela diz que não há plano definido."** A empresa está sem plano
  vinculado. É preciso **falar com o suporte** para vincular um plano.
- **"O valor aparece como 'sob consulta'."** O plano não tem preço público
  cadastrado — a própria tela orienta a falar com o suporte para conhecer os
  valores.
- **"O cartão de Mapas comportamentais não aparece."** É normal: ele só surge
  quando o módulo **Mapa Comportamental** está **incluído** no plano (ou foi
  contratado). Se não estiver, a contratação dele fica na lista de **módulos**.
- **"Contratei vidas extras e o número não é o que eu queria."** A quantidade é o
  **total** de vidas extras, e a nova contratação **substitui** a anterior. Para
  ter 15, digite **15** — não some você mesmo.
- **"Não consigo adicionar vidas."** Se o plano já é **ilimitado**, não há bloco
  de contratar vidas (não faz sentido). Fora isso, confira se há **preço**
  cadastrado para vidas extras.
- **"Contratei/cancelei e não vi cobrança mudar no banco/cartão."** Esperado: a
  tela **não cobra**. Ela ajusta o **valor mensal** e libera/retira o recurso; a
  **cobrança é conciliada pelo financeiro**.
- **"Quero trocar de plano (subir de nível)."** Isso **não** é autosserviço:
  fale com o suporte. Pela tela dá para contratar **módulos avulsos** e **vidas
  extras**, não mudar o plano.

---

## Como conferir esta entrega

Este é um **documento** (manual), não uma mudança de comportamento do sistema —
nenhuma tela, banco ou rotina foi alterada, então a **produção segue intacta** e
não há o que validar em ambiente de execução. Para revisar o conteúdo:

1. Abra, no site de teste
   (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como **Marina
   Alves** (empresa **Empresa Staging LTDA**), o menu **Sistema → Meu Plano**, e
   confira se os cartões descritos aqui (Plano atual, Valor mensal,
   Colaboradores, Mapas comportamentais, Módulos e Contratações ativas) batem
   com o que o manual descreve.
2. Confira se o passo a passo, os benefícios e os marcadores de print refletem
   como você quer conduzir os vídeos.
3. Aprovado o **formato**, eu replico o mesmo padrão para os demais módulos, nos
   lotes que você priorizar.
</content>
</invoke>
