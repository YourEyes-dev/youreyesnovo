import { useEffect, useState } from "react";
import { usePrecosAddons, type AddonPreco } from "@/hooks/usePrecosAddons";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Separator } from "@/components/ui/separator";
import { toast } from "sonner";
import { Users, Package, Save, Info, Loader2 } from "lucide-react";

function centsToReais(cents: number): string {
  return (cents / 100).toFixed(2).replace(".", ",");
}
function reaisToCents(str: string): number {
  const limpo = (str || "").trim().replace(/\s/g, "").replace(/\./g, "").replace(",", ".");
  const n = parseFloat(limpo);
  return Number.isFinite(n) ? Math.max(Math.round(n * 100), 0) : 0;
}

// Definido fora do componente pai: se ficar aninhado, o React recria o campo
// a cada tecla, ele perde o foco e só aceita um dígito.
function PrecoInput({
  value,
  onChange,
  sufixo,
}: {
  value: string;
  onChange: (v: string) => void;
  sufixo: string;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-sm text-muted-foreground">R$</span>
      <Input
        inputMode="decimal"
        className="w-28 text-right"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="0,00"
      />
      <span className="text-xs text-muted-foreground whitespace-nowrap">{sufixo}</span>
    </div>
  );
}

export function PrecosAddonsPanel() {
  const { itens, isLoading, isError, setPreco, isSaving } = usePrecosAddons();
  const [values, setValues] = useState<Record<string, string>>({});

  useEffect(() => {
    const init: Record<string, string> = {};
    for (const it of itens) init[it.key] = centsToReais(it.unit_price_cents);
    setValues(init);
  }, [itens]);

  const vida = itens.find((i) => i.kind === "life");
  const modulos = itens.filter((i) => i.kind === "module");

  const salvar = async () => {
    const mudados = itens.filter(
      (it) => reaisToCents(values[it.key] ?? "") !== it.unit_price_cents
    );
    if (mudados.length === 0) {
      toast.info("Nenhuma alteração para salvar.");
      return;
    }
    try {
      for (const it of mudados) {
        await setPreco({ featureKey: it.key, cents: reaisToCents(values[it.key] ?? "") });
      }
      toast.success(`${mudados.length} preço(s) atualizado(s).`);
    } catch (e: any) {
      toast.error(e.message || "Erro ao salvar os preços");
    }
  };

  const setValor = (key: string, v: string) => setValues((prev) => ({ ...prev, [key]: v }));

  return (
    <div className="space-y-4 max-w-3xl">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold">Preços dos add-ons</h2>
          <p className="text-sm text-muted-foreground">
            Quanto custa cada item que a empresa pode contratar por conta própria na tela "Meu Plano".
          </p>
        </div>
        <Button onClick={salvar} disabled={isSaving || isLoading}>
          {isSaving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Save className="w-4 h-4 mr-2" />}
          Salvar preços
        </Button>
      </div>

      <div className="flex items-start gap-2 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm">
        <Info className="w-4 h-4 text-blue-600 mt-0.5 shrink-0" />
        <p className="text-blue-800 text-xs">
          Preço <strong>0,00</strong> = item não fica disponível para contratação. Os valores são
          mensais. A cobrança em si é conciliada pelo financeiro (não há cobrança automática ainda).
        </p>
      </div>

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      ) : isError || itens.length === 0 ? (
        <Card>
          <CardContent className="py-8 text-center text-sm text-muted-foreground">
            <Info className="w-5 h-5 mx-auto mb-2 opacity-60" />
            Não foi possível carregar os itens neste ambiente. Confirme que o script de banco dos
            add-ons (<code>script_addon_prices.sql</code>) foi aplicado aqui.
          </CardContent>
        </Card>
      ) : (
        <>
          {/* Vida extra */}
          {vida && (
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-base flex items-center gap-2">
                  <Users className="w-4 h-4" /> Vida extra
                </CardTitle>
              </CardHeader>
              <CardContent className="flex items-center justify-between">
                <p className="text-sm text-muted-foreground">
                  Preço por colaborador acima do teto do plano.
                </p>
                <PrecoInput
                  value={values[vida.key] ?? ""}
                  onChange={(v) => setValor(vida.key, v)}
                  sufixo="/ vida / mês"
                />
              </CardContent>
            </Card>
          )}

          {/* Módulos avulsos */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Package className="w-4 h-4" /> Módulos avulsos
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {modulos.map((m, i) => (
                <div key={m.key}>
                  {i > 0 && <Separator className="my-2" />}
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{m.name}</p>
                      {m.category && (
                        <Badge variant="outline" className="mt-0.5 text-[11px] font-normal capitalize">
                          {m.category}
                        </Badge>
                      )}
                    </div>
                    <PrecoInput
                      value={values[m.key] ?? ""}
                      onChange={(v) => setValor(m.key, v)}
                      sufixo="/ mês"
                    />
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
