#!/usr/bin/env python3
"""Gera a fila de PRODUCAO a partir das partes ja conferidas na homologacao.

Cada parte de producao carrega, alem do conteudo identico ao que rodou na
homologacao:
  * cabecalho de producao, com a ordem e o aviso do retrato;
  * medicao de VOLUME: a contagem das tabelas vivas do Ponto e registrada no
    inicio e comparada no fim, para a conferencia dizer quantas linhas a parte
    tocou (o esperado, em quase todas, e ZERO);
  * copia de seguranca onde a parte altera dado existente.
"""
import os, re, glob

ORIG = 'docs/homologacao/'
OUT  = 'docs/producao/'
os.makedirs(OUT, exist_ok=True)

MARCA_CONF = '-- CONFERENCIA DESTA PARTE'

# Tabelas vivas do Ponto: sao as que a fila NAO deveria tocar. A contagem
# delas antes e depois e a prova de que a parte mexeu so na estrutura.
TABELAS = ['ponto_diario', 'ponto_marcacoes', 'ponto_espelhos',
           'ponto_banco_horas', 'ponto_alertas', 'ponto_links',
           'ponto_fechamentos', 'atestados']

# Partes que alteram dado existente e, por isso, guardam as linhas antes.
BACKUP = {
 15: dict(
   tabela='ponto_links',
   filtro='data_expiracao IS NULL',
   assunto='links_sem_prazo',
   desfazer='UPDATE public.ponto_links l SET data_expiracao = b.data_expiracao '
            'FROM backup_links_sem_prazo_AAAAMMDD b WHERE b.id = l.id;',
   porque='A parte preenche o prazo de expiracao dos links que estao sem prazo. '
          'E alteracao de dado existente — por isso as linhas afetadas sao '
          'copiadas antes.'),
}

CAB = """-- ============================================================================
-- PRODUCAO — PONTO, PARTE {n:02d} de {total}
--
-- ANTES DE COLAR ESTA PARTE
--   * o RETRATO (passo_00_retrato_antes.sql) ja tem de ter sido tirado;
--   * as partes anteriores ja tem de ter sido aplicadas, nesta ordem, cada uma
--     com a conferencia terminando em OK.
--
-- ONDE COLAR
-- No SQL Editor do projeto de PRODUCAO. Execute o arquivo INTEIRO, uma vez.
-- Pode rodar de novo sem risco: e idempotente.
--
-- CONTEUDO
-- Identico ao que foi aplicado e conferido na homologacao, onde a bateria do
-- Ponto fechou em 133 passou / 1 falhou / 0 erro.
{aviso}--
-- AO FINAL
-- Sai UMA conferencia com duas partes: as pecas que chegaram e o VOLUME —
-- quantas linhas das tabelas vivas do Ponto mudaram de quantidade. {esperado}
-- ============================================================================

"""

POS_VOLUME = """
-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (fim) — a mesma contagem, agora depois da parte.
-- ---------------------------------------------------------------------
DO $volume2$
DECLARE
  v record;
  n bigint;
  m text;
BEGIN
  FOR v IN SELECT tabela FROM public.ponto_entrega_volume
            WHERE parte = {n} AND tabela NOT LIKE '(copia)%'
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v.tabela) INTO n;
    m := NULL;
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=v.tabela AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', v.tabela) INTO m;
    END IF;
    UPDATE public.ponto_entrega_volume
       SET linhas_depois = n, marca_depois = m
     WHERE parte = {n} AND tabela = v.tabela;
  END LOOP;
END $volume2$;
"""

PRE_VOLUME = """
-- ---------------------------------------------------------------------
-- MEDICAO DE VOLUME (inicio) — a contagem de agora fica guardada para a
-- conferencia do fim comparar. Tabela propria, que nenhum sistema le.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ponto_entrega_volume (
  parte          integer NOT NULL,
  tabela         text    NOT NULL,
  linhas_antes   bigint  NOT NULL,
  linhas_depois  bigint,
  marca_antes    text,
  marca_depois   text,
  medido_em      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (parte, tabela)
);

-- Para a tabela criada por uma versao anterior desta fila continuar servindo.
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_antes  text;
ALTER TABLE public.ponto_entrega_volume ADD COLUMN IF NOT EXISTS marca_depois text;

-- Tabela nova em public fica exposta pela API do Supabase. Esta nao tem dado
-- pessoal, mas tambem nao e da conta de ninguem: RLS ligada e sem politica.
ALTER TABLE public.ponto_entrega_volume ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ponto_entrega_volume FROM PUBLIC;

DO $fechadura$
BEGIN
  EXECUTE 'REVOKE ALL ON public.ponto_entrega_volume FROM anon, authenticated';
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Papeis anon/authenticated nao existem nesta base.';
END $fechadura$;

DO $volume$
DECLARE
  t text;
  n bigint;
  m text;
BEGIN
  DELETE FROM public.ponto_entrega_volume WHERE parte = {n};
  FOREACH t IN ARRAY ARRAY[{lista}]
  LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    m := NULL;
    -- A marca e a data da ultima alteracao registrada na tabela. Contagem
    -- pega linha criada ou apagada; a marca pega linha ALTERADA.
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name=t AND column_name='updated_at') THEN
      EXECUTE format('SELECT max(updated_at)::text FROM public.%I', t) INTO m;
    END IF;
    INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, marca_antes)
    VALUES ({n}, t, n, m);
  END LOOP;
END $volume$;

"""

BACKUP_SQL = """
-- ---------------------------------------------------------------------
-- COPIA DE SEGURANCA — esta parte ALTERA dado existente
-- {porque}
-- A producao nao tem recuperacao a um ponto no tempo; a copia abaixo e o
-- unico resgate cirurgico. O comando que desfaz esta no fim do arquivo.
-- ---------------------------------------------------------------------
DO $copia$
DECLARE v_nome text := 'backup_{assunto}_' || to_char(CURRENT_DATE, 'YYYYMMDD');
BEGIN
  IF to_regclass('public.' || v_nome) IS NOT NULL THEN
    RAISE NOTICE 'A copia % ja existe — mantida como estava (a parte ja rodou hoje).', v_nome;
    RETURN;
  END IF;
  EXECUTE format(
    'CREATE TABLE public.%I AS SELECT * FROM public.{tabela} WHERE {filtro}', v_nome);
  RAISE NOTICE 'Copia de seguranca criada: %', v_nome;
END $copia$;

DO $copia_conta$
DECLARE v_nome text := 'backup_{assunto}_' || to_char(CURRENT_DATE, 'YYYYMMDD');
        n bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM public.%I', v_nome) INTO n;
  INSERT INTO public.ponto_entrega_volume (parte, tabela, linhas_antes, linhas_depois)
  VALUES ({n}, '(copia) ' || v_nome, 0, n)
  ON CONFLICT (parte, tabela) DO UPDATE SET linhas_depois = EXCLUDED.linhas_depois;
END $copia_conta$;

"""

CONF = POS_VOLUME + """
-- ============================================================================
-- CONFERENCIA DESTA PARTE — pecas e volume
-- ============================================================================
WITH esperado (tipo, nome, marcador) AS MATERIALIZED (
  VALUES
{valores}
), estado AS MATERIALIZED (
  SELECT e.tipo, e.nome, e.marcador,
         CASE e.tipo
           WHEN 'funcao'  THEN EXISTS (SELECT 1 FROM pg_proc p
                                        JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = 'public' AND p.proname = e.nome
                                         AND (e.marcador IS NULL
                                              OR p.prosrc LIKE '%' || e.marcador || '%'))
           WHEN 'tabela'  THEN to_regclass('public.' || e.nome) IS NOT NULL
           WHEN 'indice'  THEN EXISTS (SELECT 1 FROM pg_indexes
                                       WHERE schemaname = 'public' AND indexname = e.nome)
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_trigger
                                       WHERE NOT tgisinternal AND tgname = e.nome)
           WHEN 'coluna'  THEN EXISTS (SELECT 1 FROM information_schema.columns
                                       WHERE table_schema = 'public'
                                         AND table_name  = split_part(e.nome, '.', 1)
                                         AND column_name = split_part(e.nome, '.', 2))
         END AS presente
  FROM esperado e
), volume AS MATERIALIZED (
  SELECT v.tabela, v.linhas_antes AS antes, COALESCE(v.linhas_depois, v.linhas_antes) AS agora,
         v.marca_antes, v.marca_depois
  FROM public.ponto_entrega_volume v
  WHERE v.parte = {n}
)
SELECT 'peca faltando'::text AS o_que, tipo || ' ' || nome AS detalhe, 'FALTOU'::text AS situacao
FROM estado WHERE NOT presente
UNION ALL
SELECT 'volume', tabela || ': ' || antes || ' para ' || agora || ' linha(s)',
       CASE WHEN agora = antes THEN 'sem alteracao' ELSE 'MUDOU ' || (agora - antes) || ' linha(s)' END
FROM volume WHERE agora <> antes
UNION ALL
SELECT 'volume', tabela || ': conteudo alterado (ultima alteracao passou de '
       || COALESCE(marca_antes, '-') || ' para ' || COALESCE(marca_depois, '-') || ')',
       'CONFERIR — ou e movimento normal de cliente durante a execucao'
FROM volume WHERE marca_antes IS DISTINCT FROM marca_depois
  AND tabela <> {tabela_alterada}
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar; '
         || COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0)::text
         || ' linha(s) de dado vivo alteradas',
       CASE
         WHEN (SELECT count(*) FROM estado WHERE NOT presente) > 0 THEN 'CONFERIR — falta peca'
         WHEN {tolera_volume} THEN 'OK'
         WHEN COALESCE((SELECT sum(abs(agora - antes)) FROM volume), 0) > 0
           THEN 'CONFERIR — esta parte nao deveria alterar dado vivo'
         ELSE 'OK'
       END
ORDER BY 1 DESC, 2;
"""



def statements(txt):
    """Divide o arquivo em comandos de topo.

    Respeita marca de dollar-quote, texto entre aspas simples (onde um ponto e
    virgula NAO termina comando) e comentario de linha. Foi uma divisao ingenua
    demais que cortou um texto ao meio na primeira tentativa.
    """
    out = []; buf = []; i = 0; tag = None
    pat = re.compile(r'\$[A-Za-z_0-9]*\$')
    n = len(txt)
    while i < n:
        if tag is not None:
            if txt.startswith(tag, i):
                buf.append(tag); i += len(tag); tag = None
            else:
                buf.append(txt[i]); i += 1
            continue
        m = pat.match(txt, i)
        if m:
            tag = m.group(0); buf.append(tag); i = m.end(); continue
        c = txt[i]
        if c == "'":                      # texto entre aspas simples
            buf.append(c); i += 1
            while i < n:
                if txt[i] == "'" and i + 1 < n and txt[i + 1] == "'":
                    buf.append("''"); i += 2; continue
                if txt[i] == "'":
                    buf.append("'"); i += 1; break
                buf.append(txt[i]); i += 1
            continue
        if c == '-' and txt.startswith('--', i):   # comentario de linha
            j = txt.find('\n', i)
            j = n if j == -1 else j + 1
            buf.append(txt[i:j]); i = j; continue
        if c == ';':
            buf.append(';'); out.append(''.join(buf)); buf = []; i += 1; continue
        buf.append(c); i += 1
    if buf:
        out.append(''.join(buf))
    return out


def sem_conferencia_de_bancada(txt):
    """Neutraliza as conferencias herdadas que CHAMAM rotinas da bancada de QA.

    Elas vinham dos scripts de origem, que eram colados um a um num ambiente
    com a bancada instalada. Aqui as partes sao concatenadas e so a ultima
    conferencia aparece, entao essas chamadas nao servem para nada — e, na
    producao, onde a bancada nao esta completa, derrubam o arquivo inteiro
    (foi o que aconteceu com a parte 14: qa_caso_ponto_430 nao existe la).
    """
    saida = []
    for st in statements(txt):
        nu = re.sub(r'--[^\n]*', '', st)
        chama_sonda = re.search(r'\bqa_caso_[a-z0-9_]+\s*\(\s*\)', nu, re.I)
        e_criacao = re.match(r'\s*(CREATE|DO|ALTER|COMMENT|DROP|GRANT|REVOKE|SET)\b', nu, re.I)
        if chama_sonda and not e_criacao:
            saida.append(
                '\n-- (conferencia da bancada de QA removida nesta versao de producao:\n'
                '--  ela chama rotinas de teste que nao existem aqui, e so a conferencia\n'
                '--  do fim do arquivo e exibida pelo editor)\n')
            continue
        saida.append(st)
    return ''.join(saida)


def valores_da_parte(txt):
    """Reaproveita a lista de pecas ja montada na parte da homologacao."""
    i = txt.index('VALUES\n')
    j = txt.index('\n), estado AS MATERIALIZED')
    return txt[i + len('VALUES\n'):j]


partes = sorted(glob.glob(ORIG + 'parte_*.sql'))
total = len(partes)
for caminho in partes:
    nome = os.path.basename(caminho)
    n = int(nome.split('_')[1])
    txt = open(caminho, encoding='utf-8').read()
    corpo, conf_antiga = txt.split(MARCA_CONF, 1)
    valores = valores_da_parte(MARCA_CONF + conf_antiga)

    # o cabecalho da parte de homologacao sai; entra o de producao
    barra = '-- ' + '=' * 76
    fim_cab = corpo.index(barra, corpo.index(barra) + 1) + len(barra)
    corpo = corpo[fim_cab:].lstrip('\n')

    b = BACKUP.get(n)
    aviso = ('-- \n-- ATENCAO: esta parte ALTERA DADO EXISTENTE. Ela cria antes uma copia\n'
             '-- das linhas afetadas (backup_%s_AAAAMMDD) e traz, no fim do arquivo, o\n'
             '-- comando que desfaz.\n' % b['assunto']) if b else ''
    esperado = ('Nesta parte o volume MUDA — e o que ela veio fazer.'
                if b else 'Nesta parte o esperado e ZERO.')

    saida = [CAB.format(n=n, total=total, aviso=aviso, esperado=esperado)]
    saida.append("SET lock_timeout = '10s';\n")
    saida.append(PRE_VOLUME.format(n=n, lista=', '.join("'%s'" % t for t in TABELAS)))
    if b:
        saida.append(BACKUP_SQL.format(n=n, **b))
    saida.append(sem_conferencia_de_bancada(corpo))
    saida.append(CONF.format(n=n, valores=valores,
                             tolera_volume=('true' if b else 'false'),
                             tabela_alterada=("'%s'" % b['tabela'] if b else "''")))
    if b:
        saida.append('\n-- ---------------------------------------------------------------------\n'
                     '-- PARA DESFAZER esta parte (troque AAAAMMDD pela data de hoje):\n'
                     '--   %s\n'
                     '-- ---------------------------------------------------------------------\n'
                     % b['desfazer'])

    destino = OUT + nome
    open(destino, 'w', encoding='utf-8').write(''.join(saida))
    print('%-52s %s' % (destino, 'com copia de seguranca' if b else ''))
