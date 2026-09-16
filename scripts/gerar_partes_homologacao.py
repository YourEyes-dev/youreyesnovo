#!/usr/bin/env python3
"""Consolida os scripts de entrega do Ponto em partes numeradas para colar
no SQL Editor da HOMOLOGACAO. Cada parte vira um arquivo em docs/homologacao/.
"""
import os, re, textwrap

D = 'docs/'
OUT = 'docs/homologacao/'
os.makedirs(OUT, exist_ok=True)

PARTES = [
 (1, 'travas_legais', 'Travas legais de cadastro e marcacao',
  'Recusa marcacao com data/hora futura, tolerancia acima do teto legal (5/10 min), '
  'intervalo de CCT abaixo do piso de 30 min e modo "registro por excecao" sem acordo anexado.',
  ['script_ponto_onda0_travas_legais.sql']),

 (2, 'vinculo_na_chave', 'A empresa entra na chave da apuracao diaria',
  'DESTRAVADOR: enquanto a chave for (tenant, CPF, data), dois vinculos do mesmo trabalhador '
  'colidem e varias das partes seguintes nao conseguem sequer gravar o dia. Vem antes de tudo.',
  ['script_ponto_onda1_vinculo_na_chave.sql']),

 (3, 'nsr_e_lotacao', 'NSR nas marcacoes e historico de lotacao',
  'Numero Sequencial de Registro (base do AFD da Portaria 671) e o historico de lotacao por '
  'estabelecimento, com vigencia.',
  ['script_ponto_onda1_nsr_e_lotacao.sql']),

 (4, 'versionamento_e_memoria', 'Versionamento de escala e memoria de calculo',
  'Parametro de escala passa a ter vigencia (mudar a escala hoje nao reescreve o mes passado) '
  'e cada apuracao guarda a memoria que permite refazer a conta.',
  ['script_ponto_onda1_versionamento_e_memoria.sql']),

 (5, 'integridade_do_registro', 'Integridade e imutabilidade do registro',
  'Cadeia de hash encadeada e conferivel, desconsideracao de marcacao por acrescimo (nunca '
  'apagando), deteccao de marcacoes uniformes, monitoramento do relogio contra a Hora Legal '
  'Brasileira e reabertura formal de competencia fechada.',
  ['script_ponto_onda2_cadeia_hash.sql',
   'script_ponto_onda2_desconsiderar_marcacao.sql',
   'script_ponto_onda2_marcacoes_uniformes.sql',
   'script_ponto_onda2_relogio_e_origem.sql',
   'script_ponto_onda2_reabertura_competencia.sql']),

 (6, 'calculo_da_jornada', 'Calculo da jornada: virada, tolerancia, escala e noturno',
  'Turno que cruza a meia-noite pertence ao dia de inicio; tolerancia de 5 min por marcacao '
  'alem do teto diario; hora extra medida contra a jornada REAL da escala; adicional noturno '
  'que acompanha a prorrogacao (Sumula 60, II).',
  ['script_ponto_onda3_turno_da_virada.sql',
   'script_ponto_onda3_tolerancia.sql',
   'script_ponto_onda3_jornada_escala_he.sql',
   'script_ponto_onda3_adicional_noturno_prorrogado.sql']),

 (7, 'intervalo_e_repouso', 'Intervalo, repouso semanal e domingo',
  'Faixas de intervalo do art. 71, indenizacao da supressao parcial (so os minutos '
  'suprimidos), pre-assinalacao formal, DSR (desconto por falta e reflexo das extras) e '
  'domingo/feriado trabalhado pago em dobro por inteiro.',
  ['script_ponto_onda4_faixas_intervalo.sql',
   'script_ponto_onda4_supressao_intervalo.sql',
   'script_ponto_onda4_pre_assinalacao.sql',
   'script_ponto_onda4_dsr.sql',
   'script_ponto_onda4_domingo_em_dobro.sql']),

 (8, 'banco_de_horas', 'Banco de horas com lastro, prazo e limites',
  'Credito so com instrumento vigente, prazo de compensacao gravado na apuracao (o que faz a '
  'conversao do saldo vencido finalmente disparar), alerta de saldo a vencer e de estouro do '
  'teto, limite de 10h diarias no regime de compensacao, apuracao por ciclo na 12x36 e '
  'liquidacao do saldo na rescisao.',
  ['script_ponto_onda5_banco_instrumento_vigente.sql',
   'script_ponto_onda5_prazo_vencimento_saldo.sql',
   'script_ponto_onda5_alertas_banco.sql',
   'script_ponto_onda5_limite_diario_compensacao.sql',
   'script_ponto_onda5_escala_12x36.sql',
   'script_ponto_onda5_liquidar_banco_rescisao.sql']),

 (9, 'fechamento_e_folha', 'Fechamento da competencia e envio para a folha',
  'Geracao dos espelhos em uma unica transacao (nada de espelho parcial), fechamento que '
  'confere ciencia do espelho e pendencias criticas, pacote da folha com grandezas e naturezas '
  'e fila de reenvio quando a folha esta indisponivel.',
  ['script_ponto_onda6_gerar_espelhos.sql',
   'script_ponto_onda6_fechamento_pendencias.sql',
   'script_ponto_onda6_fechamento_ciencia_espelho.sql',
   'script_ponto_onda6_pacote_folha.sql',
   'script_ponto_onda6_fila_folha_reenvio.sql']),

 (10, 'conformidade_portaria_671', 'Conformidade com a Portaria MTP 671/2021',
  'AEJ (saida obrigatoria do programa de tratamento), validacao e quarentena na importacao de '
  'AFD, comprovante como documento de verdade, gestao do certificado digital e dossie de '
  'fiscalizacao.',
  ['script_ponto_onda7_aej.sql',
   'script_ponto_onda7_afd_importacao.sql',
   'script_ponto_onda7_comprovantes.sql',
   'script_ponto_onda7_certificado_digital.sql',
   'script_ponto_onda7_dossie_fiscalizacao.sql']),

 (11, 'art62_lgpd_plano_acao', 'Art. 62, LGPD e ponte com o Plano de Acao',
  'Enquadramento do art. 62 (e deteccao de controle de fato que o descaracteriza), '
  'obrigatoriedade por estabelecimento (20 trabalhadores), REP alternativo so com instrumento, '
  'trava da competencia fechada, trilha de acesso a dado sensivel com contencao de enumeracao '
  'de CPFs e a ponte alerta -> acao 5W2H.',
  ['script_ponto_onda8_enquadramento_art62.sql',
   'script_ponto_onda8_descaracterizacao_art62.sql',
   'script_ponto_onda8_obrigatoriedade_estabelecimento.sql',
   'script_ponto_onda8_rep_alternativo_instrumento.sql',
   'script_ponto_onda8_competencia_fechada.sql',
   'script_ponto_onda8_lgpd_trilha_e_enumeracao.sql',
   'script_ponto_onda8_plano_de_acao.sql']),

 (12, 'instrumentos_e_escalas', 'Instrumento coletivo e escalas',
  'Vigilancia da vigencia das CCTs (vencida e a vencer, e vigencias sobrepostas), '
  'formalizacao da 12x36, turno ininterrupto de revezamento (6h da CF art. 7, XIV), troca de '
  'turno com aprovacao e recalculo, e radar de cobertura de turno.',
  ['script_ponto_onda9_cct_vigencia.sql',
   'script_ponto_onda10_escala_12x36_formalizacao.sql',
   'script_ponto_onda10_escala_revezamento.sql',
   'script_ponto_onda10_troca_turno.sql',
   'script_ponto_onda10_cobertura_turno.sql']),

 (13, 'atestados_e_ausencias', 'Atestados e ausencias legais',
  'Deteccao de atestados sobrepostos, ponte automatica do atestado longo para o afastamento '
  'previdenciario no 16o dia (Lei 8.213, arts. 59-60) e comprovacao das ausencias do art. 473.',
  ['script_ponto_onda11_atestados_sobrepostos.sql',
   'script_ponto_onda11_atestado_encaminha_inss.sql',
   'script_ponto_onda11_comprovacao_art473.sql']),

 (14, 'correcoes_da_bateria', 'Correcoes achadas pela propria bateria',
  'Feriado sem marcacao nao vira falta, motivo de ajuste com conteudo, dossie unico por '
  'competencia, folga compensatoria registrada e — o mais serio — o aviso repetido de atestado '
  'deixando de derrubar o afastamento do INSS.',
  ['script_ponto_correcoes_402_430_431.sql',
   'script_ponto_correcoes_421_410.sql',
   'script_ponto_correcao_451_401.sql']),

 (15, 'pecas_sem_script_de_entrega', 'Pecas que so existiam em migration',
  'A bateria na homologacao mostrou que estas pecas nunca tiveram script de entrega — '
  'existem no projeto desde sempre e nunca chegaram a producao: um dia por data na apuracao, '
  'o adicional de feriado da RN23 com a folga compensatoria, o motor agendado de vigilancias, '
  'a trava de imutabilidade da marcacao e o prazo obrigatorio do link de marcacao.',
  ['script_um_dia_por_data.sql',
   'script_ponto_rn23_feriado_adicional.sql',
   'script_ponto_vigilancias_diarias.sql',
   'script_ponto004_imutabilidade.sql',
   'script_ponto_links_prazo_obrigatorio.sql']),

 (16, 'massa_da_bancada', 'A massa da bancada passa a ser reaproveitada',
  'Ajuste so da bancada de testes: as ferramentas que montam empresa e admissao de mentira '
  'procuram antes de criar, para que uma sonda interrompida no meio nao deixe a proxima '
  'execucao presa em ERRO por massa pela metade.',
  ['script_qa_massa_reaproveitavel.sql']),
]

# --------------------------------------------------------------------------
# Extracao dos objetos que cada parte cria, para a conferencia final
# --------------------------------------------------------------------------
def marcador_de(corpo, txt):
    """Escolhe um trecho distintivo do corpo novo da funcao, para provar que a
    versao que chegou e esta — e nao a antiga de mesmo nome."""
    for lit in re.findall(r"'([^'%$\n]{30,70})'", corpo):
        if txt.count(lit) == 1 and re.search(r'[A-Za-z]{4}', lit):
            return lit
    return None


def objetos(txt):
    achados = []
    def add(tipo, nome, marcador=None):
        if '%' in nome or "'" in nome or not nome:
            return
        if nome.lower() in ('if', 'not', 'exists', 'public', 'table', 'or', 'replace'):
            return
        nome = nome.lower()
        if nome not in [a[1] for a in achados if a[0] == tipo]:
            achados.append((tipo, nome, marcador))

    for m in re.finditer(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z0-9_]+)\s*\(',
                         txt, re.I):
        resto = txt[m.end():]
        fim = re.search(r'\n\s*(CREATE|DROP|ALTER|COMMENT|DO)\s', resto)
        corpo = resto[:fim.start()] if fim else resto[:6000]
        add('funcao', m.group(1), marcador_de(corpo, txt))
    for m in re.finditer(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.([a-z0-9_]+)',
                         txt, re.I):
        if not m.group(1).lower().startswith('backup_'):
            add('tabela', m.group(1))
    for m in re.finditer(r'CREATE\s+TRIGGER\s+([a-z0-9_]+)', txt, re.I):
        if m.group(1).lower() != 'qa_guarda_cercado':
            add('gatilho', m.group(1))
    for m in re.finditer(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:CONCURRENTLY\s+)?(?:IF\s+NOT\s+EXISTS\s+)?([a-z0-9_]+)\s+ON',
                         txt, re.I):
        add('indice', m.group(1))
    for m in re.finditer(r'ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z0-9_]+)[^;]*?'
                         r'ADD\s+COLUMN\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z0-9_]+)',
                         txt, re.I | re.S):
        add('coluna', m.group(1) + '.' + m.group(2))
    return achados


SQL_CONF = """
-- ============================================================================
-- CONFERENCIA DESTA PARTE
-- Lista o que a parte deveria deixar no ambiente e diz o que chegou. A ultima
-- linha resume: OK quando nada faltou.
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
)
SELECT tipo, nome, CASE WHEN presente THEN 'chegou' ELSE 'FALTOU' END AS situacao
FROM estado
WHERE NOT presente
UNION ALL
SELECT 'RESUMO',
       (SELECT count(*) FROM estado WHERE presente)::text || ' de '
         || (SELECT count(*) FROM estado)::text || ' pecas no lugar',
       CASE WHEN (SELECT count(*) FROM estado WHERE NOT presente) = 0
            THEN 'OK' ELSE 'CONFERIR as linhas acima' END
ORDER BY 1 DESC, 2;
"""

CAB = """-- ============================================================================
-- HOMOLOGACAO — PONTO, PARTE {n:02d} de {total}: {titulo}
--
-- {desc}
--
-- ONDE COLAR
-- No SQL Editor do projeto de HOMOLOGACAO. Nao e para a producao: a producao
-- so muda por gesto manual seu, depois de conferida aqui.
--
-- COMO USAR
-- Cole o arquivo INTEIRO e execute uma vez. Pode rodar de novo sem risco
-- (idempotente). As partes tem ordem: rode da 01 para a {total:02d}, conferindo o
-- resultado de cada uma antes de passar para a seguinte.
--
-- O QUE ESTE ARQUIVO REUNE
{lista}
--
-- Ao final sai UMA conferencia, dizendo o que chegou e o que faltou.
-- ============================================================================

"""

total = len(PARTES)
resumo = []
for n, slug, titulo, desc, arquivos in PARTES:
    corpo = []
    for a in arquivos:
        corpo.append('\n\n-- ############################################################\n'
                     '-- BLOCO: %s\n'
                     '-- ############################################################\n' % a)
        corpo.append(open(D + a, encoding='utf-8').read())
    txt = '\n'.join(corpo)
    objs = objetos(txt)
    valores = ',\n'.join(
        "    ('%s', '%s', %s)" % (t, nm,
            ("'" + mk.replace("'", "''") + "'") if mk else 'NULL')
        for t, nm, mk in objs)
    lista = '\n'.join('--   * ' + a for a in arquivos)
    cab = CAB.format(n=n, total=total, titulo=titulo,
                     desc='\n-- '.join(textwrap.wrap(desc, 74)),
                     lista=lista)
    conf = SQL_CONF.format(valores=valores)
    dest = OUT + 'parte_%02d_%s.sql' % (n, slug)
    open(dest, 'w', encoding='utf-8').write(cab + txt + '\n' + conf)
    resumo.append((dest, len(objs), sum(1 for _ in open(dest))))

for d, o, l in resumo:
    print('%-58s %3d objetos %6d linhas' % (d, o, l))
