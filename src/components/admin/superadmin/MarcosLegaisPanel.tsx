import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";
import { confirm } from "@/components/ui/confirm-dialog";
import { Loader2, Power, CalendarClock, CalendarX } from "lucide-react";
import { formatarDataBR, formatarHoras, useImpactoEc141 } from "@/hooks/usePontoEc141";
import { Ec141ImpactoTabela } from "@/components/ponto/Ec141ImpactoTabela";

// Marcos legais da jornada (EC 141/2026, entrega F1). A transição é MANUAL
// (decisão da fundadora, 30/10/2026): 42h e 40h nascem inativos; ativar,
// mudar a data e desativar são gestos do SuperAdmin, sempre com motivo e
// histórico. Enquanto um marco estiver inativo, nada muda para nenhum cliente.

const rpc = (nome: string, args: Record<string, unknown>) =>
  (supabase.rpc as any)(nome, args) as Promise<{ data: any; error: any }>;

interface Marco {
  id: string;
  codigo: string;
  nome: string;
  vigencia_inicio: string;
  teto_semanal_min: number;
  teto_diario_min: number;
  repousos_semana: number;
  divisor_padrao: number;
  fonte: string | null;
  ativo: boolean;
  ativado_em: string | null;
  desativado_em: string | null;
  motivo: string | null;
  tenant_id: string | null;
}

type Acao = "ativar" | "desativar" | "definir_data";

const EFEITO: Record<Acao, (m: Marco, data: string) => string> = {
  ativar: (m, data) =>
    `A partir de ${formatarDataBR(data)}, o teto legal de TODAS as contas passa a ${formatarHoras(m.teto_semanal_min)} semanais, ` +
    `${m.repousos_semana} repouso(s) e divisor ${m.divisor_padrao}. As telas de escalas passam a mostrar o painel de impacto e avisos. ` +
    `Nenhuma escala é alterada sozinha: cada RH agenda a sua. Pode ser desativado depois.`,
  desativar: (m) =>
    `O marco "${m.nome}" deixa de valer para todas as contas (o teto volta ao marco anterior). Agendamentos de escalas já feitos ` +
    `NÃO são cancelados por este botão — use "Cancelar agendamentos" se a lei foi revogada ou adiada.`,
  definir_data: (m, data) =>
    `A data de início de "${m.nome}" passa a ser ${formatarDataBR(data)}. ${m.ativo ? "O marco está ativo: o novo teto vale a partir dessa data." : "O marco segue INATIVO (nada muda até ser ativado)."}`,
};

export function MarcosLegaisPanel() {
  const queryClient = useQueryClient();
  const [dialogo, setDialogo] = useState<null | { acao: Acao; marco: Marco }>(null);
  const [data, setData] = useState("");
  const [motivo, setMotivo] = useState("");
  const [salvando, setSalvando] = useState(false);
  const [tenantPrevia, setTenantPrevia] = useState("");
  const [buscaTenant, setBuscaTenant] = useState("");
  const [marcoPrevia, setMarcoPrevia] = useState("EC141_42H");

  const { data: marcos = [], isLoading } = useQuery({
    queryKey: ["superadmin-marcos-legais"],
    queryFn: async (): Promise<Marco[]> => {
      const { data, error } = await (supabase as any)
        .from("ponto_marcos_legais")
        .select("*")
        .order("vigencia_inicio", { ascending: true });
      if (error) throw error;
      return (data || []) as Marco[];
    },
  });

  const { data: historico = [] } = useQuery({
    queryKey: ["superadmin-marcos-legais-historico"],
    queryFn: async () => {
      const { data, error } = await (supabase as any)
        .from("ponto_marcos_legais_historico")
        .select("id, codigo, tenant_id, acao, motivo, usuario_email, criado_em, depois")
        .order("criado_em", { ascending: false })
        .limit(20);
      if (error) return [];
      return data || [];
    },
  });

  const { data: tenants = [] } = useQuery({
    queryKey: ["superadmin-marcos-tenants", buscaTenant],
    queryFn: async () => {
      let q = supabase.from("tenants").select("id, nome").order("nome").limit(30);
      if (buscaTenant.trim().length >= 2) q = q.ilike("nome", `%${buscaTenant.trim()}%`);
      const { data, error } = await q;
      if (error) return [];
      return data || [];
    },
  });

  const { data: previa, isFetching: carregandoPrevia } = useImpactoEc141({
    tenantId: tenantPrevia || null,
    empresaId: null,
    marco: marcoPrevia,
    enabled: !!tenantPrevia,
  });

  const globais = marcos.filter((m) => !m.tenant_id);
  const excecoes = marcos.filter((m) => m.tenant_id);

  const abrir = (acao: Acao, marco: Marco) => {
    setDialogo({ acao, marco });
    setData(marco.vigencia_inicio);
    setMotivo("");
  };

  const executar = async () => {
    if (!dialogo) return;
    if (motivo.trim().length < 5) { toast.error("Informe o motivo (mínimo 5 caracteres)."); return; }
    if (dialogo.acao !== "desativar" && !data) { toast.error("Informe a data."); return; }
    setSalvando(true);
    try {
      const nome = dialogo.acao === "ativar" ? "ponto_marco_ativar" : dialogo.acao === "desativar" ? "ponto_marco_desativar" : "ponto_marco_definir_data";
      const args: Record<string, unknown> = { p_codigo: dialogo.marco.codigo, p_motivo: motivo.trim(), p_tenant_id: dialogo.marco.tenant_id };
      if (dialogo.acao !== "desativar") args.p_vigencia_inicio = data;
      const { data: res, error } = await rpc(nome, args);
      if (error) throw error;
      if (!res?.ok) throw new Error(res?.mensagem || res?.erro || "Não foi possível salvar.");
      toast.success("Marco legal atualizado.");
      setDialogo(null);
      queryClient.invalidateQueries({ queryKey: ["superadmin-marcos-legais"] });
      queryClient.invalidateQueries({ queryKey: ["superadmin-marcos-legais-historico"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-ec141-impacto"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-teto-legal"] });
    } catch (e: any) {
      toast.error(e?.message || "Erro ao salvar.");
    } finally {
      setSalvando(false);
    }
  };

  const cancelarLote = async (m: Marco) => {
    const ok = await confirm({
      title: `Cancelar agendamentos ligados a ${m.codigo}?`,
      description:
        `Todas as escalas, de TODAS as contas, com alteração agendada para o marco "${m.nome}" e cuja data ainda não chegou ` +
        `voltam aos valores de hoje. Use quando a lei for revogada ou adiada. Agendamentos que já entraram em vigor não são tocados.`,
      confirmLabel: "Cancelar agendamentos",
      variant: "destructive",
    });
    if (!ok) return;
    const { data: res, error } = await rpc("ponto_escalas_cancelar_agendamentos_lote", { p_tenant: null, p_marco_codigo: m.codigo });
    if (error || !res?.ok) { toast.error(error?.message || res?.erro || "Falha ao cancelar."); return; }
    toast.success(`${res.canceladas} agendamento(s) cancelado(s).`);
    queryClient.invalidateQueries({ queryKey: ["ponto-ec141-impacto"] });
  };

  return (
    <div className="space-y-6" data-testid="superadmin-marcos-legais">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Marcos legais da jornada</CardTitle>
          <CardDescription>
            A transição da EC 141/2026 é manual: 42h e 40h nascem <strong>inativos</strong>. Ativar faz o novo teto valer a partir da data
            escolhida para todas as contas (avisos e painel de impacto); nenhuma escala muda sozinha. Toda alteração pede motivo e fica no histórico.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="p-6 flex justify-center"><Loader2 className="w-5 h-5 animate-spin" /></div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Marco</TableHead>
                    <TableHead>Vale a partir de</TableHead>
                    <TableHead className="text-right">Semana</TableHead>
                    <TableHead className="text-right">Dia</TableHead>
                    <TableHead className="text-right">Repousos</TableHead>
                    <TableHead className="text-right">Divisor</TableHead>
                    <TableHead>Situação</TableHead>
                    <TableHead className="text-right">Ações</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {globais.map((m) => (
                    <TableRow key={m.id}>
                      <TableCell>
                        <div className="font-medium text-sm">{m.nome}</div>
                        <div className="text-[11px] text-muted-foreground">{m.codigo} · {m.fonte}</div>
                      </TableCell>
                      <TableCell>{formatarDataBR(m.vigencia_inicio)}</TableCell>
                      <TableCell className="text-right">{formatarHoras(m.teto_semanal_min)}</TableCell>
                      <TableCell className="text-right">{formatarHoras(m.teto_diario_min)}</TableCell>
                      <TableCell className="text-right">{m.repousos_semana}</TableCell>
                      <TableCell className="text-right">{m.divisor_padrao}</TableCell>
                      <TableCell>
                        {m.ativo
                          ? <Badge className="bg-emerald-100 text-emerald-800">Ativo</Badge>
                          : <Badge variant="outline">Inativo</Badge>}
                      </TableCell>
                      <TableCell>
                        <div className="flex justify-end gap-1 flex-wrap">
                          <Button size="sm" variant="outline" onClick={() => abrir("definir_data", m)}>
                            <CalendarClock className="w-4 h-4 mr-1" /> Data
                          </Button>
                          {m.ativo ? (
                            m.codigo !== "CF88_44H" && (
                              <Button size="sm" variant="outline" className="text-red-700" onClick={() => abrir("desativar", m)}>
                                <Power className="w-4 h-4 mr-1" /> Desativar
                              </Button>
                            )
                          ) : (
                            <Button size="sm" onClick={() => abrir("ativar", m)}>
                              <Power className="w-4 h-4 mr-1" /> Ativar
                            </Button>
                          )}
                          {m.codigo.startsWith("EC141") && (
                            <Button size="sm" variant="ghost" title="Cancelar agendamentos de escalas ligados a este marco" onClick={() => cancelarLote(m)}>
                              <CalendarX className="w-4 h-4" />
                            </Button>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          {excecoes.length > 0 && (
            <div className="p-4 border-t text-sm space-y-1">
              <div className="font-medium">Exceções por conta</div>
              {excecoes.map((m) => (
                <div key={m.id} className="text-muted-foreground">
                  {m.codigo} · conta {m.tenant_id?.slice(0, 8)} · {m.ativo ? "ativo" : "inativo"} desde {formatarDataBR(m.vigencia_inicio)}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Prévia do impacto por conta</CardTitle>
          <CardDescription>
            Somente leitura. Mostra, para a conta escolhida, as escalas acima do teto do marco e as de 6 dias sem convenção/acordo coletivo,
            mesmo com o marco ainda inativo (o cliente só vê depois da ativação).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="space-y-1">
              <Label className="text-xs">Buscar conta</Label>
              <Input value={buscaTenant} onChange={(e) => setBuscaTenant(e.target.value)} placeholder="Nome da conta" />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Conta</Label>
              <Select value={tenantPrevia} onValueChange={setTenantPrevia}>
                <SelectTrigger><SelectValue placeholder="Escolha a conta" /></SelectTrigger>
                <SelectContent>
                  {(tenants as any[]).map((t) => <SelectItem key={t.id} value={t.id}>{t.nome}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Marco</Label>
              <Select value={marcoPrevia} onValueChange={setMarcoPrevia}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {globais.filter((m) => m.codigo.startsWith("EC141")).map((m) => (
                    <SelectItem key={m.codigo} value={m.codigo}>{m.nome}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          {carregandoPrevia && <Loader2 className="w-4 h-4 animate-spin" />}
          {tenantPrevia && previa?.visivel && <Ec141ImpactoTabela impacto={previa} />}
          {tenantPrevia && previa && !previa.visivel && (
            <p className="text-sm text-muted-foreground">{previa.mensagem || "Sem dados para esta conta."}</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Histórico</CardTitle>
        </CardHeader>
        <CardContent className="text-sm space-y-1">
          {(historico as any[]).length === 0 && <p className="text-muted-foreground">Nenhuma alteração registrada.</p>}
          {(historico as any[]).map((h) => (
            <div key={h.id} className="border-b last:border-0 py-1">
              <span className="font-medium">{h.codigo}</span>{h.tenant_id ? " (exceção de conta)" : ""} · {h.acao} ·{" "}
              {new Date(h.criado_em).toLocaleString("pt-BR")} · {h.usuario_email || "sistema"} — {h.motivo}
            </div>
          ))}
        </CardContent>
      </Card>

      <Dialog open={!!dialogo} onOpenChange={(o) => !o && setDialogo(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {dialogo?.acao === "ativar" ? "Ativar marco legal" : dialogo?.acao === "desativar" ? "Desativar marco legal" : "Alterar a data do marco"}
            </DialogTitle>
            <DialogDescription>{dialogo ? dialogo.marco.nome : ""}</DialogDescription>
          </DialogHeader>
          {dialogo && (
            <div className="space-y-3">
              {dialogo.acao !== "desativar" && (
                <div className="space-y-1">
                  <Label>Vale a partir de</Label>
                  <Input type="date" value={data} onChange={(e) => setData(e.target.value)} />
                </div>
              )}
              <div className="space-y-1">
                <Label>Motivo</Label>
                <Textarea rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)}
                  placeholder="Ex.: publicação no DOU, portaria do MTE, revogação, decisão judicial" />
              </div>
              <div className="rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950/20 p-3 text-sm text-amber-900 dark:text-amber-200">
                <strong>Efeito:</strong> {EFEITO[dialogo.acao](dialogo.marco, data)}
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogo(null)}>Voltar</Button>
            <Button onClick={executar} disabled={salvando} variant={dialogo?.acao === "desativar" ? "destructive" : "default"}>
              {salvando ? "Salvando..." : "Confirmar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
