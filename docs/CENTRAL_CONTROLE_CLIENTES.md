# Central de Controle de Clientes — o que já existe e o que falta

Tela do Super Admin em `/admin/controle-clientes` (menu: Qualidade e suporte).
Nasceu no lugar da antiga **Central de Testes**, que duplicava a Documentação de
Testes do módulo **QA e testes** — a duplicação foi aposentada em 09/2026.

Base: documento de requisitos "YourEyes — Central de Controle de Clientes
(Super Admin)", versão 1.0. Dois eixos:

- **técnico** — erros e exceções dos clientes em produção, com contexto
  suficiente para corrigir antes de o cliente reclamar;
- **negócio** — uso, inatividade, health score e gatilhos de cross-sell/upsell.

## O que já está na tela

- Estrutura dos dois eixos: indicadores no topo e as abas Incidentes, Saúde dos
  clientes e Fila de alertas (ainda vazias).
- **Clientes ativos** — único número real hoje (clientes com contrato ativo).
  O cartão é clicável e abre o **radar dos clientes**.
- **Radar dos clientes** (pedido do dono do produto, 09/2026): todos os clientes
  ativos em uma imagem só, um ponto por cliente.
  - **verde** = cliente sem erro registrado na janela;
  - **vermelho** = cliente com erro registrado;
  - **cinza** = cliente ainda sem monitoramento.
  - distância do centro = porte do cliente (mais colaboradores, mais perto do
    meio): o que está no miolo é o que dói mais quando quebra;
  - abaixo do desenho, a mesma informação em lista, com o nome de cada cliente.

  **Hoje todo ponto sai cinza, de propósito.** Sem captura de erro, pintar de
  verde seria afirmar "está tudo certo" sem ter conferido. O verde e o vermelho
  acendem sozinhos assim que a captura entrar: é só a situação do cliente deixar
  de ser `sem_sinal`.

## O que falta (próximas entregas, na ordem sugerida)

1. **Captura de erros** no frontend e no backend, com identificação do cliente,
   módulo, tela e ação — e **mascaramento de dados pessoais na entrada**
   (LGPD; sem isso a Central vira um problema de privacidade, não uma solução).
2. **Ingestão segura**: toda gravação por função do servidor, nunca escrita
   direta a partir da tela do cliente.
3. Agrupamento de erros por causa e a lista de incidentes por impacto.
4. Atividade por módulo (derivada das tabelas que já existem) e health score.
5. Motor de regras, fila de alertas, prazos e canais (in-app, WhatsApp, e-mail).

Enquanto (1) não existir, nenhum número da tela pode ser inventado: indicador
sem fonte fica em "—" e cliente sem monitoramento fica cinza.
