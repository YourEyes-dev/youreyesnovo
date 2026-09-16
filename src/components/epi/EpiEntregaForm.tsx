import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useState, useRef, useMemo } from "react";
import { Camera, X, Upload, Search, UserCheck } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
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
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { EpiCompleto } from "@/types/epi";
import { MOTIVOS_ENTREGA } from "@/types/epi";
import { useColaboradores, type Colaborador } from "@/hooks/useColaboradores";
import { useAfastamentosAtivos } from "@/hooks/useAfastamentosAtivos";
import { AfastadoBadge } from "@/components/shared/AfastadoBadge";

const schema = z.object({
  epi_id: z.string().min(1, "Selecione o EPI"),
  colaborador_nome: z.string().min(2, "Nome é obrigatório"),
  colaborador_cpf: z.string().optional(),
  colaborador_cargo: z.string().optional(),
  colaborador_departamento: z.string().optional(),
  quantidade: z.coerce.number().min(1, "Quantidade deve ser pelo menos 1"),
  data_devolucao_prevista: z.string().optional(),
  motivo_entrega: z.string().optional(),
  observacoes: z.string().optional(),
});

type FormData = z.infer<typeof schema>;

interface EpiEntregaFormProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (data: { 
    epi_id: string; 
    colaborador_nome: string; 
    quantidade: number; 
    colaborador_cpf?: string; 
    colaborador_cargo?: string; 
    colaborador_departamento?: string; 
    data_devolucao_prevista?: string; 
    motivo_entrega?: string; 
    observacoes?: string;
    foto?: File;
  }) => Promise<void>;
  epis: EpiCompleto[];
  isLoading?: boolean;
}

export function EpiEntregaForm({
  open,
  onOpenChange,
  onSubmit,
  epis,
  isLoading,
}: EpiEntregaFormProps) {
  const [foto, setFoto] = useState<File | null>(null);
  const [fotoPreview, setFotoPreview] = useState<string | null>(null);
  const [colaboradorOpen, setColaboradorOpen] = useState(false);
  const [selectedColaborador, setSelectedColaborador] = useState<Colaborador | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const { colaboradores, isLoading: loadingColaboradores } = useColaboradores();
  const { getAfastamento } = useAfastamentosAtivos();

  const form = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      epi_id: "",
      colaborador_nome: "",
      colaborador_cpf: "",
      colaborador_cargo: "",
      colaborador_departamento: "",
      quantidade: 1,
      data_devolucao_prevista: "",
      motivo_entrega: "",
      observacoes: "",
    },
  });

  const selectedEpiId = form.watch("epi_id");
  const selectedEpi = epis.find((e) => e.id === selectedEpiId);

  // Filtrar colaboradores baseado na busca
  const filteredColaboradores = useMemo(() => {
    if (!searchQuery) return colaboradores;
    const query = searchQuery.toLowerCase();
    return colaboradores.filter(
      (c) =>
        c.nome_completo.toLowerCase().includes(query) ||
        c.cpf.includes(query) ||
        c.cargo?.toLowerCase().includes(query)
    );
  }, [colaboradores, searchQuery]);

  const handleSelectColaborador = (colaborador: Colaborador) => {
    setSelectedColaborador(colaborador);
    form.setValue("colaborador_nome", colaborador.nome_completo);
    form.setValue("colaborador_cpf", colaborador.cpf);
    form.setValue("colaborador_cargo", colaborador.cargo);
    form.setValue("colaborador_departamento", colaborador.departamento || "");
    setColaboradorOpen(false);
  };

  const handleClearColaborador = () => {
    setSelectedColaborador(null);
    form.setValue("colaborador_nome", "");
    form.setValue("colaborador_cpf", "");
    form.setValue("colaborador_cargo", "");
    form.setValue("colaborador_departamento", "");
  };

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      setFoto(file);
      const reader = new FileReader();
      reader.onloadend = () => {
        setFotoPreview(reader.result as string);
      };
      reader.readAsDataURL(file);
    }
  };

  const handleRemoveFoto = () => {
    setFoto(null);
    setFotoPreview(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  };

  const handleSubmit = async (data: FormData) => {
    await onSubmit({
      epi_id: data.epi_id,
      colaborador_nome: data.colaborador_nome,
      quantidade: data.quantidade,
      colaborador_cpf: data.colaborador_cpf,
      colaborador_cargo: data.colaborador_cargo,
      colaborador_departamento: data.colaborador_departamento,
      data_devolucao_prevista: data.data_devolucao_prevista,
      motivo_entrega: data.motivo_entrega,
      observacoes: data.observacoes,
      foto: foto || undefined,
    });
    form.reset();
    setFoto(null);
    setFotoPreview(null);
    setSelectedColaborador(null);
    onOpenChange(false);
  };

  const episDisponiveis = epis.filter((e) => e.quantidade_estoque > 0);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Registrar Entrega de EPI</DialogTitle>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="epi_id"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>EPI *</FormLabel>
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o EPI" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {episDisponiveis.map((epi) => (
                        <SelectItem key={epi.id} value={epi.id}>
                          <div className="flex items-center gap-2">
                            <span>{epi.tipo.nome}</span>
                            {epi.marca && <span className="text-muted-foreground">- {epi.marca}</span>}
                            {epi.tamanho && <span className="text-muted-foreground">({epi.tamanho})</span>}
                            <Badge variant="secondary" className="ml-2">
                              {epi.quantidade_estoque} em estoque
                            </Badge>
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {selectedEpi && (
              <div className="p-3 bg-muted rounded-lg text-sm">
                <p><strong>CA:</strong> {selectedEpi.ca || selectedEpi.tipo?.ca_numero || "Não informado"}</p>
                <p><strong>Modelo:</strong> {selectedEpi.modelo || "Não informado"}</p>
                <p><strong>Disponível:</strong> {selectedEpi.quantidade_estoque} unidades</p>
              </div>
            )}

            {/* Seleção de Colaborador */}
            <div className="space-y-2">
              <FormLabel>Colaborador *</FormLabel>
              {colaboradores.length > 0 ? (
                <div className="space-y-2">
                  <Popover open={colaboradorOpen} onOpenChange={setColaboradorOpen}>
                    <PopoverTrigger asChild>
                      <Button
                        variant="outline"
                        role="combobox"
                        aria-expanded={colaboradorOpen}
                        className={cn(
                          "w-full justify-between",
                          !selectedColaborador && "text-muted-foreground"
                        )}
                      >
                        {selectedColaborador ? (
                          <div className="flex items-center gap-2 flex-wrap">
                            <UserCheck className="h-4 w-4 text-primary" />
                            <span>{selectedColaborador.nome_completo}</span>
                            <AfastadoBadge afastamento={getAfastamento({ cpf: selectedColaborador.cpf, nome: selectedColaborador.nome_completo })} compact />
                            <Badge variant="secondary" className="ml-auto">
                              {selectedColaborador.cargo}
                            </Badge>
                          </div>
                        ) : (
                          <span className="flex items-center gap-2">
                            <Search className="h-4 w-4" />
                            Buscar colaborador...
                          </span>
                        )}
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-[400px] p-0" align="start">
                      <Command shouldFilter={false}>
                        <CommandInput 
                          placeholder="Buscar por nome, CPF ou função..." 
                          value={searchQuery}
                          onValueChange={setSearchQuery}
                        />
                        <CommandList>
                          <CommandEmpty>
                            {loadingColaboradores ? "Carregando..." : "Nenhum colaborador encontrado."}
                          </CommandEmpty>
                          <CommandGroup heading="Colaboradores">
                            {filteredColaboradores.map((colaborador) => (
                              <CommandItem
                                key={colaborador.id}
                                value={colaborador.id}
                                onSelect={() => handleSelectColaborador(colaborador)}
                                className="flex flex-col items-start gap-1 py-3"
                              >
                                <div className="flex items-center gap-2 w-full">
                                  <UserCheck className="h-4 w-4 text-muted-foreground" />
                                  <span className="font-medium">{colaborador.nome_completo}</span>
                                </div>
                                <div className="flex gap-2 text-xs text-muted-foreground ml-6">
                                  <span>CPF: {colaborador.cpf}</span>
                                  {colaborador.cargo && <span>• {colaborador.cargo}</span>}
                                  {colaborador.departamento && <span>• {colaborador.departamento}</span>}
                                </div>
                              </CommandItem>
                            ))}
                          </CommandGroup>
                        </CommandList>
                      </Command>
                    </PopoverContent>
                  </Popover>

                  {selectedColaborador && (
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="gap-1">
                        <UserCheck className="h-3 w-3" />
                        Colaborador selecionado
                      </Badge>
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={handleClearColaborador}
                      >
                        <X className="h-4 w-4 mr-1" />
                        Limpar
                      </Button>
                    </div>
                  )}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">
                  Nenhum colaborador cadastrado. Complete uma admissão primeiro ou preencha manualmente abaixo.
                </p>
              )}
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <FormField
                control={form.control}
                name="colaborador_nome"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Nome do Colaborador *</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="Nome completo" 
                        {...field} 
                        disabled={!!selectedColaborador}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="colaborador_cpf"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>CPF</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="000.000.000-00" 
                        {...field} 
                        disabled={!!selectedColaborador}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="colaborador_cargo"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Cargo</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="Função do colaborador" 
                        {...field} 
                        disabled={!!selectedColaborador}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="colaborador_departamento"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Departamento</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="Setor" 
                        {...field} 
                        disabled={!!selectedColaborador}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="quantidade"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Quantidade *</FormLabel>
                    <FormControl>
                      <Input
                        type="number"
                        min={1}
                        max={selectedEpi?.quantidade_estoque || 999}
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="data_devolucao_prevista"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Data de Devolução Prevista</FormLabel>
                    <FormControl>
                      <Input type="date" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            <FormField
              control={form.control}
              name="motivo_entrega"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Motivo da Entrega</FormLabel>
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o motivo" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {MOTIVOS_ENTREGA.map((motivo) => (
                        <SelectItem key={motivo} value={motivo}>
                          {motivo}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            {/* Seção de Foto */}
            <div className="space-y-2">
              <FormLabel>Foto da Entrega</FormLabel>
              <div className="flex flex-col gap-3">
                {fotoPreview ? (
                  <div className="relative w-full max-w-xs">
                    <img 
                      src={fotoPreview} 
                      alt="Preview da foto" 
                      className="w-full h-48 object-cover rounded-lg border"
                    />
                    <Button
                      type="button"
                      variant="destructive"
                      size="icon"
                      className="absolute top-2 right-2 h-8 w-8"
                      onClick={handleRemoveFoto}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ) : (
                  <div 
                    className="w-full max-w-xs h-48 border-2 border-dashed rounded-lg flex flex-col items-center justify-center gap-2 cursor-pointer hover:border-primary hover:bg-muted/50 transition-colors"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <div className="p-3 rounded-full bg-muted">
                      <Camera className="h-6 w-6 text-muted-foreground" />
                    </div>
                    <div className="text-center">
                      <p className="text-sm font-medium">Adicionar foto</p>
                      <p className="text-xs text-muted-foreground">Clique para selecionar</p>
                    </div>
                  </div>
                )}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  onChange={handleFileChange}
                />
                {!fotoPreview && (
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => fileInputRef.current?.click()}
                    >
                      <Upload className="h-4 w-4 mr-2" />
                      Escolher arquivo
                    </Button>
                  </div>
                )}
              </div>
              <p className="text-xs text-muted-foreground">
                Opcional: Tire uma foto ou selecione uma imagem da entrega do EPI
              </p>
            </div>

            <FormField
              control={form.control}
              name="observacoes"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Observações</FormLabel>
                  <FormControl>
                    <Textarea placeholder="Observações adicionais" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />

            <div className="flex justify-end gap-2 pt-4">
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
              >
                Cancelar
              </Button>
              <Button type="submit" disabled={isLoading}>
                {isLoading ? "Registrando..." : "Registrar Entrega"}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
