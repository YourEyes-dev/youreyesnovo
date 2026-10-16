# Rede de Segurança Diferencial

**O que é:** uma trava de QA que roda **antes do merge** (em todo Pull Request
para a `main`). Ela sobe um Postgres **efêmero** no runner, aplica **todas** as
migrations num banco vazio, roda o **Motor** (os `qa_caso_*`) em todos os
módulos, e compara o resultado com uma **linha de base versionada**
(`qa-harness/baseline.tsv`). Reprova o PR **só quando algo regride**.

**Por que existe:** o resto da esteira só roda **depois** do merge, contra o
staging — quando a quebra já entrou. E o Motor, sozinho, roda agendado e só
*mostra* o resultado numa tela; ele não *impede* a regressão de entrar. A Rede
move a detecção para antes do estrago e transforma o Motor na trava que faltava.

## O contrato (o que importa quando o sistema muda toda hora)

"Tudo verde" é **inatingível** de propósito: há ~770 casos documentados sem
rotina e lacunas de estrutura conhecidas (ausência, não bug). Então o alvo não
é "tudo verde" — é:

> **Nada que estava verde ficou vermelho.**

- **REGRESSÃO (reprova o PR):** um caso que era `passou` na baseline virou
  `falhou`, `erro`, `nao_implementado`, ou sumiu. Algo que funcionava parou de
  funcionar — ou perdeu a cobertura.
- **MELHOROU (só avisa):** `falhou`/`erro` → `passou`. Trave o ganho com
  `npm run qa:baseline`.
- **NOVO / REMOVIDO / demais transições:** informativo, nunca reprova.

Assim o sinal fica limpo: as lacunas conhecidas não apitam, e você só é
interrompida quando quebrou algo de verdade.

## Como rodar

Local (precisa de PostgreSQL 16 no PATH e **não** pode ser root — `initdb`
recusa root):

```bash
npm run qa:rede        # sobe banco efêmero, roda o Motor, compara com a baseline
```

No CI isso roda sozinho em todo PR para a `main`
(`.github/workflows/rede-seguranca.yml`).

### Atualizar a baseline — um gesto consciente

Quando você **de propósito** conserta uma lacuna (um caso passa a verde) ou
reestrutura casos, regenere a baseline e **versione a mudança no mesmo PR**:

```bash
npm run qa:baseline    # regrava qa-harness/baseline.tsv a partir de uma corrida limpa
```

O diff da baseline no PR mostra exatamente quais casos mudaram de estado — é
uma linha revisável, não um susto. **Nunca** regenere a baseline para "calar"
uma regressão que você não entendeu: aí a rede perde o sentido.

## Peças

| Arquivo | Papel |
|---|---|
| `qa-harness/preflight.sql` | Dá ao banco vazio a mobília do Supabase: papéis, schemas `auth`/`storage`/`extensions`, `auth.uid()/role()/jwt()`, `auth.users`, `storage.objects/buckets`. |
| `qa-harness/ext/pg_cron*`, `pg_net*` | **Extensões-falsas**: dão corpo a `cron.schedule`/`net.http_post` para as migrations atravessarem um Postgres puro. Nunca saem do runner. |
| `qa-harness/rodar-local.sh` | Orquestra: `initdb` → preflight → migrations → Motor → extrai o snapshot. |
| `qa-harness/rodar-motor.sql` | Dispara `qa_rodar_bateria` em todos os módulos. |
| `qa-harness/extrair-resultados.sql` | Um veredito por caso, ordenado (saída determinística). |
| `qa-harness/baseline.tsv` | A linha de base **versionada** (o "antes"). |
| `scripts/qa-diff-baseline.mjs` | O diff diferencial; sai 1 se houver regressão. |

**Regra de ouro:** as migrations **não mudam**. Tudo que falta para elas
rodarem num banco vazio mora no `preflight.sql` e nas extensões-falsas.

## Fidelidade — o que a Rede NÃO cobre (seja honesto com isto)

O banco efêmero roda o Motor como um papel **privilegiado** (o `postgres` de
bootstrap, que é superusuário e **ignora o RLS**). As rotinas simulam o usuário
só pelo GUC `request.jwt.claims` (não fazem `SET ROLE`), então os casos que
dependem do **RLS bloquear** um acesso indevido (isolamento entre empresas,
"documento legível sem login") **não são exercidos fielmente** aqui — eles
aparecem como `falhou`/`erro` na baseline e ficam de fora da garantia da Rede.

Hoje isso afeta um conjunto **enumerado e estável** de casos (família `MKY-*`
de visibilidade/RLS, `ISOL-*`, e alguns `PL*` que precisam de linha em
`auth.users`). Essa classe continua coberta **onde já estava**: a bateria do
Motor agendada no staging/produção (onde o papel não é superusuário), as
políticas `perfil_restringe_leitura_*`, e o Cypress.

> **Evolução v2 (anotada):** rodar o Motor sob um papel não-superusuário com
> RLS forçado tornaria essa classe fiel também. Fica para depois — exige cuidado
> para não quebrar a contabilidade do próprio Motor.

Outra ressalva: alguns casos comparam datas contra "hoje", então podem mudar de
estado com o tempo, sem mudança de código. Se um deles apitar sem você ter
mexido na área, confira e, sendo só efeito de calendário, regenere a baseline.

## Snapshot atual (referência)

Na primeira baseline: **766 `passou` · 7 `falhou` · 6 `erro` · 773
`nao_implementado`** (1552 casos, 74 módulos). Os 766 verdes são o que a Rede
protege automaticamente a cada PR.

## Onde a Rede se encaixa nas outras camadas

- **`qa:carimbos`** — carimbos de migration únicos (já existia).
- **`qa:cobertura-e2e`** — nenhum `it()` de Cypress sem caso documentado (já existia).
- **Rede de Segurança (esta)** — nenhum caso verde do Motor regride, antes do merge.
- **Esteira `staging.yml`** — aplica no staging + Cypress, depois do merge.
- **Motor agendado (`pg_cron`)** — varre staging/produção e reporta à tela de QA.
