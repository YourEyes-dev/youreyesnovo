# ADM-103 — resíduo conhecido e aceito (admissões concluídas sem usuário)

**Data da decisão:** 28/09/2026
**Decisão:** aceitar e documentar (dono do produto).

## Contexto

O bloco ADM-101/102/103/108 (reconciliação de documentos de admissão) foi
portado para homologação e produção. Depois do backfill:

- **ADM-108** — verde (0 órfãos).
- **ADM-101/102** — verdes. As auditorias foram refinadas para contar só
  documento cujo dono **já é colaborador** (documento de admissão em curso, sem
  dono, é legítimo). O passivo resolvível foi reconciliado (40 documentos na
  produção). O motor instalado (gatilho na escrita + gatilho na conclusão da
  admissão) resolve os novos casos sozinho, daqui pra frente.
- **ADM-103** — reduzido de 8 → **3** na produção (4 na homologação). Os
  restantes **não** são reconciliáveis automaticamente.

## O resíduo do ADM-103

Os casos que sobram são **admissões marcadas "concluído" cujas pessoas nunca
foram provisionadas como usuário** (`usuarios_base`). O diagnóstico confirmou,
em todos, `existe_usuario_por_cpf = false` **e** `usuarios_mesmo_nome = 0` — ou
seja, não é CPF digitado diferente; simplesmente não há registro de usuário
para aquela pessoa. Sem dono cadastrado, o motor de reconciliação (que arquiva
o documento sob o colaborador) não tem a quem vincular.

Produção (referência por `admissao_id`; nome/CPF só no diagnóstico privado):

| empresa | admissao_id | docs no limbo |
|---|---|---|
| Euromed Ocupacional | `ccd3c775-ecd9-4aa8-a76b-6456f6c1e183` | 4 |
| SUDOMED ITAPEJARA | `fec16c18-3a7e-4dca-826b-37f5b5d00a14` | 9 |
| SUDOMED REALEZA | `beec0d8b-7d95-4a18-938f-40873775658e` | 7 |

Homologação tem os dois últimos (registros antigos, anteriores à separação dos
ambientes) mais um caso local (uma pessoa com duas admissões concluídas).

## Por que NÃO foi mascarado

Diferente do ADM-101/102 — onde "documento de gente ainda em admissão, sem
dono" é legítimo e a auditoria foi corrigida para não acusá-lo — no ADM-103 a
auditoria está **certa** ao apontar: são pessoas que já concluíram a admissão e
cujos documentos deveriam estar arquivados. O resíduo é sintoma de um gap de
**onboarding** (a conclusão da admissão não provisionou o usuário), não de
reconciliação de documentos. Esconder o número enterraria um achado real, então
a auditoria ADM-103 permanece contando esses casos.

## Estado esperado da auditoria (não é regressão)

- Produção: **ADM-103 = 3** enquanto essas 3 pessoas não tiverem usuário.
- Homologação: **ADM-103 = 4** (dado fictício, mais divergência de ambiente).

Ver esse número **não** indica regressão do módulo de documentos.

## Como fechar de vez (quando/se houver decisão)

Para cada pessoa da lista, uma das opções:

1. **Provisionar o usuário** (regularizar o cadastro do colaborador). Feito
   isso, basta rodar de novo `docs/script_adm_reconciliacao_backfill.sql` — a
   reconciliação acha o dono e arquiva os documentos sozinha, e o ADM-103 baixa.
2. **Aceitar como legado** (pessoa desligada/registro antigo): manter como está;
   este documento é o registro da decisão.

Fonte para a triagem privada (mostra nome e CPF, **não** circular):
`docs/diagnostico_adm103_residual.sql`.
