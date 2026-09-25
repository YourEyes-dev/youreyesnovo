import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { motion } from "framer-motion";
import { Link2, Copy, Send, ToggleLeft, ToggleRight, Loader2, ExternalLink, RefreshCw, ShieldCheck, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";
import { confirm } from "@/components/ui/confirm-dialog";

function generateToken(): string {
  return crypto.randomUUID().replace(/-/g, "").substring(0, 16);
}

// Mesma lógica do link de ponto: produção usa o domínio próprio; os demais
// ambientes (teste/homologação/preview/localhost) usam o próprio endereço + base,
// para o link abrir no MESMO ambiente onde foi gerado.
function getOuvidoriaExternaUrl(token: string): string {
  const host = window.location.hostname;
  const ehProducao = host === "youreyes.com.br" || host.endsWith(".youreyes.com.br");
  const base = import.meta.env.BASE_URL || "/";
  const raiz = ehProducao ? "https://youreyes.com.br/" : `${window.location.origin}${base}`;
  return `${raiz}ouvidoria-externa/${token}`;
}

export function OuvidoriaLinkTab() {
  const { tenantId } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState(false);

  const { data: link, isLoading } = useQuery({
    queryKey: ["ouvidoria-link", tenantId],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data, error } = await fromTable("ouvidoria_links")
        .select("*")
        .eq("tenant_id", tenantId)
        .maybeSingle();
      if (error) throw error;
      return (data || null) as any;
    },
    enabled: !!tenantId,
  });

  const gerarLink = useMutation({
    mutationFn: async () => {
      if (!tenantId) throw new Error("Tenant não encontrado");
      const { error } = await fromTable("ouvidoria_links").insert({
        tenant_id: tenantId,
        token: generateToken(),
        ativo: true,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria-link"] });
      toast({ title: "Link da ouvidoria gerado!" });
    },
    onError: (e: any) => toast({ title: "Erro ao gerar link", description: e.message, variant: "destructive" }),
  });

  const toggleAtivo = useMutation({
    mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
      const { error } = await fromTable("ouvidoria_links").update({ ativo }).eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria-link"] });
      toast({ title: "Status atualizado!" });
    },
  });

  const regerar = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await fromTable("ouvidoria_links")
        .update({ token: generateToken(), ativo: true })
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["ouvidoria-link"] });
      toast({ title: "Novo link gerado!", description: "O link anterior deixou de funcionar." });
    },
    onError: (e: any) => toast({ title: "Erro ao regerar", description: e.message, variant: "destructive" }),
  });

  const url = link ? getOuvidoriaExternaUrl(link.token) : "";

  const copyLink = () => {
    navigator.clipboard.writeText(url);
    toast({ title: "Link copiado!" });
  };

  const sendWhatsApp = () => {
    const msg = encodeURIComponent(
      `Olá! 👋\n\nCanal de Ouvidoria da empresa. Registre sugestões, reclamações, denúncias, elogios ou dúvidas pelo link:\n${url}\n\nVocê pode se identificar ou registrar de forma anônima.`
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
    if (ok) {
      setBusy(true);
      try {
        await regerar.mutateAsync(id);
      } finally {
        setBusy(false);
      }
    }
  };

  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="space-y-4">
      <div>
        <h3 className="text-lg font-semibold flex items-center gap-2">
          <Link2 className="w-5 h-5 text-primary" /> Link público da Ouvidoria
        </h3>
        <p className="text-sm text-muted-foreground">
          Um único link para toda a empresa. O funcionário registra manifestações <strong>sem precisar logar</strong>, podendo se identificar por CPF ou de forma anônima.
        </p>
      </div>

      {isLoading ? (
        <Card><CardContent className="py-10 text-center"><Loader2 className="w-5 h-5 animate-spin mx-auto" /></CardContent></Card>
      ) : !link ? (
        <Card>
          <CardContent className="py-10 text-center space-y-4">
            <Link2 className="w-10 h-10 text-muted-foreground/50 mx-auto" />
            <div>
              <p className="font-medium">Nenhum link da ouvidoria ainda</p>
              <p className="text-sm text-muted-foreground">Gere um link único para distribuir a todos os colaboradores.</p>
            </div>
            <Button onClick={() => gerarLink.mutate()} disabled={gerarLink.isPending}>
              {gerarLink.isPending ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Plus className="w-4 h-4 mr-2" />}
              Gerar link da ouvidoria
            </Button>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center justify-between gap-2">
              <span>Link da empresa</span>
              <Badge variant={link.ativo ? "default" : "secondary"}>{link.ativo ? "Ativo" : "Inativo"}</Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center gap-2 rounded-md border bg-muted/40 p-2.5">
              <code className="text-xs sm:text-sm break-all flex-1">{url}</code>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={copyLink}><Copy className="w-3.5 h-3.5 mr-1.5" /> Copiar</Button>
              <Button variant="outline" size="sm" onClick={sendWhatsApp}><Send className="w-3.5 h-3.5 mr-1.5" /> WhatsApp</Button>
              <Button variant="outline" size="sm" onClick={() => window.open(url, "_blank")}><ExternalLink className="w-3.5 h-3.5 mr-1.5" /> Abrir</Button>
              <Button variant="outline" size="sm" onClick={() => toggleAtivo.mutate({ id: link.id, ativo: !link.ativo })}>
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
                O mesmo link serve para toda a empresa. As manifestações caem na sua Ouvidoria com o roteamento já configurado. Se o link vazar, use “Gerar novo link”.
              </span>
            </div>
          </CardContent>
        </Card>
      )}
    </motion.div>
  );
}
