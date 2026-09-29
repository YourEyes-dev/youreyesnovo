import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2, Target } from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import type { ContrapesoDev } from "@/data/mapaComportamentalRelatorio";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  colaboradorId: string;
  colaboradorNome: string;
  colaboradorCargo?: string | null;
  colaboradorDepartamento?: string | null;
  contrapesos: ContrapesoDev[];
  arquetipoLabel: string;
}

type Periodo = "trimestral" | "semestral" | "anual";
const MESES: Record<Periodo, number> = { trimestral: 3, semestral: 6, anual: 12 };
const PERIODO_LABEL: Record<Periodo, string> = {
  trimestral: "Trimestral (3 meses)", semestral: "Semestral (6 meses)", anual: "Anual (12 meses)",
};

function isoHoje(): string {
  return new Date().toISOString().slice(0, 10);
}
function isoMaisMeses(meses: number): string {
  const d = new Date();
  d.setMonth(d.getMonth() + meses);
  return d.toISOString().slice(0, 10);
}

export function CriarPdiMapaModal({
  open, onOpenChange, colaboradorId, colaboradorNome, colaboradorCargo, colaboradorDepartamento,
  contrapesos, arquetipoLabel,
}: Props) {
  const navigate = useNavigate();
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [idx, setIdx] = useState(0);
  const [periodo, setPeriodo] = useState<Periodo>("trimestral");
  const [salvando, setSalvando] = useState(false);

  const contrapeso = contrapesos[idx];

  const criar = async () => {
    if (!tenantId || !contrapeso) return;
    setSalvando(true);
    const dataInicio = isoHoje();
    const dataFim = isoMaisMeses(MESES[periodo]);
    try {
      // 1) PDI (contêiner) do próprio colaborador, já ativo.
      const { data: pdi, error: e1 } = await supabase
        .from("pdis")
        .insert({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          colaborador_id: colaboradorId,
          colaborador_nome: colaboradorNome,
          colaborador_cargo: colaboradorCargo || null,
          colaborador_departamento: colaboradorDepartamento || null,
          titulo: "Desenvolvimento a partir do Mapa Comportamental",
          descricao: `Plano de desenvolvimento derivado do Mapa Comportamental (perfil ${arquetipoLabel}). Foco em ampliar o repertório — não em trocar de perfil.`,
          periodo,
          data_inicio: dataInicio,
          data_fim: dataFim,
          status: "ativo",
          gatilho: "Mapa Comportamental",
          criado_por: user?.id,
          criado_por_nome: profile?.nome_completo,
        } as never)
        .select()
        .single();
      if (e1) throw e1;

      // 2) Meta comportamental a partir do contrapeso escolhido.
      const { error: e2 } = await supabase.from("pdi_metas").insert({
        tenant_id: tenantId,
        pdi_id: (pdi as { id: string }).id,
        titulo: contrapeso.nome,
        descricao: `Por que importa: ${contrapeso.porque}\nComo treinar: ${contrapeso.comoTreinar}`,
        categoria: "comportamental",
        temporal: PERIODO_LABEL[periodo],
        data_inicio: dataInicio,
        data_fim: dataFim,
      } as never);
      if (e2) throw e2;

      toast.success("Adicionado ao seu PDI!", { description: "Uma meta de desenvolvimento foi criada." });
      onOpenChange(false);
      navigate("/pdi");
    } catch (err) {
      console.error("Falha ao criar PDI a partir do mapa:", err);
      toast.error("Não foi possível adicionar ao PDI agora.");
    } finally {
      setSalvando(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Target className="w-5 h-5 text-indigo-600" /> Adicionar ao meu PDI
          </DialogTitle>
          <DialogDescription>
            Transforme um ponto de desenvolvimento do seu mapa em uma meta do seu Plano de Desenvolvimento
            Individual. O objetivo é ampliar o repertório, não trocar de perfil.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label>O que desenvolver</Label>
            <div className="space-y-2">
              {contrapesos.map((c, i) => (
                <button
                  key={c.nome}
                  type="button"
                  onClick={() => setIdx(i)}
                  className={`w-full text-left rounded-lg border p-3 transition ${
                    i === idx ? "border-indigo-400 bg-indigo-50/60 dark:bg-indigo-950/20" : "border-border hover:border-indigo-300"
                  }`}
                >
                  <p className="text-sm font-medium">{c.nome}</p>
                  <p className="text-xs text-muted-foreground mt-0.5">{c.porque}</p>
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-1">
            <Label>Prazo da meta</Label>
            <Select value={periodo} onValueChange={(v) => setPeriodo(v as Periodo)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {(Object.keys(PERIODO_LABEL) as Periodo[]).map((p) => (
                  <SelectItem key={p} value={p}>{PERIODO_LABEL[p]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={criar} disabled={salvando || !contrapeso} className="gap-1">
            {salvando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Target className="w-4 h-4" />}
            Criar meta no meu PDI
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
