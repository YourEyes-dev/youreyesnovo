# -*- coding: utf-8 -*-
"""Manual do RH — Ponto e Banco de Horas (empresa COM banco). PDF padrão ABNT."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER, TA_LEFT
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, PageBreak,
                                Table, TableStyle, ListFlowable, ListItem, KeepTogether)

import os
# Gera o PDF no mesmo diretório deste script (docs/). Rode: python3 gerar_manual_banco_horas.py
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Manual_RH_Ponto_Banco_de_Horas.pdf")

NAVY=colors.HexColor("#1e293b"); BLUE=colors.HexColor("#2563eb"); GRAY=colors.HexColor("#475569")
LIGHT=colors.HexColor("#f1f5f9"); EXBG=colors.HexColor("#eef5ff"); EXB=colors.HexColor("#b9d4ff")
WBG=colors.HexColor("#fff7ed"); WB=colors.HexColor("#fdba74"); GREEN=colors.HexColor("#166534")

styles=getSampleStyleSheet()
BODY=ParagraphStyle("Corpo",parent=styles["Normal"],fontName="Helvetica",fontSize=12,leading=18,
                    alignment=TA_JUSTIFY,spaceAfter=6,textColor=colors.HexColor("#111827"))
H1=ParagraphStyle("H1",parent=styles["Heading1"],fontName="Helvetica-Bold",fontSize=14,leading=20,
                  textColor=NAVY,spaceBefore=14,spaceAfter=8,alignment=TA_LEFT)
H2=ParagraphStyle("H2",parent=styles["Heading2"],fontName="Helvetica-Bold",fontSize=12.5,leading=18,
                  textColor=BLUE,spaceBefore=10,spaceAfter=5,alignment=TA_LEFT)
SMALL=ParagraphStyle("Small",parent=BODY,fontSize=9.5,leading=13,textColor=GRAY)
CAPA_T=ParagraphStyle("CapaT",parent=styles["Title"],fontName="Helvetica-Bold",fontSize=20,leading=26,
                      textColor=NAVY,alignment=TA_CENTER)
CAPA_S=ParagraphStyle("CapaS",parent=styles["Normal"],fontName="Helvetica",fontSize=13,leading=19,
                      textColor=GRAY,alignment=TA_CENTER)
CAPA_TOP=ParagraphStyle("CapaTop",parent=styles["Normal"],fontName="Helvetica-Bold",fontSize=12,
                        leading=16,textColor=GRAY,alignment=TA_CENTER)
EXTXT=ParagraphStyle("ExTxt",parent=BODY,fontSize=11,leading=16,spaceAfter=0,textColor=colors.HexColor("#0b3b8c"))
EXLBL=ParagraphStyle("ExLbl",parent=styles["Normal"],fontName="Helvetica-Bold",fontSize=10,leading=13,
                     textColor=BLUE,spaceAfter=2)
CELL=ParagraphStyle("Cell",parent=styles["Normal"],fontName="Helvetica",fontSize=9.8,leading=12.5,
                    textColor=colors.HexColor("#111827"))
CELLH=ParagraphStyle("CellH",parent=CELL,fontName="Helvetica-Bold",textColor=colors.white)

def ex(label,*paras,bg=EXBG,bd=EXB,lc=BLUE,tc=colors.HexColor("#0b3b8c")):
    inner=[Paragraph(label,ParagraphStyle("l",parent=EXLBL,textColor=lc))]
    for p in paras: inner.append(Paragraph(p,ParagraphStyle("t",parent=EXTXT,textColor=tc)))
    t=Table([[inner]],colWidths=[15.0*cm])
    t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),bg),("BOX",(0,0),(-1,-1),0.8,bd),
        ("LEFTPADDING",(0,0),(-1,-1),10),("RIGHTPADDING",(0,0),(-1,-1),10),
        ("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7)]))
    return KeepTogether([Spacer(1,3),t,Spacer(1,7)])

def warn(label,*paras): return ex(label,*paras,bg=WBG,bd=WB,lc=colors.HexColor("#9a3412"),tc=colors.HexColor("#7c2d12"))

def bullets(items):
    return ListFlowable([ListItem(Paragraph(t,BODY),leftIndent=6,value="•") for t in items],
                        bulletType="bullet",bulletColor=BLUE,leftIndent=14,bulletFontSize=10)

def make_table(data,colWidths,keep=True,align=None):
    rows=[]
    for ri,row in enumerate(data):
        st=CELLH if ri==0 else CELL
        rows.append([Paragraph(str(c),st) for c in row])
    t=Table(rows,colWidths=colWidths,repeatRows=1)
    sty=[("BACKGROUND",(0,0),(-1,0),NAVY),("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,LIGHT]),
         ("GRID",(0,0),(-1,-1),0.4,colors.HexColor("#cbd5e1")),("VALIGN",(0,0),(-1,-1),"MIDDLE"),
         ("LEFTPADDING",(0,0),(-1,-1),5),("RIGHTPADDING",(0,0),(-1,-1),5),
         ("TOPPADDING",(0,0),(-1,-1),4),("BOTTOMPADDING",(0,0),(-1,-1),4)]
    t.setStyle(TableStyle(sty))
    return KeepTogether(t) if keep else t

S=[]  # story

# ---------- CAPA ----------
S+=[Spacer(1,3.2*cm),Paragraph("DEPARTAMENTO PESSOAL",CAPA_TOP),Spacer(1,2.6*cm),
    Paragraph("Manual do Ponto Eletrônico e do Banco de Horas",CAPA_T),Spacer(1,0.5*cm),
    Paragraph("Guia prático para o RH — conferência diária, banco de horas, "
              "compensações e fechamento do mês",CAPA_S),Spacer(1,6.5*cm),
    Paragraph("Para empresas que utilizam <b>banco de horas</b>.<br/>"
              "Linguagem simples, com exemplos. Documento de apoio ao Departamento Pessoal.",CAPA_S),
    Spacer(1,0.5*cm),Paragraph("Versão 1 — 2026",CAPA_S),PageBreak()]

# ---------- SUMÁRIO ----------
S.append(Paragraph("Sumário",H1))
for s in [
 "1. Para que serve este manual",
 "2. Conceitos que você vai usar o tempo todo",
 "3. O espelho de ponto: o que cada coluna significa",
 "4. Como o banco de horas enche e esvazia",
 "5. O dia a dia: o que conferir todos os dias",
 "6. Faltas: quando vai para a folha e quando compensar pelo banco",
 "7. Todas as situações de um dia (tabela de referência)",
 "8. Fechamento do mês: quando fecha, o que trava e como fechar",
 "9. O acerto do banco de horas (fim do período)",
 "10. Checklists (diário e mensal)",
 "11. Perguntas frequentes e erros comuns",
]:
    S.append(Paragraph(s,ParagraphStyle("sum",parent=BODY,spaceAfter=4,alignment=TA_LEFT)))
S.append(PageBreak())

# ---------- 1 ----------
S.append(Paragraph("1. Para que serve este manual",H1))
S.append(Paragraph("Este manual ensina, passo a passo e em linguagem simples, como o "
 "Departamento Pessoal cuida do ponto eletrônico numa empresa que usa <b>banco de horas</b>. "
 "Ele cobre o que conferir todo dia, como ler o espelho, como o banco de horas enche e esvazia, "
 "o que fazer com faltas, e como fechar o mês com segurança. Sempre que possível, há um "
 "<b>exemplo</b> para fixar a ideia.",BODY))
S.append(Paragraph("A regra de ouro é simples: <b>resolva as pendências ao longo do mês</b>, "
 "não deixe tudo para o último dia. Um mês acompanhado de perto fecha em minutos.",BODY))

# ---------- 2 ----------
S.append(Paragraph("2. Conceitos que você vai usar o tempo todo",H1))
S.append(Paragraph("<b>Jornada</b> — quantas horas a pessoa deve trabalhar no dia, segundo a "
 "escala dela (por exemplo, 8h por dia). É o “esperado” do dia.",BODY))
S.append(Paragraph("<b>Escala</b> — o horário de trabalho da pessoa (quais dias, quais horas, "
 "quanto de intervalo). Cada pessoa tem uma escala por vez. Sem escala, o sistema não sabe qual "
 "é a jornada e não consegue apurar o dia direito.",BODY))
S.append(Paragraph("<b>Banco de horas</b> — é a “poupança” de horas. Quando a pessoa trabalha "
 "<b>a mais</b> que a jornada, ganha <b>crédito</b>. Quando trabalha <b>a menos</b>, fica com "
 "<b>débito</b>. O que sobra ou falta vai se acumulando mês a mês, até a hora do acerto.",BODY))
S.append(Paragraph("<b>Crédito, débito e saldo</b> — crédito é hora a favor; débito é hora "
 "devida; saldo é a conta final (saldo anterior + créditos − débitos).",BODY))
S.append(Paragraph("<b>Falta</b> — dia em que a pessoa deveria trabalhar e não trabalhou. Pode "
 "ser <b>justificada</b> (atestado, por exemplo) ou <b>não justificada</b>.",BODY))
S.append(Paragraph("<b>Compensação de falta</b> — é quando, em vez de descontar a falta na folha, "
 "a empresa usa o <b>saldo do banco</b> da pessoa para cobrir aquele dia. É uma decisão "
 "deliberada, que depende de acordo e da concordância da pessoa (explico na seção 6).",BODY))
S.append(Paragraph("<b>Pré-assinalação do intervalo</b> — quando a pessoa bate só entrada e "
 "saída (não bate o almoço), o intervalo é declarado e descontado automaticamente. Serve para "
 "jornadas de dia inteiro.",BODY))
S.append(Paragraph("<b>Fechar o mês</b> — travar a competência para ninguém mais alterar e gerar "
 "o espelho oficial de cada pessoa, que será assinado (ciência). O sistema fecha sempre "
 "<b>por mês</b>.",BODY))

# ---------- 3 ESPELHO ----------
S.append(Paragraph("3. O espelho de ponto: o que cada coluna significa",H1))
S.append(Paragraph("O espelho é o relatório do mês de cada pessoa, dia a dia. Estas são as "
 "colunas que mais importam:",BODY))
leg=[["Sigla","O que é","Em palavras simples"],
 ["H.D.","Total de horas do dia","Quanto a pessoa realmente trabalhou naquele dia."],
 ["H.N.","Hora normal (prevista)","Quanto ela <b>deveria</b> ter trabalhado (a jornada)."],
 ["H.E.","Hora extra","Horas que passaram da jornada (vão para o banco ou a pagar)."],
 ["H.C.","Hora compensada","Horas usadas para compensar (ex.: sábado de equalização)."],
 ["H.A.","Hora de ausência","Horas que faltaram no dia (atraso/saída antecipada)."],
 ["A.N.","Adicional noturno","Horas trabalhadas no período noturno, quando houver."],
 ["F.N.","Falta não justificada","Dia de falta sem justificativa (vai para a folha)."],
 ["F.J.","Falta justificada","Dia de falta abonado (não desconta)."]]
S.append(make_table(leg,[1.6*cm,4.6*cm,8.8*cm]))
S.append(Spacer(1,5))
S.append(Paragraph("Além das colunas, cada dia traz uma <b>Ocorrência</b> (o rótulo do que "
 "aconteceu): “Soma Banco Horas” quando sobrou hora, “Diminui Banco Horas” quando faltou, "
 "“Falta”, “Justificado”, “Compensado”, “Pendência — marcação incompleta”, entre outros.",BODY))
S.append(ex("Exemplo de leitura de um dia",
 "Numa terça, a pessoa tem H.N. 8:00 (jornada) e H.D. 8:20 (trabalhou). A diferença de 20 "
 "minutos aparece como H.E. 0:20 e vira <b>crédito</b> no banco. A ocorrência do dia é "
 "“Soma Banco Horas”."))
S.append(ex("Exemplo de leitura do mês",
 "No rodapé: H.D. (trabalhado) 181h e H.N. (previsto) 184h48. Parece que faltou hora — mas, "
 "se no mês houve uma <b>falta</b> de 8h38, essa falta é da <b>folha</b>, não do banco. "
 "Por isso o banco ainda pode estar positivo: ele só conta as horas a mais/a menos dos dias "
 "<b>trabalhados</b>. Ver a seção 6."))

# ---------- 4 BANCO ----------
S.append(Paragraph("4. Como o banco de horas enche e esvazia",H1))
S.append(Paragraph("Todo dia trabalhado é comparado com a jornada:",BODY))
S.append(bullets([
 "Trabalhou <b>a mais</b> → entra <b>crédito</b> (ocorrência “Soma Banco Horas”).",
 "Trabalhou <b>a menos</b> → entra <b>débito</b> (ocorrência “Diminui Banco Horas”).",
 "Trabalhou <b>igual</b> à jornada → não mexe no banco.",
]))
S.append(Paragraph("Duas proteções automáticas que você precisa conhecer:",H2))
S.append(bullets([
 "<b>Tolerância</b> (normalmente 10 minutos): diferenças pequenas, de poucos minutos, não "
 "contam — nem como crédito, nem como débito.",
 "<b>Teto diário de 2 horas extras</b>: o que passa de 2h extras num dia pode ficar “retido” "
 "(ocorrência “Excedente retido”), para ser avaliado à parte, em vez de inflar o banco.",
]))
S.append(ex("Exemplo de um mês",
 "Jornada de 8h/dia. Na segunda a pessoa fez 8h20 (+20 de crédito); na terça, 7h45 "
 "(−15 de débito, descontada a tolerância); nos outros dias, bateu certo. No fim do mês o "
 "banco fica com <b>+5 minutos</b> de saldo (20 de crédito − 15 de débito)."))
S.append(Paragraph("O <b>saldo</b> do mês é somado ao <b>saldo anterior</b> e segue acumulando. "
 "O espelho mostra isso no quadro “Resumo do Banco de Horas”: Saldo Anterior + Crédito − Débito "
 "= Saldo Atual.",BODY))

# ---------- 5 DIA A DIA ----------
S.append(Paragraph("5. O dia a dia: o que conferir todos os dias",H1))
S.append(Paragraph("A rotina diária evita o acúmulo de problemas no fim do mês. Todo dia (ou a "
 "cada poucos dias), faça:",BODY))
S.append(Paragraph("5.1 Acompanhar o espelho",H2))
S.append(bullets([
 "Abra <b>Ponto &rarr; Espelho</b> e veja os dias de cada pessoa.",
 "Observe o <b>status</b> de cada dia: Regular, Atraso, Falta, Incompleto, Justificado.",
 "Resolva os problemas na hora que aparecem — é muito mais fácil do que no fechamento.",
]))
S.append(Paragraph("5.2 Aprovar os ajustes pendentes",H2))
S.append(Paragraph("Em <b>Ponto &rarr; Ajustes</b>, aprove ou rejeite os pedidos de correção de "
 "horário (esquecimento de batida, correção de horário, abono). Enquanto houver ajuste pendente, "
 "o mês <b>não fecha</b>.",BODY))
S.append(Paragraph("5.3 Resolver os dias incompletos",H2))
S.append(Paragraph("Um dia “incompleto” é quando faltou uma batida (a pessoa esqueceu de bater, "
 "ou o relógio falhou). Esse dia fica “pendente” e <b>não gera débito</b> — mas <b>trava o "
 "fechamento</b> até ser resolvido.",BODY))
S.append(ex("Exemplo",
 "A pessoa bateu entrada 08:03 e saída 17:46, mas faltou o par do intervalo e o dia ficou "
 "“incompleto”. Confirmando com o gestor que ela trabalhou normal, você lança a batida que "
 "faltou pelo ajuste e aprova — o dia deixa de ser pendência."))

# ---------- 6 FALTAS ----------
S.append(Paragraph("6. Faltas: quando vai para a folha e quando compensar pelo banco",H1))
S.append(Paragraph("Esta é a parte que mais gera dúvida. Guarde a ideia central: <b>falta e "
 "banco de horas são coisas separadas</b>.",BODY))

S.append(Paragraph("6.1 O padrão: a falta vai para a folha",H2))
S.append(Paragraph("Quando a pessoa falta e você <b>não faz nada</b>, o sistema trata a falta na "
 "<b>folha</b> — desconta o dia e o descanso da semana. O <b>banco não é mexido</b>, "
 "<b>mesmo que a pessoa tenha saldo positivo</b>. Isso é proposital: evita descontar a pessoa "
 "duas vezes (no banco e na folha) e mantém o banco só para compensar jornada.",BODY))
S.append(ex("Exemplo",
 "A pessoa tem +10h de saldo no banco e falta um dia, sem atestado. Se você não fizer nada, o "
 "banco continua com +10h e a <b>falta é descontada na folha</b>. O saldo positivo não "
 "“paga” a falta sozinho."))

S.append(Paragraph("6.2 A falta justificada (atestado, abono)",H2))
S.append(Paragraph("Se a falta tem justificativa válida (atestado médico, por exemplo), você "
 "<b>abona</b> o dia. Ele aparece como <b>Justificado / F.J.</b> e <b>não é descontado</b> — "
 "nem na folha, nem no banco.",BODY))
S.append(ex("Exemplo",
 "A pessoa trouxe atestado de 1 dia. Em <b>Ponto &rarr; Ajustes</b> (ou no Espelho), abone o dia "
 "com a justificativa “Atestado médico”. O dia fica Justificado e não desconta nada."))

S.append(Paragraph("6.3 Quando você QUER usar o banco: a compensação de falta",H2))
S.append(Paragraph("Se a ideia é <b>usar o saldo positivo da pessoa para cobrir a falta</b> "
 "(em vez de descontar na folha), aí sim existe um processo: a <b>Compensação de Falta</b>. "
 "Ela transforma a falta em um <b>débito no banco</b> e <b>tira a falta do desconto da folha</b>.",BODY))
S.append(Paragraph("Para o botão aparecer, três coisas precisam existir:",BODY))
S.append(bullets([
 "<b>Regime de banco de horas</b> ativo na empresa.",
 "<b>Acordo</b> vigente da pessoa com a opção <b>“Autoriza compensação de falta”</b> ligada.",
 "A pessoa ter <b>saldo</b> suficiente (senão o banco fica negativo — vira dívida de horas).",
]))
S.append(Paragraph("Passo a passo:",H2))
S.append(bullets([
 "Vá em <b>Ponto &rarr; Apuração &rarr; Comp. Faltas</b>.",
 "No cartão “Faltas do mês”, ache a falta da pessoa e clique em <b>“Compensar”</b>.",
 "<b>Autorizar</b> (o gestor aprova usar o banco para cobrir aquele dia).",
 "<b>Homologar</b> (RH) — exigido apenas quando a falta passa do limite configurado.",
 "<b>Registrar ciência</b> (a pessoa concorda em usar as horas dela).",
 "Pronto: vira <b>débito no banco</b> e a falta <b>sai</b> do desconto da folha.",
]))
S.append(ex("Exemplo",
 "A pessoa tem +16h de saldo e faltou um dia de 8h, sem atestado, mas pediu para “descontar do "
 "banco”. Com acordo e ciência, você faz a Compensação de Falta: o banco cai para +8h e a "
 "falta não é descontada na folha."))
S.append(warn("Atenção",
 "Não dá para tomar o saldo de alguém sem concordância. Por isso a compensação exige o acordo e "
 "a ciência. Sem isso, o certo é a falta ir para a folha (item 6.1)."))

# ---------- 7 TABELA DE SITUAÇÕES ----------
S.append(Paragraph("7. Todas as situações de um dia (tabela de referência)",H1))
S.append(Paragraph("Use esta tabela para saber, em cada caso, o que o sistema faz sozinho e o "
 "que cabe a você:",BODY))
sit=[["Situação do dia","Como aparece","Banco","Folha","O que o RH faz"],
 ["Trabalhou além da jornada (até 2h)","Soma Banco Horas / H.E.","+ crédito","—","Nada"],
 ["Trabalhou além de 2h no dia","Excedente retido","crédito até o teto","—","Avaliar o excedente à parte"],
 ["Trabalhou menos (atraso/saída antec.)","Diminui Banco Horas / H.A.","− débito","—","Nada, ou justificar"],
 ["Faltou sem justificativa","Falta / F.N.","intacto","desconta dia + DSR","Deixar na folha OU compensar (6.3)"],
 ["Faltou com atestado/abono","Justificado / F.J.","intacto","não desconta","Abonar com justificativa"],
 ["Faltou e foi compensada pelo banco","(compensação)","− débito","não desconta","Fazer a Compensação de Falta"],
 ["Dia incompleto (faltou batida)","Pendência","não mexe (zero)","—","Ajustar/abonar antes de fechar"],
 ["Domingo/feriado trabalhado","Hora extra 100%","crédito 100% ou pagar","—","Conferir"],
 ["Sábado de equalização trabalhado","Compensado / H.C.","fecha a carga do mês","—","Conferir o sábado definido"],
 ["Folga compensatória","Folga compensatória","− débito (da compensação)","—","Lançar a folga"],
 ["Férias / afastamento / feriado","Protegido","intacto","conforme a regra","Registrar o evento"]]
S.append(make_table(sit,[4.2*cm,3.1*cm,2.7*cm,2.6*cm,3.4*cm]))
S.append(Spacer(1,4))
S.append(Paragraph("Observação: “DSR” é o descanso semanal remunerado. A falta não justificada "
 "costuma fazer perder também o DSR da semana — por isso ela “pesa” mais na folha.",SMALL))

# ---------- 8 FECHAMENTO ----------
S.append(Paragraph("8. Fechamento do mês: quando fecha, o que trava e como fechar",H1))
S.append(Paragraph("8.1 Quando fechar",H2))
S.append(Paragraph("Feche perto do fim do mês ou no começo do mês seguinte, depois de resolver as "
 "pendências. O sistema fecha <b>um mês por vez</b>.",BODY))
S.append(Paragraph("8.2 O que TRAVA o fechamento (pendências)",H2))
S.append(Paragraph("O mês <b>não fecha</b> enquanto houver pendência. As mais comuns:",BODY))
S.append(bullets([
 "<b>Ajuste de ponto aguardando aprovação</b> — aprove ou rejeite em Ponto &rarr; Ajustes.",
 "<b>Dia incompleto sem tratamento</b> — ajuste a batida que faltou ou abone o dia.",
 "<b>Dia muito curto sem motivo</b> — um dia que fechou bem abaixo da jornada (por padrão, 60 "
 "minutos ou mais a menos) sem folga, abono ou ajuste. Resolva lançando o que faltou ou "
 "justificando.",
 "<b>Espelho sem ciência</b> (quando a empresa exige) — falta a pessoa dar ciência no espelho.",
]))
S.append(ex("Exemplo — por que não fecha",
 "Ao clicar em “Fechar Período”, aparece “Bloqueado por pendências: 2 dias incompletos e 1 "
 "ajuste pendente”. Resolva esses 3 itens e o botão libera."))
S.append(Paragraph("8.3 Passo a passo para fechar",H2))
S.append(bullets([
 "Confira o <b>banco de horas</b> em Ponto &rarr; Apuração &rarr; Banco Horas (clique em "
 "“Apurar agora” para recalcular créditos e débitos).",
 "Se for o caso, faça as <b>compensações de falta</b> (seção 6.3).",
 "Vá em <b>Ponto &rarr; Apuração &rarr; Fechamento</b> e escolha a competência (o mês).",
 "Se não houver pendências, clique em <b>“Fechar Período”</b> e confirme.",
 "O sistema <b>trava o mês</b> e gera os espelhos de cada pessoa.",
]))
S.append(Paragraph("8.4 Espelhos e ciência",H2))
S.append(Paragraph("No cartão “Espelhos de Ponto”, baixe o PDF de cada pessoa, envie e registre a "
 "<b>ciência</b> (ou <b>ressalva</b>, se a pessoa discordar). A ciência é o que dá validade ao "
 "controle de jornada.",BODY))
S.append(Paragraph("8.5 Reabrir um mês já fechado",H2))
S.append(Paragraph("Se precisar corrigir algo depois de fechado, use <b>“Reabrir Período”</b> e "
 "informe o motivo. Atenção: espelhos ainda não confirmados são descartados; os já confirmados "
 "permanecem. Depois de corrigir, feche de novo.",BODY))

# ---------- 9 ACERTO ----------
S.append(Paragraph("9. O acerto do banco de horas (fim do período)",H1))
S.append(Paragraph("O banco tem um <b>prazo de compensação</b> (por exemplo, 6 meses). Ao chegar "
 "no fim desse prazo, além de fechar o mês normalmente, você acerta o saldo acumulado de cada "
 "pessoa, conforme o combinado no acordo:",BODY))
S.append(bullets([
 "<b>Saldo positivo (crédito):</b> vira folga, é <b>pago como hora extra</b>, ou é <b>zerado</b> "
 "(se foi o combinado).",
 "<b>Saldo negativo (débito):</b> tratado conforme o acordo (desconto ou perdão).",
]))
S.append(Paragraph("Para ajustar o saldo de uma pessoa pela tela, em Ponto &rarr; Apuração "
 "&rarr; Banco Horas, use <b>“Movimentar”</b> (lançar um crédito/débito/compensação) ou "
 "<b>“Editar Banco de Horas”</b> (ajustar o saldo anterior).",BODY))
S.append(warn("Zeragem em massa",
 "Se for acertar o saldo de muitas pessoas de uma vez, não faça uma a uma: peça ao responsável "
 "técnico para rodar o procedimento em lote (com backup antes). Pela tela, faça só ajustes "
 "pontuais."))
S.append(ex("Exemplo",
 "No fim do semestre, a pessoa está com +12h. Pelo acordo, o excedente é pago como hora extra: "
 "você registra o pagamento e zera o saldo; ou, se for folga, agenda a folga e o saldo cai na "
 "medida em que ela folga."))

# ---------- 10 CHECKLISTS ----------
S.append(Paragraph("10. Checklists",H1))
S.append(Paragraph("Todos os dias (ou a cada poucos dias):",H2))
S.append(bullets([
 "Conferir o Espelho e resolver dias incompletos cedo.",
 "Aprovar / rejeitar ajustes pendentes.",
 "Abonar faltas justificadas (atestados).",
]))
S.append(Paragraph("No fechamento do mês:",H2))
S.append(bullets([
 "Zerar as pendências (ajuste pendente, dia incompleto, dia curto sem motivo, ciência).",
 "Apurar o banco de horas e conferir créditos/débitos.",
 "Decidir, caso a caso, as faltas: folha ou compensação pelo banco.",
 "Clicar em “Fechar Período”.",
 "Enviar os espelhos e colher a ciência.",
]))
S.append(Paragraph("No fim do período de compensação:",H2))
S.append(bullets([
 "Fechar o último mês do período.",
 "Conferir o saldo de cada pessoa.",
 "Acertar o saldo conforme o acordo (pagar, folga ou zerar).",
]))

# ---------- 11 FAQ ----------
S.append(Paragraph("11. Perguntas frequentes e erros comuns",H1))
S.append(Paragraph("<b>“A pessoa tem saldo positivo; mesmo assim a falta foi para a folha. "
 "Está certo?”</b> Sim. Por padrão a falta vai para a folha e o banco não é mexido. Para usar o "
 "saldo, é preciso fazer a Compensação de Falta (seção 6.3).",BODY))
S.append(Paragraph("<b>“Trabalhou menos que o previsto no mês, mas o banco creditou. Como?”</b> "
 "Quando há uma falta no meio: a falta é da folha e não do banco. O banco só conta as horas a "
 "mais/a menos dos dias trabalhados — por isso pode ficar positivo mesmo com o total do mês "
 "abaixo do previsto.",BODY))
S.append(Paragraph("<b>“O mês não fecha.”</b> Há pendência — quase sempre um ajuste pendente, um "
 "dia incompleto ou um dia curto sem motivo. Veja o cartão de pendências e resolva.",BODY))
S.append(Paragraph("<b>“As horas da pessoa estão todas como extra.”</b> Provavelmente falta a "
 "<b>escala</b> dela: sem jornada para comparar, tudo vira extra. Atribua a escala.",BODY))
S.append(Paragraph("<b>“Quero descontar a falta do banco.”</b> Use a Compensação de Falta "
 "(acordo + ciência). Sem isso, a falta fica na folha.",BODY))
S.append(Paragraph("<b>“Quando o excedente é pago em dinheiro em vez de ir para o banco?”</b> "
 "Quando passa do teto diário (acima de 2h no dia, o que sobra pode ficar retido para avaliação) "
 "ou no acerto do período, se o combinado for pagar o saldo positivo.",BODY))
S.append(Spacer(1,8))
S.append(Paragraph("Em qualquer passo com dúvida, fale com o responsável pelo sistema antes de "
 "alterar dados em massa.",SMALL))

# ---------- build ----------
def rodape(c,doc):
    c.saveState(); c.setFont("Helvetica",8); c.setFillColor(GRAY)
    if doc.page>1:
        c.drawString(3*cm,1.2*cm,"Manual do Ponto e Banco de Horas — Departamento Pessoal")
        c.drawRightString(A4[0]-2*cm,1.2*cm,"%d"%doc.page)
    c.restoreState()

doc=SimpleDocTemplate(OUT,pagesize=A4,leftMargin=3*cm,rightMargin=2*cm,topMargin=3*cm,bottomMargin=2*cm,
                      title="Manual do Ponto e Banco de Horas",author="YourEyes")
doc.build(S,onFirstPage=rodape,onLaterPages=rodape)
print("OK",OUT)
