import { useMemo, useState } from "react";
import {
  BarChart3,
  Brain,
  TrendingUp,
  Users,
  ShieldCheck,
  Lock,
  Sparkles,
  Loader2,
  AlertTriangle,
  CheckCircle2,
  GitCompare,
  Wrench,
} from "lucide-react";
import { PrivacidadeGrupoAlert } from "./PrivacidadeGrupoAlert";
import {
  aplicarRegrasPrivacidade,
  estimarContagemPorGrupo,
} from "@/lib/psicossocial-privacy";
import { ExportarRelatorio } from "./ExportarRelatorio";
import { IntegracaoErgonomiaAEP } from "./IntegracaoErgonomiaAEP";
import { ContaprovaOrganizacional } from "./ContaprovaOrganizacional";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { AcaoGutPrioridade, AcaoTipo } from "@/types/planoAcao";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { usePsicossocial } from "@/hooks/usePsicossocial";
import { RadarPsicossocial } from "./RadarPsicossocial";
import { IPSGauge } from "./IPSGauge";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import {
  type CampanhaPsicossocial,
  getIPSColor,
  getIPSBgColor,
  getIRPSColor,
  getIRPSBgColor,
  getIRPSLabel,
  calcularIPSClassificacao,
  calcularIRPSClassificacao,
  type IPSClassificacao,
  type IRPSClassificacao,
} from "@/types/psicossocial";
import { cn } from "@/lib/utils";
import { useMinRespostasCampanha } from "@/hooks/usePsicossocialMinRespostas";

/** Rascunho 5W2H editável antes de efetivar a ação no Plano de Ação. */
interface RascunhoAcao {
  titulo: string;
  descricao: string;
  porque: string;
  onde: string;
  como: string;
  prioridade: AcaoGutPrioridade;
  tipo: AcaoTipo;
}

/**
 * Contraprova e Ergonomia cruzam dados de UMA campanha especifica (absenteismo,
 * AEP, situacoes de trabalho). Num recorte multi-campanha elas continuam
 * olhando so a campanha principal — isso precisa estar escrito na tela, senao
 * o usuario le como se fosse do conjunto todo.
 */
function labelPeriodoCurto(inicios: string[], fins: string[]): string {
  if (inicios.length === 0 && fins.length === 0) return "periodo nao informado";
  const fmt = (d?: string) => (d ? new Date(d).toLocaleDateString("pt-BR") : "—");
  const de = inicios.slice().sort()[0];
  const ate = fins.slice().sort().at(-1);
  return `${fmt(de)} a ${fmt(ate)}`;
}

function AvisoCampanhaPrincipal({ nome }: { nome: string }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50/60 p-3 text-xs text-amber-800">
      <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
      <p>
        Esta aba cruza dados de uma campanha por vez. O que aparece abaixo refere-se
        apenas a <strong>{nome}</strong>, e nao ao recorte agregado.
      </p>
    </div>
  );
}

interface ResultadosModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Uso legado / atalho de uma campanha só. */
  campanha?: CampanhaPsicossocial;
  /** Recorte multi-campanha. Tem precedência sobre `campanha`. */
  campanhas?: CampanhaPsicossocial[];
}

export function ResultadosModal({ open, onOpenChange, campanha, campanhas }: ResultadosModalProps) {
  // Normaliza as duas entradas em uma lista única.
  const selecionadas = useMemo<CampanhaPsicossocial[]>(
    () => (campanhas && campanhas.length > 0 ? campanhas : campanha ? [campanha] : []),
    [campanhas, campanha],
  );
  const isMulti = selecionadas.length > 1;
  const principal = selecionadas[0];

  // Campanha "de referência" para os campos que a tela lê (nome, instrumento,
  // GHE, situações de trabalho). No modo multi ela é sintética: herda o
  // instrumento (garantidamente homogêneo pelo seletor) e une GHEs e situações.
  const campanhaRef = useMemo<CampanhaPsicossocial>(() => {
    // Placeholder inerte: o early-return logo abaixo impede que este objeto
    // chegue a ser renderizado. Existe so para os derivados acima do return
    // (isSipro, temGHE, ...) nao estourarem quando a lista vem vazia.
    if (!principal) return { id: "", nome: "" } as CampanhaPsicossocial;
    if (!isMulti) return principal;
    // Periodo do recorte = da campanha mais antiga a mais recente. Sem isso o
    // PDF de relatorio sairia com o periodo de uma campanha so, o que invalida
    // o documento como prova do monitoramento (NR-01).
    const inicios = selecionadas.map(c => c.data_inicio).filter(Boolean) as string[];
    const fins = selecionadas.map(c => c.data_fim).filter(Boolean) as string[];
    return {
      ...principal,
      nome: `${selecionadas.length} campanhas — ${labelPeriodoCurto(inicios, fins)}`,
      data_inicio: inicios.length ? inicios.slice().sort()[0] : principal.data_inicio,
      data_fim: fins.length ? fins.slice().sort().at(-1) : principal.data_fim,
      ghe_ids: Array.from(new Set(selecionadas.flatMap(c => c.ghe_ids ?? []))),
      situacoes_trabalho: selecionadas.flatMap(c => c.situacoes_trabalho ?? []),
    } as CampanhaPsicossocial;
  }, [isMulti, principal, selecionadas]);

  const { useEstatisticasCampanhas } = usePsicossocial();
  const idsSelecionados = useMemo(() => selecionadas.map(c => c.id), [selecionadas]);
  const { data: stats, isLoading: loadingStats } = useEstatisticasCampanhas(idsSelecionados);
  const { minRespostas: MINIMO_ANONIMATO, configurado: minConfigurado } = useMinRespostasCampanha(campanhaRef);
  // Removemos a busca manual de respostas aqui pois as estatísticas já trazem o IPS e radar agregados,
  // e as respostas individuais são sensíveis ao anonimato. Se precisarmos de detalhes por dimensão,
  // eles devem vir de 'stats'.
  const loadingRespostas = false;
  const respostas: any[] = [];
  const { user, profile } = useAuthContext();
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();

  const [analisandoIA, setAnalisandoIA] = useState(false);
  const [analiseIA, setAnaliseIA] = useState<string | null>(null);
  const [criandoAcao, setCriandoAcao] = useState(false);
  // Rascunho editável da ação 5W2H sugerida pela IA. Enquanto != null, o modal
  // de revisão está aberto; a gravação só ocorre ao confirmar (handleConfirmarAcao).
  const [rascunhoAcao, setRascunhoAcao] = useState<RascunhoAcao | null>(null);
  const [salvandoAcao, setSalvandoAcao] = useState(false);

  const isLoading = loadingStats || loadingRespostas;

  const isSipro = campanhaRef.instrumento === 'sipro';
  // Quando a campanha está vinculada a GHE, a base da taxa é o GHE (não o setor).
  const temGHE = (campanhaRef.ghe_ids?.length ?? 0) > 0;
  const baseLabel = temGHE ? "GHE" : "Setor";
  const baseLabelInline = temGHE ? "GHE" : "setor";

  // IPS e classificação a partir das estatísticas reais
  const ips = stats?.ips;
  const ipsClass = ips !== undefined
    ? isSipro
      ? calcularIRPSClassificacao(ips) as unknown as IPSClassificacao
      : calcularIPSClassificacao(ips)
    : null;

  // Label e cor do score principal conforme instrumento
  const scoreLabel = isSipro ? 'IRP-S — Índice de Risco Psicossocial' : 'IPS — Índice Psicossocial';
  const scoreDescricao = isSipro
    ? 'Score 0–100: quanto maior, maior o risco organizacional'
    : 'Score 0–100: quanto maior, mais saudável o ambiente';

  // ── GAP A+B+C: Proteção de privacidade por grupo (ISO 45003) ───────────────
  // Verifica se há situações de trabalho segmentadas e aplica regras de mínimo.
  const privacidadeGrupos = useMemo(() => {
    const situacoes = campanhaRef.situacoes_trabalho ?? [];
    const totalRespondentes = stats?.concluidos ?? 0;
    if (situacoes.length === 0) return null; // sem segmentação — usa proteção global
    const contagem = estimarContagemPorGrupo(totalRespondentes, situacoes);
    return aplicarRegrasPrivacidade(situacoes, contagem, totalRespondentes);
  }, [campanhaRef.situacoes_trabalho, stats?.concluidos]);

  // Dimensões por resposta → agregar média por dimensão
  // Para SIPRO (IRP-S): maior score = maior risco → críticas têm score ALTO, pontos fortes têm score BAIXO
  // Para demais: menor score = pior → críticas têm score BAIXO, pontos fortes têm score ALTO
  const dimensoesAgregadas = (() => {
    if (!stats?.anonimato_garantido || !stats?.radar || stats.radar.length === 0) return [];
    
    // Usamos os dados do radar que já estão agregados nas estatísticas
    const arr = stats.radar.map(d => ({
      bloco: d.subject,
      media: d.value,
    }));

    // SIPRO: ordenar do mais crítico (maior score) para o menos
    // Outros: ordenar do mais crítico (menor score) para o melhor
    return isSipro
      ? arr.sort((a, b) => b.media - a.media)
      : arr.sort((a, b) => a.media - b.media);
  })();

  // Para SIPRO: crítico = score alto (≥50); ponto forte = score baixo (≤24)
  // Para demais: crítico = score baixo (<65); ponto forte = score alto (≥65)
  const limiarCritico = isSipro ? 50 : 65;
  const limiarForte = isSipro ? 25 : 65;
  const isCritico = (media: number) => isSipro ? media >= limiarCritico : media < limiarCritico;
  const isForte = (media: number) => isSipro ? media <= limiarForte : media >= limiarForte;

  const getNivelScore = (score: number): { label: string; cls: IPSClassificacao } => {
    // Para SIPRO usa lógica invertida (IRP-S): alto = ruim
    // Faixas espelhadas do IPS: 0-20 saudável, 21-35 estável, 36-50 atenção, 51-65 risco, 66-100 crítico
    const cls = isSipro
      ? (score >= 66 ? 'critico' : score >= 51 ? 'risco' : score >= 36 ? 'atencao' : score >= 21 ? 'estavel' : 'saudavel') as IPSClassificacao
      : calcularIPSClassificacao(score);
    const labels: Record<IPSClassificacao, string> = {
      saudavel: 'Saudável',
      estavel: 'Estável',
      atencao: 'Atenção',
      risco: 'Risco',
      critico: 'Crítico',
    };
    return { label: labels[cls], cls };
  };

  const handleAnalisarIA = async () => {
    if (!stats || !ips) return;
    setAnalisandoIA(true);
    setAnaliseIA(null);
    try {
      const contexto = {
        campanha: campanhaRef.nome,
        instrumento: campanhaRef.instrumento || 'copsoq',
        ips,
        classificacao: ipsClass,
        total_respostas: stats.concluidos,
        taxa_participacao: stats.taxa_participacao,
        dimensoes_criticas: dimensoesAgregadas.filter(d => isSipro ? d.media >= 50 : d.media < 50).map(d => d.bloco),
        dimensoes_atencao: dimensoesAgregadas.filter(d => isSipro ? (d.media >= 36 && d.media < 50) : (d.media >= 50 && d.media < 65)).map(d => d.bloco),
        dimensoes_saudaveis: dimensoesAgregadas.filter(d => isSipro ? d.media <= 20 : d.media >= 80).map(d => d.bloco),
      };

      const { data, error } = await supabase.functions.invoke('ai-psicossocial-analise', {
        body: { contexto },
      });

      if (error) throw error;
      setAnaliseIA(data?.analise || "Análise não disponível.");
    } catch (err) {
      console.error(err);
      toast.error("Erro ao gerar análise IA. Verifique a configuração da edge function.");
    } finally {
      setAnalisandoIA(false);
    }
  };

  // Passo 1: gera o rascunho 5W2H com a IA e abre o modal de revisão.
  // NÃO grava nada — a criação só acontece no handleConfirmarAcao.
  const handleGerarRascunho = async () => {
    if (!tenantId || !ips || !ipsClass) return;
    setCriandoAcao(true);
    try {
      const { data, error } = await supabase.functions.invoke('ai-psicossocial-analise', {
        body: {
          contexto: {
            campanha: campanhaRef.nome,
            instrumento: campanhaRef.instrumento || 'copsoq',
            ips,
            classificacao: ipsClass,
            dimensoes_criticas: dimensoesAgregadas.filter(d => isSipro ? d.media >= 50 : d.media < 50).map(d => d.bloco),
          },
          modo: 'plano_acao',
        },
      });
      if (error) throw error;

      const sugestao = data?.sugestao_acao;
      setRascunhoAcao({
        titulo: sugestao?.titulo || `Ação Psicossocial — ${campanhaRef.nome}`,
        descricao: sugestao?.descricao || `Ação gerada a partir da campanha psicossocial com IPS ${ips}.`,
        porque: sugestao?.porque || `IPS ${ips} — Classificação: ${ipsClass}`,
        onde: sugestao?.onde || 'Organização',
        como: sugestao?.como || 'Implementar ações de melhoria psicossocial conforme diagnóstico.',
        prioridade: (ips < 35 ? 'imediato' : ips < 50 ? 'urgente' : 'medio'),
        tipo: 'preventiva',
      });
    } catch (err) {
      console.error(err);
      toast.error("Erro ao gerar rascunho da ação: " + (err instanceof Error ? err.message : ""));
    } finally {
      setCriandoAcao(false);
    }
  };

  // Passo 2: grava a ação já revisada/editada pelo gestor no Plano de Ação.
  const handleConfirmarAcao = async () => {
    if (!rascunhoAcao || !tenantId) return;
    if (!rascunhoAcao.titulo.trim()) {
      toast.error("Informe um título para a ação.");
      return;
    }
    setSalvandoAcao(true);
    try {
      const { error: errAcao } = await supabase.from('plano_acoes').insert({
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        titulo: rascunhoAcao.titulo.trim(),
        descricao: rascunhoAcao.descricao,
        porque: rascunhoAcao.porque,
        onde: rascunhoAcao.onde,
        como: rascunhoAcao.como,
        tipo: rascunhoAcao.tipo,
        prioridade: rascunhoAcao.prioridade,
        origem_modulo: 'psicossocial' as const,
        origem_descricao: `Campanha Psicossocial: ${campanhaRef.nome}`,
        criado_por: user?.id,
        criado_por_nome: profile?.nome_completo || 'Sistema',
        exige_evidencia: false,
        codigo: '',
        progresso: 0,
        status: 'pendente' as const,
        tempo_gasto_minutos: 0,
      });
      if (errAcao) throw errAcao;
      toast.success("Ação criada no Plano de Ação!");
      setRascunhoAcao(null);
    } catch (err) {
      console.error(err);
      toast.error("Erro ao criar ação: " + (err instanceof Error ? err.message : ""));
    } finally {
      setSalvandoAcao(false);
    }
  };

  if (selecionadas.length === 0) return null;

  return (
    <>
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <BarChart3 className="h-5 w-5 text-purple-600" />
            Resultados — {campanhaRef.nome}
          </DialogTitle>
          <DialogDescription>
            {stats?.concluidos || 0} respostas de {stats?.total_convites || 0} convites enviados
            {isMulti && (
              <span className="block mt-1 text-xs">
                Recorte agregado · IPS recalculado sobre as respostas de todas as campanhas
                (ponderado, não é média das médias).
              </span>
            )}
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex items-center justify-center h-64">
            <Loader2 className="h-8 w-8 animate-spin text-purple-600" />
          </div>
        ) : stats?.concluidos === 0 ? (
          <div className="text-center py-12">
            <Users className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
            <h3 className="text-lg font-semibold mb-2">Nenhuma resposta ainda</h3>
            <p className="text-muted-foreground">Aguardando colaboradores responderem o questionário</p>
          </div>
        ) : (
          <Tabs defaultValue="visao_geral" className="w-full">
          <TabsList className={cn("grid w-full", isMulti ? "grid-cols-7" : "grid-cols-6")}>
              <TabsTrigger value="visao_geral">Visão Geral</TabsTrigger>
              {isMulti && (
                <TabsTrigger value="comparativo">
                  <GitCompare className="h-3.5 w-3.5 mr-1" />
                  Comparativo
                </TabsTrigger>
              )}
              <TabsTrigger value="dimensoes">Por Dimensão</TabsTrigger>
              <TabsTrigger value="ia">
                <Sparkles className="h-3.5 w-3.5 mr-1 text-purple-500" />
                IA
              </TabsTrigger>
              <TabsTrigger value="contraprova">
                <GitCompare className="h-3.5 w-3.5 mr-1" />
                Contraprova
              </TabsTrigger>
              <TabsTrigger value="ergonomia">
                <Wrench className="h-3.5 w-3.5 mr-1" />
                Ergonomia
              </TabsTrigger>
              <TabsTrigger value="participacao">Participação</TabsTrigger>
            </TabsList>

            {/* ── Tab: Comparativo (só no recorte multi-campanha) ── */}
            {isMulti && (
              <TabsContent value="comparativo" className="space-y-4 mt-4">
                <Card>
                  <CardHeader className="pb-3">
                    <CardTitle className="text-sm">Campanha a campanha</CardTitle>
                    <CardDescription className="text-xs">
                      Para monitoramento contínuo (NR-01 / ISO 45003), a evolução entre campanhas
                      costuma dizer mais que o número agregado. Campanhas abaixo do mínimo de
                      respostas aparecem sem score.
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-2">
                    {(stats?.por_campanha ?? []).map(c => {
                      const cls = c.ips !== undefined
                        ? (isSipro
                            ? (calcularIRPSClassificacao(c.ips) as unknown as IPSClassificacao)
                            : calcularIPSClassificacao(c.ips))
                        : null;
                      return (
                        <div
                          key={c.campanha_id}
                          className="flex items-center gap-3 rounded-lg border p-3"
                        >
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium truncate">{c.nome}</p>
                            <p className="text-xs text-muted-foreground">
                              {c.concluidos} de {c.total} · adesão {c.taxa_participacao.toFixed(0)}%
                              {c.data_inicio && (
                                <> · desde {new Date(c.data_inicio).toLocaleDateString("pt-BR")}</>
                              )}
                            </p>
                          </div>
                          {c.ips !== undefined && cls ? (
                            <div className="text-right shrink-0">
                              <p className={cn("text-xl font-bold leading-none", getIPSColor(cls))}>
                                {c.ips}
                              </p>
                              <p className="text-[10px] text-muted-foreground mt-0.5">
                                {isSipro ? "IRP-S" : "IPS"}
                              </p>
                            </div>
                          ) : (
                            <Badge variant="outline" className="shrink-0 gap-1">
                              <Lock className="h-3 w-3" />
                              Bloqueado
                            </Badge>
                          )}
                        </div>
                      );
                    })}
                  </CardContent>
                </Card>

                {stats && !stats.instrumento_homogeneo && (
                  <Card className="border-amber-200 bg-amber-50/40">
                    <CardContent className="pt-4 flex items-start gap-3">
                      <AlertTriangle className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
                      <p className="text-sm text-amber-800">
                        O recorte mistura instrumentos diferentes. As dimensões não são
                        equivalentes e o score agregado não deve ser usado como prova documental.
                        Use a comparação acima, campanha a campanha.
                      </p>
                    </CardContent>
                  </Card>
                )}
              </TabsContent>
            )}

            {/* ── Tab: Visão Geral ── */}
            <TabsContent value="visao_geral" className="space-y-4 mt-4">
              {!stats?.anonimato_garantido ? (
                <Card className="border-amber-200 bg-amber-50/40">
                  <CardContent className="pt-4">
                    <div className="flex items-center gap-3">
                      <Lock className="h-6 w-6 text-amber-600" />
                      <div>
                        <p className="font-semibold text-amber-800">Número insuficiente de respostas para garantir anonimato estatístico</p>
                        <p className="text-sm text-amber-700">
                          Mínimo necessário: {MINIMO_ANONIMATO} respostas. Atual: {stats?.concluidos || 0}.
                        </p>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ) : (
                <>
                  {/* GAP C — badge compacto de privacidade por grupo na visão geral */}
                  {privacidadeGrupos && (
                    <PrivacidadeGrupoAlert resultado={privacidadeGrupos} compact />
                  )}

                  {/* IPS principal */}
                  <div className="grid gap-4 md:grid-cols-2">
                    <Card className="border-purple-200 bg-gradient-to-br from-purple-50/50 to-background">
                      <CardHeader className="pb-2">
                      <CardTitle className="text-sm text-muted-foreground flex items-center gap-2">
                          <Brain className="h-4 w-4 text-purple-600" />
                          {scoreLabel}
                        </CardTitle>
                      </CardHeader>
                      <CardContent className="flex flex-col items-center">
                        {ips !== undefined && ipsClass ? (
                          <>
                            <IPSGauge score={ips} classificacao={ipsClass} size="lg" />
                            <p className="text-xs text-muted-foreground text-center mt-2">{scoreDescricao}</p>
                          </>
                        ) : (
                          <p className="text-muted-foreground text-sm py-6">Score indisponível</p>
                        )}
                      </CardContent>
                    </Card>

                    {/* Radar */}
                    <Card>
                      <CardHeader className="pb-2">
                        <CardTitle className="text-sm text-muted-foreground">Radar Psicossocial</CardTitle>
                        <CardDescription className="text-xs">Score por dimensão (0-100)</CardDescription>
                      </CardHeader>
                      <CardContent>
                        {stats?.radar && stats.radar.length > 0 ? (
                          <RadarPsicossocial dados={stats.radar} />
                        ) : (
                          <div className="flex items-center justify-center h-48 text-muted-foreground text-sm">
                            Dados insuficientes para o radar
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  </div>

                  {/* Destaques: top piores e melhores */}
                  {dimensoesAgregadas.length > 0 && (
                    <div className="grid gap-3 sm:grid-cols-2">
                      <Card className="border-red-100">
                        <CardHeader className="pb-2">
                          <CardTitle className="text-sm flex items-center gap-2 text-red-600">
                            <AlertTriangle className="h-4 w-4" />
                            {isSipro ? 'Maiores Riscos (IRP-S)' : 'Dimensões Críticas'}
                          </CardTitle>
                        </CardHeader>
                        <CardContent className="space-y-2">
                          {dimensoesAgregadas.filter(d => isCritico(d.media)).slice(0, 4).map(d => {
                            const nivel = getNivelScore(d.media);
                            return (
                              <div key={d.bloco} className="flex items-center justify-between">
                                <span className="text-sm truncate max-w-[65%]">{d.bloco}</span>
                                <div className="flex items-center gap-2">
                                  <Progress value={d.media} className="w-16 h-1.5" />
                                  <span className={cn("text-xs font-semibold w-8 text-right", getIPSColor(nivel.cls))}>{d.media}</span>
                                </div>
                              </div>
                            );
                          })}
                          {dimensoesAgregadas.filter(d => isCritico(d.media)).length === 0 && (
                            <p className="text-sm text-muted-foreground">
                              {isSipro ? 'Nenhuma dimensão em risco 🎉' : 'Nenhuma dimensão crítica 🎉'}
                            </p>
                          )}
                        </CardContent>
                      </Card>

                      <Card className="border-emerald-100">
                        <CardHeader className="pb-2">
                          <CardTitle className="text-sm flex items-center gap-2 text-emerald-600">
                            <CheckCircle2 className="h-4 w-4" />
                            {isSipro ? 'Condições Favoráveis (IRP-S)' : 'Pontos Fortes'}
                          </CardTitle>
                        </CardHeader>
                        <CardContent className="space-y-2">
                          {[...dimensoesAgregadas].reverse().filter(d => isForte(d.media)).slice(0, 4).map(d => {
                            const nivel = getNivelScore(d.media);
                            return (
                              <div key={d.bloco} className="flex items-center justify-between">
                                <span className="text-sm truncate max-w-[65%]">{d.bloco}</span>
                                <div className="flex items-center gap-2">
                                  <Progress value={d.media} className="w-16 h-1.5" />
                                  <span className={cn("text-xs font-semibold w-8 text-right", getIPSColor(nivel.cls))}>{d.media}</span>
                                </div>
                              </div>
                            );
                          })}
                          {[...dimensoesAgregadas].reverse().filter(d => isForte(d.media)).length === 0 && (
                            <p className="text-sm text-muted-foreground">
                              {isSipro ? 'Sem dimensões favoráveis ainda' : 'Sem dimensões saudáveis ainda'}
                            </p>
                          )}
                        </CardContent>
                      </Card>
                    </div>
                  )}
                </>
              )}
            </TabsContent>

            {/* ── Tab: Por Dimensão ── */}
            <TabsContent value="dimensoes" className="mt-4">
              {!stats?.anonimato_garantido ? (
                <Card className="border-amber-200 bg-amber-50/40">
                  <CardContent className="pt-4 flex items-center gap-3">
                    <Lock className="h-5 w-5 text-amber-600" />
                    <p className="text-sm text-amber-800 font-medium">Número insuficiente de respostas para garantir anonimato estatístico</p>
                  </CardContent>
                </Card>
              ) : (
                <div className="space-y-3">
                  {/* GAP C — Alerta de privacidade por grupo (ISO 45003) */}
                  {privacidadeGrupos && (
                    <PrivacidadeGrupoAlert resultado={privacidadeGrupos} />
                  )}
                  {dimensoesAgregadas.length === 0 ? (
                    <p className="text-sm text-muted-foreground text-center py-8">Sem dados de dimensões disponíveis.</p>
                  ) : (
                    dimensoesAgregadas.map(d => {
                      const nivel = getNivelScore(d.media);
                      return (
                        <div key={d.bloco} className={cn("flex items-center justify-between p-3 rounded-lg border", getIPSBgColor(nivel.cls) + "/30")}>
                          <div className="flex items-center gap-3 flex-1 min-w-0">
                            <div className={cn("w-2 h-8 rounded-full shrink-0", {
                              'bg-emerald-500': nivel.cls === 'saudavel',
                              'bg-blue-500': nivel.cls === 'estavel',
                              'bg-amber-500': nivel.cls === 'atencao',
                              'bg-orange-500': nivel.cls === 'risco',
                              'bg-red-500': nivel.cls === 'critico',
                            })} />
                            <p className="font-medium text-sm truncate">{d.bloco}</p>
                          </div>
                          <div className="flex items-center gap-3 shrink-0">
                            <Progress value={d.media} className="w-28 h-2" />
                            <span className="text-sm font-bold w-8 text-right">{d.media}</span>
                            <Badge variant="outline" className={cn("text-xs min-w-[70px] justify-center", getIPSColor(nivel.cls))}>
                              {nivel.label}
                            </Badge>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              )}
            </TabsContent>

            {/* ── Tab: Análise IA ── */}
            <TabsContent value="ia" className="mt-4 space-y-4">
              {!stats?.anonimato_garantido ? (
                <Card className="border-amber-200 bg-amber-50/40">
                  <CardContent className="pt-4 flex items-center gap-3">
                    <Lock className="h-5 w-5 text-amber-600" />
                    <p className="text-sm text-amber-800 font-medium">Número insuficiente de respostas para garantir anonimato estatístico</p>
                  </CardContent>
                </Card>
              ) : (
                <>
                  <Card className="border-purple-200 bg-purple-50/20">
                    <CardHeader className="pb-3">
                      <CardTitle className="text-sm flex items-center gap-2">
                        <Sparkles className="h-4 w-4 text-purple-600" />
                        Interpretação IA dos Resultados
                      </CardTitle>
                      <CardDescription className="text-xs">
                        A IA analisa o IPS, dimensões críticas e padrões para gerar recomendações organizacionais
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-3">
                      {analiseIA ? (
                        <div className="text-sm leading-relaxed whitespace-pre-wrap text-foreground bg-background rounded-lg p-4 border">
                          {analiseIA}
                        </div>
                      ) : (
                        <div className="text-center py-6 text-muted-foreground">
                          <Brain className="h-10 w-10 mx-auto mb-2 opacity-40" />
                          <p className="text-sm">Clique em "Analisar com IA" para gerar a interpretação dos resultados</p>
                        </div>
                      )}
                      <Button
                        onClick={handleAnalisarIA}
                        disabled={analisandoIA || !ips}
                        className="w-full gap-2 bg-gradient-to-r from-violet-600 to-purple-600 hover:from-violet-700 hover:to-purple-700"
                      >
                        {analisandoIA ? (
                          <><Loader2 className="h-4 w-4 animate-spin" /> Analisando...</>
                        ) : (
                          <><Sparkles className="h-4 w-4" /> {analiseIA ? 'Reanalisar com IA' : 'Analisar com IA'}</>
                        )}
                      </Button>
                    </CardContent>
                  </Card>

                  {/* Criar Plano de Ação */}
                  {ips !== undefined && ips < 80 && (
                    <Card className="border-amber-200 bg-amber-50/20">
                      <CardHeader className="pb-3">
                        <CardTitle className="text-sm flex items-center gap-2">
                          <TrendingUp className="h-4 w-4 text-amber-600" />
                          Plano de Ação Preventivo
                        </CardTitle>
                        <CardDescription className="text-xs">
                          A IA monta um rascunho 5W2H a partir deste diagnóstico. Você revisa e edita antes de criar a ação no Plano de Ação.
                        </CardDescription>
                      </CardHeader>
                      <CardContent>
                        <Button
                          onClick={handleGerarRascunho}
                          disabled={criandoAcao}
                          variant="outline"
                          className="w-full gap-2 border-amber-300 hover:bg-amber-50"
                        >
                          {criandoAcao ? (
                            <><Loader2 className="h-4 w-4 animate-spin" /> Gerando rascunho...</>
                          ) : (
                            <><Sparkles className="h-4 w-4 text-amber-600" /> Revisar e criar ação</>
                          )}
                        </Button>
                        <p className="text-xs text-muted-foreground mt-2 text-center">
                          Acessível em Planos & Desenvolvimento → Plano de Ação
                        </p>
                      </CardContent>
                    </Card>
                  )}
                </>
              )}
            </TabsContent>

            {/* ── Tab: Contraprova Organizacional ── */}
            <TabsContent value="contraprova" className="mt-4 space-y-3">
              {isMulti && <AvisoCampanhaPrincipal nome={principal.nome} />}
              <ContaprovaOrganizacional campanha={campanhaRef} ips={ips} />
            </TabsContent>

            {/* ── Tab: Ergonomia / AEP ── */}
            <TabsContent value="ergonomia" className="mt-4 space-y-3">
              {isMulti && <AvisoCampanhaPrincipal nome={principal.nome} />}
              {/* GAP 3: Banner de recomendação de AET quando IPS < 65 ou múltiplos críticos */}
              {stats?.anonimato_garantido && ips !== undefined && (
                (() => {
                  const criticos = dimensoesAgregadas.filter(d => isCritico(d.media));
                  const isRiscoRelevante = isSipro ? ips >= 50 : ips < 65;
                  const multiplosRiscos = criticos.length >= 2;
                  const riscoUrgente = isSipro ? ips >= 75 : ips < 35;

                  if (!isRiscoRelevante && !multiplosRiscos) return null;

                  return (
                    <div className={`flex items-start gap-3 p-4 rounded-xl border-2 ${
                      riscoUrgente
                        ? 'border-destructive/50 bg-destructive/5'
                        : 'border-orange-200 bg-orange-50/50'
                    }`}>
                      <div className={`p-2 rounded-lg shrink-0 ${riscoUrgente ? 'bg-destructive/10' : 'bg-orange-100'}`}>
                        <span className="text-lg">{riscoUrgente ? '🚨' : '⚠️'}</span>
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className={`font-semibold text-sm ${riscoUrgente ? 'text-destructive' : 'text-orange-800'}`}>
                          {riscoUrgente
                            ? 'AET Obrigatória — Risco Crítico Identificado (NR-17 §17.5)'
                            : `AET Recomendada — ${criticos.length > 0 ? `${criticos.length} dimensão(ões) em risco` : 'IPS em nível de atenção'}`
                          }
                        </p>
                        <p className={`text-xs mt-0.5 ${riscoUrgente ? 'text-destructive/80' : 'text-orange-700'}`}>
                          {riscoUrgente
                            ? 'Riscos críticos exigem Análise Ergonômica do Trabalho para investigação aprofundada das condições organizacionais conforme NR-17.'
                            : 'Recomenda-se iniciar uma Análise Ergonômica do Trabalho (AET) para aprofundar a investigação dos fatores psicossociais identificados.'
                          }
                          {criticos.length > 0 && (
                            <span className="block mt-1">
                              <strong>Dimensões afetadas:</strong> {criticos.slice(0, 3).map(d => d.bloco).join(', ')}{criticos.length > 3 ? ` e mais ${criticos.length - 3}` : ''}.
                            </span>
                          )}
                        </p>
                        <p className="text-xs text-muted-foreground mt-1">
                          📋 Base normativa: NR-17 / ISO 45003 — Acesse o módulo de Ergonomia para iniciar a AET.
                        </p>
                      </div>
                    </div>
                  );
                })()
              )}
              <IntegracaoErgonomiaAEP
                campanha={campanhaRef}
                ips={ips}
                dimensoesCriticas={dimensoesAgregadas.filter(d => isCritico(d.media)).map(d => d.bloco)}
              />
            </TabsContent>

            {/* ── Tab: Participação ── */}
            <TabsContent value="participacao" className="mt-4 space-y-4">
              <div className="grid gap-4 md:grid-cols-5">
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm">Total de pessoas que responderam</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{stats?.concluidos || 0}</div>
                    <p className="text-[11px] text-muted-foreground mt-1">
                      Respostas efetivamente registradas
                    </p>
                  </CardContent>
                </Card>
                <Card className="border-primary/30 bg-primary/5">
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm">Total no {baseLabel}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold text-primary">{stats?.total_convites || 0}</div>
                    <p className="text-[11px] text-muted-foreground mt-1">
                      {stats?.concluidos || 0} de {stats?.total_convites || 0} colaboradores do {baseLabelInline} responderam
                    </p>
                    <Progress
                      value={stats?.total_convites ? ((stats.concluidos || 0) / stats.total_convites) * 100 : 0}
                      className="h-1.5 mt-2"
                    />
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm">Concluídos</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold text-emerald-600">{stats?.concluidos || 0}</div>
                    {stats && stats.concluidos >= MINIMO_ANONIMATO ? (
                      <div className="flex items-center gap-1 mt-1">
                        <ShieldCheck className="h-3 w-3 text-emerald-600" />
                        <span className="text-xs text-emerald-600">Anonimato garantido</span>
                      </div>
                    ) : (
                      <div className="flex items-center gap-1 mt-1">
                        <Lock className="h-3 w-3 text-amber-600" />
                        <span className="text-xs text-amber-600">
                          Faltam {MINIMO_ANONIMATO - (stats?.concluidos || 0)} respostas
                        </span>
                      </div>
                    )}
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm">Pendentes</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold text-amber-600">{stats?.pendentes || 0}</div>
                  </CardContent>
                </Card>
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm">Taxa de Participação</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className="text-2xl font-bold">{stats?.taxa_participacao?.toFixed(0) || 0}%</div>
                    <Progress value={stats?.taxa_participacao || 0} className="h-2 mt-2" />
                  </CardContent>
                </Card>
              </div>

              {/* Distribuição automática por Departamento e Cargo (via CPF do respondente) */}
              {(stats?.por_departamento?.length || stats?.por_cargo?.length) ? (
                <div className="grid gap-4 md:grid-cols-2">
                  {(['por_departamento','por_cargo'] as const).map((key) => {
                    const lista = stats?.[key] ?? [];
                    if (lista.length === 0) return null;
                    const titulo = key === 'por_departamento' ? 'Por Departamento' : 'Por Cargo';
                    return (
                      <Card key={key}>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-sm">{titulo}</CardTitle>
                          <p className="text-[11px] text-muted-foreground">
                            Segmentação automática a partir do cadastro do respondente (CPF). Grupos com menos de {MINIMO_ANONIMATO} respostas têm IPS oculto (ISO 45003).
                          </p>
                        </CardHeader>
                        <CardContent className="space-y-2">
                          {lista.map((g) => (
                            <div key={g.nome} className="flex items-center justify-between rounded-md border bg-muted/30 px-2.5 py-1.5 text-xs">
                              <div className="flex flex-col">
                                <span className="font-medium">{g.nome}</span>
                                <span className="text-[10px] text-muted-foreground">{g.total} resposta(s)</span>
                              </div>
                              {g.anonimato_garantido && g.ips !== undefined ? (
                                <div className="flex items-center gap-2">
                                  <span className="font-bold">IPS {g.ips}</span>
                                  {g.ips_classificacao && (
                                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-primary/10 text-primary">
                                      {g.ips_classificacao}
                                    </span>
                                  )}
                                </div>
                              ) : (
                                <span className="flex items-center gap-1 text-[10px] text-amber-600">
                                  <Lock className="h-3 w-3" /> Anonimato
                                </span>
                              )}
                            </div>
                          ))}
                        </CardContent>
                      </Card>
                    );
                  })}
                </div>
              ) : null}
            </TabsContent>
          </Tabs>
        )}

        <div className="flex justify-end gap-2 pt-2 border-t">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Fechar
          </Button>
          <ExportarRelatorio
            campanha={campanhaRef}
            stats={stats}
            dimensoes={dimensoesAgregadas}
            analiseIA={analiseIA}
          />
        </div>
      </DialogContent>
    </Dialog>

    {/* Modal de revisão do rascunho 5W2H antes de criar a ação (item 2) */}
    <Dialog open={rascunhoAcao !== null} onOpenChange={aberto => { if (!aberto) setRascunhoAcao(null); }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-amber-600" />
            Revisar ação antes de criar
          </DialogTitle>
          <DialogDescription>
            Rascunho 5W2H sugerido pela IA a partir do diagnóstico de <strong>{campanhaRef.nome}</strong>.
            Ajuste o que precisar e confirme para criar a ação no Plano de Ação. Nada é gravado até você confirmar.
          </DialogDescription>
        </DialogHeader>

        {rascunhoAcao && (
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="rascunho-titulo" className="text-xs">O quê — Título da ação</Label>
              <Input
                id="rascunho-titulo"
                value={rascunhoAcao.titulo}
                onChange={e => setRascunhoAcao({ ...rascunhoAcao, titulo: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rascunho-descricao" className="text-xs">Descrição</Label>
              <Textarea
                id="rascunho-descricao"
                rows={3}
                value={rascunhoAcao.descricao}
                onChange={e => setRascunhoAcao({ ...rascunhoAcao, descricao: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rascunho-porque" className="text-xs">Por quê</Label>
              <Textarea
                id="rascunho-porque"
                rows={2}
                value={rascunhoAcao.porque}
                onChange={e => setRascunhoAcao({ ...rascunhoAcao, porque: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rascunho-onde" className="text-xs">Onde</Label>
              <Input
                id="rascunho-onde"
                value={rascunhoAcao.onde}
                onChange={e => setRascunhoAcao({ ...rascunhoAcao, onde: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="rascunho-como" className="text-xs">Como</Label>
              <Textarea
                id="rascunho-como"
                rows={2}
                value={rascunhoAcao.como}
                onChange={e => setRascunhoAcao({ ...rascunhoAcao, como: e.target.value })}
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label className="text-xs">Prioridade</Label>
                <Select
                  value={rascunhoAcao.prioridade}
                  onValueChange={v => setRascunhoAcao({ ...rascunhoAcao, prioridade: v as AcaoGutPrioridade })}
                >
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="imediato">Imediato</SelectItem>
                    <SelectItem value="urgente">Urgente</SelectItem>
                    <SelectItem value="medio">Médio</SelectItem>
                    <SelectItem value="baixo">Baixo</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs">Tipo</Label>
                <Select
                  value={rascunhoAcao.tipo}
                  onValueChange={v => setRascunhoAcao({ ...rascunhoAcao, tipo: v as AcaoTipo })}
                >
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="preventiva">Preventiva</SelectItem>
                    <SelectItem value="corretiva">Corretiva</SelectItem>
                    <SelectItem value="melhoria">Melhoria</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
        )}

        <DialogFooter className="gap-2 sm:gap-0">
          <Button variant="outline" onClick={() => setRascunhoAcao(null)} disabled={salvandoAcao}>
            Cancelar
          </Button>
          <Button onClick={handleConfirmarAcao} disabled={salvandoAcao} className="gap-2">
            {salvandoAcao ? (
              <><Loader2 className="h-4 w-4 animate-spin" /> Criando...</>
            ) : (
              <><CheckCircle2 className="h-4 w-4" /> Confirmar e criar ação</>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
}
