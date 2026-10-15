import { useState } from "react";
import { Check, ChevronsUpDown } from "lucide-react";
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
import { cn } from "@/lib/utils";
import { useColaboradores } from "@/hooks/useColaboradores";

interface GestorComboboxFieldProps {
  value: string;
  onChange: (value: string) => void;
  /**
   * Opcional: recebe o ID do colaborador escolhido (a admissão do gestor), ou
   * null ao limpar. É o que permite guardar o vínculo ESTRUTURADO de chefia
   * (admissoes.gestor_admissao_id), em vez de só o nome em texto. Callers que
   * não precisam do vínculo podem ignorar.
   */
  onChangeId?: (id: string | null) => void;
  disabled?: boolean;
}

export function GestorComboboxField({ value, onChange, onChangeId, disabled }: GestorComboboxFieldProps) {
  const [open, setOpen] = useState(false);
  const { colaboradores } = useColaboradores();

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          disabled={disabled}
          className="w-full justify-between font-normal h-9 px-3"
        >
          <span className={cn("truncate", !value && "text-muted-foreground")}>
            {value || "Pesquisar gestor..."}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[280px] p-0" align="start">
        <Command>
          <CommandInput placeholder="Buscar colaborador..." />
          <CommandList>
            <CommandEmpty>Nenhum colaborador encontrado.</CommandEmpty>
            <CommandGroup>
              {colaboradores.map((col) => (
                <CommandItem
                  key={col.id}
                  value={col.nome_completo}
                  onSelect={() => {
                    const limpar = col.nome_completo === value;
                    onChange(limpar ? "" : col.nome_completo);
                    onChangeId?.(limpar ? null : col.id);
                    setOpen(false);
                  }}
                >
                  <Check
                    className={cn(
                      "mr-2 h-4 w-4 shrink-0",
                      value === col.nome_completo ? "opacity-100" : "opacity-0"
                    )}
                  />
                  <div className="flex flex-col min-w-0">
                    <span className="truncate text-sm">{col.nome_completo}</span>
                    {col.cargo && (
                      <span className="truncate text-xs text-muted-foreground">{col.cargo}</span>
                    )}
                  </div>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
