# docs/prompts — prompts e materiais de apresentação

Padrões reutilizáveis para gerar peças de comunicação da YourEyes sem reescrever
do zero. As travas de marca e LGPD já estão embutidas em cada prompt.

| Arquivo | O que é |
|---|---|
| `apresentacao-institucional.md` | **PROMPT-MÃE** — gera uma apresentação (deck) slide a slide. Preencha as variáveis do topo (público, setor, objetivo, tamanho, telas) e cole numa IA. |
| `deck-parceiros-consultores.md` | Texto-fonte do deck de parceiros/consultores (13 slides) já gerado pelo prompt-mãe. Versão editável do conteúdo do `.pptx`. |
| `gerar-deck-parceiros.js` | Gerador do arquivo `YourEyes-Parceiros.pptx` (pptxgenjs) a partir do texto acima, no padrão visual da marca. |
| `roteiro-video-parceiros.md` | Roteiros de narração (institucional ~2min40 · 16:9 e teaser ~35s · 9:16) para virar o deck em vídeo MP4 no PowerPoint/Canva. |

## Regerar o `.pptx` de parceiros

```bash
cd docs/prompts
npm install pptxgenjs        # só na primeira vez
node gerar-deck-parceiros.js # produz ./YourEyes-Parceiros.pptx
```

As 5 telas reais do sistema entram no slide 8 como imagens: abra o `.pptx` e
arraste cada print por cima da moldura rotulada correspondente (mapa no fim de
`deck-parceiros-consultores.md`). Prints não são versionados — são dados de tela
do sistema, ficam com a fundadora.

> Identidade da marca: ver `docs/GUIA_MARCA.md`. Nada aqui toca produção — é
> material de comunicação.
