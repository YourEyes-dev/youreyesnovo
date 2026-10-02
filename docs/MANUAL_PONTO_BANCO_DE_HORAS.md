# Manual do Ponto Eletrônico e do Banco de Horas
### Guia prático para o RH — para empresas que usam **banco de horas**

> Linguagem simples, com exemplos. Documento de apoio ao Departamento Pessoal.
> A versão em **PDF (padrão ABNT)** é gerada por `docs/gerar_manual_banco_horas.py`
> (`python3 docs/gerar_manual_banco_horas.py`). Este `.md` é a fonte editável.
>
> Genérico (sem dados de colaborador) — serve para qualquer empresa com banco de horas.

---

## 1. Para que serve este manual
Ensina, passo a passo e em linguagem simples, como o Departamento Pessoal cuida do
ponto eletrônico numa empresa que usa **banco de horas**: o que conferir todo dia,
como ler o espelho, como o banco enche e esvazia, o que fazer com faltas e como
fechar o mês com segurança. Sempre que possível, há um **exemplo**.

**Regra de ouro:** resolva as pendências ao longo do mês; não deixe tudo para o
último dia. Um mês acompanhado de perto fecha em minutos.

## 2. Conceitos que você vai usar o tempo todo
- **Jornada** — quantas horas a pessoa deve trabalhar no dia (ex.: 8h). É o
  "esperado" do dia.
- **Escala** — o horário de trabalho (quais dias, horas, intervalo). Cada pessoa
  tem uma escala por vez. **Sem escala, o sistema não apura o dia** corretamente.
- **Banco de horas** — a "poupança" de horas. Trabalhou **a mais** → **crédito**;
  trabalhou **a menos** → **débito**. Vai acumulando mês a mês até o acerto.
- **Crédito, débito e saldo** — crédito é hora a favor; débito é hora devida;
  saldo = saldo anterior + créditos − débitos.
- **Falta** — dia que a pessoa deveria trabalhar e não trabalhou. Pode ser
  **justificada** (atestado) ou **não justificada**.
- **Compensação de falta** — usar o **saldo do banco** para cobrir a falta, em vez
  de descontar na folha. É decisão deliberada, com acordo e ciência (seção 6).
- **Pré-assinalação do intervalo** — quando a pessoa bate só entrada e saída, o
  almoço é declarado e descontado automaticamente (jornadas de dia inteiro).
- **Fechar o mês** — travar a competência e gerar o espelho oficial (que será
  assinado). O sistema fecha sempre **por mês**.

## 3. O espelho de ponto: o que cada coluna significa

| Sigla | O que é | Em palavras simples |
|---|---|---|
| **H.D.** | Total de horas do dia | Quanto a pessoa **realmente** trabalhou no dia. |
| **H.N.** | Hora normal (prevista) | Quanto ela **deveria** ter trabalhado (a jornada). |
| **H.E.** | Hora extra | Horas que passaram da jornada (vão ao banco ou a pagar). |
| **H.C.** | Hora compensada | Horas usadas para compensar (ex.: sábado de equalização). |
| **H.A.** | Hora de ausência | Horas que faltaram no dia (atraso/saída antecipada). |
| **A.N.** | Adicional noturno | Horas no período noturno, quando houver. |
| **F.N.** | Falta não justificada | Falta sem justificativa (vai para a folha). |
| **F.J.** | Falta justificada | Falta abonada (não desconta). |

Cada dia também traz uma **Ocorrência** (o rótulo do que aconteceu): "Soma Banco
Horas", "Diminui Banco Horas", "Falta", "Justificado", "Compensado", "Pendência —
marcação incompleta", etc.

> **Exemplo (um dia):** H.N. 8:00 e H.D. 8:20 → os 20 min viram H.E. 0:20 e
> **crédito** no banco; ocorrência "Soma Banco Horas".
>
> **Exemplo (o mês):** H.D. (trabalhado) 181h e H.N. (previsto) 184h48 parece
> faltar hora — mas se houve uma **falta** de 8h38 no mês, ela é da **folha**, não
> do banco. Por isso o banco pode seguir positivo: ele só conta as horas a mais/a
> menos dos **dias trabalhados** (ver seção 6).

## 4. Como o banco de horas enche e esvazia
Todo dia trabalhado é comparado com a jornada:
- Trabalhou **a mais** → **crédito** ("Soma Banco Horas").
- Trabalhou **a menos** → **débito** ("Diminui Banco Horas").
- Trabalhou **igual** → não mexe no banco.

Duas proteções automáticas:
- **Tolerância** (normalmente 10 min): diferenças pequenas não contam.
- **Teto diário de 2h extras**: o que passa de 2h num dia pode ficar "retido"
  ("Excedente retido"), para avaliar à parte, em vez de inflar o banco.

> **Exemplo:** jornada 8h. Segunda 8h20 (+20); terça 7h45 (−15, já tirada a
> tolerância); demais dias certos → saldo do mês **+5 min**.

O **saldo** soma ao **saldo anterior** e segue acumulando. No "Resumo do Banco de
Horas": Saldo Anterior + Crédito − Débito = Saldo Atual.

## 5. O dia a dia: o que conferir todos os dias
**5.1 Acompanhar o espelho** — em **Ponto → Espelho**, veja os dias e o **status**
(Regular, Atraso, Falta, Incompleto, Justificado). Resolva na hora.

**5.2 Aprovar os ajustes pendentes** — em **Ponto → Ajustes**, aprove/rejeite os
pedidos de correção. **Enquanto houver ajuste pendente, o mês não fecha.**

**5.3 Resolver os dias incompletos** — dia "incompleto" = faltou uma batida. Ele
**não gera débito**, mas **trava o fechamento** até ser resolvido.

> **Exemplo:** entrada 08:03 e saída 17:46, sem o par do intervalo → "incompleto".
> Confirmando que trabalhou normal, lance a batida que faltou pelo ajuste e aprove.

## 6. Faltas: quando vai para a folha e quando compensar pelo banco
Ideia central: **falta e banco de horas são coisas separadas.**

**6.1 O padrão: a falta vai para a folha.** Se você **não faz nada**, a falta é
tratada na **folha** (desconta o dia + o DSR da semana) e o **banco não é mexido**,
**mesmo que a pessoa tenha saldo positivo**. Isso evita descontar duas vezes.

> **Exemplo:** pessoa com +10h de saldo falta um dia sem atestado. Sem ação: banco
> segue +10h e a **falta é descontada na folha**. O saldo não "paga" a falta sozinho.

**6.2 A falta justificada (atestado/abono).** Com justificativa válida, **abone** o
dia: ele fica **Justificado / F.J.** e **não desconta** (nem folha, nem banco).

**6.3 Quando você QUER usar o banco: a compensação de falta.** Transforma a falta em
**débito no banco** e **tira a falta da folha**. Para o botão aparecer:
- **Regime de banco de horas** ativo;
- **Acordo** vigente da pessoa com **"Autoriza compensação de falta"** ligado;
- A pessoa ter **saldo** suficiente (senão o banco fica negativo).

Passo a passo:
1. **Ponto → Apuração → Comp. Faltas**.
2. Na falta, clique **"Compensar"**.
3. **Autorizar** (gestor) → **Homologar** (RH, se acima do limite) → **Registrar
   ciência** (a pessoa concorda).
4. Vira **débito no banco** e a falta **sai** da folha.

> **Exemplo:** pessoa com +16h falta um dia de 8h e pede para descontar do banco.
> Com acordo e ciência, a compensação baixa o banco para +8h e a falta não entra na
> folha.
>
> **Atenção:** não dá para tomar o saldo de alguém sem concordância — por isso a
> compensação exige acordo e ciência. Sem isso, a falta vai para a folha (6.1).

## 7. Todas as situações de um dia (tabela de referência)

| Situação do dia | Como aparece | Banco | Folha | O que o RH faz |
|---|---|---|---|---|
| Trabalhou além da jornada (até 2h) | Soma Banco Horas / H.E. | + crédito | — | Nada |
| Trabalhou além de 2h no dia | Excedente retido | crédito até o teto | — | Avaliar o excedente à parte |
| Trabalhou menos (atraso/saída antec.) | Diminui Banco Horas / H.A. | − débito | — | Nada, ou justificar |
| Faltou sem justificativa | Falta / F.N. | intacto | desconta dia + DSR | Deixar na folha **ou** compensar (6.3) |
| Faltou com atestado/abono | Justificado / F.J. | intacto | não desconta | Abonar com justificativa |
| Faltou e foi compensada pelo banco | (compensação) | − débito | não desconta | Fazer a Compensação de Falta |
| Dia incompleto (faltou batida) | Pendência | não mexe (zero) | — | Ajustar/abonar antes de fechar |
| Domingo/feriado trabalhado | Hora extra 100% | crédito 100% ou pagar | — | Conferir |
| Sábado de equalização trabalhado | Compensado / H.C. | fecha a carga do mês | — | Conferir o sábado definido |
| Folga compensatória | Folga compensatória | − débito (da compensação) | — | Lançar a folga |
| Férias / afastamento / feriado | Protegido | intacto | conforme a regra | Registrar o evento |

> "DSR" = descanso semanal remunerado. A falta não justificada costuma fazer perder
> também o DSR da semana — por isso ela "pesa" mais na folha.

## 8. Fechamento do mês: quando fecha, o que trava e como fechar
**8.1 Quando fechar** — perto do fim do mês ou no começo do seguinte, depois de
resolver as pendências. Fecha **um mês por vez**.

**8.2 O que TRAVA o fechamento (pendências):**
- **Ajuste de ponto aguardando aprovação** → aprove/rejeite em Ponto → Ajustes.
- **Dia incompleto sem tratamento** → ajuste a batida ou abone o dia.
- **Dia muito curto sem motivo** → um dia bem abaixo da jornada (por padrão, 60 min
  ou mais a menos) sem folga, abono ou ajuste. Lance o que faltou ou justifique.
- **Espelho sem ciência** (quando a empresa exige) → falta a pessoa dar ciência.

> **Exemplo:** ao clicar em "Fechar Período", aparece "Bloqueado por pendências: 2
> dias incompletos e 1 ajuste pendente". Resolva os 3 e o botão libera.

**8.3 Passo a passo para fechar:**
1. Confira o **banco** em Ponto → Apuração → Banco Horas ("Apurar agora").
2. Se for o caso, faça as **compensações de falta** (6.3).
3. Em **Ponto → Apuração → Fechamento**, escolha a competência.
4. Sem pendências, clique **"Fechar Período"** e confirme.
5. O sistema trava o mês e gera os espelhos.

**8.4 Espelhos e ciência** — baixe o PDF de cada pessoa, envie e registre a
**ciência** (ou **ressalva**). A ciência dá validade ao controle de jornada.

**8.5 Reabrir um mês** — use **"Reabrir Período"** com o motivo. Espelhos não
confirmados são descartados; os confirmados permanecem. Corrija e feche de novo.

## 9. O acerto do banco de horas (fim do período)
O banco tem um **prazo de compensação** (ex.: 6 meses). No fim do prazo, além de
fechar o mês, acerte o saldo de cada pessoa conforme o acordo:
- **Saldo positivo:** vira folga, é **pago como hora extra**, ou é **zerado**.
- **Saldo negativo:** tratado conforme o acordo (desconto ou perdão).

Pela tela, em Ponto → Apuração → Banco Horas, use **"Movimentar"** (crédito/débito/
compensação) ou **"Editar Banco de Horas"** (ajustar o saldo anterior).

> **Zeragem em massa:** para muitas pessoas de uma vez, peça ao responsável técnico
> para rodar o procedimento em lote (com backup antes). Pela tela, só ajustes
> pontuais.

## 10. Checklists
**Todos os dias:** conferir o espelho e resolver incompletos cedo; aprovar/rejeitar
ajustes; abonar atestados.

**No fechamento:** zerar pendências; apurar o banco; decidir as faltas (folha ou
compensação); "Fechar Período"; enviar espelhos e colher ciência.

**No fim do período de compensação:** fechar o último mês; conferir saldos; acertar
(pagar, folga ou zerar).

## 11. Perguntas frequentes e erros comuns
- **"A pessoa tem saldo positivo; mesmo assim a falta foi para a folha. Certo?"**
  Sim. Por padrão a falta vai para a folha e o banco não é mexido. Para usar o
  saldo, faça a Compensação de Falta (6.3).
- **"Trabalhou menos no mês, mas o banco creditou. Como?"** Havia uma falta: ela é
  da folha, não do banco. O banco só conta as horas a mais/a menos dos dias
  trabalhados.
- **"O mês não fecha."** Há pendência (ajuste pendente, dia incompleto ou dia curto
  sem motivo). Veja o cartão de pendências.
- **"As horas da pessoa estão todas como extra."** Falta a **escala** dela — sem
  jornada para comparar, tudo vira extra. Atribua a escala.
- **"Quero descontar a falta do banco."** Use a Compensação de Falta (acordo +
  ciência). Sem isso, a falta fica na folha.
- **"Quando o excedente é pago em dinheiro?"** Quando passa do teto diário (acima de
  2h no dia) ou no acerto do período, se o combinado for pagar o saldo positivo.

---
*Em qualquer passo com dúvida, fale com o responsável pelo sistema antes de alterar
dados em massa.*
