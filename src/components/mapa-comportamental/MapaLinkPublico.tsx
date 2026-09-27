import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Link2, Copy, Send, ToggleLeft, ToggleRight, Loader2, ExternalLink, RefreshCw, ShieldCheck, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { toast } from "sonner";
import { confirm } from "@/components/ui/confirm-dialog";

interface MapaLinkRow {
  id: string;
  tenant_id: string;
  empresa_id: string | null;
  token: string;
  ativo: boolean;
}

function gerarToken(): string {
  return crypto.randomUUID().replace(/-/g, "").substring(0, 16);
}

// Produção usa o domínio próprio; os demais ambientes usam o próprio endereço +
// base, para o link abrir no MESMO ambiente onde foi gerado (mesmo padrão de
// Ponto/Ouvidoria).
function urlPublica(token: string): string {
  const host = window.location.hostname;
  const ehProducao = host === "youreyes.com.br" || host.endsWith(".youreyes.com.br");
  const base = import.meta.env.BASE_URL || "/";
  const raiz = ehProducao ? "https://youreyes.com.br/" : `${window.location.origin}${base}`;
  return `${raiz}mapa-publico/${token}`;
}

export function MapaLinkPublico() {
  const { tenantId } = useAuth();
  const { empresaAtivaId, empresaAtiva } = useEmpresaAtiva();
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);

  const empresaNome = empresaAtiva?.nome_fantasia || empresaAtiva?.razao_social || "sua empresa";
  const chave = ["mapa-link", tenantId, empresaAtivaId ?? "sem-empresa"];

  const { data: link, isLoading } = useQuery({
    queryKey: chave,
    queryFn: async (): Promise<MapaLinkRow | null> => {
      if (!tenantId) return null;
      let q = fromTable("mapa_comportamental_links").select("*").eq("tenant_id", tenantId);
      q = empresaAtivaId ? q.eq("empresa_id", empresaAtivaId) : q.is("empresa_id", null);
      const { data, error } = await q.maybeSingle();
      if (error) throw error;
      return (data ?? null) as MapaLinkRow | null;
    },
    enabled: !!tenantId,
  });

  const gerar = useMutation({
    mutationFn: async () => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { error } = await fromTable("mapa_comportamental_links").insert({
        tenant_id: tenantId,
        empresa_id: empresaAtivaId || null,
        token: gerarToken(),
        ativo: true,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-link"] });
      toast.success("Link do Mapa gerado!");
    },
    onError: (e: Error) => toast.error("Erro ao gerar link", { description: e.message }),
  });

  const toggle = useMutation({
    mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
      const { error } = await fromTable("mapa_comportamental_links").update({ ativo }).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["mapa-link"] }),
  });

  const regerar = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await fromTable("mapa_comportamental_links")
        .update({ token: gerarToken(), ativo: true })
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-link"] });
      toast.success("Novo link gerado!", { description: "O link anterior deixou de funcionar." });
    },
  });

  const url = link ? urlPublica(link.token) : "";

  const copiar = () => { navigator.clipboard.writeText(url); toast.success("Link copiado!"); };
  const whatsapp = () => {
    const msg = encodeURIComponent(
      `Olá! 👋\n\nVocê foi convidado a responder o Mapa Comportamental (28 perguntas rápidas sobre o seu jeito de trabalhar). É voluntário e o resultado é seu.\n\n${url}\n\nBasta informar o seu CPF para começar.`,
    );
    window.open(`https://wa.me/?text=${msg}`, "_blank");
  };
  const handleRegerar = async (id: string) => {
    const ok = await confirm({
      title: "Gerar um novo link?",
      description: "O link atual deixará de funcionar. Use isto se o link vazou ou precisa ser trocado.",
      confirmLabel: "Gerar novo link",
      variant: "destructive",
    });
    if (ok) { setBusy(true); try { await regerar.mutateAsync(id); } finally { setBusy(false); } }
  };

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-base font-semibold flex items-center gap-2">
          <Link2 className="w-4 h-4 text-primary" /> Link para quem não tem acesso ao sistema
        </h3>
        <p className="text-sm text-muted-foreground">
          Um link por empresa (<strong>{empresaNome}</strong>) para o funcionário responder o Mapa{" "}
          <strong>sem precisar logar</strong>. Ele se identifica pelo CPF e a resposta fica registrada nesta empresa.
        </p>
      </div>

      {isLoading ? (
        <Card><CardContent className="py-8 text-center"><Loader2 className="w-5 h-5 animate-spin mx-auto" /></CardContent></Card>
      ) : !link ? (
        <Card>
          <CardContent className="py-8 text-center space-y-3">
            <Link2 className="w-9 h-9 text-muted-foreground/50 mx-auto" />
            <p className="text-sm text-muted-foreground">Nenhum link gerado para {empresaNome} ainda.</p>
            <Button onClick={() => gerar.mutate()} disabled={gerar.isPending}>
              {gerar.isPending ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Plus className="w-4 h-4 mr-2" />}
              Gerar link do Mapa
            </Button>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm flex items-center justify-between gap-2">
              <span>Link de {empresaNome}</span>
              <Badge variant={link.ativo ? "default" : "secondary"}>{link.ativo ? "Ativo" : "Inativo"}</Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center gap-2 rounded-md border bg-muted/40 p-2.5">
              <code className="text-xs sm:text-sm break-all flex-1">{url}</code>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={copiar}><Copy className="w-3.5 h-3.5 mr-1.5" /> Copiar</Button>
              <Button variant="outline" size="sm" onClick={whatsapp}><Send className="w-3.5 h-3.5 mr-1.5" /> WhatsApp</Button>
              <Button variant="outline" size="sm" onClick={() => window.open(url, "_blank")}><ExternalLink className="w-3.5 h-3.5 mr-1.5" /> Abrir</Button>
              <Button variant="outline" size="sm" onClick={() => toggle.mutate({ id: link.id, ativo: !link.ativo })}>
                {link.ativo ? <ToggleRight className="w-4 h-4 mr-1.5 text-emerald-500" /> : <ToggleLeft className="w-4 h-4 mr-1.5" />}
                {link.ativo ? "Desativar" : "Ativar"}
              </Button>
              <Button variant="outline" size="sm" onClick={() => handleRegerar(link.id)} disabled={busy}>
                {busy ? <Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" /> : <RefreshCw className="w-3.5 h-3.5 mr-1.5" />}
                Gerar novo link
              </Button>
            </div>
            <div className="flex items-start gap-2 rounded-md border border-sky-500/30 bg-sky-500/5 p-3 text-xs text-muted-foreground">
              <ShieldCheck className="w-4 h-4 text-sky-600 shrink-0 mt-0.5" />
              <span>
                O mesmo link serve para todos os funcionários desta empresa. As respostas entram no módulo já
                vinculadas a {empresaNome}, identificadas pelo CPF. Se o link vazar, use “Gerar novo link”.
              </span>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
