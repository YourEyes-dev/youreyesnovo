import { useState, useEffect, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { Card, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import {
  ArrowLeft, Play, Loader2, CheckCircle2, XCircle, AlertCircle,
  CircleDashed, Clock, ChevronRight, Bot, CalendarClock,
  FileDown, Table2, Printer, Database, MonitorPlay, ExternalLink,
} from "lucide-react";
import {
  useQaRunner, useQaResultados, useQaAgendamento, useQaAgendamentoE2E,
  type QaSituacao, type QaBateria, type QaModuloTestavel, type QaDiaAgenda,
} from "@/hooks/useQaRunner";
import { gerarPDF, gerarCSV, abrirImprimivel } from "@/lib/qaRelatorio";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

// ── aparência de cada situação ──────────────────────────
const SITUACAO: Record<
  QaSituacao,
  { label: string; icon: typeof CheckCircle2; badge: string; row: string }
> = {
  passou: {
    label: "Passou", icon: CheckCircle2,
    badge: "bg-emerald-100 text-emerald-800 border-emerald-200",
    row: "border-l-emerald-400",
  },
  falhou: {
    label: "Falhou", icon: XCircle,
    badge: "bg-red-100 text-red-800 border-red-200",
    row: "border-l-red-500",
  },
  erro: {
    label: "Erro", icon: AlertCircle,
    badge: "bg-orange-100 text-orange-800 border-orange-200",
    row: "border-l-orange-400",
  },
  nao_implementado: {
    label: "Sem rotina", icon: CircleDashed,
    badge: "bg-slate-100 text-slate-600 border-slate-200",
    row: "border-l-slate-300",
  },
};

function Placar({ b }: { b: QaBateria }) {
  const item = (n: number, s: QaSituacao) =>
    n > 0 ? (
      <span className={`px-2 py-0.5 rounded text-xs font-medium border ${SITUACAO[s].badge}`}>
        {n} {SITUACAO[s].label.toLowerCase()}
      </span>
    ) : null;
  return (
    <div className="flex flex-wrap gap-1.5">
      {item(b.passou, "passou")}
      {item(b.falhou, "falhou")}
      {item(b.erro, "erro")}
      {item(b.nao_implementado, "nao_implementado")}
    </div>
  );
}

// ── barra de exportação do relatório ────────────────────
function BarraExportar({ bateria }: { bateria: QaBateria }) {
  const { data: resultados = [], isLoading } = useQaResultados(bateria.id);
  if (isLoading || resultados.length === 0) return null;
  return (
    <div className="flex flex-wrap gap-2 mb-3">
      <span className="text-xs text-muted-foreground self-center mr-1">Relatório:</span>
      <Button variant="outline" size="sm" className="h-7 text-xs"
        onClick={() => gerarPDF(bateria, resultados)}>
        <FileDown className="h-3 w-3 mr-1" /> PDF
      </Button>
      <Button variant="outline" size="sm" className="h-7 text-xs"
        onClick={() => gerarCSV(bateria, resultados)}>
        <Table2 className="h-3 w-3 mr-1" /> Planilha
      </Button>
      <Button variant="outline" size="sm" className="h-7 text-xs"
        onClick={() => abrirImprimivel(bateria, resultados)}>
        <Printer className="h-3 w-3 mr-1" /> Imprimir
      </Button>
    </div>
  );
}

// ── relatório de uma bateria ────────────────────────────
function Relatorio({ execucaoId }: { execucaoId: string }) {
  const { data: resultados = [], isLoading } = useQaResultados(execucaoId);

  // Ordem de leitura: o que exige acao primeiro (falhou, erro), depois o que
  // passou, e por ultimo os "sem rotina" — que sao a lista de trabalho, nao
  // um resultado. Dentro de cada grupo, por codigo.
  const ordem: Record<QaSituacao, number> = {
    falhou: 0, erro: 1, passou: 2, nao_implementado: 3,
  };
  const ordenados = [...resultados].sort(
    (a, b) =>
      ordem[a.situacao] - ordem[b.situacao] || a.codigo.localeCompare(b.codigo),
  );

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground py-4">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando resultados…
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {ordenados.map((r) => {
        const s = SITUACAO[r.situacao];
        const Icon = s.icon;
        const mostrarDetalhe =
          r.situacao === "falhou" || r.situacao === "erro";
        return (
          <div
            key={r.codigo}
            className={`border-l-2 ${s.row} bg-card rounded-r-md border border-l-2 px-3 py-2`}
          >
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-2 min-w-0">
                <Icon className="h-4 w-4 shrink-0" />
                <span className="font-mono text-sm font-medium">{r.codigo}</span>
                <span className="text-sm text-muted-foreground truncate">
                  {r.obtido}
                </span>
              </div>
              <Badge variant="outline" className={`shrink-0 ${s.badge}`}>
                {s.label}
              </Badge>
            </div>

            {mostrarDetalhe && (
              <div className="mt-2 ml-6 space-y-2 text-xs">
                {/* onde falhou */}
                {r.passo_acao && (
                  <p className="font-medium text-red-700">
                    ⚠ Falhou no passo {r.passo_ordem}: {r.passo_acao}
                  </p>
                )}
                {r.esperado && (
                  <p><span className="text-muted-foreground">Esperava: </span>{r.esperado}</p>
                )}
                {r.obtido && (
                  <p><span className="text-muted-foreground">Obteve: </span>{r.obtido}</p>
                )}
                {r.erro_tecnico && (
                  <p className="font-mono text-orange-700 bg-orange-50 rounded px-2 py-1">
                    {r.erro_tecnico}
                  </p>
                )}

                {/* print da falha (corridas do Cypress) — a imagem da tela
                    no momento em que quebrou, embutida aqui mesmo */}
                {r.evidencia_png && (
                  <div className="mt-1">
                    <p className="text-muted-foreground mb-1">Tela no momento da falha:</p>
                    <a
                      href={`data:image/png;base64,${r.evidencia_png}`}
                      target="_blank"
                      rel="noreferrer"
                      title="Abrir o print em tamanho cheio"
                    >
                      <img
                        src={`data:image/png;base64,${r.evidencia_png}`}
                        alt={`Print da falha de ${r.codigo}`}
                        loading="lazy"
                        className="max-w-full rounded border shadow-sm hover:opacity-90 transition-opacity"
                      />
                    </a>
                  </div>
                )}

                {/* impacto e correção (observacoes do caso) */}
                {r.observacoes && (
                  <p className="text-amber-800 bg-amber-50 rounded px-2 py-1">
                    {r.observacoes}
                  </p>
                )}

                {/* passo a passo completo detalhado (expansível) */}
                {r.passos && r.passos.length > 0 && (
                  <details className="mt-1">
                    <summary className="cursor-pointer text-muted-foreground hover:text-foreground">
                      Ver o passo a passo completo para reproduzir
                    </summary>
                    <div className="mt-2 space-y-2 border-l-2 border-muted pl-3">
                      {r.objetivo && (
                        <p><span className="font-medium">Objetivo: </span>{r.objetivo}</p>
                      )}
                      {r.pre_condicoes && (
                        <p><span className="font-medium">Pré-condições: </span>{r.pre_condicoes}</p>
                      )}
                      {r.passos.map((p) => (
                        <div key={p.ordem} className={`rounded px-2 py-1 ${p.ordem === r.passo_ordem ? "bg-red-50 border border-red-200" : "bg-muted/40"}`}>
                          <p className="font-medium">
                            Passo {p.ordem}: {p.acao}
                            {p.ordem === r.passo_ordem && <span className="text-red-700"> ← falhou aqui</span>}
                          </p>
                          {p.onde_na_tela && p.onde_na_tela !== "-" && (
                            <p className="text-muted-foreground">Onde: {p.onde_na_tela}</p>
                          )}
                          {p.dados && p.dados !== "-" && (
                            <p className="text-muted-foreground">Dados: {p.dados}</p>
                          )}
                          {p.resultado_esperado && (
                            <p className="text-muted-foreground">Esperado: {p.resultado_esperado}</p>
                          )}
                        </div>
                      ))}
                    </div>
                  </details>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── uma linha da grade (um dia da semana) ───────────────
function LinhaDia({
  dia, onSalvar, salvando,
}: {
  dia: import("@/hooks/useQaRunner").QaDiaAgenda;
  onSalvar: (d: { dia: number; ligado: boolean; hora: number; minuto: number }) => void;
  salvando: boolean;
}) {
  const [hora, setHora] = useState(String(dia.hora).padStart(2, "0"));
  const [minuto, setMinuto] = useState(String(dia.minuto).padStart(2, "0"));

  const h = () => Math.min(23, Math.max(0, parseInt(hora || "0", 10)));
  const m = () => Math.min(59, Math.max(0, parseInt(minuto || "0", 10)));

  return (
    <div className="flex items-center gap-3 py-2">
      <div className="w-20 shrink-0">
        <Switch
          checked={dia.ligado}
          onCheckedChange={(v) => onSalvar({ dia: dia.dia_semana, ligado: v, hora: h(), minuto: m() })}
          disabled={salvando}
        />
      </div>
      <span className={`w-20 text-sm ${dia.ligado ? "font-medium" : "text-muted-foreground"}`}>
        {dia.dia_nome}
      </span>
      {dia.ligado ? (
        <div className="flex items-center gap-1">
          <Input
            className="w-12 h-8 text-center text-sm"
            value={hora}
            onChange={(e) => setHora(e.target.value.replace(/\D/g, "").slice(0, 2))}
            onBlur={() => onSalvar({ dia: dia.dia_semana, ligado: true, hora: h(), minuto: m() })}
            inputMode="numeric"
          />
          <span className="text-muted-foreground text-sm">:</span>
          <Input
            className="w-12 h-8 text-center text-sm"
            value={minuto}
            onChange={(e) => setMinuto(e.target.value.replace(/\D/g, "").slice(0, 2))}
            onBlur={() => onSalvar({ dia: dia.dia_semana, ligado: true, hora: h(), minuto: m() })}
            inputMode="numeric"
          />
        </div>
      ) : (
        <span className="text-xs text-muted-foreground">desligado</span>
      )}
    </div>
  );
}

// ── grade de agendamento (base reusada pelo motor e pelo Cypress) ──
function GradeAgendamento({
  dias, proxima, carregando, salvarDia, titulo, legenda, rodape,
}: {
  dias: QaDiaAgenda[];
  proxima: string | null | undefined;
  carregando: boolean;
  salvarDia: {
    mutate: (x: { dia: number; ligado: boolean; hora: number; minuto: number }) => void;
    isPending: boolean;
  };
  titulo: string;
  // recebe (algumLigado, proxima) e devolve a linha de status do cabeçalho
  legenda: (algumLigado: boolean, proxima: string | null | undefined) => string;
  rodape?: ReactNode;
}) {
  const algumLigado = dias.some((d) => d.ligado);

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="flex items-start gap-2 mb-2">
          <CalendarClock className="h-4 w-4 text-muted-foreground mt-0.5" />
          <div>
            <p className="text-sm font-medium">{titulo}</p>
            <p className="text-xs text-muted-foreground">
              {carregando ? "Carregando…" : legenda(algumLigado, proxima)}
            </p>
          </div>
        </div>

        <div className="mt-3 divide-y">
          {carregando ? (
            <div className="flex items-center gap-2 text-sm text-muted-foreground py-3">
              <Loader2 className="h-4 w-4 animate-spin" /> Carregando…
            </div>
          ) : (
            dias.map((d) => (
              <LinhaDia
                key={d.dia_semana}
                dia={d}
                onSalvar={(x) => salvarDia.mutate(x)}
                salvando={salvarDia.isPending}
              />
            ))
          )}
        </div>

        {rodape}
      </CardContent>
    </Card>
  );
}

// ── card de agendamento do motor SQL (grade por dia) ────
function CardAgendamento() {
  const { dias, proxima, carregando, salvarDia } = useQaAgendamento();
  return (
    <GradeAgendamento
      dias={dias}
      proxima={proxima}
      carregando={carregando}
      salvarDia={salvarDia}
      titulo="Rodar automaticamente"
      legenda={(algumLigado, prox) =>
        algumLigado && prox
          ? `Próxima: ${prox} · todos os módulos`
          : "Nenhum dia agendado — o robô só roda quando você clicar"}
    />
  );
}

// ── card de agendamento do Cypress (dispara a esteira) ──
function CardAgendamentoE2E() {
  const { dias, proxima, carregando, salvarDia } = useQaAgendamentoE2E();
  return (
    <GradeAgendamento
      dias={dias}
      proxima={proxima}
      carregando={carregando}
      salvarDia={salvarDia}
      titulo="Rodar automaticamente na esteira"
      legenda={(algumLigado, prox) =>
        algumLigado && prox
          ? `Próxima corrida programada: ${prox}`
          : "Nenhum dia agendado — a suíte só roda quando você publica uma mudança"}
      rodape={
        <p className="mt-3 border-t pt-3 text-xs text-muted-foreground">
          No horário marcado, o banco pede à esteira que rode a suíte — o mesmo
          que acontece a cada publicação. Para isso funcionar, o ambiente
          precisa de um token do GitHub guardado na configuração; sem ele, o
          horário fica salvo mas nada é disparado.
        </p>
      }
    />
  );
}

// ── lista de execuções (reusada pelo motor SQL e pelo Cypress) ──
function ListaExecucoes({
  baterias, modulos, carregando, vazio, abrirId,
}: {
  baterias: QaBateria[];
  modulos: QaModuloTestavel[];
  carregando: boolean;
  vazio: ReactNode;
  // Quando muda, abre esse relatório (ex.: bateria recém-rodada no motor).
  abrirId?: string | null;
}) {
  const [abertaId, setAbertaId] = useState<string | null>(null);
  useEffect(() => {
    if (abrirId) setAbertaId(abrirId);
  }, [abrirId]);

  if (carregando) {
    return (
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" /> Carregando…
      </div>
    );
  }
  if (baterias.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-sm text-muted-foreground">
          {vazio}
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {baterias.map((b) => {
        const aberta = abertaId === b.id;
        const quando = new Date(b.iniciada_em).toLocaleString("pt-BR");
        // Corrida do Cypress não tem módulo do catálogo — mostra "Testes de tela".
        const modLabel =
          b.disparo === "e2e"
            ? "Testes de tela (Cypress)"
            : modulos.find((m) => m.modulo_path === b.modulo_path)?.label ||
              b.modulo_path;
        return (
          <Card key={b.id}>
            <CardContent className="p-0">
              <button
                className="w-full flex items-center justify-between gap-3 p-4 text-left hover:bg-muted/40 transition-colors"
                onClick={() => setAbertaId(aberta ? null : b.id)}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <ChevronRight
                    className={`h-4 w-4 shrink-0 transition-transform ${
                      aberta ? "rotate-90" : ""
                    }`}
                  />
                  <div className="min-w-0">
                    <p className="text-sm font-medium truncate">{modLabel}</p>
                    <p className="text-xs text-muted-foreground flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {quando}
                      {b.duracao_ms != null && ` · ${b.duracao_ms} ms`}
                      {b.disparada_por_nome && ` · ${b.disparada_por_nome}`}
                    </p>
                  </div>
                </div>
                <Placar b={b} />
              </button>

              {aberta && (
                <div className="px-4 pb-4">
                  {b.observacao && b.observacao.startsWith(">>>") && (
                    <div className="mb-3 text-xs text-red-700 bg-red-50 rounded px-3 py-2">
                      {b.observacao}
                    </div>
                  )}
                  <BarraExportar bateria={b} />
                  <Relatorio execucaoId={b.id} />
                </div>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

// Marcador local da corrida disparada: guarda o baseline (a corrida e2e mais
// recente NO MOMENTO do disparo) e a hora do disparo. Assim dá para saber que
// há uma corrida "em andamento" até chegar uma corrida mais nova que o baseline
// — comparação de carimbos do servidor, imune ao relógio do navegador.
type CorridaEmAndamento = { baseline: string; at: string };
const CHAVE_CORRIDA = "qa_cypress_run";

function lerCorrida(): CorridaEmAndamento | null {
  try {
    const raw = localStorage.getItem(CHAVE_CORRIDA);
    return raw ? (JSON.parse(raw) as CorridaEmAndamento) : null;
  } catch {
    return null;
  }
}
function gravarCorrida(c: CorridaEmAndamento | null) {
  try {
    if (c) localStorage.setItem(CHAVE_CORRIDA, JSON.stringify(c));
    else localStorage.removeItem(CHAVE_CORRIDA);
  } catch {
    /* localStorage indisponível — o aviso só não persiste, sem quebrar */
  }
}

// ── painel do Cypress (testes de tela) ──────────────────
function PainelCypress({
  baterias, modulos, carregando,
}: {
  baterias: QaBateria[];
  modulos: QaModuloTestavel[];
  carregando: boolean;
}) {
  const [disparando, setDisparando] = useState(false);
  const [corrida, setCorrida] = useState<CorridaEmAndamento | null>(() => lerCorrida());

  // Carimbo da corrida e2e mais recente que a lista já conhece.
  const ultimaIniciada = baterias.reduce<string>(
    (max, b) => (b.iniciada_em > max ? b.iniciada_em : max),
    "",
  );
  // Janela de segurança: o aviso/barra some sozinho depois disto se o resultado
  // não chegar. A suíte hoje leva ~33 min, então 50 min dá folga sem prender o
  // aviso por muito tempo num raro caso de a corrida não reportar de volta.
  const JANELA_MS = 50 * 60 * 1000;
  // Estimativa de duração da suíte, só para a barra de progresso: a corrida real
  // varia (hoje ~33 min), então a barra avança pelo tempo decorrido e para perto
  // do fim (95%) até o resultado de verdade chegar — nunca finge 100% antes da hora.
  const ESTIMATIVA_MS = 35 * 60 * 1000;
  const chegouResultado = !!corrida && !!ultimaIniciada && ultimaIniciada > corrida.baseline;
  const dentroDaJanela = !!corrida && Date.now() - new Date(corrida.at).getTime() < JANELA_MS;
  const emAndamento = !!corrida && dentroDaJanela && !chegouResultado;

  // Quando chega uma corrida mais nova que o baseline, terminou: limpa o
  // marcador e avisa. (A lista já mostra o resultado — o refetch é automático.)
  useEffect(() => {
    if (chegouResultado) {
      gravarCorrida(null);
      setCorrida(null);
      toast.success("Corrida concluída", {
        description: "O resultado apareceu abaixo em Corridas.",
      });
    }
  }, [chegouResultado]);

  // Re-render de 1 em 1s enquanto em andamento: move a barra de progresso e
  // deixa a janela de 20 min expirar sozinha (o aviso some) mesmo sem dados novos.
  useEffect(() => {
    if (!emAndamento) return;
    const id = setInterval(() => setCorrida((c) => (c ? { ...c } : c)), 1000);
    return () => clearInterval(id);
  }, [emAndamento]);

  // Pede à esteira para rodar a suíte Cypress agora. O navegador não roda
  // Cypress; a Edge Function qa-disparar-cypress aciona o workflow no GitHub
  // Actions (o token do GitHub fica só no servidor). Só superadmin dispara.
  const rodarCypress = async () => {
    setDisparando(true);
    try {
      const { data, error } = await supabase.functions.invoke("qa-disparar-cypress");
      if (error) {
        // A função devolve a causa no corpo (401/403/503/502); o error.message
        // do supabase-js é genérico, então tentamos ler o corpo da resposta.
        let msg = error.message;
        const ctx = (error as { context?: Response }).context;
        if (ctx && typeof ctx.json === "function") {
          try {
            const body = await ctx.json();
            if (body?.error) msg = body.error;
          } catch {
            /* mantém msg genérica */
          }
        }
        toast.error("Não deu para disparar os testes", { description: msg });
        return;
      }
      toast.success("Corrida disparada", {
        description:
          (data as { mensagem?: string })?.mensagem ??
          "Ela aparece na esteira em instantes; o resultado volta para esta aba.",
      });
      // Marca a corrida como "em andamento": baseline = corrida e2e mais
      // recente agora; qualquer corrida mais nova encerra o aviso.
      const marcador = { baseline: ultimaIniciada, at: new Date().toISOString() };
      gravarCorrida(marcador);
      setCorrida(marcador);
    } catch (e) {
      toast.error("Não deu para disparar os testes", {
        description: (e as Error).message,
      });
    } finally {
      setDisparando(false);
    }
  };

  // Progresso da corrida em andamento, estimado pelo tempo decorrido. Começa
  // visível (3%) e para em 95% — a barra some junto com o aviso quando o
  // resultado chega, então nunca precisa fingir 100%.
  const decorridoMs = corrida ? Date.now() - new Date(corrida.at).getTime() : 0;
  const pctCorrida = Math.min(95, Math.max(3, (decorridoMs / ESTIMATIVA_MS) * 100));
  const restanteMs = ESTIMATIVA_MS - decorridoMs;
  const restanteLabel =
    restanteMs > 0
      ? `~${Math.max(1, Math.ceil(restanteMs / 60000))} min restantes`
      : "concluindo…";

  return (
    <div className="space-y-6">
      <Card>
        <CardContent className="pt-6 space-y-3 text-sm">
          <div className="flex items-start gap-2">
            <MonitorPlay className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />
            <div className="space-y-1">
              <p className="font-medium">Testes de tela (Cypress)</p>
              <p className="text-muted-foreground">
                Estes testes abrem o site de teste num navegador de verdade e
                clicam nas telas. Eles rodam na esteira (não no seu navegador):
                o botão abaixo pede à esteira para rodar a suíte agora, contra o
                site de teste como está publicado. Esta aba mostra o resultado de
                cada corrida — o que passou e o que falhou, teste a teste.
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Button
              id="btn-rodar-cypress"
              size="sm"
              onClick={rodarCypress}
              disabled={disparando}
              className="gap-2"
            >
              {disparando ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Play className="h-4 w-4" />
              )}
              {disparando ? "Disparando..." : "Rodar testes"}
            </Button>
            <a
              href="https://github.com/ustudy123/youreyesnovo/actions/workflows/cypress.yml"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
            >
              <ExternalLink className="h-3 w-3" />
              Acompanhar as corridas na esteira (prints e vídeos das falhas)
            </a>
          </div>
          <p className="text-xs text-muted-foreground">
            A corrida leva ~35 min e testa o site de teste como está publicado
            agora; para checar mudanças novas, publique antes. O resultado
            aparece aqui em “Corridas” quando terminar.
          </p>
        </CardContent>
      </Card>

      {/* aviso de corrida em andamento — some sozinho quando o resultado chega */}
      {emAndamento && (
        <Card className="border-primary/30 bg-primary/5">
          <CardContent className="pt-6 flex items-start gap-3 text-sm">
            <Loader2 className="h-4 w-4 mt-0.5 shrink-0 animate-spin text-primary" />
            <div className="flex-1 space-y-2">
              <p className="font-medium">Corrida em andamento…</p>
              <div className="space-y-1">
                <Progress value={pctCorrida} className="h-2" />
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <span>
                    Disparada às{" "}
                    {new Date(corrida!.at).toLocaleTimeString("pt-BR", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </span>
                  <span>{restanteLabel}</span>
                </div>
              </div>
              <p className="text-muted-foreground">
                A suíte roda na esteira (~35 min). Esta página se atualiza
                sozinha — o resultado aparece abaixo em “Corridas” assim que
                terminar. Pode fechar e voltar depois. A barra é uma estimativa
                pelo tempo; ela para perto do fim até o resultado real chegar.
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* agendamento — pede à esteira que rode a suíte no horário marcado */}
      <CardAgendamentoE2E />

      <div className="space-y-3">
        <h2 className="text-sm font-medium text-muted-foreground">Corridas</h2>
        <ListaExecucoes
          baterias={baterias}
          modulos={modulos}
          carregando={carregando}
          vazio={
            <span>
              Nenhuma corrida do Cypress chegou ainda. Assim que a esteira rodar
              a suíte e o envio ao painel estiver ligado, cada corrida aparece
              aqui com o resultado teste a teste.
            </span>
          }
        />
      </div>
    </div>
  );
}

export default function QARunner() {
  const navigate = useNavigate();
  const { modulos, carregandoModulos, baterias, carregandoBaterias, disparar } =
    useQaRunner();

  const [vista, setVista] = useState<"motor" | "cypress">("motor");
  const [moduloSel, setModuloSel] = useState<string>("__todos__");
  const [recemRodadaId, setRecemRodadaId] = useState<string | null>(null);

  // Corridas do Cypress (origem 'e2e') ficam na sua própria aba; o motor SQL
  // mostra só as suas (manual/agendado). Assim os dois não se misturam.
  const bateriasSql = baterias.filter((b) => b.disparo !== "e2e");
  const bateriasCypress = baterias.filter((b) => b.disparo === "e2e");

  const totalCasos = modulos.reduce((n, m) => n + Number(m.casos_executaveis), 0);

  const rodar = async () => {
    // "__todos__" vira string vazia, que o motor entende como "percorrer tudo"
    // (qa_rodar_bateria: v_todos := p_modulo IS NULL OR btrim(p_modulo) = '').
    //
    // NÃO usar `alvo || modulos[0]?...` aqui: string vazia é falsy em JS, então
    // o fallback derrubava "todos" para o primeiro módulo da lista e a bateria
    // rodava só Documentos, contrariando o que a tela mostrava.
    const alvo = moduloSel === "__todos__" ? "" : moduloSel;
    const id = await disparar.mutateAsync(alvo);
    setRecemRodadaId(id); // abre o relatório da bateria recém-criada
  };

  return (
    <div className="container max-w-4xl py-6 space-y-6">
      {/* cabeçalho */}
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate("/admin/qa")}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div className="flex items-center gap-2">
          <Bot className="h-5 w-5" />
          <h1 className="text-xl font-semibold">Testes automatizados</h1>
        </div>
      </div>

      {/* alternador de visão: motor SQL × testes de tela (Cypress) */}
      <div className="inline-flex rounded-lg border bg-muted/40 p-1">
        <button
          onClick={() => setVista("motor")}
          className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
            vista === "motor"
              ? "bg-background shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          <Database className="h-4 w-4" /> Motor (banco)
        </button>
        <button
          onClick={() => setVista("cypress")}
          className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
            vista === "cypress"
              ? "bg-background shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          <MonitorPlay className="h-4 w-4" /> Testes Cypress
          {bateriasCypress.length > 0 && (
            <span className="ml-1 rounded-full bg-muted px-1.5 text-xs">
              {bateriasCypress.length}
            </span>
          )}
        </button>
      </div>

      {vista === "motor" ? (
        <>
          {/* painel de disparo */}
          <Card>
            <CardContent className="pt-6">
              <div className="flex flex-col sm:flex-row sm:items-end gap-3">
                <div className="flex-1 space-y-1.5">
                  <label className="text-sm font-medium">Módulo</label>
                  <Select
                    value={moduloSel}
                    onValueChange={setModuloSel}
                    disabled={carregandoModulos || disparar.isPending}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Escolha o que rodar" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__todos__">
                        Todos os módulos · {totalCasos} casos
                      </SelectItem>
                      {modulos.map((m) => (
                        <SelectItem key={m.modulo_path} value={m.modulo_path}>
                          {m.label} · {m.casos_executaveis} casos
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <Button onClick={rodar} disabled={disparar.isPending || carregandoModulos}>
                  {disparar.isPending ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Rodando…
                    </>
                  ) : (
                    <>
                      <Play className="h-4 w-4 mr-2" />
                      Rodar bateria
                    </>
                  )}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground mt-3">
                Os testes rodam em um ambiente isolado. Nenhum dado de cliente é
                criado, alterado ou lido.
              </p>
            </CardContent>
          </Card>

          {/* agendamento */}
          <CardAgendamento />

          {/* histórico do motor SQL */}
          <div className="space-y-3">
            <h2 className="text-sm font-medium text-muted-foreground">Execuções</h2>
            <ListaExecucoes
              baterias={bateriasSql}
              modulos={modulos}
              carregando={carregandoBaterias}
              abrirId={recemRodadaId}
              vazio={
                <span>
                  Nenhuma bateria rodada ainda. Escolha um módulo e clique em
                  “Rodar bateria”.
                </span>
              }
            />
          </div>
        </>
      ) : (
        <PainelCypress
          baterias={bateriasCypress}
          modulos={modulos}
          carregando={carregandoBaterias}
        />
      )}
    </div>
  );
}
