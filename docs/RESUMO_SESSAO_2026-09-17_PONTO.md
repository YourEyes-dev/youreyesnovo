# Resumo da sessão de 16–17/09/2026 — Ponto: intervalo pré-assinalado, mapa dos ambientes e LGPD

Documento de passagem. Quem pegar o trabalho numa próxima sessão deve conseguir
continuar lendo só isto. Escrito em 17/09/2026.

---

## 1. Como esta sessão começou

O pedido original, em três itens, sobre o cartão-ponto de agosto/2026:

1. *"Configurei a opção de pré-assinalação, reprocessei o mês de agosto/2026, aparentemente
   o sistema não está considerando a pré-assinalação após ter sido reprocessado na
   contabilização de horas."*
2. *"A escala é das 08 às 17 com intervalo pré-assinalado das 12 às 13 (60 min). Olha como
   ficou o relatório."*
3. *"Nesse mesmo relatório, corrija a disposição dos campos que estão sobrepondo ao final
   do relatório."*

O item 2 foi **corrigido pelo próprio usuário** no meio do caminho: a escala real é
**segunda a quinta das 08:00 às 18:00 e sexta das 08:00 às 17:00**, e ele confirmou a
jornada pretendida — *"sim, 9h de segunda a quinta e 8h na sexta"*, ou seja **44h/semana**,
exatamente o teto do art. 7º, XIII da Constituição.

Essa correção invalidou o primeiro diagnóstico (que fora montado sobre "08 às 17") e
obrigou a refazer a análise. Fica o registro: **confirme a escala no banco antes de
diagnosticar**, não pela descrição verbal.

---

## 2. Os três ambientes (identidades confirmadas nesta sessão)

| | TESTE (staging) | HOMOLOGAÇÃO | PRODUÇÃO |
|---|---|---|---|
| Projeto Supabase | `bmehdgthciuvdbvutsdv` | `fgsblefvdabgdouipigz` | `diayjpsrcerycycyaxst` |
| Telas | ustudy123.github.io/youreyesnovo/**teste**/ | ustudy123.github.io/youreyesnovo/**homologacao**/ | seguramente.lovable.app |
| Como recebe | esteira automática a cada merge | script colado à mão | script colado à mão (+ ver §5) |

A identidade da homologação **não estava documentada em lugar nenhum** além de comentários
soltos de scripts — e essa falta produziu, no meio desta sessão, uma conclusão errada que
precisou ser desfeita em público. Agora está em `docs/AMBIENTES.md`.

**Regra que nasceu daqui:** toda consulta de diagnóstico deve carimbar o ambiente, lendo
`app_config.supabase_url`. Sem carimbo, uma tabela colada numa conversa não diz de onde veio.

---

## 3. O defeito e as três correções

### 3.1 O que estava errado

`ponto_jornada_do_dia` só descontava o intervalo quando o **próprio dia** da escala trazia
o trio `tem_almoco` + `inicio_almoco` + `fim_almoco`. Intervalo declarado por
**pré-assinalação** nunca era lido — a tabela nasceu marcada como *"metadado de exibição;
o motor de saldo não lê"*. Ficou pela metade: o cartão imprimia o "(P)" e a apuração
ignorava a declaração.

No cartão de agosto, quase todo dia:

```
Marcações 08:00 18:00 | H.D. 9:00 | H.N. 10:00 | H.A. 1:00
Ocorrência: "Atraso / saída antecipada"
```

O trabalhado (H.D.) estava certo; a jornada **prevista** (H.N.) vinha com a janela crua.
A diferença virava **1h de ausência por dia** e rotulava como atraso um dia integralmente
cumprido. No mês: **16:50 de ausência que nunca existiu**.

E foi por isso que as **sextas** saíam certas e o resto da semana não: naquele dia a escala
tinha a janela de almoço preenchida, nos outros não.

### 3.2 Correção do motor (entregue)

`ponto_jornada_do_dia` passa a descontar por precedência:
1. janela de almoço declarada no próprio dia;
2. minutos de intervalo no próprio dia;
3. **pré-assinalação vigente** (colaborador prevalece sobre escala).

**Não** há passo (4) caindo para `ponto_escalas.intervalo_intrajornada_minutos`, de
propósito: a tela cria toda escala com esse campo em 60 por padrão, então uma escala cuja
janela já exclui o almoço (08:00–16:00) passaria a perder mais uma hora.

- Migration: `supabase/migrations/20260916234512_ponto_jornada_desconta_pre_assinalacao.sql`
- Script de entrega: `docs/script_ponto_jornada_desconta_pre_assinalacao.sql` (pacote 57)

**Provado em réplica** com a escala real: antes 600/540 minutos (seg/sex), depois **540/480**
— as 44h. Não-regressão: escala 08:00–16:00 sem declaração continua em 480.

### 3.3 Correção do cartão-ponto (entregue)

Dois defeitos no PDF, ambos em `src/lib/ponto/cartaoPonto.ts`:

- A nota do intervalo declarado saía em **linha própria** em cada dia. Num mês de 31 dias
  isso dobrava a altura da tabela e estourava o espaço do rodapé. Passou a sair **ao lado**
  das marcações.
- O bloco final (legenda + assinaturas) era ancorado com `Math.min` — uma âncora **para
  cima**, que o imprimia por cima do resumo de horas, num documento feito para ser assinado.
  Agora, se não couber, abre folha.

Teste com dentes em `src/test/cartaoPontoPreAssinalacao.test.ts`: *"mês cheio com declaração
em todos os dias cabe em uma página"* — reprova com o código antigo (2 páginas).

### 3.4 Correção da tela de escalas (entregue)

A tela só sabia descontar intervalo **batido**. Com o intervalo **declarado**, somava a
janela crua: anunciava **10h/dia e 49h/semana** com alarme vermelho de estouro da CLT numa
escala que fecha em 44h — e gravava **588** em `jornada_diaria_minutos`.

- A conta saiu do componente para `src/lib/ponto/cargaEscala.ts`, onde pode ser testada.
- A tela passa a ler a pré-assinalação vigente por escala — a **mesma fonte** que
  `ponto_pre_assinalacao_do_dia` consulta no motor.
- O intervalo declarado aparece no dia marcado com `(P)` e o bloco de carga diz que já foi
  descontado.
- Salvar a escala grava **528** no lugar de 588.
- Testes em `src/test/cargaEscala.test.ts` (7 casos).

### 3.5 O número gravado na escala (pacote 58 — PRONTO, NÃO APLICADO)

`docs/script_ponto_escalas_regrava_jornada_declarada.sql` + migration
`supabase/migrations/20260916235640_ponto_escalas_regrava_jornada_declarada.sql`.

O motor não usa esse número quando há configuração por dia, mas ele vaza para:
1. **o AEJ** (Portaria MTP 671/2021, registro Tipo 4 "Horários contratuais") — declarar 9h48
   onde o contrato é 9h é erro de conformidade;
2. a base da **cobertura por atestado** e do **teto diário (RN17)**.

Só toca escala com configuração por dia + declaração vigente + número divergente. Escala
sem declaração **não** é tocada.

**Suspende o gatilho `trg_ponto_escala_arquiva_versao`** durante a regravação: isto não é
mudança de contrato (o contrato sempre foi 9h), e arquivar "9h48 vigorou até ontem"
afirmaria sobre o passado algo que nunca foi verdade, num arquivo que alimenta a apuração
de datas passadas. Religa no mesmo bloco; só mexe se o gatilho existir.

Provado em quatro cenários: escala com declaração 588/2940 → **528/2640**; sem declaração
600/3000 intacta; almoço batido 480/2400 intacta; zero linhas de versão criadas; segunda
passada não mexe; o comando de desfazer devolveu os valores originais.

---

## 4. O que aconteceu na produção

O usuário aplicou o **pacote 57 na homologação E na produção**. Duas consequências que
precisam ficar registradas:

1. **A apuração de competências antigas mudou na produção.** A apuração é calculada na hora
   a partir das batidas, então corrigir o motor muda também o resultado de competências já
   fechadas e já pagas — para os colaboradores com intervalo declarado. Essa mudança é a
   correção pretendida e o sentido dela é o certo (some a ausência fantasma de 1h/dia).

2. **A fotografia "antes" não chegou a ser tirada.** Existe
   `docs/script_ponto_producao_fotografia.sql` justamente para isso, e ele não foi rodado
   antes. O efeito, porém, é **calculável depois do fato**: em cada dia afetado a jornada
   prevista caiu exatamente os minutos declarados e o saldo subiu o mesmo tanto. **Montar
   essa lista, competência por competência, é um item pendente.**

---

## 5. A descoberta grande: o mapa dos ambientes estava errado

`docs/ROTEIRO_PRODUCAO_PONTO.md` assume que a produção **não recebe migrations** e marca 52
pacotes como pendentes. A medição desta sessão mostrou outra coisa.

### 5.1 Objetos do módulo Ponto (181 no projeto)

| | tem | falta |
|---|---|---|
| Produção | **176** | 5 |
| Homologação | 174 | 7 |

Faltam nos dois: `ponto_adicional_noturno_rural` (PONTO-113, regime rural),
`ponto_auditoria_ajustes_motivo`, `ponto_auditoria_motivos_resumo`,
`ponto_expurgar_geolocalizacao`, `ponto_expurgo_eventos`.
Só na homologação faltavam também `ponto_banco_horas_oficial` e
`ponto_reprocessar_pre_assinalacao`.

*(As duas últimas ausências de LGPD foram resolvidas — ver §6.)*

### 5.2 O registro de migrations da produção

`supabase_migrations.schema_migrations`: **534 carimbos**, o mais recente de **02/09/2026**.
Comparado com o repositório, mês a mês:

| mês | projeto | produção | |
|---|---|---|---|
| jan–mai | 400 | 399 | em dia |
| jun | 104 | 72 | 69% |
| jul | 146 | 24 | **16%** |
| ago | 233 | 36 | **15%** |
| set | 183 | 3 | **2%** |

**Existe um caminho automático até a produção**, o que a regra da casa nega. Ele funcionou
até maio, degradou em junho e praticamente morreu em julho. A explicação que os dados
sustentam: **o Lovable aplica na produção as migrations que ele mesmo gera**; migrations
escritas direto no repositório por sessões do Claude Code nunca passam por ele.

### 5.3 A ressalva que impede a conclusão fácil

Isso **não explica** o módulo Ponto na produção. Dos 182 objetos do Ponto, **155 nasceram
de julho em diante** — quando a via automática já estava em 16%. A produção tem 176 deles.
Logo: eles chegaram pelos **scripts de entrega colados à mão**. A fila da Travessia foi, na
prática, aplicada na produção; o que não foi feito é **anotar isso no roteiro**.

### 5.4 O que ainda NÃO se sabe — a pendência número 1

**Inventário confere nome, não versão.** Uma função pode existir com o nome certo e o corpo
antigo — foi exatamente a armadilha do pacote 56 (a produção tinha
`ponto_saldo_dias_competencia` com o nome certo e o motor monolítico por dentro).

`docs/script_ponto_raiox_motor.sql` olha **dentro** do corpo de nove funções e responde isso.
Na **homologação deu 9 de 9**. **Na produção ainda não foi rodado.** É a única coisa que
falta para reescrever o roteiro com o mapa certo.

---

## 6. O expurgo da geolocalização (LGPD) — ENTREGUE NOS DOIS AMBIENTES

A rotina não existia em ambiente nenhum: a coordenada das batidas era guardada sem prazo.
A marcação tem prazo de guarda próprio (CLT art. 74); a coordenada não, e a finalidade dela
se esgota quando a batida é conferida. Guardar as duas como se fossem uma é retenção além
do necessário (LGPD art. 15 e 16).

Entregue em **dois passos**, porque apaga dado pessoal de forma irreversível num banco sem
Point-in-Time Recovery:

- `docs/script_ponto_lgpd_geo_medicao.sql` — **só leitura**. Mede o alcance e confere a
  pré-condição.
- `docs/script_ponto_lgpd_geo_alvo_real.sql` — **só leitura**. O alcance pelo prazo **de
  cada cliente** (a primeira medição simulava 180 uniforme — era um furo).
- `docs/script_ponto_lgpd_geo_instalacao.sql` — instala e agenda. **Não expurga na hora.**

### A pré-condição que decide tudo

O hash de integridade da marcação **não pode depender da coordenada**. Se dependesse, zerá-la
quebraria a cadeia de todas as batidas antigas. Os arquivos conferem isso **no banco onde
rodam** e a instalação se recusa quando não vale. Conferido: `gerar_hash_marcacao` usa
cpf + data + hora + tipo + created_at — **não usa lat/long**.

### Imutabilidade

O gatilho `ponto_bloquear_update_marcacao` barra data, hora, tipo, CPF, colaborador e NSR —
e **não** barra as colunas de geolocalização. O expurgo convive com a imutabilidade por
desenho, não por acaso.

### Resultado real (17/09/2026)

| | homologação | produção |
|---|---|---|
| marcações | 5.939 | 6.952 |
| com coordenada | 3.641 | 4.557 |
| **anonimizadas na 1ª passada** | **2** | **2** |
| corte | 2026-03-21 | 2026-03-21 |

Registrado em `ponto_expurgo_eventos` nos dois (LGPD art. 37). **Nenhuma linha apagada,
nenhum hash alterado.** Agenda semanal ativa: **domingos às 04:41**. Prazo 180 dias por
cliente, ajustável entre 30 e 1825 em `ponto_retencao_config`.

### Por que não há cópia de resgate (exceção deliberada à regra da casa)

Copiar as coordenadas antes de apagá-las guardaria exatamente o dado pessoal que se quer
eliminar, numa tabela nova e sem política de acesso — o resgate viraria o problema. O
registro que a LGPD pede (art. 37) é de que o expurgo **aconteceu**, e disso cuida
`ponto_expurgo_eventos`.

---

## 7. Armadilhas aprendidas nesta sessão (candidatas ao CLAUDE.md)

1. **`CREATE TABLE IF NOT EXISTS` garante que a tabela EXISTA, não que tenha a FORMA
   esperada.** `ponto_retencao_config` já existia nos dois ambientes **sem chave única em
   `tenant_id`**; o `ON CONFLICT (tenant_id)` que vinha depois derrubou o arquivo inteiro.
   Em banco com deriva, script de entrega precisa **reconciliar forma**
   (`ADD COLUMN IF NOT EXISTS`, criar a constraint que faltar) e **preferir `WHERE NOT
   EXISTS` a `ON CONFLICT`**.

2. **O PostgreSQL não valida o corpo de uma função plpgsql na criação.** Um script pode
   instalar com "sucesso" uma função que quebra na primeira chamada. Script que substitui
   função com dependências novas precisa de **guarda de pré-requisito** com
   `to_regprocedure`/`to_regclass`.

3. **A conferência final não pode nomear tabela que talvez não exista** — o arquivo termina
   num `relation does not exist` em vez do aviso claro. Saídas: criar o objeto antes da
   guarda, ou usar `query_to_xml` dentro de um `CASE` sobre `to_regclass`.

4. **Cópia de resgate fora do bloco `DO`.** Se ficar dentro, o tratador de erro a desfaz
   junto e a conferência quebra.

5. **`EXCEPTION WHEN OTHERS` que engole a falha não pode terminar em "OK".** Registre o
   motivo (ex.: `set_config`) e faça a conferência dizer `FALHOU`.

6. **Simulação uniforme mente onde a configuração é por cliente.** A primeira medição do
   expurgo usou 180 dias para todos; a rotina lê o prazo de cada um.

7. **Toda consulta de diagnóstico deve carimbar o ambiente** (`app_config.supabase_url`).

8. **Confirme a escala no banco antes de diagnosticar**, não pela descrição verbal.

---

## 8. Arquivos criados ou alterados

### Código
- `src/lib/ponto/cargaEscala.ts` *(novo)* — a conta de carga da escala, testável
- `src/components/ponto/PontoEscalasTab.tsx` — usa a lib e lê a declaração vigente
- `src/lib/ponto/cartaoPonto.ts` — nota inline + bloco final nunca recua
- `src/test/cargaEscala.test.ts` *(novo)* — 7 casos
- `src/test/cartaoPontoPreAssinalacao.test.ts` — regressão de página

### Migrations
- `20260916234512_ponto_jornada_desconta_pre_assinalacao.sql`
- `20260916235640_ponto_escalas_regrava_jornada_declarada.sql`

### Scripts de entrega (para colar no SQL Editor)
- `docs/script_ponto_jornada_desconta_pre_assinalacao.sql` — **pacote 57** (aplicado nos dois)
- `docs/script_ponto_escalas_regrava_jornada_declarada.sql` — **pacote 58** (NÃO aplicado)
- `docs/script_ponto_lgpd_geo_medicao.sql` — só leitura
- `docs/script_ponto_lgpd_geo_alvo_real.sql` — só leitura
- `docs/script_ponto_lgpd_geo_instalacao.sql` — **aplicado nos dois**

### Diagnóstico (todos SÓ LEITURA, reutilizáveis)
- `docs/script_ponto_inventario_ambiente.sql` — os 181 objetos do Ponto, quais faltam
- `docs/script_ponto_raiox_motor.sql` — olha dentro do corpo de 9 funções
- `docs/script_ponto_registro_migrations.sql` — este banco recebe migrations do CLI?

### Documentação
- `docs/AMBIENTES.md` — identidade dos três projetos + a medição de 17/09
- `docs/ROTEIRO_PRODUCAO_PONTO.md` — pacotes 57 e 58 descritos e na fila

---

## 9. Estado do git

- Branch de trabalho: **`claude/oi-x3ulou`**
- Já mesclados na `main`: **PR #562** (motor + cartão), **#564** (tela de escalas),
  **#569** (pacotes 57 e 58)
- **Pendente de merge:** 9 commits na branch — os três scripts de diagnóstico, o
  endurecimento do pacote 58, o pacote LGPD completo e as duas atualizações do
  `AMBIENTES.md`

---

## 10. O que fazer na próxima sessão, em ordem

1. **Rodar `docs/script_ponto_raiox_motor.sql` na PRODUÇÃO.** É a única coisa que falta para
   saber se os 176 objetos estão com a **versão corrigida** ou só com o nome certo. Na
   homologação deu 9 de 9.
2. **Reescrever `docs/ROTEIRO_PRODUCAO_PONTO.md`** com o mapa real — hoje ele descreve um
   banco que não existe e marca como pendente o que já foi aplicado.
3. **Aplicar o pacote 58** (homologação, conferir, produção). Conferência esperada
   `t | t | t | 1 (ou mais) | OK`.
4. **Medir o que o pacote 57 moveu na produção** — a lista por competência, já que a
   fotografia "antes" não foi tirada.
5. **Levar as quatro ausências restantes** (auditoria dos motivos de ajuste ×2, adicional
   noturno rural) — sem urgência.
6. **Perguntar a quem cuida do Lovable** se a parada do caminho automático em 02/09 foi
   intencional ou quebrou. Enquanto estiver assim, tudo que é escrito direto no repositório
   só chega à produção pela mão do usuário.

### Pendências herdadas de antes desta sessão
- A "Travessia do Ponto" (roteiro de 52+ pacotes) — precisa ser refeita à luz de §5
- `converter_banco_horas_vencido` não está agendada em lugar nenhum: saldo de banco de horas
  vencido **não está sendo convertido sozinho**
- PONTO-113 (regime rural) — evolução de produto
- Benefícios: ondas B1–B3 / BEN-080
- Cinco escalas quase idênticas no cadastro do cliente (três com o mesmo nome
  "Administrativo" e jornadas diferentes) — limpeza de cadastro, decisão do usuário

---

## 11. Erros que eu cometi nesta sessão, para não se repetirem

- Diagnostiquei os itens 1 e 2 sobre a escala **descrita verbalmente** ("08 às 17") em vez da
  escala real do banco. O usuário corrigiu; a análise teve de ser refeita.
- Afirmei que a produção recusaria o pacote 57 por falta de pré-requisitos. **Estava errado**
  — ela os tinha, e o pacote aplicou de verdade lá.
- Tratei como vinda da produção uma tabela **sem carimbo de ambiente**, e construí uma
  conclusão sobre ela. Precisei desfazer em público. Daí nasceu a regra do carimbo.
- Sugeri que "boa parte do trabalho de transição pode ser desnecessária" antes de cruzar os
  dados. O cruzamento mostrou o contrário: a fila **foi** aplicada, à mão.
- Escrevi a medição do expurgo simulando 180 dias para todos, quando a rotina lê o prazo de
  cada cliente.
- Escrevi `ON CONFLICT (tenant_id)` sem conferir se a chave existia nos ambientes de destino.
