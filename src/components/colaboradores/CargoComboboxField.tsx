import { useState } from "react";
import { Check, ChevronsUpDown, Plus, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { useCargos } from "@/hooks/useCadastros";
import { toast } from "sonner";

interface CargoComboboxFieldProps {
  value: string;
  onChange: (value: string) => void;
  disabled?: boolean;
  /** Opcional: recebe o id canônico do cargo (O2-A). null quando limpo/sem match. */
  onCargoIdChange?: (cargoId: string | null) => void;
}

export function CargoComboboxField({ value, onChange, disabled, onCargoIdChange }: CargoComboboxFieldProps) {
  const [open, setOpen] = useState(false);
  const [showNovoCargo, setShowNovoCargo] = useState(false);
  const [novoNome, setNovoNome] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  const { cargos, createCargo } = useCargos();
  const cargosOptions = cargos.filter(
    (c) => typeof c?.nome === "string" && c.nome.trim().length > 0
  );

  const handleCriarCargo = async () => {
    if (!novoNome.trim()) {
      toast.error("Informe o nome da função");
      return;
    }
    setIsSaving(true);
    try {
      const novo = await createCargo.mutateAsync({ nome: novoNome.trim(), ativo: true, descricao: null, departamento_id: null, nivel: null, faixa_salarial_min: null, faixa_salarial_max: null, periodicidade_exame_meses: null, exames_obrigatorios: null, insalubridade: false, insalubridade_grau: null, insalubridade_agente_nocivo: null, periculosidade: false, periculosidade_tipo: null, aposentadoria_especial: false, aposentadoria_especial_anos: null });
      onChange(novoNome.trim());
      onCargoIdChange?.((novo as { id?: string } | null)?.id ?? null);
      setShowNovoCargo(false);
      setNovoNome("");
      toast.success(`Função "${novoNome.trim()}" criada com sucesso`);
    } catch (e) {
      toast.error("Erro ao criar função");
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <>
      <div className="flex gap-1">
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              role="combobox"
              aria-expanded={open}
              disabled={disabled}
              className="flex-1 justify-between font-normal h-9 px-3"
            >
              <span className={cn("truncate", !value && "text-muted-foreground")}>
                {value || "Selecione"}
              </span>
              <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-[280px] p-0" align="start">
            <Command>
              <CommandInput placeholder="Pesquisar função..." />
              <CommandList>
                <CommandEmpty>Nenhuma função encontrada.</CommandEmpty>
                <CommandGroup>
                  {cargosOptions.map((cargo) => (
                    <CommandItem
                      key={cargo.id}
                      value={cargo.nome}
                      onSelect={(val) => {
                        const limpar = val === value;
                        onChange(limpar ? "" : cargo.nome);
                        onCargoIdChange?.(limpar ? null : cargo.id);
                        setOpen(false);
                      }}
                    >
                      <Check
                        className={cn(
                          "mr-2 h-4 w-4",
                          value === cargo.nome ? "opacity-100" : "opacity-0"
                        )}
                      />
                      {cargo.nome}
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>

        <Button
          type="button"
          variant="outline"
          size="icon"
          className="h-9 w-9 shrink-0"
          title="Cadastrar nova função"
          onClick={() => setShowNovoCargo(true)}
          disabled={disabled}
        >
          <Plus className="h-4 w-4" />
        </Button>
      </div>

      {/* Modal de cadastro rápido de função */}
      <Dialog open={showNovoCargo} onOpenChange={setShowNovoCargo}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Nova Função</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div>
              <Label htmlFor="novo-cargo-nome">Nome do Cargo *</Label>
              <Input
                id="novo-cargo-nome"
                autoFocus
                placeholder="Ex: Analista de RH"
                value={novoNome}
                onChange={(e) => setNovoNome(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleCriarCargo()}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              Para configurar detalhes completos (departamento, nível, faixa salarial), acesse{" "}
              <a href="/cadastros/cargos" target="_blank" className="underline text-primary">
                Cadastros → Funções
              </a>
              .
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowNovoCargo(false)} disabled={isSaving}>
              Cancelar
            </Button>
            <Button onClick={handleCriarCargo} disabled={isSaving}>
              {isSaving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Criar Função
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
