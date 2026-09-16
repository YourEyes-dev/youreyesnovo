import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { useTenant } from "@/hooks/useTenant";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { AlertTriangle, CalendarX } from "lucide-react";
import { format } from "date-fns";

/**
 * Avisos das escalas — o que o banco já sabia e ninguém via:
 *
 *  · Formalização (ESC-001 / ESC-031): a 12x36 depende de acordo individual
 *    escrito, ACT ou CCT (CLT art. 59-A); o revezamento acima de 6h depende de
 *    instrumento COLETIVO (CF art. 7º, XIV — acordo individual não serve).
 *    Sem isso, o sistema apura direitinho uma escala juridicamente frágil.
 *  · Cobertura (ESC-021): turno previsto em que TODOS os atribuídos estão
 *    indisponíveis (férias, afastamento, desligamento) — precisa aparecer
 *    antes do dia, não com o posto vazio.
 */
export function PontoEscalaAvisos({ escalas }: { escalas: Array<{ id: string; nome: string; ativa?: boolean }> }) {
  const { tenantId } = useTenant();
  const { empresaAtivaId } = useEmpresaAtiva();

  const idsAtivas = escalas.filter((e) => e.ativa !== false).map((e) => e.id);

  // Status de formalização por escala — a regra vive no banco, não aqui.
  const { data: pendencias = [] } = useQuery({
    queryKey: ["ponto-escala-formalizacao", tenantId, idsAtivas.join(",")],
    queryFn: async () => {
      if (!tenantId || idsAtivas.length === 0) return [];
      const resultados = await Promise.all(
        idsAtivas.map(async (id) => {
          const { data, error } = await (supabase.rpc as any)("ponto_escala_formalizacao_status", {
            p_escala_id: id,
          });
          if (error) return null;
          return { id, status: data as string };
        }),
      );
      return resultados.filter((r): r is { id: string; status: string } => !!r && r.status === "pendente");
    },
    enabled: !!tenantId && idsAtivas.length > 0,
  });

  const { data: descobertos = [] } = useQuery({
    queryKey: ["ponto-escala-cobertura", tenantId, empresaAtivaId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await (supabase.rpc as any)("ponto_escala_cobertura_listar", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_dias_a_frente: 14,
      });
      if (error) throw error;
      return (data || []) as Array<{ escala_nome: string; data_descoberta: string; motivo: string }>;
    },
    enabled: !!tenantId,
  });

  const nomeEscala = (id: string) => escalas.find((e) => e.id === id)?.nome || "escala";

  if (pendencias.length === 0 && descobertos.length === 0) return null;

  return (
    <div className="space-y-4">
      {pendencias.length > 0 && (
        <Card className="border-amber-300">
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2 text-amber-800">
              <AlertTriangle className="w-5 h-5" />
              Escala sem o acordo que a lei exige ({pendencias.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex flex-wrap gap-2">
              {pendencias.map((p) => (
                <Badge key={p.id} variant="outline" className="border-amber-400 text-amber-900">
                  {nomeEscala(p.id)}
                </Badge>
              ))}
            </div>
            <p className="text-muted-foreground">
              A escala 12x36 só vale com acordo individual escrito, ACT ou CCT (CLT art. 59-A), e o
              turno de revezamento acima de 6 horas só com instrumento <strong>coletivo</strong>
              {" "}(CF art. 7º, XIV — acordo individual não serve). Anexe o documento na escala ou
              cadastre o acordo coletivo vigente em Compliance › Acordos; o aviso some sozinho
              depois disso. A apuração continua funcionando normalmente — o risco é jurídico.
            </p>
          </CardContent>
        </Card>
      )}

      {descobertos.length > 0 && (
        <Card className="border-destructive/40">
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <CalendarX className="w-5 h-5 text-destructive" />
              Turnos a descoberto nos próximos 14 dias ({descobertos.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="max-h-64 overflow-y-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Escala</TableHead>
                    <TableHead className="text-center">Dia</TableHead>
                    <TableHead>Por quê</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {descobertos.map((d, i) => (
                    <TableRow key={`${d.escala_nome}-${d.data_descoberta}-${i}`}>
                      <TableCell className="font-medium">{d.escala_nome}</TableCell>
                      <TableCell className="text-center">
                        {d.data_descoberta
                          ? format(new Date(`${d.data_descoberta}T00:00:00`), "dd/MM/yyyy")
                          : "—"}
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">{d.motivo || "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
