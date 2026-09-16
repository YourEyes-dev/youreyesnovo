#!/usr/bin/env python3
"""
Gera os comandos que copiam os dados da PRODUÇÃO para a HOMOLOGAÇÃO com a
identificação embaralhada.

A IDEIA CENTRAL: MASCARAR NA LEITURA
------------------------------------
A máscara é aplicada dentro do SELECT que roda NA PRODUÇÃO. O dado que
identifica pessoa — CPF, nome, e-mail, atestado — nunca sai de lá: o que
atravessa a rede, o que chega ao servidor da esteira e o que é gravado na
homologação já está embaralhado.

Isso importa por dois motivos concretos deste projeto: o repositório é
público, e a homologação está fora do Brasil. Copiar cru e mascarar depois
resolveria o resultado final, mas colocaria o dado real em trânsito e em
repouso, ainda que por minutos, nos dois lugares onde ele não deve estar.

O DEFAULT É MASCARAR, NÃO PRESERVAR
-----------------------------------
São ~1950 colunas de texto no schema. Classificar uma a uma por padrão de
nome erra nos dois sentidos, e os dois erros não custam igual:

  · mascarar demais  -> o ensaio quebra de um jeito VISÍVEL (uma rotina de
                        QA falha, uma tela fica estranha) e a gente conserta
                        pondo a coluna na lista de preservadas;
  · mascarar de menos -> um CPF real vaza EM SILÊNCIO.

Por isso a regra é invertida em relação ao instinto: **toda coluna de texto
é mascarada, exceto as que estiverem explicitamente na lista de preservadas**.
Falha para o lado seguro, e o lado inseguro é o único que não dá sinal.

Colunas que não são texto (data, número, booleano, uuid) passam intactas:
não carregam nome nem documento, e são elas que dão realismo ao ensaio —
volume, datas, valores, chaves.

Com DUAS exceções, que quase escaparam justamente por não serem "texto":

  · jsonb/json — 120 colunas no schema. O tipo não é texto, mas o conteúdo
    é livre: auth.users.raw_user_meta_data guarda nome completo e e-mail
    do usuário. Passariam inteiras.
  · text[] — 39 colunas. Mesma história, em lista.

As duas viram vazio ('{}'). Perde-se o conteúdo, preserva-se o tipo e o
NULL. Se alguma delas fizer falta no ensaio, entra na lista de preservadas
— de novo, o erro que se conserta é o que aparece.

O QUE É PRESERVADO, E POR QUÊ
-----------------------------
1. Colunas com CHECK do tipo `IN (...)` / `= ANY (ARRAY[...])`. São enums
   escritos como texto — 'aprovado', 'pendente', 'concluido'. Mascarar isso
   violaria o próprio CHECK, e o COPY falharia na cara; além disso é
   exatamente o dado de que a lógica depende.
2. A lista PRESERVAR_SEMPRE abaixo: catálogos públicos (CBO, CID como
   tabela de referência), rótulos organizacionais (cargo, setor, risco) e
   colunas de controle. Cada entrada tem motivo escrito.

O QUE NÃO É EMBARALHADO, E VOCÊ PRECISA SABER
---------------------------------------------
Salários e valores financeiros passam intactos. Não identificam ninguém
depois que nome e CPF viraram outra coisa, e são necessários para o ensaio
ter sentido (cálculo de férias, rescisão, provisão). Se a decisão for outra,
acrescente os nomes de coluna em MASCARAR_SEMPRE.

DETERMINISMO
------------
Todas as máscaras derivam de md5(valor || tempero). O mesmo CPF vira o mesmo
CPF falso em todas as 45 tabelas onde aparece, e o mesmo nome vira o mesmo
nome falso nas 62. Sem isso, as ligações por CPF — que este schema usa muito,
por ser denormalizado — se perderiam, e o ensaio deixaria de refletir a
produção.

O tempero fica num parâmetro para que o mapeamento não seja reproduzível por
quem só conhece o algoritmo: sem ele, não dá para testar "o CPF X virou Y?".
"""

import re
import sys

# ---------------------------------------------------------------------------
# Classificação
# ---------------------------------------------------------------------------

TIPOS_TEXTO = {"text", "character varying", "character"}

# Colunas preservadas mesmo sendo texto. Cada uma com o motivo — lista sem
# motivo escrito vira lista que ninguém ousa mexer depois.
PRESERVAR_SEMPRE = {
    # Rótulos organizacionais: 'Soldador', 'Produção', 'Ruído'. Não
    # identificam pessoa e são o que dá sentido a relatório e agrupamento.
    "cargo_nome", "setor_nome", "risco_nome", "funcao_nome",
    "exame_nome", "treinamento_nome", "modulo_nome", "trilha_nome",
    "curso_nome", "epi_nome", "tipo_nome", "perfil_nome",
    # Catálogos públicos: CBO e CID são tabelas de referência, iguais para
    # todo mundo. Não são dado de pessoa; são dicionário.
    "cbo_codigo", "cbo_titulo", "cid_codigo", "cid_descricao",
    "cid_capitulo", "cid_grupo",
    # Geografia grossa: útil para relatório, não identifica sozinha.
    "cidade", "estado", "uf", "pais", "cidade_foro",
    # Controle e navegação do próprio sistema.
    "modulo", "rota", "tabela", "acao", "entidade", "chave_config",

    # Colunas ESTRUTURAIS sem CHECK. São enums que ninguém escreveu como
    # enum: 'ativo', 'pendente', 'mensal', 'noturno'. Medidas no schema:
    # 215 colunas, sendo `tipo` em 48 tabelas e `status` em 30. Mascarar
    # isso não vazaria nada, mas esvaziaria o ensaio — nenhuma regra de
    # negócio funciona sem saber se a admissão está concluída ou o
    # atestado aprovado.
    #
    # A comparação aqui é por NOME EXATO, e isso não é detalhe: `origem`
    # fica, mas `ip_origem` NÃO — endereço IP é dado pessoal, e casar por
    # sufixo o teria preservado junto, em silêncio. Pelo mesmo motivo
    # `origem_descricao` fica de fora: é texto livre.
    "tipo", "status", "situacao", "categoria", "nivel", "unidade",
    "unidade_medida", "frequencia", "periodicidade", "modalidade",
    "tipo_vinculo", "tipo_documento", "tipo_evento", "tipo_usuario",
    "tipo_usuario_sugerido", "tipo_dia", "tipo_contrato", "tipo_jornada",
    "nivel_risco", "nivel_confianca", "entidade_tipo",
    "periculosidade_tipo", "ierm_nivel", "origem", "origem_modulo",
    "turno", "regime", "jornada", "prioridade", "severidade",
    "criticidade", "duplicidade_nivel", "risco_grau",

    # Atributos pessoais de baixa cardinalidade. Depois que nome e CPF
    # viraram outra coisa, não identificam ninguém — e regras dependem
    # deles (licença-maternidade olha sexo; admissão olha escolaridade).
    # Se a decisão for outra, basta tirar daqui.
    "sexo", "genero", "estado_civil", "escolaridade",

    # Colunas do auth.users de que o login depende. `aud` e `role` valem
    # 'authenticated' — embaralhar isso não vazaria nada e impediria
    # qualquer pessoa de entrar, com um erro que não diria por quê.
    "aud", "role", "email_change", "phone_change",
}

# Colunas mascaradas com formato preservado. A ordem importa: a primeira
# regra que casar é a que vale.
#
# Formato preservado é necessário quando há CHECK de formato na coluna (o
# CPF é validado por dígito verificador neste sistema) ou quando a aplicação
# lê o valor esperando um desenho — e-mail com @, telefone com DDD.
#
# Cada par é (pedaço do nome da coluna, tratamento). Vários nomes caem no
# mesmo tratamento — celular e whatsapp são telefone.
REGRAS_FORMATO = [
    ("cpf",       "cpf"),
    ("cnpj",      "cnpj"),
    ("email",     "email"),
    ("e_mail",    "email"),
    ("telefone",  "telefone"),
    ("celular",   "telefone"),
    ("whatsapp",  "telefone"),
    ("fone",      "telefone"),
    ("cep",       "cep"),
]

# Credenciais: não basta embaralhar, tem que deixar de funcionar. Token
# copiado continua sendo token válido em algum lugar.
# "password" está aqui por causa de auth.users.encrypted_password: o hash da
# senha REAL não pode sair da produção. Hash de senha é credencial, não é
# "dado já protegido" — quem o tem pode atacá-lo offline, no seu tempo.
PADROES_CREDENCIAL = ("token", "senha", "password", "secret", "hash",
                      "chave_api", "api_key")

# Tabelas do MOTOR DE QA preservadas POR INTEIRO. Elas são documentação do
# sistema, não dado de pessoa: códigos de caso (PERFIL-004), títulos,
# nomes de função SQL (qa_implementacoes.funcao_sql), caminhos de módulo,
# nomes de tabela. Mascarar isso quebrou o QA na homologação de três jeitos
# ao mesmo tempo: o seletor de módulos virou anon-..., os códigos dos casos
# sumiram e nenhuma rotina poderia sequer ser chamada (o próprio NOME da
# função estava embaralhado).
#
# As duas tabelas de RESULTADO (qa_execucoes, qa_resultados) ficam DE FORA
# de propósito: `esperado`/`obtido`/`erro_tecnico` são texto livre escrito
# em tempo de execução e poderiam ecoar um valor real da produção. O preço
# é o histórico antigo ficar ilegível na homologação — aceitável, porque
# toda corrida nova nasce limpa lá dentro.
PRESERVAR_TABELAS = {
    "public.qa_modulos",
    "public.qa_casos_teste",
    "public.qa_implementacoes",
    "public.qa_cobertura_e2e",
    "public.qa_tabelas_protegidas",
    "public.qa_mobiliario_fixo",
    "public.qa_agendamento",
    "public.qa_agendamento_dias",
    "public.qa_agendamento_e2e_dias",
}

# Exceções POR LINHA: a coluna continua mascarada para todo mundo, EXCETO
# quando a condição vale — aí o valor passa intacto. A condição roda dentro
# do SELECT NA PRODUÇÃO, onde o valor ainda é o real, então pode filtrar
# pelo próprio conteúdo. `{col}` é substituído pela coluna já entre aspas.
#
# Uso único até agora: os CERCADOS de QA. O motor de testes localiza os
# tenants sintéticos por slug — 'qa-sandbox' (qa_sandbox_tenant_id) e
# 'qa-sandbox-2' (qa_sandbox2_tenant_id, usado pelos casos de isolamento
# entre clientes) — e as empresas de mentira por nome_fantasia = '[QA] Alfa'
# / '[QA] Beta' (qa_empresa). São literais criados por migration, sem nenhum
# dado de pessoa — mas a máscara genérica os transformava em anon-..., o
# lookup devolvia NULL e a bateria abortava com "Cercado nao existe" (P0001).
# O segundo cercado embaralhado era ainda mais traiçoeiro: além dos casos
# de isolamento caírem em erro ("2o cercado nao existe"), a trava
# anti-escrita-global deixou de disparar — um NOT IN que inclui NULL nunca
# é verdadeiro — e o HTPL-001 flagrou (medido no ensaio local, não teoria).
_SLUGS_CERCADO = "('qa-sandbox', 'qa-sandbox-2')"
_COND_EMPRESA_DO_CERCADO = ("tenant_id IN (SELECT id FROM public.tenants "
                            f"WHERE slug IN {_SLUGS_CERCADO})")
EXCECOES_POR_LINHA = {
    ("public.tenants", "slug"): "{col} IN " + _SLUGS_CERCADO,
    # O nome do tenant do cercado é só cosmético, mas vê-lo como
    # "[QA] Cercado de Teste Automatizado" em vez de anon-... poupa sustos.
    ("public.tenants", "nome"): "slug IN " + _SLUGS_CERCADO,
    ("public.empresa_cadastro", "razao_social"): _COND_EMPRESA_DO_CERCADO,
    ("public.empresa_cadastro", "nome_fantasia"): _COND_EMPRESA_DO_CERCADO,
}


def eh_texto(tipo: str) -> bool:
    return tipo in TIPOS_TEXTO


def classificar(coluna: str, tipo: str, tem_check_enum: bool,
                coluna_e_lista_de_texto: bool = False) -> str:
    """Devolve o tratamento: 'copiar', 'cpf', 'cnpj', 'email', 'telefone',
    'cep', 'credencial', 'json_vazio', 'lista_vazia' ou 'generico'."""
    c = coluna.lower()

    if tipo == "jsonb":
        # Não é texto, mas carrega texto livre — e é onde mora o nome
        # completo do usuário, em auth.users.raw_user_meta_data.
        return "json_vazio"
    if tipo == "json":
        # json e jsonb precisam de tratamentos SEPARADOS. Enquanto a máscara
        # era a expressão inteira, devolver jsonb numa coluna json passava
        # (o COPY serializa para texto e o destino reinterpreta). Com o
        # embrulho do cliente real virou erro de compilação — os dois ramos
        # de um CASE têm que ter o mesmo tipo:
        #   "CASE/WHEN could not convert type json to jsonb"
        return "json_vazio_json"

    if tipo == "ARRAY" and coluna_e_lista_de_texto:
        # text[]: mesma exposição de uma coluna de texto, em lista.
        return "lista_vazia"

    if not eh_texto(tipo):
        # Data, número, booleano, uuid, enum: passam intactos. São eles que
        # dão o volume e as datas de que o ensaio precisa.
        return "copiar"

    if tem_check_enum:
        # O CHECK prova que só um conjunto fechado de valores é aceito —
        # é enum escrito como texto, e mascarar violaria o próprio CHECK.
        return "copiar"

    if c in PRESERVAR_SEMPRE:
        return "copiar"

    if any(p in c for p in PADROES_CREDENCIAL):
        return "credencial"

    # Formato preservado: casa por sufixo/igualdade, nunca por "contém", para
    # não repetir a armadilha do 'cid' dentro de 'periodicidade'.
    for chave, tratamento in REGRAS_FORMATO:
        if c == chave or c.endswith("_" + chave) or c.startswith(chave + "_"):
            return tratamento

    # Todo o resto: mascarado. É aqui que mora a decisão de falhar para o
    # lado seguro — inclusive nome, endereço, atestado, observação livre.
    return "generico"


# ---------------------------------------------------------------------------
# Expressões de máscara (SQL puro — rodam na produção, que é somente leitura)
# ---------------------------------------------------------------------------

def _semente(col: str, tempero: str) -> str:
    """md5 do valor com o tempero. Base de tudo, e a razão de o mesmo CPF
    virar sempre o mesmo CPF falso."""
    return f"md5({col} || {tempero})"


# STRING VAZIA É PRESERVADA em todas as máscaras de texto, e o motivo é
# concreto: auth.users.confirmation_token é '' para quase todos os usuários,
# e existe um índice de UNICIDADE sobre a coluna (parcial, que ignora o
# vazio). Como a máscara transforma o mesmo valor no mesmo texto, milhares
# de '' viravam o MESMO token falso — e o índice recusou a carga inteira de
# auth.users, derrubando de tabela as 16 chaves estrangeiras que apontam
# para lá. String vazia não identifica ninguém; mascará-la só cria colisão.


def expr_cpf(col: str, tempero: str) -> str:
    """CPF falso COM dígito verificador válido — o sistema valida o DV, então
    um CPF inválido seria rejeitado e o ensaio morreria na entrada.

    A base começa com 9 de propósito: na homologação, todo CPF começando com
    9 é reconhecidamente inventado.

    O cálculo é o do próprio DV: soma ponderada decrescente, módulo 11, e o
    resto vira 0 quando é menor que 2.
    """
    s = _semente(col, tempero)
    # 8 dígitos vindos do md5, com o 9 na frente => 9 dígitos de base.
    base = f"('9' || lpad(((('x' || substr({s},1,8))::bit(32)::bigint) % 100000000)::text, 8, '0'))"
    d = lambda i: f"substr(b,{i},1)::int"
    soma1 = " + ".join(f"{d(i)}*{11-i}" for i in range(1, 10))
    dv1 = f"(CASE WHEN (({soma1}) % 11) < 2 THEN 0 ELSE 11 - (({soma1}) % 11) END)"
    # O segundo dígito considera os 9 primeiros mais o primeiro DV.
    soma2 = " + ".join(f"{d(i)}*{12-i}" for i in range(1, 10)) + f" + ({dv1})*2"
    dv2 = f"(CASE WHEN (({soma2}) % 11) < 2 THEN 0 ELSE 11 - (({soma2}) % 11) END)"
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"(SELECT b || {dv1}::text || {dv2}::text FROM (SELECT {base} AS b) _t) END)")


def expr_cnpj(col: str, tempero: str) -> str:
    """CNPJ falso. Sem cálculo de DV: não achei validação de CNPJ no caminho
    crítico, e um número de 14 dígitos basta para o formato. Se algum CHECK
    reclamar, o COPY falha na cara e a gente conserta — que é o
    comportamento que se quer de um erro."""
    s = _semente(col, tempero)
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"lpad(((('x' || substr({s},1,8))::bit(32)::bigint) % 100000000)::text, 8, '0') "
            f"|| '000' || lpad(((('x' || substr({s},9,4))::bit(16)::int) % 1000)::text, 3, '0') END)")


def expr_email(col: str, tempero: str) -> str:
    """Domínio .invalid é reservado por norma (RFC 2606) justamente para isto:
    nunca vai existir de verdade, então um disparo acidental de e-mail na
    homologação não chega a lugar nenhum."""
    s = _semente(col, tempero)
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"'pessoa' || substr({s},1,10) || '@exemplo.invalid' END)")


def expr_telefone(col: str, tempero: str) -> str:
    s = _semente(col, tempero)
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"'46 9' || lpad(((('x' || substr({s},1,8))::bit(32)::bigint) % 100000000)::text, 8, '0') END)")


def expr_cep(col: str, tempero: str) -> str:
    s = _semente(col, tempero)
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"lpad(((('x' || substr({s},1,8))::bit(32)::bigint) % 100000000)::text, 8, '0') END)")


def expr_credencial(col: str, tempero: str) -> str:
    """Token não se embaralha para parecer token: se parecer, alguém tenta
    usar. Vira texto que se anuncia."""
    s = _semente(col, tempero)
    return (f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE "
            f"'invalidado-na-homologacao-' || substr({s},1,12) END)")


def expr_generico(col: str, tempero: str) -> str:
    """Preserva o que a estrutura exige e joga fora o conteúdo:

      · NULL continua NULL  — colunas NOT NULL não quebram, e contagens de
        preenchimento continuam refletindo a produção;
      · valores distintos continuam distintos — restrição de unicidade
        sobrevive, porque o md5 de valores diferentes é diferente;
      · o mesmo valor vira o mesmo texto em toda parte — as ligações por
        nome, que este schema faz por ser denormalizado, continuam de pé.
    """
    s = _semente(col, tempero)
    return f"(CASE WHEN {col} IS NULL THEN NULL WHEN {col} = '' THEN '' ELSE 'anon-' || substr({s},1,12) END)"


def expr_json_vazio(col: str, tempero: str) -> str:
    """Objeto vazio, não NULL: coluna NOT NULL continua válida, e quem lê
    encontra json legítimo em vez de quebrar no parse."""
    return f"(CASE WHEN {col} IS NULL THEN NULL ELSE '{{}}'::jsonb END)"


def expr_json_vazio_json(col: str, tempero: str) -> str:
    """Igual ao de cima, no tipo json — o tipo tem que bater com o da coluna."""
    return f"(CASE WHEN {col} IS NULL THEN NULL ELSE '{{}}'::json END)"


def expr_lista_vazia(col: str, tempero: str) -> str:
    return f"(CASE WHEN {col} IS NULL THEN NULL ELSE '{{}}'::text[] END)"


EXPRESSOES = {
    "json_vazio": expr_json_vazio,
    "json_vazio_json": expr_json_vazio_json,
    "lista_vazia": expr_lista_vazia,
    "cpf": expr_cpf,
    "cnpj": expr_cnpj,
    "email": expr_email,
    "telefone": expr_telefone,
    "cep": expr_cep,
    "credencial": expr_credencial,
    "generico": expr_generico,
}


def condicao_do_cliente(tabela: str, colunas: set[str], tenant: str) -> str | None:
    """Como reconhecer, NESTA tabela, as linhas do cliente escolhido.

    Devolve None quando a tabela não tem como ser ligada a um cliente — e aí
    ela continua inteiramente mascarada. Isso é o certo, não uma limitação:
    as tabelas sem vínculo são catálogos públicos (CBO), o motor de QA e
    configuração de plataforma. Nenhuma guarda dado de cliente.

    Medido no schema: 311 das 354 tabelas têm tenant_id, 86 têm empresa_id,
    42 não têm nenhum dos dois.
    """
    t = f"'{tenant}'::uuid"
    # A própria linha do cliente na tabela de clientes.
    if tabela == "public.tenants":
        return f"id = {t}"
    # As contas de login: ligadas ao cliente pelo profile.
    if tabela == "auth.users":
        return (f"id IN (SELECT user_id FROM public.profiles "
                f"WHERE tenant_id = {t})")
    # O caso comum, e o mais confiável: a coluna que o RLS já usa.
    if "tenant_id" in colunas:
        return f"tenant_id = {t}"
    # Sem tenant_id, mas presa a uma empresa — que por sua vez é do cliente.
    if "empresa_id" in colunas:
        return (f"empresa_id IN (SELECT id FROM public.empresa_cadastro "
                f"WHERE tenant_id = {t})")
    # Papéis e afins: ligados à pessoa, e a pessoa ao cliente.
    if "user_id" in colunas:
        return (f"user_id IN (SELECT user_id FROM public.profiles "
                f"WHERE tenant_id = {t})")
    return None


def expressao(coluna: str, tratamento: str, tempero_sql: str,
              condicao_preserva: str | None = None) -> str:
    col = f'"{coluna}"'
    if tratamento == "copiar":
        return col
    mascara = EXPRESSOES[tratamento](col, tempero_sql)
    if condicao_preserva:
        # Exceção por linha: preserva o valor quando a condição vale,
        # mascara em todos os demais casos. A condição é avaliada na
        # produção, sobre o valor ainda real.
        cond = condicao_preserva.format(col=col)
        mascara = f"(CASE WHEN {cond} THEN {col} ELSE {mascara} END)"
    return f'{mascara} AS {col}'


# ---------------------------------------------------------------------------
# Entrada / saída
# ---------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) < 3:
        print("uso: gerar_copia_mascarada.py <catalogo.tsv> <tempero> [--sem-mascara]",
              file=sys.stderr)
        print("  catalogo.tsv: tabela|coluna|tipo|tem_check_enum, vindo do psql", file=sys.stderr)
        print("  --sem-mascara: copia TUDO cru, sem embaralhar nada. Ver aviso abaixo.",
              file=sys.stderr)
        return 2

    # --sem-mascara: a cópia sai IDÊNTICA à produção — nome, CPF, e-mail,
    # atestado. Decisão do dono do produto (08/2026), tomada com o risco
    # explicitado: a homologação passa a conter dado pessoal e dado de saúde
    # (LGPD art. 11), e por isso SÓ pode ser usada com o ambiente fechado —
    # senha individual forte por pessoa, nunca a senha compartilhada.
    #
    # A esteira não confia neste script para essa trava: ela mesma recusa
    # rodar sem máscara se a lista de testadores estiver vazia. Aqui o flag
    # só monta o SELECT.
    sem_mascara = "--sem-mascara" in sys.argv[3:]

    # --cliente-real <uuid>: UM cliente vem cru; todo o resto continua
    # embaralhado. É o meio-termo que o dono do produto escolheu (08/2026),
    # e é bem menos exposto que --sem-mascara: dado real de um cliente em vez
    # de 1114. O recorte por CLIENTE (tenant) e não por empresa não é
    # preferência — é o que o schema permite: usuarios_base, onde moram nome e
    # CPF, tem tenant_id e NÃO tem empresa_id. As pessoas pertencem ao
    # cliente; a ligação com a empresa só existe via admissoes.
    cliente_real = None
    if "--cliente-real" in sys.argv:
        i = sys.argv.index("--cliente-real")
        if i + 1 >= len(sys.argv):
            print("erro: --cliente-real exige o uuid do tenant", file=sys.stderr)
            return 2
        cliente_real = sys.argv[i + 1]
        # Só uuid entra: este valor vai para dentro do SQL, e um literal
        # arbitrário aqui seria injeção com credencial de leitura da produção.
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", cliente_real):
            print(f"erro: --cliente-real nao parece um uuid: {cliente_real}",
                  file=sys.stderr)
            return 2

    caminho, tempero = sys.argv[1], sys.argv[2]
    # O tempero entra no SQL como literal entre aspas simples; escapa aspa.
    tempero_sql = "'" + tempero.replace("'", "''") + "'"

    tabelas: dict[str, list[str]] = {}
    nomes: dict[str, list[str]] = {}
    resumo = {"copiar": 0, "generico": 0, "credencial": 0, "json_vazio": 0,
              "json_vazio_json": 0, "lista_vazia": 0, "cpf": 0, "cnpj": 0, "email": 0,
              "telefone": 0, "cep": 0, "tabela_preservada": 0,
              "excecao_por_linha": 0, "cliente_real": 0}
    preservadas_vistas: set[str] = set()

    # DUAS passadas. A primeira só levanta quais colunas cada tabela tem,
    # porque a decisão "esta linha é do cliente escolhido?" depende de a
    # tabela ter tenant_id, empresa_id ou user_id — e isso não se sabe ao
    # processar a primeira coluna dela.
    linhas_catalogo: list[tuple[str, str, str, str, bool]] = []
    colunas_da_tabela: dict[str, set[str]] = {}
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.rstrip("\n")
            if not linha:
                continue
            partes = linha.split("|")
            if len(partes) < 4:
                continue
            lista_texto = len(partes) > 4 and partes[4] in ("t", "true", "1")
            linhas_catalogo.append((partes[0], partes[1], partes[2],
                                    partes[3], lista_texto))
            colunas_da_tabela.setdefault(partes[0], set()).add(partes[1])

    # Cache: a condição é a mesma para todas as colunas de uma tabela.
    cond_cliente: dict[str, str | None] = {}
    if cliente_real:
        for tab, cols in colunas_da_tabela.items():
            cond_cliente[tab] = condicao_do_cliente(tab, cols, cliente_real)

    for tabela, coluna, tipo, check, lista_texto in linhas_catalogo:
        if sem_mascara:
            # Cópia crua: toda coluna passa como está.
            tratamento = "copiar"
            resumo["copiar"] += 1
            tabelas.setdefault(tabela, []).append(f'"{coluna}"')
            nomes.setdefault(tabela, []).append(f'"{coluna}"')
            continue
        if tabela in PRESERVAR_TABELAS:
            # Tabela do motor de QA: tudo passa intacto, inclusive
            # jsonb e listas — é documentação, não dado de pessoa.
            tratamento = "copiar"
            preservadas_vistas.add(tabela)
            resumo["tabela_preservada"] += 1
        else:
            tratamento = classificar(coluna, tipo,
                                     check in ("t", "true", "1"),
                                     lista_texto)
            resumo[tratamento] = resumo.get(tratamento, 0) + 1
        condicao = EXCECOES_POR_LINHA.get((tabela, coluna))
        # A exceção do cliente escolhido soma-se às que já existiam (o
        # cercado do QA). Quando as duas valem para a mesma coluna, um OR:
        # nenhuma das duas deve deixar de valer por causa da outra.
        cond_tenant = cond_cliente.get(tabela)
        if cond_tenant:
            condicao = f"({condicao}) OR ({cond_tenant})" if condicao else cond_tenant
            if tratamento != "copiar":
                resumo["cliente_real"] += 1
        if condicao and tratamento != "copiar" and not cond_tenant:
            resumo["excecao_por_linha"] += 1
        tabelas.setdefault(tabela, []).append(
            expressao(coluna, tratamento, tempero_sql, condicao))
        nomes.setdefault(tabela, []).append(f'"{coluna}"')

    if sem_mascara:
        print("-- ATENCAO: plano gerado SEM MASCARA. A copia sai identica a "
              "producao,\n--   com nome, CPF, e-mail e atestado reais. So use "
              "com o ambiente fechado.", file=sys.stderr)
        for tabela, colunas in sorted(tabelas.items()):
            print(f"{tabela}\t{', '.join(colunas)}\t{', '.join(nomes[tabela])}")
        print(f"-- colunas: {resumo['copiar']} | todas copiadas cruas",
              file=sys.stderr)
        return 0

    # Nome errado na lista de preservadas ficaria mascarando em silêncio —
    # exatamente o tipo de erro que não dá sinal. Acusa alto.
    ausentes = PRESERVAR_TABELAS - preservadas_vistas
    if ausentes:
        print(f"-- AVISO: tabelas preservadas que NAO existem no catalogo: "
              f"{', '.join(sorted(ausentes))}", file=sys.stderr)

    for tabela, colunas in sorted(tabelas.items()):
        # Uma linha por tabela, três campos separados por TAB:
        #   tabela | expressões já mascaradas | nomes das colunas
        #
        # O terceiro existe para o COPY do destino nomear as colunas em vez
        # de confiar na ordem. Se um dia as duas estruturas divergirem em
        # ordem, um COPY posicional carregaria a coluna errada em silêncio —
        # data em campo de texto, e o erro apareceria longe daqui.
        print(f"{tabela}\t{', '.join(colunas)}\t{', '.join(nomes[tabela])}")

    # excecao_por_linha e cliente_real são MARCAS sobre colunas já contadas
    # no seu tratamento — somá-las ao total contaria a mesma coluna duas
    # vezes (a primeira versão imprimia 7007 de 5382).
    total = (sum(resumo.values())
             - resumo["excecao_por_linha"] - resumo["cliente_real"])
    mascaradas = total - resumo["copiar"] - resumo["tabela_preservada"]
    print(f"-- colunas: {total} | copiadas: {resumo['copiar']} "
          f"| preservadas por tabela (QA): {resumo['tabela_preservada']} "
          f"| mascaradas: {mascaradas} "
          f"(com excecao por linha: {resumo['excecao_por_linha']})",
          file=sys.stderr)
    if cliente_real:
        sem_vinculo = sorted(t for t, c in cond_cliente.items() if c is None)
        print(f"-- CLIENTE REAL {cliente_real}: {resumo['cliente_real']} colunas "
              f"saem CRUAS para as linhas dele, mascaradas para todos os outros.",
              file=sys.stderr)
        print(f"--   tabelas sem vinculo com cliente (seguem 100% mascaradas): "
              f"{len(sem_vinculo)}", file=sys.stderr)
    for k in ("cpf", "cnpj", "email", "telefone", "cep", "credencial",
              "json_vazio", "json_vazio_json", "lista_vazia", "generico"):
        if resumo.get(k):
            print(f"--   {k}: {resumo[k]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
