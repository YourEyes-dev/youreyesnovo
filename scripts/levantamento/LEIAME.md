# Levantamento main x produção (somente leitura)

Descobre o que a `main` espera do banco e a produção ainda não tem. Foi feito em 20/10/2026.

1. Suba um Postgres 16 efêmero e aplique todas as migrations (como `qa-harness/rodar-local.sh`,
   sem apagar o banco no fim). Aponte `PS` em `1_extrair_esperado.py` para ele.
2. `RAIZ=<raiz do repo> python3 -I scripts/levantamento/1_extrair_esperado.py` grava as impressões
   digitais (tabelas, colunas, RLS, gatilhos, views, cron, enums, políticas, índices, restrições, funções).
3. `python3 -I scripts/levantamento/2_montar_consultas.py` monta 4 consultas de leitura
   (estrutura, políticas, índices/restrições, funções) para colar no SQL Editor da produção.

Limites: só enxerga objetos do schema `public`; compara existência (e, nas funções, o corpo por
hash; nas tabelas, a assinatura das colunas), não dados; script colado à mão pode gerar corpo
diferente só por comentário/formatação. Objetos que existem só na produção não aparecem
(use `docs/diagnostico_producao_vs_migrations.sql`).
