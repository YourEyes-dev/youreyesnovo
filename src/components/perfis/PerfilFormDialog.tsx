import { useState, useEffect } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PermissoesEditor } from "./PermissoesEditor";
import type { PerfilAcesso, PerfilPermissao } from "@/hooks/usePerfisAcesso";
import { calcularNivelRisco, ACOES_DISPONIVEIS } from "@/hooks/usePerfisAcesso";
import { Loader2, AlertTriangle, ShieldAlert } from "lucide-react";
import { cn } from "@/lib/utils";

const schema = z.object({
  nome: z.string().min(2, "Nome obrigatório"),
  descricao: z.string().optional(),
  cor: z.string().optional(),
  icone: z.string().optional(),
  expira_em: z.string().optional(),
  is_perfil_assistido: z.boolean().optional(),
  pode_ver_salario: z.boolean().optional(),
});

type FormData = z.infer<typeof schema>;

const CORES_SUGERIDAS = [
  "#6366f1", "#dc2626", "#7c3aed", "#059669", "#0891b2",
  "#d97706", "#b45309", "#475569", "#64748b", "#ec4899",
];

interface PerfilFormDialogProps {
  open: boolean;
  onClose: () => void;
  perfilInicial?: PerfilAcesso;
  onSubmit: (data: FormData & { permissoes: Partial<PerfilPermissao>[] }) => Promise<void>;
  loading?: boolean;
}

export function PerfilFormDialog({ open, onClose, perfilInicial, onSubmit, loading }: PerfilFormDialogProps) {
  const [permissoes, setPermissoes] = useState<Partial<PerfilPermissao>[]>([]);
  const [tab, setTab] = useState("geral");

  // Sync permissoes when perfilInicial changes
  useEffect(() => {
    setPermissoes(perfilInicial?.permissoes || []);
  }, [perfilInicial?.id, open]);

  const form = useForm<FormData>({
    resolver: zodResolver(schema),
    values: {
      nome: perfilInicial?.nome || "",
      descricao: perfilInicial?.descricao || "",
      cor: perfilInicial?.cor || "#6366f1",
      icone: perfilInicial?.icone || "",
      expira_em: perfilInicial?.expira_em ? perfilInicial.expira_em.substring(0, 10) : "",
      is_perfil_assistido: perfilInicial?.is_perfil_assistido || false,
      // Default TRUE: perfis novos e existentes veem salário até ser desligado.
      pode_ver_salario: perfilInicial?.pode_ver_salario ?? true,
    },
  });

  const risco = calcularNivelRisco(permissoes);
  const temSensivel = permissoes.some((p) =>
    ACOES_DISPONIVEIS.find((a) => a.id === p.acao)?.sensivel
  );

  const handleSubmit = async (data: FormData) => {
    await onSubmit({
      ...data,
      expira_em: data.expira_em || undefined,
      permissoes,
    });
    form.reset();
    setPermissoes([]);
    setTab("geral");
  };

  const handleClose = () => {
    form.reset();
    setPermissoes([]);
    setTab("geral");
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-3xl max-h-[92vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle>{perfilInicial ? `Editar Perfil — ${perfilInicial.nome}` : "Novo Perfil de Acesso"}</DialogTitle>
        </DialogHeader>

        <Tabs value={tab} onValueChange={setTab} className="flex-1 flex flex-col min-h-0">
          <TabsList className="shrink-0">
            <TabsTrigger value="geral">Informações gerais</TabsTrigger>
            <TabsTrigger value="permissoes">
              Permissões
              {permissoes.length > 0 && (
                <span className="ml-1.5 bg-primary text-primary-foreground text-[10px] rounded-full px-1.5 py-0.5">
                  {permissoes.length}
                </span>
              )}
            </TabsTrigger>
          </TabsList>

          <Form {...form}>
            <form onSubmit={form.handleSubmit(handleSubmit)} className="flex-1 flex flex-col min-h-0">
              <div className="flex-1 overflow-y-auto py-4 space-y-1">
                <TabsContent value="geral" className="mt-0 space-y-4">
                  <FormField control={form.control} name="nome" render={({ field }) => (
                    <FormItem>
                      <FormLabel>Nome do perfil *</FormLabel>
                      <FormControl><Input placeholder="Ex: Gestor de RH" {...field} /></FormControl>
                      <FormMessage />
                    </FormItem>
                  )} />
                  <FormField control={form.control} name="descricao" render={({ field }) => (
                    <FormItem>
                      <FormLabel>Descrição</FormLabel>
                      <FormControl>
                        <Textarea placeholder="Descreva o propósito deste perfil e quem deve usá-lo..." rows={3} {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )} />
                  <div className="grid grid-cols-2 gap-4">
                    <FormField control={form.control} name="cor" render={({ field }) => (
                      <FormItem>
                        <FormLabel>Cor de identificação</FormLabel>
                        <div className="flex items-center gap-2 flex-wrap">
                          {CORES_SUGERIDAS.map((cor) => (
                            <button
                              key={cor}
                              type="button"
                              onClick={() => field.onChange(cor)}
                              className="w-6 h-6 rounded-full border-2 transition-transform hover:scale-110"
                              style={{
                                backgroundColor: cor,
                                borderColor: field.value === cor ? "#000" : "transparent",
                                outline: field.value === cor ? `2px solid ${cor}` : "none",
                                outlineOffset: "2px",
                              }}
                            />
                          ))}
                          <Input
                            type="color"
                            className="w-8 h-7 p-0.5 cursor-pointer"
                            value={field.value || "#6366f1"}
                            onChange={field.onChange}
                          />
                        </div>
                        <FormMessage />
                      </FormItem>
                    )} />
                    <FormField control={form.control} name="expira_em" render={({ field }) => (
                      <FormItem>
                        <FormLabel>Data de expiração <span className="text-muted-foreground">(opcional)</span></FormLabel>
                        <FormControl>
                          <Input type="date" {...field} />
                        </FormControl>
                        <p className="text-[11px] text-muted-foreground">Útil para perfis temporários de auditoria</p>
                        <FormMessage />
                      </FormItem>
                    )} />
                  </div>
                  <FormField control={form.control} name="is_perfil_assistido" render={({ field }) => (
                    <FormItem className="flex items-center gap-3 rounded-lg border border-border p-3">
                      <FormControl>
                        <Switch checked={field.value} onCheckedChange={field.onChange} />
                      </FormControl>
                      <div>
                        <FormLabel className="text-[13px] font-medium">Perfil assistido (sem login)</FormLabel>
                        <p className="text-[11px] text-muted-foreground">Para colaboradores cadastrados que não acessam o sistema diretamente</p>
                      </div>
                    </FormItem>
                  )} />

                  <FormField control={form.control} name="pode_ver_salario" render={({ field }) => (
                    <FormItem className="flex items-center gap-3 rounded-lg border border-border p-3">
                      <FormControl>
                        <Switch checked={field.value} onCheckedChange={field.onChange} />
                      </FormControl>
                      <div>
                        <FormLabel className="text-[13px] font-medium">Pode ver salário</FormLabel>
                        <p className="text-[11px] text-muted-foreground">
                          Quando desligado, o salário e os valores de remuneração ficam
                          ocultos em todas as telas para quem tem este perfil — mesmo nas
                          telas a que ele tem acesso (cadastro, folha, férias…).
                        </p>
                      </div>
                    </FormItem>
                  )} />

                  {/* Preview de risco */}
                  {risco !== "normal" && (
                    <div className={cn(
                      "flex items-center gap-2 text-[12px] rounded-lg border p-3",
                      risco === "critico"
                        ? "bg-red-50 dark:bg-red-950/30 border-red-200 dark:border-red-800 text-red-700 dark:text-red-400"
                        : "bg-amber-50 dark:bg-amber-950/30 border-amber-200 dark:border-amber-800 text-amber-700 dark:text-amber-400"
                    )}>
                      {risco === "critico" ? <ShieldAlert className="w-4 h-4 flex-shrink-0" /> : <AlertTriangle className="w-4 h-4 flex-shrink-0" />}
                      <div>
                        <p className="font-medium">Nível de risco: {risco === "critico" ? "Crítico" : "Elevado"}</p>
                        <p className="text-[11px] opacity-80">Este perfil contém permissões sensíveis. Atribua com critério e justificativa.</p>
                      </div>
                    </div>
                  )}
                </TabsContent>

                <TabsContent value="permissoes" className="mt-0">
                  <PermissoesEditor permissoes={permissoes} onChange={setPermissoes} />
                </TabsContent>
              </div>

              <DialogFooter className="shrink-0 pt-4 border-t">
                <Button type="button" variant="outline" onClick={handleClose}>Cancelar</Button>
                <Button type="submit" disabled={loading}>
                  {loading && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                  {perfilInicial ? "Salvar alterações" : "Criar perfil"}
                </Button>
              </DialogFooter>
            </form>
          </Form>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}
