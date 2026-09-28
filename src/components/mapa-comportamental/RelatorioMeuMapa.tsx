import { useState } from "react";
import {
  Sparkles, Download, RefreshCw, Info, AlertTriangle, Target,
  BookOpen, Compass, MessageSquare, Users, TrendingUp, ArrowRight, Copy, Check, Loader2, MessageSquareWarning,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { toast } from "sonner";
import { CriarAcaoAlertaModal } from "@/components/shared/CriarAcaoAlertaModal";
import {
  ARQUETIPO_LABEL, MOTOR_LABEL, MODO_LABEL,
  type MapaResultado, type Modo,
} from "@/data/instrumentos/mapaComportamental";
import {
  PERFIL_RELATORIO, OUTROS_PERFIS, OUTRO_PERFIL_APRESENTACAO, PRESSAO_POR_MODO,
  MOTOR_RELATORIO, MODO_RELATORIO, textoIntensidade,
  RELATORIO_ABERTURA, RELATORIO_SOBRE,
} from "@/data/mapaComportamentalRelatorio";
import { gerarRelatorioMeuMapaPdf } from "@/lib/mapaComportamentalRelatorioPdf";
import { ContestarModal } from "./ContestarModal";
import { useMinhasContestacoes } from "@/hooks/useMapaComportamentalContestacoes";
import { compararMapas } from "@/data/instrumentos/mapaComportamentalComparativo";
import { History } from "lucide-react";

interface Props {
  resultado: MapaResultado;
  nome?: string | null;
  mapaId?: string | null;
  concluidoEm?: string | null;
  venceEm?: string | null;
  onRefazer?: () => void;
  /** true quando exibido a um funcionário sem login (link público): esconde
   *  ações que exigem autenticação, como encaminhar ao Plano de Ação. */
  publico?: boolean;
  /** Aplicação anterior (reaplicação) — habilita o bloco "o que mudou". */
  anterior?: { resultado: MapaResultado; concluidoEm?: string | null } | null;
}

function Secao({ icon, titulo, children }: { icon: React.ReactNode; titulo: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="flex items-center gap-2 text-base">{icon}{titulo}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">{children}</CardContent>
    </Card>
  );
}

function EixoBarra({ titulo, esq, dir, pontosA, pontosB, intensidade }: {
  titulo: string; esq: string; dir: string; pontosA: number; pontosB: number; intensidade: number;
}) {
  const total = pontosA + pontosB || 1;
  const pctA = Math.round((pontosA / total) * 100);
  return (
    <div>
      <p className="text-sm font-medium">{titulo}</p>
      <div className="mt-1 h-3 w-full rounded-full bg-muted overflow-hidden flex">
        <div className="h-full bg-indigo-500/70" style={{ width: `${pctA}%` }} />
        <div className="h-full bg-fuchsia-500/70" style={{ width: `${100 - pctA}%` }} />
      </div>
      <div className="flex items-center justify-between text-xs text-muted-foreground mt-1">
        <span>{esq}</span><span>{dir}</span>
      </div>
      <p className="text-xs text-muted-foreground mt-1">{textoIntensidade(intensidade)}</p>
    </div>
  );
}

export function RelatorioMeuMapa({ resultado, nome, mapaId, concluidoEm, venceEm, onRefazer, publico = false, anterior = null }: Props) {
  const [encaminhar, setEncaminhar] = useState(false);
  const [copiado, setCopiado] = useState(false);
  const [gerandoPdf, setGerandoPdf] = useState(false);
  const [contestar, setContestar] = useState(false);
  const { data: minhasContestacoes = [] } = useMinhasContestacoes();
  const minhaContestacao = publico
    ? null
    : minhasContestacoes.find((c) => (mapaId ? c.mapa_id === mapaId : false)) ?? null;
  const baixa = resultado.confiabilidade === "baixa";
  const primario = resultado.arquetipos[0];
  const secundario = resultado.arquetipos[1] ?? null;
  const lib = PERFIL_RELATORIO[primario];
  const intensidadeBaixa = resultado.foco.misto || resultado.ritmo.misto;
  const custos = intensidadeBaixa ? lib.precos.slice(0, 2) : lib.precos;
  const modoKey = resultado.modo.resultado as Modo | "misto";
  const comparativo = anterior ? compararMapas(resultado, anterior.resultado) : null;

  const baixarPdf = async () => {
    if (gerandoPdf) return;
    setGerandoPdf(true);
    try {
      await gerarRelatorioMeuMapaPdf({ resultado, nome, concluidoEm, venceEm, anterior });
    } catch (e) {
      console.error("Falha ao gerar PDF do relatório:", e);
      toast.error("Não foi possível gerar o PDF agora.");
    } finally {
      setGerandoPdf(false);
    }
  };

  const copiarPedidos = async () => {
    const texto = lib.pedidosLider.map((f) => `“${f}”`).join("\n\n");
    try {
      await navigator.clipboard.writeText(texto);
      setCopiado(true);
      toast.success("Frases copiadas — leve para a conversa com seu líder.");
      setTimeout(() => setCopiado(false), 2500);
    } catch {
      toast.error("Não consegui copiar. Selecione o texto manualmente.");
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      {/* Cabeçalho / assinatura */}
      <Card className="overflow-hidden">
        <div className="bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-600 p-6 text-white">
          <div className="flex items-center gap-2 text-white/90 text-sm mb-1">
            <Sparkles className="w-4 h-4" /> Meu Mapa {nome ? `— ${nome}` : ""}
          </div>
          <h2 className="text-2xl font-bold">{resultado.assinatura}</h2>
          <p className="text-white/80 text-xs mt-1">
            {concluidoEm ? `Respondido em ${new Date(concluidoEm).toLocaleDateString("pt-BR")}` : ""}
            {venceEm ? ` · válido até ${new Date(venceEm).toLocaleDateString("pt-BR")}` : ""}
          </p>
        </div>
        <CardContent className="pt-4 flex flex-wrap gap-2">
          <Button size="sm" className="gap-1" onClick={baixarPdf} disabled={gerandoPdf}>
            {gerandoPdf ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />} Baixar em PDF
          </Button>
          {onRefazer && (
            <Button size="sm" variant="outline" className="gap-1" onClick={onRefazer}>
              <RefreshCw className="w-4 h-4" /> Refazer o meu mapa
            </Button>
          )}
        </CardContent>
      </Card>

      {/* Abertura + enquadramento */}
      <Alert>
        <Info className="h-4 w-4" />
        <AlertDescription className="space-y-1">
          {RELATORIO_ABERTURA.map((p, i) => <p key={i} className={i === 0 ? "font-medium" : ""}>{p}</p>)}
        </AlertDescription>
      </Alert>

      {baixa && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            Este resultado pode não refletir bem você — as respostas ficaram pouco consistentes. Vale
            refazer com calma. As seções de recomendação foram omitidas até uma nova aplicação.
          </AlertDescription>
        </Alert>
      )}

      {/* Comparativo com a aplicação anterior (RF-015 / RF-030) */}
      {comparativo && (
        <Card className="border-indigo-200 bg-indigo-50/40 dark:bg-indigo-950/20">
          <CardHeader className="pb-3">
            <CardTitle className="flex items-center gap-2 text-base">
              <History className="w-4 h-4 text-indigo-600" /> O que mudou desde a última vez
              {anterior?.concluidoEm && (
                <span className="text-xs font-normal text-muted-foreground ml-auto">
                  Comparado com {new Date(anterior.concluidoEm).toLocaleDateString("pt-BR")}
                </span>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <p className="text-muted-foreground">{comparativo.resumo}</p>
            {comparativo.itens.length > 0 && (
              <div className="space-y-1.5">
                {comparativo.itens.map((it) => (
                  <div key={it.rotulo} className="flex flex-wrap items-baseline gap-x-2 border-l-2 border-indigo-200 pl-3">
                    <span className="font-medium">{it.rotulo}:</span>
                    <span className="text-muted-foreground line-through">{it.de}</span>
                    <ArrowRight className="w-3.5 h-3.5 text-indigo-500 shrink-0" />
                    <span>{it.para}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* 2 — Em uma frase */}
      <Secao icon={<Sparkles className="w-4 h-4 text-indigo-600" />} titulo="Seu mapa em uma frase">
        <p className="text-base">{lib.emUmaFrase}</p>
        <p className="text-xs text-muted-foreground">
          ({resultado.arquetipos.map((a) => ARQUETIPO_LABEL[a]).join(" · ")} ·{" "}
          {resultado.motor.predominantes.map((m) => `Motor ${MOTOR_LABEL[m]}`).join(" e ")} ·{" "}
          {resultado.modo.resultado === "misto" ? "Modo Misto" : `Modo ${MODO_LABEL[resultado.modo.resultado as Modo]}`})
        </p>
        {secundario && (
          <p className="text-xs text-muted-foreground">
            Seu perfil ficou entre <strong>{ARQUETIPO_LABEL[primario]}</strong> e{" "}
            <strong>{ARQUETIPO_LABEL[secundario]}</strong> — trate como flexibilidade, não indefinição. As
            orientações seguem o {ARQUETIPO_LABEL[primario]}; vale ler também com o {ARQUETIPO_LABEL[secundario]} em mente.
          </p>
        )}
      </Secao>

      {/* 3 — Como você tende a trabalhar */}
      <Secao icon={<Compass className="w-4 h-4 text-indigo-600" />} titulo="Como você tende a trabalhar">
        <EixoBarra titulo="Foco" esq="Pessoas" dir="Tarefas"
          pontosA={resultado.foco.pontosA} pontosB={resultado.foco.pontosB} intensidade={resultado.foco.intensidade} />
        <EixoBarra titulo="Ritmo" esq="Acelerado" dir="Ponderado"
          pontosA={resultado.ritmo.pontosA} pontosB={resultado.ritmo.pontosB} intensidade={resultado.ritmo.intensidade} />
        {resultado.motor.predominantes.map((m) => (
          <p key={m}><span className="font-medium">Motor {MOTOR_LABEL[m]}:</span> {MOTOR_RELATORIO[m]}</p>
        ))}
        <p>
          <span className="font-medium">Modo {resultado.modo.resultado === "misto" ? "Misto" : MODO_LABEL[resultado.modo.resultado as Modo]}:</span>{" "}
          {MODO_RELATORIO[modoKey]}
        </p>
      </Secao>

      {/* 4 — No dia a dia */}
      <Secao icon={<Info className="w-4 h-4 text-indigo-600" />} titulo="O que isso significa no dia a dia">
        <p><strong>Numa reunião:</strong> {lib.noDiaADia.reuniao}</p>
        <p><strong>Num prazo apertado:</strong> {lib.noDiaADia.prazo}</p>
        <p><strong>Num desacordo:</strong> {lib.noDiaADia.desacordo}</p>
      </Secao>

      {/* 5 — Rende mais */}
      <Secao icon={<TrendingUp className="w-4 h-4 text-emerald-600" />} titulo="Onde você costuma render mais">
        {lib.rendeMais.map((c, i) => (
          <div key={i} className="border-l-2 border-emerald-200 pl-3">
            <p className="font-medium">{c.condicao}</p>
            <p className="text-muted-foreground text-xs mt-0.5">→ {c.acao}</p>
          </div>
        ))}
      </Secao>

      {/* 6 — Desgasta */}
      <Secao icon={<AlertTriangle className="w-4 h-4 text-amber-600" />} titulo="O que costuma te desgastar">
        {lib.desgasta.map((c, i) => (
          <div key={i} className="border-l-2 border-amber-200 pl-3">
            <p className="font-medium">{c.condicao}</p>
            <p className="text-muted-foreground text-xs mt-0.5">→ {c.acao}</p>
          </div>
        ))}
      </Secao>

      {/* 7 — Preço do estilo */}
      <Secao icon={<Info className="w-4 h-4 text-rose-600" />} titulo="O preço do seu estilo">
        {custos.map((c, i) => (
          <div key={i} className="border-l-2 border-rose-200 pl-3">
            <p className="font-medium">{c.texto}</p>
            <p className="text-muted-foreground text-xs mt-0.5">Sinal de que está sendo pago agora: {c.sinal}</p>
          </div>
        ))}
      </Secao>

      {/* 8 — Como melhorar (suprimida em baixa confiabilidade) */}
      {!baixa && (
        <Secao icon={<Target className="w-4 h-4 text-indigo-600" />} titulo="Como melhorar seu desempenho">
          <p className="font-semibold text-indigo-700">Para começar esta semana</p>
          <ol className="list-decimal list-inside space-y-1">
            {lib.ajustesImediatos.map((a, i) => <li key={i}>{a}</li>)}
          </ol>
          <p className="font-semibold text-indigo-700 pt-2">Para desenvolver nos próximos meses</p>
          {lib.contrapesos.map((c, i) => (
            <div key={i} className="border-l-2 border-indigo-200 pl-3">
              <p className="font-medium">{c.nome}</p>
              <p className="text-xs mt-0.5">Por que importa para você: {c.porque}</p>
              <p className="text-xs text-muted-foreground mt-0.5">Como treinar: {c.comoTreinar}</p>
            </div>
          ))}
          <p className="font-semibold text-indigo-700 pt-2">O que pedir ao seu líder</p>
          <p className="text-xs text-muted-foreground">Use estas frases na próxima conversa, do jeito que estão:</p>
          {lib.pedidosLider.map((f, i) => <p key={i} className="italic">“{f}”</p>)}
          <Button size="sm" variant="outline" className="gap-1 mt-1" onClick={copiarPedidos}>
            {copiado ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />} Copiar frases
          </Button>
        </Secao>
      )}

      {/* 9 — Zona de conforto */}
      <Secao icon={<Compass className="w-4 h-4 text-indigo-600" />} titulo="Sua zona de conforto">
        <p>{lib.zonaConforto.onde}</p>
        <p className="text-muted-foreground">{lib.zonaConforto.saida}</p>
      </Secao>

      {/* 10 — Comunicação */}
      <Secao icon={<MessageSquare className="w-4 h-4 text-indigo-600" />} titulo="Como você se comunica">
        <p>{lib.comunicacao.entrega}</p>
        <p>{lib.comunicacao.perde}</p>
        <p className="text-muted-foreground"><strong>Ajuste:</strong> {lib.comunicacao.ajuste}</p>
      </Secao>

      {/* 11 — Pressão e conflito */}
      <Secao icon={<AlertTriangle className="w-4 h-4 text-indigo-600" />} titulo="Em pressão e em conflito">
        <p>{PRESSAO_POR_MODO[modoKey]}</p>
      </Secao>

      {/* 12 — Outros perfis (suprimida em baixa confiabilidade) */}
      {!baixa && (
        <Secao icon={<Users className="w-4 h-4 text-indigo-600" />} titulo="Trabalhando com os outros perfis">
          {(Object.keys(OUTROS_PERFIS[primario]) as (keyof typeof ARQUETIPO_LABEL)[]).map((outro) => {
            const b = OUTROS_PERFIS[primario][outro];
            if (!b) return null;
            return (
              <div key={outro} className="border-l-2 border-indigo-200 pl-3">
                <p className="font-medium">Com {OUTRO_PERFIL_APRESENTACAO[outro]} ({ARQUETIPO_LABEL[outro]})</p>
                <p className="text-xs mt-0.5"><strong>Como te vê:</strong> {b.comoTeVe}</p>
                <p className="text-xs mt-0.5"><strong>Onde atrita:</strong> {b.atrito}</p>
                <p className="text-xs text-muted-foreground mt-0.5"><strong>Ajuste:</strong> {b.ajuste}</p>
              </div>
            );
          })}
        </Secao>
      )}

      {/* 13 — Feedback */}
      <Secao icon={<MessageSquare className="w-4 h-4 text-indigo-600" />} titulo="Como pedir e receber feedback">
        <p>{lib.feedback.comoPedir}</p>
        <p className="text-muted-foreground">{lib.feedback.reacaoHabitual}</p>
      </Secao>

      {/* 14 — Próximos passos */}
      <Secao icon={<ArrowRight className="w-4 h-4 text-indigo-600" />} titulo="Seus próximos passos">
        <p className="text-muted-foreground">Este relatório termina em ação, não em reflexão. Escolha por onde começar:</p>
        <div className="flex flex-wrap gap-2 pt-1">
          {!baixa && !publico && (
            <Button size="sm" className="gap-1" onClick={() => setEncaminhar(true)}>
              <Target className="w-4 h-4" /> Criar uma ação a partir deste mapa
            </Button>
          )}
          <Button size="sm" variant="outline" className="gap-1" onClick={baixarPdf} disabled={gerandoPdf}>
            {gerandoPdf ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />} Baixar em PDF
          </Button>
        </div>
      </Secao>

      {/* 15 — Sobre este resultado */}
      <Secao icon={<Info className="w-4 h-4 text-muted-foreground" />} titulo="Sobre este resultado">
        {venceEm && <p>Válido até {new Date(venceEm).toLocaleDateString("pt-BR")}. Depois disso, vale refazer — as pessoas mudam.</p>}
        {RELATORIO_SOBRE.map((p, i) => <p key={i} className="text-muted-foreground">{p}</p>)}
        {!publico && (
          minhaContestacao ? (
            <div className="rounded-md border border-amber-300 bg-amber-50/60 dark:bg-amber-950/20 p-3 text-xs">
              <p className="font-medium flex items-center gap-1.5">
                <MessageSquareWarning className="w-3.5 h-3.5 text-amber-600" />
                Você contestou este resultado {minhaContestacao.resposta ? "— o RH respondeu" : "— aguardando análise do RH"}.
              </p>
              {minhaContestacao.resposta && <p className="text-muted-foreground mt-1">Resposta do RH: {minhaContestacao.resposta}</p>}
            </div>
          ) : (
            <div className="pt-1">
              <Button size="sm" variant="outline" className="gap-1" onClick={() => setContestar(true)}>
                <MessageSquareWarning className="w-4 h-4" /> Não me reconheço neste resultado
              </Button>
            </div>
          )
        )}
        <p className="text-xs text-muted-foreground">
          Logo abaixo você vê quem acessou o seu mapa. Contestar é um direito seu (revisão humana) e não
          afeta a sua avaliação.
        </p>
      </Secao>

      {!publico && (
      <CriarAcaoAlertaModal
        open={encaminhar}
        onOpenChange={setEncaminhar}
        origemModulo="mapa_comportamental"
        origemId={mapaId ?? undefined}
        alertaTitulo="Meu desenvolvimento a partir do Mapa Comportamental"
        alertaDescricao={
          "Escolher um dos ajustes da seção “Como melhorar” e começar esta semana. " +
          "Ação de desenvolvimento pessoal, a partir do meu próprio mapa."
        }
        contextoExtra={`Meu perfil predominante: ${ARQUETIPO_LABEL[primario]}. Ação de desenvolvimento, nunca de movimentação de pessoal.`}
      />
      )}

      {!publico && (
        <ContestarModal open={contestar} onOpenChange={setContestar} mapaId={mapaId ?? null} onRefazer={onRefazer} />
      )}
    </div>
  );
}
