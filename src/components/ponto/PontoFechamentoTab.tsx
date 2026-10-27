import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog";
import { usePontoFechamento, type PontoEspelho } from "@/hooks/usePontoFechamento";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { arquivarDocumento } from "@/utils/arquivarDocumento";
import { format } from "date-fns";
import { Lock, Unlock, FileText, CheckCircle, AlertTriangle, Download, Archive, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import jsPDF from "jspdf";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { formatarHoraMinuto } from "@/lib/ponto/diaSemana";

const STATUS_FECHAMENTO: Record<string, { label: string; color: string }> = {
  aberto: { label: "Aberto", color: "bg-green-100 text-green-800" },
  em_revisao: { label: "Em Revisão", color: "bg-yellow-100 text-yellow-800" },
  fechado: { label: "Fechado", color: "bg-red-100 text-red-800" },
};

interface PendenciaFechamento {
  tipo: string;
  colaborador_cpf: string | null;
  data_referencia: string | null;
  descricao: string | null;
}

const PENDENCIA_LABEL: Record<string, string> = {
  ajuste_pendente: "Ajuste de ponto aguardando aprovação",
  dia_incompleto: "Dia incompleto sem tratamento",
  espelho_sem_ciencia: "Espelho sem ciência do colaborador",
};

const STATUS_ESPELHO: Record<string, { label: string; color: string }> = {
  preview: { label: "Em andamento", color: "bg-blue-100 text-blue-800" },
  gerado: { label: "Gerado", color: "bg-gray-100 text-gray-800" },
  enviado: { label: "Enviado", color: "bg-blue-100 text-blue-800" },
  confirmado: { label: "Confirmado", color: "bg-green-100 text-green-800" },
  ressalva: { label: "Ressalva", color: "bg-yellow-100 text-yellow-800" },
};

export function PontoFechamentoTab() {
  const { useFechamentos, useEspelhos, fecharPeriodo, fechandoPeriodo, reabrirPeriodo, reabrindoPeriodo, confirmarEspelho, confirmandoEspelho } = usePontoFechamento();
  const { tenantId, user, profile } = useAuth();
  const { empresaAtiva, empresaAtivaId } = useEmpresaAtiva();
  const nomeEmpresa = empresaAtiva?.razao_social || empresaAtiva?.nome_fantasia || null;
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [showFechar, setShowFechar] = useState(false);
  const [showReabrir, setShowReabrir] = useState(false);
  const [motivoReabertura, setMotivoReabertura] = useState("");
  const [showRessalva, setShowRessalva] = useState(false);
  const [selectedEspelho, setSelectedEspelho] = useState<PontoEspelho | null>(null);
  const [observacoes, setObservacoes] = useState("");
  const [ressalvaTexto, setRessalvaTexto] = useState("");

  const { data: fechamentos = [] } = useFechamentos();
  const { data: espelhos = [], isLoading } = useEspelhos(competencia);
  const queryClient = useQueryClient();

  const fechamentoAtual = fechamentos.find(f => f.competencia === competencia);
  const isFechado = fechamentoAtual?.status === "fechado";

  // Pendências que impedem o fechamento (PONTO-387/388). A mesma lista que o
  // portão do banco consulta ao recusar o fechamento — aqui ela aparece ANTES,
  // para o RH tratar em vez de esbarrar no bloqueio.
  const { data: pendencias = [], isLoading: loadingPendencias } = useQuery({
    queryKey: ["ponto-fechamento-pendencias", tenantId, empresaAtivaId, competencia],
    queryFn: async (): Promise<PendenciaFechamento[]> => {
      if (!tenantId) return [];
      const { data, error } = await (supabase.rpc as any)("ponto_fechamento_pendencias_criticas", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      if (error) throw error;
      return (data || []) as PendenciaFechamento[];
    },
    enabled: !!tenantId && !!competencia && !isFechado,
  });

  // Nome do colaborador a partir do que já está carregado na competência;
  // sem correspondência, mostra o CPF mesmo.
  const nomePorCpf = (cpf: string | null) => {
    const d = (cpf || "").replace(/\D/g, "");
    const achado = [...espelhos, ...previewEspelhos].find(
      e => (e.colaborador_cpf || "").replace(/\D/g, "") === d
    );
    return achado?.colaborador_nome || (cpf || "—");
  };

  const contarPendencias = (tipo: string) => pendencias.filter(p => p.tipo === tipo).length;
  const temPendencias = pendencias.length > 0;

  // Live preview: aggregate ponto_diario when there are no persisted espelhos
  const periodo = (() => {
    const [yStr, mStr] = competencia.split("-");
    const y = parseInt(yStr); const m = parseInt(mStr);
    const lastDay = new Date(y, m, 0).getDate();
    return { start: `${competencia}-01`, end: `${competencia}-${String(lastDay).padStart(2, "0")}` };
  })();

  // Pré-visualização a partir da APURAÇÃO — a mesma fonte do Banco de
  // Horas. Antes somava colunas de ponto_diario que a consolidação atual
  // não preenche mais (HE 50/100, adicional noturno, atraso), e por isso
  // o espelho saía inteiro zerado.
  const { data: previewEspelhos = [], isLoading: loadingPreview } = useQuery({
    queryKey: ["ponto-espelhos-preview", tenantId, empresaAtivaId, competencia],
    queryFn: async (): Promise<PontoEspelho[]> => {
      if (!tenantId) return [];
      const { data, error } = await (supabase.rpc as any)("ponto_espelho_resumo_empresa", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      if (error) throw error;
      return ((data || []) as any[]).map((r) => ({
        id: `preview-${r.colaborador_cpf}`,
        tenant_id: tenantId,
        colaborador_id: r.colaborador_id,
        colaborador_nome: r.colaborador_nome,
        colaborador_cpf: r.colaborador_cpf,
        competencia,
        total_horas_normais_minutos: Number(r.total_trabalhado_min) || 0,
        // RN28: o crédito do banco de horas é a base de pagamento de HE.
        total_horas_extras_50_minutos: Number(r.he_50_min) || 0,
        total_horas_extras_100_minutos: Number(r.he_100_min) || 0,
        total_adicional_noturno_minutos: 0,
        total_faltas: Number(r.total_faltas) || 0,
        total_atrasos_minutos: Number(r.atrasos_min) || 0,
        total_dsr: 0,
        banco_horas_saldo_minutos: Number(r.saldo_banco_min ?? r.saldo_min) || 0,
        total_trabalhado_minutos: Number(r.total_trabalhado_min) || 0,
        total_jornada_prevista_minutos: Number(r.total_jornada_prevista_min) || 0,
        total_creditos_minutos: Number(r.total_creditos_min) || 0,
        total_debitos_minutos: Number(r.total_debitos_min) || 0,
        total_dias_trabalhados: Number(r.dias_trabalhados) || 0,
        total_dias_protegidos: Number(r.dias_protegidos) || 0,
        total_excedente_retido_minutos: Number(r.excedente_retido_min) || 0,
        dia_equalizacao: r.dia_equalizacao || null,
        status: "preview",
        ressalva_texto: null,
        data_confirmacao: null,
        created_at: null,
      })) as PontoEspelho[];
    },
    enabled: !!tenantId && espelhos.length === 0,
  });

  // Realtime: refresh espelhos/preview when ponto changes
  useEffect(() => {
    if (!tenantId) return;
    const channel = supabase
      .channel(`ponto-espelho-live-${tenantId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ponto_diario", filter: `tenant_id=eq.${tenantId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ["ponto-espelhos-preview"] });
        queryClient.invalidateQueries({ queryKey: ["ponto-espelhos"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "ponto_registros", filter: `tenant_id=eq.${tenantId}` }, () => {
        queryClient.invalidateQueries({ queryKey: ["ponto-espelhos-preview"] });
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [tenantId, queryClient]);

  const rowsToShow: PontoEspelho[] = espelhos.length > 0 ? espelhos : previewEspelhos;
  const isPreview = espelhos.length === 0 && previewEspelhos.length > 0;

  // RN19: minutos sempre com dois dígitos ("8h 08min").
  const formatMinutos = (min: number) => formatarHoraMinuto(Math.abs(min));

  const handleFechar = async () => {
    try {
      await fecharPeriodo({ competencia, observacoes });
      setShowFechar(false);
      setObservacoes("");
    } catch {
      // O portão do banco recusou (pendência crítica) — a mensagem já aparece
      // em aviso; mantém o diálogo aberto e reconfere a lista de pendências.
      queryClient.invalidateQueries({ queryKey: ["ponto-fechamento-pendencias"] });
    }
  };

  const handleReabrir = async () => {
    await reabrirPeriodo({ competencia, motivo: motivoReabertura });
    setShowReabrir(false);
    setMotivoReabertura("");
  };


  const handleConfirmar = async (espelhoId: string) => {
    await confirmarEspelho({ espelhoId });
  };

  const handleRessalva = async () => {
    if (!selectedEspelho) return;
    await confirmarEspelho({ espelhoId: selectedEspelho.id, ressalva: ressalvaTexto });
    setShowRessalva(false);
    setRessalvaTexto("");
    setSelectedEspelho(null);
  };

  const gerarEspelhoPDF = async (espelho: PontoEspelho) => {
    const pdf = new jsPDF();
    pdf.setFontSize(16);
    pdf.text("Espelho de Ponto", 20, 20);
    pdf.setFontSize(10);
    pdf.text(`Competência: ${espelho.competencia}`, 20, 30);
    pdf.text(`Colaborador: ${espelho.colaborador_nome}`, 20, 37);
    pdf.text(`CPF: ${espelho.colaborador_cpf}`, 20, 44);
    pdf.text(`Status: ${STATUS_ESPELHO[espelho.status]?.label || espelho.status}`, 20, 51);

    const saldo = espelho.banco_horas_saldo_minutos ?? 0;
    const sinal = saldo >= 0 ? "+" : "-";

    let y = 65;
    pdf.setFontSize(12);
    pdf.text("Resumo da Jornada", 20, y); y += 10;
    pdf.setFontSize(10);
    pdf.text(`Dias trabalhados: ${espelho.total_dias_trabalhados ?? 0}`, 20, y); y += 7;
    pdf.text(`Horas trabalhadas: ${formatMinutos(espelho.total_trabalhado_minutos ?? 0)}`, 20, y); y += 7;
    pdf.text(`Jornada prevista: ${formatMinutos(espelho.total_jornada_prevista_minutos ?? 0)}`, 20, y); y += 7;
    pdf.text(`Creditos no periodo: ${formatMinutos(espelho.total_creditos_minutos ?? 0)}`, 20, y); y += 7;
    pdf.text(`Debitos no periodo: ${formatMinutos(espelho.total_debitos_minutos ?? 0)}`, 20, y); y += 7;
    pdf.text(`Saldo do periodo: ${sinal}${formatMinutos(saldo)}`, 20, y); y += 7;
    pdf.text(`Faltas: ${espelho.total_faltas ?? 0}`, 20, y); y += 7;
    pdf.text(`Dias abonados (atestado/ferias/afastamento/feriado): ${espelho.total_dias_protegidos ?? 0}`, 20, y); y += 7;
    if ((espelho.total_excedente_retido_minutos ?? 0) > 0) {
      pdf.text(`Excedente retido para decisao do RH: ${formatMinutos(espelho.total_excedente_retido_minutos ?? 0)}`, 20, y); y += 7;
    }
    if (espelho.dia_equalizacao) {
      const [ea, em, ed] = String(espelho.dia_equalizacao).split("-");
      pdf.text(`Dia de equalizacao: ${ed}/${em}/${ea}`, 20, y); y += 7;
    }
    y += 4;

    // RN28: o crédito do banco de horas é a base de pagamento de hora extra.
    pdf.text(`Horas extras 50%: ${formatMinutos(espelho.total_horas_extras_50_minutos ?? 0)}`, 20, y); y += 7;
    pdf.text(`Horas extras 100% (domingo/feriado): ${formatMinutos(espelho.total_horas_extras_100_minutos ?? 0)}`, 20, y); y += 7;
    pdf.setFontSize(8);
    pdf.text("Adicional noturno nao e apurado neste modelo; consulte a folha.", 20, y); y += 10;
    pdf.setFontSize(10);

    if (espelho.status === "confirmado" || espelho.status === "ressalva") {
      pdf.text(`Confirmado em: ${espelho.data_confirmacao ? format(new Date(espelho.data_confirmacao), "dd/MM/yyyy HH:mm") : "-"}`, 20, y); y += 7;
      if (espelho.ressalva_texto) {
        pdf.text(`Ressalva: ${espelho.ressalva_texto}`, 20, y);
      }
    }

    // Download local
    pdf.save(`espelho-ponto-${espelho.colaborador_nome}-${espelho.competencia}.pdf`);
    toast.success("PDF gerado!");

    // Auto-archive to Documentos module
    if (tenantId && user) {
      const blob = pdf.output("blob");
      const fileName = `Espelho de Ponto - ${espelho.colaborador_nome} - ${espelho.competencia}.pdf`;
      await arquivarDocumento({
        tenantId,
        empresaId: empresaAtivaId,
        userId: user.id,
        userNome: profile?.nome_completo || "Sistema",
        file: blob,
        fileName,
        tipo: "Espelho de Ponto",
        observacoes: `Espelho de ponto competência ${espelho.competencia}`,
        colaboradorId: espelho.colaborador_id || null,
        colaboradorNome: espelho.colaborador_nome,
        colaboradorCpf: espelho.colaborador_cpf,
        subpastaColaborador: "Vida Funcional",
      });
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Lock className="w-5 h-5 text-primary" /> Fechamento & Espelho de Ponto
          </h3>
          <p className="text-sm text-muted-foreground">Feche períodos e gerencie espelhos de ponto</p>
        </div>
        <div className="flex items-center gap-2">
          <CompetenciaInput value={competencia} onChange={setCompetencia} className="w-[180px]" />
          {isFechado ? (
            <Button variant="outline" onClick={() => setShowReabrir(true)}>
              <Unlock className="w-4 h-4 mr-2" /> Reabrir Período
            </Button>
          ) : (
            <Button variant="destructive" onClick={() => setShowFechar(true)}>
              <Lock className="w-4 h-4 mr-2" /> Fechar Período
            </Button>
          )}
        </div>
      </div>

      {/* Pendências que impedem o fechamento (PONTO-387/388) */}
      {!isFechado && temPendencias && (
        <Card className="border-amber-300">
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2 text-amber-700">
              <AlertTriangle className="w-5 h-5" />
              Pendências que impedem o fechamento ({pendencias.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex flex-wrap gap-2 text-sm">
              {Object.keys(PENDENCIA_LABEL).map(tipo => {
                const n = contarPendencias(tipo);
                if (!n) return null;
                return (
                  <Badge key={tipo} variant="outline" className="border-amber-400 text-amber-800">
                    {n} · {PENDENCIA_LABEL[tipo]}
                  </Badge>
                );
              })}
            </div>
            <div className="max-h-56 overflow-y-auto rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Colaborador</TableHead>
                    <TableHead>Ocorrência</TableHead>
                    <TableHead className="text-center">Dia</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {pendencias.map((p, i) => (
                    <TableRow key={`${p.tipo}-${p.colaborador_cpf}-${p.data_referencia}-${i}`}>
                      <TableCell className="font-medium">{nomePorCpf(p.colaborador_cpf)}</TableCell>
                      <TableCell className="text-sm">{PENDENCIA_LABEL[p.tipo] || p.descricao || p.tipo}</TableCell>
                      <TableCell className="text-center text-sm">
                        {p.data_referencia ? format(new Date(`${p.data_referencia}T00:00:00`), "dd/MM/yyyy") : "—"}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <p className="text-xs text-muted-foreground">
              Enquanto houver pendência aqui, o fechamento fica bloqueado: aprove ou recuse os ajustes,
              trate os dias incompletos e colha a ciência dos espelhos (Súmula 338 do TST). Espelho com
              ressalva formal registrada não bloqueia.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Status do Fechamento */}
      {fechamentoAtual && (
        <Card>
          <CardContent className="p-4 flex items-center justify-between">
            <div className="flex items-center gap-3">
              {isFechado ? <Lock className="w-6 h-6 text-destructive" /> : <Unlock className="w-6 h-6 text-success" />}
              <div>
                <p className="font-medium">Competência {competencia}</p>
                <p className="text-sm text-muted-foreground">
                  {isFechado ? `Fechado em ${format(new Date(fechamentoAtual.data_fechamento!), "dd/MM/yyyy HH:mm")} por ${fechamentoAtual.fechado_por_nome}` : "Aberto para edição"}
                </p>
              </div>
            </div>
            <Badge className={STATUS_FECHAMENTO[fechamentoAtual.status]?.color}>
              {STATUS_FECHAMENTO[fechamentoAtual.status]?.label}
            </Badge>
          </CardContent>
        </Card>
      )}

      {/* Espelhos */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <FileText className="w-4 h-4" /> Espelhos de Ponto — {competencia}
            {isPreview && (
              <Badge variant="outline" className="ml-2 text-xs">Pré-visualização ao vivo</Badge>
            )}
          </CardTitle>
          {isPreview && (
            <p className="text-xs text-muted-foreground">
              Mostrando totais calculados em tempo real a partir das marcações do período. Feche o período para gerar os espelhos oficiais.
            </p>
          )}
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-right">Trabalhado</TableHead>
                <TableHead className="text-right">Previsto</TableHead>
                <TableHead className="text-right">Créditos</TableHead>
                <TableHead className="text-right">Débitos</TableHead>
                <TableHead className="text-right">HE 50%</TableHead>
                <TableHead className="text-right">HE 100%</TableHead>
                <TableHead className="text-right">Saldo</TableHead>
                <TableHead className="text-right">Faltas</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(isLoading || loadingPreview) && rowsToShow.length === 0 ? (
                <TableRow><TableCell colSpan={11} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : rowsToShow.length === 0 ? (
                <TableRow><TableCell colSpan={11} className="text-center py-8 text-muted-foreground">
                  Nenhum registro de ponto encontrado para {competencia}.
                </TableCell></TableRow>
              ) : rowsToShow.map(e => (
                <TableRow key={e.id}>
                  <TableCell className="font-medium">{e.colaborador_nome}</TableCell>
                  <TableCell className="text-right font-mono">{formatMinutos(e.total_trabalhado_minutos ?? 0)}</TableCell>
                  <TableCell className="text-right font-mono text-muted-foreground">{formatMinutos(e.total_jornada_prevista_minutos ?? 0)}</TableCell>
                  <TableCell className="text-right font-mono text-green-600">{formatMinutos(e.total_creditos_minutos ?? 0)}</TableCell>
                  <TableCell className="text-right font-mono text-red-600">{formatMinutos(e.total_debitos_minutos ?? 0)}</TableCell>
                  <TableCell className="text-right font-mono">{formatMinutos(e.total_horas_extras_50_minutos ?? 0)}</TableCell>
                  <TableCell className="text-right font-mono">{formatMinutos(e.total_horas_extras_100_minutos ?? 0)}</TableCell>
                  <TableCell className={`text-right font-mono font-semibold ${(e.banco_horas_saldo_minutos ?? 0) >= 0 ? "text-green-600" : "text-red-600"}`}>
                    {(e.banco_horas_saldo_minutos ?? 0) >= 0 ? "+" : "-"}{formatMinutos(e.banco_horas_saldo_minutos ?? 0)}
                  </TableCell>
                  <TableCell className="text-right">{e.total_faltas}</TableCell>
                  <TableCell>
                    <Badge className={STATUS_ESPELHO[e.status]?.color}>{STATUS_ESPELHO[e.status]?.label || e.status}</Badge>
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {e.status !== "preview" && (
                        <Button size="sm" variant="ghost" onClick={() => gerarEspelhoPDF(e)} title="Baixar PDF">
                          <Download className="w-4 h-4" />
                        </Button>
                      )}
                      {e.status === "gerado" && (
                        <>
                          <Button size="sm" variant="ghost" className="text-success" onClick={() => handleConfirmar(e.id)} title="Confirmar">
                            <CheckCircle className="w-4 h-4" />
                          </Button>
                          <Button size="sm" variant="ghost" className="text-warning" onClick={() => { setSelectedEspelho(e); setShowRessalva(true); }} title="Ressalva">
                            <AlertTriangle className="w-4 h-4" />
                          </Button>
                        </>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>


      {/* Dialog Fechar */}
      <Dialog open={showFechar} onOpenChange={setShowFechar}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Fechar Período</DialogTitle>
            <DialogDescription>Ao fechar, os dados ficarão bloqueados para alteração e os espelhos serão gerados.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {/* Quem está sendo fechado. O fechamento é da empresa
                selecionada na barra do topo — deixar isso implícito foi o
                que fez parecer que ele fechava o sistema inteiro. */}
            <div className="p-3 rounded-lg border text-sm space-y-1">
              <div>
                <span className="text-muted-foreground">Empresa: </span>
                <strong>{nomeEmpresa || "Todas as empresas"}</strong>
              </div>
              <div>
                <span className="text-muted-foreground">Competência: </span>
                <strong>{competencia}</strong>
                <span className="text-muted-foreground"> · </span>
                <strong>{rowsToShow.length}</strong>
                <span className="text-muted-foreground"> colaborador(es) serão fechados</span>
              </div>
            </div>
            <div className="p-3 bg-destructive/10 rounded-lg text-sm text-destructive">
              <strong>Atenção:</strong> Os dados ficam bloqueados para alteração. Se precisar corrigir depois, use "Reabrir Período".
            </div>
            {temPendencias && (
              <div className="p-3 rounded-lg border border-amber-300 bg-amber-50 text-sm text-amber-900 space-y-1">
                <div className="flex items-center gap-2 font-medium">
                  <AlertTriangle className="w-4 h-4" />
                  {pendencias.length} pendência(s) impedem o fechamento
                </div>
                <ul className="list-disc pl-5">
                  {Object.keys(PENDENCIA_LABEL).map(tipo => {
                    const n = contarPendencias(tipo);
                    return n ? <li key={tipo}>{n} · {PENDENCIA_LABEL[tipo]}</li> : null;
                  })}
                </ul>
                <p>Trate as pendências listadas na aba antes de fechar.</p>
              </div>
            )}
            <div className="space-y-2">
              <Label>Observações (opcional)</Label>
              <Textarea value={observacoes} onChange={e => setObservacoes(e.target.value)} placeholder="Observações sobre o fechamento..." />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowFechar(false)}>Cancelar</Button>
            <Button
              variant="destructive"
              onClick={handleFechar}
              disabled={fechandoPeriodo || temPendencias || loadingPendencias}
            >
              {fechandoPeriodo ? "Fechando..." : temPendencias ? "Bloqueado por pendências" : "Confirmar Fechamento"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Reabrir */}
      <Dialog open={showReabrir} onOpenChange={setShowReabrir}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reabrir Período</DialogTitle>
            <DialogDescription>
              A competência volta a ficar aberta para correção. Os espelhos ainda não
              confirmados pelos colaboradores são descartados e serão gerados de novo no
              próximo fechamento; os já confirmados ou com ressalva permanecem.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="p-3 rounded-lg border text-sm space-y-1">
              <div>
                <span className="text-muted-foreground">Empresa: </span>
                <strong>{nomeEmpresa || "Todas as empresas"}</strong>
              </div>
              <div>
                <span className="text-muted-foreground">Competência: </span>
                <strong>{competencia}</strong>
              </div>
            </div>
            <div className="space-y-2">
              <Label>Motivo da reabertura</Label>
              <Textarea
                value={motivoReabertura}
                onChange={e => setMotivoReabertura(e.target.value)}
                placeholder="Ex.: apuração incorreta, atestado lançado após o fechamento..."
                rows={3}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowReabrir(false)}>Cancelar</Button>
            <Button onClick={handleReabrir} disabled={!motivoReabertura.trim() || reabrindoPeriodo}>
              {reabrindoPeriodo ? "Reabrindo..." : "Confirmar Reabertura"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Ressalva */}
      <Dialog open={showRessalva} onOpenChange={setShowRessalva}>
        <DialogContent>
          <DialogHeader><DialogTitle>Registrar Ressalva</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Descrição da ressalva</Label>
              <Textarea value={ressalvaTexto} onChange={e => setRessalvaTexto(e.target.value)} placeholder="Descreva a divergência encontrada..." rows={4} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowRessalva(false)}>Cancelar</Button>
            <Button onClick={handleRessalva} disabled={!ressalvaTexto || confirmandoEspelho}>
              {confirmandoEspelho ? "Registrando..." : "Registrar Ressalva"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
