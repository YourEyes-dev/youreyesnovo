import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatarDataBR, formatarHoras, type ImpactoEc141 } from "@/hooks/usePontoEc141";

/**
 * Tabela do impacto da EC 141/2026 (somente leitura), por empresa e escala.
 * Usada no Ponto (cliente, só com marco ativo) e na prévia do SuperAdmin.
 * Sem dado pessoal: só nomes de empresa/escala e contagens.
 */
export function Ec141ImpactoTabela({ impacto, mostrarSemColaborador = false }: { impacto: ImpactoEc141; mostrarSemColaborador?: boolean }) {
  const linhas = (impacto.linhas || []).filter(
    (l) => mostrarSemColaborador || l.colaboradores > 0 || l.agendamento,
  );
  const t = impacto.totais;
  return (
    <div className="space-y-3">
      {t && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
          <div className="rounded-md border p-2">
            <div className="text-xs text-muted-foreground">Escalas acima do teto</div>
            <div className="text-lg font-semibold">{t.escalas_acima_teto}</div>
            <div className="text-xs text-muted-foreground">{t.colaboradores_acima_teto} colaborador(es)</div>
          </div>
          <div className="rounded-md border p-2">
            <div className="text-xs text-muted-foreground">6 dias/semana sem CCT/ACT</div>
            <div className="text-lg font-semibold">{t.escalas_6dias_sem_coletivo}</div>
            <div className="text-xs text-muted-foreground">{t.colaboradores_6dias_sem_coletivo} colaborador(es)</div>
          </div>
          <div className="rounded-md border p-2">
            <div className="text-xs text-muted-foreground">Já agendadas</div>
            <div className="text-lg font-semibold">{t.escalas_com_agendamento}</div>
          </div>
          <div className="rounded-md border p-2">
            <div className="text-xs text-muted-foreground">Escalas ativas</div>
            <div className="text-lg font-semibold">{t.escalas}</div>
          </div>
        </div>
      )}
      {linhas.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhuma escala com colaborador atribuído.</p>
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Empresa</TableHead>
                <TableHead>Escala</TableHead>
                <TableHead className="text-right">Colaboradores</TableHead>
                <TableHead className="text-right">Carga atual</TableHead>
                <TableHead className="text-right">Teto</TableHead>
                <TableHead>Situação</TableHead>
                <TableHead>Agendamento</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {linhas.map((l) => (
                <TableRow key={l.escala_id}>
                  <TableCell className="text-sm">{l.empresa_nome}</TableCell>
                  <TableCell className="text-sm font-medium">{l.escala_nome}</TableCell>
                  <TableCell className="text-right tabular-nums">{l.colaboradores}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatarHoras(l.carga_semanal_atual_min)}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatarHoras(l.teto_semanal_min)}</TableCell>
                  <TableCell>
                    <div className="flex flex-wrap gap-1">
                      {l.acima_do_teto && <Badge variant="outline" className="border-red-300 text-red-700">Acima do teto</Badge>}
                      {l.seis_dias_sem_coletivo && <Badge variant="outline" className="border-amber-400 text-amber-800">6 dias sem CCT/ACT</Badge>}
                      {!l.acima_do_teto && !l.seis_dias_sem_coletivo && <Badge variant="outline" className="border-emerald-400 text-emerald-700">Dentro</Badge>}
                    </div>
                  </TableCell>
                  <TableCell className="text-sm">
                    {l.agendamento
                      ? `${formatarHoras(l.agendamento.nova_carga_semanal_min)} a partir de ${formatarDataBR(l.agendamento.vigente_a_partir_de)}`
                      : "—"}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}
