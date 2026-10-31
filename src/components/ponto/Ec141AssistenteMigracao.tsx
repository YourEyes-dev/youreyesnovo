import { useMemo, useState } from "react";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AlertTriangle, Info, Loader2 } from "lucide-react";
import {
  usePreviaMigracaoEc141,
  useAplicarMigracaoEc141,
  formatarDataBR,
  formatarHoras,
  type DestinoColaborador,
  type DestinoEc141,
  type LinhaMigracao,
} from "@/hooks/usePontoEc141";

/**
 * Assistente "Migrar para 42h/40h" (EC 141/2026 — entrega F2a).
 *
 * Só é aberto quando o SuperAdmin ativou um marco da emenda. O RH escolhe o
 * destino da empresa (42h ou 40h) e, se quiser, uma exceção por colaborador;
 * vê a prévia (escala atual -> proposta, carga antes/depois, se há CCT/ACT, a
 * recomendação e os avisos) e confirma. A gravação usa "vale a partir de" =
 * data do marco: nada antes dessa data muda. Sem CCT/ACT o sistema recomenda
 * 40h direto; 8h24/dia só com a confirmação abaixo (EC 141/2026, art. 7º).
 */
const STATUS_LBL: Record<LinhaMigracao["status"], string> = {
  migrar: "Será migrado",
  ja_conforme: "Já dentro do limite",
  ja_migrado: "Já migrado",
  fora_do_assistente: "Ajuste manual",
  nao_migrar: "Não migrar",
  conflito: "Agendamento existente",
};

export function Ec141AssistenteMigracao({ aberto, onFechar, teto }: {
  aberto: boolean;
  onFechar: () => void;
  teto: { codigo: string; teto_semanal_min: number; vigencia_inicio: string };
}) {
  const so40 = teto.teto_semanal_min < 2520;
  const [destino, setDestino] = useState<DestinoEc141>("40");
  const [excecoes, setExcecoes] = useState<Record<string, DestinoColaborador>>({});
  const [ciente, setCiente] = useState(false);
  const { data: previa, isFetching } = usePreviaMigracaoEc141(destino, excecoes, aberto);
  const aplicar = useAplicarMigracaoEc141();

  const linhas = previa?.linhas || [];
  const aMigrar = useMemo(() => linhas.filter((l) => l.status === "migrar"), [linhas]);
  const precisaCiencia = aMigrar.some((l) => l.requer_confirmacao_8h24);
  const gravaveis = aMigrar.filter((l) => !l.requer_confirmacao_8h24 || ciente).length;

  const mudarExcecao = (chave: string, v: string) => {
    setExcecoes((e) => {
      const n = { ...e };
      if (v === "padrao") delete n[chave];
      else n[chave] = v as DestinoColaborador;
      return n;
    });
  };

  const confirmar = async () => {
    await aplicar.mutateAsync({ destino, excecoes, confirmar8h24: ciente });
    setCiente(false);
    onFechar();
  };

  return (
    <Dialog open={aberto} onOpenChange={(v) => !v && onFechar()}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto" data-testid="ec141-assistente">
        <DialogHeader>
          <DialogTitle>Migrar escalas para a nova jornada (EC 141/2026)</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 text-sm">
          <div className="rounded-md border border-blue-200 bg-blue-50 p-3 text-blue-900 dark:bg-blue-950/30 dark:text-blue-100">
            As novas escalas valem a partir de <strong>{formatarDataBR(teto.vigencia_inicio)}</strong>. Até a véspera, nada muda
            (horários, jornada e apuração continuam como hoje). Sem redução de salário (EC 141/2026, art. 2º; CLT art. 468):
            cada colaborador migrado recebe um aditivo para assinatura eletrônica. Você pode cancelar a migração até a data.
          </div>

          <div className="flex flex-wrap items-center gap-4">
            <Label className="font-medium">Destino da empresa:</Label>
            <div className="flex gap-2">
              <Button size="sm" variant={destino === "40" ? "default" : "outline"} onClick={() => setDestino("40")}>
                40h (5 dias de 8h) — recomendado
              </Button>
              <Button size="sm" variant={destino === "42" ? "default" : "outline"} disabled={so40} onClick={() => setDestino("42")}
                title={so40 ? "O limite ativo é 40h" : "42h em 5 dias = 8h24 por dia"}>
                42h (5 dias de 8h24)
              </Button>
            </div>
            {isFetching && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />}
          </div>
          {destino === "42" && (
            <p className="text-xs text-amber-800">
              42h em 5 dias exige 8h24 por dia. Na transição, jornada diária acima de 8 horas depende de negociação coletiva
              (EC 141/2026, art. 7º): para quem não tem convenção ou acordo coletivo vigente, recomendamos 40h.
            </p>
          )}

          {previa && !previa.ok && <p className="text-destructive">{previa.mensagem || "Não foi possível montar a prévia."}</p>}
          {previa?.mensagem && previa.ok && <p className="text-amber-800">{previa.mensagem}</p>}

          {previa?.totais && (
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">{previa.totais.colaboradores} colaborador(es)</Badge>
              <Badge className="bg-blue-100 text-blue-900">{previa.totais.migrar} a migrar</Badge>
              <Badge variant="outline">{previa.totais.ja_conforme} já no limite</Badge>
              <Badge variant="outline">{previa.totais.ja_migrado} já migrado(s)</Badge>
              {previa.totais.fora_do_assistente > 0 && <Badge variant="outline">{previa.totais.fora_do_assistente} ajuste manual</Badge>}
              <Badge variant="outline">{previa.totais.sem_coletivo} sem CCT/ACT</Badge>
            </div>
          )}

          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Escala atual</TableHead>
                <TableHead>Proposta a partir de {formatarDataBR(teto.vigencia_inicio).slice(0, 5)}</TableHead>
                <TableHead>CCT/ACT?</TableHead>
                <TableHead>Recomendação</TableHead>
                <TableHead>Destino</TableHead>
                <TableHead>Situação e avisos</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {linhas.length === 0 && (
                <TableRow><TableCell colSpan={7} className="text-center text-muted-foreground py-6">Nenhum colaborador com escala nesta empresa.</TableCell></TableRow>
              )}
              {linhas.map((l) => (
                <TableRow key={l.chave} data-testid="ec141-linha">
                  <TableCell className="font-medium">{l.colaborador_nome || "-"}</TableCell>
                  <TableCell>
                    <div className="text-xs text-muted-foreground">{l.escala_nome}</div>
                    <div className="text-xs">{l.jornada_atual}</div>
                    <div className="font-medium">{formatarHoras(l.carga_antes_min)}/semana</div>
                  </TableCell>
                  <TableCell>
                    {l.status === "migrar" ? (
                      <>
                        <div className="text-xs">{l.jornada_nova}</div>
                        <div className="font-medium text-blue-800">{formatarHoras(l.carga_depois_min)}/semana</div>
                        {l.modo === "nova_escala" && <div className="text-[11px] text-muted-foreground">em escala nova (colegas com destino diferente)</div>}
                      </>
                    ) : <span className="text-muted-foreground">—</span>}
                  </TableCell>
                  <TableCell>{l.tem_coletivo ? <span>Sim{l.instrumento_nome ? ` (${l.instrumento_nome})` : ""}</span> : <span className="text-amber-800">Não</span>}</TableCell>
                  <TableCell>{l.recomendacao}h</TableCell>
                  <TableCell>
                    <Select value={excecoes[l.chave] || "padrao"} onValueChange={(v) => mudarExcecao(l.chave, v)}>
                      <SelectTrigger className="h-8 w-[130px]"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="padrao">Padrão ({destino}h)</SelectItem>
                        <SelectItem value="40">40h</SelectItem>
                        {!so40 && <SelectItem value="42">42h</SelectItem>}
                        <SelectItem value="manter">Não migrar</SelectItem>
                      </SelectContent>
                    </Select>
                  </TableCell>
                  <TableCell className="space-y-1 max-w-[320px]">
                    <Badge variant="outline">{STATUS_LBL[l.status] || l.status}</Badge>
                    {l.avisos.map((a, i) => (
                      <div key={i} className={`flex gap-1 text-xs ${a.nivel === "forte" ? "text-red-700 font-medium" : a.nivel === "alerta" ? "text-amber-800" : "text-muted-foreground"}`}>
                        {a.nivel === "forte" || a.nivel === "alerta" ? <AlertTriangle className="h-3 w-3 mt-0.5 shrink-0" /> : <Info className="h-3 w-3 mt-0.5 shrink-0" />}
                        <span>{a.mensagem}</span>
                      </div>
                    ))}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>

          {precisaCiencia && (
            <label className="flex items-start gap-2 rounded-md border border-red-300 bg-red-50 p-3 text-red-900 dark:bg-red-950/30 dark:text-red-100">
              <Checkbox checked={ciente} onCheckedChange={(v) => setCiente(v === true)} className="mt-0.5" data-testid="ec141-ciente-8h24" />
              <span>
                Estou ciente de que {aMigrar.filter((l) => l.requer_confirmacao_8h24).length} colaborador(es) sem convenção ou acordo
                coletivo vigente ficarão com jornada acima de 8h por dia (8h24). Na transição, isso depende de negociação coletiva
                (EC 141/2026, art. 7º). Sem esta confirmação, eles não serão migrados — escolha 40h para eles.
              </span>
            </label>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onFechar}>Fechar</Button>
          <Button
            onClick={confirmar}
            disabled={aplicar.isPending || !previa?.pode_aplicar || gravaveis === 0}
            data-testid="ec141-confirmar-migracao"
          >
            {aplicar.isPending && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
            Confirmar migração de {gravaveis} colaborador(es)
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
