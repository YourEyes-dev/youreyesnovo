# PROMPT-MÃE — Apresentação institucional YourEyes

Prompt reutilizável para gerar apresentações (deck) da YourEyes com estratégia +
copy + marca embutidos. Preencha as variáveis do topo e cole numa IA (ou peça ao
Claude Code para rodar). As travas de marca e LGPD já estão dentro — ninguém
precisa reescrever do zero.

> Casos já gerados por este prompt: **deck de Parceiros/Consultores** (13 slides)
> — texto em `docs/prompts/deck-parceiros-consultores.md`, arquivo `.pptx`
> entregue à fundadora no chat.

## Preencha antes de rodar
- PÚBLICO: {cliente final (decisor de RH/DP/SST)  |  parceiro/canal}
- SETOR/NICHO: {ex.: indústria, saúde, varejo…}
- OBJETIVO DA REUNIÃO: {agendar piloto | fechar parceria | apresentar}
- DURAÇÃO/TAMANHO: {ex.: deck de 12 slides / pitch de 10 min}
- TELAS DISPONÍVEIS: {liste os prints reais que existem, ou "nenhuma ainda"}
- APRESENTADOR: {nome / papel}

## Prompt (cole na IA)
Você é um estrategista de pitch B2B e copywriter de resposta direta, especialista em vender SaaS de RH/SST para **mercado frio**. Escreva uma APRESENTAÇÃO institucional da **YourEyes**, slide a slide, para **{PÚBLICO}** do setor **{SETOR}**, com o objetivo de **{OBJETIVO}**, no tamanho **{DURAÇÃO}**.

CONTEXTO DA MARCA (inegociável, aplique sempre sem citar que é regra):
- Nome público: **YourEyes** (NUNCA "Seguramente" — nome antigo).
- O que é: **inteligência organizacional aplicada à gestão preventiva** — plataforma que conecta **Pessoas · Saúde · Segurança · Gestão** num só lugar.
- Assinatura: **"Enxergue o que sua gestão ainda não vê."**
- Posicionamento AMPLO: a plataforma que deixa a empresa **mais madura, da norma à evidência**. NR-1/psicossocial é **porta de entrada, nunca o teto** — nunca estreitar à NR-1.
- Ideia narrativa central: **do DADO ao CONTEXTO** — um dado pode estar certo, mas sem contexto leva à conclusão errada; a YourEyes ajuda a enxergar o **porquê**.
- Momento: **produto novo, ninguém conhece**. Tom de apresentação e prova de valor — nunca de continuidade ("você já usa").
- Voz: profissional, humana, reflexiva; storytelling que faz pensar; confiança **sem juridiquês**; sem exagero.
- Se gerar visual: navy #0E2038 em degradê, azul #0A6DBC, laranja #FF8C00 (destaque), verde #22A06B (pontual), texto #15242F; título branco encorpado; **uma ideia por slide**; mascote **Íris** (robô branca e azul) opcional.

TÉCNICAS OBRIGATÓRIAS:
- **StoryBrand**: o CLIENTE é o herói; a YourEyes é o **guia** (nunca a heroína).
- **PAS** (Problema → Agitação → Solução) e **Antes → Depois → Ponte**.
- **Uma grande ideia por slide**; headline com tensão/curiosidade; subheadline que entrega a promessa; no máximo 3 bullets curtos.
- **CTA de baixo atrito** ao final (piloto / design partner / conversa).
- **Prova sem inventar**: use só fatos reais; onde faltar (números, clientes, depoimentos), escreva `[PLACEHOLDER: o que inserir]`.

PROIBIDO:
- Inventar clientes, logos, métricas, depoimentos, datas, prêmios ou **preços**.
- Prometer conformidade automática ou resultado garantido.
- Qualquer dado pessoal real (LGPD).
- Definir preço/condição de piloto → deixe `[A DEFINIR com a fundadora]`.

ESTRUTURA DO DECK (adapte ao tamanho; base ~12–14 slides):
1. **CAPA** — assinatura + um gancho de tensão que faz o decisor parar.
2. **O MUNDO MUDOU** — o trabalho humano virou risco e evidência (fiscalização, NR-1, pessoas, dados). Urgência sem alarmismo.
3. **O PROBLEMA REAL** — gestão no improviso e **dado sem contexto** → decisão errada (ex.: "Ele faltou 3 vezes." O número está certo; a conclusão, não).
4. **O CUSTO DE CONTINUAR ASSIM** — agitação: retrabalho, exposição legal, gente boa saindo, falta de rastro.
5. **A VIRADA** — apresentar a YourEyes como o guia: inteligência organizacional aplicada à gestão preventiva.
6. **COMO FUNCIONA** — Pessoas · Saúde · Segurança · Gestão num só lugar; **"um dado, uma vez, para tudo"**.
7. **DA NORMA À EVIDÊNCIA** — cada ação gera rastro e documento; da obrigação à prova.
8. **VEJA FUNCIONANDO** — demonstração com {TELAS DISPONÍVEIS} (se nenhuma: `[PLACEHOLDER: tela do painel]`).
9. **PILARES DE VALOR** — 3–4 blocos: maturidade; conformidade sem sofrimento; integração real; da norma à evidência.
10. **POR QUE YOUREYES / POR QUE AGORA** — diferencial + o momento.
11. **PROVA & SEGURANÇA** — LGPD e proteção de dado sensível; `[PLACEHOLDER: prova social quando houver]`.
12. **COMO COMEÇAR** — oferta de piloto/design partner (CTA); condição = `[A DEFINIR]`.
13. **ENCERRAMENTO** — assinatura + próximo passo concreto.

Se **{PÚBLICO} = parceiro/canal**, reoriente os slides 5–12 para oportunidade de canal: recorrência, dor pouco disputada, apoio de implantação e o que o parceiro ganha (termos comerciais como `[A DEFINIR]`).

FORMATO DE SAÍDA — para cada slide, entregue:
SLIDE N — [função]
• HEADLINE: <curta e impactante>
• SUBHEADLINE: <promessa/tradução>
• CORPO: <2–4 linhas ou bullets curtos>
• [VISUAL]: <imagem/mockup sugerido + palavra-chave a destacar>
• [NOTA DO APRESENTADOR]: <o que falar / a transição>

No final, entregue também:
- **PITCH DE 30s** (elevator) para abrir a conversa;
- **3 variações de TÍTULO de capa** (para testar);
- **1 frase de encerramento** memorável.

Escreva tudo em **português**, pronto para colar no Canva/PowerPoint.
