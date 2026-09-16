import { useState, useMemo, useEffect } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Plus, HelpCircle, X, Trash2 } from "lucide-react";
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
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import type { EpiTipo, EpiCompleto } from "@/types/epi";
import { CATEGORIAS_EPI, UNIDADES_MEDIDA, TIPOS_DURABILIDADE } from "@/types/epi";
import { useEpiLocais } from "@/hooks/useEpiLocais";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

// CA e validade não são mais obrigatórios AQUI: quem decide é a categoria
// (epi_categorias.exige_ca). Capacete e luva têm Certificado de Aprovação;
// uniforme e crachá não têm. A exigência é conferida no envio, em
// handleSubmit, onde a categoria escolhida já é conhecida. O formato continua
// validado sempre que o campo vier preenchido.
const schema = z.object({
  nome: z.string().min(2, "Nome do EPI deve ter pelo menos 2 caracteres"),
  categoria: z.string().optional(),
  codigo: z.string().optional(),
  ca: z.string().regex(/^\d*$/, "CA deve conter apenas números").optional(),
  marca: z.string().optional(),
  modelo: z.string().optional(),
  tamanho: z.string().optional(),
  data_fabricacao: z.string().optional(),
  data_validade: z.string().optional().refine((val) => {
    if (!val) return true;
    const date = new Date(val);
    return !isNaN(date.getTime());
  }, "Data de validade inválida"),
  quantidade_estoque: z.coerce.number().min(0, "Quantidade deve ser maior ou igual a 0"),
  quantidade_minima: z.coerce.number().min(1, "Quantidade mínima deve ser pelo menos 1"),
  custo_unitario: z.coerce.number().min(0).optional(),
  local_estoque_id: z.string().optional(),
  localizacao: z.string().optional(),
  unidade_medida: z.string().optional(),
  tipo_durabilidade: z.string().optional(),
  periodicidade_troca_dias: z.union([z.coerce.number().min(1, "Deve ser pelo menos 1 dia"), z.literal(""), z.undefined()]).optional(),
  fabricante: z.string().optional(),
  observacoes: z.string().optional(),
});

type FormData = z.infer<typeof schema>;

interface EpiFormProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSubmit: (data: any) => Promise<void>;
  onCreateTipo: (data: {
    nome: string;
    descricao?: string;
    categoria?: string;
    unidade_medida?: string;
    tipo_durabilidade?: string;
    validade_meses?: number | null;
    periodicidade_troca_dias?: number | null;
    ca_numero?: string;
    ca_validade?: string;
    marca?: string;
    fabricante?: string;
    estoque_minimo?: number | null;
    estoque_inicial?: number | null;
    controla_tamanho?: boolean;
    tamanhos?: string[];
    grade_tamanhos?: Array<{ tamanho: string; local_estoque_id: string; quantidade: number }>;
  }) => Promise<void>;
  onCreateCategoria?: (nome: string) => Promise<void>;
  tipos: EpiTipo[];
  customCategorias?: string[];
  /**
   * Categorias que exigem CA, por nome. Categoria ausente do mapa conta como
   * "exige" — é o padrão da coluna no banco e mantém a NR-06 valendo para
   * tudo que ninguém marcou ainda.
   */
  categoriasExigemCa?: Record<string, boolean>;
  epi?: EpiCompleto | null;
  isLoading?: boolean;
}

export function EpiForm({
  open,
  onOpenChange,
  onSubmit,
  onCreateTipo,
  onCreateCategoria,
  tipos,
  customCategorias = [],
  categoriasExigemCa = {},
  epi,
  isLoading,
}: EpiFormProps) {
  const [selectedCategoria, setSelectedCategoria] = useState<string>("");
  const [showNewCategoriaInput, setShowNewCategoriaInput] = useState(false);
  const [newCategoriaName, setNewCategoriaName] = useState("");
  const [isCreatingCategoria, setIsCreatingCategoria] = useState(false);
  const [controlaTamanho, setControlaTamanho] = useState(false);
  const [gradeTamanhos, setGradeTamanhos] = useState<Array<{ tamanho: string; local_estoque_id: string; quantidade: number }>>([]);
  const [novoTamanho, setNovoTamanho] = useState("");

  const { locaisAtivos } = useEpiLocais();

  const categorias = useMemo(() => {
    const existingCategories = tipos
      .filter(t => t.is_active !== false && t.categoria)
      .map(t => t.categoria as string);
    const allCategories = [...new Set([...CATEGORIAS_EPI, ...existingCategories, ...customCategorias])];
    return allCategories.sort();
  }, [tipos, customCategorias]);

  // A categoria manda na exigência do CA. Sem categoria escolhida, exige —
  // é o comportamento antigo, e é o lado seguro do erro.
  const exigeCa = categoriasExigemCa[selectedCategoria] ?? true;

  const form = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      nome: epi?.tipo?.nome || "",
      categoria: epi?.tipo?.categoria || "",
      codigo: epi?.codigo || "",
      ca: epi?.ca || "",
      marca: epi?.marca || "",
      modelo: epi?.modelo || "",
      tamanho: epi?.tamanho || "",
      data_fabricacao: epi?.data_fabricacao || "",
      data_validade: epi?.data_validade || "",
      quantidade_estoque: epi?.quantidade_estoque || 0,
      quantidade_minima: epi?.quantidade_minima || 5,
      custo_unitario: epi?.custo_unitario ? Number(epi.custo_unitario) : undefined,
      local_estoque_id: "",
      localizacao: epi?.localizacao || "",
      unidade_medida: epi?.tipo?.unidade_medida || "unidade",
      tipo_durabilidade: epi?.tipo?.tipo_durabilidade || "duravel",
      periodicidade_troca_dias: epi?.tipo?.periodicidade_troca_dias || undefined,
      fabricante: epi?.tipo?.fabricante || "",
      observacoes: epi?.observacoes || "",
    },
  });

  useEffect(() => {
    if (open) {
      form.reset({
        nome: epi?.tipo?.nome || "",
        categoria: epi?.tipo?.categoria || "",
        codigo: epi?.codigo || "",
        ca: epi?.ca || "",
        marca: epi?.marca || "",
        modelo: epi?.modelo || "",
        tamanho: epi?.tamanho || "",
        data_fabricacao: epi?.data_fabricacao || "",
        data_validade: epi?.data_validade || "",
        quantidade_estoque: epi?.quantidade_estoque || 0,
        quantidade_minima: epi?.quantidade_minima || 5,
        custo_unitario: epi?.custo_unitario ? Number(epi.custo_unitario) : undefined,
        local_estoque_id: "",
        localizacao: epi?.localizacao || "",
        unidade_medida: epi?.tipo?.unidade_medida || "unidade",
        tipo_durabilidade: epi?.tipo?.tipo_durabilidade || "duravel",
        periodicidade_troca_dias: epi?.tipo?.periodicidade_troca_dias || undefined,
        fabricante: epi?.tipo?.fabricante || "",
        observacoes: epi?.observacoes || "",
      });
      setSelectedCategoria(epi?.tipo?.categoria || "");
    }
  }, [epi, open]);

  // CT-36: Validar unicidade do CA no cadastro
  const [caExistente, setCaExistente] = useState<string | null>(null);
  const caValue = form.watch("ca");

  useEffect(() => {
    const verificarCA = async () => {
      if (!caValue || caValue.length < 3) {
        setCaExistente(null);
        return;
      }
      // Não validar se estiver editando e CA for o mesmo
      if (epi?.ca === caValue) {
        setCaExistente(null);
        return;
      }
      const { data: existente } = await supabase
        .from("epi_tipos")
        .select("id, nome")
        .eq("ca_numero", caValue)
        .limit(1)
        .maybeSingle();
      setCaExistente(existente ? existente.nome : null);
    };
    const timer = setTimeout(verificarCA, 500);
    return () => clearTimeout(timer);
  }, [caValue, epi?.ca]);

  const handleSubmit = async (data: FormData) => {
    // Exigência de CA conforme a categoria escolhida (NR-06 para o que é EPI
    // de verdade; nada para uniforme e afins).
    if (exigeCa) {
      let faltou = false;
      if (!data.ca?.trim()) {
        form.setError("ca", { message: "Número do CA é obrigatório para esta categoria (NR-06)." });
        faltou = true;
      }
      if (!data.data_validade?.trim()) {
        form.setError("data_validade", { message: "Data de validade do CA é obrigatória para esta categoria." });
        faltou = true;
      }
      if (faltou) {
        toast.error(
          "Esta categoria exige CA e data de validade. Se este item não tem CA (uniforme, por exemplo), marque a categoria como isenta em EPI › Configurações."
        );
        return;
      }
    }

    // CT-36: Bloquear se CA já existe
    if (caExistente) {
      toast.error(`O CA ${data.ca} já está cadastrado para o EPI "${caExistente}".`);
      return;
    }

    // First create the tipo, then create the EPI record
    const categoria = selectedCategoria || data.categoria;
    
    try {
      const result = await onCreateTipo({
        nome: data.nome,
        categoria: categoria,
        unidade_medida: data.unidade_medida,
        tipo_durabilidade: data.tipo_durabilidade,
        periodicidade_troca_dias: data.periodicidade_troca_dias ? Number(data.periodicidade_troca_dias) : null,
        marca: data.marca,
        fabricante: data.fabricante,
        // Vazio vira undefined: categoria isenta de CA cadastra sem número e
        // sem validade, e string vazia em coluna de data quebraria o insert.
        ca_numero: data.ca?.trim() || undefined,
        // Faltava enviar a validade: a assinatura de onCreateTipo já a
        // declarava, mas handleSubmit nunca a mandava, então
        // epi_tipos.ca_validade ficava sempre NULL — e os alertas de CA
        // vencido/vencendo nunca disparavam para item nenhum.
        ca_validade: data.data_validade?.trim() || undefined,
        estoque_minimo: data.quantidade_minima,
        estoque_inicial: data.quantidade_estoque,
        controla_tamanho: controlaTamanho,
        tamanhos: controlaTamanho ? gradeTamanhos.map(g => g.tamanho) : [],
        grade_tamanhos: controlaTamanho ? gradeTamanhos : [],
      });
      
      form.reset();
      onOpenChange(false);
    } catch (error) {
      console.error("Erro ao cadastrar EPI:", error);
    }
  };

  const handleCategoriaChange = (value: string) => {
    if (value === "__new_cat__") {
      setShowNewCategoriaInput(true);
      return;
    }
    setSelectedCategoria(value);
    form.setValue("categoria", value);
  };

  const handleCreateCategoria = async () => {
    if (!newCategoriaName.trim() || !onCreateCategoria) return;
    setIsCreatingCategoria(true);
    try {
      await onCreateCategoria(newCategoriaName.trim());
      setSelectedCategoria(newCategoriaName.trim());
      form.setValue("categoria", newCategoriaName.trim());
      setNewCategoriaName("");
      setShowNewCategoriaInput(false);
    } finally {
      setIsCreatingCategoria(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{epi ? "Editar EPI" : "Cadastrar Novo EPI"}</DialogTitle>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(handleSubmit)} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Categoria */}
              <FormItem>
                <FormLabel className="flex items-center gap-1.5">
                  Categoria *
                  <TooltipProvider>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <HelpCircle className="h-4 w-4 text-muted-foreground cursor-help" />
                      </TooltipTrigger>
                      <TooltipContent side="right" align="start" className="max-w-xs z-[100]">
                        <p>Categoria é o agrupamento do EPI (ex: Proteção Auditiva).</p>
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>
                </FormLabel>
                {showNewCategoriaInput ? (
                  <div className="flex gap-2">
                    <Input
                      placeholder="Nome da nova categoria"
                      value={newCategoriaName}
                      onChange={(e) => setNewCategoriaName(e.target.value)}
                      onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); handleCreateCategoria(); } }}
                      autoFocus
                    />
                    <Button type="button" size="sm" onClick={handleCreateCategoria} disabled={isCreatingCategoria || !newCategoriaName.trim()}>
                      {isCreatingCategoria ? "..." : "OK"}
                    </Button>
                    <Button type="button" size="sm" variant="ghost" onClick={() => { setShowNewCategoriaInput(false); setNewCategoriaName(""); }}>
                      ✕
                    </Button>
                  </div>
                ) : (
                  <Select onValueChange={handleCategoriaChange} value={selectedCategoria}>
                    <SelectTrigger>
                      <SelectValue placeholder="Selecione a categoria" />
                    </SelectTrigger>
                    <SelectContent>
                      {categorias.map((cat) => (
                        <SelectItem key={cat} value={cat}>{cat}</SelectItem>
                      ))}
                      <Separator className="my-1" />
                      <SelectItem value="__new_cat__" className="text-primary font-medium">
                        <span className="flex items-center gap-2">
                          <Plus className="h-4 w-4" />
                          Nova categoria
                        </span>
                      </SelectItem>
                    </SelectContent>
                  </Select>
                )}
              </FormItem>

              {/* Nome do EPI - campo de texto livre */}
              <FormField
                control={form.control}
                name="nome"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="flex items-center gap-1.5">
                      Nome do EPI *
                      <TooltipProvider>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <HelpCircle className="h-4 w-4 text-muted-foreground cursor-help" />
                          </TooltipTrigger>
                          <TooltipContent side="right" align="start" className="max-w-xs z-[100]">
                            <p>Informe o nome do EPI a ser cadastrado.</p>
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    </FormLabel>
                    <FormControl>
                      <Input placeholder="Ex: Protetor Auricular 3M" {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>

            {/* Remaining fields */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <FormField control={form.control} name="codigo" render={({ field }) => (
                <FormItem>
                  <FormLabel>Código / Nº Série</FormLabel>
                  <FormControl><Input placeholder="Código único" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="ca" render={({ field }) => (
                <FormItem>
                  <FormLabel>CA (Certificado de Aprovação){exigeCa ? " *" : ""}</FormLabel>
                  <FormControl><Input placeholder={exigeCa ? "Número do CA" : "Número do CA (opcional)"} {...field} /></FormControl>
                  {!exigeCa && selectedCategoria && (
                    <p className="text-xs text-muted-foreground">
                      A categoria "{selectedCategoria}" está marcada como isenta de CA.
                    </p>
                  )}
                  {caExistente && (
                    <p className="text-xs text-destructive font-medium">
                      ⚠ CA já cadastrado para: {caExistente}
                    </p>
                  )}
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="marca" render={({ field }) => (
                <FormItem>
                  <FormLabel>Marca</FormLabel>
                  <FormControl><Input placeholder="Fabricante" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="modelo" render={({ field }) => (
                <FormItem>
                  <FormLabel>Modelo</FormLabel>
                  <FormControl><Input placeholder="Modelo do EPI" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="fabricante" render={({ field }) => (
                <FormItem>
                  <FormLabel>Fabricante</FormLabel>
                  <FormControl><Input placeholder="Ex: 3M do Brasil" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              {/* Campo Tamanho removido - controlado pela grade de tamanhos */}
              <FormField control={form.control} name="unidade_medida" render={({ field }) => (
                <FormItem>
                  <FormLabel>Unidade de Medida</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value || "unidade"}>
                    <FormControl>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {UNIDADES_MEDIDA.map((um) => <SelectItem key={um.value} value={um.value}>{um.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="tipo_durabilidade" render={({ field }) => (
                <FormItem>
                  <FormLabel>Tipo de Durabilidade</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value || "duravel"}>
                    <FormControl>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {TIPOS_DURABILIDADE.map((td) => <SelectItem key={td.value} value={td.value}>{td.label}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="periodicidade_troca_dias" render={({ field }) => (
                <FormItem>
                  <FormLabel className="flex items-center gap-1.5">
                    Periodicidade de Troca (dias)
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <HelpCircle className="h-4 w-4 text-muted-foreground cursor-help" />
                        </TooltipTrigger>
                        <TooltipContent side="right" align="start" className="max-w-xs z-[100]">
                          <p>Informe em dias a periodicidade de troca/manutenção do EPI. Será usado como referência no momento da entrega.</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </FormLabel>
                  <FormControl><Input type="number" min={1} placeholder="Ex: 180" {...field} value={field.value || ""} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="data_fabricacao" render={({ field }) => (
                <FormItem>
                  <FormLabel>Data de Fabricação</FormLabel>
                  <FormControl><Input type="date" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="data_validade" render={({ field }) => (
                <FormItem>
                  <FormLabel>Data de Validade{exigeCa ? " *" : ""}</FormLabel>
                  <FormControl><Input type="date" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="quantidade_estoque" render={({ field }) => (
                <FormItem>
                  <FormLabel>Quantidade em Estoque *</FormLabel>
                  <FormControl><Input type="number" min={0} {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="quantidade_minima" render={({ field }) => (
                <FormItem>
                  <FormLabel>Quantidade Mínima (Alerta)</FormLabel>
                  <FormControl><Input type="number" min={1} {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="custo_unitario" render={({ field }) => (
                <FormItem>
                  <FormLabel>Custo Unitário (R$)</FormLabel>
                  <FormControl><Input type="number" step="0.01" min={0} placeholder="0,00" {...field} value={field.value || ""} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="local_estoque_id" render={({ field }) => (
                <FormItem>
                  <FormLabel>Local de Estoque</FormLabel>
                  <Select onValueChange={field.onChange} value={field.value || ""}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="Selecione o local" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {locaisAtivos.map((local) => (
                        <SelectItem key={local.id} value={local.id}>
                          {local.nome}{local.filial?.nome ? ` (${local.filial.nome})` : ""}
                        </SelectItem>
                      ))}
                      {locaisAtivos.length === 0 && (
                        <div className="px-2 py-1.5 text-sm text-muted-foreground">Nenhum local cadastrado</div>
                      )}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )} />
              <FormField control={form.control} name="localizacao" render={({ field }) => (
                <FormItem>
                  <FormLabel>Localização</FormLabel>
                  <FormControl><Input placeholder="Ex: Armário A, Prateleira 3" {...field} /></FormControl>
                  <FormMessage />
                </FormItem>
              )} />
            </div>

            <FormField control={form.control} name="observacoes" render={({ field }) => (
              <FormItem>
                <FormLabel>Observações</FormLabel>
                <FormControl><Textarea placeholder="Observações adicionais" {...field} /></FormControl>
                <FormMessage />
              </FormItem>
            )} />

            {/* Controle por Tamanho */}
            <div className="space-y-3 p-4 rounded-lg border bg-muted/30">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm font-medium">Controlar por Tamanho</p>
                  <p className="text-xs text-muted-foreground">Habilite para gerenciar estoque por tamanho (ex: calçados, luvas)</p>
                </div>
                <Switch checked={controlaTamanho} onCheckedChange={setControlaTamanho} />
              </div>

              {controlaTamanho && (
                <div className="space-y-3 pt-2">
                  <div className="flex gap-2 items-end">
                    <Input
                      placeholder="Ex: 38, 39, P, M, G..."
                      value={novoTamanho}
                      onChange={(e) => setNovoTamanho(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          if (novoTamanho.trim() && !gradeTamanhos.some(g => g.tamanho === novoTamanho.trim())) {
                            setGradeTamanhos([...gradeTamanhos, { tamanho: novoTamanho.trim(), local_estoque_id: "", quantidade: 0 }]);
                            setNovoTamanho("");
                          }
                        }
                      }}
                      className="h-8 text-sm"
                    />
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      onClick={() => {
                        if (novoTamanho.trim() && !gradeTamanhos.some(g => g.tamanho === novoTamanho.trim())) {
                          setGradeTamanhos([...gradeTamanhos, { tamanho: novoTamanho.trim(), local_estoque_id: "", quantidade: 0 }]);
                          setNovoTamanho("");
                        }
                      }}
                    >
                      <Plus className="w-3.5 h-3.5 mr-1" /> Adicionar
                    </Button>
                  </div>

                  {gradeTamanhos.length > 0 && (
                    <div className="border rounded-lg overflow-hidden">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="text-xs">Tamanho</TableHead>
                            <TableHead className="text-xs">Local de Estoque</TableHead>
                            <TableHead className="text-xs w-24">Quantidade</TableHead>
                            <TableHead className="text-xs w-10"></TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {gradeTamanhos.map((item, idx) => (
                            <TableRow key={item.tamanho}>
                              <TableCell className="py-1.5">
                                <Badge variant="secondary">{item.tamanho}</Badge>
                              </TableCell>
                              <TableCell className="py-1.5">
                                <Select
                                  value={item.local_estoque_id}
                                  onValueChange={(val) => {
                                    const updated = [...gradeTamanhos];
                                    updated[idx] = { ...updated[idx], local_estoque_id: val };
                                    setGradeTamanhos(updated);
                                  }}
                                >
                                  <SelectTrigger className="h-7 text-xs">
                                    <SelectValue placeholder="Selecione" />
                                  </SelectTrigger>
                                  <SelectContent>
                                    {locaisAtivos.map((local) => (
                                      <SelectItem key={local.id} value={local.id}>
                                        {local.nome}{local.filial?.nome ? ` (${local.filial.nome})` : ""}
                                      </SelectItem>
                                    ))}
                                  </SelectContent>
                                </Select>
                              </TableCell>
                              <TableCell className="py-1.5">
                                <Input
                                  type="number"
                                  min={0}
                                  className="h-7 text-xs w-20"
                                  value={item.quantidade}
                                  onChange={(e) => {
                                    const updated = [...gradeTamanhos];
                                    updated[idx] = { ...updated[idx], quantidade: parseInt(e.target.value) || 0 };
                                    setGradeTamanhos(updated);
                                  }}
                                />
                              </TableCell>
                              <TableCell className="py-1.5">
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="icon"
                                  className="h-6 w-6"
                                  onClick={() => setGradeTamanhos(gradeTamanhos.filter((_, i) => i !== idx))}
                                >
                                  <Trash2 className="w-3.5 h-3.5 text-destructive" />
                                </Button>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  )}

                  {gradeTamanhos.length === 0 && (
                    <p className="text-xs text-muted-foreground">Adicione ao menos um tamanho à grade</p>
                  )}
                </div>
              )}
            </div>

            <div className="flex justify-end gap-2 pt-4">
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
              <Button type="submit" disabled={isLoading}>
                {isLoading ? "Salvando..." : epi ? "Salvar Alterações" : "Cadastrar"}
              </Button>
            </div>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
