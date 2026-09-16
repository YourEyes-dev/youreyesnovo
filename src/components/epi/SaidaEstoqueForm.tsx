import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { PackageMinus } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import type { EpiCompleto } from "@/types/epi";
import type { EpiLocalEstoque } from "@/hooks/useEpiLocais";
import type { EpiTamanho } from "@/hooks/useEpiTamanhos";

export const SUBTIPOS_SAIDA = [
  { value: "descarte", label: "Descarte" },
  { value: "perda", label: "Perda / Extravio" },
  { value: "dano", label: "Dano / Avaria" },
  { value: "vencimento", label: "Vencimento" },
  { value: "correcao", label: "Correção de Estoque" },
  { value: "outro", label: "Outro" },
] as const;

const schema = z.object({
  epi_id: z.string().min(1, "Selecione o EPI"),
  local_estoque_id: z.string().min(1, "Selecione o local de estoque"),
  quantidade: z.coerce.number().min(1, "Quantidade deve ser pelo menos 1"),
  subtipo: z.string().min(1, "Selecione o motivo da saída"),
  tamanho: z.string().optional(),
  observacoes: z.string().optional(),
});

export type SaidaEstoqueFormData = z.infer<typeof schema>;

interface SaidaEstoqueFormProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (data: SaidaEstoqueFormData) => Promise<void>;
  epis: EpiCompleto[];
  locais: EpiLocalEstoque[];
  getTamanhosForEpi?: (epiId: string) => EpiTamanho[];
  isLoading?: boolean;
}

export function SaidaEstoqueForm({
  open,
  onOpenChange,
  onSubmit,
  epis,
  locais,
  getTamanhosForEpi,
  isLoading,
}: SaidaEstoqueFormProps) {
  const locaisAtivos = locais.filter((l) => l.ativo);

  const form = useForm<SaidaEstoqueFormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      epi_id: "",
      local_estoque_id: "",
      quantidade: 1,
      subtipo: "descarte",
      tamanho: "",
      observacoes: "",
    },
  });

  const handleSubmit = async (data: SaidaEstoqueFormData) => {
    await onSubmit(data);
    form.reset();
    onOpenChange(false);
  };

  const selectedEpi = epis.find((e) => e.id === form.watch("epi_id"));
  const selectedEpiTamanhos = selectedEpi && getTamanhosForEpi
    ? getTamanhosForEpi(selectedEpi.id)
    : [];
  const temTamanhos = selectedEpiTamanhos.length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <PackageMinus className="w-5 h-5 text-destructive" />
            Saída de Estoque
          </DialogTitle>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="epi_id"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>EPI *</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o EPI" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {epis.map((epi) => (
                        <SelectItem key={epi.id} value={epi.id}>
                          {epi.tipo?.nome || "EPI"} {(epi.ca || epi.tipo?.ca_numero) ? `(CA: ${epi.ca || epi.tipo?.ca_numero})` : ""} — Estoque: {epi.quantidade_estoque}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="local_estoque_id"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Local de Estoque *</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o local" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {locaisAtivos.map((local) => (
                        <SelectItem key={local.id} value={local.id}>
                          {local.nome} {local.filial?.nome ? `(${local.filial.nome})` : ""}
                        </SelectItem>
                      ))}
                      {locaisAtivos.length === 0 && (
                        <div className="px-2 py-1.5 text-sm text-muted-foreground">
                          Nenhum local cadastrado.
                        </div>
                      )}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className={`grid ${temTamanhos ? "grid-cols-3" : "grid-cols-2"} gap-4`}>
              <FormField
                control={form.control}
                name="quantidade"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Quantidade *</FormLabel>
                    <FormControl>
                      <Input type="number" min={1} {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="subtipo"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Motivo da Saída *</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {SUBTIPOS_SAIDA.map((s) => (
                          <SelectItem key={s.value} value={s.value}>
                            {s.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {temTamanhos && (
                <FormField
                  control={form.control}
                  name="tamanho"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Tamanho *</FormLabel>
                      <Select onValueChange={field.onChange} value={field.value || ""}>
                        <FormControl>
                          <SelectTrigger>
                            <SelectValue placeholder="Tamanho" />
                          </SelectTrigger>
                        </FormControl>
                        <SelectContent>
                          {selectedEpiTamanhos.map((t) => (
                            <SelectItem key={t.id} value={t.tamanho}>
                              {t.tamanho}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}
            </div>

            {selectedEpi && (
              <div className="p-3 rounded-lg border bg-destructive/5 text-sm">
                <p><strong>EPI:</strong> {selectedEpi.tipo?.nome}</p>
                <p className="text-muted-foreground">
                  Estoque atual: {selectedEpi.quantidade_estoque} {selectedEpi.tipo?.unidade_medida || "unidade"}(s)
                </p>
              </div>
            )}

            <FormField
              control={form.control}
              name="observacoes"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Observações</FormLabel>
                  <FormControl>
                    <Textarea
                      placeholder="Detalhes sobre esta saída de estoque..."
                      {...field}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Cancelar
              </Button>
              <Button type="submit" variant="destructive" disabled={isLoading}>
                {isLoading ? "Registrando..." : "Registrar Saída"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
