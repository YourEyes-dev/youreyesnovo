import { useMemo, useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Loader2, Send, Link2, Copy, Check } from "lucide-react";
import { toast } from "sonner";
import { useColaboradores, type Colaborador } from "@/hooks/useColaboradores";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { buildTermoCienciaHtml } from "@/lib/manualFuncaoTermo";

interface Props {
  open: boolean;
  onClose: () => void;
  cargoId: string;
  cargoNome: string;
  manualHtml: string;
  manualTitulo: string;
}

interface LinkGerado {
  colaboradorNome: string;
  tokenColaborador: string;
  tokenGestor: string | null;
}

const PUBLIC_BASE = "https://www.youreyes.com.br";

function publicLink(token: string) {
  return `${PUBLIC_BASE}/manual-funcao/assinatura/${token}`;
}

export function EnviarManualAssinaturaDialog({ open, onClose, cargoId, cargoNome, manualHtml, manualTitulo }: Props) {
  const { tenantId, user, profile } = useAuth();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { colaboradores, isLoading } = useColaboradores();

  const [selecionados, setSelecionados] = useState<Set<string>>(new Set());
  const [gestorNome, setGestorNome] = useState("");
  const [gestorCpf, setGestorCpf] = useState("");
  const [gestorEmail, setGestorEmail] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [linksGerados, setLinksGerados] = useState<LinkGerado[]>([]);
  const [copied, setCopied] = useState<string | null>(null);

  const cargoNomeLc = cargoNome.trim().toLowerCase();
  // Prioriza o vínculo canônico cargo_id (O2-A); só cai no match por texto do
  // nome quando o colaborador ainda não tem cargo_id resolvido (legado/backfill).
  const colaboradoresDoCargo = useMemo(
    () =>
      colaboradores.filter((c) =>
        c.cargo_id
          ? c.cargo_id === cargoId
          : (c.cargo || "").trim().toLowerCase() === cargoNomeLc
      ),
    [colaboradores, cargoNomeLc, cargoId]
  );

  const handleToggle = (id: string) => {
    setSelecionados((prev) => {
      const n = new Set(prev);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });
  };

  const handleSelectAll = () => {
    if (selecionados.size === colaboradoresDoCargo.length) {
      setSelecionados(new Set());
    } else {
      setSelecionados(new Set(colaboradoresDoCargo.map((c) => c.id)));
    }
  };

  const handleEnviar = async () => {
    if (!tenantId || !user) return;
    if (selecionados.size === 0) {
      toast.error("Selecione ao menos um colaborador.");
      return;
    }
    setEnviando(true);
    try {
      const novos: LinkGerado[] = [];
      for (const colab of colaboradoresDoCargo.filter((c) => selecionados.has(c.id))) {
        const termoHtml = buildTermoCienciaHtml({
          cargoNome,
          colaboradorNome: colab.nome_completo,
          colaboradorCpf: colab.cpf,
          empresaNome: profile?.nome_completo || "",
          gestorNome: gestorNome || colab.gestor_imediato || undefined,
        });

        const { data: ass, error } = await fromTable("manual_funcao_assinaturas")
          .insert({
            tenant_id: tenantId,
            empresa_id: empresaAtivaId || colab.empresa_id || null,
            cargo_id: cargoId,
            cargo_nome: cargoNome,
            colaborador_id: colab.id,
            colaborador_nome: colab.nome_completo,
            colaborador_cpf: colab.cpf,
            gestor_id: null,
            gestor_nome: gestorNome || colab.gestor_imediato || null,
            gestor_cpf: gestorCpf || null,
            gestor_email: gestorEmail || null,
            manual_html_snapshot: manualHtml,
            termo_html: termoHtml,
            manual_titulo: manualTitulo,
            enviado_por: user.id,
            enviado_por_nome: profile?.nome_completo || "",
          })
          .select("id")
          .single() as { data: { id: string } | null; error: any };

        if (error || !ass) throw error || new Error("Falha ao criar assinatura");

        const tokenColaborador = crypto.randomUUID() + "-" + crypto.randomUUID().slice(0, 8);
        const tokenGestor = (gestorNome || colab.gestor_imediato)
          ? crypto.randomUUID() + "-" + crypto.randomUUID().slice(0, 8)
          : null;

        const linksRows: any[] = [
          { tenant_id: tenantId, assinatura_id: ass.id, tipo_assinante: "colaborador", token: tokenColaborador },
        ];
        if (tokenGestor) {
          linksRows.push({ tenant_id: tenantId, assinatura_id: ass.id, tipo_assinante: "gestor", token: tokenGestor });
        }
        const { error: errLinks } = await fromTable("manual_funcao_links").insert(linksRows);
        if (errLinks) throw errLinks;

        novos.push({ colaboradorNome: colab.nome_completo, tokenColaborador, tokenGestor });
      }

      setLinksGerados(novos);
      toast.success(`${novos.length} link(s) gerado(s) com sucesso!`);
    } catch (err: any) {
      console.error(err);
      toast.error(err.message || "Erro ao gerar links de assinatura");
    } finally {
      setEnviando(false);
    }
  };

  const handleCopy = async (token: string) => {
    await navigator.clipboard.writeText(publicLink(token));
    setCopied(token);
    setTimeout(() => setCopied(null), 1500);
  };

  const handleClose = () => {
    setSelecionados(new Set());
    setGestorNome("");
    setGestorCpf("");
    setGestorEmail("");
    setLinksGerados([]);
    onClose();
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Send className="w-5 h-5 text-primary" />
            Enviar Manual para Assinatura — {cargoNome}
          </DialogTitle>
        </DialogHeader>

        {linksGerados.length === 0 ? (
          <div className="space-y-4">
            <div>
              <div className="flex items-center justify-between mb-2">
                <Label className="text-sm font-medium">Colaboradores deste cargo</Label>
                <Button variant="ghost" size="sm" onClick={handleSelectAll} disabled={!colaboradoresDoCargo.length}>
                  {selecionados.size === colaboradoresDoCargo.length ? "Desmarcar todos" : "Selecionar todos"}
                </Button>
              </div>
              <ScrollArea className="h-48 border rounded p-2">
                {isLoading ? (
                  <div className="flex items-center justify-center h-full text-sm text-muted-foreground">
                    Carregando...
                  </div>
                ) : colaboradoresDoCargo.length === 0 ? (
                  <div className="text-sm text-muted-foreground py-8 text-center">
                    Nenhum colaborador ativo encontrado para este cargo.
                  </div>
                ) : (
                  <div className="space-y-1">
                    {colaboradoresDoCargo.map((c) => (
                      <label key={c.id} className="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-muted cursor-pointer">
                        <Checkbox checked={selecionados.has(c.id)} onCheckedChange={() => handleToggle(c.id)} />
                        <span className="text-sm flex-1">{c.nome_completo}</span>
                        <span className="text-xs text-muted-foreground">{c.cpf}</span>
                      </label>
                    ))}
                  </div>
                )}
              </ScrollArea>
            </div>

            <div className="space-y-3 border-t pt-3">
              <Label className="text-sm font-medium">Gestor Imediato (opcional)</Label>
              <p className="text-xs text-muted-foreground">
                Se informado, o gestor receberá um link para assinar após o colaborador. Caso contrário, será usado o gestor cadastrado no perfil de cada colaborador.
              </p>
              <div className="grid grid-cols-2 gap-2">
                <Input placeholder="Nome do gestor" value={gestorNome} onChange={(e) => setGestorNome(e.target.value)} />
                <Input placeholder="CPF do gestor (validação)" value={gestorCpf} onChange={(e) => setGestorCpf(e.target.value)} />
              </div>
              <Input placeholder="E-mail do gestor (opcional)" value={gestorEmail} onChange={(e) => setGestorEmail(e.target.value)} />
            </div>

            <DialogFooter>
              <Button variant="outline" onClick={handleClose}>Cancelar</Button>
              <Button onClick={handleEnviar} disabled={enviando || selecionados.size === 0}>
                {enviando ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Send className="w-4 h-4 mr-2" />}
                Gerar Links ({selecionados.size})
              </Button>
            </DialogFooter>
          </div>
        ) : (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Links gerados. Compartilhe com cada colaborador (e gestor, quando aplicável):
            </p>
            <ScrollArea className="h-80 border rounded p-3">
              <div className="space-y-3">
                {linksGerados.map((l) => (
                  <div key={l.tokenColaborador} className="border rounded p-3 space-y-2">
                    <div className="font-medium text-sm">{l.colaboradorNome}</div>
                    <div className="flex items-center gap-2">
                      <Badge variant="secondary" className="shrink-0">Colaborador</Badge>
                      <Input readOnly value={publicLink(l.tokenColaborador)} className="text-xs h-8" />
                      <Button size="sm" variant="outline" onClick={() => handleCopy(l.tokenColaborador)}>
                        {copied === l.tokenColaborador ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                      </Button>
                    </div>
                    {l.tokenGestor && (
                      <div className="flex items-center gap-2">
                        <Badge variant="outline" className="shrink-0">Gestor</Badge>
                        <Input readOnly value={publicLink(l.tokenGestor)} className="text-xs h-8" />
                        <Button size="sm" variant="outline" onClick={() => handleCopy(l.tokenGestor!)}>
                          {copied === l.tokenGestor ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                        </Button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </ScrollArea>
            <DialogFooter>
              <Button onClick={handleClose}>
                <Link2 className="w-4 h-4 mr-2" /> Concluir
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
