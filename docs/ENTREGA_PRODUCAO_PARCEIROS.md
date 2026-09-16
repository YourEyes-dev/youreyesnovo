# Entrega em produção — Programa de Parceiros (roteiro)

Aprovado pelo dono do produto em 04/09/2026 após conferência no ambiente de
teste. Nada aqui é automático: a produção só muda pelos dois gestos manuais
(script no SQL Editor de produção e Publicar no Lovable).

## Antes de começar

- Confirme que o SQL Editor aberto é o do projeto de **produção**
  (`diayjpsrcerycycyaxst`), não o de teste.
- Rode um script por vez, na ordem abaixo, esperando a linha de conferência
  de cada um sair com `OK` antes de colar o próximo. Cada script roda em UMA
  transação: se der erro, nada daquele script fica aplicado; corrija e rode
  de novo (todos são idempotentes).
- Selecione "No limit" no editor para não truncar a conferência.
- Nenhum dos scripts altera ou apaga dado de cliente; eles criam tabelas,
  funções e políticas do programa e semeiam a política de parceiros.

## Ordem dos scripts (SQL Editor de produção)

| # | Arquivo | O que faz | Conferência esperada |
|---|---------|-----------|----------------------|
| 1 | `docs/script_parceiros_onda1.sql` | Tabelas do programa, níveis, RLS, funções do SuperAdmin, casos de QA | `OK — Programa de Parceiros (Ondas 0 e 1) aplicado` |
| 2 | `docs/script_parceiros_onda2.sql` | Portal do parceiro (estágios, carteira, extrato), cadastro | `OK — Programa de Parceiros (Onda 2) aplicado` |
| 3 | `docs/script_parceiros_contrato.sql` | Versões do Contrato de Parceria (v1) e situação contratual | `OK — Contrato de Parceria aplicado` |
| 4 | `docs/script_parceiros_onda3.sql` | Motor de comissões, fechamento mensal (pg_cron), sugestão por localidade | `OK — Programa de Parceiros (Onda 3) aplicado` |
| 5 | `docs/script_parceiros_politica_v2.sql` | Política v2 (trilhas, matriz, ciclos de 24 meses, bônus, clawback), contrato v2 | `OK — Política v2 do Programa de Parceiros aplicada` |
| 6 | `docs/script_parceiros_onda4.sql` | Captura por link `?ref=`, atribuição automática, porta Meta Ads em standby | `OK — Onda 4 aplicada (Meta Ads em standby)` |
| 7 | `docs/script_youreyes_dados_fiscais.sql` | Cadastro único dos dados fiscais da YourEyes usados nos contratos | `OK — dados fiscais da YourEyes prontos` |
| 8 | `docs/script_parceiros_contrato_assinatura.sql` | Contrato em padrão ABNT com as duas partes e assinatura eletrônica completa | `OK` com `qa_pgp_016 = passou` |
| 9 | `docs/script_parceiros_aprovacao_portas.sql` | Aprovação em duas travas (contrato só após aprovar), faixa de indicação no site, porta livre de cadastro fechada (chave para reabrir), endereço do parceiro na assinatura | `OK` com `qa_pgp_017 = passou`, `qa_pgp_016 = passou`, `porta_livre_aberta = f`, `coluna_endereco = t` |

Prova realizada em 04/09/2026: os oito scripts foram executados nessa ordem
numa réplica local reconstruída até o estado atual da produção (migrations
anteriores ao programa) e todos devolveram `OK`.

## Depois dos scripts

1. **Publicar no Lovable** (as telas do site, do portal e do SuperAdmin já
   estão na `main`). O Publicar também reimplanta as Edge Functions
   `parceiro-cadastro`, `meta-leads-webhook`, `mercadopago-checkout`,
   `mercadopago-webhook` e `onboarding-signup`.
2. **SuperAdmin › Dados da YourEyes**: preencher razão social, CNPJ,
   endereço, e-mail, representante legal e foro. Sem isso o contrato sai com
   traços no lugar dos dados da contratada.
3. **SuperAdmin › Parceiros › Níveis e remuneração**: revisar os valores
   pré-preenchidos da política (vieram dos anexos do programa; são
   editáveis).
4. **SuperAdmin › Contratos**: conferir que o modelo "Contrato de Parceria
   Comercial (v2)" aparece na categoria parceria exigindo CPF, telefone,
   endereço, selfie e geolocalização.
5. Fazer um cadastro de parceiro de teste pelo site e assinar o contrato, para
   validar câmera e localização no domínio de produção (HTTPS obrigatório).

## Conferência rápida (SQL Editor de produção, depois de tudo)

```sql
SELECT (SELECT count(*) FROM public.parceiro_programa_config)            AS parametros,
       (SELECT count(*) FROM public.parceiro_niveis WHERE ativo)         AS niveis,
       (SELECT versao FROM public.parceiro_contratos_versoes WHERE vigente) AS contrato_vigente,
       (SELECT count(*) FROM public.contratos_aceite
         WHERE categoria = 'parceria' AND ativo AND requer_selfie)        AS modelo_parceria,
       (SELECT count(*) FROM cron.job WHERE jobname = 'parceiros-fechamento-mensal') AS cron_fechamento,
       (SELECT cnpj IS NOT NULL FROM public.youreyes_empresa WHERE id = 1) AS dados_fiscais_preenchidos;
```

Esperado: `parametros = 43`, `niveis = 9`, `contrato_vigente = 2`,
`modelo_parceria = 1`, `cron_fechamento = 1`; `dados_fiscais_preenchidos`
passa a `true` depois do passo 2.

## Entrega 2 (11/09/2026) — o que muda para quem já rodou os 8 scripts

Rodar só o script 9 e publicar no Lovable de novo. Efeitos:
- Representante e Operador: o painel vira "Cadastro em análise" até a aprovação;
  ao aprovar em SuperAdmin › Parceiros, o contrato é gerado e o parceiro recebe
  e-mail para assinar; o link só aparece depois da assinatura. Indicador segue
  automático (aprovado na hora → assina → link).
- Site: quem chega por `?ref=` vê a faixa "Você foi indicado por X"; o painel do
  parceiro oferece dois links (apresentação e contratar).
- "Cadastre sua empresa" (tela de login) deixa de criar empresa sem plano: leva
  aos planos. Para reabrir (ou preparar o teste grátis): SuperAdmin › Dados da
  YourEyes › Portas de entrada.

## Pendências que continuam do lado da casa

- Revisão jurídica do texto v2 do contrato (publicar nova versão pelo
  SuperAdmin quando houver ajustes; ninguém precisa reassinar até lá).
- Chaves do Meta Ads em `app_config` só quando existir campanha.
- Secret `QA_E2E_TOKEN` no repositório para os testes de tela reportarem no
  painel de QA.
