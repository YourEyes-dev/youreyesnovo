import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Scale, ChevronDown, ChevronUp } from "lucide-react";
import { useImpactoEc141, formatarDataBR, formatarHoras } from "@/hooks/usePontoEc141";
import { Ec141ImpactoTabela } from "./Ec141ImpactoTabela";

/**
 * Aviso + painel de impacto da EC 141/2026 na tela de escalas.
 *
 * Só aparece quando o SuperAdmin YourEyes ATIVA um marco da emenda (42h ou
 * 40h) — enquanto a lei não for ativada, este componente não desenha nada.
 * É somente leitura: a migração das escalas é feita pelo RH, editando a
 * escala com "vale a partir de" (o assistente fica para a entrega F2).
 */
export function PontoEc141Painel() {
  const { data: impacto } = useImpactoEc141();
  const [aberto, setAberto] = useState(false);

  if (!impacto?.visivel || !impacto.marco) return null;
  const m = impacto.marco;
  const t = impacto.totais;
  const pendencias = (t?.escalas_acima_teto || 0) + (t?.escalas_6dias_sem_coletivo || 0);

  return (
    <Card className="border-blue-300" data-testid="ponto-ec141-painel">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Scale className="w-4 h-4 text-blue-700" />
          Redução da jornada (EC 141/2026): {formatarHoras(m.teto_semanal_min)} semanais a partir de {formatarDataBR(m.vigencia_inicio)}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <p className="text-muted-foreground">
          A partir dessa data o limite passa a ser {formatarHoras(m.teto_semanal_min)} por semana, com {m.repousos_semana} repousos
          semanais (6 dias por semana só com convenção ou acordo coletivo). Sem redução de salário.
          {pendencias > 0
            ? ` Há ${t?.escalas_acima_teto || 0} escala(s) acima do novo teto (${t?.colaboradores_acima_teto || 0} colaborador(es)) e ${t?.escalas_6dias_sem_coletivo || 0} escala(s) de 6 dias sem instrumento coletivo.`
            : " Suas escalas já estão dentro do novo limite."}
          {" "}Para ajustar, edite a escala e escolha "A partir de uma data". Nada é alterado automaticamente.
        </p>
        <Button size="sm" variant="outline" onClick={() => setAberto(!aberto)}>
          {aberto ? <ChevronUp className="w-4 h-4 mr-1" /> : <ChevronDown className="w-4 h-4 mr-1" />}
          {aberto ? "Ocultar detalhes" : "Ver escalas afetadas"}
        </Button>
        {aberto && <Ec141ImpactoTabela impacto={impacto} />}
      </CardContent>
    </Card>
  );
}
