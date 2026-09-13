# Guia de Marca — YourEyes (v1)

Fonte única da identidade da marca. Definido uma vez; a equipe de agentes e a
Central de Comando GTM injetam este guia automaticamente em toda peça (texto e
arte) — ninguém precisa repetir cores/tom/posicionamento a cada pedido.

> **Nome.** A marca pública é **YourEyes**. **"Seguramente" é o nome antigo**
> (o projeto nasceu como Seguramente e foi renomeado) — **não usar em peças novas**.
> A produção ainda roda em `seguramente.lovable.app`, mas a comunicação é YourEyes.

> **Referência viva:** o feed real **@youreyes.oficial** é a fonte de estilo
> (voz + arte). Em dúvida, olhar o feed.

## Essência
- **Assinatura/campanha:** *Enxergue o que sua gestão ainda não vê.*
- **O que é:** *inteligência organizacional aplicada à gestão preventiva* — uma
  plataforma que conecta **Pessoas · Saúde · Segurança · Gestão** num só lugar.
- **Ideia central do conteúdo:** do **dado** ao **contexto** — um dado pode estar
  certo, mas sem contexto leva à conclusão errada; a YourEyes ajuda a enxergar o
  *porquê*, não só o *quê*.
- **Posicionamento (amplo):** a plataforma que deixa a empresa mais madura —
  governança contínua do trabalho humano (RH, DP, SST, jornada, folha,
  documentos, cultura, metas), da norma à evidência. **NR-1/psicossocial é porta
  de entrada, nunca o teto. Nunca estreitar à NR-1.**
- **Público:** decisores de RH/DP/SST em pequenas e médias empresas.

## Mascote
- **Íris** — uma **robô branca e azul**, simpática e competente. O nome remete à
  íris do olho (**YourEyes** = visão, clareza). Já aparece no feed.
- **Uso:** boa em redes sociais e materiais leves; em peças institucionais é
  opcional. Não forçar.

## Estilo de conteúdo (o feed é a referência)
- **Formato-assinatura:** carrossel narrativo — abre com um **dado isolado** que
  induz a conclusão apressada → hipóteses → falta de **contexto** → a YourEyes
  ajuda a enxergar o porquê (ex.: *"Ele chegou atrasado 4 vezes"*).
- **Arte:** fundo navy/azul em degradê, foto cinematográfica de trabalho **ou**
  mockup do sistema; título branco encorpado com palavras-chave em **azul/laranja**;
  laranja como destaque/carimbo de tensão.
- **A arte final de qualidade sai do processo de vocês (designer/templates), não
  do gerador de IA "do zero"** — que não atinge esse nível. Papel dos agentes:
  **copy + roteiro de carrossel + briefing de arte** e preencher os **templates**
  (autofill).

## Cores
| Papel | Hex |
|---|---|
| Azul (principal) | `#0A6DBC` |
| Verde | `#22A06B` |
| Laranja (destaque/CTA) | `#FF8C00` |
| Navy (fundo escuro/autoridade) | `#0E2038` |
| Texto | `#15242F` |
| Fundo claro | `#F5F8F9` |

(São as cores do próprio sistema — `src/index.css` — em HSL.)

## Tipografia
- **Inter** (ou uma sem serifa limpa e profissional). Títulos com peso, corpo
  legível. Sem serifa decorativa.

## Tom de voz
Profissional, claro e **humano**. Confiança **sem juridiquês**. Direto ao ponto.
Sem exagero. **Nunca prometer conformidade ou resultado automático.**

## Pilares de mensagem
1. **Maturidade organizacional** — sair do improviso para a gestão com evidência.
2. **Conformidade sem sofrimento** — atende a lei/ISOs com experiência simples.
3. **Um dado, uma vez, para tudo** — integração real entre RH, DP e SST.
4. **Da norma à evidência** — cada ação gera rastreabilidade e documento.

## O que evitar
- Estreitar a promessa à NR-1.
- "Você já usa / já começou" (o mercado é frio; ninguém conhece a marca ainda).
- Nome antigo "Seguramente" em peça nova.
- Dado pessoal real (CPF, nome, atestado); promessa de resultado/conformidade automática.

## Como isto é reutilizado (para nunca repetir)
1. **Canva Brand Kit "YourEyes"** = o visual (cores, fontes, logo, Íris). Toda
   arte gerada com esse Brand Kit já sai on-brand. **`brand_kit_id = kAHU8P-jQu4`**
   (URL: https://www.canva.com/brand/kAHU8P-jQu4). É o padrão embutido no botão
   "Gerar no Canva" da Central de Comando GTM.
2. **Este guia** = o resto (nome, tom, público, pilares, do/don't). Injetado
   automaticamente pela Central de Comando GTM (constante `BRAND_PROMPT`) e pelos
   subagentes em `.claude/agents/`.

## Templates de post (método confiável de arte)
A arte no padrão do feed NÃO vem do gerador de IA "do zero" — vem de **preencher
um layout desenhado por vocês**. Método validado (09/2026):

1. **Molde** = um post real da YourEyes no Canva: design `DAHVA4RxENo`, página 1.
   **Versão atual do molde (09/2026):** manchete alinhada à ESQUERDA, **Íris à
   direita** com o mockup do sistema, e no rodapé o **logo YourEyes + a tagline
   "INTELIGÊNCIA QUE PROTEGE. VISÃO QUE ANTECIPA."** (fundo navy em degradê).
   > **Atenção:** o molde é editado ao vivo pela dona — o layout e os ids **mudam
   > quando ela mexe nele**. Já houve uma versão anterior (texto centralizado, Íris
   > à esquerda, sem logo/tagline, ids `LBgRTN2nQDQH9CvX / LB63FGmKFsrypyf2 /
   > LBRYlX7cfhbyKlwY / LBhbnGL1GGXXWFlQ`). **Sempre ler a cópia com `read-design`
   > para conferir os ids reais antes de trocar texto** — não confiar de cabeça.
2. Para gerar uma peça: **copiar** o molde (`copy-design`, só a página 1) →
   **ler a cópia** (`read-design open_transaction:true`) p/ pegar `page_id` e ids →
   **trocar os textos** (`edit-design` `replace_text`) → **commit** → **exportar**
   (`export-design` PNG). O layout, a Íris, o mockup, o logo e as cores ficam
   intactos; só o texto muda.
3. **Campos de manchete — versão atual do molde:**
   - `LBprgcHFYDgZpPgY` — gancho (linha branca de cima; ex.: "Cumpriu a norma?")
   - `LBpTmLDL9QyHycq3` — destaque 1 (palavra grande azul; ex.: "PROVE")
   - `LBh7CNbmW8v7LNQf` — linha 2 (branca; ex.: "cada ato com")
   - `LBWn0k2kBW9v3VN2` — destaque 2 (grande azul; ex.: "EVIDÊNCIA")
   (o `locator_id` real é `<page_id>-<esses ids>`; o `page_id` muda a cada cópia.)
   Limites de texto: destaque 1 cabe ~8 caracteres numa linha; destaque 2 quebra
   em 2 linhas se passar de ~11. Gancho e linha 2 são as linhas brancas menores.
4. **Tagline no molde × assinatura do guia — reconciliar.** O molde usa
   "Inteligência que protege. Visão que antecipa."; a Essência deste guia usa
   "Enxergue o que sua gestão ainda não vê." São duas linhas diferentes; decidir
   qual é a oficial (ou o papel de cada uma) com a dona.
5. **Posts já gerados por este método (09/2026):**
   - `DAHVBaOHlhY` — "Um dado isolado ENGANA sem o CONTEXTO" (do dado ao contexto)
   - `DAHVBJuPNfk` — "Cumpriu a norma? PROVE cada ato com EVIDÊNCIA" (norma→evidência)
   - `DAHVBAxKTYg` — "Dados em silos? UNIFIQUE RH, DP e SST num só lugar" (integração)
6. Conforme surgirem mais posts-modelo (carrossel narrativo, etc.), registrar cada
   molde aqui com seu id e seus campos.

## Organização no Canva (pastas + nomes) — padrão da casa

Regra: **nenhuma arte solta**. Todo criativo nasce dentro de uma pasta e com nome
padronizado, para uma equipe conseguir tocar sem se perder. A estrutura espelha o
fluxo da casa (produção → aprovação → aprovado → publicado):

```
📁 YourEyes — Social            (FAHVFLzXRoQ)
   ├─ 0. Referências & Marca    (FAHVFPZWA7w)  ← molde-mestre (36 modelos), logo, Íris, kit
   ├─ 1. Em produção            (FAHVFO8HB0c)  ← rascunhos sendo montados
   ├─ 2. Em aprovação           (FAHVFMFUneA)  ← aguardando o "ok" da Leiridiani (gate humano)
   ├─ 3. Aprovados — a publicar (FAHVFGpgW7I)  ← prontos/agendados
   ├─ 4. Publicados             (FAHVFLdvSXM)  ← histórico (subpastas por mês: 2026-09, ...)
   └─ 9. Descartados            (FAHVFBfa2Rk)  ← versões abandonadas
```

O **status vive na PASTA** (a peça se move de pasta conforme avança), nunca no nome.

**Padrão de nome de cada design:**
`AAAA-MM-DD · CANAL · PILAR · título-curto · vN`
Ex.: `2026-09-13 · IG · VISIBILIDADE · Você não protege o que não enxerga · v1`
- **CANAL:** `IG` (feed), `IG-STORY`, `LINKEDIN`, `REELS`.
- **PILAR** (o assunto): `CONTEXTO` (do dado ao contexto) · `EVIDÊNCIA` (da norma à
  evidência) · `INTEGRAÇÃO` (um dado, uma vez, p/ tudo) · `MATURIDADE` · `LGPD` ·
  `PESSOAS` · `VISIBILIDADE` · `DEMO` (post com tela do sistema).
- **vN:** versão; sobe a cada revisão aprovada (v1 → v2).

**Regras operacionais para a equipe:**
- Criou peça nova → nasce em **1. Em produção** com o nome já no padrão.
- Terminou → move para **2. Em aprovação** e chama a Leiridiani.
- Aprovada → **3. Aprovados**; depois de postada → **4. Publicados/AAAA-MM**.
- Reprovou/abandonou → **9. Descartados** (não apagar na hora; histórico ajuda).
- O molde-mestre (`DAHVA4RxENo`) **nunca sai** de *0. Referências* e não se edita
  para produzir peça — sempre se **copia** dele (ver seção do método acima).

> **Aprendizado (09/2026):** rascunho de cópia deixado **sem título e solto** na
> raiz pode ser limpo pelo Canva e some. Por isso: nomear e mover para a pasta
> **assim que criar**. (Os 3 primeiros posts de teste se perderam exatamente assim;
> os PNGs exportados sobreviveram, os designs editáveis não.)
