# AFAST-021 — recaída da mesma doença: efeito de responsabilidade em aberto (conhecido)

**Situação na bateria:** 🟥 Falhou (achado, não crash) — "metade boa, metade ausente".
**Natureza:** lacuna de recurso. **Não é bug** de código nem regressão. Fica
vermelho de propósito até a regra ser fechada — como ADM-103 e DESL-065.

## O que a auditoria cobra (art. 75/76 do Decreto 3.048; recaída em ≤ 60 dias, mesmo CID)

Afastou por uma doença, voltou, e em menos de 60 dias afastou de novo pela
**mesma** doença (mesmo CID). Isso é **recaída**, e a lei trata como
**continuação** do benefício anterior, não como afastamento novo:

1. os dias **acumulam** com o afastamento anterior;
2. a empresa **NÃO paga novos 15 dias** — a responsabilidade dos primeiros 15
   dias é do empregador **uma vez** por episódio; na recaída o INSS assume
   desde o 1º dia;
3. o **S-2230** (eSocial) sai já **no 1º dia** da recaída.

## O que já existe no motor (a "metade boa")

A **acumulação por CID em 60 dias** está implementada: a inteligência de
afastamento **soma os dias** do novo afastamento com o anterior quando o CID
se repete dentro da janela. Isso a auditoria confirma.

## O que falta (a "metade ausente")

O **efeito de responsabilidade** não está fechado: o motor ainda **não marca
explicitamente** que, na recaída, **não há novos 15 dias do empregador** (e,
por consequência, o encaminhamento ao INSS desde o 1º dia). Hoje entreguei o
apoio da **data do S-2230 na recaída** (`afastamento_prazo_recaida_s2230`), mas
a regra dos 15 dias do empregador não está materializada como decisão do motor.

## Por que fica como "conhecido" (e não corrigido agora)

Fechar isso é **mudança de comportamento de recurso** (afeta cálculo de
responsabilidade e o que vai à folha / ao INSS), então passa pelas **três
conferências da casa**:
1. mapear o impacto (folha, eSocial S-2230, telas de afastamento);
2. atualizar a Documentação de Testes (o caso AFAST-021);
3. atualizar a Execução de Testes (a rotina `qa_caso_afast_021`).

Enquanto essa entrega não é priorizada, a auditoria **continua acusando** (não
foi mascarada) — é o comportamento correto: o vermelho sinaliza uma regra
trabalhista ainda não garantida pelo motor.

## Como fechar quando for priorizado

Implementar, na inteligência de afastamento, a marcação de recaída que:
- reconhece o episódio como continuação (já acumula dias);
- **suprime os 15 dias do empregador** no episódio de recaída;
- garante o S-2230 no 1º dia (apoio de data já entregue).
Depois: atualizar `qa_caso_afast_021` para confirmar o efeito completo e
revalidar a bateria da família AFAST.

## Risco de deixar em aberto

Baixo/contido: hoje o sistema **não paga a mais sozinho** — a folha não lança
15 dias novos por conta própria; o risco é o operador tratar a recaída como
afastamento novo na mão. Documentado para que a decisão seja consciente.
