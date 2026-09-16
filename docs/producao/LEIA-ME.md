# Fila de entrega do Ponto para a PRODUÇÃO

18 passos, na ordem. Tudo pelo SQL Editor do projeto de produção, colando cada
arquivo **inteiro** e conferindo o resultado antes de passar ao próximo.

O conteúdo é **idêntico** ao que foi aplicado e conferido na homologação, onde a
bateria do Ponto fechou em **133 passou / 1 falhou / 0 erro**. O que estas
versões acrescentam é o que a produção exige: medição de volume em cada parte e
cópia de segurança onde há alteração de dado existente.

## A ordem

| Passo | Arquivo | Observação |
|---|---|---|
| 00 | `passo_00_retrato_antes.sql` | **Primeiro de todos.** Sem ele nada depois é comparável |
| 01 | `parte_01_travas_legais.sql` | |
| 02 | `parte_02_vinculo_na_chave.sql` | **Sozinha, em horário de baixo movimento** — ver abaixo |
| 03 | `parte_03_nsr_e_lotacao.sql` | |
| 04 | `parte_04_versionamento_e_memoria.sql` | |
| 05 | `parte_05_integridade_do_registro.sql` | |
| 06 | `parte_06_calculo_da_jornada.sql` | |
| 07 | `parte_07_intervalo_e_repouso.sql` | |
| 08 | `parte_08_banco_de_horas.sql` | |
| 09 | `parte_09_fechamento_e_folha.sql` | |
| 10 | `parte_10_conformidade_portaria_671.sql` | |
| 11 | `parte_11_art62_lgpd_plano_acao.sql` | |
| 12 | `parte_12_instrumentos_e_escalas.sql` | |
| 13 | `parte_13_atestados_e_ausencias.sql` | |
| 14 | `parte_14_correcoes_da_bateria.sql` | |
| 15 | `parte_15_pecas_sem_script_de_entrega.sql` | **Altera dado** — cria cópia de segurança |
| 16 | `parte_16_massa_da_bancada.sql` | |
| 17 | `passo_17_conferencia_efeito.sql` | O veredito final |

## Como ler a conferência de cada parte

Cada parte termina em uma tabela com no máximo três tipos de linha:

- **`peça faltando`** — a parte não chegou completa. **Pare** e me avise qual peça.
- **`volume`** — quantas linhas das tabelas vivas do Ponto mudaram. Em 15 das 16
  partes o esperado é **zero**: elas só mexem em estrutura. A parte 15 é a
  exceção e mostra quantas linhas guardou na cópia.
- **`RESUMO`** — termina em `OK` ou `CONFERIR`. Só siga adiante com `OK`.

Se aparecer uma linha de `conteudo alterado` numa parte que não deveria alterar
dado: pode ser movimento normal de cliente durante a execução (a produção está
viva). Confirme rodando a mesma parte de novo — ela é idempotente — e veja se a
linha some.

## A parte 02 merece cuidado especial

É a única com criação de índice único em tabela grande (`ponto_diario`). Ela
toma bloqueio de escrita enquanto o índice é construído, e o arquivo já traz
`lock_timeout` de 10 segundos: se não conseguir o bloqueio, ela desiste em vez
de segurar o sistema. **Rode-a sozinha, fora do horário de pico**, e repita se
o timeout estourar.

## Cópias de segurança

A produção não tem recuperação a um ponto no tempo. Por isso a única parte que
altera dado existente guarda antes as linhas afetadas:

- **Parte 15** → `backup_links_sem_prazo_AAAAMMDD`, com o comando de desfazer
  escrito no fim do próprio arquivo.

As outras 15 partes só criam ou substituem estrutura (função, gatilho, índice,
tabela nova). Não têm o que desfazer, e por isso não geram cópia.

## O que esta fila NÃO faz

- **Não preenche o NSR das marcações antigas.** O gatilho passa a numerar as
  novas; o preenchimento retroativo é um script à parte
  (`docs/script_ponto210_backfill_nsr.sql`), que altera dado e deve ser
  decidido separadamente.
- **Não muda tela.** Tudo aqui é banco. Peças que dependem de campo novo na
  interface só aparecem para o usuário depois de Publicar no Lovable.
- **Não instala a bancada de testes na produção.** A bateria continua rodando
  na homologação.

## Depois do passo 17

O veredito da conferência de efeito diz o que fazer:

- **`OK`** ou **`OK COM LISTA`** — passado intacto e travas ativas. Se vier com
  lista, ela é a mudança esperada no mês aberto: leve ao DP antes de fechar a
  competência.
- **`CONFERIR`** — falta trava: alguma parte não chegou completa.
- **`PARE`** — competência já apurada mudou. Não siga para a folha; me chame.

Feito isso, vale o roteiro humano: abrir o espelho de um colaborador conhecido
(tem que estar idêntico ao de antes), um feriado trabalhado, um dia de intervalo
curto, um colaborador com dois vínculos, o painel de alertas e um fechamento.

## Como esta fila foi ensaiada

Numa réplica local degradada de propósito ao formato da produção (chave da
apuração sem a empresa, sem adicional de feriado, sem folga compensatória, sem
motor de vigilâncias, sem gatilho de NSR, sem a apuração bruta), na ordem exata
acima:

- passo 00 tirou o retrato **antes** de qualquer parte;
- as 16 partes rodaram sem erro, cada uma terminando em `OK`, com **volume zero**
  em 15 delas e 3 linhas guardadas na cópia da parte 15;
- passo 17 fechou em **0 no passado, 0 travas ausentes**, listando apenas os dias
  do mês aberto que passam a ser apurados de outro jeito.

Nenhuma réplica reproduz a produção linha a linha. O que a fila garante é que
roda limpa nas formas de estrutura conhecidas, que cada parte diz o que chegou e
quanto dado tocou, e que o passo 17 compara com o retrato do próprio ambiente.
