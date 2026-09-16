import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { ArrowRightLeft } from "lucide-react";
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

const schema = z
  .object({
    epi_id: z.string().min(1, "Selecione o EPI"),
    local_origem_id: z.string().min(1, "Selecione o local de origem"),
    local_destino_id: z.string().min(1, "Selecione o local de destino"),
    quantidade: z.coerce.number().min(1, "Quantidade deve ser pelo menos 1"),
    tamanho: z.string().optional(),
    observacoes: z.string().optional(),
  })
  .refine((d) => d.local_origem_id !== d.local_destino_id, {
    message: "Origem e destino devem ser diferentes",
    path: ["local_destino_id"],
  });

export type TransferenciaFormData = z.infer<typeof schema>;

interface TransferenciaEstoqueFormProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (data: TransferenciaFormData) => Promise<void>;
  epis: EpiCompleto[];
  locais: EpiLocalEstoque[];
  getTamanhosForEpi?: (epiId: string) => EpiTamanho[];
  isLoading?: boolean;
}

export function TransferenciaEstoqueForm({
  open,
  onOpenChange,
  onSubmit,
  epis,
  locais,
  getTamanhosForEpi,
  isLoading,
}: TransferenciaEstoqueFormProps) {
  const locaisAtivos = locais.filter((l) => l.ativo);

  const form = useForm<TransferenciaFormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      epi_id: "",
      local_origem_id: "",
      local_destino_id: "",
      quantidade: 1,
      tamanho: "",
      observacoes: "",
    },
  });

  const handleSubmit = async (data: TransferenciaFormData) => {
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
            <ArrowRightLeft className="w-5 h-5 text-primary" />
            Transferência entre Locais
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

            <div className="grid grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="local_origem_id"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Local de Origem *</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Origem" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {locaisAtivos.map((local) => (
                          <SelectItem key={local.id} value={local.id}>
                            {local.nome} {local.filial?.nome ? `(${local.filial.nome})` : ""}
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
                name="local_destino_id"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Local de Destino *</FormLabel>
                    <Select onValueChange={field.onChange} value={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Destino" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {locaisAtivos.map((local) => (
                          <SelectItem key={local.id} value={local.id}>
                            {local.nome} {local.filial?.nome ? `(${local.filial.nome})` : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <div className={`grid ${temTamanhos ? "grid-cols-2" : ""} gap-4`}>
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
              <div className="p-3 rounded-lg border bg-muted/30 text-sm">
                <p><strong>EPI:</strong> {selectedEpi.tipo?.nome}</p>
                <p className="text-muted-foreground">
                  Estoque global: {selectedEpi.quantidade_estoque} {selectedEpi.tipo?.unidade_medida || "unidade"}(s)
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
                      placeholder="Motivo da transferência..."
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
              <Button type="submit" disabled={isLoading}>
                {isLoading ? "Transferindo..." : "Confirmar Transferência"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
