import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { PiggyBank, RefreshCw, Scale } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useDecimoTerceiroContabil, type Conciliacao13 } from "@/hooks/useDecimoTerceiro";
import { toast } from "sonner";
import { useFolhaCalculo } from "@/hooks/useFolhaCalculo";
import { format } from "date-fns";

const fmtMoeda = (v: number) => (v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2 });

export function ProvisoesTab() {
  const { useProvisoes } = useFolhaCalculo();
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const { data: provisoes = [], isLoading, refetch } = useProvisoes(competencia);
  const { provisionar, conciliar, ocupado } = useDecimoTerceiroContabil();
  const [conc, setConc] = useState<Conciliacao13 | null>(null);

  // A provisão do 13º nasce 1/12 por mês (regime de competência). Até
  // aqui era lançada à mão, quando alguém lembrava.
  const rodarProvisao = async () => {
    try {
      const r = await provisionar(competencia);
      if (!r) return;
      await refetch();
      toast.success(
        `${r.provisionados} colaborador(es) provisionado(s) em ${r.competencia}` +
        (r.revertidos > 0 ? `; ${r.revertidos} provisão(ões) revertida(s) por desligamento` : "") +
        `. Total R$ ${fmtMoeda(r.total_provisionado)}.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível provisionar");
    }
  };

  const rodarConciliacao = async () => {
    try {
      const r = await conciliar(Number(competencia.slice(0, 4)));
      setConc(r);
      if (r) toast.info(`Conciliação ${r.ano}: ${r.situacao}.`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Não foi possível conciliar");
    }
  };

  const pFerias = provisoes.filter((p: any) => p.tipo === "ferias");
  const p13 = provisoes.filter((p: any) => p.tipo === "13_salario");

  const totalFerias = pFerias.reduce((s: number, p: any) => s + (p.valor_total || 0), 0);
  const total13 = p13.reduce((s: number, p: any) => s + (p.valor_total || 0), 0);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <PiggyBank className="w-5 h-5 text-primary" /> Provisões
          </h3>
          <p className="text-sm text-muted-foreground">Provisões mensais de férias e 13º salário</p>
        </div>
        <div className="flex items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs">Competência</Label>
            <CompetenciaInput value={competencia} onChange={setCompetencia} className="w-40" />
          </div>
          <Button variant="outline" onClick={rodarProvisao} disabled={ocupado}>
            <RefreshCw className="w-4 h-4 mr-2" />
            {ocupado ? "Processando..." : "Provisionar 13º"}
          </Button>
          <Button variant="outline" onClick={rodarConciliacao}>
            <Scale className="w-4 h-4 mr-2" /> Conciliar ano
          </Button>
        </div>
      </div>

      {conc && (
        <Card className="border-l-4 border-l-blue-500">
          <CardContent className="p-4 space-y-1">
            <p className="text-sm font-medium">
              Conciliação do 13º de {conc.ano}: {conc.situacao}
            </p>
            <div className="grid grid-cols-3 gap-4 text-sm">
              <div><span className="text-muted-foreground">Provisionado:</span> R$ {fmtMoeda(conc.provisionado)}</div>
              <div><span className="text-muted-foreground">Pago:</span> R$ {fmtMoeda(conc.pago)}</div>
              <div><span className="text-muted-foreground">Diferença:</span> R$ {fmtMoeda(conc.diferenca)}</div>
            </div>
            <p className="text-xs text-muted-foreground">
              O custo do 13º nasce 1/12 por mês. Diferença grande no fim do ano costuma ser
              mês sem provisionar — rode a provisão das competências que faltam.
            </p>
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="border-l-4 border-l-amber-500">
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Provisão Férias</p>
            <p className="text-2xl font-bold">R$ {fmtMoeda(totalFerias)}</p>
            <p className="text-xs text-muted-foreground">{pFerias.length} colaboradores</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-emerald-500">
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Provisão 13º</p>
            <p className="text-2xl font-bold">R$ {fmtMoeda(total13)}</p>
            <p className="text-xs text-muted-foreground">{p13.length} colaboradores</p>
          </CardContent>
        </Card>
        <Card className="border-l-4 border-l-primary">
          <CardContent className="p-4">
            <p className="text-sm text-muted-foreground">Total Provisões</p>
            <p className="text-2xl font-bold">R$ {fmtMoeda(totalFerias + total13)}</p>
          </CardContent>
        </Card>
      </div>

      {/* Tabela de Férias */}
      <Card>
        <CardHeader><CardTitle className="text-base">Provisão de Férias — {competencia}</CardTitle></CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-right">Provisão</TableHead>
                <TableHead className="text-right">1/3</TableHead>
                <TableHead className="text-right">FGTS</TableHead>
                <TableHead className="text-right">Total</TableHead>
                <TableHead className="text-center">Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={6} className="text-center py-6 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : pFerias.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-6 text-muted-foreground">Nenhuma provisão de férias para esta competência.</TableCell></TableRow>
              ) : pFerias.map((p: any) => (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.colaborador_nome}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(p.valor_provisao)}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(p.valor_terco)}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(p.encargos_fgts)}</TableCell>
                  <TableCell className="text-right font-bold">R$ {fmtMoeda(p.valor_total)}</TableCell>
                  <TableCell className="text-center">
                    <Badge variant={p.revertida ? "secondary" : "default"} className="text-xs">
                      {p.revertida ? "Revertida" : "Ativa"}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Tabela de 13º */}
      <Card>
        <CardHeader><CardTitle className="text-base">Provisão de 13º Salário — {competencia}</CardTitle></CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-right">Provisão</TableHead>
                <TableHead className="text-right">FGTS</TableHead>
                <TableHead className="text-right">Total</TableHead>
                <TableHead className="text-center">Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={5} className="text-center py-6 text-muted-foreground">Carregando...</TableCell></TableRow>
              ) : p13.length === 0 ? (
                <TableRow><TableCell colSpan={5} className="text-center py-6 text-muted-foreground">Nenhuma provisão de 13º para esta competência.</TableCell></TableRow>
              ) : p13.map((p: any) => (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.colaborador_nome}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(p.valor_provisao)}</TableCell>
                  <TableCell className="text-right">R$ {fmtMoeda(p.encargos_fgts)}</TableCell>
                  <TableCell className="text-right font-bold">R$ {fmtMoeda(p.valor_total)}</TableCell>
                  <TableCell className="text-center">
                    <Badge variant={p.revertida ? "secondary" : "default"} className="text-xs">
                      {p.revertida ? "Revertida" : "Ativa"}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
