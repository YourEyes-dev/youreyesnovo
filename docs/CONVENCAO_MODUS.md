# Convenção de nomenclatura — Módulo de perfil comportamental

> Fonte da verdade da marca. Toda implementação futura e todo texto que
> circula seguem esta convenção. Mesma lógica do módulo de Férias (módulo
> "Férias", motor "INR™").

## A distinção fundamental

| | Nome | O que é | Onde vive |
|---|---|---|---|
| **MÓDULO** | **Mapa Comportamental** | Nome descritivo | Menu, rota, navegação, título interno |
| **INSTRUMENTO** | **MODUS™ — seu modo de operar** | Questionário, algoritmo e resultado | Relatório, tela do instrumento, material comercial |

As duas coisas **não se misturam**: o módulo é onde o usuário encontra; o
instrumento é o ativo de marca.

## Onde cada um aparece

| Superfície | Texto |
|---|---|
| Menu e navegação | Mapa Comportamental |
| Rota | `/mapa-comportamental` |
| Título interno do módulo | Mapa Comportamental |
| Marca do instrumento na tela | MODUS™ — seu modo de operar |
| Abertura do relatório | MODUS™ · Modo de operar, não medida de valor |
| Assinatura do resultado | "Seu MODUS é Estrategista-Racional" |
| Material comercial | MODUS™, o instrumento de perfil comportamental do YourEyes |

## Regras de uso da marca

1. **MODUS** é sempre em CAIXA ALTA e invariável. Nunca traduzir, flexionar
   ou usar como substantivo comum.
   PROIBIDO: "modus comportamental", "o modus dela", "os modus da equipe".
2. O símbolo **™** aparece **apenas na primeira menção de cada peça** (tela,
   documento, página). Nas menções seguintes, só MODUS.
3. **"modo de operar"** é a única forma aceita. Não usar como sinônimo:
   "estilo de trabalho", "jeito de agir", "forma de ser",
   "perfil de personalidade".
4. **Nunca** usar junto de MODUS: "teste", "avaliação psicológica",
   "perfil psicológico", "análise de personalidade", "diagnóstico".
   O instrumento é de **autopercepção e desenvolvimento**, não é
   psicodiagnóstico — e a linguagem precisa sustentar isso.

## Nomenclatura técnica

MODUS **não** entra em identificador de código. Marca pode mudar; esquema de
banco não deve mudar junto.

- Tabelas e colunas: prefixo do módulo (`mapa_comportamental_*`), sem a marca.
- Rotas, componentes e arquivos: seguem o nome do módulo.
- A marca entra como **valor de campo**, não como identificador, gravada em
  cada resultado e exibida no relatório e na memória de cálculo:
  - `instrumento_nome = 'MODUS'`
  - `instrumento_versao = '1.0'`

No código, esses valores vêm das constantes `MAPA_INSTRUMENTO_MARCA` e
`MAPA_INSTRUMENTO_VERSAO_LABEL` (`src/data/instrumentos/mapaComportamental.ts`)
e são expostos no campo `instrumentoNome` de `MapaResultado` e no snapshot de
auditoria (`instrumentoDefinicaoSnapshot`).

## O que NÃO muda

- Arquétipos: **Pioneiro, Conector, Guardião, Estrategista**.
- Motor de Decisão: **Racional, Relacional, Pragmático**.
- Modo de Contexto: **Constante, Cadenciado**.

## Escopo do ajuste (ao aplicar a convenção no repositório)

Substituir "Mapa Comportamental" por "MODUS" **apenas** onde o texto se refere
ao **instrumento** (questionário, algoritmo, resultado, relatório, material
comercial). **Manter** "Mapa Comportamental" onde se refere ao **módulo**
(menu, rota, conjunto de telas, título do módulo).

Na dúvida, **manter e sinalizar** para decisão humana. Não substituir em massa.
Identificadores de código (tabelas, colunas, rotas, componentes, arquivos) e
os valores já gravados/enum **nunca** mudam por conta da marca.
