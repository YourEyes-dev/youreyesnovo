import { useState, useMemo } from "react";
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
import { useUsuariosDiretorio } from "@/hooks/useUsuariosDiretorio";

interface GestorComboboxFieldProps {
  value: string;
  onChange: (value: string) => void;
  /**
   * Opcional: recebe o CPF (só dígitos) do gestor escolhido, ou null ao limpar.
   * É o que grava o vínculo de chefia (admissoes.gestor_cpf). O CPF é usado,
   * e não o id da ficha, porque o gestor pode ser um pró-labore ou um usuário
   * do sistema (o dono) que NÃO tem ficha de colaborador — e o CPF é a
   * identidade que todos compartilham.
   */
  onChangeCpf?: (cpf: string | null) => void;
  disabled?: boolean;
}

type OpcaoGestor = {
  cpf: string; // só dígitos
  nome: string;
  origem: "colaborador" | "sistema";
  detalhe?: string;
};

export function GestorComboboxField({ value, onChange, onChangeCpf, disabled }: GestorComboboxFieldProps) {
  const [open, setOpen] = useState(false);
  const { colaboradores } = useColaboradores();
  const { usuarios } = useUsuariosDiretorio();

  // Une colaboradores + usuários do sistema, sem repetir (deduplicado por CPF).
  // Só entram quem tem CPF — o vínculo de chefia depende dele. Colaborador tem
  // precedência quando a mesma pessoa existe nas duas listas.
  const opcoes = useMemo<OpcaoGestor[]>(() => {
    const porCpf = new Map<string, OpcaoGestor>();
    for (const c of colaboradores) {
      const cpf = (c.cpf || "").replace(/\D/g, "");
      if (cpf.length !== 11 || porCpf.has(cpf)) continue;
      porCpf.set(cpf, { cpf, nome: c.nome_completo, origem: "colaborador", detalhe: c.cargo || undefined });
    }
    for (const u of usuarios) {
      const cpf = (u.cpf || "").replace(/\D/g, "");
      if (cpf.length !== 11 || porCpf.has(cpf)) continue;
      porCpf.set(cpf, { cpf, nome: u.nome_completo, origem: "sistema", detalhe: u.email_principal || undefined });
    }
    return Array.from(porCpf.values()).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
  }, [colaboradores, usuarios]);

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
            {value || "Pesquisar gestor (colaborador ou usuário do sistema)..."}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[320px] p-0" align="start">
        <Command
          filter={(val, search) => {
            // val = "nome|cpf"; casa por nome ou por dígitos do CPF
            const termo = search.toLowerCase().trim();
            const digitos = termo.replace(/\D/g, "");
            const texto = val.toLowerCase();
            if (texto.includes(termo)) return 1;
            if (digitos && texto.replace(/\D/g, "").includes(digitos)) return 1;
            return 0;
          }}
        >
          <CommandInput placeholder="Buscar por nome ou CPF..." />
          <CommandList>
            <CommandEmpty>Nenhuma pessoa encontrada.</CommandEmpty>
            <CommandGroup>
              {opcoes.map((op) => (
                <CommandItem
                  key={`${op.origem}-${op.cpf}`}
                  value={`${op.nome}|${op.cpf}`}
                  onSelect={() => {
                    const limpar = op.nome === value;
                    onChange(limpar ? "" : op.nome);
                    onChangeCpf?.(limpar ? null : op.cpf);
                    setOpen(false);
                  }}
                >
                  <Check
                    className={cn(
                      "mr-2 h-4 w-4 shrink-0",
                      value === op.nome ? "opacity-100" : "opacity-0"
                    )}
                  />
                  <div className="flex flex-col min-w-0 flex-1">
                    <span className="truncate text-sm">{op.nome}</span>
                    {op.detalhe && (
                      <span className="truncate text-xs text-muted-foreground">{op.detalhe}</span>
                    )}
                  </div>
                  <span
                    className={cn(
                      "ml-2 shrink-0 rounded px-1.5 py-0.5 text-[10px]",
                      op.origem === "colaborador"
                        ? "bg-primary/10 text-primary"
                        : "bg-muted text-muted-foreground"
                    )}
                  >
                    {op.origem === "colaborador" ? "Colaborador" : "Usuário"}
                  </span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
