import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { ShieldAlert, ArrowRight } from "lucide-react";
import { ChecklistDeteccaoObservavel } from "./ChecklistDeteccaoObservavel";

/**
 * Visão Psicossocial "básica" — a que fica disponível já no NR-1 (Starter).
 *
 * Mostra os SINAIS observáveis (Radar, a partir dos dados que a empresa já
 * tem) + orientação da NR-1, sem liberar o que MEDE e DOCUMENTA (campanhas
 * com instrumento validado, IPS, PGR), que é o módulo Psicossocial completo
 * (Essential). Serve de "básico honesto" e gancho de upsell.
 */
export function PsicossocialVisaoBasica() {
  return (
    <div className="space-y-4">
      <Card className="border-violet-200 bg-violet-50/40">
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <ShieldAlert className="h-5 w-5 text-violet-600" />
            Visão Psicossocial — NR-1
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3 text-sm text-muted-foreground">
          <p>
            A NR-1 exige que o <strong>risco psicossocial</strong> faça parte do
            inventário de riscos (GRO/PGR). Esta visão mostra{" "}
            <strong>sinais observáveis</strong>, calculados a partir dos dados
            que a empresa já tem — um primeiro alerta de que há risco a
            investigar.
          </p>
          <p>
            Para <strong>medir</strong> o risco com instrumento validado
            (COPSOQ, HSE, PROART, SIPRO) e <strong>gerar o PGR</strong> com plano
            de ação, ative o módulo completo de Psicossocial.
          </p>
          <Button asChild size="sm" variant="outline" className="gap-1.5">
            <Link to="/meu-plano">
              Ativar Psicossocial completo <ArrowRight className="h-4 w-4" />
            </Link>
          </Button>
        </CardContent>
      </Card>

      <ChecklistDeteccaoObservavel />
    </div>
  );
}
