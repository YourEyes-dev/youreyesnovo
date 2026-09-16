import { isEntrevistaInstrumento } from "@/types/psicossocial";
import { useEffect, useMemo, useState } from "react";
import {
  ClipboardList,
  Sparkles,
  FileDown,
  Loader2,
  Users,
  Plus,
  Trash2,
  Check,
  AlertTriangle,
  Lock,
  Pencil,
  Building2,
} from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { cn } from "@/lib/utils";

import type { CampanhaPsicossocial } from "@/types/psicossocial";
import { getMinimoRespostas } from "@/types/psicossocial";
import { SelecaoCampanhasModal } from "./SelecaoCampanhasModal";
import { usePsicossocialResultadosGHE } from "@/hooks/usePsicossocialResultadosGHE";
import { useSeveridadesCatalogo } from "@/hooks/useSeveridadesCatalogo";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { usePorteEmpresa } from "@/hooks/usePorteEmpresa";
import { usePapeisEmpresa } from "@/hooks/usePapeisEmpresa";
import { faixaEmTexto } from "@/lib/porteEmpresa";
import { referenciaDoFator } from "@/data/planoAcaoReferencia";
import {
  usePsicossocialPlanoAcao,
  type AcaoPlanoPsicossocial,
  type NovaAcaoPlano,
} from "@/hooks/usePsicossocialPlanoAcao";
import { calcularFatoresRisco, type FatorRiscoGHE } from "@/lib/fatoresRiscoPsicossocial";
import { NIVEL15_TOKENS, NIVEL15_ORDEM, type NivelGRO15 } from "@/lib/groPsicossocial15";
import { PRAZO_POR_NIVEL, NIVEIS_SINTESE, calcularAteQuando, linhaSintese } from "@/lib/planoAcaoPrazos";
import {
  gerarPdfPlanoAcao,
  type CabecalhoRelatorio,
  type GrupoPlano,
  type ContagemNiveis,
} from "@/lib/planoAcaoPdf";

const MINIMO_ANONIMATO = 5;

const COR_BADGE: Record<NivelGRO15, string> = {
  critico: "bg-red-100 text-red-800 border-red-200",
  alto: "bg-orange-100 text-orange-800 border-orange-200",
  medio: "bg-amber-100 text-amber-800 border-amber-200",
  baixo: "bg-blue-100 text-blue-800 border-blue-200",
  trivial: "bg-emerald-100 text-emerald-800 border-emerald-200",
};

interface OpcaoIA {
  o_que: string;
  quem?: string;
  onde?: string;
  por_que?: string;
  como?: string;
  quanto?: string;
}

interface SugestaoIA {
  fator_id: string;
  opcoes: OpcaoIA[];
}

interface PlanoAcaoPGRProps {
  campanhas: CampanhaPsicossocial[];
}

export function PlanoAcaoPGR({ campanhas }: PlanoAcaoPGRProps) {
  const { empresaAtiva, empresaAtivaId } = useEmpresaAtiva();
  const { data: porteInfo } = usePorteEmpresa();
  const { data: papeisEmpresa = [] } = usePapeisEmpresa();

  const [seletorAberto, setSeletorAberto] = useState(false);
  const [selecionadas, setSelecionadas] = useState<CampanhaPsicossocial[]>([]);
  const campanhaIds = useMemo(() => selecionadas.map(c => c.id), [selecionadas]);

  const [gerandoGhe, setGerandoGhe] = useState<string | null>(null);
  const [sugestoes, setSugestoes] = useState<Record<string, SugestaoIA[]>>({});
  const [marcadas, setMarcadas] = useState<Set<string>>(new Set());
  const [editando, setEditando] = useState<AcaoPlanoPsicossocial | null>(null);
  const [exportando, setExportando] = useState(false);

  const { resultadosPorGHE, isLoading: carregandoGHE } = usePsicossocialResultadosGHE(campanhaIds);
  const { data: severidades } = useSeveridadesCatalogo();
  const { acoes, criarLote, criandoLote, atualizar, excluir, limparGhe } =
    usePsicossocialPlanoAcao(campanhaIds);

  const isSipro = selecionadas.some(c => c.instrumento === "sipro");

  // Data inicial do plano = encerramento da campanha mais recente do recorte.
  // É a data em que o diagnóstico ficou disponível, que é o marco que a NR-01
  // usa para contar o prazo de tratamento.
  const dataInicialPlano = useMemo(() => {
    const fins = selecionadas
      .map(c => c.data_fim)
      .filter(Boolean)
      .sort() as string[];
    if (fins.length > 0) return new Date(`${fins[fins.length - 1]}T12:00:00`);
    return new Date();
  }, [selecionadas]);

  // Entrevista guiada individual é nominal (não anônima): a regra de anonimato
  // de 5 respostas não se aplica — o inventário e o plano valem a partir de 1.
  const minimoGrupo = useMemo(
    () =>
      selecionadas.length > 0 &&
      selecionadas.every(c => isEntrevistaInstrumento((c as any).tipo_instrumento))
        ? 1
        : MINIMO_ANONIMATO,
    [selecionadas],
  );

  // GHEs com respondentes suficientes para análise.
  // Quando o próprio GHE tem menos de 5 elegíveis (empresa pequena), o piso de
  // anonimato é inatingível por definição — nesse caso o mínimo passa a ser a
  // população elegível do grupo (nunca menor que 1).
  const ghes = useMemo(
    () =>
      resultadosPorGHE
        .filter(g => g.count > 0)
        .map(g => {
          const minGrupo = Math.max(1, Math.min(minimoGrupo, g.elegiveis || minimoGrupo));
          const liberado = g.count >= minGrupo;
          return {
            ...g,
            liberado,
            fatores: liberado
              ? calcularFatoresRisco(g.radar, { isSipro, severidades })
              : [],
          };
        }),
    [resultadosPorGHE, isSipro, severidades, minimoGrupo],
  );


  const acoesPorGhe = useMemo(() => {
    const mapa = new Map<string, AcaoPlanoPsicossocial[]>();
    for (const a of acoes) {
      const chave = a.ghe_id ?? "__org__";
      mapa.set(chave, [...(mapa.get(chave) ?? []), a]);
    }
    return mapa;
  }, [acoes]);

  const totalAcoes = acoes.length;

  // ── Síntese executiva: conta fatores por nível em todos os GHEs ───────────
  const contagem = useMemo((): ContagemNiveis => {
    const base: ContagemNiveis = { critico: 0, alto: 0, medio: 0, baixo: 0, trivial: 0 };
    for (const g of ghes) {
      for (const f of g.fatores) base[f.nivelKey] += 1;
    }
    return base;
  }, [ghes]);

  // ── IA: gerar opções de ação por GHE ─────────────────────────────────────
  const gerarSugestoes = async (ghe: (typeof ghes)[number]) => {
    if (ghe.fatores.length === 0) return;
    setGerandoGhe(ghe.ghe_id ?? "__org__");
    try {
      const { data, error } = await supabase.functions.invoke("ai-psicossocial-plano-acao", {
        body: {
          ghe_nome: ghe.ghe_nome,
          respondentes: ghe.count,
          composicao: ghe.composicaoSetores,
          instrumento: isSipro ? "SIPRO" : (selecionadas[0]?.instrumento ?? "COPSOQ").toUpperCase(),
          // Porte define o registro da acao: uma empresa de 8 pessoas nao
          // sustenta comite de saude mental, e uma de 800 nao se resolve com
          // conversa na reuniao de equipe.
          porte: porteInfo?.faixa.porte ?? null,
          porte_label: porteInfo?.faixa.label ?? null,
          porte_perfil: porteInfo?.faixa.perfil ?? null,
          colaboradores_cnpj: porteInfo?.colaboradores ?? null,
          // Papeis reais da empresa: a IA nao pode responsabilizar RH/SESMT/
          // ouvidoria que nao existem. Sem cargos cadastrados, cai em
          // "Responsavel legal".
          papeis_disponiveis: papeisEmpresa,
          fatores: ghe.fatores.map(f => ({
            fator_id: f.fatorId,
            fator: f.fator,
            nivel_gro: f.nivelKey,
            score: f.scoreRisco,
            dimensoes: f.dimensoes,
            norma: f.norma,
            // Acao modelo daquele fator no porte da empresa (SudoMed), usada
            // como base pela IA e como fallback se ela falhar.
            referencia: porteInfo ? referenciaDoFator(porteInfo.faixa.porte, f.fatorId) ?? null : null,
          })),
          opcoes_por_fator: 3,
        },
      });

      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      const chave = ghe.ghe_id ?? "__org__";
      setSugestoes(prev => ({ ...prev, [chave]: data?.sugestoes ?? [] }));
      const qtd = (data?.sugestoes ?? []).reduce(
        (acc: number, s: SugestaoIA) => acc + (s.opcoes?.length ?? 0),
        0,
      );
      toast.success(`${qtd} opções geradas para ${ghe.ghe_nome}`);
    } catch (e) {
      // Fallback determinístico: se a IA falhar (chave ausente, timeout, cota),
      // cai para a ação de referência do porte. Um plano com a ação padrão é
      // muito melhor do que um plano vazio — este é documento probatório de
      // NR-01, e a tela não pode ficar sem saída.
      const refs: SugestaoIA[] = porteInfo
        ? ghe.fatores
            .map(f => {
              const r = referenciaDoFator(porteInfo.faixa.porte, f.fatorId);
              if (!r) return null;
              return {
                fator_id: f.fatorId,
                opcoes: [
                  {
                    o_que: r.oQue,
                    quem: r.quem,
                    onde: r.onde,
                    por_que: r.porQue,
                    como: r.como,
                    quanto: "A definir pela empresa",
                  },
                ],
              } as SugestaoIA;
            })
            .filter((x): x is SugestaoIA => x !== null)
        : [];

      if (refs.length > 0) {
        setSugestoes(prev => ({ ...prev, [ghe.ghe_id ?? "__org__"]: refs }));
        toast.warning(
          `IA indisponível — carreguei as ações de referência para ${porteInfo?.faixa.label}.`,
          { description: "Revise e edite antes de incluir no plano." },
        );
      } else {
        toast.error(e instanceof Error ? e.message : "Falha ao gerar sugestões");
      }
    } finally {
      setGerandoGhe(null);
    }
  };

  const chaveOpcao = (gheKey: string, fatorId: string, idx: number) =>
    `${gheKey}::${fatorId}::${idx}`;

  const toggleOpcao = (chave: string) => {
    setMarcadas(prev => {
      const next = new Set(prev);
      if (next.has(chave)) next.delete(chave);
      else next.add(chave);
      return next;
    });
  };

  // ── Vincular as opções marcadas ao plano ─────────────────────────────────
  const vincularSelecionadas = async (ghe: (typeof ghes)[number]) => {
    const gheKey = ghe.ghe_id ?? "__org__";
    const lista = sugestoes[gheKey] ?? [];
    const novas: NovaAcaoPlano[] = [];

    lista.forEach(sug => {
      const fator = ghe.fatores.find(f => f.fatorId === sug.fator_id);
      if (!fator) return;
      sug.opcoes?.forEach((op, idx) => {
        if (!marcadas.has(chaveOpcao(gheKey, sug.fator_id, idx))) return;
        // "o_que" é NOT NULL no banco — sugestões da IA podem vir vazias.
        const oQue = (op.o_que ?? "").trim() || `Ação para: ${fator.fator}`;
        const ate = calcularAteQuando(dataInicialPlano, fator.nivelKey);
        novas.push({
          empresa_id: empresaAtivaId ?? null,
          campanha_ids: campanhaIds,
          ghe_id: ghe.ghe_id,
          ghe_nome: ghe.ghe_nome,
          fator_id: fator.fatorId,
          fator: fator.fator,
          nivel_gro: fator.nivelKey,
          o_que: oQue,
          quem: op.quem ?? null,
          onde: op.onde ?? null,
          por_que: op.por_que ?? null,
          data_inicial: dataInicialPlano.toISOString().slice(0, 10),
          ate_quando: ate ? ate.toISOString().slice(0, 10) : null,
          como: op.como ?? null,
          quanto: op.quanto ?? null,
          selecionada: true,
          origem: "ia",
        });
      });
    });

    if (novas.length === 0) {
      toast.info("Marque ao menos uma opção antes de vincular");
      return;
    }

    await criarLote(novas);
    toast.success(`${novas.length} ação(ões) vinculadas ao plano`);
    setMarcadas(prev => {
      const next = new Set(prev);
      for (const k of Array.from(next)) if (k.startsWith(`${gheKey}::`)) next.delete(k);
      return next;
    });
    setSugestoes(prev => ({ ...prev, [gheKey]: [] }));
  };

  // ── Ação manual ──────────────────────────────────────────────────────────
  const adicionarManual = async (ghe: (typeof ghes)[number], fator: FatorRiscoGHE) => {
    const ate = calcularAteQuando(dataInicialPlano, fator.nivelKey);
    await criarLote([
      {
        empresa_id: empresaAtivaId ?? null,
        campanha_ids: campanhaIds,
        ghe_id: ghe.ghe_id,
        ghe_nome: ghe.ghe_nome,
        fator_id: fator.fatorId,
        fator: fator.fator,
        nivel_gro: fator.nivelKey,
        o_que: "Descreva a ação",
        quem: null,
        onde: null,
        por_que: null,
        data_inicial: dataInicialPlano.toISOString().slice(0, 10),
        ate_quando: ate ? ate.toISOString().slice(0, 10) : null,
        como: null,
        quanto: null,
        selecionada: true,
        origem: "manual",
      },
    ]);
    toast.success("Ação em branco criada — edite os campos");
  };

  // ── PDF ──────────────────────────────────────────────────────────────────
  const exportarPdf = () => {
    if (totalAcoes === 0) {
      toast.error("Vincule ao menos uma ação antes de gerar o relatório");
      return;
    }
    setExportando(true);
    try {
      const totalRespondentes = selecionadas.reduce((a, c) => a + (c.total_respostas ?? 0), 0);
      const inicios = selecionadas.map(c => c.data_inicio).filter(Boolean).sort() as string[];
      const fins = selecionadas.map(c => c.data_fim).filter(Boolean).sort() as string[];
      const fmt = (d?: string) => (d ? new Date(`${d}T12:00:00`).toLocaleDateString("pt-BR") : "—");

      const ipsValidos = selecionadas
        .map(c => c.ips_score)
        .filter(v => typeof v === "number") as number[];
      const ipsGlobal = ipsValidos.length
        ? Math.round(ipsValidos.reduce((a, b) => a + b, 0) / ipsValidos.length)
        : null;

      const cabecalho: CabecalhoRelatorio = {
        campanha:
          selecionadas.length === 1
            ? selecionadas[0].nome
            : `${selecionadas.length} campanhas consolidadas`,
        instrumento: isSipro
          ? "SIPRO / IRP-S"
          : (selecionadas[0]?.instrumento ?? "COPSOQ").toUpperCase(),
        periodo: `${fmt(inicios[0])} a ${fmt(fins[fins.length - 1])}`,
        totalRespondentes,
        razaoSocial: empresaAtiva?.razao_social || empresaAtiva?.nome_fantasia || "—",
        cnpj: empresaAtiva?.cnpj || "—",
        ipsGlobal,
        porteCategoria: porteInfo?.faixa.categoria,
        colaboradoresCnpj: porteInfo?.colaboradores ?? null,
        setorPorte: porteInfo?.setorLabel,
      };

      const grupos: GrupoPlano[] = ghes
        .map(g => {
          const chave = g.ghe_id ?? "__org__";
          const lista = (acoesPorGhe.get(chave) ?? []).sort(
            (a, b) => (NIVEL15_ORDEM[a.nivel_gro] ?? 5) - (NIVEL15_ORDEM[b.nivel_gro] ?? 5),
          );
          return {
            gheId: g.ghe_id,
            gheNome: g.ghe_nome,
            setores: g.composicaoSetores,
            cargos: g.composicaoCargos,
            acoes: lista,
          };
        })
        .filter(g => g.acoes.length > 0);

      const doc = gerarPdfPlanoAcao(cabecalho, grupos, contagem);
      const nome = `Plano_Acao_Psicossocial_${new Date().toISOString().slice(0, 10)}.pdf`;
      doc.save(nome);
      toast.success("Relatório gerado");
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Falha ao gerar o PDF";
      toast.error(msg);
    } finally {
      setExportando(false);
    }
  };

  // ── Render ───────────────────────────────────────────────────────────────
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div>
              <CardTitle className="flex items-center gap-2 text-base">
                <ClipboardList className="h-5 w-5 text-primary" />
                Plano de Ação PGR
              </CardTitle>
              <CardDescription className="mt-1">
                Ações 5W2H por fator de risco e por GHE, derivadas do Inventário PGR.
                O nível de GRO vem do cruzamento probabilidade × severidade.
              </CardDescription>
              {porteInfo && (
                <div className="mt-2 flex items-center gap-2 flex-wrap text-xs">
                  <Badge variant="outline" className="gap-1.5 font-normal">
                    <Building2 className="h-3.5 w-3.5" />
                    {porteInfo.faixa.label}
                  </Badge>
                  <span className="text-muted-foreground">
                    {porteInfo.colaboradores} colaborador
                    {porteInfo.colaboradores === 1 ? "" : "es"} ativo
                    {porteInfo.colaboradores === 1 ? "" : "s"} no CNPJ ·{" "}
                    {porteInfo.setorLabel} ({faixaEmTexto(porteInfo.faixa)}) ·
                    critério IBGE/SEBRAE por pessoal ocupado
                  </span>
                </div>
              )}
            </div>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setSeletorAberto(true)} className="gap-2">
                <Users className="h-4 w-4" />
                {selecionadas.length === 0
                  ? "Selecionar campanhas"
                  : `${selecionadas.length} campanha(s)`}
              </Button>
              <Button
                onClick={exportarPdf}
                disabled={totalAcoes === 0 || exportando}
                className="gap-2"
              >
                {exportando ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <FileDown className="h-4 w-4" />
                )}
                Gerar relatório
              </Button>
            </div>
          </div>
        </CardHeader>

        {selecionadas.length > 0 && (
          <CardContent className="pt-0">
            <div className="rounded-lg border bg-muted/30 p-3 space-y-1.5">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Síntese executiva
              </p>
              {NIVEIS_SINTESE.map(nivel => (
                <p key={nivel} className="text-xs flex items-center gap-2">
                  <span
                    className={cn(
                      "inline-block h-2 w-2 rounded-full shrink-0",
                      nivel === "critico" && "bg-red-500",
                      nivel === "alto" && "bg-orange-500",
                      nivel === "medio" && "bg-amber-500",
                      nivel === "baixo" && "bg-blue-500",
                      nivel === "trivial" && "bg-emerald-500",
                    )}
                  />
                  {linhaSintese(nivel, contagem[nivel], NIVEL15_TOKENS[nivel])}
                </p>
              ))}
              <p className="text-[11px] text-muted-foreground pt-1">
                Prazos contados a partir de{" "}
                <strong>{dataInicialPlano.toLocaleDateString("pt-BR")}</strong>, encerramento da
                campanha mais recente do recorte.
              </p>
            </div>
          </CardContent>
        )}
      </Card>

      {selecionadas.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center gap-3 py-14 text-center">
            <ClipboardList className="h-9 w-9 text-muted-foreground" />
            <p className="text-sm font-medium">Nenhuma campanha selecionada</p>
            <p className="text-xs text-muted-foreground max-w-md">
              Escolha uma ou mais campanhas para carregar os fatores de risco por GHE e montar
              o plano de ação.
            </p>
            <Button onClick={() => setSeletorAberto(true)} className="mt-1 gap-2">
              <Users className="h-4 w-4" />
              Selecionar campanhas
            </Button>
          </CardContent>
        </Card>
      ) : carregandoGHE ? (
        <Card>
          <CardContent className="flex items-center justify-center gap-2 py-14">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            <span className="text-sm text-muted-foreground">Carregando GHEs…</span>
          </CardContent>
        </Card>
      ) : ghes.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center gap-3 py-14 text-center">
            <AlertTriangle className="h-8 w-8 text-amber-500" />
            <p className="text-sm font-medium">Nenhum GHE com respostas neste recorte</p>
            <p className="text-xs text-muted-foreground max-w-md">
              As respostas precisam ter GHE vinculado. Verifique o cadastro de GHE e o vínculo
              das campanhas selecionadas.
            </p>
          </CardContent>
        </Card>
      ) : (
        ghes.map(ghe => {
          const gheKey = ghe.ghe_id ?? "__org__";
          const listaSug = sugestoes[gheKey] ?? [];
          const acoesGhe = (acoesPorGhe.get(gheKey) ?? []).sort(
            (a, b) => (NIVEL15_ORDEM[a.nivel_gro] ?? 5) - (NIVEL15_ORDEM[b.nivel_gro] ?? 5),
          );
          const marcadasDoGhe = Array.from(marcadas).filter(k => k.startsWith(`${gheKey}::`)).length;

          return (
            <Card key={gheKey}>
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div className="min-w-0">
                    <CardTitle className="text-sm flex items-center gap-2">
                      {ghe.ghe_nome}
                      {ghe.ghe_codigo && (
                        <Badge variant="outline" className="text-[10px]">
                          {ghe.ghe_codigo}
                        </Badge>
                      )}
                    </CardTitle>
                    <CardDescription className="text-xs mt-0.5">
                      {ghe.count} respondente(s)
                      {ghe.composicaoSetores.length > 0 && ` · ${ghe.composicaoSetores.join(", ")}`}
                    </CardDescription>
                  </div>

                  {ghe.liberado && (
                    <div className="flex gap-2">
                      {acoesGhe.length > 0 && (
                        <Button
                          variant="ghost"
                          size="sm"
                          className="gap-1.5 text-xs"
                          onClick={async () => {
                            await limparGhe(ghe.ghe_id);
                            toast.success("Ações do GHE removidas");
                          }}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                          Limpar
                        </Button>
                      )}
                      <Button
                        size="sm"
                        variant="outline"
                        className="gap-1.5"
                        disabled={gerandoGhe === gheKey}
                        onClick={() => gerarSugestoes(ghe)}
                      >
                        {gerandoGhe === gheKey ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Sparkles className="h-3.5 w-3.5" />
                        )}
                        Sugerir ações com IA
                      </Button>
                    </div>
                  )}
                </div>
              </CardHeader>

              <CardContent className="space-y-4">
                {!ghe.liberado ? (
                  <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50/60 p-3 text-xs text-amber-800">
                    <Lock className="h-4 w-4 mt-0.5 shrink-0" />
                    <p>
                      Este GHE tem {ghe.count} resposta(s). São necessárias {minimoGrupo} para
                      liberar a análise sem risco de reidentificação (ISO 45003).
                    </p>
                  </div>
                ) : (
                  <>
                    {/* Fatores de risco do GHE */}
                    <div className="space-y-1.5">
                      {ghe.fatores.map(f => (
                        <div
                          key={f.fatorId}
                          className="flex items-center gap-3 rounded-lg border p-2.5"
                        >
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium truncate">{f.fator}</p>
                            <p className="text-[11px] text-muted-foreground truncate">
                              {f.dimensoes.join(" • ")} · {f.norma}
                            </p>
                          </div>
                          <span className="text-xs text-muted-foreground shrink-0">
                            risco {f.scoreRisco}%
                          </span>
                          <Badge
                            variant="outline"
                            className={cn("shrink-0 text-[10px]", COR_BADGE[f.nivelKey])}
                          >
                            {NIVEL15_TOKENS[f.nivelKey]}
                          </Badge>
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-7 gap-1 text-xs shrink-0"
                            onClick={() => adicionarManual(ghe, f)}
                            disabled={criandoLote}
                          >
                            <Plus className="h-3.5 w-3.5" />
                            Ação
                          </Button>
                        </div>
                      ))}
                    </div>

                    {/* Sugestões da IA, selecionáveis */}
                    {listaSug.length > 0 && (
                      <div className="rounded-lg border border-primary/30 bg-primary/5 p-3 space-y-3">
                        <div className="flex items-center justify-between gap-2">
                          <p className="text-xs font-semibold flex items-center gap-1.5">
                            <Sparkles className="h-3.5 w-3.5 text-primary" />
                            Opções sugeridas — marque as que quer vincular
                          </p>
                          <Button
                            size="sm"
                            className="h-7 gap-1.5 text-xs"
                            disabled={marcadasDoGhe === 0 || criandoLote}
                            onClick={() => vincularSelecionadas(ghe)}
                          >
                            <Check className="h-3.5 w-3.5" />
                            Vincular {marcadasDoGhe > 0 && `(${marcadasDoGhe})`}
                          </Button>
                        </div>

                        {listaSug.map(sug => {
                          const fator = ghe.fatores.find(f => f.fatorId === sug.fator_id);
                          if (!fator) return null;
                          return (
                            <div key={sug.fator_id} className="space-y-1.5">
                              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                                {fator.fator} · {NIVEL15_TOKENS[fator.nivelKey]}
                              </p>
                              {sug.opcoes?.map((op, idx) => {
                                const chave = chaveOpcao(gheKey, sug.fator_id, idx);
                                const marcada = marcadas.has(chave);
                                return (
                                  <div
                                    key={chave}
                                    role="button"
                                    tabIndex={0}
                                    onClick={() => toggleOpcao(chave)}
                                    onKeyDown={e => {
                                      if (e.key === "Enter" || e.key === " ") {
                                        e.preventDefault();
                                        toggleOpcao(chave);
                                      }
                                    }}
                                    className={cn(
                                      "flex items-start gap-2.5 rounded-md border bg-background p-2.5 cursor-pointer transition-colors",
                                      marcada ? "border-primary bg-primary/5" : "hover:bg-accent/40",
                                    )}
                                  >
                                    <Checkbox
                                      checked={marcada}
                                      className="mt-0.5 pointer-events-none"
                                      tabIndex={-1}
                                    />
                                    <div className="min-w-0 space-y-0.5">
                                      <p className="text-xs font-medium">{op.o_que}</p>
                                      <p className="text-[11px] text-muted-foreground">
                                        <strong>Quem:</strong> {op.quem ?? "—"} ·{" "}
                                        <strong>Onde:</strong> {op.onde ?? "—"} ·{" "}
                                        <strong>Quanto:</strong> {op.quanto ?? "—"}
                                      </p>
                                      {op.como && (
                                        <p className="text-[11px] text-muted-foreground">
                                          <strong>Como:</strong> {op.como}
                                        </p>
                                      )}
                                    </div>
                                  </div>
                                );
                              })}
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {/* Ações já vinculadas */}
                    {acoesGhe.length > 0 && (
                      <div className="space-y-1.5">
                        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                          Ações do plano ({acoesGhe.length})
                        </p>
                        {acoesGhe.map(a => (
                          <div key={a.id} className="rounded-lg border p-2.5 flex items-start gap-3">
                            <div className="flex-1 min-w-0 space-y-0.5">
                              <div className="flex items-center gap-2 flex-wrap">
                                <Badge
                                  variant="outline"
                                  className={cn("text-[10px]", COR_BADGE[a.nivel_gro])}
                                >
                                  {NIVEL15_TOKENS[a.nivel_gro]}
                                </Badge>
                                <span className="text-[11px] text-muted-foreground">{a.fator}</span>
                                {a.origem === "manual" && (
                                  <Badge variant="secondary" className="text-[10px]">
                                    manual
                                  </Badge>
                                )}
                              </div>
                              <p className="text-sm font-medium">{a.o_que}</p>
                              <p className="text-[11px] text-muted-foreground">
                                {a.quem ?? "—"} · {a.onde ?? "—"} ·{" "}
                                {a.data_inicial
                                  ? new Date(`${a.data_inicial}T12:00:00`).toLocaleDateString("pt-BR")
                                  : "—"}{" "}
                                →{" "}
                                {a.nivel_gro === "trivial"
                                  ? "sem prazo"
                                  : a.ate_quando
                                    ? new Date(`${a.ate_quando}T12:00:00`).toLocaleDateString("pt-BR")
                                    : "—"}
                              </p>
                            </div>
                            <div className="flex gap-1 shrink-0">
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-7 w-7 p-0"
                                onClick={() => setEditando(a)}
                              >
                                <Pencil className="h-3.5 w-3.5" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-7 w-7 p-0 text-destructive"
                                onClick={() => excluir(a.id)}
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
              </CardContent>
            </Card>
          );
        })
      )}

      <SelecaoCampanhasModal
        open={seletorAberto}
        onOpenChange={setSeletorAberto}
        campanhas={campanhas}
        preSelecionadas={campanhaIds}
        onConfirmar={sel => {
          setSelecionadas(sel);
          setSugestoes({});
          setMarcadas(new Set());
        }}
      />

      <EdicaoAcaoDialog
        acao={editando}
        onOpenChange={aberto => !aberto && setEditando(null)}
        onSalvar={(id, campos) => {
          atualizar({ id, campos });
          setEditando(null);
          toast.success("Ação atualizada");
        }}
      />
    </div>
  );
}

// ── Diálogo de edição 5W2H ──────────────────────────────────────────────────
function EdicaoAcaoDialog({
  acao,
  onOpenChange,
  onSalvar,
}: {
  acao: AcaoPlanoPsicossocial | null;
  onOpenChange: (aberto: boolean) => void;
  onSalvar: (id: string, campos: Partial<AcaoPlanoPsicossocial>) => void;
}) {
  const [form, setForm] = useState<Partial<AcaoPlanoPsicossocial>>({});

  // Recarrega o formulário sempre que abrir com outra ação.
  // useEffect e não useMemo: isto é efeito colateral, não valor derivado.
  const acaoId = acao?.id;
  useEffect(() => {
    if (acao) setForm({ ...acao });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [acaoId]);

  if (!acao) return null;

  const campo = (k: keyof AcaoPlanoPsicossocial) => (form[k] as string | null) ?? "";
  const set = (k: keyof AcaoPlanoPsicossocial, v: string) =>
    setForm(prev => ({ ...prev, [k]: v }));

  return (
    <Dialog open={!!acao} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] flex flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle>Editar ação</DialogTitle>
          <DialogDescription>
            {acao.fator} · {acao.ghe_nome} · nível {NIVEL15_TOKENS[acao.nivel_gro]} (
            {PRAZO_POR_NIVEL[acao.nivel_gro].rotuloPrazo})
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 min-h-0 max-h-[55vh] overflow-y-auto overscroll-contain scrollbar-visible space-y-3 px-1">
          <div>
            <Label className="text-xs">O quê? — ação a ser executada</Label>
            <Textarea
              value={campo("o_que")}
              onChange={e => set("o_que", e.target.value)}
              rows={2}
              className="mt-1"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <Label className="text-xs">Quem? — responsável</Label>
              <Input value={campo("quem")} onChange={e => set("quem", e.target.value)} className="mt-1" />
            </div>
            <div>
              <Label className="text-xs">Onde? — meio ou local</Label>
              <Input value={campo("onde")} onChange={e => set("onde", e.target.value)} className="mt-1" />
            </div>
          </div>

          <div>
            <Label className="text-xs">Por quê? — justificativa</Label>
            <Textarea
              value={campo("por_que")}
              onChange={e => set("por_que", e.target.value)}
              rows={2}
              className="mt-1"
            />
          </div>

          <div>
            <Label className="text-xs">Como? — método de execução</Label>
            <Textarea
              value={campo("como")}
              onChange={e => set("como", e.target.value)}
              rows={2}
              className="mt-1"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <Label className="text-xs">Data inicial</Label>
              <Input
                type="date"
                value={campo("data_inicial")}
                onChange={e => set("data_inicial", e.target.value)}
                className="mt-1"
              />
            </div>
            <div>
              <Label className="text-xs">Até quando</Label>
              <Input
                type="date"
                value={campo("ate_quando")}
                onChange={e => set("ate_quando", e.target.value)}
                className="mt-1"
              />
            </div>
            <div>
              <Label className="text-xs">Quanto? — recurso</Label>
              <Input
                value={campo("quanto")}
                onChange={e => set("quanto", e.target.value)}
                placeholder="Tempo interno, custo…"
                className="mt-1"
              />
            </div>
          </div>

          <p className="text-[11px] text-muted-foreground">
            O nível de GRO não é editável: ele vem do cruzamento probabilidade × severidade do
            Inventário de Risco e sustenta o documento como prova do monitoramento.
          </p>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancelar
          </Button>
          <Button
            onClick={() =>
              onSalvar(acao.id, {
                o_que: form.o_que ?? acao.o_que,
                quem: form.quem ?? null,
                onde: form.onde ?? null,
                por_que: form.por_que ?? null,
                como: form.como ?? null,
                quanto: form.quanto ?? null,
                data_inicial: form.data_inicial ?? null,
                ate_quando: form.ate_quando ?? null,
              })
            }
          >
            Salvar
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
