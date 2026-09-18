# Ambientes YourEyes

Este projeto suporta três ambientes Supabase independentes: **produção**, **teste**
(staging) e **homologação**. Cada um tem seu próprio arquivo `.env`, e as URLs/chaves
são injetadas no build pelo Vite conforme o `--mode`.

| | TESTE (staging) | HOMOLOGAÇÃO | PRODUÇÃO |
|---|---|---|---|
| Projeto Supabase | `bmehdgthciuvdbvutsdv` | `fgsblefvdabgdouipigz` | `diayjpsrcerycycyaxst` |
| Como recebe mudança | esteira automática, a cada merge | **o mesmo script colado à mão** | script colado à mão |
| Estrutura | a do repositório | forward-only (ver decisão 09/2026 abaixo) | a real |
| Dados | fictícios | fictícios | reais |
| Responde a | "a mudança funciona?" | "o script aplica sem quebrar?" | — |

> **Decisão 09/2026 — a homologação deixou de ser recriada.** O fluxo passou a ser
> `desenvolvimento → homologação → produção`, forward-only: todo script de entrega
> é aplicado primeiro na homologação e depois, o MESMO, na produção. A homologação
> **não é mais recriada a partir da produção** (o RECRIAR abaixo está **suspenso**,
> não apagado). Motivo: recriar apagava a estrutura de testes já montada na tela do
> SuperAdmin — casos documentados, cobertura e mobiliário de QA (`qa_casos_teste`,
> `qa_cobertura_e2e`, `qa_implementacoes`, `qa_modulos`, agendamentos).
>
> **O que se perde com isso, e o que fica.** A homologação deixa de ser espelho
> fiel da produção e passa a divergir dela — some a garantia original de "o script
> aplica na estrutura REAL da produção?". O colchão que resta é a disciplina do
> próprio script de entrega (idempotente, `IF NOT EXISTS`, blocos `DO` com
> `EXCEPTION` por item). Nem tudo se perde num eventual recriar: **Cypress** vive no
> repositório (`cypress/e2e/*.cy.ts`, fora do banco) e o **motor de QA** vem das
> migrations; só os **casos documentados** (dados nas tabelas acima) seriam
> sobrescritos, porque hoje o `PRESERVAR_TABELAS` do gerador copia esses dados **da
> produção**, não mantém os da homologação.
>
> **Para voltar a poder recriar sem perder testes** (anotado, não implementado):
> **(A)** mudar o recriar para PRESERVAR as linhas dessas tabelas que já estão na
> homologação (dump antes de dropar o schema, restaura depois), em vez de copiá-las
> da produção; e/ou **(B)** tornar os casos parte do repositório — um helper que
> exporta `qa_casos_teste`/cobertura para uma migration-seed, fazendo do repo a
> fonte da verdade (aí recriar volta a ser seguro de graça). A casa já faz a B em
> parte, nas migrations `qa_*_casos_tela.sql`.

A homologação nasceu por causa de uma diferença que custou caro duas vezes: o teste
recebe tudo automaticamente e a produção só recebe o que é colado, então os dois se
afastam. Um script de entrega já abortou na produção por uma coluna que existia no
teste, e uma rotina de QA quebrou por funções auxiliares que nunca chegaram lá. Com
a decisão 09/2026 a homologação não é mais espelho da produção; a proteção contra
esse tipo de erro passa a depender da disciplina do script de entrega.

## Arquivos de ambiente

| Arquivo | Propósito | Está no Git? |
|---|---|---|
| `.env` | Ambiente ativo local/preview (produção por padrão). | Sim |
| `.env.example` | Template para novos desenvolvedores. | Sim |
| `.env.production` | Configuração do projeto Supabase de produção. | Sim |
| `.env.staging` | Configuração do projeto Supabase de teste. | Sim |
| `.env.homologacao` | Configuração do projeto Supabase de homologação. | Sim |

> **Sobre segurança:** esses arquivos estão **versionados de propósito** e só podem conter valores públicos — URL do projeto e chave anon/publishable (a mesma que qualquer navegador recebe). **Nunca** coloque neles `service_role`, senhas ou tokens privados; secrets vivem em `Project Settings > Edge Functions > Secrets`. Para sobrescritas locais privadas use `.env.local` / `.env.staging.local`, que o `.gitignore` ignora (regra `*.local`).

## Como alternar entre ambientes

### Para desenvolvimento local

Não copie arquivos: o Vite carrega o `.env.<modo>` automaticamente pelo `--mode`, sem tocar no `.env` (que é versionado e deve continuar apontando para produção).

```bash
# Produção (padrão)
npm run dev

# Teste (staging)
npm run dev:staging

# Homologação
npm run dev:homologacao
```

### Para build manual

```bash
# Teste (staging)
npm run build:staging

# Homologação
npm run build:homologacao

# Produção
npm run build:production
```

> Os scripts usam apenas `--mode`: nenhum deles sobrescreve o `.env`.

## Criar a homologação

> ⚠️ **SUSPENSO desde 09/2026 (ver "Decisão 09/2026" no topo).** Recriar a
> homologação a partir da produção APAGA a estrutura de testes já montada nela.
> O fluxo atual é forward-only (`desenvolvimento → homologação → produção`), e a
> homologação não é mais recriada. O roteiro abaixo fica registrado para o caso de
> um dia se implementar a preservação dos casos (opções A/B no topo); até lá, não
> use o RECRIAR numa homologação que já tenha testes montados.

Roteiro completo, na ordem. Só o passo 1 depende do painel do Supabase; o resto é
linha de comando e cópia de arquivo.

### 1. Criar o projeto

No painel do Supabase, crie um projeto novo (sugestão de nome: `youreyes-homologacao`).
Anote **Project URL**, **anon/public key** e o **project ref**.

> Escolha a mesma região da produção. Diferença de região muda latência e, em
> alguns casos, comportamento de fuso em função de data — e a graça da
> homologação é justamente não ter diferença nenhuma.
>
> **Na prática, não foi o que aconteceu:** a produção está em `sa-east-1` (São
> Paulo) e a homologação nasceu em `us-east-1`. Não é impeditivo e não há
> questão de LGPD, porque dado real nunca vai para lá — a cópia é só de
> estrutura. O custo é tempo: a corrida da esteira passou de ~2min30 para
> ~10min, porque cada um dos ~1300 comandos de limpeza atravessa o continente.
> A dúvida que vale conferir uma vez é o fuso: rode `SHOW TimeZone;` nos dois
> projetos. Se der o mesmo valor nos dois (é o esperado), não há diferença de
> comportamento a temer, só a lentidão.

### 2. Preencher `.env.homologacao`

Substitua os três placeholders pelos valores reais. O arquivo já está no
repositório com os avisos.

Há uma trava no `vite.config.ts`: se a URL apontar para o projeto de produção, o
build de qualquer modo que não seja `production` **não nasce**, com mensagem
explicando. Publicar um ambiente de teste sobre o banco real é o acidente que ela
existe para impedir.

### 3. Copiar a ESTRUTURA da produção — pela esteira, sem instalar nada

Este é o passo que diferencia a homologação do teste. Ela **não** nasce das
migrations: nasce de um retrato da produção, com o drift que a produção tem.

O retrato tem cerca de 2,4 MB — não cabe no SQL Editor. Mas também não precisa
de nada instalado na sua máquina: **quem faz o trabalho é a esteira do GitHub**,
igual ao que já acontece com o ambiente de teste. Você aperta um botão.

> Por que não usar o CLI do Supabase na sua máquina: `supabase db dump` roda o
> `pg_dump` dentro de um contêiner e exige Docker Desktop instalado. Instalar
> vários GB para um comando é desproporcional — a esteira já tem tudo.

#### 3.1. Criar o usuário somente leitura na produção

Cole `docs/script_homologacao_leitor_producao.sql` no SQL Editor da **produção**,
depois de trocar a senha na linha indicada.

Ele cria o usuário `homologacao_leitor_v2`, que **lê tudo e não escreve nada** —
não por configuração, mas por construção: recebe o papel `pg_read_all_data` do
PostgreSQL e nenhuma permissão de escrita. É o que mantém de pé a regra da casa
de que a produção nunca é alterada por esteira. Se a credencial vazasse, ainda
assim ninguém alteraria nada com ela.

A conferência do script mostra quatro linhas; todas devem vir `ok`.

#### 3.2. Guardar as duas senhas como secrets do GitHub

Em **Settings → Secrets and variables → Actions → New repository secret**, crie
**dois** secrets. Em cada um, o conteúdo é **só a senha** — nada de endereço,
nada de `postgresql://`, nada de usuário:

| Nome do secret | Conteúdo |
|---|---|
| `PRODUCAO_DB_PASSWORD` | a senha definida no passo 3.1 para `homologacao_leitor_v2` |
| `HOMOLOGACAO_DB_PASSWORD` | a senha do banco da homologação |

A senha pode ter **qualquer caractere**, inclusive `@` e dois-pontos.

> **Por que não há mais URL de conexão aqui.** As duas primeiras versões
> montavam `postgresql://usuario:senha@host/banco` — uma pedindo a string
> pronta, outra montando-a a partir de seis secrets. As duas falharam pelo
> mesmo motivo: quem lê uma URL procura o primeiro `@` para saber onde a senha
> termina, e a senha da produção tem um `@`. O endereço virava outra coisa, e o
> erro que aparecia falava de *host* desconhecido — mandava procurar longe da
> causa. A esteira não monta mais endereço nenhum: host e usuário vão em
> parâmetros separados, e a senha vai por `PGPASSWORD`, que aceita qualquer
> caractere literalmente.

Secret é campo protegido: o valor não aparece mais depois de salvo, nem nos logs
da esteira.

Se ainda existirem secrets de versões anteriores, faça a limpeza: **apague**
`PRODUCAO_DB_URL_LEITURA`, `HOMOLOGACAO_DB_URL`, `PRODUCAO_DB_USER` e
`HOMOLOGACAO_DB_USER` — não são mais lidos, e senha guardada sem uso é só risco
parado. Os de host (`PRODUCAO_DB_HOST`, `HOMOLOGACAO_DB_HOST`) pode manter: se
existirem, valem quando o campo do formulário for deixado em branco.

#### 3.3. Apertar o botão

No GitHub: aba **Actions** → **homologacao** → **Run workflow**. O formulário
pede três coisas:

| Campo | O que preencher |
|---|---|
| `confirmar` | a palavra `RECRIAR` |
| `host_producao` | `aws-1-sa-east-1.pooler.supabase.com` (já vem preenchido) |
| `host_homologacao` | o endereço do pooler da homologação |

Onde achar o endereço: no painel do projeto, botão **Connect** → bloco **Session
pooler**. Da string que aparece, copie **apenas o trecho entre o `@` e os
dois-pontos da porta** — termina em `.pooler.supabase.com`. Não use o de conexão
direta (`db.<ref>.supabase.co`): ele só atende por IPv6, e o GitHub não tem IPv6.

Os endereços ficam visíveis de propósito, no formulário e no log. Erro escondido
dentro de um valor secreto é erro que ninguém consegue conferir — foi assim que
as duas primeiras tentativas se perderam. A esteira confere cada endereço antes
de tentar conectar e recusa dizendo o que sobrou (um `@`, a porta, a URL
inteira, o endereço direto), e o passo seguinte prova as duas conexões antes de
qualquer trabalho pesado, dizendo **qual** das duas falhou.

A esteira não roda sozinha nunca — só por este botão. Não tem gatilho por push,
de propósito: se seguisse a `main`, a homologação viraria um segundo ambiente de
teste.

O que ela faz, e o que impede:

1. exige a palavra `RECRIAR` digitada;
2. **recusa rodar se o destino apontar para a produção** — o destino é apagado e
   recriado, então esta é a trava mais importante do arquivo;
3. lê a estrutura da produção com o usuário somente leitura;
4. **confere que nenhuma linha de dado veio junto** e aborta se vier — prova, não
   confiança, de que nenhum CPF, salário ou atestado saiu da produção;
5. recria o schema `public` da homologação com essa estrutura;
6. copia os dados com a identificação **embaralhada na leitura** (o plano de
   máscara é gerado por `scripts/homologacao/gerar_copia_mascarada.py` — o
   dado real nunca sai da produção) e prova, medindo, que nada identificável
   atravessou;
7. grava em `app_config` a URL e a chave anon **do próprio ambiente** (lidas
   do `.env.homologacao`, a mesma fonte do site) — as rotinas de disparo do
   banco passam a chamar a própria homologação, nunca a produção (a cópia
   chega com esses valores embaralhados, então sem este passo elas não
   chamam ninguém);
8. **publica as Edge Functions** no projeto da homologação (mesmo padrão da
   esteira do staging: CLI fixada + link + deploy com 3 tentativas). Roda
   também no modo `so_finalizar`. **Para só atualizar functions, porém, prefira
   o botão dedicado `homologacao-funcoes.yml`** (sem `RECRIAR`; ver **Manter a
   homologação em dia**) — este passo aqui existe porque a recriação também
   precisa dele. As chaves de plataforma o
   Supabase injeta sozinho; chaves de recurso (`OPENAI_API_KEY`,
   `RESEND_API_KEY`, `GITHUB_DISPATCH_TOKEN`...) são segredos do projeto,
   configurados no painel por quem decidir usar o recurso na homologação —
   sem elas, a function correspondente recusa com mensagem clara;
9. guarda o retrato e o log como anexo da corrida, por 7 dias.

> **Modo `mascarar = um_cliente` (o recomendado quando o embaralhamento
> atrapalha).** O formulário tem os campos `mascarar` e `cliente_real`. Em
> `um_cliente` + o `tenant_id` de um cliente, **só aquele cliente vem com
> dados reais**; os outros continuam embaralhados como sempre. Foi a escolha
> do dono do produto (08/2026) para o cliente SUDOMED ITAPEJARA
> (`83f1b040-c857-45a4-b71d-506e2a32d527`, 4 empresas), que é a própria
> operação da casa — não dado de terceiro.
>
> O recorte é por **cliente (tenant)**, e não por empresa, porque é o que o
> schema permite: `usuarios_base` — onde moram nome e CPF — tem `tenant_id` e
> **não** tem `empresa_id`. As pessoas pertencem ao cliente; a ligação com a
> empresa só existe via `admissoes`. Medido: 311 das 354 tabelas têm
> `tenant_id`, 86 têm `empresa_id`, e as 39 sem vínculo nenhum são catálogos
> públicos, motor de QA e configuração de plataforma — seguem 100%
> mascaradas.
>
> Três detalhes que o modo exige, e que só apareceram ao construir:
>
> - a trava de vazamento **exclui as linhas do cliente escolhido** da
>   medição. Sem isso ela leria os CPFs reais dele como fuga e apagaria a
>   cópia inteira — o oposto do pedido. Para todos os outros clientes o rigor
>   continua igual: máscara que falhar em qualquer um deles dispara o
>   apaga-tudo;
> - **superadmins ficam sem a senha compartilhada**, mesmo tendo e-mail
>   mascarado. Superadmin enxerga todos os clientes, então uma conta dessas
>   com `123456` seria a porta dos fundos para o dado real, anulando a
>   proteção;
> - colunas do tipo `json` (não `jsonb`) precisaram de tratamento separado:
>   com o embrulho condicional, os dois ramos do `CASE` têm que ter o mesmo
>   tipo, e a máscara devolvia `jsonb` (`CASE/WHEN could not convert type
>   json to jsonb`). Enquanto a máscara era a expressão inteira, isso passava
>   despercebido.
>
> **Modo `mascarar = nao` (cópia crua total).** Em `nao`, a cópia sai
> **idêntica à produção** — nome, CPF, e-mail e atestado reais de **todos**
> os clientes. Existe, mas o `um_cliente` cobre o mesmo caso de uso com uma
> fração da exposição.

### Sincronizar um cliente sem refazer a cópia

O botão RECRIAR resolve trazendo tudo de novo: apaga a homologação inteira e
reconstrói em ~40 minutos. Quem tem ensaio em andamento ou cadastro de teste
lá dentro perde tudo.

O workflow **`homologacao-sincronizar-cliente`** é o reparo no lugar da
demolição: lê da produção só as linhas de UM cliente, sem máscara, e
**atualiza só essas linhas** na homologação. Poucos minutos, e o resto do
ambiente fica exatamente como estava.

Formulário: `confirmar` = `SINCRONIZAR`, `cliente_real` = o `tenant_id`, e os
dois hosts de pooler. Exige o secret `HOMOLOGACAO_TESTADORES`, pelo mesmo
motivo do modo `um_cliente`.

**O que torna isso possível:** as chaves nunca são embaralhadas (a máscara só
toca texto, json e listas), então cada linha da homologação sabe qual linha
da produção é a dela. Medido: 353 das 354 tabelas têm chave primária de uma
coluna — a única sem chave (`ponto_entrega_conferencia`) fica de fora, e o
passo diz isso em voz alta.

**O que ela NÃO faz, de propósito: não insere linhas novas.** Registro criado
na produção depois da última cópia não existe na homologação, e criá-lo
exigiria respeitar a ordem das 627 chaves estrangeiras — o problema que a
cópia completa resolve derrubando todas elas. Em vez de inserir em silêncio,
a esteira **conta** quantas linhas não acharam par e avisa. Número relevante
= hora de rodar o RECRIAR completo com `mascarar=um_cliente`.

Dois cuidados que o desenho embute: os gatilhos são desligados durante a
sincronia (senão a auditoria grava um histórico que nunca houve e o
`atualizado_em` reescreve as datas), e `auth.users` é tratado à parte — mexer
no e-mail sem acertar a identidade junto deixa o login aceitando a senha e
devolvendo para a tela de entrada, sem erro claro.

Ao final, a esteira **prova que não passou do recorte**: conta as empresas de
outros clientes cujo nome não começa com `anon-` e reprova a corrida se
achar alguma.
>
> Isso muda a natureza do ambiente: ele passa a conter **dado pessoal e dado
> de saúde** (LGPD art. 11), num endereço que é página pública e num projeto
> fora do Brasil (`us-east-1`). Por isso a esteira **recusa** rodar sem
> máscara enquanto o ambiente não estiver fechado, e "fechado" tem
> significado verificável:
>
> - o secret **`HOMOLOGACAO_TESTADORES`** (e-mails reais de quem vai testar,
>   separados por vírgula) é **obrigatório** — sem ele a corrida aborta;
> - o secret `HOMOLOGACAO_SENHA_USUARIOS` **não pode valer `123456`** — com
>   e-mail real no banco, senha compartilhada conhecida transformaria a base
>   de clientes em base de credenciais. A corrida aborta se ele ainda existir
>   com esse valor;
> - **toda** conta recebe primeiro uma senha aleatória de 32 bytes que
>   ninguém vê; só depois os e-mails da lista recebem uma senha utilizável,
>   também sorteada, impressa **uma vez** no log da corrida e apagada do
>   banco em seguida.
>
> As conferências de máscara (CPF começando com 9, e-mail `.invalid`) são
> puladas nesse modo — elas provam que a máscara agiu, e não há máscara;
> mantidas, disparariam o apaga-tudo justamente porque o dado real chegou.
> No lugar delas o log registra quantas contas com e-mail real existem.
>
> **Decisões que continuam com o dono do produto**, e que a esteira não pode
> tomar: desligar o envio de e-mail do Auth no projeto de homologação (com
> e-mails reais na base, um "esqueci minha senha" ali alcançaria o cliente de
> verdade) e decidir sobre a região fora do Brasil.

> **O motor de QA atravessa intacto.** As tabelas `qa_modulos`,
> `qa_casos_teste`, `qa_implementacoes`, `qa_cobertura_e2e` e afins são
> documentação do sistema (códigos de caso, títulos, nomes de função SQL) —
> não têm dado de pessoa e são **preservadas por inteiro**, senão a tela de
> Testes automatizados quebra na homologação ("Cercado nao existe", módulos
> `anon-`). Pelo mesmo motivo, os cercados de QA (`tenants.slug` em
> `qa-sandbox`/`qa-sandbox-2` e as empresas `[QA] Alfa`/`[QA] Beta`) são as
> únicas linhas cujo texto passa sem máscara — são sintéticos por
> construção. O histórico de execuções (`qa_execucoes`/`qa_resultados`)
> continua mascarado de propósito: é texto livre escrito em tempo de
> execução e poderia ecoar valor real. Verificado em réplica local: com
> essas exceções, a bateria completa devolve na cópia mascarada exatamente
> o mesmo placar da base sem máscara.

#### 3.4. Conferir

**A esteira já confere sozinha.** O último passo mede os dois lados com
`docs/script_conferencia_homologacao.sql`, monta um quadro lado a lado e
**reprova a corrida** se qualquer medida divergir:

```
MEDIDA                     PRODUCAO  HOMOLOGACAO   SITUACAO
tabelas                         351          351   ok
indices                         855          855   ok
permissoes de tela             5643            0   diferenca esperada
```

São doze medidas: tabelas, colunas, visões, funções, políticas, gatilhos,
índices, índices inválidos, restrições, enums, valores de enum e permissões.
Verde significa cópia fiel; não há o que conferir à mão depois.

> Nem sempre foi assim. A esteira imprimia três números e pedia "compare com a
> produção". A comparação achou uma diferença real de um índice — mas só
> aconteceu porque alguém lembrou de fazer. Conferência que depende de gesto
> humano é conferência que uma hora não acontece.

Para conferir por fora mesmo assim, o mesmo arquivo roda no SQL Editor dos dois
projetos. É só leitura: rodar na produção é seguro, e rodar duas vezes não muda
nada.

Para uma conferência ainda mais completa, rode na homologação os scripts
`docs/script_divergencia_producao_parte1.sql` e `parte2.sql`. O resultado tem que
ser **igual ao da produção** — as mesmas tabelas faltando, as mesmas colunas, o
mesmo motor de QA incompleto.

Igualdade aqui não é defeito: é a prova de que a cópia é fiel. A homologação não
deve estar "certa"; deve estar igual à produção, defeitos e tudo.

> **A diferença esperada: as permissões.** A esteira roda o `pg_dump` com
> `--no-privileges`, então os `GRANT` para `anon` e `authenticated` — que é
> como as telas leem o banco — **não** são copiados. Na produção a linha
> "permissoes de tela" vem na casa dos milhares; na homologação vem zero.
>
> Isso decorre do que a homologação é hoje: um espelho de estrutura, para
> conferir se um **script de entrega aplica** contra a estrutura real. Não é,
> ainda, um ambiente onde se navega pelas telas — sem os `GRANT`, o
> `npm run dev:homologacao` conecta mas não lê nada. Se um dia a homologação
> precisar servir as telas, o caminho é copiar as permissões junto (tirar o
> `--no-privileges` do passo de leitura) e rodar a esteira de novo.

### 4. Semear dados fictícios

Use os mesmos padrões do teste: `Empresa Homologação LTDA`, CPFs da faixa
900.000.0XX com dígito verificador válido (o sistema valida DV). O volume não
precisa ser grande — a homologação não é ambiente de carga.

### 5. A partir daqui, só o gesto manual

**Nunca rode `supabase db push` na homologação.** Ela deixaria de ser cópia da
produção e viraria um segundo ambiente de teste — inútil, porque já existe um.

Daqui em diante ela recebe exatamente o que a produção recebe: o script colado no
SQL Editor. Na mesma ordem, com o mesmo conteúdo.

## Medição de 17/09/2026 — o que cada ambiente realmente tem

Feita com `docs/script_ponto_inventario_ambiente.sql`, `docs/script_ponto_raiox_motor.sql`
e `docs/script_ponto_registro_migrations.sql` (os três são somente leitura). Vale a pena
repetir de tempos em tempos: foi ela que mostrou que o roteiro de produção descrevia um
banco que não existia mais.

**Identidade.** Toda consulta de diagnóstico deve carimbar o projeto lendo
`app_config.supabase_url` — sem isso, uma tabela colada numa conversa não diz de onde
veio, e já custou uma conclusão errada aqui.

**Objetos do módulo Ponto** (181 no projeto):

| | tem | falta |
|---|---|---|
| Produção | 176 | 5 |
| Homologação | 174 | 7 |

Faltam nos dois: `ponto_adicional_noturno_rural` (PONTO-113, regime rural),
`ponto_auditoria_ajustes_motivo`, `ponto_auditoria_motivos_resumo`,
`ponto_expurgar_geolocalizacao` e `ponto_expurgo_eventos`. Só na homologação faltam
também `ponto_banco_horas_oficial` e `ponto_reprocessar_pre_assinalacao`.

> **Pendência de LGPD — RESOLVIDA em 17/09/2026.** `ponto_expurgar_geolocalizacao` e
> `ponto_expurgo_eventos` são a rotina de descarte da geolocalização das marcações. Não
> estavam em **nenhum** dos dois ambientes: a geolocalização era guardada sem prazo
> (LGPD art. 15 e 16). Entregue em dois passos —
> `docs/script_ponto_lgpd_geo_medicao.sql` (só leitura, mede e confere a pré-condição do
> hash) e `docs/script_ponto_lgpd_geo_instalacao.sql` (instala e agenda). Aplicado na
> homologação e na produção, conferência `OK` nos dois. Prazo de 180 dias por cliente,
> passada semanal aos domingos às 04:41.
>
> **A armadilha que esse script achou, e que vale para qualquer entrega futura:**
> `ponto_retencao_config` já existia nos dois ambientes **sem a chave única em
> `tenant_id`**. `CREATE TABLE IF NOT EXISTS` garante que a tabela EXISTA, não que ela
> tenha a FORMA esperada — e o `ON CONFLICT (tenant_id)` que vinha depois derrubou o
> arquivo inteiro. Em banco com deriva, script de entrega precisa **reconciliar forma**
> (`ADD COLUMN IF NOT EXISTS`, criar a constraint que faltar) e evitar `ON CONFLICT`
> onde a chave pode não existir — `WHERE NOT EXISTS` funciona nos dois casos.

**O registro de migrations da produção** (`supabase_migrations.schema_migrations`):
534 carimbos, o mais recente de 02/09/2026. Comparado com o repositório, mês a mês:

| mês | projeto | produção | |
|---|---|---|---|
| 2026-01 a 2026-05 | 400 | 399 | praticamente em dia |
| 2026-06 | 104 | 72 | 69% |
| 2026-07 | 146 | 24 | 16% |
| 2026-08 | 233 | 36 | 15% |
| 2026-09 | 183 | 3 | 2% |

Existe, portanto, **um caminho automático até a produção** — o que a regra da casa nega.
Ele funcionou até maio, degradou em junho e praticamente morreu em julho. A explicação
que os dados sustentam: o Lovable aplica na produção as migrations que **ele mesmo**
gera; migrations escritas direto no repositório por sessões do Claude Code nunca passam
por ele. À medida que o trabalho migrou do editor do Lovable para as sessões, a produção
parou de receber.

**Mas isso não explica o módulo Ponto na produção.** Dos 182 objetos do Ponto, **155
nasceram de julho em diante** — justamente quando o caminho automático já tinha caído
para 16%. A produção tem 176 deles. Logo, eles chegaram lá pelos **scripts de entrega
colados à mão**, não pela via automática. A fila da Travessia foi, na prática, aplicada
na produção; o que não foi feito é **anotar isso no roteiro**, que seguiu marcando tudo
como pendente.

**O que esta medição ainda NÃO responde.** Inventário confere nome, não versão. Uma
função pode existir com o nome certo e o corpo antigo — foi exatamente a armadilha do
pacote 56. O `script_ponto_raiox_motor.sql` olha dentro do corpo de nove funções e
responde isso; na homologação deu **9 de 9**. Na produção ainda não foi rodado.


## O fluxo de entrega com três ambientes

1. **Desenvolver** → merge na `main` → a esteira aplica no **teste**.
2. **Validar no teste**: a mudança funciona?
3. **Colar o script na HOMOLOGAÇÃO**: ele aplica na estrutura real? A conferência
   volta toda `ok`?
4. Só então **colar na produção**.

O passo 3 é o que muda. Ele custa dois minutos e responde à única pergunta que o
teste não consegue responder — porque o teste tem a estrutura do repositório, e a
produção tem a dela.

Se o script abortar no passo 3, você descobriu de graça o que teria descoberto na
produção com a operação parada.

## Manter a homologação em dia

A homologação envelhece igual à produção — e pelo mesmo motivo, se alguém colar um
script só na produção e esquecer dela.

- **Todo script de entrega passa pela homologação ANTES da produção.** É a ordem
  do fluxo forward-only (`desenvolvimento → homologação → produção`) e a regra que
  mantém a homologação à frente da produção sem nenhum trabalho extra. Nunca cole
  algo só na produção.
- ~~**A cada trimestre, aperte de novo o botão `RECRIAR`.**~~ **SUSPENSO desde
  09/2026** (ver "Decisão 09/2026" no topo): recriar apagaria a estrutura de testes
  da homologação. Enquanto a preservação dos casos (opções A/B) não estiver
  implementada, a homologação **não** é recriada — ela só anda para frente, pelos
  próprios scripts de entrega.
- **Cada tipo de mudança chega por um caminho diferente** (é o que substitui o
  antigo "recria tudo"):
  - **Telas** (o que se vê e clica): sozinhas, a cada merge — a esteira reconstrói
    e republica o site da homologação (`.../homologacao/`) junto com o de teste.
  - **Banco** (estrutura/dados): pelo **script de entrega** colado no SQL Editor da
    homologação, ANTES da produção (o fluxo forward-only).
  - **Funções de servidor** (Edge Functions): pelo botão **`homologacao-funcoes.yml`**
    (Actions → `homologacao-funcoes` → **Run workflow**, ~2 min). Ele republica as
    functions do repositório na homologação **sem `RECRIAR`** — não lê a produção,
    não recria o schema, não copia/apaga dados, não toca na estrutura de QA
    acumulada; alvo fixo na homologação, com aborto se o ref apontar para a
    produção. Reusa o mesmo passo de deploy provado no `homologacao.yml` e os
    mesmos secrets (`SUPABASE_ACCESS_TOKEN`, `HOMOLOGACAO_DB_PASSWORD`). É a porta a
    usar sempre que uma função nova/alterada precisar ir para a homologação (foi o
    que fechou os testes do Portal do Parceiro, presos em "sem rotina" porque a
    `seed-e2e-user` da homologação estava desatualizada).
- **Confira quando desconfiar:** os scripts
  `docs/script_divergencia_producao_parte*.sql` comparam qualquer ambiente com o
  repositório. Rodando os mesmos na produção e na homologação, a diferença entre
  os dois resultados é exatamente o quanto elas se afastaram.

### Casos de tela da homologação — fechados (09/2026)

Ao trazer o MarketYE e as fixtures profundas (Metas, Plano de Ação, GHE) para a
homologação, os casos verdes no teste passaram a rodar lá também. Restaram alguns
vermelhos **só na homologação**; todos investigados e fechados. Resultado final:
a bateria `cypress-homologacao` **#45** (commit `c41a2db`, PR #519) fechou
**37/37 specs verdes**. O que cada um era:

- **`PGP-031` (portal-parceiro — "copiar o link de indicação") — era DADO, não
  bug.** O `portal-link-principal` vinha vazio porque o parceiro-robô estava com
  **contrato de parceria pendente** (`parceiro_contrato_situacao().pendente=true`),
  e a tela só popula o link com contrato aceito. Corrigido no **seed** (andaime):
  `seed-e2e-user > semearRoboParceiro` passou a registrar o **aceite** da versão
  vigente do contrato (`parceiro_contratos_aceites`, idempotente por
  `UNIQUE(parceiro_id, versao)`). Hoje **3/3**.
- **`TRILHA-010` (trilhas — "cria uma trilha na Gestão") — era INSTABILIDADE, não
  bug.** O `[DIAG] [FALHA]` era só a **1ª tentativa**; o Cypress repetiu e a
  criação passou. Um diagnóstico temporário (`cy.intercept` no POST de
  `/rest/v1/trilhas`) confirmou que o **INSERT responde 2xx** na homologação — a
  trilha grava normalmente. O diagnóstico foi removido depois. Hoje **4/4**.
  - Achado colateral (código de produto, corrigido **com autorização do dono**):
    `TrilhaForm.handleSubmit` engolia a exceção num `catch {}` vazio. O usuário até
    via o toast de erro (vem do `onError` da mutation em `useTrilhas`), mas a falha
    não deixava rastro no console/telemetria nem era vista pelos testes. Trocado por
    `catch (e) { console.error(...) }`; comportamento preservado (diálogo segue
    aberto na falha). **Não era a causa** da falha do TRILHA-010.
- **`cargos.cy.ts` (CARGO-TELA-07 — "estado vazio ao buscar cargo inexistente") —
  era TESTE, não bug.** O registro de humor **"Como você está hoje?"** (psicossocial)
  abria durante o spec e travava o body (`data-scroll-locked` / `pointer-events:none`
  do Radix); o `cy.type()` na busca era recusado (falha intermitente, 1 de 7). Com
  um modal aberto o fundo fica inerte **de propósito** — comportamento correto do
  produto. Corrigido no teste com `{force:true}` nos `type()` da busca (mesmo padrão
  de `trilhas`/`mural`/`swot`/`incidentes`). **Risco latente global:** esse modal de
  humor pode abrir em qualquer página após o login e travar outros specs; se voltar a
  incomodar, vale um fechamento global do modal no login dos testes.

Aprendizado geral: a homologação também fica atrás da **base de dados de
referência**, não só do esquema recente. Ex.: as categorias-raiz do marketplace
(Fev/2026) nunca haviam sido semeadas ali — o que quebrava o MarketYE (MKY-021).
Corrigido por scripts de entrega (`docs/script_marketye_homologacao.sql` e
`docs/script_marketye_categorias_homologacao.sql`).

> **Princípio da cobertura de tela (Cypress) — não vai para produção.** Os specs
> `cypress/e2e/*.cy.ts`, os casos `e2e` em `qa_casos_teste` e a ponte
> `qa_cobertura_e2e` são **infra de teste**: rodam nas esteiras de **teste** e
> **homologação** e **não têm passo de produção**. A produção não roda Cypress e a
> ponte só serve à guarda (`qa-cobertura-e2e`/`verificar-cobertura-e2e.mjs`) das
> esteiras. Os `docs/script_*_homologacao.sql` desta cobertura são para o SQL
> Editor da **homologação apenas** — nunca o de produção.

### Cobertura nova de tela — Férias (09/2026, doc-first)

O módulo **Férias** (`jornada-rotina/ferias`) tinha forte cobertura de MOTOR
(fracionamento, concessivo, saldo, encargos…) e **zero tela**. Documentamos os
casos primeiro (fonte da verdade) e só então implementamos os `it()`:

- **10 casos `e2e` FERIAS-TELA-01..10** em `qa_casos_teste` — o módulo monta com
  cabeçalho/abas, o modal **Nova Solicitação** abre/fecha, o filtro de status
  abre, e as abas Solicitações/Calendário/Saldos/Financeiro/INR™/Vencimentos/
  Coletivas abrem sem erro. Todos **data-independentes** (valem na ilha vazia,
  sem fixtures).
- **`cypress/e2e/ferias.cy.ts`** — os 10 `it()`, ligados aos casos pela ponte
  `qa_cobertura_e2e`. Robustos ao scroll-lock do Radix e ao registro de humor
  (`{force:true}` + fechamento best-effort do modal).
- Duas entregas: migration `20260915210000_qa_ferias_casos_tela.sql` (aplica no
  teste pela esteira) e `docs/script_ferias_casos_tela_homologacao.sql` (colado
  no SQL Editor da homologação — **necessário antes da corrida**, senão a guarda
  reprova os `it()` como "inventados").

Validação: teste `ferias` 10/10; homologação (bateria #47, `81c05c7`) **38 specs /
322 testes, tudo verde**, guarda incluída. Fica registrado que o módulo Férias
mantém **1 caso `e2e` anterior sem teste** (FERIAS-055, "aviso sem ciência não
conclui a concessão") — só gera aviso na guarda, nunca reprova; candidato a
implementação futura (precisa de fixtures de solicitação).

### Cobertura nova de tela — Colaboradores (09/2026, doc-first)

O módulo **Colaboradores** (`estrutura-organizacional/colaboradores`) — o núcleo
de gente (admissão, ativos, desligados) — não tinha tela documentada. Mesmo
padrão do Férias:

- **9 casos `e2e` COLAB-TELA-01..09** em `qa_casos_teste` — o módulo monta com
  abas (Ativos/Admissões/Desligados) e ações (Novo Cadastro, Importar); a aba
  Ativos traz busca e filtros; alternância cards/lista; **Novo Cadastro** abre a
  escolha colaborador×terceiro; **Importar** abre o modal; filtro de Departamento;
  e o contador "Mostrando X de Y". Data-independentes (sem fixtures).
- **`cypress/e2e/colaboradores.cy.ts`** — os 9 `it()`, ligados pela ponte.
- Entregas: migration `20260916180500_qa_colaboradores_casos_tela.sql` e
  `docs/script_colaboradores_casos_tela_homologacao.sql` (colado no SQL Editor da
  homologação antes da corrida).

Validação: homologação (bateria #48, `26e816f`) **39 specs, tudo verde**, guarda
incluída (colaboradores 9/9). O módulo mantém **2 casos `e2e` anteriores sem
teste** — só geram aviso na guarda, nunca reprovam. Nota de operação: a esteira
do teste passou por um surto de **colisões de carimbo** entre sessões (09/16);
esta migration foi re-carimbada para `…180500` para desbloquear — conteúdo
intacto. Reforço do costume: conferir o carimbo livre **no momento da mescla**,
não só ao criar.

### Cobertura nova de tela — Financeiro (09/2026, doc-first)

O módulo **Financeiro** (`financeiro`) — folha, benefícios, provisões, eSocial —
não tinha tela documentada. Mesmo padrão:

- **10 casos `e2e` FINAN-TELA-01..10** em `qa_casos_teste` — o módulo monta com
  as 13 abas; o **Painel** mostra KPIs e cards; a aba **Folha** abre com **Novo
  Período** (+ modal); a aba **Benefícios** com **Novo Benefício**/**Vincular**
  (+ modal Novo Tipo de Benefício); e as abas Rubricas/Provisões/eSocial/Tabelas
  abrem sem erro. Data-independentes (sem fixtures).
- **`cypress/e2e/financeiro.cy.ts`** — os 10 `it()`, ligados pela ponte.
- Entregas: migration `20260917120000_qa_financeiro_casos_tela.sql` e
  `docs/script_financeiro_casos_tela_homologacao.sql` (colado no SQL Editor da
  homologação antes da corrida).

Validação: homologação (bateria #49, `967e7d5`) **40 specs, tudo verde**, guarda
incluída (financeiro 10/10; sem casos `e2e` pré-existentes no módulo).

### Cobertura nova de tela — Usuários (09/2026, doc-first)

O módulo **Usuários** (`infraestrutura-auth/usuarios-permissoes`, rota `/usuarios`)
— identidades, vínculos e ciclo de vida — já tinha forte cobertura de **MOTOR**
(59 casos api de permissão/isolamento: CTX/ISOL/USR/PER/VIN) e nenhuma **tela**.
Mesmo padrão:

- **7 casos `e2e` USR-TELA-01..07** em `qa_casos_teste` — o módulo monta com
  cabeçalho/métricas (Ativos/Com convite/Multiempresa/Alertas IA) e a ação **Novo
  Usuário**; os filtros de busca/empresa/status/tipo aparecem; o modal **Novo
  Usuário** abre ("Dados Básicos"); e a busca por termo inexistente mostra o vazio
  orientativo. Data-independentes (sem fixtures).
- **`cypress/e2e/usuarios.cy.ts`** — os 7 `it()`, ligados pela ponte.
- Entregas: migration `20260917144156_qa_usuarios_casos_tela.sql` e
  `docs/script_usuarios_casos_tela_homologacao.sql`. As duas **garantem a linha do
  módulo** (idempotente, sob `infraestrutura-auth`) para não depender da ordem de
  outra sessão.

Validação: homologação (bateria #50, `f1d6d39`) **41 specs, tudo verde**, guarda
incluída (usuarios 7/7). Confirmação na homologação: `casos_usr_tela=7`,
`pontes_usr_tela=7`, `e2e_no_modulo_usuarios=12` (os 7 de tela + 5 casos `e2e` de
motor pré-existentes — CTX/USR/PER). Esses 5 seguem como casos `e2e` documentados
sem teste de tela (só aviso na guarda).

### Cobertura nova de tela — Aprendizado & Papéis (09/2026, doc-first)

Caso diferente: o módulo **Aprendizado & Papéis**
(`desenvolvimento-performance/aprendizado-competencias`, rota `/aprendizado-papeis`)
já tinha os **13 casos `e2e` documentados** (APR-*, migration `20260901130500`),
mas **nenhum teste de tela nem ponte** — a documentação existia, o teste não (só
aviso na guarda). Aqui implementamos o subconjunto **data-independente** e ligamos
cada `it()` ao caso já documentado:

- **5 `it()` em `cypress/e2e/aprendizado-papeis.cy.ts`** — APR-001 (as 4 abas),
  APR-002 (Funções lista + busca), APR-010 (abrir o detalhe da função e voltar),
  APR-040 (Assinaturas orienta no vazio), APR-050 (Indicadores monta os cartões).
  A ilha de QA (`seed-e2e-user`) planta 4 cargos fixos (mesmos no teste e na
  homologação), então APR-002/APR-010 contam com "Analista Financeiro"; os vazios
  são forçados via busca (robustos com ou sem dados).
- Entregas: migration `20260917164458_qa_aprendizado_papeis_ponte_e2e.sql`
  (garante os 5 casos + a ponte, idempotente) e
  `docs/script_aprendizado_papeis_ponte_homologacao.sql`. As duas **garantem os 5
  casos ligados** para não depender de o Item 2 (`docs/script_qa_casos_modulos_item2.sql`)
  já ter chegado na homologação.

Validação: homologação (bateria #51, `e4492a7c`) **tudo verde**, guarda incluída
(aprendizado 5/5). Confirmação na homologação: `casos_apr_ligados=5`,
`pontes_apr_tela=5`, `e2e_no_modulo_aprendizado=13`. Os outros **8 casos APR**
(adicionar atividade/competência, gerar manual por IA, assinaturas com envios,
salvar config, isolamento) exigem fixtures e seguem como documentados-sem-teste
(só aviso na guarda).

### Cobertura nova de tela — Central de Pendências (09/2026, doc-first)

O módulo **Central de Pendências** (`sistema/pendencias`, rota `/pendencias`) — o
agregador de ações/providências por perfil (férias, documentos, ajustes,
avaliações, desligamentos, afastamentos, alertas de saúde) — **não existia no QA**
(sem módulo, sem casos, sem spec). Padrão doc-first "puro":

- **4 casos `e2e` PEND-TELA-01..04** em `qa_casos_teste` — o módulo monta com
  cabeçalho + 3 cartões (Urgentes/Em Atenção/Total de Ações); a busca e os 4
  filtros por perfil (Tudo/Meu Perfil/Minha Equipe/Gestão / RH) aparecem; a busca
  sem resultado orienta ("Nenhuma pendência encontrada"); selecionar "Gestão / RH"
  ativa a aba. Data-independentes (o vazio é forçado via busca).
- **`cypress/e2e/pendencias.cy.ts`** — os 4 `it()`, ligados pela ponte. A Central
  de Pendências saiu do menu lateral (fica no dashboard); o spec navega direto por
  `/pendencias`.
- Entregas: migration `20260917202153_qa_pendencias_casos_tela.sql` e
  `docs/script_pendencias_casos_tela_homologacao.sql`. As duas **garantem a linha
  do módulo** `sistema/pendencias` (idempotente, sob a seção `sistema`).

Validação: `pendencias.cy.ts` **passou 4/4** na bateria #52 (`693e15a7`);
confirmação na homologação `casos_pend_tela=4`, `pontes_pend_tela=4`,
`e2e_no_modulo_pendencias=4`. **Ressalva:** a bateria #52 fechou **vermelha por 1
falha pré-existente e não relacionada** — `trilhas.cy.ts › "cria uma trilha na
Gestão"` (`AssertionError: Expected to find content: 'Trilha criada!' but never
did`, `trilhas.cy.ts:71`; modal não fechou, campo de nome da campanha ausente).
Esse teste **passou** nas baterias #50 e #51 e está **fora do escopo** desta
entrega (não toca Trilhas nem `TrilhaForm`). **Resolvido: era flake** — passou na
re-rodada #53 (`a84f549e`), com a **suíte inteira verde (43/43)**.

**Nota de cobertura (evitar retrabalho):** dois "candidatos" que **não são
lacuna** — já têm tela coberta por specs existentes:
- **Atestados/GAF** (`/atestados`, tela "MOD-GAF") → `afastamentos.cy.ts` (Central
  GAF, casos AFAST-TELA-*).
- **Feed** (`/feed`) → é o **Mural Interno** (a página `Feed.tsx` renderiza o h1
  "Mural Interno"), já coberto por `mural.cy.ts` (7 `it()`: compositor, feed,
  atualizar, publicar, bloquear vazio, comentar, excluir) + casos MURAL-*
  (`20260828140400_qa_mural_casos_tela.sql`). Não criar spec de Feed separado.

Com isso, a rodada doc-first de tela cobriu os módulos que faltavam
(Férias, Colaboradores, Financeiro, Usuários, Aprendizado & Papéis, Pendências);
Atestados/GAF e Feed(=Mural) já estavam cobertos. A suíte da homologação voltou a
**43/43 verde** na bateria #53 (`a84f549e`).

**Nota de flake (para o histórico):** `trilhas.cy.ts › "cria uma trilha na Gestão"`
falhou **apenas** na #52 (`'Trilha criada!' never did`, `trilhas.cy.ts:71`; modal
não fechou) e passou nas #50, #51 e na re-rodada #53. Foi **instabilidade**, não
regressão — nenhuma entrega tocou Trilhas/`TrilhaForm`. Se voltar a piscar, é
candidato a endurecer o `it()` (esperar o fechamento do modal / o toast com mais
tolerância).

## Testes de tela (Cypress) na homologação

Por padrão a suíte Cypress roda só no **teste** (é lá que a tela nasce, e as duas
telas — teste e homologação — são o mesmo código publicado em duas pastas). A
raia de tela na homologação foi montada **por decisão explícita da equipe**, para
quando se quiser exercitar as telas contra o banco cópia-da-produção (volume e
estrutura reais). Ela **não roda sozinha**: é um botão.

**Como rodar (dois caminhos, mesmo resultado):**

1. **Pelo app:** homologação → **Testes automatizados → Cypress → "Rodar testes"**.
   O botão pede à Edge Function `qa-disparar-cypress`, que detecta o ambiente e
   dispara a esteira **da homologação** (`cypress-homologacao.yml`). Exige o
   secret `GITHUB_DISPATCH_TOKEN` no projeto Supabase da homologação (ver abaixo).
2. **Pela esteira:** Actions → `cypress-homologacao` → **Run workflow**.

Nos dois, o workflow semeia a conta-robô e a ilha de fixtures na homologação,
roda a suíte contra `https://ustudy123.github.io/youreyesnovo/homologacao/` e
devolve o resultado ao painel de QA **da homologação** (aba Cypress → "Corridas").

**O resultado no painel do app:** funciona porque a camada de QA e2e (tabela
`qa_cobertura_e2e`, coluna `qa_resultados.evidencia_png`, as funções de registro
e o valor `'e2e'` no enum `qa_disparo`) foi entregue à **produção**
(`docs/script_qa_e2e_camada.sql`). Como a homologação copia a estrutura da
produção, toda cópia futura já nasce com a camada — o painel sobrevive ao
`RECRIAR`, e a fidelidade continua batendo (as duas têm a camada). A
`qa_cobertura_e2e` está na lista de tabelas preservadas da máscara, então a
ponte caso↔teste atravessa a cópia intacta.

**Pré-requisito (depois de mesclar função nova):** as Edge Functions precisam estar
publicadas na homologação com a versão nova (a `seed-e2e-user` que semeia a conta-robô,
a `qa-disparar-cypress` que detecta o ambiente etc.). Rode o botão
**`homologacao-funcoes.yml`** (Actions → `homologacao-funcoes` → **Run workflow**,
~2 min) — a porta sancionada que republica só as functions, sem `RECRIAR`. (O modo
`so_finalizar` do `homologacao.yml` faz o mesmo deploy, mas passa pelo gate do
`RECRIAR` e pela conferência de fidelidade, que pós-09/2026 pode não fechar — prefira
a porta dedicada.)

**Segredos:**

| Onde | Secret | Valor |
|---|---|---|
| GitHub (Actions) | `QA_E2E_TOKEN_HOMOLOGACAO` | o **mesmo** valor do `QA_E2E_TOKEN` das Edge Functions do projeto Supabase de homologação (`fgsblefvdabgdouipigz`). Sem ele, o seed e o relatório não funcionam. |
| GitHub (Actions) | `CYPRESS_EMAIL` / `CYPRESS_PASSWORD` | opcionais; sem eles usa `teste@lucas.com` / `7654321`, a conta que o seed cria. |
| Supabase homologação | `GITHUB_DISPATCH_TOKEN` | token do GitHub com permissão **Actions: write** no repositório. Só é preciso para o **botão** do app; a aba Actions não depende dele. |

**Travas de ambiente (produção inalcançável):** o `cypress.config.ts` só aceita
host da lista (`ustudy123.github.io`) e aborta se a app falar com o ref da
produção; a `seed-e2e-user` recusa qualquer ref fora do teste e da homologação.

**Sobre a ilha e a fidelidade:** a suíte roda numa ilha isolada (tenant fixo
`Empresa Staging LTDA`), invisível às contas mascaradas da produção porque a RLS
separa por tenant. Ela é replantada a cada corrida e some no próximo `RECRIAR`
(o próprio workflow a replanta antes de rodar, então não precisa sobreviver).

## Rodar a homologação localmente

```bash
npm run dev:homologacao      # sobe apontando para o banco de homologação
npm run build:homologacao    # gera o build de homologação
```

A versão do build sai carimbada — `1.0.0-homolog.<data>` na homologação e
`1.0.0-teste.<data>` no teste —, então um print de tela já diz de onde veio.

Enquanto não houver host próprio para a homologação, ela roda local. Não é
limitação séria: o que se valida ali é o **script**, no SQL Editor, não a tela.

## Criar o projeto Supabase de staging

Roteiro completo, na ordem. Nenhum arquivo da aplicação precisa ser alterado — o trabalho é de infraestrutura.

### 1. Criar o projeto

No dashboard do Supabase, crie um novo projeto (ex.: `youreyes-staging`). Anote **Project URL**, **anon/public key** e o **project ref**.

### 2. Preencher `.env.staging`

Substitua os placeholders `<staging-project-id>` e `<staging-anon-key>` pelos valores reais. `VITE_APP_URL` deve apontar para a URL onde o staging será acessado.

### 3. Replicar o schema (todas as migrations do repositório)

```bash
supabase link --project-ref <staging-project-id>
supabase db push
```

> Rodar as migrations manualmente no SQL Editor não é viável nesse volume — use a CLI.

### 4. Deployar as Edge Functions (71 funções)

```bash
supabase functions deploy --project-ref <staging-project-id>
```

### 5. Recadastrar os secrets

Secrets **não** são copiados entre projetos. Configure em `Project Settings > Edge Functions > Secrets`:

| Secret | Uso |
|---|---|
| `LOVABLE_API_KEY` | Lovable AI Gateway (geração de conteúdo, análises) |
| `OPENAI_API_KEY` | Extrações e análises com GPT-4o |
| `RESEND_API_KEY` | Envio de e-mails transacionais |
| `EMAIL_FROM` | Remetente dos e-mails |
| `APP_URL` / `SITE_URL` | Links públicos (assinaturas, convites) — apontar para a URL de staging |
| `WHATSAPI_BASE_URL` / `WHATSAPI_TOKEN` | OTP e ponto via WhatsApp |
| `MERCADOPAGO_ACCESS_TOKEN` | Cobrança/assinaturas |
| `CONSULTACRM_KEY` | Consulta de conselhos profissionais |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são injetados automaticamente pela plataforma.

> Em staging, use chaves de teste/sandbox sempre que o provedor oferecer (Mercado Pago, WhatsApp), para não disparar cobranças ou mensagens reais.

### 6. Criar os buckets de Storage

Execute `supabase/seeds/staging_buckets.sql` no SQL Editor do staging. Ele cria os 22 buckets com a mesma visibilidade e limites de produção (atestados, documentos, esocial-certificados, ponto-selfies, trilha-conteudo etc.). As policies de `storage.objects` já vêm nas migrations.

### 7. Popular dados de teste

Crie um usuário administrador no staging (Authentication > Users) e execute o seed no SQL Editor:

No SQL Editor (que não entende comandos do psql como `\i`): abra o arquivo `supabase/seeds/staging.sql`, cole o conteúdo inteiro no editor, ajuste o UUID do administrador no topo e execute.

O seed cria:

- Um tenant `Empresa Staging LTDA` (plano `enterprise`).
- Uma empresa matriz com CNPJ fictício.
- 4 departamentos: Administrativo, RH, Operações e Tecnologia.
- 4 cargos associados.
- 20 colaboradores fictícios com CPFs seqüenciais.
- Contexto de IA (`ai_context`) para testes de geração de funções.

### 8. Validar

- [ ] Login com o usuário admin.
- [ ] Empresa ativa carrega e o seletor de empresa funciona.
- [ ] Módulo Ponto: marcação, apuração e banco de horas.
- [ ] Geração de um PDF (Cartão Ponto ou Manual de Função).
- [ ] Uma chamada de IA (Gerar Função com IA) — valida secret + Edge Function.
- [ ] Upload de um documento — valida bucket + policies.

## Automação (GitHub Actions)

O workflow `.github/workflows/staging.yml` mantém o staging atualizado sozinho: a cada mudança mesclada na `main`, ele aplica as migrations novas no projeto de staging, reimplanta as Edge Functions e — se os secrets do Netlify estiverem configurados — publica o site de teste. Ninguém precisa de CLI local para manter o ambiente.

Secrets (Settings > Secrets and variables > Actions do repositório):

| Secret | Para quê | Obrigatório |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | Token pessoal do Supabase (Account > Access Tokens) | Sim |
| `SUPABASE_DB_PASSWORD` | Senha do banco do projeto de staging | Sim |
O site de teste é publicado no **GitHub Pages** do próprio repositório — https://ustudy123.github.io/youreyesnovo/teste/ — sem contas nem secrets adicionais. Ele aponta para o banco de STAGING (login com os usuários fictícios).

O mesmo Pages hospeda os dois ambientes públicos, cada um numa pasta com nome próprio, e a raiz é só uma placa que redireciona para o teste:

- `.../youreyesnovo/teste/` → ambiente de **teste** (banco de staging);
- `.../youreyesnovo/homologacao/` → ambiente de **homologação** (cópia embaralhada da produção);
- `.../youreyesnovo/` (raiz) → redireciona para `/teste/` (mantém vivos o link curto e links antigos).

O Pages serve um único `404.html` (o da raiz) para qualquer caminho inexistente do site inteiro: ele carrega o app de teste e desvia os caminhos sob `/homologacao/` para o app de homologação, para nunca abrir um ambiente achando que é o outro.

O workflow tem trava contra apontar para a produção e pode ser disparado manualmente na aba Actions (`workflow_dispatch`).

Outros workflows do repositório:

- `homologacao.yml` — recria a homologação a partir da estrutura da produção (por botão, digitando `RECRIAR`). **SUSPENSO desde 09/2026.** Ver **Manter a homologação em dia**.
- `homologacao-funcoes.yml` — **publica só as Edge Functions na homologação** (por botão, sem `RECRIAR`, ~2 min). É a porta sancionada para levar função nova/alterada à homologação no fluxo forward-only. Ver **Manter a homologação em dia**.
- `cypress.yml` — dispara a suíte de tela contra o **teste**, sob demanda.
- `cypress-homologacao.yml` — dispara a suíte de tela contra a **homologação**. Ver **Testes de tela (Cypress) na homologação**.

O botão **"Rodar testes"** (tela de QA de cada ambiente) aciona a `qa-disparar-cypress`, que **detecta o ambiente pelo projeto Supabase** e dispara a esteira certa: `cypress.yml` no teste, `cypress-homologacao.yml` na homologação. Precisa do secret `GITHUB_DISPATCH_TOKEN` no projeto Supabase daquele ambiente.

## Verificação de ambiente

Para garantir que nenhum valor de produção está hard-coded onde não deve, verifique o `src/` **e as migrations** (era nas migrations que o problema estava):

```bash
rg -n "diayjpsrcerycycyaxst" src/ supabase/migrations/
```

Resultado esperado: nenhuma ocorrência em `src/`; nas migrations, apenas as duas ocorrências **neutralizadas** e o script de entrega:

- `20260702174019_…` — reparo de dados de produção com **guarda de ambiente**: em banco sem o tenant de produção, o bloco sai sem fazer nada (as URLs restantes são dados históricos de selfie, não chamadas);
- `20260803100000_…` e `20260810100000_…` — o dispatch dos agentes lê URL e chave da tabela `app_config`; a URL fixa não existe mais no corpo da função.

Os únicos arquivos com valores fixos legítimos são `.env`, `.env.production` e `supabase/config.toml`.

### Agentes YourEyes no staging (`app_config`)

O disparador dos agentes (roda a cada minuto) só chama a Edge Function se `app_config` tiver `supabase_url` e `supabase_anon_key`. **Num ambiente recém-criado ele não chama ninguém** — proteção para o staging nunca acionar a produção. Para ativar os agentes no staging, insira os valores DO STAGING:

```sql
INSERT INTO public.app_config (chave, valor) VALUES
  ('supabase_url', 'https://<staging-project-id>.supabase.co'),
  ('supabase_anon_key', '<staging-anon-key>')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();
```

Em produção, os valores são semeados pelo script `docs/script_app_config_producao.sql`.

### Agendar os Testes de tela (Cypress) — `github_dispatch_token`

A aba "Testes Cypress" do painel de QA tem "Rodar automaticamente", igual ao Motor. Mas o Cypress roda na esteira do GitHub, não no banco: no horário marcado, o `pg_cron` do ambiente pede à esteira que rode (`workflow_dispatch`). Isso exige um token do GitHub em `app_config`. **Sem o token, o horário fica salvo mas nada é disparado** — mesma proteção de ambiente dos agentes.

O token é um *fine-grained PAT* com permissão **Actions: Read and write** neste repositório. Crie em GitHub → Settings → Developer settings → Fine-grained tokens. Guarde-o no ambiente que deve disparar (normalmente o staging):

```sql
INSERT INTO public.app_config (chave, valor) VALUES
  ('github_dispatch_token', '<cole-o-token-aqui>')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();
```

Opcionalmente, `github_dispatch_repo` (padrão `ustudy123/youreyesnovo`), `github_dispatch_workflow` (padrão `staging.yml`) e `github_dispatch_ref` (padrão `main`) sobrescrevem os alvos. **Nunca versione o token** — ele vive só no `app_config` do ambiente. O schema/funções são instalados pela migration `20260814120000_qa_agendamento_e2e_esteira.sql` (staging) e pelo script `docs/script_qa_agendamento_e2e.sql` (produção).

## Checklist antes de publicar

- [ ] `.env` está com `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` corretos para o ambiente desejado.
- [ ] Migrations estão aplicadas no projeto.
- [ ] Edge Functions estão deployadas e secrets configuradas.
- [ ] Buckets de Storage criados.
- [ ] Se for staging, execute `npm run build:staging` e confirme no build gerado que a URL é a do staging.
- [ ] `app_config` do ambiente aponta para o próprio ambiente (agentes).
- [ ] Nenhum secret privado (service_role, senhas) foi commitado — os arquivos `.env*` versionados só carregam URL e chave publishable.

## Dúvidas comuns

**Posso ter dois bancos na mesma conta Supabase?**
Sim, cada projeto Supabase é um banco isolado. Você pode ter quantos projetos quiser na mesma conta, respeitando os limites do plano. Não é preciso criar outra conta.

**É preciso duas contas Lovable?**
Não. A Lovable conecta um projeto Supabase por vez — o editor continua apontando para produção. O staging é usado via build local (`npm run build:staging`) ou alternando temporariamente a conexão do Supabase nas configurações do projeto.

**Como publico o staging em um domínio próprio?**
A Lovable publica um único build por projeto (hoje, produção). Para um `teste.youreyes.com.br`, hospede o resultado de `npm run build:staging` em um host estático (Vercel, Netlify, Cloudflare Pages) apontando para o domínio de teste.

**E o `supabase/config.toml`?**
Ele mantém o `project_id` de produção como padrão. Quando for trabalhar localmente no staging via CLI, use `supabase link --project-ref <staging-project-id>` para sobrescrever temporariamente.

## Conferir se a produção está alinhada com o repositório

O ambiente de teste recebe **toda** mudança automaticamente pela esteira; a
produção só recebe o que é colado no SQL Editor. A cada script não colado, os
dois se afastam — e a diferença só aparece quando algo quebra na hora errada.
Já aconteceu duas vezes: um script de entrega abortou por causa de uma coluna
que existia no teste e não na produção, e a rotina de QA `FERIAS-017` quebrou
porque duas funções auxiliares nunca foram entregues.

Para medir essa distância antes que ela cobre o preço, existem duas consultas
**somente leitura** para colar no SQL Editor da produção:

| Arquivo | Compara |
|---|---|
| `docs/script_divergencia_producao_parte1.sql` | tabelas, colunas e tipos (enums) |
| `docs/script_divergencia_producao_parte2.sql` | funções, gatilhos e políticas de segurança |

Elas listam **só as diferenças**, nos dois sentidos:

- **só no repositório** → falta aplicar na produção;
- **só na produção** → objeto criado direto no banco que ninguém trouxe de volta
  para o código (precedentes: `feriados`, `feriado_comportamento`);
- **difere** → o conjunto mudou; a coluna `detalhe` mostra o que a produção tem
  hoje, para comparação.

Em ambiente alinhado o resultado é uma linha só, a de resumo.

> **Os arquivos envelhecem.** Cada um carrega uma fotografia do repositório na
> data em que foi gerado. Depois de novas migrations, precisa regerar — é rápido:
> extrai-se o inventário de uma réplica com todas as migrations aplicadas.

Vale rodar antes de uma entrega grande e depois de um período sem colar scripts.
