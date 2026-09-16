# Fila de entrega do Ponto para a HOMOLOGAÇÃO

Estas 16 partes reúnem, em ordem, as correções do módulo do Ponto que já estão
prontas e testadas no projeto e ainda não chegaram ao ambiente de homologação
(que é cópia da estrutura de produção). São os mesmos scripts de entrega que
vivem em `docs/script_ponto_onda*.sql`, agrupados por assunto para reduzir o
número de colagens de ~55 para 16.

## Como rodar

Cole cada arquivo **inteiro** no SQL Editor do projeto de homologação e execute.
**A ordem importa** — vá da parte 01 para a 16, conferindo o resultado de cada
uma antes de passar para a seguinte. Todas são idempotentes: rodar de novo não
quebra nem duplica.

Cada parte termina em uma conferência única, que lista o que deveria ter chegado
e diz o que faltou. O resultado esperado é a última linha com `OK`.

## As partes

| # | Arquivo | O que entrega |
|---|---|---|
| 01 | `parte_01_travas_legais.sql` | Marcação futura recusada; tolerância acima do teto legal, intervalo de CCT abaixo de 30 min e registro por exceção sem acordo passam a ser recusados no cadastro |
| 02 | `parte_02_vinculo_na_chave.sql` | **Destravador.** A empresa entra na chave da apuração diária (PONTO-394) — sem isto, dois vínculos colidem e várias partes seguintes nem conseguem gravar o dia |
| 03 | `parte_03_nsr_e_lotacao.sql` | NSR nas marcações (base do AFD) e histórico de lotação com vigência |
| 04 | `parte_04_versionamento_e_memoria.sql` | Parâmetro de escala com vigência (mudar hoje não reescreve o mês passado) e memória de cálculo |
| 05 | `parte_05_integridade_do_registro.sql` | Cadeia de hash conferível, desconsideração por acréscimo, marcações uniformes, Hora Legal Brasileira, reabertura formal de competência |
| 06 | `parte_06_calculo_da_jornada.sql` | Turno da virada, tolerância de 5 min por marcação, HE contra a jornada real da escala, adicional noturno prorrogado |
| 07 | `parte_07_intervalo_e_repouso.sql` | Faixas do art. 71, indenização da supressão parcial, pré-assinalação, DSR, domingo/feriado em dobro |
| 08 | `parte_08_banco_de_horas.sql` | Crédito só com instrumento vigente, prazo de compensação, alertas de vencimento e de teto, limite de 10h, ciclo 12x36, liquidação na rescisão |
| 09 | `parte_09_fechamento_e_folha.sql` | Espelhos gerados em uma transação, fechamento que confere ciência e pendências, pacote e fila da folha |
| 10 | `parte_10_conformidade_portaria_671.sql` | AEJ, validação e quarentena de AFD, comprovante como documento, certificado digital, dossiê de fiscalização |
| 11 | `parte_11_art62_lgpd_plano_acao.sql` | Enquadramento e descaracterização do art. 62, obrigatoriedade por estabelecimento, REP alternativo, trilha de acesso a dado sensível, ponte alerta → ação 5W2H |
| 12 | `parte_12_instrumentos_e_escalas.sql` | Vigilância de CCT, formalização da 12x36, turno de revezamento, troca de turno, radar de cobertura |
| 13 | `parte_13_atestados_e_ausencias.sql` | Atestados sobrepostos, ponte automática para o afastamento do INSS no 16º dia, comprovação do art. 473 |
| 14 | `parte_14_correcoes_da_bateria.sql` | Correções achadas pela própria bateria, inclusive o aviso repetido de atestado que derrubava o afastamento do INSS |
| 15 | `parte_15_pecas_sem_script_de_entrega.sql` | Peças que só existiam em migration e nunca tiveram script de entrega: um dia por data na apuração, adicional de feriado (RN23) com folga compensatória, motor agendado de vigilâncias, imutabilidade da marcação e prazo obrigatório do link |
| 16 | `parte_16_massa_da_bancada.sql` | Só a bancada: as ferramentas de massa procuram antes de criar, para uma sonda interrompida não deixar a execução seguinte presa em ERRO |

## O que esperar no fim

Depois da parte 16, rodando a bateria do módulo do Ponto na homologação, o
resultado esperado é o mesmo do projeto:

**133 passou · 1 falhou · 0 erro · 8 sem rotina**

A única falha é **PONTO-113** (regime rural — trabalho novo, ainda no backlog).

## Como isto foi conferido

As partes foram aplicadas, em ordem e duas vezes seguidas, a duas réplicas
locais: uma montada pelas migrations do projeto e outra com a chave antiga da
apuração diária (a mesma situação estrutural da homologação). Nenhum erro, e a
segunda passada não quebrou nem duplicou nada. Na réplica de chave antiga, a
bateria saiu de **109 passou / 7 falhou / 18 erro** para **133 passou / 1 falhou
/ 0 erro**.

As partes 15 e 16 nasceram do resultado da primeira rodada na homologação, que
caiu de 88 para 9 falhas. Para conferi-las foi montada uma terceira réplica,
degradada de propósito ao formato da homologação (sem o adicional de feriado,
sem a folga compensatória, sem o motor de vigilâncias e sem a apuração bruta):
ela saiu de **127 passou / 7 falhou** para **133 passou / 1 falhou / 0 erro**
com a parte 15 aplicada.

Nenhuma réplica reproduz a produção linha a linha; o que estas partes garantem é
que rodam limpas nas duas formas de estrutura conhecidas e que a conferência de
cada uma diz, no próprio ambiente, o que chegou e o que faltou.

## Produção

Nada aqui é para a produção. A produção só muda por gesto manual do usuário,
depois de conferido na homologação.

## Para a produção, depois

Dois scripts somente leitura acompanham a fila quando ela for para a produção:

- `docs/script_ponto_retrato_antes.sql` — tira a fotografia da apuração **antes**
  da primeira parte. Sem ela, nenhuma conferência posterior significa nada.
- `docs/script_ponto_conferencia_efeito.sql` — depois das partes, responde em
  três seções: o passado não foi reescrito, o que muda no mês aberto (e por
  quê), e se as travas estão ativas. Termina num veredito único.

Os dois foram ensaiados numa réplica degradada ao formato da produção: antes das
partes o veredito saiu `CONFERIR` com 5 travas ausentes; depois, `OK COM LISTA`
com o passado intacto. Adulterando o retrato de propósito, o veredito virou
`PARE` — a detecção funciona nos dois sentidos.
