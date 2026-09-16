import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { usePontoAlertas, ALERTA_TIPOS } from "@/hooks/usePontoAlertas";
import { Bell, CheckCircle, AlertTriangle, AlertOctagon, Info, Sparkles } from "lucide-react";
import { CriarAcaoAlertaModal } from "@/components/shared/CriarAcaoAlertaModal";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { abreviacaoDiaSemana } from "@/lib/ponto/diaSemana";

const SEVERIDADE_CONFIG: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
  baixa: { label: "Baixa", color: "bg-blue-100 text-blue-800", icon: <Info className="w-4 h-4" /> },
  media: { label: "Média", color: "bg-yellow-100 text-yellow-800", icon: <AlertTriangle className="w-4 h-4" /> },
  alta: { label: "Alta", color: "bg-orange-100 text-orange-800", icon: <AlertTriangle className="w-4 h-4" /> },
  critica: { label: "Crítica", color: "bg-red-100 text-red-800", icon: <AlertOctagon className="w-4 h-4" /> },
};

export function PontoAlertasTab() {
  const { alertas, loadingAlertas, resolverAlerta } = usePontoAlertas();
  const [filtroTipo, setFiltroTipo] = useState<string>("all");
  const [acaoModal, setAcaoModal] = useState<{ open: boolean; titulo: string; descricao: string; id?: string }>({ open: false, titulo: "", descricao: "" });
  const { tenantId, user, profile } = useAuth();
  const qc = useQueryClient();
  const [gerando, setGerando] = useState<string | null>(null);
  // Análise da IA: sugestão em tela, decisão do humano registrada. A IA nunca
  // decide sozinha nada que afete direito do trabalhador (LGPD art. 20).
  const [analise, setAnalise] = useState<any>(null);
  const [obsDecisao, setObsDecisao] = useState("");
  const [decidindo, setDecidindo] = useState(false);

  /** Converte o alerta em ação 5W2H no Plano de Ação, pela ponte do banco —
   *  que preenche a origem e deixa o alerta vinculado à ação gerada. */
  const gerarAcao = async (alertaId: string) => {
    if (!tenantId) return;
    setGerando(alertaId);
    try {
      const { error } = await (supabase.rpc as any)("ponto_alerta_gerar_acao", {
        p_tenant_id: tenantId,
        p_alerta_id: alertaId,
        p_responsavel_id: user?.id || null,
        p_responsavel_nome: profile?.nome_completo || null,
        p_prazo_dias: 15,
      });
      if (error) throw error;
      qc.invalidateQueries({ queryKey: ["ponto-alertas"] });
      qc.invalidateQueries({ queryKey: ["plano-acao"] });
      toast.success("Ação criada no Plano de Ação, ligada a este alerta.");
    } catch (e: any) {
      toast.error("Não foi possível gerar a ação: " + (e?.message || ""));
    } finally {
      setGerando(null);
    }
  };

  const analisarComIa = async (alertaId: string) => {
    if (!tenantId) return;
    try {
      const { data: id, error } = await (supabase.rpc as any)("ponto_ia_analisar_alerta", {
        p_tenant_id: tenantId,
        p_alerta_id: alertaId,
      });
      if (error) throw error;
      const { data } = await supabase
        .from("ponto_ia_analises" as any)
        .select("*")
        .eq("id", id as string)
        .maybeSingle() as { data: any };
      setObsDecisao("");
      setAnalise({ ...data, alerta_id: alertaId });
    } catch (e: any) {
      toast.error("Não foi possível analisar: " + (e?.message || ""));
    }
  };

  const decidir = async (decisao: "aceito" | "rejeitado") => {
    if (!analise || !user) return;
    setDecidindo(true);
    try {
      const { error } = await (supabase.rpc as any)("ponto_ia_registrar_decisao", {
        p_analise_id: analise.id,
        p_decisao: decisao,
        p_decidido_por: user.id,
        p_decidido_por_nome: profile?.nome_completo || null,
        p_observacao: obsDecisao || null,
      });
      if (error) throw error;
      // Aceitar a sugestão é o gesto que vira ação — e é humano, não da IA.
      if (decisao === "aceito") await gerarAcao(analise.alerta_id);
      setAnalise(null);
      toast.success(decisao === "aceito" ? "Sugestão aceita e ação criada." : "Sugestão rejeitada. A decisão fica registrada.");
    } catch (e: any) {
      toast.error("Não foi possível registrar a decisão: " + (e?.message || ""));
    } finally {
      setDecidindo(false);
    }
  };

  const alertasFiltrados = filtroTipo === "all" ? alertas : alertas.filter(a => a.tipo === filtroTipo);

  const contagem = {
    total: alertas.length,
    critica: alertas.filter(a => a.severidade === "critica").length,
    alta: alertas.filter(a => a.severidade === "alta").length,
    media: alertas.filter(a => a.severidade === "media").length,
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Bell className="w-5 h-5 text-primary" /> Alertas Operacionais
          </h3>
          <p className="text-sm text-muted-foreground">Riscos trabalhistas e alertas de conformidade</p>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-3xl font-bold">{contagem.total}</p>
            <p className="text-sm text-muted-foreground">Total Ativos</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-3xl font-bold text-red-600">{contagem.critica}</p>
            <p className="text-sm text-muted-foreground">Críticos</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-3xl font-bold text-orange-600">{contagem.alta}</p>
            <p className="text-sm text-muted-foreground">Alta</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 text-center">
            <p className="text-3xl font-bold text-yellow-600">{contagem.media}</p>
            <p className="text-sm text-muted-foreground">Média</p>
          </CardContent>
        </Card>
      </div>

      {/* Filter chips */}
      <div className="flex gap-2 flex-wrap">
        <Button variant={filtroTipo === "all" ? "default" : "outline"} size="sm" onClick={() => setFiltroTipo("all")}>Todos</Button>
        {Object.entries(ALERTA_TIPOS).map(([key, val]) => (
          <Button key={key} variant={filtroTipo === key ? "default" : "outline"} size="sm" onClick={() => setFiltroTipo(key)}>
            {val.icon} {val.label}
          </Button>
        ))}
      </div>

      {/* Table */}
      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Severidade</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Colaborador</TableHead>
                <TableHead>Título</TableHead>
                <TableHead>Descrição</TableHead>
                <TableHead>Data</TableHead>
                <TableHead>Ação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingAlertas ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : alertasFiltrados.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                  {alertas.length === 0 ? "Nenhum alerta ativo. ✅" : "Nenhum alerta para este filtro."}
                </TableCell></TableRow>
              ) : alertasFiltrados.map(a => {
                const sev = SEVERIDADE_CONFIG[a.severidade] || SEVERIDADE_CONFIG.media;
                const tipo = ALERTA_TIPOS[a.tipo as keyof typeof ALERTA_TIPOS];
                return (
                  <TableRow key={a.id}>
                    <TableCell>
                      <Badge className={sev.color}>{sev.icon} {sev.label}</Badge>
                    </TableCell>
                    <TableCell><Badge variant="outline">{tipo?.label || a.tipo}</Badge></TableCell>
                    <TableCell>{a.colaborador_nome || "Geral"}</TableCell>
                    <TableCell className="font-medium">{a.titulo}</TableCell>
                    <TableCell className="max-w-[200px] truncate">{a.descricao || "-"}</TableCell>
                    {/* RN16: data legível + abreviação do dia da semana. */}
                    <TableCell className="whitespace-nowrap">
                      {a.data_referencia
                        ? <>
                            {String(a.data_referencia).slice(0, 10).split("-").reverse().join("/")}{" "}
                            <span className="text-muted-foreground font-medium text-xs">
                              {abreviacaoDiaSemana(String(a.data_referencia))}
                            </span>
                          </>
                        : "-"}
                    </TableCell>
                    <TableCell className="flex gap-1">
                      <Button size="sm" variant="outline" onClick={() => resolverAlerta(a.id)}>
                        <CheckCircle className="w-3 h-3 mr-1" /> Resolver
                      </Button>
                      {(a as any).plano_acao_id ? (
                        <Badge variant="outline" className="border-emerald-400 text-emerald-700">
                          Ação criada
                        </Badge>
                      ) : (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={gerando === a.id}
                          onClick={() => gerarAcao(a.id)}
                        >
                          {gerando === a.id ? "Gerando..." : "Gerar ação"}
                        </Button>
                      )}
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-primary"
                        onClick={() => analisarComIa(a.id)}
                      >
                        <Sparkles className="w-3 h-3 mr-1" /> Analisar com IA
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Sugestão da IA + decisão humana registrada (LGPD art. 20) */}
      <Dialog open={!!analise} onOpenChange={(o) => !o && setAnalise(null)}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>Sugestão da análise automática</DialogTitle>
            <DialogDescription>
              A análise <strong>sugere</strong>; quem decide é você. Nada aqui é aplicado sozinho —
              e a sua decisão fica registrada, aceitando ou recusando.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3 text-sm">
            <div>
              <p className="text-xs text-muted-foreground">Causa provável</p>
              <p>{analise?.causa_provavel || "—"}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Impacto se persistir</p>
              <p>{analise?.impacto || "—"}</p>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Ação sugerida</p>
              <p>{analise?.acao_sugerida || "—"}</p>
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">Observação da sua decisão (opcional)</p>
              <Textarea rows={3} value={obsDecisao} onChange={(e) => setObsDecisao(e.target.value)}
                placeholder="Ex: já tratamos com o gestor da área; a causa aqui é outra." />
            </div>
          </div>

          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => decidir("rejeitado")} disabled={decidindo}>
              Recusar sugestão
            </Button>
            <Button onClick={() => decidir("aceito")} disabled={decidindo}>
              {decidindo ? "Registrando..." : "Aceitar e criar ação"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <CriarAcaoAlertaModal
        open={acaoModal.open}
        onOpenChange={(open) => setAcaoModal(prev => ({ ...prev, open }))}
        alertaTitulo={acaoModal.titulo}
        alertaDescricao={acaoModal.descricao}
        origemModulo="ponto"
        origemId={acaoModal.id}
      />
    </div>
  );
}
