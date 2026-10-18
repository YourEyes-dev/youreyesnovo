import { useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, Target } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { CriarAcaoAlertaModal } from "@/components/shared/CriarAcaoAlertaModal";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { calcularCobertura, montarAlertas, type AlertaCultura } from "@/lib/celebracoes";
import type { CulturaAcao } from "@/types/cultura";

interface Props {
  acoes: CulturaAcao[];
}

/** Medir → agir: o alerta abre a sugestão de ação do Plano de Ação (a IA propõe, a pessoa escolhe). */
export const AlertasCultura = ({ acoes }: Props) => {
  const { pessoas, config } = useCelebracoes({ exigirEmpresa: true });
  const [aberto, setAberto] = useState<AlertaCultura | null>(null);
  const meta = config?.meta_cobertura ?? 95;

  const alertas = useMemo(
    () => montarAlertas({ acoes, cobertura: calcularCobertura(pessoas, acoes), metaCobertura: meta }),
    [acoes, pessoas, meta],
  );

  return (
    <Card data-testid="alertas-cultura">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-primary" strokeWidth={1.75} /> Alertas
        </CardTitle>
      </CardHeader>
      <CardContent>
        {alertas.length === 0 ? (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="h-4 w-4 text-emerald-600" /> Nenhum alerta: celebrações em dia e cobertura dentro da meta.
          </p>
        ) : (
          <div className="space-y-2">
            {alertas.map((a) => (
              <div key={a.id} className="flex items-center gap-3 p-2 rounded-lg border bg-amber-500/5 border-amber-500/20">
                {a.id === "cobertura" ? <Target className="h-4 w-4 text-amber-600 shrink-0" /> : <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0" />}
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium">{a.titulo}</p>
                  <p className="text-xs text-muted-foreground">{a.descricao}</p>
                </div>
                <Button size="sm" variant="outline" className="h-8 shrink-0" onClick={() => setAberto(a)}>
                  Criar ação no Plano de Ação
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>
      {aberto && (
        <CriarAcaoAlertaModal
          open
          onOpenChange={(o) => !o && setAberto(null)}
          alertaTitulo={aberto.titulo}
          alertaDescricao={aberto.descricao}
          origemModulo="cultura"
          contextoExtra="Módulo Cultura & Celebrações. Reconhecimento e celebração de colaboradores; sem avaliar desempenho individual."
        />
      )}
    </Card>
  );
};
