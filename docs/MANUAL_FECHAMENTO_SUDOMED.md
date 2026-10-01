# Manual de Ponto e Fechamento — SUDOMED
### Passo a passo para o RH, do zero. Linguagem simples, sem jargão.

> Este manual cobre **tudo** o que precisa estar configurado e **tudo** o que o
> RH faz todo mês para fechar o ponto corretamente. Foi escrito para quem está
> começando em Departamento Pessoal. Siga na ordem.
>
> **Empresas (CNPJ):** 26.114.701/0001-45 · 31.219.374/0001-26 · 41.085.456/0001-89
> **Como é o ponto da Sudomed:** banco de horas com acerto **semestral**; acordo
> **individual** por pessoa; **várias escalas** (algumas sem sábado, algumas com
> **um sábado variável** no mês para fechar a carga); convenção coletiva (CCT)
> a cadastrar.

---

## PARTE 0 — Entenda a situação antes de mexer

### 0.1 O que já existe e o que falta
Para ver, **sem risco**, o estado atual das 3 empresas (escalas, acordos, regime
de banco, CCT, fechamentos e zeragens já feitas), rode o relatório de conferência
`docs/script_sudomed_raiox_ponto.sql` no **SQL Editor** do projeto. Ele **só lê**,
não altera nada. O resultado vem em seções numeradas. Onde aparecer
"(nenhum … a configurar)", é um item deste manual ainda pendente.

Pelo que você descreveu, hoje faltam configurar: **a CCT**, os **acordos
individuais** e o **regime de banco de horas**. As escalas já existem (algumas).

### 0.2 Três conceitos que confundem (leia com calma)
1. **Escala** = o horário de trabalho da pessoa (que dias, que horas, se tem
   sábado). Uma pessoa tem **uma** escala por vez.
2. **Banco de horas** = a "poupança" de horas. Quem trabalha a mais fica com
   **crédito**; quem fica devendo, **débito**. O acerto dessa poupança é o que
   vocês fazem **a cada semestre**.
3. **Fechar o mês** = travar o mês para ninguém mais mexer e gerar o espelho
   oficial de cada pessoa. **O sistema fecha sempre por MÊS.** O "semestral" é só
   a hora de **acertar o saldo do banco** — explico na Parte 3.

### 0.3 Sobre "semestral": o que o sistema faz e o que ele não faz
O sistema **não tem um botão "fechar semestre"**. Ele:
- **Fecha o ponto mês a mês** (Parte 2); e
- **Guarda o saldo do banco acumulando** mês após mês; e
- Deixa você definir que o banco **vence em 180 dias** (= 6 meses = semestral),
  e o que fazer com o que sobrar (pagar, folga ou zerar).

Então o "fechamento semestral" na prática = **fechar os 6 meses normalmente** +
**no 6º mês, acertar o banco** (Parte 3).

---

## PARTE 1 — CONFIGURAÇÃO INICIAL (faz uma vez)

> Faça esta parte **uma vez por empresa**. Se as 3 empresas têm as mesmas regras,
> repita os passos em cada uma (troque a empresa no seletor **"Empresa"** no topo
> da tela de Ponto).

### Passo 1 — Ligar o controle de ponto na empresa
1. Vá no **cadastro da empresa** → aba **"Jornada e Turnos"**.
2. Ligue a opção **"Utiliza controle de ponto"**.
3. Salve. (Sem isso, a empresa nem aparece no seletor do Ponto.)

Repita nas 3 empresas.

### Passo 2 — Configurações gerais do ponto
Menu **Ponto → Configurações → Geral**. Confira cada cartão:

- **Modo de Registro** — escolha como as pessoas batem ponto:
  - **"Somente Interno (REP-C)"** — só o RH/gestor lança.
  - **"Somente Link Externo (REP-P)"** — cada um bate pelo celular, por um link.
  - **"Ambos (Recomendado)"** — os dois. **Use este** se as pessoas batem pelo
    celular e o RH também precisa ajustar.
  - Se escolher Link Externo ou Ambos, preencha **"Instrumento que autoriza o
    registro por link (REP-A)"** (a referência do acordo/convenção).
- **Verificação e Segurança** — ligue **"Selfie obrigatória"** e/ou
  **"Geolocalização obrigatória"** se quiser exigir foto/local na batida.
- **Tolerâncias (CLT Art. 58)** — **"Tolerância atraso (min)"** e
  **"Tolerância hora extra (min)"**. O padrão (10 e 10) atende a CLT; mas a CCT
  pode mandar outro valor — confira a convenção.
- **Justificativas e Abonos** — botão **"Configurar Justificativas"**: cadastre
  os motivos que o RH usa ao abonar/ajustar (ex.: "Atestado médico").
- **Feriados** — cadastre os feriados (Nacional/Estadual/Municipal). Não esqueça
  os **municipais** das cidades das 3 empresas.

Clique **"Salvar Configurações"**.

### Passo 3 — Cadastrar as ESCALAS
Menu **Ponto → Escalas**. Botão **"Criar Escala"** (ou **"Cadastro
Inteligente"**, que monta a escala a partir de um texto que você escreve/fala).

Para cada escala diferente que a Sudomed tem, crie uma. No diálogo **"Nova Escala
de Trabalho"**:

1. **"Nome da Escala"** — ex.: "Administrativo", "Produção Seg-Sáb".
2. **"Modalidade"** — para horário normal de semana, escolha **"Fixa (dias da
   semana definidos)"**.
3. No bloco **"Dias da semana"**, marque para cada dia: **"Trab."** (se trabalha),
   **"Almoço"**, e os horários **"Entrada" / "Início almoço" / "Fim almoço" /
   "Saída"**. Use os atalhos **"Seg→Sex iguais"** ou **"Seg→Sáb iguais"** para
   agilizar.
4. Olhe o contador **"Carga calculada"** (horas por semana e por mês). A meta CLT
   é 44h/semana · 220h/mês — confira com a sua CCT.

#### Como tratar o SÁBADO — o ponto que mais confunde na Sudomed
Você tem três situações. Configure assim:

- **Escala que NÃO trabalha sábado:** deixe o **sábado como folga** (não marque
  "Trab." no sábado). Pronto.

- **Escala que trabalha UM sábado variável no mês** (para fechar a carga mensal):
  **NÃO** fixe o sábado na grade. Em vez disso, no bloco âmbar **"Equalização
  mensal (sábado variável)"**, **ligue o switch** e escolha a **"Carga semanal
  contratada"** (ex.: **"44h (padrão)"**). O sistema então:
  - calcula sozinho quantas horas faltam no mês para fechar a carga; e
  - reconhece **qualquer sábado trabalhado** como o dia que compensa esse déficit.
  É o jeito certo para "um sábado qualquer do mês". **Não use** o modelo antigo
  **"Compensações Mensais"** (posição fixa tipo "3º sábado") — ele só serve
  quando o sábado é **sempre** o mesmo.

- **Escala que trabalha sábado fixo toda semana:** aí sim marque **"Trab."** no
  sábado na grade, com os horários.

5. Campos comuns: **"Intervalo (min)"**, **"Tolerância marcação (min)"** (padrão
   5), **"Tolerância diária (min)"** (padrão 10), percentuais de hora extra,
   **"Comportamento em feriado"** (Folga ou Trabalha).
6. **"Criar Escala"**.

Repita para cada escala.

### Passo 4 — (Só se usarem jornada de 2 batidas) Intervalo pré-assinalado
Se alguma escala **não bate o almoço** (a pessoa marca só entrada e saída, e o
almoço é "declarado"), configure em **Ponto → Configurações → Intervalo
pré-assinalado → "Nova declaração"**:
- **"Alcance"**: "Escala inteira" ou "Um colaborador".
- **"Intervalo (minutos)"** e a **"Janela"** (ex.: 12:00–13:00).
- **"Vigência — início"** e **"Lastro"** (a cláusula da CCT que autoriza).

Se todo mundo bate o almoço normalmente, **pule este passo**.

### Passo 5 — Cadastrar a CONVENÇÃO COLETIVA (CCT)
Menu **Ponto → Compliance → CCT → "Nova CCT"**. Preencha com a sua convenção:
- **"Nome da CCT"**, **"Sindicato"**, **"Categoria Profissional"**,
  **"Vigência Início/Fim"**.
- **"Jornada Semanal (h)"** e **"Jornada Diária (h)"**.
- **"Horas Extras"**: percentuais de dia útil, domingos, feriados e o limite
  diário.
- **"Adicional Noturno"** e **"Intervalos"**.
- **"Banco de Horas & DSR"**: ligue **"Banco de Horas Permitido"** e defina
  **"Prazo Compensação (meses)"** = **6** (semestral), conforme a sua CCT.
- Salve.

### Passo 6 — Cadastrar os ACORDOS INDIVIDUAIS (um por pessoa)
Como vocês usam **acordo individual** de banco de horas, cadastre **um acordo por
colaborador**. Menu **Ponto → Compliance → Acordos → "Novo Acordo"**:
- **"Tipo"**: **"Acordo Individual"**.
- **"Título"**: ex.: "Acordo de Banco de Horas — [Nome] — 2026".
- **"Vigência Início/Fim"**.
- **"URL do Documento"**: o link do acordo assinado (guarde o documento!).
- (Opcional) o switch **"Autoriza compensação de falta"** só é necessário se você
  quiser poder **converter falta injustificada em débito do banco**. Se ligar,
  preencha o **"CPF do colaborador"** para valer **só para aquela pessoa**.
- Salve. Repita para cada pessoa.

> Dica: sem o acordo cadastrado e vigente, o sistema **não acumula** banco de
> horas para a pessoa (proteção legal). Por isso este passo é obrigatório.

### Passo 7 — Configurar o REGIME DE BANCO DE HORAS
Menu **Ponto → Apuração → Config BH → "Nova Configuração"**:
- **"Tipo"**: **"Individual"** (porque o acordo de vocês é individual).
- **"Escala (opcional)"**: pode deixar "Todas as escalas" ou criar uma config por
  escala, se as regras mudam entre elas.
- **"Acordo Vinculado (opcional)"**: vincule ao acordo da pessoa/escala.
- **"Data de início"**: a data a partir da qual o banco começa a contar (a
  **vigência** do regime). **Importante:** o banco só acumula a partir daqui.
- **"Prazo de Compensação (dias)"**: **180** (= 6 meses = semestral).
- **"Limite Acúmulo (horas)"**: o teto de horas que pode acumular (padrão 60).
- **"Forma de Compensação"**: Folga / Redução de jornada / Antecipação de férias.
- **"Forma de Pgto. ao Vencer"**: o que fazer com o saldo que sobrar no fim do
  semestre — **"Pagar como Horas Extras"**, **"Liquidar na rescisão"** ou
  **"Zerar (com aviso)"**. (É isto que automatiza o acerto semestral — veja a
  Parte 3.)
- Ligue **"Exige acordo individual"** (combina com o passo 6).
- Salve.

### Passo 8 — Atribuir a escala a cada colaborador
Menu **Ponto → Escalas → "Atribuir Escala"**:
- Escolha a **"Escala"**, a **"Data Início"**, marque os colaboradores.
- Se a pessoa está trocando de escala, marque **"Substituir escala atual"**.

✅ **Fim da configuração inicial.** Rode de novo o Raio-X (0.1) e confira que as
seções 3, 4, 5 e 6 agora aparecem preenchidas.

---

## PARTE 2 — ROTINA DE TODO MÊS (fechar o mês)

> Faça nesta ordem, perto do fim do mês / início do mês seguinte.

### 1) Acompanhar o Espelho durante o mês
Menu **Ponto → Espelho**. Veja as marcações do dia, por pessoa. Status possíveis:
Regular, Atraso, Falta, Incompleto, Justificado. Vá resolvendo os problemas ao
longo do mês — não deixe tudo para o último dia.

### 2) Aprovar os AJUSTES pendentes
Menu **Ponto → Ajustes** (o número vermelho mostra quantos dias estão pendentes).
Aprove ou rejeite cada pedido de correção de horário. **Enquanto houver ajuste
pendente, o mês não fecha.**

### 3) Resolver as PENDÊNCIAS
Menu **Ponto → Apuração → Fechamento**. O cartão **"Pendências que impedem o
fechamento"** lista o que falta. Os três tipos são:
- **"Ajuste de ponto aguardando aprovação"** → volte ao passo 2.
- **"Dia incompleto sem tratamento"** → a pessoa esqueceu de bater; ajuste o dia
  (lance o horário ou abone com justificativa).
- **"Espelho sem ciência do colaborador"** → falta a pessoa "dar ciência" no
  espelho dela.

### 4) Conferir o BANCO DE HORAS
Menu **Ponto → Apuração → Banco Horas**. Clique **"Apurar agora"** para o sistema
recalcular créditos e débitos do mês. Confira os cards **"Total Créditos / Total
Débitos / Saldo Total"** e, se houver, o bloco **"Equalização mensal (fechar
44h)"** (o sábado variável). Se precisar marcar qual sábado foi trabalhado, use
**"Definir sábados"**.

### 5) (Se teve falta a compensar) Compensação de faltas
Menu **Ponto → Apuração → Comp. Faltas**. No cartão **"Faltas do mês"**, clique
**"Compensar"** na falta elegível. O fluxo é: **Autorizar** (gestor) → **Homologar
(RH)**, se acima do limite → **Registrar ciência** (a pessoa concorda) → vira
**débito no banco**. Só aparece quando há **regime de banco + acordo** vigentes
(por isso a Parte 1).

### 6) FECHAR o mês
Menu **Ponto → Apuração → Fechamento**:
1. Escolha a **competência** (o mês).
2. Se não há pendências, clique **"Fechar Período"** → **"Confirmar Fechamento"**.
   (Se o botão estiver **"Bloqueado por pendências"**, volte aos passos 2–3.)
3. O sistema **trava o mês** e **gera os espelhos** oficiais (o PDF de cada um é
   arquivado sozinho em Documentos → "Vida Funcional").

### 7) Espelhos: enviar e colher ciência
Ainda em **Fechamento**, no cartão **"Espelhos de Ponto"**, cada linha tem o
status (Gerado → Enviado → Confirmado). Baixe o PDF, envie para a pessoa e
registre a **ciência** (ou **ressalva**, se ela discordar).

> **Precisa reabrir um mês já fechado?** Botão **"Reabrir Período"** → informe o
> **"Motivo da reabertura"**. Atenção: espelhos ainda não confirmados são
> descartados; os já confirmados permanecem.

✅ **Mês fechado.** Repita todo mês.

---

## PARTE 3 — O ACERTO SEMESTRAL DO BANCO

> Lembre: você **fecha todo mês** (Parte 2). O acerto do banco é feito **no último
> mês do semestre**, depois de fechar aquele mês.

Ao chegar no fim do semestre (o prazo de 180 dias / 6 meses do Passo 7):

1. Feche o mês normalmente (Parte 2).
2. Vá em **Ponto → Apuração → Banco Horas** e confira o **"Saldo Atual"** de cada
   pessoa.
3. Decida o destino do saldo, conforme o acordo e a **"Forma de Pgto. ao Vencer"**
   que você configurou:
   - **Saldo positivo (crédito):** vira folga, ou é **pago como hora extra**, ou é
     **zerado** (se foi o combinado) — exatamente o que estiver em "Forma de Pgto.
     ao Vencer".
   - **Saldo negativo (débito):** tratar conforme o acordo (desconto ou perdão).
4. Para **zerar/ajustar** o saldo de uma pessoa manualmente, use, na mesma tela:
   - **"Movimentar"** → lançar um **"Débito"** ou **"Compensação"** que leva o
     saldo a zero; **ou**
   - **"Editar Banco de Horas"** → ajustar o **"Saldo Anterior"** (campo com
     **"+ Crédito" / "− Débito"**, horas e minutos).

> **Zeragem em massa (muitas pessoas de uma vez):** se for zerar o saldo de várias
> pessoas ao mesmo tempo (como foi feito em agosto, referente a julho), **não faça
> uma a uma** — peça para o responsável técnico rodar o **script de zeragem
> corretiva** no SQL Editor (ele guarda backup antes de mexer). Faça pela tela
> apenas ajustes pontuais, de poucas pessoas.

### O calendário da Sudomed (a transição)
- **2026 (agora até dezembro):** vocês estão **zerando aos poucos** os saldos
  antigos (agosto zerou julho de algumas pessoas; até dezembro zeram o resto).
  Faça cada zeragem registrando bem o motivo.
- **A partir de 2027:** o acerto do banco passa a ser **sempre em junho e
  dezembro**, para **todos**, não importa há quantos meses a pessoa está na
  empresa. Ou seja:
  - **Acerto 1:** feche janeiro→junho mês a mês e **acerte o banco no fechamento
    de junho**.
  - **Acerto 2:** feche julho→dezembro mês a mês e **acerte o banco no fechamento
    de dezembro**.

---

## PARTE 4 — CHECKLISTS RÁPIDOS

### Configuração inicial (uma vez, por empresa)
- [ ] Empresa com **"Utiliza controle de ponto"** ligado
- [ ] **Configurações → Geral** salvas (modo, tolerâncias, justificativas,
      feriados)
- [ ] **Escalas** criadas (sábado tratado: folga / "Equalização mensal" / fixo)
- [ ] **Intervalo pré-assinalado** (só se usarem 2 batidas)
- [ ] **CCT** cadastrada
- [ ] **Acordos individuais** cadastrados (um por pessoa)
- [ ] **Config BH** criada (Tipo Individual, Prazo 180, Exige acordo, Data de
      início)
- [ ] **Escalas atribuídas** a cada colaborador

### Todo mês
- [ ] Espelho conferido
- [ ] Ajustes aprovados/rejeitados
- [ ] Pendências zeradas (ajuste, dia incompleto, ciência)
- [ ] Banco de horas **"Apurar agora"** e conferido
- [ ] Faltas compensadas (se houver)
- [ ] **"Fechar Período"**
- [ ] Espelhos enviados e com ciência

### Fim de semestre (jun e dez, a partir de 2027)
- [ ] Último mês do semestre fechado
- [ ] Saldos conferidos
- [ ] Saldos acertados/zerados conforme o acordo

---

## PARTE 5 — ERROS COMUNS (evite)
- **"O mês não fecha."** → Tem pendência. Veja o cartão de pendências e resolva
  (quase sempre é ajuste pendente ou dia incompleto).
- **"O banco não acumula para a pessoa."** → Falta o **acordo individual vigente**
  e/ou o **Config BH** com a **data de início** certa. Confira os passos 6 e 7.
- **"O sábado está contando errado."** → Para sábado variável, use **"Equalização
  mensal (sábado variável)"** na escala, não o modelo antigo de posição fixa.
- **"Aparecem desligados/fim de semana nas listas."** → Já corrigido no sistema;
  se notar algo, avise o responsável técnico.
- **Não confunda os dois lugares de "tipo de banco":** o **regime** (Config BH)
  usa Sem Banco/Semanal/Mensal/Individual/Coletivo; o **banco individual** (aba
  Banco Horas, ao criar "Novo Banco") usa Mensal/Semestral/Anual. Para a Sudomed:
  regime **Individual** com prazo **180 dias**.

---
*Documento de apoio ao RH da Sudomed. Dúvida em qualquer passo, fale com o
responsável pelo sistema antes de alterar dados em lote.*
