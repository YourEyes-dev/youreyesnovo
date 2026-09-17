# 13º Salário — entrega em HOMOLOGAÇÃO e depois em PRODUÇÃO

Referência: YE-DP-13-001. O módulo inteiro cabe em **um arquivo só**:
`docs/script_13o_ENTREGA_UNICA.sql`.

O fluxo é o da casa (decisão 09/2026), forward-only:

1. **HOMOLOGAÇÃO** (`fgsblefvdabgdouipigz`) — cole o arquivo, leia a conferência,
   rode a bateria de testes;
2. **PRODUÇÃO** (`diayjpsrcerycycyaxst`) — cole **o mesmo arquivo**. Nada é
   reescrito entre um ambiente e outro.
3. **Publicar no Lovable** — as telas vêm do código, não do banco.

## Por que um arquivo só

Eram nove scripts, e a ordem entre eles era o único jeito de errar: o script do
fechamento recriava o cálculo da parcela na versão anterior à política do
adiantamento, e a documentação de testes reinstalava sondas antigas por cima das
apertadas. Duas armadilhas reais, ambas encontradas em teste. No arquivo único a
ordem já vem embutida. Os nove continuam no repositório para consulta e para
reaplicar uma parte isolada, quando for o caso.

## Como aplicar

- Reserve ~15 minutos, fora do horário de fechamento de folha.
- Cole o arquivo inteiro no SQL Editor e execute uma vez.
- Se algo falhar, **nada é aplicado** — o editor roda tudo em uma transação. Nesse
  caso mande o erro e pare por aí.
- É idempotente: rodar duas vezes não quebra nem duplica.

## O que esperar na conferência

Uma tabela de **26 linhas**, agrupadas por passo:

| Passo | O que confere |
|---|---|
| 1 | apuração dos avos, médias e parâmetros por empresa |
| 2 | INSS, IRRF, lote, prazo legal, reabertura, unicidade da parcela viva |
| 3 | política do adiantamento valendo no cálculo e média física (Súmula 347) |
| 4 | varredura de alertas e geração de Plano de Ação |
| 5 | provisão, conciliação, 13º da rescisão e adiantamento nas férias |
| 6 | validação prévia e montagem do S-1200/S-1210 |
| 7 | aviso prévio projetado, Súmula 46, 31 casos documentados, sonda DEC13-070 |
| 8 | motivo CULPA_RECIPROCA e a trava dos dois erros da rescisão |
| 9 | agendamento diário da varredura |

**Esperado: 25 linhas OK.** A linha do passo 9 sai **OK** onde há `pg_cron`
(produção e homologação) ou **INFORMATIVO** onde não há — aí a varredura funciona
pelo botão da tela, e o próprio texto traz o comando que cria o agendamento.

Qualquer **FALTA** significa que aquele item não foi criado: pare e mande a tabela.

## Depois de aplicar: a bateria de testes

```sql
WITH rodada AS (
  SELECT qa_rodar_bateria('manual','financeiro/decimo-terceiro') AS id
)
SELECT r.codigo, r.situacao, left(r.obtido, 160) AS resultado
  FROM qa_resultados r, rodada
 WHERE r.execucao_id = rodada.id
 ORDER BY r.situacao, r.codigo;
```

Esperado: **31 passaram, nenhuma falha**. O DEC13-023 sai como
`nao_implementado` quando não há rubrica de adicional noturno, insalubridade ou
periculosidade cadastrada — o caso avisa isso em vez de fingir que passou. Em
produção isso é o esperado até o cliente cadastrar seus adicionais, e aí ele passa
a conferir as rubricas **reais**.

## O que fica de fora da produção

`docs/script_13o_rubricas_adicionais_demo.sql` cadastra rubricas de adicional
**fictícias** e serve só a homologação e teste. Em produção ele não faz nada — a
trava é o próprio identificador do projeto. Rubrica de produção é cadastro do
cliente.

## O que o script NÃO altera

Nenhum cálculo de 13º já gravado, nenhuma rescisão fechada, nenhum dado de
negócio. Tudo é `CREATE OR REPLACE`, `ADD COLUMN IF NOT EXISTS`, índice/gatilho
recriado e `INSERT ... ON CONFLICT`. A única remoção é a de configurações
duplicadas do 13º, e ela **copia as linhas antes** para
`backup_decimo_terceiro_config_<aaaammdd>`.

## Conferir o ambiente a qualquer momento

`docs/script_13o_conferencia_ambiente.sql` é somente leitura e diz, em qualquer
ambiente, o que já está lá e o que falta.

## Na tela, depois do Publicar

Financeiro → Folha → **13º Salário**: Calcular 13º → **Apurar** mostra os avos com
a memória mês a mês e a média com as competências somadas; a coluna **13º
integral** traz o valor cheio do ano e **Prazo legal** a data-limite da parcela.
Aba **eSocial** → bloco "13º salário — apuração anual" → **Validar 13º**.
Financeiro → **Rescisões**: o motivo **Culpa Recíproca (metade das verbas)**.

## Como este pacote foi conferido

- Réplica montada com o que a produção tem hoje (1.044 migrations, sem nada do
  13º, porque lá migration não chega);
- o arquivo único aplicado **três vezes seguidas** em uma transação, sem erro;
- o estado final é **idêntico** ao que as migrations produzem: mesmo md5 do corpo
  de todas as funções do módulo, mesmos 18 índices, 23 regras, 4 gatilhos e o
  mesmo vocabulário de motivos de rescisão;
- bateria do módulo: 30 passaram e 1 sem dado para conferir naquela réplica
  (nenhuma falha).
