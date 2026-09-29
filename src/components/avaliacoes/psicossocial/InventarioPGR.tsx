import { useMemo, useState, useEffect } from "react";
import { isEntrevistaInstrumento } from "@/types/psicossocial";
import {
  FileText,
  AlertTriangle,
  ShieldAlert,
  Info,
  ChevronDown,
  ChevronUp,
  Loader2,
  ShieldCheck,
  Database,
  BookOpen,
  RefreshCw,
  Filter,
  Users,
} from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { RelatorioModal } from "./RelatorioModal";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import type { CampanhaPsicossocial, RadarDimensao } from "@/types/psicossocial";
import { toast } from "sonner";
import { useGRORiscos } from "@/hooks/useGRORiscos";
import { resolverSituacoesTrabalho } from "@/utils/situacoesCampanha";
import { usePsicossocialResultadosGHE } from "@/hooks/usePsicossocialResultadosGHE";
import { PrivacidadeGrupoAlert } from "./PrivacidadeGrupoAlert";
import {
  aplicarRegrasPrivacidade,
  estimarContagemPorGrupo,
  MINIMO_RESPONDENTES_GRUPO,
} from "@/lib/psicossocial-privacy";
import {
  scoreToProb15,
  sevFallbackFromScore,
  nivelGRO15,
  normalizarNomeFator,
  PROB15_LABELS,
  NIVEL15_LABELS,
  NIVEL15_ORDEM,
  type NivelGRO15,
} from "@/lib/groPsicossocial15";
import { getSeveridadeInfo } from "@/lib/psicossocial-severidade";
import { useSeveridadesCatalogo } from "@/hooks/useSeveridadesCatalogo";
import {
  resolverFatorPorSubject,
  CATEGORIA_LABELS,
  type CategoriaRiscoPsicossocial,
} from "@/data/catalogoRiscosPsicossociais";
import { ExplicacaoPGRGRO } from "./ExplicacaoPGRGRO";
import { EvidenciasEntrevistaPanel } from "./EvidenciasEntrevistaPanel";

interface InventarioPGRProps {
  campanhas: CampanhaPsicossocial[];
}

const MINIMO_ANONIMATO = 5;

/**
 * Resolve a normativa e o fator a partir do catálogo unificado.
 * O catálogo (NR-01 + ISO 45003) substitui o antigo mapa hardcoded.
 */
function getNormativaForSubject(subject: string): {
  fator: string;
  norma: string;
  descricao: string;
  categoria: CategoriaRiscoPsicossocial | null;
  categoriaLabel: string;
  manifestacoes: string[];
} {
  const fator = resolverFatorPorSubject(subject);
  if (fator) {
    return {
      fator: fator.nome,
      norma: fator.baseNormativa.join(" / "),
      descricao: fator.descricao,
      categoria: fator.categoria,
      categoriaLabel: CATEGORIA_LABELS[fator.categoria],
      manifestacoes: fator.manifestacoes,
    };
  }
  return {
    fator: subject,
    norma: "NR-01 / ISO 45003",
    descricao: "Fator psicossocial não catalogado — avaliar enquadramento normativo manualmente.",
    categoria: null,
    categoriaLabel: "Não classificado",
    manifestacoes: [],
  };
}

interface InventarioItem {
  fatorId: string;
  dimensoes: string[]; // dimensões do instrumento equivalentes a este fator
  fator: string;
  norma: string;
  descricao: string;
  categoriaLabel: string;
  manifestacoes: string[];
  scoreReal: number;
  probabilidadeLabel: string;
  severidadeLabel: string;
  nivelLabel: string;
  nivelKey: NivelGRO15;
  fonteCampanhas: number; // quantas campanhas contribuíram com score para esse fator
}

export function InventarioPGR({ campanhas }: InventarioPGRProps) {
  const [expanded, setExpanded] = useState(false);
  const [relatorioOpen, setRelatorioOpen] = useState(false);
  const { data: sevCatalogo } = useSeveridadesCatalogo();
  // Campanhas válidas (mín. anonimato para questionário, 1 para entrevista guiada)
  const campanhasValidas = useMemo(() =>
    campanhas.filter(c => {
      const isEntrevistaGuiada =isEntrevistaInstrumento((c as any).tipo_instrumento);
      const minRespostas = isEntrevistaGuiada ? 1 : MINIMO_ANONIMATO;
      
      return c.ips_score != null &&
        (c.total_respostas || 0) >= minRespostas &&
        Array.isArray(c.radar_data) &&
        c.radar_data.length > 0;
    }),
    [campanhas]
  );

  const { importarDaCampanha, riscos: groRiscos } = useGRORiscos();
  const pendentesReavaliacao = groRiscos.filter(r => r.necessita_reavaliacao).length;

  const [filtroCampanha, setFiltroCampanha] = useState<string>("todos");
  const [filtroGHE, setFiltroGHE] = useState<string>("todos");

  useEffect(() => {
    if (campanhasValidas.length > 0) {
      if (filtroCampanha === "todos") {
        // Se estiver em "todos", mantém
      } else if (!campanhasValidas.some(c => c.id === filtroCampanha)) {
        // Se a campanha selecionada não for mais válida, volta para "todos"
        setFiltroCampanha("todos");
      }
    }
  }, [campanhasValidas, filtroCampanha]);

  const isSipro = campanhasValidas[0]?.instrumento === 'sipro' ||isEntrevistaInstrumento((campanhasValidas[0] as any)?.tipo_instrumento);
  const campanhaAtual = campanhasValidas[0];
  const semEscopoGRO = !campanhaAtual?.situacoes_trabalho || campanhaAtual.situacoes_trabalho.length === 0;

  // ── GAP A+B: Proteção de privacidade por grupo (ISO 45003) ──────────────────
  // Calcula quais pares setor+função têm respondentes suficientes,
  // aplica fallback automático (funcao → setor → empresa) para grupos pequenos.
  const privacidadeGrupos = useMemo(() => {
    if (!campanhaAtual) return null;
    const situacoes = campanhaAtual.situacoes_trabalho ?? [];
    const totalRespondentes = campanhaAtual.total_respostas ?? 0;
    const contagem = estimarContagemPorGrupo(totalRespondentes, situacoes);
    return aplicarRegrasPrivacidade(situacoes, contagem, totalRespondentes);
  }, [campanhaAtual]);

  // Agregação por GHE (respostas com ghe_id_snapshot). Permite filtrar o inventário
  // por um único Grupo Homogêneo de Exposição (NR-17 / ISO 45003).
  const campanhasIdsParaGHE = useMemo(
    () => (filtroCampanha === "todos" ? campanhasValidas.map(c => c.id) : [filtroCampanha]),
    [campanhasValidas, filtroCampanha],
  );
  const { resultadosPorGHE, isLoading: isLoadingGHE } = usePsicossocialResultadosGHE(campanhasIdsParaGHE);

  const ghesDisponiveis = useMemo(
    () => resultadosPorGHE.filter(r => r.ghe_id && r.count > 0),
    [resultadosPorGHE],
  );

  // Reseta filtro de GHE se não fizer mais sentido
  useEffect(() => {
    if (filtroGHE !== "todos" && !ghesDisponiveis.some(g => g.ghe_id === filtroGHE)) {
      setFiltroGHE("todos");
    }
  }, [ghesDisponiveis, filtroGHE]);

  const gheSelecionado = filtroGHE === "todos"
    ? null
    : ghesDisponiveis.find(g => g.ghe_id === filtroGHE) ?? null;
  const bloqueadoPorAnonimatoGHE = !!gheSelecionado && gheSelecionado.count < MINIMO_ANONIMATO;

  /**
   * Agregação real das dimensões.
   * - Sem filtro de GHE: usa radar_data já calculado das campanhas válidas (média ponderada por respondentes).
   * - Com filtro de GHE: usa radar reconstruído das respostas individuais do GHE selecionado.
   */

  const inventario = useMemo((): InventarioItem[] => {
    if (campanhasValidas.length === 0) return [];

    // 1. Coleta scores brutos por subject (dimensão do instrumento)
    const porSubject: Record<string, { somaScore: number; pesoTotal: number; campanhas: number }> = {};

    if (gheSelecionado) {
      if (bloqueadoPorAnonimatoGHE) return [];
      gheSelecionado.radar.forEach(dim => {
        porSubject[dim.subject] = { somaScore: dim.value, pesoTotal: 1, campanhas: 1 };
      });
    } else {
      const campanhasParaProcessar = filtroCampanha === "todos"
        ? campanhasValidas
        : campanhasValidas.filter(c => c.id === filtroCampanha);

      if (campanhasParaProcessar.length === 0) return [];

      campanhasParaProcessar.forEach(campanha => {
        const peso = campanha.total_respostas ?? 1;
        const radar = campanha.radar_data as RadarDimensao[];
        radar.forEach(dim => {
          if (!porSubject[dim.subject]) {
            porSubject[dim.subject] = { somaScore: 0, pesoTotal: 0, campanhas: 0 };
          }
          porSubject[dim.subject].somaScore += dim.value * peso;
          porSubject[dim.subject].pesoTotal += peso;
          porSubject[dim.subject].campanhas += 1;
        });
      });
    }

    // 2. Reagrupa por fator do catálogo (13 fatores padrão NR-01 / ISO 45003).
    //    Várias dimensões do instrumento (COPSOQ/SIPRO/HSE) podem mapear ao mesmo fator
    //    — aqui consolidamos a média ponderada para um único registro por fator.
    type FatorAgg = {
      fatorId: string;
      dimensoes: Set<string>;
      somaScore: number;
      pesoTotal: number;
      campanhas: number;
      normativa: ReturnType<typeof getNormativaForSubject>;
    };
    const porFator: Record<string, FatorAgg> = {};





    Object.entries(porSubject).forEach(([subject, agg]) => {
      const normativa = getNormativaForSubject(subject);
      // chave estável: nome do fator do catálogo (ou subject puro quando não catalogado)
      const fatorKey = normativa.fator;
      if (!porFator[fatorKey]) {
        porFator[fatorKey] = {
          fatorId: fatorKey,
          dimensoes: new Set(),
          somaScore: 0,
          pesoTotal: 0,
          campanhas: 0,
          normativa,
        };
      }
      porFator[fatorKey].dimensoes.add(subject);
      porFator[fatorKey].somaScore += agg.somaScore;
      porFator[fatorKey].pesoTotal += agg.pesoTotal;
      porFator[fatorKey].campanhas = Math.max(porFator[fatorKey].campanhas, agg.campanhas);
    });

    const items: InventarioItem[] = Object.values(porFator).map(agg => {
      const scoreReal = Math.round(agg.somaScore / agg.pesoTotal);
      // Metodologia P x S: probabilidade variável (score) + severidade FIXA do
      // catálogo de riscos; nível pelo cruzamento na matriz (inclui TRIVIAL).
      // Instrumentos não-SIPRO usam escala protetiva — converte para risco.
      const scoreRisco = isSipro ? scoreReal : 100 - scoreReal;
      const prob = scoreToProb15(scoreRisco);
      const sev = sevCatalogo?.get(normalizarNomeFator(agg.normativa.fator)) ?? sevFallbackFromScore(scoreRisco);
      const nivel = nivelGRO15(prob, sev);

      return {
        fatorId: agg.fatorId,
        dimensoes: Array.from(agg.dimensoes).sort(),
        fator: agg.normativa.fator,
        norma: agg.normativa.norma,
        descricao: agg.normativa.descricao,
        categoriaLabel: agg.normativa.categoriaLabel,
        manifestacoes: agg.normativa.manifestacoes,
        scoreReal,
        probabilidadeLabel: PROB15_LABELS[prob],
        severidadeLabel: getSeveridadeInfo(sev)?.label ?? String(sev),
        nivelLabel: NIVEL15_LABELS[nivel],
        nivelKey: nivel,
        fonteCampanhas: agg.campanhas,
      };
    });

    return items.sort((a, b) => (NIVEL15_ORDEM[a.nivelKey] ?? 5) - (NIVEL15_ORDEM[b.nivelKey] ?? 5));
  }, [campanhasValidas, isSipro, filtroCampanha, gheSelecionado, bloqueadoPorAnonimatoGHE, sevCatalogo]);



  const criticos = inventario.filter(i => i.nivelKey === 'critico').length;
  const altos = inventario.filter(i => i.nivelKey === 'alto').length;
  const medios = inventario.filter(i => i.nivelKey === 'medio').length;
  const baixos = inventario.filter(i => i.nivelKey === 'baixo').length;
  const triviais = inventario.filter(i => i.nivelKey === 'trivial').length;

  const handleImportarGRO = async () => {
    if (campanhasValidas.length === 0) return;
    // Importar da campanha mais recente com radar_data
    const campanha = campanhasValidas[0];
    const radar = campanha.radar_data as RadarDimensao[];

    // Resolve as situações de trabalho: pares Setor+Função legados ou derivadas dos GHEs vinculados
    let situacoes: typeof campanha.situacoes_trabalho = [];
    try {
      situacoes = await resolverSituacoesTrabalho(campanha);
    } catch (e: any) {
      toast.error(`Erro ao carregar os GHEs da campanha: ${e.message}`);
      return;
    }

    if (!situacoes || situacoes.length === 0) {
      toast.error(
        "Esta campanha não possui GHEs nem situações de trabalho (Setor+Função) vinculados. " +
        "Edite a campanha e vincule pelo menos um GHE antes de exportar ao GRO (NR-17).",
        { duration: 6000 }
      );
      return;
    }

    await importarDaCampanha.mutateAsync({
      campanhaId: campanha.id,
      campanhaName: campanha.nome,
      dimensoes: radar.map(d => ({ subject: d.subject, value: d.value })),
      empresaId: null,
      isSipro: campanha.instrumento === 'sipro',
      situacoes,
    });
  };

  const idsEntrevistaFallback = campanhas.filter((c: any) =>isEntrevistaInstrumento(c.tipo_instrumento)).map(c => c.id);

  if (campanhasValidas.length === 0) {
    return (
      <div className="space-y-4">
        <ExplicacaoPGRGRO />
        {idsEntrevistaFallback.length > 0 && (
          <EvidenciasEntrevistaPanel campanhaIds={idsEntrevistaFallback} />
        )}
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-8 text-center gap-2">
            <ShieldAlert className="h-8 w-8 text-muted-foreground opacity-40" />
            <p className="text-sm font-medium">Inventário quantitativo não disponível</p>
            <p className="text-xs text-muted-foreground">
              Necessário ao menos uma campanha concluída (questionários exigem mín. {MINIMO_ANONIMATO} respostas; entrevistas guiadas exigem mín. 1).
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }


  const nivelColors: Record<string, string> = {
    critico: "border-l-red-500",
    alto: "border-l-orange-500",
    medio: "border-l-amber-500",
    baixo: "border-l-emerald-500",
    trivial: "border-l-slate-300",
  };

  const nivelBadgeColors: Record<string, string> = {
    critico: "bg-red-50 text-red-700 border-red-200",
    alto: "bg-orange-50 text-orange-700 border-orange-200",
    medio: "bg-amber-50 text-amber-700 border-amber-200",
    baixo: "bg-emerald-50 text-emerald-700 border-emerald-200",
    trivial: "bg-slate-50 text-slate-600 border-slate-200",
  };

  // IDs de campanhas com modalidade entrevista guiada (evidências qualitativas, fora do critério de radar)
  const campanhasEntrevistaIds = (filtroCampanha === "todos" ? campanhas : campanhas.filter(c => c.id === filtroCampanha))
    .filter((c: any) =>isEntrevistaInstrumento(c.tipo_instrumento))
    .map(c => c.id);


  return (
    <div className="space-y-4">
      <ExplicacaoPGRGRO />
      {campanhasEntrevistaIds.length > 0 && (
        <EvidenciasEntrevistaPanel campanhaIds={campanhasEntrevistaIds} />
      )}

      <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <FileText className="h-4 w-4 text-purple-600" />
              Inventário de Riscos Psicossociais
              <Badge variant="outline" className="text-[10px] font-mono bg-emerald-50 text-emerald-700 border-emerald-200 gap-1">
                <ShieldCheck className="h-2.5 w-2.5" />
                Dados Reais
              </Badge>
            </CardTitle>
            <CardDescription className="text-xs mt-0.5">
              NR-01 · ISO 45003 — {inventario.length} dimensões avaliadas · {campanhasValidas.length} campanha(s) consolidada(s)
              {" · "}Instrumento: <strong>{isSipro ? "SIPRO" : campanhasValidas[0]?.instrumento?.toUpperCase()}</strong>
            </CardDescription>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <div className="flex items-center gap-1.5 bg-muted/50 px-2 py-1 rounded-md border border-purple-100">
              <Filter className="h-3 w-3 text-purple-600/60" />
              <Select value={filtroCampanha} onValueChange={setFiltroCampanha}>
                <SelectTrigger className="w-[180px] h-7 text-[10px] border-none bg-transparent focus:ring-0">
                  <SelectValue placeholder="Filtrar Campanha" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todas as Campanhas</SelectItem>
                  {campanhasValidas.map(c => (
                    <SelectItem key={c.id} value={c.id}>{c.nome}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="flex items-center gap-1.5 bg-muted/50 px-2 py-1 rounded-md border border-cyan-100">
              <Users className="h-3 w-3 text-cyan-600/60" />
              <Select value={filtroGHE} onValueChange={setFiltroGHE} disabled={isLoadingGHE}>
                <SelectTrigger className="w-[200px] h-7 text-[10px] border-none bg-transparent focus:ring-0">
                  <SelectValue placeholder={isLoadingGHE ? "Carregando GHEs..." : "Filtrar GHE"} />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="todos">Todos os GHEs</SelectItem>
                  {ghesDisponiveis.length === 0 ? (
                    <div className="px-2 py-1.5 text-[10px] text-muted-foreground">
                      Nenhuma resposta com GHE vinculada
                    </div>
                  ) : (
                    ghesDisponiveis.map(g => (
                      <SelectItem key={g.ghe_id!} value={g.ghe_id!}>
                        {g.ghe_nome}
                        <span className="ml-2 text-[10px] text-muted-foreground">
                          · {g.count} resp.
                        </span>
                      </SelectItem>
                    ))
                  )}
                </SelectContent>
              </Select>
            </div>

            {criticos > 0 && (
              <Badge className="bg-red-600 text-white gap-1">
                <AlertTriangle className="h-3 w-3" />
                {criticos} crítico(s)
              </Badge>
            )}
            {altos > 0 && (
              <Badge className="bg-orange-500 text-white">{altos} alto(s)</Badge>
            )}
            {pendentesReavaliacao > 0 && (
              <Badge className="bg-violet-100 text-violet-700 border border-violet-300 gap-1">
                <RefreshCw className="h-3 w-3" />
                {pendentesReavaliacao} reavaliar
              </Badge>
            )}
            {/* GAP 4: Botão Relatório completo com metodologia */}
            <Button
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => setRelatorioOpen(true)}
              title="Gerar relatório estruturado com metodologia — NR-01 / ISO 45003"
            >
              <BookOpen className="h-3.5 w-3.5" />
              Relatório
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={handleImportarGRO}
              disabled={importarDaCampanha.isPending}
              title={semEscopoGRO ? "Campanha sem Setor+Função vinculado — adicione situações de trabalho para exportar ao GRO com conformidade NR-17" : "Enviar riscos ao inventário GRO"}
            >
              {importarDaCampanha.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Database className="h-3.5 w-3.5" />}
              Enviar ao GRO
              {semEscopoGRO && <AlertTriangle className="h-3 w-3 text-amber-500" />}
            </Button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* Banner do escopo (GHE selecionado) */}
        {gheSelecionado && (
          <div className={cn(
            "flex items-start gap-2 p-3 rounded-lg border text-xs",
            bloqueadoPorAnonimatoGHE
              ? "bg-amber-50/60 border-amber-200 text-amber-800"
              : "bg-cyan-50/60 border-cyan-200 text-cyan-800",
          )}>
            <Users className="h-4 w-4 shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold">
                Escopo: GHE <strong>{gheSelecionado.ghe_nome}</strong>
                <span className="ml-2 font-normal opacity-80">
                  · {gheSelecionado.count} respondente(s) · {gheSelecionado.campanhas} campanha(s)
                </span>
              </p>
              {bloqueadoPorAnonimatoGHE ? (
                <p className="mt-0.5">
                  Mínimo de {MINIMO_ANONIMATO} respondentes por GHE não atingido — inventário bloqueado
                  para preservar anonimato (ISO 45003). Aguarde mais respostas ou volte para "Todos os GHEs".
                </p>
              ) : (
                <p className="mt-0.5 opacity-80">
                  Os scores abaixo refletem apenas as respostas deste Grupo Homogêneo de Exposição.
                </p>
              )}
            </div>
          </div>
        )}

        {/* Matriz resumida */}
        <div className="grid grid-cols-5 gap-2">
          {[
            { label: "Crítico", count: criticos, bg: "bg-red-50 border-red-200", text: "text-red-700" },
            { label: "Alto", count: altos, bg: "bg-orange-50 border-orange-200", text: "text-orange-700" },
            { label: "Médio", count: medios, bg: "bg-amber-50 border-amber-200", text: "text-amber-700" },
            { label: "Baixo", count: baixos, bg: "bg-emerald-50 border-emerald-200", text: "text-emerald-700" },
            { label: "Trivial", count: triviais, bg: "bg-slate-50 border-slate-200", text: "text-slate-600" },
          ].map(({ label, count, bg, text }) => (
            <div key={label} className={cn("p-3 rounded-lg border text-center", bg)}>
              <p className={cn("text-xl font-bold", text)}>{count}</p>
              <p className={cn("text-xs font-medium", text)}>Risco {label}</p>
            </div>
          ))}
        </div>

        {/* GAP C — Alerta de privacidade por grupo (ISO 45003) */}
        {privacidadeGrupos && (campanhaAtual?.situacoes_trabalho?.length ?? 0) > 0 && (
          <PrivacidadeGrupoAlert resultado={privacidadeGrupos} />
        )}

        {/* Tabela */}
        <div className="rounded-lg border overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted/50">
                <TableHead className="text-xs">Dimensão / Fator</TableHead>
                <TableHead className="text-xs text-center">Score Real</TableHead>
                <TableHead className="text-xs">Base Normativa</TableHead>
                <TableHead className="text-xs text-center">Probabilidade</TableHead>
                <TableHead className="text-xs text-center">Severidade</TableHead>
                <TableHead className="text-xs text-center">Grau de Risco</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(expanded ? inventario : inventario.slice(0, 7)).map((item) => (
                <TableRow key={item.fatorId} className={cn("border-l-2", nivelColors[item.nivelKey])}>
                  <TableCell className="py-2 align-top max-w-[320px]">
                    <div className="flex items-center gap-1.5 mb-0.5 flex-wrap">
                      <p className="font-medium text-sm leading-tight">{item.fator}</p>
                      <Badge variant="outline" className="text-[9px] px-1 py-0 h-4 bg-purple-50 text-purple-700 border-purple-200">
                        {item.categoriaLabel}
                      </Badge>
                    </div>
                    <p className="text-[11px] text-muted-foreground leading-snug">{item.descricao}</p>
                    {item.dimensoes.length > 0 && !(item.dimensoes.length === 1 && item.dimensoes[0] === item.fator) && (
                      <div className="mt-1 flex flex-wrap gap-1">
                        <span className="text-[10px] text-muted-foreground/70 italic">
                          Dimensões do instrumento ({item.dimensoes.length}):
                        </span>
                        {item.dimensoes.map((d) => (
                          <Badge key={d} variant="secondary" className="text-[9px] px-1 py-0 h-4 font-normal">
                            {d}
                          </Badge>
                        ))}
                      </div>
                    )}
                  </TableCell>

                  <TableCell className="py-2 text-center">
                    <div className="flex flex-col items-center gap-0.5">
                      <span className="font-bold text-sm">{item.scoreReal}%</span>
                      <div className="w-16 bg-muted rounded-full h-1.5">
                        <div
                          className={cn("h-1.5 rounded-full", {
                            "bg-red-500": item.nivelKey === 'critico',
                            "bg-orange-500": item.nivelKey === 'alto',
                            "bg-amber-500": item.nivelKey === 'medio',
                            "bg-emerald-500": item.nivelKey === 'baixo',
                            "bg-slate-400": item.nivelKey === 'trivial',
                          })}
                          style={{ width: `${item.scoreReal}%` }}
                        />
                      </div>
                    </div>
                  </TableCell>
                  <TableCell className="py-2">
                    <Badge variant="outline" className="text-xs font-mono">{item.norma}</Badge>
                  </TableCell>
                  <TableCell className="py-2 text-center">
                    <span className="text-xs font-semibold">{item.probabilidadeLabel}</span>
                  </TableCell>
                  <TableCell className="py-2 text-center">
                    <span className="text-xs text-muted-foreground">{item.severidadeLabel}</span>
                  </TableCell>
                  <TableCell className="py-2 text-center">
                    <Badge className={cn("text-xs border", nivelBadgeColors[item.nivelKey])}>
                      {item.nivelLabel}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>

        {inventario.length > 7 && (
          <Button
            variant="ghost"
            size="sm"
            className="w-full gap-1 text-xs"
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? (
              <><ChevronUp className="h-3.5 w-3.5" /> Mostrar menos</>
            ) : (
              <><ChevronDown className="h-3.5 w-3.5" /> Ver todas as {inventario.length} dimensões</>
            )}
          </Button>
        )}

        {/* GAP 2: Alerta de ações obrigatórias para alto/crítico */}
        {(criticos > 0 || altos > 0) && (
          <div className="flex items-start gap-2 p-3 bg-orange-50/50 rounded-lg border border-orange-200 text-xs text-orange-800">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5 text-orange-500" />
            <p>
              <strong>{criticos + altos} dimensão(ões) não tolerável(is)</strong> identificada(s).
              Ações obrigatórias foram geradas automaticamente no Plano de Ação Global
              {criticos > 0 && ` (${criticos} crítica(s) — prazo 30 dias`}{altos > 0 && `, ${altos} alta(s) — prazo 60 dias`}{(criticos > 0 || altos > 0) && ")"}. NR-01 / ISO 45003.
            </p>
          </div>
        )}

        {/* GAP 4: Metodologia sempre visível no Inventário PGR */}
        <div className="rounded-lg border border-border/60 bg-muted/30 p-3 space-y-2">
          <p className="text-xs font-semibold text-foreground flex items-center gap-1.5">
            <BookOpen className="h-3.5 w-3.5 text-purple-600" />
            Metodologia — NR-01 / NR-17 / ISO 45003
          </p>
          <div className="grid gap-1.5 sm:grid-cols-2 text-xs text-muted-foreground">
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">1.</span>
              <span><strong>Coleta:</strong> Respostas agregadas (mín. 5 para questionários; s/ mínimo para entrevista guiada)</span>
            </div>
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">2.</span>
              <span><strong>Score real:</strong> Média ponderada de {campanhasValidas.length} campanha(s)</span>
            </div>
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">3.</span>
              <span><strong>Probabilidade × Severidade:</strong> Calculados via mapeamento normativo SIPRO/COPSOQ</span>
            </div>
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">4.</span>
              <span><strong>Nível GRO:</strong> Crítico / Alto / Médio / Baixo conforme matriz P×S (NR-01 Anexo I)</span>
            </div>
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">5.</span>
              <span><strong>Ações 5W2H:</strong> Geradas automaticamente para Crítico (30d) e Alto (60d)</span>
            </div>
            <div className="flex items-start gap-1.5">
              <span className="text-purple-600 font-bold shrink-0">6.</span>
              <span><strong>Auditabilidade:</strong> Use "Relatório" para exportar documento completo com rastreabilidade</span>
            </div>
          </div>
        </div>
      </CardContent>

      {/* GAP 4: Modal de relatório estruturado */}
      <RelatorioModal
        open={relatorioOpen}
        onClose={() => setRelatorioOpen(false)}
        campanhas={campanhasValidas}
        campanhaIdInicial={filtroCampanha === "todos" ? undefined : filtroCampanha}
      />
      </Card>
    </div>
  );
}
