# Fila de produção — as cinco correções da auditoria de DP

Roteiro para o **SQL Editor do projeto de PRODUÇÃO**. Dez passos, na ordem.
Cada arquivo é colado inteiro, roda sozinho e termina com uma conferência.
**Só siga para o próximo quando o anterior fechar OK.**

Se qualquer passo devolver `PENDENTE` ou `PARE`, pare de verdade e me mande o
resultado. Nenhum passo aqui altera ou apaga dado de colaborador; um passo que
dá erro se desfaz sozinho, porque o editor roda o arquivo inteiro em uma
transação só.

---

## O que estas correções fazem

Cinco achados de uma auditoria de fechamento feita por especialista em DP em
01/09/2026, sobre uma competência real:

| | achado | efeito |
|---|---|---|
| 1 | o minuto do registro sumia no truncamento | devolve ~4 h/ano por pessoa |
| 2 | a tolerância pesava só de um lado | sobras de 6 a 10 min passam a contar |
| 3 | espelho e banco de horas discordavam | uma fonte só; documentos param de se contradizer |
| 4 | dia incompleto virava débito; falta descontada 2× | as duas cobranças em dobro saem |
| 5 | o rótulo prometia 50% num crédito de 1:1 | o documento passa a dizer a verdade |

**Isto muda saldos.** Os itens 1, 2 e 4 alteram o saldo de competências ainda
abertas, **sempre a favor do trabalhador** — nenhum deles pode tirar minuto de
ninguém. O passo 08 mede exatamente quanto mudou, para quem, e acusa em letra
clara se algum saldo tiver piorado.

Vale avisar o DP da **Clínica Magalhães Lopes** antes: foi a competência
08/2026 dela que originou a auditoria, e é a que mais deve mudar.

### Uma lição da primeira execução em produção (01/09/2026)

A conferência do passo 02 **executava a sonda do PONTO-470** para provar a
correção. Rodar um caso de teste fora do cercado **grava a massa dele** — CPF
fictício, 550 minutos — e o passo 09 corretamente acusou isso como "passado
reescrito". Nenhum dado de cliente foi tocado: a linha era do inquilino de
testes. A conferência do passo 02 foi corrigida para apenas **ler** o registro
do caso, nunca executá-lo. Para rodar os casos de verdade, use a bateria do
módulo no ambiente de teste.

### Duas ressalvas descobertas no ensaio desta fila

**1. A correção do minuto (item 1) não mexe em dia que já está gravado.**
A apuração de saldo lê as horas já consolidadas em `ponto_diario`; quem lê as
marcações uma a uma é a consolidação diária. Então a correção passa a valer
para os dias consolidados **de agora em diante** — os dias já gravados só
mudam se a competência for reconsolidada, o que **reescreve `ponto_diario`** e
é uma decisão à parte, com cópia de segurança própria. Não está nesta fila de
propósito. O ganho de ~4 h/ano é daqui para a frente.

**2. Dia sem NENHUM registro continua debitando o banco.**
A correção do item 4 tira do banco a falta **registrada** (linha em
`ponto_diario` com situação `falta`). O dia em que o sistema não criou linha
alguma cai por outro caminho e segue debitando a jornada inteira. É a mesma
ausência, tratada de dois jeitos conforme a rotina diária tenha criado a linha
ou não — uma inconsistência real, que encontrei ensaiando esta fila. Corrigir
também esse caso mexeria em muito mais gente de uma vez, então preferi trazer
para a sua decisão em vez de ampliar a mudança por conta própria. Me diga se
quer que eu trate, e em que ordem.

---

## Os passos

| # | arquivo | o que faz | escreve? |
|---|---|---|---|
| 00 | `passo_00_retrato_antes.sql` | fotografa o que está **gravado** no Ponto (13 meses) | só em tabela de apoio |
| 01 | `passo_01_saldo_calculado_ANTES.sql` | fotografa o que a **conta responde** hoje | só em tabela de apoio |
| 02 | `passo_02_minuto_do_registro.sql` | correção 1 — o minuto do registro | só função |
| 03 | `passo_03_tolerancia_simetrica.sql` | correção 2 — tolerância nos dois sentidos | só função |
| 04 | `passo_04_fonte_unica_banco_horas.sql` | correção 3 — fonte única do banco de horas | só função |
| 05 | `passo_05_dia_incompleto_e_falta.sql` | correção 4 — pendência e falta fora do banco | só função |
| 06 | `passo_06_credito_um_por_um.sql` | correção 5 — crédito 1:1 e `tem_regime` | só função |
| 07 | `passo_07_saldo_calculado_DEPOIS.sql` | **o mesmo arquivo do passo 01**, rodado de novo | só em tabela de apoio |
| 08 | `passo_08_efeito_das_correcoes.sql` | compara 01 e 07: quanto mudou e para que lado | nada |
| 09 | `passo_09_o_passado_nao_foi_reescrito.sql` | confere que competência já apurada não mudou | nada |
| 10 | `passo_10_reparo_caso_353.sql` | registra o caso PONTO-353 na Documentação de testes | só tabelas `qa_*` |

O passo **10 só é necessário** se a conferência do passo 03 tiver acusado
`1 de 2 documentados`. Ele não mexe em cálculo nenhum: o PONTO-353 nasceu numa
migration que ficou de fora das 16 partes entregues em 08/2026, e o passo 03
tenta *atualizar* um caso que pode não existir — um UPDATE em zero linhas não
dá erro, só não faz nada.

Os passos 01 e 07 são **o mesmo arquivo**. Ele sabe sozinho se está gravando a
fotografia "antes" ou a "depois", e diz qual gravou.

A ordem entre 02 e 06 importa em um ponto só: **o 06 depende do 04**. O resto
pode ser conferido na ordem que estiver.

---

## O que esperar em cada conferência

* **00** — a contagem de linhas fotografadas, e `OK`.
* **01** — `antes | N colaborador(es) x competencia | OK`. Se vier
  `ATENCAO: nenhum colaborador entrou na fotografia`, pare: significa que
  nenhuma empresa está com o controle de ponto ligado, e aí nada disto tem
  efeito.
* **02 a 06** — uma linha por corpo de apuração encontrado, todas `OK`. A linha
  `ponto_saldo_dias_competencia ... só delega para o miolo` também é `OK`:
  quer dizer que naquele ambiente a apuração está partida em duas funções.
* **07** — as duas fotografias listadas, com `OK`.
* **08** — o resumo, o detalhe por empresa, as 20 maiores mudanças e o
  **VEREDITO**. Esperado: `OK — nenhuma correcao tirou tempo de ninguem`.
  No ensaio desta fila, um colaborador com uma sobra de 8 min e um dia
  incompleto rendeu **+188 min** devolvidos (8 da sobra + 180 do dia que
  deixou de virar débito). É essa a ordem de grandeza por pessoa afetada.
* **09** — a seção 1 (passado intacto) **sem nenhuma linha**. Estes cinco
  scripts não escrevem em `ponto_diario`, então competência já apurada não pode
  mudar; se mudar, é sinal de parar.
  A seção 2 (mês aberto) **vai ter linhas**, e é esperado: são os dias em que a
  reapuração passa a contar 1 ou 2 minutos a mais. É exatamente a correção do
  minuto aparecendo — confira com o DP, não é motivo para parar.
* **10** — `2 de 2 documentados; 2 com rotina ativa; OK`.

---

## Depois de tudo verde

Três coisas ainda faltam, e nenhuma delas é SQL:

1. **Publicar no Lovable.** As partes de **tela** das correções 3, 4 e 5 só
   chegam à produção assim: o aviso de apuração desatualizada, o rótulo
   "Pendência — marcação incompleta" e o "Soma Banco Horas (1:1)". Os números
   já estarão certos antes disso; o que falta é o documento dizer o que a conta
   faz.
2. **Conferir um espelho de verdade.** Emita o espelho e o relatório de banco
   de horas da mesma competência, para o mesmo colaborador, e confira que os
   dois trazem os mesmos Saldo Anterior / Crédito / Débito / Saldo Atual.
3. **Descartar as tabelas de apoio**, quando a conferência estiver aceita:

```sql
DROP TABLE IF EXISTS public.ponto_efeito_apuracao;
-- e, se o retrato da entrega anterior já não for mais necessário:
-- DROP TABLE IF EXISTS public.ponto_retrato_pre;
-- DROP TABLE IF EXISTS public.ponto_entrega_volume;
```

Guarde `ponto_efeito_apuracao` pelo menos até o próximo fechamento fechar sem
surpresa: é a prova documentada de quanto cada colaborador ganhou, e de que
ninguém perdeu.
