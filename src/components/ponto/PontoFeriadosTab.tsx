import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { motion } from "framer-motion";
import { CalendarDays, Plus, Pencil, Trash2, Loader2, Info, Repeat } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { confirm } from "@/components/ui/confirm-dialog";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";
import { useEmpresaCadastro } from "@/hooks/useEmpresaCadastro";
import { FeriadoFormDialog } from "./FeriadoFormDialog";
import { FeriadoTabelasPanel } from "./FeriadoTabelasPanel";
import {
  type Feriado, type FeriadoForm, dataEfetiva, incideNoAno,
  validarFeriado, payloadFeriado, LABEL_ABRANGENCIA,
} from "@/lib/ponto/feriados";

const BADGE_ABRANGENCIA: Record<string, string> = {
  nacional: "bg-slate-100 text-slate-800 hover:bg-slate-100",
  estadual: "bg-blue-100 text-blue-800 hover:bg-blue-100",
  municipal: "bg-amber-100 text-amber-800 hover:bg-amber-100",
  filial: "bg-violet-100 text-violet-800 hover:bg-violet-100",
};

export function PontoFeriadosTab() {
  const { tenantId } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const { empresas } = useEmpresaCadastro();

  const currentYear = new Date().getFullYear();
  const [ano, setAno] = useState<number>(currentYear);
  const [unidadeFiltro, setUnidadeFiltro] = useState<string>("todas");
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Feriado | null>(null);
  const [reconsolidando, setReconsolidando] = useState(false);

  const unidades = useMemo(
    () => (empresas || []).map((e) => ({
      id: e.id as string,
      nome: (e.nome_fantasia || e.razao_social || "Unidade") as string,
    })),
    [empresas],
  );
  const nomeUnidade = (id: string | null) =>
    unidades.find((u) => u.id === id)?.nome || "—";

  const { data: todos = [], isLoading } = useQuery({
    queryKey: ["feriados", tenantId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("feriados" as any)
        .select("*")
        .order("mes", { ascending: true })
        .order("dia", { ascending: true });
      if (error) throw error;
      return (data || []) as unknown as Feriado[];
    },
    enabled: !!tenantId,
  });

  const feriados = useMemo(() => {
    return todos
      .filter((f) => incideNoAno(f, ano))
      .filter((f) => unidadeFiltro === "todas"
        || f.abrangencia !== "filial"
        || f.empresa_id === unidadeFiltro)
      .sort((a, b) => (dataEfetiva(a, ano) || "").localeCompare(dataEfetiva(b, ano) || ""));
  }, [todos, ano, unidadeFiltro]);

  const anos = useMemo(() => {
    const arr: number[] = [];
    for (let y = currentYear - 2; y <= currentYear + 3; y++) arr.push(y);
    return arr;
  }, [currentYear]);

  const reconsolidarDia = async (data: string | null) => {
    if (!tenantId || !data) return;
    setReconsolidando(true);
    try {
      const { error } = await supabase.rpc("consolidar_ponto_dia_todos" as any, {
        p_tenant_id: tenantId, p_data: data,
      } as any);
      if (error) throw error;
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
    } catch (e) {
      toast({
        title: "Falha ao reconsolidar espelho",
        description: e instanceof Error ? e.message : "Tente novamente.",
        variant: "destructive",
      });
    } finally {
      setReconsolidando(false);
    }
  };

  const salvarMutation = useMutation({
    mutationFn: async (form: FeriadoForm) => {
      if (!tenantId) throw new Error("Tenant não identificado.");
      const erro = validarFeriado(form);
      if (erro) throw new Error(erro);

      const payload = payloadFeriado(form, tenantId);
      if (editing) {
        const { error } = await supabase.from("feriados" as any)
          .update(payload as any).eq("id", editing.id);
        if (error) throw error;
        return { atual: payload.data, anterior: editing.data };
      }
      const { error } = await supabase.from("feriados" as any).insert(payload as any);
      if (error) throw error;
      return { atual: payload.data, anterior: null as string | null };
    },
    onSuccess: async ({ atual, anterior }) => {
      toast({ title: editing ? "Feriado atualizado" : "Feriado adicionado" });
      setShowForm(false);
      setEditing(null);
      queryClient.invalidateQueries({ queryKey: ["feriados"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-equalizacao"] });
      await reconsolidarDia(atual);
      if (anterior && anterior !== atual) await reconsolidarDia(anterior);
    },
    onError: (e: Error) => {
      toast({ title: "Erro ao salvar", description: e.message, variant: "destructive" });
    },
  });

  const excluirMutation = useMutation({
    mutationFn: async (f: Feriado) => {
      const { error } = await supabase.from("feriados" as any).delete().eq("id", f.id);
      if (error) throw error;
      return dataEfetiva(f, ano);
    },
    onSuccess: async (data) => {
      toast({ title: "Feriado excluído" });
      queryClient.invalidateQueries({ queryKey: ["feriados"] });
      await reconsolidarDia(data);
    },
    onError: (e: Error) => {
      toast({ title: "Erro ao excluir", description: e.message, variant: "destructive" });
    },
  });

  return (
    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="space-y-4">
      <FeriadoTabelasPanel />

      <Card>
        <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <CardTitle className="flex items-center gap-2 text-lg">
              <CalendarDays className="h-5 w-5 text-primary" />
              Feriados por localização
            </CardTitle>
            <CardDescription>
              Estaduais e municipais (com recorrência anual); os nacionais são fornecidos pelo sistema. Feriado específico de uma unidade fica no Calendário da unidade, acima.
            </CardDescription>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Label className="text-xs text-muted-foreground">Unidade</Label>
            <Select value={unidadeFiltro} onValueChange={setUnidadeFiltro}>
              <SelectTrigger className="w-[200px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="todas">Todas as unidades</SelectItem>
                {unidades.map((u) => (
                  <SelectItem key={u.id} value={u.id}>{u.nome}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Label className="text-xs text-muted-foreground">Ano</Label>
            <Select value={String(ano)} onValueChange={(v) => setAno(Number(v))}>
              <SelectTrigger className="w-[100px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                {anos.map((y) => (<SelectItem key={y} value={String(y)}>{y}</SelectItem>))}
              </SelectContent>
            </Select>
            <Button onClick={() => { setEditing(null); setShowForm(true); }} size="sm">
              <Plus className="h-4 w-4 mr-1" /> Adicionar feriado
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {reconsolidando && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground mb-3 p-2 rounded bg-muted/40">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              Reconsolidando espelho de ponto dos colaboradores… isso pode levar alguns segundos.
            </div>
          )}
          <div className="rounded-md border overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[110px]">Data</TableHead>
                  <TableHead>Nome</TableHead>
                  <TableHead className="w-[120px]">Abrangência</TableHead>
                  <TableHead>Unidade / local</TableHead>
                  <TableHead className="w-[110px]">Tipo</TableHead>
                  <TableHead className="w-[110px] text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isLoading ? (
                  <TableRow>
                    <TableCell colSpan={6} className="text-center py-6 text-muted-foreground">
                      <Loader2 className="h-4 w-4 animate-spin inline mr-2" /> Carregando…
                    </TableCell>
                  </TableRow>
                ) : feriados.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6} className="text-center py-6 text-muted-foreground">
                      Nenhum feriado para {ano}.
                    </TableCell>
                  </TableRow>
                ) : (
                  feriados.map((f) => {
                    // 'filial' legada é somente-leitura: a abrangência foi unificada
                    // no Calendário da unidade; novas não são criadas por aqui.
                    const somenteLeitura = !f.tenant_id || f.abrangencia === "nacional" || f.abrangencia === "filial";
                    const efetiva = dataEfetiva(f, ano);
                    const local = f.abrangencia === "filial"
                      ? nomeUnidade(f.empresa_id)
                      : [f.municipio, f.uf].filter(Boolean).join(" / ") || "—";
                    return (
                      <TableRow key={f.id} className={!f.ativo ? "opacity-60" : ""}>
                        <TableCell className="font-mono text-xs">
                          <div className="flex items-center gap-1">
                            {efetiva ? new Date(efetiva + "T00:00:00").toLocaleDateString("pt-BR") : "—"}
                            {f.recorrente && (
                              <Repeat className="h-3 w-3 text-muted-foreground" aria-label="Recorrente" />
                            )}
                          </div>
                        </TableCell>
                        <TableCell className="font-medium">{f.nome}</TableCell>
                        <TableCell>
                          <Badge className={BADGE_ABRANGENCIA[f.abrangencia]}>
                            {LABEL_ABRANGENCIA[f.abrangencia]}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs">{local}</TableCell>
                        <TableCell>
                          {f.tipo === "facultativo" ? (
                            <Badge variant="outline">Facultativo</Badge>
                          ) : (
                            <Badge className="bg-teal-100 text-teal-800 hover:bg-teal-100">Feriado</Badge>
                          )}
                        </TableCell>
                        <TableCell className="text-right">
                          {somenteLeitura ? (
                            <span className="text-xs text-muted-foreground inline-flex items-center gap-1">
                              <Info className="h-3 w-3" /> Somente leitura
                            </span>
                          ) : (
                            <div className="flex items-center justify-end gap-1">
                              <Button size="icon" variant="ghost" aria-label="Editar"
                                onClick={() => { setEditing(f); setShowForm(true); }}>
                                <Pencil className="h-4 w-4" />
                              </Button>
                              <Button
                                size="icon" variant="ghost" aria-label="Excluir"
                                onClick={async () => {
                                  const ok = await confirm({
                                    title: "Excluir feriado?",
                                    description: `Esta ação remove "${f.nome}" e reconsolida o espelho do dia.`,
                                    confirmLabel: "Excluir",
                                    variant: "destructive",
                                  });
                                  if (ok) excluirMutation.mutate(f);
                                }}
                              >
                                <Trash2 className="h-4 w-4 text-destructive" />
                              </Button>
                            </div>
                          )}
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <FeriadoFormDialog
        open={showForm}
        onOpenChange={(v) => { setShowForm(v); if (!v) setEditing(null); }}
        editing={editing}
        salvando={salvarMutation.isPending}
        onSubmit={(form) => salvarMutation.mutate(form)}
      />
    </motion.div>
  );
}
