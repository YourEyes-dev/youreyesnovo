import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Search, Copy, Check, FileSignature, Clock, CheckCircle2, XCircle, ExternalLink } from "lucide-react";
import { format } from "date-fns";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { toast } from "sonner";

const PUBLIC_BASE = "https://www.youreyes.com.br";

interface Assinatura {
  id: string;
  cargo_nome: string;
  colaborador_nome: string;
  gestor_nome: string | null;
  status: string;
  data_envio: string;
  data_assinatura_colaborador: string | null;
  data_assinatura_gestor: string | null;
  data_conclusao: string | null;
  documento_arquivado_id: string | null;
}

const STATUS_META: Record<string, { label: string; color: string; icon: any }> = {
  aguardando_colaborador: { label: "Aguardando colaborador", color: "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300", icon: Clock },
  aguardando_gestor: { label: "Aguardando gestor", color: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300", icon: Clock },
  concluido: { label: "Concluído", color: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300", icon: CheckCircle2 },
  cancelado: { label: "Cancelado", color: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300", icon: XCircle },
};

export function AssinaturasManualTab() {
  const { tenantId } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const [search, setSearch] = useState("");
  const [copied, setCopied] = useState<string | null>(null);

  const { data: assinaturas = [], isLoading } = useQuery({
    queryKey: ["manual_funcao_assinaturas", tenantId, empresaAtivaId],
    queryFn: async (): Promise<Assinatura[]> => {
      if (!tenantId) return [];
      let q = fromTable("manual_funcao_assinaturas")
        .select("id, cargo_nome, colaborador_nome, gestor_nome, status, data_envio, data_assinatura_colaborador, data_assinatura_gestor, data_conclusao, documento_arquivado_id")
        .eq("tenant_id", tenantId)
        .order("data_envio", { ascending: false }) as any;
      if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
      const { data } = await q;
      return (data || []) as Assinatura[];
    },
    enabled: !!tenantId,
    refetchInterval: 15000,
  });

  const filtradas = useMemo(() => {
    const s = search.trim().toLowerCase();
    if (!s) return assinaturas;
    return assinaturas.filter((a) =>
      a.colaborador_nome.toLowerCase().includes(s) ||
      a.cargo_nome.toLowerCase().includes(s) ||
      (a.gestor_nome || "").toLowerCase().includes(s)
    );
  }, [assinaturas, search]);

  const handleCopiarLinks = async (assinaturaId: string) => {
    const { data } = await fromTable("manual_funcao_links")
      .select("token, tipo_assinante, used_at")
      .eq("assinatura_id", assinaturaId) as any;
    if (!data?.length) { toast.error("Nenhum link encontrado."); return; }
    const text = data.map((l: any) =>
      `${l.tipo_assinante === "colaborador" ? "Colaborador" : "Gestor"}${l.used_at ? " (usado)" : ""}: ${PUBLIC_BASE}/manual-funcao/assinatura/${l.token}`
    ).join("\n");
    await navigator.clipboard.writeText(text);
    setCopied(assinaturaId);
    setTimeout(() => setCopied(null), 1500);
    toast.success("Links copiados!");
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input
            placeholder="Buscar por colaborador, cargo, gestor..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>
        <Badge variant="outline" className="ml-auto">{filtradas.length} envio(s)</Badge>
      </div>

      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => <Skeleton key={i} className="h-20 w-full rounded-xl" />)}
        </div>
      ) : filtradas.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            <FileSignature className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>Nenhum manual enviado para assinatura ainda.</p>
            <p className="text-sm mt-1">Gere um manual em "Funções" e clique em "Enviar para Assinatura".</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {filtradas.map((a) => {
            const meta = STATUS_META[a.status] || STATUS_META.aguardando_colaborador;
            const Icon = meta.icon;
            return (
              <Card key={a.id} className="hover:shadow-md transition-shadow">
                <CardContent className="py-3 px-4">
                  <div className="flex items-center justify-between flex-wrap gap-3">
                    <div className="flex-1 min-w-[240px]">
                      <div className="font-medium text-sm">{a.colaborador_nome}</div>
                      <div className="text-xs text-muted-foreground">
                        {a.cargo_nome}
                        {a.gestor_nome ? ` · Gestor: ${a.gestor_nome}` : ""}
                      </div>
                      <div className="text-xs text-muted-foreground mt-1">
                        Enviado: {format(new Date(a.data_envio), "dd/MM/yyyy HH:mm")}
                        {a.data_assinatura_colaborador ? ` · Colab: ${format(new Date(a.data_assinatura_colaborador), "dd/MM HH:mm")}` : ""}
                        {a.data_assinatura_gestor ? ` · Gestor: ${format(new Date(a.data_assinatura_gestor), "dd/MM HH:mm")}` : ""}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge className={meta.color}>
                        <Icon className="w-3 h-3 mr-1" /> {meta.label}
                      </Badge>
                      <Button size="sm" variant="outline" onClick={() => handleCopiarLinks(a.id)}>
                        {copied === a.id ? <Check className="w-3.5 h-3.5 mr-1" /> : <Copy className="w-3.5 h-3.5 mr-1" />}
                        Links
                      </Button>
                      {a.documento_arquivado_id && (
                        <Button size="sm" variant="outline" asChild>
                          <a href={`/documentos?doc=${a.documento_arquivado_id}`}>
                            <ExternalLink className="w-3.5 h-3.5 mr-1" /> Documento
                          </a>
                        </Button>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
