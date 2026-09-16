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

  Com a captura ligada (09/2026), o radar acende de verdade: verde é cliente
  sem nenhum erro nas últimas 24 horas; vermelho é cliente com erro no período,
  e a lista ao lado mostra quantos.

- **Captura de erros (eixo técnico) — no ar desde 09/2026.**
  - O que é capturado: tela que quebra (ErrorBoundary), erro não tratado da
    janela e promessa rejeitada. Cada evento leva empresa, área, tela, ação,
    horário, versão, navegador e a trilha dos últimos passos do usuário.
  - **Mascaramento antes de gravar** (`mascarar_pii`): CPF, CNPJ, e-mail,
    telefone, sequência longa de dígitos e valores de campo de segredo viram
    `[cpf]`, `[email]`, `[oculto]`… O navegador já mascara antes de enviar, e o
    servidor mascara de novo antes de gravar.
  - **Usuário pseudonimizado** (`pseudonimo_usuario`): dá para dizer "o mesmo
    usuário de novo" sem guardar quem ele é. O sal vive no `app_config` de cada
    ambiente, nunca no código.
  - **Uma única porta de escrita** (`registrar_evento_erro`): a tabela não tem
    política de INSERT, o papel `authenticated` não tem GRANT de escrita, a
    chamada sem sessão é recusada e há limite de 60 eventos por usuário por
    minuto.
  - **Agrupamento**: erros iguais (ignorando números e endereços) viram um
    incidente com contador; incidente resolvido que volta a acontecer reabre.
  - **Retenção**: evento bruto vive 90 dias, com expurgo agendado. Prazo a
    confirmar com o DPO.
  - **Leitura**: só superadmin, por RLS e por funções dedicadas
    (`central_incidentes`, `central_situacao_clientes`, `central_resumo`).
  - **Provas**: casos CENTRAL-001 a CENTRAL-005 na Documentação de Testes, com
    rotina no motor para cada um.

## O que falta (próximas entregas, na ordem sugerida)

1. **Erro de servidor**: hoje a captura cobre a tela. Falha dentro de Edge
   Function e de rotina do banco ainda não vira evento — entra com o mesmo
   caminho (`registrar_evento_erro`, origem `backend`) e com o número de
   correlação entre a tela e o servidor.
2. **Triagem na tela**: abrir o incidente, ver o detalhe técnico e a trilha do
   usuário, marcar em análise/resolvido, e "revelar" dado mascarado só com
   registro de quem revelou e por quê (RN-003/004).
3. **Atividade e inatividade por módulo** (derivadas das tabelas que já
   existem) e **health score** do cliente.
4. **Motor de regras e alertas**: limiares configuráveis sem publicação nova,
   prazos, escalonamento e canais (in-app, WhatsApp, e-mail) — sem dado pessoal
   nas mensagens externas.
5. **Gatilhos de cross-sell/upsell** a partir do uso contra o plano contratado.

Regra que continua valendo: indicador sem fonte fica em "—". Nada na tela é
simulado.
