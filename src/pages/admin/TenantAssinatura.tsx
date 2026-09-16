import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { useSuperAdmin } from "@/hooks/useSuperAdmin";
import { usePlanosCatalogo } from "@/hooks/usePlanosCatalogo";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ArrowLeft, CreditCard, CalendarClock, Info, Building2, Layers, Loader2, Handshake } from "lucide-react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

const TRIAL_PADRAO_DIAS = 7;

function formatarData(d: Date) {
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
}


// Programa de Parceiros — marcos do cliente que o motor de comissões lê:
// setup pago pelo cliente, 1ª/3ª mensalidade compensadas, go-live homologado
// (nasce o ciclo de 24 meses), contrato, cancelamento e desconto concedido.
function ProgramaParceirosCard({ tenantId }: { tenantId: string }) {
  const qc = useQueryClient();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any;
  const { data, isLoading } = useQuery({
    queryKey: ["superadmin", "tenant-programa", tenantId],
    queryFn: async () => { const { data, error } = await sb.rpc("superadmin_tenant_programa", { _tenant_id: tenantId }); if (error) throw error; return data as Record<string, string | number | boolean | null> | null; },
  });
  const [f, setF] = useState<Record<string, string>>({});
  useEffect(() => {
    if (!data) return;
    setF({
      setup_valor: ((Number(data.setup_valor_cents ?? 0)) / 100).toFixed(2).replace(".", ","),
      desconto_pct: String(data.desconto_pct ?? 0),
      contrato_assinado_em: String(data.contrato_assinado_em ?? ""),
      primeira_mensalidade_compensada_em: String(data.primeira_mensalidade_compensada_em ?? ""),
      go_live_homologado_em: String(data.go_live_homologado_em ?? ""),
      terceira_mensalidade_compensada_em: String(data.terceira_mensalidade_compensada_em ?? ""),
      cancelado_em: String(data.cancelado_em ?? ""),
    });
  }, [data]);
  const salvar = useMutation({
    mutationFn: async () => {
      const cents = Math.round(parseFloat((f.setup_valor || "0").replace(/\./g, "").replace(",", ".")) * 100) || 0;
      const { error } = await sb.rpc("superadmin_tenant_programa_salvar", { _tenant_id: tenantId, _dados: {
        setup_valor_cents: cents, desconto_pct: Number(f.desconto_pct || 0),
        contrato_assinado_em: f.contrato_assinado_em || null, primeira_mensalidade_compensada_em: f.primeira_mensalidade_compensada_em || null,
        go_live_homologado_em: f.go_live_homologado_em || null, terceira_mensalidade_compensada_em: f.terceira_mensalidade_compensada_em || null,
        cancelado_em: f.cancelado_em || null,
      } });
      if (error) throw error;
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["superadmin", "tenant-programa", tenantId] }); toast.success("Marcos do cliente salvos"); },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : "Não foi possível salvar"),
  });
  const campo = (k: string, label: string, hint?: string) => (
    <div><Label className="text-xs">{label}</Label><Input type="date" value={f[k] ?? ""} onChange={(e) => setF((x) => ({ ...x, [k]: e.target.value }))} />{hint && <p className="text-[11px] text-muted-foreground mt-0.5">{hint}</p>}</div>
  );
  return (
    <Card data-testid="tenant-programa-parceiros">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2"><Handshake className="w-4 h-4" /> Programa de Parceiros — marcos do cliente</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading ? <Skeleton className="h-24 w-full" /> : (
          <>
            {data && (
              <div className="flex flex-wrap gap-2 text-xs">
                <Badge variant="outline">estágio: {String(data.estagio ?? "—")}</Badge>
                <Badge variant="outline">base de comissão: R$ {((Number(data.base_cents ?? 0)) / 100).toFixed(2).replace(".", ",")}</Badge>
                {data.ciclo_inicio && <Badge variant="outline">ciclo: {String(data.ciclo_inicio)} → {String(data.ciclo_fim)}</Badge>}
              </div>
            )}
            <div className="grid sm:grid-cols-2 gap-3">
              <div><Label className="text-xs">Setup cobrado do cliente (R$)</Label><Input value={f.setup_valor ?? ""} onChange={(e) => setF((x) => ({ ...x, setup_valor: e.target.value }))} placeholder="1.200,00" /><p className="text-[11px] text-muted-foreground mt-0.5">Base das parcelas 30/40/30 e do bônus de retenção.</p></div>
              <div><Label className="text-xs">Desconto concedido na mensalidade (%)</Label><Input type="number" step="0.5" value={f.desconto_pct ?? "0"} onChange={(e) => setF((x) => ({ ...x, desconto_pct: e.target.value }))} /><p className="text-[11px] text-muted-foreground mt-0.5">Reduz a base de comissão do parceiro.</p></div>
              {campo("contrato_assinado_em", "Contrato assinado em", "Referência do bônus de velocidade.")}
              {campo("primeira_mensalidade_compensada_em", "1ª mensalidade compensada em", "Libera a 1ª parcela do setup.")}
              {campo("go_live_homologado_em", "Go-live homologado em", "Nasce o ciclo de 24 meses; libera a 2ª parcela.")}
              {campo("terceira_mensalidade_compensada_em", "3ª mensalidade compensada em", "Libera a 3ª parcela e a retenção do Operador.")}
              {campo("cancelado_em", "Cancelado em", "Entre o 4º e o 12º mês gera clawback.")}
            </div>
            <div className="flex justify-end"><Button onClick={() => salvar.mutate()} disabled={salvar.isPending}>{salvar.isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}Salvar marcos</Button></div>
          </>
        )}
      </CardContent>
    </Card>
  );
}

export default function TenantAssinatura() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { tenants, setTenantPlano, isSettingPlano } = useSuperAdmin();
  const { planos } = usePlanosCatalogo();

  const tenant = tenants.find((t) => t.id === id);
  const planoAtual = tenant?.plano_atual ?? null;

  // Plano é a única parte desta tela que persiste de verdade (no motor).
  const [planoSel, setPlanoSel] = useState<string>("");
  useEffect(() => {
    if (planoAtual) setPlanoSel(planoAtual);
  }, [planoAtual]);

  // Trial / pagamento seguem apenas como prévia — estado local, não grava.
  const [trialDias, setTrialDias] = useState<number>(TRIAL_PADRAO_DIAS);
  const [pago, setPago] = useState(false);

  const inicio = tenant?.created_at ? new Date(tenant.created_at) : null;
  const vencimento = inicio ? new Date(inicio.getTime() + trialDias * 86400000) : null;

  const hoje = new Date();
  const diasRestantes = vencimento
    ? Math.ceil((vencimento.getTime() - hoje.getTime()) / 86400000)
    : 0;
  const vencido = !pago && diasRestantes <= 0;

  const situacao = pago
    ? { label: "Pago", cor: "bg-emerald-100 text-emerald-800 border-emerald-200" }
    : vencido
    ? { label: "Trial vencido", cor: "bg-red-100 text-red-800 border-red-200" }
    : { label: `Em trial · ${diasRestantes} dia${diasRestantes === 1 ? "" : "s"} restante${diasRestantes === 1 ? "" : "s"}`,
        cor: "bg-amber-100 text-amber-800 border-amber-200" };

  const nomePlano = (code: string | null) =>
    planos.find((p) => p.code === code)?.name || code || "—";

  const handleSalvarPlano = async () => {
    if (!id || !planoSel) return;
    try {
      await setTenantPlano({ tenantId: id, planoCode: planoSel });
      toast.success(`Plano atualizado para ${nomePlano(planoSel)}.`);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar o plano");
    }
  };

  return (
    <div className="p-6 max-w-3xl mx-auto space-y-4">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate("/admin")}>
          <ArrowLeft className="w-5 h-5" />
        </Button>
        <div className="min-w-0">
          <h1 className="text-xl font-semibold truncate">
            {tenant?.nome || <Skeleton className="h-6 w-48" />}
          </h1>
          <p className="text-sm text-muted-foreground">Assinatura e período de teste</p>
        </div>
      </div>

      {/* Plano: esta parte grava de verdade no motor de entitlements. */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <Layers className="w-4 h-4" /> Plano
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium">Plano atual</p>
              <p className="text-xs text-muted-foreground">
                Define o que a empresa pode acessar. O bloqueio por plano ainda está desligado —
                por enquanto a escolha fica registrada.
              </p>
            </div>
            <Badge variant="outline" className="capitalize">{nomePlano(planoAtual)}</Badge>
          </div>

          <Separator />

          <div className="grid grid-cols-1 sm:grid-cols-[1fr_auto] gap-3 sm:items-end">
            <div className="space-y-2">
              <Label htmlFor="plano">Alterar plano</Label>
              <Select value={planoSel} onValueChange={setPlanoSel}>
                <SelectTrigger id="plano">
                  <SelectValue placeholder="Selecione o plano" />
                </SelectTrigger>
                <SelectContent>
                  {planos.map((p) => (
                    <SelectItem key={p.code} value={p.code}>
                      {p.name}{!p.is_public ? " (interno)" : ""}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              onClick={handleSalvarPlano}
              disabled={isSettingPlano || !planoSel || planoSel === planoAtual}
            >
              {isSettingPlano && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Salvar plano
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Trial e pagamento seguem como prévia — honestidade com o superadmin. */}
      <div className="flex items-start gap-2 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm">
        <Info className="w-4 h-4 text-blue-600 mt-0.5 shrink-0" />
        <div>
          <p className="font-medium text-blue-900">Período de teste e pagamento — prévia visual.</p>
          <p className="text-blue-800 text-xs mt-0.5">
            Os controles de trial e pagamento abaixo ainda não gravam nem cobram nada —
            a plataforma de pagamento será definida depois. Só o plano, acima, é salvo.
          </p>
        </div>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <CreditCard className="w-4 h-4" /> Situação
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium">Situação atual</p>
              <p className="text-xs text-muted-foreground">
                Calculada a partir da data de criação e dos dias de teste.
              </p>
            </div>
            <Badge variant="outline" className={situacao.cor}>{situacao.label}</Badge>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <Label htmlFor="pago" className="text-sm font-medium">Pagamento confirmado</Label>
              <p className="text-xs text-muted-foreground">
                Marcar manualmente enquanto não há integração com a plataforma de pagamento.
              </p>
            </div>
            <Switch id="pago" checked={pago} onCheckedChange={setPago} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <CalendarClock className="w-4 h-4" /> Período de teste
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="dias">Dias de teste</Label>
              <Input
                id="dias"
                type="number"
                min={0}
                max={365}
                value={trialDias}
                onChange={(e) => setTrialDias(Math.max(0, Number(e.target.value) || 0))}
              />
              <p className="text-xs text-muted-foreground mt-1">Padrão: {TRIAL_PADRAO_DIAS} dias.</p>
            </div>
            <div>
              <Label>Vence em</Label>
              <div className="h-10 flex items-center rounded-md border border-input bg-muted/40 px-3 text-sm">
                {vencimento ? formatarData(vencimento) : "—"}
              </div>
              <p className="text-xs text-muted-foreground mt-1">
                {inicio ? `Contado a partir de ${formatarData(inicio)}.` : "Sem data de criação."}
              </p>
            </div>
          </div>

          {vencido && (
            <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
              Com esta configuração, a empresa já estaria com o teste vencido — é neste ponto que
              o checkout apareceria e o acesso ficaria bloqueado.
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <Building2 className="w-4 h-4" /> Empresa
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm space-y-1.5">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Plano</span>
            <span className="capitalize">{nomePlano(planoAtual)}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Criada em</span>
            <span>{inicio ? formatarData(inicio) : "—"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Status</span>
            <span>{tenant?.ativo ? "Ativa" : "Inativa"}</span>
          </div>
        </CardContent>
      </Card>

      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={() => navigate("/admin")}>Voltar</Button>
      </div>
      {id && <ProgramaParceirosCard tenantId={id} />}
    </div>
  );
}
