import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  BookOpen,
  Brain,
  Plus,
  Link2,
  BarChart3,
  ShieldCheck,
  Activity,
  FileText,
  ClipboardList,
  ChevronRight,
  ChevronLeft,
  X,
  CheckCircle2,
  Circle,
  Lightbulb,
  Lock,
  Sparkles,
  AlertTriangle,
  RefreshCw,
  Wrench,
  Users,
  Eye,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { ManualPsicossocial } from "./ManualPsicossocial";

interface GuiaRapidoPsicossocialProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const PASSOS = [
  {
    id: "overview",
    icon: Brain,
    color: "text-purple-600",
    bgColor: "bg-purple-50",
    titulo: "O que é esse módulo?",
    subtitulo: "Visão geral — para quem é e o que resolve",
    descricao:
      "O módulo Psicossocial do YourEyes ajuda sua empresa a identificar, avaliar e tratar riscos relacionados ao trabalho — como estresse excessivo, falta de autonomia e esgotamento — de forma automática e em conformidade com a lei (NR-01).",
    destaques: [
      { icon: Users, label: "Para: RH, Gestores e SST" },
      { icon: ShieldCheck, label: "Exigido pela NR-01 / GRO" },
      { icon: Lock, label: "100% Anônimo para o colaborador" },
      { icon: Sparkles, label: "Questionários validados cientificamente" },
    ],
    dica: "Você não precisa ser especialista. O sistema faz as análises — você só precisa criar a campanha e distribuir o link.",
  },
  {
    id: "coleta",
    icon: Plus,
    color: "text-purple-600",
    bgColor: "bg-purple-50",
    titulo: "Passo 1 — Crie uma Campanha",
    subtitulo: "Por onde tudo começa",
    descricao:
      "A campanha é o ponto de partida. Você escolhe o tipo de questionário, define o período de coleta e configura quem vai responder. O Assistente de Seleção te guia na escolha certa.",
    acoes: [
      "Clique em **Nova Campanha** no topo da página",
      "O **Assistente** vai recomendar o instrumento ideal para o seu caso",
      "Escolha o **SIPRO** para avaliação geral — instrumento autoral do YourEyes, integrado com GRO, AET e demais módulos (recomendado na maioria dos casos)",
      "Defina o nome, período de início e fim da campanha",
      "Avance para configurar os grupos de trabalho (próximo passo)",
    ],
    dica: "Use o SIPRO para campanhas regulares. Outros instrumentos (PHQ-9, GAD-7, MBI) são para situações específicas como investigar depressão ou burnout.",
  },
  {
    id: "distribuicao",
    icon: Link2,
    color: "text-emerald-600",
    bgColor: "bg-emerald-50",
    titulo: "Passo 2 — Envie para os Colaboradores",
    subtitulo: "Convite individual ou link público",
    descricao:
      "Após ativar a campanha, você tem duas formas de distribuir: convite individual (recomendado) ou link público. O colaborador não precisa de login em nenhuma delas — e a identidade nunca é gravada junto às respostas.",
    acoes: [
      "**Convite individual (recomendado)**: o sistema dispara link único por colaborador (WhatsApp/e-mail) e grava automaticamente o **snapshot de Setor, Cargo e GHE** na resposta — sem nome, sem CPF",
      "**Link público / QR Code**: distribuição massiva, mas sem segmentação por grupo",
      "Verificação via **código WhatsApp** garante 1 resposta por pessoa",
      "**Identidade nunca é salva** junto às respostas — só hash anônimo + snapshot do grupo",
      "O snapshot é o que permite o **cruzamento por GHE / Setor / Cargo** depois (menu **Resultados → Por GHE**)",
    ],
    dica: "Use sempre que possível o convite individual. Ele preserva o anonimato (em questionários, a regra ≥5 por segmento) e habilita as análises cruzadas no dashboard.",
  },
  {
    id: "anonimato",
    icon: Lock,
    color: "text-rose-600",
    bgColor: "bg-rose-50",
    titulo: "Passo 3 — Regra do Anonimato",
    subtitulo: "Como o sistema protege os colaboradores",
    descricao:
      "O sistema garante que nenhum colaborador seja identificado pelas suas respostas. A trava de confidencialidade depende do tipo de instrumento: os questionários (SIPRO, COPSOQ, HSE, PROART) só exibem resultados com no mínimo 5 respondentes por grupo/segmento; as entrevistas guiadas e coletivas são liberadas a partir de 1 resposta, porque o material já é tratado de forma qualitativa e agregada.",
    acoes: [
      "**Questionários**: mínimo de **5 respondentes** por grupo (e por segmento) para exibir resultados",
      "**Entrevistas guiadas / coletivas**: liberadas a partir de **1 resposta** — a trava de 5 não se aplica",
      "Em questionários, segmentos com menos de 5 respostas aparecem como '**Amostra insuficiente**'",
      "Se um grupo de questionário tem menos de 5: sistema **agrupa automaticamente** (Setor → Empresa)",
      "Para empresas com menos de 20 pessoas: use apenas o nível **Empresa**",
      "Resultados exibidos **somente em formato agregado** — nunca individual",
    ],
    dica: "A regra dos 5 segue a ISO 45003 e o COPSOQ III e vale apenas para questionários. As entrevistas guiadas e coletivas já nascem anônimas e agregadas, por isso liberam com 1 resposta. O sistema aplica tudo automaticamente.",
  },
  {
    id: "resultados",
    icon: BarChart3,
    color: "text-blue-600",
    bgColor: "bg-blue-50",
    titulo: "Passo 4 — Veja os Resultados",
    subtitulo: "Visão Geral, Dimensões, IA e Segmentos",
    descricao:
      "Ao encerrar a campanha, o sistema calcula automaticamente o IRP-S (Índice de Risco Psicossocial) e classifica cada dimensão. Os resultados de cada campanha ficam organizados em abas: Visão Geral, Por Dimensão, IA, Contraprova, Ergonomia e Participação (a aba Comparativo aparece quando há mais de uma campanha no recorte).",
    acoes: [
      "**IRP-S (Índice de Risco Psicossocial)**: score de 0 a 100 — **quanto maior, maior o risco**",
      "**0–20 = Saudável** · **21–35 = Estável** · **36–50 = Atenção** · **51–65 = Risco** · **66–100 = Crítico**",
      "**Cruzamento por GHE / Setor / Cargo**: o heatmap comparativo fica no menu **Resultados → Por GHE** (somente convites individuais alimentam essa visão)",
      "**Aba IA**: análise interpretativa gerada automaticamente com recomendações 5W2H",
      "**Aba Contraprova**: cruza a percepção dos trabalhadores com evidências operacionais de outros módulos (afastamentos, ocorrências) para validar ou questionar o resultado",
    ],
    dica: "Para identificar onde concentrar ações, use o menu Resultados → Por GHE: ele mostra exatamente qual GHE ou Setor está em risco, sem expor pessoas.",
  },
  {
    id: "gro",
    icon: ClipboardList,
    color: "text-orange-600",
    bgColor: "bg-orange-50",
    titulo: "Passo 5 — Riscos Vão para o GRO Automaticamente",
    subtitulo: "Integração com o inventário de riscos",
    descricao:
      "Ao encerrar a campanha, os fatores de risco identificados são automaticamente exportados para o GRO (Inventário de Riscos Ocupacionais) — o documento obrigatório do PGR.",
    acoes: [
      "**Nenhuma ação necessária** — exportação é automática ao encerrar",
      "Cada risco fica vinculado ao **Setor + Função** correspondente",
      "Riscos classificados como **Alto ou Crítico** geram um **Plano de Ação 5W2H** automático",
      "Prazo automático: **30 dias** para Crítico, **60 dias** para Alto",
      "**Não é possível arquivar um risco** sem ter um plano de ação vinculado",
    ],
    dica: "O Inventário de Riscos Ocupacionais (GRO) é alimentado automaticamente a cada campanha encerrada. Esses dados sustentam a elaboração do PGR pela equipe técnica responsável, garantindo conformidade contínua com a NR-01.",
  },
  {
    id: "aet",
    icon: AlertTriangle,
    color: "text-amber-600",
    bgColor: "bg-amber-50",
    titulo: "Passo 6 — Quando o Sistema Recomenda a AET",
    subtitulo: "Análise Ergonômica do Trabalho (NR-17)",
    descricao:
      "Quando o sistema identifica situações críticas — como IPS muito baixo, riscos recorrentes ou múltiplos fatores simultâneos — ele recomenda a realização de uma AET (Análise Ergonômica do Trabalho), conforme exige a NR-17.",
    acoes: [
      "O **banner de AET** aparece automaticamente nos resultados quando necessário",
      "**IRP-S acima de 35 (Atenção)** → recomendação de AET",
      "**IRP-S acima de 50 ou múltiplos fatores críticos** → AET prioritária pela NR-17",
      "Os dados psicossociais alimentam a **Avaliação Ergonômica Preliminar (AEP)**",
      "Acesse o módulo de **Ergonomia** para iniciar a AET recomendada",
    ],
    dica: "O psicossocial não é isolado — ele integra a ergonomia. Um ambiente com problemas psicossociais quase sempre tem aspectos ergonômicos relacionados.",
  },
  {
    id: "monitoramento",
    icon: RefreshCw,
    color: "text-teal-600",
    bgColor: "bg-teal-50",
    titulo: "Passo 7 — Monitore e Reaprecie",
    subtitulo: "O ciclo não termina na primeira campanha",
    descricao:
      "Após executar as ações do plano, o sistema exige que os riscos sejam reavaliados. O histórico de campanhas mostra a evolução do IPS ao longo do tempo, permitindo medir o impacto das intervenções.",
    acoes: [
      "Acompanhe o **Histórico IRP-S** na aba correspondente (evolução ao longo do tempo)",
      "Após executar ações, **reavalue os riscos** no GRO",
      "**Campanhas trimestrais** são o intervalo recomendado",
      "Compare resultados **antes e depois** de intervenções",
      "O **Inventário PGR** consolida todos os dados para auditoria",
    ],
    dica: "Campanhas realizadas regularmente constroem um histórico robusto. Isso demonstra evolução e ROI das ações — importante para relatórios de auditoria da NR-01.",
  },
  {
    id: "recursos",
    icon: FileText,
    color: "text-indigo-600",
    bgColor: "bg-indigo-50",
    titulo: "Documentos e Recursos",
    subtitulo: "Tudo que o sistema gera para você",
    descricao:
      "O YourEyes gera automaticamente todos os documentos necessários para conformidade legal e auditoria. Baixe o Manual Completo em PDF para ter um guia de referência offline.",
    acoes: [
      "**Inventário de Riscos Ocupacionais** — exportável para o PGR",
      "**Plano de Ação 5W2H** — gerado automaticamente para riscos Alto/Crítico",
      "**Relatório Psicossocial** — diagnóstico completo da campanha",
      "**Documento de Metodologia** — documenta os critérios utilizados",
      "**Relatório de Integração AEP** — conecta psicossocial ao módulo de Ergonomia",
    ],
    dica: "Todos os documentos são rastreáveis e auditáveis. A metodologia é documentada automaticamente, atendendo ao requisito de transparência da NR-01.",
  },
];

export function GuiaRapidoPsicossocial({ open, onOpenChange }: GuiaRapidoPsicossocialProps) {
  const [passo, setPasso] = useState(0);

  const atual = PASSOS[passo];
  const IconeAtual = atual.icon;
  const progresso = ((passo + 1) / PASSOS.length) * 100;

  const irPara = (idx: number) => {
    if (idx >= 0 && idx < PASSOS.length) setPasso(idx);
  };

  const handleClose = () => {
    setPasso(0);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) handleClose(); else onOpenChange(true); }}>
      <DialogContent className="max-w-3xl p-0 gap-0 overflow-hidden flex flex-col max-h-[90vh] h-[90vh] [&>button.absolute]:hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-5 pb-4 border-b bg-background">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-purple-100">
              <BookOpen className="h-5 w-5 text-purple-600" />
            </div>
            <div>
              <h2 className="font-bold text-base text-foreground">Guia do Módulo Psicossocial</h2>
              <p className="text-xs text-muted-foreground">
                {passo + 1} de {PASSOS.length} — {atual.titulo}
              </p>
            </div>
          </div>
          <Button variant="ghost" size="icon" onClick={handleClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Barra de progresso */}
        <div className="h-1 bg-muted">
          <motion.div
            className="h-full bg-purple-600"
            animate={{ width: `${progresso}%` }}
            transition={{ duration: 0.3 }}
          />
        </div>

        <div className="flex flex-1 overflow-hidden min-h-0">
          {/* Sidebar */}
          <div className="w-52 shrink-0 border-r bg-muted/30 py-4 hidden sm:block overflow-y-auto">
            <p className="text-[11px] font-semibold text-muted-foreground uppercase tracking-wider px-4 mb-2">
              Passo a Passo
            </p>
            {PASSOS.map((p, idx) => {
              const Icone = p.icon;
              const concluido = idx < passo;
              const ativo = idx === passo;
              return (
                <button
                  key={p.id}
                  onClick={() => irPara(idx)}
                  className={cn(
                    "w-full flex items-center gap-2.5 px-4 py-2.5 text-left transition-all text-sm",
                    ativo
                      ? "bg-purple-50 text-purple-700 font-medium border-r-2 border-purple-600"
                      : "text-muted-foreground hover:bg-muted/60"
                  )}
                >
                  {concluido ? (
                    <CheckCircle2 className="h-4 w-4 text-emerald-500 shrink-0" />
                  ) : ativo ? (
                    <Icone className={cn("h-4 w-4 shrink-0", p.color)} />
                  ) : (
                    <Circle className="h-4 w-4 text-muted-foreground/40 shrink-0" />
                  )}
                  <span className="text-xs leading-tight">
                    {p.titulo.replace(/^Passo \d+ — /, "")}
                  </span>
                </button>
              );
            })}
          </div>

          {/* Conteúdo */}
          <div className="flex-1 overflow-y-auto">
            <AnimatePresence mode="wait">
              <motion.div
                key={passo}
                initial={{ opacity: 0, x: 20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -20 }}
                transition={{ duration: 0.2 }}
                className="p-6 space-y-5"
              >
                {/* Cabeçalho */}
                <div className="flex items-start gap-4">
                  <div className={cn("p-3 rounded-xl shrink-0", atual.bgColor)}>
                    <IconeAtual className={cn("h-6 w-6", atual.color)} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="font-bold text-lg text-foreground">{atual.titulo}</h3>
                      <Badge variant="outline" className="text-xs">
                        {atual.subtitulo}
                      </Badge>
                    </div>
                  </div>
                </div>

                {/* Descrição */}
                <p className="text-sm text-foreground/80 leading-relaxed">{atual.descricao}</p>

                {/* Destaques (overview) */}
                {atual.destaques && (
                  <div className="grid grid-cols-2 gap-3">
                    {atual.destaques.map(({ icon: Ic, label }) => (
                      <div
                        key={label}
                        className="flex items-center gap-2.5 p-3 rounded-lg bg-muted/50 border border-border/50"
                      >
                        <Ic className="h-4 w-4 text-purple-600 shrink-0" />
                        <span className="text-xs font-medium text-foreground">{label}</span>
                      </div>
                    ))}
                  </div>
                )}

                {/* Ações */}
                {atual.acoes && (
                  <div className="space-y-2">
                    <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                      Como fazer
                    </p>
                    <ol className="space-y-2">
                      {atual.acoes.map((acao, i) => (
                        <li key={i} className="flex items-start gap-3">
                          <span className="shrink-0 w-5 h-5 rounded-full bg-purple-100 text-purple-700 text-xs font-bold flex items-center justify-center mt-0.5">
                            {i + 1}
                          </span>
                          <span
                            className="text-sm text-foreground/80"
                            dangerouslySetInnerHTML={{
                              __html: acao.replace(/\*\*(.*?)\*\*/g, '<strong class="text-foreground">$1</strong>'),
                            }}
                          />
                        </li>
                      ))}
                    </ol>
                  </div>
                )}

                {/* Dica */}
                {atual.dica && (
                  <div className="flex items-start gap-3 p-3 rounded-lg bg-amber-50 border border-amber-200">
                    <Lightbulb className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
                    <p className="text-xs text-amber-800 leading-relaxed">{atual.dica}</p>
                  </div>
                )}

                {/* CTA Manual PDF — última etapa */}
                {passo === PASSOS.length - 1 && (
                  <div className="flex flex-col items-center gap-3 pt-2 border-t border-border">
                    <p className="text-xs text-muted-foreground text-center">
                      Quer um guia de referência para consultar offline?
                    </p>
                    <ManualPsicossocial />
                  </div>
                )}

                {/* Indicadores mobile */}
                <div className="flex justify-center gap-1.5 sm:hidden pt-2">
                  {PASSOS.map((_, i) => (
                    <button
                      key={i}
                      onClick={() => irPara(i)}
                      className={cn(
                        "h-1.5 rounded-full transition-all",
                        i === passo ? "w-6 bg-purple-600" : "w-1.5 bg-muted-foreground/30"
                      )}
                    />
                  ))}
                </div>
              </motion.div>
            </AnimatePresence>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t bg-background shrink-0">
          <Button
            variant="outline"
            size="sm"
            onClick={() => irPara(passo - 1)}
            disabled={passo === 0}
            className="gap-2"
          >
            <ChevronLeft className="h-4 w-4" />
            Anterior
          </Button>

          <span className="text-xs text-muted-foreground hidden sm:block">
            {passo + 1} / {PASSOS.length}
          </span>

          {passo < PASSOS.length - 1 ? (
            <Button
              size="sm"
              onClick={() => irPara(passo + 1)}
              className="gap-2 bg-purple-600 hover:bg-purple-700 text-white"
            >
              Próximo
              <ChevronRight className="h-4 w-4" />
            </Button>
          ) : (
            <Button
              size="sm"
              onClick={handleClose}
              className="gap-2 bg-emerald-600 hover:bg-emerald-700 text-white"
            >
              <CheckCircle2 className="h-4 w-4" />
              Concluir
            </Button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
