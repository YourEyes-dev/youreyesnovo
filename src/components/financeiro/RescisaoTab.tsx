import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Plus, Calculator, Eye } from "lucide-react";
import { useFolhaCalculo } from "@/hooks/useFolhaCalculo";
import { useColaboradores } from "@/hooks/useColaboradores";
import { toast } from "sonner";
import { formatDateBR } from "@/lib/dataLocal";

const TIPOS_RESCISAO = [
  { value: "PEDIDO_DEMISSAO", label: "Pedido de Demissão" },
  { value: "DISPENSA_SEM_JUSTA_CAUSA", label: "Dispensa sem Justa Causa" },
  { value: "DISPENSA_COM_JUSTA_CAUSA", label: "Dispensa com Justa Causa" },
  { value: "CULPA_RECIPROCA", label: "Culpa Recíproca (metade das verbas)" },
  { value: "TERMINO_EXPERIENCIA", label: "Término de Experiência" },
  { value: "RESCISAO_INDIRETA", label: "Rescisão Indireta" },
  { value: "ACORDO_484A", label: "Acordo (Art. 484-A)" },
  { value: "FALECIMENTO", label: "Falecimento" },
  { value: "TERMINO_TEMPORARIO", label: "Término Temporário" },
  { value: "TERMINO_APRENDIZ", label: "Término Aprendiz" },
  { value: "ENCERRAMENTO_ESTAGIO", label: "Encerramento Estágio" },
];

const STATUS_RESCISAO: Record<string, { label: string; color: string }> = {
  em_calculo: { label: "Em Cálculo", color: "bg-yellow-100 text-yellow-800" },
  em_conferencia: { label: "Em Conferência", color: "bg-blue-100 text-blue-800" },
  aprovada: { label: "Aprovada", color: "bg-green-100 text-green-800" },
  paga: { label: "Paga", color: "bg-emerald-100 text-emerald-800" },
  reaberta: { label: "Reaberta", color: "bg-orange-100 text-orange-800" },
};

const fmtMoeda = (v: number) => (v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 });

export function RescisaoTab() {
  const { useRescisoes, criarRescisao, criandoRescisao, atualizarRescisao } = useFolhaCalculo();
  const { data: rescisoes = [], isLoading } = useRescisoes();
  const { colaboradores } = useColaboradores();
  const [showModal, setShowModal] = useState(false);
  const [showDetalhe, setShowDetalhe] = useState<any>(null);

  const [form, setForm] = useState({
    colaborador_id: "",
    colaborador_nome: "",
    colaborador_cpf: "",
    tipo_rescisao: "DISPENSA_SEM_JUSTA_CAUSA",
    data_desligamento: new Date().toISOString().split("T")[0],
    data_admissao: "",
    salario_base: 0,
    aviso_tipo: "indenizado",
    dias_aviso: 30,
    motivo: "",
    dependentes_irrf: 0,
  });

  const handleColabSelect = (id: string) => {
    const c = colaboradores.find((c: any) => c.id === id) as any;
    if (c) {
      setForm(p => ({
        ...p,
        colaborador_id: c.id,
        colaborador_nome: c.nome_completo,
        colaborador_cpf: c.cpf,
        data_admissao: c.data_admissao || "",
        salario_base: c.salario || 0,
      }));
    }
  };

  const handleCalcular = async () => {
    if (!form.colaborador_nome || !form.data_admissao) return toast.error("Selecione o colaborador e preencha a data de admissão");
    await criarRescisao(form);
    setShowModal(false);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Calculator className="w-5 h-5 text-primary" /> Rescisões
          </h3>
          <p className="text-sm text-muted-foreground">Cálculo de verbas rescisórias por tipo de desligamento</p>
        </div>
        <Button onClick={() => setShowModal(true)}>
          <Plus className="w-4 h-4 mr-2" /> Nova Rescisão
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Data Deslig.</TableHead>
                <TableHead className="text-right">Bruto</TableHead>
                <TableHead className="text-right">Descontos</TableHead>
                <TableHead className="text-right">Líquido</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : rescisoes.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhuma rescisão registrada.</TableCell></TableRow>
              ) : rescisoes.map((r: any) => {
                const st = STATUS_RESCISAO[r.status] || STATUS_RESCISAO.em_calculo;
                const tipo = TIPOS_RESCISAO.find(t => t.value === r.tipo_rescisao);
                return (
                  <TableRow key={r.id}>
                    <TableCell className="font-medium">{r.colaborador_nome}</TableCell>
                    <TableCell className="text-sm">{tipo?.label || r.tipo_rescisao}</TableCell>
                    <TableCell>{formatDateBR(r.data_desligamento)}</TableCell>
                    <TableCell className="text-right">R$ {fmtMoeda(r.total_bruto)}</TableCell>
                    <TableCell className="text-right text-destructive">R$ {fmtMoeda(r.total_descontos)}</TableCell>
                    <TableCell className="text-right font-bold">R$ {fmtMoeda(r.total_liquido)}</TableCell>
                    <TableCell className="text-center"><Badge className={st.color + " text-xs"}>{st.label}</Badge></TableCell>
                    <TableCell>
                      <Button variant="ghost" size="icon" onClick={() => setShowDetalhe(r)}>
                        <Eye className="w-4 h-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Modal Nova Rescisão */}
      <Dialog open={showModal} onOpenChange={setShowModal}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Nova Rescisão</DialogTitle>
            <DialogDescription>Preencha os dados para calcular as verbas rescisórias</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Colaborador *</Label>
              <Select value={form.colaborador_id} onValueChange={handleColabSelect}>
                <SelectTrigger><SelectValue placeholder="Selecione..." /></SelectTrigger>
                <SelectContent>
                  {colaboradores.map((c: any) => (
                    <SelectItem key={c.id} value={c.id}>{c.nome_completo}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Tipo de Rescisão *</Label>
                <Select value={form.tipo_rescisao} onValueChange={v => setForm(p => ({ ...p, tipo_rescisao: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{TIPOS_RESCISAO.map(t => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Aviso Prévio</Label>
                <Select value={form.aviso_tipo} onValueChange={v => setForm(p => ({ ...p, aviso_tipo: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="indenizado">Indenizado</SelectItem>
                    <SelectItem value="trabalhado">Trabalhado</SelectItem>
                    <SelectItem value="dispensado">Dispensado</SelectItem>
                    <SelectItem value="nao_aplicavel">Não aplicável</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Data Admissão *</Label>
                <Input type="date" value={form.data_admissao} onChange={e => setForm(p => ({ ...p, data_admissao: e.target.value }))} />
              </div>
              <div className="space-y-2">
                <Label>Data Desligamento *</Label>
                <Input type="date" value={form.data_desligamento} onChange={e => setForm(p => ({ ...p, data_desligamento: e.target.value }))} />
              </div>
              <div className="space-y-2">
                <Label>Salário Base</Label>
                <Input type="number" step="0.01" value={form.salario_base} onChange={e => setForm(p => ({ ...p, salario_base: Number(e.target.value) }))} />
              </div>
            </div>
            <div className="space-y-2">
              <Label>Motivo</Label>
              <Input value={form.motivo} onChange={e => setForm(p => ({ ...p, motivo: e.target.value }))} placeholder="Motivo do desligamento" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowModal(false)}>Cancelar</Button>
            <Button onClick={handleCalcular} disabled={criandoRescisao}>
              {criandoRescisao ? "Calculando..." : "Calcular Rescisão"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Modal Detalhe Rescisão */}
      <Dialog open={!!showDetalhe} onOpenChange={() => setShowDetalhe(null)}>
        <DialogContent className="sm:max-w-2xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Detalhes da Rescisão — {showDetalhe?.colaborador_nome}</DialogTitle>
          </DialogHeader>
          {showDetalhe && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div><span className="text-muted-foreground">Tipo:</span> <span className="font-medium">{TIPOS_RESCISAO.find(t => t.value === showDetalhe.tipo_rescisao)?.label}</span></div>
                <div><span className="text-muted-foreground">Data:</span> <span className="font-medium">{formatDateBR(showDetalhe.data_desligamento)}</span></div>
                <div><span className="text-muted-foreground">Prazo Legal:</span> <span className="font-medium">{showDetalhe.prazo_legal ? new Date(showDetalhe.prazo_legal).toLocaleDateString("pt-BR") : "—"}</span></div>
                <div><span className="text-muted-foreground">Aviso:</span> <span className="font-medium">{showDetalhe.aviso_tipo || "—"}</span></div>
              </div>

              <Card>
                <CardHeader><CardTitle className="text-base">Verbas Rescisórias</CardTitle></CardHeader>
                <CardContent className="space-y-2 text-sm">
                  {[
                    { label: "Saldo de Salário", valor: showDetalhe.saldo_salario, info: `${showDetalhe.dias_saldo || 0} dias` },
                    { label: "Aviso Prévio", valor: showDetalhe.aviso_previo_valor },
                    { label: "Férias Vencidas", valor: showDetalhe.ferias_vencidas },
                    { label: "Férias Proporcionais", valor: showDetalhe.ferias_proporcionais },
                    { label: "1/3 de Férias", valor: showDetalhe.terco_ferias },
                    { label: "13º Proporcional", valor: showDetalhe.decimo_terceiro_proporcional },
                  ].filter(v => v.valor > 0).map((v, i) => (
                    <div key={i} className="flex justify-between">
                      <span>{v.label} {v.info && <span className="text-muted-foreground">({v.info})</span>}</span>
                      <span className="font-medium text-emerald-600">R$ {fmtMoeda(v.valor)}</span>
                    </div>
                  ))}
                  <div className="border-t pt-2 flex justify-between font-semibold">
                    <span>Total Bruto</span>
                    <span>R$ {fmtMoeda(showDetalhe.total_bruto)}</span>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader><CardTitle className="text-base">Descontos e Encargos</CardTitle></CardHeader>
                <CardContent className="space-y-2 text-sm">
                  <div className="flex justify-between"><span>INSS (base: R$ {fmtMoeda(showDetalhe.base_inss)})</span><span className="text-destructive">- R$ {fmtMoeda(showDetalhe.valor_inss)}</span></div>
                  <div className="flex justify-between"><span>IRRF (base: R$ {fmtMoeda(showDetalhe.base_irrf)})</span><span className="text-destructive">- R$ {fmtMoeda(showDetalhe.valor_irrf)}</span></div>
                  <div className="flex justify-between"><span>FGTS (base: R$ {fmtMoeda(showDetalhe.base_fgts)})</span><span className="text-muted-foreground">R$ {fmtMoeda(showDetalhe.valor_fgts)}</span></div>
                  {showDetalhe.multa_fgts > 0 && (
                    <div className="flex justify-between"><span>Multa FGTS ({showDetalhe.aliquota_multa_fgts}%)</span><span className="text-muted-foreground">R$ {fmtMoeda(showDetalhe.multa_fgts)}</span></div>
                  )}
                  <div className="border-t pt-2 flex justify-between font-semibold">
                    <span>Total Descontos</span>
                    <span className="text-destructive">R$ {fmtMoeda(showDetalhe.total_descontos)}</span>
                  </div>
                </CardContent>
              </Card>

              <div className="bg-primary/5 rounded-xl p-4 flex justify-between items-center">
                <span className="text-lg font-semibold">Líquido a Receber</span>
                <span className="text-2xl font-bold text-primary">R$ {fmtMoeda(showDetalhe.total_liquido)}</span>
              </div>

              <div className="flex gap-2">
                {showDetalhe.status === "em_calculo" && (
                  <Button size="sm" onClick={() => { atualizarRescisao({ id: showDetalhe.id, status: "em_conferencia" }); setShowDetalhe(null); }}>
                    Enviar para Conferência
                  </Button>
                )}
                {showDetalhe.status === "em_conferencia" && (
                  <Button size="sm" onClick={() => { atualizarRescisao({ id: showDetalhe.id, status: "aprovada" }); setShowDetalhe(null); }}>
                    Aprovar
                  </Button>
                )}
                {showDetalhe.status === "aprovada" && (
                  <Button size="sm" onClick={() => { atualizarRescisao({ id: showDetalhe.id, status: "paga", data_pagamento: new Date().toISOString().split("T")[0] }); setShowDetalhe(null); }}>
                    Marcar como Paga
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
