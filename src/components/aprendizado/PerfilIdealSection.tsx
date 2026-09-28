import { useEffect, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Fingerprint, Save, Loader2, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import {
  ARQUETIPO_LABEL, MOTOR_LABEL, MODO_LABEL, MAPA_ALGORITMO_VERSAO,
  type Arquetipo, type Motor,
} from "@/data/instrumentos/mapaComportamental";

interface PerfilIdealSectionProps {
  cargoId: string;
  cargoNome: string;
}

type ModoIdeal = "constante" | "cadenciado" | "misto";
const SEM = "__sem__";

const ARQUETIPOS: Arquetipo[] = ["pioneiro", "conector", "guardiao", "estrategista"];
const MOTORES: Motor[] = ["racional", "relacional", "pragmatico"];
const MODOS: ModoIdeal[] = ["constante", "cadenciado", "misto"];
const MODO_IDEAL_LABEL: Record<ModoIdeal, string> = { ...MODO_LABEL, misto: "Misto (flexível)" };

export function PerfilIdealSection({ cargoId, cargoNome }: PerfilIdealSectionProps) {
  const { tenantId, user, profile, hasMinimumRole } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const qc = useQueryClient();
  const podeEditar = hasMinimumRole("admin");

  const { data: perfil, isLoading } = useQuery({
    queryKey: ["cargo_perfil_ideal", cargoId],
    queryFn: async () => {
      const { data } = await fromTable("cargo_perfil_ideal")
        .select("*")
        .eq("tenant_id", tenantId!)
        .eq("cargo_id", cargoId)
        .maybeSingle() as { data: Record<string, unknown> | null };
      return data;
    },
    enabled: !!tenantId && !!cargoId,
  });

  const [arquetipo, setArquetipo] = useState<string>(SEM);
  const [motores, setMotores] = useState<Motor[]>([]);
  const [modo, setModo] = useState<string>(SEM);
  const [observacoes, setObservacoes] = useState("");

  useEffect(() => {
    setArquetipo((perfil?.arquetipo_ideal as string) || SEM);
    setMotores(((perfil?.motor_ideal as Motor[]) || []).filter((m) => MOTORES.includes(m)));
    setModo((perfil?.modo_ideal as string) || SEM);
    setObservacoes((perfil?.observacoes as string) || "");
  }, [perfil]);

  const salvar = useMutation({
    mutationFn: async () => {
      const payload = {
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        cargo_id: cargoId,
        arquetipo_ideal: arquetipo === SEM ? null : arquetipo,
        motor_ideal: motores.length ? motores : null,
        modo_ideal: modo === SEM ? null : modo,
        observacoes: observacoes.trim() || null,
        definido_por: user?.id || null,
        definido_por_nome: profile?.nome_completo || null,
        algoritmo_versao: MAPA_ALGORITMO_VERSAO,
        updated_at: new Date().toISOString(),
      };
      const { error } = await fromTable("cargo_perfil_ideal")
        .upsert(payload, { onConflict: "tenant_id,cargo_id" });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["cargo_perfil_ideal", cargoId] });
      qc.invalidateQueries({ queryKey: ["completude_perfil_ideal"] });
      toast.success("Perfil comportamental ideal salvo.");
    },
    onError: (e: Error) => toast.error("Erro ao salvar: " + e.message),
  });

  const toggleMotor = (m: Motor) =>
    setMotores((prev) => (prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m]));

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-10 text-muted-foreground">
        <Loader2 className="w-5 h-5 animate-spin mr-2" /> Carregando...
      </div>
    );
  }

  return (
    <div className="space-y-5 max-w-2xl">
      <div className="rounded-lg border border-primary/20 bg-primary/5 p-4 flex items-start gap-3">
        <Fingerprint className="w-5 h-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-medium text-foreground">Estilo comportamental esperado da função</p>
          <p className="text-xs text-muted-foreground mt-1">
            Define o arquétipo, o motor e o modo que <strong>tendem</strong> a fluir nesta função. É referência de
            desenvolvimento — usada para mostrar a aderência de estilo na ficha do Mapa. Não é critério de
            seleção, promoção ou desligamento; não existe perfil melhor nem pior.
          </p>
        </div>
      </div>

      {!podeEditar && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Lock className="w-3.5 h-3.5" /> Somente RH/Admin edita o perfil ideal — você está vendo em modo leitura.
        </div>
      )}

      <div className="space-y-2">
        <Label>Arquétipo esperado</Label>
        <Select value={arquetipo} onValueChange={setArquetipo} disabled={!podeEditar}>
          <SelectTrigger><SelectValue placeholder="Não definido" /></SelectTrigger>
          <SelectContent>
            <SelectItem value={SEM}>Não definido</SelectItem>
            {ARQUETIPOS.map((a) => <SelectItem key={a} value={a}>{ARQUETIPO_LABEL[a]}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-2">
        <Label>Motor(es) de decisão esperado(s)</Label>
        <div className="flex flex-wrap gap-2">
          {MOTORES.map((m) => (
            <Button
              key={m}
              type="button"
              size="sm"
              variant={motores.includes(m) ? "default" : "outline"}
              onClick={() => toggleMotor(m)}
              disabled={!podeEditar}
            >
              {MOTOR_LABEL[m]}
            </Button>
          ))}
        </div>
        <p className="text-xs text-muted-foreground">Pode marcar mais de um quando a função aceita motores diferentes.</p>
      </div>

      <div className="space-y-2">
        <Label>Modo de contexto esperado</Label>
        <Select value={modo} onValueChange={setModo} disabled={!podeEditar}>
          <SelectTrigger><SelectValue placeholder="Não definido" /></SelectTrigger>
          <SelectContent>
            <SelectItem value={SEM}>Não definido</SelectItem>
            {MODOS.map((m) => <SelectItem key={m} value={m}>{MODO_IDEAL_LABEL[m]}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-2">
        <Label>Observações (opcional)</Label>
        <Textarea
          value={observacoes}
          onChange={(e) => setObservacoes(e.target.value)}
          placeholder="Contexto do estilo esperado para esta função..."
          className="min-h-[80px]"
          disabled={!podeEditar}
        />
      </div>

      {podeEditar && (
        <div className="flex justify-end">
          <Button onClick={() => salvar.mutate()} disabled={salvar.isPending} className="gap-2">
            {salvar.isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            Salvar perfil ideal
          </Button>
        </div>
      )}
    </div>
  );
}
