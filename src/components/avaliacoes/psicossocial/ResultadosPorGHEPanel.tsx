import { isEntrevistaInstrumento } from "@/types/psicossocial";
import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import {
  Users,
  AlertTriangle,
  ShieldAlert,
  ShieldCheck,
  Lock,
  Sparkles,
  Loader2,
  Inbox,
  ChevronRight,
  Activity,
  Target,
} from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Progress } from "@/components/ui/progress";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { usePsicossocial } from "@/hooks/usePsicossocial";
import { usePsicossocialResultadosGHE, type ResultadoGHE, type EstratoGHE } from "@/hooks/usePsicossocialResultadosGHE";

import {
  GRO_NIVEL_RISCO_LABELS,
  GRO_NIVEL_RISCO_COLORS,
  GRO_PROBABILIDADE_LABELS,
  GRO_SEVERIDADE_LABELS,
  scoreToProbabilidade,
  scoreToSeveridade,
  calcularNivelGRO,
} from "@/types/gro";
import {
  resolverFatorPorSubject,
  CATEGORIA_LABELS,
} from "@/data/catalogoRiscosPsicossociais";
import { CriarAcaoAlertaModal } from "@/components/shared/CriarAcaoAlertaModal";

const MINIMO_ANONIMATO = 5;

interface FatorAvaliado {
  subject: string;
  fator: string;
  categoriaLabel: string;
  descricao: string;
  norma: string;
  scoreReal: number;
  probabilidadeLabel: string;
  severidadeLabel: string;
  nivelKey: 'baixo' | 'medio' | 'alto' | 'critico';
  nivelLabel: string;
}

interface GHEAvaliado extends ResultadoGHE {
  fatores: FatorAvaliado[];
  criticos: number;
  altos: number;
  medios: number;
  baixos: number;
  bloqueado: boolean;
}

function avaliarFatores(radar: ResultadoGHE['radar'], isSipro: boolean): FatorAvaliado[] {
  return radar.map(d => {
    const score = d.value;
    const prob = scoreToProbabilidade(score, isSipro);
    const sev = scoreToSeveridade(score, isSipro);
    const nivel = calcularNivelGRO(prob, sev);
    const fator = resolverFatorPorSubject(d.subject);
    return {
      subject: d.subject,
      fator: fator?.nome ?? d.subject,
      categoriaLabel: fator ? CATEGORIA_LABELS[fator.categoria] : "Não classificado",
      descricao: fator?.descricao ?? "Fator não catalogado — avaliar enquadramento normativo manualmente.",
      norma: fator ? fator.baseNormativa.join(" / ") : "NR-01 / ISO 45003",
      scoreReal: score,
      probabilidadeLabel: GRO_PROBABILIDADE_LABELS[prob],
      severidadeLabel: GRO_SEVERIDADE_LABELS[sev],
      nivelKey: nivel,
      nivelLabel: GRO_NIVEL_RISCO_LABELS[nivel],
    };
  });
}

const ordemNivel: Record<string, number> = { critico: 0, alto: 1, medio: 2, baixo: 3 };

export function ResultadosPorGHEPanel() {
  const { campanhas, isLoadingCampanhas } = usePsicossocial();
  const [gheDrillDown, setGheDrillDown] = useState<GHEAvaliado | null>(null);
  const [campanhaFiltro, setCampanhaFiltro] = useState<string>("all");

  const campanhasValidasTodas = useMemo(
    () => campanhas.filter(c =>
      c.ips_score != null &&
      // Entrevista guiada individual é nominal: não há regra de anonimato de 5
      // respostas; o inventário/plano de ação valem a partir de 1 entrevista.
      (c.total_respostas || 0) >= (isEntrevistaInstrumento((c as any).tipo_instrumento) ? 1 : MINIMO_ANONIMATO) &&
      Array.isArray(c.radar_data) &&
      c.radar_data.length > 0,
    ),
    [campanhas],
  );

  const campanhasValidas = useMemo(
    () => campanhaFiltro === "all"
      ? campanhasValidasTodas
      : campanhasValidasTodas.filter(c => c.id === campanhaFiltro),
    [campanhasValidasTodas, campanhaFiltro],
  );

  // Se o recorte é só de entrevistas guiadas, o mínimo por GHE cai para 1.
  const minimoGrupo = useMemo(
    () => campanhasValidas.length > 0 && campanhasValidas.every(c => isEntrevistaInstrumento((c as any).tipo_instrumento))
      ? 1
      : MINIMO_ANONIMATO,
    [campanhasValidas],
  );

  const isSipro = campanhasValidas[0]?.instrumento === 'sipro';
  const campanhaIds = useMemo(() => campanhasValidas.map(c => c.id), [campanhasValidas]);
  const { resultadosPorGHE, isLoading, error } = usePsicossocialResultadosGHE(campanhaIds);



  if (typeof window !== "undefined") {
    // Diagnóstico em runtime para entender por que o painel pode aparecer vazio
    // (mostra contagem de campanhas válidas, respostas agregadas e eventuais erros).
    // eslint-disable-next-line no-console
    console.debug("[ResultadosPorGHEPanel]", {
      totalCampanhas: campanhas.length,
      campanhasValidas: campanhasValidas.length,
      campanhaIds,
      resultadosPorGHE: resultadosPorGHE.length,
      gruposDetalhe: resultadosPorGHE.map(r => ({ ghe: r.ghe_nome, count: r.count, campanhas: r.campanhas })),
      error,
    });
  }

  const ghesAvaliados: GHEAvaliado[] = useMemo(() => {
    return resultadosPorGHE
      .map(g => {
        const fatores = avaliarFatores(g.radar, isSipro);
        fatores.sort((a, b) => (ordemNivel[a.nivelKey] ?? 4) - (ordemNivel[b.nivelKey] ?? 4));
        // GHE com menos de 5 elegíveis (empresa pequena) nunca alcançaria o piso
        // de anonimato: o mínimo passa a ser a própria população do grupo.
        const minGrupo = Math.max(1, Math.min(minimoGrupo, g.elegiveis || minimoGrupo));
        const bloqueado = g.count < minGrupo;
        return {
          ...g,
          fatores: bloqueado ? [] : fatores,
          criticos: fatores.filter(f => f.nivelKey === 'critico').length,
          altos: fatores.filter(f => f.nivelKey === 'alto').length,
          medios: fatores.filter(f => f.nivelKey === 'medio').length,
          baixos: fatores.filter(f => f.nivelKey === 'baixo').length,
          bloqueado,
        };
      })
      .sort((a, b) => {
        // GHEs reais primeiro, "sem GHE" por último
        if (!!a.ghe_id !== !!b.ghe_id) return a.ghe_id ? -1 : 1;
        if (a.bloqueado !== b.bloqueado) return a.bloqueado ? 1 : -1;
        if (b.criticos !== a.criticos) return b.criticos - a.criticos;
        if (b.altos !== a.altos) return b.altos - a.altos;
        return (a.ipsMedio ?? 100) - (b.ipsMedio ?? 100);
      });
  }, [resultadosPorGHE, isSipro, minimoGrupo]);

  const filtroCampanhaBar = (
    <div className="flex flex-col sm:flex-row sm:items-center gap-2 px-1">
      <span className="text-xs font-medium text-muted-foreground">Filtrar por campanha:</span>
      <Select value={campanhaFiltro} onValueChange={setCampanhaFiltro}>
        <SelectTrigger className="h-8 text-xs w-full sm:w-[320px]">
          <SelectValue placeholder="Selecione uma campanha" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">
            Todas as campanhas ({campanhasValidasTodas.length})
          </SelectItem>
          {campanhasValidasTodas.map(c => (
            <SelectItem key={c.id} value={c.id}>
              {c.nome ?? "Campanha sem nome"} · {c.total_respostas ?? 0} resp.
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );

  if (isLoadingCampanhas || isLoading) {
    return (
      <div className="space-y-3">
        {filtroCampanhaBar}
        <div className="flex items-center justify-center py-12 text-muted-foreground">
          <Loader2 className="h-5 w-5 animate-spin mr-2" /> Carregando resultados por GHE…
        </div>
      </div>
    );
  }

  if (campanhasValidas.length === 0) {
    return (
      <div className="space-y-3">
        {filtroCampanhaBar}
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-10 text-center gap-2">
            <Inbox className="h-8 w-8 text-muted-foreground opacity-40" />
            <p className="text-sm font-medium">Nenhuma campanha válida encontrada</p>
            <p className="text-xs text-muted-foreground max-w-md">
              É necessário pelo menos uma campanha com resultados (mín. {MINIMO_ANONIMATO} respostas em questionários; 1 em entrevista guiada)
              e dados do radar calculados.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (ghesAvaliados.length === 0) {
    return (
      <div className="space-y-3">
        {filtroCampanhaBar}
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-10 text-center gap-2">
            <Users className="h-8 w-8 text-muted-foreground opacity-40" />
            <p className="text-sm font-medium">Nenhum GHE com respostas vinculadas</p>
            <p className="text-xs text-muted-foreground max-w-md">
              Encontramos <strong>{campanhasValidas.length} campanha(s) válida(s)</strong>, mas
              nenhuma resposta carrega o <code>ghe_id_snapshot</code> e as campanhas correspondentes
              não têm GHEs (<code>ghe_ids</code>) configurados.
            </p>
            <p className="text-xs text-muted-foreground max-w-md">
              Para liberar a análise: edite a campanha e vincule um ou mais GHEs, ou colete novas
              respostas via link público com GHE definido por par Setor + Função.
            </p>
            {error && (
              <p className="text-xs text-red-600 mt-2">Erro ao carregar: {String(error)}</p>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  const totalCriticos = ghesAvaliados.reduce((s, g) => s + g.criticos, 0);
  const totalAltos = ghesAvaliados.reduce((s, g) => s + g.altos, 0);
  const ghesBloqueados = ghesAvaliados.filter(g => g.bloqueado).length;

  return (
    <div className="space-y-4">
      {filtroCampanhaBar}
      <Card>

        <CardHeader className="pb-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <Users className="h-4 w-4 text-cyan-600" />
                Resultados por GHE — Grupo Homogêneo de Exposição
                <Badge variant="outline" className="text-[10px] bg-cyan-50 text-cyan-700 border-cyan-200">
                  NR-17 / ISO 45003
                </Badge>
              </CardTitle>
              <CardDescription className="text-xs mt-0.5">
                {ghesAvaliados.length} GHE(s) com respostas · {campanhasValidas.length} campanha(s) consideradas
                {ghesBloqueados > 0 && ` · ${ghesBloqueados} bloqueado(s) por anonimato`}
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              {totalCriticos > 0 && (
                <Badge className="bg-red-600 text-white gap-1">
                  <AlertTriangle className="h-3 w-3" />
                  {totalCriticos} crítico(s)
                </Badge>
              )}
              {totalAltos > 0 && (
                <Badge className="bg-orange-500 text-white">{totalAltos} alto(s)</Badge>
              )}
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {ghesAvaliados.map((g) => (
              <motion.div
                key={g.ghe_id ?? `sem-ghe-${g.ghe_nome}`}
                whileHover={{ y: -3 }}
                transition={{ type: "spring", stiffness: 300, damping: 20 }}
              >
                <Card
                  role="button"
                  tabIndex={0}
                  onClick={() => !g.bloqueado && setGheDrillDown(g)}
                  onKeyDown={(e) => {
                    if ((e.key === 'Enter' || e.key === ' ') && !g.bloqueado) setGheDrillDown(g);
                  }}
                  className={cn(
                    "h-full transition-colors border-l-4",
                    g.criticos > 0 ? "border-l-red-500" :
                    g.altos > 0 ? "border-l-orange-500" :
                    g.medios > 0 ? "border-l-amber-500" :
                    g.bloqueado ? "border-l-muted opacity-70" : "border-l-emerald-500",
                    !g.bloqueado && "cursor-pointer hover:border-primary/40",
                  )}
                >
                  <CardContent className="p-4 space-y-3">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex-1 min-w-0">
                        <p className="font-semibold text-sm leading-tight">{g.ghe_nome}</p>
                        <p className="text-[11px] text-muted-foreground mt-0.5">
                          {g.count} respondente(s) · {g.campanhas} campanha(s)
                        </p>
                      </div>
                      {g.ipsMedio != null && !g.bloqueado && (
                        <div className="text-right">
                          <p className="text-[10px] text-muted-foreground uppercase">IPS</p>
                          <p className={cn(
                            "font-bold text-lg leading-none",
                            g.ipsMedio < 35 ? "text-red-600" :
                            g.ipsMedio < 50 ? "text-orange-600" :
                            g.ipsMedio < 65 ? "text-amber-600" :
                            g.ipsMedio < 80 ? "text-blue-600" : "text-emerald-600",
                          )}>
                            {g.ipsMedio}
                          </p>
                        </div>
                      )}
                    </div>

                    {g.bloqueado ? (
                      <div className="flex items-start gap-2 p-2 rounded-md border border-amber-200 bg-amber-50/60 text-[11px] text-amber-800">
                        <Lock className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                        <span>
                          Mínimo de {minimoGrupo} respondentes não atingido —
                          análise bloqueada por anonimato (ISO 45003).
                        </span>
                      </div>
                    ) : (
                      <>
                        <div className="grid grid-cols-4 gap-1">
                          {[
                            { label: 'Crít.', count: g.criticos, cls: 'bg-red-50 text-red-700 border-red-200' },
                            { label: 'Alto', count: g.altos, cls: 'bg-orange-50 text-orange-700 border-orange-200' },
                            { label: 'Médio', count: g.medios, cls: 'bg-amber-50 text-amber-700 border-amber-200' },
                            { label: 'Baixo', count: g.baixos, cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
                          ].map(s => (
                            <div key={s.label} className={cn("rounded border text-center p-1.5", s.cls)}>
                              <p className="font-bold text-sm leading-none">{s.count}</p>
                              <p className="text-[9px] font-medium leading-tight mt-0.5">{s.label}</p>
                            </div>
                          ))}
                        </div>
                        <Button variant="ghost" size="sm" className="w-full h-7 text-xs gap-1 text-primary hover:bg-primary/5">
                          Ver fatores e recomendações
                          <ChevronRight className="h-3 w-3" />
                        </Button>
                      </>
                    )}
                  </CardContent>
                </Card>
              </motion.div>
            ))}
          </div>
        </CardContent>
      </Card>

      <GHEDrillDownSheet
        ghe={gheDrillDown}
        onOpenChange={(o) => !o && setGheDrillDown(null)}
      />
    </div>
  );
}

interface GHEDrillDownSheetProps {
  ghe: GHEAvaliado | null;
  onOpenChange: (open: boolean) => void;
}

function GHEDrillDownSheet({ ghe, onOpenChange }: GHEDrillDownSheetProps) {
  const [acaoAlerta, setAcaoAlerta] = useState<FatorAvaliado | null>(null);

  if (!ghe) {
    return (
      <Sheet open={false} onOpenChange={onOpenChange}>
        <SheetContent />
      </Sheet>
    );
  }

  return (
    <>
      <Sheet open={!!ghe} onOpenChange={onOpenChange}>
        <SheetContent className="w-full sm:max-w-2xl overflow-hidden flex flex-col p-0">
          <SheetHeader className="px-6 pt-6 pb-3 border-b">
            <SheetTitle className="flex items-center gap-2 text-base">
              <Users className="h-5 w-5 text-cyan-600" />
              {ghe.ghe_nome}
              {ghe.ghe_codigo && (
                <Badge variant="outline" className="text-[10px] font-mono">
                  {ghe.ghe_codigo}
                </Badge>
              )}
            </SheetTitle>
            <SheetDescription className="text-xs">
              {ghe.count} respondente(s) · {ghe.campanhas} campanha(s)
              {ghe.ipsMedio != null && (
                <> · IPS médio <strong className="text-foreground">{ghe.ipsMedio}</strong></>
              )}
            </SheetDescription>
            <div className="flex flex-wrap gap-1.5 pt-1">
              {ghe.criticos > 0 && (
                <Badge className="bg-red-600 text-white text-[10px]">{ghe.criticos} crítico(s)</Badge>
              )}
              {ghe.altos > 0 && (
                <Badge className="bg-orange-500 text-white text-[10px]">{ghe.altos} alto(s)</Badge>
              )}
              {ghe.medios > 0 && (
                <Badge className="bg-amber-500 text-white text-[10px]">{ghe.medios} médio(s)</Badge>
              )}
              {ghe.baixos > 0 && (
                <Badge className="bg-emerald-600 text-white text-[10px]">{ghe.baixos} baixo(s)</Badge>
              )}
            </div>

            {ghe.composicaoSetorCargos.length > 0 && (
              <div className="mt-2 rounded-md border bg-muted/30 p-2.5 space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[10px] font-semibold uppercase text-muted-foreground">
                    Composição cadastral do GHE
                  </p>
                  <span className="text-[10px] text-muted-foreground">
                    {ghe.composicaoSetorCargos.length} setor(es) · {ghe.composicaoCargos.length} cargo(s)
                  </span>
                </div>
                <p className="text-[10px] text-muted-foreground leading-snug">
                  Vínculos Setor → Cargo conforme cadastro do GHE. Um mesmo cargo pode aparecer em mais de um setor.
                </p>
                <div className="space-y-1.5">
                  {ghe.composicaoSetorCargos.map(({ setor, cargos }) => (
                    <div key={setor} className="rounded border bg-background/60 p-2">
                      <div className="flex items-center gap-1.5 mb-1">
                        <Badge variant="secondary" className="text-[10px] font-medium">
                          {setor}
                        </Badge>
                        <span className="text-[10px] text-muted-foreground">
                          {cargos.length} cargo(s)
                        </span>
                      </div>
                      <div className="flex flex-wrap gap-1">
                        {cargos.length === 0 ? (
                          <span className="text-[10px] text-muted-foreground italic">
                            Setor sem cargo vinculado neste GHE
                          </span>
                        ) : (
                          cargos.map(c => (
                            <Badge
                              key={c}
                              variant="outline"
                              className="text-[10px] font-normal bg-cyan-50 text-cyan-700 border-cyan-200"
                            >
                              {c}
                            </Badge>
                          ))
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </SheetHeader>



          <ScrollArea className="flex-1 px-6 py-4">
            <Tabs defaultValue="fatores" className="space-y-3">
              <TabsList className="grid grid-cols-3 w-full">
                <TabsTrigger value="fatores" className="text-xs">Fatores</TabsTrigger>
                <TabsTrigger value="setores" className="text-xs">
                  Por setor ({ghe.setores.length})
                </TabsTrigger>
                <TabsTrigger value="cargos" className="text-xs">
                  Por cargo ({ghe.cargos.length})
                </TabsTrigger>
              </TabsList>

              <TabsContent value="fatores" className="space-y-3 mt-3">
                <p className="text-xs text-muted-foreground flex items-start gap-1.5">
                  <Activity className="h-3.5 w-3.5 mt-0.5 shrink-0 text-cyan-600" />
                  Fatores psicossociais avaliados para este Grupo Homogêneo de Exposição, ordenados do
                  mais crítico ao mais saudável. Para cada fator não tolerável (crítico/alto) você pode
                  gerar uma <strong>ação 5W2H</strong> direto no Plano de Ação Global.
                </p>

                {ghe.fatores.length === 0 ? (
                  <div className="text-center text-sm text-muted-foreground py-6">
                    Nenhum fator avaliado neste GHE.
                  </div>
                ) : (
                  ghe.fatores.map((f) => {
                    const cor =
                      f.nivelKey === 'critico' ? 'border-l-red-500 bg-red-50/30' :
                      f.nivelKey === 'alto' ? 'border-l-orange-500 bg-orange-50/30' :
                      f.nivelKey === 'medio' ? 'border-l-amber-500 bg-amber-50/30' :
                      'border-l-emerald-500 bg-emerald-50/20';
                    return (
                      <Card key={f.subject} className={cn("border-l-4", cor)}>
                        <CardContent className="p-3 space-y-2">
                          <div className="flex items-start justify-between gap-2">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <p className="font-semibold text-sm leading-tight">{f.fator}</p>
                                <Badge variant="outline" className="text-[9px] bg-purple-50 text-purple-700 border-purple-200">
                                  {f.categoriaLabel}
                                </Badge>
                              </div>
                              <p className="text-[11px] text-muted-foreground leading-snug mt-0.5">
                                {f.descricao}
                              </p>
                            </div>
                            <Badge variant="outline" className={cn("shrink-0 text-[10px]", GRO_NIVEL_RISCO_COLORS[f.nivelKey])}>
                              {f.nivelLabel}
                            </Badge>
                          </div>

                          <div className="grid grid-cols-3 gap-2 text-[10px]">
                            <div>
                              <p className="text-muted-foreground uppercase">Score</p>
                              <p className="font-bold text-sm">{f.scoreReal}%</p>
                              <Progress value={f.scoreReal} className="h-1 mt-0.5" />
                            </div>
                            <div>
                              <p className="text-muted-foreground uppercase">Probabilidade</p>
                              <p className="font-semibold text-xs">{f.probabilidadeLabel}</p>
                            </div>
                            <div>
                              <p className="text-muted-foreground uppercase">Severidade</p>
                              <p className="font-semibold text-xs">{f.severidadeLabel}</p>
                            </div>
                          </div>

                          <div className="flex items-center justify-between gap-2 pt-1 border-t">
                            <Badge variant="outline" className="text-[9px] font-mono">{f.norma}</Badge>
                            {(f.nivelKey === 'critico' || f.nivelKey === 'alto') && (
                              <Button
                                size="sm"
                                variant="outline"
                                className="h-7 gap-1 text-xs border-primary/30 text-primary hover:bg-primary/5"
                                onClick={() => setAcaoAlerta(f)}
                              >
                                <Sparkles className="h-3 w-3" />
                                Criar Ação 5W2H
                              </Button>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    );
                  })
                )}

                <div className="mt-4 p-3 rounded-lg border bg-muted/30 text-[11px] text-muted-foreground flex items-start gap-2">
                  <ShieldCheck className="h-3.5 w-3.5 mt-0.5 shrink-0 text-emerald-600" />
                  <p>
                    Os scores apresentados resultam exclusivamente das respostas dos colaboradores deste GHE,
                    mantendo o anonimato individual (mínimo {MINIMO_ANONIMATO} respondentes — ISO 45003).
                    Use as ações 5W2H para registrar evidência do tratamento dos riscos no PGR.
                  </p>
                </div>
              </TabsContent>

              <TabsContent value="setores" className="mt-3">
                <EstratificacaoLista estratos={ghe.setores} tipo="setor" />
              </TabsContent>
              <TabsContent value="cargos" className="mt-3">
                <EstratificacaoLista estratos={ghe.cargos} tipo="cargo" />
              </TabsContent>
            </Tabs>
          </ScrollArea>

        </SheetContent>
      </Sheet>

      {acaoAlerta && ghe && (
        <CriarAcaoAlertaModal
          open={!!acaoAlerta}
          onOpenChange={(o) => !o && setAcaoAlerta(null)}
          alertaTitulo={`${acaoAlerta.fator} — GHE ${ghe.ghe_nome}`}
          alertaDescricao={`${acaoAlerta.descricao} Nível: ${acaoAlerta.nivelLabel}. Score ${acaoAlerta.scoreReal}% (Prob. ${acaoAlerta.probabilidadeLabel} / Sev. ${acaoAlerta.severidadeLabel}).`}
          origemModulo="psicossocial"
          contextoExtra={`Grupo Homogêneo de Exposição: ${ghe.ghe_nome} (${ghe.count} respondentes). Base normativa: ${acaoAlerta.norma}.`}
        />
      )}
    </>
  );
}


interface EstratificacaoListaProps {
  estratos: EstratoGHE[];
  tipo: "setor" | "cargo";
}

function EstratificacaoLista({ estratos, tipo }: EstratificacaoListaProps) {
  if (estratos.length === 0) {
    return (
      <div className="text-center text-sm text-muted-foreground py-6">
        Nenhum {tipo} informado nas respostas deste GHE.
      </div>
    );
  }
  const total = estratos.reduce((s, e) => s + e.count, 0);
  return (
    <div className="space-y-2">
      <p className="text-xs text-muted-foreground flex items-start gap-1.5">
        <Target className="h-3.5 w-3.5 mt-0.5 shrink-0 text-cyan-600" />
        Estratificação por {tipo} dentro deste GHE. Grupos com menos de {MINIMO_ANONIMATO}{" "}
        respondentes têm o IPS suprimido para preservar o anonimato (ISO 45003).
      </p>
      {estratos.map((e) => {
        const bloqueado = e.count < MINIMO_ANONIMATO;
        const pct = total > 0 ? Math.round((e.count / total) * 100) : 0;
        return (
          <Card key={e.nome} className={cn("border-l-4", bloqueado ? "border-l-muted" :
            e.ipsMedio == null ? "border-l-muted" :
            e.ipsMedio < 35 ? "border-l-red-500" :
            e.ipsMedio < 50 ? "border-l-orange-500" :
            e.ipsMedio < 65 ? "border-l-amber-500" :
            e.ipsMedio < 80 ? "border-l-blue-500" : "border-l-emerald-500")}>
            <CardContent className="p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-sm leading-tight truncate">{e.nome}</p>
                  <p className="text-[11px] text-muted-foreground mt-0.5">
                    {e.count} respondente(s) · {pct}% do GHE
                  </p>
                </div>
                {bloqueado ? (
                  <Badge variant="outline" className="text-[10px] gap-1 border-amber-300 text-amber-700 bg-amber-50">
                    <Lock className="h-3 w-3" /> Anonimato
                  </Badge>
                ) : e.ipsMedio != null ? (
                  <div className="text-right shrink-0">
                    <p className="text-[10px] text-muted-foreground uppercase">IPS</p>
                    <p className={cn(
                      "font-bold text-base leading-none",
                      e.ipsMedio < 35 ? "text-red-600" :
                      e.ipsMedio < 50 ? "text-orange-600" :
                      e.ipsMedio < 65 ? "text-amber-600" :
                      e.ipsMedio < 80 ? "text-blue-600" : "text-emerald-600",
                    )}>
                      {e.ipsMedio}
                    </p>
                  </div>
                ) : null}
              </div>
              <Progress value={pct} className="h-1" />
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
