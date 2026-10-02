# Plano de Acerto do Banco de Horas — SUDOMED
### Documento para conferência da contabilidade/DP **antes** de qualquer alteração

> **Nada será alterado no sistema até este plano ser aprovado.** Depois de
> aprovado, cada passo é feito com **backup antes**, testado fora da produção, e
> conferido a cada etapa. Envolve meses já fechados e horas já pagas — por isso
> a validação da contabilidade é essencial.

---

## 1. O contexto (resumo)
- Fechamento do banco é **semestral**. Deveria ter sido em junho; por causa da
  implantação do sistema, foi feito **um mês atrasado (julho)**, e **só para
  quem já tinha 6 meses de casa** (o "Grupo A"). As horas desse grupo **foram
  pagas em julho** (contabilidade).
- Quem ainda **não** tinha 6 meses (o "Grupo B") **mantém o saldo** e segue
  acumulando, até fechar junto com todos em **dezembro/2026**.
- Os saldos do **sistema antigo** (até maio/2026) foram informados na planilha
  `HORAS_2026` e são a base do saldo "migrado".
- Já corrigimos um **bug** que recalculava o passado com a escala nova (ex.: a
  Natieli, que era 44h até agosto); agora o cálculo respeita a escala de cada
  período.

## 2. Fontes de dados usadas
- **Migrado (sistema antigo):** coluna TOTAL da planilha `HORAS_2026` (até maio).
- **YE (oficial):** cálculo do YourEyes a partir das marcações (junho em diante),
  já com o bug corrigido.

---

## 3. GRUPO A — ZERA no fechamento de julho → saldo **0** a partir de agosto
Esses colaboradores têm as horas **encerradas em julho** (já pagas). Resultado:
**saldo zero** e agosto passa a acumular do zero.

| Colaborador | Empresa | Saldo de julho (a zerar) | Observação |
|---|---|---|---|
| Adriana Medeiros da Silva | Barros & Nuernberg Eng. | +21h21 | migrado já no banco |
| Cleciane Beltrame | Barros & Nuernberg Eng. | +0h50 | migrado já no banco |
| Letícia Aparecida Vargas | Barros & Nuernberg Eng. | −2h18 | migrado já no banco |
| Luciana Karpovicz Lemos | Barros & Nuernberg Eng. | −11h04 | migrado já no banco |
| Luciani Marinho Almeida | Barros & Nuernberg Eng. | +15h14 | migrado já no banco |
| Marina Fernandes da Silva | Barros & Nuernberg Eng. | −3h59 | migrado já no banco |
| Paulo Eduardo de Souza Pires | Barros & Nuernberg Eng. | −7h32 | migrado já no banco |
| Aylyn Kiane Tavares | Nuernberg & Barros | 0 | já está zerado em julho |
| Deisi Rafaela da Silva Caliari | Nuernberg & Barros | 0 | já está zerado em julho |
| Carol Varela Zeredi | Sudoclin | 0 | já está zerado em julho |

> **Correção de data:** hoje o sistema zerou esse grupo da Barros em **agosto**
> (um mês errado), fazendo setembro começar zerado. O certo é **agosto começar
> zerado**. O acerto move a zeragem para **julho**.

---

## 4. GRUPO B — MANTÉM o saldo (migrado + trabalho real no YE)
Esses **não** zeram. O saldo correto = **saldo migrado** (sistema antigo) **+**
o que o YE apurar de junho em diante.

| Colaborador | Empresa | Migrado (sist. antigo) | Já no banco YE? | Ação |
|---|---|---|---|---|
| Luiza Gabrieli Buzanello Dierings | Nuernberg & Barros | **+13h29** | ❌ não | **somar** o migrado + reapurar |
| Juleide Gonzaga | Nuernberg & Barros | **+5h13** | ❌ não | **somar** o migrado + reapurar |
| Jaqueline Dalmolin | Nuernberg & Barros | **+6h26** | ❌ não | **somar** o migrado + reapurar |
| Vera Lucia Cordeiro da Cruz | Sudoclin | **+4h40** | ❌ não | **somar** o migrado + reapurar |
| Tania Mara Goldoni Lolle | Barros & Nuernberg Eng. | +3h39 | ✅ sim | só reapurar (migrado já está) |
| Kailaine Lopes de Meira | Barros & Nuernberg Eng. | +16h00 | ✅ sim | só reapurar (migrado já está) |
| Natiele Custodio de Meira | Barros & Nuernberg Eng. | — (admitida em jun) | ✅ (sem migrado) | só reapurar (agosto ≈ −9h10) |

> **Por que 4 precisam "somar":** as empresas Nuernberg & Barros e Sudoclin não
> tinham regime de banco quando o saldo antigo foi migrado, então o migrado ficou
> num trilho separado e **não entrou** no cálculo. Vamos lançá-lo como **abertura
> de junho** dessas pessoas e reapurar — aí o saldo fica migrado + trabalho real.
>
> **O número final de cada um do Grupo B** (migrado + apuração) será **gerado
> pela reapuração** e apresentado para conferência final **antes** de fechar —
> nenhum número é "cravado no escuro".

---

## 5. Demais colaboradores (não listados)
Quem **não** está nas tabelas acima (ex.: Cacilda, Fabieli, Mila, Suzana,
Pamela, e outros) **não é zerado** — mantêm o saldo normalmente. A reapuração
apenas recalcula com as regras corretas; nada é apagado.

---

## 6. Como será executado (depois de aprovado)
Por empresa, uma de cada vez, com **backup antes** e conferência depois:
1. **Reabrir** junho e julho (necessário porque estão fechados e é onde entra o
   acerto; as horas do Grupo A foram pagas em julho, então o registro deve
   refletir julho).
2. **Lançar o saldo migrado** como abertura de junho — só para Luiza, Juleide,
   Jaque e Vera.
3. **Reapurar** junho → mês atual (com o cálculo já corrigido).
4. **Zerar o Grupo A em julho** (encerramento semestral) → agosto abre em zero.
5. **Remover** as liquidações lançadas por engano em agosto (do Grupo A).
6. **Grupo B mantém** o saldo (migrado + apuração).
7. **Refechar** junho e julho.
8. Conferir os saldos finais de todos (A = 0; B = migrado + apuração) **antes**
   de considerar encerrado.

**Segurança:** cada passo é um script testado numa réplica do banco, com cópia
de segurança das linhas antes de qualquer alteração. A produção só é tocada por
script colado por você no SQL Editor, com conferência.

---

## 7. O que precisa da sua aprovação / da contabilidade
1. **Grupo A zera em julho** (lista do item 3) — confirmam que são exatamente
   esses e que as horas foram pagas em julho.
2. **Grupo B mantém** (lista do item 4) — confirmam os **saldos migrados**
   (13h29, 5h13, 6h26, 4h40 para Luiza/Juleide/Jaque/Vera).
3. Cientes de que **junho/julho serão reabertos e refechados** para registrar o
   acerto corretamente.
4. De acordo em **conferir os números finais do Grupo B** (gerados pela
   reapuração) antes do fechamento definitivo.

*Documento de planejamento — nenhuma alteração foi feita. Dúvida em qualquer
linha, me chame antes de aprovarmos.*
