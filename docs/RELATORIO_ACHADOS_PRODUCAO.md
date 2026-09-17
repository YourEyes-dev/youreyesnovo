# Relatório de achados — motor de QA na produção

**Data:** 17/09/2026
**Origem:** bateria do motor de QA executada **na produção** (só leitura, por
simulação com descarte). Cada achado tem um **código** rastreável (ex.: `ADM-092`).
**Este relatório não contém dado pessoal** — só contagens e a natureza do gap.

Estes NÃO são erros do motor nem "drift de teste": são **gaps reais de produto**
que o motor encontrou porque, na produção, ele roda contra **dados reais** (no
dev/sandbox davam "nada a auditar" por falta de massa). É o motor virando **radar
de conformidade**.

---

## Resumo executivo

| Severidade | Qtd | Temas |
|---|---|---|
| 🔴 Crítico (jurídico/compliance) | 5 | eSocial de admissão não sai; menor de idade admitido/em escala noturna; experiência acima do teto |
| 🟠 Alto (controle/dados) | 4 | Autoaprovação de ajuste de ponto; documentos órfãos; ASO admissional inexistente; admissão concluída com ASO inapto |
| 🟡 Médio (feature/jurídico) | 10 | Vale-transporte, intermitente, prazo determinado, piso CCT, retenção, retroativa, assinatura, regime rural, fechamento, cota |
| ⚪ Baixo | 5 | Checklist fixo, folga em minutos, cota PCD parcial, aprendiz, isolamento de expurgo |
| 🔧 Drift técnico (entrega pendente, não é achado de produto) | 2 | `ponto_diario_status_check` antiga; `converter_banco_horas_vencido` ausente |

> Severidade é **sugestão minha** para ajudar a triar — a palavra final é sua.

---

## 🔴 Críticos (risco jurídico/compliance)

### 1. eSocial S-2200 não é gerado — `ADM-092`
**10.541 admissões concluídas, 0 eventos S-2200 na fila de transmissão e 0
registro de log mencionando 2200.** O evento de admissão do eSocial simplesmente
não aparece. Isso é o coração da obrigação acessória da admissão.
**Sugestão:** investigar por que a conclusão da admissão não enfileira o S-2200;
é provavelmente o gap de maior risco da lista.

### 2. eSocial S-2190 (admissão preliminar) não existe — `ADM-093`
Decorrência do item 1: sem o caminho do S-2200, não há admissão preliminar
(S-2190), prevista no MOS para casos de contratação em cima da hora.
**Sugestão:** tratar junto com o item 1.

### 3. Admissão comum aceita candidato de 15 anos — `ADM-030`
O banco aceitou admissão **comum** de alguém com 15 anos na data de início —
**nada valida a idade contra a modalidade**. A CF (art. 7º, XXXIII) veda trabalho
a menores de 16, salvo aprendiz a partir de 14.
**Sugestão:** trava de idade mínima por modalidade na conclusão da admissão.

### 4. Menor pode ser alocado em escala noturna / função de risco — `ADM-031`
Nenhuma função cruza `data_nascimento` com risco da função ou turno — um
colaborador de 17 anos pode entrar em escala noturna ou insalubre (vedado ao
menor).
**Sugestão:** validação de idade × turno/risco.

### 5. Contrato de experiência aceito acima do teto legal — `ADM-041`
O banco aceitou 100 dias diretos e 60+45=105 dias com prorrogação — ambos acima
do teto de 90 dias.
**Sugestão:** validar duração/prorrogação do contrato de experiência.

---

## 🟠 Altos (controle interno / integridade de dados)

### 6. Ajuste de ponto aprovado pelo próprio colaborador — `PONTO-252`
**76 de 1.709 ajustes aprovados foram aprovados pelo PRÓPRIO colaborador.** O
ajuste altera a marcação; a autoaprovação anula o controle (quem pede não deveria
aprovar).
**Sugestão:** bloquear aprovação pelo mesmo usuário que solicitou; auditar os 76.

### 7. Documentos de admissão órfãos — `ADM-072` / `ADM-073`
**64 de 255 documentos de admissão (25,1%) estão sem `colaborador_id`** e **sem
`pasta_id`**, embora existam 14.096 pastas de colaborador na base. Mais: **8 de
10.541 admissões concluídas têm 60 documentos sem dono/pasta.** Documento de
pessoa admitida sem vínculo é risco de organização e LGPD.
**Sugestão:** corrigir o insert em `public.documentos` (grava `colaborador_id`
nulo) e um reparo dos órfãos existentes (com backup).

### 8. ASO admissional não existe como entidade — `ADM-020`
O único ASO do sistema é o de **retorno** de afastamento (`afastamentos.aso_retorno_*`).
Não há ASO **admissional** estruturado — peça central da SST na contratação.
**Sugestão:** modelar o ASO admissional.

### 9. Admissão concluída com ASO inapto e sem evento eSocial — `ADM-022`
A admissão concluiu mesmo com ASO **inapto** e sem gerar evento — o gatilho
`auto_criar_onboarding_admissao` olha só a mudança de status.
**Sugestão:** bloquear conclusão com ASO inapto.

---

## 🟡 Médios (feature / jurídico)

- **Vale-transporte não existe na admissão** — `ADM-021`. Nenhum campo de opção
  (trajeto/linhas) nem renúncia (Lei 7.418).
- **Contrato intermitente não existe** — `ADM-040`. Nenhuma coluna/função trata a
  modalidade (art. 452-A exige contrato escrito).
- **Prazo determinado não tem onde viver** — `ADM-107`. `tipo_contrato` é texto
  livre e não há campo de data de término.
- **Piso da CCT não é consultado** — `ADM-052`. `folha_cct.piso_salarial` existe e
  ninguém olha; a admissão grava qualquer salário.
- **Retenção/descarte de admissão inexistente** — `ADM-050`. O descarte existe no
  Ponto e no Hub, mas não na admissão (LGPD).
- **Admissão retroativa entra calada** — `ADM-051`. Sem justificativa (a coluna nem
  existe), sem marcação de exceção, sem alerta.
- **Conclusão não confere assinatura** — `ADM-070`. `finalizar_admissao_by_token`
  só troca o status; nada liga a assinatura.
- **Cota (recálculo) depende de digitação** — `EMP-050`. O total de empregados não
  conta das admissões; a cota pode ficar errada.
- **Regime rural inexistente (noturno)** — `PONTO-113`. O cálculo noturno aplica a
  regra urbana (22h–5h, 20%, ficta) a todos; o rural tem janela própria.
- **Falta abaixo da jornada não vira pendência** — `PONTO-477`. Um dia 333 min
  abaixo da jornada, sem folga/abono/ajuste, não aparece no fechamento.

---

## ⚪ Baixos

- **Checklist de documentos fixo no código** — `ADM-090`/`ADM-021` (`ensure_admissao_...`); não é parametrizável por empresa.
- **Cota PCD — metade boa, metade faltando** — `ADM-050`-família. O gatilho
  `recalcular_cota_pcd` funciona (2% e 4% nas faixas certas da Lei 8.213), mas há
  parte não coberta.
- **Aprendiz** — os campos existem em `empresa_cadastro` (min/max/atual) mas a cota
  não é calculada da mesma forma.
- **Folga compensatória não aceita minutos** — `PONTO-476`. Só folga de dia inteiro.
- **`ponto_expurgo_eventos` sem trava de cercado** — `PONTO-270`. Tabela do módulo
  sem a proteção de isolamento (relevante para o próprio QA).
- **`PONTO-HOM-C1`** — uma vigilância acusou "tenant com erro"; investigar.

---

## 🔧 Drift técnico (entrega pendente — NÃO é achado de produto)

Estes dois só precisam de entrega/alinhamento com o dev; não são gaps de negócio:

- **`ponto_diario_status_check` desatualizada** (10 rotinas: PONTO-131/300/301/310/
  311/320/321/322/330/394). A trava de status do `ponto_diario` na produção é mais
  **antiga** que a do dev — falta um valor de status que a feature passou a usar.
  **Correção:** alinhar o `CHECK` (entrega pequena, com backup).
- **`converter_banco_horas_vencido(uuid)` ausente** — `PONTO-354`. Função de feature
  do banco de horas que nunca chegou à produção. **Correção:** entregar a função.

---

## Como sugiro usar este relatório

1. **Triar por severidade** — o item 1 (eSocial S-2200) é o que eu olharia primeiro.
2. Cada correção vira **feature real na produção** (muda o app), então segue a
   disciplina da casa: desenvolver → testar → seu aprovado → produção, uma a uma.
3. Os dois itens de **drift técnico** eu já consigo preparar como entrega segura
   assim que você der o ok.
4. O motor continua rodando as demais famílias — cada uma deve revelar mais alguns
   achados, que eu acrescento aqui.

> Nada neste relatório alterou a produção. Tudo foi leitura. As correções só
> acontecem quando você decidir, item a item.
