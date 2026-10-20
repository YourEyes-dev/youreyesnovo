# Carga de demonstração — HOMOLOGAÇÃO

Empresa fictícia **Metalúrgica Exemplo Ltda** (tenant próprio, isolado de qualquer
cliente), com todas as telas do sistema preenchidas, para demonstrações comerciais.
O login `leirinuernberg@gmail.com` é ligado a esse tenant pela parte 00 (o vínculo
anterior fica em `backup_demo_vinculo_<aaaammdd>`, com o comando de desfazer no
fim da parte 00; o papel de SuperAdmin não é alterado).

## Como rodar
No SQL Editor do projeto de **HOMOLOGAÇÃO**, cole cada arquivo **inteiro**, um por
vez, **nesta ordem**, e confira que a última linha do resultado mostra `OK`:

`00 → 02a → 02b → 01a → 01b → 01c → 01d → 01e → 01f → 01g → 01h → 01i → 01j → 01k → 03a → 03b → 04a → 04b → 04c → 05a → 05b → 05c → 05d → 06a → 06b`

(A parte 01 — Ponto — vem **depois** da 02b porque respeita férias e afastamentos
já lançados.) Os arquivos 01b a 01e são os mais pesados (10 a 40 s cada na réplica
local); se o editor estourar o tempo, rode o mesmo arquivo de novo — é idempotente
e continua de onde parou.

Todos os arquivos recusam rodar fora da homologação/teste (conferem
`app_config.supabase_url`), são idempotentes e só tocam dados do tenant demo.
Não há dado real: nomes inventados, CPFs 900.000.0XX, e-mails `@metalurgica-exemplo.demo`.

## Antes da demonstração
Rode de novo `01e` (ponto do mês corrente) no dia da demonstração para completar os
dias recentes.

## Limites conhecidos
Arquivos (PDF, fotos, vídeos) não existem no storage: botões de download/visualização
não abrem arquivo. Textos de IA estão gravados prontos. Marketplace não foi semeado
(catálogo global, afetaria todos os clientes). Bugs do app encontrados durante a carga
estão listados no relatório da sessão.
