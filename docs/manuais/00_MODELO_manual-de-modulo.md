# Modelo de manual de módulo — YourEyes

> Este arquivo é o **molde** que todo manual de módulo segue. Copie a estrutura
> abaixo ao documentar um novo módulo. O objetivo dos manuais é servir de
> **roteiro para gravação de vídeos** (comercial + tutorial de operação), por
> isso cada tela que aparece no vídeo tem um **marcador de print** dizendo
> exatamente o que capturar e com quais dados fictícios.

## Como ler os marcadores de print

Ao longo do texto você verá blocos assim:

> 📸 **PRINT 03 — Tela X**
> **Onde:** caminho no menu / aba / botão que abre a tela.
> **O que precisa aparecer:** os elementos que a câmera deve mostrar.
> **Dados fictícios na tela:** os valores de exemplo que devem estar visíveis.
> **Ação filmada (se for vídeo):** o clique/gesto que o narrador executa.

Cada print recebe um **número sequencial** dentro do módulo (PRINT 01, 02, …).
No fim do manual há um **checklist de todos os prints** para conferir na hora
da captura no ambiente de teste.

## Regras de dados fictícios (LGPD — vale para TODO print)

- **Nunca** capturar tela com dado real (CPF, nome, atestado de pessoa real).
- Empresa demonstração: **Empresa Staging LTDA**.
- CPFs sempre na faixa da casa: **900.000.0XX** (dígito verificador válido).
- Personas fictícias padrão (use as mesmas em todos os módulos para dar
  continuidade entre vídeos):

| Persona | Papel no sistema | Cargo | Departamento | CPF fictício |
|---|---|---|---|---|
| **Marina Alves** | Analista de RH (opera o sistema) | Analista de RH | Recursos Humanos | 900.000.001-75 |
| **Bruno Carvalho** | Gestor (aprova ajustes/férias) | Coordenador de Operações | Operações | 900.000.002-56 |
| **Camila Duarte** | Colaboradora (bate ponto) | Operadora de Produção | Operações | 900.000.003-37 |
| **Diego Freitas** | Colaborador (home office) | Desenvolvedor Full Stack | Tecnologia | 900.000.004-18 |
| **Eduarda Lima** | Colaboradora (financeiro) | Analista Financeiro | Administrativo | 900.000.005-07 |

> Onde o ambiente de teste hoje mostra "Colaborador 1, Colaborador 2…", vale
> renomear alguns registros para as personas acima antes de gravar — os vídeos
> ficam muito mais críveis. Os CPFs já batem com o seed de staging.

## Estrutura obrigatória de cada manual

1. **Cabeçalho** (nome do módulo, para quem é, onde fica no menu, uma frase).
2. **Por que este módulo existe / benefícios** (o gancho comercial).
3. **Conceitos-chave** (glossário curto dos termos que aparecem na tela).
4. **Pré-requisitos** (o que precisa estar pronto antes de usar).
5. **Mapa da tela** (as abas/áreas principais, visão de 30 segundos).
6. **Passo a passo por fluxo** (cada fluxo com objetivo, passos numerados,
   marcadores de print e o benefício daquele fluxo).
7. **Roteiro do vídeo comercial** (30–90s, foco em dor → solução → prova).
8. **Roteiro do vídeo tutorial** (operação real, passo a passo narrado).
9. **Checklist de prints** (lista de todas as capturas).
10. **Erros comuns / dúvidas frequentes** (o que o suporte mais responde).

O primeiro manual completo já escrito neste padrão é o
[`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md) —
use-o como referência de profundidade e tom.
