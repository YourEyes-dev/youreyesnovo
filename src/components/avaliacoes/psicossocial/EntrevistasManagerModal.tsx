import { useMemo, useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/progress";
import {
  Copy,
  ExternalLink,
  Plus,
  Search,
  Trash2,
  Ban,
  Loader2,
  MessageSquare,
  Mic,
  FileText,
  AlertTriangle,
} from "lucide-react";
import { toast } from "sonner";
import { format, parseISO } from "date-fns";
import { ptBR } from "date-fns/locale";
import { confirm } from "@/components/ui/confirm-dialog";
import {
  useEntrevistasCampanha,
  useCancelarEntrevista,
  useExcluirEntrevista,
} from "@/hooks/useEntrevistasCampanha";
import { useGerarEntrevista } from "@/hooks/useGerarEntrevista";
import { useColaboradores } from "@/hooks/useColaboradores";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useAuthContext } from "@/contexts/AuthContext";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useQueryClient } from "@tanstack/react-query";
import { gerarLinksEntrevistaColaboradores } from "@/utils/gerarLinksEntrevistaColaboradores";

interface Props {
  /** tipo_instrumento da campanha (workshop = 'entrevista_coletiva'). */
  tipoInstrumento?: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  campanhaId: string | null;
  campanhaNome?: string;
}

const STATUS_META: Record<string, { label: string; variant: "default" | "secondary" | "outline" | "destructive" }> = {
  pendente: { label: "Pendente", variant: "secondary" },
  em_andamento: { label: "Em andamento", variant: "default" },
  concluida: { label: "Concluída", variant: "outline" },
  cancelada: { label: "Cancelada", variant: "destructive" },
};

export function EntrevistasManagerModal({ open, onOpenChange, campanhaId, campanhaNome, tipoInstrumento }: Props) {
  const isColetiva = tipoInstrumento === "entrevista_coletiva";
  const [grupoNome, setGrupoNome] = useState("");
  const [participantes, setParticipantes] = useState("");
  const { data: entrevistas = [], isLoading } = useEntrevistasCampanha(campanhaId);
  const gerar = useGerarEntrevista();
  const cancelar = useCancelarEntrevista();
  const excluir = useExcluirEntrevista();
  const { colaboradores, cpfsConflitantes } = useColaboradores();
  const { empresaAtiva, empresaAtivaId } = useEmpresaAtiva();
  const { user } = useAuthContext();
  const qc = useQueryClient();
  const [busca, setBusca] = useState("");
  const [filtroStatus, setFiltroStatus] = useState<string>("todos");
  const [gerandoDoc, setGerandoDoc] = useState(false);

  const PROD_URL = "https://www.youreyes.com.br";
  const linkOf = (token: string) => `${PROD_URL}/entrevista/${token}`;

  const filtradas = useMemo(() => {
    return entrevistas.filter((e) => {
      if (filtroStatus !== "todos" && e.status !== filtroStatus) return false;
      if (!busca.trim()) return true;
      const q = busca.toLowerCase();
      return (
        e.token.toLowerCase().includes(q) ||
        (e.colaborador_nome || "").toLowerCase().includes(q)
      );
    });
  }, [entrevistas, busca, filtroStatus]);

  const copiar = async (token: string) => {
    try {
      await navigator.clipboard.writeText(linkOf(token));
      toast.success("Link copiado");
    } catch {
      toast.error("Não foi possível copiar");
    }
  };

  const handleGerarDocumentoColaboradores = async () => {
    if (!campanhaId) return;
    if (!user) {
      toast.error("Não autenticado");
      return;
    }
    if (!colaboradores || colaboradores.length === 0) {
      toast.error("Nenhum colaborador encontrado para a empresa ativa");
      return;
    }

    setGerandoDoc(true);
    try {
      const tenantRes = await fromTable("profiles")
        .select("tenant_id")
        .eq("user_id", user.id)
        .single();
      const tenantId = (tenantRes.data as any)?.tenant_id;
      if (!tenantId) throw new Error("Tenant não encontrado");

      // Regra: UM link por colaborador por campanha (qualquer status).
      // A entrevista é retomável de onde parou, então um link existente —
      // pendente, em andamento ou concluída — é sempre reaproveitado em vez
      // de gerar um novo. Prioriza o link mais recente quando há histórico.
      const linkPorColab = new Map<string, string>();
      const ordenadas = [...entrevistas].sort((a, b) => {
        const ta = new Date((a as any).created_at ?? 0).getTime();
        const tb = new Date((b as any).created_at ?? 0).getTime();
        return tb - ta; // mais recente primeiro
      });
      for (const e of ordenadas) {
        const cid = (e as any).colaborador_id;
        if (cid && !linkPorColab.has(cid)) {
          linkPorColab.set(cid, e.token);
        }
      }

      const itens: Array<{ nome: string; cpf?: string | null; cargo?: string | null; link: string }> = [];
      const novas: any[] = [];

      for (const c of colaboradores) {
        const existente = linkPorColab.get(c.id);
        if (existente) {
          itens.push({ nome: c.nome_completo, cpf: c.cpf, cargo: c.cargo, link: linkOf(existente) });
          continue;
        }
        const token = Array.from(crypto.getRandomValues(new Uint8Array(16)))
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        novas.push({
          tenant_id: tenantId,
          empresa_id: empresaAtivaId || null,
          campanha_id: campanhaId,
          token,
          modalidade: "texto",
          status: "pendente",
          colaborador_id: c.id,
          colaborador_nome: c.nome_completo,
        });
        itens.push({ nome: c.nome_completo, cpf: c.cpf, cargo: c.cargo, link: linkOf(token) });
      }

      if (novas.length > 0) {
        const { error } = await fromTable("psicossocial_entrevistas").insert(novas as any);
        if (error) throw error;
      }

      await gerarLinksEntrevistaColaboradores({
        empresaNome:
          (empresaAtiva as any)?.razao_social ||
          (empresaAtiva as any)?.nome_fantasia ||
          "Empresa",
        empresaCnpj: (empresaAtiva as any)?.cnpj || "",
        campanhaNome: campanhaNome || "Campanha",
        itens,
      });

      qc.invalidateQueries({ queryKey: ["psicossocial-entrevistas", campanhaId] });
      const reaproveitados = itens.length - novas.length;
      toast.success(
        `Documento gerado com ${itens.length} link(s) — ${novas.length} novo(s)` +
        (reaproveitados > 0 ? `, ${reaproveitados} reaproveitado(s)` : "") + "."
      );
    } catch (e: any) {
      console.error(e);
      toast.error(e?.message || "Falha ao gerar documento");
    } finally {
      setGerandoDoc(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle>Links de Entrevista Guiada</DialogTitle>
          <DialogDescription>
            {campanhaNome
              ? `Gerencie os links gerados para a campanha "${campanhaNome}".`
              : "Gerencie os links gerados para esta campanha."}
          </DialogDescription>
        </DialogHeader>

        {/* Aviso: CPF repetido entre pessoas distintas colapsa a lista de
            colaboradores (cada CPF gera 1 link). É erro de cadastro. */}
        {!isColetiva && cpfsConflitantes.length > 0 && (
          <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-amber-900 space-y-1.5">
            <div className="flex items-center gap-2 text-sm font-medium">
              <AlertTriangle className="h-4 w-4 shrink-0" />
              Cadastro com CPF repetido
            </div>
            <p className="text-xs leading-relaxed">
              Colaboradores diferentes estão cadastrados com o <strong>mesmo CPF</strong>.
              O sistema usa o CPF como identidade, então eles são tratados como uma
              pessoa só — cada CPF repetido gera <strong>apenas 1 link</strong>, e não
              um por pessoa.
            </p>
            <ul className="text-xs list-disc pl-5 space-y-0.5">
              {cpfsConflitantes.map((c) => (
                <li key={c.cpf}>
                  Mesmo CPF: <strong>{c.nomes.join(", ")}</strong>
                </li>
              ))}
            </ul>
            <p className="text-xs leading-relaxed">
              Corrija o CPF de cada colaborador em <strong>Admissões / Colaboradores</strong>{" "}
              para que cada um receba o seu próprio link.
            </p>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <div className="relative flex-1 min-w-[220px]">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
              placeholder="Buscar por token ou nome..."
              className="pl-8"
            />
          </div>
          <div className="flex gap-1 flex-wrap">
            {["todos", "pendente", "em_andamento", "concluida", "cancelada"].map((s) => (
              <Button
                key={s}
                size="sm"
                variant={filtroStatus === s ? "default" : "outline"}
                onClick={() => setFiltroStatus(s)}
              >
                {s === "todos" ? "Todos" : STATUS_META[s]?.label || s}
              </Button>
            ))}
          </div>
          {!isColetiva && (
            <Button
              size="sm"
              disabled={!campanhaId || gerar.isPending}
              onClick={() => campanhaId && gerar.mutate({ campanhaId })}
            >
              {gerar.isPending ? (
                <Loader2 className="h-4 w-4 mr-1 animate-spin" />
              ) : (
                <Plus className="h-4 w-4 mr-1" />
              )}
              Novo link
            </Button>
          )}
        </div>

        {isColetiva && (
          <div className="rounded-lg border p-3 bg-purple-50/50 space-y-2">
            <p className="text-sm font-medium">Nova sessão coletiva (Workshop)</p>
            <p className="text-xs text-muted-foreground">
              O profissional reúne o grupo, lê as perguntas e registra a percepção
              coletiva na sessão. Informe o grupo reunido e quantas pessoas participaram.
            </p>
            <div className="flex gap-2 flex-wrap items-end">
              <div className="flex-1 min-w-[180px]">
                <Input
                  placeholder="Nome do grupo/GHE (ex.: Produção — Turno A)"
                  value={grupoNome}
                  onChange={(e) => setGrupoNome(e.target.value)}
                />
              </div>
              <div className="w-32">
                <Input
                  type="number"
                  min={1}
                  placeholder="Nº pessoas"
                  value={participantes}
                  onChange={(e) => setParticipantes(e.target.value)}
                />
              </div>
              <Button
                size="sm"
                disabled={!campanhaId || gerar.isPending || !grupoNome.trim()}
                onClick={() =>
                  campanhaId &&
                  gerar.mutate(
                    {
                      campanhaId,
                      grupoNome: grupoNome.trim(),
                      participantesPrevistos: participantes ? Number(participantes) : undefined,
                    },
                    { onSuccess: () => { setGrupoNome(""); setParticipantes(""); } }
                  )
                }
              >
                {gerar.isPending ? (
                  <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                ) : (
                  <Plus className="h-4 w-4 mr-1" />
                )}
                Nova sessão
              </Button>
            </div>
          </div>
        )}

        <Button
          variant="default"
          className="w-full"
          disabled={!campanhaId || gerandoDoc || !empresaAtivaId}
          onClick={handleGerarDocumentoColaboradores}
        >
          {gerandoDoc ? (
            <>
              <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              Gerando documento...
            </>
          ) : (
            <>
              <FileText className="h-4 w-4 mr-2" />
              Gerar Documento da Empresa (PDF) — 1 link por colaborador
            </>
          )}
        </Button>
        {!empresaAtivaId && (
          <p className="text-xs text-muted-foreground -mt-1">
            Selecione uma empresa ativa no topo para habilitar a geração em massa.
          </p>
        )}

        <div className="flex-1 overflow-y-auto border rounded-md">
          {isLoading ? (
            <div className="p-6 text-center text-sm text-muted-foreground flex items-center justify-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin" /> Carregando...
            </div>
          ) : filtradas.length === 0 ? (
            <div className="p-8 text-center text-sm text-muted-foreground">
              Nenhum link encontrado. Clique em "Novo link" para gerar.
            </div>
          ) : (
            <div className="divide-y">
              {filtradas.map((e) => {
                const meta = STATUS_META[e.status] || { label: e.status, variant: "secondary" as const };
                const progresso =
                  e.total_riscos > 0 ? Math.round((e.riscos_cobertos / e.total_riscos) * 100) : 0;
                // Progresso da CONVERSA (quanto a pessoa avançou), pelo status.
                // Obs.: fase_atual NÃO avança durante a entrevista (só é gravado
                // como 3 no fechamento), então não serve para medir o meio da
                // conversa — usamos um valor representativo para "em andamento".
                const progressoConversa =
                  e.status === "concluida"
                    ? 100
                    : e.status === "em_andamento"
                    ? 50
                    : 0;
                const podeCancelar = e.status === "pendente" || e.status === "em_andamento";
                return (
                  <div key={e.id} className="p-3 flex flex-col gap-2 hover:bg-muted/30">
                    <div className="flex items-start justify-between gap-3 flex-wrap">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Badge variant={meta.variant}>{meta.label}</Badge>
                        <Badge variant="outline" className="gap-1">
                          {e.modalidade === "voz" ? (
                            <Mic className="h-3 w-3" />
                          ) : (
                            <MessageSquare className="h-3 w-3" />
                          )}
                          {e.modalidade === "voz" ? "Áudio" : "Texto"}
                        </Badge>
                        <span className="text-xs text-muted-foreground">
                          Criado {format(parseISO(e.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}
                        </span>
                        {(e as any).tipo_sessao === "coletiva" && (
                          <Badge variant="outline" className="gap-1">
                            Workshop{(e as any).participantes_previstos ? ` · ${(e as any).participantes_previstos} pessoas` : ""}
                          </Badge>
                        )}
                        {e.colaborador_nome && (
                          <span className="text-xs">• {e.colaborador_nome}</span>
                        )}
                      </div>
                      <div className="flex gap-1">
                        <Button size="sm" variant="ghost" onClick={() => copiar(e.token)}>
                          <Copy className="h-4 w-4 mr-1" /> Copiar
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => window.open(linkOf(e.token), "_blank")}
                        >
                          <ExternalLink className="h-4 w-4 mr-1" /> Abrir
                        </Button>
                        {podeCancelar && (
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={async () => {
                              const ok = await confirm({
                                title: "Cancelar link?",
                                description:
                                  "O link deixará de funcionar. Esta ação não pode ser desfeita.",
                                confirmLabel: "Cancelar link",
                                variant: "destructive",
                              });
                              if (ok) cancelar.mutate({ id: e.id, campanhaId: campanhaId! });
                            }}
                          >
                            <Ban className="h-4 w-4 mr-1" /> Cancelar
                          </Button>
                        )}
                        {(e.status === "pendente" || e.status === "cancelada") && (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-destructive hover:text-destructive"
                            onClick={async () => {
                              const ok = await confirm({
                                title: "Excluir link?",
                                description:
                                  "O link e todas as suas mensagens serão removidos permanentemente.",
                                confirmLabel: "Excluir",
                                variant: "destructive",
                              });
                              if (ok) excluir.mutate({ id: e.id, campanhaId: campanhaId! });
                            }}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 text-xs">
                      <code className="px-2 py-1 rounded bg-muted truncate max-w-md">
                        {linkOf(e.token)}
                      </code>
                    </div>
                    {e.status !== "cancelada" && (
                    <div className="flex flex-col gap-1.5 pt-0.5">
                      <div className="flex items-center gap-2">
                        <span className="text-[11px] text-muted-foreground w-28 shrink-0">Progresso da conversa</span>
                        <Progress value={progressoConversa} className="h-1.5 flex-1 max-w-xs" />
                        <span className="text-xs text-muted-foreground w-10 text-right">{progressoConversa}%</span>
                      </div>
                      {e.total_riscos > 0 && (
                        <div className="flex items-center gap-2">
                          <span className="text-[11px] text-muted-foreground w-28 shrink-0">Riscos identificados</span>
                          <Progress value={progresso} className="h-1.5 flex-1 max-w-xs" />
                          <span className="text-xs text-muted-foreground w-10 text-right">{e.riscos_cobertos}/{e.total_riscos}</span>
                        </div>
                      )}
                    </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
