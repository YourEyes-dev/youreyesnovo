import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { UFS, MESES, type Feriado, type FeriadoForm, formVazioFeriado } from "@/lib/ponto/feriados";

export interface FeriadoFormDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  editing: Feriado | null;
  salvando: boolean;
  onSubmit: (form: FeriadoForm) => void;
}

/** Formulário de feriado por localização: estadual ou municipal + recorrência anual.
 *  Feriado específico de uma unidade mora no Calendário da unidade, não aqui. */
export function FeriadoFormDialog({
  open, onOpenChange, editing, salvando, onSubmit,
}: FeriadoFormDialogProps) {
  const [form, setForm] = useState<FeriadoForm>(formVazioFeriado());

  useEffect(() => {
    if (!open) return;
    setForm(editing
      ? {
          data: editing.data || "",
          nome: editing.nome,
          abrangencia: editing.abrangencia === "municipal" ? "municipal" : "estadual",
          uf: editing.uf || "",
          municipio: editing.municipio || "",
          codigo_ibge: editing.codigo_ibge || "",
          empresa_id: editing.empresa_id || "",
          tipo: editing.tipo,
          recorrente: editing.recorrente,
          dia: editing.dia ? String(editing.dia) : "",
          mes: editing.mes ? String(editing.mes) : "",
          ativo: editing.ativo,
        }
      : formVazioFeriado());
  }, [open, editing]);

  const set = (patch: Partial<FeriadoForm>) => setForm((f) => ({ ...f, ...patch }));

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{editing ? "Editar feriado" : "Adicionar feriado"}</DialogTitle>
          <DialogDescription>
            Feriados estaduais e municipais (por localização). Para um feriado só de uma unidade, use o Calendário da unidade. Após salvar, o espelho de ponto é reconsolidado.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="flex items-center justify-between rounded-md border p-3">
            <div>
              <Label className="text-sm">Recorrente todo ano</Label>
              <p className="text-xs text-muted-foreground">
                Repete no mesmo dia/mês em todos os anos (ex.: aniversário do município).
              </p>
            </div>
            <Switch checked={form.recorrente} onCheckedChange={(v) => set({ recorrente: v })} />
          </div>

          <div className="grid grid-cols-2 gap-3">
            {form.recorrente ? (
              <>
                <div className="space-y-1">
                  <Label>Dia</Label>
                  <Input
                    type="number" min={1} max={31} value={form.dia}
                    onChange={(e) => set({ dia: e.target.value })}
                  />
                </div>
                <div className="space-y-1">
                  <Label>Mês</Label>
                  <Select value={form.mes} onValueChange={(v) => set({ mes: v })}>
                    <SelectTrigger><SelectValue placeholder="Mês" /></SelectTrigger>
                    <SelectContent>
                      {MESES.map((m, i) => (
                        <SelectItem key={m} value={String(i + 1)}>{m}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </>
            ) : (
              <div className="space-y-1">
                <Label>Data</Label>
                <Input type="date" value={form.data} onChange={(e) => set({ data: e.target.value })} />
              </div>
            )}
            <div className="space-y-1">
              <Label>Tipo</Label>
              <Select value={form.tipo} onValueChange={(v) => set({ tipo: v as FeriadoForm["tipo"] })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="feriado">Feriado</SelectItem>
                  <SelectItem value="facultativo">Facultativo</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-1">
            <Label>Nome</Label>
            <Input
              value={form.nome}
              onChange={(e) => set({ nome: e.target.value })}
              placeholder="Ex.: Aniversário do município"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Abrangência</Label>
              <Select
                value={form.abrangencia}
                onValueChange={(v) => set({ abrangencia: v as FeriadoForm["abrangencia"] })}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="estadual">Estadual</SelectItem>
                  <SelectItem value="municipal">Municipal</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>UF</Label>
              <Select value={form.uf} onValueChange={(v) => set({ uf: v })}>
                <SelectTrigger><SelectValue placeholder="UF" /></SelectTrigger>
                <SelectContent>
                  {UFS.map((u) => (<SelectItem key={u} value={u}>{u}</SelectItem>))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {form.abrangencia === "municipal" && (
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>Município</Label>
                <Input value={form.municipio} onChange={(e) => set({ municipio: e.target.value })} />
              </div>
              <div className="space-y-1">
                <Label>Código IBGE (opcional)</Label>
                <Input value={form.codigo_ibge} onChange={(e) => set({ codigo_ibge: e.target.value })} />
              </div>
            </div>
          )}

          <div className="flex items-center justify-between rounded-md border p-3">
            <Label className="text-sm">Ativo</Label>
            <Switch checked={form.ativo} onCheckedChange={(v) => set({ ativo: v })} />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={() => onSubmit(form)} disabled={salvando}>
            {salvando ? "Salvando…" : "Salvar"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
