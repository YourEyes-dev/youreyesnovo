import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useTenant } from "@/hooks/useTenant";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Scale, Edit, ArrowRightLeft, Info } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { rpcUntyped } from "@/integrations/supabase/untypedClient";
import { toast } from "sonner";
import { format } from "date-fns";

interface CCTForm {
  nome: string;
  sindicato: string;
  categoria_profissional: string;
  vigencia_inicio: string;
  vigencia_fim: string;
  jornada_semanal_horas: number;
  jornada_diaria_horas: number;
  he_percentual_dia_util: number;
  he_percentual_domingos: number;
  he_percentual_feriados: number;
  he_limite_diario_min: number;
  adicional_noturno_percentual: number;
  hora_noturna_inicio: string;
  hora_noturna_fim: string;
  usa_hora_ficta: boolean;
  intervalo_minimo_min: number;
  intervalo_maximo_min: number;
  banco_horas_permitido: boolean;
  banco_horas_prazo_compensacao_meses: number;
  dsr_proporcional: boolean;
  observacoes: string;
}

const defaultForm: CCTForm = {
  nome: "",
  sindicato: "",
  categoria_profissional: "",
  vigencia_inicio: "",
  vigencia_fim: "",
  jornada_semanal_horas: 44,
  jornada_diaria_horas: 8,
  he_percentual_dia_util: 50,
  he_percentual_domingos: 100,
  he_percentual_feriados: 100,
  he_limite_diario_min: 120,
  adicional_noturno_percentual: 20,
  hora_noturna_inicio: "22:00",
  hora_noturna_fim: "05:00",
  usa_hora_ficta: true,
  intervalo_minimo_min: 60,
  intervalo_maximo_min: 120,
  banco_horas_permitido: true,
  banco_horas_prazo_compensacao_meses: 6,
  dsr_proporcional: true,
  observacoes: "",
};

export function PontoCCTTab() {
  const { tenantId } = useTenant();
  const queryClient = useQueryClient();
  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<CCTForm>(defaultForm);
  const [salvando, setSalvando] = useState(false);

  const { data: ccts = [], isLoading } = useQuery({
    queryKey: ["ponto-cct-config", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_cct_config")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const handleEditar = (cct: any) => {
    setForm({
      nome: cct.nome || "",
      sindicato: cct.sindicato || "",
      categoria_profissional: cct.categoria_profissional || "",
      vigencia_inicio: cct.vigencia_inicio || "",
      vigencia_fim: cct.vigencia_fim || "",
      jornada_semanal_horas: cct.jornada_semanal_horas || 44,
      jornada_diaria_horas: cct.jornada_diaria_horas || 8,
      he_percentual_dia_util: cct.he_percentual_dia_util || 50,
      he_percentual_domingos: cct.he_percentual_domingos || 100,
      he_percentual_feriados: cct.he_percentual_feriados || 100,
      he_limite_diario_min: cct.he_limite_diario_min || 120,
      adicional_noturno_percentual: cct.adicional_noturno_percentual || 20,
      hora_noturna_inicio: cct.hora_noturna_inicio || "22:00",
      hora_noturna_fim: cct.hora_noturna_fim || "05:00",
      usa_hora_ficta: cct.usa_hora_ficta ?? true,
      intervalo_minimo_min: cct.intervalo_minimo_min || 60,
      intervalo_maximo_min: cct.intervalo_maximo_min || 120,
      banco_horas_permitido: cct.banco_horas_permitido ?? true,
      banco_horas_prazo_compensacao_meses: cct.banco_horas_prazo_compensacao_meses || 6,
      dsr_proporcional: cct.dsr_proporcional ?? true,
      observacoes: cct.observacoes || "",
    });
    setEditId(cct.id);
    setShowModal(true);
  };

  const handleSalvar = async () => {
    if (!form.nome || !tenantId) {
      toast.error("Nome da CCT é obrigatório");
      return;
    }
    setSalvando(true);
    try {
      if (!editId) return;
      // Só os parâmetros que o cálculo ainda lê desta tela (jornada diária, % de
      // hora extra, horário noturno e hora ficta, vigência). O resto mudou para
      // Convenções e acordos e para a configuração do banco de horas.
      const payload = {
        vigencia_inicio: form.vigencia_inicio || null,
        vigencia_fim: form.vigencia_fim || null,
        jornada_diaria_horas: form.jornada_diaria_horas,
        he_percentual_dia_util: form.he_percentual_dia_util,
        he_percentual_domingos: form.he_percentual_domingos,
        he_percentual_feriados: form.he_percentual_feriados,
        hora_noturna_inicio: form.hora_noturna_inicio,
        hora_noturna_fim: form.hora_noturna_fim,
        usa_hora_ficta: form.usa_hora_ficta,
      };
      const { error } = await fromTable("ponto_cct_config").update(payload as any).eq("id", editId);
      if (error) throw error;
      toast.success("Parâmetros atualizados");

      queryClient.invalidateQueries({ queryKey: ["ponto-cct-config"] });
      setShowModal(false);
    } catch (err: any) {
      toast.error(err.message || "Erro ao salvar");
    } finally {
      setSalvando(false);
    }
  };

  // Traz a CCT para o cadastro novo (Convenções e acordos). O instrumento nasce
  // INATIVO: ativar é decisão do RH, porque instrumento coletivo ativo já conta
  // para 12x36 e registro alternativo.
  const handleImportar = async (cct: any) => {
    const { data, error } = await rpcUntyped("ponto_importar_cct_legado", { p_cct_id: cct.id });
    if (error || !data?.ok) { toast.error(error?.message || "Não foi possível trazer a CCT"); return; }
    toast.success(data.ja_importada
      ? "Esta CCT já está no novo cadastro."
      : "CCT copiada para Convenções e acordos (inativa). Revise lá os sindicatos, as empresas e o documento, e ative.");
    queryClient.invalidateQueries({ queryKey: ["ponto-cct-config"] });
    queryClient.invalidateQueries({ queryKey: ["ponto-acordos"] });
  };

  const updateForm = (field: keyof CCTForm, value: any) => setForm(prev => ({ ...prev, [field]: value }));

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-lg font-semibold flex items-center gap-2">
          <Scale className="w-5 h-5 text-primary" /> CCT (configuração antiga)
        </h3>
        <p className="text-sm text-muted-foreground">Somente leitura. Mostra as convenções do cadastro antigo.</p>
      </div>

      <Alert className="border-sky-500/40 bg-sky-50 dark:bg-sky-950/20">
        <Info className="h-4 w-4" />
        <AlertDescription className="text-sm">
          As convenções agora são cadastradas em <strong>Compliance → Convenções e acordos</strong>, onde cabe mais de
          uma por empresa (atividade principal e categorias diferenciadas), com sindicatos, abrangência e documento.
          Use "Trazer para o novo cadastro" em cada linha. Enquanto a próxima etapa não chega, o cálculo ainda lê
          daqui a jornada diária, os percentuais de hora extra e o horário noturno — por isso eles continuam editáveis.
        </AlertDescription>
      </Alert>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nome</TableHead>
                <TableHead>Sindicato</TableHead>
                <TableHead>Categoria</TableHead>
                <TableHead className="text-center">Jornada</TableHead>
                <TableHead className="text-center">HE Dia Útil</TableHead>
                <TableHead className="text-center">HE Dom/Fer</TableHead>
                <TableHead className="text-center">Vigência</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : ccts.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nada no cadastro antigo. Use Convenções e acordos.</TableCell></TableRow>
              ) : ccts.map((cct: any) => (
                <TableRow key={cct.id}>
                  <TableCell className="font-medium">{cct.nome}</TableCell>
                  <TableCell>{cct.sindicato || "—"}</TableCell>
                  <TableCell>{cct.categoria_profissional || "—"}</TableCell>
                  <TableCell className="text-center">{cct.jornada_diaria_horas}h/dia</TableCell>
                  <TableCell className="text-center">{cct.he_percentual_dia_util}%</TableCell>
                  <TableCell className="text-center">{cct.he_percentual_domingos}% / {cct.he_percentual_feriados}%</TableCell>
                  <TableCell className="text-center">
                    {cct.vigencia_inicio && cct.vigencia_fim
                      ? `${format(new Date(cct.vigencia_inicio), "MM/yy")} — ${format(new Date(cct.vigencia_fim), "MM/yy")}`
                      : <Badge variant="outline">Sem vigência</Badge>}
                  </TableCell>
                  <TableCell className="text-center">
                    <div className="flex items-center justify-center gap-1">
                      <Button variant="ghost" size="icon" title="Parâmetros que o cálculo ainda usa" onClick={() => handleEditar(cct)}><Edit className="w-4 h-4" /></Button>
                      {cct.instrumento_id ? (
                        <Badge variant="outline" className="text-[10px]">no novo cadastro</Badge>
                      ) : (
                        <Button variant="ghost" size="sm" onClick={() => handleImportar(cct)}>
                          <ArrowRightLeft className="w-4 h-4 mr-1" /> Trazer para o novo cadastro
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={showModal} onOpenChange={setShowModal}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Parâmetros que o cálculo ainda usa — {form.nome}</DialogTitle>
          </DialogHeader>
          <div className="space-y-6">
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-2">
                <Label>Vigência início</Label>
                <Input type="date" value={form.vigencia_inicio} onChange={e => updateForm("vigencia_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Vigência fim</Label>
                <Input type="date" value={form.vigencia_fim} onChange={e => updateForm("vigencia_fim", e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="space-y-2">
                <Label>Jornada diária (h)</Label>
                <Input type="number" value={form.jornada_diaria_horas} onChange={e => updateForm("jornada_diaria_horas", Number(e.target.value))} />
              </div>
              <div className="space-y-2">
                <Label>% HE dia útil</Label>
                <Input type="number" value={form.he_percentual_dia_util} onChange={e => updateForm("he_percentual_dia_util", Number(e.target.value))} />
              </div>
              <div className="space-y-2">
                <Label>% HE domingos</Label>
                <Input type="number" value={form.he_percentual_domingos} onChange={e => updateForm("he_percentual_domingos", Number(e.target.value))} />
              </div>
              <div className="space-y-2">
                <Label>% HE feriados</Label>
                <Input type="number" value={form.he_percentual_feriados} onChange={e => updateForm("he_percentual_feriados", Number(e.target.value))} />
              </div>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Noturno: início</Label>
                <Input type="time" value={form.hora_noturna_inicio} onChange={e => updateForm("hora_noturna_inicio", e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Noturno: fim</Label>
                <Input type="time" value={form.hora_noturna_fim} onChange={e => updateForm("hora_noturna_fim", e.target.value)} />
              </div>
              <div className="flex items-center gap-2 pt-6">
                <Switch checked={form.usa_hora_ficta} onCheckedChange={v => updateForm("usa_hora_ficta", v)} />
                <Label>Hora ficta (52m30s)</Label>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowModal(false)}>Cancelar</Button>
            <Button onClick={handleSalvar} disabled={salvando}>{salvando ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
