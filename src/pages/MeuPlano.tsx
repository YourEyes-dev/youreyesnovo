import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMeuPlano } from "@/hooks/useMeuPlano";
import { FEATURE_PLAN_NAME } from "@/lib/planFeatures";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Separator } from "@/components/ui/separator";
import { toast } from "sonner";
import {
  ArrowLeft,
  Layers,
  Users,
  Check,
  Lock,
  Sparkles,
  Info,
  Wallet,
  Plus,
  Loader2,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils";

const VIDA_KEY = "limit.vidas";

function centsToReais(cents: number | null | undefined): string {
  if (cents == null) return "—";
  return (cents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export default function MeuPlano() {
  const navigate = useNavigate();
  const { plano, isLoading, contratar, cancelar, isMutating } = useMeuPlano();
  const [vidasQtd, setVidasQtd] = useState("");

  const vidas = plano?.vidas;
  const percent = vidas?.percent ?? null;
  const perto = percent !== null && percent >= 80 && percent < 100;
  const noLimite = percent !== null && percent >= 100;

  const barCor = noLimite ? "bg-red-500" : perto ? "bg-amber-500" : "bg-emerald-500";

  const disponiveis = plano?.modulos.filter((m) => m.disponivel) ?? [];
  const bloqueados = plano?.modulos.filter((m) => !m.disponivel) ?? [];
  const precos = plano?.precos ?? {};
  const addons = plano?.addons ?? [];
  const valores = plano?.valores;

  const precoVida = precos[VIDA_KEY] ?? 0;
  const vidasAddon = addons.find((a) => a.feature_key === VIDA_KEY);

  const doContratar = async (featureKey: string, quantity?: number) => {
    try {
      await contratar({ featureKey, quantity });
      toast.success("Contratação registrada. O valor mensal foi atualizado.");
    } catch (e: any) {
      toast.error(e.message || "Não foi possível contratar agora.");
    }
  };

  const doCancelar = async (featureKey: string) => {
    try {
      await cancelar(featureKey);
      toast.success("Add-on cancelado.");
    } catch (e: any) {
      toast.error(e.message || "Não foi possível cancelar agora.");
    }
  };

  const contratarVidas = async () => {
    const q = parseInt(vidasQtd, 10);
    if (!Number.isFinite(q) || q < 1) {
      toast.error("Informe quantas vidas extras deseja (1 ou mais).");
      return;
    }
    await doContratar(VIDA_KEY, q);
    setVidasQtd("");
  };

  return (
    <div className="p-6 max-w-3xl mx-auto space-y-4">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
          <ArrowLeft className="w-5 h-5" />
        </Button>
        <div>
          <h1 className="text-xl font-semibold">Meu Plano</h1>
          <p className="text-sm text-muted-foreground">Plano, uso, módulos e contratações da sua empresa</p>
        </div>
      </div>

      {isLoading ? (
        <div className="space-y-4">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-32 w-full" />
          <Skeleton className="h-40 w-full" />
        </div>
      ) : !plano?.plano ? (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            <Info className="w-5 h-5 mx-auto mb-2 opacity-60" />
            Ainda não há um plano definido para esta empresa. Fale com o suporte.
          </CardContent>
        </Card>
      ) : (
        <>
          {/* Plano atual */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Layers className="w-4 h-4" /> Plano atual
              </CardTitle>
            </CardHeader>
            <CardContent className="flex items-center justify-between">
              <div>
                <p className="text-2xl font-bold">{plano.plano.name}</p>
                {!plano.plano.is_public && (
                  <p className="text-xs text-muted-foreground mt-0.5">Plano interno</p>
                )}
              </div>
              <Sparkles className="w-8 h-8 text-primary/30" />
            </CardContent>
          </Card>

          {/* Valor mensal */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Wallet className="w-4 h-4" /> Valor mensal
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {valores?.total_cents == null ? (
                <p className="text-sm text-muted-foreground">
                  Valor do plano <strong>sob consulta</strong>. Fale com o suporte para conhecer os valores.
                </p>
              ) : (
                <>
                  <div className="flex items-baseline gap-1.5">
                    <span className="text-sm text-muted-foreground">R$</span>
                    <span className="text-3xl font-bold">{centsToReais(valores.total_cents)}</span>
                    <span className="text-sm text-muted-foreground">/ mês</span>
                  </div>
                  <div className="text-sm text-muted-foreground space-y-0.5 pt-1">
                    <div className="flex justify-between">
                      <span>Plano ({plano.plano.name})</span>
                      <span>R$ {centsToReais(valores.base_cents)}</span>
                    </div>
                    {valores.addons_cents > 0 && (
                      <div className="flex justify-between">
                        <span>Add-ons contratados</span>
                        <span>R$ {centsToReais(valores.addons_cents)}</span>
                      </div>
                    )}
                  </div>
                </>
              )}
              <p className="text-[11px] text-muted-foreground pt-1">
                Os add-ons contratados aqui ajustam o valor mensal; a cobrança é conciliada pelo financeiro.
              </p>
            </CardContent>
          </Card>

          {/* Contratações ativas */}
          {addons.length > 0 && (
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-base flex items-center gap-2">
                  <Plus className="w-4 h-4" /> Contratações ativas
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {addons.map((a, i) => (
                  <div key={a.feature_key}>
                    {i > 0 && <Separator className="my-2" />}
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-sm font-medium truncate">
                          {a.kind === "life" ? `${a.quantity} vida(s) extra(s)` : a.name}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          R${" "}
                          {a.kind === "life"
                            ? `${centsToReais(a.unit_price_cents)} × ${a.quantity} = ${centsToReais(
                                a.quantity * a.unit_price_cents
                              )}`
                            : centsToReais(a.unit_price_cents)}{" "}
                          / mês
                        </p>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-muted-foreground hover:text-red-600"
                        disabled={isMutating}
                        onClick={() => doCancelar(a.feature_key)}
                      >
                        <X className="w-4 h-4 mr-1" /> Cancelar
                      </Button>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}

          {/* Vidas: uso × limite */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Users className="w-4 h-4" /> Colaboradores (vidas)
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {vidas?.is_unlimited || vidas?.limit == null ? (
                <div className="flex items-baseline gap-2">
                  <span className="text-2xl font-bold">{vidas?.used ?? 0}</span>
                  <span className="text-sm text-muted-foreground">colaboradores ativos · limite ilimitado</span>
                </div>
              ) : (
                <>
                  <div className="flex items-baseline justify-between">
                    <div className="flex items-baseline gap-1.5">
                      <span className="text-2xl font-bold">{vidas.used}</span>
                      <span className="text-sm text-muted-foreground">de {vidas.limit} vidas</span>
                    </div>
                    <span
                      className={cn(
                        "text-sm font-semibold",
                        noLimite ? "text-red-600" : perto ? "text-amber-600" : "text-emerald-600"
                      )}
                    >
                      {percent}%
                    </span>
                  </div>
                  <div className="h-2.5 w-full rounded-full bg-muted overflow-hidden">
                    <div
                      className={cn("h-full rounded-full transition-all", barCor)}
                      style={{ width: `${Math.min(percent ?? 0, 100)}%` }}
                    />
                  </div>
                  {(perto || noLimite) && (
                    <div
                      className={cn(
                        "rounded-md border px-3 py-2 text-sm",
                        noLimite
                          ? "border-red-200 bg-red-50 text-red-800"
                          : "border-amber-200 bg-amber-50 text-amber-800"
                      )}
                    >
                      {noLimite
                        ? "Você atingiu o limite de vidas do seu plano. Adicione vidas extras abaixo para cadastrar mais colaboradores."
                        : `Você está usando ${percent}% do limite de vidas. Você pode adicionar vidas extras abaixo.`}
                    </div>
                  )}

                  {/* Adicionar vidas extras (autosserviço) */}
                  {precoVida > 0 && (
                    <div className="rounded-md border bg-muted/30 px-3 py-3 space-y-2">
                      <p className="text-sm font-medium">Adicionar vidas extras</p>
                      <p className="text-xs text-muted-foreground">
                        R$ {centsToReais(precoVida)} por vida / mês, acima do teto do plano.
                      </p>
                      {vidasAddon && (
                        <p className="text-xs text-emerald-700">
                          Você já tem {vidasAddon.quantity} vida(s) extra(s) contratada(s). Uma nova
                          contratação substitui a atual.
                        </p>
                      )}
                      <div className="flex items-center gap-2">
                        <Input
                          type="number"
                          min={1}
                          inputMode="numeric"
                          className="w-24"
                          placeholder="Qtd"
                          value={vidasQtd}
                          onChange={(e) => setVidasQtd(e.target.value)}
                        />
                        <Button size="sm" disabled={isMutating} onClick={contratarVidas}>
                          {isMutating ? (
                            <Loader2 className="w-4 h-4 mr-1 animate-spin" />
                          ) : (
                            <Plus className="w-4 h-4 mr-1" />
                          )}
                          Contratar
                        </Button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </CardContent>
          </Card>

          {/* Módulos: disponíveis × bloqueados */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Check className="w-4 h-4" /> Módulos do seu plano
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {disponiveis.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Incluídos ({disponiveis.length})
                  </p>
                  {disponiveis.map((m) => (
                    <div key={m.key} className="flex items-center gap-2 text-sm">
                      <Check className="w-4 h-4 text-emerald-600 flex-shrink-0" />
                      <span>{m.name}</span>
                    </div>
                  ))}
                </div>
              )}

              {bloqueados.length > 0 && (
                <>
                  {disponiveis.length > 0 && <Separator />}
                  <div className="space-y-2">
                    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Disponíveis para contratar ({bloqueados.length})
                    </p>
                    {bloqueados.map((m) => {
                      const planoDoModulo = FEATURE_PLAN_NAME[m.key];
                      const preco = precos[m.key] ?? 0;
                      return (
                        <div key={m.key} className="flex items-center gap-2 text-sm">
                          <Lock className="w-4 h-4 flex-shrink-0 opacity-60 text-muted-foreground" />
                          <span className="flex-1 text-muted-foreground">{m.name}</span>
                          {preco > 0 ? (
                            <Button
                              size="sm"
                              variant="outline"
                              disabled={isMutating}
                              onClick={() => doContratar(m.key)}
                            >
                              {isMutating ? (
                                <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" />
                              ) : (
                                <Plus className="w-3.5 h-3.5 mr-1" />
                              )}
                              Contratar (R$ {centsToReais(preco)}/mês)
                            </Button>
                          ) : (
                            planoDoModulo && (
                              <Badge variant="outline" className="text-[11px] font-normal">
                                {planoDoModulo}
                              </Badge>
                            )
                          )}
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <p className="text-xs text-muted-foreground text-center px-4">
            Módulos e vidas extras podem ser contratados aqui, na hora. Para mudar de plano, fale com o suporte.
          </p>
        </>
      )}
    </div>
  );
}
