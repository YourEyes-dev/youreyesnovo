import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Loader2, Plus } from "lucide-react";
import { useCargos, useDepartamentos } from "@/hooks/useCadastros";

interface CriarFuncaoRapidaDialogProps {
  open: boolean;
  onClose: () => void;
  /** Chamado com o id do cargo recém-criado, para já abrir o detalhe. */
  onCreated: (cargoId: string) => void;
}

const NIVEIS: { value: string; label: string }[] = [
  { value: "operacional", label: "Operacional" },
  { value: "tatico", label: "Tático" },
  { value: "estrategico", label: "Estratégico" },
];

// Sentinela para "sem departamento" — o Select do shadcn não aceita value vazio.
const SEM_DEPARTAMENTO = "__nenhum__";

export function CriarFuncaoRapidaDialog({ open, onClose, onCreated }: CriarFuncaoRapidaDialogProps) {
  const { createCargo } = useCargos();
  const { departamentos } = useDepartamentos();

  const [nome, setNome] = useState("");
  const [nivel, setNivel] = useState<string>("");
  const [departamentoId, setDepartamentoId] = useState<string>(SEM_DEPARTAMENTO);

  const salvando = createCargo.isPending;

  const resetar = () => {
    setNome("");
    setNivel("");
    setDepartamentoId(SEM_DEPARTAMENTO);
  };

  const handleFechar = () => {
    if (salvando) return;
    resetar();
    onClose();
  };

  const handleSalvar = async () => {
    const nomeLimpo = nome.trim();
    if (!nomeLimpo) return;

    const novo = await createCargo.mutateAsync({
      nome: nomeLimpo,
      nivel: nivel || null,
      departamento_id: departamentoId === SEM_DEPARTAMENTO ? null : departamentoId,
      descricao: null,
      ativo: true,
      faixa_salarial_min: null,
      faixa_salarial_max: null,
      periodicidade_exame_meses: null,
      exames_obrigatorios: null,
      insalubridade: false,
      insalubridade_grau: null,
      insalubridade_agente_nocivo: null,
      periculosidade: false,
      periculosidade_tipo: null,
      aposentadoria_especial: false,
      aposentadoria_especial_anos: null,
    });

    resetar();
    onClose();
    if (novo?.id) onCreated(novo.id);
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && handleFechar()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Plus className="w-5 h-5 text-primary" />
            Criar função
          </DialogTitle>
          <DialogDescription>
            Comece com o essencial. Depois você detalha atividades, competências e POPs na tela da função.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="nova-funcao-nome">Nome da função *</Label>
            <Input
              id="nova-funcao-nome"
              placeholder="Ex.: Analista de RH"
              value={nome}
              onChange={(e) => setNome(e.target.value)}
              autoFocus
              onKeyDown={(e) => {
                if (e.key === "Enter" && nome.trim() && !salvando) handleSalvar();
              }}
            />
          </div>

          <div className="space-y-1.5">
            <Label>Nível</Label>
            <Select value={nivel} onValueChange={setNivel}>
              <SelectTrigger>
                <SelectValue placeholder="Selecione (opcional)" />
              </SelectTrigger>
              <SelectContent>
                {NIVEIS.map((n) => (
                  <SelectItem key={n.value} value={n.value}>{n.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label>Departamento</Label>
            <Select value={departamentoId} onValueChange={setDepartamentoId}>
              <SelectTrigger>
                <SelectValue placeholder="Selecione (opcional)" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={SEM_DEPARTAMENTO}>Sem departamento</SelectItem>
                {departamentos.map((d) => (
                  <SelectItem key={d.id} value={d.id}>{d.nome}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" onClick={handleFechar} disabled={salvando}>
            Cancelar
          </Button>
          <Button onClick={handleSalvar} disabled={!nome.trim() || salvando} className="gap-2">
            {salvando ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
            Criar função
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
