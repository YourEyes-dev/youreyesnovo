import { useState, useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useAuth } from "@/hooks/useAuth";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Bell, CheckCircle, AlertTriangle, Clock, Plus } from "lucide-react";
import { toast } from "sonner";
import { format, addMonths, endOfMonth, setDate, isBefore, differenceInDays } from "date-fns";
import { formatDateBR } from "@/lib/dataLocal";

interface AlertaPrazo {
  id: string;
  competencia: string;
  tipo: string;
  descricao: string;
  data_limite: string;
  status: string;
  concluido_em?: string;
  concluido_por?: string;
}

const TIPO_LABELS: Record<string, string> = {
  fechamento_folha: "Fechamento da Folha",
  pagamento: "Pagamento (5º dia útil)",
  fgts: "FGTS (até dia 20)",
  esocial_s1200: "eSocial S-1200",
  esocial_s1210: "eSocial S-1210",
  dctfweb: "DCTFWeb",
  inss_patronal: "INSS Patronal (dia 20)",
  rescisao_pagamento: "Pagamento de rescisão",
  // 13º salário — gerados pela varredura do banco, não por esta tela
  decimo_terceiro_1a_parcela: "13º — 1ª parcela (até 30/11)",
  decimo_terceiro_2a_parcela: "13º — 2ª parcela (até 20/12)",
  decimo_terceiro_base_incompleta: "13º — base de médias incompleta",
  decimo_terceiro_afastamento: "13º — afastamento a validar",
};

const TIPO_ICONS: Record<string, string> = {
  fechamento_folha: "📋",
  pagamento: "💰",
  fgts: "🏦",
  esocial_s1200: "📡",
  esocial_s1210: "📡",
  dctfweb: "📄",
  inss_patronal: "🏛️",
  rescisao_pagamento: "🤝",
  decimo_terceiro_1a_parcela: "🎁",
  decimo_terceiro_2a_parcela: "🎁",
  decimo_terceiro_base_incompleta: "🧮",
  decimo_terceiro_afastamento: "🩺",
};

/**
 * Gera alertas padrão para uma competência
 */
function gerarAlertasPadrao(competencia: string): Omit<AlertaPrazo, "id">[] {
  const [ano, mes] = competencia.split("-").map(Number);
  const proximoMes = addMonths(new Date(ano, mes - 1, 1), 1);

  return [
    {
      competencia,
      tipo: "fechamento_folha",
      descricao: `Fechar folha de ${competencia} para cálculo de proventos e descontos`,
      data_limite: format(endOfMonth(new Date(ano, mes - 1, 1)), "yyyy-MM-dd"),
      status: "pendente",
    },
    {
      competencia,
      tipo: "pagamento",
      descricao: `Pagamento dos salários ref. ${competencia} (até 5º dia útil)`,
      data_limite: format(setDate(proximoMes, 7), "yyyy-MM-dd"), // aprox 5º útil
      status: "pendente",
    },
    {
      competencia,
      tipo: "fgts",
      descricao: `Recolhimento FGTS Digital ref. ${competencia}`,
      data_limite: format(setDate(proximoMes, 20), "yyyy-MM-dd"),
      status: "pendente",
    },
    {
      competencia,
      tipo: "esocial_s1200",
      descricao: `Envio evento S-1200 (Remuneração) ref. ${competencia}`,
      data_limite: format(setDate(proximoMes, 15), "yyyy-MM-dd"),
      status: "pendente",
    },
    {
      competencia,
      tipo: "esocial_s1210",
      descricao: `Envio evento S-1210 (Pagamentos) ref. ${competencia}`,
      data_limite: format(setDate(proximoMes, 15), "yyyy-MM-dd"),
      status: "pendente",
    },
    {
      competencia,
      tipo: "dctfweb",
      descricao: `Transmissão DCTFWeb ref. ${competencia}`,
      data_limite: format(setDate(proximoMes, 15), "yyyy-MM-dd"),
      status: "pendente",
    },
    {
      competencia,
      tipo: "inss_patronal",
      descricao: `Recolhimento INSS patronal ref. ${competencia}`,
      data_limite: format(setDate(proximoMes, 20), "yyyy-MM-dd"),
      status: "pendente",
    },
  ];
}

export function FolhaAlertasTab() {
  const { tenantId } = useTenant();
  const { profile } = useAuth();
  const queryClient = useQueryClient();
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));

  const { data: alertas = [], isLoading } = useQuery({
    queryKey: ["folha-alertas", tenantId, competencia],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await supabase
        .from("folha_alertas_prazo" as any)
        .select("*")
        .eq("tenant_id", tenantId)
        // Os alertas do 13º nascem da varredura do banco e valem para o
        // ano inteiro, não para uma competência só: por isso entram
        // sempre, ao lado dos alertas mensais da competência escolhida.
        .or(`competencia.eq.${competencia},tipo.like.decimo_terceiro%`)
        .order("data_limite", { ascending: true }) as { data: any[] | null };
      return (data || []) as AlertaPrazo[];
    },
    enabled: !!tenantId,
  });

  // Varredura do 13º: roda no banco (prazo das parcelas, base de médias
  // incompleta, afastamento a validar) e é idempotente — o mesmo alerta
  // não nasce duas vezes. O agendamento diário faz isso sozinho; o botão
  // serve para conferir na hora.
  const [varrendo, setVarrendo] = useState(false);
  const varrer13 = async () => {
    if (!tenantId) return;
    setVarrendo(true);
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const rpc = (supabase as any).rpc.bind(supabase);
      const { data, error } = await rpc("decimo_terceiro_alertas_varrer", {
        p_tenant: tenantId,
        p_ano: Number(competencia.slice(0, 4)),
      });
      if (error) throw error;
      const novos = Number((data || {}).alertas_novos ?? 0);
      const acoes = Number((data || {}).acoes_criadas ?? 0);
      queryClient.invalidateQueries({ queryKey: ["folha-alertas"] });
      if (novos === 0) toast.info("13º: nenhum alerta novo — nada vencendo nem faltando.");
      else toast.success(`13º: ${novos} alerta(s)${acoes > 0 ? `, ${acoes} já com ação no Plano` : ""}.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível varrer os alertas do 13º");
    } finally {
      setVarrendo(false);
    }
  };

  const gerarAlertas = async () => {
    if (alertas.length > 0) {
      toast.info("Alertas já existem para esta competência.");
      return;
    }
    const novos = gerarAlertasPadrao(competencia).map(a => ({ ...a, tenant_id: tenantId }));
    await supabase.from("folha_alertas_prazo" as any).insert(novos as any);
    queryClient.invalidateQueries({ queryKey: ["folha-alertas"] });
    toast.success(`${novos.length} alertas criados para ${competencia}.`);
  };

  const concluir = async (id: string) => {
    await supabase.from("folha_alertas_prazo" as any).update({
      status: "concluido",
      concluido_em: new Date().toISOString(),
      concluido_por: profile?.nome_completo,
    } as any).eq("id", id);
    queryClient.invalidateQueries({ queryKey: ["folha-alertas"] });
    toast.success("Marcado como concluído.");
  };

  const statusBadge = (alerta: AlertaPrazo) => {
    if (alerta.status === "concluido") return <Badge className="bg-green-500/10 text-green-700 border-green-200"><CheckCircle className="w-3 h-3 mr-1" />Concluído</Badge>;
    const dias = differenceInDays(new Date(alerta.data_limite), new Date());
    if (dias < 0) return <Badge variant="destructive"><AlertTriangle className="w-3 h-3 mr-1" />Atrasado ({Math.abs(dias)}d)</Badge>;
    if (dias <= 5) return <Badge className="bg-yellow-500/10 text-yellow-700 border-yellow-200"><Clock className="w-3 h-3 mr-1" />{dias}d restantes</Badge>;
    return <Badge variant="outline"><Clock className="w-3 h-3 mr-1" />{dias}d</Badge>;
  };

  const resumo = useMemo(() => {
    const concluidos = alertas.filter(a => a.status === "concluido").length;
    const atrasados = alertas.filter(a => a.status !== "concluido" && isBefore(new Date(a.data_limite), new Date())).length;
    const pendentes = alertas.length - concluidos - atrasados;
    return { concluidos, atrasados, pendentes, total: alertas.length };
  }, [alertas]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Bell className="w-5 h-5 text-primary" /> Alertas de Prazo
          </h3>
          <p className="text-sm text-muted-foreground">Controle de prazos fiscais e trabalhistas da folha</p>
        </div>
        <div className="flex items-center gap-3">
          <CompetenciaInput value={competencia} onChange={setCompetencia} />
          <Button onClick={varrer13} size="sm" variant="outline" disabled={varrendo}>
            🎁 {varrendo ? "Varrendo..." : "Varrer 13º"}
          </Button>
          {alertas.length === 0 && (
            <Button onClick={gerarAlertas} size="sm">
              <Plus className="w-4 h-4 mr-1" /> Gerar Alertas
            </Button>
          )}
        </div>
      </div>

      {/* Cards resumo */}
      {resumo.total > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold">{resumo.total}</p><p className="text-xs text-muted-foreground">Total</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-green-600">{resumo.concluidos}</p><p className="text-xs text-muted-foreground">Concluídos</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-yellow-600">{resumo.pendentes}</p><p className="text-xs text-muted-foreground">Pendentes</p></CardContent></Card>
          <Card><CardContent className="p-4 text-center"><p className="text-2xl font-bold text-red-600">{resumo.atrasados}</p><p className="text-xs text-muted-foreground">Atrasados</p></CardContent></Card>
        </div>
      )}

      {/* Tabela */}
      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead></TableHead>
                <TableHead>Obrigação</TableHead>
                <TableHead>Descrição</TableHead>
                <TableHead>Prazo</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : alertas.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Clique em "Gerar Alertas" para criar os prazos desta competência.</TableCell></TableRow>
              ) : alertas.map((a) => (
                <TableRow key={a.id} className={a.status === "concluido" ? "opacity-60" : ""}>
                  <TableCell className="text-xl">{TIPO_ICONS[a.tipo] || "📌"}</TableCell>
                  <TableCell className="font-medium text-sm">{TIPO_LABELS[a.tipo] || a.tipo}</TableCell>
                  <TableCell className="text-sm text-muted-foreground max-w-xs truncate">{a.descricao}</TableCell>
                  <TableCell className="text-sm">{formatDateBR(a.data_limite, "dd/MM/yyyy")}</TableCell>
                  <TableCell className="text-center">{statusBadge(a)}</TableCell>
                  <TableCell>
                    {a.status !== "concluido" && (
                      <Button variant="ghost" size="sm" onClick={() => concluir(a.id)}>
                        <CheckCircle className="w-4 h-4 mr-1" /> Concluir
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
